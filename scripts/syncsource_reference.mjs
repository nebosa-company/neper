// Reference vectors for `e.algo.syncsource` (L037): run appdor's own src/sync/change-stream.js and src/sync/entity-browse.js
// over random single operations -- token shape, stream URLs, delivery bodies, planned row changes and their ledger
// counts, the entities a channel names, an index response read into entities, and the merged picker list -- and write
// the link fixture tests/selfhost/fixtures/link/algo_syncsource. APPDOR_DIR defaults to D:/repos/appdor. Names are ASCII
// letters, digits, spaces, dots and slashes, where `localeCompare` and the module's collation agree.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const cs = await load('src/sync/change-stream.js');
const eb = await load('src/sync/entity-browse.js');

let seed = 0x3c5b;
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

const WORDS = ['orders', 'Orders', 'customers', 'invoice items', 'a', 'B', 'list 2', 'list 10', 'items.v2', 'Users', 'users', 'zeta', 'alpha', 'Alpha', 'x1', 'x10', 'ab', 'aB', 'a b'];
const COLS = ['id', 'name', 'qty', 'tag', 'note'];
const VALUES = ['a', 1, 2.5, true, null, '', { k: [1, 2] }, [3]];
const genRecord = () => {
  const r = {};
  for (const c of COLS) if (chance(0.55)) r[c] = pick(VALUES);
  if (chance(0.75)) r.id = pick([1, 2, 'k3', 0, '', null, 7]);
  return r;
};
const genMapping = () => COLS.filter(() => chance(0.7)).map((name) => ({ name, ...(chance(0.15) ? { missingInSource: true } : {}), ...(chance(0.2) ? { structured: true } : {}) }));
const genBinding = () => ({ ...(chance(0.9) ? { column_mapping: genMapping() } : {}), ...(chance(0.9) ? { sync_key: pick(['id', 'name', 'zz']) } : {}) });

function genChannel() {
  const actions = {};
  const n = int(6);
  for (let i = 0; i < n; i++) {
    const path = pick(['/orders', '/customers', '/items/{id}', 'noslash', '/invoices', '/orders', '/a b', '/x.y']);
    actions['act' + i] = { key: 'act' + i, method: pick(['GET', 'GET', 'POST']), path, ...(chance(0.7) ? { name: pick(WORDS) } : {}), ...(chance(0.3) ? { resultPath: pick(['data', 'result.items']) } : {}) };
  }
  const channel = { actions };
  if (chance(0.8)) channel.browse = { ...(chance(0.9) ? { path: pick(['/', '/index', '/api/tables']) } : {}), ...(chance(0.5) ? { resultPath: pick(['data', 'schema.tables', 'paths']) } : {}), ...(chance(0.5) ? { namePath: pick(['name', 'meta.title']) } : {}), ...(chance(0.4) ? { pathTemplate: pick(['/{name}', '/rest/{name}', '/{name}/list']) } : {}) };
  return channel;
}
function genBody(channel) {
  const rp = channel.browse && channel.browse.resultPath;
  const leaf = pick([
    () => Array.from({ length: int(6) }, () => pick([...WORDS, '/rpc/fn', '/', '/rpc/x'])),
    () => Array.from({ length: int(5) }, () => ({ name: pick(WORDS), meta: { title: pick(WORDS) } })),
    () => Object.fromEntries(Array.from({ length: int(5) }, () => [pick(['/' + pick(WORDS), pick(WORDS), '/rpc/x', '/', '']), {}])),
    () => Array.from({ length: int(4) }, () => pick([pick(WORDS), { name: pick(WORDS) }, { other: 1 }, 5, null, { name: '' }])),
    () => 'text', () => null, () => 7,
  ])();
  if (!rp) return chance(0.9) ? leaf : { data: leaf };
  const parts = rp.split('.');
  let body = leaf;
  for (let i = parts.length - 1; i >= 0; i--) body = { [parts[i]]: body };
  if (chance(0.15)) return { elsewhere: 1 };
  return body;
}
const genEntity = (source) => ({ path: pick(['/orders', '/customers', '/invoices', '/a', '/b']), name: pick(WORDS), source });

function genOp() {
  switch (int(10)) {
    case 0: return { op: 'token', token: pick(['cs_' + 'a1b2c3d4e5f6g7h8i', 'cs_short', 'xs_' + 'a1b2c3d4e5f6g7h8i9', 'cs_a1b2c3d4e5f6g7h8-', 'cs_' + 'Z'.repeat(40), '', 'cs_' + '_'.repeat(16), 'cs_' + 'a'.repeat(16), 'cs_' + 'a'.repeat(17)]) };
    case 1: return { op: 'url', base: pick(['https://x.test', 'https://x.test///', '', 'http://a/b/', '/']), token: pick(['cs_abc', '']) };
    case 2: return { op: 'delivery', payload: pick([null, 5, 'x', [1], {}, { op: 'DELETE', record: { id: 1 } }, { op: 'Upsert', id: 3 }, { op: 'patch', id: 1 }, { record: null }, { record: [1] }, { record: { id: 1 }, op: 'delete' }, { id: 2, name: 'n' }, { op: '', id: 1 }, { op: 0, id: 1 }, { op: 'delete', id: 9, record: 'x' }]) };
    case 3: case 4: case 5: return { op: 'plan', binding: genBinding(), planOp: pick(['upsert', 'delete', 'upsert']), record: chance(0.9) ? genRecord() : pick([null, {}]), existing: pick([null, { id: 'row1', data: { a: 1 } }, { id: 4 }, undefined]) };
    case 6: return { op: 'counts', plan: pick([{}, { ok: true, action: 'insert', key: 'k1' }, { ok: true, action: 'update', key: '2', rowId: 'r' }, { ok: true, action: 'delete', key: 'z' }, { ok: true, action: 'noop', key: 'q' }, { ok: false, reason: 'x' }]) };
    case 7: { const channel = genChannel(); return { op: 'static', channel }; }
    case 8: { const channel = genChannel(); return { op: 'entities', channel, body: genBody(channel) }; }
    default: return { op: 'merge', source: Array.from({ length: int(5) }, () => genEntity('source')), catalog: Array.from({ length: int(5) }, () => genEntity('catalog')) };
  }
}

function execute(op) {
  switch (op.op) {
    case 'token': return cs.looksLikeStreamToken(op.token);
    case 'url': return cs.streamUrl(op.base, op.token);
    case 'delivery': return cs.changeFromDelivery(op.payload);
    case 'plan': return cs.planStreamChange({ binding: op.binding, op: op.planOp, record: op.record, existing: op.existing });
    case 'counts': return cs.streamPlanCounts(op.plan);
    case 'static': return { entities: eb.staticEntities(op.channel), browse: eb.canBrowse(op.channel) };
    case 'entities': return eb.entitiesFromBody(op.channel, op.body);
    case 'merge': return eb.mergeEntities(op.source, op.catalog);
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
const template = readFileSync(resolve(here, 'syncsource_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_syncsource/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_syncsource`, kinds);
