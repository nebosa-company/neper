
  // ---------------------------------------------------------------- Intl.Locale
  var RE_TYPE = /^[a-z0-9]{3,8}(?:-[a-z0-9]{3,8})*$/i;
  function cloneParts(t) {
    var exts = [];
    for (var i = 0; i < t.extensions.length; i++) {
      var x = t.extensions[i];
      if (x.singleton === 'u') {
        var kws = [];
        for (var k = 0; k < x.keywords.length; k++) push(kws, { key: x.keywords[k].key, value: x.keywords[k].value });
        push(exts, { singleton: 'u', attributes: apply(arrSlice, x.attributes, [0]), keywords: kws });
      } else push(exts, x);
    }
    return { language: t.language, script: t.script, region: t.region, variants: apply(arrSlice, t.variants, [0]), extensions: exts, privateUse: t.privateUse };
  }
  function uExtension(t, make) {
    for (var i = 0; i < t.extensions.length; i++) if (t.extensions[i].singleton === 'u') return t.extensions[i];
    if (!make) return null;
    var x = { singleton: 'u', attributes: [], keywords: [] };
    push(t.extensions, x);
    return x;
  }
  function getKeyword(t, key) {
    var x = uExtension(t, false);
    if (x === null) return undefined;
    for (var i = 0; i < x.keywords.length; i++) if (x.keywords[i].key === key) return x.keywords[i].value;
    return undefined;
  }
  function setKeyword(t, key, value) {
    var x = uExtension(t, true);
    for (var i = 0; i < x.keywords.length; i++) if (x.keywords[i].key === key) { x.keywords[i].value = value; return; }
    push(x.keywords, { key: key, value: value });
  }
  function normalizedTypeValue(key, v) {
    v = lower(v);
    if (has(UNICODE_TYPE_ALIAS, key) && has(UNICODE_TYPE_ALIAS[key], v)) return UNICODE_TYPE_ALIAS[key][v];
    return v;
  }
  var FW_NAMES2 = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  function Locale(tagArg) {
    if (new.target === undefined) throw new TypeErr("Constructor Intl.Locale requires 'new'");
    var options = arguments.length > 1 ? arguments[1] : undefined;
    if (typeof tagArg !== 'string' && !isObject(tagArg)) throw new TypeErr('First argument to Intl.Locale constructor cannot be empty or missing');
    var proto = getPrototypeFromNewTarget(new.target, Locale.prototype, 'Locale');
    var tagStr = LocaleSlots.has(tagArg) ? LocaleSlots.get(tagArg).tag : toStr(tagArg);
    options = coerceOptionsToObject(options);
    var t = parseTag(tagStr);
    if (t === null) throw new RangeErr('Incorrect locale information provided');
    t = cloneParts(parseTag(tagToString(t, true)));
    var language = getOption(options, 'language', 'string', undefined, undefined);
    if (language !== undefined && (!test(RE_LANG, language) || language.length === 4)) throw new RangeErr('Incorrect locale information provided');
    var script = getOption(options, 'script', 'string', undefined, undefined);
    if (script !== undefined && !test(RE_SCRIPT, script)) throw new RangeErr('Incorrect locale information provided');
    var region = getOption(options, 'region', 'string', undefined, undefined);
    if (region !== undefined && !test(RE_REGION, region)) throw new RangeErr('Incorrect locale information provided');
    var variants = getOption(options, 'variants', 'string', undefined, undefined), variantList;
    if (variants !== undefined) {
      variantList = split(variants, '-');
      for (var vi = 0; vi < variantList.length; vi++) {
        if (!test(RE_VARIANT, variantList[vi])) throw new RangeErr('Incorrect locale information provided');
        variantList[vi] = lower(variantList[vi]);
        for (var vj = 0; vj < vi; vj++) if (variantList[vj] === variantList[vi]) throw new RangeErr('Incorrect locale information provided');
      }
    }
    var calendar = getOption(options, 'calendar', 'string', undefined, undefined);
    if (calendar !== undefined && !test(RE_TYPE, calendar)) throw new RangeErr('Incorrect locale information provided');
    var collation = getOption(options, 'collation', 'string', undefined, undefined);
    if (collation !== undefined && !test(RE_TYPE, collation)) throw new RangeErr('Incorrect locale information provided');
    var fw = getOption(options, 'firstDayOfWeek', 'string', undefined, undefined);
    if (fw !== undefined) {
      if (test(/^[0-7]$/, fw)) fw = FW_NAMES2[+fw];
      else if (!test(RE_TYPE, fw)) throw new RangeErr('Incorrect locale information provided');
      else fw = lower(fw);
    }
    var hc = getOption(options, 'hourCycle', 'string', ['h11', 'h12', 'h23', 'h24'], undefined);
    var kf = getOption(options, 'caseFirst', 'string', ['upper', 'lower', 'false'], undefined);
    var kn = options.numeric;
    if (kn !== undefined) kn = toStr(!!kn);
    var nu = getOption(options, 'numberingSystem', 'string', undefined, undefined);
    if (nu !== undefined && !test(RE_TYPE, nu)) throw new RangeErr('Incorrect locale information provided');
    if (language !== undefined) t.language = lower(language);
    if (script !== undefined) t.script = titleScript(script);
    if (region !== undefined) t.region = upper(region);
    if (variants !== undefined) t.variants = variantList;
    if (fw !== undefined) setKeyword(t, 'fw', fw);
    if (calendar !== undefined) setKeyword(t, 'ca', normalizedTypeValue('ca', calendar));
    if (collation !== undefined) setKeyword(t, 'co', lower(collation));
    if (hc !== undefined) setKeyword(t, 'hc', hc);
    if (kf !== undefined) setKeyword(t, 'kf', kf);
    if (kn !== undefined) setKeyword(t, 'kn', kn === 'true' ? '' : 'false');
    if (nu !== undefined) setKeyword(t, 'nu', lower(nu));
    var o = create(proto);
    var canon = tagToString(t, true);
    LocaleSlots.set(o, { tag: canon, parts: parseTag(canon) });
    return o;
  }
  function localeParts(o) { return LocaleSlots.get(o).parts; }
  function localeFromParts(p) {
    var o = create(Locale.prototype), canon = tagToString(p, true);
    LocaleSlots.set(o, { tag: canon, parts: parseTag(canon) });
    return o;
  }
  // The language an undetermined tag most likely means, from its script and/or region.
  function guessLanguage(script, region) {
    var best, k;
    if (script === 'Cyrl' && region === 'RO') return 'bg';
    if (script !== '') for (k in LIKELY) if (k !== 'und' && LIKELY[k][0] === script && (region === '' || LIKELY[k][1] === region)) return k;
    if (region !== '') for (k in LIKELY) if (k !== 'und' && LIKELY[k][1] === region) return k;
    if ((script === '' || script === 'Latn') && has(REGION_LANG, region)) return REGION_LANG[region];
    return script === '' && region === '' ? 'en' : undefined;
  }
  function maximizeParts(p) {
    var r = cloneParts(p), lang = r.language, script = r.script, region = r.region;
    if (script !== '' && region !== '' && lang !== 'und') return r;
    var full = null;
    if (lang === 'und') {
      var guess = guessLanguage(script, region);
      if (guess !== undefined) { r.language = guess; lang = guess; }
    }
    if (region !== '' && has(LIKELY_FULL, lang + '-' + region)) full = LIKELY_FULL[lang + '-' + region];
    else if (script !== '' && has(LIKELY_FULL, lang + '-' + script)) full = LIKELY_FULL[lang + '-' + script];
    else if (has(LIKELY, lang)) full = [lang, LIKELY[lang][0], LIKELY[lang][1]];
    if (full === null) return r;
    if (lang === 'und') r.language = full[0];
    if (script === '') r.script = full[1];
    if (region === '') r.region = full[2];
    return r;
  }
  function minimizeParts(p) {
    var max = maximizeParts(p);
    var tries = [['', ''], ['', max.region], [max.script, '']];
    for (var i = 0; i < tries.length; i++) {
      var cand = cloneParts(max);
      cand.script = tries[i][0];
      cand.region = tries[i][1];
      var mc = maximizeParts(cand);
      if (mc.language === max.language && mc.script === max.script && mc.region === max.region) return cand;
    }
    return max;
  }
  var localeMethods = {
    maximize() { return localeFromParts(maximizeParts(localeParts(this))); },
    minimize() { return localeFromParts(minimizeParts(localeParts(this))); },
    toString() { return LocaleSlots.get(this).tag; },
    get baseName() { var p = localeParts(this); return tagToString({ language: p.language, script: p.script, region: p.region, variants: p.variants, extensions: [], privateUse: '' }, false); },
    get calendar() { return getKeyword(localeParts(this), 'ca'); },
    get caseFirst() { return getKeyword(localeParts(this), 'kf'); },
    get collation() { return getKeyword(localeParts(this), 'co'); },
    get hourCycle() { return getKeyword(localeParts(this), 'hc'); },
    get language() { return localeParts(this).language; },
    get numberingSystem() { return getKeyword(localeParts(this), 'nu'); },
    get numeric() { var v = getKeyword(localeParts(this), 'kn'); return v === '' || v === 'true'; },
    get region() { var r = localeParts(this).region; return r === '' ? undefined : r; },
    get script() { var s = localeParts(this).script; return s === '' ? undefined : s; }
  };
  (function () {
    var names = Object.getOwnPropertyNames(localeMethods);
    for (var i = 0; i < names.length; i++) {
      var d = Object.getOwnPropertyDescriptor(localeMethods, names[i]);
      d.enumerable = false;
      defineProperty(Locale.prototype, names[i], d);
    }
  })();
  defineProperty(Locale.prototype, 'constructor', { value: Locale, writable: true, enumerable: false, configurable: true });
  tag(Locale.prototype, 'Intl.Locale');
  lock(Locale);
  define(Intl, 'Locale', Locale);
