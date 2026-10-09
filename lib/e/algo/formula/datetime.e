// The date and time function group of the formula library (L027): DATE, TIME, NOW, TODAY, YEAR, MONTH, DAY, HOUR,
// MINUTE, SECOND, CENTURY, WEEKDAY, WEEKNUM, ISOWEEKNUM, DATEADD, DATEDIF, DATETIME_DIFF, DAYS, DATEVALUE,
// TIMEVALUE, EDATE, EOMONTH, NETWORKDAYS, WORKDAY, YEARFRAC, ADD_DAYS, SUBTRACT_DAYS, ADD_MINUTES,
// SUBTRACT_MINUTES, DATETIME_ADD, FIRSTDAYOFMONTH, LASTDAYOFMONTH, EOWEEK, EWOMONTH, DAYOFYEAR, DAYSSINCE,
// DAYSREMAINING, HOURS_DIFF, TOTALHOURS, TOTALMINUTES, IS_BEFORE, IS_AFTER, DATEONLY, DATESTR, TIMESTR,
// TOTIMESTAMP, FROMTIMESTAMP, DATETIME_PARSE, FROMNOW, TONOW, UTCNOW, NETWORKDAY, WORKDAYS, WORKDAY_DIFF,
// WORKDAYADD, DATERANGE, SET_TIMEZONE and SET_LOCALE, plus `format_date` and `parse_date_with_format`, which the
// conversion functions share. Each follows appdor's `src/formula/datetime.js`.
//
// Everything is read and built in UTC. A date is a number of milliseconds since the epoch, an invalid one NaN, and
// the construction rules are JavaScript's (`Date.UTC` reads a year 0 to 99 as 1900 to 1999 and rolls a month or
// day past its range into the next period; a value past 8.64e15 is invalid). The clock is `ctx.now`.
//
// Differences: SET_TIMEZONE knows the zones in `e.tz`'s embedded pack and the fixed offsets, where JavaScript
// knows every IANA zone; SET_LOCALE writes English whatever the tag (JavaScript's `Intl` knows the locale);
// WORKDAY refuses a count past 10,000,000 days where JavaScript would loop for minutes.

use e.algo.formula as f
use e.math
use e.mem
use e.str
use e.text.unicode as unicode
use e.text.utf8 as utf8
use e.time
use e.tz

fn day_ms() -> f64 { ret 86400000.0f64 }

// --- JavaScript's date arithmetic -------------------------------------------------------------------------------------

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

// ToIntegerOrInfinity.
fn integer_of(x: f64) -> f64 {
    if x != x { ret 0.0f64 }
    ret math.trunc[f64](x)
}

// TimeClip.
fn time_clip(t: f64) -> f64 {
    if !finite(t) { ret f.nan() }
    if t > 8640000000000000.0f64 || t < -8640000000000000.0f64 { ret f.nan() }
    ret math.trunc[f64](t) + 0.0f64
}

// MakeDay(year, month, date): the day number, or NaN.
fn make_day(year: f64, month: f64, date: f64) -> f64 {
    if !finite(year) || !finite(month) || !finite(date) { ret f.nan() }
    let y = math.trunc[f64](year)
    let m = math.trunc[f64](month)
    let dt = math.trunc[f64](date)
    let ym = y + math.floor[f64](m / 12.0f64)
    if ym > 400000.0f64 || ym < -400000.0f64 { ret f.nan() }
    var mn = f.fmod(m, 12.0f64)
    if mn < 0.0f64 { mn += 12.0f64 }
    let days = time.days_from_civil(i64(ym), i64(mn) + 1i64, 1i64)
    ret f64(days) + dt - 1.0f64
}

fn make_time(hour: f64, minute: f64, second: f64, milli: f64) -> f64 {
    if !finite(hour) || !finite(minute) || !finite(second) || !finite(milli) { ret f.nan() }
    ret math.trunc[f64](hour) * 3600000.0f64 + math.trunc[f64](minute) * 60000.0f64 + math.trunc[f64](second) * 1000.0f64 + math.trunc[f64](milli)
}

// `Date.UTC(year, month, day, hour, minute, second, ms)`.
fn date_utc(year: f64, month: f64, day: f64, hour: f64, minute: f64, second: f64, milli: f64) -> f64 {
    var y = year
    if y == y {
        let yi = math.trunc[f64](y)
        if yi >= 0.0f64 && yi <= 99.0f64 { y = 1900.0f64 + yi } else { y = yi }
    }
    let d = make_day(y, month, day)
    let t = make_time(hour, minute, second, milli)
    if !finite(d) || !finite(t) { ret f.nan() }
    ret time_clip(d * day_ms() + t)
}

type Parts = struct { year: f64, month: f64, day: f64, hour: f64, minute: f64, second: f64, milli: f64, weekday: f64 }

// The UTC fields of a valid time value.
fn parts_of(ms: f64) -> Parts {
    let days = math.floor[f64](ms / day_ms())
    let into = ms - days * day_ms()
    let (year, month, day) = time.civil_from_days(i64(days))
    let whole = i64(into)
    var wd = f.fmod(days + 4.0f64, 7.0f64)
    if wd < 0.0f64 { wd += 7.0f64 }
    ret Parts { year: f64(year), month: f64(month - 1i64), day: f64(day), hour: f64(whole / 3600000i64), minute: f64(whole / 60000i64 % 60i64), second: f64(whole / 1000i64 % 60i64), milli: f64(whole % 1000i64), weekday: wd }
}

fn from_parts(p: Parts) -> f64 {
    // The parts of a valid date are already in range, so MakeDay/MakeTime never see a year in 0..99 mapped wrongly:
    // build with the raw year (setUTC* keep it), not `Date.UTC`'s 1900 shift.
    let d = make_day(p.year, p.month, p.day)
    let t = make_time(p.hour, p.minute, p.second, p.milli)
    if !finite(d) || !finite(t) { ret f.nan() }
    ret time_clip(d * day_ms() + t)
}

fn utc_midnight(ms: f64) -> f64 { ret math.floor[f64](ms / day_ms()) * day_ms() }

fn clock_now(c: *f.Call) -> f64 {
    if c.ev.ctx.has_now { ret c.ev.ctx.now }
    let (stamp, e) = time.now()
    if e != ok { ret 0.0f64 }
    ret math.floor[f64](f64(stamp.nanos) / 1000000.0f64)
}

fn js_round(x: f64) -> f64 {
    if !finite(x) { ret x }
    let fl = math.floor[f64](x)
    if x - fl >= 0.5f64 { ret fl + 1.0f64 }
    ret fl
}

// --- names -------------------------------------------------------------------------------------------------------------

fn month_name(index: i64) -> str {
    if index == 0i64 { ret "January" }
    if index == 1i64 { ret "February" }
    if index == 2i64 { ret "March" }
    if index == 3i64 { ret "April" }
    if index == 4i64 { ret "May" }
    if index == 5i64 { ret "June" }
    if index == 6i64 { ret "July" }
    if index == 7i64 { ret "August" }
    if index == 8i64 { ret "September" }
    if index == 9i64 { ret "October" }
    if index == 10i64 { ret "November" }
    ret "December"
}

fn weekday_name(index: i64) -> str {
    if index == 0i64 { ret "Sunday" }
    if index == 1i64 { ret "Monday" }
    if index == 2i64 { ret "Tuesday" }
    if index == 3i64 { ret "Wednesday" }
    if index == 4i64 { ret "Thursday" }
    if index == 5i64 { ret "Friday" }
    ret "Saturday"
}

// --- ISO week, units ----------------------------------------------------------------------------------------------------

