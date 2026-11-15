// R's prettyunits, string for string: `pretty_bytes` and `pretty_num` (default, no-pad and "6"
// width styles), `pretty_ms`, `pretty_sec` and `pretty_dt` (the last is `pretty_sec` of a
// difference in seconds), and `vague_dt` ("moments ago", "3 hours ago", in its default, short
// and terse forms). Every function is vectorised the way R's is: the default styles right-pad
// the whole vector to one width.
//
// Not here: NA (Neper has none; NaN takes its place and prints "NaN"), infinities, negative
// times, `pretty_color`, `pretty_round`, `pretty_signif` and `pretty_p_value`.

use e.math
use e.mem
use e.str

error TooLarge

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nan(x: f64) -> bool { ret x != x }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// R's round(x, digits) for digits >= 0 (nmath/fround.c): the nearer of the two neighbours with
// `digits` decimals, the even one on a tie.
fn fround(x0: f64, digits: usize) -> f64 {
    if x0 == 0.0f64 || is_nan(x0) { ret x0 }
    var sgn = 1.0f64
    var x = x0
    if x < 0.0f64 {
        sgn = -1.0f64
        x = 0.0f64 - x
    }
    var p = 1.0f64
    var i = 0usize
    while i < digits {
        p = p * 10.0f64
        i += 1usize
    }
    let x10 = x * p
    let i10 = math.floor[f64](x10)
    let xd = i10 / p
    let xu = math.ceil[f64](x10) / p
    let du = xu - x
    let dd = x - xd
    let odd = i10 - 2.0f64 * math.floor[f64](i10 / 2.0f64) == 1.0f64
    if du < dd || (odd && du == dd) { ret sgn * xu }
    ret sgn * xd
}

// R's round(x): to the nearest integer, ties to even.
fn rint(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let d = x - f
    if d > 0.5f64 { ret f + 1.0f64 }
    if d < 0.5f64 { ret f }
    if f - 2.0f64 * math.floor[f64](f / 2.0f64) == 0.0f64 { ret f }
    ret f + 1.0f64
}

// R's x %% y for doubles.
fn modulo(x: f64, y: f64) -> f64 {
    let q = x / y
    let tmp = x - math.floor[f64](q) * y
    let q2 = math.floor[f64](tmp / y)
    ret tmp - q2 * y
}

fn parsed(s: str) -> f64 {
    let (v, e) = str.parse_f64(s)
    if e != ok { ret nan() }
    ret v
}

// 1000^k as the correctly rounded double, which is what R's powl-based `^` gives.
fn pow1000(k: i64) -> f64 {
    if k == -8i64 { ret parsed("1e-24") }
    if k == -7i64 { ret parsed("1e-21") }
    if k == -6i64 { ret parsed("1e-18") }
    if k == -5i64 { ret parsed("1e-15") }
    if k == -4i64 { ret parsed("1e-12") }
    if k == -3i64 { ret parsed("1e-9") }
    if k == -2i64 { ret parsed("1e-6") }
    if k == -1i64 { ret parsed("1e-3") }
    if k == 0i64 { ret parsed("1e0") }
    if k == 1i64 { ret parsed("1e3") }
    if k == 2i64 { ret parsed("1e6") }
    if k == 3i64 { ret parsed("1e9") }
    if k == 4i64 { ret parsed("1e12") }
    if k == 5i64 { ret parsed("1e15") }
    if k == 6i64 { ret parsed("1e18") }
    if k == 7i64 { ret parsed("1e21") }
    if k == 8i64 { ret parsed("1e24") }
    ret math.pow[f64](1000.0f64, f64(k))
}

// --- Number text.

