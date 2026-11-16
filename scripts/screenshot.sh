#!/usr/bin/env bash
# =============================================================================
# Capture the emulator screen as PNG.
#
#   scripts/screenshot.sh [name]          target device (--device / default)
#   scripts/screenshot.sh --all [name]    every running device, one PNG each
#
# Saves to <project>/.android-screenshots/<name>[-<device>]-<timestamp>.png and
# also overwrites latest.png. Prints ONLY the absolute file path(s) on stdout,
# so tools and AI agents can capture them:  img="$(scripts/screenshot.sh home)"
# When more than one device is running, the device name is part of the file name.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config

ALL=0
[ "${1:-}" = "--all" ] && { ALL=1; shift; }
name="${1:-screenshot}"
name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')"
dir="$(screenshot_dir)"
stamp="$(date +%Y%m%d-%H%M%S)"

# capture SERIAL DEVICE_NAME — write one PNG, print its path.
capture() {
  local serial="$1" device="$2" file
  file="$dir/${name}${device:+-$device}-$stamp.png"
  # exec-out streams raw bytes (no CRLF mangling, unlike `adb shell`).
  adb_host -s "$serial" exec-out screencap -p > "$file"
  [ -s "$file" ] || { rm -f "$file"; die "Screenshot failed on $serial (empty output)"; }
  cp "$file" "$dir/latest.png"
  printf '%s\n' "$file"
}

if [ "$ALL" = 1 ]; then
  require_sdk
  emus="$(running_emulators)"
  [ -n "$emus" ] || die "No running emulator. Start one with: $(cmd emulator-start.sh)"
  while read -r s n; do capture "$s" "$n"; done <<<"$emus"
else
  require_device
  # Add the device name only when several devices are running (keeps the
  # single-device file names unchanged).
  device=""
  if [ "$(running_emulators | wc -l | tr -d ' ')" -gt 1 ]; then
    device="$(running_emulators | awk -v s="$ANDROID_SERIAL" '$1 == s { print $2 }')"
  fi
  capture "$ANDROID_SERIAL" "$device"
fi
