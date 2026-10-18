
  // ---------------------------------------------------------------- Intl.RelativeTimeFormat
  var RelativeSlots = slotted('RelativeTimeFormat');
  var RTF_UNITS = { second: 'second', seconds: 'second', minute: 'minute', minutes: 'minute', hour: 'hour', hours: 'hour', day: 'day', days: 'day', week: 'week', weeks: 'week',
    month: 'month', months: 'month', quarter: 'quarter', quarters: 'quarter', year: 'year', years: 'year' };
  var RTF_NAMES = {
    long: { second: ['second', 'seconds'], minute: ['minute', 'minutes'], hour: ['hour', 'hours'], day: ['day', 'days'], week: ['week', 'weeks'], month: ['month', 'months'],
      quarter: ['quarter', 'quarters'], year: ['year', 'years'] },
    short: { second: ['sec.', 'sec.'], minute: ['min.', 'min.'], hour: ['hr.', 'hr.'], day: ['day', 'days'], week: ['wk.', 'wk.'], month: ['mo.', 'mo.'],
      quarter: ['qtr.', 'qtrs.'], year: ['yr.', 'yr.'] }
  };
  RTF_NAMES.narrow = RTF_NAMES.short;
  var RTF_AUTO = {
    year: { '-1': 'last year', '0': 'this year', '1': 'next year' }, quarter: { '-1': 'last quarter', '0': 'this quarter', '1': 'next quarter' },
    month: { '-1': 'last month', '0': 'this month', '1': 'next month' }, week: { '-1': 'last week', '0': 'this week', '1': 'next week' },
    day: { '-1': 'yesterday', '0': 'today', '1': 'tomorrow' }, hour: { '0': 'this hour' }, minute: { '0': 'this minute' }, second: { '0': 'now' }
  };
  var RTF_AUTO_SHORT = {
    year: { '-1': 'last yr.', '0': 'this yr.', '1': 'next yr.' }, quarter: { '-1': 'last qtr.', '0': 'this qtr.', '1': 'next qtr.' },
    month: { '-1': 'last mo.', '0': 'this mo.', '1': 'next mo.' }, week: { '-1': 'last wk.', '0': 'this wk.', '1': 'next wk.' },
    day: RTF_AUTO.day, hour: RTF_AUTO.hour, minute: RTF_AUTO.minute, second: RTF_AUTO.second
  };
  function RelativeTimeFormat() {
    if (new.target === undefined) throw new TypeErr("Constructor Intl.RelativeTimeFormat requires 'new'");
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var o = create(getPrototypeFromNewTarget(new.target, RelativeTimeFormat.prototype, 'RelativeTimeFormat'));
    var requested = canonicalizeLocaleList(locales);
    options = coerceOptionsToObject(options);
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var numberingSystem = getOption(options, 'numberingSystem', 'string', undefined, undefined);
    if (numberingSystem !== undefined && !test(RE_NUMSYS, numberingSystem)) throw new RangeErr('Invalid numberingSystem');
    var opt = create(null);
    if (numberingSystem !== undefined) opt.nu = lower(numberingSystem);
    var r = resolveLocale(AVAILABLE, requested, opt, ['nu'], { nu: NUMBERING_SYSTEMS });
    var style = getOption(options, 'style', 'string', ['long', 'short', 'narrow'], 'long');
    var numeric = getOption(options, 'numeric', 'string', ['always', 'auto'], 'always');
    var nf = new NumberFormat(r.locale);
    RelativeSlots.set(o, nullObject({ locale: r.locale, numberingSystem: r.nu, style: style, numeric: numeric, nf: nf }));
    return o;
  }
  function relativeParts(rtf, value, unit) {
    value = +value;
    if (typeof arguments[1] === 'symbol') throw new TypeErr('Cannot convert a Symbol to a number');
    if (value !== value || value === Infinity || value === -Infinity) throw new RangeErr('Value need to be finite number for Intl.RelativeTimeFormat.prototype.format()');
    unit = toStr(unit);
    if (!has(RTF_UNITS, unit)) throw new RangeErr('Invalid unit argument for format() \'' + unit + '\'');
    var u = RTF_UNITS[unit];
    if (rtf.numeric === 'auto') {
      var table = rtf.style === 'long' ? RTF_AUTO : RTF_AUTO_SHORT, key = value === 0 ? '0' : '' + value;
      if (has(table[u], key)) return [{ type: 'literal', value: table[u][key] }];
    }
    var past = value < 0 || (value === 0 && 1 / value < 0), abs = past ? -value : value;
    var numParts = rtf.nf.formatToParts(abs), names = RTF_NAMES[rtf.style][u], one = abs === 1;
    var word = one ? names[0] : names[1], out = [];
    if (!past) push(out, { type: 'literal', value: 'in ' });
    for (var i = 0; i < numParts.length; i++) push(out, { type: numParts[i].type, value: numParts[i].value, unit: u });
    push(out, { type: 'literal', value: ' ' + word + (past ? ' ago' : '') });
    return out;
  }
  var relativeMethods = {
    format(value, unit) { return partsString(relativeParts(RelativeSlots.get(this), value, unit)); },
    formatToParts(value, unit) {
      var parts = relativeParts(RelativeSlots.get(this), value, unit), out = [];
      for (var i = 0; i < parts.length; i++) {
        var p = { type: parts[i].type, value: parts[i].value };
        if (parts[i].unit !== undefined) p.unit = parts[i].unit;
        push(out, p);
      }
      return out;
    },
    resolvedOptions() {
      var s = RelativeSlots.get(this);
      return { locale: s.locale, style: s.style, numeric: s.numeric, numberingSystem: s.numberingSystem };
    }
  };
  installProto(RelativeTimeFormat, relativeMethods, 'Intl.RelativeTimeFormat');
  makeSupportedLocalesOf(RelativeTimeFormat, function () { return AVAILABLE; });
  define(Intl, 'RelativeTimeFormat', RelativeTimeFormat);
