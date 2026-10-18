// The Temporal built-ins (ISO 8601 calendar; UTC and fixed-offset time zones), evaluated into the main realm after the prelude
// (generated into temporal.e by scripts/gen_js_prelude.py). Page scripts cannot change how they behave: intrinsics are captured up front.
(function (global) {
  'use strict';
  var apply = Reflect.apply, defineProperty = Object.defineProperty, create = Object.create, getProto = Object.getPrototypeOf;
  var TypeErr = TypeError, RangeErr = RangeError, WM = WeakMap, Big = BigInt, Num = Number, Str = String, Sym = Symbol;
  var wmGet = WM.prototype.get, wmSet = WM.prototype.set, wmHas = WM.prototype.has;
  var mathFloor = Math.floor, mathTrunc = Math.trunc, mathAbs = Math.abs, mathMax = Math.max, mathMin = Math.min;
  var isInteger = Num.isInteger, isFinite_ = Num.isFinite, isSafe = Num.isSafeInteger;
  var strSlice = Str.prototype.slice, strToUpper = Str.prototype.toUpperCase, strToLower = Str.prototype.toLowerCase;
  var strIndexOf = Str.prototype.indexOf, strCharCodeAt = Str.prototype.charCodeAt, strRepeat = Str.prototype.repeat;
  var strPadStart = Str.prototype.padStart, strStartsWith = Str.prototype.startsWith;
  var reExec = RegExp.prototype.exec;
  var arrPush = Array.prototype.push;
  var symTag = Sym.toStringTag, symToPrim = Sym.toPrimitive;

  function define(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: false, configurable: true }); }
  function isObject(v) { return (typeof v === 'object' && v !== null) || typeof v === 'function'; }
  function tag(proto, name) { defineProperty(proto, symTag, { value: name, writable: false, enumerable: false, configurable: true }); }
  function exec(re, s) { re.lastIndex = 0; return apply(reExec, re, [s]); }
  function sliceS(s, a, b) { return apply(strSlice, s, [a, b]); }
  function upper(s) { return apply(strToUpper, s, []); }
  function lower(s) { return apply(strToLower, s, []); }
  function pad(s, n) { return apply(strPadStart, s, [n, '0']); }
  function repeat(s, n) { return apply(strRepeat, s, [n]); }
  function startsWith(s, p) { return apply(strStartsWith, s, [p]); }
  function toStr(v) { if (typeof v === 'symbol') throw new TypeErr('cannot convert a Symbol to a string'); return Str(v); }
  function defineLen(f, n) { defineProperty(f, 'length', { value: n, writable: false, enumerable: false, configurable: true }); return f; }
  function lock(C) { defineProperty(C, 'prototype', { writable: false, enumerable: false, configurable: false }); }

  var NS = { ms: 1000000n, s: 1000000000n, min: 60000000000n, h: 3600000000000n, d: 86400000000000n };
  var NS_PER_DAY = 86400000000000n;

  // ---------------------------------------------------------------- slots
  function slotted(name) {
    var map = new WM();
    return {
      set: function (o, v) { apply(wmSet, map, [o, v]); },
      get: function (o) {
        if (!isObject(o) || !apply(wmHas, map, [o])) throw new TypeErr('not a Temporal.' + name);
        return apply(wmGet, map, [o]);
      },
      has: function (o) { return isObject(o) && apply(wmHas, map, [o]); }
    };
  }

  // ---------------------------------------------------------------- numbers
  function toIntegerIfIntegral(v) {
    var n = +v;
    if (n !== n || n === Infinity || n === -Infinity) throw new RangeErr('value must be a finite number');
    if (!isInteger(n)) throw new RangeErr('value must be an integer');
    return n === 0 ? 0 : n;
  }
  function toIntegerWithTruncation(v) {
    var n = +v;
    if (n !== n || n === Infinity || n === -Infinity) throw new RangeErr('value must be a finite number');
    n = mathTrunc(n);
    return n === 0 ? 0 : n;
  }
  function toPositiveInteger(v) {
    var n = toIntegerWithTruncation(v);
    if (n <= 0) throw new RangeErr('value must be positive');
    return n;
  }
  function absBig(n) { return n < 0n ? -n : n; }
  function signOf(n) { return n > 0 ? 1 : n < 0 ? -1 : 0; }

  // The integer nearest n/d under a rounding mode (d > 0). Mode names are the Temporal ones.
  function roundDiv(n, d, mode) {
    var q = n / d, r = n % d;
    if (r === 0n) return q;
    var neg = n < 0n, twice = absBig(r) * 2n, cmp = twice < d ? -1 : twice > d ? 1 : 0;
    var away = neg ? q - 1n : q + 1n;
    switch (mode) {
      case 'ceil': return neg ? q : away;
      case 'floor': return neg ? away : q;
      case 'expand': return away;
      case 'trunc': return q;
      case 'halfCeil': return cmp < 0 ? q : cmp > 0 ? away : (neg ? q : away);
      case 'halfFloor': return cmp < 0 ? q : cmp > 0 ? away : (neg ? away : q);
      case 'halfExpand': return cmp < 0 ? q : away;
      case 'halfTrunc': return cmp <= 0 ? q : away;
      default: return cmp < 0 ? q : cmp > 0 ? away : (q % 2n === 0n ? q : away);
    }
  }
  function roundNumberToIncrement(x, increment, mode) {
    return roundDiv(x, increment, mode) * increment;
  }
  // The Number nearest n/d, exactly (n a BigInt, d a positive BigInt).
  function divToNumber(n, d) {
    if (n % d === 0n) return Num(n / d);
    var neg = n < 0n;
    var a = absBig(n) << 100n;
    var q = a / d, sticky = a % d !== 0n;
    var r = Num(q * 2n + (sticky ? 1n : 0n)) / 2535301200456458802993406410752; // 2^101
    return neg ? -r : r;
  }
  var NEG_ZERO_FIX = function (n) { return n === 0 ? 0 : n; };

  // ---------------------------------------------------------------- options
  function getOptionsObject(options) {
    if (options === undefined) return create(null);
    if (isObject(options)) return options;
    throw new TypeErr('options must be an object');
  }
  function getStringOption(options, name, allowed, dflt) {
    var v = options[name];
    if (v === undefined) return dflt;
    v = toStr(v);
    for (var i = 0; i < allowed.length; i++) if (allowed[i] === v) return v;
    throw new RangeErr(name + ' is not a valid value: ' + v);
  }
  var ROUNDING_MODES = ['ceil', 'floor', 'expand', 'trunc', 'halfCeil', 'halfFloor', 'halfExpand', 'halfTrunc', 'halfEven'];
  function getRoundingModeOption(options, dflt) { return getStringOption(options, 'roundingMode', ROUNDING_MODES, dflt); }
  function getRoundingIncrementOption(options) {
    var v = options.roundingIncrement;
    if (v === undefined) return 1;
    var n = toIntegerWithTruncation(v);
    if (n < 1 || n > 1e9) throw new RangeErr('roundingIncrement out of range');
    return n;
  }
  function validateRoundingIncrement(increment, maximum, inclusive) {
    var m = inclusive ? maximum : maximum - 1;
    if (increment > m) throw new RangeErr('roundingIncrement out of range');
    if (maximum % increment !== 0) throw new RangeErr('roundingIncrement does not divide evenly');
  }

  var UNITS = ['year', 'month', 'week', 'day', 'hour', 'minute', 'second', 'millisecond', 'microsecond', 'nanosecond'];
  var PLURAL = { years: 'year', months: 'month', weeks: 'week', days: 'day', hours: 'hour', minutes: 'minute', seconds: 'second',
    milliseconds: 'millisecond', microseconds: 'microsecond', nanoseconds: 'nanosecond' };
  function unitIndex(u) { for (var i = 0; i < UNITS.length; i++) if (UNITS[i] === u) return i; return -1; }
  function isCalendarUnit(u) { var i = unitIndex(u); return i >= 0 && i <= 2; }
  function isDateUnit(u) { var i = unitIndex(u); return i >= 0 && i <= 3; }
  function larger(a, b) { return unitIndex(a) <= unitIndex(b) ? a : b; }
  // group: 'date' | 'time' | 'datetime'; extra: allowed extra string (e.g. 'auto')
  function getUnitOption(options, name, group, dflt, extra) {
    var v = options[name];
    if (v === undefined) return dflt;
    v = toStr(v);
    if (extra !== undefined && v === extra) return v;
    if (PLURAL[v] !== undefined) v = PLURAL[v];
    var i = unitIndex(v);
    if (i < 0) throw new RangeErr(name + ' is not a valid unit: ' + v);
    if (group === 'date' && i > 3) throw new RangeErr(name + ' must be a date unit');
    if (group === 'time' && i < 3 + 1) throw new RangeErr(name + ' must be a time unit');
    return v;
  }
  var UNIT_NS = { day: NS_PER_DAY, hour: NS.h, minute: NS.min, second: NS.s, millisecond: NS.ms, microsecond: 1000n, nanosecond: 1n };
  function maxIncrement(unit) {
    switch (unit) {
      case 'hour': return 24;
      case 'minute': case 'second': return 60;
      case 'millisecond': case 'microsecond': case 'nanosecond': return 1000;
      default: return undefined;
    }
  }

  // ---------------------------------------------------------------- parsing helpers
  var DIGITS = /^[0-9]+$/;
  function digitsToNum(s) { return +s; }

  // ---------------------------------------------------------------- Duration
  var durationSlots = slotted('Duration');
  var DURATION_FIELDS = ['years', 'months', 'weeks', 'days', 'hours', 'minutes', 'seconds', 'milliseconds', 'microseconds', 'nanoseconds'];
  var DURATION_ALPHA = ['days', 'hours', 'microseconds', 'milliseconds', 'minutes', 'months', 'nanoseconds', 'seconds', 'weeks', 'years'];

  function durationSign(d) {
    for (var i = 0; i < 10; i++) { var v = d[DURATION_FIELDS[i]]; if (v !== 0) return v < 0 ? -1 : 1; }
    return 0;
  }
  function timeNs(d) {
    return Big(d.days) * NS_PER_DAY + Big(d.hours) * NS.h + Big(d.minutes) * NS.min + Big(d.seconds) * NS.s +
      Big(d.milliseconds) * NS.ms + Big(d.microseconds) * 1000n + Big(d.nanoseconds);
  }
  function isValidDuration(d) {
    var sign = 0;
    for (var i = 0; i < 10; i++) {
      var v = d[DURATION_FIELDS[i]];
      if (v === Infinity || v === -Infinity || v !== v) return false;
      if (v < 0) { if (sign > 0) return false; sign = -1; } else if (v > 0) { if (sign < 0) return false; sign = 1; }
    }
    if (mathAbs(d.years) >= 4294967296 || mathAbs(d.months) >= 4294967296 || mathAbs(d.weeks) >= 4294967296) return false;
    var total = absBig(timeNs(d));
    return total < 9007199254740992000000000n;
  }
  function newDurationRecord(y, mo, w, d, h, mi, s, ms, us, ns) {
    return { years: y, months: mo, weeks: w, days: d, hours: h, minutes: mi, seconds: s, milliseconds: ms, microseconds: us, nanoseconds: ns };
  }
  function createDurationRecord(y, mo, w, d, h, mi, s, ms, us, ns) {
    var r = newDurationRecord(y, mo, w, d, h, mi, s, ms, us, ns);
    if (!isValidDuration(r)) throw new RangeErr('duration out of range');
    return r;
  }
  function protoFromNewTarget(nt, fallback) {
    var p = nt.prototype;
    return isObject(p) ? p : fallback;
  }
  var DurationProto;
  function wrapDuration(rec, proto) {
    var o = create(proto === undefined ? DurationProto : proto);
    durationSlots.set(o, rec);
    return o;
  }
  function defaultTemporalLargestUnit(d) {
    for (var i = 0; i < 10; i++) if (d[DURATION_FIELDS[i]] !== 0) return UNITS[i];
    return 'nanosecond';
  }
  function toDurationFromPartial(item) {
    var r = newDurationRecord(0, 0, 0, 0, 0, 0, 0, 0, 0, 0), any = false, given = {};
    for (var i = 0; i < 10; i++) {
      var k = DURATION_ALPHA[i], v = item[k];
      if (v !== undefined) { any = true; given[k] = true; r[k] = toIntegerIfIntegral(v); }
    }
    return { record: r, any: any, given: given };
  }
  var DURATION_RE = /^([+−-])?[Pp](?:([0-9]+)[Yy])?(?:([0-9]+)[Mm])?(?:([0-9]+)[Ww])?(?:([0-9]+)[Dd])?(?:[Tt](?:([0-9]+)(?:[.,]([0-9]{1,9}))?[Hh])?(?:([0-9]+)(?:[.,]([0-9]{1,9}))?[Mm])?(?:([0-9]+)(?:[.,]([0-9]{1,9}))?[Ss])?)?$/;
  function parseDuration(s) {
    var m = exec(DURATION_RE, s);
    if (m === null) throw new RangeErr('invalid duration string');
    var hasT = false;
    for (var i = 0; i < s.length; i++) { var c = s[i]; if (c === 'T' || c === 't') { hasT = true; break; } }
    var any = false;
    for (var j = 2; j <= 11; j++) if (m[j] !== undefined) any = true;
    if (!any) throw new RangeErr('invalid duration string');
    if (hasT && m[6] === undefined && m[8] === undefined && m[10] === undefined) throw new RangeErr('invalid duration string');
    // only the last time component may carry a fraction
    if (m[7] !== undefined && (m[8] !== undefined || m[10] !== undefined)) throw new RangeErr('invalid duration string');
    if (m[9] !== undefined && m[10] !== undefined) throw new RangeErr('invalid duration string');
    var sign = (m[1] === '-' || m[1] === '−') ? -1 : 1;
    function f(g) { return m[g] === undefined ? 0 : digitsToNum(m[g]); }
    var hours = f(6), minutes = f(8), seconds = f(10);
    var ms = 0, us = 0, ns = 0;
    function frac(str) { return str === undefined ? 0n : Big(str + repeat('0', 9 - str.length)); }
    if (m[7] !== undefined) {
      var tot = frac(m[7]) * 3600n;
      minutes = Num(tot / NS.min);
      seconds = Num((tot % NS.min) / NS.s);
      var restNs = tot % NS.s;
      ms = Num(restNs / NS.ms); us = Num((restNs / 1000n) % 1000n); ns = Num(restNs % 1000n);
    } else if (m[9] !== undefined) {
      var tot2 = frac(m[9]) * 60n;
      seconds = Num(tot2 / NS.s);
      var rest2 = tot2 % NS.s;
      ms = Num(rest2 / NS.ms); us = Num((rest2 / 1000n) % 1000n); ns = Num(rest2 % 1000n);
    } else if (m[11] !== undefined) {
      var rest3 = frac(m[11]);
      ms = Num(rest3 / NS.ms); us = Num((rest3 / 1000n) % 1000n); ns = Num(rest3 % 1000n);
    }
    var rec = newDurationRecord(sign * f(2), sign * f(3), sign * f(4), sign * f(5), sign * hours, sign * minutes, sign * seconds, sign * ms, sign * us, sign * ns);
    for (var k = 0; k < 10; k++) if (rec[DURATION_FIELDS[k]] === 0) rec[DURATION_FIELDS[k]] = 0;
    if (!isValidDuration(rec)) throw new RangeErr('duration out of range');
    return rec;
  }
  function toTemporalDurationRecord(item) {
    if (isObject(item)) {
      if (durationSlots.has(item)) return copyDuration(durationSlots.get(item));
      var p = toDurationFromPartial(item);
      if (!p.any) throw new TypeErr('duration-like object has no duration properties');
      var r = p.record;
      if (!isValidDuration(r)) throw new RangeErr('duration out of range');
      return r;
    }
    if (typeof item !== 'string') throw new TypeErr('cannot convert to a Temporal.Duration');
    return parseDuration(item);
  }
  function copyDuration(d) {
    return newDurationRecord(d.years, d.months, d.weeks, d.days, d.hours, d.minutes, d.seconds, d.milliseconds, d.microseconds, d.nanoseconds);
  }
  function negateDuration(d) {
    var r = copyDuration(d);
    for (var i = 0; i < 10; i++) { var k = DURATION_FIELDS[i]; r[k] = r[k] === 0 ? 0 : -r[k]; }
    return r;
  }
  // Distributes a nanosecond total over the time units no larger than `largest` (days included when largest is 'day').
  function balanceTime(total, largest) {
    var neg = total < 0n, t = absBig(total);
    var d = 0n, h = 0n, mi = 0n, s = 0n, ms = 0n, us = 0n, ns = 0n;
    var li = unitIndex(largest);
    if (li <= 3) { d = t / NS_PER_DAY; t = t % NS_PER_DAY; }
    if (li <= 4) { h = t / NS.h; t = t % NS.h; }
    if (li <= 5) { mi = t / NS.min; t = t % NS.min; }
    if (li <= 6) { s = t / NS.s; t = t % NS.s; }
    if (li <= 7) { ms = t / NS.ms; t = t % NS.ms; }
    if (li <= 8) { us = t / 1000n; t = t % 1000n; }
    ns = t;
    var sg = neg ? -1 : 1;
    return { days: sg * Num(d), hours: sg * Num(h), minutes: sg * Num(mi), seconds: sg * Num(s), milliseconds: sg * Num(ms), microseconds: sg * Num(us), nanoseconds: sg * Num(ns) };
  }
  function fixZeros(r) { for (var i = 0; i < 10; i++) { var k = DURATION_FIELDS[i]; if (r[k] === 0) r[k] = 0; } return r; }
  function fromTimeParts(y, mo, w, parts) {
    return fixZeros(createDurationRecord(y, mo, w, parts.days, parts.hours, parts.minutes, parts.seconds, parts.milliseconds, parts.microseconds, parts.nanoseconds));
  }

  function getRelativeTo(options) {
    var v = options.relativeTo;
    if (v === undefined) return undefined;
    throw new RangeErr('relativeTo is not supported yet');
  }

  function addDurations(a, b, sign) {
    var largest = larger(defaultTemporalLargestUnit(a), defaultTemporalLargestUnit(b));
    if (isCalendarUnit(largest)) throw new RangeErr('years, months and weeks need a relativeTo');
    var total = timeNs(a) + (sign < 0 ? -timeNs(b) : timeNs(b));
    return fromTimeParts(0, 0, 0, balanceTime(total, largest));
  }

  function durationToString(d, precision, mode) {
    var sign = durationSign(d);
    var date = '';
    function seg(v, c) { return v === 0 ? '' : absBig(Big(v)).toString() + c; }
    date = seg(d.years, 'Y') + seg(d.months, 'M') + seg(d.weeks, 'W') + seg(d.days, 'D');
    var h = d.hours, mi = d.minutes, s = d.seconds, ms = d.milliseconds, us = d.microseconds, ns = d.nanoseconds;
    var subs = absBig(Big(ms) * NS.ms + Big(us) * 1000n + Big(ns));
    var secTotalNs = absBig(Big(s) * NS.s) + subs;
    var secBig = secTotalNs / NS.s, fracNs = secTotalNs % NS.s;
    var timeOut = seg(h, 'H') + seg(mi, 'M');
    var fracStr = '';
    if (precision === 'auto') {
      if (fracNs !== 0n) {
        fracStr = pad(fracNs.toString(), 9);
        var e = fracStr.length;
        while (fracStr[e - 1] === '0') e--;
        fracStr = '.' + sliceS(fracStr, 0, e);
      }
    } else if (precision > 0) {
      fracStr = '.' + sliceS(pad(fracNs.toString(), 9), 0, precision);
    }
    var needSeconds = secBig !== 0n || fracNs !== 0n || precision !== 'auto' || (date === '' && timeOut === '');
    if (needSeconds) timeOut += secBig.toString() + fracStr + 'S';
    return (sign < 0 ? '-' : '') + 'P' + date + (timeOut === '' ? '' : 'T' + timeOut);
  }

  var Duration = (function () {
    function Duration() {
      if (new.target === undefined) throw new TypeErr('Temporal.Duration must be called with new');
      var a = arguments;
      var f = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      for (var i = 0; i < 10; i++) if (a[i] !== undefined) f[i] = toIntegerIfIntegral(a[i]);
      var rec = createDurationRecord(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9]);
      return wrapDuration(fixZeros(rec), protoFromNewTarget(new.target, DurationProto));
    }
    return Duration;
  })();
  defineProperty(Duration, 'length', { value: 0, configurable: true });
  DurationProto = Duration.prototype;
  var durationStatics = {
    from(item) {
      if (isObject(item) && durationSlots.has(item)) return wrapDuration(copyDuration(durationSlots.get(item)));
      return wrapDuration(toTemporalDurationRecord(item));
    },
    compare(one, two, options) {
      var a = toTemporalDurationRecord(one), b = toTemporalDurationRecord(two);
      options = getOptionsObject(options);
      var rel = getRelativeTo(options);
      var same = true;
      for (var i = 0; i < 10; i++) if (a[DURATION_FIELDS[i]] !== b[DURATION_FIELDS[i]]) same = false;
      if (same) return 0;
      if (rel === undefined && (a.years || a.months || a.weeks || b.years || b.months || b.weeks)) throw new RangeErr('relativeTo is required');
      var x = timeNs(a), y = timeNs(b);
      return x < y ? -1 : x > y ? 1 : 0;
    }
  };
  define(Duration, 'from', durationStatics.from);
  define(Duration, 'compare', defineLen(durationStatics.compare, 2));
  lock(Duration);

  var durationGetters = {
    get years() { return durationSlots.get(this).years; },
    get months() { return durationSlots.get(this).months; },
    get weeks() { return durationSlots.get(this).weeks; },
    get days() { return durationSlots.get(this).days; },
    get hours() { return durationSlots.get(this).hours; },
    get minutes() { return durationSlots.get(this).minutes; },
    get seconds() { return durationSlots.get(this).seconds; },
    get milliseconds() { return durationSlots.get(this).milliseconds; },
    get microseconds() { return durationSlots.get(this).microseconds; },
    get nanoseconds() { return durationSlots.get(this).nanoseconds; },
    get sign() { return durationSign(durationSlots.get(this)); },
    get blank() { return durationSign(durationSlots.get(this)) === 0; }
  };
  var gnames = ['years', 'months', 'weeks', 'days', 'hours', 'minutes', 'seconds', 'milliseconds', 'microseconds', 'nanoseconds', 'sign', 'blank'];
  for (var gi = 0; gi < gnames.length; gi++) {
    var gd = Object.getOwnPropertyDescriptor(durationGetters, gnames[gi]);
    defineProperty(DurationProto, gnames[gi], { get: gd.get, enumerable: false, configurable: true });
  }

  var durationMethods = {
    with(temporalDurationLike) {
      var cur = durationSlots.get(this);
      if (!isObject(temporalDurationLike)) throw new TypeErr('duration-like must be an object');
      var p = toDurationFromPartial(temporalDurationLike);
      if (!p.any) throw new TypeErr('duration-like object has no duration properties');
      var r = copyDuration(cur);
      for (var i = 0; i < 10; i++) { var k = DURATION_FIELDS[i]; if (p.given[k]) r[k] = p.record[k]; }
      return wrapDuration(fixZeros(createDurationRecord(r.years, r.months, r.weeks, r.days, r.hours, r.minutes, r.seconds, r.milliseconds, r.microseconds, r.nanoseconds)));
    },
    negated() { return wrapDuration(negateDuration(durationSlots.get(this))); },
    abs() {
      var d = durationSlots.get(this);
      return wrapDuration(durationSign(d) < 0 ? negateDuration(d) : copyDuration(d));
    },
    add(other) {
      var a = durationSlots.get(this);
      return wrapDuration(addDurations(a, toTemporalDurationRecord(other), 1));
    },
    subtract(other) {
      var a = durationSlots.get(this);
      return wrapDuration(addDurations(a, toTemporalDurationRecord(other), -1));
    },
    round(roundTo) {
      var d = durationSlots.get(this);
      if (roundTo === undefined) throw new TypeErr('round requires an argument');
      var largestUnit, smallestUnit, increment, mode, rel;
      if (typeof roundTo === 'string') {
        var o = create(null);
        o.smallestUnit = roundTo;
        roundTo = o;
        largestUnit = undefined;
        rel = undefined;
        increment = 1;
        mode = 'halfExpand';
        smallestUnit = getUnitOption(roundTo, 'smallestUnit', 'datetime', undefined);
      } else {
        roundTo = getOptionsObject(roundTo);
        largestUnit = getUnitOption(roundTo, 'largestUnit', 'datetime', undefined, 'auto');
        rel = getRelativeTo(roundTo);
        increment = getRoundingIncrementOption(roundTo);
        mode = getRoundingModeOption(roundTo, 'halfExpand');
        smallestUnit = getUnitOption(roundTo, 'smallestUnit', 'datetime', undefined);
      }
      if (smallestUnit === undefined && largestUnit === undefined) throw new RangeErr('smallestUnit or largestUnit is required');
      var smallestGiven = smallestUnit !== undefined;
      if (smallestUnit === undefined) smallestUnit = 'nanosecond';
      var existing = defaultTemporalLargestUnit(d);
      var defaultLargest = larger(existing, smallestUnit);
      var largestAuto = largestUnit === undefined || largestUnit === 'auto';
      if (largestAuto) largestUnit = defaultLargest;
      if (largestUnit !== defaultLargest && unitIndex(largestUnit) > unitIndex(smallestUnit)) throw new RangeErr('largestUnit must be larger than smallestUnit');
      var max = maxIncrement(smallestUnit);
      if (max !== undefined) validateRoundingIncrement(increment, max, false);
      if (increment > 1 && largestUnit !== smallestUnit && isDateUnit(smallestUnit)) throw new RangeErr('roundingIncrement needs a matching largestUnit');
      if (rel === undefined && (isCalendarUnit(largestUnit) || isCalendarUnit(smallestUnit) || d.years || d.months || d.weeks)) {
        throw new RangeErr('relativeTo is required');
      }
      var total = timeNs(d);
      var unitNs = UNIT_NS[smallestUnit];
      var inc = unitNs * Big(increment);
      var rounded = roundNumberToIncrement(total, inc, mode);
      return wrapDuration(fromTimeParts(0, 0, 0, balanceTime(rounded, largestUnit)));
    },
    total(totalOf) {
      var d = durationSlots.get(this);
      if (totalOf === undefined) throw new TypeErr('total requires an argument');
      var unit, rel;
      if (typeof totalOf === 'string') {
        var o = create(null);
        o.unit = totalOf;
        totalOf = o;
        unit = getUnitOption(totalOf, 'unit', 'datetime', undefined);
      } else {
        totalOf = getOptionsObject(totalOf);
        rel = getRelativeTo(totalOf);
        unit = getUnitOption(totalOf, 'unit', 'datetime', undefined);
      }
      if (unit === undefined) throw new RangeErr('unit is required');
      if (rel === undefined && (isCalendarUnit(unit) || d.years || d.months || d.weeks)) throw new RangeErr('relativeTo is required');
      return divToNumber(timeNs(d), UNIT_NS[unit]);
    },
    toString(options) {
      var d = durationSlots.get(this);
      options = getOptionsObject(options);
      var digits = getFractionalDigits(options);
      var mode = getRoundingModeOption(options, 'trunc');
      var smallest = getUnitOption(options, 'smallestUnit', 'time', undefined);
      if (smallest === 'hour' || smallest === 'minute') throw new RangeErr('smallestUnit must be second or smaller');
      var precision = 'auto', inc = 1n, unit = 'nanosecond';
      if (smallest !== undefined) {
        switch (smallest) {
          case 'second': precision = 0; inc = NS.s; break;
          case 'millisecond': precision = 3; inc = NS.ms; break;
          case 'microsecond': precision = 6; inc = 1000n; break;
          default: precision = 9; inc = 1n;
        }
      } else if (digits !== 'auto') {
        precision = digits;
        inc = 10n ** Big(9 - digits);
      }
      var r = d;
      if (precision !== 'auto' || inc !== 1n) {
        var timePart = timeNs(d);
        var rounded = roundNumberToIncrement(timePart, inc, mode);
        var largest = larger(defaultTemporalLargestUnit(d), 'second');
        if (isCalendarUnit(largest)) largest = 'day';
        var parts = balanceTime(rounded, largest);
        r = newDurationRecord(d.years, d.months, d.weeks, parts.days, parts.hours, parts.minutes, parts.seconds, parts.milliseconds, parts.microseconds, parts.nanoseconds);
        if (!isValidDuration(r)) throw new RangeErr('duration out of range');
      }
      return durationToString(r, precision, mode);
    },
    toJSON() { return durationToString(durationSlots.get(this), 'auto', 'trunc'); },
    toLocaleString() { return durationToString(durationSlots.get(this), 'auto', 'trunc'); },
    valueOf() { throw new TypeErr('Temporal.Duration cannot be converted to a primitive; use compare()'); }
  };
  function getFractionalDigits(options) {
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
  var dnames = ['with', 'negated', 'abs', 'add', 'subtract', 'round', 'total', 'toString', 'toJSON', 'toLocaleString', 'valueOf'];
  defineLen(durationMethods.toString, 0);
  defineLen(durationMethods.toJSON, 0);
  defineLen(durationMethods.toLocaleString, 0);
  for (var di = 0; di < dnames.length; di++) define(DurationProto, dnames[di], durationMethods[dnames[di]]);
  tag(DurationProto, 'Temporal.Duration');

  // ---------------------------------------------------------------- namespace
  var Temporal = {};
  define(Temporal, 'Duration', Duration);
  tag(Temporal, 'Temporal');
  define(global, 'Temporal', Temporal);
})(globalThis);
