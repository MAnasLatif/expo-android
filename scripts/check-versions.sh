#!/usr/bin/env bash
# =============================================================================
# Maintainer helper for dependency updates.
#
#   scripts/check-versions.sh                 show pinned vs latest upstream versions
#   scripts/check-versions.sh --verify-sync   fail if Dockerfile / compose defaults
#                                             drift from config/versions.env (CI)
#
# Needs only curl, grep, sed and perl (all built into macOS and CI runners).
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
set -a
# shellcheck source=../config/versions.env
source "$VERSIONS_FILE"
set +a

# --- Mode 1: consistency check ---------------------------------------------------
if [ "${1:-}" = "--verify-sync" ]; then
  bad=0
  for key in UBUNTU_VERSION JDK_VERSION NODE_VERSION BUN_VERSION CMDLINE_TOOLS_BUILD \
             CMDLINE_TOOLS_LINUX_SHA1 PLATFORM_TOOLS_VERSION PLATFORM_TOOLS_LINUX_SHA1; do
    want="${!key}"
    grep -qE "^ARG ${key}=${want}\$" "$REPO_ROOT/Dockerfile" \
      || { echo "Dockerfile: ARG ${key} default != ${want}" >&2; bad=1; }
    grep -qF "\${${key}:-${want}}" "$COMPOSE_FILE" \
      || { echo "docker-compose.yml: ${key} default != ${want}" >&2; bad=1; }
  done
  [ "$bad" = 0 ] && ok "Dockerfile and docker-compose.yml match config/versions.env"
  exit "$bad"
fi

# --- Mode 2: report latest upstream releases ----------------------------------------
REPO_XML="$(curl -fsSL https://dl.google.com/android/repository/repository2-3.xml | tr -d '\n')"
IMG_XML="$(curl -fsSL "https://dl.google.com/android/repository/sys-img/${SYSTEM_IMAGE_TAG}/sys-img2-3.xml" | tr -d '\n')"

# Highest number captured by a regex with one group.
latest() { grep -oE "$1" | sed -E "s/$1/\\1/" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1; }
# SHA-1 listed right before an archive URL in Google's repository XML.
sha1_of() {
  perl -ne 'print "$1\n" if /<checksum type="sha1">([0-9a-f]{40})<\/checksum>\s*<url>\Q'"$2"'\E<\/url>/' <<<"$1" | head -1
}
row() { printf '  %-26s pinned %-14s latest %s\n' "$1" "$2" "$3"; }

pt="$(latest 'platform-tools_r([0-9.]+)-darwin\.zip' <<<"$REPO_XML")"
emu="$(latest 'emulator-darwin_x64-([0-9]+)\.zip' <<<"$REPO_XML")"
clt="$(latest 'commandlinetools-linux-([0-9]+)_latest\.zip' <<<"$REPO_XML")"
img="$(latest "x86_64-${SYSTEM_IMAGE_API}_r([0-9]+)\.zip" <<<"$IMG_XML")"
node="$(curl -fsSL https://nodejs.org/dist/index.json | grep -oE '"version":"v24\.[0-9.]+"' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
bun="$(curl -fsSI https://github.com/oven-sh/bun/releases/latest | tr -d '\r' | sed -nE 's#^location: .*/bun-v([0-9.]+)$#\1#Ip')"

echo "Versions (config/versions.env vs upstream):"
row "Node.js (24 LTS)" "$NODE_VERSION" "$node"
row "Bun" "$BUN_VERSION" "$bun"
row "cmdline-tools (linux)" "$CMDLINE_TOOLS_BUILD" "$clt"
row "platform-tools" "$PLATFORM_TOOLS_VERSION" "$pt"
row "emulator" "$EMULATOR_BUILD" "$emu"
row "system image API $SYSTEM_IMAGE_API" "r$SYSTEM_IMAGE_REVISION" "r$img"

echo
echo "Checksums for the latest releases (paste into config/versions.env):"
echo "  CMDLINE_TOOLS_LINUX_SHA1=$(sha1_of "$REPO_XML" "commandlinetools-linux-${clt}_latest.zip")"
echo "  PLATFORM_TOOLS_LINUX_SHA1=$(sha1_of "$REPO_XML" "platform-tools_r${pt}-linux.zip")"
echo "  PLATFORM_TOOLS_DARWIN_SHA1=$(sha1_of "$REPO_XML" "platform-tools_r${pt}-darwin.zip")"
echo "  EMULATOR_DARWIN_X64_SHA1=$(sha1_of "$REPO_XML" "emulator-darwin_x64-${emu}.zip")"
echo "  EMULATOR_DARWIN_AARCH64_SHA1=$(sha1_of "$REPO_XML" "emulator-darwin_aarch64-${emu}.zip")"
echo "  SYSTEM_IMAGE_X86_64_SHA1=$(sha1_of "$IMG_XML" "x86_64-${SYSTEM_IMAGE_API}_r${img}.zip")"
echo "  SYSTEM_IMAGE_ARM64_SHA1=$(sha1_of "$IMG_XML" "arm64-v8a-${SYSTEM_IMAGE_API}_r${img}.zip")"
