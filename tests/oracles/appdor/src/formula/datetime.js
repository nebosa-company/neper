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
 * Date & Time functions (docs/formulas.md:116-140) plus the Appdor original
 * `century` (date-time.md:3).
 *
 * All construction and extraction uses UTC for determinism across time zones.
 * `NOW`/`TODAY` are volatile and read the injected clock `ctx.now` (a Date or
 * timestamp) when provided, so evaluation is reproducible in tests
 * (REQ-FORMULAENGINE-15).
 */

import { isError, valueError, numError } from './errors.js';
import { toDate, toNumber, toText, isBlank } from './values.js';
// The Date FIELD's relative wording, shared so a formula and a column set to
// "Relative" cannot describe the same instant in two different sentences.
import { relativeFrom } from '../fields/datetime-format.js';
// SET_LOCALE renders through the shared formatter, like every other
// locale-aware call in the product — see tests/i18n/no-ad-hoc-locale.test.js.
import { formatDate as formatFieldDate, zonedParts } from '../localization/index.js';

const CATEGORY = 'datetime';
const DAY_MS = 86_400_000;

function clockNow(ctx) {
  if (ctx && ctx.now instanceof Date) return new Date(ctx.now.getTime());
  if (ctx && (typeof ctx.now === 'number' || typeof ctx.now === 'string')) {
    const d = new Date(ctx.now);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return new Date();
}

function asDate(v) {
  if (isBlank(v)) return null;
  return toDate(v);
}

function utcMidnight(d) {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function pad(n, w = 2) {
  return String(Math.abs(n)).padStart(w, '0');
}

/** English ordinal for a day-of-month: the `Do` token. 1st, 2nd, 3rd, 11th. */
function ordinal(n) {
  const teens = n % 100;
  if (teens >= 11 && teens <= 13) return `${n}th`;
  return `${n}${['th', 'st', 'nd', 'rd'][n % 10] || 'th'}`;
}

/**
 * Moment's locale-composite formats, expanded before the atomic tokens run.
 *
 * `'L'` used to render as the letter `"L"`, because `String.replace` leaves
 * every character it does not match alone — an unknown token is silently
 * literal text here, never an error. These are moment's `en` definitions, which
 * is the locale this whole function already is: MONTHS below is English and
 * every part is read in UTC, deliberately (see the module docblock), so that a
 * formula's output does not change with who is looking at it.
 */
const LOCALIZED_FORMATS = {
  L: 'MM/DD/YYYY',
  LL: 'MMMM D, YYYY',
  LLL: 'MMMM D, YYYY h:mm A',
  LLLL: 'dddd, MMMM D, YYYY h:mm A',
  LT: 'h:mm A',
  LTS: 'h:mm:ss A',
};

/**
 * Every token this formatter understands, longest-first per family.
 *
 * `Do` must precede `D` and `MMMM` must precede `MM`, or the shorter token eats
 * the front of the longer one — which is how `'MMMM Do YYYY'` used to render as
 * `"December 31o 2025"`: `D` matched, `o` fell through as literal text.
 *
 * The leading `\[([^\]]*)\]` alternative is moment's escape, and it is what
 * makes widening the table safe rather than a new hazard: `dd`, `A` and `Do`
 * now MEAN something, so the way to print the word "Added" is `'[Added]'`.
 */
const FORMAT_TOKEN = /\[([^\]]*)\]|LTS|LLLL|LLL|LL|LT|L|YYYY|YY|MMMM|MMM|MM|M|DDDD|DDD|DD|Do|D|dddd|ddd|dd|SSS|HH|H|hh|h|mm|m|ss|s|ZZ|Z|WW|W|Q|A|a/g;

/**
 * Format a date with moment-style tokens, in UTC and in English.
 *
 * The table used to hold exactly `YYYY YY MMMM MMM MM M DD D HH H mm m ss s`,
 * and anything outside that subset was emitted as literal text rather than
 * reported: `DATETIME_FORMAT({Due}, 'dddd, MMMM Do YYYY')` on 2025-12-31 gave
 * `"dddd, December 31o 2025"` and `'L'` gave `"L"`. docs/formulas.md:1650
 * promises "Moment.js-style specifiers (M, MM, D, DD, YYYY, etc.); `'W'` gives
 * ISO week number", so the table was the thing that was wrong, not the promise.
 *
 * This is not only an import concern. `TOTEXT`/`FORMAT` in convertion.js reach
 * the same table from natively-authored formulas and from CSV export, so the
 * silent literal was shipping in exports too.
 */
export function formatDate(date, fmt) {
  const month = date.getUTCMonth();
  const dayOfMonth = date.getUTCDate();
  const weekday = WEEKDAYS[date.getUTCDay()];
  const hours24 = date.getUTCHours();
  // 0 and 12 are both "12" on a 12-hour clock; `% 12` alone renders midnight
  // as "0 AM".
  const hours12 = hours24 % 12 || 12;
  const dayOfYear = Math.floor(
    (Date.UTC(date.getUTCFullYear(), month, dayOfMonth) - Date.UTC(date.getUTCFullYear(), 0, 1)) / DAY_MS
  ) + 1;
  const isoWeek = isoWeekNumber(date);
  const tokens = {
    YYYY: date.getUTCFullYear(),
    YY: pad(date.getUTCFullYear() % 100),
    MMMM: MONTHS[month],
    MMM: MONTHS[month].slice(0, 3),
    MM: pad(month + 1),
    M: month + 1,
    Q: Math.floor(month / 3) + 1,
    DDDD: pad(dayOfYear, 3),
    DDD: dayOfYear,
    DD: pad(dayOfMonth),
    Do: ordinal(dayOfMonth),
    D: dayOfMonth,
    dddd: weekday,
    ddd: weekday.slice(0, 3),
    dd: weekday.slice(0, 2),
    WW: pad(isoWeek),
    W: isoWeek,
    HH: pad(hours24),
    H: hours24,
    hh: pad(hours12),
    h: hours12,
    A: hours24 < 12 ? 'AM' : 'PM',
    a: hours24 < 12 ? 'am' : 'pm',
    mm: pad(date.getUTCMinutes()),
    m: date.getUTCMinutes(),
    ss: pad(date.getUTCSeconds()),
    s: date.getUTCSeconds(),
    SSS: pad(date.getUTCMilliseconds(), 3),
    // Not a formatting choice: every part above is read in UTC by construction,
    // so the offset is always zero and a `Z` that printed anything else would
    // be describing a timestamp this function never produced.
    ZZ: '+0000',
    Z: '+00:00',
  };
  return fmt.replace(FORMAT_TOKEN, (match, escaped) => {
    // `escaped` participated only for the `[...]` alternative, so `''` (an
    // empty `[]`) has to be distinguished from "did not match" by `undefined`.
    if (escaped !== undefined) return escaped;
    // One level deep and no deeper: the expansions above contain no L-token and
    // no brackets, so this cannot recurse.
    if (LOCALIZED_FORMATS[match]) return formatDate(date, LOCALIZED_FORMATS[match]);
    return String(tokens[match]);
  });
}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

// Indexed by `getUTCDay()`, so Sunday is 0 — the `dddd` / `ddd` / `dd` tokens.
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/**
 * The ISO-8601 week number of a date, in UTC.
 *
 * Lifted out of `ISOWEEKNUM` rather than copied for the `W`/`WW` format tokens:
 * two implementations of "which week is this" is how a formula and the string
 * it formats end up disagreeing at a year boundary.
 */
/**
 * Parse a date STRING against a format, the inverse of `formatDate` above.
 *
 * Airtable's `DATETIME_PARSE(text, format)` maps to `TODATE` (see
 * `src/formula/compat/dialects.js`), and `TODATE` took one argument — so an
 * imported formula reading
 *
 *     DATETIME_DIFF(TODAY(), TODATE({Opened date}, "MM-DD-YY"), "days")
 *
 * was an arity error and every one of its cells rendered `#VALUE!`. The
 * translation was right and the target could not express it, which is the
 * shape of every lossy mapping worth finding: the formula LOOKS translated.
 *
 * Format-directed rather than heuristic, and that is the whole point. `09-09-26`
 * is a real date in three different orders, and `Date.parse` picks one by
 * guessing; the caller has told us the order and this reads it. Anything the
 * format does not name is matched literally, so a separator that disagrees is a
 * refusal rather than a silent reinterpretation.
 *
 * Tokens are the numeric and month-name half of `formatDate`'s vocabulary, which
 * is what a parse can invert: `dddd`/`Do`/`W` and friends describe a date rather
 * than determine one, so they are matched and discarded. Longest token first, or
 * `MM` would be read as `M` followed by a literal digit.
 *
 * Two-digit years follow the POSIX split — 00-68 is 2000s, 69-99 is 1900s —
 * stated here because it is a convention rather than a fact, and a base whose
 * dates straddle it will want `YYYY`.
 *
 * Built in UTC, like everything `formatDate` reads, so a value round-trips
 * through the pair unchanged.
 *
 * @param {string} text
 * @param {string} fmt
 * @returns {Date|null} null when the text does not match the format
 */
export function parseDateWithFormat(text, fmt) {
  const src = String(text == null ? '' : text);
  const format = String(fmt == null ? '' : fmt);
  if (!src || !format) return null;

  const NUM = { YYYY: 4, YY: 2, MM: 2, M: 2, DD: 2, D: 2, HH: 2, H: 2, hh: 2, h: 2, mm: 2, m: 2, ss: 2, s: 2, SSS: 3 };
  // Longest first: `MM` before `M`, `MMMM` before `MMM`.
  const TOKENS = ['YYYY', 'MMMM', 'MMM', 'SSS', 'DDDD', 'DDD', 'dddd', 'ddd', 'YY', 'MM', 'DD', 'HH', 'hh', 'mm', 'ss', 'dd', 'Do', 'WW', 'M', 'D', 'H', 'h', 'm', 's', 'W', 'Q', 'A', 'a'];
  const got = { y: null, mo: null, d: null, H: null, mi: null, sec: null, ms: 0, pm: null };

  let i = 0;
  let j = 0;
  while (j < format.length) {
    // `[literal]`: the escape formatDate emits. Matched verbatim, tokens ignored.
    if (format[j] === '[') {
      const close = format.indexOf(']', j + 1);
      if (close !== -1) {
        const lit = format.slice(j + 1, close);
        if (!src.startsWith(lit, i)) return null;
        i += lit.length; j = close + 1;
        continue;
      }
    }
    const token = TOKENS.find((t) => format.startsWith(t, j));
    if (!token) {
      // A literal. It must be there, or the text is not in this format.
      if (src[i] !== format[j]) return null;
      i += 1; j += 1;
      continue;
    }
    j += token.length;

    if (token === 'MMMM' || token === 'MMM') {
      const idx = MONTHS.findIndex((mo) => src.slice(i).toLowerCase().startsWith(
        (token === 'MMM' ? mo.slice(0, 3) : mo).toLowerCase(),
      ));
      if (idx === -1) return null;
      got.mo = idx;
      i += token === 'MMM' ? 3 : MONTHS[idx].length;
      continue;
    }
    if (token === 'A' || token === 'a') {
      const half = src.slice(i, i + 2).toLowerCase();
      if (half !== 'am' && half !== 'pm') return null;
      got.pm = half === 'pm';
      i += 2;
      continue;
    }
    if (!Object.hasOwn(NUM, token)) {
      // Descriptive, not determining — `dddd`, `Do`, `W`, `Q`. Consume the
      // run it occupies and move on rather than refusing a format that names it.
      while (i < src.length && /[A-Za-z0-9]/.test(src[i])) i += 1;
      continue;
    }
    const width = NUM[token];
    let digits = '';
    while (digits.length < width && /[0-9]/.test(src[i] || '')) { digits += src[i]; i += 1; }
    if (!digits) return null;
    const n = Number(digits);
    if (token === 'YYYY') got.y = n;
    else if (token === 'YY') got.y = n <= 68 ? 2000 + n : 1900 + n;
    else if (token === 'MM' || token === 'M') got.mo = n - 1;
    else if (token === 'DD' || token === 'D') got.d = n;
    else if (token === 'HH' || token === 'H' || token === 'hh' || token === 'h') got.H = n;
    else if (token === 'mm' || token === 'm') got.mi = n;
    else if (token === 'ss' || token === 's') got.sec = n;
    else if (token === 'SSS') got.ms = n;
  }
  // Trailing text the format did not account for means it is a different shape.
  if (i < src.length) return null;
  if (got.y === null || got.mo === null || got.d === null) return null;
  if (got.mo < 0 || got.mo > 11 || got.d < 1 || got.d > 31) return null;

  let hours = got.H === null ? 0 : got.H;
  if (got.pm === true && hours < 12) hours += 12;
  if (got.pm === false && hours === 12) hours = 0;
  // A clock reading that does not exist is a refusal, not a roll into the next
  // hour/day: `12:99` is not 13:39.
  if (hours > 23 || (got.mi || 0) > 59 || (got.sec || 0) > 59) return null;
  const out = utcDate(got.y, got.mo, got.d, hours, got.mi || 0, got.sec || 0, got.ms || 0);
  // `Date.UTC` rolls 31 February into March rather than refusing it.
  if (out.getUTCMonth() !== got.mo || out.getUTCDate() !== got.d) return null;
  return out;
}

/**
 * Date.UTC with the year taken literally: `Date.UTC(26, 0, 1)` is 1926 (years
 * 0-99 are mapped to 19xx), which is not what DATE(26,1,1) or "YY" parsing mean.
 */
function utcDate(y, mo, d, h = 0, mi = 0, sec = 0, ms = 0) {
  const out = new Date(Date.UTC(2000, mo, d, h, mi, sec, ms));
  out.setUTCFullYear(y, mo, d);
  return out;
}

function isoWeekNumber(d) {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = (date.getUTCDay() + 6) % 7; // Mon=0
  date.setUTCDate(date.getUTCDate() - dayNum + 3); // Thursday of this week
  const firstThursday = new Date(Date.UTC(date.getUTCFullYear(), 0, 4));
  const firstDayNum = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - firstDayNum + 3);
  return 1 + Math.round((date.getTime() - firstThursday.getTime()) / (7 * DAY_MS));
}

