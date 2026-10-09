// Reference and fixture generator for e.algo.formula (L026).
//
//   node scripts/formula_reference.mjs            (APPDOR_DIR defaults to D:/repos/appdor)
//
// Runs appdor's own formula engine (src/formula: tokenizer, parser, evaluator, registry, values) -- the code the
// Neper module ports -- over hand-written and seeded random formulas, and writes the outcomes, rendered in one
// canonical text, into tests/selfhost/fixtures/link/algo_formula/src/main.e (from
// scripts/formula_core_fixture_template.e). The registry is a small one built here (IF, IFERROR, ISERROR, ISBLANK,
// TYPEOF, SUM, UPPER, LEN, PI and the language forms LET and LETS) so that the core is checked on its own; the
// function library is checked by its own fixtures.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, 'src/formula', p)).href);
const { Registry } = await load('registry.js');
const { Evaluator } = await load('evaluator.js');
const { parse, collectReferences } = await load('parser.js');
const errors = await load('errors.js');
const values = await load('values.js');
const index = await load('index.js');
const { isError, isNA, genericError, limitError, valueError } = errors;
const { toBool, toText, isBlank, typeOf, collectNumbers } = values;

// --- the registry under test -------------------------------------------------------------------------------------

const childScope = (scope) => ({ ...(scope || {}) });
const nameOf = (n) => (n && (n.type === 'name' || n.type === 'field') ? n.name : n && n.type === 'string' ? n.value : null);
const registry = new Registry();
registry.register({ name: 'LET', lazy: true, minArgs: 3, maxArgs: 3, fn: (nodes, ctx, ev, scope) => {
  const name = nameOf(nodes[0]);
  if (!name) return valueError('LET expects a variable name as its first argument');
  const v = ev.eval(nodes[1], scope);
  if (isError(v)) return v;
  const inner = childScope(scope);
  inner[name] = v;
  return ev.eval(nodes[2], inner);
} });
registry.register({ name: 'LETS', lazy: true, minArgs: 3, fn: (nodes, ctx, ev, scope) => {
  if (nodes.length % 2 === 0) return valueError('LETS expects name/value pairs followed by a body expression');
  let cur = childScope(scope);
  for (let i = 0; i < nodes.length - 1; i += 2) {
    const name = nameOf(nodes[i]);
    if (!name) return valueError('LETS variable names must be identifiers');
    const v = ev.eval(nodes[i + 1], cur);
    if (isError(v)) return v;
    cur = childScope(cur);
    cur[name] = v;
  }
  return ev.eval(nodes[nodes.length - 1], cur);
} });
registry.register({ name: 'IF', lazy: true, minArgs: 2, maxArgs: 3, fn: (nodes, ctx, ev, scope) => {
  const c = ev.eval(nodes[0], scope);
  if (isError(c)) return c;
  if (toBool(c)) return ev.eval(nodes[1], scope);
  return nodes.length > 2 ? ev.eval(nodes[2], scope) : false;
} });
registry.register({ name: 'IFERROR', lazy: true, minArgs: 2, maxArgs: 2, fn: (nodes, ctx, ev, scope) => {
  const v = ev.eval(nodes[0], scope);
  if (isError(v)) return ev.eval(nodes[1], scope);
  return v;
} });
registry.register({ name: 'ISERROR', passErrors: true, minArgs: 1, maxArgs: 1, fn: (args) => isError(args[0]) });
registry.register({ name: 'ISBLANK', passErrors: true, minArgs: 1, maxArgs: 1, fn: (args) => isBlank(args[0]) });
registry.register({ name: 'TYPEOF', passErrors: true, minArgs: 1, maxArgs: 1, fn: (args) => typeOf(args[0]) });
registry.register({ name: 'SUM', minArgs: 1, fn: (args) => {
  const n = (() => { try { return collectNumbers(args); } catch (e) { return e; } })();
  if (isError(n)) return n;
  return n.reduce((a, b) => a + b, 0);
} });
registry.register({ name: 'UPPER', aliases: ['UPPERCASE'], minArgs: 1, maxArgs: 1, fn: (args) => {
  const s = toText(args[0]);
  return isError(s) ? s : s.toUpperCase();
} });
registry.register({ name: 'LEN', aliases: ['LENGTH'], minArgs: 1, maxArgs: 1, fn: (args) => {
  const s = toText(args[0]);
  return isError(s) ? s : s.length;
} });
registry.register({ name: 'PI', minArgs: 0, maxArgs: 0, fn: () => Math.PI });
registry.register({ name: 'ERROR', passErrors: true, minArgs: 0, maxArgs: 1, fn: (args) => genericError(args.length ? toText(args[0]) : 'Error') });

