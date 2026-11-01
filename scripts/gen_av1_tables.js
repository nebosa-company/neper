// Generates lib/e/fmt/av1_tables.e from the AV1 specification sources (https://github.com/AOMediaCodec/av1-spec).
// usage: node scripts/gen_av1_tables.js <spec dir> [output file]
// Every C-like table of the spec's markdown (a fenced `c` block holding `Name[ dims ] = { ... }`) is read, its
// symbolic dimensions and values are evaluated, and the values are written as one flat little-endian i32 array in a
// base64 string literal, with a constant per table giving its offset. Tables the decoder does not use are left out.
const fs = require('fs');
const path = require('path');

const specDir = process.argv[2];
const outFile = process.argv[3] || path.join(__dirname, '..', 'lib', 'e', 'fmt', 'av1_tables.e');
if (!specDir) { console.error('usage: node gen_av1_tables.js <spec dir> [output file]'); process.exit(2); }

const BT = String.fromCharCode(96);
function rd(f) { return fs.readFileSync(path.join(specDir, f), 'utf8').replace(/\r\n/g, '\n'); }

const SKIP = new Set(['Quantizer_Matrix', 'Gaussian_Sequence', 'Warped_Filters', 'Upscale_Filter', 'Wedge_Codebook', 'Wedge_Master_Oblique_Odd',
  'Wedge_Master_Oblique_Even', 'Wedge_Master_Vertical', 'Div_Lut', 'tplSamplePos', 'Ii_Weights_1d', 'Wedge_Bits']);

function enumerations() {
  const c = {};
  const blocks = ['4X4', '4X8', '8X4', '8X8', '8X16', '16X8', '16X16', '16X32', '32X16', '32X32', '32X64', '64X32', '64X64', '64X128', '128X64', '128X128', '4X16', '16X4', '8X32', '32X8', '16X64', '64X16'];
  blocks.forEach((n, i) => { c['BLOCK_' + n] = i; });
  c.BLOCK_INVALID = 22;
  const tx = ['4X4', '8X8', '16X16', '32X32', '64X64', '4X8', '8X4', '8X16', '16X8', '16X32', '32X16', '32X64', '64X32', '4X16', '16X4', '8X32', '32X8', '16X64', '64X16'];
  tx.forEach((n, i) => { c['TX_' + n] = i; });
  const modes = ['DC_PRED', 'V_PRED', 'H_PRED', 'D45_PRED', 'D135_PRED', 'D113_PRED', 'D157_PRED', 'D203_PRED', 'D67_PRED', 'SMOOTH_PRED', 'SMOOTH_V_PRED', 'SMOOTH_H_PRED', 'PAETH_PRED', 'UV_CFL_PRED'];
  modes.forEach((n, i) => { c[n] = i; });
  const refs = ['INTRA_FRAME', 'LAST_FRAME', 'LAST2_FRAME', 'LAST3_FRAME', 'GOLDEN_FRAME', 'BWDREF_FRAME', 'ALTREF2_FRAME', 'ALTREF_FRAME'];
  refs.forEach((n, i) => { c[n] = i; });
  c.RESTORE_NONE = 0; c.RESTORE_WIENER = 1; c.RESTORE_SGRPROJ = 2; c.RESTORE_SWITCHABLE = 3;
  return c;
}

function constants() {
  const consts = enumerations();
  const re = new RegExp('^[|][ ]*' + BT + '([A-Za-z][A-Za-z0-9_]*)' + BT + '[ ]*[|][ ]*(-?[0-9]+)[ ]*[|]');
  for (const f of ['03.symbols.md', '04.conventions.md', '06.bitstream.syntax.md', '07.bitstream.semantics.md', '08.decoding.process.md', '09.parsing.process.md']) {
    for (const l of rd(f).split('\n')) {
      const m = l.match(re);
      if (m && !(m[1] in consts)) consts[m[1]] = Number(m[2]);
    }
  }
  return consts;
}

function evalExpr(txt, consts) {
  const e = txt.replace(/[A-Za-z_][A-Za-z0-9_]*/g, x => {
    if (!(x in consts)) throw new Error('unknown ' + x);
    return consts[x];
  });
  return Function('return (' + e + ')')();
}

function declarations(block) {
  const out = [];
  const re = /([A-Za-z_][A-Za-z0-9_]*)\s*((?:\[[^\]]*\]\s*)+)=\s*\{/g;
  let m;
  while ((m = re.exec(block))) {
    const start = m.index + m[0].length - 1;
    let depth = 0, i = start;
    for (; i < block.length; i++) {
      if (block[i] === '{') depth++;
      else if (block[i] === '}') { depth--; if (depth === 0) break; }
    }
    out.push({ name: m[1], dimsTxt: m[2], body: block.slice(start, i + 1) });
    re.lastIndex = i + 1;
  }
  return out;
}

