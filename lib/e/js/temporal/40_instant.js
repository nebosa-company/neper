  // ---------------------------------------------------------------- Instant
  var instantSlots = slotted('Instant');
  var InstantProto;
  function wrapInstant(ns, proto) { return wrapWith(instantSlots, proto === undefined ? InstantProto : proto, ns); }
  function toBigInt(v) {
    var p = toPrimitive(v, 'number');
    switch (typeof p) {
      case 'bigint': return p;
      case 'boolean': return p ? 1n : 0n;
      case 'string': return Big(p);
    }
    throw new TypeErr('cannot convert value to a BigInt');
  }
  function checkInstant(ns) { if (!instantValid(ns)) throw new RangeErr('epoch nanoseconds out of range'); return ns; }
  function offsetNsFromRec(rec) { return rec.offsetNs === undefined ? 0 : rec.offsetNs; }
  function parseInstantString(s) {
    var rec = parseISOString(s, 'instant');
    if (!rec.hasDate || !rec.hasTime || (!rec.z && rec.offsetNs === undefined)) throw new RangeErr('invalid instant string');
    var date = mkDate(rec.year, rec.month, rec.day), time = mkTime(rec.hour, rec.minute, rec.second, rec.millisecond, rec.microsecond, rec.nanosecond);
    return checkInstant(epochNsOf(date, time) - Big(rec.z ? 0 : rec.offsetNs));
  }
  function toTemporalInstant(item) {
    if (isObject(item)) {
      if (instantSlots.has(item)) return instantSlots.get(item);
      if (zdtSlots.has(item)) return zdtSlots.get(item).ns;
    }
    var p = toPrimitive(item, 'string');
    if (typeof p !== 'string') throw new TypeErr('cannot convert to a Temporal.Instant');
    return parseInstantString(p);
  }
  function instantString(ns, tz, precision) {
    var wall = ns + Big(tz === undefined ? 0 : tz.offset);
    var dt = wallToDateTime(wall);
    var s = dateString(dt.date) + 'T' + timeString(dt.time, precision);
    if (tz === undefined) return s + 'Z';
    return s + formatOffsetNs(tz.offset, false);
  }
  function maxInstantIncrement(unit) { return Num(NS_PER_DAY / UNIT_NS[unit]); }
  function differenceInstant(sinceOp, ns, other, options) {
    var o = toTemporalInstant(other);
    options = getOptionsObject(options);
    var st = getDifferenceSettings(sinceOp, options, 'time', [], 'nanosecond', 'second');
    var norm = roundNumberToIncrement(o - ns, UNIT_NS[st.smallest] * Big(st.increment), st.mode);
    var parts = balanceTime(norm, st.largest);
    var rec = fixZeros(createDurationRecord(0, 0, 0, 0, parts.hours, parts.minutes, parts.seconds, parts.milliseconds, parts.microseconds, parts.nanoseconds));
    return wrapDuration(sinceOp ? negateDuration(rec) : rec);
  }
  function addDurationToInstant(sign, ns, other) {
    var d = toTemporalDurationRecord(other);
    if (d.years || d.months || d.weeks || d.days) throw new RangeErr('years, months, weeks and days are not allowed for an Instant');
    var norm = timeDurationNs(d);
    return wrapInstant(checkInstant(sign < 0 ? ns - norm : ns + norm));
  }

  function Instant() {
    needNew(new.target, 'Instant');
    var ns = toBigInt(arguments[0]);
    return wrapInstant(checkInstant(ns), protoFromNewTarget(new.target, InstantProto));
  }
  defineLen(Instant, 1);
  InstantProto = Instant.prototype;
  installClass(Instant, 'Temporal.Instant', {
    from(item) { return wrapInstant(toTemporalInstant(item)); },
    fromEpochMilliseconds(epochMilliseconds) {
      var n = +epochMilliseconds;
      if (!isInteger(n)) throw new RangeErr('epochMilliseconds must be an integer');
      return wrapInstant(checkInstant(Big(n) * NS.ms));
    },
    fromEpochNanoseconds(epochNanoseconds) {
      return wrapInstant(checkInstant(toBigInt(epochNanoseconds)));
    },
    compare(one, two) {
      var a = toTemporalInstant(one), b = toTemporalInstant(two);
      return a < b ? -1 : a > b ? 1 : 0;
    }
  }, {
    get epochMilliseconds() { return Num(floorDiv(instantSlots.get(this), NS.ms)); },
    get epochNanoseconds() { return instantSlots.get(this); }
  }, {
    add(temporalDurationLike) { return addDurationToInstant(1, instantSlots.get(this), temporalDurationLike); },
    subtract(temporalDurationLike) { return addDurationToInstant(-1, instantSlots.get(this), temporalDurationLike); },
    until(other, options) { return differenceInstant(false, instantSlots.get(this), other, options); },
    since(other, options) { return differenceInstant(true, instantSlots.get(this), other, options); },
    round(roundTo) {
      var ns = instantSlots.get(this);
      if (roundTo === undefined) throw new TypeErr('round requires an argument');
      var increment = 1, mode = 'halfExpand', smallest;
      if (typeof roundTo === 'string') {
        var o = create(null);
        o.smallestUnit = roundTo;
        smallest = getUnitOption(o, 'smallestUnit', 'time', undefined);
      } else {
        roundTo = getOptionsObject(roundTo);
        increment = getRoundingIncrementOption(roundTo);
        mode = getRoundingModeOption(roundTo, 'halfExpand');
        smallest = getUnitOption(roundTo, 'smallestUnit', 'time', undefined);
      }
      if (smallest === undefined) throw new RangeErr('smallestUnit is required');
      validateRoundingIncrement(increment, maxInstantIncrement(smallest), true);
      return wrapInstant(checkInstant(roundAsIfPositive(ns, UNIT_NS[smallest] * Big(increment), mode)));
    },
    equals(other) { return instantSlots.get(this) === toTemporalInstant(other); },
    toString(options) {
      var ns = instantSlots.get(this);
      options = getOptionsObject(options);
      var tzLike;
      var p = getSecondsPrecision(options, true, undefined, function () { tzLike = options.timeZone; });
      var tz = tzLike === undefined ? undefined : toTimeZone(tzLike);
      var r = roundAsIfPositive(ns, UNIT_NS[p.unit] * Big(p.inc), p.mode);
      checkInstant(r);
      return instantString(r, tz, p.precision);
    },
    toJSON() { return instantString(instantSlots.get(this), undefined, 'auto'); },
    toLocaleString() { return instantString(instantSlots.get(this), undefined, 'auto'); },
    valueOf() { throw new TypeErr('Temporal.Instant cannot be converted to a primitive; use compare()'); },
    toZonedDateTimeISO(timeZone) {
      var ns = instantSlots.get(this);
      return wrapZoned(ns, toTimeZone(timeZone));
    }
  });
  defineLen(InstantProto.toString, 0);
  defineLen(InstantProto.toJSON, 0);
  defineLen(InstantProto.toLocaleString, 0);
