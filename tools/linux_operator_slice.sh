#!/usr/bin/env bash
# RoomKit Linux Operator, first slice, on the Linux test machine. Order:
#   1. pure isolation rules with real symbolic links (no Operator);
#   2. the Operator test refuses to start with illegal arguments (exit 64, no
#      Operator, nothing created);
#   3. the isolated Operator: private folders, host start/stop and failures.
# Everything the Operator writes goes to one new isolation folder inside the new
# source snapshot's data folder; logs and engine settings go to the new run
# folder. No real data, no public or cross-machine connection, no firewall or
# login change, no sudo, nothing installed. Reuses Godot 4.7.2 and pwsh 7.6.6.
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
PWSH="$ROOT/tools/pwsh/7.6.6/pwsh"
SRC="$ROOT/src/$ROOMKIT_SOURCE_ID"
RUN="$ROOT/runs/$ROOMKIT_RUN_ID"
ISO="$SRC/data/l2b3-$ROOMKIT_RUN_ID"
PANEL=28391
section() { printf '\n## %s\n' "$1"; }
finish() { rk_summary; status=$?; echo "ROOMKIT_LINUX_OPERATOR_COMPLETE run=$ROOMKIT_RUN_ID failures=$rk_failures"; exit "$status"; }
start_time() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }
hosted=(bash -c 'trap "" PIPE; umask 022; exec "$@"' _)
# TCP listeners of this user on a port (from /proc/net/tcp*, state 0A = LISTEN).
listeners_on() {
  local uid n=0 address state owner port
  uid="$(id -u)"
  while read -r _ address _ state _ _ _ owner _; do
    port=$((16#${address##*:}))
    if [ "$state" = "0A" ] && [ "$owner" = "$uid" ] && [ "$port" -eq "$1" ]; then n=$((n + 1)); fi
  done < <(tail -q -n +2 /proc/net/tcp /proc/net/tcp6 2>/dev/null)
  echo "$n"
}
# expect_refusal <name> <arguments...>: the Operator test must print REFUSED,
# exit 64, never reach OPERATOR_READY and create nothing at the refused paths.
expect_refusal() {
  local name="$1"; shift
  local out="$RUN/$name.out" code
  timeout 120 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/$name.godot.log" --script res://tests/run_posix_operator.gd -- "$@" > "$out" 2>&1
  code=$?
  if [ "$code" -eq 64 ] && grep -q '^REFUSED' "$out" && ! grep -q 'OPERATOR_READY' "$out"; then
    rk_record "$name" PASS "exit=64 $(grep -m1 '^REFUSED' "$out" | cut -c1-160)"
  else
    rk_record "$name" FAIL "exit=$code expected 64 and a REFUSED line without OPERATOR_READY"
    head -n 5 "$out" | sed 's/^/    /'
  fi
}

if [ -e "$RUN" ]; then echo "BLOCKED run folder already exists: $RUN"; exit 3; fi
if [ ! -x "$GODOT" ]; then echo "BLOCKED the installed Godot is missing"; exit 4; fi
if [ ! -x "$PWSH" ]; then echo "BLOCKED pwsh 7.6.6 is missing"; exit 4; fi
mkdir -p "$RUN/tmp" "$RUN/xdg/config" "$RUN/xdg/cache" "$RUN/xdg/data" "$RUN/cwd"
export XDG_CONFIG_HOME="$RUN/xdg/config" XDG_CACHE_HOME="$RUN/xdg/cache" XDG_DATA_HOME="$RUN/xdg/data"
export TMPDIR="$RUN/tmp"
export POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1
RK_OUT="$RUN"
. "$HERE/linux_test_lib.sh"

section "machine"
printf 'kernel=%s loadavg=%s engine=%s\n' "$(uname -r)" "$(cut -d' ' -f1-3 /proc/loadavg)" "$("$GODOT" --version 2>&1 | head -n 1)"
printf 'listeners of this user before the run: panel %s=%s lobby 28300=%s control 28301=%s\n' "$PANEL" "$(listeners_on "$PANEL")" "$(listeners_on 28300)" "$(listeners_on 28301)"

section "runner self-test (injected failures)"
rk_step runner_selftest 120 bash "$HERE/linux_test_lib_selftest.sh" "$HERE/linux_test_lib.sh"
tail -n 1 "$RUN/runner_selftest.out"

section "source snapshot (new)"
if [ -e "$SRC" ]; then rk_record source FAIL "the source folder already exists; this slice needs a new one"; finish; fi
if ! rk_install_source "$HERE/roomkit-src.tar" "$SRC" "$ROOMKIT_SRC_SHA256"; then finish; fi

section "read-only environment check before the acceptance run"
bash "$HERE/linux_env_check.sh" "$SRC" > "$RUN/env_check.out" 2>&1
cat "$RUN/env_check.out"
gate="$(tail -n 1 "$RUN/env_check.out")"
if [ "$gate" = "ENV_GATE OK" ]; then rk_record env_gate PASS "$gate"; else rk_record env_gate FAIL "${gate:-no gate line}; acceptance not started, nothing was stopped"; finish; fi
if [ "$(listeners_on "$PANEL")" -ne 0 ]; then rk_record panel_port FAIL "port $PANEL is already in use; nothing started"; finish; fi

section "sentinel: an unrelated process that must not be touched"
sleep 1800 &
SENTINEL=$!
SENTINEL_START="$(start_time "$SENTINEL")"
printf 'sentinel pid=%s start_time=%s\n' "$SENTINEL" "$SENTINEL_START"
cd "$RUN/cwd"

section "1. pure isolation rules with real symbolic links (no Operator)"
rk_step isolation_rules 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/isolation_rules.godot.log" --script res://tests/run_operator_isolation_rules.gd
grep -E '^(PASS|FAIL|NOT RUN)|_RESULT' "$RUN/isolation_rules.out"
if [ "${rk_states[${#rk_states[@]}-1]}" != PASS ]; then echo "isolation rules failed: nothing else is started"; kill "$SENTINEL" 2>/dev/null; finish; fi

section "2. the Operator test refuses illegal arguments (no Operator is started)"
mkdir -p "$ISO"
chmod 700 "$SRC/data" "$ISO"
mkdir -p "$ISO/elsewhere-target"
ln -s "$ISO/elsewhere-target" "$ISO/linked"
good=("--isolation=$ISO" "--data-root=$ISO/data" "--games=$ISO/games.json" "--public-client-dir=$ISO/public" "--operator-log-path=$ISO/operator.log" "--panel-port=$PANEL")
expect_refusal refuse_no_arguments
expect_refusal refuse_real_data_root "--isolation=$ISO" "--data-root=$SRC/data/framework" "--games=$ISO/games.json" "--public-client-dir=$ISO/public" "--panel-port=$PANEL"
expect_refusal refuse_duplicate_games "--games=$SRC/artifacts/framework-games.json" "${good[@]}"
expect_refusal refuse_bare_games_name "--isolation=$ISO" "--data-root=$ISO/data" "--games=games.json" "--public-client-dir=$ISO/public" "--panel-port=$PANEL"
expect_refusal refuse_traversal "--isolation=$ISO" "--data-root=$ISO/data" "--games=$ISO/games.json" "--public-client-dir=$ISO/../public" "--panel-port=$PANEL"
expect_refusal refuse_linked_games "--isolation=$ISO" "--data-root=$ISO/data" "--games=$ISO/linked/games.json" "--public-client-dir=$ISO/public" "--panel-port=$PANEL"
expect_refusal refuse_production_port "--isolation=$ISO" "--data-root=$ISO/data" "--games=$ISO/games.json" "--public-client-dir=$ISO/public" "--panel-port=28291"
touch "$ISO/games.json"
expect_refusal refuse_existing_index "${good[@]}"
rm -f "$ISO/games.json" "$ISO/linked"
rmdir "$ISO/elsewhere-target"
created="$(find "$ISO" -mindepth 1 2>/dev/null | wc -l)"
if [ "$created" -eq 0 ] && [ ! -e "$SRC/data/framework" ] && [ ! -e "$SRC/artifacts/client" ] && [ -z "$(ls -A "$SRC/run" 2>/dev/null)" ]; then
  rk_record refusals_created_nothing PASS "the refused runs created nothing in the isolation folder, data/framework, artifacts/client or run/"
else
  rk_record refusals_created_nothing FAIL "$created entries in the isolation folder; framework=$([ -e "$SRC/data/framework" ] && echo yes || echo no) client=$([ -e "$SRC/artifacts/client" ] && echo yes || echo no)"
fi
if [ "$(listeners_on "$PANEL")" -ne 0 ]; then rk_record refusals_no_listener FAIL "something listens on $PANEL after the refusals"; else rk_record refusals_no_listener PASS "nothing listens on $PANEL after the refusals"; fi

section "3. isolated Operator: private folders, host start/stop and failures"
export ROOMKIT_PWSH="$PWSH"
rk_step operator 900 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$ISO/operator.log" --script res://tests/run_posix_operator.gd -- "${good[@]}"
grep -E '^(PASS|FAIL|INFO|REFUSED)|_RESULT' "$RUN/operator.out"
unset ROOMKIT_PWSH

section "sentinel after the tests"
if kill -0 "$SENTINEL" 2>/dev/null && [ "$(start_time "$SENTINEL")" = "$SENTINEL_START" ]; then
  rk_record sentinel PASS "pid $SENTINEL is still the same live process (start_time unchanged)"
else
  rk_record sentinel FAIL "the sentinel process is gone or was replaced"
fi
kill "$SENTINEL" 2>/dev/null; wait "$SENTINEL" 2>/dev/null

section "leftovers"
processes="$(pgrep -u "$(id -u)" -f "$SRC" | wc -l)"
listening="$(( $(listeners_on "$PANEL") + $(listeners_on 28300) + $(listeners_on 28301) ))"
# Folders must all be 700 and every data file (databases, JSON, TLS) 600. Log
# files are created by the engine itself with the caller's umask (022 here, on
# purpose); they sit inside 700 folders and are only reported.
loose="$( { find "$ISO" "$SRC/run" -type d -perm /077; find "$ISO" "$SRC/run" -type f \( -name '*.sqlite*' -o -name '*.json' -o -name '*.key' -o -name '*.crt' -o -name '.gdignore' \) -perm /077; } 2>/dev/null | wc -l)"
open_logs="$(find "$ISO" -type f -name '*.log' -perm /077 2>/dev/null | wc -l)"
echo "INFO log files readable by group or others (inside 700 folders, created by the engine with umask 022): $open_logs"
links="$(find "$ISO" -type l 2>/dev/null | wc -l)"
bootstraps="$(find "$SRC/run" -maxdepth 1 -name 'managed-*.json' 2>/dev/null | wc -l)"
marker=0; [ -e "$ISO/data/host-running.json" ] && marker=1
outside="$( { [ -e "$SRC/data/framework" ] && echo framework; [ -e "$SRC/artifacts/client" ] && echo artifacts-client; } | tr '\n' ' ')"
if [ "$processes" -eq 0 ]; then rk_record no_leftover_processes PASS "no Operator, host or helper of this run remains"; else rk_record no_leftover_processes FAIL "$processes process(es) of this run remain"; fi
if [ "$listening" -eq 0 ]; then rk_record no_leftover_listeners PASS "nothing of this user listens on $PANEL, 28300 or 28301"; else rk_record no_leftover_listeners FAIL "$listening listener(s) remain"; fi
if [ "$loose" -eq 0 ] && [ "$links" -eq 0 ]; then rk_record private_modes PASS "the isolation and runtime folders are owner-only and hold no link"; else rk_record private_modes FAIL "$loose entries readable by group or others, $links link(s)"; fi
if [ "$bootstraps" -eq 0 ] && [ "$marker" -eq 0 ]; then rk_record no_leftover_markers PASS "no host bootstrap file and no host marker remain"; else rk_record no_leftover_markers FAIL "$bootstraps bootstrap file(s), marker=$marker"; fi
if [ -z "$outside" ]; then rk_record nothing_outside_isolation PASS "nothing was written to data/framework or artifacts/client"; else rk_record nothing_outside_isolation FAIL "written outside the isolation folder: $outside"; fi
find "$ISO" -maxdepth 2 -printf '%m %y %P\n' 2>/dev/null | sort -k3 | head -n 40

section "existing unit suite"
rk_step run_unit 600 "$GODOT" --headless --path "$SRC" --log-file "$RUN/run_unit.godot.log" --script res://tests/run_unit.gd
grep -E '^FAIL|UNIT_RESULT' "$RUN/run_unit.out"

section "not run here"
echo "NOT RUN backups, restore, results settlement and account deletion through the Operator on Linux (Windows maintenance helper); full managed host with lobby and rooms (process journal and memory limit are refused on Linux); public or cross-machine connection"

section "after the run"
printf 'engine or pwsh processes of this user still running: %s\n' "$(pgrep -u "$(id -u)" -f 'Godot_v4|/pwsh' | wc -l)"
printf 'run folder size: %s, isolation folder size: %s\n' "$(du -sh "$RUN" | awk '{print $1}')" "$(du -sh "$ISO" 2>/dev/null | awk '{print $1}')"
finish
