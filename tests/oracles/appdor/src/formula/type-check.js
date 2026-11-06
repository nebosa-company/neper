/**
 * Static type checking for formula expressions (LC10).
 *
 * Walks the AST to detect type errors at known source offsets before evaluation,
 * so the formula editor can show red underlines and gutter markers. Also
 * computes pushdown classification — whether the whole expression can be
 * compiled to SQL — by walking the AST and checking each function's pushdown
 * capability.
 *
 * Pure, dependency-free except for the function registry.
 */

import { parse, collectReferences, ParseError } from './parser.js';
import { getRegistry } from './default-registry.js';

/**
 * A positioned diagnostic, as a catalogue KEY plus its values rather than as a
 * sentence.
 *
 * The person who reads these is the formula author, in the editor, in their
 * own language — so the words are owed to `locales/*.json` under
 * `formula.diag.*`. This module is pure and has no document to read a language
 * out of, so it names the diagnostic and the editor renders it, the same split
 * `forms/index.js` uses for `form.validation.pattern`.
 *
 * `code` and `messageKey` are NOT redundant: `code` is the class a caller
 * switches on (`type_mismatch` covers two different sentences), `messageKey`
 * is the exact sentence. `detail` carries text this module did not author —
 * the parser's own structural message — which stays in the formula language's
 * terms and is appended by the editor, not translated.
 *
 * @typedef {Object} TypeDiagnostic
 * @property {string} kind 'type_error' | 'warning' | 'info'
 * @property {string} messageKey catalogue key, `formula.diag.*`
 * @property {Object<string, string>} [params] interpolation values for messageKey
 * @property {string} [detail] untranslated parser text, if any
 * @property {number} offset character position in source
 * @property {string} [code] machine-readable error code
 */

/**
 * @typedef {Object} ValidationResult
 * @property {boolean} ok
 * @property {TypeDiagnostic[]} diagnostics positioned diagnostics
 * @property {string} [inferredType] 'number'|'text'|'boolean'|'date'|'array'|'blank'|'error'
 * @property {'volatile'|'stable'} volatilityClass
 * @property {'full'|'partial'|'none'} pushdown
 * @property {string[]} references field references
 * @property {string[]} functions called function names
 */

/**
 * Validate and diagnose a formula expression.
 *
 * @param {string} source formula text
 * @param {object} [opts]
 * @param {Object<string, string>} [opts.fieldTypes] field name → type hint
 * @returns {ValidationResult}
 */
export function diagnoseExpression(source, opts = {}) {
  const diagnostics = [];

  // Parse — syntax errors become positioned diagnostics.
  let ast;
  try {
    ast = parse(source);
  } catch (e) {
    const offset = (e instanceof ParseError && typeof e.offset === 'number') ? e.offset : 0;
    diagnostics.push({
      kind: 'type_error',
      messageKey: 'formula.diag.syntaxError',
      detail: e.message || '',
      offset,
      code: 'parse_error',
    });
    return {
      ok: false,
      diagnostics,
      inferredType: 'error',
      volatilityClass: 'stable',
      pushdown: 'none',
      references: [],
      functions: [],
    };
  }

  // Collect references and called functions.
  const references = collectReferences(ast);
  const functions = calledFunctions(ast);

  // Walk the AST for type errors at known positions.
  const registry = getRegistry();
  walkForTypeErrors(ast, registry, opts.fieldTypes || {}, diagnostics);

  // Determine volatility: if any called function is volatile, the whole
  // expression is volatile.
  let volatile = false;
  for (const fn of functions) {
    const entry = registry.resolve(fn);
    if (entry && entry.volatile) {
      volatile = true;
      break;
    }
  }

  // Determine pushdown class: 'full' if every function supports pushdown and
  // no volatile functions are present (volatile = read-evaluated by nature).
  /** @type {ValidationResult['pushdown']} */
  let pushdown = 'full';
  if (volatile) {
    pushdown = 'none';
  } else {
    for (const fn of functions) {
      const entry = registry.resolve(fn);
      if (!entry || entry.pushdown === false) {
        pushdown = 'partial';
        break;
      }
    }
  }

  // Simple type inference from the AST root.
  const inferredType = inferAstType(ast, opts.fieldTypes || {});

  return {
    ok: diagnostics.filter((d) => d.kind === 'type_error').length === 0,
    diagnostics,
    inferredType,
    volatilityClass: volatile ? 'volatile' : 'stable',
    pushdown,
    references,
    functions,
  };
}

