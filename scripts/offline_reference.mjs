// Reference vectors for `e.algo.offline` (L037): run appdor's own src/offline write-queue.js, read-cache.js,
// conflict-review.js and access-purge.js over random operation scripts -- network-failure classification, the queue over
// a memory outbox, the read cache and its overlay and purge, the connectivity machine, replay planning and resolution,
// the conflict review and the resolution plans -- and write the link fixture tests/selfhost/fixtures/link/algo_offline.
// APPDOR_DIR defaults to D:/repos/appdor. Date.now is replaced by a counter so the outbox's stamps are reproducible.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const wq = await load('src/offline/write-queue.js');
const rc = await load('src/offline/read-cache.js');
const cr = await load('src/offline/conflict-review.js');
const ap = await load('src/offline/access-purge.js');

let seed = 0x7a31;
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

const TABLES = ['t1', 't2'];
const RIDS = ['r1', 'r2', 'r3', 'r4'];
const FIELDS = ['a', 'b', 'c'];
const VALS = ['x', 'y', 1, 2, null, true, ''];
const genValues = () => { const p = {}; for (const f of FIELDS) if (chance(0.5)) p[f] = pick(VALS); return p; };
const genMutation = () => {
  const op = pick(['insert', 'update', 'update', 'delete']);
  const m = { op, table: pick(TABLES), recordId: pick(RIDS) };
  if (op !== 'delete') m.payload = genValues();
  if (chance(0.3)) m.baseVersion = int(5);
  if (chance(0.6)) m.at = 100 + int(900);
  return m;
};
const genError = () => pick([
  { offline: true }, { message: 'Failed to fetch' }, { message: 'NetworkError when attempting to fetch' }, 'ECONNREFUSED 127.0.0.1',
  { message: 'permission denied' }, null, { message: '' }, { offline: false, message: 'load failed' }, 'x', 0, true, { code: 12 },
  { message: 'connect ETIMEDOUT' }, 'Fetch failed', { offline: 'yes', message: 'Network request failed' }, '', undefined,
]);
const genQueuedWrite = () => {
  const op = pick(['update', 'create', 'delete']);
  const w = { op, tableId: pick(['t1', 't2', 5]), recordId: pick(RIDS) };
  if (op !== 'delete') w.values = genValues();
  if (chance(0.5)) w.baseVersion = 1 + int(4);
  return w;
};
const genRecord = () => ({ ...(chance(0.92) ? { id: pick([...RIDS, 1, 2]) } : {}), ...genValues() });
const genRecords = () => { const rs = Array.from({ length: int(5) }, genRecord); return rs; };
const genRaw = () => {
  if (chance(0.06)) return pick([null, {}, { server: { id: 'z' } }]);
  const mutation = {
    ...(chance(0.6) ? { id: pick(['m1', 'm2', 3, 0]) } : {}),
    ...(chance(0.9) ? { table: pick(TABLES) } : {}),
    ...(chance(0.9) ? { recordId: pick(RIDS) } : {}),
    ...(chance(0.9) ? { payload: genValues() } : {}),
    ...(chance(0.6) ? { baseData: genValues() } : {}),
    ...(chance(0.3) ? { baseUpdatedAt: '2026-01-01T00:00:00Z' } : {}),
  };
  const server = chance(0.15) ? pick([null, undefined]) : { id: 'r', ...(chance(0.7) ? { updatedAt: '2026-01-02T00:00:00Z' } : {}), ...(chance(0.2) ? { updated_at: '2026-01-03T00:00:00Z' } : {}), ...genValues() };
  return { mutation, ...(server !== undefined ? { server } : {}) };
};

function scenario() {
  return {
    start: 1000 + int(5) * 100,
    tick: pick([1, 7, 100]),
    maxAttempts: pick([undefined, 2, 3]),
    pushPlan: Object.fromEntries(RIDS.map((r) => [r, Array.from({ length: 4 }, () => pick(['ok', 'ok', 'err', 'conflict', 'throw']))])),
  };
}

