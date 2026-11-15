# Using the Android environment from an AI coding agent

This guide is for AI coding agents (Claude Code, Codex, Cursor, Aider, …) and
the people who use them. Everything is a plain shell command run from the
project terminal. The repo installs no plugin or MCP server and changes no
agent configuration.

> **Tip for users:** copy the "Snippet for your project" section below into your
> Expo project's `CLAUDE.md` / `AGENTS.md`, replacing `$EAE` with the absolute
> path to your clone of this repository.

## Prerequisites (done once by a human)

```bash
scripts/setup.sh --project /path/to/expo-app   # SDK, AVD, Docker image
```

## Snippet for your project

````markdown
## Android testing (expo-android-environment)

The Android tools live in `$EAE` (e.g. `~/tools/expo-android-environment`).
Run these from this project's root:

| Goal | Command |
|------|---------|
| Check what is running | `$EAE/scripts/status.sh` |
| Boot the phone | `$EAE/scripts/emulator-start.sh --no-animations` |
| Start the container | `$EAE/scripts/start.sh "$PWD"` |
| Start Metro (non-blocking) | `$EAE/scripts/expo.sh --background` |
| Open app in Expo Go | `$EAE/scripts/open-app.sh` |
| Screenshot (prints path) | `$EAE/scripts/screenshot.sh <name>` |
| List on-screen elements | `$EAE/scripts/device.sh ui` |
| Tap by visible text | `$EAE/scripts/device.sh tap-text "Login"` |
| Tap / swipe / scroll | `$EAE/scripts/device.sh tap X Y` · `swipe X1 Y1 X2 Y2` · `scroll down` |
| Type text | `$EAE/scripts/device.sh text "hello"` |
| Back / Home | `$EAE/scripts/device.sh back` · `home` |
| JS logs / errors | `$EAE/scripts/device.sh logcat` · `logcat --errors` |
| Metro logs | `$EAE/scripts/expo.sh --logs` |
| Reload JS | `$EAE/scripts/device.sh reload` |
| Run a command in the container | `$EAE/scripts/shell.sh bun add <pkg>` |

Screenshots are saved to `./.android-screenshots/` (latest one is always
`./.android-screenshots/latest.png`). Read the PNG to inspect the UI.
Install packages through `$EAE/scripts/shell.sh bun add …` so Linux
`node_modules` stay in sync inside the container.
````

## Recommended verification loop

1. `scripts/status.sh`. If it exits non-zero, follow the hints it prints.
2. Make the code change. Fast Refresh applies it automatically.
3. `scripts/device.sh logcat --errors -n 50` and `scripts/expo.sh --logs`.
   Check for red-box errors or bundling failures.
4. `scripts/screenshot.sh after-change`, then read the printed PNG path.
5. To navigate, run `scripts/device.sh ui`. It prints the tap point for every
   element:

   ```text
   # centerX centerY | text | content-desc | resource-id | class | clickable
   540 1210 | Sign in |  |  | android.widget.TextView | clickable
   ```

   Then use `scripts/device.sh tap 540 1210` or `scripts/device.sh tap-text "Sign in"`.
6. Repeat screenshot → inspect → interact until the flow is verified.

## Notes

- Coordinates are **device pixels** (default 1080 × 2400). Screenshots are
  the same size, so pixel positions in a screenshot can be tapped directly.
- `--no-animations` on `emulator-start.sh` makes screenshots deterministic.
- If the app shows a red error screen, `scripts/device.sh logcat` has the
  JavaScript stack under the `ReactNativeJS` tag.
- `scripts/device.sh adb …` runs any raw adb command against the emulator
  through the isolated adb, with the right server port. Use it instead of a
  global `adb`, which may not exist.
