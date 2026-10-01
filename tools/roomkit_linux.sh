#!/usr/bin/env bash
# RoomKit on Linux from source or an exported package: one isolated instance of
# the management service (Operator -> managed host -> lobby -> rooms).
#
#   tools/roomkit_linux.sh start  [options]
#   tools/roomkit_linux.sh stop   [--instance NAME]
#   tools/roomkit_linux.sh status [--instance NAME]
#
# Options (start):
#   --instance NAME       instance name, [a-z0-9-]{1,32} (default: l3)
#   --panel-port P        local admin panel (default 28491; 28291 is refused)
#   --lobby-port P        lobby (WSS)       (default 28500)
#   --control-port P      room control      (default 28501)
#   --udp-range A-B       room UDP ports    (default 28540-28555)
#   --bind IPV4           lobby/room address and the address given to clients
#                         (default 127.0.0.1: same machine only)
# Ports and address only apply when the instance is created; afterwards its
# config.json (changed through the panel) wins.
#
# Everything of an instance lives in <project>/data/instance-NAME (700): the
# Operator data root (databases, TLS, config), the game index and prepared game
# projects, the public client configuration, and HOME/XDG/cache/tmp for the
# engine and pwsh. Files are created with umask 077 and SIGPIPE is ignored (it
# stays ignored in every child). Only one instance per source folder runs at a
# time (they share res://run).
#
# stop asks the Operator to shut down (operator-stop.request) and waits for its
# exit; it never signals a process. Anything that does not exit is reported and
# left alone. Uses the installed engine and pwsh (ROOMKIT_GODOT, ROOMKIT_PWSH
# override the default ~/roomkit/tools locations). Nothing is installed; no sudo,
# firewall or login change.
set -u
umask 077
trap '' PIPE
PROJECT="$(cd "$(dirname "$0")/.." && pwd -P)"
GODOT="${ROOMKIT_GODOT:-$HOME/roomkit/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64}"
PWSH="${ROOMKIT_PWSH:-$HOME/roomkit/tools/pwsh/7.6.6/pwsh}"
EXPORTED=0
if [ -f "$PROJECT/linux-package.json" ]; then
  EXPORTED=1
  GODOT="$PROJECT/Operator.x86_64"
fi
command="${1:-}"; [ $# -gt 0 ] && shift
NAME=l3 PANEL=28491 LOBBY=28500 CONTROL=28501 UDP=28540-28555 BIND=127.0.0.1
PANEL_EXPLICIT=0
fail() { echo "ROOMKIT_FAILED $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || fail "missing option value for $1"
  case "$1" in
    --instance) NAME="${2:-}"; shift 2 ;;
    --panel-port) PANEL="${2:-}"; PANEL_EXPLICIT=1; shift 2 ;;
    --lobby-port) LOBBY="${2:-}"; shift 2 ;;
    --control-port) CONTROL="${2:-}"; shift 2 ;;
    --udp-range) UDP="${2:-}"; shift 2 ;;
    --bind) BIND="${2:-}"; shift 2 ;;
    *) fail "unknown option $1" ;;
  esac
done
[[ "$NAME" =~ ^[a-z0-9-]{1,32}$ ]] || fail "invalid instance name"
INST="$PROJECT/data/instance-$NAME"
DATA="$INST/data"
STATE="$INST/instance.json"
PANEL_SETTING="$INST/panel.port"
config_field() { sed -n 's/.*"'"$1"'": *"\{0,1\}\([^",}]*\).*/\1/p' "$DATA/config.json"; }

