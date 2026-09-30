#!/bin/bash
# Test child for tests/run_posix_process.gd. Uses only shell builtins while it
# waits, so a forced stop leaves no grandchildren behind.
#   --mode=exit --code=N      exit immediately with N
#   --mode=hang --fifo=PATH   block forever opening a FIFO nobody writes to
#   --mode=echo               copy standard input to standard output until EOF
mode=exit; code=0; fifo=""
for argument in "$@"; do
  case "$argument" in
    --mode=*) mode="${argument#--mode=}" ;;
    --code=*) code="${argument#--code=}" ;;
    --fifo=*) fifo="${argument#--fifo=}" ;;
  esac
done
case "$mode" in
  exit) exit "$code" ;;
  hang) while true; do read -r _ < "$fifo"; done ;;
  echo) while IFS= read -r line; do printf '%s\n' "$line"; done ;;
  *) exit 64 ;;
esac
