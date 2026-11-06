/**
 * Value model, blank semantics and type coercion for the formula engine.
 *
 * Values are native JS: number | string | boolean | Date | Array | null (blank)
 * | FormulaError. Blank is represented as `null`. Empty string is also treated
 * as blank by ISBLANK but retains its identity as text elsewhere.
 *
 * Blank semantics (REQ-FORMULAENGINE-09): arithmetic treats blank as
 * blank-propagating, not zero, unless coerced via TONUMBER. Aggregation
 * functions (SUM/COUNT/…) skip blanks per their own spec.
 *
 * Dependency-free.
 */

import { FormulaError, isError, valueError } from './errors.js';

export const BLANK = null;

/** A blank cell: null, undefined, or the empty string. */
export function isBlank(v) {
  return v === null || v === undefined || v === '';
}

export function isNumberValue(v) {
  return typeof v === 'number' && !Number.isNaN(v);
}

export function isTextValue(v) {
  return typeof v === 'string';
}

export function isBoolValue(v) {
  return typeof v === 'boolean';
}

export function isDateValue(v) {
  return v instanceof Date && !Number.isNaN(v.getTime());
}

export function isArrayValue(v) {
  return Array.isArray(v);
}

/**
 * The `typeof(x)` / `TYPE` result. One of:
 * 'blank' | 'number' | 'text' | 'boolean' | 'date' | 'array' | 'error'.
 */
export function typeOf(v) {
  if (isError(v)) return 'error';
  if (isBlank(v)) return 'blank';
  if (isBoolValue(v)) return 'boolean';
  if (isNumberValue(v)) return 'number';
  if (isDateValue(v)) return 'date';
  if (isArrayValue(v)) return 'array';
  if (isTextValue(v)) return 'text';
  return 'text';
}

/**
 * Excel-style TYPE code: 1 number, 2 text, 4 boolean, 16 error, 64 array,
 * plus 32 for date (an Appdor extension), 0 for blank.
 */
export function typeCode(v) {
  switch (typeOf(v)) {
    case 'number':
      return 1;
    case 'text':
      return 2;
    case 'boolean':
      return 4;
    case 'error':
      return 16;
    case 'array':
      return 64;
    case 'date':
      return 32;
    default:
      return 0;
  }
}

/**
 * Coerce to number. Blank -> null (propagates). Errors pass through. Booleans
 * map to 1/0. Dates map to their epoch-millis serial. Non-numeric text -> a
 * #VALUE! error. Returns a number, null, or FormulaError.
 */
const DECIMAL_TEXT = /^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/;

export function toNumber(v) {
  if (isError(v)) return v;
  if (isBlank(v)) return null;
  if (typeof v === 'number') return Number.isNaN(v) ? valueError() : v;
  if (typeof v === 'boolean') return v ? 1 : 0;
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'string') {
    const trimmed = v.trim();
    if (trimmed === '') return null;
    // Plain decimals and scientific notation only. Number() would also read
    // '0x10', '0b1', 'Infinity' and '1e999' as numbers, which no cell means.
    if (DECIMAL_TEXT.test(trimmed)) {
      const n = Number(trimmed);
      if (Number.isFinite(n)) return n;
    }
    return valueError(`Cannot convert "${v}" to a number`);
  }
  return valueError();
}

/**
 * Coerce to number treating blank as zero (for functions that opt in, e.g.
 * explicit arithmetic aggregation once a value is present).
 */

/** Coerce to text. Blank -> ''. Booleans -> 'true'/'false'. Errors pass through. */
export function toText(v) {
  if (isError(v)) return v;
  if (isBlank(v)) return '';
  if (typeof v === 'string') return v;
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return numberToText(v);
  if (v instanceof Date) return v.toISOString();
  if (Array.isArray(v)) return v.map((x) => (isBlank(x) ? '' : toText(x))).join(',');
  return String(v);
}

/** Render a number as text without locale artifacts or float noise. */
export function numberToText(n) {
  if (!Number.isFinite(n)) return String(n);
  if (Number.isInteger(n)) return String(n);
  // 15 significant digits: 0.1 + 0.2 is '0.3', not '0.30000000000000004'.
  return String(Number(n.toPrecision(15)));
}

/**
 * Coerce to boolean. Blank -> false. Numbers: 0 -> false else true. Text:
 * 'true'/'false' (case-insensitive), '1'/'0', '' -> false. Errors pass through.
 */
export function toBool(v) {
  if (isError(v)) return v;
  if (isBlank(v)) return false;
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  if (typeof v === 'string') {
    const t = v.trim().toLowerCase();
    if (t === 'true' || t === '1' || t === 'yes') return true;
    if (t === 'false' || t === '0' || t === 'no' || t === '') return false;
    return true; // any non-empty, non-false string is truthy
  }
  if (v instanceof Date) return true;
  if (Array.isArray(v)) return v.length > 0;
  return Boolean(v);
}

