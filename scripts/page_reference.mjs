// Reference vectors for `e.algo.page` and `e.algo.batch` (L033): run appdor's own records engine, bulk planner and
// undo stack (src/grid-ops), row windowing (src/grid/virtual-rows.js) and limits (src/performance/limits.js) over
// scripted inputs and write the link fixture tests/selfhost/fixtures/link/algo_page_batch. APPDOR_DIR defaults to
// D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const engine = await load('src/grid-ops/records-engine.js');
const bulk = await load('src/grid-ops/bulk.js');
const undoMod = await load('src/grid-ops/undo-redo.js');
const rowsMod = await load('src/grid/virtual-rows.js');
const limits = await load('src/performance/limits.js');

const hex = (s) => (s === '' ? '_' : Buffer.from(String(s), 'utf8').toString('hex'));
const num = (n) => String(n);
const flag = (b) => (b ? '1' : '0');
function renderValue(v) {
  if (v === null || v === undefined) return '_';
  if (typeof v === 'number') return `N${String(v)}`;
  if (typeof v === 'string') return `T${hex(v)}`;
  if (typeof v === 'boolean') return v ? 'B1' : 'B0';
  if (Array.isArray(v)) return `[${v.map(renderValue).join(',')}]`;
  return 'O';
}
const renderFields = (r) => Object.entries(r).map(([k, v]) => `${hex(k)}=${renderValue(v)},`).join('');

let seed = 0xbeef;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const wire = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));

const cases = [];
const add = (o) => cases.push(JSON.stringify(o));

// prefixes and keys
for (const name of ['Sales Invoices', 'Customers', '', '  ', 'a', 'ab', 'abcd', 'one two three four five', 'Åland Orders', 'x  y', 'The Quick Brown Fox Jumps', '123 456', 'ß ss']) {
  add({ op: 'prefix', name, e: engine.createKeyMinter().prefixFor(name) });
}
for (const key of ['INV-1042', 'ab-1', 'ABCDEFG-1', 'A-1', 'INV-', 'INV-12x', 'inv-1', 'INV-007', 'INV-1-2', '', null, 'AB-99999999999999999999']) {
  const r = engine.parseRecordKey(key);
  add({ op: 'parsekey', key, e: r ? `${r.prefix}:${r.number}` : 'null' });
}
for (let k = 0; k < 20; k += 1) {
  const initial = pick([{}, { tbl_a: 5 }, { tbl_a: 3, tbl_b: 10 }]);
  const minter = engine.createKeyMinter(initial);
  const script = [];
  const out = [];
  for (let s = 0; s < 6; s += 1) {
    const t = pick(['tbl_a', 'tbl_b', 'tbl_c']);
    const kind = pick(['mint', 'many', 'reserve', 'counter', 'snap']);
    if (kind === 'mint') { script.push(['mint', t, 'INV']); out.push(minter.mint(t, 'INV')); }
    else if (kind === 'many') { const n = 1 + int(3); script.push(['many', t, 'SI', n]); out.push(minter.mintMany(t, 'SI', n).join(',')); }
    else if (kind === 'reserve') { const n = int(20); script.push(['reserve', t, n]); minter.reserve(t, n); out.push('r'); }
    else if (kind === 'counter') { script.push(['counter', t]); out.push(String(minter.counterOf(t))); }
    else { script.push(['snap']); out.push(Object.entries(minter.snapshot()).map(([n, v]) => `${n}=${v},`).join('')); }
  }
  add({ op: 'keys', initial, script, e: out.map((x) => `${x};`).join('') });
}