fn iso_week_number(ms: f64) -> f64 {
    let p = parts_of(ms)
    let date = date_utc(p.year, p.month, p.day, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
    let day_num = f.fmod(parts_of(date).weekday + 6.0f64, 7.0f64)
    // Thursday of this week
    let thursday = date - day_num * day_ms() + 3.0f64 * day_ms()
    let tp = parts_of(thursday)
    let first = date_utc(tp.year, 0.0f64, 4.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
    let first_num = f.fmod(parts_of(first).weekday + 6.0f64, 7.0f64)
    let first_thursday = first - first_num * day_ms() + 3.0f64 * day_ms()
    ret 1.0f64 + js_round((thursday - first_thursday) / (7.0f64 * day_ms()))
}

// The canonical unit of a token: 1 year, 2 quarter, 3 month, 4 week, 5 day, 6 hour, 7 minute, 8 second,
// 9 millisecond, 0 unknown. `m` and `M` differ by case; everything else is case-insensitive.
fn normalize_unit(a: *mem.Arena, raw: str) -> u8 {
    let t = str.trim(raw)
    if str.eq(t, "M") { ret 3u8 }
    if str.eq(t, "m") { ret 7u8 }
    let l = f.lower_text(a, t)
    if str.eq(l, "ms") || str.eq(l, "millisecond") || str.eq(l, "milliseconds") { ret 9u8 }
    if str.eq(l, "s") || str.eq(l, "sec") || str.eq(l, "secs") || str.eq(l, "second") || str.eq(l, "seconds") { ret 8u8 }
    if str.eq(l, "min") || str.eq(l, "mins") || str.eq(l, "minute") || str.eq(l, "minutes") { ret 7u8 }
    if str.eq(l, "h") || str.eq(l, "hr") || str.eq(l, "hrs") || str.eq(l, "hour") || str.eq(l, "hours") { ret 6u8 }
    if str.eq(l, "d") || str.eq(l, "day") || str.eq(l, "days") { ret 5u8 }
    if str.eq(l, "w") || str.eq(l, "wk") || str.eq(l, "wks") || str.eq(l, "week") || str.eq(l, "weeks") { ret 4u8 }
    if str.eq(l, "mo") || str.eq(l, "mos") || str.eq(l, "month") || str.eq(l, "months") { ret 3u8 }
    if str.eq(l, "q") || str.eq(l, "quarter") || str.eq(l, "quarters") { ret 2u8 }
    if str.eq(l, "y") || str.eq(l, "yr") || str.eq(l, "yrs") || str.eq(l, "year") || str.eq(l, "years") { ret 1u8 }
    ret 0u8
}

// `String(v)` for a unit argument.
fn unit_text(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Blank { ret "" }
    if v.kind == .Date { ret f.date_js_string(a, v.n) }
    if v.kind == .Array {
        var out = ""
        var i = 0usize
        while i < v.items.len {
            if i > 0usize { out = f.join(a, out, ",") }
            if v.items[i].kind != .Blank { out = f.join(a, out, unit_text(a, v.items[i])) }
            i += 1usize
        }
        ret out
    }
    if v.kind == .Record { ret "[object Object]" }
    let t = f.to_text(a, v)
    if t.kind == .Error { ret f.code_text(t.code) }
    ret t.s
}

// `setUTC*` arithmetic on a time value: the unit's field plus `amount`, everything else kept.
fn add_unit(ms: f64, amount: f64, unit: u8) -> f64 {
    var p = parts_of(ms)
    if unit == 1u8 { p.year = p.year + amount }
    if unit == 2u8 { p.month = p.month + amount * 3.0f64 }
    if unit == 3u8 { p.month = p.month + amount }
    if unit == 4u8 { p.day = p.day + amount * 7.0f64 }
    if unit == 5u8 { p.day = p.day + amount }
    if unit == 6u8 { p.hour = p.hour + amount }
    if unit == 7u8 { p.minute = p.minute + amount }
    if unit == 8u8 { p.second = p.second + amount }
    if unit == 9u8 { p.milli = p.milli + amount }
    ret from_parts(p)
}

// `from` plus `count` months with the day of month clamped to the wanted month.
fn add_months_clamped(ms: f64, count: f64) -> f64 {
    var p = parts_of(ms)
    let day = p.day
    p.day = 1.0f64
    p.month = p.month + count
    let first = from_parts(p)
    if !finite(first) { ret first }
    let fp = parts_of(first)
    let last_day = parts_of(date_utc_raw(fp.year, fp.month + 1.0f64, 0.0f64)).day
    p.day = math.min[f64](day, last_day)
    ret from_parts(Parts { year: fp.year, month: fp.month, day: p.day, hour: p.hour, minute: p.minute, second: p.second, milli: p.milli, weekday: 0.0f64 })
}

// `Date.UTC(year, month, day)` without the 0..99 year shift: the same fields `setUTC*` would use.
fn date_utc_raw(year: f64, month: f64, day: f64) -> f64 {
    let d = make_day(year, month, day)
    if !finite(d) { ret f.nan() }
    ret time_clip(d * day_ms())
}

fn elapsed_months(from: f64, to: f64) -> f64 {
    let pf = parts_of(from)
    let pt = parts_of(to)
    var months = (pt.year - pf.year) * 12.0f64 + (pt.month - pf.month)
    if months > 0.0f64 && add_months_clamped(from, months) > to {
        months -= 1.0f64
    } else if months < 0.0f64 && add_months_clamped(from, months) < to {
        months += 1.0f64
    }
    ret months
}

// --- formatting ---------------------------------------------------------------------------------------------------------

fn pad_number(a: *mem.Arena, n: f64, width: usize) -> str {
    var text = f.number_text(a, abs_f(n))
    var out = text
    while out.len < width { out = f.join(a, "0", out) }
    ret out
}

fn upper_ascii(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var b = s[i]
        if b >= 97u8 && b <= 122u8 { b = b - 32u8 }
        out[i] = b
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn abs_f(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn ordinal(a: *mem.Arena, n: f64) -> str {
    let teens = f.fmod(n, 100.0f64)
    var suffix = "th"
    if !(teens >= 11.0f64 && teens <= 13.0f64) {
        let last = f.fmod(n, 10.0f64)
        if last == 1.0f64 { suffix = "st" }
        if last == 2.0f64 { suffix = "nd" }
        if last == 3.0f64 { suffix = "rd" }
    }
    ret f.join(a, f.number_text(a, n), suffix)
}

fn matches_at(fmt: str, at: usize, token: str) -> bool {
    if at + token.len > fmt.len { ret false }
    ret str.eq(fmt[at..at + token.len], token)
}

// The format token at `at`, in the regular expression's alternation order, or "".
fn token_at(fmt: str, at: usize) -> str {
    if matches_at(fmt, at, "LTS") { ret "LTS" }
    if matches_at(fmt, at, "LLLL") { ret "LLLL" }
    if matches_at(fmt, at, "LLL") { ret "LLL" }
    if matches_at(fmt, at, "LL") { ret "LL" }
    if matches_at(fmt, at, "LT") { ret "LT" }
    if matches_at(fmt, at, "L") { ret "L" }
    if matches_at(fmt, at, "YYYY") { ret "YYYY" }
    if matches_at(fmt, at, "YY") { ret "YY" }
    if matches_at(fmt, at, "MMMM") { ret "MMMM" }
    if matches_at(fmt, at, "MMM") { ret "MMM" }
    if matches_at(fmt, at, "MM") { ret "MM" }
    if matches_at(fmt, at, "M") { ret "M" }
    if matches_at(fmt, at, "DDDD") { ret "DDDD" }
    if matches_at(fmt, at, "DDD") { ret "DDD" }
    if matches_at(fmt, at, "DD") { ret "DD" }
    if matches_at(fmt, at, "Do") { ret "Do" }
    if matches_at(fmt, at, "D") { ret "D" }
    if matches_at(fmt, at, "dddd") { ret "dddd" }
    if matches_at(fmt, at, "ddd") { ret "ddd" }
    if matches_at(fmt, at, "dd") { ret "dd" }
    if matches_at(fmt, at, "SSS") { ret "SSS" }
    if matches_at(fmt, at, "HH") { ret "HH" }
    if matches_at(fmt, at, "H") { ret "H" }
    if matches_at(fmt, at, "hh") { ret "hh" }
    if matches_at(fmt, at, "h") { ret "h" }
    if matches_at(fmt, at, "mm") { ret "mm" }
    if matches_at(fmt, at, "m") { ret "m" }
    if matches_at(fmt, at, "ss") { ret "ss" }
    if matches_at(fmt, at, "s") { ret "s" }
    if matches_at(fmt, at, "ZZ") { ret "ZZ" }
    if matches_at(fmt, at, "Z") { ret "Z" }
    if matches_at(fmt, at, "WW") { ret "WW" }
    if matches_at(fmt, at, "W") { ret "W" }
    if matches_at(fmt, at, "Q") { ret "Q" }
    if matches_at(fmt, at, "A") { ret "A" }
    if matches_at(fmt, at, "a") { ret "a" }
    ret ""
}

fn localized(token: str) -> str {
    if str.eq(token, "L") { ret "MM/DD/YYYY" }
    if str.eq(token, "LL") { ret "MMMM D, YYYY" }
    if str.eq(token, "LLL") { ret "MMMM D, YYYY h:mm A" }
    if str.eq(token, "LLLL") { ret "dddd, MMMM D, YYYY h:mm A" }
    if str.eq(token, "LT") { ret "h:mm A" }
    if str.eq(token, "LTS") { ret "h:mm:ss A" }
    ret ""
}

// A date as text by moment-style tokens, in UTC and English; `[text]` is literal and an unknown letter stays.
fn format_date(a: *mem.Arena, ms: f64, fmt: str) -> str {
    let p = parts_of(ms)
    var out = ""
    var i = 0usize
    let year = p.year
    let month = p.month
    let day_of_month = p.day
    let weekday = weekday_name(i64(p.weekday))
    let hours24 = p.hour
    var hours12 = f.fmod(hours24, 12.0f64)
    if hours12 == 0.0f64 { hours12 = 12.0f64 }
    let day_of_year = math.floor[f64]((date_utc(year, month, day_of_month, 0.0f64, 0.0f64, 0.0f64, 0.0f64) - date_utc(year, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)) / day_ms()) + 1.0f64
    let iso_week = iso_week_number(ms)
    while i < fmt.len {
        if fmt[i] == 91u8 {
            // [escaped]
            var close = i + 1usize
            while close < fmt.len && fmt[close] != 93u8 { close += 1usize }
            if close < fmt.len {
                out = f.join(a, out, fmt[i + 1usize..close])
                i = close + 1usize
                continue
            }
        }
        let token = token_at(fmt, i)
        if token.len == 0usize {
            out = f.join(a, out, fmt[i..i + 1usize])
            i += 1usize
            continue
        }
        i += token.len
        let expansion = localized(token)
        if expansion.len > 0usize {
            out = f.join(a, out, format_date(a, ms, expansion))
            continue
        }
        var piece = ""
        if str.eq(token, "YYYY") { piece = f.number_text(a, year) }
        if str.eq(token, "YY") { piece = pad_number(a, f.fmod(year, 100.0f64), 2usize) }
        if str.eq(token, "MMMM") { piece = month_name(i64(month)) }
        if str.eq(token, "MMM") { piece = month_name(i64(month))[0usize..3usize] }
        if str.eq(token, "MM") { piece = pad_number(a, month + 1.0f64, 2usize) }
        if str.eq(token, "M") { piece = f.number_text(a, month + 1.0f64) }
        if str.eq(token, "Q") { piece = f.number_text(a, math.floor[f64](month / 3.0f64) + 1.0f64) }
        if str.eq(token, "DDDD") { piece = pad_number(a, day_of_year, 3usize) }
        if str.eq(token, "DDD") { piece = f.number_text(a, day_of_year) }
        if str.eq(token, "DD") { piece = pad_number(a, day_of_month, 2usize) }
        if str.eq(token, "Do") { piece = ordinal(a, day_of_month) }
        if str.eq(token, "D") { piece = f.number_text(a, day_of_month) }
        if str.eq(token, "dddd") { piece = weekday }
        if str.eq(token, "ddd") { piece = weekday[0usize..3usize] }
        if str.eq(token, "dd") { piece = weekday[0usize..2usize] }
        if str.eq(token, "WW") { piece = pad_number(a, iso_week, 2usize) }
        if str.eq(token, "W") { piece = f.number_text(a, iso_week) }
        if str.eq(token, "HH") { piece = pad_number(a, hours24, 2usize) }
        if str.eq(token, "H") { piece = f.number_text(a, hours24) }
        if str.eq(token, "hh") { piece = pad_number(a, hours12, 2usize) }
        if str.eq(token, "h") { piece = f.number_text(a, hours12) }
        if str.eq(token, "A") {
            if hours24 < 12.0f64 { piece = "AM" } else { piece = "PM" }
        }
        if str.eq(token, "a") {
            if hours24 < 12.0f64 { piece = "am" } else { piece = "pm" }
        }
        if str.eq(token, "mm") { piece = pad_number(a, p.minute, 2usize) }
        if str.eq(token, "m") { piece = f.number_text(a, p.minute) }
        if str.eq(token, "ss") { piece = pad_number(a, p.second, 2usize) }
        if str.eq(token, "s") { piece = f.number_text(a, p.second) }
        if str.eq(token, "SSS") { piece = pad_number(a, p.milli, 3usize) }
        if str.eq(token, "ZZ") { piece = "+0000" }
        if str.eq(token, "Z") { piece = "+00:00" }
        out = f.join(a, out, piece)
    }
    ret out
}

// --- parsing against a format ------------------------------------------------------------------------------------------

fn parse_tokens() -> [28]str {
    var t: [28]str = zero
    t[0usize] = "YYYY"
    t[1usize] = "MMMM"
    t[2usize] = "MMM"
    t[3usize] = "SSS"
    t[4usize] = "DDDD"
    t[5usize] = "DDD"
    t[6usize] = "dddd"
    t[7usize] = "ddd"
    t[8usize] = "YY"
    t[9usize] = "MM"
    t[10usize] = "DD"
    t[11usize] = "HH"
    t[12usize] = "hh"
    t[13usize] = "mm"
    t[14usize] = "ss"
    t[15usize] = "dd"
    t[16usize] = "Do"
    t[17usize] = "WW"
    t[18usize] = "M"
    t[19usize] = "D"
    t[20usize] = "H"
    t[21usize] = "h"
    t[22usize] = "m"
    t[23usize] = "s"
    t[24usize] = "W"
    t[25usize] = "Q"
    t[26usize] = "A"
    t[27usize] = "a"
    ret t
}

fn numeric_width(token: str) -> usize {
    if str.eq(token, "YYYY") { ret 4usize }
    if str.eq(token, "SSS") { ret 3usize }
    if str.eq(token, "YY") || str.eq(token, "MM") || str.eq(token, "M") || str.eq(token, "DD") || str.eq(token, "D") || str.eq(token, "HH") || str.eq(token, "H") || str.eq(token, "hh") || str.eq(token, "h") || str.eq(token, "mm") || str.eq(token, "m") || str.eq(token, "ss") || str.eq(token, "s") { ret 2usize }
    ret 0usize
}

// The date a text spells in the given format, or false. Time of day tokens, `A`/`a`, and month names are read; the
// descriptive tokens (`dddd`, `Do`, `W`, `Q`) consume the alphanumeric run they occupy and are discarded.
fn parse_date_with_format(a: *mem.Arena, src_text: str, fmt_text: str) -> (f64, bool) {
    if src_text.len == 0usize || fmt_text.len == 0usize { ret (0.0f64, false) }
    let src = units_of(a, src_text)
    let fmt = units_of(a, fmt_text)
    let tokens = parse_tokens()
    var y = 0.0f64
    var has_y = false
    var mo = 0.0f64
    var has_mo = false
    var d = 0.0f64
    var has_d = false
    var hour = 0.0f64
    var has_h = false
    var minute = 0.0f64
    var second = 0.0f64
    var milli = 0.0f64
    var pm = 0i32
    var i = 0usize
    var j = 0usize
    while j < fmt.len {
        var token = ""
        var k = 0usize
        while k < 28usize && token.len == 0usize {
            let t = tokens[k]
            if j + t.len <= fmt.len {
                var all = true
                var q = 0usize
                while q < t.len && all {
                    if u32(fmt[j + q]) != u32(t[q]) { all = false }
                    q += 1usize
                }
                if all { token = t }
            }
            k += 1usize
        }
        if token.len == 0usize {
            if i >= src.len || src[i] != fmt[j] { ret (0.0f64, false) }
            i += 1usize
            j += 1usize
            continue
        }
        j += token.len
        if str.eq(token, "MMMM") || str.eq(token, "MMM") {
            var found = -1i64
            var m = 0i64
            while m < 12i64 && found < 0i64 {
                var name = month_name(m)
                if str.eq(token, "MMM") { name = name[0usize..3usize] }
                let lowered = f.lower_text(a, name)
                var all = i + lowered.len <= src.len
                var q = 0usize
                while all && q < lowered.len {
                    var u = u32(src[i + q])
                    if u >= 65u32 && u <= 90u32 { u += 32u32 }
                    if u != u32(lowered[q]) { all = false }
                    q += 1usize
                }
                if all { found = m }
                m += 1i64
            }
            if found < 0i64 { ret (0.0f64, false) }
            mo = f64(found)
            has_mo = true
            if str.eq(token, "MMM") { i += 3usize } else { i += month_name(found).len }
            continue
        }
        if str.eq(token, "A") || str.eq(token, "a") {
            if i + 2usize > src.len { ret (0.0f64, false) }
            var u0 = u32(src[i])
            var u1 = u32(src[i + 1usize])
            if u0 >= 65u32 && u0 <= 90u32 { u0 += 32u32 }
            if u1 >= 65u32 && u1 <= 90u32 { u1 += 32u32 }
            if u1 != 109u32 || (u0 != 97u32 && u0 != 112u32) { ret (0.0f64, false) }
            if u0 == 112u32 { pm = 1i32 } else { pm = 2i32 }
            i += 2usize
            continue
        }
        let width = numeric_width(token)
        if width == 0usize {
            while i < src.len && ((u32(src[i]) >= 65u32 && u32(src[i]) <= 90u32) || (u32(src[i]) >= 97u32 && u32(src[i]) <= 122u32) || (u32(src[i]) >= 48u32 && u32(src[i]) <= 57u32)) { i += 1usize }
            continue
        }
        var digits = 0usize
        var n = 0.0f64
        while digits < width && i < src.len && u32(src[i]) >= 48u32 && u32(src[i]) <= 57u32 {
            n = n * 10.0f64 + f64(u32(src[i]) - 48u32)
            digits += 1usize
            i += 1usize
        }
        if digits == 0usize { ret (0.0f64, false) }
        if str.eq(token, "YYYY") {
            y = n
            has_y = true
        } else if str.eq(token, "YY") {
            has_y = true
            if n <= 68.0f64 { y = 2000.0f64 + n } else { y = 1900.0f64 + n }
        } else if str.eq(token, "MM") || str.eq(token, "M") {
            mo = n - 1.0f64
            has_mo = true
        } else if str.eq(token, "DD") || str.eq(token, "D") {
            d = n
            has_d = true
        } else if str.eq(token, "HH") || str.eq(token, "H") || str.eq(token, "hh") || str.eq(token, "h") {
            hour = n
            has_h = true
        } else if str.eq(token, "mm") || str.eq(token, "m") {
            minute = n
        } else if str.eq(token, "ss") || str.eq(token, "s") {
            second = n
        } else if str.eq(token, "SSS") {
            milli = n
        }
    }
    if i < src.len { ret (0.0f64, false) }
    if !has_y || !has_mo || !has_d { ret (0.0f64, false) }
    if mo < 0.0f64 || mo > 11.0f64 || d < 1.0f64 || d > 31.0f64 { ret (0.0f64, false) }
    var hours = 0.0f64
    if has_h { hours = hour }
    if pm == 1i32 && hours < 12.0f64 { hours += 12.0f64 }
    if pm == 2i32 && hours == 12.0f64 { hours = 0.0f64 }
    let out = date_utc(y, mo, d, hours, minute, second, milli)
    if !finite(out) { ret (0.0f64, false) }
    let p = parts_of(out)
    if p.month != mo || p.day != d { ret (0.0f64, false) }
    ret (out, true)
}

fn units_of(a: *mem.Arena, s: str) -> []u16 {
    var none: []u16 = zero
    var n = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got { more = false } else {
            n += 1usize
            if scalar >= 65536u32 { n += 1usize }
        }
    }
    if n == 0usize { ret none }
    let (out, e) = mem.alloc[u16](a, n)
    if e != ok { ret none }
    var w = 0usize
    it = utf8.iterator(s)
    more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else if scalar >= 65536u32 {
            out[w] = u16(55296u32 + ((scalar - 65536u32) >> 10u32))
            out[w + 1usize] = u16(56320u32 + ((scalar - 65536u32) & 1023u32))
            w += 2usize
        } else {
            out[w] = u16(scalar)
            w += 1usize
        }
    }
    ret out
}

// --- handlers -----------------------------------------------------------------------------------------------------------

// The date an argument stands for: `valid` false with `early` set to blank or the error.
fn as_date(c: *f.Call, i: usize) -> (f64, f.Value, bool) {
    let v = c.args[i]
    if f.is_blank(v) { ret (0.0f64, f.blank(), false) }
    let d = f.to_date(c.a, v)
    if f.is_error(d) { ret (0.0f64, d, false) }
    if d.kind != .Date { ret (0.0f64, f.blank(), false) }
    ret (d.n, f.blank(), true)
}

fn num_or(c: *f.Call, i: usize, fallback: f64) -> f64 {
    let n = f.to_number(c.a, c.args[i])
    if f.is_error(n) { ret f.nan() }
    if n.kind == .Blank { ret fallback }
    ret n.n
}

fn h_date(c: *f.Call) -> f.Value {
    let y = f.to_number(c.a, c.args[0usize])
    let m = f.to_number(c.a, c.args[1usize])
    let d = f.to_number(c.a, c.args[2usize])
    if f.is_error(y) { ret y }
    if f.is_error(m) { ret m }
    if f.is_error(d) { ret d }
    var yv = 0.0f64
    if y.kind != .Blank { yv = y.n }
    var mv = 1.0f64
    if m.kind != .Blank { mv = m.n }
    var dv = 1.0f64
    if d.kind != .Blank { dv = d.n }
    ret f.date(date_utc(yv, mv - 1.0f64, dv, 0.0f64, 0.0f64, 0.0f64, 0.0f64))
}

fn h_time(c: *f.Call) -> f.Value {
    let h = f.to_number(c.a, c.args[0usize])
    let m = f.to_number(c.a, c.args[1usize])
    let s = f.to_number(c.a, c.args[2usize])
    if f.is_error(h) { ret h }
    if f.is_error(m) { ret m }
    if f.is_error(s) { ret s }
    var hv = 0.0f64
    if h.kind != .Blank { hv = h.n }
    var mv = 0.0f64
    if m.kind != .Blank { mv = m.n }
    var sv = 0.0f64
    if s.kind != .Blank { sv = s.n }
    ret f.date(date_utc(1970.0f64, 0.0f64, 1.0f64, hv, mv, sv, 0.0f64))
}

fn h_now(c: *f.Call) -> f.Value { ret f.date(clock_now(c)) }

fn h_today(c: *f.Call) -> f.Value { ret f.date(utc_midnight(clock_now(c))) }

// YEAR..CENTURY: which field.
fn extract(c: *f.Call, what: u8) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let p = parts_of(ms)
    if what == 0u8 { ret f.number(p.year) }
    if what == 1u8 { ret f.number(p.month + 1.0f64) }
    if what == 2u8 { ret f.number(p.day) }
    if what == 3u8 { ret f.number(p.hour) }
    if what == 4u8 { ret f.number(p.minute) }
    if what == 5u8 { ret f.number(p.second) }
    ret f.number(math.floor[f64]((p.year - 1.0f64) / 100.0f64) + 1.0f64)
}

fn h_year(c: *f.Call) -> f.Value { ret extract(c, 0u8) }

fn h_month(c: *f.Call) -> f.Value { ret extract(c, 1u8) }

fn h_day(c: *f.Call) -> f.Value { ret extract(c, 2u8) }

fn h_hour(c: *f.Call) -> f.Value { ret extract(c, 3u8) }

fn h_minute(c: *f.Call) -> f.Value { ret extract(c, 4u8) }

fn h_second(c: *f.Call) -> f.Value { ret extract(c, 5u8) }

fn h_century(c: *f.Call) -> f.Value { ret extract(c, 6u8) }

fn h_weekday(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    var kind = 1.0f64
    if c.args.len > 1usize { kind = math.trunc[f64](num_or(c, 1usize, 1.0f64)) }
    let dow = parts_of(ms).weekday
    if kind == 1.0f64 { ret f.number(dow + 1.0f64) }
    if kind == 2.0f64 {
        if dow == 0.0f64 { ret f.number(7.0f64) }
        ret f.number(dow)
    }
    if kind == 3.0f64 {
        if dow == 0.0f64 { ret f.number(6.0f64) }
        ret f.number(dow - 1.0f64)
    }
    ret f.number(dow + 1.0f64)
}

fn h_weeknum(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let p = parts_of(ms)
    let start = date_utc(p.year, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
    let days = math.floor[f64]((ms - start) / day_ms())
    ret f.number(math.floor[f64]((days + parts_of(start).weekday) / 7.0f64) + 1.0f64)
}

fn h_isoweeknum(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    ret f.number(iso_week_number(ms))
}

fn h_dateadd(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let amount = f.to_number(c.a, c.args[1usize])
    if f.is_error(amount) { ret amount }
    var n = 0.0f64
    if amount.kind != .Blank { n = math.trunc[f64](amount.n) }
    let raw = unit_text(c.a, c.args[2usize])
    let unit = normalize_unit(c.a, raw)
    if unit == 0u8 {
        // the message interpolates the value itself, where a null reads "null"
        var shown = raw
        if c.args[2usize].kind == .Blank { shown = "null" }
        ret f.value_error(f.join3(c.a, "Unknown DATEADD unit \"", shown, "\""))
    }
    ret f.date(add_unit(ms, n, unit))
}

fn diff_ymd(a: f64, b: f64) -> (f64, f64, f64) {
    let pa = parts_of(a)
    let pb = parts_of(b)
    var years = pb.year - pa.year
    var months = pb.month - pa.month
    var days = pb.day - pa.day
    if days < 0.0f64 {
        months -= 1.0f64
        let prev = parts_of(date_utc_raw(pb.year, pb.month, 0.0f64))
        days += prev.day
    }
    if months < 0.0f64 {
        years -= 1.0f64
        months += 12.0f64
    }
    ret (years, months, days)
}

fn h_datedif(c: *f.Call) -> f.Value {
    let (a_ms, a_early, a_valid) = as_date(c, 0usize)
    let (b_ms, b_early, b_valid) = as_date(c, 1usize)
    if f.is_error(a_early) { ret a_early }
    if f.is_error(b_early) { ret b_early }
    if !a_valid || !b_valid { ret f.blank() }
    let unit_value = f.to_text(c.a, c.args[2usize])
    var unit = ""
    if f.is_error(unit_value) { unit = f.code_text(unit_value.code) } else { unit = unit_value.s }
    unit = upper_ascii(c.a, unit)
    if b_ms < a_ms { ret f.num_error("DATEDIF end date is before start date") }
    let (years, months, days) = diff_ymd(a_ms, b_ms)
    if str.eq(unit, "Y") { ret f.number(years) }
    if str.eq(unit, "M") { ret f.number(years * 12.0f64 + months) }
    if str.eq(unit, "D") { ret f.number(math.floor[f64]((b_ms - a_ms) / day_ms())) }
    if str.eq(unit, "MD") { ret f.number(days) }
    if str.eq(unit, "YM") { ret f.number(months) }
    if str.eq(unit, "YD") {
        let pa = parts_of(a_ms)
        let pb = parts_of(b_ms)
        let anchor = date_utc(pb.year, pa.month, pa.day, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
        var base = anchor
        if anchor > b_ms { base = date_utc(pb.year - 1.0f64, pa.month, pa.day, 0.0f64, 0.0f64, 0.0f64, 0.0f64) }
        ret f.number(math.floor[f64]((b_ms - base) / day_ms()))
    }
    ret f.value_error(f.join3(c.a, "Unknown DATEDIF unit \"", unit, "\""))
}

fn h_datetime_diff(c: *f.Call) -> f.Value {
    let (a_ms, a_early, a_valid) = as_date(c, 0usize)
    let (b_ms, b_early, b_valid) = as_date(c, 1usize)
    if f.is_error(a_early) { ret a_early }
    if f.is_error(b_early) { ret b_early }
    if !a_valid || !b_valid { ret f.blank() }
    var raw = "day"
    if c.args.len > 2usize {
        let t = f.to_text(c.a, c.args[2usize])
        if f.is_error(t) { raw = f.code_text(t.code) } else { raw = t.s }
    }
    var shown = raw
    var for_unit = raw
    if raw.len == 0usize { for_unit = "day" }
    let unit = normalize_unit(c.a, for_unit)
    let ms = a_ms - b_ms
    if unit == 9u8 { ret f.number(ms) }
    if unit == 8u8 { ret f.number(math.trunc[f64](ms / 1000.0f64)) }
    if unit == 7u8 { ret f.number(math.trunc[f64](ms / 60000.0f64)) }
    if unit == 6u8 { ret f.number(math.trunc[f64](ms / 3600000.0f64)) }
    if unit == 5u8 { ret f.number(math.trunc[f64](ms / day_ms())) }
    if unit == 4u8 { ret f.number(math.trunc[f64](ms / (7.0f64 * day_ms()))) }
    if unit == 3u8 { ret f.number(elapsed_months(b_ms, a_ms)) }
    if unit == 2u8 { ret f.number(math.trunc[f64](elapsed_months(b_ms, a_ms) / 3.0f64)) }
    if unit == 1u8 { ret f.number(math.trunc[f64](elapsed_months(b_ms, a_ms) / 12.0f64)) }
    ret f.value_error(f.join3(c.a, "Unknown diff unit \"", shown, "\""))
}

fn h_days(c: *f.Call) -> f.Value {
    let (e_ms, e_early, e_valid) = as_date(c, 0usize)
    let (s_ms, s_early, s_valid) = as_date(c, 1usize)
    if f.is_error(e_early) { ret e_early }
    if f.is_error(s_early) { ret s_early }
    if !e_valid || !s_valid { ret f.blank() }
    ret f.number(js_round((e_ms - s_ms) / day_ms()))
}

fn h_datevalue(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    ret f.date(utc_midnight(ms))
}

fn h_timevalue(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let p = parts_of(ms)
    ret f.date(date_utc(1970.0f64, 0.0f64, 1.0f64, p.hour, p.minute, p.second, 0.0f64))
}

fn h_edate(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let months = f.to_number(c.a, c.args[1usize])
    if f.is_error(months) { ret months }
    var n = 0.0f64
    if months.kind != .Blank { n = math.trunc[f64](months.n) }
    ret f.date(add_unit(ms, n, 3u8))
}

fn h_eomonth(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let months = f.to_number(c.a, c.args[1usize])
    if f.is_error(months) { ret months }
    var n = 0.0f64
    if months.kind != .Blank { n = math.trunc[f64](months.n) }
    let moved = add_unit(ms, n, 3u8)
    if !finite(moved) { ret f.date(moved) }
    let p = parts_of(moved)
    ret f.date(date_utc_raw(p.year, p.month + 1.0f64, 0.0f64))
}

// The holiday dates (UTC midnights) of an optional argument.
fn holiday_list(c: *f.Call, index: usize, out: []f64) -> usize {
    if index >= c.args.len { ret 0usize }
    let arg = c.args[index]
    if arg.kind == .Blank { ret 0usize }
    var n = 0usize
    if arg.kind == .Array {
        var i = 0usize
        while i < arg.items.len && n < out.len {
            let d = f.to_date(c.a, arg.items[i])
            if d.kind == .Date && finite(d.n) {
                out[n] = utc_midnight(d.n)
                n += 1usize
            }
            i += 1usize
        }
    } else {
        let d = f.to_date(c.a, arg)
        if d.kind == .Date && finite(d.n) {
            out[0usize] = utc_midnight(d.n)
            n = 1usize
        }
    }
    ret n
}

fn is_holiday(list: []const f64, count: usize, t: f64) -> bool {
    var i = 0usize
    while i < count {
        if list[i] == t { ret true }
        i += 1usize
    }
    ret false
}

fn h_networkdays(c: *f.Call) -> f.Value {
    let (s_ms, s_early, s_valid) = as_date(c, 0usize)
    let (e_ms, e_early, e_valid) = as_date(c, 1usize)
    if f.is_error(s_early) { ret s_early }
    if f.is_error(e_early) { ret e_early }
    if !s_valid || !e_valid { ret f.blank() }
    var holidays: [64]f64 = zero
    let hn = holiday_list(c, 2usize, holidays[0..])
    var count = 0.0f64
    var forward = e_ms >= s_ms
    var cur = 0.0f64
    var last = 0.0f64
    if forward {
        cur = utc_midnight(s_ms)
        last = utc_midnight(e_ms)
    } else {
        cur = utc_midnight(e_ms)
        last = utc_midnight(s_ms)
    }
    while cur <= last {
        let dow = parts_of(cur).weekday
        if dow != 0.0f64 && dow != 6.0f64 && !is_holiday(holidays[0..], hn, cur) { count += 1.0f64 }
        cur += day_ms()
    }
    if forward { ret f.number(count) }
    ret f.number(0.0f64 - count)
}

fn h_workday(c: *f.Call) -> f.Value {
    let (s_ms, s_early, s_valid) = as_date(c, 0usize)
    if f.is_error(s_early) { ret s_early }
    if !s_valid { ret f.blank() }
    let days = f.to_number(c.a, c.args[1usize])
    if f.is_error(days) { ret days }
    var holidays: [64]f64 = zero
    let hn = holiday_list(c, 2usize, holidays[0..])
    var remaining = 0.0f64
    if days.kind != .Blank { remaining = math.trunc[f64](days.n) }
    var step = day_ms()
    if remaining < 0.0f64 { step = 0.0f64 - day_ms() }
    remaining = abs_f(remaining)
    if remaining > 10000000.0f64 { ret f.generic_error("WORKDAY count is too large") }
    var cur = utc_midnight(s_ms)
    while remaining > 0.0f64 {
        cur += step
        let dow = parts_of(cur).weekday
        if dow != 0.0f64 && dow != 6.0f64 && !is_holiday(holidays[0..], hn, cur) { remaining -= 1.0f64 }
    }
    ret f.date(cur)
}

fn h_yearfrac(c: *f.Call) -> f.Value {
    let (a_ms, a_early, a_valid) = as_date(c, 0usize)
    let (b_ms, b_early, b_valid) = as_date(c, 1usize)
    if f.is_error(a_early) { ret a_early }
    if f.is_error(b_early) { ret b_early }
    if !a_valid || !b_valid { ret f.blank() }
    var basis = 0.0f64
    if c.args.len > 2usize { basis = math.trunc[f64](num_or(c, 2usize, 0.0f64)) }
    var start = a_ms
    var end = b_ms
    if a_ms > b_ms {
        start = b_ms
        end = a_ms
    }
    if basis == 3.0f64 { ret f.number((end - start) / day_ms() / 365.0f64) }
    if basis == 1.0f64 { ret f.number((end - start) / day_ms() / 365.25f64) }
    let ps = parts_of(start)
    let pe = parts_of(end)
    let d360 = (pe.year - ps.year) * 360.0f64 + (pe.month - ps.month) * 30.0f64 + (math.min[f64](pe.day, 30.0f64) - math.min[f64](ps.day, 30.0f64))
    ret f.number(d360 / 360.0f64)
}

// ADD_DAYS (day_ms, +1), SUBTRACT_DAYS, ADD_MINUTES, SUBTRACT_MINUTES.
fn shift_by(c: *f.Call, unit_ms: f64, direction: f64) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let n = f.to_number(c.a, c.args[1usize])
    if f.is_error(n) { ret n }
    var v = 0.0f64
    if n.kind != .Blank { v = n.n }
    ret f.date(time_clip(ms + direction * v * unit_ms))
}

fn h_add_days(c: *f.Call) -> f.Value { ret shift_by(c, day_ms(), 1.0f64) }

fn h_subtract_days(c: *f.Call) -> f.Value { ret shift_by(c, day_ms(), -1.0f64) }

fn h_add_minutes(c: *f.Call) -> f.Value { ret shift_by(c, 60000.0f64, 1.0f64) }

fn h_subtract_minutes(c: *f.Call) -> f.Value { ret shift_by(c, 60000.0f64, -1.0f64) }

fn h_datetime_add(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let count = f.to_number(c.a, c.args[1usize])
    if f.is_error(count) { ret count }
    let unit_value = f.to_text(c.a, c.args[2usize])
    if f.is_error(unit_value) { ret unit_value }
    var n = 0.0f64
    if count.kind != .Blank { n = count.n }
    let unit = normalize_unit(c.a, unit_value.s)
    if unit == 1u8 { ret f.date(add_unit(ms, n, 1u8)) }
    if unit == 2u8 { ret f.date(add_months_clamped(ms, n * 3.0f64)) }
    if unit == 3u8 { ret f.date(add_months_clamped(ms, n)) }
    if unit == 4u8 { ret f.date(time_clip(ms + n * 7.0f64 * day_ms())) }
    if unit == 5u8 { ret f.date(time_clip(ms + n * day_ms())) }
    if unit == 6u8 { ret f.date(time_clip(ms + n * 3600000.0f64)) }
    if unit == 7u8 { ret f.date(time_clip(ms + n * 60000.0f64)) }
    if unit == 8u8 { ret f.date(time_clip(ms + n * 1000.0f64)) }
    if unit == 9u8 { ret f.date(time_clip(ms + n)) }
    ret f.value_error(f.join(c.a, "Unknown unit: ", unit_value.s))
}

// FIRSTDAYOFMONTH, LASTDAYOFMONTH, EOWEEK, EWOMONTH.
fn boundary(c: *f.Call, what: u8) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let p = parts_of(ms)
    if what == 0u8 { ret f.date(date_utc_raw(p.year, p.month, 1.0f64)) }
    if what == 1u8 { ret f.date(date_utc_raw(p.year, p.month + 1.0f64, 0.0f64)) }
    if what == 2u8 {
        let end = utc_midnight(ms)
        ret f.date(time_clip(end + (6.0f64 - p.weekday) * day_ms()))
    }
    let last = date_utc_raw(p.year, p.month + 1.0f64, 0.0f64)
    let lw = parts_of(last).weekday
    ret f.date(time_clip(last + (6.0f64 - lw) * day_ms()))
}

fn h_firstdayofmonth(c: *f.Call) -> f.Value { ret boundary(c, 0u8) }

fn h_lastdayofmonth(c: *f.Call) -> f.Value { ret boundary(c, 1u8) }

fn h_eoweek(c: *f.Call) -> f.Value { ret boundary(c, 2u8) }

fn h_ewomonth(c: *f.Call) -> f.Value { ret boundary(c, 3u8) }

fn h_dayofyear(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let p = parts_of(ms)
    let start = date_utc(p.year, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
    ret f.number(math.floor[f64]((utc_midnight(ms) - start) / day_ms()) + 1.0f64)
}

// DAYSSINCE (sign 1) and DAYSREMAINING (sign -1).
fn since_now(c: *f.Call, sign: f64) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let diff = utc_midnight(clock_now(c)) - utc_midnight(ms)
    ret f.number(sign * math.floor[f64](diff / day_ms()))
}

fn h_dayssince(c: *f.Call) -> f.Value { ret since_now(c, 1.0f64) }

fn h_daysremaining(c: *f.Call) -> f.Value { ret since_now(c, -1.0f64) }

fn h_hours_diff(c: *f.Call) -> f.Value {
    let (a_ms, a_early, a_valid) = as_date(c, 0usize)
    let (b_ms, b_early, b_valid) = as_date(c, 1usize)
    if f.is_error(a_early) { ret a_early }
    if f.is_error(b_early) { ret b_early }
    if !a_valid || !b_valid { ret f.blank() }
    ret f.number((b_ms - a_ms) / 3600000.0f64)
}

fn total_of(c: *f.Call, unit_ms: f64) -> f.Value {
    if c.args.len == 2usize {
        let (a_ms, a_early, a_valid) = as_date(c, 0usize)
        let (b_ms, b_early, b_valid) = as_date(c, 1usize)
        if f.is_error(a_early) { ret a_early }
        if f.is_error(b_early) { ret b_early }
        if !a_valid || !b_valid { ret f.blank() }
        ret f.number((b_ms - a_ms) / unit_ms)
    }
    let n = f.to_number(c.a, c.args[0usize])
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    ret f.number(n.n / unit_ms)
}

fn h_totalhours(c: *f.Call) -> f.Value { ret total_of(c, 3600000.0f64) }

fn h_totalminutes(c: *f.Call) -> f.Value { ret total_of(c, 60000.0f64) }

fn h_is_before(c: *f.Call) -> f.Value {
    let (a_ms, a_early, a_valid) = as_date(c, 0usize)
    let (b_ms, b_early, b_valid) = as_date(c, 1usize)
    if f.is_error(a_early) { ret a_early }
    if f.is_error(b_early) { ret b_early }
    if !a_valid || !b_valid { ret f.blank() }
    ret f.boolean(a_ms < b_ms)
}

fn h_is_after(c: *f.Call) -> f.Value {
    let (a_ms, a_early, a_valid) = as_date(c, 0usize)
    let (b_ms, b_early, b_valid) = as_date(c, 1usize)
    if f.is_error(a_early) { ret a_early }
    if f.is_error(b_early) { ret b_early }
    if !a_valid || !b_valid { ret f.blank() }
    ret f.boolean(a_ms > b_ms)
}

fn h_dateonly(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    ret f.date(utc_midnight(ms))
}

fn h_datestr(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    ret f.text(format_date(c.a, ms, "YYYY-MM-DD"))
}

fn h_timestr(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    ret f.text(format_date(c.a, ms, "HH:mm:ss"))
}

fn h_totimestamp(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    ret f.number(math.floor[f64](ms / 1000.0f64))
}

fn h_fromtimestamp(c: *f.Call) -> f.Value {
    let n = f.to_number(c.a, c.args[0usize])
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.blank() }
    var ms = n.n * 1000.0f64
    if abs_f(n.n) > 100000000000.0f64 { ms = n.n }
    ret f.date(time_clip(ms))
}

