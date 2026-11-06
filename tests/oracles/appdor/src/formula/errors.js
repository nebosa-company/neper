/**
 * Formula error model.
 *
 * Evaluation errors are first-class *values*, never thrown exceptions or blank
 * cells (REQ-FORMULAENGINE-08). Functions such as IFERROR / IFNA / ISERROR /
 * ISNA intercept them; an unhandled error propagates to the cell and renders as
 * a distinct error state with a hover explanation.
 *
 * Dependency-free: no DOM, no network, no Supabase.
 */

/** Canonical error codes (Excel-compatible surface). */
export const ERROR_CODES = {
  DIV0: '#DIV/0!',
  VALUE: '#VALUE!',
  NA: '#N/A',
  NAME: '#NAME?',
  NUM: '#NUM!',
  REF: '#REF!',
  ERROR: '#ERROR!',
  LIMIT: '#LIMIT!',
};

/**
 * A typed formula error value. Instances flow through evaluation like any other
 * value; `isError` recognises them.
 */
export class FormulaError {
  /**
   * @param {string} code one of ERROR_CODES
   * @param {string} [message] human-readable explanation for the hover tooltip
   */
  constructor(code, message = '') {
    this.code = code;
    this.message = message;
    this.isFormulaError = true;
  }

  toString() {
    return this.code;
  }
}

/** True when `v` is a FormulaError value. */
export function isError(v) {
  return v instanceof FormulaError || (v && v.isFormulaError === true);
}

/** True when `v` specifically is the #N/A error. */
export function isNA(v) {
  return isError(v) && v.code === ERROR_CODES.NA;
}

// Convenience constructors -------------------------------------------------

export const divZero = (msg = 'Division by zero') =>
  new FormulaError(ERROR_CODES.DIV0, msg);
export const valueError = (msg = 'Wrong type of argument') =>
  new FormulaError(ERROR_CODES.VALUE, msg);
export const naError = (msg = 'Value not available') =>
  new FormulaError(ERROR_CODES.NA, msg);
export const nameError = (msg = 'Unknown name') =>
  new FormulaError(ERROR_CODES.NAME, msg);
export const numError = (msg = 'Invalid numeric value') =>
  new FormulaError(ERROR_CODES.NUM, msg);
export const refError = (msg = 'Invalid reference') =>
  new FormulaError(ERROR_CODES.REF, msg);
export const genericError = (msg = 'Formula error') =>
  new FormulaError(ERROR_CODES.ERROR, msg);

/** Resource cap exceeded — step budget, AST complexity, or traversal depth. */
export const limitError = (msg = 'Resource limit exceeded') =>
  new FormulaError(ERROR_CODES.LIMIT, msg);

/**
 * A field whose value depends on its own value (REQ-FORMULAENGINE-07).
 *
 * `path` is the cycle in order — `['A', 'B', 'A']` — and is spelled out in the
 * message because "which cycle" is the only question worth asking on seeing
 * one. The renderer shows that message as the cell's hover explanation.
 *
 * The code is #REF!, not a new one: a reference that resolves to itself is an
 * invalid reference, ERROR_CODES is the Excel-compatible seven, and a spelling
 * invented here would reach cells that no other layer of this product — or any
 * spreadsheet a value is exported to — recognises. `validate.js` refuses the
 * same shape at write time under `formula_self_reference` /
 * `formula_circular_reference`; this is what the rows written before it existed
 * evaluate to.
 */
export const circularError = (path) =>
  new FormulaError(
    ERROR_CODES.REF,
    `Circular reference: ${Array.isArray(path) ? path.join(' → ') : String(path)}`,
  );
