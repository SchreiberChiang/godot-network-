# Shared step recorder for the RoomKit Linux test scripts (sourced, not executed).
# Every step leaves one result line; rk_summary prints them all and returns
# non-zero when any step failed, timed out or printed a script error. A
# "COMPLETE" marker printed by a caller only means execution reached the end.
# Set RK_OUT to a writable folder before use.
rk_names=()
rk_states=()
rk_details=()
rk_failures=0

# rk_record <name> <PASS|FAIL|TIMEOUT|NOTRUN> <detail>
rk_record() {
  rk_names+=("$1"); rk_states+=("$2"); rk_details+=("$3")
  case "$2" in PASS|NOTRUN) ;; *) rk_failures=$((rk_failures + 1)) ;; esac
  printf 'STEP %-8s %s | %s\n' "$2" "$1" "$3"
}

# rk_step <name> <timeout seconds> <command...>
# Output goes to $RK_OUT/<name>.out. Fails on a non-zero exit, a timeout, or any
# "SCRIPT ERROR" line even when the command itself exits 0.
rk_step() {
  local name="$1" limit="$2"; shift 2
  local out="$RK_OUT/$name.out" code errors result state detail
  timeout "$limit" "$@" > "$out" 2>&1
  code=$?
  errors="$(grep -c 'SCRIPT ERROR' "$out")"
  result="$(grep -E '_RESULT|REGRESSION|_PORTABLE' "$out" | tail -n 1)"
  detail="exit=$code script_errors=$errors ${result:-no result line}"
  if [ "$code" -eq 124 ]; then state=TIMEOUT
  elif [ "$code" -ne 0 ] || [ "$errors" -ne 0 ]; then state=FAIL
  else state=PASS; fi
  # A known platform limit stays a failure; it is only labelled so it is not
  # mistaken for a new regression.
  if [ "$state" = FAIL ] && grep -q 'FAIL sim manager initialized' "$out"; then detail="$detail [known limit: room manager returns UNSUPPORTED_PLATFORM off Windows]"; fi
  rk_record "$name" "$state" "$detail"
  if [ "$state" != PASS ]; then grep -E '^FAIL|SCRIPT ERROR|^ERROR' "$out" | head -n 8 | sed 's/^/    /'; fi
}

# rk_summary: prints the table; returns 0 only when every step passed.
rk_summary() {
  local i
  printf '\n## summary\n'
  for i in "${!rk_names[@]}"; do printf '%-8s %s | %s\n' "${rk_states[$i]}" "${rk_names[$i]}" "${rk_details[$i]}"; done
  printf 'steps=%s failures=%s\n' "${#rk_names[@]}" "$rk_failures"
  [ "$rk_failures" -eq 0 ]
}
