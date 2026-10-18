  // ---------------------------------------------------------------- shared class plumbing
  var ownNames = Object.getOwnPropertyNames, getDesc = Object.getOwnPropertyDescriptor;
  // Installs statics (data), accessors (getters on the prototype) and methods onto a constructor and its prototype.
  var fnToString = Function.prototype.toString;
  // A method's `length` counts the parameters before `options` (which is always optional).
  function autoLength(f) {
    var src = apply(fnToString, f, []);
    var open = apply(strIndexOf, src, ['(']), close = apply(strIndexOf, src, [')']);
    var inner = sliceS(src, open + 1, close), n = 0, i = 0, start = 0;
    if (inner === '') return 0;
    while (i <= inner.length) {
      if (i === inner.length || inner[i] === ',') {
        var name = sliceS(inner, start, i);
        while (name[0] === ' ') name = sliceS(name, 1);
        if (name === 'options') break;
        n++;
        start = i + 1;
      }
      i++;
    }
    return n;
  }
  function installClass(C, tagName, statics, accessors, methods) {
    var proto = C.prototype, names, i;
    names = ownNames(statics);
    for (i = 0; i < names.length; i++) define(C, names[i], defineLen(statics[names[i]], autoLength(statics[names[i]])));
    lock(C);
    names = ownNames(accessors);
    for (i = 0; i < names.length; i++) {
      var d = getDesc(accessors, names[i]);
      defineProperty(proto, names[i], { get: d.get, enumerable: false, configurable: true });
    }
    names = ownNames(methods);
    for (i = 0; i < names.length; i++) define(proto, names[i], defineLen(methods[names[i]], autoLength(methods[names[i]])));
    tag(proto, tagName);
  }
  function needNew(nt, what) { if (nt === undefined) throw new TypeErr('Temporal.' + what + ' must be called with new'); }
  function wrapWith(slots, proto, rec) { var o = create(proto); slots.set(o, rec); return o; }

  function timeString(t, precision) {
    var s = pad(Str(t.hour), 2) + ':' + pad(Str(t.minute), 2);
    if (precision === 'minute') return s;
    s += ':' + pad(Str(t.second), 2);
    var frac = pad(Str(t.millisecond), 3) + pad(Str(t.microsecond), 3) + pad(Str(t.nanosecond), 3);
    if (precision === 'auto') {
      var e = 9;
      while (e > 0 && frac[e - 1] === '0') e--;
      if (e > 0) s += '.' + sliceS(frac, 0, e);
    } else if (precision > 0) {
      s += '.' + sliceS(frac, 0, precision);
    }
    return s;
  }
  function yearString(y) {
    if (y >= 0 && y <= 9999) return pad(Str(y), 4);
    return (y < 0 ? '-' : '+') + pad(Str(mathAbs(y)), 6);
  }
  function dateString(d) { return yearString(d.year) + '-' + pad(Str(d.month), 2) + '-' + pad(Str(d.day), 2); }
  function calendarAnnotation(id, show) {
    if (show === 'never' || (show === 'auto' && id === 'iso8601')) return '';
    return '[' + (show === 'critical' ? '!' : '') + 'u-ca=' + id + ']';
  }

  function getFractionalSecondDigits(options) {
    var v = options.fractionalSecondDigits;
    if (v === undefined) return 'auto';
    if (typeof v !== 'number') {
      if (toStr(v) !== 'auto') throw new RangeErr('fractionalSecondDigits must be auto or 0-9');
      return 'auto';
    }
    if (v !== v || v === Infinity || v === -Infinity) throw new RangeErr('fractionalSecondDigits must be auto or 0-9');
    var f = mathFloor(v);
    if (f < 0 || f > 9) throw new RangeErr('fractionalSecondDigits must be auto or 0-9');
    return f;
  }
  // Reads fractionalSecondDigits, roundingMode and smallestUnit; answers the precision and the rounding to apply.
  function getSecondsPrecision(options, allowMinute, afterDigits, afterSmallest) {
    var digits = getFractionalSecondDigits(options);
    if (afterDigits !== undefined) afterDigits();
    var mode = getRoundingModeOption(options, 'trunc');
    var raw = options.smallestUnit;
    if (raw !== undefined) raw = toStr(raw);
    if (afterSmallest !== undefined) afterSmallest();
    var smallest = raw === undefined ? undefined : validateUnit(raw, 'smallestUnit', 'time');
    if (smallest === 'hour') throw new RangeErr('smallestUnit is not valid here');
    return secondsPrecisionOf(digits, smallest, mode, allowMinute);
  }
  function secondsPrecisionOf(digits, smallest, mode, allowMinute) {
    if (smallest === 'hour' || (smallest === 'minute' && !allowMinute)) throw new RangeErr('smallestUnit is not valid here');
    switch (smallest) {
      case 'minute': return { precision: 'minute', unit: 'minute', inc: 1, mode: mode };
      case 'second': return { precision: 0, unit: 'second', inc: 1, mode: mode };
      case 'millisecond': return { precision: 3, unit: 'millisecond', inc: 1, mode: mode };
      case 'microsecond': return { precision: 6, unit: 'microsecond', inc: 1, mode: mode };
      case 'nanosecond': return { precision: 9, unit: 'nanosecond', inc: 1, mode: mode };
    }
    if (digits === 'auto') return { precision: 'auto', unit: 'nanosecond', inc: 1, mode: mode };
    if (digits === 0) return { precision: 0, unit: 'second', inc: 1, mode: mode };
    if (digits <= 3) return { precision: digits, unit: 'millisecond', inc: Math.pow(10, 3 - digits), mode: mode };
    if (digits <= 6) return { precision: digits, unit: 'microsecond', inc: Math.pow(10, 6 - digits), mode: mode };
    return { precision: digits, unit: 'nanosecond', inc: Math.pow(10, 9 - digits), mode: mode };
  }
  // Rounds a clock time; answers {days, time}.
  function roundTime(t, increment, unit, mode) {
    var ns = timeToNs(t), step = Num(UNIT_NS[unit]) * increment;
    var r = Num(roundDiv(Big(ns), Big(step), mode)) * step;
    var days = mathFloor(r / NS_NUM_PER_DAY);
    return { days: days, time: timeFromNs(r - days * NS_NUM_PER_DAY) };
  }
  // Adds nanoseconds (a BigInt) to a clock time; answers {days (Number), time}.
  function addTimeNs(t, norm) {
    var total = Big(timeToNs(t)) + norm;
    var days = floorDiv(total, NS_PER_DAY), rem = floorMod(total, NS_PER_DAY);
    return { days: Num(days), time: timeFromNs(Num(rem)) };
  }
