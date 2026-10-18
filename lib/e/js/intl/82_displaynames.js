
  // ---------------------------------------------------------------- Intl.DisplayNames (English names)
  var DisplaySlots = slotted('DisplayNames');
  var LANGUAGE_NAMES = { ar: 'Arabic', bg: 'Bulgarian', bn: 'Bangla', ca: 'Catalan', cs: 'Czech', cy: 'Welsh', da: 'Danish', de: 'German', el: 'Greek', en: 'English', es: 'Spanish',
    et: 'Estonian', fa: 'Persian', fi: 'Finnish', fil: 'Filipino', fr: 'French', ga: 'Irish', gl: 'Galician', he: 'Hebrew', hi: 'Hindi', hr: 'Croatian', hu: 'Hungarian',
    hy: 'Armenian', id: 'Indonesian', is: 'Icelandic', it: 'Italian', ja: 'Japanese', ka: 'Georgian', kk: 'Kazakh', km: 'Khmer', ko: 'Korean', lt: 'Lithuanian', lv: 'Latvian',
    mk: 'Macedonian', mn: 'Mongolian', ms: 'Malay', my: 'Burmese', nb: 'Norwegian Bokmål', ne: 'Nepali', nl: 'Dutch', pa: 'Punjabi', pl: 'Polish', pt: 'Portuguese', ro: 'Romanian',
    ru: 'Russian', sk: 'Slovak', sl: 'Slovenian', sq: 'Albanian', sr: 'Serbian', sv: 'Swedish', sw: 'Swahili', ta: 'Tamil', te: 'Telugu', th: 'Thai', tr: 'Turkish',
    uk: 'Ukrainian', ur: 'Urdu', uz: 'Uzbek', vi: 'Vietnamese', zh: 'Chinese' };
  var DIALECT_NAMES = { 'en-US': 'American English', 'en-GB': 'British English', 'en-AU': 'Australian English', 'en-CA': 'Canadian English', 'es-ES': 'European Spanish',
    'es-419': 'Latin American Spanish', 'es-MX': 'Mexican Spanish', 'fr-CA': 'Canadian French', 'fr-CH': 'Swiss French', 'pt-BR': 'Brazilian Portuguese',
    'pt-PT': 'European Portuguese', 'de-AT': 'Austrian German', 'de-CH': 'Swiss High German', 'zh-Hans': 'Simplified Chinese', 'zh-Hant': 'Traditional Chinese' };
  var SCRIPT_NAMES = { Arab: 'Arabic', Armn: 'Armenian', Beng: 'Bangla', Cyrl: 'Cyrillic', Deva: 'Devanagari', Ethi: 'Ethiopic', Geor: 'Georgian', Grek: 'Greek', Gujr: 'Gujarati',
    Guru: 'Gurmukhi', Hans: 'Simplified Han', Hant: 'Traditional Han', Hebr: 'Hebrew', Jpan: 'Japanese', Khmr: 'Khmer', Knda: 'Kannada', Kore: 'Korean', Laoo: 'Lao',
    Latn: 'Latin', Mlym: 'Malayalam', Mymr: 'Myanmar', Sinh: 'Sinhala', Taml: 'Tamil', Telu: 'Telugu', Thai: 'Thai', Hani: 'Han' };
  var REGION_NAMES = { AR: 'Argentina', AT: 'Austria', AU: 'Australia', BE: 'Belgium', BG: 'Bulgaria', BR: 'Brazil', CA: 'Canada', CH: 'Switzerland', CL: 'Chile', CN: 'China',
    CO: 'Colombia', CZ: 'Czechia', DE: 'Germany', DK: 'Denmark', EG: 'Egypt', ES: 'Spain', FI: 'Finland', FR: 'France', GB: 'United Kingdom', GR: 'Greece', HK: 'Hong Kong SAR China',
    HU: 'Hungary', ID: 'Indonesia', IE: 'Ireland', IL: 'Israel', IN: 'India', IR: 'Iran', IT: 'Italy', JP: 'Japan', KR: 'South Korea', MX: 'Mexico', MY: 'Malaysia', NL: 'Netherlands',
    NO: 'Norway', NZ: 'New Zealand', PE: 'Peru', PH: 'Philippines', PK: 'Pakistan', PL: 'Poland', PT: 'Portugal', RO: 'Romania', RS: 'Serbia', RU: 'Russia', SA: 'Saudi Arabia',
    SE: 'Sweden', SG: 'Singapore', TH: 'Thailand', TR: 'Türkiye', TW: 'Taiwan', UA: 'Ukraine', US: 'United States', VN: 'Vietnam', ZA: 'South Africa', '001': 'world',
    '419': 'Latin America', '150': 'Europe' };
  var CURRENCY_DISPLAY = { AED: 'United Arab Emirates Dirham', AFN: 'Afghan Afghani', ALL: 'Albanian Lek', AMD: 'Armenian Dram',
    ANG: 'Netherlands Antillean Guilder', AOA: 'Angolan Kwanza', ARS: 'Argentine Peso', AUD: 'Australian Dollar', AWG: 'Aruban Florin',
    AZN: 'Azerbaijani Manat', BAM: 'Bosnia-Herzegovina Convertible Mark', BBD: 'Barbadian Dollar', BDT: 'Bangladeshi Taka', BGN: 'Bulgarian Lev',
    BHD: 'Bahraini Dinar', BIF: 'Burundian Franc', BMD: 'Bermudan Dollar', BND: 'Brunei Dollar', BOB: 'Bolivian Boliviano', BRL: 'Brazilian Real',
    BSD: 'Bahamian Dollar', BTN: 'Bhutanese Ngultrum', BWP: 'Botswanan Pula', BYN: 'Belarusian Ruble', BZD: 'Belize Dollar', CAD: 'Canadian Dollar',
    CDF: 'Congolese Franc', CHF: 'Swiss Franc', CLP: 'Chilean Peso', CNY: 'Chinese Yuan', COP: 'Colombian Peso', CRC: 'Costa Rican Colón',
    CUP: 'Cuban Peso', CVE: 'Cape Verdean Escudo', CZK: 'Czech Koruna', DJF: 'Djiboutian Franc', DKK: 'Danish Krone', DOP: 'Dominican Peso',
    DZD: 'Algerian Dinar', EGP: 'Egyptian Pound', ERN: 'Eritrean Nakfa', ETB: 'Ethiopian Birr', EUR: 'Euro', FJD: 'Fijian Dollar',
    FKP: 'Falkland Islands Pound', GBP: 'British Pound', GEL: 'Georgian Lari', GHS: 'Ghanaian Cedi', GIP: 'Gibraltar Pound', GMD: 'Gambian Dalasi',
    GNF: 'Guinean Franc', GTQ: 'Guatemalan Quetzal', GYD: 'Guyanaese Dollar', HKD: 'Hong Kong Dollar', HNL: 'Honduran Lempira',
    HTG: 'Haitian Gourde', HUF: 'Hungarian Forint', IDR: 'Indonesian Rupiah', ILS: 'Israeli New Shekel', INR: 'Indian Rupee', IQD: 'Iraqi Dinar',
    IRR: 'Iranian Rial', ISK: 'Icelandic Króna', JMD: 'Jamaican Dollar', JOD: 'Jordanian Dinar', JPY: 'Japanese Yen', KES: 'Kenyan Shilling',
    KGS: 'Kyrgyz Som', KHR: 'Cambodian Riel', KMF: 'Comorian Franc', KPW: 'North Korean Won', KRW: 'South Korean Won', KWD: 'Kuwaiti Dinar',
    KYD: 'Cayman Islands Dollar', KZT: 'Kazakhstani Tenge', LAK: 'Laotian Kip', LBP: 'Lebanese Pound', LKR: 'Sri Lankan Rupee',
    LRD: 'Liberian Dollar', LSL: 'Lesotho Loti', LYD: 'Libyan Dinar', MAD: 'Moroccan Dirham', MDL: 'Moldovan Leu', MGA: 'Malagasy Ariary',
    MKD: 'Macedonian Denar', MMK: 'Myanmar Kyat', MNT: 'Mongolian Tugrik', MOP: 'Macanese Pataca', MRU: 'Mauritanian Ouguiya',
    MUR: 'Mauritian Rupee', MVR: 'Maldivian Rufiyaa', MWK: 'Malawian Kwacha', MXN: 'Mexican Peso', MYR: 'Malaysian Ringgit',
    MZN: 'Mozambican Metical', NAD: 'Namibian Dollar', NGN: 'Nigerian Naira', NIO: 'Nicaraguan Córdoba', NOK: 'Norwegian Krone',
    NPR: 'Nepalese Rupee', NZD: 'New Zealand Dollar', OMR: 'Omani Rial', PAB: 'Panamanian Balboa', PEN: 'Peruvian Sol',
    PGK: 'Papua New Guinean Kina', PHP: 'Philippine Peso', PKR: 'Pakistani Rupee', PLN: 'Polish Zloty', PYG: 'Paraguayan Guarani',
    QAR: 'Qatari Riyal', RON: 'Romanian Leu', RSD: 'Serbian Dinar', RUB: 'Russian Ruble', RWF: 'Rwandan Franc', SAR: 'Saudi Riyal',
    SBD: 'Solomon Islands Dollar', SCR: 'Seychellois Rupee', SDG: 'Sudanese Pound', SEK: 'Swedish Krona', SGD: 'Singapore Dollar',
    SHP: 'St. Helena Pound', SLE: 'Sierra Leonean Leone', SOS: 'Somali Shilling', SRD: 'Surinamese Dollar', SSP: 'South Sudanese Pound',
    STN: 'São Tomé & Príncipe Dobra', SYP: 'Syrian Pound', SZL: 'Swazi Lilangeni', THB: 'Thai Baht', TJS: 'Tajikistani Somoni',
    TMT: 'Turkmenistani Manat', TND: 'Tunisian Dinar', TOP: 'Tongan Paʻanga', TRY: 'Turkish Lira', TTD: 'Trinidad & Tobago Dollar',
    TWD: 'New Taiwan Dollar', TZS: 'Tanzanian Shilling', UAH: 'Ukrainian Hryvnia', UGX: 'Ugandan Shilling', USD: 'US Dollar', UYU: 'Uruguayan Peso',
    UZS: 'Uzbekistani Som', VES: 'Venezuelan Bolívar', VND: 'Vietnamese Dong', VUV: 'Vanuatu Vatu', WST: 'Samoan Tala',
    XAF: 'Central African CFA Franc', XCD: 'East Caribbean Dollar', XOF: 'West African CFA Franc', XPF: 'CFP Franc', YER: 'Yemeni Rial',
    ZAR: 'South African Rand', ZMW: 'Zambian Kwacha', ZWL: 'Zimbabwean Dollar (2009–2024)' };
  var CALENDAR_DISPLAY = { buddhist: 'Buddhist Calendar', chinese: 'Chinese Calendar', coptic: 'Coptic Calendar', dangi: 'Dangi Calendar', ethioaa: 'Ethiopic Amete Alem Calendar',
    ethiopic: 'Ethiopic Calendar', gregory: 'Gregorian Calendar', hebrew: 'Hebrew Calendar', indian: 'Indian National Calendar', 'islamic-civil': 'Hijri Calendar (tabular, civil epoch)',
    'islamic-tbla': 'Hijri Calendar (tabular, astronomical epoch)', 'islamic-umalqura': 'Hijri Calendar (Umm al-Qura)', iso8601: 'ISO-8601 Calendar', japanese: 'Japanese Calendar',
    persian: 'Persian Calendar', roc: 'Minguo Calendar' };
  var FIELD_DISPLAY = { era: 'era', year: 'year', quarter: 'quarter', month: 'month', weekOfYear: 'week', weekday: 'day of the week', day: 'day', dayPeriod: 'AM/PM', hour: 'hour',
    minute: 'minute', second: 'second', timeZoneName: 'time zone' };
  var RE_DN_LANG = /^(?:[a-z]{2,3}|[a-z]{5,8})(?:-[a-z]{4})?(?:-(?:[a-z]{2}|[0-9]{3}))?(?:-(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3}))*$/i;
  function DisplayNames() {
    if (new.target === undefined) throw new TypeErr("Constructor Intl.DisplayNames requires 'new'");
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var o = create(getPrototypeFromNewTarget(new.target, DisplayNames.prototype, 'DisplayNames'));
    var requested = canonicalizeLocaleList(locales);
    options = getOptionsObject(options);
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var r = resolveLocale(AVAILABLE, requested, create(null), [], create(null));
    var style = getOption(options, 'style', 'string', ['narrow', 'short', 'long'], 'long');
    var type = getOption(options, 'type', 'string', ['language', 'region', 'script', 'currency', 'calendar', 'dateTimeField'], undefined);
    if (type === undefined) throw new TypeErr('type is required');
    var fallback = getOption(options, 'fallback', 'string', ['code', 'none'], 'code');
    var languageDisplay = getOption(options, 'languageDisplay', 'string', ['dialect', 'standard'], 'dialect');
    var st = nullObject({ locale: r.locale, style: style, type: type, fallback: fallback });
    if (type === 'language') st.languageDisplay = languageDisplay;
    DisplaySlots.set(o, st);
    return o;
  }
  var RE_SCRIPT_ONLY = /^[a-z]{4}$/i, RE_REGION_ONLY = /^(?:[a-z]{2}|[0-9]{3})$/i, RE_CURRENCY_ONLY = /^[a-z]{3}$/i;
  function displayNameOf(st, code) {
    code = toStr(code);
    var type = st.type, canon, name;
    if (type === 'language') {
      if (!test(RE_DN_LANG, code)) throw new RangeErr('Invalid language code');
      canon = canonicalizeTag(code);
      if (indexOf(canon, '-u-') >= 0 || indexOf(canon, '-x-') >= 0) throw new RangeErr('Invalid language code');
      var p = parseTag(canon), cp = canonicalParts(p);
      var langName = LANGUAGE_NAMES[cp.language];
      if (st.languageDisplay === 'dialect' && cp.region && has(DIALECT_NAMES, cp.language + '-' + cp.region) && !cp.script && !cp.variants.length) name = DIALECT_NAMES[cp.language + '-' + cp.region];
      else if (st.languageDisplay === 'dialect' && cp.script && !cp.region && has(DIALECT_NAMES, cp.language + '-' + cp.script) && !cp.variants.length) name = DIALECT_NAMES[cp.language + '-' + cp.script];
      else if (langName !== undefined) {
        var extras = [];
        if (cp.script) push(extras, has(SCRIPT_NAMES, cp.script) ? SCRIPT_NAMES[cp.script] : cp.script);
        if (cp.region) push(extras, has(REGION_NAMES, cp.region) ? REGION_NAMES[cp.region] : cp.region);
        for (var v = 0; v < cp.variants.length; v++) push(extras, upper(cp.variants[v]));
        name = extras.length ? langName + ' (' + join(extras, ', ') + ')' : langName;
      }
      return name !== undefined ? name : (st.fallback === 'code' ? canon : undefined);
    }
    if (type === 'region') {
      if (!test(RE_REGION_ONLY, code)) throw new RangeErr('Invalid region code');
      canon = upper(code);
      name = REGION_NAMES[canon];
    } else if (type === 'script') {
      if (!test(RE_SCRIPT_ONLY, code)) throw new RangeErr('Invalid script code');
      canon = titleScript(code);
      name = SCRIPT_NAMES[canon];
    } else if (type === 'currency') {
      if (!test(RE_CURRENCY_ONLY, code)) throw new RangeErr('Invalid currency code');
      canon = upper(code);
      name = CURRENCY_DISPLAY[canon];
    } else if (type === 'calendar') {
      if (!test(RE_TYPE, code)) throw new RangeErr('Invalid calendar code');
      canon = lower(code);
      var id = canonicalCalendarIdIntl(canon);
      name = id === undefined ? undefined : CALENDAR_DISPLAY[id];
      if (name === undefined) canon = canon;
    } else {
      if (!has(FIELD_DISPLAY, code)) throw new RangeErr('Invalid dateTimeField');
      canon = code;
      name = FIELD_DISPLAY[code];
    }
    if (name !== undefined) return name;
    return st.fallback === 'code' ? canon : undefined;
  }
  function canonicalCalendarIdIntl(id) {
    if (id === 'islamicc') return 'islamic-civil';
    if (id === 'ethiopic-amete-alem') return 'ethioaa';
    return has(CALENDAR_DISPLAY, id) ? id : undefined;
  }
  var displayMethods = {
    of(code) { return displayNameOf(DisplaySlots.get(this), code); },
    resolvedOptions() {
      var st = DisplaySlots.get(this), r = { locale: st.locale, style: st.style, type: st.type, fallback: st.fallback };
      if (st.type === 'language') r.languageDisplay = st.languageDisplay;
      return r;
    }
  };
  defineLen(DisplayNames, 2);
  installProto(DisplayNames, displayMethods, 'Intl.DisplayNames');
  makeSupportedLocalesOf(DisplayNames, function () { return AVAILABLE; });
  define(Intl, 'DisplayNames', DisplayNames);
