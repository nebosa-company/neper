// Vectors for `e.fmt.css.cascade` (L040): random documents, user-agent and author rule sets (selectors, declarations with
// !important, source order with ties, layer priorities, @container queries over a container stack, @scope donuts) and
// inline styles, resolved by Vaper's own StyleResolver cascade, presentational hints and rule index
// (scripts/css_cascade_reference.dart) and written as the link fixture tests/selfhost/fixtures/link/text_css_cascade.
// The script copies Vaper's css library to a temporary package, `vaper_css_copy`, renaming the resolver's private
// `_cascade`, `_presentationalHints`, `_candidates` and `_RuleIndex` (and nothing else) so the reference can call them.
// DART_PACKAGES must name a package_config.json that maps html, csslib, source_span, meta, path, string_scanner,
// term_glyph, collection, typed_data and the Vaper packages (vaper_protocol, vaper_css_values).
// Usage: DART=D:/flutter/bin/dart.bat DART_PACKAGES=<package_config.json> node scripts/css_cascade_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, readdirSync, copyFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
const VAPER_CSS = process.env.VAPER_CSS || 'D:/repos/vaper/packages/vaper_engine_core/lib/src/css';
let seed = 0x51ca;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

const CLASSES = ['a', 'b', 'c', 'item'];
const IDS = ['x', 'y', 'main'];
const PROPS = ['color', 'background', 'background-color', 'background-image', 'font', 'font-size', 'font-family', 'text-decoration', 'text-decoration-line', 'width', 'height', 'float', 'text-align', 'vertical-align', 'border', 'padding', 'white-space', 'z-index', 'direction', 'margin-left', 'list-style-type', 'display'];
let vn = 0;
const value = () => `v${++vn}`;

function attrs(tag) {
  const out = [];
  if (chance(0.45)) out.push(`class="${Array.from({ length: 1 + int(3) }, () => pick(CLASSES)).join(' ')}"`);
  if (chance(0.2)) out.push(`id="${pick(IDS)}"`);
  if (chance(0.15)) out.push('data-k="a"');
  if (tag === 'a' && chance(0.7)) out.push('href="/p"');
  if (chance(0.25)) {
    const n = 1 + int(3);
    const ds = [];
    for (let i = 0; i < n; i++) {
      const p = pick(PROPS);
      const name = chance(0.15) ? p.toUpperCase() : p;
      ds.push(`${name}${chance(0.2) ? ' :' : ':'} ${value()}${chance(0.15) ? ' !important' : ''}`);
    }
    if (chance(0.15)) ds.push('--Custom: ' + value());
    if (chance(0.1)) ds.push('color:');
    out.push(`style="${ds.join('; ')}"`);
  }
  if (chance(0.2)) out.push(`dir="${pick(['rtl', 'LTR', 'auto'])}"`);
  const len = () => pick(['120', '33.5', '7%', 'abc', '50 ', '0', '1e2', ' 10']);
  if (['table', 'td', 'th', 'img', 'col', 'hr'].includes(tag)) {
    if (chance(0.5)) out.push(`width="${len()}"`);
    if (chance(0.4)) out.push(`height="${len()}"`);
  }
  if (['body', 'table', 'tr', 'td', 'th'].includes(tag) && chance(0.4)) out.push(`bgcolor="${pick(['red', '#fff', ''])}"`);
  if (['body', 'font'].includes(tag)) {
    if (chance(0.4)) out.push(`color="${pick(['blue', 'green'])}"`);
    if (chance(0.3)) out.push(`text="${pick(['navy', 'teal'])}"`);
  }
  if (tag === 'font') {
    if (chance(0.5)) out.push(`size="${pick(['1', '4', '+2', '-1', '9', '-9', 'x', '3'])}"`);
    if (chance(0.4)) out.push(`face="${pick(['Arial', 'serif'])}"`);
  }
  if (tag === 'hr' && chance(0.5)) out.push(`size="${pick(['2', '5', '10%'])}"`);
  if (tag === 'img') {
    if (chance(0.5)) out.push(`border="${pick(['0', '2', '1', 'x', '-1'])}"`);
    if (chance(0.5)) out.push(`align="${pick(['left', 'RIGHT', 'top', 'middle', 'absbottom', 'center', 'texttop'])}"`);
  }
  if (['td', 'th'].includes(tag) && chance(0.4)) out.push('nowrap');
  if (['td', 'th', 'tr'].includes(tag) && chance(0.4)) out.push(`valign="${pick(['top', 'MIDDLE', 'bottom', 'baseline'])}"`);
  if (['td', 'th', 'tr', 'p', 'div', 'caption', 'col'].includes(tag) && chance(0.5)) out.push(`align="${pick(['left', 'center', 'RIGHT', 'justify', 'x'])}"`);
  if (tag === 'table') {
    if (chance(0.5)) out.push(`align="${pick(['center', 'left', 'right', 'x'])}"`);
    if (chance(0.5)) out.push(`border="${pick(['0', '1', '3', '', 'z'])}"`);
    if (chance(0.5)) out.push(`cellpadding="${pick(['0', '4', 'q', '-2'])}"`);
  }
  if (['ol', 'li'].includes(tag) && chance(0.5)) out.push(`type="${pick(['1', 'a', 'A', 'i', 'I', 'z'])}"`);
  return out.length ? ' ' + out.join(' ') : '';
}

