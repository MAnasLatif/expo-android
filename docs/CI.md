# Running expoemu in CI (headless)

expoemu's flows (`expoemu run`) and visual checks (`expoemu compare`) produce
exit codes and JUnit reports, so they fit any CI system. The one hard
requirement is a **Mac that can run the Android Emulator with hardware
acceleration** (Hypervisor.framework).

## Where it works

| Runner | Works? | Why |
|--------|--------|-----|
| **Self-hosted Mac** (Mac mini, spare MacBook, Mac in the cloud with nested virtualization) | ✅ Recommended | Same as your own machine |
| **Your Mac before pushing** (`expoemu run`) | ✅ | No CI needed at all |
| GitHub-hosted macOS runners (`macos-*`) | ❌ | GitHub documents that nested virtualization isn't supported on its macOS runners, so the emulator gets no acceleration |
| Linux runners with KVM | ❌ for now | expoemu's emulator side is macOS-only. Linux host support is a welcome contribution. |

## Self-hosted Mac runner: example workflow

1. On the Mac: install Docker Desktop and Node.js, and
   [add it as a self-hosted runner](https://docs.github.com/actions/hosting-your-own-runners)
   with the label `expoemu`.
2. In your Expo app's repo, add `.github/workflows/android-flows.yml`:

```yaml
name: Android flows

on:
  pull_request:
  workflow_dispatch:

jobs:
  flows:
    runs-on: [self-hosted, macOS, expoemu]
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      # Idempotent: a few seconds once the SDK, AVD and image exist on the runner.
      - name: Set up expoemu
        run: npx -y expoemu setup --accept-licenses --no-global

      - name: Start emulator, Metro and the app (no window)
        run: npx -y expoemu up --headless --no-animations

      - name: Run flows
        run: npx -y expoemu run --report test-results

      - name: Upload screenshots and reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: expoemu-results
          path: |
            test-results/
            .android-screenshots/

      - name: Stop everything
        if: always()
        run: npx -y expoemu down
```

- `--accept-licenses` accepts the Android SDK license non-interactively. Make
  sure your organisation is fine with that.
- `test-results/junit.xml` works with any JUnit reporter action, so failed
  steps show up in the pull request.
- On failure the job fails (exit code 1). The artifact contains the failure
  screenshot and error log of every failed flow.
- Pin a version for reproducible runs: `npx -y expoemu@0.5.0 …`, or add
  `expoemu` to devDependencies.

## Headless mode

- `expoemu up --headless` (or `expoemu emulator start --headless`) runs the
  emulator without a window. Screenshots, taps and UI dumps work the same.
- To make it the default on a machine, set `EMULATOR_HEADLESS=true` in
  `~/.expoemu/config.env`.

## Making CI runs reliable

- **Animations off:** use `up --no-animations`, so screenshots don't capture
  half-finished transitions.
- **Generous timeouts:** the first bundle on a cold runner can take a minute,
  so start flows with `wait-for "…" --timeout 60`.
- **One device per job,** unless you test multi-device flows on purpose.
  Each emulator needs 2–4 GB of RAM.
- **Visual baselines per device:** compare against baselines made on the same
  device profile. Mask clocks, animations and Expo Go's "Tools" tooltip with
  `--mask`.
- **Update notice:** off automatically in CI (`CI` is set). Logs stay clean.
- **Clean state:** add `app clear` at the start of flows that need a fresh
  install (it wipes storage and reopens the project).
