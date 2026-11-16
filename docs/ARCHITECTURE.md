# Architecture

## Why the emulator is not in Docker

Docker Desktop on macOS runs containers inside a Linux VM. That VM doesn't
expose hardware virtualization (KVM) to containers, so an emulator inside
Docker would run without acceleration and be unusably slow, with no graphical
window either. The Android Emulator therefore runs **natively on macOS**,
accelerated by Apple's **Hypervisor.framework**. Everything else (JDK, Node,
Bun, Expo CLI, Metro, adb client, caches) runs in Docker.

## Components

```text
┌─────────────────────────────── macOS ───────────────────────────────┐
│                                                                      │
│  Your editor / AI agent ── runs ──> scripts/*.sh                     │
│                                                                      │
│  ~/.expoemu/            (ENV_HOME, fully isolated)          │
│    sdk/platform-tools/adb  ──>  adb server  127.0.0.1:5037           │
│    sdk/emulator/emulator   ──>  Android 16 VM (Hypervisor.framework) │
│    sdk/system-images/...        ▲ registers with adb server          │
│    avd/expo_pixel_api36.avd     │                                    │
│                                 │                                    │
│  127.0.0.1:8081  ◄── adb reverse tcp:8081 (device → macOS)           │
│        │                                                             │
│  ┌─────┴──────────────── Docker Desktop VM ───────────────────────┐  │
│  │  container "expoemu"  (user: expo)                    │  │
│  │    Metro :8081  (published to 127.0.0.1:8081 on macOS)         │  │
│  │    adb client ── ADB_SERVER_SOCKET=tcp:host.docker.internal:5037 ──► macOS adb server
│  │    /workspace            ← bind mount of your project          │  │
│  │    /workspace/node_modules ← per-project named volume          │  │
│  │    ~/.bun ~/.expo ~/.gradle ~/.cache ← shared cache volumes    │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

## Network paths

| From → To | Path |
|-----------|------|
| Container adb client → emulator | `host.docker.internal:5037` → macOS adb server (bound to loopback; Docker Desktop forwards `host.docker.internal` to the host's loopback) → emulator |
| Emulator → Metro | app requests `127.0.0.1:8081` on the device → `adb reverse` → macOS `127.0.0.1:8081` → Docker published port → Metro in container |
| macOS scripts / agents → emulator | isolated `adb` in `ENV_HOME` → same server |

`localhost` in the container is the container itself. The container never
assumes it is macOS.

### One adb server, version-locked

Only one adb server runs, on macOS. The container's adb is a *client* only.
adb refuses to talk across versions and kills a mismatched server, so
`config/versions.env` pins platform-tools to the **same version** on both
sides, installed from fixed archives instead of sdkmanager's "latest".

## Why no Java on macOS

`sdkmanager` and `avdmanager` are Java programs. Instead of installing a JDK on
the host, `scripts/setup.sh` downloads the exact archives (emulator, system
image, platform-tools), checks their SHA-1, and writes the AVD's `config.ini`
directly. The container has a JDK for Gradle and native builds.

## Isolation guarantees

- `ANDROID_HOME`, `ANDROID_AVD_HOME`, `ANDROID_USER_HOME` and
  `ANDROID_EMULATOR_HOME` are exported **only inside the scripts**. They point
  into `ENV_HOME`, so `~/.android`, `~/Library/Android` and shell profiles are
  never touched.
- Docker resources carry the label `com.expoemu.managed=true` and the
  `expoemu` name prefix. `cleanup.sh` selects by both.
- `cleanup.sh --sdk` deletes `ENV_HOME` only if it contains the marker
  `.expoemu-root` written by setup.

## Lifecycle and persistence

| Command | Removes | Keeps |
|---------|---------|-------|
| `scripts/stop.sh` | container | image, node_modules, caches, SDK, AVD |
| `scripts/emulator-stop.sh` | emulator process, adb server | AVD + quick-boot snapshot |
| `scripts/cleanup.sh --project` | one project's node_modules volume | everything else |
| `scripts/cleanup.sh --caches` | all env volumes | image, SDK |
| `scripts/cleanup.sh --all` | everything this project created | your projects |

## Several emulators

Each device is an AVD under `~/.expoemu/avd/`, written directly from a
profile (`scripts/lib/common.sh` → `write_avd`). All AVDs point at the same
system image, so a new device only adds its data disk.

Running emulators take consecutive console/adb port pairs (5554/5555,
5556/5557, …) and all register with the **one** adb server, so the
container sees every device. Metro's port is reversed into each device, so
one Metro serves all of them, and each device runs its own copy of the app.

Commands choose their device in `require_device`: `EXPOEMU_DEVICE` (set by
the CLI's global `--device`) can be a device name or a serial. Without it,
commands use the default device. `open --all` and `screenshot --all` loop
over `running_emulators`.

## Container runtimes

The container side works with any engine that speaks the Docker Engine API
and provides `host.docker.internal` → host loopback:

| `CONTAINER_RUNTIME` | Engine | How the scripts reach it |
|---------------------|--------|--------------------------|
| `docker` (default) | Docker Desktop | current docker context |
| `kiri` (optional) | [Kiri](https://runkiri.com) | `DOCKER_HOST=unix://$KIRI_SOCKET`, set inside the scripts only |

The runtime is chosen in `scripts/lib/common.sh` (`select_runtime`). Nothing
global is changed: no `docker context use`, no edits to
`~/.docker/config.json`, and Kiri is never installed by this repo.

## Apple Silicon

The emulator and system image are native arm64 (`arm64-v8a`). Google only
ships Linux adb for x86_64, so the container is built as `linux/amd64` and
runs under Docker Desktop's Rosetta/QEMU emulation. Bun's "baseline" build is
selected automatically when AVX2 is unavailable.
