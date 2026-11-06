//
// `tsc --checkJs` follows imports out of the checked set, so this file is
// reached from modules that ARE in scope. Its remaining findings are two known,
// benign shapes: `date - date` arithmetic, which JavaScript resolves through
// valueOf() and TypeScript refuses to infer, and `@param {object}` JSDoc that
// understates a parameter's real shape. Neither is a defect; both are work.
//
// Staged deliberately rather than silenced forever — this comment is what the
// next increment deletes. See tsconfig.json.
/**
 * Text functions (docs/formulas.md:87-114) plus Appdor originals `soundex`,
 * `occurance`, and `same` (text.md:20,35,44).
 *
 * Regex functions catch invalid patterns (returning #VALUE!) and cap input
 * length to bound catastrophic backtracking (REQ security/sandboxing).
 */

import { isError, valueError } from './errors.js';
import { toText, toNumber, isBlank, toBool } from './values.js';
import { compileSafePattern } from '../validation/safe-pattern.js';
// The Text FIELD's casing lives in one place; CASING() shares it so a formula
// and a column configured the same way cannot disagree about word boundaries.
import { applyCasing, words, CASING_MODES } from '../fields/text-casing.js';

const CATEGORY = 'text';
/**
 * Exported because `REPEAT` uses it as a RESULT ceiling rather than an input
 * one, and the SQL compiler has to answer NULL at exactly the count this
 * answers `#VALUE!` at — see `sql-compiler.js`. Two hand-copied 100,000s that
 * drift apart are a divergence no test would name.
 */
export const MAX_REGEX_INPUT = 100_000;

/** Control characters CLEAN strips, minus the three that are legal whitespace. */
const CONTROL_CHARS = new RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]', 'g');

function str(v) {
  const t = toText(v);
  return isError(t) ? t : t;
}

function safeRegex(pattern, flags) {
  const r = compileSafePattern(String(pattern), flags);
  if ('re' in r) return r.re;
  // Backtracking shapes (nested quantifiers, back-references) are refused, not
  // run: one cell can otherwise pin the thread for minutes.
  return valueError(`Invalid regular expression: ${pattern}`);
}

// Linear: the dot is excluded from the domain labels, so a run of dots cannot
// be split two ways. Length-guarded at the call site (RFC 5321: 254-320).
const EMAIL_RE = /^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$/;
const URL_RE = /^(https?:\/\/)?([\w-]+\.)+[\w-]+(\/[^\s]*)?$/i;
const MAX_EMAIL_LENGTH = 320;
const MAX_URL_LENGTH = 2048;

function soundex(s) {
  const a = s.toUpperCase().replace(/[^A-Z]/g, '');
  if (!a) return '';
  const codes = { B: 1, F: 1, P: 1, V: 1, C: 2, G: 2, J: 2, K: 2, Q: 2, S: 2, X: 2, Z: 2, D: 3, T: 3, L: 4, M: 5, N: 5, R: 6 };
  let result = a[0];
  let prev = codes[a[0]] || 0;
  for (let i = 1; i < a.length && result.length < 4; i++) {
    const code = codes[a[i]] || 0;
    if (code !== 0 && code !== prev) result += code;
    // H and W do not reset the previous code; vowels do.
    if (a[i] !== 'H' && a[i] !== 'W') prev = code;
  }
  return (result + '000').slice(0, 4);
}

