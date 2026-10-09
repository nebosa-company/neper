// Reference vectors for `e.algo.transpile` (L028): translate formulas of every dialect with appdor's own
// `src/formula/compat` and rank pasted text with its `detectDialect`, then write the link fixture
// tests/selfhost/fixtures/link/algo_transpile. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const compat = await import(pathToFileURL(resolve(appdor, 'src/formula/compat/index.js')).href);
const dialects = await import(pathToFileURL(resolve(appdor, 'src/formula/compat/dialects.js')).href);

const hex = (s) => (s === '' ? '_' : Buffer.from(s, 'utf8').toString('hex'));
const render = (r) => `${r.status}|${r.canonical === null ? '-' : hex(r.canonical)}|${r.diagnostics.map((d) => `${d.category}:${hex(d.message)}:${d.function === undefined ? '-' : hex(d.function)}`).join(';')}`;

let seed = 0x2468;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];

const ids = Object.keys(dialects.DIALECTS);
const REFS = {
  brace: ['{Status}', '{Due Date}', '{A}', '{B}', '{C}'],
  field: ['field("Status")', "field('Due Date')", 'FIELD( "A" )', '{A}'],
  prop: ['prop("Status")', "prop('Due Date')", 'Prop( "A" )', '{A}'],
  bracket: ['[Status]', '[Due Date]', '[A]', '[ B ]', '{A}'],
};
const ARGS = ['1', '2', '3', '"days"', '"x"', '"YYYY-MM-DD"', '[1, 2]', 'BLANK()', 'true', '-5', '2.5'];
const SHAPES = [
  (r) => `${r[0]} + 1`, (r) => `-(${r[0]} + ${r[1]}) * 2`, (r) => `!${r[0]} && ${r[1]} || ${r[2]}`, (r) => `${r[0]} ? 1 : ${r[1]} ? 2 : 3`,
  (r) => `(${r[0]} ? 1 : 2) + 3`, () => '2 ^ 3 ^ 2', () => '(2 ^ 3) ^ 2', (r) => `${r[0]} - (${r[1]} - ${r[2]})`, (r) => `(${r[0]} - ${r[1]}) - ${r[2]}`,
  () => '"a\\"b\\nc\\td"', (r) => `${r[0]} <> ${r[1]}`, (r) => `${r[0]} == 1`, (r) => `${r[0]} = "[Draft]"`, () => 'foo', () => '{weird name} + 1',
  () => '[1, 2, [3]]', (r) => `LEN(${r[0]}) > 3 & "x"`, (r) => `IF(${r[0]} > 1, "a", "b")`, (r) => `if(${r[0]} > 1, "a", "b")`, () => 'NOPE(1)', () => '',
  () => '1 +', () => '"unclosed', (r) => `${r[0]} % 2`, () => 'record_id()', () => 'Row()', () => 'lets(x, 1, x + 1)', () => 'let(x, 1, x)', () => '1e3 + .5',
];
const cases = [];
const add = (d, s, c) => {
  const r = compat.translate(s, d, c ? { columns: c } : {});
  cases.push(JSON.stringify({ d, s, ...(c ? { c } : {}), e: render(r) }));
};
for (const d of ids) {
  const refs = REFS[dialects.DIALECTS[d].fieldRefs[0]];
  for (const shape of SHAPES) {
    for (let k = 0; k < 2; k += 1) {
      const r = [pick(refs), pick(refs), pick(refs)];
      add(d, shape(r), k === 1 ? ['Status', 'A', 'due date'] : undefined);
    }
  }
  // every mapped function, with varied argument lists
  for (const name of Object.values(dialects.DIALECTS[d].functions).map((m) => m.source)) {
    for (const n of [0, 1, 2, 3]) {
      const args = Array.from({ length: n }, () => (rnd() < 0.5 ? pick(refs) : pick(ARGS)));
      add(d, `${name}(${args.join(', ')})`);
      add(d, `${name.toLowerCase()}(${args.join(', ')})`);
    }
    add(d, `IF(${pick(refs)} > 1, ${name}(${pick(refs)}, ${pick(ARGS)}), ${name}(${pick(ARGS)}))`);
  }
}
// Quickbase variables and comments
for (const s of [
  'var x = [A] * 2; x + 1', 'var text y = "a"; var n = 3; y & n', 'VAR a = 1;', 'var a = 1; // note\nvar b = a + 1; b', '// only a comment', "// Bob's rule\nIf([Status] = \"x\", 1, 2)",
  'var x = [A]; // c1\n// c2\nx', 'var = 3', 'var x', 'If([Status] = "[Draft]", 1, 2)', 'GetRecords([A], [B])', 'Size([A]) + SumValues([B])', 'SearchAndReplace([A], "a", "b")',
  'var x = 1; var y = 2; ', '1; 2', 'var x = ["a;b"]; x',
]) add('quickbase', s);
for (const d of ids) for (const s of ['IF({A}, 1, 2)', 'X(', '']) add(d, s, ['A']);
add('nosuch', '1 + 1');
add('airtable', `"${'x'.repeat(20001)}"`);
// detection
for (const s of [
  'IF({Status}="Done", 1, 2)', 'field("A") + field("B")', 'prop("A") + 1', '[Status] + [Due]', 'var x = [A]; x', 'WORKDAYS({A}, {B})', 'FORMATDATE(prop("d"), "L")',
  'ADD_DAYS({A}, 3)', 'VLOOKUP([A], [B])', 'USEREMAIL()', 'RECORD_ID()', '', 'plain text', '1 + 2', 'SIZE([A]) + GETRECORDS([B])', 'lets(x, 1, x)', 'dateBetween(prop("a"), prop("b"))',
  '{A} + [B] + field("C") + prop("D")', 'DATE_DIFF(field("a"), field("b"))', 'SELECT([T], [A] > 1)', 'abc (1) + def\t(2)', 'x1(2) _y( 3 )',
]) cases.push(JSON.stringify({ detect: s, e: compat.detectDialect(s).map((r) => `${r.dialect}:${r.score}`).join(',') }));

const chunks = [];
const size = 25;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}(), &registry) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'transpile_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_transpile/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_transpile`);
