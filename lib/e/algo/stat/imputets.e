// R imputeTS: na_ma (simple, linear and exponential weights), na_mean (mean, median, mode, geometric, harmonic), na_replace.
// A missing value is NaN. na_locf and the interpolations are in e.algo.stat.zoo.
//
// na_locf (option locf or nocb, na_remaining rev, keep or mean) and na_interpolation (linear, spline) wrap the zoo functions.
//
// Not here: na_kalman, na_seadec, na_seasplit, na_random, statsNA, the maxgap option, na_interpolation stine.

use e.math
use e.mem
use e.algo.stat.zoo as zoo

fn is_nan(x: f64) -> bool { ret x != x }

// kind: 0 simple, 1 linear (1 / (1 + d)), 2 exponential (1 / 2^d); the window widens until it holds two values
fn na_ma(a: *mem.Arena, x: []const f64, k: usize, kind: usize) -> ([]f64, err) {
    let (o, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (o, e) }
    let n = x.len
    var i = 0usize
    while i < n {
        o[i] = x[i]
        if is_nan(x[i]) {
            var kk = k
            var done = false
            while !done && kk <= n {
                var s = 0.0f64
                var w = 0.0f64
                var cnt = 0usize
                var j = 0usize
                if i > kk { j = i - kk }
                var hi = i + kk
                if hi > n - 1usize { hi = n - 1usize }
                while j <= hi {
                    if j != i && !is_nan(x[j]) {
                        var d = f64(i) - f64(j)
                        if d < 0.0f64 { d = 0.0f64 - d }
                        var wt = 1.0f64
                        if kind == 1usize { wt = 1.0f64 / (1.0f64 + d) }
                        if kind == 2usize { wt = math.pow[f64](2.0f64, 0.0f64 - d) }
                        s += wt * x[j]
                        w += wt
                        cnt += 1usize
                    }
                    j += 1usize
                }
                if cnt >= 2usize {
                    o[i] = s / w
                    done = true
                }
                kk += 1usize
            }
        }
        i += 1usize
    }
    ret (o, ok)
}

fn sorted_copy(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    ret (s, ok)
}

