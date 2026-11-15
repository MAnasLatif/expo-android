#!/usr/bin/env bash
# =============================================================================
# Boot the virtual Android phone natively on macOS and wait until it is ready.
#
#   scripts/emulator-start.sh [--headless] [--cold-boot] [--wipe] [--no-animations]
#
#   --headless       no window (CI / fully agent-driven sessions)
#   --cold-boot      ignore the quick-boot snapshot
#   --wipe           factory-reset the device's data
#   --no-animations  disable system animations (stabler screenshots/tests)
#
# The emulator registers with the isolated adb server on $ADB_SERVER_PORT, which
# the Docker container also uses. Metro's port is reversed into the device so
# the app can load its bundle from 127.0.0.1.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_macos
require_sdk

# Note: empty arrays are expanded as ${A[@]+"${A[@]}"} — macOS ships bash 3.2,
# where "${A[@]}" on an empty array fails under `set -u`.
HEADLESS="$EMULATOR_HEADLESS" EXTRA=() NO_ANIM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --headless) HEADLESS=true; shift ;;
    --cold-boot) EXTRA+=(-no-snapshot-load); shift ;;
    --wipe) EXTRA+=(-wipe-data); shift ;;
    --no-animations) NO_ANIM=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[ -f "$AVD_HOME/$AVD_NAME.avd/config.ini" ] || die "AVD '$AVD_NAME' not found. Run: scripts/setup.sh"
[ "$HEADLESS" = true ] && EXTRA+=(-no-window)

# --- 1. adb server (localhost only; Docker reaches it via host.docker.internal)
adb_host start-server >/dev/null 2>&1 || die "Could not start adb server on port $ADB_SERVER_PORT"

# --- 2. Launch (unless one is already running) --------------------------------
if [ -n "$(emulator_serial)" ]; then
  ok "Emulator already running: $(emulator_serial)"
else
  mkdir -p "$LOG_DIR" "$RUN_DIR"
  info "Starting emulator '$AVD_NAME' (GPU: $EMULATOR_GPU, headless: $HEADLESS)"
  nohup "$EMULATOR_BIN" -avd "$AVD_NAME" \
    -gpu "$EMULATOR_GPU" -no-boot-anim -no-metrics \
    -netdelay none -netspeed full \
    ${EXTRA[@]+"${EXTRA[@]}"} >"$LOG_DIR/emulator.log" 2>&1 &
  echo $! > "$RUN_DIR/emulator.pid"
fi

# --- 3. Wait for full boot ------------------------------------------------------
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
info "Waiting for Android to finish booting (timeout ${BOOT_TIMEOUT}s)"
pid="$(cat "$RUN_DIR/emulator.pid" 2>/dev/null || true)"
for ((i = 0; i < BOOT_TIMEOUT; i += 2)); do
  serial="$(emulator_serial)"
  if [ -n "$serial" ] && [ "$(adb_host -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
    break
  fi
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && [ -z "$serial" ]; then
    tail -20 "$LOG_DIR/emulator.log" >&2
    die "Emulator exited during boot (full log: $LOG_DIR/emulator.log)"
  fi
  sleep 2
done
[ -n "${serial:-}" ] || die "Timed out waiting for the emulator (log: $LOG_DIR/emulator.log)"
export ANDROID_SERIAL="$serial"

# --- 4. Post-boot tweaks ----------------------------------------------------------
# Unlock the screen so taps/screenshots hit the app, not the lock screen.
adb_host shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb_host shell wm dismiss-keyguard >/dev/null 2>&1 || true
if [ "$NO_ANIM" = 1 ]; then
  for s in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb_host shell settings put global "$s" 0
  done
  ok "System animations disabled"
fi
# Metro: device 127.0.0.1:PORT -> macOS 127.0.0.1:PORT -> container (published port)
adb_host reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null
ok "Emulator ready: $serial (Metro port $METRO_PORT reversed)"