fn h_datetime_parse(c: *f.Call) -> f.Value {
    let t = f.to_text(c.a, c.args[0usize])
    if f.is_error(t) { ret t }
    if str.trim(t.s).len == 0usize { ret f.blank() }
    let parsed = f.to_date(c.a, t)
    if f.is_error(parsed) || parsed.kind != .Date { ret f.value_error(f.join(c.a, "Could not read a date from: ", t.s)) }
    ret parsed
}

fn plural(a: *mem.Arena, count: f64, name: str) -> str {
    var s = ""
    if count != 1.0f64 { s = "s" }
    ret f.join(a, f.join3(a, f.number_text(a, count), " ", name), s)
}

// The relative wording of the Date field: up to three units, `in ...` for the future and `... ago` for the past.
fn relative_text(a: *mem.Arena, value_ms: f64, now_ms: f64) -> str {
    let delta = js_round((now_ms - value_ms) / 1000.0f64)
    let future = delta < 0.0f64
    var remaining = abs_f(delta)
    if remaining < 1.0f64 { ret "just now" }
    var parts = ""
    var count_parts = 0usize
    var unit = 0usize
    while unit < 6usize && count_parts < 3usize {
        var seconds = 31536000.0f64
        var name = "year"
        if unit == 1usize {
            seconds = 2592000.0f64
            name = "month"
        }
        if unit == 2usize {
            seconds = 86400.0f64
            name = "day"
        }
        if unit == 3usize {
            seconds = 3600.0f64
            name = "hour"
        }
        if unit == 4usize {
            seconds = 60.0f64
            name = "minute"
        }
        if unit == 5usize {
            seconds = 1.0f64
            name = "second"
        }
        let count = math.floor[f64](remaining / seconds)
        if count > 0.0f64 {
            if count_parts > 0usize { parts = f.join(a, parts, ", ") }
            parts = f.join(a, parts, plural(a, count, name))
            count_parts += 1usize
            remaining -= count * seconds
        }
        unit += 1usize
    }
    if future { ret f.join(a, "in ", parts) }
    ret f.join(a, parts, " ago")
}

