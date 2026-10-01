#!/usr/bin/env bash
# RoomKit stage acceptance on the Linux test machine: L2 finish and the L3
# same-machine loop (docs/17 "当前连续任务单", work packages 1-4). Order:
#   A. process journal, cross-run recovery, room memory limit, maintenance under
#      pwsh, isolated Operator with the real host (package 1);
#   B. account deletion with signed results and late settlement, deletion through
#      a real Operator, Operator lifecycle with backup and restore (package 3);
#   C. the official entry tools/roomkit_linux.sh: an isolated instance, two real
#      headless clients (register, login, room, purchase and replay, a full round
#      with signed settlement), backup/restore, stop and restart with data kept
#      (packages 2 and 3);
#   D. fault: the Operator this run started and verified is killed; host and room
#      leave by themselves; read-only recovery on the next start (package 4);
#   E. low-load endurance on the instance, then the final stop and leftovers.
# Everything stays in the new source snapshot and the new run folder under
# ~/roomkit. Only fake accounts. No real data, no public or cross-machine
# connection (the instance binds 127.0.0.1), no firewall or login change, no sudo,
# nothing installed. Reuses Godot 4.7.2 and pwsh 7.6.6.
# Exit code: non-zero when any step fails (tools/linux_test_lib.sh).
#
# Next to this script: linux_test_lib.sh, linux_test_lib_selftest.sh,
#   linux_env_check.sh, roomkit-src.tar
# Required environment: ROOMKIT_SOURCE_ID, ROOMKIT_RUN_ID, ROOMKIT_SRC_SHA256
# Optional: ROOMKIT_ENDURANCE_MINUTES (default 60; 0 skips E's endurance step),
#   ROOMKIT_PHASES (default ABCDE; CDE runs only the instance loop)
set -u
umask 077
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/roomkit"
GODOT="$ROOT/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64"
PWSH="$ROOT/tools/pwsh/7.6.6/pwsh"
SRC="$ROOT/src/$ROOMKIT_SOURCE_ID"
RUN="$ROOT/runs/$ROOMKIT_RUN_ID"
REAL_HOME="$HOME"
ISO="$SRC/data/l3op-$ROOMKIT_RUN_ID"
INST="$SRC/data/instance-l3"
ENDURANCE="${ROOMKIT_ENDURANCE_MINUTES:-60}"
# Which parts run: A and B (component and driver checks) and C/D/E (the instance
# loop). ROOMKIT_PHASES=CDE re-checks only the instance loop.
PHASES="${ROOMKIT_PHASES:-ABCDE}"
PANEL=28391 LOBBY_T=28520 CONTROL_T=28521
I_PANEL=28491 I_LOBBY=28500 I_CONTROL=28501 I_UDP_FIRST=28540 I_UDP_LAST=28555
section() { printf '\n## %s  (%s)\n' "$1" "$(date '+%H:%M:%S')"; }
finish() { rk_summary; status=$?; echo "ROOMKIT_LINUX_L3_COMPLETE run=$ROOMKIT_RUN_ID failures=$rk_failures"; exit "$status"; }
start_time() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }
hosted=(bash -c 'trap "" PIPE; umask 022; exec "$@"' _)
listeners_on() {
  local uid n=0 address state owner port
  uid="$(id -u)"
  while read -r _ address _ state _ _ _ owner _; do
    port=$((16#${address##*:}))
    if [ "$state" = "0A" ] && [ "$owner" = "$uid" ] && [ "$port" -eq "$1" ]; then n=$((n + 1)); fi
  done < <(tail -q -n +2 /proc/net/tcp /proc/net/tcp6 2>/dev/null)
  echo "$n"
}
# Local address of this user's TCP listener on a port (hex from /proc/net/tcp).
listener_address() {
  local uid address state owner port
  uid="$(id -u)"
  while read -r _ address _ state _ _ _ owner _; do
    port=$((16#${address##*:}))
    if [ "$state" = "0A" ] && [ "$owner" = "$uid" ] && [ "$port" -eq "$1" ]; then echo "${address%%:*}"; fi
  done < <(tail -q -n +2 /proc/net/tcp 2>/dev/null)
}
udp_in_range() {
  local uid n=0 address owner port
  uid="$(id -u)"
  while read -r _ address _ _ _ _ _ owner _; do
    port=$((16#${address##*:}))
    if [ "$owner" = "$uid" ] && [ "$port" -ge "$1" ] && [ "$port" -le "$2" ]; then n=$((n + 1)); fi
  done < <(tail -q -n +2 /proc/net/udp /proc/net/udp6 2>/dev/null)
  echo "$n"
}
# Local addresses (hex) of this user's UDP sockets in [first, last].
udp_addresses() {
  local uid address owner port
  uid="$(id -u)"
  while read -r _ address _ _ _ _ _ owner _; do
    port=$((16#${address##*:}))
    if [ "$owner" = "$uid" ] && [ "$port" -ge "$1" ] && [ "$port" -le "$2" ]; then echo "${address%%:*}"; fi
  done < <(tail -q -n +2 /proc/net/udp /proc/net/udp6 2>/dev/null)
}
source_processes() { pgrep -u "$(id -u)" -f "$SRC" | grep -v "^$$\$" | wc -l; }
entry() { "${entry_env[@]}" bash "$SRC/tools/roomkit_linux.sh" "$@"; }
acceptance() { rk_step "l3_$1" "${2:-900}" "$PWSH" -NoProfile -NonInteractive -File "$SRC/tests/linux_l3_acceptance.ps1" -Phase "$1" -Instance "$INST" -PanelPort "$I_PANEL"; grep -E '^(PASS|FAIL|INFO|NOT RUN)|ACCEPTANCE_|_RESULT' "$RUN/l3_$1.out"; }
# leftovers <label>: nothing of this source runs, listens or holds UDP; no launch file.
leftovers() {
  local label="$1" p l u r
  sleep 2
  p="$(source_processes)"
  l=$(( $(listeners_on "$I_PANEL") + $(listeners_on "$I_LOBBY") + $(listeners_on "$I_CONTROL") ))
  u="$(udp_in_range "$I_UDP_FIRST" "$I_UDP_LAST")"
  r="$(find "$SRC/run" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)"
  if [ "$p" -eq 0 ] && [ "$l" -eq 0 ] && [ "$u" -eq 0 ] && [ "$r" -eq 0 ]; then
    rk_record "leftovers_$label" PASS "no process of this source, no listener on $I_PANEL/$I_LOBBY/$I_CONTROL, no UDP on $I_UDP_FIRST-$I_UDP_LAST, no launch file"
  else
    rk_record "leftovers_$label" FAIL "processes=$p listeners=$l udp=$u launch_files=$r"
    pgrep -u "$(id -u)" -af "$SRC" | cut -c1-600 | sed 's/^/    /'
    find "$SRC/run" -maxdepth 1 -name '*.json' -printf '    launch file %f\n' 2>/dev/null
  fi
}

if [ -e "$RUN" ]; then echo "BLOCKED run folder already exists: $RUN"; exit 3; fi
if [ ! -x "$GODOT" ]; then echo "BLOCKED the installed Godot is missing"; exit 4; fi
if [ ! -x "$PWSH" ]; then echo "BLOCKED pwsh 7.6.6 is missing"; exit 4; fi
mkdir -p "$RUN/tmp" "$RUN/home" "$RUN/xdg/config" "$RUN/xdg/cache" "$RUN/xdg/data" "$RUN/cwd" "$RUN/process"
export HOME="$RUN/home" XDG_CONFIG_HOME="$RUN/xdg/config" XDG_CACHE_HOME="$RUN/xdg/cache" XDG_DATA_HOME="$RUN/xdg/data" TMPDIR="$RUN/tmp"
export POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1 NO_COLOR=1
export ROOMKIT_GODOT="$GODOT" ROOMKIT_PWSH="$PWSH"
entry_env=(env ROOMKIT_GODOT="$GODOT" ROOMKIT_PWSH="$PWSH")
RK_OUT="$RUN"
. "$HERE/linux_test_lib.sh"
home_before="$(ls -A "$REAL_HOME" | sort | tr '\n' ' ')"

section "machine"
printf 'kernel=%s cpus=%s memory=%s loadavg=%s engine=%s\n' "$(uname -r)" "$(nproc)" "$(awk '/MemTotal/ {print $2" kB"}' /proc/meminfo)" "$(cut -d' ' -f1-3 /proc/loadavg)" "$("$GODOT" --version 2>&1 | head -n 1)"

section "runner self-test (injected failures)"
rk_step runner_selftest 120 bash "$HERE/linux_test_lib_selftest.sh" "$HERE/linux_test_lib.sh"
tail -n 1 "$RUN/runner_selftest.out"

section "source snapshot (new)"
if [ -e "$SRC" ]; then rk_record source FAIL "the source folder already exists; this run needs a new one"; finish; fi
if ! rk_install_source "$HERE/roomkit-src.tar" "$SRC" "$ROOMKIT_SRC_SHA256"; then finish; fi

section "read-only environment check before the acceptance run"
# The check looks for the shared tools under the real home (~/roomkit/tools).
HOME="$REAL_HOME" bash "$HERE/linux_env_check.sh" "$SRC" > "$RUN/env_check.out" 2>&1
cat "$RUN/env_check.out"
gate="$(tail -n 1 "$RUN/env_check.out")"
if [ "$gate" = "ENV_GATE OK" ]; then rk_record env_gate PASS "$gate"; else rk_record env_gate FAIL "${gate:-no gate line}; acceptance not started, nothing was stopped"; finish; fi
for port in "$PANEL" "$LOBBY_T" "$CONTROL_T" "$I_PANEL" "$I_LOBBY" "$I_CONTROL"; do
  if [ "$(listeners_on "$port")" -ne 0 ]; then rk_record ports_free FAIL "port $port is already in use; nothing started"; finish; fi
done

section "sentinel: an unrelated process that must not be touched"
sleep 14400 &
SENTINEL=$!
SENTINEL_START="$(start_time "$SENTINEL")"
printf 'sentinel pid=%s start_time=%s\n' "$SENTINEL" "$SENTINEL_START"
cd "$RUN/cwd"
mkdir -p "$SRC/data/journal-$ROOMKIT_RUN_ID"
chmod 700 "$SRC/data" "$SRC/data/journal-$ROOMKIT_RUN_ID"

if [[ "$PHASES" == *A* ]]; then
section "A1. process owner regression"
rk_step owner_logic 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/owner_logic.godot.log" --script res://tests/run_posix_owner_logic.gd
rk_step posix_process 900 "$GODOT" --headless --path "$SRC" --log-file "$RUN/posix_process.godot.log" --script res://tests/run_posix_process.gd -- "--work=$RUN/process" "--fixture=$SRC/tests/fixtures/posix_child.sh" "--sentinel-pid=$SENTINEL"

section "A2. journal rules (read-only inspection of earlier records)"
rk_step journal_rules 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/journal_rules.godot.log" --script res://tests/run_posix_journal_rules.gd -- "--work=$SRC/data/journal-$ROOMKIT_RUN_ID" "--fixture=$SRC/tests/fixtures/posix_child.sh"
grep -E '^(PASS|FAIL)|_RESULT' "$RUN/journal_rules.out"

section "A3. room lifecycle with the process journal and the memory limit"
rk_step integration 900 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/integration.godot.log" --script res://tests/run_integration.gd
grep -E '^FAIL|_RESULT' "$RUN/integration.out"
rk_step posix_rooms 900 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/posix_rooms.godot.log" --script res://tests/run_posix_rooms.gd
grep -E '^(PASS|FAIL|INFO)|_RESULT' "$RUN/posix_rooms.out"

section "A4. cross-run recovery with real hosts and rooms; secure WSS/DTLS clients"
rk_step recovery 900 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/recovery.godot.log" --script res://tests/run_recovery.gd
grep -E '^(PASS|FAIL)|RECOVERY_|_RESULT' "$RUN/recovery.out"
rk_step secure 900 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/secure.godot.log" --script res://tests/run_secure.gd
grep -E '^FAIL|_RESULT' "$RUN/secure.out"

section "A5. maintenance script under pwsh (metrics, backup, restore, link refusal)"
rk_step maintenance 900 "${hosted[@]}" "$PWSH" -NoProfile -NonInteractive -File "$SRC/tests/test_operator_maintenance.ps1"
grep -E '^(PASS|FAIL)|MAINTENANCE_RESULT' "$RUN/maintenance.out"

section "A6. isolated Operator: maintenance, earlier markers, real host, unexpected exit"
rk_step isolation_rules 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/isolation_rules.godot.log" --script res://tests/run_operator_isolation_rules.gd
if [ "${rk_states[${#rk_states[@]}-1]}" = PASS ]; then
  mkdir -p "$ISO"; chmod 700 "$ISO"
  good=("--isolation=$ISO" "--data-root=$ISO/data" "--games=$ISO/games.json" "--public-client-dir=$ISO/public" "--operator-log-path=$ISO/operator.log" "--panel-port=$PANEL")
  rk_step operator 1200 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$ISO/operator.log" --script res://tests/run_posix_operator.gd -- "${good[@]}"
  grep -E '^(PASS|FAIL|INFO|REFUSED)|_RESULT' "$RUN/operator.out"
else
  rk_record operator NOTRUN "isolation rules failed: the Operator was not started"
fi

else
  rk_record phase_a NOTRUN "ROOMKIT_PHASES=$PHASES"
fi

if [[ "$PHASES" == *B* ]]; then
section "B1. account deletion: signed results and late settlement (storage level)"
rk_step account_deletion 900 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/account_deletion.godot.log" --script res://tests/run_account_deletion.gd
grep -E '^FAIL|_RESULT' "$RUN/account_deletion.out"

section "B2. game index of this snapshot (for the Operator drivers)"
rk_step build_index 300 "$PWSH" -NoProfile -NonInteractive -File "$SRC/tools/build_framework.ps1"

section "B3. account deletion through a real Operator, host, room and two clients"
rk_step deletion_e2e 1200 "${hosted[@]}" "$PWSH" -NoProfile -NonInteractive -File "$SRC/tests/test_account_deletion.ps1"
grep -E '^(PASS|FAIL)|ACCOUNT_DELETION_|_RESULT' "$RUN/deletion_e2e.out"

section "B4. Operator lifecycle: backup, restore, restart (crash injection is Windows-only here)"
rk_step operator_lifecycle 1200 "${hosted[@]}" "$PWSH" -NoProfile -NonInteractive -File "$SRC/tests/test_operator.ps1" -Lifecycle
grep -E '^(PASS|FAIL|NOT RUN)|OPERATOR_RESULT|OPERATOR_PROCESS_EXIT' "$RUN/operator_lifecycle.out"
leftovers after_drivers
else
  rk_record phase_b NOTRUN "ROOMKIT_PHASES=$PHASES"
fi

section "C0. session clean-up rules (unit) and the Operator's logout path (doubles)"
rk_step session_cleanup 300 "$GODOT" --headless --path "$SRC" --log-file "$RUN/session_cleanup.godot.log" --script res://tests/run_session_cleanup.gd
grep -E '^FAIL|_RESULT' "$RUN/session_cleanup.out"
mkdir -p "$SRC/data/logout-$ROOMKIT_RUN_ID"; chmod 700 "$SRC/data/logout-$ROOMKIT_RUN_ID"
rk_step logout_cleanup 300 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/logout_cleanup.godot.log" --script res://tests/run_operator_logout_cleanup.gd -- "--data-root=$SRC/data/logout-$ROOMKIT_RUN_ID/data"
grep -E '^(PASS|FAIL)|_RESULT' "$RUN/logout_cleanup.out"

section "C0b. bounded backup waiting, result retries and internal RPC cancellation"
rk_step backup_wait 180 "${hosted[@]}" "$GODOT" --headless --path "$SRC" --log-file "$RUN/backup_wait.godot.log" --script res://tests/run_operator_backup_wait.gd
grep -E '^FAIL|_RESULT' "$RUN/backup_wait.out"
rk_step rpc_cancel 180 "$GODOT" --headless --path "$SRC" --log-file "$RUN/rpc_cancel.godot.log" --script res://tests/run_local_rpc_cancel.gd
grep -E '^FAIL|_RESULT' "$RUN/rpc_cancel.out"

section "C1. official entry: start an isolated instance"
entry_args=(--instance l3 --panel-port "$I_PANEL" --lobby-port "$I_LOBBY" --control-port "$I_CONTROL" --udp-range "$I_UDP_FIRST-$I_UDP_LAST" --bind 127.0.0.1)
rk_step entry_refuses_28291 60 bash -c '! "$@"' _ "${entry_env[@]}" bash "$SRC/tools/roomkit_linux.sh" start --instance refused --panel-port 28291
rk_step entry_start 600 "${entry_env[@]}" bash "$SRC/tools/roomkit_linux.sh" start "${entry_args[@]}"
cat "$RUN/entry_start.out"
entry status --instance l3
loose_inst="$( { find "$INST" -type d -perm /077; find "$INST" -type f -perm /077; } 2>/dev/null | wc -l)"
if [ "$loose_inst" -eq 0 ]; then rk_record instance_private PASS "every folder of the instance is 700 and every file 600 (umask 077)"; else rk_record instance_private FAIL "$loose_inst entries readable by group or others"; find "$INST" -perm /077 | head -n 8 | sed "s#$SRC/##; s/^/    /"; fi
printf 'instance folders: %s\n' "$(cd "$INST" && find . -maxdepth 1 -mindepth 1 -printf '%f ' )"
printf 'engine user data inside the instance: %s entries\n' "$(find "$INST/xdg" -mindepth 1 2>/dev/null | wc -l)"

section "C2. two real headless clients through the instance (full round, signed settlement)"
acceptance prepare 600
# The host (lobby, rooms) runs from here on: every socket of the instance on 127.0.0.1.
addresses="$(listener_address "$I_PANEL") $(listener_address "$I_LOBBY") $(listener_address "$I_CONTROL")"
room_udp="$(udp_addresses "$I_UDP_FIRST" "$I_UDP_LAST" | sort -u | tr '\n' ' ')"
if [ "$addresses" = "0100007F 0100007F 0100007F" ] && [ "$room_udp" = "0100007F " ]; then rk_record loopback_only PASS "panel, lobby, room control and room UDP sockets are bound to 127.0.0.1 only"; else rk_record loopback_only FAIL "addresses (hex) panel/lobby/control: [$addresses] room UDP: [$room_udp]"; fi
rk_step clients 1500 "$PWSH" -NoProfile -NonInteractive -File "$SRC/tests/test_framework_clients.ps1" -GamesIndex "$INST/games.json"
grep -E '^(PASS|FAIL)|FRAMEWORK_CLIENT|_RESULT' "$RUN/clients.out"
acceptance persist 900

section "C3. stop and restart with the official entry; data kept"
rk_step entry_stop 300 "${entry_env[@]}" bash "$SRC/tools/roomkit_linux.sh" stop --instance l3
cat "$RUN/entry_stop.out"
leftovers after_stop
tmp_left="$(find "$INST/tmp" -mindepth 1 2>/dev/null | wc -l)"
if [ "$tmp_left" -eq 0 ]; then rk_record instance_tmp_clean PASS "the instance tmp folder is empty after the stop"; else rk_record instance_tmp_clean FAIL "$tmp_left entries in the instance tmp folder"; fi
rk_step entry_restart 600 "${entry_env[@]}" bash "$SRC/tools/roomkit_linux.sh" start "${entry_args[@]}"
acceptance after-restart 600
rk_step entry_stop_2 300 "${entry_env[@]}" bash "$SRC/tools/roomkit_linux.sh" stop --instance l3
leftovers before_fault

section "D. fault: kill the Operator this run started and verified"
acceptance fault 600
leftovers after_fault
if kill -0 "$SENTINEL" 2>/dev/null && [ "$(start_time "$SENTINEL")" = "$SENTINEL_START" ]; then rk_record sentinel_after_fault PASS "the unrelated sentinel is untouched"; else rk_record sentinel_after_fault FAIL "the sentinel process is gone or was replaced"; fi
rk_step entry_after_fault 600 "${entry_env[@]}" bash "$SRC/tools/roomkit_linux.sh" start "${entry_args[@]}"
acceptance after-fault 600

section "E. low-load endurance on the instance ($ENDURANCE minutes, 2-8 clients)"
if [ "$ENDURANCE" -gt 0 ]; then
  rk_step endurance $((ENDURANCE * 60 + 1800)) "$PWSH" -NoProfile -NonInteractive -File "$SRC/tests/linux_endurance.ps1" -Instance "$INST" -PanelPort "$I_PANEL" -Minutes "$ENDURANCE"
  grep -E 'ENDURANCE_(START|SUMMARY|RESULT)|CYCLE_FAILURE' "$RUN/endurance.out"
  printf 'session clean-up events logged by the Operator: %s\n' "$(grep -o 'SESSION_CLEANUP job=[0-9a-f]* event=[a-z_]*' "$INST/logs/console.log" 2>/dev/null | sed 's/.*event=//' | sort | uniq -c | tr '\n' ' ')"
  printf 'storage refusals logged by the Operator: %s\n' "$(grep -c 'OPERATOR_STORAGE_REFUSED' "$INST/logs/console.log" 2>/dev/null)"
  grep 'OPERATOR_STORAGE_REFUSED' "$INST/logs/console.log" 2>/dev/null | sed 's/ t=[0-9]*//' | sort | uniq -c | head -n 10
  automatic_ok="$(awk '/OPERATOR_MAINTENANCE .*event=backup_begin/ {automatic=($0 ~ /automatic=true/)} /OPERATOR_MAINTENANCE .*event=backup_end/ {if(automatic && $0 ~ /ok=true/) count++; automatic=0} END {print count+0}' "$INST/logs/console.log")"
  waits_ok="$(grep -c 'OPERATOR_BACKUP_WAIT .*event=finished code=OK' "$INST/logs/console.log" || true)"
  waits_other="$(grep 'OPERATOR_BACKUP_WAIT .*event=finished' "$INST/logs/console.log" | grep -vc 'code=OK' || true)"
  if [ "$ENDURANCE" -ge 60 ]; then
    if [ "$automatic_ok" -ge 2 ]; then rk_record automatic_backups PASS "$automatic_ok successful automatic backup windows observed"; else rk_record automatic_backups FAIL "only $automatic_ok successful automatic backup windows observed; expected at least 2"; fi
  fi
  if [ "$waits_ok" -gt 0 ] && [ "$waits_other" -eq 0 ]; then
    rk_record backup_wait_observed PASS "$waits_ok original account requests waited through real backup windows; no waiting failure"
  elif [ "$waits_other" -gt 0 ]; then
    rk_record backup_wait_observed FAIL "$waits_other waiting requests failed (successful=$waits_ok); inspect the fixed-code diagnostic lines"
  else
    rk_record backup_wait_observed NOTRUN "no account request naturally overlapped a backup; the real backup wait path needs a separate directed check"
  fi
else
  rk_record endurance NOTRUN "ROOMKIT_ENDURANCE_MINUTES=0"
fi
rk_step entry_final_stop 300 "${entry_env[@]}" bash "$SRC/tools/roomkit_linux.sh" stop --instance l3
cat "$RUN/entry_final_stop.out"
leftovers final

section "sentinel after the tests"
if kill -0 "$SENTINEL" 2>/dev/null && [ "$(start_time "$SENTINEL")" = "$SENTINEL_START" ]; then rk_record sentinel PASS "pid $SENTINEL is still the same live process (start_time unchanged)"; else rk_record sentinel FAIL "the sentinel process is gone or was replaced"; fi
kill "$SENTINEL" 2>/dev/null; wait "$SENTINEL" 2>/dev/null

section "final checks"
checked=("$ISO" "$INST" "$SRC/run" "$SRC/data/journal-$ROOMKIT_RUN_ID")
loose="$( { find "${checked[@]}" -type d -perm /077; find "${checked[@]}" -type f \( -name '*.sqlite*' -o -name '*.json' -o -name '*.jsonl' -o -name '*.key' -o -name '*.crt' -o -name '*.lock' -o -name '.gdignore' \) -perm /077; } 2>/dev/null | wc -l)"
if [ "$loose" -eq 0 ]; then rk_record private_modes PASS "Operator, instance, runtime and journal folders 700; databases, JSON, keys, certificates, audit and lock files 600"; else rk_record private_modes FAIL "$loose entries readable by group or others"; fi
echo "INFO test fixture entries outside the checked folders readable by group or others: $(find "$SRC/data" -mindepth 1 ! -path "$ISO*" ! -path "$INST*" ! -path "$SRC/data/journal-*" ! -name '*.log' -perm /077 2>/dev/null | wc -l)"
outside="$( { [ -e "$SRC/data/framework" ] && echo framework; [ -e "$SRC/artifacts/client" ] && echo artifacts-client; } | tr '\n' ' ')"
if [ -z "$outside" ]; then rk_record nothing_in_default_paths PASS "nothing was written to data/framework or artifacts/client"; else rk_record nothing_in_default_paths FAIL "written: $outside"; fi
home_after="$(ls -A "$REAL_HOME" | sort | tr '\n' ' ')"
if [ "$home_before" = "$home_after" ]; then rk_record real_home_untouched PASS "no new entry in the real home folder"; else rk_record real_home_untouched FAIL "the real home folder changed: before [$home_before] after [$home_after]"; fi

section "existing unit suite"
rk_step run_unit 600 "$GODOT" --headless --path "$SRC" --log-file "$RUN/run_unit.godot.log" --script res://tests/run_unit.gd
grep -E '^FAIL|UNIT_RESULT' "$RUN/run_unit.out"

section "not run here"
echo "NOT RUN Windows client to Linux (next stage, needs a firewall decision); public network; exported packages; host crash injection through the Windows identity helper (Linux: unexpected host exit in A6)"

section "after the run"
printf 'engine or pwsh processes of this user still running: %s\n' "$(pgrep -u "$(id -u)" -f 'Godot_v4|/pwsh' | wc -l)"
printf 'run folder size: %s, source data folder size: %s\n' "$(du -sh "$RUN" | awk '{print $1}')" "$(du -sh "$SRC/data" 2>/dev/null | awk '{print $1}')"
finish
