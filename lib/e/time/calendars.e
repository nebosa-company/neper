// Non-ISO calendars over `e.time`'s day count (days from 1970-01-01), the way NodaTime
// keeps `CalendarSystem`s: a date in any calendar is a `time.Date` read in that calendar,
// and every conversion goes through the one day count. Three arithmetic calendars and
// the Japanese era reckoning:
//
// - `Julian`: leap every fourth year, proleptic, astronomical year numbering (year 0
//   exists, 1 BC is 0).
// - `IslamicCivil`: the tabular civil calendar (Friday epoch, 30-year cycle with leap
//   years 2 5 7 10 13 16 18 21 24 26 29; odd months 30 days, even 29, the 12th 30 in a
//   leap year). The observational and Umm al-Qura calendars are not arithmetic and are
//   not here.
// - `Hebrew`: the fixed-rule calendar (molad, four postponements, 12 or 13 months).
//   Months are numbered civil, NodaTime's default: Tishri is 1, and in a leap year
//   Adar I is 6 and Adar II is 7, so Nisan is 7 in an ordinary year and 8 in a leap one.
//   `scriptural_month` / `civil_month` convert to the Nisan-is-1 numbering.
// - `Persian`: the Solar Hijri calendar by its 33-year arithmetic rule (months 1-6 of 31
//   days, 7-11 of 30, the 12th 29 or 30), matching the astronomical calendar 1278..1502 AP.
// - `UmmAlQura`: the published month table for 1343..1500 AH, refused outside it.
//   The Coptic, Ethiopic and Thai Buddhist calendars follow the same surface.
//
// Japanese eras ride the Gregorian year, month and day: an era is a start date, the year
// of the era is the Gregorian year minus the era's start year plus one. The first era
// is Meiji (1868-09-08, the .NET and NodaTime table); earlier dates are refused.
//
// Month arithmetic counts real months (a Hebrew leap year has thirteen) and clamps the
// day to the landed month's length; years are 12-month (Hebrew: the same civil month
// number, clamped to the year's last month). Hebrew and Islamic years start at 1.

use e.time

type Calendar = enum u8 { Julian, IslamicCivil, Hebrew, Coptic, Ethiopic, ThaiBuddhist, Persian, UmmAlQura }
type JapaneseDate = struct { era: u8, year: i32, month: u8, day: u8 }
error Invalid

const RD_UNIX: i64 = 719163i64
const HEBREW_EPOCH: i64 = -1373427i64
const ISLAMIC_EPOCH: i64 = 227015i64
// The Coptic and Ethiopic calendars (twelve months of thirty days and a short month of five or six, a leap year when
// the year mod 4 is 3): their year 1 starts on these R.D. day numbers.
const COPTIC_EPOCH: i64 = 103605i64
const ETHIOPIC_EPOCH: i64 = 2796i64
// The Thai solar (Buddhist Era) calendar since 1941: the Gregorian year plus 543, the months and days the Gregorian ones.
const BUDDHIST_OFFSET: i64 = 543i64
// The Persian (Solar Hijri) calendar by its 33-year arithmetic rule: year 1 begins on this R.D. day, so that the
// rule agrees with the astronomical calendar from 1278 AP (1899) on; before that the astronomy differs by a day.
const PERSIAN_EPOCH: i64 = 226895i64
// Umm al-Qura: the table covers 1343..1500 AH; 1 Muharram 1343 is this day count from 1970-01-01.
const UQ_START: i64 = -16589i64
const UQ_FIRST: i64 = 1343i64
const UQ_LAST: i64 = 1500i64
const JULIAN_DAY_UNIX: i64 = 2440588i64
const ERA_COUNT: u8 = 5u8

// ---- Julian ----

fn julian_to_days(year: i64, month: i64, day: i64) -> i64 {
    let a = time.floor_div(14i64 - month, 12i64)
    let y = year + 4800i64 - a
    let m = month + 12i64 * a - 3i64
    let jdn = day + time.floor_div(153i64 * m + 2i64, 5i64) + 365i64 * y + time.floor_div(y, 4i64) - 32083i64
    ret jdn - JULIAN_DAY_UNIX
}

