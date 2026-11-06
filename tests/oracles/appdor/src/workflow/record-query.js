/**
 * What a "Find records" step means, as one pure module both engines share.
 *
 * The step has always carried `filter`, `sort`, `limit` and (durable engine)
 * `offset`, and the builder documents the filter as a plain map —
 * `{"status": "open"}`, "leave empty for every record". Until 2026-10-08 the
 * worker's two record readers (`findRecords` for the flat engine, `db.find`
 * for the durable one) read `select('id,data')…limit(q.limit || 100)` and
 * dropped everything else. A rule written as "find the records whose Статус is
 * Открито, then count them" counted the whole table, and the browser preview
 * hid it because the preview never reads real rows. Found on appdor.com with a
 * real run: a daily digest reported all 29 nonconformities as open.
 *
 * Two filter dialects are accepted, because both are in use:
 *
 *   - **a plain map** `{ field: value }` — what the step form's placeholder
 *     teaches. Every key must match. A value that is an array means "any of";
 *     a cell that is an array (multi-select, link) matches when it contains
 *     the value. Comparison is by text, so `5` finds `"5"`, the way a person
 *     typing into a JSON box expects.
 *   - **a view filter tree** — `{ operator: 'and'|'or', children }`, a single
 *     `{ field, op, value }` condition, or an `{ expr }` — evaluated by
 *     `views/query.js`, so a filter copied from a view means the same thing
 *     here as it does on screen.
 *
 * The other half of the bug was ORDER: filtering has to happen over the whole
 * table and THEN take `limit`, never the other way round. Taking the first 100
 * rows and filtering those finds nothing when the matches are row 150. So a
 * filtered or sorted query pages through the table (up to `SCAN_CAP` rows)
 * before it applies offset and limit. A table bigger than the cap is an error,
 * not a quietly truncated answer — a truncated count is the same lie with a
 * smaller number.
 *
 * Pure: `queryRecords` is handed the page reader, so the worker keeps its own
 * guarded `from('table_rows')` read and this file never touches a client.
 */

import { filterRecords, sortRecords } from '../views/query.js'; import { t } from '../language.js';

/** Rows asked of the reader per page while scanning. */
export const PAGE_SIZE = 1000;

/** The most rows a filtered or sorted Find will scan before it refuses. */
export const SCAN_CAP = 50000;

/** The step's documented default when it names no limit. */
export const DEFAULT_LIMIT = 100;

/** Row columns a sort may name that live beside `data`, not inside it. */
const SYSTEM_SORT_FIELDS = ['created_at', 'updated_at'];

/**
 * A query the step cannot run as written.
 *
 * `permanent`: the same filter will be just as malformed on the third retry.
 * `effectNotApplied`: nothing was read, so nothing downstream acted on it.
 */
export class RecordQueryError extends Error {
  constructor(message, code) {
    super(message); this.code = code; // a stable reason; the message is translated
    this.name = 'RecordQueryError';
    this.permanent = true;
    this.effectNotApplied = true;
  }
}

function parseJsonOption(value, what) {
  if (typeof value !== 'string') return value;
  const text = value.trim();
  if (text === '') return null;
  try {
    return JSON.parse(text);
  } catch {
    throw new RecordQueryError(t(what === 'sort' ? 'workflow.run.error.findSortNotJson' : 'workflow.run.error.findFilterNotJson'), `${what}-not-json`);
  }
}

function isTreeNode(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value)
    && (value.operator === 'and' || value.operator === 'or'
      || typeof value.expr === 'string'
      || (typeof value.field === 'string' && typeof value.op === 'string'));
}

function isEmptyValue(value) {
  return value === null || value === undefined || value === '';
}

/** One cell against one expected value, by text. */
function sameValue(cell, expected) {
  if (isEmptyValue(cell) || isEmptyValue(expected)) return isEmptyValue(cell) && isEmptyValue(expected);
  if (typeof cell === 'object' || typeof expected === 'object') return JSON.stringify(cell) === JSON.stringify(expected);
  return String(cell) === String(expected);
}

function cellMatches(cell, expected) {
  if (Array.isArray(expected)) return expected.some((e) => cellMatches(cell, e));
  if (Array.isArray(cell)) return cell.length === 0 ? isEmptyValue(expected) : cell.some((c) => sameValue(c, expected));
  return sameValue(cell, expected);
}

/**
 * The step's filter as a predicate over `{ id, ...data }`, or null for "every record".
 *
 * @param {unknown} filter a plain map, a view filter tree, an array of
 *   conditions (all must hold), their JSON text, or empty
 * @param {Array} [fields] field definitions, for typed view-tree operators
 * @returns {((record: object) => boolean) | null}
 */
export function compileRecordFilter(filter, fields = []) {
  const parsed = parseJsonOption(filter, 'filter');
  if (parsed === null || parsed === undefined) return null;
  if (Array.isArray(parsed)) {
    if (parsed.length === 0) return null;
    const tree = { operator: 'and', children: parsed };
    return (record) => filterRecords([record], tree, fields).length === 1;
  }
  if (typeof parsed !== 'object') {
    throw new RecordQueryError(t('workflow.run.error.findFilterNotObject'), 'filter-not-object');
  }
  if (isTreeNode(parsed)) return (record) => filterRecords([record], parsed, fields).length === 1;
  const entries = Object.entries(parsed);
  if (entries.length === 0) return null;
  return (record) => entries.every(([field, expected]) => cellMatches(record[field], expected));
}

