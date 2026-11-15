#!/usr/bin/env bash
# =============================================================================
# Start the development container for an Expo project.
#
#   scripts/start.sh [/path/to/expo-app] [--no-install]
#
# Mounts the project at /workspace and installs Linux node_modules into the
# project's dedicated Docker volume on first run (bun install).
# Equivalent to `docker compose up -d` with PROJECT_DIR set.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_docker

ARG_PROJECT="" INSTALL=1
for a in "$@"; do
  case "$a" in
    --no-install) INSTALL=0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) ARG_PROJECT="$a" ;;
  esac
done
resolve_project "$ARG_PROJECT"

# --- 1. Image (built once, reused forever) ----------------------------------
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  info "Image not found — building it once"
  compose build
fi

# --- 2. Container (recreated automatically if the project changed) --------
info "Starting container for $PROJECT_DIR"
compose up -d --remove-orphans >/dev/null
ok "Container $CONTAINER_NAME running (project mounted at /workspace)"

# --- 3. Dependencies (only when the node_modules volume is empty) ------------
if [ "$INSTALL" = 1 ]; then
  if docker exec "$CONTAINER_NAME" test -d /workspace/node_modules/.bin; then
    ok "node_modules present (volume expo-android-env_node_modules_$PROJECT_SLUG)"
  else
    info "Installing dependencies with bun (first run for this project)"
    docker exec -u expo -w /workspace "$CONTAINER_NAME" bun install
    ok "Dependencies installed"
  fi
fi

cat >&2 <<EOF

Next:
  scripts/emulator-start.sh   # if the phone isn't running yet
  scripts/expo.sh             # start Metro (interactive)  — or: scripts/expo.sh --background
  scripts/open-app.sh         # install Expo Go if needed and open the app
EOF
