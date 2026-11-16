// Tiny Semantic Versioning 2.0 helpers (no dependencies). Shared by the CLI's
// update notice and the release workflow's version sync.
'use strict';

const SEMVER = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/;

// Precedence: -1 if a < b, 0 if equal, 1 if a > b.
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

module.exports = { SEMVER, compare };
