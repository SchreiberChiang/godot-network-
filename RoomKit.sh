#!/usr/bin/env bash
set -euo pipefail
umask 077
trap '' PIPE
fail() { echo "ROOMKIT_FAILED $*" >&2; exit 2; }
[ "$(uname -s)" = Linux ] || fail 'supported platforms: Windows and Linux'
# Do not resolve away links before the dispatcher can reject them.
root="$(cd -L -- "$(dirname -- "$0")" && pwd -L)"
cursor="$root"
while [ "$cursor" != / ]; do
  [ ! -L "$cursor" ] || fail 'linked installation path'
  cursor="$(dirname -- "$cursor")"
done
for file in RoomKit.sh tools tools/runtime_paths.sh tools/roomkit.ps1 tools/roomkit_entry.ps1; do
  [ ! -L "$root/$file" ] || fail "linked entry: $file"
done
. "$root/tools/runtime_paths.sh"
rk_runtime_paths "$root"
[[ "$RK_PWSH" = /* ]] && [ -x "$RK_PWSH" ] || fail 'pwsh missing; set ROOMKIT_PWSH to an installed absolute executable (nothing installed)'
export ROOMKIT_PWSH="$RK_PWSH"
cd -- "$root"
# Relative script argument keeps the management launcher from treating this
# short-lived dispatcher as a leftover engine process under the source root.
exec "$RK_PWSH" -NoLogo -NoProfile -NonInteractive -File tools/roomkit.ps1 "$@"
