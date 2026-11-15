// R's readr parsers, value for value: `parse_number` (grouping and decimal marks), `parse_double`,
// `parse_integer`, `parse_logical`, `parse_date`, `parse_time` and `parse_datetime` (readr's
// format language: %Y %y %m %b %B %d %e %H %I %M %S %OS %p %z %Z %. %+ %* %AD %AT %D %F %R %T
// %x %X, English month names) and `read_delim`'s field splitting (delimiter, quote, doubled and
// backslash escapes, comment character, whitespace trimming, empty rows). A failed parse is NaN
// (NA). Dates answer days since 1970-01-01, times seconds, datetimes seconds since the epoch (UTC).
//
// Not here: `guess_parser`, locales other than English, time zones other than UTC and the
// offsets %z gives, `%a` and the type conversion of whole columns.

use e.math
use e.mem
use e.str

error Unsupported

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn is_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

fn trim(s: str) -> str {
    var a = 0usize
    var b = s.len
    while a < b && (s[a] == 32u8 || s[a] == 9u8) { a += 1usize }
    while b > a && (s[b - 1usize] == 32u8 || s[b - 1usize] == 9u8) { b -= 1usize }
    ret s[a..b]
}

// --- parse_number

// The value of the number at the start of s and the position where reading stopped.
fn scan_number(s: str, decimal: u8, grouping: u8) -> (f64, usize) {
    var cur = 0usize
    while cur < s.len {
        let c = s[cur]
        if c == 45u8 || c == decimal || is_digit(c) { break }
        cur += 1usize
    }
    if cur == s.len { ret (nan(), cur) }
    var sum = 0.0f64
    var denom = 1.0f64
    var exponent = 0.0f64
    var state = 0u8
    var seen = false
    var exp_init = true
    var sign = 1.0f64
    var exp_sign = 1.0f64
    while cur < s.len {
        let c = s[cur]
        var stop = false
        if state == 0u8 {
            if c == 45u8 {
                state = 1u8
                sign = -1.0f64
            } else if c == decimal {
                state = 2u8
            } else if is_digit(c) {
                seen = true
                state = 1u8
                sum = f64(c - 48u8)
            } else {
                stop = true
            }
        } else if state == 1u8 {
            if c == grouping {
            } else if c == decimal {
                state = 2u8
            } else if seen && (c == 101u8 || c == 69u8) {
                state = 3u8
            } else if is_digit(c) {
                seen = true
                sum = sum * 10.0f64 + f64(c - 48u8)
            } else {
                stop = true
            }
        } else if state == 2u8 {
            if c == grouping {
            } else if seen && (c == 101u8 || c == 69u8) {
                state = 3u8
            } else if is_digit(c) {
                seen = true
                denom = denom * 10.0f64
                sum = sum + f64(c - 48u8) / denom
            } else {
                stop = true
            }
        } else {
            if c == 45u8 && exp_init {
                exp_sign = -1.0f64
                exp_init = false
            } else if c == 43u8 && exp_init {
                exp_init = false
            } else if is_digit(c) {
                exponent = exponent * 10.0f64 + f64(c - 48u8)
                exp_init = false
            } else {
                stop = true
            }
        }
        if stop { break }
        cur += 1usize
    }
    if !seen { ret (nan(), cur) }
    var res = sign * sum
    if exponent != 0.0f64 { res = res * math.pow[f64](10.0f64, exp_sign * exponent) }
    ret (res, cur)
}

fn parse_number(s: str, decimal: u8, grouping: u8) -> f64 {
    let (v, end) = scan_number(s, decimal, grouping)
    ret v
}

// --- parse_double: digits, one decimal mark, an optional exponent (e E s S f F d D l L).

