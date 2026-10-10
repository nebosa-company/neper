// Vectors for `e.fmt.css.match` (L040): random HTML documents and selector lists, matched by Vaper's own selector
// matcher (scripts/css_match_reference.dart under `dart run --packages`) and written as the link fixture
// tests/selfhost/fixtures/link/text_css_match. DART defaults to `dart`; DART_PACKAGES must name a package_config.json
// that maps html, csslib, source_span, meta, path, string_scanner, term_glyph, collection, typed_data and the Vaper
// packages (vaper_protocol, vaper_css_values, vaper_engine_core).
// Usage: DART=D:/flutter/bin/dart.bat DART_PACKAGES=D:/temp/flowp/pkg/package_config.json node scripts/css_match_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x4d17;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

const BLOCK = ['div', 'section', 'ul', 'p', 'nav', 'form', 'span', 'a', 'button', 'label', 'li', 'h1', 'h2', 'b', 'em'];
const CLASSES = ['a', 'b', 'c', 'item', 'on'];
const IDS = ['x', 'y', 'main', 'z'];
function attrs(tag) {
  const out = [];
  if (chance(0.4)) out.push(`class="${[...new Set(Array.from({ length: 1 + int(2) }, () => pick(CLASSES)))].join(' ')}"`);
  if (chance(0.2)) out.push(`id="${pick(IDS)}"`);
  if (chance(0.15)) out.push(`data-k="${pick(['a b', 'a-b', 'abc', 'A', 'x'])}"`);
  if (chance(0.12)) out.push('disabled');
  if (chance(0.12)) out.push('checked');
  if (chance(0.12)) out.push('required');
  if (chance(0.1)) out.push('readonly');
  if (chance(0.1)) out.push(`title="${pick(['t', 'hello'])}"`);
  if (tag === 'a' && chance(0.7)) out.push(`href="${pick(['/x', 'http://e.test/', '#f'])}"`);
  if (chance(0.05)) out.push('contenteditable="true"');
  return out.length ? ' ' + out.join(' ') : '';
}
function inputTag() {
  const type = pick(['text', 'number', 'range', 'email', 'url', 'checkbox', 'radio', 'submit', 'hidden', 'text']);
  const a = [`type="${type}"`];
  if (chance(0.5)) a.push(`value="${pick(['', 'abc', '5', '12', '-3', 'a@b.co', 'a@b', 'http://x.y', 'x', '123', 'ab'])}"`);
  if (chance(0.3)) a.push(`min="${pick(['0', '3', '10'])}"`);
  if (chance(0.3)) a.push(`max="${pick(['5', '10', '100'])}"`);
  if (chance(0.2)) a.push(`pattern="${pick(['[a-z]+', '\\d{3}', 'ab|cd', '[0-9]*'])}"`);
  if (chance(0.15)) a.push(`maxlength="${pick(['2', '5'])}"`);
  if (chance(0.15)) a.push(`minlength="${pick(['2', '4'])}"`);
  if (chance(0.3)) a.push(`placeholder="${pick(['p', ''])}"`);
  if (chance(0.15)) a.push('required');
  if (chance(0.1)) a.push('disabled');
  if (chance(0.1)) a.push('readonly');
  if (chance(0.1)) a.push('checked');
  return `<input ${a.join(' ')}>`;
}
function node(depth) {
  const r = rnd();
  if (r < 0.12) return pick(['text', ' ', 'a b', 'Hello', '\n']);
  if (r < 0.15) return '<!-- c -->';
  if (r < 0.28) return inputTag();
  if (r < 0.32) return `<select${chance(0.3) ? ' multiple' : ''}${attrs('select')}><option${chance(0.3) ? ' selected' : ''}>o</option></select>`;
  if (r < 0.35) return `<textarea${attrs('textarea')}>${pick(['', 'x'])}</textarea>`;
  if (r < 0.38) return `<img src="a.png"${attrs('img')}>`;
  if (depth >= 3) return pick(['x', '<span>y</span>']);
  const tag = pick(BLOCK);
  const kids = Array.from({ length: int(4) }, () => node(depth + 1)).join('');
  return `<${tag}${attrs(tag)}>${kids}</${tag}>`;
}
function doc() {
  const kids = Array.from({ length: 1 + int(4) }, () => node(0)).join('');
  return `<!doctype html><html><head></head><body>${kids}</body></html>`;
}

