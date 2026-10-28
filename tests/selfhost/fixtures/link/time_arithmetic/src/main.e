// Public e.time arithmetic must never turn an overflow into a deadline in the
// opposite direction. These endpoint cases also cover the unit constructors.
use e.os
use e.time

fn main() {
    let largest = 9223372036854775807i64
    let smallest = 0i64 - 9223372036854775807i64 - 1i64

    if time.days(106752i64).nanos != largest || time.days(-106752i64).nanos != smallest { os.exit(1) }
    if time.hours(2562048i64).nanos != largest || time.minutes(153722880i64).nanos != largest { os.exit(2) }
    if time.seconds(9223372037i64).nanos != largest || time.millis(9223372036855i64).nanos != largest || time.micros(9223372036854776i64).nanos != largest { os.exit(3) }

    let high = time.Duration { nanos: largest }
    let low = time.Duration { nanos: smallest }
    let one = time.Duration { nanos: 1i64 }
    let minus_one = time.Duration { nanos: -1i64 }
    if time.duration_add(high, one).nanos != largest || time.duration_add(low, minus_one).nanos != smallest { os.exit(4) }
    if time.duration_sub(high, minus_one).nanos != largest || time.duration_sub(low, one).nanos != smallest { os.exit(5) }
    if time.duration_neg(low).nanos != largest || time.duration_scale(high, 2i64).nanos != largest || time.duration_scale(low, 2i64).nanos != smallest || time.duration_scale(low, -1i64).nanos != largest { os.exit(6) }

    let top_timestamp = time.Timestamp { nanos: largest }
    let bottom_timestamp = time.Timestamp { nanos: smallest }
    if time.timestamp_add(top_timestamp, one).nanos != largest || time.timestamp_add(bottom_timestamp, minus_one).nanos != smallest { os.exit(7) }
    if time.timestamp_diff(top_timestamp, time.Timestamp { nanos: -1i64 }).nanos != largest || time.timestamp_diff(bottom_timestamp, time.Timestamp { nanos: 1i64 }).nanos != smallest { os.exit(8) }

    let top_instant = time.Instant { nanos: largest }
    let bottom_instant = time.Instant { nanos: smallest }
    if time.instant_add(top_instant, one).nanos != largest || time.instant_add(bottom_instant, minus_one).nanos != smallest { os.exit(9) }
    if time.instant_diff(top_instant, time.Instant { nanos: -1i64 }).nanos != largest || time.instant_diff(bottom_instant, time.Instant { nanos: 1i64 }).nanos != smallest { os.exit(10) }

    let max_date = time.to_date(top_timestamp)
    let offset_date = time.to_date_at(top_timestamp, 1i32)
    let max_time = time.to_time(top_timestamp)
    let offset_time = time.to_time_at(top_timestamp, 1i32)
    if max_date.year != offset_date.year || max_date.month != offset_date.month || max_date.day != offset_date.day { os.exit(11) }
    if max_time.hour != offset_time.hour || max_time.minute != offset_time.minute || max_time.second != offset_time.second || max_time.nanos != offset_time.nanos { os.exit(12) }
    os.exit(0)
}
