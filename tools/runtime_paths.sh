#!/usr/bin/env bash
# Shared discovery only: explicit overrides, project-local tools, old user tools.
# The caller supplies an absolute ROOMKIT_PROJECT; sourcing changes no files.
rk_runtime_paths() {
  local root="$1" local_godot local_pwsh
  local_godot="$root/artifacts/environment/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64"
  local_pwsh="$root/artifacts/environment/tools/pwsh/7.6.6/pwsh"
  if [ -n "${ROOMKIT_GODOT:-}" ]; then RK_GODOT="$ROOMKIT_GODOT"
  elif [ -e "$local_godot" ]; then RK_GODOT="$local_godot"
  else RK_GODOT="$HOME/roomkit/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64"; fi
  if [ -n "${ROOMKIT_PWSH:-}" ]; then RK_PWSH="$ROOMKIT_PWSH"
  elif [ -e "$local_pwsh" ]; then RK_PWSH="$local_pwsh"
  else RK_PWSH="$HOME/roomkit/tools/pwsh/7.6.6/pwsh"; fi
  RK_EXPORTED=0
  if [ -f "$root/linux-package.json" ]; then RK_EXPORTED=1; RK_GODOT="$root/Operator.x86_64"; fi
}
