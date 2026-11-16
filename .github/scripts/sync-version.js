#!/usr/bin/env node
// =============================================================================
// Make a released version the project's version on main.
//
//   node .github/scripts/sync-version.js <version> [--date YYYY-MM-DD]
//
// - package.json "version" becomes <version>, but only if <version> is newer
//   than the current one (tagging an old commit never moves it backwards)
// - for a stable version, CHANGELOG.md's "Unreleased" notes move under a new
//   "## [<version>] - <date>" heading (skipped if empty or already there)
//
// Prints "changed" or "unchanged" on stdout (the release workflow commits only
// on "changed"). No dependencies: runs on a bare GitHub runner.
// =============================================================================
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..', '..');
const SEMVER = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/;

// Semantic Versioning 2.0 precedence: -1 if a < b, 0 if equal, 1 if a > b.
function compare(a, b) {
  const pa = SEMVER.exec(a), pb = SEMVER.exec(b);
  if (!pa || !pb) throw new Error(`not a version: ${!pa ? a : b}`);
  for (let i = 1; i <= 3; i++) {
    const d = Number(pa[i]) - Number(pb[i]);
    if (d) return Math.sign(d);
  }
  const ra = pa[4], rb = pb[4];
  if (!ra && !rb) return 0;
  if (!ra) return 1;          // 1.0.0 > 1.0.0-beta.1
  if (!rb) return -1;
  const xa = ra.split('.'), xb = rb.split('.');
  for (let i = 0; i < Math.max(xa.length, xb.length); i++) {
    if (xa[i] === undefined) return -1;
    if (xb[i] === undefined) return 1;
    const na = /^\d+$/.test(xa[i]), nb = /^\d+$/.test(xb[i]);
    if (na && nb) { const d = Number(xa[i]) - Number(xb[i]); if (d) return Math.sign(d); continue; }
    if (na !== nb) return na ? -1 : 1;   // numeric identifiers sort first
    if (xa[i] !== xb[i]) return xa[i] < xb[i] ? -1 : 1;
  }
  return 0;
}

// Move the Unreleased notes under a version heading (stable versions only).
function updateChangelog(text, version, date) {
  if (text.includes(`## [${version}]`)) return text;          // already released
  const m = /## \[Unreleased\]\n([\s\S]*?)(?=\n## \[|$)/.exec(text);
  if (!m || !m[1].trim()) return text;                         // nothing to move
  return text.replace(m[0], `## [Unreleased]\n\n## [${version}] - ${date}\n${m[1].replace(/^\n*/, '\n')}`);
}

function sync(version, date, root = ROOT) {
  const pkgFile = path.join(root, 'package.json');
  const pkgText = fs.readFileSync(pkgFile, 'utf8');
  const current = JSON.parse(pkgText).version;
  if (compare(version, current) <= 0) return { changed: false, current };

  // Replace only the version value, keeping the file's formatting.
  fs.writeFileSync(pkgFile, pkgText.replace(/("version"\s*:\s*")[^"]+(")/, `$1${version}$2`));

  const isPrerelease = version.includes('-');
  const logFile = path.join(root, 'CHANGELOG.md');
  if (!isPrerelease && fs.existsSync(logFile)) {
    const before = fs.readFileSync(logFile, 'utf8');
    const after = updateChangelog(before, version, date);
    if (after !== before) fs.writeFileSync(logFile, after);
  }
  return { changed: true, current };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const version = (args[0] || '').replace(/^v/, '');
  const dateIdx = args.indexOf('--date');
  const date = dateIdx >= 0 ? args[dateIdx + 1] : new Date().toISOString().slice(0, 10);
  if (!SEMVER.test(version)) {
    console.error('usage: sync-version.js <version> [--date YYYY-MM-DD]');
    process.exit(2);
  }
  const r = sync(version, date);
  console.error(r.changed ? `package.json: ${r.current} -> ${version}` : `package.json stays ${r.current} (not older than ${version})`);
  console.log(r.changed ? 'changed' : 'unchanged');
}

module.exports = { compare, updateChangelog, sync };
