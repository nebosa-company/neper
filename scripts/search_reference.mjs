// Reference vectors for `e.algo.search` (L034): random entity sets and queries scored by appdor's own search
// (src/search/index.js), and scripted index / outbox / recents sessions run through its indexing pipeline and realm
// boundary (indexing-pipeline.js, tenant-scope.js); written as the link fixture tests/selfhost/fixtures/link/
// algo_fulltext. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const idx = await load('src/search/index.js');
const pipe = await load('src/search/indexing-pipeline.js');

// A fixed clock for the dead letters and the wedge test.
const RealDate = Date;
const FIXED = RealDate.parse('2026-02-01T12:00:00.000Z');
class FakeDate extends RealDate {
  constructor(...args) { if (args.length === 0) super(FIXED); else super(...args); }
  static now() { return FIXED; }
}
globalThis.Date = FakeDate;
const NOW_ISO = '2026-02-01T12:00:00.000Z';

const hex = (s) => (s === '' || s === null || s === undefined ? '_' : Buffer.from(String(s), 'utf8').toString('hex'));
const num = (n) => String(n);
const flag = (b) => (b ? '1' : '0');

let seed = 0x5ea4c;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const wire = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));

const WORDS = ['Sales', 'sales', 'Invoice', 'invoices', 'Customer', 'Customers', 'éclair', 'Ångström', 'CRM', 'Contact', 'contacts', '2024', 'Q3', 'Report', 'a-b', 'under_score', 'Order', 'Orders', 'Tasks', 'Project', 'Plan', 'Notes', 'ZED', 'İstanbul'];
const TYPES = ['app', 'table', 'page', 'record', 'view', 'form', 'dashboard', 'automation', 'other'];
const KEYS = ['CRM-482', 'CRM-483', 'INV-12', 'INV-120', 'ab-1', 'TASK_X-9'];
const title = () => Array.from({ length: 1 + int(3) }, () => pick(WORDS)).join(pick([' ', ' ', '-', '_']));
function makeEntity(i) {
  const e = { id: `e${i}`, type: pick(TYPES), title: rnd() < 0.05 ? '' : title() };
  if (rnd() < 0.4) e.text = Array.from({ length: int(5) }, () => pick(WORDS)).join(' ');
  else if (rnd() < 0.6) e.fields = { Name: pick(WORDS), Notes: pick(['', null, ['a', 'b'], 'free text here', 7, true]), Secret: pick(WORDS), Tags: pick([['x', 'y'], [], null]) };
  if (rnd() < 0.25) e.key = pick(KEYS);
  if (rnd() < 0.3) e.appId = pick(['a1', 'a2']);
  if (rnd() < 0.3) e.tableId = pick(['t1', 't2']);
  if (rnd() < 0.2) e.namespace = pick(['n1', 'n2']);
  return e;
}
const QUERIES = ['sales', 'Sales Invoice', 'inv', 'crm-482', 'CRM-482', 'CRM-4', 'CR', 'INV-12', 'éclair', 'zzz', '', '  ', 'a b', 'order orders', '2024', 'ANGSTROM', 'free', 'x y', 'under score', 'istanbul', 'ab-1', 'TASK_X-9'];

const cases = [];
const add = (o) => cases.push(JSON.stringify(o));

