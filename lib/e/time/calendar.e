// Proleptic Gregorian calendar arithmetic over `e.time`'s `Date` and `Time`, with
// ISO-8601 weekdays and weeks. The day count `e.time` already keeps (days from the
// civil epoch) is the one currency: every question is a conversion to it or back, so
// the calendar has no table beyond the month lengths.
//
// A pattern is a compile-time string over the closed verbs `yyyy MM dd HH mm ss
// SSSSSSSSS`; every other byte is literal. Locale names are absent on purpose, and
// zones and daylight saving belong to `e.tz`.

use e.time

type DateTime = struct { date: time.Date, time: time.Time }
type Weekday = enum u8 { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }
type IsoWeek = struct { year: i32, week: u8 }
type Components = struct { year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8, nanos: u32, weekday: Weekday, day_of_year: u16 }
error Invalid

fn is_leap_year(year: i32) -> bool { ret time.is_leap(i64(year)) }

fn days_in_month(year: i32, month: u8) -> (u8, err) {
    if month < 1u8 || month > 12u8 { ret (0u8, Invalid) }
    ret (u8(time.days_in_month(i64(year), i64(month))), ok)
}

fn valid_date(date: time.Date) -> bool {
    let (last, month_error) = days_in_month(date.year, date.month)
    if month_error != ok { ret false }
    ret date.day >= 1u8 && date.day <= last
}

fn valid_time(value: time.Time) -> bool {
    ret value.hour < 24u8 && value.minute < 60u8 && value.second < 60u8 && value.nanos < 1000000000u32
}

fn day_count(date: time.Date) -> i64 { ret time.days_from_civil(i64(date.year), i64(date.month), i64(date.day)) }

fn date_of(count: i64) -> time.Date {
    let (year, month, day) = time.civil_from_days(count)
    var d: time.Date = zero
    d.year = i32(year)
    d.month = u8(month)
    d.day = u8(day)
    ret d
}

// 1970-01-01 was a Thursday; the count is days since it.
fn weekday_of_count(count: i64) -> Weekday {
    let index = time.floor_mod(count + 3i64, 7i64)
    if index == 0i64 { ret .Monday }
    if index == 1i64 { ret .Tuesday }
    if index == 2i64 { ret .Wednesday }
    if index == 3i64 { ret .Thursday }
    if index == 4i64 { ret .Friday }
    if index == 5i64 { ret .Saturday }
    ret .Sunday
}

fn weekday_index(day: Weekday) -> i64 {
    if day == .Monday { ret 0i64 }
    if day == .Tuesday { ret 1i64 }
    if day == .Wednesday { ret 2i64 }
    if day == .Thursday { ret 3i64 }
    if day == .Friday { ret 4i64 }
    if day == .Saturday { ret 5i64 }
    ret 6i64
}

fn weekday(date: time.Date) -> (Weekday, err) {
    if !valid_date(date) { ret (.Monday, Invalid) }
    ret (weekday_of_count(day_count(date)), ok)
}

fn day_of_year(date: time.Date) -> (u16, err) {
    if !valid_date(date) { ret (0u16, Invalid) }
    let first = time.days_from_civil(i64(date.year), 1i64, 1i64)
    ret (u16(day_count(date) - first + 1i64), ok)
}

// ISO 8601: week 1 is the week with the year's first Thursday; a date's week-year may
// be the year before or after its calendar year.
fn iso_week(date: time.Date) -> (IsoWeek, err) {
    if !valid_date(date) { ret (zero, Invalid) }
    let count = day_count(date)
    // The Thursday of this date's week decides the week-year.
    let thursday = count - weekday_index(weekday_of_count(count)) + 3i64
    let (thursday_year, _, _) = time.civil_from_days(thursday)
    let year_start = time.days_from_civil(thursday_year, 1i64, 1i64)
    var w: IsoWeek = zero
    w.year = i32(thursday_year)
    w.week = u8((thursday - year_start) / 7i64 + 1i64)
    ret (w, ok)
}

fn compare(a: DateTime, b: DateTime) -> i32 {
    let da = day_count(a.date)
    let db = day_count(b.date)
    if da != db {
        if da < db { ret -1i32 }
        ret 1i32
    }
    let ta = time_nanos(a.time)
    let tb = time_nanos(b.time)
    if ta != tb {
        if ta < tb { ret -1i32 }
        ret 1i32
    }
    ret 0i32
}

fn time_nanos(value: time.Time) -> i64 {
    let seconds = (i64(value.hour) * 60i64 + i64(value.minute)) * 60i64 + i64(value.second)
    ret seconds * 1000000000i64 + i64(value.nanos)
}

fn add_days(value: DateTime, days: i64) -> (DateTime, err) {
    if !valid_date(value.date) || !valid_time(value.time) { ret (zero, Invalid) }
    let count = day_count(value.date) + days
    let (year, _, _) = time.civil_from_days(count)
    if year < -2147483648i64 || year > 2147483647i64 { ret (zero, Invalid) }
    var out = value
    out.date = date_of(count)
    ret (out, ok)
}

// The day is clamped to the last day of the month landed in.
fn add_months(value: DateTime, months: i64) -> (DateTime, err) {
    if !valid_date(value.date) || !valid_time(value.time) { ret (zero, Invalid) }
    let total = i64(value.date.year) * 12i64 + i64(value.date.month) - 1i64 + months
    let year = time.floor_div(total, 12i64)
    let month = time.floor_mod(total, 12i64) + 1i64
    if year < -2147483648i64 || year > 2147483647i64 { ret (zero, Invalid) }
    var out = value
    out.date.year = i32(year)
    out.date.month = u8(month)
    let last = u8(time.days_in_month(year, month))
    if out.date.day > last { out.date.day = last }
    ret (out, ok)
}