const TAGS = ['div', 'span', 'p', 'a', 'li', 'ul', 'input', 'label', 'section', 'h1', 'b', 'button', 'select', 'textarea', 'img', 'body', 'html'];
function simple() {
  return pick([
    pick(TAGS), pick(TAGS).toUpperCase(), '*', `.${pick(CLASSES)}`, `#${pick(IDS)}`, `[class]`, '[data-k]', `[data-k="${pick(['a b', 'a-b', 'abc', 'A'])}"]`, `[data-k="${pick(['a', 'ab'])}" i]`,
    '[data-k~=a]', '[data-k|=a]', '[data-k^=a]', '[data-k$=c]', '[data-k*=b]', '[type=checkbox]', '[type="text"]', '[href]',
    ':first-child', ':last-child', ':only-child', ':first-of-type', ':last-of-type', ':only-of-type', ':empty', ':root', ':nth-child(2)', ':nth-child(odd)', ':nth-child(even)',
    ':nth-child(2n+1)', ':nth-child(-n+3)', ':nth-child(n+2)', ':nth-child(3n)', ':nth-last-child(2)', ':nth-of-type(2)', ':nth-last-of-type(odd)', ':nth-child(2n + 1 of .a)',
    ':nth-child(1 of .b, .c)', ':nth-child(0n+2)', ':nth-child(+n)',
    ':not(.a)', ':not(.a, #x)', ':not(:first-child)', ':is(a, b)', ':where(.a, .b)', ':not()', ':is()', ':matches(div)', ':has(> span)', ':has(.a)', ':has(+ p)', ':has(~ li)', ':has(a b)', ':has(> p .a)',
    ':hover', ':focus', ':focus-visible', ':focus-within', ':active', ':disabled', ':enabled', ':checked', ':required', ':optional', ':read-only', ':read-write', ':placeholder-shown',
    ':in-range', ':out-of-range', ':default', ':valid', ':invalid', ':link', ':any-link', ':visited', ':target', ':scope', '::before',
  ]);
}
function selector() {
  const comps = [];
  const n = 1 + int(3);
  for (let i = 0; i < n; i++) {
    let c = '';
    const k = 1 + int(2);
    for (let j = 0; j < k; j++) c += simple();
    comps.push(c);
  }
  let s = comps[0];
  for (let i = 1; i < comps.length; i++) s += pick([' ', ' > ', ' + ', ' ~ ']) + comps[i];
  return chance(0.3) ? `${s}, ${simple()}` : s;
}

const inputs = [];
for (let i = 0; i < 140; i++) {
  const html = doc();
  const base = { html };
  const sels = Array.from({ length: 4 }, () => selector());
  const state = chance(0.5) ? { ...(chance(0.7) ? { hover: int(50) } : {}), ...(chance(0.7) ? { focus: int(50) } : {}), ...(chance(0.5) ? { active: int(50) } : {}), ...(chance(0.5) ? { focusWithin: [int(50), int(50)] } : {}) } : undefined;
  for (const s of sels) inputs.push({ ...base, selector: s, ...(state ? { state } : {}) });
}
const tmp = tmpdir();
const inPath = resolve(tmp, 'css_match_inputs.json');
const outPath = resolve(tmp, 'css_match_expected.json');
writeFileSync(inPath, JSON.stringify(inputs));
const dartArgs = ['run', ...(process.env.DART_PACKAGES ? [`--packages=${process.env.DART_PACKAGES}`] : []), resolve(here, 'css_match_reference.dart'), inPath, outPath];
execFileSync(process.env.DART || 'dart', dartArgs, { stdio: 'inherit', shell: true });
const expected = JSON.parse(readFileSync(outPath, 'utf8'));
const cases = inputs.map((inp, i) => JSON.stringify({ ...inp, e: expected[i] }));

const chunks = [];
const size = 10;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'css_match_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/text_css_match/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
let ones = 0; let total = 0;
for (const e of expected) for (const r of e.r) { total += r.length; ones += (r.match(/1/g) || []).length; }
console.log(`${cases.length} cases in ${chunks.length} chunks -> text_css_match; ${ones}/${total} positive matches`);
