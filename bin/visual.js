// =============================================================================
// Visual regression: compare screenshots with saved baselines.
//
//   expoemu baseline NAME [--update]        save the current screen as .expoemu/baselines/NAME.png
//   expoemu compare NAME [options]          screenshot now and compare with that baseline
//   expoemu compare A.png B.png [options]   compare two image files
//
// options:
//   --threshold P          max % of differing pixels to still pass (default 0.1)
//   --tolerance N          per-channel difference ignored as noise, 0-255 (default 16)
//   --mask x1,y1,x2,y2     ignore a rectangle in device pixels (repeatable)
//   --include-status-bar   also compare the status bar (clock, battery…), ignored by default
//
// With --device NAME, baselines live in .expoemu/baselines/NAME/ (screens of
// different devices differ). A diff image marks changed pixels in red,
// ignored areas in blue. Exit 0 = match, 1 = differs, 2 = usage / missing file.
// =============================================================================
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const png = require('./png.js');

// --- Pixel comparison (pure; unit-tested) -----------------------------------------
// masks: [{x1,y1,x2,y2}] areas to skip. Returns counts and a diff image.
function compareImages(a, b, { tolerance = 16, masks = [] } = {}) {
  if (a.width !== b.width || a.height !== b.height) {
    return { sizeMismatch: true, a: `${a.width}x${a.height}`, b: `${b.width}x${b.height}` };
  }
  const { width, height } = b;
  const out = Buffer.alloc(width * height * 4);
  let compared = 0, changed = 0;
  const masked = (x, y) => masks.some((m) => x >= m.x1 && x < m.x2 && y >= m.y1 && y < m.y2);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      if (masked(x, y)) {                                   // ignored: light blue
        out[i] = 200; out[i + 1] = 220; out[i + 2] = 255; out[i + 3] = 255;
        continue;
      }
      compared++;
      const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]),
        Math.abs(a.data[i + 2] - b.data[i + 2]), Math.abs(a.data[i + 3] - b.data[i + 3]));
      if (d > tolerance) {                                  // changed: red
        changed++;
        out[i] = 255; out[i + 1] = 0; out[i + 2] = 0; out[i + 3] = 255;
      } else {                                              // same: faded copy for context
        const g = (b.data[i] * 0.3 + b.data[i + 1] * 0.59 + b.data[i + 2] * 0.11) | 0;
        out[i] = out[i + 1] = out[i + 2] = 180 + ((g * 75) / 255 | 0); out[i + 3] = 255;
      }
    }
  }
  const percent = compared ? (changed / compared) * 100 : 0;
  return { width, height, compared, changed, percent, diff: { width, height, data: out } };
}

// --- CLI ----------------------------------------------------------------------------

function parseOptions(argv) {
  const o = { positional: [], threshold: 0.1, tolerance: 16, masks: [], statusBar: false, update: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--threshold') o.threshold = Number(argv[++i]);
    else if (a === '--tolerance') o.tolerance = Number(argv[++i]);
    else if (a === '--include-status-bar') o.statusBar = true;
    else if (a === '--update') o.update = true;
    else if (a === '--mask') {
      const m = /^(\d+),(\d+),(\d+),(\d+)$/.exec(argv[++i] || '');
      if (!m) throw new Error('--mask needs x1,y1,x2,y2 (device pixels)');
      o.masks.push({ x1: +m[1], y1: +m[2], x2: +m[3], y2: +m[4] });
    } else if (a.startsWith('--')) throw new Error(`unknown option ${a}`);
    else o.positional.push(a);
  }
  if (!(o.threshold >= 0)) throw new Error('--threshold must be a number >= 0');
  if (!(o.tolerance >= 0 && o.tolerance <= 255)) throw new Error('--tolerance must be 0-255');
  return o;
}

const safeName = (s) => String(s).replace(/[^A-Za-z0-9._-]/g, '-');

function baselinePath(cwd, name) {
  const device = process.env.EXPOEMU_DEVICE;
  const dir = path.join(cwd, '.expoemu', 'baselines', ...(device ? [safeName(device)] : []));
  return path.join(dir, `${safeName(name)}.png`);
}

