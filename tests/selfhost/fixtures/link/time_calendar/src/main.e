// `e.time.calendar`: leap years, month lengths, weekdays and ISO weeks across year
// boundaries, month and year arithmetic with the clamped day, components both ways,
// and comptime-pattern formatting and parsing. Every check has its own exit code.
use e.os
use e.mem
use e.time
use e.time.calendar as cal

fn text_equal(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn date(year: i32, month: u8, day: u8) -> time.Date {
    var d: time.Date = zero
    d.year = year
    d.month = month
    d.day = day
    ret d
}

fn at(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) -> cal.DateTime {
    var v: cal.DateTime = zero
    v.date = date(year, month, day)
    v.time.hour = hour
    v.time.minute = minute
    v.time.second = second
    ret v
}

fn main() {
    if !cal.is_leap_year(2000i32) || cal.is_leap_year(1900i32) || !cal.is_leap_year(2024i32) || cal.is_leap_year(2023i32) { os.exit(1) }
    let (feb, e1) = cal.days_in_month(2024i32, 2u8)
    let (_, bad_month) = cal.days_in_month(2024i32, 13u8)
    if e1 != ok || feb != 29u8 || bad_month != cal.Invalid { os.exit(2) }
    if !cal.valid_date(date(2024i32, 2u8, 29u8)) || cal.valid_date(date(2023i32, 2u8, 29u8)) || cal.valid_date(date(2023i32, 0u8, 1u8)) { os.exit(3) }
    var t: time.Time = zero
    t.hour = 23u8
    t.minute = 59u8
    t.second = 59u8
    t.nanos = 999999999u32
    var bad_time = t
    bad_time.hour = 24u8
    if !cal.valid_time(t) || cal.valid_time(bad_time) { os.exit(4) }
    let (wd, e2) = cal.weekday(date(2026i32, 9u8, 12u8))
    let (wd2, _) = cal.weekday(date(1970i32, 1u8, 1u8))
    let (wd3, _) = cal.weekday(date(1969i32, 12u8, 31u8))
    if e2 != ok || wd != .Saturday || wd2 != .Thursday || wd3 != .Wednesday { os.exit(5) }
    let (yd, e3) = cal.day_of_year(date(2024i32, 12u8, 31u8))
    let (yd2, _) = cal.day_of_year(date(2023i32, 3u8, 1u8))
    if e3 != ok || yd != 366u16 || yd2 != 60u16 { os.exit(6) }
    // ISO weeks: 2021-01-03 is week 53 of 2020; 2024-12-30 is week 1 of 2025.
    let (w1, e4) = cal.iso_week(date(2021i32, 1u8, 3u8))
    let (w2, _) = cal.iso_week(date(2024i32, 12u8, 30u8))
    let (w3, _) = cal.iso_week(date(2026i32, 9u8, 12u8))
    if e4 != ok || w1.year != 2020i32 || w1.week != 53u8 || w2.year != 2025i32 || w2.week != 1u8 || w3.year != 2026i32 || w3.week != 37u8 { os.exit(7) }
    let a = at(2024i32, 1u8, 31u8, 10u8, 0u8, 0u8)
    let (plus_month, e5) = cal.add_months(a, 1i64)
    if e5 != ok || plus_month.date.month != 2u8 || plus_month.date.day != 29u8 || plus_month.time.hour != 10u8 { os.exit(8) }
    let (minus_years, e6) = cal.add_years(plus_month, -1i64)
    if e6 != ok || minus_years.date.year != 2023i32 || minus_years.date.day != 28u8 { os.exit(9) }
    let (plus_days, e7) = cal.add_days(a, 366i64)
    if e7 != ok || plus_days.date.year != 2025i32 || plus_days.date.month != 1u8 || plus_days.date.day != 31u8 { os.exit(10) }
    if cal.difference_days(plus_days, a) != 366i64 || cal.difference_days(a, plus_days) != -366i64 { os.exit(11) }
    if cal.compare(a, plus_month) >= 0i32 || cal.compare(a, a) != 0i32 || cal.compare(at(2024i32, 1u8, 31u8, 10u8, 0u8, 1u8), a) <= 0i32 { os.exit(12) }
    let (c, e8) = cal.components(at(2026i32, 9u8, 12u8, 8u8, 30u8, 15u8))
    if e8 != ok || c.weekday != .Saturday || c.day_of_year != 255u16 || c.minute != 30u8 { os.exit(13) }
    let (back, e9) = cal.from_components(c)
    if e9 != ok || cal.compare(back, at(2026i32, 9u8, 12u8, 8u8, 30u8, 15u8)) != 0i32 { os.exit(14) }
    var wrong = c
    wrong.weekday = .Monday
    let (_, mismatch) = cal.from_components(wrong)
    if mismatch != cal.Invalid { os.exit(15) }
    var buffer: [40]u8 = zero
    let (shown, e10) = cal.format["yyyy-MM-dd HH:mm:ss"](at(2026i32, 9u8, 12u8, 8u8, 5u8, 9u8), buffer[0..])
    if e10 != ok || !text_equal(shown, "2026-09-12 08:05:09") { os.exit(16) }
    var with_nanos = at(2000i32, 1u8, 1u8, 0u8, 0u8, 0u8)
    with_nanos.time.nanos = 123456789u32
    let (shown2, e11) = cal.format["dd/MM/yyyy ss.SSSSSSSSS"](with_nanos, buffer[0..])
    if e11 != ok || !text_equal(shown2, "01/01/2000 00.123456789") { os.exit(17) }
    let (parsed, e12) = cal.parse["yyyy-MM-dd HH:mm:ss"]("2026-09-12 08:05:09")
    if e12 != ok || cal.compare(parsed, at(2026i32, 9u8, 12u8, 8u8, 5u8, 9u8)) != 0i32 { os.exit(18) }
    let (_, bad_parse) = cal.parse["yyyy-MM-dd"]("2026-13-01")
    let (_, bad_literal) = cal.parse["yyyy-MM-dd"]("2026/09/12")
    let (_, trailing) = cal.parse["yyyy-MM-dd"]("2026-09-12x")
    if bad_parse != cal.Invalid || bad_literal != cal.Invalid || trailing != cal.Invalid { os.exit(19) }
    let (short, e13) = cal.parse["HH:mm"]("23:59")
    if e13 != ok || short.time.hour != 23u8 || short.date.month != 1u8 { os.exit(20) }
    var small: [5]u8 = zero
    let (_, too_small) = cal.format["yyyy-MM-dd"](a, small[0..])
    if too_small != cal.Invalid { os.exit(21) }
    os.exit(0)
}
