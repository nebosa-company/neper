// Vectors for `e.fmt.woff` and `e.fmt.woff2` (L043): random WOFF/WOFF2 fonts (and damaged ones) decoded by Vaper's own Dart
// decoders (scripts/woff_reference.dart) and written as the link fixture tests/selfhost/fixtures/link/fmt_woff.
// Usage: DART=D:/flutter/bin/dart.bat node scripts/woff_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import zlib from 'node:zlib';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x57f2;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;
const be16 = (v) => [(v >> 8) & 255, v & 255];
const be32 = (v) => [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
const tagBytes = (s) => [...s].map((c) => c.charCodeAt(0));
const randBytes = (n) => Array.from({ length: n }, () => int(256));
const compressible = (n) => { const out = []; while (out.length < n) { const b = int(256), r = 1 + int(12); for (let i = 0; i < r && out.length < n; i++) out.push(b); } return out; };

// ---- WOFF 1
function woff1() {
  const names = ['head', 'glyf', 'loca', 'cmap', 'name', 'OS/2', 'post', 'maxp', 'hhea', 'hmtx', 'zzzz', 'kern'];
  const n = 1 + int(6);
  const tags = [];
  while (tags.length < n) { const t = pick(names); if (!tags.includes(t)) tags.push(t); }
  const tables = tags.map((t) => {
    const raw = chance(0.5) ? compressible(int(400)) : randBytes(int(120));
    const z = [...zlib.deflateSync(Buffer.from(raw))];
    const useZ = z.length < raw.length && chance(0.85);
    return { tag: t, orig: raw, data: useZ ? z : raw, checksum: int(0x7fffffff) };
  });
  const head = [...tagBytes('wOFF'), ...be32(chance(0.7) ? 0x00010000 : 0x4f54544f), ...be32(0), ...be16(n), ...be16(0), ...be32(0), ...be16(1), ...be16(0), ...be32(0), ...be32(0), ...be32(0), ...be32(0), ...be32(0)];
  let off = 44 + 20 * n;
  const dir = [], body = [];
  for (const t of tables) {
    dir.push(...tagBytes(t.tag), ...be32(off), ...be32(t.data.length), ...be32(t.orig.length), ...be32(t.checksum));
    body.push(...t.data);
    while (body.length & 3) body.push(0);
    off = 44 + 20 * n + body.length;
  }
  let out = [...head, ...dir, ...body];
  const m = int(14);
  if (m === 0) out = out.slice(0, int(out.length));
  else if (m === 1) out[int(Math.min(out.length, 44 + 20 * n))] ^= 1 + int(255);
  else if (m === 2) { out[12] = 0; out[13] = 0; }
  else if (m === 3) { const t = int(n); const at = 44 + 20 * t + 12 + 3; out[at] = (out[at] + 1) & 255; }
  else if (m === 4) { const t = int(n); const at = 44 + 20 * t + 4 + 3; out[at] = (out[at] + 1 + int(40)) & 255; }
  else if (m === 5) out[0] = 0x78;
  return out;
}

// ---- WOFF 2
const KNOWN = ['cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ', 'fpgm', 'glyf', 'loca', 'prep', 'CFF ', 'VORG', 'EBDT', 'EBLC', 'gasp', 'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea', 'vmtx', 'BASE', 'GDEF', 'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH', 'CBDT', 'CBLC', 'COLR', 'CPAL', 'SVG ', 'sbix', 'acnt', 'avar', 'bdat', 'bloc', 'bsln', 'cvar', 'fdsc', 'feat', 'fmtx', 'fvar', 'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx', 'opbd', 'prop', 'trak', 'Zapf', 'Silf', 'Glat', 'Gloc', 'Feat', 'Sill'];
const u255 = (v) => (v < 253 ? [v] : v < 506 ? [255, v - 253] : v < 759 ? [254, v - 506] : [253, ...be16(v)]);
const base128 = (v) => { const out = [v & 127]; v = Math.floor(v / 128); while (v > 0) { out.unshift((v & 127) | 128); v = Math.floor(v / 128); } return out; };

function glyfTransform(G, mut) {
  const nContour = [], nPoints = [], flags = [], glyph = [], composite = [], bboxData = [], instr = [];
  const bitmap = new Array(((G + 31) >> 5) << 2).fill(0);
  for (let g = 0; g < G; g++) {
    const kind = int(20);
    if (kind < 3) { nContour.push(...be16(0)); continue; }
    const haveBbox = chance(0.4);
    if (kind < 15) {
      const nc = 1 + int(3);
      nContour.push(...be16(nc));
      let total = 0;
      for (let c = 0; c < nc; c++) { const np = chance(0.1) ? 0 : 1 + int(12); nPoints.push(...u255(np)); total += np; }
      for (let p = 0; p < total; p++) {
        const f = int(256);
        flags.push(f);
        const fl = f & 127;
        const nb = fl < 84 ? 1 : fl < 120 ? 2 : fl < 124 ? 3 : 4;
        for (let b = 0; b < nb; b++) glyph.push(int(256));
      }
      const il = int(14);
      glyph.push(...u255(il));
      for (let b = 0; b < il; b++) instr.push(int(256));
      if (haveBbox) { bitmap[g >> 3] |= 0x80 >> (g & 7); bboxData.push(...randBytes(8)); }
    } else {
      nContour.push(...be16(0xffff));
      const k = 1 + int(3);
      let needInstr = false;
      for (let c = 0; c < k; c++) {
        let fl = 0;
        const words = chance(0.5);
        if (words) fl |= 1;
        const sc = int(4);
        if (sc === 1) fl |= 8; else if (sc === 2) fl |= 64; else if (sc === 3) fl |= 128;
        if (chance(0.2)) { fl |= 256; needInstr = true; }
        if (c < k - 1) fl |= 32;
        composite.push(...be16(fl), ...be16(int(G + 1)), ...randBytes(words ? 4 : 2));
        composite.push(...randBytes(sc === 1 ? 2 : sc === 2 ? 4 : sc === 3 ? 8 : 0));
      }
      if (needInstr) { const il = int(10); glyph.push(...u255(il)); for (let b = 0; b < il; b++) instr.push(int(256)); }
      if (!(mut === 'nobbox' && chance(0.5))) bitmap[g >> 3] |= 0x80 >> (g & 7);
      bboxData.push(...randBytes(8));
    }
  }
  const overlap = chance(0.3);
  const indexFormat = chance(0.5) ? 1 : 0;
  const streams = [nContour, nPoints, flags, glyph, composite, [...bitmap, ...bboxData], instr];
  const head = [...be16(0), ...be16(overlap ? 1 : 0), ...be16(G), ...be16(indexFormat), ...streams.flatMap((s) => be32(s.length))];
  const out = [...head, ...streams.flat()];
  if (overlap) out.push(...randBytes((G + 7) >> 3));
  return { data: out, indexFormat };
}

function woff2() {
  const G = 1 + int(14);
  const H = 1 + int(G);
  const mut = pick(['none', 'none', 'none', 'none', 'none', 'ttcf', 'noloca', 'rawglyf', 'cut', 'flip', 'nobbox', 'hmtxbad', 'nohmtx']);
  const gl = glyfTransform(G, mut);
  const tables = [];
  const plain = (tag, content) => tables.push({ tag, version: 0, content, dstLen: content.length, xformLen: content.length });
  plain('head', randBytes(54));
  const hhea = randBytes(36); hhea[34] = H >> 8; hhea[35] = H & 255;
  plain('hhea', hhea);
  plain('maxp', randBytes(6));
  const glyfRaw = mut === 'rawglyf';
  let glyfContent = gl.data;
  if (mut === 'cut') glyfContent = glyfContent.slice(0, Math.max(0, glyfContent.length - 1 - int(30)));
  if (mut === 'flip' && glyfContent.length) { const at = int(glyfContent.length); glyfContent = glyfContent.map((b, i) => (i === at ? b ^ 0x5a : b)); }
  tables.push({ tag: 'glyf', version: glyfRaw ? 3 : 0, content: glyfContent, dstLen: 1000 + int(1000), xformLen: glyfContent.length });
  const locaLen = (gl.indexFormat ? 4 : 2) * (G + 1);
  if (mut !== 'noloca') tables.push({ tag: 'loca', version: glyfRaw ? 3 : 0, content: glyfRaw ? randBytes(locaLen) : [], dstLen: locaLen, xformLen: glyfRaw ? locaLen : 0 });
  if (mut !== 'nohmtx') {
    if (chance(0.6)) {
      let fl = pick([0, 1, 2]);
      if (mut === 'hmtxbad') fl = pick([3, 4, 0x80]);
      const c = [fl];
      for (let i = 0; i < H; i++) c.push(...randBytes(2));
      if (!(fl & 1)) for (let i = 0; i < H; i++) c.push(...randBytes(2));
      if (!(fl & 2)) for (let i = G - H; i > 0; i--) c.push(...randBytes(2));
      tables.push({ tag: 'hmtx', version: 1, content: c, dstLen: 2 * G + 2 * H, xformLen: c.length });
    } else {
      plain('hmtx', randBytes(4 * H + 2 * (G - H)));
    }
  }
  for (const t of ['cmap', 'name', 'post']) if (chance(0.5)) plain(t, chance(0.5) ? compressible(int(200)) : randBytes(int(60)));
  if (chance(0.3)) plain('Wxyz', randBytes(1 + int(30)));
  for (let i = tables.length - 1; i > 0; i--) { const j = int(i + 1); [tables[i], tables[j]] = [tables[j], tables[i]]; }
  const dir = [];
  for (const t of tables) {
    const idx = KNOWN.indexOf(t.tag);
    dir.push(((t.version & 3) << 6) | (idx < 0 ? 63 : idx));
    if (idx < 0) dir.push(...tagBytes(t.tag));
    dir.push(...base128(t.dstLen));
    const transformed = t.tag === 'glyf' || t.tag === 'loca' ? t.version === 0 : t.version !== 0;
    if (transformed) dir.push(...base128(t.xformLen));
  }
  const blob = tables.flatMap((t) => t.content);
  const comp = [...zlib.brotliCompressSync(Buffer.from(blob), { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 5, [zlib.constants.BROTLI_PARAM_LGWIN]: 22 } })];
  const flavor = mut === 'ttcf' ? 0x74746366 : 0x00010000;
  const head2 = [...tagBytes('wOF2'), ...be32(flavor), ...be32(0), ...be16(tables.length), ...be16(0), ...be32(0), ...be32(comp.length), ...be16(1), ...be16(0), ...be32(0), ...be32(0), ...be32(0), ...be32(0), ...be32(0)];
  let out = [...head2, ...dir, ...comp];
  if (chance(0.04)) out = out.slice(0, int(out.length));
  if (chance(0.04)) { const at = int(Math.min(out.length, 48 + dir.length)); out[at] ^= 1 + int(255); }
  out.mut = mut;
  return out;
}