fn julian_from_days(count: i64) -> (i64, i64, i64) {
    let c = count + JULIAN_DAY_UNIX + 32082i64
    let d = time.floor_div(4i64 * c + 3i64, 1461i64)
    let e = c - time.floor_div(1461i64 * d, 4i64)
    let m = time.floor_div(5i64 * e + 2i64, 153i64)
    let day = e - time.floor_div(153i64 * m + 2i64, 5i64) + 1i64
    let month = m + 3i64 - 12i64 * time.floor_div(m, 10i64)
    let year = d - 4800i64 + time.floor_div(m, 10i64)
    ret (year, month, day)
}

// ---- Islamic civil ----

fn islamic_leap(year: i64) -> bool { ret time.floor_mod(14i64 + 11i64 * year, 30i64) < 11i64 }

fn islamic_fixed(year: i64, month: i64, day: i64) -> i64 {
    ret ISLAMIC_EPOCH - 1i64 + (year - 1i64) * 354i64 + time.floor_div(3i64 + 11i64 * year, 30i64) + 29i64 * (month - 1i64) + time.floor_div(month, 2i64) + day
}

fn islamic_to_days(year: i64, month: i64, day: i64) -> i64 { ret islamic_fixed(year, month, day) - RD_UNIX }

fn islamic_from_days(count: i64) -> (i64, i64, i64) {
    let rd = count + RD_UNIX
    let year = time.floor_div(30i64 * (rd - ISLAMIC_EPOCH) + 10646i64, 10631i64)
    let prior = rd - islamic_fixed(year, 1i64, 1i64)
    let month = time.floor_div(11i64 * prior + 330i64, 325i64)
    let day = rd - islamic_fixed(year, month, 1i64) + 1i64
    ret (year, month, day)
}

// ---- Hebrew ----

fn hebrew_leap(year: i64) -> bool { ret time.floor_mod(7i64 * year + 1i64, 19i64) < 7i64 }

fn hebrew_month_count(year: i64) -> i64 {
    if hebrew_leap(year) { ret 13i64 }
    ret 12i64
}

fn hebrew_elapsed(year: i64) -> i64 {
    let months = time.floor_div(235i64 * year - 234i64, 19i64)
    let parts = 12084i64 + 13753i64 * months
    var day = 29i64 * months + time.floor_div(parts, 25920i64)
    if time.floor_mod(3i64 * (day + 1i64), 7i64) < 3i64 { day += 1i64 }
    ret day
}

fn hebrew_new_year(year: i64) -> i64 {
    let ny0 = hebrew_elapsed(year - 1i64)
    let ny1 = hebrew_elapsed(year)
    let ny2 = hebrew_elapsed(year + 1i64)
    var correction = 0i64
    if ny2 - ny1 == 356i64 {
        correction = 2i64
    } else if ny1 - ny0 == 382i64 {
        correction = 1i64
    }
    ret HEBREW_EPOCH + ny1 + correction
}

fn hebrew_year_length(year: i64) -> i64 { ret hebrew_new_year(year + 1i64) - hebrew_new_year(year) }

// `s` is the scriptural number (Nisan 1 .. Adar 12, Adar II 13).
fn hebrew_scriptural_length(year: i64, s: i64) -> i64 {
    if s == 2i64 || s == 4i64 || s == 6i64 || s == 10i64 || s == 13i64 { ret 29i64 }
    if s == 12i64 && !hebrew_leap(year) { ret 29i64 }
    let length = hebrew_year_length(year)
    if s == 8i64 && length != 355i64 && length != 385i64 { ret 29i64 }
    if s == 9i64 && (length == 353i64 || length == 383i64) { ret 29i64 }
    ret 30i64
}

// Civil month (Tishri 1) to scriptural (Nisan 1).
fn scriptural_month(year: i32, civil: u8) -> u8 {
    let leap = hebrew_leap(i64(year))
    let c = i64(civil)
    if c <= 6i64 { ret u8(c + 6i64) }
    if leap {
        if c == 7i64 { ret 13u8 }
        ret u8(c - 7i64)
    }
    ret u8(c - 6i64)
}

fn civil_month(year: i32, scriptural: u8) -> u8 {
    let s = i64(scriptural)
    if s >= 7i64 { ret u8(s - 6i64) }
    ret u8(s + hebrew_month_count(i64(year)) - 6i64)
}

