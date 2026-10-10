// Vectors for `e.fmt.html.accessible` (L040): random HTML documents run through Vaper's own accessibility tree builder
// (scripts/html_accessible_reference.dart under `dart run --packages`) and written as the link fixture
// tests/selfhost/fixtures/link/html_accessible. See scripts/css_match_vectors.mjs for DART and DART_PACKAGES.
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x7a11;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

const IDS = ['a1', 'b2', 'c3', 'd4'];
const WORDS = ['Save', 'Cancel', 'Name', 'Hello world', 'x', 'Item one', ' spaced  out ', 'Title', 'Close', 'Search'];
const ROLES = ['button', 'link', 'heading', 'img', 'textbox', 'searchbox', 'checkbox', 'switch', 'radio', 'combobox', 'listbox', 'slider', 'progressbar', 'meter', 'list', 'listitem', 'table', 'grid', 'row', 'cell', 'gridcell', 'columnheader', 'rowheader', 'navigation', 'main', 'banner', 'contentinfo', 'complementary', 'form', 'search', 'region', 'article', 'dialog', 'alertdialog', 'separator', 'figure', 'group', 'radiogroup', 'presentation', 'none', 'bogus', 'bogus button', 'tab'];
function ariaAttrs() {
  const out = [];
  if (chance(0.12)) out.push(`role="${pick(ROLES)}"`);
  if (chance(0.1)) out.push(`aria-label="${pick(WORDS)}"`);
  if (chance(0.08)) out.push(`aria-labelledby="${pick(IDS)}${chance(0.4) ? ' ' + pick(IDS) : ''}"`);
  if (chance(0.06)) out.push(`aria-hidden="${pick(['true', 'false', 'TRUE'])}"`);
  if (chance(0.06)) out.push(`aria-disabled="${pick(['true', 'false'])}"`);
  if (chance(0.06)) out.push(`aria-checked="${pick(['true', 'false', 'mixed'])}"`);
  if (chance(0.06)) out.push(`aria-expanded="${pick(['true', 'false'])}"`);
  if (chance(0.05)) out.push(`aria-selected="${pick(['true', 'false'])}"`);
  if (chance(0.05)) out.push(`aria-required="${pick(['true', 'false'])}"`);
  if (chance(0.05)) out.push(`aria-invalid="${pick(['true', 'false', 'grammar'])}"`);
  if (chance(0.05)) out.push(`aria-level="${pick(['1', '3', '9', 'x'])}"`);
  if (chance(0.04)) out.push(`aria-valuenow="${pick(['5', '2.5'])}" aria-valuemin="0" aria-valuemax="10"`);
  if (chance(0.1)) out.push(`id="${pick(IDS)}"`);
  if (chance(0.08)) out.push(`title="${pick(WORDS)}"`);
  return out.length ? ' ' + out.join(' ') : '';
}
function inline(depth, inA = false) {
  const r = rnd();
  if (r < 0.3) return pick(WORDS);
  if (r < 0.34) return '<!-- c -->';
  if (depth > 2) return pick(WORDS);
  const tag = pick(inA ? ['span', 'b', 'em', 'span', 'label'] : ['span', 'b', 'em', 'a', 'a', 'span', 'label']);
  const href = tag === 'a' && chance(0.8) ? ` href="${pick(['/x', ' http://e.test/y ', '#f', ''])}"` : '';
  return `<${tag}${href}${ariaAttrs()}>${Array.from({ length: int(3) }, () => inline(depth + 1, inA || tag === 'a')).join('')}</${tag}>`;
}
function control() {
  const r = int(12);
  if (r === 0) return `<input type="${pick(['text', 'checkbox', 'radio', 'range', 'submit', 'reset', 'button', 'image', 'hidden', 'file', 'password'])}"${chance(0.5) ? ` value="${pick(['v', '5', 'Go'])}"` : ''}${chance(0.3) ? ' checked' : ''}${chance(0.3) ? ' disabled' : ''}${chance(0.3) ? ' required' : ''}${chance(0.3) ? ` placeholder="${pick(['ph', ''])}"` : ''}${chance(0.3) ? ` min="${pick(['1', '-5'])}" max="${pick(['20', '8'])}"` : ''}${chance(0.3) ? ` alt="${pick(WORDS)}"` : ''}${chance(0.3) ? ` id="${pick(IDS)}"` : ''}${ariaAttrs()}>`;
  if (r === 1) return `<textarea${ariaAttrs()}${chance(0.3) ? ` placeholder="ph"` : ''}>${pick(['', 'text', ' a  b '])}</textarea>`;
  if (r === 2) return `<select${chance(0.4) ? ' multiple' : ''}${ariaAttrs()}><option>a</option></select>`;
  if (r === 3) return `<progress${chance(0.6) ? ` value="${pick(['0.5', '3'])}"` : ''}${chance(0.5) ? ` max="${pick(['10', '1'])}"` : ''}></progress>`;
  if (r === 4) return `<meter value="${pick(['3', '0.4'])}"${chance(0.5) ? ' min="1"' : ''}${chance(0.5) ? ' max="9"' : ''}></meter>`;
  if (r === 5) return `<img src="a.png"${chance(0.6) ? ` alt="${pick(WORDS)}"` : ''}${ariaAttrs()}>`;
  if (r === 6) return `<label${chance(0.6) ? ` for="${pick(IDS)}"` : ''}>${inline(1)}</label>`;
  if (r === 7) return `<details${chance(0.5) ? ' open' : ''}><summary>${inline(1)}</summary>${inline(1)}</details>`;
  if (r === 8) return `<table${ariaAttrs()}>${chance(0.6) ? '<caption>Cap</caption>' : ''}<tbody><tr><th>H</th><td>${inline(2)}</td></tr></tbody></table>`;
  if (r === 9) return `<fieldset><legend>${pick(WORDS)}</legend>${inline(1)}</fieldset>`;
  if (r === 10) return `<figure>${inline(1)}<figcaption>${pick(WORDS)}</figcaption></figure>`;
  const t = pick(['h1', 'h2', 'h6', 'nav', 'main', 'header', 'footer', 'aside', 'form', 'section', 'article', 'dialog', 'div', 'ul', 'ol']);
  const heading = /^h\d$/.test(t);
  if (t === 'ul' || t === 'ol') return `<${t}${ariaAttrs()}><li>${inline(1)}</li></${t}>`;
  return `<${t}${ariaAttrs()}>${heading ? inline(1) : `${inline(1)}${chance(0.4) ? control() : ''}`}</${t}>`;
}
function block() {
  const r = rnd();
  if (r < 0.4) return control();
  const tag = pick(['div', 'section', 'p', 'nav', 'div', 'span']);
  const inlineOnly = tag === 'p' || tag === 'span';
  return `<${tag}${ariaAttrs()}>${Array.from({ length: 1 + int(3) }, () => (inlineOnly || chance(0.5) ? inline(1) : control())).join('')}</${tag}>`;
}
function doc() {
  const kids = Array.from({ length: 1 + int(4) }, () => block()).join('');
  return `<!doctype html><html><head><title>t</title></head><body${chance(0.05) ? ' aria-hidden="true"' : ''}>${kids}</body></html>`;
}

