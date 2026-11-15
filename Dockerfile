# syntax=docker/dockerfile:1
# =============================================================================
# Expo Emulator — development container
#
# Contains: Ubuntu, JDK 17, Node.js LTS, Bun, Android cmdline-tools and
# platform-tools (adb). The Android Emulator is NOT in here — it runs natively
# on macOS for hardware acceleration. The container's adb client connects to
# the macOS adb server through host.docker.internal (see docker-compose.yml).
#
# All versions come from config/versions.env via build args (docker compose
# passes them automatically). Defaults below exist only so `docker build .`
# works stand-alone.
# =============================================================================
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ARG JDK_VERSION=17
ARG NODE_VERSION=24.22.3
ARG BUN_VERSION=1.4.4
ARG CMDLINE_TOOLS_BUILD=16111833
ARG CMDLINE_TOOLS_LINUX_SHA1=e025545c62a8e64c7559119566a569fb1dec5f60
ARG PLATFORM_TOOLS_VERSION=37.0.3
ARG PLATFORM_TOOLS_LINUX_SHA1=e1579b288a7ae4e9bc28dedec6a154d78b3c04ed
# Optional: extra sdkmanager packages, e.g. "platforms;android-36 build-tools;36.0.0"
# Only needed for native builds (expo run:android). Expo Go needs none.
ARG ANDROID_EXTRA_PACKAGES=""

LABEL org.opencontainers.image.title="expoemu" \
      org.opencontainers.image.description="Expo + Bun + Android adb toolchain; pairs with a native macOS Android Emulator" \
      org.opencontainers.image.licenses="MIT" \
      com.expoemu.managed="true"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    JAVA_HOME=/usr/lib/jvm/jdk

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- 1. Base OS packages + JDK ----------------------------------------------
# setpriv (util-linux) drops root -> expo user in the entrypoint.
# tini reaps zombie processes (Metro spawns many workers).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip xz-utils git jq tini procps util-linux \
      openjdk-${JDK_VERSION}-jdk-headless \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sfn "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" /usr/lib/jvm/jdk \
 && java -version

# --- 2. Node.js (official tarball, SHA-256 verified) -------------------------
# Expo CLI's binaries use a `node` shebang, so Node is required even with Bun.
RUN case "$(dpkg --print-architecture)" in amd64) a=x64 ;; arm64) a=arm64 ;; *) echo "unsupported arch" >&2; exit 1 ;; esac \
 && f="node-v${NODE_VERSION}-linux-${a}.tar.xz" \
 && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${f}" \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${f}\$" | sha256sum -c - \
 && tar -xJf "${f}" -C /usr/local --strip-components=1 --no-same-owner \
 && rm "${f}" \
 && node --version && npm --version

# --- 3. Bun (official release, SHA-256 verified) -----------------------------
# Uses the "baseline" build when the CPU lacks AVX2 (e.g. Rosetta on Apple
# Silicon), otherwise the optimized build.
RUN case "$(dpkg --print-architecture)" in amd64) a=x64 ;; arm64) a=aarch64 ;; esac \
 && if [ "$a" = x64 ] && ! grep -q avx2 /proc/cpuinfo; then a=x64-baseline; fi \
 && f="bun-linux-${a}.zip" \
 && base="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}" \
 && curl -fsSLO "${base}/${f}" \
 && curl -fsSL "${base}/SHASUMS256.txt" | grep " ${f}\$" | sha256sum -c - \
 && unzip -q "${f}" && install -m 0755 "bun-linux-${a}/bun" /usr/local/bin/bun \
 && ln -s /usr/local/bin/bun /usr/local/bin/bunx \
 && rm -rf "${f}" "bun-linux-${a}" \
 && bun --version

# --- 4. Android SDK: cmdline-tools + pinned platform-tools (SHA-1 verified) --
# platform-tools is installed from a pinned zip (not sdkmanager "latest") so
# the adb version always matches the one installed on macOS.
RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
 && f="commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" \
 && curl -fsSLO "https://dl.google.com/android/repository/${f}" \
 && echo "${CMDLINE_TOOLS_LINUX_SHA1}  ${f}" | sha1sum -c - \
 && unzip -q "${f}" -d /tmp/clt && mv /tmp/clt/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
 && rm -rf "${f}" /tmp/clt \
 && f="platform-tools_r${PLATFORM_TOOLS_VERSION}-linux.zip" \
 && curl -fsSLO "https://dl.google.com/android/repository/${f}" \
 && echo "${PLATFORM_TOOLS_LINUX_SHA1}  ${f}" | sha1sum -c - \
 && unzip -q "${f}" -d "${ANDROID_HOME}" && rm "${f}" \
 && if [ -n "${ANDROID_EXTRA_PACKAGES}" ]; then \
      yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null \
      && "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ${ANDROID_EXTRA_PACKAGES}; \
    fi

ENV PATH="${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}"

# --- 5. Non-root user --------------------------------------------------------
# Ubuntu 24.04 ships a default `ubuntu` user at UID 1000; replace it with
# `expo` so files created in the mounted project are owned by a normal user.
RUN userdel -r ubuntu 2>/dev/null || true \
 && useradd --create-home --uid 1000 --shell /bin/bash expo \
 && mkdir -p /workspace /home/expo/.bun/install/cache /home/expo/.expo /home/expo/.gradle /home/expo/.cache \
 && chown -R expo:expo /workspace /home/expo "${ANDROID_HOME}"

ENV HOME=/home/expo \
    BUN_INSTALL_CACHE_DIR=/home/expo/.bun/install/cache

COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 8081

# tini = PID 1; entrypoint fixes volume ownership then drops to `expo`.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
