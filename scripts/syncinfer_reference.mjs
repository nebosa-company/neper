// Reference vectors for `e.algo.syncinfer` (L037): run appdor's own src/io/infer.js (`detectDateOrder`,
// `detectDecimalSeparator`, `inferColumnType`), `inferExternalSchema` of src/connectors/index.js and `proposeMapping` of
// src/sync/synced-table.js on random columns and samples -- booleans, integers and identifiers, numbers in both decimal
// conventions with grouping and units, currencies and percents, ISO, slash and dot dates, datetimes with their
// suffixes, emails, URLs, phone numbers, long text, repeated values for the select rule, nested values -- and write the
// link fixture tests/selfhost/fixtures/link/algo_syncinfer. APPDOR_DIR defaults to D:/repos/appdor.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appdor, canon, clone, emit, rng } from './ref_common.mjs';

const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const infer = await load('src/io/infer.js');
const conn = await load('src/connectors/index.js');
const st = await load('src/sync/synced-table.js');
const { int, pick, chance } = rng(0x51f3);

const BOOLS = ['true', 'false', 'yes', 'No', 'Y', 'n', '1', '0', 'да', 'Не', 'TRUE', 'ДА', 'нЕ', 'maybe'];
const INTS = ['1', '42', '007', '01067', '12345678901234567890', '9007199254740991', '9007199254740992', '-5', '0', '00', '100', '7', '123456', '-0', '2', '3', '0888123456'];
const NUMBERS = ['1.5', '19.99', '0.001', '1,234.56', '1.234,56', '-3.14', '.5', ',5', '1,234', '1.234', '1 234,56', '12 345.67', '1.2.3', '1,2,3.4', '1.234.567', '1,234,567',
  '1234,567', '12,3456', '0,500', '19,99', '1,50', '-1.234,5', '1,234,5', '12.345', '123,456', '1\u00a0234,56', '99.9', '0.5', '5,', '1..2', '--5', '1e5', '12abc', '٣'];
const MONEY = ['$5', '€1.234,56', '£3', '¥100', '1,50 лв.', '12 BGN', '5 usd', '7.5 EUR', '$ 9', '12 лв', '13 ЛВ', '5 Eur', '€ 19,99', '$1,234.56', '12 лв.', 'BGN', '5 USD.', '1,5лв'];
const PERCENT = ['50%', '12,5 %', '3.14%', '100 %', '%', '5%%', '0,5%', '12.5 %', '-3%', '1.234,5%'];
const ISO = ['2024-03-15', '2024-3-5', '2024-13-45', '1999-12-31', '0001-01-01', '2024-02-30', '2024-1-1'];
const SLASH = ['25/12/2024', '05/03/2024', '12/25/2024', '5.3.24', '31.12.2024', '1/1/1', '31/02/2024', '00/10/2024', '13/13/2013', '1/2/0050', '25.12.50', '1/1/2024', '12/12/12',
  '30/04/2024', '29/02/2023', '29/02/2024', '3/15/24', '15.3.2024', '01.02.2003', '10/10/10', '1/13/2024', '0/5/2024', '5/0/2024', '1/1/999', '1/1/12345'];
const DATETIMES = ['2024-03-15 10:30', '2024-03-15T10:30:00', '2024-3-5 1:30', '2024-03-15 10:30:45.123', '2024-03-15T10:30Z', '2024-03-15 10:30 PM', '2024-03-15 25:00',
  '2024-02-30 10:30', '2024-03-15 10:30:45+02:00', '2024-03-15 10:30 foo', '2024-03-15 10:30:60', '2024-03-15T10:30:00.000Z', '2024-03-15 10:30 GMT', '2024-03-15 10:30 UTC', '2024-03-15 10:30 +0200',
  '2024-3-5T10:30', '2024-03-15 24:00', '2024-03-15 24:01', '2024-03-15 13:30 PM', '2024-03-15 12:30 AM', '2024-03-15 10:30 EST', '2024-03-15 10:30 (comment)', '2024-03-15 10:30:',
  '2024-03-15 10:3', '2024-03-15  10:30', '2024-03-15T 10:30', '2024-13-15 10:30', '2024-03-32 10:30', '2024-00-15 10:30', '2024-03-15 10:30Z', '2024-03-15 10:30 z', '2024-03-15T10:30+01',
  '2024-03-15T10:30+01:00', '2024-03-15T10:30:15.5', '2024-03-15T10:30:15,5', '2024-03-15 10:30:45 -08:00', '2024-03-15 10:30 pm', '2024-03-15 1:30 am', '2024-03-15 10:30:45 PST'];