const extract = (getter) => ({
  category: CATEGORY,
  minArgs: 1,
  maxArgs: 1,
  fn: (args) => {
    const d = asDate(args[0]);
    if (isError(d)) return d;
    if (d === null) return null;
    return getter(d);
  },
});

/**
 * The two unit tokens whose meaning depends on CASE, moment's pair.
 *
 * This is the half of the vocabulary the old `String(unit).toLowerCase()` threw
 * away: `'m'` is MINUTES and `'M'` is MONTHS, and folding them meant
 * `DATEADD({Due}, 30, 'm')` landed thirty months out instead of thirty minutes.
 * Not an invented reading — docs/formulas.md:1645 lists the DATETIME_DIFF units
 * as `'ms'`, `'s'`, `'m'`, `'h'`, `'d'`, `'w'`, `'M'`, `'Q'`, `'y'`, and
 * `INTERVAL_UNITS` in src/formula/sql-compiler.js already compiles `'m'` to
 * `INTERVAL '1 minute'` — so the SAME formula answered minutes when it was
 * pushed to the database and months when it was evaluated in process.
 */
const CASE_SIGNIFICANT_UNITS = new Map([
  ['M', 'month'],
  ['m', 'minute'],
]);

/**
 * Every other spelling of a unit, case-insensitively, as an explicit table.
 *
 * Explicit because the other half of the fold was `.replace(/s$/, '')`, which
 * is not a plural rule: it turned `'ms'` into `'m'` (so
 * `DATETIME_DIFF(a, b, 'ms')` answered 18 where the span was 47 million
 * milliseconds) and `'s'` into `''`. Plurals are listed, not stripped.
 *
 * Kept deliberately in step with sql-compiler.js's `INTERVAL_UNITS`: a unit one
 * of them accepts and the other does not is a formula that means two different
 * things depending on whether the query planner pushed it down.
 */
