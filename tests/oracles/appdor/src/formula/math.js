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
 * Mathematical functions (docs/formulas.md:41-85) plus Appdor statistical
 * originals: `kurtosis`, `skewness`, `logn`, `is_normal` (math.md:26-54).
 *
 * Aggregation functions skip blanks and flatten array arguments. Non-aggregation
 * functions propagate blank as blank (REQ-FORMULAENGINE-09).
 */

import { isError, numError, divZero } from './errors.js';
// For the hover-explanation messages a FormulaError carries (errors.js: the
// renderer shows `message` as the cell's hover title). The error CODES —
// #DIV/0!, #NUM! and the rest — are spreadsheet convention and stay English
// everywhere; the sentences under them are copy and translate. Keyed with
// {fn}/{min} placeholders where several functions share one sentence shape,
// resolved at evaluation time so the message follows the active language.
//
// INJECTED, not imported. This module sits on the REST host's import chain
// (rest-host -> api/index -> views/query -> formula/*), and that service must
// never reach src/language.js — tests/api/rest-host.test.js walks the graph
// and refuses the edge. So the UI hands the translator in at boot
// (src/boot.js), and a headless caller that never does gets a terse
// code-shaped message built from the key's leaf and the arguments — which is
// the right shape for an API response anyway.
let translate = null;
/** Wire the UI's t() in. Boot-time, UI only; services never call it. */
export function setFormulaTranslator(fn) { translate = fn; }
const msg = (key, subs) => (translate
  ? translate(key, null, subs)
  : `${key.split('.').pop()}: ${Object.values(subs || {}).join(', ')}`);
import { toNumber, toText, isBlank, collectNumbers, looseEquals, flattenValues } from './values.js';

const CATEGORY = 'math';

// --- helpers --------------------------------------------------------------

/** Coerce one arg to a number; blank -> null, error passes through. */
function num(v) {
  return toNumber(v);
}

/** A single-number function that propagates blank/error. */
function unaryNum(fn) {
  return {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      const r = fn(n);
      // ASIN(2), LOG10(-1), EXP(1000) ... are #NUM!, not NaN/Infinity that a
      // cell would store and JSON.stringify would turn into null.
      if (typeof r === 'number' && !Number.isFinite(r)) return numError(msg('formula.error.invalidResult', { fn: 'math' }));
      return r;
    },
  };
}

/** Flatten args to a numeric array; returns FormulaError if any element errors. */
function numbers(args) {
  try {
    return collectNumbers(args);
  } catch (e) {
    if (isError(e)) return e;
    throw e;
  }
}

function sum(nums) {
  let s = 0;
  for (const n of nums) s += n;
  return s;
}

function mean(nums) {
  return nums.length ? sum(nums) / nums.length : 0;
}

/** COUNTIF / SUMIF / AVERAGEIF criterion: the same rules as the *IFS family. */
function makeMatcher(criteria) {
  return (value) => matchesCriterion(value, criteria);
}

function variance(nums, population) {
  const n = nums.length;
  if (n < (population ? 1 : 2)) return numError(msg('formula.error.varianceNeedsData'));
  const m = mean(nums);
  let ss = 0;
  for (const x of nums) ss += (x - m) * (x - m);
  return ss / (population ? n : n - 1);
}

function factorial(n) {
  if (n < 0 || !Number.isInteger(n)) return numError(msg('formula.error.factNonNegativeInteger'));
  // 171! already overflows a double; refuse before looping, so FACT(1e12)
  // answers at once instead of spinning.
  if (n > 170) return numError(msg('formula.error.invalidResult', { fn: 'FACT' }));
  let f = 1;
  for (let i = 2; i <= n; i++) f *= i;
  return f;
}

/**
 * Round |n| * 10^d with `pick` (round / floor / ceil), sign restored, so ties go
 * away from zero and binary noise (4.35 * 100 = 434.99999999999994) cannot flip
 * a digit: the product is first trimmed to 15 significant digits.
 */
function scaleRound(n, d, pick) {
  const f = 10 ** d;
  const scaled = Number((Math.abs(n) * f).toPrecision(15));
  return Math.sign(n) * pick(scaled) / f || 0;
}

