#!/usr/bin/env bash
# =============================================================================
# Boot a virtual Android device natively on macOS and wait until it is ready.
# Several devices can run at the same time — start each one by name.
#
#   scripts/emulator-start.sh [--device NAME] [--headless] [--cold-boot] [--wipe] [--no-animations]
#
#   --device NAME    which device (see `devices`; default: the default phone)
#   --headless       no window (CI / fully agent-driven sessions)
#   --cold-boot      ignore the quick-boot snapshot
#   --wipe           factory-reset the device's data
#   --no-animations  disable system animations (stabler screenshots/tests)
#
# Every emulator registers with the isolated adb server on $ADB_SERVER_PORT,
# which the Docker container also uses. Metro's port is reversed into the
# device so the app can load its bundle from 127.0.0.1.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_macos
require_sdk

# Note: empty arrays are expanded as ${A[@]+"${A[@]}"} — macOS ships bash 3.2,
# where "${A[@]}" on an empty array fails under `set -u`.
HEADLESS="$EMULATOR_HEADLESS" EXTRA=() NO_ANIM=0
# Device: --device, else EXPOEMU_DEVICE (set by the CLI's global --device), else default.
DEVICE="${EXPOEMU_DEVICE:-}"; [[ "$DEVICE" == emulator-* ]] && DEVICE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --device|-d) DEVICE="${2:-}"; shift 2 ;;
    --headless) HEADLESS=true; shift ;;
    --cold-boot) EXTRA+=(-no-snapshot-load); shift ;;
    --wipe) EXTRA+=(-wipe-data); shift ;;
    --no-animations) NO_ANIM=1; shift ;;
    -h|--help) sed -n '2,/^# =====*$/p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done
DEVICE="$(device_name "$DEVICE")"

if [ ! -f "$AVD_HOME/$DEVICE.avd/config.ini" ]; then
  if [ "$DEVICE" = "$AVD_NAME" ]; then die "AVD '$AVD_NAME' not found. Run: $(cmd setup.sh)"; fi
  die "No device named '$DEVICE'. Create it with: $(cmd devices.sh) create $DEVICE --profile phone|small|large|tablet|foldable"
fi
[ "$HEADLESS" = true ] && EXTRA+=(-no-window)

# --- 1. adb server (localhost only; Docker reaches it via host.docker.internal)
adb_host start-server >/dev/null 2>&1 || die "Could not start adb server on port $ADB_SERVER_PORT"

# --- 2. Launch (unless this device is already running) -------------------------
PID_FILE="$RUN_DIR/emulator-$DEVICE.pid"
LOG_FILE="$LOG_DIR/emulator-$DEVICE.log"
if serial="$(serial_for_device "$DEVICE")" && [ -n "$serial" ]; then
  ok "Device '$DEVICE' already running: $serial"
else
  mkdir -p "$LOG_DIR" "$RUN_DIR"
  others="$(running_emulators | wc -l | tr -d ' ')"
  info "Starting device '$DEVICE' (GPU: $EMULATOR_GPU, headless: $HEADLESS${others:+, $others other(s) running})"
  # The emulator picks the next free console/adb port pair (5554/5555, 5556/5557, …).
  nohup "$EMULATOR_BIN" -avd "$DEVICE" \
    -gpu "$EMULATOR_GPU" -no-boot-anim -no-metrics \
    -netdelay none -netspeed full \
    ${EXTRA[@]+"${EXTRA[@]}"} >"$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
fi

# --- 3. Wait for full boot ------------------------------------------------------
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
info "Waiting for '$DEVICE' to finish booting (timeout ${BOOT_TIMEOUT}s)"
pid="$(cat "$PID_FILE" 2>/dev/null || true)"
serial=""
for ((i = 0; i < BOOT_TIMEOUT; i += 2)); do
  serial="$(serial_for_device "$DEVICE")"
  if [ -n "$serial" ] && [ "$(adb_host -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
    break
  fi
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && [ -z "$serial" ]; then
    tail -20 "$LOG_FILE" >&2
    die "Emulator exited during boot (full log: $LOG_FILE)"
  fi
  sleep 2
done
[ -n "$serial" ] || die "Timed out waiting for '$DEVICE' (log: $LOG_FILE)"
export ANDROID_SERIAL="$serial"

# --- 4. Post-boot tweaks ----------------------------------------------------------
# Unlock the screen so taps/screenshots hit the app, not the lock screen.
adb_host shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb_host shell wm dismiss-keyguard >/dev/null 2>&1 || true
# The emulator's virtual touchscreens advertise stylus buttons, so Gboard pops
# a full-screen "Try out your stylus" tutorial on first text input, stealing
# focus from the app and breaking automated typing/taps. Turn it off.
adb_host shell settings put secure stylus_handwriting_enabled 0 >/dev/null 2>&1 || true
if [ "$NO_ANIM" = 1 ]; then
  for s in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb_host shell settings put global "$s" 0
  done
  ok "System animations disabled"
fi
# Metro: device 127.0.0.1:PORT -> macOS 127.0.0.1:PORT -> container (published port)
adb_host reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null
ok "Device '$DEVICE' ready: $serial (Metro port $METRO_PORT reversed)"