const text = {
  CHAR: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = toNumber(args[0]);
      if (isError(n)) return n;
      if (n === null) return '';
      return String.fromCharCode(Math.trunc(n));
    },
  },
  UNICHAR: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = toNumber(args[0]);
      if (isError(n)) return n;
      if (n === null) return '';
      return String.fromCodePoint(Math.trunc(n));
    },
  },
  CODE: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      return s.length ? s.charCodeAt(0) : valueError('CODE of empty text');
    },
  },
  UNICODE: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      return s.length ? s.codePointAt(0) : valueError('UNICODE of empty text');
    },
  },
  CONCATENATE: {
    category: CATEGORY,
    aliases: ['CONCAT'],
    minArgs: 1,
    fn: (args) => {
      let out = '';
      for (const a of args) {
        if (Array.isArray(a)) {
          for (const x of a) out += isBlank(x) ? '' : toText(x);
        } else {
          out += isBlank(a) ? '' : toText(a);
        }
      }
      return out;
    },
  },
  CONTAINS: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const hay = str(args[0]);
      const needle = str(args[1]);
      if (isError(hay)) return hay;
      if (isError(needle)) return needle;
      return hay.includes(needle);
    },
  },
  EXACT: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => str(args[0]) === str(args[1]),
  },
  // Appdor original: case-insensitive equality (text.md:44).
  SAME: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const a = str(args[0]);
      const b = str(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      const caseSensitive = args.length > 2 ? Boolean(args[2]) : false;
      return caseSensitive ? a === b : a.toLowerCase() === b.toLowerCase();
    },
  },
  FIND: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => findImpl(args, true),
  },
  SEARCH: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => findImpl(args, false),
  },
  ISEMAIL: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      return typeof s === 'string' && s.length <= MAX_EMAIL_LENGTH && EMAIL_RE.test(s);
    },
  },
  ISURL: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      return typeof s === 'string' && s.length <= MAX_URL_LENGTH && URL_RE.test(s);
    },
  },
  LEFT: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const n = args.length > 1 ? toNumber(args[1]) : 1;
      if (isError(n)) return n;
      return s.slice(0, Math.max(0, Math.trunc(n ?? 1)));
    },
  },
  RIGHT: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const n = args.length > 1 ? toNumber(args[1]) : 1;
      if (isError(n)) return n;
      const k = Math.max(0, Math.trunc(n ?? 1));
      return k === 0 ? '' : s.slice(-k);
    },
  },
  MID: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const start = toNumber(args[1]);
      const len = toNumber(args[2]);
      if (isError(start)) return start;
      if (isError(len)) return len;
      const from = Math.max(0, Math.trunc(start) - 1);
      return s.substr(from, Math.max(0, Math.trunc(len)));
    },
  },
  LEN: {
    category: CATEGORY,
    aliases: ['LENGTH'],
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      return isError(s) ? s : s.length;
    },
  },
  LOWER: { category: CATEGORY, aliases: ['LOWERCASE'], minArgs: 1, maxArgs: 1, fn: (args) => { const s = str(args[0]); return isError(s) ? s : s.toLowerCase(); } },
  UPPER: { category: CATEGORY, aliases: ['UPPERCASE'], minArgs: 1, maxArgs: 1, fn: (args) => { const s = str(args[0]); return isError(s) ? s : s.toUpperCase(); } },
  PROPER: {
    category: CATEGORY,
    aliases: ['PROPERCASE'],
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      return s.replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\B\w/g, (c) => c.toLowerCase());
    },
  },
  REVERSE: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      return isError(s) ? s : [...s].reverse().join('');
    },
  },
  REPEAT: {
    category: CATEGORY,
    aliases: ['REPT'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const n = toNumber(args[1]);
      if (isError(n)) return n;
      const count = Math.max(0, Math.trunc(n ?? 0));
      if (s.length * count > MAX_REGEX_INPUT) return valueError('REPEAT result too large');
      return s.repeat(count);
    },
  },
  REPLACE: {
    category: CATEGORY,
    minArgs: 4,
    maxArgs: 4,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const start = toNumber(args[1]);
      const count = toNumber(args[2]);
      const repl = str(args[3]);
      if (isError(start)) return start;
      if (isError(count)) return count;
      if (isError(repl)) return repl;
      const from = Math.max(0, Math.trunc(start) - 1);
      return s.slice(0, from) + repl + s.slice(from + Math.max(0, Math.trunc(count)));
    },
  },
  SUBSTITUTE: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 4,
    fn: (args) => {
      const s = str(args[0]);
      const oldText = str(args[1]);
      const newText = str(args[2]);
      if (isError(s)) return s;
      if (isError(oldText)) return oldText;
      if (isError(newText)) return newText;
      if (oldText === '') return s;
      if (args.length > 3) {
        const instance = toNumber(args[3]);
        if (isError(instance)) return instance;
        let idx = -1;
        let count = 0;
        const target = Math.trunc(instance);
        while ((idx = s.indexOf(oldText, idx + 1)) !== -1) {
          count++;
          if (count === target) {
            return s.slice(0, idx) + newText + s.slice(idx + oldText.length);
          }
        }
        return s;
      }
      return s.split(oldText).join(newText);
    },
  },
  TEXTJOIN: {
    category: CATEGORY,
    minArgs: 3,
    fn: (args) => {
      const delim = str(args[0]);
      if (isError(delim)) return delim;
      const ignoreEmpty = Boolean(args[1]);
      const parts = [];
      const push = (v) => {
        if (isBlank(v)) {
          if (!ignoreEmpty) parts.push('');
        } else {
          parts.push(toText(v));
        }
      };
      for (let i = 2; i < args.length; i++) {
        const a = args[i];
        if (Array.isArray(a)) a.forEach(push);
        else push(a);
      }
      return parts.join(delim);
    },
  },
  TRIM: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      return s.replace(/\s+/g, ' ').trim();
    },
  },
  WORDCOUNT: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const t = s.trim();
      return t === '' ? 0 : t.split(/\s+/).length;
    },
  },
  // Appdor original: count non-overlapping occurrences (text.md:20).
  OCCURANCE: {
    category: CATEGORY,
    aliases: ['OCCURRENCE'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const s = str(args[0]);
      const sub = str(args[1]);
      if (isError(s)) return s;
      if (isError(sub)) return sub;
      if (sub === '') return 0;
      let count = 0;
      let idx = -1;
      while ((idx = s.indexOf(sub, idx + 1)) !== -1) count++;
      return count;
    },
  },
  SOUNDEX: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      return isError(s) ? s : soundex(s);
    },
  },
  REGEXMATCH: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      if (s.length > MAX_REGEX_INPUT) return valueError('Input too large for regex');
      const re = safeRegex(str(args[1]));
      // Same check as `isError`, spelled so the RegExp half narrows.
      if (!(re instanceof RegExp)) return re;
      return re.test(s);
    },
  },
  REGEXEXTRACT: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      if (s.length > MAX_REGEX_INPUT) return valueError('Input too large for regex');
      const re = safeRegex(str(args[1]));
      if (isError(re)) return re;
      const m = s.match(re);
      if (!m) return '';
      const group = args.length > 2 ? Math.trunc(toNumber(args[2]) ?? 0) : m.length > 1 ? 1 : 0;
      return m[group] ?? '';
    },
  },
  REGEXREPLACE: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      if (s.length > MAX_REGEX_INPUT) return valueError('Input too large for regex');
      const re = safeRegex(str(args[1]), 'g');
      if (isError(re)) return re;
      const repl = str(args[2]);
      if (isError(repl)) return repl;
      return s.replace(re, repl);
    },
  },

  // --- the remaining text names the field specs list ----------------------

  STARTS_WITH: affix('STARTS_WITH', (hay, needle) => hay.startsWith(needle)),
  ENDS_WITH: affix('ENDS_WITH', (hay, needle) => hay.endsWith(needle)),

  /**
   * Recase, sharing the Text field's own eleven modes.
   *
   * The same module the column uses, so `CASING({Name}, 'kebab')` and a column
   * configured to kebab-case cannot disagree about where a word starts — which
   * they would within a week if this had its own splitter.
   */
  CASING: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const mode = str(args[1]);
      if (isError(mode)) return mode;
      if (!CASING_MODES.includes(mode)) {
        return valueError(`Unknown casing mode: ${mode}. One of: ${CASING_MODES.join(', ')}`);
      }
      return applyCasing(s, mode);
    },
  },

  /** Strip the control characters that survive a copy-paste out of a PDF. */
  CLEAN: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      // Built from escape sequences, never typed as literal control characters:
      // those put raw bytes in the source, which tests/source-is-text.test.js
      // refuses — and rightly, since git diff and grep cannot read them.
      // Tab, newline and carriage return are KEPT; they are the whitespace a
      // long-text value is allowed to contain.
      return s.replace(CONTROL_CHARS, '');
    },
  },

  // ENCODE_URL_COMPONENT is an alias on the existing URLENCODE in
  // random-hash-encode.js — see the note there. Only the decode half needs a
  // name of its own, because `URLENCODE(s, 'decode')` is not a name anyone
  // would look for.
  DECODE_URL_COMPONENT: {
    category: CATEGORY,
    aliases: ['DECODEURL', 'URLDECODE'],
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      try {
        return decodeURIComponent(s);
      } catch {
        // A stray `%` is not a decodable escape. Returning #VALUE! rather than
        // the input says the string was not what it claimed to be.
        return valueError(`Not a valid URL-encoded string: ${s}`);
      }
    },
  },

  /**
   * Initials: the first letter of each word, up to three.
   *
   * Three because this is what an avatar shows, and a fourth letter does not
   * fit in the circle it is drawn in.
   */
  INITIALS: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const upper = args.length > 1 ? toBool(args[1]) : true;
      if (isError(upper)) return upper;
      const letters = words(s).slice(0, 3).map((w) => w.charAt(0)).join('');
      return upper ? letters.toLocaleUpperCase() : letters;
    },
  },

  // Padding. PAD centres; PADLEFT and PADRIGHT are the spreadsheet spellings of
  // padStart and padEnd, and are named for the side the PADDING goes on.
  PADLEFT: {
    category: CATEGORY,
    aliases: ['PADSTART'],
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => padWith(args, (s, width, fill) => s.padStart(width, fill)),
  },
  PADRIGHT: {
    category: CATEGORY,
    aliases: ['PADEND'],
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => padWith(args, (s, width, fill) => s.padEnd(width, fill)),
  },
  PAD: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => padWith(args, (s, width, fill) => {
      const total = width - s.length;
      if (total <= 0) return s;
      // The odd character goes on the right, so `PAD('x', 4)` is ' x  ' — the
      // convention every centring implementation shares.
      const left = Math.floor(total / 2);
      return s.padStart(s.length + left, fill).padEnd(width, fill);
    }),
  },

  /**
   * PART: the nth segment of a delimited string, 1-based.
   *
   * A negative index counts from the end, which is how you take the extension
   * off a filename without knowing how many dots it has.
   */
  PART: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      const delimiter = args.length > 2 ? str(args[1]) : ' ';
      if (isError(delimiter)) return delimiter;
      const indexArg = toNumber(args[args.length > 2 ? 2 : 1]);
      if (isError(indexArg)) return indexArg;
      const segments = s.split(delimiter);
      const n = Math.trunc(indexArg ?? 0);
      if (n === 0) return valueError('PART is 1-based; there is no part 0');
      const picked = n < 0 ? segments[segments.length + n] : segments[n - 1];
      return picked === undefined ? '' : picked;
    },
  },

  // --- extractors ---------------------------------------------------------
  //
  // Each returns an ARRAY, because "the emails in this text" is a list even
  // when it has one member — a function that returns a bare string for one hit
  // and an array for two forces every caller to test which happened.

  EXTRACTEMAILS: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      if (s.length > MAX_REGEX_INPUT) return valueError('Input too large for regex');
      return extractEmails(s);
    },
  },
  EXTRACTNUMBERS: extractor(/-?\d+(?:\.\d+)?/g, (m) => Number(m)),
  EXTRACTPRICES: extractor(/[$€£¥]\s?-?\d+(?:[.,]\d+)?|-?\d+(?:[.,]\d+)?\s?[$€£¥]/g),
  EXTRACTHASHTAGS: extractor(/#[\p{L}\p{N}_]+/gu),
  EXTRACTPHONENUMBERS: extractor(/\+?\d[\d\s().-]{6,}\d/g, (m) => m.trim()),
  EXTRACTDOMAINS: extractor(/(?:https?:\/\/)?(?:[\w-]+\.)+[a-z]{2,}(?=[/\s]|$)/gi),
  EXTRACTDATES: extractor(/\d{4}-\d{2}-\d{2}|\d{1,2}\/\d{1,2}\/\d{2,4}|\d{1,2}\.\d{1,2}\.\d{2,4}/g),

  /** EXTRACT(text, pattern): the generic form the others specialise. */
  EXTRACT: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      if (s.length > MAX_REGEX_INPUT) return valueError('Input too large for regex');
      const re = safeRegex(str(args[1]), 'g');
      if (isError(re)) return re;
      return [...s.matchAll(re)].map((m) => (m[1] !== undefined ? m[1] : m[0]));
    },
  },
};

