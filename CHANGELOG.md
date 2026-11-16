# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Several emulators at once. Named devices come from profiles (`phone`,
  `small`, `large`, `tablet`, `foldable`) via `device create`, and `devices`
  lists them. `emulator start|stop --device NAME` runs them side by side. A
  global `--device NAME` targets any command at one device. `open --all`
  and `screenshot --all` cover every running device, all served by one
  Metro.

### Changed

- Install once, test every project. The first-run dependency install uses the
  project's own package manager (npm `ci`, yarn/pnpm frozen lockfile, bun),
  and `bun install --no-save` when there is no lockfile, so nothing is
  written into the project. `.android-screenshots/` ignores itself in git.
- Upgrading from 0.1.0: the npm 0.1.0 package used older internal names for
  its folder and Docker resources. The folder moves to `~/.expoemu`
  automatically on first run (no re-download), the old container is
  replaced, and `npx expoemu cleanup --legacy` removes the old image and
  volumes.

### Added

- npm package **`expoemu`**: `npx expoemu setup | up | down | status | screenshot |
  ui | tap-text | logcat …` from the Expo project folder, for people and AI
  assistants. `up` starts the phone, container and Metro, and opens the app
  in one command.
- Settings for npm installs live in `~/.expoemu/config.env`
  (`EXPOEMU_CONFIG` overrides). Git clones keep using `.env`.
- The Docker image rebuilds automatically when its sources change (for
  example after upgrading expoemu).
- Release workflow: pushing a `vX.Y.Z` tag publishes to npm with provenance.
- Many more device actions, all available as `npx expoemu <cmd>`:
  - touch: `double-tap`, `long-press`, `long-press-text`, `drag`, `scroll
    left|right`, `scroll-to`
  - typing: `fill`, `clear`, `hide-keyboard`, `recents`, `enter`, `lock`,
    `unlock`
  - wait and assert: `wait-for`, `wait-gone`, `assert-text`,
    `assert-no-text`, `texts`, `ui --xml`
  - device state: `rotate`, `dark-mode`, `font-scale`, `animations`,
    `network`, `airplane`, `location`, `battery`, `notifications`,
    `permission`, `locale`, `record`, `info`
  - app and debugging: `app launch|stop|restart|clear|install|uninstall|list|info`,
    `crash`, `perf`, `memory`
- Selectors match `testID`, `accessibilityLabel` and placeholders, and
  prefer exact matches. `APP_PACKAGE` selects the target app (Expo Go by
  default).
- Optional [Kiri](https://runkiri.com) container runtime
  (`CONTAINER_RUNTIME=kiri` or `scripts/setup.sh --runtime kiri`). Docker
  Desktop stays the default. The global docker context is never changed.

### Changed

- Commands now target the Expo project in the current folder before the
  saved `PROJECT_DIR`.

### Fixed

- `scripts/start.sh` caps `CONTAINER_CPUS` to the engine's CPU count instead
  of failing on small VMs.
- `open` force-stops Expo Go first, so a quick-boot snapshot can't leave
  stale code on screen.
- Gboard's stylus tutorial no longer hijacks typing. The emulator
  advertises stylus input, so `emulator start` disables handwriting.
- `scroll`/`tap-text`/`fill` hide the on-screen keyboard first, which stops
  accidental glide typing. Scroll swipes start inside the scroll view.
- Expo Go's first-run developer menu is dismissed after install or
  `app clear`.

## [0.1.0] - 2026-11-15

### Added

- Docker image: Ubuntu 24.04, OpenJDK 17, Node.js 24.22.3, Bun 1.4.4, Android
  cmdline-tools and platform-tools 37.0.3.
- Native macOS Android Emulator (build 16863232) with an Android 16 / API 36
  Google APIs image (x86_64 on Intel, arm64 on Apple Silicon), installed into
  an isolated `~/.expoemu`. macOS doesn't need Java.
- Shared adb server: the container's adb client talks to the macOS server
  through `host.docker.internal`.
- Metro on `127.0.0.1` with `adb reverse` into the emulator.
- Scripts: `setup`, `start`, `stop`, `shell`, `expo`, `open-app`,
  `emulator-start`, `emulator-stop`, `screenshot`, `device`, `status`,
  `cleanup`, `check-versions`.
- Agent-friendly device control: UI element listing, tap by text,
  screenshots, logcat filters.
- Open-source project files: MIT license, contributing guide, code of
  conduct, security policy, CI, Dependabot.