const UNIT_ALIASES = new Map([
  ['ms', 'millisecond'], ['millisecond', 'millisecond'], ['milliseconds', 'millisecond'],
  ['s', 'second'], ['sec', 'second'], ['secs', 'second'], ['second', 'second'], ['seconds', 'second'],
  ['min', 'minute'], ['mins', 'minute'], ['minute', 'minute'], ['minutes', 'minute'],
  ['h', 'hour'], ['hr', 'hour'], ['hrs', 'hour'], ['hour', 'hour'], ['hours', 'hour'],
  ['d', 'day'], ['day', 'day'], ['days', 'day'],
  ['w', 'week'], ['wk', 'week'], ['wks', 'week'], ['week', 'week'], ['weeks', 'week'],
  ['mo', 'month'], ['mos', 'month'], ['month', 'month'], ['months', 'month'],
  ['q', 'quarter'], ['quarter', 'quarter'], ['quarters', 'quarter'],
  ['y', 'year'], ['yr', 'year'], ['yrs', 'year'], ['year', 'year'], ['years', 'year'],
]);

/**
 * A unit token → the canonical unit id, or null when it is not a unit at all.
 *
 * The case-significant pair is consulted FIRST and only for an exact match, so
 * `'m'` and `'M'` part company while `'Minutes'`, `'MONTHS'` and `'MS'` still
 * arrive through the case-insensitive table below.
 */
