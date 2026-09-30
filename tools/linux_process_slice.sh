#!/usr/bin/env bash
# RoomKit L2-A on the Linux test machine: child-process ownership and owner-only
# path protection, proved with test child programs. No Operator, host or game
# room is started and no real data is used. Reuses the installed Godot 4.7.2;
# installs nothing, no sudo, no services, no firewall or login changes; all
# writes stay under ~/roomkit.
# Exit code: non-zero when any step fails (tools/linux_test_lib.sh).
#
# Next to this script: linux_test_lib.sh, linux_test_lib_selftest.sh, roomkit-src.tar
# Required environment: ROOMKIT_SOURCE_ID, ROOMKIT_RUN_ID, ROOMKIT_SRC_SHA256
set -u
umask 077
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/roomkit"
GODOT="$ROOT/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64"
SRC="$ROOT/src/$ROOMKIT_SOURCE_ID"
RUN="$ROOT/runs/$ROOMKIT_RUN_ID"
section() { printf '\n## %s\n' "$1"; }
finish() { rk_summary; status=$?; echo "ROOMKIT_LINUX_PROCESS_COMPLETE run=$ROOMKIT_RUN_ID failures=$rk_failures"; exit "$status"; }

if [ -e "$RUN" ]; then echo "BLOCKED run folder already exists: $RUN"; exit 3; fi
if [ ! -x "$GODOT" ]; then echo "BLOCKED the installed Godot is missing"; exit 4; fi
mkdir -p "$RUN/tmp" "$RUN/xdg/config" "$RUN/xdg/cache" "$RUN/xdg/data" "$RUN/process"
export XDG_CONFIG_HOME="$RUN/xdg/config" XDG_CACHE_HOME="$RUN/xdg/cache" XDG_DATA_HOME="$RUN/xdg/data"
export TMPDIR="$RUN/tmp"
RK_OUT="$RUN"
. "$HERE/linux_test_lib.sh"
start_time() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }

section "machine"
printf 'kernel=%s loadavg=%s engine=%s\n' "$(uname -r)" "$(cut -d' ' -f1-3 /proc/loadavg)" "$("$GODOT" --version 2>&1 | head -n 1)"

section "runner self-test (injected failures)"
rk_step runner_selftest 120 bash "$HERE/linux_test_lib_selftest.sh" "$HERE/linux_test_lib.sh"
tail -n 1 "$RUN/runner_selftest.out"

section "source snapshot"
if ! rk_install_source "$HERE/roomkit-src.tar" "$SRC" "$ROOMKIT_SRC_SHA256"; then finish; fi

section "sentinel: an unrelated process that must not be touched"
sleep 900 &
SENTINEL=$!
SENTINEL_START="$(start_time "$SENTINEL")"
printf 'sentinel pid=%s start_time=%s parent=this script (not the engine under test)\n' "$SENTINEL" "$SENTINEL_START"

section "ownership rules against a fake process table (no real process)"
rk_step owner_logic 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/owner_logic.godot.log" --script res://tests/run_posix_owner_logic.gd
grep -E '^FAIL|_RESULT' "$RUN/owner_logic.out"

section "real child processes and owner-only paths"
# The engine runs with the private test folder as its working directory, so a
# command smuggled through a file name could only write there (and is looked for).
cd "$RUN/process"
rk_step posix_process 900 "$GODOT" --headless --path "$SRC" --log-file "$RUN/posix_process.godot.log" --script res://tests/run_posix_process.gd -- "--work=$RUN/process" "--fixture=$SRC/tests/fixtures/posix_child.sh" "--sentinel-pid=$SENTINEL"
grep -E '^(PASS|FAIL|NOT RUN|INFO)|_RESULT' "$RUN/posix_process.out"

section "sentinel after the tests"
if kill -0 "$SENTINEL" 2>/dev/null && [ "$(start_time "$SENTINEL")" = "$SENTINEL_START" ]; then
  rk_record sentinel PASS "pid $SENTINEL is still the same live process (start_time unchanged)"
else
  rk_record sentinel FAIL "the sentinel process is gone or was replaced"
fi
kill "$SENTINEL" 2>/dev/null; wait "$SENTINEL" 2>/dev/null

section "leftovers"
children="$(pgrep -u "$(id -u)" -f "posix_child" | wc -l)"
fifos="$(find "$RUN/process" -type p 2>/dev/null | wc -l)"
# Symbolic links always show open mode bits and carry no data of their own.
loose="$(find "$RUN/process/private" ! -type l -perm /077 2>/dev/null | wc -l)"
links="$(find "$RUN/process" -type l 2>/dev/null | wc -l)"
canaries="$(find "$RUN" "$SRC" -name 'canary-*' 2>/dev/null | wc -l)"
if [ "$children" -eq 0 ]; then rk_record no_leftover_children PASS "no test child process remains"; else rk_record no_leftover_children FAIL "$children test child process(es) remain"; fi
if [ "$loose" -eq 0 ]; then rk_record private_modes PASS "nothing under the private test folder is readable by group or others"; else rk_record private_modes FAIL "$loose private entries are readable by group or others"; fi
if [ "$fifos" -eq 0 ] && [ "$links" -eq 0 ]; then rk_record no_leftover_fixtures PASS "no FIFO or link left by the test"; else rk_record no_leftover_fixtures FAIL "$fifos FIFO file(s) and $links link(s) left by the test"; fi
if [ "$canaries" -eq 0 ]; then rk_record no_injected_command PASS "no canary file anywhere in the run or source folder: no file name or argument was executed"; else rk_record no_injected_command FAIL "$canaries canary file(s) exist: a name or argument was executed by a shell"; fi
ls -ld "$RUN/process/private" "$RUN/process/private"/* 2>/dev/null | awk '{print $1, $NF}' | sed "s|$RUN/||"

section "existing unit suite (the room manager limit is expected and stays a failure)"
rk_step run_unit 600 "$GODOT" --headless --path "$SRC" --log-file "$RUN/run_unit.godot.log" --script res://tests/run_unit.gd
grep -E 'UNIT_RESULT' "$RUN/run_unit.out"

section "after the run"
printf 'engine processes of this user still running from ~/roomkit/tools: %s\n' "$(pgrep -u "$(id -u)" -f "$ROOT/tools" | wc -l)"
printf 'run folder size: %s\n' "$(du -sh "$RUN" | awk '{print $1}')"
finish