// scoring
for (let k = 0; k < 90; k += 1) {
  const entities = Array.from({ length: 2 + int(14) }, (_, i) => makeEntity(i));
  const build = {};
  if (rnd() < 0.3) build.searchableFields = pick([['Name'], ['Name', 'Notes'], []]);
  if (rnd() < 0.3) build.skipFields = pick([['Secret'], ['Name']]);
  const options = {};
  if (rnd() < 0.5) options.limit = pick([1, 2, 5, 0, 50]);
  if (rnd() < 0.3) options.types = pick([['app'], ['table', 'record'], []]);
  if (rnd() < 0.2) options.tableId = pick(['t1', 't2']);
  if (rnd() < 0.2) options.appId = pick(['a1', 'a2']);
  if (rnd() < 0.15) options.namespace = pick(['n1', 'n2']);
  const index = idx.buildIndex(entities, build);
  const query = pick(QUERIES);
  const r = idx.search(index, query, options);
  const hits = r.results.map((h) => `${hex(h.entity.id)}:${num(h.score)}:${h.matches.map((m) => `${hex(m)},`).join('')};`).join('');
  add({ op: 'search', entities, build, options, query, e: `${hits}|${r.total}` });
}
// searchable fields, find-in-table, plan, record keys
for (let k = 0; k < 20; k += 1) {
  const data = { Name: 'x', Secret: 'y', Notes: 'z', Extra: 1 };
  const columns = pick([[], [{ name: 'Secret', searchable: false }], [{ name: 'Secret', searchable: false }, { name: 'Notes', searchable: false }, { name: 'Missing', searchable: false }], [{ name: 'Name' }, { name: 'Secret', searchable: true }]]);
  add({ op: 'searchable', data, columns, e: Object.keys(idx.searchableFields(data, columns)).map((n) => `${hex(n)},`).join('') });
}
for (let k = 0; k < 40; k += 1) {
  const records = Array.from({ length: 1 + int(5) }, () => {
    const r = {};
    if (rnd() < 0.9) r.Name = pick(['Hello World', 'hello', 'a very long sentence with the word needle somewhere in the middle of it all', 'İstanbul needle', null, '']);
    if (rnd() < 0.8) r.Notes = pick([['alpha', 'needle beta'], 'Needle at start', 12345, true, '😀 needle 😀']);
    return r;
  });
  const query = pick(['needle', 'HELLO', 'x', '', 'beta', '12', 'stanbul']);
  const names = pick([undefined, [], ['Name'], ['Notes', 'Name'], ['Missing']]);
  const out = idx.findInTable(records, query, names);
  add({ op: 'findtable', records, query, names: wire(names), e: out.map((h) => `${records.indexOf(h.record)}:${h.matchedFields.map((f) => `${hex(f.field)}=${hex(f.snippet)},`).join('')};`).join('') });
}
for (let k = 0; k < 40; k += 1) {
  const input = { query: pick(['abc', '', '  ', ' x ']) };
  if (rnd() < 0.8) input.rowCount = pick([0, 10, 999, 1000, 5000]);
  if (rnd() < 0.5) input.loadedRows = pick([0, 10, 999, 1000, 5000]);
  if (rnd() < 0.5) input.tableId = pick(['t1', undefined]);
  if (rnd() < 0.3) input.limit = pick([10, 100]);
  if (rnd() < 0.3) input.offset = pick([0, 50]);
  if (rnd() < 0.3) input.fuzzy = pick([true, false]);
  const p = idx.planSearch(input);
  let e = `${p.mode}:${p.reason}`;
  if (p.mode === 'server') e = `${p.mode}:${p.reason}:${p.rpc.args.p_table_id === null ? '-' : hex(p.rpc.args.p_table_id)}:${hex(p.rpc.args.p_query)}:${p.rpc.args.p_limit}:${p.rpc.args.p_offset}:${flag(p.rpc.args.p_fuzzy)}`;
  add({ op: 'plan', ...wire(input), e });
}
for (const text of ['CRM-482', 'crm-482', 'AB-1', 'A-1', 'ABC_D-9', ' CRM-482 ', 'CRM-', 'CRM-12x', '', 'INV-007', 'a_b-1', 'AB_-1']) {
  const r = idx.detectRecordKey(text);
  add({ op: 'detect', text, e: `${r ? `${r.prefix}:${r.number}` : 'null'}|${flag(idx.isRecordKey(text))}` });
}