const inputs = Array.from({ length: 220 }, () => doc());
const tmp = tmpdir();
const inPath = resolve(tmp, 'html_accessible_inputs.json');
const outPath = resolve(tmp, 'html_accessible_expected.json');
writeFileSync(inPath, JSON.stringify(inputs));
const dartArgs = ['run', ...(process.env.DART_PACKAGES ? [`--packages=${process.env.DART_PACKAGES}`] : []), resolve(here, 'html_accessible_reference.dart'), inPath, outPath];
execFileSync(process.env.DART || 'dart', dartArgs, { stdio: 'inherit', shell: true });
const expected = JSON.parse(readFileSync(outPath, 'utf8'));
const canon = (v) => {
  const walk = (x) => {
    if (Array.isArray(x)) return x.map(walk);
    if (x && typeof x === 'object') { const o = {}; for (const k of Object.keys(x).sort()) o[k] = walk(x[k]); return o; }
    return x;
  };
  return JSON.stringify(walk(v));
};
const cases = inputs.map((html, i) => JSON.stringify({ html, e: canon(expected[i]) }));

const chunks = [];
const size = 8;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'html_accessible_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/html_accessible/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
const roles = {};
const count = (n) => { roles[n.r] = (roles[n.r] || 0) + 1; for (const k of n.k) count(k); };
for (const e of expected) if (e) count(e);
console.log(`${cases.length} cases in ${chunks.length} chunks -> html_accessible`, roles);