fn hebrew_civil_length(year: i64, civil: i64) -> i64 {
    ret hebrew_scriptural_length(year, i64(scriptural_month(i32(year), u8(civil))))
}

fn hebrew_to_days(year: i64, month: i64, day: i64) -> i64 {
    var days = hebrew_new_year(year) + day - 1i64
    var c = 1i64
    while c < month {
        days += hebrew_civil_length(year, c)
        c += 1i64
    }
    ret days - RD_UNIX
}

fn hebrew_from_days(count: i64) -> (i64, i64, i64) {
    let rd = count + RD_UNIX
    var year = time.floor_div((rd - HEBREW_EPOCH) * 98496i64, 35975351i64)
    while hebrew_new_year(year + 1i64) <= rd { year += 1i64 }
    while hebrew_new_year(year) > rd { year -= 1i64 }
    var left = rd - hebrew_new_year(year)
    var month = 1i64
    while month < hebrew_month_count(year) {
        let length = hebrew_civil_length(year, month)
        if left < length { break }
        left -= length
        month += 1i64
    }
    ret (year, month, left + 1i64)
}

// ---- Persian (33-year arithmetic) ----

// Leap years are those whose year mod 33 is 1 5 9 13 17 22 26 or 30.
fn persian_leap(year: i64) -> bool {
    let r = time.floor_mod(year, 33i64)
    if r < 1i64 { ret false }
    if r <= 17i64 { ret time.floor_mod(r - 1i64, 4i64) == 0i64 }
    if r < 22i64 { ret false }
    ret time.floor_mod(r - 22i64, 4i64) == 0i64 && r <= 30i64
}

// Leap years among the years 1 .. n.
fn persian_leaps_before(n: i64) -> i64 {
    let r = time.floor_mod(n, 33i64)
    var part = 0i64
    if r >= 22i64 {
        part = 6i64 + time.floor_div(r - 22i64, 4i64)
    } else if r >= 18i64 {
        part = 5i64
    } else {
        part = time.floor_div(r + 3i64, 4i64)
    }
    ret time.floor_div(n, 33i64) * 8i64 + part
}

fn persian_to_days(year: i64, month: i64, day: i64) -> i64 {
    var offset = 0i64
    if month <= 7i64 {
        offset = (month - 1i64) * 31i64
    } else {
        offset = 186i64 + (month - 7i64) * 30i64
    }
    ret PERSIAN_EPOCH + 365i64 * (year - 1i64) + persian_leaps_before(year - 1i64) + offset + day - 1i64 - RD_UNIX
}

fn persian_from_days(count: i64) -> (i64, i64, i64) {
    var year = time.floor_div((count + RD_UNIX - PERSIAN_EPOCH) * 33i64, 12053i64) + 1i64
    while persian_to_days(year + 1i64, 1i64, 1i64) <= count { year += 1i64 }
    while persian_to_days(year, 1i64, 1i64) > count { year -= 1i64 }
    let left = count - persian_to_days(year, 1i64, 1i64)
    if left < 186i64 { ret (year, left / 31i64 + 1i64, left - left / 31i64 * 31i64 + 1i64) }
    let rest = left - 186i64
    let month = 7i64 + rest / 30i64
    ret (year, month, rest - rest / 30i64 * 30i64 + 1i64)
}

// ---- Umm al-Qura (the published table) ----

fn hex_value(b: u8) -> i64 {
    if b >= 97u8 { ret i64(b) - 87i64 }
    ret i64(b) - 48i64
}

// The six hex digits of `year` as one number: twelve 2-bit lengths, month 1 on top.
fn uq_year_bits(year: i64) -> i64 {
    let digits = uq_table()
    let base = usize(year - UQ_FIRST) * 6usize
    var bits = 0i64
    var k = 0usize
    while k < 6usize {
        bits = bits * 16i64 + hex_value(digits[base + k])
        k += 1usize
    }
    ret bits
}

fn uq_month_length(year: i64, month: i64) -> i64 {
    var bits = uq_year_bits(year)
    var skip = 12i64 - month
    while skip > 0i64 {
        bits = time.floor_div(bits, 4i64)
        skip -= 1i64
    }
    ret 28i64 + time.floor_mod(bits, 4i64)
}

fn uq_year_length(year: i64) -> i64 {
    var total = 0i64
    var m = 1i64
    while m <= 12i64 {
        total += uq_month_length(year, m)
        m += 1i64
    }
    ret total
}

