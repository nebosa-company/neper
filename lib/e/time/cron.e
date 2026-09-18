// Six-field cron schedules: second, minute, hour, day of month, month and day of
// week. Fields accept `*`, lists, inclusive ranges and `/step`; numbers only. Sunday
// is 0 or 7. When both day fields are restricted, either may match (Vixie cron).

use e.mem
use e.time

type Schedule = struct { seconds: u64, minutes: u64, hours: u32, doms: u32, months: u16, dows: u8, dom_restricted: bool, dow_restricted: bool, offset_minutes: i32 }
error Invalid

const SECOND: i64 = 1000000000i64
const MINUTE: i64 = 60000000000i64
const DAY: i64 = 86400000000000i64
const MAX_I64: i64 = 9223372036854775807i64
const MIN_I64: i64 = -9223372036854775807i64 - 1i64

fn number(text: str, at: usize) -> (u32, usize, err) {
    if at >= text.len || text[at] < 48u8 || text[at] > 57u8 { ret (0u32, at, Invalid) }
    var value = 0u32
    var end = at
    while end < text.len && text[end] >= 48u8 && text[end] <= 57u8 {
        let digit = u32(text[end] - 48u8)
        if value > 429496729u32 || (value == 429496729u32 && digit > 5u32) { ret (0u32, at, Invalid) }
        value = value * 10u32 + digit
        end += 1usize
    }
    ret (value, end, ok)
}

fn field(text: str, minimum: u32, maximum: u32, sunday: bool) -> (u64, bool, err) {
    if text.len == 0usize { ret (0u64, false, Invalid) }
    var bits = 0u64
    var at = 0usize
    while at < text.len {
        var first = minimum
        var last = maximum
        if text[at] == 42u8 {
            at += 1usize
        } else {
            let (parsed, after, parse_error) = number(text, at)
            if parse_error != ok { ret (0u64, false, Invalid) }
            first = parsed
            last = parsed
            at = after
            if at < text.len && text[at] == 45u8 {
                let (range_end, after_range, range_error) = number(text, at + 1usize)
                if range_error != ok { ret (0u64, false, Invalid) }
                last = range_end
                at = after_range
            }
        }
        if first < minimum || first > maximum || last < minimum || last > maximum || first > last { ret (0u64, false, Invalid) }
        var step = 1u32
        if at < text.len && text[at] == 47u8 {
            let (parsed_step, after_step, step_error) = number(text, at + 1usize)
            if step_error != ok || parsed_step == 0u32 { ret (0u64, false, Invalid) }
            step = parsed_step
            at = after_step
        }
        var value = first
        while value <= last {
            var bit = value
            if sunday && value == 7u32 { bit = 0u32 }
            bits |= 1u64 << bit
            if last - value < step { break }
            value += step
        }
        if at == text.len { break }
        if text[at] != 44u8 { ret (0u64, false, Invalid) }
        at += 1usize
        if at == text.len { ret (0u64, false, Invalid) }
    }
    ret (bits, !(text.len == 1usize && text[0usize] == 42u8), ok)
}

fn parse(a: *mem.Arena, expr: str, offset_minutes: i32) -> (Schedule, err) {
    if offset_minutes < -1439i32 || offset_minutes > 1439i32 { ret (zero, Invalid) }
    var parts: [6]str = zero
    var count = 0usize
    var at = 0usize
    while at < expr.len {
        while at < expr.len && (expr[at] == 32u8 || expr[at] == 9u8) { at += 1usize }
        if at == expr.len { break }
        if count == parts.len { ret (zero, Invalid) }
        let start = at
        while at < expr.len && expr[at] != 32u8 && expr[at] != 9u8 { at += 1usize }
        parts[count] = expr[start..at]
        count += 1usize
    }
    if count != 6usize { ret (zero, Invalid) }
    let (seconds, _, second_error) = field(parts[0usize], 0u32, 59u32, false)
    let (minutes, _, minute_error) = field(parts[1usize], 0u32, 59u32, false)
    let (hours, _, hour_error) = field(parts[2usize], 0u32, 23u32, false)
    let (doms, dom_restricted, dom_error) = field(parts[3usize], 1u32, 31u32, false)
    let (months, _, month_error) = field(parts[4usize], 1u32, 12u32, false)
    let (dows, dow_restricted, dow_error) = field(parts[5usize], 0u32, 7u32, true)
    if second_error != ok || minute_error != ok || hour_error != ok || dom_error != ok || month_error != ok || dow_error != ok { ret (zero, Invalid) }
    ret (Schedule { seconds: seconds, minutes: minutes, hours: u32(hours), doms: u32(doms), months: u16(months), dows: u8(dows), dom_restricted: dom_restricted, dow_restricted: dow_restricted, offset_minutes: offset_minutes }, ok)
}

