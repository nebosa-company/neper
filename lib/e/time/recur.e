// RFC 5545 recurrence rules over `e.time.calendar` date-times. A rule is parsed from
// its `FREQ=...;BYDAY=...` text into a plain struct with no storage, and expanded
// against a start the caller supplies (the rule text carries no DTSTART).
//
// Supported parts: FREQ (YEARLY to SECONDLY), INTERVAL, COUNT, UNTIL, WKST, BYMONTH,
// BYMONTHDAY, BYYEARDAY, BYDAY (with ordinals for MONTHLY and YEARLY), BYHOUR,
// BYMINUTE, BYSECOND and BYSETPOS. BYWEEKNO and BYEASTER are refused. Date-times are
// floating (no zone, whole seconds); a date-only UNTIL is midnight of that day, as
// python-dateutil reads it. Occurrences before the start are never produced, and the
// start itself is produced only when the rule matches it.
//
// ponytail: a rule whose periods stay empty is searched for a bounded number of
// iterations (the year 9999 or 4,000,000 sub-daily steps) and then ends quietly.

use e.time
use e.time.calendar

const YEARLY: u8 = 0u8
const MONTHLY: u8 = 1u8
const WEEKLY: u8 = 2u8
const DAILY: u8 = 3u8
const HOURLY: u8 = 4u8
const MINUTELY: u8 = 5u8
const SECONDLY: u8 = 6u8

type Rule = struct {
    freq: u8,
    interval: i64,
    count: i64,
    has_until: bool,
    until: calendar.DateTime,
    wkst: i64,
    months: u64,
    mday_pos: u64,
    mday_neg: u64,
    any_day: bool,
    day_pos: [7]u64,
    day_neg: [7]u64,
    hours: u64,
    minutes: u64,
    seconds: u64,
    yday_n: usize,
    yday: [32]i64,
    setpos_n: usize,
    setpos: [32]i64,
}
error Invalid

fn upper(b: u8) -> u8 {
    if b >= 97u8 && b <= 122u8 { ret b - 32u8 }
    ret b
}

fn upper_eq(s: str, lit: str) -> bool {
    if s.len != lit.len { ret false }
    var i = 0usize
    while i < s.len {
        if upper(s[i]) != lit[i] { ret false }
        i += 1usize
    }
    ret true
}

// An optionally signed decimal at `from`; the position after it.
fn read_int(s: str, from: usize) -> (i64, usize, bool) {
    var at = from
    var negative = false
    if at < s.len && (s[at] == 43u8 || s[at] == 45u8) {
        negative = s[at] == 45u8
        at += 1usize
    }
    let first = at
    var value = 0i64
    while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 {
        value = value * 10i64 + i64(s[at] - 48u8)
        if value > 100000000i64 { ret (0i64, from, false) }
        at += 1usize
    }
    if at == first { ret (0i64, from, false) }
    if negative { value = 0i64 - value }
    ret (value, at, true)
}

fn weekday_code(s: str) -> i64 {
    if s.len != 2usize { ret -1i64 }
    if upper_eq(s, "MO") { ret 0i64 }
    if upper_eq(s, "TU") { ret 1i64 }
    if upper_eq(s, "WE") { ret 2i64 }
    if upper_eq(s, "TH") { ret 3i64 }
    if upper_eq(s, "FR") { ret 4i64 }
    if upper_eq(s, "SA") { ret 5i64 }
    if upper_eq(s, "SU") { ret 6i64 }
    ret -1i64
}

fn bit_set(mask: u64, n: i64) -> bool {
    if n < 0i64 || n > 63i64 { ret false }
    ret ((mask >> u32(n)) & 1u64) != 0u64
}

fn with_bit(mask: u64, n: i64) -> u64 { ret mask | (1u64 << u32(n)) }

// One `YYYYMMDD` or `YYYYMMDDTHHMMSS[Z]` value.
fn parse_stamp(s: str) -> (calendar.DateTime, err) {
    var out: calendar.DateTime = zero
    if s.len != 8usize && s.len != 15usize && s.len != 16usize { ret (out, Invalid) }
    let (year, y_ok) = time.parse_digits(s, 0usize, 4usize)
    let (month, m_ok) = time.parse_digits(s, 4usize, 2usize)
    let (day, d_ok) = time.parse_digits(s, 6usize, 2usize)
    if !y_ok || !m_ok || !d_ok { ret (out, Invalid) }
    out.date.year = i32(year)
    out.date.month = u8(month)
    out.date.day = u8(day)
    if s.len > 8usize {
        if s[8usize] != 84u8 && s[8usize] != 116u8 { ret (out, Invalid) }
        let (hour, h_ok) = time.parse_digits(s, 9usize, 2usize)
        let (minute, n_ok) = time.parse_digits(s, 11usize, 2usize)
        let (second, s_ok) = time.parse_digits(s, 13usize, 2usize)
        if !h_ok || !n_ok || !s_ok { ret (out, Invalid) }
        if s.len == 16usize && upper(s[15usize]) != 90u8 { ret (out, Invalid) }
        out.time.hour = u8(hour)
        out.time.minute = u8(minute)
        out.time.second = u8(second)
    }
    if !calendar.valid_date(out.date) || !calendar.valid_time(out.time) { ret (out, Invalid) }
    ret (out, ok)
}