# Start time of a live process; nothing for a missing one or a zombie (exited).
start_time() { awk '$3 != "Z" {print $22}' "/proc/$1/stat" 2>/dev/null; }
# The recorded Operator: prints its pid when that exact process (pid + start
# time from instance.json) still runs, nothing otherwise.
recorded_pid() {
  local file="$1" pid started
  [ -f "$file" ] || return 0
  pid="$(sed -n 's/.*"pid": *\([0-9]\{1,10\}\).*/\1/p' "$file")"
  started="$(sed -n 's/.*"start_time": *"\([0-9]\{1,20\}\)".*/\1/p' "$file")"
  if [ -n "$pid" ] && [ -n "$started" ] && [ "$(start_time "$pid")" = "$started" ]; then echo "$pid"; fi
}
listeners_on() {
  local n=0 address state port
  while read -r _ address _ state _; do
    port=$((16#${address##*:}))
    if [ "$state" = "0A" ] && [ "$port" -eq "$1" ]; then n=$((n + 1)); fi
  done < <(tail -q -n +2 /proc/net/tcp /proc/net/tcp6 2>/dev/null)
  echo "$n"
}
udp_in_range() {
  local n=0 address port
  while read -r _ address _; do
    port=$((16#${address##*:}))
    if [ "$port" -ge "$1" ] && [ "$port" -le "$2" ]; then n=$((n + 1)); fi
  done < <(tail -q -n +2 /proc/net/udp /proc/net/udp6 2>/dev/null)
  echo "$n"
}
# Processes started from this source folder (Operator, host, rooms, helpers).
## Their command lines name this folder (--path, a script under tools/, or a
## prepared game project inside the instance). This script itself is skipped.
source_processes() {
  local pid literal
  literal="$(printf '%s' "$PROJECT" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
  for pid in $(pgrep -f -- "$literal/|$literal( |$)" 2>/dev/null); do
    [ "$pid" = "$$" ] && continue
    { tr '\0' ' ' < "/proc/$pid/cmdline"; } 2>/dev/null | grep -q 'roomkit_linux\.sh' && continue
    [ -e "/proc/$pid" ] && echo "$pid"
  done
}

do_status() {
  local pid
  pid="$(recorded_pid "$STATE")"
  if [ -n "$pid" ]; then
    echo "ROOMKIT_RUNNING instance=$NAME pid=$pid panel=http://127.0.0.1:$(sed -n 's/.*"panel_port": *\([0-9]*\).*/\1/p' "$STATE")/"
  else
    echo "ROOMKIT_NOT_RUNNING instance=$NAME"
  fi
}

do_stop() {
  local pid deadline left
  pid="$(recorded_pid "$STATE")"
  if [ -z "$pid" ]; then
    [ -f "$STATE" ] && rm -f "$STATE"
    echo "ROOMKIT_NOT_RUNNING instance=$NAME"
    return 0
  fi
  : > "$DATA/operator-stop.request"
  deadline=$((SECONDS + 90))
  while [ -n "$(recorded_pid "$STATE")" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; done
  if [ -n "$(recorded_pid "$STATE")" ]; then
    fail "the Operator (pid $pid) has not exited after 90 s; nothing was signalled. See $INST/logs"
  fi
  rm -f "$STATE"
  # The Operator waits for its host; rooms leave when their control connection closes.
  deadline=$((SECONDS + 30))
  while [ -n "$(source_processes)" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; done
  left="$(source_processes | wc -l)"
  find "$INST/tmp" -mindepth 1 -delete 2>/dev/null
  if [ "$left" -ne 0 ]; then
    fail "the Operator exited but $left process(es) started from this source still run; nothing was signalled"
  fi
  echo "ROOMKIT_STOPPED instance=$NAME"
}

do_start() {
  local pid first last port other started deadline
  [ -x "$GODOT" ] || fail "engine not found: $GODOT"
  [ -x "$PWSH" ] || fail "pwsh not found: $PWSH"
  pid="$(recorded_pid "$STATE")"
  if [ -n "$pid" ]; then do_status; return 0; fi
  if [ "$PANEL_EXPLICIT" -eq 0 ] && [ -f "$PANEL_SETTING" ]; then
    [ ! -L "$PANEL_SETTING" ] || fail "panel setting is a symbolic link"
    PANEL="$(cat "$PANEL_SETTING")"
  fi
  if [ -f "$DATA/config.json" ]; then
    [ ! -L "$DATA/config.json" ] || fail "instance configuration is a symbolic link"
    LOBBY="$(config_field lobby_port)"; CONTROL="$(config_field control_port)"
    UDP="$(config_field udp_first)-$(config_field udp_last)"; BIND="$(config_field lobby_bind)"
  fi
  for port in "$PANEL" "$LOBBY" "$CONTROL"; do
    [[ "$port" =~ ^[0-9]{4,5}$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || fail "invalid port $port"
  done
  [[ "$UDP" =~ ^([0-9]{4,5})-([0-9]{4,5})$ ]] || fail "invalid UDP range $UDP"
  first="${BASH_REMATCH[1]}"; last="${BASH_REMATCH[2]}"
  [ "$first" -ge 1024 ] && [ "$last" -le 65535 ] && [ "$first" -le "$last" ] && [ $((last - first)) -le 255 ] || fail "invalid UDP range $UDP"
  [ "$PANEL" -ne 28291 ] || fail "28291 is the Windows management port; choose another panel port"
  [ "$PANEL" -ne "$LOBBY" ] && [ "$PANEL" -ne "$CONTROL" ] && [ "$LOBBY" -ne "$CONTROL" ] || fail "panel, lobby and control ports must differ"
  for port in "$PANEL" "$LOBBY" "$CONTROL"; do
    if [ "$port" -ge "$first" ] && [ "$port" -le "$last" ]; then fail "port $port lies inside the UDP range"; fi
  done
  [[ "$BIND" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail "invalid bind address $BIND"
  for other in "$PROJECT"/data/instance-*/instance.json; do
    [ -f "$other" ] || continue
    if [ -n "$(recorded_pid "$other")" ]; then fail "another instance of this source folder is running ($(basename "$(dirname "$other")")); stop it first"; fi
  done
  for port in "$PANEL" "$LOBBY" "$CONTROL"; do
    [ "$(listeners_on "$port")" -eq 0 ] || fail "TCP port $port is already in use"
  done
  [ "$(udp_in_range "$first" "$last")" -eq 0 ] || fail "UDP ports $UDP are already in use"
  [ -z "$(source_processes)" ] || fail "processes started from this source folder are still running; nothing was started"
  for folder in "$PROJECT/data" "$INST" "$DATA" "$INST/public" "$INST/logs" "$INST/home" "$INST/xdg" "$INST/xdg/config" "$INST/xdg/cache" "$INST/xdg/data" "$INST/tmp" "$INST/build"; do
    [ -L "$folder" ] && fail "$folder is a symbolic link"
    mkdir -p "$folder" && chmod 700 "$folder" || fail "cannot prepare $folder"
  done
  export HOME="$INST/home" XDG_CONFIG_HOME="$INST/xdg/config" XDG_CACHE_HOME="$INST/xdg/cache" XDG_DATA_HOME="$INST/xdg/data" TMPDIR="$INST/tmp"
  export ROOMKIT_PWSH="$PWSH" POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1
  [ ! -L "$PANEL_SETTING" ] || fail "panel setting is a symbolic link"
  printf '%s\n' "$PANEL" > "$PANEL_SETTING" && chmod 600 "$PANEL_SETTING" || fail "cannot save panel port"
  if [ ! -f "$INST/games.json" ]; then
    if [ "$EXPORTED" -eq 1 ]; then
      [ -f "$PROJECT/games.json" ] && [ ! -L "$PROJECT/games.json" ] || fail "package game index missing or linked"
      cp "$PROJECT/games.json" "$INST/games.json" && chmod 600 "$INST/games.json" || fail "cannot prepare package game index"
    else
      "$PWSH" -NoProfile -NonInteractive -File "$PROJECT/tools/build_framework.ps1" -IndexPath "$INST/games.json" -BuildRoot "$INST/build" > "$INST/logs/build.log" 2>&1 || fail "game build failed; see $INST/logs/build.log"
    fi
  fi
  rm -f "$DATA/operator-stop.request"
  cd "$INST" || fail "cannot enter $INST"
  local engine_args=()
  if [ "$EXPORTED" -eq 0 ]; then engine_args=(--path "$PROJECT" --script res://host/operator.gd); fi
  setsid "$GODOT" --headless "${engine_args[@]}" --log-file "$INST/logs/operator.log" -- \
    "--data-root=$DATA" "--games=$INST/games.json" "--public-client-dir=$INST/public" "--operator-log-path=$INST/logs/operator.log" \
    "--panel-port=$PANEL" "--initial-bind=$BIND" "--initial-ports=$LOBBY,$CONTROL,$first,$last" \
    < /dev/null > "$INST/logs/console.log" 2> "$INST/logs/stderr.log" &
  pid=$!
  started=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do started="$(start_time "$pid")"; [ -n "$started" ] && break; sleep 0.1; done
  [ -n "$started" ] || fail "the Operator exited at once; see $INST/logs/stderr.log"
  printf '{"pid": %s, "start_time": "%s", "panel_port": %s, "project": "%s"}\n' "$pid" "$started" "$PANEL" "$PROJECT" > "$STATE"
  deadline=$((SECONDS + 90))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -z "$(recorded_pid "$STATE")" ]; then rm -f "$STATE"; tail -n 5 "$INST/logs/stderr.log" >&2; fail "the Operator exited during start; see $INST/logs"; fi
    if grep -q "\"pid\":$pid[,}]" "$DATA/operator.json" 2>/dev/null; then
      echo "ROOMKIT_PANEL http://127.0.0.1:$PANEL/ instance=$NAME pid=$pid"
      echo "ROOMKIT_CLIENT_CONFIG $INST/public/connection.json"
      return 0
    fi
    sleep 0.3
  done
  : > "$DATA/operator-stop.request"
  fail "the Operator did not become ready in 90 s; a stop was requested, nothing was signalled. See $INST/logs"
}

case "$command" in
  start) do_start ;;
  stop) do_stop ;;
  status) do_status ;;
  *) echo "usage: $0 start|stop|status [options]" >&2; exit 2 ;;
esac
