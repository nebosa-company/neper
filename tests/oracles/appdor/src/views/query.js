/**
 * View query engine (LC15 / views-core): the pure, deterministic data pipeline
 * a saved view applies to a set of records — filter → sort → group → summarize,
 * plus row coloring and quick search. Field-type-aware and dependency-light; the
 * optional expression filter/color nodes evaluate through the sandboxed formula
 * engine.
 *
 * This owns the transformation semantics that both the client and the server
 * query layer share; persistence, virtualization, and SQL pushdown live
 * elsewhere. Records are plain objects keyed by field name; `fields` is an array
 * of `{ name, type, options? }` describing the columns.
 */

import { matchesBucket } from '../charts/buckets.js';
import { evaluate, isError } from '../formula/index.js';

const DAY_MS = 86_400_000;

// --- value helpers --------------------------------------------------------

function isEmpty(v) {
  return v === null || v === undefined || v === '' || (Array.isArray(v) && v.length === 0);
}

function asArray(v) {
  if (Array.isArray(v)) return v;
  if (isEmpty(v)) return [];
  return [v];
}

function toNum(v) {
  if (isEmpty(v)) return null;
  const n = Number(v);
  return Number.isNaN(n) ? null : n;
}

/**
 * A date-time string that names no zone. Kept in step with `NAIVE_DATETIME` in
 * `src/formula/values.js`, where the reasoning lives.
 *
 * Duplicated rather than imported for the same reason `toDate` itself is:
 * this module is the view engine and it holds its own coercions. What it must
 * not do is hold a DIFFERENT rule — a saved view sorted `2026-02-01T00:00:00Z`
 * ahead of `2026-02-01` while the database called them equal, because
 * `new Date('2026-02-01T00:00:00')` is the evaluating machine's midnight and
 * `'2026-02-01'` is UTC midnight. The rows are the same rows; the page is a
 * different page.
 */
const NAIVE_DATETIME = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/;

function toDate(v) {
  if (isEmpty(v)) return null;
  const d = v instanceof Date ? v : new Date(NAIVE_DATETIME.test(v) ? `${String(v).replace(' ', 'T')}Z` : v);
  return Number.isNaN(d.getTime()) ? null : d;
}

