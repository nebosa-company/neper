// Reference vectors for `e.algo.syncjob` (L037): run appdor's own src/sync/sync-schedule.js, sync-refusal.js and the pure
// half of synced-table.js (with syncPlan from src/connectors) over random inputs -- leases, due bindings, backoff,
// schedules, health, deletion policy and flag plans, sync-key validation, quarantine, pull plans, ledger rows, response
// bodies and schema drift -- and write the link fixture tests/selfhost/fixtures/link/algo_syncjob.
// APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const sched = await load('src/sync/sync-schedule.js');
const refusal = await load('src/sync/sync-refusal.js');
const st = await load('src/sync/synced-table.js');
const conn = await load('src/connectors/index.js');

let seed = 0x91a3;
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

const BASE = Date.UTC(2026, 4, 1);
const iso = (ms) => new Date(ms).toISOString();
const instant = () => (chance(0.75) ? iso(BASE + int(7200000)) : BASE + int(7200000));
const VALUES = ['a', 'b', 1, 2, 2.5, true, null, ''];
const COLS = ['id', 'name', 'qty', 'tag', 'note'];
const TYPES = ['string', 'int', 'float', 'bool', 'date'];

const genRow = (i) => ({ ...(chance(0.9) ? { id: pick([1, 2, 3, 4, '1', 'x']) } : {}), name: pick(VALUES), ...(chance(0.5) ? { qty: pick([1, 2, null]) } : {}), ...(chance(0.2) ? { __rowId: `row${i}` } : {}), ...(chance(0.2) ? { _missingInSource: pick([true, false]) } : {}) });
const genBinding = (i) => ({
  id: `b${i}`,
  ...(chance(0.9) ? { status: pick(['active', 'error', 'paused', 'detached', 'connection_removed']) } : {}),
  ...(chance(0.7) ? { next_run_at: pick([iso(BASE + i * 60000 + int(7200000)), 'garbage']) } : {}),
  ...(chance(0.4) ? { claimed_by: pick(['w1', 'w2', null, '']) } : {}),
  ...(chance(0.4) ? { claimed_at: pick([iso(BASE - int(900000)), 'junk', null]) } : {}),
  ...(chance(0.5) ? { interval_minutes: pick([1, 5, 15, '30', 90, 0, null, 'x']) } : {}),
  ...(chance(0.5) ? { consecutive_failures: pick([0, 1, 2, 3, 8, 30, '2', null]) } : {}),
});

function genMapping() {
  return COLS.filter(() => chance(0.7)).map((name) => ({ name, nativeType: pick(TYPES), lc8Type: pick(['text', 'number', 'checkbox']), ...(chance(0.15) ? { missingInSource: true } : {}), ...(chance(0.1) ? { structured: true } : {}) }));
}
function genObserved() {
  return COLS.filter(() => chance(0.7)).map((name) => ({ name, nativeType: pick(TYPES), lc8Type: pick(['text', 'number', 'date']), ...(chance(0.2) ? { downgraded: true, diagnostic: 'lossy' } : {}), ...(chance(0.15) ? { structured: true } : {}) }));
}

