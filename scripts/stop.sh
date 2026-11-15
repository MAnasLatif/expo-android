#!/usr/bin/env bash
# =============================================================================
# Stop the development container. Image, node_modules and caches are kept, so
# the next `scripts/start.sh` is instant.
#
#   scripts/stop.sh [--all]     --all also stops the emulator and adb server
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_docker

# compose needs PROJECT_DIR for interpolation even when tearing down.
export PROJECT_DIR="${PROJECT_DIR:-$REPO_ROOT}"
info "Stopping container"
compose down --remove-orphans >/dev/null 2>&1 || true
ok "Container stopped (image, volumes and caches kept)"

if [ "${1:-}" = "--all" ]; then
  "$(dirname "$0")/emulator-stop.sh"
fi
