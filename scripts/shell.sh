#!/usr/bin/env bash
# =============================================================================
# Open a shell (or run one command) inside the container as the `expo` user.
#
#   scripts/shell.sh                     interactive bash in /workspace
#   scripts/shell.sh bun add zustand     run a single command
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config
require_docker
container_running || die "Container not running. Start it with: $(cmd start.sh) /path/to/expo-app"

# Allocate a TTY only when we have one (agents/CI run without a terminal).
flags=(-i)
[ -t 0 ] && [ -t 1 ] && flags+=(-t)

if [ $# -eq 0 ]; then
  exec docker exec "${flags[@]}" -u expo -w /workspace "$CONTAINER_NAME" bash -l
fi
exec docker exec "${flags[@]}" -u expo -w /workspace "$CONTAINER_NAME" "$@"