// --- canonical rendering -----------------------------------------------------------------------------------------

const hex = (s) => (s === '' ? '_' : Buffer.from(s, 'utf8').toString('hex'));
function render(v) {
  if (isError(v)) return `E|${v.code}|${hex(v.message)}`;
  if (v === null || v === undefined) return '_';
  if (typeof v === 'number') return `N|${String(v)}`;
  if (typeof v === 'string') return `T|${hex(v)}`;
  if (typeof v === 'boolean') return `B|${v ? 1 : 0}`;
  if (v instanceof Date) return `D|${Number.isNaN(v.getTime()) ? 'invalid' : v.toISOString()}`;
  if (Array.isArray(v)) return `[${v.map(render).join(',')}]`;
  return `?|${String(v)}`;
}

// --- the cases ----------------------------------------------------------------------------------------------------

const FIELDS = {
  Price: 10, Qty: 3, Name: 'Ada Lovelace', Empty: '', Nothing: null, Flag: true, NumText: '42', Neg: -7, Float: 1.5,
  Big: 1e21, Small: 1e-7, DateText: '2026-01-15', Stamp: '2026-01-15T23:30:00', List: [1, 2, 3], Mixed: [1, 'a', null],
  Padded: ' 5 ', Hex: '0x10', Inf: 'Infinity', Word: 'abc', 'Unit Price': 2.5, Zero: 0,
};
const DATE_FIELD = { When: '2026-03-01T12:00:00.000Z' };

function runCase(spec) {
  const fields = { ...spec.fields };
  for (const [k, v] of Object.entries(spec.dates || {})) fields[k] = new Date(v);
  const ctx = { fields, strictRefs: !!spec.strict };
  if (spec.fieldName) ctx.fieldName = spec.fieldName;
  if (spec.formulas) ctx.formulas = spec.formulas;
  if (spec.maxSteps) ctx.maxSteps = spec.maxSteps;
  if (spec.maxNodes) ctx.maxNodes = spec.maxNodes;
  // index.evaluate with the test registry
  return index.evaluate(spec.src, ctx, registry);
}

const cases = [];
function add(spec) {
  const out = runCase(spec);
  cases.push({ k: 'E', ...spec, expect: render(out) });
}

