#!/usr/bin/env bash
# Check an immutable Linux server directory. No installation or service startup.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { echo "LINUX_PACKAGE_FAILED $*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || fail "run as an ordinary user, not root"
[ "$(uname -m)" = x86_64 ] || fail "this package requires Linux x86_64"
for tool in sha256sum ldd setsid pgrep timeout mktemp; do command -v "$tool" >/dev/null || fail "missing $tool"; done
[ -f "$ROOT/SHA256SUMS.txt" ] && [ ! -L "$ROOT/SHA256SUMS.txt" ] || fail "checksum manifest missing or linked"
while IFS= read -r line; do
  [[ "$line" =~ ^[0-9a-f]{64}[[:space:]][[:space:]][a-zA-Z0-9_./-]+$ ]] || fail "invalid checksum line"
  file="${line:66}"
  [[ "$file" != /* && "/$file/" != */../* ]] || fail "checksum path outside package"
  cursor="$ROOT/$file"
  while [ "$cursor" != / ]; do [ ! -L "$cursor" ] || fail "linked package path $file"; cursor="$(dirname "$cursor")"; done
done < "$ROOT/SHA256SUMS.txt"
(cd "$ROOT" && sha256sum -c SHA256SUMS.txt) || fail "checksum mismatch"
for file in Operator.x86_64 ManagedHost.x86_64 games/shooter/Server.x86_64 games/turns/Server.x86_64; do
  chmod 700 "$ROOT/$file" || fail "cannot set execute permission $file"
  ldd "$ROOT/$file" > /dev/null 2>&1 || fail "cannot inspect runtime libraries $file"
  if ldd "$ROOT/$file" | grep -q 'not found'; then fail "missing runtime library $file"; fi
  version="$("$ROOT/$file" --headless --version)" || fail "cannot read engine identity $file"
  [ "$version" = 4.7.2.stable.official.ed1daf0bf ] || fail "unexpected engine identity $file"
done
. "$ROOT/tools/runtime_paths.sh"
rk_runtime_paths "$ROOT"
PWSH="$RK_PWSH"
[[ "$PWSH" = /* ]] && [ -x "$PWSH" ] || fail "set ROOMKIT_PWSH to the existing absolute pwsh executable"
[ ! -L "$ROOT/data" ] || fail "linked package data directory"
umask 077
mkdir -p "$ROOT/data" && chmod 700 "$ROOT/data"
probe="$(mktemp -d "$ROOT/data/package-check-XXXXXXXX")"
cleanup() { case "$probe" in "$ROOT"/data/package-check-*) rm -rf -- "$probe" ;; esac; }
trap cleanup EXIT
mkdir "$probe/home" "$probe/config" "$probe/cache" "$probe/share" "$probe/tmp"
storage="$(HOME="$probe/home" XDG_CONFIG_HOME="$probe/config" XDG_CACHE_HOME="$probe/cache" XDG_DATA_HOME="$probe/share" TMPDIR="$probe/tmp" \
  DOTNET_EnableDiagnostics=0 COMPlus_EnableDiagnostics=0 POWERSHELL_DIAGNOSTICS_OPTOUT=1 POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
  timeout 15 "$PWSH" -NoProfile -NonInteractive -Command '
    $ErrorActionPreference="Stop"
    if($PSVersionTable.PSVersion.ToString() -ne "7.6.6"){throw "This candidate requires the tested pwsh 7.6.6 runtime."}
    $library=[Runtime.InteropServices.NativeLibrary]::Load("libsqlite3.so.0")
    [Runtime.InteropServices.NativeLibrary]::Free($library)
    Write-Output "LINUX_STORAGE_DEPENDENCIES_OK pwsh=7.6.6 sqlite=loaded"
  ')" || fail "pwsh/SQLite dependency check failed"
[ "$storage" = "LINUX_STORAGE_DEPENDENCIES_OK pwsh=7.6.6 sqlite=loaded" ] || fail "unexpected storage dependency response"
echo "$storage"
echo "LINUX_PACKAGE_VALID engine=4.7.2.stable.official.ed1daf0bf pwsh=7.6.6 sqlite=loaded"
