// Section 8's clocks and durations, over the `os.clock` intrinsic.
//
// PARTIAL. Everything the fence declares is here except the five calendar
// conversions -- `to_date`, `to_time`, `to_date_at`, `to_time_at` and `from_civil` --
// which need civil-date arithmetic and nothing yet calls. `Date` and `Time` are
// declared because they are part of the surface; they have no constructor until those
// five land. `docs/modules.json` keeps `e.time` at `surface: "spec"` for that reason,
// so `check_module_surfaces.py` does not yet hold this file to the whole fence.
//
// Every duration is a signed nanosecond count, so the whole module is i64 arithmetic
// and the only failure is the clock's own.

use e.os

type Timestamp = struct { nanos: i64 }
type Instant = struct { nanos: i64 }
type Duration = struct { nanos: i64 }
type Date = struct { year: i32, month: u8, day: u8 }
type Time = struct { hour: u8, minute: u8, second: u8, nanos: u32 }
type Timer = struct { started: Instant }

error Invalid

fn now() -> (Timestamp, err) {
    let (ticks, clock_error) = os.clock(.Wall)
    if clock_error != ok { ret (Timestamp { nanos: 0i64 }, clock_error) }
    ret (Timestamp { nanos: ticks }, ok)
}

fn monotonic() -> (Instant, err) {
    let (ticks, clock_error) = os.clock(.Monotonic)
    if clock_error != ok { ret (Instant { nanos: 0i64 }, clock_error) }
    ret (Instant { nanos: ticks }, ok)
}

fn timer_start() -> (Timer, err) {
    let (started, clock_error) = monotonic()
    if clock_error != ok { ret (Timer { started: Instant { nanos: 0i64 } }, clock_error) }
    ret (Timer { started: started }, ok)
}

// A clock that fails mid-measurement reports no elapsed time rather than a wrong one.
fn timer_elapsed(t: Timer) -> Duration {
    ret since(t.started)
}

fn since(start: Instant) -> Duration {
    let (current, clock_error) = monotonic()
    if clock_error != ok { ret Duration { nanos: 0i64 } }
    ret instant_diff(current, start)
}

fn timestamp_add(t: Timestamp, d: Duration) -> Timestamp {
    ret Timestamp { nanos: t.nanos + d.nanos }
}

fn timestamp_diff(a: Timestamp, b: Timestamp) -> Duration {
    ret Duration { nanos: a.nanos - b.nanos }
}

fn timestamp_cmp(a: Timestamp, b: Timestamp) -> i32 {
    ret compare_nanos(a.nanos, b.nanos)
}

fn instant_add(t: Instant, d: Duration) -> Instant {
    ret Instant { nanos: t.nanos + d.nanos }
}

fn instant_diff(a: Instant, b: Instant) -> Duration {
    ret Duration { nanos: a.nanos - b.nanos }
}

fn instant_cmp(a: Instant, b: Instant) -> i32 {
    ret compare_nanos(a.nanos, b.nanos)
}

fn duration_add(a: Duration, b: Duration) -> Duration {
    ret Duration { nanos: a.nanos + b.nanos }
}

fn duration_sub(a: Duration, b: Duration) -> Duration {
    ret Duration { nanos: a.nanos - b.nanos }
}

fn duration_neg(d: Duration) -> Duration {
    ret Duration { nanos: 0i64 - d.nanos }
}

fn duration_scale(d: Duration, n: i64) -> Duration {
    ret Duration { nanos: d.nanos * n }
}

fn duration_cmp(a: Duration, b: Duration) -> i32 {
    ret compare_nanos(a.nanos, b.nanos)
}

fn compare_nanos(a: i64, b: i64) -> i32 {
    if a < b { ret -1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

fn days(n: i64) -> Duration {
    ret Duration { nanos: n * 86400000000000i64 }
}

fn hours(n: i64) -> Duration {
    ret Duration { nanos: n * 3600000000000i64 }
}

fn minutes(n: i64) -> Duration {
    ret Duration { nanos: n * 60000000000i64 }
}

fn seconds(n: i64) -> Duration {
    ret Duration { nanos: n * 1000000000i64 }
}

fn millis(n: i64) -> Duration {
    ret Duration { nanos: n * 1000000i64 }
}

fn micros(n: i64) -> Duration {
    ret Duration { nanos: n * 1000i64 }
}

fn nanos(n: i64) -> Duration {
    ret Duration { nanos: n }
}

// Truncating toward zero, so a duration and its negation give answers that differ
// only in sign.
fn as_days(d: Duration) -> i64 {
    ret d.nanos / 86400000000000i64
}

fn as_hours(d: Duration) -> i64 {
    ret d.nanos / 3600000000000i64
}

fn as_minutes(d: Duration) -> i64 {
    ret d.nanos / 60000000000i64
}

fn as_seconds(d: Duration) -> i64 {
    ret d.nanos / 1000000000i64
}

fn as_millis(d: Duration) -> i64 {
    ret d.nanos / 1000000i64
}

fn as_micros(d: Duration) -> i64 {
    ret d.nanos / 1000i64
}

fn as_nanos(d: Duration) -> i64 {
    ret d.nanos
}
