// Reference vectors for `e.algo.view` and `e.algo.pivot` (L032): random record sets, field descriptors, filter
// trees, view configs, chart, KPI, pivot and server-aggregate configs, run through appdor's own engine
// (src/views/query.js, grid/filter-tree.js, grid/multi-sort.js, charts/*, pivot/index.js), written as the link
// fixture tests/selfhost/fixtures/link/algo_query. Run with TZ=UTC: appdor reads a zone-less date-time in the zone
// of the machine in two places. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const query = await load('src/views/query.js');
const tree = await load('src/grid/filter-tree.js');
const aggregateMod = await load('src/charts/aggregate.js');
const server = await load('src/charts/server-aggregate.js');
const pivot = await load('src/pivot/index.js');
const buckets = await load('src/charts/buckets.js');

const hex = (s) => (s === '' ? '_' : Buffer.from(String(s), 'utf8').toString('hex'));
const NOW = '2026-02-01T12:00:00.000Z';
const CTX = { now: NOW, userId: 'u1' };
const num = (n) => String(n);

function renderValue(v) {
  if (v === null || v === undefined) return '_';
  if (typeof v === 'number') return `N${String(v)}`;
  if (typeof v === 'string') return `T${hex(v)}`;
  if (typeof v === 'boolean') return v ? 'B1' : 'B0';
  if (v instanceof Date) return `D${v.toISOString()}`;
  if (Array.isArray(v)) return `[${v.map(renderValue).join(',')}]`;
  return 'O';
}
const renderCell = (v) => (v === null || v === undefined ? '_' : num(v));
const idxOf = (r) => String(r['~idx']).slice(1);
const renderRows = (rs) => rs.map(idxOf).join(',');

let seed = 0xa11ce;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

const FIELDS = [
  { name: 'Name', type: 'text' }, { name: 'Qty', type: 'number' }, { name: 'Price', type: 'currency' },
  { name: 'Status', type: 'select', options: ['open', 'blocked', 'closed'], optionColors: { open: 'green', closed: 'grey', blocked: '' } },
  { name: 'Tags', type: 'multiselect' }, { name: 'Due', type: 'date' }, { name: 'Stamp', type: 'datetime' },
  { name: 'Done', type: 'checkbox' }, { name: 'Owner', type: 'user' }, { name: 'Score', type: 'rating' }, { name: 'Notes', type: 'text' },
  { name: 'Files', type: 'attachment' },
];
const POOLS = {
  Name: ['Ada', 'ada lovelace', 'Bob', '', null, 'Zed', 'éclair', 'Éclair', '10', '9', 'a_b', 'A-B', 'Ångström', 'ZED', 'cy', 'Cy'],
  Qty: [0, 1, 2, 5, 10, -3, '7', '', null, 'abc', 2.5, 100],
  Price: [0, 9.99, 10, '12.5', null, 1000, -1],
  Status: ['open', 'closed', 'blocked', 'weird', null, '', 'Open'],
  Tags: [[], ['a'], ['a', 'b'], ['b'], ['x', 'y', 'z'], null, 'a', ['a', 'a']],
  Due: ['2026-01-15', '2026-01-16T10:00:00Z', '2026-02-01', '2026-02-01T00:00:00', '2026-06-15', null, '', 'bogus', '1/2/2026', '2025-12-31', '2026-02-02'],
  Stamp: ['2026-01-15 08:30', '2026-02-01T23:59:59Z', '2026-02-02T00:00', null, 'x'],
  Done: [true, false, null, 'true', 1, 0, '1'],
  Owner: ['u1', 'u2', null, ''],
  Score: [1, 2, 3, 4, 5, null, '3'],
  Notes: ['hello world', 'Hello', 'goodbye', '', null, 'a/b', '10/5', 'x'],
  Files: [[{ name: 'a', size: 100 }, { name: 'b', size: 50 }], [{ name: 'c', size: 'x' }], 'plain', null, [], { name: 'd', size: 7 }],
};
function makeRow(i) {
  const r = {};
  for (const f of FIELDS) {
    if (rnd() < 0.08) continue; // a missing key
    r[f.name] = JSON.parse(JSON.stringify(pick(POOLS[f.name])));
  }
  r['~idx'] = `\u0001${i}`;
  return r;
}
const makeRows = (n) => Array.from({ length: n }, (_, i) => makeRow(i));

