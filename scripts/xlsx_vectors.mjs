// Vectors for `e.fmt.xlsx` and `x.migrate.typemaps` (L044): Appdor's own src/io/xlsx.js and importer maps over random
// sheets, workbooks, cell references, formula cells, sheet lists and type names, written as the link fixture
// tests/selfhost/fixtures/link/fmt_xlsx. Usage: node scripts/xlsx_vectors.mjs   (APPDOR_DIR defaults to D:/repos/appdor)
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (f) => import(pathToFileURL(resolve(appdor, f)).href);
const x = await load('src/io/xlsx.js');
const monday = await load('src/importers/monday.js');
const airtable = await load('src/importers/airtable.js');
const quickbase = await load('src/importers/quickbase.js');

let seed = 0x91c3;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

const WORDS = ['Name', 'Amount', 'Status', 'Owner', 'Deal', 'Close date', 'Qty', 'Notes', 'id', 'Stage', 'Region', '2024', 'Q3 pipeline - exported'];
const STRINGS = ['', ' ', '  padded  ', '\u00a0nbsp\u00a0', '\t tab', '0', 'true', 'false', '12.50', 'x', 'Zoë', '日本', '=SUM(A1:A2)', '\u2003em\u2003'];

function cellValue() {
  const r = int(20);
  if (r < 3) return null;
  if (r < 7) return pick(WORDS);
  if (r < 9) return pick(STRINGS);
  if (r < 12) return int(2000) - 100;
  if (r < 14) return [0, -0, 0.1, 1e21, 1e-7, 123456789012345680000, 1.5e300, 2.5, -3.75, 1 / 3][int(10)];
  if (r < 16) return chance(0.5);
  if (r < 17) return { x: pick(['NaN', 'Infinity', '-Infinity']) };
  return { d: [1970 + int(131), 1 + int(12), 1 + int(28), chance(0.5) ? 0 : int(24), chance(0.5) ? 0 : int(60), chance(0.5) ? 0 : int(60)] };
}

function realize(v) {
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    if ('x' in v) return Number(v.x);
    const [y, mo, d, h, mi, s] = v.d;
    const dt = new Date(y, mo - 1, d, h, mi, s);
    return dt;
  }
  return v;
}

// A cell as the case carries it: dates as the local components the JS Date reports.
function encode(v) {
  if (v && typeof v === 'object' && !Array.isArray(v) && 'd' in v) {
    const dt = realize(v);
    return { d: [dt.getFullYear(), dt.getMonth() + 1, dt.getDate(), dt.getHours(), dt.getMinutes(), dt.getSeconds()] };
  }
  if (typeof v === 'number' && Object.is(v, -0)) return 0;
  return v;
}

function sheet() {
  const rows = 1 + int(14), cols = 1 + int(7);
  const aoa = [];
  if (chance(0.3)) { const b = new Array(1 + int(2)).fill(null); b[0] = 'Q3 pipeline - exported 2026-01-04'; aoa.push(b); if (chance(0.5)) aoa.push([]); }
  const header = Array.from({ length: cols }, () => (chance(0.15) ? null : pick(WORDS)));
  if (chance(0.7)) aoa.push(header);
  for (let r = 0; r < rows; r++) {
    const len = chance(0.15) ? cols + 1 + int(3) : chance(0.2) ? int(cols + 1) : cols;
    const row = Array.from({ length: len }, () => cellValue());
    if (chance(0.1)) row.push('', '');
    aoa.push(chance(0.03) ? null : row);
  }
  return aoa.map((row) => (row === null ? null : row.map(encode)));
}

const run = (aoa) => aoa.map((row) => (row === null ? null : row.map(realize)));

function expectSheet(aoa, pin) {
  const t = x.sheetToTable(run(aoa), pin === undefined ? {} : { headerRow: pin });
  return {
    headers: t.headers,
    rows: t.rows.map((rec) => t.headers.map((h) => rec[h])),
    headerRow: String(t.headerRow),
    skippedRows: String(t.skippedRows),
    renamed: t.renamedHeaders.map((r) => ({ index: String(r.index), from: r.from, to: r.to })),
  };
}

const cases = [];
const add = (c) => cases.push(c);

for (let i = 0; i < 260; i++) {
  const aoa = sheet();
  const pin = chance(0.2) ? int(aoa.length + 3) - 1 : undefined;
  const c = { op: 'sheet', aoa };
  if (pin !== undefined) c.pin = pin;
  c.e = expectSheet(aoa, pin);
  add(c);
}
add({ op: 'sheet', aoa: [], e: expectSheet([], undefined) });
add({ op: 'sheet', aoa: [[null, null], [null]], e: expectSheet([[null, null], [null]], undefined) });
add({ op: 'sheet', aoa: [['A', 'A', 'A 2', '', 'A']], e: expectSheet([['A', 'A', 'A 2', '', 'A']], undefined) });

