#!/usr/bin/env node
// =============================================================================
// expoemu — Expo Emulator
//
// Thin, dependency-free dispatcher: every command maps to a bash script in
// ../scripts. Run it from your Expo project folder:
//
//   npx expoemu setup        one-time install (isolated SDK, AVD, Docker image)
//   npx expoemu up           phone + container + Metro + open the app
//   npx expoemu screenshot   …and the other agent-friendly device commands
//   npx expoemu down         stop everything
//
// The scripts do the real work; this file only routes arguments and exit codes.
// =============================================================================
'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const ROOT = path.resolve(__dirname, '..');
const SCRIPTS = path.join(ROOT, 'scripts');
const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));

// --- Command table --------------------------------------------------------------
// script: file in scripts/; prefix: args inserted before the user's args.
// Each list below forwards `expoemu <cmd> …` to `<script> <cmd> …`.
const DEVICE_CMDS = [ // scripts/device.sh — touch, elements, waits, keys
  'tap', 'double-tap', 'long-press', 'swipe', 'drag', 'scroll',
  'ui', 'texts', 'find', 'tap-text', 'long-press-text', 'scroll-to',
  'wait-for', 'wait-gone', 'assert-text', 'assert-no-text',
  'text', 'clear', 'fill', 'hide-keyboard', 'key', 'back', 'home', 'recents',
  'enter', 'lock', 'unlock',
  'logcat', 'reload', 'devmenu', 'open-url', 'activity', 'size', 'adb',
];
const SYSTEM_CMDS = [ // scripts/system.sh — device state, capture, info
  'rotate', 'dark-mode', 'font-scale', 'animations', 'network', 'airplane',
  'location', 'battery', 'notifications', 'permission', 'locale', 'record', 'info',
];
const APP_CMDS = ['app', 'crash', 'perf', 'memory']; // scripts/app.sh

const COMMANDS = {
  setup:            { script: 'setup.sh' },
  start:            { script: 'start.sh' },
  stop:             { script: 'stop.sh' },
  shell:            { script: 'shell.sh' },
  expo:             { script: 'expo.sh' },
  open:             { script: 'open-app.sh' },
  status:           { script: 'status.sh' },
  doctor:           { script: 'status.sh' },
  screenshot:       { script: 'screenshot.sh' },
  cleanup:          { script: 'cleanup.sh' },
  'check-versions': { script: 'check-versions.sh' },
  down:             { script: 'stop.sh', prefix: ['--all'] },
};
for (const c of DEVICE_CMDS) COMMANDS[c] = { script: 'device.sh', prefix: [c] };
for (const c of SYSTEM_CMDS) COMMANDS[c] = { script: 'system.sh', prefix: [c] };
for (const c of APP_CMDS) COMMANDS[c] = { script: 'app.sh', prefix: [c] };

const HELP = `expoemu ${pkg.version} — Expo Emulator

Run an Expo app on a native Android emulator (macOS) with the toolchain in
Docker. Run commands from your Expo project folder.
"Text" selectors match visible text, accessibilityLabel, testID or placeholder.

SETUP & LIFECYCLE
  setup [--runtime docker|kiri] [--accept-licenses]   one-time install
  up [--headless] [--no-animations] [--cold-boot]     phone + container + Metro + open app
  down                                                stop container, emulator, adb
  status | doctor                                     health check (exit 1 if broken)
  emulator start|stop [flags]                         only the phone
  start | stop                                        only the container
  expo [--background|--logs|--stop] [expo args]       Metro bundler
  open [--reinstall]                                  install Expo Go if needed, open app
  shell [cmd…]                                        shell / command inside the container
  cleanup --project|--caches|--image|--sdk|--all      scoped removal (asks first)

SEE THE SCREEN
  screenshot [name]                 PNG in ./.android-screenshots, prints its path
  record [SECONDS] [name]           MP4 screen recording (max 180 s)
  ui [--xml]                        elements with tap coordinates (or raw XML)
  texts                             visible text only
  find "Text"                       center "X Y" of an element

TOUCH
  tap X Y | double-tap X Y | long-press X Y [ms]
  tap-text "Text" | long-press-text "Text" [ms]
  swipe X1 Y1 X2 Y2 [ms] | drag X1 Y1 X2 Y2 [ms]
  scroll down|up|left|right | scroll-to "Text" [--up] [--max N]

TYPE & KEYS
  fill "Field" "value" [--keep-keyboard]   tap field, clear, type, hide keyboard
  text "hello" | clear | hide-keyboard
  key NAME|CODE | back | home | recents | enter | lock | unlock

WAIT & ASSERT (exit 0 = pass, 1 = fail)
  wait-for "Text" [--timeout S] | wait-gone "Text" [--timeout S]
  assert-text "Text" | assert-no-text "Text"

DEVICE STATE
  rotate portrait|landscape|auto | dark-mode on|off | font-scale 1.3|reset
  animations on|off | network on|off | airplane on|off
  location LAT LON | battery LEVEL|unplug|charge|reset
  notifications open|close|settings
  permission grant|revoke|list [PERM] [PKG] | locale TAG|reset [PKG]
  info                              device summary

APP & DEBUGGING
  app launch|stop|restart|clear|install|uninstall|list|info [PKG]
  logcat [--errors|--all] [-n N] [--follow] [--clear] | crash [-n N]
  perf [--reset] | memory | reload | devmenu | open-url URL | activity | size
  adb ARGS…                         raw adb against the emulator

OTHER
  check-versions [--verify-sync]   compare pinned tool versions with upstream
  help | --version

Docs: docs/AGENTS.md in the package (or the project README).`;

