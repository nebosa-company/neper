  // ---------------------------------------------------------------- relativeTo for Duration
  // A relativeTo is {zoned: bool, date, ns, tz}: a plain date (at midnight) or a zoned date-time.
  function getRelativeTo(options) {
    var v = options.relativeTo;
    if (v === undefined) return undefined;
    var tz, ns, date, rec;
    if (isObject(v)) {
      if (zdtSlots.has(v)) { var zs = zdtSlots.get(v); return zonedRelative(zs.ns, zs.tz); }
      if (pdSlots.has(v)) return { zoned: false, date: copyDate(pdSlots.get(v)) };
      if (pdtSlots.has(v)) return { zoned: false, date: copyDate(pdtSlots.get(v).date) };
      getCalendarFromBag(v);
      var names = ZONED_NAMES.slice();
      names.splice(names.length - 1, 0, 'timeZone');
      var r = prepareFields(v, names), f = r.fields;
      var offsetNs, behaviour = 'wall';
      if (f.offset !== undefined) { offsetNs = parseOffsetString(f.offset, true); behaviour = 'option'; }
      if (f.timeZone === undefined) {
        return { zoned: false, date: dateFromFields(f, 'constrain') };
      }
      tz = toTimeZone(f.timeZone);
      var dt = dateTimeFromFields(f, 'constrain');
      ns = interpretOffset(dt, behaviour, offsetNs, tz, 'compatible', 'reject', false);
      return zonedRelative(ns, tz);
    }
    if (typeof v !== 'string') throw new TypeErr('relativeTo must be a string or an object');
    rec = parseISOString(v, 'zoned');
    if (!rec.hasDate) throw new RangeErr('invalid relativeTo string');
    if (rec.calendar !== undefined) canonicalCalendar(rec.calendar);
    if (rec.tz === undefined) {
      if (rec.z) throw new RangeErr('a UTC designator needs a time zone annotation');
      if (!dateWithinLimits(rec.year, rec.month, rec.day)) throw new RangeErr('date out of range');
      return { zoned: false, date: mkDate(rec.year, rec.month, rec.day) };
    }
    if (exec(RE_TZ_OFFSET_ANN, rec.tz) !== null) tz = offsetZone(parseOffsetString(rec.tz, false));
    else if (tzNamed(rec.tz)) tz = UTC_ZONE;
    else throw new RangeErr('unsupported time zone: ' + rec.tz);
    var behaviour2 = rec.z ? 'exact' : rec.offsetNs !== undefined ? 'option' : 'wall';
    var dt2 = { date: mkDate(rec.year, rec.month, rec.day), time: mkTime(rec.hour, rec.minute, rec.second, rec.millisecond, rec.microsecond, rec.nanosecond) };
    ns = interpretOffset(dt2, behaviour2, rec.offsetNs === undefined ? 0 : rec.offsetNs, tz, 'compatible', 'reject', true);
    return zonedRelative(ns, tz);
  }
  // The start of the local day of a zoned relativeTo has to be representable too.
  function zonedRelative(ns, tz) {
    var local = wallToDateTime(ns + Big(tz.offset));
    checkInstant(epochNsOf(local.date, MIDNIGHT) - Big(tz.offset));
    return { zoned: true, ns: ns, tz: tz };
  }
  // The origin as a local date-time and the wall-clock nanosecond count of both it and `d` added to it.
  function relOrigin(rel) {
    if (rel.zoned) return wallToDateTime(rel.ns + Big(rel.tz.offset));
    return { date: rel.date, time: MIDNIGHT };
  }
  function relTargetWall(rel, d) {
    if (rel.zoned) return addZoned(rel.ns, rel.tz, d, 'constrain') + Big(rel.tz.offset);
    var tr = addTimeNs(MIDNIGHT, timeDurationNs(d));
    var date = addDate(rel.date, d.years, d.months, d.weeks, d.days + tr.days, 'constrain');
    return epochNsOfDateAt(date, timeToNs(tr.time));
  }
  function relOriginWall(rel) {
    return rel.zoned ? rel.ns + Big(rel.tz.offset) : epochNsOfDateAt(rel.date, 0);
  }
  function relativeCompare(a, b, rel) {
    var x, y;
    var dated = a.years || a.months || a.weeks || b.years || b.months || b.weeks;
    if (rel.zoned ? (dated || a.days || b.days) : dated) {
      if (rel.zoned) { x = relTargetWall(rel, a); y = relTargetWall(rel, b); }
      else {
        var o = epochDays(rel.date.year, rel.date.month, rel.date.day);
        function days(d) {
          var t = addDate(rel.date, d.years, d.months, d.weeks, d.days, 'constrain');
          var total = Big(epochDays(t.year, t.month, t.day) - o) * NS_PER_DAY + timeNsOnly(d);
          if (absBig(total) >= 9007199254740992000000000n) throw new RangeErr('duration out of range');
          return total;
        }
        x = days(a); y = days(b);
      }
    } else { x = timeNs(a); y = timeNs(b); }
    return x < y ? -1 : x > y ? 1 : 0;
  }
  function timeNsOnly(d) { return timeNs(newDurationRecord(0, 0, 0, 0, d.hours, d.minutes, d.seconds, d.milliseconds, d.microseconds, d.nanoseconds)); }
  function checkNextDay(rel) {
    if (rel.zoned) addZoned(rel.ns, rel.tz, newDurationRecord(0, 0, 0, 1, 0, 0, 0, 0, 0, 0), 'constrain');
  }
  function blankDuration(d) { return durationSign(d) === 0; }
  function relativeRound(d, rel, largest, increment, smallest, mode) {
    if (rel.zoned && isDateUnit(largest) && !(smallest === 'nanosecond' && increment === 1)) checkNextDay(rel);
    if (blankDuration(d)) return d;
    if (!rel.zoned) checkDateTime(rel.date, MIDNIGHT);
    var origin = relOrigin(rel), targetWall = relTargetWall(rel, d);
    var originWall = relOriginWall(rel);
    if (rel.zoned && !isDateUnit(largest)) {
      var norm = roundNumberToIncrement(targetWall - originWall, UNIT_NS[smallest] * Big(increment), mode);
      var parts = balanceTime(norm, largest);
      return fixZeros(createDurationRecord(0, 0, 0, 0, parts.hours, parts.minutes, parts.seconds, parts.milliseconds, parts.microseconds, parts.nanoseconds));
    }
    var di = differenceWithRounding(origin, wallToDateTime(targetWall), largest, increment, smallest, mode, rel.zoned);
    return internalToRecord(di, largest);
  }
  function relativeTotal(d, rel, unit) {
    if (rel.zoned && isDateUnit(unit)) checkNextDay(rel);
    if (blankDuration(d)) return 0;
    if (!rel.zoned) checkDateTime(rel.date, MIDNIGHT);
    var origin = relOrigin(rel), targetWall = relTargetWall(rel, d), originWall = relOriginWall(rel);
    if (isCalendarUnit(unit)) {
      var target = wallToDateTime(targetWall);
      if (compareDate(origin.date, target.date) === 0 && compareTime(origin.time, target.time) === 0) return 0;
      var di = differenceISODateTime(origin, target, unit);
      return totalCalendar(di, targetWall, origin.date, timeToNs(origin.time), unit);
    }
    return divToNumber(targetWall - originWall, UNIT_NS[unit]);
  }
