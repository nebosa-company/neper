  // ---------------------------------------------------------------- namespace
  var Temporal = {};
  define(Temporal, 'Duration', Duration);
  define(Temporal, 'Instant', Instant);
  define(Temporal, 'Now', Now);
  define(Temporal, 'PlainDate', PlainDate);
  define(Temporal, 'PlainDateTime', PlainDateTime);
  define(Temporal, 'PlainMonthDay', PlainMonthDay);
  define(Temporal, 'PlainTime', PlainTime);
  define(Temporal, 'PlainYearMonth', PlainYearMonth);
  define(Temporal, 'ZonedDateTime', ZonedDateTime);
  tag(Temporal, 'Temporal');
  var dateGetTime = Date.prototype.getTime;
  define(Date.prototype, 'toTemporalInstant', defineLen({
    toTemporalInstant() {
      var t = apply(dateGetTime, this, []);
      if (t !== t) throw new RangeErr('invalid Date');
      return wrapInstant(Big(t) * NS.ms);
    }
  }.toTemporalInstant, 0));
  // Intl.DateTimeFormat reads Temporal objects through this (captured and removed by the Intl script).
  define(global, '__temporalFormat', function (v) {
    if (!isObject(v)) return undefined;
    var r;
    if (pdSlots.has(v)) { r = pdSlots.get(v); return { type: 'PlainDate', cal: calOf(r), y: r.year, mo: r.month, d: r.day }; }
    if (pdtSlots.has(v)) { r = pdtSlots.get(v); return { type: 'PlainDateTime', cal: calOf(r.date), y: r.date.year, mo: r.date.month, d: r.date.day, h: r.time.hour, mi: r.time.minute, s: r.time.second, ms: r.time.millisecond }; }
    if (timeSlots.has(v)) { r = timeSlots.get(v); return { type: 'PlainTime', cal: 'iso8601', h: r.hour, mi: r.minute, s: r.second, ms: r.millisecond }; }
    if (pymSlots.has(v)) { r = pymSlots.get(v); return { type: 'PlainYearMonth', cal: calOf(r), y: r.year, mo: r.month, d: r.day }; }
    if (pmdSlots.has(v)) { r = pmdSlots.get(v); return { type: 'PlainMonthDay', cal: calOf(r), y: r.year, mo: r.month, d: r.day }; }
    if (instantSlots.has(v)) return { type: 'Instant', cal: 'iso8601', epochMs: Num(floorDiv(instantSlots.get(v), NS.ms)) };
    if (zdtSlots.has(v)) { r = zdtSlots.get(v); return { type: 'ZonedDateTime', cal: r.cal === undefined ? 'iso8601' : r.cal, epochMs: Num(floorDiv(r.ns, NS.ms)), tzId: r.tz.id, tzOffsetMinutes: r.tz.named ? null : r.tz.offset / 60000000000 }; }
    return undefined;
  });
  define(global, 'Temporal', Temporal);
})(globalThis);
