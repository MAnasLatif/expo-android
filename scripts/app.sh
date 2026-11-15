#!/usr/bin/env bash
# =============================================================================
# App control and diagnostics. PKG defaults to APP_PACKAGE (Expo Go).
#
# APP
#   app launch [PKG]               start the app's launcher activity
#   app stop [PKG]                 force-stop the app
#   app restart [PKG]              stop + start (Expo Go: reopens your project)
#   app clear [PKG]                wipe app data (AsyncStorage, SecureStore,
#                                  permissions) — a fresh-install state
#                                  (Expo Go: reopens your project afterwards)
#   app install FILE.apk           install/upgrade an APK (grants permissions)
#   app uninstall PKG              remove an app
#   app list                       installed third-party apps
#   app info [PKG]                 version, SDK levels, install time
#
# DIAGNOSTICS
#   crash [-n N] [--clear]         recent crashes from the crash log buffer
#   perf [PKG] [--reset]           frame stats: jank %, frame-time percentiles
#                                  (--reset, interact, then perf to measure a flow)
#   memory [PKG]                   memory use: PSS/RSS, Java and native heap
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config

cmd="${1:-help}"; shift || true
case "$cmd" in help|-h|--help) sed -n '2,/^# =====*$/p' "$0"; exit 0 ;; esac
require_device
sh() { adb_host shell "$@"; }
get() { sh "$@" 2>/dev/null | tr -d '\r'; }

installed() { [[ "$(get pm list packages "$1")" == *"package:$1"* ]]; }
need_installed() { installed "$1" || die "Package not installed: $1"; }

launch() {
  local component
  component="$(get cmd package resolve-activity --brief "$1" | tail -1)"
  [[ "$component" == */* ]] || die "No launcher activity for $1"
  sh am start -n "$component" >/dev/null
}

case "$cmd" in
  # --- App control -----------------------------------------------------------
  app)
    sub="${1:-}"; shift || true
    pkg="${1:-$APP_PACKAGE}"
    case "$sub" in
      launch)  need_installed "$pkg"; launch "$pkg"; ok "Launched $pkg" ;;
      stop)    sh am force-stop "$pkg"; ok "Stopped $pkg" ;;
      restart)
        if [ "$pkg" = host.exp.exponent ]; then
          # Expo Go: reopen the project (open-app force-stops and deep-links).
          exec bash "$(dirname "$0")/open-app.sh"
        fi
        need_installed "$pkg"; sh am force-stop "$pkg"; launch "$pkg"; ok "Restarted $pkg" ;;
      clear)
        need_installed "$pkg"
        [[ "$(get pm clear "$pkg")" == *Success* ]] || die "Could not clear data for $pkg"
        ok "Cleared all data for $pkg"
        if [ "$pkg" = host.exp.exponent ]; then
          # Expo Go: reopen the project and get past its first-run introduction.
          exec bash "$(dirname "$0")/open-app.sh" --first-run
        fi ;;
      install)
        [ -f "${1:-}" ] || die "usage: app install FILE.apk"
        adb_host install -r -g "$1" || die "Install failed"
        ok "Installed $1" ;;
      uninstall)
        [ -n "${1:-}" ] || die "usage: app uninstall PKG"
        need_installed "$1"
        adb_host uninstall "$1" >/dev/null || die "Uninstall failed"
        ok "Uninstalled $1" ;;
      list)    get pm list packages -3 | sed 's/^package://' | sort ;;
      info)
        need_installed "$pkg"
        get dumpsys package "$pkg" | awk -v p="$pkg" '
          /versionName=/ && !vn { sub(/.*versionName=/, ""); vn = $0 }
          /versionCode=/ && !vc { vc = $1; sub(/versionCode=/, "", vc); for (i = 2; i <= NF; i++) if ($i ~ /^(minSdk|targetSdk)=/) sdk = sdk " " $i }
          /firstInstallTime=/ && !fi { sub(/.*firstInstallTime=/, ""); fi = $0 }
          END { printf "package:      %s\nversion:      %s (%s)\nsdk:         %s\ninstalled:    %s\n", p, vn, vc, sdk, fi }' ;;
      *) die "usage: app launch|stop|restart|clear|install|uninstall|list|info [PKG]" ;;
    esac ;;

  # --- Diagnostics -------------------------------------------------------------
  crash)
    n=60
    while [ $# -gt 0 ]; do
      case "$1" in
        -n) n="$2"; shift ;;
        --clear) adb_host logcat -b crash -c; ok "Crash buffer cleared"; exit 0 ;;
        *) die "usage: crash [-n N] [--clear]" ;;
      esac; shift
    done
    out="$(adb_host logcat -b crash -d -v time 2>/dev/null | tail -n "$n")"
    if [ -n "$out" ]; then printf '%s\n' "$out"; else ok "No crashes recorded"; fi ;;
  perf)
    pkg="$APP_PACKAGE" reset=0
    for a in "$@"; do case "$a" in --reset) reset=1 ;; *) pkg="$a" ;; esac; done
    if [ "$reset" = 1 ]; then
      sh dumpsys gfxinfo "$pkg" reset >/dev/null
      ok "Frame stats reset for $pkg — interact with the app, then run perf again"; exit 0
    fi
    get dumpsys gfxinfo "$pkg" \
      | awk '/^Total frames rendered|^Janky frames:|^(50th|90th|95th|99th) percentile|^Number (Slow UI thread|Frozen frames)/' \
      | sed -n '1,9p' ;;
  memory)
    pkg="${1:-$APP_PACKAGE}"
    get dumpsys meminfo "$pkg" | awk '
      /TOTAL PSS:/  { printf "total PSS:    %.1f MB\ntotal RSS:    %.1f MB\n", $3/1024, $6/1024 }
      /Java Heap:/  { printf "java heap:    %.1f MB\n", $3/1024 }
      /Native Heap:/ && NF <= 4 { printf "native heap:  %.1f MB\n", $3/1024 }' ;;
  *) die "Unknown command: $cmd (try: $(cmd app.sh)$([ -n "${EXPOEMU_CLI:-}" ] || echo ' help'))" ;;
esac
