  // ---------------------------------------------------------------- calendar-aware duration arithmetic (ISO calendar)
  // An "internal" duration is {years, months, weeks, days, norm} with norm the BigInt nanoseconds of hours..nanoseconds.
  function toInternal(d) {
    return { years: d.years, months: d.months, weeks: d.weeks, days: d.days,
      norm: Big(d.hours) * NS.h + Big(d.minutes) * NS.min + Big(d.seconds) * NS.s + Big(d.milliseconds) * NS.ms + Big(d.microseconds) * 1000n + Big(d.nanoseconds) };
  }
  function internalSign(di) {
    if (di.years !== 0) return di.years < 0 ? -1 : 1;
    if (di.months !== 0) return di.months < 0 ? -1 : 1;
    if (di.weeks !== 0) return di.weeks < 0 ? -1 : 1;
    if (di.days !== 0) return di.days < 0 ? -1 : 1;
    return di.norm < 0n ? -1 : di.norm > 0n ? 1 : 0;
  }
  function internalToRecord(di, largest) {
    var li = unitIndex(largest), days = di.days, norm = di.norm;
    var parts;
    if (li <= 3) {
      parts = balanceTime(norm, 'day');
      days += parts.days;
    } else {
      norm += Big(days) * NS_PER_DAY;
      days = 0;
      parts = balanceTime(norm, largest);
    }
    return fixZeros(createDurationRecord(di.years, di.months, di.weeks, days, parts.hours, parts.minutes, parts.seconds, parts.milliseconds, parts.microseconds, parts.nanoseconds));
  }

  function addDate(date, years, months, weeks, days, overflow) {
    var ym = balanceYearMonth(date.year + years, date.month + months);
    var day = date.day, dim = daysInMonth(ym.year, ym.month);
    if (day > dim) {
      if (overflow === 'reject') throw new RangeErr('day out of range');
      day = dim;
    }
    var r = balanceDate(ym.year, ym.month, day + days + 7 * weeks);
    if (!dateWithinLimits(r.year, r.month, r.day)) throw new RangeErr('date out of range');
    return r;
  }
  function dateSurpasses(sign, y1, m1, d1, b) {
    d1 = mathMin(d1, daysInMonth(y1, m1));
    if (y1 !== b.year) return sign * (y1 - b.year) > 0;
    if (m1 !== b.month) return sign * (m1 - b.month) > 0;
    if (d1 !== b.day) return sign * (d1 - b.day) > 0;
    return false;
  }
  function differenceDate(a, b, largest) {
    var sign = -compareDate(a, b);
    var years = 0, months = 0, weeks = 0, days = 0;
    if (sign === 0) return { years: 0, months: 0, weeks: 0, days: 0 };
    if (largest === 'year' || largest === 'month') {
      var k;
      if (largest === 'year') {
        k = b.year - a.year;
        while (dateSurpasses(sign, a.year + k, a.month, a.day, b)) k -= sign;
        while (!dateSurpasses(sign, a.year + k + sign, a.month, a.day, b)) k += sign;
        years = k;
      }
      var base = a.year + years;
      k = (b.year - base) * 12 + (b.month - a.month);
      var inter = balanceYearMonth(base, a.month + k);
      while (dateSurpasses(sign, inter.year, inter.month, a.day, b)) { k -= sign; inter = balanceYearMonth(base, a.month + k); }
      inter = balanceYearMonth(base, a.month + k + sign);
      while (!dateSurpasses(sign, inter.year, inter.month, a.day, b)) { k += sign; inter = balanceYearMonth(base, a.month + k + sign); }
      months = k;
    }
    var im = balanceYearMonth(a.year + years, a.month + months);
    var constrained = mkDate(im.year, im.month, mathMin(a.day, daysInMonth(im.year, im.month)));
    days = epochDays(b.year, b.month, b.day) - epochDays(constrained.year, constrained.month, constrained.day);
    if (largest === 'week') {
      weeks = mathTrunc(days / 7);
      days = days - weeks * 7;
    }
    return { years: years === 0 ? 0 : years, months: months === 0 ? 0 : months, weeks: weeks === 0 ? 0 : weeks, days: days === 0 ? 0 : days };
  }
  // b - a for the clock times, in nanoseconds (BigInt).
  function differenceTime(a, b) { return Big(timeToNs(b) - timeToNs(a)); }
  function differenceISODateTime(a, b, largest) {
    var norm = differenceTime(a.time, b.time);
    var timeSign = norm < 0n ? -1 : norm > 0n ? 1 : 0;
    var dateSign = -compareDate(a.date, b.date);
    var adj = b.date;
    if (timeSign === -dateSign) {
      adj = balanceDate(adj.year, adj.month, adj.day + timeSign);
      norm -= Big(timeSign) * NS_PER_DAY;
    }
    var dateLargest = larger('day', largest);
    var dd = differenceDate(a.date, adj, dateLargest);
    if (largest !== dateLargest) {
      norm += Big(dd.days) * NS_PER_DAY;
      dd.days = 0;
    }
    return { years: dd.years, months: dd.months, weeks: dd.weeks, days: dd.days, norm: norm };
  }

  function unsignedMode(mode, sign) {
    var neg = sign < 0;
    switch (mode) {
      case 'ceil': return neg ? 'zero' : 'infinity';
      case 'floor': return neg ? 'infinity' : 'zero';
      case 'expand': return 'infinity';
      case 'trunc': return 'zero';
      case 'halfCeil': return neg ? 'half-zero' : 'half-infinity';
      case 'halfFloor': return neg ? 'half-infinity' : 'half-zero';
      case 'halfExpand': return 'half-infinity';
      case 'halfTrunc': return 'half-zero';
      default: return 'half-even';
    }
  }
  // Picks r1 or r2 for the position num/den (in [0, 1]) between them.
  function applyUnsigned(num, den, r1, r2, um, increment) {
    if (num === 0n) return r1;
    if (num === den) return r2;
    if (um === 'zero') return r1;
    if (um === 'infinity') return r2;
    var twice = num * 2n;
    if (twice < den) return r1;
    if (twice > den) return r2;
    if (um === 'half-zero') return r1;
    if (um === 'half-infinity') return r2;
    return (r1 / increment) % 2 === 0 ? r1 : r2;
  }
  function epochNsOfDateAt(date, timeNs) { return Big(epochDays(date.year, date.month, date.day)) * NS_PER_DAY + Big(timeNs); }

  function dateDuration(sign, y, mo, w, d) {
    return { years: y, months: mo, weeks: w, days: d };
  }
  // Rounds a calendar unit; returns {dur, total: [num, den, r1, sign], expanded, ns}.
  function nudgeCalendar(sign, dur, destNs, originDate, originTimeNs, increment, unit, mode) {
    var r1, r2, start, end;
    var y = dur.years, mo = dur.months, w = dur.weeks, d = dur.days;
    var inc = Big(increment);
    switch (unit) {
      case 'year':
        r1 = Num(roundNumberToIncrement(Big(y), inc, 'trunc')); r2 = r1 + increment * sign;
        start = [r1, 0, 0, 0]; end = [r2, 0, 0, 0];
        break;
      case 'month':
        r1 = Num(roundNumberToIncrement(Big(mo), inc, 'trunc')); r2 = r1 + increment * sign;
        start = [y, r1, 0, 0]; end = [y, r2, 0, 0];
        break;
      case 'week':
        var wStart = addDate(originDate, y, mo, 0, 0, 'constrain');
        var wEnd = balanceDate(wStart.year, wStart.month, wStart.day + d);
        w += differenceDate(wStart, wEnd, 'week').weeks;
        r1 = Num(roundNumberToIncrement(Big(w), inc, 'trunc')); r2 = r1 + increment * sign;
        start = [y, mo, r1, 0]; end = [y, mo, r2, 0];
        break;
      default:
        r1 = Num(roundNumberToIncrement(Big(d), inc, 'trunc')); r2 = r1 + increment * sign;
        start = [y, mo, w, r1]; end = [y, mo, w, r2];
    }
    var sd = addDate(originDate, start[0], start[1], start[2], start[3], 'constrain');
    var ed = addDate(originDate, end[0], end[1], end[2], end[3], 'constrain');
    var startNs = epochNsOfDateAt(sd, originTimeNs), endNs = epochNsOfDateAt(ed, originTimeNs);
    if (sign === 1 ? (startNs > destNs || destNs > endNs) : (startNs < destNs || destNs < endNs)) throw new RangeErr('duration out of range');
    var num = destNs - startNs, den = endNs - startNs;
    if (den < 0n) { num = -num; den = -den; }
    var a1 = mathAbs(r1), a2 = mathAbs(r2);
    var rounded = applyUnsigned(num, den, a1, a2, unsignedMode(mode, sign), increment);
    var expanded = rounded === a2;
    var ru = rounded * sign;
    var out = { years: y, months: mo, weeks: w, days: d, norm: 0n };
    switch (unit) {
      case 'year': out.years = ru; out.months = 0; out.weeks = 0; out.days = 0; break;
      case 'month': out.months = ru; out.weeks = 0; out.days = 0; break;
      case 'week': out.weeks = ru; out.days = 0; break;
      default: out.days = ru;
    }
    return { dur: out, expanded: expanded, ns: expanded ? endNs : startNs, total: { num: num, den: den, r1: r1, sign: sign, increment: increment } };
  }
  function nudgeTime(sign, dur, destNs, increment, unit, mode) {
    var total = dur.norm + Big(dur.days) * NS_PER_DAY;
    var unitNs = UNIT_NS[unit] * Big(increment);
    var rounded = roundNumberToIncrement(total, unitNs, mode);
    var diff = rounded - total;
    var whole = total / NS_PER_DAY, rwhole = rounded / NS_PER_DAY;
    var delta = rwhole - whole;
    var expanded = delta !== 0n && ((delta < 0n ? -1 : 1) === sign);
    var rem = rounded - rwhole * NS_PER_DAY;
    return { dur: { years: dur.years, months: dur.months, weeks: dur.weeks, days: Num(rwhole), norm: rem }, expanded: expanded, ns: destNs + diff };
  }
  // Rounding a zoned duration to a time unit: the days are kept apart and the time is rounded against the length of the day.
  function nudgeZoned(sign, dur, destNs, originDate, originTimeNs, increment, unit, mode) {
    var unitNs = UNIT_NS[unit] * Big(increment);
    var startDate = addDate(originDate, dur.years, dur.months, dur.weeks, dur.days, 'constrain');
    var endDate = addDate(originDate, dur.years, dur.months, dur.weeks, dur.days + sign, 'constrain');
    var startNs = epochNsOfDateAt(startDate, originTimeNs), endNs = epochNsOfDateAt(endDate, originTimeNs);
    var span = endNs - startNs;
    var rounded = roundNumberToIncrement(dur.norm, unitNs, mode);
    var beyond = rounded - span;
    var bsign = beyond < 0n ? -1 : beyond > 0n ? 1 : 0;
    var expanded = bsign !== -sign, days = dur.days, nudged;
    if (expanded) {
      days += sign;
      rounded = roundNumberToIncrement(beyond, unitNs, mode);
      nudged = endNs + rounded;
    } else nudged = startNs + rounded;
    return { dur: { years: dur.years, months: dur.months, weeks: dur.weeks, days: days, norm: rounded }, expanded: expanded, ns: nudged };
  }
  function bubble(sign, dur, nudgedNs, originDate, originTimeNs, largest, smallest) {
    if (smallest === largest) return dur;
    var li = unitIndex(largest), si = unitIndex(smallest), i = mathMin(si - 1, 3), done = false;
    var out = dur;
    while (i >= li && !done) {
      var unit = UNITS[i];
      if (unit !== 'week' || largest === 'week') {
        var y = out.years, mo = out.months, w = out.weeks, d = out.days;
        var e;
        switch (unit) {
          case 'year': e = [y + sign, 0, 0, 0]; break;
          case 'month': e = [y, mo + sign, 0, 0]; break;
          case 'week': e = [y, mo, w + sign, 0]; break;
          default: e = [y, mo, w, d + sign];
        }
        var ed = addDate(originDate, e[0], e[1], e[2], e[3], 'constrain');
        var endNs = epochNsOfDateAt(ed, originTimeNs);
        var beyond = nudgedNs - endNs;
        var expandedToEnd = beyond === 0n || (beyond < 0n ? -1 : 1) === sign;
        if (expandedToEnd) out = { years: e[0], months: e[1], weeks: e[2], days: e[3], norm: 0n };
        else done = true;
      }
      i--;
    }
    return out;
  }
  // RoundRelativeDuration: `dur` is internal; destNs the wall-clock nanoseconds of the end point.
  function roundRelative(dur, destNs, originDate, originTimeNs, largest, increment, smallest, mode, zoned) {
    var sign = internalSign(dur);
    if (sign === 0) return dur;
    var n;
    if (isCalendarUnit(smallest) || (zoned && smallest === 'day')) n = nudgeCalendar(sign, dur, destNs, originDate, originTimeNs, increment, smallest, mode);
    else if (zoned) n = nudgeZoned(sign, dur, destNs, originDate, originTimeNs, increment, smallest, mode);
    else n = nudgeTime(sign, dur, destNs, increment, smallest, mode);
    var result = n.dur;
    if (n.expanded && smallest !== 'week') result = bubble(sign, result, n.ns, originDate, originTimeNs, largest, smallest);
    return result;
  }
  // The exact value of `dur` in `unit` for a calendar unit (a Number).
  function totalCalendar(dur, destNs, originDate, originTimeNs, unit) {
    var sign = internalSign(dur);
    if (sign === 0) return 0;
    var n = nudgeCalendar(sign, dur, destNs, originDate, originTimeNs, 1, unit, 'trunc');
    var t = n.total;
    return divToNumber(Big(t.r1) * t.den + Big(t.sign) * t.num, t.den);
  }
  // DifferenceISODateTime followed by rounding to a smallest unit and increment.
  function differenceWithRounding(a, b, largest, increment, smallest, mode, zoned) {
    if (compareDate(a.date, b.date) === 0 && compareTime(a.time, b.time) === 0) return { years: 0, months: 0, weeks: 0, days: 0, norm: 0n };
    var diff = differenceISODateTime(a, b, largest);
    if (smallest === 'nanosecond' && increment === 1) return diff;
    return roundRelative(diff, epochNsOf(b.date, b.time), a.date, timeToNs(a.time), largest, increment, smallest, mode, zoned);
  }
