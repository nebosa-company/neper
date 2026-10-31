// Vectors for `e.fmt.css.container` (L040): random container-query condition trees evaluated at several container sizes
// by the documented container-query contract and written as the link fixture tests/selfhost/fixtures/link/text_css_container.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x2ec9;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

function cond(depth) {
  const r = int(10);
  if (depth >= 3 || r < 4) {
    if (int(8) === 0) return { t: 'unknown' };
    const f = pick(['width', 'height', 'aspectRatio', 'orientationPortrait', 'orientationLandscape']);
    return { t: 'feat', f, o: pick(['lt', 'le', 'gt', 'ge', 'eq']), v: f === 'aspectRatio' ? pick([0, 0.5, 1, 1.5, 2, 1.333]) : pick([0, 100, 320.25, 400, 600, 799.7, 800]) };
  }
  if (r < 6) return { t: 'and', p: Array.from({ length: 1 + int(3) }, () => cond(depth + 1)) };
  if (r < 8) return { t: 'or', p: Array.from({ length: 1 + int(3) }, () => cond(depth + 1)) };
  return { t: 'not', p: cond(depth + 1) };
}
const SIZES = [{ w: 800, h: 600 }, { w: 320, h: 480 }, { w: 400 }, { h: 300 }, {}, { w: 600, h: 0 }, { w: 799.9, h: 400 }, { w: 600.3, h: 600 }, { w: 0, h: 0 }, { w: 1000, h: 1000 }];
const inputs = Array.from({ length: 400 }, () => ({ c: cond(0), sizes: SIZES }));

function evaluate(c, width, height) {
  if (c.t === 'and') {
    let unknown = false;
    for (const part of c.p) {
      const value = evaluate(part, width, height);
      if (value === false) return false;
      if (value === null) unknown = true;
    }
    return unknown ? null : true;
  }
  if (c.t === 'or') {
    let unknown = false;
    for (const part of c.p) {
      const value = evaluate(part, width, height);
      if (value === true) return true;
      if (value === null) unknown = true;
    }
    return unknown ? null : false;
  }
  if (c.t === 'not') {
    const value = evaluate(c.p, width, height);
    return value === null ? null : !value;
  }
  if (c.t === 'unknown') return null;
  let actual;
  if (c.f === 'width') actual = width;
  else if (c.f === 'height') actual = height;
  else if (c.f === 'aspectRatio') {
    if (width === undefined || height === undefined || height <= 0) return null;
    actual = width / height;
  } else if (c.f === 'orientationPortrait') {
    if (width === undefined || height === undefined) return null;
    return height >= width;
  } else {
    if (width === undefined || height === undefined) return null;
    return width > height;
  }
  if (actual === undefined) return null;
  if (c.o === 'lt') return actual < c.v;
  if (c.o === 'le') return actual <= c.v;
  if (c.o === 'gt') return actual > c.v;
  if (c.o === 'ge') return actual >= c.v;
  if (c.f === 'aspectRatio') {
    if (c.v === 0) return actual === 0;
    return Math.abs(actual / c.v - 1) < 0.001;
  }
  return Math.abs(actual - c.v) < 0.5;
}

function usesBlockAxis(c) {
  if (c.t === 'and' || c.t === 'or') return c.p.some(usesBlockAxis);
  if (c.t === 'not') return usesBlockAxis(c.p);
  return c.t === 'feat' && c.f !== 'width';
}

const expected = inputs.map(({ c, sizes }) => ({
  e: sizes.map((s) => evaluate(c, s.w, s.h)),
  block: usesBlockAxis(c),
}));
const cases = inputs.map((inp, i) => JSON.stringify({ c: inp.c, sizes: inp.sizes, e: expected[i] }));

const chunks = [];
const size = 20;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'css_container_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/text_css_container/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
let t = 0, f = 0, n = 0;
for (const e of expected) for (const v of e.e) { if (v === true) t++; else if (v === false) f++; else n++; }
console.log(`${cases.length} cases in ${chunks.length} chunks -> text_css_container; true ${t}, false ${f}, unknown ${n}`);