const base = { fields: FIELDS, dates: DATE_FIELD };
const sources = [
  '1 + 2 * 3', '(1 + 2) * 3', '2 ^ 3 ^ 2', '-2 ^ 2', '10 / 4', '10 % 4', '-7 % 3', '7 % -3', '5.5 % 2', '1 / 0', '1 % 0', '0 / 0 + 1',
  '{Price} * {Qty}', '{Price} + {Nothing}', '{Nothing} + 1', '{Empty} + 1', '{NumText} + 1', '{Padded} * 2', '{Hex} + 0', '{Inf} + 1', '{Word} + 1',
  '{Price} & "x"', '{Flag} & "!"', '{List} & "|"', '{Mixed} & ""', '"a" & "b" & "c"', '{Float} & {Big} & {Small}', '1e21 & 1e-7 & 0.000001 & 123456789012345680000',
  '"abc" = "ABC"', '"abc" == "abd"', '"a" != "A"', '1 <> 2', '{Nothing} = {Empty}', '{Nothing} = 0', '{Flag} = 1', '{Flag} = "yes"', '2 < 10', '"2" < "10"', '{NumText} > 5',
  '"b" > "a"', '{DateText} < {Stamp}', '{When} > {DateText}', '{When} = "2026-03-01T12:00:00.000Z"', '"2026-02-01T00:00:00Z" > "2026-02-01"',
  'true && false', 'true || 1/0', 'false && 1/0', '!true', '!{Nothing}', '!"x"', '1 && "y"', '{Flag} ? "yes" : "no"', '{Nothing} ? 1 : 2', '1 ? 2 ? 3 : 4 : 5', '1 / 0 ? 1 : 2',
  '[1, 2, 3]', '[1, "a", {Nothing}, [2, 3]]', '[]', '[1, 2,]', 'SUM([1, 2], 3)', 'SUM({List}, {Mixed})', 'SUM("a", 2)', 'SUM(1/0, 2)', 'SUM()', 'SUM',
  'IF({Price} > 5, "big", "small")', 'IF(true, 1)', 'IF(false, 1)', 'IF(1/0, 1, 2)', 'IFERROR(1/0, "n/a")', 'IFERROR(2, 3)', 'ISERROR(1/0)', 'ISERROR(1)',
  'ISBLANK({Nothing})', 'ISBLANK({Empty})', 'ISBLANK(0)', 'TYPEOF({Stamp})', 'TYPEOF({When})', 'TYPEOF([1])', 'TYPEOF(1/0)', 'TYPEOF({Nothing})',
  'UPPER("abc")', 'upper(Name)', 'Upper_Case', 'UPPERCASE({Name})', 'LEN({Name})', 'LEN({Big})', 'LEN({Small})', 'LEN(PI())', 'PI', 'pi()', 'PI + 1',
  'Name', 'name', '{name}', '{NAME}', '{Unit Price} * 2', '{ Unit Price }', 'Unknown', '{Unknown}', 'Unknown()', 'UPPER()', 'UPPER(1, 2)', 'IF(1)', 'LET(x, 2)',
  'LET(x, 2, x * 3)', 'LET(x, 2, LET(y, x + 1, x * y))', 'LET("s", "hi", s & s)', 'LET({f}, 5, f + {Price})', 'LETS(a, 1, b, a + 1, a + b)', 'LETS(a, 1)', 'LETS(1, 2, 3)',
  'LET(x, 1/0, 5)', 'LET(x, 2, x) + x', 'LET(Price, 1, Price) + Price',
  '1 + // comment\n 2', '"a // not a comment"', '  \t 7 \r\n', 'ERROR("boom")', 'ERROR()', 'IFERROR(ERROR("x"), 0)', 'ISERROR(ERROR("x"))',
  '"a\\nb"', '\'it\\\'s\'', '"tab\\tx\\\\y"', '"\\q"', '.5 + 5.', '1e3', '1.5E-2', '1e', '0x10', '1_000',
  '', '   ', '1 +', '(1', '1)', '1 2', '{Unterminated', '"open', '@', '1 + * 2', 'f(1,,2)', '[1,,2]', '1 ? 2', 'a.b.c', '$x + 1', '1.2.3',
  'true', 'FALSE', 'null', 'NULL + 1', 'TRUE & FALSE', '-"5"', '+"x"', '-{Nothing}', '+{Empty}', '+{NumText}', '- - 3', '!!1',
  '{Big} + 1', '{Small} * 1', '2 ^ 0.5', '(-8) ^ (1/3)', '0 ^ 0', '10 ^ 400', '1 - 0.9', '0.1 + 0.2', '1e300 * 1e10', '-1e300 * 1e10',
];
for (const src of sources) add({ ...base, src });
// strict references
for (const src of ['{Missing}', 'Missing', 'Price + Missing', 'PI']) add({ ...base, src, strict: true });
// budgets
add({ ...base, src: '1 + 2 + 3 + 4 + 5', maxSteps: 3 });
add({ ...base, src: 'IFERROR(1 + 2 + 3 + 4, 0)', maxSteps: 4 });
add({ ...base, src: 'ISERROR(1 + 2 + 3 + 4)', maxSteps: 4 });
add({ ...base, src: '[1, 2, 3, 4, 5, 6]', maxSteps: 4 });
add({ ...base, src: 'SUM(1, 2, 3)', maxSteps: 2 });
add({ ...base, src: '1 + 2 + 3 + 4 + 5', maxNodes: 5 });
add({ ...base, src: '1 + 2 + 3', maxNodes: 5 });
add({ ...base, src: 'SUM(1,2,3,4,5,6,7,8,9)', maxNodes: 9 });
add({ ...base, src: 'SUM(1,2,3,4,5,6,7,8,9)', maxNodes: 10 });
// sibling formulas and cycles
const formulas = { Total: '{Price} * {Qty}', Tax: '{Total} * 0.2', Gross: '{Total} + {Tax}', A: '{B} + 1', B: '{A} + 1', Self: '{Self} + 1', Empty: '', Broken: '1 +', UsesBroken: '{Broken} + 1', Chain1: '{Chain2}', Chain2: '{Chain3}', Chain3: '{Chain1}' };
for (const src of ['{Gross}', '{Tax} + 1', 'Total', '{A}', '{B}', '{Self}', '{Empty}', '{Broken}', '{UsesBroken}', '{Chain1}', 'total', '{Missing}']) add({ ...base, src, formulas });
add({ ...base, src: '{Progress} + 1', fieldName: 'Progress', fields: { ...FIELDS, Progress: 5 } });
add({ ...base, src: '{Progress} + 1', fieldName: 'progress', formulas: { Progress: '{Progress} + 1' } });
add({ ...base, src: '{Other}', fieldName: 'Mine', formulas: { Other: '{Mine} + 1', Mine: '{Other}' } });
add({ ...base, src: 'LET(x, {Gross}, x + {Total})', formulas });