fn parse_double(a: *mem.Arena, s0: str, decimal: u8) -> f64 {
    let s = trim(s0)
    if s.len == 0usize { ret nan() }
    let (initial, e) = str.builder(a, s.len + 16usize)
    if e != ok { ret nan() }
    var b = initial
    var i = 0usize
    if s[i] == 45u8 {
        let _ = str.push_byte(&b, 45u8)
        i += 1usize
    } else if s[i] == 43u8 {
        i += 1usize
    }
    var digits = 0usize
    var frac = 0i64
    var seen_point = false
    var bad = false
    while i < s.len && (is_digit(s[i]) || (s[i] == decimal && !seen_point)) {
        if s[i] == decimal {
            seen_point = true
        } else {
            digits += 1usize
            if seen_point { frac += 1i64 }
            let _ = str.push_byte(&b, s[i])
        }
        i += 1usize
    }
    if digits == 0usize { bad = true }
    var expon = 0i64
    if !bad && i < s.len {
        let c = s[i]
        if c == 101u8 || c == 69u8 || c == 115u8 || c == 83u8 || c == 102u8 || c == 70u8 || c == 100u8 || c == 68u8 || c == 108u8 || c == 76u8 {
            i += 1usize
            var esign = 1i64
            var signed = false
            if i < s.len && (s[i] == 45u8 || s[i] == 43u8) {
                if s[i] == 45u8 { esign = -1i64 }
                signed = true
                i += 1usize
            }
            var ed = 0usize
            while i < s.len && is_digit(s[i]) {
                if expon < 100000i64 { expon = expon * 10i64 + i64(s[i] - 48u8) }
                ed += 1usize
                i += 1usize
            }
            if ed == 0usize && !signed { bad = true }
            expon = expon * esign
        }
    }
    // readr's bsd_strtod clamps the decimal exponent of the digit string to [-307, 307].
    var total = expon - frac
    if total < -307i64 { total = -307i64 }
    if total > 307i64 { total = 307i64 }
    let _ = str.push_byte(&b, 101u8)
    let _ = str.push_i64(&b, total)
    let text = str.done(&b)
    if bad || i != s.len { ret nan() }
    let (v, pe) = str.parse_f64(text)
    if pe != ok { ret nan() }
    ret v
}

fn parse_integer(s0: str) -> f64 {
    let s = trim(s0)
    if s.len == 0usize { ret nan() }
    var i = 0usize
    var neg = false
    if s[0usize] == 45u8 {
        neg = true
        i = 1usize
    } else if s[0usize] == 43u8 {
        i = 1usize
    }
    if i >= s.len { ret nan() }
    var v = 0i64
    while i < s.len {
        if !is_digit(s[i]) { ret nan() }
        v = v * 10i64 + i64(s[i] - 48u8)
        if v > 2147483647i64 { ret nan() }
        i += 1usize
    }
    if neg { ret f64(0i64 - v) }
    ret f64(v)
}

// parse_logical: 1 true, 0 false, NaN neither.
fn parse_logical(s0: str) -> f64 {
    let s = trim(s0)
    if str.eq(s, "TRUE") || str.eq(s, "T") || str.eq(s, "true") || str.eq(s, "True") || str.eq(s, "t") || str.eq(s, "1") { ret 1.0f64 }
    if str.eq(s, "FALSE") || str.eq(s, "F") || str.eq(s, "false") || str.eq(s, "False") || str.eq(s, "f") || str.eq(s, "0") { ret 0.0f64 }
    ret nan()
}

// --- Dates and times.

type Parser = struct { s: str, at: usize, year: i64, mon: i64, day: i64, hour: i64, min: i64, sec: i64, psec: f64, ampm: i64, tzh: i64, tzm: i64, sign: i64, utc: bool, compact: bool, names: str }

fn new_parser(s: str) -> Parser {
    ret Parser { s: s, at: 0usize, year: -1i64, mon: 1i64, day: 1i64, hour: 0i64, min: 0i64, sec: 0i64, psec: 0.0f64, ampm: -1i64, tzh: 0i64, tzm: 0i64, sign: 1i64, utc: false, compact: true, names: "" }
}

fn done(p: *Parser) -> bool { ret p.at >= p.s.len }

fn skip_space(p: *Parser) {
    while p.at < p.s.len && is_space(p.s[p.at]) { p.at += 1usize }
}

fn eat(p: *Parser, c: u8) -> bool {
    if p.at < p.s.len && p.s[p.at] == c {
        p.at += 1usize
        ret true
    }
    ret false
}

// consumeInteger(n, exact): up to n digits, no sign.
fn take_int(p: *Parser, n: usize, exact: bool) -> (i64, bool) {
    if p.at >= p.s.len || p.s[p.at] == 45u8 || p.s[p.at] == 43u8 { ret (0i64, false) }
    var v = 0i64
    var k = 0usize
    while k < n && p.at + k < p.s.len && is_digit(p.s[p.at + k]) {
        v = v * 10i64 + i64(p.s[p.at + k] - 48u8)
        k += 1usize
    }
    p.at += k
    if exact && k != n { ret (v, false) }
    ret (v, true)
}