fn parse_list(value: str, lo: i64, hi: i64, signed: bool, mask_pos: *u64, mask_neg: *u64) -> err {
    var at = 0usize
    while at < value.len {
        let (n, after, good) = read_int(value, at)
        if !good || n == 0i64 && lo > 0i64 { ret Invalid }
        var magnitude = n
        if n < 0i64 { magnitude = 0i64 - n }
        if magnitude < lo || magnitude > hi { ret Invalid }
        if n < 0i64 {
            if !signed { ret Invalid }
            *mask_neg = with_bit(*mask_neg, magnitude)
        } else {
            *mask_pos = with_bit(*mask_pos, magnitude)
        }
        at = after
        if at < value.len {
            if value[at] != 44u8 || at + 1usize == value.len { ret Invalid }
            at += 1usize
        }
    }
    if value.len == 0usize { ret Invalid }
    ret ok
}

fn parse_byday(value: str, r: *Rule) -> err {
    if value.len == 0usize { ret Invalid }
    var at = 0usize
    while at < value.len {
        var ordinal = 0i64
        var next = at
        if value[at] == 43u8 || value[at] == 45u8 || (value[at] >= 48u8 && value[at] <= 57u8) {
            let (n, after, good) = read_int(value, at)
            if !good || n == 0i64 || n > 53i64 || n < -53i64 { ret Invalid }
            ordinal = n
            next = after
        }
        if next + 2usize > value.len { ret Invalid }
        let wd = weekday_code(value[next..next + 2usize])
        if wd < 0i64 { ret Invalid }
        let index = usize(wd)
        if ordinal == 0i64 {
            r.day_pos[index] = with_bit(r.day_pos[index], 0i64)
        } else if ordinal > 0i64 {
            r.day_pos[index] = with_bit(r.day_pos[index], ordinal)
        } else {
            r.day_neg[index] = with_bit(r.day_neg[index], 0i64 - ordinal)
        }
        r.any_day = true
        at = next + 2usize
        if at < value.len {
            if value[at] != 44u8 || at + 1usize == value.len { ret Invalid }
            at += 1usize
        }
    }
    ret ok
}

fn parse_signed_list(value: str, lo: i64, hi: i64, out: []i64, n: *usize) -> err {
    var at = 0usize
    if value.len == 0usize { ret Invalid }
    while at < value.len {
        let (v, after, good) = read_int(value, at)
        var magnitude = v
        if v < 0i64 { magnitude = 0i64 - v }
        if !good || magnitude < lo || magnitude > hi || *n == out.len { ret Invalid }
        out[*n] = v
        *n += 1usize
        at = after
        if at < value.len {
            if value[at] != 44u8 || at + 1usize == value.len { ret Invalid }
            at += 1usize
        }
    }
    ret ok
}

fn freq_code(s: str) -> i64 {
    if upper_eq(s, "YEARLY") { ret 0i64 }
    if upper_eq(s, "MONTHLY") { ret 1i64 }
    if upper_eq(s, "WEEKLY") { ret 2i64 }
    if upper_eq(s, "DAILY") { ret 3i64 }
    if upper_eq(s, "HOURLY") { ret 4i64 }
    if upper_eq(s, "MINUTELY") { ret 5i64 }
    if upper_eq(s, "SECONDLY") { ret 6i64 }
    ret -1i64
}

