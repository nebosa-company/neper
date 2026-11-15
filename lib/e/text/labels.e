// R's scales label formatters, string for string: `number` (accuracy, scale, prefix, suffix,
// big and decimal marks, positive and negative styles, scale cuts), which `comma`, `percent`,
// `dollar` and `bytes` are options of, `scientific`, `ordinal` (English rules), and
// `date_time` (label_date and label_time, in UTC). They follow scales' own order of work: the
// accuracy is found from the data (`precision`) unless given, the value is rounded to it,
// and each group of values with the same decimals is formatted the way R's format() does it
// with seven significant digits and `nsmall`.
//
// Not here: NA in the middle of a vector (NaN prints "NA"), `trim = FALSE` padding, the other
// ordinal rule sets, `label_date_short`, a locale other than C, and time zones other than UTC.

use e.math
use e.mem
use e.str

error InvalidOption

type Cut = struct { name: str, at: f64 }

// accuracy: NaN asks for `precision`. cuts: empty for none, else ascending, the first at 0.
type Number = struct {
    accuracy: f64,
    scale: f64,
    prefix: str,
    suffix: str,
    big_mark: str,
    decimal_mark: str,
    positive: u8,
    negative: u8,
    cuts: []const Cut,
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nan(x: f64) -> bool { ret x != x }

fn infinity() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

fn is_infinite(x: f64) -> bool { ret x == infinity() || x == 0.0f64 - infinity() }

fn is_finite(x: f64) -> bool { ret !is_nan(x) && !is_infinite(x) }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// round(x): ties to even.
fn rint(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let d = x - f
    if d > 0.5f64 { ret f + 1.0f64 }
    if d < 0.5f64 { ret f }
    if f - 2.0f64 * math.floor[f64](f / 2.0f64) == 0.0f64 { ret f }
    ret f + 1.0f64
}

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

// 10^k as the correctly rounded double, k in -40..40.
fn pow10(a: *mem.Arena, k: i64) -> f64 {
    let (initial, e) = str.builder(a, 8usize)
    if e != ok { ret nan() }
    var b = initial
    let _ = str.push(&b, "1e")
    let _ = str.push_i64(&b, k)
    let text = str.done(&b)
    ret parsed(text)
}

// R_pow_di(10, n): repeated squaring, as signif() computes its powers of ten.
fn pow_di10(n: i64) -> f64 {
    var x = 10.0f64
    var m = n
    var neg = false
    if m < 0i64 {
        neg = true
        m = 0i64 - m
    }
    var xn = 1.0f64
    while true {
        if (m & 1i64) != 0i64 { xn = xn * x }
        m = m / 2i64
        if m > 0i64 { x = x * x } else { break }
    }
    if neg { ret 1.0f64 / xn }
    ret xn
}

// signif(x, digits).
fn signif(x0: f64, digits: i64) -> f64 {
    if is_nan(x0) || !is_finite(x0) || x0 == 0.0f64 { ret x0 }
    var dig = digits
    if dig > 22i64 { ret x0 }
    if dig < 1i64 { dig = 1i64 }
    var sgn = 1.0f64
    var x = x0
    if x < 0.0f64 {
        sgn = -1.0f64
        x = 0.0f64 - x
    }
    let l10 = math.log10[f64](x)
    let e10 = dig - 1i64 - i64(math.floor[f64](l10))
    if e10 > 300i64 || e10 < -300i64 { ret x0 }
    if e10 > 0i64 {
        let p = pow_di10(e10)
        ret sgn * (rint(x * p) / p)
    }
    let p = pow_di10(0i64 - e10)
    ret sgn * (rint(x / p) * p)
}

// scales::precision(): the smallest power of ten (at most 1) that separates the values.
fn precision(a: *mem.Arena, x: []const f64) -> f64 {
    let (vals, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 1.0f64 }
    var n = 0usize
    var i = 0usize
    while i < x.len {
        if is_finite(x[i]) {
            var seen = false
            var k = 0usize
            while k < n {
                if vals[k] == x[i] { seen = true }
                k += 1usize
            }
            if !seen {
                vals[n] = x[i]
                n += 1usize
            }
        }
        i += 1usize
    }
    if n <= 1usize { ret 1.0f64 }
    // insertion sort
    i = 1usize
    while i < n {
        let v = vals[i]
        var j = i
        while j > 0usize && vals[j - 1usize] > v {
            vals[j] = vals[j - 1usize]
            j -= 1usize
        }
        vals[j] = v
        i += 1usize
    }
    var smallest = vals[1usize] - vals[0usize]
    i = 2usize
    while i < n {
        let d = vals[i] - vals[i - 1usize]
        if d < smallest { smallest = d }
        i += 1usize
    }
    if smallest < 0.00000001490116119384765625f64 { ret 1.0f64 }
    var p = pow10(a, i64(math.floor[f64](math.log10[f64](smallest))) - 1i64)
    var all_tens = true
    i = 0usize
    while i < n {
        if modulo(rint(vals[i] / p), 10.0f64) != 0.0f64 { all_tens = false }
        i += 1usize
    }
    if all_tens { p = p * 10.0f64 }
    if p > 1.0f64 { ret 1.0f64 }
    ret p
}

// --- format(): fixed notation with seven significant digits and nsmall.

fn push_group(b: *str.Builder, digits: str, mark: str) {
    var i = 0usize
    while i < digits.len {
        if i > 0usize && (digits.len - i) % 3usize == 0usize { let _ = str.push(b, mark) }
        let _ = str.push_byte(b, digits[i])
        i += 1usize
    }
}

// The fractional digits format() needs to show 7 significant digits of ax (>= 0), trailing
// zeros dropped.
fn needed_decimals(a: *mem.Arena, ax: f64) -> usize {
    if ax == 0.0f64 || ax >= 10000000.0f64 { ret 0usize }
    let kp = i64(math.floor[f64](math.log10[f64](ax)))
    var decimals = 6i64 - kp
    if decimals < 0i64 { decimals = 0i64 }
    if decimals > 90i64 { decimals = 90i64 }
    let (initial, e) = str.builder(a, usize(decimals) + 24usize)
    if e != ok { ret 0usize }
    var b = initial
    let _ = str.push_f64_fixed(&b, ax, u8(decimals))
    let text = str.done(&b)
    var end = text.len
    while end > 0usize && text[end - 1usize] == 48u8 { end -= 1usize }
    var dot = 0usize
    while dot < text.len && text[dot] != 46u8 { dot += 1usize }
    if end <= dot + 1usize { ret 0usize }
    ret end - dot - 1usize
}

// format(x, nsmall, big.mark, decimal.mark, scientific = FALSE, trim = TRUE) for one group of
// non-negative values, which all share the decimals.
fn format_group(a: *mem.Arena, xs: []const f64, nsmall: usize, o: *const Number) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, xs.len)
    if e != ok { ret (out, e) }
    var rgt = 0usize
    var i = 0usize
    while i < xs.len {
        if is_finite(xs[i]) {
            let d = needed_decimals(a, xs[i])
            if d > rgt { rgt = d }
        }
        i += 1usize
    }
    if rgt < nsmall { rgt = nsmall }
    i = 0usize
    while i < xs.len {
        if is_nan(xs[i]) {
            out[i] = "NA"
        } else if is_infinite(xs[i]) {
            out[i] = "Inf"
        } else {
            let (initial, be) = str.builder(a, 64usize + rgt)
            if be != ok { ret (out, be) }
            var raw = initial
            let _ = str.push_f64_fixed(&raw, xs[i], u8(rgt))
            let text = str.done(&raw)
            var dot = 0usize
            while dot < text.len && text[dot] != 46u8 { dot += 1usize }
            let (initial2, be2) = str.builder(a, text.len + text.len / 3usize + 8usize)
            if be2 != ok { ret (out, be2) }
            var b = initial2
            push_group(&b, text[0usize..dot], o.big_mark)
            if dot < text.len {
                let _ = str.push(&b, o.decimal_mark)
                let _ = str.push(&b, text[dot + 1usize..text.len])
            }
            out[i] = str.done(&b)
        }
        i += 1usize
    }
    ret (out, ok)
}

