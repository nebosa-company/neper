// Reference vectors for `e.algo.journal` (L036, the runtime half): drive appdor's own run journal (src/workflow/journal.js)
// through random operation scripts -- run creation, commits with entries, header patches, stale and tampered writes,
// index queries, summaries, clock recording and the in-memory store (create with unique keys, load, commit, due, list)
// -- and write the link fixture tests/selfhost/fixtures/link/algo_journal. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const j = await import(pathToFileURL(resolve(appdor, 'src/workflow/journal.js')).href);

let seed = 0x7036a;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

// A canonical rendering: keys sorted, undefined members dropped (as JSON.stringify drops them).
function canon(v) {
  if (v === undefined) return 'undefined';
  const walk = (x) => {
    if (Array.isArray(x)) return x.map(walk);
    if (x && typeof x === 'object') {
      const out = {};
      for (const k of Object.keys(x).sort()) if (x[k] !== undefined) out[k] = walk(x[k]);
      return out;
    }
    return x;
  };
  return JSON.stringify(walk(v));
}

const KEYS = ['a', 'b', 'c', 'step.1', 'loop:2'];
const TYPES = ['run-started', 'step-started', 'step-completed', 'step-failed', 'step-skipped', 'branch-taken', 'loop-started',
  'fork-started', 'fork-branch-completed', 'timer-set', 'timer-fired', 'signal-awaited', 'signal-received', 'clock', 'random',
  'var-set', 'effect-recorded', 'run-paused', 'run-resumed', 'run-cancelled', 'run-completed', 'run-failed', 'run-retried'];
const STATUS = ['pending', 'running', 'suspended', 'paused', 'succeeded', 'failed', 'cancelled'];

function anyValue(depth = 0) {
  const r = rnd();
  if (r < 0.15) return null;
  if (r < 0.3) return chance(0.5);
  if (r < 0.55) return int(100);
  if (r < 0.8 || depth > 1) return pick(['x', 'ok', 'ünï', '', 'retry later']);
  if (r < 0.9) return [anyValue(depth + 1), anyValue(depth + 1)];
  return { v: anyValue(depth + 1), n: int(5) };
}

function entrySpec() {
  const type = chance(0.03) ? 'bogus-type' : pick(TYPES);
  const f = {};
  if (chance(0.85)) f.key = pick(KEYS);
  if (type === 'step-completed' && chance(0.85)) f.result = anyValue();
  if (type === 'fork-branch-completed') { if (chance(0.7)) f.branch = pick(['left', 'right', 'mid']); if (chance(0.3)) { delete f.key; f.stepId = pick(KEYS); } }
  if ((type === 'clock' || type === 'random') && chance(0.85)) f.value = anyValue();
  if (type === 'signal-received') f.payload = anyValue();
  if (chance(0.1)) f.attempt = int(4);
  if (chance(0.04)) f.rev = 999;
  if (chance(0.03)) f.type = 'hijack';
  if (chance(0.03)) f.seq = 77;
  return { type, fields: f };
}

function workflowSpec() {
  const w = {};
  if (chance(0.8)) w.id = pick(['wf-a', 'wf-b', 'wf-c']);
  if (chance(0.7)) w.version = pick([1, 2, 3, 0]);
  if (chance(0.7)) w.trigger = { type: pick(['manual', 'schedule', 'record.created', '']) };
  return w;
}
function triggerSpec() {
  const t = {};
  if (chance(0.5)) t.payload = pick([{ id: 1 }, {}, null, 0, { r: 'x' }]);
  if (chance(0.4)) t.meta = pick([{ source: 'ui' }, null, '']);
  if (chance(0.5)) t.input = pick([{ n: 1 }, null, { a: [1, 2] }]);
  return t;
}
function optionsSpec() {
  const o = {};
  if (chance(0.5)) o.runId = pick(['r-1', 'r-2', '', 'run-x']);
  if (chance(0.4)) o.tableId = pick(['t1', '', null]);
  if (chance(0.3)) o.applicationId = pick(['app', null]);
  if (chance(0.4)) o.createdBy = pick(['u1', null]);
  if (chance(0.3)) o.changeId = pick(['c1', 'c2']);
  if (chance(0.25)) o.batchId = pick(['b1', 'b2']);
  if (chance(0.25)) o.scheduleOccurrence = pick(['2026-01-01T00:00', '2026-01-02T00:00']);
  if (chance(0.4)) o.now = pick([1000, 2000, 0, null]);
  if (chance(0.3)) o.defer = pick([true, false, 'yes']);
  if (chance(0.3)) o.mode = pick(['dry-run', 'live', 'other']);
  return o;
}
function patchSpec() {
  const p = {};
  if (chance(0.5)) p.status = pick(STATUS);
  if (chance(0.3)) p.finishedAt = int(5000);
  if (chance(0.3)) p.waiting = pick([null, { kind: 'timer', wakeAt: int(3000) }, { kind: 'signal', signal: 'go', timeoutAt: int(3000) }, { kind: 'signal', signal: 'x' }]);
  if (chance(0.2)) p.error = pick(['boom', null]);
  if (chance(0.2)) p.metered = 1;
  if (chance(0.15)) p.startedAt = int(2000);
  return p;
}
function headerSpec() {
  const h = {};
  if (chance(0.5)) h.status = pick(['suspended', 'suspended', 'running', 'pending']);
  if (chance(0.5)) h.waiting = pick([{ kind: 'timer', wakeAt: int(3000) }, { kind: 'signal', signal: 's', timeoutAt: int(3000) }, { kind: 'signal', signal: 's' }, null]);
  return h;
}

