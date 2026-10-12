// Pattern-based date-time text, the shape NodaTime's `LocalDateTimePattern` has: a runtime
// pattern string of custom specifiers, formatted from and parsed into an
// `e.time.calendar` `DateTime`. (`calendar.format` is the compile-time, fixed-width
// subset; this reads any pattern a caller holds as data.) English names, invariant culture;
// `format_locale` and `parse_locale` take a language tag and use that language's CLDR month,
// weekday and AM/PM names from `e.time.names` (`MMM` and `ddd` are then its abbreviations,
// not three letters; `t` is the first character of the mark).
//
// Specifiers: `yyyy` four-digit year, `yy` two-digit year (parsed 00-29 as 2000-2029,
// 30-99 as 1930-1999); `MMMM` `MMM` month name, `MM` `M` month number; `dddd` `ddd`
// weekday name, `dd` `d` day; `HH` `H` 24-hour, `hh` `h` 12-hour; `mm` `m` minute; `ss`
// `s` second; `f`..`fffffffff` a fixed fraction of that many digits, `F`..`FFFFFFFFF` the
// same with trailing zeros (and a bare separator) dropped; `tt` `t` AM/PM or A/P. A
// quoted run `'...'` or `"..."` is literal, `\x` is literal x, `%x` makes a single
// letter a specifier; every other byte is literal. A doubled letter run longer than the
// forms above is `Invalid`.
//
// Parsing: a padded form (`dd`) reads exactly its digits, an unpadded one (`d`) one or
// two; names match case-insensitively; each field may appear once; `h` needs `tt`/`t`
// and `tt`/`t` needs `h`; a weekday name that disagrees with the date is refused. A
// field the pattern lacks takes the template's value (2000-01-01T00:00:00 for `parse`).

use e.time
use e.time.calendar
use e.time.names

type Buf = struct { dst: []u8, n: usize, bad: bool }
type Fields = struct { year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, nanos: i64, hour12: i64, pm: i64, weekday: i64 }
error Invalid

fn lower(b: u8) -> u8 {
    if b >= 65u8 && b <= 90u8 { ret b + 32u8 }
    ret b
}

fn is_digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

fn month_name(month: u8) -> str {
    if month == 1u8 { ret "January" }
    if month == 2u8 { ret "February" }
    if month == 3u8 { ret "March" }
    if month == 4u8 { ret "April" }
    if month == 5u8 { ret "May" }
    if month == 6u8 { ret "June" }
    if month == 7u8 { ret "July" }
    if month == 8u8 { ret "August" }
    if month == 9u8 { ret "September" }
    if month == 10u8 { ret "October" }
    if month == 11u8 { ret "November" }
    if month == 12u8 { ret "December" }
    ret ""
}

fn weekday_name(index: i64) -> str {
    if index == 0i64 { ret "Monday" }
    if index == 1i64 { ret "Tuesday" }
    if index == 2i64 { ret "Wednesday" }
    if index == 3i64 { ret "Thursday" }
    if index == 4i64 { ret "Friday" }
    if index == 5i64 { ret "Saturday" }
    if index == 6i64 { ret "Sunday" }
    ret ""
}

// The month, weekday and AM/PM texts of locale `loc` (0 is the invariant English: the abbreviation is its first three
// letters, the mark is AM or PM).
fn month_text(loc: usize, month: u8, abbr: bool) -> str {
    if loc != 0usize { ret names.month(loc, month, abbr) }
    let full = month_name(month)
    if abbr && full.len >= 3usize { ret full[0usize..3usize] }
    ret full
}

fn weekday_text(loc: usize, index: i64, abbr: bool) -> str {
    if loc != 0usize { ret names.weekday(loc, index, abbr) }
    let full = weekday_name(index)
    if abbr && full.len >= 3usize { ret full[0usize..3usize] }
    ret full
}

fn mark_text(loc: usize, pm: bool) -> str {
    if loc != 0usize { ret names.day_period(loc, pm) }
    if pm { ret "PM" }
    ret "AM"
}

// The byte length of the UTF-8 scalar at the start of `s`.
fn first_scalar(s: str) -> usize {
    if s.len == 0usize { ret 0usize }
    var n = 1usize
    if s[0usize] >= 240u8 {
        n = 4usize
    } else if s[0usize] >= 224u8 {
        n = 3usize
    } else if s[0usize] >= 192u8 {
        n = 2usize
    }
    if n > s.len { n = s.len }
    ret n
}

