// Vectors for `e.ui.interpolate` (L039): random interpolation operations run through Vaper's own Dart kernels
// (scripts/ui_interpolate_reference.dart) and written as the link fixture tests/selfhost/fixtures/link/ui_interpolate.
// The fixture compares numbers within 1e-9 (the libm of the two sides need not agree to the last bit).
// Usage: DART=D:/flutter/bin/dart.bat node scripts/ui_interpolate_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x1a7e;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const num = (lo, hi) => Math.round((lo + rnd() * (hi - lo)) * 1000) / 1000;
const T = () => pick([0, 1, -0.5, 1.5, num(0, 1), num(0, 1), num(0, 1), 0.25, 0.5]);
const argb = () => (int(256) << 24 | int(256) << 16 | int(256) << 8 | int(256)) >>> 0;
const matrix = () => pick([[1, 0, 0, 1, num(-50, 50), num(-50, 50)], [num(-2, 2), num(-2, 2), num(-2, 2), num(-2, 2), num(-20, 20), num(-20, 20)], (() => { const a = num(-3.1, 3.1); const s = num(0.2, 3); return [Math.cos(a) * s, Math.sin(a) * s, -Math.sin(a) * s, Math.cos(a) * s, num(-9, 9), num(-9, 9)]; })(), [0, 0, 0, 0, 1, 2], [-1, 0, 0, 1, 0, 0]]);

const ops = [];
for (let i = 0; i < 400; i++) {
  const r = int(5);
  if (r === 0) ops.push({ op: 'lerp', a: num(-100, 100), b: num(-100, 100), t: T() });
  else if (r === 1) ops.push({ op: 'color', a: argb(), b: argb(), t: T() });
  else if (r === 2) ops.push({ op: 'bezier', x1: num(0, 1), y1: num(-1, 2), x2: num(0, 1), y2: num(-1, 2), t: T() });
  else if (r === 3) ops.push({ op: 'affine', a: matrix(), b: matrix(), t: T() });
  else ops.push({ op: 'decompose', m: matrix() });
}
const tmp = tmpdir();
const inPath = resolve(tmp, 'ui_interpolate_inputs.json');
const outPath = resolve(tmp, 'ui_interpolate_expected.json');
writeFileSync(inPath, JSON.stringify(ops));
execFileSync(process.env.DART || 'dart', ['run', resolve(here, 'ui_interpolate_reference.dart'), inPath, outPath], { stdio: 'inherit', shell: true });
const expected = JSON.parse(readFileSync(outPath, 'utf8'));
const cases = ops.map((op, i) => JSON.stringify({ ...op, e: expected[i] }));

const chunks = [];
const size = 25;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'ui_interpolate_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/ui_interpolate/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> ui_interpolate`);
