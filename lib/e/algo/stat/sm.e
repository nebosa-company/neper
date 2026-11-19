// R sm: the normal-reference bandwidth hnorm, sm.density in one and two dimensions with the Gaussian kernel, and sm.regression at evaluation points
// (local constant or local linear, Gaussian kernel), all on unbinned data (sm bins only above 100 observations).
//
// Not here: h.select dispatch, bands and standard errors, sm.ancova, sm.survival and sm.options.

use e.math
use e.mem
use e.math.nmath as nm
use e.algo.stat.fdrtool as fd

fn sd_of(x: []const f64) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / f64(x.len)
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(x.len - 1usize))
}

fn phi(z: f64) -> f64 { ret math.exp[f64](0.0f64 - z * z / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64) }

// hnorm for one variable (ndim 1) or per column of a two-variable data set (ndim 2): sd times (4 / (3 n))^(1/5), or n^(-1/6)
fn hnorm(x: []const f64, ndim: usize) -> f64 {
    let n = f64(x.len)
    if ndim == 2usize { ret sd_of(x) * math.pow[f64](1.0f64 / n, 1.0f64 / 6.0f64) }
    ret sd_of(x) * math.pow[f64](4.0f64 / (3.0f64 * n), 0.2f64)
}

// sm.density(x, h) at p
fn density1(x: []const f64, h: f64, p: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += phi((p - x[i]) / h)
        i += 1usize
    }
    ret s / (f64(x.len) * h)
}

// the two-dimensional product-kernel estimate at (p, q)
fn density2(x: []const f64, y: []const f64, h1: f64, h2: f64, p: f64, q: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += phi((p - x[i]) / h1) * phi((q - y[i]) / h2)
        i += 1usize
    }
    ret s / (f64(x.len) * h1 * h2)
}

// sm.regression(x, y, h, poly.index) at p: 0 the kernel-weighted mean, 1 the local-linear intercept
fn regression(x: []const f64, y: []const f64, h: f64, p: f64, poly: usize) -> f64 {
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var t0 = 0.0f64
    var t1 = 0.0f64
    var i = 0usize
    while i < x.len {
        let w = phi((x[i] - p) / h)
        let d = x[i] - p
        s0 += w
        s1 += w * d
        s2 += w * d * d
        t0 += w * y[i]
        t1 += w * d * y[i]
        i += 1usize
    }
    if poly == 0usize { ret t0 / s0 }
    ret (s2 * t0 - s1 * t1) / (s0 * s2 - s1 * s1)
}

// the density cross-validation function cv(x, h) of sm for one variable (unit bandwidth weights)
fn cv_density(x: []const f64, h: f64) -> f64 {
    let n = x.len
    let nn = f64(n)
    let pi2 = 6.283185307179586f64
    let s2 = math.sqrt[f64](2.0f64)
    var hc = math.exp[f64](0.0f64) / (math.sqrt[f64](pi2) * s2 * h) * nn / (nn * (nn - 1.0f64))
    var a = 0.0f64
    var b = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if i != j {
                let d = x[i] - x[j]
                a += math.exp[f64](0.0f64 - 0.5f64 * (d / (h * s2)) * (d / (h * s2))) / (math.sqrt[f64](pi2) * h * s2)
                b += math.exp[f64](0.0f64 - 0.5f64 * (d / h) * (d / h)) / (math.sqrt[f64](pi2) * h)
            }
            j += 1usize
        }
        i += 1usize
    }
    hc += a * (nn - 2.0f64) / (nn * (nn - 1.0f64) * (nn - 1.0f64))
    hc -= b * 2.0f64 / (nn * (nn - 1.0f64))
    ret hc
}

// the leave-one-out squared error of the local linear smoother at bandwidth h
fn cv_regression(x: []const f64, y: []const f64, h: f64) -> f64 {
    let n = x.len
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        var s0 = 0.0f64
        var s1 = 0.0f64
        var s2 = 0.0f64
        var j = 0usize
        while j < n {
            if j != i {
                let wd = x[i] - x[j]
                let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
                s0 += w
                s1 += w * wd
                s2 += w * wd * wd
            }
            j += 1usize
        }
        var fit = 0.0f64
        j = 0usize
        while j < n {
            if j != i {
                let wd = x[i] - x[j]
                let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
                fit += w * (s2 - wd * s1) / (s2 * s0 - s1 * s1) * y[j]
            }
            j += 1usize
        }
        tot += (y[i] - fit) * (y[i] - fit)
        i += 1usize
    }
    ret tot
}

