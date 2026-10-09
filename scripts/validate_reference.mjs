// Reference vectors for `e.data.validate` (L031): build table definitions and records over every field type and
// rule shape, run appdor's own validation engine (src/validation) over them, and write the link fixture
// tests/selfhost/fixtures/link/data_validate. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const index = await load('src/validation/index.js');
const conditional = await load('src/validation/conditional.js');
const bulk = await load('src/validation/bulk.js');
const { isError } = await load('src/formula/index.js');

const hex = (s) => (s === '' ? '_' : Buffer.from(String(s), 'utf8').toString('hex'));
const NOW = new Date('2026-06-15T09:30:00.000Z');
const flag = (b) => (b ? '1' : '0');

function renderValue(v) {
  if (isError(v)) return 'E';
  if (v === null || v === undefined) return '_';
  if (typeof v === 'number') return `N${String(v)}`;
  if (typeof v === 'string') return `T${hex(v)}`;
  if (typeof v === 'boolean') return v ? 'B1' : 'B0';
  if (v instanceof Date) return `D${v.toISOString()}`;
  if (Array.isArray(v)) return `[${v.map(renderValue).join(',')}]`;
  return 'O';
}
const renderViolation = (v) => `${v.field === null || v.field === undefined ? '-' : hex(v.field)}:${v.code}:${v.severity}:${v.ruleId === undefined || v.ruleId === null ? '-' : hex(String(v.ruleId))}:${hex(v.message)}`;
const renderViolations = (vs) => vs.map(renderViolation).join(';');

let seed = 0x7a11d;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

// field type -> sample values: [valid..., invalid...]
const SAMPLES = {
  text: [['hello', 'Hello World', 'a'], ['', ' ']],
  email: [['ada@example.com', 'a@b.co'], ['nope', 'a@b', '@x.y', 'a b@c.d']],
  url: [['https://example.com/a', 'example.org', 'http://a.b:8080/x?y'], ['not a url', 'http://', 'a b.c']],
  phone: [['+359 88 123 4567', '(212) 555-0100', '+14155550100'], ['abc', '12', '+0123']],
  ip: [['10.0.0.1', '255.255.255.255'], ['256.1.1.1', '1.2.3', '01.2.3.4']],
  cidr: [['10.0.0.0/8', 'fe80::/10', '192.168.1.0/24'], ['10.0.0.0/129', '10.0.0.0', 'zz/8']],
  number: [[1, 0, '5', 2.5, '-3', true], ['abc', {}, [1, 2]]],
  currency: [[10, '12.50'], ['x']],
  percent: [[0.5, '50'], ['half']],
  date: [['2026-01-15', '2026-01-15T10:00:00Z', 1700000000000], ['not a date', 'zzz']],
  uuid: [['123e4567-e89b-42d3-a456-426614174000'], ['123e4567', 'zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz']],
  base64: [['SGVsbG8=', 'YQ==', ''], ['SGVsbG8===', 'a b']],
  iban: [['GB82 WEST 1234 5698 7654 32', 'DE89370400440532013000'], ['GB82 WEST 1234 5698 7654 33', 'XX']],
  'credit-card': [['4539 1488 0343 6467'], ['4539 1488 0343 6468', '0']],
  'iso-3166-2': [['BG', 'us', ' DE '], ['ZZ', 'UK', 'XX']],
  'iso-3166-3': [['BGR', 'usa'], ['ZZZ', 'GBX']],
  'iso-4217': [['EUR', 'usd'], ['EURO', '12']],
  tzdb: [['Europe/Sofia', 'America/Argentina/Buenos_Aires'], ['europe/sofia', 'Sofia']],
  rating: [[0, 3, 2.5, '4'], [-1, 'five']],
  location: [['42.69, 23.32', 'Sofia, Bulgaria', '0;0'], ['91, 0', '0, 181']],
  image: [['https://x.test/a.png', '/img/a.png', 'data:image/png;base64,AAAA'], ['javascript:alert(1)', 'not a url at all', 'http://a.invalid/x']],
  select: [['open', 'closed', 'other'], ['nonsense']],
  multiselect: [[['open'], ['open', 'closed']], [['bad'], ['open', 'bad']]],
  checkbox: [[true, false], []],
  vin: [['1HGCM82633A004352'], ['1HGCM82633A004353']],
  nace: [['F.41.20', '62.01', 'A'], ['04', 'ZZ']],
};
const TYPES = Object.keys(SAMPLES);
const OPTIONS = ['open', 'closed', 'other'];
const EXPRS = ['{Qty} > 0', '{Name} = "x"', 'LEN({Name}) > 2', '{Flag}', 'ISBLANK({Email})', '1 / 0', '{Qty} * 2 > 5', 'NOPE(1)', 'IF({Qty} > 1, true, false)', '{Missing}', '"0"', '[]', '[1]', '0', '1'];
const MESSAGES = ['Bad {Field}', 'Value {value} is not a {type}', '{Field} must be at least {min}', 'No {Missing} here', '{Field}: {Name}', 'x'];