for (let i = 0; i < 60; i++) {
  const aoa = sheet();
  add({ op: 'detect', aoa, e: String(x.detectHeaderRow(run(aoa))) });
}

for (let i = 0; i < 50; i++) {
  const n = int(4);
  const sheets = [];
  for (let k = 0; k < n; k++) sheets.push({ name: chance(0.2) ? '' : chance(0.1) ? '  ' : pick(['Deals', 'People', ' Sheet2 ', 'Q3', 'Deals']), aoa: sheet() });
  const pins = {};
  if (chance(0.5) && sheets.length) { const nm = String(sheets[int(sheets.length)].name).trim(); if (nm) pins[nm] = int(4); }
  const out = x.workbookToTables(sheets.map((s) => ({ name: s.name, aoa: run(s.aoa) })), { headerRows: pins });
  add({
    op: 'workbook', sheets, pins: Object.entries(pins).map(([name, row]) => ({ name, row })),
    e: out.map((t) => ({ name: t.name, headers: t.headers, rows: t.rows.map((rec) => t.headers.map((h) => rec[h])), headerRow: String(t.headerRow), skippedRows: String(t.skippedRows), renamed: t.renamedHeaders.map((r) => ({ index: String(r.index), from: r.from, to: r.to })) })),
  });
}

const REFS = ['A1', 'b2', 'AB12', '$A$1', '$AB12', 'C$7', ' D4 ', 'A0', '0', '', 'A', '12', 'AA', 'ZZ99', 'a1b', 'A-1', '1A', 'XFD1048576', 'A 1', '\u00a0B3', 'aaa00012', '$$A1', 'A1$', 'É5'];
for (let i = 0; i < 90; i++) {
  const ref = i < REFS.length ? REFS[i] : pick(['', '$']) + String.fromCharCode(65 + int(26)) + (chance(0.3) ? String.fromCharCode(97 + int(26)) : '') + pick(['', '$']) + (1 + int(2000));
  const r = x.parseCellRef(ref);
  add({ op: 'ref', ref, e: r === null ? null : { column: String(r.column), row: String(r.row) } });
}

for (let i = 0; i < 40; i++) {
  const cells = [];
  const ws = {};
  const n = int(8);
  for (let k = 0; k < n; k++) {
    const ref = chance(0.15) ? pick(['!ref', '!merges', '!cols']) : String.fromCharCode(65 + int(6)) + (1 + int(30)) + (chance(0.05) ? 'x' : '');
    if (ref in ws) continue;
    const r = int(5);
    const cell = r === 0 ? { v: 1 } : r === 1 ? { f: '' } : r === 2 ? { f: ' SUM(A1:A3) ' } : r === 3 ? { f: 5 } : { f: pick(['A1+B1', "Sheet2!A1*2", "'My Sheet'!B2"]), v: 3 };
    ws[ref] = cell;
    cells.push({ ref, has: typeof cell.f === 'string', f: typeof cell.f === 'string' ? cell.f : '' });
  }
  const out = x.sheetFormulas(ws);
  add({ op: 'formulas', cells, e: out.map((o) => ({ ref: o.ref, column: String(o.column), row: String(o.row), formula: o.formula })) });
}

for (let i = 0; i < 50; i++) {
  const names = Array.from({ length: int(5) }, () => pick(['Deals', 'People', '', 'Q3', 'Sheet 1', 'Deals']));
  const requested = chance(0.2) ? '' : chance(0.6) ? pick(['Deals', 'People', 'Q3', 'nope']) : pick(names.length ? names : ['x']);
  const d = x.describeSheets(names, requested || undefined);
  add({ op: 'describe', names, requested, e: { names: d.names, chosen: d.chosen, ignored: d.ignored, needsChoice: d.needsChoice } });
}

const maps = [
  ['monday_type', monday.MONDAY_TYPE_MAP, false],
  ['airtable_type', airtable.AIRTABLE_TYPE_MAP, false],
  ['quickbase_type', quickbase.QUICKBASE_TYPE_MAP, false],
  ['airtable_view_type', airtable.AIRTABLE_VIEW_TYPE_MAP, true],
  ['monday_view_type', monday.MONDAY_VIEW_TYPE_MAP, true],
];
for (const [name, map, view] of maps) {
  const keys = [...Object.keys(map), '', 'unknown', 'Text', 'text ', 'singleLineText', 'grid', 'table', 'dblink'];
  for (const k of keys) {
    const v = map[k];
    add({ op: 'map', map: name, key: k, e: view ? (v || 'grid') : v === undefined ? null : v });
  }
}

const lines = cases.map((c) => JSON.stringify(c));
const chunks = [];
const size = 12;
for (let i = 0; i < lines.length; i += size) {
  chunks.push(`"${lines.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'xlsx_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/fmt_xlsx/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> fmt_xlsx`);
