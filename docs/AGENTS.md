# Using eaenv from an AI coding assistant

This guide is for AI coding assistants (Claude Code, Codex, Cursor, Aider, …)
and the people who use them. Everything is a plain `npx eaenv …` command run
from the Expo project folder. eaenv installs no plugin or MCP server and
changes no assistant configuration.

> **Tip for users:** copy the "Snippet for your project" section below into your
> Expo project's `CLAUDE.md` / `AGENTS.md`. Adding eaenv as a devDependency
> (`npm i -D eaenv`) pins the version, and `npx` won't ask to install.

## Prerequisites (done once by a human)

```bash
cd /path/to/expo-app
npx eaenv setup        # isolated Android SDK, Pixel AVD, Docker image
```

## Snippet for your project

````markdown
## Android testing (eaenv)

Run these from this project's root. All output paths are absolute.

| Goal | Command |
|------|---------|
| Check what is running | `npx eaenv status` (exit 0 = all good) |
| Start everything | `npx eaenv up --no-animations` |
| Stop everything | `npx eaenv down` |
| Screenshot (prints path) | `npx eaenv screenshot <name>` |
| List on-screen elements | `npx eaenv ui` |
| Tap by visible text | `npx eaenv tap-text "Login"` |
| Tap / swipe / scroll | `npx eaenv tap X Y` · `npx eaenv swipe X1 Y1 X2 Y2` · `npx eaenv scroll down` |
| Type text / keys | `npx eaenv text "hello"` · `npx eaenv key ENTER` · `npx eaenv back` |
| JS logs / errors | `npx eaenv logcat -n 100` · `npx eaenv logcat --errors -n 50` |
| Metro logs | `npx eaenv expo --logs` |
| Reload JS / reopen app | `npx eaenv reload` · `npx eaenv open` |
| Add a package | `npx eaenv shell bun add <pkg>` |

Screenshots are saved to `./.android-screenshots/`, and the latest one is
always `./.android-screenshots/latest.png`. Read the PNG to inspect the UI.
Install packages through `npx eaenv shell …` so the container's Linux
`node_modules` stays in sync.
````

## Recommended verification loop

1. `npx eaenv status`. If it exits non-zero, run `npx eaenv up` or follow
   the hints it prints.
2. Make the code change. Fast Refresh applies it within seconds.
3. `npx eaenv logcat --errors -n 50` and `npx eaenv expo --logs`. Check for
   red-box errors or bundling failures.
4. `npx eaenv screenshot after-change`, then read the printed PNG path.
5. To navigate, run `npx eaenv ui`. It prints the tap point for every element:

   ```text
   # centerX centerY | text | content-desc | resource-id | class | clickable
   540 1210 | Sign in |  |  | android.widget.TextView | clickable
   ```

   Then use `npx eaenv tap 540 1210` or `npx eaenv tap-text "Sign in"`.
6. Repeat screenshot → inspect → interact until the flow is verified.

## Notes

- Coordinates are **device pixels** (default 1080 × 2400). Screenshots are
  the same size, so pixel positions in a screenshot can be tapped directly.
- `--no-animations` on `up` makes screenshots deterministic.
- If the app shows a red error screen, `npx eaenv logcat` has the JavaScript
  stack under the `ReactNativeJS` tag.
- If the screen shows old code, run `npx eaenv open`. It restarts Expo Go and
  loads a fresh bundle.
- `npx eaenv adb …` runs any raw adb command against the emulator with the
  isolated adb and the right server port. Use it instead of a global `adb`,
  which may not exist.