function genOps() {
  const ops = [];
  const n = 5 + int(11);
  for (let i = 0; i < n; i++) {
    const r = int(26);
    switch (r) {
      case 0: ops.push({ op: 'netFail', error: genError() }); break;
      case 1: case 2: ops.push({ op: 'queue', error: genError(), ...(chance(0.8) ? { mutation: chance(0.85) ? genMutation() : pick([{}, { op: 'update' }, { table: 't1' }, null]) } : {}) }); break;
      case 3: case 4: ops.push({ op: 'qflush', ...(chance(0.5) ? { at: pick([0, 200, 1500, 100000]) } : {}), ...(chance(0.3) ? { resolve: 'server-wins' } : {}) }); break;
      case 5: ops.push({ op: 'qstatus' }); break;
      case 6: ops.push({ op: 'describe', status: pick([undefined, null, { pending: 0, dead: 0, durable: true }, { pending: 0, dead: 1 }, { pending: 0, dead: 3 }, { pending: 1, durable: true }, { pending: 4, durable: false }, { pending: 2 }, { pending: 1, dead: 2, durable: true }]) }); break;
      case 7: case 8: ops.push({ op: 'cstore', table: pick(['t1', 't2', 5]), records: genRecords(), at: pick([1000, 2000, 1500]) }); break;
      case 9: case 10: ops.push({ op: 'cread', table: pick(['t1', 't2', 5, 'nope']), now: chance(0.6) ? pick([301000, 301001, 300999, 302000, 302001, 301500, 1200]) : 1000 + int(1000000), online: chance(0.6) }); break;
      case 11: ops.push({ op: 'coverlay', table: pick(['t1', 't2', 5]), writes: Array.from({ length: int(5) }, genQueuedWrite) }); break;
      case 12: ops.push({ op: 'cevict', table: pick(['t1', 't2', 5]) }); break;
      case 13: ops.push({ op: 'cscopes' }); break;
      case 14: ops.push({ op: 'cdrop', table: pick(['t1', 't2', 5]), ids: pick([['1'], ['r1', 'r2'], [], ['1', '2', 'zz'], null]) }); break;
      case 15: ops.push({ op: 'conn', next: pick(['online', 'offline', 'reconnecting', 'bogus']), at: pick([undefined, 5, 10]) }); break;
      case 16: ops.push({ op: 'conn', next: pick(['offline', 'reconnecting', 'online']), at: 1 + int(9) }); break;
      case 17: ops.push({ op: 'history' }); break;
      case 18: ops.push({ op: 'replay', queue: Array.from({ length: int(6) }, genQueuedWrite), versions: Object.fromEntries(RIDS.filter(() => chance(0.7)).map((x) => [x, int(6)])) }); break;
      case 19: {
        const write = genQueuedWrite();
        ops.push({ op: 'resolveReplay', conflict: { write, reason: 'changed-on-server', ...(chance(0.8) ? { serverVersion: 1 + int(5) } : {}) }, choice: pick(['local-wins', 'server-wins', 'merge', 'merge', 'weird']), ...(chance(0.85) ? { server: genValues() } : {}), ...(chance(0.85) ? { base: genValues() } : {}) });
        break;
      }
      case 20: ops.push({ op: 'review', conflicts: Array.from({ length: int(5) }, genRaw) }); break;
      case 21: case 22: ops.push({ op: 'resolution', conflicts: Array.from({ length: 1 + int(3) }, genRaw), index: int(3), choice: pick(['keep-mine', 'keep-theirs', 'merge', 'merge', 'bogus', '']) }); break;
      case 23: ops.push({ op: 'count', conflicts: Array.from({ length: int(5) }, genRaw) }); break;
      case 24: ops.push({ op: 'purge', cached: Array.from({ length: int(4) }, () => ({ tableId: pick(['t1', 't2', 5, '', 't3']), recordIds: pick([['1', '2'], ['r1'], [], ['r1', 'r2', 'r3']]) })), readable: pick([null, { tableIds: ['t1'], recordIdsByTable: { t1: ['1', 'r2'] } }, { tableIds: ['t1', 't2', 5], recordIdsByTable: { t1: ['r1'], t2: [1, 2], 5: ['1'] } }, { tableIds: [], recordIdsByTable: {} }, { tableIds: ['t2'] }, { recordIdsByTable: { t1: [] } }]), probeOk: chance(0.85) }); break;
      default: ops.push({ op: 'applyPurge', readable: pick([null, { tableIds: ['t1'], recordIdsByTable: { t1: ['1', 'r2'] } }, { tableIds: ['t1', 't2', 5], recordIdsByTable: { t1: ['r1'], t2: ['1'], 5: ['1', '2'] } }, { tableIds: ['t2'], recordIdsByTable: { t2: [] } }]), probeOk: chance(0.85) }); break;
    }
  }
  return ops;
}

