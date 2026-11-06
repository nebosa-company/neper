/**
 * Serialize an AST back to canonical formula text.
 *
 * Used by the dialect-compatibility layer to emit a canonical Neposer formula
 * after translating a competitor dialect (source text → dialect parse →
 * canonical AST → canonical text). Precedence-aware so the output re-parses to
 * the same AST; equality/inequality operators normalise to `=`/`!=`.
 *
 * Dependency-free.
 */

const PREC = {
  '||': 2,
  '&&': 3,
  '=': 4,
  '==': 4,
  '!=': 4,
  '<>': 4,
  '<': 4,
  '<=': 4,
  '>': 4,
  '>=': 4,
  '&': 5,
  '+': 6,
  '-': 6,
  '*': 7,
  '/': 7,
  '%': 7,
  '^': 8,
};

const CANON_OP = { '==': '=', '<>': '!=' };

function nodePrec(node) {
  if (!node || typeof node !== 'object') return 10;
  if (node.type === 'ternary') return 1;
  if (node.type === 'binary') return PREC[node.op] ?? 4;
  if (node.type === 'unary') return 9;
  return 10;
}

function quote(str) {
  const escaped = String(str)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n')
    .replace(/\t/g, '\\t')
    .replace(/\r/g, '\\r');
  return `"${escaped}"`;
}

/** True when a bare identifier is safe to render without `{}` braces. */
function isSimpleName(name) {
  return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name);
}

export function stringify(node) {
  if (!node || typeof node !== 'object') return '';
  switch (node.type) {
    case 'number':
      return String(node.value);
    case 'string':
      return quote(node.value);
    case 'bool':
      return node.value ? 'true' : 'false';
    case 'null':
      return 'BLANK()';
    case 'field':
      return `{${node.name}}`;
    case 'name':
      return isSimpleName(node.name) ? node.name : `{${node.name}}`;
    case 'array':
      return `[${node.elements.map(stringify).join(', ')}]`;
    case 'call':
      return `${node.name.toUpperCase()}(${node.args.map(stringify).join(', ')})`;
    case 'unary': {
      const operand = wrap(node.operand, 9, 'operand', node.op);
      return node.op === '!' ? `!${operand}` : `${node.op}${operand}`;
    }
    case 'binary': {
      const p = PREC[node.op] ?? 4;
      const op = CANON_OP[node.op] || node.op;
      const left = wrap(node.left, p, 'left', node.op);
      const right = wrap(node.right, p, 'right', node.op);
      return `${left} ${op} ${right}`;
    }
    case 'ternary': {
      const cond = node.cond.type === 'ternary' ? `(${stringify(node.cond)})` : stringify(node.cond);
      return `${cond} ? ${stringify(node.then)} : ${stringify(node.alt)}`;
    }
    default:
      return '';
  }
}

function wrap(child, parentPrec, side, parentOp) {
  const cp = nodePrec(child);
  let need = cp < parentPrec;
  if (cp === parentPrec && child.type === 'binary') {
    // Right-associative for ^, left-associative otherwise.
    need = parentOp === '^' ? side === 'left' : side === 'right';
  }
  if (child.type === 'ternary') need = true;
  const text = stringify(child);
  return need ? `(${text})` : text;
}

export default stringify;