// hcv(x) (regression false) or hcv(x, y) (true): the cross-validation bandwidth, the minimum of the criterion on the eight-point log grid from hnorm / 10 to 2 hnorm refined by the parabola through the grid minimum and its neighbours; NaN at the boundary
fn hcv(x: []const f64, y: []const f64, regression_cv: bool) -> f64 {
    let ng = 8usize
    let hn = hnorm(x, 1usize)
    let hs = hn / 10.0f64
    let he = hn * 2.0f64
    var cvg: [8]f64 = zero
    var hg: [8]f64 = zero
    var i = 0usize
    while i < ng {
        hg[i] = math.log[f64](hs) + (math.log[f64](he) - math.log[f64](hs)) * f64(i) / f64(ng - 1usize)
        if regression_cv { cvg[i] = cv_regression(x, y, math.exp[f64](hg[i])) } else { cvg[i] = cv_density(x, math.exp[f64](hg[i])) }
        if cvg[i] != cvg[i] { cvg[i] = 1.0e300f64 }
        i += 1usize
    }
    var ind = 0usize
    i = 1usize
    while i < ng {
        if cvg[i] < cvg[ind] { ind = i }
        i += 1usize
    }
    if ind == 0usize || ind == ng - 1usize { ret 0.0f64 / 0.0f64 }
    let v0 = cvg[ind - 1usize]
    let v1 = cvg[ind]
    let v2 = cvg[ind + 1usize]
    let l0 = hg[ind - 1usize]
    let l1 = hg[ind]
    let l2 = hg[ind + 1usize]
    let aa = (v1 - v0 - (l1 - l0) * (v1 - v2) / (l1 - l2)) / (l1 * l1 - l0 * l0 - (l1 * l1 - l2 * l2) * (l1 - l0) / (l1 - l2))
    let bb = (v1 - v2 - aa * (l1 * l1 - l2 * l2)) / (l1 - l2)
    ret math.exp[f64](0.0f64 - bb / (2.0f64 * aa))
}

// quantile of x (type 7, R's default) with the sorted copy in s
fn quantile7(s: []const f64, p: f64) -> f64 {
    let n = s.len
    let h = f64(n - 1usize) * p
    let lo = usize(math.floor[f64](h))
    var hi = lo + 1usize
    if hi >= n { hi = n - 1usize }
    ret s[lo] + (h - f64(lo)) * (s[hi] - s[lo])
}

fn phi4(z: f64) -> f64 { ret (z * z * z * z - 6.0f64 * z * z + 3.0f64) * phi(z) }

fn phi6(z: f64) -> f64 {
    let z2 = z * z
    ret (z2 * z2 * z2 - 15.0f64 * z2 * z2 + 45.0f64 * z2 - 15.0f64) * phi(z)
}

// the double sum over all ordered pairs (i, j) of f((x_i - x_j) / b), diagonal included
fn pair_sum(x: []const f64, b: f64, which: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < x.len {
        var j = 0usize
        while j < x.len {
            let z = (x[i] - x[j]) / b
            if which == 6usize { t += phi6(z) } else { t += phi4(z) }
            j += 1usize
        }
        i += 1usize
    }
    ret t
}