function genOp() {
  const r = int(24);
  switch (r) {
    case 0: return { op: 'lease', row: pick([{}, { claimed_by: 'w1', claimed_at: iso(BASE - int(900000)) }, { claimed_by: 'w2' }, { claimed_by: 'w2', claimed_at: 'junk' }]), me: pick(['w1', '', 'w3']), now: instant() };
    case 1: { const rows = Array.from({ length: int(7) }, (_, i) => genBinding(i)); const seen = new Set(); const uniq = rows.filter((x) => { const k = x.next_run_at || ''; if (seen.has(k) && k !== 'garbage') return false; seen.add(k); return true; }); return { op: 'due', rows: uniq, now: instant() }; }
    case 2: return { op: 'backoff', failures: pick([undefined, 0, 1, 2, 5, 25, '3', null, -2]), interval: pick([undefined, 1, 5, 30, '45', 0, 1000, null]) };
    case 3: return { op: 'after', row: genBinding(0), failed: chance(0.5), now: instant() };
    case 4: return { op: 'health', row: genBinding(0) };
    case 5: return { op: 'policy', deletes: Array.from({ length: int(3) }, (_, i) => genRow(i)), policy: pick(['flag', 'delete', 'soft', undefined]) };
    case 6: return { op: 'flagPlan', rows: Array.from({ length: int(5) }, (_, i) => genRow(i)) };
    case 7: return { op: 'unflagPlan', local: Array.from({ length: int(5) }, (_, i) => genRow(i)), remote: Array.from({ length: int(5) }, (_, i) => genRow(i)), key: pick(['id', 'name']) };
    case 8: return { op: 'refusal', code: pick(['sql-sources-not-configured', 'sql-host-not-allowed', 'sql-source-unresolved', 'sql-address-private', 'sql-address-', 'sql-address-Bad', 'other', '']) };
    case 9: return { op: 'coerce', column: pick([undefined, {}, { structured: true }]), value: pick([undefined, null, 1, 'a', { k: 1 }, [1]]) };
    case 10: return { op: 'validateKey', columns: pick([[{ name: 'id' }, { name: 'name' }], []]), key: pick([undefined, '', 'id', 'zz']), sample: pick([undefined, [], [{ id: 1 }, { id: 2 }], [{ id: 1 }, { id: 1 }], [{ id: 1 }, { id: '' }, { name: 'x' }], [{ id: 1 }, { id: '1' }, { id: 1 }]]) };
    case 11: return { op: 'quarantine', rows: Array.from({ length: int(6) }, (_, i) => genRow(i)), key: pick(['id', 'name']) };
    case 12: return { op: 'syncPlan', local: Array.from({ length: int(5) }, (_, i) => genRow(i)), remote: Array.from({ length: int(5) }, (_, i) => genRow(i)), key: pick(['id', 'name']), options: pick([{}, { fields: ['name'] }, { bulkLoad: true }, { fields: ['name', 'qty'], bulkLoad: true }]) };
    case 13: return { op: 'planPull', local: pick([[], ...[1, 2].map(() => Array.from({ length: 1 + int(4) }, (_, i) => genRow(i)))]), remote: Array.from({ length: int(6) }, (_, i) => genRow(i)), key: pick(['id', 'name']), fields: pick([undefined, [], ['name']]), partial: pick([undefined, true, false, 'yes']) };
    case 14: return { op: 'ledger', synced: pick(['s1', 7]), trigger: pick(['manual', 'schedule']), plan: pick([undefined, null, { inserts: [1, 2], updates: [1], deletes: [], quarantined: [1], bulkLoad: true }, { inserts: [] }]), error: pick([undefined, null, 'boom']), started: pick([undefined, iso(BASE), BASE]), finished: pick([undefined, iso(BASE + 5000), BASE - 5, 'junk']) };
    case 15: return { op: 'nextRun', row: pick([{}, { interval_minutes: 15 }, { interval_minutes: 1 }, { interval_minutes: '120' }]), now: instant() };
    case 16: return { op: 'bodyRecords', body: pick([[1, 2], { data: [1] }, { records: [2], data: 'x' }, { value: [3] }, { items: [4] }, { results: [5] }, { other: [6] }, null, 'str', {}]) };
    case 17: { const stored = genMapping(); const observed = genObserved(); return { op: 'drift', stored, observed }; }
    default: { const stored = genMapping(); const observed = genObserved(); return { op: 'accept', stored, observed, choices: pick([undefined, {}, { add: COLS }, { add: ['qty', 'note', 'qty'] }, { add: 'qty' }]) }; }
  }
}

function execute(op) {
  switch (op.op) {
    case 'lease': return sched.leaseAvailable(op.row, op.me, op.now);
    case 'due': return sched.dueBindings(op.rows, op.now);
    case 'backoff': return sched.backoffMinutes(op.failures, op.interval);
    case 'after': return sched.scheduleAfterRun({ row: op.row, error: op.failed ? 'boom' : null, now: op.now });
    case 'health': return sched.bindingHealth(op.row);
    case 'policy': return sched.applyDeletionPolicy(op.deletes, op.policy);
    case 'flagPlan': return sched.flagPlan(op.rows);
    case 'unflagPlan': return sched.unflagPlan(op.local, op.remote, op.key);
    case 'refusal': return { key: refusal.syncRefusalKey(op.code), text: refusal.describeSyncRefusal(op.code, (key, _p, vars) => `${key}|${vars.variable}`) };
    case 'coerce': return st.coerceValue(op.column, op.value);
    case 'validateKey': return st.validateSyncKey({ columns: op.columns, syncKey: op.key, sample: op.sample });
    case 'quarantine': return st.quarantineByKey(op.rows, op.key);
    case 'syncPlan': return conn.syncPlan(op.local, op.remote, op.key, op.options);
    case 'planPull': return st.planPull({ localRows: op.local, remoteRows: op.remote, syncKey: op.key, fields: op.fields, partial: op.partial });
    case 'ledger': return st.runLedgerRow({ syncedTableId: op.synced, trigger: op.trigger, plan: op.plan, error: op.error, startedAt: op.started, finishedAt: op.finished });
    case 'nextRun': return st.nextRunAt(op.row, op.now);
    case 'bodyRecords': return st.recordsFromBody(op.body);
    case 'drift': return st.driftReport(op.stored, op.observed);
    case 'accept': return st.acceptDrift(op.stored, st.driftReport(op.stored, op.observed), op.choices);
    default: throw new Error(op.op);
  }
}

const cases = [];
const kinds = {};
for (let i = 0; i < 700; i++) {
  const op = genOp();
  kinds[op.op] = (kinds[op.op] || 0) + 1;
  cases.push(JSON.stringify({ op, e: canon(execute(op)) }));
}

const chunks = [];
const size = 20;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'syncjob_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_syncjob/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_syncjob`, kinds);
