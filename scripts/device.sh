#!/usr/bin/env bash
# =============================================================================
# Drive the emulator from the terminal — built for humans and AI agents.
#
# TOUCH
#   tap X Y                      tap at pixel coordinates
#   double-tap X Y               two quick taps
#   long-press X Y [ms]          press and hold (default 800 ms)
#   swipe X1 Y1 X2 Y2 [ms]       swipe (default 300 ms)
#   drag X1 Y1 X2 Y2 [ms]        drag and drop (default 1000 ms)
#   scroll down|up|left|right    scroll the middle of the screen
#
# ELEMENTS (match visible text, accessibilityLabel, testID or placeholder;
#           exact match preferred, else case-insensitive "contains")
#   ui                           list on-screen elements with tap coordinates
#   find "Sign in"               print center "X Y" of the element
#   tap-text "Sign in"           tap an element
#   long-press-text "Item" [ms]  long-press an element
#   scroll-to "Row 30" [--up] [--max N]   scroll until the element is visible
#   texts                        list visible text only (compact)
#   ui --xml                     save the raw view hierarchy XML, print its path
#
# WAIT & ASSERT (exit 0 = success, 1 = failure — usable as test steps)
#   wait-for "Welcome" [--timeout S]      wait until an element appears (default 15 s)
#   wait-gone "Loading" [--timeout S]     wait until an element disappears
#   assert-text "Welcome"                 fail unless the element is on screen
#   assert-no-text "Error"                fail if the element is on screen
#
# KEYBOARD & KEYS
#   text "hello world"           type into the focused field
#   clear                        clear the focused field
#   fill "Email" "me@x.com" [--keep-keyboard]
#                                tap a field, clear it, type, hide the keyboard
#   hide-keyboard                close the on-screen keyboard if shown
#   key NAME|CODE                any key (BACK, ENTER, TAB, VOLUME_UP, …)
#   back | home | recents | enter
#   lock | unlock                screen off / wake and dismiss the lock screen
#
# EXPO / APP
#   reload                       reload the JS bundle
#   devmenu                      open the React Native dev menu
#   open-url URL                 open a deep link
#   activity                     show the foreground app/activity
#   size                         screen size in pixels
#   logcat [--errors|--all] [-n N] [--follow] [--clear]
#   adb ARGS…                    raw adb against the emulator
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config

cmd="${1:-help}"; shift || true
case "$cmd" in help|-h|--help) sed -n '2,/^# =====*$/p' "$0"; exit 0 ;; esac
require_device
sh() { adb_host shell "$@"; }

# Screen size "W H" (respects overrides from `wm size`).
screen_size() {
  sh wm size | tr -d '\r' | awk -F'[ x]' '/Override/ {w=$3; h=$4} /Physical/ && !w {w=$3; h=$4} END {print w, h}'
}

# Bounds "x1 y1 x2 y2" of the largest scrollable view on screen, or the whole
# screen if none. Swipes must START inside a scroll view to scroll it.
scroll_area() {
  local area
  sh uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  area="$(adb_host exec-out cat /sdcard/window_dump.xml 2>/dev/null | perl -ne '
    while (/<node ([^>]*?)\/?>/g) {
      my $a = $1;
      next unless $a =~ /scrollable="true"/;
      my ($x1,$y1,$x2,$y2) = $a =~ /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/;
      my $s = ($x2-$x1)*($y2-$y1);
      if ($s > $best) { $best = $s; $b = "$x1 $y1 $x2 $y2" }
    }
    END { print $b if $b }')"
  if [ -n "$area" ]; then echo "$area"; else read -r w h < <(screen_size); echo "0 0 $w $h"; fi
}

