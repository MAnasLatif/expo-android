// Validates skills/expoemu against the Agent Skills spec (agentskills.io),
// skills.sh conventions and Anthropic's authoring best practices, and keeps
// the skill in sync with the real CLI commands.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { COMMANDS } = require('../bin/expoemu.js');

const SKILL_DIR = path.join(__dirname, '..', 'skills', 'expoemu');
const skillMd = fs.readFileSync(path.join(SKILL_DIR, 'SKILL.md'), 'utf8');
const CLI = new Set([...Object.keys(COMMANDS), 'up', 'emulator', 'help']);

// Minimal frontmatter parser: top-level "key: value" plus one nested map.
function frontmatter(text) {
  const m = /^---\n([\s\S]*?)\n---\n/.exec(text);
  assert.ok(m, 'SKILL.md must start with YAML frontmatter');
  const out = {};
  let parent = null;
  for (const line of m[1].split('\n')) {
    const nested = /^ {2}([\w-]+):\s*(.*)$/.exec(line);
    const top = /^([\w-]+):\s*(.*)$/.exec(line);
    if (nested && parent) out[parent][nested[1]] = nested[2].replace(/^"|"$/g, '');
    else if (top) {
      parent = top[2] === '' ? top[1] : null;
      out[top[1]] = top[2] === '' ? {} : top[2];
    }
  }
  return { data: out, body: text.slice(m[0].length) };
}

const { data: fm, body } = frontmatter(skillMd);
const files = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
  e.isDirectory() ? files(path.join(dir, e.name)) : [path.join(dir, e.name)]);
const skillTexts = files(SKILL_DIR).filter((f) => f.endsWith('.md')).map((f) => fs.readFileSync(f, 'utf8'));

test('name follows the spec and matches its folder', () => {
  assert.match(fm.name, /^[a-z0-9]+(-[a-z0-9]+)*$/, 'lowercase letters, digits, single hyphens');
  assert.ok(fm.name.length <= 64);
  assert.strictEqual(fm.name, path.basename(SKILL_DIR));
  assert.doesNotMatch(fm.name, /anthropic|claude/, 'reserved words');
});

test('description: present, <= 1024 chars, third person, says when to use', () => {
  assert.ok(fm.description && fm.description.length > 50);
  assert.ok(fm.description.length <= 1024, `description is ${fm.description.length} chars`);
  assert.doesNotMatch(fm.description, /<[^>]+>/, 'no XML tags');
  assert.doesNotMatch(fm.description, /^(I|You|We)\b/, 'third person');
  assert.match(fm.description, /Use when/, 'states when to use it');
});

test('optional fields are within limits', () => {
  assert.ok(!fm.compatibility || fm.compatibility.length <= 500);
  assert.strictEqual(fm.license, 'MIT');
  assert.ok(fm.metadata && fm.metadata.version, 'metadata.version');
});

test('SKILL.md body stays under 500 lines', () => {
  assert.ok(body.split('\n').length < 500);
});

test('references exist, are one level deep, long ones have contents', () => {
  const links = [...skillMd.matchAll(/\]\((references\/[^)]+)\)/g)].map((m) => m[1]);
  assert.ok(links.length >= 3, 'SKILL.md links its references');
  for (const rel of links) {
    assert.match(rel, /^references\/[^/]+\.md$/, `${rel} must be one level deep`);
    const text = fs.readFileSync(path.join(SKILL_DIR, rel), 'utf8');
    if (text.split('\n').length > 100) assert.match(text, /## Contents/, `${rel} needs a table of contents`);
  }
});

test('every `npx expoemu <cmd>` in the skill is a real CLI command', () => {
  for (const text of skillTexts) {
    for (const m of text.matchAll(/npx (?:-y )?expoemu (?:--device \S+ )?([a-z][a-z-]*)/g)) {
      assert.ok(CLI.has(m[1]), `unknown command in skill: ${m[1]}`);
    }
  }
});

test('every CLI command is documented in references/commands.md', () => {
  const ref = fs.readFileSync(path.join(SKILL_DIR, 'references', 'commands.md'), 'utf8');
  for (const cmd of CLI) {
    assert.match(ref, new RegExp('`' + cmd.replace(/-/g, '\\-') + '[ `]'), `commands.md is missing "${cmd}"`);
  }
});

test('evals are valid', () => {
  const evals = JSON.parse(fs.readFileSync(path.join(SKILL_DIR, 'evals', 'evals.json'), 'utf8'));
  assert.strictEqual(evals.skill_name, fm.name);
  assert.ok(evals.evals.length >= 3);
  for (const e of evals.evals) assert.ok(e.prompt && e.expected_behavior.length);
});
