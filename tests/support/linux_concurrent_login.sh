#!/usr/bin/env bash
# Parent of pwsh and every engine: private HOME/XDG/TMP, 077, ignored SIGPIPE.
# Usage: bash tests/support/linux_concurrent_login.sh /absolute/godot /absolute/pwsh [4|8|all]
set -eu
umask 077
trap '' PIPE
project="$(cd "$(dirname "$0")/../.." && pwd -P)"
godot="${1:?absolute Godot 4.7.2 executable required}"
pwsh="${2:?absolute pwsh 7 executable required}"
size="${3:-all}"
case "$size" in 4|8|all) ;; *) printf 'Expected 4, 8 or all\n' >&2; exit 2 ;; esac
case "$godot" in /*) ;; *) printf 'Godot path must be absolute\n' >&2; exit 2 ;; esac
case "$pwsh" in /*) ;; *) printf 'pwsh path must be absolute\n' >&2; exit 2 ;; esac
[ -x "$godot" ] && [ -x "$pwsh" ] || { printf 'Executable not found\n' >&2; exit 2; }
[ ! -L "$project/data" ] || { printf 'data is a symlink\n' >&2; exit 2; }
mkdir -p "$project/data"
batch="$(mktemp -d "$project/data/linux-concurrent-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
printf 'LINUX_CONCURRENT_BATCH evidence=%s\n' "$batch"
groups=("$size")
[ "$size" != all ] || groups=(4 8)
status=0
for clients in "${groups[@]}"; do
  root="$batch/group-$clients"
  mkdir -p "$root"/{home,xdg/config,xdg/cache,xdg/data,xdg/state,xdg/runtime,tmp,logs}
  # These assignments apply only to the test subprocess. They are set before
  # pwsh starts, rather than changing pwsh's cached home after initialization.
  if HOME="$root/home" XDG_CONFIG_HOME="$root/xdg/config" XDG_CACHE_HOME="$root/xdg/cache" \
    XDG_DATA_HOME="$root/xdg/data" XDG_STATE_HOME="$root/xdg/state" XDG_RUNTIME_DIR="$root/xdg/runtime" \
    TMPDIR="$root/tmp" TMP="$root/tmp" TEMP="$root/tmp" \
    ROOMKIT_GODOT="$godot" ROOMKIT_PWSH="$pwsh" POWERSHELL_TELEMETRY_OPTOUT=1 \
    POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    "$pwsh" -NoProfile -NonInteractive -File "$project/tests/test_linux_concurrent_login.ps1" \
      -Godot "$godot" -Clients "$clients" -RunRoot "$root" \
      > "$root/logs/driver.stdout" 2> "$root/logs/driver.stderr"; then
    code=0
  else
    code=$?
    status=1
  fi
  cat "$root/logs/driver.stdout"
  if [ -s "$root/logs/driver.stderr" ]; then cat "$root/logs/driver.stderr" >&2; status=1; fi
  printf 'LINUX_CONCURRENT_GROUP clients=%s exit=%s evidence=%s\n' "$clients" "$code" "$root"
  printf '%s\n' "$code" > "$root/logs/driver.exit"
done
printf 'LINUX_CONCURRENT_BATCH_RESULT exit=%s evidence=%s\n' "$status" "$batch"
exit "$status"
