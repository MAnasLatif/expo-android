#!/usr/bin/env node
// =============================================================================
// eaenv — Expo Android ENVironment CLI
//
// Thin, dependency-free dispatcher: every command maps to a bash script in
// ../scripts. Run it from your Expo project folder:
//
//   npx eaenv setup        one-time install (isolated SDK, AVD, Docker image)
//   npx eaenv up           phone + container + Metro + open the app
//   npx eaenv screenshot   …and the other agent-friendly device commands
//   npx eaenv down         stop everything
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
const DEVICE_CMDS = [
  'tap', 'swipe', 'scroll', 'text', 'key', 'back', 'home', 'ui', 'find',
  'tap-text', 'logcat', 'reload', 'devmenu', 'open-url', 'activity', 'size', 'adb',
];

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

const HELP = `eaenv ${pkg.version} — Expo Android ENVironment

Run an Expo app on a native Android emulator (macOS) with the toolchain in
Docker. Run commands from your Expo project folder.

Setup & lifecycle
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

Device control (great for AI assistants)
  screenshot [name]            save PNG to ./.android-screenshots, print its path
  ui                           list on-screen elements with tap coordinates
  tap X Y | tap-text "Text"    tap by pixels or by visible text
  find "Text"                  print the center "X Y" of an element
  swipe X1 Y1 X2 Y2 [ms]       swipe;  scroll down|up
  text "hello"                 type text;  key BACK|HOME|ENTER…;  back;  home
  logcat [--errors|--all] [-n N] [--follow] [--clear]
  reload | devmenu | open-url URL | activity | size | adb ARGS…

Other
  check-versions [--verify-sync]   compare pinned tool versions with upstream
  help | --version

Docs: docs/AGENTS.md in the package (or the project README).`;

// --- Helpers ---------------------------------------------------------------------
function runScript(script, args) {
  const file = path.join(SCRIPTS, script);
  // Invoke through bash so executable bits don't matter after npm install.
  const r = spawnSync('bash', [file, ...args], { stdio: 'inherit', cwd: process.cwd() });
  if (r.error) {
    console.error(`eaenv: failed to run bash: ${r.error.message}`);
    return 1;
  }
  return r.status === null ? 1 : r.status;
}

// `up`: the whole session in one command, stopping at the first failure.
function up(args) {
  const emuFlags = args.filter((a) => ['--headless', '--no-animations', '--cold-boot'].includes(a));
  const unknown = args.filter((a) => !emuFlags.includes(a));
  if (unknown.length) {
    console.error(`eaenv up: unknown option(s): ${unknown.join(' ')}`);
    return 2;
  }
  const steps = [
    ['emulator-start.sh', emuFlags],
    ['start.sh', []],
    ['expo.sh', ['--background']],
    ['open-app.sh', []],
  ];
  for (const [script, a] of steps) {
    const code = runScript(script, a);
    if (code !== 0) return code;
  }
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
    console.error(`eaenv: unknown command "${cmd}". Run: npx eaenv help`);
    return 2;
  }
  // Checked at runtime, not via package.json "os": a project may list eaenv as a
  // devDependency and `bun install` runs inside the Linux container too.
  if (process.platform !== 'darwin') {
    console.error('eaenv: the Android emulator side currently supports macOS only.');
    return 1;
  }
  if (cmd === 'up') return up(args);
  if (cmd === 'emulator') {
    const [sub, ...rest] = args;
    if (sub === 'start') return runScript('emulator-start.sh', rest);
    if (sub === 'stop') return runScript('emulator-stop.sh', rest);
    console.error('usage: eaenv emulator start|stop [flags]');
    return 2;
  }

  const entry = COMMANDS[cmd];
  return runScript(entry.script, [...(entry.prefix || []), ...args]);
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}

module.exports = { COMMANDS, main };
