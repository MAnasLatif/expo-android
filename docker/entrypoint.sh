#!/usr/bin/env bash
# =============================================================================
# Container entrypoint.
#  1. Named volumes (node_modules, caches) are created root-owned by Docker;
#     hand them to the unprivileged `expo` user.
#  2. Report whether the macOS adb server is reachable (non-fatal: the
#     emulator may simply not be started yet).
#  3. Drop privileges and exec the command (default: sleep infinity).
# =============================================================================
set -euo pipefail

# --- 1. Fix ownership of mounted volumes (only when running as root) --------
if [ "$(id -u)" = "0" ]; then
  for d in /workspace/node_modules /home/expo/.bun /home/expo/.expo /home/expo/.gradle /home/expo/.cache; do
    if [ -d "$d" ] && [ "$(stat -c %u "$d")" != "1000" ]; then
      chown -R expo:expo "$d"
    fi
  done
fi

# --- 2. adb connectivity hint ------------------------------------------------
# ADB_SERVER_SOCKET (set in docker-compose.yml) points the adb client at the
# macOS server, e.g. tcp:host.docker.internal:5037.
if [ -n "${ADB_SERVER_SOCKET:-}" ]; then
  # bash /dev/tcp wants "host/port"; ADB_SERVER_SOCKET is "tcp:host:port".
  hostport="${ADB_SERVER_SOCKET#tcp:}"
  if timeout 3 bash -c "</dev/tcp/${hostport%:*}/${hostport##*:}" 2>/dev/null; then
    echo "[entrypoint] macOS adb server reachable at ${ADB_SERVER_SOCKET}"
  else
    echo "[entrypoint] adb server not reachable yet at ${ADB_SERVER_SOCKET} (start the emulator on macOS: scripts/emulator-start.sh)"
  fi
fi

# --- 3. Drop to the expo user ------------------------------------------------
if [ "$(id -u)" = "0" ]; then
  # Keep the environment (ADB_SERVER_SOCKET, ANDROID_HOME, ...); only fix HOME/USER.
  exec setpriv --reuid=expo --regid=expo --init-groups -- \
    env HOME=/home/expo USER=expo "$@"
fi
exec "$@"
