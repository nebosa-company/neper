// Vectors for `e.gfx.cssvalue` (L039): random CSS values (lengths, calc, numbers, angles, times, colours in every
// syntax, transforms) run through Vaper's own Dart parsers (scripts/css_values_reference.dart under `dart run`) and
// written as the link fixture tests/selfhost/fixtures/link/gfx_cssvalue. The fixture compares numbers within 1e-9
// relative and colours exactly. Usage: DART=D:/flutter/bin/dart.bat node scripts/css_values_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x6c0a;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;
const num = () => pick(['0', '1', '2', '10', '16', '100', '1.5', '.5', '-2', '+3', '0.25', '12.75', '-0.5', '33.333', '360', '255', '5.']);
const unit = () => pick(['px', 'px', 'pt', 'em', 'rem', 'ex', 'ch', '%', 'vw', 'vh', 'vmin', 'vmax', 'cm', 'mm', 'in', 'q', 'pc', 'dvh', 'svw', 'vi', '']);
const len = () => num() + unit();
const upper = (s) => (chance(0.1) ? s.toUpperCase() : s);

function genLength(depth = 0) {
  const r = int(14);
  if (r < 5 || depth > 1) return len();
  if (r === 5) return `calc(${len()} ${pick(['+', '-'])} ${len()})`;
  if (r === 6) return `calc(${len()} * ${num()})`;
  if (r === 7) return `calc(${num()} * ${len()})`;
  if (r === 8) return `calc(${len()} / ${pick(['2', '4', '0', '2.5'])})`;
  if (r === 9) return `${pick(['min', 'max'])}(${genLength(depth + 1)}, ${genLength(depth + 1)})`;
  if (r === 10) return `clamp(${genLength(depth + 1)}, ${genLength(depth + 1)}, ${genLength(depth + 1)})`;
  if (r === 11) return pick([`abs(${len()})`, `hypot(${len()}, ${len()})`, `mod(${len()}, ${len()})`, `rem(${len()}, ${len()})`]);
  if (r === 12) return `round(${pick(['', 'nearest, ', 'up, ', 'down, ', 'to-zero, '])}${len()}, ${len()})`;
  return `calc(${len()} ${pick(['+', '-'])} ${genLength(depth + 1)} ${pick(['+', '-'])} ${num()}px)`;
}