fn uq_year_start(year: i64) -> i64 {
    var day = UQ_START
    var y = UQ_FIRST
    while y < year {
        day += uq_year_length(y)
        y += 1i64
    }
    ret day
}

fn uq_to_days(year: i64, month: i64, day: i64) -> i64 {
    var days = uq_year_start(year) + day - 1i64
    var m = 1i64
    while m < month {
        days += uq_month_length(year, m)
        m += 1i64
    }
    ret days
}

// `count` is inside the table: 1343-01-01 up to the end of 1500.
fn uq_in_range(count: i64) -> bool {
    ret count >= UQ_START && count < uq_year_start(UQ_LAST + 1i64)
}

fn uq_from_days(count: i64) -> (i64, i64, i64) {
    var year = UQ_FIRST
    var start = UQ_START
    while year < UQ_LAST {
        let length = uq_year_length(year)
        if count < start + length { break }
        start += length
        year += 1i64
    }
    var left = count - start
    var month = 1i64
    while month < 12i64 {
        let length = uq_month_length(year, month)
        if left < length { break }
        left -= length
        month += 1i64
    }
    ret (year, month, left + 1i64)
}

// ---- the shared surface ----

fn african_epoch(cal: Calendar) -> i64 {
    if cal == .Ethiopic { ret ETHIOPIC_EPOCH }
    ret COPTIC_EPOCH
}

fn african_to_days(cal: Calendar, year: i64, month: i64, day: i64) -> i64 {
    let rd = african_epoch(cal) - 1i64 + 365i64 * (year - 1i64) + time.floor_div(year, 4i64) + 30i64 * (month - 1i64) + day
    ret rd - RD_UNIX
}

fn african_from_days(cal: Calendar, count: i64) -> (i64, i64, i64) {
    let rd = count + RD_UNIX
    let year = time.floor_div(4i64 * (rd - african_epoch(cal)) + 1463i64, 1461i64)
    let month = time.floor_div(rd - (african_to_days(cal, year, 1i64, 1i64) + RD_UNIX), 30i64) + 1i64
    let day = rd + 1i64 - (african_to_days(cal, year, month, 1i64) + RD_UNIX)
    ret (year, month, day)
}

fn is_leap_year(cal: Calendar, year: i32) -> bool {
    if cal == .ThaiBuddhist { ret time.is_leap(i64(year) - BUDDHIST_OFFSET) }
    if cal == .Persian { ret persian_leap(i64(year)) }
    if cal == .UmmAlQura { ret year_ok(cal, year) && uq_year_length(i64(year)) > 354i64 }
    if cal == .Coptic || cal == .Ethiopic { ret time.floor_mod(i64(year), 4i64) == 3i64 }
    if cal == .Julian { ret time.floor_mod(i64(year), 4i64) == 0i64 }
    if cal == .IslamicCivil { ret islamic_leap(i64(year)) }
    ret hebrew_leap(i64(year))
}

fn months_in_year(cal: Calendar, year: i32) -> u8 {
    if cal == .Coptic || cal == .Ethiopic { ret 13u8 }
    if cal == .Hebrew { ret u8(hebrew_month_count(i64(year))) }
    ret 12u8
}

fn year_ok(cal: Calendar, year: i32) -> bool {
    if cal == .Julian { ret true }
    if cal == .UmmAlQura { ret i64(year) >= UQ_FIRST && i64(year) <= UQ_LAST }
    ret year >= 1i32
}

