
  // ---------------------------------------------------------------- Intl.supportedValuesOf
  var SUPPORTED_CALENDARS = ['buddhist', 'chinese', 'coptic', 'dangi', 'ethioaa', 'ethiopic', 'gregory', 'hebrew', 'indian', 'islamic-civil',
    'islamic-tbla', 'islamic-umalqura', 'iso8601', 'japanese', 'persian', 'roc'];
  var SUPPORTED_CURRENCIES = ['AED', 'AFN', 'ALL', 'AMD', 'ANG', 'AOA', 'ARS', 'AUD', 'AWG', 'AZN', 'BAM', 'BBD', 'BDT', 'BGN', 'BHD', 'BIF', 'BMD', 'BND', 'BOB', 'BRL',
    'BSD', 'BTN', 'BWP', 'BYN', 'BZD', 'CAD', 'CDF', 'CHF', 'CLP', 'CNY', 'COP', 'CRC', 'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP', 'ERN', 'ETB', 'EUR', 'FJD',
    'FKP', 'GBP', 'GEL', 'GHS', 'GIP', 'GMD', 'GNF', 'GTQ', 'GYD', 'HKD', 'HNL', 'HTG', 'HUF', 'IDR', 'ILS', 'INR', 'IQD', 'IRR', 'ISK', 'JMD', 'JOD', 'JPY', 'KES', 'KGS',
    'KHR', 'KMF', 'KPW', 'KRW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP', 'LKR', 'LRD', 'LSL', 'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT', 'MOP', 'MRU', 'MUR', 'MVR', 'MWK',
    'MXN', 'MYR', 'MZN', 'NAD', 'NGN', 'NIO', 'NOK', 'NPR', 'NZD', 'OMR', 'PAB', 'PEN', 'PGK', 'PHP', 'PKR', 'PLN', 'PYG', 'QAR', 'RON', 'RSD', 'RUB', 'RWF', 'SAR', 'SBD',
    'SCR', 'SDG', 'SEK', 'SGD', 'SHP', 'SLE', 'SOS', 'SRD', 'SSP', 'STN', 'SYP', 'SZL', 'THB', 'TJS', 'TMT', 'TND', 'TOP', 'TRY', 'TTD', 'TWD', 'TZS', 'UAH', 'UGX', 'USD',
    'UYU', 'UZS', 'VES', 'VND', 'VUV', 'WST', 'XAF', 'XCD', 'XOF', 'XPF', 'YER', 'ZAR', 'ZMW', 'ZWL'];
  // Structurally valid IANA zone names (the shapes the time zone database theory file allows).
  var RE_ZONE_NAME = /^(?:(?:[A-Za-z_]|\.(?!\.?(?:\/|$)))[A-Za-z.\-_]{0,13}(?:\/(?:[A-Za-z_]|\.(?!\.?(?:\/|$)))[A-Za-z.\-_]{0,13})*|(?:Etc\/)?GMT[+-]\d{1,2}|SystemV\/[A-Z]{3}\d{1,2}(?:[A-Z]{3})?|CST6CDT|EST5EDT|MST7MDT|PST8PDT|NZ)$/;
  var supportedValuesOf = {
    supportedValuesOf(key) {
      key = toStr(key);
      var list;
      if (key === 'calendar') list = SUPPORTED_CALENDARS;
      else if (key === 'collation') list = allCollations();
      else if (key === 'currency') list = SUPPORTED_CURRENCIES;
      else if (key === 'numberingSystem') list = NUMBERING_SYSTEMS;
      else if (key === 'timeZone') {
        var names = tzNames(), out = [];
        for (var i = 0; i < names.length; i++) if (canonicalTimeZone(names[i]).id === names[i] && names[i] !== 'UTC' && names[i] !== 'Etc/GMT' && names[i] !== 'Etc/UTC' && RE_ZONE_NAME.test(names[i])) push(out, names[i]);
        push(out, 'UTC');
        list = out;
      } else if (key === 'unit') list = SANCTIONED_UNITS;
      else throw new RangeErr('Invalid key : ' + key);
      var copy = [];
      for (var j = 0; j < list.length; j++) push(copy, list[j]);
      return sortStrings(copy);
    }
  }.supportedValuesOf;
  define(Intl, 'supportedValuesOf', defineLen(supportedValuesOf, 1));