const BLOCK = ['div', 'section', 'ul', 'ol', 'table', 'hr'];
const PHRASING = ['span', 'b', 'em', 'font', 'a', 'img'];
// `phrasing` content (inside p, a, span, ...) holds only phrasing elements, so the two HTML parsers build one tree.
function node(depth, phrasing, inCell) {
  const r = int(12);
  if (depth >= 4 || r < 2) return chance(0.5) ? 'text' : '';
  if (!phrasing && !inCell && r === 2) return `<table${attrs('table')}><tbody>${Array.from({ length: 1 + int(2) }, () => `<tr${attrs('tr')}>${Array.from({ length: 1 + int(3) }, () => { const c = pick(['td', 'th']); return `<${c}${attrs(c)}>${chance(0.5) ? node(depth + 2, false, true) : 'c'}</${c}>`; }).join('')}</tr>`).join('')}</tbody></table>`;
  if (!phrasing && r === 3) { const l = pick(['ul', 'ol']); return `<${l}${attrs(l)}>${Array.from({ length: 1 + int(3) }, () => `<li${attrs('li')}>${node(depth + 1, true, inCell)}</li>`).join('')}</${l}>`; }
  if (!phrasing && r === 4) return `<p${attrs('p')}>${Array.from({ length: int(3) }, () => node(depth + 1, true, inCell)).join('')}</p>`;
  if (!phrasing && r < 7) { const d = pick(['div', 'section']); return `<${d}${attrs(d)}>${Array.from({ length: int(3) }, () => node(depth + 1, false, inCell)).join('')}</${d}>`; }
  if (!phrasing && r === 7) return `<hr${attrs('hr')}>`;
  const tag = pick(PHRASING);
  if (tag === 'img') return `<img${attrs('img')}>`;
  if (tag === 'a') return `<a${attrs('a')}>${chance(0.5) ? 'text' : ''}</a>`;
  return `<${tag}${attrs(tag)}>${Array.from({ length: int(3) }, () => node(depth + 1, true, inCell)).join('')}</${tag}>`;
}function doc() {
  const bodyAttrs = attrs('body') + (chance(0.3) ? ` link="${pick(['red', 'purple'])}"` : '');
  const kids = Array.from({ length: 1 + int(4) }, () => node(0, false, false)).join('');
  return `<!DOCTYPE html><html${chance(0.2) ? attrs('html') : ''}><head><title>t</title></head><body${bodyAttrs}>${kids}</body></html>`;
}