// random expressions
let seed = 0x5eed;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const NAMES = Object.keys(FIELDS).filter((n) => !n.includes(' ')).concat(['When', 'Missing']);
function gen(d) {
  const r = rnd();
  if (d <= 0 || r < 0.28) {
    const k = rnd();
    if (k < 0.3) return pick(['0', '1', '2', '3', '10', '2.5', '.5', '1e3', '100']);
    if (k < 0.45) return JSON.stringify(pick(['', 'a', 'B', 'abc', '5', ' 7 ', '2026-01-15', 'true', 'x y']));
    if (k < 0.52) return pick(['true', 'false', 'null']);
    if (k < 0.85) return `{${pick(NAMES)}}`;
    return pick(NAMES);
  }
  if (r < 0.55) return `(${gen(d - 1)} ${pick(['+', '-', '*', '/', '%', '^', '&', '=', '==', '!=', '<>', '<', '<=', '>', '>=', '&&', '||'])} ${gen(d - 1)})`;
  if (r < 0.62) return `${pick(['-', '+', '!'])}${gen(d - 1)}`;
  if (r < 0.68) return `(${gen(d - 1)} ? ${gen(d - 1)} : ${gen(d - 1)})`;
  if (r < 0.74) return `[${Array.from({ length: Math.floor(rnd() * 4) }, () => gen(d - 1)).join(', ')}]`;
  if (r < 0.80) return `IF(${gen(d - 1)}, ${gen(d - 1)}${rnd() < 0.7 ? `, ${gen(d - 1)}` : ''})`;
  if (r < 0.85) return `IFERROR(${gen(d - 1)}, ${gen(d - 1)})`;
  if (r < 0.90) return `${pick(['ISERROR', 'ISBLANK', 'TYPEOF', 'UPPER', 'LEN'])}(${gen(d - 1)})`;
  if (r < 0.94) return `SUM(${Array.from({ length: 1 + Math.floor(rnd() * 3) }, () => gen(d - 1)).join(', ')})`;
  if (r < 0.97) return `LET(v, ${gen(d - 1)}, ${rnd() < 0.5 ? 'v' : `v ${pick(['+', '&', '='])} ${gen(d - 1)}`})`;
  return `LETS(p, ${gen(d - 1)}, q, p ${pick(['+', '&'])} 1, ${pick(['p', 'q', 'p & q'])})`;
}
for (let i = 0; i < 450; i += 1) add({ ...base, src: gen(1 + Math.floor(rnd() * 4)) });