fn h_fromnow(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    ret f.text(relative_text(c.a, ms, clock_now(c)))
}

fn h_daterange(c: *f.Call) -> f.Value {
    let (s_ms, s_early, s_valid) = as_date(c, 0usize)
    if f.is_error(s_early) { ret s_early }
    var e_ms = s_ms
    var e_valid = s_valid
    if c.args.len > 1usize {
        let (m, early, valid) = as_date(c, 1usize)
        if f.is_error(early) { ret early }
        e_ms = m
        e_valid = valid
    }
    if !s_valid && !e_valid { ret f.blank() }
    var first = ""
    var second = ""
    var lo_valid = s_valid
    var hi_valid = e_valid
    var lo = s_ms
    var hi = e_ms
    if s_valid && e_valid && e_ms < s_ms {
        lo = e_ms
        hi = s_ms
    }
    if lo_valid { first = format_date(c.a, lo, "YYYY-MM-DD") }
    if hi_valid { second = format_date(c.a, hi, "YYYY-MM-DD") }
    let (items, e) = mem.alloc[f.Value](c.a, 2usize)
    if e != ok { ret f.generic_error("Out of memory") }
    items[0usize] = f.text(first)
    items[1usize] = f.text(second)
    ret f.record(items)
}

fn offset_zone_seconds(name: str) -> (i64, bool) {
    // +HH:MM, +HHMM, +HH
    if name.len < 3usize { ret (0i64, false) }
    if name[0usize] != 43u8 && name[0usize] != 45u8 { ret (0i64, false) }
    var digits: [4]u8 = zero
    var n = 0usize
    var i = 1usize
    while i < name.len {
        let b = name[i]
        if b >= 48u8 && b <= 57u8 {
            if n >= 4usize { ret (0i64, false) }
            digits[n] = b - 48u8
            n += 1usize
        } else if b == 58u8 && n == 2usize {
            i += 0usize
        } else {
            ret (0i64, false)
        }
        i += 1usize
    }
    if n != 2usize && n != 4usize { ret (0i64, false) }
    var hours = i64(digits[0usize]) * 10i64 + i64(digits[1usize])
    var minutes = 0i64
    if n == 4usize { minutes = i64(digits[2usize]) * 10i64 + i64(digits[3usize]) }
    if hours > 23i64 || minutes > 59i64 { ret (0i64, false) }
    var total = hours * 3600i64 + minutes * 60i64
    if name[0usize] == 45u8 { total = 0i64 - total }
    ret (total, true)
}

