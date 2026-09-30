#!/usr/bin/env bash
# RoomKit L1: storage slice on the Linux test machine, isolated under ~/roomkit.
# Reuses the already installed, versioned pwsh and Godot folders (nothing is
# downloaded or installed), unpacks the shipped source snapshot into a NEW source
# folder, and runs the portable drivers on brand-new fake data. No sudo, no
# services, no firewall or login changes, no real data.
# The exit code is non-zero when any step fails, times out or prints a script
# error (tools/linux_test_lib.sh); COMPLETE only marks the end of execution.
#
# Next to this script: linux_test_lib.sh, linux_test_lib_selftest.sh,
#   roomkit-src.tar, foreign/accounts.sqlite, foreign/assets.sqlite (test
#   databases generated on Windows by the same driver).
# Required environment: ROOMKIT_SOURCE_ID, ROOMKIT_RUN_ID, ROOMKIT_SRC_SHA256,
#   ROOMKIT_EXPECT_SHOOTER, ROOMKIT_EXPECT_TURNS
set -u
umask 077
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/roomkit"
PWSH="$ROOT/tools/pwsh/7.6.6/pwsh"
SRC="$ROOT/src/$ROOMKIT_SOURCE_ID"
RUN="$ROOT/runs/$ROOMKIT_RUN_ID"
section() { printf '\n## %s\n' "$1"; }

if [ -e "$RUN" ]; then echo "BLOCKED run folder already exists: $RUN"; exit 3; fi
if [ ! -x "$PWSH" ]; then echo "BLOCKED pwsh 7.6.6 is not installed at $PWSH"; exit 4; fi
mkdir -p "$RUN/tmp" "$RUN/xdg/config" "$RUN/xdg/cache" "$RUN/xdg/data"
export XDG_CONFIG_HOME="$RUN/xdg/config" XDG_CACHE_HOME="$RUN/xdg/cache" XDG_DATA_HOME="$RUN/xdg/data"
export TMPDIR="$RUN/tmp"
export POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1
RK_OUT="$RUN"
. "$HERE/linux_test_lib.sh"

section "runner self-test (injected failures)"
rk_step runner_selftest 120 bash "$HERE/linux_test_lib_selftest.sh" "$HERE/linux_test_lib.sh"
cat "$RUN/runner_selftest.out"

section "source snapshot"
gotsrc="$(sha256sum "$HERE/roomkit-src.tar" | awk '{print $1}')"
if [ "$gotsrc" != "$ROOMKIT_SRC_SHA256" ]; then rk_record source FAIL "archive hash mismatch"; rk_summary; exit 5; fi
if [ -e "$SRC" ]; then
  if [ "$(cat "$SRC.sha256" 2>/dev/null)" = "$gotsrc" ]; then echo "KEPT existing $SRC (same archive hash)"; else rk_record source FAIL "folder exists with a different archive: $SRC"; rk_summary; exit 5; fi
else
  mkdir -p "$SRC" && tar -xf "$HERE/roomkit-src.tar" -C "$SRC" && printf '%s\n' "$gotsrc" > "$SRC.sha256" && echo "INSTALLED $SRC"
fi
rk_record source PASS "sha256=$gotsrc files=$(find "$SRC" -type f | wc -l) crlf_text_files=$(grep -rlI $'\r$' --include='*.gd' --include='*.json' --include='*.ps1' "$SRC" 2>/dev/null | wc -l)"
printf 'pwsh: '; "$PWSH" -NoProfile -Command '"{0} {1}" -f $PSVersionTable.PSVersion, [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription' 2>&1 | head -n 1
printf 'system sqlite library: %s\n' "$(ldconfig -p 2>/dev/null | grep -m1 'libsqlite3.so.0' | awk '{print $NF}')"

section "build identity (unchanged inputs must keep the digests)"
rk_step digest 600 "$PWSH" -NoProfile -File "$SRC/tests/content_digest_portable.ps1" -Source "$SRC" -Work "$RUN/digest-work" -ExpectShooter "$ROOMKIT_EXPECT_SHOOTER" -ExpectTurns "$ROOMKIT_EXPECT_TURNS"
grep -E '^(FAIL|INFO)|_PORTABLE' "$RUN/digest.out"

section "storage slice (production helpers, fake data, Windows databases as foreign input)"
rk_step storage_slice 1500 "$PWSH" -NoProfile -File "$SRC/tests/storage_slice_portable.ps1" -Source "$SRC" -Work "$RUN/slice" -Foreign "$HERE/foreign"
cat "$RUN/storage_slice.out"

section "after the run"
printf 'leftover pwsh or godot processes of this user: %s\n' "$(pgrep -u "$(id -u)" -f "$ROOT/tools" | wc -l)"
printf 'modes under the run folder that are not owner-only: %s\n' "$(find "$RUN/slice" -perm /077 2>/dev/null | wc -l)"
printf 'run folder size: %s\n' "$(du -sh "$RUN" | awk '{print $1}')"

section "test databases generated here (base64 tar.gz, for the Windows cross-check)"
if [ -f "$RUN/slice/export/accounts.sqlite" ] && [ -f "$RUN/slice/export/assets.sqlite" ]; then
  ( cd "$RUN/slice/export" && sha256sum accounts.sqlite assets.sqlite )
  echo "-----BEGIN ROOMKIT TEST DATABASES-----"
  tar -czf - -C "$RUN/slice/export" accounts.sqlite assets.sqlite | base64 -w 76
  echo "-----END ROOMKIT TEST DATABASES-----"
else
  rk_record export FAIL "export folder is missing"
fi

rk_summary
status=$?
echo "ROOMKIT_LINUX_STORAGE_COMPLETE run=$ROOMKIT_RUN_ID failures=$rk_failures"
exit "$status"