fn push(b: *Buf, c: u8) {
    if b.n >= b.dst.len {
        b.bad = true
        ret
    }
    b.dst[b.n] = c
    b.n += 1usize
}

fn push_str(b: *Buf, s: str) {
    var i = 0usize
    while i < s.len {
        push(b, s[i])
        i += 1usize
    }
}

fn push_prefix(b: *Buf, s: str, count: usize) {
    var i = 0usize
    while i < count && i < s.len {
        push(b, s[i])
        i += 1usize
    }
}

fn push_num(b: *Buf, value: i64, width: usize) {
    var digits: [20]u8 = zero
    var count = 0usize
    var v = value
    if v == 0i64 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while v > 0i64 {
        digits[count] = u8(48i64 + v % 10i64)
        count += 1usize
        v = v / 10i64
    }
    var pad = width
    while pad > count {
        push(b, 48u8)
        pad -= 1usize
    }
    while count > 0usize {
        count -= 1usize
        push(b, digits[count])
    }
}

fn run_of(pattern: str, at: usize) -> usize {
    var n = 1usize
    while at + n < pattern.len && pattern[at + n] == pattern[at] { n += 1usize }
    ret n
}

fn is_specifier(c: u8) -> bool {
    ret c == 121u8 || c == 77u8 || c == 100u8 || c == 72u8 || c == 104u8 || c == 109u8 || c == 115u8 || c == 102u8 || c == 70u8 || c == 116u8
}

// Literal prefix handling shared by both directions: returns the index after a quoted run
// or escape, `at` itself when the byte is not literal-introducing, and sets `bad`.
fn quoted_end(pattern: str, at: usize) -> (usize, bool) {
    let q = pattern[at]
    var j = at + 1usize
    while j < pattern.len && pattern[j] != q { j += 1usize }
    if j >= pattern.len { ret (at, false) }
    ret (j, true)
}

fn format(pattern: str, value: calendar.DateTime, dst: []u8) -> (str, err) {
    let (text, text_error) = format_in(0usize, pattern, value, dst)
    ret (text, text_error)
}

// `format` with the names of a language tag (`fr`, `de-AT`, ...); an unknown tag is `Invalid`.
fn format_locale(tag: str, pattern: str, value: calendar.DateTime, dst: []u8) -> (str, err) {
    let (loc, known) = names.locale_index(tag)
    if !known { ret ("", Invalid) }
    let (text, text_error) = format_in(loc, pattern, value, dst)
    ret (text, text_error)
}

