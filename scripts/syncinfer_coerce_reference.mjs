// Reference vectors for `coerceValue` / `coerceRecord` of appdor's src/io/infer.js against e.algo.syncinfer (L037): run
// appdor's own functions on generated cells (booleans, integers and identifiers, numbers in both decimal conventions,
// money, percents, ISO / slash / dot dates, datetimes with their suffixes, text, JSON numbers and booleans) for every
// field type, with and without the column's pinned date order and decimal convention, and under four local zones
// (UTC, Asia/Kolkata, America/Phoenix, Etc/GMT+7, set through process.env.TZ per case). Writes the link fixture
// tests/selfhost/fixtures/link/algo_syncinfer_coerce. APPDOR_DIR defaults to D:/repos/appdor.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appdor, canon, clone, emit, rng } from './ref_common.mjs';

const infer = await import(pathToFileURL(resolve(appdor, 'src/io/infer.js')).href);
const { int, pick, chance } = rng(0x7c0e);

const BOOLS = ['true', 'false', 'yes', 'No', 'Y', 'n', '1', '0', 'да', 'Не', 'TRUE', 'ДА', 'нЕ', 'maybe', ' yes ', 'TrUe'];
const INTS = ['1', '42', '007', '01067', '12345678901234567890', '9007199254740991', '9007199254740992', '-5', '0', '00', '100', '-0', '0888123456', '00000000000000000001',
  '000000000000009007199254740991', '000000000000009007199254740992', '9007199254740993', '123456789012345678901234567890'];
const NUMBERS = ['1.5', '19.99', '0.001', '1,234.56', '1.234,56', '-3.14', '.5', ',5', '1,234', '1.234', '1 234,56', '12 345.67', '1.2.3', '1,2,3.4', '1.234.567', '1,234,567',
  '1234,567', '12,3456', '0,500', '19,99', '1,50', '-1.234,5', '1,234,5', '12.345', '123,456', '1\u00a0234,56', '99.9', '0.5', '5,', '1..2', '--5', '1e5', '12abc', '٣', '-.5', '-,5',
  '0.1', '0.30000000000000004', '1.7976931348623157e308', '123456789.123456789', '9007199254740993.5', '0.000001', '1234567.1234567', '-0.0', '- 5',
  `1${'0'.repeat(30)}.5`, `0.${'0'.repeat(30)}1`, `5${'0'.repeat(320)}.1`];
const MONEY = ['$5', '€1.234,56', '£3', '¥100', '1,50 лв.', '12 BGN', '5 usd', '7.5 EUR', '$ 9', '12 лв', '13 ЛВ', '5 Eur', '€ 19,99', '$1,234.56', '12 лв.', 'BGN', '5 USD.', '1,5лв', '$-5', '-$5', '$ 1 234,5'];
const PERCENT = ['50%', '12,5 %', '3.14%', '100 %', '%', '5%%', '0,5%', '12.5 %', '-3%', '1.234,5%', '5 %  ', '50'];
const ISO = ['2024-03-15', '2024-3-5', '2024-13-45', '1999-12-31', '0001-01-01', '2024-02-30', '2024-1-1', '2024-00-10', '9999-12-31', '0000-01-01', '2024-04-31', '2023-02-29'];
const SLASH = ['25/12/2024', '05/03/2024', '12/25/2024', '5.3.24', '31.12.2024', '1/1/1', '31/02/2024', '00/10/2024', '13/13/2013', '1/2/0050', '25.12.50', '1/1/2024', '12/12/12',
  '30/04/2024', '29/02/2023', '29/02/2024', '3/15/24', '15.3.2024', '01.02.2003', '10/10/10', '1/13/2024', '0/5/2024', '5/0/2024', '1/1/999', '1/1/12345', '1/1/202', '31/12/99', '1/1/0100', '29/2/2000', '29/2/1900'];
const DATETIMES = ['2024-03-15 10:30', '2024-03-15T10:30:00', '2024-3-5 1:30', '2024-03-15 10:30:45.123', '2024-03-15T10:30Z', '2024-03-15 10:30 PM', '2024-03-15 25:00',
  '2024-02-30 10:30', '2024-03-15 10:30:45+02:00', '2024-03-15 10:30 foo', '2024-03-15 10:30:60', '2024-03-15T10:30:00.000Z', '2024-03-15 10:30 GMT', '2024-03-15 10:30 UTC', '2024-03-15 10:30 +0200',
  '2024-03-15 24:00', '2024-03-15 24:01', '2024-03-15 13:30 PM', '2024-03-15 12:30 AM', '2024-03-15 10:30 EST', '2024-03-15 10:30 (comment)', '2024-03-15 10:30:45 -08:00', '2024-03-15 10:30 pm',
  '2024-03-15 10:30:45 PST', '2024-03-15T23:59:59.999-12:00', '2024-03-15T00:00:00+14:00', '2024-12-31T23:30:00-05:00', '2024-01-01T00:30:00+05:30', 'Mar 5 2024', 'March 5, 2024 10:00', '5 March 2024',
  'Tue, 05 Mar 2024 10:00:00 GMT', 'Sat Mar 16 2024 10:00:00 GMT+0200', '+275760-09-13T00:00:00.000Z', '+275760-09-13T00:00:00.001Z', '-271821-04-20T00:00:00.000Z', '-271821-04-19T23:59:59.999Z',
  '+002024-03-15T10:30:00Z', '-000001-01-01T00:00:00Z', '-000000-01-01T00:00:00Z', '0001-01-01T00:00:00Z', '0000-01-01T00:00:00Z', '9999-12-31T23:59:59.999Z', '1970-01-01T00:00:00Z', '1969-12-31T23:59:59.999Z',
  '1900-01-01T00:00:00Z', '2024-03-15T10:30:00.5Z', '2024-03-15T10:30:00.123456Z', '2024-02-29T12:00:00', '2023-02-29T12:00:00', '12:30', '10:30 PM', '2024', '2024-03', '99', 'x'];