const colorWord = () => pick(['red', 'blue', 'white', 'black', 'rebeccapurple', 'steelblue', 'transparent', 'currentcolor', 'tomato', 'nosuchcolor', '#fff', '#112233', '#12345678', '#abcd', '#abc', '#12345', 'Gold']);
function genColor(depth = 0) {
  const r = int(26);
  const alpha = pick(['', ' / 0.5', ' / 50%', ' / 1', ' / none', ', 0.3', '']);
  if (r < 4) return upper(colorWord());
  if (r === 4) return `rgb(${int(300)}, ${int(256)}, ${int(256)}${chance(0.3) ? `, ${pick(['0.5', '50%', '1', '0'])}` : ''})`;
  if (r === 5) return `rgb(${pick(['10%', '50%', '100%', '120%'])} ${int(256)} ${pick(['0', '75%'])}${pick(['', ' / 0.4', ' / 20%'])})`;
  if (r === 6) return `rgba(${int(256)},${int(256)},${int(256)},${pick(['.5', '0.25', '1'])})`;
  if (r === 7) return `hsl(${pick(['0', '120', '240', '-30', '400', '0.5turn', '1.5rad', '90deg', '100grad'])}, ${pick(['50%', '100%', '0%', '25'])}, ${pick(['50%', '25%', '75%', '100%'])}${chance(0.3) ? `, ${pick(['0.5', '50%'])}` : ''})`;
  if (r === 8) return `hsl(${pick(['0', '200', '350'])} ${pick(['50%', '80%'])} ${pick(['40%', '60%'])}${pick(['', ' / 0.5', ' / 30%'])})`;
  if (r === 9) return `hwb(${pick(['0', '120', '240', '0.25turn'])} ${pick(['0%', '20%', '60%', '50%'])} ${pick(['0%', '30%', '70%', '50%'])}${pick(['', ' / 0.5'])})`;
  if (r === 10) return `lab(${pick(['50%', '29.2', '80', '0', '100%'])} ${pick(['40', '-20', '50%', '0', 'none'])} ${pick(['59.5', '-30', '-10%', '0'])}${pick(['', ' / 0.5'])})`;
  if (r === 11) return `lch(${pick(['50%', '29.2', '80', '20'])} ${pick(['40', '60%', '0'])} ${pick(['30', '120deg', '0.5turn', '300'])}${pick(['', ' / 0.5'])})`;
  if (r === 12) return `oklab(${pick(['0.6', '60%', '0.9', '0'])} ${pick(['0.1', '-0.05', '50%', '0'])} ${pick(['0.1', '-0.1', '0'])}${pick(['', ' / 0.5'])})`;
  if (r === 13) return `oklch(${pick(['0.6', '60%', '0.9'])} ${pick(['0.1', '0.2', '50%'])} ${pick(['30', '250', '120deg'])}${pick(['', ' / 0.5'])})`;
  if (r === 14) return `color(${pick(['srgb', 'srgb-linear', 'display-p3', 'a98-rgb', 'rec2020', 'prophoto-rgb', 'xyz', 'xyz-d50', 'xyz-d65', 'bogus'])} ${pick(['0.5', '1', '0', '50%'])} ${pick(['0.2', '0.8', '25%'])} ${pick(['0.7', '0'])}${pick(['', ' / 0.5'])})`;
  if (r === 15 && depth < 2) return `rgb(from ${genColorSimple()} r g b${pick(['', ' / 0.5', ' / alpha'])})`;
  if (r === 16 && depth < 2) return `rgb(from ${genColorSimple()} calc(r * 0.5) g calc(b + 20)${pick(['', ' / 0.5'])})`;
  if (r === 17 && depth < 2) return `hsl(from ${genColorSimple()} h s calc(l * 0.8)${pick(['', ' / 0.5'])})`;
  if (r === 18 && depth < 2) return `hsl(from ${genColorSimple()} calc(h + 30) s l)`;
  if (r === 19 && depth < 2) return `hwb(from ${genColorSimple()} h w b${pick(['', ' / 0.5'])})`;
  if (r === 20 && depth < 2) return `lab(from ${genColorSimple()} l a b${pick(['', ' / 0.5'])})`;
  if (r === 21 && depth < 2) return `oklch(from ${genColorSimple()} l c h)`;
  if (r === 22 && depth < 2) return `color(from ${genColorSimple()} srgb r g b)`;
  if (r === 23) return `rgb(${int(256)} ${int(256)} ${int(256)}${alpha})`;
  if (r === 24) return `/* c */ ${colorWord()}`;
  return `rgb(/* x */ ${int(256)}, ${int(256)} /* y */, ${int(256)})`;
}
function genColorSimple() { return pick(['red', '#336699', 'rgb(10, 200, 30)', 'hsl(200, 50%, 50%)', 'rebeccapurple', 'white', 'black', '#80808080']); }
function genMix() {
  const space = pick(['srgb', 'srgb-linear', 'lab', 'lch', 'oklab', 'oklch', 'xyz', 'xyz-d50', 'hsl', 'srgb longer hue']);
  const stop = () => `${genColorSimple()}${pick(['', '', ' 30%', ' 60%', ' 0%', ' 100%'])}`;
  return `color-mix(in ${space}, ${stop()}, ${stop()})`;
}
function genNumberExpr(depth = 0) {
  const r = int(12);
  if (r < 3 || depth > 1) return num();
  if (r === 3) return `${num()} ${pick(['+', '-', '*', '/'])} ${num()}`;
  if (r === 4) return `calc(${num()} ${pick(['+', '-'])} ${num()} * ${num()})`;
  if (r === 5) return pick([`sin(${num()}deg)`, `cos(${num()}rad)`, `tan(${num()}deg)`, `asin(0.5)`, `acos(0.5)`, `atan(1)`, `atan2(1, 2)`]);
  if (r === 6) return pick([`sqrt(${pick(['16', '2', '-1', '0'])})`, `pow(${num()}, 2)`, `exp(1)`, `log(${pick(['10', '2.7', '-1'])})`, `log(8, 2)`, 'pi', 'e', `abs(${num()})`, `sign(${num()})`]);
  if (r === 7) return `${pick(['min', 'max'])}(${genNumberExpr(depth + 1)}, ${genNumberExpr(depth + 1)})`;
  if (r === 8) return `clamp(0, ${num()}, 10)`;
  if (r === 9) return pick([`mod(${num()}, 3)`, `rem(-7, 3)`, `round(2.5, 1)`, `round(up, 2.1, 1)`, `round(down, -2.1, 1)`, `round(to-zero, -2.9, 1)`, `hypot(3, 4)`]);
  if (r === 10) return `(${num()} + ${num()}) * ${num()}`;
  return `${num()}${pick(['deg', 'grad', 'turn', 'rad'])}`;
}
function genAngle() { return pick([`${num()}deg`, `${num()}turn`, `${num()}grad`, `${num()}rad`, num(), `calc(${num()}deg + 10deg)`, `calc(1turn / 4)`, 'x']); }
function genTime() {
  const r = int(8);
  if (r < 3) return pick(['1s', '250ms', '0', '0s', '.5s', '2.5s', '10MS']);
  if (r === 3) return `calc(${pick(['1s', '200ms'])} + ${pick(['0.5s', '100ms'])})`;
  if (r === 4) return `calc(${pick(['1s', '200ms'])} * ${pick(['2', '0.5', '3'])})`;
  if (r === 5) return `${pick(['min', 'max'])}(${pick(['1s', '300ms'])}, ${pick(['0.5s', '700ms'])})`;
  if (r === 6) return `clamp(100ms, ${pick(['1s', '50ms'])}, 500ms)`;
  return pick(['5', 'abc', '1s 2s', '2 * 1s', '1s / 2', '1s * 1s', '(1s + 1s)']);
}
function genTransform() {
  const fn = () => pick([
    `translate(${pick(['10px', '5', '50%', '1em', 'calc(1px + 2px)'])}${pick(['', ', 20px', ', 10%'])})`, `translateX(${pick(['10px', '20', '50%'])})`, `translateY(${pick(['-5px', '7', '25%'])})`,
    `scale(${pick(['2', '0.5', '1.5'])}${pick(['', ', 3', ', 0.5'])})`, `scaleX(${pick(['2', '-1'])})`, `scaleY(${pick(['0.5', '3'])})`,
    `rotate(${pick(['45deg', '1turn', '0.5rad', '100grad', 'calc(10deg * 2)', '30'])})`, `skewX(${pick(['10deg', '0.1rad'])})`, `skewY(${pick(['-20deg', '15deg'])})`, `skew(${pick(['10deg', '5deg'])}${pick(['', ', 20deg'])})`,
    `matrix(${pick(['1, 0, 0, 1, 5, 6', '2, 0.5, -0.5, 2, 10, 20', '1,2,3'])})`, 'bogus(1)', 'translate()',
  ]);
  const n = 1 + int(3);
  const parts = [];
  for (let i = 0; i < n; i++) parts.push(fn());
  return pick(['', 'none', 'NONE']) || parts.join(pick([' ', ' ', '  ']));
}
function genOrigin() { return pick(['', 'center', 'left top', 'right bottom', '25% 75%', '50%', 'top', 'left', '10px 20px', 'bottom right', '0% 100%', 'center center', 'left 30%']); }

