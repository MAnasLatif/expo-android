# Using expoemu from an AI coding assistant

This guide is for AI coding assistants (Claude Code, Codex, Cursor, Aider, …)
and the people who use them. Everything is a plain `npx expoemu …` command run
from the Expo project folder. expoemu installs no plugin or MCP server and
changes no assistant configuration.

> **Recommended: install the skill.** `npx skills add MAnasLatif/expoemu` puts
> the [expoemu Agent Skill](../skills/expoemu/SKILL.md) into your project for
> Claude Code, Cursor, Codex, Copilot and others. Then add one line to
> `AGENTS.md` / `CLAUDE.md`: *"Use the `expoemu` skill to run, test and debug
> this app on Android."* The skill contains everything below and more.
>
> **Without the skill:** copy the "Snippet for your project" section below into
> your Expo project's `CLAUDE.md` / `AGENTS.md`. Adding expoemu as a
> devDependency (`npm i -D expoemu`) pins the version, and `npx` won't ask to install.

## Prerequisites (done once by a human)

```bash
cd /path/to/expo-app
npx expoemu setup        # isolated Android SDK, Pixel AVD, Docker image
```

## Snippet for your project

````markdown
## Android testing (expoemu)

Run from this project's root. `"Text"` selectors match visible text,
accessibilityLabel, testID or placeholder (exact match preferred).
Waits and asserts exit 0 on success and 1 on failure.

| Goal | Command |
|------|---------|
| Is everything running? | `npx expoemu status` (exit 0 = all good) |
| Start / stop everything | `npx expoemu up --no-animations` · `npx expoemu down` |
| Screenshot (prints path) | `npx expoemu screenshot <name>` |
| What's on screen | `npx expoemu ui` (tap coordinates) · `npx expoemu texts` |
| Tap | `npx expoemu tap-text "Login"` · `npx expoemu tap X Y` · `double-tap` · `long-press-text "Item"` |
| Fill a form field | `npx expoemu fill "Email" "me@example.com"` (or by testID: `fill email-input "…"`) |
| Scroll | `npx expoemu scroll down` · `npx expoemu scroll-to "Settings"` |
| Keys | `npx expoemu back` · `enter` · `key TAB` · `hide-keyboard` |
| Wait for UI | `npx expoemu wait-for "Welcome" --timeout 20` · `wait-gone "Loading"` |
| Verify | `npx expoemu assert-text "Welcome"` · `assert-no-text "Error"` |
| Logs / crashes | `npx expoemu logcat --errors -n 50` · `npx expoemu crash` · `npx expoemu expo --logs` |
| Fresh state | `npx expoemu app clear` (wipes storage, reopens the project) |
| Edge cases | `npx expoemu network off` · `dark-mode on` · `font-scale 1.3` · `rotate landscape` · `locale ar` |
| Permissions | `npx expoemu permission grant CAMERA` · `permission revoke CAMERA` |
| Several devices | `npx expoemu devices` · `npx expoemu emulator start --device tablet` · add `--device NAME` to any command · `open --all` · `screenshot --all` |
| Performance | `npx expoemu perf --reset` → interact → `npx expoemu perf` · `npx expoemu memory` |
| Reload / reopen | `npx expoemu reload` · `npx expoemu open` |
| Add a package | `npx expoemu shell npm install <pkg>` (or yarn / pnpm / bun, matching the project) |

Screenshots and recordings go to `./.android-screenshots/`, and
`latest.png` is always the newest screenshot. Read the PNG to inspect the UI.
Reset any state you change, e.g. `network on`, `dark-mode off`,
`font-scale reset`, `locale reset`.
````

## Recommended verification loop

1. `npx expoemu status`. If it exits non-zero, run `npx expoemu up` or follow
   the hints it prints.
2. Make the code change. Fast Refresh applies it within seconds.
3. Check for errors: `npx expoemu logcat --errors -n 50`,
   `npx expoemu expo --logs` and `npx expoemu crash`.
4. Drive the flow with selectors rather than coordinates when possible:

   ```bash
   npx expoemu fill "Email" "ada@example.com"
   npx expoemu fill "Password" "hunter2"
   npx expoemu tap-text "Sign in"
   npx expoemu wait-for "Welcome" --timeout 20
   npx expoemu assert-no-text "Invalid password"
   npx expoemu screenshot after-login
   ```

5. If a selector doesn't match, run `npx expoemu ui` to see exactly what's on
   screen (text, accessibility label, testID, flags) and the tap point for
   each element.
6. Give important elements a `testID`. It's the most stable selector.

## Notes

- With several devices running, every command uses the default phone
  unless you add `--device NAME` (see `npx expoemu devices`). Coordinates
  differ per device: use `ui --device NAME` for that device.
- Coordinates are **device pixels** (default 1080 × 2400). Screenshots are
  the same size, so pixel positions in a screenshot can be tapped directly.
- `fill`, `tap-text` and `scroll` hide the on-screen keyboard first. This
  stops a swipe from becoming keyboard "glide typing" and a tap from landing
  on a key.
- `--no-animations` on `up` (or `npx expoemu animations off`) makes
  screenshots deterministic.
- If the screen shows old code, run `npx expoemu open`. It restarts Expo Go and
  loads a fresh bundle.
- `network off` takes the *app* offline, but Metro keeps working because it
  runs over adb. Use it to test offline behaviour live.
- `npx expoemu adb …` runs any raw adb command against the emulator with the
  isolated adb and the right server port.
