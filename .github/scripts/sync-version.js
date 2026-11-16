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
// SemVer helpers live in bin/semver.js (shared with the CLI's update notice).
const { SEMVER, compare } = require(path.join(ROOT, 'bin', 'semver.js'));

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
