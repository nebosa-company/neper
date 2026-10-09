// Reference vectors for `e.algo.checksum` (L030): generate valid identifiers of every kind, mutate them, and run
// appdor's own validators (src/fields/specialized.js, barcode.js, nace.js) over them; write the link fixture
// tests/selfhost/fixtures/link/algo_checksum. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const spec = await load('src/fields/specialized.js');
const barcode = await load('src/fields/barcode.js');
const nace = await load('src/fields/nace.js');

const KINDS = ['iban', 'lei', 'isin', 'isbn', 'isbn10', 'isbn13', 'ean13', 'barcode', 'vin', 'credit-card', 'imei', 'bic', 'vat', 'mic', 'duns', 'hs-code', 'unlocode', 'incoterm',
  'icd10', 'snomed', 'loinc', 'ndc', 'rxnorm', 'mac', 'upc', 'nace'];
const hex = (s) => (s === '' ? '_' : Buffer.from(s, 'utf8').toString('hex'));
const bits = (v) => KINDS.map((k) => (spec.SPECIALIZED_VALIDATORS[k](v) ? '1' : '0')).join('');

let seed = 0xc0de;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const DIG = '0123456789';
const ALP = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const rand = (alphabet, n) => Array.from({ length: n }, () => alphabet[int(alphabet.length)]).join('');