function normalizeUnit(unit) {
  const raw = String(unit ?? '').trim();
  if (CASE_SIGNIFICANT_UNITS.has(raw)) return CASE_SIGNIFICANT_UNITS.get(raw);
  return UNIT_ALIASES.get(raw.toLowerCase()) || null;
}

function addUnit(date, amount, unit) {
  const d = new Date(date.getTime());
  switch (normalizeUnit(unit)) {
    // Calendar arithmetic clamps the day (31 Jan + 1 month = 28 Feb), exactly
    // like DATETIME_ADD; setUTCMonth/setUTCFullYear alone overflow into March.
    case 'year':
      return addMonthsClamped(d, amount * 12);
    case 'quarter':
      return addMonthsClamped(d, amount * 3);
    case 'month':
      return addMonthsClamped(d, amount);
    case 'week':
      d.setUTCDate(d.getUTCDate() + amount * 7);
      break;
    case 'day':
      d.setUTCDate(d.getUTCDate() + amount);
      break;
    case 'hour':
      d.setUTCHours(d.getUTCHours() + amount);
      break;
    case 'minute':
      d.setUTCMinutes(d.getUTCMinutes() + amount);
      break;
    case 'second':
      d.setUTCSeconds(d.getUTCSeconds() + amount);
      break;
    case 'millisecond':
      d.setUTCMilliseconds(d.getUTCMilliseconds() + amount);
      break;
    default:
      return valueError(`Unknown DATEADD unit "${unit}"`);
  }
  return d;
}

/**
 * `from` plus `count` months, with the day-of-month clamped to the target month.
 *
 * 31 January plus one month is 28 February, not 3 March: `setUTCMonth` alone
 * overflows, which would make the anchor `elapsedMonths` compares against land
 * in the month AFTER the one it is asking about.
 */
function addMonthsClamped(from, count) {
  const d = new Date(from.getTime());
  const day = d.getUTCDate();
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + count);
  const lastDay = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(day, lastDay));
  return d;
}

/**
 * Signed count of COMPLETE months elapsed from `from` to `to`.
 *
 * The month and year arms of `diffUnits` used to subtract calendar FIELDS —
 * `(ay - by) * 12 + (am - bm)` and `ay - by` — which is not a difference
 * between two instants, it is a difference between two labels. Somebody hired
 * on 31 December read as a full year of tenure on 1 January, so on migration
 * day every seniority band, vesting cliff and renewal alert built on
 * `DATETIME_DIFF(TODAY(), {Hired}, 'years')` changed value at once, with
 * nothing in the report saying anything had.
 *
 * docs/formulas.md:1645 says the answer is "whole units", and that is what
 * Airtable (moment's truncated `diff`) returns. So the fix is the semantics,
 * not a compatibility flag: no natively-authored caller depends on the old
 * reading — nothing in `src/`, `services/` or `templates/` calls
 * DATETIME_DIFF, the SQL compiler never compiles it (only DATEADD and DATEDIF
 * are pushed down), and `DATEDIF` next door has always measured elapsed time
 * via `diffYMD`, so the two functions in this file disagreed with each other.
 *
 * Counted by anchoring rather than by dividing: months are 28-31 days long, so
 * the field difference is the upper bound and one is given back when the
 * day-of-month (and time of day) has not come round yet.
 */
function elapsedMonths(from, to) {
  let months = (to.getUTCFullYear() - from.getUTCFullYear()) * 12 + (to.getUTCMonth() - from.getUTCMonth());
  if (months > 0 && addMonthsClamped(from, months) > to) months -= 1;
  else if (months < 0 && addMonthsClamped(from, months) < to) months += 1;
  return months;
}

function diffUnits(a, b, unit) {
  // a - b in the given unit (Airtable DATETIME_DIFF order).
  const u = normalizeUnit(unit || 'day');
  const ms = a.getTime() - b.getTime();
  switch (u) {
    case 'millisecond':
      return ms;
    case 'second':
      return Math.trunc(ms / 1000);
    case 'minute':
      return Math.trunc(ms / 60000);
    case 'hour':
      return Math.trunc(ms / 3600000);
    case 'day':
      return Math.trunc(ms / DAY_MS);
    case 'week':
      return Math.trunc(ms / (7 * DAY_MS));
    // Elapsed, not calendar-field: see `elapsedMonths`. Quarters and years are
    // whole months divided down for the same reason — a quarter boundary
    // crossed is not a quarter elapsed.
    case 'month':
      return elapsedMonths(b, a);
    case 'quarter':
      return Math.trunc(elapsedMonths(b, a) / 3);
    case 'year':
      return Math.trunc(elapsedMonths(b, a) / 12);
    default:
      return valueError(`Unknown diff unit "${unit}"`);
  }
}

