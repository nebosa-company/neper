/**
 * Information functions (docs/formulas.md:182-189): type predicates and TYPE.
 *
 * All are `passErrors` so they can inspect an error argument instead of
 * propagating it — e.g. `ISNUMBER(1/0)` is `false`, not a division error, while
 * `ISERROR(1/0)` is `true` (REQ-FORMULAENGINE-09).
 */

import { isError, isNA } from './errors.js';
import { isBlank, isNumberValue, isTextValue, isBoolValue, typeCode, toDate } from './values.js';

const CATEGORY = 'information';
const unary = (fn) => ({ category: CATEGORY, passErrors: true, minArgs: 1, maxArgs: 1, fn });

export default {
  ISBLANK: unary((args) => isBlank(args[0])),
  ISNUMBER: unary((args) => isNumberValue(args[0])),
  ISTEXT: unary((args) => isTextValue(args[0])),
  ISNONTEXT: unary((args) => !isTextValue(args[0])),
  ISERROR: unary((args) => isError(args[0])),
  ISNA: unary((args) => isNA(args[0])),
  ISLOGICAL: unary((args) => isBoolValue(args[0])),
  TYPE: unary((args) => typeCode(args[0])),

  // --- the remaining information names the specs list ---------------------

  // ISNOTBLANK is not `NOT(ISBLANK())` written twice — it is registered so the
  // name AppSheet users type resolves, and so it cannot drift from ISBLANK.
  ISNOTBLANK: unary((args) => !isBlank(args[0])),

  // ISNULL is Quickbase's spelling of the same question. Registered as its own
  // entry rather than an ISBLANK alias only because the two products document
  // them separately; the implementation is deliberately the same call.
  ISNULL: unary((args) => isBlank(args[0])),

  /**
   * ISDATE: does this value name a real instant?
   *
   * A bare number is NOT a date here, even though `new Date(42)` succeeds.
   * Counting every number as a date would make ISDATE true for most of a
   * numeric column, which is the opposite of what the question is for.
   */
  ISDATE: unary((args) => {
    const v = args[0];
    if (v instanceof Date) return !Number.isNaN(v.getTime());
    if (typeof v !== 'string' || !v.trim()) return false;
    // Same reading as the engine's own coercion, so ISDATE(x) and DATEVALUE(x)
    // cannot disagree (and '7' is not a date).
    return toDate(v) instanceof Date;
  }),

  /**
   * NZ: the value, or a stand-in when it is blank. Quickbase's null-coalesce.
   *
   * The stand-in defaults to 0 because that is what NZ is for — feeding a blank
   * into arithmetic that would otherwise propagate the blank all the way out.
   */
  NZ: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      if (!isBlank(args[0])) return args[0];
      return args.length > 1 ? args[1] : 0;
    },
  },

  /** IS_SAME_TYPE: do two values belong to the same type? */
  IS_SAME_TYPE: {
    category: CATEGORY,
    aliases: ['ISSAMATYPE', 'IS_SAMA_TYPE'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => typeCode(args[0]) === typeCode(args[1]),
  },
};
