/**
 * Random, Hash & Encoding functions (docs/formulas.md:30-39).
 *
 * Self-contained implementations (no crypto/Buffer dependency): MT19937 Mersenne
 * Twister for RANDOM, and MD5/SHA-1/SHA-256/CRC32 matching RFC test vectors
 * (REQ correctness). RANDOM/UUID/GENERATEPASSWORD are `generateOnce` — the host
 * persists their first result rather than regenerating on re-render
 * (REQ-FORMULAENGINE-15). A deterministic RNG can be injected via `ctx.rng`
 * (a function returning [0,1)) or `ctx.randomSeed`.
 */

import { isError, valueError } from './errors.js';
import { toNumber, toText, isBlank } from './values.js';

const CATEGORY = 'random-hash-encode';

// --- Mersenne Twister MT19937 ---------------------------------------------

class MersenneTwister {
  constructor(seed) {
    this.mt = new Array(624);
    this.index = 624;
    this.seedMT(seed >>> 0);
  }

  seedMT(seed) {
    this.mt[0] = seed >>> 0;
    for (let i = 1; i < 624; i++) {
      const s = this.mt[i - 1] ^ (this.mt[i - 1] >>> 30);
      this.mt[i] =
        (((((s & 0xffff0000) >>> 16) * 1812433253) << 16) +
          (s & 0x0000ffff) * 1812433253 +
          i) >>>
        0;
    }
  }

  generate() {
    for (let i = 0; i < 624; i++) {
      const y = (this.mt[i] & 0x80000000) + (this.mt[(i + 1) % 624] & 0x7fffffff);
      this.mt[i] = this.mt[(i + 397) % 624] ^ (y >>> 1);
      if (y % 2 !== 0) this.mt[i] ^= 0x9908b0df;
    }
    this.index = 0;
  }

  nextUint32() {
    if (this.index >= 624) this.generate();
    let y = this.mt[this.index++];
    y ^= y >>> 11;
    y ^= (y << 7) & 0x9d2c5680;
    y ^= (y << 15) & 0xefc60000;
    y ^= y >>> 18;
    return y >>> 0;
  }

  random() {
    return this.nextUint32() / 4294967296; // [0,1)
  }
}

function rngFor(ctx) {
  if (ctx && typeof ctx.rng === 'function') return ctx.rng;
  if (ctx && ctx.randomSeed != null) {
    const mt = new MersenneTwister(Number(ctx.randomSeed) >>> 0);
    return () => mt.random();
  }
  // No injected generator: draw from the platform CSPRNG. GENERATEPASSWORD and
  // UUID are persisted as secrets/identifiers, and a Mersenne Twister seeded
  // from a 32-bit clock/Math.random value has only 2^32 outcomes. The Twister
  // stays behind ctx.rng / ctx.randomSeed, for reproducible tests.
  return secureUnit;
}

/** A uniform double in [0,1) from 53 bits of crypto.getRandomValues. */
function secureUnit() {
  const source = typeof globalThis !== 'undefined' ? globalThis.crypto : null;
  if (!source || typeof source.getRandomValues !== 'function') {
    throw new Error('secure-random-unavailable');
  }
  const w = new Uint32Array(2);
  source.getRandomValues(w);
  return ((w[0] >>> 5) * 67108864 + (w[1] >>> 6)) / 9007199254740992;
}

/** Longest GENERATEPASSWORD the formula engine will build. */
const MAX_PASSWORD_LENGTH = 256;

// --- UTF-8 + base64 -------------------------------------------------------