fn parse_rule(text: str) -> (Rule, err) {
    var r: Rule = zero
    r.interval = 1i64
    var body = text
    if body.len > 6usize && upper_eq(body[0usize..6usize], "RRULE:") { body = body[6usize..body.len] }
    var seen_freq = false
    var at = 0usize
    while at <= body.len {
        var end = at
        while end < body.len && body[end] != 59u8 { end += 1usize }
        let part = body[at..end]
        if part.len > 0usize {
            var eq_at = 0usize
            while eq_at < part.len && part[eq_at] != 61u8 { eq_at += 1usize }
            if eq_at == part.len || eq_at + 1usize == part.len { ret (zero, Invalid) }
            let key = part[0usize..eq_at]
            let value = part[eq_at + 1usize..part.len]
            if upper_eq(key, "FREQ") {
                seen_freq = true
                let code = freq_code(value)
                if code < 0i64 { ret (zero, Invalid) }
                r.freq = u8(code)
            } else if upper_eq(key, "INTERVAL") {
                let (n, after, good) = read_int(value, 0usize)
                if !good || after != value.len || n < 1i64 || n > 1000000i64 { ret (zero, Invalid) }
                r.interval = n
            } else if upper_eq(key, "COUNT") {
                let (n, after, good) = read_int(value, 0usize)
                if !good || after != value.len || n < 1i64 { ret (zero, Invalid) }
                r.count = n
            } else if upper_eq(key, "UNTIL") {
                let (stamp, stamp_error) = parse_stamp(value)
                if stamp_error != ok { ret (zero, Invalid) }
                r.until = stamp
                r.has_until = true
            } else if upper_eq(key, "WKST") {
                let wd = weekday_code(value)
                if wd < 0i64 { ret (zero, Invalid) }
                r.wkst = wd
            } else if upper_eq(key, "BYMONTH") {
                var none: u64 = 0u64
                if parse_list(value, 1i64, 12i64, false, &r.months, &none) != ok { ret (zero, Invalid) }
            } else if upper_eq(key, "BYMONTHDAY") {
                if parse_list(value, 1i64, 31i64, true, &r.mday_pos, &r.mday_neg) != ok { ret (zero, Invalid) }
            } else if upper_eq(key, "BYDAY") {
                if parse_byday(value, &r) != ok { ret (zero, Invalid) }
            } else if upper_eq(key, "BYHOUR") {
                if parse_list_range(value, 0i64, 23i64, &r.hours) != ok { ret (zero, Invalid) }
            } else if upper_eq(key, "BYMINUTE") {
                if parse_list_range(value, 0i64, 59i64, &r.minutes) != ok { ret (zero, Invalid) }
            } else if upper_eq(key, "BYSECOND") {
                if parse_list_range(value, 0i64, 59i64, &r.seconds) != ok { ret (zero, Invalid) }
            } else if upper_eq(key, "BYYEARDAY") {
                if parse_signed_list(value, 1i64, 366i64, r.yday[0usize..32usize], &r.yday_n) != ok { ret (zero, Invalid) }
            } else if upper_eq(key, "BYSETPOS") {
                if parse_signed_list(value, 1i64, 366i64, r.setpos[0usize..32usize], &r.setpos_n) != ok { ret (zero, Invalid) }
            } else {
                ret (zero, Invalid)
            }
        }
        at = end + 1usize
    }
    if !seen_freq { ret (zero, Invalid) }
    if r.any_day && r.freq != MONTHLY && r.freq != YEARLY {
        var d = 0usize
        while d < 7usize {
            if r.day_pos[d] > 1u64 || r.day_neg[d] != 0u64 { ret (zero, Invalid) }
            d += 1usize
        }
    }
    ret (r, ok)
}

// A plain list of values in a range (zero allowed), as one mask.
fn parse_list_range(value: str, lo: i64, hi: i64, mask: *u64) -> err {
    var at = 0usize
    if value.len == 0usize { ret Invalid }
    while at < value.len {
        let (n, after, good) = read_int(value, at)
        if !good || n < lo || n > hi { ret Invalid }
        *mask = with_bit(*mask, n)
        at = after
        if at < value.len {
            if value[at] != 44u8 || at + 1usize == value.len { ret Invalid }
            at += 1usize
        }
    }
    ret ok
}

fn popcount(mask: u64) -> i64 {
    var n = 0i64
    var m = mask
    while m != 0u64 {
        n += 1i64
        m = m & (m - 1u64)
    }
    ret n
}

// The n-th (0-based) set bit's position, ascending.
fn nth_bit(mask: u64, n: i64) -> i64 {
    var left = n
    var pos = 0i64
    while pos < 64i64 {
        if bit_set(mask, pos) {
            if left == 0i64 { ret pos }
            left -= 1i64
        }
        pos += 1i64
    }
    ret 0i64
}

