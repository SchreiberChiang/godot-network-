#!/usr/bin/env bash
# RoomKit: option P re-measurement and option G (native SQLite) prototype on the
# Linux test machine. Isolated under ~/roomkit, fake data only. Reuses the
# installed Godot 4.7.2 and pwsh 7.6.6; the only new third-party file is the
# official godot-sqlite addons.zip, verified by SHA256 and unpacked into its own
# versioned folder. No sudo, no services, no firewall or login changes. Nothing
# here touches the production storage backend.
# Exit code: non-zero when any step fails (tools/linux_test_lib.sh).
#
# Next to this script: linux_test_lib.sh, linux_test_lib_selftest.sh,
#   roomkit-src.tar, foreign/{accounts,assets}.sqlite (Windows test databases),
#   optionally addons.zip (otherwise it is looked up in the download folders).
# Required environment: ROOMKIT_SOURCE_ID, ROOMKIT_RUN_ID, ROOMKIT_SRC_SHA256,
#   ROOMKIT_ADDON_SHA256, ROOMKIT_ADDON_VERSION
set -u
umask 077
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/roomkit"
GODOT="$ROOT/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64"
PWSH="$ROOT/tools/pwsh/7.6.6/pwsh"
SRC="$ROOT/src/$ROOMKIT_SOURCE_ID"
RUN="$ROOT/runs/$ROOMKIT_RUN_ID"
ADDON_DIR="$ROOT/prototypes/godot-sqlite-$ROOMKIT_ADDON_VERSION"
ADDON_ZIP="$ROOT/downloads/godot-sqlite-$ROOMKIT_ADDON_VERSION-addons.zip"
section() { printf '\n## %s\n' "$1"; }
finish() { rk_summary; status=$?; echo "ROOMKIT_LINUX_G_PROTOTYPE_COMPLETE run=$ROOMKIT_RUN_ID failures=$rk_failures"; exit "$status"; }

if [ -e "$RUN" ]; then echo "BLOCKED run folder already exists: $RUN"; exit 3; fi
if [ ! -x "$PWSH" ] || [ ! -x "$GODOT" ]; then echo "BLOCKED the installed pwsh or Godot is missing"; exit 4; fi
mkdir -p "$RUN/tmp" "$RUN/xdg/config" "$RUN/xdg/cache" "$RUN/xdg/data" "$ROOT/downloads" "$ROOT/prototypes"
export XDG_CONFIG_HOME="$RUN/xdg/config" XDG_CACHE_HOME="$RUN/xdg/cache" XDG_DATA_HOME="$RUN/xdg/data"
export TMPDIR="$RUN/tmp"
export POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1
RK_OUT="$RUN"
. "$HERE/linux_test_lib.sh"
memory() { awk '/^Rss:/{r=$2} /^Pss:/{p=$2} /^Private_Clean:/{c=$2} /^Private_Dirty:/{d=$2} END{ if(r=="") print "memory=unavailable"; else printf "rss_mb=%.1f pss_mb=%.1f private_mb=%.1f", r/1024, p/1024, (c+d)/1024 }' "/proc/$1/smaps_rollup" 2>/dev/null || echo "memory=unavailable"; }

section "machine"
printf 'loadavg=%s mem_available_mb=%s\n' "$(cut -d' ' -f1-3 /proc/loadavg)" "$(awk '/^MemAvailable:/{printf "%d", $2/1024}' /proc/meminfo)"

section "runner self-test (injected failures)"
rk_step runner_selftest 120 bash "$HERE/linux_test_lib_selftest.sh" "$HERE/linux_test_lib.sh"
cat "$RUN/runner_selftest.out"

section "source snapshot"
if ! rk_install_source "$HERE/roomkit-src.tar" "$SRC" "$ROOMKIT_SRC_SHA256"; then finish; fi

