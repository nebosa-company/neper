
  // ---------------------------------------------------------------- Intl.ListFormat
  var ListSlots = slotted('ListFormat');
  var LIST_PATTERNS = {
    conjunction: { long: ['{0}, {1}', '{0}, and {1}', '{0} and {1}'], short: ['{0}, {1}', '{0}, & {1}', '{0} & {1}'], narrow: ['{0}, {1}', '{0}, {1}', '{0}, {1}'] },
    disjunction: { long: ['{0}, {1}', '{0}, or {1}', '{0} or {1}'], short: ['{0}, {1}', '{0}, or {1}', '{0} or {1}'], narrow: ['{0}, {1}', '{0}, or {1}', '{0} or {1}'] },
    unit: { long: ['{0}, {1}', '{0}, {1}', '{0}, {1}'], short: ['{0}, {1}', '{0}, {1}', '{0}, {1}'], narrow: ['{0} {1}', '{0} {1}', '{0} {1}'] }
  };
  // Patterns per language: [start and middle, end, pair] for each type and style; languages not listed use English.
  function wordPatterns(and, or) {
    var conj = ['{0}, {1}', '{0} ' + and + ' {1}', '{0} ' + and + ' {1}'], disj = ['{0}, {1}', '{0} ' + or + ' {1}', '{0} ' + or + ' {1}'], plain = ['{0}, {1}', '{0}, {1}', '{0} ' + and + ' {1}'], bare = ['{0} {1}', '{0} {1}', '{0} {1}'];
    return { conjunction: { long: conj, short: conj, narrow: bare }, disjunction: { long: disj, short: disj, narrow: disj }, unit: { long: conj, short: plain, narrow: bare } };
  }
  var LIST_PATTERNS_BY_LANG = { es: wordPatterns('y', 'o'), de: wordPatterns('und', 'oder'), fr: wordPatterns('et', 'ou'), it: wordPatterns('e', 'o'), pt: wordPatterns('e', 'ou'), nl: wordPatterns('en', 'of'),
    sv: wordPatterns('och', 'eller'), da: wordPatterns('og', 'eller'), nb: wordPatterns('og', 'eller'), pl: wordPatterns('i', 'lub'), ru: wordPatterns('и', 'или'), tr: wordPatterns('ve', 'veya') };
  function listPatterns(locale) {
    var lang = split(locale, '-')[0];
    return has(LIST_PATTERNS_BY_LANG, lang) ? LIST_PATTERNS_BY_LANG[lang] : LIST_PATTERNS;
  }
  function ListFormat() {
    if (new.target === undefined) throw new TypeErr("Constructor Intl.ListFormat requires 'new'");
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var o = create(getPrototypeFromNewTarget(new.target, ListFormat.prototype, 'ListFormat'));
    var requested = canonicalizeLocaleList(locales);
    options = getOptionsObject(options);
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var r = resolveLocale(AVAILABLE, requested, {}, [], {});
    var type = getOption(options, 'type', 'string', ['conjunction', 'disjunction', 'unit'], 'conjunction');
    var style = getOption(options, 'style', 'string', ['long', 'short', 'narrow'], 'long');
    ListSlots.set(o, { locale: r.locale, type: type, style: style });
    return o;
  }
  function stringListFromIterable(iterable) {
    var list = [];
    if (iterable === undefined) return list;
    var it = iterable[symIterator]();
    if (it === undefined) throw new TypeErr('not iterable');
    var iterator = getIteratorFrom(iterable), next = iterator.next;
    while (true) {
      var res = apply(next, iterator, []);
      if (!isObject(res)) throw new TypeErr('iterator result is not an object');
      if (res.done) return list;
      var v = res.value;
      if (typeof v !== 'string') {
        var ex = new TypeErr('Iterable yielded ' + typeof v + ' which is not a string');
        var ret = iterator['return'];
        if (ret !== undefined && ret !== null) { try { apply(ret, iterator, []); } catch (e2) { } }
        throw ex;
      }
      push(list, v);
    }
  }
  function getIteratorFrom(iterable) {
    var m = iterable[symIterator];
    if (typeof m !== 'function') throw new TypeErr('not iterable');
    var iterator = apply(m, iterable, []);
    if (!isObject(iterator)) throw new TypeErr('iterator is not an object');
    return iterator;
  }
  function createPartsFromList(st, list) {
    var n = list.length, parts = [];
    if (n === 0) return parts;
    if (n === 1) { push(parts, { type: 'element', value: list[0] }); return parts; }
    var pats = listPatterns(st.locale)[st.type][st.style];
    function expand(pat, a, b) {
      var out = [], i = indexOf(pat, '{0}'), j = indexOf(pat, '{1}');
      var pre = sliceS(pat, 0, i), mid = sliceS(pat, i + 3, j), post = sliceS(pat, j + 3);
      if (pre !== '') push(out, { type: 'literal', value: pre });
      push(out, { type: 'element', value: a });
      if (mid !== '') push(out, { type: 'literal', value: mid });
      push(out, { type: 'element', value: b });
      if (post !== '') push(out, { type: 'literal', value: post });
      return out;
    }
    // build right to left: [last-but-one, last] use the end pattern (or the pair pattern for two), earlier ones the start/middle
    var pat = n === 2 ? pats[2] : pats[1];
    var tail = expand(pat, list[n - 2], list[n - 1]);
    for (var k = n - 3; k >= 0; k--) {
      var head = expand(pats[0], list[k], '\u0000');
      var merged = [];
      for (var h = 0; h < head.length; h++) {
        if (head[h].value === '\u0000') { for (var t = 0; t < tail.length; t++) push(merged, tail[t]); } else push(merged, head[h]);
      }
      tail = merged;
    }
    // merge adjacent literals
    var out = [];
    for (var q = 0; q < tail.length; q++) {
      if (out.length && out[out.length - 1].type === 'literal' && tail[q].type === 'literal') out[out.length - 1].value += tail[q].value;
      else push(out, tail[q]);
    }
    return out;
  }
  var listMethods = {
    format(list) {
      var st = ListSlots.get(this), parts = createPartsFromList(st, stringListFromIterable(list)), s = '';
      for (var i = 0; i < parts.length; i++) s += parts[i].value;
      return s;
    },
    formatToParts(list) {
      var st = ListSlots.get(this), parts = createPartsFromList(st, stringListFromIterable(list)), out = [];
      for (var i = 0; i < parts.length; i++) push(out, { type: parts[i].type, value: parts[i].value });
      return out;
    },
    resolvedOptions() {
      var st = ListSlots.get(this);
      return { locale: st.locale, type: st.type, style: st.style };
    }
  };
  installProto(ListFormat, listMethods, 'Intl.ListFormat');
  makeSupportedLocalesOf(ListFormat, function () { return AVAILABLE; });
  define(Intl, 'ListFormat', ListFormat);
