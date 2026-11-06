/**
 * Static validation for a formula column definition.
 *
 * The engine could already answer every one of these questions — `parse()`
 * raises on unbalanced source, `Registry.resolve()` returns null for a name
 * nobody registered, `detectCycle()` walks the dependency graph — and none of
 * it was on the write path. `POST /rest/v1/table_columns` accepted `1/0`,
 * `NOSUCHFUNC(1)`, `IF({Name} = "x", "yes"` and `{F_selfref} + 1` with 201
 * apiece, measured against the running stack on 2026-08-03.
 *
 * This module composes what is already here into one verdict. It parses; it
 * does NOT evaluate. Evaluating to decide validity would be wrong in both
 * directions: `GETFIELDVALUES("Deals", "Amount")` fails without a host context
 * and is perfectly valid, and `RAND()` succeeds without proving anything. So
 * every check below reads the AST.
 *
 * The five reasons are the same vocabulary
 * `supabase/init/53-value-constraints.sql` raises, so a client can branch on
 * one set of tokens whichever layer said no. The database is the narrower of
 * the two by design — it decides balance rather than full grammar, and reports
 * `formula_unbalanced` where this module can say `formula_syntax_error` with
 * the parser's own sentence. `tests/formula/validate.test.js` pins the
 * direction that matters: the database never refuses source this accepts.
 *
 * Pure and DOM-free, like the rest of `src/formula/`.
 */

import { parse, collectReferences } from './parser.js';
// The shared registry, from the leaf that owns it. Reaching it through
// index.js would close a cycle — index.js re-exports this module — and a cycle
// here is not benign: `tests/import-cycles.test.js` refuses one because the
// failure mode is a half-initialised namespace rather than a crash.
import { getRegistry } from './default-registry.js';

/** Every `call` node name in an AST, in source order, duplicates included. */
function calledFunctions(ast) {
  const names = [];
  const walk = (node) => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'call' && node.name) names.push(node.name);
    for (const key of Object.keys(node)) {
      const child = node[key];
      if (Array.isArray(child)) child.forEach(walk);
      else if (child && typeof child === 'object') walk(child);
    }
  };
  walk(ast);
  return names;
}

/**
 * Does the AST divide by a literal zero?
 *
 * Only the literal case. `{a} / {b}` may or may not divide by zero depending on
 * the row, and that is the evaluator's `#DIV/0!` to return at render time — a
 * column definition that MIGHT fail is not a column definition that is wrong.
 * `1/0` always fails and can be refused before it is stored.
 */
function dividesByLiteralZero(ast) {
  let found = false;
  const walk = (node) => {
    if (found || !node || typeof node !== 'object') return;
    if (node.type === 'binary' && (node.op === '/' || node.op === '%')
        && node.right && node.right.type === 'number' && Number(node.right.value) === 0) {
      found = true;
      return;
    }
    for (const key of Object.keys(node)) {
      const child = node[key];
      if (Array.isArray(child)) child.forEach(walk);
      else if (child && typeof child === 'object') walk(child);
    }
  };
  walk(ast);
  return found;
}

/**
 * Validate a formula as a column definition.
 *
 * @param {string} source the formula text
 * @param {object} [opts]
 * @param {string} [opts.name] the column the formula belongs to, for self- and
 *   cycle-reference detection and for the message
 * @param {Object<string,string>} [opts.siblings] the other formula columns on
 *   the same table, `name -> source`. Only names present here participate in
 *   the cycle walk, so an ordinary field reference is never mistaken for one.
 * @returns {{ok: true, references: string[]}
 *          |{ok: false, reason: string, message: string, value: string}}
 */
export function validateFormula(source, opts = {}) {
  const name = opts.name || '';
  const src = typeof source === 'string' ? source.trim() : '';

  // A formula column created before its expression is written is a legitimate
  // intermediate state — the editor in applications.js opens on ''.
  if (src === '') return { ok: true, references: [] };

  let ast;
  try {
    ast = parse(src);
  } catch (e) {
    return {
      ok: false,
      reason: 'formula_syntax_error',
      message: name
        ? `the formula for "${name}" does not parse: ${e && e.message ? e.message : 'syntax error'}`
        : `the formula does not parse: ${e && e.message ? e.message : 'syntax error'}`,
      value: src,
    };
  }

  const registry = getRegistry();
  for (const fn of calledFunctions(ast)) {
    if (!registry.resolve(fn)) {
      return {
        ok: false,
        reason: 'formula_unknown_function',
        message: `"${fn}" is not a formula function${name ? `, in the formula for "${name}"` : ''}`,
        value: fn,
      };
    }
  }

  if (dividesByLiteralZero(ast)) {
    return {
      ok: false,
      reason: 'formula_division_by_zero',
      message: name ? `the formula for "${name}" divides by zero` : 'the formula divides by zero',
      value: src,
    };
  }

  const references = collectReferences(ast);

  if (name && references.some((r) => String(r).toLowerCase() === name.toLowerCase())) {
    return {
      ok: false,
      reason: 'formula_self_reference',
      message: `the formula for "${name}" refers to itself`,
      value: name,
    };
  }

  if (name && opts.siblings) {
    const graph = {};
    for (const [k, v] of Object.entries(opts.siblings)) {
      if (k !== name) graph[k] = v;
    }
    graph[name] = src;
    if (cycleThrough(graph, name)) {
      return {
        ok: false,
        reason: 'formula_circular_reference',
        message: `the formula for "${name}" is part of a circular reference`,
        value: src,
      };
    }
  }

  return { ok: true, references };
}

/** Can `start` reach itself through the formula dependency graph? */
function cycleThrough(graph, start) {
  const edges = {};
  for (const [k, v] of Object.entries(graph)) {
    let refs = [];
    try {
      refs = collectReferences(parse(String(v || '')));
    } catch {
      refs = []; // an unparseable sibling cannot be walked; it fails on its own write
    }
    // Case-insensitive, as the evaluator resolves names.
    const byLower = new Map(Object.keys(graph).map((g) => [g.toLowerCase(), g]));
    edges[k] = [...new Set(refs.map((r) => byLower.get(String(r).toLowerCase())).filter((r) => r !== undefined))];
  }
  const seen = new Set();
  const queue = [...(edges[start] || [])];
  while (queue.length) {
    const n = queue.shift();
    if (n === start) return true;
    if (seen.has(n)) continue;
    seen.add(n);
    for (const m of edges[n] || []) queue.push(m);
  }
  return false;
}