fn floor_div(value: i64, divisor: i64) -> i64 {
    var adjusted = value
    if value < 0i64 { adjusted = value - (divisor - 1i64) }
    ret adjusted / divisor
}

fn matches(s: Schedule, t: time.Timestamp) -> bool {
    let clock = time.to_time_at(t, s.offset_minutes)
    let date = time.to_date_at(t, s.offset_minutes)
    if (s.seconds & (1u64 << u32(clock.second))) == 0u64 || (s.minutes & (1u64 << u32(clock.minute))) == 0u64 || (s.hours & (1u32 << u32(clock.hour))) == 0u32 || (s.months & (1u16 << u16(date.month))) == 0u16 { ret false }
    let offset = i64(s.offset_minutes) * MINUTE
    if (offset > 0i64 && t.nanos > MAX_I64 - offset) || (offset < 0i64 && t.nanos < MIN_I64 - offset) { ret false }
    let local = t.nanos + offset
    var weekday = (floor_div(local, DAY) + 4i64) % 7i64
    if weekday < 0i64 { weekday += 7i64 }
    let dom_match = (s.doms & (1u32 << u32(date.day))) != 0u32
    let dow_match = (s.dows & (1u8 << u8(weekday))) != 0u8
    if s.dom_restricted && s.dow_restricted { ret dom_match || dow_match }
    if s.dom_restricted { ret dom_match }
    if s.dow_restricted { ret dow_match }
    ret true
}

fn next(s: Schedule, after: time.Timestamp) -> (time.Timestamp, err) {
    if after.nanos > MAX_I64 - SECOND { ret (zero, Invalid) }
    let first = floor_div(after.nanos, SECOND) * SECOND + SECOND
    let offset = i64(s.offset_minutes) * MINUTE
    if (offset > 0i64 && first > MAX_I64 - offset) || (offset < 0i64 && first < MIN_I64 - offset) { ret (zero, Invalid) }
    let first_day = floor_div(first + offset, DAY)
    var day_offset = 0i64
    while day_offset < 146097i64 {
        let day_number = first_day + day_offset
        if day_number < -106751i64 {
            day_offset += 1i64
            continue
        }
        if day_number > 106750i64 { break }
        let local_midnight = day_number * DAY
        if (offset > 0i64 && local_midnight < MIN_I64 + offset) || (offset < 0i64 && local_midnight > MAX_I64 + offset) { break }
        let utc_midnight = local_midnight - offset
        if utc_midnight > MAX_I64 - DAY { break }
        let day_probe = time.Timestamp { nanos: utc_midnight }
        let date = time.to_date_at(day_probe, s.offset_minutes)
        if (s.months & (1u16 << u16(date.month))) != 0u16 {
            var weekday = (day_number + 4i64) % 7i64
            if weekday < 0i64 { weekday += 7i64 }
            let dom_match = (s.doms & (1u32 << u32(date.day))) != 0u32
            let dow_match = (s.dows & (1u8 << u8(weekday))) != 0u8
            var day_match = true
            if s.dom_restricted && s.dow_restricted { day_match = dom_match || dow_match }
            if s.dom_restricted && !s.dow_restricted { day_match = dom_match }
            if !s.dom_restricted && s.dow_restricted { day_match = dow_match }
            if day_match {
                var hour = 0u32
                while hour < 24u32 {
                    if (s.hours & (1u32 << hour)) != 0u32 {
                        var minute = 0u32
                        while minute < 60u32 {
                            if (s.minutes & (1u64 << minute)) != 0u64 {
                                var second = 0u32
                                while second < 60u32 {
                                    if (s.seconds & (1u64 << second)) != 0u64 {
                                        let candidate = utc_midnight + i64(hour) * 3600i64 * SECOND + i64(minute) * 60i64 * SECOND + i64(second) * SECOND
                                        if candidate >= first { ret (time.Timestamp { nanos: candidate }, ok) }
                                    }
                                    second += 1u32
                                }
                            }
                            minute += 1u32
                        }
                    }
                    hour += 1u32
                }
            }
        }
        day_offset += 1i64
    }
    ret (zero, Invalid)
}
