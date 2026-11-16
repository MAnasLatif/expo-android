#!/usr/bin/env bash
# Variables defined here are consumed by the scripts that source this file.
# shellcheck disable=SC2034
# =============================================================================
# Shared helpers for every script in scripts/. Source it, don't execute it:
#   source "$(dirname "$0")/lib/common.sh"
#
# Responsibilities:
#   - load config/versions.env + .env
#   - derive isolated SDK paths under $ENV_HOME (never touches ~/Library/Android)
#   - resolve which Expo project is being worked on
#   - thin wrappers for adb (host) and docker compose
# =============================================================================
set -euo pipefail

# --- Paths -------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
VERSIONS_FILE="$REPO_ROOT/config/versions.env"
# Local settings file:
#  - git clone   -> <repo>/.env (as before)
#  - npm / npx   -> ~/.expoemu/config.env, because the package lives
#                   in a cache folder that changes with every version.
#  - EXPOEMU_CONFIG overrides both.
if [ -n "${EXPOEMU_CONFIG:-}" ]; then
  ENV_FILE="$EXPOEMU_CONFIG"
elif [ -d "$REPO_ROOT/.git" ] || [ -f "$REPO_ROOT/.env" ]; then
  ENV_FILE="$REPO_ROOT/.env"
else
  ENV_FILE="$HOME/.expoemu/config.env"
fi
LABEL="com.expoemu.managed=true"
CONTAINER_NAME="expoemu"
IMAGE_NAME="expoemu:local"

