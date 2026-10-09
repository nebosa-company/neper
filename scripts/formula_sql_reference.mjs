// Reference vectors for `e.algo.formula.sql` (L029): compile formulas with appdor's own `compileToSql` and
// classify them with its `classifyPushdown`, then write the link fixture tests/selfhost/fixtures/link/
// algo_formula_sql. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const sqlc = await load('src/formula/sql-compiler.js');
const push = await load('src/formula/pushdown.js');
const index = await load('src/formula/index.js');

const SCHEMA = {
  Price: { type: 'number', column: 'price' }, Qty: { type: 'number', column: 'qty' }, Name: { type: 'text', column: 'name' },
  Notes: { type: 'longText', column: 'notes' }, Due: { type: 'date', column: 'due' }, Done: { type: 'checkbox', column: 'done' },
  'Total Cost': { type: 'currency', column: 'total_cost' }, Rating: { type: 'rating', column: 'rating' },
  Created: { type: 'created_time', column: 'created_at' }, Tag: { type: 'singleSelect', column: 'tag' },
  'We"ird': { type: 'percent', column: 'we"ird' },
};

const hex = (s) => (s === '' ? '_' : Buffer.from(s, 'utf8').toString('hex'));
const renderParam = (p) => (p === null || p === undefined ? '_' : typeof p === 'number' ? `n${String(p)}` : typeof p === 'boolean' ? `b${p ? 1 : 0}` : `s${hex(p)}`);
const render = (r) => `${r.pushdown}|${r.type}|${r.oversize ? 1 : 0}|${hex(r.sql)}|${r.params.map(renderParam).join(',')}`;
const renderVerdict = (v) => `${v.classification}|${v.reason || '-'}|${(v.unsupportedFunctions || []).join(',')}|${v.unsupportedFunctions === undefined ? 'u' : 'd'}`;

let seed = 0x5eed;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];

const FIELDS = ['{Price}', '{Qty}', '{Name}', '{Notes}', '{Due}', '{Done}', '{Total Cost}', '{Rating}', '{Created}', '{Tag}', '{Missing}', '{price}', '{We"ird}'];
const LITS = ['0', '1', '2', '2.5', '-3', '100', '0.1', '"abc"', '""', '"Hello"', '"a%b_c"', 'true', 'false', 'BLANK()', '"days"', '"d"', '"month"', '"mo"', '" Weeks "', '1e3'];
const VOCAB = [...FIELDS, ...FIELDS.slice(0, 7), ...LITS];
const cases = [];
const seen = new Set();
const add = (s, q = 1) => {
  const key = `${q}|${s}`;
  if (seen.has(key)) return;
  seen.add(key);
  const r = sqlc.compileToSql(s, SCHEMA, q === 0 ? { doubleQuoteColumns: false } : {});
  cases.push(JSON.stringify({ s, ...(q === 0 ? { q: 0 } : {}), e: render(r) }));
};
const addClassify = (s) => cases.push(JSON.stringify({ c: s, e: renderVerdict(push.classifyPushdown(s)) }));

// every function (and alias) at its arities
for (const entry of index.getRegistry().list()) {
  const names = [entry.name, ...(entry.aliases || [])];
  const min = entry.minArgs ?? 0;
  const max = entry.maxArgs === undefined || entry.maxArgs === -1 ? min + 3 : Math.min(entry.maxArgs, min + 3);
  for (const n of names) {
    for (let arity = Math.max(0, min - 1); arity <= max + 1; arity += 1) {
      for (let k = 0; k < 4; k += 1) add(`${n}(${Array.from({ length: arity }, () => pick(VOCAB)).join(', ')})`);
    }
    add(n);
    add(n.toLowerCase());
  }
}
// functions the compiler maps itself, over typed arguments
const NAMES = ['CONTAINS', 'STARTS_WITH', 'ENDS_WITH', 'STARTSWITH', 'ENDSWITH', 'COALESCE', 'NVL', 'NULLIF', 'CEIL', 'CEILING', 'IFBLANK', 'ISBLANK', 'ISEMPTY', 'LEFT', 'RIGHT',
  'MID', 'SUBSTRING', 'REPLACE', 'SUBSTITUTE', 'REPT', 'REPEAT', 'FIND', 'SEARCH', 'ROUND', 'ROUNDUP', 'ROUNDDOWN', 'MOD', 'POWER', 'POW', 'EXP', 'LN', 'LOG', 'LOG10', 'SQRT', 'ASIN',
  'ACOS', 'MIN', 'MAX', 'IF', 'IFS', 'SWITCH', 'CASE', 'AND', 'OR', 'NOT', 'LEN', 'UPPER', 'TRIM', 'CONCAT', 'CONCATENATE', 'TEXT', 'TOSTRING', 'YEAR', 'MONTH', 'DAY', 'WEEKDAY', 'WEEKNUM',
  'ISOWEEKNUM', 'TODATE', 'DATEADD', 'DATEDIF', 'DATE_ADD', 'SUM', 'AVERAGE', 'COUNT', 'ISNUMBER', 'ISTEXT', 'ISERROR', 'IFERROR', 'NOW', 'TODAY', 'CURRENTUSER', 'GETRECORDS', 'JOIN', 'SPLIT'];
