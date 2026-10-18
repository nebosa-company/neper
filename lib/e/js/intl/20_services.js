
  // ---------------------------------------------------------------- shared constructor plumbing
  function makeService(name, length, init) {
    // A service constructor: callable (except Locale-like ones, which pass `needsNew`) and brand-checked through a slot map.
    var Slots = slotted(name);
    return { Slots: Slots };
  }
  function ctorLocales(locales) { return canonicalizeLocaleList(locales); }
  function installProto(C, methods, toStringTag) {
    var names = Object.getOwnPropertyNames(methods);
    for (var i = 0; i < names.length; i++) {
      var d = Object.getOwnPropertyDescriptor(methods, names[i]);
      d.enumerable = false;
      defineProperty(C.prototype, names[i], d);
    }
    defineProperty(C.prototype, 'constructor', { value: C, writable: true, enumerable: false, configurable: true });
    tag(C.prototype, toStringTag);
    lock(C);
  }
  function fnNamed(f, name, len) {
    defineProperty(f, 'name', { value: name, writable: false, enumerable: false, configurable: true });
    defineProperty(f, 'length', { value: len, writable: false, enumerable: false, configurable: true });
    return f;
  }

  // ---------------------------------------------------------------- Intl.Collator
  var CollatorSlots = slotted('Collator');
  var RE_COLLATION = /^[a-z0-9]{3,8}(?:-[a-z0-9]{3,8})*$/i;
  function stripMarks(s) {
    var d = apply(String.prototype.normalize, s, ['NFD']), out = '';
    for (var i = 0; i < d.length; i++) {
      var c = apply(strCharCodeAt, d, [i]);
      if (c >= 0x300 && c <= 0x36f) continue;
      out += d[i];
    }
    return out;
  }
  function isPunct(ch) { return exec(/^[\s!-\/:-@\[-`{-~\u00a1-\u00bf\u2000-\u206f]$/, ch) !== null; }
  function collatorCompare(st, x, y) {
    x = apply(String.prototype.normalize, x, ['NFD']);
    y = apply(String.prototype.normalize, y, ['NFD']);
    if (st.ignorePunctuation) {
      var fx = '', fy = '';
      for (var a = 0; a < x.length; a++) if (!isPunct(x[a])) fx += x[a];
      for (var b = 0; b < y.length; b++) if (!isPunct(y[b])) fy += y[b];
      x = fx; y = fy;
    }
    var r = primary(st, stripMarks(x), stripMarks(y));
    if (r !== 0) return r;
    if (st.sensitivity === 'base') return 0;
    if (st.sensitivity !== 'case') {
      var ax = lower(x), ay = lower(y);
      if (ax !== ay) {
        var m = marksOnly(ax), n = marksOnly(ay);
        if (m !== n) return m < n ? -1 : 1;
      }
      if (st.sensitivity === 'accent') return 0;
    }
    // case level: lower before upper unless caseFirst says otherwise
    var sx = stripMarks(x), sy = stripMarks(y);
    for (var i = 0; i < sx.length && i < sy.length; i++) {
      if (sx[i] !== sy[i]) {
        var lx = lower(sx[i]) === sx[i], ly = lower(sy[i]) === sy[i];
        if (lx !== ly) return (lx ? -1 : 1) * (st.caseFirst === 'upper' ? -1 : 1);
      }
    }
    if (st.sensitivity === 'case') return 0;
    return x === y ? 0 : x < y ? -1 : 1;
  }
  function marksOnly(s) {
    var d = apply(String.prototype.normalize, s, ['NFD']), out = '';
    for (var i = 0; i < d.length; i++) {
      var c = apply(strCharCodeAt, d, [i]);
      if (c >= 0x300 && c <= 0x36f) out += d[i]; else out += '.';
    }
    return out;
  }
  // German phone-book order sorts a, o and u with a diaeresis as ae, oe and ue.
  function phonebook(s) {
    var out = '';
    for (var i = 0; i < s.length; i++) {
      var c = s[i];
      out += c === 'ä' ? 'ae' : c === 'ö' ? 'oe' : c === 'ü' ? 'ue' : c;
    }
    return out;
  }
  function primary(st, x, y) {
    x = lower(x); y = lower(y);
    if (st.collation === 'phonebk') { x = phonebook(x); y = phonebook(y); }
    if (st.numeric) {
      var i = 0, j = 0;
      while (i < x.length && j < y.length) {
        var cx = x[i], cy = y[j];
        if (isDigit(cx) && isDigit(cy)) {
          var ei = i, ej = j;
          while (ei < x.length && isDigit(x[ei])) ei++;
          while (ej < y.length && isDigit(y[ej])) ej++;
          var nx = sliceS(x, i, ei), ny = sliceS(y, j, ej);
          while (nx.length > 1 && nx[0] === '0') nx = sliceS(nx, 1);
          while (ny.length > 1 && ny[0] === '0') ny = sliceS(ny, 1);
          if (nx.length !== ny.length) return nx.length < ny.length ? -1 : 1;
          if (nx !== ny) return nx < ny ? -1 : 1;
          i = ei; j = ej;
        } else {
          if (cx !== cy) return cx < cy ? -1 : 1;
          i++; j++;
        }
      }
      return (x.length - i) === (y.length - j) ? 0 : (x.length - i) < (y.length - j) ? -1 : 1;
    }
    return x === y ? 0 : x < y ? -1 : 1;
  }
  function isDigit(c) { return c >= '0' && c <= '9'; }
  function Collator() {
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var nt = new.target === undefined ? Collator : new.target;
    var o = create(getPrototypeFromNewTarget(nt, Collator.prototype));
    var requested = canonicalizeLocaleList(locales);
    options = coerceOptionsToObject(options);
    var usage = getOption(options, 'usage', 'string', ['sort', 'search'], 'sort');
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var collation = getOption(options, 'collation', 'string', undefined, undefined);
    if (collation !== undefined && !test(RE_COLLATION, collation)) throw new RangeErr('Invalid collation');
    var numeric = getOption(options, 'numeric', 'boolean', undefined, undefined);
    var caseFirst = getOption(options, 'caseFirst', 'string', ['upper', 'lower', 'false'], undefined);
    var opt = create(null);
    if (collation !== undefined) opt.co = lower(collation);
    if (numeric !== undefined) opt.kn = '' + numeric;
    if (caseFirst !== undefined) opt.kf = caseFirst;
    var r = resolveLocale(AVAILABLE, requested, opt, ['co', 'kf', 'kn'], { co: collationData(requested.length > 0 ? parseTag(requested[0]).language : 'en'), kf: ['false', 'lower', 'upper'], kn: ['false', 'true'] });
    var sensitivity = getOption(options, 'sensitivity', 'string', ['base', 'accent', 'case', 'variant'], undefined);
    if (sensitivity === undefined) sensitivity = 'variant';
    var ip = getOption(options, 'ignorePunctuation', 'boolean', undefined, false);
    CollatorSlots.set(o, { locale: r.locale, usage: usage, sensitivity: sensitivity, ignorePunctuation: ip, collation: r.co === undefined || r.co === null ? 'default' : r.co,
      numeric: r.kn === 'true', caseFirst: r.kf, boundCompare: undefined });
    return o;
  }
  var collatorMethods = {
    get compare() {
      var st = CollatorSlots.get(this);
      if (st.boundCompare === undefined) {
        var f = (x, y) => collatorCompare(st, toStr(x), toStr(y));
        fnNamed(f, '', 2);
        st.boundCompare = f;
      }
      return st.boundCompare;
    },
    resolvedOptions() {
      var st = CollatorSlots.get(this);
      return { locale: st.locale, usage: st.usage, sensitivity: st.sensitivity, ignorePunctuation: st.ignorePunctuation, collation: st.collation,
        numeric: st.numeric, caseFirst: st.caseFirst };
    }
  };
  installProto(Collator, collatorMethods, 'Intl.Collator');
  makeSupportedLocalesOf(Collator, function () { return AVAILABLE; });
  define(Intl, 'Collator', Collator);

  // ---------------------------------------------------------------- Intl.PluralRules
  var PluralSlots = slotted('PluralRules');
  var PLURAL_ONLY_OTHER = ['ja', 'zh', 'ko', 'vi', 'th', 'id', 'ms', 'my', 'km', 'lo'];
  function languageOf(locale) { return split(locale, '-')[0]; }
  function pluralOperands(str) {
    // str is the plain decimal string of the (rounded) number
    var neg = str[0] === '-';
    if (neg) str = sliceS(str, 1);
    var dot = indexOf(str, '.'), intPart = dot < 0 ? str : sliceS(str, 0, dot), frac = dot < 0 ? '' : sliceS(str, dot + 1);
    return { i: intPart, f: frac, v: frac.length };
  }
  function pluralCategory(lang, type, ops) {
    var i = +ops.i, iLast = i % 10, iLast2 = i % 100;
    if (includes(PLURAL_ONLY_OTHER, lang)) return 'other';
    if (type === 'ordinal') {
      if (lang === 'en') {
        if (iLast === 1 && iLast2 !== 11) return 'one';
        if (iLast === 2 && iLast2 !== 12) return 'two';
        if (iLast === 3 && iLast2 !== 13) return 'few';
      }
      return 'other';
    }
    if (lang === 'fr' || lang === 'pt' || lang === 'es' || lang === 'it') {
      if (ops.v === 0 && i !== 0 && i % 1000000 === 0) return 'many';
      if (lang === 'es' || lang === 'it') return (i === 1 && ops.v === 0) ? 'one' : 'other';
      return (i === 0 || i === 1) ? 'one' : 'other';
    }
    if (lang === 'ru' || lang === 'uk') {
      if (ops.v !== 0) return 'other';
      if (iLast === 1 && iLast2 !== 11) return 'one';
      if (iLast >= 2 && iLast <= 4 && !(iLast2 >= 12 && iLast2 <= 14)) return 'few';
      return 'many';
    }
    if (lang === 'pl') {
      if (ops.v !== 0) return 'other';
      if (i === 1) return 'one';
      if (iLast >= 2 && iLast <= 4 && !(iLast2 >= 12 && iLast2 <= 14)) return 'few';
      return 'many';
    }
    if (lang === 'ar') {
      if (ops.v !== 0) return 'other';
      if (i === 0) return 'zero';
      if (i === 1) return 'one';
      if (i === 2) return 'two';
      if (iLast2 >= 3 && iLast2 <= 10) return 'few';
      if (iLast2 >= 11 && iLast2 <= 99) return 'many';
      return 'other';
    }
    return (i === 1 && ops.v === 0) ? 'one' : 'other';
  }
  function pluralCategories(lang, type) {
    if (includes(PLURAL_ONLY_OTHER, lang)) return ['other'];
    if (type === 'ordinal') return lang === 'en' ? ['one', 'two', 'few', 'other'] : ['other'];
    if (lang === 'ru' || lang === 'uk' || lang === 'pl') return ['one', 'few', 'many', 'other'];
    if (lang === 'ar') return ['zero', 'one', 'two', 'few', 'many', 'other'];
    if (lang === 'fr' || lang === 'pt' || lang === 'es' || lang === 'it') return ['one', 'many', 'other'];
    return ['one', 'other'];
  }