section "storage slice with explicit owner-only protection (umask 022 on purpose)"
rk_step storage_slice_umask022 1500 bash -c 'umask 022; exec "$@"' run "$PWSH" -NoProfile -File "$SRC/tests/storage_slice_portable.ps1" -Source "$SRC" -Work "$RUN/slice" -Foreign "$HERE/foreign"
grep -E '^(FAIL|NOT RUN)|permission|owner-only|readable by group|umask=|STORAGE_SLICE_RESULT' "$RUN/storage_slice_umask022.out"
section "injected failure: copied databases that cannot be protected must be refused"
"$PWSH" -NoProfile -File "$SRC/tests/storage_slice_portable.ps1" -Source "$SRC" -Work "$RUN/slice-injected" -Foreign "$HERE/foreign" -InjectCopyPermissionFailure > "$RUN/slice_injected.out" 2>&1
injected=$?
if [ "$injected" -ne 0 ] && grep -q 'FAIL copied foreign databases are set to owner-only' "$RUN/slice_injected.out" && grep -q 'NOT RUN foreign database checks' "$RUN/slice_injected.out" && ! grep -q 'PASS foreign account database accepts' "$RUN/slice_injected.out"; then
  rk_record permission_injection PASS "driver exit=$injected, unprotected copies were refused and not used"
else
  rk_record permission_injection FAIL "driver exit=$injected; the unprotected copies were not refused"
fi

section "option P: repeated measurement (three rounds, both workers alive for memory)"
rk_step p_perf 1500 "$PWSH" -NoProfile -File "$SRC/tests/perf/storage_perf_portable.ps1" -Source "$SRC" -Work "$RUN/p-perf" -Rounds 3
cat "$RUN/p_perf.out"

section "option G: official addon"
if [ ! -f "$ADDON_ZIP" ]; then
  for candidate in "$HERE/addons.zip" "$(xdg-user-dir DOWNLOAD 2>/dev/null)/addons.zip" "$HOME/Downloads/addons.zip" "$HOME/download/addons.zip"; do
    if [ -f "$candidate" ] && [ "$(sha256sum "$candidate" | awk '{print $1}')" = "$ROOMKIT_ADDON_SHA256" ]; then cp "$candidate" "$ADDON_ZIP"; chmod 600 "$ADDON_ZIP"; break; fi
  done
fi
if [ ! -f "$ADDON_ZIP" ] || [ "$(sha256sum "$ADDON_ZIP" | awk '{print $1}')" != "$ROOMKIT_ADDON_SHA256" ]; then
  rk_record addon FAIL "addons.zip with the official SHA256 was not found (bundle, download folders)"; finish
fi
if [ ! -d "$ADDON_DIR" ]; then
  mkdir "$ADDON_DIR" && unzip -q "$ADDON_ZIP" -d "$ADDON_DIR" || { rm -rf "$ADDON_DIR"; rk_record addon FAIL "addons.zip could not be unpacked"; finish; }
fi
ADDON_SRC="$(find "$ADDON_DIR" -maxdepth 3 -type d -name godot-sqlite | head -n 1)"
if [ -z "$ADDON_SRC" ]; then rk_record addon FAIL "godot-sqlite folder not found in the archive"; finish; fi
rk_record addon PASS "sha256 matches; unpacked to $ADDON_DIR ($(du -sh "$ADDON_DIR" | awk '{print $1}')); linux libraries: $(find "$ADDON_SRC" -name '*linux*' -name '*.so' | wc -l)"
ls "$ADDON_SRC" "$ADDON_SRC/bin" 2>/dev/null | head -n 30

