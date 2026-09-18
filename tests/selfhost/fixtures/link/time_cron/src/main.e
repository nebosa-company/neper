// Six-field cron parsing, Vixie DOM/DOW rules, offsets and next-time search.

use e.mem
use e.os
use e.time
use e.time.cron

fn stamp(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) -> time.Timestamp {
    let date = time.Date { year: year, month: month, day: day }
    let clock = time.Time { hour: hour, minute: minute, second: second, nanos: 0u32 }
    let (value, stamp_error) = time.from_civil(date, clock)
    if stamp_error != ok { os.exit(20i32) }
    ret value
}

fn main(a: *mem.Arena) -> err {
    let (work, work_error) = cron.parse(a, "0 */15 9-10 * * 1-5", 0i32)
    if work_error != ok || !cron.matches(work, stamp(2024i32, 1u8, 1u8, 9u8, 30u8, 0u8)) || cron.matches(work, stamp(2024i32, 1u8, 1u8, 9u8, 31u8, 0u8)) { os.exit(1i32) }
    let (following, next_error) = cron.next(work, stamp(2024i32, 1u8, 1u8, 9u8, 30u8, 0u8))
    if next_error != ok || following.nanos != stamp(2024i32, 1u8, 1u8, 9u8, 45u8, 0u8).nanos { os.exit(2i32) }
    let (days, days_error) = cron.parse(a, "0 0 0 1 * 1", 0i32)
    if days_error != ok || !cron.matches(days, stamp(2024i32, 1u8, 8u8, 0u8, 0u8, 0u8)) { os.exit(3i32) }
    let (local_nine, offset_error) = cron.parse(a, "0 0 9 * * *", 60i32)
    let (offset_next, offset_next_error) = cron.next(local_nine, stamp(2024i32, 1u8, 1u8, 7u8, 59u8, 59u8))
    if offset_error != ok || offset_next_error != ok || offset_next.nanos != stamp(2024i32, 1u8, 1u8, 8u8, 0u8, 0u8).nanos { os.exit(4i32) }
    let (_, bad_second_error) = cron.parse(a, "60 * * * * *", 0i32)
    let (_, bad_step_error) = cron.parse(a, "*/0 * * * * *", 0i32)
    if bad_second_error != cron.Invalid || bad_step_error != cron.Invalid { os.exit(5i32) }
    ret ok
}
