#!/usr/bin/env bash
# =============================================================================
# Shut down the emulator gracefully (quick-boot snapshot is saved), then stop
# the isolated adb server so no background services are left running.
#
#   scripts/emulator-stop.sh [--keep-adb]
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_sdk

KEEP_ADB=0
[ "${1:-}" = "--keep-adb" ] && KEEP_ADB=1

pid="$(cat "$RUN_DIR/emulator.pid" 2>/dev/null || true)"
serial="$(emulator_serial)"

# --- 1. Graceful shutdown via the emulator console --------------------------
if [ -n "$serial" ]; then
  info "Stopping emulator $serial"
  adb_host -s "$serial" emu kill >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
fi

# --- 2. Fallback: terminate the process we started ----------------------------
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  warn "Emulator did not exit in time; sending SIGTERM to $pid"
  kill "$pid" 2>/dev/null || true
fi
rm -f "$RUN_DIR/emulator.pid"
[ -n "$serial$pid" ] && ok "Emulator stopped" || ok "No emulator was running"

# --- 3. adb server -------------------------------------------------------------
if [ "$KEEP_ADB" = 0 ]; then
  adb_host kill-server >/dev/null 2>&1 || true
  ok "adb server stopped"
fi