function utf8Bytes(str) {
  const bytes = [];
  for (let i = 0; i < str.length; i++) {
    let c = str.charCodeAt(i);
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) {
      bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff) {
      const c2 = str.charCodeAt(++i);
      c = 0x10000 + ((c & 0x3ff) << 10) + (c2 & 0x3ff);
      bytes.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    } else {
      bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return bytes;
}

function bytesToUtf8(bytes) {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const c = bytes[i++];
    if (c < 0x80) out += String.fromCharCode(c);
    else if (c < 0xe0) out += String.fromCharCode(((c & 0x1f) << 6) | (bytes[i++] & 0x3f));
    else if (c < 0xf0)
      out += String.fromCharCode(((c & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f));
    else {
      const cp =
        ((c & 0x07) << 18) | ((bytes[i++] & 0x3f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f);
      out += String.fromCodePoint(cp);
    }
  }
  return out;
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function base64Encode(str) {
  const bytes = utf8Bytes(str);
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = bytes[i + 1];
    const b2 = bytes[i + 2];
    out += B64[b0 >> 2];
    out += B64[((b0 & 3) << 4) | (b1 === undefined ? 0 : b1 >> 4)];
    out += b1 === undefined ? '=' : B64[((b1 & 15) << 2) | (b2 === undefined ? 0 : b2 >> 6)];
    out += b2 === undefined ? '=' : B64[b2 & 63];
  }
  return out;
}

function base64Decode(str) {
  const clean = String(str).replace(/[^A-Za-z0-9+/]/g, '');
  const bytes = [];
  for (let i = 0; i < clean.length; i += 4) {
    const n0 = B64.indexOf(clean[i]);
    const n1 = B64.indexOf(clean[i + 1]);
    const n2 = B64.indexOf(clean[i + 2]);
    const n3 = B64.indexOf(clean[i + 3]);
    bytes.push((n0 << 2) | (n1 >> 4));
    if (n2 !== -1 && clean[i + 2] !== undefined) bytes.push(((n1 & 15) << 4) | (n2 >> 2));
    if (n3 !== -1 && clean[i + 3] !== undefined) bytes.push(((n2 & 3) << 6) | n3);
  }
  return bytesToUtf8(bytes);
}

// --- Hash primitives ------------------------------------------------------

function toHex(bytes) {
  return bytes.map((b) => b.toString(16).padStart(2, '0')).join('');
}

function crc32(str) {
  const bytes = utf8Bytes(str);
  let crc = 0xffffffff;
  for (const b of bytes) {
    crc ^= b;
    for (let k = 0; k < 8; k++) {
      crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

// MD5 (RFC 1321), canonical cmn/ff/gg/hh/ii structure.
//
// biome-ignore-start lint/suspicious/noShadow: the a/b/c/d/x/s/t parameter names
// are RFC 1321's own, and the round helpers below are pure functions of them.
// They shadow the state variables of the same name declared further down — which
// is what makes the 64 round calls line up with the published reference. Renaming
// them would make this block harder to check against the RFC, not easier to read,
// and this is the one place in the codebase where matching an external spec
// beats matching the house rule.
function md5(str) {
  const add = (a, b) => (a + b) & 0xffffffff;
  const rol = (n, c) => (n << c) | (n >>> (32 - c));
  const cmn = (q, a, b, x, s, t) => add(rol(add(add(a, q), add(x, t)), s), b);
  const ff = (a, b, c, d, x, s, t) => cmn((b & c) | (~b & d), a, b, x, s, t);
  const gg = (a, b, c, d, x, s, t) => cmn((b & d) | (c & ~d), a, b, x, s, t);
  const hh = (a, b, c, d, x, s, t) => cmn(b ^ c ^ d, a, b, x, s, t);
  const ii = (a, b, c, d, x, s, t) => cmn(c ^ (b | ~d), a, b, x, s, t);
  // biome-ignore-end lint/suspicious/noShadow: end of the RFC 1321 round helpers

  const bytes = utf8Bytes(str);
  const ml = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (let i = 0; i < 8; i++) bytes.push((ml / Math.pow(2, 8 * i)) & 0xff);

  let a = 0x67452301, b = 0xefcdab89, c = 0x98badcfe, d = 0x10325476;
  for (let off = 0; off < bytes.length; off += 64) {
    const x = [];
    for (let j = 0; j < 16; j++)
      x[j] = bytes[off + j * 4] | (bytes[off + j * 4 + 1] << 8) | (bytes[off + j * 4 + 2] << 16) | (bytes[off + j * 4 + 3] << 24);
    const oa = a, ob = b, oc = c, od = d;
    a = ff(a, b, c, d, x[0], 7, -680876936); d = ff(d, a, b, c, x[1], 12, -389564586); c = ff(c, d, a, b, x[2], 17, 606105819); b = ff(b, c, d, a, x[3], 22, -1044525330);
    a = ff(a, b, c, d, x[4], 7, -176418897); d = ff(d, a, b, c, x[5], 12, 1200080426); c = ff(c, d, a, b, x[6], 17, -1473231341); b = ff(b, c, d, a, x[7], 22, -45705983);
    a = ff(a, b, c, d, x[8], 7, 1770035416); d = ff(d, a, b, c, x[9], 12, -1958414417); c = ff(c, d, a, b, x[10], 17, -42063); b = ff(b, c, d, a, x[11], 22, -1990404162);
    a = ff(a, b, c, d, x[12], 7, 1804603682); d = ff(d, a, b, c, x[13], 12, -40341101); c = ff(c, d, a, b, x[14], 17, -1502002290); b = ff(b, c, d, a, x[15], 22, 1236535329);
    a = gg(a, b, c, d, x[1], 5, -165796510); d = gg(d, a, b, c, x[6], 9, -1069501632); c = gg(c, d, a, b, x[11], 14, 643717713); b = gg(b, c, d, a, x[0], 20, -373897302);
    a = gg(a, b, c, d, x[5], 5, -701558691); d = gg(d, a, b, c, x[10], 9, 38016083); c = gg(c, d, a, b, x[15], 14, -660478335); b = gg(b, c, d, a, x[4], 20, -405537848);
    a = gg(a, b, c, d, x[9], 5, 568446438); d = gg(d, a, b, c, x[14], 9, -1019803690); c = gg(c, d, a, b, x[3], 14, -187363961); b = gg(b, c, d, a, x[8], 20, 1163531501);
    a = gg(a, b, c, d, x[13], 5, -1444681467); d = gg(d, a, b, c, x[2], 9, -51403784); c = gg(c, d, a, b, x[7], 14, 1735328473); b = gg(b, c, d, a, x[12], 20, -1926607734);
    a = hh(a, b, c, d, x[5], 4, -378558); d = hh(d, a, b, c, x[8], 11, -2022574463); c = hh(c, d, a, b, x[11], 16, 1839030562); b = hh(b, c, d, a, x[14], 23, -35309556);
    a = hh(a, b, c, d, x[1], 4, -1530992060); d = hh(d, a, b, c, x[4], 11, 1272893353); c = hh(c, d, a, b, x[7], 16, -155497632); b = hh(b, c, d, a, x[10], 23, -1094730640);
    a = hh(a, b, c, d, x[13], 4, 681279174); d = hh(d, a, b, c, x[0], 11, -358537222); c = hh(c, d, a, b, x[3], 16, -722521979); b = hh(b, c, d, a, x[6], 23, 76029189);
    a = hh(a, b, c, d, x[9], 4, -640364487); d = hh(d, a, b, c, x[12], 11, -421815835); c = hh(c, d, a, b, x[15], 16, 530742520); b = hh(b, c, d, a, x[2], 23, -995338651);
    a = ii(a, b, c, d, x[0], 6, -198630844); d = ii(d, a, b, c, x[7], 10, 1126891415); c = ii(c, d, a, b, x[14], 15, -1416354905); b = ii(b, c, d, a, x[5], 21, -57434055);
    a = ii(a, b, c, d, x[12], 6, 1700485571); d = ii(d, a, b, c, x[3], 10, -1894986606); c = ii(c, d, a, b, x[10], 15, -1051523); b = ii(b, c, d, a, x[1], 21, -2054922799);
    a = ii(a, b, c, d, x[8], 6, 1873313359); d = ii(d, a, b, c, x[15], 10, -30611744); c = ii(c, d, a, b, x[6], 15, -1560198380); b = ii(b, c, d, a, x[13], 21, 1309151649);
    a = ii(a, b, c, d, x[4], 6, -145523070); d = ii(d, a, b, c, x[11], 10, -1120210379); c = ii(c, d, a, b, x[2], 15, 718787259); b = ii(b, c, d, a, x[9], 21, -343485551);
    a = add(a, oa); b = add(b, ob); c = add(c, oc); d = add(d, od);
  }
  const out = [];
  for (const v of [a, b, c, d]) for (let i = 0; i < 4; i++) out.push((v >>> (8 * i)) & 0xff);
  return toHex(out);
}

// SHA-1 (RFC 3174).
function sha1(str) {
  return sha1Bytes(utf8Bytes(str));
}

/** SHA-1 over a raw byte array (used by HMAC-SHA1 / TOTP). Lowercase hex digest. */
function sha1Bytes(input) {
  const bytes = input.slice();
  const ml = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (let i = 7; i >= 0; i--) bytes.push((ml / Math.pow(2, 8 * i)) & 0xff);
  let h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;
  const rol = (x, c) => (x << c) | (x >>> (32 - c));
  for (let i = 0; i < bytes.length; i += 64) {
    const w = new Array(80);
    for (let j = 0; j < 16; j++)
      w[j] = (bytes[i + j * 4] << 24) | (bytes[i + j * 4 + 1] << 16) | (bytes[i + j * 4 + 2] << 8) | bytes[i + j * 4 + 3];
    for (let j = 16; j < 80; j++) w[j] = rol(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
    let a = h0, b = h1, c = h2, d = h3, e = h4;
    for (let j = 0; j < 80; j++) {
      let f, k;
      if (j < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
      else if (j < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
      else { f = b ^ c ^ d; k = 0xca62c1d6; }
      const t = (rol(a, 5) + f + e + k + w[j]) >>> 0;
      e = d; d = c; c = rol(b, 30) >>> 0; b = a; a = t;
    }
    h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0; h3 = (h3 + d) >>> 0; h4 = (h4 + e) >>> 0;
  }
  return [h0, h1, h2, h3, h4].map((h) => (h >>> 0).toString(16).padStart(8, '0')).join('');
}

// SHA-256 (FIPS 180-4).
function sha256(str) {
  return sha256Bytes(utf8Bytes(str));
}

/** SHA-256 over a raw byte array (used by HMAC). Returns a lowercase hex digest. */
function sha256Bytes(input) {
  const bytes = input.slice();
  const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  let h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const ml = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (let i = 7; i >= 0; i--) bytes.push(Math.floor(ml / Math.pow(2, 8 * i)) & 0xff);
  const rotr = (x, n) => (x >>> n) | (x << (32 - n));
  for (let i = 0; i < bytes.length; i += 64) {
    const w = new Array(64);
    for (let j = 0; j < 16; j++)
      w[j] = ((bytes[i + j * 4] << 24) | (bytes[i + j * 4 + 1] << 16) | (bytes[i + j * 4 + 2] << 8) | bytes[i + j * 4 + 3]) >>> 0;
    for (let j = 16; j < 64; j++) {
      const s0 = rotr(w[j - 15], 7) ^ rotr(w[j - 15], 18) ^ (w[j - 15] >>> 3);
      const s1 = rotr(w[j - 2], 17) ^ rotr(w[j - 2], 19) ^ (w[j - 2] >>> 10);
      w[j] = (w[j - 16] + s0 + w[j - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, hh] = h;
    for (let j = 0; j < 64; j++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (hh + S1 + ch + K[j] + w[j]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      hh = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    h = [h[0] + a, h[1] + b, h[2] + c, h[3] + d, h[4] + e, h[5] + f, h[6] + g, h[7] + hh].map((x) => x >>> 0);
  }
  return h.map((x) => x.toString(16).padStart(8, '0')).join('');
}

/** rngFor, with "no secure randomness here" as a #VALUE! rather than a throw. */
function safeRng(ctx) {
  const rng = rngFor(ctx);
  if (rng !== secureUnit) return rng;
  try {
    secureUnit();
    return rng;
  } catch {
    return valueError();
  }
}

// --- catalog --------------------------------------------------------------

const randomHashEncode = {
  RANDOM: {
    category: CATEGORY,
    aliases: ['RAND'],
    generateOnce: true,
    minArgs: 0,
    maxArgs: 2,
    fn: (args, ctx) => {
      const from = args.length > 0 ? toNumber(args[0]) : 0;
      const to = args.length > 1 ? toNumber(args[1]) : 1;
      if (isError(from)) return from;
      if (isError(to)) return to;
      const lo = from ?? 0;
      const hi = to ?? 1;
      const rng = safeRng(ctx);
      if (isError(rng)) return rng;
      return lo + rng() * (hi - lo);
    },
  },
  UUID: {
    category: CATEGORY,
    aliases: ['GUID'],
    generateOnce: true,
    minArgs: 0,
    maxArgs: 0,
    fn: (_args, ctx) => {
      if (!(ctx && (typeof ctx.rng === 'function' || ctx.randomSeed != null))) {
        const source = typeof globalThis !== 'undefined' ? globalThis.crypto : null;
        if (source && typeof source.randomUUID === 'function') return source.randomUUID();
      }
      const rng = safeRng(ctx);
      if (isError(rng)) return rng;
      return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (rng() * 16) | 0;
        const v = c === 'x' ? r : (r & 0x3) | 0x8;
        return v.toString(16);
      });
    },
  },
  MD5: { category: CATEGORY, minArgs: 1, maxArgs: 1, fn: (args) => hashFn(args[0], md5) },
  SHA1: { category: CATEGORY, minArgs: 1, maxArgs: 1, fn: (args) => hashFn(args[0], sha1) },
  SHA256: { category: CATEGORY, minArgs: 1, maxArgs: 1, fn: (args) => hashFn(args[0], sha256) },
  CRC32: { category: CATEGORY, minArgs: 1, maxArgs: 1, fn: (args) => hashFn(args[0], crc32) },
  BASE64: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const s = toText(args[0]);
      if (isError(s)) return s;
      const mode = args.length > 1 ? String(toText(args[1])).toLowerCase() : 'encode';
      if (mode === 'decode') return base64Decode(s);
      return base64Encode(s);
    },
  },
  URLENCODE: {
    category: CATEGORY,
    // `ENCODE_URL_COMPONENT` is Airtable's spelling, added as an alias rather
    // than as a second function: two implementations of one encoding is how
    // they come to disagree about a `+`.
    aliases: ['ENCODE_URL', 'ENCODEURL', 'URL_ENCODE', 'ENCODE_URL_COMPONENT'],
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const s = toText(args[0]);
      if (isError(s)) return s;
      const mode = args.length > 1 ? String(toText(args[1])).toLowerCase() : 'encode';
      try {
        return mode === 'decode' ? decodeURIComponent(s) : encodeURIComponent(s);
      } catch {
        return valueError('Malformed URL component');
      }
    },
  },
  GENERATEPASSWORD: {
    category: CATEGORY,
    aliases: ['GENERATE_PASSWORD'],
    generateOnce: true,
    minArgs: 0,
    maxArgs: 2,
    fn: (args, ctx) => {
      const len = args.length > 0 && !isBlank(args[0]) ? Math.trunc(toNumber(args[0]) ?? 16) : 16;
      const alphabet =
        args.length > 1 && !isBlank(args[1])
          ? toText(args[1])
          : 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*';
      // The step budget counts AST nodes, not iterations inside a function, so
      // the loop bound is enforced here.
      if (len > MAX_PASSWORD_LENGTH) return valueError();
      const chars = Array.from(String(alphabet));
      if (!chars.length) return valueError();
      const rng = safeRng(ctx);
      if (isError(rng)) return rng;
      let out = '';
      for (let i = 0; i < Math.max(1, len); i++) {
        out += chars[Math.floor(rng() * chars.length)];
      }
      return out;
    },
  },
};

function hashFn(value, fn) {
  const s = toText(value);
  if (isError(s)) return s;
  return fn(s);
}

export default randomHashEncode;
/**
 * SHA-256 hex of bytes (Uint8Array / ArrayBuffer / string), without requiring a
 * secure context. `crypto.subtle` exists only on https and localhost, so a
 * self-hosted deployment reached over plain http:// on a LAN address would throw
 * a TypeError; this uses subtle when it is there and the pure implementation when
 * it is not.
 */
async function sha256Hex(input) {
  const bytes = typeof input === 'string' ? utf8Bytes(input)
    : input instanceof Uint8Array ? input : new Uint8Array(input);
  const subtle = typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.subtle;
  if (subtle && typeof subtle.digest === 'function') {
    try {
      return [...new Uint8Array(await subtle.digest('SHA-256', bytes))].map((b) => b.toString(16).padStart(2, '0')).join('');
    } catch { /* a cross-realm buffer or a restricted context: use the pure digest */ }
  }
  return sha256Bytes(Array.from(bytes));
}

export { md5, sha1, sha1Bytes, sha256, sha256Bytes, sha256Hex, crc32, base64Encode, base64Decode, MersenneTwister, utf8Bytes };
