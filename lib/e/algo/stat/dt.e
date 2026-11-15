// The algorithms of R's data.table that are not data-frame verbs: the rolling functions
// (`frollmean`, `frollsum`, `frollmax`, `frollmin`, `frollmedian` as `frollapply` with a built-in
// function, with `align`, `fill`, `na.rm` and `adaptive` windows), `shift`, `rleid`, `between`,
// `inrange`, `foverlaps` (the pairs it matches) and `forder` (a stable ordering, NA first or
// last or dropped). NA is NaN. Results of the rolling functions are the exact algorithm
// (`algo = "exact"`), which equals the fast one wherever there is no rounding drift.
//
// Not here: the keyed `[.data.table` machinery, `frollmean` with `hasNA = FALSE` shortcuts,
// `maxgap` and `minoverlap` in `foverlaps` (their defaults are used), and `forder` on strings.

use e.math
use e.mem

error Unsupported

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nan(x: f64) -> bool { ret x != x }

// kind: 0 mean, 1 sum, 2 max, 3 min, 4 median. align: 0 right, 1 left, 2 center.
fn window_value(x: []const f64, from: usize, to: usize, kind: u8, na_rm: bool, buf: []f64) -> f64 {
    var n = 0usize
    var i = from
    while i <= to {
        let v = x[i]
        if is_nan(v) {
            if !na_rm { ret nan() }
        } else {
            buf[n] = v
            n += 1usize
        }
        i += 1usize
    }
    if kind == 1u8 {
        var s = 0.0f64
        var c = 0.0f64
        var k = 0usize
        while k < n {
            let t = s + buf[k]
            var a = s
            if a < 0.0f64 { a = 0.0f64 - a }
            var b = buf[k]
            if b < 0.0f64 { b = 0.0f64 - b }
            if a >= b { c = c + ((s - t) + buf[k]) } else { c = c + ((buf[k] - t) + s) }
            s = t
            k += 1usize
        }
        if n == 0usize { ret 0.0f64 }
        ret s + c
    }
    if n == 0usize {
        if kind == 0u8 { ret nan() }
        if kind == 2u8 { ret 0.0f64 - mem.bitcast[f64](9218868437227405312u64) }
        if kind == 3u8 { ret mem.bitcast[f64](9218868437227405312u64) }
        ret nan()
    }
    if kind == 0u8 {
        var s = 0.0f64
        var c = 0.0f64
        var k = 0usize
        while k < n {
            let t = s + buf[k]
            var a = s
            if a < 0.0f64 { a = 0.0f64 - a }
            var b = buf[k]
            if b < 0.0f64 { b = 0.0f64 - b }
            if a >= b { c = c + ((s - t) + buf[k]) } else { c = c + ((buf[k] - t) + s) }
            s = t
            k += 1usize
        }
        ret (s + c) / f64(n)
    }
    var best = buf[0usize]
    if kind == 2u8 || kind == 3u8 {
        var k = 1usize
        while k < n {
            if kind == 2u8 && buf[k] > best { best = buf[k] }
            if kind == 3u8 && buf[k] < best { best = buf[k] }
            k += 1usize
        }
        ret best
    }
    // median
    var q = 1usize
    while q < n {
        let v = buf[q]
        var j = q
        while j > 0usize && buf[j - 1usize] > v {
            buf[j] = buf[j - 1usize]
            j -= 1usize
        }
        buf[j] = v
        q += 1usize
    }
    if n % 2usize == 1usize { ret buf[n / 2usize] }
    ret (buf[n / 2usize - 1usize] + buf[n / 2usize]) / 2.0f64
}

