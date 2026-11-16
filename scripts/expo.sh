#!/usr/bin/env bash
# =============================================================================
# Run Expo / Metro inside the container.
#
#   scripts/expo.sh [expo args]            foreground, interactive (press a, r, j…)
#   scripts/expo.sh --background [args]    detached; returns once Metro is ready
#   scripts/expo.sh --logs                 print the background Metro log
#   scripts/expo.sh --stop                 stop background Metro
#
# Metro listens on all interfaces INSIDE the container (required for Docker's
# port publishing; NOT --localhost, which would bind the container loopback).
# Docker publishes it on macOS 127.0.0.1 only, and REACT_NATIVE_PACKAGER_HOSTNAME
# =127.0.0.1 makes bundle URLs point there. The emulator reaches it through
# `adb reverse`, which this script (re)applies when a device is online.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_docker
container_running || die "Container not running. Start it with: $(cmd start.sh) /path/to/expo-app"

LOG=/tmp/metro.log
in_container() { docker exec -u expo -w /workspace "$CONTAINER_NAME" bash -lc "$1"; }

metro_ready() {
  curl -fs --max-time 2 "http://127.0.0.1:$METRO_PORT/status" 2>/dev/null | grep -q running
}

# Keep the device -> Metro tunnel up (idempotent; harmless if no emulator).
# One Metro serves every running device: reverse the port into each of them.
reverse_port() {
  [ -x "$ADB" ] || return 0
  local s
  for s in $(running_targets | awk '{print $1}'); do
    adb_host -s "$s" reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null 2>&1 || true
  done
}

case "${1:-}" in
  --logs) in_container "cat $LOG 2>/dev/null || echo 'No background Metro log yet.'"; exit 0 ;;
  --stop)
    # "[e]xpo" so pkill doesn't match (and kill) its own bash -c command line.
    in_container "pkill -f '[e]xpo start' || true"
    ok "Metro stopped"; exit 0 ;;
  --background)
    shift
    if metro_ready; then ok "Metro already running on 127.0.0.1:$METRO_PORT"; reverse_port; exit 0; fi
    info "Starting Metro in the background"
    # No TTY under `exec -d`, so Expo runs non-interactively by itself.
    # Do NOT set CI=1: Expo disables file watching (Fast Refresh) in CI mode.
    docker exec -d -u expo -w /workspace "$CONTAINER_NAME" bash -lc \
      "bunx expo start --port $METRO_PORT $* > $LOG 2>&1"
    for _ in $(seq 1 90); do metro_ready && break; sleep 2; done
    metro_ready || { in_container "tail -30 $LOG" >&2; die "Metro did not become ready"; }
    reverse_port
    ok "Metro ready at http://127.0.0.1:$METRO_PORT — open the app with: $(cmd open-app.sh)"
    exit 0 ;;
esac

# --- Foreground (default) ------------------------------------------------------
reverse_port
flags=(-i); [ -t 0 ] && [ -t 1 ] && flags+=(-t)
exec docker exec "${flags[@]}" -u expo -w /workspace "$CONTAINER_NAME" \
  bunx expo start --port "$METRO_PORT" "$@"