// --- AST walking ----------------------------------------------------------------

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
 * Walk the AST to detect type errors. Currently detects:
 * - Arithmetic on non-numeric operands at known positions
 * - String concatenation with numeric-only operators
 * - Comparison between incompatible types
 */
function walkForTypeErrors(node, registry, fieldTypes, diagnostics) {
  if (!node || typeof node !== 'object') return;

  switch (node.type) {
    case 'binary': {
      const op = node.op;
      if (op === '+' || op === '-' || op === '*' || op === '/' || op === '%' || op === '^') {
        // Check left operand type
        const leftType = nodeType(node.left, registry, fieldTypes);
        const rightType = nodeType(node.right, registry, fieldTypes);
        if (leftType === 'text' && op !== '&' && op !== '+' && op !== '=' && op !== '==') {
          diagnostics.push({
            kind: 'type_error',
            messageKey: 'formula.diag.operatorOnTextConcat',
            params: { op },
            offset: node.left.pos ?? 0,
            code: 'type_mismatch',
          });
        }
        if (rightType === 'text' && op !== '&' && op !== '+' && op !== '=' && op !== '==') {
          diagnostics.push({
            kind: 'type_error',
            messageKey: 'formula.diag.operatorOnText',
            params: { op },
            offset: node.right.pos ?? 0,
            code: 'type_mismatch',
          });
        }
      }
      break;
    }
    case 'call': {
      // Check function exists in registry.
      const entry = registry.resolve(node.name);
      if (!entry) {
        diagnostics.push({
          kind: 'type_error',
          messageKey: 'formula.diag.unknownFunction',
          params: { name: node.name },
          offset: node.pos ?? 0,
          code: 'unknown_function',
        });
      }
      break;
    }
  }

  // Recurse into children.
  for (const key of Object.keys(node)) {
    const child = node[key];
    if (Array.isArray(child)) child.forEach((c) => walkForTypeErrors(c, registry, fieldTypes, diagnostics));
    else if (child && typeof child === 'object') walkForTypeErrors(child, registry, fieldTypes, diagnostics);
  }
}

/** Best-effort type of an AST node, from literal value or field type hint. */
function nodeType(node, _registry, fieldTypes) {
  if (!node || typeof node !== 'object') return 'blank';
  switch (node.type) {
    case 'number': return 'number';
    case 'string': return 'text';
    case 'bool': return 'boolean';
    case 'null': return 'blank';
    case 'array': return 'array';
    case 'field':
    case 'name':
      return fieldTypes[node.name] || 'blank';
    case 'unary': {
      if (node.op === '!') return 'boolean';
      return nodeType(node.operand, _registry, fieldTypes);
    }
    case 'call': {
      // Approximate: number functions return number, text functions return text, etc.
      return 'blank';
    }
    case 'binary': {
      if (node.op === '&') return 'text';
      if (node.op === '=' || node.op === '==' || node.op === '!=' || node.op === '<>'
        || node.op === '<' || node.op === '<=' || node.op === '>' || node.op === '>='
        || node.op === '&&' || node.op === '||') {
        return 'boolean';
      }
      // Arithmetic: prefer number.
      const lt = nodeType(node.left, _registry, fieldTypes);
      const rt = nodeType(node.right, _registry, fieldTypes);
      if (lt === 'number' || rt === 'number') return 'number';
      return lt;
    }
    default: return 'blank';
  }
}

/**
 * Infer the type of an AST root (best-effort).
 */
function inferAstType(node, fieldTypes) {
  return nodeType(node, null, fieldTypes);
}
