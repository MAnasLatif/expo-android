## What does this change?

<!-- One focused change per PR. -->

## How was it tested?

- [ ] Host: Intel / Apple Silicon, macOS version: …
- [ ] `scripts/status.sh` exits 0 after `emulator-start`, `start`, `expo.sh --background`, `open-app`
- [ ] ShellCheck passes

## Checklist

- [ ] Versions changed only in `config/versions.env` (+ mirrored Dockerfile / compose defaults)
- [ ] Nothing installed outside `ENV_HOME` on the host
- [ ] Cleanup remains limited to labelled `expoemu` resources
- [ ] `CHANGELOG.md` updated under **Unreleased**
- [ ] Docs updated (README / docs/)
