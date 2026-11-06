/**
 * Array / Ranges group (docs/formulas.md:164-180) with lambda iteration
 * (REQ-FORMULAENGINE-12). Inside MAP/FILTER/REDUCE/SORT/ANY/ALL the lambda
 * expression binds `current` (the element), `index` (0-based), and — in REDUCE
 * — `accumulator`/`acc`. Notion Formulas 2.0 / Smartsheet COLLECT parity.
 *
 * MIRROR/ROLLUP/CHILDREN/ANCESTORS/GetRecords are relationship-layer functions
 * deferred to phase 2 (they depend on lookup-rollup-link-fields); they resolve
 * through the injected context when the host provides them.
 */

import { isError } from './errors.js';
import { compareValues, isBlank, looseEquals, toBool, toText } from './values.js';

const CATEGORY = 'array';

function toArray(v) {
  if (Array.isArray(v)) return v;
  if (isBlank(v)) return [];
  return [v];
}

function childScope(scope, extra) {
  const s = {};
  if (scope) for (const k of Object.keys(scope)) s[k] = scope[k];
  Object.assign(s, extra);
  return s;
}

function lambdaScope(scope, element, index, extra) {
  return childScope(scope, { current: element, value: element, index, ...(extra || {}) });
}

const array = {
  MAP: {
    category: CATEGORY,
    aliases: ['SELECT'],
    lazy: true,
    minArgs: 2,
    maxArgs: 2,
    fn: (nodes, ctx, ev, scope) => {
      const arr = ev.eval(nodes[0], scope);
      if (isError(arr)) return arr;
      const out = [];
      const items = toArray(arr);
      for (let i = 0; i < items.length; i++) {
        const v = ev.eval(nodes[1], lambdaScope(scope, items[i], i));
        if (isError(v)) return v;
        out.push(v);
      }
      return out;
    },
  },
  FILTER: {
    category: CATEGORY,
    lazy: true,
    minArgs: 2,
    maxArgs: 2,
    fn: (nodes, ctx, ev, scope) => {
      const arr = ev.eval(nodes[0], scope);
      if (isError(arr)) return arr;
      const out = [];
      const items = toArray(arr);
      for (let i = 0; i < items.length; i++) {
        const keep = ev.eval(nodes[1], lambdaScope(scope, items[i], i));
        if (isError(keep)) return keep;
        if (toBool(keep)) out.push(items[i]);
      }
      return out;
    },
  },
  REDUCE: {
    category: CATEGORY,
    lazy: true,
    minArgs: 2,
    maxArgs: 3,
    fn: (nodes, ctx, ev, scope) => {
      const arr = ev.eval(nodes[0], scope);
      if (isError(arr)) return arr;
      const items = toArray(arr);
      let acc;
      let start = 0;
      if (nodes.length > 2) {
        acc = ev.eval(nodes[2], scope);
        if (isError(acc)) return acc;
      } else {
        if (items.length === 0) return null;
        acc = items[0];
        start = 1;
      }
      const exprNode = nodes[1];
      for (let i = start; i < items.length; i++) {
        acc = ev.eval(exprNode, lambdaScope(scope, items[i], i, { accumulator: acc, acc }));
        if (isError(acc)) return acc;
      }
      return acc;
    },
  },
  SORT: {
    category: CATEGORY,
    lazy: true,
    minArgs: 1,
    maxArgs: 3,
    fn: (nodes, ctx, ev, scope) => {
      const arr = ev.eval(nodes[0], scope);
      if (isError(arr)) return arr;
      const items = toArray(arr).slice();
      let keyNode = null;
      let desc = false;
      if (nodes.length === 2 && nodes[1].type === 'bool') {
        desc = nodes[1].value;
      } else {
        if (nodes.length >= 2) keyNode = nodes[1];
        if (nodes.length >= 3) {
          const d = ev.eval(nodes[2], scope);
          if (isError(d)) return d;
          desc = toBool(d);
        }
      }
      const keyOf = (el, i) => (keyNode ? ev.eval(keyNode, lambdaScope(scope, el, i)) : el);
      const decorated = items.map((el, i) => ({ el, key: keyOf(el, i) }));
      for (const d of decorated) if (isError(d.key)) return d.key;
      decorated.sort((a, b) => {
        const c = compareValues(a.key, b.key);
        if (isError(c)) return 0;
        return desc ? -c : c;
      });
      return decorated.map((d) => d.el);
    },
  },
  ANY: {
    category: CATEGORY,
    aliases: ['SOME'],
    lazy: true,
    minArgs: 1,
    maxArgs: 2,
    fn: (nodes, ctx, ev, scope) => {
      const arr = ev.eval(nodes[0], scope);
      if (isError(arr)) return arr;
      const items = toArray(arr);
      for (let i = 0; i < items.length; i++) {
        const test = nodes.length > 1 ? ev.eval(nodes[1], lambdaScope(scope, items[i], i)) : items[i];
        if (isError(test)) return test;
        if (toBool(test)) return true;
      }
      return false;
    },
  },
  ALL: {
    category: CATEGORY,
    aliases: ['EVERY'],
    lazy: true,
    minArgs: 1,
    maxArgs: 2,
    fn: (nodes, ctx, ev, scope) => {
      const arr = ev.eval(nodes[0], scope);
      if (isError(arr)) return arr;
      const items = toArray(arr);
      for (let i = 0; i < items.length; i++) {
        const test = nodes.length > 1 ? ev.eval(nodes[1], lambdaScope(scope, items[i], i)) : items[i];
        if (isError(test)) return test;
        if (!toBool(test)) return false;
      }
      return true;
    },
  },
  JOIN: {
    category: CATEGORY,
    aliases: ['ARRAYJOIN'],
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const items = toArray(args[0]);
      const delim = args.length > 1 ? toText(args[1]) : ',';
      if (isError(delim)) return delim;
      return items.map((v) => (isBlank(v) ? '' : toText(v))).join(delim);
    },
  },
  FLAT: {
    category: CATEGORY,
    // `FLATTERN` is the spelling in the field-spec document. Registered as an
    // alias rather than corrected silently — somebody has typed it into a
    // formula, and #NAME? on a typo the product itself published is a poor
    // welcome. It flattens fully, which is what the spec's example shows.
    aliases: ['FLATTEN', 'FLATTERN'],
    minArgs: 1,
    fn: (args) => {
      const out = [];
      const walk = (v) => {
        if (Array.isArray(v)) v.forEach(walk);
        else out.push(v);
      };
      args.forEach(walk);
      return out;
    },
  },
  UNIQUE: {
    category: CATEGORY,
    aliases: ['ARRAYUNIQUE'],
    minArgs: 1,
    fn: (args) => {
      const out = [];
      const items = args.length === 1 ? toArray(args[0]) : args;
      // Keyed, so it is linear: the old out.some(looseEquals) scan was O(n^2).
      const seen = new Set();
      for (const v of items) {
        const key = uniqueKey(v);
        if (seen.has(key)) continue;
        seen.add(key);
        out.push(v);
      }
      return out;
    },
  },
  COMPACT: {
    category: CATEGORY,
    aliases: ['ARRAYCOMPACT'],
    minArgs: 1,
    fn: (args) => {
      const items = args.length === 1 ? toArray(args[0]) : args;
      return items.filter((v) => !isBlank(v) && !isError(v));
    },
  },
  // Smartsheet COLLECT(range, criteriaRange, criteria).
  COLLECT: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const range = toArray(args[0]);
      const criteriaRange = toArray(args[1]);
      const criteria = args[2];
      const match = makeMatcher(criteria);
      const out = [];
      for (let i = 0; i < range.length; i++) {
        if (match(criteriaRange[i])) out.push(range[i]);
      }
      return out;
    },
  },

  // --- the remaining array names the specs list ---------------------------

  /**
   * GET(array, n): the nth element, 1-based, negative counting from the end.
   *
   * 1-based because every other position argument in this language is — FIND,
   * MID, PART and LARGE all count from one, and a single 0-based function is a
   * trap rather than a convenience.
   */
  GET: {
    category: CATEGORY,
    aliases: ['NTH'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      const list = toArray(args[0]);
      const n = Math.trunc(Number(args[1]));
      if (!Number.isFinite(n) || n === 0) return null;
      const value = n < 0 ? list[list.length + n] : list[n - 1];
      return value === undefined ? null : value;
    },
  },
  FIRST: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const list = toArray(args[0]);
      return list.length ? list[0] : null;
    },
  },
  LAST: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const list = toArray(args[0]);
      return list.length ? list[list.length - 1] : null;
    },
  },

  /** SPLIT(text, delimiter): the inverse of JOIN. */
  SPLIT: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 3,
    fn: (args) => {
      const text = isBlank(args[0]) ? '' : toText(args[0]);
      if (isError(text)) return text;
      const delimiter = args.length > 1 && !isBlank(args[1]) ? toText(args[1]) : ',';
      if (isError(delimiter)) return delimiter;
      const parts = text.split(delimiter);
      // Trimming by default, because the delimiter people mean is "comma and
      // whatever space follows it"; pass FALSE to keep the spacing.
      const trim = args.length > 2 ? toBool(args[2]) : true;
      if (isError(trim)) return trim;
      return trim ? parts.map((p) => p.trim()) : parts;
    },
  },

  /**
   * SLICE(array, start, end): a section, 1-based and end-INCLUSIVE.
   *
   * End-inclusive because 1-based and end-exclusive together are the shape
   * nobody predicts: `SLICE(list, 2, 3)` returning one element would be read as
   * a bug every time. Negative indexes count from the end.
   */
  SLICE: {
    category: CATEGORY,
    // `ARRAYSLICE` is the spelling formula-engine documents, beside ARRAYCOMPACT,
    // ARRAYFLATTEN and ARRAYUNIQUE — all three of which already carry their ARRAY*
    // alias. The function was here; only the documented name was not, so a formula
    // copied out of the reference failed with #NAME?.
    aliases: ['ARRAYSLICE'],
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const list = toArray(args[0]);
      const at = (raw, fallback) => {
        const n = Math.trunc(Number(raw));
        if (!Number.isFinite(n) || n === 0) return fallback;
        return n < 0 ? list.length + n : n - 1;
      };
      const start = at(args[1], 0);
      const end = args.length > 2 ? at(args[2], list.length - 1) : list.length - 1;
      return list.slice(Math.max(0, start), Math.max(0, end + 1));
    },
  },
};

/** A Set key equal for exactly the values looseEquals treats as equal. */
function uniqueKey(v) {
  if (isBlank(v)) return 'blank';
  if (v instanceof Date) return `d:${v.getTime()}`;
  if (typeof v === 'boolean') return `b:${v}`;
  return `s:${String(toText(v)).toLowerCase()}`;
}

function makeMatcher(criteria) {
  if (typeof criteria === 'string') {
    const m = criteria.match(/^\s*(<=|>=|<>|!=|=|<|>)\s*(.*)$/);
    if (m) {
      const op = m[1];
      const rhsRaw = m[2];
      const rhsNum = Number(rhsRaw);
      const rhsIsNum = rhsRaw.trim() !== '' && !Number.isNaN(rhsNum);
      const rhs = rhsIsNum ? rhsNum : rhsRaw;
      return (value) => {
        if (op === '=') return looseEquals(value, rhs);
        if (op === '<>' || op === '!=') return !looseEquals(value, rhs);
        const c = compareValues(value, rhs);
        if (isError(c)) return false;
        if (op === '<') return c < 0;
        if (op === '<=') return c <= 0;
        if (op === '>') return c > 0;
        return c >= 0;
      };
    }
  }
  return (value) => looseEquals(value, criteria);
}

export default array;
