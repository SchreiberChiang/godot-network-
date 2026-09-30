#!/usr/bin/env bash
# RoomKit: install test dependencies and run isolated checks on a Linux test
# machine. Everything stays under ~/roomkit: downloads, versioned tool folders,
# the source of one exact commit, and a per-run output folder. No sudo, no PATH
# or login changes, no firewall changes, no services, no real data. Existing
# folders are never overwritten. Engine and PowerShell config, cache and temp
# files are redirected into the run folder (XDG_*, TMPDIR).
#
# The two official packages are downloaded here from GitHub Releases unless they
# were shipped next to this script, and are installed only after their hashes
# match the official values (Godot: SHA512-SUMS.txt of the release; PowerShell:
# the SHA256 published in the release's hashes.sha256, passed in by the caller).
# Next to this script: roomkit-src.tar, linux_test_lib.sh,
# driver/content_digest_portable.ps1. The exit code is non-zero when any step
# failed, timed out or printed a script error.
# Required environment: ROOMKIT_COMMIT, ROOMKIT_RUN_ID, ROOMKIT_SRC_SHA256,
#   ROOMKIT_GODOT_SHA512, ROOMKIT_PWSH_SHA256, ROOMKIT_EXPECT_SHOOTER,
#   ROOMKIT_EXPECT_TURNS
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/roomkit"
DOWNLOADS="$ROOT/downloads"
GODOT_NAME="Godot_v4.7.2-stable_linux.x86_64"
GODOT_URL="https://github.com/godotengine/godot/releases/download/4.7.2-stable"
PWSH_NAME="powershell-7.6.6-linux-x64.tar.gz"
PWSH_URL="https://github.com/PowerShell/PowerShell/releases/download/v7.6.6"
GODOT_DIR="$ROOT/tools/godot/4.7.2-stable"
GODOT="$GODOT_DIR/$GODOT_NAME"
PWSH_DIR="$ROOT/tools/pwsh/7.6.6"
PWSH="$PWSH_DIR/pwsh"
SRC="$ROOT/src/$ROOMKIT_COMMIT"
RUN="$ROOT/runs/$ROOMKIT_RUN_ID"
blocked=0
section() { printf '\n## %s\n' "$1"; }
fail() { printf 'BLOCKED %s\n' "$1"; blocked=1; }

if [ -e "$RUN" ]; then echo "BLOCKED run folder already exists: $RUN"; exit 3; fi
mkdir -p "$RUN/tmp" "$RUN/xdg/config" "$RUN/xdg/cache" "$RUN/xdg/data" "$DOWNLOADS" "$ROOT/tools/godot" "$ROOT/tools/pwsh" "$ROOT/src"
export XDG_CONFIG_HOME="$RUN/xdg/config" XDG_CACHE_HOME="$RUN/xdg/cache" XDG_DATA_HOME="$RUN/xdg/data"
export TMPDIR="$RUN/tmp"
export POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1

section "supplementary read-only checks"
printf 'node: %s\n' "$(command -v node >/dev/null 2>&1 && node --version || echo 'not found')"
printf 'system sqlite (via python3 sqlite3 module): %s\n' "$(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)' 2>&1)"
printf 'disk before: %s\n' "$(df -h "$HOME" | awk 'NR==2{print $4" available"}')"

section "official packages (shipped copy or download, then hash check)"
# fetch <file name> <base url> <expected hash> <sha256sum|sha512sum>
fetch() {
  target="$DOWNLOADS/$1"
  if [ -f "$HERE/$1" ] && [ ! -f "$target" ]; then cp "$HERE/$1" "$target" && echo "COPIED $1 from the bundle"; fi
  if [ -f "$target" ] && [ "$($4 "$target" | awk '{print $1}')" = "$3" ]; then echo "PASS $1 already present and matches the official hash"; return 0; fi
  echo "DOWNLOADING $2/$1"
  started=$(date +%s)
  curl -fsSL --retry 5 --retry-delay 3 -C - --connect-timeout 20 --max-time 1500 -o "$target" "$2/$1"
  code=$?
  printf 'curl exit=%s seconds=%s bytes=%s\n' "$code" "$(( $(date +%s) - started ))" "$(stat -c %s "$target" 2>/dev/null || echo 0)"
  if [ "$code" -ne 0 ]; then fail "$1 could not be downloaded on this machine (partial file kept for resume)"; return 1; fi
  got="$($4 "$target" | awk '{print $1}')"
  if [ "$got" = "$3" ]; then echo "PASS $1 matches the official hash (${got:0:16}...)"; else fail "$1 hash mismatch (got ${got:0:16}...); not installed"; return 1; fi
}
fetch "$GODOT_NAME.zip" "$GODOT_URL" "$ROOMKIT_GODOT_SHA512" sha512sum
fetch "$PWSH_NAME" "$PWSH_URL" "$ROOMKIT_PWSH_SHA256" sha256sum
src_tar="$HERE/roomkit-src.tar"
gotsrc="$(sha256sum "$src_tar" | awk '{print $1}')"
if [ "$gotsrc" = "$ROOMKIT_SRC_SHA256" ]; then echo "PASS source archive matches the hash recorded on Windows ($gotsrc)"; else fail "source archive SHA256 mismatch"; fi
if [ "$blocked" -ne 0 ]; then echo "ROOMKIT_LINUX_SETUP_BLOCKED packages"; exit 4; fi

