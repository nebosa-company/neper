  // ---------------------------------------------------------------- calendar fields
  var RE_MONTH_CODE = /^M([0-9]{2})(L?)$/;
  var FIELD_CONV = {
    year: toIntegerWithTruncation, month: toPositiveInteger, day: toPositiveInteger,
    era: function (v) { return primitiveString(v); }, eraYear: toIntegerWithTruncation,
    monthCode: function (v) {
      var s = primitiveString(v);
      if (exec(RE_MONTH_CODE, s) === null) throw new RangeErr('invalid monthCode');
      return s;
    },
    hour: toIntegerWithTruncation, minute: toIntegerWithTruncation, second: toIntegerWithTruncation,
    millisecond: toIntegerWithTruncation, microsecond: toIntegerWithTruncation, nanosecond: toIntegerWithTruncation,
    offset: function (v) { var s = primitiveString(v); parseOffsetString(s, true); return s; }, timeZone: function (v) { return v; }
  };
  // Reads the named properties (given in alphabetical order) off a bag.
  function prepareFields(bag, names) {
    var out = {}, any = false;
    for (var i = 0; i < names.length; i++) {
      var v = bag[names[i]];
      if (v !== undefined) { any = true; out[names[i]] = FIELD_CONV[names[i]](v); }
    }
    return { fields: out, any: any };
  }
  function resolveMonth(f) {
    var code = f.monthCode, month = f.month;
    if (code !== undefined) {
      var m = exec(RE_MONTH_CODE, code);
      if (m === null) throw new RangeErr('invalid monthCode');
      var mc = +m[1];
      if (m[2] === 'L' || mc < 1 || mc > 12) throw new RangeErr('monthCode is not valid in the ISO calendar');
      if (month !== undefined && month !== mc) throw new RangeErr('month and monthCode do not agree');
      return mc;
    }
    if (month === undefined) throw new TypeErr('month or monthCode is required');
    return month;
  }
  function monthCodeOf(m) { return 'M' + pad(Str(m), 2); }
  function regulateDate(y, m, d, overflow) {
    if (overflow === 'constrain') {
      m = mathMin(mathMax(m, 1), 12);
      d = mathMin(mathMax(d, 1), daysInMonth(y, m));
    } else if (!isValidDate(y, m, d)) {
      throw new RangeErr('date out of range');
    }
    return mkDate(y, m, d);
  }
  function dateFromFields(f, overflow, cal) {
    if (!isIsoCal(cal)) {
      var iso = calDateFromFields(cal, f, overflow);
      iso.cal = cal;
      return iso;
    }
    if (f.year === undefined) throw new TypeErr('year is required');
    if (f.day === undefined) throw new TypeErr('day is required');
    if (f.month === undefined && f.monthCode === undefined) throw new TypeErr('month or monthCode is required');
    var month = resolveMonth(f);
    var d = regulateDate(f.year, month, f.day, overflow);
    if (!dateWithinLimits(d.year, d.month, d.day)) throw new RangeErr('date out of range');
    return d;
  }
  function dateFieldsOf(d) {
    if (!isIsoCal(d.cal)) {
      var cf = calFields(d.cal, d);
      return { era: cf.era, eraYear: cf.eraYear, year: cf.year, month: cf.month, monthCode: cf.monthCode, day: cf.day };
    }
    return { year: d.year, month: d.month, monthCode: monthCodeOf(d.month), day: d.day };
  }
  // CalendarMergeFields for the ISO calendar: month and monthCode replace each other.
  function mergeFields(base, partial) {
    var out = {}, k;
    var dropMonth = partial.month !== undefined || partial.monthCode !== undefined;
    var dropYear = partial.year !== undefined || partial.era !== undefined || partial.eraYear !== undefined;
    for (k in base) if (!(dropMonth && (k === 'month' || k === 'monthCode')) && !(dropYear && (k === 'year' || k === 'era' || k === 'eraYear'))) out[k] = base[k];
    for (k in partial) out[k] = partial[k];
    return out;
  }

  // ---------------------------------------------------------------- PlainDate
  var pdSlots = slotted('PlainDate');
  carriers.push(pdSlots);
  var PlainDateProto;
  function wrapDate(d, proto) { return wrapWith(pdSlots, proto === undefined ? PlainDateProto : proto, d); }
  var DATE_NAMES = ['day', 'month', 'monthCode', 'year'];
  function copyDate(d) { var r = mkDate(d.year, d.month, d.day); if (d.cal !== undefined) r.cal = d.cal; return r; }
  function checkDateString(rec) {
    if (rec.z) throw new RangeErr('a UTC designator is not allowed here');
    if (rec.calendar !== undefined) return canonicalCalendar(rec.calendar);
    return 'iso8601';
  }
  function toTemporalDate(item, options) {
    if (isObject(item)) {
      if (pdSlots.has(item)) { getOverflow(getOptionsObject(options)); return copyDate(pdSlots.get(item)); }
      if (pdtSlots.has(item)) { getOverflow(getOptionsObject(options)); return copyDate(pdtSlots.get(item).date); }
      if (zdtSlots.has(item)) { var zd = zdtDateTime(zdtSlots.get(item)).date; getOverflow(getOptionsObject(options)); return zd; }
      var cal = getCalendarFromBag(item);
      var r = prepareFields(item, calFieldList(cal, DATE_NAMES));
      return dateFromFields(r.fields, getOverflow(getOptionsObject(options)), cal);
    }
    if (typeof item !== 'string') throw new TypeErr('cannot convert to a Temporal.PlainDate');
    var rec = parseISOString(item, 'date');
    if (!rec.hasDate) throw new RangeErr('invalid date string');
    var scal = checkDateString(rec);
    if (!dateWithinLimits(rec.year, rec.month, rec.day)) throw new RangeErr('date out of range');
    getOverflow(getOptionsObject(options));
    return withCal(mkDate(rec.year, rec.month, rec.day), scal);
  }
  function addDurationToDate(sign, date, other, options) {
    var d = toTemporalDurationRecord(other);
    if (sign < 0) d = negateDuration(d);
    var overflow = getOverflow(getOptionsObject(options));
    var norm = timeDurationNs(d);
    var days = d.days + Num(norm / NS_PER_DAY);
    return wrapDate(addDate(date, d.years, d.months, d.weeks, days, overflow));
  }
  function differenceTemporalDate(sinceOp, date, other, options) {
    var o = toTemporalDate(other);
    if (calOf(date) !== calOf(o)) throw new RangeErr('calendars must match');
    options = getOptionsObject(options);
    var st = getDifferenceSettings(sinceOp, options, 'date', [], 'day', 'day');
    if (compareDate(date, o) === 0) return wrapDuration(createDurationRecord(0, 0, 0, 0, 0, 0, 0, 0, 0, 0));
    var dd = differenceDate(date, o, st.largest);
    var di = { years: dd.years, months: dd.months, weeks: dd.weeks, days: dd.days, norm: 0n };
    if (st.smallest !== 'day' || st.increment !== 1) {
      di = roundRelative(di, epochNsOfDateAt(o, 0), date, 0, st.largest, st.increment, st.smallest, st.mode);
    }
    var rec = internalToRecord(di, 'day');
    return wrapDuration(sinceOp ? negateDuration(rec) : rec);
  }

  function PlainDate() {
    needNew(new.target, 'PlainDate');
    var a = arguments;
    var y = toIntegerWithTruncation(a[0]), m = toIntegerWithTruncation(a[1]), d = toIntegerWithTruncation(a[2]);
    var cal = a[3];
    if (cal !== undefined) {
      if (typeof cal !== 'string') throw new TypeErr('calendar must be a string');
      cal = canonicalCalendar(cal);
    }
    if (!isValidDate(y, m, d) || !dateWithinLimits(y, m, d)) throw new RangeErr('date out of range');
    return wrapDate(withCal(mkDate(y, m, d), cal), protoFromNewTarget(new.target, PlainDateProto));
  }
  defineLen(PlainDate, 3);
  PlainDateProto = PlainDate.prototype;
  installClass(PlainDate, 'Temporal.PlainDate', {
    from(item, options) { return wrapDate(toTemporalDate(item, options)); },
    compare(one, two) {
      var a = toTemporalDate(one), b = toTemporalDate(two);
      return compareDate(a, b);
    }
  }, accessorsFor(function (self) { return pdSlots.get(self); }, DATE_GETTER_NAMES), {
    toPlainYearMonth() {
      var d = pdSlots.get(this);
      if (!isIsoCal(d.cal)) return wrapYearMonth(calYearMonthRef(d.cal, d));
      return wrapYearMonth(mkDate(d.year, d.month, 1));
    },
    toPlainMonthDay() {
      var d = pdSlots.get(this);
      if (!isIsoCal(d.cal)) { var cf = calFields(d.cal, d); return wrapMonthDay(calMonthDayRef(d.cal, cf.monthCode, cf.day, 'constrain')); }
      return wrapMonthDay(mkDate(1972, d.month, d.day));
    },
    add(temporalDurationLike, options) { return addDurationToDate(1, pdSlots.get(this), temporalDurationLike, options); },
    subtract(temporalDurationLike, options) { return addDurationToDate(-1, pdSlots.get(this), temporalDurationLike, options); },
    with(temporalDateLike, options) {
      var d = pdSlots.get(this);
      if (!isObject(temporalDateLike)) throw new TypeErr('date-like must be an object');
      rejectTemporalLike(temporalDateLike);
      var r = prepareFields(temporalDateLike, calFieldList(d.cal, DATE_NAMES));
      if (!r.any) throw new TypeErr('date-like object has no date properties');
      var merged = mergeFields(dateFieldsOf(d), r.fields);
      return wrapDate(dateFromFields(merged, getOverflow(getOptionsObject(options)), d.cal));
    },
    withCalendar(calendar) {
      var d = pdSlots.get(this);
      var ncal = toCalendarId(calendar);
      return wrapDate(withCal(mkDate(d.year, d.month, d.day), ncal));
    },
    until(other, options) { return differenceTemporalDate(false, pdSlots.get(this), other, options); },
    since(other, options) { return differenceTemporalDate(true, pdSlots.get(this), other, options); },
    equals(other) {
      var d = pdSlots.get(this), o = toTemporalDate(other);
      return compareDate(d, o) === 0 && calOf(d) === calOf(o);
    },
    toPlainDateTime(temporalTime) {
      var d = pdSlots.get(this);
      var t = temporalTime === undefined ? MIDNIGHT : toTemporalTime(temporalTime);
      if (!dateTimeWithinLimits(d, t)) throw new RangeErr('date-time out of range');
      return wrapDateTime({ date: copyDate(d), time: copyTime(t) });
    },
    toZonedDateTime(item) { return plainDateToZoned(pdSlots.get(this), item); },
    toString(options) {
      var d = pdSlots.get(this);
      options = getOptionsObject(options);
      var show = getCalendarNameOption(options);
      return dateString(d) + calendarAnnotation(calOf(d), show);
    },
    toJSON() { return dateString(pdSlots.get(this)); },
    toLocaleString() { return dateString(pdSlots.get(this)); },
    valueOf() { throw new TypeErr('Temporal.PlainDate cannot be converted to a primitive; use compare()'); }
  });
  defineLen(PlainDateProto.toPlainDateTime, 0);
  defineLen(PlainDateProto.toJSON, 0);
  defineLen(PlainDateProto.toLocaleString, 0);
