
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
      monthFromCode: function (y, code, overflow) { var m = codeNumber(code); return m >= 1 && m <= 12 && !code.leap ? m : 0; },
      validCode: function (code) { return code.number >= 1 && code.number <= 12 && !code.leap; }
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
      monthFromCode: function (y, code) { return code.leap ? 0 : (code.number >= 1 && code.number <= 13 ? code.number : 0); },
      validCode: function (code) { return code.number >= 1 && code.number <= 13 && !code.leap; }
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

  // ---- Umm al-Qura: the published month lengths for 1301..1599 AH, the tabular civil calendar outside them
  var UQ_TABLE = 'a66665a9a59669a66569a9995a69a59999a66666666999966a96599a999666a66599a6996666a5a659a66996666a65999a66659a69996699a66599a99965aa66566a69959a69996699a66659a66996669a6596a69965a6a65969a696666699a5969a69599a9999669a66599a99966669a59999a99659aa65966a69599a6996666999a5999a99659aa65966a69659a6a59669a66665a69999669a66599a9966669a65969a6966666a59966a66659a69995a6a66599a696666699999999a66599aa59666a66599a6996666a59999a66996666a65999a96659a9999669a66599a6999666a66596a69959a6a65669a666666669996669a6596a69965a6a65969a9965a69999999a66665a69a5966a66659a69996669a65999a9966669a65969a69659a6a56669a65999a66996666a65966a99659a9a59669a66599a99696699a65999a99965aa66596a69965a69a59999a96659a9999669a66599a9996669a59999a66666666a5659aa6595aa69656a69996669a65999a66996669a6599a69965a9a65969a6966666999966a66659a69996669a59999a66666669a59969a96599a999666a66599a69966669999999a6696666a65966a69659a9999669a66599a69996669a965a69a59669a66599a69996699a65999a99659aa65966a69659a6999666999a599a6696666a66596a69965a6a65669a69666669999669a6659a69996669a6599a666966669a59969a96599a99965aa66599a699666699999999a66659aa65966a69659a9999669a66599a69996669a65999a9966669a59969a6665a66999966a66656a69965a6a65969a666666699999699a66599a99959aa66569a6995a66a59999a66965a69a59699a96659a9999669a66599a6996666a66566a69959a6a59669a66599a666966669a6596a69965a9a65669a6959a69999969a66659a6999666a66599a69996669a65999a69665a6a59966a69599a9996669a59999a666666669a5966a69659a9a59669a65999a99666699a65999a996666a65996a66665a69999969a66659a99995a9a65969a9965a699999999a66659a6999666a66566a99959a9a59699a66666699a59699a96659a999966a66659a69996669a66599a99959a9a65669a9659a6999666999a6599a69965a9a65669a9959a69996669a6665a66699666a66599a69995a6a66569a69966669a5996a669599a9a56669a65999a96666699999999a99659a9a595aa66596a69966669999999a6696666a6', UQ_FIRST = 1301, UQ_LAST = 1599, UQ_START = -31472;
  function umalquraCalendar() {
    var civil = islamicCalendar('islamic-civil', 227015), starts = [], lens = [], day = UQ_START;
    for (var y = UQ_FIRST; y <= UQ_LAST; y++) {
      var bits = parseInt(sliceS(UQ_TABLE, (y - UQ_FIRST) * 6, (y - UQ_FIRST) * 6 + 6), 16), row = [];
      for (var m = 12; m >= 1; m--) { row[m - 1] = 28 + (bits % 4); bits = mathFloor(bits / 4); }
      starts[y - UQ_FIRST] = day;
      lens[y - UQ_FIRST] = row;
      for (var k = 0; k < 12; k++) day += row[k];
    }
    var end = day;
    function inTable(y) { return y >= UQ_FIRST && y <= UQ_LAST; }
    var cal = {
      id: 'islamic-umalqura', hasEras: true, eras: civil.eras,
      fromDays: function (days) {
        if (days < UQ_START || days >= end) return civil.fromDays(days);
        var y = UQ_FIRST;
        while (y < UQ_LAST && days >= starts[y - UQ_FIRST + 1]) y++;
        var left = days - starts[y - UQ_FIRST], m = 1;
        while (m < 12 && left >= lens[y - UQ_FIRST][m - 1]) { left -= lens[y - UQ_FIRST][m - 1]; m++; }
        return { year: y, month: m, day: left + 1 };
      },
      toDays: function (y, m, d) {
        if (!inTable(y)) return civil.toDays(y, m, d);
        var n = starts[y - UQ_FIRST] + d - 1;
        for (var i = 1; i < m; i++) n += lens[y - UQ_FIRST][i - 1];
        return n;
      },
      monthsInYear: function () { return 12; },
      daysInMonth: function (y, m) { return inTable(y) ? lens[y - UQ_FIRST][m - 1] : civil.daysInMonth(y, m); },
      daysInYear: function (y) { if (!inTable(y)) return civil.daysInYear(y); var t = 0; for (var i = 0; i < 12; i++) t += lens[y - UQ_FIRST][i]; return t; },
      inLeapYear: function (y) { return cal.daysInYear(y) === 355; },
      monthCode: function (y, m) { return monthCodeFor(m, false); },
      monthFromCode: function (y, code) { return code.leap ? 0 : (code.number >= 1 && code.number <= 12 ? code.number : 0); }
    };
    return cal;
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
      id: 'hebrew', hasEras: true, lunisolar: true,
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
  CALS['islamic-umalqura'] = umalquraCalendar();
  CALS['islamic-rgsa'] = islamicCalendar('islamic-rgsa', 227015);
  CALS.islamic = islamicCalendar('islamic', 227015);

  // ---- Chinese and Dangi: the lunisolar calendars computed from the moon and sun (Meeus' series, as in Reingold & Dershowitz),
  // with the day boundary at midnight in China or Korea standard time. Years outside 1700..2300 repeat the 19-year cycle of the
  // nearest computed years (still a consistent calendar, not an astronomical one).
  function astroSin(d) { return Math.sin(d * Math.PI / 180); }
  function mod360(x) { return x - 360 * mathFloor(x / 360); }
  function deltaTSeconds(y) {
    var t;
    if (y < 1900) { t = (y - 1820) / 100; return -20 + 32 * t * t; }
    if (y < 1920) { t = y - 1900; return -2.79 + 1.494119 * t - 0.0598939 * t * t + 0.0061966 * t * t * t - 0.000197 * t * t * t * t; }
    if (y < 1941) { t = y - 1920; return 21.20 + 0.84493 * t - 0.076100 * t * t + 0.0020936 * t * t * t; }
    if (y < 1961) { t = y - 1950; return 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2547; }
    if (y < 1986) { t = y - 1975; return 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718; }
    if (y < 2005) { t = y - 2000; return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * t * t * t + 0.000651814 * t * t * t * t + 0.00002373599 * t * t * t * t * t; }
    if (y < 2050) { t = y - 2000; return 62.92 + 0.32217 * t + 0.005589 * t * t; }
    if (y < 2150) return -20 + 32 * ((y - 1820) / 100) * ((y - 1820) / 100) - 0.5628 * (2150 - y);
    t = (y - 1820) / 100;
    return -20 + 32 * t * t;
  }
  var J1970 = 2440587.5;
  function jdeToUT(jde) { return jde - deltaTSeconds(2000 + (jde - 2451545) / 365.25) / 86400; }
  function utToJde(jd) { return jd + deltaTSeconds(2000 + (jd - 2451545) / 365.25) / 86400; }
  // Meeus ch. 49: JDE (TT) of the k-th new moon (k = 0 is the one of 2000-01-06)
  function newMoonJDE(k) {
    var T = k / 1236.85, T2 = T * T, T3 = T2 * T, T4 = T3 * T;
    var jde = 2451550.09766 + 29.530588861 * k + 0.00015437 * T2 - 0.000000150 * T3 + 0.00000000073 * T4;
    var E = 1 - 0.002516 * T - 0.0000074 * T2;
    var M = mod360(2.5534 + 29.10535670 * k - 0.0000014 * T2 - 0.00000011 * T3);
    var Mp = mod360(201.5643 + 385.81693528 * k + 0.0107582 * T2 + 0.00001238 * T3 - 0.000000058 * T4);
    var F = mod360(160.7108 + 390.67050284 * k - 0.0016118 * T2 - 0.00000227 * T3 + 0.000000011 * T4);
    var O = mod360(124.7746 - 1.56375588 * k + 0.0020672 * T2 + 0.00000215 * T3);
    var sn = astroSin;
    var c = -0.40720 * sn(Mp) + 0.17241 * E * sn(M) + 0.01608 * sn(2 * Mp) + 0.01039 * sn(2 * F) + 0.00739 * E * sn(Mp - M) - 0.00514 * E * sn(Mp + M)
      + 0.00208 * E * E * sn(2 * M) - 0.00111 * sn(Mp - 2 * F) - 0.00057 * sn(Mp + 2 * F) + 0.00056 * E * sn(2 * Mp + M) - 0.00042 * sn(3 * Mp)
      + 0.00042 * E * sn(M + 2 * F) + 0.00038 * E * sn(M - 2 * F) - 0.00024 * E * sn(2 * Mp - M) - 0.00017 * sn(O) - 0.00007 * sn(Mp + 2 * M)
      + 0.00004 * sn(2 * Mp - 2 * F) + 0.00004 * sn(3 * M) + 0.00003 * sn(Mp + M - 2 * F) + 0.00003 * sn(2 * Mp + 2 * F) - 0.00003 * sn(Mp + M + 2 * F)
      + 0.00003 * sn(Mp - M + 2 * F) - 0.00002 * sn(Mp - M - 2 * F) - 0.00002 * sn(3 * Mp + M) + 0.00002 * sn(4 * Mp);
    var A = [[299.77, 0.107408, -0.009173], [251.88, 0.016321], [251.83, 26.651886], [349.42, 36.412478], [84.66, 18.206239], [141.74, 53.303771], [207.14, 2.453732],
      [154.84, 7.306860], [34.52, 27.261239], [207.19, 0.121824], [291.34, 1.844379], [161.72, 24.198154], [239.56, 25.513099], [331.55, 3.592518]];
    var amp = [0.000325, 0.000165, 0.000164, 0.000126, 0.00011, 0.000062, 0.00006, 0.000056, 0.000047, 0.000042, 0.00004, 0.000037, 0.000035, 0.000023];
    for (var i = 0; i < 14; i++) c += amp[i] * sn(A[i][0] + A[i][1] * k + (A[i][2] ? A[i][2] * T2 : 0));
    return jde + c;
  }
  var SUN_COEF = [403406, 195207, 119433, 112392, 3891, 2819, 1721, 660, 350, 334, 314, 268, 242, 234, 158, 132, 129, 114, 99, 93, 86, 78, 72, 68, 64, 46, 38, 37, 32, 29, 28, 27, 27, 25, 24, 21, 21, 20, 18, 17, 14, 13, 13, 13, 12, 10, 10, 10, 10];
  var SUN_ADD = [270.54861, 340.19128, 63.91854, 331.26220, 317.843, 86.631, 240.052, 310.26, 247.23, 260.87, 297.82, 343.14, 166.79, 81.53, 3.50, 132.75, 182.95, 162.03, 29.8, 266.4, 249.2, 157.6, 257.8, 185.1, 69.9, 8.0, 197.1, 250.4, 65.3, 162.7, 341.5, 291.6, 98.5, 146.7, 110.0, 5.2, 342.6, 230.9, 256.1, 45.3, 242.9, 115.2, 151.8, 285.3, 53.3, 126.6, 205.7, 85.9, 146.1];
  var SUN_MUL = [0.9287892, 35999.1376958, 35999.4089666, 35998.7287385, 71998.20261, 71998.4403, 36000.35726, 71997.4812, 32964.4678, -19.4410, 445267.1117, 45036.8840, 3.1008, 22518.4434, -19.9739, 65928.9345, 9038.0293, 3034.7684, 33718.148, 3034.4057, -2280.773, 29929.992, 31556.493, 149.588, 9037.750, 107997.405, -4444.176, 151.771, 67555.328, 31556.080, -4561.540, 107996.706, 1221.655, 62894.167, 31437.369, 14578.298, -31931.757, 34777.259, 1221.999, 62894.511, -4442.039, 107997.909, 119.066, 16859.071, -4.578, 26895.292, -39.127, 12297.536, 90073.778];
  // Apparent solar longitude (degrees) at a Julian day in dynamical time.
  function solarLongitude(jde) {
    var c = (jde - 2451545) / 36525, sum = 0;
    for (var i = 0; i < 49; i++) sum += SUN_COEF[i] * astroSin(SUN_ADD[i] + SUN_MUL[i] * c);
    var lam = 282.7771834 + 36000.76953744 * c + 0.000005729577951308232 * sum;
    var omega = 124.90 - 1934.134 * c + 0.002063 * c * c;
    var nut = -0.004778 * astroSin(omega) - 0.0003667 * astroSin(201.11 + 72001.5377 * c);
    return mod360(lam + nut - 0.005575);
  }
  function chinaOffset(ed) { return 1970 + ed / 365.2425 < 1929 ? 1397 / 180 : 8; }
  var KOREA_CHANGES = [epochDays(1908, 4, 1), epochDays(1912, 1, 1), epochDays(1954, 3, 21), epochDays(1961, 8, 10)];
  function koreaOffset(ed) {
    if (ed < KOREA_CHANGES[0]) return 8 + 27 / 60 + 52 / 3600;
    if (ed < KOREA_CHANGES[1]) return 8.5;
    if (ed < KOREA_CHANGES[2]) return 9;
    if (ed < KOREA_CHANGES[3]) return 8.5;
    return 9;
  }
  function lunisolarCalendar(id, offsetFn) {
    function localDay(jd) { var ed = jd - J1970; return mathFloor(ed + offsetFn(ed) / 24); }
    function newMoonDay(k) { return localDay(jdeToUT(newMoonJDE(k))); }
    function longitudeAtMidnight(day) {
      var ed = day;
      for (var i = 0; i < 3; i++) ed = day - offsetFn(ed) / 24;
      return solarLongitude(utToJde(J1970 + ed));
    }
    function solstice(y) {
      var lo = J1970 + epochDays(y, 12, 18), hi = lo + 7;
      for (var i = 0; i < 50; i++) {
        var mid = (lo + hi) / 2, l = solarLongitude(utToJde(mid));
        if (mod360(l - 270 + 180) - 180 < 0) lo = mid; else hi = mid;
      }
      return lo;
    }
    var intervals = {};
    // The months from the one containing the December solstice of Gregorian year y to the one containing the next, with month numbers.
    function interval(y) {
      if (intervals[y] !== undefined) return intervals[y];
      var solA = localDay(solstice(y)), solB = localDay(solstice(y + 1));
      function containing(day) {
        var k = Math.round((J1970 + day + 0.5 - 2451550.09766) / 29.530588861);
        while (newMoonDay(k) > day) k--;
        while (newMoonDay(k + 1) <= day) k++;
        return k;
      }
      var ka = containing(solA), kb = containing(solB), days = [];
      for (var k = ka; k <= kb; k++) days[days.length] = newMoonDay(k);
      var count = kb - ka, leapIdx = -1, months = [];
      if (count === 13) {
        for (var j = 1; j <= 12; j++) {
          if (mathFloor(longitudeAtMidnight(days[j]) / 30) === mathFloor(longitudeAtMidnight(days[j + 1]) / 30)) { leapIdx = j; break; }
        }
      }
      for (var m = 0; m < count; m++) {
        var num = ((10 + m) % 12) + 1, leap = false;
        if (leapIdx >= 0 && m >= leapIdx) { num = ((10 + m - 1) % 12) + 1; leap = m === leapIdx; }
        months[m] = { start: days[m], len: days[m + 1] - days[m], num: num, leap: leap };
      }
      intervals[y] = months;
      return months;
    }
    function firstMonth(months) { for (var i = 0; i < months.length; i++) if (months[i].num === 1 && !months[i].leap) return i; return -1; }
    var rows = {};
    var LOW = 1700, HIGH = 2300;
    function computedRow(Y) {
      if (rows[Y] !== undefined) return rows[Y];
      var cur = interval(Y - 1), nxt = interval(Y), all = [], i;
      for (i = firstMonth(cur); i < cur.length; i++) all[all.length] = cur[i];
      var stop = firstMonth(nxt);
      for (i = 0; i < stop; i++) all[all.length] = nxt[i];
      var lens = [], total = 0, leap = 0;
      for (i = 0; i < all.length; i++) { lens[i] = all[i].len; total += all[i].len; if (all[i].leap) leap = all[i].num; }
      // dangi 2052: the new moon ending the leap eighth month falls within minutes of midnight; the reference tables put it a day earlier
      if (id === 'dangi' && Y === 2052 && leap === 8) {
        for (i = 0; i < all.length; i++) if (all[i].leap && lens[i] === 30 && lens[i + 1] === 29) { lens[i] = 29; lens[i + 1] = 30; }
      }
      return (rows[Y] = { start: all[0].start, leap: leap, lens: lens, total: total });
    }
    var sumHigh, sumLow;
    function cycleSums() {
      if (sumHigh === undefined) {
        sumHigh = computedRow(HIGH).start + computedRow(HIGH).total - computedRow(HIGH - 18).start;
        sumLow = computedRow(LOW + 18).start + computedRow(LOW + 18).total - computedRow(LOW).start;
      }
    }
    var cache = {};
    function info(y) {
      if (y >= LOW && y <= HIGH) return computedRow(y);
      if (cache[y] !== undefined) return cache[y];
      cycleSums();
      var r, n, y2;
      if (y > HIGH) { n = mathFloor((y - HIGH + 18) / 19); y2 = y - 19 * n; r = computedRow(y2); r = { start: r.start + n * sumHigh, leap: r.leap, lens: r.lens, total: r.total }; }
      else { n = mathFloor((LOW - y + 18) / 19); y2 = y + 19 * n; r = computedRow(y2); r = { start: r.start - n * sumLow, leap: r.leap, lens: r.lens, total: r.total }; }
      cache[y] = r;
      return r;
    }
    function yearOf(d) {
      var y = mathFloor(1970 + d / 365.2425);
      while (info(y).start > d) y--;
      while (info(y + 1).start <= d) y++;
      return y;
    }
    var cal = {
      id: id, hasEras: false, eras: [], lunisolar: true, refSpan: [1900, 2100],
      fromDays: function (d) {
        var y = yearOf(d), yi = info(y), left = d - yi.start, m = 0;
        while (left >= yi.lens[m]) { left -= yi.lens[m]; m++; }
        return { year: y, month: m + 1, day: left + 1 };
      },
      toDays: function (y, m, d) { var yi = info(y), n = yi.start + d - 1; for (var j = 0; j < m - 1; j++) n += yi.lens[j]; return n; },
      monthsInYear: function (y) { return info(y).lens.length; },
      daysInMonth: function (y, m) { return info(y).lens[m - 1]; },
      daysInYear: function (y) { return info(y).total; },
      inLeapYear: function (y) { return info(y).leap !== 0; },
      monthCode: function (y, m) {
        var leap = info(y).leap;
        if (leap === 0 || m <= leap) return monthCodeFor(m, false);
        if (m === leap + 1) return monthCodeFor(leap, true);
        return monthCodeFor(m - 1, false);
      },
      monthFromCode: function (y, code) {
        var leap = info(y).leap;
        if (code.leap) return leap === code.number ? code.number + 1 : 0;
        if (leap !== 0 && code.number > leap) return code.number + 1;
        return code.number >= 1 && code.number <= 12 ? code.number : 0;
      },
      validCode: function (code) { return code.number >= 1 && code.number <= 12; },
      addAbsent: function (code) { return { number: code.number, leap: false }; }
    };
    return cal;
  }
  CALS.chinese = lunisolarCalendar('chinese', chinaOffset);
  CALS.dangi = lunisolarCalendar('dangi', koreaOffset);
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
    if (!cal.hasEras) return { era: undefined, eraYear: undefined };
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
  // The month a missing leap month stands for when comparing year anniversaries: the next month going forwards, the plain month backwards.
  function absentLeapCode(cal, p, sign) {
    return sign > 0 ? { number: p.number + 1, leap: false } : { number: p.number, leap: false };
  }
  // The month it becomes when a date is moved into a year without it (Hebrew Adar I -> Adar, Chinese M04L -> M04).
  function addAbsentCode(cal, p) {
    if (cal.addAbsent) return cal.addAbsent(p);
    return { number: p.number + 1, leap: false };
  }
  function calValidCode(cal, p) {
    if (cal.validCode) return cal.validCode(p);
    if (cal.id === 'hebrew') return p.number >= 1 && p.number <= 12 && (!p.leap || p.number === 5);
    return p.number >= 1 && p.number <= 12 && !p.leap;
  }
  function resolveCalMonth(cal, year, f, overflow) {
    var code = f.monthCode, month = f.month, resolved;
    if (code !== undefined) {
      var p = parseMonthCode(code);
      if (p === null || !calValidCode(cal, p)) throw new RangeErr('invalid monthCode for the calendar');
      resolved = cal.monthFromCode(year, p);
      if (resolved === 0) {
        // a valid leap month the year does not have: constrained to the plain month (Hebrew: the following one)
        if (overflow === 'reject') throw new RangeErr('monthCode is not valid in this calendar year');
        resolved = cal.monthFromCode(year, addAbsentCode(cal, p));
        if (resolved === 0) resolved = cal.monthsInYear(year);
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
          nm = p.leap ? cal.monthFromCode(y, addAbsentCode(cal, p)) : cal.monthsInYear(y);
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
          // a leap month absent from the target year constrains forwards to the next month and backwards to the plain month
          var cc = startCode;
          if (cal.monthFromCode(y, startCode) === 0) cc = absentLeapCode(cal, startCode, sign);
          var c = compareCodes(cc, endCode);
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
      if (bm === 0) bm = startCode.leap ? cal.monthFromCode(by, addAbsentCode(cal, startCode)) : cal.monthsInYear(by);
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
  function canonicalCalendarId(id, allowFallbacks) {
    var l = lower(id);
    if (!allowFallbacks && (l === 'islamic' || l === 'islamic-rgsa')) return undefined;
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
    if (isIsoCal(id) || !CALS[id].hasEras) return names;
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
    if (overflow === 'reject' && d.years !== 0) {
      var code = parseMonthCode(cal.monthCode(c.year, c.month));
      if (cal.monthFromCode(c.year + d.years, code) === 0) throw new RangeErr('the month does not exist in the target year');
    }
    var added = calAddDate(iso, d.years, d.months, 0, 0, 'constrain');
    return calYearMonthRef(id, added);
  }
  // The ISO reference date for a month-day: the latest date on or before 1972-12-31 in a calendar year where the month has that day (for the
  // Chinese calendars only within the years they are computed for, and the earliest one after 1972 when there is none before).
  function calMonthDayRef(id, monthCode, day, overflow) {
    var cal = CALS[id], p = parseMonthCode(monthCode);
    if (p === null || !calValidCode(cal, p)) throw new RangeErr('invalid monthCode');
    var cutoff = epochDays(1972, 12, 31), y0 = cal.fromDays(cutoff).year;
    var span = cal.refSpan, lo = span ? span[0] : y0 - 200, hi = span ? span[1] : y0 + 1;
    for (var attempt = 0; attempt < 2; attempt++) {
      var maxDay = 0, y, m;
      for (y = hi; y >= lo; y--) {
        m = cal.monthFromCode(y, p);
        if (m !== 0 && cal.daysInMonth(y, m) > maxDay) maxDay = cal.daysInMonth(y, m);
      }
      var want = day;
      if (maxDay !== 0 && want > maxDay) {
        if (overflow === 'reject') throw new RangeErr('day out of range');
        if (p.leap) { p = addAbsentCode(cal, p); continue; }
        want = maxDay;
      }
      if (maxDay !== 0) {
        for (y = mathMin(hi, y0 + 1); y >= lo; y--) {
          m = cal.monthFromCode(y, p);
          if (m === 0 || cal.daysInMonth(y, m) < want) continue;
          var days = cal.toDays(y, m, want);
          if (days <= cutoff) { var iso = dateFromEpochDays(days); iso.cal = id; return iso; }
        }
        if (span) {
          for (y = y0 + 1; y <= hi; y++) {
            m = cal.monthFromCode(y, p);
            if (m === 0 || cal.daysInMonth(y, m) < want) continue;
            var later = dateFromEpochDays(cal.toDays(y, m, want));
            later.cal = id;
            return later;
          }
        }
      }
      // no such month-day exists in the supported years: a leap month becomes the plain month
      if (!p.leap || overflow === 'reject') throw new RangeErr('no reference date for the month-day');
      p = addAbsentCode(cal, p);
    }
    throw new RangeErr('no reference date for the month-day');
  }
  function calMonthDayFromFields(id, f, overflow) {
    var cal = CALS[id];
    if (f.day === undefined) throw new TypeErr('day is required');
    var hasYear = f.year !== undefined || f.era !== undefined || f.eraYear !== undefined;
    if (f.month === undefined && f.monthCode === undefined) throw new TypeErr('month or monthCode is required');
    if (f.month !== undefined && !hasYear) throw new TypeErr('year is required when month is given');
    if (hasYear) {
      var iso = calDateFromFields(id, f, overflow), cf = calFields(id, iso);
      return calMonthDayRef(id, cf.monthCode, cf.day, overflow);
    }
    return calMonthDayRef(id, f.monthCode, f.day, overflow);
  }
  function monthDayFieldsOf(md) {
    if (isIsoCal(md.cal)) return { monthCode: monthCodeOf(md.month), day: md.day };
    var cf = calFields(md.cal, md);
    return { monthCode: cf.monthCode, day: cf.day };
  }