section "install (versioned folders, never overwritten)"
if [ -e "$GODOT_DIR" ]; then echo "KEPT existing $GODOT_DIR (not overwritten)"; else mkdir "$GODOT_DIR" && unzip -q "$DOWNLOADS/$GODOT_NAME.zip" -d "$GODOT_DIR" && chmod u+x "$GODOT" && echo "INSTALLED $GODOT_DIR"; fi
if [ -e "$PWSH_DIR" ]; then echo "KEPT existing $PWSH_DIR (not overwritten)"; else mkdir "$PWSH_DIR" && tar -xzf "$DOWNLOADS/$PWSH_NAME" -C "$PWSH_DIR" && chmod u+x "$PWSH" && echo "INSTALLED $PWSH_DIR"; fi
if [ -e "$SRC" ]; then
  if [ "$(cat "$SRC.sha256" 2>/dev/null)" = "$gotsrc" ]; then echo "KEPT existing $SRC (same archive hash)"; else fail "source folder exists with a different or unknown archive hash: $SRC"; fi
else
  mkdir "$SRC" && tar -xf "$src_tar" -C "$SRC" && printf '%s\n' "$gotsrc" > "$SRC.sha256" && echo "INSTALLED $SRC"
fi
if [ ! -x "$GODOT" ]; then fail "Godot binary missing after install"; fi
if [ ! -x "$PWSH" ]; then fail "pwsh binary missing after install"; fi
if [ "$blocked" -ne 0 ]; then echo "ROOMKIT_LINUX_SETUP_BLOCKED install"; exit 5; fi
du -sh "$GODOT_DIR" "$PWSH_DIR" "$SRC" 2>/dev/null
printf 'source files: %s; .gd/.json/.ps1 files containing CRLF: %s\n' "$(find "$SRC" -type f | wc -l)" "$(grep -rlI $'\r$' --include='*.gd' --include='*.json' --include='*.ps1' "$SRC" 2>/dev/null | wc -l)"

section "versions"
printf 'godot: '; "$GODOT" --version 2>&1 | head -n 1
printf 'pwsh: '; "$PWSH" -NoProfile -Command '"{0} {1} {2}" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription' 2>&1 | head -n 2

RK_OUT="$RUN"
. "$HERE/linux_test_lib.sh"
section "production PowerShell digest (portable driver, before any engine run)"
rk_step digest 600 "$PWSH" -NoProfile -File "$HERE/driver/content_digest_portable.ps1" -Source "$SRC" -Work "$RUN/digest-work" -ExpectShooter "$ROOMKIT_EXPECT_SHOOTER" -ExpectTurns "$ROOMKIT_EXPECT_TURNS"
cat "$RUN/digest.out"
if command -v node >/dev/null 2>&1; then
  printf 'node reference on LF fixture: %s (expected 05f794ef76f0)\n' "$(node "$SRC/tests/content_digest_reference.cjs" "$RUN/digest-work/fixture/lf" 2>&1)"
else
  echo "NOT RUN independent Node reference (node is not installed; not installing it for this)"
fi

section "pure GDScript tests (headless)"
touch "$RUN/.before-tests"
mkdir -p "$RUN/sound"
godot_test() { name="$1"; shift; rk_step "$name" 600 "$GODOT" --headless --path "$SRC" --log-file "$RUN/$name.godot.log" --script "res://tests/$name.gd" -- "$@"; }
godot_test run_shooter
godot_test run_framework_feedback
godot_test run_client_sound "--work=$RUN/sound"
godot_test run_room_disappear_regression
godot_test run_managed_contracts
godot_test run_unit
printf 'files created under the source folder by the tests: %s\n' "$(find "$SRC" -type f -newer "$RUN/.before-tests" | wc -l)"
find "$SRC" -type f -newer "$RUN/.before-tests" | sed "s|^$SRC/||" | cut -d/ -f1 | sort | uniq -c | head -n 8 | sed 's/^/    /'
printf 'leftover godot or pwsh processes of this user: %s\n' "$(pgrep -u "$(id -u)" -f "$ROOT/tools" | wc -l)"

section "footprint"
printf 'roomkit total: %s\n' "$(du -sh "$ROOT" | awk '{print $1}')"
printf 'disk after: %s\n' "$(df -h "$HOME" | awk 'NR==2{print $4" available"}')"
printf 'config, cache and temp files were redirected to %s\n' "$RUN"
rk_summary
status=$?
# COMPLETE only says the script reached its end; the exit code carries the verdict.
echo "ROOMKIT_LINUX_SETUP_COMPLETE run=$ROOMKIT_RUN_ID failures=$rk_failures"
exit "$status"
