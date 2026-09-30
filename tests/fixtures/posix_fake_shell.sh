#!/bin/bash
# Stand-in for the PowerShell executable in tests/run_posix_helper.gd. It ignores
# the script it is asked to run and misbehaves as ROOMKIT_FAKE_SHELL_MODE says, so
# the limits of host/platform/posix_helper.gd can be tested without PowerShell.
# Shell builtins only: a forced stop must leave no grandchild holding a pipe.
mode="${ROOMKIT_FAKE_SHELL_MODE:-ok}"
# Blocks without reading standard input: opening a FIFO nobody writes to.
block() { local never; while true; do read -r never < "$ROOMKIT_FAKE_SHELL_FIFO"; done; }
flood() { local chunk i; printf -v chunk '%01024d' 0; for ((i = 0; i < $1; i++)); do printf '%s' "$chunk"; done; }
case "$mode" in
  ok)            IFS= read -r line; printf '{"ok":true,"line":"%s","arguments":%d,"file":"%s"}\n' "$line" "$#" "${4##*/}" ;;
  ok-noinput)    printf '{"ok":true,"arguments":%d,"last":"%s"}\n' "$#" "${!#}" ;;
  hang)          IFS= read -r line; block ;;
  hang-noread)   block ;;
  stderr-flood)  IFS= read -r line; flood 2048 >&2; printf '{"ok":true,"line":"%s"}\n' "$line" ;;
  stdout-flood)  IFS= read -r line; flood 6144; printf '\n' ;;
  exit-3)        IFS= read -r line; printf '{"ok":true}\n'; exit 3 ;;
  garbage)       IFS= read -r line; printf 'not json\n' ;;
  stdout-drip)   IFS= read -r line; while true; do printf x; done ;;
  stderr-drip)   IFS= read -r line; while true; do flood 64; done >&2 ;;
  late-line)     IFS= read -r line; read -r -t 0.8 _; printf '{"ok":true,"late":true}\n' ;;
  worker-drip)   IFS= read -r line; while true; do flood 64; done >&2 ;;
  worker-then-drip) IFS= read -r line; printf '{"ok":true,"code":""}\n'; while true; do printf x >&2; done ;;
  worker-late)   while IFS= read -r line && [ -n "$line" ]; do read -r -t 0.8 _; printf '{"ok":true,"code":"","late":true}\n'; done ;;
  stderr-hang)   IFS= read -r line; flood 64 >&2; block ;;
  silent-close)  IFS= read -r line; exec 1>&-; block ;;
  worker)        while IFS= read -r line && [ -n "$line" ]; do printf '{"ok":true,"code":"","echo":"%s"}\n' "$line"; done ;;
  worker-once)   IFS= read -r line; printf '{"ok":true,"code":"","echo":"%s"}\n' "$line" ;;
  worker-mute)   block ;;
  worker-noisy)  while IFS= read -r line && [ -n "$line" ]; do flood 256 >&2; printf '{"ok":true,"code":"","echo":"%s"}\n' "$line"; done ;;
  *)             exit 64 ;;
esac