section "option G: isolated prototype project"
GPROJ="$RUN/g/project"
mkdir -p "$GPROJ/addons" "$RUN/g/data"
cp "$SRC/prototypes/native_sqlite/project.godot" "$SRC/prototypes/native_sqlite/proto.gd" "$GPROJ/" && cp -r "$ADDON_SRC" "$GPROJ/addons/"
# The editor import registers the extension. Both runs are recorded: on Windows
# the first import with this addon crashed while exiting, the second did not.
rk_step g_import_first 300 "$GODOT" --headless --path "$GPROJ" --import
rk_step g_import_second 300 "$GODOT" --headless --path "$GPROJ" --import
printf 'extension list present: %s\n' "$([ -f "$GPROJ/.godot/extension_list.cfg" ] && echo yes || echo no)"
mkdir -p "$RUN/g/data/verify"
rk_step g_verify 600 "$GODOT" --headless --path "$GPROJ" --script res://proto.gd -- --mode=verify "--work=$RUN/g/data/verify"
grep -E '^(PASS|FAIL|INFO|PROTO_)' "$RUN/g_verify.out"
leaks="$(grep -l 'SECRET_PARAM_7731' "$RUN"/g_*.out 2>/dev/null | wc -l)"
if [ "$leaks" -eq 0 ]; then rk_record g_no_secret_in_output PASS "the bound test secret never appears in engine output"; else rk_record g_no_secret_in_output FAIL "the bound test secret appears in $leaks output file(s)"; fi

section "option G: repeated measurement (three rounds)"
# engine <name> <sample: 0|1> <godot args...>; sets engine_ms, engine_code, engine_memory
engine() {
  local name="$1" sample="$2"; shift 2
  local out="$RUN/$name.out" started pid waited=0
  started=$(date +%s%N)
  "$GODOT" --headless --path "$GPROJ" "$@" > "$out" 2>&1 &
  pid=$!
  engine_memory=""
  if [ "$sample" -eq 1 ]; then
    while kill -0 "$pid" 2>/dev/null && ! grep -q 'PROTO_HOLD' "$out" 2>/dev/null && [ "$waited" -lt 1200 ]; do sleep 0.1; waited=$((waited + 1)); done
    sleep 1.5
    engine_memory="$(memory "$pid")"
  fi
  wait "$pid"; engine_code=$?
  engine_ms=$(( ($(date +%s%N) - started) / 1000000 ))
}
g_problems=0
for round in 1 2 3; do
  engine "g_start_$round" 0 --script res://proto.gd -- --mode=baseline --hold-ms=0
  printf 'ROUND %s loadavg=%s engine_start_and_quit_ms=%s\n' "$round" "$(cut -d' ' -f1 /proc/loadavg)" "$engine_ms"
  engine "g_baseline_$round" 1 --script res://proto.gd -- --mode=baseline --hold-ms=3000
  printf 'ROUND %s baseline_engine %s\n' "$round" "$engine_memory"
  mkdir -p "$RUN/g/data/perf-$round"
  engine "g_perf_$round" 1 --script res://proto.gd -- --mode=perf "--work=$RUN/g/data/perf-$round" --reads=200 --commits=100 --hold-ms=3000
  [ "$engine_code" -eq 0 ] || g_problems=$((g_problems + 1))
  printf 'ROUND %s engine_with_database %s\n' "$round" "$engine_memory"
  grep '^INFO' "$RUN/g_perf_$round.out" | sed "s/^INFO/ROUND $round/"
  grep -q 'SCRIPT ERROR' "$RUN/g_perf_$round.out" && g_problems=$((g_problems + 1))
done
if [ "$g_problems" -eq 0 ]; then rk_record g_perf PASS "three rounds completed"; else rk_record g_perf FAIL "$g_problems round(s) failed"; fi

section "after the run"
printf 'leftover pwsh or godot processes of this user: %s\n' "$(pgrep -u "$(id -u)" -f "$ROOT/tools" | wc -l)"
printf 'entries under the storage work folders readable by group or others: %s\n' "$(find "$RUN/slice" "$RUN/p-perf" -perm /077 2>/dev/null | wc -l)"
printf 'run folder size: %s, roomkit total: %s\n' "$(du -sh "$RUN" | awk '{print $1}')" "$(du -sh "$ROOT" | awk '{print $1}')"
finish
