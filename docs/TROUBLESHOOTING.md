# Troubleshooting

Start with `expoemu status` (or `scripts/status.sh` in a git clone). It
checks every link in the chain and prints a hint for each failure.

> Script names below map to `expoemu` commands: `scripts/emulator-start.sh`
> → `expoemu emulator start`, `scripts/open-app.sh` → `expoemu open`,
> `scripts/device.sh logcat` → `expoemu logcat`, and so on.

## The `expoemu` command

**`expoemu: command not found`.**
The global command isn't installed, or isn't on your PATH:

- Install it: `npx expoemu install` (setup normally does this).
- **Using nvm/fnm?** Global npm commands belong to one Node version. After
  switching versions, run `npx expoemu install` again.
- **Installed but still not found?** `npx expoemu install` prints a warning if
  npm's global `bin` folder isn't on your PATH, together with the line to add
  to `~/.zshrc`. Open a new terminal afterwards.
- **`EACCES` / permission denied:** npm's global folder belongs to root.
  Don't use sudo. Switch to a Node version manager (nvm, fnm, volta), or run
  `npm config set prefix ~/.npm-global` and add `~/.npm-global/bin` to your
  PATH.

Until then, every command also works as `npx expoemu …`.

**Old version after a release:** `expoemu update`.

## Emulator

**Emulator exits during boot.**
Check `~/.expoemu/logs/emulator.log`. Common causes:

- *Not enough memory:* lower `AVD_RAM_MB` in `.env`, then
  `scripts/setup.sh --recreate-avd`.
- *GPU problems* (black screen, crash in `libOpenglRender`): set
  `EMULATOR_GPU=swiftshader_indirect` in `.env`.
- *Corrupt snapshot:* `scripts/emulator-start.sh --cold-boot`. If that fails,
  try `--wipe`.

**"HVF is not available" / slow emulator.**
Run `~/.expoemu/sdk/emulator/emulator -accel-check`. On macOS,
Hypervisor.framework is built in. If you're inside a VM (e.g. a CI Mac VM),
nested virtualization may be unavailable.

**Screen is locked / taps do nothing.**
Run `expoemu unlock`.

**A "Try out your stylus" screen appears when typing.**
The emulator's virtual touchscreen reports stylus support, so Gboard shows
its handwriting tutorial. `emulator start` turns this off. If you started the
emulator another way, run
`expoemu adb shell settings put secure stylus_handwriting_enabled 0`.

**"This is the developer menu" covers the app.**
That's Expo Go's one-time introduction after it's installed or its data is
cleared. `open` and `app clear` dismiss it automatically. You can also run
`expoemu tap-text Continue` and then `expoemu tap-text Close`.

**`rotate landscape` does nothing.**
The app is locked to one orientation. The Expo template sets
`"orientation": "portrait"` in `app.json`. Change it to `"default"` to allow
rotation. The home screen launcher also never rotates.

**`scroll` types random words into a text field.**
That happened when the swipe crossed the on-screen keyboard (glide typing).
`scroll`, `tap-text` and `fill` now hide the keyboard first. For raw
`swipe`, run `expoemu hide-keyboard` before it.

## adb

**Container can't see the emulator.**
1. `scripts/status.sh`: is the adb server listening on `127.0.0.1:5037`?
2. Run `scripts/shell.sh adb devices` inside the container.
3. If you changed `ADB_SERVER_PORT`, restart both sides:
   `scripts/stop.sh --all`, then start again.

**"adb server version doesn't match this client; killing…"**
Some other adb (e.g. from Android Studio or Homebrew) is using the same
port with a different version. Either quit it or give this environment its
own port, e.g. `ADB_SERVER_PORT=5038` in `.env`. Keep both platform-tools
versions in `config/versions.env` identical.

## Metro / Expo

**App shows "Could not connect to development server".**
- Is Metro running? Run `scripts/expo.sh --logs` or `curl 127.0.0.1:8081/status`.
- Re-apply the tunnel with `scripts/open-app.sh`. It runs `adb reverse`
  again. The reverse resets when the emulator restarts.

**Port 8081 already in use.**
Another Metro is running on macOS. Stop it, or set `METRO_PORT=8082`.

**Fast Refresh doesn't pick up changes.**
First check `scripts/expo.sh --logs` for *"Metro is running in CI mode,
reloads are disabled"*. Expo turns off file watching when `CI` is set, so
never export `CI=1` when running Metro. The scripts don't set it. If that's
not the cause, set `WATCH_POLLING=true` in `.env` and restart the container
(`scripts/start.sh`). Also make sure Docker Desktop uses **VirtioFS** file
sharing (Settings → General).

**Native module / binary errors after switching branches.**
Reinstall the Linux node_modules with
`scripts/cleanup.sh --project && scripts/start.sh`.

**Expo Go version doesn't match the project SDK.**
`scripts/open-app.sh --reinstall` downloads the Expo Go build for the
project's `expo` version.

## UI commands

**`ui`, `tap-text`, `wait-for` take ~3 s each.** The UI server isn't used.
`expoemu ui-server status` says why: turned off with `EXPOEMU_UI_SERVER=0`,
a physical phone (opt in with `EXPOEMU_UI_SERVER=1`), or a git clone without
the APK (run `server/build.sh`). After a failed start it isn't retried for
5 minutes. `expoemu ui-server start` retries now and prints the error.

**Maestro, Appium or `uiautomator` fails with "already registered" or gets
killed.** Android allows one UI-automation connection at a time, and the UI
server holds it. Run `expoemu ui-server stop` first, or set
`EXPOEMU_UI_SERVER=0` while you use the other tool. expoemu restarts the
server on the next UI command.

**Screen read right after a tap shows the old screen.** Before reading, the
server waits until the UI has been still for 300 ms. For slow transitions,
use `wait-for "Text"` (it retries), or raise `EXPOEMU_UI_IDLE_MS`.

## Kiri (optional runtime)

**"Kiri is not running (no socket at …)".**
Open Kiri.app. If Kiri is installed somewhere non-standard, set
`KIRI_SOCKET` in `.env` to its Docker API socket.

**"Kiri needs Apple Rosetta for linux/amd64 images".**
Run `softwareupdate --install-rosetta`. Kiri runs amd64 images only through
Rosetta on Apple Silicon.

**Container refused: "range of CPUs is from 0.01 to 2.00".**
Kiri's VM defaults to 2 CPUs. `scripts/start.sh` caps `CONTAINER_CPUS`
automatically. If you run `docker compose` directly, lower `CONTAINER_CPUS`
or give the VM more CPUs in `~/.kiri/vm.json`.

**Image or volumes "missing" after switching runtimes.**
Kiri and Docker Desktop keep separate images and volumes. Run
`scripts/setup.sh --runtime kiri --skip-sdk` once to build the image on Kiri.

**Fast Refresh doesn't react on Kiri.**
Kiri doesn't document whether file-change events propagate through its
virtiofs sharing. Check `scripts/expo.sh --logs`, then open an issue with your
Kiri version (`kiri update --check`).

## Docker

**`PROJECT_DIR` error from docker compose.**
Set `PROJECT_DIR` in `.env`, or use `scripts/start.sh /path/to/app`.

**Slow on Apple Silicon.**
The container runs as `linux/amd64` because Google publishes Linux adb only
for x86_64. Enable *Use Rosetta for x86_64/amd64 emulation* in Docker Desktop
settings. The emulator itself runs natively.
