// Tests for .github/scripts/sync-version.js (tag version -> package.json).
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { compare, updateChangelog, sync } = require('../.github/scripts/sync-version.js');

test('semver precedence', () => {
  assert.strictEqual(compare('0.2.0', '0.1.0'), 1);
  assert.strictEqual(compare('0.1.0', '0.2.0'), -1);
  assert.strictEqual(compare('1.0.0', '1.0.0'), 0);
  assert.strictEqual(compare('1.0.0', '1.0.0-rc.1'), 1);        // release > pre-release
  assert.strictEqual(compare('1.0.0-beta.2', '1.0.0-beta.10'), -1); // numeric ids
  assert.strictEqual(compare('1.0.0-alpha.1', '1.0.0-beta.1'), -1);
  assert.strictEqual(compare('0.10.0', '0.9.9'), 1);
});

test('changelog: Unreleased notes move under the new version', () => {
  const before = '# Changelog\n\n## [Unreleased]\n\n### Added\n\n- thing\n\n## [0.1.0] - 2026-01-01\n';
  const after = updateChangelog(before, '0.2.0', '2026-02-02');
  assert.match(after, /## \[Unreleased\]\n\n## \[0\.2\.0\] - 2026-02-02\n\n### Added\n\n- thing\n\n## \[0\.1\.0\]/);
  assert.strictEqual(updateChangelog(after, '0.2.0', '2026-02-02'), after);          // idempotent
  const empty = '# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - 2026-01-01\n';
  assert.strictEqual(updateChangelog(empty, '0.2.0', '2026-02-02'), empty);          // nothing to move
});

function fixture(version, changelog) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sync-version-'));
  fs.writeFileSync(path.join(dir, 'package.json'), `{\n  "name": "x",\n  "version": "${version}",\n  "bin": {}\n}\n`);
  if (changelog) fs.writeFileSync(path.join(dir, 'CHANGELOG.md'), changelog);
  return dir;
}

test('newer tag updates package.json (formatting kept)', () => {
  const dir = fixture('0.1.0', '## [Unreleased]\n\n- a\n');
  assert.deepStrictEqual(sync('0.2.0', '2026-02-02', dir), { changed: true, current: '0.1.0' });
  assert.strictEqual(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'),
    '{\n  "name": "x",\n  "version": "0.2.0",\n  "bin": {}\n}\n');
  assert.match(fs.readFileSync(path.join(dir, 'CHANGELOG.md'), 'utf8'), /## \[0\.2\.0\] - 2026-02-02/);
});

test('older or equal tag changes nothing; pre-release skips changelog', () => {
  const dir = fixture('0.3.0', '## [Unreleased]\n\n- a\n');
  assert.strictEqual(sync('0.2.0', '2026-02-02', dir).changed, false);
  assert.strictEqual(sync('0.3.0', '2026-02-02', dir).changed, false);
  assert.strictEqual(sync('0.4.0-beta.1', '2026-02-02', dir).changed, true);
  assert.doesNotMatch(fs.readFileSync(path.join(dir, 'CHANGELOG.md'), 'utf8'), /0\.4\.0-beta\.1/);
});