// sm's sj(x, h): the Sheather-Jones fixed-point residual at bandwidth h (unbinned, as sm does below 100 observations); s is the sorted copy of x
fn sj(x: []const f64, s: []const f64, h: f64) -> f64 {
    let n = f64(x.len)
    let lambda = quantile7(s, 0.75f64) - quantile7(s, 0.25f64)
    let a = 0.92f64 * lambda * math.pow[f64](n, 0.0f64 - 1.0f64 / 7.0f64)
    let b = 0.912f64 * lambda * math.pow[f64](n, 0.0f64 - 1.0f64 / 9.0f64)
    let tdb = 0.0f64 - pair_sum(x, b, 6usize) / (n * (n - 1.0f64) * math.pow[f64](b, 7.0f64))
    let sda = pair_sum(x, a, 4usize) / (n * (n - 1.0f64) * math.pow[f64](a, 5.0f64))
    let alpha2 = 1.357f64 * math.pow[f64](math.abs[f64](sda / tdb), 1.0f64 / 7.0f64) * math.pow[f64](h, 5.0f64 / 7.0f64)
    let sdalpha2 = pair_sum(x, alpha2, 4usize) / (n * (n - 1.0f64) * math.pow[f64](alpha2, 5.0f64))
    let d0 = 1.0f64 / math.sqrt[f64](4.0f64 * 3.141592653589793238462643383279f64)
    ret math.pow[f64](d0 / (n * math.abs[f64](sdalpha2)), 0.2f64) - h
}

// hsj: the Sheather-Jones bandwidth, stepping the normal-reference one by 1.1 or 0.9 until sj changes sign and interpolating linearly
fn hsj(a: *mem.Arena, x: []const f64) -> (f64, err) {
    let (s, e0) = mem.alloc[f64](a, x.len)
    if e0 != ok { ret (0.0f64, e0) }
    var i = 0usize
    while i < x.len {
        let v = x[i]
        var j = i
        while j > 0usize && s[j - 1usize] > v {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = v
        i += 1usize
    }
    var h0 = hnorm(x, 1usize)
    var v0 = sj(x, s, h0)
    var step = 0.9f64
    if v0 > 0.0f64 { step = 1.1f64 }
    var h1 = h0 * step
    var v1 = sj(x, s, h1)
    var guard = 0usize
    while v1 * v0 > 0.0f64 && guard < 2000usize {
        h0 = h1
        v0 = v1
        h1 = h0 * step
        v1 = sj(x, s, h1)
        guard += 1usize
    }
    ret (h0 + (h1 - h0) * math.abs[f64](v0) / (math.abs[f64](v0) + math.abs[f64](v1)), ok)
}

type CvCtx = struct { x: []const f64 }

fn cv_log(c: *CvCtx, lh: f64) -> f64 {
    let v = cv_density(c.x, math.exp[f64](lh))
    if v != v { ret 1.0e10f64 }
    ret v
}

// h.select(x, method = "cv") for one unbinned variable: R's optimise of the density cross-validation score over log(start / 8) .. log(start * 4), start = sd / 2
fn hselect_cv(x: []const f64) -> f64 {
    let start = sd_of(x) / 2.0f64
    var c = CvCtx { x: x }
    ret math.exp[f64](fd.brent_min[CvCtx](&c, cv_log, math.log[f64](start / 8.0f64), math.log[f64](start * 4.0f64)))
}

type CvRegCtx = struct { x: []const f64, y: []const f64 }

fn cv_reg_log(c: *CvRegCtx, lh: f64) -> f64 {
    let v = cv_regression(c.x, c.y, math.exp[f64](lh)) / f64(c.x.len)
    if v != v { ret 1.0e10f64 }
    ret v
}

// h.select(x, y, method = "cv") for one unbinned covariate: optimise of the leave-one-out squared error over the same log interval
fn hselect_cv_reg(x: []const f64, y: []const f64) -> f64 {
    let start = sd_of(x) / 2.0f64
    var c = CvRegCtx { x: x, y: y }
    ret math.exp[f64](fd.brent_min[CvRegCtx](&c, cv_reg_log, math.log[f64](start / 8.0f64), math.log[f64](start * 4.0f64)))
}

// the local-linear smoother at x[i] with bandwidth h: trace entry s_ii and the fit sum_j s_ij y[j]
fn smooth_row(x: []const f64, y: []const f64, i: usize, h: f64, sii: *f64) -> f64 {
    let n = x.len
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var j = 0usize
    while j < n {
        let wd = x[i] - x[j]
        let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
        s0 += w
        s1 += w * wd
        s2 += w * wd * wd
        j += 1usize
    }
    var fit = 0.0f64
    j = 0usize
    while j < n {
        let wd = x[i] - x[j]
        let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
        let sij = w * (s2 - wd * s1) / (s2 * s0 - s1 * s1)
        fit += sij * y[j]
        if j == i { *sii = sij }
        j += 1usize
    }
    ret fit
}

// the df criterion (tr S - df)^2 (kind 0) and the AICc criterion (kind 1) of sm at log bandwidth lh
type CritCtx = struct { x: []const f64, y: []const f64, kind: usize, df: f64 }

fn crit_log(c: *CritCtx, lh: f64) -> f64 {
    let n = c.x.len
    let h = math.exp[f64](lh)
    var tr = 0.0f64
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        var sii = 0.0f64
        let fit = smooth_row(c.x, c.y, i, h, &sii)
        tr += sii
        rss += (c.y[i] - fit) * (c.y[i] - fit)
        i += 1usize
    }
    if c.kind == 0usize { ret (tr - c.df) * (tr - c.df) }
    let nn = f64(n)
    let v = math.log[f64](rss / nn) + 1.0f64 + 2.0f64 * (tr + 1.0f64) / (nn - tr - 2.0f64)
    if v != v { ret 1.0e10f64 }
    ret v
}

