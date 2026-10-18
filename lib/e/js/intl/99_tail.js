
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
  delete global.__tzNames;
  delete global.__tzOffset;
  define(global, 'Intl', Intl);
})(globalThis);
