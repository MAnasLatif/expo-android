# Security Policy

## Supported versions

Only the latest release on the `main` branch receives fixes.

## Reporting a vulnerability

**Please do not open a public issue for security problems.** Use GitHub's
[private vulnerability reporting](../../security/advisories/new) instead.
Include steps to reproduce and the impact. You can expect a first response
within 7 days.

## Security design notes

- Metro is published on `127.0.0.1` only. It is not reachable from your
  network.
- The adb server listens on `127.0.0.1` on macOS. The container reaches it
  through Docker Desktop's `host.docker.internal` forwarding. adb is never
  exposed on `0.0.0.0`.
- All downloaded archives (Android SDK, Node.js, Bun) are verified against
  pinned checksums.
- The container runs as a non-root user.
- `.env` is git-ignored. Never commit tokens or personal paths.
