#!/usr/bin/env bash
# Project-local, pinned Linux x86_64 dependency preparation. Never starts RoomKit,
# edits databases, invokes sudo, or changes shell profiles/firewall/PATH.
# Archives are accepted only when their fixed SHA256 matches this source.
# Sources: https://github.com/godotengine/godot/releases/tag/4.7.2-stable
#          https://github.com/PowerShell/PowerShell/releases/tag/v7.6.6
# These are the already accepted RoomKit versions, not a latest-version lookup.
set -euo pipefail
fail() { echo "ROOMKIT_ENVIRONMENT_FAILED $*" >&2; exit 1; }
usage() {
  cat <<'EOF'
RoomKit Linux x86_64 environment
  bash PrepareEnvironment.sh check
  bash PrepareEnvironment.sh prepare
  bash PrepareEnvironment.sh prepare --offline --godot-archive /ABS/Godot_v4.7.2-stable_linux.x86_64.zip --pwsh-archive /ABS/powershell-7.6.6-linux-x64.tar.gz

check creates nothing and starts no service. prepare installs missing tested
tools under this project's artifacts/environment/tools; existing tools are
never replaced. The exported Linux package includes Godot, so omit its archive.
Without --offline, missing archives are downloaded from official GitHub Releases.
Missing system libraries are reported for you to install separately; no sudo.
After READY: source uses bash tools/roomkit_linux.sh start; exported package uses
bash CheckPackage.sh, then bash RoomKit.sh start. Preparation never starts these.
EOF
}
mode="${1:-check}"; [ $# -eq 0 ] || shift
case "$mode" in check|prepare) ;; -h|--help|help) usage; exit 0 ;; *) usage >&2; exit 64 ;; esac
godot_archive='' pwsh_archive='' offline=0
seen='|'
while [ $# -gt 0 ]; do
  option="$1"; shift
  case "$seen" in *"|$option|"*) echo "ROOMKIT_ENVIRONMENT_FAILED duplicate option $option" >&2; exit 64 ;; esac
  seen="$seen$option|"
  case "$option" in
    --offline) offline=1 ;;
    --godot-archive|--pwsh-archive)
      [ $# -gt 0 ] && [ -n "$1" ] || { echo 'ROOMKIT_ENVIRONMENT_FAILED missing archive path' >&2; exit 64; }
      if [ "$option" = --godot-archive ]; then godot_archive="$1"; else pwsh_archive="$1"; fi
      shift ;;
    *) echo "ROOMKIT_ENVIRONMENT_FAILED unknown option $option" >&2; exit 64 ;;
  esac