// Anderson–Darling normality test (used by is_normal). Returns true when the
// sample is consistent with normality at α = 0.05.
function isNormalAD(nums) {
  const n = nums.length;
  if (n < 8) return numError(msg('formula.error.needsAtLeastPoints', { fn: 'is_normal', min: 8 }));
  const m = mean(nums);
  // n >= 8 above, so variance cannot take its "not enough data points" branch.
  const sd = Math.sqrt(/** @type {number} */ (variance(nums, false)));
  if (sd === 0) return true; // constant sample: treat as (degenerately) normal
  const sorted = [...nums].sort((a, b) => a - b);
  const cdf = (x) => 0.5 * (1 + erf((x - m) / (sd * Math.SQRT2)));
  let s = 0;
  for (let i = 0; i < n; i++) {
    const zi = cdf(sorted[i]);
    const zn = cdf(sorted[n - 1 - i]);
    s += (2 * (i + 1) - 1) * (Math.log(zi) + Math.log(1 - zn));
  }
  let a2 = -n - s / n;
  // Adjust for estimated mean/variance (D'Agostino).
  a2 *= 1 + 0.75 / n + 2.25 / (n * n);
  return a2 < 0.752; // critical value at α = 0.05
}

function erf(x) {
  // Abramowitz & Stegun 7.1.26 approximation. The polynomial variable the
  // reference calls t is named u here, because this module imports t() for
  // its error messages.
  const u = 1 / (1 + 0.3275911 * Math.abs(x));
  const y =
    1 -
    ((((1.061405429 * u - 1.453152027) * u + 1.421413741) * u - 0.284496736) * u +
      0.254829592) *
      u *
      Math.exp(-x * x);
  return x >= 0 ? y : -y;
}

// --- catalog --------------------------------------------------------------