// h.select(x, y, method = "df" or "aicc") for one unbinned covariate; kind 0 is df (with df = df), 1 is aicc
fn hselect_crit(x: []const f64, y: []const f64, kind: usize, df: f64) -> f64 {
    let start = sd_of(x) / 2.0f64
    var c = CritCtx { x: x, y: y, kind: kind, df: df }
    ret math.exp[f64](fd.brent_min[CritCtx](&c, crit_log, math.log[f64](start / 8.0f64), math.log[f64](start * 4.0f64)))
}

// sm.sigma(x, y) with the second-order differences (unit weights, unbinned): the residual scale of sm.regression
fn sm_sigma(a: *mem.Arena, x: []const f64, y: []const f64) -> (f64, err) {
    let n = x.len
    let (idx, e0) = mem.alloc[usize](a, n)
    if e0 != ok { ret (0.0f64, e0) }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let k = idx[i]
        var j = i
        while j > 0usize && x[idx[j - 1usize]] > x[k] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = k
        i += 1usize
    }
    var ssq = 0.0f64
    i = 0usize
    while i + 2usize < n {
        let x0 = x[idx[i]]
        let x1 = x[idx[i + 1usize]]
        let x2 = x[idx[i + 2usize]]
        var aa = (x2 - x1) / (x2 - x0)
        var bb = (x1 - x0) / (x2 - x0)
        if x2 == x0 {
            aa = 0.5f64
            bb = 0.5f64
        }
        let cc = aa * aa + bb * bb + 1.0f64
        let eps = y[idx[i]] * aa + y[idx[i + 2usize]] * bb - y[idx[i + 1usize]]
        ssq += eps * eps / cc
        i += 1usize
    }
    ret (math.sqrt[f64](ssq / (f64(n) - 2.0f64)), ok)
}

// the standard error of the local-linear sm.regression estimate at p: sigma * sqrt(sum of squared weights)
fn regression_se(a: *mem.Arena, x: []const f64, y: []const f64, h: f64, p: f64) -> (f64, err) {
    let (sg, e) = sm_sigma(a, x, y)
    if e != ok { ret (0.0f64, e) }
    let n = x.len
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var j = 0usize
    while j < n {
        let wd = x[j] - p
        let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
        s0 += w
        s1 += w * wd
        s2 += w * wd * wd
        j += 1usize
    }
    var q = 0.0f64
    j = 0usize
    while j < n {
        let wd = x[j] - p
        let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
        let swj = w * (s2 - wd * s1) / (s2 * s0 - s1 * s1)
        q += swj * swj
        j += 1usize
    }
    ret (sg * math.sqrt[f64](q), ok)
}

fn brk(lo: f64, by: f64, k: usize) -> f64 {
    if k == 0usize { ret lo - 1.0e-5f64 }
    ret lo + f64(k) * by
}