fn take_seconds(p: *Parser) -> (i64, f64, bool) {
    if p.at >= p.s.len || p.s[p.at] == 45u8 || p.s[p.at] == 43u8 { ret (0i64, 0.0f64, false) }
    var whole = 0i64
    var k = 0usize
    while p.at + k < p.s.len && is_digit(p.s[p.at + k]) {
        whole = whole * 10i64 + i64(p.s[p.at + k] - 48u8)
        k += 1usize
    }
    if k == 0usize { ret (0i64, 0.0f64, false) }
    var frac = 0.0f64
    if p.at + k < p.s.len && p.s[p.at + k] == 46u8 {
        var scale = 0.1f64
        var j = k + 1usize
        while p.at + j < p.s.len && is_digit(p.s[p.at + j]) {
            frac = frac + f64(p.s[p.at + j] - 48u8) * scale
            scale = scale / 10.0f64
            j += 1usize
        }
        k = j
    }
    p.at += k
    ret (whole, frac, true)
}

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn starts_with_ci(s: str, at: usize, word: str) -> bool {
    if at + word.len > s.len { ret false }
    var i = 0usize
    while i < word.len {
        if lower(s[at + i]) != lower(word[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn month_word(i: usize, full: bool) -> str {
    if i == 0usize { if full { ret "January" } else { ret "Jan" } }
    if i == 1usize { if full { ret "February" } else { ret "Feb" } }
    if i == 2usize { if full { ret "March" } else { ret "Mar" } }
    if i == 3usize { if full { ret "April" } else { ret "Apr" } }
    if i == 4usize { ret "May" }
    if i == 5usize { if full { ret "June" } else { ret "Jun" } }
    if i == 6usize { if full { ret "July" } else { ret "Jul" } }
    if i == 7usize { if full { ret "August" } else { ret "Aug" } }
    if i == 8usize { if full { ret "September" } else { ret "Sep" } }
    if i == 9usize { if full { ret "October" } else { ret "Oct" } }
    if i == 10usize { if full { ret "November" } else { ret "Nov" } }
    if full { ret "December" }
    ret "Dec"
}

// Item idx of group g in a locale's names: "months;abbreviated months;days;abbreviated days;am|pm",
// the items of a group separated by |.
fn name_item(names: str, group: usize, idx: usize) -> str {
    var g = 0usize
    var k = 0usize
    var start = 0usize
    var i = 0usize
    while i <= names.len {
        let end_of_text = i == names.len
        if end_of_text || names[i] == 59u8 || names[i] == 124u8 {
            if g == group && k == idx { ret names[start..i] }
            if !end_of_text && names[i] == 59u8 {
                g += 1usize
                k = 0usize
            } else {
                k += 1usize
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret ""
}

fn day_word(i: usize, full: bool) -> str {
    if i == 0usize { if full { ret "Sunday" } else { ret "Sun" } }
    if i == 1usize { if full { ret "Monday" } else { ret "Mon" } }
    if i == 2usize { if full { ret "Tuesday" } else { ret "Tue" } }
    if i == 3usize { if full { ret "Wednesday" } else { ret "Wed" } }
    if i == 4usize { if full { ret "Thursday" } else { ret "Thu" } }
    if i == 5usize { if full { ret "Friday" } else { ret "Fri" } }
    if full { ret "Saturday" }
    ret "Sat"
}

fn take_day(p: *Parser, full: bool) -> bool {
    var i = 0usize
    while i < 7usize {
        var w = day_word(i, full)
        if p.names.len > 0usize {
            var g = 3usize
            if full { g = 2usize }
            w = name_item(p.names, g, i)
        }
        if w.len > 0usize && starts_with_ci(p.s, p.at, w) {
            p.at += w.len
            ret true
        }
        i += 1usize
    }
    ret false
}

fn take_month(p: *Parser, full: bool) -> bool {
    var i = 0usize
    while i < 12usize {
        var w = month_word(i, full)
        if p.names.len > 0usize {
            var g = 1usize
            if full { g = 0usize }
            w = name_item(p.names, g, i)
        }
        if starts_with_ci(p.s, p.at, w) {
            p.mon = i64(i + 1usize)
            p.at += w.len
            ret true
        }
        i += 1usize
    }
    ret false
}

fn take_ampm(p: *Parser) -> bool {
    var am = "AM"
    var pm = "PM"
    if p.names.len > 0usize {
        am = name_item(p.names, 4usize, 0usize)
        pm = name_item(p.names, 4usize, 1usize)
    }
    if am.len > 0usize && starts_with_ci(p.s, p.at, am) {
        p.ampm = 1i64
        p.at += am.len
        ret true
    }
    if pm.len > 0usize && starts_with_ci(p.s, p.at, pm) {
        p.ampm = 2i64
        p.at += pm.len
        ret true
    }
    ret false
}

fn take_tz_offset(p: *Parser) -> bool {
    if eat(p, 90u8) { ret true }
    var mult = 1i64
    if p.at < p.s.len && (p.s[p.at] == 43u8 || p.s[p.at] == 45u8) {
        if p.s[p.at] == 45u8 { mult = -1i64 }
        p.at += 1usize
    }
    let (h, ok1) = take_int(p, 2usize, true)
    if !ok1 { ret false }
    let _ = eat(p, 58u8)
    let (m, ok2) = take_int(p, 2usize, true)
    p.tzh = h * mult
    p.tzm = 0i64
    if ok2 { p.tzm = m * mult }
    ret true
}

fn parse_iso(p: *Parser) -> bool {
    let (y, oy) = take_int(p, 4usize, true)
    if !oy { ret false }
    p.year = y
    if eat(p, 45u8) { p.compact = false }
    let (m, om) = take_int(p, 2usize, true)
    if !om { ret false }
    p.mon = m
    if !p.compact && !eat(p, 45u8) { ret false }
    let (d, od) = take_int(p, 2usize, true)
    if !od { ret false }
    p.day = d
    if done(p) { ret true }
    if p.at >= p.s.len { ret false }
    let next = p.s[p.at]
    p.at += 1usize
    if next != 84u8 && next != 32u8 { ret false }
    let (h, oh) = take_int(p, 2usize, true)
    if !oh { ret false }
    p.hour = h
    let _ = eat(p, 58u8)
    let (mi, omi) = take_int(p, 2usize, true)
    if omi { p.min = mi }
    let _ = eat(p, 58u8)
    let (sw, sf, os) = take_seconds(p)
    if os {
        p.sec = sw
        p.psec = sf
    }
    if done(p) { ret true }
    p.utc = true
    if !take_tz_offset(p) { ret false }
    ret done(p)
}

fn parse_date_auto(p: *Parser) -> bool {
    let (y, oy) = take_int(p, 4usize, true)
    if !oy { ret false }
    p.year = y
    if !eat(p, 45u8) && !eat(p, 47u8) { ret false }
    let (m, om) = take_int(p, 2usize, true)
    if !om { ret false }
    p.mon = m
    if !eat(p, 45u8) && !eat(p, 47u8) { ret false }
    let (d, od) = take_int(p, 2usize, true)
    if !od { ret false }
    p.day = d
    ret true
}

fn parse_time_auto(p: *Parser) -> bool {
    let (h, oh) = take_int(p, 2usize, false)
    if !oh { ret false }
    p.hour = h
    if !eat(p, 58u8) { ret false }
    let (m, om) = take_int(p, 2usize, true)
    if !om { ret false }
    p.min = m
    let _ = eat(p, 58u8)
    let (sw, sf, os) = take_seconds(p)
    if os { p.sec = sw }
    skip_space(p)
    let _ = take_ampm(p)
    skip_space(p)
    ret true
}

// %R, %T and %X: hour and minute of any width, then optional seconds.
fn parse_time_lenient(p: *Parser, seconds: bool) -> bool {
    let (h, oh) = take_int(p, 2usize, false)
    if !oh || h > 23i64 { ret false }
    p.hour = h
    if !eat(p, 58u8) { ret true }
    let (m, om) = take_int(p, 2usize, false)
    if !om { ret false }
    p.min = m
    if seconds && eat(p, 58u8) {
        let (sw, os) = take_int(p, 2usize, true)
        if !os { ret false }
        p.sec = sw
        if eat(p, 46u8) {
            while p.at < p.s.len && is_digit(p.s[p.at]) { p.at += 1usize }
        }
    }
    ret true
}

fn parse_format(p: *Parser, fmt: str) -> bool {
    if !parse_fmt(p, fmt) { ret false }
    ret done(p)
}

// The format language, recursively for %D, %F, %R, %T.
fn parse_fmt(p: *Parser, fmt: str) -> bool {
    skip_space(p)
    var i = 0usize
    while i < fmt.len {
        let c = fmt[i]
        if is_space(c) {
            skip_space(p)
            i += 1usize
        } else if c != 37u8 {
            if !eat(p, c) { ret false }
            i += 1usize
        } else {
            if i + 1usize >= fmt.len { ret false }
            let f = fmt[i + 1usize]
            i += 2usize
            if f == 89u8 {
                let (v, k) = take_int(p, 4usize, true)
                if !k { ret false }
                p.year = v
            } else if f == 121u8 {
                let (v, k) = take_int(p, 2usize, true)
                if !k { ret false }
                if v < 69i64 { p.year = v + 2000i64 } else { p.year = v + 1900i64 }
            } else if f == 109u8 {
                let (v, k) = take_int(p, 2usize, false)
                if !k { ret false }
                p.mon = v
            } else if f == 98u8 {
                if !take_month(p, false) { ret false }
            } else if f == 66u8 {
                if !take_month(p, true) { ret false }
            } else if f == 100u8 {
                let (v, k) = take_int(p, 2usize, false)
                if !k { ret false }
                p.day = v
            } else if f == 101u8 {
                var n = 2usize
                if eat(p, 32u8) { n = 1usize }
                let (v, k) = take_int(p, n, true)
                if !k { ret false }
                p.day = v
            } else if f == 104u8 {
                var sgn = 1i64
                if p.at < p.s.len && p.s[p.at] == 45u8 {
                    sgn = -1i64
                    p.at += 1usize
                } else if p.at < p.s.len && p.s[p.at] == 43u8 {
                    p.at += 1usize
                }
                let (v, k) = take_int(p, 10usize, false)
                if !k { ret false }
                p.hour = v
                p.sign = sgn
            } else if f == 72u8 {
                let (v, k) = take_int(p, 2usize, false)
                if !k || v < 0i64 || v > 23i64 { ret false }
                p.hour = v
            } else if f == 73u8 {
                let (v, k) = take_int(p, 2usize, false)
                if !k || v < 1i64 || v > 12i64 { ret false }
                p.hour = v % 12i64
            } else if f == 77u8 {
                let (v, k) = take_int(p, 2usize, true)
                if !k { ret false }
                p.min = v
            } else if f == 83u8 {
                let (w, fr, k) = take_seconds(p)
                if !k { ret false }
                p.sec = w
            } else if f == 79u8 {
                if i >= fmt.len || fmt[i] != 83u8 { ret false }
                i += 1usize
                let (w, fr, k) = take_seconds(p)
                if !k { ret false }
                p.sec = w
                p.psec = fr
            } else if f == 112u8 {
                if !take_ampm(p) { ret false }
            } else if f == 122u8 {
                p.utc = true
                if !take_tz_offset(p) { ret false }
            } else if f == 90u8 {
                let start = p.at
                while p.at < p.s.len && !is_space(p.s[p.at]) { p.at += 1usize }
                if p.at == start { ret false }
            } else if f == 46u8 {
                if p.at >= p.s.len || is_digit(p.s[p.at]) { ret false }
                p.at += 1usize
            } else if f == 43u8 {
                if p.at >= p.s.len || is_digit(p.s[p.at]) { ret false }
                p.at += 1usize
                while p.at < p.s.len && !is_digit(p.s[p.at]) { p.at += 1usize }
            } else if f == 42u8 {
                while p.at < p.s.len && !is_digit(p.s[p.at]) { p.at += 1usize }
            } else if f == 97u8 {
                if !take_day(p, false) { ret false }
            } else if f == 65u8 && !(i < fmt.len && (fmt[i] == 68u8 || fmt[i] == 84u8)) {
                if !take_day(p, true) { ret false }
            } else if f == 65u8 {
                let g = fmt[i]
                i += 1usize
                if i != fmt.len { ret false }
                if g == 68u8 {
                    if !parse_date_auto(p) { ret false }
                } else {
                    if !parse_time_auto(p) { ret false }
                }
            } else if f == 68u8 {
                if !parse_fmt(p, "%m/%d/%y") { ret false }
            } else if f == 70u8 {
                let (y, oy) = take_int(p, 4usize, true)
                if !oy || !eat(p, 45u8) { ret false }
                p.year = y
                let (m, om) = take_int(p, 2usize, false)
                if !om { ret false }
                p.mon = m
                if eat(p, 45u8) {
                    let (d, od) = take_int(p, 2usize, false)
                    if !od { ret false }
                    p.day = d
                }
            } else if f == 82u8 {
                if !parse_time_lenient(p, false) { ret false }
            } else if f == 88u8 || f == 84u8 {
                if !parse_time_lenient(p, true) { ret false }
            } else if f == 120u8 {
                if !parse_fmt(p, "%y/%m/%d") { ret false }
            } else {
                ret false
            }
        }
    }
    skip_space(p)
    ret true
}

fn days_in_month(y: i64, m: i64) -> i64 {
    if m == 2i64 {
        if (y % 4i64 == 0i64 && y % 100i64 != 0i64) || y % 400i64 == 0i64 { ret 29i64 }
        ret 28i64
    }
    if m == 4i64 || m == 6i64 || m == 9i64 || m == 11i64 { ret 30i64 }
    ret 31i64
}

fn floor_div(a: i64, b: i64) -> i64 {
    var q = a / b
    if (a % b != 0i64) && ((a < 0i64) != (b < 0i64)) { q -= 1i64 }
    ret q
}

fn days_from_civil(y0: i64, m: i64, d: i64) -> i64 {
    var y = y0
    if m <= 2i64 { y -= 1i64 }
    let era = floor_div(y, 400i64)
    let yoe = y - era * 400i64
    var mp = m - 3i64
    if m <= 2i64 { mp = m + 9i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + d - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

fn valid_date(p: *Parser) -> bool {
    if p.year < 0i64 || p.mon < 1i64 || p.mon > 12i64 || p.day < 1i64 { ret false }
    ret p.day <= days_in_month(p.year, p.mon)
}

fn hour_of(p: *Parser) -> i64 {
    if p.hour == 12i64 {
        if p.ampm == 1i64 { ret 0i64 }
        ret 12i64
    }
    if p.ampm == 2i64 { ret p.hour + 12i64 }
    ret p.hour
}

// parse_date(x, format): days since the epoch, or NaN. The default format is "%AD".
fn parse_date(s: str, fmt: str) -> f64 { ret parse_date_in(s, fmt, "") }

fn parse_time(s: str, fmt: str) -> f64 { ret parse_time_in(s, fmt, "") }

fn parse_datetime(s: str, fmt: str) -> f64 { ret parse_datetime_in(s, fmt, "") }

// The same with a locale's names (see name_item); "" is English.
fn parse_date_in(s: str, fmt: str, names: str) -> f64 {
    var p = new_parser(trim(s))
    p.names = names
    if !parse_format(&p, fmt) { ret nan() }
    if !valid_date(&p) { ret nan() }
    ret f64(days_from_civil(p.year, p.mon, p.day))
}

// parse_time(x, format): seconds since midnight (the default format is "%AT").
fn parse_time_in(s: str, fmt: str, names: str) -> f64 {
    var p = new_parser(trim(s))
    p.names = names
    if !parse_format(&p, fmt) { ret nan() }
    if p.min < 0i64 || p.min > 59i64 || p.sec < 0i64 || p.sec > 59i64 { ret nan() }
    let sgn = f64(p.sign)
    ret sgn * (f64(hour_of(&p)) * 3600.0f64 + f64(p.min) * 60.0f64 + f64(p.sec) + p.psec)
}

// parse_datetime(x, format): seconds since the epoch in UTC; an empty format is ISO 8601.
fn parse_datetime_in(s: str, fmt: str, names: str) -> f64 {
    var p = new_parser(trim(s))
    p.names = names
    var good = false
    if fmt.len == 0usize { good = parse_iso(&p) } else { good = parse_format(&p, fmt) }
    if !good { ret nan() }
    if !valid_date(&p) { ret nan() }
    let h = hour_of(&p)
    if h < 0i64 || h > 23i64 || p.min < 0i64 || p.min > 59i64 || p.sec < 0i64 || p.sec > 60i64 { ret nan() }
    var t = f64(days_from_civil(p.year, p.mon, p.day)) * 86400.0f64 + f64(h) * 3600.0f64 + f64(p.min) * 60.0f64 + f64(p.sec) + p.psec
    t = t - f64(p.tzh) * 3600.0f64 - f64(p.tzm) * 60.0f64
    ret t
}

// --- read_delim's field splitting.

fn blank(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] != 32u8 && s[i] != 9u8 { ret false }
        i += 1usize
    }
    ret true
}

// Splits `text` into rows of fields. quote 0 means none; comment 0 means none.
fn read_delim(a: *mem.Arena, text: str, delim: u8, quote: u8, comment: u8, escape_backslash: bool, escape_double: bool, trim_ws: bool, skip_empty: bool) -> ([]str, []usize, err) {
    let (fields, fe) = mem.alloc[str](a, text.len + 2usize)
    let (counts, ce) = mem.alloc[usize](a, text.len + 2usize)
    if fe != ok { ret (fields, counts, fe) }
    if ce != ok { ret (fields, counts, ce) }
    var nf = 0usize
    var nr = 0usize
    var row_fields = 0usize
    var i = 0usize
    var row_has_content = false
    while i <= text.len {
        // one field starting at i
        let (initial, be) = str.builder(a, text.len - i + 2usize)
        if be != ok { ret (fields, counts, be) }
        var b = initial
        var at_end = i >= text.len
        var quoted = false
        var lit = false
        var end_of_row = false
        if !at_end {
            if trim_ws {
                while i < text.len && (text[i] == 32u8 || text[i] == 9u8) && text[i] != delim { i += 1usize }
            }
            if quote != 0u8 && i < text.len && text[i] == quote {
                quoted = true
                i += 1usize
                while i < text.len {
                    let c = text[i]
                    if escape_backslash && c == 92u8 && i + 1usize < text.len {
                        let _ = str.push_byte(&b, text[i + 1usize])
                        i += 2usize
                    } else if c == quote {
                        if escape_double && i + 1usize < text.len && text[i + 1usize] == quote {
                            let _ = str.push_byte(&b, quote)
                            i += 2usize
                        } else if escape_double || i + 1usize >= text.len || text[i + 1usize] == delim || text[i + 1usize] == 10u8 || text[i + 1usize] == 13u8 {
                            i += 1usize
                            break
                        } else {
                            let _ = str.push_byte(&b, c)
                            i += 1usize
                            lit = true
                            break
                        }
                    } else {
                        let _ = str.push_byte(&b, c)
                        i += 1usize
                    }
                }
            }
            while i < text.len {
                let c = text[i]
                if c == delim || c == 10u8 || c == 13u8 { break }
                if comment != 0u8 && c == comment {
                    while i < text.len && text[i] != 10u8 && text[i] != 13u8 { i += 1usize }
                    break
                }
                if escape_backslash && c == 92u8 && i + 1usize < text.len {
                    let _ = str.push_byte(&b, text[i + 1usize])
                    i += 2usize
                } else {
                    let _ = str.push_byte(&b, c)
                    i += 1usize
                }
            }
        }
        var field = str.done(&b)
        if lit && field.len > 0usize && field[field.len - 1usize] == quote { field = field[0usize..field.len - 1usize] }
        if trim_ws { field = trim(field) }
        // what ended the field
        var ender = 0u8
        if i < text.len { ender = text[i] }
        if i >= text.len { end_of_row = true } else if ender == 10u8 || ender == 13u8 { end_of_row = true }
        if quoted || !blank(field) { row_has_content = true }
        if i < text.len && text[i] == delim && delim != 9u8 && delim != 32u8 { row_has_content = true }
        if end_of_row {
            if !row_has_content && skip_empty {
                nf -= row_fields
            } else {
                fields[nf] = field
                nf += 1usize
                row_fields += 1usize
                counts[nr] = row_fields
                nr += 1usize
            }
            row_fields = 0usize
            row_has_content = false
            if i < text.len {
                if ender == 13u8 && i + 1usize < text.len && text[i + 1usize] == 10u8 { i += 2usize } else { i += 1usize }
            } else {
                i += 1usize
            }
            at_end = true
        } else {
            fields[nf] = field
            nf += 1usize
            row_fields += 1usize
            i += 1usize
        }
    }
    ret (fields[0usize..nf], counts[0usize..nr], ok)
}

// --- guess_parser

const G_LOGICAL: u8 = 0u8
const G_INTEGER: u8 = 1u8
const G_DOUBLE: u8 = 2u8
const G_NUMBER: u8 = 3u8
const G_TIME: u8 = 4u8
const G_DATE: u8 = 5u8
const G_DATETIME: u8 = 6u8
const G_CHARACTER: u8 = 7u8

fn is_na_text(v: str) -> bool { ret v.len == 0usize || str.eq(v, "NA") }

fn leading_zero(v: str) -> bool {
    var i = 0usize
    if i < v.len && (v[i] == 45u8 || v[i] == 43u8) { i += 1usize }
    ret i + 1usize < v.len && v[i] == 48u8 && is_digit(v[i + 1usize])
}

fn guess_logical(v: str) -> bool {
    ret str.eq(v, "T") || str.eq(v, "F") || str.eq(v, "TRUE") || str.eq(v, "FALSE") || str.eq(v, "true") || str.eq(v, "false") || str.eq(v, "True") || str.eq(v, "False") || str.eq(v, "t") || str.eq(v, "f")
}

fn guess_integer(v0: str) -> bool {
    var i = 0usize
    while i < v0.len && (v0[i] == 32u8 || v0[i] == 9u8) { i += 1usize }
    let v = v0[i..v0.len]
    if leading_zero(v) { ret false }
    var k = 0usize
    if k < v.len && (v[k] == 45u8 || v[k] == 43u8) { k += 1usize }
    if k >= v.len { ret false }
    var total = 0i64
    while k < v.len {
        if !is_digit(v[k]) { ret false }
        total = total * 10i64 + i64(v[k] - 48u8)
        if total > 2147483647i64 { ret false }
        k += 1usize
    }
    ret true
}

fn guess_double(a: *mem.Arena, v0: str) -> bool {
    var i = 0usize
    while i < v0.len && (v0[i] == 32u8 || v0[i] == 9u8) { i += 1usize }
    let v = v0[i..v0.len]
    if v.len == 0usize || leading_zero(v) { ret false }
    if v[v.len - 1usize] == 32u8 || v[v.len - 1usize] == 9u8 { ret false }
    let x = parse_double(a, v, 46u8)
    ret x == x
}

fn guess_number(v: str) -> bool {
    if v.len == 0usize || leading_zero(v) { ret false }
    let c = v[0usize]
    if !(is_digit(c) || c == 45u8 || c == 46u8) { ret false }
    let (x, end) = scan_number(v, 46u8, 44u8)
    ret x == x && end == v.len
}

fn digits_at(v: str, at: usize, n: usize) -> bool {
    if at + n > v.len { ret false }
    var i = 0usize
    while i < n {
        if !is_digit(v[at + i]) { ret false }
        i += 1usize
    }
    ret true
}

// The shape guess_parser looks for: 0 neither, 1 a date alone, 2 a date and a time; `dashed` says
// the date had separators.
fn iso_shape(v: str) -> (u8, bool) {
    if !digits_at(v, 0usize, 4usize) { ret (0u8, false) }
    var i = 4usize
    var dashed = false
    if i < v.len && (v[i] == 45u8 || v[i] == 47u8) {
        dashed = true
        i += 1usize
        if !digits_at(v, i, 2usize) { ret (0u8, false) }
        i += 2usize
        if i >= v.len || (v[i] != 45u8 && v[i] != 47u8) { ret (0u8, false) }
        i += 1usize
        if !digits_at(v, i, 2usize) { ret (0u8, false) }
        i += 2usize
    } else {
        if !digits_at(v, i, 4usize) { ret (0u8, false) }
        i += 4usize
    }
    if i == v.len { ret (1u8, dashed) }
    if v[i] != 84u8 && v[i] != 32u8 { ret (0u8, false) }
    i += 1usize
    if !digits_at(v, i, 2usize) { ret (0u8, false) }
    i += 2usize
    if i < v.len && v[i] == 58u8 {
        i += 1usize
        if !digits_at(v, i, 2usize) { ret (0u8, false) }
        i += 2usize
        if i < v.len && v[i] == 58u8 {
            i += 1usize
            if !digits_at(v, i, 2usize) { ret (0u8, false) }
            i += 2usize
            if i < v.len && v[i] == 46u8 {
                i += 1usize
                if i >= v.len || !is_digit(v[i]) { ret (0u8, false) }
                while i < v.len && is_digit(v[i]) { i += 1usize }
            }
        }
    } else if digits_at(v, i, 2usize) {
        i += 2usize
        if digits_at(v, i, 2usize) { i += 2usize }
    }
    if i == v.len { ret (2u8, dashed) }
    if v[i] == 90u8 && i + 1usize == v.len { ret (2u8, dashed) }
    if v[i] == 43u8 || v[i] == 45u8 {
        i += 1usize
        if !digits_at(v, i, 2usize) { ret (0u8, false) }
        i += 2usize
        if i < v.len && v[i] == 58u8 { i += 1usize }
        if i < v.len {
            if !digits_at(v, i, 2usize) { ret (0u8, false) }
            i += 2usize
        }
        if i == v.len { ret (2u8, dashed) }
    }
    ret (0u8, false)
}

// guess_parser over a column of strings (NA is "" or "NA"): the type code, G_LOGICAL to G_CHARACTER.
fn guess_parser(a: *mem.Arena, values: []const str, integer: bool) -> u8 {
    var t = 0u8
    while t < 7u8 {
        var all = true
        var i = 0usize
        while i < values.len && all {
            let v = values[i]
            if !is_na_text(v) {
                var good = false
                if t == G_LOGICAL { good = guess_logical(v) }
                if t == G_INTEGER { good = integer && guess_integer(v) }
                if t == G_DOUBLE { good = guess_double(a, v) }
                if t == G_NUMBER { good = guess_number(v) }
                if t == G_TIME {
                    let x = parse_time(v, "%AT")
                    good = x == x
                }
                if t == G_DATE {
                    let (shape, dashed) = iso_shape(v)
                    good = shape == 1u8 && dashed
                }
                if t == G_DATETIME {
                    let (shape, dashed) = iso_shape(v)
                    good = shape != 0u8
                }
                if !good { all = false }
            }
            i += 1usize
        }
        if all {
            if t != G_INTEGER || integer { ret t }
        }
        t += 1u8
    }
    ret G_CHARACTER
}
