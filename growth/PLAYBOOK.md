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
1. Demo GIF/video at the top of README — NEEDS ANAS. Shot list ready: growth/DEMO_SHOTLIST.md
2. Launch kit drafts: Show HN, r/reactnative, r/expo, dev.to article, X/LinkedIn thread (agent drafts into growth/launch/)
3. `good first issue` labels + 3–5 small issues so contributors can join
4. Awesome lists (awesome-react-native, awesome-expo, awesome-claude-code, awesome-mcp) — draft PR text for Anas
5. Get listed on skills directories (skills.sh, claude-plugins.dev, tessl, smithery) — agents' skills already show up there for "android emulator" searches; expoemu's skill should too
6. MCP server wrapper so agents find expoemu through MCP directories (competitors seen: callstack/agent-device, Android-Ui-MCP, expo-android MCP)
7. Wider audience: Expo dev builds (not only Expo Go), Linux host investigation
- DONE 2026-11-20: README "Why expoemu?" + comparison table → PR #8

## Notes from runs
- Cross-repo GitHub reads are blocked for this scheduled task (403) and WebFetch of github.com issue pages needs approval → thread leads can't be fully verified. Fix: Anas adds read access / approves github.com fetches, or the agent relies on search snippets.
- npm downloads API is blocked from the shell (proxy 403); WebFetch npmjs.com also needs approval.
- Search for live threads works best via `gh api search/issues` with `is:issue is:open created:>DATE` (needs is:issue).
