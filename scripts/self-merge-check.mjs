#!/usr/bin/env node
// Decide whether an upstream maintainer's `/merge` may merge a PR without a
// FlatPark maintainer's review. Used by .github/workflows/self-merge.yml.
//
//   self-merge-check.mjs <base-sha> <head-sha> <commenter-user-id>
//
// <base-sha> is the PR's merge-base with main; the diff base..head is exactly
// what the PR changes. The maintainer list and the "app already exists" test
// are read from the CHECKED-OUT tree (main), never from the PR, so a PR cannot
// grant itself rights.
//
// The self-merge surface ("option A"): everything inside registry/<id>/ of an
// app the commenter maintains, EXCEPT what runs as code in trusted CI.
//
//   - resolve-update.sh, and flatpark.yml's `update:` section. check-updates.sh
//     `eval`s them in update-check.yml on a contents:write token that can open
//     and merge PRs — the same line pr-checks' guard-infra draws.
//   - the build recipe. Every other *.yml/*.yaml/*.json in the app dir is a
//     manifest (or a module file), built in publish.yml next to the signing key
//     and the R2 credentials. Outside `finish-args` and the MANAGED EXTRA-DATA
//     block it must stay byte-identical, comments and blank lines aside. The
//     managed block may only carry extra-data sources with the six keys
//     update-pins.mjs writes — extra-data is fetched on the user's machine at
//     install time, never in CI. A new manifest-like file is refused outright.
//   - adding or removing an app. A self-merge edits an app already on main; it
//     never creates, renames or de-lists one.
//
// Local files the recipe installs (wrapper, apply_extra.sh, desktop, metainfo,
// icons) are in the surface: they are copied into /app by build-commands that
// cannot change, inside flatpak-builder's sandbox, and they run on users'
// machines with the same trust users already place in the upstream binary.
//
// Prints a markdown reason list on stdout. Exit 0 = allowed, 1 = refused,
// 2 = usage / environment error.
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MAINTAINERS = join(ROOT, 'config/maintainers.yml');
const BEGIN = '# BEGIN MANAGED EXTRA-DATA';
const END = '# END MANAGED EXTRA-DATA';
const MANAGED_KEYS = new Set(['type', 'filename', 'only-arches', 'url', 'sha256', 'size']);
const ARCHES = new Set(['x86_64', 'aarch64']);

const [base, head, userId] = process.argv.slice(2);
if (!base || !head || !/^\d+$/.test(userId || '')) {
  process.stderr.write('usage: self-merge-check.mjs <base-sha> <head-sha> <commenter-user-id>\n');
  process.exit(2);
}

function git(...args) {
  const r = spawnSync('git', ['-C', ROOT, ...args], { encoding: 'utf8', maxBuffer: 64 << 20 });
  if (r.status !== 0) {
    process.stderr.write(`git ${args.join(' ')} failed: ${r.stderr}`);
    process.exit(2);
  }
  return r.stdout;
}
const show = (rev, path) => git('show', `${rev}:${path}`);

// config/maintainers.yml: `<app-id>:` then `- login: x` / `id: N` pairs. Only
// the numeric id is authoritative — a login can be renamed and re-registered.
function parseMaintainers(text) {
  const apps = new Map();
  let app = null;
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\s+#.*$/, '').replace(/^#.*$/, '');
    if (!line.trim()) continue;
    let m;
    if ((m = line.match(/^([A-Za-z0-9._-]+):\s*$/))) {
      app = m[1];
      apps.set(app, new Set());
    } else if (app && (m = line.match(/^\s+(?:-\s+)?id:\s*(\d+)\s*$/))) {
      apps.get(app).add(m[1]);
    }
  }
  return apps;
}

// Drop comments and blank lines, and the lines inside the regions a
// maintainer may change, so what is left can be compared verbatim.
function skeleton(text, { finishArgs = false, managed = false, keepOnly = null } = {}) {
  const out = [];
  let inManaged = false;
  let top = null; // current top-level key
  for (const raw of text.split('\n')) {
    const t = raw.trim();
    if (t === BEGIN) { inManaged = true; if (managed) continue; }
    if (t === END) { inManaged = false; if (managed) continue; }
    if (managed && inManaged) continue;
    if (t === '' || t.startsWith('#')) continue;
    const m = raw.match(/^([A-Za-z0-9_-]+):/);
    if (m) top = m[1];
    if (finishArgs && top === 'finish-args') continue;
    if (keepOnly && top !== keepOnly) continue;
    out.push(raw.replace(/\s+$/, ''));
  }
  return out.join('\n');
}