fn add_years(value: DateTime, years: i64) -> (DateTime, err) {
    let (result, add_error) = add_months(value, years * 12i64)
    ret (result, add_error)
}

fn difference_days(a: DateTime, b: DateTime) -> i64 { ret day_count(a.date) - day_count(b.date) }

fn components(value: DateTime) -> (Components, err) {
    if !valid_date(value.date) || !valid_time(value.time) { ret (zero, Invalid) }
    var c: Components = zero
    c.year = value.date.year
    c.month = value.date.month
    c.day = value.date.day
    c.hour = value.time.hour
    c.minute = value.time.minute
    c.second = value.time.second
    c.nanos = value.time.nanos
    c.weekday = weekday_of_count(day_count(value.date))
    let (yday, _) = day_of_year(value.date)
    c.day_of_year = yday
    ret (c, ok)
}

// The date and time fields are what count; `weekday` and `day_of_year` are derived and
// must agree with them.
fn from_components(value: Components) -> (DateTime, err) {
    var out: DateTime = zero
    out.date.year = value.year
    out.date.month = value.month
    out.date.day = value.day
    out.time.hour = value.hour
    out.time.minute = value.minute
    out.time.second = value.second
    out.time.nanos = value.nanos
    if !valid_date(out.date) || !valid_time(out.time) { ret (zero, Invalid) }
    let (derived, _) = components(out)
    if derived.weekday != value.weekday || derived.day_of_year != value.day_of_year { ret (zero, Invalid) }
    ret (out, ok)
}

// A run of one verb letter: how long it is.
fn run_length(pattern: str, at: usize) -> usize {
    var end = at
    while end < pattern.len && pattern[end] == pattern[at] { end += 1usize }
    ret end - at
}

fn is_verb(c: u8) -> bool {
    ret c == 121u8 || c == 77u8 || c == 100u8 || c == 72u8 || c == 109u8 || c == 115u8 || c == 83u8
}

// Writes `value` in exactly `width` digits, zero-padded, a `-` first when negative.
fn write_field(dst: []u8, at: usize, value: i64, width: usize) -> (usize, bool) {
    var written = at
    var magnitude = value
    if value < 0i64 {
        if written >= dst.len { ret (written, false) }
        dst[written] = 45u8
        written += 1usize
        magnitude = 0i64 - value
    }
    if written + width > dst.len { ret (written, false) }
    time.write_digits(dst, written, magnitude, width)
    ret (written + width, true)
}

fn format[PATTERN: str](value: DateTime, dst: []u8) -> (str, err) {
    if !valid_date(value.date) || !valid_time(value.time) { ret ("", Invalid) }
    let pattern: str = PATTERN
    var at = 0usize
    var written = 0usize
    while at < pattern.len {
        let c = pattern[at]
        if is_verb(c) {
            let width = run_length(pattern, at)
            var field = 0i64
            var digits = width
            if c == 121u8 {
                field = i64(value.date.year)
                if width != 4usize { ret ("", Invalid) }
            }
            if c == 77u8 {
                field = i64(value.date.month)
                if width != 2usize { ret ("", Invalid) }
            }
            if c == 100u8 {
                field = i64(value.date.day)
                if width != 2usize { ret ("", Invalid) }
            }
            if c == 72u8 {
                field = i64(value.time.hour)
                if width != 2usize { ret ("", Invalid) }
            }
            if c == 109u8 {
                field = i64(value.time.minute)
                if width != 2usize { ret ("", Invalid) }
            }
            if c == 115u8 {
                field = i64(value.time.second)
                if width != 2usize { ret ("", Invalid) }
            }
            if c == 83u8 {
                field = i64(value.time.nanos)
                if width != 9usize { ret ("", Invalid) }
            }
            let (next, fits) = write_field(dst, written, field, digits)
            if !fits { ret ("", Invalid) }
            written = next
            at += width
        } else {
            if written >= dst.len { ret ("", Invalid) }
            dst[written] = c
            written += 1usize
            at += 1usize
        }
    }
    ret (dst[..written], ok)
}

fn parse[PATTERN: str](source: str) -> (DateTime, err) {
    let pattern: str = PATTERN
    var out: DateTime = zero
    var at = 0usize
    var read = 0usize
    while at < pattern.len {
        let c = pattern[at]
        if is_verb(c) {
            let width = run_length(pattern, at)
            var negative = false
            if c == 121u8 && read < source.len && source[read] == 45u8 {
                negative = true
                read += 1usize
            }
            let (field, has_field) = time.parse_digits(source, read, width)
            if !has_field { ret (zero, Invalid) }
            var value = field
            if negative { value = 0i64 - field }
            if c == 121u8 { out.date.year = i32(value) }
            if c == 77u8 { out.date.month = u8(value) }
            if c == 100u8 { out.date.day = u8(value) }
            if c == 72u8 { out.time.hour = u8(value) }
            if c == 109u8 { out.time.minute = u8(value) }
            if c == 115u8 { out.time.second = u8(value) }
            if c == 83u8 { out.time.nanos = u32(value) }
            read += width
            at += width
        } else {
            if read >= source.len || source[read] != c { ret (zero, Invalid) }
            read += 1usize
            at += 1usize
        }
    }
    if read != source.len { ret (zero, Invalid) }
    // A pattern without a date field leaves month and day at zero, which no date has.
    if out.date.month == 0u8 { out.date.month = 1u8 }
    if out.date.day == 0u8 { out.date.day = 1u8 }
    if !valid_date(out.date) || !valid_time(out.time) { ret (zero, Invalid) }
    ret (out, ok)
}