function fieldDef(i) {
  const type = pick(TYPES);
  const f = { name: pick(['Name', 'Email', 'Qty', 'Flag', 'Status', 'Notes', 'Code', 'Phone', 'Date', 'Url']) + (i === 0 ? '' : String(i)), type };
  if (rnd() < 0.5) f.label = pick(['Label A', 'Customer email', 'Qty']);
  if (rnd() < 0.3) f.required = true;
  if (rnd() < 0.25) f.showIf = pick(EXPRS);
  if (rnd() < 0.15) f.editableIf = pick(EXPRS);
  if (rnd() < 0.2) f.requireIf = pick(EXPRS);
  if (['number', 'currency', 'percent', 'rating', 'date'].includes(type) && rnd() < 0.6) { if (rnd() < 0.7) f.min = pick(type === 'date' ? ['2026-01-01', 0] : [0, 1, '2', 'x', -5]); if (rnd() < 0.7) f.max = pick(type === 'date' ? ['2026-12-31'] : [10, 100, '50']); }
  if (['text', 'email', 'url', 'select'].includes(type) && rnd() < 0.5) { if (rnd() < 0.6) f.minLength = pick([1, 3, 5]); if (rnd() < 0.6) f.maxLength = pick([3, 10, 20]); }
  if (type === 'text' && rnd() < 0.3) f.pattern = pick(['^[a-z]+$', '\\d', 'abc', '(', '^\\w+@\\w+$']);
  if (type === 'select' || type === 'multiselect') { f.options = OPTIONS.slice(); if (rnd() < 0.2) f.allowUserInput = true; if (type === 'multiselect' && rnd() < 0.5) f.limit = pick([1, 2]); }
  if (rnd() < 0.2) f.validIf = rnd() < 0.5 ? pick(EXPRS) : [pick(EXPRS), pick(EXPRS)];
  if (rnd() < 0.25) f.unique = rnd() < 0.5 ? true : { caseSensitive: rnd() < 0.5 };
  if (rnd() < 0.3) f.messages = Object.fromEntries(['required', 'format', 'min', 'max', 'minLength', 'maxLength', 'pattern', 'membership', 'validIf', 'unique'].filter(() => rnd() < 0.4).map((k) => [k, pick(MESSAGES)]));
  if (rnd() < 0.2) f.severity = pick(['warning', 'error', 'info']);
  if (rnd() < 0.15) f.severities = { required: pick(['warning', 'error']), format: 'warning', min: 'warning' };
  if (rnd() < 0.05) f.computed = true;
  return f;
}

function valueFor(f, mode) {
  const samples = SAMPLES[f.type] || SAMPLES.text;
  if (mode === 0) return undefined;
  if (mode === 1) return pick(['', null, []]);
  if (mode <= 6) return pick(samples[0]);
  return samples[1].length ? pick(samples[1]) : pick(samples[0]);
}

