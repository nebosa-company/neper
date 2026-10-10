// Vectors for `e.fmt.css.container` (L040): random container-query condition trees evaluated at several container sizes by
// Vaper's own Dart code (scripts/css_container_reference.dart) and written as the link fixture
// tests/selfhost/fixtures/link/text_css_container. Usage: DART=D:/flutter/bin/dart.bat node scripts/css_container_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

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

const tmp = tmpdir();
const inPath = resolve(tmp, 'css_container_inputs.json');
const outPath = resolve(tmp, 'css_container_expected.json');
writeFileSync(inPath, JSON.stringify(inputs));
execFileSync(process.env.DART || 'dart', ['run', resolve(here, 'css_container_reference.dart'), inPath, outPath], { stdio: 'inherit', shell: true });
const expected = JSON.parse(readFileSync(outPath, 'utf8'));
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
