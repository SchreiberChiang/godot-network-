#!/usr/bin/env bash
# RoomKit: read-only environment check of the Linux test machine before a mainline
# acceptance run. It changes nothing: no file outside its own output (stdout) is
# written, nothing is installed, deleted or rebuilt, no process is signalled, no
# sudo. It reads the shared tools, the mainline and experiment folders under
# the selected source snapshot, processes and resource use only.
# Last line: ENV_GATE OK, or ENV_GATE BLOCK <reasons> when a mainline run should
# not start (the caller stops and reports instead).
set -u
ROOT="$HOME/roomkit"
GODOT_DIR="$ROOT/tools/godot/4.7.2-stable"
GODOT="$GODOT_DIR/Godot_v4.7.2-stable_linux.x86_64"
PWSH_DIR="$ROOT/tools/pwsh/7.6.6"

SNAPSHOT="${1:-}"
block=()
section() { printf '\n## %s\n' "$1"; }
size() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

section "machine"
printf 'user=%s uid=%s kernel=%s uptime=%s\n' "$(id -un)" "$(id -u)" "$(uname -r)" "$(uptime -p 2>/dev/null)"
printf 'loadavg=%s cpus=%s\n' "$(cut -d' ' -f1-3 /proc/loadavg)" "$(nproc)"
free -m | awk 'NR==2 {printf "memory MB: total=%s used=%s available=%s\n", $2, $3, $7} NR==3 {printf "swap MB: total=%s used=%s\n", $2, $3}'
df -h "$HOME" /tmp 2>/dev/null | awk 'NR==1 || /\//'
printf 'HOME=%s XDG_CONFIG_HOME=%s XDG_DATA_HOME=%s XDG_CACHE_HOME=%s TMPDIR=%s (of this login shell)\n' "$HOME" "${XDG_CONFIG_HOME:-unset}" "${XDG_DATA_HOME:-unset}" "${XDG_CACHE_HOME:-unset}" "${TMPDIR:-unset}"

section "shared Godot"
if [ -x "$GODOT" ]; then
  printf 'path=%s version=%s\n' "$GODOT" "$("$GODOT" --version 2>&1 | head -n 1)"
  installed="$(sha256sum "$GODOT" | awk '{print $1}')"
  printf 'installed binary sha256=%s size=%s mtime=%s\n' "$installed" "$(stat -c %s "$GODOT")" "$(stat -c %y "$GODOT" | cut -d. -f1)"
  archive="$(ls "$ROOT"/downloads/Godot_v4.7.2-stable_linux.x86_64.zip 2>/dev/null | head -n 1)"
  if [ -n "$archive" ]; then
    packed="$(unzip -p "$archive" Godot_v4.7.2-stable_linux.x86_64 2>/dev/null | sha256sum | awk '{print $1}')"
    printf 'archive=%s archive sha256=%s binary inside=%s\n' "${archive#$ROOT/}" "$(sha256sum "$archive" | awk '{print $1}')" "$packed"
    if [ "$packed" = "$installed" ]; then echo "installed binary equals the one in the original archive"; else echo "DIFFERENT: installed binary is not the one in the original archive"; block+=("godot-binary-changed"); fi
  else
    echo "original archive not found in ~/roomkit/downloads (cannot compare)"
  fi
  printf 'files in the Godot folder: %s; changed later than the binary: %s\n' "$(find "$GODOT_DIR" -type f | wc -l)" "$(find "$GODOT_DIR" -type f -newer "$GODOT" | wc -l)"
  find "$GODOT_DIR" -type f -newer "$GODOT" -printf '  newer: %P %TY-%Tm-%Td %TH:%TM\n' | head -n 10
  printf 'extensions or libraries in the Godot folder: %s\n' "$(find "$GODOT_DIR" \( -name '*.gdextension' -o -name '*.so' -o -name '*.so.*' \) | wc -l)"
else
  echo "MISSING $GODOT"; block+=("godot-missing")
fi