# --- One-time migration from the 0.1.0 layout --------------------------------
# expoemu 0.1.0 used a different folder (~/.<LEGACY_NAME>) and Docker names.
# Move (never re-download) the SDK/AVD folder to ~/.expoemu, fix the absolute
# AVD path inside it, and point settings files at the new folder. Skipped while
# an emulator from the old folder is still running.
# (Name built from parts on purpose — keep it as is.)
LEGACY_NAME="expo-android""-env"
migrate_legacy_home() {
  local old="$HOME/.$LEGACY_NAME" new="$HOME/.expoemu" f
  [ -f "$old/.$LEGACY_NAME-root" ] && [ ! -e "$new" ] || return 0
  if pgrep -f "$old/sdk/emulator" >/dev/null 2>&1; then
    printf 'expoemu: stop the running emulator once (old location) so ~/.%s can move to ~/.expoemu\n' "$LEGACY_NAME" >&2
    return 0
  fi
  mv "$old" "$new" && mv "$new/.$LEGACY_NAME-root" "$new/.expoemu-root"
  for f in "$new"/avd/*.ini; do [ -f "$f" ] && sed -i '' "s#$old/#$new/#g" "$f"; done
  for f in "$new/config.env" "$REPO_ROOT/.env"; do
    [ -f "$f" ] && sed -i '' "s#\${HOME}/\.$LEGACY_NAME\$#\${HOME}/.expoemu#; s#$old\$#$new#" "$f"
  done
  printf 'expoemu: moved ~/.%s to ~/.expoemu (one-time rename)\n' "$LEGACY_NAME" >&2
}
migrate_legacy_home

# --- Logging -----------------------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi
info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
ok()   { printf '%s ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
warn() { printf '%s !%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s ✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# --- Command hints -------------------------------------------------------------
# Show commands the way the user runs them: `npx expoemu open` when called through
# the expoemu CLI (bin/expoemu.js sets EXPOEMU_CLI=1), `scripts/open-app.sh` otherwise.
cmd() {
  local script="$1" sub
  case "$script" in
    setup.sh) sub=setup ;;          start.sh) sub=start ;;
    stop.sh) sub=stop ;;            shell.sh) sub=shell ;;
    expo.sh) sub=expo ;;            open-app.sh) sub=open ;;
    status.sh) sub=status ;;        screenshot.sh) sub=screenshot ;;
    cleanup.sh) sub=cleanup ;;      device.sh|system.sh|app.sh) sub=help ;;
    devices.sh) sub=devices ;;
    emulator-start.sh) sub="emulator start" ;;
    emulator-stop.sh) sub="emulator stop" ;;
    *) sub="${script%.sh}" ;;
  esac
  if [ -n "${EXPOEMU_CLI:-}" ]; then printf 'npx expoemu %s' "$sub"; else printf 'scripts/%s' "$script"; fi
}

# --- Config loading ----------------------------------------------------------
# Values already exported in the shell win over files (handy for CI/overrides).
load_config() {
  # Remember any .env keys already set in the environment (e.g. CI or a
  # one-off `ENV_HOME=... scripts/status.sh`) so .env cannot clobber them.
  local keys k overrides=()
  keys="$(sed -nE 's/^([A-Z_][A-Z0-9_]*)=.*/\1/p' "$REPO_ROOT/.env.example")"
  for k in $keys; do
    if [ -n "${!k:-}" ]; then overrides+=("$k=${!k}"); fi
  done

  set -a
  # shellcheck disable=SC1090
  source "$VERSIONS_FILE"
  # shellcheck disable=SC1090
  if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi
  set +a

  local kv
  for kv in ${overrides[@]+"${overrides[@]}"}; do
    printf -v "${kv%%=*}" '%s' "${kv#*=}"
    export "${kv%%=*}"
  done

  # Defaults (mirror .env.example) so scripts work before .env exists.
  : "${ENV_HOME:=$HOME/.expoemu}"
  : "${SCREENSHOT_DIR:=.android-screenshots}"
  : "${AVD_NAME:=expo_pixel_api36}"
  : "${AVD_DEVICE_NAME:=pixel_8}"
  : "${AVD_LCD_WIDTH:=1080}" "${AVD_LCD_HEIGHT:=2400}" "${AVD_LCD_DENSITY:=420}"
  : "${AVD_RAM_MB:=4096}" "${AVD_CORES:=4}" "${AVD_DATA_PARTITION:=8G}"
  : "${EMULATOR_GPU:=host}" "${EMULATOR_HEADLESS:=false}"
  : "${ADB_SERVER_PORT:=5037}" "${METRO_PORT:=8081}"
  # Android package targeted by app/permission/locale commands (Expo Go).
  : "${APP_PACKAGE:=host.exp.exponent}"

  # Isolated Android layout — everything lives under $ENV_HOME.
  SDK_DIR="$ENV_HOME/sdk"
  AVD_HOME="$ENV_HOME/avd"
  LOG_DIR="$ENV_HOME/logs"
  RUN_DIR="$ENV_HOME/run"
  ADB="$SDK_DIR/platform-tools/adb"
  EMULATOR_BIN="$SDK_DIR/emulator/emulator"

  # Env vars understood by adb/emulator: keep them inside $ENV_HOME so the
  # user's ~/.android (and any other SDK) is never read or modified.
  export ANDROID_HOME="$SDK_DIR" ANDROID_SDK_ROOT="$SDK_DIR"
  export ANDROID_AVD_HOME="$AVD_HOME"
  export ANDROID_USER_HOME="$ENV_HOME/user-home"
  export ANDROID_EMULATOR_HOME="$ENV_HOME/user-home"
  export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"

  detect_arch
  # System image path inside the SDK (shared by every device/AVD).
  SYS_IMG_REL="system-images/android-${SYSTEM_IMAGE_API}/${SYSTEM_IMAGE_TAG}/${SYS_IMG_ABI}"
  select_runtime
}

# --- Container runtime: Docker Desktop (default) or Kiri (opt-in) ------------
# Kiri (https://runkiri.com) is a lightweight Docker-compatible runtime that
# speaks the Docker Engine API. We point the docker CLI at Kiri's socket via
# DOCKER_HOST for THIS process only — the user's global docker context,
# ~/.docker/config.json and shell profiles are never changed.
select_runtime() {
  : "${CONTAINER_RUNTIME:=docker}"
  case "$CONTAINER_RUNTIME" in
    docker)
      RUNTIME_NAME="Docker Desktop" ;;
    kiri)
      RUNTIME_NAME="Kiri"
      : "${KIRI_SOCKET:=$HOME/.kiri/run/docker.sock}"
      export DOCKER_HOST="unix://$KIRI_SOCKET"
      unset DOCKER_CONTEXT   # DOCKER_HOST wins anyway; avoid confusing warnings
      # Kiri links its bundled docker CLI into ~/.kiri/bin. Use it only when no
      # docker CLI is on PATH (e.g. Docker Desktop not installed).
      if ! command -v docker >/dev/null && [ -x "$HOME/.kiri/bin/docker" ]; then
        PATH="$PATH:$HOME/.kiri/bin"
      fi ;;
    *)
      die "CONTAINER_RUNTIME must be 'docker' or 'kiri' (got '$CONTAINER_RUNTIME')" ;;
  esac
}