fn h_set_timezone(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let zone_value = f.to_text(c.a, c.args[1usize])
    if f.is_error(zone_value) { ret zone_value }
    let name = zone_value.s
    let lowered = f.lower_text(c.a, name)
    if str.eq(lowered, "utc") || str.eq(lowered, "gmt") || str.eq(lowered, "etc/utc") || str.eq(lowered, "etc/gmt") {
        ret f.date(ms)
    }
    let (seconds, is_offset) = offset_zone_seconds(name)
    if is_offset { ret f.date(time_clip(ms + f64(seconds) * 1000.0f64)) }
    let (db, db_error) = tz.builtin(c.a)
    if db_error == ok {
        let (zone, zone_error) = tz.zone(&db, name)
        if zone_error == ok {
            let instant = time.Timestamp { nanos: i64(ms) * 1000000i64 }
            let local = tz.to_local(zone, instant)
            ret f.date(date_utc(f64(local.date.year), f64(local.date.month) - 1.0f64, f64(local.date.day), f64(local.time.hour), f64(local.time.minute), f64(local.time.second), f64(local.time.nanos / 1000000u32)))
        }
    }
    ret f.value_error(f.join(c.a, "Unknown time zone: ", name))
}

fn h_set_locale(c: *f.Call) -> f.Value {
    let (ms, early, valid) = as_date(c, 0usize)
    if f.is_error(early) { ret early }
    if !valid { ret f.blank() }
    let locale = f.to_text(c.a, c.args[1usize])
    if f.is_error(locale) { ret locale }
    ret f.text(format_date(c.a, ms, "MMMM D, YYYY"))
}

