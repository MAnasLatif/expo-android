#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Fast UI dumps through the expoemu UI server (see server/).
#
# `uiautomator dump` starts a new process and waits for the UI to be idle
# for a full second, so every call takes ~2-3 s. The UI server is a small
# helper app that stays running on the device and returns the identical XML
# in ~0.1-0.4 s.
#
# Reliability rules:
#   - Every failure falls back to `uiautomator dump` (the old, slow path).
#   - Android allows ONE UiAutomation connection: the server is stopped
#     before uiautomator runs, or uiautomator gets killed.
#   - Emulators use it by default. Physical phones only with
#     EXPOEMU_UI_SERVER=1 (installing an app on someone's phone is opt-in).
#   - EXPOEMU_UI_SERVER=0 turns it off everywhere.
#   - The server quits by itself after 15 minutes without requests.
#
# Needs common.sh (adb_host, is_emulator, RUN_DIR, REPO_ROOT, ANDROID_SERIAL).
# =============================================================================

UI_SERVER_PKG="dev.expoemu.server"
UI_SERVER_DEVICE_PORT=47219
UI_SERVER_APK="$REPO_ROOT/server/dist/expoemu-server.apk"
UI_SERVER_VERSION_FILE="$REPO_ROOT/server/dist/version.txt"
# How long the UI must be quiet before a dump (uiautomator waits 1000 ms).
: "${EXPOEMU_UI_IDLE_MS:=300}"

UI_PORT=""
UI_TOKEN=""

# Why the server isn't used (empty when it can be). Printed by `ui-server status`.
ui_server_unavailable() {
  case "${EXPOEMU_UI_SERVER:-auto}" in
    0|off|false|no) echo "turned off (EXPOEMU_UI_SERVER=${EXPOEMU_UI_SERVER})"; return ;;
    1|on|true|yes) ;;
    *) is_emulator || { echo "physical phone: opt in with EXPOEMU_UI_SERVER=1"; return; } ;;
  esac
  [ -f "$UI_SERVER_APK" ] && [ -f "$UI_SERVER_VERSION_FILE" ] \
    || { echo "APK not built (git clone: run server/build.sh)"; return; }
  command -v curl >/dev/null 2>&1 || echo "curl not found"
}

# Per-device state: "<host port> <token>". Serial made file-name safe.
ui_server_state_file() {
  printf '%s/ui-server-%s\n' "$RUN_DIR" "$(printf '%s' "$ANDROID_SERIAL" | tr -c 'A-Za-z0-9.\n-' '_')"
}

# ui_server_get PATH [MAX_SECONDS] — HTTP GET against the running server.
ui_server_get() {
  [ -n "$UI_PORT" ] || return 1
  curl -fsS --max-time "${2:-5}" -H "X-Token: $UI_TOKEN" \
    "http://127.0.0.1:$UI_PORT$1" 2>/dev/null
}

ui_server_expected_version() { tr -d ' \n' < "$UI_SERVER_VERSION_FILE"; }

# True when the server for this device answers with the current version.
ui_server_alive() {
  local state; state="$(ui_server_state_file)"
  [ -f "$state" ] || return 1
  read -r UI_PORT UI_TOKEN < "$state" || return 1
  [ "$(ui_server_get /ping 2)" = "expoemu-ui-server $(ui_server_expected_version)" ]
}

# Stop the server (frees UiAutomation for uiautomator) and forget its port.
ui_server_stop() {
  local state; state="$(ui_server_state_file)"
  if [ -f "$state" ]; then
    read -r UI_PORT UI_TOKEN < "$state" || true
    [ -n "$UI_PORT" ] && adb_host forward --remove "tcp:$UI_PORT" >/dev/null 2>&1 || true
    rm -f "$state"
  fi
  adb_host shell am force-stop "$UI_SERVER_PKG" >/dev/null 2>&1 || true
  UI_PORT=""; UI_TOKEN=""
}

# Install (or upgrade) the APK when the device has another version.
ui_server_install() {
  local want have
  want="$(ui_server_expected_version)"
  have="$(adb_host shell dumpsys package "$UI_SERVER_PKG" 2>/dev/null | tr -d '\r' \
    | awk -F= '/versionName=/ { print $2; exit }')"
  [ "$have" = "$want" ] && return 0
  adb_host install -r -t "$UI_SERVER_APK" >/dev/null 2>&1 && return 0
  # A differently signed copy can't be replaced in place.
  adb_host uninstall "$UI_SERVER_PKG" >/dev/null 2>&1 || true
  adb_host install -t "$UI_SERVER_APK" >/dev/null 2>&1
}

# Make sure the server runs on this device. Returns 1 if it can't, and then
# stays out of the way for 5 minutes instead of retrying on every command.
ui_server_ensure() {
  local state failed i
  state="$(ui_server_state_file)"; failed="$state.failed"
  ui_server_alive && return 0
  if [ -f "$failed" ] && [ -n "$(find "$failed" -mmin -5 2>/dev/null)" ]; then return 1; fi
  mkdir -p "$RUN_DIR"
  # Two commands at once on one device: only one starts the server, the
  # other waits for it (a lock older than a minute is stale).
  local lock="$state.lock" rc=0
  for ((i = 0; i < 60; i++)); do
    mkdir "$lock" 2>/dev/null && break
    [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null
    sleep 0.25
  done
  if ui_server_alive; then rmdir "$lock" 2>/dev/null || true; return 0; fi
  ui_server_start_locked "$state" "$failed" || rc=1
  rmdir "$lock" 2>/dev/null || true
  return "$rc"
}

ui_server_start_locked() {
  local state="$1" failed="$2" i
  ui_server_stop
  if ui_server_install; then
    UI_TOKEN="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    # -w keeps `am` alive: it hosts the UiAutomation connection. nohup + & let
    # it outlive this adb shell.
    adb_host shell "nohup am instrument -w -e token $UI_TOKEN $UI_SERVER_PKG/.Server >/dev/null 2>&1 &" >/dev/null 2>&1 || true
    UI_PORT="$(adb_host forward tcp:0 "tcp:$UI_SERVER_DEVICE_PORT" 2>/dev/null | tr -d '\r' | awk 'NR == 1')"
    if [ -n "$UI_PORT" ]; then
      printf '%s %s\n' "$UI_PORT" "$UI_TOKEN" > "$state"
      for ((i = 0; i < 40; i++)); do
        if ui_server_alive; then rm -f "$failed"; return 0; fi
        sleep 0.25
      done
    fi
  fi
  ui_server_stop
  : > "$failed"
  return 1
}

# Print the current view hierarchy as XML (the `uiautomator dump` format).
# Fast path: the UI server. Slow path: uiautomator. Returns 1 if both fail.
dump_xml() {
  local xml
  if [ -z "$(ui_server_unavailable)" ]; then
    if ui_server_ensure; then
      if xml="$(ui_server_get "/dump?idle=$EXPOEMU_UI_IDLE_MS" 20)" && [[ "$xml" == *"<hierarchy"* ]]; then
        printf '%s\n' "$xml"
        return 0
      fi
      ui_server_stop
    fi
  else
    # A server left running from earlier would make uiautomator get killed.
    [ -f "$(ui_server_state_file)" ] && ui_server_stop
  fi
  if ! adb_host shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1; then
    # Killed by a server we didn't know about (state lost)? Stop it, retry once.
    adb_host shell am force-stop "$UI_SERVER_PKG" >/dev/null 2>&1 || true
    adb_host shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || return 1
  fi
  adb_host exec-out cat /sdcard/window_dump.xml
}
