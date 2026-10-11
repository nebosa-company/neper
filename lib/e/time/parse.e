// Date-time and duration text parsers over `e.time.calendar`: a strict ISO 8601 reader,
// a lenient reader for the shapes people write, and humantime-style duration strings.
//
// `parse_date` is the fallback order: strict ISO first, then lenient. The lenient
// reader accepts, in any order dateutil accepts them: numbers separated by `- / .`
// or spaces, month names (`Jan`, `January`, `Sept`), weekday names (ignored), the jump
// words `of at on and st nd rd th`, a time `H:MM[:SS[.f]]` or `H am|pm`, and a zone
// `Z UTC GMT +HH[:MM] -HHMM`. A date needs year, month and day; nothing is filled from
// a default and unknown words are refused. Three bare numbers read month-first unless
// `day_first`, year-first when the first is above 31 or has four digits (dateutil's
// rules). A year of at most two digits is 2000-2068 or 1969-1999.
//
// The zone is reported, not applied: `value` is the wall-clock reading. Zones by name
// belong to `e.tz`; recurrence to `e.time.recur`.
//
// Durations are `15m30s`, `1h 30m`, `500ms`: whole numbers each followed by a unit
// (`ns us ms s m h d w` and the long spellings, `M` months of 30.44 days, `y` years of
// 365.25 days); a bare number is refused.

use e.time
use e.time.calendar

type Parsed = struct { value: calendar.DateTime, has_time: bool, has_offset: bool, offset_minutes: i32 }
type Token = struct { kind: u8, start: usize, len: usize, value: i64 }
error Invalid

const NUM: u8 = 0u8
const WORD: u8 = 1u8
const PUNCT: u8 = 2u8
const MAX_TOKENS: usize = 64usize

fn lower(b: u8) -> u8 {
    if b >= 65u8 && b <= 90u8 { ret b + 32u8 }
    ret b
}

fn is_digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

fn is_alpha(b: u8) -> bool { ret (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8) }

fn word_is(s: str, lit: str) -> bool {
    if s.len != lit.len { ret false }
    var i = 0usize
    while i < s.len {
        if lower(s[i]) != lit[i] { ret false }
        i += 1usize
    }
    ret true
}

fn finish(p: Parsed) -> (Parsed, err) {
    if !calendar.valid_date(p.value.date) || !calendar.valid_time(p.value.time) { ret (zero, Invalid) }
    ret (p, ok)
}

