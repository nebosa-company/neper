// The Intl built-ins (ECMA-402), evaluated into the main realm after Temporal (generated into intl.e by scripts/gen_js_prelude.py).
// Locale data is a compact built-in set (English plus the language tags the algorithms need); intrinsics are captured up front.
(function (global) {
  'use strict';
  var apply = Reflect.apply, defineProperty = Object.defineProperty, create = Object.create, getProto = Object.getPrototypeOf;
  var TypeErr = TypeError, RangeErr = RangeError, WM = WeakMap, Num = Number, Str = String, Sym = Symbol, Obj = Object;
  var wmGet = WM.prototype.get, wmSet = WM.prototype.set, wmHas = WM.prototype.has;
  var strSlice = Str.prototype.slice, strToUpper = Str.prototype.toUpperCase, strToLower = Str.prototype.toLowerCase;
  var strIndexOf = Str.prototype.indexOf, strCharCodeAt = Str.prototype.charCodeAt, strSplit = Str.prototype.split;
  var arrPush = Array.prototype.push, arrJoin = Array.prototype.join, arrSort = Array.prototype.sort, arrSlice = Array.prototype.slice;
  var symTag = Sym.toStringTag, symIterator = Sym.iterator;
  var mathFloor = Math.floor, mathMax = Math.max, mathMin = Math.min, mathAbs = Math.abs, mathPow = Math.pow, mathLog10 = Math.log10;
  var reExec = RegExp.prototype.exec;
  var isInteger = Num.isInteger;

  function define(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: false, configurable: true }); }
  function isObject(v) { return (typeof v === 'object' && v !== null) || typeof v === 'function'; }
  function tag(proto, name) { defineProperty(proto, symTag, { value: name, writable: false, enumerable: false, configurable: true }); }
  function defineLen(f, n) { defineProperty(f, 'length', { value: n, writable: false, enumerable: false, configurable: true }); return f; }
  function lock(C) { defineProperty(C, 'prototype', { writable: false, enumerable: false, configurable: false }); }
  function nameGetter(f, name) {
    defineProperty(f, 'name', { value: 'get ' + name, writable: false, enumerable: false, configurable: true });
    return f;
  }
  function sliceS(s, a, b) { return apply(strSlice, s, [a, b]); }
  function upper(s) { return apply(strToUpper, s, []); }
  function lower(s) { return apply(strToLower, s, []); }
  function split(s, sep) { return apply(strSplit, s, [sep]); }
  function join(a, sep) { return apply(arrJoin, a, [sep]); }
  function push(a, v) { defineProperty(a, a.length, { value: v, writable: true, enumerable: true, configurable: true }); }
  function indexOf(s, t) { return apply(strIndexOf, s, [t]); }
  function exec(re, s) { re.lastIndex = 0; return apply(reExec, re, [s]); }
  function toStr(v) { if (typeof v === 'symbol') throw new TypeErr('cannot convert a Symbol to a string'); return Str(v); }
  function includes(a, v) { for (var i = 0; i < a.length; i++) if (a[i] === v) return true; return false; }
  function keysOf(o) { return Obj.keys(o); }
  function has(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
  function sortStrings(a) { apply(arrSort, a, []); return a; }

  // %Intl%.[[FallbackSymbol]]: where the legacy constructor-as-function pattern keeps the real NumberFormat / DateTimeFormat.
  var FallbackSymbol = Symbol('IntlLegacyConstructedSymbol');
  function inProtoChain(o, proto) {
    for (var p = Obj.getPrototypeOf(o); p !== null; p = Obj.getPrototypeOf(p)) if (p === proto) return true;
    return false;
  }
  function slotted(name) {
    var map = new WM();
    return {
      // UnwrapNumberFormat / UnwrapDateTimeFormat: an object inheriting from the constructor's prototype is looked through its fallback symbol.
      unwrap: function (o, proto) {
        if (isObject(o) && !apply(wmHas, map, [o]) && inProtoChain(o, proto)) o = o[FallbackSymbol];
        if (!isObject(o) || !apply(wmHas, map, [o])) throw new TypeErr('not an Intl.' + name);
        return apply(wmGet, map, [o]);
      },
      set: function (o, v) { apply(wmSet, map, [o, v]); },
      get: function (o) {
        if (!isObject(o) || !apply(wmHas, map, [o])) throw new TypeErr('not an Intl.' + name);
        return apply(wmGet, map, [o]);
      },
      has: function (o) { return isObject(o) && apply(wmHas, map, [o]); }
    };
  }

  // ---------------------------------------------------------------- BCP 47
  var RE_LANG = /^(?:[a-z]{2,3}|[a-z]{5,8})$/i, RE_SCRIPT = /^[a-z]{4}$/i, RE_REGION = /^(?:[a-z]{2}|[0-9]{3})$/i;
  var RE_VARIANT = /^(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3})$/i, RE_ALNUM_28 = /^[a-z0-9]{2,8}$/i, RE_ALNUM_38 = /^[a-z0-9]{3,8}$/i;
  var RE_ALNUM_18 = /^[a-z0-9]{1,8}$/i, RE_UKEY = /^[a-z0-9][a-z]$/i, RE_TKEY = /^[a-z][0-9]$/i, RE_SINGLETON = /^[a-z0-9]$/i;
  function test(re, s) { return exec(re, s) !== null; }

  // Parses a structurally valid language tag into parts; null when it is not one.
  function parseTag(input) {
    if (typeof input !== 'string' || input.length === 0) return null;
    for (var c = 0; c < input.length; c++) {
      var code = apply(strCharCodeAt, input, [c]);
      var ok = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code === 45;
      if (!ok) return null;
    }
    var p = split(input, '-'), i = 0, n = p.length;
    for (var j = 0; j < n; j++) if (p[j].length === 0) return null;
    var r = { language: '', script: '', region: '', variants: [], extensions: [], privateUse: '' };
    if (!test(RE_LANG, p[0])) return null;
    r.language = lower(p[0]);
    i = 1;
    if (i < n && test(RE_SCRIPT, p[i])) { r.script = p[i]; i++; }
    if (i < n && test(RE_REGION, p[i])) { r.region = p[i]; i++; }
    while (i < n && test(RE_VARIANT, p[i])) {
      var v = lower(p[i]);
      if (includes(r.variants, v)) return null;
      push(r.variants, v);
      i++;
    }
    var seen = [];
    while (i < n) {
      var s = lower(p[i]);
      if (s === 'x') {
        i++;
        if (i >= n) return null;
        var pu = [];
        while (i < n) { if (!test(RE_ALNUM_18, p[i])) return null; push(pu, lower(p[i])); i++; }
        r.privateUse = join(pu, '-');
        break;
      }
      if (!test(RE_SINGLETON, s)) return null;
      if (includes(seen, s)) return null;
      push(seen, s);
      i++;
      var body = [];
      while (i < n && p[i].length > 1) { push(body, lower(p[i])); i++; }
      if (body.length === 0) return null;
      for (var b = 0; b < body.length; b++) if (!test(RE_ALNUM_28, body[b])) return null;
      if (s === 'u') {
        // attributes (3-8) then keywords (key, then type subtags of 3-8)
        var k = 0, attrs = [], kws = [];
        while (k < body.length && body[k].length >= 3) { push(attrs, body[k]); k++; }
        while (k < body.length) {
          if (!test(RE_UKEY, body[k])) return null;
          var key = body[k], vals = [];
          k++;
          while (k < body.length && body[k].length >= 3) { push(vals, body[k]); k++; }
          for (var q = 0; q < kws.length; q++) if (kws[q].key === key) { key = null; break; }
          if (key === null) { continue; }
          push(kws, { key: key, value: join(vals, '-') });
        }
        push(r.extensions, { singleton: 'u', attributes: attrs, keywords: kws });
      } else if (s === 't') {
        var m = 0, tlang = null;
        if (test(RE_LANG, body[0])) {
          var tp = { language: body[0], script: '', region: '', variants: [] };
          m = 1;
          if (m < body.length && test(RE_SCRIPT, body[m])) { tp.script = body[m]; m++; }
          if (m < body.length && test(RE_REGION, body[m])) { tp.region = body[m]; m++; }
          while (m < body.length && test(RE_VARIANT, body[m])) {
            if (includes(tp.variants, body[m])) return null;
            push(tp.variants, body[m]);
            m++;
          }
          tlang = tp;
        }
        var fields = [];
        while (m < body.length) {
          if (!test(RE_TKEY, body[m])) return null;
          var fk = body[m], fv = [];
          m++;
          while (m < body.length && body[m].length >= 3) { push(fv, body[m]); m++; }
          if (fv.length === 0) return null;
          push(fields, { key: fk, value: join(fv, '-') });
        }
        if (tlang === null && fields.length === 0) return null;
        push(r.extensions, { singleton: 't', tlang: tlang, fields: fields });
      } else {
        for (var o = 0; o < body.length; o++) if (!test(RE_ALNUM_28, body[o])) return null;
        push(r.extensions, { singleton: s, body: join(body, '-') });
      }
    }
    if (r.language === 'root') return null;
    return r;
  }

  // ---------------------------------------------------------------- canonicalization (the alias data this build knows)
  var LANG_ALIAS = {
    iw: 'he', in: 'id', ji: 'yi', jw: 'jv', mo: 'ro', sh: 'sr-Latn', tl: 'fil', no: 'nb', aam: 'aas', adp: 'dz', aue: 'ktz', ayx: 'nun',
    bgm: 'bcg', bjd: 'drl', ccq: 'rki', cjr: 'mom', cka: 'cmr', cmk: 'xch', coy: 'pij', drh: 'khk', drw: 'prs', gav: 'dev', gfx: 'vaj',
    ggn: 'gvr', gti: 'nyc', guv: 'duz', hrr: 'jal', ibi: 'opa', ilw: 'gal', jeg: 'oyb', kgc: 'tdf', kgh: 'kml', koj: 'kwv', krm: 'bmf',
    ktr: 'dtp', kvs: 'gdj', kwq: 'yam', kxe: 'tvd', kzj: 'dtp', kzt: 'dtp', lii: 'raq', lmm: 'rmx', meg: 'cir', mst: 'mry', mwj: 'vaj',
    myt: 'mry', nad: 'xny', ncp: 'kdz', nnx: 'ngv', nts: 'pij', oun: 'vaj', pcr: 'adx', pmc: 'huw', pmu: 'phr', ppa: 'bfy', ppr: 'lcq',
    pry: 'prt', puz: 'pub', sca: 'hle', skk: 'oyb', tdu: 'dtp', thc: 'tpo', thx: 'oyb', tie: 'ras', tkk: 'twm', tlw: 'weo', tmp: 'tyj',
    tne: 'kak', tnf: 'prs', tsf: 'taj', uok: 'ema', xba: 'cax', xia: 'acn', xkh: 'waw', xsj: 'suj', ybd: 'rki', yma: 'lrr',
    cmn: 'zh', zsm: 'ms', swh: 'sw', arb: 'ar', uzn: 'uz', npi: 'ne', pes: 'fa', ekk: 'et', lvs: 'lv', khk: 'mn', gax: 'om', hbs: 'sr-Latn',
    cnr: 'sr-ME'
  };
  // sgn-<region> sign languages with their own language code.
  var SIGN_LANG = { BE: 'sfb', BR: 'bzs', CH: 'sgg', CO: 'csn', DE: 'gsg', DK: 'dsl', ES: 'ssp', FR: 'fsl', GB: 'bfi', GR: 'gss', IE: 'isg', IT: 'ise', JP: 'jsl', MX: 'mfs', NI: 'ncs', NL: 'dse', NO: 'nsl', PT: 'psr', SE: 'swl', US: 'ase', ZA: 'sfs' };
  var REGION_ALIAS = {
    BU: 'MM', DD: 'DE', FX: 'FR', TP: 'TL', YD: 'YE', ZR: 'CD', '554': 'NZ', '840': 'US', '826': 'GB', '276': 'DE', '250': 'FR', '392': 'JP',
    '156': 'CN', '124': 'CA', '036': 'AU', '356': 'IN', '076': 'BR', '643': 'RU', '724': 'ES', '380': 'IT', '410': 'KR', '484': 'MX'
  };
  var VARIANT_ALIAS = { heploc: 'alalc97', polytoni: 'polyton' };
  var COMPLEX_LANG = {
    sh: { language: 'sr', script: 'Latn' }, hbs: { language: 'sr', script: 'Latn' }
  };
  var COMPLEX_REGION = {
    SU: ['RU', 'AM', 'AZ', 'BY', 'EE', 'GE', 'KZ', 'KG', 'LV', 'LT', 'MD', 'TJ', 'TM', 'UA', 'UZ'],
    '810': ['RU', 'AM', 'AZ', 'BY', 'EE', 'GE', 'KZ', 'KG', 'LV', 'LT', 'MD', 'TJ', 'TM', 'UA', 'UZ'],
    CS: ['RS', 'ME'], '891': ['RS', 'ME'], YU: ['RS', 'ME'], AN: ['CW', 'SX', 'BQ'], '530': ['CW', 'SX', 'BQ'], NT: ['SA', 'IQ'], '062': ['034', '143'],
    '172': ['RU', 'AM', 'AZ', 'BY', 'GE', 'KZ', 'KG', 'MD', 'TJ', 'TM', 'UA', 'UZ']
  };
  // Likely subtags (language -> script, region), enough to maximize and minimize the common languages.
  var BOOLEAN_KEYS = ['kb', 'kc', 'kh', 'kk', 'kn'];
  var GRANDFATHERED = { 'art-lojban': 'jbo', 'cel-gaulish': 'xtg', 'zh-guoyu': 'zh', 'zh-hakka': 'hak', 'zh-xiang': 'hsn', 'no-bok': 'nb', 'no-nyn': 'nn' };
  var LANG3 = { aar: 'aa', abk: 'ab', afr: 'af', aka: 'ak', amh: 'am', ara: 'ar', arg: 'an', asm: 'as', ava: 'av', ave: 'ae', aym: 'ay', aze: 'az', bak: 'ba', bam: 'bm', bel: 'be',
    ben: 'bn', bis: 'bi', bod: 'bo', tib: 'bo', bos: 'bs', bre: 'br', bul: 'bg', cat: 'ca', ces: 'cs', cze: 'cs', cha: 'ch', che: 'ce', chu: 'cu', chv: 'cv', cor: 'kw', cos: 'co',
    cre: 'cr', cym: 'cy', wel: 'cy', dan: 'da', deu: 'de', ger: 'de', div: 'dv', dzo: 'dz', ell: 'el', gre: 'el', eng: 'en', epo: 'eo', est: 'et', eus: 'eu', baq: 'eu', ewe: 'ee',
    fao: 'fo', fas: 'fa', per: 'fa', fij: 'fj', fin: 'fi', fra: 'fr', fre: 'fr', fry: 'fy', ful: 'ff', gla: 'gd', gle: 'ga', glg: 'gl', glv: 'gv', grn: 'gn', guj: 'gu', hat: 'ht',
    hau: 'ha', heb: 'he', her: 'hz', hin: 'hi', hmo: 'ho', hrv: 'hr', hun: 'hu', hye: 'hy', arm: 'hy', ibo: 'ig', ido: 'io', iii: 'ii', iku: 'iu', ile: 'ie', ina: 'ia', ind: 'id',
    ipk: 'ik', isl: 'is', ice: 'is', ita: 'it', jav: 'jv', jpn: 'ja', kal: 'kl', kan: 'kn', kas: 'ks', kat: 'ka', geo: 'ka', kau: 'kr', kaz: 'kk', khm: 'km', kik: 'ki', kin: 'rw',
    kir: 'ky', kom: 'kv', kon: 'kg', kor: 'ko', kua: 'kj', kur: 'ku', lao: 'lo', lat: 'la', lav: 'lv', lim: 'li', lin: 'ln', lit: 'lt', ltz: 'lb', lub: 'lu', lug: 'lg', mah: 'mh',
    mal: 'ml', mar: 'mr', mkd: 'mk', mac: 'mk', mlg: 'mg', mlt: 'mt', mon: 'mn', mri: 'mi', mao: 'mi', msa: 'ms', may: 'ms', mya: 'my', bur: 'my', nau: 'na', nav: 'nv', nbl: 'nr',
    nde: 'nd', ndo: 'ng', nep: 'ne', nld: 'nl', dut: 'nl', nno: 'nn', nob: 'nb', nor: 'no', nya: 'ny', oci: 'oc', oji: 'oj', ori: 'or', orm: 'om', oss: 'os', pan: 'pa', pli: 'pi',
    pol: 'pl', por: 'pt', pus: 'ps', que: 'qu', roh: 'rm', ron: 'ro', rum: 'ro', run: 'rn', rus: 'ru', sag: 'sg', san: 'sa', sin: 'si', slk: 'sk', slo: 'sk', slv: 'sl', sme: 'se',
    smo: 'sm', sna: 'sn', snd: 'sd', som: 'so', sot: 'st', spa: 'es', sqi: 'sq', alb: 'sq', srd: 'sc', srp: 'sr', ssw: 'ss', sun: 'su', swa: 'sw', swe: 'sv', tah: 'ty', tam: 'ta',
    tat: 'tt', tel: 'te', tgk: 'tg', tha: 'th', tir: 'ti', ton: 'to', tsn: 'tn', tso: 'ts', tuk: 'tk', tur: 'tr', twi: 'tw', uig: 'ug', ukr: 'uk', urd: 'ur', uzb: 'uz', ven: 've',
    vie: 'vi', vol: 'vo', wln: 'wa', wol: 'wo', xho: 'xh', yid: 'yi', yor: 'yo', zha: 'za', zho: 'zh', chi: 'zh', zul: 'zu' };
  var LIKELY = {
    en: ['Latn', 'US'], es: ['Latn', 'ES'], fr: ['Latn', 'FR'], de: ['Latn', 'DE'], it: ['Latn', 'IT'], pt: ['Latn', 'BR'], nl: ['Latn', 'NL'],
    sv: ['Latn', 'SE'], da: ['Latn', 'DK'], nb: ['Latn', 'NO'], fi: ['Latn', 'FI'], pl: ['Latn', 'PL'], cs: ['Latn', 'CZ'], tr: ['Latn', 'TR'],
    ru: ['Cyrl', 'RU'], uk: ['Cyrl', 'UA'], el: ['Grek', 'GR'], he: ['Hebr', 'IL'], ar: ['Arab', 'EG'], fa: ['Arab', 'IR'], hi: ['Deva', 'IN'],
    bn: ['Beng', 'BD'], th: ['Thai', 'TH'], ja: ['Jpan', 'JP'], ko: ['Kore', 'KR'], zh: ['Hans', 'CN'], vi: ['Latn', 'VN'], id: ['Latn', 'ID'],
    ms: ['Latn', 'MY'], hu: ['Latn', 'HU'], ro: ['Latn', 'RO'], bg: ['Cyrl', 'BG'], sr: ['Cyrl', 'RS'], hr: ['Latn', 'HR'], sk: ['Latn', 'SK'],
    sl: ['Latn', 'SI'], lt: ['Latn', 'LT'], lv: ['Latn', 'LV'], et: ['Latn', 'EE'], ca: ['Latn', 'ES'], eu: ['Latn', 'ES'], gl: ['Latn', 'ES'],
    is: ['Latn', 'IS'], ga: ['Latn', 'IE'], cy: ['Latn', 'GB'], sw: ['Latn', 'TZ'], af: ['Latn', 'ZA'], fil: ['Latn', 'PH'], ur: ['Arab', 'PK'],
    ta: ['Taml', 'IN'], te: ['Telu', 'IN'], mr: ['Deva', 'IN'], gu: ['Gujr', 'IN'], kn: ['Knda', 'IN'], ml: ['Mlym', 'IN'], pa: ['Guru', 'IN'],
    ne: ['Deva', 'NP'], si: ['Sinh', 'LK'], my: ['Mymr', 'MM'], km: ['Khmr', 'KH'], lo: ['Laoo', 'LA'], ka: ['Geor', 'GE'], hy: ['Armn', 'AM'],
    az: ['Latn', 'AZ'], kk: ['Cyrl', 'KZ'], uz: ['Latn', 'UZ'], mn: ['Cyrl', 'MN'], am: ['Ethi', 'ET'], sq: ['Latn', 'AL'], mk: ['Cyrl', 'MK'],
    be: ['Cyrl', 'BY'], yi: ['Hebr', 'UA'], hyw: ['Armn', 'AM'], aae: ['Latn', 'IT'], pap: ['Latn', 'CW'], hsn: ['Hans', 'CN'], gan: ['Hans', 'CN'], wuu: ['Hans', 'CN'], yue: ['Hant', 'HK'], jbo: ['Latn', '001'], hak: ['Hans', 'CN'], aa: ['Latn', 'ET'], und: ['Latn', 'US']
  };
  // Regions whose likely language is not the language that names them as its default region.
  var REGION_LANG = { AT: 'de', CH: 'de', LI: 'de', LU: 'fr', BE: 'nl', AQ: 'en', CA: 'en', AU: 'en', NZ: 'en', IE: 'en', SG: 'en', IN: 'hi', PK: 'ur', CW: 'pap', CY: 'el', MC: 'fr', SM: 'it', VA: 'it' };
  var LIKELY_FULL = {
    'en-Shaw': ['en', 'Shaw', 'GB'], 'und-419': ['es', 'Latn', '419'], 'und-150': ['en', 'Latn', '150'], 'zh-TW': ['zh', 'Hant', 'TW'], 'zh-HK': ['zh', 'Hant', 'HK'], 'zh-MO': ['zh', 'Hant', 'MO'], 'zh-Hant': ['zh', 'Hant', 'TW'],
    'zh-Hans': ['zh', 'Hans', 'CN'], 'sr-Latn': ['sr', 'Latn', 'RS'], 'sr-Cyrl': ['sr', 'Cyrl', 'RS'], 'pa-Arab': ['pa', 'Arab', 'PK'],
    'uz-Cyrl': ['uz', 'Cyrl', 'UZ'], 'uz-Arab': ['uz', 'Arab', 'AF']
  };
  function titleScript(s) { return upper(sliceS(s, 0, 1)) + lower(sliceS(s, 1)); }

  // Canonical string of a parsed tag, applying the alias tables and the canonical ordering of variants and extensions.
  function canonicalParts(t) {
    var language = t.language, script = t.script ? titleScript(t.script) : '', region = t.region ? upper(t.region) : '';
    var variants = [];
    for (var i = 0; i < t.variants.length; i++) push(variants, t.variants[i]);
    if (variants.length && has(GRANDFATHERED, language + '-' + variants[0])) {
      language = GRANDFATHERED[language + '-' + variants[0]];
      var rest = [];
      for (var gv = 1; gv < variants.length; gv++) push(rest, variants[gv]);
      variants = rest;
    }
    if (has(LANG3, language)) language = LANG3[language];
    if (language === 'sgn' && region !== '' && has(SIGN_LANG, region)) { language = SIGN_LANG[region]; region = ''; }
    if (has(LANG_ALIAS, language)) {
      var rep = LANG_ALIAS[language], rp = split(rep, '-');
      language = rp[0];
      if (rp.length > 1 && rp[1].length === 4 && script === '') script = rp[1];
      else if (rp.length > 1 && rp[1].length !== 4 && region === '') region = rp[1];
    }
    if (region !== '' && has(REGION_ALIAS, region)) region = REGION_ALIAS[region];
    else if (region !== '' && has(COMPLEX_REGION, region)) {
      var cands = COMPLEX_REGION[region], pick = cands[0], likelyLang = language;
      if (language === 'und' && script !== '') { var gl = guessLanguage(script, ''); if (gl !== undefined) likelyLang = gl; }
      var lk = LIKELY[likelyLang];
      if (lk && includes(cands, lk[1])) pick = lk[1];
      region = pick;
    }
    for (var v = 0; v < variants.length; v++) if (has(VARIANT_ALIAS, variants[v])) variants[v] = VARIANT_ALIAS[variants[v]];
    var kept = [];
    for (var vk = 0; vk < variants.length; vk++) {
      if (variants[vk] === 'arevmda' && language === 'hy') language = 'hyw';
      if (variants[vk] !== 'arevela' && variants[vk] !== 'arevmda') push(kept, variants[vk]);
    }
    if (includes(kept, 'hepburn') && includes(kept, 'alalc97')) {
      var hk = [];
      for (var hv = 0; hv < kept.length; hv++) if (kept[hv] !== 'hepburn') push(hk, kept[hv]);
      kept = hk;
    }
    variants = kept;
    sortStrings(variants);
    return { language: language, script: script, region: region, variants: variants };
  }
  var SUBDIVISION_ALIAS = { no23: 'no50', cn11: 'cnbj', cz10a: 'cz110', fra: 'frges', frg: 'frges', lud: 'lucl' };
  var UNICODE_TYPE_ALIAS = {
    ca: { islamicc: 'islamic-civil', 'ethiopic-amete-alem': 'ethioaa', gregorian: 'gregory' },
    ks: { primary: 'level1', tertiary: 'level3' },
    kb: {}, kc: {}, kn: {}, kh: {}, kf: {},
    ms: { imperial: 'uksystem' },
    tz: { cnckg: 'cnsha', eire: 'iedub', est: 'papty', gmt0: 'gmt', uct: 'utc', zulu: 'utc' },
    rg: SUBDIVISION_ALIAS, sd: SUBDIVISION_ALIAS, va: {}
  };
  function sortedExtensions(exts) {
    var out = [];
    for (var i = 0; i < exts.length; i++) push(out, exts[i]);
    apply(arrSort, out, [function (a, b) { return a.singleton < b.singleton ? -1 : a.singleton > b.singleton ? 1 : 0; }]);
    return out;
  }
  function keywordsToString(attrs, kws) {
    var parts = [];
    var sa = attrs ? sortStrings(apply(arrSlice, attrs, [0])) : [];
    for (var a = 0; a < sa.length; a++) push(parts, sa[a]);
    var sk = apply(arrSlice, kws, [0]);
    apply(arrSort, sk, [function (x, y) { return x.key < y.key ? -1 : x.key > y.key ? 1 : 0; }]);
    for (var k = 0; k < sk.length; k++) {
      var val = sk[k].value;
      if (has(UNICODE_TYPE_ALIAS, sk[k].key) && has(UNICODE_TYPE_ALIAS[sk[k].key], val)) val = UNICODE_TYPE_ALIAS[sk[k].key][val];
      if (val === 'true' || ((val === 'yes') && BOOLEAN_KEYS.indexOf(sk[k].key) >= 0)) val = '';
      push(parts, sk[k].key);
      if (val !== '') push(parts, val);
    }
    return join(parts, '-');
  }
  function tagToString(t, canonical) {
    var c = canonical ? canonicalParts(t) : t;
    var parts = [c.language];
    if (c.script) push(parts, c.script);
    if (c.region) push(parts, c.region);
    for (var i = 0; i < c.variants.length; i++) push(parts, c.variants[i]);
    var exts = canonical ? sortedExtensions(t.extensions) : t.extensions;
    for (var e = 0; e < exts.length; e++) {
      var x = exts[e];
      if (x.singleton === 'u') {
        var ks = keywordsToString(x.attributes, x.keywords);
        if (ks !== '') { push(parts, 'u'); push(parts, ks); }
      } else if (x.singleton === 't') {
        var tp = [];
        if (x.tlang) {
          var tl = canonicalParts({ language: x.tlang.language, script: x.tlang.script, region: x.tlang.region, variants: x.tlang.variants });
          push(tp, tl.language);
          if (tl.script) push(tp, lower(tl.script));
          if (tl.region) push(tp, lower(tl.region));
          for (var tv = 0; tv < tl.variants.length; tv++) push(tp, tl.variants[tv]);
        }
        var fs = apply(arrSlice, x.fields, [0]);
        apply(arrSort, fs, [function (p, q) { return p.key < q.key ? -1 : p.key > q.key ? 1 : 0; }]);
        for (var f = 0; f < fs.length; f++) { push(tp, fs[f].key); push(tp, fs[f].key === 'm0' && fs[f].value === 'names' ? 'prprname' : fs[f].value); }
        push(parts, 't');
        push(parts, join(tp, '-'));
      } else {
        push(parts, x.singleton);
        push(parts, x.body);
      }
    }
    if (t.privateUse) { push(parts, 'x'); push(parts, t.privateUse); }
    return join(parts, '-');
  }
  function canonicalizeTag(input) {
    var t = parseTag(input);
    if (t === null) throw new RangeErr('Incorrect locale information provided');
    return tagToString(t, true);
  }
  function isStructurallyValid(input) { return parseTag(input) !== null; }

  var LocaleSlots = slotted('Locale');

  // CanonicalizeLocaleList
  function canonicalizeLocaleList(locales) {
    var seen = [];
    if (locales === undefined) return seen;
    var O;
    if (typeof locales === 'string' || LocaleSlots.has(locales)) O = [locales];
    else O = toObject(locales);
    var len = (typeof locales === 'string' || LocaleSlots.has(locales)) ? 1 : toLength(O.length);
    for (var k = 0; k < len; k++) {
      if (!(k in O)) continue;
      var v = O[k];
      if (typeof v !== 'string' && !isObject(v)) throw new TypeErr('Incorrect locale information provided');
      var tagStr = LocaleSlots.has(v) ? LocaleSlots.get(v).tag : toStr(v);
      var c = canonicalizeTag(tagStr);
      if (!includes(seen, c)) push(seen, c);
    }
    return seen;
  }
  function toObject(v) {
    if (v === undefined || v === null) throw new TypeErr('Cannot convert undefined or null to object');
    return Obj(v);
  }
  function toLength(v) {
    var n = +v;
    if (n !== n || n <= 0) return 0;
    return n > 9007199254740991 ? 9007199254740991 : mathFloor(n);
  }

  // ---------------------------------------------------------------- available locales and matching
  var AVAILABLE = ['en', 'en-US', 'en-GB', 'en-AU', 'en-CA', 'en-IN', 'en-001', 'de', 'de-DE', 'de-AT', 'de-CH', 'fr', 'fr-FR', 'fr-CA', 'fr-CH', 'es', 'es-ES', 'es-MX',
    'es-419', 'it', 'it-IT', 'pt', 'pt-BR', 'pt-PT', 'nl', 'nl-NL', 'sv', 'da', 'nb', 'fi', 'pl', 'cs', 'tr', 'ru', 'uk', 'el', 'he', 'ar', 'hi', 'th',
    'ja', 'ko', 'zh', 'zh-Hans', 'zh-Hant', 'zh-CN', 'zh-TW', 'zh-HK', 'vi', 'id', 'ms', 'hu', 'ro', 'bg', 'sr', 'hr', 'sk', 'sl', 'lt', 'lv', 'et',
    'ca', 'sw', 'fil', 'fa', 'ur', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'ne', 'sq', 'af', 'am', 'az', 'be', 'cy', 'eu', 'ga', 'gl', 'hy',
    'is', 'ka', 'kk', 'km', 'lo', 'mk', 'mn', 'my', 'si', 'uz'];
  var DEFAULT_LOCALE = 'en-US';

  function bestAvailableLocale(available, locale) {
    var candidate = locale;
    while (true) {
      if (includes(available, candidate)) return candidate;
      var pos = lastIndexOf(candidate, '-');
      if (pos < 0) return undefined;
      if (pos >= 2 && charAt(candidate, pos - 2) === '-') pos -= 2;
      candidate = sliceS(candidate, 0, pos);
    }
  }
  function lastIndexOf(s, t) { return apply(String.prototype.lastIndexOf, s, [t]); }
  function charAt(s, i) { return apply(String.prototype.charAt, s, [i]); }
  function stripUnicodeExtension(loc) {
    var parts = split(loc, '-'), out = [], skipping = false;
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i];
      if (p.length === 1) skipping = (p === 'u');
      if (!skipping) push(out, p);
    }
    return join(out, '-');
  }
  function lookupSupported(available, requested) {
    var out = [];
    for (var i = 0; i < requested.length; i++) {
      var noExt = stripUnicodeExtension(requested[i]);
      if (bestAvailableLocale(available, noExt) !== undefined) push(out, requested[i]);
    }
    return out;
  }
  function supportedLocales(available, requested, options) {
    if (options !== undefined) {
      options = toObject(options);
      var matcher = options.localeMatcher;
      if (matcher !== undefined) {
        matcher = toStr(matcher);
        if (matcher !== 'lookup' && matcher !== 'best fit') throw new RangeErr('Value ' + matcher + ' out of range for Intl options property localeMatcher');
      }
    }
    return lookupSupported(available, requested);
  }

  // GetOption / GetNumberOption / CoerceOptionsToObject / GetOptionsObject
  function getOption(options, property, type, values, fallback) {
    var value = options[property];
    if (value === undefined) return fallback;
    if (type === 'boolean') value = !!value;
    else {
      value = toStr(value);
      if (values !== undefined && !includes(values, value)) throw new RangeErr('Value ' + value + ' out of range for Intl options property ' + property);
    }
    return value;
  }
  function getNumberOption(options, property, minimum, maximum, fallback) {
    var value = options[property];
    if (value === undefined) return fallback;
    value = +value;
    if (value !== value || value < minimum || value > maximum) throw new RangeErr(property + ' value is out of range.');
    return mathFloor(value);
  }
  function coerceOptionsToObject(options) {
    if (options === undefined) return create(null);
    return toObject(options);
  }
  function getOptionsObject(options) {
    if (options === undefined) return create(null);
    if (isObject(options)) return options;
    throw new TypeErr('Options must be an object');
  }

  // ResolveLocale for the relevant extension keys: `data[key]` lists the supported values of a key (the first is the default).
  function resolveLocale(available, requested, opt, keys, data) {
    var found, foundLocale = DEFAULT_LOCALE, extension = null;
    for (var i = 0; i < requested.length && found === undefined; i++) {
      var noExt = stripUnicodeExtension(requested[i]);
      var m = bestAvailableLocale(available, noExt);
      if (m !== undefined) { found = m; foundLocale = m; if (noExt !== requested[i]) extension = requested[i]; }
    }
    if (found === undefined) foundLocale = DEFAULT_LOCALE;
    var result = create(null);
    result.dataLocale = foundLocale; result.locale = foundLocale;
    var supportedExtension = '';
    var kw = [];
    if (extension !== null) {
      var t = parseTag(extension);
      for (var e = 0; e < t.extensions.length; e++) if (t.extensions[e].singleton === 'u') kw = t.extensions[e].keywords;
    }
    for (var k = 0; k < keys.length; k++) {
      var key = keys[k], supported = data[key] || [], value = supported.length ? supported[0] : null, kwValue;
      var supportedExtensionAddition = '';
      for (var q = 0; q < kw.length; q++) {
        if (kw[q].key === key) {
          kwValue = kw[q].value === '' ? 'true' : kw[q].value;
          if (includes(supported, kwValue)) { value = kwValue; supportedExtensionAddition = '-' + key + (kwValue === 'true' ? '' : '-' + kwValue); }
          else if (kwValue === 'true' && includes(supported, '')) { value = ''; }
        }
      }
      if (has(opt, key)) {
        var optionsValue = opt[key];
        if (optionsValue !== undefined && optionsValue !== null && includes(supported, optionsValue) && optionsValue !== value) {
          value = optionsValue;
          supportedExtensionAddition = '';
        }
      }
      result[key] = value;
      supportedExtension += supportedExtensionAddition;
    }
    if (supportedExtension.length > 0) {
      var base = foundLocale;
      var pos = indexOf(base, '-x-');
      if (pos < 0) base = base + '-u' + supportedExtension;
      else base = sliceS(base, 0, pos) + '-u' + supportedExtension + sliceS(base, pos);
      result.locale = canonicalizeTag(base);
    }
    return result;
  }

  var Intl = {};
  tag(Intl, 'Intl');
  var getCanonicalLocales = {
    getCanonicalLocales(locales) { return canonicalizeLocaleList(locales); }
  }.getCanonicalLocales;
  define(Intl, 'getCanonicalLocales', getCanonicalLocales);

  // Constructor plumbing shared by the service constructors: `supportedLocalesOf` and the prototype checks.
  function makeSupportedLocalesOf(C, available) {
    var f = {
      supportedLocalesOf(locales) {
        var requested = canonicalizeLocaleList(locales);
        return supportedLocales(available(), requested, arguments.length > 1 ? arguments[1] : undefined);
      }
    }.supportedLocalesOf;
    defineLen(f, 1);
    define(C, 'supportedLocalesOf', f);
  }
  function ordinaryCreateFromConstructor(newTarget, fallbackProto) {
    var proto = newTarget.prototype;
    if (!isObject(proto)) proto = fallbackProto;
    return create(proto);
  }
  var realmGlobalOf = global.__fnRealmGlobal;
  // The prototype for an object made through `newTarget`: its `prototype`, else the named class's prototype in newTarget's own realm.
  function getPrototypeFromNewTarget(newTarget, fallback, name) {
    var proto = newTarget.prototype;
    if (isObject(proto)) return proto;
    var g = realmGlobalOf(newTarget);
    if (g === global) return fallback;
    var intl = g.Intl, ctor = intl === undefined ? undefined : intl[name];
    return ctor !== undefined && isObject(ctor.prototype) ? ctor.prototype : fallback;
  }

  var IntlInternals = {
    define: define, isObject: isObject, tag: tag, defineLen: defineLen, lock: lock, sliceS: sliceS, upper: upper, lower: lower, split: split, join: join,
    push: push, indexOf: indexOf, toStr: toStr, includes: includes, slotted: slotted, parseTag: parseTag, tagToString: tagToString,
    canonicalizeTag: canonicalizeTag, canonicalizeLocaleList: canonicalizeLocaleList, canonicalParts: canonicalParts, isStructurallyValid: isStructurallyValid,
    supportedLocales: supportedLocales, lookupSupported: lookupSupported, getOption: getOption, getNumberOption: getNumberOption,
    coerceOptionsToObject: coerceOptionsToObject, getOptionsObject: getOptionsObject, resolveLocale: resolveLocale,
    makeSupportedLocalesOf: makeSupportedLocalesOf, getPrototypeFromNewTarget: getPrototypeFromNewTarget, AVAILABLE: AVAILABLE,
    DEFAULT_LOCALE: DEFAULT_LOCALE, LocaleSlots: LocaleSlots, LIKELY: LIKELY, LIKELY_FULL: LIKELY_FULL, titleScript: titleScript, has: has,
    keywordsToString: keywordsToString, sortedExtensions: sortedExtensions, bestAvailableLocale: bestAvailableLocale, stripUnicodeExtension: stripUnicodeExtension,
    sortStrings: sortStrings, getProto: getProto, ordinaryCreateFromConstructor: ordinaryCreateFromConstructor, toLength: toLength
  };
