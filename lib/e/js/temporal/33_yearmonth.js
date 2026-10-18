  // ---------------------------------------------------------------- PlainYearMonth
  var pymSlots = slotted('PlainYearMonth');
  carriers.push(pymSlots);
  var PlainYearMonthProto;
  function wrapYearMonth(d, proto) {
    if (!yearMonthWithinLimits(d.year, d.month)) throw new RangeErr('year-month out of range');
    return wrapWith(pymSlots, proto === undefined ? PlainYearMonthProto : proto, d);
  }
  var YEARMONTH_NAMES = ['month', 'monthCode', 'year'];
  function yearMonthFromFields(f, overflow) {
    if (f.year === undefined) throw new TypeErr('year is required');
    if (f.month === undefined && f.monthCode === undefined) throw new TypeErr('month or monthCode is required');
    var month = resolveMonth(f);
    if (overflow === 'constrain') month = mathMin(mathMax(month, 1), 12);
    else if (month < 1 || month > 12) throw new RangeErr('month out of range');
    if (!yearMonthWithinLimits(f.year, month)) throw new RangeErr('year-month out of range');
    return mkDate(f.year, month, 1);
  }
  function toTemporalYearMonth(item, options) {
    if (isObject(item)) {
      if (pymSlots.has(item)) { getOverflow(getOptionsObject(options)); return copyDate(pymSlots.get(item)); }
      getCalendarFromBag(item);
      var r = prepareFields(item, YEARMONTH_NAMES);
      return yearMonthFromFields(r.fields, getOverflow(getOptionsObject(options)));
    }
    if (typeof item !== 'string') throw new TypeErr('cannot convert to a Temporal.PlainYearMonth');
    var rec = parseISOString(item, 'yearmonth');
    if (!rec.hasDate) throw new RangeErr('invalid year-month string');
    checkDateString(rec);
    if (!yearMonthWithinLimits(rec.year, rec.month)) throw new RangeErr('year-month out of range');
    getOverflow(getOptionsObject(options));
    return mkDate(rec.year, rec.month, 1);
  }
  function yearMonthString(d, show) {
    var s = yearString(d.year) + '-' + pad(Str(d.month), 2);
    if (show === 'always' || show === 'critical') s += '-' + pad(Str(d.day), 2);
    return s + calendarAnnotation('iso8601', show);
  }
  function addDurationToYearMonth(sign, ym, other, options) {
    var d = toTemporalDurationRecord(other);
    if (sign < 0) d = negateDuration(d);
    var overflow = getOverflow(getOptionsObject(options));
    if (d.weeks || d.days || d.hours || d.minutes || d.seconds || d.milliseconds || d.microseconds || d.nanoseconds) throw new RangeErr('only years and months can be added to a PlainYearMonth');
    var first = mkDate(ym.year, ym.month, 1);
    if (!dateWithinLimits(first.year, first.month, first.day)) throw new RangeErr('date out of range');
    var start = first;
    if (durationSign(d) < 0) start = mkDate(ym.year, ym.month, daysInMonth(ym.year, ym.month));
    var added = addDate(start, d.years, d.months, 0, 0, 'constrain');
    return wrapYearMonth(yearMonthFromFields({ year: added.year, month: added.month }, overflow));
  }
  function differenceTemporalYearMonth(sinceOp, ym, other, options) {
    var o = toTemporalYearMonth(other);
    options = getOptionsObject(options);
    var st = getDifferenceSettings(sinceOp, options, 'date', ['week', 'day'], 'month', 'year');
    if (ym.year === o.year && ym.month === o.month) return wrapDuration(createDurationRecord(0, 0, 0, 0, 0, 0, 0, 0, 0, 0));
    var a = mkDate(ym.year, ym.month, 1), b = mkDate(o.year, o.month, 1);
    if (!dateWithinLimits(a.year, a.month, 1) || !dateWithinLimits(b.year, b.month, 1)) throw new RangeErr('date out of range');
    var dd = differenceDate(a, b, st.largest);
    var di = { years: dd.years, months: dd.months, weeks: 0, days: 0, norm: 0n };
    if (st.smallest !== 'month' || st.increment !== 1) {
      di = roundRelative(di, epochNsOfDateAt(b, 0), a, 0, st.largest, st.increment, st.smallest, st.mode);
    }
    var rec = internalToRecord(di, 'month');
    return wrapDuration(sinceOp ? negateDuration(rec) : rec);
  }

  function PlainYearMonth() {
    needNew(new.target, 'PlainYearMonth');
    var a = arguments;
    var y = toIntegerWithTruncation(a[0]), m = toIntegerWithTruncation(a[1]);
    var cal = a[2];
    if (cal !== undefined) {
      if (typeof cal !== 'string') throw new TypeErr('calendar must be a string');
      canonicalCalendar(cal);
    }
    var ref = a[3] === undefined ? 1 : toIntegerWithTruncation(a[3]);
    if (!isValidDate(y, m, ref)) throw new RangeErr('year-month out of range');
    return wrapYearMonth(mkDate(y, m, ref), protoFromNewTarget(new.target, PlainYearMonthProto));
  }
  defineLen(PlainYearMonth, 2);
  PlainYearMonthProto = PlainYearMonth.prototype;
  installClass(PlainYearMonth, 'Temporal.PlainYearMonth', {
    from(item, options) { return wrapYearMonth(toTemporalYearMonth(item, options)); },
    compare(one, two) {
      var a = toTemporalYearMonth(one), b = toTemporalYearMonth(two);
      return compareDate(a, b);
    }
  }, {
    get calendarId() { pymSlots.get(this); return 'iso8601'; },
    get era() { pymSlots.get(this); return undefined; },
    get eraYear() { pymSlots.get(this); return undefined; },
    get year() { return pymSlots.get(this).year; },
    get month() { return pymSlots.get(this).month; },
    get monthCode() { return monthCodeOf(pymSlots.get(this).month); },
    get daysInMonth() { var d = pymSlots.get(this); return daysInMonth(d.year, d.month); },
    get daysInYear() { return isLeap(pymSlots.get(this).year) ? 366 : 365; },
    get monthsInYear() { pymSlots.get(this); return 12; },
    get inLeapYear() { return isLeap(pymSlots.get(this).year); }
  }, {
    with(temporalYearMonthLike, options) {
      var ym = pymSlots.get(this);
      if (!isObject(temporalYearMonthLike)) throw new TypeErr('year-month-like must be an object');
      rejectTemporalLike(temporalYearMonthLike);
      var r = prepareFields(temporalYearMonthLike, YEARMONTH_NAMES);
      if (!r.any) throw new TypeErr('year-month-like object has no year-month properties');
      var merged = mergeFields({ year: ym.year, month: ym.month, monthCode: monthCodeOf(ym.month) }, r.fields);
      return wrapYearMonth(yearMonthFromFields(merged, getOverflow(getOptionsObject(options))));
    },
    add(temporalDurationLike, options) { return addDurationToYearMonth(1, pymSlots.get(this), temporalDurationLike, options); },
    subtract(temporalDurationLike, options) { return addDurationToYearMonth(-1, pymSlots.get(this), temporalDurationLike, options); },
    until(other, options) { return differenceTemporalYearMonth(false, pymSlots.get(this), other, options); },
    since(other, options) { return differenceTemporalYearMonth(true, pymSlots.get(this), other, options); },
    equals(other) {
      var ym = pymSlots.get(this), o = toTemporalYearMonth(other);
      return compareDate(ym, o) === 0;
    },
    toString(options) {
      var ym = pymSlots.get(this);
      options = getOptionsObject(options);
      return yearMonthString(ym, getCalendarNameOption(options));
    },
    toJSON() { return yearMonthString(pymSlots.get(this), 'auto'); },
    toLocaleString() { return yearMonthString(pymSlots.get(this), 'auto'); },
    valueOf() { throw new TypeErr('Temporal.PlainYearMonth cannot be converted to a primitive; use compare()'); },
    toPlainDate(item) {
      var ym = pymSlots.get(this);
      if (!isObject(item)) throw new TypeErr('item must be an object');
      var r = prepareFields(item, ['day']);
      var merged = mergeFields({ year: ym.year, month: ym.month, monthCode: monthCodeOf(ym.month) }, r.fields);
      return wrapDate(dateFromFields(merged, 'constrain'));
    }
  });
  defineLen(PlainYearMonthProto.toString, 0);
  defineLen(PlainYearMonthProto.toJSON, 0);
  defineLen(PlainYearMonthProto.toLocaleString, 0);

  // ---------------------------------------------------------------- PlainMonthDay
  var pmdSlots = slotted('PlainMonthDay');
  carriers.push(pmdSlots);
  var PlainMonthDayProto;
  function wrapMonthDay(d, proto) { return wrapWith(pmdSlots, proto === undefined ? PlainMonthDayProto : proto, d); }
  function monthDayFromFields(f, overflow) {
    if (f.day === undefined) throw new TypeErr('day is required');
    if (f.month === undefined && f.monthCode === undefined) throw new TypeErr('month or monthCode is required');
    var month = resolveMonth(f);
    var year = f.year === undefined ? 1972 : f.year;
    var d = regulateDate(year, month, f.day, overflow);
    return mkDate(1972, d.month, d.day);
  }
  function toTemporalMonthDay(item, options) {
    if (isObject(item)) {
      if (pmdSlots.has(item)) { getOverflow(getOptionsObject(options)); return copyDate(pmdSlots.get(item)); }
      getCalendarFromBag(item);
      var r = prepareFields(item, DATE_NAMES);
      return monthDayFromFields(r.fields, getOverflow(getOptionsObject(options)));
    }
    if (typeof item !== 'string') throw new TypeErr('cannot convert to a Temporal.PlainMonthDay');
    var rec = parseISOString(item, 'monthday');
    if (!rec.hasDate) throw new RangeErr('invalid month-day string');
    checkDateString(rec);
    getOverflow(getOptionsObject(options));
    return mkDate(1972, rec.month, rec.day);
  }
  function monthDayString(d, show) {
    var s = pad(Str(d.month), 2) + '-' + pad(Str(d.day), 2);
    if (show === 'always' || show === 'critical') s = yearString(d.year) + '-' + s;
    return s + calendarAnnotation('iso8601', show);
  }

  function PlainMonthDay() {
    needNew(new.target, 'PlainMonthDay');
    var a = arguments;
    var m = toIntegerWithTruncation(a[0]), d = toIntegerWithTruncation(a[1]);
    var cal = a[2];
    if (cal !== undefined) {
      if (typeof cal !== 'string') throw new TypeErr('calendar must be a string');
      canonicalCalendar(cal);
    }
    var ref = a[3] === undefined ? 1972 : toIntegerWithTruncation(a[3]);
    if (!isValidDate(ref, m, d) || !dateWithinLimits(ref, m, d)) throw new RangeErr('month-day out of range');
    return wrapMonthDay(mkDate(ref, m, d), protoFromNewTarget(new.target, PlainMonthDayProto));
  }
  defineLen(PlainMonthDay, 2);
  PlainMonthDayProto = PlainMonthDay.prototype;
  installClass(PlainMonthDay, 'Temporal.PlainMonthDay', {
    from(item, options) { return wrapMonthDay(toTemporalMonthDay(item, options)); }
  }, {
    get calendarId() { pmdSlots.get(this); return 'iso8601'; },
    get monthCode() { return monthCodeOf(pmdSlots.get(this).month); },
    get day() { return pmdSlots.get(this).day; }
  }, {
    with(temporalMonthDayLike, options) {
      var md = pmdSlots.get(this);
      if (!isObject(temporalMonthDayLike)) throw new TypeErr('month-day-like must be an object');
      rejectTemporalLike(temporalMonthDayLike);
      var r = prepareFields(temporalMonthDayLike, DATE_NAMES);
      if (!r.any) throw new TypeErr('month-day-like object has no month-day properties');
      var merged = mergeFields({ monthCode: monthCodeOf(md.month), day: md.day }, r.fields);
      return wrapMonthDay(monthDayFromFields(merged, getOverflow(getOptionsObject(options))));
    },
    equals(other) {
      var md = pmdSlots.get(this), o = toTemporalMonthDay(other);
      return compareDate(md, o) === 0;
    },
    toString(options) {
      var md = pmdSlots.get(this);
      options = getOptionsObject(options);
      return monthDayString(md, getCalendarNameOption(options));
    },
    toJSON() { return monthDayString(pmdSlots.get(this), 'auto'); },
    toLocaleString() { return monthDayString(pmdSlots.get(this), 'auto'); },
    valueOf() { throw new TypeErr('Temporal.PlainMonthDay cannot be converted to a primitive'); },
    toPlainDate(item) {
      var md = pmdSlots.get(this);
      if (!isObject(item)) throw new TypeErr('item must be an object');
      var r = prepareFields(item, ['year']);
      var merged = mergeFields({ monthCode: monthCodeOf(md.month), day: md.day }, r.fields);
      return wrapDate(dateFromFields(merged, 'constrain'));
    }
  });
  defineLen(PlainMonthDayProto.toString, 0);
  defineLen(PlainMonthDayProto.toJSON, 0);
  defineLen(PlainMonthDayProto.toLocaleString, 0);
