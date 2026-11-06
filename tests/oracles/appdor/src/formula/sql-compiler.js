/**
 * SQL compiler for formula expressions (LC10.5, LC10.14).
 *
 * Translates a formula AST into a parameterized SQL WHERE clause fragment.
 * The compiler walks the AST and produces a `{sql, params}` pair where `sql`
 * is a PostgreSQL-compatible SQL string with `$1, $2, ...` placeholders and
 * `params` is the corresponding ordered array of values.
 *
 * Architecture:
 *   - Pure function: no network, no database, no side effects.
 *   - Parameterized: every literal becomes a `$N` placeholder — no string
 *     concatenation of user values into SQL, so SQL injection is impossible
 *     by construction (LC10.14).
 *   - Pushdown-aware: functions marked `pushdown: false` or `volatile: true`
 *     in the registry cause the compiler to return `{pushdown: 'none'}` for
 *     that subtree; the host composes a hybrid plan.
 *   - Conformance: produces results identical to the in-process evaluator
 *     for every supported operator and function (LC10.5).
 *
 * Usage:
 *   import { compileToSql } from './formula/sql-compiler.js';
 *   const { sql, params, pushdown } = compileToSql('{Price} * {Qty} > 100', {
 *     Price: { type: 'number', column: 'price' },
 *     Qty:   { type: 'number', column: 'quantity' },
 *   });
 *   // sql:    '"price" * "quantity" > $1'
 *   // params: [100]
 */

import { getRegistry } from './default-registry.js';
import { parse } from './parser.js';
import { MAX_REGEX_INPUT } from './text.js';

/**
 * The largest count or offset a text function will hand Postgres.
 *
 * `LEFT`, `RIGHT`, `MID`, `REPLACE` and `REPEAT` take their count from a CELL,
 * and the evaluator has an answer for every double it could hold —
 * `LEFT(text, 9e15)` is the whole string. Postgres takes an `int`, so the same
 * cell was `integer out of range`, which is not a different answer, it is no
 * page at all: one oversized number anywhere in the column killed every query
 * that used the expression (LC10.33).
 *
 * 2^30-1 rather than `int`'s own 2^31-1, because `OVERLAY(x PLACING y FROM s
 * FOR n)` ADDS the two internally, and the sum overflows where neither operand
 * does — measured, `OVERLAY('abcdef' PLACING 'z' FROM 1 FOR 2147483647)`
 * raises `integer out of range`. Clamping both to 2^30-1 keeps every sum
 * inside an `int`, and nothing is lost by it: a `text` value stops at 1GB, so
 * no count at or above 2^30 can behave differently from one at the clamp.
 */
const SQL_TEXT_INDEX_MAX = 1073741823;

/**
 * The largest fragment any ONE compiled node may carry before the whole
 * compile is abandoned.
 *
 * Several emissions below interpolate an already-compiled argument MORE THAN
 * ONCE: `EXP` names its argument three times (a guard at each end of the range
 * and the call itself), and so do `_power`, `ASIN`/`ACOS` and `MOD`. Nesting
 * them therefore multiplies the emitted text by three PER LEVEL, and until this
 * constant existed the only size gate in the product ran on the FINISHED
 * string — `predicateShapeReason`'s `text.length > 4000` in
 * `src/api/formula-query.js`, which is reached after `compileToSql` has already
 * built the whole rope and `trim()` has flattened it.
 *
 * Measured on this tree through `compileFilter` with a one-column schema, with
 * the guard removed:
 *
 *     72 request bytes  (EXP nested 13 deep)       171 ms,  300 MB RSS
 *   1116 request bytes  (16 x EXP nested 11)      1251 ms, 3198 MB RSS
 *   2436 request bytes  (40 x EXP nested 10)      1865 ms, 2710 MB RSS
 *
 * Every one of those ends in `unsupported_expression`: the whole cost is paid
 * to reject the input. `POST /v1/tables/{id}/query` reaches this from
 * ai-proxy, which is one single-threaded Node process also serving `/api/`,
 * the inbound webhook doors, OAuth and the rest of `/v1`, inside a task whose
 * whole memory budget is 4096 MiB (`infra/fargate/cloudformation.yml`). So a
 * 2 KB body is a stall for every tenant, and a slightly larger one is an OOM.
 *
 * The bound is therefore applied where the text GROWS — once per node, in
 * `compile()` — rather than to the finished fragment. 32768 is eight times the
 * 4000 the database will accept, and every intermediate fragment of an
 * expression that passes THAT gate is contained in the finished one, so
 * nothing that used to compile stops compiling. `.length` on a V8 rope is O(1)
 * and does not flatten it, so the check itself costs nothing.
 */
const SQL_FRAGMENT_MAX = 32768;

/**
 * Raised by `compile()` when a node passes `SQL_FRAGMENT_MAX`.
 *
 * A throw rather than a `pushdown: 'none'` return, because 'none' unwinds one
 * level at a time: a WIDE expression — forty nested `EXP` bombs joined by `||`
 * — would still let every sibling build its own oversized fragment before the
 * first refusal reached the top. `compileToSql` already catches everything the
 * compiler throws; the class exists only so the caller can be told the
 * fragment was too LONG rather than merely unsupported, which keeps the reason
 * the route logs the same one the 4000-char gate used to produce.
 */
class FragmentTooLarge extends Error {}

/**
 * `EXP`'s range, at both ends, because `exp(double precision)` RAISES outside
 * it rather than saturating — `value out of range: overflow` above the first
 * and `value out of range: underflow` below the second.
 *
 * `Math.exp` turns over at the same two doubles (measured against the server's
 * libm on 2026-08-16: both give 1.7976931348622732e+308 at the maximum and
 * 5e-324 at the minimum, and the next double out is Infinity in-process and an
 * ERROR in the database). So the guard is not a tolerance — it reproduces the
 * evaluator exactly: NULL where it answers Infinity (a non-finite number is
 * `#NUM!`, which reconciles to NULL), and 0 where it answers 0.
 */
const SQL_EXP_MAX = 709.782712893384;
const SQL_EXP_MIN = -745.1332191019411;

/**
 * The units `DATEADD` may name, and the SQL keyword each becomes.
 *
 * An allow-list rather than a pass-through because the unit is the one piece of
 * a formula that lands in the SQL as SYNTAX rather than as a value (see
 * `_tryDateAdd`). The VALUES here are what reach the query; a unit that is not
 * a key is not compiled at all.
 */
const INTERVAL_UNITS = new Map([
  ['ms', 'millisecond'], ['millisecond', 'millisecond'], ['milliseconds', 'millisecond'],
  ['s', 'second'], ['sec', 'second'], ['second', 'second'], ['seconds', 'second'],
  ['m', 'minute'], ['min', 'minute'], ['minute', 'minute'], ['minutes', 'minute'],
  ['h', 'hour'], ['hour', 'hour'], ['hours', 'hour'],
  ['d', 'day'], ['day', 'day'], ['days', 'day'],
  ['w', 'week'], ['week', 'week'], ['weeks', 'week'],
  ['mo', 'month'], ['month', 'month'], ['months', 'month'],
  ['q', 'quarter'], ['quarter', 'quarter'], ['quarters', 'quarter'],
  ['y', 'year'], ['year', 'year'], ['years', 'year'],
]);

/**
 * The VALUE type of a compiled expression.
 *
 * `'blank'` is a compiled NULL literal, which is text-compatible on both sides
 * of a comparison; `'unknown'` is an expression whose branches disagree (a
 * `SWITCH` returning a number in one arm and text in another) or a function
 * whose result type is not fixed.
 *
 * @typedef {'number'|'text'|'boolean'|'date'|'blank'|'unknown'} SqlValueType
 */

/**
 * What `compileToSql` answers.
 *
 * `type` is a real fourth member, not an internal breadcrumb, and it has two
 * consumers that cannot work without it:
 *
 *   * `compileOrderBy` (src/api/formula-query.js) decides from it whether a
 *     sort key is folded through `NULLIF(…, '')` and given a `COLLATE` — a
 *     collation on a numeric key is an error, and a numeric key folded as text
 *     sorts 100 before 9.
 *   * `_equality`/`_ordering` in the compiler itself decide from it whether to
 *     case-fold, because `looseEquals` compares text case-insensitively and
 *     `LOWER()` of a numeric is a type error rather than a slower comparison.
 *
 * It is therefore declared here rather than removed. The alternative the
 * typecheck error left open — deleting the field — would mean a sort on a text
 * column silently ordering by byte value again, which is the disagreement this
 * whole file was measured against.
 *
 * @typedef {Object} CompiledSql
 * @property {string} sql the WHERE/value fragment, with `$1..$N` placeholders
 * @property {any[]} params the ordered values, never interpolated into `sql`
 * @property {'full'|'partial'|'none'} pushdown
 * @property {SqlValueType} type
 * @property {boolean} oversize true when the compile was abandoned because a
 *   fragment passed `SQL_FRAGMENT_MAX`; always present, never absent, for the
 *   same reason `type` is (see the catch blocks in `compileToSql`)
 */

