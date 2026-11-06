/**
 * Tokenizer for the formula language.
 *
 * Locale-invariant source (REQ non-functional i18n): `,` is always the argument
 * separator and `.` the decimal point, regardless of the viewer's locale.
 *
 * Tokens:
 *   NUMBER  STRING  BOOL  NULL  IDENT  FIELD  OP  PUNCT  EOF
 *
 * `{Field Name}` is lexed as one FIELD token carrying the inner name (so names
 * may contain spaces and punctuation). `//` starts a line comment, stripped
 * from the token stream but the parser preserves the raw source separately.
 *
 * Dependency-free.
 */

import { genericError } from './errors.js';

export const TT = {
  NUMBER: 'NUMBER',
  STRING: 'STRING',
  BOOL: 'BOOL',
  NULL: 'NULL',
  IDENT: 'IDENT',
  FIELD: 'FIELD',
  OP: 'OP',
  PUNCT: 'PUNCT',
  EOF: 'EOF',
};

/** Thrown for lexical errors; the public API converts it to a FormulaError. */
export class TokenizeError extends Error {}

const isDigit = (c) => c >= '0' && c <= '9';
const isIdentStart = (c) => /[A-Za-z_$]/.test(c);
const isIdentPart = (c) => /[A-Za-z0-9_$.]/.test(c);

// Multi-char operators must be tried before single-char ones.
const MULTI_OPS = ['<>', '<=', '>=', '==', '!=', '&&', '||'];
const SINGLE_OPS = ['+', '-', '*', '/', '%', '^', '&', '=', '<', '>', '!'];
const PUNCT = ['(', ')', ',', '[', ']', '?', ':'];

/**
 * @param {string} src formula source text
 * @returns {{type:string, value:*, pos:number}[]} tokens ending with EOF
 */
export function tokenize(src) {
  const tokens = [];
  let i = 0;
  const n = src.length;

  const push = (type, value, pos) => tokens.push({ type, value, pos });

  while (i < n) {
    const c = src[i];

    // Whitespace
    if (c === ' ' || c === '\t' || c === '\r' || c === '\n') {
      i++;
      continue;
    }

    // Line comment `// ...`
    if (c === '/' && src[i + 1] === '/') {
      i += 2;
      while (i < n && src[i] !== '\n') i++;
      continue;
    }

    // Field reference {Field Name}
    if (c === '{') {
      const start = i;
      i++;
      let name = '';
      while (i < n && src[i] !== '}') {
        name += src[i];
        i++;
      }
      if (i >= n) throw new TokenizeError('Unterminated field reference {…}');
      i++; // consume }
      push(TT.FIELD, name.trim(), start);
      continue;
    }

    // String literal
    if (c === '"' || c === "'") {
      const quote = c;
      const start = i;
      i++;
      let str = '';
      while (i < n && src[i] !== quote) {
        if (src[i] === '\\') {
          const next = src[i + 1];
          if (next === 'n') str += '\n';
          else if (next === 't') str += '\t';
          else if (next === 'r') str += '\r';
          else if (next === '\\') str += '\\';
          else if (next === quote) str += quote;
          else str += next;
          i += 2;
          continue;
        }
        str += src[i];
        i++;
      }
      if (i >= n) throw new TokenizeError('Unterminated string literal');
      i++; // consume closing quote
      push(TT.STRING, str, start);
      continue;
    }

    // Number literal (supports .5, 1., 1e3, 1.5E-2)
    if (isDigit(c) || (c === '.' && isDigit(src[i + 1]))) {
      const start = i;
      let num = '';
      while (i < n && isDigit(src[i])) num += src[i++];
      if (src[i] === '.') {
        num += src[i++];
        while (i < n && isDigit(src[i])) num += src[i++];
      }
      if (src[i] === 'e' || src[i] === 'E') {
        num += src[i++];
        if (src[i] === '+' || src[i] === '-') num += src[i++];
        while (i < n && isDigit(src[i])) num += src[i++];
      }
      push(TT.NUMBER, Number(num), start);
      continue;
    }

    // Identifier / keyword (function name or bare field reference)
    if (isIdentStart(c)) {
      const start = i;
      let id = '';
      while (i < n && isIdentPart(src[i])) id += src[i++];
      const lower = id.toLowerCase();
      if (lower === 'true') push(TT.BOOL, true, start);
      else if (lower === 'false') push(TT.BOOL, false, start);
      else if (lower === 'null') push(TT.NULL, null, start);
      // `blank` is NOT a keyword: it is the BLANK() function (Airtable parity).
      else push(TT.IDENT, id, start);
      continue;
    }

    // Multi-char operators
    const two = src.slice(i, i + 2);
    if (MULTI_OPS.includes(two)) {
      push(TT.OP, two, i);
      i += 2;
      continue;
    }

    // Single-char operators
    if (SINGLE_OPS.includes(c)) {
      push(TT.OP, c, i);
      i++;
      continue;
    }

    // Punctuation
    if (PUNCT.includes(c)) {
      push(TT.PUNCT, c, i);
      i++;
      continue;
    }

    throw new TokenizeError(`Unexpected character '${c}' at position ${i}`);
  }

  push(TT.EOF, null, i);
  return tokens;
}

export { genericError };
