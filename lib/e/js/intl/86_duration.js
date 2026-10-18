
  // ---------------------------------------------------------------- Intl.DurationFormat
  var DurationSlots = slotted('DurationFormat');
  var DF_UNITS = ['years', 'months', 'weeks', 'days', 'hours', 'minutes', 'seconds', 'milliseconds', 'microseconds', 'nanoseconds'];
  var DF_STYLES = { years: ['long', 'short', 'narrow'], months: ['long', 'short', 'narrow'], weeks: ['long', 'short', 'narrow'], days: ['long', 'short', 'narrow'],
    hours: ['long', 'short', 'narrow', 'numeric', '2-digit'], minutes: ['long', 'short', 'narrow', 'numeric', '2-digit'], seconds: ['long', 'short', 'narrow', 'numeric', '2-digit'],
    milliseconds: ['long', 'short', 'narrow', 'numeric'], microseconds: ['long', 'short', 'narrow', 'numeric'], nanoseconds: ['long', 'short', 'narrow', 'numeric'] };
  var DF_DIGITAL = { years: 'short', months: 'short', weeks: 'short', days: 'short', hours: 'numeric', minutes: '2-digit', seconds: '2-digit', milliseconds: 'numeric',
    microseconds: 'numeric', nanoseconds: 'numeric' };
  var temporalDuration = global.Temporal !== undefined ? global.Temporal.Duration : undefined;
  var durationFrom = temporalDuration !== undefined ? temporalDuration.from : undefined;
  var durationGetters = create(null);
  if (temporalDuration !== undefined) for (var dg = 0; dg < DF_UNITS.length; dg++) durationGetters[DF_UNITS[dg]] = Object.getOwnPropertyDescriptor(temporalDuration.prototype, DF_UNITS[dg]).get;
  function DurationFormat() {
    if (new.target === undefined) throw new TypeErr("Constructor Intl.DurationFormat requires 'new'");
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var o = create(getPrototypeFromNewTarget(new.target, DurationFormat.prototype));
    var requested = canonicalizeLocaleList(locales);
    options = getOptionsObject(options);
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var numberingSystem = getOption(options, 'numberingSystem', 'string', undefined, undefined);
    if (numberingSystem !== undefined && !test(RE_NUMSYS, numberingSystem)) throw new RangeErr('Invalid numberingSystem');
    var opt = create(null);
    if (numberingSystem !== undefined) opt.nu = lower(numberingSystem);
    var r = resolveLocale(AVAILABLE, requested, opt, ['nu'], { nu: NUMBERING_SYSTEMS });
    var style = getOption(options, 'style', 'string', ['long', 'short', 'narrow', 'digital'], 'short');
    var st = nullObject({ locale: r.locale, numberingSystem: r.nu, style: style });
    var prevStyle = '';
    for (var i = 0; i < DF_UNITS.length; i++) {
      var unit = DF_UNITS[i], uStyle = getOption(options, unit, 'string', DF_STYLES[unit], undefined), displayDefault = 'always';
      var sub = unit === 'milliseconds' || unit === 'microseconds' || unit === 'nanoseconds';
      if (uStyle === undefined) {
        if (style === 'digital') {
          if (unit !== 'hours' && unit !== 'minutes' && unit !== 'seconds') displayDefault = 'auto';
          uStyle = DF_DIGITAL[unit];
        } else if (prevStyle === 'fractional' || prevStyle === 'numeric' || prevStyle === '2-digit') {
          if (unit !== 'minutes' && unit !== 'seconds') displayDefault = 'auto';
          uStyle = 'numeric';
        } else {
          displayDefault = 'auto';
          uStyle = style;
        }
      }
      if (uStyle === 'numeric' && sub) uStyle = 'fractional';
      var display = getOption(options, unit + 'Display', 'string', ['auto', 'always'], displayDefault);
      if (display === 'always' && uStyle === 'fractional' && false) throw new RangeErr('conflict');
      if (prevStyle === 'fractional' || prevStyle === 'numeric' || prevStyle === '2-digit') {
        if (uStyle !== 'fractional' && uStyle !== 'numeric' && uStyle !== '2-digit') throw new RangeErr(unit + ' style conflicts with the previous numeric unit');
        if (unit === 'minutes' || unit === 'seconds') uStyle = uStyle === 'numeric' ? '2-digit' : uStyle;
      }
      defineProperty(st, unit, { value: uStyle, writable: true, enumerable: true, configurable: true });
      defineProperty(st, unit + 'Display', { value: display, writable: true, enumerable: true, configurable: true });
      prevStyle = uStyle;
    }
    var fd = getNumberOption(options, 'fractionalDigits', 0, 9, undefined);
    defineProperty(st, 'fractionalDigits', { value: fd, writable: true, enumerable: true, configurable: true });
    DurationSlots.set(o, st);
    return o;
  }
  function toDurationRecord(input) {
    if (!isObject(input) && typeof input !== 'string') throw new TypeErr('Duration must be an object or a string');
    var d = apply(durationFrom, temporalDuration, [input]), rec = create(null);
    for (var i = 0; i < DF_UNITS.length; i++) rec[DF_UNITS[i]] = apply(durationGetters[DF_UNITS[i]], d, []);
    return rec;
  }
  function durationToFractional(duration, exponent) {
    var seconds = duration.seconds, ms = duration.milliseconds, us = duration.microseconds, ns = duration.nanoseconds;
    if (exponent === 9 && ms === 0 && us === 0 && ns === 0) return seconds;
    if (exponent === 6 && us === 0 && ns === 0) return ms;
    if (exponent === 3 && ns === 0) return us;
    var total = BigInt(ns);
    if (exponent === 9) total += BigInt(seconds) * 1000000000n;
    if (exponent >= 6) total += BigInt(ms) * 1000000n;
    if (exponent >= 3) total += BigInt(us) * 1000n;
    var e = BigInt(mathPow(10, exponent)), q = total / e, rem = total % e;
    if (rem < 0n) rem = -rem;
    var rs = '' + rem;
    while (rs.length < exponent) rs = '0' + rs;
    return '' + q + '.' + rs;
  }
  function durationParts(st, duration) {
    var result = [], needSeparator = false, displayNegativeSign = true;
    for (var i = 0; i < DF_UNITS.length; i++) {
      var unit = DF_UNITS[i], value = duration[unit], style = st[unit], display = st[unit + 'Display'], single = sliceS(unit, 0, unit.length - 1);
      var nfOpts = create(null), done = false;
      if (unit === 'seconds' || unit === 'milliseconds' || unit === 'microseconds') {
        var nextStyle = st[DF_UNITS[i + 1]];
        if (nextStyle === 'fractional') {
          value = durationToFractional(duration, unit === 'seconds' ? 9 : unit === 'milliseconds' ? 6 : 3);
          nfOpts.maximumFractionDigits = st.fractionalDigits === undefined ? 9 : st.fractionalDigits;
          nfOpts.minimumFractionDigits = st.fractionalDigits === undefined ? 0 : st.fractionalDigits;
          nfOpts.roundingMode = 'trunc';
          done = true;
        }
      }
      var displayRequired = false;
      if (unit === 'minutes' && needSeparator) {
        displayRequired = st.secondsDisplay === 'always' || duration.seconds !== 0 || duration.milliseconds !== 0 || duration.microseconds !== 0 || duration.nanoseconds !== 0;
      }
      if (value !== 0 || display !== 'auto' || displayRequired) {
        if (displayNegativeSign) {
          displayNegativeSign = false;
          if (value === 0) {
            var neg = false;
            for (var k = 0; k < DF_UNITS.length; k++) if (duration[DF_UNITS[k]] < 0) neg = true;
            if (neg) value = -0;
          }
        } else nfOpts.signDisplay = 'never';
        nfOpts.numberingSystem = st.numberingSystem;
        var numeric = style === 'numeric' || style === '2-digit' || style === 'fractional';
        if (style === '2-digit') nfOpts.minimumIntegerDigits = 2;
        if (!numeric) { nfOpts.style = 'unit'; nfOpts.unit = single; nfOpts.unitDisplay = style; } else nfOpts.useGrouping = false;
        var nf = new NumberFormat(st.locale, nfOpts), list;
        if (!needSeparator) list = [];
        else { list = result[result.length - 1]; push(list, { type: 'literal', value: ':' }); }
        var parts = nf.formatToParts(value);
        for (var p = 0; p < parts.length; p++) push(list, { type: parts[p].type, value: parts[p].value, unit: single });
        if (!needSeparator) {
          if (style === '2-digit' || numeric) needSeparator = true;
          push(result, list);
        }
      }
      if (done) break;
    }
    var listStyle = st.style === 'digital' ? 'short' : st.style;
    var lf = new ListFormat(st.locale, { type: 'unit', style: listStyle }), strings = [];
    for (var a = 0; a < result.length; a++) {
      var str = '';
      for (var b = 0; b < result[a].length; b++) str += result[a][b].value;
      push(strings, str);
    }
    var flat = [], lp = lf.formatToParts(strings), ri = 0;
    for (var c = 0; c < lp.length; c++) {
      if (lp[c].type === 'element') { for (var e = 0; e < result[ri].length; e++) push(flat, result[ri][e]); ri++; }
      else push(flat, { type: lp[c].type, value: lp[c].value });
    }
    return flat;
  }
  var durationMethods = {
    format(duration) {
      var st = DurationSlots.get(this), parts = durationParts(st, toDurationRecord(duration)), s = '';
      for (var i = 0; i < parts.length; i++) s += parts[i].value;
      return s;
    },
    formatToParts(duration) {
      var st = DurationSlots.get(this), parts = durationParts(st, toDurationRecord(duration)), out = [];
      for (var i = 0; i < parts.length; i++) {
        var p = { type: parts[i].type, value: parts[i].value };
        if (parts[i].unit !== undefined) p.unit = parts[i].unit;
        push(out, p);
      }
      return out;
    },
    resolvedOptions() {
      var st = DurationSlots.get(this), r = { locale: st.locale, numberingSystem: st.numberingSystem, style: st.style };
      for (var i = 0; i < DF_UNITS.length; i++) {
        var u = DF_UNITS[i];
        defineProperty(r, u, { value: st[u] === 'fractional' ? 'numeric' : st[u], writable: true, enumerable: true, configurable: true });
        defineProperty(r, u + 'Display', { value: st[u + 'Display'], writable: true, enumerable: true, configurable: true });
      }
      if (st.fractionalDigits !== undefined) r.fractionalDigits = st.fractionalDigits;
      return r;
    }
  };
  installProto(DurationFormat, durationMethods, 'Intl.DurationFormat');
  makeSupportedLocalesOf(DurationFormat, function () { return AVAILABLE; });
  define(Intl, 'DurationFormat', DurationFormat);