const EMAILS = ['a@b.co', 'x.y@z.org', 'bad@', '@bad.com', 'a@b', 'a b@c.d', 'a@b.c.', 'a@.b', 'a@b..c', 'аа@бб.вв', 'u@h.io ', 'a@b@c.d', 'a@b.c d'];
const URLS = ['example.com', 'https://example.com/path', 'http://a.b:8080/x', 'HTTP://UP.CASE', 'a.b', 'www.x.y/z w', '1.234', '019.99', 'a_b.c-d.org', 'http://x', 'ftp://a.b', 'a.b:80',
  'a.b:', 'a.b/', 'https://a.b/c?d=e#f', 'a..b', '.a.b', 'a.b.', 'http://a.b.c:8x', 'a.b/ c', 'ex ample.com', 'пример.рф'];
const PHONES = ['+359888123456', '0888123456', '(02) 123-4567', '555-1234', '+1 (555) 123-4567', '12345', '1234567', '01067', '+0123456789', '+1', '1', '0123456', '012345', '+12345678901234567', '123456789012345', '1234567890123456'];
const TEXT = ['hello', 'Hello world', 'abc123', 'é', '日本語', 'x'.repeat(120), 'y'.repeat(101), '😀'.repeat(60), 'a'.repeat(100), 'line\nbreak', 'tab\there', ' padded ', '', '   ', 'N/A', 'n/a', 'ok'];
const SELECTS = ['red', 'green', 'blue', 'Open', 'Closed', 'Pending', 'A', 'B', 'C'];
const GROUPS = [BOOLS, INTS, NUMBERS, MONEY, PERCENT, ISO, SLASH, DATETIMES, EMAILS, URLS, PHONES, TEXT, SELECTS];

const genCell = (group) => {
  const r = chance(0.04) ? pick([null, '', '  ', undefined]) : pick(group);
  return r;
};
const genNumberCell = () => pick([1, 2.5, -3, 100, 0, 1e21, 1.5e-7, 0.1 + 0.2, 12345678901234567890, true, false, '12', '1,5', 19.99, 1234.5, 1.0, -0]);

function genColumn() {
  const kind = int(10);
  const n = 1 + int(chance(0.1) ? 30 : 9);
  let values;
  if (kind <= 5) {
    // A few values of one group, repeated: most of these are all valid for one type.
    const g = pick(GROUPS);
    const few = Array.from({ length: 1 + int(chance(0.7) ? 2 : 4) }, () => pick(g));
    values = Array.from({ length: n }, () => (chance(0.03) ? pick([null, '', '  ']) : pick(few)));
  } else if (kind === 6) {
    const gs = [pick(GROUPS), pick(GROUPS)];
    values = Array.from({ length: n }, () => genCell(pick(gs)));
  } else if (kind === 7) {
    values = Array.from({ length: n }, () => genNumberCell());
  } else if (kind === 8) {
    const few = Array.from({ length: 1 + int(4) }, () => pick(TEXT.concat(SELECTS)));
    values = Array.from({ length: 2 + int(26) }, () => pick(few));
  } else {
    values = Array.from({ length: n }, () => pick([genCell(pick(GROUPS)), genNumberCell()]));
  }
  return values;
}

const jsonable = (values) => values.map((v) => (v === undefined ? null : v)).map((v) => (typeof v === 'number' && !Number.isFinite(v) ? null : v));