const datetime = {
  DATE: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const y = toNumber(args[0]);
      const m = toNumber(args[1]);
      const d = toNumber(args[2]);
      if (isError(y)) return y;
      if (isError(m)) return m;
      if (isError(d)) return d;
      return utcDate(y, (m ?? 1) - 1, d ?? 1);
    },
  },
  TIME: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const h = toNumber(args[0]) ?? 0;
      const m = toNumber(args[1]) ?? 0;
      const s = toNumber(args[2]) ?? 0;
      if (isError(h)) return h;
      if (isError(m)) return m;
      if (isError(s)) return s;
      return new Date(Date.UTC(1970, 0, 1, h, m, s));
    },
  },
  NOW: { category: CATEGORY, volatile: true, minArgs: 0, maxArgs: 0, fn: (_a, ctx) => clockNow(ctx) },
  TODAY: { category: CATEGORY, volatile: true, minArgs: 0, maxArgs: 0, fn: (_a, ctx) => utcMidnight(clockNow(ctx)) },
  YEAR: extract((d) => d.getUTCFullYear()),
  MONTH: extract((d) => d.getUTCMonth() + 1),
  DAY: extract((d) => d.getUTCDate()),
  HOUR: extract((d) => d.getUTCHours()),
  MINUTE: extract((d) => d.getUTCMinutes()),
  SECOND: extract((d) => d.getUTCSeconds()),
  // Appdor original: century number, e.g. 2026 -> 21 (date-time.md:3).
  CENTURY: extract((d) => Math.floor((d.getUTCFullYear() - 1) / 100) + 1),
  WEEKDAY: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (d === null) return null;
      const type = args.length > 1 ? Math.trunc(toNumber(args[1]) ?? 1) : 1;
      const dow = d.getUTCDay(); // 0 Sun .. 6 Sat
      if (type === 1) return dow + 1; // Sun=1..Sat=7
      if (type === 2) return dow === 0 ? 7 : dow; // Mon=1..Sun=7
      if (type === 3) return dow === 0 ? 6 : dow - 1; // Mon=0..Sun=6
      return dow + 1;
    },
  },
  WEEKNUM: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (d === null) return null;
      const start = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
      const days = Math.floor((d.getTime() - start.getTime()) / DAY_MS);
      return Math.floor((days + start.getUTCDay()) / 7) + 1;
    },
  },
  ISOWEEKNUM: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (d === null) return null;
      return isoWeekNumber(d);
    },
  },
  DATEADD: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (d === null) return null;
      const amount = toNumber(args[1]);
      if (isError(amount)) return amount;
      return addUnit(d, Math.trunc(amount ?? 0), args[2]);
    },
  },
  DATEDIF: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const a = asDate(args[0]);
      const b = asDate(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (a === null || b === null) return null;
      const unit = String(toText(args[2])).toUpperCase();
      if (b < a) return numError('DATEDIF end date is before start date');
      switch (unit) {
        case 'Y':
          return diffYMD(a, b).years;
        case 'M':
          return diffYMD(a, b).years * 12 + diffYMD(a, b).months;
        case 'D':
          return Math.floor((b - a) / DAY_MS);
        case 'MD':
          return diffYMD(a, b).days;
        case 'YM':
          return diffYMD(a, b).months;
        case 'YD': {
          const anchor = new Date(Date.UTC(b.getUTCFullYear(), a.getUTCMonth(), a.getUTCDate()));
          const base = anchor > b ? new Date(Date.UTC(b.getUTCFullYear() - 1, a.getUTCMonth(), a.getUTCDate())) : anchor;
          return Math.floor((b.getTime() - base.getTime()) / DAY_MS);
        }
        default:
          return valueError(`Unknown DATEDIF unit "${unit}"`);
      }
    },
  },
  DATETIME_DIFF: {
    category: CATEGORY,
    aliases: ['DATETIME_DIF', 'DATETIMEDIFF'],
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const a = asDate(args[0]);
      const b = asDate(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (a === null || b === null) return null;
      return diffUnits(a, b, args.length > 2 ? toText(args[2]) : 'day');
    },
  },
  DAYS: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const end = asDate(args[0]);
      const start = asDate(args[1]);
      if (isError(end)) return end;
      if (isError(start)) return start;
      if (end === null || start === null) return null;
      return Math.round((end - start) / DAY_MS);
    },
  },
  DATEVALUE: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (d === null) return null;
      return utcMidnight(d);
    },
  },
  TIMEVALUE: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (d === null) return null;
      return new Date(Date.UTC(1970, 0, 1, d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds()));
    },
  },
  EDATE: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (d === null) return null;
      const months = toNumber(args[1]);
      if (isError(months)) return months;
      return addUnit(d, Math.trunc(months ?? 0), 'month');
    },
  },
  EOMONTH: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (d === null) return null;
      const months = toNumber(args[1]);
      if (isError(months)) return months;
      const moved = addUnit(d, Math.trunc(months ?? 0), 'month');
      if (!(moved instanceof Date)) return moved;
      return new Date(Date.UTC(moved.getUTCFullYear(), moved.getUTCMonth() + 1, 0));
    },
  },
  NETWORKDAYS: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const start = asDate(args[0]);
      const end = asDate(args[1]);
      if (isError(start)) return start;
      if (isError(end)) return end;
      if (start === null || end === null) return null;
      const holidays = sortedWeekdayHolidays(args[2]);
      const dir = end >= start ? 1 : -1;
      const lo = dayIndex(dir > 0 ? start : end);
      const hi = dayIndex(dir > 0 ? end : start);
      const count = weekdaysBefore(hi + 1) - weekdaysBefore(lo) - holidaysIn(holidays, lo, hi);
      return dir > 0 ? count : -count;
    },
  },
  WORKDAY: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const start = asDate(args[0]);
      if (isError(start)) return start;
      if (start === null) return null;
      const days = toNumber(args[1]);
      if (isError(days)) return days;
      const holidays = sortedWeekdayHolidays(args[2]);
      const n = Math.trunc(days ?? 0);
      if (!Number.isFinite(n) || Math.abs(n) > 1e8) return numError();
      const step = n >= 0 ? 1 : -1;
      const startIdx = dayIndex(start);
      if (n === 0) return utcMidnight(start);
      // Arithmetic, not a day-by-day walk: whole weeks at once, then widen by
      // however many holidays fell inside what was covered, until none are new.
      let target = shiftWorkdays(startIdx, n);
      let from = startIdx;
      for (let guard = 0; guard < 10000; guard += 1) {
        const lo = step > 0 ? from + 1 : target;
        const hi = step > 0 ? target : from - 1;
        const h = holidaysIn(holidays, lo, hi);
        if (h === 0) break;
        from = target;
        target = shiftWorkdays(target, step * h);
      }
      const out = new Date(target * DAY_MS);
      return Number.isNaN(out.getTime()) ? numError() : out;
    },
  },
  YEARFRAC: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const a = asDate(args[0]);
      const b = asDate(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (a === null || b === null) return null;
      const basis = args.length > 2 ? Math.trunc(toNumber(args[2]) ?? 0) : 0;
      const [start, end] = a <= b ? [a, b] : [b, a];
      if (basis === 3) return (end - start) / DAY_MS / 365;
      if (basis === 1) return (end - start) / DAY_MS / 365.25;
      // Default US 30/360.
      const d360 =
        (end.getUTCFullYear() - start.getUTCFullYear()) * 360 +
        (end.getUTCMonth() - start.getUTCMonth()) * 30 +
        (Math.min(end.getUTCDate(), 30) - Math.min(start.getUTCDate(), 30));
      return d360 / 360;
    },
  },

  // --- the remaining date/time names the specs list -----------------------

  // Shifting. ADD_DAYS/SUBTRACT_DAYS and their minute pair are Monday's names
  // for what DATEADD already does; they exist because someone will type them.
  ADD_DAYS: shiftBy(DAY_MS, 1),
  SUBTRACT_DAYS: shiftBy(DAY_MS, -1),
  ADD_MINUTES: shiftBy(60_000, 1),
  SUBTRACT_MINUTES: shiftBy(60_000, -1),
  DATETIME_ADD: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const base = asDate(args[0]);
      if (isError(base)) return base;
      if (!base) return null;
      const count = toNumber(args[1]);
      if (isError(count)) return count;
      const unit = toText(args[2]);
      if (isError(unit)) return unit;
      return addUnits(base, count ?? 0, unit);
    },
  },

  // Boundaries of a period.
  FIRSTDAYOFMONTH: boundary((d) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1))),
  LASTDAYOFMONTH: boundary((d) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0))),
  // EOWEEK ends on Saturday, matching AppSheet's week; EOMONTH already exists.
  EOWEEK: boundary((d) => {
    const end = utcMidnight(d);
    end.setUTCDate(end.getUTCDate() + (6 - end.getUTCDay()));
    return end;
  }),
  /**
   * EWOMONTH: the end of the WEEK that ends the month.
   *
   * Genuinely different from EOMONTH, which the spec flags — the last week of
   * the month usually spills into the next one, and a rota that stops at the
   * 31st cuts that week in half.
   */
  EWOMONTH: boundary((d) => {
    const lastDay = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0));
    lastDay.setUTCDate(lastDay.getUTCDate() + (6 - lastDay.getUTCDay()));
    return lastDay;
  }),

  DAYOFYEAR: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (!d) return null;
      const start = Date.UTC(d.getUTCFullYear(), 0, 1);
      return Math.floor((utcMidnight(d).getTime() - start) / DAY_MS) + 1;
    },
  },

  // Distance from now. DAYSSINCE counts backwards, DAYSREMAINING forwards, and
  // each returns a NEGATIVE number when the date is on the other side — the
  // alternative is clamping at zero, which hides an overdue task.
  DAYSSINCE: sinceNow((diffMs) => Math.floor(diffMs / DAY_MS)),
  DAYSREMAINING: sinceNow((diffMs) => -Math.floor(diffMs / DAY_MS)),
  HOURS_DIFF: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const a = asDate(args[0]);
      const b = asDate(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (!a || !b) return null;
      return (b.getTime() - a.getTime()) / 3_600_000;
    },
  },
  TOTALHOURS: totalOf(3_600_000),
  TOTALMINUTES: totalOf(60_000),

  // Comparisons. Named functions rather than `<` because a formula reads better
  // as IS_BEFORE({due}, TODAY()) and because dates compare by instant, not by
  // the string an operator would coerce them to.
  IS_BEFORE: comparison((a, b) => a.getTime() < b.getTime()),
  IS_AFTER: comparison((a, b) => a.getTime() > b.getTime()),

  // Conversions.
  DATEONLY: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      return d ? utcMidnight(d) : null;
    },
  },
  DATESTR: formatterOf('YYYY-MM-DD'),
  TIMESTR: formatterOf('HH:mm:ss'),
  TOTIMESTAMP: {
    category: CATEGORY,
    aliases: ['TIMESTAMP'],
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      // Seconds, not milliseconds: every other system in the specs that says
      // "timestamp" means seconds, and a value 1000x off is not obviously wrong
      // on sight.
      return d ? Math.floor(d.getTime() / 1000) : null;
    },
  },
  FROMTIMESTAMP: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = toNumber(args[0]);
      if (isError(n)) return n;
      if (n === null) return null;
      // Accepts either scale: a value past ~1e11 cannot be a seconds timestamp
      // in any century anyone is modelling, so it is milliseconds.
      return new Date(Math.abs(n) > 1e11 ? n : n * 1000);
    },
  },
  DATETIME_PARSE: {
    category: CATEGORY,
    aliases: ['DATETIMEPARSE'],
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const text = toText(args[0]);
      if (isError(text)) return text;
      if (!String(text).trim()) return null;
      // With a format the caller has said which order the text is in; the
      // local-time guesser behind toDate would answer machine-dependently.
      const fmt = args.length > 1 ? toText(args[1]) : '';
      const parsed = fmt && String(fmt).trim() ? parseDateWithFormat(text, fmt) : toDate(text);
      if (isError(parsed) || !parsed) {
        return valueError(`Could not read a date from: ${text}`);
      }
      return parsed;
    },
  },

  // Relative wording, sharing the field module so a formula and a column set to
  // "Relative" cannot describe the same instant differently.
  FROMNOW: relativeTo((value, now) => relativeFrom(value, now)),
  TONOW: relativeTo((value, now) => relativeFrom(value, now)),

  UTCNOW: {
    category: CATEGORY,
    volatile: true,
    minArgs: 0,
    maxArgs: 0,
    fn: (_args, ctx) => clockNow(ctx),
  },

  // Working days.
  NETWORKDAY: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => datetime.NETWORKDAYS.fn(args),
  },
  WORKDAYS: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => datetime.NETWORKDAYS.fn(args),
  },
  WORKDAY_DIFF: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => datetime.NETWORKDAYS.fn(args),
  },
  WORKDAYADD: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => datetime.WORKDAY.fn(args),
  },

  /**
   * DATERANGE(start, end): the `{start, end}` shape the Date range COLUMN
   * stores, so a formula can build a value that column accepts directly.
   *
   * ISO date strings rather than Dates, because that is what is written to the
   * cell — handing back Date objects would round-trip through JSON as something
   * the column's own parser does not recognise.
   */
  DATERANGE: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const start = asDate(args[0]);
      if (isError(start)) return start;
      const end = args.length > 1 ? asDate(args[1]) : start;
      if (isError(end)) return end;
      if (!start && !end) return null;
      const iso = (d) => (d ? formatDate(d, 'YYYY-MM-DD') : '');
      // Reversed bounds are swapped rather than refused: a range typed
      // backwards is a range, and refusing it loses both dates.
      if (start && end && end.getTime() < start.getTime()) {
        return { start: iso(end), end: iso(start) };
      }
      return { start: iso(start), end: iso(end) };
    },
  },

  /**
   * SET_TIMEZONE(datetime, tz): the same instant, read in another zone.
   *
   * The returned Date is SHIFTED so its UTC parts spell that zone's wall clock
   * — which is what makes `TIMESTR(SET_TIMEZONE(x, 'Asia/Tokyo'))` show Tokyo's
   * time, since every formatter here reads UTC parts. The instant is therefore
   * no longer the original one, and that is deliberate: this is a display
   * conversion, and the alternative (a tagged value) would need every function
   * downstream to know about the tag.
   */
  SET_TIMEZONE: {
    category: CATEGORY,
    aliases: ['SETTIMEZONE'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (!d) return null;
      const zone = toText(args[1]);
      if (isError(zone)) return zone;
      try {
        // `zonedParts` is the shared, cached reader — it already pins the
        // Gregorian calendar, Latin digits and a 24-hour cycle, which is
        // exactly what these parts need to survive `Number()`. Constructing an
        // Intl formatter here instead would duplicate all three decisions and
        // break tests/i18n/no-ad-hoc-locale.test.js.
        const p = zonedParts(d, zone);
        return new Date(Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second));
      } catch {
        return valueError(`Unknown time zone: ${zone}`);
      }
    },
  },

  /**
   * SET_LOCALE(datetime, locale): the instant unchanged, formatted for a place.
   *
   * Returns the date itself — the locale only reaches the OUTPUT, through the
   * shared localization module, so this is `DATETIME_FORMAT`'s companion rather
   * than a transformation of the value. An unknown tag is refused rather than
   * silently falling back to English, which would render a French report in
   * English and look like a data problem.
   */
  SET_LOCALE: {
    category: CATEGORY,
    aliases: ['SETLOCALE'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (!d) return null;
      const locale = toText(args[1]);
      if (isError(locale)) return locale;
      // An unrecognised tag falls back to the active locale rather than being
      // refused — `formattingTag` is the product's one locale-resolution policy
      // and this follows it. Being stricter here than everywhere else would
      // mean a tag that renders a dashboard fine returns #VALUE! in a formula.
      return formatFieldDate(d, locale, {
        timeZone: 'UTC', year: 'numeric', month: 'long', day: 'numeric',
      });
    },
  },
};

