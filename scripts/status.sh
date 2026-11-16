#!/usr/bin/env bash
# =============================================================================
# Health check for the whole environment. Exit code 0 = everything needed for
# development is up; 1 = something is missing (details printed).
#
#   scripts/status.sh
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config

FAIL=0
pass() { ok "$1"; }
fail() { printf '%s ✗%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; FAIL=1; }
note() { warn "$1"; }

echo "Expo Emulator status" >&2

# --- Host SDK ------------------------------------------------------------------
if [ -x "$ADB" ] && [ -x "$EMULATOR_BIN" ]; then
  pass "Isolated SDK: $SDK_DIR (adb $(cat "$SDK_DIR/platform-tools/.installed" 2>/dev/null), emulator $(cat "$SDK_DIR/emulator/.installed" 2>/dev/null))"
else
  fail "Isolated SDK missing — run $(cmd setup.sh)"
fi
[ -f "$AVD_HOME/$AVD_NAME.avd/config.ini" ] && pass "AVD: $AVD_NAME" || fail "AVD '$AVD_NAME' missing — run $(cmd setup.sh)"

# --- Emulator + adb server -------------------------------------------------------
emus=""
if [ -x "$ADB" ]; then
  if lsof -nP -iTCP:"$ADB_SERVER_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    pass "adb server listening on 127.0.0.1:$ADB_SERVER_PORT"
    emus="$(running_targets)"
  else
    fail "adb server not running — $(cmd emulator-start.sh) starts it"
  fi
fi
# One block per running device (several can run at once).
# Read from fd 3: `adb shell` inside the loop would otherwise consume stdin
# (the device list) and silently skip the remaining devices.
while read -r serial name kind <&3; do
  [ -n "$serial" ] || continue
  api="$(adb_host -s "$serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
  booted="$(adb_host -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  label=Device; [ "$kind" = usb ] && label=Phone
  if [ "$booted" = 1 ]; then pass "$label '$name': $serial (API $api, booted)"; else fail "$label '$name' ($serial) still booting"; fi
  rev="$(adb_host -s "$serial" reverse --list 2>/dev/null || true)"
  if [[ "$rev" == *"tcp:$METRO_PORT"* ]]; then pass "  adb reverse tcp:$METRO_PORT active"
  else note "  adb reverse for Metro not set ($(cmd expo.sh) or $(cmd open-app.sh) set it)"; fi
  pkgs="$(adb_host -s "$serial" shell pm list packages host.exp.exponent 2>/dev/null || true)"
  if [[ "$pkgs" == *exponent* ]]; then pass "  Expo Go installed"
  else note "  Expo Go not installed yet ($(cmd open-app.sh) installs it)"; fi
done 3<<<"$emus"
if [ -x "$ADB" ] && [ -z "$emus" ] && lsof -nP -iTCP:"$ADB_SERVER_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  fail "No emulator running — $(cmd emulator-start.sh)"
fi

# --- Container runtime (Docker Desktop or Kiri) -----------------------------------
if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
  fail "$RUNTIME_NAME not running (CONTAINER_RUNTIME=$CONTAINER_RUNTIME)"
else
  pass "Container runtime: $RUNTIME_NAME ($(docker info -f '{{.NCPU}} CPUs, server {{.ServerVersion}}' 2>/dev/null))"
  if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    fail "Image missing — $(cmd setup.sh)"
  elif image_outdated; then
    note "Image $IMAGE_NAME is from older sources — next start rebuilds it"
  else
    pass "Image $IMAGE_NAME built (up to date)"
  fi
  if container_running; then
    mounted="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME")"
    # Docker Desktop reports bind sources with a /host_mnt prefix.
    pass "Container running (project: ${mounted#/host_mnt})"
    # Proves the container -> host.docker.internal -> adb server -> emulator path.
    if docker exec "$CONTAINER_NAME" adb devices 2>/dev/null | grep -qE '^emulator-[0-9]+\s+device'; then
      pass "Container sees the emulator through adb"
    else
      fail "Container cannot see the emulator via adb (is the emulator running?)"
    fi
  else
    fail "Container not running — $(cmd start.sh) /path/to/expo-app"
  fi
fi

# --- Metro -----------------------------------------------------------------------------
if curl -fs --max-time 2 "http://127.0.0.1:$METRO_PORT/status" 2>/dev/null | grep -q running; then
  pass "Metro running on 127.0.0.1:$METRO_PORT"
else
  note "Metro not running ($(cmd expo.sh))"
fi

exit "$FAIL"
