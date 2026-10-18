
  // ---------------------------------------------------------------- calendar systems
  // Every calendar maps between epoch days (days since 1970-01-01) and its own (year, ordinal month, day). The ISO calendar is the
  // default and is handled by the code elsewhere; the systems here are the non-ISO ones, built over the Gregorian arithmetic
  // (gregory, buddhist, roc, japanese), the fixed-length-month systems (coptic, ethiopic, ethioaa, indian, persian, islamic variants)
  // and the Hebrew calendar.
  var CALS = create(null);
  function floorDivN(a, b) { return mathFloor(a / b); }
  function modN(a, b) { return a - b * mathFloor(a / b); }
  var RD_UNIX = 719163;

  function monthCodeFor(m, leap) { return 'M' + pad(Str(m), 2) + (leap ? 'L' : ''); }

  // ---- Gregorian-based
  function gregorianBased(id, yearOffset, eras) {
    var cal = {
      id: id, hasEras: true, eras: eras,
      fromDays: function (days) { var d = dateFromEpochDays(days); return { year: d.year + yearOffset, month: d.month, day: d.day }; },
      toDays: function (y, m, d) { return epochDays(y - yearOffset, m, d); },
      monthsInYear: function (y) { return 12; },
      daysInMonth: function (y, m) { return daysInMonth(y - yearOffset, m); },
      daysInYear: function (y) { return isLeap(y - yearOffset) ? 366 : 365; },
      inLeapYear: function (y) { return isLeap(y - yearOffset); },
      monthCode: function (y, m) { return monthCodeFor(m, false); },
      monthFromCode: function (y, code, overflow) { var m = codeNumber(code); return m >= 1 && m <= 12 && !code.leap ? m : 0; }
    };
    return cal;
  }
  // The number and leap flag of a month code ("M05L").
  function parseMonthCode(code) {
    var m = exec(RE_MONTH_CODE, code);
    if (m === null) return null;
    return { number: +m[1], leap: m[2] === 'L' };
  }
  function codeNumber(code) { var p = typeof code === 'string' ? parseMonthCode(code) : code; return p === null ? 0 : p.number; }

  // ---- fixed-month-length calendars with a thirteenth short month: coptic, ethiopic
  function africanCalendar(id, epochRD, yearBias, eras) {
    return {
      id: id, hasEras: true, eras: eras,
      fromDays: function (days) {
        var rd = days + RD_UNIX, year = floorDivN(4 * (rd - epochRD) + 1463, 1461);
        var yearStart = epochRD - 1 + 365 * (year - 1) + floorDivN(year, 4) + 1;
        var left = rd - yearStart, month = mathMin(floorDivN(left, 30) + 1, 13);
        return { year: year + yearBias, month: month, day: left - 30 * (month - 1) + 1 };
      },
      toDays: function (y, m, d) { y -= yearBias; return epochRD + 365 * (y - 1) + floorDivN(y, 4) + 30 * (m - 1) + d - 1 - RD_UNIX; },
      monthsInYear: function () { return 13; },
      daysInMonth: function (y, m) { return m < 13 ? 30 : (modN(y - yearBias, 4) === 3 ? 6 : 5); },
      daysInYear: function (y) { return modN(y - yearBias, 4) === 3 ? 366 : 365; },
      inLeapYear: function (y) { return modN(y - yearBias, 4) === 3; },
      monthCode: function (y, m) { return monthCodeFor(m, false); },
      monthFromCode: function (y, code) { return code.leap ? 0 : (code.number >= 1 && code.number <= 13 ? code.number : 0); }
    };
  }
  // ---- Indian national calendar
  function indianCalendar() {
    function leap(y) { return isLeap(y + 78); }
    function yearStart(y) { return epochDays(y + 78, 3, leap(y) ? 21 : 22); }
    var MLEN = [30, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 30];
    return {
      id: 'indian', hasEras: true,
      eras: [{ name: 'shaka', aliases: [], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; }, start: null }],
      fromDays: function (days) {
        var iso = dateFromEpochDays(days), y = iso.year - 78;
        if (days < yearStart(y)) y -= 1; else if (days >= yearStart(y + 1)) y += 1;
        var left = days - yearStart(y), m = 1;
        while (true) {
          var len = m === 1 && leap(y) ? 31 : MLEN[m - 1];
          if (left < len) break;
          left -= len; m++;
        }
        return { year: y, month: m, day: left + 1 };
      },
      toDays: function (y, m, d) { var n = yearStart(y); for (var i = 1; i < m; i++) n += (i === 1 && leap(y)) ? 31 : MLEN[i - 1]; return n + d - 1; },
      monthsInYear: function () { return 12; },
      daysInMonth: function (y, m) { return m === 1 && leap(y) ? 31 : MLEN[m - 1]; },
      daysInYear: function (y) { return leap(y) ? 366 : 365; },
      inLeapYear: function (y) { return leap(y); },
      monthCode: function (y, m) { return monthCodeFor(m, false); },
      monthFromCode: function (y, code) { return code.leap ? 0 : (code.number >= 1 && code.number <= 12 ? code.number : 0); }
    };
  }
  // ---- Persian (33-year arithmetic rule)
  function persianCalendar() {
    var LEAPS = [1, 5, 9, 13, 17, 22, 26, 30];
    function leap(y) { return includesNum(LEAPS, modN(y, 33)); }
    function leapsThrough(n) {
      var q = floorDivN(n, 33), r = modN(n, 33), c = q * 8;
      for (var i = 0; i < LEAPS.length; i++) if (LEAPS[i] <= r) c++;
      return c;
    }
    var EPOCH_DAYS = epochDays(2021, 3, 21) - (365 * 1399 + leapsThrough(1399));
    function yearStart(y) { return EPOCH_DAYS + 365 * (y - 1) + leapsThrough(y - 1); }
    return {
      id: 'persian', hasEras: true,
      eras: [{ name: 'ap', aliases: [], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; }, start: null }],
      fromDays: function (days) {
        var y = floorDivN((days - EPOCH_DAYS) * 33, 12053) + 1;
        while (yearStart(y + 1) <= days) y++;
        while (yearStart(y) > days) y--;
        var left = days - yearStart(y);
        if (left < 186) return { year: y, month: floorDivN(left, 31) + 1, day: modN(left, 31) + 1 };
        left -= 186;
        return { year: y, month: 7 + floorDivN(left, 30), day: modN(left, 30) + 1 };
      },
      toDays: function (y, m, d) { return yearStart(y) + (m <= 6 ? (m - 1) * 31 : 186 + (m - 7) * 30) + d - 1; },
      monthsInYear: function () { return 12; },
      daysInMonth: function (y, m) { return m <= 6 ? 31 : (m <= 11 ? 30 : (leap(y) ? 30 : 29)); },
      daysInYear: function (y) { return leap(y) ? 366 : 365; },
      inLeapYear: function (y) { return leap(y); },
      monthCode: function (y, m) { return monthCodeFor(m, false); },
      monthFromCode: function (y, code) { return code.leap ? 0 : (code.number >= 1 && code.number <= 12 ? code.number : 0); }
    };
  }
  function includesNum(a, v) { for (var i = 0; i < a.length; i++) if (a[i] === v) return true; return false; }
  // ---- tabular Islamic calendars
  function islamicCalendar(id, epochRD) {
    function fixed(y, m, d) { return epochRD - 1 + (y - 1) * 354 + floorDivN(3 + 11 * y, 30) + 29 * (m - 1) + floorDivN(m, 2) + d; }
    function leap(y) { return modN(14 + 11 * y, 30) < 11; }
    return {
      id: id, hasEras: true,
      eras: [{ name: 'ah', aliases: [], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; }, start: null, minYear: 1 },
        { name: 'bh', aliases: [], yearFor: function (ey) { return 1 - ey; }, eraYear: function (y) { return 1 - y; }, start: null, maxYear: 0 }],
      fromDays: function (days) {
        var rd = days + RD_UNIX, y = floorDivN(30 * (rd - epochRD) + 10646, 10631);
        var prior = rd - fixed(y, 1, 1), m = mathMin(12, floorDivN(11 * prior + 330, 325));
        return { year: y, month: m, day: rd - fixed(y, m, 1) + 1 };
      },
      toDays: function (y, m, d) { return fixed(y, m, d) - RD_UNIX; },
      monthsInYear: function () { return 12; },
      daysInMonth: function (y, m) { return m % 2 === 1 ? 30 : (m === 12 && leap(y) ? 30 : 29); },
      daysInYear: function (y) { return leap(y) ? 355 : 354; },
      inLeapYear: function (y) { return leap(y); },
      monthCode: function (y, m) { return monthCodeFor(m, false); },
      monthFromCode: function (y, code) { return code.leap ? 0 : (code.number >= 1 && code.number <= 12 ? code.number : 0); }
    };
  }
  // ---- Hebrew
  function hebrewCalendar() {
    var EPOCH = -1373427;
    function leap(y) { return modN(7 * y + 1, 19) < 7; }
    function monthCount(y) { return leap(y) ? 13 : 12; }
    function elapsed(y) {
      var months = floorDivN(235 * y - 234, 19), parts = 12084 + 13753 * months, day = 29 * months + floorDivN(parts, 25920);
      if (modN(3 * (day + 1), 7) < 3) day++;
      return day;
    }
    function newYear(y) {
      var n0 = elapsed(y - 1), n1 = elapsed(y), n2 = elapsed(y + 1), corr = 0;
      if (n2 - n1 === 356) corr = 2; else if (n1 - n0 === 382) corr = 1;
      return EPOCH + n1 + corr;
    }
    function yearLength(y) { return newYear(y + 1) - newYear(y); }
    // scriptural number: Nisan 1 .. Adar 12 (Adar I in a leap year), Adar II 13
    function scriptural(y, civil) {
      var l = leap(y);
      if (civil <= 6) return civil + 6;
      if (l) return civil === 7 ? 13 : civil - 7;
      return civil - 6;
    }
    function civilOf(y, s) { return s >= 7 ? s - 6 : s + monthCount(y) - 6; }
    function scripturalLength(y, s) {
      if (s === 2 || s === 4 || s === 6 || s === 10 || s === 13) return 29;
      if (s === 12 && !leap(y)) return 29;
      var len = yearLength(y);
      if (s === 8 && len !== 355 && len !== 385) return 29;
      if (s === 9 && (len === 353 || len === 383)) return 29;
      return 30;
    }
    function civilLength(y, c) { return scripturalLength(y, scriptural(y, c)); }
    return {
      id: 'hebrew', hasEras: true,
      eras: [{ name: 'am', aliases: [], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; }, start: null }],
      fromDays: function (days) {
        var rd = days + RD_UNIX, y = floorDivN((rd - EPOCH) * 98496, 35975351);
        while (newYear(y + 1) <= rd) y++;
        while (newYear(y) > rd) y--;
        var left = rd - newYear(y), m = 1;
        while (m < monthCount(y)) {
          var len = civilLength(y, m);
          if (left < len) break;
          left -= len; m++;
        }
        return { year: y, month: m, day: left + 1 };
      },
      toDays: function (y, m, d) {
        var n = newYear(y) + d - 1;
        for (var c = 1; c < m; c++) n += civilLength(y, c);
        return n - RD_UNIX;
      },
      monthsInYear: function (y) { return monthCount(y); },
      daysInMonth: function (y, m) { return civilLength(y, m); },
      daysInYear: function (y) { return yearLength(y); },
      inLeapYear: function (y) { return leap(y); },
      monthCode: function (y, m) {
        var s = scriptural(y, m);
        // civil Tishri..Elul; Adar I is M05L in a leap year, Adar II is M06
        var table = { 7: 'M07', 8: 'M08', 9: 'M09', 10: 'M10', 11: 'M11', 12: 'M12', 1: 'M01', 2: 'M02', 3: 'M03', 4: 'M04', 5: 'M05', 6: 'M06' };
        // month numbering by code: M01 Tishri ... M05 Shevat, M05L Adar I, M06 Adar (II), M07 Nisan ... M12 Elul
        if (m <= 5) return monthCodeFor(m, false);
        if (leap(y)) { if (m === 6) return 'M05L'; return monthCodeFor(m - 1, false); }
        return monthCodeFor(m, false);
      },
      monthFromCode: function (y, code) {
        var n = code.number;
        if (n < 1 || n > 12) return 0;
        if (code.leap) return (n === 5 && leap(y)) ? 6 : 0;
        if (n <= 5) return n;
        return leap(y) ? n + 1 : n;
      }
    };
  }

  var GREGORY_ERAS = [
    { name: 'ce', aliases: ['ad'], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; }, minYear: 1 },
    { name: 'bce', aliases: ['bc'], yearFor: function (ey) { return 1 - ey; }, eraYear: function (y) { return 1 - y; }, maxYear: 0 }
  ];
  CALS.gregory = gregorianBased('gregory', 0, GREGORY_ERAS);
  CALS.buddhist = gregorianBased('buddhist', 543, [{ name: 'be', aliases: [], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; } }]);
  CALS.roc = gregorianBased('roc', -1911, [
    { name: 'roc', aliases: [], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; }, minYear: 1 },
    { name: 'broc', aliases: [], yearFor: function (ey) { return 1 - ey; }, eraYear: function (y) { return 1 - y; }, maxYear: 0 }]);
  // Japanese eras ride the Gregorian year; an era is a start date and its years count from the Gregorian year of that date.
  var JAPANESE_ERAS = [
    { name: 'reiwa', start: [2019, 5, 1], base: 2019 }, { name: 'heisei', start: [1989, 1, 8], base: 1989 }, { name: 'showa', start: [1926, 12, 25], base: 1926 },
    { name: 'taisho', start: [1912, 7, 30], base: 1912 }, { name: 'meiji', start: [1873, 1, 1], base: 1868 }
  ];
  CALS.japanese = gregorianBased('japanese', 0, []);
  CALS.japanese.japanese = true;
  CALS.coptic = africanCalendar('coptic', 103605, 0, [{ name: 'am', aliases: [], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; } }]);
  CALS.ethiopic = africanCalendar('ethiopic', 2796, 0, []);
  CALS.ethiopic.ethiopic = true;
  CALS.ethioaa = africanCalendar('ethioaa', 2796, 5500, [{ name: 'aa', aliases: [], yearFor: function (ey) { return ey; }, eraYear: function (y) { return y; } }]);
  CALS.indian = indianCalendar();
  CALS.persian = persianCalendar();
  CALS.hebrew = hebrewCalendar();
  CALS['islamic-civil'] = islamicCalendar('islamic-civil', 227015);
  CALS['islamic-tbla'] = islamicCalendar('islamic-tbla', 227014);
  CALS['islamic-umalqura'] = islamicCalendar('islamic-umalqura', 227015);
  CALS['islamic-rgsa'] = islamicCalendar('islamic-rgsa', 227015);
  CALS.islamic = islamicCalendar('islamic', 227015);
  var CAL_ALIASES = { ethiopicaa: 'ethioaa', 'ethiopic-amete-alem': 'ethioaa', islamicc: 'islamic-civil' };

  // ---- generic calendar operations
  function calOf(d) { return d.cal === undefined ? 'iso8601' : d.cal; }
  function calSystem(id) { return CALS[id]; }
  // Era and era year of a (calendar year, month, day).
  function eraOf(cal, y, m, d) {
    if (cal.japanese) {
      var iso = dateFromEpochDays(cal.toDays(y, m, d));
      for (var i = 0; i < JAPANESE_ERAS.length; i++) {
        var s = JAPANESE_ERAS[i].start;
        if (iso.year > s[0] || (iso.year === s[0] && (iso.month > s[1] || (iso.month === s[1] && iso.day >= s[2])))) return { era: JAPANESE_ERAS[i].name, eraYear: iso.year - JAPANESE_ERAS[i].base + 1 };
      }
      return iso.year >= 1 ? { era: 'ce', eraYear: iso.year } : { era: 'bce', eraYear: 1 - iso.year };
    }
    if (cal.ethiopic) return y > 0 ? { era: 'am', eraYear: y } : { era: 'aa', eraYear: y + 5500 };
    for (var k = 0; k < cal.eras.length; k++) {
      var e = cal.eras[k];
      if ((e.minYear === undefined || y >= e.minYear) && (e.maxYear === undefined || y <= e.maxYear)) return { era: e.name, eraYear: e.eraYear(y) };
    }
    return { era: cal.eras[0].name, eraYear: cal.eras[0].eraYear(y) };
  }
  // The calendar year for an era name and era year (undefined when the era is not one of the calendar's).
  function yearFromEra(cal, era, eraYear) {
    if (cal.japanese) {
      if (era === 'ce' || era === 'ad') return eraYear;
      if (era === 'bce' || era === 'bc') return 1 - eraYear;
      for (var i = 0; i < JAPANESE_ERAS.length; i++) if (JAPANESE_ERAS[i].name === era) return JAPANESE_ERAS[i].base + eraYear - 1;
      return undefined;
    }
    if (cal.ethiopic) { if (era === 'am') return eraYear; if (era === 'aa') return eraYear - 5500; return undefined; }
    for (var k = 0; k < cal.eras.length; k++) {
      var e = cal.eras[k];
      if (e.name === era || includesStr(e.aliases, era)) return e.yearFor(eraYear);
    }
    return undefined;
  }
  function includesStr(a, v) { for (var i = 0; i < a.length; i++) if (a[i] === v) return true; return false; }
  function calHasEras(cal) { return cal.hasEras; }

  // The calendar fields of an ISO date record.
  function calFields(id, iso) {
    var cal = CALS[id], days = epochDays(iso.year, iso.month, iso.day), c = cal.fromDays(days);
    var e = eraOf(cal, c.year, c.month, c.day);
    return { year: c.year, month: c.month, monthCode: cal.monthCode(c.year, c.month), day: c.day, era: e.era, eraYear: e.eraYear,
      daysInMonth: cal.daysInMonth(c.year, c.month), daysInYear: cal.daysInYear(c.year), monthsInYear: cal.monthsInYear(c.year), inLeapYear: cal.inLeapYear(c.year),
      dayOfYear: days - cal.toDays(c.year, 1, 1) + 1 };
  }
  // Turns calendar fields {year|era+eraYear, month|monthCode, day} into an ISO date record, honouring overflow.
  function calDateFromFields(id, f, overflow) {
    var cal = CALS[id], year = f.year;
    if (f.era !== undefined || f.eraYear !== undefined) {
      if (f.era === undefined || f.eraYear === undefined) throw new TypeErr('era and eraYear must be provided together');
      var ey = yearFromEra(cal, f.era, f.eraYear);
      if (ey === undefined) throw new RangeErr('invalid era for the calendar');
      if (year !== undefined && year !== ey) throw new RangeErr('year does not match era and eraYear');
      year = ey;
    }
    if (year === undefined) throw new TypeErr('year is required');
    if (f.day === undefined) throw new TypeErr('day is required');
    var month = resolveCalMonth(cal, year, f, overflow);
    var mlen = cal.daysInMonth(year, month), day = f.day;
    if (day > mlen) { if (overflow === 'reject') throw new RangeErr('day out of range'); day = mlen; }
    var iso = dateFromEpochDays(cal.toDays(year, month, day));
    if (!dateWithinLimits(iso.year, iso.month, iso.day)) throw new RangeErr('date out of range');
    return iso;
  }
  function resolveCalMonth(cal, year, f, overflow) {
    var code = f.monthCode, month = f.month, resolved;
    if (code !== undefined) {
      var p = parseMonthCode(code);
      if (p === null) throw new RangeErr('invalid monthCode');
      resolved = cal.monthFromCode(year, p);
      if (resolved === 0) {
        if (p.number >= 1 && p.number <= 13 && p.leap && overflow === 'constrain' && cal.id === 'hebrew' && p.number === 5) resolved = cal.monthFromCode(year, { number: 6, leap: false });
        else if (p.number > cal.monthsInYear(year) && !p.leap && overflow === 'constrain' && cal.monthFromCode(year, p) === 0 && p.number <= 13) resolved = cal.monthsInYear(year);
        else throw new RangeErr('monthCode is not valid in this calendar year');
      }
      if (month !== undefined && month !== resolved) throw new RangeErr('month and monthCode do not agree');
      return resolved;
    }
    if (month === undefined) throw new TypeErr('month or monthCode is required');
    var max = cal.monthsInYear(year);
    if (month > max) { if (overflow === 'reject') throw new RangeErr('month out of range'); return max; }
    return month;
  }
  // CalendarDateAdd: years and months in calendar terms, then weeks and days as plain days.
  function calAddDate(date, years, months, weeks, days, overflow) {
    var id = date.cal, cal = CALS[id], c = cal.fromDays(epochDays(date.year, date.month, date.day));
    var y = c.year, m = c.month, d = c.day;
    if (years !== 0 || months !== 0) {
      var code = cal.monthCode(y, m);
      if (years !== 0) {
        y += years;
        var p = parseMonthCode(code), nm = cal.monthFromCode(y, p);
        if (nm === 0) {
          if (overflow === 'reject') throw new RangeErr('month does not exist in the target year');
          // a leap month with no leap year: the following month takes its place (Adar I -> Adar)
          nm = p.leap ? cal.monthFromCode(y, { number: p.number + 1, leap: false }) : cal.monthsInYear(y);
          if (nm === 0) nm = cal.monthsInYear(y);
        }
        m = nm;
      }
      if (months !== 0) {
        var total = m + months;
        if (months > 0) {
          while (total > cal.monthsInYear(y)) { total -= cal.monthsInYear(y); y++; }
        } else {
          while (total < 1) { y--; total += cal.monthsInYear(y); }
        }
        m = total;
      }
      var mlen = cal.daysInMonth(y, m);
      if (d > mlen) { if (overflow === 'reject') throw new RangeErr('day out of range'); d = mlen; }
    }
    var iso = dateFromEpochDays(cal.toDays(y, m, d) + 7 * weeks + days);
    if (!dateWithinLimits(iso.year, iso.month, iso.day)) throw new RangeErr('date out of range');
    iso.cal = id;
    return iso;
  }
  // CalendarDateUntil restricted to years, months, weeks and days. A step "surpasses" the end when it lies beyond it in the direction of
  // travel, comparing year, then month (month code order for the year steps, ordinal for the month steps), then the unconstrained day.
  function compareCodes(a, b) {
    if (a.number !== b.number) return a.number < b.number ? -1 : 1;
    if (a.leap !== b.leap) return a.leap ? 1 : -1;
    return 0;
  }
  function calDifferenceDate(a, b, largest) {
    var id = a.cal, cal = CALS[id], da = epochDays(a.year, a.month, a.day), db = epochDays(b.year, b.month, b.day);
    if (largest === 'day' || largest === 'week') {
      var diff = db - da;
      if (largest === 'week') { var w = diff < 0 ? -mathFloor(-diff / 7) : mathFloor(diff / 7); return { years: 0, months: 0, weeks: w, days: diff - w * 7 }; }
      return { years: 0, months: 0, weeks: 0, days: diff };
    }
    if (da === db) return { years: 0, months: 0, weeks: 0, days: 0 };
    var sign = db < da ? -1 : 1, sa = cal.fromDays(da), sb = cal.fromDays(db);
    var startCode = parseMonthCode(cal.monthCode(sa.year, sa.month)), endCode = parseMonthCode(cal.monthCode(sb.year, sb.month));
    var years = 0;
    if (largest === 'year') {
      var cand = sb.year - sa.year;
      while (cand !== 0) {
        var y = sa.year + cand, surpass;
        if (y !== sb.year) surpass = sign * (y - sb.year) > 0;
        else {
          var c = compareCodes(startCode, endCode);
          if (c !== 0) surpass = sign * c > 0;
          else surpass = sa.day !== sb.day && sign * (sa.day - sb.day) > 0;
        }
        if (!surpass) break;
        cand -= sign;
      }
      years = cand;
    }
    var by = sa.year + years, bm = sa.month;
    if (years !== 0) {
      bm = cal.monthFromCode(by, startCode);
      if (bm === 0) bm = startCode.leap ? cal.monthFromCode(by, { number: startCode.number + 1, leap: false }) : cal.monthsInYear(by);
      if (bm === 0) bm = cal.monthsInYear(by);
    }
    var months = 0;
    while (true) {
      var next = addMonthsOrdinal(cal, by, bm, sign), beyond;
      if (next.year !== sb.year) beyond = sign * (next.year - sb.year) > 0;
      else if (next.month !== sb.month) beyond = sign * (next.month - sb.month) > 0;
      else beyond = sa.day !== sb.day && sign * (sa.day - sb.day) > 0;
      if (beyond) break;
      by = next.year; bm = next.month; months += sign;
      if (months > 100000 || months < -100000) break;
    }
    var landed = cal.toDays(by, bm, mathMin(sa.day, cal.daysInMonth(by, bm)));
    return { years: years, months: months, weeks: 0, days: db - landed };
  }
  function addMonthsOrdinal(cal, y, m, sign) {
    if (sign === 1) { m++; if (m > cal.monthsInYear(y)) { m = 1; y++; } }
    else { m--; if (m < 1) { y--; m = cal.monthsInYear(y); } }
    return { year: y, month: m };
  }
  function canonicalCalendarId(id) {
    var l = lower(id);
    if (l === 'iso8601') return 'iso8601';
    if (CAL_ALIASES[l] !== undefined) l = CAL_ALIASES[l];
    if (CALS[l] !== undefined) return l;
    return undefined;
  }

  // ---- getters shared by the date-carrying classes
  var DATE_GETTER_NAMES = ['calendarId', 'era', 'eraYear', 'year', 'month', 'monthCode', 'day', 'dayOfWeek', 'dayOfYear', 'weekOfYear', 'yearOfWeek', 'daysInWeek',
    'daysInMonth', 'daysInYear', 'monthsInYear', 'inLeapYear'];
  function dateGetterValue(name, d) {
    var id = calOf(d);
    if (id === 'iso8601') {
      switch (name) {
        case 'calendarId': return id;
        case 'era': case 'eraYear': return undefined;
        case 'year': return d.year;
        case 'month': return d.month;
        case 'monthCode': return monthCodeOf(d.month);
        case 'day': return d.day;
        case 'dayOfWeek': return dayOfWeek(d.year, d.month, d.day);
        case 'dayOfYear': return dayOfYear(d.year, d.month, d.day);
        case 'weekOfYear': return weekInfo(d.year, d.month, d.day).week;
        case 'yearOfWeek': return weekInfo(d.year, d.month, d.day).year;
        case 'daysInWeek': return 7;
        case 'daysInMonth': return daysInMonth(d.year, d.month);
        case 'daysInYear': return isLeap(d.year) ? 366 : 365;
        case 'monthsInYear': return 12;
        default: return isLeap(d.year);
      }
    }
    if (name === 'calendarId') return id;
    if (name === 'dayOfWeek') return dayOfWeek(d.year, d.month, d.day);
    if (name === 'daysInWeek') return 7;
    if (name === 'weekOfYear' || name === 'yearOfWeek') return undefined;
    var f = calFields(id, d);
    if (name === 'era' || name === 'eraYear') return CALS[id].hasEras ? f[name] : undefined;
    return f[name];
  }
  function nameGetter(f, name) {
    defineProperty(f, 'name', { value: 'get ' + name, writable: false, enumerable: false, configurable: true });
    return f;
  }
  // An accessors object for installClass: each getter reads the date record `getDate(this)` gives (which also brand-checks `this`).
  function accessorsFor(getDate, names) {
    var out = {};
    for (var i = 0; i < names.length; i++) {
      (function (name) {
        var g = nameGetter(function () { return dateGetterValue(name, getDate(this)); }, name);
        defineProperty(out, name, { get: g, enumerable: true, configurable: true });
      })(names[i]);
    }
    return out;
  }
  function mergeAccessors(a, b) {
    var out = {}, names = ownNames(a), i;
    for (i = 0; i < names.length; i++) defineProperty(out, names[i], getDesc(a, names[i]));
    names = ownNames(b);
    for (i = 0; i < names.length; i++) defineProperty(out, names[i], getDesc(b, names[i]));
    return out;
  }
  function isIsoCal(id) { return id === undefined || id === 'iso8601'; }
  // Records of non-ISO dates carry their calendar id; ISO ones carry none.
  function withCal(d, id) { if (!isIsoCal(id)) d.cal = id; return d; }
  var arrSortFn = Array.prototype.sort;
  // The field names read from a bag in a calendar: non-ISO calendars add era and eraYear, keeping the alphabetical order.
  function calFieldList(id, names) {
    if (isIsoCal(id)) return names;
    var all = [];
    for (var i = 0; i < names.length; i++) all[all.length] = names[i];
    all[all.length] = 'era';
    all[all.length] = 'eraYear';
    apply(arrSortFn, all, []);
    return all;
  }

  // ---- year-month and month-day records in a calendar
  // A year-month is stored as the ISO date of its first day (with the calendar id); a month-day as a reference ISO date.
  function calYearMonthRef(id, d) {
    var cal = CALS[id], c = cal.fromDays(epochDays(d.year, d.month, d.day));
    var iso = dateFromEpochDays(cal.toDays(c.year, c.month, 1));
    iso.cal = id;
    return iso;
  }
  function calYearMonthFromFields(id, f, overflow) {
    var cal = CALS[id], year = f.year;
    if (f.era !== undefined || f.eraYear !== undefined) {
      if (f.era === undefined || f.eraYear === undefined) throw new TypeErr('era and eraYear must be provided together');
      var ey = yearFromEra(cal, f.era, f.eraYear);
      if (ey === undefined) throw new RangeErr('invalid era for the calendar');
      if (year !== undefined && year !== ey) throw new RangeErr('year does not match era and eraYear');
      year = ey;
    }
    if (year === undefined) throw new TypeErr('year is required');
    var month = resolveCalMonth(cal, year, f, overflow);
    var iso = dateFromEpochDays(cal.toDays(year, month, 1));
    if (!yearMonthWithinLimits(iso.year, iso.month)) throw new RangeErr('year-month out of range');
    iso.cal = id;
    return iso;
  }
  function yearMonthFieldsOf(ym) {
    var cf = calFields(ym.cal, ym);
    return { era: cf.era, eraYear: cf.eraYear, year: cf.year, month: cf.month, monthCode: cf.monthCode };
  }
  function calYearMonthAdd(ym, d, overflow) {
    var id = ym.cal, cal = CALS[id], c = cal.fromDays(epochDays(ym.year, ym.month, ym.day));
    var start = durationSign(d) < 0 ? cal.toDays(c.year, c.month, cal.daysInMonth(c.year, c.month)) : cal.toDays(c.year, c.month, 1);
    var iso = dateFromEpochDays(start);
    iso.cal = id;
    var added = calAddDate(iso, d.years, d.months, 0, 0, 'constrain');
    return calYearMonthRef(id, added);
  }
  // The ISO reference date for a month-day: the latest date on or before 1972-12-31 in a calendar year where the month has that day.
  function calMonthDayRef(id, monthCode, day, overflow) {
    var cal = CALS[id], p = parseMonthCode(monthCode);
    if (p === null) throw new RangeErr('invalid monthCode');
    var cutoff = epochDays(1972, 12, 31), y0 = cal.fromDays(cutoff).year;
    var maxDay = 0, found = false;
    for (var y = y0 + 1; y >= y0 - 200; y--) {
      var m = cal.monthFromCode(y, p);
      if (m === 0) continue;
      var len = cal.daysInMonth(y, m);
      if (len > maxDay) maxDay = len;
    }
    if (maxDay === 0) throw new RangeErr('monthCode is not valid in this calendar');
    if (day > maxDay) {
      if (overflow === 'reject') throw new RangeErr('day out of range');
      day = maxDay;
    }
    for (var yy = y0 + 1; yy >= y0 - 200; yy--) {
      var mm = cal.monthFromCode(yy, p);
      if (mm === 0 || cal.daysInMonth(yy, mm) < day) continue;
      var days = cal.toDays(yy, mm, day);
      if (days <= cutoff) { var iso = dateFromEpochDays(days); iso.cal = id; return iso; }
    }
    throw new RangeErr('no reference date for the month-day');
  }
  function calMonthDayFromFields(id, f, overflow) {
    var cal = CALS[id];
    if (f.day === undefined) throw new TypeErr('day is required');
    var hasYear = f.year !== undefined || f.era !== undefined || f.eraYear !== undefined;
    if (f.monthCode === undefined && !hasYear) {
      if (f.month === undefined) throw new TypeErr('month or monthCode is required');
      throw new TypeErr('year is required when month is given without monthCode');
    }
    if (f.month === undefined && f.monthCode === undefined) throw new TypeErr('month or monthCode is required');
    if (hasYear) {
      var iso = calDateFromFields(id, f, overflow), cf = calFields(id, iso);
      return calMonthDayRef(id, cf.monthCode, cf.day, 'constrain');
    }
    return calMonthDayRef(id, f.monthCode, f.day, overflow);
  }
  function monthDayFieldsOf(md) {
    if (isIsoCal(md.cal)) return { monthCode: monthCodeOf(md.month), day: md.day };
    var cf = calFields(md.cal, md);
    return { monthCode: cf.monthCode, day: cf.day };
  }