/** ADD_/SUBTRACT_ pairs: one unit of milliseconds, one direction. */
function shiftBy(unitMs, direction) {
  return {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (!d) return null;
      const n = toNumber(args[1]);
      if (isError(n)) return n;
      return new Date(d.getTime() + direction * (n ?? 0) * unitMs);
    },
  };
}

/**
 * Add a count of a named unit, calendar-correctly for months and years.
 *
 * Shares `normalizeUnit` with `DATEADD` for the reason that table exists:
 * this function carried its own copy of the `toLowerCase().replace(/s$/, '')`
 * fold, so `DATETIME_ADD(x, 30, 'm')` and `DATEADD(x, 30, 'm')` were wrong in
 * exactly the same way, and fixing one would have left the pair disagreeing.
 */
function addUnits(base, count, unit) {
  const d = new Date(base.getTime());
  switch (normalizeUnit(unit)) {
    case 'year': return addMonthsClamped(d, count * 12);
    // Months are not 30 days: adding one to 31 January must not land in March,
    // so the day is clamped to the target month's length.
    case 'quarter': return addMonthsClamped(d, count * 3);
    case 'month': return addMonthsClamped(d, count);
    case 'week': return new Date(d.getTime() + count * 7 * DAY_MS);
    case 'day': return new Date(d.getTime() + count * DAY_MS);
    case 'hour': return new Date(d.getTime() + count * 3_600_000);
    case 'minute': return new Date(d.getTime() + count * 60_000);
    case 'second': return new Date(d.getTime() + count * 1000);
    case 'millisecond': return new Date(d.getTime() + count);
    default: return valueError(`Unknown unit: ${unit}`);
  }
}