// parse diagnostics, dependencies
function parseCase(src, opts = {}) {
  try {
    const ast = parse(src, opts);
    return { ok: true, refs: collectReferences(ast) };
  } catch (e) {
    return { ok: false, message: e.message, offset: e.offset, complexity: e.code === 'formula-complexity' };
  }
}
for (const src of ['1 + 2', '{A} + {B} * A', 'SUM({x}, y, {x})', 'IF(a, {b c}, [d, e])', 'LET(v, {k}, v + w)', '', '1 +', '(1', 'f(1,,2)', '{open', '"open', '@x', '1 2', '1)', 'a ? b', '"é" + @', '😀 + 1', '"😀" & #', '{é} + 😀']) {
  const r = parseCase(src);
  cases.push({ k: 'P', src, expect: r.ok ? `ok|${r.refs.map(hex).join(',')}` : `err|${r.offset}|${hex(r.message)}|${r.complexity ? 1 : 0}` });
}
{
  const r = parseCase('1+1+1+1+1+1', { maxNodes: 5 });
  cases.push({ k: 'P', src: '1+1+1+1+1+1', maxNodes: 5, expect: r.ok ? 'ok|' : `err|${r.offset}|${hex(r.message)}|${r.complexity ? 1 : 0}` });
}

// dependency graphs
function graphCase(graph) {
  const cycle = index.detectCycle(graph);
  const order = index.evaluationOrder(graph);
  cases.push({ k: 'G', graph, expect: `${cycle ? cycle.map(hex).join(',') : '-'}|${order ? order.map(hex).join(',') : '-'}` });
}
graphCase({});
graphCase({ A: '1' });
graphCase({ A: '{B} + 1', B: '{C} + 1', C: '1' });
graphCase({ A: '{B}', B: '{A}' });
graphCase({ A: '{A}' });
graphCase({ X: '{Y} + {Z}', Y: '{Z}', Z: '1', W: '{X} + {Q}' });
graphCase({ A: '{B}', B: '{C}', C: '{D}', D: '{B}', E: '1' });
graphCase({ A: '1 +', B: '{A}' });
graphCase({ Total: '{Price} * {Qty}', Tax: '{Total} * 0.2', Gross: '{Total} + {Tax}' });
for (let i = 0; i < 40; i += 1) {
  const names = ['A', 'B', 'C', 'D', 'E', 'F'].slice(0, 2 + Math.floor(rnd() * 5));
  const graph = {};
  for (const n of names) {
    const refs = names.filter(() => rnd() < (i % 2 ? 0.25 : 0.12)).map((r) => `{${r}}`);
    graph[n] = refs.length ? refs.join(' + ') : '1';
  }
  graphCase(graph);
}

// --- write the fixture ----------------------------------------------------------------------------------------

const line = (c) => {
  if (c.k === 'E') {
    const spec = {
      k: 'E', src: c.src, fields: c.fields, dates: c.dates || {}, formulas: c.formulas || {}, fieldName: c.fieldName || '', strict: !!c.strict,
      maxSteps: c.maxSteps || 0, maxNodes: c.maxNodes || 0, expect: c.expect,
    };
    return JSON.stringify(spec);
  }
  if (c.k === 'P') return JSON.stringify({ k: 'P', src: c.src, maxNodes: c.maxNodes || 0, expect: c.expect });
  return JSON.stringify({ k: 'G', graph: c.graph, expect: c.expect });
};
const lines = cases.map(line);
const chunkSize = 25;
const chunks = [];
for (let i = 0; i < lines.length; i += chunkSize) {
  const body = lines.slice(i, i + chunkSize).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n');
  chunks.push(`"${body}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}(), &registry) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'formula_core_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_formula/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
const kinds = { E: 0, P: 0, G: 0 };
for (const c of cases) kinds[c.k] += 1;
const errorsSeen = cases.filter((c) => c.k === 'E' && c.expect.startsWith('E|')).length;
console.log(`wrote ${cases.length} cases (${kinds.E} evaluations of which ${errorsSeen} are errors, ${kinds.P} parses, ${kinds.G} graphs) in ${chunks.length} chunks`);
