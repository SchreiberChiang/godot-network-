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

# Source install: a good archive installs; a wrong hash, a corrupt archive and a
# clashing folder are failures and leave nothing half-installed.
mkdir -p "$work/src-in/tools" && echo "x" > "$work/src-in/tools/a.txt" && tar -cf "$work/good.tar" -C "$work/src-in" .
good_sha="$(sha256sum "$work/good.tar" | awk '{print $1}')"
head -c 700 "$work/good.tar" > "$work/corrupt.tar"
corrupt_sha="$(sha256sum "$work/corrupt.tar" | awk '{print $1}')"

( RK_OUT="$work/g"; mkdir -p "$RK_OUT"; . "$lib"
  rk_install_source "$work/good.tar" "$work/g/src" "$good_sha" >/dev/null || exit 9
  [ -f "$work/g/src/tools/a.txt" ] || exit 9
  rk_install_source "$work/good.tar" "$work/g/src" "$good_sha" >/dev/null || exit 9
  rk_summary >/dev/null ); expect "$?" 0 "a good source archive installs and is kept on a second run"

( RK_OUT="$work/h"; mkdir -p "$RK_OUT"; . "$lib"
  rk_install_source "$work/good.tar" "$work/h/src" "0000" >/dev/null && exit 9
  [ ! -e "$work/h/src" ] || exit 9
  rk_summary >/dev/null ); expect "$?" 1 "a source archive with the wrong hash fails and installs nothing"

( RK_OUT="$work/i"; mkdir -p "$RK_OUT"; . "$lib"
  rk_install_source "$work/corrupt.tar" "$work/i/src" "$corrupt_sha" >/dev/null && exit 9
  [ ! -e "$work/i/src" ] || exit 9
  rk_summary >/dev/null ); expect "$?" 1 "a corrupt source archive fails to unpack and leaves no folder"

( RK_OUT="$work/j"; mkdir -p "$RK_OUT" "$work/j/src"; . "$lib"
  rk_install_source "$work/good.tar" "$work/j/src" "$good_sha" >/dev/null && exit 9
  rk_summary >/dev/null ); expect "$?" 1 "an existing folder from another archive is refused"

( RK_OUT="$work/k"; mkdir -p "$RK_OUT"; . "$lib"
  rk_step digest 10 bash -c 'echo "FAIL shooter prepared tree gives the expected digest"; echo "CONTENT_DIGEST_PORTABLE passed=10 failed=1 not_run=0"; exit 1' >/dev/null
  rk_step later 10 true >/dev/null
  rk_summary >/dev/null ); expect "$?" 1 "a failed digest step fails the run even when later steps pass"

if [ "$bad" -eq 0 ]; then echo "LINUX_TEST_LIB_SELFTEST passed=11 failed=0"; else echo "LINUX_TEST_LIB_SELFTEST failed"; fi
exit "$bad"
