#!/usr/bin/env bash
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
ENV_FILE="$REPO_ROOT/.env"
LABEL="com.expo-android-env.managed=true"
CONTAINER_NAME="expo-android-env"
IMAGE_NAME="expo-android-env:local"

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

# --- Config loading ----------------------------------------------------------
# Values already exported in the shell win over files (handy for CI/overrides).
load_config() {
  local preset_project="${PROJECT_DIR:-}"
  set -a
  # shellcheck disable=SC1090
  source "$VERSIONS_FILE"
  # shellcheck disable=SC1090
  [ -f "$ENV_FILE" ] && source "$ENV_FILE"
  set +a
  [ -n "$preset_project" ] && PROJECT_DIR="$preset_project"

  # Defaults (mirror .env.example) so scripts work before .env exists.
  : "${ENV_HOME:=$HOME/.expo-android-env}"
  : "${SCREENSHOT_DIR:=.android-screenshots}"
  : "${AVD_NAME:=expo_pixel_api36}"
  : "${AVD_DEVICE_NAME:=pixel_8}"
  : "${AVD_LCD_WIDTH:=1080}" "${AVD_LCD_HEIGHT:=2400}" "${AVD_LCD_DENSITY:=420}"
  : "${AVD_RAM_MB:=4096}" "${AVD_CORES:=4}" "${AVD_DATA_PARTITION:=8G}"
  : "${EMULATOR_GPU:=host}" "${EMULATOR_HEADLESS:=false}"
  : "${ADB_SERVER_PORT:=5037}" "${METRO_PORT:=8081}"

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
# Priority: explicit argument > PROJECT_DIR (env/.env) > current directory if it
# looks like an Expo app. Lets agents call these scripts from the project root.
is_expo_project() {
  [ -f "$1/package.json" ] && grep -q '"expo"' "$1/package.json"
}

resolve_project() {
  local candidate="${1:-${PROJECT_DIR:-}}"
  if [ -z "$candidate" ] && is_expo_project "$PWD"; then candidate="$PWD"; fi
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
  if [ -n "${PROJECT_DIR:-}" ]; then base="$PROJECT_DIR"
  elif is_expo_project "$PWD"; then base="$PWD"; fi
  local dir="$base/$SCREENSHOT_DIR"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# --- Docker ------------------------------------------------------------------
require_docker() {
  command -v docker >/dev/null || die "Docker is not installed. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
  docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop and retry."
}

# docker compose with both env files; shell env (PROJECT_DIR, ...) wins.
compose() {
  local args=(--project-directory "$REPO_ROOT" -f "$COMPOSE_FILE" --env-file "$VERSIONS_FILE")
  [ -f "$ENV_FILE" ] && args+=(--env-file "$ENV_FILE")
  docker compose "${args[@]}" "$@"
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]
}

# --- adb (host side) ---------------------------------------------------------
require_sdk() {
  [ -x "$ADB" ] || die "Isolated SDK not installed. Run: scripts/setup.sh"
}

adb_host() { "$ADB" -P "$ADB_SERVER_PORT" "$@"; }

# Serial of the first running emulator (empty if none).
emulator_serial() {
  adb_host devices 2>/dev/null | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1; exit}'
}

# Ensure an emulator is online and export ANDROID_SERIAL for later adb calls.
require_device() {
  require_sdk
  local serial
  serial="$(emulator_serial)"
  [ -n "$serial" ] || die "No running emulator. Start one with: scripts/emulator-start.sh"
  export ANDROID_SERIAL="$serial"
}