fn days_in_month(cal: Calendar, year: i32, month: u8) -> (u8, err) {
    if !year_ok(cal, year) { ret (0u8, Invalid) }
    if month < 1u8 || month > months_in_year(cal, year) { ret (0u8, Invalid) }
    let y = i64(year)
    let m = i64(month)
    if cal == .Julian {
        if m == 2i64 {
            if time.floor_mod(y, 4i64) == 0i64 { ret (29u8, ok) }
            ret (28u8, ok)
        }
        if m == 4i64 || m == 6i64 || m == 9i64 || m == 11i64 { ret (30u8, ok) }
        ret (31u8, ok)
    }
    if cal == .ThaiBuddhist { ret (u8(time.days_in_month(y - BUDDHIST_OFFSET, m)), ok) }
    if cal == .UmmAlQura { ret (u8(uq_month_length(y, m)), ok) }
    if cal == .Persian {
        if m <= 6i64 { ret (31u8, ok) }
        if m <= 11i64 || persian_leap(y) { ret (30u8, ok) }
        ret (29u8, ok)
    }
    if cal == .Coptic || cal == .Ethiopic {
        if m == 13i64 {
            if time.floor_mod(y, 4i64) == 3i64 { ret (6u8, ok) }
            ret (5u8, ok)
        }
        ret (30u8, ok)
    }
    if cal == .IslamicCivil {
        if m == 12i64 && islamic_leap(y) { ret (30u8, ok) }
        if time.floor_mod(m, 2i64) == 1i64 { ret (30u8, ok) }
        ret (29u8, ok)
    }
    ret (u8(hebrew_civil_length(y, m)), ok)
}

fn valid(cal: Calendar, date: time.Date) -> bool {
    let (last, month_error) = days_in_month(cal, date.year, date.month)
    if month_error != ok { ret false }
    ret date.day >= 1u8 && date.day <= last
}

fn to_days(cal: Calendar, date: time.Date) -> (i64, err) {
    if !valid(cal, date) { ret (0i64, Invalid) }
    let y = i64(date.year)
    let m = i64(date.month)
    let d = i64(date.day)
    if cal == .Julian { ret (julian_to_days(y, m, d), ok) }
    if cal == .IslamicCivil { ret (islamic_to_days(y, m, d), ok) }
    if cal == .Coptic || cal == .Ethiopic { ret (african_to_days(cal, y, m, d), ok) }
    if cal == .ThaiBuddhist { ret (time.days_from_civil(y - BUDDHIST_OFFSET, m, d), ok) }
    if cal == .Persian { ret (persian_to_days(y, m, d), ok) }
    if cal == .UmmAlQura { ret (uq_to_days(y, m, d), ok) }
    ret (hebrew_to_days(y, m, d), ok)
}

fn make_date(year: i64, month: i64, day: i64) -> time.Date {
    var d: time.Date = zero
    d.year = i32(year)
    d.month = u8(month)
    d.day = u8(day)
    ret d
}

// Hebrew and Islamic years before 1, and counts that land there, answer `Invalid`.
fn from_days(cal: Calendar, count: i64) -> (time.Date, err) {
    if cal == .Julian {
        let (y, m, d) = julian_from_days(count)
        ret (make_date(y, m, d), ok)
    }
    if cal == .IslamicCivil {
        if count < islamic_to_days(1i64, 1i64, 1i64) { ret (zero, Invalid) }
        let (y, m, d) = islamic_from_days(count)
        ret (make_date(y, m, d), ok)
    }
    if cal == .Persian {
        if count < persian_to_days(1i64, 1i64, 1i64) { ret (zero, Invalid) }
        let (y, m, d) = persian_from_days(count)
        ret (make_date(y, m, d), ok)
    }
    if cal == .UmmAlQura {
        if !uq_in_range(count) { ret (zero, Invalid) }
        let (y, m, d) = uq_from_days(count)
        ret (make_date(y, m, d), ok)
    }
    if cal == .ThaiBuddhist {
        let (y, m, d) = time.civil_from_days(count)
        if y + BUDDHIST_OFFSET < 1i64 { ret (zero, Invalid) }
        ret (make_date(y + BUDDHIST_OFFSET, m, d), ok)
    }
    if cal == .Coptic || cal == .Ethiopic {
        if count < african_to_days(cal, 1i64, 1i64, 1i64) { ret (zero, Invalid) }
        let (y, m, d) = african_from_days(cal, count)
        ret (make_date(y, m, d), ok)
    }
    if count < hebrew_to_days(1i64, 1i64, 1i64) { ret (zero, Invalid) }
    let (y, m, d) = hebrew_from_days(count)
    ret (make_date(y, m, d), ok)
}

fn convert(from: Calendar, to: Calendar, date: time.Date) -> (time.Date, err) {
    let (count, count_error) = to_days(from, date)
    if count_error != ok { ret (zero, Invalid) }
    let (out, out_error) = from_days(to, count)
    ret (out, out_error)
}

