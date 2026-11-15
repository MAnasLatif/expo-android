#!/usr/bin/env bash
# =============================================================================
# Capture the emulator screen as PNG.
#
#   scripts/screenshot.sh [name]
#
# Saves to <project>/.android-screenshots/<name>-<timestamp>.png and also
# overwrites latest.png. Prints ONLY the absolute file path on stdout, so tools
# and AI agents can capture it:  img="$(scripts/screenshot.sh home)"
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_device

name="${1:-screenshot}"
name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')"
dir="$(screenshot_dir)"
file="$dir/${name}-$(date +%Y%m%d-%H%M%S).png"

# exec-out streams raw bytes (no CRLF mangling, unlike `adb shell`).
adb_host exec-out screencap -p > "$file"
[ -s "$file" ] || { rm -f "$file"; die "Screenshot failed (empty output)"; }
cp "$file" "$dir/latest.png"

printf '%s\n' "$file"