// --- registration -------------------------------------------------------------------------------------------------------

fn add(r: *f.Registry, a: *mem.Arena, name: str, aliases: []const str, volatile_fn: bool, low: i32, high: i32, handler: f.Handler) -> err {
    ret f.register(r, a, f.Entry { name: name, key: "", aliases: aliases, category: "datetime", lazy: false, pass_errors: false, volatile_fn: volatile_fn, generate_once: false, min_args: low, max_args: high, handler: handler })
}

fn al1(a: *mem.Arena, x: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 1usize)
    s[0usize] = x
    ret s
}

fn al2(a: *mem.Arena, x: str, y: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 2usize)
    s[0usize] = x
    s[1usize] = y
    ret s
}

// Register the date and time functions.
fn register(r: *f.Registry, a: *mem.Arena) -> err {
    var none: []const str = zero
    try add(r, a, "DATE", none, false, 3i32, 3i32, h_date)
    try add(r, a, "TIME", none, false, 3i32, 3i32, h_time)
    try add(r, a, "NOW", none, true, 0i32, 0i32, h_now)
    try add(r, a, "TODAY", none, true, 0i32, 0i32, h_today)
    try add(r, a, "YEAR", none, false, 1i32, 1i32, h_year)
    try add(r, a, "MONTH", none, false, 1i32, 1i32, h_month)
    try add(r, a, "DAY", none, false, 1i32, 1i32, h_day)
    try add(r, a, "HOUR", none, false, 1i32, 1i32, h_hour)
    try add(r, a, "MINUTE", none, false, 1i32, 1i32, h_minute)
    try add(r, a, "SECOND", none, false, 1i32, 1i32, h_second)
    try add(r, a, "CENTURY", none, false, 1i32, 1i32, h_century)
    try add(r, a, "WEEKDAY", none, false, 1i32, 2i32, h_weekday)
    try add(r, a, "WEEKNUM", none, false, 1i32, 2i32, h_weeknum)
    try add(r, a, "ISOWEEKNUM", none, false, 1i32, 1i32, h_isoweeknum)
    try add(r, a, "DATEADD", none, false, 3i32, 3i32, h_dateadd)
    try add(r, a, "DATEDIF", none, false, 3i32, 3i32, h_datedif)
    try add(r, a, "DATETIME_DIFF", al2(a, "DATETIME_DIF", "DATETIMEDIFF"), false, 2i32, 3i32, h_datetime_diff)
    try add(r, a, "DAYS", none, false, 2i32, 2i32, h_days)
    try add(r, a, "DATEVALUE", none, false, 1i32, 1i32, h_datevalue)
    try add(r, a, "TIMEVALUE", none, false, 1i32, 1i32, h_timevalue)
    try add(r, a, "EDATE", none, false, 2i32, 2i32, h_edate)
    try add(r, a, "EOMONTH", none, false, 2i32, 2i32, h_eomonth)
    try add(r, a, "NETWORKDAYS", none, false, 2i32, 3i32, h_networkdays)
    try add(r, a, "WORKDAY", none, false, 2i32, 3i32, h_workday)
    try add(r, a, "YEARFRAC", none, false, 2i32, 3i32, h_yearfrac)
    try add(r, a, "ADD_DAYS", none, false, 2i32, 2i32, h_add_days)
    try add(r, a, "SUBTRACT_DAYS", none, false, 2i32, 2i32, h_subtract_days)
    try add(r, a, "ADD_MINUTES", none, false, 2i32, 2i32, h_add_minutes)
    try add(r, a, "SUBTRACT_MINUTES", none, false, 2i32, 2i32, h_subtract_minutes)
    try add(r, a, "DATETIME_ADD", none, false, 3i32, 3i32, h_datetime_add)
    try add(r, a, "FIRSTDAYOFMONTH", none, false, 1i32, 1i32, h_firstdayofmonth)
    try add(r, a, "LASTDAYOFMONTH", none, false, 1i32, 1i32, h_lastdayofmonth)
    try add(r, a, "EOWEEK", none, false, 1i32, 1i32, h_eoweek)
    try add(r, a, "EWOMONTH", none, false, 1i32, 1i32, h_ewomonth)
    try add(r, a, "DAYOFYEAR", none, false, 1i32, 1i32, h_dayofyear)
    try add(r, a, "DAYSSINCE", none, true, 1i32, 1i32, h_dayssince)
    try add(r, a, "DAYSREMAINING", none, true, 1i32, 1i32, h_daysremaining)
    try add(r, a, "HOURS_DIFF", none, false, 2i32, 2i32, h_hours_diff)
    try add(r, a, "TOTALHOURS", none, false, 1i32, 2i32, h_totalhours)
    try add(r, a, "TOTALMINUTES", none, false, 1i32, 2i32, h_totalminutes)
    try add(r, a, "IS_BEFORE", none, false, 2i32, 2i32, h_is_before)
    try add(r, a, "IS_AFTER", none, false, 2i32, 2i32, h_is_after)
    try add(r, a, "DATEONLY", none, false, 1i32, 1i32, h_dateonly)
    try add(r, a, "DATESTR", none, false, 1i32, 1i32, h_datestr)
    try add(r, a, "TIMESTR", none, false, 1i32, 1i32, h_timestr)
    try add(r, a, "TOTIMESTAMP", al1(a, "TIMESTAMP"), false, 1i32, 1i32, h_totimestamp)
    try add(r, a, "FROMTIMESTAMP", none, false, 1i32, 1i32, h_fromtimestamp)
    try add(r, a, "DATETIME_PARSE", al1(a, "DATETIMEPARSE"), false, 1i32, 2i32, h_datetime_parse)
    try add(r, a, "FROMNOW", none, true, 1i32, 1i32, h_fromnow)
    try add(r, a, "TONOW", none, true, 1i32, 1i32, h_fromnow)
    try add(r, a, "UTCNOW", none, true, 0i32, 0i32, h_now)
    try add(r, a, "NETWORKDAY", none, false, 2i32, 3i32, h_networkdays)
    try add(r, a, "WORKDAYS", none, false, 2i32, 3i32, h_networkdays)
    try add(r, a, "WORKDAY_DIFF", none, false, 2i32, 3i32, h_networkdays)
    try add(r, a, "WORKDAYADD", none, false, 2i32, 3i32, h_workday)
    try add(r, a, "DATERANGE", none, false, 1i32, 2i32, h_daterange)
    try add(r, a, "SET_TIMEZONE", al1(a, "SETTIMEZONE"), false, 2i32, 2i32, h_set_timezone)
    try add(r, a, "SET_LOCALE", al1(a, "SETLOCALE"), false, 2i32, 2i32, h_set_locale)
    ret ok
}
