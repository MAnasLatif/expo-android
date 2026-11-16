#!/usr/bin/env bash
# =============================================================================
# Shut down emulators gracefully (quick-boot snapshots are saved).
#
#   scripts/emulator-stop.sh                    stop ALL running devices
#   scripts/emulator-stop.sh --device NAME      stop one device
#   add --keep-adb to leave the adb server running
#
# The isolated adb server is stopped once no emulator is left, so no background
# services keep running.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_sdk

KEEP_ADB=0 ONLY=""
# The CLI turns a global --device into EXPOEMU_DEVICE (name or serial).
if [ -n "${EXPOEMU_DEVICE:-}" ]; then
  if [[ "$EXPOEMU_DEVICE" == emulator-* ]]; then
    ONLY="$(running_emulators | awk -v s="$EXPOEMU_DEVICE" '$1 == s { print $2 }')"
    [ -n "$ONLY" ] || die "No running emulator with serial $EXPOEMU_DEVICE"
  else
    ONLY="$(device_name "$EXPOEMU_DEVICE")"
  fi
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-adb) KEEP_ADB=1 ;;
    --device|-d) ONLY="$(device_name "${2:-}")"; shift ;;
    -h|--help) sed -n '2,/^# =====*$/p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac; shift
done

# stop_one SERIAL NAME — console "kill", wait, then SIGTERM our process if needed.
stop_one() {
  local serial="$1" name="$2" pid_file="$RUN_DIR/emulator-$2.pid" pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  info "Stopping device '$name' ($serial)"
  adb_host -s "$serial" emu kill >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    if [ -n "$(serial_for_device "$name")" ] || { [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; }; then sleep 1; else break; fi
  done
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    warn "'$name' did not exit in time; sending SIGTERM to $pid"
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
  ok "Stopped '$name'"
}

# --- 1. Stop the requested device(s) ---------------------------------------------
stopped=0
while read -r serial name <&3; do   # fd 3: adb inside must not eat the list
  [ -n "$serial" ] || continue
  if [ -z "$ONLY" ] || [ "$name" = "$ONLY" ]; then stop_one "$serial" "$name"; stopped=$((stopped + 1)); fi
done 3< <(running_emulators)
rm -f "$RUN_DIR/emulator.pid"   # pid file name used by older versions
if [ "$stopped" = 0 ]; then
  if [ -n "$ONLY" ]; then ok "Device '$ONLY' was not running"; else ok "No emulator was running"; fi
fi

# --- 2. adb server: only when nothing is left ----------------------------------------
if [ "$KEEP_ADB" = 0 ]; then
  if [ -z "$(running_emulators)" ]; then
    adb_host kill-server >/dev/null 2>&1 || true
    ok "adb server stopped"
  else
    info "Other devices still running — adb server kept: $(running_emulators | awk '{print $2}' | tr '\n' ' ')"
  fi
fi
