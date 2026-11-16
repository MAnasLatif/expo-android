#!/usr/bin/env bash
# =============================================================================
# Change emulator/device state — for testing how an app behaves under
# different conditions. All changes are reversible.
#
# DISPLAY
#   rotate portrait|landscape|reverse-portrait|reverse-landscape|auto|status
#                                      (apps locked in app.json "orientation" won't rotate)
#   dark-mode on|off|status            system dark theme
#   font-scale 1.3|reset|status        accessibility text size (0.85 – 2.0)
#   animations on|off                  system animations (off = stable screenshots)
#
# CONNECTIVITY
#   network on|off|status              Wi-Fi + mobile data (Metro keeps working:
#                                      it runs over adb, not the network)
#   network gprs|edge|3g|4g|full       slow-network profile: speed + latency
#                                      (emulators; `full` removes the limits)
#   airplane on|off|status             airplane mode
#
# SENSORS & DEVICE
#   location LAT LON                   set GPS position (e.g. 37.422 -122.084)
#   battery LEVEL|unplug|charge|reset|status
#   notifications open|close|settings  pull down the shade / quick settings
#
# APP CONTEXT (default package: APP_PACKAGE, i.e. Expo Go)
#   permission grant|revoke PERM [PKG] e.g. CAMERA, ACCESS_FINE_LOCATION,
#                                      POST_NOTIFICATIONS, RECORD_AUDIO
#   permission list [PKG]              granted runtime permissions
#   locale TAG|reset|status [PKG]      per-app language, e.g. ar, fr-FR, ja
#                                      (reopen the app to apply)
#
# CAPTURE & INFO
#   record [SECONDS] [name]            screen video (default 10 s, max 180)
#                                      → ./.android-screenshots/<name>.mp4
#   info                               device summary (model, API, screen, state)
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config

cmd="${1:-help}"; shift || true
case "$cmd" in help|-h|--help) sed -n '2,/^# =====*$/p' "$0"; exit 0 ;; esac
require_device
sh() { adb_host shell "$@"; }
# Trimmed single-value read (adb shell output ends with \r).
get() { sh "$@" 2>/dev/null | tr -d '\r'; }

# Expand short permission names: CAMERA -> android.permission.CAMERA
perm_name() {
  case "$1" in *.*) echo "$1" ;; *) echo "android.permission.$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" ;; esac
}

on_off() { case "${1:-}" in on|off|status) ;; *) die "usage: $cmd on|off|status" ;; esac; }