# Dump the UI hierarchy and print one line per meaningful node:
#   <centerX> <centerY> | text | content-desc | resource-id | class | flags
# text falls back to the field's hint (placeholder) when the field is empty.
ui_rows() {
  sh uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || die "uiautomator dump failed (is the screen locked or animating?)"
  adb_host exec-out cat /sdcard/window_dump.xml | perl -ne '
    while (/<node ([^>]*?)\/?>/g) {
      my $a = $1; my %h;
      $h{$1} = $2 while $a =~ /([\w-]+)="([^"]*)"/g;
      my $text = length($h{text}) ? $h{text} : ($h{hint} // "");
      # React Native testIDs appear as bare resource-ids ("login-button");
      # framework/app ids ("android:id/content") are noise, so drop them.
      my $id = $h{"resource-id"} // ""; $id = "" if $id =~ /:id\//;
      next unless length($text) || length($h{"content-desc"}) || length($id) || $h{clickable} eq "true";
      my ($x1,$y1,$x2,$y2) = $h{bounds} =~ /\[(\d+),(\d+)\]\[(\d+),(\d+)\]/;
      next if $x2 <= $x1 || $y2 <= $y1;
      my @f;
      push @f, "clickable" if $h{clickable} eq "true";
      push @f, "focused"   if $h{focused} eq "true";
      push @f, "checked"   if $h{checked} eq "true";
      push @f, "disabled"  if $h{enabled} eq "false";
      printf "%d %d | %s | %s | %s | %s | %s\n", ($x1+$x2)/2, ($y1+$y2)/2,
        $text, $h{"content-desc"}, $id, $h{class}, join(",", @f);
    }'
}

# Center "X Y" of the element matching $1 in text, content-desc or resource-id
# (testID). Exact (case-insensitive) match wins over a "contains" match.
find_xy() {
  local needle
  needle="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  ui_rows | awk -F' \\| ' -v n="$needle" '
    {
      t = tolower($2); d = tolower($3); id = tolower($4)
      split($1, xy, " ")
      if (!exact && (t == n || d == n || id == n)) { exact = xy[1] " " xy[2] }
      if (!partial && (index(t, n) || index(d, n) || index(id, n))) { partial = xy[1] " " xy[2] }
    }
    END {
      if (exact) print exact; else if (partial) print partial; else exit 1
    }'
}

need_xy() { find_xy "$1" || die "No element matching: $1"; }

# `input text` needs spaces as %s and shell metacharacters escaped.
type_text() {
  local escaped
  escaped="$(printf '%s' "$1" | sed -e 's/[][(){}<>|;&*?~^$`"'"'"'\\]/\\&/g' -e 's/ /%s/g')"
  sh input text "$escaped"
}

# Select-all + delete in the focused field (keycombination needs Android 13+;
# fall back to many DELs after moving to the end).
clear_field() {
  if ! sh input keycombination KEYCODE_CTRL_LEFT KEYCODE_A >/dev/null 2>&1; then
    sh input keyevent KEYCODE_MOVE_END
    sh "for i in \$(seq 1 80); do input keyevent KEYCODE_DEL; done"
    return
  fi
  sh input keyevent KEYCODE_DEL
}

# Capture first, match after: `cmd | grep -q` under `set -o pipefail` can fail
# with SIGPIPE (exit 141) when grep exits before the writer finishes.
keyboard_shown() {
  local out
  out="$(sh dumpsys window InputMethod 2>/dev/null)"
  [[ "$out" == *"isVisible=true"* ]]
}

# Hide the on-screen keyboard if it is (or is about to be) visible. The IME
# animates in after a field gets focus, so poll briefly instead of checking once.
# Anything that swipes or taps app content calls this first: a swipe across
# the keyboard becomes glide typing, and a tap may hit a key instead of the app.
ensure_keyboard_hidden() {
  local tries="${1:-5}" i
  for ((i = 0; i < tries; i++)); do
    if keyboard_shown; then sh input keyevent KEYCODE_BACK; sleep 0.3; return 0; fi
    sleep 0.2
  done
  return 1
}