fn digits_of(v: u64, out: []u8) -> usize {
    if v == 0u64 {
        out[0usize] = 48u8
        ret 1usize
    }
    var tmp: [24]u8 = zero
    var n = 0usize
    var w = v
    while w > 0u64 {
        tmp[n] = u8(48u64 + w % 10u64)
        w = w / 10u64
        n += 1usize
    }
    var i = 0usize
    while i < n {
        out[i] = tmp[n - 1usize - i]
        i += 1usize
    }
    ret n
}

// as.character of a whole number: fixed digits, or scientific ("1e+05") when that is shorter.
fn push_whole(b: *str.Builder, v: f64) {
    var d: [24]u8 = zero
    let n = digits_of(u64(v), d[0usize..24usize])
    var m = n
    while m > 1usize && d[m - 1usize] == 48u8 { m -= 1usize }
    var sci = m
    if m > 1usize { sci = m + 1usize }
    sci = sci + 4usize
    if n <= sci {
        let _ = str.push(b, d[0usize..n])
        ret
    }
    let _ = str.push_byte(b, d[0usize])
    if m > 1usize {
        let _ = str.push_byte(b, 46u8)
        let _ = str.push(b, d[1usize..m])
    }
    let _ = str.push(b, "e+")
    let e = n - 1usize
    let _ = str.push_byte(b, u8(48usize + e / 10usize))
    let _ = str.push_byte(b, u8(48usize + e % 10usize))
}

// as.character of a value with one decimal, 0 <= v <= 60.
fn push_tenths(b: *str.Builder, v: f64) {
    let t = u64(rint(v * 10.0f64))
    let _ = str.push_u64(b, t / 10u64)
    if t % 10u64 != 0u64 {
        let _ = str.push_byte(b, 46u8)
        let _ = str.push_byte(b, u8(48u64 + t % 10u64))
    }
}

