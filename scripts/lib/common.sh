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
#  - npm / npx   -> ~/.expo-android-env/config.env, because the package lives
#                   in a cache folder that changes with every version.
#  - EAENV_CONFIG overrides both.
if [ -n "${EAENV_CONFIG:-}" ]; then
  ENV_FILE="$EAENV_CONFIG"
elif [ -d "$REPO_ROOT/.git" ] || [ -f "$REPO_ROOT/.env" ]; then
  ENV_FILE="$REPO_ROOT/.env"
else
  ENV_FILE="$HOME/.expo-android-env/config.env"
fi
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
# PROJECT_DIR so `npx eaenv …` always targets the project you run it from.
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
  have="$(docker image inspect -f '{{index .Config.Labels "com.expo-android-env.build-hash"}}' "$IMAGE_NAME" 2>/dev/null || true)"
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
