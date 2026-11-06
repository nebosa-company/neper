/**
 * Formula engine — public API.
 *
 * One engine, three host surfaces (REQ-FORMULAENGINE-10): calculated fields,
 * view filters, and conditional-coloring rules all consume this identical
 * parser/evaluator. The package is dependency-free — no DOM, no Supabase — and
 * the References group resolves through an injected context object so the host
 * (Neposer/Appdor shell) supplies tenancy and user identity.
 *
 *   import { evaluate } from './formula/index.js';
 *   evaluate('{Price} * {Qty}', { fields: { Price: 10, Qty: 3 } }); // => 30
 */

import { parse as parseSource, collectReferences, ParseError, TokenizeError, COMPLEXITY_REFUSED } from './parser.js';
import { Evaluator } from './evaluator.js';
import { isError, isNA, genericError, limitError, FormulaError, ERROR_CODES } from './errors.js';
import { typeOf } from './values.js';
import { stringify } from './stringify.js';
// The registry and the category modules it registers live in a leaf, so that a
// module inside the package can reach the shared registry without importing
// this façade back. See default-registry.js.
import { buildRegistry, getRegistry } from './default-registry.js';

// `buildRegistry` and `getRegistry` keep their long-standing home in this
// module's public API; the implementation moved to ./default-registry.js.
export { buildRegistry, getRegistry };

/**
 * Parse formula source into an AST.
 *
 * `opts` is FORWARDED, which it was not: this façade took one argument and
 * dropped the second, so `parse(source, { maxNodes })` compiled, ran, and
 * silently used the 10,000 default — and since every one of the eighteen
 * consumers in this product imports the façade rather than `parser.js`, the
 * AST-complexity cap was a constant nobody could move. LC10.15 asks for a cap
 * that can be exceeded on purpose and observed; a cap with no way in cannot be
 * tested at its own boundary, only at 10,001 nodes.
 *
 * @param {string} source
 * @param {{maxNodes?: number}} [opts]
 * @throws {ParseError|TokenizeError}
 */
export function parse(source, opts = {}) {
  return parseSource(source, opts);
}

/**
 * Is this the AST-complexity refusal rather than a syntax error?
 *
 * Exported because the two need different answers and only the parser knows
 * which it threw: a syntax error is the author's typo and belongs in the editor
 * with a caret on it, and a complexity refusal is a RESOURCE CAP — `#LIMIT!`,
 * and an observability event with the tenant on it (LC10.15).
 *
 * @param {*} e
 * @returns {boolean}
 */
export function isComplexityRefusal(e) {
  return !!e && e.code === COMPLEXITY_REFUSED;
}

/**
 * Parse and return an AST plus its diagnostics, or a diagnostics-only object on
 * failure — never throws. Shape: {ok, ast?, error?, offset?, references?}.
 */
export function compile(source) {
  try {
    const ast = parseSource(source);
    return { ok: true, ast, references: collectReferences(ast) };
  } catch (e) {
    const err = { ok: false, error: e && e.message ? e.message : 'Parse error' };
    if (e && typeof e.offset === 'number') err.offset = e.offset;
    return err;
  }
}

/**
 * Evaluate a formula. Never throws — parse or runtime failures come back as
 * FormulaError values.
 * @param {string|object} source formula text or a pre-parsed AST
 * @param {object} [ctx] evaluation context (fields, getField, rowId, now, …).
 *   Pass `fieldName` — the field this formula belongs to — and optionally
 *   `formulas`, the sibling formula fields as name -> source, to get a #REF!
 *   naming the cycle when a formula depends on its own value. Without them a
 *   self-reference reads a blank cell and answers blank.
 * @param {import('./registry.js').Registry} [registry] custom registry
 *   (defaults to the shared one)
 * @returns {*} a value or FormulaError
 */
export function evaluate(source, ctx = {}, registry = getRegistry()) {
  let ast;
  if (typeof source === 'string') {
    try {
      ast = parseSource(source, ctx);
    } catch (e) {
      // A resource cap is not a parse error, and returning `#ERROR!` for one
      // said it was. `errors.js` has always documented `#LIMIT!` as covering
      // "step budget, AST complexity, or traversal depth"; the complexity half
      // could not reach it, because every ParseError left here as
      // `genericError`. LC10.15 asks for BOTH caps to answer with the typed
      // limit error, and this is the second one.
      // The parser's own sentence is carried through rather than restated: a
      // second copy here would be a second string to translate and a second
      // one to forget, and the parser is where the cap actually lives.
      if (isComplexityRefusal(e)) return limitError(e.message);
      return genericError(e && e.message ? e.message : 'Parse error');
    }
  } else {
    ast = source;
  }
  const ev = new Evaluator(registry, ctx);
  try {
    return ev.eval(ast);
  } catch (e) {
    return isError(e) ? e : genericError(e && e.message ? e.message : 'Evaluation error');
  }
}

