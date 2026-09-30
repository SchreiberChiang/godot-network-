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

# rk_install_source <archive.tar> <destination folder> <expected sha256>
# Verifies the archive, unpacks it into a NEW folder and records one step. An
# existing folder is kept only when it came from the same archive. Any failure
# (hash, unpack, empty result) is recorded as FAIL and returns non-zero, so the
# caller must stop instead of testing a half-installed tree.
rk_install_source() {
  local archive="$1" destination="$2" expected="$3" actual
  actual="$(sha256sum "$archive" 2>/dev/null | awk '{print $1}')"
  if [ -z "$actual" ] || [ "$actual" != "$expected" ]; then rk_record source FAIL "archive hash mismatch or unreadable archive"; return 1; fi
  if [ -e "$destination" ]; then
    if [ "$(cat "$destination.sha256" 2>/dev/null)" = "$actual" ]; then rk_record source PASS "kept existing folder from the same archive sha256=$actual"; return 0; fi
    rk_record source FAIL "folder exists with a different or unknown archive"; return 1
  fi
  if ! mkdir -p "$destination" || ! tar -xf "$archive" -C "$destination" 2>"$RK_OUT/source-unpack.err"; then
    rm -rf "$destination"
    rk_record source FAIL "archive could not be unpacked; nothing installed"; return 1
  fi
  if [ "$(find "$destination" -type f | wc -l)" -eq 0 ]; then rm -rf "$destination"; rk_record source FAIL "archive was empty; nothing installed"; return 1; fi
  printf '%s\n' "$actual" > "$destination.sha256"
  rk_record source PASS "installed sha256=$actual files=$(find "$destination" -type f | wc -l)"
}