// keyset paging
const VALUES = [1, 2, 10, 'a', 'B', 'b', '', null, true, false, 0, -1, '10', '9', 2.5];
function makeRows(n) {
  return Array.from({ length: n }, (_, i) => {
    const r = { id: `r${String(i).padStart(3, '0')}`, '~idx': `\u0001${i}` };
    if (rnd() < 0.9) r.a = pick(VALUES);
    if (rnd() < 0.9) r.b = pick(VALUES);
    return r;
  });
}
for (let k = 0; k < 60; k += 1) {
  const rows = makeRows(2 + int(25));
  const sort = Array.from({ length: int(3) }, () => ({ field: pick(['a', 'b', 'id']), dir: pick(['asc', 'desc', undefined]) }));
  const limit = pick([1, 2, 3, 5, 50, 0, undefined]);
  let cursor = null;
  for (let page = 0; page < 5; page += 1) {
    const opts = { sort };
    if (limit !== undefined) opts.limit = limit;
    if (cursor) opts.cursor = cursor;
    const r = engine.paginate(rows.slice(), opts);
    const e = !r.ok ? `no:${r.error}` : `${r.records.map((x) => `${String(x['~idx']).slice(1)},`).join('')}|${r.nextCursor === null ? '-' : r.nextCursor}|${flag(r.hasMore)}`;
    add({ op: 'page', rows, sort: wire(sort), ...(limit === undefined ? {} : { limit }), cursor, e });
    if (!r.ok || !r.nextCursor) break;
    cursor = r.nextCursor;
  }
}
for (const cursor of ['zzzz', 'bnVsbA==', 'MA==', 'W10=', 'InMi', 'eyJhIjoxfQ==', 'NQ==', 'eyJhIjoxfQ', '!!!', 'e30=', 'eyJpZCI6InIwMDEifQ==']) {
  const rows = makeRows(6);
  const r = engine.paginate(rows.slice(), { sort: [{ field: 'a' }], limit: 2, cursor });
  add({ op: 'page', rows, sort: [{ field: 'a' }], limit: 2, cursor, e: !r.ok ? `no:${r.error}` : `${r.records.map((x) => `${String(x['~idx']).slice(1)},`).join('')}|${r.nextCursor === null ? '-' : r.nextCursor}|${flag(r.hasMore)}` });
}
// duplication
for (let k = 0; k < 24; k += 1) {
  const table = { id: 't1', name: 'Tasks', columns: [
    { id: 'c1', name: 'Title', type: 'text' }, { name: 'Parent', type: 'link', config: { linkedTableId: pick(['t1', 't1', 't2', 5]) } },
    { id: 'c3', name: 'Subs', type: 'link', config: { linkedTableId: 't1' } }, { id: 'c4', name: 'Other', type: 'link', config: { linkedTableId: 't9' } },
  ] };
  const rows = Array.from({ length: int(5) }, (_, i) => {
    const r = { id: `row-${i}`, Title: `T${i}` };
    if (rnd() < 0.8) r.Parent = pick(['row-0', 'row-1', 'row-9', null, '']);
    if (rnd() < 0.8) r.Subs = pick([['row-0', 'row-2'], [], ['row-9'], null, 'row-1']);
    if (rnd() < 0.5) r.Other = 'row-0';
    return r;
  });
  const opts = { withRecords: rnd() < 0.7 };
  if (rnd() < 0.4) opts.newId = 't1b';
  if (rnd() < 0.4) opts.newName = 'Renamed';
  const minter = engine.createKeyMinter();
  const d = engine.duplicateTable(table, rows, { ...opts, keyMinter: minter });
  add({ op: 'dup', table, rows, withRecords: opts.withRecords, newId: opts.newId ?? '', newName: opts.newName ?? '',
    e: `${hex(d.table.id)}|${hex(d.table.name)}|${d.table.columns.map((c) => `${c.id === undefined ? '_' : hex(c.id)}:${hex(c.name)}:${c.type}:${c.config && c.config.linkedTableId !== undefined ? hex(String(c.config.linkedTableId)) : '-'};`).join('')}|${d.records.map((r) => `${renderFields(r)};`).join('')}|${Object.entries(d.idMap).map(([from, to]) => `${hex(from)}>${hex(to)};`).join('')}|${minter.counterOf(d.table.id)}` });
}
// windows and limits
for (let k = 0; k < 60; k += 1) {
  const p = { total: pick([0, 1, 10, 50, 1000, 100000]), scrollTop: pick([0, 33, 500, 99999, 33000, 1e7]), viewportHeight: pick([0, 100, 600, 800]), rowHeight: pick([undefined, 20, 33, 0, 40.5]) };
  if (rnd() < 0.4) p.overscan = pick([0, 1, 3, 10]);
  const r = rowsMod.planRows(p);
  add({ op: 'rows', ...p, e: `${r.startIndex},${r.endIndex},${r.topSpacer},${r.bottomSpacer},${r.ariaRowCount}` });
}
for (const n of [0, 1, 999, 1000, 1001, 99999, 100000, 100001, 250000, 1234567, -5, 'x']) {
  for (const locale of ['en', 'bg', undefined]) {
    const l = limits.loadPlan(n, locale);
    add({ op: 'load', n, locale: locale ?? '', e: `${l.loaded}|${flag(l.truncated)}|${l.requests}|${l.notice === null ? '-' : hex(l.notice)}` });
  }
}
for (let k = 0; k < 20; k += 1) {
  const values = Array.from({ length: int(10) }, () => pick([1, 5, 12, 7, 3, 9, 100, null, NaN, 2.5]));
  const p = pick([0, 0.25, 0.5, 0.75, 0.95, 1]);
  const r = limits.percentile(values, p);
  add({ op: 'percentile', values: values.map((v) => (Number.isNaN(v) ? null : v)), p, e: Number.isNaN(r) ? 'nan' : String(r) });
}
for (const name of ['formSubmissionP95', 'gridSortAtScale', 'pageReferenceInteractiveP75', 'nope', 'recordScriptOutcome']) {
  for (const ms of [0, 100, 1000, 1500, 2000.5, 99999]) {
    const r = limits.withinBudget(name, ms);
    add({ op: 'budget', name, ms, e: `${flag(r.ok)}|${hex(r.message)}` });
  }
}

