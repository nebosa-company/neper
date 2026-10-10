// Vectors for `e.fmt.css.selector` (L038): random selector lists built from well-formed and malformed pieces, parsed by
// Vaper's own parser (scripts/css_selector_reference.dart under `dart run`) and written as the link fixture
// tests/selfhost/fixtures/link/text_css_selector. Usage: DART=D:/flutter/bin/dart.bat node scripts/css_selector_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x5e1c;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

const SIMPLE = [
  'a', 'DIV', 'p', 'Span', '*', '.cls', '.Cls-2', '#main', '#Id', '[href]', '[HREF]', '[a=b]', '[a="b c"]', "[a='x']", '[a=1]', '[a=1.5em]', '[a=50%]',
  '[a~=b]', '[a|=b]', '[a^=b]', '[a$=b]', '[a*=b]', '[a=b i]', '[a=b I]', '[a=b s]', '[a="b"i]', '[ns|a=b]', '[*|a]', '[|a]', '[a=]', '[=b]', '[a!=b]', '[]',
  '[a', ':first-child', ':LAST-CHILD', ':only-child', ':first-of-type', ':last-of-type', ':only-of-type', ':empty', ':root', ':hover', ':focus', ':active', ':checked',
  ':lang(en)', ':dir(rtl)', ':nth-child(2n+1)', ':nth-child(odd)', ':nth-child(3)', ':nth-child( 2n + 1 of .a, .b )', ':nth-last-child(-n+3)', ':nth-of-type(even)',
  ':nth-last-of-type(2)', ':nth-child(2n+1 OF li.x)', ':nth-child(2n+1 offset)', ':not(.a)', ':not(.a, #b)', ':not(:hover)', ':is(a, b.c)', ':matches(x)',
  ':where(.a .b)', ':where()', ':has(> img)', ':has(+ p, ~ q)', ':has(a b)', ':has(.x > .y)', ':not()', ':is(a::before)', ':not(:is(.a, .b))', '::before', '::after',
  '::marker', '::first-letter', '::first-line', ':before', ':after', ':first-line', ':first-letter', '::selection', ':selection', '::placeholder', ':placeholder',
  ':backdrop', '::foo', '::highlight(x)', ':', '::', ':a(', 'svg|rect', '*|a', '|a', 'ns|*', 'a|', '&', '|', '$', '!',
];
const COMBS = [' ', ' ', ' > ', '>', ' + ', '+', ' ~ ', '~', '  ', ''];

const inputs = [];
for (let i = 0; i < 520; i++) {
  const lists = 1 + int(3);
  const parts = [];
  for (let l = 0; l < lists; l++) {
    const compounds = 1 + int(3);
    let sel = '';
    for (let c = 0; c < compounds; c++) {
      const simples = 1 + int(3);
      for (let s = 0; s < simples; s++) sel += pick(SIMPLE);
      if (c + 1 < compounds) sel += pick(COMBS);
    }
    if (int(12) === 0) sel = pick(COMBS) + sel;
    if (int(12) === 0) sel += pick(COMBS);
    parts.push(sel);
  }
  inputs.push(parts.join(pick([',', ', ', ' , '])));
}
const tmp = tmpdir();
const inPath = resolve(tmp, 'css_selector_inputs.json');
const outPath = resolve(tmp, 'css_selector_expected.json');
writeFileSync(inPath, JSON.stringify(inputs));
execFileSync(process.env.DART || 'dart', ['run', resolve(here, 'css_selector_reference.dart'), inPath, outPath], { stdio: 'inherit', shell: true });
const expected = JSON.parse(readFileSync(outPath, 'utf8'));

const canon = (v) => {
  const walk = (x) => {
    if (Array.isArray(x)) return x.map(walk);
    if (x && typeof x === 'object') { const o = {}; for (const k of Object.keys(x).sort()) o[k] = walk(x[k]); return o; }
    return x;
  };
  return JSON.stringify(walk(v));
};
const cases = inputs.map((src, i) => JSON.stringify({ src, e: canon(expected[i]) }));

const chunks = [];
const size = 15;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'css_selector_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/text_css_selector/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> text_css_selector`);