// sm binning(x, y, nbins) for one variable: equal-width bins over (min - 1e-5, max], right-closed as R's cut; the non-empty bins' midpoints, counts, y means and y deviations about the mean go to bx, bf, bm, bd (each nbins long); the answer is how many bins are non-empty
fn binning1d(a: *mem.Arena, x: []const f64, y: []const f64, nbins: usize, bx: []f64, bf: []f64, bm: []f64, bd: []f64) -> (usize, err) {
    let n = x.len
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let b0 = lo - 1.0e-5f64
    let (cnt, e0) = mem.alloc[f64](a, nbins)
    let (sum, e1) = mem.alloc[f64](a, nbins)
    let (idx, e2) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    let by = (hi - lo) / f64(nbins)
    var k = 0usize
    while k < nbins {
        cnt[k] = 0.0f64
        sum[k] = 0.0f64
        k += 1usize
    }
    i = 0usize
    while i < n {
        // breaks[j] = b0 + (hi - b0) * j / nbins, the seq() R forms; x falls in the first bin whose upper break is >= x
        var j = 0usize
        while j + 1usize < nbins && x[i] > lo + f64(j + 1usize) * by { j += 1usize }
        idx[i] = j
        cnt[j] += 1.0f64
        sum[j] += y[i]
        i += 1usize
    }
    var m = 0usize
    k = 0usize
    while k < nbins {
        if cnt[k] > 0.0f64 {
            let mean = sum[k] / cnt[k]
            var dev = 0.0f64
            i = 0usize
            while i < n {
                if idx[i] == k { dev += (y[i] - mean) * (y[i] - mean) }
                i += 1usize
            }
            bx[m] = (brk(lo, by, k) + brk(lo, by, k + 1usize)) / 2.0f64
            bf[m] = cnt[k]
            bm[m] = mean
            bd[m] = dev
            m += 1usize
        }
        k += 1usize
    }
    ret (m, ok)
}

// the local-linear sm.regression estimate at p over weighted points (the bin counts f as weights, the bin means as y): binned sm.regression
fn regression_w(x: []const f64, y: []const f64, f: []const f64, h: f64, p: f64) -> f64 {
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var t0 = 0.0f64
    var t1 = 0.0f64
    var i = 0usize
    while i < x.len {
        let d = x[i] - p
        let w = f[i] * phi(d / h)
        s0 += w
        s1 += w * d
        s2 += w * d * d
        t0 += w * y[i]
        t1 += w * d * y[i]
        i += 1usize
    }
    ret (s2 * t0 - s1 * t1) / (s0 * s2 - s1 * s1)
}

// the Gaussian kernel density estimate at p over weighted points (bin midpoints with counts f): binned sm.density
fn density_w(x: []const f64, f: []const f64, h: f64, p: f64) -> f64 {
    var s = 0.0f64
    var tot = 0.0f64
    var i = 0usize
    while i < x.len {
        s += f[i] * phi((p - x[i]) / h)
        tot += f[i]
        i += 1usize
    }
    ret s / (tot * h)
}

// cv.crit.dens of sm over binned data (midpoints x, counts f): n is the number of bins, as in sm
fn cv_density_w(x: []const f64, f: []const f64, h: f64) -> f64 {
    let m = x.len
    let nn = f64(m)
    let pi2 = 6.283185307179586f64
    let s2 = math.sqrt[f64](2.0f64)
    var hc = 0.0f64
    var i = 0usize
    while i < m {
        hc += f[i] / (math.sqrt[f64](pi2) * s2 * h)
        i += 1usize
    }
    hc = hc / (nn * (nn - 1.0f64))
    var a = 0.0f64
    var b = 0.0f64
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            if i != j {
                let d = x[i] - x[j]
                a += f[i] * f[j] * math.exp[f64](0.0f64 - 0.5f64 * (d / (h * s2)) * (d / (h * s2))) / (math.sqrt[f64](pi2) * h * s2)
                b += f[i] * f[j] * math.exp[f64](0.0f64 - 0.5f64 * (d / h) * (d / h)) / (math.sqrt[f64](pi2) * h)
            }
            j += 1usize
        }
        i += 1usize
    }
    hc += a * (nn - 2.0f64) / (nn * (nn - 1.0f64) * (nn - 1.0f64))
    hc -= b * 2.0f64 / (nn * (nn - 1.0f64))
    ret hc
}

type CvWCtx = struct { x: []const f64, f: []const f64 }

