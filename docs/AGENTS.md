# Using expoemu from an AI coding assistant

This guide is for AI coding assistants (Claude Code, Codex, Cursor, Aider, …)
and the people who use them. Everything is a plain `npx expoemu …` command run
from the Expo project folder. expoemu installs no plugin or MCP server and
changes no assistant configuration.

> **Tip for users:** copy the "Snippet for your project" section below into your
> Expo project's `CLAUDE.md` / `AGENTS.md`. Adding expoemu as a devDependency
> (`npm i -D expoemu`) pins the version, and `npx` won't ask to install.

## Prerequisites (done once by a human)

```bash
cd /path/to/expo-app
npx expoemu setup        # isolated Android SDK, Pixel AVD, Docker image
```

## Snippet for your project

````markdown
## Android testing (expoemu)

Run these from this project's root. All output paths are absolute.

| Goal | Command |
|------|---------|
| Check what is running | `npx expoemu status` (exit 0 = all good) |
| Start everything | `npx expoemu up --no-animations` |
| Stop everything | `npx expoemu down` |
| Screenshot (prints path) | `npx expoemu screenshot <name>` |
| List on-screen elements | `npx expoemu ui` |
| Tap by visible text | `npx expoemu tap-text "Login"` |
| Tap / swipe / scroll | `npx expoemu tap X Y` · `npx expoemu swipe X1 Y1 X2 Y2` · `npx expoemu scroll down` |
| Type text / keys | `npx expoemu text "hello"` · `npx expoemu key ENTER` · `npx expoemu back` |
| JS logs / errors | `npx expoemu logcat -n 100` · `npx expoemu logcat --errors -n 50` |
| Metro logs | `npx expoemu expo --logs` |
| Reload JS / reopen app | `npx expoemu reload` · `npx expoemu open` |
| Add a package | `npx expoemu shell bun add <pkg>` |

Screenshots are saved to `./.android-screenshots/`, and the latest one is
always `./.android-screenshots/latest.png`. Read the PNG to inspect the UI.
Install packages through `npx expoemu shell …` so the container's Linux
`node_modules` stays in sync.
````

## Recommended verification loop

1. `npx expoemu status`. If it exits non-zero, run `npx expoemu up` or follow
   the hints it prints.
2. Make the code change. Fast Refresh applies it within seconds.
3. `npx expoemu logcat --errors -n 50` and `npx expoemu expo --logs`. Check for
   red-box errors or bundling failures.
4. `npx expoemu screenshot after-change`, then read the printed PNG path.
5. To navigate, run `npx expoemu ui`. It prints the tap point for every element:

   ```text
   # centerX centerY | text | content-desc | resource-id | class | clickable
   540 1210 | Sign in |  |  | android.widget.TextView | clickable
   ```

   Then use `npx expoemu tap 540 1210` or `npx expoemu tap-text "Sign in"`.
6. Repeat screenshot → inspect → interact until the flow is verified.

## Notes

- Coordinates are **device pixels** (default 1080 × 2400). Screenshots are
  the same size, so pixel positions in a screenshot can be tapped directly.
- `--no-animations` on `up` makes screenshots deterministic.
- If the app shows a red error screen, `npx expoemu logcat` has the JavaScript
  stack under the `ReactNativeJS` tag.
- If the screen shows old code, run `npx expoemu open`. It restarts Expo Go and
  loads a fresh bundle.
- `npx expoemu adb …` runs any raw adb command against the emulator with the
  isolated adb and the right server port. Use it instead of a global `adb`,
  which may not exist.