// ISO 8601: `YYYY-MM-DD` or `YYYYMMDD`, then optionally `T`, `t` or a space and
// `HH`, `HH:MM`, `HH:MM:SS`, `HHMM` or `HHMMSS` with a `.` or `,` fraction of one to
// nine digits after the seconds, then optionally `Z`, `+HH`, `+HHMM` or `+HH:MM`.
fn parse_iso(text: str) -> (Parsed, err) {
    var p: Parsed = zero
    let (year, year_ok) = time.parse_digits(text, 0usize, 4usize)
    if !year_ok { ret (zero, Invalid) }
    var at = 4usize
    var extended = false
    if at < text.len && text[at] == 45u8 {
        extended = true
        at += 1usize
    }
    let (month, month_ok) = time.parse_digits(text, at, 2usize)
    if !month_ok { ret (zero, Invalid) }
    at += 2usize
    if extended {
        if at >= text.len || text[at] != 45u8 { ret (zero, Invalid) }
        at += 1usize
    }
    let (day, day_ok) = time.parse_digits(text, at, 2usize)
    if !day_ok { ret (zero, Invalid) }
    at += 2usize
    p.value.date.year = i32(year)
    p.value.date.month = u8(month)
    p.value.date.day = u8(day)
    if at == text.len {
        let (done, done_error) = finish(p)
        ret (done, done_error)
    }
    if text[at] != 84u8 && text[at] != 116u8 && text[at] != 32u8 { ret (zero, Invalid) }
    at += 1usize
    let (hour, hour_ok) = time.parse_digits(text, at, 2usize)
    if !hour_ok { ret (zero, Invalid) }
    at += 2usize
    p.has_time = true
    p.value.time.hour = u8(hour)
    var colon = false
    if at < text.len && text[at] == 58u8 { colon = true }
    var have_minute = false
    if colon || (at + 1usize < text.len && is_digit(text[at]) && is_digit(text[at + 1usize])) {
        if colon { at += 1usize }
        let (minute, minute_ok) = time.parse_digits(text, at, 2usize)
        if !minute_ok { ret (zero, Invalid) }
        at += 2usize
        p.value.time.minute = u8(minute)
        have_minute = true
    }
    if have_minute {
        var have_second = false
        if colon {
            if at < text.len && text[at] == 58u8 { have_second = true }
            if have_second { at += 1usize }
        } else if at + 1usize < text.len && is_digit(text[at]) && is_digit(text[at + 1usize]) {
            have_second = true
        }
        if have_second {
            let (second, second_ok) = time.parse_digits(text, at, 2usize)
            if !second_ok { ret (zero, Invalid) }
            at += 2usize
            p.value.time.second = u8(second)
            if at < text.len && (text[at] == 46u8 || text[at] == 44u8) {
                at += 1usize
                var scale = 100000000i64
                var fraction = 0i64
                var digits = 0usize
                while at < text.len && is_digit(text[at]) && digits < 9usize {
                    fraction += i64(text[at] - 48u8) * scale
                    scale = scale / 10i64
                    digits += 1usize
                    at += 1usize
                }
                if digits == 0usize { ret (zero, Invalid) }
                p.value.time.nanos = u32(fraction)
            }
        }
    }
    if at == text.len {
        let (done, done_error) = finish(p)
        ret (done, done_error)
    }
    if text[at] == 90u8 || text[at] == 122u8 {
        p.has_offset = true
        at += 1usize
    } else if text[at] == 43u8 || text[at] == 45u8 {
        let negative = text[at] == 45u8
        at += 1usize
        let (oh, oh_ok) = time.parse_digits(text, at, 2usize)
        if !oh_ok { ret (zero, Invalid) }
        at += 2usize
        var om = 0i64
        if at < text.len {
            if text[at] == 58u8 { at += 1usize }
            let (m, m_ok) = time.parse_digits(text, at, 2usize)
            if !m_ok { ret (zero, Invalid) }
            om = m
            at += 2usize
        }
        if oh > 23i64 || om > 59i64 { ret (zero, Invalid) }
        var total = oh * 60i64 + om
        if negative { total = 0i64 - total }
        p.has_offset = true
        p.offset_minutes = i32(total)
    } else {
        ret (zero, Invalid)
    }
    if at != text.len { ret (zero, Invalid) }
    let (done, done_error) = finish(p)
    ret (done, done_error)
}

fn month_of(w: str) -> i64 {
    if word_is(w, "jan") || word_is(w, "january") { ret 1i64 }
    if word_is(w, "feb") || word_is(w, "february") { ret 2i64 }
    if word_is(w, "mar") || word_is(w, "march") { ret 3i64 }
    if word_is(w, "apr") || word_is(w, "april") { ret 4i64 }
    if word_is(w, "may") { ret 5i64 }
    if word_is(w, "jun") || word_is(w, "june") { ret 6i64 }
    if word_is(w, "jul") || word_is(w, "july") { ret 7i64 }
    if word_is(w, "aug") || word_is(w, "august") { ret 8i64 }
    if word_is(w, "sep") || word_is(w, "sept") || word_is(w, "september") { ret 9i64 }
    if word_is(w, "oct") || word_is(w, "october") { ret 10i64 }
    if word_is(w, "nov") || word_is(w, "november") { ret 11i64 }
    if word_is(w, "dec") || word_is(w, "december") { ret 12i64 }
    ret 0i64
}

fn is_weekday(w: str) -> bool {
    ret word_is(w, "mon") || word_is(w, "monday") || word_is(w, "tue") || word_is(w, "tues") || word_is(w, "tuesday") || word_is(w, "wed") || word_is(w, "wednesday") || word_is(w, "thu") || word_is(w, "thur") || word_is(w, "thurs") || word_is(w, "thursday") || word_is(w, "fri") || word_is(w, "friday") || word_is(w, "sat") || word_is(w, "saturday") || word_is(w, "sun") || word_is(w, "sunday")
}