function genOp() {
  const k = int(20);
  if (k < 11) {
    const values = jsonable(genColumn());
    const opts = chance(0.3) ? { ...(chance(0.5) ? { decimal: pick(['comma', 'dot', 'weird', null]) } : {}), ...(chance(0.5) ? { maxSelectOptions: pick([0, 1, 2, 3, 5, 100, -1, 2.5]) } : {}) } : {};
    return { op: 'column', values, opts };
  }
  if (k < 13) return { op: 'order', values: jsonable(genColumn()) };
  if (k < 15) return { op: 'decimal', values: jsonable(genColumn()) };
  const names = ['a', 'b', 'c', 'name', 'Дата', '2', '10', '1', 'z y', '', '01', '4294967295', '4294967294'];
  const cols = Array.from({ length: 1 + int(5) }, () => pick(names));
  const unique = [...new Set(cols)];
  const rows = Array.from({ length: int(chance(0.1) ? 0 : 7) }, () => {
    const row = {};
    const order = unique.slice().sort(() => rnd2() - 0.5);
    for (const c of order) if (chance(0.85)) row[c] = pick([...genColumn().slice(0, 1), genNumberCell()]);
    return row;
  });
  if (k < 17) return { op: 'schema', rows: rows.map((r) => jsonableRow(r)) };
  // proposeMapping: now and then a nested value or a null row.
  const sample = rows.map((r) => jsonableRow(r));
  if (sample.length && chance(0.35)) sample[int(sample.length)][pick(unique)] = pick([{ k: 1 }, [1, 2], {}, [], { a: [1] }]);
  if (sample.length && chance(0.08)) sample[int(sample.length)] = null;
  return { op: 'mapping', sample };
}
const rnd2 = () => int(1000) / 1000;
const jsonableRow = (r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v === undefined ? null : (typeof v === 'number' && !Number.isFinite(v) ? null : v)]));

function execute(op) {
  switch (op.op) {
    case 'column': return infer.inferColumnType(clone(op.values), clone(op.opts));
    case 'order': return infer.detectDateOrder(clone(op.values));
    case 'decimal': return infer.detectDecimalSeparator(clone(op.values));
    case 'schema': return conn.inferExternalSchema(clone(op.rows));
    case 'mapping': return st.proposeMapping({ connector: 'x', sample: clone(op.sample) });
    default: throw new Error(op.op);
  }
}

// A single date or datetime cell composed from parts, to hold the platform-parser port to node's.
const genDateCell = () => {
  const y = pick(['2024', '1999', '0001', '9999', '2000', '0000']);
  const m = pick(['03', '3', '12', '1', '00', '13', '02', '11']);
  const d = pick(['05', '5', '31', '30', '29', '00', '32', '1', '15']);
  if (chance(0.3)) {
    // slash and dot forms
    const a = pick(['1', '5', '12', '13', '31', '0', '00', '07', '25']);
    const b = pick(['1', '5', '12', '13', '31', '0', '00', '07', '32']);
    const c = pick(['24', '2024', '99', '50', '49', '00', '0000', '202', '12345']);
    return `${a}${pick(['/', '.'])}${b}${pick(['/', '.'])}${c}`;
  }
  const sep = pick([' ', 'T', 'T', ' ']);
  const h = pick(['10', '1', '0', '23', '24', '12', '9', '25', '13']);
  const mi = pick(['30', '00', '59', '60', '05', '3']);
  const sec = pick(['', '', ':00', ':45', ':60', ':4', ':45.123', ':45.1', ':45.1234567', '.5', ':', ':45,5']);
  const zone = pick(['', '', '', 'Z', ' Z', 'z', '+02:00', '-08:00', '+0200', ' +02:00', ' GMT', ' UTC', ' UT', ' EST', ' PST', ' PM', ' AM', ' pm', ' foo', 'foo', ' (c)', '+01', '+1', ' GMT+2',
    ' GMT+0200', '+99:99', ' +25:00', ' CEST', 'T', ' T', '  ', ' 5', ' )', ' -', '-', '+']);
  return `${y}-${m}-${d}${sep}${h}:${mi}${sec}${zone}`;
};

const cases = [];
const kinds = {};
const types = {};
let threw = 0;
let guard = 0;
while (cases.length < 1700 && guard++ < 40000) {
  const op = cases.length >= 1000 ? { op: 'column', values: [genDateCell()], opts: {} } : genOp();
  let result;
  try { result = execute(op); } catch (e) { result = { threw: true }; threw += 1; }
  kinds[op.op] = (kinds[op.op] || 0) + 1;
  if (op.op === 'column') types[result.type] = (types[result.type] || 0) + 1;
  cases.push({ op, e: canon(result) });
}
const chunks = emit('algo_syncinfer', 'syncinfer_fixture_template.e', cases, 'algo syncinfer ok');
console.log(`${cases.length} cases in ${chunks} chunks -> algo_syncinfer`, kinds, 'threw', threw, 'types', types);
