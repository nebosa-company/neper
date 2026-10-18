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
  define(global, 'Temporal', Temporal);
})(globalThis);