fn day_passes(r: Rule, day: i64) -> bool {
    let (year, month, dom) = time.civil_from_days(day)
    if r.months != 0u64 && !bit_set(r.months, month) { ret false }
    let year_start = time.days_from_civil(year, 1i64, 1i64)
    let doy = day - year_start + 1i64
    var year_len = 365i64
    if time.is_leap(year) { year_len = 366i64 }
    let month_len = time.days_in_month(year, month)
    if r.yday_n > 0usize {
        var hit = false
        var i = 0usize
        while i < r.yday_n {
            let v = r.yday[i]
            if v > 0i64 && v == doy { hit = true }
            if v < 0i64 && v == doy - year_len - 1i64 { hit = true }
            i += 1usize
        }
        if !hit { ret false }
    }
    if (r.mday_pos | r.mday_neg) != 0u64 {
        if !bit_set(r.mday_pos, dom) && !bit_set(r.mday_neg, month_len - dom + 1i64) { ret false }
    }
    if r.any_day {
        let wd = calendar.weekday_index(calendar.weekday_of_count(day))
        let index = usize(wd)
        if !bit_set(r.day_pos[index], 0i64) {
            var rel_pos = doy
            var rel_len = year_len
            if r.freq == MONTHLY || (r.freq == YEARLY && r.months != 0u64) {
                rel_pos = dom
                rel_len = month_len
            }
            let from_start = (rel_pos - 1i64) / 7i64 + 1i64
            let from_end = (rel_len - rel_pos) / 7i64 + 1i64
            if !bit_set(r.day_pos[index], from_start) && !bit_set(r.day_neg[index], from_end) { ret false }
        }
    }
    ret true
}

fn stamp_of(day: i64, hour: i64, minute: i64, second: i64) -> calendar.DateTime {
    var out: calendar.DateTime = zero
    out.date = calendar.date_of(day)
    out.time.hour = u8(hour)
    out.time.minute = u8(minute)
    out.time.second = u8(second)
    ret out
}

