  // ---------------------------------------------------------------- PlainDateTime
  var pdtSlots = slotted('PlainDateTime');
  carriers.push(pdtSlots);
  var PlainDateTimeProto;
  function wrapDateTime(dt, proto) { return wrapWith(pdtSlots, proto === undefined ? PlainDateTimeProto : proto, dt); }
  var DATETIME_NAMES = ['day', 'hour', 'microsecond', 'millisecond', 'minute', 'month', 'monthCode', 'nanosecond', 'second', 'year'];
  function checkDateTime(date, time) {
    if (!dateTimeWithinLimits(date, time)) throw new RangeErr('date-time out of range');
  }
  function dateTimeFromFields(f, overflow, cal) {
    var date = dateFromFields(f, overflow, cal);
    var time = regulateTime(mkTime(f.hour === undefined ? 0 : f.hour, f.minute === undefined ? 0 : f.minute, f.second === undefined ? 0 : f.second,
      f.millisecond === undefined ? 0 : f.millisecond, f.microsecond === undefined ? 0 : f.microsecond, f.nanosecond === undefined ? 0 : f.nanosecond), overflow);
    checkDateTime(date, time);
    return { date: date, time: time };
  }
  function dateTimeFieldsOf(dt) {
    var f = dateFieldsOf(dt.date);
    f.hour = dt.time.hour; f.minute = dt.time.minute; f.second = dt.time.second;
    f.millisecond = dt.time.millisecond; f.microsecond = dt.time.microsecond; f.nanosecond = dt.time.nanosecond;
    return f;
  }
  function toTemporalDateTime(item, options) {
    if (isObject(item)) {
      if (pdtSlots.has(item)) { getOverflow(getOptionsObject(options)); var s = pdtSlots.get(item); return { date: copyDate(s.date), time: copyTime(s.time) }; }
      if (zdtSlots.has(item)) { var z = zdtDateTime(zdtSlots.get(item)); getOverflow(getOptionsObject(options)); return z; }
      if (pdSlots.has(item)) {
        var pd = pdSlots.get(item);
        getOverflow(getOptionsObject(options));
        checkDateTime(pd, MIDNIGHT);
        return { date: copyDate(pd), time: MIDNIGHT };
      }
      var cal = getCalendarFromBag(item);
      var r = prepareFields(item, calFieldList(cal, DATETIME_NAMES));
      return dateTimeFromFields(r.fields, getOverflow(getOptionsObject(options)), cal);
    }
    if (typeof item !== 'string') throw new TypeErr('cannot convert to a Temporal.PlainDateTime');
    var rec = parseISOString(item, 'datetime');
    if (!rec.hasDate) throw new RangeErr('invalid date-time string');
    var scal = checkDateString(rec);
    var date = withCal(mkDate(rec.year, rec.month, rec.day), scal), time = mkTime(rec.hour, rec.minute, rec.second, rec.millisecond, rec.microsecond, rec.nanosecond);
    checkDateTime(date, time);
    getOverflow(getOptionsObject(options));
    return { date: date, time: time };
  }
  function addDateTimeParts(dt, d, norm, overflow) {
    var tr = addTimeNs(dt.time, norm);
    var date = addDate(dt.date, d.years, d.months, d.weeks, d.days + tr.days, overflow);
    checkDateTime(date, tr.time);
    return { date: date, time: tr.time };
  }
  function addDurationToDateTime(sign, dt, other, options) {
    var d = toTemporalDurationRecord(other);
    if (sign < 0) d = negateDuration(d);
    var overflow = getOverflow(getOptionsObject(options));
    return wrapDateTime(addDateTimeParts(dt, d, timeDurationNs(d), overflow));
  }
  function differenceTemporalDateTime(sinceOp, dt, other, options) {
    var o = toTemporalDateTime(other);
    if (calOf(dt.date) !== calOf(o.date)) throw new RangeErr('calendars must match');
    options = getOptionsObject(options);
    var st = getDifferenceSettings(sinceOp, options, 'datetime', [], 'nanosecond', 'day');
    var di = differenceWithRounding(dt, o, st.largest, st.increment, st.smallest, st.mode);
    var rec = internalToRecord(di, st.largest);
    return wrapDuration(sinceOp ? negateDuration(rec) : rec);
  }
  function roundDateTime(dt, increment, unit, mode) {
    if (unit === 'day') {
      var ns = timeToNs(dt.time);
      var up = roundDiv(Big(ns), NS_PER_DAY, mode);
      var date = withCal(balanceDate(dt.date.year, dt.date.month, dt.date.day + Num(up)), dt.date.cal);
      checkDateTime(date, MIDNIGHT);
      return { date: date, time: MIDNIGHT };
    }
    var r = roundTime(dt.time, increment, unit, mode);
    var d2 = withCal(balanceDate(dt.date.year, dt.date.month, dt.date.day + r.days), dt.date.cal);
    checkDateTime(d2, r.time);
    return { date: d2, time: r.time };
  }
  function dateTimeString(dt, precision, show) {
    return dateString(dt.date) + 'T' + timeString(dt.time, precision) + calendarAnnotation(calOf(dt.date), show);
  }

  function PlainDateTime() {
    needNew(new.target, 'PlainDateTime');
    var a = arguments;
    var y = toIntegerWithTruncation(a[0]), mo = toIntegerWithTruncation(a[1]), d = toIntegerWithTruncation(a[2]);
    var f = [0, 0, 0, 0, 0, 0];
    for (var i = 0; i < 6; i++) if (a[3 + i] !== undefined) f[i] = toIntegerWithTruncation(a[3 + i]);
    var cal = a[9];
    if (cal !== undefined) {
      if (typeof cal !== 'string') throw new TypeErr('calendar must be a string');
      cal = canonicalCalendar(cal);
    }
    if (!isValidDate(y, mo, d) || !isValidTime(f[0], f[1], f[2], f[3], f[4], f[5])) throw new RangeErr('date-time out of range');
    var date = withCal(mkDate(y, mo, d), cal), time = mkTime(f[0], f[1], f[2], f[3], f[4], f[5]);
    checkDateTime(date, time);
    return wrapDateTime({ date: date, time: time }, protoFromNewTarget(new.target, PlainDateTimeProto));
  }
  defineLen(PlainDateTime, 3);
  PlainDateTimeProto = PlainDateTime.prototype;
  installClass(PlainDateTime, 'Temporal.PlainDateTime', {
    from(item, options) {
      var r = toTemporalDateTime(item, options);
      return wrapDateTime(r);
    },
    compare(one, two) {
      var a = toTemporalDateTime(one), b = toTemporalDateTime(two);
      var c = compareDate(a.date, b.date);
      return c !== 0 ? c : compareTime(a.time, b.time);
    }
  }, mergeAccessors(accessorsFor(function (self) { return pdtSlots.get(self).date; }, DATE_GETTER_NAMES), {
    get hour() { return pdtSlots.get(this).time.hour; },
    get minute() { return pdtSlots.get(this).time.minute; },
    get second() { return pdtSlots.get(this).time.second; },
    get millisecond() { return pdtSlots.get(this).time.millisecond; },
    get microsecond() { return pdtSlots.get(this).time.microsecond; },
    get nanosecond() { return pdtSlots.get(this).time.nanosecond; }
  }), {
    with(temporalDateTimeLike, options) {
      var dt = pdtSlots.get(this);
      if (!isObject(temporalDateTimeLike)) throw new TypeErr('date-time-like must be an object');
      rejectTemporalLike(temporalDateTimeLike);
      var r = prepareFields(temporalDateTimeLike, calFieldList(dt.date.cal, DATETIME_NAMES));
      if (!r.any) throw new TypeErr('date-time-like object has no date-time properties');
      var merged = mergeFields(dateTimeFieldsOf(dt), r.fields);
      return wrapDateTime(dateTimeFromFields(merged, getOverflow(getOptionsObject(options)), dt.date.cal));
    },
    withPlainTime(plainTimeLike) {
      var dt = pdtSlots.get(this);
      var t = plainTimeLike === undefined ? MIDNIGHT : toTemporalTime(plainTimeLike);
      checkDateTime(dt.date, t);
      return wrapDateTime({ date: copyDate(dt.date), time: copyTime(t) });
    },
    withCalendar(calendar) {
      var dt = pdtSlots.get(this);
      var ncal = toCalendarId(calendar);
      return wrapDateTime({ date: withCal(mkDate(dt.date.year, dt.date.month, dt.date.day), ncal), time: copyTime(dt.time) });
    },
    add(temporalDurationLike, options) { return addDurationToDateTime(1, pdtSlots.get(this), temporalDurationLike, options); },
    subtract(temporalDurationLike, options) { return addDurationToDateTime(-1, pdtSlots.get(this), temporalDurationLike, options); },
    until(other, options) { return differenceTemporalDateTime(false, pdtSlots.get(this), other, options); },
    since(other, options) { return differenceTemporalDateTime(true, pdtSlots.get(this), other, options); },
    round(roundTo) {
      var dt = pdtSlots.get(this);
      if (roundTo === undefined) throw new TypeErr('round requires an argument');
      var increment = 1, mode = 'halfExpand', smallest;
      if (typeof roundTo === 'string') {
        var o = create(null);
        o.smallestUnit = roundTo;
        smallest = getUnitOption(o, 'smallestUnit', 'datetime', undefined);
        if (smallest !== undefined && isCalendarUnit(smallest)) throw new RangeErr('smallestUnit must be day or smaller');
      } else {
        roundTo = getOptionsObject(roundTo);
        increment = getRoundingIncrementOption(roundTo);
        mode = getRoundingModeOption(roundTo, 'halfExpand');
        smallest = getUnitOption(roundTo, 'smallestUnit', 'datetime', undefined);
        if (smallest !== undefined && isCalendarUnit(smallest)) throw new RangeErr('smallestUnit must be day or smaller');
      }
      if (smallest === undefined) throw new RangeErr('smallestUnit is required');
      if (smallest === 'day') validateRoundingIncrement(increment, 1, true);
      else validateRoundingIncrement(increment, maxIncrement(smallest), false);
      return wrapDateTime(roundDateTime(dt, increment, smallest, mode));
    },
    equals(other) {
      var dt = pdtSlots.get(this), o = toTemporalDateTime(other);
      return compareDate(dt.date, o.date) === 0 && compareTime(dt.time, o.time) === 0 && calOf(dt.date) === calOf(o.date);
    },
    toString(options) {
      var dt = pdtSlots.get(this);
      options = getOptionsObject(options);
      var show = getCalendarNameOption(options);
      var p = getSecondsPrecision(options, true);
      var r = roundDateTime(dt, p.inc, p.unit, p.mode);
      return dateTimeString(r, p.precision, show);
    },
    toJSON() { return dateTimeString(pdtSlots.get(this), 'auto', 'auto'); },
    toLocaleString() { return dateTimeString(pdtSlots.get(this), 'auto', 'auto'); },
    valueOf() { throw new TypeErr('Temporal.PlainDateTime cannot be converted to a primitive; use compare()'); },
    toZonedDateTime(temporalTimeZoneLike, options) {
      var dt = pdtSlots.get(this);
      var tz = toTimeZone(temporalTimeZoneLike);
      options = getOptionsObject(options);
      var dis = getDisambiguation(options);
      return wrapZoned(epochNsForLocal(tz, dt, dis), tz, undefined, dt.date.cal);
    },
    toPlainDate() { return wrapDate(copyDate(pdtSlots.get(this).date)); },
    toPlainTime() { return wrapTime(copyTime(pdtSlots.get(this).time)); }
  });
  defineLen(PlainDateTimeProto.withPlainTime, 0);
  defineLen(PlainDateTimeProto.toString, 0);
  defineLen(PlainDateTimeProto.toJSON, 0);
  defineLen(PlainDateTimeProto.toLocaleString, 0);
