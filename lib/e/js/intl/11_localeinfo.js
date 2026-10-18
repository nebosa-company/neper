
  // ---------------------------------------------------------------- Intl.Locale info methods (a small built-in data set)
  var FW_NAMES = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
  var WEEK_DATA = { US: [7, [6, 7], 1], CA: [7, [6, 7], 1], BR: [7, [6, 7], 1], MX: [7, [6, 7], 1], JP: [7, [6, 7], 1], IN: [7, [7], 1], IL: [7, [5, 6], 1], SA: [7, [5, 6], 1],
    EG: [6, [5, 6], 1], GB: [1, [6, 7], 4], DE: [1, [6, 7], 4], FR: [1, [6, 7], 4], IT: [1, [6, 7], 4], ES: [1, [6, 7], 4], NL: [1, [6, 7], 4], SE: [1, [6, 7], 4], RU: [1, [6, 7], 1],
    CN: [1, [6, 7], 1], KR: [7, [6, 7], 1], AU: [1, [6, 7], 1], AF: [6, [4, 5], 1] };
  var H12_REGIONS = ['US', 'CA', 'AU', 'NZ', 'IN', 'PH', 'EG', 'SA', 'KR', 'MX', 'CO', 'PK', 'BD', 'IE'];
  var REGION_CALENDARS = { JP: ['gregory', 'japanese'], TH: ['buddhist', 'gregory'], TW: ['gregory', 'roc', 'chinese'], CN: ['gregory', 'chinese'], SA: ['islamic-umalqura', 'gregory', 'islamic', 'islamic-rgsa'],
    IR: ['persian', 'gregory', 'islamic', 'islamic-civil', 'islamic-tbla'], IL: ['gregory', 'hebrew', 'islamic', 'islamic-civil', 'islamic-tbla'], IN: ['gregory', 'indian'],
    ET: ['gregory', 'ethiopic', 'ethioaa'], EG: ['gregory', 'coptic', 'islamic', 'islamic-civil', 'islamic-tbla'], KR: ['gregory', 'dangi'], AF: ['persian', 'gregory', 'islamic', 'islamic-civil', 'islamic-tbla'] };
  var LANG_COLLATIONS = { zh: ['pinyin', 'stroke', 'zhuyin', 'emoji', 'eor'], de: ['phonebk', 'emoji', 'eor'], sv: ['trad', 'emoji', 'eor'], es: ['trad', 'emoji', 'eor'], ja: ['unihan', 'emoji', 'eor'] };
  var REGION_ZONES = { US: ['America/Adak', 'America/Anchorage', 'America/Boise', 'America/Chicago', 'America/Denver', 'America/Detroit', 'America/Indiana/Knox', 'America/Indiana/Marengo',
    'America/Juneau', 'America/Kentucky/Louisville', 'America/Los_Angeles', 'America/Menominee', 'America/New_York', 'America/Phoenix', 'Pacific/Honolulu'],
    GB: ['Europe/London'], DE: ['Europe/Berlin', 'Europe/Busingen'], FR: ['Europe/Paris'], JP: ['Asia/Tokyo'], CN: ['Asia/Shanghai', 'Asia/Urumqi'], IN: ['Asia/Kolkata'],
    AU: ['Antarctica/Macquarie', 'Australia/Adelaide', 'Australia/Brisbane', 'Australia/Darwin', 'Australia/Hobart', 'Australia/Lord_Howe', 'Australia/Melbourne', 'Australia/Perth', 'Australia/Sydney'],
    BR: ['America/Sao_Paulo', 'America/Manaus', 'America/Bahia'], CA: ['America/Toronto', 'America/Vancouver', 'America/Edmonton', 'America/Halifax', 'America/Winnipeg', 'America/St_Johns'],
    RU: ['Europe/Moscow', 'Asia/Yekaterinburg', 'Asia/Vladivostok'], KR: ['Asia/Seoul'], EG: ['Africa/Cairo'], IL: ['Asia/Jerusalem'], SA: ['Asia/Riyadh'], NL: ['Europe/Amsterdam'],
    ES: ['Africa/Ceuta', 'Atlantic/Canary', 'Europe/Madrid'], IT: ['Europe/Rome'], SE: ['Europe/Stockholm'], MX: ['America/Mexico_City', 'America/Cancun', 'America/Tijuana'] };
  var RTL_SCRIPTS = ['Arab', 'Hebr', 'Thaa', 'Syrc', 'Nkoo', 'Adlm', 'Rohg', 'Mand', 'Samr', 'Phnx'];
  var RTL_LANGS = ['ar', 'he', 'fa', 'ur', 'yi', 'ps', 'sd', 'ug', 'dv', 'ckb'];
  function localeRegion(p) {
    var u = uExtension(p, false), i;
    if (u !== null) {
      for (i = 0; i < u.keywords.length; i++) if (u.keywords[i].key === 'rg' && u.keywords[i].value.length >= 2) return upper(sliceS(u.keywords[i].value, 0, 2));
      for (i = 0; i < u.keywords.length; i++) if (u.keywords[i].key === 'sd' && u.keywords[i].value.length >= 2) return upper(sliceS(u.keywords[i].value, 0, 2));
    }
    if (p.region) return upper(p.region);
    var m = maximizeParts(p);
    return m.region ? upper(m.region) : undefined;
  }
  function withFirst(first, rest) {
    var out = [];
    if (first !== undefined) push(out, first);
    for (var i = 0; i < rest.length; i++) if (rest[i] !== first) push(out, rest[i]);
    return out;
  }
  var localeInfo = {
    getCalendars() {
      var p = localeParts(this), region = localeRegion(p), list = region !== undefined && has(REGION_CALENDARS, region) ? REGION_CALENDARS[region] : ['gregory'];
      var ca = getKeyword(p, 'ca');
      return withFirst(ca === undefined ? undefined : (canonicalCalendarIdIntl2(ca)), list);
    },
    getCollations() {
      var p = localeParts(this), list = has(LANG_COLLATIONS, p.language) ? LANG_COLLATIONS[p.language] : ['emoji', 'eor'], co = getKeyword(p, 'co');
      var res = withFirst(co === undefined || co === 'standard' || co === 'search' ? undefined : co, list);
      return res;
    },
    getHourCycles() {
      var p = localeParts(this), region = localeRegion(p), hc = getKeyword(p, 'hc');
      var base = region !== undefined && includes(H12_REGIONS, region) ? ['h12'] : ['h23'];
      return withFirst(hc, base);
    },
    getNumberingSystems() {
      var p = localeParts(this), nu = getKeyword(p, 'nu'), def = (p.language === 'ar' && (!p.region || p.region === 'EG' || p.region === 'SA')) ? 'arab' : p.language === 'fa' ? 'arabext' : 'latn';
      return withFirst(nu, [def]);
    },
    getTextInfo() {
      var p = localeParts(this), m = maximizeParts(p), script = p.script || m.script;
      var rtl = (script && includes(RTL_SCRIPTS, script)) || (!p.script && includes(RTL_LANGS, p.language));
      return { direction: rtl ? 'rtl' : 'ltr' };
    },
    getTimeZones() {
      var p = localeParts(this);
      if (!p.region) return undefined;
      var region = upper(p.region), list = has(REGION_ZONES, region) ? REGION_ZONES[region] : [];
      var out = [];
      for (var i = 0; i < list.length; i++) push(out, list[i]);
      return sortStrings(out);
    },
    getWeekInfo() {
      var p = localeParts(this), region = localeRegion(p), d = region !== undefined && has(WEEK_DATA, region) ? WEEK_DATA[region] : [1, [6, 7], 1];
      var fw = getKeyword(p, 'fw'), first = d[0];
      if (fw !== undefined) { var idx = FW_NAMES.indexOf(fw); if (idx >= 0) first = idx === 0 ? 7 : idx; }
      var weekend = [];
      for (var i = 0; i < d[1].length; i++) push(weekend, d[1][i]);
      return { firstDay: first, weekend: weekend, minimalDays: d[2] };
    }
  };
  function canonicalCalendarIdIntl2(id) { return id === 'islamicc' ? 'islamic-civil' : id === 'ethiopic-amete-alem' ? 'ethioaa' : id; }
  (function () {
    var names = Obj.getOwnPropertyNames(localeInfo);
    for (var i = 0; i < names.length; i++) define(Locale.prototype, names[i], defineLen(localeInfo[names[i]], 0));
    defineProperty(Locale.prototype, 'firstDayOfWeek', { get: nameGetter(function () { return getKeyword(localeParts(this), 'fw'); }, 'firstDayOfWeek'), enumerable: false, configurable: true });
    defineProperty(Locale.prototype, 'variants', { get: nameGetter(function () { var v = localeParts(this).variants; return v.length ? join(v, '-') : undefined; }, 'variants'), enumerable: false, configurable: true });
  })();
