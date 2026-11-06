/**
 * Financial functions (docs/formulas.md:197-205) with Excel-compatible argument
 * order and sign conventions (REQ-FORMULAENGINE-18). Validated against published
 * Excel results in the mirrored Jest suite.
 */

import { isError, numError, divZero } from './errors.js';
import { toNumber, flattenValues } from './values.js';

const CATEGORY = 'finance';

function nums(args, count) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const n = toNumber(args[i]);
    if (isError(n)) return n;
    out.push(n === null ? 0 : n);
  }
  return out;
}

const finance = {
  PMT: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 5,
    fn: (args) => {
      const v = nums(args, Math.min(args.length, 5));
      if (isError(v)) return v;
      const [rate, nper, pv, fv = 0, type = 0] = v;
      if (nper === 0) return divZero('PMT: nper is zero');
      if (rate === 0) return -(pv + fv) / nper;
      const pow = Math.pow(1 + rate, nper);
      return -(rate * (fv + pv * pow)) / ((pow - 1) * (1 + rate * type));
    },
  },
  FV: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 5,
    fn: (args) => {
      const v = nums(args, Math.min(args.length, 5));
      if (isError(v)) return v;
      const [rate, nper, pmt, pv = 0, type = 0] = v;
      if (rate === 0) return -(pv + pmt * nper);
      const pow = Math.pow(1 + rate, nper);
      return -(pv * pow + pmt * (1 + rate * type) * ((pow - 1) / rate));
    },
  },
  PV: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 5,
    fn: (args) => {
      const v = nums(args, Math.min(args.length, 5));
      if (isError(v)) return v;
      const [rate, nper, pmt, fv = 0, type = 0] = v;
      if (rate === 0) return -(fv + pmt * nper);
      const pow = Math.pow(1 + rate, nper);
      return -(fv + pmt * (1 + rate * type) * ((pow - 1) / rate)) / pow;
    },
  },
  NPV: {
    category: CATEGORY,
    minArgs: 2,
    fn: (args) => {
      const rate = toNumber(args[0]);
      if (isError(rate)) return rate;
      const values = flattenValues(args.slice(1));
      let total = 0;
      for (let i = 0; i < values.length; i++) {
        const n = toNumber(values[i]);
        if (isError(n)) return n;
        total += (n === null ? 0 : n) / Math.pow(1 + rate, i + 1);
      }
      return total;
    },
  },
  NPER: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 5,
    fn: (args) => {
      const v = nums(args, Math.min(args.length, 5));
      if (isError(v)) return v;
      const [rate, pmt, pv, fv = 0, type = 0] = v;
      if (rate === 0) {
        if (pmt === 0) return divZero('NPER: payment is zero');
        return -(pv + fv) / pmt;
      }
      const num = pmt * (1 + rate * type) - fv * rate;
      const den = pv * rate + pmt * (1 + rate * type);
      if (num / den <= 0) return numError('NPER: no solution');
      return Math.log(num / den) / Math.log(1 + rate);
    },
  },
  RATE: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 6,
    fn: (args) => {
      const v = nums(args, Math.min(args.length, 6));
      if (isError(v)) return v;
      const [nper, pmt, pv, fv = 0, type = 0, guess = 0.1] = v;
      let rate = guess;
      for (let iter = 0; iter < 100; iter++) {
        const pow = Math.pow(1 + rate, nper);
        let f;
        let df;
        if (rate === 0) {
          f = pv + pmt * nper + fv;
          df = nper * (nper - 1) * pmt * 0.5 + pv * nper;
        } else {
          f = pv * pow + pmt * (1 + rate * type) * ((pow - 1) / rate) + fv;
          const dpow = nper * Math.pow(1 + rate, nper - 1);
          df =
            pv * dpow +
            pmt * (1 + rate * type) * ((dpow * rate - (pow - 1)) / (rate * rate)) +
            pmt * type * ((pow - 1) / rate);
        }
        if (Math.abs(df) < 1e-12) break;
        const next = rate - f / df;
        if (Math.abs(next - rate) < 1e-8) return next;
        rate = next;
      }
      return numError('RATE did not converge');
    },
  },
  IRR: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args) => {
      const values = flattenValues([args[0]]).map((x) => toNumber(x));
      for (const v of values) if (isError(v)) return v;
      const flows = values.map((x) => (x === null ? 0 : x));
      let rate = args.length > 1 ? toNumber(args[1]) ?? 0.1 : 0.1;
      for (let iter = 0; iter < 200; iter++) {
        let npv = 0;
        let dnpv = 0;
        for (let i = 0; i < flows.length; i++) {
          npv += flows[i] / Math.pow(1 + rate, i);
          if (i > 0) dnpv -= (i * flows[i]) / Math.pow(1 + rate, i + 1);
        }
        if (Math.abs(dnpv) < 1e-12) break;
        const next = rate - npv / dnpv;
        if (Math.abs(next - rate) < 1e-8) return next;
        rate = next;
      }
      return numError('IRR did not converge');
    },
  },
  SLN: {
    category: CATEGORY,
    minArgs: 3,
    maxArgs: 3,
    fn: (args) => {
      const v = nums(args, 3);
      if (isError(v)) return v;
      const [cost, salvage, life] = v;
      if (life === 0) return divZero('SLN: life is zero');
      return (cost - salvage) / life;
    },
  },
};

export default finance;
