// Tests for bin/update-check.js (newer-version notice) without touching the network.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const u = require('../bin/update-check.js');

const tmpCache = (data) => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'expoemu-upd-')), 'update-check.json');
  if (data) fs.writeFileSync(file, JSON.stringify(data));
  return file;
};

test('reports only a newer version', () => {
  assert.strictEqual(u.availableUpdate('0.4.0', tmpCache({ latest: '0.5.0' })), '0.5.0');
  assert.strictEqual(u.availableUpdate('0.4.0', tmpCache({ latest: '0.4.0' })), null);
  assert.strictEqual(u.availableUpdate('0.5.0', tmpCache({ latest: '0.4.9' })), null);
  assert.strictEqual(u.availableUpdate('0.4.0', tmpCache()), null);              // no cache yet
  assert.strictEqual(u.availableUpdate('0.4.0', tmpCache({ latest: 'junk' })), null);
});

test('message matches how the user runs expoemu', () => {
  assert.match(u.updateMessage('0.5.0', '0.4.0', 'expoemu'), /expoemu 0\.5\.0 is available .*expoemu update/);
  assert.match(u.updateMessage('0.5.0', '0.4.0', 'npx expoemu'), /npx expoemu@latest/);
});

test('checks at most once a day', () => {
  const fresh = tmpCache({ latest: '0.4.0', checkedAt: Date.now() });
  assert.strictEqual(u.refreshInBackground(fresh), false);
});

test('can be turned off', () => {
  assert.strictEqual(u.disabled({ EXPOEMU_NO_UPDATE_CHECK: '1' }), true);
  assert.strictEqual(u.disabled({ CI: 'true' }), true);
  assert.strictEqual(u.disabled({}), false);
});
