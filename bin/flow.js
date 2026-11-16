// =============================================================================
// expoemu flows: saved, repeatable UI tests made of expoemu commands.
//
//   expoemu run                     every .flow in ./.expoemu/flows/
//   expoemu run login.flow other/   specific files and/or folders
//   expoemu run --init              create ./.expoemu/flows/example.flow
//   options: --var KEY=VALUE (repeatable)  --bail  --report DIR
//
// A .flow file is one expoemu command per line (without the `expoemu`):
//
//   # Login with a wrong password shows an error      <- first comment = title
//   open
//   wait-for "Sign in" --timeout 30
//   fill "Email" "${EMAIL:-ada@example.com}"           <- ${VAR} / ${VAR:-default}
//   tap-text "Sign in"
//   wait-for "Invalid password"
//
// Each flow stops at its first failing step (exit code != 0), takes a failure
// screenshot and saves recent error logs. All flows run (unless --bail), then
// a report is written: report.json, junit.xml (for CI) and summary.md.
// Exit code: 0 if every flow passed, 1 otherwise.
// =============================================================================
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// Commands that make no sense (or are dangerous) inside a test flow.
const FORBIDDEN = new Set(['setup', 'cleanup', 'install', 'uninstall', 'update', 'run', 'device']);

// --- Parsing -------------------------------------------------------------------

// Shell-like split: "double" and 'single' quotes, backslash escapes outside
// single quotes. Throws on an unterminated quote.
function tokenize(line) {
  const tokens = [];
  let cur = '', inTok = false, quote = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quote) {
      if (c === quote) { quote = null; continue; }
      if (c === '\\' && quote === '"' && i + 1 < line.length) { cur += line[++i]; continue; }
      cur += c; continue;
    }
    if (c === '"' || c === "'") { quote = c; inTok = true; continue; }
    if (c === '\\' && i + 1 < line.length) { cur += line[++i]; inTok = true; continue; }
    if (/\s/.test(c)) { if (inTok) { tokens.push(cur); cur = ''; inTok = false; } continue; }
    cur += c; inTok = true;
  }
  if (quote) throw new Error(`unterminated ${quote} quote`);
  if (inTok) tokens.push(cur);
  return tokens;
}

// ${VAR} and ${VAR:-default}; an unset ${VAR} without default is an error.
function expand(token, vars) {
  return token.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}/g, (_, name, def) => {
    if (vars[name] !== undefined && vars[name] !== '') return vars[name];
    if (def !== undefined) return def;
    throw new Error(`variable \${${name}} is not set (use --var ${name}=… or \${${name}:-default})`);
  });
}

