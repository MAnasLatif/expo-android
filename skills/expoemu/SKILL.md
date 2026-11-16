---
name: expoemu
description: Runs and tests Expo / React Native apps on a real Android emulator on macOS with the expoemu CLI (npx expoemu). Boots the emulator, starts Metro in Docker, opens the app in Expo Go, then drives it with screenshots, UI inspection, taps by text or testID, typing, scrolling, waits and assertions, logs, crashes and performance. Also changes device state (dark mode, offline, rotation, permissions, language) and runs several devices at once. Use when the user asks to run, test, verify, debug or screenshot an Expo app on Android, check a UI change on a phone or tablet, reproduce an Android bug, or mentions expoemu.
license: MIT
compatibility: macOS (Intel or Apple Silicon) with Docker Desktop or Kiri, Node.js 18+, and an Expo project that runs in Expo Go.
allowed-tools: Bash(npx expoemu:*) Bash(npx -y expoemu:*) Bash(expoemu:*) Read
metadata:
  author: MAnasLatif
  version: "1.0.0"
  homepage: https://github.com/MAnasLatif/expoemu
---

# expoemu: test Expo apps on a real Android emulator

`expoemu` (Expo Emulator) runs the user's Expo app on a native Android emulator
on macOS. The toolchain (Node, Bun, Expo CLI, Metro, adb client) lives in
Docker; the emulator runs natively; nothing is installed into the project.
Every action is a terminal command, so you can see the screen, interact and
verify results yourself.

## Ground rules

- Run every command **from the Expo project root**. The current folder decides
  which project is tested.
- Use `npx expoemu <command>`. If `npx` asks to install, use `npx -y expoemu …`.
  If the project has `expoemu` in devDependencies, plain `npx expoemu` is pinned.
- Exit codes matter. `0` is success. `1` means failure and a ✗ line on stderr
  says why. Read it before retrying.
- Never use a global `adb`. Use `npx expoemu adb …` (isolated SDK, right port).
- Install packages **inside the container** with the project's package manager:
  `npx expoemu shell npm install <pkg>` (or yarn / pnpm / bun to match the lockfile).
- Ask the user before `setup` (it accepts the Android SDK license and downloads
  about 8 GB), before any `cleanup`, and before `device delete`.

## Workflow

Copy this checklist and tick it off:

```
- [ ] 1. npx expoemu status          → understand what is running
- [ ] 2. npx expoemu up --no-animations   (if anything is down)
- [ ] 3. Inspect: screenshot + ui
- [ ] 4. Act: tap-text / fill / scroll-to …
- [ ] 5. Verify: wait-for / assert-text / screenshot / logcat --errors
- [ ] 6. Reset any device state you changed
```

**1. Check.** Run `npx expoemu status`. Exit `0` means everything is ready. Otherwise
follow the hints it prints. If the isolated SDK is missing, setup has never run:
ask the user, then run `npx expoemu setup --accept-licenses` (about 10 min, once per Mac).

**2. Start.** Run `npx expoemu up --no-animations`. It boots the phone, starts the
container and Metro, and opens the app in Expo Go (about 30 s after the first
boot). `--no-animations` keeps screenshots stable.

**3. Inspect the screen.**

```bash
npx expoemu screenshot home     # prints an absolute PNG path, so Read it to see the screen
npx expoemu ui                  # every element: "centerX centerY | text | label | testID | class | flags"
npx expoemu texts               # just the visible strings
```

**4. Act.** Prefer selectors over pixel coordinates:

```bash
npx expoemu tap-text "Sign in"            # text, accessibilityLabel, testID or placeholder
npx expoemu fill "Email" "ada@example.com" # tap field, clear, type, hide keyboard
npx expoemu fill password-input "secret"  # by testID
npx expoemu scroll-to "Privacy policy"    # scrolls until visible
npx expoemu tap 540 1210                  # pixels from `ui` / the screenshot
npx expoemu back
```

**5. Verify.** Never assume an action worked:

```bash
npx expoemu wait-for "Welcome" --timeout 20   # exit 0 when it appears
npx expoemu assert-no-text "Invalid password"
npx expoemu logcat --errors -n 50            # native + JS errors
npx expoemu expo --logs                      # Metro / bundling errors
npx expoemu screenshot after-login
```

After editing code, Fast Refresh updates the app in about 2–5 s. Then
`wait-for` the change, or `npx expoemu open` (fresh reload) if the screen shows old code.

**6. Clean up.** Undo state you changed (`network on`, `dark-mode off`,
`font-scale reset`, `locale reset`, `rotate portrait`). Leave the emulator
running unless the user asks to stop. `npx expoemu down` stops everything.

## Selectors

`"Text"` arguments match, case-insensitively, the visible text, the
`accessibilityLabel`, the React Native `testID`, and an empty TextInput's
`placeholder`. An exact match wins over a partial one. If nothing matches, run
`npx expoemu ui` and use what it shows. When you write app code, add a `testID`
to important elements. It is the most stable selector.

## Key facts and gotchas

- **Coordinates** are device pixels (default phone 1080×2400). Screenshots are
  the same size, so a pixel in a screenshot can be tapped directly.
- **Keyboard**: `fill`, `tap-text` and `scroll` hide the on-screen keyboard
  first. Before a raw `swipe`, run `npx expoemu hide-keyboard`, because a swipe
  over the keyboard types text.
- **Offline testing**: `npx expoemu network off` cuts the app's internet, but
  Metro keeps working over adb.
- **Fresh state**: `npx expoemu app clear` wipes storage (AsyncStorage,
  SecureStore, permissions) and reopens the project.
- **Rotation** has no effect if `app.json` locks `"orientation"`.
- **Red error screen**: the stack trace is in `npx expoemu logcat` (tag `ReactNativeJS`).
- **Several devices**: commands go to the default phone unless you add
  `--device NAME`. For `adb`, `shell` and `expo`, put `--device` before the
  command: `npx expoemu --device tablet adb shell …`.

## Several devices at once

```bash
npx expoemu devices                                  # created devices + running state
npx expoemu device create tablet --profile tablet    # phone|small|large|tablet|foldable
npx expoemu emulator start --device tablet           # runs next to the phone
npx expoemu open --all                               # app on every running device
npx expoemu tap-text "Send" --device tablet
npx expoemu screenshot --all                         # one PNG per device
```

Each device costs about 2–4 GB of RAM while running. Three devices fit a 32 GB Mac.

## References

- Every command and flag: [references/commands.md](references/commands.md)
- Recipes (login flow, offline, dark mode, permissions, deep links,
  performance, multi-device chat): [references/workflows.md](references/workflows.md)
- Problems and fixes: [references/troubleshooting.md](references/troubleshooting.md)