/**
 * Compile a formula expression to parameterized SQL.
 *
 * @param {string} source formula text
 * @param {Object<string, {type: string, column: string}>} schema
 *   Map of field display names to {type, column} where `column` is the
 *   SQL column name.
 * @param {object} [opts]
 * @param {boolean} [opts.doubleQuoteColumns=true] wrap column refs in double quotes
 * @returns {CompiledSql}
 */
export function compileToSql(source, schema = {}, opts = {}) {
  const doubleQuote = opts.doubleQuoteColumns !== false;
  const params = [];
  const compiler = new SqlCompiler(schema, params, doubleQuote);

  let ast;
  try {
    ast = parse(source);
  } catch {
    // `type` on the failure paths too, so a caller reading it never has to test
    // for its absence. A field that is present on one return and missing on
    // another is the shape that makes `compiled.type === 'text'` quietly false.
    // `oversize` is carried on every return for the same reason.
    return { sql: '', params: [], pushdown: 'none', type: 'unknown', oversize: false };
  }

  try {
    const result = compiler.compile(ast);
    return {
      sql: result.sql,
      params: [...params],
      pushdown: result.pushdown,
      type: result.type || 'unknown',
      oversize: false,
    };
  } catch (err) {
    // The size bound is the one failure worth telling apart from the rest: it
    // is the compiler declining to build text nobody could execute, not an
    // expression it does not know how to translate. See `SQL_FRAGMENT_MAX`.
    return { sql: '', params: [], pushdown: 'none', type: 'unknown', oversize: err instanceof FragmentTooLarge };
  }
}

/**
 * A compiled fragment as a WHERE clause — `truthy()` (src/views/query.js), in
 * SQL.
 *
 * `filterRecords` applies the engine's truthiness to WHATEVER a filter
 * expression returns, so `IF({Qty}, "big", "small")` is a legal saved-view
 * filter and selects every row (both branches are non-empty strings). SQL
 * demands a boolean in WHERE and answers `argument of WHERE must be type
 * boolean` — a raise, not a different page, so the route returns 500 and the
 * conformance comparison sees an empty result it could mistake for "no rows
 * matched".
 *
 * Returns null when the fragment's type cannot be decided, which the caller
 * must treat as "not pushed down" rather than guessing.
 *
 * @param {{sql: string, type?: string}} compiled a `compileToSql` result
 * @returns {string|null}
 */
export function booleanFragment(compiled) {
  if (!compiled || !compiled.sql) return null;
  const sql = compiled.sql;
  // NOT `boolArg`, and the difference is measured rather than stylistic. The
  // product has TWO truthiness rules and this position uses the OTHER one:
  //
  //   toBool  (values.js, inside the expression)  "0" and "false" are FALSE
  //   truthy  (views/query.js, the filter itself) any non-empty string is TRUE
  //
  // A filter of a bare text field over a row holding the string "0" selects
  // that row in the browser and, compiled through `boolArg`, did not in the
  // database. Errors are false under `truthy` — which is what every guarded
  // emission already coalesces to — so an error-capable expression needs no
  // refusal here, unlike in `boolArg`.
  switch (compiled.type) {
    case 'boolean': return `(${sql} IS TRUE)`;
    case 'number': return `(((${sql}) <> 0) IS TRUE)`;
    case 'text': return `(((${sql}) <> '') IS TRUE)`;
    case 'date': return `(${sql} IS NOT NULL)`;
    case 'blank': return 'false';
    default: return null;
  }
}

const registry = getRegistry();

/**
 * The VALUE type a field's SQL expression has, from the field's declared type.
 *
 * The compiler needs this for exactly one reason and it is not cosmetic:
 * `values.js:looseEquals` compares two texts CASE-INSENSITIVELY, and `=` in SQL
 * does not. Emitting `LOWER(a) = LOWER(b)` unconditionally is not an option
 * either — `LOWER()` of a numeric is a type error — so the operator has to know
 * what it is comparing. Mirrors the sets in `src/api/formula-query.js`, which
 * decide the cast on the other side of the same wire.
 */
const NUMERIC_FIELD_TYPES = new Set([
  'number', 'currency', 'percent', 'rating', 'duration', 'autonumber', 'count', 'rollup',
]);
const BOOLEAN_FIELD_TYPES = new Set(['checkbox', 'boolean', 'toggle']);
// The registry spells the audit types with hyphens (created-time,
// last-modified-time); the underscored spellings are kept for older callers.
const TEMPORAL_FIELD_TYPES = new Set([
  'date', 'datetime', 'created-time', 'last-modified-time', 'created_time', 'modified_time', 'timestamp',
]);

/** How many arguments each of these SQL emissions actually uses (see compileFunction). */
const SQL_MAX_ARGS_USED = {
  ROUNDUP: 1, ROUNDDOWN: 1, TRUNC: 1, CEILING: 1, FLOOR: 1,
  LOG: 1, LOG10: 1, TEXT: 1, TOTEXT: 1, TOSTRING: 1, STRING: 1, TODATE: 1,
};

function valueTypeOfField(fieldType) {
  if (NUMERIC_FIELD_TYPES.has(fieldType)) return 'number';
  if (BOOLEAN_FIELD_TYPES.has(fieldType)) return 'boolean';
  if (TEMPORAL_FIELD_TYPES.has(fieldType)) return 'date';
  return 'text';
}

/**
 * The units `DATEDIF` may name. Excel's codes, and only the ones whose SQL
 * equivalent is exact: `'d'` is a subtraction, while `'m'` and `'y'` mean
 * COMPLETE months and years, which is not `EXTRACT(MONTH FROM …)` and is not
 * worth guessing at. An unsupported unit is not pushed down, and the in-process
 * evaluator — which has the real implementation — answers it.
 */
const DATEDIF_UNITS = new Map([['d', 'day']]);

/**
 * The functions and operators that can produce a typed ERROR VALUE (LC10.4)
 * rather than a value or a blank — every one of which this compiler already
 * emits as a NULL, because SQL has no error values.
 *
 * `/` and `%` answer `#DIV/0!`; `SQRT`, `LN`, `LOG`, `LOG10`, `ASIN` and `ACOS`
 * answer `#NUM!` outside their domain; `^`/`POWER` answers `#VALUE!` for a
 * negative base with a fractional exponent.
 */
const ERROR_VALUE_FUNCTIONS = new Set(['SQRT', 'LN', 'LOG', 'LOG10', 'ASIN', 'ACOS', 'POWER', 'POW', 'MOD']);
const ERROR_VALUE_OPERATORS = new Set(['/', '%', '^']);

/**
 * Can this subtree evaluate to an error value?
 *
 * Answered from the AST rather than from the emitted SQL, because the emitted
 * SQL is where the distinction has already been lost: a guarded `CASE WHEN … <
 * 0 THEN NULL` and an absent cell are the same NULL by then.
 *
 * Conservative in the safe direction — a false positive costs a pushdown, a
 * false negative costs a wrong page.
 *
 * @param {any} node an AST node
 * @returns {boolean}
 */
function astMayError(node) {
  if (!node || typeof node !== 'object') return false;
  if (node.type === 'binary' && ERROR_VALUE_OPERATORS.has(node.op)) return true;
  if (node.type === 'call' && ERROR_VALUE_FUNCTIONS.has(String(node.name || '').toUpperCase())) return true;
  for (const key of Object.keys(node)) {
    if (key === 'node') continue;
    const child = node[key];
    if (Array.isArray(child)) { if (child.some(astMayError)) return true; } else if (astMayError(child)) return true;
  }
  return false;
}

class SqlCompiler {
  constructor(schema, params, doubleQuote) {
    this.schema = schema;
    this.params = params;
    this.doubleQuote = doubleQuote;
    this._paramIndex = 0;
  }

