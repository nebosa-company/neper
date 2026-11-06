/**
 * Recursive-descent parser: tokens -> AST.
 *
 * Grammar (low -> high precedence):
 *   expression  := ternary
 *   ternary     := or ('?' expression ':' expression)?
 *   or          := and ('||' and)*
 *   and         := comparison ('&&' comparison)*
 *   comparison  := concat (('='|'=='|'!='|'<>'|'<'|'<='|'>'|'>=') concat)*
 *   concat      := additive ('&' additive)*
 *   additive    := multiplicative (('+'|'-') multiplicative)*
 *   multiplic.  := exponent (('*'|'/'|'%') exponent)*
 *   exponent    := unary ('^' unary)?            // right-associative
 *   unary       := ('-'|'+'|'!') unary | primary
 *   primary     := NUMBER | STRING | BOOL | NULL | FIELD
 *                | IDENT ('(' arglist? ')')?      // call, else bare name ref
 *                | '(' expression ')'
 *                | '[' arglist? ']'               // array literal
 *
 * `let`/`lets` and lambda functions (MAP/FILTER/…) parse as ordinary `call`
 * nodes; the evaluator treats them as special forms.
 *
 * AST node shapes:
 *   {type:'number', value}  {type:'string', value}  {type:'bool', value}
 *   {type:'null'}  {type:'field', name}  {type:'name', name}
 *   {type:'call', name, args:[node]}  {type:'unary', op, operand}
 *   {type:'binary', op, left, right}  {type:'ternary', cond, then, alt}
 *   {type:'array', elements:[node]}
 *
 * Dependency-free.
 */

import { tokenize, TT, TokenizeError } from './tokenizer.js';

/**
 * Parse error with optional position for caret-precise diagnostics
 * (the NQL/AQL heritage the spec requires).
 */
export class ParseError extends Error {
  /**
   * @param {string} message
   * @param {number} [offset] character position in the source where the error
   *   was detected, for gutter markers and caret placement
   * @param {string} [code] a machine-readable classification. Only
   *   `COMPLEXITY_REFUSED` is defined; everything else is a syntax error and
   *   leaves this undefined.
   */
  constructor(message, offset, code) {
    super(message);
    this.offset = offset;
    if (code) this.code = code;
  }
}

/**
 * The `ParseError.code` that means "this is a resource cap, not a typo".
 *
 * The AST-complexity ceiling was refused with a bare `ParseError`, `evaluate()`
 * catches every `ParseError` and returns `genericError`, and so a formula
 * refused for being too large arrived in the cell as `#ERROR!` — the same code
 * a misspelled function name produces, and the same code a stray bracket
 * produces. LC10.15 asks that a resource cap return a TYPED `#LIMIT` error, and
 * `errors.js` has said since it was written that `#LIMIT!` covers "step budget,
 * AST complexity, or traversal depth". One of those three could not reach it.
 *
 * A code rather than a message match: `src/formula/index.js` is the translator,
 * and a translator keyed on English prose breaks the moment the prose is
 * reworded — silently, back to `#ERROR!`, which is precisely the failure this
 * exists to end.
 */
export const COMPLEXITY_REFUSED = 'formula-complexity';

class Parser {
  constructor(tokens) {
    this.tokens = tokens;
    this.i = 0;
  }

  peek() {
    return this.tokens[this.i];
  }

  next() {
    return this.tokens[this.i++];
  }

  atEnd() {
    return this.peek().type === TT.EOF;
  }

  expectPunct(p) {
    const t = this.peek();
    if (t.type === TT.PUNCT && t.value === p) {
      this.i++;
      return;
    }
    throw new ParseError(`Expected '${p}' but found '${this.describe(t)}'`, t.pos);
  }

  describe(t) {
    if (t.type === TT.EOF) return 'end of formula';
    return String(t.value);
  }

  isOp(v) {
    const t = this.peek();
    return t.type === TT.OP && t.value === v;
  }

  isPunct(v) {
    const t = this.peek();
    return t.type === TT.PUNCT && t.value === v;
  }

  parse() {
    if (this.atEnd()) {
      throw new ParseError('Empty formula', 0);
    }
    const node = this.parseExpression();
    if (!this.atEnd()) {
      throw new ParseError(`Unexpected '${this.describe(this.peek())}' after expression`, this.peek().pos);
    }
    return node;
  }

  parseExpression() {
    return this.parseTernary();
  }

  parseTernary() {
    const cond = this.parseOr();
    if (this.isPunct('?')) {
      this.i++;
      const then = this.parseExpression();
      this.expectPunct(':');
      const alt = this.parseExpression();
      return { type: 'ternary', cond, then, alt };
    }
    return cond;
  }

  parseOr() {
    let left = this.parseAnd();
    while (this.isOp('||')) {
      this.i++;
      const right = this.parseAnd();
      left = { type: 'binary', op: '||', left, right };
    }
    return left;
  }

  parseAnd() {
    let left = this.parseComparison();
    while (this.isOp('&&')) {
      this.i++;
      const right = this.parseComparison();
      left = { type: 'binary', op: '&&', left, right };
    }
    return left;
  }