function makeTable() {
  const n = 1 + int(5);
  const fields = Array.from({ length: n }, (_, i) => fieldDef(i));
  const t = { fields };
  if (rnd() < 0.4) t.recordRules = Array.from({ length: 1 + int(2) }, (_, i) => ({ id: pick(['r1', 'r2', undefined]), expression: pick(EXPRS), message: pick(['', 'Rule failed {Name}', 'No']), severity: pick([undefined, 'warning', 'error']), field: pick([undefined, 'Name', '']), active: pick([undefined, true, false]) }));
  return t;
}

function makeRecord(table) {
  const r = {};
  for (const f of table.fields) {
    const v = valueFor(f, int(10));
    if (v !== undefined) r[f.name] = v;
  }
  if (rnd() < 0.5) r.Qty = pick([0, 1, 2, 5, '3']);
  if (rnd() < 0.4) r.Name = pick(['x', 'xyz', '']);
  if (rnd() < 0.3) r.Flag = pick([true, false]);
  if (rnd() < 0.2) r.Email = pick(['ada@example.com', '']);
  return r;
}

const cases = [];
const add = (o) => cases.push(JSON.stringify(o));
const jsonSafe = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));

// validateRecord
for (let k = 0; k < 520; k += 1) {
  const table = makeTable();
  const record = makeRecord(table);
  const ctx = { now: NOW };
  const wire = {};
  if (rnd() < 0.4) {
    const existing = Array.from({ length: 1 + int(3) }, () => makeRecord(table));
    if (rnd() < 0.4) existing.push({ ...record, deleted_at: pick(['2026-01-01', '', null]), is_deleted: pick([true, false, undefined]) });
    if (rnd() < 0.3) existing.push({ ...record });
    ctx.existingRecords = existing;
    wire.existing = existing;
  }
  if (rnd() < 0.2) { ctx.isNew = true; wire.isNew = true; }
  if (rnd() < 0.2) { ctx.locale = pick(['bg', 'fr']); wire.locale = ctx.locale; }
  const r = index.validateRecord(JSON.parse(JSON.stringify(table)), record, ctx);
  add({ op: 'validate', table: jsonSafe(table), record, ctx: wire, e: `${flag(r.valid)}|${renderViolations(r.violations)}` });
}
// a record that is itself in the stored rows (named by index)
for (let k = 0; k < 20; k += 1) {
  const table = { fields: [{ name: 'Name', type: 'text', unique: true }, { name: 'Email', type: 'email', unique: { caseSensitive: true } }] };
  const row = { Name: pick(['A', 'a', 'B']), Email: pick(['x@y.zz', 'X@y.zz']) };
  const existing = [{ Name: 'a', Email: 'X@y.zz' }, row, { Name: 'B', Email: 'x@y.zz' }];
  const r = index.validateRecord(table, row, { existingRecords: existing });
  add({ op: 'validate', table, record: row, ctx: { existing }, self: 1, e: `${flag(r.valid)}|${renderViolations(r.violations)}` });
}
// behavior
for (let k = 0; k < 120; k += 1) {
  const f = fieldDef(k);
  const record = { Qty: pick([0, 1, 5]), Name: pick(['x', 'xyz', '']), Flag: pick([true, false]), Email: pick(['a@b.cc', '']) };
  const b = index.fieldBehavior(f, record, { now: NOW });
  add({ op: 'behavior', field: f, record, e: `${flag(b.visible)}${flag(b.editable)}${flag(b.required)}` });
}
// import and backfill
for (let k = 0; k < 90; k += 1) {
  const table = { fields: [
    { name: 'Name', type: 'text', required: true, unique: pick([true, { caseSensitive: true }]) },
    { name: 'Email', type: 'email', unique: true },
    { name: 'Qty', type: 'number', min: 0, max: 10 },
  ] };
  const mk = () => ({ Name: pick(['ann', 'Ann', 'bob', '', 'cy']), Email: pick(['a@b.cc', 'A@b.cc', 'nope', '', 'c@d.ee']), Qty: pick([1, 5, 11, -1, 'x', 2]) });
  const rows = Array.from({ length: 2 + int(6) }, mk);
  const existing = Array.from({ length: int(3) }, mk);
  if (rnd() < 0.3) existing.push({ ...mk(), is_deleted: true });
  const policy = pick(['reject', 'skip', 'flag', undefined, 'bogus']);
  const r = bulk.validateImport(table, rows, { policy, existingRecords: existing, now: NOW });
  const idx = (list) => list.map((x) => rows.indexOf(x.row === undefined ? x : x.row)).join(',');
  const imported = r.policy === 'skip' ? r.imported : r.imported;
  const importedIdx = imported.map((row) => rows.indexOf(row)).join(',');
  const rejectedIdx = r.rejected.map((x) => x.index).join(',');
  const flaggedIdx = r.flagged.map((x) => x.index).join(',');
  const summary = `${r.summary.total},${r.summary.valid},${r.summary.invalid}${Object.entries(r.summary.byCode).map(([c, n]) => `,${c}=${n}`).join('')}`;
  add({ op: 'import', table, rows, policy: policy ?? null, ctx: { existing }, e: `${r.policy}|${flag(r.valid)}|${importedIdx}|${rejectedIdx}|${flaggedIdx}|${r.rows.map((x) => `${flag(x.valid)}${renderViolations(x.violations)}/`).join('')}|${summary}` });
  void idx;
}
for (let k = 0; k < 40; k += 1) {
  const table = { fields: [{ name: 'Name', label: 'Name', type: 'text' }, { name: 'Qty', type: 'number' }, { name: 'Status', type: 'select', options: OPTIONS }] };
  const records = Array.from({ length: 2 + int(5) }, () => ({ Name: pick(['ann', '', 'bob', null]), Qty: pick([1, 5, 50, -2, '']), Status: pick(['open', 'weird', '', 'closed']) }));
  if (rnd() < 0.3) records.push({ Name: 'gone', Qty: 1, deleted_at: '2026-01-01' });
  const rule = pick([{ field: 'Name', required: true }, { field: 'Qty', max: 10 }, { field: 'Qty', min: 0, max: 10, message: 'ignored', severity: 'warning' }, { field: 'Status' , unique: true }, { field: 'Status', options: OPTIONS }, { field: 'Name', minLength: 3 }, { field: 'Missing', required: true },
    { expression: '{Qty} > 0', id: 'q' }, { expression: '{Qty} > 0' }, { field: 'Name', expression: 'LEN({Name}) > 0', message: 'm' }]);
  const sample = pick([undefined, 1, 3]);
  const r = bulk.backfillCheck(table, records, rule, { sampleSize: sample, now: NOW });
  add({ op: 'backfill', table, records, rule: jsonSafe(rule), sample: sample ?? null, e: `${r.checked}|${r.violating}|${r.violations.map((v) => `${v.index}=${renderViolation(v)};`).join('')}|${r.sample.length}` });
}
// duplicates
for (let k = 0; k < 40; k += 1) {
  const mk = () => ({ Name: pick(['Jon Smith', 'jon  smith', 'Jane', '', null, ' JON SMITH ']), City: pick(['Sofia', 'sofia', 'Plovdiv', '']) });
  const existing = Array.from({ length: 2 + int(5) }, mk);
  if (rnd() < 0.3) existing.push({ ...mk(), is_deleted: true });
  const record = mk();
  const config = { fields: pick([['Name'], ['Name', 'City'], []]), threshold: pick([undefined, 0.5, 1, 0]) };
  const list = bulk.findDuplicates(record, existing, config);
  add({ op: 'dups', record, existing, config: jsonSafe(config), e: list.map((m) => `${existing.indexOf(m.record)}:${m.score}:${m.matched}:${m.compared};`).join('') });
}
// suggestions
for (let k = 0; k < 40; k += 1) {
  const f = { name: 'S', type: 'text', suggestedValues: pick(['["a", "b", "a", "", null, 3, 3]', '{Qty}', '1 / 0', '[1, 2, 3, 4]', '"x"', 'NOPE(1)', 'BLANK()', '[{Qty}, {Name}]']), suggestionLimit: pick([undefined, 2, 0, -1, 1.7]) };
  const record = { Qty: pick([1, 2]), Name: pick(['n', '']) };
  const limit = pick([undefined, undefined, 1, 3]);
  const s = conditional.suggestedValues(f, record, { now: NOW, ...(limit === undefined ? {} : { limit }) });
  add({ op: 'suggest', field: jsonSafe(f), record, limit: limit ?? null, e: `${flag(s.constrained)}${flag(!!s.error)}|${s.values.map(renderValue).join(',')}` });
}
// containers and forms
for (let k = 0; k < 40; k += 1) {
  const containers = [
    { id: 'p1', kind: 'page', showIf: pick([undefined, '{Qty} > 0', '{Flag}']), fields: ['A'], children: [{ id: 's1', showIf: pick([undefined, '{Name} = "x"', '1 / 0']), fields: ['B', 'C'], children: [{ id: 'g1', kind: 'group', showIf: pick([undefined, '{Qty} > 2']), fields: ['D'] }] }] },
    { id: 'p2', fields: ['E'], showIf: pick([undefined, '{Flag}']) },
  ];
  const record = { Qty: pick([0, 1, 5]), Name: pick(['x', '']), Flag: pick([true, false]) };
  const st = conditional.evaluateContainers(containers, record, { now: NOW });
  add({ op: 'containers', containers, record, e: Object.entries(st).map(([id, s]) => `${id}:${flag(s.visible)}${flag(s.selfVisible)}${flag(s.hiddenByAncestor)}:${s.kind};`).join('') });
  const fields = ['A', 'B', 'C', 'D', 'E', 'F'].map((name) => ({ name, type: 'text', required: pick([true, false]), showIf: pick([undefined, undefined, '{Qty} > 0']), requireIf: pick([undefined, '{Flag}']), editableIf: pick([undefined, '{Name} = "x"']) }));
  const fb = conditional.evaluateFormBehavior({ containers, fields }, record, { now: NOW });
  add({ op: 'form', form: { containers, fields }, record, e: Object.entries(fb.fields).map(([name, b]) => `${name}:${flag(b.visible)}${flag(b.editable)}${flag(b.required)}:${b.container ?? '-'};`).join('') });
}
// initial values, auto-set, computed writes
for (let k = 0; k < 20; k += 1) {
  const table = { fields: [
    { name: 'Created', type: 'date', initialValue: pick(['NOW()', '1 / 0', '"seed"']), defaultValue: 'ignored' },
    { name: 'Status', type: 'select', defaultValue: pick(['open', 0, false, null]) },
    { name: 'Total', type: 'number', computed: true },
    { name: 'Auto', type: 'autonumber' },
    { name: 'Plain', type: 'text' },
  ] };
  add({ op: 'initial', table, e: Object.entries(index.computeInitialValues(table, { now: NOW })).map(([n, v]) => `${n}=${renderValue(v)};`).join('') });
  add({ op: 'computed', table, keys: ['Total', 'Plain', 'Auto', 'Missing', 'Status'], e: renderViolations(index.computedWriteViolations(table, ['Total', 'Plain', 'Auto', 'Missing', 'Status'])) });
  const t2 = { fields: [
    { name: 'Slug', type: 'text', autoSet: { when: pick([undefined, '{Name} != ""']), value: 'LOWER({Name})', replace: pick([true, false, undefined]) } },
    { name: 'Stamp', type: 'text', autoSet: { value: pick(['{Slug} & "!"', '1 / 0', '"s"']) } },
    { name: 'Name', type: 'text' },
  ] };
  const rec = JSON.parse(JSON.stringify({ Name: pick(['Ada', '']), Slug: pick(['', 'old', undefined]) }));
  const applied = index.applyAutoSet(t2, rec, { now: NOW });
  add({ op: 'autoset', table: t2, record: rec, e: Object.entries(applied).map(([n, v]) => `${n}=${renderValue(v)};`).join('') });
}

const chunks = [];
const size = 20;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}(), &registry, now_ms) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'validate_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/data_validate/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> data_validate`);