case "$cmd" in
  # --- Touch ------------------------------------------------------------------
  tap)        [ $# -eq 2 ] || die "usage: tap X Y"; sh input tap "$1" "$2" ;;
  double-tap) [ $# -eq 2 ] || die "usage: double-tap X Y"
              # One shell call keeps both taps within the double-tap window.
              sh "input tap $1 $2; input tap $1 $2" ;;
  long-press) [ $# -ge 2 ] || die "usage: long-press X Y [ms]"
              sh input swipe "$1" "$2" "$1" "$2" "${3:-800}" ;;
  swipe)      [ $# -ge 4 ] || die "usage: swipe X1 Y1 X2 Y2 [ms]"; sh input swipe "$1" "$2" "$3" "$4" "${5:-300}" ;;
  drag)       [ $# -ge 4 ] || die "usage: drag X1 Y1 X2 Y2 [ms]"; sh input draganddrop "$1" "$2" "$3" "$4" "${5:-1000}" ;;
  scroll)
    ensure_keyboard_hidden 1 || true
    # Swipe within the scrollable container (25%..75% of its size).
    read -r ax1 ay1 ax2 ay2 < <(scroll_area)
    x=$(((ax1 + ax2) / 2)); y=$(((ay1 + ay2) / 2))
    top=$((ay1 + (ay2 - ay1) * 25 / 100)); bottom=$((ay1 + (ay2 - ay1) * 75 / 100))
    left=$((ax1 + (ax2 - ax1) * 20 / 100)); right=$((ax1 + (ax2 - ax1) * 80 / 100))
    case "${1:-down}" in
      down)  sh input swipe "$x" "$bottom" "$x" "$top" 300 ;;   # content moves up
      up)    sh input swipe "$x" "$top" "$x" "$bottom" 300 ;;
      right) sh input swipe "$right" "$y" "$left" "$y" 300 ;;   # content moves left
      left)  sh input swipe "$left" "$y" "$right" "$y" 300 ;;
      *) die "usage: scroll down|up|left|right" ;;
    esac ;;

  # --- Elements ---------------------------------------------------------------
  ui)
    if [ "${1:-}" = "--xml" ]; then
      sh uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || die "uiautomator dump failed"
      file="$(screenshot_dir)/ui-$(date +%Y%m%d-%H%M%S).xml"
      adb_host exec-out cat /sdcard/window_dump.xml > "$file"
      printf '%s\n' "$file"; exit 0
    fi
    echo "# centerX centerY | text | content-desc | testID | class | flags"
    ui_rows ;;
  texts)
    # Visible strings only (text or accessibility label), de-duplicated.
    ui_rows | awk -F' \\| ' '{ s = length($2) ? $2 : $3; if (length(s) && !seen[s]++) print s }' ;;
  find)       [ $# -ge 1 ] || die "usage: find \"text\""; need_xy "$*" ;;
  tap-text)
    [ $# -ge 1 ] || die "usage: tap-text \"text\""
    ensure_keyboard_hidden 1 || true   # element may sit under the keyboard
    xy="$(need_xy "$*")"
    # shellcheck disable=SC2086
    sh input tap $xy
    ok "Tapped \"$*\" at $xy" ;;
  long-press-text)
    [ $# -ge 1 ] || die "usage: long-press-text \"text\" [ms]"
    ensure_keyboard_hidden 1 || true
    xy="$(need_xy "$1")"; read -r x y <<<"$xy"
    sh input swipe "$x" "$y" "$x" "$y" "${2:-800}"
    ok "Long-pressed \"$1\" at $xy" ;;
  scroll-to)
    [ $# -ge 1 ] || die "usage: scroll-to \"text\" [--up] [--max N]"
    needle="$1"; shift; dir=down; max=15
    while [ $# -gt 0 ]; do
      case "$1" in --up) dir=up ;; --max) max="$2"; shift ;; *) die "unknown option: $1" ;; esac; shift
    done
    for ((i = 0; i <= max; i++)); do
      if xy="$(find_xy "$needle")"; then echo "$xy"; exit 0; fi
      [ "$i" -lt "$max" ] && bash "$0" scroll "$dir" && sleep 0.4
    done
    die "\"$needle\" not found after $max scrolls" ;;

  # --- Wait & assert ------------------------------------------------------------
  wait-for|wait-gone)
    [ $# -ge 1 ] || die "usage: $cmd \"text\" [--timeout SECONDS]"
    needle="$1"; shift; timeout=15
    while [ $# -gt 0 ]; do
      case "$1" in --timeout) timeout="$2"; shift ;; *) die "unknown option: $1" ;; esac; shift
    done
    deadline=$((SECONDS + timeout))
    while :; do
      if xy="$(find_xy "$needle")"; then
        [ "$cmd" = wait-for ] && { echo "$xy"; exit 0; }
      else
        [ "$cmd" = wait-gone ] && { ok "\"$needle\" is gone"; exit 0; }
      fi
      [ "$SECONDS" -ge "$deadline" ] && break
      sleep 0.5
    done
    if [ "$cmd" = wait-for ]; then die "Timed out after ${timeout}s waiting for \"$needle\""
    else die "Timed out after ${timeout}s: \"$needle\" is still on screen"; fi ;;
  assert-text)
    [ $# -ge 1 ] || die "usage: assert-text \"text\""
    if xy="$(find_xy "$*")"; then ok "Found \"$*\" at $xy"; else die "Assertion failed: \"$*\" is not on screen"; fi ;;
  assert-no-text)
    [ $# -ge 1 ] || die "usage: assert-no-text \"text\""
    if xy="$(find_xy "$*")"; then die "Assertion failed: \"$*\" is on screen at $xy"; else ok "\"$*\" is not on screen"; fi ;;

  # --- Keyboard & keys --------------------------------------------------------
  text)       [ $# -ge 1 ] || die "usage: text \"string\""; type_text "$*" ;;
  clear)      clear_field ;;
  fill)
    [ $# -ge 2 ] || die "usage: fill \"field text/testID\" \"value\" [--keep-keyboard]"
    ensure_keyboard_hidden 1 || true
    xy="$(need_xy "$1")"
    # shellcheck disable=SC2086
    sh input tap $xy
    sleep 0.3; clear_field; type_text "$2"
    # Hide the keyboard so it can't cover the next element an agent taps.
    [ "${3:-}" = "--keep-keyboard" ] || ensure_keyboard_hidden || true
    ok "Filled \"$1\" with \"$2\"" ;;
  hide-keyboard)
    if ensure_keyboard_hidden; then ok "Keyboard hidden"; else ok "Keyboard not shown"; fi ;;
  key)
    [ $# -eq 1 ] || die "usage: key NAME|CODE"
    k="$1"; [[ "$k" =~ ^[0-9]+$ ]] || k="KEYCODE_$(printf '%s' "${k#KEYCODE_}" | tr '[:lower:]' '[:upper:]')"
    sh input keyevent "$k" ;;
  back)       sh input keyevent KEYCODE_BACK ;;
  home)       sh input keyevent KEYCODE_HOME ;;
  recents)    sh input keyevent KEYCODE_APP_SWITCH ;;
  enter)      sh input keyevent KEYCODE_ENTER ;;
  lock)       sh input keyevent KEYCODE_SLEEP ;;
  unlock)
    sh input keyevent KEYCODE_WAKEUP; sh wm dismiss-keyguard
    sleep 1
    # A PIN set by `biometric enroll`: type it (swipe-only locks are already gone).
    if keyguard_showing && [ -f "$(pin_file)" ]; then
      sh input text "$(cat "$(pin_file)")"; sh input keyevent KEYCODE_ENTER; sleep 1
    fi
    if keyguard_showing; then die "Still locked — the screen lock needs a PIN/password expoemu doesn't know"; fi
    ok "Unlocked" ;;

  # --- Expo / app ---------------------------------------------------------------
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
  reload)     sh input keyevent KEYCODE_R KEYCODE_R; ok "Reload requested" ;;
  devmenu)    sh input keyevent KEYCODE_MENU ;;
  open-url)   [ $# -eq 1 ] || die "usage: open-url URL"; sh am start -a android.intent.action.VIEW -d "$1" >/dev/null ;;
  # awk reads all input (no early exit), avoiding SIGPIPE under pipefail.
  activity)   sh dumpsys activity activities | tr -d '\r' \
                | awk '/topResumedActivity|mResumedActivity/ && !f { sub(/^ */, ""); print; f = 1 }' ;;
  size)       screen_size ;;
  adb)        adb_host "$@" ;;
  *) die "Unknown command: $cmd (try: $(cmd device.sh)$([ -n "${EXPOEMU_CLI:-}" ] || echo ' help'))" ;;
esac