const OPS = {
  text: ['contains', 'notContains', 'is', 'isNot', 'startsWith', 'endsWith', 'isEmpty', 'isNotEmpty'],
  number: ['=', '!=', '<', '<=', '>', '>=', 'isEmpty', 'isNotEmpty'],
  select: ['is', 'isNot', 'isAnyOf', 'isNoneOf', 'isEmpty', 'isNotEmpty'],
  multiselect: ['hasAnyOf', 'hasAllOf', 'hasNoneOf', 'isEmpty', 'isNotEmpty'],
  checkbox: ['isChecked', 'isUnchecked'],
  date: ['on', 'before', 'after', 'onOrBefore', 'onOrAfter', 'within', 'isEmpty', 'isNotEmpty'],
  user: ['is', 'isNot', 'isCurrentUser', 'isEmpty', 'isNotEmpty'],
};
const familyOf = (t) => (['number', 'currency', 'percent', 'rating'].includes(t) ? 'number' : ['date', 'datetime'].includes(t) ? 'date' : OPS[t] ? t : 'text');
const OPERANDS = {
  text: ['a', 'ada', 'ED', '', '10', 'o', 'x', null],
  number: [0, 1, 5, '2', 'abc', '', null, 2.5, 100],
  select: ['open', 'closed', 'weird', ['open', 'closed'], [], null, ''],
  multiselect: ['a', ['a'], ['a', 'b'], [], ['q'], null],
  date: ['today', 'yesterday', 'tomorrow', '2026-01-16', '2026-02-01', { relative: 'today' }, { relative: 'yesterday' }, { relative: 'tomorrow' }, { relative: 'lastNDays', days: 3 },
    { relative: 'nextNDays', days: 2 }, { start: '2026-01-01', end: '2026-01-31' }, { start: '2026-02-01' }, { end: '2026-01-20' }, { start: 'bogus' }, 'bogus', '', null, 5, '2026-02-01T00:00:00'],
  user: ['u1', 'u2', null, ''],
};
function randomCondition() {
  const f = pick(FIELDS);
  const family = familyOf(f.type);
  const c = { field: f.name, op: pick(OPS[family]) };
  if (rnd() < 0.15) c.type = pick(['text', 'number', 'select', 'date', 'multiselect', 'checkbox', 'user', 'weird']);
  const eff = c.type || f.type;
  const fam = familyOf(eff);
  if (!OPS[fam].includes(c.op) && rnd() < 0.5) c.op = pick(OPS[fam]);
  if (rnd() < 0.9) c.value = pick(OPERANDS[fam] || OPERANDS.text);
  if (rnd() < 0.04) { c.expr = pick(['{Qty} > 1', '{Name} = "Bob"', '1/0', 'NOPE(1)', '{Done}', 'LEN({Name}) > 2']); }
  if (rnd() < 0.05) { c.op = pick(['inBucket', 'notInBuckets']); c.bucket = pick(['month', 'year', { size: 5 }, 'day', undefined]); c.value = pick(['2026-02', '2026', '0–5', 'open', null]); c.values = pick([['2026-02'], ['2026-01', '2026-02'], [null], ['open']]); }
  return c;
}
function randomTree(depth) {
  if (depth <= 0 || rnd() < 0.5) return randomCondition();
  return { operator: pick(['and', 'or']), children: Array.from({ length: int(4) }, () => randomTree(depth - 1)) };
}
const wire = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));

const cases = [];
const add = (o) => cases.push(JSON.stringify(o));
const evalCtx = { ...CTX };