/** STARTS_WITH / ENDS_WITH share everything but the test. */
function affix(name, test) {
  return {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const hay = str(args[0]);
      const needle = str(args[1]);
      if (isError(hay)) return hay;
      if (isError(needle)) return needle;
      // Case-insensitive by default: a person filtering for names starting
      // "mac" means MacDonald too, and the strict form is one argument away.
      const caseSensitive = args.length > 2 ? toBool(args[2]) : false;
      if (isError(caseSensitive)) return caseSensitive;
      return caseSensitive ? test(hay, needle) : test(hay.toLowerCase(), needle.toLowerCase());
    },
  };
}

/** The three PAD forms differ only in where the fill goes. */
function padWith(args, place) {
  const s = str(args[0]);
  if (isError(s)) return s;
  const widthArg = toNumber(args[1]);
  if (isError(widthArg)) return widthArg;
  const fill = args.length > 2 ? str(args[2]) : ' ';
  if (isError(fill)) return fill;
  if (!fill) return valueError('PAD needs a non-empty fill character');
  const width = Math.trunc(widthArg ?? 0);
  // A width shorter than the value returns it whole rather than truncating:
  // padding is for making a value longer, and silently cutting it is a
  // different operation with a different name.
  return width <= s.length ? s : place(s, width, fill);
}