/**
 * A date-time string that names no zone — `2026-01-15T23:30:00`, or the same
 * with a space, with or without seconds and fractions.
 *
 * ECMA-262 reads the date-only form `2026-01-15` as UTC and this form as LOCAL
 * time, which is the one place the engine's stated rule — "all construction and
 * extraction uses UTC for determinism across time zones" (datetime.js) — was
 * not what the code did. Measured against the SQL backend, on a server whose
 * `TimeZone` is UTC and a harness in Europe/Berlin:
 *
 *     HOUR({When})   When = '2026-01-15T23:30:00'   in-process 22   SQL 23
 *
 * and the same value sorted into a different position. Nothing about that
 * answer is a property of the record: it is a property of the machine that
 * evaluated it, so two viewers in two zones saw two different cells and neither
 * matched the database. Date-only and zone-qualified strings already agreed and
 * are left exactly as they were.
 */
const NAIVE_DATETIME = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/;

/**
 * A complete ISO-8601 date or timestamp, anchored — the shape `compareValues`
 * is allowed to read as an instant rather than as text.
 */
const ISO_TEMPORAL = /^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/;

/**
 * Coerce to a Date. Blank -> null. Accepts Date, epoch millis number, ISO/parse-
 * able string. Non-date -> #VALUE! error.
 */
export function toDate(v) {
  if (isError(v)) return v;
  if (isBlank(v)) return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? valueError('Invalid date') : v;
  if (typeof v === 'number') {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? valueError('Invalid date') : d;
  }
  if (typeof v === 'string') {
    // ISO-8601 only. V8's legacy parser reads '10', 'hello 1' or '1/2/2026' as
    // local-time dates, which differs per machine; a non-ISO shape goes through
    // an explicit format (TODATE / DATETIME_PARSE) instead.
    const text = v.trim();
    if (ISO_TEMPORAL.test(text)) {
      const d = new Date(NAIVE_DATETIME.test(text) ? `${text.replace(' ', 'T')}Z` : text.replace(' ', 'T'));
      if (!Number.isNaN(d.getTime())) return d;
    }
    return valueError(`Cannot convert "${v}" to a date`);
  }
  return valueError();
}

/**
 * Flatten an argument list into a numeric list for aggregation. Blanks and
 * non-numeric text are skipped (spreadsheet range semantics), but a genuine
 * FormulaError value propagates (thrown for the caller to surface).
 */
export function collectNumbers(args) {
  const out = [];
  const walk = (v) => {
    if (isError(v)) throw v; // a real error value propagates
    if (isBlank(v)) return;
    if (Array.isArray(v)) {
      v.forEach(walk);
      return;
    }
    const n = toNumber(v);
    if (isError(n)) return; // unconvertible text is ignored, not an error
    if (n !== null) out.push(n);
  };
  args.forEach(walk);
  return out;
}

/** Flatten nested arrays/args into a flat value list (blanks preserved). */
export function flattenValues(args) {
  const out = [];
  const walk = (v) => {
    if (Array.isArray(v)) v.forEach(walk);
    else out.push(v);
  };
  args.forEach(walk);
  return out;
}

/**
 * Loose equality used by `=`/`==` and MATCH: number/number, text/text
 * (case-insensitive per spreadsheet convention), boolean, dates by time.
 */
export function looseEquals(a, b) {
  if (isBlank(a) && isBlank(b)) return true;
  if (isBlank(a) || isBlank(b)) return false;
  if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime();
  if (typeof a === 'number' && typeof b === 'number') return a === b;
  if (typeof a === 'boolean' || typeof b === 'boolean') return toBool(a) === toBool(b);
  if (typeof a === 'string' && typeof b === 'string') {
    return a.toLowerCase() === b.toLowerCase();
  }
  // Cross-type: compare via text.
  return toText(a) === toText(b);
}

/** Strict equality used by EXACT / SAME(exact): text is case-sensitive. */

/**
 * Ordering comparison for SORT and comparison operators. Returns a number
 * (<0, 0, >0) or a FormulaError on incomparable types.
 */
export function compareValues(a, b) {
  if (isBlank(a) && isBlank(b)) return 0;
  if (isBlank(a)) return -1;
  if (isBlank(b)) return 1;
  if (a instanceof Date && b instanceof Date) return a.getTime() - b.getTime();
  // Two ISO-8601 timestamps compare as INSTANTS, not as text.
  //
  // A date cell is stored as its string and `typedRecord` deliberately leaves it
  // that way, so `{When} > {Due}` reached the text branch below and compared
  // `'2026-02-01T00:00:00Z'` against `'2026-02-01'` character by character —
  // answering TRUE, where the same comparison in SQL casts both to
  // `timestamptz`, finds them equal, and answers FALSE. Same row, same
  // expression, two pages.
  //
  // Anchored on a full ISO shape rather than handed to `new Date()`, because
  // `new Date('10')` is a valid date and `{Qty} > {Price}` on two numeric
  // strings must not become a date comparison. Within ONE column every value
  // has the same shape and this changes nothing; it decides the case where a
  // date meets a datetime, or a zoned string meets a zoneless one.
  if (typeof a === 'string' && typeof b === 'string' && ISO_TEMPORAL.test(a) && ISO_TEMPORAL.test(b)) {
    const da = toDate(a);
    const db = toDate(b);
    if (da instanceof Date && db instanceof Date) return da.getTime() - db.getTime();
  }
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  if (typeof a === 'boolean' && typeof b === 'boolean') {
    return (a ? 1 : 0) - (b ? 1 : 0);
  }
  const ta = toText(a);
  const tb = toText(b);
  if (isError(ta)) return ta;
  if (isError(tb)) return tb;
  return ta < tb ? -1 : ta > tb ? 1 : 0;
}

export { FormulaError };
