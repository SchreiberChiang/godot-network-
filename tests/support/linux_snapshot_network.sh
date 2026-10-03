#!/usr/bin/env bash
# Source-only snapshot acceptance; use existing Godot 4.7.2 and pwsh 7.
# Usage: bash tests/support/linux_snapshot_network.sh /absolute/godot /absolute/pwsh [dtls|enet]
# The default runs full DTLS capacity and recovery once. No installs or services.
set -eu
umask 077
trap '' PIPE
project="$(cd "$(dirname "$0")/../.." && pwd -P)"
godot="${1:?absolute Godot 4.7.2 executable required}"
pwsh="${2:?absolute pwsh 7 executable required}"
mode="${3:-dtls}"
case "$mode" in dtls|enet) ;; *) printf 'Expected dtls or enet\n' >&2; exit 2 ;; esac
case "$godot" in /*) ;; *) printf 'Godot path must be absolute\n' >&2; exit 2 ;; esac
case "$pwsh" in /*) ;; *) printf 'pwsh path must be absolute\n' >&2; exit 2 ;; esac
[ -x "$godot" ] && [ -x "$pwsh" ] || { printf 'Executable not found\n' >&2; exit 2; }
for relative in logs logs/shooter-snapshot-nettest logs/shooter-snapshot-nettest/batches; do
  [ ! -L "$project/$relative" ] || { printf 'Evidence directory is a symlink\n' >&2; exit 2; }
done
mkdir -p "$project/logs/shooter-snapshot-nettest/batches"
root="$(mktemp -d "$project/logs/shooter-snapshot-nettest/batches/linux-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
mkdir -p "$root"/{home,xdg/config,xdg/cache,xdg/data,xdg/state,xdg/runtime,tmp}
printf 'LINUX_SNAPSHOT_BATCH mode=%s evidence=%s\n' "$mode" "$root"
extra=()
[ "$mode" != dtls ] || extra=(-Dtls)
if HOME="$root/home" XDG_CONFIG_HOME="$root/xdg/config" XDG_CACHE_HOME="$root/xdg/cache" \
  XDG_DATA_HOME="$root/xdg/data" XDG_STATE_HOME="$root/xdg/state" XDG_RUNTIME_DIR="$root/xdg/runtime" \
  TMPDIR="$root/tmp" TMP="$root/tmp" TEMP="$root/tmp" \
  ROOMKIT_GODOT="$godot" ROOMKIT_PWSH="$pwsh" POWERSHELL_TELEMETRY_OPTOUT=1 \
  POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1 \
  "$pwsh" -NoProfile -NonInteractive -File "$project/tests/test_shooter_snapshot_network.ps1" \
    -Godot "$godot" "${extra[@]}" > "$root/driver.stdout" 2> "$root/driver.stderr"; then
  code=0
else
  code=$?
fi
cat "$root/driver.stdout"
if [ -s "$root/driver.stderr" ]; then cat "$root/driver.stderr" >&2; [ "$code" != 0 ] || code=1; fi
printf '%s\n' "$code" > "$root/driver.exit"
printf 'LINUX_SNAPSHOT_BATCH_RESULT mode=%s exit=%s evidence=%s\n' "$mode" "$code" "$root"
exit "$code"
