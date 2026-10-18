  // ---------------------------------------------------------------- ISO calendar and clock arithmetic
  function isLeap(y) { return y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0); }
  var MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  function daysInMonth(y, m) { return m === 2 ? (isLeap(y) ? 29 : 28) : MONTH_DAYS[m - 1]; }
  function epochDays(y, m, d) {
    if (m <= 2) y -= 1;
    var era = mathFloor(y / 400), yoe = y - era * 400, mp = (m + 9) % 12;
    var doy = mathFloor((153 * mp + 2) / 5) + d - 1;
    var doe = yoe * 365 + mathFloor(yoe / 4) - mathFloor(yoe / 100) + doy;
    return era * 146097 + doe - 719468;
  }
  function dateFromEpochDays(z) {
    z += 719468;
    var era = mathFloor(z / 146097), doe = z - era * 146097;
    var yoe = mathFloor((doe - mathFloor(doe / 1460) + mathFloor(doe / 36524) - mathFloor(doe / 146096)) / 365);
    var y = yoe + era * 400, doy = doe - (365 * yoe + mathFloor(yoe / 4) - mathFloor(yoe / 100));
    var mp = mathFloor((5 * doy + 2) / 153), d = doy - mathFloor((153 * mp + 2) / 5) + 1, m = mp < 10 ? mp + 3 : mp - 9;
    return { year: y + (m <= 2 ? 1 : 0), month: m, day: d };
  }
  function mkDate(y, m, d) { return { year: y, month: m, day: d }; }
  function dayOfWeek(y, m, d) { var z = epochDays(y, m, d); return (((z % 7) + 7 + 3) % 7) + 1; }
  function dayOfYear(y, m, d) { return epochDays(y, m, d) - epochDays(y, 1, 1) + 1; }
  function weeksInYear(y) {
    function p(x) { return (x + mathFloor(x / 4) - mathFloor(x / 100) + mathFloor(x / 400)) % 7; }
    return 52 + ((p(y) === 4 || p(y - 1) === 3) ? 1 : 0);
  }
  function weekInfo(y, m, d) {
    var week = mathFloor((dayOfYear(y, m, d) - dayOfWeek(y, m, d) + 10) / 7), year = y;
    if (week < 1) { year = y - 1; week = weeksInYear(year); }
    else if (week > weeksInYear(y)) { year = y + 1; week = 1; }
    return { week: week, year: year };
  }
  function compareDate(a, b) {
    if (a.year !== b.year) return a.year < b.year ? -1 : 1;
    if (a.month !== b.month) return a.month < b.month ? -1 : 1;
    if (a.day !== b.day) return a.day < b.day ? -1 : 1;
    return 0;
  }
  function dateWithinLimits(y, m, d) { var z = epochDays(y, m, d); return z >= -100000001 && z <= 100000000; }
  function yearMonthWithinLimits(y, m) {
    if (y < -271821 || y > 275760) return false;
    if (y === -271821 && m < 4) return false;
    if (y === 275760 && m > 9) return false;
    return true;
  }
  function isValidDate(y, m, d) { return m >= 1 && m <= 12 && d >= 1 && d <= daysInMonth(y, m); }
  function balanceDate(y, m, d) { return dateFromEpochDays(epochDays(y, m, 1) + d - 1); }
  // Year/month with the month carried into the year.
  function balanceYearMonth(y, m) {
    var mm = m - 1;
    y += mathFloor(mm / 12);
    mm = ((mm % 12) + 12) % 12;
    return { year: y, month: mm + 1 };
  }

  var NS_NUM_PER_DAY = 86400000000000;
  function isValidTime(h, mi, s, ms, us, ns) {
    return h >= 0 && h <= 23 && mi >= 0 && mi <= 59 && s >= 0 && s <= 59 && ms >= 0 && ms <= 999 && us >= 0 && us <= 999 && ns >= 0 && ns <= 999;
  }
  function mkTime(h, mi, s, ms, us, ns) { return { hour: h, minute: mi, second: s, millisecond: ms, microsecond: us, nanosecond: ns }; }
  function timeToNs(t) {
    return ((t.hour * 60 + t.minute) * 60 + t.second) * 1000000000 + t.millisecond * 1000000 + t.microsecond * 1000 + t.nanosecond;
  }
  function timeFromNs(n) {
    var h = mathFloor(n / 3600000000000); n -= h * 3600000000000;
    var mi = mathFloor(n / 60000000000); n -= mi * 60000000000;
    var s = mathFloor(n / 1000000000); n -= s * 1000000000;
    var ms = mathFloor(n / 1000000); n -= ms * 1000000;
    var us = mathFloor(n / 1000); n -= us * 1000;
    return mkTime(h, mi, s, ms, us, n);
  }
  function compareTime(a, b) { var x = timeToNs(a), y = timeToNs(b); return x < y ? -1 : x > y ? 1 : 0; }
  var MIDNIGHT = mkTime(0, 0, 0, 0, 0, 0);
  function epochNsOf(date, time) { return Big(epochDays(date.year, date.month, date.day)) * NS_PER_DAY + Big(timeToNs(time)); }
  var NS_MAX_INSTANT = 8640000000000000000000n;
  function dateTimeWithinLimits(date, time) {
    if (mathAbs(epochDays(date.year, date.month, date.day)) > 100000001) return false;
    var ns = epochNsOf(date, time);
    if (ns <= -NS_MAX_INSTANT - NS_PER_DAY) return false;
    if (ns >= NS_MAX_INSTANT + NS_PER_DAY) return false;
    return true;
  }
  function instantValid(ns) { return ns >= -NS_MAX_INSTANT && ns <= NS_MAX_INSTANT; }
  function floorDiv(a, b) { var q = a / b; return (a % b !== 0n && (a < 0n) !== (b < 0n)) ? q - 1n : q; }
  function floorMod(a, b) { var r = a % b; return (r !== 0n && (r < 0n) !== (b < 0n)) ? r + b : r; }
  // The date and time of a wall-clock nanosecond count since the epoch.
  function wallToDateTime(wall) {
    var days = floorDiv(wall, NS_PER_DAY), rem = floorMod(wall, NS_PER_DAY);
    return { date: dateFromEpochDays(Num(days)), time: timeFromNs(Num(rem)) };
  }

  // ---------------------------------------------------------------- options shared by the plain types
  function getOverflow(options) { return getStringOption(options, 'overflow', ['constrain', 'reject'], 'constrain'); }
  function getDisambiguation(options) { return getStringOption(options, 'disambiguation', ['compatible', 'earlier', 'later', 'reject'], 'compatible'); }
  function getOffsetOption(options, dflt) { return getStringOption(options, 'offset', ['prefer', 'use', 'ignore', 'reject'], dflt); }
  function getCalendarNameOption(options) { return getStringOption(options, 'calendarName', ['auto', 'always', 'never', 'critical'], 'auto'); }
  function getShowOffsetOption(options) { return getStringOption(options, 'offset', ['auto', 'never'], 'auto'); }
  function getShowTimeZoneOption(options) { return getStringOption(options, 'timeZoneName', ['auto', 'never', 'critical'], 'auto'); }
  function negateRoundingMode(m) {
    switch (m) {
      case 'ceil': return 'floor';
      case 'floor': return 'ceil';
      case 'halfCeil': return 'halfFloor';
      case 'halfFloor': return 'halfCeil';
      default: return m;
    }
  }
  function toPrimitive(v, hint) {
    if (!isObject(v)) return v;
    var ex = v[symToPrim];
    if (ex !== undefined && ex !== null) {
      if (typeof ex !== 'function') throw new TypeErr('@@toPrimitive is not callable');
      var r = apply(ex, v, [hint]);
      if (isObject(r)) throw new TypeErr('cannot convert object to primitive');
      return r;
    }
    var names = hint === 'string' ? ['toString', 'valueOf'] : ['valueOf', 'toString'];
    for (var i = 0; i < 2; i++) {
      var f = v[names[i]];
      if (typeof f === 'function') { var r2 = apply(f, v, []); if (!isObject(r2)) return r2; }
    }
    throw new TypeErr('cannot convert object to primitive');
  }
  function primitiveString(v) {
    var p = toPrimitive(v, 'string');
    if (typeof p !== 'string') throw new TypeErr('value must be a string');
    return p;
  }

  // Difference settings shared by until()/since(): returns {largest, smallest, increment, mode}.
  function getDifferenceSettings(sinceOp, options, group, disallowed, fallbackSmallest, smallestLargestDefault) {
    var largestRaw = options.largestUnit;
    if (largestRaw !== undefined) largestRaw = toStr(largestRaw);
    var increment = getRoundingIncrementOption(options);
    var mode = getRoundingModeOption(options, 'trunc');
    var smallestRaw = options.smallestUnit;
    if (smallestRaw !== undefined) smallestRaw = toStr(smallestRaw);
    var largest = largestRaw === undefined ? undefined : validateUnit(largestRaw, 'largestUnit', group, 'auto');
    var smallest = smallestRaw === undefined ? undefined : validateUnit(smallestRaw, 'smallestUnit', group);
    for (var i = 0; i < disallowed.length; i++) {
      if (largest === disallowed[i] || smallest === disallowed[i]) throw new RangeErr('unit is not allowed here');
    }
    if (smallest === undefined) smallest = fallbackSmallest;
    var defaultLargest = larger(smallestLargestDefault, smallest);
    if (largest === undefined || largest === 'auto') largest = defaultLargest;
    if (larger(largest, smallest) !== largest) throw new RangeErr('largestUnit must be larger than smallestUnit');
    var max = maxIncrement(smallest);
    if (max !== undefined) validateRoundingIncrement(increment, max, false);
    if (sinceOp) mode = negateRoundingMode(mode);
    return { largest: largest, smallest: smallest, increment: increment, mode: mode };
  }

  // ---------------------------------------------------------------- calendar and time zone identifiers
  var CALENDAR_ID = /^[A-Za-z0-9]{3,8}(?:-[A-Za-z0-9]{3,8})*$/;
  function canonicalCalendar(id) {
    var c = canonicalCalendarId(id);
    if (c === undefined) throw new RangeErr('unsupported calendar: ' + id);
    return c;
  }
  // A time-zone or calendar-bearing Temporal object is recognised through these registries (filled in by the types below).
  var carriers = [];
  function carrierCalendar(v) {
    for (var i = 0; i < carriers.length; i++) {
      if (carriers[i].has(v)) {
        var r = carriers[i].get(v);
        if (r.cal !== undefined) return r.cal;
        if (r.date !== undefined && r.date.cal !== undefined) return r.date.cal;
        return 'iso8601';
      }
    }
    return undefined;
  }
  function toCalendarId(c) {
    if (isObject(c)) {
      var found = carrierCalendar(c);
      if (found !== undefined) return found;
      throw new TypeErr('calendar must be a string');
    }
    if (typeof c !== 'string') throw new TypeErr('calendar must be a string');
    var rec;
    var kinds = ['datetime', 'monthday', 'yearmonth', 'time'];
    for (var i = 0; i < 4; i++) {
      try { rec = parseISOString(c, kinds[i]); break; } catch (e) { if (i === 3) rec = undefined; }
    }
    if (rec === undefined) {
      if (exec(CALENDAR_ID, c) !== null) return canonicalCalendar(c);
      throw new RangeErr('invalid calendar: ' + c);
    }
    return rec.calendar === undefined ? 'iso8601' : canonicalCalendar(rec.calendar);
  }
  function getCalendarFromBag(bag) {
    var c = bag.calendar;
    return c === undefined ? 'iso8601' : toCalendarId(c);
  }
  var tzIndex = null, tzLinkMap = null;
  // The canonical-case name of an IANA time zone identifier (zones and links alike), or undefined when it is not one.
  function tzLookup(id) {
    if (tzIndex === null) {
      tzIndex = create(null);
      var names = tzNames();
      for (var n = 0; n < names.length; n++) tzIndex[upper(names[n])] = names[n];
    }
    return tzIndex[upper(id)];
  }
  var UTC_FAMILY = ['UTC', 'ETC/UTC', 'ETC/GMT', 'GMT', 'UCT', 'ETC/UCT', 'ZULU', 'ETC/ZULU', 'ETC/UNIVERSAL', 'UNIVERSAL', 'ETC/GREENWICH', 'GREENWICH', 'GMT0', 'ETC/GMT0', 'ETC/GMT+0', 'ETC/GMT-0', 'GMT+0', 'GMT-0'];
  // The primary identifier a link name resolves to (zones are their own primary); the UTC family shares one.
  function tzPrimary(id) {
    var u = upper(id);
    for (var i = 0; i < UTC_FAMILY.length; i++) if (UTC_FAMILY[i] === u) return 'UTC';
    if (tzLinkMap === null) {
      tzLinkMap = create(null);
      var lines = apply(strSplit, tzLinks(), ['\n']);
      for (var l = 0; l < lines.length; l++) {
        var sp = apply(strIndexOf, lines[l], [' ']);
        if (sp > 0) tzLinkMap[upper(sliceS(lines[l], sp + 1))] = sliceS(lines[l], 0, sp);
      }
    }
    var guard = 0, cur = id;
    while (tzLinkMap[upper(cur)] !== undefined && guard++ < 10) cur = tzLinkMap[upper(cur)];
    var cu = upper(cur);
    for (var k = 0; k < UTC_FAMILY.length; k++) if (UTC_FAMILY[k] === cu) return 'UTC';
    return cur;
  }
  function sameTimeZone(a, b) {
    if (!a.named && !b.named && a.id !== 'UTC' && b.id !== 'UTC') return a.id === b.id;
    if ((!a.named && a.id !== 'UTC') || (!b.named && b.id !== 'UTC')) return false;
    return tzPrimary(a.id) === tzPrimary(b.id);
  }
  function tzNamed(id) { return tzLookup(id) !== undefined; }
  function tzOffsetAt(tz, ns) {
    if (!tz.named) return tz.offset;
    var s = tzOffsetSeconds(tz.id, Num(floorDiv(ns, NS.ms)));
    return s !== s ? 0 : s * 1000000000;
  }
  function formatOffsetNs(ns, subMinute) {
    var sign = ns < 0 ? '-' : '+', a = mathAbs(ns);
    var h = mathFloor(a / 3600000000000); a -= h * 3600000000000;
    var m = mathFloor(a / 60000000000); a -= m * 60000000000;
    var s = mathFloor(a / 1000000000); a -= s * 1000000000;
    var out = sign + pad(Str(h), 2) + ':' + pad(Str(m), 2);
    if (subMinute && (s !== 0 || a !== 0)) {
      out += ':' + pad(Str(s), 2);
      if (a !== 0) {
        var f = pad(Str(a), 9), e = 9;
        while (f[e - 1] === '0') e--;
        out += '.' + sliceS(f, 0, e);
      }
    }
    return out;
  }
