// Reference vectors for `e.algo.realtime` (L037): run appdor's own src/realtime/index.js over random operation scripts --
// presence and its viewer filter, version-based cell resolution, per-field merge, topic authorization, the connection
// lifecycle with a scripted jitter, delivery telemetry, payload trimming and view membership -- and write the link
// fixture tests/selfhost/fixtures/link/algo_realtime. The clock (Date.now and the injected now) is one counter and
// Math.random a scripted cycle. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const rt = await import(pathToFileURL(resolve(appdor, 'src/realtime/index.js')).href);

let seed = 0x7e11;
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

const USERS = ['u1', 'u2', 'u3'];
const BASE = Date.UTC(2026, 2, 1);
const iso = (ms) => new Date(ms).toISOString();
const instant = () => (chance(0.7) ? iso(BASE + int(120000)) : BASE + int(120000));
const VALS = [null, 'a', 'b', 1, 2, true, [1], { k: 1 }];

function genOps() {
  const ops = [];
  const n = 8 + int(14);
  for (let i = 0; i < n; i++) {
    const r = rnd();
    if (r < 0.1) ops.push({ op: 'setPresence', user: pick(USERS), info: { ...(chance(0.7) ? { cursor: { r: int(5), c: int(5) } } : {}), ...(chance(0.85) ? { at: instant() } : {}), ...(chance(0.7) ? { name: pick(['Ann', 'Bob']) } : {}), ...(chance(0.3) ? { anonymous: pick([true, false, 'yes']) } : {}) } });
    else if (r < 0.14) ops.push({ op: 'clearPresence', user: pick(USERS) });
    else if (r < 0.2) ops.push({ op: 'active', now: instant(), ...(chance(0.4) ? { ttl: pick([1000, 60000, 0]) } : {}) });
    else if (r < 0.24) ops.push({ op: 'filterView', policy: pick([{}, { isPortalUser: true }, { isPortalUser: true, showInternalPresenceToPortal: true }]) });
    else if (r < 0.26) ops.push({ op: 'status', state: pick([{}, { enabled: false }, { reachable: false }, { enabled: true, reachable: false }]) });
    else if (r < 0.32) ops.push({ op: 'tok', token: pick(['t1', 't2', 't3']), info: { userId: pick(USERS), ...(chance(0.7) ? { scopes: pick([[], ['tbl1'], ['*'], ['tbl2', 'tbl3'], 'tbl1']) } : {}), ...(chance(0.5) ? { expiresAt: BASE + int(300000) } : {}) } });
    else if (r < 0.35) ops.push({ op: 'revoke', token: pick(['t1', 't2', 't3']) });
    else if (r < 0.43) ops.push({ op: 'sub', topic: pick(['table:tbl1', 'table:tbl2:rows', 'table:tbl3:*', 'other', 'table:x:y:z', 'table::q']), token: pick(['t1', 't2', 't3', 'nope']), userId: pick(USERS) });
    else if (r < 0.46) ops.push({ op: 'unsub', topic: pick(['table:tbl1', 'table:tbl2:rows', 'other']) });
    else if (r < 0.48) ops.push({ op: 'evict', userId: pick(USERS) });
    else if (r < 0.51) ops.push({ op: 'may', userId: pick(USERS), topic: pick(['table:tbl1', 'table:tbl2:rows', 'other']) });
    else if (r < 0.54) ops.push({ op: 'subs', ...(chance(0.5) ? { userId: pick(USERS) } : {}) });
    else if (r < 0.62) ops.push({ op: 'lc', what: pick(['heartbeat', 'disconnected', 'plan', 'plan', 'reconnected', 'seq', 'seq', 'stale', 'should', 'state', 'events']), ...(chance(0.4) ? { n: pick([0, 1, 5, 60001, 3000]) } : {}) });
    else if (r < 0.72) ops.push({ op: 'tel', what: pick(['trace', 'delivery', 'degradation', 'coalesce', 'conn', 'export']), publishAt: chance(0.5) ? BASE + int(1000) : undefined, info: { ...(chance(0.6) ? { deliveredAt: BASE + int(5000) } : {}), ...(chance(0.6) ? { subscriberCount: int(9) } : {}), ...(chance(0.3) ? { coalesced: true } : {}), ...(chance(0.3) ? { degraded: true } : {}) }, count: int(50), since: pick([0, BASE + 100, BASE + 100000]) });
    else if (r < 0.77) ops.push({ op: 'resolveEdit', ...(chance(0.8) ? { cell: { value: pick(VALS), version: int(4), updatedBy: pick([...USERS, null]), updatedAt: chance(0.9) ? instant() : null } } : {}), edit: { value: pick(VALS), baseVersion: pick([0, 1, 2, 3]), userId: pick(USERS), at: instant() } });
    else if (r < 0.82) ops.push({ op: 'merge', base: { a: 1, b: 2 }, edits: Array.from({ length: int(5) }, () => ({ field: pick(['a', 'b', 'c']), value: pick(VALS), userId: pick(USERS), at: instant() })) });
    else if (r < 0.9) ops.push({ op: 'trim', payload: pick([null, { recordId: 'r1', record: { id: 'r1', a: 1, b: 2 } }, { records: [{ id: 'r1', a: 1, b: 2 }, { id: 'r2', a: 3, c: 4 }], changes: { a: 1, z: 2, id: 'r1' } }, { recordId: 7 }]), permissions: { ...(chance(0.5) ? { readableFields: pick([['a'], [], ['a', 'c']]) } : {}), ...(chance(0.5) ? { readableRowIds: pick([['r1'], [], ['r2', '7']]) } : {}) } });
    else if (r < 0.95) ops.push({ op: 'member', record: pick([{ s: 'open', n: 1 }, { s: 'done', n: 1 }]), filter: pick([null, {}, { s: 'open' }, { s: 'open', n: 1 }]), ...(chance(0.6) ? { previous: pick([{ s: 'open', n: 1 }, { s: 'done' }]) } : {}) });
    else ops.push({ op: 'affected', record: pick([{ s: 'open' }, { s: 'done' }]), ...(chance(0.7) ? { previous: pick([{ s: 'open' }, { s: 'done' }]) } : {}), views: [{ id: 'v1', name: 'Open', filter: { s: 'open' } }, { id: 'v2', name: 'All', filter: null }, { id: 'v3', filter: { s: 'done' } }] });
  }
  return ops;
}