// --- valid generators -------------------------------------------------------
const mod97 = (s) => { let r = 0; for (const c of s) { const v = c >= 'A' ? c.charCodeAt(0) - 55 : Number(c); r = (r * (v > 9 ? 100 : 10) + v) % 97; } return r; };
const iban = () => { const cc = rand(ALP, 2); const bban = rand(DIG + ALP, 10 + int(21)); const chk = String(98 - mod97(`${bban}${cc}00`)).padStart(2, '0'); return `${cc}${chk}${bban}`; };
const lei = () => { const body = rand(DIG + ALP, 18); const chk = String(98 - mod97(`${body}00`)).padStart(2, '0'); return `${body}${chk}`; };
const luhnDigit = (p) => { let sum = 0; let alt = true; for (let i = p.length - 1; i >= 0; i -= 1) { let d = Number(p[i]); if (alt) { d *= 2; if (d > 9) d -= 9; } sum += d; alt = !alt; } return (10 - (sum % 10)) % 10; };
const luhn = (n) => { const p = rand(DIG, n - 1); return p + luhnDigit(p); };
const isin = () => { const body = rand(ALP, 2) + rand(DIG + ALP, 9); const digits = [...body].map((c) => (c >= 'A' ? String(c.charCodeAt(0) - 55) : c)).join(''); return body + luhnDigit(digits); };
const isbn10 = () => { const p = rand(DIG, 9); let sum = 0; for (let i = 0; i < 9; i += 1) sum += Number(p[i]) * (10 - i); const c = (11 - (sum % 11)) % 11; return p + (c === 10 ? 'X' : String(c)); };
const ean = (n) => { const p = rand(DIG, n - 1); let sum = 0; for (let i = 0; i < p.length; i += 1) sum += Number(p[p.length - 1 - i]) * (i % 2 === 0 ? 3 : 1); return p + ((10 - (sum % 10)) % 10); };
const VIN_T = { A: 1, B: 2, C: 3, D: 4, E: 5, F: 6, G: 7, H: 8, J: 1, K: 2, L: 3, M: 4, N: 5, P: 7, R: 9, S: 2, T: 3, U: 4, V: 5, W: 6, X: 7, Y: 8, Z: 9 };
const VIN_W = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];
const vin = () => { const set = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'; const s = [...rand(set, 17)]; let sum = 0; for (let i = 0; i < 17; i += 1) if (i !== 8) sum += (s[i] >= '0' && s[i] <= '9' ? Number(s[i]) : VIN_T[s[i]]) * VIN_W[i]; const c = sum % 11; s[8] = c === 10 ? 'X' : String(c); return s.join(''); };
const VD = [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 2, 3, 4, 0, 6, 7, 8, 9, 5], [2, 3, 4, 0, 1, 7, 8, 9, 5, 6], [3, 4, 0, 1, 2, 8, 9, 5, 6, 7], [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
  [5, 9, 8, 7, 6, 0, 4, 3, 2, 1], [6, 5, 9, 8, 7, 1, 0, 4, 3, 2], [7, 6, 5, 9, 8, 2, 1, 0, 4, 3], [8, 7, 6, 5, 9, 3, 2, 1, 0, 4], [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]];
const VP = [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 5, 7, 6, 2, 8, 3, 0, 9, 4], [5, 8, 0, 3, 7, 9, 6, 1, 4, 2], [8, 9, 1, 6, 0, 4, 3, 5, 2, 7], [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
  [4, 2, 8, 6, 5, 7, 3, 9, 0, 1], [2, 7, 9, 3, 8, 0, 6, 4, 1, 5], [7, 0, 4, 6, 9, 1, 3, 2, 5, 8]];
const VINV = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9];
const verhoeffAppend = (p) => { let c = 0; const rev = [...p].reverse(); for (let i = 0; i < rev.length; i += 1) c = VD[c][VP[(i + 1) % 8][Number(rev[i])]]; return p + VINV[c]; };
const snomed = () => verhoeffAppend(String(1 + int(9)) + rand(DIG, 4 + int(12)));
const loinc = () => { const p = rand(DIG, 1 + int(6)); return `${p}-${luhnDigit(p)}`; };
const VAT = { AT: () => `U${rand(DIG, 8)}`, BE: () => (rnd() < 0.5 ? rand(DIG, 9) : pick(['0', '1']) + rand(DIG, 9)), BG: () => rand(DIG, 9 + int(2)), CY: () => rand(DIG, 8) + rand(ALP, 1), CZ: () => rand(DIG, 8 + int(3)),
  DE: () => rand(DIG, 9), DK: () => rand(DIG, 8), EE: () => rand(DIG, 9), EL: () => rand(DIG, 9), ES: () => rand(DIG + ALP, 1) + rand(DIG, 7) + rand(DIG + ALP, 1), FI: () => rand(DIG, 8),
  FR: () => rand(DIG + ALP, 2) + rand(DIG, 9), HR: () => rand(DIG, 11), HU: () => rand(DIG, 8), IE: () => (rnd() < 0.5 ? rand(DIG, 7) + rand(ALP, 1 + int(2)) : rand(DIG, 1) + rand(DIG + ALP + '+*', 1) + rand(DIG, 5) + rand(ALP, 1)),
  IT: () => rand(DIG, 11), LT: () => rand(DIG, rnd() < 0.5 ? 9 : 12), LU: () => rand(DIG, 8), LV: () => rand(DIG, 11), MT: () => rand(DIG, 8), NL: () => `${rand(DIG, 9)}B${rand(DIG, 2)}`,
  PL: () => rand(DIG, 10), PT: () => rand(DIG, 9), RO: () => rand(DIG, 2 + int(9)), SE: () => rand(DIG, 12), SI: () => rand(DIG, 8), SK: () => rand(DIG, 10) };
