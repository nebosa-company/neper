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
 * Tree-walking evaluator.
 *
 * Values flow as native JS (see values.js); errors are first-class values that
 * propagate through operators. Non-lazy functions auto-propagate an error
 * argument (returning it without invoking the implementation) unless the entry
 * declares `passErrors` (information/type functions inspect errors themselves).
 * Lazy functions (IF, IFERROR, AND/OR short-circuit, LET/LETS, MAP/FILTER/…)
 * receive raw AST arg nodes plus this evaluator so they can control evaluation
 * and bind lambda scopes (`current`, `index`).
 *
 * A per-evaluation step budget terminates runaway expressions
 * (REQ security/sandboxing). No `eval()`/`Function()` is ever used.
 *
 * Dependency-free: no DOM, no network, no Supabase.
 */

import { isError, genericError, limitError, nameError, divZero, valueError, refError, circularError } from './errors.js';
// Sibling formulas arrive as source (that is how a column stores them), so
// resolving one means parsing it. parser.js imports nothing from here, so this
// closes no cycle — see tests/import-cycles.test.js.
import { parse } from './parser.js';
import { toNumber, toText, toBool, isBlank, looseEquals, compareValues } from './values.js';
import { checkArity } from './registry.js';

const hasOwn = (obj, key) => Object.prototype.hasOwnProperty.call(obj, key);

/**
 * The evaluation context, named once rather than described in prose.
 *
 * Only `fields`, `getField`, `maxSteps`, `strictRefs`, `fieldName` and
 * `formulas` are read by the evaluator itself; the rest are read by function
 * implementations that receive the same object, which is why they belong in the
 * type even though nothing in this file touches them.
 *
 * `fieldName` is the field this formula BELONGS to and `formulas` the other
 * formula fields beside it (name -> source). Both are optional and both exist
 * for one reason: without them a formula has no idea which cell it is filling,
 * so `{Progress} + 1` stored on the column named `Progress` reads a blank and
 * quietly answers blank — a cell that depends on itself, rendering as though it
 * simply had nothing to say. With them the cycle is named. See resolveCell().
 *
 * @typedef {{ fields?: Object<string, any>, getField?: (name: string) => any,
 *   rowId?: any, tableId?: any, appId?: any, realmId?: any, userId?: any,
 *   createdOn?: any, createdBy?: any, updatedOn?: any, updatedBy?: any,
 *   browserAgent?: any, now?: any, random?: () => number, maxSteps?: number,
 *   strictRefs?: boolean, fieldName?: string,
 *   formulas?: Object<string, string> }} EvalContext
 */

export class Evaluator {
  /**
   * @param {import('./registry.js').Registry} registry
   * @param {EvalContext} ctx
   */
  constructor(registry, ctx = {}) {
    this.registry = registry;
    this.ctx = ctx;
    this.steps = 0;
    this.maxSteps = ctx.maxSteps || 2_000_000;
    // The formulas being evaluated right now, outermost first. A reference to
    // any name on it is a cycle. The field this formula belongs to seeds the
    // stack, which is what makes a DIRECT self-reference detectable even when
    // no sibling formulas were supplied.
    this.resolving = [];
    if (ctx.fieldName != null && String(ctx.fieldName) !== '') {
      this.resolving.push(String(ctx.fieldName));
    }
    /** @type {Map<string, object>} parsed sibling formulas, one parse each. */
    this.formulaAsts = new Map();
  }

  tick() {
    if (++this.steps > this.maxSteps) {
      throw limitError('Evaluation budget exceeded');
    }
  }

  /**
   * Evaluate an AST node under an optional variable scope.
   * @returns {*} a value or FormulaError
   */
  eval(node, scope = null) {
    this.tick();
    switch (node.type) {
      case 'number':
      case 'string':
      case 'bool':
        return node.value;
      case 'null':
        return null;
      case 'array':
        return node.elements.map((e) => this.eval(e, scope));
      case 'field':
        return this.resolveField(node.name);
      case 'name':
        return this.resolveName(node.name, scope);
      case 'unary':
        return this.evalUnary(node, scope);
      case 'binary':
        return this.evalBinary(node, scope);
      case 'ternary': {
        const c = this.eval(node.cond, scope);
        if (isError(c)) return c;
        return toBool(c) ? this.eval(node.then, scope) : this.eval(node.alt, scope);
      }
      case 'call':
        return this.evalCall(node, scope);
      default:
        return genericError(`Unknown node type: ${node.type}`);
    }
  }