// Expands the rule from `start`, writing the occurrences at or after `from` into
// `out` until it is full, COUNT or UNTIL ends the rule, or the search bound is met.
// Returns how many were written.
fn expand_from(rule: Rule, start: calendar.DateTime, from: calendar.DateTime, out: []calendar.DateTime) -> (usize, err) {
    if !calendar.valid_date(start.date) || !calendar.valid_time(start.time) { ret (0usize, Invalid) }
    var r = rule
    let start_day = calendar.day_count(start.date)
    let start_h = i64(start.time.hour)
    let start_m = i64(start.time.minute)
    let start_s = i64(start.time.second)
    let start_seconds = start_day * 86400i64 + start_h * 3600i64 + start_m * 60i64 + start_s
    if !r.any_day && r.yday_n == 0usize && r.mday_pos == 0u64 && r.mday_neg == 0u64 {
        if r.freq == YEARLY {
            if r.months == 0u64 { r.months = with_bit(0u64, i64(start.date.month)) }
            r.mday_pos = with_bit(0u64, i64(start.date.day))
        } else if r.freq == MONTHLY {
            r.mday_pos = with_bit(0u64, i64(start.date.day))
        } else if r.freq == WEEKLY {
            let wd = usize(calendar.weekday_index(calendar.weekday_of_count(start_day)))
            r.day_pos[wd] = with_bit(0u64, 0i64)
            r.any_day = true
        }
    }
    var hours = r.hours
    var minutes = r.minutes
    var seconds = r.seconds
    if r.freq < HOURLY && hours == 0u64 { hours = with_bit(0u64, start_h) }
    if r.freq < MINUTELY && minutes == 0u64 { minutes = with_bit(0u64, start_m) }
    if r.freq < SECONDLY && seconds == 0u64 { seconds = with_bit(0u64, start_s) }
    let wk_offset = time.floor_mod(calendar.weekday_index(calendar.weekday_of_count(start_day)) - r.wkst, 7i64)
    let week0 = start_day - wk_offset
    let start_months = i64(start.date.year) * 12i64 + i64(start.date.month) - 1i64
    var days: [400]i64 = zero
    var written = 0usize
    var emitted = 0i64
    var k = 0i64
    var steps = 0i64
    while true {
        steps += 1i64
        if steps > 4000000i64 { break }
        var nd = 0usize
        var h_mask = hours
        var m_mask = minutes
        var s_mask = seconds
        var period_ok = true
        if r.freq == YEARLY {
            let year = i64(start.date.year) + k * r.interval
            if year > 9999i64 { break }
            let first = time.days_from_civil(year, 1i64, 1i64)
            var len = 365i64
            if time.is_leap(year) { len = 366i64 }
            var d = 0i64
            while d < len {
                if day_passes(r, first + d) {
                    days[nd] = first + d
                    nd += 1usize
                }
                d += 1i64
            }
        } else if r.freq == MONTHLY {
            let total = start_months + k * r.interval
            let year = total / 12i64
            if year > 9999i64 { break }
            let month = total % 12i64 + 1i64
            let first = time.days_from_civil(year, month, 1i64)
            let len = time.days_in_month(year, month)
            var d = 0i64
            while d < len {
                if day_passes(r, first + d) {
                    days[nd] = first + d
                    nd += 1usize
                }
                d += 1i64
            }
        } else if r.freq == WEEKLY {
            let first = week0 + k * r.interval * 7i64
            if first > 2932896i64 { break }
            var d = 0i64
            while d < 7i64 {
                if day_passes(r, first + d) {
                    days[nd] = first + d
                    nd += 1usize
                }
                d += 1i64
            }
        } else if r.freq == DAILY {
            let day = start_day + k * r.interval
            if day > 2932896i64 { break }
            if day_passes(r, day) {
                days[0usize] = day
                nd = 1usize
            }
        } else {
            var unit = 3600i64
            if r.freq == MINUTELY { unit = 60i64 }
            if r.freq == SECONDLY { unit = 1i64 }
            let moment = (start_seconds + k * r.interval * unit) / unit * unit
            let day = time.floor_div(moment, 86400i64)
            if day > 2932896i64 { break }
            let within = moment - day * 86400i64
            let hour = within / 3600i64
            let minute = within / 60i64 % 60i64
            let second = within % 60i64
            if day_passes(r, day) {
                days[0usize] = day
                nd = 1usize
            }
            h_mask = hours
            if r.freq >= HOURLY {
                if hours != 0u64 && !bit_set(hours, hour) { period_ok = false }
                h_mask = with_bit(0u64, hour)
            }
            if r.freq >= MINUTELY {
                if minutes != 0u64 && !bit_set(minutes, minute) { period_ok = false }
                m_mask = with_bit(0u64, minute)
            } else if minutes == 0u64 {
                m_mask = with_bit(0u64, start_m)
            }
            if r.freq >= SECONDLY {
                if seconds != 0u64 && !bit_set(seconds, second) { period_ok = false }
                s_mask = with_bit(0u64, second)
            } else if seconds == 0u64 {
                s_mask = with_bit(0u64, start_s)
            }
        }
        k += 1i64
        if !period_ok || nd == 0usize { continue }
        let nh = popcount(h_mask)
        let nm = popcount(m_mask)
        let ns = popcount(s_mask)
        let per_day = nh * nm * ns
        let total = i64(nd) * per_day
        // The positions this period yields, ascending: every one, or the BYSETPOS ones.
        var picks: [32]i64 = zero
        var pick_n = 0usize
        if r.setpos_n > 0usize {
            var i = 0usize
            while i < r.setpos_n {
                var index = r.setpos[i] - 1i64
                if r.setpos[i] < 0i64 { index = total + r.setpos[i] }
                if index >= 0i64 && index < total {
                    var dup = false
                    var j = 0usize
                    while j < pick_n {
                        if picks[j] == index { dup = true }
                        j += 1usize
                    }
                    if !dup {
                        picks[pick_n] = index
                        pick_n += 1usize
                    }
                }
                i += 1usize
            }
            var a = 1usize
            while a < pick_n {
                var b = a
                while b > 0usize && picks[b - 1usize] > picks[b] {
                    let swap = picks[b]
                    picks[b] = picks[b - 1usize]
                    picks[b - 1usize] = swap
                    b -= 1usize
                }
                a += 1usize
            }
        }
        var position = 0i64
        var pick_at = 0usize
        while true {
            var index = position
            if r.setpos_n > 0usize {
                if pick_at >= pick_n { break }
                index = picks[pick_at]
                pick_at += 1usize
            } else {
                if position >= total { break }
                position += 1i64
            }
            let day_index = index / per_day
            let rest = index % per_day
            let hour = nth_bit(h_mask, rest / (nm * ns))
            let minute = nth_bit(m_mask, rest / ns % nm)
            let second = nth_bit(s_mask, rest % ns)
            let stamp = stamp_of(days[usize(day_index)], hour, minute, second)
            if r.has_until && calendar.compare(stamp, r.until) > 0i32 { ret (written, ok) }
            if calendar.compare(stamp, start) < 0i32 { continue }
            if r.count > 0i64 && emitted >= r.count { ret (written, ok) }
            emitted += 1i64
            if calendar.compare(stamp, from) >= 0i32 {
                out[written] = stamp
                written += 1usize
                if written == out.len { ret (written, ok) }
            }
        }
        if r.count > 0i64 && emitted >= r.count { break }
    }
    ret (written, ok)
}

fn expand(rule: Rule, start: calendar.DateTime, out: []calendar.DateTime) -> (usize, err) {
    let (n, expand_error) = expand_from(rule, start, start, out)
    ret (n, expand_error)
}