// batches
for (let k = 0; k < 40; k += 1) {
  const ids = Array.from({ length: int(12) }, (_, i) => pick([`id${i}`, i, `x${i}`]));
  const fail = {};
  const throwIds = [];
  for (const id of ids) {
    if (rnd() < 0.2) fail[String(id)] = pick(['bad', '', 'locked']);
    if (rnd() < 0.1) throwIds.push(String(id));
  }
  const opts = {};
  if (rnd() < 0.6) opts.chunkSize = pick([1, 2, 3, 5]);
  if (rnd() < 0.4) opts.startIndex = int(4);
  let ledger;
  if (rnd() < 0.3) ledger = { succeeded: ['prev1'], failed: [{ recordId: 'prev2', error: 'old' }] };
  const apply = async (id) => {
    if (throwIds.includes(String(id))) throw new Error(`boom ${id}`);
    if (Object.prototype.hasOwnProperty.call(fail, String(id))) return { ok: false, error: fail[String(id)] };
    return { ok: true };
  };
  const r = await engine.runBatch(ids, apply, { ...opts, ...(ledger ? { ledger: JSON.parse(JSON.stringify(ledger)) } : {}) });
  add({ op: 'batch', ids, fail, throwIds, ...(opts.chunkSize ? { chunkSize: opts.chunkSize } : {}), ...(opts.startIndex ? { startIndex: opts.startIndex } : {}), ...(ledger ? { ledger } : {}),
    e: `${r.processed}|${r.total}|${flag(r.done)}|${r.nextIndex === null ? '-' : r.nextIndex}|${r.summary.succeeded},${r.summary.failed}|${r.ledger.succeeded.map((x) => `${renderValue(x)},`).join('')}|${r.ledger.failed.map((x) => `${renderValue(x.recordId)}:${hex(x.error)};`).join('')}|${engine.describeBatch(r)}` });
}