// Right-justify every string to the widest, as format(justify = "right").
fn justify(a: *mem.Arena, items: []str) -> ([]str, err) {
    var width = 0usize
    var i = 0usize
    while i < items.len {
        if items[i].len > width { width = items[i].len }
        i += 1usize
    }
    let (out, e) = mem.alloc[str](a, items.len)
    if e != ok { ret (out, e) }
    i = 0usize
    while i < items.len {
        let pad = width - items[i].len
        let (initial, be) = str.builder(a, width)
        if be != ok { ret (out, be) }
        var b = initial
        var k = 0usize
        while k < pad {
            let _ = str.push_byte(&b, 32u8)
            k += 1usize
        }
        let _ = str.push(&b, items[i])
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

fn strip_leading(a: *mem.Arena, items: []str) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, items.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < items.len {
        var at = 0usize
        while at < items[i].len && items[i][at] == 32u8 { at += 1usize }
        out[i] = items[i][at..items[i].len]
        i += 1usize
    }
    ret (out, ok)
}

fn is_whole(amt: f64, tol: f64) -> bool {
    if is_nan(amt) { ret true }
    ret amt - math.floor[f64](amt) <= tol
}

// "-5", "5", "12.35" or "NaN": the amount (>= 0) with its sign, a whole number in plain digits
// and anything else with two decimals, as pretty_bytes and pretty_num write it.
fn number_text(a: *mem.Arena, amt: f64, negative: bool, tol: f64) -> str {
    let (initial, e) = str.builder(a, 48usize)
    if e != ok { ret "" }
    var b = initial
    if negative { let _ = str.push_byte(&b, 45u8) }
    if is_nan(amt) {
        let _ = str.push(&b, "NaN")
    } else if is_whole(amt, tol) {
        let _ = str.push_u64(&b, u64(math.floor[f64](amt)))
    } else {
        let _ = str.push_f64_fixed(&b, amt, 2u8)
    }
    ret str.done(&b)
}

// The default styles: the whole numbers are padded to one width among themselves (R formats
// that group together), then "<number> <unit>", then everything is right-justified.
fn assemble(a: *mem.Arena, nums: []const str, whole: []const bool, units: []const str) -> ([]str, err) {
    var width = 0usize
    var i = 0usize
    while i < nums.len {
        if whole[i] && nums[i].len > width { width = nums[i].len }
        i += 1usize
    }
    let (out, e) = mem.alloc[str](a, nums.len)
    if e != ok { ret (out, e) }
    i = 0usize
    while i < nums.len {
        let (initial, be) = str.builder(a, width + units[i].len + 2usize)
        if be != ok { ret (out, be) }
        var b = initial
        if whole[i] {
            var k = nums[i].len
            while k < width {
                let _ = str.push_byte(&b, 32u8)
                k += 1usize
            }
        }
        let _ = str.push(&b, nums[i])
        let _ = str.push_byte(&b, 32u8)
        let _ = str.push(&b, units[i])
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

// --- pretty_bytes.

fn byte_unit(i: usize) -> str {
    if i == 0usize { ret "B" }
    if i == 1usize { ret "kB" }
    if i == 2usize { ret "MB" }
    if i == 3usize { ret "GB" }
    if i == 4usize { ret "TB" }
    if i == 5usize { ret "PB" }
    if i == 6usize { ret "EB" }
    if i == 7usize { ret "ZB" }
    ret "YB"
}

// The exponent (0 = B .. 8 = YB) of |x|: the number of limits 1000, 999950, 999950e3, ... at or
// below it, and at least `floor` (1 for the kB-smallest "6" style).
fn byte_exponent(ax: f64, floor_exp: usize) -> usize {
    var e = 0usize
    var j = 0usize
    while j < 8usize {
        var limit = 1000.0f64
        if j > 0usize { limit = 999950.0f64 * pow1000(i64(j) - 1i64) }
        if ax >= limit { e += 1usize }
        j += 1usize
    }
    if e < floor_exp { ret floor_exp }
    ret e
}

// style 0 default (right-justified), 1 nopad, 2 the six-character form.
fn pretty_bytes(a: *mem.Arena, x: []const f64, style: u8) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, x.len)
    if e != ok { ret (out, e) }
    let (nums, ne) = mem.alloc[str](a, x.len)
    let (whole, we) = mem.alloc[bool](a, x.len)
    let (units, ue) = mem.alloc[str](a, x.len)
    if ne != ok || we != ok || ue != ok { ret (out, ne) }
    var i = 0usize
    while i < x.len {
        let neg = x[i] < 0.0f64
        let ax = abs_of(x[i])
        var floor_exp = 0usize
        if style == 2u8 { floor_exp = 1usize }
        var exponent = byte_exponent(ax, floor_exp)
        if ax == 0.0f64 { exponent = floor_exp }
        var amt = ax / pow1000(i64(exponent))
        if ax == 0.0f64 { amt = 0.0f64 }
        if is_nan(ax) { amt = nan() }
        if style == 2u8 {
            let (initial, be) = str.builder(a, 32usize)
            if be != ok { ret (out, be) }
            var b = initial
            if is_nan(amt) {
                let _ = str.push(&b, "NaN")
            } else if neg {
                let _ = str.push(&b, "< 0")
                exponent = 1usize
            } else if amt < 10.0f64 {
                let _ = str.push_f64_fixed(&b, amt, 1u8)
            } else if amt < 100.0f64 {
                let _ = str.push_byte(&b, 32u8)
                let _ = str.push_f64_fixed(&b, amt, 0u8)
            } else {
                let _ = str.push_f64_fixed(&b, amt, 0u8)
            }
            let _ = str.push_byte(&b, 32u8)
            let _ = str.push(&b, byte_unit(exponent))
            out[i] = str.done(&b)
        } else {
            nums[i] = number_text(a, amt, neg, 0.0f64)
            whole[i] = is_whole(amt, 0.0f64)
            units[i] = byte_unit(exponent)
        }
        i += 1usize
    }
    if style == 2u8 { ret (out, ok) }
    let (joined, je) = assemble(a, nums, whole, units)
    if je != ok { ret (joined, je) }
    if style == 0u8 {
        let (r0, e0) = justify(a, joined)
        ret (r0, e0)
    }
    let (r1, e1) = strip_leading(a, joined)
    ret (r1, e1)
}

// --- pretty_num.

fn prefix_of(i: i64) -> str {
    if i == -8i64 { ret "y" }
    if i == -7i64 { ret "z" }
    if i == -6i64 { ret "a" }
    if i == -5i64 { ret "f" }
    if i == -4i64 { ret "p" }
    if i == -3i64 { ret "n" }
    if i == -2i64 { ret "u" }
    if i == -1i64 { ret "m" }
    if i == 0i64 { ret "" }
    if i == 1i64 { ret "k" }
    if i == 2i64 { ret "M" }
    if i == 3i64 { ret "G" }
    if i == 4i64 { ret "T" }
    if i == 5i64 { ret "P" }
    if i == 6i64 { ret "E" }
    if i == 7i64 { ret "Z" }
    ret "Y"
}

// The SI exponent (-8 = y .. 8 = Y) of |x|: 17 limits 999950 * 1000^(j - 9) for j = 0..16.
fn num_exponent(ax: f64) -> i64 {
    var below = 0i64
    var j = 0i64
    while j < 17i64 {
        let limit = 999950.0f64 * pow1000(j - 9i64)
        if ax < limit { below += 1i64 }
        j += 1i64
    }
    var e = 9i64 - below
    if e > 8i64 { e = 8i64 }
    if e < -8i64 { e = -8i64 }
    ret e
}

fn pretty_num(a: *mem.Arena, x: []const f64, style: u8) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, x.len)
    if e != ok { ret (out, e) }
    let (nums, ne) = mem.alloc[str](a, x.len)
    let (whole, we) = mem.alloc[bool](a, x.len)
    let (units, ue) = mem.alloc[str](a, x.len)
    if ne != ok || we != ok || ue != ok { ret (out, ne) }
    var i = 0usize
    while i < x.len {
        let neg = x[i] < 0.0f64
        let ax = abs_of(x[i])
        var exponent = num_exponent(ax)
        var amt = ax / pow1000(exponent)
        if ax == 0.0f64 {
            amt = 0.0f64
            exponent = 0i64
        }
        if is_nan(ax) {
            amt = nan()
            exponent = 0i64
        }
        if style == 2u8 {
            let r = fround(amt, 2usize)
            let (initial, be) = str.builder(a, 32usize)
            if be != ok { ret (out, be) }
            var b = initial
            if is_nan(r) {
                let _ = str.push(&b, " NaN")
            } else if !neg && r < 10.0f64 {
                let _ = str.push_f64_fixed(&b, r, 2u8)
            } else if !neg && r < 100.0f64 {
                let _ = str.push_f64_fixed(&b, r, 1u8)
            } else if !neg {
                let _ = str.push_byte(&b, 32u8)
                let _ = str.push_f64_fixed(&b, r, 0u8)
            } else if r < 10.0f64 {
                let _ = str.push_byte(&b, 45u8)
                let _ = str.push_f64_fixed(&b, r, 1u8)
            } else if r < 100.0f64 {
                let _ = str.push(&b, " -")
                let _ = str.push_f64_fixed(&b, r, 0u8)
            } else {
                let _ = str.push_byte(&b, 45u8)
                let _ = str.push_f64_fixed(&b, r, 0u8)
            }
            let _ = str.push_byte(&b, 32u8)
            let prefix = prefix_of(exponent)
            let _ = str.push(&b, prefix)
            var text = str.done(&b)
            // sub(" $", "  "): a trailing space (an empty prefix) becomes two.
            if prefix.len == 0usize {
                let (initial2, be2) = str.builder(a, text.len + 2usize)
                if be2 != ok { ret (out, be2) }
                var b2 = initial2
                let _ = str.push(&b2, text)
                let _ = str.push_byte(&b2, 32u8)
                text = str.done(&b2)
            }
            out[i] = text
        } else {
            nums[i] = number_text(a, amt, neg, 0.0000000000000002220446049250313f64)
            whole[i] = is_whole(amt, 0.0000000000000002220446049250313f64)
            units[i] = prefix_of(exponent)
        }
        i += 1usize
    }
    if style == 2u8 { ret (out, ok) }
    let (joined, je) = assemble(a, nums, whole, units)
    if je != ok { ret (joined, je) }
    if style == 0u8 {
        let (r0, e0) = justify(a, joined)
        ret (r0, e0)
    }
    let (r1, e1) = strip_leading(a, joined)
    ret (r1, e1)
}