const math = {
  SUM: { category: CATEGORY, minArgs: 1, fn: (args) => { const n = numbers(args); return isError(n) ? n : sum(n); } },
  AVERAGE: {
    category: CATEGORY,
    aliases: ['AVG', 'MEAN'],
    minArgs: 1,
    fn: (args) => {
      const n = numbers(args);
      if (isError(n)) return n;
      if (n.length === 0) return divZero(msg('formula.error.fnOfNoNumbers', { fn: 'AVERAGE' }));
      return mean(n);
    },
  },
  COUNT: { category: CATEGORY, minArgs: 1, fn: (args) => { const n = numbers(args); return isError(n) ? n : n.length; } },
  COUNTA: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => flattenValues(args).filter((v) => !isBlank(v)).length,
  },
  COUNTBLANK: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => flattenValues(args).filter((v) => isBlank(v)).length,
  },
  COUNTIF: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const match = makeMatcher(args[1]);
      return flattenValues([args[0]]).filter((v) => match(v)).length;
    },
  },
  SUMIF: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const range = flattenValues([args[0]]);
      const match = makeMatcher(args[1]);
      const sumRange = args.length > 2 ? flattenValues([args[2]]) : range;
      let total = 0;
      for (let i = 0; i < range.length; i++) {
        if (match(range[i])) {
          const n = toNumber(sumRange[i]);
          if (isError(n)) return n;
          if (n !== null) total += n;
        }
      }
      return total;
    },
  },
  AVERAGEIF: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const range = flattenValues([args[0]]);
      const match = makeMatcher(args[1]);
      const avgRange = args.length > 2 ? flattenValues([args[2]]) : range;
      let total = 0;
      let count = 0;
      for (let i = 0; i < range.length; i++) {
        if (match(range[i])) {
          const n = toNumber(avgRange[i]);
          if (isError(n)) return n;
          if (n !== null) {
            total += n;
            count++;
          }
        }
      }
      if (count === 0) return divZero(msg('formula.error.fnMatchedNoNumbers', { fn: 'AVERAGEIF' }));
      return total / count;
    },
  },
  MAX: { category: CATEGORY, minArgs: 1, fn: (args) => { const n = numbers(args); if (isError(n)) return n; let m = n[0]; for (const x of n) if (x > m) m = x; return n.length ? m : 0; } },
  MIN: { category: CATEGORY, minArgs: 1, fn: (args) => { const n = numbers(args); if (isError(n)) return n; let m = n[0]; for (const x of n) if (x < m) m = x; return n.length ? m : 0; } },
  MEDIAN: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => {
      const n = numbers(args);
      if (isError(n)) return n;
      if (n.length === 0) return numError(msg('formula.error.fnOfNoNumbers', { fn: 'MEDIAN' }));
      const s = [...n].sort((a, b) => a - b);
      const mid = Math.floor(s.length / 2);
      return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
    },
  },
  MODE: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => {
      const n = numbers(args);
      if (isError(n)) return n;
      const counts = new Map();
      let best = null;
      let bestCount = 1;
      for (const x of n) {
        const c = (counts.get(x) || 0) + 1;
        counts.set(x, c);
        if (c > bestCount) {
          bestCount = c;
          best = x;
        }
      }
      if (best === null) return numError(msg('formula.error.modeNoRepeat'));
      return best;
    },
  },
  STDEV: { category: CATEGORY, minArgs: 1, fn: (args) => { const n = numbers(args); if (isError(n)) return n; const v = variance(n, false); return typeof v === 'number' ? Math.sqrt(v) : v; } },
  STDEVP: { category: CATEGORY, minArgs: 1, fn: (args) => { const n = numbers(args); if (isError(n)) return n; const v = variance(n, true); return typeof v === 'number' ? Math.sqrt(v) : v; } },
  VAR: { category: CATEGORY, minArgs: 1, fn: (args) => { const n = numbers(args); return isError(n) ? n : variance(n, false); } },
  VARP: { category: CATEGORY, minArgs: 1, fn: (args) => { const n = numbers(args); return isError(n) ? n : variance(n, true); } },
  PRODUCT: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => {
      const n = numbers(args);
      if (isError(n)) return n;
      if (n.length === 0) return 0;
      return n.reduce((a, b) => a * b, 1);
    },
  },
  SUMPRODUCT: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => {
      const arrays = args.map((a) => flattenValues([a]));
      const len = Math.max(...arrays.map((a) => a.length));
      let total = 0;
      for (let i = 0; i < len; i++) {
        let p = 1;
        for (const arr of arrays) {
          const n = toNumber(arr[i]);
          if (isError(n)) return n;
          p *= n === null ? 0 : n;
        }
        total += p;
      }
      return total;
    },
  },

  // monday.com arithmetic-as-functions (direct-resolve targets for that dialect).
  ADD: {
    category: CATEGORY,
    aliases: ['PLUS'],
    minArgs: 2,
    fn: (args) => { const n = numbers(args); return isError(n) ? n : sum(n); },
  },
  MINUS: {
    category: CATEGORY,
    aliases: ['SUBTRACT'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const a = num(args[0]);
      const b = num(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (a === null || b === null) return null;
      return a - b;
    },
  },
  MULTIPLY: {
    category: CATEGORY,
    aliases: ['TIMES'],
    minArgs: 2,
    fn: (args) => {
      const n = numbers(args);
      if (isError(n)) return n;
      return n.reduce((a, b) => a * b, 1);
    },
  },
  DIVIDE: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const a = num(args[0]);
      const b = num(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (a === null || b === null) return null;
      if (b === 0) return divZero(msg('formula.error.fnByZero', { fn: 'DIVIDE' }));
      return a / b;
    },
  },

  ABS: unaryNum(Math.abs),
  SIGN: unaryNum(Math.sign),
  SQRT: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      if (n < 0) return numError(msg('formula.error.sqrtNegative'));
      return Math.sqrt(n);
    },
  },
  EXP: unaryNum(Math.exp),
  LN: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      if (n <= 0) return numError(msg('formula.error.fnNeedsPositive', { fn: 'LN' }));
      return Math.log(n);
    },
  },
  LOG: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      const base = args.length > 1 ? num(args[1]) : 10;
      if (isError(base)) return base;
      if (n <= 0 || base <= 0 || base === 1) return numError(msg('formula.error.invalidArguments', { fn: 'LOG' }));
      return Math.log(n) / Math.log(base);
    },
  },
  LOGN: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      const base = num(args[1]);
      if (isError(n)) return n;
      if (isError(base)) return base;
      if (n === null || base === null) return null;
      if (n <= 0 || base <= 0 || base === 1) return numError(msg('formula.error.invalidArguments', { fn: 'LOGN' }));
      return Math.log(n) / Math.log(base);
    },
  },
  POWER: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const b = num(args[0]);
      const e = num(args[1]);
      if (isError(b)) return b;
      if (isError(e)) return e;
      if (b === null || e === null) return null;
      if (b === 0 && e < 0) return divZero(msg('formula.error.fnByZero', { fn: 'POWER' }));
      const r = Math.pow(b, e);
      return Number.isFinite(r) ? r : numError(msg('formula.error.invalidResult', { fn: 'POWER' }));
    },
  },
  MOD: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const a = num(args[0]);
      const b = num(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (a === null || b === null) return null;
      if (b === 0) return divZero(msg('formula.error.fnByZero', { fn: 'MOD' }));
      // Excel MOD result takes the sign of the divisor.
      return a - b * Math.floor(a / b);
    },
  },
  QUOTIENT: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const a = num(args[0]);
      const b = num(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (a === null || b === null) return null;
      if (b === 0) return divZero(msg('formula.error.fnByZero', { fn: 'QUOTIENT' }));
      return Math.trunc(a / b);
    },
  },
  ROUND: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      const d = args.length > 1 ? num(args[1]) : 0;
      if (isError(d)) return d;
      return scaleRound(n, d || 0, Math.round);
    },
  },
  ROUNDUP: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      const d = args.length > 1 ? num(args[1]) : 0;
      if (isError(d)) return d;
      return scaleRound(n, d || 0, Math.ceil);
    },
  },
  ROUNDDOWN: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      const d = args.length > 1 ? num(args[1]) : 0;
      if (isError(d)) return d;
      return scaleRound(n, d || 0, Math.floor);
    },
  },
  CEILING: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      const sig = args.length > 1 ? num(args[1]) : 1;
      if (isError(sig)) return sig;
      if (sig === 0) return 0;
      return Math.ceil(n / sig) * sig;
    },
  },
  FLOOR: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      const sig = args.length > 1 ? num(args[1]) : 1;
      if (isError(sig)) return sig;
      if (sig === 0) return 0;
      return Math.floor(n / sig) * sig;
    },
  },
  PI: { category: CATEGORY, minArgs: 0, maxArgs: 0, fn: () => Math.PI },
  SIN: unaryNum(Math.sin),
  COS: unaryNum(Math.cos),
  TAN: unaryNum(Math.tan),
  ASIN: unaryNum(Math.asin),
  ACOS: unaryNum(Math.acos),
  ATAN: unaryNum(Math.atan),
  ATAN2: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const y = num(args[0]);
      const x = num(args[1]);
      if (isError(y)) return y;
      if (isError(x)) return x;
      return Math.atan2(y, x);
    },
  },
  DEGREES: unaryNum((n) => (n * 180) / Math.PI),
  RADIANS: unaryNum((n) => (n * Math.PI) / 180),
  ISODD: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return false;
      return Math.abs(Math.trunc(n)) % 2 === 1;
    },
  },
  ISEVEN: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return true;
      return Math.abs(Math.trunc(n)) % 2 === 0;
    },
  },
  FACT: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      return factorial(Math.trunc(n));
    },
  },
  COMBIN: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      const k = num(args[1]);
      if (isError(n)) return n;
      if (isError(k)) return k;
      if (n === null || k === null) return null;
      if (k < 0 || n < 0 || k > n) return numError(msg('formula.error.invalidArguments', { fn: 'COMBIN' }));
      const nn = Math.trunc(n);
      const kk = Math.trunc(k);
      let r = 1;
      const kUse = Math.min(kk, nn - kk); // C(n,k) = C(n,n-k): at most n/2 steps
      for (let i = 0; i < kUse; i++) {
        r = (r * (nn - i)) / (i + 1);
        if (!Number.isFinite(r)) return numError(msg('formula.error.invalidResult', { fn: 'COMBIN' }));
      }
      return Math.round(r);
    },
  },
  PERMUT: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      const k = num(args[1]);
      if (isError(n)) return n;
      if (isError(k)) return k;
      if (n === null || k === null) return null;
      if (k < 0 || n < 0 || k > n) return numError(msg('formula.error.invalidArguments', { fn: 'PERMUT' }));
      const nn = Math.trunc(n);
      const kk = Math.trunc(k);
      let r = 1;
      for (let i = 0; i < kk; i++) {
        r *= nn - i;
        if (!Number.isFinite(r)) return numError(msg('formula.error.invalidResult', { fn: 'PERMUT' }));
      }
      return r;
    },
  },

  // Appdor statistical originals.
  KURTOSIS: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => {
      const n = numbers(args);
      if (isError(n)) return n;
      if (n.length < 4) return numError(msg('formula.error.needsAtLeastPoints', { fn: 'KURTOSIS', min: 4 }));
      const m = mean(n);
      const sd = Math.sqrt(/** @type {number} */ (variance(n, false)));
      if (sd === 0) return numError(msg('formula.error.fnZeroVariance', { fn: 'KURTOSIS' }));
      const N = n.length;
      let s4 = 0;
      for (const x of n) s4 += Math.pow((x - m) / sd, 4);
      // Excess kurtosis, sample-corrected (Excel KURT).
      return (
        (N * (N + 1) * s4) / ((N - 1) * (N - 2) * (N - 3)) -
        (3 * (N - 1) * (N - 1)) / ((N - 2) * (N - 3))
      );
    },
  },
  SKEWNESS: {
    category: CATEGORY,
    aliases: ['SKEW'],
    minArgs: 1,
    fn: (args) => {
      const n = numbers(args);
      if (isError(n)) return n;
      if (n.length < 3) return numError(msg('formula.error.needsAtLeastPoints', { fn: 'SKEWNESS', min: 3 }));
      const m = mean(n);
      const sd = Math.sqrt(/** @type {number} */ (variance(n, false)));
      if (sd === 0) return numError(msg('formula.error.fnZeroVariance', { fn: 'SKEWNESS' }));
      const N = n.length;
      let s3 = 0;
      for (const x of n) s3 += Math.pow((x - m) / sd, 3);
      return (N / ((N - 1) * (N - 2))) * s3;
    },
  },
  IS_NORMAL: {
    category: CATEGORY,
    aliases: ['ISNORMAL'],
    minArgs: 1,
    fn: (args) => {
      const n = numbers(args);
      if (isError(n)) return n;
      return isNormalAD(n);
    },
  },

  // --- the remaining math names the field specs list ----------------------
  //
  // Mostly thin, and thin is the point: `ARCSIN` is `ASIN` under the name half
  // the spreadsheets in the spec use, and a user who types the name they know
  // should not get #NAME?. They are registered as real entries rather than as
  // aliases only where the SEMANTICS differ (INT floors, TRUNC truncates — and
  // they disagree on every negative number).

  ARCSIN: unaryNum(Math.asin),
  ARCCOS: unaryNum(Math.acos),
  ARCTAN: unaryNum(Math.atan),
  LOG10: unaryNum(Math.log10),
  LOG2: unaryNum(Math.log2),

  // INT floors toward negative infinity; TRUNC cuts toward zero. For -2.5 that
  // is -3 and -2. Aliasing them to each other would be wrong for every negative.
  INT: unaryNum(Math.floor),
  TRUNC: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      const places = args.length > 1 ? num(args[1]) : 0;
      if (isError(places)) return places;
      return scaleRound(n, Math.trunc(places || 0), Math.floor);
    },
  },

  // EVEN and ODD round AWAY from zero, as every spreadsheet defines them:
  // EVEN(1.5) is 2, EVEN(-1.5) is -2.
  EVEN: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      if (n === 0) return 0;
      const away = Math.ceil(Math.abs(n) / 2) * 2;
      return n < 0 ? -away : away;
    },
  },
  ODD: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = num(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      if (n === 0) return 1;
      const magnitude = Math.abs(n);
      let away = Math.ceil(magnitude);
      if (away % 2 === 0) away += 1;
      return n < 0 ? -away : away;
    },
  },

  RANDBETWEEN: {
    category: CATEGORY,
    // `generateOnce`, not `volatile`: a random number that changes on every
    // render makes a cell nobody can act on, and the registry already draws
    // that distinction for UUID and RANDOM.
    generateOnce: true,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const lo = num(args[0]);
      const hi = num(args[1]);
      if (isError(lo)) return lo;
      if (isError(hi)) return hi;
      if (lo === null || hi === null) return null;
      const low = Math.ceil(Math.min(lo, hi));
      const high = Math.floor(Math.max(lo, hi));
      if (high < low) return numError(msg('formula.error.randbetweenNoInteger'));
      return low + Math.floor(Math.random() * (high - low + 1));
    },
  },

  // Counting. COUNTALL counts everything including blanks; COUNTA counts
  // non-blank; COUNT counts numbers. Three names, three different answers, and
  // the specs list all three.
  COUNTALL: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => flattenValues(args).length,
  },
  COUNTUNIQUE: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => {
      // Keyed by the normalised value (lower-cased text, as looseEquals
      // compares) so this is linear, not quadratic.
      const seen = new Set();
      for (const v of flattenValues(args)) {
        if (isBlank(v)) continue;
        seen.add(uniqueKey(v));
      }
      return seen.size;
    },
  },
  // Smartsheet's COUNTM counts multi-select entries across the range.
  COUNTM: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => {
      let total = 0;
      for (const v of flattenValues(args)) {
        if (isBlank(v)) continue;
        total += Array.isArray(v) ? v.length : String(v).split(',').filter((p) => p.trim()).length;
      }
      return total;
    },
  },

  // Nth largest / smallest. 1-based, as every spreadsheet defines them.
  LARGE: nthValue('LARGE', (a, b) => b - a),
  SMALL: nthValue('SMALL', (a, b) => a - b),

  // The *IFS family. One criteria pair per two trailing args, ALL of which must
  // match — which is the only thing separating them from their *IF singulars.
  SUMIFS: conditionalAggregate('SUMIFS', (picked) => picked.reduce((a, b) => a + b, 0)),
  AVERAGEIFS: conditionalAggregate('AVERAGEIFS', (picked) => (
    picked.length ? picked.reduce((a, b) => a + b, 0) / picked.length : divZero(msg('formula.error.fnNoMatchingRows', { fn: 'AVERAGEIFS' }))
  )),
  COUNTIFS: {
    category: CATEGORY,
    minArgs: 2,
    fn: (args) => {
      const matched = matchingIndexes(args, 0);
      if (isError(matched)) return matched;
      // `isError` is not declared as a type predicate, so the narrowing above
      // is invisible to `tsc --checkJs`. The cast states what the early return
      // already guaranteed rather than widening the checked set.
      return /** @type {number[]} */ (matched).length;
    },
  },

  // Weighted average: values and weights, pairwise.
  AVGW: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      // Pair by position BEFORE dropping blanks: filtering each side alone would
      // slide later items into the wrong pairing.
      const rawValues = flattenValues([args[0]]);
      const rawWeights = flattenValues([args[1]]);
      if (rawValues.length !== rawWeights.length) return numError(msg('formula.error.avgwWeightCount'));
      const values = [];
      const weights = [];
      for (let i = 0; i < rawValues.length; i += 1) {
        if (isError(rawValues[i])) return rawValues[i];
        if (isError(rawWeights[i])) return rawWeights[i];
        const v = toNumber(rawValues[i]);
        const w = toNumber(rawWeights[i]);
        if (isError(v) || isError(w) || v === null || w === null) continue;
        values.push(v);
        weights.push(w);
      }
      const total = weights.reduce((acc, w) => acc + w, 0);
      if (total === 0) return divZero(msg('formula.error.avgwZeroWeights'));
      // `weighted`, not `sum`: this module exports a `sum` helper, and shadowing it
      // inside an aggregate implementation is how the wrong one gets called later.
      let weighted = 0;
      for (let i = 0; i < values.length; i += 1) weighted += values[i] * weights[i];
      return weighted / total;
    },
  },
};

