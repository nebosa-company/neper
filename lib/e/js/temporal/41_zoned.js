  // ---------------------------------------------------------------- time zones (UTC and fixed offsets)
  var UTC_ZONE = { id: 'UTC', offset: 0 };
  function zoneFromName(nm) { return nm === 'UTC' ? UTC_ZONE : { id: nm, offset: 0, named: true }; }
  function offsetZone(ns) { return { id: formatOffsetNs(ns, false), offset: ns }; }
  var RE_SUB_MINUTE_OFFSET = /^[+−-][0-9]{2}:?[0-9]{2}:?[0-9]{2}/;
  function timeZoneFromString(s, strict) {
    if (exec(RE_OFFSET_ONLY, s) !== null) return offsetZone(parseOffsetString(s, false));
    if (exec(RE_SUB_MINUTE_OFFSET, s) !== null && exec(RE_OFFSET_SUB, s) !== null) throw new RangeErr('time zone offsets have minute precision');
    if (exec(RE_TZ_NAME, s) !== null) {
      var nm = tzLookup(s);
      if (nm !== undefined) return zoneFromName(nm);
      throw new RangeErr('unsupported time zone: ' + s);
    }
    if (strict) throw new RangeErr('invalid time zone identifier: ' + s);
    var rec = parseISOString(s, 'zone');
    if (rec.tz !== undefined) {
      if (exec(RE_TZ_OFFSET_ANN, rec.tz) !== null) return offsetZone(parseOffsetString(rec.tz, false));
      var nm2 = tzLookup(rec.tz);
      if (nm2 !== undefined) return zoneFromName(nm2);
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
  // The instants a wall-clock time maps to in a zone, earliest first (none in a gap, two when a clock change repeats it).
  function possibleEpochNs(tz, dt) {
    var wall = epochNsOf(dt.date, dt.time);
    if (!tz.named) return [wall - Big(tz.offset)];
    var o1 = tzOffsetAt(tz, wall - NS.d), o2 = tzOffsetAt(tz, wall + NS.d), out = [], c1 = wall - Big(o1);
    if (tzOffsetAt(tz, c1) === o1) out[out.length] = c1;
    if (o2 !== o1) {
      var c2 = wall - Big(o2);
      if (tzOffsetAt(tz, c2) === o2) out[out.length] = c2;
    }
    if (out.length === 2 && out[0] > out[1]) { var t = out[0]; out[0] = out[1]; out[1] = t; }
    return out;
  }
  function epochNsForLocal(tz, dt, disambiguation) {
    if (!dateTimeWithinLimits(dt.date, dt.time)) throw new RangeErr('date-time out of range');
    if (!tz.named) return checkInstant(epochNsOf(dt.date, dt.time) - Big(tz.offset));
    var poss = possibleEpochNs(tz, dt);
    if (poss.length === 1) return checkInstant(poss[0]);
    if (poss.length === 2) {
      if (disambiguation === 'reject') throw new RangeErr('the wall-clock time is ambiguous in the time zone');
      return checkInstant(disambiguation === 'later' ? poss[1] : poss[0]);
    }
    if (disambiguation === 'reject') throw new RangeErr('the wall-clock time does not exist in the time zone');
    var wall = epochNsOf(dt.date, dt.time), gap = Big(tzOffsetAt(tz, wall + NS.d) - tzOffsetAt(tz, wall - NS.d));
    if (disambiguation === 'earlier') {
      var e = possibleEpochNs(tz, wallToDateTime(wall - gap));
      return checkInstant(e[0]);
    }
    var l = possibleEpochNs(tz, wallToDateTime(wall + gap));
    return checkInstant(l[l.length - 1]);
  }

  // ---------------------------------------------------------------- ZonedDateTime
  var zdtSlots = slotted('ZonedDateTime');
  carriers.push(zdtSlots);
  var ZonedProto;
  function wrapZoned(ns, tz, proto, cal) { var rec = { ns: ns, tz: tz }; if (!isIsoCal(cal)) rec.cal = cal; return wrapWith(zdtSlots, proto === undefined ? ZonedProto : proto, rec); }
  function zdtDateTime(z) { var r = wallToDateTime(z.ns + Big(tzOffsetAt(z.tz, z.ns))); if (z.cal !== undefined) r.date.cal = z.cal; return r; }
  var ZONED_FIELD_NAMES = ['day', 'hour', 'microsecond', 'millisecond', 'minute', 'month', 'monthCode', 'nanosecond', 'offset', 'second', 'timeZone', 'year'];
  var ZONED_NAMES = ['day', 'hour', 'microsecond', 'millisecond', 'minute', 'month', 'monthCode', 'nanosecond', 'offset', 'second', 'year'];

  function interpretOffset(dt, behaviour, offsetNs, tz, disambiguation, offsetOpt, matchMinutes) {
    if (!dateTimeWithinLimits(dt.date, dt.time)) throw new RangeErr('date-time out of range');
    if (behaviour === 'wall' || (behaviour === 'option' && offsetOpt === 'ignore')) return epochNsForLocal(tz, dt, disambiguation);
    if (behaviour === 'exact' || (behaviour === 'option' && offsetOpt === 'use')) {
      return checkInstant(epochNsOf(dt.date, dt.time) - Big(offsetNs));
    }
    // prefer and reject work from the wall-clock time taken as if it were UTC, which must not precede the earliest instant
    if (epochNsOf(dt.date, dt.time) < -NS_MAX_INSTANT) throw new RangeErr('wall-clock time out of range');
    if (tz.named) {
      var poss = possibleEpochNs(tz, dt);
      for (var pi = 0; pi < poss.length; pi++) {
        var po = tzOffsetAt(tz, poss[pi]);
        if (po === offsetNs || (matchMinutes && Num(roundNumberToIncrement(Big(po), NS.min, 'halfExpand')) === offsetNs)) return checkInstant(poss[pi]);
      }
      if (offsetOpt === 'reject') throw new RangeErr('offset does not match the time zone');
      return epochNsForLocal(tz, dt, disambiguation);
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
        return { ns: s.ns, tz: s.tz, cal: s.cal };
      }
      var cal = getCalendarFromBag(item);
      var r = prepareFields(item, calFieldList(cal, ZONED_FIELD_NAMES));
      var f = r.fields;
      if (f.timeZone === undefined) throw new TypeErr('timeZone is required');
      tz = toTimeZone(f.timeZone);
      var offsetNs, behaviour = 'wall';
      if (f.offset !== undefined) { offsetNs = parseOffsetString(f.offset, true); behaviour = 'option'; }
      options = getOptionsObject(options);
      dis = getDisambiguation(options);
      offsetOpt = getOffsetOption(options, 'reject');
      overflow = getOverflow(options);
      var dt = dateTimeFromFields(f, overflow, cal);
      ns = interpretOffset(dt, behaviour, offsetNs, tz, dis, offsetOpt, false);
      return { ns: ns, tz: tz, cal: isIsoCal(cal) ? undefined : cal };
    }
    if (typeof item !== 'string') throw new TypeErr('cannot convert to a Temporal.ZonedDateTime');
    rec = parseISOString(item, 'zoned');
    if (!rec.hasDate || rec.tz === undefined) throw new RangeErr('a time zone annotation is required');
    var scal = rec.calendar !== undefined ? canonicalCalendar(rec.calendar) : 'iso8601';
    if (exec(RE_TZ_OFFSET_ANN, rec.tz) !== null) tz = offsetZone(parseOffsetString(rec.tz, false));
    else if (tzNamed(rec.tz)) tz = zoneFromName(tzLookup(rec.tz));
    else throw new RangeErr('unsupported time zone: ' + rec.tz);
    var behaviour2 = rec.z ? 'exact' : rec.offsetNs !== undefined ? 'option' : 'wall';
    options = getOptionsObject(options);
    dis = getDisambiguation(options);
    offsetOpt = getOffsetOption(options, 'reject');
    getOverflow(options);
    var dt2 = { date: mkDate(rec.year, rec.month, rec.day), time: mkTime(rec.hour, rec.minute, rec.second, rec.millisecond, rec.microsecond, rec.nanosecond) };
    ns = interpretOffset(dt2, behaviour2, rec.offsetNs === undefined ? 0 : rec.offsetNs, tz, dis, offsetOpt, true);
    return { ns: ns, tz: tz, cal: isIsoCal(scal) ? undefined : scal };
  }
  // The wall-clock time of a parsed or constructed-from-fields ZonedDateTime must not precede the earliest instant.
  function checkWall(ns, tz) {
    if (ns + Big(tzOffsetAt(tz, ns)) < -NS_MAX_INSTANT) throw new RangeErr('wall-clock time out of range');
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
    return wrapZoned(epochNsForLocal(tz, dt, 'compatible'), tz, undefined, date.cal);
  }
  // The next (or previous) instant at which a named zone's offset changes, or null when none is found within thirty years.
  function transitionNs(tz, ns, forward) {
    var STEP = 3 * 86400, LIMIT = 30 * 366 * 86400;
    var secs = Num(floorDiv(forward ? ns : ns - 1n, NS.s)), base = tzOffsetAt(tz, Big(secs) * NS.s);
    var cur = secs, far = secs;
    function off(sec) { return tzOffsetAt(tz, Big(sec) * NS.s); }
    if (forward) {
      for (var t = 0; t < LIMIT; t += STEP) {
        far = cur + STEP;
        if (off(far) !== base) {
          var lo = cur, hi = far;
          while (hi - lo > 1) { var mid = lo + mathFloor((hi - lo) / 2); if (off(mid) === base) lo = mid; else hi = mid; }
          var r = Big(hi) * NS.s;
          return r > ns && (r < NS_MAX_INSTANT && r > -NS_MAX_INSTANT) ? r : null;
        }
        cur = far;
      }
      return null;
    }
    for (var u = 0; u < LIMIT; u += STEP) {
      far = cur - STEP;
      if (off(far) !== base) {
        var lo2 = far, hi2 = cur;
        while (hi2 - lo2 > 1) { var mid2 = lo2 + mathFloor((hi2 - lo2) / 2); if (off(mid2) === base) hi2 = mid2; else lo2 = mid2; }
        var r2 = Big(hi2) * NS.s;
        return r2 < ns && (r2 < NS_MAX_INSTANT && r2 > -NS_MAX_INSTANT) ? r2 : null;
      }
      cur = far;
    }
    return null;
  }
  function addZoned(ns, tz, d, overflow, cal) {
    var norm = timeDurationNs(d);
    if (d.years === 0 && d.months === 0 && d.weeks === 0 && d.days === 0) return checkInstant(ns + norm);
    var dt = wallToDateTime(ns + Big(tzOffsetAt(tz, ns)));
    withCal(dt.date, cal);
    var date = addDate(dt.date, d.years, d.months, d.weeks, d.days, overflow);
    var mid = epochNsForLocal(tz, { date: date, time: dt.time }, 'compatible');
    return checkInstant(mid + norm);
  }
  function zonedString(z, p, showOffset, showTz, showCal) {
    var zoff = tzOffsetAt(z.tz, z.ns), dt = wallToDateTime(z.ns + Big(zoff));
    var s = dateString(dt.date) + 'T' + timeString(dt.time, p);
    if (showOffset !== 'never') s += formatOffsetNs(zoff, false);
    if (showTz !== 'never') s += '[' + (showTz === 'critical' ? '!' : '') + z.tz.id + ']';
    return s + calendarAnnotation(z.cal === undefined ? 'iso8601' : z.cal, showCal);
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
      if (!sameTimeZone(z.tz, o.tz)) throw new RangeErr('the time zones must match');
      if ((z.cal === undefined ? 'iso8601' : z.cal) !== (o.cal === undefined ? 'iso8601' : o.cal)) throw new RangeErr('calendars must match');
      if (z.ns === o.ns) return wrapDuration(createDurationRecord(0, 0, 0, 0, 0, 0, 0, 0, 0, 0));

      var a = zdtDateTime(z), b = zdtDateTime(o);
      var di = differenceISODateTime(a, b, st.largest);
      if (!(st.smallest === 'nanosecond' && st.increment === 1)) {
        di = roundRelative(di, o.ns + Big(tzOffsetAt(o.tz, o.ns)), a.date, timeToNs(a.time), st.largest, st.increment, st.smallest, st.mode, tzOffsetAt(z.tz, z.ns));
      }
      rec = internalToRecord(di, st.largest);
    }
    return wrapDuration(sinceOp ? negateDuration(rec) : rec);
  }

  function ZonedDateTime() {
    needNew(new.target, 'ZonedDateTime');
    var ns = toBigInt(arguments[0]);
    var tzArg = arguments[1];
    if (typeof tzArg !== 'string') throw new TypeErr('time zone must be a string');
    var tz = timeZoneFromString(tzArg, true);
    var cal = arguments[2];
    if (cal !== undefined) {
      if (typeof cal !== 'string') throw new TypeErr('calendar must be a string');
      cal = canonicalCalendar(cal);
    }
    return wrapZoned(checkInstant(ns), tz, protoFromNewTarget(new.target, ZonedProto), cal);
  }
  defineLen(ZonedDateTime, 2);
  ZonedProto = ZonedDateTime.prototype;
  function zdt(self) { return zdtSlots.get(self); }
  installClass(ZonedDateTime, 'Temporal.ZonedDateTime', {
    from(item, options) {
      var r = toTemporalZoned(item, options);
      return wrapZoned(r.ns, r.tz, undefined, r.cal);
    },
    compare(one, two) {
      var a = toTemporalZoned(one), b = toTemporalZoned(two);
      return a.ns < b.ns ? -1 : a.ns > b.ns ? 1 : 0;
    }
  }, mergeAccessors(accessorsFor(function (self) { return zdtDateTime(zdt(self)).date; }, DATE_GETTER_NAMES), {
    get timeZoneId() { return zdt(this).tz.id; },
    get hour() { return zdtDateTime(zdt(this)).time.hour; },
    get minute() { return zdtDateTime(zdt(this)).time.minute; },
    get second() { return zdtDateTime(zdt(this)).time.second; },
    get millisecond() { return zdtDateTime(zdt(this)).time.millisecond; },
    get microsecond() { return zdtDateTime(zdt(this)).time.microsecond; },
    get nanosecond() { return zdtDateTime(zdt(this)).time.nanosecond; },
    get epochMilliseconds() { return Num(floorDiv(zdt(this).ns, NS.ms)); },
    get epochNanoseconds() { return zdt(this).ns; },
    get hoursInDay() {
      var z = zdt(this), d = zdtDateTime(z).date;
      var a = epochNsForLocal(z.tz, { date: d, time: MIDNIGHT }, 'compatible');
      var n = balanceDate(d.year, d.month, d.day + 1);
      var b = epochNsForLocal(z.tz, { date: n, time: MIDNIGHT }, 'compatible');
      return divToNumber(b - a, NS.h);
    },
    get offsetNanoseconds() { var z = zdt(this); return tzOffsetAt(z.tz, z.ns); },
    get offset() { var z = zdt(this); return formatOffsetNs(tzOffsetAt(z.tz, z.ns), true); }
  }), {
    with(temporalZonedDateTimeLike, options) {
      var z = zdt(this);
      if (!isObject(temporalZonedDateTimeLike)) throw new TypeErr('zoned-date-time-like must be an object');
      rejectTemporalLike(temporalZonedDateTimeLike);
      var r = prepareFields(temporalZonedDateTimeLike, calFieldList(z.cal, ZONED_NAMES));
      if (!r.any) throw new TypeErr('zoned-date-time-like object has no properties');
      var cur = zdtDateTime(z);
      var base = dateTimeFieldsOf(cur);
      base.offset = formatOffsetNs(tzOffsetAt(z.tz, z.ns), true);
      var merged = mergeFields(base, r.fields, z.cal);
      options = getOptionsObject(options);
      var dis = getDisambiguation(options);
      var offsetOpt = getOffsetOption(options, 'prefer');
      var overflow = getOverflow(options);
      var dt = dateTimeFromFields(merged, overflow, z.cal);
      var offsetNs = parseOffsetString(merged.offset, true);
      return wrapZoned(interpretOffset(dt, 'option', offsetNs, z.tz, dis, offsetOpt, false), z.tz, undefined, z.cal);
    },
    withPlainTime(plainTimeLike) {
      var z = zdt(this), dt = zdtDateTime(z);
      if (plainTimeLike === undefined) return wrapZoned(startOfDayNs(z), z.tz, undefined, z.cal);
      var t = toTemporalTime(plainTimeLike);
      return wrapZoned(epochNsForLocal(z.tz, { date: dt.date, time: t }, 'compatible'), z.tz, undefined, z.cal);
    },
    withTimeZone(timeZone) {
      var z = zdt(this);
      return wrapZoned(z.ns, toTimeZone(timeZone), undefined, z.cal);
    },
    withCalendar(calendar) {
      var z = zdt(this);
      var ncal = toCalendarId(calendar);
      return wrapZoned(z.ns, z.tz, undefined, ncal);
    },
    add(temporalDurationLike, options) {
      var z = zdt(this);
      var d = toTemporalDurationRecord(temporalDurationLike);
      var overflow = getOverflow(getOptionsObject(options));
      return wrapZoned(addZoned(z.ns, z.tz, d, overflow, z.cal), z.tz, undefined, z.cal);
    },
    subtract(temporalDurationLike, options) {
      var z = zdt(this);
      var d = negateDuration(toTemporalDurationRecord(temporalDurationLike));
      var overflow = getOverflow(getOptionsObject(options));
      return wrapZoned(addZoned(z.ns, z.tz, d, overflow, z.cal), z.tz, undefined, z.cal);
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
        return wrapZoned(checkInstant(start + rounded * len), z.tz, undefined, z.cal);
      }
      var rt = roundDateTime(dt, increment, smallest, mode);
      return wrapZoned(interpretOffset(rt, 'option', tzOffsetAt(z.tz, z.ns), z.tz, 'compatible', 'prefer', false), z.tz, undefined, z.cal);
    },
    equals(other) {
      var z = zdt(this), o = toTemporalZoned(other);
      return z.ns === o.ns && sameTimeZone(z.tz, o.tz) && (z.cal === undefined ? 'iso8601' : z.cal) === (o.cal === undefined ? 'iso8601' : o.cal);
    },
    toString(options) {
      var z = zdt(this);
      options = getOptionsObject(options);
      var showCal = getCalendarNameOption(options);
      var showOffset;
      var showTz;
      var p = getSecondsPrecision(options, true, function () { showOffset = getShowOffsetOption(options); }, function () { showTz = getShowTimeZoneOption(options); });
      var rounded = roundAsIfPositive(z.ns, UNIT_NS[p.unit] * Big(p.inc), p.mode);
      checkInstant(rounded);
      return zonedString({ ns: rounded, tz: z.tz }, p.precision, showOffset, showTz, showCal);
    },
    toJSON() { return zonedString(zdt(this), 'auto', 'auto', 'auto', 'auto'); },
    toLocaleString() { return zonedString(zdt(this), 'auto', 'auto', 'auto', 'auto'); },
    valueOf() { throw new TypeErr('Temporal.ZonedDateTime cannot be converted to a primitive; use compare()'); },
    getTimeZoneTransition(directionParam) {
      zdt(this);
      if (directionParam === undefined) throw new TypeErr('direction is required');
      var opts;
      if (typeof directionParam === 'string') { opts = create(null); opts.direction = directionParam; }
      else opts = getOptionsObject(directionParam);
      var dir = getStringOption(opts, 'direction', ['next', 'previous'], undefined);
      if (dir === undefined) throw new RangeErr('direction is required');
      var zz = zdt(this);
      if (!zz.tz.named) return null;
      var tn = transitionNs(zz.tz, zz.ns, dir === 'next');
      return tn === null ? null : wrapZoned(tn, zz.tz, undefined, zz.cal);
    },
    startOfDay() { var z = zdt(this); return wrapZoned(startOfDayNs(z), z.tz, undefined, z.cal); },
    toInstant() { return wrapInstant(zdt(this).ns); },
    toPlainDateTime() { var dt = zdtDateTime(zdt(this)); return wrapDateTime(dt); },
    toPlainDate() { return wrapDate(zdtDateTime(zdt(this)).date); },
    toPlainTime() { return wrapTime(zdtDateTime(zdt(this)).time); }
  });
  defineLen(ZonedProto.withPlainTime, 0);
  defineLen(ZonedProto.toString, 0);
  defineLen(ZonedProto.toJSON, 0);
  defineLen(ZonedProto.toLocaleString, 0);
  defineLen(ZonedProto.startOfDay, 0);