  resolveName(name, scope) {
    if (scope && hasOwn(scope, name)) return scope[name];
    // Field context takes priority so a field named like a function still reads.
    const fieldVal = this.resolveCell(name);
    if (fieldVal !== undefined) return fieldVal;
    // Zero-arg function used without parentheses (PI, NOW, TODAY, USERID…).
    const entry = this.registry.resolve(name);
    if (entry && (entry.minArgs ?? 0) === 0) {
      return this.invoke(entry, [], [], scope);
    }
    if (this.ctx.strictRefs) return refError(`Unknown reference "${name}"`);
    return null;
  }

  resolveField(name) {
    const v = this.resolveCell(name);
    if (v !== undefined) return v;
    if (this.ctx.strictRefs) return refError(`Unknown field "${name}"`);
    return null;
  }

  /**
   * One cell, cycle-aware: the #REF! naming the cycle if this name is already
   * being computed, the value of its own formula if one was declared for it,
   * and otherwise whatever the host stored.
   *
   * A cycle has to be answered HERE rather than left to arithmetic. The missing
   * value of a field being computed reads as blank, blank propagates through
   * `+` by design (REQ-09), and the cell ends up empty — the one rendering that
   * says "this formula has nothing to report" when what happened is that it
   * could never have a value at all.
   *
   * Returns undefined when no field, and no formula, answers to the name; both
   * callers have their own not-found handling for that.
   */
  resolveCell(name) {
    const at = this.resolvingIndex(name);
    if (at !== -1) {
      // The cycle as walked, closed back onto its first member: A → B → A.
      return circularError(this.resolving.slice(at).concat(this.resolving[at]));
    }
    const formula = this.formulaEntry(name);
    if (formula) return this.evalFormula(formula.name, formula.source);
    return this.lookupField(name);
  }

  /** Where `name` sits on the resolution stack, matched as fields are. */
  resolvingIndex(name) {
    const lower = String(name).toLowerCase();
    return this.resolving.findIndex((n) => n.toLowerCase() === lower);
  }

  /**
   * The formula declared for a field, as `{name, source}` under the spelling
   * `ctx.formulas` uses, or null. Matched case-insensitively like lookupField,
   * so one map serves both. A declared-but-empty formula is not one: a column
   * created before its expression is written is a legitimate state, and its
   * stored cell is what should be read.
   */
  formulaEntry(name) {
    const map = this.ctx.formulas;
    if (!map || typeof map !== 'object') return null;
    let key = null;
    if (hasOwn(map, name)) {
      key = name;
    } else {
      const lower = String(name).toLowerCase();
      for (const k of Object.keys(map)) {
        if (k.toLowerCase() === lower) {
          key = k;
          break;
        }
      }
    }
    if (key === null) return null;
    const source = map[key];
    if (typeof source !== 'string' || source.trim() === '') return null;
    return { name: key, source };
  }

  /**
   * Evaluate a sibling field's own formula, with its name on the resolution
   * stack for the duration. Parsed once per evaluation — a field read twice in
   * one expression is not re-parsed — and evaluated in a fresh scope, because a
   * LET binding in one formula is not visible in another.
   */
  evalFormula(name, source) {
    let ast = this.formulaAsts.get(name);
    if (!ast) {
      try {
        ast = parse(source);
      } catch (e) {
        return genericError(e && e.message ? e.message : 'Parse error');
      }
      this.formulaAsts.set(name, ast);
    }
    this.resolving.push(name);
    try {
      return this.eval(ast);
    } finally {
      this.resolving.pop();
    }
  }

  /** Returns the field value, or undefined when the field is not present. */
  lookupField(name) {
    if (typeof this.ctx.getField === 'function') {
      const v = this.ctx.getField(name);
      return v === undefined ? undefined : normalizeCell(v);
    }
    const fields = this.ctx.fields;
    if (fields && typeof fields === 'object') {
      if (hasOwn(fields, name)) return normalizeCell(fields[name]);
      // Case-insensitive fallback (display names may differ in case).
      const lower = name.toLowerCase();
      for (const key of Object.keys(fields)) {
        if (key.toLowerCase() === lower) return normalizeCell(fields[key]);
      }
    }
    return undefined;
  }