fn cv_w_log(c: *CvWCtx, lh: f64) -> f64 {
    let v = cv_density_w(c.x, c.f, math.exp[f64](lh))
    if v != v { ret 1.0e10f64 }
    ret v
}

// h.select(x, method = "cv") on binned data: start = sd / 2 of the raw sample
fn hselect_cv_binned(x: []const f64, f: []const f64, start: f64) -> f64 {
    var c = CvWCtx { x: x, f: f }
    ret math.exp[f64](fd.brent_min[CvWCtx](&c, cv_w_log, math.log[f64](start / 8.0f64), math.log[f64](start * 4.0f64)))
}

type BinRegCtx = struct { x: []const f64, y: []const f64, f: []const f64, dv: []const f64, kind: usize, df: f64 }

// the criteria of sm's h.select for regression on binned data: kind 0 cv (cross-validated smoother), 1 df, 2 aicc; weights are the bin counts
fn bin_reg_log(c: *BinRegCtx, lh: f64) -> f64 {
    let m = c.x.len
    let h = math.exp[f64](lh)
    var tr = 0.0f64
    var tot = 0.0f64
    var nobs = 0.0f64
    var rss = 0.0f64
    var i = 0usize
    while i < m {
        var s0 = 0.0f64
        var s1 = 0.0f64
        var s2 = 0.0f64
        var j = 0usize
        while j < m {
            if c.kind != 0usize || j != i {
                let wd = c.x[i] - c.x[j]
                let w = c.f[j] * math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
                s0 += w
                s1 += w * wd
                s2 += w * wd * wd
            }
            j += 1usize
        }
        var fit = 0.0f64
        var sii = 0.0f64
        j = 0usize
        while j < m {
            if c.kind != 0usize || j != i {
                let wd = c.x[i] - c.x[j]
                let w = c.f[j] * math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
                let sij = w * (s2 - wd * s1) / (s2 * s0 - s1 * s1)
                fit += sij * c.y[j]
                if j == i { sii = sij }
            }
            j += 1usize
        }
        let r = c.y[i] - fit
        rss += c.f[i] * r * r + c.dv[i]
        tr += c.f[i] * sii
        nobs += c.f[i]
        tot += sii
        i += 1usize
    }
    if c.kind == 0usize {
        let v = rss / nobs
        if v != v { ret 1.0e10f64 }
        ret v
    }
    if c.kind == 1usize { ret (tot - c.df) * (tot - c.df) }
    let sg = rss / nobs
    let v = math.log[f64](sg) + 1.0f64 + 2.0f64 * (tr + 1.0f64) / (nobs - tr - 2.0f64)
    if v != v { ret 1.0e10f64 }
    ret v
}

fn hselect_bin_reg(x: []const f64, y: []const f64, f: []const f64, dv: []const f64, kind: usize, df: f64, start: f64) -> f64 {
    var c = BinRegCtx { x: x, y: y, f: f, dv: dv, kind: kind, df: df }
    ret math.exp[f64](fd.brent_min[BinRegCtx](&c, bin_reg_log, math.log[f64](start / 8.0f64), math.log[f64](start * 4.0f64)))
}

fn mm(c: []f64, l: []const f64, r: []const f64, n: usize) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var v = 0.0f64
            var k = 0usize
            while k < n {
                v += l[i * n + k] * r[k * n + j]
                k += 1usize
            }
            c[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

fn trace(m: []const f64, n: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        t += m[i * n + i]
        i += 1usize
    }
    ret t
}

// the local-linear smoothing matrix of the points xs at bandwidth h, written into the block at offset o of the big matrix smx (stride nt)
fn smooth_block(smx: []f64, nt: usize, o: usize, xs: []const f64, h: f64) {
    let n = xs.len
    var i = 0usize
    while i < n {
        var s0 = 0.0f64
        var s1 = 0.0f64
        var s2 = 0.0f64
        var j = 0usize
        while j < n {
            let wd = xs[i] - xs[j]
            let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
            s0 += w
            s1 += w * wd
            s2 += w * wd * wd
            j += 1usize
        }
        j = 0usize
        while j < n {
            let wd = xs[i] - xs[j]
            let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
            smx[(o + i) * nt + o + j] = w * (s2 - wd * s1) / (s2 * s0 - s1 * s1)
            j += 1usize
        }
        i += 1usize
    }
}