// the value na_mean fills with; option 0 mean, 1 median, 2 mode (first of the most frequent, in sorted order), 3 geometric, 4 harmonic
fn na_mean_value(a: *mem.Arena, x: []const f64, option: usize) -> f64 {
    let (v, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var m = 0usize
    var i = 0usize
    while i < x.len {
        if !is_nan(x[i]) {
            v[m] = x[i]
            m += 1usize
        }
        i += 1usize
    }
    let obs = v[0usize..m]
    let (s, e2) = sorted_copy(a, obs)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let nf = f64(m)
    var t = 0.0f64
    i = 0usize
    if option == 0usize {
        while i < m {
            t += obs[i]
            i += 1usize
        }
        ret t / nf
    }
    if option == 1usize {
        if m % 2usize == 1usize { ret s[m / 2usize] }
        ret (s[m / 2usize - 1usize] + s[m / 2usize]) / 2.0f64
    }
    if option == 2usize {
        var best = 0usize
        var bc = 0usize
        var c = 1usize
        i = 1usize
        while i <= m {
            if i < m && s[i] == s[i - 1usize] {
                c += 1usize
            } else {
                if c > bc {
                    bc = c
                    best = i - 1usize
                }
                c = 1usize
            }
            i += 1usize
        }
        ret s[best]
    }
    if option == 3usize {
        while i < m {
            t += math.log[f64](obs[i])
            i += 1usize
        }
        ret math.exp[f64](t / nf)
    }
    while i < m {
        t += 1.0f64 / obs[i]
        i += 1usize
    }
    ret 1.0f64 / (t / nf)
}

fn any_nan(x: []const f64) -> bool {
    var i = 0usize
    while i < x.len {
        if is_nan(x[i]) { ret true }
        i += 1usize
    }
    ret false
}

// na_locf(x, option = "locf" or "nocb", na_remaining = "rev" (0), "keep" (1) or "mean" (2))
fn na_locf_ts(a: *mem.Arena, x: []const f64, nocb: bool, remaining: usize) -> ([]f64, err) {
    let (r1, e1) = zoo.na_locf(a, x, nocb, 0i64 - 1i64, false)
    if e1 != ok { ret (r1, e1) }
    if !any_nan(r1[0usize..x.len]) || remaining == 1usize { ret (r1[0usize..x.len], ok) }
    if remaining == 0usize {
        let (r2, e2) = zoo.na_locf(a, r1[0usize..x.len], !nocb, 0i64 - 1i64, false)
        ret (r2[0usize..x.len], e2)
    }
    let m = na_mean_value(a, r1[0usize..x.len], 0usize)
    var i = 0usize
    while i < x.len {
        if is_nan(r1[i]) { r1[i] = m }
        i += 1usize
    }
    ret (r1[0usize..x.len], ok)
}

// na_interpolation(x, option = "linear" (0) or "spline" (1)): the missing values interpolated over the index 1 .. n, constant (linear) or polynomial (spline, fmm) beyond the observed range
fn na_interpolation(a: *mem.Arena, x: []const f64, option: usize) -> ([]f64, err) {
    let n = x.len
    let (idx, e) = mem.alloc[f64](a, n)
    if e != ok { ret (idx, e) }
    var i = 0usize
    while i < n {
        idx[i] = f64(i + 1usize)
        i += 1usize
    }
    if option == 0usize {
        let (r, e2) = zoo.na_approx(a, idx, x, 2i64, 0i64 - 1i64, false)
        ret (r[0usize..n], e2)
    }
    // spline(indx, x[indx], n = n): the fmm spline of the observed points evaluated at n equally spaced points between the first and last observed index,
    // whose k-th value then fills the k-th position when it is missing (the package indexes the output by position)
    var m = 0usize
    i = 0usize
    while i < n {
        if !is_nan(x[i]) { m += 1usize }
        i += 1usize
    }
    let (xs, e4) = mem.alloc[f64](a, m)
    let (ys, e5) = mem.alloc[f64](a, m)
    let (bb, e6) = mem.alloc[f64](a, m)
    let (cc, e7) = mem.alloc[f64](a, m)
    let (dd, e8) = mem.alloc[f64](a, m)
    let (out, e9) = mem.alloc[f64](a, n)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (out, mem.Full) }
    var q = 0usize
    i = 0usize
    while i < n {
        if !is_nan(x[i]) {
            xs[q] = f64(i + 1usize)
            ys[q] = x[i]
            q += 1usize
        }
        i += 1usize
    }
    zoo.spline_coef(0u8, m, xs, ys, bb, cc, dd)
    let lo = xs[0usize]
    let hi = xs[m - 1usize]
    var cur = zoo.Cursor{ i: 0usize }
    let by = (hi - lo) / f64(n - 1usize)
    i = 0usize
    while i < n {
        var u = lo + f64(i) * by
        if i + 1usize == n { u = hi }
        if is_nan(x[i]) { out[i] = zoo.spline_at(0u8, m, xs, ys, bb, cc, dd, u, &cur) } else { out[i] = x[i] }
        i += 1usize
    }
    ret (out, ok)
}

// maxgap: runs of missing values longer than maxgap in the original series are put back to missing in the filled one (maxgap < 0 means no limit)
fn apply_maxgap(x: []const f64, filled: []f64, maxgap: i64) {
    if maxgap < 0i64 { ret }
    let n = x.len
    var i = 0usize
    while i < n {
        if is_nan(x[i]) {
            var j = i
            while j < n && is_nan(x[j]) { j += 1usize }
            if i64(j - i) > maxgap {
                var k = i
                while k < j {
                    filled[k] = 0.0f64 / 0.0f64
                    k += 1usize
                }
            }
            i = j
        } else {
            i += 1usize
        }
    }
}