function simple() {
  switch (int(14)) {
    case 0: return pick(['div', 'p', 'span', 'a', 'ul', 'li', 'td', 'th', 'tr', 'table', 'body', 'html', 'img', 'font', 'b']);
    case 1: case 2: return '.' + pick(CLASSES);
    case 3: return '#' + pick(IDS);
    case 4: return '*';
    case 5: return '[data-k]';
    case 6: return pick([':first-child', ':last-child', ':nth-child(2)', ':nth-child(odd)', ':only-child', ':empty']);
    case 7: return ':not(.' + pick(CLASSES) + ')';
    case 8: return ':is(.a, #x)';
    case 9: return ':where(div, p)';
    case 10: return 'a[href]';
    case 11: return 'li.' + pick(CLASSES);
    case 12: return ':scope';
    default: return '.' + pick(CLASSES) + '.' + pick(CLASSES);
  }
}
function selector() {
  let s = simple();
  const n = int(3);
  for (let i = 0; i < n; i++) s = s + pick([' ', ' > ', ' + ', ' ~ ']) + simple();
  return s;
}
function scopedSelector() {
  return chance(0.3) ? ':scope > ' + simple() : selector();
}

function condTree(depth) {
  const r = int(10);
  if (depth >= 2 || r < 5) {
    if (int(10) === 0) return { t: 'unknown' };
    const f = pick(['width', 'height', 'aspectRatio', 'orientationPortrait', 'orientationLandscape']);
    return { t: 'feat', f, o: pick(['lt', 'le', 'gt', 'ge', 'eq']), v: f === 'aspectRatio' ? pick([0.5, 1, 1.5, 2]) : pick([0, 100, 320, 400, 600, 800]) };
  }
  if (r < 7) return { t: 'and', p: Array.from({ length: 1 + int(2) }, () => condTree(depth + 1)) };
  if (r < 9) return { t: 'or', p: Array.from({ length: 1 + int(2) }, () => condTree(depth + 1)) };
  return { t: 'not', p: condTree(depth + 1) };
}

function makeRules(count, withExtras, srcStart) {
  const rules = [];
  let src = srcStart;
  for (let i = 0; i < count; i++) {
    const scoped = withExtras && chance(0.25);
    const d = Array.from({ length: 1 + int(3) }, () => [pick(PROPS), value(), chance(0.12)]);
    if (!chance(0.3)) src += 1 + int(2);
    const r = { sel: scoped ? scopedSelector() : selector(), d, src, layer: withExtras && chance(0.3) ? int(4) : null, cont: [], sc: [] };
    if (withExtras && chance(0.3)) {
      r.cont = Array.from({ length: 1 + int(2) }, () => ({ n: chance(0.5) ? pick(['card', 'side']) : null, c: condTree(0) }));
    }
    if (scoped) {
      r.sc = Array.from({ length: 1 + int(chance(0.2) ? 2 : 1) }, () => ({
        s: chance(0.15) ? [] : Array.from({ length: 1 + int(2) }, () => pick(['.a', '#x', 'div', 'ul', 'section', '.item'])),
        l: chance(0.5) ? [] : Array.from({ length: 1 + int(2) }, () => pick(['.b', 'p', 'li', ':scope > p', 'span'])),
      }));
    }
    rules.push(r);
  }
  return rules;
}

const inputs = [];
for (let i = 0; i < 90; i++) {
  const stack = Array.from({ length: int(4) }, () => {
    const o = { k: pick(['size', 'inline']), n: chance(0.5) ? [pick(['card', 'side'])] : [], w: chance(0.9) ? pick([200, 400, 600, 1000]) : null, h: chance(0.7) ? pick([100, 300, 700]) : null };
    return o;
  });
  inputs.push({ html: doc(), ua: makeRules(int(6), false, 0), author: makeRules(3 + int(10), true, 0), stack });
}