  /** Add a parameter value and return its placeholder. */
  param(value) {
    this._paramIndex++;
    this.params.push(value);
    return `$${this._paramIndex}`;
  }

  /** Quote a column name if configured. */
  col(name) {
    if (this.doubleQuote) return `"${name.replace(/"/g, '""')}"`;
    return name;
  }

  /**
   * Compile an AST node, returning {sql, pushdown}.
   * pushdown is 'full' if every sub-node is fully pushdown-able.
   *
   * The node itself travels on the result, because one decision downstream
   * needs the SOURCE and not the SQL: whether this subtree can produce an ERROR
   * VALUE. See `astMayError` and `SqlCompiler.boolArg`.
   */
  compile(node) {
    const out = this._compileNode(node);
    if (out && typeof out === 'object' && out.node === undefined) out.node = node;
    // The size bound, checked HERE because `compile()` is the single funnel
    // every node's emission passes through on its way to its parent — so the
    // fragment is measured at the moment it grows, one multiplication after it
    // was still inside the budget, rather than after the whole rope is built.
    // See `SQL_FRAGMENT_MAX` for the measurement that put it here.
    if (out && typeof out.sql === 'string' && out.sql.length > SQL_FRAGMENT_MAX) {
      throw new FragmentTooLarge();
    }
    return out;
  }

  _compileNode(node) {
    if (!node || typeof node !== 'object') {
      return { sql: this.param(null), pushdown: 'full' };
    }

    switch (node.type) {
      case 'number':
        // `::double precision`, and it is the number TYPE of the language
        // rather than a formatting preference — see `fieldExpression` in
        // src/api/formula-query.js for the same cast on the field side and for
        // why the two must agree. A bare `$1` arrives as `numeric` from the
        // migration's parameter rewrite, and `0.1::numeric + 0.2::numeric` is
        // exactly 0.3 while the evaluator's is 0.30000000000000004: a filter
        // `0.1 + 0.2 = 0.3` then selects EVERY row in the database and NO row
        // in the browser, with no field involved at all.
        return { sql: `(${this.param(node.value)})::double precision`, pushdown: 'full', type: 'number' };
      case 'string':
        return { sql: this.param(node.value), pushdown: 'full', type: 'text' };
      case 'bool':
        return { sql: this.param(node.value), pushdown: 'full', type: 'boolean' };
      case 'null':
        return { sql: 'NULL', pushdown: 'full', type: 'blank' };
      case 'field':
        return this.compileField(node);
      case 'unary':
        return this.compileUnary(node);
      case 'binary':
        return this.compileBinary(node);
      case 'ternary':
        return this.compileTernary(node);
      case 'call':
        return this.compileCall(node);
      case 'array':
        return { sql: '', params: [], pushdown: 'none' }; // arrays not pushdown-able
      case 'name':
        return this.compileName(node);
      default:
        return { sql: '', pushdown: 'none' };
    }
  }

  compileField(node) {
    const name = node.name;
    // Look up the schema for the SQL column name.
    const def = this._findField(name);
    if (!def) {
      // Unknown field — cannot push down.
      return { sql: '', pushdown: 'none' };
    }
    return { sql: this.col(def.column), pushdown: 'full', type: valueTypeOfField(def.type) };
  }

  compileName(node) {
    // A bare name could be a zero-arg function (PI, NOW, TODAY).
    const entry = registry.resolve(node.name);
    if (entry && (entry.minArgs ?? 0) === 0) {
      return this.compileFunction(entry, []);
    }
    // Try as a field reference.
    const def = this._findField(node.name);
    if (def) return { sql: this.col(def.column), pushdown: 'full', type: valueTypeOfField(def.type) };
    // Unknown bare name — cannot push down.
    return { sql: '', pushdown: 'none' };
  }

  /**
   * A text operand as the engine sees it.
   *
   * `isBlank()` (`values.js:20`) calls null, undefined AND the empty string
   * blank — one predicate over three spellings. On the SQL side those are two
   * different values, so every text operand entering a comparison is folded to
   * NULL first. Without it `ISBLANK({Title})` is true in the browser and false
   * in the database for a row whose Title is `""`, which is not a rounding
   * difference: it is a different row set.
   */
  static blankText(sql) {
    return `NULLIF(${sql}, '')`;
  }

  /**
   * A text argument to a text FUNCTION, where the engine's answer for a blank
   * is a value rather than a blank: `LEN(blank)` is 0, `UPPER(blank)` is `''`,
   * `TRIM(blank)` is `''`. SQL would answer NULL to all three.
   */
  static textArg(sql) {
    return `COALESCE(${sql}, '')`;
  }

  /**
   * An argument in BOOLEAN POSITION, as `toBool` (`values.js:180`) defines it.
   *
   * Every connective in this file used to emit `COALESCE(x, false)`, which is
   * correct only when `x` is already a boolean. The language does not require
   * that: `IF({Qty}, …)`, `NOT({Qty})`, `AND({Qty}, {Price})` and
   * `IF({Title}, …)` are all legal, the evaluator answers them through
   * `toBool`, and the SQL those compiled to did not return a different answer —
   * it RAISED, `COALESCE types numeric and boolean cannot be matched`, before
   * a single row was read. `predicateShapeReason` never saw it because the
   * fragment is well-formed TEXT; only a database can refuse it, and the route
   * has no way to turn that into anything but a 500.
   *
   * So each declared type gets the rule `toBool` gives it:
   *   * number  — `v !== 0`
   *   * text    — trimmed, lowercased, false for `''`/`false`/`0`/`no`, true
   *               for every other non-empty string (NOT merely `<> ''`)
   *   * date    — a Date is always truthy; a blank is not
   *   * blank   — false
   *   * unknown — REFUSED. A guess here is a silently different page.
   *
   * @param {{sql: string, type?: string, node?: any}} compiled
   * @returns {string|null} null when the type cannot be decided
   */
  static boolArg(compiled) {
    const sql = compiled.sql;
    // An ERROR VALUE in boolean position has no SQL spelling, and the engine's
    // answer for one is neither true nor false nor blank. `toBool` RETURNS the
    // error, and each consumer then does something different with the object it
    // gets back: `IF` finds it truthy and takes the THEN branch, `!` finds it
    // truthy and answers FALSE, `OR` short-circuits to TRUE, `AND` to false.
    // Compiled, all four become one NULL coalesced to false — so on a row where
    // the division failed, `NOT({Qty} / {Price} > 1)` excluded the row in the
    // browser and INCLUDED it in the database. Measured on rows 3 and 13.
    //
    // There is no emission that fixes this, because SQL's NULL cannot carry the
    // distinction between "blank" and "errored". So the expression is refused,
    // which the routes turn into `unsupported_expression` — a page the product
    // declines to push down beats a page with the wrong rows in it.
    if (astMayError(compiled.node)) return null;
    switch (compiled.type) {
      // `x IS TRUE` rather than `COALESCE(x, false)` — the same three answers
      // (true stays true, false stays false, NULL becomes false) in the
      // operator SQL has for exactly this, and one fewer nesting level in a
      // fragment the database's shape gate has to read.
      case 'boolean': return `(${sql} IS TRUE)`;
      case 'number': return `(((${sql}) <> 0) IS TRUE)`;
      case 'text': return `((LOWER(BTRIM(${sql})) NOT IN ('', 'false', '0', 'no')) IS TRUE)`;
      case 'date': return `(${sql} IS NOT NULL)`;
      case 'blank': return 'false';
      default: return null;
    }
  }

  compileUnary(node) {
    const operand = this.compile(node.operand);
    if (operand.pushdown === 'none') return { sql: '', pushdown: 'none' };

    switch (node.op) {
      case '-':
        return { sql: `(-${operand.sql})`, pushdown: operand.pushdown, type: 'number' };
      case '+':
        return { sql: `(+${operand.sql})`, pushdown: operand.pushdown, type: 'number' };
      case '!': {
        // `NOT NULL` is NULL; `toBool(blank)` is false, so the engine's answer
        // for `!{Missing}` is TRUE. Three-valued logic is where a filter that
        // agrees on every present value still returns a different page.
        const bool = SqlCompiler.boolArg(operand);
        if (bool === null) return { sql: '', pushdown: 'none' };
        return { sql: `(NOT ${bool})`, pushdown: operand.pushdown, type: 'boolean' };
      }
      default:
        return { sql: '', pushdown: 'none' };
    }
  }