/**
 * The step's sort as `[{ field, direction }]`.
 *
 * Accepts the array the form's placeholder shows, a single object, its JSON
 * text, or a bare field name (`"-field"` for descending).
 */
export function normalizeRecordSort(sort) {
  if (typeof sort === 'string') {
    const text = sort.trim();
    if (text === '') return [];
    if (text.startsWith('[') || text.startsWith('{')) return normalizeRecordSort(parseJsonOption(text, 'sort'));
    return text.startsWith('-') ? [{ field: text.slice(1), direction: 'desc' }] : [{ field: text, direction: 'asc' }];
  }
  if (sort === null || sort === undefined) return [];
  const list = Array.isArray(sort) ? sort : [sort];
  return list
    .filter((s) => s && typeof s === 'object' && typeof s.field === 'string' && s.field)
    .map((s) => ({ field: s.field, direction: String(s.direction || 'asc').toLowerCase() === 'desc' ? 'desc' : 'asc' }));
}

function toCount(value, fallback) {
  if (value === null || value === undefined || value === '') return fallback;
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

/** A stored row as the record a step sees: its id beside its fields. */
export function rowToRecord(row) {
  return { id: row.id, ...((row && row.data) || {}) };
}

/**
 * Filter, sort, then offset and limit — in that order — over records already in hand.
 *
 * The flat engine's in-memory dataset path and the worker's scan both end
 * here. `limit` absent means no limit: the default belongs to the reader that
 * pages a real table, not to a caller holding a fixture.
 *
 * @param {Array<object>} records `{ id, ...fields }`
 * @param {{ filter?, sort?, offset?, limit?, fields?: Array, meta?: Map }} query
 *   `meta` maps a record to its row's system columns, for sorts on `created_at`
 *   or `updated_at` that the record's own fields do not carry.
 */
export function applyRecordQuery(records, query = {}) {
  const fields = query.fields || [];
  const match = compileRecordFilter(query.filter, fields);
  const sorts = normalizeRecordSort(query.sort);
  let out = match ? records.filter(match) : records.slice();
  if (sorts.length) {
    const meta = query.meta;
    const views = out.map((record) => {
      const system = meta && meta.get(record);
      if (!system) return record;
      const view = { ...record };
      for (const key of SYSTEM_SORT_FIELDS) if (!(key in record) && key in system) view[key] = system[key];
      return view;
    });
    const back = new Map(views.map((view, i) => [view, out[i]]));
    out = sortRecords(views, sorts, fields).map((view) => back.get(view));
  }
  const offset = toCount(query.offset, 0);
  const limit = query.limit === undefined || query.limit === null || query.limit === '' ? undefined : toCount(query.limit, undefined);
  if (offset || limit !== undefined) out = out.slice(offset, limit === undefined ? undefined : offset + limit);
  return out;
}

/**
 * Run a Find against a table through a page reader.
 *
 * @param {{ filter?, sort?, offset?, limit? }} q the step's query, as rendered
 * @param {(range: { from: number, to: number }) => Promise<Array<{ id, data, created_at?, updated_at? }>>} readRange
 *   reads rows `from..to` inclusive in a stable order and THROWS when it cannot
 *   read — an unreadable table must fail the run, never look empty
 * @param {{ pageSize?: number, scanCap?: number, defaultLimit?: number }} [options]
 * @returns {Promise<Array<object>>} records, `{ id, ...fields }`
 */
export async function queryRecords(q, readRange, options = {}) {
  const query = q || {};
  const pageSize = options.pageSize || PAGE_SIZE;
  const scanCap = options.scanCap || SCAN_CAP;
  const limit = toCount(query.limit, options.defaultLimit || DEFAULT_LIMIT) || (options.defaultLimit || DEFAULT_LIMIT);
  const offset = toCount(query.offset, 0);
  // Validate before reading: a malformed filter must fail even on an empty table.
  const match = compileRecordFilter(query.filter);
  const sorts = normalizeRecordSort(query.sort);

  if (!match && sorts.length === 0) {
    // Nothing to evaluate, so the reader's own order and range are the answer.
    const rows = await readRange({ from: offset, to: offset + limit - 1 });
    return (rows || []).slice(0, limit).map(rowToRecord);
  }

  const rows = [];
  for (let from = 0; ; from += pageSize) {
    const page = (await readRange({ from, to: from + pageSize - 1 })) || [];
    rows.push(...page);
    if (rows.length > scanCap) {
      throw new RecordQueryError(t('workflow.run.error.findScanCap', null, { cap: scanCap }), 'scan-cap');
    }
    if (page.length < pageSize) break;
  }
  const meta = new Map();
  const records = rows.map((row) => {
    const record = rowToRecord(row);
    meta.set(record, { created_at: row.created_at, updated_at: row.updated_at });
    return record;
  });
  return applyRecordQuery(records, { filter: query.filter, sort: sorts, offset, limit, meta });
}
