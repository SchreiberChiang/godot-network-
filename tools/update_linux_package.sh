#!/usr/bin/env bash
# Offline update of a stopped, exported Linux instance. No signals or installs.
# prepare --old-package ABS --new-package ABS --instance NAME
# verify|status|seal|rollback --new-package ABS --instance NAME
# seal is the explicit point after which rollback is forbidden. It does not
# start a service. rollback never rewrites old data, deletes a snapshot or starts
# an old service; it only cancels an untouched, unsealed candidate.
set -euo pipefail
umask 077
trap '' PIPE
PWSH="${ROOMKIT_PWSH:-$HOME/roomkit/tools/pwsh/7.6.6/pwsh}"
[[ "$PWSH" = /* ]] && [ -x "$PWSH" ] || { echo 'ROOMKIT_UPDATE_FAILED code=PWSH_NOT_FOUND' >&2; exit 64; }
exec "$PWSH" -NoProfile -NonInteractive -File "$(dirname "$0")/update_linux_package.ps1" "$@"
