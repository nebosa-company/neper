// Section 8's clocks, durations and civil calendar, over the `os.clock` intrinsic.
//
// Every declaration in the fence is here. `docs/modules.json` keeps `e.time` at
// `surface: "partial"` because the calendar arithmetic needs helpers of its own and
// spec 12 has no visibility, so a module held to its fence exactly could not have
// them -- not because anything the fence names is missing.
//
// Every duration is a signed nanosecond count, so the whole module is i64 arithmetic
// and the only failure is the clock's own. That count is also what bounds the
// calendar: an i64 of nanoseconds reaches from 1677 to 2262, and no date outside
// that is representable at all.

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

// --- The civil calendar.
//
// Proleptic Gregorian, which is to say the rules are run backwards past the year they
// were adopted rather than switching to Julian at some date and place. That is what
// the fence asks for and it is also the only choice that makes arithmetic total.

const NANOS_PER_SECOND: i64 = 1000000000i64
const NANOS_PER_DAY: i64 = 86400000000000i64
const NANOS_PER_MINUTE: i64 = 60000000000i64

// The days either side of the epoch that an i64 of nanoseconds can reach. The last
// partial day at each end is left out: a whole day of nanoseconds added to 106751 days
// passes what an i64 holds, and a range that is one day short at each extreme is
// better than one that wraps.
const MAX_CIVIL_DAY: i64 = 106750i64
const MIN_CIVIL_DAY: i64 = -106750i64

const ISO8601_LENGTH: usize = 30usize

// Floor division, not the truncation the operator gives. Every divisor here is
// positive and the dividend is not: a timestamp before 1970 is negative, and
// truncating toward zero would put the second before midnight in the following day.
fn floor_div(value: i64, divisor: i64) -> i64 {
    var quotient = value / divisor
    if value % divisor != 0i64 && value < 0i64 { quotient -= 1i64 }
    ret quotient
}

fn floor_mod(value: i64, divisor: i64) -> i64 {
    ret value - floor_div(value, divisor) * divisor
}

fn is_leap(year: i64) -> bool {
    if year % 4i64 != 0i64 { ret false }
    if year % 100i64 != 0i64 { ret true }
    ret year % 400i64 == 0i64
}

fn days_in_month(year: i64, month: i64) -> i64 {
    if month == 2i64 {
        if is_leap(year) { ret 29i64 }
        ret 28i64
    }
    if month == 4i64 || month == 6i64 || month == 9i64 || month == 11i64 { ret 30i64 }
    ret 31i64
}

// The day number for a civil date, counting from 1970-01-01. The year is shifted so
// that March begins it, which moves the leap day to the end of the year and lets the
// month lengths be one linear expression instead of a table. `era` is four hundred
// years, the period over which the calendar repeats exactly.
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    var shifted_year = year
    if month <= 2i64 { shifted_year -= 1i64 }
    // Floor division again, spelled the way it is spelled everywhere this algorithm
    // appears: subtracting 399 before truncating rounds a negative year down.
    var toward_floor = shifted_year
    if shifted_year < 0i64 { toward_floor = shifted_year - 399i64 }
    let era = toward_floor / 400i64
    let year_of_era = shifted_year - era * 400i64
    var month_index = month + 9i64
    if month > 2i64 { month_index = month - 3i64 }
    let day_of_year = (153i64 * month_index + 2i64) / 5i64 + day - 1i64
    let day_of_era = year_of_era * 365i64 + year_of_era / 4i64 - year_of_era / 100i64 + day_of_year
    // 719468 is the day number of 1970-01-01 counted from the start of the era that
    // holds it, which is what moves the answer onto the epoch.
    ret era * 146097i64 + day_of_era - 719468i64
}

// The inverse, by the same shift: the year, month and day for a day number.
fn civil_from_days(count: i64) -> (i64, i64, i64) {
    let shifted = count + 719468i64
    var toward_floor = shifted
    if shifted < 0i64 { toward_floor = shifted - 146096i64 }
    let era = toward_floor / 146097i64
    let day_of_era = shifted - era * 146097i64
    let year_of_era = (day_of_era - day_of_era / 1460i64 + day_of_era / 36524i64 - day_of_era / 146096i64) / 365i64
    let shifted_year = year_of_era + era * 400i64
    let day_of_year = day_of_era - (365i64 * year_of_era + year_of_era / 4i64 - year_of_era / 100i64)
    let month_index = (5i64 * day_of_year + 2i64) / 153i64
    let day = day_of_year - (153i64 * month_index + 2i64) / 5i64 + 1i64
    var month = month_index + 3i64
    if month_index >= 10i64 { month = month_index - 9i64 }
    var year = shifted_year
    if month <= 2i64 { year = shifted_year + 1i64 }
    ret (year, month, day)
}

