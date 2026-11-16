// Tests for bin/flow.js (saved test flows) — parsing and reports, no device needed.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { tokenize, expand, parseFlow, findFlows, junit, run } = require('../bin/flow.js');
const { COMMANDS, BUILTINS } = require('../bin/expoemu.js');

test('tokenize: quotes, escapes, spaces', () => {
  assert.deepStrictEqual(tokenize('tap-text "Sign in"'), ['tap-text', 'Sign in']);
  assert.deepStrictEqual(tokenize(`fill 'Email' "a b"`), ['fill', 'Email', 'a b']);
  assert.deepStrictEqual(tokenize('text "say \\"hi\\""'), ['text', 'say "hi"']);
  assert.deepStrictEqual(tokenize('wait-for  Welcome   --timeout 30'), ['wait-for', 'Welcome', '--timeout', '30']);
  assert.deepStrictEqual(tokenize('text ""'), ['text', '']);
  assert.throws(() => tokenize('tap-text "oops'), /unterminated/);
});

test('expand: variables and defaults', () => {
  assert.strictEqual(expand('${EMAIL}', { EMAIL: 'a@x.com' }), 'a@x.com');
  assert.strictEqual(expand('${EMAIL:-d@x.com}', {}), 'd@x.com');
  assert.strictEqual(expand('user-${N:-1}-x', { N: '7' }), 'user-7-x');
  assert.throws(() => expand('${MISSING}', {}), /not set/);
});

test('parseFlow: title, comments, steps, forbidden commands', () => {
  const flow = parseFlow('# Login works\n\nopen\n# a comment\nexpoemu wait-for "Sign in" --timeout 30\nfill "Email" "${E:-a@x}"\n', {});
  assert.strictEqual(flow.title, 'Login works');
  assert.deepStrictEqual(flow.steps.map((s) => s.args), [
    ['open'], ['wait-for', 'Sign in', '--timeout', '30'], ['fill', 'Email', 'a@x'],
  ]);
  assert.strictEqual(flow.steps[1].line, 5);
  assert.throws(() => parseFlow('cleanup --all\n'), /line 1: "cleanup" is not allowed/);
  assert.throws(() => parseFlow('open\nrun other.flow\n'), /line 2/);
});

test('every step command in the example flow exists', () => {
  const known = new Set([...Object.keys(COMMANDS), ...BUILTINS]);
  const flow = parseFlow(fs.readFileSync(path.join(__dirname, '..', 'bin', 'flow.js'), 'utf8')
    .match(/const EXAMPLE = `([\s\S]*?)`;/)[1].replace(/\\\$/g, '$'), {});
  for (const s of flow.steps) assert.ok(known.has(s.args[0]), s.args[0]);
});

test('findFlows: default folder, directories sorted, errors', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'flows-'));
  fs.mkdirSync(path.join(dir, '.expoemu', 'flows'), { recursive: true });
  for (const f of ['b.flow', 'a.flow', 'notes.txt']) fs.writeFileSync(path.join(dir, '.expoemu', 'flows', f), 'open\n');
  assert.deepStrictEqual(findFlows([], dir).map((f) => path.basename(f)), ['a.flow', 'b.flow']);
  assert.throws(() => findFlows(['nope.flow'], dir), /not found/);
});

test('junit report marks failures', () => {
  const xmlOut = junit([
    { name: 'ok', passed: true, seconds: 1 },
    { name: 'bad', passed: false, seconds: 2, failedStep: { line: 3, text: 'wait-for "<X>"' }, failedOutput: 'Timed out' },
  ]);
  assert.match(xmlOut, /tests="2" failures="1"/);
  assert.match(xmlOut, /<failure message="step 3: wait-for &quot;&lt;X&gt;&quot;">Timed out<\/failure>/);
});

test('run --init writes an example and refuses to overwrite', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'flows-init-'));
  const quiet = { log() {}, error() {} };
  assert.strictEqual(run(['--init'], { bin: 'unused', cwd: dir, out: quiet }), 0);
  assert.ok(fs.existsSync(path.join(dir, '.expoemu', 'flows', 'example.flow')));
  assert.strictEqual(run(['--init'], { bin: 'unused', cwd: dir, out: quiet }), 1);
});
