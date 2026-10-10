// Time-based triggers (L035), after appdor's `src/workflow/schedule.js`: five-field cron parsed and matched against a
// named zone's wall clock (a time the clock skips does not fire, a time it repeats fires once, at its first
// reading), the three authoring forms (interval, daily/weekly/monthly, cron) normalized to one runtime schedule,
// next-fire previews, the missed-fire policies (one catch-up, skip, all) with their bounded burst, the shared fire
// plan a worker claims, the single-concurrency overlap decision with its stale-run escape, write-once occurrence
// stamps for date-approaching triggers, duration-in-state tracking and a cursor-continued scheduled scan.
//
// Instants are epoch milliseconds in an `f64`, as appdor's; the clock is a parameter. Zones are `e.tz`'s builtin
// pack: a name outside it is an unknown zone, and so is any name `Intl` would also refuse.
//
// Differences from appdor's: the error texts are the catalogue keys humanized ("Invalid cron"), which is what
// appdor's return with no bundle loaded; a cron expression is a text, never another type.

use e.algo.formula as f
use e.algo.view as view
use e.math
use e.mem
use e.str
use e.text.utf8 as utf8
use e.tz as tz

const DAY_MS: i64 = 86400000i64
const MAX_CATCH_UP_FIRES: usize = 1000usize

fn floor_div(x: i64, y: i64) -> i64 {
    var q = x / y
    if (x % y != 0i64) && ((x < 0i64) != (y < 0i64)) { q -= 1i64 }
    ret q
}

fn is_finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