// Focused cases: a nest of classed elements and rules of equal specificity over two properties, so layer order, scope
// proximity (nearest root, unscoped last) and source ties decide most winners.
function nest(depth) {
  if (depth === 0) return chance(0.5) ? 'x' : '';
  const tag = pick(['div', 'section']);
  const cls = Array.from({ length: 1 + int(2) }, () => pick(['a', 'b'])).join(' ');
  return `<${tag} class="${cls}">${nest(depth - 1)}${chance(0.3) ? `<${pick(['div', 'section'])} class="${pick(['a', 'b'])}">${nest(depth - 2 < 0 ? 0 : depth - 2)}</${'div'}>`.replace(/<section([^>]*)>(.*)<\/div>$/s, '') : ''}</${tag}>`;
}
for (let i = 0; i < 40; i++) {
  const rules = [];
  const n = 4 + int(6);
  for (let r = 0; r < n; r++) {
    const scoped = chance(0.6);
    const d = [[pick(['color', 'width']), value(), chance(0.05)]];
    const o = { sel: pick(['.a', '.b', 'div', 'section', '.a', '.b']), d, src: int(4), layer: chance(0.5) ? int(3) : null, cont: [], sc: [] };
    if (scoped) o.sc = Array.from({ length: 1 + int(chance(0.25) ? 2 : 1) }, () => ({ s: chance(0.1) ? [] : [pick(['.a', '.b', 'div', 'section'])], l: chance(0.3) ? [pick(['.a', '.b', 'section'])] : [] }));
    rules.push(o);
  }
  inputs.push({ html: `<!DOCTYPE html><html><head><title>t</title></head><body>${nest(3 + int(3))}</body></html>`, ua: [], author: rules, stack: [] });
}
const tmp = resolve(tmpdir(), 'css_cascade_work');
const copyLib = resolve(tmp, 'vaper_css_copy', 'lib', 'css');
mkdirSync(copyLib, { recursive: true });
for (const f of readdirSync(VAPER_CSS)) {
  if (!f.endsWith('.dart')) continue;
  let text = readFileSync(resolve(VAPER_CSS, f), 'utf8');
  if (f === 'style_resolver.dart') {
    text = text.replace(/\b_cascade\(/g, 'cascadeForTest(').replace(/\b_presentationalHints\(/g, 'presentationalHintsForTest(').replace(/\b_candidates\(/g, 'candidatesForTest(').replace(/\b_RuleIndex\b/g, 'RuleIndex');
  }
  writeFileSync(resolve(copyLib, f), text, 'utf8');
}
const base = JSON.parse(readFileSync(process.env.DART_PACKAGES, 'utf8'));
base.packages = base.packages.filter((p) => p.name !== 'vaper_css_copy' && p.name !== 'vaper_engine_core');
base.packages.push({ name: 'vaper_css_copy', rootUri: pathToFileURL(resolve(tmp, 'vaper_css_copy')).href, packageUri: 'lib/', languageVersion: '3.9' });
const config = resolve(tmp, 'package_config.json');
writeFileSync(config, JSON.stringify(base));
const inPath = resolve(tmp, 'inputs.json');
const outPath = resolve(tmp, 'expected.json');
writeFileSync(inPath, JSON.stringify(inputs));
execFileSync(process.env.DART || 'dart', ['run', `--packages=${config}`, resolve(here, 'css_cascade_reference.dart'), inPath, outPath], { stdio: 'inherit', shell: true });
const expected = JSON.parse(readFileSync(outPath, 'utf8'));
const cases = inputs.map((inp, i) => JSON.stringify({ ...inp, e: expected[i] }));

const chunks = [];
const size = 5;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'css_cascade_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/text_css_cascade/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
let elements = 0; let winners = 0; let hints = 0;
for (const c of expected) for (const e of c) { elements += 1; winners += Object.keys(e.w).length; hints += e.h.length; }
console.log(`${cases.length} cases in ${chunks.length} chunks -> text_css_cascade; ${elements} elements, ${winners} winning declarations, ${hints} hints`);
