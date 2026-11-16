# expoemu command reference

Every command is `expoemu <command> [args]`, run from the Expo project root.
After `setup` (or `expoemu install`) the global command exists, so `expoemu <command>`
works the same without `npx`.
Exit code `0` = success, `1` = failure (reason on stderr), `2` = usage error.
Add `--device NAME` (or `-d NAME`) to any command to target one device; for
`adb`, `shell` and `expo` put it before the command.

## Contents

- [Setup and lifecycle](#setup-and-lifecycle)
- [Several devices](#several-devices)
- [See the screen](#see-the-screen)
- [Touch](#touch)
- [Type and keys](#type-and-keys)
- [Wait and assert](#wait-and-assert)
- [Device state](#device-state)
- [App control and debugging](#app-control-and-debugging)
- [Maintenance](#maintenance)
- [Configuration](#configuration)

## Setup and lifecycle

| Command | What it does |
|---------|--------------|
| `setup [--accept-licenses] [--runtime docker\|kiri] [--recreate-avd] [--skip-sdk] [--skip-docker] [--no-global]` | One-time install: isolated Android SDK + Pixel phone in `~/.expoemu`, Docker image, and the global `expoemu` command (unless `--no-global`). Idempotent. `--accept-licenses` accepts the Android SDK license (ask the user first). |
| `install` | Install only the global `expoemu` command (npm, or Bun when run via `bunx`). Never uses sudo. |
| `update` | Upgrade the global command to the latest release. |
| `uninstall` | Remove the global command (SDK, devices and settings are kept). |
| `up [--no-animations] [--headless] [--cold-boot]` | Boot the phone, start the container (installs deps on first use), start Metro, open the app in Expo Go. Honors `--device`. |
| `down` | Stop the container, every emulator and the adb server. Image, caches and devices are kept. |
| `status` (alias `doctor`) | Health check of SDK, devices, adb, container, Metro. Exit `1` if something required is down. |
| `emulator start [--device NAME] [--no-animations] [--headless] [--cold-boot] [--wipe]` | Boot one device (default phone). Several can run at once. |
| `emulator stop [--device NAME] [--keep-adb]` | Stop all devices, or one. |
| `start` / `stop` | Start / stop only the container for the current project. |
| `expo [--background\|--logs\|--stop] [expo args]` | Metro bundler. Default is interactive; `--background` returns once Metro is ready. |
| `open [--all] [--reinstall] [--url URL]` | Install the matching Expo Go if needed and open the project (fresh bundle). `--all` = every running device. |
| `shell [cmd…]` | Shell, or one command, inside the container in `/workspace` (the project). |
| `cleanup --project\|--caches\|--image\|--sdk\|--all\|--legacy [--yes]` | Scoped removal of expoemu's own resources. Shows a plan and asks first. Ask the user before running. |

## Several devices

| Command | What it does |
|---------|--------------|
| `devices` | Created devices, profile, screen size and running serial. `*` marks the default. |
| `device create NAME [--profile phone\|small\|large\|tablet\|foldable]` | New device (shares the system image; ~2 GB data). |
| `device delete NAME [--yes]` | Delete a device and its data (not the default). |
| `device profiles` | List profiles with screen and RAM. |

Profiles: `phone` Pixel 8 1080×2400 (default) · `small` 720×1600, 2 GB ·
`large` Pixel 9 Pro XL 1344×2992 · `tablet` Pixel Tablet 2560×1600 ·
`foldable` Pixel Fold inner 2208×1840.

`--device` accepts a device name, `default`, a serial like `emulator-5556`, or a
connected **physical phone** (USB, or Wi-Fi via `expoemu adb connect IP:5555`)
by its model name from `expoemu devices` (e.g. `pixel-7`) or its serial. All
commands work on phones, except emulator-only ones (`network` speed profiles,
`sms`, `call`, `biometric`, `location`).

## See the screen

| Command | What it does |
|---------|--------------|
| `screenshot [--all] [name]` | PNG in `./.android-screenshots/`, prints the absolute path(s). Also updates `latest.png`. |
| `record [SECONDS] [name]` | MP4 screen recording (default 10 s, max 180), prints the path. |
| `ui [--xml]` | One line per element: `centerX centerY \| text \| content-desc \| testID \| class \| flags` (flags: clickable, focused, checked, disabled). `--xml` saves the raw hierarchy and prints its path. |
| `texts` | Visible strings only. |
| `find "Text"` | Center `X Y` of the element (exit 1 if absent). |
| `size` | Screen size in pixels. |
| `activity` | Foreground app / activity. |

## Touch

| Command | What it does |
|---------|--------------|
| `tap X Y` | Tap pixels. |
| `double-tap X Y` | Two quick taps. |
| `long-press X Y [ms]` | Press and hold (default 800 ms). |
| `tap-text "Text"` | Tap an element by selector. Hides the keyboard first. |
| `long-press-text "Text" [ms]` | Long-press an element. |
| `swipe X1 Y1 X2 Y2 [ms]` | Swipe (default 300 ms). |
| `drag X1 Y1 X2 Y2 [ms]` | Drag and drop (default 1000 ms). |
| `scroll down\|up\|left\|right` | Scroll inside the largest scroll view. |
| `scroll-to "Text" [--up] [--max N]` | Scroll until the element is visible (default max 15). Prints `X Y`. |

## Type and keys

| Command | What it does |
|---------|--------------|
| `fill "Field" "value" [--keep-keyboard]` | Tap a field (by text/placeholder/testID), clear it, type, hide the keyboard. |
| `text "hello"` | Type into the focused field. |
| `clear` | Clear the focused field. |
| `hide-keyboard` | Close the on-screen keyboard if shown. |
| `key NAME\|CODE` | Any key: `ENTER`, `TAB`, `DEL`, `VOLUME_UP`, `MENU`, … |
| `back` · `home` · `recents` · `enter` | Shortcuts. |
| `lock` · `unlock` | Screen off / wake and dismiss the lock screen. |

## Wait and assert

All exit `0` on success and `1` on failure, so they work as test steps.

| Command | What it does |
|---------|--------------|
| `wait-for "Text" [--timeout S]` | Wait until the element appears (default 15 s); prints `X Y`. |
| `wait-gone "Text" [--timeout S]` | Wait until it disappears. |
| `assert-text "Text"` | Fail unless on screen. |
| `assert-no-text "Text"` | Fail if on screen. |

## Device state

All reversible. Reset what you change.

| Command | What it does |
|---------|--------------|
| `rotate portrait\|landscape\|reverse-portrait\|reverse-landscape\|auto\|status` | Orientation (no effect if app.json locks it). |
| `dark-mode on\|off\|status` | System dark theme. |
| `font-scale 1.3\|reset\|status` | Accessibility text size (0.85–2.0). |
| `animations on\|off` | System animations. |
| `network on\|off\|status` | Wi-Fi + mobile data. Metro keeps working (adb). |
| `network gprs\|edge\|3g\|4g\|full` | Slow-network profile (speed + latency): gprs ~58 kbit/s, edge ~470 kbit/s, 3g ~14 Mbit/s, 4g ~173 Mbit/s; `full` removes limits. Emulators only. |
| `airplane on\|off\|status` | Airplane mode. |
| `location LAT LON` | GPS position, e.g. `location 37.422 -122.084`. |
| `battery LEVEL\|unplug\|charge\|reset\|status` | Fake battery level / charging. |
| `notifications open\|close\|settings` | Notification shade / quick settings. |
| `permission grant\|revoke PERM [PKG]` · `permission list [PKG]` | Runtime permissions, e.g. `CAMERA`, `ACCESS_FINE_LOCATION`, `POST_NOTIFICATIONS`, `RECORD_AUDIO`. |
| `locale TAG\|reset\|status [PKG]` | Per-app language (`ar`, `fr-FR`, `ja`); reopen the app (`open`) to apply. |
| `info` | Device summary: model, API, screen, theme, battery, network, app locale. |

`PKG` defaults to `APP_PACKAGE` (Expo Go, `host.exp.exponent`).

## App control and debugging

| Command | What it does |
|---------|--------------|
| `app launch\|stop\|restart [PKG]` | Start / force-stop / restart (Expo Go restart reopens the project). |
| `app clear [PKG]` | Wipe app data; for Expo Go also reopens the project. |
| `app install FILE.apk` · `app uninstall PKG` · `app list` · `app info [PKG]` | Manage APKs. |
| `logcat [--errors\|--all] [-n N] [--follow] [--clear]` | Default: JS + React Native + Expo logs. `--errors`: all errors. |
| `crash [-n N] [--clear]` | Crash log buffer. |
| `perf [--reset]` | Frame stats: jank %, 50/90/95/99th percentile. `--reset`, interact, then `perf`. |
| `memory` | PSS/RSS, Java and native heap (MB). |
| `reload` | Reload the JS bundle. |
| `devmenu` | Open the React Native dev menu. |
| `open-url URL` | Open a deep link (`myapp://path` or `exp://…`). |
| `adb ARGS…` | Raw adb against the target device. |

## Maintenance

| Command | What it does |
|---------|--------------|
| `check-versions [--verify-sync]` | Compare pinned tool versions with upstream. |
| `help` · `--version` | Usage / version. |

## Configuration

Settings file: `~/.expoemu/config.env` (git clone: repo `.env`). Useful keys:
`APP_PACKAGE` (target app, default Expo Go), `AVD_RAM_MB`, `AVD_CORES`,
`EMULATOR_GPU` (`host` or `swiftshader_indirect`), `CONTAINER_RUNTIME`
(`docker` or `kiri`), `METRO_PORT` (8081), `ADB_SERVER_PORT` (5037),
`SCREENSHOT_DIR` (`.android-screenshots`). Environment variables with the
same names override the file for one command.
