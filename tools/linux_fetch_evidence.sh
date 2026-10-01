#!/usr/bin/env bash
# Read-only: packs the evidence of one L3 acceptance run as a tar on stdout.
# Run from Windows without copying anything:
#   ssh <host> "bash -s -- <run id> <source id>" < tools\linux_fetch_evidence.sh > evidence.tar
# Contains step outputs, engine/Operator/host logs and client reports. Leaves out
# databases, keys, certificates, the acceptance credential files and the test
# context (it holds a session token) and client bootstraps. Also writes a listing
# of this source's processes still running and of entries readable by others.
# Starts, stops and changes nothing.
set -u
run_id="$1"; source_id="$2"
[[ "$run_id" =~ ^[0-9]{14}-[0-9a-f]{6}$ ]] && [[ "$source_id" =~ ^[0-9a-f]{12}-worktree-[0-9a-f]{12}(-r[0-9a-f]{6})?$ ]] || { echo "invalid ids" >&2; exit 2; }
ROOT="$HOME/roomkit"
RUN="$ROOT/runs/$run_id"
SRC="$ROOT/src/$source_id"
INST="$SRC/data/instance-l3"
STAGE="$(mktemp -d "$ROOT/runs/fetch-XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
{
  echo "== processes started from this source (pid ppid state started command)"
  for pid in $(pgrep -u "$(id -u)" -f "$SRC"); do
    printf '%s %s %s %s ' "$pid" "$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)" "$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null)" "$(ps -o lstart= -p "$pid" 2>/dev/null)"
    { tr '\0' ' ' < "/proc/$pid/cmdline"; } 2>/dev/null; echo
  done
  echo "== listeners and UDP sockets of this user on 28391-28700"
  ss -H -lntup 2>/dev/null | awk '{split($5, a, ":"); p = a[length(a)]; if (p >= 28391 && p <= 28700) print}'
  ss -H -lnuap 2>/dev/null | awk '{split($5, a, ":"); p = a[length(a)]; if (p >= 28391 && p <= 28700) print}'
  echo "== entries readable by group or others (instance, runtime, Operator test folders)"
  find "$INST" "$SRC/run" "$SRC"/data/l3op-* "$SRC"/data/journal-* -perm /077 ! -name '*.log' -printf '%m %y %p\n' 2>/dev/null | sed "s#$SRC/##"
  echo "== runtime folder"
  ls -la "$SRC/run" 2>/dev/null
} > "$STAGE/state.txt"
mkdir -p "$STAGE/run" "$STAGE/instance"
cp "$RUN"/*.out "$RUN"/*.log "$STAGE/run/" 2>/dev/null
cp "$ROOT/incoming/$run_id/console.txt" "$STAGE/console.txt" 2>/dev/null
if [ -d "$INST" ]; then
  (cd "$INST" && find logs data/logs acceptance -type f \
      ! -name '*.sqlite*' ! -name '*.key' ! -name '*.crt' ! -name 'bootstrap.json' \
      ! -name 'admin.json' ! -name 'persist.json' ! -name 'test-context.json' ! -name 'endurance-accounts.json' \
      ! -name '*.tmp' -size -20M 2>/dev/null) | while read -r file; do
    mkdir -p "$STAGE/instance/$(dirname "$file")"
    cp "$INST/$file" "$STAGE/instance/$file"
  done
fi
for folder in "$SRC"/logs/*; do [ -d "$folder" ] && mkdir -p "$STAGE/source-logs" && cp -r "$folder" "$STAGE/source-logs/" 2>/dev/null; done
tar -cf - -C "$STAGE" .