// sm.ancova(x, y, group, h, model = "equal") for one covariate, unbinned, unit weights: the p-value of the test of equal regression curves; rows are ordered by group then x as R does
fn ancova_equal(a: *mem.Arena, x: []const f64, y: []const f64, group: []const f64, h: f64) -> (f64, err) {
    let n = x.len
    let (ord, e0) = mem.alloc[usize](a, n)
    if e0 != ok { ret (0.0f64, e0) }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && (group[ord[j - 1usize]] > group[v] || (group[ord[j - 1usize]] == group[v] && x[ord[j - 1usize]] > x[v])) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    let nn = n * n
    let (xs, e1) = mem.alloc[f64](a, n)
    let (ys, e2) = mem.alloc[f64](a, n)
    let (gs, e3) = mem.alloc[f64](a, n)
    let (sd, e4) = mem.alloc[f64](a, nn)
    let (ss, e5) = mem.alloc[f64](a, nn)
    let (bm, e6) = mem.alloc[f64](a, nn)
    let (q, e7) = mem.alloc[f64](a, nn)
    let (q2, e8) = mem.alloc[f64](a, nn)
    let (t1, e9) = mem.alloc[f64](a, nn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (0.0f64, mem.Full) }
    i = 0usize
    while i < n {
        xs[i] = x[ord[i]]
        ys[i] = y[ord[i]]
        gs[i] = group[ord[i]]
        i += 1usize
    }
    i = 0usize
    while i < nn {
        sd[i] = 0.0f64
        ss[i] = 0.0f64
        bm[i] = 0.0f64
        i += 1usize
    }
    var st = 0usize
    while st < n {
        var en = st
        while en < n && gs[en] == gs[st] { en += 1usize }
        smooth_block(sd, n, st, xs[st..en], h)
        // sm.sigweight: t(R) R with the second-difference rows of the block
        let m = en - st
        var r = 1usize
        while r + 1usize < m {
            let x0 = xs[st + r - 1usize]
            let x1 = xs[st + r]
            let x2 = xs[st + r + 1usize]
            var aa = (x2 - x1) / (x2 - x0)
            var bb = (x1 - x0) / (x2 - x0)
            if x2 == x0 {
                aa = 0.5f64
                bb = 0.5f64
            }
            let cc = math.sqrt[f64](aa * aa + bb * bb + 1.0f64)
            var rowv: [3]f64 = zero
            rowv[0usize] = aa / cc
            rowv[1usize] = 0.0f64 - 1.0f64 / cc
            rowv[2usize] = bb / cc
            var u = 0usize
            while u < 3usize {
                var v = 0usize
                while v < 3usize {
                    bm[(st + r - 1usize + u) * n + st + r - 1usize + v] += rowv[u] * rowv[v]
                    v += 1usize
                }
                u += 1usize
            }
            r += 1usize
        }
        st = en
    }
    smooth_block(ss, n, 0usize, xs, h)
    var sig2 = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            sig2 += ys[i] * bm[i * n + j] * ys[j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nn {
        t1[i] = sd[i] - ss[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var v = 0.0f64
            var k = 0usize
            while k < n {
                v += t1[k * n + i] * t1[k * n + j]
                k += 1usize
            }
            q[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
    var obs = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            obs += ys[i] * q[i * n + j] * ys[j]
            j += 1usize
        }
        i += 1usize
    }
    obs = obs / sig2
    // p.quad.moment(Q - B obs, I, obs, 0)
    i = 0usize
    while i < nn {
        q[i] = q[i] - bm[i] * obs
        i += 1usize
    }
    mm(q2, q, q, n)
    mm(t1, q2, q, n)
    let k1 = trace(q, n)
    let k2 = 2.0f64 * trace(q2, n)
    let k3 = 8.0f64 * trace(t1, n)
    let aa = math.abs[f64](k3 / (4.0f64 * k2))
    let bb = 8.0f64 * k2 * k2 * k2 / (k3 * k3)
    let cc = k1 - aa * bb
    ret (1.0f64 - nm.pchisq(0.0f64 - cc / aa, bb, true, false), ok)
}