fn format_in(loc: usize, pattern: str, value: calendar.DateTime, dst: []u8) -> (str, err) {
    if !calendar.valid_date(value.date) || !calendar.valid_time(value.time) { ret ("", Invalid) }
    let (wd, wd_error) = calendar.weekday(value.date)
    if wd_error != ok { ret ("", Invalid) }
    var b: Buf = zero
    b.dst = dst
    var at = 0usize
    while at < pattern.len {
        let c = pattern[at]
        if c == 39u8 || c == 34u8 {
            let (close, closed) = quoted_end(pattern, at)
            if !closed { ret ("", Invalid) }
            var k = at + 1usize
            while k < close {
                push(&b, pattern[k])
                k += 1usize
            }
            at = close + 1usize
        } else if c == 92u8 {
            if at + 1usize >= pattern.len { ret ("", Invalid) }
            push(&b, pattern[at + 1usize])
            at += 2usize
        } else if is_specifier(c) || (c == 37u8 && at + 1usize < pattern.len && is_specifier(pattern[at + 1usize])) {
            var letter = c
            var run = 0usize
            if c == 37u8 {
                letter = pattern[at + 1usize]
                run = 1usize
                at += 1usize
            } else {
                run = run_of(pattern, at)
            }
            if letter == 121u8 {
                if run == 4usize {
                    push_num(&b, i64(value.date.year), 4usize)
                } else if run == 2usize {
                    push_num(&b, time.floor_mod(i64(value.date.year), 100i64), 2usize)
                } else { ret ("", Invalid) }
            } else if letter == 77u8 {
                if run == 4usize {
                    push_str(&b, month_text(loc, value.date.month, false))
                } else if run == 3usize {
                    push_str(&b, month_text(loc, value.date.month, true))
                } else if run == 2usize {
                    push_num(&b, i64(value.date.month), 2usize)
                } else if run == 1usize {
                    push_num(&b, i64(value.date.month), 1usize)
                } else { ret ("", Invalid) }
            } else if letter == 100u8 {
                if run == 4usize {
                    push_str(&b, weekday_text(loc, calendar.weekday_index(wd), false))
                } else if run == 3usize {
                    push_str(&b, weekday_text(loc, calendar.weekday_index(wd), true))
                } else if run == 2usize {
                    push_num(&b, i64(value.date.day), 2usize)
                } else if run == 1usize {
                    push_num(&b, i64(value.date.day), 1usize)
                } else { ret ("", Invalid) }
            } else if letter == 72u8 {
                if run > 2usize { ret ("", Invalid) }
                push_num(&b, i64(value.time.hour), run)
            } else if letter == 104u8 {
                if run > 2usize { ret ("", Invalid) }
                var h12 = i64(value.time.hour) % 12i64
                if h12 == 0i64 { h12 = 12i64 }
                push_num(&b, h12, run)
            } else if letter == 109u8 {
                if run > 2usize { ret ("", Invalid) }
                push_num(&b, i64(value.time.minute), run)
            } else if letter == 115u8 {
                if run > 2usize { ret ("", Invalid) }
                push_num(&b, i64(value.time.second), run)
            } else if letter == 116u8 {
                if run > 2usize { ret ("", Invalid) }
                let mark = mark_text(loc, value.time.hour >= 12u8)
                if run == 2usize {
                    push_str(&b, mark)
                } else {
                    push_prefix(&b, mark, first_scalar(mark))
                }
            } else {
                // f / F fraction of `run` digits, from the nanoseconds.
                if run > 9usize { ret ("", Invalid) }
                var digits: [9]u8 = zero
                var v = i64(value.time.nanos)
                var d = 9usize
                while d > 0usize {
                    d -= 1usize
                    digits[d] = u8(48i64 + v % 10i64)
                    v = v / 10i64
                }
                var keep = run
                if letter == 70u8 {
                    while keep > 0usize && digits[keep - 1usize] == 48u8 { keep -= 1usize }
                }
                var k = 0usize
                while k < keep {
                    push(&b, digits[k])
                    k += 1usize
                }
            }
            at += run
        } else {
            push(&b, c)
            at += 1usize
        }
    }
    if b.bad { ret ("", Invalid) }
    ret (dst[..b.n], ok)
}

// Reads `min`..`max` digits at `at`; returns the value, the new position and success.
fn read_digits(src: str, at: usize, min: usize, max: usize) -> (i64, usize, bool) {
    var n = 0usize
    var v = 0i64
    while n < max && at + n < src.len && is_digit(src[at + n]) {
        v = v * 10i64 + i64(src[at + n] - 48u8)
        n += 1usize
    }
    if n < min { ret (0i64, at, false) }
    ret (v, at + n, true)
}

fn starts_with_fold(src: str, at: usize, name: str, count: usize) -> bool {
    var n = count
    if n > name.len { n = name.len }
    if at + n > src.len { ret false }
    var i = 0usize
    while i < n {
        if lower(src[at + i]) != lower(name[i]) { ret false }
        i += 1usize
    }
    ret true
}

// The month or weekday whose name (`count` letters of it, 0 = whole) is at `at`.
fn match_month(loc: usize, src: str, at: usize, abbr: bool) -> (i64, usize) {
    var best = 0i64
    var best_len = 0usize
    var m = 1u8
    while m <= 12u8 {
        let name = month_text(loc, m, abbr)
        if name.len > best_len && starts_with_fold(src, at, name, name.len) {
            best = i64(m)
            best_len = name.len
        }
        m += 1u8
    }
    if best == 0i64 { ret (0i64, at) }
    ret (best, at + best_len)
}

fn match_weekday(loc: usize, src: str, at: usize, abbr: bool) -> (i64, usize) {
    var best = -1i64
    var best_len = 0usize
    var w = 0i64
    while w < 7i64 {
        let name = weekday_text(loc, w, abbr)
        if name.len > best_len && starts_with_fold(src, at, name, name.len) {
            best = w
            best_len = name.len
        }
        w += 1i64
    }
    if best < 0i64 { ret (-1i64, at) }
    ret (best, at + best_len)
}