// bulk
const renderPlan = (p) => {
  let out = `${flag(p.ok)}|${hex(p.error || '')}|${(p.denied || []).map((d) => `${renderValue(d.id)}:${hex(d.reason)};`).join('')}`;
  if (!p.ok) return out;
  out += `|${hex(p.correlationId)}|${renderFields(p.patch)}|${p.total}|${(p.skipped || []).map((d) => `${renderValue(d.id)}:${hex(d.reason)};`).join('')}|${p.chunks.map((c) => `${c.map((x) => `${renderValue(x)},`).join('')}/`).join('')}|${p.mode}`;
  return out;
};
for (let k = 0; k < 60; k += 1) {
  const targets = rnd() < 0.05 ? [] : Array.from({ length: 1 + int(9) }, (_, i) => pick([`a${i}`, i]));
  const patch = rnd() < 0.1 ? {} : { Status: 'Done', ...(rnd() < 0.3 ? { Qty: 5 } : {}) };
  const deny = {};
  for (const t of targets) if (rnd() < 0.2) deny[String(t)] = pick(['no', '']);
  const input = { targets, patch, correlationId: 'c-1' };
  if (rnd() < 0.5) input.authorize = (id) => (Object.prototype.hasOwnProperty.call(deny, String(id)) ? { ok: false, reason: deny[String(id)] } : true);
  if (rnd() < 0.4) input.onDenied = 'skip';
  if (rnd() < 0.5) input.chunkSize = pick([1, 2, 3, 0, -4]);
  if (rnd() < 0.3) input.syncThreshold = pick([0, 2, 5]);
  const plan = bulk.planBulkMutation(input);
  const wirePlan = { op: 'bulk', targets, patch, correlationId: 'c-1', ...(input.authorize ? { deny } : {}), ...(input.onDenied ? { onDenied: input.onDenied } : {}), ...(input.chunkSize !== undefined ? { chunkSize: input.chunkSize } : {}), ...(input.syncThreshold !== undefined ? { syncThreshold: input.syncThreshold } : {}) };
  if (rnd() < 0.5 || !plan.ok) { add({ ...wirePlan, e: renderPlan(plan) }); continue; }
  // run it
  const fail = {};
  for (const t of targets) if (rnd() < 0.25) fail[String(t)] = pick(['bad', '', 'locked', 'bad']);
  const throwChunks = rnd() < 0.3 ? [1 + int(3)] : [];
  const voidChunks = rnd() < 0.2;
  let chunkNo = 0;
  const cancelAfter = rnd() < 0.2 ? 1 + int(2) : null;
  const apply = (ids) => {
    chunkNo += 1;
    if (throwChunks.includes(chunkNo)) throw new Error('boom');
    if (voidChunks) return undefined;
    return ids.map((id) => (Object.prototype.hasOwnProperty.call(fail, String(id)) ? { id, ok: false, error: fail[String(id)] } : { id, ok: true }));
  };
  const events = [];
  const result = await bulk.runBulkMutation(plan, { apply, isCancelled: cancelAfter === null ? undefined : () => chunkNo >= cancelAfter, onProgress: (p) => events.push(p) });
  const summary = bulk.summarizeBulkOutcome(result);
  const e = `${renderPlan(plan)}#${flag(result.ok)}:${hex(result.error || '')}:${flag(result.cancelled)}:${result.total},${result.applied},${result.failed}#${result.outcomes.map((o) => `${renderValue(o.id)}:${flag(o.ok)}:${hex(o.error || '')};`).join('')}#${events.map((p) => `${p.done}/${p.total}/${p.applied}/${p.failed}/${p.percent};`).join('')}#${flag(summary.ok)}:${hex(summary.headline)}:${Object.entries(summary.byReason).map(([r, c]) => `${hex(r)}=${c},`).join('')}`;
  add({ ...wirePlan, run: true, fail, throwChunks, voidChunks, ...(cancelAfter === null ? {} : { cancelAfter }), e });
}