# --- Host architecture -> emulator/system-image flavour -----------------------
detect_arch() {
  case "$(uname -m)" in
    x86_64) HOST_ARCH=x86_64; SYS_IMG_ABI=x86_64;    EMULATOR_FLAVOUR=darwin_x64 ;;
    arm64)  HOST_ARCH=arm64;  SYS_IMG_ABI=arm64-v8a; EMULATOR_FLAVOUR=darwin_aarch64 ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || die "The emulator side of this project currently supports macOS only."
}

# --- Project resolution ------------------------------------------------------
# Priority: explicit argument > current directory if it looks like an Expo app
# > PROJECT_DIR (env/.env). The current directory wins over the saved
# PROJECT_DIR so `npx expoemu …` always targets the project you run it from.
is_expo_project() {
  [ -f "$1/package.json" ] && grep -q '"expo"' "$1/package.json"
}

resolve_project() {
  local candidate="${1:-}"
  if [ -z "$candidate" ] && is_expo_project "$PWD"; then candidate="$PWD"; fi
  [ -n "$candidate" ] || candidate="${PROJECT_DIR:-}"
  [ -n "$candidate" ] || die "No Expo project given. Pass a path, set PROJECT_DIR in $ENV_FILE, or run from your project folder."
  [ -d "$candidate" ] || die "Project directory not found: $candidate"
  PROJECT_DIR="$(cd "$candidate" && pwd -P)"
  is_expo_project "$PROJECT_DIR" || warn "$PROJECT_DIR has no 'expo' dependency in package.json"
  # Per-project volume suffix: <name>-<hash> keeps node_modules separate per app.
  local base hash
  base="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')"
  hash="$(printf '%s' "$PROJECT_DIR" | shasum | cut -c1-8)"
  PROJECT_SLUG="${base}-${hash}"
  export PROJECT_DIR PROJECT_SLUG
}

# Screenshot folder: inside the project when known (so agents can read it),
# otherwise inside this repo.
screenshot_dir() {
  local base="$REPO_ROOT"
  if is_expo_project "$PWD"; then base="$PWD"
  elif [ -n "${PROJECT_DIR:-}" ]; then base="$PROJECT_DIR"; fi
  local dir="$base/$SCREENSHOT_DIR"
  mkdir -p "$dir"
  # Self-ignoring folder: screenshots/recordings never get committed, and the
  # user's own .gitignore is left untouched.
  [ -f "$dir/.gitignore" ] || printf '# Created by expoemu — ignore everything in this folder\n*\n' > "$dir/.gitignore"
  printf '%s\n' "$dir"
}

# --- Docker ------------------------------------------------------------------
require_docker() {
  if [ "$CONTAINER_RUNTIME" = kiri ]; then
    command -v docker >/dev/null \
      || die "No docker CLI found. Install Kiri (https://runkiri.com) — it ships one in ~/.kiri/bin — or set CONTAINER_RUNTIME=docker."
    if ! docker info >/dev/null 2>&1; then
      [ -S "$KIRI_SOCKET" ] \
        || die "Kiri is not running (no socket at $KIRI_SOCKET). Open Kiri.app, or install it from https://runkiri.com"
      die "Kiri's engine at $KIRI_SOCKET is not responding. Try: kiri diag logs"
    fi
    # On Apple Silicon Kiri runs linux/amd64 images through Apple Rosetta only;
    # without Rosetta, amd64 programs (like Google's Linux adb) cannot start.
    if [ "$HOST_ARCH" = arm64 ] && [ "${DOCKER_PLATFORM:-linux/amd64}" = linux/amd64 ] \
       && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
      die "Kiri needs Apple Rosetta for linux/amd64 images. Install it with: softwareupdate --install-rosetta"
    fi
    return
  fi
  command -v docker >/dev/null || die "Docker is not installed. Install Docker Desktop: https://www.docker.com/products/docker-desktop/ (or use Kiri: CONTAINER_RUNTIME=kiri)"
  docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop and retry."
}

