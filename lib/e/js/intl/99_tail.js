
  // The locale-sensitive methods of the core built-ins go through Intl.
  var numberValueOf = Number.prototype.valueOf, bigintValueOf = BigInt.prototype.valueOf;
  define(Number.prototype, 'toLocaleString', {
    toLocaleString() {
      var x = apply(numberValueOf, this, []);
      return new NumberFormat(arguments.length > 0 ? arguments[0] : undefined, arguments.length > 1 ? arguments[1] : undefined).format(x);
    }
  }.toLocaleString);
  define(BigInt.prototype, 'toLocaleString', {
    toLocaleString() {
      var x = apply(bigintValueOf, this, []);
      return new NumberFormat(arguments.length > 0 ? arguments[0] : undefined, arguments.length > 1 ? arguments[1] : undefined).format(x);
    }
  }.toLocaleString);
  define(String.prototype, 'localeCompare', defineLen({
    localeCompare(that) {
      if (this === undefined || this === null) throw new TypeErr('String.prototype.localeCompare called on null or undefined');
      var s = toStr(this), t = toStr(that);
      return new Collator(arguments.length > 1 ? arguments[1] : undefined, arguments.length > 2 ? arguments[2] : undefined).compare(s, t);
    }
  }.localeCompare, 1));
  // toLocaleLowerCase / toLocaleUpperCase: the language-sensitive mappings of SpecialCasing.txt for Turkish, Azeri and Lithuanian.
  var strFromCharCode = Str.fromCharCode, reSoftDotted = /\p{Soft_Dotted}/u, reTest = RegExp.prototype.test;
  function codePointsOf(s) {
    var out = [];
    for (var i = 0; i < s.length; i++) {
      var c = apply(strCharCodeAt, s, [i]);
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        var d = apply(strCharCodeAt, s, [i + 1]);
        if (d >= 0xDC00 && d <= 0xDFFF) { push(out, 0x10000 + ((c - 0xD800) * 1024) + (d - 0xDC00)); i++; continue; }
      }
      push(out, c);
    }
    return out;
  }
  function cpToString(cp) {
    if (cp < 0x10000) return apply(strFromCharCode, Str, [cp]);
    cp -= 0x10000;
    return apply(strFromCharCode, Str, [0xD800 + (cp >> 10), 0xDC00 + (cp & 1023)]);
  }
  // Whether `target` follows position i with no intervening code point of combining class 0 or 230 (230 stops the search unless it is the target).
  function followedBy(cps, i, target) {
    for (var j = i + 1; j < cps.length; j++) {
      var cc = combiningClass(cps[j]);
      if (cps[j] === target) return true;
      if (cc === 0 || cc === 230) return false;
    }
    return false;
  }
  function moreAbove(cps, i) {
    for (var j = i + 1; j < cps.length; j++) {
      var cc = combiningClass(cps[j]);
      if (cc === 230) return true;
      if (cc === 0) return false;
    }
    return false;
  }
  function afterSoftDotted(cps, i) {
    for (var j = i - 1; j >= 0; j--) {
      var cc = combiningClass(cps[j]);
      if (apply(reTest, reSoftDotted, [cpToString(cps[j])])) return true;
      if (cc === 0 || cc === 230) return false;
    }
    return false;
  }
  function localeLower(s, lang) {
    var cps = codePointsOf(s), out = '';
    for (var i = 0; i < cps.length; i++) {
      var c = cps[i];
      if (lang === 'tr' || lang === 'az') {
        if (c === 0x130) { out += 'i'; continue; }
        if (c === 0x49) {
          if (followedBy(cps, i, 0x307)) { out += 'i'; var k = i + 1; while (cps[k] !== 0x307) { out += cpToString(cps[k]); k++; } i = k; }
          else out += '\u0131';
          continue;
        }
      } else if (lang === 'lt') {
        if ((c === 0x49 || c === 0x4A || c === 0x12E) && moreAbove(cps, i)) { out += lower(cpToString(c)) + '\u0307'; continue; }
        if (c === 0xCC) { out += 'i\u0307\u0300'; continue; }
        if (c === 0xCD) { out += 'i\u0307\u0301'; continue; }
        if (c === 0x128) { out += 'i\u0307\u0303'; continue; }
      }
      out += lower(cpToString(c));
    }
    return out;
  }
  function localeUpper(s, lang) {
    var cps = codePointsOf(s), out = '';
    for (var i = 0; i < cps.length; i++) {
      var c = cps[i];
      if ((lang === 'tr' || lang === 'az') && c === 0x69) { out += '\u0130'; continue; }
      if (lang === 'lt' && c === 0x307 && afterSoftDotted(cps, i)) continue;
      out += upper(cpToString(c));
    }
    return out;
  }
  function localeCaseTarget(self, locales) {
    if (self === undefined || self === null) throw new TypeErr('String.prototype.toLocaleCase called on null or undefined');
    var s = toStr(self), requested = canonicalizeLocaleList(locales);
    return { s: s, lang: requested.length === 0 ? 'en' : split(requested[0], '-')[0] };
  }
  define(String.prototype, 'toLocaleLowerCase', defineLen({
    toLocaleLowerCase() {
      var t = localeCaseTarget(this, arguments.length > 0 ? arguments[0] : undefined);
      return t.lang === 'tr' || t.lang === 'az' || t.lang === 'lt' ? localeLower(t.s, t.lang) : lower(t.s);
    }
  }.toLocaleLowerCase, 0));
  define(String.prototype, 'toLocaleUpperCase', defineLen({
    toLocaleUpperCase() {
      var t = localeCaseTarget(this, arguments.length > 0 ? arguments[0] : undefined);
      return t.lang === 'tr' || t.lang === 'az' || t.lang === 'lt' ? localeUpper(t.s, t.lang) : upper(t.s);
    }
  }.toLocaleUpperCase, 0));
  delete global.__tzNames;
  delete global.__tzOffset;
  delete global.__tzLinks;
  delete global.__fnRealmGlobal;
  delete global.__ccc;
  delete global.__temporalFormat;
  define(global, 'Intl', Intl);
})(globalThis);