async function execute(spec, ops) {
  let t = spec.start;
  const realNow = Date.now;
  Date.now = () => { const v = t; t += spec.tick; return v; };
  try {
    const outbox = await wq.createWriteQueue({ indexedDB: null, maxAttempts: spec.maxAttempts || 0 });
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
    const cache = rc.createReadCache();
    const conn = rc.createConnectivity();
    const out = [];
    for (const op of ops) {
      let r;
      switch (op.op) {
        case 'netFail': r = wq.isNetworkFailure(op.error); break;
        case 'queue': r = await wq.queueIfOffline(outbox, op.error, op.mutation); break;
        case 'qflush': r = await wq.flushQueue(outbox, push, { ...(op.at !== undefined ? { at: op.at } : {}), resolve: op.resolve || null }); break;
        case 'qstatus': r = wq.queueStatus(outbox); break;
        case 'describe': r = wq.describeQueue(op.status); break;
        case 'cstore': cache.store(op.table, op.records, op.at); r = null; break;
        case 'cread': r = cache.read(op.table, op.now, { online: op.online }); break;
        case 'coverlay': r = cache.overlay(op.table, op.writes); break;
        case 'cevict': r = cache.evict(op.table); break;
        case 'cscopes': r = cache.scopes(); break;
        case 'cdrop': r = cache.dropRecords(op.table, op.ids); break;
        case 'conn': r = conn.to(op.next, op.at); break;
        case 'history': r = conn.history(); break;
        case 'replay': r = rc.planReplay(op.queue, op.versions); break;
        case 'resolveReplay': r = rc.resolveConflict(op.conflict, op.choice, { serverRecord: op.server ?? null, baseRecord: op.base ?? null }); break;
        case 'review': r = cr.buildConflictReview(op.conflicts); break;
        case 'resolution': {
          const review = cr.buildConflictReview(op.conflicts);
          const valid = op.conflicts.filter((c) => c && c.mutation);
          const index = op.index % Math.max(1, review.items.length);
          const item = review.items[index];
          const raw = valid[index] || {};
          r = cr.planOfflineResolution(item, op.choice, { server: raw.server ?? null, mutation: raw.mutation ?? null });
          break;
        }
        case 'count': r = cr.conflictCount(cr.buildConflictReview(op.conflicts)); break;
        case 'purge': { const plan = ap.planCachePurge({ cached: op.cached, readable: op.readable, probeOk: op.probeOk }); r = { plan, outcome: ap.purgeOutcome(plan) }; break; }
        case 'applyPurge': {
          const plan = ap.planCachePurge({ cached: cache.scopes(), readable: op.readable, probeOk: op.probeOk });
          r = { plan, applied: ap.applyCachePurge(cache, plan), outcome: ap.purgeOutcome(plan) };
          break;
        }
        default: throw new Error(op.op);
      }
      out.push(canon(r));
    }
    return out.join('\n');
  } finally {
    Date.now = realNow;
  }
}

const cases = [];
const kinds = {};
for (let i = 0; i < 220; i++) {
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
const template = readFileSync(resolve(here, 'offline_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_offline/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_offline`, kinds);
