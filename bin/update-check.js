// "A newer expoemu is available" notice.
//
// - At most once a day, a detached background process asks the npm registry
//   for the latest version and caches it in ~/.expoemu/run/update-check.json.
//   The command itself never waits for the network.
// - The CLI prints a one-line notice (from the cache) after a command, only in
//   an interactive terminal, so agents and CI output stay clean. Scripts get
//   EXPOEMU_UPDATE_AVAILABLE so `status` can mention it.
// - Off with EXPOEMU_NO_UPDATE_CHECK=1 (also off when CI is set).
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { compare } = require('./semver.js');

const DAY = 24 * 60 * 60 * 1000;
const CACHE = path.join(os.homedir(), '.expoemu', 'run', 'update-check.json');

function disabled(env = process.env) {
  return Boolean(env.EXPOEMU_NO_UPDATE_CHECK || env.CI);
}

function readCache(file = CACHE) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return {}; }
}

// Newer version from the cache, or null.
function availableUpdate(current, file = CACHE) {
  const { latest } = readCache(file);
  try { return latest && compare(latest, current) > 0 ? latest : null; } catch { return null; }
}

function updateMessage(latest, current, cmd) {
  const how = cmd === 'expoemu' ? 'expoemu update' : 'npx expoemu@latest <command>';
  return `expoemu ${latest} is available (you have ${current}) — update with: ${how}`;
}

// Runs in the background process: fetch, then write { latest, checkedAt }.
// A failed check still records checkedAt, so it is retried only tomorrow.
const FETCH = `
const https = require('https'), fs = require('fs');
const file = process.argv[1];
let prev = {}; try { prev = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}
const done = (latest) => {
  try { fs.writeFileSync(file, JSON.stringify({ latest: latest || prev.latest || null, checkedAt: Date.now() })); } catch {}
  process.exit(0);
};
const req = https.get('https://registry.npmjs.org/expoemu/latest',
  { headers: { accept: 'application/json' }, timeout: 5000 }, (res) => {
    let body = ''; res.on('data', (d) => { body += d; });
    res.on('end', () => { try { done(JSON.parse(body).version); } catch { done(); } });
  });
req.on('timeout', () => { req.destroy(); done(); });
req.on('error', () => done());
`;

// Start a background refresh when the cache is older than a day.
function refreshInBackground(file = CACHE, now = Date.now()) {
  const { checkedAt } = readCache(file);
  if (checkedAt && now - checkedAt < DAY) return false;
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    spawn(process.execPath, ['-e', FETCH, file], { detached: true, stdio: 'ignore' }).unref();
    return true;
  } catch {
    return false;
  }
}

module.exports = { CACHE, DAY, disabled, readCache, availableUpdate, updateMessage, refreshInBackground };