  compileBinary(node) {
    const op = node.op;

    // Logical operators with short-circuit semantics.
    if (op === '||' || op === '&&') {
      const left = this.compile(node.left);
      const right = this.compile(node.right);
      if (left.pushdown === 'none' && right.pushdown === 'none') return { sql: '', pushdown: 'none' };
      const sqlOp = op === '||' ? 'OR' : 'AND';
      // `toBool(blank)` is false and there is no third answer, so a NULL operand
      // is folded before the connective rather than after it. `NULL OR false`
      // is NULL — which a WHERE clause discards, agreeing by luck — but
      // `NOT(NULL OR false)` is also NULL, and there the luck runs out.
      const operands = [left, right].filter((r) => r.pushdown !== 'none').map((r) => SqlCompiler.boolArg(r));
      if (operands.some((o) => o === null)) return { sql: '', pushdown: 'none' };
      const combined = operands.map((o) => `(${o})`).join(` ${sqlOp} `);
      return {
        sql: combined,
        pushdown: left.pushdown === 'full' && right.pushdown === 'full' ? 'full' : 'partial',
        type: 'boolean',
      };
    }

    const left = this.compile(node.left);
    const right = this.compile(node.right);
    if (left.pushdown === 'none' || right.pushdown === 'none') {
      return { sql: '', pushdown: 'none' };
    }

    switch (op) {
      case '+':
        return { sql: `(${left.sql} + ${right.sql})`, pushdown: 'full', type: 'number' };
      case '-':
        return { sql: `(${left.sql} - ${right.sql})`, pushdown: 'full', type: 'number' };
      case '*':
        return { sql: `(${left.sql} * ${right.sql})`, pushdown: 'full', type: 'number' };
      case '/':
        // Guard against division by zero with NULLIF. The engine answers
        // `#DIV/0!` and SQL has no error VALUE, so NULL is as close as the two
        // models come — and every surface treats both as "not a match".
        return { sql: `(${left.sql} / NULLIF(${right.sql}, 0))`, pushdown: 'full', type: 'number' };
      case '%':
        // Without the NULLIF, `{Qty} % {Qty}` on a row where Qty is 0 does not
        // return a wrong answer — it RAISES, and takes the whole page with it.
        //
        // The numeric round trip is not a widening: `mod()` has no `double
        // precision` overload at all, so with every other operand now a double
        // this is the one place that has to step out of the language's number
        // type and back into it. A double converts to `numeric` exactly, so the
        // remainder is the remainder of the same two values.
        return {
          sql: `MOD((${left.sql})::numeric, NULLIF((${right.sql})::numeric, 0))::double precision`,
          pushdown: 'full',
          type: 'number',
        };
      case '^':
        return { sql: this._power(left.sql, right.sql), pushdown: 'full', type: 'number' };
      case '&':
        // String concatenation. `concat()` in the evaluator runs both sides
        // through `toText`, where a blank becomes `''` rather than propagating.
        return {
          sql: `CONCAT(${SqlCompiler.textArg(left.sql)}, ${SqlCompiler.textArg(right.sql)})`,
          pushdown: 'full',
          type: 'text',
        };
      case '=':
      case '==':
        return { sql: this._equality(left, right, false), pushdown: 'full', type: 'boolean' };
      case '!=':
      case '<>':
        return { sql: this._equality(left, right, true), pushdown: 'full', type: 'boolean' };
      case '<':
      case '<=':
      case '>':
      case '>=':
        return { sql: this._ordering(op, left, right), pushdown: 'full', type: 'boolean' };
      default:
        return { sql: '', pushdown: 'none' };
    }
  }

  /**
   * `=` and `!=`, as `looseEquals` (`values.js:206`) defines them.
   *
   * Two rules, both absent from SQL's `=`:
   *   * blank equals blank, and blank equals nothing else — never "unknown".
   *     `IS NOT DISTINCT FROM` is exactly that operator.
   *   * text compares CASE-INSENSITIVELY ("per spreadsheet convention"). So
   *     `{Title} = "acme"` matches a row whose Title is `Acme`, and a database
   *     that compares them byte for byte returns a different page from the same
   *     saved view.
   *
   * `LOWER` is applied only when both sides are text, because `LOWER` of a
   * numeric is a type error rather than a slower comparison. A blank literal is
   * text-compatible: `{Qty} = ""` on a numeric column stays a plain comparison.
   */
  _equality(left, right, negated) {
    const bothText = this._isText(left) && this._isText(right);
    const l = bothText ? `LOWER(${SqlCompiler.blankText(left.sql)})` : left.sql;
    const r = bothText ? `LOWER(${SqlCompiler.blankText(right.sql)})` : right.sql;
    return `(${l} IS ${negated ? '' : 'NOT '}DISTINCT FROM ${r})`;
  }

  /**
   * `< <= > >=`, as `compareValues` (`values.js:225`) defines them.
   *
   * The rule that SQL does not have: **a blank is less than everything**, and
   * two blanks are equal. So `{Missing} < 1` is TRUE in the engine, while
   * `NULL < 1` is unknown — and `NOT` of that, or an `AND` around it, turns the
   * disagreement into a missing row.
   *
   * Rather than a four-branch CASE repeating both operands, this compares row
   * values: `(a IS NOT NULL, a) < (b IS NOT NULL, b)`. `false < true`, so a
   * NULL side loses on the first element exactly as a blank does in
   * `compareValues`; when both are present the comparison falls through to the
   * values themselves. Two NULLs make the row comparison unknown, which is the
   * `compareValues() === 0` case, so it is coalesced to what the operator
   * answers for equal operands.
   */
  _ordering(op, left, right) {
    const bothText = this._isText(left) && this._isText(right);
    const l = bothText ? SqlCompiler.blankText(left.sql) : left.sql;
    const r = bothText ? SqlCompiler.blankText(right.sql) : right.sql;
    const equalAnswer = op === '<=' || op === '>=' ? 'true' : 'false';
    return `COALESCE((ROW(${l} IS NOT NULL, ${l}) ${op} ROW(${r} IS NOT NULL, ${r})), ${equalAnswer})`;
  }

  _isText(compiled) {
    return compiled.type === 'text' || compiled.type === 'blank';
  }

  /**
   * `POWER`, which raises on a negative base with a fractional exponent —
   * `a negative number raised to a non-integer power yields a complex result`.
   * The engine answers `#VALUE!` for the same input, so the guard turns a
   * query-killing exception into the NULL that an error reconciles to.
   */
  _power(base, exponent) {
    return `CASE WHEN ${base} < 0 AND ${exponent} <> TRUNC(${exponent}) THEN NULL`
      + ` ELSE POWER(${base}, ${exponent}) END`;
  }

  compileTernary(node) {
    const cond = this.compile(node.cond);
    const thenBranch = this.compile(node.then);
    const altBranch = this.compile(node.alt);
    if (cond.pushdown === 'none' || thenBranch.pushdown === 'none' || altBranch.pushdown === 'none') {
      return { sql: '', pushdown: 'none' };
    }
    const test = SqlCompiler.boolArg(cond);
    if (test === null) return { sql: '', pushdown: 'none' };
    return {
      sql: `CASE WHEN ${test} THEN ${thenBranch.sql} ELSE ${altBranch.sql} END`,
      pushdown: 'full',
      type: thenBranch.type === altBranch.type ? thenBranch.type : 'unknown',
    };
  }

  compileCall(node) {
    // DATEADD is handled BEFORE the arguments are compiled, because its unit is
    // a SQL keyword rather than a value and the two cannot be told apart once
    // every argument has become a `$N`. See `_tryDateAdd`.
    const dateAdd = this._tryDateAdd(node);
    if (dateAdd) return dateAdd;
    const dateDif = this._tryDateDif(node);
    if (dateDif) return dateDif;

    // Compile args first — if any arg can't be pushed down, the whole call can't.
    const compiledArgs = node.args.map((a) => this.compile(a));
    const anyNone = compiledArgs.some((a) => a.pushdown === 'none');
    if (anyNone) return { sql: '', pushdown: 'none' };

    // Try hardcoded SQL mapping first (covers functions not in registry).
    const hardcoded = this._tryHardcodedFunction(node.name, compiledArgs);
    if (hardcoded) return hardcoded;

    // Fall back to registry.
    const entry = registry.resolve(node.name);
    if (!entry) return { sql: '', pushdown: 'none' };

    // Volatile or explicitly non-pushdown-able functions.
    if (entry.volatile || entry.pushdown === false) {
      return { sql: '', pushdown: 'none' };
    }

    return this.compileFunction(entry, compiledArgs);
  }