// frollmean(x, n, fill, algo = "exact", align, na.rm) and its siblings; a fixed window `n`.
fn froll(a: *mem.Arena, x: []const f64, n: usize, kind: u8, align: u8, fill: f64, na_rm: bool) -> ([]f64, err) {
    let len = x.len
    let (out, e) = mem.alloc[f64](a, len)
    let (buf, be) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (out, e) }
    if be != ok { ret (out, be) }
    var i = 0usize
    while i < len {
        // window start (may be before 0) as a signed value
        var start = i64(i) - i64(n) + 1i64
        if align == 1u8 { start = i64(i) }
        if align == 2u8 { start = i64(i) - i64((n - 1usize) / 2usize) }
        let end = start + i64(n) - 1i64
        if start < 0i64 || end >= i64(len) {
            out[i] = fill
        } else {
            out[i] = window_value(x, usize(start), usize(end), kind, na_rm, buf)
        }
        i += 1usize
    }
    ret (out, ok)
}

// The adaptive form: window i ends at i and holds `n[i]` values.
fn froll_adaptive(a: *mem.Arena, x: []const f64, n: []const usize, kind: u8, fill: f64, na_rm: bool) -> ([]f64, err) {
    let len = x.len
    let (out, e) = mem.alloc[f64](a, len)
    let (buf, be) = mem.alloc[f64](a, len + 1usize)
    if e != ok { ret (out, e) }
    if be != ok { ret (out, be) }
    var i = 0usize
    while i < len {
        let w = n[i]
        if w == 0usize || w > i + 1usize {
            out[i] = fill
        } else {
            out[i] = window_value(x, i + 1usize - w, i, kind, na_rm, buf)
        }
        i += 1usize
    }
    ret (out, ok)
}

// shift(x, n, fill, type): type 0 lag, 1 lead (n > 0 shifts toward the end for lag), 2 cyclic.
fn shift(a: *mem.Arena, x: []const f64, n: i64, fill: f64, kind: u8) -> ([]f64, err) {
    let len = x.len
    let (out, e) = mem.alloc[f64](a, len)
    if e != ok { ret (out, e) }
    var by = n
    if kind == 1u8 { by = 0i64 - n }
    var i = 0usize
    while i < len {
        var src = i64(i) - by
        if kind == 2u8 {
            if len > 0usize {
                var m = src % i64(len)
                if m < 0i64 { m += i64(len) }
                src = m
            }
            out[i] = x[usize(src)]
        } else if src < 0i64 || src >= i64(len) {
            out[i] = fill
        } else {
            out[i] = x[usize(src)]
        }
        i += 1usize
    }
    ret (out, ok)
}

fn same_value(a: f64, b: f64) -> bool {
    if is_nan(a) && is_nan(b) { ret true }
    ret mem.bitcast[u64](a) == mem.bitcast[u64](b)
}

// rleid(x): the run id of each element, NA equal to NA.
fn rleid(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (out, e) }
    var id = 0.0f64
    var i = 0usize
    while i < x.len {
        if i == 0usize || !same_value(x[i], x[i - 1usize]) { id = id + 1.0f64 }
        out[i] = id
        i += 1usize
    }
    ret (out, ok)
}

// between(x, lower, upper, incbounds, NAbounds = TRUE): 1 true, 0 false, NaN (NA) when x is NA;
// an NA bound is no bound.
fn between(x: f64, lower: f64, upper: f64, inc: bool) -> f64 {
    if is_nan(x) { ret nan() }
    if !is_nan(lower) {
        if inc { if !(x >= lower) { ret 0.0f64 } } else { if !(x > lower) { ret 0.0f64 } }
    }
    if !is_nan(upper) {
        if inc { if !(x <= upper) { ret 0.0f64 } } else { if !(x < upper) { ret 0.0f64 } }
    }
    ret 1.0f64
}

// inrange(x, lower, upper, incbounds): whether x lies in any of the ranges.
fn inrange(x: f64, lower: []const f64, upper: []const f64, inc: bool) -> bool {
    var i = 0usize
    while i < lower.len {
        let r = between(x, lower[i], upper[i], inc)
        if r == 1.0f64 { ret true }
        i += 1usize
    }
    ret false
}