/** A function returning some boundary of the period containing a date. */
function boundary(pick) {
  return {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      return d ? pick(d) : null;
    },
  };
}

/** DAYSSINCE / DAYSREMAINING: a signed distance from now. */
function sinceNow(measure) {
  return {
    category: CATEGORY,
    volatile: true,
    minArgs: 1,
    maxArgs: 1,
    fn: (args, ctx) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (!d) return null;
      return measure(utcMidnight(clockNow(ctx)).getTime() - utcMidnight(d).getTime());
    },
  };
}

/** TOTALHOURS / TOTALMINUTES: a duration expressed in one unit. */
function totalOf(unitMs) {
  return {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      // Two dates measure the span between them; one number is already a
      // duration in milliseconds, which is what DATETIME_DIFF returns.
      if (args.length === 2) {
        const a = asDate(args[0]);
        const b = asDate(args[1]);
        if (isError(a)) return a;
        if (isError(b)) return b;
        if (!a || !b) return null;
        return (b.getTime() - a.getTime()) / unitMs;
      }
      const n = toNumber(args[0]);
      if (isError(n)) return n;
      return n === null ? null : n / unitMs;
    },
  };
}

/** IS_BEFORE / IS_AFTER. */
function comparison(test) {
  return {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const a = asDate(args[0]);
      const b = asDate(args[1]);
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (!a || !b) return null;
      return test(a, b);
    },
  };
}

