#!/bin/sh
# herdr keepawake hook
#
# Fires on pane_agent_status_changed. Keeps macOS awake while ANY herdr agent
# pane is working (or blocked/awaiting input), and lets it sleep once every
# agent is idle.
#
# caffeinate flags:
#   -i  prevent idle system sleep
#   -m  prevent disk idle sleep
#   -s  prevent system sleep on AC power
#
# State is tracked in a pidfile so successive hook invocations can find and
# manage the single long-lived caffeinate process.

set -eu

STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}"
PIDFILE="${STATE_DIR%/}/herdr-keepawake.pid"

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"

# States that should keep the machine awake. "working" is the primary one;
# "blocked" means an agent is waiting on input, keep awake so you can respond.
should_stay_awake() {
  statuses=$("$HERDR_BIN" agent list 2>/dev/null \
    | grep -o '"agent_status"[[:space:]]*:[[:space:]]*"[a-z]*"' \
    | sed 's/.*"\([a-z]*\)"$/\1/') || return 1
  for s in $statuses; do
    case "$s" in
      working|blocked) return 0 ;;
    esac
  done
  return 1
}

caffeine_running() {
  [ -f "$PIDFILE" ] || return 1
  pid=$(cat "$PIDFILE" 2>/dev/null) || return 1
  [ -n "$pid" ] || return 1
  # Confirm the pid is actually a live caffeinate process.
  ps -p "$pid" -o comm= 2>/dev/null | grep -q caffeinate
}

start_caffeine() {
  caffeine_running && return 0
  caffeinate -i -m -s &
  echo $! > "$PIDFILE"
}

stop_caffeine() {
  if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "${pid:-}" ]; then
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
  fi
}

if should_stay_awake; then
  start_caffeine
else
  stop_caffeine
fi