const EMAIL_EXCLUDED = /[\s@<>()[\]{},;:"']/;

/**
 * Every email in `s`, found by anchoring on each '@' and expanding both ways.
 * The previous single regex rescanned to the end of a long '@'-free run from
 * every start position (quadratic); each character here is visited a bounded
 * number of times, because runs are delimited by the excluded set, '@' included.
 */
function extractEmails(s) {
  const out = [];
  let consumed = 0;
  for (let at = s.indexOf('@'); at !== -1; at = s.indexOf('@', at + 1)) {
    let start = at;
    while (start > consumed && !EMAIL_EXCLUDED.test(s[start - 1])) start -= 1;
    if (start === at) continue;
    let end = at + 1;
    while (end < s.length && !EMAIL_EXCLUDED.test(s[end])) end += 1;
    // The domain is the run after '@'; it must end in .<2+ letters>. The regex
    // was greedy, so take the LAST dot whose tail starts with two letters.
    let stop = -1;
    for (let q = end - 1; q > at + 1; q -= 1) {
      if (s[q] !== '.') continue;
      let k = q + 1;
      while (k < end && /[a-z]/i.test(s[k])) k += 1;
      if (k - (q + 1) >= 2) { stop = k; break; }
    }
    if (stop === -1) continue;
    out.push(s.slice(start, stop));
    consumed = stop;
  }
  return out;
}

/** An extractor: every match, as an array, optionally mapped. */
function extractor(pattern, map) {
  return {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const s = str(args[0]);
      if (isError(s)) return s;
      if (s.length > MAX_REGEX_INPUT) return valueError('Input too large for regex');
      const found = String(s).match(pattern) || [];
      return map ? found.map(map) : found;
    },
  };
}

function findImpl(args, caseSensitive) {
  const needle = str(args[0]);
  const hay = str(args[1]);
  if (isError(needle)) return needle;
  if (isError(hay)) return hay;
  const start = args.length > 2 ? toNumber(args[2]) : 1;
  if (isError(start)) return start;
  const from = Math.max(0, Math.trunc((start ?? 1)) - 1);
  const idx = caseSensitive
    ? hay.indexOf(needle, from)
    : hay.toLowerCase().indexOf(needle.toLowerCase(), from);
  return idx === -1 ? 0 : idx + 1;
}

export default text;
