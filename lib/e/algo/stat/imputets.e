// R imputeTS: na_ma (simple, linear and exponential weights), na_mean (mean, median, mode, geometric, harmonic), na_replace.
// A missing value is NaN. na_locf and the interpolations are in e.algo.stat.zoo.
//
// na_locf (option locf or nocb, na_remaining rev, keep or mean) and na_interpolation (linear, spline) wrap the zoo functions.
//
// Not here: na_kalman, na_seadec, na_seasplit, statsNA, the maxgap option, na_interpolation stine.

use e.math
use e.mem
use e.algo.stat.zoo as zoo
use e.algo.stat.stlpkg as stl
use e.algo.rand.r as rng
use e.algo.stat.kalman as kal
use e.algo.stat.structts as sts

error TooFewData

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
    if option == 2usize {
        let (st, es) = na_stine(a, x)
        ret (st, es)
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

// na_random(x, lower_bound, upper_bound): every missing value is a uniform draw on the bounds (the minimum and maximum of the observed values when lo >= hi is passed as NaN), drawn in order of position; rg is the seeded generator
fn na_random(a: *mem.Arena, rg: *rng.Rng, x: []const f64, lo0: f64, hi0: f64) -> ([]f64, err) {
    let (r, e1) = mem.alloc[f64](a, x.len)
    if e1 != ok { ret (r, e1) }
    var lo = lo0
    var hi = hi0
    var i = 0usize
    if is_nan(lo) || is_nan(hi) {
        var mn = 1.0e300f64
        var mx = 0.0f64 - 1.0e300f64
        while i < x.len {
            if !is_nan(x[i]) {
                if x[i] < mn { mn = x[i] }
                if x[i] > mx { mx = x[i] }
            }
            i += 1usize
        }
        if is_nan(lo) { lo = mn }
        if is_nan(hi) { hi = mx }
    }
    i = 0usize
    while i < x.len {
        r[i] = x[i]
        if is_nan(x[i]) { r[i] = lo + (hi - lo) * rng.unif(rg) }
        i += 1usize
    }
    ret (r, ok)
}

// na_replace(x, fill)
fn na_replace(a: *mem.Arena, x: []const f64, fill: f64) -> ([]f64, err) {
    let (r, e1) = mem.alloc[f64](a, x.len)
    if e1 != ok { ret (r, e1) }
    var i = 0usize
    while i < x.len {
        r[i] = x[i]
        if is_nan(x[i]) { r[i] = fill }
        i += 1usize
    }
    ret (r, ok)
}

// stinepack::stinterp(indx, x[indx], 1:n) with the default scaled Stineman slopes, the positions outside the observed range then filled by na_locf(na_remaining = "rev")
fn na_stine(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let n = x.len
    var m = 0usize
    var i = 0usize
    while i < n {
        if !is_nan(x[i]) { m += 1usize }
        i += 1usize
    }
    let (xs, e1) = mem.alloc[f64](a, m)
    let (ys, e2) = mem.alloc[f64](a, m)
    let (yp, e3) = mem.alloc[f64](a, m)
    let (out, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (out, mem.Full) }
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
    if m < 2usize { ret (out, mem.Full) }
    // scaled Stineman slopes
    let sx = xs[m - 1usize] - xs[0usize]
    var mn = ys[0usize]
    var mx = ys[0usize]
    i = 1usize
    while i < m {
        if ys[i] < mn { mn = ys[i] }
        if ys[i] > mx { mx = ys[i] }
        i += 1usize
    }
    var sy = mx - mn
    if sy <= 0.0f64 { sy = 1.0f64 }
    if m == 2usize {
        let sl = (ys[1usize] - ys[0usize]) / (xs[1usize] - xs[0usize])
        yp[0usize] = sl
        yp[1usize] = sl
    } else {
        let m1 = m - 1usize
        i = 1usize
        while i < m1 {
            let dxm = (xs[i] - xs[i - 1usize]) / sx
            let dym = (ys[i] - ys[i - 1usize]) / sy
            let dxp = (xs[i + 1usize] - xs[i]) / sx
            let dyp = (ys[i + 1usize] - ys[i]) / sy
            let d2p = dxp * dxp + dyp * dyp
            let d2m = dxm * dxm + dym * dym
            yp[i] = ((dym * d2p + dyp * d2m) / (dxm * d2p + dxp * d2m)) * sy / sx
            i += 1usize
        }
        // the end slopes on the scaled data, then unscaled
        let s0 = ((ys[1usize] - ys[0usize]) / sy) / ((xs[1usize] - xs[0usize]) / sx)
        let p1 = yp[1usize] * sx / sy
        if (s0 >= 0.0f64 && s0 >= p1) || (s0 <= 0.0f64 && s0 <= p1) { yp[0usize] = (2.0f64 * s0 - p1) * sy / sx } else { yp[0usize] = (s0 + math.abs[f64](s0) * (s0 - p1) / (math.abs[f64](s0) + math.abs[f64](s0 - p1))) * sy / sx }
        let sn = ((ys[m1] - ys[m1 - 1usize]) / sy) / ((xs[m1] - xs[m1 - 1usize]) / sx)
        let pm = yp[m1 - 1usize] * sx / sy
        if (sn >= 0.0f64 && sn >= pm) || (sn <= 0.0f64 && sn <= pm) { yp[m1] = (2.0f64 * sn - pm) * sy / sx } else { yp[m1] = (sn + math.abs[f64](sn) * (sn - pm) / (math.abs[f64](sn) + math.abs[f64](sn - pm))) * sy / sx }
    }
    i = 0usize
    while i < n {
        let u = f64(i + 1usize)
        if !is_nan(x[i]) {
            out[i] = x[i]
        } else if u < xs[0usize] || u > xs[m - 1usize] {
            out[i] = 0.0f64 / 0.0f64
        } else {
            var j = 0usize
            while j + 2usize < m && xs[j + 1usize] <= u { j += 1usize }
            let dx = xs[j + 1usize] - xs[j]
            let sl = (ys[j + 1usize] - ys[j]) / dx
            let d1 = u - xs[j]
            let d2 = u - xs[j + 1usize]
            let y0 = ys[j] + sl * d1
            let o1 = (yp[j] - sl) * d1
            let o2 = (yp[j + 1usize] - sl) * d2
            let pr = o1 * o2
            var yo = y0
            if pr > 0.0f64 { yo = y0 + pr / (o1 + o2) }
            if pr < 0.0f64 { yo = y0 + pr * (d1 + d2) / (o1 - o2) / dx }
            out[i] = yo
        }
        i += 1usize
    }
    // na_locf(na_remaining = "rev"): leading gaps take the first value, trailing gaps the last
    let first = ys[0usize]
    let last = ys[m - 1usize]
    i = 0usize
    while i < n {
        if is_nan(out[i]) {
            if f64(i + 1usize) < xs[0usize] { out[i] = first } else { out[i] = last }
        }
        i += 1usize
    }
    ret (out, ok)
}

// na_seadec(x with frequency period, algorithm): linear interpolation, then the robust stl (s.window 11) of the filled series; the seasonally adjusted series with the original gaps is imputed by the algorithm (0 interpolation, 1 locf, 2 mean) and the seasonal part added back at the gaps only
fn na_seadec(a: *mem.Arena, x: []const f64, period: usize, algorithm: usize) -> ([]f64, err) {
    let n = x.len
    let (temp, e1) = na_interpolation(a, x, 0usize)
    if e1 != ok { ret (temp, e1) }
    let (season, e2) = mem.alloc[f64](a, n)
    let (trend, e3) = mem.alloc[f64](a, n)
    let (rw, e4) = mem.alloc[f64](a, n)
    let (adj, e5) = mem.alloc[f64](a, n)
    let (out, e6) = mem.alloc[f64](a, n)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (out, mem.Full) }
    let es = stl.stl(a, temp[0usize..n], period, false, 11.0f64, 0i64, 0.0f64, 1i64, 0.0f64, 1i64, 0usize, 0usize, 0usize, true, season, trend, rw)
    if es != ok { ret (out, es) }
    var i = 0usize
    while i < n {
        let remainder = temp[i] - season[i] - trend[i]
        adj[i] = trend[i] + remainder
        if is_nan(x[i]) { adj[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    var filled: []f64 = zero
    if algorithm == 0usize {
        let (f, ef) = na_interpolation(a, adj, 0usize)
        if ef != ok { ret (out, ef) }
        filled = f
    } else if algorithm == 1usize {
        let (f, ef) = na_locf_ts(a, adj, false, 0usize)
        if ef != ok { ret (out, ef) }
        filled = f
    } else {
        let mv = na_mean_value(a, adj, 0usize)
        let (f, ef) = mem.alloc[f64](a, n)
        if ef != ok { ret (out, ef) }
        i = 0usize
        while i < n {
            f[i] = adj[i]
            if is_nan(adj[i]) { f[i] = mv }
            i += 1usize
        }
        filled = f
    }
    i = 0usize
    while i < n {
        out[i] = x[i]
        if is_nan(x[i]) { out[i] = filled[i] + season[i] }
        i += 1usize
    }
    ret (out, ok)
}

// the base algorithms na_seadec and na_seasplit hand a series to: 0 interpolation (linear), 1 locf (na_remaining rev), 2 mean
fn apply_base(a: *mem.Arena, x: []const f64, algorithm: usize) -> ([]f64, err) {
    if algorithm == 0usize {
        let (f, ef) = na_interpolation(a, x, 0usize)
        ret (f, ef)
    }
    if algorithm == 1usize {
        let (f, ef) = na_locf_ts(a, x, false, 0usize)
        ret (f, ef)
    }
    let mv = na_mean_value(a, x, 0usize)
    let (f, ef) = mem.alloc[f64](a, x.len)
    if ef != ok { ret (f, ef) }
    var i = 0usize
    while i < x.len {
        f[i] = x[i]
        if is_nan(x[i]) { f[i] = mv }
        i += 1usize
    }
    ret (f, ok)
}

// na_seasplit(x with frequency period, algorithm): the series of every cycle position is imputed on its own
fn na_seasplit(a: *mem.Arena, x: []const f64, period: usize, algorithm: usize) -> ([]f64, err) {
    let n = x.len
    let (out, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (out, e1) }
    var i = 0usize
    while i < n {
        out[i] = x[i]
        i += 1usize
    }
    var ph = 0usize
    while ph < period {
        var cnt = 0usize
        i = ph
        while i < n {
            cnt += 1usize
            i += period
        }
        let (sub, e2) = mem.alloc[f64](a, cnt)
        if e2 != ok { ret (out, e2) }
        var q = 0usize
        i = ph
        while i < n {
            sub[q] = x[i]
            q += 1usize
            i += period
        }
        let (f, e3) = apply_base(a, sub, algorithm)
        if e3 != ok { ret (out, e3) }
        q = 0usize
        i = ph
        while i < n {
            out[i] = f[q]
            q += 1usize
            i += period
        }
        ph += 1usize
    }
    ret (out, ok)
}

// statsNA(x): out = (length, number of NAs, number of gaps, average gap size, percentage of NAs, longest gap, most frequent gap size, most weighty gap size); ties go to the larger size as the package loops do
fn stats_na(a: *mem.Arena, x: []const f64, out: []f64) -> err {
    let n = x.len
    let (vec, e1) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i <= n {
        vec[i] = 0.0f64
        i += 1usize
    }
    var nna = 0usize
    var run = 0usize
    i = 0usize
    while i < n {
        if is_nan(x[i]) {
            nna += 1usize
            run += 1usize
            if i + 1usize == n { vec[run] += 1.0f64 }
        } else {
            if run > 0usize { vec[run] += 1.0f64 }
            run = 0usize
        }
        i += 1usize
    }
    var mx = 0.0f64
    var common = 0usize
    i = 1usize
    while i <= n {
        if vec[i] >= mx {
            mx = vec[i]
            common = i
        }
        i += 1usize
    }
    var longest = 0.0f64 / 0.0f64
    i = n
    while i >= 1usize {
        if vec[i] > 0.0f64 {
            longest = f64(i)
            break
        }
        i -= 1usize
    }
    var wmx = 0.0f64
    var wcommon = 0usize
    i = 1usize
    while i <= n {
        if vec[i] * f64(i) >= wmx {
            wmx = vec[i] * f64(i)
            wcommon = i
        }
        i += 1usize
    }
    var gaps = 0.0f64
    i = 1usize
    while i <= n {
        gaps += vec[i]
        i += 1usize
    }
    out[0usize] = f64(n)
    out[1usize] = f64(nna)
    out[2usize] = gaps
    out[3usize] = 0.0f64
    if nna > 0usize { out[3usize] = f64(nna) / gaps }
    out[4usize] = f64(nna) / f64(n) * 100.0f64
    out[5usize] = longest
    out[6usize] = f64(common)
    out[7usize] = f64(wcommon)
    ret ok
}

// na_kalman for a state-space model: smooth = KalmanSmooth, otherwise the filtered states of KalmanRun; a missing value
// becomes the state estimate times Z. The model is not changed.
fn na_kalman_model(a: *mem.Arena, x: []const f64, orig: []const f64, m: *const kal.SsModel, smooth: bool, nit: i64) -> ([]f64, err) {
    let n = x.len
    let p = m.p
    let (o, e) = mem.alloc[f64](a, n)
    if e != ok { ret (o, e) }
    var erg: []f64 = zero
    if smooth {
        let (sm, se) = kal.kalman_smooth(a, m, x, nit)
        if se != ok { ret (o, se) }
        erg = sm
    } else {
        let (mc, ce) = kal.ss_copy(a, m)
        if ce != ok { ret (o, ce) }
        var mw = mc
        let (st, ste) = mem.alloc[f64](a, n * p)
        if ste != ok { ret (o, ste) }
        let (q1, q2, q3, fe) = kal.kalman_filter(a, &mw, x, nit, st, zero, 1.0e300f64)
        if fe != ok { ret (o, fe) }
        erg = st
    }
    var i = 0usize
    while i < n {
        o[i] = orig[i]
        if is_nan(orig[i]) {
            var s = 0.0f64
            var j = 0usize
            while j < p {
                s += erg[i * p + j] * m.zv[j]
                j += 1usize
            }
            o[i] = s
        }
        i += 1usize
    }
    ret (o, ok)
}

// the number of distinct values of x, a missing value counting as one (R's length(unique(x)))
fn distinct_count(x: []const f64) -> usize {
    var cnt = 0usize
    var i = 0usize
    while i < x.len {
        var seen = false
        var j = 0usize
        while j < i && !seen {
            if x[j] == x[i] || (is_nan(x[j]) && is_nan(x[i])) { seen = true }
            j += 1usize
        }
        if !seen { cnt += 1usize }
        i += 1usize
    }
    ret cnt
}

// na_kalman(x, model = "StructTS", smooth, type = kind (0 level, 1 trend, 2 BSM), frequency nf): at least three observed values are needed; a series with two distinct values is
// linearly interpolated, as imputeTS does; a missing first value is replaced by the first observed one for the fit and the smoothing
fn na_kalman_structts(a: *mem.Arena, x: []const f64, kind: usize, nf: usize, smooth: bool) -> ([]f64, err) {
    let n = x.len
    var nobs = 0usize
    var first = 0usize
    var seen = false
    var i = 0usize
    while i < n {
        if !is_nan(x[i]) {
            nobs += 1usize
            if !seen {
                first = i
                seen = true
            }
        }
        i += 1usize
    }
    if nobs == n {
        let (r0, e0) = na_interpolation(a, x, 0usize)
        ret (r0, e0)
    }
    if distinct_count(x) == 2usize {
        let (r1, e1) = na_interpolation(a, x, 0usize)
        ret (r1, e1)
    }
    let (data, e) = mem.alloc[f64](a, n)
    if e != ok { ret (data, e) }
    i = 0usize
    while i < n {
        data[i] = x[i]
        i += 1usize
    }
    if nobs < 3usize { ret (data, TooFewData) }
    if is_nan(data[0usize]) { data[0usize] = x[first] }
    let (model, me) = sts.struct_ts_model(a, data, kind, nf)
    if me != ok { ret (data, me) }
    let (r2, e2) = na_kalman_model(a, data, x, &model, smooth, 0i64 - 1i64)
    ret (r2, e2)
}
