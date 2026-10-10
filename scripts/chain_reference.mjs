// Reference vectors for `e.algo.chain` (L037): run appdor's own tamper-evident history module
// (src/history/tamper-evident.js with diffRecords from src/history/index.js) over random operation scripts -- record
// changes and appends onto a hash chain, verification before and after tampering, diffs, WAS and CHANGED predicates,
// history filters, field histories, plan retention and exports -- and write the link fixture
// tests/selfhost/fixtures/link/algo_chain. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const te = await load('src/history/tamper-evident.js');
const hist = await load('src/history/index.js');

let seed = 0x4c37;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

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

const FIELDS = ['status', 'owner', 'priority', 'title', 'updated_at', 'tags'];
const VALUES = [null, 'open', 'review', 'done', 'x', 1, 2, 2.5, true, false, [1], [1, 2], { k: 1 }, { k: 1, j: 'a' }, 'ünï'];
const randomState = () => {
  const s = {};
  for (const f of FIELDS) if (chance(0.5)) s[f] = pick(VALUES);
  return s;
};
let clock = Date.UTC(2026, 0, 1);
const stamp = () => { clock += (1 + int(40)) * 86400000 + int(86400) * 1000 + int(1000); return new Date(clock).toISOString(); };

function genRevisions(ids) {
  const revs = [];
  for (const id of ids) {
    let state = {};
    for (let i = 0, n = 1 + int(5); i < n; i++) {
      const next = chance(0.7) ? { ...state, ...randomState() } : randomState();
      const changes = hist.diffRecords(state, next);
      revs.push({ recordId: id, action: 'update', actor: 'u1', at: stamp(), changes });
      state = next;
    }
  }
  return revs.sort((a, b) => (a.at < b.at ? -1 : 1)).map((r) => (chance(0.9) ? r : { ...r, extra: 1 }));
}

function script() {
  clock = Date.UTC(2026, 0, 1) + int(100) * 86400000;
  const chain = [];
  const ops = [];
  const out = [];
  const run = (op, f) => { ops.push(op); out.push(canon(f())); };
  const ids = ['r1', 'r2', 'r3'];
  const revisions = genRevisions(ids);
  for (let i = 0, n = 2 + int(5); i < n; i++) {
    const r = rnd();
    if (r < 0.4) {
      const change = { recordId: pick(ids), before: chance(0.2) ? null : randomState(), after: chance(0.1) ? undefined : randomState(), ...(chance(0.8) ? { actor: pick(['u1', 'u2']) } : {}), at: stamp(), ...(chance(0.3) ? { action: pick(['create', 'delete']) } : {}) };
      run({ op: 'recordChange', change }, () => te.recordChange(chain, change));
    } else if (r < 0.6) {
      const entry = { recordId: pick(ids), action: 'note', at: stamp(), detail: pick(VALUES), nested: { b: 1, a: [1, { z: 1, y: 2 }] } };
      run({ op: 'append', entry }, () => te.chainAppend(chain, entry));
    } else if (r < 0.7 && chain.length) {
      const index = int(chain.length);
      const field = pick(['actor', 'at', 'hash', 'prev', 'action']);
      const value = pick(['evil', 'zzz']);
      run({ op: 'tamper', index, field, value }, () => { chain[index][field] = value; return null; });
    } else if (r < 0.75 && chain.length) {
      const index = int(chain.length);
      run({ op: 'drop', index }, () => { chain.splice(index, 1); return null; });
    } else if (r < 0.85) {
      run({ op: 'verify' }, () => te.verifyChain(chain));
    } else if (r < 0.92) {
      const plan = pick(['free', 'pro', 'business', 'enterprise', 'unknown']);
      const nowMs = clock + int(1500) * 86400000 + int(1000);
      const windows = chance(0.2) ? { free: 30, pro: 400, custom: 5, enterprise: null } : undefined;
      const adopt = chance(0.5);
      const op = { op: 'retention', plan, nowMs, ...(windows ? { windows } : {}), adopt };
      run(op, () => { const res = te.applyHistoryRetention(chain, plan, nowMs, windows); if (adopt) { chain.length = 0; chain.push(...res.chain); } return res; });
    } else {
      const recordId = chance(0.5) ? pick(ids) : undefined;
      run({ op: 'export', ...(recordId ? { recordId } : {}) }, () => te.exportHistory(chain, recordId ? { recordId } : {}));
    }
  }
  const before = randomState();
  const after = chance(0.5) ? { ...before, ...randomState() } : randomState();
  const ignore = chance(0.3) ? ['title', 'owner'] : undefined;
  run({ op: 'diff', before, after, ...(ignore ? { ignore } : {}) }, () => hist.diffRecords(before, after, ignore ? { ignore } : {}));
  const rid = pick(ids);
  const field = pick(FIELDS);
  const value = pick(VALUES);
  const during = chance(0.5) ? { ...(chance(0.8) ? { from: revisions[int(revisions.length)].at } : {}), ...(chance(0.8) ? { to: revisions[int(revisions.length)].at } : {}) } : undefined;
  run({ op: 'was', revisions, recordId: rid, field, value, ...(during ? { options: { during } } : {}) }, () => te.was(revisions, rid, field, value, during ? { during } : {}));
  const copts = {};
  if (chance(0.4)) copts.after = revisions[int(revisions.length)].at;
  if (chance(0.3)) copts.before = revisions[int(revisions.length)].at;
  if (chance(0.3)) copts.from = pick(VALUES);
  if (chance(0.3)) copts.to = pick(VALUES);
  run({ op: 'changed', revisions, recordId: rid, field, options: copts }, () => te.changed(revisions, rid, field, copts));
  const records = ids.map((id) => ({ id, n: 1 }));
  const predicate = chance(0.5) ? { op: 'was', field, value, options: during ? { during } : {} } : { op: 'changed', field, options: copts };
  run({ op: 'filter', records, revisions, predicate }, () => te.filterByHistory(records, revisions, predicate));
  const fields = [pick(FIELDS), pick(FIELDS)];
  run({ op: 'fieldHistory', revisions, recordId: rid, fields }, () => te.fieldHistory(revisions, rid, fields));
  return { ops, e: out.join('\n') };
}

const cases = [];
for (let i = 0; i < 220; i++) cases.push(JSON.stringify(script()));

const chunks = [];
const size = 4;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'chain_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_chain/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
const kinds = {};
for (const c of cases) for (const l of JSON.parse(c).ops) kinds[l.op] = (kinds[l.op] || 0) + 1;
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_chain`, kinds);
