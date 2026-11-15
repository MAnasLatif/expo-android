# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-15

### Added

- Docker image: Ubuntu 24.04, OpenJDK 17, Node.js 24.22.3, Bun 1.4.4, Android
  cmdline-tools and platform-tools 37.0.3.
- Native macOS Android Emulator (build 16863232) with an Android 16 / API 36
  Google APIs image (x86_64 on Intel, arm64 on Apple Silicon), installed into
  an isolated `~/.expo-android-env`. macOS doesn't need Java.
- Shared adb server: the container's adb client talks to the macOS server
  through `host.docker.internal`.
- Metro on `127.0.0.1` with `adb reverse` into the emulator.
- Scripts: `setup`, `start`, `stop`, `shell`, `expo`, `open-app`,
  `emulator-start`, `emulator-stop`, `screenshot`, `device`, `status`,
  `cleanup`, `check-versions`.
- Agent-friendly device control: UI element listing, tap by text,
  screenshots, logcat filters.
- Open-source project files: MIT license, contributing guide, code of
  conduct, security policy, CI, Dependabot.