const vat = () => { const c = pick(Object.keys(VAT)); return c + VAT[c](); };
const mac = () => { const sep = pick([':', '-']); return Array.from({ length: 6 }, () => rand('0123456789ABCDEF', 2)).join(sep); };
const macCisco = () => `${rand('0123456789abcdef', 4)}.${rand('0123456789ABCDEF', 4)}.${rand('0123456789abcdef', 4)}`;
const hs = () => { const ch = pick(['01', '02', '33', '61', '84', '97', '98', '00', '77', '96']); return ch + rand(DIG, pick([4, 6, 8])); };
const ndc = () => pick([`${rand(DIG, 4)}-${rand(DIG, 4)}-${rand(DIG, 2)}`, `${rand(DIG, 5)}-${rand(DIG, 3)}-${rand(DIG, 2)}`, `${rand(DIG, 5)}-${rand(DIG, 4)}-${rand(DIG, 1)}`, rand(DIG, 10), rand(DIG, 11)]);
const nacecode = () => { const div = pick(nace.NACE_SECTIONS.flatMap((s) => s.divisions.map((d) => [s.section, d[0]]))); const base = div[1]; return pick([div[0], base, `${base}.${int(10)}`, `${base}.${int(10)}${int(10)}`, `${div[0]}.${base}`, `${div[0]}${base}.${int(10)}`, `${div[0]} ${base}`, pick(['04', '34', '99', '00']), `${base}.${int(10)}${int(10)}${int(10)}`]); };
const GENERATORS = [iban, lei, isin, isbn10, () => ean(13), () => ean(13), () => luhn(12 + int(8)), () => luhn(15), vin, () => ean(12), () => ean(8), () => rand(ALP, 6) + rand(DIG + ALP, 2) + (rnd() < 0.5 ? rand(DIG + ALP, 3) : ''),
  vat, () => rand(DIG + ALP, 4), () => rand(DIG, 9), hs, () => rand(ALP, 2) + rand(ALP + '23456789', 3), () => pick(['EXW', 'FCA', 'FAS', 'FOB', 'CFR', 'CIF', 'CPT', 'CIP', 'DAP', 'DPU', 'DDP', 'DDU', 'XYZ']),
  () => rand(ALP, 1) + rand(DIG, 1) + rand(DIG + ALP, 1) + (rnd() < 0.5 ? `.${rand(DIG + ALP, 1 + int(4))}` : ''), snomed, loinc, ndc, () => rand(DIG, 1 + int(8)), () => (rnd() < 0.7 ? mac() : macCisco()), () => ean(12), nacecode,
  () => `${rand(DIG, 2)}`, () => luhnDigit('7992739871') + '', () => '', () => '   ', () => '-- --'];

// --- mutations -------------------------------------------------------------
const TRICKS = ['ı', 'ſ', 'ß', 'ﬁ', 'ﬀ', 'ǰ', '\u00a0', '\u2003', '\t', '\ufeff', '١', 'Ａ', '٣'];
function mutate(s) {
  const chars = [...s];
  switch (int(12)) {
    case 0: return s.toLowerCase();
    case 1: return s.replace(/(.{4})/g, '$1 ').trim();
    case 2: return s.replace(/(.{3})/g, '$1-');
    case 3: { if (!chars.length) return s; const i = int(chars.length); chars[i] = pick(DIG + ALP); return chars.join(''); }
    case 4: return s.slice(0, -1);
    case 5: return s + pick(DIG + ALP);
    case 6: return ` ${s} `;
    case 7: { const i = int(chars.length + 1); chars.splice(i, 0, pick(TRICKS)); return chars.join(''); }
    case 8: { if (!chars.length) return s; const i = int(chars.length); chars[i] = pick(TRICKS); return chars.join(''); }
    case 9: return chars.reverse().join('');
    case 10: { if (chars.length < 2) return s; const i = int(chars.length - 1); [chars[i], chars[i + 1]] = [chars[i + 1], chars[i]]; return chars.join(''); }
    default: return s.replace(/-/g, '').replace(/\s/g, '');
  }
}

const cases = [];
const add = (obj) => cases.push(JSON.stringify(obj));
const values = [];
for (const gen of GENERATORS) {
  for (let k = 0; k < 14; k += 1) {
    const v = gen();
    values.push(v);
    for (let m = 0; m < 3; m += 1) values.push(mutate(v));
  }
}
for (let k = 0; k < 60; k += 1) values.push(rand(DIG + ALP + ' -.', 1 + int(34)));
// well-known identifiers
values.push('GB82 WEST 1234 5698 7654 32', 'DE89 3704 0044 0532 0130 00', 'US0378331005', '0306406152', '9780306406157', '4539 1488 0343 6467', '1HGCM82633A004352', '73211009', '2345-6',
  '5493001KJTIGC8Y1R712', 'NL91 ABNA 0417 1643 00', '12-34', '4006381333931', '036000291452', 'U07.1', 'A00', '00:1A:2B:3C:4D:5E', '0000-0000-0000', '1234.5678.9ABC');
for (const v of values) add({ v, e: bits(v) });