const TEXT = ['hello', ' padded ', '', '   ', 'N/A', 'a'.repeat(120), '😀', 'тест'];
const GROUPS = [BOOLS, INTS, NUMBERS, MONEY, PERCENT, ISO, SLASH, DATETIMES, TEXT];
const TYPES = ['checkbox', 'number', 'currency', 'percent', 'date', 'datetime', 'text', 'longtext', 'select', 'email', 'url', 'phone', 'weird', '', 'text'];
const JSONVALS = [1, 2.5, -3, 100, 0, 1e21, 1.5e-7, 0.1 + 0.2, 12345678901234567890, true, false, 19.99, 1234.5, 1.0, -0, 1e-7, 123456789012, 9007199254740991, 9007199254740992];
const ZONES = ['UTC', 'Asia/Kolkata', 'America/Phoenix', 'Etc/GMT+7'];

const cell = () => {
  const k = int(30);
  if (k === 0) return pick([null, undefined]);
  if (k < 4) return pick(JSONVALS);
  if (k === 4) return pick([[], ['a'], [1, 2]]);
  return pick(pick(GROUPS));
};
const orders = ['dmy', 'mdy', 'weird', null, undefined, '', 5];
const decimals = ['comma', 'dot', 'weird', null, undefined, '', 'COMMA'];
const optsOf = () => {
  const o = {};
  if (chance(0.5)) o.dateOrder = pick(orders);
  if (chance(0.5)) o.decimal = pick(decimals);
  return o;
};
const clean = (v) => (v === undefined ? null : typeof v === 'number' && !Number.isFinite(v) ? null : v);

function genOp() {
  const tz = pick(ZONES);
  if (chance(0.78)) {
    return { op: 'value', tz, raw: clean(cell()), type: pick(TYPES), opts: JSON.parse(JSON.stringify(optsOf())) };
  }
  const names = ['a', 'b', 'c', 'Дата', '1'];
  const fields = Array.from({ length: int(5) }, () => {
    const f = { name: pick(names) };
    if (chance(0.9)) f.type = pick(TYPES);
    if (chance(0.5)) f.dateOrder = pick(orders);
    if (chance(0.5)) f.decimal = pick(decimals);
    return JSON.parse(JSON.stringify(f));
  });
  const record = {};
  for (const n of [...names, 'extra']) if (chance(0.7)) record[n] = clean(cell());
  return { op: 'record', tz, record, fields };
}

function execute(op) {
  process.env.TZ = op.tz;
  if (op.op === 'value') return infer.coerceValue(clone(op.raw), op.type, clone(op.opts));
  return infer.coerceRecord(clone(op.record), clone(op.fields));
}

// The historical zones have local mean time before the standard one; a case whose instant has such an offset is left out
// (the port takes one fixed offset east of UTC).
const NOMINAL = { UTC: 0, 'Asia/Kolkata': -330, 'America/Phoenix': 420, 'Etc/GMT+7': 420 };
function historical(op) {
  if (op.tz === 'UTC') return false;
  process.env.TZ = op.tz;
  const cells = op.op === 'value' ? [op.raw] : Object.values(op.record);
  return cells.some((c) => {
    if (c === null || c === undefined) return false;
    const d = new Date(String(c).trim());
    return !Number.isNaN(d.getTime()) && d.getTimezoneOffset() !== NOMINAL[op.tz];
  });
}
const run = (op) => {
  try { return execute(op); } catch (e) { return { threw: true }; }
};
const cases = [];
const types = {};
let nulls = 0;
for (let guard = 0; cases.length < 1800 && guard < 50000; guard += 1) {
  const op = genOp();
  if (historical(op)) continue;
  const result = run(op);
  if (op.op === 'value') { types[op.type] = (types[op.type] || 0) + 1; if (result === null) nulls += 1; }
  cases.push({ op, e: canon(result === undefined ? null : result) });
}
// Every date and datetime literal as a date and a datetime cell under every zone and order.
for (const tz of ZONES) {
  for (const raw of [...ISO, ...SLASH, ...DATETIMES]) {
    for (const [type, opts] of [['date', {}], ['date', { dateOrder: 'dmy' }], ['date', { dateOrder: 'mdy' }], ['datetime', {}]]) {
      const op = { op: 'value', tz, raw, type, opts };
      if (historical(op)) continue;
      cases.push({ op, e: canon(run(op)) });
    }
  }
}
// Every number literal under every type and pin.
for (const raw of [...INTS, ...NUMBERS, ...MONEY, ...PERCENT]) {
  for (const type of ['number', 'currency', 'percent']) {
    for (const opts of [{}, { decimal: 'comma' }, { decimal: 'dot' }]) {
      const op = { op: 'value', tz: 'UTC', raw, type, opts };
      cases.push({ op, e: canon(run(op)) });
    }
  }
}
const chunks = emit('algo_syncinfer_coerce', 'syncinfer_coerce_fixture_template.e', cases, 'algo syncinfer coerce ok');
console.log(`${cases.length} cases in ${chunks} chunks`, types, 'nulls', nulls);