for (const n of NAMES) {
  for (let k = 0; k < 24; k += 1) {
    const arity = 1 + Math.floor(rnd() * 4);
    add(`${n}(${Array.from({ length: arity }, () => pick(VOCAB)).join(', ')})`);
  }
}
for (const unit of ['"d"', '"day"', '"days"', '"D"', '" day "', '"ms"', '"s"', '"min"', '"h"', '"w"', '"mo"', '"months"', '"q"', '"year"', '"y"', '"fortnight"', '"m"', '{Tag}', '1', 'BLANK()']) {
  for (const f of ['DATEADD', 'DATE_ADD', 'dateadd', 'DATEDIF', 'date_dif']) {
    add(`${f}({Due}, 3, ${unit})`);
    add(`${f}({Due}, {Created}, ${unit})`);
    add(`${f}({Due}, {Missing}, ${unit})`);
    add(`${f}({Name}, {Qty}, ${unit})`);
  }
}
// operators over typed operands
const OPS = ['+', '-', '*', '/', '%', '^', '&', '=', '==', '!=', '<>', '<', '<=', '>', '>=', '&&', '||'];
for (const op of OPS) {
  for (let k = 0; k < 40; k += 1) add(`${pick(VOCAB)} ${op} ${pick(VOCAB)}`);
}
for (const u of ['-', '+', '!']) for (const v of VOCAB) add(`${u}${v.startsWith('-') ? `(${v})` : v}`);
for (let k = 0; k < 120; k += 1) add(`${pick(VOCAB)} ? ${pick(VOCAB)} : ${pick(VOCAB)}`);
// nested forms
const FN = ['IF', 'ABS', 'ROUND', 'LEN', 'UPPER', 'LEFT', 'MID', 'MOD', 'POWER', 'SQRT', 'EXP', 'LN', 'MIN', 'MAX', 'AND', 'OR', 'NOT', 'COALESCE', 'CONCAT', 'FIND', 'IFS', 'SWITCH', 'ISBLANK',
  'CONTAINS', 'REPEAT', 'WEEKNUM', 'YEAR', 'TEXT', 'NULLIF', 'FLOOR', 'INT', 'SIGN'];
function gen(depth) {
  if (depth === 0 || rnd() < 0.25) return pick(VOCAB);
  const r = rnd();
  if (r < 0.35) return `(${gen(depth - 1)} ${pick(OPS)} ${gen(depth - 1)})`;
  if (r < 0.45) return `(${gen(depth - 1)} ? ${gen(depth - 1)} : ${gen(depth - 1)})`;
  if (r < 0.5) return `!${gen(depth - 1)}`;
  const n = pick(FN);
  const arity = 1 + Math.floor(rnd() * 3);
  return `${n}(${Array.from({ length: arity }, () => gen(depth - 1)).join(', ')})`;
}
for (let k = 0; k < 900; k += 1) add(gen(1 + Math.floor(rnd() * 3)), k % 11 === 0 ? 0 : 1);
// the size bound
let nest = '{Price}';
for (let k = 0; k < 14; k += 1) nest = `EXP(${nest})`;
add(nest);
let nest2 = '{Price}';
for (let k = 0; k < 9; k += 1) nest2 = `EXP(${nest2})`;
add(nest2);
add(`${'{Price} * '.repeat(40)}1`);
add(`POWER(${nest2}, ${nest2})`);
add(`CONCAT(${Array.from({ length: 80 }, () => '"abcdefgh"').join(', ')})`);
// classification
for (const s of ['', '   ', '1 +', 'NOW()', 'TODAY() + 1', '{Price} + 1', 'NOPE(1)', 'NOPE(1) + NOW()', 'GETRECORDS("t")', 'getrecords("t") + children(1)', 'IF({Done}, SUM(1, 2), 3)', 'CURRENTUSER()',
  'LET(x, 1, x + 1)', 'UPPER("a") & LOWER("B")', 'FOO(BAR(1), BAR(2))', 'ancestors()', 'RANDBETWEEN(1, 2)', 'UUID()', 'DAYSSINCE({Due})', 'IF(NOPE(), UNKNOWN(), NOPE())', '[1, 2, 3]']) addClassify(s);
for (const entry of index.getRegistry().list()) addClassify(`${entry.name}(1, 2)`);
for (let k = 0; k < 120; k += 1) addClassify(gen(2));

const chunks = [];
const size = 25;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}(), &registry, columns) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'formula_sql_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_formula_sql/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
const kinds = {};
for (const l of cases) { const e = JSON.parse(l).e; const k = e.split('|')[0]; kinds[k] = (kinds[k] || 0) + 1; }
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_formula_sql`, JSON.stringify(kinds));
