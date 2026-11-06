/**
 * Lookup functions (docs/formulas.md:149-154).
 *
 * Operate over array values (multi-select cells, lookup results, array
 * literals). Cross-table Formula Queries (GetRecords/GetFieldValues) belong to
 * the relationship layer and resolve through the injected context in reference.js.
 */

import { isError, naError, valueError } from './errors.js';
import { toNumber, looseEquals, compareValues, isBlank } from './values.js';

const CATEGORY = 'lookup';

function toArray(v) {
  if (Array.isArray(v)) return v;
  if (isBlank(v)) return [];
  return [v];
}

const lookup = {
  CHOOSE: {
    category: CATEGORY,
    minArgs: 2,
    fn: (args) => {
      const idx = toNumber(args[0]);
      if (isError(idx)) return idx;
      const i = Math.trunc(idx);
      if (i < 1 || i > args.length - 1) return valueError('CHOOSE index out of range');
      return args[i];
    },
  },
  INDEX: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const arr = toArray(args[0]);
      const pos = toNumber(args[1]);
      if (isError(pos)) return pos;
      const i = Math.trunc(pos);
      if (i < 1 || i > arr.length) return naError('INDEX position out of range');
      return arr[i - 1];
    },
  },
  MATCH: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const target = args[0];
      const arr = toArray(args[1]);
      const type = args.length > 2 ? Math.trunc(toNumber(args[2]) ?? 0) : 0;
      if (type === 0) {
        for (let i = 0; i < arr.length; i++) {
          if (looseEquals(arr[i], target)) return i + 1;
        }
        return naError('MATCH found no exact match');
      }
      // type 1: largest value <= target (array ascending);
      // type -1: smallest value >= target (array descending).
      let best = -1;
      for (let i = 0; i < arr.length; i++) {
        const c = compareValues(arr[i], target);
        if (isError(c)) return c;
        if (type === 1 && c <= 0) best = i;
        if (type === -1 && c >= 0) best = i;
      }
      return best === -1 ? naError('MATCH found no match') : best + 1;
    },
  },
  LOOKUP: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const target = args[0];
      const source = toArray(args[1]);
      const result = args.length > 2 ? toArray(args[2]) : source;
      for (let i = 0; i < source.length; i++) {
        if (looseEquals(source[i], target)) return result[i] ?? naError('LOOKUP result missing');
      }
      return naError('LOOKUP found no match');
    },
  },
  OFFSET: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args) => {
      const arr = toArray(args[0]);
      const offset = toNumber(args[1]);
      if (isError(offset)) return offset;
      const start = Math.trunc(offset ?? 0);
      if (args.length > 2) {
        const count = Math.trunc(toNumber(args[2]) ?? 1);
        return arr.slice(start, start + count);
      }
      if (start < 0 || start >= arr.length) return naError('OFFSET out of range');
      return arr[start];
    },
  },
};

export default lookup;
