// The algorithms of R's zoo that are not data-frame verbs: `rollapply` (mean, sum, median, max, min
// over a width, with `by`, `align`, `partial` and `fill` as zoo defines them), `na.fill`,
// `na.locf` (`fromLast`, `maxgap`, `na.rm`), `na.approx` and `na.spline` (fmm and natural, with
// `rule`, `maxgap` and `na.rm`), `yearmon` and `yearqtr` arithmetic and formatting, and `merge` of
// two series by index. NA is NaN. The index of a series is a sorted vector of numbers.
//
// Not here: rollapply with a user function, matrices, `zooreg` frequency arithmetic, `na.approx`
// with `xout`, `na.spline` methods other than fmm and natural, `merge` with duplicate indexes and
// `fill` for interior "extend" over an irregular index (the interpolation is by position, as zoo
// does for plain zoo objects).

use e.math
use e.mem
use e.str

error Unsupported

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nan(x: f64) -> bool { ret x != x }

fn no_values() -> []f64 {
    var none: []f64 = zero
    ret none
}

fn no_positions() -> []usize {
    var none: []usize = zero
    ret none
}

// --- Window statistics

fn sum_of(buf: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var c = 0.0f64
    var k = 0usize
    while k < n {
        let t = s + buf[k]
        var p = s
        if p < 0.0f64 { p = 0.0f64 - p }
        var q = buf[k]
        if q < 0.0f64 { q = 0.0f64 - q }
        if p >= q { c = c + ((s - t) + buf[k]) } else { c = c + ((buf[k] - t) + s) }
        s = t
        k += 1usize
    }
    ret s + c
}

