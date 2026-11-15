# expo-android-environment

[![CI](https://github.com/OWNER/expo-android-environment/actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Run and test **Expo / React Native apps on a real Android emulator on your
Mac** without installing Android Studio, Java or the Android SDK system-wide.

- 🐳 **Toolchain in Docker:** JDK 17, Node.js, Bun, Expo CLI, Metro, adb
- 📱 **Native emulator on macOS:** Google's Android Emulator with an Android
  16 (API 36) Pixel device, hardware-accelerated by Hypervisor.framework
- 🧹 **Clean host:** everything on macOS lives in one folder
  (`~/.expo-android-env`) and is removed with one command
- 🤖 **Agent-ready:** plain terminal commands for screenshots, taps, swipes,
  UI inspection and logs, so Claude Code or any AI agent can test your app
- 📌 **Reproducible:** every download is version-pinned and checksum-verified

```text
 macOS                                          Docker
┌───────────────────────────┐   adb (5037)   ┌───────────────────────────┐
│ Android Emulator (native) │◄──────────────►│ Expo CLI · Metro · Bun    │
│ isolated SDK + AVD        │   Metro (8081) │ JDK 17 · adb client       │
│ VS Code / AI agent        │◄──────────────►│ /workspace = your project │
└───────────────────────────┘                └───────────────────────────┘
```

## Requirements

- macOS 13+ on **Intel or Apple Silicon**
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- About 10 GB free disk space (SDK and system image ~6 GB, AVD data ~2 GB,
  Docker image ~0.6 GB, plus `node_modules` volumes)
- An Expo project that uses **Expo Go**

## Quick start

```bash
# 1. Get the tools (anywhere you like)
git clone https://github.com/OWNER/expo-android-environment.git ~/tools/expo-android-environment
cd ~/tools/expo-android-environment

# 2. One-time setup: isolated SDK + Pixel AVD + Docker image (~10 min)
scripts/setup.sh --project ~/code/my-expo-app

# 3. Every development session
scripts/emulator-start.sh          # boot the phone (window appears)
scripts/start.sh                   # start the container (uses PROJECT_DIR from .env)
scripts/expo.sh --background       # Metro in the background (or `scripts/expo.sh` for the interactive UI)
scripts/open-app.sh                # installs the matching Expo Go if needed, opens your app
```

Edit code on macOS as usual and Fast Refresh updates the phone within
seconds. The first emulator boot takes about 2–3 minutes. Later boots use a
quick-boot snapshot.

```bash
# Finish for the day
scripts/stop.sh --all              # container + emulator + adb server
```

Next time, just run step 3. Nothing is reinstalled.

## Commands

| Command | What it does |
|---------|--------------|
| `scripts/setup.sh [--project DIR]` | One-time install (idempotent). `--recreate-avd`, `--skip-docker`, `--skip-sdk` |
| `scripts/emulator-start.sh` | Boot the emulator and wait until ready. `--headless`, `--cold-boot`, `--wipe`, `--no-animations` |
| `scripts/emulator-stop.sh` | Shut down the emulator (snapshot saved) and the adb server |
| `scripts/start.sh [DIR]` | Start the container for a project; runs `bun install` on first use |
| `scripts/stop.sh [--all]` | Stop the container (`--all` also stops the emulator) |
| `scripts/shell.sh [cmd…]` | Shell or one command inside the container, e.g. `scripts/shell.sh bun add zod` |
| `scripts/expo.sh [args]` | `bunx expo start` in the container. `--background`, `--logs`, `--stop` |
| `scripts/open-app.sh` | Install Expo Go if missing and open the app |
| `scripts/screenshot.sh [name]` | Save a PNG to `<project>/.android-screenshots/` and print its path |
| `scripts/device.sh …` | `tap`, `swipe`, `scroll`, `text`, `key`, `back`, `home`, `ui`, `find`, `tap-text`, `logcat`, `reload`, `open-url`, `adb …` |
| `scripts/status.sh` | Health check of SDK, emulator, adb, container and Metro |
| `scripts/cleanup.sh …` | Scoped removal: `--containers`, `--project`, `--caches`, `--image`, `--sdk`, `--all` |
| `scripts/check-versions.sh` | Compare pinned versions with the latest upstream releases |

Plain Docker Compose also works once `.env` has `PROJECT_DIR`:
`docker compose up -d`, `docker compose exec -u expo app bash`, `docker compose down`.

## Using it with Claude Code and other AI agents

The scripts work from any directory, so an agent working in your Expo project
can call them by absolute path:

```bash
~/tools/expo-android-environment/scripts/screenshot.sh home      # → prints PNG path
~/tools/expo-android-environment/scripts/device.sh ui            # elements + tap coordinates
~/tools/expo-android-environment/scripts/device.sh tap-text "Sign in"
~/tools/expo-android-environment/scripts/device.sh logcat --errors
```

[docs/AGENTS.md](docs/AGENTS.md) has a ready-made snippet for your project's
`CLAUDE.md` / `AGENTS.md` and a recommended verification loop. Nothing in this
repo changes your agent's configuration.

## Configuration

`scripts/setup.sh` creates `.env` from [.env.example](.env.example). Common settings:

| Variable | Default | Purpose |
|----------|---------|---------|
| `PROJECT_DIR` | — | Expo project mounted at `/workspace` |
| `ENV_HOME` | `~/.expo-android-env` | Isolated SDK, AVD, logs |
| `AVD_RAM_MB` / `AVD_CORES` | `4096` / `4` | Emulator resources |
| `EMULATOR_GPU` | `host` | `swiftshader_indirect` for software rendering |
| `CONTAINER_CPUS` / `CONTAINER_MEMORY` | `4` / `6g` | Docker limits |
| `METRO_PORT` / `ADB_SERVER_PORT` | `8081` / `5037` | Ports |
| `WATCH_POLLING` | `false` | Set `true` if Fast Refresh misses file changes |

Tool versions live in [config/versions.env](config/versions.env).

## Working with several projects

Run `scripts/start.sh /path/to/other-app` to switch projects. The container is
recreated with the new mount. Each project keeps its own Linux `node_modules`
volume, and Bun/Expo/Gradle caches are shared.

> **Note:** The container's `node_modules` is a Docker volume that hides your
> macOS `node_modules`. Add packages with `scripts/shell.sh bun add <pkg>`.
> If your editor needs type definitions, you can also run `bun install` on
> macOS. The two copies don't interfere.

## Cleanup and uninstall

```bash
scripts/cleanup.sh --project          # this project's node_modules volume
scripts/cleanup.sh --caches           # all volumes created by this environment
scripts/cleanup.sh --all              # full uninstall: container, volumes, image, ~/.expo-android-env
```

Cleanup only touches resources labelled `com.expo-android-env.managed=true`
with the `expo-android-env` prefix, plus `ENV_HOME` if setup created it. Your
projects, other Docker resources and other Android SDKs are never touched.

## Documentation

- [Architecture: how the pieces connect](docs/ARCHITECTURE.md)
- [AI agent guide](docs/AGENTS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Contributing

Contributions are welcome: version bumps, Linux/Windows host support, new
device helpers. See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Security issues: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The Android SDK components downloaded by `setup.sh` are
provided by Google under the
[Android SDK License Agreement](https://developer.android.com/studio/terms).