// barcode symbologies
const SYMS = ['ean13', 'ean8', 'upca', 'code39', 'code128', 'qr', 'bogus', 'constructor'];
const B = [];
for (let k = 0; k < 14; k += 1) B.push(ean(13), ean(8), ean(12), rand(DIG, 13), rand(DIG, 12), rand(DIG, 8), rand(DIG + ALP + '-. $/+%', 3 + int(10)), rand(ALP + DIG, 4));
B.push('', '  ', '1234567890128', ' 4006381333931 ', 'ABC', 'ABC1', 'HELLO WORLD', 'a-b', 'AB😀', '😀', 'A😀B', 'CODE39+', '12345', 'abc', 'ABCDEFG$', '-');
for (const b of B) for (const s of SYMS.slice(0, 7)) {
  const r = barcode.validateBarcode(b, s);
  add({ b, s, e: r.ok ? `ok|${hex(r.value)}|${r.symbology}` : `no|${r.reason}|${hex(r.message)}` });
}
for (const b of B.slice(0, 40)) add({ v: b, e: bits(b) });
// scan to field value
const FORMATS = ['ean_13', 'EAN-13', 'ean_8', 'upc_a', 'code_39', 'code_128', 'qr_code', 'QR', 'weird', '', 'pdf417', 'Code128'];
for (let k = 0; k < 160; k += 1) {
  const raw = pick(B.filter((b) => b.trim() !== ''));
  const format = pick(FORMATS);
  const accepted = pick([[], ['ean13'], ['ean13', 'upca'], ['qr'], ['code39', 'bogus'], ['ean8', 'ean13', 'upca', 'code128']]);
  const r = barcode.scanToFieldValue({ rawValue: raw, format: format || undefined }, { acceptedSymbologies: accepted });
  add({ t: raw, f: format, x: accepted, e: r.ok ? `ok|${hex(r.value)}|${r.symbology}` : `no|${r.reason}|${hex(r.message)}` });
}
add({ t: '', f: 'ean_13', x: [], e: (() => { const r = barcode.scanToFieldValue({ rawValue: '' }, {}); return `no|${r.reason}|${hex(r.message)}`; })() });
// scan capability
for (const d of [true, false]) for (const s of [true, false]) for (const c of [true, false]) for (const p of ['granted', 'denied', 'prompt']) {
  const r = barcode.barcodeScanSupport({ hasDetector: d, isSecureContext: s, hasCamera: c, permission: p });
  add({ p: [d, s, c, p], e: `${r.reason}|${hex(r.message || '')}${r.available && r.needsPrompt ? '|prompt' : ''}` });
}
// NACE
const NV = ['A', 'a', 'V', 'W', '', ' ', '01', '1', '41', '41.2', '41.20', '41.200', 'F', 'F41', 'F.41', 'F 41', 'F.41.20', 'G.41', '04', '34', '99', '00', ' 62.01 ', 'j62', 'J62.01', 'J.62.0', 'U99', 'V99', '87', '88', '11.', '11.x', 'F4', 'AB', '01.1.1', '01.11', '47.91', 'ı', 'ß'];
for (const n of NV) { const r = nace.parseNaceCode(n); add({ n, e: r ? `${r.level}|${r.section}|${r.division || ''}|${r.code}` : 'null' }); }
for (const n of nacecodes()) { const r = nace.parseNaceCode(n); add({ n, e: r ? `${r.level}|${r.section}|${r.division || ''}|${r.code}` : 'null' }); }
function nacecodes() { return Array.from({ length: 80 }, () => nacecode()); }
for (const k of ['A', 'a', 'F', 'V', 'W', '41', '04', ' 41 ', '', 'zz', '01', '99', 'U']) {
  for (const l of ['en', 'bg', 'BG', ' bg ', 'fr', 'bg-BG', '']) {
    const text = `${nace.naceSectionTitle(k, l)}|${nace.naceDivisionTitle(k, l)}|${nace.isNaceSection(k) ? 'S' : '-'}|${nace.isNaceDivision(k) ? 'D' : '-'}|${nace.naceSectionOf(k) || ''}`;
    add({ k, l, e: hex(text) });
  }
}

const chunks = [];
const size = 40;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'checksum_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_checksum/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
const ones = cases.filter((l) => /"e":"[01]{26}"/.test(l)).filter((l) => l.includes('1')).length;
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_checksum (${ones} value lines with a pass)`);