// Height of the status bar in pixels on the target device.
function statusBarHeight(exec) {
  const r = exec(['adb', 'shell', 'dumpsys', 'window']);
  const m = /type=statusBars frame=\[0,0\]\[\d+,(\d+)\]/.exec(r.stdout || '');
  if (m) return Number(m[1]);
  const d = /(\d+)/.exec(exec(['adb', 'shell', 'wm', 'density']).stdout || '');
  return Math.round((24 * (d ? Number(d[1]) : 420)) / 160);
}

function main(cmd, argv, { bin, cwd = process.cwd(), out = console } = {}) {
  let o;
  try { o = parseOptions(argv); } catch (e) { out.error(`expoemu ${cmd}: ${e.message}`); return 2; }
  const exec = (args) => spawnSync(process.execPath, [bin, ...args], {
    cwd, encoding: 'utf8', env: { ...process.env, EXPOEMU_NO_UPDATE_CHECK: '1', NO_COLOR: '1' },
  });
  const screenshot = (label) => {
    const r = exec(['screenshot', label]);
    if (r.status !== 0) throw new Error((r.stderr || r.stdout || 'screenshot failed').trim());
    return r.stdout.trim().split('\n').pop();
  };

  try {
    // expoemu baseline NAME [--update]
    if (cmd === 'baseline') {
      const [name] = o.positional;
      if (!name) { out.error('usage: expoemu baseline NAME [--update]'); return 2; }
      const file = baselinePath(cwd, name);
      if (fs.existsSync(file) && !o.update) {
        out.error(`Baseline exists: ${path.relative(cwd, file)} — use --update to replace it`);
        return 1;
      }
      const shot = screenshot(`baseline-${safeName(name)}`);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.copyFileSync(shot, file);
      out.log(file);
      out.error(` ✓ Baseline saved (commit .expoemu/baselines/ to share it)`);
      return 0;
    }

    // expoemu compare A.png B.png  |  expoemu compare NAME
    let aFile, bFile, label, ignoreTop = 0;
    if (o.positional.length === 2) {
      [aFile, bFile] = o.positional.map((p) => path.resolve(cwd, p));
      label = `${path.basename(aFile, '.png')}-vs-${path.basename(bFile, '.png')}`;
    } else if (o.positional.length === 1) {
      label = safeName(o.positional[0]);
      aFile = baselinePath(cwd, o.positional[0]);
      if (!fs.existsSync(aFile)) {
        out.error(`No baseline "${o.positional[0]}" (${path.relative(cwd, aFile)}) — create it with: expoemu baseline ${o.positional[0]}`);
        return 2;
      }
      bFile = screenshot(`compare-${label}`);
      if (!o.statusBar) ignoreTop = statusBarHeight(exec);
    } else {
      out.error('usage: expoemu compare NAME | expoemu compare A.png B.png [--threshold P] [--tolerance N] [--mask x1,y1,x2,y2] [--include-status-bar]');
      return 2;
    }
    for (const f of [aFile, bFile]) if (!fs.existsSync(f)) { out.error(`not found: ${f}`); return 2; }

    const a = png.decode(fs.readFileSync(aFile));
    const b = png.decode(fs.readFileSync(bFile));
    const masks = [...o.masks];
    if (ignoreTop) masks.push({ x1: 0, y1: 0, x2: b.width, y2: ignoreTop });
    const res = compareImages(a, b, { tolerance: o.tolerance, masks });
    if (res.sizeMismatch) {
      out.error(` ✗ Different sizes: ${res.a} vs ${res.b} — compare screenshots from the same device (use --device for per-device baselines)`);
      return 1;
    }

    const shotsDir = path.dirname(bFile);
    const diffFile = path.join(shotsDir, `diff-${label}-${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}.png`);
    fs.writeFileSync(diffFile, png.encode(res.diff));
    const pct = res.percent < 0.01 && res.changed ? '<0.01' : res.percent.toFixed(2);
    out.log(diffFile);
    const summary = `${pct}% of pixels differ (${res.changed} of ${res.compared}; threshold ${o.threshold}%)`;
    if (res.percent > o.threshold) {
      out.error(` ✗ ${label}: ${summary}\n   expected: ${aFile}\n   actual:   ${bFile}\n   diff:     ${diffFile} (red = changed)`);
      return 1;
    }
    out.error(` ✓ ${label}: ${summary}`);
    return 0;
  } catch (e) {
    out.error(`expoemu ${cmd}: ${e.message}`);
    return 1;
  }
}

module.exports = { compareImages, parseOptions, baselinePath, main };