const hex = (a) => Buffer.from(a).toString('hex');
const cases = [];
for (let i = 0; i < 160; i++) cases.push({ k: 'woff', h: hex(woff1()) });
for (let i = 0; i < 320; i++) { const w = woff2(); cases.push({ k: 'woff2', h: hex(w), m: w.mut }); }
const tmp = join(tmpdir(), 'woff_vectors');
mkdirSync(tmp, { recursive: true });
writeFileSync(join(tmp, 'in.json'), JSON.stringify(cases));
const dart = process.env.DART || 'dart';
execFileSync(dart, ['run', resolve(here, 'woff_reference.dart'), join(tmp, 'in.json'), join(tmp, 'out.json')], { stdio: 'inherit', shell: true });
const answers = JSON.parse(readFileSync(join(tmp, 'out.json'), 'utf8'));
const lines = [];
let nulls = 0, excs = 0, oks = 0;
const byMut = {};
cases.forEach((c, i) => {
  if (answers[i] === 'exc') { excs++; return; }
  if (answers[i] === null) nulls++; else oks++;
  if (c.m) { const key = c.m + (answers[i] === null ? ' refused' : ' decoded'); byMut[key] = (byMut[key] || 0) + 1; }
  lines.push(JSON.stringify({ k: c.k, h: c.h, e: answers[i] }));
});
const chunks = [];
const size = 8;
for (let i = 0; i < lines.length; i += size) {
  chunks.push(`"${lines.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'woff_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/fmt_woff/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(byMut);
console.log(`${lines.length} cases in ${chunks.length} chunks -> fmt_woff; decoded ${oks}, refused ${nulls}, dropped(exc) ${excs}`);
