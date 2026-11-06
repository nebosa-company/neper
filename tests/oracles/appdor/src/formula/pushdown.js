/**
 * Pushdown classifier for formula expressions (LC10).
 *
 * Decides whether a formula expression can be compiled to SQL and pushed down
 * to the database for filtering, sorting, and aggregation — or whether it must
 * be evaluated in-process per row. Classifies into:
 *
 *   'full'    — every operator and function supports pushdown; the expression
 *              can compile to a single parameterized SQL clause.
 *   'partial' — some functions support pushdown, others don't; a hybrid plan
 *              (SQL pre-filter + in-process remainder) is possible.
 *   'none'    — no pushdown possible (e.g. volatile functions, host callbacks,
 *              cross-table references).
 *
 * Pure — reads the function registry's pushdown flags per function.
 */

import { parse } from './parser.js';
import { getRegistry } from './default-registry.js';
// The compiler is the authority on what it can emit; the registry's own
// `pushdown` flag was never set by any function.
import { canCompile } from './sql-compiler.js';

/**
 * What the classifier answers, named once because two functions return it and
 * one of them returns the other's result.
 *
 * `reason` is a CODE, not a sentence. The audience for it is the query planner
 * — the thing that has to decide between a SQL clause and a per-row walk — and
 * a planner that has to string-match "one or more functions do not support SQL
 * pushdown" is a planner that breaks when the wording improves. A surface that
 * wants to tell a person why their filter is slow renders its own copy from
 * `classification`, `reason` and `unsupportedFunctions`.
 *
 * @typedef {Object} PushdownVerdict
 * @property {'full'|'partial'|'none'} classification
 * @property {'parse-error'|'volatile-functions'|'unsupported-functions'} [reason]
 * @property {string[]} [unsupportedFunctions]
 */

/**
 * Classify pushdown capability of a formula expression.
 *
 * @param {string} source formula text
 * @returns {PushdownVerdict}
 */
export function classifyPushdown(source) {
  if (!source || typeof source !== 'string' || source.trim() === '') {
    return { classification: 'full' };
  }

  let ast;
  try {
    ast = parse(source);
  } catch {
    return { classification: 'none', reason: 'parse-error' };
  }

  return classifyAst(ast);
}

/**
 * Classify an already-parsed AST.
 *
 * @param {object} ast
 * @returns {PushdownVerdict}
 */
export function classifyAst(ast) {
  const registry = getRegistry();
  const unsupported = [];
  let hasVolatile = false;
  let hasUnsupportedOp = false;

  const walk = (node) => {
    if (!node || typeof node !== 'object') return;

    if (node.type === 'call') {
      const entry = registry.resolve(node.name);
      if (!entry) {
        // Unknown function — cannot push down.
        unsupported.push(node.name);
        hasUnsupportedOp = true;
      } else if (entry.volatile) {
        // Volatile functions (NOW, TODAY, CURRENTUSER) are read-evaluated.
        hasVolatile = true;
      } else if (entry.pushdown === false || !canCompile(entry.name, Array.isArray(node.args) ? node.args.length : 1)) {
        // Explicitly marked, or the SQL compiler has no emission for it.
        unsupported.push(node.name);
        hasUnsupportedOp = true;
      }
    }

    // Cross-record functions require host callbacks — never push-down.
    if (node.type === 'call' && ['GETRECORDS', 'GETFIELDVALUES', 'CHILDREN', 'ANCESTORS'].includes(String(node.name).toUpperCase())) {
      unsupported.push(node.name);
      hasUnsupportedOp = true;
    }

    // Field references are pushdown-able (they become column refs).
    // Name references that are NOT fields (variables from LET) are not.

    for (const key of Object.keys(node)) {
      const child = node[key];
      if (Array.isArray(child)) child.forEach(walk);
      else if (child && typeof child === 'object') walk(child);
    }
  };

  walk(ast);

  if (hasVolatile) {
    return {
      classification: 'none',
      // Volatile functions (NOW, TODAY, CURRENTUSER) must be read-evaluated.
      reason: 'volatile-functions',
      unsupportedFunctions: unsupported.length ? unsupported : undefined,
    };
  }

  if (hasUnsupportedOp) {
    return {
      classification: 'partial',
      reason: 'unsupported-functions',
      unsupportedFunctions: [...new Set(unsupported)],
    };
  }

  return { classification: 'full' };
}

/**
 * List the pushdown capability for each function in the registry (for docs and
 * autocomplete display).
 *
 * @returns {Array<{name: string, pushdown: boolean}>}
 */
export function pushdownCapabilities() {
  return getRegistry()
    .list()
    .map((e) => ({ name: e.name, pushdown: e.pushdown !== false && !e.volatile && canCompile(e.name, e.minArgs ?? 1) }));
}
