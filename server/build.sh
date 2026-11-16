#!/usr/bin/env bash
# =============================================================================
# Build the expoemu UI server APK -> server/dist/expoemu-server.apk
#
# No Gradle: aapt2 -> javac -> d8 -> zipalign -> apksigner, with the versions
# pinned in config/versions.env. Needs a JDK 17 and an Android SDK with
# sdkmanager (ANDROID_HOME). Without them it builds inside the expoemu
# Docker image (`expoemu:local`, made by `expoemu start`), keeping the
# build SDK in ~/.expoemu/server-sdk.
#
# The APK is signed with server/expoemu-debug.keystore. That key is public on
# purpose (like Android's debug key): every build gets the same signature, so
# a new APK installs over an old one. It only signs this test helper.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=/dev/null
source "$ROOT/config/versions.env"

sdkmanager_bin() {
  local d
  for d in "${ANDROID_HOME:-}/cmdline-tools/latest/bin" "${ANDROID_SDK_ROOT:-}/cmdline-tools/latest/bin"; do
    [ -x "$d/sdkmanager" ] && { echo "$d/sdkmanager"; return 0; }
  done
  command -v sdkmanager 2>/dev/null
}

# --- No local toolchain: build inside Docker ---------------------------------
if [ "${EXPOEMU_IN_DOCKER_BUILD:-}" != 1 ] && { ! command -v javac >/dev/null 2>&1 || [ -z "$(sdkmanager_bin)" ]; }; then
  command -v docker >/dev/null 2>&1 || { echo "build.sh: needs a JDK + Android SDK, or Docker" >&2; exit 1; }
  docker image inspect expoemu:local >/dev/null 2>&1 \
    || { echo "build.sh: image expoemu:local missing — run 'expoemu start' (or scripts/start.sh) once" >&2; exit 1; }
  cache="${EXPOEMU_HOME:-$HOME/.expoemu}/server-sdk"
  mkdir -p "$cache"
  exec docker run --rm --entrypoint bash \
    --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e EXPOEMU_IN_DOCKER_BUILD=1 -e BUILD_SDK=/build-sdk \
    -v "$ROOT:/src" -v "$cache:/build-sdk" \
    expoemu:local /src/server/build.sh
fi

# --- Toolchain -----------------------------------------------------------------
SDK="${BUILD_SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}}"
[ -n "$SDK" ] || { echo "build.sh: set ANDROID_HOME" >&2; exit 1; }
BT="$SDK/build-tools/$SERVER_BUILD_TOOLS"
JAR="$SDK/platforms/$SERVER_PLATFORM/android.jar"
if [ ! -x "$BT/aapt2" ] || [ ! -f "$JAR" ]; then
  echo "==> Installing build-tools $SERVER_BUILD_TOOLS and $SERVER_PLATFORM into $SDK"
  sm="$(sdkmanager_bin)"
  yes 2>/dev/null | "$sm" --sdk_root="$SDK" --licenses >/dev/null || true
  "$sm" --sdk_root="$SDK" "build-tools;$SERVER_BUILD_TOOLS" "platforms;$SERVER_PLATFORM" >/dev/null
fi

# --- Version: hash of the sources, so any change reinstalls on devices -------
VERSION="$(cat "$HERE/AndroidManifest.xml" "$HERE"/src/dev/expoemu/server/*.java | sha1sum | cut -c1-12)"

OUT="$HERE/dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT" "$WORK/classes" "$WORK/dex"

echo "==> Building expoemu UI server $VERSION"
"$BT/aapt2" link -o "$WORK/base.apk" -I "$JAR" \
  --manifest "$HERE/AndroidManifest.xml" \
  --min-sdk-version 24 --target-sdk-version 36 \
  --version-code 1 --version-name "$VERSION"
javac -nowarn --release 11 -classpath "$JAR" -d "$WORK/classes" \
  $(find "$HERE/src" -name '*.java')
"$BT/d8" --release --min-api 24 --lib "$JAR" --output "$WORK/dex" \
  $(find "$WORK/classes" -name '*.class')
( cd "$WORK/dex" && jar uf "$WORK/base.apk" classes.dex )
"$BT/zipalign" -f -p 4 "$WORK/base.apk" "$WORK/aligned.apk"
"$BT/apksigner" sign --ks "$HERE/expoemu-debug.keystore" \
  --ks-pass pass:android --key-pass pass:android --ks-key-alias expoemu \
  --out "$OUT/expoemu-server.apk" "$WORK/aligned.apk"
rm -f "$OUT/expoemu-server.apk.idsig"
printf '%s\n' "$VERSION" > "$OUT/version.txt"
echo "==> $OUT/expoemu-server.apk ($(wc -c < "$OUT/expoemu-server.apk" | tr -d ' ') bytes)"
