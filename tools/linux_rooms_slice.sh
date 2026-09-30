#!/usr/bin/env bash
# RoomKit L2-B2 (first item) on the Linux test machine: RoomManager creates,
# starts, registers, readies, stops and reclaims real room children
# (examples/minimal/room.gd) through the process owner. No Operator, no managed
# host, no lobby, no player connection, no real data. Reuses the installed Godot
# 4.7.2; installs nothing, no sudo, no services, no firewall or login changes;
# all writes stay under ~/roomkit.
# Exit code: non-zero when any step fails (tools/linux_test_lib.sh).
#
# Next to this script: linux_test_lib.sh, linux_test_lib_selftest.sh,
#   linux_env_check.sh, roomkit-src.tar
# Required environment: ROOMKIT_SOURCE_ID, ROOMKIT_RUN_ID, ROOMKIT_SRC_SHA256
set -u
umask 077
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/roomkit"
GODOT="$ROOT/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64"
SRC="$ROOT/src/$ROOMKIT_SOURCE_ID"
RUN="$ROOT/runs/$ROOMKIT_RUN_ID"
section() { printf '\n## %s\n' "$1"; }
finish() { rk_summary; status=$?; echo "ROOMKIT_LINUX_ROOMS_COMPLETE run=$ROOMKIT_RUN_ID failures=$rk_failures"; exit "$status"; }
start_time() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }
# Same start conditions as a future Linux host: SIGPIPE ignored, and a loose
# umask so that the private runtime files cannot rely on a strict caller umask.
hosted=(bash -c 'trap "" PIPE; umask 022; exec "$@"' _)
# UDP sockets of this user on the test port ranges (28100-28199), from /proc.
udp_in_range() {
  local uid n=0 address owner port
  uid="$(id -u)"
  while read -r _ address _ _ _ _ _ owner _; do
    port=$((16#${address##*:}))
    if [ "$owner" = "$uid" ] && [ "$port" -ge 28100 ] && [ "$port" -le 28199 ]; then n=$((n + 1)); fi
  done < <(tail -q -n +2 /proc/net/udp /proc/net/udp6 2>/dev/null)
  echo "$n"
}

if [ -e "$RUN" ]; then echo "BLOCKED run folder already exists: $RUN"; exit 3; fi
if [ ! -x "$GODOT" ]; then echo "BLOCKED the installed Godot is missing"; exit 4; fi
mkdir -p "$RUN/tmp" "$RUN/xdg/config" "$RUN/xdg/cache" "$RUN/xdg/data" "$RUN/process" "$RUN/cwd"
export XDG_CONFIG_HOME="$RUN/xdg/config" XDG_CACHE_HOME="$RUN/xdg/cache" XDG_DATA_HOME="$RUN/xdg/data"
export TMPDIR="$RUN/tmp"
RK_OUT="$RUN"
. "$HERE/linux_test_lib.sh"

section "machine"
printf 'kernel=%s loadavg=%s engine=%s\n' "$(uname -r)" "$(cut -d' ' -f1-3 /proc/loadavg)" "$("$GODOT" --version 2>&1 | head -n 1)"
printf 'UDP sockets of this user on ports 28100-28199 before the run: %s\n' "$(udp_in_range)"

section "runner self-test (injected failures)"
rk_step runner_selftest 120 bash "$HERE/linux_test_lib_selftest.sh" "$HERE/linux_test_lib.sh"
tail -n 1 "$RUN/runner_selftest.out"

section "source snapshot"
if ! rk_install_source "$HERE/roomkit-src.tar" "$SRC" "$ROOMKIT_SRC_SHA256"; then finish; fi

section "read-only environment check before the acceptance run"
bash "$HERE/linux_env_check.sh" "$SRC" > "$RUN/env_check.out" 2>&1
cat "$RUN/env_check.out"
gate="$(tail -n 1 "$RUN/env_check.out")"
if [ "$gate" = "ENV_GATE OK" ]; then
  rk_record env_gate PASS "$gate"
else
  rk_record env_gate FAIL "${gate:-no gate line}; acceptance not started, nothing was stopped"
  finish
fi

section "sentinel: an unrelated process that must not be touched"
sleep 1800 &
SENTINEL=$!
SENTINEL_START="$(start_time "$SENTINEL")"
printf 'sentinel pid=%s start_time=%s\n' "$SENTINEL" "$SENTINEL_START"
cd "$RUN/cwd"

section "process owner regression"
rk_step owner_logic 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/owner_logic.godot.log" --script res://tests/run_posix_owner_logic.gd
rk_step posix_process 900 "$GODOT" --headless --path "$SRC" --log-file "$RUN/posix_process.godot.log" --script res://tests/run_posix_process.gd -- "--work=$RUN/process" "--fixture=$SRC/tests/fixtures/posix_child.sh" "--sentinel-pid=$SENTINEL"

section "room lifecycle with real room children (tests/run_integration.gd, now also on Linux)"
rk_step integration 900 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/integration.godot.log" --script res://tests/run_integration.gd
grep -E '^(PASS|FAIL)|_RESULT' "$RUN/integration.out"
grep -c 'ROOM_STATE' "$RUN/integration.out" | sed 's/^/room state transitions logged: /'

section "Linux room specifics (tests/run_posix_rooms.gd)"
rk_step posix_rooms 900 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/posix_rooms.godot.log" --script res://tests/run_posix_rooms.gd
grep -E '^(PASS|FAIL|INFO)|_RESULT' "$RUN/posix_rooms.out"

section "sentinel after the tests"
if kill -0 "$SENTINEL" 2>/dev/null && [ "$(start_time "$SENTINEL")" = "$SENTINEL_START" ]; then
  rk_record sentinel PASS "pid $SENTINEL is still the same live process (start_time unchanged)"
else
  rk_record sentinel FAIL "the sentinel process is gone or was replaced"
fi
kill "$SENTINEL" 2>/dev/null; wait "$SENTINEL" 2>/dev/null

section "leftovers"
processes="$(pgrep -u "$(id -u)" -f "$SRC|posix_child" | wc -l)"
udp="$(udp_in_range)"
launch_files="$(find "$SRC/run" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)"
loose="$(find "$SRC/run" ! -type l -perm /077 2>/dev/null | wc -l)"
if [ "$processes" -eq 0 ]; then rk_record no_leftover_processes PASS "no room, holder or test child of this run remains"; else rk_record no_leftover_processes FAIL "$processes process(es) of this run remain"; fi
if [ "$udp" -eq 0 ]; then rk_record no_leftover_udp PASS "no UDP socket of this user remains on ports 28100-28199"; else rk_record no_leftover_udp FAIL "$udp UDP socket(s) of this user remain on ports 28100-28199"; fi
if [ "$launch_files" -eq 0 ]; then rk_record no_launch_files PASS "no private launch file remains in the runtime folder"; else rk_record no_launch_files FAIL "$launch_files private launch file(s) remain"; fi
if [ "$loose" -eq 0 ]; then rk_record runtime_modes PASS "the runtime folder and its files are owner-only"; else rk_record runtime_modes FAIL "$loose runtime entries are readable by group or others"; fi
ls -la "$SRC/run" 2>/dev/null | awk 'NR>1 {print $1, $NF}'

section "existing unit suite"
rk_step run_unit 600 "$GODOT" --headless --path "$SRC" --log-file "$RUN/run_unit.godot.log" --script res://tests/run_unit.gd
grep -E '^FAIL|UNIT_RESULT' "$RUN/run_unit.out"

section "after the run"
printf 'engine processes of this user still running from ~/roomkit/tools: %s\n' "$(pgrep -u "$(id -u)" -f "$ROOT/tools" | wc -l)"
printf 'run folder size: %s\n' "$(du -sh "$RUN" | awk '{print $1}')"
finish