done
[ "$mode" = prepare ] || { [ "$seen" = '|' ] || { echo 'ROOMKIT_ENVIRONMENT_FAILED check accepts no installation options' >&2; exit 64; }; }
[ "$(id -u)" -ne 0 ] || fail 'run as an ordinary user, not root'
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || fail 'only Linux x86_64 is supported by this preparation entry'
for tool in realpath dirname sha256sum ldd timeout awk grep sed find sort; do command -v "$tool" >/dev/null || fail "missing command $tool"; done
# Preserve the logical path until every ancestor has been checked for links.
root="$(realpath -ms -- "$(dirname "${BASH_SOURCE[0]}")/..")"
guard_path() {
  local value="$1" cursor
  [[ "$value" = /* && "$value" != *$'\n'* && "$value" != *$'\r'* && "/$value/" != */../* ]] || fail 'absolute paths without traversal are required'
  cursor="$value"
  while :; do
    [ ! -L "$cursor" ] || fail "linked path refused: $value"
    [ "$cursor" != / ] || break
    cursor="$(dirname -- "$cursor")"
  done
}
guard_path "$root"
[ -f "$root/project.godot" ] || fail 'not a RoomKit source checkout or exported package'
[ ! -L "$root/tools/runtime_paths.sh" ] || fail 'linked runtime path helper'
. "$root/tools/runtime_paths.sh"
rk_runtime_paths "$root"
[ -z "$godot_archive" ] || { guard_path "$godot_archive"; [ -f "$godot_archive" ] || fail 'Godot archive does not exist'; }
[ -z "$pwsh_archive" ] || { guard_path "$pwsh_archive"; [ -f "$pwsh_archive" ] || fail 'PowerShell archive does not exist'; }
if [ "$RK_EXPORTED" -eq 1 ] && [ -n "$godot_archive" ]; then fail 'the exported package includes Godot; no Godot archive is needed'; fi
tools_root="$root/artifacts/environment/tools"
godot_target="$tools_root/godot/4.7.2-stable"
pwsh_target="$tools_root/pwsh/7.6.6"
guard_path "$tools_root"
missing=0 need_godot=0 need_pwsh=0
require_system() {
  local command libraries
  for command in setsid pgrep mktemp; do
    if ! command -v "$command" >/dev/null; then echo "MISSING system-command=$command"; missing=1; fi
  done
  libraries="$(ldconfig -p 2>/dev/null || true)"
  for library in libsqlite3.so.0 libicuuc.so libssl.so; do
    if ! grep -F "$library" <<< "$libraries" >/dev/null; then echo "MISSING system-library=$library (install separately for your distribution)"; missing=1; fi
  done
}
check_binary() {
  local path="$1" expected="$2" version dependencies
  guard_path "$path"
  [ -f "$path" ] && [ -x "$path" ] || return 1
  dependencies="$(ldd "$path" 2>&1)" || fail "cannot inspect native executable $path"
  if grep -q 'not found' <<< "$dependencies"; then fail "missing native dependency for $path"; fi
  if [ "$expected" = godot ]; then
    version="$(timeout 15 "$path" --headless --version)" || fail 'cannot inspect Godot version'
    [ "$version" = 4.7.2.stable.official.ed1daf0bf ] || fail 'Godot must be the tested official 4.7.2 ed1daf0bf build'
  else
    # --version exits before loading profiles/scripts; diagnostic output is off.
    version="$(DOTNET_EnableDiagnostics=0 COMPlus_EnableDiagnostics=0 POWERSHELL_DIAGNOSTICS_OPTOUT=1 POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off timeout 15 "$path" --version)" || fail 'cannot inspect PowerShell version or its native libraries'
    [ "$version" = 'PowerShell 7.6.6' ] || fail 'PowerShell must be the tested 7.6.6 build'
  fi
  echo "FOUND $expected=$path"
}
require_system
if [ "$RK_EXPORTED" -eq 1 ]; then
  guard_path "$RK_GODOT"
  [ -f "$RK_GODOT" ] || fail 'the exported package is missing Operator.x86_64'
  echo 'FOUND godot=bundled (package integrity and identity: CheckPackage.sh)'
elif ! check_binary "$RK_GODOT" godot; then need_godot=1; echo 'MISSING godot=4.7.2.stable.official.ed1daf0bf'; fi
if ! check_binary "$RK_PWSH" pwsh; then need_pwsh=1; echo 'MISSING pwsh=7.6.6'; fi
if [ "$mode" = check ]; then
  if [ "$missing" -ne 0 ] || [ "$need_godot" -ne 0 ] || [ "$need_pwsh" -ne 0 ]; then echo 'ROOMKIT_ENVIRONMENT_INCOMPLETE'; exit 2; fi
  echo "ROOMKIT_ENVIRONMENT_READY kind=$([ "$RK_EXPORTED" -eq 1 ] && echo exported || echo source)"; exit 0
fi
[ "$missing" -eq 0 ] || fail 'system dependencies missing; no tools were installed'
if [ "$need_godot" -eq 0 ] && [ "$need_pwsh" -eq 0 ]; then echo 'ROOMKIT_ENVIRONMENT_READY existing-tools-preserved'; exit 0; fi
# An explicit override is user-owned. Do not silently replace it with local tools.
[ "$need_godot" -eq 0 ] || [ -z "${ROOMKIT_GODOT:-}" ] || fail 'ROOMKIT_GODOT points to a missing executable; correct or unset the override'
[ "$need_pwsh" -eq 0 ] || [ -z "${ROOMKIT_PWSH:-}" ] || fail 'ROOMKIT_PWSH points to a missing executable; correct or unset the override'
for command in mkdir chmod mktemp cp mv rm; do command -v "$command" >/dev/null || fail "missing preparation command $command"; done
if [ "$need_godot" -eq 1 ]; then command -v unzip >/dev/null || fail 'unzip is required to prepare the source engine'; fi
if [ "$need_pwsh" -eq 1 ]; then command -v tar >/dev/null || fail 'tar is required to prepare PowerShell'; fi
[ "$offline" -eq 1 ] || command -v curl >/dev/null || fail 'curl is required for downloads; use --offline with official archives'
if [ "$need_godot" -eq 1 ]; then guard_path "$godot_target"; [ ! -e "$godot_target" ] || fail 'existing Godot tool directory is incomplete; preserved for review'; [ "$offline" -eq 0 ] || [ -n "$godot_archive" ] || fail 'offline preparation needs --godot-archive'; fi
if [ "$need_pwsh" -eq 1 ]; then guard_path "$pwsh_target"; [ ! -e "$pwsh_target" ] || fail 'existing PowerShell tool directory is incomplete; preserved for review'; [ "$offline" -eq 0 ] || [ -n "$pwsh_archive" ] || fail 'offline preparation needs --pwsh-archive'; fi
umask 077
mkdir -p "$root/artifacts/environment"
guard_path "$root/artifacts/environment/.prepare-lock"
mkdir "$root/artifacts/environment/.prepare-lock" 2>/dev/null || fail 'preparation already running or an old lock requires review'
stage=''
cleanup() {
  if [ -n "$stage" ]; then
    case "$stage" in "$root"/artifacts/environment/.stage-*) guard_path "$stage"; rm -rf -- "$stage" ;; *) echo 'refused unexpected cleanup path' >&2 ;; esac
  fi
  rmdir -- "$root/artifacts/environment/.prepare-lock" 2>/dev/null || true
}
trap cleanup EXIT
stage="$(mktemp -d "$root/artifacts/environment/.stage-XXXXXXXX")"
fetch() {
  local supplied="$1" target="$2" url="$3" expected="$4" actual
  if [ -n "$supplied" ]; then cp -- "$supplied" "$target"
  else curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 900 --retry 2 --output "$target" "$url" || fail 'official download failed; use offline archives if GitHub is unreachable'; fi
  actual="$(sha256sum "$target" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || fail "archive SHA256 mismatch; nothing from this archive was installed"
  echo "VERIFIED archive-sha256=$actual"
}
# Verify all needed archives before installing either tool. Fixed hashes cannot be
# replaced by CLI/env input. Extraction only sees the authenticated official bytes.
if [ "$need_godot" -eq 1 ]; then fetch "$godot_archive" "$stage/godot.zip" 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip' cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4; fi
if [ "$need_pwsh" -eq 1 ]; then fetch "$pwsh_archive" "$stage/pwsh.tar.gz" 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/powershell-7.6.6-linux-x64.tar.gz' ddbc4a2d113bbd46d283cfedcbcd117a70caefd7673f41f2b4e0000badf103bc; fi
if [ "$need_godot" -eq 1 ]; then
  mkdir "$stage/godot"
  unzip -q "$stage/godot.zip" -d "$stage/godot" || fail 'Godot extraction failed'
  chmod 700 "$stage/godot/Godot_v4.7.2-stable_linux.x86_64"
  check_binary "$stage/godot/Godot_v4.7.2-stable_linux.x86_64" godot || fail 'Godot archive executable missing'
fi
if [ "$need_pwsh" -eq 1 ]; then
  mkdir "$stage/pwsh"
  tar --extract --gzip --file "$stage/pwsh.tar.gz" --directory "$stage/pwsh" --no-same-owner --no-same-permissions --keep-old-files || fail 'PowerShell extraction failed'
  chmod 700 "$stage/pwsh/pwsh"
  check_binary "$stage/pwsh/pwsh" pwsh || fail 'PowerShell archive executable missing'
fi
if [ "$need_godot" -eq 1 ]; then
  mkdir -p "$(dirname "$godot_target")"; guard_path "$godot_target"
  [ ! -e "$godot_target" ] || fail 'Godot target appeared during preparation; preserved'
  mv -nT -- "$stage/godot" "$godot_target"
  [ ! -e "$stage/godot" ] || fail 'Godot target appeared during publication; existing directory preserved'
  echo "INSTALLED godot=$godot_target"
fi
if [ "$need_pwsh" -eq 1 ]; then
  mkdir -p "$(dirname "$pwsh_target")"; guard_path "$pwsh_target"
  [ ! -e "$pwsh_target" ] || fail 'PowerShell target appeared during preparation; preserved'
  mv -nT -- "$stage/pwsh" "$pwsh_target"
  [ ! -e "$stage/pwsh" ] || fail 'PowerShell target appeared during publication; existing directory preserved'
  echo "INSTALLED pwsh=$pwsh_target"
fi
echo "ROOMKIT_ENVIRONMENT_READY kind=$([ "$RK_EXPORTED" -eq 1 ] && echo exported || echo source)"
echo 'No service was started. Archives and temporary extraction files are removed.'