// kind: 0 mean, 1 sum, 2 median, 3 max, 4 min. Any NA gives NA.
fn window_value(buf: []f64, n: usize, kind: u8) -> f64 {
    var k = 0usize
    while k < n {
        if is_nan(buf[k]) { ret nan() }
        k += 1usize
    }
    if kind == 1u8 { ret sum_of(buf, n) }
    if kind == 0u8 {
        let m = sum_of(buf, n) / f64(n)
        var t = 0.0f64
        var d = 0.0f64
        var c = 0.0f64
        k = 0usize
        while k < n {
            let v = buf[k] - m
            let u = d + v
            var p = d
            if p < 0.0f64 { p = 0.0f64 - p }
            var q = v
            if q < 0.0f64 { q = 0.0f64 - q }
            if p >= q { c = c + ((d - u) + v) } else { c = c + ((v - u) + d) }
            d = u
            k += 1usize
        }
        t = (d + c) / f64(n)
        ret m + t
    }
    var best = buf[0usize]
    if kind == 3u8 || kind == 4u8 {
        k = 1usize
        while k < n {
            if kind == 3u8 && buf[k] > best { best = buf[k] }
            if kind == 4u8 && buf[k] < best { best = buf[k] }
            k += 1usize
        }
        ret best
    }
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

// --- rollapply

// rollapply(x, width, FUN, by, align, partial): the computed values and their 0-based positions.
// kind as above; align 0 center, 1 left, 2 right; partial -1 for FALSE, else the least number of
// points a window must hold (TRUE is 1).
fn rollapply(a: *mem.Arena, x: []const f64, kind: u8, width: i64, by: i64, align: u8, partial: i64) -> ([]f64, []usize, err) {
    let n = i64(x.len)
    let (vals, ve) = mem.alloc[f64](a, x.len + 1usize)
    let (pos, pe) = mem.alloc[usize](a, x.len + 1usize)
    let (buf, be) = mem.alloc[f64](a, usize(width) + 1usize)
    if ve != ok { ret (vals, pos, ve) }
    if pe != ok { ret (vals, pos, pe) }
    if be != ok { ret (vals, pos, be) }
    if n == 0i64 { ret (vals[0usize..0usize], pos[0usize..0usize], ok) }
    var hi = 0i64
    if align == 0u8 { hi = width / 2i64 }
    if align == 1u8 { hi = width - 1i64 }
    let lo = hi - (width - 1i64)
    var start = 1i64
    if partial < 0i64 {
        start = 1i64
        if 0i64 - lo > 0i64 { start = 0i64 - lo + 1i64 }
    }
    if start > n { start = n }
    var count = 0usize
    var i = start
    while i <= n {
        var have = 0usize
        var p = i + lo
        while p <= i + hi {
            if p >= 1i64 && p <= n {
                buf[have] = x[usize(p - 1i64)]
                have += 1usize
            }
            p += 1i64
        }
        var need = partial
        if partial < 0i64 { need = width }
        if i64(have) >= need && have > 0usize {
            vals[count] = window_value(buf, have, kind)
            pos[count] = usize(i - 1i64)
            count += 1usize
        }
        i += by
    }
    ret (vals[0usize..count], pos[0usize..count], ok)
}

// zoo's na.fill(dat, fill, ix) over the computed points `pos` of a series of length n. `codes` is
// (code, value) three times, for the points before the first computed one, between, and after
// the last: code 0 a value (NaN for NA), 1 "extend".
fn fill_positions(a: *mem.Arena, n: usize, vals: []const f64, pos: []const usize, codes: []const f64) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, n + 1usize)
    let (isx, xe) = mem.alloc[bool](a, n + 1usize)
    if e != ok { ret (out, e) }
    if xe != ok { ret (out, xe) }
    var i = 0usize
    while i < n {
        out[i] = nan()
        isx[i] = false
        i += 1usize
    }
    var k = 0usize
    while k < pos.len {
        out[pos[k]] = vals[k]
        isx[pos[k]] = true
        k += 1usize
    }
    if pos.len == 0usize {
        i = 0usize
        while i < n {
            if codes[0usize] == 1.0f64 { out[i] = nan() } else { out[i] = codes[1usize] }
            i += 1usize
        }
        ret (out[0usize..n], ok)
    }
    let first = pos[0usize]
    let last = pos[pos.len - 1usize]
    // left
    i = 0usize
    while i < first {
        if codes[0usize] == 1.0f64 { out[i] = vals[0usize] } else { out[i] = codes[1usize] }
        i += 1usize
    }
    // between
    if codes[2usize] == 1.0f64 {
        // approx(wix, object[wix], xout = first:last): NA points are dropped, rule 1
        let (xs, xse) = mem.alloc[usize](a, pos.len + 1usize)
        let (ys, yse) = mem.alloc[f64](a, pos.len + 1usize)
        if xse != ok { ret (out, xse) }
        if yse != ok { ret (out, yse) }
        var m = 0usize
        k = 0usize
        while k < pos.len {
            if !is_nan(vals[k]) {
                xs[m] = pos[k]
                ys[m] = vals[k]
                m += 1usize
            }
            k += 1usize
        }
        i = first
        while i <= last {
            var v = nan()
            if m >= 2usize && i >= xs[0usize] && i <= xs[m - 1usize] {
                var j = 0usize
                while j + 1usize < m && xs[j + 1usize] <= i { j += 1usize }
                if xs[j] == i {
                    v = ys[j]
                } else {
                    let f = f64(i - xs[j]) / f64(xs[j + 1usize] - xs[j])
                    v = ys[j] + f * (ys[j + 1usize] - ys[j])
                }
            }
            out[i] = v
            i += 1usize
        }
    } else {
        i = first
        while i <= last {
            if !isx[i] { out[i] = codes[3usize] }
            i += 1usize
        }
    }
    // right
    i = last + 1usize
    while i < n {
        if codes[4usize] == 1.0f64 { out[i] = vals[pos.len - 1usize] } else { out[i] = codes[5usize] }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// na.fill(object, fill) with the points that are not NA as the computed ones.
fn na_fill(a: *mem.Arena, x: []const f64, codes: []const f64) -> ([]f64, err) {
    let (vals, ve) = mem.alloc[f64](a, x.len + 1usize)
    let (pos, pe) = mem.alloc[usize](a, x.len + 1usize)
    if ve != ok { ret (vals, ve) }
    if pe != ok { ret (vals, pe) }
    var m = 0usize
    var i = 0usize
    while i < x.len {
        if !is_nan(x[i]) {
            vals[m] = x[i]
            pos[m] = i
            m += 1usize
        }
        i += 1usize
    }
    let (r, e) = fill_positions(a, x.len, vals[0usize..m], pos[0usize..m], codes)
    ret (r, e)
}

// --- na.locf, na.approx, na.spline

// The kept range of na.trim(is.na = "all", maxgap): `lo` and `hi`, hi exclusive; maxgap < 0 is Inf.
fn trim_range(x: []const f64, maxgap: i64) -> (usize, usize) {
    let n = x.len
    var first = n
    var last = 0usize
    var found = false
    var i = 0usize
    while i < n {
        if !is_nan(x[i]) {
            if !found { first = i }
            last = i
            found = true
        }
        i += 1usize
    }
    let big = maxgap >= 0i64
    if !found {
        if big && i64(n) > maxgap { ret (0usize, n) }
        ret (0usize, 0usize)
    }
    var lo = first
    var hi = last + 1usize
    if big && i64(first) > maxgap { lo = 0usize }
    if big && i64(n - 1usize - last) > maxgap { hi = n }
    ret (lo, hi)
}

// Which points sit in a run of NA longer than maxgap (maxgap >= 0).
fn long_gaps(a: *mem.Arena, y: []const f64, maxgap: i64) -> ([]bool, err) {
    let (bad, e) = mem.alloc[bool](a, y.len + 1usize)
    if e != ok { ret (bad, e) }
    var i = 0usize
    while i < y.len {
        bad[i] = false
        i += 1usize
    }
    i = 0usize
    while i < y.len {
        if is_nan(y[i]) {
            var j = i
            while j < y.len && is_nan(y[j]) { j += 1usize }
            if i64(j - i) > maxgap {
                var k = i
                while k < j {
                    bad[k] = true
                    k += 1usize
                }
            }
            i = j
        } else {
            i += 1usize
        }
    }
    ret (bad[0usize..y.len], ok)
}

// na.locf(zoo(x), na.rm, fromLast, maxgap); maxgap < 0 is Inf.
fn na_locf(a: *mem.Arena, x: []const f64, from_last: bool, maxgap: i64, na_rm: bool) -> ([]f64, err) {
    let n = x.len
    let (out, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < n {
        var src = i
        if from_last { src = n - 1usize - i }
        out[i] = x[src]
        i += 1usize
    }
    // forward fill of the (possibly reversed) copy
    var last_good = nan()
    var have = false
    let (lg, le) = long_gaps(a, out[0usize..n], maxgap)
    if le != ok { ret (out, le) }
    let (src_vals, sve) = mem.alloc[f64](a, n + 1usize)
    if sve != ok { ret (out, sve) }
    i = 0usize
    while i < n {
        if !is_nan(out[i]) {
            last_good = out[i]
            have = true
        }
        if have { src_vals[i] = last_good } else { src_vals[i] = nan() }
        i += 1usize
    }
    i = 0usize
    while i < n {
        if is_nan(out[i]) {
            var skip = false
            if maxgap >= 0i64 && lg[i] { skip = true }
            if !skip { out[i] = src_vals[i] }
        }
        i += 1usize
    }
    // undo the reversal
    if from_last {
        i = 0usize
        while i < n / 2usize {
            let t = out[i]
            out[i] = out[n - 1usize - i]
            out[n - 1usize - i] = t
            i += 1usize
        }
    }
    if na_rm {
        let (lo, hi) = trim_range(out[0usize..n], -1i64)
        ret (out[lo..hi], ok)
    }
    ret (out[0usize..n], ok)
}

// approx(x, y, xout = x, rule) over the non-NA points; rule 1 gives NA outside, 2 repeats the end.
fn approx_at(xs: []const f64, ys: []const f64, m: usize, xo: f64, rule: i64) -> f64 {
    if xo < xs[0usize] {
        if rule == 2i64 { ret ys[0usize] }
        ret nan()
    }
    if xo > xs[m - 1usize] {
        if rule == 2i64 { ret ys[m - 1usize] }
        ret nan()
    }
    var j = 0usize
    while j + 1usize < m && xs[j + 1usize] <= xo { j += 1usize }
    if xs[j] == xo { ret ys[j] }
    let f = (xo - xs[j]) / (xs[j + 1usize] - xs[j])
    ret ys[j] + f * (ys[j + 1usize] - ys[j])
}

fn na_approx(a: *mem.Arena, idx: []const f64, y: []const f64, rule: i64, maxgap: i64, na_rm: bool) -> ([]f64, err) {
    let n = y.len
    let (out, e) = mem.alloc[f64](a, n + 1usize)
    let (xs, xe) = mem.alloc[f64](a, n + 1usize)
    let (ys, ye) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (out, e) }
    if xe != ok { ret (out, xe) }
    if ye != ok { ret (out, ye) }
    var m = 0usize
    var i = 0usize
    while i < n {
        if !is_nan(y[i]) {
            xs[m] = idx[i]
            ys[m] = y[i]
            m += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = nan()
        i += 1usize
    }
    if m < 2usize {
        if m == 1usize {
            i = 0usize
            while i < n {
                if idx[i] == xs[0usize] { out[i] = ys[0usize] }
                i += 1usize
            }
        }
        ret (out[0usize..n], ok)
    }
    i = 0usize
    while i < n {
        out[i] = approx_at(xs, ys, m, idx[i], rule)
        i += 1usize
    }
    if maxgap >= 0i64 && maxgap < i64(n) {
        let (lg, le) = long_gaps(a, y, maxgap)
        if le != ok { ret (out, le) }
        i = 0usize
        while i < n {
            if lg[i] { out[i] = nan() }
            i += 1usize
        }
    }
    if na_rm {
        let (lo, hi) = trim_range(out[0usize..n], maxgap)
        ret (out[lo..hi], ok)
    }
    ret (out[0usize..n], ok)
}

// R's spline_coef: method 0 fmm, 1 natural. Arrays are 0-based here; the C code is 1-based.
fn spline_coef(method: u8, n: usize, x: []const f64, y: []const f64, b: []f64, c: []f64, d: []f64) {
    var i = 0usize
    while i < n {
        b[i] = 0.0f64
        c[i] = 0.0f64
        d[i] = 0.0f64
        i += 1usize
    }
    if n < 2usize { ret }
    if n < 3usize {
        let t = y[1usize] - y[0usize]
        b[0usize] = t / (x[1usize] - x[0usize])
        b[1usize] = b[0usize]
        ret
    }
    let nm1 = n - 1usize
    d[0usize] = x[1usize] - x[0usize]
    c[1usize] = (y[1usize] - y[0usize]) / d[0usize]
    i = 1usize
    while i < nm1 {
        d[i] = x[i + 1usize] - x[i]
        b[i] = 2.0f64 * (d[i - 1usize] + d[i])
        c[i + 1usize] = (y[i + 1usize] - y[i]) / d[i]
        c[i] = c[i + 1usize] - c[i]
        i += 1usize
    }
    if method == 1u8 {
        i = 2usize
        while i < nm1 {
            let t = d[i - 1usize] / b[i - 1usize]
            b[i] = b[i] - t * d[i - 1usize]
            c[i] = c[i] - t * c[i - 1usize]
            i += 1usize
        }
        c[nm1 - 1usize] = c[nm1 - 1usize] / b[nm1 - 1usize]
        i = n - 3usize
        while i > 0usize {
            c[i] = (c[i] - d[i] * c[i + 1usize]) / b[i]
            i -= 1usize
        }
        c[0usize] = 0.0f64
        c[nm1] = 0.0f64
        b[0usize] = (y[1usize] - y[0usize]) / d[0usize] - d[0usize] * c[1usize]
        c[0usize] = 0.0f64
        d[0usize] = c[1usize] / d[0usize]
        b[nm1] = (y[nm1] - y[nm1 - 1usize]) / d[nm1 - 1usize] + d[nm1 - 1usize] * c[nm1 - 1usize]
        i = 1usize
        while i < nm1 {
            b[i] = (y[i + 1usize] - y[i]) / d[i] - d[i] * (c[i + 1usize] + 2.0f64 * c[i])
            d[i] = (c[i + 1usize] - c[i]) / d[i]
            c[i] = 3.0f64 * c[i]
            i += 1usize
        }
        c[nm1] = 0.0f64
        d[nm1] = 0.0f64
        ret
    }
    // fmm
    b[0usize] = 0.0f64 - d[0usize]
    b[nm1] = 0.0f64 - d[nm1 - 1usize]
    c[0usize] = 0.0f64
    c[nm1] = 0.0f64
    if n > 3usize {
        c[0usize] = c[2usize] / (x[3usize] - x[1usize]) - c[1usize] / (x[2usize] - x[0usize])
        c[nm1] = c[nm1 - 1usize] / (x[nm1] - x[nm1 - 2usize]) - c[nm1 - 2usize] / (x[nm1 - 1usize] - x[nm1 - 3usize])
        c[0usize] = c[0usize] * d[0usize] * d[0usize] / (x[3usize] - x[0usize])
        c[nm1] = 0.0f64 - c[nm1] * d[nm1 - 1usize] * d[nm1 - 1usize] / (x[nm1] - x[nm1 - 3usize])
    }
    i = 1usize
    while i < n {
        let t = d[i - 1usize] / b[i - 1usize]
        b[i] = b[i] - t * d[i - 1usize]
        c[i] = c[i] - t * c[i - 1usize]
        i += 1usize
    }
    c[nm1] = c[nm1] / b[nm1]
    i = nm1
    while i > 0usize {
        i -= 1usize
        c[i] = (c[i] - d[i] * c[i + 1usize]) / b[i]
    }
    b[nm1] = (y[nm1] - y[nm1 - 1usize]) / d[nm1 - 1usize] + d[nm1 - 1usize] * (c[nm1 - 1usize] + 2.0f64 * c[nm1])
    i = 0usize
    while i < nm1 {
        b[i] = (y[i + 1usize] - y[i]) / d[i] - d[i] * (c[i + 1usize] + 2.0f64 * c[i])
        d[i] = (c[i + 1usize] - c[i]) / d[i]
        c[i] = 3.0f64 * c[i]
        i += 1usize
    }
    c[nm1] = 3.0f64 * c[nm1]
    d[nm1] = d[nm1 - 1usize]
}

type Cursor = struct { i: usize }

// R's spline_eval step: the interval index persists between calls, so a point that is exactly
// a node can be answered from the interval on its left.
fn spline_at(method: u8, n: usize, x: []const f64, y: []const f64, b: []const f64, c: []const f64, d: []const f64, u: f64, cur: *Cursor) -> f64 {
    var i = cur.i
    if u < x[0usize] || (i < n - 1usize && x[i + 1usize] < u) {
        i = 0usize
        var j = n
        while j > i + 1usize {
            let k = (i + j) / 2usize
            if u < x[k] { j = k } else { i = k }
        }
    }
    cur.i = i
    let dx = u - x[i]
    var tmp = d[i]
    if method == 1u8 && u < x[0usize] { tmp = 0.0f64 }
    ret y[i] + dx * (b[i] + dx * (c[i] + dx * tmp))
}

fn na_spline(a: *mem.Arena, idx: []const f64, y: []const f64, method: u8, maxgap: i64, na_rm: bool) -> ([]f64, err) {
    let n = y.len
    let (out, e) = mem.alloc[f64](a, n + 1usize)
    let (xs, xe) = mem.alloc[f64](a, n + 1usize)
    let (ys, ye) = mem.alloc[f64](a, n + 1usize)
    let (b, be) = mem.alloc[f64](a, n + 1usize)
    let (c, ce) = mem.alloc[f64](a, n + 1usize)
    let (d, de) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (out, e) }
    if xe != ok { ret (out, xe) }
    if ye != ok { ret (out, ye) }
    if be != ok { ret (out, be) }
    if ce != ok { ret (out, ce) }
    if de != ok { ret (out, de) }
    var m = 0usize
    var i = 0usize
    while i < n {
        if !is_nan(y[i]) {
            xs[m] = idx[i]
            ys[m] = y[i]
            m += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = nan()
        i += 1usize
    }
    if m < 1usize { ret (out[0usize..n], ok) }
    spline_coef(method, m, xs, ys, b, c, d)
    var cur = Cursor { i: 0usize }
    i = 0usize
    while i < n {
        out[i] = spline_at(method, m, xs, ys, b, c, d, idx[i], &cur)
        i += 1usize
    }
    if maxgap >= 0i64 && maxgap < i64(n) {
        // ix <- splinefun(x, seq_along(y))(xout); a point is NA when the gap at floor(ix) or ceiling(ix) is long
        let (lg, le) = long_gaps(a, y, maxgap)
        if le != ok { ret (out, le) }
        let (pos, pe) = mem.alloc[f64](a, n + 1usize)
        if pe != ok { ret (out, pe) }
        i = 0usize
        while i < n {
            pos[i] = f64(i + 1usize)
            i += 1usize
        }
        spline_coef(method, n, idx, pos, b, c, d)
        cur.i = 0usize
        i = 0usize
        while i < n {
            let ix = spline_at(method, n, idx, pos, b, c, d, idx[i], &cur)
            let lo = i64(math.floor[f64](ix))
            let hi = i64(math.ceil[f64](ix))
            var bad = false
            if lo >= 1i64 && lo <= i64(n) && lg[usize(lo - 1i64)] { bad = true }
            if hi >= 1i64 && hi <= i64(n) && lg[usize(hi - 1i64)] { bad = true }
            if bad { out[i] = nan() }
            i += 1usize
        }
    }
    if na_rm {
        let (lo, hi) = trim_range(out[0usize..n], maxgap)
        ret (out[lo..hi], ok)
    }
    ret (out[0usize..n], ok)
}

// --- yearmon and yearqtr

fn yearmon(v: f64) -> f64 { ret math.floor[f64](12.0f64 * v + 0.0001f64) / 12.0f64 }

fn yearqtr(v: f64) -> f64 { ret math.floor[f64](4.0f64 * v + 0.001f64) / 4.0f64 }

// x + d: the right side is converted first, then the sum, as Ops.yearmon does.
fn yearmon_add(v: f64, d: f64) -> f64 { ret yearmon(yearmon(v) + yearmon(d)) }

fn yearqtr_add(v: f64, d: f64) -> f64 { ret yearqtr(yearqtr(v) + yearqtr(d)) }

fn year_of(x: f64) -> f64 { ret math.floor[f64](x + 0.001f64) }

// (year, month) of a yearmon value (already normalised).
fn yearmon_parts(v: f64) -> (i64, i64) {
    let x = yearmon(v)
    let y = year_of(x)
    let m = math.floor[f64](12.0f64 * (x - y) + 1.0f64 + 0.5f64 + 0.001f64)
    ret (i64(y), i64(m))
}

fn yearqtr_parts(v: f64) -> (i64, i64) {
    let x = yearqtr(v)
    let y = year_of(x)
    let q = math.floor[f64](4.0f64 * (x - y) + 1.0f64 + 0.5f64 + 0.001f64)
    ret (i64(y), i64(q))
}

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

fn push_padded(b: *str.Builder, v: i64, width: usize) {
    var t = v
    if t < 0i64 { t = 0i64 - t }
    var k = 1usize
    while t >= 10i64 {
        t = t / 10i64
        k += 1usize
    }
    if v < 0i64 { k += 1usize }
    while k < width {
        let _ = str.push_byte(b, 48u8)
        k += 1usize
    }
    let _ = str.push_i64(b, v)
}

// format(as.yearmon(v), format): strftime on the first of the month (%Y %y %m %b %B %d %%).
fn yearmon_format(a: *mem.Arena, v: f64, fmt: str) -> (str, err) {
    let (year, month) = yearmon_parts(v)
    let (initial, e) = str.builder(a, fmt.len * 12usize + 32usize)
    if e != ok { ret ("", e) }
    var b = initial
    var i = 0usize
    while i < fmt.len {
        if fmt[i] == 37u8 && i + 1usize < fmt.len {
            let f = fmt[i + 1usize]
            if f == 89u8 {
                let _ = str.push_i64(&b, year)
            } else if f == 121u8 {
                var yy = year % 100i64
                if yy < 0i64 { yy += 100i64 }
                push_padded(&b, yy, 2usize)
            } else if f == 109u8 {
                push_padded(&b, month, 2usize)
            } else if f == 98u8 {
                let _ = str.push(&b, month_name(month, false))
            } else if f == 66u8 {
                let _ = str.push(&b, month_name(month, true))
            } else if f == 100u8 {
                let _ = str.push(&b, "01")
            } else if f == 37u8 {
                let _ = str.push_byte(&b, 37u8)
            } else {
                ret ("", Unsupported)
            }
            i += 2usize
        } else {
            let _ = str.push_byte(&b, fmt[i])
            i += 1usize
        }
    }
    ret (str.done(&b), ok)
}

fn replace_all(a: *mem.Arena, s: str, pat: str, rep: str) -> (str, err) {
    let (initial, e) = str.builder(a, s.len + rep.len * (s.len + 1usize) + 8usize)
    if e != ok { ret ("", e) }
    var b = initial
    var i = 0usize
    while i < s.len {
        if i + pat.len <= s.len && str.eq(s[i..i + pat.len], pat) {
            let _ = str.push(&b, rep)
            i += pat.len
        } else {
            let _ = str.push_byte(&b, s[i])
            i += 1usize
        }
    }
    ret (str.done(&b), ok)
}

fn int_text(a: *mem.Arena, v: i64, width: usize) -> (str, err) {
    let (initial, e) = str.builder(a, 32usize)
    if e != ok { ret ("", e) }
    var b = initial
    push_padded(&b, v, width)
    ret (str.done(&b), ok)
}

// format(as.yearqtr(v), format): %q, %Y, %y and %C replaced in that order, as zoo does.
fn yearqtr_format(a: *mem.Arena, v: f64, fmt: str) -> (str, err) {
    let (year, qtr) = yearqtr_parts(v)
    let (qs, qe) = int_text(a, qtr, 0usize)
    let (ys, ye) = int_text(a, year, 0usize)
    var yy = year % 100i64
    if yy < 0i64 { yy += 100i64 }
    let (y2, y2e) = int_text(a, yy, 2usize)
    let (cs, ce) = int_text(a, year / 100i64, 0usize)
    if qe != ok { ret ("", qe) }
    if ye != ok { ret ("", ye) }
    if y2e != ok { ret ("", y2e) }
    if ce != ok { ret ("", ce) }
    let (s1, e1) = replace_all(a, fmt, "%q", qs)
    if e1 != ok { ret ("", e1) }
    let (s2, e2) = replace_all(a, s1, "%Y", ys)
    if e2 != ok { ret ("", e2) }
    let (s3, e3) = replace_all(a, s2, "%y", y2)
    if e3 != ok { ret ("", e3) }
    let (s4, e4) = replace_all(a, s3, "%C", cs)
    ret (s4, e4)
}

// --- merge

// The stable order of an index.
fn order_of(a: *mem.Arena, idx: []const f64) -> ([]usize, err) {
    let (o, e) = mem.alloc[usize](a, idx.len + 1usize)
    if e != ok { ret (o, e) }
    var i = 0usize
    while i < idx.len {
        var j = i
        while j > 0usize && idx[o[j - 1usize]] > idx[i] {
            o[j] = o[j - 1usize]
            j -= 1usize
        }
        o[j] = i
        i += 1usize
    }
    ret (o[0usize..idx.len], ok)
}

// merge(zoo(x1, i1), zoo(x2, i2), all, fill): the merged index and the two columns.
fn merge2(a: *mem.Arena, i1: []const f64, x1: []const f64, i2: []const f64, x2: []const f64, all: bool, fill: f64) -> ([]f64, []f64, []f64, err) {
    let (o1, e1) = order_of(a, i1)
    let (o2, e2) = order_of(a, i2)
    let cap = i1.len + i2.len + 1usize
    let (idx, ie) = mem.alloc[f64](a, cap)
    let (ca, ae) = mem.alloc[f64](a, cap)
    let (cb, be) = mem.alloc[f64](a, cap)
    if e1 != ok { ret (idx, ca, cb, e1) }
    if e2 != ok { ret (idx, ca, cb, e2) }
    if ie != ok { ret (idx, ca, cb, ie) }
    if ae != ok { ret (idx, ca, cb, ae) }
    if be != ok { ret (idx, ca, cb, be) }
    var n = 0usize
    var p = 0usize
    var q = 0usize
    while p < o1.len || q < o2.len {
        var key = 0.0f64
        var take1 = false
        var take2 = false
        if p < o1.len && q < o2.len {
            if i1[o1[p]] < i2[o2[q]] {
                key = i1[o1[p]]
                take1 = true
            } else if i2[o2[q]] < i1[o1[p]] {
                key = i2[o2[q]]
                take2 = true
            } else {
                key = i1[o1[p]]
                take1 = true
                take2 = true
            }
        } else if p < o1.len {
            key = i1[o1[p]]
            take1 = true
        } else {
            key = i2[o2[q]]
            take2 = true
        }
        let both = take1 && take2
        if all || both {
            idx[n] = key
            if take1 { ca[n] = x1[o1[p]] } else { ca[n] = fill }
            if take2 { cb[n] = x2[o2[q]] } else { cb[n] = fill }
            n += 1usize
        }
        if take1 { p += 1usize }
        if take2 { q += 1usize }
    }
    ret (idx[0usize..n], ca[0usize..n], cb[0usize..n], ok)
}
