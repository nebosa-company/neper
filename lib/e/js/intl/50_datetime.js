
  // ---------------------------------------------------------------- Intl.DateTimeFormat
  var tzNames = global.__tzNames, tzOffsetSeconds = global.__tzOffset, temporalInfo = global.__temporalFormat;
  var DateSlots = slotted('DateTimeFormat');
  var MONTHS_LONG = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  var DAYS_LONG = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  var zoneIndex = null;
  function zoneTable() {
    if (zoneIndex === null) {
      zoneIndex = create(null);
      var names = tzNames();
      for (var i = 0; i < names.length; i++) zoneIndex[lower(names[i])] = names[i];
    }
    return zoneIndex;
  }
  var RE_OFFSET_ID = /^([+−-])([0-9]{2})(?::?([0-9]{2}))?$/;
  function parseOffsetId(s) {
    var m = exec(RE_OFFSET_ID, s);
    if (m === null) return null;
    var h = +m[2], mi = m[3] === undefined ? 0 : +m[3];
    if (h > 23 || mi > 59) return null;
    return (m[1] === '-' || m[1] === '−' ? -1 : 1) * (h * 60 + mi);
  }
  function formatOffsetId(minutes) {
    var sign = minutes < 0 ? '-' : '+', a = minutes < 0 ? -minutes : minutes, h = mathFloor(a / 60), m = a % 60;
    return sign + (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
  }
  // The canonical time zone identifier, or undefined when it is not one.
  function canonicalTimeZone(id) {
    var off = parseOffsetId(id);
    if (off !== null) return { id: formatOffsetId(off), offsetMinutes: off };
    var name = zoneTable()[lower(id)];
    if (name !== undefined) return { id: name, offsetMinutes: null };
    return undefined;
  }
  function zoneOffsetMs(tz, ms) {
    if (tz.offsetMinutes !== null) return tz.offsetMinutes * 60000;
    if (tz.id === 'UTC') return 0;
    var s = tzOffsetSeconds(tz.id, ms);
    return s !== s ? 0 : s * 1000;
  }
  // Proleptic Gregorian civil date from days since 1970-01-01.
  function civilFromDays(z) {
    z += 719468;
    var era = mathFloor(z / 146097), doe = z - era * 146097;
    var yoe = mathFloor((doe - mathFloor(doe / 1460) + mathFloor(doe / 36524) - mathFloor(doe / 146096)) / 365);
    var y = yoe + era * 400, doy = doe - (365 * yoe + mathFloor(yoe / 4) - mathFloor(yoe / 100)), mp = mathFloor((5 * doy + 2) / 153);
    var d = doy - mathFloor((153 * mp + 2) / 5) + 1, m = mp < 10 ? mp + 3 : mp - 9;
    return { year: m <= 2 ? y + 1 : y, month: m, day: d };
  }
  function daysFromCivil(y, m, d) {
    if (m <= 2) y -= 1;
    var era = mathFloor(y / 400), yoe = y - era * 400, mp = (m + 9) % 12, doy = mathFloor((153 * mp + 2) / 5) + d - 1;
    return era * 146097 + yoe * 365 + mathFloor(yoe / 4) - mathFloor(yoe / 100) + doy - 719468;
  }
  function fieldsOf(ms, tz) {
    var local = ms + zoneOffsetMs(tz, ms), days = mathFloor(local / 86400000), rem = local - days * 86400000;
    var c = civilFromDays(days);
    return { year: c.year, month: c.month, day: c.day, weekday: ((days % 7) + 11) % 7, hour: mathFloor(rem / 3600000), minute: mathFloor(rem / 60000) % 60,
      second: mathFloor(rem / 1000) % 60, ms: rem % 1000 };
  }
  var US_ZONES = { 'America/New_York': ['EST', 'EDT', 'Eastern Standard Time', 'Eastern Daylight Time'], 'America/Chicago': ['CST', 'CDT', 'Central Standard Time', 'Central Daylight Time'],
    'America/Denver': ['MST', 'MDT', 'Mountain Standard Time', 'Mountain Daylight Time'], 'America/Los_Angeles': ['PST', 'PDT', 'Pacific Standard Time', 'Pacific Daylight Time'] };
  function two(n) { return n < 10 ? '0' + n : '' + n; }
  function offsetText(offMs, long) {
    var m = mathFloor(mathAbs(offMs) / 60000), h = mathFloor(m / 60), mm = m % 60, sign = offMs < 0 ? '-' : '+';
    if (long) return offMs === 0 ? 'GMT' : 'GMT' + sign + two(h) + ':' + two(mm);
    if (offMs === 0) return 'GMT';
    return 'GMT' + sign + h + (mm ? ':' + two(mm) : '');
  }
  function zoneNameText(tz, ms, style) {
    var off = zoneOffsetMs(tz, ms);
    if (style === 'shortOffset') return offsetText(off, false);
    if (style === 'longOffset') return offsetText(off, true);
    if (tz.id === 'UTC') return style === 'long' || style === 'longGeneric' ? 'Coordinated Universal Time' : 'UTC';
    if (has(US_ZONES, tz.id)) {
      var z = US_ZONES[tz.id], dst = off !== zoneOffsetMs(tz, Date.UTC(new Date(ms).getUTCFullYear(), 0, 1)) && tzOffsetSeconds(tz.id, ms) * 1000 > tzOffsetSeconds(tz.id, Date.UTC(new Date(ms).getUTCFullYear(), 0, 1)) * 1000;
      if (style === 'long') return dst ? z[3] : z[2];
      if (style === 'shortGeneric') return z[0].charAt(0) + 'T';
      if (style === 'longGeneric') return sliceS(z[2], 0, z[2].length - 14) + ' Time';
      return dst ? z[1] : z[0];
    }
    if (tz.offsetMinutes !== null) return offsetText(off, style === 'longOffset');
    return offsetText(off, style === 'long');
  }

  var RE_CAL = /^[a-z0-9]{3,8}(?:-[a-z0-9]{3,8})*$/i;
  var CALENDARS = ['gregory', 'buddhist', 'chinese', 'coptic', 'dangi', 'ethioaa', 'ethiopic', 'hebrew', 'indian', 'islamic', 'islamic-civil', 'islamic-rgsa', 'islamic-tbla', 'islamic-umalqura', 'iso8601', 'japanese', 'persian', 'roc'];
  function pickStyle(options, name, values) { return getOption(options, name, 'string', values, undefined); }
  // Internal records are null-prototype objects so that nothing on Object.prototype can intercept their fields.
  function nullObject(o) {
    var r = create(null), ks = Obj.keys(o);
    for (var i = 0; i < ks.length; i++) defineProperty(r, ks[i], { value: o[ks[i]], writable: true, enumerable: true, configurable: true });
    return r;
  }
  function createDateTimeFormat(o, locales, options, required, defaults, toLocaleStringTimeZone) {
    var requested = canonicalizeLocaleList(locales);
    options = coerceOptionsToObject(options);
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var calendar = getOption(options, 'calendar', 'string', undefined, undefined);
    if (calendar !== undefined && !test(RE_CAL, calendar)) throw new RangeErr('Invalid calendar');
    var numberingSystem = getOption(options, 'numberingSystem', 'string', undefined, undefined);
    if (numberingSystem !== undefined && !test(RE_NUMSYS, numberingSystem)) throw new RangeErr('Invalid numberingSystem');
    var hour12 = getOption(options, 'hour12', 'boolean', undefined, undefined);
    var hourCycle = getOption(options, 'hourCycle', 'string', ['h11', 'h12', 'h23', 'h24'], undefined);
    if (hour12 !== undefined) hourCycle = null;
    var opt = create(null);
    if (calendar !== undefined) opt.ca = lower(calendar);
    if (numberingSystem !== undefined) opt.nu = lower(numberingSystem);
    if (hourCycle !== undefined && hourCycle !== null) opt.hc = hourCycle;
    var r = resolveLocale(AVAILABLE, requested, opt, ['ca', 'hc', 'nu'], { ca: CALENDARS, hc: ['h12', 'h23', 'h11', 'h24'], nu: NUMBERING_SYSTEMS });
    var dt = nullObject({ locale: r.locale, calendar: r.ca, numberingSystem: r.nu, boundFormat: undefined });
    var timeZone = options.timeZone;
    if (timeZone === undefined) timeZone = toLocaleStringTimeZone !== undefined ? toLocaleStringTimeZone : 'UTC';
    else timeZone = toStr(timeZone);
    var tz = canonicalTimeZone(timeZone);
    if (tz === undefined) throw new RangeErr('Invalid time zone specified: ' + timeZone);
    dt.timeZone = tz;
    var f = nullObject({ weekday: pickStyle(options, 'weekday', ['narrow', 'short', 'long']), era: pickStyle(options, 'era', ['narrow', 'short', 'long']),
      year: pickStyle(options, 'year', ['2-digit', 'numeric']), month: pickStyle(options, 'month', ['2-digit', 'numeric', 'narrow', 'short', 'long']),
      day: pickStyle(options, 'day', ['2-digit', 'numeric']), dayPeriod: pickStyle(options, 'dayPeriod', ['narrow', 'short', 'long']),
      hour: pickStyle(options, 'hour', ['2-digit', 'numeric']), minute: pickStyle(options, 'minute', ['2-digit', 'numeric']),
      second: pickStyle(options, 'second', ['2-digit', 'numeric']) });
    f.fractionalSecondDigits = getNumberOption(options, 'fractionalSecondDigits', 1, 3, undefined);
    f.timeZoneName = pickStyle(options, 'timeZoneName', ['short', 'long', 'shortOffset', 'longOffset', 'shortGeneric', 'longGeneric']);
    var formatMatcher = getOption(options, 'formatMatcher', 'string', ['basic', 'best fit'], 'best fit');
    var dateStyle = getOption(options, 'dateStyle', 'string', ['full', 'long', 'medium', 'short'], undefined);
    var timeStyle = getOption(options, 'timeStyle', 'string', ['full', 'long', 'medium', 'short'], undefined);
    dt.raw = nullObject({ f: f, dateStyle: dateStyle, timeStyle: timeStyle, hour12: hour12, hourCycle: hourCycle, locHc: r.hc, explicitZone: options.timeZone !== undefined });
    applyDefaults(dt, required, defaults);
    DateSlots.set(o, dt);
  }
  var FIELD_KEYS = ['weekday', 'era', 'year', 'month', 'day', 'dayPeriod', 'hour', 'minute', 'second', 'fractionalSecondDigits'];
  function anyField(f, names) { for (var i = 0; i < names.length; i++) if (f[names[i]] !== undefined) return true; return false; }
  var DATE_KEYS = ['weekday', 'year', 'month', 'day'], TIME_KEYS = ['dayPeriod', 'hour', 'minute', 'second', 'fractionalSecondDigits'];
  // Sets dt.f / dt.dateStyle / dt.timeStyle / dt.hourCycle from the explicit options and the required/defaults of the caller.
  function applyDefaults(dt, required, defaults) {
    var raw = dt.raw, f = create(null), k;
    for (k in raw.f) f[k] = raw.f[k];
    var dateStyle = raw.dateStyle, timeStyle = raw.timeStyle;
    var hasExplicit = anyField(f, FIELD_KEYS) || f.timeZoneName !== undefined;
    dt.dateStyle = undefined; dt.timeStyle = undefined;
    if (dateStyle !== undefined || timeStyle !== undefined) {
      if (hasExplicit) throw new TypeErr('Can\'t set option when dateStyle or timeStyle is used');
      if (required === 'date' && timeStyle !== undefined) throw new TypeErr('Invalid option : timeStyle');
      if (required === 'time' && dateStyle !== undefined) throw new TypeErr('Invalid option : dateStyle');
      dt.dateStyle = dateStyle; dt.timeStyle = timeStyle;
    } else {
      var needDefaults = true;
      if (required === 'date' || required === 'any') if (anyField(f, DATE_KEYS)) needDefaults = false;
      if (required === 'time' || required === 'any') if (anyField(f, TIME_KEYS)) needDefaults = false;
      if (needDefaults && (defaults === 'date' || defaults === 'all')) { f.year = 'numeric'; f.month = 'numeric'; f.day = 'numeric'; }
      if (needDefaults && (defaults === 'time' || defaults === 'all')) { f.hour = 'numeric'; f.minute = 'numeric'; f.second = 'numeric'; }
    }
    dt.hourCycle = undefined;
    if (f.hour !== undefined || timeStyle !== undefined) {
      var hc = raw.locHc === undefined || raw.locHc === null ? 'h12' : raw.locHc;
      if (raw.hour12 !== undefined) hc = raw.hour12 ? 'h12' : 'h23';
      else if (raw.hourCycle !== undefined && raw.hourCycle !== null) hc = raw.hourCycle;
      dt.hourCycle = hc;
    }
    dt.f = f;
  }
  // ---- Temporal objects
  var UTC_ZONE = { id: 'UTC', offsetMinutes: null };
  var ALLOWED = {
    PlainDate: ['weekday', 'era', 'year', 'month', 'day'], PlainTime: TIME_KEYS, PlainDateTime: FIELD_KEYS, PlainYearMonth: ['era', 'year', 'month'],
    PlainMonthDay: ['month', 'day'], Instant: FIELD_KEYS.concat ? FIELD_KEYS : FIELD_KEYS, ZonedDateTime: FIELD_KEYS
  };
  var TEMPORAL_DEFAULTS = {
    PlainDate: { year: 'numeric', month: 'numeric', day: 'numeric' }, PlainTime: { hour: 'numeric', minute: 'numeric', second: 'numeric' },
    PlainDateTime: { year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' },
    PlainYearMonth: { year: 'numeric', month: 'numeric' }, PlainMonthDay: { month: 'numeric', day: 'numeric' },
    Instant: { year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' },
    ZonedDateTime: { year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric', timeZoneName: 'short' }
  };
  // The format settings that apply to a Temporal object's data model, and the calendar fields to format.
  function temporalVariant(dt, info) {
    var type = info.type, allowed = ALLOWED[type], raw = dt.raw, k;
    var strictCal = type === 'PlainYearMonth' || type === 'PlainMonthDay';
    if (!(info.cal === dt.calendar || (!strictCal && info.cal === 'iso8601'))) throw new RangeErr('calendars do not match');
    if (raw.dateStyle !== undefined && raw.timeStyle !== undefined && (type === 'PlainDate' || type === 'PlainTime' || type === 'PlainYearMonth' || type === 'PlainMonthDay')) throw new TypeErr('dateStyle and timeStyle cannot both be used with ' + type);
    var eff = (raw.dateStyle !== undefined || raw.timeStyle !== undefined) ? stylesToFields({ dateStyle: raw.dateStyle, timeStyle: raw.timeStyle }) : create(null);
    if (raw.dateStyle === undefined && raw.timeStyle === undefined) for (k in raw.f) if (raw.f[k] !== undefined) eff[k] = raw.f[k];
    var requested = false, kept = create(null);
    for (k in eff) {
      if (k === 'timeZoneName') continue;
      if (k !== 'era') requested = true;
      if (allowed.indexOf(k) >= 0) kept[k] = eff[k];
    }
    var f;
    if (!requested) {
      f = create(null);
      for (k in TEMPORAL_DEFAULTS[type]) f[k] = TEMPORAL_DEFAULTS[type][k];
      if (kept.era !== undefined) f.era = kept.era;
      if ((type === 'ZonedDateTime' || type === 'Instant') && eff.timeZoneName !== undefined) f.timeZoneName = eff.timeZoneName;
    } else {
      if (!anyField(kept, FIELD_KEYS)) throw new TypeErr('the options do not overlap the Temporal object\'s data');
      f = kept;
      if ((type === 'Instant' || type === 'ZonedDateTime') && eff.timeZoneName !== undefined) f.timeZoneName = eff.timeZoneName;
    }
    var v = nullObject({ locale: dt.locale, calendar: dt.calendar, f: f, joinAt: raw.dateStyle === 'full' || raw.dateStyle === 'long', hourCycle: dt.hourCycle, numberingSystem: dt.numberingSystem });
    if (f.hour !== undefined && v.hourCycle === undefined) {
      var hc = raw.locHc === undefined || raw.locHc === null ? 'h12' : raw.locHc;
      if (raw.hour12 !== undefined) hc = raw.hour12 ? 'h12' : 'h23';
      else if (raw.hourCycle !== undefined && raw.hourCycle !== null) hc = raw.hourCycle;
      v.hourCycle = hc;
    }
    if (type === 'Instant') v.timeZone = dt.timeZone;
    else if (type === 'ZonedDateTime') v.timeZone = canonicalTimeZone(info.tzId);
    else v.timeZone = UTC_ZONE;
    return v;
  }
  function isoFieldsOf(info) {
    var days = daysFromCivil(info.y === undefined ? 1970 : info.y, info.mo === undefined ? 1 : info.mo, info.d === undefined ? 1 : info.d);
    return { year: info.y === undefined ? 1970 : info.y, month: info.mo === undefined ? 1 : info.mo, day: info.d === undefined ? 1 : info.d,
      weekday: ((days % 7) + 11) % 7, hour: info.h || 0, minute: info.mi || 0, second: info.s || 0, ms: info.ms || 0 };
  }
  // ---- composition
  function monthText(m, style) {
    var n = MONTHS_LONG[m - 1];
    if (style === 'long') return n;
    if (style === 'narrow') return n.charAt(0);
    return sliceS(n, 0, 3);
  }
  function weekdayText(d, style) {
    var n = DAYS_LONG[d];
    if (style === 'long') return n;
    if (style === 'narrow') return n.charAt(0);
    return sliceS(n, 0, 3);
  }
  function lit(v) { return { type: 'literal', value: v }; }
  function part(t, v) { return { type: t, value: v }; }
  function datePartsFor(dt, f, c, ms) {
    var parts = [], textual = f.month === 'long' || f.month === 'short' || f.month === 'narrow';
    var yearBC = c.year <= 0, yv = yearBC ? 1 - c.year : c.year;
    var yearStr = f.year === '2-digit' ? two(yv % 100) : '' + yv;
    var monthStr = f.month === undefined ? undefined : (textual ? monthText(c.month, f.month) : (f.month === '2-digit' ? two(c.month) : '' + c.month));
    var dayStr = f.day === undefined ? undefined : (f.day === '2-digit' ? two(c.day) : '' + c.day);
    var eraStr = f.era === undefined ? undefined : (f.era === 'long' ? (yearBC ? 'Before Christ' : 'Anno Domini') : f.era === 'narrow' ? (yearBC ? 'B' : 'A') : (yearBC ? 'BC' : 'AD'));
    if (f.weekday !== undefined) {
      push(parts, part('weekday', weekdayText(c.weekday, f.weekday)));
      if (monthStr !== undefined || dayStr !== undefined || f.year !== undefined) push(parts, lit(', '));
    }
    if (textual) {
      if (monthStr !== undefined) push(parts, part('month', monthStr));
      if (dayStr !== undefined) { push(parts, lit(' ')); push(parts, part('day', dayStr)); }
      if (f.year !== undefined) { push(parts, lit(dayStr !== undefined ? ', ' : ' ')); push(parts, part('year', yearStr)); }
    } else {
      var first = true;
      if (monthStr !== undefined) { push(parts, part('month', monthStr)); first = false; }
      if (dayStr !== undefined) { if (!first) push(parts, lit('/')); push(parts, part('day', dayStr)); first = false; }
      if (f.year !== undefined) { if (!first) push(parts, lit('/')); push(parts, part('year', yearStr)); }
    }
    if (eraStr !== undefined) { if (parts.length) push(parts, lit(' ')); push(parts, part('era', eraStr)); }
    return parts;
  }
  function timePartsFor(dt, f, c, ms) {
    var parts = [], hc = dt.hourCycle || 'h12', h = c.hour, period = null;
    if (f.hour !== undefined) {
      var hv = h;
      if (hc === 'h12') { period = h < 12 ? 'AM' : 'PM'; hv = h % 12 === 0 ? 12 : h % 12; }
      else if (hc === 'h11') { period = h < 12 ? 'AM' : 'PM'; hv = h % 12; }
      else if (hc === 'h24') hv = h === 0 ? 24 : h;
      var hs = (f.hour === '2-digit' || ((hc === 'h23' || hc === 'h24') && (f.minute !== undefined))) ? two(hv) : '' + hv;
      push(parts, part('hour', hs));
    }
    if (f.minute !== undefined) {
      if (parts.length) push(parts, lit(':'));
      push(parts, part('minute', f.hour !== undefined || f.second !== undefined ? two(c.minute) : (f.minute === '2-digit' ? two(c.minute) : '' + c.minute)));
    }
    if (f.second !== undefined) {
      if (parts.length) push(parts, lit(':'));
      push(parts, part('second', f.minute !== undefined || f.hour !== undefined ? two(c.second) : (f.second === '2-digit' ? two(c.second) : '' + c.second)));
    }
    if (f.fractionalSecondDigits !== undefined) {
      var fs = ('00' + c.ms), fsd = sliceS(sliceS(fs, fs.length - 3), 0, f.fractionalSecondDigits);
      if (parts.length) push(parts, lit('.'));
      push(parts, part('fractionalSecond', fsd));
    }
    if (f.hour !== undefined && period !== null) { push(parts, lit(' ')); push(parts, part('dayPeriod', period)); }
    else if (f.dayPeriod !== undefined && f.hour === undefined) {
      var dp = h >= 6 && h < 12 ? 'in the morning' : h === 12 && c.minute === 0 ? 'noon' : h >= 12 && h < 18 ? 'in the afternoon' : h >= 18 && h < 21 ? 'in the evening' : 'at night';
      if (parts.length) push(parts, lit(' '));
      push(parts, part('dayPeriod', dp));
    }
    return parts;
  }
  function stylesToFields(dt) {
    var f = create(null), ds = dt.dateStyle, ts = dt.timeStyle;
    if (ds === 'full') { f.weekday = 'long'; f.month = 'long'; f.day = 'numeric'; f.year = 'numeric'; }
    else if (ds === 'long') { f.month = 'long'; f.day = 'numeric'; f.year = 'numeric'; }
    else if (ds === 'medium') { f.month = 'short'; f.day = 'numeric'; f.year = 'numeric'; }
    else if (ds === 'short') { f.month = 'numeric'; f.day = 'numeric'; f.year = '2-digit'; }
    if (ts !== undefined) { f.hour = 'numeric'; f.minute = '2-digit'; if (ts !== 'short') f.second = '2-digit'; if (ts === 'full') f.timeZoneName = 'long'; else if (ts === 'long') f.timeZoneName = 'short'; }
    return f;
  }
  function formatToPartsInternal(dt, ms, fixed) {
    if (ms !== ms || ms > 8.64e15 || ms < -8.64e15) throw new RangeErr('Invalid time value');
    ms = ms < 0 ? -mathFloor(-ms) : mathFloor(ms);
    var f = (dt.dateStyle !== undefined || dt.timeStyle !== undefined) ? stylesToFields(dt) : dt.f;
    var c = fixed || fieldsOf(ms, dt.timeZone), parts = [];
    var dparts = datePartsFor(dt, f, c, ms), hasDate = f.weekday !== undefined || f.year !== undefined || f.month !== undefined || f.day !== undefined || f.era !== undefined;
    var tparts = timePartsFor(dt, f, c, ms), hasTime = f.hour !== undefined || f.minute !== undefined || f.second !== undefined || f.fractionalSecondDigits !== undefined || (f.dayPeriod !== undefined);
    for (var i = 0; i < dparts.length; i++) push(parts, dparts[i]);
    if (hasDate && hasTime) push(parts, lit((dt.joinAt || dt.dateStyle === 'full' || dt.dateStyle === 'long') ? ' at ' : ', '));
    for (var j = 0; j < tparts.length; j++) push(parts, tparts[j]);
    if (f.timeZoneName !== undefined) {
      if (parts.length) push(parts, lit(' '));
      push(parts, part('timeZoneName', zoneNameText(dt.timeZone, ms, f.timeZoneName)));
    }
    if (dt.numberingSystem !== undefined && dt.numberingSystem !== 'latn') {
      for (var np = 0; np < parts.length; np++) {
        var pt = parts[np].type;
        if (pt === 'year' || pt === 'month' || pt === 'day' || pt === 'hour' || pt === 'minute' || pt === 'second' || pt === 'fractionalSecond') parts[np].value = mapDigits(parts[np].value, dt.numberingSystem);
      }
    }
    return parts;
  }
  function partsString(parts) { var s = ''; for (var i = 0; i < parts.length; i++) s += parts[i].value; return s; }
  // The parts for a value given to format(): a Date value, or a Temporal object (ZonedDateTime only through toLocaleString).
  function partsFor(dt, date, viaToLocaleString) {
    if (date === undefined) return formatToPartsInternal(dt, Date.now());
    var info = isObject(date) && temporalInfo !== undefined ? temporalInfo(date) : undefined;
    if (info === undefined) return formatToPartsInternal(dt, timeClip(+date));
    if (info.type === 'ZonedDateTime' && !viaToLocaleString) throw new TypeErr('format() does not support Temporal.ZonedDateTime');
    var v = temporalVariant(dt, info);
    if (info.type === 'Instant' || info.type === 'ZonedDateTime') return formatToPartsInternal(v, timeClip(info.epochMs));
    return formatToPartsInternal(v, 0, isoFieldsOf(info));
  }
  var TIME_TYPES = ['hour', 'minute', 'second', 'fractionalSecond', 'dayPeriod'];
  function firstTimePart(parts) {
    for (var i = 0; i < parts.length; i++) if (TIME_TYPES.indexOf(parts[i].type) >= 0) return i;
    return -1;
  }
  // When both ends are on the same date, the end keeps only its time (and zone name).
  function collapseSharedDate(pa, pb) {
    var ia = firstTimePart(pa), ib = firstTimePart(pb);
    if (ia <= 0 || ib <= 0 || ia !== ib) return null;
    for (var i = 0; i < ia; i++) if (pa[i].value !== pb[i].value) return null;
    return apply(arrSlice, pb, [ib]);
  }
  function temporalKind(date) {
    var info = isObject(date) && temporalInfo !== undefined ? temporalInfo(date) : undefined;
    return info === undefined ? undefined : info.type;
  }
  function rangeParts(dt, start, end) {
    var ka = temporalKind(start), kb = temporalKind(end);
    if (ka !== kb) throw new TypeErr('startDate and endDate must be the same kind of value');
    if (ka === 'ZonedDateTime') throw new TypeErr('formatRange() does not support Temporal.ZonedDateTime');
    return [partsFor(dt, start), partsFor(dt, end)];
  }
  function DateTimeFormat() {
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var nt = new.target === undefined ? DateTimeFormat : new.target;
    var o = create(getPrototypeFromNewTarget(nt, DateTimeFormat.prototype));
    createDateTimeFormat(o, locales, options, 'any', 'date');
    return o;
  }
  function timeClip(x) {
    if (x !== x || x > 8.64e15 || x < -8.64e15) return NaN;
    return x < 0 ? -mathFloor(-x) : mathFloor(x);
  }
  var dateTimeMethods = {
    get format() {
      var dt = DateSlots.get(this);
      if (dt.boundFormat === undefined) {
        var f = (date) => partsString(partsFor(dt, date));
        fnNamed(f, '', 1);
        dt.boundFormat = f;
      }
      return dt.boundFormat;
    },
    formatToParts(date) {
      var dt = DateSlots.get(this), parts = partsFor(dt, date), out = [];
      for (var i = 0; i < parts.length; i++) push(out, { type: parts[i].type, value: parts[i].value });
      return out;
    },
    formatRange(start, end) {
      var dt = DateSlots.get(this);
      if (start === undefined || end === undefined) throw new TypeErr('startDate and endDate are required');
      var pr = rangeParts(dt, start, end), a = partsString(pr[0]), b = partsString(pr[1]);
      if (a === b) return a;
      var col = collapseSharedDate(pr[0], pr[1]);
      return a + '\u2009\u2013\u2009' + (col === null ? b : partsString(col));
    },
    formatRangeToParts(start, end) {
      var dt = DateSlots.get(this);
      if (start === undefined || end === undefined) throw new TypeErr('startDate and endDate are required');
      var pr = rangeParts(dt, start, end), pa = pr[0], pb = pr[1], out = [];
      if (partsString(pa) === partsString(pb)) { for (var s = 0; s < pa.length; s++) push(out, { type: pa[s].type, value: pa[s].value, source: 'shared' }); return out; }
      var col = collapseSharedDate(pa, pb), tail = col === null ? pb : col, timeAt = col === null ? -1 : firstTimePart(pa);
      for (var i = 0; i < pa.length; i++) push(out, { type: pa[i].type, value: pa[i].value, source: (timeAt >= 0 && i < timeAt - 1) ? 'shared' : 'startRange' });
      push(out, { type: 'literal', value: '\u2009\u2013\u2009', source: 'shared' });
      for (var j = 0; j < tail.length; j++) push(out, { type: tail[j].type, value: tail[j].value, source: 'endRange' });
      return out;
    },
    resolvedOptions() {
      var dt = DateSlots.get(this), r = { locale: dt.locale, calendar: dt.calendar, numberingSystem: dt.numberingSystem, timeZone: dt.timeZone.id };
      if (dt.hourCycle !== undefined) { r.hourCycle = dt.hourCycle; r.hour12 = dt.hourCycle === 'h11' || dt.hourCycle === 'h12'; }
      var f = dt.f, keys = ['weekday', 'era', 'year', 'month', 'day', 'dayPeriod', 'hour', 'minute', 'second', 'fractionalSecondDigits', 'timeZoneName'];
      if (dt.dateStyle === undefined && dt.timeStyle === undefined) {
        for (var i = 0; i < keys.length; i++) {
          var v = f[keys[i]];
          if (v === undefined) continue;
          if ((keys[i] === 'minute' || keys[i] === 'second') && (f.hour !== undefined || (keys[i] === 'second' && f.minute !== undefined))) v = '2-digit';
          defineProperty(r, keys[i], { value: v, writable: true, enumerable: true, configurable: true });
        }
      }
      if (dt.dateStyle !== undefined) r.dateStyle = dt.dateStyle;
      if (dt.timeStyle !== undefined) r.timeStyle = dt.timeStyle;
      return r;
    }
  };
  installProto(DateTimeFormat, dateTimeMethods, 'Intl.DateTimeFormat');
  makeSupportedLocalesOf(DateTimeFormat, function () { return AVAILABLE; });
  define(Intl, 'DateTimeFormat', DateTimeFormat);

  // Date.prototype.toLocale*String
  var dateGetTime = Date.prototype.getTime;
  function dateLocaleMethod(name, required, defaults) {
    var m = {
      [name](locales, options) {
        var x = apply(dateGetTime, this, []);
        if (x !== x) return 'Invalid Date';
        var o = create(DateTimeFormat.prototype);
        createDateTimeFormat(o, arguments.length > 0 ? arguments[0] : undefined, arguments.length > 1 ? arguments[1] : undefined, required, defaults);
        return partsString(formatToPartsInternal(DateSlots.get(o), x));
      }
    };
    define(Date.prototype, name, defineLen(m[name], 0));
  }
  dateLocaleMethod('toLocaleString', 'any', 'all');
  dateLocaleMethod('toLocaleDateString', 'date', 'date');
  dateLocaleMethod('toLocaleTimeString', 'time', 'time');

  // Temporal.*.prototype.toLocaleString
  function temporalToLocaleString(name, isZoned) {
    var C = global.Temporal && global.Temporal[name];
    if (C === undefined) return;
    var m = {
      toLocaleString() {
        var self = this, info = temporalInfo(self);
        if (info === undefined || info.type !== name) throw new TypeErr('not a Temporal.' + name);
        var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
        var o = create(DateTimeFormat.prototype);
        if (isZoned) {
          var opts = coerceOptionsToObject(options), tzOpt = opts.timeZone;
          if (tzOpt !== undefined) throw new TypeErr('the timeZone option is not allowed in ZonedDateTime.toLocaleString');
          createDateTimeFormat(o, locales, opts, 'any', 'all', info.tzId);
        } else createDateTimeFormat(o, locales, options, 'any', 'date');
        return partsString(partsFor(DateSlots.get(o), self, true));
      }
    };
    define(C.prototype, 'toLocaleString', defineLen(m.toLocaleString, 0));
  }
  var TEMPORAL_NAMES = ['Instant', 'PlainDate', 'PlainDateTime', 'PlainTime', 'PlainYearMonth', 'PlainMonthDay', 'ZonedDateTime'];
  if (temporalInfo !== undefined) for (var tn = 0; tn < TEMPORAL_NAMES.length; tn++) temporalToLocaleString(TEMPORAL_NAMES[tn], TEMPORAL_NAMES[tn] === 'ZonedDateTime');
