#!/usr/bin/env bash
# Fast refusal/read-only checks; no downloads, real installs or services.
set -euo pipefail
source_root="$(cd "$(dirname "$0")/.." && pwd -P)"
[ "$(id -u)" -ne 0 ] || { echo 'test requires an ordinary user'; exit 64; }
umask 077
[ ! -L "$source_root/artifacts" ] || { echo 'linked test artifact root'; exit 64; }
mkdir -p "$source_root/artifacts"
work="$(mktemp -d "$source_root/artifacts/environment-test-XXXXXXXX")"
cleanup() { case "$work" in "$source_root"/artifacts/environment-test-*) rm -rf -- "$work" ;; *) exit 99 ;; esac; }
trap cleanup EXIT
mkdir -p "$work/source/tools" "$work/home"
cp "$source_root/PrepareEnvironment.sh" "$work/source/"
cp "$source_root/tools/prepare_environment.sh" "$source_root/tools/runtime_paths.sh" "$work/source/tools/"
printf 'config_version=5\n' > "$work/source/project.godot"
export HOME="$work/home"
unset ROOMKIT_GODOT ROOMKIT_PWSH || true
passes=0
expect() {
  local label="$1" code="$2" pattern="$3"; shift 3
  local actual=0
  "$@" > "$work/last.out" 2>&1 || actual=$?
  if [ "$actual" -ne "$code" ] || ! grep -F "$pattern" "$work/last.out" >/dev/null; then
    echo "FAIL $label exit=$actual expected=$code"; cat "$work/last.out"; exit 1
  fi
  passes=$((passes+1)); echo "PASS $label"
}
entry="$work/source/PrepareEnvironment.sh"
expect help 0 'check creates nothing' bash "$entry" --help
expect unknown-mode 64 'RoomKit Linux' bash "$entry" bad
expect unknown-option 64 'unknown option' bash "$entry" prepare --hash unsafe
expect duplicate-option 64 'duplicate option' bash "$entry" prepare --offline --offline
expect readonly-no-install-options 64 'check accepts no' bash "$entry" check --offline
expect missing-option-value 64 'missing archive path' bash "$entry" prepare --pwsh-archive
expect relative-archive 1 'absolute paths' bash "$entry" prepare --pwsh-archive fake.tar.gz
expect traversal-archive 1 'absolute paths' bash "$entry" prepare --pwsh-archive "$work/source/../fake.tar.gz"
printf 'not the official archive\n' > "$work/bad.zip"
printf 'not the official archive\n' > "$work/bad.tar.gz"
ln -s "$work/bad.zip" "$work/linked.zip"
expect linked-archive 1 'linked path refused' bash "$entry" prepare --godot-archive "$work/linked.zip"
ln -s "$work/source" "$work/linked-source"
expect linked-project 1 'linked path refused' bash "$work/linked-source/PrepareEnvironment.sh" check
before="$(find "$work/source" -printf '%P %y %s\n' | sort)"
expect missing-check 2 'ROOMKIT_ENVIRONMENT_INCOMPLETE' bash "$entry" check
after="$(find "$work/source" -printf '%P %y %s\n' | sort)"
[ "$before" = "$after" ] || { echo 'FAIL check changed files'; exit 1; }
passes=$((passes+1)); echo 'PASS check-is-read-only'
expect offline-missing-archives 1 'offline preparation needs --godot-archive' bash "$entry" prepare --offline
expect forged-archive 1 'SHA256 mismatch' bash "$entry" prepare --offline --godot-archive "$work/bad.zip" --pwsh-archive "$work/bad.tar.gz"
[ ! -e "$work/source/artifacts/environment/tools" ] && [ ! -e "$work/source/artifacts/environment/.prepare-lock" ] && ! find "$work/source/artifacts/environment" -name '.stage-*' | grep -q . || { echo 'FAIL failed archive left installation/temporary files'; exit 1; }
passes=$((passes+1)); echo 'PASS failed-archive-cleanup'
mkdir -p "$work/source/artifacts/environment/tools/godot/4.7.2-stable"
printf 'user data\n' > "$work/source/artifacts/environment/tools/godot/4.7.2-stable/keep.txt"
expect keep-incomplete-existing 1 'existing Godot tool directory' bash "$entry" prepare --offline --godot-archive "$work/bad.zip" --pwsh-archive "$work/bad.tar.gz"
[ "$(cat "$work/source/artifacts/environment/tools/godot/4.7.2-stable/keep.txt")" = 'user data' ] || exit 1
passes=$((passes+1)); echo 'PASS user-tool-preserved'
expect missing-explicit-path 1 'correct or unset the override' env ROOMKIT_GODOT="$work/missing-godot" bash "$entry" prepare --offline --godot-archive "$work/bad.zip" --pwsh-archive "$work/bad.tar.gz"
mv "$work/source/artifacts" "$work/source/artifacts-kept"
ln -s "$work/source/artifacts-kept" "$work/source/artifacts"
expect linked-install-root 1 'linked path refused' bash "$entry" prepare --offline --godot-archive "$work/bad.zip" --pwsh-archive "$work/bad.tar.gz"
rm "$work/source/artifacts"
printf '{}\n' > "$work/source/linux-package.json"
printf 'bundled engine\n' > "$work/source/Operator.x86_64"
expect package-refuses-godot-archive 1 'includes Godot' bash "$entry" prepare --offline --godot-archive "$work/bad.zip" --pwsh-archive "$work/bad.tar.gz"
expect package-needs-only-pwsh 1 'offline preparation needs --pwsh-archive' bash "$entry" prepare --offline
expect package-invalid-pwsh-hash 1 'SHA256 mismatch' bash "$entry" prepare --offline --pwsh-archive "$work/bad.tar.gz"
echo "ENVIRONMENT_BOUNDARIES passed=$passes failed=0"