// A commit as the scenarios build it: entries added in order, a header patch, the optional rebase, expected override and
// tamper. An unknown entry type is the JavaScript throw, reported as `error:unknown-journal-entry-type`.
function buildCommit(run, spec) {
  const c = j.beginCommit(run);
  for (const e of spec.entries || []) {
    try { c.add(e.type, e.fields); } catch (err) { return { error: 'unknown-journal-entry-type' }; }
  }
  if (spec.patch) c.setHeader(spec.patch);
  if (spec.rebase != null) c.rebase({ seq: spec.rebase });
  const built = c.build();
  if (spec.expected != null) built.expectedSeq = spec.expected;
  if (spec.tamper && built.entries[spec.tamper.index]) built.entries[spec.tamper.index].seq = spec.tamper.seq;
  return { built };
}

async function scenario() {
  const ops = [];
  const out = [];
  let run = null;
  const prefix = pick(['run', 'r']);
  const store = j.createMemoryStore({ idPrefix: prefix });
  let created = 0;
  const note = (op, text) => { ops.push(op); out.push(text); };
  const create = () => {
    const spec = { workflow: workflowSpec(), trigger: triggerSpec(), options: optionsSpec() };
    run = j.createRun(spec.workflow, spec.trigger, spec.options);
    note({ op: 'create', ...spec }, canon(run));
  };
  create();
  const steps = int(14) + 4;
  for (let i = 0; i < steps; i++) {
    const r = rnd();
    if (r < 0.3) {
      const spec = { entries: Array.from({ length: int(4) }, entrySpec), patch: chance(0.6) ? patchSpec() : null };
      if (chance(0.12)) spec.expected = Math.max(0, run.seq + pick([-1, 1, 3]));
      if (chance(0.08)) spec.rebase = int(5);
      if (chance(0.06) && spec.entries.length) spec.tamper = { index: int(spec.entries.length), seq: pick([5, 0, 100]) };
      const built = buildCommit(run, spec);
      if (built.error) { note({ op: 'apply', ...spec }, 'error:' + built.error); continue; }
      const res = j.applyCommit(run, built.built);
      if (res.ok) run = res.run;
      note({ op: 'apply', ...spec }, canon(res));
    } else if (r < 0.52) {
      const name = pick(['result', 'isComplete', 'skipped', 'started', 'branch', 'loop', 'forkBranches', 'failureCount', 'lastFailure', 'signal', 'hasSignal', 'timerFired', 'recorded', 'hasRecorded', 'size']);
      const key = pick(KEYS.concat(['missing']));
      const q = j.journalIndex(run)[name];
      note({ op: 'q', name, key }, canon(typeof q === 'function' ? q(key) : q));
    } else if (r < 0.58) {
      note({ op: 'summary' }, canon(j.summarizeRun(run)));
    } else if (r < 0.66) {
      const key = pick(KEYS);
      const now = int(9000);
      const c = j.beginCommit(run);
      const value = j.recordClock(key, j.journalIndex(run), c, () => now);
      let wrote = false;
      if (!c.isEmpty) { const res = j.applyCommit(run, c.build()); if (res.ok) { run = res.run; wrote = true; } }
      note({ op: 'clock', key, now }, canon({ value, wrote }));
    } else if (r < 0.78) {
      const spec = { workflow: workflowSpec(), trigger: triggerSpec(), options: optionsSpec(), header: chance(0.5) ? headerSpec() : {} };
      const fresh = Object.assign(j.createRun(spec.workflow, spec.trigger, spec.options), spec.header);
      const stored = await store.create(fresh);
      created++;
      note({ op: 's_create', ...spec }, canon(stored));
    } else if (r < 0.84) {
      const list = await store.list();
      const id = list.length && chance(0.8) ? pick(list).runId : 'nope';
      note({ op: 's_load', id }, canon(await store.load(id)));
    } else if (r < 0.92) {
      const list = await store.list();
      const id = list.length && chance(0.85) ? pick(list).runId : 'nope';
      const loaded = await store.load(id);
      const spec = { id, entries: Array.from({ length: int(3) }, entrySpec), patch: chance(0.6) ? patchSpec() : null };
      if (chance(0.15)) spec.expected = int(5);
      if (!loaded) { note({ op: 's_commit', ...spec }, canon(await store.commit(id, { expectedSeq: 0, entries: [], patch: {} }))); continue; }
      const built = buildCommit(loaded, spec);
      if (built.error) { note({ op: 's_commit', ...spec }, 'error:' + built.error); continue; }
      note({ op: 's_commit', ...spec }, canon(await store.commit(id, built.built)));
    } else if (r < 0.97) {
      const now = int(4000);
      const limit = pick([undefined, 1, 2, 0, 100]);
      const spec = { now };
      if (limit !== undefined) spec.limit = limit;
      note({ op: 's_due', ...spec }, canon(await store.due(now, limit)));
    } else {
      note({ op: 's_list' }, canon(await store.list()));
    }
  }
  return { prefix, ops, e: out.join('\n') };
}

const cases = [];
for (let i = 0; i < 160; i++) cases.push(JSON.stringify(await scenario()));

const chunks = [];
const size = 4;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'journal_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_journal/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_journal`);