// A field slot is set once: -1 marks "unset" until read.
fn parse_with(loc: usize, pattern: str, source: str, template: calendar.DateTime) -> (calendar.DateTime, err) {
    var f: Fields = zero
    f.year = -1i64
    f.month = -1i64
    f.day = -1i64
    f.hour = -1i64
    f.minute = -1i64
    f.second = -1i64
    f.nanos = -1i64
    f.hour12 = -1i64
    f.pm = -1i64
    f.weekday = -1i64
    var at = 0usize
    var pos = 0usize
    while at < pattern.len {
        let c = pattern[at]
        if c == 39u8 || c == 34u8 {
            let (close, closed) = quoted_end(pattern, at)
            if !closed { ret (zero, Invalid) }
            var k = at + 1usize
            while k < close {
                if pos >= source.len || source[pos] != pattern[k] { ret (zero, Invalid) }
                pos += 1usize
                k += 1usize
            }
            at = close + 1usize
        } else if c == 92u8 {
            if at + 1usize >= pattern.len { ret (zero, Invalid) }
            if pos >= source.len || source[pos] != pattern[at + 1usize] { ret (zero, Invalid) }
            pos += 1usize
            at += 2usize
        } else if is_specifier(c) || (c == 37u8 && at + 1usize < pattern.len && is_specifier(pattern[at + 1usize])) {
            var letter = c
            var run = 0usize
            if c == 37u8 {
                letter = pattern[at + 1usize]
                run = 1usize
                at += 1usize
            } else {
                run = run_of(pattern, at)
            }
            if letter == 121u8 {
                if run != 4usize && run != 2usize { ret (zero, Invalid) }
                if f.year >= 0i64 { ret (zero, Invalid) }
                let (v, next, good) = read_digits(source, pos, run, run)
                if !good { ret (zero, Invalid) }
                f.year = v
                if run == 2usize {
                    if v < 30i64 {
                        f.year = 2000i64 + v
                    } else {
                        f.year = 1900i64 + v
                    }
                }
                pos = next
            } else if letter == 77u8 {
                if run > 4usize { ret (zero, Invalid) }
                if f.month >= 0i64 { ret (zero, Invalid) }
                if run >= 3usize {
                    let (v, next) = match_month(loc, source, pos, run == 3usize)
                    if v == 0i64 { ret (zero, Invalid) }
                    f.month = v
                    pos = next
                } else {
                    var lo = 1usize
                    if run == 2usize { lo = 2usize }
                    let (v, next, good) = read_digits(source, pos, lo, 2usize)
                    if !good { ret (zero, Invalid) }
                    f.month = v
                    pos = next
                }
            } else if letter == 100u8 {
                if run > 4usize { ret (zero, Invalid) }
                if run >= 3usize {
                    if f.weekday >= 0i64 { ret (zero, Invalid) }
                    let (v, next) = match_weekday(loc, source, pos, run == 3usize)
                    if v < 0i64 { ret (zero, Invalid) }
                    f.weekday = v
                    pos = next
                } else {
                    if f.day >= 0i64 { ret (zero, Invalid) }
                    var lo = 1usize
                    if run == 2usize { lo = 2usize }
                    let (v, next, good) = read_digits(source, pos, lo, 2usize)
                    if !good { ret (zero, Invalid) }
                    f.day = v
                    pos = next
                }
            } else if letter == 72u8 || letter == 104u8 || letter == 109u8 || letter == 115u8 {
                if run > 2usize { ret (zero, Invalid) }
                var lo = 1usize
                if run == 2usize { lo = 2usize }
                let (v, next, good) = read_digits(source, pos, lo, 2usize)
                if !good { ret (zero, Invalid) }
                if letter == 72u8 {
                    if f.hour >= 0i64 { ret (zero, Invalid) }
                    f.hour = v
                } else if letter == 104u8 {
                    if f.hour12 >= 0i64 { ret (zero, Invalid) }
                    f.hour12 = v
                } else if letter == 109u8 {
                    if f.minute >= 0i64 { ret (zero, Invalid) }
                    f.minute = v
                } else {
                    if f.second >= 0i64 { ret (zero, Invalid) }
                    f.second = v
                }
                pos = next
            } else if letter == 116u8 {
                if run > 2usize { ret (zero, Invalid) }
                if f.pm >= 0i64 { ret (zero, Invalid) }
                if pos >= source.len { ret (zero, Invalid) }
                if loc != 0usize {
                    // The language's marks: the whole mark for `tt`, its first character for `t` (refused when
                    // both marks share it, as in Japanese).
                    let am = mark_text(loc, false)
                    let pm_mark = mark_text(loc, true)
                    var am_len = am.len
                    var pm_len = pm_mark.len
                    if run == 1usize {
                        am_len = first_scalar(am)
                        pm_len = first_scalar(pm_mark)
                    }
                    let is_am = am_len > 0usize && starts_with_fold(source, pos, am, am_len)
                    let is_pm = pm_len > 0usize && starts_with_fold(source, pos, pm_mark, pm_len)
                    if is_am == is_pm { ret (zero, Invalid) }
                    if is_am {
                        f.pm = 0i64
                        pos += am_len
                    } else {
                        f.pm = 1i64
                        pos += pm_len
                    }
                } else {
                    let first = lower(source[pos])
                    if first == 97u8 {
                        f.pm = 0i64
                    } else if first == 112u8 {
                        f.pm = 1i64
                    } else { ret (zero, Invalid) }
                    pos += 1usize
                    if run == 2usize {
                        if pos >= source.len || lower(source[pos]) != 109u8 { ret (zero, Invalid) }
                        pos += 1usize
                    }
                }
            } else {
                if run > 9usize { ret (zero, Invalid) }
                if f.nanos >= 0i64 { ret (zero, Invalid) }
                var lo = run
                if letter == 70u8 { lo = 0usize }
                let (v, next, good) = read_digits(source, pos, lo, run)
                if !good { ret (zero, Invalid) }
                var digits = next - pos
                var scaled = v
                while digits < 9usize {
                    scaled = scaled * 10i64
                    digits += 1usize
                }
                f.nanos = scaled
                pos = next
            }
            at += run
        } else {
            if pos >= source.len || source[pos] != c { ret (zero, Invalid) }
            pos += 1usize
            at += 1usize
        }
    }
    if pos != source.len { ret (zero, Invalid) }
    var out = template
    if f.year >= 0i64 { out.date.year = i32(f.year) }
    if f.month >= 0i64 { out.date.month = u8(f.month) }
    if f.day >= 0i64 { out.date.day = u8(f.day) }
    if f.minute >= 0i64 { out.time.minute = u8(f.minute) }
    if f.second >= 0i64 { out.time.second = u8(f.second) }
    if f.nanos >= 0i64 { out.time.nanos = u32(f.nanos) }
    if f.hour >= 0i64 {
        if f.hour12 >= 0i64 || f.pm >= 0i64 { ret (zero, Invalid) }
        out.time.hour = u8(f.hour)
    } else if f.hour12 >= 0i64 || f.pm >= 0i64 {
        if f.hour12 < 1i64 || f.hour12 > 12i64 || f.pm < 0i64 { ret (zero, Invalid) }
        out.time.hour = u8(f.hour12 % 12i64 + 12i64 * f.pm)
    }
    if !calendar.valid_date(out.date) || !calendar.valid_time(out.time) { ret (zero, Invalid) }
    if f.weekday >= 0i64 {
        let (wd, wd_error) = calendar.weekday(out.date)
        if wd_error != ok || calendar.weekday_index(wd) != f.weekday { ret (zero, Invalid) }
    }
    ret (out, ok)
}

fn parse(pattern: str, source: str) -> (calendar.DateTime, err) {
    var template: calendar.DateTime = zero
    template.date.year = 2000i32
    template.date.month = 1u8
    template.date.day = 1u8
    let (value, value_error) = parse_with(0usize, pattern, source, template)
    ret (value, value_error)
}

// `parse` with the names of a language tag; an unknown tag is `Invalid`.
fn parse_locale(tag: str, pattern: str, source: str) -> (calendar.DateTime, err) {
    var template: calendar.DateTime = zero
    template.date.year = 2000i32
    template.date.month = 1u8
    template.date.day = 1u8
    let (loc, known) = names.locale_index(tag)
    if !known { ret (zero, Invalid) }
    let (value, value_error) = parse_with(loc, pattern, source, template)
    ret (value, value_error)
}