// filters
for (let k = 0; k < 160; k += 1) {
  const rows = makeRows(4 + int(8));
  const t = rnd() < 0.05 ? null : randomTree(1 + int(3));
  const out = t === null ? rows.slice() : query.filterRecords(rows, t, FIELDS, evalCtx);
  add({ op: 'filter', rows, fields: FIELDS, tree: wire(t), ctx: CTX, e: renderRows(out) });
}
// sorts
for (let k = 0; k < 90; k += 1) {
  const rows = makeRows(2 + int(70));
  const sorts = Array.from({ length: 1 + int(3) }, () => ({ field: pick(FIELDS).name, direction: pick(['asc', 'desc', undefined]) }));
  add({ op: 'sort', rows, fields: FIELDS, sorts: wire(sorts), e: renderRows(query.sortRecords(rows, sorts, FIELDS)) });
}
// groups
for (let k = 0; k < 60; k += 1) {
  const rows = makeRows(3 + int(10));
  const spec = rnd() < 0.5 ? pick(FIELDS).name : { field: pick(FIELDS).name, direction: pick(['asc', 'desc']) };
  const groups = query.groupRecords(rows, spec, FIELDS);
  add({ op: 'group', rows, fields: FIELDS, spec, e: groups.map((g) => `${g.value === null ? 'null' : renderValue(g.value)}/${hex(g.label)}=${renderRows(g.records)};`).join('') });
}
// summaries
const FNS = Object.keys(query.SUMMARY_FUNCTIONS).concat(['bogus']);
const render = (s) => {
  if (s === null || s === undefined) return '-';
  if (typeof s === 'number') return `n${s}`;
  if (s instanceof Date) return `d${s.toISOString()}`;
  if (s.kind === 'bytes') return `b${s.bytes}`;
  if (s.kind === 'distribution') return `dist${s.entries.map((e) => `:${hex(e.label)}=${e.count}`).join('')}`;
  return '?';
};
for (const fn of FNS) {
  for (let k = 0; k < 14; k += 1) {
    const field = pick(['Qty', 'Name', 'Due', 'Tags', 'Done', 'Status', 'Score', 'Files', 'Price']);
    const values = Array.from({ length: int(9) }, () => JSON.parse(JSON.stringify(pick(POOLS[field]))));
    const out = query.SUMMARY_FUNCTIONS[fn] ? query.SUMMARY_FUNCTIONS[fn](values) : null;
    add({ op: 'summary', values, fn, e: render(out) });
  }
}
// colors and search
for (let k = 0; k < 40; k += 1) {
  const row = makeRow(0);
  const color = pick([
    { mode: 'none' }, { mode: 'select', field: 'Status' }, { mode: 'select', field: 'Name' },
    { mode: 'rules', rules: [{ filter: randomTree(2), color: 'red' }, { expr: '{Qty} > 2', color: 'blue' }, { filter: randomCondition(), color: 'green' }] }, { mode: 'rules' }, undefined,
  ]);
  const c = query.rowColor(row, color, FIELDS, evalCtx);
  add({ op: 'color', row, color: wire(color), fields: FIELDS, ctx: CTX, e: c === null ? 'none' : hex(c) });
}
for (let k = 0; k < 40; k += 1) {
  const rows = makeRows(4 + int(6));
  const term = pick(['a', 'ADA', 'hello', '10', '', 'x', 'true', 'zz', 'u1', 'open']);
  const names = pick([undefined, [], ['Name'], ['Name', 'Tags'], ['Notes', 'Qty']]);
  add({ op: 'search', rows, term, names: wire(names), e: renderRows(query.quickSearch(rows, term, names)) });
}
// buckets
for (let k = 0; k < 90; k += 1) {
  const value = pick([...POOLS.Due, ...POOLS.Qty, ...POOLS.Name]);
  const bucket = pick([undefined, 'year', 'month', 'quarter', 'day', 'week', { size: 5 }, { size: 2 }, 'weird']);
  const key = buckets.bucketKey(value, bucket);
  add({ op: 'bucket', value: wire(value), bucket: wire(bucket), e: key === buckets.NO_VALUE ? 'none' : hex(String(key)) });
}
// views
for (let k = 0; k < 70; k += 1) {
  const rows = makeRows(3 + int(12));
  const config = {};
  if (rnd() < 0.6) config.filters = randomTree(2);
  if (rnd() < 0.3) { config.search = pick(['a', 'b', 'ada']); if (rnd() < 0.5) config.searchFields = pick([['Name'], ['Notes', 'Name']]); }
  if (rnd() < 0.6) config.sorts = Array.from({ length: 1 + int(2) }, () => ({ field: pick(FIELDS).name, direction: pick(['asc', 'desc']) }));
  if (rnd() < 0.4) config.summaries = Object.fromEntries(Array.from({ length: 1 + int(3) }, () => [pick(FIELDS).name, pick(['count', 'filled', 'sum', 'min', 'max', 'unique', 'distribution', 'average'])]));
  if (rnd() < 0.5) config.group_by = pick([['Status'], ['Status', 'Owner'], ['Done'], ['Tags']]);
  if (rnd() < 0.3) { config.visibleFields = pick([['Name', 'Qty'], ['Status']]); config.newFieldPolicy = pick(['hide', 'show']); }
  const r = query.applyView(rows, config, FIELDS, evalCtx);
  let out = '';
  if (r.visibleFields) out = r.records.map((x) => `${Object.entries(x).map(([n, v]) => `${hex(n)}=${renderValue(v)},`).join('')};`).join('');
  else out = renderRows(r.records);
  out += '|';
  if (r.summaries) out += Object.entries(r.summaries).map(([n, s]) => `${hex(n)}=${render(s)};`).join('');
  out += '|';
  if (r.groups) {
    out += r.groups.map((g) => `${g.value === null ? 'null' : renderValue(g.value)}/${hex(g.label)}:${g.count}:${(g.subgroups || []).map((s) => `${s.value === null ? 'null' : renderValue(s.value)}/${hex(s.label)}:${s.count},`).join('')}${g.summaries ? Object.entries(g.summaries).map(([n, s]) => `${hex(n)}=${render(s)},`).join('') : ''};`).join('');
  }
  add({ op: 'view', rows, config: wire(config), fields: FIELDS, ctx: CTX, e: out });
}
// filter-tree edits and sort levels
const renderTree = (t) => {
  if (t === null || t === undefined) return 'null';
  if (t.operator === 'and' || t.operator === 'or') return `G[${t.operator}](${(t.children || []).map(renderTree).join(';')})`;
  return `C[${hex(t.field)}|${t.op}|${t.type || ''}|${'value' in t ? renderValue(t.value) : 'U'}]`;
};
const simpleCond = () => { const c = randomCondition(); delete c.expr; delete c.bucket; delete c.values; if (c.op === 'inBucket' || c.op === 'notInBuckets') c.op = 'is'; return c; };
const simpleTree = (d) => (d <= 0 || rnd() < 0.4 ? simpleCond() : { operator: pick(['and', 'or']), children: Array.from({ length: int(4) }, () => simpleTree(d - 1)) });
const pathIn = (t) => {
  const p = [];
  let n = t;
  while (n && (n.operator === 'and' || n.operator === 'or') && n.children && n.children.length && rnd() < 0.7) { const i = int(n.children.length); p.push(i); n = n.children[i]; }
  if (rnd() < 0.1) p.push(7);
  return p;
};
for (let k = 0; k < 120; k += 1) {
  const t = simpleTree(3);
  const group = t.operator ? t : { operator: 'and', children: [t] };
  const p = pathIn(group);
  const action = pick(['add', 'remove', 'replace', 'toggle', 'prune', 'count', 'depth']);
  const node = simpleTree(2);
  let out;
  if (action === 'add') out = renderTree(tree.addNode(group, p, node));
  else if (action === 'remove') out = renderTree(tree.removeNode(group, p));
  else if (action === 'replace') out = renderTree(tree.replaceNode(group, p, node));
  else if (action === 'toggle') { const r = tree.toggleGroupOperator(group, p); out = `${renderTree(r.tree)}|${r.operator}`; }
  else if (action === 'prune') out = renderTree(tree.pruneTree(group));
  else if (action === 'count') out = String(tree.countConditions(group));
  else out = String(tree.treeDepth(group));
  add({ op: 'tree', tree: wire(group), action, path: p, node: wire(node), e: out });
}
const multiSort = await load('src/grid/multi-sort.js');
for (let k = 0; k < 60; k += 1) {
  const sorts = Array.from({ length: int(5) }, (_, i) => ({ field: `F${i}`, direction: pick(['asc', 'desc']) }));
  const field = pick(['F0', 'F1', 'F2', 'F3', 'F4', 'Fx']);
  const action = pick(['append', 'remove', 'move', 'level']);
  const delta = pick([-1, 1, -3, 3, 0]);
  const state = { sorts: wire(sorts), sortMode: 'manual' };
  let extra = '';
  if (action === 'append') { const d = multiSort.appendSortLevel(state, field); extra = d === null ? '' : d; }
  else if (action === 'remove') multiSort.removeSortLevel(state, field);
  else if (action === 'move') extra = multiSort.moveSortLevel(state, field, delta) ? 'moved' : '';
  else extra = String(multiSort.sortLevel(state, field));
  add({ op: 'sortlevels', sorts, action, field, delta, e: `${state.sorts.map((s) => `${hex(s.field)}:${s.direction},`).join('')}|${extra}` });
}
// charts and KPIs
const renderChart = (c) => `${c.labels.map(hex).join(',')}|${c.datasets.map((d) => `${hex(d.label)}${'splitValue' in d ? `~${d.splitValue === null ? 'null' : renderValue(d.splitValue)}` : ''}=${d.data.map(renderCell).join(',')};`).join('')}|${c.drilldown.map((d) => (d.other ? 'other;' : `${hex(d.field)}=${d.value === null ? 'null' : renderValue(d.value)};`)).join('')}`;
const AGGS = ['count', 'sum', 'avg', 'average', 'min', 'max', 'median', 'unique', 'countValues', 'weird'];
function randomChartConfig() {
  const c = { chartType: pick(['bar', 'pie', 'line']), xField: pick(['Status', 'Name', 'Due', 'Qty', 'Tags', 'Done', 'Owner']) };
  const b = pick([undefined, undefined, 'year', 'month', 'quarter', 'day', 'week', { size: 5 }, { size: 2 }]);
  if (b !== undefined) c.xBucket = b;
  if (rnd() < 0.4) c.splitField = pick(['Status', 'Owner', 'Done', 'Tags']);
  if (rnd() < 0.8) c.series = Array.from({ length: 1 + int(2) }, () => ({ aggregation: pick(AGGS), field: pick(['Qty', 'Price', 'Score', 'Name', 'Status']), ...(rnd() < 0.3 ? { label: pick(['Total', 'Avg']) } : {}) }));
  if (rnd() < 0.3) c.topN = 1 + int(3);
  if (rnd() < 0.3) c.filter = randomTree(1);
  return c;
}
for (let k = 0; k < 110; k += 1) {
  const rows = makeRows(3 + int(14));
  const config = randomChartConfig();
  add({ op: 'chart', rows, config: wire(config), fields: FIELDS, ctx: CTX, e: renderChart(aggregateMod.buildChartData(rows, config, FIELDS, evalCtx)) });
}
for (let k = 0; k < 60; k += 1) {
  const rows = makeRows(2 + int(10));
  const config = { series: [{ aggregation: pick(AGGS), field: pick(['Qty', 'Price', 'Score']) }] };
  if (rnd() < 0.4) config.filter = randomTree(1);
  if (rnd() < 0.4) config.comparison = { filter: randomTree(1) };
  if (rnd() < 0.5) config.thresholds = Array.from({ length: 1 + int(3) }, () => ({ value: pick([0, 1, 5, 10, 100, undefined]), label: pick(['low', 'mid', '']), color: pick([undefined, '#f00']), icon: pick(['', '!']) }));
  const r = aggregateMod.buildKPI(rows, config, FIELDS, evalCtx);
  let out = `${renderCell(r.value)}|${r.rowCount}`;
  if (r.comparison) out += `|${renderCell(r.comparison.value)}:${r.comparison.delta}:${renderCell(r.comparison.percentDelta)}:${r.comparison.direction}`;
  if (r.threshold) out += `|${hex(r.threshold.label)}:${r.threshold.color}:${hex(r.threshold.icon)}:${r.threshold.band}`;
  add({ op: 'kpi', rows, config: wire(config), fields: FIELDS, ctx: CTX, e: out });
}
for (let k = 0; k < 40; k += 1) {
  const thresholds = Array.from({ length: int(4) }, () => ({ value: pick([0, 1, 5, 10, undefined, -2]), label: pick(['a', 'b']), color: pick([undefined, '#0f0']), icon: pick(['', '*']) }));
  const value = pick([0, 1, 5, 7, 100, -1, null]);
  const r = aggregateMod.evaluateThresholds(value, thresholds);
  add({ op: 'eval', value, thresholds: wire(thresholds), e: r ? `${hex(r.label)}:${r.color}:${hex(r.icon)}:${r.band}` : 'none' });
}
for (let k = 0; k < 60; k += 1) {
  const rows = makeRows(3 + int(14));
  const config = { rows: pick([[], ['Status'], ['Status', 'Owner'], ['Due'], ['Qty']]), columns: pick([[], ['Done'], ['Owner'], ['Status']]), measure: pick([{ aggregation: 'count' }, { aggregation: 'sum', field: 'Qty' }, { aggregation: 'avg', field: 'Price' }, undefined]) };
  if (rnd() < 0.3) config.filter = randomTree(1);
  const r = pivot.buildPivot(rows, config, FIELDS, evalCtx);
  add({ op: 'pivot', rows, config: wire(config), fields: FIELDS, ctx: CTX, e: `${r.rowKeys.map((x) => `${hex(x)},`).join('')}|${r.columnKeys.map((x) => `${hex(x)},`).join('')}|${r.rows.map((row) => `${r.columnKeys.map((c) => `${renderCell(row.cells[c])},`).join('')}${renderCell(row.total)};`).join('')}|${r.columnKeys.map((c) => `${renderCell(r.columnTotals[c])},`).join('')}|${renderCell(r.grandTotal)}` });
}
for (let k = 0; k < 40; k += 1) {
  const rows = makeRows(3 + int(14));
  const config = { groupBy: pick([[], ['Status'], ['Status', 'Done'], ['Qty']]), measures: pick([undefined, [{ aggregation: 'sum', field: 'Qty', label: 'Total' }, { aggregation: 'count' }], [{ aggregation: 'max', field: 'Price' }]]) };
  if (rnd() < 0.3) config.filter = randomTree(1);
  const r = pivot.summaryReport(rows, config, FIELDS, evalCtx);
  const labels = Object.keys(r.groups.length ? r.groups[0].measures : r.grandTotal);
  add({ op: 'report', rows, config: wire(config), fields: FIELDS, ctx: CTX, e: `${labels.map((l) => `${hex(l)},`).join('')}|${r.groups.map((g) => `${hex(g.key)}:${g.count}:${labels.map((l) => `${renderCell(g.measures[l])},`).join('')};`).join('')}|${labels.map((l) => `${renderCell(r.grandTotal[l])},`).join('')}|${r.total}` });
}
// server planning and shaping
const renderPlan = (p) => {
  if (!p.ok) return `no:${p.reason}`;
  const a = p.args;
  return `ok:${hex(a.p_table_id)}:${a.p_x_field === null ? '-' : hex(a.p_x_field)}:${a.p_x_bucket === null ? '-' : a.p_x_bucket}:${a.p_aggregation}:${a.p_measure_field === null ? '-' : hex(a.p_measure_field)}:${a.p_split_field === null ? '-' : hex(a.p_split_field)}:${a.p_limit}:${a.p_conditions.map((c) => `${hex(c.field)}:${c.op}:${c.type ?? ""}${'bucket' in c ? `:bucket=${c.bucket === null || c.bucket === undefined ? '-' : c.bucket}:${c.value === undefined || c.value === null ? '_' : renderValue(c.value)}:${(c.values || []).map((v) => `${renderValue(v)},`).join('')}` : `${'value' in c ? `:${hex(c.value)}` : ''}`};`).join('')}`;
};
const serverFilter = () => {
  const c = () => {
    const kind = int(8);
    if (kind === 0) return { field: 'Qty', op: pick(['=', '<', 'isEmpty', 'bogus']), type: 'number', value: pick([5, '', null, 'x']) };
    if (kind === 1) return { field: 'Status', op: pick(['is', 'isNot', 'isAnyOf']), type: 'select', value: pick(['open', null]) };
    if (kind === 2) return { field: 'Name', op: pick(['contains', 'startsWith', 'isEmpty']), value: pick(['a', '']) };
    if (kind === 3) return { field: 'Due', op: 'before', type: 'date', value: '2026-01-01' };
    if (kind === 4) return { field: 'Due', op: pick(['inBucket', 'notInBuckets']), bucket: pick(['month', { size: 5 }]), value: '2026-02', values: ['2026-01'] };
    if (kind === 5) return { expr: '{Qty} > 1' };
    if (kind === 6) return { field: 'Owner', op: 'is', type: 'user', value: 'u1' };
    return { field: 'Name', op: 'is', type: 'weird', value: 'a' };
  };
  const r = rnd();
  if (r < 0.15) return undefined;
  if (r < 0.5) return c();
  if (r < 0.85) return { operator: 'and', children: Array.from({ length: 1 + int(3) }, c) };
  return { operator: pick(['or', 'and']), children: [c(), { operator: 'and', children: [c()] }] };
};
for (let k = 0; k < 160; k += 1) {
  const config = { tableId: pick(['t1', 't1', '']), xField: pick(['Status', undefined]), series: pick([undefined, [{ aggregation: pick(AGGS), field: pick(['Qty', undefined]) }], [{ aggregation: 'sum', field: 'Qty' }, { aggregation: 'count' }]]), aggregation: pick([undefined, 'sum', 'median']) };
  if (rnd() < 0.3) config.field = 'Price';
  if (rnd() < 0.2) config.measureField = 'Score';
  if (rnd() < 0.4) config.xBucket = pick(['month', { size: 5 }, { size: 'x' }, {}, '']);
  if (rnd() < 0.3) config.splitField = 'Owner';
  if (rnd() < 0.3) config.topN = 3;
  if (rnd() < 0.2) config.comparison = { filter: { field: 'Qty', op: '=', type: 'number', value: 1 } };
  const f = serverFilter();
  if (f !== undefined) config.filter = f;
  const kind = pick(['chart', 'kpi']);
  add({ op: 'plan', config: wire(config), kind, e: renderPlan(server.planAggregate(config, { kind })) });
}
for (let k = 0; k < 60; k += 1) {
  const aggregation = pick(['count', 'sum', 'avg', 'min', 'max']);
  const labels = pick([['a', 'b', 'c'], ['1', '2', '10'], ['2026-01', '2026-02'], ['x']]);
  const groups = [];
  for (const l of labels.concat(rnd() < 0.4 ? [null] : [])) for (const s of (rnd() < 0.4 ? ['u1', 'u2', null] : [null])) if (rnd() < 0.85) groups.push({ bucket: l, split: s, measure: rnd() < 0.1 ? null : int(50) + (rnd() < 0.3 ? 0.5 : 0), row_count: 1 + int(5) });
  const config = { chartType: 'bar', xField: 'X', aggregation, series: [{ aggregation, field: 'Qty', ...(rnd() < 0.3 ? { label: 'S' } : {}) }] };
  if (rnd() < 0.4) config.splitField = 'Owner';
  if (rnd() < 0.4 && ['count', 'sum'].includes(aggregation)) config.topN = 1 + int(2);
  const c = server.chartDataFromGroups(groups, config);
  add({ op: 'gchart', groups, config, e: `${renderChart(c)}|${c.total}` });
  const kcfg = { aggregation, series: [{ aggregation, field: 'Qty' }], thresholds: rnd() < 0.5 ? [{ value: 10, label: 'hi', color: '#f00' }, { value: 0, label: 'lo' }] : undefined };
  const kg = groups.slice(0, int(3));
  const kr = server.kpiFromGroups(kg, kcfg);
  add({ op: 'gkpi', groups: kg, config: wire(kcfg), e: `${renderCell(kr.value)}|${kr.rowCount}${kr.threshold ? `|${hex(kr.threshold.label)}:${kr.threshold.color}:${kr.threshold.band}` : ''}` });
}

const chunks = [];
const size = 12;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}(), &registry) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'query_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_view/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_view`);