function dayStart(d) {
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

function lc(v) {
  return String(v ?? '').toLowerCase();
}

function fieldMap(fields) {
  const m = new Map();
  for (const f of fields || []) m.set(f.name, f);
  return m;
}

// --- date operand resolution ---------------------------------------------

function clockNow(ctx) {
  if (ctx && ctx.now instanceof Date) return new Date(ctx.now.getTime());
  if (ctx && (typeof ctx.now === 'number' || typeof ctx.now === 'string')) {
    const d = new Date(ctx.now);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return new Date();
}

/** Resolve a filter operand that may be a relative date token to a Date. */
function resolveDateValue(value, ctx) {
  if (value && typeof value === 'object' && value.relative) {
    const now = clockNow(ctx);
    const base = dayStart(now);
    if (value.relative === 'today') return new Date(base);
    if (value.relative === 'yesterday') return new Date(base - DAY_MS);
    if (value.relative === 'tomorrow') return new Date(base + DAY_MS);
    return now;
  }
  if (value === 'today' || value === 'yesterday' || value === 'tomorrow') {
    return resolveDateValue({ relative: value }, ctx);
  }
  return toDate(value);
}

/**
 * Resolve a [start, end) range for `within`-style date filters.
 *
 * Returns NULL when the operand names no range at all — an operator chosen but
 * a date not yet typed, or a bound that does not parse. `within` then matches
 * nothing, which is what every other date operator here already does with an
 * unusable operand (`on`, `before`, `after` and both `onOr*` go through
 * `sameDay`/`cmpDay`, which answer false when `b` is null).
 *
 * That agreement is the whole point, and the direction matters. This used to
 * return `[-Infinity, Infinity]` — a range containing every date — so a
 * half-written `within` matched EVERY record while its five siblings matched
 * none. `matchesFilter` is not only the grid's: it decides record-level
 * permission rules (`permissions/record-rules.js`), which workflow rules fire
 * (`workflows/registry.js`), and what a portal visitor sees
 * (`portal/index.js`). An unfilled date box that widens a permission rule to
 * every row is a failure that shows nothing on screen — the rule looks
 * configured — and `condition-builder.js#rowsToTree` cannot screen it out,
 * because a row with a field and an operator but no value is a COMPLETE row as
 * far as it can tell, and it writes `value: ''`.
 */
function resolveDateRange(value, ctx) {
  const now = clockNow(ctx);
  const base = dayStart(now);
  if (value && typeof value === 'object') {
    if (value.relative === 'today') return [base, base + DAY_MS];
    if (value.relative === 'yesterday') return [base - DAY_MS, base];
    if (value.relative === 'tomorrow') return [base + DAY_MS, base + 2 * DAY_MS];
    if (value.relative === 'lastNDays') return [base - (value.days || 0) * DAY_MS, base + DAY_MS];
    if (value.relative === 'nextNDays') return [base, base + ((value.days || 0) + 1) * DAY_MS];
    if (value.start != null || value.end != null) {
      const s = value.start != null ? toDate(value.start) : null;
      const e = value.end != null ? toDate(value.end) : null;
      // A bound that was SPECIFIED but does not parse leaves no usable range.
      // Only an ABSENT bound is genuinely open-ended: `{start: '2026-01-01'}`
      // means "from January onwards" and keeps its infinite end.
      if ((value.start != null && !s) || (value.end != null && !e)) return null;
      return [s ? s.getTime() : -Infinity, e ? e.getTime() + DAY_MS : Infinity];
    }
  }
  const d = resolveDateValue(value, ctx);
  return d ? [dayStart(d), dayStart(d) + DAY_MS] : null;
}

// --- operator tables ------------------------------------------------------

const TEXT_OPS = {
  contains: (a, b) => lc(a).includes(lc(b)),
  notContains: (a, b) => !lc(a).includes(lc(b)),
  is: (a, b) => lc(a) === lc(b),
  isNot: (a, b) => lc(a) !== lc(b),
  startsWith: (a, b) => lc(a).startsWith(lc(b)),
  endsWith: (a, b) => lc(a).endsWith(lc(b)),
  isEmpty: (a) => isEmpty(a),
  isNotEmpty: (a) => !isEmpty(a),
};

const NUMBER_OPS = {
  '=': (a, b) => toNum(a) === toNum(b),
  '!=': (a, b) => toNum(a) !== toNum(b),
  '<': (a, b) => toNum(a) !== null && toNum(a) < toNum(b),
  '<=': (a, b) => toNum(a) !== null && toNum(a) <= toNum(b),
  '>': (a, b) => toNum(a) !== null && toNum(a) > toNum(b),
  '>=': (a, b) => toNum(a) !== null && toNum(a) >= toNum(b),
  isEmpty: (a) => isEmpty(a),
  isNotEmpty: (a) => !isEmpty(a),
};

const SELECT_OPS = {
  is: (a, b) => a === b,
  isNot: (a, b) => a !== b,
  isAnyOf: (a, b) => asArray(b).includes(a),
  isNoneOf: (a, b) => !asArray(b).includes(a),
  isEmpty: (a) => isEmpty(a),
  isNotEmpty: (a) => !isEmpty(a),
};

const MULTISELECT_OPS = {
  hasAnyOf: (a, b) => asArray(a).some((x) => asArray(b).includes(x)),
  hasAllOf: (a, b) => asArray(b).every((x) => asArray(a).includes(x)),
  hasNoneOf: (a, b) => !asArray(a).some((x) => asArray(b).includes(x)),
  isEmpty: (a) => asArray(a).length === 0,
  isNotEmpty: (a) => asArray(a).length > 0,
};

const CHECKBOX_OPS = {
  isChecked: (a) => a === true,
  isUnchecked: (a) => a !== true,
};

const DATE_OPS = {
  on: (a, _b, ctx, raw) => sameDay(a, resolveDateValue(raw, ctx)),
  before: (a, _b, ctx, raw) => cmpDay(a, resolveDateValue(raw, ctx)) < 0,
  after: (a, _b, ctx, raw) => cmpDay(a, resolveDateValue(raw, ctx)) > 0,
  onOrBefore: (a, _b, ctx, raw) => cmpDay(a, resolveDateValue(raw, ctx)) <= 0,
  onOrAfter: (a, _b, ctx, raw) => cmpDay(a, resolveDateValue(raw, ctx)) >= 0,
  within: (a, _b, ctx, raw) => {
    const d = toDate(a);
    if (!d) return false;
    const range = resolveDateRange(raw, ctx);
    if (!range) return false;
    const [start, end] = range;
    return d.getTime() >= start && d.getTime() < end;
  },
  isEmpty: (a) => isEmpty(a),
  isNotEmpty: (a) => !isEmpty(a),
};

const USER_OPS = {
  is: (a, b) => a === b,
  isNot: (a, b) => a !== b,
  isCurrentUser: (a, _b, ctx) => a === (ctx && ctx.userId),
  isEmpty: (a) => isEmpty(a),
  isNotEmpty: (a) => !isEmpty(a),
};

const OP_TABLES = {
  text: TEXT_OPS,
  number: NUMBER_OPS,
  currency: NUMBER_OPS,
  percent: NUMBER_OPS,
  rating: NUMBER_OPS,
  select: SELECT_OPS,
  multiselect: MULTISELECT_OPS,
  checkbox: CHECKBOX_OPS,
  date: DATE_OPS,
  datetime: DATE_OPS,
  user: USER_OPS,
  // A masked column answers only "is it set". With the text table it fell back
  // to, `contains` / `startsWith` read a password one character at a time —
  // through the grid's filter and through every API that filters with this.
  password: { isEmpty: TEXT_OPS.isEmpty, isNotEmpty: TEXT_OPS.isNotEmpty },
};

/**
 * The operators this engine can actually apply to a field of `type`.
 *
 * Exported for the pickers. `evalCondition` looks the operator up in the table
 * for the condition's type and returns FALSE when it is not there — so a
 * control that offers `hasAnyOf` on an attachment column (the field registry
 * calls that kind `multiselect`; this file has no `attachment` entry and falls
 * back to the text operators) builds a condition that quietly removes every
 * record. On screen that is indistinguishable from "there is no data", which
 * is the worst way for a filter to fail.
 *
 * The fallback is `evalCondition`'s own, deliberately: one function decides
 * what an unknown type filters with, so a picker and the engine cannot drift.
 *
 * @param {string} type field type as the condition carries it
 * @returns {string[]} operator ids, in table order
 */
export function filterOperatorsFor(type) {
  return Object.keys(OP_TABLES[type] || TEXT_OPS);
}

function sameDay(a, b) {
  const da = toDate(a);
  if (!da || !b) return false;
  return dayStart(da) === dayStart(b);
}

function cmpDay(a, b) {
  const da = toDate(a);
  if (!da || !b) return NaN;
  return dayStart(da) - dayStart(b);
}

// --- filter evaluation ----------------------------------------------------

function evalCondition(node, record, fields, ctx) {
  if (node.expr) {
    return truthy(evaluate(node.expr, { ...ctx, fields: record }));
  }
  if (node.op === 'inBucket' || node.op === 'notInBuckets') return matchesBucket(record[node.field], node);
  const field = fields.get(node.field);
  const type = node.type || (field && field.type) || 'text';
  const table = OP_TABLES[type] || TEXT_OPS;
  const fn = table[node.op];
  if (!fn) return false;
  const cell = record[node.field];
  return !!fn(cell, node.value, ctx, node.value);
}

function truthy(v) {
  if (isError(v)) return false;
  if (v === true) return true;
  if (v === false || v == null || v === '') return false;
  if (typeof v === 'number') return v !== 0;
  if (Array.isArray(v)) return v.length > 0;
  return true;
}

/** Evaluate a (possibly nested) filter tree against a record. */
export function matchesFilter(node, record, fields, ctx = {}) {
  if (!node) return true;
  const fm = fields instanceof Map ? fields : fieldMap(fields);
  return evalTree(node, record, fm, ctx);
}

function evalTree(node, record, fm, ctx) {
  if (node.operator === 'and' || node.operator === 'or') {
    const children = node.children || [];
    if (children.length === 0) return true;
    return node.operator === 'and'
      ? children.every((c) => evalTree(c, record, fm, ctx))
      : children.some((c) => evalTree(c, record, fm, ctx));
  }
  return evalCondition(node, record, fm, ctx);
}

export function filterRecords(records, tree, fields, ctx = {}) {
  if (!tree) return records.slice();
  const fm = fieldMap(fields);
  return records.filter((r) => evalTree(tree, r, fm, ctx));
}

// --- sorting --------------------------------------------------------------

function collate(a, b, field) {
  const type = field && field.type;
  // Sorting by a password orders the rows by it, which is a way of reading it.
  if (type === 'password') return 0;
  if (type === 'select' && field.options) {
    // Options are stored as strings, `{label}` or `{value,label}`.
    const values = field.options.map((o) => (o && typeof o === 'object' ? (o.value !== undefined ? o.value : o.label) : o));
    const ia = values.indexOf(a);
    const ib = values.indexOf(b);
    return (ia === -1 ? Infinity : ia) - (ib === -1 ? Infinity : ib);
  }
  if (type === 'number' || type === 'currency' || type === 'percent' || type === 'rating') {
    const na = toNum(a);
    const nb = toNum(b);
    if (na === null && nb === null) return 0;
    if (na === null) return 1;
    if (nb === null) return -1;
    return na - nb;
  }
  if (type === 'date' || type === 'datetime') {
    const da = toDate(a);
    const db = toDate(b);
    if (!da && !db) return 0;
    if (!da) return 1;
    if (!db) return -1;
    return da.getTime() - db.getTime();
  }
  if (isEmpty(a) && isEmpty(b)) return 0;
  if (isEmpty(a)) return 1;
  if (isEmpty(b)) return -1;
  // `numeric`, so `Item 2` sorts before `Item 10` and `NCR-9` before `NCR-10`.
  return String(a).localeCompare(String(b), undefined, { numeric: true });
}

/** Stable multi-level sort. `sorts`: [{ field, direction }]. */
export function sortRecords(records, sorts, fields) {
  if (!sorts || sorts.length === 0) return records.slice();
  const fm = fieldMap(fields);
  const decorated = records.map((r, i) => ({ r, i }));
  decorated.sort((x, y) => {
    for (const s of sorts) {
      const va = x.r[s.field];
      const vb = y.r[s.field];
      // Empty cells always sort last, independent of asc/desc (Airtable parity).
      const ea = isEmpty(va);
      const eb = isEmpty(vb);
      if (ea && eb) continue;
      if (ea) return 1;
      if (eb) return -1;
      let c = collate(va, vb, fm.get(s.field));
      if (s.direction === 'desc') c = -c;
      if (c !== 0) return c;
    }
    return x.i - y.i; // stable
  });
  return decorated.map((d) => d.r);
}

// --- grouping -------------------------------------------------------------

const NO_VALUE = Symbol('no-value');

/** One stable object per distinct array content, so a Map keys equal arrays together. */
function arrayKey(arr, seen) {
  const id = JSON.stringify(arr);
  if (!seen.has(id)) seen.set(id, arr);
  return seen.get(id);
}

/** Group records by one field; empty values form an explicit "No value" group. */
export function groupRecords(records, groupSpec, fields) {
  const spec = typeof groupSpec === 'string' ? { field: groupSpec } : groupSpec;
  const fm = fieldMap(fields);
  const field = fm.get(spec.field);
  const buckets = new Map();
  const arrays = new Map(); // content key -> the first array seen
  for (const r of records) {
    const raw = r[spec.field];
    // Arrays (multiselect / link) are a new object per record: key them by
    // content so identical selections land in one group.
    const key = isEmpty(raw) ? NO_VALUE : Array.isArray(raw) ? arrayKey(raw, arrays) : raw;
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(r);
  }
  let keys = [...buckets.keys()];
  keys.sort((a, b) => {
    if (a === NO_VALUE) return 1;
    if (b === NO_VALUE) return -1;
    let c = collate(a, b, field);
    if (spec.direction === 'desc') c = -c;
    return c;
  });
  // `summaries` is attached later by `applyView`, only when the view config
  // asks for aggregates — declaring it optional here is what lets that
  // assignment be checked instead of inferred away.
  return /** @type {{value: *, label: string, records: *, count: number, summaries?: Object.<string, *>}[]} */ (
    keys.map((k) => ({
      value: k === NO_VALUE ? null : k,
      label: k === NO_VALUE ? 'No value' : Array.isArray(k) ? k.join(', ') : String(k),
      records: buckets.get(k),
      count: buckets.get(k).length,
    }))
  );
}

// --- summaries ------------------------------------------------------------

/** Checkbox truthiness, matching the `bool` kind's own parse in the registry. */
const isChecked = (v) => v === true || v === 'true' || v === 1 || v === '1';

/**
 * Milliseconds in an average month, for `rangeMonths`.
 *
 * An average, and deliberately: a calendar-accurate month count needs two
 * concrete endpoints and a rounding rule ("is 31 Jan to 1 Mar one month or
 * two?"), and the footer is showing a magnitude, not a billing period. Airtable
 * makes the same approximation for the same reason.
 */
const MONTH_MS = 30.436_875 * 86_400_000;

export const SUMMARY_FUNCTIONS = {
  none: () => null,
  // The plain record count — the single most-used summary in every grid
  // product surveyed, and the one this footer did not have. `filled`, `empty`
  // and `unique` were all here; the total was not.
  count: (vals) => vals.length,
  filled: (vals) => vals.filter((v) => !isEmpty(v)).length,
  empty: (vals) => vals.filter((v) => isEmpty(v)).length,
  unique: (vals) => new Set(vals.filter((v) => !isEmpty(v)).map((v) => JSON.stringify(v))).size,
  percentFilled: (vals) => (vals.length ? (vals.filter((v) => !isEmpty(v)).length / vals.length) * 100 : 0),
  percentEmpty: (vals) => (vals.length ? (vals.filter((v) => isEmpty(v)).length / vals.length) * 100 : 0),
  percentUnique: (vals) =>
    vals.length ? (new Set(vals.filter((v) => !isEmpty(v)).map((v) => JSON.stringify(v))).size / vals.length) * 100 : 0,
  sum: (vals) => nums(vals).reduce((a, b) => a + b, 0),
  average: (vals) => (nums(vals).length ? nums(vals).reduce((a, b) => a + b, 0) / nums(vals).length : null),
  median: (vals) => median(nums(vals)),
  min: (vals) => minMax(vals, 'min'),
  max: (vals) => minMax(vals, 'max'),
  range: (vals) => {
    const lo = minMax(vals, 'min');
    const hi = minMax(vals, 'max');
    if (lo === null || hi === null) return null;
    if (lo instanceof Date && hi instanceof Date) return (hi.getTime() - lo.getTime()) / DAY_MS;
    // `minMax` yields whatever the column holds; `range` is only meaningful
    // for the numeric case, which the Date branch above has already left.
    return Number(hi) - Number(lo);
  },
  stdev: (vals) => {
    const n = nums(vals);
    if (n.length < 2) return null;
    const m = n.reduce((a, b) => a + b, 0) / n.length;
    return Math.sqrt(n.reduce((a, b) => a + (b - m) * (b - m), 0) / (n.length - 1));
  },
  variance: (vals) => {
    const n = nums(vals);
    if (n.length < 2) return null;
    const m = n.reduce((a, b) => a + b, 0) / n.length;
    // Sample variance, so it is the square of `stdev` above rather than a
    // second, differently-normalized statistic sitting next to it in the menu.
    return n.reduce((a, b) => a + (b - m) * (b - m), 0) / (n.length - 1);
  },
  earliest: (vals) => minMax(vals, 'min'),
  latest: (vals) => minMax(vals, 'max'),

  // --- date spans, in a stated unit ---------------------------------------
  //
  // `range` returns days for dates and a bare difference for numbers, and the
  // formatter printed both as an unlabelled number: "Range: 47" could be
  // dollars or days. These two say which.
  rangeDays: (vals) => {
    const span = dateSpanMs(vals);
    return span === null ? null : span / DAY_MS;
  },
  rangeMonths: (vals) => {
    const span = dateSpanMs(vals);
    return span === null ? null : span / MONTH_MS;
  },

  // --- checkbox ------------------------------------------------------------
  //
  // An unchecked box is stored as `false`, `null` or absent depending on how
  // the row was written, so "unchecked" is "not checked" rather than
  // "explicitly false" — otherwise a column nobody has touched summarizes as
  // zero of both.
  checked: (vals) => vals.filter(isChecked).length,
  unchecked: (vals) => vals.filter((v) => !isChecked(v)).length,
  percentChecked: (vals) => (vals.length ? (vals.filter(isChecked).length / vals.length) * 100 : 0),
  percentUnchecked: (vals) => (vals.length ? (vals.filter((v) => !isChecked(v)).length / vals.length) * 100 : 0),

  /**
   * Per-option counts, commonest first.
   *
   * The one function here that does NOT return a scalar. Every other value is a
   * number, a Date or null and `formatSummary` assumes that, so this returns a
   * tagged object rather than a bare Map — a renderer can then tell a
   * distribution from a number without guessing, and a future bar chart has
   * somewhere to hang off.
   */
  distribution: (vals) => {
    const counts = new Map();
    for (const v of vals) {
      if (isEmpty(v)) continue;
      // A multiselect cell holds several options and each one counts.
      for (const item of Array.isArray(v) ? v : [v]) {
        if (isEmpty(item)) continue;
        const label = String(item);
        counts.set(label, (counts.get(label) || 0) + 1);
      }
    }
    if (!counts.size) return null;
    return {
      kind: 'distribution',
      entries: [...counts.entries()]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .map(([label, count]) => ({ label, count })),
    };
  },

  /**
   * Total attachment size in bytes.
   *
   * Reads `size` off each attachment descriptor. A cell holding plain strings
   * (a column converted to attachment, say) contributes nothing rather than
   * NaN — a footer reading "NaN" is worse than one reading "0 B".
   */
  totalSize: (vals) => {
    let total = 0;
    for (const v of vals) {
      if (isEmpty(v)) continue;
      for (const file of Array.isArray(v) ? v : [v]) {
        const size = file && typeof file === 'object' ? Number(file.size) : NaN;
        if (Number.isFinite(size)) total += size;
      }
    }
    return { kind: 'bytes', bytes: total };
  },
};

/** The span between the earliest and latest date in a column, in ms. */
function dateSpanMs(vals) {
  const lo = minMax(vals, 'min');
  const hi = minMax(vals, 'max');
  if (!(lo instanceof Date) || !(hi instanceof Date)) return null;
  return hi.getTime() - lo.getTime();
}

function nums(vals) {
  return vals.map(toNum).filter((n) => n !== null);
}

function median(arr) {
  if (!arr.length) return null;
  const s = [...arr].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

function isDateLike(v) {
  return v instanceof Date || (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}|\d\/\d/.test(v));
}

function minMax(vals, which) {
  const nonEmpty = vals.filter((v) => !isEmpty(v));
  // Only treat as dates when every non-empty value is date-like, so numeric
  // columns are never misread as epoch timestamps.
  if (nonEmpty.length && nonEmpty.every(isDateLike)) {
    const t = nonEmpty.map((v) => toDate(v)).filter(Boolean).map((d) => d.getTime());
    if (!t.length) return null;
    return new Date(which === 'min' ? Math.min(...t) : Math.max(...t));
  }
  const numbers = nums(vals);
  if (!numbers.length) return null;
  return which === 'min' ? Math.min(...numbers) : Math.max(...numbers);
}

/** Compute a summary for a column over a set of records. */
export function summarize(records, fieldName, fn) {
  const impl = SUMMARY_FUNCTIONS[fn];
  if (!impl) return null;
  return impl(records.map((r) => r[fieldName]));
}

// --- row coloring ---------------------------------------------------------

/**
 * Resolve a row's color per the view color config:
 *   { mode:'none' } | { mode:'select', field } |
 *   { mode:'rules', rules:[{ filter?, expr?, color }] } (first match wins)
 */
export function rowColor(record, color, fields, ctx = {}) {
  if (!color || color.mode === 'none' || !color.mode) return null;
  const fm = fieldMap(fields);
  if (color.mode === 'select') {
    const field = fm.get(color.field);
    const value = record[color.field];
    if (isEmpty(value) || !field || !field.optionColors) return null;
    return field.optionColors[value] || null;
  }
  if (color.mode === 'rules') {
    for (const rule of color.rules || []) {
      const matched = rule.filter
        ? evalTree(rule.filter, record, fm, ctx)
        : rule.expr
          ? truthy(evaluate(rule.expr, { ...ctx, fields: record }))
          : false;
      if (matched) return rule.color;
    }
  }
  return null;
}

// --- quick search ---------------------------------------------------------

/** Substring search across the given (visible) field names; blank term is a no-op. */
export function quickSearch(records, term, fieldNames) {
  if (!term) return records.slice();
  const needle = lc(term);
  const names = fieldNames && fieldNames.length ? fieldNames : null;
  return records.filter((r) => {
    const keys = names || Object.keys(r);
    return keys.some((k) => {
      const v = r[k];
      if (isEmpty(v)) return false;
      return lc(Array.isArray(v) ? v.join(' ') : v).includes(needle);
    });
  });
}

// --- orchestrator ---------------------------------------------------------

/**
 * Apply a full view config to a record set.
 * @param {object[]} records
 * @param {ViewConfig} [config]
 * @param {object[]} [fields] column descriptors
 * @param {Object.<string, *>} [ctx] { now, userId, … }
 * @returns {{records: object[], groups?: object[], summaries?: Object.<string, *>, visibleFields?: string[]}}
 *
 * @typedef {Object} ViewConfig
 * @property {*} [filters]
 * @property {*} [sorts]
 * @property {string[]} [group_by]
 * @property {*} [color]
 * @property {Object.<string, string>} [summaries] field name → aggregate name
 * @property {string} [search]
 * @property {string[]} [searchFields]
 * @property {string[]} [visibleFields]  which fields are shown; hidden fields
 *   still participate in filters/sorts/grouping but are omitted from the
 *   returned record keys. When absent, all fields are visible.
 * @property {string} [newFieldPolicy]  'show' (default) or 'hide' — determines
 *   visibility of fields not explicitly listed in `visibleFields`.
 */
export function applyView(records, config = {}, fields = [], ctx = {}) {
  let rows = records.slice();
  if (config.filters) rows = filterRecords(rows, config.filters, fields, ctx);
  if (config.search) rows = quickSearch(rows, config.search, config.searchFields);
  if (config.sorts) rows = sortRecords(rows, config.sorts, fields);

  const out = { records: rows };

  // Field visibility (LC15.25): hidden fields stay in the data for filters
  // and sorts to work, but the caller can drop them from the render layer.
  if (config.visibleFields && config.visibleFields.length) {
    // When newFieldPolicy is 'hide', only explicitly-listed fields are visible.
    // When it is 'show' (default), unlisted fields are visible — so the set
    // of visible fields is the complement only when the policy says 'hide'.
    out.visibleFields = config.newFieldPolicy === 'hide'
      ? config.visibleFields.slice()
      : null;
    if (out.visibleFields) {
      // Strip non-visible keys from each record's render output without
      // mutating the original data — the caller receives a projection.
      out.records = rows.map((r) => {
        const projected = {};
        for (const k of out.visibleFields) {
          if (k in r) projected[k] = r[k];
        }
        return projected;
      });
    }
  }

  if (config.summaries) {
    out.summaries = {};
    for (const [fieldName, fn] of Object.entries(config.summaries)) {
      out.summaries[fieldName] = summarize(rows, fieldName, fn);
    }
  }

  // Two-level sub-grouping (LC15.22): group_by is [primary, secondary]
  if (config.group_by && config.group_by.length) {
    const primary = config.group_by[0];
    const secondary = config.group_by.length >= 2 ? config.group_by[1] : null;

    if (secondary) {
      // Two-level: import subGroupRecords from query-language to avoid circular deps.
      // We compute it inline here to keep query.js self-contained.
      const top = groupRecords(rows, primary, fields);
      out.groups = top.map((g) => ({
        value: g.value,
        label: g.label,
        count: g.count,
        subgroups: groupRecords(g.records, secondary, fields).map((s) => ({
          value: s.value,
          label: s.label,
          records: s.records,
          count: s.count,
        })),
      }));
    } else {
      const groups = groupRecords(rows, primary, fields);
      if (config.summaries) {
        for (const g of groups) {
          g.summaries = {};
          for (const [fieldName, fn] of Object.entries(config.summaries)) {
            g.summaries[fieldName] = summarize(g.records, fieldName, fn);
          }
        }
      }
      out.groups = groups;
    }
  }

  return out;
}

export { isEmpty };