// --- scale_cut.

type CutResult = struct { scales: []f64, suffixes: []str, accuracy: []f64 }

fn cut_index(cuts: []const Cut, v: f64) -> i64 {
    var found = -1i64
    var k = 0usize
    while k < cuts.len {
        if v >= cuts[k].at { found = i64(k) }
        k += 1usize
    }
    if is_infinite(v) || is_nan(v) { ret -1i64 }
    ret found
}

fn apply_cuts(a: *mem.Arena, x: []const f64, o: *const Number) -> (CutResult, err) {
    var none: CutResult = zero
    let n = x.len
    let (idx, e1) = mem.alloc[i64](a, n)
    let (bscale, e2) = mem.alloc[f64](a, n)
    let (suffixes, e3) = mem.alloc[str](a, n)
    let (acc, e4) = mem.alloc[f64](a, n)
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    var i = 0usize
    while i < n {
        idx[i] = cut_index(o.cuts, abs_of(x[i] * o.scale))
        i += 1usize
    }
    // Values that do not divide evenly by their break take a smaller break that does.
    i = 0usize
    while i < n {
        let j = idx[i]
        if j >= 1i64 {
            let v = x[i] * o.scale
            let brk = o.cuts[usize(j)].at
            if modulo(v / brk, 1.0f64) != 0.0f64 && is_finite(v / brk) {
                var lower = o.cuts[usize(j) - 1usize].at
                if lower == 0.0f64 { lower = 1.0f64 }
                let improved = modulo(v / lower, 1.0f64) == 0.0f64
                let ratio = math.log10[f64](brk / lower)
                let power10 = modulo(ratio, 1.0f64) == 0.0f64
                if improved && !power10 { idx[i] = j - 1i64 }
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var name = ""
        var s = o.scale
        if idx[i] >= 0i64 {
            let brk = o.cuts[usize(idx[i])]
            name = brk.name
            let inv = 1.0f64 / brk.at
            if !is_infinite(inv) && !is_nan(inv) { s = o.scale * inv }
        }
        if abs_of(x[i]) == 0.0f64 || is_nan(s) { s = 1.0f64 }
        bscale[i] = s
        let (initial, be) = str.builder(a, name.len + o.suffix.len + 4usize)
        if be != ok { ret (none, be) }
        var b = initial
        let _ = str.push(&b, name)
        let _ = str.push(&b, o.suffix)
        suffixes[i] = str.done(&b)
        i += 1usize
    }
    // accuracy: given, or `precision` within each group of equal scales
    i = 0usize
    while i < n {
        if !is_nan(o.accuracy) {
            acc[i] = o.accuracy
        } else {
            var count = 0usize
            var k = 0usize
            while k < n {
                if bscale[k] == bscale[i] { count += 1usize }
                k += 1usize
            }
            let (grp, ge) = mem.alloc[f64](a, count)
            if ge != ok { ret (none, ge) }
            var at = 0usize
            k = 0usize
            while k < n {
                if bscale[k] == bscale[i] {
                    grp[at] = x[k] * bscale[k]
                    at += 1usize
                }
                k += 1usize
            }
            acc[i] = precision(a, grp)
        }
        i += 1usize
    }
    ret (CutResult { scales: bscale, suffixes: suffixes, accuracy: acc }, ok)
}

// --- number().

// scales::number(x, ...): one string per value.
fn number(a: *mem.Arena, x: []const f64, o: *const Number) -> ([]str, err) {
    var none: []str = zero
    let n = x.len
    let (scales, e1) = mem.alloc[f64](a, n)
    let (accs, e2) = mem.alloc[f64](a, n)
    let (sufs, e3) = mem.alloc[str](a, n)
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    var i = 0usize
    if o.cuts.len > 0usize {
        let (cut, ce) = apply_cuts(a, x, o)
        if ce != ok { ret (none, ce) }
        i = 0usize
        while i < n {
            scales[i] = cut.scales[i]
            accs[i] = cut.accuracy[i]
            sufs[i] = cut.suffixes[i]
            i += 1usize
        }
    } else {
        var acc = o.accuracy
        if is_nan(acc) {
            let (prod, pe) = mem.alloc[f64](a, n)
            if pe != ok { ret (none, pe) }
            i = 0usize
            while i < n {
                prod[i] = x[i] * o.scale
                i += 1usize
            }
            acc = precision(a, prod)
        }
        i = 0usize
        while i < n {
            scales[i] = o.scale
            accs[i] = acc
            sufs[i] = o.suffix
            i += 1usize
        }
    }
    let (rounded, re) = mem.alloc[f64](a, n)
    let (nsmalls, ne) = mem.alloc[usize](a, n)
    if re != ok { ret (none, re) }
    if ne != ok { ret (none, ne) }
    i = 0usize
    while i < n {
        rounded[i] = rint(x[i] / (accs[i] / scales[i])) * (accs[i] / scales[i])
        var ns = 0.0f64 - math.floor[f64](math.log10[f64](accs[i]))
        if ns < 0.0f64 { ns = 0.0f64 }
        if ns > 20.0f64 { ns = 20.0f64 }
        nsmalls[i] = usize(ns)
        i += 1usize
    }
    let (out, oe) = mem.alloc[str](a, n)
    if oe != ok { ret (none, oe) }
    var done = 0usize
    i = 0usize
    while i < n {
        // one format() call per distinct nsmall, in order of first appearance
        var first = true
        var k = 0usize
        while k < i {
            if nsmalls[k] == nsmalls[i] { first = false }
            k += 1usize
        }
        if first {
            var count = 0usize
            k = 0usize
            while k < n {
                if nsmalls[k] == nsmalls[i] { count += 1usize }
                k += 1usize
            }
            let (vals, ve) = mem.alloc[f64](a, count)
            if ve != ok { ret (none, ve) }
            var at = 0usize
            k = 0usize
            while k < n {
                if nsmalls[k] == nsmalls[i] {
                    vals[at] = abs_of(rounded[k]) * scales[k]
                    at += 1usize
                }
                k += 1usize
            }
            let (texts, te) = format_group(a, vals, nsmalls[i], o)
            if te != ok { ret (none, te) }
            at = 0usize
            k = 0usize
            while k < n {
                if nsmalls[k] == nsmalls[i] {
                    out[k] = texts[at]
                    at += 1usize
                }
                k += 1usize
            }
        }
        i += 1usize
    }
    // prefix, suffix, signs
    i = 0usize
    while i < n {
        let v = rounded[i]
        let (initial, be) = str.builder(a, out[i].len + o.prefix.len + sufs[i].len + 12usize)
        if be != ok { ret (none, be) }
        var b = initial
        if is_nan(v) {
            let _ = str.push(&b, "NA")
        } else {
            let negative = v < 0.0f64
            let positive = v > 0.0f64
            if negative && o.negative == 2u8 { let _ = str.push_byte(&b, 40u8) }
            if negative && o.negative == 0u8 { let _ = str.push_byte(&b, 45u8) }
            if negative && o.negative == 1u8 { let _ = str.push(&b, "\xe2\x88\x92") }
            if positive && o.positive == 1u8 { let _ = str.push_byte(&b, 43u8) }
            if positive && o.positive == 2u8 { let _ = str.push(&b, "\xe2\x80\x87") }
            if is_infinite(v) {
                let _ = str.push(&b, "Inf")
            } else {
                let _ = str.push(&b, o.prefix)
                let _ = str.push(&b, out[i])
                let _ = str.push(&b, sufs[i])
            }
            if negative && o.negative == 2u8 { let _ = str.push_byte(&b, 41u8) }
        }
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

fn defaults() -> Number {
    var none: []const Cut = zero
    ret Number { accuracy: nan(), scale: 1.0f64, prefix: "", suffix: "", big_mark: " ", decimal_mark: ".", positive: 0u8, negative: 0u8, cuts: none }
}

// label_comma / comma: big mark ",".
fn comma_options() -> Number {
    var o = defaults()
    o.big_mark = ","
    ret o
}

// label_percent / percent: scale 100, suffix "%".
fn percent_options() -> Number {
    var o = defaults()
    o.scale = 100.0f64
    o.suffix = "%"
    ret o
}

fn dollar_options() -> Number {
    var o = defaults()
    o.prefix = "$"
    o.big_mark = ","
    ret o
}

fn needs_cents(x: []const f64, scale: f64, threshold: f64) -> bool {
    var any = false
    var biggest = 0.0f64
    var fractional = false
    var i = 0usize
    while i < x.len {
        let v = x[i] * scale
        if !is_nan(v) {
            any = true
            if abs_of(v) > biggest { biggest = abs_of(v) }
            if v != math.floor[f64](v) { fractional = true }
        }
        i += 1usize
    }
    if !any { ret false }
    if biggest > threshold { ret false }
    ret fractional
}

// scales::dollar: the accuracy is 0.01 when some value needs cents and none is above
// `largest_with_cents`, else 1.
fn dollar(a: *mem.Arena, x: []const f64, base: *const Number, largest_with_cents: f64) -> ([]str, err) {
    var o = *base
    if is_nan(o.accuracy) && o.cuts.len == 0usize {
        if needs_cents(x, o.scale, largest_with_cents) { o.accuracy = 0.01f64 } else { o.accuracy = 1.0f64 }
    }
    if str.eq(o.big_mark, ",") && str.eq(o.decimal_mark, ",") { o.big_mark = " " }
    let (r, e) = number(a, x, &o)
    ret (r, e)
}

fn x_none() -> []str {
    var none: []str = zero
    ret none
}

fn no_cuts() -> []Cut {
    var none: []Cut = zero
    ret none
}

// --- Scale cuts.

fn make_cuts(a: *mem.Arena, names: []const str, ats: []const f64, space: bool) -> ([]Cut, err) {
    let (cuts, e) = mem.alloc[Cut](a, names.len)
    if e != ok { ret (cuts, e) }
    var i = 0usize
    while i < names.len {
        var name = names[i]
        if space {
            let (initial, be) = str.builder(a, name.len + 2usize)
            if be != ok { ret (cuts, be) }
            var b = initial
            let _ = str.push_byte(&b, 32u8)
            let _ = str.push(&b, name)
            name = str.done(&b)
        }
        cuts[i] = Cut { name: name, at: ats[i] }
        i += 1usize
    }
    ret (cuts, ok)
}

fn scale_cuts(a: *mem.Arena, kind: u8, space: bool) -> ([]Cut, err) {
    let (names, ne) = mem.alloc[str](a, 9usize)
    let (ats, ae) = mem.alloc[f64](a, 9usize)
    if ne != ok { ret (no_cuts(), ne) }
    if ae != ok { ret (no_cuts(), ae) }
    var count = 5usize
    names[0usize] = ""
    ats[0usize] = 0.0f64
    if kind == 2u8 {
        // cut_time_scale
        count = 9usize
        names[1usize] = "ns"
        names[2usize] = "\xce\xbcs"
        names[3usize] = "ms"
        names[4usize] = "s"
        names[5usize] = "m"
        names[6usize] = "h"
        names[7usize] = "d"
        names[8usize] = "w"
        ats[1usize] = 0.000000001f64
        ats[2usize] = 0.000001f64
        ats[3usize] = 0.001f64
        ats[4usize] = 1.0f64
        ats[5usize] = 60.0f64
        ats[6usize] = 3600.0f64
        ats[7usize] = 86400.0f64
        ats[8usize] = 604800.0f64
    } else {
        names[1usize] = "K"
        names[2usize] = "M"
        names[3usize] = "B"
        names[4usize] = "T"
        ats[1usize] = 1000.0f64
        ats[2usize] = 1000000.0f64
        ats[3usize] = 1000000000.0f64
        ats[4usize] = 1000000000000.0f64
        if kind == 1u8 {
            ats[3usize] = 1000000000000.0f64
            ats[4usize] = 1000000000000000000.0f64
        }
    }
    let (r, e) = make_cuts(a, names[0usize..count], ats[0usize..count], space)
    ret (r, e)
}

// cut_short_scale() is kind 0, cut_long_scale() kind 1, cut_time_scale() kind 2.

// cut_si(unit): 0 and 10^-24 .. 10^24, each named " <prefix><unit>".
fn cut_si(a: *mem.Arena, unit: str) -> ([]Cut, err) {
    let (cuts, e) = mem.alloc[Cut](a, 18usize)
    if e != ok { ret (cuts, e) }
    var k = 0usize
    while k < 18usize {
        var prefix = ""
        var at = 0.0f64
        if k > 0usize {
            prefix = si_prefix(k)
            at = pow10(a, 3i64 * (i64(k) - 9i64))
        }
        let (initial, be) = str.builder(a, unit.len + 8usize)
        if be != ok { ret (cuts, be) }
        var b = initial
        let _ = str.push_byte(&b, 32u8)
        let _ = str.push(&b, prefix)
        let _ = str.push(&b, unit)
        cuts[k] = Cut { name: str.done(&b), at: at }
        k += 1usize
    }
    ret (cuts, ok)
}

fn si_prefix(k: usize) -> str {
    if k == 1usize { ret "y" }
    if k == 2usize { ret "z" }
    if k == 3usize { ret "a" }
    if k == 4usize { ret "f" }
    if k == 5usize { ret "p" }
    if k == 6usize { ret "n" }
    if k == 7usize { ret "\xc2\xb5" }
    if k == 8usize { ret "m" }
    if k == 9usize { ret "" }
    if k == 10usize { ret "k" }
    if k == 11usize { ret "M" }
    if k == 12usize { ret "G" }
    if k == 13usize { ret "T" }
    if k == 14usize { ret "P" }
    if k == 15usize { ret "E" }
    if k == 16usize { ret "Z" }
    ret "Y"
}

// --- bytes.

fn byte_prefix(i: usize) -> str {
    if i == 1usize { ret "k" }
    if i == 2usize { ret "M" }
    if i == 3usize { ret "G" }
    if i == 4usize { ret "T" }
    if i == 5usize { ret "P" }
    if i == 6usize { ret "E" }
    if i == 7usize { ret "Z" }
    ret "Y"
}

fn pow_int(base: f64, k: usize) -> f64 {
    var r = 1.0f64
    var i = 0usize
    while i < k {
        r = r * base
        i += 1usize
    }
    ret r
}

// cut_bytes("si" or "binary"): " B", " kB", .. at 0, 1000^1 .. 1000^8 (or 1024^k, " iB", " kiB", ..).
fn cut_bytes(a: *mem.Arena, binary: bool) -> ([]Cut, err) {
    let (cuts, e) = mem.alloc[Cut](a, 9usize)
    if e != ok { ret (cuts, e) }
    var k = 0usize
    while k < 9usize {
        var at = 0.0f64
        if k > 0usize {
            if binary { at = pow_int(1024.0f64, k) } else { at = pow10(a, 3i64 * i64(k)) }
        }
        let (initial, be) = str.builder(a, 8usize)
        if be != ok { ret (cuts, be) }
        var b = initial
        let _ = str.push_byte(&b, 32u8)
        if k > 0usize { let _ = str.push(&b, byte_prefix(k)) }
        if binary { let _ = str.push_byte(&b, 105u8) }
        let _ = str.push_byte(&b, 66u8)
        cuts[k] = Cut { name: str.done(&b), at: at }
        k += 1usize
    }
    ret (cuts, ok)
}

fn unit_name(a: *mem.Arena, k: usize, binary: bool) -> str {
    let (initial, be) = str.builder(a, 8usize)
    if be != ok { ret "" }
    var b = initial
    let _ = str.push(&b, byte_prefix(k))
    if binary { let _ = str.push_byte(&b, 105u8) }
    let _ = str.push_byte(&b, 66u8)
    ret str.done(&b)
}

// label_bytes(units, accuracy, scale): units "auto_si", "auto_binary", or "kB", "MiB", ...
fn bytes(a: *mem.Arena, x: []const f64, units: str, accuracy: f64, scale: f64) -> ([]str, err) {
    var o = defaults()
    o.accuracy = accuracy
    o.scale = scale
    if str.eq(units, "auto_si") || str.eq(units, "auto_binary") {
        let (cuts, ce) = cut_bytes(a, str.eq(units, "auto_binary"))
        if ce != ok { ret (x_none(), ce) }
        o.cuts = cuts
    } else {
        var power = 0usize
        var base = 1000.0f64
        var k = 1usize
        while k <= 8usize {
            if str.eq(units, unit_name(a, k, false)) {
                power = k
                base = 1000.0f64
            }
            if str.eq(units, unit_name(a, k, true)) {
                power = k
                base = 1024.0f64
            }
            k += 1usize
        }
        if power == 0usize { ret (x_none(), InvalidOption) }
        let (initial, be) = str.builder(a, units.len + 2usize)
        if be != ok { ret (x_none(), be) }
        var b = initial
        let _ = str.push_byte(&b, 32u8)
        let _ = str.push(&b, units)
        o.suffix = str.done(&b)
        var divisor = 0.0f64
        if base == 1000.0f64 { divisor = pow10(a, 3i64 * i64(power)) } else { divisor = pow_int(1024.0f64, power) }
        o.scale = scale / divisor
    }
    let (r, e) = number(a, x, &o)
    ret (r, e)
}

// --- ordinal (English rules).

fn ordinal(a: *mem.Arena, x: []const f64, prefix: str, suffix: str, big_mark: str) -> ([]str, err) {
    var o = defaults()
    o.accuracy = 1.0f64
    o.prefix = prefix
    o.big_mark = big_mark
    let (rounded, re) = mem.alloc[f64](a, x.len)
    if re != ok { ret (x_none(), re) }
    var i = 0usize
    while i < x.len {
        rounded[i] = rint(x[i])
        i += 1usize
    }
    let (nums, ne) = number(a, rounded, &o)
    if ne != ok { ret (nums, ne) }
    let (out, oe) = mem.alloc[str](a, x.len)
    if oe != ok { ret (out, oe) }
    i = 0usize
    while i < x.len {
        if is_nan(x[i]) {
            out[i] = "NA"
        } else {
            let v = abs_of(rounded[i])
            var last = 0u64
            var tens = 0u64
            if is_finite(v) {
                last = u64(modulo(v, 10.0f64))
                tens = u64(modulo(math.floor[f64](v / 10.0f64), 10.0f64))
            }
            var ending = "th"
            if last == 1u64 && tens != 1u64 { ending = "st" }
            if last == 2u64 && tens != 1u64 { ending = "nd" }
            if last == 3u64 && tens != 1u64 { ending = "rd" }
            let (initial, be) = str.builder(a, nums[i].len + suffix.len + 4usize)
            if be != ok { ret (out, be) }
            var b = initial
            let _ = str.push(&b, nums[i])
            let _ = str.push(&b, ending)
            let _ = str.push(&b, suffix)
            out[i] = str.done(&b)
        }
        i += 1usize
    }
    ret (out, ok)
}

// --- scientific.

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// The first `keep` significant digits of ax (> 0), correctly rounded, and the decimal exponent.
fn sig_digits(a: *mem.Arena, ax: f64, keep: usize) -> (str, i64) {
    let kp = i64(math.floor[f64](math.log10[f64](ax)))
    var decimals = i64(keep) - 1i64 - kp
    var text = ""
    if decimals >= 0i64 {
        if decimals > 99i64 { decimals = 99i64 }
        let (initial, e) = str.builder(a, usize(decimals) + 32usize)
        if e != ok { ret ("", 0i64) }
        var b = initial
        let _ = str.push_f64_fixed(&b, ax, u8(decimals))
        text = str.done(&b)
    } else {
        let (initial, e) = str.builder(a, 400usize)
        if e != ok { ret ("", 0i64) }
        var b = initial
        let _ = str.push_f64_fixed(&b, ax, 0u8)
        text = str.done(&b)
    }
    let (buf, be) = mem.alloc[u8](a, text.len + keep + 2usize)
    if be != ok { ret ("", 0i64) }
    var n = 0usize
    var int_digits = 0usize
    var seen_point = false
    var lead = 0usize
    var started = false
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c == 46u8 {
            seen_point = true
        } else if is_digit(c) {
            if !started && c == 48u8 {
                if seen_point { lead += 1usize }
            } else {
                started = true
                buf[n] = c
                n += 1usize
            }
            if !seen_point { int_digits += 1usize }
        }
        i += 1usize
    }
    var exp10 = 0i64
    if int_digits > 0usize && text[0usize] != 48u8 {
        exp10 = i64(int_digits) - 1i64
    } else {
        exp10 = 0i64 - i64(lead) - 1i64
    }
    if decimals < 0i64 {
        // an integer text longer than `keep`: round at the digit after the keep-th, ties to even
        var keep_n = keep
        if n < keep_n { keep_n = n }
        var up = false
        if n > keep_n {
            let d = buf[keep_n]
            var rest_zero = true
            var k = keep_n + 1usize
            while k < n {
                if buf[k] != 48u8 { rest_zero = false }
                k += 1usize
            }
            if d > 53u8 || (d == 53u8 && !rest_zero) { up = true }
            if d == 53u8 && rest_zero && (buf[keep_n - 1usize] - 48u8) % 2u8 == 1u8 { up = true }
        }
        if up {
            var k = keep_n
            var carried = true
            while k > 0usize && carried {
                k -= 1usize
                if buf[k] == 57u8 {
                    buf[k] = 48u8
                } else {
                    buf[k] = buf[k] + 1u8
                    carried = false
                }
            }
            if carried {
                buf[0usize] = 49u8
                exp10 += 1i64
            }
        }
        n = keep_n
    }
    var have = n
    while have < keep {
        buf[have] = 48u8
        have += 1usize
    }
    ret (buf[0usize..keep], exp10)
}

// format(x, scientific = TRUE) of one vector: the mantissa decimals are the most any value
// needs to show 7 significant digits.
fn scientific(a: *mem.Arena, x: []const f64, digits: i64, scale: f64, prefix: str, suffix: str, decimal_mark: str) -> ([]str, err) {
    let (vals, ve) = mem.alloc[f64](a, x.len)
    if ve != ok { ret (x_none(), ve) }
    var i = 0usize
    while i < x.len {
        vals[i] = signif(x[i] * scale, digits)
        i += 1usize
    }
    var rgt = 0usize
    i = 0usize
    while i < vals.len {
        let v = abs_of(vals[i])
        if is_finite(v) && v > 0.0f64 {
            let (d7, e7) = sig_digits(a, v, 7usize)
            var nsig = 7usize
            while nsig > 1usize && d7[nsig - 1usize] == 48u8 { nsig -= 1usize }
            if nsig - 1usize > rgt { rgt = nsig - 1usize }
        }
        i += 1usize
    }
    let (out, oe) = mem.alloc[str](a, x.len)
    if oe != ok { ret (out, oe) }
    i = 0usize
    while i < vals.len {
        let v = vals[i]
        var mant = "0000000000000000000000"
        var e10 = 0i64
        if is_finite(v) && v != 0.0f64 {
            let (dg, ex) = sig_digits(a, abs_of(v), rgt + 1usize)
            mant = dg
            e10 = ex
        }
        let (initial, be) = str.builder(a, 48usize + prefix.len + suffix.len)
        if be != ok { ret (out, be) }
        var b = initial
        if is_nan(v) {
            let _ = str.push(&b, "NA")
        } else {
            let _ = str.push(&b, prefix)
            if v < 0.0f64 { let _ = str.push_byte(&b, 45u8) }
            if is_infinite(v) {
                let _ = str.push(&b, "Inf")
            } else {
                let _ = str.push_byte(&b, mant[0usize])
                if rgt > 0usize {
                    let _ = str.push(&b, decimal_mark)
                    let _ = str.push(&b, mant[1usize..rgt + 1usize])
                }
                if e10 < 0i64 {
                    let _ = str.push(&b, "e-")
                    e10 = 0i64 - e10
                } else {
                    let _ = str.push(&b, "e+")
                }
                if e10 < 10i64 { let _ = str.push_byte(&b, 48u8) }
                let _ = str.push_i64(&b, e10)
            }
            let _ = str.push(&b, suffix)
        }
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}

// --- label_date / label_time in UTC: strftime over seconds since the epoch.

fn month_name(m: i64, full: bool) -> str {
    if m == 1i64 { if full { ret "January" } else { ret "Jan" } }
    if m == 2i64 { if full { ret "February" } else { ret "Feb" } }
    if m == 3i64 { if full { ret "March" } else { ret "Mar" } }
    if m == 4i64 { if full { ret "April" } else { ret "Apr" } }
    if m == 5i64 { ret "May" }
    if m == 6i64 { if full { ret "June" } else { ret "Jun" } }
    if m == 7i64 { if full { ret "July" } else { ret "Jul" } }
    if m == 8i64 { if full { ret "August" } else { ret "Aug" } }
    if m == 9i64 { if full { ret "September" } else { ret "Sep" } }
    if m == 10i64 { if full { ret "October" } else { ret "Oct" } }
    if m == 11i64 { if full { ret "November" } else { ret "Nov" } }
    if full { ret "December" }
    ret "Dec"
}

fn weekday_name(w: i64, full: bool) -> str {
    if w == 0i64 { if full { ret "Sunday" } else { ret "Sun" } }
    if w == 1i64 { if full { ret "Monday" } else { ret "Mon" } }
    if w == 2i64 { if full { ret "Tuesday" } else { ret "Tue" } }
    if w == 3i64 { if full { ret "Wednesday" } else { ret "Wed" } }
    if w == 4i64 { if full { ret "Thursday" } else { ret "Thu" } }
    if w == 5i64 { if full { ret "Friday" } else { ret "Fri" } }
    if full { ret "Saturday" }
    ret "Sat"
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

fn push_pad(b: *str.Builder, v: i64, width: usize, fill: u8) {
    var digits: [24]u8 = zero
    var n = 0usize
    var w = v
    if w == 0i64 {
        digits[0usize] = 48u8
        n = 1usize
    }
    while w > 0i64 {
        digits[n] = u8(48i64 + w % 10i64)
        w = w / 10i64
        n += 1usize
    }
    var k = n
    while k < width {
        let _ = str.push_byte(b, fill)
        k += 1usize
    }
    var i = n
    while i > 0usize {
        i -= 1usize
        let _ = str.push_byte(b, digits[i])
    }
}

// format(x, format = fmt, tz = "UTC") for seconds since the epoch.
fn date_time(a: *mem.Arena, secs: []const f64, fmt: str) -> ([]str, err) {
    let (out, e) = mem.alloc[str](a, secs.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < secs.len {
        let (initial, be) = str.builder(a, fmt.len * 4usize + 32usize)
        if be != ok { ret (out, be) }
        var b = initial
        if is_nan(secs[i]) {
            let _ = str.push(&b, "NA")
        } else {
            let total = i64(math.floor[f64](secs[i]))
            let days = floor_div(total, 86400i64)
            let rem = total - days * 86400i64
            let z = days + 719468i64
            let era = floor_div(z, 146097i64)
            let doe = z - era * 146097i64
            let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
            var year = yoe + era * 400i64
            let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
            let mp = (5i64 * doy + 2i64) / 153i64
            let day = doy - (153i64 * mp + 2i64) / 5i64 + 1i64
            var month = mp - 9i64
            if mp < 10i64 { month = mp + 3i64 }
            if month <= 2i64 { year += 1i64 }
            let hour = rem / 3600i64
            let minute = (rem % 3600i64) / 60i64
            let second = rem % 60i64
            var wday = (days + 4i64) % 7i64
            if wday < 0i64 { wday += 7i64 }
            let yday = days - days_from_civil(year, 1i64, 1i64)
            var k = 0usize
            while k < fmt.len {
                let c = fmt[k]
                if c != 37u8 || k + 1usize >= fmt.len {
                    let _ = str.push_byte(&b, c)
                    k += 1usize
                } else {
                    let f = fmt[k + 1usize]
                    k += 2usize
                    if f == 89u8 {
                         push_pad(&b, year, 4usize, 48u8)
                        continue
                    }
                    if f == 121u8 {
                         push_pad(&b, ((year % 100i64) + 100i64) % 100i64, 2usize, 48u8)
                        continue
                    }
                    if f == 109u8 {
                         push_pad(&b, month, 2usize, 48u8)
                        continue
                    }
                    if f == 100u8 {
                         push_pad(&b, day, 2usize, 48u8)
                        continue
                    }
                    if f == 101u8 {
                         push_pad(&b, day, 2usize, 32u8)
                        continue
                    }
                    if f == 72u8 {
                         push_pad(&b, hour, 2usize, 48u8)
                        continue
                    }
                    if f == 73u8 {
                        var h12 = hour % 12i64
                        if h12 == 0i64 { h12 = 12i64 }
                        push_pad(&b, h12, 2usize, 48u8)
                        continue
                    }
                    if f == 77u8 {
                         push_pad(&b, minute, 2usize, 48u8)
                        continue
                    }
                    if f == 83u8 {
                         push_pad(&b, second, 2usize, 48u8)
                        continue
                    }
                    if f == 112u8 {
                         if hour < 12i64 { let _ = str.push(&b, "AM") } else { let _ = str.push(&b, "PM") }
                        continue
                    }
                    if f == 98u8 || f == 104u8 {
                        let _ = str.push(&b, month_name(month, false))
                        continue
                    }
                    if f == 66u8 {
                         let _ = str.push(&b, month_name(month, true))
                        continue
                    }
                    if f == 97u8 {
                         let _ = str.push(&b, weekday_name(wday, false))
                        continue
                    }
                    if f == 65u8 {
                         let _ = str.push(&b, weekday_name(wday, true))
                        continue
                    }
                    if f == 106u8 {
                         push_pad(&b, yday + 1i64, 3usize, 48u8)
                        continue
                    }
                    if f == 117u8 {
                         if wday == 0i64 { push_pad(&b, 7i64, 1usize, 48u8) } else { push_pad(&b, wday, 1usize, 48u8) }
                        continue
                    }
                    if f == 119u8 {
                         push_pad(&b, wday, 1usize, 48u8)
                        continue
                    }
                    if f == 85u8 {
                         push_pad(&b, (yday + 7i64 - wday) / 7i64, 2usize, 48u8)
                        continue
                    }
                    if f == 87u8 {
                         push_pad(&b, (yday + 7i64 - (wday + 6i64) % 7i64) / 7i64, 2usize, 48u8)
                        continue
                    }
                    if f == 90u8 {
                         let _ = str.push(&b, "UTC")
                        continue
                    }
                    if f == 122u8 {
                         let _ = str.push(&b, "+0000")
                        continue
                    }
                    if f == 70u8 {
                        push_pad(&b, year, 4usize, 48u8)
                        let _ = str.push_byte(&b, 45u8)
                        push_pad(&b, month, 2usize, 48u8)
                        let _ = str.push_byte(&b, 45u8)
                        push_pad(&b, day, 2usize, 48u8)
                        continue
                    }
                    if f == 84u8 {
                        push_pad(&b, hour, 2usize, 48u8)
                        let _ = str.push_byte(&b, 58u8)
                        push_pad(&b, minute, 2usize, 48u8)
                        let _ = str.push_byte(&b, 58u8)
                        push_pad(&b, second, 2usize, 48u8)
                        continue
                    }
                    if f == 82u8 {
                        push_pad(&b, hour, 2usize, 48u8)
                        let _ = str.push_byte(&b, 58u8)
                        push_pad(&b, minute, 2usize, 48u8)
                        continue
                    }
                    if f == 68u8 {
                        push_pad(&b, month, 2usize, 48u8)
                        let _ = str.push_byte(&b, 47u8)
                        push_pad(&b, day, 2usize, 48u8)
                        let _ = str.push_byte(&b, 47u8)
                        push_pad(&b, ((year % 100i64) + 100i64) % 100i64, 2usize, 48u8)
                        continue
                    }
                    if f == 110u8 {
                         let _ = str.push_byte(&b, 10u8)
                        continue
                    }
                    if f == 116u8 {
                         let _ = str.push_byte(&b, 9u8)
                        continue
                    }
                    if f == 37u8 {
                         let _ = str.push_byte(&b, 37u8)
                        continue
                    }
                        let _ = str.push_byte(&b, 37u8)
                        let _ = str.push_byte(&b, f)
                }
            }
        }
        out[i] = str.done(&b)
        i += 1usize
    }
    ret (out, ok)
}
