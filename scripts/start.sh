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

# --- 1. Image (built once; rebuilt only when its sources change) -------------
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  info "Image not found — building it once"
  compose build
elif image_outdated; then
  info "Image sources changed (new version?) — rebuilding (cached layers reused)"
  compose build
fi

# --- 2. Container (recreated automatically if the project changed) --------
# A container from expoemu 0.1.0 (old name) would hold port 8081: remove it.
# Only the container — its image/volumes stay until `cleanup --legacy`.
legacy="$(docker ps -aq --filter "label=com.$LEGACY_NAME.managed=true" --filter "name=^${LEGACY_NAME}$")"
if [ -n "$legacy" ]; then
  docker rm -f "$legacy" >/dev/null && info "Removed the old 0.1.0 container (run '$(cmd cleanup.sh) --legacy' to free its disk space)"
fi

info "Starting container for $PROJECT_DIR"
fit_resource_limits
compose up -d --remove-orphans >/dev/null
ok "Container $CONTAINER_NAME running (project mounted at /workspace)"

# --- 3. Dependencies (only when the node_modules volume is empty) ------------
if [ "$INSTALL" = 1 ]; then
  if docker exec "$CONTAINER_NAME" test -d /workspace/node_modules/.bin; then
    ok "node_modules present (volume expoemu_node_modules_$PROJECT_SLUG)"
  else
    # Use the project's own package manager in a mode that never rewrites
    # its files: a plain `bun install` would add a bun.lock to npm/yarn/pnpm
    # projects. node_modules itself lives in a Docker volume, not the project.
    p="$PROJECT_DIR"
    if   [ -f "$p/bun.lock" ] || [ -f "$p/bun.lockb" ]; then pm=bun;  install="bun install --frozen-lockfile || bun install"
    elif [ -f "$p/package-lock.json" ];  then pm=npm;  install="npm ci --no-audit --no-fund"
    elif [ -f "$p/pnpm-lock.yaml" ];     then pm=pnpm; install="corepack pnpm install --frozen-lockfile"
    elif [ -f "$p/yarn.lock" ];          then pm=yarn; install="corepack yarn install --frozen-lockfile || corepack yarn install --immutable"
    else                                      pm=bun;  install="bun install --no-save"   # no lockfile: don't create one
    fi
    info "Installing dependencies with $pm (first run for this project; project files are not modified)"
    docker exec -u expo -w /workspace -e COREPACK_ENABLE_DOWNLOAD_PROMPT=0 "$CONTAINER_NAME" bash -lc "$install" \
      || die "Dependency install failed ($pm). Fix it in the project, then re-run: $(cmd start.sh)"
    ok "Dependencies installed"
  fi
fi

# Next-step hints, unless start.sh runs as one step of `expoemu up`.
if [ -z "${EXPOEMU_QUIET_HINTS:-}" ]; then
  cat >&2 <<EOF

Next:
  $(cmd emulator-start.sh)   # if the phone isn't running yet
  $(cmd expo.sh) --background   # start Metro (or without --background for the interactive UI)
  $(cmd open-app.sh)   # install Expo Go if needed and open the app
EOF
fi