  evalUnary(node, scope) {
    const v = this.eval(node.operand, scope);
    if (isError(v)) return v;
    switch (node.op) {
      case '-': {
        if (isBlank(v)) return null;
        const n = toNumber(v);
        if (isError(n)) return n;
        return n === null ? null : -n;
      }
      case '+': {
        if (isBlank(v)) return null;
        return toNumber(v);
      }
      case '!':
        return !toBool(v);
      default:
        return genericError(`Unknown unary operator ${node.op}`);
    }
  }

  evalBinary(node, scope) {
    const op = node.op;

    // Short-circuit logical operators.
    if (op === '||') {
      const l = this.eval(node.left, scope);
      if (isError(l)) return l;
      if (toBool(l)) return true;
      const r = this.eval(node.right, scope);
      if (isError(r)) return r;
      return toBool(r);
    }
    if (op === '&&') {
      const l = this.eval(node.left, scope);
      if (isError(l)) return l;
      if (!toBool(l)) return false;
      const r = this.eval(node.right, scope);
      if (isError(r)) return r;
      return toBool(r);
    }

    const left = this.eval(node.left, scope);
    if (isError(left)) return left;
    const right = this.eval(node.right, scope);
    if (isError(right)) return right;

    switch (op) {
      case '&':
        return concat(left, right);
      case '=':
      case '==':
        return looseEquals(left, right);
      case '!=':
      case '<>':
        return !looseEquals(left, right);
      case '<':
      case '<=':
      case '>':
      case '>=': {
        const c = compareValues(left, right);
        if (isError(c)) return c;
        if (op === '<') return c < 0;
        if (op === '<=') return c <= 0;
        if (op === '>') return c > 0;
        return c >= 0;
      }
      case '+':
      case '-':
      case '*':
      case '/':
      case '%':
      case '^':
        return arithmetic(op, left, right);
      default:
        return genericError(`Unknown operator ${op}`);
    }
  }

  evalCall(node, scope) {
    const entry = this.registry.resolve(node.name);
    if (!entry) return nameError(`Unknown function "${node.name}"`);
    const arityMsg = checkArity(entry, node.args.length);
    if (arityMsg) return valueError(arityMsg);
    return this.invoke(entry, node.args, node.args, scope);
  }

  /**
   * Invoke a resolved entry. For lazy entries `argNodes` are passed through;
   * otherwise each node is evaluated first (with error auto-propagation unless
   * `passErrors`).
   */
  invoke(entry, argNodes, _rawNodes, scope) {
    if (entry.lazy) {
      try {
        return entry.fn(argNodes, this.ctx, this, scope);
      } catch (e) {
        return isError(e) ? e : genericError(e && e.message);
      }
    }
    const args = [];
    for (const argNode of argNodes) {
      const v = this.eval(argNode, scope);
      if (isError(v) && !entry.passErrors) return v;
      args.push(v);
    }
    try {
      return entry.fn(args, this.ctx, this, scope);
    } catch (e) {
      return isError(e) ? e : genericError(e && e.message ? e.message : 'Error');
    }
  }
}

// --- operator helpers -----------------------------------------------------

function concat(a, b) {
  const ta = toText(a);
  if (isError(ta)) return ta;
  const tb = toText(b);
  if (isError(tb)) return tb;
  return ta + tb;
}

function arithmetic(op, left, right) {
  // Blank propagates (not zero) for operator arithmetic (REQ-09).
  if (isBlank(left) || isBlank(right)) return null;
  const a = toNumber(left);
  if (isError(a)) return a;
  const b = toNumber(right);
  if (isError(b)) return b;
  switch (op) {
    case '+':
      return a + b;
    case '-':
      return a - b;
    case '*':
      return a * b;
    case '/':
      if (b === 0) return divZero();
      return a / b;
    case '%':
      if (b === 0) return divZero();
      return a % b;
    case '^': {
      const r = Math.pow(a, b);
      return Number.isNaN(r) ? valueError('Invalid exponentiation') : r;
    }
    default:
      return genericError(`Unknown operator ${op}`);
  }
}

/**
 * Normalise a raw host cell value into an engine value. Recognises ISO date
 * strings? No — leave strings as strings; date functions coerce explicitly to
 * avoid surprising numeric strings becoming dates. Empty string stays as-is.
 */
function normalizeCell(v) {
  return v;
}