  parseComparison() {
    let left = this.parseConcat();
    const cmp = ['=', '==', '!=', '<>', '<', '<=', '>', '>='];
    while (this.peek().type === TT.OP && cmp.includes(this.peek().value)) {
      const op = this.next().value;
      const right = this.parseConcat();
      left = { type: 'binary', op, left, right };
    }
    return left;
  }

  parseConcat() {
    let left = this.parseAdditive();
    while (this.isOp('&')) {
      this.i++;
      const right = this.parseAdditive();
      left = { type: 'binary', op: '&', left, right };
    }
    return left;
  }

  parseAdditive() {
    let left = this.parseMultiplicative();
    while (this.isOp('+') || this.isOp('-')) {
      const op = this.next().value;
      const right = this.parseMultiplicative();
      left = { type: 'binary', op, left, right };
    }
    return left;
  }

  parseMultiplicative() {
    let left = this.parseExponent();
    while (this.isOp('*') || this.isOp('/') || this.isOp('%')) {
      const op = this.next().value;
      const right = this.parseExponent();
      left = { type: 'binary', op, left, right };
    }
    return left;
  }

  parseExponent() {
    const left = this.parseUnary();
    if (this.isOp('^')) {
      this.i++;
      const right = this.parseExponent(); // right-associative
      return { type: 'binary', op: '^', left, right };
    }
    return left;
  }

  parseUnary() {
    if (this.isOp('-') || this.isOp('+') || this.isOp('!')) {
      const op = this.next().value;
      const operand = this.parseUnary();
      return { type: 'unary', op, operand };
    }
    return this.parsePrimary();
  }

  parsePrimary() {
    const t = this.peek();

    switch (t.type) {
      case TT.NUMBER:
        this.i++;
        return { type: 'number', value: t.value };
      case TT.STRING:
        this.i++;
        return { type: 'string', value: t.value };
      case TT.BOOL:
        this.i++;
        return { type: 'bool', value: t.value };
      case TT.NULL:
        this.i++;
        return { type: 'null' };
      case TT.FIELD:
        this.i++;
        return { type: 'field', name: t.value };
      case TT.IDENT: {
        this.i++;
        // Function call if followed by '('
        if (this.isPunct('(')) {
          const args = this.parseArgList('(', ')');
          return { type: 'call', name: t.value, args };
        }
        // Bare name: variable (let/lets) or field reference, resolved at eval.
        return { type: 'name', name: t.value };
      }
      case TT.PUNCT:
        if (t.value === '(') {
          this.i++;
          const expr = this.parseExpression();
          this.expectPunct(')');
          return expr;
        }
        if (t.value === '[') {
          const elements = this.parseArgList('[', ']');
          return { type: 'array', elements };
        }
        break;
      default:
        break;
    }
    throw new ParseError(`Unexpected '${this.describe(t)}'`, t.pos);
  }

  parseArgList(open, close) {
    this.expectPunct(open);
    const args = [];
    if (this.isPunct(close)) {
      this.i++;
      return args;
    }
    args.push(this.parseExpression());
    while (this.isPunct(',')) {
      this.i++;
      // Allow trailing comma tolerance: if next is close, stop.
      if (this.isPunct(close)) break;
      args.push(this.parseExpression());
    }
    this.expectPunct(close);
    return args;
  }
}

/**
 * Parse formula source into an AST.
 * @param {string} source
 * @param {object} [opts]
 * @param {number} [opts.maxNodes] AST node count cap (default 10_000)
 * @returns {object} AST root node
 * @throws {ParseError|TokenizeError}
 */
export function parse(source, opts = {}) {
  if (typeof source !== 'string') {
    throw new ParseError('Formula source must be a string', 0);
  }
  const tokens = tokenize(source);
  const maxNodes = opts.maxNodes ?? 10_000;
  let nodeCount = 0;
  const parser = new Parser(tokens);
  // Wrap every AST-producing method call with a node counter so even a
  // deeply-nested expression is halted before it saturates the evaluator.
  const original = parser.parse.bind(parser);
  parser.parse = function () {
    nodeCount++;
    if (nodeCount > maxNodes) {
      throw new ParseError('Formula exceeds maximum complexity', 0, COMPLEXITY_REFUSED);
    }
    return original();
  };
  // The counter above is approximate (it counts top-level `parse()` calls, not
  // every AST node). A full node walk before returning is the precise check.
  const ast = parser.parse();
  let counted = 0;
  const countNodes = (node) => {
    if (!node || typeof node !== 'object') return;
    counted++;
    if (counted > maxNodes) {
      throw new ParseError('Formula exceeds maximum complexity', 0, COMPLEXITY_REFUSED);
    }
    for (const key of Object.keys(node)) {
      const child = node[key];
      if (Array.isArray(child)) child.forEach(countNodes);
      else if (child && typeof child === 'object') countNodes(child);
    }
  };
  countNodes(ast);
  return ast;
}

/**
 * Collect the set of `{Field}` / bare-name references in an AST (used for
 * dependency tracking and cycle detection). Returns an array of unique names.
 */
export function collectReferences(ast) {
  const names = new Set();
  const walk = (node) => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'field' || node.type === 'name') {
      names.add(node.name);
    }
    for (const key of Object.keys(node)) {
      const child = node[key];
      if (Array.isArray(child)) child.forEach(walk);
      else if (child && typeof child === 'object') walk(child);
    }
  };
  walk(ast);
  return [...names];
}

export { TokenizeError };
