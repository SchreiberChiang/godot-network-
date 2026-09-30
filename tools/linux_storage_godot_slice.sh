#!/usr/bin/env bash
# RoomKit L2-B1 on the Linux test machine: Godot calls the account service and the
# asset repository, which reach the PowerShell storage scripts through the process
# owner. No Operator, host or game room is started and no real data is used.
# Reuses the installed Godot 4.7.2 and pwsh 7.6.6; installs nothing, no sudo, no
# services, no firewall or login changes; all writes stay under ~/roomkit (test
# databases go to <source snapshot>/data, the only place the services accept).
# Exit code: non-zero when any step fails (tools/linux_test_lib.sh).
#
# Next to this script: linux_test_lib.sh, linux_test_lib_selftest.sh, linux_env_check.sh, roomkit-src.tar
# Required environment: ROOMKIT_SOURCE_ID, ROOMKIT_RUN_ID, ROOMKIT_SRC_SHA256
set -u
umask 077
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/roomkit"
GODOT="$ROOT/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64"
PWSH="$ROOT/tools/pwsh/7.6.6/pwsh"
SRC="$ROOT/src/$ROOMKIT_SOURCE_ID"
RUN="$ROOT/runs/$ROOMKIT_RUN_ID"
TEST_PASSWORD='L2b1-Test-Pass-01'
section() { printf '\n## %s\n' "$1"; }
finish() { rk_summary; status=$?; echo "ROOMKIT_LINUX_STORAGE_GODOT_COMPLETE run=$ROOMKIT_RUN_ID failures=$rk_failures"; exit "$status"; }
start_time() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }
# The host must be started with SIGPIPE ignored (see host/platform/posix_helper.gd).
# umask 022 is deliberate: protection must not depend on a strict caller umask.
hosted=(bash -c 'trap "" PIPE; umask 022; exec "$@"' _)

if [ -e "$RUN" ]; then echo "BLOCKED run folder already exists: $RUN"; exit 3; fi
if [ ! -x "$GODOT" ]; then echo "BLOCKED the installed Godot is missing"; exit 4; fi
if [ ! -x "$PWSH" ]; then echo "BLOCKED pwsh 7.6.6 is not installed at $PWSH"; exit 4; fi
mkdir -p "$RUN/tmp" "$RUN/xdg/config" "$RUN/xdg/cache" "$RUN/xdg/data" "$RUN/process" "$RUN/helper" "$RUN/unsafe" "$RUN/cwd"
export XDG_CONFIG_HOME="$RUN/xdg/config" XDG_CACHE_HOME="$RUN/xdg/cache" XDG_DATA_HOME="$RUN/xdg/data"
export TMPDIR="$RUN/tmp"
export POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1
RK_OUT="$RUN"
. "$HERE/linux_test_lib.sh"

section "machine"
printf 'kernel=%s loadavg=%s engine=%s\n' "$(uname -r)" "$(cut -d' ' -f1-3 /proc/loadavg)" "$("$GODOT" --version 2>&1 | head -n 1)"
printf 'pwsh: '; "$PWSH" -NoProfile -Command '"{0} {1}" -f $PSVersionTable.PSVersion, [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription' 2>&1 | head -n 1
printf 'other engine or pwsh processes of this user before the run: %s\n' "$(pgrep -u "$(id -u)" -f 'Godot_v4|/pwsh' | wc -l)"
free -m | awk 'NR==2 {printf "memory MB: total=%s used=%s available=%s\n", $2, $3, $7}'

section "runner self-test (injected failures)"
rk_step runner_selftest 120 bash "$HERE/linux_test_lib_selftest.sh" "$HERE/linux_test_lib.sh"
tail -n 1 "$RUN/runner_selftest.out"

section "source snapshot"
if ! rk_install_source "$HERE/roomkit-src.tar" "$SRC" "$ROOMKIT_SRC_SHA256"; then finish; fi
if [ -e "$SRC/data" ]; then echo "note: $SRC/data already exists (an earlier run of this snapshot)"; fi

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

section "process owner regression (the owner changed: optional keep-pipes stop, locked trust list)"
rk_step owner_logic 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/owner_logic.godot.log" --script res://tests/run_posix_owner_logic.gd
rk_step posix_process 900 "$GODOT" --headless --path "$SRC" --log-file "$RUN/posix_process.godot.log" --script res://tests/run_posix_process.gd -- "--work=$RUN/process" "--fixture=$SRC/tests/fixtures/posix_child.sh" "--sentinel-pid=$SENTINEL"

section "helper limits with a STAND-IN shell (real processes, not PowerShell)"
rk_step helper_pipe_unsafe 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/helper_pipe_unsafe.godot.log" --script res://tests/run_posix_helper.gd -- "--work=$RUN/unsafe" "--shell=$SRC/tests/fixtures/posix_fake_shell.sh" --expect=pipe-unsafe
grep -E '^(PASS|FAIL|INFO)' "$RUN/helper_pipe_unsafe.out"
rk_step helper_limits 600 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/helper_limits.godot.log" --script res://tests/run_posix_helper.gd -- "--work=$RUN/helper" "--shell=$SRC/tests/fixtures/posix_fake_shell.sh"
grep -E '^(PASS|FAIL|INFO)' "$RUN/helper_limits.out"