const ops = [];
function add(op) { ops.push(op); }
for (let i = 0; i < 900; i++) {
  const r = int(13);
  if (r < 3) {
    const bases = pick([undefined, { em: 16, rem: 16 }, { em: 10, rem: 20, vw: 1000, vh: 800 }, { vw: 500, vh: 300 }]);
    const evalB = pick([undefined, { em: 16, rem: 16, percent: 200 }, { em: 12, rem: 18, percent: 100, vw: 1280, vh: 720 }, { percent: 50 }, {}]);
    add({ op: 'length', raw: upper(genLength()), ...(bases ? { bases } : {}), ...(evalB ? { eval: evalB } : {}) });
  } else if (r === 3 || r === 4) add({ op: 'number', raw: genNumberExpr() });
  else if (r === 5) add({ op: 'angle', raw: genAngle() });
  else if (r === 6) add({ op: 'time', raw: genTime() });
  else if (r === 7) add({ op: 'lightdark', raw: pick(['light-dark(red, blue)', 'light-dark(#fff, #000)', 'LIGHT-DARK( a , b )', 'light-dark(a)', 'light-dark(a, b, c)', 'dark(a,b)', 'light-dark(rgb(1, 2, 3), hsl(0, 0%, 0%))']), dark: chance(0.5) });
  else if (r === 8 || r === 9 || r === 10) add({ op: 'color', raw: genColor() });
  else if (r === 11) add({ op: chance(0.6) ? 'mix' : 'contrast', raw: chance(0.6) ? genMix() : `contrast-color(${pick([genColorSimple(), 'currentcolor', genMix()])})`, ...(chance(0.7) ? { current: 0xff336699 } : {}) });
  else if (r === 12) {
    const k = int(3);
    if (k === 0) add({ op: 'transform', raw: genTransform() });
    else if (k === 1) add({ op: 'translatePercent', raw: genTransform() });
    else add({ op: 'origin', raw: genOrigin() });
  }
}
for (let i = 0; i < 160; i++) add({ op: pick(['transform', 'transform', 'translatePercent']), raw: genTransform() });
const tmp = tmpdir();
const inPath = resolve(tmp, 'css_values_inputs.json');
const outPath = resolve(tmp, 'css_values_expected.json');
writeFileSync(inPath, JSON.stringify(ops));
execFileSync(process.env.DART || 'dart', ['run', resolve(here, 'css_values_reference.dart'), inPath, outPath], { stdio: 'inherit', shell: true });
const expected = JSON.parse(readFileSync(outPath, 'utf8'));
const cases = ops.map((op, i) => JSON.stringify({ ...op, e: expected[i] }));

const chunks = [];
const size = 30;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'css_values_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/gfx_cssvalue/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
const kinds = {};
for (const o of ops) kinds[o.op] = (kinds[o.op] || 0) + 1;
console.log(`${cases.length} cases in ${chunks.length} chunks -> gfx_cssvalue`, kinds);
const nulls = {};
ops.forEach((o, i) => { if (expected[i] === null) nulls[o.op] = (nulls[o.op] || 0) + 1; });
console.log('null results', nulls);