// Parse a .flow file into { title, steps: [{ line, text, args }] }.
function parseFlow(text, vars = {}) {
  let title = null;
  const steps = [];
  text.split(/\r?\n/).forEach((raw, idx) => {
    const line = raw.trim();
    if (!line) return;
    if (line.startsWith('#')) { if (title === null) title = line.replace(/^#+\s*/, ''); return; }
    let args;
    try {
      args = tokenize(line).map((t) => expand(t, vars));
    } catch (e) {
      throw new Error(`line ${idx + 1}: ${e.message}`);
    }
    if (args[0] === 'expoemu') args.shift();               // tolerate "expoemu tap …"
    if (!args.length) return;
    if (FORBIDDEN.has(args[0])) throw new Error(`line ${idx + 1}: "${args[0]}" is not allowed in a flow`);
    steps.push({ line: idx + 1, source: line, text: formatArgs(args), args });
  });
  return { title, steps };
}

// Show a step with its variables already expanded, quoting where needed.
function formatArgs(args) {
  return args.map((a) => (a === '' || /[\s"'\\$]/.test(a) ? JSON.stringify(a) : a)).join(' ');
}

// --- Files -----------------------------------------------------------------------

function findFlows(targets, cwd) {
  const list = targets.length ? targets : [path.join(cwd, '.expoemu', 'flows')];
  const files = [];
  for (const t of list) {
    const p = path.resolve(cwd, t);
    if (!fs.existsSync(p)) throw new Error(`not found: ${t}${targets.length ? '' : ' (create one with: expoemu run --init)'}`);
    if (fs.statSync(p).isDirectory()) {
      for (const f of fs.readdirSync(p).sort()) if (f.endsWith('.flow')) files.push(path.join(p, f));
    } else {
      files.push(p);
    }
  }
  if (!files.length) throw new Error('no .flow files found');
  return files;
}

const EXAMPLE = `# Example flow: the app opens and shows its first screen
# Run with: expoemu run          (all flows in .expoemu/flows/)
# One expoemu command per line; the flow stops at the first failing step.
open
wait-for "Welcome" --timeout 60
screenshot home
# fill "Email" "\${EMAIL:-ada@example.com}"
# tap-text "Sign in"
# assert-no-text "Error"
`;

// --- Reports ---------------------------------------------------------------------

const xml = (s) => String(s).replace(/[<>&"']/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' }[c]));

function junit(results) {
  const failures = results.filter((r) => !r.passed).length;
  const time = results.reduce((s, r) => s + r.seconds, 0).toFixed(2);
  const cases = results.map((r) => {
    const body = r.passed ? '' :
      `\n      <failure message="${xml(`step ${r.failedStep.line}: ${r.failedStep.text}`)}">${xml(r.failedOutput)}</failure>\n    `;
    return `    <testcase classname="expoemu.flows" name="${xml(r.name)}" time="${r.seconds.toFixed(2)}">${body}</testcase>`;
  }).join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<testsuites tests="${results.length}" failures="${failures}" time="${time}">\n  <testsuite name="expoemu" tests="${results.length}" failures="${failures}" time="${time}">\n${cases}\n  </testsuite>\n</testsuites>\n`;
}

function markdown(results) {
  const lines = ['| Flow | Result | Time |', '|------|--------|------|'];
  for (const r of results) {
    const res = r.passed ? '✅ pass' : `❌ step ${r.failedStep.line}: \`${r.failedStep.text}\``;
    lines.push(`| ${r.title || r.name} | ${res} | ${r.seconds.toFixed(1)} s |`);
  }
  return `# expoemu flow report\n\n${lines.join('\n')}\n`;
}

// --- Runner ------------------------------------------------------------------------

function run(argv, { bin, cwd = process.cwd(), out = console } = {}) {
  const vars = { ...process.env };
  const targets = [];
  let bail = false, reportDir = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--init') {
      const dir = path.join(cwd, '.expoemu', 'flows');
      const file = path.join(dir, 'example.flow');
      if (fs.existsSync(file)) { out.error(`exists: ${file}`); return 1; }
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(file, EXAMPLE);
      out.log(file);
      return 0;
    }
    if (a === '--bail') { bail = true; continue; }
    if (a === '--report') { reportDir = argv[++i]; continue; }
    if (a === '--var') {
      const m = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(argv[++i] || '');
      if (!m) { out.error('usage: --var KEY=VALUE'); return 2; }
      vars[m[1]] = m[2]; continue;
    }
    targets.push(a);
  }

  let files;
  try { files = findFlows(targets, cwd); } catch (e) { out.error(`expoemu run: ${e.message}`); return 2; }

  // Parse everything first: a typo in the last flow should not waste a run.
  const flows = [];
  for (const f of files) {
    try { flows.push({ file: f, ...parseFlow(fs.readFileSync(f, 'utf8'), vars) }); }
    catch (e) { out.error(`expoemu run: ${path.relative(cwd, f)}: ${e.message}`); return 2; }
  }

  const exec = (args) => spawnSync(process.execPath, [bin, ...args], {
    cwd, encoding: 'utf8', env: { ...process.env, EXPOEMU_NO_UPDATE_CHECK: '1', NO_COLOR: '1' },
  });

  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const dir = path.resolve(cwd, reportDir || path.join('.android-screenshots', 'runs', stamp));
  fs.mkdirSync(dir, { recursive: true });

  const results = [];
  for (const flow of flows) {
    const name = path.basename(flow.file, '.flow');
    out.log(`\n▶ ${name}${flow.title ? ` — ${flow.title}` : ''}`);
    const t0 = Date.now();
    const r = { name, title: flow.title, file: path.relative(cwd, flow.file), passed: true, steps: [] };
    for (const step of flow.steps) {
      const s0 = Date.now();
      const res = exec(step.args);
      const seconds = (Date.now() - s0) / 1000;
      const output = `${res.stdout || ''}${res.stderr || ''}`.trim();
      const ok = res.status === 0;
      r.steps.push({ line: step.line, command: step.text, passed: ok, seconds, output });
      out.log(`  ${ok ? '✓' : '✗'} ${step.text}  (${seconds.toFixed(1)} s)`);
      if (!ok) {
        r.passed = false;
        r.failedStep = step;
        r.failedOutput = output;
        out.log(output.split('\n').slice(-5).map((l) => `      ${l}`).join('\n'));
        // Evidence for whoever reads the report: screen + recent errors.
        const shot = exec(['screenshot', `failure-${name}-line${step.line}`]);
        if (shot.status === 0) r.failureScreenshot = shot.stdout.trim();
        const logs = exec(['logcat', '--errors', '-n', '40']);
        if (logs.status === 0) {
          r.failureLog = path.join(dir, `${name}-errors.log`);
          fs.writeFileSync(r.failureLog, logs.stdout);
        }
        if (r.failureScreenshot) out.log(`      screenshot: ${r.failureScreenshot}`);
        break;
      }
    }
    r.seconds = (Date.now() - t0) / 1000;
    results.push(r);
    if (!r.passed && bail) break;
  }

  fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify({ results }, null, 2));
  fs.writeFileSync(path.join(dir, 'junit.xml'), junit(results));
  fs.writeFileSync(path.join(dir, 'summary.md'), markdown(results));

  const failed = results.filter((r) => !r.passed).length;
  out.log(`\n${failed ? '✗' : '✓'} ${results.length - failed}/${results.length} flow(s) passed — report: ${path.relative(cwd, dir) || dir}`);
  return failed ? 1 : 0;
}

module.exports = { tokenize, expand, parseFlow, formatArgs, findFlows, junit, markdown, run, FORBIDDEN };