/**
 * The unique field references a formula depends on (by display name).
 * Used for the dependency graph and cycle detection.
 * @returns {string[]}
 */
export function dependencies(source) {
  const ast = typeof source === 'string' ? parseSource(source) : source;
  return collectReferences(ast);
}

/**
 * Detect a circular reference among formula fields (REQ-FORMULAENGINE-07).
 * @param {Object<string,string>} formulaSources map of fieldName -> source
 * @returns {string[]|null} the cycle members in order (a → b → a) or null
 */
/**
 * The formula fields `src` reads, as the keys of `formulaSources`. Names are
 * matched case-insensitively because the evaluator resolves them that way: a
 * graph keyed case-sensitively missed `{progress}` -> `Progress`, so a real
 * cycle through it went undetected.
 */
function knownDependencies(src, formulaSources) {
  const byLower = new Map(Object.keys(formulaSources).map((k) => [k.toLowerCase(), k]));
  const out = [];
  for (const d of dependencies(src)) {
    const key = byLower.get(String(d).toLowerCase());
    if (key !== undefined && !out.includes(key)) out.push(key);
  }
  return out;
}

export function detectCycle(formulaSources) {
  const deps = {};
  for (const [name, src] of Object.entries(formulaSources)) {
    try {
      deps[name] = knownDependencies(src, formulaSources);
    } catch {
      deps[name] = [];
    }
  }
  const WHITE = 0;
  const GRAY = 1;
  const BLACK = 2;
  const color = {};
  const stack = [];
  let cycle = null;
  Object.keys(deps).forEach((n) => (color[n] = WHITE));

  const visit = (n) => {
    if (cycle) return;
    color[n] = GRAY;
    stack.push(n);
    for (const m of deps[n] || []) {
      if (color[m] === GRAY) {
        const idx = stack.indexOf(m);
        cycle = stack.slice(idx).concat(m);
        return;
      }
      if (color[m] === WHITE) {
        visit(m);
        if (cycle) return;
      }
    }
    stack.pop();
    color[n] = BLACK;
  };

  for (const n of Object.keys(deps)) {
    if (color[n] === WHITE) visit(n);
    if (cycle) break;
  }
  return cycle;
}

/**
 * Topologically order formula fields so dependencies evaluate first
 * (REQ-FORMULAENGINE-07). Returns null if a cycle exists.
 * @param {Object<string,string>} formulaSources
 * @returns {string[]|null}
 */
export function evaluationOrder(formulaSources) {
  if (detectCycle(formulaSources)) return null;
  const deps = {};
  for (const [name, src] of Object.entries(formulaSources)) {
    try {
      deps[name] = knownDependencies(src, formulaSources);
    } catch {
      deps[name] = [];
    }
  }
  const order = [];
  const seen = new Set();
  const visit = (n) => {
    if (seen.has(n)) return;
    seen.add(n);
    for (const m of deps[n] || []) visit(m);
    order.push(n);
  };
  Object.keys(deps).forEach(visit);
  return order;
}

/**
 * Infer the output type of a formula given a sample context, activating the
 * matching field-type formatting options (REQ-FORMULAENGINE-05).
 * @returns {'number'|'text'|'boolean'|'date'|'array'|'blank'|'error'}
 */
export function inferType(source, ctx = {}) {
  const v = evaluate(source, ctx);
  return typeOf(v);
}

/** Resolve a (possibly aliased) function name to its canonical entry, or null. */
export function resolveFunction(name) {
  return getRegistry().resolve(name);
}

/** The full function catalog for docs / autocomplete. */
export function functionCatalog() {
  return getRegistry()
    .list()
    .map((e) => ({
      name: e.name,
      aliases: e.aliases || [],
      category: e.category,
      volatile: !!e.volatile,
      generateOnce: !!e.generateOnce,
      minArgs: e.minArgs ?? 0,
      maxArgs: e.maxArgs,
      pushdown: e.pushdown ?? false,
    }));
}

export {
  isError,
  isNA,
  FormulaError,
  ERROR_CODES,
  limitError,
  ParseError,
  TokenizeError,
  collectReferences,
  typeOf,
  stringify,
};

/**
 * Static validation of a formula as a COLUMN DEFINITION — syntax, unknown
 * functions, division by a literal zero, self-reference and cycles. The
 * authoritative copy of the same rules lives in
 * `supabase/init/53-value-constraints.sql`; this is the one a client calls
 * before it writes, so the user sees the reason at the keystroke rather than as
 * a 400.
 */
export { validateFormula } from './validate.js';

export { diagnoseExpression } from './type-check.js';
export { classifyPushdown, classifyAst as classifyPushdownAst, pushdownCapabilities } from './pushdown.js';
