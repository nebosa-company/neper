// Temporal.Now with a named zone, and time-zone offsets across the whole Date range,
// driven through `e.js.realm`. #844: the plain ISO methods must use the zone's offset at
// the captured instant, not the named zone's placeholder 0. #840: an epoch past the i64
// nanosecond window must clamp rather than overflow the offset lookup.
use e.js.interp as js
use e.js.realm as realm
use e.mem
use e.os
use e.str

fn check(it: *js.Interp, source: str, want: str) -> bool {
    let (v, e) = realm.run(it, source)
    if e != ok { ret false }
    let (s, se) = js.to_string(it, v)
    if se != ok { ret false }
    ret str.eq(s, want)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, re) = realm.new_realm(a)
    if re != ok { os.exit(9i32) }
    it.quiet = true
    // 844: the plain methods agree with the zoned value converted to plain, in a named
    // zone that is never UTC.
    if !check(it, "(function () { var tz = 'America/Los_Angeles'; return String(Temporal.Now.plainDateTimeISO(tz)).slice(0, 13) === String(Temporal.Now.zonedDateTimeISO(tz).toPlainDateTime()).slice(0, 13) ? 'same' : 'diff'; })()", "same") { os.exit(1i32) }
    if !check(it, "(function () { var tz = 'America/Los_Angeles'; return String(Temporal.Now.plainDateISO(tz)).slice(0, 10) === String(Temporal.Now.zonedDateTimeISO(tz).toPlainDate()).slice(0, 10) ? 'same' : 'diff'; })()", "same") { os.exit(1i32) }
    if !check(it, "(function () { var tz = 'America/Los_Angeles'; return String(Temporal.Now.plainTimeISO(tz)).slice(0, 5) === String(Temporal.Now.zonedDateTimeISO(tz).toPlainTime()).slice(0, 5) ? 'same' : 'diff'; })()", "same") { os.exit(1i32) }
    // 840: the extreme ends of the Date range resolve an offset without trapping.
    if !check(it, "(function () { var z = Temporal.Instant.fromEpochMilliseconds(8640000000000000).toZonedDateTimeISO('America/Los_Angeles'); return String(z.offset).length >= 6 ? 'six' : String(z.offset); })()", "six") { os.exit(2i32) }
    if !check(it, "(function () { var z = Temporal.Instant.fromEpochMilliseconds(-8640000000000000).toZonedDateTimeISO('America/Los_Angeles'); return String(z.offset).length >= 6 ? 'six' : String(z.offset); })()", "six") { os.exit(2i32) }
    ret ok
}
