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

Run from this project's root. `"Text"` selectors match visible text,
accessibilityLabel, testID or placeholder (exact match preferred).
Waits and asserts exit 0 on success and 1 on failure.

| Goal | Command |
|------|---------|
| Is everything running? | `npx eaenv status` (exit 0 = all good) |
| Start / stop everything | `npx eaenv up --no-animations` · `npx eaenv down` |
| Screenshot (prints path) | `npx eaenv screenshot <name>` |
| What's on screen | `npx eaenv ui` (tap coordinates) · `npx eaenv texts` |
| Tap | `npx eaenv tap-text "Login"` · `npx eaenv tap X Y` · `double-tap` · `long-press-text "Item"` |
| Fill a form field | `npx eaenv fill "Email" "me@example.com"` (or by testID: `fill email-input "…"`) |
| Scroll | `npx eaenv scroll down` · `npx eaenv scroll-to "Settings"` |
| Keys | `npx eaenv back` · `enter` · `key TAB` · `hide-keyboard` |
| Wait for UI | `npx eaenv wait-for "Welcome" --timeout 20` · `wait-gone "Loading"` |
| Verify | `npx eaenv assert-text "Welcome"` · `assert-no-text "Error"` |
| Logs / crashes | `npx eaenv logcat --errors -n 50` · `npx eaenv crash` · `npx eaenv expo --logs` |
| Fresh state | `npx eaenv app clear` (wipes storage, reopens the project) |
| Edge cases | `npx eaenv network off` · `dark-mode on` · `font-scale 1.3` · `rotate landscape` · `locale ar` |
| Permissions | `npx eaenv permission grant CAMERA` · `permission revoke CAMERA` |
| Performance | `npx eaenv perf --reset` → interact → `npx eaenv perf` · `npx eaenv memory` |
| Reload / reopen | `npx eaenv reload` · `npx eaenv open` |
| Add a package | `npx eaenv shell bun add <pkg>` |

Screenshots and recordings go to `./.android-screenshots/`, and
`latest.png` is always the newest screenshot. Read the PNG to inspect the UI.
Reset any state you change, e.g. `network on`, `dark-mode off`,
`font-scale reset`, `locale reset`.
````

## Recommended verification loop

1. `npx eaenv status`. If it exits non-zero, run `npx eaenv up` or follow
   the hints it prints.
2. Make the code change. Fast Refresh applies it within seconds.
3. Check for errors: `npx eaenv logcat --errors -n 50`,
   `npx eaenv expo --logs` and `npx eaenv crash`.
4. Drive the flow with selectors rather than coordinates when possible:

   ```bash
   npx eaenv fill "Email" "ada@example.com"
   npx eaenv fill "Password" "hunter2"
   npx eaenv tap-text "Sign in"
   npx eaenv wait-for "Welcome" --timeout 20
   npx eaenv assert-no-text "Invalid password"
   npx eaenv screenshot after-login
   ```

5. If a selector doesn't match, run `npx eaenv ui` to see exactly what's on
   screen (text, accessibility label, testID, flags) and the tap point for
   each element.
6. Give important elements a `testID`. It's the most stable selector.

## Notes

- Coordinates are **device pixels** (default 1080 × 2400). Screenshots are
  the same size, so pixel positions in a screenshot can be tapped directly.
- `fill`, `tap-text` and `scroll` hide the on-screen keyboard first. This
  stops a swipe from becoming keyboard "glide typing" and a tap from landing
  on a key.
- `--no-animations` on `up` (or `npx eaenv animations off`) makes
  screenshots deterministic.
- If the screen shows old code, run `npx eaenv open`. It restarts Expo Go and
  loads a fresh bundle.
- `network off` takes the *app* offline, but Metro keeps working because it
  runs over adb. Use it to test offline behaviour live.
- `npx eaenv adb …` runs any raw adb command against the emulator with the
  isolated adb and the right server port.
