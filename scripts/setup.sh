#!/usr/bin/env bash
# =============================================================================
# First-time setup (idempotent — safe to re-run).
#
#   scripts/setup.sh [--project /path/to/expo-app] [--accept-licenses]
#                    [--runtime docker|kiri]
#                    [--skip-sdk] [--skip-docker] [--recreate-avd]
#
# --runtime kiri  use Kiri (https://runkiri.com) instead of Docker Desktop.
#                 Optional; install Kiri yourself first. Saved to .env.
#
# On macOS it installs ONLY into $ENV_HOME (default ~/.expoemu):
#   sdk/platform-tools   pinned adb (same version as the container)
#   sdk/emulator         Google Android Emulator (uses Hypervisor.framework)
#   sdk/system-images    Android 16 / API 36, Google APIs, x86_64 or arm64
#   avd/                 one Pixel virtual device
# Nothing is added to PATH, shell profiles, ~/Library/Android or ~/.android.
# No Java is required on macOS: archives are fetched directly and checksummed
# instead of using sdkmanager/avdmanager.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"

# --- Arguments ---------------------------------------------------------------
ARG_PROJECT="" ARG_RUNTIME="" ACCEPT_LICENSES="${ACCEPT_ANDROID_LICENSES:-no}" SKIP_SDK=0 SKIP_DOCKER=0 RECREATE_AVD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) ARG_PROJECT="$2"; shift 2 ;;
    --runtime)
      case "${2:-}" in docker|kiri) ARG_RUNTIME="$2" ;; *) die "--runtime must be 'docker' or 'kiri'" ;; esac
      shift 2 ;;
    --accept-licenses) ACCEPT_LICENSES=yes; shift ;;
    --skip-sdk) SKIP_SDK=1; shift ;;
    --skip-docker) SKIP_DOCKER=1; shift ;;
    --recreate-avd) RECREATE_AVD=1; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

require_macos
for tool in curl unzip shasum; do command -v "$tool" >/dev/null || die "Missing required tool: $tool"; done

# --- 1. Local .env -----------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
  mkdir -p "$(dirname "$ENV_FILE")"
  cp "$REPO_ROOT/.env.example" "$ENV_FILE"
  ok "Created settings file $ENV_FILE"
fi
if [ -n "$ARG_PROJECT" ]; then
  abs="$(cd "$ARG_PROJECT" && pwd -P)" || die "Not a directory: $ARG_PROJECT"
  # Rewrite the PROJECT_DIR= line in place (BSD sed syntax for macOS).
  sed -i '' "s|^PROJECT_DIR=.*|PROJECT_DIR=$abs|" "$ENV_FILE"
  ok "PROJECT_DIR set to $abs"
fi
if [ -n "$ARG_RUNTIME" ]; then
  # Replace the line, or append it for .env files created before this option.
  if grep -q '^CONTAINER_RUNTIME=' "$ENV_FILE"; then
    sed -i '' "s|^CONTAINER_RUNTIME=.*|CONTAINER_RUNTIME=$ARG_RUNTIME|" "$ENV_FILE"
  else
    printf '\nCONTAINER_RUNTIME=%s\n' "$ARG_RUNTIME" >> "$ENV_FILE"
  fi
  ok "Container runtime set to $ARG_RUNTIME"
  # A one-off CONTAINER_RUNTIME in the shell would otherwise override .env.
  export CONTAINER_RUNTIME="$ARG_RUNTIME"
fi
load_config
mkdir -p "$SDK_DIR" "$AVD_HOME" "$LOG_DIR" "$RUN_DIR" "$ANDROID_USER_HOME" "$ENV_HOME/downloads"
# Marker proving this folder was created by us — cleanup.sh refuses to delete
# an ENV_HOME without it (protects against a mis-set ENV_HOME=/ or $HOME).
touch "$ENV_HOME/.expoemu-root"

# --- 2. Android SDK license (asked once, remembered in ENV_HOME) ------------
LICENSE_MARK="$ENV_HOME/.android-sdk-license-accepted"
[ -f "$LICENSE_MARK" ] && ACCEPT_LICENSES=yes
if [ "$SKIP_SDK" = 0 ] && [ "$ACCEPT_LICENSES" != yes ]; then
  cat >&2 <<'EOF'

The Android Emulator, platform-tools and system images are provided by Google
under the Android Software Development Kit License Agreement:
  https://developer.android.com/studio/terms
EOF
  if [ -t 0 ]; then
    read -r -p "Do you accept these terms? [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]] || die "License not accepted — nothing installed."
  else
    die "Non-interactive shell: re-run with --accept-licenses to accept the Android SDK terms."
  fi
fi
[ "$SKIP_SDK" = 0 ] && date -u +%Y-%m-%dT%H:%M:%SZ > "$LICENSE_MARK"