# Content hash of everything that shapes the image. Stored as an image label
# so a new package version (changed Dockerfile / versions) triggers a rebuild.
image_build_hash() {
  {
    cat "$REPO_ROOT/Dockerfile" "$REPO_ROOT/docker/entrypoint.sh" "$VERSIONS_FILE"
    printf '%s|%s\n' "${ANDROID_EXTRA_PACKAGES:-}" "${DOCKER_PLATFORM:-linux/amd64}"
  } | shasum | cut -c1-12
}

# True when the image is missing or was built from different sources.
image_outdated() {
  local have
  have="$(docker image inspect -f '{{index .Config.Labels "com.expoemu.build-hash"}}' "$IMAGE_NAME" 2>/dev/null || true)"
  [ "$have" != "$(image_build_hash)" ]
}

# docker compose with both env files; shell env (PROJECT_DIR, ...) wins.
compose() {
  BUILD_HASH="$(image_build_hash)"; export BUILD_HASH
  local args=(--project-directory "$REPO_ROOT" -f "$COMPOSE_FILE" --env-file "$VERSIONS_FILE")
  [ -f "$ENV_FILE" ] && args+=(--env-file "$ENV_FILE")
  docker compose "${args[@]}" "$@"
}

# The engine rejects `--cpus` above its own CPU count ("range of CPUs is from
# 0.01 to N"). Engines with small VMs (Kiri defaults to 2 CPUs, Docker Desktop
# can be set low) would fail to start the container, so cap the limit.
fit_resource_limits() {
  local ncpu want
  ncpu="$(docker info -f '{{.NCPU}}' 2>/dev/null || true)"
  want="${CONTAINER_CPUS:-4}"
  if [ -n "$ncpu" ] && awk -v w="$want" -v n="$ncpu" 'BEGIN { exit !(w > n) }'; then
    warn "CONTAINER_CPUS=$want exceeds the engine's $ncpu CPUs — using $ncpu"
    export CONTAINER_CPUS="$ncpu"
  fi
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]
}

# --- adb (host side) ---------------------------------------------------------
require_sdk() {
  [ -x "$ADB" ] || die "Isolated SDK not installed. Run: $(cmd setup.sh)"
}

adb_host() { "$ADB" -P "$ADB_SERVER_PORT" "$@"; }

# Serial of the first running emulator (empty if none).
emulator_serial() {
  adb_host devices 2>/dev/null | awk '/^emulator-[0-9]+[[:space:]]+device$/ && !f {print $1; f=1}'
}

# --- Several emulators at once --------------------------------------------------
# Every emulator is a named AVD ("device"). The default one is $AVD_NAME and can
# also be called "default". Commands target a device with --device NAME (the
# CLI exports EXPOEMU_DEVICE) or the default device when several are running.

# "default" -> $AVD_NAME; anything else unchanged.
device_name() { if [ "${1:-}" = default ] || [ -z "${1:-}" ]; then echo "$AVD_NAME"; else echo "$1"; fi; }

# One line per running emulator: "<serial> <avd name>".
running_emulators() {
  local s name
  for s in $(adb_host devices 2>/dev/null | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1}'); do
    name="$(adb_host -s "$s" emu avd name 2>/dev/null | tr -d '\r' | awk 'NR == 1')"
    printf '%s %s\n' "$s" "${name:-unknown}"
  done
}

# Serial of the running emulator for device NAME (empty if not running).
serial_for_device() {
  local want
  want="$(device_name "$1")"
  running_emulators | awk -v n="$want" '$2 == n && !f { print $1; f = 1 }'
}

