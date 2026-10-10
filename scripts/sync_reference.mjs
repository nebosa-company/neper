// Reference vectors for `e.algo.sync` (L037): run appdor's own offline modules (src/offline/index.js,
// durable-queue.js, sync-engine.js) over random operation scripts -- the coalescing queue, the durable outbox over a
// memory store with scripted save failures, the cursor, delta pulls and applies, field-level conflict detection and
// resolution, and full syncs -- and write the link fixture tests/selfhost/fixtures/link/algo_sync.
// APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const off = await load('src/offline/index.js');
const dq = await load('src/offline/durable-queue.js');
const se = await load('src/offline/sync-engine.js');

let seed = 0x5a17;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

function canon(v) {
  if (v === undefined) return 'null';
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

const RIDS = ['r1', 'r2', 'r3', 'r4'];
const TABLES = ['tasks', 'notes'];
const VALS = [null, 'x', 'y', 1, 2, true, [1], { k: 1 }];
const genPayload = () => { const p = {}; for (const f of ['a', 'b', 'c']) if (chance(0.5)) p[f] = pick(VALS); return p; };
const genMutation = () => {
  const op = pick(['insert', 'update', 'update', 'delete']);
  const m = { op, table: pick(TABLES), recordId: pick(RIDS) };
  if (op !== 'delete') m.payload = genPayload();
  if (chance(0.3)) m.baseVersion = int(5);
  if (chance(0.5)) m.at = 100 + int(900);
  if (chance(0.15)) m.waitingOnAttachments = pick([['f1'], ['f1', 'f2'], []]);
  if (chance(0.15)) m.nextAttemptAt = pick([0, 50, 5000, 100000]);
  return m;
};
const genRecord = (i) => ({ id: pick(RIDS) + (chance(0.3) ? String(i) : ''), updatedAt: `2026-01-0${1 + int(3)}T00:00:0${int(4)}Z`, n: int(9), ...(chance(0.4) ? genPayload() : {}) });

function scenario() {
  const spec = {
    start: 1000 + int(5) * 100,
    tick: pick([1, 7, 100]),
    maxAttempts: pick([undefined, 2, 3]),
    baseDelayMs: pick([undefined, 10, 500]),
    durable: chance(0.7),
    saveFailures: Array.from({ length: 12 }, () => pick([null, null, null, null, 'quota', 'io'])),
    clearFails: chance(0.1),
    pushPlan: Object.fromEntries(RIDS.map((r) => [r, Array.from({ length: 4 }, () => pick(['ok', 'ok', 'err', 'conflict', 'throw']))])),
    server: Array.from({ length: int(9) }, (_, i) => genRecord(i)),
    deletions: pick([[], ['r1'], [{ id: 'r2' }, 'zz']]),
    ignoreCursor: chance(0.1),
    pageSize: pick([200, 2, 3]),
  };
  // unique ids on the server (a record is one row)
  const seen = new Set();
  spec.server = spec.server.filter((r) => (seen.has(r.id) ? false : (seen.add(r.id), true)));
  return spec;
}

function genOps() {
  const ops = [];
  const n = 4 + int(10);
  if (chance(0.5)) ops.push({ op: 'restore' });
  for (let i = 0; i < n; i++) {
    const r = rnd();
    if (r < 0.3) ops.push({ op: 'add', mutation: genMutation() });
    else if (r < 0.45) ops.push({ op: 'flush', ...(chance(0.3) ? { continueOnError: true } : {}), ...(chance(0.3) ? { resolve: 'server-wins' } : {}), ...(chance(0.4) ? { at: pick([0, 200, 1500, 100000, 1000000]) } : {}) });
    else if (r < 0.5) ops.push({ op: 'revive', seq: 1 + int(6) });
    else if (r < 0.55) ops.push({ op: 'discard', seq: 1 + int(6) });
    else if (r < 0.6) ops.push({ op: 'settle', seq: 1 + int(6) });
    else if (r < 0.64) ops.push({ op: 'release', ids: pick([['f1'], ['f1', 'f2'], []]) });
    else if (r < 0.67) ops.push({ op: 'clear' });
    else if (r < 0.72) ops.push({ op: pick(['pending', 'dead', 'describe']) });
    else if (r < 0.75) ops.push({ op: 'ready', at: pick([0, 1500, 100000]) });
    else if (r < 0.85) ops.push({ op: 'runSync', local: Array.from({ length: int(4) }, (_, k) => ({ id: pick(RIDS), n: -k })), cursor: chance(0.7) ? { updatedAt: null, id: null } : { updatedAt: '2026-01-02T00:00:00Z', id: 'r2' }, strategy: pick(['manual', 'last-write-wins']) });
    else if (r < 0.9) ops.push({ op: 'pull', cursor: chance(0.5) ? { updatedAt: null, id: null } : { updatedAt: '2026-01-02T00:00:01Z', id: 'r1' }, limit: pick([1, 2, 200]), maxPages: pick([1, 2, 50]) });
    else ops.push({ op: 'syncQueue', queue: Array.from({ length: 1 + int(4) }, () => genMutation()), ...(chance(0.4) ? { resolve: 'server-wins' } : {}), ...(chance(0.3) ? { stopOnError: false } : {}) });
  }
  // stateless
  const q = Array.from({ length: int(4) }, () => genMutation());
  ops.push({ op: 'enqueue', queue: q, mutation: genMutation() });
  ops.push({ op: 'optimistic', records: Array.from({ length: 1 + int(3) }, (_, k) => ({ id: RIDS[k], n: k })), mutation: genMutation() });
  const cur = { updatedAt: pick([null, '2026-01-02T00:00:01Z']), id: pick([null, 'r2']) };
  ops.push({ op: 'cursor', cursor: cur, record: genRecord(0), records: Array.from({ length: int(3) }, (_, k) => genRecord(k)) });
  const base = chance(0.15) ? undefined : genPayload();
  ops.push({ op: 'resolve', conflict: { ...(base ? { base } : {}), mine: genPayload(), theirs: genPayload(), mineAt: pick(['a', 'b', '']), theirsAt: pick(['a', 'b']) }, strategy: pick(['manual', 'last-write-wins', 'field-merge', 'field-merge', 'weird']) });
  ops.push({ op: 'detect', ...(chance(0.15) ? {} : { base: genPayload() }), mine: genPayload(), theirs: genPayload() });
  ops.push({ op: 'apply', local: Array.from({ length: int(4) }, (_, k) => ({ id: pick(RIDS), n: -k })), changes: { records: Array.from({ length: int(4) }, (_, k) => ({ id: pick(RIDS), n: k })), deletions: pick([[], ['r1'], [{ id: 'r3' }]]) }, pendingIds: pick([[], ['r1'], ['r2', 'r3']]) });
  return ops;
}

async function execute(spec, ops) {
  let t = spec.start;
  const now = () => { const v = t; t += spec.tick; return v; };
  let stored = [];
  let saveCall = 0;
  const store = {
    durable: spec.durable,
    withLock: (run) => run(),
    async load() { return [...stored]; },
    async save(next) {
      const plan = spec.saveFailures[saveCall++ % spec.saveFailures.length];
      if (plan === 'quota') { const e = new Error('full'); e.name = 'QuotaExceededError'; throw e; }
      if (plan === 'io') throw new Error('disk broke');
      stored = [...next];
    },
    async clear() { if (spec.clearFails) throw new Error('clear broke'); stored = []; },
  };
  const options = { now, ...(spec.maxAttempts ? { maxAttempts: spec.maxAttempts } : {}), ...(spec.baseDelayMs ? { baseDelayMs: spec.baseDelayMs } : {}) };
  const outbox = dq.createOutbox(store, options);
  const calls = {};
  const push = async (m) => {
    const key = String(m.recordId);
    const n = calls[key] || 0;
    calls[key] = n + 1;
    const plan = spec.pushPlan[key] || ['ok'];
    const outcome = plan[n % plan.length];
    if (outcome === 'ok') return { ok: true };
    if (outcome === 'conflict') return { conflict: true, server: { id: key, v: n } };
    if (outcome === 'throw') throw new Error(`boom ${key}`);
    return { error: `err ${key} ${n}` };
  };
  const fetchPage = async (cursor, limit) => {
    const after = spec.ignoreCursor ? [...spec.server] : spec.server.filter((r) => se.isAfterCursor(r, cursor));
    after.sort((a, b) => (a.updatedAt < b.updatedAt ? -1 : a.updatedAt > b.updatedAt ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    const records = after.slice(0, Math.min(limit, spec.pageSize));
    const first = cursor == null || cursor.updatedAt == null;
    return { records, ...(first ? { deletions: spec.deletions } : {}) };
  };
  const out = [];
  for (const op of ops) {
    let r;
    switch (op.op) {
      case 'restore': r = await outbox.restore(); break;
      case 'add': r = await outbox.add(op.mutation); break;
      case 'flush': r = await outbox.flush(push, { ...(op.at !== undefined ? { at: op.at } : {}), ...(op.continueOnError ? { continueOnError: true } : {}), ...(op.resolve ? { resolve: op.resolve } : {}) }); break;
      case 'revive': r = await outbox.revive(op.seq); break;
      case 'discard': r = await outbox.discard(op.seq); break;
      case 'settle': r = await outbox.settle(op.seq); break;
      case 'release': r = await outbox.releaseAttachments(op.ids); break;
      case 'clear': r = await outbox.clear(); break;
      case 'pending': r = outbox.pending(); break;
      case 'dead': r = outbox.deadLetters(); break;
      case 'ready': r = outbox.ready(op.at); break;
      case 'describe': r = dq.describeOutbox(outbox); break;
      case 'runSync': r = await se.runSync({ outbox, fetchPage, push, local: op.local, cursor: op.cursor, strategy: op.strategy, now }); break;
      case 'pull': r = await se.pullChanges(fetchPage, { cursor: op.cursor, limit: op.limit, maxPages: op.maxPages }); break;
      case 'syncQueue': r = await off.sync(op.queue, push, { ...(op.resolve ? { resolve: op.resolve } : {}), ...(op.stopOnError === false ? { stopOnError: false } : {}) }); break;
      case 'enqueue': r = off.enqueue(op.queue, op.mutation); break;
      case 'optimistic': r = off.applyOptimistic(op.records, op.mutation); break;
      case 'cursor': r = { enc: se.encodeCursor(op.cursor), dec: se.decodeCursor(se.encodeCursor(op.cursor)), after: se.isAfterCursor(op.record, op.cursor), adv: se.advanceCursor(op.records, op.cursor) }; break;
      case 'resolve': r = se.resolveConflict(op.conflict, op.strategy); break;
      case 'detect': r = se.detectFieldConflicts(op.base, op.mine, op.theirs); break;
      case 'apply': r = se.applyChanges(op.local, op.changes, { pendingIds: new Set(op.pendingIds) }); break;
      default: throw new Error(op.op);
    }
    out.push(canon(r));
  }
  return out.join('\n');
}

const cases = [];
const kinds = {};
for (let i = 0; i < 260; i++) {
  const spec = scenario();
  const ops = genOps();
  const e = await execute(spec, ops);
  for (const o of ops) kinds[o.op] = (kinds[o.op] || 0) + 1;
  cases.push(JSON.stringify({ spec, ops, e }));
}

const chunks = [];
const size = 4;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'sync_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_sync/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_sync`, kinds);
