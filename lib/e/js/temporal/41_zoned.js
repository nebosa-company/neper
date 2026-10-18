  // ---------------------------------------------------------------- time zones (UTC and fixed offsets)
  var UTC_ZONE = { id: 'UTC', offset: 0 };
  function offsetZone(ns) { return { id: formatOffsetNs(ns, false), offset: ns }; }
  var RE_SUB_MINUTE_OFFSET = /^[+−-][0-9]{2}:?[0-9]{2}:?[0-9]{2}/;
  function timeZoneFromString(s) {
    if (exec(RE_OFFSET_ONLY, s) !== null) return offsetZone(parseOffsetString(s, false));
    if (exec(RE_SUB_MINUTE_OFFSET, s) !== null && exec(RE_OFFSET_SUB, s) !== null) throw new RangeErr('time zone offsets have minute precision');
    if (exec(RE_TZ_NAME, s) !== null) {
      if (tzNamed(s)) return UTC_ZONE;
      throw new RangeErr('unsupported time zone: ' + s);
    }
    var rec = parseISOString(s, 'zone');
    if (rec.tz !== undefined) {
      if (exec(RE_TZ_OFFSET_ANN, rec.tz) !== null) return offsetZone(parseOffsetString(rec.tz, false));
      if (tzNamed(rec.tz)) return UTC_ZONE;
      throw new RangeErr('unsupported time zone: ' + rec.tz);
    }
    if (rec.z) return UTC_ZONE;
    if (rec.offsetNs !== undefined) {
      if (rec.offsetSubMinute) throw new RangeErr('time zone offsets have minute precision');
      return offsetZone(rec.offsetNs);
    }
    throw new RangeErr('invalid time zone: ' + s);
  }
  function toTimeZone(v) {
    if (isObject(v) && zdtSlots.has(v)) return zdtSlots.get(v).tz;
    if (typeof v !== 'string') throw new TypeErr('time zone must be a string');
    return timeZoneFromString(v);
  }
  function epochNsForLocal(tz, dt, disambiguation) {
    if (!dateTimeWithinLimits(dt.date, dt.time)) throw new RangeErr('date-time out of range');
    return checkInstant(epochNsOf(dt.date, dt.time) - Big(tz.offset));
  }

  // ---------------------------------------------------------------- ZonedDateTime
  var zdtSlots = slotted('ZonedDateTime');
  carriers.push(zdtSlots);
  var ZonedProto;
  function wrapZoned(ns, tz, proto) { return wrapWith(zdtSlots, proto === undefined ? ZonedProto : proto, { ns: ns, tz: tz }); }
  function zdtDateTime(z) { return wallToDateTime(z.ns + Big(z.tz.offset)); }
  var ZONED_NAMES = ['day', 'hour', 'microsecond', 'millisecond', 'minute', 'month', 'monthCode', 'nanosecond', 'offset', 'second', 'year'];

  function interpretOffset(dt, behaviour, offsetNs, tz, disambiguation, offsetOpt, matchMinutes) {
    if (!dateTimeWithinLimits(dt.date, dt.time)) throw new RangeErr('date-time out of range');
    if (behaviour === 'wall' || (behaviour === 'option' && offsetOpt === 'ignore')) return epochNsForLocal(tz, dt, disambiguation);
    if (behaviour === 'exact' || (behaviour === 'option' && offsetOpt === 'use')) {
      return checkInstant(epochNsOf(dt.date, dt.time) - Big(offsetNs));
    }
    var cand = epochNsForLocal(tz, dt, 'compatible');
    var cmp = matchMinutes ? Num(roundNumberToIncrement(Big(tz.offset), NS.min, 'halfExpand')) : tz.offset;
    if (cmp === offsetNs || tz.offset === offsetNs) return cand;
    if (offsetOpt === 'reject') throw new RangeErr('offset does not match the time zone');
    return epochNsForLocal(tz, dt, disambiguation);
  }
  function toTemporalZoned(item, options) {
    var dis, offsetOpt, overflow, rec, tz, ns;
    if (isObject(item)) {
      if (zdtSlots.has(item)) {
        var s = zdtSlots.get(item);
        options = getOptionsObject(options);
        getDisambiguation(options); getOffsetOption(options, 'reject'); getOverflow(options);
        return { ns: s.ns, tz: s.tz };
      }
      getCalendarFromBag(item);
      var names = ZONED_NAMES.slice();
      // timeZone sits between second and year in alphabetical order
      names.splice(names.length - 1, 0, 'timeZone');
      var r = prepareFields(item, names);
      var f = r.fields;
      if (f.timeZone === undefined) throw new TypeErr('timeZone is required');
      tz = toTimeZone(f.timeZone);
      var offsetNs, behaviour = 'wall';
      if (f.offset !== undefined) { offsetNs = parseOffsetString(f.offset, true); behaviour = 'option'; }
      options = getOptionsObject(options);
      dis = getDisambiguation(options);
      offsetOpt = getOffsetOption(options, 'reject');
      overflow = getOverflow(options);
      var dt = dateTimeFromFields(f, overflow);
      ns = interpretOffset(dt, behaviour, offsetNs, tz, dis, offsetOpt, false);
      return { ns: ns, tz: tz };
    }
    if (typeof item !== 'string') throw new TypeErr('cannot convert to a Temporal.ZonedDateTime');
    rec = parseISOString(item, 'zoned');
    if (!rec.hasDate || rec.tz === undefined) throw new RangeErr('a time zone annotation is required');
    if (rec.calendar !== undefined) canonicalCalendar(rec.calendar);
    if (exec(RE_TZ_OFFSET_ANN, rec.tz) !== null) tz = offsetZone(parseOffsetString(rec.tz, false));
    else if (tzNamed(rec.tz)) tz = UTC_ZONE;
    else throw new RangeErr('unsupported time zone: ' + rec.tz);
    var behaviour2 = rec.z ? 'exact' : rec.offsetNs !== undefined ? 'option' : 'wall';
    options = getOptionsObject(options);
    dis = getDisambiguation(options);
    offsetOpt = getOffsetOption(options, 'reject');
    getOverflow(options);
    var dt2 = { date: mkDate(rec.year, rec.month, rec.day), time: mkTime(rec.hour, rec.minute, rec.second, rec.millisecond, rec.microsecond, rec.nanosecond) };
    ns = interpretOffset(dt2, behaviour2, rec.offsetNs === undefined ? 0 : rec.offsetNs, tz, dis, offsetOpt, true);
    return { ns: ns, tz: tz };
  }
  function plainDateToZoned(date, item) {
    var tz, time;
    if (isObject(item) && !zdtSlots.has(item)) {
      var tzLike = item.timeZone;
      if (tzLike === undefined) tz = toTimeZone(item);
      else { tz = toTimeZone(tzLike); time = item.plainTime; }
    } else tz = toTimeZone(item);
    var dt;
    if (time === undefined) dt = { date: date, time: MIDNIGHT };
    else dt = { date: date, time: toTemporalTime(time) };
    return wrapZoned(epochNsForLocal(tz, dt, 'compatible'), tz);
  }
  function addZoned(ns, tz, d, overflow) {
    var norm = timeDurationNs(d);
    if (d.years === 0 && d.months === 0 && d.weeks === 0 && d.days === 0) return checkInstant(ns + norm);
    var dt = wallToDateTime(ns + Big(tz.offset));
    var date = addDate(dt.date, d.years, d.months, d.weeks, d.days, overflow);
    var mid = epochNsForLocal(tz, { date: date, time: dt.time }, 'compatible');
    return checkInstant(mid + norm);
  }
  function zonedString(z, p, showOffset, showTz, showCal) {
    var dt = wallToDateTime(z.ns + Big(z.tz.offset));
    var s = dateString(dt.date) + 'T' + timeString(dt.time, p);
    if (showOffset !== 'never') s += formatOffsetNs(z.tz.offset, false);
    if (showTz !== 'never') s += '[' + (showTz === 'critical' ? '!' : '') + z.tz.id + ']';
    return s + calendarAnnotation('iso8601', showCal);
  }
  function startOfDayNs(z) {
    var dt = zdtDateTime(z);
    return epochNsForLocal(z.tz, { date: dt.date, time: MIDNIGHT }, 'compatible');
  }
  function differenceZoned(sinceOp, z, other, options) {
    var o = toTemporalZoned(other);
    options = getOptionsObject(options);
    var st = getDifferenceSettings(sinceOp, options, 'datetime', [], 'nanosecond', 'hour');
    var rec;
    if (!isDateUnit(st.largest)) {
      var norm = roundNumberToIncrement(o.ns - z.ns, UNIT_NS[st.smallest] * Big(st.increment), st.mode);
      var parts = balanceTime(norm, st.largest);
      rec = fixZeros(createDurationRecord(0, 0, 0, 0, parts.hours, parts.minutes, parts.seconds, parts.milliseconds, parts.microseconds, parts.nanoseconds));
    } else {
      if (z.tz.id !== o.tz.id) throw new RangeErr('the time zones must match');
      if (z.ns === o.ns) return wrapDuration(createDurationRecord(0, 0, 0, 0, 0, 0, 0, 0, 0, 0));

      var a = zdtDateTime(z), b = zdtDateTime(o);
      var di = differenceISODateTime(a, b, st.largest);
      if (!(st.smallest === 'nanosecond' && st.increment === 1)) {
        di = roundRelative(di, o.ns + Big(o.tz.offset), a.date, timeToNs(a.time), st.largest, st.increment, st.smallest, st.mode, true);
      }
      rec = internalToRecord(di, 'hour');
    }
    return wrapDuration(sinceOp ? negateDuration(rec) : rec);
  }

  function ZonedDateTime() {
    needNew(new.target, 'ZonedDateTime');
    var ns = toBigInt(arguments[0]);
    var tzArg = arguments[1];
    if (typeof tzArg !== 'string') throw new TypeErr('time zone must be a string');
    var tz = timeZoneFromString(tzArg);
    var cal = arguments[2];
    if (cal !== undefined) {
      if (typeof cal !== 'string') throw new TypeErr('calendar must be a string');
      canonicalCalendar(cal);
    }
    return wrapZoned(checkInstant(ns), tz, protoFromNewTarget(new.target, ZonedProto));
  }
  defineLen(ZonedDateTime, 2);
  ZonedProto = ZonedDateTime.prototype;
  function zdt(self) { return zdtSlots.get(self); }
  installClass(ZonedDateTime, 'Temporal.ZonedDateTime', {
    from(item, options) {
      var r = toTemporalZoned(item, options);
      return wrapZoned(r.ns, r.tz);
    },
    compare(one, two) {
      var a = toTemporalZoned(one), b = toTemporalZoned(two);
      return a.ns < b.ns ? -1 : a.ns > b.ns ? 1 : 0;
    }
  }, {
    get calendarId() { zdt(this); return 'iso8601'; },
    get timeZoneId() { return zdt(this).tz.id; },
    get era() { zdt(this); return undefined; },
    get eraYear() { zdt(this); return undefined; },
    get year() { return zdtDateTime(zdt(this)).date.year; },
    get month() { return zdtDateTime(zdt(this)).date.month; },
    get monthCode() { return monthCodeOf(zdtDateTime(zdt(this)).date.month); },
    get day() { return zdtDateTime(zdt(this)).date.day; },
    get hour() { return zdtDateTime(zdt(this)).time.hour; },
    get minute() { return zdtDateTime(zdt(this)).time.minute; },
    get second() { return zdtDateTime(zdt(this)).time.second; },
    get millisecond() { return zdtDateTime(zdt(this)).time.millisecond; },
    get microsecond() { return zdtDateTime(zdt(this)).time.microsecond; },
    get nanosecond() { return zdtDateTime(zdt(this)).time.nanosecond; },
    get epochMilliseconds() { return Num(floorDiv(zdt(this).ns, NS.ms)); },
    get epochNanoseconds() { return zdt(this).ns; },
    get dayOfWeek() { var d = zdtDateTime(zdt(this)).date; return dayOfWeek(d.year, d.month, d.day); },
    get dayOfYear() { var d = zdtDateTime(zdt(this)).date; return dayOfYear(d.year, d.month, d.day); },
    get weekOfYear() { var d = zdtDateTime(zdt(this)).date; return weekInfo(d.year, d.month, d.day).week; },
    get yearOfWeek() { var d = zdtDateTime(zdt(this)).date; return weekInfo(d.year, d.month, d.day).year; },
    get hoursInDay() { zdt(this); return 24; },
    get daysInWeek() { zdt(this); return 7; },
    get daysInMonth() { var d = zdtDateTime(zdt(this)).date; return daysInMonth(d.year, d.month); },
    get daysInYear() { return isLeap(zdtDateTime(zdt(this)).date.year) ? 366 : 365; },
    get monthsInYear() { zdt(this); return 12; },
    get inLeapYear() { return isLeap(zdtDateTime(zdt(this)).date.year); },
    get offsetNanoseconds() { return zdt(this).tz.offset; },
    get offset() { return formatOffsetNs(zdt(this).tz.offset, true); }
  }, {
    with(temporalZonedDateTimeLike, options) {
      var z = zdt(this);
      if (!isObject(temporalZonedDateTimeLike)) throw new TypeErr('zoned-date-time-like must be an object');
      rejectTemporalLike(temporalZonedDateTimeLike);
      var r = prepareFields(temporalZonedDateTimeLike, ZONED_NAMES);
      if (!r.any) throw new TypeErr('zoned-date-time-like object has no properties');
      var cur = zdtDateTime(z);
      var base = dateTimeFieldsOf(cur);
      base.offset = formatOffsetNs(z.tz.offset, true);
      var merged = mergeFields(base, r.fields);
      options = getOptionsObject(options);
      var dis = getDisambiguation(options);
      var offsetOpt = getOffsetOption(options, 'prefer');
      var overflow = getOverflow(options);
      var dt = dateTimeFromFields(merged, overflow);
      var offsetNs = parseOffsetString(merged.offset, true);
      return wrapZoned(interpretOffset(dt, 'option', offsetNs, z.tz, dis, offsetOpt, false), z.tz);
    },
    withPlainTime(plainTimeLike) {
      var z = zdt(this), dt = zdtDateTime(z);
      if (plainTimeLike === undefined) return wrapZoned(startOfDayNs(z), z.tz);
      var t = toTemporalTime(plainTimeLike);
      return wrapZoned(epochNsForLocal(z.tz, { date: dt.date, time: t }, 'compatible'), z.tz);
    },
    withTimeZone(timeZone) {
      var z = zdt(this);
      return wrapZoned(z.ns, toTimeZone(timeZone));
    },
    withCalendar(calendar) {
      var z = zdt(this);
      toCalendarId(calendar);
      return wrapZoned(z.ns, z.tz);
    },
    add(temporalDurationLike, options) {
      var z = zdt(this);
      var d = toTemporalDurationRecord(temporalDurationLike);
      var overflow = getOverflow(getOptionsObject(options));
      return wrapZoned(addZoned(z.ns, z.tz, d, overflow), z.tz);
    },
    subtract(temporalDurationLike, options) {
      var z = zdt(this);
      var d = negateDuration(toTemporalDurationRecord(temporalDurationLike));
      var overflow = getOverflow(getOptionsObject(options));
      return wrapZoned(addZoned(z.ns, z.tz, d, overflow), z.tz);
    },
    until(other, options) { return differenceZoned(false, zdt(this), other, options); },
    since(other, options) { return differenceZoned(true, zdt(this), other, options); },
    round(roundTo) {
      var z = zdt(this);
      if (roundTo === undefined) throw new TypeErr('round requires an argument');
      var increment = 1, mode = 'halfExpand', smallest;
      if (typeof roundTo === 'string') {
        var o = create(null);
        o.smallestUnit = roundTo;
        smallest = getUnitOption(o, 'smallestUnit', 'datetime', undefined);
      } else {
        roundTo = getOptionsObject(roundTo);
        increment = getRoundingIncrementOption(roundTo);
        mode = getRoundingModeOption(roundTo, 'halfExpand');
        smallest = getUnitOption(roundTo, 'smallestUnit', 'datetime', undefined);
      }
      if (smallest === undefined || isCalendarUnit(smallest)) throw new RangeErr('smallestUnit must be day or smaller');
      if (smallest === 'day') validateRoundingIncrement(increment, 1, true);
      else validateRoundingIncrement(increment, maxIncrement(smallest), false);
      var dt = zdtDateTime(z);
      if (smallest === 'day') {
        var start = startOfDayNs(z);
        var next = epochNsForLocal(z.tz, { date: balanceDate(dt.date.year, dt.date.month, dt.date.day + 1), time: MIDNIGHT }, 'compatible');
        var len = next - start;
        var rounded = roundDiv(z.ns - start, len, mode);
        return wrapZoned(checkInstant(start + rounded * len), z.tz);
      }
      var rt = roundDateTime(dt, increment, smallest, mode);
      return wrapZoned(interpretOffset(rt, 'option', z.tz.offset, z.tz, 'compatible', 'prefer', false), z.tz);
    },
    equals(other) {
      var z = zdt(this), o = toTemporalZoned(other);
      return z.ns === o.ns && z.tz.id === o.tz.id;
    },
    toString(options) {
      var z = zdt(this);
      options = getOptionsObject(options);
      var showCal = getCalendarNameOption(options);
      var showOffset;
      var p = getSecondsPrecision(options, true, function () { showOffset = getShowOffsetOption(options); });
      var showTz = getShowTimeZoneOption(options);
      var rounded = roundAsIfPositive(z.ns, UNIT_NS[p.unit] * Big(p.inc), p.mode);
      checkInstant(rounded);
      return zonedString({ ns: rounded, tz: z.tz }, p.precision, showOffset, showTz, showCal);
    },
    toJSON() { return zonedString(zdt(this), 'auto', 'auto', 'auto', 'auto'); },
    toLocaleString() { return zonedString(zdt(this), 'auto', 'auto', 'auto', 'auto'); },
    valueOf() { throw new TypeErr('Temporal.ZonedDateTime cannot be converted to a primitive; use compare()'); },
    startOfDay() { var z = zdt(this); return wrapZoned(startOfDayNs(z), z.tz); },
    toInstant() { return wrapInstant(zdt(this).ns); },
    toPlainDateTime() { var dt = zdtDateTime(zdt(this)); return wrapDateTime(dt); },
    toPlainDate() { return wrapDate(zdtDateTime(zdt(this)).date); },
    toPlainTime() { return wrapTime(zdtDateTime(zdt(this)).time); }
  });
  defineLen(ZonedProto.toString, 0);
  defineLen(ZonedProto.toJSON, 0);
  defineLen(ZonedProto.toLocaleString, 0);
  defineLen(ZonedProto.startOfDay, 0);
