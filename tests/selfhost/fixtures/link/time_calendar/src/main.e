// `e.time`'s civil calendar: the four conversions, `from_civil`, and ISO 8601 both ways.
//
// The expected nanosecond counts are not derived from this code -- they were computed
// independently and written down, so a wrong shift or a wrong leap rule fails here rather than
// agreeing with itself.

use e.mem
use e.os
use e.time

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn is_date(d: time.Date, year: i32, month: u8, day: u8) -> bool {
    if d.year != year { ret false }
    if d.month != month { ret false }
    if d.day != day { ret false }
    ret true
}

fn is_time(t: time.Time, hour: u8, minute: u8, second: u8, fraction: u32) -> bool {
    if t.hour != hour { ret false }
    if t.minute != minute { ret false }
    if t.second != second { ret false }
    if t.nanos != fraction { ret false }
    ret true
}

fn civil(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8, fraction: u32) -> (time.Timestamp, err) {
    var d: time.Date = zero
    d.year = year
    d.month = month
    d.day = day
    var t: time.Time = zero
    t.hour = hour
    t.minute = minute
    t.second = second
    t.nanos = fraction
    let (stamp, civil_error) = time.from_civil(d, t)
    ret (stamp, civil_error)
}

fn main(a: *mem.Arena) -> err {
    // --- The epoch itself, which every other answer is counted from.
    var epoch: time.Timestamp = zero
    if !is_date(time.to_date(epoch), 1970i32, 1u8, 1u8) { os.exit(10i32) }
    if !is_time(time.to_time(epoch), 0u8, 0u8, 0u8, 0u32) { os.exit(11i32) }

    // --- A date well away from it, checked against a count computed elsewhere.
    let (recent, recent_error) = civil(2026i32, 9u8, 9u8, 12u8, 34u8, 56u8, 123456789u32)
    if recent_error != ok { os.exit(12i32) }
    if recent.nanos != 1788957296123456789i64 { os.exit(13i32) }
    if !is_date(time.to_date(recent), 2026i32, 9u8, 9u8) { os.exit(14i32) }
    if !is_time(time.to_time(recent), 12u8, 34u8, 56u8, 123456789u32) { os.exit(15i32) }

    // --- Before the epoch, which is where truncating division goes wrong: the second before
    // midnight belongs to the last day of 1969, and dividing toward zero puts it in 1970.
    let (before, before_error) = civil(1969i32, 12u8, 31u8, 23u8, 59u8, 59u8, 0u32)
    if before_error != ok { os.exit(20i32) }
    if before.nanos != -1000000000i64 { os.exit(21i32) }
    if !is_date(time.to_date(before), 1969i32, 12u8, 31u8) { os.exit(22i32) }
    if !is_time(time.to_time(before), 23u8, 59u8, 59u8, 0u32) { os.exit(23i32) }

    // --- Long before it, which is where the four-hundred-year shift has to hold.
    let (old, old_error) = civil(1900i32, 3u8, 1u8, 0u8, 0u8, 0u8, 0u32)
    if old_error != ok { os.exit(24i32) }
    if old.nanos != -2203891200000000000i64 { os.exit(25i32) }
    if !is_date(time.to_date(old), 1900i32, 3u8, 1u8) { os.exit(26i32) }

    // --- The leap rule, in all three of its cases.
    let (leap, leap_error) = civil(2024i32, 2u8, 29u8, 12u8, 0u8, 0u8, 0u32)
    if leap_error != ok { os.exit(30i32) }
    if leap.nanos != 1709208000000000000i64 { os.exit(31i32) }
    // A year divisible by four hundred is a leap year even though it ends a century.
    let (century_leap, century_leap_error) = civil(2000i32, 2u8, 29u8, 0u8, 0u8, 0u8, 0u32)
    if century_leap_error != ok { os.exit(32i32) }
    if century_leap.nanos != 951782400000000000i64 { os.exit(33i32) }
    // A century that is not is not.
    let (century, century_error) = civil(1900i32, 2u8, 29u8, 0u8, 0u8, 0u8, 0u32)
    if century_error != time.Invalid { os.exit(34i32) }
    let (common, common_error) = civil(2023i32, 2u8, 29u8, 0u8, 0u8, 0u8, 0u32)
    if common_error != time.Invalid { os.exit(35i32) }

    // --- What is not a date, refused rather than folded into one that is.
    let (month_zero, month_zero_error) = civil(2026i32, 0u8, 1u8, 0u8, 0u8, 0u8, 0u32)
    if month_zero_error != time.Invalid { os.exit(40i32) }
    let (month_high, month_high_error) = civil(2026i32, 13u8, 1u8, 0u8, 0u8, 0u8, 0u32)
    if month_high_error != time.Invalid { os.exit(41i32) }
    let (day_zero, day_zero_error) = civil(2026i32, 1u8, 0u8, 0u8, 0u8, 0u8, 0u32)
    if day_zero_error != time.Invalid { os.exit(42i32) }
    let (day_high, day_high_error) = civil(2026i32, 4u8, 31u8, 0u8, 0u8, 0u8, 0u32)
    if day_high_error != time.Invalid { os.exit(43i32) }
    let (hour_high, hour_high_error) = civil(2026i32, 1u8, 1u8, 24u8, 0u8, 0u8, 0u32)
    if hour_high_error != time.Invalid { os.exit(44i32) }
    // A leap second has nowhere to go in a count of nanoseconds since the epoch.
    let (leap_second, leap_second_error) = civil(2016i32, 12u8, 31u8, 23u8, 59u8, 60u8, 0u32)
    if leap_second_error != time.Invalid { os.exit(45i32) }
    let (over_nanos, over_nanos_error) = civil(2026i32, 1u8, 1u8, 0u8, 0u8, 0u8, 1000000000u32)
    if over_nanos_error != time.Invalid { os.exit(46i32) }
    // Outside what an i64 of nanoseconds reaches, which is refused rather than wrapped.
    let (far, far_error) = civil(3000i32, 1u8, 1u8, 0u8, 0u8, 0u8, 0u32)
    if far_error != time.Invalid { os.exit(47i32) }
    let (ancient, ancient_error) = civil(1600i32, 1u8, 1u8, 0u8, 0u8, 0u8, 0u32)
    if ancient_error != time.Invalid { os.exit(48i32) }

    // --- An offset shifts the fields and nothing else. Ten hours past the epoch in a zone ten
    // hours ahead is the first day, not the last of 1969.
    var ten_hours: time.Timestamp = zero
    if !is_date(time.to_date_at(ten_hours, 600i32), 1970i32, 1u8, 1u8) { os.exit(50i32) }
    if !is_time(time.to_time_at(ten_hours, 600i32), 10u8, 0u8, 0u8, 0u32) { os.exit(51i32) }
    // And behind it, which crosses back over the epoch into the previous year.
    if !is_date(time.to_date_at(ten_hours, -600i32), 1969i32, 12u8, 31u8) { os.exit(52i32) }
    if !is_time(time.to_time_at(ten_hours, -600i32), 14u8, 0u8, 0u8, 0u32) { os.exit(53i32) }

    // --- Every day of a year, there and back. A shift that is wrong for one month only shows
    // up if every month is asked.
    var walk = 0i64
    while walk < 366i64 {
        var stepped: time.Timestamp = zero
        stepped.nanos = 1735689600000000000i64 + walk * 86400000000000i64
        let stepped_date = time.to_date(stepped)
        let stepped_time = time.to_time(stepped)
        let (back, back_error) = time.from_civil(stepped_date, stepped_time)
        if back_error != ok { os.exit(60i32) }
        if back.nanos != stepped.nanos { os.exit(61i32) }
        walk += 1i64
    }

    // --- ISO 8601 out. Fixed width, always UTC, nine fractional digits.
    var buffer: [40]u8 = zero
    let written = time.format_iso8601(epoch, buffer[..])
    if !same(written, "1970-01-01T00:00:00.000000000Z") { os.exit(70i32) }
    let written_recent = time.format_iso8601(recent, buffer[..])
    if !same(written_recent, "2026-09-09T12:34:56.123456789Z") { os.exit(71i32) }
    let written_before = time.format_iso8601(before, buffer[..])
    if !same(written_before, "1969-12-31T23:59:59.000000000Z") { os.exit(72i32) }
    // A buffer too small gets nothing rather than a timestamp that is missing its end.
    var cramped: [29]u8 = zero
    let refused = time.format_iso8601(epoch, cramped[..])
    if refused.len != 0usize { os.exit(73i32) }

    // --- ISO 8601 in, including the shorter spellings of the same instant.
    let (read_epoch, read_epoch_error) = time.parse_iso8601("1970-01-01T00:00:00.000000000Z")
    if read_epoch_error != ok { os.exit(80i32) }
    if read_epoch.nanos != 0i64 { os.exit(81i32) }
    let (read_short, read_short_error) = time.parse_iso8601("1970-01-01T00:00:00Z")
    if read_short_error != ok { os.exit(82i32) }
    if read_short.nanos != 0i64 { os.exit(83i32) }
    // A single fractional digit is tenths, not nanoseconds: what a digit is worth is decided by
    // where it sits, not by how many followed it.
    let (read_millis, read_millis_error) = time.parse_iso8601("1970-01-01T00:00:00.5Z")
    if read_millis_error != ok { os.exit(84i32) }
    if read_millis.nanos != 500000000i64 { os.exit(85i32) }
    let (read_recent, read_recent_error) = time.parse_iso8601("2026-09-09T12:34:56.123456789Z")
    if read_recent_error != ok { os.exit(86i32) }
    if read_recent.nanos != recent.nanos { os.exit(87i32) }
    // An offset names the same instant as the UTC spelling of it.
    let (read_offset, read_offset_error) = time.parse_iso8601("2026-09-09T14:34:56.123456789+02:00")
    if read_offset_error != ok { os.exit(88i32) }
    if read_offset.nanos != recent.nanos { os.exit(89i32) }
    let (read_behind, read_behind_error) = time.parse_iso8601("2026-09-09T07:34:56.123456789-05:00")
    if read_behind_error != ok { os.exit(90i32) }
    if read_behind.nanos != recent.nanos { os.exit(91i32) }

    // --- What is not this shape.
    let (no_zone, no_zone_error) = time.parse_iso8601("2026-09-09T12:34:56")
    if no_zone_error != time.Invalid { os.exit(100i32) }
    let (no_separator, no_separator_error) = time.parse_iso8601("20260909T123456Z")
    if no_separator_error != time.Invalid { os.exit(101i32) }
    let (empty_fraction, empty_fraction_error) = time.parse_iso8601("2026-09-09T12:34:56.Z")
    if empty_fraction_error != time.Invalid { os.exit(102i32) }
    let (trailing, trailing_error) = time.parse_iso8601("2026-09-09T12:34:56Z ")
    if trailing_error != time.Invalid { os.exit(103i32) }
    let (bad_month, bad_month_error) = time.parse_iso8601("2026-13-09T12:34:56Z")
    if bad_month_error != time.Invalid { os.exit(104i32) }
    let (bad_offset, bad_offset_error) = time.parse_iso8601("2026-09-09T12:34:56+0200")
    if bad_offset_error != time.Invalid { os.exit(105i32) }
    let (letters, letters_error) = time.parse_iso8601("not-a-timestamp-at-all")
    if letters_error != time.Invalid { os.exit(106i32) }
    ret ok
}