// foverlaps(x, y, type, mult, nomatch, which = TRUE): the (xid, yid) pairs, 1-based, with NaN
// for no match under nomatch = NA. `y` is in its key order. type: 0 any, 1 within, 2 start, 3 end,
// 4 equal. mult: 0 all, 1 first, 2 last. nomatch_na: keep unmatched x rows.
fn foverlaps(a: *mem.Arena, xs: []const f64, xe: []const f64, ys: []const f64, ye: []const f64, kind: u8, mult: u8, nomatch_na: bool) -> ([]f64, err) {
    let cap = xs.len * (ys.len + 1usize)
    let (pairs, e) = mem.alloc[f64](a, 2usize * cap)
    if e != ok { ret (pairs, e) }
    var n = 0usize
    var i = 0usize
    while i < xs.len {
        var found = 0usize
        var first = 0usize
        var last = 0usize
        var j = 0usize
        while j < ys.len {
            var hit = false
            if kind == 0u8 { hit = xs[i] <= ye[j] && xe[i] >= ys[j] }
            if kind == 1u8 { hit = xs[i] >= ys[j] && xe[i] <= ye[j] }
            if kind == 2u8 { hit = xs[i] == ys[j] && xs[i] <= ye[j] && xe[i] >= ys[j] }
            if kind == 3u8 { hit = xe[i] == ye[j] && xs[i] <= ye[j] && xe[i] >= ys[j] }
            if kind == 4u8 { hit = xs[i] == ys[j] && (xe[i] == ye[j] || xs[i] == xe[i]) }
            if hit {
                if found == 0usize { first = j }
                last = j
                found += 1usize
                if mult == 0u8 {
                    pairs[2usize * n] = f64(i + 1usize)
                    pairs[2usize * n + 1usize] = f64(j + 1usize)
                    n += 1usize
                }
            }
            j += 1usize
        }
        if found > 0usize && mult != 0u8 {
            pairs[2usize * n] = f64(i + 1usize)
            if mult == 1u8 { pairs[2usize * n + 1usize] = f64(first + 1usize) } else { pairs[2usize * n + 1usize] = f64(last + 1usize) }
            n += 1usize
        }
        if found == 0usize && nomatch_na {
            pairs[2usize * n] = f64(i + 1usize)
            pairs[2usize * n + 1usize] = nan()
            n += 1usize
        }
        i += 1usize
    }
    ret (pairs[0usize..2usize * n], ok)
}

// forder(x, order = ±1, na.last): the stable ordering as 1-based positions. na_last: 1 last,
// 0 first, -1 dropped.
fn forder(a: *mem.Arena, x: []const f64, decreasing: bool, na_last: i64) -> ([]f64, err) {
    let len = x.len
    let (idx, e) = mem.alloc[usize](a, len)
    if e != ok { ret (no_values(), e) }
    var m = 0usize
    var i = 0usize
    while i < len {
        if !is_nan(x[i]) || na_last >= 0i64 {
            idx[m] = i
            m += 1usize
        }
        i += 1usize
    }
    // insertion sort, stable
    i = 1usize
    while i < m {
        let v = idx[i]
        var j = i
        while j > 0usize && before(x, idx[j - 1usize], v, decreasing, na_last) == false {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = v
        i += 1usize
    }
    let (out, oe) = mem.alloc[f64](a, m)
    if oe != ok { ret (out, oe) }
    i = 0usize
    while i < m {
        out[i] = f64(idx[i] + 1usize)
        i += 1usize
    }
    ret (out, ok)
}

// Whether row p must stay before row q (p comes first in the input, so ties keep it first).
fn before(x: []const f64, p: usize, q: usize, decreasing: bool, na_last: i64) -> bool {
    let pn = is_nan(x[p])
    let qn = is_nan(x[q])
    if pn && qn { ret true }
    if pn { ret na_last == 0i64 }
    if qn { ret na_last != 0i64 }
    if decreasing { ret x[p] >= x[q] }
    ret x[p] <= x[q]
}

fn no_values() -> []f64 {
    var none: []f64 = zero
    ret none
}
