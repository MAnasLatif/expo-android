# Contributing

Thanks for helping improve **expo-android**. Contributions of all
sizes are welcome: bug reports, docs, version bumps, new platforms.

## Ground rules

- **Keep the host clean.** Anything installed on macOS must go under
  `$ENV_HOME` (default `~/.expo-android-env`). Never write to `~/.android`,
  `~/Library/Android`, shell profiles or global `PATH`.
- **Cleanup must stay scoped.** Docker resources need the
  `com.expo-android-env.managed=true` label and the `expo-android-env` name
  prefix. Never add a `docker system prune` or anything similar.
- **Pin and verify downloads.** Every archive comes from
  `config/versions.env` with a checksum.
- **Scripts stay POSIX-friendly bash** that runs on macOS's bash 3.2 and
  Linux bash 5. Use BSD-compatible flags such as `sed -i ''` on host-side
  scripts.

## Development setup

```bash
git clone https://github.com/<you>/expo-android.git
cd expo-android
scripts/setup.sh --project /path/to/any/expo-app
```

## Updating dependency versions

All versions live in **`config/versions.env`**.

1. Run `scripts/check-versions.sh`. It prints the latest Android emulator,
   platform-tools, cmdline-tools and system image, with SHA-1 checksums,
   plus the latest Node LTS and Bun.
2. Update `config/versions.env`. **Keep the macOS and Linux platform-tools on
   the same version**, because mismatched adb versions kill each other's server.
3. Mirror the new defaults in the `Dockerfile` `ARG`s and the `build.args`
   in `docker-compose.yml`. CI fails if they drift.
4. Rebuild and test: `scripts/setup.sh`, then follow the manual test plan
   below.
5. Add a line to `CHANGELOG.md` under **Unreleased**.

## Manual test plan (before opening a PR)

```bash
scripts/emulator-start.sh --no-animations
scripts/start.sh /path/to/expo-app
scripts/expo.sh --background
scripts/open-app.sh
scripts/status.sh            # must exit 0
scripts/screenshot.sh test   # PNG shows the app
scripts/device.sh ui         # lists elements
scripts/stop.sh --all
```

Mention which host you tested on (Intel or Apple Silicon, macOS version,
Docker Desktop version) in the PR.

## Linting

CI runs [ShellCheck](https://www.shellcheck.net/) and a Docker build. To run
ShellCheck locally without installing it:

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 -x -S warning \
  scripts/*.sh scripts/lib/*.sh docker/*.sh
```

## Commits and pull requests

- Use small, focused commits with [Conventional Commit](https://www.conventionalcommits.org/)
  prefixes: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`.
- Each PR should do one thing and say how it was tested.
- By contributing you agree that your work is released under the MIT License.

## Good first contributions

- Linux host support for the emulator side (KVM)
- Windows (WSL2) host support
- Development builds (`expo run:android`) using `ANDROID_EXTRA_PACKAGES`
- More `device.sh` helpers (e.g. wait-for-text, rotate, dark mode toggle)