// --- Times.

// pretty_ms(ms, compact), for 0 <= ms < 1e15.
fn pretty_ms(a: *mem.Arena, ms: []const f64, compact: bool) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, ms.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < ms.len {
        let x = ms[i]
        let days = math.floor[f64](x / 86400000.0f64)
        let hours = math.floor[f64](modulo(x / 3600000.0f64, 24.0f64))
        let minutes = math.floor[f64](modulo(x / 60000.0f64, 60.0f64))
        let seconds = fround(modulo(x / 1000.0f64, 60.0f64), 1usize)
        let (initial, be) = str.builder(a, 64usize)
        if be != ok { ret (out, be) }
        var b = initial
        if compact && days <= 0.0f64 && hours <= 0.0f64 && minutes <= 0.0f64 && seconds <= 0.0f64 {
            let _ = str.push(&b, "NA")
        } else if compact {
            let _ = str.push_byte(&b, 126u8)
            if days > 0.0f64 {
                push_whole(&b, days)
                let _ = str.push_byte(&b, 100u8)
            } else if hours > 0.0f64 {
                push_whole(&b, hours)
                let _ = str.push_byte(&b, 104u8)
            } else if minutes > 0.0f64 {
                push_whole(&b, minutes)
                let _ = str.push_byte(&b, 109u8)
            } else {
                push_tenths(&b, seconds)
                let _ = str.push_byte(&b, 115u8)
            }
        } else if x < 1000.0f64 {
            push_whole(&b, math.ceil[f64](x))
            let _ = str.push(&b, "ms")
        } else {
            var first = true
            if days != 0.0f64 {
                push_whole(&b, days)
                let _ = str.push_byte(&b, 100u8)
                first = false
            }
            if hours != 0.0f64 {
                if !first { let _ = str.push_byte(&b, 32u8) }
                push_whole(&b, hours)
                let _ = str.push_byte(&b, 104u8)
                first = false
            }
            if minutes != 0.0f64 {
                if !first { let _ = str.push_byte(&b, 32u8) }
                push_whole(&b, minutes)
                let _ = str.push_byte(&b, 109u8)
                first = false
            }
            if seconds != 0.0f64 {
                if !first { let _ = str.push_byte(&b, 32u8) }
                push_tenths(&b, seconds)
                let _ = str.push_byte(&b, 115u8)
            }
        }
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

// pretty_sec(sec) and pretty_dt(dt): milliseconds are seconds times 1000.
fn pretty_sec(a: *mem.Arena, sec: []const f64, compact: bool) -> ([]str, err) {
    let (ms, e) = mem.alloc[f64](a, sec.len)
    if e != ok { ret (out_empty(), e) }
    var i = 0usize
    while i < sec.len {
        ms[i] = sec[i] * 1000.0f64
        i += 1usize
    }
    let (r3, e3) = pretty_ms(a, ms, compact)
    ret (r3, e3)
}

fn out_empty() -> []str {
    var none: []str = zero
    ret none
}

fn push_count(b: *str.Builder, v: f64, width: usize) {
    let rounded = rint(v)
    let negative = rounded < 0.0f64
    var magnitude = rounded
    if negative { magnitude = 0.0f64 - rounded }
    var d: [24]u8 = zero
    let n = digits_of(u64(magnitude), d[0usize..24usize])
    var used = n
    if negative { used = n + 1usize }
    var pad = 0usize
    if used < width { pad = width - used }
    var k = 0usize
    while k < pad {
        let _ = str.push_byte(b, 32u8)
        k += 1usize
    }
    if negative { let _ = str.push_byte(b, 45u8) }
    let _ = str.push(b, d[0usize..n])
}

fn push_ago(b: *str.Builder, v: f64, tail: str) {
    push_count(b, v, 0usize)
    let _ = str.push(b, tail)
}

fn push_terse(b: *str.Builder, v: f64, unit: u8) {
    push_count(b, v, 2usize)
    let _ = str.push_byte(b, unit)
}

// vague_dt(dt, format) for a difference in seconds: style 0 default, 1 short, 2 terse.
fn vague_dt(a: *mem.Arena, seconds: []const f64, style: u8) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, seconds.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < seconds.len {
        let s = seconds[i]
        let minutes = s / 60.0f64
        let hours = s / 60.0f64 / 60.0f64
        let days = s / 60.0f64 / 60.0f64 / 24.0f64
        let years = s / 60.0f64 / 60.0f64 / 24.0f64 / 365.25f64
        let (initial, be) = str.builder(a, 64usize)
        if be != ok { ret (out, be) }
        var b = initial
        if style == 0u8 {
            if s < 10.0f64 {
                let _ = str.push(&b, "moments ago")
            } else if s < 45.0f64 {
                let _ = str.push(&b, "less than a minute ago")
            } else if s < 90.0f64 {
                let _ = str.push(&b, "about a minute ago")
            } else if minutes < 45.0f64 {
                push_ago(&b, minutes, " minutes ago")
            } else if minutes < 90.0f64 {
                let _ = str.push(&b, "about an hour ago")
            } else if hours < 24.0f64 {
                push_ago(&b, hours, " hours ago")
            } else if hours < 42.0f64 {
                let _ = str.push(&b, "a day ago")
            } else if days < 30.0f64 {
                push_ago(&b, days, " days ago")
            } else if days < 45.0f64 {
                let _ = str.push(&b, "about a month ago")
            } else if days < 335.0f64 {
                push_ago(&b, days / 30.0f64, " months ago")
            } else if years < 1.5f64 {
                let _ = str.push(&b, "about a year ago")
            } else {
                push_ago(&b, years, " years ago")
            }
        } else if style == 1u8 {
            if s < 50.0f64 {
                let _ = str.push(&b, "<1 min")
            } else if minutes < 50.0f64 {
                push_ago(&b, minutes, " min")
            } else if hours < 1.5f64 {
                let _ = str.push(&b, "1 hour")
            } else if hours < 18.0f64 {
                push_ago(&b, hours, " hours")
            } else if hours < 42.0f64 {
                let _ = str.push(&b, "1 day")
            } else if days < 30.0f64 {
                push_ago(&b, days, " day")
            } else if days < 45.0f64 {
                let _ = str.push(&b, "1 mon")
            } else if days < 335.0f64 {
                push_ago(&b, days / 30.0f64, " mon")
            } else if years < 1.5f64 {
                let _ = str.push(&b, "1 year")
            } else {
                push_ago(&b, years, " years")
            }
        } else {
            if s < 50.0f64 {
                push_terse(&b, s, 115u8)
            } else if minutes < 50.0f64 {
                push_terse(&b, minutes, 109u8)
            } else if hours < 18.0f64 {
                push_terse(&b, hours, 104u8)
            } else if days < 30.0f64 {
                push_terse(&b, days, 100u8)
            } else if days < 335.0f64 {
                push_terse(&b, days / 30.0f64, 77u8)
            } else {
                push_terse(&b, years, 121u8)
            }
        }
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}
