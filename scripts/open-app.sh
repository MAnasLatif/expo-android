#!/usr/bin/env bash
# =============================================================================
# Open the running Expo project in Expo Go on one or all running devices.
# Installs the Expo Go build matching the project's SDK if it is missing.
#
#   scripts/open-app.sh [--all] [--reinstall] [--url exp://...] [--first-run]
#
# --all:       open on every running device (one Metro serves them all);
#              otherwise the target device (--device / EXPOEMU_DEVICE / default).
# --first-run: Expo Go was just installed or its data cleared, so it will show
#              its one-time developer-menu introduction over the app; wait for
#              it and dismiss it (done automatically after installing Expo Go).
#
# The APK is downloaded inside the container (cached in the expo-home volume)
# and installed through the shared adb server — nothing is stored on macOS.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_docker
container_running || die "Container not running. Start it with: $(cmd start.sh) /path/to/expo-app"

ALL=0 REINSTALL=0 FIRST_RUN_FLAG=0 URL="exp://127.0.0.1:$METRO_PORT"
while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=1; shift ;;
    --reinstall) REINSTALL=1; shift ;;
    --first-run) FIRST_RUN_FLAG=1; shift ;;
    --url) URL="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^# =====*$/p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done
EXPO_GO_PKG=host.exp.exponent

curl -fs --max-time 2 "http://127.0.0.1:$METRO_PORT/status" | grep -q running \
  || warn "Metro is not responding on 127.0.0.1:$METRO_PORT — start it with $(cmd expo.sh)"

# open_on SERIAL — install Expo Go if needed, tunnel Metro, open the project.
open_on() {
  export ANDROID_SERIAL="$1"
  local first_run="$FIRST_RUN_FLAG" pkgs
  pkgs="$(adb_host shell pm list packages "$EXPO_GO_PKG" 2>/dev/null || true)"

  # --- 1. Ensure Expo Go is installed -------------------------------------------
  if [ "$REINSTALL" = 1 ] || [[ "$pkgs" != *"$EXPO_GO_PKG"* ]]; then
    info "Installing Expo Go for this project's Expo SDK on $ANDROID_SERIAL"
    # Runs in the container: resolve SDK -> APK URL via api.expo.dev, cache, install.
    docker exec -u expo -w /workspace -e ANDROID_SERIAL="$ANDROID_SERIAL" "$CONTAINER_NAME" bash -lc '
      set -euo pipefail
      sdk_major="$(node -p "require(\"expo/package.json\").version.split(\".\")[0]")"
      url="$(curl -fsSL https://api.expo.dev/v2/versions/latest \
        | jq -r --arg v "${sdk_major}.0.0" ".data.sdkVersions[\$v].androidClientUrl // empty")"
      [ -n "$url" ] || { echo "No Expo Go build found for SDK ${sdk_major}" >&2; exit 1; }
      apk="$HOME/.expo/expo-go/$(basename "$url")"
      mkdir -p "$(dirname "$apk")"
      [ -s "$apk" ] || curl -fL --progress-bar -o "$apk" "$url"
      echo "Installing $(basename "$apk")"
      adb install -r -g "$apk"
    '
    ok "Expo Go installed on $ANDROID_SERIAL"
    first_run=1
  fi

  # An intro still on screen (e.g. an earlier wait gave up on a slow device) was
  # never acknowledged, so it will show again after reopening: wait for it.
  local device; device="$(dirname "$0")/device.sh"
  if [ "$first_run" = 0 ] && EXPOEMU_DEVICE="$ANDROID_SERIAL" bash "$device" find "This is the developer menu" >/dev/null 2>&1; then
    first_run=1
  fi

  # --- 2. Tunnel + deep link ----------------------------------------------------------
  adb_host reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null
  # Force-stop first: after a quick-boot snapshot Expo Go may still show an old
  # experience, and a deep link to it only brings it to the front without
  # fetching a fresh bundle from the current Metro.
  adb_host shell am force-stop "$EXPO_GO_PKG"
  adb_host shell am start -a android.intent.action.VIEW -d "$URL" "$EXPO_GO_PKG" >/dev/null
  ok "Opened $URL in Expo Go on $ANDROID_SERIAL"

  # --- 3. Fresh Expo Go: dismiss its one-time developer-menu introduction ---------
  # It covers the app until "Continue" is tapped (which opens the full dev menu,
  # closed with "Close"). Only done when we know it will appear.
  # The first bundle can take minutes on a small device while other emulators
  # run, so wait generously (only when we know the intro will appear).
  if [ "$first_run" = 1 ]; then
    info "Waiting for Expo Go's first-run developer menu on $ANDROID_SERIAL (bundle may still be building)"
    if EXPOEMU_DEVICE="$ANDROID_SERIAL" bash "$device" wait-for "This is the developer menu" --timeout 240 >/dev/null 2>&1; then
      dismiss_intro "$device"
    else
      warn "Expo Go's first-run menu did not appear on $ANDROID_SERIAL; nothing to dismiss"
    fi
  fi
}

# "Continue" opens the full dev menu, "Close" closes it.
dismiss_intro() {
  EXPOEMU_DEVICE="$ANDROID_SERIAL" bash "$1" tap-text "Continue" >/dev/null 2>&1 || true
  sleep 1
  EXPOEMU_DEVICE="$ANDROID_SERIAL" bash "$1" tap-text "Close" >/dev/null 2>&1 || true
  ok "Dismissed Expo Go's first-run developer menu on $ANDROID_SERIAL"
}

if [ "$ALL" = 1 ]; then
  require_sdk
  serials="$(running_targets | awk '{print $1}')"
  [ -n "$serials" ] || die "No running emulator. Start one with: $(cmd emulator-start.sh)"
  for s in $serials; do open_on "$s"; done
else
  require_device
  open_on "$ANDROID_SERIAL"
fi