  /**
   * `DATEADD(date, n, unit)` — the one function whose argument is SYNTAX.
   *
   * Postgres has no interval whose unit is a bind parameter: `INTERVAL '1 ' || $2`
   * is not an interval, and `INTERVAL '1 $2'` is the four characters `1 $2`
   * offered to the interval parser, which rejects them. So the unit cannot be a
   * value, and this cannot be compiled from `compiledArgs` — by then it already
   * is one.
   *
   * The previous form emitted `INTERVAL '1 $2'` and was wrong in two ways at
   * once: the query could not run, AND the `$2` sat inside a quoted literal,
   * which is precisely the shape `private.compiled_predicate_reason` refuses as
   * `dollar_in_literal`. Nothing consumed this compiler's SQL until
   * `src/api/formula-query.js`, so neither half had ever been executed.
   *
   * The unit is therefore read from the AST and matched against the list below.
   * A unit that is not a literal — `DATEADD({Due}, 1, {Unit})` — is not pushed
   * down at all rather than guessed at, and the in-process evaluator answers it.
   * Nothing a caller wrote is ever inlined: only a keyword from this map is, and
   * the map's VALUES are what reach the SQL.
   *
   * Returns `{sql, pushdown}` for a DATEADD call, or null when this is not one.
   */
  _tryDateAdd(node) {
    if (String(node.name || '').toUpperCase().replace(/_/g, '') !== 'DATEADD') return null;
    const args = Array.isArray(node.args) ? node.args : [];
    if (args.length < 3) return { sql: '', pushdown: 'none' };

    const unitNode = args[2];
    const unit = unitNode && unitNode.type === 'string'
      ? INTERVAL_UNITS.get(String(unitNode.value).trim().toLowerCase())
      : null;
    if (!unit) return { sql: '', pushdown: 'none' };

    // Only now, and only two of them: compiling the unit would push a parameter
    // that the SQL never references, and `compileToSqlQuery` hands `params`
    // straight to `pg`, which rejects a bind list longer than the statement uses.
    const target = this.compile(args[0]);
    if (target.pushdown !== 'full') return { sql: '', pushdown: 'none' };
    const amount = this.compile(args[1]);
    if (amount.pushdown !== 'full') return { sql: '', pushdown: 'none' };

    return { sql: `(${target.sql} + (${amount.sql} * INTERVAL '1 ${unit}'))`, pushdown: 'full' };
  }

  /**
   * `DATEDIF(start, end, unit)` — the second function whose argument is syntax,
   * and the second one that had been compiled as though it were not.
   *
   * The evaluator's DATEDIF requires the unit and answers `#VALUE!` without it;
   * this compiled the TWO-argument form as `EXTRACT(DAY FROM (b - a))`, so the
   * expression the engine refuses was the only one the database would run, and
   * the three-argument form users actually write was not pushed down at all.
   *
   * Only `'d'` is emitted. `'m'` and `'y'` are complete months and years —
   * `DATEDIF('2026-01-31', '2026-03-01', 'm')` is 1, not 2 — and an EXTRACT
   * does not compute that. Guessing would produce a filter that is wrong on
   * month boundaries only, which is the kind of defect that survives review.
   *
   * Returns `{sql, pushdown}` for a DATEDIF call, or null when this is not one.
   */
  _tryDateDif(node) {
    if (String(node.name || '').toUpperCase().replace(/_/g, '') !== 'DATEDIF') return null;
    const args = Array.isArray(node.args) ? node.args : [];
    if (args.length < 3) return { sql: '', pushdown: 'none' };

    const unitNode = args[2];
    const unit = unitNode && unitNode.type === 'string'
      ? DATEDIF_UNITS.get(String(unitNode.value).trim().toLowerCase())
      : null;
    if (!unit) return { sql: '', pushdown: 'none' };

    const from = this.compile(args[0]);
    if (from.pushdown !== 'full') return { sql: '', pushdown: 'none' };
    const to = this.compile(args[1]);
    if (to.pushdown !== 'full') return { sql: '', pushdown: 'none' };

    // Whole days between two instants, truncated toward zero — the difference
    // of two dates, not the DAY FIELD of an interval, which stops at 30.
    //
    // The CASE is Excel's rule and the engine's: an end BEFORE the start is
    // `#NUM!`, not a negative number of days. Without it a filter on
    // `DATEDIF({Start}, {End}, "d") < 1` selects every backwards row in the
    // database and none of them in the browser.
    const days = `TRUNC(EXTRACT(EPOCH FROM ((${to.sql}) - (${from.sql}))) / 86400)`;
    return {
      sql: `CASE WHEN (${to.sql}) < (${from.sql}) THEN NULL ELSE ${days} END`,
      pushdown: 'full',
      type: 'number',
    };
  }

  /**
   * Try to compile a function call using hardcoded SQL mappings.
   * Returns {sql, pushdown} or null if no mapping exists.
   */
  _tryHardcodedFunction(rawName, compiledArgs) {
    const name = String(rawName).toUpperCase().replace(/_/g, '');
    const args = compiledArgs.map((a) => a.sql);

    // --- Functions available as SQL even if not in the formula registry ---
    //
    // `LIKE` was the obvious emission and it is wrong twice over: the needle is
    // a VALUE, so a `%` or `_` inside it — `CONTAINS({Notes}, "100%")` — is
    // read as a wildcard, and a blank needle becomes NULL rather than the empty
    // string the engine substitutes. `POSITION` has neither problem.
    if (name === 'CONTAINS') {
      if (args.length < 2) return null;
      return {
        sql: `(POSITION(${SqlCompiler.textArg(args[1])} IN ${SqlCompiler.textArg(args[0])}) > 0)`,
        pushdown: 'full',
        type: 'boolean',
      };
    }
    // STARTS_WITH and ENDS_WITH are case-INSENSITIVE in the evaluator while
    // CONTAINS is not. That is the engine's inconsistency, not this compiler's,
    // and the compiler's job is to reproduce it rather than to improve on it.
    if (name === 'STARTSWITH') {
      if (args.length < 2) return null;
      const hay = `LOWER(${SqlCompiler.textArg(args[0])})`;
      const needle = `LOWER(${SqlCompiler.textArg(args[1])})`;
      return { sql: `(LEFT(${hay}, LENGTH(${needle})) = ${needle})`, pushdown: 'full', type: 'boolean' };
    }
    if (name === 'ENDSWITH') {
      if (args.length < 2) return null;
      const hay = `LOWER(${SqlCompiler.textArg(args[0])})`;
      const needle = `LOWER(${SqlCompiler.textArg(args[1])})`;
      return { sql: `(RIGHT(${hay}, LENGTH(${needle})) = ${needle})`, pushdown: 'full', type: 'boolean' };
    }
    if (name === 'COALESCE' || name === 'NVL') {
      return { sql: `COALESCE(${args.join(', ')})`, pushdown: 'full', type: 'unknown' };
    }
    if (name === 'NULLIF') {
      if (args.length < 2) return null;
      return { sql: `NULLIF(${args[0]}, ${args[1]})`, pushdown: 'full', type: compiledArgs[0].type };
    }
    if (name === 'CEIL') {
      return { sql: `CEIL(${args[0]})`, pushdown: 'full', type: 'number' };
    }
    return null;
  }

