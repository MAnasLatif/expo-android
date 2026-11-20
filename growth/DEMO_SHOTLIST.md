# Demo GIF — shot list for Anas (backlog #1)

Goal: a 20–30 s GIF at the top of README that shows the whole promise:
"clean Mac → phone running my Expo app → my agent taps & checks it".

## Prep (2 min)
- Terminal: large font (18–20pt), dark theme, window ~1200×750, clear history, short prompt (`PS1='$ '`).
- Run `expoemu setup` beforehand (don't record the 10-min install). Emulator NOT running.
- Use a tiny sample Expo app with a visible text input + button (e.g. a sign-in screen).
- Recorder: Kap or CleanShot X (GIF, 15 fps, ≤ 8 MB). Or `asciinema` for terminal-only + separate emulator clip.

## Shots (side by side: terminal left, emulator right)
1. (0–3 s) `cd my-expo-app && expoemu up` — show the progress lines.
2. (3–10 s) Speed up 4× during boot; phone appears, app opens. Overlay text: "No Android Studio. No Java."
3. (10–16 s) `expoemu fill "Email" "test@example.com"` → `expoemu tap-text "Sign in"`.
4. (16–20 s) `expoemu wait-for "Wrong password"` → green ✓ in terminal.
5. (20–25 s) `expoemu screenshot` → the PNG path; optional cut to Claude Code saying "I checked the error screen ✓".
6. End card (2 s): `npx expoemu setup` + repo URL.

## After recording
- Save as `docs/demo.gif` (or upload to a GitHub issue comment and use the user-images URL to keep the npm package small).
- README: put `![expoemu demo](docs/demo.gif)` right under the badges. The agent can open the PR once the file exists.
