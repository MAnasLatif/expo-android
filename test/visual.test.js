// Tests for bin/png.js and bin/visual.js (screenshot comparison), no device needed.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const png = require('../bin/png.js');
const { compareImages, parseOptions, baselinePath, main } = require('../bin/visual.js');

// Solid-colour RGBA image with an optional coloured square.
function image(w, h, rgb, square) {
  const data = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) { data[i * 4] = rgb[0]; data[i * 4 + 1] = rgb[1]; data[i * 4 + 2] = rgb[2]; data[i * 4 + 3] = 255; }
  if (square) {
    for (let y = square.y; y < square.y + square.size; y++) {
      for (let x = square.x; x < square.x + square.size; x++) {
        const i = (y * w + x) * 4; data[i] = square.rgb[0]; data[i + 1] = square.rgb[1]; data[i + 2] = square.rgb[2];
      }
    }
  }
  return { width: w, height: h, data };
}

test('PNG encode/decode round-trip (RGBA)', () => {
  const img = image(17, 9, [10, 200, 30], { x: 2, y: 2, size: 4, rgb: [250, 0, 0] });
  const back = png.decode(png.encode(img));
  assert.strictEqual(back.width, 17);
  assert.strictEqual(back.height, 9);
  assert.ok(back.data.equals(img.data));
});

test('PNG decode handles RGB and all row filters', () => {
  // Hand-made 3x2 RGB image using filters Sub (1) and Paeth (4).
  const w = 3, h = 2, rows = [];
  const pixels = [[[10, 20, 30], [40, 50, 60], [70, 80, 90]], [[15, 25, 35], [45, 55, 65], [75, 85, 95]]];
  // row 0, filter Sub: each byte minus the byte 3 to the left
  const r0 = [1]; pixels[0].flat().forEach((v, i, a) => r0.push((v - (i >= 3 ? a[i - 3] : 0)) & 255));
  // row 1, filter Up: each byte minus the byte above
  const r1 = [2]; pixels[1].flat().forEach((v, i) => r1.push((v - pixels[0].flat()[i]) & 255));
  rows.push(...r0, ...r1);
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const chunk = (k, b) => { const l = Buffer.alloc(4); l.writeUInt32BE(b.length); const c = Buffer.alloc(4); c.writeUInt32BE(png.crc32(Buffer.concat([Buffer.from(k), b]))); return Buffer.concat([l, Buffer.from(k), b, c]); };
  const file = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(Buffer.from(rows))), chunk('IEND', Buffer.alloc(0))]);
  const img = png.decode(file);
  assert.deepStrictEqual([...img.data.subarray(0, 4)], [10, 20, 30, 255]);
  assert.deepStrictEqual([...img.data.subarray(20, 24)], [75, 85, 95, 255]);
});

test('identical images: 0% changed', () => {
  const a = image(20, 20, [255, 255, 255]);
  const r = compareImages(a, image(20, 20, [255, 255, 255]));
  assert.strictEqual(r.changed, 0);
  assert.strictEqual(r.percent, 0);
});

test('changed square is counted and drawn red; tolerance ignores noise', () => {
  const a = image(20, 20, [255, 255, 255]);
  const b = image(20, 20, [255, 255, 255], { x: 0, y: 0, size: 2, rgb: [0, 0, 0] });
  const r = compareImages(a, b);
  assert.strictEqual(r.changed, 4);
  assert.strictEqual(r.percent, 1);
  assert.deepStrictEqual([...r.diff.data.subarray(0, 4)], [255, 0, 0, 255]);
  const noisy = image(20, 20, [250, 250, 250]);
  assert.strictEqual(compareImages(a, noisy, { tolerance: 16 }).changed, 0);
  assert.strictEqual(compareImages(a, noisy, { tolerance: 2 }).changed, 400);
});

test('masks are skipped; size mismatch is reported', () => {
  const a = image(20, 20, [255, 255, 255]);
  const b = image(20, 20, [255, 255, 255], { x: 0, y: 0, size: 4, rgb: [0, 0, 0] });
  const r = compareImages(a, b, { masks: [{ x1: 0, y1: 0, x2: 20, y2: 5 }] });
  assert.strictEqual(r.changed, 0);
  assert.strictEqual(r.compared, 300);
  assert.deepStrictEqual(compareImages(a, image(10, 10, [0, 0, 0])), { sizeMismatch: true, a: '20x20', b: '10x10' });
});

test('options and per-device baseline paths', () => {
  const o = parseOptions(['home', '--threshold', '0.5', '--mask', '0,0,100,50', '--include-status-bar']);
  assert.deepStrictEqual([o.positional, o.threshold, o.masks, o.statusBar], [['home'], 0.5, [{ x1: 0, y1: 0, x2: 100, y2: 50 }], true]);
  assert.throws(() => parseOptions(['--mask', 'x']), /x1,y1,x2,y2/);
  const prev = process.env.EXPOEMU_DEVICE;
  delete process.env.EXPOEMU_DEVICE;
  assert.strictEqual(baselinePath('/p', 'home'), path.join('/p', '.expoemu', 'baselines', 'home.png'));
  process.env.EXPOEMU_DEVICE = 'tablet';
  assert.strictEqual(baselinePath('/p', 'home'), path.join('/p', '.expoemu', 'baselines', 'tablet', 'home.png'));
  if (prev === undefined) delete process.env.EXPOEMU_DEVICE; else process.env.EXPOEMU_DEVICE = prev;
});

test('compare two files from the CLI module: exit codes and diff file', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'visual-'));
  fs.writeFileSync(path.join(dir, 'a.png'), png.encode(image(40, 40, [255, 255, 255])));
  fs.writeFileSync(path.join(dir, 'b.png'), png.encode(image(40, 40, [255, 255, 255], { x: 0, y: 0, size: 10, rgb: [0, 0, 0] })));
  const quiet = { lines: [], log(s) { this.lines.push(s); }, error() {} };
  assert.strictEqual(main('compare', ['a.png', 'a.png'], { bin: 'unused', cwd: dir, out: quiet }), 0);
  assert.strictEqual(main('compare', ['a.png', 'b.png'], { bin: 'unused', cwd: dir, out: quiet }), 1);
  assert.strictEqual(main('compare', ['a.png', 'b.png', '--threshold', '10'], { bin: 'unused', cwd: dir, out: quiet }), 0);
  assert.ok(fs.existsSync(quiet.lines.pop()), 'diff image written');
});
