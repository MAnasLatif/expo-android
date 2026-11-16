// Unit tests for the expoemu CLI dispatcher (no emulator or Docker needed).
// Run with: npm test
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const BIN = path.join(ROOT, 'bin', 'expoemu.js');
const pkg = require('../package.json');
const { COMMANDS } = require('../bin/expoemu.js');

const run = (...args) => spawnSync(process.execPath, [BIN, ...args],
  { encoding: 'utf8', env: { ...process.env, EXPOEMU_NO_UPDATE_CHECK: '1' } });

test('--version prints the package version', () => {
  const r = run('--version');
  assert.strictEqual(r.status, 0);
  assert.strictEqual(r.stdout.trim(), pkg.version);
});

test('help lists the key commands', () => {
  const r = run('help');
  assert.strictEqual(r.status, 0);
  for (const word of ['setup', 'up', 'down', 'screenshot', 'tap-text', 'logcat', 'status']) {
    assert.match(r.stdout, new RegExp(`\\b${word}\\b`), `help should mention ${word}`);
  }
});

test('unknown command exits 2 with a hint', () => {
  const r = run('definitely-not-a-command');
  assert.strictEqual(r.status, 2);
  assert.match(r.stderr, /unknown command/);
});

test('every command maps to an existing script', () => {
  for (const [name, { script }] of Object.entries(COMMANDS)) {
    assert.ok(fs.existsSync(path.join(ROOT, 'scripts', script)), `${name} -> scripts/${script} missing`);
  }
  for (const s of ['emulator-start.sh', 'emulator-stop.sh', 'expo.sh', 'open-app.sh', 'start.sh']) {
    assert.ok(fs.existsSync(path.join(ROOT, 'scripts', s)), `scripts/${s} missing (used by up/emulator)`);
  }
});

test('help documents every command', () => {
  const { HELP } = require('../bin/expoemu.js');
  for (const name of Object.keys(COMMANDS)) {
    if (name === 'doctor' || name === 'check-versions') continue; // aliases/maintenance
    assert.ok(HELP.includes(name), `help is missing "${name}"`);
  }
});

test('every routed command is handled by its script', () => {
  // A command forwarded to device/system/app.sh must appear in that script's
  // case statement, otherwise users get "Unknown command" at runtime.
  for (const [name, { script, prefix }] of Object.entries(COMMANDS)) {
    if (!prefix || prefix[0] !== name) continue;
    const src = fs.readFileSync(path.join(ROOT, 'scripts', script), 'utf8');
    const handled = new RegExp(`^\\s*(?:[\\w-]+\\|)*${name.replace(/-/g, '\\-')}(?:\\|[\\w-]+)*\\)`, 'm');
    assert.match(src, handled, `${script} has no case for "${name}"`);
  }
});

test('--device is extracted anywhere, but not from passthrough commands', () => {
  const { extractDevice } = require('../bin/expoemu.js');
  assert.deepStrictEqual(extractDevice(['tap-text', 'Login', '--device', 'tablet']),
    { device: 'tablet', rest: ['tap-text', 'Login'] });
  assert.deepStrictEqual(extractDevice(['-d', 'small', 'screenshot', 'home']),
    { device: 'small', rest: ['screenshot', 'home'] });
  assert.deepStrictEqual(extractDevice(['--device=tablet', 'ui']),
    { device: 'tablet', rest: ['ui'] });
  // adb's own -d (USB device) must reach adb untouched…
  assert.deepStrictEqual(extractDevice(['adb', '-d', 'shell', 'ls']),
    { device: null, rest: ['adb', '-d', 'shell', 'ls'] });
  // …but a --device before the command still targets an emulator.
  assert.deepStrictEqual(extractDevice(['--device', 'tablet', 'shell', 'ls', '-d', 'x']),
    { device: 'tablet', rest: ['shell', 'ls', '-d', 'x'] });
  assert.deepStrictEqual(extractDevice(['status']), { device: null, rest: ['status'] });
});

test('hints use the same form the user ran: npx vs global command', () => {
  const { commandPrefix } = require('../bin/expoemu.js');
  assert.strictEqual(commandPrefix('/Users/a/.npm/_npx/123abc/node_modules/expoemu/bin/expoemu.js', '/w'), 'npx expoemu');
  assert.strictEqual(commandPrefix('/w/node_modules/expoemu/bin/expoemu.js', '/w'), 'npx expoemu');      // devDependency
  assert.strictEqual(commandPrefix('/Users/a/.nvm/versions/node/v24/lib/node_modules/expoemu/bin/expoemu.js', '/w'), 'expoemu');
  assert.strictEqual(commandPrefix('/opt/homebrew/lib/node_modules/expoemu/bin/expoemu.js', '/w'), 'expoemu');
});

test('package "files" ships everything the scripts need at runtime', () => {
  for (const f of ['bin/', 'scripts/', 'docker/', 'config/', 'Dockerfile', 'docker-compose.yml', '.env.example']) {
    assert.ok(pkg.files.includes(f), `package.json files is missing ${f}`);
  }
});
