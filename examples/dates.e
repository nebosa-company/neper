// Dates are plain structs on the stack. e.time allocates nothing, anywhere.
//
//   type Timestamp = struct { nanos: i64 }   // wall clock, UTC, Unix epoch
//   type Instant   = struct { nanos: i64 }   // monotonic, arbitrary epoch
//   type Duration  = struct { nanos: i64 }
//   type Date      = struct { year: i32, month: u8, day: u8 }
//   type Time      = struct { hour: u8, minute: u8, second: u8, nanos: u32 }

use e.mem
use e.time
use e.io

fn is_expired(issued: time.Timestamp, valid_for: time.Duration) -> (bool, err) {
    let now = try time.now()
    ret (time.timestamp_cmp(now, time.timestamp_add(issued, valid_for)) > 0, ok)
}

// The root arena arrives as a parameter (spec §13) and goes unused here:
// e.time never allocates.
fn main(a: *mem.Arena, args: []str) -> err {
    let now = try time.now()

    // Civil fields: pure integer arithmetic, no tables, no allocation.
    let d = time.to_date(now)
    let t = time.to_time(now)
    try io.printf["{}-{}-{} {}:{}\n"](d.year, d.month, d.day, t.hour, t.minute)

    // A formatted date has a bounded length, so it goes in a stack buffer.
    // No arena is involved at all.
    var buf: [32]u8 = undef
    let s = time.format_iso8601(now, buf[0..])
    try io.print(s)

    // Arithmetic goes through Duration, never raw integers. Every operation over a
    // clock type is spelled <t>_<op>, which is the protocol convention (§9, §16).
    let deadline = time.timestamp_add(now, time.days(30))
    let left = time.timestamp_diff(deadline, now)
    try io.printf["{} days left\n"](time.as_days(left))

    // Elapsed time uses the monotonic clock, never the wall clock —
    // the wall clock can jump backwards.
    let start = try time.monotonic()
    let parsed = try time.parse_iso8601("2026-09-04T12:00:00Z")
    try io.printf["parse took {}ns\n"](time.as_nanos(time.since(start)))
    try io.printf["parsed is {} relative to now\n"](time.timestamp_cmp(parsed, now)) // -1, 0 or 1

    // Time zones are an explicit offset. e.time is UTC-only.
    let local = time.to_date_at(now, 120) // UTC+02:00
    try io.printf["in UTC+02:00 it is {}-{}-{}\n"](local.year, local.month, local.day)

    ret ok
}