# Pick the target emulator and export ANDROID_SERIAL for later adb calls.
#   EXPOEMU_DEVICE=<name|serial>  -> that device
#   otherwise                      -> the default device if running, else the first one
require_device() {
  require_sdk
  local want="${EXPOEMU_DEVICE:-}" serial=""
  if [ -n "$want" ]; then
    if [[ "$want" == emulator-* ]]; then
      running_emulators | awk '{print $1}' | grep -qx "$want" && serial="$want"
    else
      serial="$(serial_for_device "$want")"
    fi
    [ -n "$serial" ] || die "Device '$want' is not running. Start it with: $(cmd emulator-start.sh) --device $want"
  else
    serial="$(serial_for_device "$AVD_NAME")"
    [ -n "$serial" ] || serial="$(emulator_serial)"
    [ -n "$serial" ] || die "No running emulator. Start one with: $(cmd emulator-start.sh)"
  fi
  export ANDROID_SERIAL="$serial"
}

# --- Device profiles and AVD creation --------------------------------------------
PROFILES="phone small large tablet foldable"
# profile -> "<hw.device.name> <width> <height> <density> <ram MB>"
profile_spec() {
  case "$1" in
    phone)    echo "pixel_8 1080 2400 420 4096" ;;         # default: Pixel 8
    small)    echo "small_phone 720 1600 320 2048" ;;      # budget / small screen
    large)    echo "pixel_9_pro_xl 1344 2992 480 4096" ;;  # large flagship
    tablet)   echo "pixel_tablet 2560 1600 320 4096" ;;    # 10.95" tablet, landscape
    foldable) echo "pixel_fold 2208 1840 420 4096" ;;      # unfolded inner screen
    *) return 1 ;;
  esac
}

# write_avd NAME HW_DEVICE WIDTH HEIGHT DENSITY RAM_MB PROFILE
# Writes the AVD config directly (avdmanager would need Java on macOS).
# All devices share the one system image; each only adds its own data disk.
write_avd() {
  local name="$1" hwdev="$2" w="$3" h="$4" dpi="$5" ram="$6" profile="$7"
  local dir="$AVD_HOME/$name.avd" cpu_arch
  cpu_arch="$([ "$HOST_ARCH" = x86_64 ] && echo x86_64 || echo arm64)"
  mkdir -p "$dir"
  cat > "$AVD_HOME/$name.ini" <<EOF
avd.ini.encoding=UTF-8
path=$dir
target=android-${SYSTEM_IMAGE_API}
EOF
  # Camera/microphone disabled: avoids macOS privacy prompts and saves CPU.
  cat > "$dir/config.ini" <<EOF
avd.ini.encoding=UTF-8
AvdId=$name
avd.ini.displayname=Expo Emulator $name ($profile, API ${SYSTEM_IMAGE_API})
expoemu.profile=$profile
abi.type=$SYS_IMG_ABI
hw.cpu.arch=$cpu_arch
hw.cpu.ncore=$AVD_CORES
hw.ramSize=$ram
vm.heapSize=256
image.sysdir.1=$SYS_IMG_REL/
tag.id=$SYSTEM_IMAGE_TAG
tag.display=Google APIs
target=android-${SYSTEM_IMAGE_API}
PlayStore.enabled=false
hw.device.name=$hwdev
hw.device.manufacturer=Google
hw.lcd.width=$w
hw.lcd.height=$h
hw.lcd.density=$dpi
hw.keyboard=yes
hw.mainKeys=no
hw.gpu.enabled=yes
hw.gpu.mode=$EMULATOR_GPU
hw.accelerometer=yes
hw.audioInput=no
hw.camera.back=none
hw.camera.front=none
disk.dataPartition.size=$AVD_DATA_PARTITION
showDeviceFrame=no
fastboot.forceColdBoot=no
runtime.network.latency=none
runtime.network.speed=full
EOF
}

# Names of all created devices (AVDs), default first.
list_devices() {
  local f n
  [ -f "$AVD_HOME/$AVD_NAME.ini" ] && echo "$AVD_NAME"
  for f in "$AVD_HOME"/*.ini; do
    [ -f "$f" ] || continue
    n="$(basename "$f" .ini)"; [ "$n" = "$AVD_NAME" ] || echo "$n"
  done
}
