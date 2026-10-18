  // ---------------------------------------------------------------- PlainTime
  var timeSlots = slotted('PlainTime');
    var PlainTimeProto;
  function wrapTime(t, proto) { return wrapWith(timeSlots, proto === undefined ? PlainTimeProto : proto, t); }
  var TIME_ALPHA = ['hour', 'microsecond', 'millisecond', 'minute', 'nanosecond', 'second'];
  function regulateTime(t, overflow) {
    if (overflow === 'constrain') {
      return mkTime(mathMin(mathMax(t.hour, 0), 23), mathMin(mathMax(t.minute, 0), 59), mathMin(mathMax(t.second, 0), 59),
        mathMin(mathMax(t.millisecond, 0), 999), mathMin(mathMax(t.microsecond, 0), 999), mathMin(mathMax(t.nanosecond, 0), 999));
    }
    if (!isValidTime(t.hour, t.minute, t.second, t.millisecond, t.microsecond, t.nanosecond)) throw new RangeErr('time out of range');
    return t;
  }
  // Reads the time fields of a property bag in alphabetical order; `base` supplies the defaults when given.
  function readTimeFields(bag, base) {
    var out = base === undefined ? mkTime(0, 0, 0, 0, 0, 0) : mkTime(base.hour, base.minute, base.second, base.millisecond, base.microsecond, base.nanosecond);
    var any = false;
    for (var i = 0; i < 6; i++) {
      var k = TIME_ALPHA[i], v = bag[k];
      if (v !== undefined) { any = true; out[k] = toIntegerWithTruncation(v); }
    }
    return { time: out, any: any };
  }
  function toTemporalTime(item, options) {
    if (isObject(item)) {
      if (timeSlots.has(item)) { getOverflow(getOptionsObject(options)); return copyTime(timeSlots.get(item)); }
      if (pdtSlots.has(item)) { getOverflow(getOptionsObject(options)); return copyTime(pdtSlots.get(item).time); }
      if (zdtSlots.has(item)) { getOverflow(getOptionsObject(options)); return copyTime(zdtDateTime(zdtSlots.get(item)).time); }
      var r = readTimeFields(item);
      if (!r.any) throw new TypeErr('time-like object has no time properties');
      var overflow = getOverflow(getOptionsObject(options));
      return regulateTime(r.time, overflow);
    }
    if (typeof item !== 'string') throw new TypeErr('cannot convert to a Temporal.PlainTime');
    var rec = parseISOString(item, 'time');
    if (!rec.hasTime || rec.z) throw new RangeErr('invalid time string');
    getOverflow(getOptionsObject(options));
    return mkTime(rec.hour, rec.minute, rec.second, rec.millisecond, rec.microsecond, rec.nanosecond);
  }
  function copyTime(t) { return mkTime(t.hour, t.minute, t.second, t.millisecond, t.microsecond, t.nanosecond); }
  function timeDurationNs(d) {
    return Big(d.hours) * NS.h + Big(d.minutes) * NS.min + Big(d.seconds) * NS.s + Big(d.milliseconds) * NS.ms + Big(d.microseconds) * 1000n + Big(d.nanoseconds);
  }
  function differenceTemporalTime(sinceOp, t, other, options) {
    var o = toTemporalTime(other);
    options = getOptionsObject(options);
    var st = getDifferenceSettings(sinceOp, options, 'time', [], 'nanosecond', 'hour');
    var norm = differenceTime(t, o);
    var unitNs = UNIT_NS[st.smallest] * Big(st.increment);
    norm = roundNumberToIncrement(norm, unitNs, st.mode);
    var parts = balanceTime(norm, st.largest);
    var rec = fixZeros(createDurationRecord(0, 0, 0, 0, parts.hours, parts.minutes, parts.seconds, parts.milliseconds, parts.microseconds, parts.nanoseconds));
    return wrapDuration(sinceOp ? negateDuration(rec) : rec);
  }
  function addDurationToTime(sign, t, other) {
    var d = toTemporalDurationRecord(other);
    var norm = timeDurationNs(d);
    if (sign < 0) norm = -norm;
    return wrapTime(addTimeNs(t, norm).time);
  }

  function PlainTime() {
    needNew(new.target, 'PlainTime');
    var a = arguments, f = [0, 0, 0, 0, 0, 0];
    for (var i = 0; i < 6; i++) if (a[i] !== undefined) f[i] = toIntegerWithTruncation(a[i]);
    if (!isValidTime(f[0], f[1], f[2], f[3], f[4], f[5])) throw new RangeErr('time out of range');
    return wrapTime(mkTime(f[0], f[1], f[2], f[3], f[4], f[5]), protoFromNewTarget(new.target, PlainTimeProto));
  }
  defineLen(PlainTime, 0);
  PlainTimeProto = PlainTime.prototype;
  installClass(PlainTime, 'Temporal.PlainTime', {
    from(item, options) {
      return wrapTime(toTemporalTime(item, options));
    },
    compare(one, two) {
      var a = toTemporalTime(one), b = toTemporalTime(two);
      return compareTime(a, b);
    }
  }, {
    get hour() { return timeSlots.get(this).hour; },
    get minute() { return timeSlots.get(this).minute; },
    get second() { return timeSlots.get(this).second; },
    get millisecond() { return timeSlots.get(this).millisecond; },
    get microsecond() { return timeSlots.get(this).microsecond; },
    get nanosecond() { return timeSlots.get(this).nanosecond; }
  }, {
    add(temporalDurationLike) { return addDurationToTime(1, timeSlots.get(this), temporalDurationLike); },
    subtract(temporalDurationLike) { return addDurationToTime(-1, timeSlots.get(this), temporalDurationLike); },
    with(temporalTimeLike, options) {
      var t = timeSlots.get(this);
      if (!isObject(temporalTimeLike)) throw new TypeErr('time-like must be an object');
      rejectTemporalLike(temporalTimeLike);
      var r = readTimeFields(temporalTimeLike, t);
      if (!r.any) throw new TypeErr('time-like object has no time properties');
      var overflow = getOverflow(getOptionsObject(options));
      return wrapTime(regulateTime(r.time, overflow));
    },
    until(other, options) { return differenceTemporalTime(false, timeSlots.get(this), other, options); },
    since(other, options) { return differenceTemporalTime(true, timeSlots.get(this), other, options); },
    round(roundTo) {
      var t = timeSlots.get(this);
      if (roundTo === undefined) throw new TypeErr('round requires an argument');
      var increment = 1, mode = 'halfExpand', smallest;
      if (typeof roundTo === 'string') {
        var o = create(null);
        o.smallestUnit = roundTo;
        smallest = getUnitOption(o, 'smallestUnit', 'time', undefined);
      } else {
        roundTo = getOptionsObject(roundTo);
        increment = getRoundingIncrementOption(roundTo);
        mode = getRoundingModeOption(roundTo, 'halfExpand');
        smallest = getUnitOption(roundTo, 'smallestUnit', 'time', undefined);
      }
      if (smallest === undefined) throw new RangeErr('smallestUnit is required');
      validateRoundingIncrement(increment, maxIncrement(smallest), false);
      return wrapTime(roundTime(t, increment, smallest, mode).time);
    },
    equals(other) {
      var t = timeSlots.get(this), o = toTemporalTime(other);
      return compareTime(t, o) === 0;
    },
    toString(options) {
      var t = timeSlots.get(this);
      options = getOptionsObject(options);
      var p = getSecondsPrecision(options, true);
      var r = roundTime(t, p.inc, p.unit, p.mode);
      return timeString(r.time, p.precision);
    },
    toJSON() { return timeString(timeSlots.get(this), 'auto'); },
    toLocaleString() { return timeString(timeSlots.get(this), 'auto'); },
    valueOf() { throw new TypeErr('Temporal.PlainTime cannot be converted to a primitive; use compare()'); }
  });
  defineLen(PlainTimeProto.toString, 0);
  defineLen(PlainTimeProto.toJSON, 0);
  defineLen(PlainTimeProto.toLocaleString, 0);

  // Objects of any Temporal type are refused where a calendar-less "like" bag is expected.
  var anyTemporalSlots = [];
  function rejectTemporalLike(o) {
    if (anyTemporalHas(o)) throw new TypeErr('a Temporal object is not allowed here');
    if (o.calendar !== undefined) throw new TypeErr('calendar is not allowed here');
    if (o.timeZone !== undefined) throw new TypeErr('timeZone is not allowed here');
  }
  function anyTemporalHas(o) {
    return timeSlots.has(o) || pdSlots.has(o) || pdtSlots.has(o) || pymSlots.has(o) || pmdSlots.has(o) || zdtSlots.has(o);
  }