fn is_jump(w: str) -> bool {
    ret word_is(w, "of") || word_is(w, "at") || word_is(w, "on") || word_is(w, "and") || word_is(w, "st") || word_is(w, "nd") || word_is(w, "rd") || word_is(w, "th") || word_is(w, "t")
}

fn tokenize(text: str, toks: []Token) -> (usize, bool) {
    var n = 0usize
    var at = 0usize
    while at < text.len {
        if n == toks.len { ret (0usize, false) }
        let c = text[at]
        let start = at
        if is_digit(c) {
            var v = 0i64
            while at < text.len && is_digit(text[at]) {
                if at - start >= 18usize { ret (0usize, false) }
                v = v * 10i64 + i64(text[at] - 48u8)
                at += 1usize
            }
            toks[n] = Token { kind: NUM, start: start, len: at - start, value: v }
        } else if is_alpha(c) {
            while at < text.len && is_alpha(text[at]) { at += 1usize }
            toks[n] = Token { kind: WORD, start: start, len: at - start, value: 0i64 }
        } else {
            at += 1usize
            toks[n] = Token { kind: PUNCT, start: start, len: 1usize, value: i64(c) }
        }
        n += 1usize
    }
    ret (n, true)
}

fn next_nonspace(toks: []Token, n: usize, from: usize) -> usize {
    var i = from
    while i < n && toks[i].kind == PUNCT && toks[i].value == 32i64 { i += 1usize }
    ret i
}

fn expand_year(value: i64, digits: usize) -> i64 {
    if digits > 2usize { ret value }
    if value <= 68i64 { ret 2000i64 + value }
    ret 1900i64 + value
}