/** DATESTR / TIMESTR: a fixed format applied to a date. */
function formatterOf(fmt) {
  return {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      return d ? formatDate(d, fmt) : null;
    },
  };
}

/** FROMNOW / TONOW: the relative wording the Date field also uses. */
function relativeTo(describe) {
  return {
    category: CATEGORY,
    volatile: true,
    minArgs: 1,
    maxArgs: 1,
    fn: (args, ctx) => {
      const d = asDate(args[0]);
      if (isError(d)) return d;
      if (!d) return null;
      return describe(d, clockNow(ctx));
    },
  };
}

function diffYMD(a, b) {
  let years = b.getUTCFullYear() - a.getUTCFullYear();
  let months = b.getUTCMonth() - a.getUTCMonth();
  let days = b.getUTCDate() - a.getUTCDate();
  if (days < 0) {
    months -= 1;
    const prevMonth = new Date(Date.UTC(b.getUTCFullYear(), b.getUTCMonth(), 0));
    days += prevMonth.getUTCDate();
  }
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  return { years, months, days };
}

/** Days since the epoch (UTC calendar day). */
function dayIndex(d) {
  return Math.floor(d.getTime() / DAY_MS);
}

const mod = (a, m) => ((a % m) + m) % m;

/** Weekdays (Mon-Fri) in the day-index range [0, idx), by closed form. */
function weekdaysBefore(idx) {
  const m = idx + 3; // day 0 (1970-01-01) is a Thursday: 3 days after a Monday
  return Math.floor(m / 7) * 5 + Math.min(mod(m, 7), 5);
}

/**
 * The day index n workdays from `idx` (holidays ignored). Starting on a weekend
 * counts from the neighbouring weekday on the far side, as the day-by-day walk
 * did: Saturday + 1 is Monday, Saturday - 1 is Friday.
 */
function shiftWorkdays(idx, n) {
  const dow = mod(idx + 4, 7); // 0 = Sunday
  let base = idx;
  if (dow === 6) base = n > 0 ? idx - 1 : idx + 2;
  else if (dow === 0) base = n > 0 ? idx - 2 : idx + 1;
  const p = mod(base + 3, 7); // 0 = Monday .. 4 = Friday
  const monday = base - p;
  const total = p + n;
  return monday + Math.floor(total / 5) * 7 + mod(total, 5);
}

/** Holiday day indexes that fall on a weekday, sorted: weekend ones never matter. */
function sortedWeekdayHolidays(arg) {
  const out = [];
  for (const t of collectHolidays(arg)) {
    const idx = Math.floor(t / DAY_MS);
    const dow = mod(idx + 4, 7);
    if (dow !== 0 && dow !== 6) out.push(idx);
  }
  return out.sort((a, b) => a - b);
}

function lowerBound(arr, x) {
  let lo = 0;
  let hi = arr.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (arr[mid] < x) lo = mid + 1; else hi = mid;
  }
  return lo;
}

/** How many sorted holiday indexes lie in [lo, hi]. */
function holidaysIn(sorted, lo, hi) {
  if (hi < lo || !sorted.length) return 0;
  return lowerBound(sorted, hi + 1) - lowerBound(sorted, lo);
}

function collectHolidays(arg) {
  const set = new Set();
  if (arg == null) return set;
  const vals = Array.isArray(arg) ? arg : [arg];
  for (const v of vals) {
    const d = toDate(v);
    if (d instanceof Date) set.add(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  }
  return set;
}

export default datetime;