// --- Helpers ---------------------------------------------------------------------
function runScript(script, args, extraEnv = {}) {
  const file = path.join(SCRIPTS, script);
  // Invoke through bash so executable bits don't matter after npm install.
  // EXPOEMU_CLI makes the scripts print hints as `npx expoemu …` commands.
  const r = spawnSync('bash', [file, ...args], {
    stdio: 'inherit',
    cwd: process.cwd(),
    env: { ...process.env, EXPOEMU_CLI: '1', ...extraEnv },
  });
  if (r.error) {
    console.error(`expoemu: failed to run bash: ${r.error.message}`);
    return 1;
  }
  return r.status === null ? 1 : r.status;
}

// `up`: the whole session in one command, stopping at the first failure.
function up(args) {
  const emuFlags = args.filter((a) => ['--headless', '--no-animations', '--cold-boot'].includes(a));
  const unknown = args.filter((a) => !emuFlags.includes(a));
  if (unknown.length) {
    console.error(`expoemu up: unknown option(s): ${unknown.join(' ')}`);
    return 2;
  }
  const steps = [
    ['emulator-start.sh', emuFlags],
    ['start.sh', []],
    ['expo.sh', ['--background']],
    ['open-app.sh', []],
  ];
  for (const [script, a] of steps) {
    // Intermediate "next step" hints are noise here: up runs those steps itself.
    const code = runScript(script, a, { EXPOEMU_QUIET_HINTS: '1' });
    if (code !== 0) return code;
  }
  console.error('\nexpoemu: ready. Try: npx expoemu screenshot  |  npx expoemu ui  |  npx expoemu status');
  return 0;
}

function main(argv) {
  const [cmd, ...args] = argv;

  if (!cmd || cmd === 'help' || cmd === '-h' || cmd === '--help') {
    console.log(HELP);
    return 0;
  }
  if (cmd === '-v' || cmd === '--version' || cmd === 'version') {
    console.log(pkg.version);
    return 0;
  }
  const known = cmd === 'up' || cmd === 'emulator' || Object.hasOwn(COMMANDS, cmd);
  if (!known) {
    console.error(`expoemu: unknown command "${cmd}". Run: npx expoemu help`);
    return 2;
  }
  // Checked at runtime, not via package.json "os": a project may list expoemu as a
  // devDependency and `bun install` runs inside the Linux container too.
  if (process.platform !== 'darwin') {
    console.error('expoemu: the Android emulator side currently supports macOS only.');
    return 1;
  }
  if (cmd === 'up') return up(args);
  if (cmd === 'emulator') {
    const [sub, ...rest] = args;
    if (sub === 'start') return runScript('emulator-start.sh', rest);
    if (sub === 'stop') return runScript('emulator-stop.sh', rest);
    console.error('usage: expoemu emulator start|stop [flags]');
    return 2;
  }

  const entry = COMMANDS[cmd];
  return runScript(entry.script, [...(entry.prefix || []), ...args]);
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}

module.exports = { COMMANDS, HELP, main };