fn parse_lenient(text: str, day_first: bool) -> (Parsed, err) {
    var toks: [64]Token = zero
    let (n, lexed) = tokenize(text, toks[0usize..64usize])
    if !lexed || n == 0usize { ret (zero, Invalid) }
    var p: Parsed = zero
    var vals: [3]i64 = zero
    var digs: [3]usize = zero
    var count = 0usize
    var month_at = 3usize
    var year_at = 3usize
    var meridiem = 0i64
    var i = 0usize
    while i < n {
        let t = toks[i]
        if t.kind == NUM {
            let after = next_nonspace(toks[0usize..64usize], n, i + 1usize)
            if i + 1usize < n && toks[i + 1usize].kind == PUNCT && toks[i + 1usize].value == 58i64 && !p.has_time {
                if t.len > 2usize || i + 2usize >= n || toks[i + 2usize].kind != NUM || toks[i + 2usize].len != 2usize { ret (zero, Invalid) }
                p.has_time = true
                p.value.time.hour = u8(t.value)
                p.value.time.minute = u8(toks[i + 2usize].value)
                i += 3usize
                if i + 1usize < n && toks[i].kind == PUNCT && toks[i].value == 58i64 && toks[i + 1usize].kind == NUM {
                    if toks[i + 1usize].len != 2usize { ret (zero, Invalid) }
                    p.value.time.second = u8(toks[i + 1usize].value)
                    i += 2usize
                    if i + 1usize < n && toks[i].kind == PUNCT && toks[i].value == 46i64 && toks[i + 1usize].kind == NUM {
                        let digits = toks[i + 1usize].len
                        if digits > 9usize { ret (zero, Invalid) }
                        var fraction = toks[i + 1usize].value
                        var pad = digits
                        while pad < 9usize {
                            fraction = fraction * 10i64
                            pad += 1usize
                        }
                        p.value.time.nanos = u32(fraction)
                        i += 2usize
                    }
                }
                continue
            }
            if !p.has_time && t.len <= 2usize && after < n && toks[after].kind == WORD && (word_is(text[toks[after].start..toks[after].start + toks[after].len], "am") || word_is(text[toks[after].start..toks[after].start + toks[after].len], "pm")) {
                p.has_time = true
                p.value.time.hour = u8(t.value)
                if word_is(text[toks[after].start..toks[after].start + toks[after].len], "pm") { meridiem = 2i64 } else { meridiem = 1i64 }
                if t.value < 1i64 || t.value > 12i64 { ret (zero, Invalid) }
                i = after + 1usize
                continue
            }
            if count == 3usize { ret (zero, Invalid) }
            vals[count] = t.value
            digs[count] = t.len
            if t.len > 2usize {
                if year_at != 3usize { ret (zero, Invalid) }
                year_at = count
            }
            count += 1usize
            i += 1usize
            continue
        }
        if t.kind == WORD {
            let w = text[t.start..t.start + t.len]
            let month = month_of(w)
            if month > 0i64 {
                if count == 3usize || month_at != 3usize { ret (zero, Invalid) }
                vals[count] = month
                digs[count] = 0usize
                month_at = count
                count += 1usize
            } else if word_is(w, "am") || word_is(w, "pm") {
                if !p.has_time || meridiem != 0i64 { ret (zero, Invalid) }
                if p.value.time.hour < 1u8 || p.value.time.hour > 12u8 { ret (zero, Invalid) }
                if word_is(w, "pm") { meridiem = 2i64 } else { meridiem = 1i64 }
            } else if word_is(w, "z") || word_is(w, "utc") || word_is(w, "gmt") {
                if p.has_offset { ret (zero, Invalid) }
                p.has_offset = true
            } else if is_weekday(w) || is_jump(w) {
                // dropped
            } else {
                ret (zero, Invalid)
            }
            i += 1usize
            continue
        }
        // Punctuation: a sign after a time is a zone offset, anything else separates.
        if (t.value == 43i64 || t.value == 45i64) && p.has_time && !p.has_offset && i + 1usize < n && toks[i + 1usize].kind == NUM {
            let digits = toks[i + 1usize].len
            var hh = 0i64
            var mm = 0i64
            var used = 2usize
            if digits == 4usize {
                hh = toks[i + 1usize].value / 100i64
                mm = toks[i + 1usize].value % 100i64
            } else if digits <= 2usize {
                hh = toks[i + 1usize].value
                if i + 3usize < n && toks[i + 2usize].kind == PUNCT && toks[i + 2usize].value == 58i64 && toks[i + 3usize].kind == NUM && toks[i + 3usize].len == 2usize {
                    mm = toks[i + 3usize].value
                    used = 4usize
                }
            } else {
                ret (zero, Invalid)
            }
            if hh > 23i64 || mm > 59i64 { ret (zero, Invalid) }
            var total = hh * 60i64 + mm
            if t.value == 45i64 { total = 0i64 - total }
            p.has_offset = true
            p.offset_minutes = i32(total)
            i += used
            continue
        }
        i += 1usize
    }
    if count != 3usize { ret (zero, Invalid) }
    var year = 0i64
    var month = 0i64
    var day = 0i64
    var year_digits = 0usize
    if month_at == 0usize {
        if vals[1usize] > 31i64 {
            month = vals[0usize]
            year = vals[1usize]
            year_digits = digs[1usize]
            day = vals[2usize]
        } else {
            month = vals[0usize]
            day = vals[1usize]
            year = vals[2usize]
            year_digits = digs[2usize]
        }
    } else if month_at == 1usize {
        month = vals[1usize]
        if vals[0usize] > 31i64 {
            year = vals[0usize]
            year_digits = digs[0usize]
            day = vals[2usize]
        } else {
            day = vals[0usize]
            year = vals[2usize]
            year_digits = digs[2usize]
        }
    } else if month_at == 2usize {
        month = vals[2usize]
        if vals[1usize] > 31i64 {
            day = vals[0usize]
            year = vals[1usize]
            year_digits = digs[1usize]
        } else {
            year = vals[0usize]
            year_digits = digs[0usize]
            day = vals[1usize]
        }
    } else if vals[0usize] > 31i64 || year_at == 0usize {
        year = vals[0usize]
        year_digits = digs[0usize]
        if day_first && vals[2usize] <= 12i64 {
            day = vals[1usize]
            month = vals[2usize]
        } else {
            month = vals[1usize]
            day = vals[2usize]
        }
    } else if vals[0usize] > 12i64 || (day_first && vals[1usize] <= 12i64) {
        day = vals[0usize]
        month = vals[1usize]
        year = vals[2usize]
        year_digits = digs[2usize]
    } else {
        month = vals[0usize]
        day = vals[1usize]
        year = vals[2usize]
        year_digits = digs[2usize]
    }
    year = expand_year(year, year_digits)
    if year < 1i64 || year > 9999i64 { ret (zero, Invalid) }
    if month < 1i64 || month > 12i64 || day < 1i64 || day > 31i64 { ret (zero, Invalid) }
    p.value.date.year = i32(year)
    p.value.date.month = u8(month)
    p.value.date.day = u8(day)
    if meridiem == 2i64 && p.value.time.hour < 12u8 { p.value.time.hour += 12u8 }
    if meridiem == 1i64 && p.value.time.hour == 12u8 { p.value.time.hour = 0u8 }
    let (done, done_error) = finish(p)
    ret (done, done_error)
}