export ROOMKIT_PWSH="$PWSH"
for mode in oneshot resident; do
  section "Godot -> services -> real PowerShell storage, mode=$mode"
  printf 'loadavg before: %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
  rk_step "storage_$mode" 1800 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/storage_$mode.godot.log" --script res://tests/run_posix_storage.gd -- "--mode=$mode"
  grep -E '^(PASS|FAIL|NOT RUN|INFO)|_RESULT|EVIDENCE' "$RUN/storage_$mode.out"
  printf 'loadavg after: %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
done
unset ROOMKIT_PWSH

section "sentinel after the tests"
if kill -0 "$SENTINEL" 2>/dev/null && [ "$(start_time "$SENTINEL")" = "$SENTINEL_START" ]; then
  rk_record sentinel PASS "pid $SENTINEL is still the same live process (start_time unchanged)"
else
  rk_record sentinel FAIL "the sentinel process is gone or was replaced"
fi
kill "$SENTINEL" 2>/dev/null; wait "$SENTINEL" 2>/dev/null

section "leftovers"
processes="$(pgrep -u "$(id -u)" -f "$SRC|fake-pwsh|storage_worker.ps1|posix_child" | wc -l)"
loose="$(find "$SRC/data" ! -type l -perm /077 2>/dev/null | wc -l)"
entries="$(find "$SRC/data" 2>/dev/null | wc -l)"
requests="$(find "$SRC/data" "$RUN" \( -name 'request-*' -o -name 'helper-*.json' \) 2>/dev/null | wc -l)"
links="$(find "$SRC/data" "$RUN/process" "$RUN/helper" -type l 2>/dev/null | wc -l)"
fifos="$(find "$RUN" "$SRC/data" \( -type p -o -type s \) 2>/dev/null | wc -l)"
canaries="$(find "$RUN" "$SRC" -name 'canary-*' 2>/dev/null | wc -l)"
secret_text="$(grep -rlF -- "$TEST_PASSWORD" "$RUN" 2>/dev/null | wc -l)"
secret_data="$(grep -rlaF -- "$TEST_PASSWORD" "$SRC/data" 2>/dev/null | wc -l)"
if [ "$processes" -eq 0 ]; then rk_record no_leftover_processes PASS "no engine, helper, worker or test child of this run remains"; else rk_record no_leftover_processes FAIL "$processes process(es) of this run remain"; fi
if [ "$entries" -gt 0 ] && [ "$loose" -eq 0 ]; then rk_record data_modes PASS "all $entries entries under the test data folder are owner-only"; else rk_record data_modes FAIL "$loose of $entries entries under the test data folder are readable by group or others"; fi
if [ "$requests" -eq 0 ]; then rk_record no_request_files PASS "no request or helper file remains"; else rk_record no_request_files FAIL "$requests request or helper file(s) remain"; fi
if [ "$links" -eq 0 ] && [ "$fifos" -eq 0 ] && [ "$canaries" -eq 0 ]; then rk_record no_leftover_fixtures PASS "no link, FIFO, socket or canary file left by the tests (the temporary folder included)"; else rk_record no_leftover_fixtures FAIL "$links link(s), $fifos FIFO(s) or socket(s), $canaries canary file(s) left"; fi
find "$RUN" "$SRC/data" \( -type p -o -type s \) -printf 'left behind: %y %P\n' 2>/dev/null | sed -E 's/[0-9]{3,}/N/g' | sort | uniq -c | head -n 12
if [ "$secret_text" -eq 0 ] && [ "$secret_data" -eq 0 ]; then rk_record no_secret_in_output PASS "the test password appears in no output, log or data file of this run"; else rk_record no_secret_in_output FAIL "the test password appears in $secret_text output/log file(s) and $secret_data data file(s)"; fi
find "$SRC/data" -maxdepth 3 -printf '%m %y %P\n' 2>/dev/null | sort -k3 | head -n 60
printf 'test data size: %s\n' "$(du -sh "$SRC/data" 2>/dev/null | awk '{print $1}')"

section "existing unit suite (the room manager limit is expected and stays a failure)"
rk_step run_unit 600 "$GODOT" --headless --path "$SRC" --log-file "$RUN/run_unit.godot.log" --script res://tests/run_unit.gd
grep -E 'UNIT_RESULT' "$RUN/run_unit.out"

section "not run here"
echo "NOT RUN tests/run_accounts.gd, run_assets.gd, run_resident_store.gd, run_account_deletion.gd, run_account_recovery.gd, run_result_rewards.gd, run_grant_storage.gd: their fixtures and process checks call powershell.exe and Windows process APIs directly"

section "after the run"
printf 'engine or pwsh processes of this user still running: %s\n' "$(pgrep -u "$(id -u)" -f 'Godot_v4|/pwsh' | wc -l)"
printf 'run folder size: %s\n' "$(du -sh "$RUN" | awk '{print $1}')"
finish