// The days from 1970-01-01 to a civil date.
fn civil_days(year: i64, month: i64, day: i64) -> i64 {
    var y = year
    if month <= 2i64 { y -= 1i64 }
    let era = floor_div(y, 400i64)
    let yoe = y - era * 400i64
    var mp = month - 3i64
    if month <= 2i64 { mp = month + 9i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + day - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

fn civil_year(days: i64) -> i64 {
    let z = days + 719468i64
    let era = floor_div(z, 146097i64)
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    let y = yoe + era * 400i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    var month = mp + 3i64
    if mp >= 10i64 { month = mp - 9i64 }
    if month <= 2i64 { ret y + 1i64 }
    ret y
}

fn civil_month(days: i64) -> i64 {
    let z = days + 719468i64
    let era = floor_div(z, 146097i64)
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    if mp < 10i64 { ret mp + 3i64 }
    ret mp - 9i64
}

fn civil_day(days: i64) -> i64 {
    let z = days + 719468i64
    let era = floor_div(z, 146097i64)
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    ret doy - (153i64 * mp + 2i64) / 5i64 + 1i64
}

fn days_in_month(year: i64, month: i64) -> i64 {
    var next_year = year
    var next_month = month + 1i64
    if next_month == 13i64 {
        next_month = 1i64
        next_year += 1i64
    }
    ret civil_days(next_year, next_month, 1i64) - civil_days(year, month, 1i64)
}

// 0 is Sunday, as `getUTCDay`.
fn weekday_of(days: i64) -> i64 {
    var w = (days + 4i64) % 7i64
    if w < 0i64 { w += 7i64 }
    ret w
}

// --- cron ---------------------------------------------------------------------------------------------------------

// Each field is a set of its values as bits; `dom_wild` and `dow_wild` are "the field text starts with `*`".
type Cron = struct { minute: u64, hour: u32, dom: u32, month: u32, dow: u32, dom_wild: bool, dow_wild: bool }

fn upper_ascii(c: u8) -> u8 {
    if c >= 97u8 && c <= 122u8 { ret c - 32u8 }
    ret c
}

fn name_equals(token: str, name: str) -> bool {
    if token.len != name.len { ret false }
    var i = 0usize
    while i < token.len {
        if upper_ascii(token[i]) != name[i] { ret false }
        i += 1usize
    }
    ret true
}

fn day_names() -> str { ret "SUNMONTUEWEDTHUFRISAT" }
fn month_names() -> str { ret "JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC" }

// The index of a three-letter name in a packed table, or -1.
fn name_index(token: str, table: str) -> i64 {
    var i = 0usize
    while i * 3usize < table.len {
        if name_equals(token, table[i * 3usize..i * 3usize + 3usize]) { ret i64(i) }
        i += 1usize
    }
    ret -1i64
}

// One endpoint of a range: a number, or a name from the table (`min` the value of its first entry). -1 when it
// is neither; a number is a safe integer of plain digits.
fn endpoint(token: str, table: str, has_names: bool, min: i64) -> i64 {
    if has_names {
        let at = name_index(token, table)
        if at >= 0i64 { ret at + min }
    }
    if token.len == 0usize { ret -1i64 }
    var i = 0usize
    while i < token.len {
        if token[i] < 48u8 || token[i] > 57u8 { ret -1i64 }
        i += 1usize
    }
    var first = 0usize
    while first + 1usize < token.len && token[first] == 48u8 { first += 1usize }
    let digits = token[first..token.len]
    if digits.len > 16usize { ret -1i64 }
    if digits.len == 16usize && str.compare(digits, "9007199254740991") > 0i32 { ret -1i64 }
    var value = 0i64
    i = 0usize
    while i < digits.len {
        value = value * 10i64 + i64(digits[i] - 48u8)
        i += 1usize
    }
    ret value
}

// The values of a field as bits, or false: lists, ranges, steps and names.
fn parse_field(spec: str, min: i64, max: i64, table: str, has_names: bool) -> (u64, bool) {
    var out = 0u64
    var start = 0usize
    var i = 0usize
    while i <= spec.len {
        if i == spec.len || spec[i] == 44u8 {
            let part = spec[start..i]
            if part.len == 0usize { ret (0u64, false) }
            // Split on `/`: at most one step.
            var slash = part.len
            var slashes = 0usize
            var j = 0usize
            while j < part.len {
                if part[j] == 47u8 {
                    if slashes == 0usize { slash = j }
                    slashes += 1usize
                }
                j += 1usize
            }
            if slashes > 1usize { ret (0u64, false) }
            let range = part[0usize..slash]
            var step = 1i64
            if slashes == 1usize {
                step = endpoint(part[slash + 1usize..part.len], "", false, 0i64)
                if step < 1i64 { ret (0u64, false) }
            }
            var lo = 0i64
            var hi = 0i64
            if str.eq(range, "*") {
                lo = min
                hi = max
            } else {
                var dash = range.len
                var dashes = 0usize
                j = 0usize
                while j < range.len {
                    if range[j] == 45u8 {
                        if dashes == 0usize { dash = j }
                        dashes += 1usize
                    }
                    j += 1usize
                }
                if dashes > 1usize { ret (0u64, false) }
                if dashes == 1usize {
                    lo = endpoint(range[0usize..dash], table, has_names, min)
                    hi = endpoint(range[dash + 1usize..range.len], table, has_names, min)
                } else {
                    lo = endpoint(range, table, has_names, min)
                    hi = lo
                }
            }
            if lo < 0i64 || hi < 0i64 || lo < min || hi > max || lo > hi { ret (0u64, false) }
            var v = lo
            while v <= hi {
                out = out | (1u64 << u64(v))
                v += step
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret (out, true)
}

// The fields of a cron expression split on white space (JavaScript's), at most six kept so a long one counts as
// not five.
fn split_fields(s: str, out: []str) -> usize {
    var n = 0usize
    var start = 0usize
    var in_field = false
    var it = utf8.iterator(s)
    var at = 0usize
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            var width = 1usize
            if scalar >= 65536u32 { width = 4usize } else if scalar >= 2048u32 { width = 3usize } else if scalar >= 128u32 { width = 2usize }
            if view.js_space(scalar) {
                if in_field {
                    if n < out.len { out[n] = s[start..at] }
                    n += 1usize
                    in_field = false
                }
            } else if !in_field {
                in_field = true
                start = at
            }
            at += width
        }
    }
    if in_field {
        if n < out.len { out[n] = s[start..s.len] }
        n += 1usize
    }
    ret n
}

// A five-field cron expression: minute, hour, day of month, month, day of week.
fn parse_cron(expr: str) -> (Cron, bool) {
    var empty = Cron { minute: 0u64, hour: 0u32, dom: 0u32, month: 0u32, dow: 0u32, dom_wild: false, dow_wild: false }
    var parts: [6]str = zero
    let n = split_fields(expr, parts[0usize..6usize])
    if n != 5usize { ret (empty, false) }
    let (minute, ok_minute) = parse_field(parts[0usize], 0i64, 59i64, "", false)
    let (hour, ok_hour) = parse_field(parts[1usize], 0i64, 23i64, "", false)
    let (dom, ok_dom) = parse_field(parts[2usize], 1i64, 31i64, "", false)
    let (month, ok_month) = parse_field(parts[3usize], 1i64, 12i64, month_names(), true)
    let (dow, ok_dow) = parse_field(parts[4usize], 0i64, 6i64, day_names(), true)
    if !ok_minute || !ok_hour || !ok_dom || !ok_month || !ok_dow { ret (empty, false) }
    let c = Cron {
        minute: minute, hour: u32(hour), dom: u32(dom), month: u32(month), dow: u32(dow),
        dom_wild: parts[2usize].len > 0usize && parts[2usize][0usize] == 42u8,
        dow_wild: parts[4usize].len > 0usize && parts[4usize][0usize] == 42u8,
    }
    ret (c, true)
}

// --- zones --------------------------------------------------------------------------------------------------------

// A zone name is "" or `UTC` (no conversion) or one in the builtin pack.
type Clock = struct { db: tz.Database }

fn new_clock(a: *mem.Arena) -> (Clock, err) {
    let (db, e) = tz.builtin(a)
    ret (Clock { db: db }, e)
}

fn is_utc(name: str) -> bool { ret name.len == 0usize || str.eq(name, "UTC") }

fn is_known_timezone(c: *const Clock, name: str) -> bool {
    if is_utc(name) { ret true }
    let (z, e) = tz.zone(&c.db, name)
    ret e == ok
}

fn offset_seconds(c: *const Clock, name: str, seconds: i64) -> i64 {
    if is_utc(name) { ret 0i64 }
    let (z, e) = tz.zone(&c.db, name)
    if e != ok { ret 0i64 }
    let data = mem.cast[*const tz.ZoneData](z.state)
    ret i64(tz.offset_at_seconds(data, seconds).seconds)
}

// The instant as whole milliseconds (`new Date(ms)` truncates).
fn ms_int(ms: f64) -> i64 { ret i64(math.trunc[f64](ms)) }

type Wall = struct { year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, weekday: i64 }

// The wall-clock fields an observer in `name` reads at the instant.
fn wall_clock(c: *const Clock, ms: f64, name: str) -> Wall {
    let t = ms_int(ms)
    let seconds = floor_div(t, 1000i64)
    let local = seconds + offset_seconds(c, name, seconds)
    let days = floor_div(local, 86400i64)
    let in_day = local - days * 86400i64
    ret Wall {
        year: civil_year(days), month: civil_month(days), day: civil_day(days), hour: in_day / 3600i64,
        minute: (in_day % 3600i64) / 60i64, second: in_day % 60i64, weekday: weekday_of(days),
    }
}

// How far ahead of UTC the zone's wall clock is at the instant, in milliseconds.
fn zone_offset_ms(c: *const Clock, ms: f64, name: str) -> i64 {
    if is_utc(name) { ret 0i64 }
    let seconds = floor_div(ms_int(ms), 1000i64)
    ret offset_seconds(c, name, seconds) * 1000i64
}

// The instants (up to three) at which the zone's clock reads the date and time, ascending: none for a time inside a
// spring-forward gap, two for one in a fall-back overlap.
type Instants = struct { count: usize, at: [3]i64 }

fn wall_to_instants(c: *const Clock, year: i64, month: i64, day: i64, hour: i64, minute: i64, name: str) -> Instants {
    var out = Instants { count: 0usize, at: zero }
    let goal = civil_days(year, month, day) * DAY_MS + (hour * 60i64 + minute) * 60000i64
    if is_utc(name) {
        out.at[0usize] = goal
        out.count = 1usize
        ret out
    }
    var probes: [3]i64 = zero
    probes[0usize] = goal - DAY_MS
    probes[1usize] = goal
    probes[2usize] = goal + DAY_MS
    var p = 0usize
    while p < 3usize {
        let ts = goal - zone_offset_ms(c, f64(probes[p]), name)
        var seen = false
        var k = 0usize
        while k < out.count {
            if out.at[k] == ts { seen = true }
            k += 1usize
        }
        if !seen {
            let w = wall_clock(c, f64(ts), name)
            if w.year == year && w.month == month && w.day == day && w.hour == hour && w.minute == minute {
                out.at[out.count] = ts
                out.count += 1usize
            }
        }
        p += 1usize
    }
    // Ascending.
    var i = 1usize
    while i < out.count {
        var j = i
        while j > 0usize && out.at[j - 1usize] > out.at[j] {
            let swap = out.at[j]
            out.at[j] = out.at[j - 1usize]
            out.at[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
    ret out
}

fn day_matches(c: Cron, dom: i64, dow: i64) -> bool {
    let date_matches = (c.dom >> u32(dom)) & 1u32 == 1u32
    let weekday_matches = (c.dow >> u32(dow)) & 1u32 == 1u32
    if c.dom_wild || c.dow_wild { ret date_matches && weekday_matches }
    ret date_matches || weekday_matches
}

// The next fire strictly after `from_ms` for a parsed cron, in the zone (UTC when empty); `false` when none exists
// within a Gregorian cycle (an impossible date) or the zone is unknown.
fn next_cron_fire(c: *const Clock, cron: Cron, from_ms: f64, name: str) -> (f64, bool) {
    if !is_finite(from_ms) || !is_known_timezone(c, name) { ret (0.0f64, false) }
    let start = wall_clock(c, from_ms, name)
    var y = start.year
    while y <= start.year + 400i64 {
        var mo = 1i64
        while mo <= 12i64 {
            if (cron.month >> u32(mo)) & 1u32 == 0u32 || (y == start.year && mo < start.month) {
                mo += 1i64
                continue
            }
            let last_day = days_in_month(y, mo)
            var first_day = 1i64
            if y == start.year && mo == start.month { first_day = start.day }
            var d = first_day
            while d <= last_day {
                if day_matches(cron, d, weekday_of(civil_days(y, mo, d))) {
                    let same_day = y == start.year && mo == start.month && d == start.day
                    var h = 0i64
                    while h < 24i64 {
                        if (cron.hour >> u32(h)) & 1u32 == 1u32 && !(same_day && h < start.hour) {
                            var mi = 0i64
                            while mi < 60i64 {
                                if (cron.minute >> u64(mi)) & 1u64 == 1u64 && !(same_day && h == start.hour && mi < start.minute) {
                                    let inst = wall_to_instants(c, y, mo, d, h, mi, name)
                                    if inst.count > 0usize && f64(inst.at[0usize]) > from_ms { ret (f64(inst.at[0usize]), true) }
                                }
                                mi += 1i64
                            }
                        }
                        h += 1i64
                    }
                }
                d += 1i64
            }
            mo += 1i64
        }
        y += 1i64
    }
    ret (0.0f64, false)
}

// The latest occurrence at or before `now_ms`, with the same zone policy.
fn previous_cron_fire(c: *const Clock, cron: Cron, now_ms: f64, name: str) -> (f64, bool) {
    if !is_finite(now_ms) || !is_known_timezone(c, name) { ret (0.0f64, false) }
    let start = wall_clock(c, now_ms, name)
    let base = ms_int(now_ms)
    var upper_offset = zone_offset_ms(c, now_ms - 86400000.0f64, name)
    let here = zone_offset_ms(c, now_ms, name)
    let after = zone_offset_ms(c, now_ms + 86400000.0f64, name)
    if here > upper_offset { upper_offset = here }
    if after > upper_offset { upper_offset = after }
    let upper_wall = base + upper_offset
    var y = start.year
    while y >= start.year - 400i64 {
        var mo = 12i64
        while mo >= 1i64 {
            if (cron.month >> u32(mo)) & 1u32 == 0u32 || (y == start.year && mo > start.month) {
                mo -= 1i64
                continue
            }
            var last_day = days_in_month(y, mo)
            if y == start.year && mo == start.month { last_day = start.day }
            var d = last_day
            while d >= 1i64 {
                if day_matches(cron, d, weekday_of(civil_days(y, mo, d))) {
                    var h = 23i64
                    while h >= 0i64 {
                        if (cron.hour >> u32(h)) & 1u32 == 1u32 {
                            var mi = 59i64
                            while mi >= 0i64 {
                                if (cron.minute >> u64(mi)) & 1u64 == 1u64 {
                                    let wall = civil_days(y, mo, d) * DAY_MS + (h * 60i64 + mi) * 60000i64
                                    if wall <= upper_wall {
                                        let inst = wall_to_instants(c, y, mo, d, h, mi, name)
                                        if inst.count > 0usize && f64(inst.at[0usize]) <= now_ms { ret (f64(inst.at[0usize]), true) }
                                    }
                                }
                                mi -= 1i64
                            }
                        }
                        h -= 1i64
                    }
                }
                d -= 1i64
            }
            mo -= 1i64
        }
        y -= 1i64
    }
    ret (0.0f64, false)
}

// --- the unified schedule -----------------------------------------------------------------------------------------

const KIND_NONE: u8 = 0u8
const KIND_INTERVAL: u8 = 1u8
const KIND_CRON: u8 = 2u8

// The policies: `one-catch-up` (the default) fires once at the most recent missed instant, `skip` fires nothing for
// an outage, `all` fires every missed instant in order, capped.
fn one_catch_up() -> str { ret "one-catch-up" }

type Schedule = struct {
    kind: u8,
    cron: str,
    parsed: Cron,
    every_ms: f64,
    timezone: str,
    on_missed: str,
    reason: str,
    has_error: bool,
}

// An authoring value rendered as JavaScript's `String(value)`, or absent.
type Field = struct { has: bool, text: str }

// `daily`, `weekly` or `monthly`: present, with the fields each form reads.
type Simple = struct { present: bool, minute: Field, hour: Field, day: Field, day_of_month: Field }

type Spec = struct {
    timezone: str,
    on_missed: str,
    has_cron: bool,
    cron: str,
    has_every: bool,
    every_ms: f64,
    has_minutes: bool,
    minutes: f64,
    daily: Simple,
    weekly: Simple,
    monthly: Simple,
}

fn no_field() -> Field { ret Field { has: false, text: "" } }

fn no_simple() -> Simple {
    ret Simple { present: false, minute: no_field(), hour: no_field(), day: no_field(), day_of_month: no_field() }
}

fn no_spec() -> Spec {
    ret Spec {
        timezone: "", on_missed: "", has_cron: false, cron: "", has_every: false, every_ms: 0.0f64, has_minutes: false,
        minutes: 0.0f64, daily: no_simple(), weekly: no_simple(), monthly: no_simple(),
    }
}

fn failure(message: str) -> Schedule {
    var empty = Cron { minute: 0u64, hour: 0u32, dom: 0u32, month: 0u32, dow: 0u32, dom_wild: false, dow_wild: false }
    ret Schedule {
        kind: KIND_NONE, cron: "", parsed: empty, every_ms: 0.0f64, timezone: "", on_missed: "", reason: message, has_error: true,
    }
}

fn is_policy(name: str) -> bool {
    ret str.eq(name, "one-catch-up") || str.eq(name, "skip") || str.eq(name, "all")
}

fn all_digits(s: str) -> bool {
    if s.len == 0usize { ret false }
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret false }
        i += 1usize
    }
    ret true
}

// The value of a simple-form field: its default when absent, and false when it is not plain digits.
fn field_text(x: Field, fallback: str) -> (str, bool) {
    if !x.has { ret (fallback, true) }
    ret (x.text, all_digits(x.text))
}

fn cron_schedule(c: *const Clock, text: str, timezone: str, on_missed: str) -> Schedule {
    let (parsed, good) = parse_cron(text)
    if !good { ret failure("Invalid cron") }
    ret Schedule { kind: KIND_CRON, cron: text, parsed: parsed, every_ms: 0.0f64, timezone: timezone, on_missed: on_missed, reason: "", has_error: false }
}

// The three authoring forms as one runtime schedule. An unknown zone is an error, not a fall back to UTC.
fn normalize_schedule(a: *mem.Arena, c: *const Clock, spec: Spec) -> Schedule {
    var timezone = "UTC"
    if spec.timezone.len != 0usize { timezone = spec.timezone }
    if !is_known_timezone(c, timezone) { ret failure("Unknown timezone") }
    var on_missed = one_catch_up()
    if spec.on_missed.len != 0usize { on_missed = spec.on_missed }
    if !is_policy(on_missed) { ret failure("Unknown missed policy") }
    if spec.has_cron { ret cron_schedule(c, spec.cron, timezone, on_missed) }
    if spec.has_every || spec.has_minutes {
        var every = spec.every_ms
        if !spec.has_every { every = spec.minutes * 60000.0f64 }
        if !is_finite(every) { ret failure("Unrecognized") }
        if every < 300000.0f64 { ret failure("Minimum interval") }
        var empty = Cron { minute: 0u64, hour: 0u32, dom: 0u32, month: 0u32, dow: 0u32, dom_wild: false, dow_wild: false }
        ret Schedule { kind: KIND_INTERVAL, cron: "", parsed: empty, every_ms: every, timezone: timezone, on_missed: on_missed, reason: "", has_error: false }
    }
    var simple = spec.daily
    if !simple.present { simple = spec.weekly }
    if !simple.present { simple = spec.monthly }
    if simple.present {
        let (minute, ok_minute) = field_text(simple.minute, "0")
        let (hour, ok_hour) = field_text(simple.hour, "0")
        var day = "*"
        var day_ok = true
        var dom = "*"
        var dom_ok = true
        if spec.weekly.present {
            let (value, good) = field_text(simple.day, "0")
            day = value
            day_ok = good
        }
        if spec.monthly.present {
            let (value, good) = field_text(simple.day_of_month, "1")
            dom = value
            dom_ok = good
        }
        if !ok_minute || !ok_hour || !day_ok || !dom_ok { ret failure("Unrecognized") }
        // The day value is shared: `weekly` puts it in the weekday field and `monthly` in the date field.
        var text = f.join3(a, minute, " ", hour)
        if spec.monthly.present { text = f.join3(a, text, " ", dom) } else { text = f.join(a, text, " *") }
        text = f.join(a, text, " *")
        if spec.weekly.present { text = f.join3(a, text, " ", day) } else { text = f.join(a, text, " *") }
        ret cron_schedule(c, text, timezone, on_missed)
    }
    ret failure("Unrecognized")
}

// The persisted shape a worker reads: `{type, cron | everyMs | atHour/atMinute, timezone, onMissed}`.
type Stored = struct {
    kind: str,
    cron: str,
    has_cron: bool,
    every_ms: f64,
    has_every: bool,
    timezone: str,
    on_missed: str,
    at_hour: Field,
    at_minute: Field,
}

// The runtime schedule for a stored one, or false for a type this module does not model.
fn runtime_schedule(a: *mem.Arena, c: *const Clock, stored: Stored) -> (Schedule, bool) {
    var spec = no_spec()
    spec.timezone = stored.timezone
    spec.on_missed = stored.on_missed
    if str.eq(stored.kind, "cron") {
        spec.has_cron = true
        spec.cron = stored.cron
        ret (normalize_schedule(a, c, spec), true)
    }
    if str.eq(stored.kind, "interval") {
        spec.has_every = true
        spec.every_ms = stored.every_ms
        ret (normalize_schedule(a, c, spec), true)
    }
    if str.eq(stored.kind, "daily") {
        spec.daily.present = true
        spec.daily.hour = stored.at_hour
        spec.daily.minute = stored.at_minute
        if !spec.daily.hour.has { spec.daily.hour = Field { has: true, text: "0" } }
        if !spec.daily.minute.has { spec.daily.minute = Field { has: true, text: "0" } }
        ret (normalize_schedule(a, c, spec), true)
    }
    ret (failure(""), false)
}

// The next fire strictly after `from_ms`, in the schedule's zone.
fn next_fire(c: *const Clock, s: Schedule, from_ms: f64, anchor_ms: f64) -> (f64, bool) {
    if s.has_error || !is_finite(from_ms) || !is_finite(anchor_ms) { ret (0.0f64, false) }
    if s.kind == KIND_INTERVAL {
        if !is_finite(s.every_ms) || s.every_ms <= 0.0f64 { ret (0.0f64, false) }
        let n = math.floor[f64]((from_ms - anchor_ms) / s.every_ms) + 1.0f64
        let at = anchor_ms + n * s.every_ms
        if is_finite(at) && at > from_ms { ret (at, true) }
        ret (0.0f64, false)
    }
    if s.kind == KIND_CRON {
        let (at, found) = next_cron_fire(c, s.parsed, from_ms, s.timezone)
        ret (at, found)
    }
    ret (0.0f64, false)
}

// The next `n` fire times, fewer when the schedule runs out.
fn next_fires(a: *mem.Arena, c: *const Clock, s: Schedule, from_ms: f64, n: i64, anchor_ms: f64) -> []const f64 {
    var none: []const f64 = zero
    if n < 1i64 { ret none }
    var want = usize(n)
    if want > 4096usize { want = 4096usize }
    let (out, e) = mem.alloc[f64](a, want)
    if e != ok { ret none }
    var count = 0usize
    var at = from_ms
    while count < want {
        let (next, found) = next_fire(c, s, at, anchor_ms)
        if !found { break }
        out[count] = next
        count += 1usize
        at = next
    }
    ret out[0usize..count]
}

// What a missed-fire policy does across a downtime window.
type Plan = struct {
    policy: str,
    due: bool,
    fire_at: []const f64,
    missed: i64,
    skipped: i64,
    capped: bool,
    has_spent: bool,
    spent_at: f64,
}

fn empty_plan(policy: str, capped: bool) -> Plan {
    var none: []const f64 = zero
    ret Plan { policy: policy, due: false, fire_at: none, missed: 0i64, skipped: 0i64, capped: capped, has_spent: false, spent_at: 0.0f64 }
}

// Apply the schedule's policy between the last fire and now. `missed` is the count a skipped outage leaves
// visible; a cron's count stops at the chunk limit and `capped` marks a lower bound.
fn missed_fires(a: *mem.Arena, c: *const Clock, s: Schedule, last_fired: f64, now_ms: f64, anchor_ms: f64) -> Plan {
    var policy = one_catch_up()
    if s.on_missed.len != 0usize { policy = s.on_missed }
    var plan = empty_plan(policy, false)
    if !is_finite(last_fired) || !is_finite(now_ms) || now_ms <= last_fired { ret plan }
    if s.kind == KIND_INTERVAL && !s.has_error {
        let (first, found) = next_fire(c, s, last_fired, anchor_ms)
        if !found || first > now_ms { ret plan }
        let count = i64(math.floor[f64]((now_ms - first) / s.every_ms)) + 1i64
        let latest = first + f64(count - 1i64) * s.every_ms
        if str.eq(policy, "skip") {
            plan.missed = count
            plan.skipped = count
            plan.has_spent = true
            plan.spent_at = latest
            ret plan
        }
        if !str.eq(policy, "all") {
            let (one, e1) = mem.alloc[f64](a, 1usize)
            if e1 != ok { ret plan }
            one[0usize] = latest
            ret Plan { policy: policy, due: true, fire_at: one, missed: count - 1i64, skipped: count - 1i64, capped: false, has_spent: false, spent_at: 0.0f64 }
        }
        var length = usize(count)
        if length > MAX_CATCH_UP_FIRES { length = MAX_CATCH_UP_FIRES }
        let (many, e2) = mem.alloc[f64](a, length + 1usize)
        if e2 != ok { ret plan }
        var i = 0usize
        while i < length {
            many[i] = first + f64(i) * s.every_ms
            i += 1usize
        }
        ret Plan { policy: policy, due: true, fire_at: many[0usize..length], missed: i64(length) - 1i64, skipped: 0i64, capped: count > i64(length), has_spent: false, spent_at: 0.0f64 }
    }
    // Enumerate the window, up to the chunk limit.
    let (instants, e3) = mem.alloc[f64](a, MAX_CATCH_UP_FIRES + 1usize)
    if e3 != ok { ret plan }
    var count = 0usize
    var capped = false
    var at = last_fired
    var running = true
    while running {
        let (next, found) = next_fire(c, s, at, anchor_ms)
        if !found || next > now_ms {
            running = false
        } else if count >= MAX_CATCH_UP_FIRES {
            capped = true
            running = false
        } else {
            instants[count] = next
            count += 1usize
            at = next
        }
    }
    if count == 0usize { ret empty_plan(policy, capped) }
    let missed = i64(count) - 1i64
    var last = instants[count - 1usize]
    if capped && s.kind == KIND_CRON {
        let (previous, have) = previous_cron_fire(c, s.parsed, now_ms, s.timezone)
        if have { last = previous }
    }
    if str.eq(policy, "skip") {
        plan.missed = i64(count)
        plan.skipped = i64(count)
        plan.capped = capped
        plan.has_spent = true
        plan.spent_at = last
        ret plan
    }
    if str.eq(policy, "all") {
        ret Plan { policy: policy, due: true, fire_at: instants[0usize..count], missed: missed, skipped: 0i64, capped: capped, has_spent: false, spent_at: 0.0f64 }
    }
    let (one, e4) = mem.alloc[f64](a, 1usize)
    if e4 != ok { ret plan }
    one[0usize] = last
    ret Plan { policy: policy, due: true, fire_at: one, missed: missed, skipped: i64(count) - 1i64, capped: capped, has_spent: false, spent_at: 0.0f64 }
}

// At most one catch-up fire per missed window, never a burst.
type CatchUp = struct { due: bool, fire_at: f64, missed: i64, catch_up: bool, capped: bool }

fn catch_up(a: *mem.Arena, c: *const Clock, s: Schedule, last_fired: f64, now_ms: f64, anchor_ms: f64) -> CatchUp {
    var one = s
    one.on_missed = one_catch_up()
    let plan = missed_fires(a, c, one, last_fired, now_ms, anchor_ms)
    if !plan.due { ret CatchUp { due: false, fire_at: 0.0f64, missed: 0i64, catch_up: false, capped: false } }
    ret CatchUp { due: true, fire_at: plan.fire_at[0usize], missed: plan.missed, catch_up: plan.missed > 0i64, capped: plan.capped }
}

// The number a text spells in plain digits, NaN otherwise (an absent field is zero).
fn number_of_text(x: Field) -> f64 {
    if !x.has { ret 0.0f64 }
    if x.text.len == 0usize { ret 0.0f64 }
    if !all_digits(x.text) { ret 0.0f64 / 0.0f64 }
    var v = 0.0f64
    var i = 0usize
    while i < x.text.len {
        v = v * 10.0f64 + f64(x.text[i] - 48u8)
        i += 1usize
    }
    ret v
}

type FirePlan = struct { present: bool, plan: Plan }

// The instants a worker should claim for this poll, resolved from shared schedule state rather than a worker's
// clock: `last_fired` and `anchor_ms` are NaN when absent.
fn schedule_fire_plan(a: *mem.Arena, c: *const Clock, stored: Stored, last_fired: f64, now_ms: f64, anchor_ms: f64) -> FirePlan {
    var none = FirePlan { present: false, plan: empty_plan("", false) }
    if !is_finite(now_ms) { ret none }
    let (sched, known) = runtime_schedule(a, c, stored)
    if !known || sched.has_error { ret none }
    var anchor = 0.0f64
    if is_finite(anchor_ms) { anchor = anchor_ms }
    if is_finite(last_fired) { ret planned_from(a, c, sched, last_fired, now_ms, anchor) }
    if str.eq(stored.kind, "interval") {
        var fire = now_ms
        if is_finite(anchor_ms) { fire = anchor_ms }
        let (one, e) = mem.alloc[f64](a, 1usize)
        if e != ok { ret none }
        one[0usize] = fire
        ret FirePlan { present: true, plan: Plan { policy: sched.on_missed, due: true, fire_at: one, missed: 0i64, skipped: 0i64, capped: false, has_spent: false, spent_at: 0.0f64 } }
    }
    if str.eq(stored.kind, "daily") {
        let w = wall_clock(c, now_ms, sched.timezone)
        let hour = number_of_text(stored.at_hour)
        let minute = number_of_text(stored.at_minute)
        if !is_finite(hour) || !is_finite(minute) {
            ret FirePlan { present: true, plan: missed_fires(a, c, sched, now_ms, now_ms, anchor) }
        }
        let inst = wall_to_instants(c, w.year, w.month, w.day, i64(hour), i64(minute), sched.timezone)
        if inst.count == 0usize || f64(inst.at[0usize]) > now_ms {
            ret FirePlan { present: true, plan: missed_fires(a, c, sched, now_ms, now_ms, anchor) }
        }
        ret planned_from(a, c, sched, f64(inst.at[0usize]) - 1.0f64, now_ms, anchor)
    }
    if !is_finite(anchor_ms) { ret none }
    ret planned_from(a, c, sched, anchor_ms, now_ms, anchor)
}

fn planned_from(a: *mem.Arena, c: *const Clock, sched: Schedule, from: f64, now_ms: f64, anchor: f64) -> FirePlan {
    let plan = missed_fires(a, c, sched, from, now_ms, anchor)
    if plan.due || plan.skipped == 0i64 || plan.has_spent { ret FirePlan { present: true, plan: plan } }
    var all = sched
    all.on_missed = "all"
    let spent = missed_fires(a, c, all, from, now_ms, anchor)
    var out = plan
    if spent.fire_at.len > 0usize {
        out.has_spent = true
        out.spent_at = spent.fire_at[spent.fire_at.len - 1usize]
    }
    ret FirePlan { present: true, plan: out }
}

// --- overlap and due evaluation -----------------------------------------------------------------------------------

// Whether a due rule starts, given a previous run that may still be going: one at a time by default, with a
// stale-run escape so a crashed worker's `running` row does not stop a schedule forever.
type Decision = struct {
    fire: bool,
    reason: str,
    has_skipped: bool,
    skipped_fire_at: f64,
    has_stale: bool,
    stale_for_ms: f64,
    has_active: bool,
    active_since_ms: f64,
}

fn decision(fire: bool, reason: str) -> Decision {
    ret Decision {
        fire: fire, reason: reason, has_skipped: false, skipped_fire_at: 0.0f64, has_stale: false, stale_for_ms: 0.0f64,
        has_active: false, active_since_ms: 0.0f64,
    }
}

// `started_at` is NaN for an active run that never recorded a start.
fn overlap_decision(due: bool, fire_at: f64, has_active_run: bool, started_at: f64, concurrency: str, stale_after_ms: f64, now_ms: f64) -> Decision {
    if !due { ret decision(false, "not-due") }
    if !has_active_run { ret decision(true, "no-active-run") }
    if str.eq(concurrency, "allow") { ret decision(true, "concurrency-allowed") }
    var started = 0.0f64
    if is_finite(started_at) { started = started_at }
    if started != 0.0f64 && now_ms - started >= stale_after_ms {
        var out = decision(true, "previous-run-stale")
        out.has_stale = true
        out.stale_for_ms = now_ms - started
        ret out
    }
    var out = decision(false, "previous-run-active")
    out.has_skipped = true
    out.skipped_fire_at = fire_at
    out.has_active = started != 0.0f64
    out.active_since_ms = started
    ret out
}

// Is a stored schedule due: an interval is due at its period or when never run, a daily rule once a day at its
// time on its own clock, a cron when an instant has passed since the last run (or the anchor, never fires at
// once). `last_run` and `anchor` are NaN when absent.
fn is_due(a: *mem.Arena, c: *const Clock, stored: Stored, now_ms: f64, last_run: f64, anchor: f64) -> bool {
    if str.eq(stored.kind, "interval") {
        if !is_finite(last_run) { ret true }
        ret now_ms - last_run >= stored.every_ms
    }
    if str.eq(stored.kind, "daily") {
        let (sched, known) = runtime_schedule(a, c, stored)
        if !known || sched.has_error || !is_finite(now_ms) { ret false }
        let w = wall_clock(c, now_ms, sched.timezone)
        let hour = number_of_text(stored.at_hour)
        let minute = number_of_text(stored.at_minute)
        if !is_finite(hour) || !is_finite(minute) { ret false }
        let inst = wall_to_instants(c, w.year, w.month, w.day, i64(hour), i64(minute), sched.timezone)
        if inst.count == 0usize { ret false }
        let scheduled = f64(inst.at[0usize])
        ret now_ms >= scheduled && (!is_finite(last_run) || last_run < scheduled)
    }
    if str.eq(stored.kind, "cron") {
        let (parsed, good) = parse_cron(stored.cron)
        if !good { ret false }
        var from = now_ms
        if is_finite(last_run) { from = last_run } else if is_finite(anchor) { from = anchor }
        let (next, found) = next_cron_fire(c, parsed, from, stored.timezone)
        ret found && next <= now_ms
    }
    ret false
}

// A scheduled workflow as `dueWorkflows` reads it.
type Workflow = struct {
    id: str,
    has_schedule: bool,
    schedule: Stored,
    last_run: f64,
    anchor: f64,
    has_active_run: bool,
    started_at: f64,
    concurrency: str,
    schedule_concurrency: str,
}

type Verdict = struct { id: str, decision: Decision }

// The decision for every scheduled workflow at `now_ms`; the caller keeps those with `fire`.
fn due_workflows(a: *mem.Arena, c: *const Clock, workflows: []const Workflow, now_ms: f64) -> []const Verdict {
    var none: []const Verdict = zero
    let (out, e) = mem.alloc[Verdict](a, workflows.len + 1usize)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < workflows.len {
        let w = workflows[i]
        if w.has_schedule {
            var concurrency = "skip"
            if w.concurrency.len != 0usize { concurrency = w.concurrency } else if w.schedule_concurrency.len != 0usize { concurrency = w.schedule_concurrency }
            let due = is_due(a, c, w.schedule, now_ms, w.last_run, w.anchor)
            out[n] = Verdict { id: w.id, decision: overlap_decision(due, now_ms, w.has_active_run, w.started_at, concurrency, 21600000.0f64, now_ms) }
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// --- date approaching, duration in state, scheduled scan ---------------------------------------------------------

// An occurrence stamp: the goal a record has already fired for.
type Stamp = struct { id: str, goal: f64 }

type DateEvent = struct { id: str, goal: f64, fire_at: f64 }

// The records whose date (plus an offset, negative for before) has arrived and has not fired for that value.
// `stamps` is updated in place (a changed date re-arms it); a stamp for an unseen record is appended, capacity
// permitting, and the new count returned through the result.
type DateEvents = struct { events: []const DateEvent, stamp_count: usize }

fn due_date_events(a: *mem.Arena, ids: []const str, dates: []const str, offset_ms: f64, stamps: []Stamp, stamp_count: usize, now_ms: f64) -> DateEvents {
    var none: []const DateEvent = zero
    let (out, e) = mem.alloc[DateEvent](a, ids.len + 1usize)
    if e != ok { ret DateEvents { events: none, stamp_count: stamp_count } }
    var n = 0usize
    var count = stamp_count
    var i = 0usize
    while i < ids.len {
        if dates[i].len != 0usize {
            let (goal, good) = view.to_date(a, f.text(dates[i]))
            if good {
                let fire_at = goal + offset_ms
                var at = count
                var k = 0usize
                while k < count {
                    if str.eq(stamps[k].id, ids[i]) { at = k }
                    k += 1usize
                }
                let fired = at < count && stamps[at].goal == goal
                if !fired && now_ms >= fire_at {
                    if at < count {
                        stamps[at].goal = goal
                    } else if count < stamps.len {
                        stamps[count] = Stamp { id: ids[i], goal: goal }
                        count += 1usize
                    }
                    out[n] = DateEvent { id: ids[i], goal: goal, fire_at: fire_at }
                    n += 1usize
                }
            }
        }
        i += 1usize
    }
    ret DateEvents { events: out[0usize..n], stamp_count: count }
}

// A record's continuous stretch in the filter: since when, and whether it already fired.
type InState = struct { id: str, since: f64, fired: bool }

type StateEvent = struct { id: str, since: f64, duration_ms: f64 }

type StateResult = struct { events: []const StateEvent, state_count: usize }

fn row_id(a: *mem.Arena, row: view.Row) -> str { ret view.cell_string(a, row, "id") }

// Fire when a record has matched `filter` continuously for `duration_ms`; leaving the filter re-arms it. `state`
// is updated in place.
fn duration_in_state_due(a: *mem.Arena, reg: *const f.Registry, rows: []const view.Row, filter: view.Node, has_filter: bool, fields: []const view.FieldDef, ctx: *const view.Context, duration_ms: f64, state: []InState, state_count: usize, now_ms: f64) -> StateResult {
    var none: []const StateEvent = zero
    let (out, e) = mem.alloc[StateEvent](a, rows.len + 1usize)
    if e != ok { ret StateResult { events: none, state_count: state_count } }
    var n = 0usize
    var count = state_count
    var i = 0usize
    while i < rows.len {
        let id = row_id(a, rows[i])
        var at = count
        var k = 0usize
        while k < count {
            if str.eq(state[k].id, id) { at = k }
            k += 1usize
        }
        if view.matches_filter(a, reg, filter, has_filter, rows[i], fields, ctx) {
            if at == count {
                if count < state.len {
                    state[count] = InState { id: id, since: now_ms, fired: false }
                    count += 1usize
                } else {
                    i += 1usize
                    continue
                }
            }
            if !state[at].fired && now_ms - state[at].since >= duration_ms {
                state[at].fired = true
                out[n] = StateEvent { id: id, since: state[at].since, duration_ms: now_ms - state[at].since }
                n += 1usize
            }
        } else if at < count {
            // Stopped matching: the clock and the firing re-arm.
            var j = at
            while j + 1usize < count {
                state[j] = state[j + 1usize]
                j += 1usize
            }
            count -= 1usize
        }
        i += 1usize
    }
    ret StateResult { events: out[0usize..n], state_count: count }
}

type ScanEvent = struct { id: str, batch_id: str, size: usize, position: usize }

type Scan = struct { events: []const ScanEvent, total: usize, next_cursor: usize, has_next: bool }

// One tick of a scheduled scan: the matching records from `cursor`, at most `cap` of them, each tagged with the
// scan batch, and where to continue when the match set is larger.
fn scan_batch(a: *mem.Arena, reg: *const f.Registry, rows: []const view.Row, filter: view.Node, has_filter: bool, fields: []const view.FieldDef, ctx: *const view.Context, cap: usize, cursor: usize, batch_id: str, has_batch_id: bool) -> Scan {
    var none: []const ScanEvent = zero
    let matched = view.filter_rows(a, reg, rows, filter, has_filter, fields, ctx)
    var take = 0usize
    if cursor < matched.len { take = matched.len - cursor }
    if take > cap { take = cap }
    let (out, e) = mem.alloc[ScanEvent](a, take + 1usize)
    if e != ok { ret Scan { events: none, total: matched.len, next_cursor: 0usize, has_next: false } }
    var id = batch_id
    if !has_batch_id { id = f.join(a, "scan_", f.number_text(a, f64(cursor))) }
    var i = 0usize
    while i < take {
        out[i] = ScanEvent { id: row_id(a, matched[cursor + i]), batch_id: id, size: matched.len, position: cursor + i }
        i += 1usize
    }
    ret Scan { events: out[0usize..take], total: matched.len, next_cursor: cursor + take, has_next: cursor + take < matched.len }
}