// pipelines
const PIPELINES = process.env.NO_PIPELINES ? 0 : 50;
const REALMS = ['r1', 'r2', ' r1 ', '', undefined, 'r3'];
function makeDoc(i, realmPool = REALMS) {
  const d = { id: `d${i}`, kind: pick(['record', 'table', 'app', 'page']), title: title() };
  if (rnd() < 0.5) d.text = Array.from({ length: int(4) }, () => pick(WORDS)).join(' ');
  else d.fields = { Name: pick(WORDS), Secret: pick(WORDS) };
  const realm = pick(realmPool);
  if (realm !== undefined) d.realmId = realm;
  if (rnd() < 0.3) d.tenantId = pick(['a1', 'a2']);
  if (rnd() < 0.3) d.tableId = pick(['t1', 't2']);
  if (rnd() < 0.3) d.key = pick(KEYS);
  return d;
}
for (let k = 0; k < PIPELINES; k += 1) {
  const enforceRealm = rnd() < 0.5;
  const realm = rnd() < 0.5 ? pick(['r1', 'r2', ' r1 ', '']) : undefined;
  const source = Array.from({ length: 6 }, (_, i) => makeDoc(i));
  const failIds = rnd() < 0.3 ? [pick(['d1', 'd2'])] : [];
  const skipIds = rnd() < 0.2 ? ['d3'] : [];
  const hiddenIds = rnd() < 0.3 ? [pick(['d0', 'd4'])] : [];
  const index = pipe.createSearchIndex({ ...(enforceRealm ? { enforceRealm: true } : {}), ...(realm !== undefined ? { realm } : {}) });
  const consumer = pipe.createOutboxConsumer(index, (e) => {
    if (failIds.includes(e.artifactId)) throw new Error(`bad ${e.artifactId}`);
    if (skipIds.includes(e.artifactId)) return null;
    const src = source.find((d) => d.id === e.artifactId);
    if (src) return JSON.parse(JSON.stringify(src));
    return { id: e.artifactId, kind: 'record', title: `T ${e.artifactId}` };
  });
  const recents = pipe.createRecents({ limit: rnd() < 0.3 ? 3 : 50 });
  const script = [];
  const out = [];
  let seq = 0;
  const mkEvents = (n) => Array.from({ length: n }, () => { seq += 1; const id = pick(['d0', 'd1', 'd2', 'd3', 'd4', 'd5', `x${int(4)}`]); return { seq: rnd() < 0.15 ? Math.max(1, seq - 2) : seq, artifactId: id, type: pick(['created', 'updated', 'renamed', 'trashed', 'purged', 'restored']), ...(rnd() < 0.7 ? { at: pick(['2026-02-01T11:50:00.000Z', '2026-02-01T11:59:00.000Z', '2026-01-01T00:00:00.000Z', 'bogus']) } : {}) }; });
  const renderCands = (list) => list.map((c) => `${hex(c.id)}:${hex(c.title)}:${c.kind}:${num(c.score)}:${hex(c.key ?? '')}:${hex(c.tableId ?? '')};`).join('');
  const renderCounts = (c) => `${c.total}${Object.entries(c.byKind).map(([n, v]) => `,${n}=${v}`).join('')}${Object.keys(c.byRealm).length ? `@${hex(Object.keys(c.byRealm)[0])}` : ''}`;
  for (let s = 0; s < 14; s += 1) {
    const kind = pick(['upsert', 'upsert', 'batch', 'remove', 'batchRemove', 'size', 'has', 'query', 'query', 'queryUser', 'queryScoped', 'suggest', 'scopedStats', 'stats', 'drop', 'clear', 'drain', 'drain', 'backlog', 'wedged', 'cstats', 'clearDead', 'touch', 'recents', 'fav', 'unfav', 'isFav', 'purge']);
    const queryOptions = () => {
      const o = {};
      if (rnd() < 0.3) o.kinds = pick([['record'], ['table', 'app']]);
      if (rnd() < 0.3) o.tableId = pick(['t1', 't2']);
      if (rnd() < 0.3) o.tenantId = pick(['a1', 'a2']);
      if (rnd() < 0.4) o.realm = pick(REALMS.filter((r) => r !== undefined));
      if (rnd() < 0.4) o.limit = pick([1, 2, 5, 0]);
      if (rnd() < 0.2) o.canSee = true;
      return o;
    };
    const jsOptions = (o) => { const j = { ...o }; if (o.canSee) j.canSee = (d) => !hiddenIds.includes(d.id); return j; };
    if (kind === 'upsert') {
      const d = makeDoc(int(8));
      if (rnd() < 0.1) d.id = '';
      script.push(['upsert', d]);
      const r = index.upsert(JSON.parse(JSON.stringify(d)));
      out.push(`${flag(r.ok)}:${r.error || ''}`);
    } else if (kind === 'batch') {
      const docs = Array.from({ length: 1 + int(5) }, () => makeDoc(int(8)));
      script.push(['batch', docs]);
      const r = index.batchUpsert(docs.map((d) => JSON.parse(JSON.stringify(d))));
      out.push(`${r.upserted},${r.errors},${r.deduplicated}`);
    } else if (kind === 'remove') { const id = pick(['d0', 'd1', 'zz']); script.push(['remove', id]); index.remove(id); out.push('r'); }
    else if (kind === 'batchRemove') { const ids = [pick(['d0', 'd1']), pick(['d2', 'zz'])]; script.push(['batchRemove', ids]); out.push(String(index.batchRemove(ids).removed)); }
    else if (kind === 'size') { script.push(['size']); out.push(String(index.size())); }
    else if (kind === 'has') { const id = pick(['d0', 'd3']); script.push(['has', id]); out.push(flag(index.has(id))); }
    else if (kind === 'query' || kind === 'queryUser') {
      const text = pick(['sales', 'invoice', 'customer', 'crm-482', 'order', 'zzz', 'plan notes', '']);
      const o = queryOptions();
      if (kind === 'queryUser') {
        const user = pick(['u1', 'u2']);
        script.push(['queryUser', text, o, user]);
        out.push(renderCands(index.query(text, { ...jsOptions(o), boost: recents.boostFor(user) })));
      } else {
        script.push(['query', text, o]);
        out.push(renderCands(index.query(text, jsOptions(o))));
      }
    } else if (kind === 'queryScoped' || kind === 'suggest') {
      const text = pick(['sales', 'invoice', 'customer', 'order', 'zzz']);
      const o = queryOptions();
      script.push([kind, text, o]);
      if (kind === 'suggest') out.push(index.suggest(text, jsOptions(o)).map((s) => `${hex(s.id)}:${hex(s.title)},`).join(''));
      else {
        const r = index.queryScoped(text, jsOptions(o));
        out.push(`${r.results.map((c) => `${hex(c.id)}:${hex(c.title)}:${c.kind}:${num(c.score)}:${hex(c.key ?? '')}:${hex(c.tableId ?? '')};`).join('')}|${r.total}|${renderCounts(r.counts)}|${r.suggestions.map((s) => `${hex(s.id)}:${hex(s.title)}:${s.kind};`).join('')}`);
      }
    } else if (kind === 'scopedStats') {
      const r = pick(['r1', 'r2', undefined, '  ']);
      script.push(['scopedStats', r === undefined ? null : r]);
      const st = index.scopedStats(r);
      out.push(`${renderCounts({ total: st.total, byKind: st.byKind, byRealm: st.byRealm })}|${st.upserted},${st.removed},${st.errors}`);
    } else if (kind === 'stats') {
      script.push(['stats']);
      const st = index.stats();
      out.push(`${st.documentCount}|${st.upserted},${st.removed},${st.errors}${Object.entries(st.byKind).map(([n, v]) => `|${n}=${v}`).join('')}${Object.entries(st.byTenant).map(([n, v]) => `|t:${hex(n)}=${v}`).join('')}`);
    } else if (kind === 'drop') {
      const r = pick(['r1', 'r2', '', undefined]);
      script.push(['drop', r === undefined ? null : r]);
      const x = index.dropRealmAndUnattributed(r);
      out.push(`${flag(x.ok)}:${x.reason || ''}:${x.removed},${x.unattributed}`);
    } else if (kind === 'clear') { script.push(['clear']); index.clear(); out.push('c'); }
    else if (kind === 'drain') {
      const batch = rnd() < 0.4;
      const events = mkEvents(batch ? 110 + int(20) : 1 + int(6));
      script.push(['drain', events, { batch, now: NOW_ISO }]);
      const r = consumer.drain(events, { batchMode: batch });
      out.push(`${r.processed},${r.upserts},${r.removals},${r.errors},${r.cursor}${r.deadLetters.map((d) => `${d.seq}:${hex(d.artifactId)}:${hex(d.error)}:${hex(d.at)};`).join('')}`);
    } else if (kind === 'backlog') {
      const events = mkEvents(int(5));
      script.push(['backlog', events]);
      const b = consumer.backlog(events);
      out.push(`${b.depth},${b.oldestSeq === null ? '-' : b.oldestSeq},${b.oldestAt === null || b.oldestAt === undefined ? '-' : hex(b.oldestAt)},${b.cursor}`);
    } else if (kind === 'wedged') {
      const events = rnd() < 0.2 ? mkEvents(1100) : mkEvents(int(4));
      script.push(['wedged', events, { nowMs: FIXED }]);
      const w = consumer.isWedged(events);
      out.push(`${flag(w.wedged)}:${hex(w.reason || '')}`);
    } else if (kind === 'cstats') {
      const events = mkEvents(int(4));
      script.push(['cstats', events, { nowMs: FIXED }]);
      const st = consumer.stats(events);
      out.push(`${st.cursor},${st.totalProcessed},${st.totalUpserts},${st.totalRemovals},${st.lastDrainAt === null ? '-' : hex(st.lastDrainAt)},${st.deadLetterCount},${st.depth},${flag(st.wedged)}:${hex(st.reason || '')}`);
    } else if (kind === 'clearDead') { script.push(['clearDead']); consumer.clearDeadLetters(); out.push('d'); }
    else if (kind === 'touch') { const u = pick(['u1', 'u2']); const id = pick(['d0', 'd1', 'd2', 'd3', 'd4']); const at = pick(['t1', 't2']); script.push(['touch', u, id, at]); recents.touch(u, id, at); out.push('t'); }
    else if (kind === 'recents') { const u = pick(['u1', 'u2']); const n = pick([1, 2, 10]); script.push(['recents', u, { n }]); out.push(recents.recents(u, n).map((r) => `${hex(r.id)}:${hex(r.at)},`).join('')); }
    else if (kind === 'fav') { const u = pick(['u1', 'u2']); const id = pick(['d0', 'd1', 'd2']); script.push(['fav', u, id]); recents.favorite(u, id); out.push('f'); }
    else if (kind === 'unfav') { const u = pick(['u1', 'u2']); const id = pick(['d0', 'd1', 'd2']); script.push(['unfav', u, id]); recents.unfavorite(u, id); out.push('u'); }
    else if (kind === 'isFav') { const u = pick(['u1', 'u2']); const id = pick(['d0', 'd1', 'd2']); script.push(['isFav', u, id]); out.push(flag(recents.isFavorite(u, id))); }
    else { const u = pick(['u1', 'u2']); const vis = pick([['d0', 'd1'], [], ['d2']]); script.push(['purge', u, vis]); recents.purgeForUser(u, vis); out.push('p'); }
  }
  add({ op: 'pipeline', enforceRealm, ...(realm !== undefined ? { realm } : {}), source, failIds, skipIds, hiddenIds, recentsLimit: 0, script, e: out.map((x) => `${x};`).join('') });
}

const chunks = [];
const size = 12;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'search_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_fulltext/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_fulltext`);