  /**
   * Compile a known, pushdown-able function call with already-compiled args.
   *
   * Every emission below was measured against the in-process evaluator over the
   * same records (`scripts/qa-formula-conformance.mjs`), and the guards are
   * there because the measurement failed without them. Three recurring shapes:
   *
   *   * BLANK IS A VALUE, NOT UNKNOWN. `LEN(blank)` is 0, `UPPER(blank)` is
   *     `''`, `TRIM(blank)` is `''`. SQL answers NULL to all of them, so text
   *     arguments are coalesced at the boundary.
   *   * A DOMAIN ERROR IS A VALUE, NOT AN EXCEPTION. `SQRT(-1)` is `#NUM!` in
   *     the engine and an aborted statement in Postgres — which does not return
   *     a different row, it returns no page at all. Each such function is
   *     guarded into NULL, the value an error reconciles to.
   *   * THE ENGINE'S ROUNDING IS NOT THE DATABASE'S. `ROUND` is half-UP
   *     (`Math.round`), `ROUNDUP` is away from zero, `INT` is a floor, and
   *     `MOD` takes the sign of the DIVISOR. Postgres agrees with none of the
   *     four by default.
   */
  compileFunction(entry, compiledArgs) {
    const name = entry.name.toUpperCase();
    // Optional second arguments the evaluator honours and these emissions do
    // not: ROUNDUP/ROUNDDOWN/TRUNC (digits), CEILING/FLOOR (significance), LOG
    // (base), TEXT/TODATE (format). Emitting anyway filtered different rows than
    // the grid AND left an unreferenced bind parameter, which pg rejects. Refuse
    // pushdown; the in-process evaluator answers.
    if (compiledArgs.length > (SQL_MAX_ARGS_USED[name] ?? Infinity)) return { sql: '', pushdown: 'none' };
    const args = compiledArgs.map((a) => a.sql);
    const text = (i) => SqlCompiler.textArg(args[i]);
    // Clamped, not merely floored: the count is a cell value and `::int` is
    // where an oversized one raises. See `SQL_TEXT_INDEX_MAX`.
    const clamp = (expr) => `LEAST(${expr}, ${SQL_TEXT_INDEX_MAX})`;
    const count = (i) => clamp(`GREATEST(COALESCE(${args[i]}, 0), 0)`);

    // --- Logical ---
    // Every boolean-position argument goes through `toBool`'s rule, or is
    // refused. See `SqlCompiler.boolArg`.
    const bool = (i) => SqlCompiler.boolArg(compiledArgs[i]);

    if (name === 'IF') {
      if (args.length < 3) return { sql: '', pushdown: 'none' };
      if (bool(0) === null) return { sql: '', pushdown: 'none' };
      return {
        sql: `CASE WHEN ${bool(0)} THEN ${args[1]} ELSE ${args[2]} END`,
        pushdown: 'full',
        type: compiledArgs[1].type === compiledArgs[2].type ? compiledArgs[1].type : 'unknown',
      };
    }
    if (name === 'IFERROR' || name === 'IFNA') {
      // Both test for an ERROR VALUE, which SQL does not have. `IFNA` was
      // compiled as `COALESCE`, which is a different function: the engine
      // returns the fallback for `#N/A` and passes a BLANK straight through,
      // while COALESCE replaces the blank and never sees an error.
      return { sql: '', pushdown: 'none' };
    }
    if (name === 'IFBLANK') {
      if (args.length < 2) return { sql: '', pushdown: 'none' };
      return { sql: `COALESCE(${args[0]}, ${args[1]})`, pushdown: 'full', type: compiledArgs[1].type };
    }
    if (name === 'AND' || name === 'OR') {
      const bools = compiledArgs.map((a) => SqlCompiler.boolArg(a));
      if (bools.some((b) => b === null)) return { sql: '', pushdown: 'none' };
      return { sql: `(${bools.join(name === 'AND' ? ' AND ' : ' OR ')})`, pushdown: 'full', type: 'boolean' };
    }
    if (name === 'NOT') {
      if (bool(0) === null) return { sql: '', pushdown: 'none' };
      return { sql: `(NOT ${bool(0)})`, pushdown: 'full', type: 'boolean' };
    }
    if (name === 'IFS') {
      if (args.length < 2) return { sql: '', pushdown: 'none' };
      for (let i = 0; i + 1 < args.length; i += 2) if (bool(i) === null) return { sql: '', pushdown: 'none' };
      let sql = 'CASE ';
      for (let i = 0; i + 1 < args.length; i += 2) {
        sql += `WHEN ${bool(i)} THEN ${args[i + 1]} `;
      }
      // An odd argument count means the last one is the ELSE.
      if (args.length % 2 === 1) sql += `ELSE ${args[args.length - 1]} `;
      sql += 'END';
      return { sql, pushdown: 'full', type: 'unknown' };
    }
    if (name === 'SWITCH' || name === 'CASE') {
      // SWITCH is not IFS with a different name, and compiling it as one was a
      // silent wrong answer rather than an error: its FIRST argument is the
      // SUBJECT (`logical.js:76`), matched against each case with `looseEquals`
      // — so `SWITCH({Status}, "open", 1, "shut", 2)` compiled to `CASE WHEN
      // {Status} THEN "open" …`, which reads the subject as a condition and
      // returns the case LABELS as values.
      if (args.length < 3) return { sql: '', pushdown: 'none' };
      const subject = compiledArgs[0];
      const rest = compiledArgs.slice(1);
      const pairs = Math.floor(rest.length / 2);
      let sql = 'CASE ';
      for (let i = 0; i < pairs; i++) {
        sql += `WHEN ${this._equality(subject, rest[i * 2], false)} THEN ${rest[i * 2 + 1].sql} `;
      }
      if (rest.length % 2 === 1) sql += `ELSE ${rest[rest.length - 1].sql} `;
      sql += 'END';
      return { sql, pushdown: 'full', type: 'unknown' };
    }

    // --- Comparison / Information ---
    if (name === 'ISBLANK' || name === 'ISEMPTY') {
      const arg = compiledArgs[0] || { type: 'unknown', sql: 'NULL' };
      if (arg.type === 'text' || arg.type === 'blank') {
        return { sql: `(${SqlCompiler.blankText(args[0])} IS NULL)`, pushdown: 'full', type: 'boolean' };
      }
      if (arg.type === 'unknown') {
        return { sql: `(${args[0]} IS NULL OR (${args[0]})::text = '')`, pushdown: 'full', type: 'boolean' };
      }
      return { sql: `(${args[0]} IS NULL)`, pushdown: 'full', type: 'boolean' };
    }
    if (name === 'ISNUMBER') {
      // pg_typeof(...) = 'numeric' or regex check
      return { sql: `(${args[0]} IS NOT NULL AND ${args[0]} ~ '^[+-]?[0-9]+\\.?[0-9]*$')`, pushdown: 'partial' };
    }
    if (name === 'ISTEXT') {
      return { sql: `(${args[0]} IS NOT NULL AND pg_typeof(${args[0]}) IN ('text','varchar','character varying'))`, pushdown: 'partial' };
    }
    if (name === 'ISLOGICAL') {
      return { sql: `(${args[0]} IS NOT NULL AND pg_typeof(${args[0]}) = 'boolean')`, pushdown: 'partial' };
    }
    if (name === 'ISDATE') {
      return { sql: `(${args[0]} IS NOT NULL AND pg_typeof(${args[0]}) IN ('date','timestamp','timestamptz'))`, pushdown: 'partial' };
    }
    if (name === 'ISERROR' || name === 'ISERR' || name === 'ISNA') {
      // Error detection is in-process only — errors don't exist as SQL values.
      return { sql: '', pushdown: 'none' };
    }

    // --- Math ---
    if (name === 'ABS') return { sql: `ABS(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'SIGN') return { sql: `SIGN(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'ROUND') {
      // `Math.round` is half-UP: 2.5 → 3 and -2.5 → -2. Postgres `round()` on
      // numeric is half-AWAY-FROM-ZERO: -2.5 → -3. `floor(x + 0.5)` is the
      // former, and the scale factor carries it to the digits form.
      if (args.length < 2) return { sql: `FLOOR((${args[0]}) + 0.5)`, pushdown: 'full', type: 'number' };
      // `POWER(…)` and not `10::numeric ^ d`, because `^` is not in the
      // character class `private.compiled_predicate_reason` allows and the
      // database would refuse the whole predicate as `unexpected_character`.
      // The value-parity half of the conformance suite never saw it — it runs a
      // bare SELECT — and `tests/formula/sql-compiler.test.js` did, which is
      // why that cross-check exists.
      const scale = `POWER(10::numeric, (${args[1]})::numeric)`;
      return { sql: `(FLOOR((${args[0]}) * ${scale} + 0.5) / ${scale})`, pushdown: 'full', type: 'number' };
    }
    if (name === 'ROUNDUP') {
      // Away from zero, not upward: ROUNDUP(-2.5) is -3, while CEIL(-2.5) is -2.
      return { sql: `(SIGN(${args[0]}) * CEIL(ABS(${args[0]})))`, pushdown: 'full', type: 'number' };
    }
    if (name === 'ROUNDDOWN') {
      // Toward zero, not downward: ROUNDDOWN(-2.5) is -2, FLOOR(-2.5) is -3.
      return { sql: `TRUNC(${args[0]})`, pushdown: 'full', type: 'number' };
    }
    if (name === 'CEILING') return { sql: `CEIL(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'FLOOR') return { sql: `FLOOR(${args[0]})`, pushdown: 'full', type: 'number' };
    // INT is a FLOOR in the evaluator — INT(-2.5) is -3 — so it is not TRUNC.
    if (name === 'INT') return { sql: `FLOOR(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'TRUNC') return { sql: `TRUNC(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'SQRT') {
      return { sql: `CASE WHEN (${args[0]}) < 0 THEN NULL ELSE SQRT(${args[0]}) END`, pushdown: 'full', type: 'number' };
    }
    if (name === 'POWER' || name === 'POW') {
      if (args.length < 2) return { sql: '', pushdown: 'none' };
      return { sql: this._power(args[0], args[1]), pushdown: 'full', type: 'number' };
    }
    if (name === 'MOD') {
      if (args.length < 2) return { sql: '', pushdown: 'none' };
      // The evaluator's MOD takes the sign of the DIVISOR — MOD(-7, 3) is 2 —
      // while Postgres `mod()` takes the sign of the dividend and answers -1.
      // The double modulo is the floored one. The NULLIF keeps a zero divisor
      // from raising, since the engine answers `#DIV/0!` rather than aborting.
      // `::numeric` on both operands for the same reason as the `%` operator
      // above: `mod()` has no `double precision` overload.
      const divisor = `NULLIF((${args[1]})::numeric, 0)`;
      return {
        sql: `MOD(MOD((${args[0]})::numeric, ${divisor}) + ${divisor}, ${divisor})::double precision`,
        pushdown: 'full',
        type: 'number',
      };
    }
    if (name === 'EXP') {
      // Guarded at BOTH ends, and not to the same value. `Math.exp` saturates
      // where `exp(double precision)` raises: Infinity above the maximum,
      // which is `#NUM!` and reconciles to NULL, and 0 below the minimum,
      // which is a NUMBER and has to stay one — answering NULL there would
      // trade a page-killing raise for a wrong value. See `SQL_EXP_MAX`.
      return {
        sql: `CASE WHEN (${args[0]}) > ${SQL_EXP_MAX} THEN NULL`
          + ` WHEN (${args[0]}) < ${SQL_EXP_MIN} THEN 0::double precision`
          + ` ELSE EXP(${args[0]}) END`,
        pushdown: 'full',
        type: 'number',
      };
    }
    if (name === 'LN') {
      return { sql: `CASE WHEN (${args[0]}) <= 0 THEN NULL ELSE LN(${args[0]}) END`, pushdown: 'full', type: 'number' };
    }
    if (name === 'LOG' || name === 'LOG10') {
      // The evaluator's LOG is base 10 — `LOG(100)` is 2 — and this compiled it
      // to `LN`, which answers 4.605. Same name, different function, and the
      // filter that used it selected different rows in the two backends.
      return { sql: `CASE WHEN (${args[0]}) <= 0 THEN NULL ELSE LOG(${args[0]}) END`, pushdown: 'full', type: 'number' };
    }
    if (name === 'SIN') return { sql: `SIN(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'COS') return { sql: `COS(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'TAN') return { sql: `TAN(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'ASIN' || name === 'ACOS') {
      const fn = name === 'ASIN' ? 'ASIN' : 'ACOS';
      return {
        sql: `CASE WHEN (${args[0]}) < -1 OR (${args[0]}) > 1 THEN NULL ELSE ${fn}(${args[0]}) END`,
        pushdown: 'full',
        type: 'number',
      };
    }
    if (name === 'ATAN') return { sql: `ATAN(${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'PI') return { sql: 'PI()', pushdown: 'full', type: 'number' };
    if (name === 'MIN' || name === 'MAX') {
      // Row-wise, not aggregate — and blank-tolerant on both sides. GREATEST
      // and LEAST already ignore NULLs, which matches the evaluator's habit of
      // dropping blanks; where they part company is ALL-blank, which the
      // evaluator answers 0 and SQL answers NULL.
      const fn = name === 'MIN' ? 'LEAST' : 'GREATEST';
      return { sql: `COALESCE(${fn}(${args.join(', ')}), 0)`, pushdown: 'full', type: 'number' };
    }

    // --- Text ---
    if (name === 'UPPER' || name === 'UPPERCASE') return { sql: `UPPER(${text(0)})`, pushdown: 'full', type: 'text' };
    if (name === 'LOWER' || name === 'LOWERCASE') return { sql: `LOWER(${text(0)})`, pushdown: 'full', type: 'text' };
    if (name === 'TRIM') return { sql: `TRIM(${text(0)})`, pushdown: 'full', type: 'text' };
    if (name === 'LTRIM') return { sql: `LTRIM(${text(0)})`, pushdown: 'full', type: 'text' };
    if (name === 'RTRIM') return { sql: `RTRIM(${text(0)})`, pushdown: 'full', type: 'text' };
    if (name === 'LEN' || name === 'LENGTH') return { sql: `LENGTH(${text(0)})`, pushdown: 'full', type: 'number' };
    if (name === 'LEFT') {
      if (args.length < 2) return { sql: '', pushdown: 'none' };
      // `LEFT(x, -1)` is `''` in the evaluator and 'everything but the last
      // character' in Postgres — a negative count is a different function
      // there, not an empty result.
      return { sql: `LEFT(${text(0)}, ${count(1)}::int)`, pushdown: 'full', type: 'text' };
    }
    if (name === 'RIGHT') {
      if (args.length < 2) return { sql: '', pushdown: 'none' };
      return { sql: `RIGHT(${text(0)}, ${count(1)}::int)`, pushdown: 'full', type: 'text' };
    }
    if (name === 'MID' || name === 'SUBSTRING' || name === 'SUBSTR') {
      if (args.length < 2) return { sql: '', pushdown: 'none' };
      const from = `${clamp(`GREATEST(COALESCE(${args[1]}, 1), 1)`)}::int`;
      if (args.length === 2) return { sql: `SUBSTRING(${text(0)} FROM ${from})`, pushdown: 'full', type: 'text' };
      // A negative length raises in Postgres and is `''` in the evaluator.
      return { sql: `SUBSTRING(${text(0)} FROM ${from} FOR ${count(2)}::int)`, pushdown: 'full', type: 'text' };
    }
    if (name === 'REPLACE') {
      // Excel's REPLACE is POSITIONAL — REPLACE(text, start, count, new) —
      // declared `minArgs: 4` in `text.js:265`. It was compiled as SQL's
      // REPLACE, which substitutes a substring, so `REPLACE({Title}, "c", "K")`
      // returned `aKme` from the database and `#VALUE!` from the engine: not a
      // different row, a different function. SUBSTITUTE is the one that
      // substitutes.
      if (args.length !== 4) return { sql: '', pushdown: 'none' };
      const from = `${clamp(`GREATEST(TRUNC(COALESCE(${args[1]}, 1)), 1)`)}::int`;
      return {
        sql: `OVERLAY(${text(0)} PLACING ${text(3)} FROM ${from} FOR ${count(2)}::int)`,
        pushdown: 'full',
        type: 'text',
      };
    }
    if (name === 'SUBSTITUTE') {
      // Only the every-occurrence form. The fourth argument names WHICH
      // occurrence, and SQL's REPLACE has no such notion.
      if (args.length !== 3) return { sql: '', pushdown: 'none' };
      return { sql: `REPLACE(${text(0)}, ${text(1)}, ${text(2)})`, pushdown: 'full', type: 'text' };
    }
    if (name === 'REPT' || name === 'REPEAT') {
      if (args.length < 2) return { sql: '', pushdown: 'none' };
      // The only text function whose ceiling is the EVALUATOR's rather than
      // `int`'s: `text.js` answers `#VALUE!` ('REPEAT result too large') once
      // `length x count` passes MAX_REGEX_INPUT, and an error reconciles to
      // NULL. `SQL_TEXT_INDEX_MAX` cannot stand in for that in either
      // direction, and both failures were measured:
      //
      //   * `REPEAT('abc', 1073741823)` raises `requested length too large` —
      //     a clamp that only keeps the count inside an `int` still kills the
      //     page, just with a different message.
      //   * `REPEAT('', 1073741823)` does not raise at all. It ran past a 6s
      //     statement timeout, because an empty string is copied once per
      //     count — the HUNG request LC10.33 forbids, which is worse than the
      //     typed error it would have replaced.
      //
      // So the guard is on the RESULT LENGTH, computed in `double precision`
      // before any cast so the product itself cannot overflow, and the count
      // inside the surviving branch is clamped to the same ceiling: past it
      // the row is NULL anyway, except for the empty string, which repeats to
      // `''` at any count.
      const t = text(0);
      const n = `GREATEST(COALESCE(${args[1]}, 0), 0)`;
      return {
        sql: `CASE WHEN LENGTH(${t}) * ${n} > ${MAX_REGEX_INPUT} THEN NULL`
          + ` ELSE REPEAT(${t}, LEAST(${n}, ${MAX_REGEX_INPUT})::int) END`,
        pushdown: 'full',
        type: 'text',
      };
    }
    if (name === 'CONCAT' || name === 'CONCATENATE') {
      return { sql: `CONCAT(${args.map((_, i) => text(i)).join(', ')})`, pushdown: 'full', type: 'text' };
    }
    if (name === 'TEXT' || name === 'TOSTRING' || name === 'STRING') {
      return { sql: `(${args[0]})::text`, pushdown: 'full', type: 'text' };
    }
    if (name === 'FIND' || name === 'SEARCH') {
      // Both are 1-based and answer 0 when absent, which POSITION already does.
      // They differ from each other in CASE: FIND is sensitive, SEARCH is not.
      // The three-argument form is not pushed down — `POSITION(a IN
      // SUBSTRING(b FROM c))` counts from the substring, so it answers a
      // different number from the same inputs.
      if (args.length !== 2) return { sql: '', pushdown: 'none' };
      const needle = name === 'SEARCH' ? `LOWER(${text(0)})` : text(0);
      const hay = name === 'SEARCH' ? `LOWER(${text(1)})` : text(1);
      return { sql: `POSITION(${needle} IN ${hay})`, pushdown: 'full', type: 'number' };
    }
    if (name === 'SPLIT' || name === 'JOIN' || name === 'TEXTJOIN' || name === 'ARRAYJOIN') {
      // A list. `compile()` already refuses array LITERALS for the same reason:
      // a text[] is not a formula list, its `::text` is `{a,b}` rather than
      // `a,b`, and the argument ORDER of the evaluator's JOIN is not
      // ARRAY_TO_STRING's. There is no filter these three make possible that
      // the in-process path cannot answer.
      return { sql: '', pushdown: 'none' };
    }

    // --- Date/Time ---
    if (name === 'YEAR') return { sql: `EXTRACT(YEAR FROM ${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'MONTH') return { sql: `EXTRACT(MONTH FROM ${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'DAY') return { sql: `EXTRACT(DAY FROM ${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'HOUR') return { sql: `EXTRACT(HOUR FROM ${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'MINUTE') return { sql: `EXTRACT(MINUTE FROM ${args[0]})`, pushdown: 'full', type: 'number' };
    if (name === 'SECOND') return { sql: `FLOOR(EXTRACT(SECOND FROM ${args[0]}))`, pushdown: 'full', type: 'number' };
    if (name === 'WEEKDAY') {
      // The evaluator numbers Sunday 1 (the spreadsheet convention); `DOW`
      // numbers it 0. One off, every row, silently.
      return { sql: `(EXTRACT(DOW FROM ${args[0]}) + 1)`, pushdown: 'full', type: 'number' };
    }
    if (name === 'WEEKNUM') {
      // The spreadsheet week number, not the ISO one: week 1 is the week
      // containing 1 January and weeks start on Sunday. `EXTRACT(WEEK …)` is
      // ISO-8601, which disagrees at the start of most years and around the
      // turn of it — 2025-06-01 is week 23 to the engine and 22 to ISO.
      // This is `datetime.js:227-229` transcribed: the days elapsed since
      // 1 January, plus that day's weekday, over seven.
      const d = args[0];
      return {
        sql: `(FLOOR(((EXTRACT(DOY FROM ${d}) - 1) + EXTRACT(DOW FROM DATE_TRUNC('year', ${d}))) / 7) + 1)`,
        pushdown: 'full',
        type: 'number',
      };
    }
    if (name === 'ISOWEEKNUM') {
      // The one `EXTRACT(WEEK …)` actually is.
      return { sql: `EXTRACT(WEEK FROM ${args[0]})`, pushdown: 'full', type: 'number' };
    }
    if (name === 'DATE') {
      // `DATE(y, m, d)` in the evaluator is a CONSTRUCTOR, and it rolls over —
      // `DATE(2026, 13, 45)` is 2027-02-14. This compiled it as a one-argument
      // cast, which is a different function entirely, and `MAKE_DATE` raises on
      // the inputs the evaluator accepts. Left to the in-process path.
      return { sql: '', pushdown: 'none' };
    }
    if (name === 'TODATE') {
      return { sql: `(${args[0]})::date`, pushdown: 'full', type: 'date' };
    }
    if (name === 'TODAY' || name === 'NOW' || name === 'CURRENTUSER' || name === 'USERID') {
      // Volatile — cannot push down.
      return { sql: '', pushdown: 'none' };
    }

    // --- Aggregates -----------------------------------------------------
    //
    // SUM/AVERAGE/COUNT/COUNTA are LIST functions applied to a row's values,
    // and they were compiled to SQL AGGREGATES. In row scope that is not a
    // slower answer, it is a different question: `SUM({Qty})` collapses the
    // table to one row instead of answering `{Qty}`. In a WHERE clause it is
    // not a question at all — `aggregate functions are not allowed in WHERE` —
    // so the route answered 500 to a filter the product had already validated.
    if (name === 'SUM' || name === 'AVG' || name === 'AVERAGE' || name === 'COUNT'
      || name === 'COUNTA' || name === 'MINA' || name === 'MAXA') {
      return { sql: '', pushdown: 'none' };
    }

    // Default: function not mapped to SQL.
    return { sql: '', pushdown: 'none' };
  }

  /** Find a field definition in the schema (case-insensitive). */
  _findField(name) {
    // Direct match.
    if (this.schema[name]) return this.schema[name];
    // Case-insensitive fallback.
    const lower = String(name).toLowerCase();
    for (const key of Object.keys(this.schema)) {
      if (key.toLowerCase() === lower) return this.schema[key];
    }
    return null;
  }
}

/**
 * Compile a formula expression to SQL and return the raw query components
 * for direct use with a PostgreSQL client.
 *
 * @param {string} source formula text
 * @param {Object<string, {type: string, column: string}>} schema
 * @param {object} [opts]
 * @returns {{text: string, values: any[], pushdown: string}}
 */
export function compileToSqlQuery(source, schema = {}, opts = {}) {
  const { sql, params, pushdown } = compileToSql(source, schema, opts);
  return { text: sql, values: params, pushdown };
}

/**
 * Check if a formula can be fully pushed down to SQL.
 *
 * @param {string} source formula text
 * @param {Object<string, {type: string, column: string}>} schema
 * @returns {boolean}
 */
export function isPushdownable(source, schema = {}) {
  const { pushdown } = compileToSql(source, schema);
  return pushdown === 'full';
}

const canCompileCache = new Map();

/**
 * Can this compiler emit SQL for `NAME(...)` called with `argc` arguments?
 *
 * The single source of truth for "does this function push down", asked of the
 * compiler itself by compiling a probe call. It replaces a registry flag
 * (`entry.pushdown`) that no function ever set, which left the classifier
 * answering "yes" for everything and the capability list "yes" for everything.
 * Several probe argument shapes are tried because some emissions refuse a
 * number where text is expected and vice versa; one that compiles is enough.
 *
 * @param {string} name
 * @param {number} [argc]
 * @returns {boolean}
 */
export function canCompile(name, argc = 1) {
  const key = `${String(name).toUpperCase()}/${argc}`;
  const cached = canCompileCache.get(key);
  if (cached !== undefined) return cached;
  const num = { type: 'number', value: 1 };
  const str = { type: 'string', value: 'a' };
  const shapes = [
    Array(argc).fill(num),
    Array(argc).fill(str),
    Array.from({ length: argc }, (_, i) => (i === 0 ? num : str)),
    Array.from({ length: argc }, (_, i) => (i === 0 ? str : num)),
  ];
  let ok = false;
  for (const args of shapes) {
    try {
      const out = new SqlCompiler({}, [], false).compileCall({ type: 'call', name, args });
      if (out && out.pushdown !== 'none') { ok = true; break; }
    } catch {
      // A probe the compiler throws on is not a function it can emit.
    }
  }
  canCompileCache.set(key, ok);
  return ok;
}
