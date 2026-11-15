# Expo Emulator (`expoemu`)

[![npm](https://img.shields.io/npm/v/expoemu.svg)](https://www.npmjs.com/package/expoemu)
[![CI](https://github.com/OWNER/expoemu/actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Run and test **Expo / React Native apps on a real Android emulator on your
Mac** with one npm command, and no Android Studio, Java or system-wide Android
SDK. **Expo Emulator** (`expoemu`) — Expo + Android **emu**lator.

```bash
npx expoemu up    # phone boots, Metro starts, your app opens
```

- 🐳 **Toolchain in Docker:** JDK 17, Node.js, Bun, Expo CLI, Metro, adb
- 📱 **Native emulator on macOS:** Google's Android Emulator with an Android
  16 (API 36) Pixel device, hardware-accelerated by Hypervisor.framework
- 🤖 **AI-assistant ready:** `npx expoemu screenshot`, `ui`, `tap-text`,
  `logcat`… let Claude Code or any AI agent test your app from the terminal
- 🧹 **Clean host:** everything on macOS lives in `~/.expoemu` and is
  removed with one command
- 📌 **Reproducible:** every download is version-pinned and checksum-verified

```text
 macOS                                          Docker (or Kiri)
┌───────────────────────────┐   adb (5037)   ┌───────────────────────────┐
│ Android Emulator (native) │◄──────────────►│ Expo CLI · Metro · Bun    │
│ isolated SDK + AVD        │   Metro (8081) │ JDK 17 · adb client       │
│ VS Code / AI agent        │◄──────────────►│ /workspace = your project │
└───────────────────────────┘                └───────────────────────────┘
```

## Requirements

- macOS 13+ on **Intel or Apple Silicon**
- Node.js 18+ (for `npx`) or Bun (`bunx expoemu …` works too)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/), or
  optionally [Kiri](https://runkiri.com) (see [Using Kiri](#optional-using-kiri-instead-of-docker-desktop))
- About 10 GB free disk space (SDK and system image ~6 GB, AVD data ~2 GB,
  Docker image ~0.6 GB, plus `node_modules` volumes)
- An Expo project that uses **Expo Go**

## Quick start

Run everything **from your Expo project folder**:

```bash
cd ~/code/my-expo-app

npx expoemu setup     # once: isolated SDK + Pixel AVD + Docker image (~10 min)
npx expoemu up        # every session: phone + container + Metro + open the app
# … edit code, Fast Refresh updates the phone …
npx expoemu down      # stop everything
```

Next time, `npx expoemu up` takes about 30 seconds. Nothing is reinstalled.

**Recommended for teams and AI assistants:** add it to the project, so the
version is pinned and `npx` never prompts:

```bash
npm i -D expoemu      # or: bun add -d expoemu
npx expoemu up
```

## Commands

| Command | What it does |
|---------|--------------|
| `npx expoemu setup` | One-time install (idempotent). `--runtime docker\|kiri`, `--accept-licenses`, `--recreate-avd` |
| `npx expoemu up` | Boot the phone, start the container and Metro, open the app. `--no-animations`, `--headless`, `--cold-boot` |
| `npx expoemu down` | Stop the container, emulator and adb server (image and caches kept) |
| `npx expoemu status` | Health check of SDK, emulator, adb, container and Metro (exit 1 if broken) |
| `npx expoemu emulator start\|stop` | Only the phone |
| `npx expoemu start` / `stop` | Only the container (runs `bun install` on first use) |
| `npx expoemu expo [--background\|--logs\|--stop]` | Metro (interactive by default) |
| `npx expoemu open [--reinstall]` | Install the matching Expo Go if needed and open the app |
| `npx expoemu shell [cmd…]` | Shell or command in the container, e.g. `npx expoemu shell bun add zod` |
| `npx expoemu cleanup …` | Scoped removal: `--project`, `--caches`, `--image`, `--sdk`, `--all` |

### Device actions

In the commands below, a `"Text"` selector matches **visible text,
`accessibilityLabel`, `testID` or a TextInput `placeholder`**. An exact match
wins over a partial one.

**See the screen**

| Command | What it does |
|---------|--------------|
| `screenshot [name]` | PNG in `./.android-screenshots/`, prints its path (also `latest.png`) |
| `record [SECONDS] [name]` | MP4 screen recording (default 10 s, max 180) |
| `ui [--xml]` | Elements with tap coordinates, testIDs and focused/checked/disabled flags (or raw XML) |
| `texts` | Just the visible text |
| `find "Text"` | Center `X Y` of an element |

**Touch**

| Command | What it does |
|---------|--------------|
| `tap X Y` · `double-tap X Y` · `long-press X Y [ms]` | Tap by pixels |
| `tap-text "Sign in"` · `long-press-text "Item" [ms]` | Tap an element |
| `swipe X1 Y1 X2 Y2 [ms]` · `drag X1 Y1 X2 Y2 [ms]` | Gestures |
| `scroll down\|up\|left\|right` | Scrolls inside the scrollable view |
| `scroll-to "Row 30" [--up] [--max N]` | Scroll until an element is visible |

**Type and keys**

| Command | What it does |
|---------|--------------|
| `fill "Email" "me@x.com"` | Tap a field, clear it, type, hide the keyboard |
| `text "hello"` · `clear` · `hide-keyboard` | Typing in the focused field |
| `key NAME` · `back` · `home` · `recents` · `enter` · `lock` · `unlock` | Keys (`key VOLUME_UP`, `key TAB`, …) |

**Wait and assert** (exit 0 = pass, 1 = fail, so they work as test steps)

| Command | What it does |
|---------|--------------|
| `wait-for "Welcome" [--timeout S]` | Wait until an element appears (default 15 s) |
| `wait-gone "Loading" [--timeout S]` | Wait until it disappears |
| `assert-text "Welcome"` · `assert-no-text "Error"` | Check what's on screen |

**Device state** (all reversible)

| Command | What it does |
|---------|--------------|
| `rotate portrait\|landscape\|auto` | Orientation (apps locked in `app.json` stay put) |
| `dark-mode on\|off` · `font-scale 1.3\|reset` · `animations on\|off` | Display |
| `network on\|off` · `airplane on\|off` | Offline testing. Metro keeps working over adb |
| `location 37.42 -122.08` · `battery 15\|unplug\|charge\|reset` | Sensors |
| `notifications open\|close\|settings` | Notification shade, quick settings |
| `permission grant\|revoke\|list [PERM]` | Runtime permissions, e.g. `permission grant CAMERA` |
| `locale ar\|fr-FR\|reset` | Per-app language (reopen the app to apply) |
| `info` | Device summary |

**App and debugging**

| Command | What it does |
|---------|--------------|
| `app launch\|stop\|restart\|clear\|info [PKG]` | App control. `clear` = fresh-install state |
| `app install FILE.apk` · `app uninstall PKG` · `app list` | Manage APKs |
| `logcat [--errors\|--all] [-n N] [--follow]` | JS logs (`ReactNativeJS`) or errors |
| `crash [-n N]` | Recent crashes |
| `perf [--reset]` · `memory` | Jank %, frame-time percentiles, memory use |
| `reload` · `devmenu` · `open-url URL` · `activity` · `size` · `adb …` | Misc |

Prefix every command with `npx expoemu`, e.g. `npx expoemu scroll-to "Row 30"`.
App commands target Expo Go unless you set `APP_PACKAGE`. Run
`npx expoemu help` for the full list.

## Using it with Claude Code and other AI assistants

An assistant working in your project only needs `npx expoemu` commands:

```bash
npx expoemu status                      # is everything running?
npx expoemu screenshot home             # → prints the PNG path to read
npx expoemu ui                          # elements + tap coordinates
npx expoemu tap-text "Sign in"
npx expoemu logcat --errors -n 50
```

[docs/AGENTS.md](docs/AGENTS.md) has a snippet for your project's
`CLAUDE.md` / `AGENTS.md` and a recommended
screenshot → inspect → interact loop. expoemu doesn't change any assistant's
configuration.

## Configuration

Settings live in `~/.expoemu/config.env`, created by `setup` from
[.env.example](.env.example). In a git clone, they live in the repo's `.env`.

| Variable | Default | Purpose |
|----------|---------|---------|
| `ENV_HOME` | `~/.expoemu` | Isolated SDK, AVD, logs |
| `AVD_RAM_MB` / `AVD_CORES` | `4096` / `4` | Emulator resources |
| `EMULATOR_GPU` | `host` | `swiftshader_indirect` for software rendering |
| `CONTAINER_RUNTIME` | `docker` | `docker` (Docker Desktop) or `kiri` (optional) |
| `CONTAINER_CPUS` / `CONTAINER_MEMORY` | `4` / `6g` | Container limits (CPUs capped to what the engine has) |
| `METRO_PORT` / `ADB_SERVER_PORT` | `8081` / `5037` | Ports |
| `PROJECT_DIR` | — | Fallback project when not run from an Expo folder |

Tool versions are pinned in [config/versions.env](config/versions.env). After
upgrading expoemu, the Docker image rebuilds automatically if its sources
changed.

## Working with several projects

Run `npx expoemu up` from another project's folder and the container is
recreated with that project mounted. Each project keeps its own Linux
`node_modules` volume. Bun, Expo and Gradle caches are shared.

> **Note:** The container's `node_modules` is a Docker volume that hides your
> macOS `node_modules`. Add packages with `npx expoemu shell bun add <pkg>`.
> A macOS `bun install` for editor types also works. The two copies don't
> interfere.

## Optional: using Kiri instead of Docker Desktop

[Kiri](https://runkiri.com) is a small, fast container runtime that speaks
the Docker Engine API. It's **entirely optional**. Docker Desktop stays the
default, and expoemu never installs Kiri or changes your Docker settings.

1. Install Kiri yourself by following [its docs](https://docs.runkiri.com/install/).
   It needs macOS 14 or newer. On Apple Silicon it also needs Apple Rosetta
   (`softwareupdate --install-rosetta`), because the image is `linux/amd64`.
2. Switch expoemu to Kiri: `npx expoemu setup --runtime kiri --skip-sdk`
3. Use everything as usual. `npx expoemu status` shows `Container runtime: Kiri`.

The scripts set `DOCKER_HOST=unix://~/.kiri/run/docker.sock` for their own
process only. Your global `docker context` stays as it is. Images and volumes
are separate per runtime.

> **Status:** the adb and Metro networking relies on features Kiri
> documents (`host.docker.internal` → the Mac's loopback, and
> `-p 127.0.0.1:…`). The full flow hasn't yet been run on a real Kiri install,
> and Kiri doesn't document whether file-change events (needed for Fast
> Refresh) cross its file sharing. Please report your results in an issue.

## Cleanup and uninstall

```bash
npx expoemu cleanup --project     # this project's node_modules volume
npx expoemu cleanup --caches      # all volumes created by expoemu
npx expoemu cleanup --all         # full uninstall: container, volumes, image, ~/.expoemu
```

Cleanup shows what it will remove and asks first. It only touches resources
labelled `com.expoemu.managed=true` with the `expoemu`
prefix, plus `ENV_HOME` if setup created it. Your projects, other Docker
resources and other Android SDKs are never touched.

## From source (contributors)

```bash
git clone https://github.com/OWNER/expoemu.git && cd expoemu
scripts/setup.sh --project ~/code/my-expo-app
```

Every `npx expoemu <cmd>` has a script in [scripts/](scripts/), e.g.
`scripts/emulator-start.sh`, `scripts/device.sh tap-text "Sign in"`. You can
also run `node bin/expoemu.js <cmd>`.

## Documentation

- [Architecture: how the pieces connect](docs/ARCHITECTURE.md)
- [AI assistant guide](docs/AGENTS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Contributing

Contributions are welcome: version bumps, Linux/Windows host support, new
device helpers. See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Security issues: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The Android SDK components downloaded by `setup` are
provided by Google under the
[Android SDK License Agreement](https://developer.android.com/studio/terms).