/** LARGE / SMALL: the nth value once the numbers are ordered. */
function nthValue(name, order) {
  return {
    category: CATEGORY,
    minArgs: 2,
    fn: (args) => {
      const pool = collectNumbers(args.slice(0, -1));
      if (isError(pool)) return pool;
      const k = num(args[args.length - 1]);
      if (isError(k)) return k;
      const rank = Math.trunc(k ?? 0);
      if (rank < 1 || rank > pool.length) return numError(msg('formula.error.noValueAtPosition', { fn: name, position: k }));
      return [...pool].sort(order)[rank - 1];
    },
  };
}

/**
 * The indexes of the rows matching every (range, criterion) pair.
 *
 * `start` is where the pairs begin — 0 for COUNTIFS, 1 for SUMIFS/AVERAGEIFS,
 * whose first argument is the range being aggregated rather than tested.
 * Returns an error when the ranges are ragged: silently intersecting what
 * happens to line up would answer a question nobody asked.
 */
function matchingIndexes(args, start) {
  const pairs = [];
  for (let i = start; i + 1 < args.length; i += 2) {
    pairs.push([flattenValues([args[i]]), args[i + 1]]);
  }
  if (!pairs.length) return numError(msg('formula.error.conditionalNeedsRangeCriterion'));
  const length = pairs[0][0].length;
  if (pairs.some(([range]) => range.length !== length)) {
    return numError(msg('formula.error.conditionalRangesSameLength'));
  }
  const out = [];
  for (let row = 0; row < length; row += 1) {
    if (pairs.every(([range, criterion]) => matchesCriterion(range[row], criterion))) out.push(row);
  }
  return out;
}