// Everything a PR may put inside the MANAGED block: extra-data list items with
// the keys update-pins.mjs writes, indented at least as deep as the first item
// so nothing can climb out of `sources:` into the module.
function managedProblems(text) {
  const problems = [];
  let inManaged = false;
  let indent = null;
  for (const raw of text.split('\n')) {
    const t = raw.trim();
    if (t === BEGIN) { inManaged = true; indent = null; continue; }
    if (t === END) { inManaged = false; continue; }
    if (!inManaged || t === '' || t.startsWith('#')) continue;
    const lead = raw.length - raw.trimStart().length;
    if (indent === null) indent = lead;
    if (lead < indent) { problems.push(`line escapes the managed block: \`${t}\``); continue; }
    if (t.startsWith('- ') && ARCHES.has(t.slice(2).trim())) continue;
    const m = t.match(/^(?:-\s+)?([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m || !MANAGED_KEYS.has(m[1])) { problems.push(`unexpected line in the managed block: \`${t}\``); continue; }
    if (m[1] === 'type' && m[2] !== 'extra-data') problems.push(`managed source is not extra-data: \`${t}\``);
  }
  return problems;
}

const reasons = [];
const refuse = (msg) => reasons.push(msg);

const maintainers = parseMaintainers(readFileSync(MAINTAINERS, 'utf8'));
const mine = new Set([...maintainers].filter(([, ids]) => ids.has(userId)).map(([app]) => app));
if (mine.size === 0) {
  process.stdout.write('- You are not listed as a maintainer of any app in `config/maintainers.yml`.\n');
  process.exit(1);
}

const changes = git('diff', '--name-status', '--no-renames', base, head)
  .split('\n').filter(Boolean).map((l) => l.split('\t'));
if (changes.length === 0) refuse('The PR changes nothing.');

const onMain = (path) => spawnSync('git', ['-C', ROOT, 'cat-file', '-e', `HEAD:${path}`]).status === 0;
const apps = new Set();

for (const [status, path] of changes) {
  const m = path.match(/^registry\/([^/]+)\/(.+)$/);
  if (!m) { refuse(`\`${path}\` is outside registry/<app-id>/.`); continue; }
  const [, id, rel] = m;
  apps.add(id);
  if (!mine.has(id)) { refuse(`\`${path}\` belongs to \`${id}\`, which you do not maintain.`); continue; }
  if (!onMain(`registry/${id}/flatpark.yml`)) { refuse(`\`${id}\` is not on main — adding an app needs a maintainer review.`); continue; }

  if (rel === 'resolve-update.sh') {
    refuse(`\`${path}\`: the update resolver runs in CI with a write token, so changes to it need a maintainer review.`);
  } else if (rel === 'flatpark.yml') {
    if (status === 'D') { refuse(`\`${path}\` is deleted — de-listing needs a maintainer review.`); continue; }
    if (status === 'M' && skeleton(show(base, path), { keepOnly: 'update' }) !== skeleton(show(head, path), { keepOnly: 'update' })) {
      refuse(`\`${path}\`: the \`update:\` section runs in CI with a write token, so changes to it need a maintainer review.`);
    }
  } else if (!rel.includes('/') && /\.(ya?ml|json)$/.test(rel)) {
    if (status !== 'M') { refuse(`\`${path}\` is ${status === 'A' ? 'a new' : 'a deleted'} manifest file — build recipe changes need a maintainer review.`); continue; }
    const before = show(base, path);
    const after = show(head, path);
    if (skeleton(before, { finishArgs: true, managed: true }) !== skeleton(after, { finishArgs: true, managed: true })) {
      refuse(`\`${path}\`: only \`finish-args\` and the MANAGED EXTRA-DATA block may change — build steps, modules and non-extra-data sources need a maintainer review.`);
    }
    const markers = (x) => x.split('\n').filter((l) => l.trim() === BEGIN).length;
    if (markers(after) !== markers(before)) refuse(`\`${path}\`: the number of MANAGED EXTRA-DATA blocks changed.`);
    for (const p of managedProblems(after)) refuse(`\`${path}\`: ${p}`);
    const fa = after.split('\n');
    let inFa = false;
    for (const raw of fa) {
      if (/^[A-Za-z0-9_-]+:/.test(raw)) inFa = raw.startsWith('finish-args:');
      else if (inFa && raw.trim() && !raw.trim().startsWith('#') && !/^\s+-\s/.test(raw)) {
        refuse(`\`${path}\`: unexpected line under finish-args: \`${raw.trim()}\``);
      }
    }
  }
}

if (reasons.length) {
  process.stdout.write(reasons.map((r) => `- ${r}`).join('\n') + '\n');
  process.exit(1);
}
process.stdout.write(`- Every change is inside ${[...apps].map((a) => `\`registry/${a}/\``).join(', ')}, within the self-merge surface.\n`);
