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
  // Rounding where truncation and expansion mean towards negative and positive infinity (used on epoch nanoseconds).
  function roundAsIfPositive(n, increment, mode) {
    switch (mode) {
      case 'trunc': mode = 'floor'; break;
      case 'expand': mode = 'ceil'; break;
      case 'halfTrunc': mode = 'halfFloor'; break;
      case 'halfExpand': mode = 'halfCeil'; break;
    }
    return roundDiv(n, increment, mode) * increment;
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