fn from_iso(cal: Calendar, date: time.Date) -> (time.Date, err) {
    let count = time.days_from_civil(i64(date.year), i64(date.month), i64(date.day))
    let (out, out_error) = from_days(cal, count)
    ret (out, out_error)
}

fn to_iso(cal: Calendar, date: time.Date) -> (time.Date, err) {
    let (count, count_error) = to_days(cal, date)
    if count_error != ok { ret (zero, Invalid) }
    let (y, m, d) = time.civil_from_days(count)
    ret (make_date(y, m, d), ok)
}

// Months from the calendar's year 1, month 1 (Julian: from year 0): the currency of
// month arithmetic.
fn month_index(cal: Calendar, year: i64, month: i64) -> i64 {
    if cal == .Hebrew { ret time.floor_div(235i64 * year - 234i64, 19i64) + month - 1i64 }
    if cal == .Coptic || cal == .Ethiopic { ret year * 13i64 + month - 1i64 }
    ret year * 12i64 + month - 1i64
}

fn year_of_index(cal: Calendar, index: i64) -> i64 {
    if cal == .Coptic || cal == .Ethiopic { ret time.floor_div(index, 13i64) }
    if cal != .Hebrew { ret time.floor_div(index, 12i64) }
    var year = time.floor_div(19i64 * index + 234i64, 235i64)
    while month_index(cal, year + 1i64, 1i64) <= index { year += 1i64 }
    while month_index(cal, year, 1i64) > index { year -= 1i64 }
    ret year
}

fn add_months(cal: Calendar, date: time.Date, months: i64) -> (time.Date, err) {
    if !valid(cal, date) { ret (zero, Invalid) }
    let index = month_index(cal, i64(date.year), i64(date.month)) + months
    let year = year_of_index(cal, index)
    if year < -2147483648i64 || year > 2147483647i64 { ret (zero, Invalid) }
    if !year_ok(cal, i32(year)) { ret (zero, Invalid) }
    let month = index - month_index(cal, year, 1i64) + 1i64
    let (last, last_error) = days_in_month(cal, i32(year), u8(month))
    if last_error != ok { ret (zero, Invalid) }
    var day = i64(date.day)
    if day > i64(last) { day = i64(last) }
    ret (make_date(year, month, day), ok)
}

fn add_years(cal: Calendar, date: time.Date, years: i64) -> (time.Date, err) {
    if !valid(cal, date) { ret (zero, Invalid) }
    let year = i64(date.year) + years
    if year < -2147483648i64 || year > 2147483647i64 { ret (zero, Invalid) }
    if !year_ok(cal, i32(year)) { ret (zero, Invalid) }
    var month = i64(date.month)
    let last_month = i64(months_in_year(cal, i32(year)))
    if month > last_month { month = last_month }
    let (last, last_error) = days_in_month(cal, i32(year), u8(month))
    if last_error != ok { ret (zero, Invalid) }
    var day = i64(date.day)
    if day > i64(last) { day = i64(last) }
    ret (make_date(year, month, day), ok)
}

fn add_days(cal: Calendar, date: time.Date, days: i64) -> (time.Date, err) {
    let (count, count_error) = to_days(cal, date)
    if count_error != ok { ret (zero, Invalid) }
    let (out, out_error) = from_days(cal, count + days)
    ret (out, out_error)
}

fn day_of_year(cal: Calendar, date: time.Date) -> (u16, err) {
    let (count, count_error) = to_days(cal, date)
    if count_error != ok { ret (0u16, Invalid) }
    var first = date
    first.month = 1u8
    first.day = 1u8
    let (start, start_error) = to_days(cal, first)
    if start_error != ok { ret (0u16, Invalid) }
    ret (u16(count - start + 1i64), ok)
}

fn month_name_hebrew(year: i32, civil: u8) -> str {
    let s = scriptural_month(year, civil)
    if s == 1u8 { ret "Nisan" }
    if s == 2u8 { ret "Iyyar" }
    if s == 3u8 { ret "Sivan" }
    if s == 4u8 { ret "Tammuz" }
    if s == 5u8 { ret "Av" }
    if s == 6u8 { ret "Elul" }
    if s == 7u8 { ret "Tishri" }
    if s == 8u8 { ret "Heshvan" }
    if s == 9u8 { ret "Kislev" }
    if s == 10u8 { ret "Tevet" }
    if s == 11u8 { ret "Shevat" }
    if s == 12u8 {
        if hebrew_leap(i64(year)) { ret "Adar I" }
        ret "Adar"
    }
    ret "Adar II"
}

