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
  define(global, 'Temporal', Temporal);
})(globalThis);
