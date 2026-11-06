/**
 * Conversion functions (docs/formulas.md:142-147): text/number/date coercion and
 * date formatting. Alias families collapse onto one canonical implementation
 * each (REQ-FORMULAENGINE-02).
 */

import { isError, valueError } from './errors.js';
import { toNumber, toText, toDate, isBlank } from './values.js';
import { formatDate, parseDateWithFormat } from './datetime.js';
import { formatExcelNumber, hasDigitPlaceholder, isExcelDateFormat, excelDateFormatToMoment } from './excel-format.js';

const CATEGORY = 'convertion';

const convertion = {
  TOTEXT: {
    category: CATEGORY,
    aliases: ['TEXT', 'STR_VALUE', 'STRVALUE'],
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const v = args[0];
      if (isError(v)) return v;
      if (args.length > 1 && !isBlank(args[1])) {
        const fmt = toText(args[1]);
        if (v instanceof Date) {
          if (!isExcelDateFormat(fmt)) return formatDate(v, fmt);
          const moment = excelDateFormatToMoment(fmt);
          return moment === null ? valueError() : formatDate(v, moment);
        }
        if (typeof v === 'number' || typeof v === 'boolean' || (typeof v === 'string' && !isError(toNumber(v)) && toNumber(v) !== null)) {
          const n = toNumber(v);
          const out = hasDigitPlaceholder(fmt) ? formatExcelNumber(n, fmt) : null;
          return out === null ? valueError() : out;
        }
      }
      return isBlank(v) ? '' : toText(v);
    },
  },
  TONUMBER: {
    category: CATEGORY,
    aliases: ['VALUE', 'NUMBER', 'DECIMAL'],
    minArgs: 1,
    maxArgs: 1,
    fn: (args) => {
      const n = toNumber(args[0]);
      // VALUE of blank is 0 in spreadsheets when explicitly converting.
      return n === null ? 0 : n;
    },
  },
  TODATE: {
    category: CATEGORY,
    aliases: ['PARSEDATE'],
    minArgs: 1,
    // The second argument is the FORMAT, and it is why this used to reject
    // every Airtable base that parsed a date. `DATETIME_PARSE(text, format)`
    // maps here (src/formula/compat/dialects.js), so with `maxArgs: 1` a
    // faithfully translated formula was an arity error and its whole column
    // rendered `#VALUE!` — the translation looked right and the target could
    // not express it. Measured on a real import 2026-09-09:
    // `TODATE({Opened date}, "MM-DD-YY")`, twenty error cells.
    maxArgs: 2,
    fn: (args) => {
      if (isBlank(args[0])) return null;
      // Format-directed when given one: "09-09-26" is a real date in three
      // different orders and `toDate` picks one by guessing. A caller that
      // named the order gets it read, not guessed.
      if (!isBlank(args[1])) {
        const parsed = parseDateWithFormat(toText(args[0]), toText(args[1]));
        return parsed || valueError('TODATE could not read that text in that format');
      }
      return toDate(args[0]);
    },
  },
  DATETIME_FORMAT: {
    category: CATEGORY,
    aliases: ['FORMAT', 'DATETIMEFORMAT', 'FORMATDATE'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      if (isBlank(args[0])) return '';
      const d = toDate(args[0]);
      if (isError(d)) return d;
      if (!(d instanceof Date)) return valueError('FORMAT expects a date');
      return formatDate(d, toText(args[1]));
    },
  },
};

export default convertion;
