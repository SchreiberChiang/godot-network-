#!/usr/bin/env bash
# Read-only progress of the newest RoomKit L3 acceptance on the Linux test machine.
# Run from Windows without copying anything:  ssh <host> "bash -s" < tools\linux_progress.sh
# Reads ~/roomkit/incoming/*/console.txt only; starts, stops and writes nothing.
# The percentage is an estimate from typical section durations (minutes below),
# not a measurement; the endurance section dominates.
set -u
console="$(ls -t "$HOME"/roomkit/incoming/*/console.txt 2>/dev/null | head -n 1)"
if [ -z "$console" ]; then echo "no acceptance console found under ~/roomkit/incoming"; exit 0; fi
sections=("A1" "A2" "A3" "A4" "A5" "A6" "B1" "B2" "B3" "B4" "C1" "C2" "C3" "D." "E." "sentinel after" "final checks" "existing unit" "after the run")
minutes=(0.3 0.1 1 0.3 1.3 1.3 1.8 0.1 3 2.3 0.3 9 6 5 62 0.1 0.2 1 0.1)
total=0; for m in "${minutes[@]}"; do total="$(awk -v a="$total" -v b="$m" 'BEGIN {print a + b}')"; done
current=-1
for i in "${!sections[@]}"; do
  if grep -q "^## ${sections[$i]}" "$console"; then current=$i; fi
done
done_minutes=0
for ((i = 0; i < current; i++)); do done_minutes="$(awk -v a="$done_minutes" -v b="${minutes[$i]}" 'BEGIN {print a + b}')"; done
started="$(grep -m1 '^## machine' "$console" | sed -n 's/.*(\(.*\)).*/\1/p')"
section_line="$(grep '^## ' "$console" | tail -n 1)"
section_time="$(echo "$section_line" | sed -n 's/.*(\(..:..:..\)).*/\1/p')"
in_section=0
if [ -n "$section_time" ]; then in_section="$(( ($(date +%s) - $(date -d "$section_time" +%s)) / 60 ))"; fi
if [ "$current" -ge 0 ]; then
  part="$(awk -v e="$in_section" -v m="${minutes[$current]}" 'BEGIN {x = e; if (x > m) x = m; print x}')"
  done_minutes="$(awk -v a="$done_minutes" -v b="$part" 'BEGIN {print a + b}')"
fi
percent="$(awk -v d="$done_minutes" -v t="$total" 'BEGIN {printf "%d", 100 * d / t}')"
if grep -q 'ROOMKIT_LINUX_L3_COMPLETE' "$console"; then percent=100; fi
echo "console: $console"
echo "started: ${started:-?}  now: $(date '+%H:%M:%S')"
echo "section: ${section_line#\#\# }  (running ${in_section} min)"
echo "estimated progress: ${percent}%  (about $(awk -v d="$done_minutes" -v t="$total" 'BEGIN {printf "%d", t - d}') min left if nothing stalls)"
echo "steps so far: $(grep -c '^STEP PASS' "$console") passed, $(grep -cE '^STEP (FAIL|TIMEOUT)' "$console") failed"
grep -E '^STEP (FAIL|TIMEOUT)' "$console" | sed 's/^/  /'
grep -E 'ENDURANCE_PROGRESS' "$console" | tail -n 1 | cut -c1-200
tail -n 1 "$console" | grep 'ROOMKIT_LINUX_L3_COMPLETE' || true