// The offset is minutes and nothing more. A named zone is `e.tz`'s work, and so is
// deciding which offset a local time had -- this only shifts by one it is given.
fn to_date_at(t: Timestamp, offset_minutes: i32) -> Date {
    let local = t.nanos + i64(offset_minutes) * NANOS_PER_MINUTE
    let (year, month, day) = civil_from_days(floor_div(local, NANOS_PER_DAY))
    ret Date { year: i32(year), month: u8(month), day: u8(day) }
}

fn to_time_at(t: Timestamp, offset_minutes: i32) -> Time {
    let local = t.nanos + i64(offset_minutes) * NANOS_PER_MINUTE
    let within_day = floor_mod(local, NANOS_PER_DAY)
    let second_of_day = within_day / NANOS_PER_SECOND
    ret Time {
        hour: u8(second_of_day / 3600i64),
        minute: u8(second_of_day / 60i64 % 60i64),
        second: u8(second_of_day % 60i64),
        nanos: u32(within_day % NANOS_PER_SECOND),
    }
}

fn to_date(t: Timestamp) -> Date {
    ret to_date_at(t, 0i32)
}

fn to_time(t: Timestamp) -> Time {
    ret to_time_at(t, 0i32)
}

// Refused rather than clamped. The fence's clamping rule is about adding months and
// years -- where the day has to land somewhere -- not about being handed the
// thirty-first of February, which is not a date and should not become one.
fn from_civil(d: Date, t: Time) -> (Timestamp, err) {
    if d.month < 1u8 || d.month > 12u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let year = i64(d.year)
    let month = i64(d.month)
    let day = i64(d.day)
    if day < 1i64 || day > days_in_month(year, month) { ret (Timestamp { nanos: 0i64 }, Invalid) }
    if t.hour > 23u8 || t.minute > 59u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    // A leap second is not representable and is not quietly folded into the next one:
    // the fence has no room for a sixty-first second, and a count of nanoseconds since
    // the epoch has no gap to put one in.
    if t.second > 59u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    if t.nanos > 999999999u32 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let day_number = days_from_civil(year, month, day)
    if day_number > MAX_CIVIL_DAY || day_number < MIN_CIVIL_DAY { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let second_of_day = i64(t.hour) * 3600i64 + i64(t.minute) * 60i64 + i64(t.second)
    ret (Timestamp { nanos: day_number * NANOS_PER_DAY + second_of_day * NANOS_PER_SECOND + i64(t.nanos) }, ok)
}

fn write_digits(buf: []u8, at: usize, value: i64, width: usize) {
    var remaining = value
    var index = width
    while index > 0usize {
        index -= 1usize
        buf[at + index] = u8(48i64 + remaining % 10i64)
        remaining = remaining / 10i64
    }
}

// Fixed width, always UTC, always nine fractional digits:
// `1970-01-01T00:00:00.000000000Z` is thirty bytes and every representable timestamp
// writes exactly that shape. There is nothing variable to decide per field, and a
// caller can size a buffer without asking. A buffer too small to hold it gets nothing
// rather than a truncated timestamp that reads like a real one.
fn format_iso8601(t: Timestamp, buf: []u8) -> str {
    if buf.len < ISO8601_LENGTH { ret "" }
    let d = to_date(t)
    let clock = to_time(t)
    write_digits(buf, 0usize, i64(d.year), 4usize)
    buf[4usize] = 45u8
    write_digits(buf, 5usize, i64(d.month), 2usize)
    buf[7usize] = 45u8
    write_digits(buf, 8usize, i64(d.day), 2usize)
    buf[10usize] = 84u8
    write_digits(buf, 11usize, i64(clock.hour), 2usize)
    buf[13usize] = 58u8
    write_digits(buf, 14usize, i64(clock.minute), 2usize)
    buf[16usize] = 58u8
    write_digits(buf, 17usize, i64(clock.second), 2usize)
    buf[19usize] = 46u8
    write_digits(buf, 20usize, i64(clock.nanos), 9usize)
    buf[29usize] = 90u8
    ret buf[0usize..ISO8601_LENGTH]
}

fn digit_value(byte: u8) -> (i64, bool) {
    if byte < 48u8 || byte > 57u8 { ret (0i64, false) }
    ret (i64(byte - 48u8), true)
}

fn parse_digits(s: str, at: usize, width: usize) -> (i64, bool) {
    if at + width > s.len { ret (0i64, false) }
    var value = 0i64
    var index = 0usize
    while index < width {
        let (digit, is_digit) = digit_value(s[at + index])
        if !is_digit { ret (0i64, false) }
        value = value * 10i64 + digit
        index += 1usize
    }
    ret (value, true)
}

// Takes what `format_iso8601` writes and the shorter spellings of the same instant:
// the fraction may be absent or one to nine digits, and the zone may be `Z` or
// `+HH:MM` / `-HH:MM`. A time with no zone at all is refused -- a `Timestamp` is an
// instant, and a civil time without an offset does not name one.
//
// ponytail: only this shape. Ordinal dates (`1970-002`), week dates (`1970-W01-4`),
// a comma for the decimal point and a basic format with no separators are all ISO
// 8601 and none of them are here; the extended calendar form is what anything writes.
fn parse_iso8601(s: str) -> (Timestamp, err) {
    // `1970-01-01T00:00:00Z` is the shortest this accepts.
    if s.len < 20usize { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let (year, has_year) = parse_digits(s, 0usize, 4usize)
    if !has_year || s[4usize] != 45u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let (month, has_month) = parse_digits(s, 5usize, 2usize)
    if !has_month || s[7usize] != 45u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let (day, has_day) = parse_digits(s, 8usize, 2usize)
    if !has_day || s[10usize] != 84u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let (hour, has_hour) = parse_digits(s, 11usize, 2usize)
    if !has_hour || s[13usize] != 58u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let (minute, has_minute) = parse_digits(s, 14usize, 2usize)
    if !has_minute || s[16usize] != 58u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
    let (second, has_second) = parse_digits(s, 17usize, 2usize)
    if !has_second { ret (Timestamp { nanos: 0i64 }, Invalid) }
    var at = 19usize
    var fraction = 0i64
    if s[at] == 46u8 {
        at += 1usize
        var scale = 100000000i64
        var digits = 0usize
        while at < s.len && digits < 9usize {
            let (digit, is_digit) = digit_value(s[at])
            if !is_digit { break }
            fraction += digit * scale
            scale = scale / 10i64
            digits += 1usize
            at += 1usize
        }
        // A decimal point with no digits after it is not a fraction.
        if digits == 0usize { ret (Timestamp { nanos: 0i64 }, Invalid) }
    }
    if at >= s.len { ret (Timestamp { nanos: 0i64 }, Invalid) }
    var offset_minutes = 0i64
    if s[at] == 90u8 {
        at += 1usize
    } else {
        if s[at] != 43u8 && s[at] != 45u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
        let negative = s[at] == 45u8
        at += 1usize
        let (offset_hour, has_offset_hour) = parse_digits(s, at, 2usize)
        if !has_offset_hour { ret (Timestamp { nanos: 0i64 }, Invalid) }
        at += 2usize
        if at >= s.len || s[at] != 58u8 { ret (Timestamp { nanos: 0i64 }, Invalid) }
        at += 1usize
        let (offset_minute, has_offset_minute) = parse_digits(s, at, 2usize)
        if !has_offset_minute { ret (Timestamp { nanos: 0i64 }, Invalid) }
        at += 2usize
        if offset_hour > 23i64 || offset_minute > 59i64 { ret (Timestamp { nanos: 0i64 }, Invalid) }
        offset_minutes = offset_hour * 60i64 + offset_minute
        if negative { offset_minutes = 0i64 - offset_minutes }
    }
    // Trailing anything is a different string, not this one with something ignored.
    if at != s.len { ret (Timestamp { nanos: 0i64 }, Invalid) }
    var date: Date = zero
    date.year = i32(year)
    date.month = u8(month)
    date.day = u8(day)
    var clock: Time = zero
    clock.hour = u8(hour)
    clock.minute = u8(minute)
    clock.second = u8(second)
    clock.nanos = u32(fraction)
    let (civil, civil_error) = from_civil(date, clock)
    if civil_error != ok { ret (Timestamp { nanos: 0i64 }, civil_error) }
    // The fields read were local to the offset given, so the offset comes back off to
    // leave the instant they name.
    ret (Timestamp { nanos: civil.nanos - offset_minutes * NANOS_PER_MINUTE }, ok)
}

// --- Half-open intervals over any i64 unit (nanos, days, ...): `[start, end)`.

type Interval = struct { start: i64, end: i64 }

// Whether two half-open intervals share a point: `a.start < b.end && b.start < a.end`.
fn intervals_overlap(a: Interval, b: Interval) -> bool {
    ret a.start < b.end && b.start < a.end
}

// Merge a list sorted by `start` in place: overlapping or touching neighbours
// become one; answers the merged count (the prefix of `xs`).
fn intervals_merge(xs: []Interval) -> usize {
    if xs.len == 0usize { ret 0usize }
    var kept = 0usize
    var i = 1usize
    while i < xs.len {
        if xs[i].start <= xs[kept].end {
            if xs[i].end > xs[kept].end { xs[kept].end = xs[i].end }
        } else {
            kept += 1usize
            xs[kept] = xs[i]
        }
        i += 1usize
    }
    ret kept + 1usize
}
