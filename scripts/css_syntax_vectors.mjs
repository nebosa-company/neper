// Vectors for `e.fmt.css.syntax` (L038): random CSS built from well-formed and malformed fragments, run through Vaper's
// own tokenizer and grammar (scripts/css_syntax_reference.dart under `dart run`) and written as the link fixture
// tests/selfhost/fixtures/link/text_css_syntax. Usage: node scripts/css_syntax_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x3c55;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

const FRAGMENTS = [
  'a{color:red}', 'p , q > r{margin:0 auto!important;padding:1px 2.5em}', '@media (min-width:600px){a{b:c}}', '@import url(x.css);',
  '@font-face{src:url("a b.woff") format("woff")}', '/* c */', '/* unterminated', '<!--', '-->', '"str\\"esc"', "'x\ny'", "'ok'", 'url( a)',
  'url(a b)', 'url("q")', 'URL(x)', 'url(a"b)', 'url(a\\)b)', '#abc', '#123', '#-x', '#', '12px', '+.5', '-.5e3', '1e+2', '1E-2', '5%', '.5em', '1.',
  '--custom: {a:b}', '\\41 bc', '\\', '\\\n', 'é', 'ünï{x:y}', '日本', '!important', '! important', '@', '@-x', '@media', 'a(b[c]{d})', '{', '}', ')', ']', ';',
  ',', ':', 'a:b', 'width:calc(1px + 2px)', 'color: #fff !important;', 'font: 12px/1.5 "A B", serif', 'x\u0000y', '\r\n', '\f', '\t', ' ', '  ',
  '.cls#id[attr="v"]:hover::before', '+', '-', '--', '-a', '-1', '+-1', '.', '..', '<', '<!-', 'u+0025-00ff', '1e', '1ex', '1e3x', '0.0001', '1000000',
  '\\000041', '\\10FFFF', '\\110000', '\\D800', 'a\\ b', '"\\0041"', '"\\\n"', '"a\\', 'f(', 'f( )', 'f(a,b)', 'a{b:c;d:e}', 'a{b:c;;d}', 'a{;}', 'a{b}', 'a{:c}', 'a{b:}',
  'a{b:c!important}', 'a{b:c ! IMPORTANT}', 'a{b:{c:d}}', 'a{b:(c;d)}', '@x{', '@x(', '@x[;]', '@x a;b{', 'p{', 'b', 'x y z',
];

const inputs = [];
for (let i = 0; i < 420; i++) {
  const n = 1 + int(10);
  let s = '';
  for (let k = 0; k < n; k++) s += pick(FRAGMENTS) + (int(3) === 0 ? ' ' : '');
  inputs.push(s);
}
const tmp = tmpdir();
const inPath = resolve(tmp, 'css_syntax_inputs.json');
const outPath = resolve(tmp, 'css_syntax_expected.json');
writeFileSync(inPath, JSON.stringify(inputs));
execFileSync(process.env.DART || 'dart', ['run', resolve(here, 'css_syntax_reference.dart'), inPath, outPath], { stdio: 'inherit', shell: true });
const expected = JSON.parse(readFileSync(outPath, 'utf8'));

const canon = (v) => {
  const walk = (x) => {
    if (Array.isArray(x)) return x.map(walk);
    if (x && typeof x === 'object') { const o = {}; for (const k of Object.keys(x).sort()) o[k] = walk(x[k]); return o; }
    return x;
  };
  return JSON.stringify(walk(v));
};
// numeric values arrive as Dart's text; as JSON numbers the comparison is by value
const fix = (x) => {
  if (Array.isArray(x)) return x.map(fix);
  if (x && typeof x === 'object') {
    const o = {};
    for (const k of Object.keys(x)) o[k] = k === 'nv' && typeof x[k] === 'string' ? Number(x[k]) : fix(x[k]);
    return o;
  }
  return x;
};
const cases = inputs.map((src, i) => JSON.stringify({ src, e: canon(fix(expected[i])) }));

const chunks = [];
const size = 12;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'css_syntax_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/text_css_syntax/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> text_css_syntax`);
