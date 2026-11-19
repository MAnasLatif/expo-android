# expoemu — daily growth & improvement playbook

Read by the scheduled daily agent at the start of every run. Owner: M Anas Latif.

## Goal
More real users and GitHub stars for expoemu by (1) making the tool better and
(2) reaching people who actually have the problem it solves. Stars follow users.

## Who has this problem (search for them)
- Expo / React Native devs on macOS who want an Android emulator without Android Studio
- People fighting Android SDK / Java / Gradle setup on Mac just to test Expo Go
- Devs using Claude Code / Cursor / Codex who want the agent to run, tap and screenshot their app
- Teams wanting cheap mobile UI tests (flows, visual diffs) without Detox/Maestro setup

Search terms: "expo android emulator mac without android studio", "expo go emulator
apple silicon", "android emulator docker mac expo", "claude code test react native app",
"AI agent android emulator screenshot", "maestro alternative expo".
Places: GitHub issues/discussions in expo/expo, react-native-community, r/reactnative,
r/expo, Stack Overflow [expo]+[android-emulator], dev.to, Hacker News. (Expo Discord: Anas manually.)

## Hard rules
- NEVER post, comment, or open PRs outside MAnasLatif/expoemu. Draft replies for Anas instead.
- Drafted replies must answer the person's actual question first; mention expoemu only
  when it genuinely fits, and disclose "I built this". No copy-paste spam, max 3 per day.
  Only threads from the last ~30 days that are still unresolved.
- No star-for-star, no asking for stars in other people's threads (GitHub ToS + reputation).
- Code changes: always on a branch `agent/<yyyymmdd>-<slug>` + PR to main. Never push to main.
  Run `npm test` before opening a PR. One focused PR per day max. Don't touch release/version files.
- Never publish to npm or create releases. Anas merges and releases.

## Backlog (agent keeps this updated; top = next)
1. Demo GIF/video at the top of README (needs Anas to record on a Mac — draft the shot list)
2. README hero: 1-line pain statement + "Why not Android Studio / Expo Orbit / Maestro?" table
3. Launch kit drafts: Show HN, r/reactnative, r/expo, dev.to article, X/LinkedIn thread
4. Awesome lists (awesome-react-native, awesome-expo, awesome-claude-code, awesome-mcp) — draft PR text for Anas
5. `good first issue` labels + 3–5 small issues so contributors can join
6. Wider audience: Expo dev builds (not only Expo Go), Linux host investigation
7. MCP server wrapper so agents find expoemu through MCP directories
