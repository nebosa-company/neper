/**
 * Logical & conditional functions (docs/formulas.md:17-28) plus the Appdor
 * originals `inrange` and `typeof` (logical.md:7,23).
 *
 * Error-handling functions (IF, IFS, IFERROR, IFNA, SWITCH, AND, OR) are lazy so
 * they can short-circuit and intercept error values (REQ-FORMULAENGINE-08).
 */

import { isError, isNA, naError, genericError } from './errors.js';
import { toBool, toNumber, toText, looseEquals, typeOf } from './values.js';

const CATEGORY = 'logical';

export default {
  IF: {
    category: CATEGORY,
    lazy: true,
    minArgs: 2,
    maxArgs: 3,
    fn: (nodes, ctx, ev, scope) => {
      const cond = ev.eval(nodes[0], scope);
      if (isError(cond)) return cond;
      if (toBool(cond)) return ev.eval(nodes[1], scope);
      return nodes.length > 2 ? ev.eval(nodes[2], scope) : false;
    },
  },

  IFS: {
    category: CATEGORY,
    lazy: true,
    minArgs: 2,
    fn: (nodes, ctx, ev, scope) => {
      // Optional trailing default when the arg count is odd.
      const hasDefault = nodes.length % 2 === 1;
      const pairEnd = hasDefault ? nodes.length - 1 : nodes.length;
      for (let i = 0; i < pairEnd; i += 2) {
        const cond = ev.eval(nodes[i], scope);
        if (isError(cond)) return cond;
        if (toBool(cond)) return ev.eval(nodes[i + 1], scope);
      }
      if (hasDefault) return ev.eval(nodes[nodes.length - 1], scope);
      return naError('No condition in IFS matched');
    },
  },

  IFERROR: {
    category: CATEGORY,
    lazy: true,
    minArgs: 2,
    maxArgs: 2,
    fn: (nodes, ctx, ev, scope) => {
      const v = ev.eval(nodes[0], scope);
      if (isError(v)) return ev.eval(nodes[1], scope);
      return v;
    },
  },

  IFNA: {
    category: CATEGORY,
    lazy: true,
    minArgs: 2,
    maxArgs: 2,
    fn: (nodes, ctx, ev, scope) => {
      const v = ev.eval(nodes[0], scope);
      if (isNA(v)) return ev.eval(nodes[1], scope);
      return v;
    },
  },

  SWITCH: {
    category: CATEGORY,
    aliases: ['CASE'],
    lazy: true,
    minArgs: 3,
    fn: (nodes, ctx, ev, scope) => {
      const subject = ev.eval(nodes[0], scope);
      if (isError(subject)) return subject;
      const rest = nodes.slice(1);
      const hasDefault = rest.length % 2 === 1;
      const pairCount = Math.floor(rest.length / 2);
      for (let i = 0; i < pairCount; i++) {
        const caseVal = ev.eval(rest[i * 2], scope);
        if (isError(caseVal)) return caseVal;
        if (looseEquals(subject, caseVal)) return ev.eval(rest[i * 2 + 1], scope);
      }
      if (hasDefault) return ev.eval(rest[rest.length - 1], scope);
      return naError('No case in SWITCH matched');
    },
  },

  AND: {
    category: CATEGORY,
    lazy: true,
    minArgs: 1,
    fn: (nodes, ctx, ev, scope) => {
      for (const node of nodes) {
        const v = ev.eval(node, scope);
        if (isError(v)) return v;
        if (!toBool(v)) return false;
      }
      return true;
    },
  },

  OR: {
    category: CATEGORY,
    lazy: true,
    minArgs: 1,
    fn: (nodes, ctx, ev, scope) => {
      for (const node of nodes) {
        const v = ev.eval(node, scope);
        if (isError(v)) return v;
        if (toBool(v)) return true;
      }
      return false;
    },
  },

  XOR: {
    category: CATEGORY,
    minArgs: 1,
    fn: (args) => {
      let trues = 0;
      for (const a of args) if (toBool(a)) trues++;
      return trues % 2 === 1;
    },
  },

  NOT: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => !toBool(args[0]),
  },

  TRUE: {
    category: CATEGORY,
    minArgs: 0,
    maxArgs: 0,
    fn: () => true,
  },

  // Airtable parity: BLANK() yields an empty (blank) value; ERROR() yields a
  // typed error value that ISERROR/IFERROR can intercept.
  BLANK: {
    category: CATEGORY,
    minArgs: 0,
    maxArgs: 0,
    fn: () => null,
  },

  ERROR: {
    category: CATEGORY,
    passErrors: true,
    minArgs: 0,
    maxArgs: 1,
    fn: (args) => genericError(args.length ? toText(args[0]) : 'Error'),
  },

  FALSE: {
    category: CATEGORY,
    minArgs: 0,
    maxArgs: 0,
    fn: () => false,
  },

  // Appdor original: inclusive range test a <= x <= b (logical.md:7).
  INRANGE: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const x = toNumber(args[0]);
      const a = toNumber(args[1]);
      const b = toNumber(args[2]);
      if (isError(x)) return x;
      if (isError(a)) return a;
      if (isError(b)) return b;
      if (x === null || a === null || b === null) return false;
      const lo = Math.min(a, b);
      const hi = Math.max(a, b);
      return x >= lo && x <= hi;
    },
  },

  // Appdor original: runtime type name (logical.md:23).
  TYPEOF: {
    category: CATEGORY,
    passErrors: true,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => typeOf(args[0]),
  },

  // --- the remaining logical names the specs list -------------------------

  /**
   * IS_SAME / UNEQUAL: loose equality, and its negation.
   *
   * Loose because a formula comparing a number column to a typed "5" means
   * yes — the strict form is `=` in the expression language, and anyone who
   * wants it has it.
   */
  IS_SAME: {
    category: CATEGORY,
    aliases: ['ISSAME'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => looseEquals(args[0], args[1]),
  },
  UNEQUAL: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => !looseEquals(args[0], args[1]),
  },
};