case "$cmd" in
  # --- Display ------------------------------------------------------------------
  rotate)
    # Note: apps locked to one orientation (app.json "orientation": "portrait",
    # the Expo default) and the launcher won't rotate — that's the app's choice.
    case "${1:-status}" in
      portrait) r=0 ;; landscape) r=1 ;; reverse-portrait) r=2 ;; reverse-landscape) r=3 ;;
      auto)   sh wm user-rotation free >/dev/null 2>&1 || sh settings put system accelerometer_rotation 1
              ok "Auto-rotate on"; exit 0 ;;
      status) echo "$(get wm user-rotation) (0=portrait 1=landscape 2/3=reverse)"; exit 0 ;;
      *) die "usage: rotate portrait|landscape|reverse-portrait|reverse-landscape|auto|status" ;;
    esac
    if ! sh wm user-rotation lock "$r" >/dev/null 2>&1; then
      sh settings put system accelerometer_rotation 0
      sh settings put system user_rotation "$r"
    fi
    ok "Rotation: $1 (apps locked to one orientation in app.json stay as they are)" ;;
  dark-mode)
    on_off "${1:-}"
    case "$1" in
      on)  sh cmd uimode night yes >/dev/null; ok "Dark mode on" ;;
      off) sh cmd uimode night no >/dev/null; ok "Dark mode off" ;;
      status) get cmd uimode night ;;
    esac ;;
  font-scale)
    case "${1:-status}" in
      status) echo "font_scale=$(get settings get system font_scale)" ;;
      reset)  sh settings put system font_scale 1.0; ok "Font scale reset to 1.0" ;;
      *) [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "usage: font-scale 1.3|reset|status"
         sh settings put system font_scale "$1"; ok "Font scale: $1" ;;
    esac ;;
  animations)
    case "${1:-}" in on) v=1 ;; off) v=0 ;; *) die "usage: animations on|off" ;; esac
    for s in window_animation_scale transition_animation_scale animator_duration_scale; do
      sh settings put global "$s" "$v"
    done
    ok "Animations $1" ;;

  # --- Connectivity -------------------------------------------------------------
  network)
    case "${1:-}" in
      on)  sh svc wifi enable; sh svc data enable; ok "Network on (Wi-Fi + mobile data)" ;;
      off) sh svc wifi disable; sh svc data disable
           ok "Network off — the app is offline; Metro still works via adb" ;;
      status)
        echo "$(get cmd wifi status | head -1); mobile_data=$(get settings get global mobile_data)"
        # Speed/latency profile (emulator console); phones have no console.
        if is_emulator; then adb_host emu network status 2>/dev/null | tr -d '\r' | sed -n '2,5p'; fi ;;
      gprs|edge|3g|4g|full)
        # Throttle the emulator's modem (speed + latency). Metro is unaffected:
        # it is tunnelled over adb, so the app loads normally but its own
        # network requests are slow — exactly what you want to test.
        is_emulator || die "Network speed profiles need an emulator (phones use their real network)"
        case "$1" in
          gprs) speed=gprs; delay=gprs ;;    # ~58 kbit/s, 150–550 ms
          edge) speed=edge; delay=edge ;;    # ~470 kbit/s, 80–400 ms
          3g)   speed=hsdpa; delay=umts ;;  # 3G/HSPA: ~14 Mbit/s down, 35–200 ms ('umts' speed is only 384 kbit/s)
          4g)   speed=lte;   delay=20:60 ;; # ~173 Mbit/s down, 20–60 ms
          full) speed=full;  delay=none ;;  # no limits (default)
        esac
        [[ "$(adb_host emu network speed "$speed" 2>&1)" == *OK* ]] || die "Emulator rejected network speed $speed"
        [[ "$(adb_host emu network delay "$delay" 2>&1)" == *OK* ]] || die "Emulator rejected network delay $delay"
        if [ "$1" = full ]; then ok "Network speed: full (no throttling)"
        else ok "Network speed: $1 — reset with: $(cmd system.sh | sed 's/ help$//') network full"; fi ;;
      *) die "usage: network on|off|status|gprs|edge|3g|4g|full" ;;
    esac ;;
  airplane)
    on_off "${1:-}"
    case "$1" in
      on)  sh cmd connectivity airplane-mode enable; ok "Airplane mode on" ;;
      off) sh cmd connectivity airplane-mode disable; ok "Airplane mode off" ;;
      status) echo "airplane-mode: $(get cmd connectivity airplane-mode)" ;;
    esac ;;

  # --- Sensors & device ---------------------------------------------------------
  location)
    [ $# -eq 2 ] || die "usage: location LAT LON   (e.g. location 37.422 -122.084)"
    # The emulator console takes longitude first.
    adb_host emu geo fix "$2" "$1" >/dev/null || die "Failed to set location"
    ok "Location set to $1, $2" ;;
  battery)
    case "${1:-status}" in
      unplug) sh dumpsys battery unplug; ok "Charger unplugged" ;;
      charge) sh dumpsys battery set ac 1; sh dumpsys battery set status 2; ok "Charging (AC)" ;;
      reset)  sh dumpsys battery reset; ok "Battery back to real state" ;;
      status) get dumpsys battery | awk '/level|AC powered|status:/ { sub(/^ */, ""); print }' ;;
      *) [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -le 100 ] || die "usage: battery LEVEL|unplug|charge|reset|status"
         sh dumpsys battery unplug; sh dumpsys battery set level "$1"; ok "Battery level: $1%" ;;
    esac ;;
  notifications)
    case "${1:-open}" in
      open)     sh cmd statusbar expand-notifications ;;
      settings) sh cmd statusbar expand-settings ;;
      close)    sh cmd statusbar collapse ;;
      *) die "usage: notifications open|close|settings" ;;
    esac ;;

  # --- App context -----------------------------------------------------------------
  permission)
    action="${1:-}"; shift || true
    case "$action" in
      grant|revoke)
        [ $# -ge 1 ] || die "usage: permission $action PERMISSION [PACKAGE]"
        p="$(perm_name "$1")"; pkg="${2:-$APP_PACKAGE}"
        # pm prints a Java stack trace on failure; show only the reason.
        if ! out="$(sh pm "$action" "$pkg" "$p" 2>&1)" || [[ "$out" == *Exception* ]]; then
          reason="$(printf '%s\n' "$out" | tr -d '\r' | grep -m1 -E 'Exception:|Error:' | sed 's/^.*Exception: //')"
          die "Could not $action $p for $pkg: ${reason:-unknown error} (runtime permissions the app declares only)"
        fi
        # (no ${var^} capitalisation: macOS ships bash 3.2)
        if [ "$action" = grant ]; then ok "Granted $p to $pkg"; else ok "Revoked $p from $pkg"; fi ;;
      list)
        pkg="${1:-$APP_PACKAGE}"
        get dumpsys package "$pkg" | awk '/runtime permissions:/ {r=1; next} r && /granted=true/ { sub(/^ */, ""); sub(/:.*/, ""); print } r && /^ *[A-Za-z].*:$/ && !/permission/ {r=0}' | sort -u ;;
      *) die "usage: permission grant|revoke PERM [PKG] | permission list [PKG]" ;;
    esac ;;
  locale)
    case "${1:-status}" in
      status) get cmd locale get-app-locales "${2:-$APP_PACKAGE}" ;;
      reset)  sh cmd locale set-app-locales "${2:-$APP_PACKAGE}" --locales "" ; ok "App locale reset (reopen the app)" ;;
      *)      sh cmd locale set-app-locales "${2:-$APP_PACKAGE}" --locales "$1"; ok "App locale: $1 (reopen the app to apply)" ;;
    esac ;;

  # --- Capture & info ---------------------------------------------------------------
  record)
    secs="${1:-10}"; name="${2:-recording}"
    [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -ge 1 ] && [ "$secs" -le 180 ] || die "usage: record [SECONDS 1-180] [name]"
    name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')"
    file="$(screenshot_dir)/${name}-$(date +%Y%m%d-%H%M%S).mp4"
    info "Recording ${secs}s…"
    sh screenrecord --time-limit "$secs" /sdcard/expoemu-record.mp4
    adb_host pull /sdcard/expoemu-record.mp4 "$file" >/dev/null 2>&1 || die "Could not copy the recording"
    sh rm -f /sdcard/expoemu-record.mp4
    printf '%s\n' "$file" ;;
  info)
    cat <<EOF
model:        $(get getprop ro.product.model)
android:      $(get getprop ro.build.version.release) (API $(get getprop ro.build.version.sdk))
abi:          $(get getprop ro.product.cpu.abi)
screen:       $(get wm size | awk -F': ' '{v=$2} END{print v}') @ $(get wm density | awk -F': ' '{v=$2} END{print v}') dpi
rotation:     $(get settings get system user_rotation)
dark mode:    $(get cmd uimode night)
font scale:   $(get settings get system font_scale)
battery:      $(get dumpsys battery | awk '/^ *level:/ {print $2 "%"}')
wifi:         $(get cmd wifi status | head -1)
airplane:     $(get cmd connectivity airplane-mode)
app package:  $APP_PACKAGE ($(get cmd locale get-app-locales "$APP_PACKAGE" | sed 's/.* are //'))
EOF
    ;;
  *) die "Unknown command: $cmd (try: $(cmd system.sh)$([ -n "${EXPOEMU_CLI:-}" ] || echo ' help'))" ;;
esac