function readTables() {
  const consts = constants();
  const out = [];
  const files = fs.readdirSync(specDir).filter(f => /^(0[3-9]|10|annex).*\.md$/.test(f));
  for (const f of files) {
    const text = rd(f);
    const re = /~~~~+\s*c\n([\s\S]*?)\n~~~~+/g;
    let m;
    while ((m = re.exec(text))) {
      for (const d of declarations(m[1])) {
        const dims = [...d.dimsTxt.matchAll(/\[([^\]]*)\]/g)].map(x => { try { return evalExpr(x[1], consts); } catch (e) { return NaN; } });
        const body = d.body.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
        const vals = [];
        let ok = true;
        for (const p of body.replace(/[{}]/g, ' ').split(',')) {
          const t = p.trim();
          if (t === '') continue;
          // an entry the spec left without its comma ("TX_32X32 TX_4X8") is two values
          const pieces = /[*+\/()]/.test(t) ? [t] : t.split(/\s+/);
          for (const piece of pieces) {
            try { vals.push(evalExpr(piece, consts)); } catch (e) { ok = false; }
          }
        }
        out.push({ file: f, name: d.name, dims, vals, ok });
      }
    }
  }
  return out;
}

const all = readTables();
const seen = new Set();
const tables = [];
for (const t of all) {
  if (SKIP.has(t.name) || seen.has(t.name)) continue;
  seen.add(t.name);
  const size = t.dims.reduce((a, b) => a * b, 1);
  if (!t.ok || size !== t.vals.length) { console.error('skipped ' + t.name + ' (dims ' + t.dims.join('x') + ' = ' + size + ' values ' + t.vals.length + ' ok ' + t.ok + ')'); continue; }
  tables.push(t);
}

let total = 0;
for (const t of tables) total += t.vals.length;
const buf = Buffer.alloc(total * 4);
let off = 0;
const offsets = [];
for (const t of tables) {
  offsets.push(off);
  for (const v of t.vals) { buf.writeInt32LE(v, off * 4); off++; }
}
const b64 = buf.toString('base64');
const CHUNK = 120000;
const chunks = [];
for (let i = 0; i < b64.length; i += CHUNK) chunks.push(b64.slice(i, i + CHUNK));

let src = '// AV1 specification tables, generated by scripts/gen_av1_tables.js from the AV1 specification sources: do not edit.\n';
src += '// One flat array of i32: `load` decodes it, `T_<NAME>` is the offset of the table `<Name>` of the specification in it\n';
src += '// (row-major in the spec\'s index order), `N_<NAME>` its number of values.\n\n';
src += 'use e.bytes\nuse e.mem\n\n';
src += 'error Invalid\n\n';
src += 'const COUNT: usize = ' + total + 'usize\n';
for (let i = 0; i < tables.length; i++) {
  const n = tables[i].name.toUpperCase();
  src += 'const T_' + n + ': usize = ' + offsets[i] + 'usize\n';
}
src += '\n';
for (let i = 0; i < tables.length; i++) {
  const n = tables[i].name.toUpperCase();
  src += 'const N_' + n + ': usize = ' + tables[i].vals.length + 'usize\n';
}
src += '\n';
for (let i = 0; i < chunks.length; i++) src += 'fn part' + i + '() -> str { ret "' + chunks[i] + '" }\n\n';
src += 'fn load(a: *mem.Arena) -> ([]i32, err) {\n';
src += '    let (raw, raw_error) = mem.alloc[u8](a, COUNT * 4usize + 16usize)\n';
src += '    if raw_error != ok { ret (zero, raw_error) }\n';
src += '    var at = 0usize\n';
for (let i = 0; i < chunks.length; i++) {
  src += '    let (got' + i + ', e' + i + ') = bytes.base64_decode(raw[at..], part' + i + '(), .Standard)\n';
  src += '    if e' + i + ' != ok { ret (zero, Invalid) }\n';
  src += '    at += got' + i + '.len\n';
}
src += '    if at != COUNT * 4usize { ret (zero, Invalid) }\n';
src += '    let (values, values_error) = mem.alloc[i32](a, COUNT)\n';
src += '    if values_error != ok { ret (zero, values_error) }\n';
src += '    var i = 0usize\n';
src += '    while i < COUNT {\n';
src += '        let (v, v_error) = bytes.load[i32](raw, i * 4usize, .Little)\n';
src += '        if v_error != ok { ret (zero, Invalid) }\n';
src += '        values[i] = v\n';
src += '        i += 1usize\n';
src += '    }\n';
src += '    ret (values, ok)\n';
src += '}\n';
fs.writeFileSync(outFile, src);
console.log('tables ' + tables.length + ', values ' + total + ', source bytes ' + src.length + ', chunks ' + chunks.length);
