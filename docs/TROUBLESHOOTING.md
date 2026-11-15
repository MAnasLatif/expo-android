# Troubleshooting

Start with `scripts/status.sh`. It checks every link in the chain and prints
a hint for each failure.

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
`scripts/device.sh key WAKEUP` then `scripts/device.sh adb shell wm dismiss-keyguard`.

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

## Docker

**`PROJECT_DIR` error from docker compose.**
Set `PROJECT_DIR` in `.env`, or use `scripts/start.sh /path/to/app`.

**Slow on Apple Silicon.**
The container runs as `linux/amd64` because Google publishes Linux adb only
for x86_64. Enable *Use Rosetta for x86_64/amd64 emulation* in Docker Desktop
settings. The emulator itself runs natively.