// ---- Japanese eras ----

fn era_name(era: u8) -> str {
    if era == 0u8 { ret "Meiji" }
    if era == 1u8 { ret "Taisho" }
    if era == 2u8 { ret "Showa" }
    if era == 3u8 { ret "Heisei" }
    if era == 4u8 { ret "Reiwa" }
    ret ""
}

// Start of era `era` as an ISO date (index 5 is the end of the table: not an era).
fn era_start(era: u8) -> time.Date {
    if era == 0u8 { ret make_date(1868i64, 9i64, 8i64) }
    if era == 1u8 { ret make_date(1912i64, 7i64, 30i64) }
    if era == 2u8 { ret make_date(1926i64, 12i64, 25i64) }
    if era == 3u8 { ret make_date(1989i64, 1i64, 8i64) }
    ret make_date(2019i64, 5i64, 1i64)
}

fn iso_count(date: time.Date) -> i64 { ret time.days_from_civil(i64(date.year), i64(date.month), i64(date.day)) }

fn japanese_from_iso(date: time.Date) -> (JapaneseDate, err) {
    if date.month < 1u8 || date.month > 12u8 { ret (zero, Invalid) }
    if i64(date.day) < 1i64 || i64(date.day) > time.days_in_month(i64(date.year), i64(date.month)) { ret (zero, Invalid) }
    let count = iso_count(date)
    var era = ERA_COUNT
    while era > 0u8 {
        if iso_count(era_start(era - 1u8)) <= count {
            var j: JapaneseDate = zero
            j.era = era - 1u8
            j.year = date.year - era_start(era - 1u8).year + 1i32
            j.month = date.month
            j.day = date.day
            ret (j, ok)
        }
        era -= 1u8
    }
    ret (zero, Invalid)
}

fn japanese_to_iso(j: JapaneseDate) -> (time.Date, err) {
    if j.era >= ERA_COUNT || j.year < 1i32 { ret (zero, Invalid) }
    let start = era_start(j.era)
    let year = start.year + j.year - 1i32
    let date = make_date(i64(year), i64(j.month), i64(j.day))
    if date.month < 1u8 || date.month > 12u8 { ret (zero, Invalid) }
    if i64(date.day) < 1i64 || i64(date.day) > time.days_in_month(i64(year), i64(date.month)) { ret (zero, Invalid) }
    let count = iso_count(date)
    if count < iso_count(start) { ret (zero, Invalid) }
    if j.era + 1u8 < ERA_COUNT {
        if count >= iso_count(era_start(j.era + 1u8)) { ret (zero, Invalid) }
    }
    ret (date, ok)
}

// The Umm al-Qura month lengths, years 1343..1500 AH (1924-08-01 to 2077-11-16): six hex digits a year, two bits a
// month (length - 28), month 1 in the top bits. Generated from the hijri-converter / hijridate table by
// `scripts/gen_persian_uq_test.py --table`.
fn uq_table() -> str {
    ret "9a6a2a59999999d8a65a69695a69a5999a5c999a8e6659a69995a69999999a66966669999999a6599a5999999aa65969a9965999999a99999999999999999a9998a999999a99999999999999999a999a6999999999666a66659a666666999a5a99996965a99996669a9999996666669999999a65999a69666699999999999a59a9a5999a59999a69999999999a999a6599999a59999a99599a9999699a65999a9966669999999a66666669a6599a666599a999666a665969a9965a69999999a66666669999669a66599a9996669a65969a9965a69a5966a66659a699996699a66599a9996669a6659aa6595aa69656a69996669a65999a66996669a6599a69965a9a65969a6966666999966a66659a69996669a59999a66666669a59969a96599a999666a66599a69966669999999a6696666a65966a69659a9999669a66599a69996669a65999a996666a59996a66665a66999666a665969a9965a6a65969a6665a6699999999a6659a6999666a66596a9996669a65999a66665a69a59699a9659a699996699a6599a6996666a65966a69659a6a59669a66599a669666669a6599a69965a6a65969a6965a66a59999a66659a6999666a66599a699666699a5999a69665a6a59666a66599a9996669a59999a666666669a5966a"
}