fn parse_date(text: str, day_first: bool) -> (Parsed, err) {
    let (strict, strict_error) = parse_iso(text)
    if strict_error == ok { ret (strict, ok) }
    let (loose, loose_error) = parse_lenient(text, day_first)
    ret (loose, loose_error)
}

fn unit_nanos(w: str) -> i64 {
    if w.len == 0usize { ret 0i64 }
    if w.len == 1usize && w[0usize] == 77u8 { ret 2630016000000000i64 }
    if word_is(w, "nsec") || word_is(w, "ns") { ret 1i64 }
    if word_is(w, "usec") || word_is(w, "us") { ret 1000i64 }
    if word_is(w, "msec") || word_is(w, "ms") { ret 1000000i64 }
    if word_is(w, "seconds") || word_is(w, "second") || word_is(w, "sec") || word_is(w, "s") { ret 1000000000i64 }
    if word_is(w, "minutes") || word_is(w, "minute") || word_is(w, "min") || word_is(w, "m") { ret 60000000000i64 }
    if word_is(w, "hours") || word_is(w, "hour") || word_is(w, "hr") || word_is(w, "h") { ret 3600000000000i64 }
    if word_is(w, "days") || word_is(w, "day") || word_is(w, "d") { ret 86400000000000i64 }
    if word_is(w, "weeks") || word_is(w, "week") || word_is(w, "w") { ret 604800000000000i64 }
    if word_is(w, "months") || word_is(w, "month") { ret 2630016000000000i64 }
    if word_is(w, "years") || word_is(w, "year") || word_is(w, "y") { ret 31557600000000000i64 }
    ret 0i64
}

fn parse_duration(text: str) -> (time.Duration, err) {
    var total = 0i64
    var at = 0usize
    var parts = 0usize
    while true {
        while at < text.len && text[at] == 32u8 { at += 1usize }
        if at == text.len { break }
        let first = at
        var value = 0i64
        while at < text.len && is_digit(text[at]) {
            let digit = i64(text[at] - 48u8)
            if value > 922337203685477580i64 || (value == 922337203685477580i64 && digit > 7i64) { ret (time.Duration { nanos: 0i64 }, Invalid) }
            value = value * 10i64 + digit
            at += 1usize
        }
        if at == first { ret (time.Duration { nanos: 0i64 }, Invalid) }
        while at < text.len && text[at] == 32u8 { at += 1usize }
        let unit_start = at
        while at < text.len && is_alpha(text[at]) { at += 1usize }
        let scale = unit_nanos(text[unit_start..at])
        if scale == 0i64 { ret (time.Duration { nanos: 0i64 }, Invalid) }
        if value > 9223372036854775807i64 / scale { ret (time.Duration { nanos: 0i64 }, Invalid) }
        let piece = value * scale
        if total > 9223372036854775807i64 - piece { ret (time.Duration { nanos: 0i64 }, Invalid) }
        total += piece
        parts += 1usize
    }
    if parts == 0usize { ret (time.Duration { nanos: 0i64 }, Invalid) }
    ret (time.Duration { nanos: total }, ok)
}
