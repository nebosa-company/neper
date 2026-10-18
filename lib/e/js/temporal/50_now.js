  // ---------------------------------------------------------------- Temporal.Now
  var dateNow = Date.now;
  var Now = {};
  function nowNs() { return Big(apply(dateNow, Date, [])) * NS.ms; }
  var nowMethods = {
    instant() { return wrapInstant(nowNs()); },
    timeZoneId() { return 'UTC'; },
    plainDateTimeISO(timeZone) {
      var tz = timeZone === undefined ? UTC_ZONE : toTimeZone(timeZone);
      return wrapDateTime(wallToDateTime(nowNs() + Big(tz.offset)));
    },
    plainDateISO(timeZone) {
      var tz = timeZone === undefined ? UTC_ZONE : toTimeZone(timeZone);
      return wrapDate(wallToDateTime(nowNs() + Big(tz.offset)).date);
    },
    plainTimeISO(timeZone) {
      var tz = timeZone === undefined ? UTC_ZONE : toTimeZone(timeZone);
      return wrapTime(wallToDateTime(nowNs() + Big(tz.offset)).time);
    },
    zonedDateTimeISO(timeZone) {
      var tz = timeZone === undefined ? UTC_ZONE : toTimeZone(timeZone);
      return wrapZoned(nowNs(), tz);
    }
  };
  var nowNames = ownNames(nowMethods);
  for (var ni = 0; ni < nowNames.length; ni++) define(Now, nowNames[ni], nowMethods[nowNames[ni]]);
  tag(Now, 'Temporal.Now');