# --- Helper: download + verify SHA-1 + extract into the SDK -------------------
# install_zip <url> <sha1> <dest-dir> <marker-value>
# Skips work if <dest-dir>/.installed already contains <marker-value>.
install_zip() {
  local url="$1" sha1="$2" dest="$3" marker="$4"
  local name zip tmp
  name="$(basename "$url")"
  if [ -f "$dest/.installed" ] && [ "$(cat "$dest/.installed")" = "$marker" ]; then
    ok "$name already installed"; return
  fi
  zip="$ENV_HOME/downloads/$name"
  if [ ! -f "$zip" ] || ! echo "$sha1  $zip" | shasum -a 1 -c - >/dev/null 2>&1; then
    info "Downloading $name"
    curl -fL --progress-bar -o "$zip.part" "$url"
    mv "$zip.part" "$zip"
  fi
  echo "$sha1  $zip" | shasum -a 1 -c - >/dev/null || die "Checksum mismatch for $name (delete $zip and retry)"
  tmp="$(mktemp -d "$ENV_HOME/downloads/extract.XXXXXX")"
  unzip -q "$zip" -d "$tmp"
  rm -rf "$dest"; mkdir -p "$(dirname "$dest")"
  # Every Google archive has exactly one top-level folder.
  mv "$tmp"/*/ "$dest"
  rm -rf "$tmp" "$zip"
  echo "$marker" > "$dest/.installed"
  ok "Installed $name"
}

# --- 3. Isolated SDK on macOS --------------------------------------------------
if [ "$SKIP_SDK" = 0 ]; then
  info "Installing isolated Android SDK into $SDK_DIR ($HOST_ARCH)"
  repo="https://dl.google.com/android/repository"

  install_zip "$repo/platform-tools_r${PLATFORM_TOOLS_VERSION}-darwin.zip" \
    "$PLATFORM_TOOLS_DARWIN_SHA1" "$SDK_DIR/platform-tools" "$PLATFORM_TOOLS_VERSION"

  if [ "$HOST_ARCH" = x86_64 ]; then emu_sha="$EMULATOR_DARWIN_X64_SHA1"; img_sha="$SYSTEM_IMAGE_X86_64_SHA1"
  else emu_sha="$EMULATOR_DARWIN_AARCH64_SHA1"; img_sha="$SYSTEM_IMAGE_ARM64_SHA1"; fi

  install_zip "$repo/emulator-${EMULATOR_FLAVOUR}-${EMULATOR_BUILD}.zip" \
    "$emu_sha" "$SDK_DIR/emulator" "$EMULATOR_BUILD"

  install_zip "$repo/sys-img/${SYSTEM_IMAGE_TAG}/${SYS_IMG_ABI}-${SYSTEM_IMAGE_API}_r${SYSTEM_IMAGE_REVISION}.zip" \
    "$img_sha" "$SDK_DIR/$SYS_IMG_REL" "${SYSTEM_IMAGE_API}_r${SYSTEM_IMAGE_REVISION}"

  # The emulator expects these folders to exist in a valid SDK root.
  mkdir -p "$SDK_DIR/platforms" "$SDK_DIR/platform-tools"

  # --- 4. Virtual device (written directly; avdmanager would need Java) -----
  avd_dir="$AVD_HOME/$AVD_NAME.avd"
  if [ -d "$avd_dir" ] && [ "$RECREATE_AVD" = 1 ]; then
    info "Recreating AVD $AVD_NAME (wipes its data)"; rm -rf "$avd_dir" "$AVD_HOME/$AVD_NAME.ini"
  fi
  if [ ! -f "$avd_dir/config.ini" ]; then
    # Default device = "phone" profile, overridable via the AVD_* settings.
    write_avd "$AVD_NAME" "$AVD_DEVICE_NAME" "$AVD_LCD_WIDTH" "$AVD_LCD_HEIGHT" \
      "$AVD_LCD_DENSITY" "$AVD_RAM_MB" phone
    ok "Created AVD $AVD_NAME ($AVD_DEVICE_NAME, API ${SYSTEM_IMAGE_API}, $SYS_IMG_ABI)"
  else
    ok "AVD $AVD_NAME already exists (use --recreate-avd to rebuild it)"
  fi

  # --- 5. Hardware acceleration check (Hypervisor.framework) ----------------
  if accel="$("$EMULATOR_BIN" -accel-check 2>&1)"; then
    # Output is "accel:\n0\n<description>\naccel" — the description is line 3.
    ok "Hardware acceleration: $(echo "$accel" | sed -n '3p')"
  else
    warn "Hardware acceleration check failed:"; echo "$accel" >&2
  fi
fi

# --- 6. Docker image -----------------------------------------------------------
if [ "$SKIP_DOCKER" = 0 ]; then
  require_docker
  info "Building Docker image $IMAGE_NAME (first build takes a few minutes)"
  # PROJECT_DIR is required by compose interpolation; any dir works for a build.
  PROJECT_DIR="${PROJECT_DIR:-$REPO_ROOT}" compose build
  ok "Docker image ready"
fi

cat >&2 <<EOF

${C_GREEN}Setup complete.${C_RESET} Next, from your Expo project folder:
EOF
# Hints follow how setup was run (npx expoemu … vs scripts/….sh).
if [ -n "${EXPOEMU_CLI:-}" ]; then
  cat >&2 <<'EOF'
  npx expoemu up        # boot the phone, start the container + Metro, open the app
  npx expoemu status    # verify everything is connected
  npx expoemu down      # stop everything when you're done
EOF
else
  cat >&2 <<'EOF'
  scripts/emulator-start.sh                 # boot the virtual phone
  scripts/start.sh /path/to/your-expo-app   # start the container
  scripts/expo.sh --background              # run Metro
  scripts/open-app.sh                       # open the app in Expo Go
  scripts/status.sh                         # verify everything is connected
EOF
fi