function execute(spec, ops) {
  let t = spec.start;
  const tick = () => { const v = t; t += spec.tick; return v; };
  let rcall = 0;
  const realRandom = Math.random;
  const realNow = Date.now;
  Math.random = () => spec.jitter[rcall++ % spec.jitter.length];
  Date.now = tick;
  try {
    let presence = {};
    let users = [];
    const auth = rt.createTopicAuth({ now: tick });
    const events = [];
    const lc = rt.createConnectionLifecycle({ now: tick, onStateChange: (e) => events.push(e) });
    const tel = rt.createRealtimeTelemetry();
    let trace = null;
    const out = [];
    for (const op of ops) {
      let r;
      switch (op.op) {
        case 'setPresence': presence = rt.setPresence(presence, op.user, op.info); r = presence; break;
        case 'clearPresence': presence = rt.clearPresence(presence, op.user); r = presence; break;
        case 'active': users = rt.activeUsers(presence, op.now, op.ttl); r = users; break;
        case 'filterView': r = rt.filterPresenceForViewer(users, op.policy); break;
        case 'status': r = rt.realtimeStatus(op.state); break;
        case 'tok': r = auth.registerToken(op.token, op.info); break;
        case 'revoke': r = auth.revokeToken(op.token); break;
        case 'sub': r = auth.subscribe(op.topic, { token: op.token, userId: op.userId }); break;
        case 'unsub': r = auth.unsubscribe(op.topic); break;
        case 'evict': r = auth.evictUser(op.userId); break;
        case 'may': r = !!auth.mayReceive(op.userId, op.topic); break;
        case 'subs': r = op.userId ? auth.activeSubscriptions(op.userId) : auth.activeSubscriptions(); break;
        case 'lc':
          switch (op.what) {
            case 'heartbeat': lc.heartbeat(); r = null; break;
            case 'disconnected': r = lc.disconnected(); break;
            case 'plan': r = lc.planReconnect(); break;
            case 'reconnected': r = lc.reconnected(op.n !== undefined ? { lastKnownSeq: op.n } : {}); break;
            case 'seq': r = lc.advanceSeq(); break;
            case 'stale': r = op.n !== undefined ? lc.isStale(op.n) : lc.isStale(); break;
            case 'should': r = op.n !== undefined ? lc.shouldReconnect(op.n) : lc.shouldReconnect(); break;
            case 'state': r = { state: lc.state, seq: lc.sequence, disconnectAt: lc.disconnectAt }; break;
            case 'events': r = events.splice(0); break;
            default: throw new Error(op.what);
          }
          break;
        case 'tel':
          switch (op.what) {
            case 'trace': trace = tel.startTrace(op.publishAt); r = trace; break;
            case 'delivery': r = tel.recordDelivery(trace ? trace.correlationId : 'none', op.info); break;
            case 'degradation': tel.recordDegradation('slow'); r = null; break;
            case 'coalesce': tel.recordCoalesce(op.count, op.count - 1); r = null; break;
            case 'conn': tel.recordConnectionCount(op.count); r = null; break;
            case 'export': r = tel.export({ since: op.since }); break;
            default: throw new Error(op.what);
          }
          break;
        case 'resolveEdit': r = rt.resolveEdit(op.cell, op.edit); break;
        case 'merge': r = rt.mergeRecord(op.base, op.edits); break;
        case 'trim': r = rt.trimEventPayload(op.payload, op.permissions); break;
        case 'member': r = rt.evaluateViewMembership(op.record, op.filter, op.previous !== undefined ? { previousRecord: op.previous } : {}); break;
        case 'affected': r = rt.affectedViews(op.record, op.previous === undefined ? null : op.previous, op.views); break;
        default: throw new Error(op.op);
      }
      out.push(canon(r));
    }
    return out.join('\n');
  } finally {
    Math.random = realRandom;
    Date.now = realNow;
  }
}

const cases = [];
const kinds = {};
for (let i = 0; i < 220; i++) {
  const spec = { start: BASE + int(100000), tick: pick([1, 250, 5000]), jitter: Array.from({ length: 5 }, () => pick([0, 0.25, 0.5, 0.999])) };
  const ops = genOps();
  const e = execute(spec, ops);
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
const template = readFileSync(resolve(here, 'realtime_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_realtime/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_realtime`, kinds);
