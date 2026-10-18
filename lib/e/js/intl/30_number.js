
  // ---------------------------------------------------------------- numbers: exact decimals, rounding
  var BigI = BigInt, F64 = Float64Array, U64 = BigUint64Array;
  var f64buf = new F64(1), u64buf = new U64(f64buf.buffer);
  var TEN = 10n;
  function pow10(n) { var r = 1n; for (var i = 0; i < n; i++) r *= TEN; return r; }
  function pow5(n) { var r = 1n; for (var i = 0; i < n; i++) r *= 5n; return r; }
  function digitCount(b) { return b === 0n ? 1 : apply(strSliceLen, '' + b, []); }
  function strSliceLen() { return this.length; }
  // { kind: 'finite' | 'nan' | 'inf', neg, coeff (BigInt), exp } : value = coeff * 10^exp
  function normalizeDecimal(d) {
    if (d.kind !== 'finite') return d;
    if (d.coeff === 0n) { d.exp = 0; return d; }
    while (d.coeff % TEN === 0n) { d.coeff /= TEN; d.exp++; }
    return d;
  }
  function decimalFromNumber(x) {
    if (x !== x) return { kind: 'nan', neg: false, coeff: 0n, exp: 0 };
    var neg = x < 0 || (x === 0 && 1 / x < 0);
    if (x === Infinity || x === -Infinity) return { kind: 'inf', neg: neg, coeff: 0n, exp: 0 };
    if (neg) x = -x;
    if (x === 0) return { kind: 'finite', neg: neg, coeff: 0n, exp: 0 };
    f64buf[0] = x;
    var bits = u64buf[0], e11 = Number((bits >> 52n) & 2047n), frac = bits & 0xfffffffffffffn, m, e;
    if (e11 === 0) { m = frac; e = -1074; } else { m = frac | 0x10000000000000n; e = e11 - 1075; }
    if (e >= 0) return normalizeDecimal({ kind: 'finite', neg: neg, coeff: m << BigI(e), exp: 0 });
    return normalizeDecimal({ kind: 'finite', neg: neg, coeff: m * pow5(-e), exp: e });
  }
  var RE_DECIMAL = /^[ \t\n\r\u00a0\ufeff\u2028\u2029]*([+-]?)(?:(Infinity)|([0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE]([+-]?[0-9]+))?)[ \t\n\r\u00a0\ufeff\u2028\u2029]*$/;
  var RE_RADIX = /^[ \t\n\r\u00a0\ufeff\u2028\u2029]*(0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[bB][01]+)[ \t\n\r\u00a0\ufeff\u2028\u2029]*$/;
  var RE_BLANK = /^[ \t\n\r\u00a0\ufeff\u2028\u2029]*$/;
  function decimalFromString(s) {
    if (exec(RE_BLANK, s) !== null) return { kind: 'finite', neg: false, coeff: 0n, exp: 0 };
    var m = exec(RE_DECIMAL, s);
    if (m !== null) {
      var neg = m[1] === '-';
      if (m[2] !== undefined) return { kind: 'inf', neg: neg, coeff: 0n, exp: 0 };
      var mant = m[3], dot = indexOf(mant, '.'), exp = m[4] === undefined ? 0 : +m[4];
      if (dot >= 0) { exp -= mant.length - dot - 1; mant = sliceS(mant, 0, dot) + sliceS(mant, dot + 1); }
      return normalizeDecimal({ kind: 'finite', neg: neg, coeff: BigI(mant), exp: exp });
    }
    var r = exec(RE_RADIX, s);
    if (r !== null) return normalizeDecimal({ kind: 'finite', neg: false, coeff: BigI(r[1]), exp: 0 });
    return { kind: 'nan', neg: false, coeff: 0n, exp: 0 };
  }
  function toIntlMathematicalValue(value) {
    var prim = toPrimitiveNumber(value);
    if (typeof prim === 'bigint') return normalizeDecimal({ kind: 'finite', neg: prim < 0n, coeff: prim < 0n ? -prim : prim, exp: 0 });
    if (typeof prim === 'string') return decimalFromString(prim);
    return decimalFromNumber(typeof prim === 'number' ? prim : +prim);
  }
  function toPrimitiveNumber(value) {
    if (!isObject(value)) return value;
    var ex = value[Sym.toPrimitive];
    if (ex !== undefined && ex !== null) {
      var r = apply(ex, value, ['number']);
      if (isObject(r)) throw new TypeErr('Cannot convert object to primitive value');
      return r;
    }
    var order = ['valueOf', 'toString'];
    for (var i = 0; i < 2; i++) {
      var f = value[order[i]];
      if (typeof f === 'function') { var res = apply(f, value, []); if (!isObject(res)) return res; }
    }
    throw new TypeErr('Cannot convert object to primitive value');
  }

  // Rounds |coeff*10^exp| to a multiple of incr*10^pos under `mode`; the result is the multiple count as BigInt (in units of incr*10^pos).
  function roundUnits(coeff, exp, pos, incr, mode, neg) {
    var q, r, D;
    if (exp >= pos) { D = BigI(incr); var c = coeff * pow10(exp - pos); q = c / D; r = c % D; }
    else { D = pow10(pos - exp) * BigI(incr); q = coeff / D; r = coeff % D; }
    if (r === 0n) return q;
    var twice = r * 2n, cmp = twice < D ? -1 : twice > D ? 1 : 0, up = false;
    switch (mode) {
      case 'ceil': up = !neg; break;
      case 'floor': up = neg; break;
      case 'expand': up = true; break;
      case 'trunc': up = false; break;
      case 'halfCeil': up = cmp > 0 || (cmp === 0 && !neg); break;
      case 'halfFloor': up = cmp > 0 || (cmp === 0 && neg); break;
      case 'halfExpand': up = cmp >= 0; break;
      case 'halfTrunc': up = cmp > 0; break;
      default: up = cmp > 0 || (cmp === 0 && (q % 2n === 1n)); break;
    }
    return up ? q + 1n : q;
  }
  function magnitudeOf(d) { return d.coeff === 0n ? 0 : digitCount(d.coeff) + d.exp - 1; }

  // Rounds a finite decimal per the NumberFormat's rounding settings. Result: { coeff (BigInt), exp, mag } with value = coeff*10^exp, the
  // digits already padded to the minimums as strings in { int, frac }.
  function roundFraction(d, mnfd, mxfd, incr, mode) {
    var units = roundUnits(d.coeff, d.exp, -mxfd, incr, mode, d.neg) * BigI(incr);
    return { coeff: units, exp: -mxfd, mag: -mxfd, minFrac: mnfd };
  }
  function roundSignificant(d, mnsd, mxsd, mode) {
    var e = magnitudeOf(d), pos = e - mxsd + 1;
    var units = roundUnits(d.coeff, d.exp, pos, 1, mode, d.neg);
    // rounding up can carry into another digit (999 -> 1000): the magnitude moves with it
    var e2 = units === 0n ? e : digitCount(units) + pos - 1;
    var minFrac = mnsd - e2 - 1;
    if (minFrac < 0) minFrac = 0;
    return { coeff: units, exp: pos, mag: pos, minFrac: minFrac, sig: true, e: e2 };
  }
  function applyRounding(nf, d) {
    if (d.coeff === 0n) {
      var zero = { coeff: 0n, exp: 0, mag: 0, minFrac: nf.roundingType === 'significantDigits' ? mathMax(nf.minSig - 1, 0) : nf.minFrac };
      if (nf.roundingType === 'significantDigits') zero.minFrac = mathMax(nf.minSig - 1, 0);
      return zero;
    }
    var t = nf.roundingType, res;
    if (t === 'fractionDigits') res = roundFraction(d, nf.minFrac, nf.maxFrac, nf.roundingIncrement, nf.roundingMode);
    else if (t === 'significantDigits') res = roundSignificant(d, nf.minSig, nf.maxSig, nf.roundingMode);
    else if (t === 'compact') {
      if (magnitudeOf(d) >= 1) res = roundFraction(d, 0, 0, 1, nf.roundingMode);
      else res = roundSignificant(d, 1, 2, nf.roundingMode);
    } else {
      var s = roundSignificant(d, nf.minSig, nf.maxSig, nf.roundingMode), f = roundFraction(d, nf.minFrac, nf.maxFrac, nf.roundingIncrement, nf.roundingMode);
      if (t === 'morePrecision') res = s.mag <= f.mag ? s : f;
      else res = s.mag <= f.mag ? f : s;
    }
    return res;
  }
  // The digit strings of a rounded result.
  function digitsOf(res, nf) {
    var coeff = res.coeff, exp = res.exp, s = coeff === 0n ? '' : '' + coeff, intStr, fracStr;
    if (exp >= 0) { intStr = s === '' ? '0' : s + repeatStr('0', exp); fracStr = ''; }
    else {
      var n = -exp;
      while (s.length <= n) s = '0' + s;
      intStr = sliceS(s, 0, s.length - n); fracStr = sliceS(s, s.length - n);
    }
    var minFrac = res.minFrac;
    while (fracStr.length < minFrac) fracStr += '0';
    // strip trailing zeros beyond the minimum
    var end = fracStr.length;
    while (end > minFrac && fracStr[end - 1] === '0') end--;
    fracStr = sliceS(fracStr, 0, end);
    if (nf.trailingZeroDisplay === 'stripIfInteger') {
      var allZero = true;
      for (var i = 0; i < fracStr.length; i++) if (fracStr[i] !== '0') allZero = false;
      if (allZero) fracStr = '';
    }
    while (intStr.length < nf.minInt) intStr = '0' + intStr;
    return { int: intStr, frac: fracStr, zero: res.coeff === 0n };
  }
  function repeatStr(s, n) { return apply(String.prototype.repeat, s, [n]); }

  // ---------------------------------------------------------------- NumberFormat options
  var ROUNDING_INCREMENTS = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000];
  var ROUNDING_MODES = ['ceil', 'floor', 'expand', 'trunc', 'halfCeil', 'halfFloor', 'halfExpand', 'halfTrunc', 'halfEven'];
  function defaultNumberOption(value, minimum, maximum, fallback) {
    if (value === undefined) return fallback;
    value = +value;
    if (value !== value || value < minimum || value > maximum) throw new RangeErr('Value out of range for Intl number option');
    return mathFloor(value);
  }
  function setDigitOptions(nf, options, mnfdDefault, mxfdDefault, notation) {
    var mnid = getNumberOption(options, 'minimumIntegerDigits', 1, 21, 1);
    var mnfd = options.minimumFractionDigits, mxfd = options.maximumFractionDigits;
    var mnsd = options.minimumSignificantDigits, mxsd = options.maximumSignificantDigits;
    nf.minInt = mnid;
    var roundingIncrement = getNumberOption(options, 'roundingIncrement', 1, 5000, 1);
    if (!includes(ROUNDING_INCREMENTS, roundingIncrement)) throw new RangeErr('roundingIncrement value is out of range.');
    var roundingMode = getOption(options, 'roundingMode', 'string', ROUNDING_MODES, 'halfExpand');
    var roundingPriority = getOption(options, 'roundingPriority', 'string', ['auto', 'morePrecision', 'lessPrecision'], 'auto');
    var trailingZeroDisplay = getOption(options, 'trailingZeroDisplay', 'string', ['auto', 'stripIfInteger'], 'auto');
    if (roundingIncrement !== 1) mxfdDefault = mnfdDefault;
    nf.roundingIncrement = roundingIncrement; nf.roundingMode = roundingMode; nf.trailingZeroDisplay = trailingZeroDisplay;
    var hasSd = mnsd !== undefined || mxsd !== undefined, hasFd = mnfd !== undefined || mxfd !== undefined;
    var needSd = true, needFd = true;
    if (roundingPriority === 'auto') {
      needSd = hasSd;
      if (needSd || (!hasFd && notation === 'compact')) needFd = false;
    }
    if (needSd) {
      if (hasSd) {
        nf.minSig = defaultNumberOption(mnsd, 1, 21, 1);
        nf.maxSig = defaultNumberOption(mxsd, nf.minSig, 21, 21);
      } else { nf.minSig = 1; nf.maxSig = 21; }
    }
    if (needFd) {
      if (hasFd) {
        mnfd = defaultNumberOption(mnfd, 0, 100, undefined);
        mxfd = defaultNumberOption(mxfd, 0, 100, undefined);
        if (mnfd === undefined) mnfd = mathMin(mnfdDefault, mxfd);
        else if (mxfd === undefined) mxfd = mathMax(mxfdDefault, mnfd);
        else if (mnfd > mxfd) throw new RangeErr('maximumFractionDigits value is out of range.');
        nf.minFrac = mnfd; nf.maxFrac = mxfd;
      } else { nf.minFrac = mnfdDefault; nf.maxFrac = mxfdDefault; }
    }
    if (!needSd && !needFd) {
      nf.minFrac = 0; nf.maxFrac = 0; nf.minSig = 1; nf.maxSig = 2; nf.roundingType = 'morePrecision'; nf.compactRounding = true;
      nf.roundingType = 'compact'; nf.reportedPriority = roundingPriority;
    } else if (roundingPriority === 'morePrecision') nf.roundingType = 'morePrecision';
    else if (roundingPriority === 'lessPrecision') nf.roundingType = 'lessPrecision';
    else if (hasSd) nf.roundingType = 'significantDigits';
    else nf.roundingType = 'fractionDigits';
    nf.roundingPriority = roundingPriority;
    if (roundingIncrement !== 1) {
      if (nf.roundingType !== 'fractionDigits') throw new TypeErr('roundingIncrement requires fraction digit rounding');
      if (nf.maxFrac !== nf.minFrac) throw new RangeErr('roundingIncrement requires equal minimum and maximum fraction digits');
    }
  }

  var SANCTIONED_UNITS = ['acre', 'bit', 'byte', 'celsius', 'centimeter', 'day', 'degree', 'fahrenheit', 'fluid-ounce', 'foot', 'gallon', 'gigabit', 'gigabyte',
    'gram', 'hectare', 'hour', 'inch', 'kilobit', 'kilobyte', 'kilogram', 'kilometer', 'liter', 'megabit', 'megabyte', 'meter', 'microsecond', 'mile',
    'mile-scandinavian', 'milliliter', 'millimeter', 'millisecond', 'minute', 'month', 'nanosecond', 'ounce', 'percent', 'petabyte', 'pound', 'second',
    'stone', 'terabit', 'terabyte', 'week', 'yard', 'year'];
  function isWellFormedUnit(u) {
    if (includes(SANCTIONED_UNITS, u)) return true;
    var i = indexOf(u, '-per-');
    if (i < 0) return false;
    var a = sliceS(u, 0, i), b = sliceS(u, i + 5);
    return includes(SANCTIONED_UNITS, a) && includes(SANCTIONED_UNITS, b);
  }
  var UNIT_NAMES = {
    // [short, narrow, long singular, long plural, short plural]
    acre: ['ac', 'ac', 'acre', 'acres'], bit: ['bit', 'bit', 'bit', 'bits'], byte: ['byte', 'B', 'byte', 'bytes'], celsius: ['°C', '°C', 'degree Celsius', 'degrees Celsius'],
    centimeter: ['cm', 'cm', 'centimeter', 'centimeters'], day: ['day', 'd', 'day', 'days', 'days'], degree: ['deg', '°', 'degree', 'degrees'],
    fahrenheit: ['°F', '°', 'degree Fahrenheit', 'degrees Fahrenheit'], 'fluid-ounce': ['fl oz', 'fl oz', 'fluid ounce', 'fluid ounces'], foot: ['ft', '′', 'foot', 'feet'],
    gallon: ['gal', 'gal', 'gallon', 'gallons'], gigabit: ['Gb', 'Gb', 'gigabit', 'gigabits'], gigabyte: ['GB', 'GB', 'gigabyte', 'gigabytes'], gram: ['g', 'g', 'gram', 'grams'],
    hectare: ['ha', 'ha', 'hectare', 'hectares'], hour: ['hr', 'h', 'hour', 'hours'], inch: ['in', '″', 'inch', 'inches'], kilobit: ['kb', 'kb', 'kilobit', 'kilobits'],
    kilobyte: ['kB', 'kB', 'kilobyte', 'kilobytes'], kilogram: ['kg', 'kg', 'kilogram', 'kilograms'], kilometer: ['km', 'km', 'kilometer', 'kilometers'], liter: ['L', 'L', 'liter', 'liters'],
    megabit: ['Mb', 'Mb', 'megabit', 'megabits'], megabyte: ['MB', 'MB', 'megabyte', 'megabytes'], meter: ['m', 'm', 'meter', 'meters'], microsecond: ['μs', 'μs', 'microsecond', 'microseconds'],
    mile: ['mi', 'mi', 'mile', 'miles'], 'mile-scandinavian': ['smi', 'smi', 'mile-scandinavian', 'miles-scandinavian'], milliliter: ['mL', 'mL', 'milliliter', 'milliliters'],
    millimeter: ['mm', 'mm', 'millimeter', 'millimeters'], millisecond: ['ms', 'ms', 'millisecond', 'milliseconds'], minute: ['min', 'm', 'minute', 'minutes'], month: ['mth', 'm', 'month', 'months', 'mths'],
    nanosecond: ['ns', 'ns', 'nanosecond', 'nanoseconds'], ounce: ['oz', 'oz', 'ounce', 'ounces'], percent: ['%', '%', 'percent', 'percent'], petabyte: ['PB', 'PB', 'petabyte', 'petabytes'],
    pound: ['lb', '#', 'pound', 'pounds'], second: ['sec', 's', 'second', 'seconds'], stone: ['st', 'st', 'stone', 'stone'], terabit: ['Tb', 'Tb', 'terabit', 'terabits'],
    terabyte: ['TB', 'TB', 'terabyte', 'terabytes'], week: ['wk', 'w', 'week', 'weeks', 'wks'], yard: ['yd', 'yd', 'yard', 'yards'], year: ['yr', 'y', 'year', 'years', 'yrs']
  };
  var CURRENCY_DIGITS = { JPY: 0, KRW: 0, VND: 0, CLP: 0, ISK: 0, HUF: 2, BHD: 3, KWD: 3, OMR: 3, JOD: 3, TND: 3, IQD: 0, XAF: 0, XOF: 0, UGX: 0, PYG: 0, RWF: 0 };
  var CURRENCY_SYMBOL = { USD: '$', EUR: '€', GBP: '£', JPY: '¥', INR: '₹', KRW: '₩', CNY: 'CN¥', CAD: 'CA$', AUD: 'A$', MXN: 'MX$', BRL: 'R$', ILS: '₪', VND: '₫', NZD: 'NZ$', HKD: 'HK$', TWD: 'NT$' };
  var CURRENCY_NARROW = { USD: '$', EUR: '€', GBP: '£', JPY: '¥', INR: '₹', KRW: '₩', CNY: '¥', CAD: '$', AUD: '$', MXN: '$', BRL: 'R$', ILS: '₪', VND: '₫', NZD: '$', HKD: '$', TWD: '$', RUB: '₽' };
  var CURRENCY_NAME = { USD: ['US dollar', 'US dollars'], EUR: ['euro', 'euros'], GBP: ['British pound', 'British pounds'], JPY: ['Japanese yen', 'Japanese yen'],
    CAD: ['Canadian dollar', 'Canadian dollars'], AUD: ['Australian dollar', 'Australian dollars'], INR: ['Indian rupee', 'Indian rupees'], CNY: ['Chinese yuan', 'Chinese yuan'] };
  function currencyDigits(c) { return has(CURRENCY_DIGITS, c) ? CURRENCY_DIGITS[c] : 2; }

  var NumberFormatSlots = slotted('NumberFormat');
  var RE_CURRENCY = /^[A-Za-z]{3}$/, RE_NUMSYS = /^[a-z0-9]{3,8}(?:-[a-z0-9]{3,8})*$/i;
  var NUMBERING_SYSTEMS = ['latn'];
  function initializeNumberFormat(o, locales, options) {
    var requested = canonicalizeLocaleList(locales);
    options = coerceOptionsToObject(options);
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var numberingSystem = getOption(options, 'numberingSystem', 'string', undefined, undefined);
    if (numberingSystem !== undefined && !test(RE_NUMSYS, numberingSystem)) throw new RangeErr('Invalid numberingSystem');
    var opt = {};
    if (numberingSystem !== undefined) opt.nu = lower(numberingSystem);
    var r = resolveLocale(AVAILABLE, requested, opt, ['nu'], { nu: NUMBERING_SYSTEMS });
    var nf = { locale: r.locale, numberingSystem: r.nu, sym: numberSymbols(r.locale) };
    var style = getOption(options, 'style', 'string', ['decimal', 'percent', 'currency', 'unit'], 'decimal');
    nf.style = style;
    var currency = getOption(options, 'currency', 'string', undefined, undefined);
    if (currency !== undefined && !test(RE_CURRENCY, currency)) throw new RangeErr('Invalid currency code');
    if (style === 'currency' && currency === undefined) throw new TypeErr('Currency code is required with currency style.');
    var currencyDisplay = getOption(options, 'currencyDisplay', 'string', ['code', 'symbol', 'narrowSymbol', 'name'], 'symbol');
    var currencySign = getOption(options, 'currencySign', 'string', ['standard', 'accounting'], 'standard');
    var unit = getOption(options, 'unit', 'string', undefined, undefined);
    if (unit !== undefined && !isWellFormedUnit(unit)) throw new RangeErr('Invalid unit argument');
    if (style === 'unit' && unit === undefined) throw new TypeErr('Unit is required with unit style.');
    var unitDisplay = getOption(options, 'unitDisplay', 'string', ['short', 'narrow', 'long'], 'short');
    if (style === 'currency') { nf.currency = upper(currency); nf.currencyDisplay = currencyDisplay; nf.currencySign = currencySign; }
    if (style === 'unit') { nf.unit = unit; nf.unitDisplay = unitDisplay; }
    var notation = getOption(options, 'notation', 'string', ['standard', 'scientific', 'engineering', 'compact'], 'standard');
    nf.notation = notation;
    var mnfdDefault, mxfdDefault;
    if (style === 'currency' && notation === 'standard') { var cd = currencyDigits(nf.currency); mnfdDefault = cd; mxfdDefault = cd; }
    else { mnfdDefault = 0; mxfdDefault = style === 'percent' ? 0 : 3; }
    setDigitOptions(nf, options, mnfdDefault, mxfdDefault, notation);
    var compactDisplay = getOption(options, 'compactDisplay', 'string', ['short', 'long'], 'short');
    var defaultUseGrouping = 'auto';
    if (notation === 'compact') { nf.compactDisplay = compactDisplay; defaultUseGrouping = 'min2'; }
    var ug = options.useGrouping;
    if (ug === undefined) ug = defaultUseGrouping;
    else if (ug === true) ug = 'always';
    else if (!ug) ug = false;
    else if (ug === 'true' || ug === 'false') ug = defaultUseGrouping;
    else {
      ug = toStr(ug);
      if (ug === 'true' || ug === 'false') ug = defaultUseGrouping;
      else if (ug !== 'min2' && ug !== 'auto' && ug !== 'always') throw new RangeErr('Value ' + ug + ' out of range for Intl.NumberFormat options property useGrouping');
    }
    nf.useGrouping = ug;
    nf.signDisplay = getOption(options, 'signDisplay', 'string', ['auto', 'never', 'always', 'exceptZero', 'negative'], 'auto');
    nf.boundFormat = undefined;
    NumberFormatSlots.set(o, nf);
  }

  // ---------------------------------------------------------------- formatting to parts
  var NUM_SYM = { de: [',', '.'], es: [',', '.'], it: [',', '.'], pt: [',', '.'], nl: [',', '.'], tr: [',', '.'], id: [',', '.'], da: [',', '.'],
    fr: [',', '\u202f'], ru: [',', '\u00a0'], pl: [',', '\u00a0'], sv: [',', '\u00a0'], cs: [',', '\u00a0'], nb: [',', '\u00a0'], fi: [',', '\u00a0'],
    uk: [',', '\u00a0'], hu: [',', '\u00a0'], bg: [',', '\u00a0'], sk: [',', '\u00a0'] };
  var INDIAN_GROUPING = ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa'];
  function numberSymbols(locale) {
    var lang = languageOf(locale), sym = has(NUM_SYM, lang) ? NUM_SYM[lang] : ['.', ','];
    var indian = includes(INDIAN_GROUPING, lang) || sliceS(locale, locale.length - 3) === '-IN';
    return { dec: sym[0], grp: sym[1], indian: indian };
  }
  var COMPACT_SHORT = ['', 'K', 'M', 'B', 'T'], COMPACT_LONG = ['', ' thousand', ' million', ' billion', ' trillion'];
  function groupDigits(intStr, mode, indian) {
    if (mode === false) return [intStr];
    var n = intStr.length, min = mode === 'min2' ? 5 : 4;
    if (n < min) return [intStr];
    var groups = [], end = n;
    groups.unshift(sliceS(intStr, end - 3, end)); end -= 3;
    while (end > (indian ? 2 : 3)) { groups.unshift(sliceS(intStr, end - (indian ? 2 : 3), end)); end -= indian ? 2 : 3; }
    groups.unshift(sliceS(intStr, 0, end));
    return groups;
  }
  function signFor(nf, d, isZeroResult) {
    var neg = d.neg;
    switch (nf.signDisplay) {
      case 'never': return '';
      case 'always': return neg ? '-' : '+';
      case 'exceptZero': return isZeroResult || d.kind === 'nan' ? '' : (neg ? '-' : '+');
      case 'negative': return (neg && !isZeroResult) ? '-' : '';
      default: return neg ? '-' : '';
    }
  }
  function numberParts(nf, d) {
    var parts = [];
    var work = { kind: d.kind, neg: d.neg, coeff: d.coeff, exp: d.exp };
    var expParts = null, compactSuffix = '', body = [];
    var isZero = false;
    if (work.kind === 'nan') { body = [{ type: 'nan', value: 'NaN' }]; work.neg = false; }
    else if (work.kind === 'inf') body = [{ type: 'infinity', value: '∞' }];
    else {
      if (nf.style === 'percent') work.exp += 2;
      var res, digits, exponent = 0, compactIndex = 0;
      if (nf.notation === 'scientific' || nf.notation === 'engineering') {
        var mag = work.coeff === 0n ? 0 : magnitudeOf(work);
        exponent = nf.notation === 'engineering' ? 3 * mathFloor(mag / 3) : mag;
        var scaled = { kind: 'finite', neg: work.neg, coeff: work.coeff, exp: work.exp - exponent };
        res = applyRounding(nf, scaled);
        if (res.coeff !== 0n && digitCount(res.coeff) + res.exp - 1 >= (nf.notation === 'engineering' ? 3 : 1)) {
          // rounding carried into the next order of magnitude
          if (nf.notation === 'scientific' || digitCount(res.coeff) + res.exp - 1 >= 3) {
            exponent += nf.notation === 'engineering' ? 3 : 1;
            scaled = { kind: 'finite', neg: work.neg, coeff: work.coeff, exp: work.exp - exponent };
            res = applyRounding(nf, scaled);
          }
        }
        if (work.coeff === 0n) exponent = 0;
      } else if (nf.notation === 'compact') {
        var m2 = work.coeff === 0n ? 0 : magnitudeOf(work);
        compactIndex = m2 < 3 ? 0 : mathMin(mathFloor(m2 / 3), 4);
        var sc = { kind: 'finite', neg: work.neg, coeff: work.coeff, exp: work.exp - 3 * compactIndex };
        res = applyRounding(nf, sc);
        if (res.coeff !== 0n && digitCount(res.coeff) + res.exp - 1 >= 3 && compactIndex < 4) {
          compactIndex++;
          sc = { kind: 'finite', neg: work.neg, coeff: work.coeff, exp: work.exp - 3 * compactIndex };
          res = applyRounding(nf, sc);
        }
      } else res = applyRounding(nf, work);
      digits = digitsOf(res, nf);
      isZero = digits.zero;
      var groups = groupDigits(digits.int, nf.useGrouping, nf.sym.indian);
      for (var g = 0; g < groups.length; g++) {
        if (g > 0) push(body, { type: 'group', value: nf.sym.grp });
        push(body, { type: 'integer', value: groups[g] });
      }
      if (digits.frac !== '') { push(body, { type: 'decimal', value: nf.sym.dec }); push(body, { type: 'fraction', value: digits.frac }); }
      if (nf.notation === 'scientific' || nf.notation === 'engineering') {
        push(body, { type: 'exponentSeparator', value: 'E' });
        if (exponent < 0) push(body, { type: 'exponentMinusSign', value: '-' });
        push(body, { type: 'exponentInteger', value: '' + mathAbs(exponent) });
      } else if (nf.notation === 'compact' && compactIndex > 0) {
        if (nf.compactDisplay === 'long') { push(body, { type: 'literal', value: ' ' }); push(body, { type: 'compact', value: sliceS(COMPACT_LONG[compactIndex], 1) }); }
        else push(body, { type: 'compact', value: COMPACT_SHORT[compactIndex] });
      }
      if (digits.zero && d.neg && false) work.neg = false;
    }
    var sign = signFor(nf, work.kind === 'nan' ? { neg: false, kind: 'nan' } : { neg: d.neg, kind: work.kind }, isZero);
    var signPart = sign === '' ? null : { type: sign === '-' ? 'minusSign' : 'plusSign', value: sign };
    var plural = 'other';
    return assemble(nf, signPart, body, d, isZero);
  }
  function assemble(nf, signPart, body, d, isZero) {
    var out = [];
    function addSign() { if (signPart) push(out, signPart); }
    function addBody() { for (var i = 0; i < body.length; i++) push(out, body[i]); }
    if (nf.style === 'currency') {
      var c = nf.currency, disp = nf.currencyDisplay, sym;
      if (disp === 'code') sym = c;
      else if (disp === 'narrowSymbol') sym = has(CURRENCY_NARROW, c) ? CURRENCY_NARROW[c] : c;
      else if (disp === 'name') sym = null;
      else sym = has(CURRENCY_SYMBOL, c) ? CURRENCY_SYMBOL[c] : c;
      if (disp === 'name') {
        addSign(); addBody();
        var names = has(CURRENCY_NAME, c) ? CURRENCY_NAME[c] : [c, c];
        var one = body.length === 1 && body[0].type === 'integer' && body[0].value === '1';
        push(out, { type: 'literal', value: ' ' }); push(out, { type: 'currency', value: one ? names[0] : names[1] });
      } else if (nf.currencySign === 'accounting' && signPart && signPart.type === 'minusSign') {
        push(out, { type: 'literal', value: '(' });
        push(out, { type: 'currency', value: sym });
        if (disp === 'code' || /[A-Za-z]$/.test(sym)) push(out, { type: 'literal', value: '00a0' });
        addBody();
        push(out, { type: 'literal', value: ')' });
      } else {
        addSign();
        push(out, { type: 'currency', value: sym });
        if (disp === 'code' || (/[A-Za-z]$/.test(sym) && body.length && body[0].type !== 'nan')) push(out, { type: 'literal', value: '00a0' });
        addBody();
      }
    } else if (nf.style === 'percent') {
      addSign(); addBody(); push(out, { type: 'percentSign', value: '%' });
    } else if (nf.style === 'unit') {
      addSign(); addBody();
      var u = unitText(nf, body);
      if (u.sep !== '') push(out, { type: 'literal', value: u.sep });
      push(out, { type: 'unit', value: u.text });
    } else { addSign(); addBody(); }
    return out;
  }
  function isOne(body) {
    // English plural "one": the integer part is exactly 1 with no fraction digits
    var intStr = '', frac = '';
    for (var i = 0; i < body.length; i++) { if (body[i].type === 'integer') intStr += body[i].value; if (body[i].type === 'fraction') frac = body[i].value; }
    return intStr === '1' && frac === '';
  }
  function unitText(nf, body) {
    var u = nf.unit, per = indexOf(u, '-per-'), one = isOne(body), disp = nf.unitDisplay;
    function single(name, plural) {
      var t = UNIT_NAMES[name];
      if (disp === 'long') return plural ? t[3] : t[2];
      if (disp === 'narrow') return t[1];
      return (plural && t[4] !== undefined) ? t[4] : t[0];
    }
    var text, sep = disp === 'long' ? ' ' : (disp === 'short' ? ' ' : '');
    if (disp === 'narrow' && (u === 'bit' || u === 'byte' || u === 'day' || u === 'hour' || u === 'minute' || u === 'second' || u === 'week' || u === 'month' || u === 'year' || u === 'acre' || u === 'fluid-ounce' || u === 'gallon' || u === 'ounce' || u === 'stone' || u === 'yard' || u === 'mile-scandinavian' || u === 'hectare' || u === 'microsecond')) sep = u === 'byte' || u === 'bit' ? '' : '';
    if (u === 'percent' && disp !== 'long') sep = disp === 'short' ? '' : '';
    if (u === 'celsius' || u === 'fahrenheit') sep = disp === 'long' ? ' ' : '';
    if (per < 0) text = single(u, !one);
    else {
      var a = sliceS(u, 0, per), b = sliceS(u, per + 5);
      if (disp === 'long') text = single(a, !one) + ' per ' + UNIT_NAMES[b][2];
      else text = single(a, false) + '/' + (b === 'hour' ? 'h' : UNIT_NAMES[b][0]);
      if (disp === 'narrow') { text = UNIT_NAMES[a][1] + '/' + (b === 'hour' ? 'h' : UNIT_NAMES[b][1]); }
    }
    return { text: text, sep: sep };
  }
  function partsToString(parts) { var s = ''; for (var i = 0; i < parts.length; i++) s += parts[i].value; return s; }
  function formatNumeric(nf, x) { return numberParts(nf, toIntlMathematicalValue(x)); }

  // ---------------------------------------------------------------- NumberFormat object
  function NumberFormat() {
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var nt = new.target === undefined ? NumberFormat : new.target;
    var o = create(getPrototypeFromNewTarget(nt, NumberFormat.prototype));
    initializeNumberFormat(o, locales, options);
    return o;
  }
  function roundingMagnitudeForDigits(nf) { return nf; }
  var numberFormatMethods = {
    get format() {
      var nf = NumberFormatSlots.get(this);
      if (nf.boundFormat === undefined) {
        var f = (value) => partsToString(formatNumeric(nf, value));
        fnNamed(f, '', 1);
        nf.boundFormat = f;
      }
      return nf.boundFormat;
    },
    formatToParts(value) {
      var nf = NumberFormatSlots.get(this), parts = formatNumeric(nf, value), out = [];
      for (var i = 0; i < parts.length; i++) push(out, { type: parts[i].type, value: parts[i].value });
      return out;
    },
    formatRange(start, end) {
      var nf = NumberFormatSlots.get(this);
      if (start === undefined || end === undefined) throw new TypeErr('start and end are required');
      var res = rangeParts(nf, start, end), s = '';
      for (var i = 0; i < res.length; i++) s += res[i].value;
      return s;
    },
    formatRangeToParts(start, end) {
      var nf = NumberFormatSlots.get(this);
      if (start === undefined || end === undefined) throw new TypeErr('start and end are required');
      var res = rangeParts(nf, start, end), out = [];
      for (var i = 0; i < res.length; i++) push(out, { type: res[i].type, value: res[i].value, source: res[i].source });
      return out;
    },
    resolvedOptions() {
      var nf = NumberFormatSlots.get(this), r = { locale: nf.locale, numberingSystem: nf.numberingSystem, style: nf.style };
      if (nf.style === 'currency') { r.currency = nf.currency; r.currencyDisplay = nf.currencyDisplay; r.currencySign = nf.currencySign; }
      if (nf.style === 'unit') { r.unit = nf.unit; r.unitDisplay = nf.unitDisplay; }
      r.minimumIntegerDigits = nf.minInt;
      var t = nf.roundingType;
      if (t === 'fractionDigits' || t === 'morePrecision' || t === 'lessPrecision' || t === 'compact') {
        if (t !== 'compact' || true) { r.minimumFractionDigits = nf.minFrac; r.maximumFractionDigits = nf.maxFrac; }
      }
      if (t === 'significantDigits' || t === 'morePrecision' || t === 'lessPrecision') { r.minimumSignificantDigits = nf.minSig; r.maximumSignificantDigits = nf.maxSig; }
      if (t === 'compact') { r.minimumFractionDigits = 0; r.maximumFractionDigits = 0; r.minimumSignificantDigits = 1; r.maximumSignificantDigits = 2; }
      r.useGrouping = nf.useGrouping;
      r.notation = nf.notation;
      if (nf.notation === 'compact') r.compactDisplay = nf.compactDisplay;
      r.signDisplay = nf.signDisplay;
      r.roundingIncrement = nf.roundingIncrement;
      r.roundingMode = nf.roundingMode;
      r.roundingPriority = t === 'compact' ? nf.reportedPriority : (t === 'morePrecision' ? 'morePrecision' : t === 'lessPrecision' ? 'lessPrecision' : 'auto');
      r.trailingZeroDisplay = nf.trailingZeroDisplay;
      return r;
    }
  };
  function rangeParts(nf, start, end) {
    var x = toIntlMathematicalValue(start), y = toIntlMathematicalValue(end);
    if (x.kind === 'nan' || y.kind === 'nan') throw new RangeErr('Invalid number range');
    var xp = numberParts(nf, x), yp = numberParts(nf, y), xs = partsToString(xp), ys = partsToString(yp), out = [];
    if (xs === ys) {
      push(out, { type: 'approximatelySign', value: '~', source: 'shared' });
      for (var i = 0; i < xp.length; i++) push(out, { type: xp[i].type, value: xp[i].value, source: 'shared' });
      return out;
    }
    for (var a = 0; a < xp.length; a++) push(out, { type: xp[a].type, value: xp[a].value, source: 'startRange' });
    var spaced = false;
    for (var sp = 0; sp < xp.length; sp++) if (xp[sp].type === 'currency' || xp[sp].type === 'unit') spaced = true;
    for (var sq = 0; sq < yp.length; sq++) if (yp[sq].type === 'currency' || yp[sq].type === 'unit') spaced = true;
    push(out, { type: 'literal', value: spaced ? ' – ' : '–', source: 'shared' });
    for (var b = 0; b < yp.length; b++) push(out, { type: yp[b].type, value: yp[b].value, source: 'endRange' });
    return out;
  }
  installProto(NumberFormat, numberFormatMethods, 'Intl.NumberFormat');
  makeSupportedLocalesOf(NumberFormat, function () { return AVAILABLE; });
  define(Intl, 'NumberFormat', NumberFormat);