/**
 * One cell against one criterion.
 *
 * A bare value compares loosely; a string beginning with a comparison operator
 * ('>10', '<>done') compares numerically or textually as written — the shape
 * every spreadsheet's *IF family uses, and the reason a criterion is a value
 * rather than an expression.
 */
function matchesCriterion(cell, criterion) {
  if (typeof criterion === 'string') {
    // `s` so a criterion with a newline is still an operator + operand.
    const m = /^\s*(<=|>=|<>|!=|=|<|>)\s*(.*)$/s.exec(criterion);
    if (m) {
      const [, op, rest] = m;
      const target = toNumber(rest);
      const numeric = !isError(target) && target !== null && rest.trim() !== '';
      if (op === '=') return looseEquals(cell, numeric ? target : rest);
      if (op === '<>' || op === '!=') return !looseEquals(cell, numeric ? target : rest);
      let left;
      let right;
      if (numeric) {
        left = toNumber(cell);
        if (isError(left) || left === null) return false;
        right = target;
      } else {
        // Text ordering, case-insensitive like the equality tests.
        left = String(cell ?? '').toLowerCase();
        right = rest.toLowerCase();
      }
      switch (op) {
        case '>': return left > right;
        case '<': return left < right;
        case '>=': return left >= right;
        default: return left <= right;
      }
    }
  }
  return looseEquals(cell, criterion);
}

/** A Set key equal for exactly the values looseEquals treats as equal. */
function uniqueKey(v) {
  if (v instanceof Date) return `d:${v.getTime()}`;
  if (typeof v === 'boolean') return `b:${v}`;
  return `s:${String(typeof v === 'string' ? v : toText(v)).toLowerCase()}`;
}

/** SUMIFS / AVERAGEIFS: aggregate the values whose row matched every pair. */
function conditionalAggregate(name, reduce) {
  return {
    category: CATEGORY,
    minArgs: 3,
    fn: (args) => {
      const matched = matchingIndexes(args, 1);
      if (isError(matched)) return matched;
      const values = flattenValues([args[0]]);
      const picked = [];
      for (const row of /** @type {number[]} */ (matched)) {
        const n = toNumber(values[row]);
        if (isError(n)) return n;
        if (n !== null) picked.push(n);
      }
      return reduce(picked);
    },
  };
}

export default math;
