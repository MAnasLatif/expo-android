# expoemu troubleshooting

Start with `npx expoemu status`. It checks every link and prints a hint for
each failure. Find the symptom below.

## Contents

- [Setup and environment](#setup-and-environment)
- [Emulator](#emulator)
- [App and Metro](#app-and-metro)
- [Interaction](#interaction)
- [Several devices](#several-devices)

## Setup and environment

| Symptom | Fix |
|---------|-----|
| `Isolated SDK not installed` / `AVD … not found` | Setup never ran. Ask the user, then `npx expoemu setup --accept-licenses` (~10 min). |
| `Refusing … non-interactive shell (add --accept-licenses)` | Same as above: the Android SDK license needs explicit acceptance. |
| `Docker is not running` | Ask the user to start Docker Desktop (or Kiri if `CONTAINER_RUNTIME=kiri`). |
| `The emulator side … supports macOS only` | expoemu needs a Mac. There is no workaround on Linux or Windows. |
| `Dependency install failed (npm)` | The project's lockfile doesn't install cleanly (e.g. a `file:` dependency outside the project). Fix the project, then `npx expoemu start`. |

## Emulator

| Symptom | Fix |
|---------|-----|
| `Emulator exited during boot` | Read `~/.expoemu/logs/emulator-<device>.log`. Try `npx expoemu emulator start --cold-boot`. If the GPU fails, set `EMULATOR_GPU=swiftshader_indirect`. |
| Timed out waiting for boot | First boot takes 2–3 min. Retry. Low RAM? Stop other devices. |
| Screen locked / taps do nothing | `npx expoemu unlock` |
| `No running emulator` | `npx expoemu emulator start` or `npx expoemu up` |

## App and Metro

| Symptom | Fix |
|---------|-----|
| Screen shows old code | `npx expoemu open` (force-stops Expo Go and loads a fresh bundle). |
| Changes don't appear (Fast Refresh) | `npx expoemu expo --logs`. A syntax error stops bundling. Fix it and the app updates. |
| "Could not connect to development server" | `npx expoemu expo --background`, then `npx expoemu open`. |
| Red error screen | `npx expoemu logcat -n 100` (JS stack), fix the code, `npx expoemu reload`. |
| App closes / crashes | `npx expoemu crash`, `npx expoemu logcat --errors -n 100`. |
| "This is the developer menu" covers the app | Expo Go's one-time intro: `npx expoemu tap-text Continue` then `npx expoemu tap-text Close`. `open` normally does this. |
| Native module missing in Expo Go | The library needs a development build, so it can't run in Expo Go. Tell the user. |

## Interaction

| Symptom | Fix |
|---------|-----|
| `No element matching: X` | `npx expoemu ui` shows what is really on screen. Match text, label, testID or placeholder. Content may be off-screen: `scroll-to "X"`. It may still be loading: `wait-for "X"`. |
| Tap hits the wrong element | Use the exact text, or a testID. Tap coordinates from `ui`. |
| Random words appear in a field | A swipe crossed the keyboard. Run `hide-keyboard` before raw `swipe`. |
| `scroll` doesn't move | The list may be horizontal (`scroll left\|right`) or not scrollable. Use `swipe` inside it. |
| `rotate` has no effect | The app is locked by `app.json` `"orientation"`. |
| `locale` change not visible | Reopen the app: `npx expoemu open`. |
| `permission grant` fails | Only runtime permissions that the app declares can be granted. |

## Several devices

| Symptom | Fix |
|---------|-----|
| Command acted on the wrong device | Add `--device NAME`. Without it the default phone is used. |
| `Device 'X' is not running` | `npx expoemu emulator start --device X` |
| `--device` ignored with adb/shell/expo | Put it before the command: `npx expoemu --device X adb …`. |
| Mac slows down | Each device uses 2–4 GB of RAM. Stop the unused ones: `npx expoemu emulator stop --device X`. |
