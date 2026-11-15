# Contributing

Thanks for helping improve **Expo Emulator** (`expoemu`). Contributions of all
sizes are welcome: bug reports, docs, version bumps, new platforms.

## Ground rules

- **Keep the host clean.** Anything installed on macOS must go under
  `$ENV_HOME` (default `~/.expoemu`). Never write to `~/.android`,
  `~/Library/Android`, shell profiles or global `PATH`.
- **Cleanup must stay scoped.** Docker resources need the
  `com.expoemu.managed=true` label and the `expoemu` name
  prefix. Never add a `docker system prune` or anything similar.
- **Pin and verify downloads.** Every archive comes from
  `config/versions.env` with a checksum.
- **Scripts stay POSIX-friendly bash** that runs on macOS's bash 3.2 and
  Linux bash 5. Use BSD-compatible flags such as `sed -i ''` on host-side
  scripts.

## Development setup

```bash
git clone https://github.com/<you>/expoemu.git
cd expoemu
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

## Testing the npm package locally

The CLI (`bin/expoemu.js`) only routes commands to `scripts/`. To test the real
package before a release:

```bash
npm test                                   # CLI unit tests
npm pack                                   # → expoemu-X.Y.Z.tgz
cd /path/to/expo-app
npx --package=/path/to/expoemu-X.Y.Z.tgz expoemu up
```

## Releasing to npm

Maintainers only. Publishing uses **npm Trusted Publishing (OIDC)**: no npm
token or repository secret. npm trusts the
[Release workflow](.github/workflows/release.yml) because the `expoemu`
package has this trusted publisher configured:

| Field | Value |
|-------|-------|
| Publisher | GitHub Actions |
| Organization or user | `MAnasLatif` |
| Repository | `expoemu` |
| Workflow filename | `release.yml` |
| Environment | *(empty)* |

The trusted publisher was set up once, from a maintainer's machine with
npm 11.15+ and 2FA:

```bash
npm trust github expoemu --file release.yml --repository MAnasLatif/expoemu --allow-publish
```

The same is available on npmjs.com → expoemu → Settings → Trusted publishing.
npm only allows this for a package that already exists, so version `0.1.0`
was published once by hand (`npm publish --access public`). Then, under
**Settings → Publishing access**, choose *Require two-factor authentication
and disallow tokens*. Trusted publishing keeps working.

Push a version tag on any commit. The **tag decides the version**, so
`package.json` doesn't need editing:

```bash
git tag v0.1.0 && git push origin v0.1.0               # → expoemu@0.1.0 on npm "latest"
git tag v0.2.0-beta.1 && git push origin v0.2.0-beta.1 # → expoemu@0.2.0-beta.1 on npm "beta"
```

| Tag | npm version | npm dist-tag | Users get it with |
|-----|-------------|--------------|-------------------|
| `v1.2.3` | `1.2.3` | `latest` | `npx expoemu …` |
| `v1.3.0-beta.1` | `1.3.0-beta.1` | `beta` | `npx expoemu@beta …` |
| `v1.3.0-rc.1` / `-alpha.1` / `-next.1` | same | `rc` / `alpha` / `next` | `npx expoemu@rc …` |

The [Release workflow](.github/workflows/release.yml) validates the tag and
runs the tests, ShellCheck and the version sync check. It then publishes
through trusted publishing, which adds
[provenance](https://docs.npmjs.com/generating-provenance-statements)
automatically, and creates a GitHub Release with generated notes and the
tarball. If the version is already on npm, for example `0.1.0` published by
hand or a re-run, it skips the npm step and only creates the missing GitHub
Release. A failed release publishes nothing. Delete the tag (`git push --delete origin vX.Y.Z`),
fix the problem, and tag again.

Before tagging, move the **Unreleased** notes in `CHANGELOG.md` under the new
version and commit.

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
