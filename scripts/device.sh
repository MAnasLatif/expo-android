#!/usr/bin/env bash
# =============================================================================
# Drive the emulator from the terminal — built for humans and AI agents.
#
#   scripts/device.sh tap X Y                 tap at pixel coordinates
#   scripts/device.sh swipe X1 Y1 X2 Y2 [ms]  swipe (default 300 ms)
#   scripts/device.sh scroll down|up          scroll the middle of the screen
#   scripts/device.sh text "hello world"      type into the focused field
#   scripts/device.sh key BACK|HOME|ENTER|…   press a key (KEYCODE_ name or number)
#   scripts/device.sh back | home             shortcuts
#   scripts/device.sh ui                      list on-screen elements + tap centers
#   scripts/device.sh find "Sign in"          print center "X Y" of matching element
#   scripts/device.sh tap-text "Sign in"      find an element by text and tap it
#   scripts/device.sh logcat [--errors|--all] [-n N] [--follow] [--clear]
#   scripts/device.sh reload                  reload the JS bundle (Expo Go)
#   scripts/device.sh devmenu                 open the React Native dev menu
#   scripts/device.sh open-url URL            open a deep link
#   scripts/device.sh activity                show the foreground app/activity
#   scripts/device.sh size                    screen size in pixels
#   scripts/device.sh adb ARGS…               raw adb against the emulator
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config

cmd="${1:-help}"; shift || true
case "$cmd" in help|-h|--help) sed -n '2,21p' "$0"; exit 0 ;; esac
require_device
sh() { adb_host shell "$@"; }

# Screen size "W H" (respects overrides from `wm size`).
screen_size() {
  sh wm size | tr -d '\r' | awk -F'[ x]' '/Override/ {w=$3; h=$4} /Physical/ && !w {w=$3; h=$4} END {print w, h}'
}

# Dump the UI hierarchy and print one line per meaningful node:
#   <centerX> <centerY> | text | content-desc | resource-id | class | clickable
ui_rows() {
  sh uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || die "uiautomator dump failed (is the screen locked or animating?)"
  adb_host exec-out cat /sdcard/window_dump.xml | perl -ne '
    while (/<node ([^>]*?)\/?>/g) {
      my $a = $1; my %h;
      $h{$1} = $2 while $a =~ /([\w-]+)="([^"]*)"/g;
      next unless length($h{text}) || length($h{"content-desc"}) || $h{clickable} eq "true";
      my ($x1,$y1,$x2,$y2) = $h{bounds} =~ /\[(\d+),(\d+)\]\[(\d+),(\d+)\]/;
      next if $x2 <= $x1 || $y2 <= $y1;
      printf "%d %d | %s | %s | %s | %s | %s\n", ($x1+$x2)/2, ($y1+$y2)/2,
        $h{text}, $h{"content-desc"}, $h{"resource-id"}, $h{class},
        $h{clickable} eq "true" ? "clickable" : "";
    }'
}

# Center of the first element whose text or content-desc contains $1 (case-insensitive).
find_xy() {
  local needle="$1"
  ui_rows | awk -F' \\| ' -v n="$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')" '
    { t = tolower($2); d = tolower($3) }
    index(t, n) || index(d, n) { split($1, xy, " "); print xy[1], xy[2]; found = 1; exit }
    END { exit !found }'
}

case "$cmd" in
  tap)      [ $# -eq 2 ] || die "usage: tap X Y"; sh input tap "$1" "$2" ;;
  swipe)    [ $# -ge 4 ] || die "usage: swipe X1 Y1 X2 Y2 [ms]"; sh input swipe "$1" "$2" "$3" "$4" "${5:-300}" ;;
  scroll)
    read -r w h < <(screen_size)
    x=$((w / 2)); top=$((h * 30 / 100)); bottom=$((h * 70 / 100))
    case "${1:-down}" in
      down) sh input swipe "$x" "$bottom" "$x" "$top" 300 ;;   # content moves up
      up)   sh input swipe "$x" "$top" "$x" "$bottom" 300 ;;
      *) die "usage: scroll down|up" ;;
    esac ;;
  text)
    [ $# -ge 1 ] || die "usage: text \"string\""
    # `input text` needs spaces as %s and shell metacharacters escaped.
    escaped="$(printf '%s' "$*" | sed -e 's/[][(){}<>|;&*?~^$`"'"'"'\\]/\\&/g' -e 's/ /%s/g')"
    sh input text "$escaped" ;;
  key)
    [ $# -eq 1 ] || die "usage: key NAME|CODE"
    k="$1"; [[ "$k" =~ ^[0-9]+$ ]] || k="KEYCODE_${k#KEYCODE_}"
    sh input keyevent "$k" ;;
  back)     sh input keyevent KEYCODE_BACK ;;
  home)     sh input keyevent KEYCODE_HOME ;;
  ui)
    echo "# centerX centerY | text | content-desc | resource-id | class | clickable"
    ui_rows ;;
  find)     [ $# -ge 1 ] || die "usage: find \"text\""; find_xy "$*" || die "No element matching: $*" ;;
  tap-text)
    [ $# -ge 1 ] || die "usage: tap-text \"text\""
    xy="$(find_xy "$*")" || die "No element matching: $*"
    # shellcheck disable=SC2086
    sh input tap $xy
    ok "Tapped \"$*\" at $xy" ;;
  logcat)
    n=300 mode=app follow=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --errors) mode=errors ;; --all) mode=all ;; --follow|-f) follow=1 ;;
        --clear) adb_host logcat -c; ok "logcat cleared"; exit 0 ;;
        -n) n="$2"; shift ;;
        *) die "unknown logcat option: $1" ;;
      esac; shift
    done
    case "$mode" in
      app)    filter=(ReactNativeJS:V ReactNative:V Expo:V ExpoModulesCore:V AndroidRuntime:E '*:S') ;;
      errors) filter=('*:E') ;;
      all)    filter=() ;;
    esac
    # ${a[@]+...} form: empty arrays break `set -u` on macOS bash 3.2.
    # Filter first, then keep the last N lines (`logcat -t N` would cut
    # before filtering and usually return nothing).
    if [ "$follow" = 1 ]; then adb_host logcat -v time ${filter[@]+"${filter[@]}"}
    else adb_host logcat -d -v time ${filter[@]+"${filter[@]}"} | tail -n "$n"; fi ;;
  reload)   sh input keyevent KEYCODE_R KEYCODE_R; ok "Reload requested" ;;
  devmenu)  sh input keyevent KEYCODE_MENU ;;
  open-url) [ $# -eq 1 ] || die "usage: open-url URL"; sh am start -a android.intent.action.VIEW -d "$1" >/dev/null ;;
  activity) sh dumpsys activity activities | tr -d '\r' | grep -m1 -E 'topResumedActivity|mResumedActivity' | sed 's/^ *//' ;;
  size)     screen_size ;;
  adb)      adb_host "$@" ;;
  *) die "Unknown command: $cmd (try: $(cmd device.sh)$([ -n "${EXPOEMU_CLI:-}" ] || echo ' help'))" ;;
esac
