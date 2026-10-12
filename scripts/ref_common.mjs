// Shared by the L037/L164 reference scripts: a seeded generator, the canonical JSON the fixtures compare, and the
// writer that turns `{"op", "e"}` lines into a link fixture (chunks of 20 lines, one exit code per chunk).
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const here = dirname(fileURLToPath(import.meta.url));
export const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';

export function rng(seed0) {
  let seed = seed0;
  const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const int = (n) => Math.floor(rnd() * n);
  return { rnd, int, pick: (a) => a[int(a.length)], chance: (p) => rnd() < p };
}

export function canon(v) {
  if (v === undefined) return 'null';
  const walk = (x) => {
    if (Array.isArray(x)) return x.map(walk);
    if (x && typeof x === 'object') {
      const out = {};
      for (const k of Object.keys(x).sort()) if (x[k] !== undefined) out[k] = walk(x[k]);
      return out;
    }
    return x;
  };
  return JSON.stringify(walk(v));
}

export const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

const CRLF = String.fromCharCode(13, 10);
const LF = String.fromCharCode(10);

// Write tests/selfhost/fixtures/link/<name>/src/main.e from scripts/<template> and the cases `[{op, e}]`.
export function emit(name, templateFile, cases, okText) {
  const lines = cases.map((c) => JSON.stringify(c));
  const chunks = [];
  for (let i = 0; i < lines.length; i += 20) {
    chunks.push(`"${lines.slice(i, i + 20).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
  }
  const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
  const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
  const template = readFileSync(resolve(here, templateFile), 'utf8').split(CRLF).join(LF);
  const text = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls).replace('__OK_TEXT__', okText);
  const target = resolve(here, '..', `tests/selfhost/fixtures/link/${name}/src/main.e`);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, text, 'utf8');
  return chunks.length;
}
