# expo-android · `eaenv`

[![npm](https://img.shields.io/npm/v/eaenv.svg)](https://www.npmjs.com/package/eaenv)
[![CI](https://github.com/OWNER/expo-android/actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Run and test **Expo / React Native apps on a real Android emulator on your
Mac** with one npm command, and no Android Studio, Java or system-wide Android
SDK. **eaenv** stands for **E**xpo **A**ndroid **ENV**ironment.

```bash
npx eaenv up    # phone boots, Metro starts, your app opens
```

- 🐳 **Toolchain in Docker:** JDK 17, Node.js, Bun, Expo CLI, Metro, adb
- 📱 **Native emulator on macOS:** Google's Android Emulator with an Android
  16 (API 36) Pixel device, hardware-accelerated by Hypervisor.framework
- 🤖 **AI-assistant ready:** `npx eaenv screenshot`, `ui`, `tap-text`,
  `logcat`… let Claude Code or any AI agent test your app from the terminal
- 🧹 **Clean host:** everything on macOS lives in `~/.expo-android-env` and is
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
- Node.js 18+ (for `npx`) or Bun (`bunx eaenv …` works too)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/), or
  optionally [Kiri](https://runkiri.com) (see [Using Kiri](#optional-using-kiri-instead-of-docker-desktop))
- About 10 GB free disk space (SDK and system image ~6 GB, AVD data ~2 GB,
  Docker image ~0.6 GB, plus `node_modules` volumes)
- An Expo project that uses **Expo Go**

## Quick start

Run everything **from your Expo project folder**:

```bash
cd ~/code/my-expo-app

npx eaenv setup     # once: isolated SDK + Pixel AVD + Docker image (~10 min)
npx eaenv up        # every session: phone + container + Metro + open the app
# … edit code, Fast Refresh updates the phone …
npx eaenv down      # stop everything
```

Next time, `npx eaenv up` takes about 30 seconds. Nothing is reinstalled.

**Recommended for teams and AI assistants:** add it to the project, so the
version is pinned and `npx` never prompts:

```bash
npm i -D eaenv      # or: bun add -d eaenv
npx eaenv up
```

## Commands

| Command | What it does |
|---------|--------------|
| `npx eaenv setup` | One-time install (idempotent). `--runtime docker\|kiri`, `--accept-licenses`, `--recreate-avd` |
| `npx eaenv up` | Boot the phone, start the container and Metro, open the app. `--no-animations`, `--headless`, `--cold-boot` |
| `npx eaenv down` | Stop the container, emulator and adb server (image and caches kept) |
| `npx eaenv status` | Health check of SDK, emulator, adb, container and Metro (exit 1 if broken) |
| `npx eaenv emulator start\|stop` | Only the phone |
| `npx eaenv start` / `stop` | Only the container (runs `bun install` on first use) |
| `npx eaenv expo [--background\|--logs\|--stop]` | Metro (interactive by default) |
| `npx eaenv open [--reinstall]` | Install the matching Expo Go if needed and open the app |
| `npx eaenv shell [cmd…]` | Shell or command in the container, e.g. `npx eaenv shell bun add zod` |
| `npx eaenv cleanup …` | Scoped removal: `--project`, `--caches`, `--image`, `--sdk`, `--all` |

**Device control:**

| Command | What it does |
|---------|--------------|
| `npx eaenv screenshot [name]` | Save a PNG to `./.android-screenshots/` and print its path |
| `npx eaenv ui` | List on-screen elements with tap coordinates |
| `npx eaenv tap X Y` · `tap-text "Sign in"` · `find "Sign in"` | Tap by pixels or by visible text |
| `npx eaenv swipe X1 Y1 X2 Y2` · `scroll down\|up` | Gestures |
| `npx eaenv text "hello"` · `key ENTER` · `back` · `home` | Typing and keys |
| `npx eaenv logcat [--errors\|--all] [-n N]` | App logs (`ReactNativeJS`) or errors |
| `npx eaenv reload` · `devmenu` · `open-url URL` · `adb …` | Misc |

Run `npx eaenv help` for the full list.

## Using it with Claude Code and other AI assistants

An assistant working in your project only needs `npx eaenv` commands:

```bash
npx eaenv status                      # is everything running?
npx eaenv screenshot home             # → prints the PNG path to read
npx eaenv ui                          # elements + tap coordinates
npx eaenv tap-text "Sign in"
npx eaenv logcat --errors -n 50
```

[docs/AGENTS.md](docs/AGENTS.md) has a snippet for your project's
`CLAUDE.md` / `AGENTS.md` and a recommended
screenshot → inspect → interact loop. eaenv doesn't change any assistant's
configuration.

## Configuration

Settings live in `~/.expo-android-env/config.env`, created by `setup` from
[.env.example](.env.example). In a git clone, they live in the repo's `.env`.

| Variable | Default | Purpose |
|----------|---------|---------|
| `ENV_HOME` | `~/.expo-android-env` | Isolated SDK, AVD, logs |
| `AVD_RAM_MB` / `AVD_CORES` | `4096` / `4` | Emulator resources |
| `EMULATOR_GPU` | `host` | `swiftshader_indirect` for software rendering |
| `CONTAINER_RUNTIME` | `docker` | `docker` (Docker Desktop) or `kiri` (optional) |
| `CONTAINER_CPUS` / `CONTAINER_MEMORY` | `4` / `6g` | Container limits (CPUs capped to what the engine has) |
| `METRO_PORT` / `ADB_SERVER_PORT` | `8081` / `5037` | Ports |
| `PROJECT_DIR` | — | Fallback project when not run from an Expo folder |

Tool versions are pinned in [config/versions.env](config/versions.env). After
upgrading eaenv, the Docker image rebuilds automatically if its sources
changed.

## Working with several projects

Run `npx eaenv up` from another project's folder and the container is
recreated with that project mounted. Each project keeps its own Linux
`node_modules` volume. Bun, Expo and Gradle caches are shared.

> **Note:** The container's `node_modules` is a Docker volume that hides your
> macOS `node_modules`. Add packages with `npx eaenv shell bun add <pkg>`.
> A macOS `bun install` for editor types also works. The two copies don't
> interfere.

## Optional: using Kiri instead of Docker Desktop

[Kiri](https://runkiri.com) is a small, fast container runtime that speaks
the Docker Engine API. It's **entirely optional**. Docker Desktop stays the
default, and eaenv never installs Kiri or changes your Docker settings.

1. Install Kiri yourself by following [its docs](https://docs.runkiri.com/install/).
   It needs macOS 14 or newer. On Apple Silicon it also needs Apple Rosetta
   (`softwareupdate --install-rosetta`), because the image is `linux/amd64`.
2. Switch eaenv to Kiri: `npx eaenv setup --runtime kiri --skip-sdk`
3. Use everything as usual. `npx eaenv status` shows `Container runtime: Kiri`.

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
npx eaenv cleanup --project     # this project's node_modules volume
npx eaenv cleanup --caches      # all volumes created by eaenv
npx eaenv cleanup --all         # full uninstall: container, volumes, image, ~/.expo-android-env
```

Cleanup shows what it will remove and asks first. It only touches resources
labelled `com.expo-android-env.managed=true` with the `expo-android-env`
prefix, plus `ENV_HOME` if setup created it. Your projects, other Docker
resources and other Android SDKs are never touched.

## From source (contributors)

```bash
git clone https://github.com/OWNER/expo-android.git && cd expo-android
scripts/setup.sh --project ~/code/my-expo-app
```

Every `npx eaenv <cmd>` has a script in [scripts/](scripts/), e.g.
`scripts/emulator-start.sh`, `scripts/device.sh tap-text "Sign in"`. You can
also run `node bin/eaenv.js <cmd>`.

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
