  // ---------------------------------------------------------------- ISO 8601 / RFC 9557 string parsing
  var RE_TZ_NAME = /^[A-Za-z_.][A-Za-z0-9_.+-]*(?:\/[A-Za-z_.][A-Za-z0-9_.+-]*)*$/;
  var RE_TZ_OFFSET_ANN = /^[+-][0-9]{2}(?::?[0-9]{2})?$/;
  var RE_ANN_KEY = /^[a-z_][a-z0-9_-]*$/;
  var RE_ANN_VALUE = /^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$/;
  var RE_MONTHDAY = /^(?:--)?([0-9]{2})-?([0-9]{2})$/;
  var RE_YEARMONTH = /^([+-][0-9]{6}|[0-9]{4})-?([0-9]{2})$/;

  function isDigit(c) { return c !== undefined && c >= '0' && c <= '9'; }
  function reject() { throw new RangeErr('invalid ISO 8601 string'); }

  function parseAnnotations(text, rec) {
    var i = 0, first = true, calendarCount = 0, criticalCalendar = false;
    while (i < text.length) {
      if (text[i] !== '[') reject();
      var end = apply(strIndexOf, text, [']', i]);
      if (end < 0) reject();
      var body = sliceS(text, i + 1, end);
      i = end + 1;
      var critical = false;
      if (body[0] === '!') { critical = true; body = sliceS(body, 1); }
      var eq = apply(strIndexOf, body, ['=']);
      if (eq < 0) {
        if (!first) reject();
        if (exec(RE_TZ_OFFSET_ANN, body) !== null) rec.tz = body;
        else if (exec(RE_TZ_NAME, body) !== null) rec.tz = body;
        else reject();
        rec.tzCritical = critical;
      } else {
        var key = sliceS(body, 0, eq), value = sliceS(body, eq + 1);
        if (exec(RE_ANN_KEY, key) === null || exec(RE_ANN_VALUE, value) === null) reject();
        if (key === 'u-ca') {
          calendarCount++;
          if (critical) criticalCalendar = true;
          if (rec.calendar === undefined) rec.calendar = value;
        } else if (critical) reject();
      }
      first = false;
    }
    if (calendarCount > 1 && criticalCalendar) reject();
  }

  function parseOffsetAt(s, p, rec) {
    // s[p] is the sign; returns the position after the offset
    var neg = s[p] !== '+';
    p++;
    function two() {
      if (!isDigit(s[p]) || !isDigit(s[p + 1])) reject();
      var n = (s.charCodeAt(p) - 48) * 10 + (s.charCodeAt(p + 1) - 48);
      p += 2;
      return n;
    }
    var h = two(), mi = 0, sec = 0, frac = 0, ext = false, hadMin = false, hasSec = false;
    if (h > 23) reject();
    if (s[p] === ':') { ext = true; p++; mi = two(); hadMin = true; }
    else if (isDigit(s[p])) { mi = two(); hadMin = true; }
    if (mi > 59) reject();
    if (hadMin) {
      if (ext && s[p] === ':') { p++; sec = two(); hasSec = true; if (sec > 59) reject(); p = readFraction(); }
      else if (!ext && isDigit(s[p])) { sec = two(); hasSec = true; if (sec > 59) reject(); p = readFraction(); }
    }
    function readFraction() {
      if (s[p] === '.' || s[p] === ',') {
        p++;
        var start = p;
        while (isDigit(s[p])) p++;
        var digits = sliceS(s, start, p);
        if (digits.length < 1 || digits.length > 9) reject();
        frac = Num(digits + repeat('0', 9 - digits.length));
      }
      return p;
    }
    var total = ((h * 60 + mi) * 60 + sec) * 1000000000 + frac;
    rec.offsetNs = neg ? -total : total;
    rec.offsetSubMinute = hasSec;
    return p;
  }

  // Parses `s` as a date, a date-time, or a time; the callers check which parts they need. `kind` only selects the extra
  // month-day / year-month / time-only shapes.
  function parseISOString(s, kind) {
    if (typeof s !== 'string') throw new TypeErr('value must be a string');
    var rec = { year: undefined, month: undefined, day: undefined, hasTime: false, hour: 0, minute: 0, second: 0, millisecond: 0,
      microsecond: 0, nanosecond: 0, z: false, offsetNs: undefined, offsetSubMinute: false, tz: undefined, tzCritical: false,
      calendar: undefined, hasDate: false, timeOnly: false };
    var br = apply(strIndexOf, s, ['[']);
    var main = br < 0 ? s : sliceS(s, 0, br);
    parseAnnotations(br < 0 ? '' : sliceS(s, br), rec);
    var m;
    if (kind === 'monthday') {
      m = exec(RE_MONTHDAY, main);
      if (m !== null) {
        rec.month = +m[1]; rec.day = +m[2];
        if (rec.month < 1 || rec.month > 12 || rec.day < 1 || rec.day > daysInMonth(1972, rec.month)) reject();
        rec.hasDate = true;
        rec.monthDayOnly = true;
        return rec;
      }
    }
    if (kind === 'yearmonth') {
      m = exec(RE_YEARMONTH, main);
      if (m !== null) {
        var ys = m[1];
        rec.year = signedYear(ys); rec.month = +m[2];
        if (rec.month < 1 || rec.month > 12) reject();
        rec.hasDate = true;
        rec.day = 1;
        rec.yearMonthOnly = true;
        return rec;
      }
    }
    var p = 0;
    var c0 = main[0];
    var tried = false;
    if (kind === 'time' && (c0 === 'T' || c0 === 't')) {
      rec.timeOnly = true;
      p = parseTimeAt(main, 1, rec);
      p = parseZoneAt(main, p, rec);
      if (p !== main.length) reject();
      return rec;
    }
    var save = null;
    try {
      p = parseDateAt(main, 0, rec);
      rec.hasDate = true;
      var sep = main[p];
      if (sep === 'T' || sep === 't' || sep === ' ') {
        p = parseTimeAt(main, p + 1, rec);
        p = parseZoneAt(main, p, rec);
      }
      if (p !== main.length) reject();
      return rec;
    } catch (e) {
      if (kind !== 'time') throw e;
      save = e;
    }
    // time-only without the T designator: must not also read as a month-day or a year-month
    rec.hasDate = false; rec.year = rec.month = rec.day = undefined; rec.z = false; rec.offsetNs = undefined; rec.hasTime = false;
    p = parseTimeAt(main, 0, rec);
    p = parseZoneAt(main, p, rec);
    if (p !== main.length) throw save;
    var md = exec(RE_MONTHDAY, main), ym = exec(RE_YEARMONTH, main);
    if (md !== null && +md[1] >= 1 && +md[1] <= 12 && +md[2] >= 1 && +md[2] <= daysInMonth(1972, +md[1])) reject();
    if (ym !== null && +ym[2] >= 1 && +ym[2] <= 12) reject();
    rec.timeOnly = true;
    return rec;
  }
  function signedYear(ys) {
    if (ys[0] === '+' || ys[0] === '-') {
      var n = +sliceS(ys, 1);
      if (ys[0] === '-' && n === 0) reject();
      return ys[0] === '+' ? n : -n;
    }
    return +ys;
  }
  function parseDateAt(s, p, rec) {
    var start = p, yl;
    if (s[p] === '+' || s[p] === '-') yl = 7; else yl = 4;
    var ystr = sliceS(s, p, p + yl);
    if (yl === 7) { for (var i = 1; i < 7; i++) if (!isDigit(ystr[i])) reject(); }
    else for (var j = 0; j < 4; j++) if (!isDigit(ystr[j])) reject();
    rec.year = signedYear(ystr);
    p += yl;
    var ext = s[p] === '-';
    if (ext) p++;
    if (!isDigit(s[p]) || !isDigit(s[p + 1])) reject();
    rec.month = (s.charCodeAt(p) - 48) * 10 + (s.charCodeAt(p + 1) - 48);
    p += 2;
    if (ext) { if (s[p] !== '-') reject(); p++; }
    if (!isDigit(s[p]) || !isDigit(s[p + 1])) reject();
    rec.day = (s.charCodeAt(p) - 48) * 10 + (s.charCodeAt(p + 1) - 48);
    p += 2;
    if (!isValidDate(rec.year, rec.month, rec.day)) reject();
    return p;
  }
  function parseTimeAt(s, p, rec) {
    function two() {
      if (!isDigit(s[p]) || !isDigit(s[p + 1])) reject();
      var n = (s.charCodeAt(p) - 48) * 10 + (s.charCodeAt(p + 1) - 48);
      p += 2;
      return n;
    }
    var h = two(), mi = 0, sec = 0, ext = false, fracDigits = '';
    if (h > 23) reject();
    if (s[p] === ':') { ext = true; p++; mi = two(); }
    else if (isDigit(s[p])) mi = two();
    if (mi > 59) reject();
    var gotSeconds = false;
    if (ext) { if (s[p] === ':') { p++; sec = two(); gotSeconds = true; } }
    else if (isDigit(s[p])) { sec = two(); gotSeconds = true; }
    if (gotSeconds) {
      if (sec > 60) reject();
      if (sec === 60) sec = 59;
      if (s[p] === '.' || s[p] === ',') {
        p++;
        var st = p;
        while (isDigit(s[p])) p++;
        fracDigits = sliceS(s, st, p);
        if (fracDigits.length < 1 || fracDigits.length > 9) reject();
      }
    }
    var f = fracDigits + repeat('0', 9 - fracDigits.length);
    rec.hasTime = true;
    rec.hour = h; rec.minute = mi; rec.second = sec;
    rec.millisecond = +sliceS(f, 0, 3); rec.microsecond = +sliceS(f, 3, 6); rec.nanosecond = +sliceS(f, 6, 9);
    return p;
  }
  function parseZoneAt(s, p, rec) {
    var c = s[p];
    if (c === 'Z' || c === 'z') { rec.z = true; return p + 1; }
    if (c === '+' || c === '-') return parseOffsetAt(s, p, rec);
    return p;
  }

  // "+HH:MM" style offset strings as accepted for the `offset` property and time-zone identifiers; returns nanoseconds.
  var RE_OFFSET_ONLY = /^[+-][0-9]{2}(?::?[0-9]{2})?$/;
  var RE_OFFSET_SUB = /^[+-][0-9]{2}(?::?[0-9]{2}(?::?[0-9]{2}(?:[.,][0-9]{1,9})?)?)?$/;
  function parseOffsetString(s, subMinute) {
    if (exec(subMinute ? RE_OFFSET_SUB : RE_OFFSET_ONLY, s) === null) throw new RangeErr('invalid UTC offset: ' + s);
    var rec = {};
    var end = parseOffsetAt(s, 0, rec);
    if (end !== s.length) throw new RangeErr('invalid UTC offset: ' + s);
    return rec.offsetNs;
  }
