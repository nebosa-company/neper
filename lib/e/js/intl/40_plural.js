
  // ---------------------------------------------------------------- Intl.PluralRules
  function PluralRules() {
    if (new.target === undefined) throw new TypeErr("Constructor Intl.PluralRules requires 'new'");
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var o = create(getPrototypeFromNewTarget(new.target, PluralRules.prototype, 'PluralRules'));
    var requested = canonicalizeLocaleList(locales);
    options = coerceOptionsToObject(options);
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var type = getOption(options, 'type', 'string', ['cardinal', 'ordinal'], 'cardinal');
    var notation = getOption(options, 'notation', 'string', ['standard', 'scientific', 'engineering', 'compact'], 'standard');
    var pr = nullObject({ type: type, notation: notation });
    setDigitOptions(pr, options, 0, 3, notation);
    var compactDisplay = getOption(options, 'compactDisplay', 'string', ['short', 'long'], 'short');
    if (notation === 'compact') pr.compactDisplay = compactDisplay;
    var r = resolveLocale(AVAILABLE, requested, {}, [], {});
    pr.locale = r.locale;
    PluralSlots.set(o, pr);
    return o;
  }
  var PluralSlots = slotted('PluralRules');
  function pluralSelect(pr, n) {
    if (n !== n || n === Infinity || n === -Infinity) return 'other';
    var d = decimalFromNumber(n < 0 ? -n : n);
    var res = applyRounding(pr, d), digits = digitsOf(res, pr);
    var ops = { i: digits.int, f: digits.frac, v: digits.frac.length };
    return pluralCategory(languageOf(pr.locale), pr.type, ops);
  }
  var pluralMethods = {
    select(value) {
      var pr = PluralSlots.get(this);
      return pluralSelect(pr, +value);
    },
    selectRange(start, end) {
      var pr = PluralSlots.get(this);
      if (start === undefined || end === undefined) throw new TypeErr('start and end are required');
      var x = +start, y = +end;
      if (x !== x || y !== y) throw new RangeErr('Invalid number range');
      return pluralSelect(pr, y);
    },
    resolvedOptions() {
      var pr = PluralSlots.get(this), t = pr.roundingType;
      var r = { locale: pr.locale, type: pr.type, notation: pr.notation };
      if (pr.notation === 'compact') r.compactDisplay = pr.compactDisplay;
      r.minimumIntegerDigits = pr.minInt;
      if (t === 'fractionDigits' || t === 'morePrecision' || t === 'lessPrecision') { r.minimumFractionDigits = pr.minFrac; r.maximumFractionDigits = pr.maxFrac; }
      if (t === 'significantDigits' || t === 'morePrecision' || t === 'lessPrecision') { r.minimumSignificantDigits = pr.minSig; r.maximumSignificantDigits = pr.maxSig; }
      if (t === 'compact') { r.minimumFractionDigits = 0; r.maximumFractionDigits = 0; r.minimumSignificantDigits = 1; r.maximumSignificantDigits = 2; }
      r.pluralCategories = pluralCategories(languageOf(pr.locale), pr.type);
      r.roundingIncrement = pr.roundingIncrement;
      r.roundingMode = pr.roundingMode;
      r.roundingPriority = t === 'morePrecision' ? 'morePrecision' : t === 'lessPrecision' ? 'lessPrecision' : 'auto';
      r.trailingZeroDisplay = pr.trailingZeroDisplay;
      return r;
    }
  };
  installProto(PluralRules, pluralMethods, 'Intl.PluralRules');
  makeSupportedLocalesOf(PluralRules, function () { return AVAILABLE; });
  define(Intl, 'PluralRules', PluralRules);