section "shared pwsh"
if [ -x "$PWSH_DIR/pwsh" ]; then
  printf 'path=%s version=%s\n' "$PWSH_DIR/pwsh" "$("$PWSH_DIR/pwsh" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1 | head -n 1)"
  installed="$(sha256sum "$PWSH_DIR/pwsh" | awk '{print $1}')"
  printf 'installed pwsh launcher sha256=%s; System.Management.Automation.dll sha256=%s\n' "$installed" "$(sha256sum "$PWSH_DIR/System.Management.Automation.dll" 2>/dev/null | awk '{print $1}')"
  archive="$(ls "$ROOT"/downloads/powershell-7.6.6-linux-x64.tar.gz 2>/dev/null | head -n 1)"
  if [ -n "$archive" ]; then
    packed="$(tar -xzOf "$archive" ./pwsh 2>/dev/null | sha256sum | awk '{print $1}')"
    [ "$packed" = "$(printf '' | sha256sum | awk '{print $1}')" ] && packed="$(tar -xzOf "$archive" pwsh 2>/dev/null | sha256sum | awk '{print $1}')"
    printf 'archive=%s archive sha256=%s pwsh inside=%s\n' "${archive#$ROOT/}" "$(sha256sum "$archive" | awk '{print $1}')" "$packed"
    if [ "$packed" = "$installed" ]; then echo "installed pwsh equals the one in the original archive"; else echo "DIFFERENT: installed pwsh is not the one in the original archive"; block+=("pwsh-changed"); fi
    listed="$(tar -tzf "$archive" 2>/dev/null | grep -v '/$' | wc -l)"
    printf 'files: archive=%s installed=%s; installed files changed later than the pwsh launcher: %s\n' "$listed" "$(find "$PWSH_DIR" -type f | wc -l)" "$(find "$PWSH_DIR" -type f -newer "$PWSH_DIR/pwsh" | wc -l)"
  else
    echo "original archive not found in ~/roomkit/downloads (cannot compare)"
  fi
else
  echo "MISSING $PWSH_DIR/pwsh"; block+=("pwsh-missing")
fi
ls -la "$ROOT/downloads" 2>/dev/null | awk 'NR>1 {print "  downloads:", $5, $NF}'

section "mainline snapshot: no experiment extension"
if [ -n "$SNAPSHOT" ] && [ -d "$SNAPSHOT" ]; then
  found="$(find "$SNAPSHOT" \( -name '*.gdextension' -o -name '*.so' -o -name '*.so.*' -o -name '*.dll' \) | wc -l)"
  printf 'snapshot=%s extension or native library files: %s\n' "${SNAPSHOT#$ROOT/}" "$found"
  [ "$found" -eq 0 ] || { find "$SNAPSHOT" \( -name '*.gdextension' -o -name '*.so' -o -name '*.dll' \) -printf '  %P\n' | head; block+=("extension-in-snapshot"); }
  printf 'prototype folder in the snapshot: %s\n' "$(ls "$SNAPSHOT/prototypes/native_sqlite" 2>/dev/null | tr '\n' ' ')"
fi
# Scoped (adopted from the Codex re-run): it does not enter ~/roomkit/experiments
# or user-level configuration folders.
section "processes"
echo "engine, pwsh, debugger and build processes of any user (pid user cpu% mem% elapsed command):"
ps -eo pid,user,pcpu,pmem,etime,args --sort=-pcpu | grep -E 'Godot_v|/pwsh|(^|/| )gdb( |$)|lldb|scons|cc1plus|clang|ninja|sqlite-import-lab' | grep -v -E 'grep -E|linux_env_check' | cut -c1-200 | head -n 20
running="$(pgrep -u "$(id -u)" -f 'Godot_v|/pwsh|(^|/)gdb( |$)|scons|cc1plus|sqlite-import-lab' | grep -v "^$$\$" | wc -l)"
printf 'matching processes of this user: %s\n' "$running"
[ "$running" -eq 0 ] || block+=("processes-running")
echo "top CPU users:"
ps -eo pid,user,pcpu,pmem,args --sort=-pcpu | head -n 8 | cut -c1-160

avail_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
[ "$avail_kb" -gt 2097152 ] || block+=("disk-below-2GB")

if [ "${#block[@]}" -eq 0 ]; then echo "ENV_GATE OK"; else echo "ENV_GATE BLOCK ${block[*]}"; fi
