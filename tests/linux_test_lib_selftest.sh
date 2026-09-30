#!/usr/bin/env bash
# Failure injection for tools/linux_test_lib.sh: a failing command, a timeout and
# a script error hidden behind exit 0 must each be recorded and must make the
# summary return non-zero; an all-pass run must return zero. Needs only bash and
# coreutils, so it runs in Git Bash on Windows and on the Linux test machine.
# Usage: bash tests/linux_test_lib_selftest.sh <path to linux_test_lib.sh>
set -u
lib="$1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bad=0
expect() { if [ "$1" = "$2" ]; then printf 'PASS %s\n' "$3"; else printf 'FAIL %s (got %s, wanted %s)\n' "$3" "$1" "$2"; bad=1; fi; }

# Each scenario runs in a subshell so the recorder state starts clean.
( RK_OUT="$work/a"; mkdir -p "$RK_OUT"; . "$lib"
  rk_step ok 10 bash -c 'echo "X_RESULT passed=1 failed=0"' >/dev/null
  rk_summary >/dev/null ); expect "$?" 0 "all steps passing gives exit 0"

( RK_OUT="$work/b"; mkdir -p "$RK_OUT"; . "$lib"
  rk_step ok 10 true >/dev/null
  rk_step broken 10 bash -c 'echo "X_RESULT passed=1 failed=1"; exit 1' >/dev/null
  rk_summary >/dev/null ); expect "$?" 1 "a failing command gives a non-zero exit"

( RK_OUT="$work/c"; mkdir -p "$RK_OUT"; . "$lib"
  rk_step slow 1 sleep 5 >/dev/null
  [ "${rk_states[0]}" = TIMEOUT ] || exit 9
  rk_summary >/dev/null ); expect "$?" 1 "a timeout is recorded as TIMEOUT and gives a non-zero exit"

( RK_OUT="$work/d"; mkdir -p "$RK_OUT"; . "$lib"
  rk_step hidden 10 bash -c 'echo "SCRIPT ERROR: something"; echo "X_RESULT passed=3 failed=0"; exit 0' >/dev/null
  [ "${rk_states[0]}" = FAIL ] || exit 9
  rk_summary >/dev/null ); expect "$?" 1 "a script error behind exit 0 is a failure"

( RK_OUT="$work/e"; mkdir -p "$RK_OUT"; . "$lib"
  rk_step unit 10 bash -c 'echo "FAIL sim manager initialized"; echo "UNIT_RESULT passed=292 failed=1"; exit 1' >/dev/null
  case "${rk_details[0]}" in *"known limit"*) ;; *) exit 9 ;; esac
  rk_summary >/dev/null ); expect "$?" 1 "the known platform limit is labelled but still fails"

( RK_OUT="$work/f"; mkdir -p "$RK_OUT"; . "$lib"
  rk_step first 10 false >/dev/null
  rk_step second 10 true >/dev/null
  [ "${#rk_names[@]}" -eq 2 ] && [ "${rk_states[1]}" = PASS ] || exit 9
  rk_summary >/dev/null ); expect "$?" 1 "later steps still run and are recorded after a failure"

if [ "$bad" -eq 0 ]; then echo "LINUX_TEST_LIB_SELFTEST passed=6 failed=0"; else echo "LINUX_TEST_LIB_SELFTEST failed"; fi
exit "$bad"
