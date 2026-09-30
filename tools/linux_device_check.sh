#!/usr/bin/env bash
# RoomKit L0: read-only facts about a Linux test machine. It installs nothing,
# writes nothing, never uses sudo and prints only to stdout. No environment
# dump, no MAC addresses, no file contents from the home directory.
# Run from the Windows project root (the script is piped, nothing is copied):
#   ssh zhao@192.168.10.105 'bash -s' < tools/linux_device_check.sh > logs/linux-device-check.txt
set -u
export LC_ALL=C
section() { printf '\n## %s\n' "$1"; }
run() { printf '$ %s\n' "$*"; "$@" 2>&1 || printf '(exit %s)\n' "$?"; }
have() { command -v "$1" >/dev/null 2>&1; }

section "system"
run uname -srmo
if [ -r /etc/os-release ]; then grep -E '^(NAME|VERSION|ID|ID_LIKE|VERSION_ID)=' /etc/os-release; fi
if have ldd; then ldd --version 2>&1 | head -n 1; fi
run date -u +%Y-%m-%dT%H:%M:%SZ
if have timedatectl; then timedatectl show -p NTPSynchronized -p Timezone 2>&1; fi

section "cpu and memory"
run nproc
if have lscpu; then lscpu | grep -E '^(Architecture|Model name|CPU\(s\)|Thread|Core|Flags)' | sed -E 's/^(Flags:).*/\1 (omitted)/'; fi
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
run uptime

section "disk"
run df -hT "$HOME" /tmp
run df -i "$HOME"

section "user and permissions"
printf 'user=%s uid=%s\n' "$(id -un)" "$(id -u)"
printf 'groups=%s\n' "$(id -Gn)"
printf 'sudo_binary=%s (not invoked)\n' "$(command -v sudo || echo none)"
printf 'home_mode=%s umask=%s\n' "$(stat -c %a "$HOME" 2>/dev/null)" "$(umask)"
printf 'open_files_limit=%s max_user_processes=%s\n' "$(ulimit -n)" "$(ulimit -u)"
if have loginctl; then loginctl show-user "$(id -un)" -p Linger 2>&1; fi
if have systemctl; then printf 'systemd_user='; systemctl --user is-system-running 2>&1 | head -n 1; fi

section "process safety prerequisites"
printf 'kernel=%s (pidfd_open needs >= 5.3, pidfd_send_signal >= 5.1)\n' "$(uname -r)"
printf 'pid_max=%s\n' "$(cat /proc/sys/kernel/pid_max 2>/dev/null)"
printf 'proc_stat_readable=%s proc_exe_readable=%s\n' "$([ -r /proc/self/stat ] && echo yes || echo no)" "$(readlink /proc/self/exe >/dev/null 2>&1 && echo yes || echo no)"
grep -E '^hidepid|proc ' /proc/mounts 2>/dev/null | head -n 2

section "godot"
for name in godot godot4 Godot; do if have "$name"; then printf '%s -> %s\n' "$name" "$(command -v "$name")"; "$name" --version 2>&1 | head -n 1; fi; done
printf 'known RoomKit tool locations (no home-directory scan):\n'
for directory in "$HOME/roomkit/tools/godot" "$HOME/.local/share/roomkit/tools/godot"; do
  if [ -d "$directory" ]; then ls -ld "$directory"; fi
done
printf 'export templates:\n'
ls -1 "$HOME/.local/share/godot/export_templates" 2>/dev/null || echo '(none)'

section "powershell and dotnet"
if have pwsh; then printf 'pwsh -> %s\n' "$(command -v pwsh)"; pwsh --version 2>&1 | head -n 1; else echo 'pwsh: not found'; fi
ls -d /opt/microsoft/powershell/* "$HOME"/.local/share/powershell "$HOME"/roomkit/tools/pwsh 2>/dev/null || true
if have dotnet; then dotnet --list-runtimes 2>&1 | head -n 5; else echo 'dotnet: not found (not required; pwsh bundles its runtime)'; fi
printf 'libicu: '; (ldconfig -p 2>/dev/null | grep -m1 -E 'libicuuc\.so' ) || echo 'not found (pwsh then needs DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1)'
printf 'libssl: '; (ldconfig -p 2>/dev/null | grep -m1 -E 'libssl\.so' ) || echo 'not found'

section "sqlite"
(ldconfig -p 2>/dev/null | grep -E 'libsqlite3\.so') || echo 'libsqlite3 not in ldconfig cache'
ls -l /usr/lib/*/libsqlite3.so* /usr/lib64/libsqlite3.so* /usr/lib/libsqlite3.so* 2>/dev/null || true
if have sqlite3; then run sqlite3 --version; else echo 'sqlite3 CLI: not found (not required)'; fi

section "network and firewall overview"
if have ip; then ip -4 -o addr show scope global | awk '{print $2, $4}'; ip -4 route show default | awk '{print "default via", $3, "dev", $5}'; fi
for unit in ufw firewalld nftables; do if have systemctl; then printf '%s: %s\n' "$unit" "$(systemctl is-active "$unit" 2>&1 | head -n 1)"; fi; done
printf 'ufw_binary=%s firewall-cmd=%s nft=%s (rule listing needs root; not attempted)\n' "$(command -v ufw || echo none)" "$(command -v firewall-cmd || echo none)" "$(command -v nft || echo none)"
printf 'listeners on RoomKit default ports (28291, 28300, 28301, 28400-28431):\n'
if have ss; then ss -H -lntu 2>/dev/null | awk '{print $1, $5}' | grep -E ':(28291|2830[01]|284[0-2][0-9]|2843[01])$' || echo '(none)'; fi

section "tools"
for tool in bash tar unzip curl wget git python3 openssl sha256sum; do
  flag=--version; case "$tool" in openssl) flag=version;; unzip) flag=-v;; esac
  if have "$tool"; then printf '%s: %s\n' "$tool" "$("$tool" $flag 2>&1 | head -n 1)"; else printf '%s: not found\n' "$tool"; fi
done
printf 'locale: %s\n' "$(locale 2>/dev/null | grep -E '^LANG=' || echo unknown)"
printf 'utf8 locales: %s\n' "$(locale -a 2>/dev/null | grep -ci 'utf')"

section "done"
echo "ROOMKIT_LINUX_CHECK_COMPLETE"