// undo scripts
const renderStep = (r) => (!r.ok ? `no:${r.error}` : `ok:${r.label === null || r.label === undefined ? '-' : hex(r.label)}:${r.writes.map((w) => `${renderValue(w.recordId)}.${hex(w.field)}=${renderValue(w.value)}${'expected' in w ? `~${renderValue(w.expected)}` : ''};`).join('')}`);
for (let k = 0; k < 50; k += 1) {
  const depth = pick([2, 3, 100, undefined]);
  let scopeValue = 'acct';
  const stack = undoMod.createUndoStack({ ...(depth === undefined ? {} : { depth }), scope: () => scopeValue });
  const script = [];
  const out = [];
  const handles = [];
  const mkChanges = () => Array.from({ length: 1 + int(3) }, () => [pick(['r1', 'r2', 3]), pick(['Name', 'Qty']), pick([null, 1, 'a']), pick([2, 'b', null])]);
  for (let s = 0; s < 10; s += 1) {
    const e = pick(['ann', 'bob']);
    const t = pick(['t1', 't2']);
    const kind = pick(['push', 'push', 'undo', 'redo', 'state', 'prepareUndo', 'prepareRedo', 'commit', 'scope', 'bulkChanges']);
    if (kind === 'push') {
      const ch = mkChanges();
      const label = pick([undefined, 'edit']);
      script.push(['push', e, t, ch, ...(label === undefined ? [] : [label])]);
      const r = stack.push(e, t, ch.map(([recordId, field, before, after]) => ({ recordId, field, before, after })), label === undefined ? {} : { label });
      out.push(String(r.undoDepth));
    } else if (kind === 'undo') { script.push(['undo', e, t]); out.push(renderStep(stack.undo(e, t))); }
    else if (kind === 'redo') { script.push(['redo', e, t]); out.push(renderStep(stack.redo(e, t))); }
    else if (kind === 'state') { script.push(['state', e, t]); const st = stack.state(e, t); out.push(`${flag(st.canUndo)}${flag(st.canRedo)}${st.undoDepth}`); }
    else if (kind === 'prepareUndo' || kind === 'prepareRedo') {
      script.push([kind, e, t]);
      const r = kind === 'prepareUndo' ? stack.prepareUndo(e, t) : stack.prepareRedo(e, t);
      out.push(renderStep(r));
      if (r.ok) handles.push(r);
    } else if (kind === 'commit') {
      script.push(['commit', handles.length ? int(handles.length) : 0, []]);
      const h = handles.length ? script[script.length - 1][1] : -1;
      const ack = h >= 0 ? handles[h].writes.filter(() => rnd() < 0.6).map((w) => [w.recordId, w.field]) : [];
      script[script.length - 1][2] = ack;
      const n = h >= 0 ? handles[h].commit(ack.map(([recordId, field]) => ({ recordId, field }))) : 0;
      out.push(String(n));
    } else if (kind === 'scope') { const v = pick(['acct', 'other']); script.push(['scope', v]); scopeValue = v; out.push('s'); }
    else {
      const rows = [{ id: 'r1', Name: 'x' }, { id: 'r2', Qty: 3 }];
      const ids = pick([['r1'], ['r1', 'r2', 'r9'], []]);
      script.push(['bulkChanges', rows, ids, 'Name', 'z']);
      out.push(undoMod.bulkChanges(rows, ids, 'Name', 'z').map((c) => `${renderValue(c.recordId)}:${renderValue(c.before)}>${renderValue(c.after)},`).join(''));
    }
  }
  add({ op: 'undo', ...(depth === undefined ? {} : { depth }), script, e: out.map((x) => `${x};`).join('') });
}

const chunks = [];
const size = 20;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'page_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_page_batch/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_page_batch`);
