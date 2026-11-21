// R sm: the normal-reference bandwidth hnorm, sm.density in one and two dimensions with the Gaussian kernel, and sm.regression at evaluation points
// (local constant or local linear, Gaussian kernel), all on unbinned data (sm bins only above 100 observations).
//
// Also: the reference-band model fits, the sm.options defaults, sm.ancova and sm.survival at one point.

use e.math
use e.mem
use e.algo.stat.armld as ld
use e.algo.stat.armx87 as xe
use e.str
use e.math.nmath as nm
use e.algo.stat.fdrtool as fd
use e.algo.stat.rnm

fn sd_of(x: []const f64) -> f64 { ret math.sqrt[f64](ld.var_ld(x)) }

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

// h.select's density cross-validation score as sm's cv.crit.dens evaluates it: long double sums of the full n x n matrix less its diagonal, column by column
fn cv_density_hs(x: []const f64, h: f64) -> f64 {
    let n = x.len
    let nn = f64(n)
    let s2 = math.sqrt[f64](2.0f64)
    let c = math.sqrt[f64](2.0f64 * 3.141592653589793f64)
    let d0 = 0.3989422804014327f64 / (s2 * h * 1.0f64)
    var t0 = ld.ld_zero()
    var i = 0usize
    while i < n {
        t0 = ld.ld_add(t0, ld.ld_from(d0))
        i += 1usize
    }
    var hc = ld.ld_to(t0) / (nn * (nn - 1.0f64))
    var all = ld.ld_zero()
    var dg = ld.ld_zero()
    var all2 = ld.ld_zero()
    var dg2 = ld.ld_zero()
    var j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            let d = x[i] - x[j]
            let z = d / (h * s2)
            let v = xe.exp_r(0.0f64 - 0.5f64 * (z * z)) / (c * h * s2)
            let z2 = d / (h * 1.0f64)
            let v2 = xe.exp_r(0.0f64 - 0.5f64 * (z2 * z2)) / (c * h * 1.0f64)
            all = ld.ld_add(all, ld.ld_from(v))
            all2 = ld.ld_add(all2, ld.ld_from(v2))
            if i == j {
                dg = ld.ld_add(dg, ld.ld_from(v))
                dg2 = ld.ld_add(dg2, ld.ld_from(v2))
            }
            i += 1usize
        }
        j += 1usize
    }
    hc = hc + (ld.ld_to(all) - ld.ld_to(dg)) * (nn - 2.0f64) / (nn * ((nn - 1.0f64) * (nn - 1.0f64)))
    hc = hc - (ld.ld_to(all2) - ld.ld_to(dg2)) * 2.0f64 / (nn * (nn - 1.0f64))
    ret hc
}

// h.select's leave-one-out score as sm's cv.crit.reg evaluates it: row sums and (I - S) y in the BLAS order, the squares summed in long double
fn cv_regression_hs(x: []const f64, y: []const f64, h: f64) -> f64 {
    let n = x.len
    var tot = ld.ld_zero()
    var i = 0usize
    while i < n {
        var s0 = 0.0f64
        var s1 = 0.0f64
        var s2 = 0.0f64
        var j = 0usize
        while j < n {
            let wd = x[i] - x[j]
            var w = xe.exp_r(0.0f64 - 0.5f64 * ((wd / h) * (wd / h)))
            if i == j { w = 0.0f64 }
            s0 += w
            s1 += w * wd
            s2 += w * (wd * wd)
            j += 1usize
        }
        var fit = 0.0f64
        j = 0usize
        while j < n {
            let wd = x[i] - x[j]
            var w = xe.exp_r(0.0f64 - 0.5f64 * ((wd / h) * (wd / h)))
            if i == j { w = 0.0f64 }
            let s = w * (s2 - wd * s1) / (s2 * s0 - s1 * s1)
            var m = 0.0f64 - s
            if i == j { m = 1.0f64 - s }
            fit += m * y[j]
            j += 1usize
        }
        tot = ld.ld_add(tot, ld.ld_from(fit * fit))
        i += 1usize
    }
    ret ld.ld_to(tot) / f64(n)
}

type CvCtx = struct { x: []const f64 }

fn cv_log(c: *CvCtx, lh: f64) -> f64 {
    let v = cv_density_hs(c.x, xe.exp_r(lh))
    if v != v { ret 1.0e10f64 }
    ret v
}

// h.select(x, method = "cv") for one unbinned variable: R's optimise of the density cross-validation score over log(start / 8) .. log(start * 4), start = sd / 2
fn hselect_cv(x: []const f64) -> f64 {
    let start = sd_of(x) / 2.0f64
    var c = CvCtx { x: x }
    ret xe.exp_r(fd.brent_min[CvCtx](&c, cv_log, xe.log_r(start / 8.0f64), xe.log_r(start * 4.0f64)))
}

type CvRegCtx = struct { x: []const f64, y: []const f64 }

fn cv_reg_log(c: *CvRegCtx, lh: f64) -> f64 {
    let v = cv_regression_hs(c.x, c.y, xe.exp_r(lh))
    if v != v { ret 1.0e10f64 }
    ret v
}

// h.select(x, y, method = "cv") for one unbinned covariate: optimise of the leave-one-out squared error over the same log interval
fn hselect_cv_reg(x: []const f64, y: []const f64) -> f64 {
    let start = sd_of(x) / 2.0f64
    var c = CvRegCtx { x: x, y: y }
    ret xe.exp_r(fd.brent_min[CvRegCtx](&c, cv_reg_log, xe.log_r(start / 8.0f64), xe.log_r(start * 4.0f64)))
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

// the se sm.regression reports at p (unit weights) under a reference model: kind 1 no.effect, 2 linear; sigma * sqrt(sum (w_j - m_j)^2) with w the local-linear row and m the model's smoother row (1/n, or the least-squares line's hat row)
fn regression_se_model(a: *mem.Arena, x: []const f64, y: []const f64, h: f64, p: f64, kind: usize) -> (f64, err) {
    let (sg, e) = sm_sigma(a, x, y)
    if e != ok { ret (0.0f64, e) }
    let n = x.len
    var sx = 0.0f64
    var j = 0usize
    while j < n {
        sx += x[j]
        j += 1usize
    }
    let mx = sx / f64(n)
    var sxx = 0.0f64
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    j = 0usize
    while j < n {
        let wd = x[j] - p
        let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
        s0 += w
        s1 += w * wd
        s2 += w * wd * wd
        sxx += (x[j] - mx) * (x[j] - mx)
        j += 1usize
    }
    var q = 0.0f64
    j = 0usize
    while j < n {
        let wd = x[j] - p
        let w = math.exp[f64](0.0f64 - 0.5f64 * (wd / h) * (wd / h))
        let swj = w * (s2 - wd * s1) / (s2 * s0 - s1 * s1)
        var m = 1.0f64 / f64(n)
        if kind == 2usize { m += (p - mx) * (x[j] - mx) / sxx }
        q += (swj - m) * (swj - m)
        j += 1usize
    }
    ret (sg * math.sqrt[f64](q), ok)
}

// the 2-d sm.density variability band: se = dnorm(0, sd = sqrt(2)) / sqrt(4 n h1 h2); answers (se, lower, upper) as density_band does
fn density_band2(est: f64, n: f64, h1: f64, h2: f64) -> (f64, f64, f64) {
    let se = phi(0.0f64) / math.sqrt[f64](2.0f64) / math.sqrt[f64](4.0f64 * n * h1 * h2)
    let up = math.sqrt[f64](est) + 2.0f64 * se
    var lo = math.sqrt[f64](est) - 2.0f64 * se
    if lo < 0.0f64 { lo = 0.0f64 }
    ret (se, lo * lo, up * up)
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
fn ancova_equal(a: *mem.Arena, x: []const f64, y: []const f64, group: []const f64, h: f64, parallel: bool) -> (f64, err) {
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
    if parallel {
        // the parallel model: M = (D'Q0'Q0 D)^-1 D'Q0'Q0 with Q0 = I - S(h.alpha); alpha = M y, ghat = Ss (I - D M) y, ghati = Sd y
        var lo = xs[0usize]
        var hi = xs[0usize]
        i = 0usize
        while i < n {
            if xs[i] < lo { lo = xs[i] }
            if xs[i] > hi { hi = xs[i] }
            i += 1usize
        }
        let halpha = 2.0f64 * (hi - lo) / f64(n)
        let (gi, eg) = mem.alloc[usize](a, n)
        if eg != ok { ret (0.0f64, eg) }
        var ng = 0usize
        i = 0usize
        while i < n {
            if i > 0usize && gs[i] != gs[i - 1usize] { ng += 1usize }
            gi[i] = ng
            i += 1usize
        }
        let kk = ng
        // R builds D with istart fixed at n[1] + 1 for every column (it is never advanced), so column l marks rows n1 + 1 .. n1 + n[l + 1]
        let (dmat, edd) = mem.alloc[f64](a, n * kk)
        let (gsz, egz) = mem.alloc[usize](a, kk + 1usize)
        if edd != ok || egz != ok { ret (0.0f64, mem.Full) }
        var zq = 0usize
        while zq <= kk {
            gsz[zq] = 0usize
            zq += 1usize
        }
        i = 0usize
        while i < n {
            gsz[gi[i]] += 1usize
            i += 1usize
        }
        i = 0usize
        while i < n {
            var l0 = 0usize
            while l0 < kk {
                dmat[i * kk + l0] = 0.0f64
                if i >= gsz[0usize] && i < gsz[0usize] + gsz[l0 + 1usize] { dmat[i * kk + l0] = 1.0f64 }
                l0 += 1usize
            }
            i += 1usize
        }
        let (q0, eq0) = mem.alloc[f64](a, nn)
        let (am, eam) = mem.alloc[f64](a, n * kk)
        let (gm, egm) = mem.alloc[f64](a, kk * (kk + n))
        let (dm, edm) = mem.alloc[f64](a, nn)
        if eq0 != ok || eam != ok || egm != ok || edm != ok { ret (0.0f64, mem.Full) }
        i = 0usize
        while i < nn {
            q0[i] = 0.0f64
            i += 1usize
        }
        smooth_block(q0, n, 0usize, xs, halpha)
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                var v = 0.0f64
                if i == j { v = 1.0f64 }
                q0[i * n + j] = v - q0[i * n + j]
                j += 1usize
            }
            i += 1usize
        }
        // A = Q0 D (n by kk): column l sums the Q0 columns of group l + 1
        i = 0usize
        while i < n {
            var l = 0usize
            while l < kk {
                var v = 0.0f64
                var r = 0usize
                while r < n {
                    v += q0[i * n + r] * dmat[r * kk + l]
                    r += 1usize
                }
                am[i * kk + l] = v
                l += 1usize
            }
            i += 1usize
        }
        // [A'A | A'Q0] then Gauss-Jordan to M (kk by n)
        let wd = kk + n
        var l = 0usize
        while l < kk {
            var c2 = 0usize
            while c2 < kk {
                var v = 0.0f64
                var r = 0usize
                while r < n {
                    v += am[r * kk + l] * am[r * kk + c2]
                    r += 1usize
                }
                gm[l * wd + c2] = v
                c2 += 1usize
            }
            c2 = 0usize
            while c2 < n {
                var v = 0.0f64
                var r = 0usize
                while r < n {
                    v += am[r * kk + l] * q0[r * n + c2]
                    r += 1usize
                }
                gm[l * wd + kk + c2] = v
                c2 += 1usize
            }
            l += 1usize
        }
        var col = 0usize
        while col < kk {
            var piv = col
            var rr = col + 1usize
            while rr < kk {
                if math.abs[f64](gm[rr * wd + col]) > math.abs[f64](gm[piv * wd + col]) { piv = rr }
                rr += 1usize
            }
            var cc2 = 0usize
            while cc2 < wd {
                let tt = gm[col * wd + cc2]
                gm[col * wd + cc2] = gm[piv * wd + cc2]
                gm[piv * wd + cc2] = tt
                cc2 += 1usize
            }
            let pv = gm[col * wd + col]
            cc2 = 0usize
            while cc2 < wd {
                gm[col * wd + cc2] = gm[col * wd + cc2] / pv
                cc2 += 1usize
            }
            rr = 0usize
            while rr < kk {
                if rr != col {
                    let fct = gm[rr * wd + col]
                    cc2 = 0usize
                    while cc2 < wd {
                        gm[rr * wd + cc2] -= fct * gm[col * wd + cc2]
                        cc2 += 1usize
                    }
                }
                rr += 1usize
            }
            col += 1usize
        }
        // DM (n by n): row i is row gi[i] - 1 of M for groups after the first, zero otherwise
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                var v = 0.0f64
                var l1 = 0usize
                while l1 < kk {
                    v += dmat[i * kk + l1] * gm[l1 * wd + kk + j]
                    l1 += 1usize
                }
                dm[i * n + j] = v
                j += 1usize
            }
            i += 1usize
        }
        // Qm = DM + Ss (I - DM) - Sd, into t1
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                var v = dm[i * n + j] - sd[i * n + j]
                var k = 0usize
                while k < n {
                    var e = 0.0f64
                    if k == j { e = 1.0f64 }
                    v += ss[i * n + k] * (e - dm[k * n + j])
                    k += 1usize
                }
                t1[i * n + j] = v
                j += 1usize
            }
            i += 1usize
        }
        // obs = sum((D alpha + ghat - ghati)^2) / sigma^2 = |Qm y|^2 / sigma^2 for the same linear map
        var ob2 = 0.0f64
        i = 0usize
        while i < n {
            var v = 0.0f64
            var j = 0usize
            while j < n {
                v += t1[i * n + j] * ys[j]
                j += 1usize
            }
            ob2 += v * v
            i += 1usize
        }
        obs = ob2 / sig2
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
    }
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

// sm.survival(x, y = time, status, h, hv, p, status.code) at the evaluation point e: the local-linear regression of the ordered event times on the estimated survival-weighted covariate distribution, as sm's code
fn survival_at(a: *mem.Arena, x: []const f64, y: []const f64, status: []const f64, code: f64, h: f64, hv: f64, p: f64, e: f64) -> (f64, err) {
    let n = x.len
    let (ord, e0) = mem.alloc[usize](a, n)
    let (w, e1) = mem.alloc[f64](a, n)
    let (wf, e2) = mem.alloc[f64](a, n)
    let (yw, e3) = mem.alloc[f64](a, n)
    let (wd, e4) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && y[ord[j - 1usize]] > y[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    i = 0usize
    while i < n {
        let d = (e - x[ord[i]]) / h
        w[i] = math.exp[f64](0.0f64 - 0.5f64 * d * d)
        i += 1usize
    }
    var acc = 0.0f64
    i = n
    while i > 0usize {
        acc += w[i - 1usize]
        wf[i - 1usize] = acc
        i -= 1usize
    }
    var ns = 0usize
    var cp = 1.0f64
    var cum = 0.0f64
    i = 0usize
    while i < n {
        if status[ord[i]] == code {
            let nxt = cp * (1.0f64 - w[i] / wf[i])
            cum += cp - nxt
            cp = nxt
            wd[ns] = cum - p
            yw[ns] = y[ord[i]]
            ns += 1usize
        }
        i += 1usize
    }
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var k = 0usize
    while k < ns {
        let d = wd[k] / hv
        let kw = math.exp[f64](0.0f64 - 0.5f64 * d * d)
        s0 += kw
        s1 += kw * wd[k]
        s2 += kw * wd[k] * wd[k]
        k += 1usize
    }
    var est = 0.0f64
    k = 0usize
    while k < ns {
        let d = wd[k] / hv
        let kw = math.exp[f64](0.0f64 - 0.5f64 * d * d)
        est += kw * (s2 - wd[k] * s1) / (s2 * s0 - s1 * s1) * yw[k]
        k += 1usize
    }
    ret (est, ok)
}

// sm.regression(x, y, h, model = "no.effect" (kind 0) or "linear" (kind 1)) for one covariate, unbinned, unit weights: the p-value of the reference-band test (which = 0) or the q.squared (which = 1)
fn regression_test(a: *mem.Arena, x: []const f64, y: []const f64, h: f64, kind: usize, which: usize) -> (f64, err) {
    let n = x.len
    let nn = n * n
    let (w, e0) = mem.alloc[f64](a, nn)
    let (s0, e1) = mem.alloc[f64](a, nn)
    let (t1, e2) = mem.alloc[f64](a, nn)
    let (wq, e3) = mem.alloc[f64](a, nn)
    let (bm, e4) = mem.alloc[f64](a, nn)
    let (c2, e5) = mem.alloc[f64](a, nn)
    let (ee, e6) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < nn {
        w[i] = 0.0f64
        i += 1usize
    }
    smooth_block(w, n, 0usize, x, h)
    var mean = 0.0f64
    i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    // S0 = I - X (X'X)^-1 X' with X = 1 (no effect) or (1, x - mean)
    var sxx = 0.0f64
    i = 0usize
    while i < n {
        sxx += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var proj = 1.0f64 / f64(n)
            if kind == 1usize { proj += (x[i] - mean) * (x[j] - mean) / sxx }
            var d = 0.0f64
            if i == j { d = 1.0f64 }
            s0[i * n + j] = d - proj
            t1[i * n + j] = d - w[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    // W = (I - W0)'(I - W0)
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
            wq[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
    var r0 = 0.0f64
    var r1 = 0.0f64
    i = 0usize
    while i < n {
        var v = 0.0f64
        var k = 0usize
        while k < n {
            v += s0[i * n + k] * y[k]
            k += 1usize
        }
        ee[i] = v
        r0 += v * v
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            r1 += ee[i] * wq[i * n + j] * ee[j]
            j += 1usize
        }
        i += 1usize
    }
    let ts = (r0 - r1) / r1
    if which == 1usize { ret ((r0 - r1) / r0, ok) }
    // p.quad.moment(I - (1 + ts) W, S0, ts, 0)
    i = 0usize
    while i < nn {
        t1[i] = 0.0f64 - (1.0f64 + ts) * wq[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        t1[i * n + i] += 1.0f64
        i += 1usize
    }
    mm(bm, t1, s0, n)
    mm(c2, bm, bm, n)
    mm(t1, c2, bm, n)
    let k1 = trace(bm, n)
    let k2 = 2.0f64 * trace(c2, n)
    let k3 = 8.0f64 * trace(t1, n)
    let aa = math.abs[f64](k3 / (4.0f64 * k2))
    let bb = 8.0f64 * k2 * k2 * k2 / (k3 * k3)
    let cc = k1 - aa * bb
    ret (1.0f64 - nm.pchisq(0.0f64 - cc / aa, bb, true, false), ok)
}

// cv.crit.dens of sm for two variables (unit weights, no binning): the bandwidths are h1, h2
fn cv_density_2d(x1: []const f64, x2: []const f64, h1: f64, h2: f64) -> f64 {
    let n = x1.len
    let nn = f64(n)
    let pi2 = 6.283185307179586f64
    let s2 = math.sqrt[f64](2.0f64)
    let c0 = 1.0f64 / (math.sqrt[f64](pi2) * s2 * h1) / (math.sqrt[f64](pi2) * s2 * h2)
    var hc = nn * c0 / (nn * (nn - 1.0f64))
    var a = 0.0f64
    var b = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if i != j {
                let d1 = x1[i] - x1[j]
                let d2 = x2[i] - x2[j]
                a += math.exp[f64](0.0f64 - 0.5f64 * (d1 / (h1 * s2)) * (d1 / (h1 * s2))) / (math.sqrt[f64](pi2) * h1 * s2) * (math.exp[f64](0.0f64 - 0.5f64 * (d2 / (h2 * s2)) * (d2 / (h2 * s2))) / (math.sqrt[f64](pi2) * h2 * s2))
                b += math.exp[f64](0.0f64 - 0.5f64 * (d1 / h1) * (d1 / h1)) / (math.sqrt[f64](pi2) * h1) * (math.exp[f64](0.0f64 - 0.5f64 * (d2 / h2) * (d2 / h2)) / (math.sqrt[f64](pi2) * h2))
            }
            j += 1usize
        }
        i += 1usize
    }
    hc += a * (nn - 2.0f64) / (nn * (nn - 1.0f64) * (nn - 1.0f64))
    hc -= b * 2.0f64 / (nn * (nn - 1.0f64))
    ret hc
}

type Cv2Ctx = struct { x1: []const f64, x2: []const f64, s1: f64, s2: f64 }

fn cv2_log(c: *Cv2Ctx, lh: f64) -> f64 {
    let h = math.exp[f64](lh)
    let v = cv_density_2d(c.x1, c.x2, h * c.s1, h * c.s2)
    if v != v { ret 1.0e10f64 }
    ret v
}

// h.select(cbind(x1, x2), method = "cv") with the default scaled structure (start 0.5): the factor times the two standard deviations; which 0 the first bandwidth, 1 the second
fn hselect_cv_2d(x1: []const f64, x2: []const f64, which: usize) -> f64 {
    var c = Cv2Ctx { x1: x1, x2: x2, s1: sd_of(x1), s2: sd_of(x2) }
    let f = math.exp[f64](fd.brent_min[Cv2Ctx](&c, cv2_log, math.log[f64](0.5f64 / 8.0f64), math.log[f64](0.5f64 * 4.0f64)))
    if which == 0usize { ret f * c.s1 }
    ret f * c.s2
}

type Cv2cCtx = struct { x1: []const f64, x2: []const f64 }

fn cv2c_log(c: *Cv2cCtx, lh: f64) -> f64 {
    let h = math.exp[f64](lh)
    let v = cv_density_2d(c.x1, c.x2, h, h)
    if v != v { ret 1.0e10f64 }
    ret v
}

// the common structure (structure.2d = "common"): one bandwidth for both variables, start mean(sd / 2)
fn hselect_cv_2d_common(x1: []const f64, x2: []const f64) -> f64 {
    var c = Cv2cCtx { x1: x1, x2: x2 }
    let start = (sd_of(x1) / 2.0f64 + sd_of(x2) / 2.0f64) / 2.0f64
    ret math.exp[f64](fd.brent_min[Cv2cCtx](&c, cv2c_log, math.log[f64](start / 8.0f64), math.log[f64](start * 4.0f64)))
}

type Cv2sCtx = struct { x1: []const f64, x2: []const f64 }

fn cv2s_obj(c: *Cv2sCtx, lh: []const f64) -> f64 {
    let v = cv_density_2d(c.x1, c.x2, math.exp[f64](lh[0usize]), math.exp[f64](lh[1usize]))
    if v != v { ret 1.0e10f64 }
    ret v
}

// the separate structure (structure.2d = "separate"): R's optim (Nelder-Mead, reltol 1e-6) on the two log bandwidths from log(sd / 2); which 0 or 1
fn hselect_cv_2d_separate(a: *mem.Arena, x1: []const f64, x2: []const f64, which: usize) -> f64 {
    var c = Cv2sCtx { x1: x1, x2: x2 }
    var st: [2]f64 = zero
    st[0usize] = math.log[f64](sd_of(x1) / 2.0f64)
    st[1usize] = math.log[f64](sd_of(x2) / 2.0f64)
    var xo: [2]f64 = zero
    let (fv, cnt, fail) = rnm.nmmin[Cv2sCtx](a, &c, cv2s_obj, st[0usize..2usize], 0.0f64 - 1.0e308f64, 1.0e-6f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, xo[0usize..2usize])
    let _ = fv
    let _ = cnt
    let _ = fail
    ret math.exp[f64](xo[which])
}

// the 2-d local-linear smoother row of sm.weight2 at point i of (x1, x2), bandwidths h1, h2; cross drops the point itself. sii receives the diagonal entry (0 when cross), the answer is the fit of y
fn smooth_row_2d(x1: []const f64, x2: []const f64, y: []const f64, i: usize, h1: f64, h2: f64, cross: bool, sii: *f64) -> f64 {
    let n = x1.len
    var a11 = 0.0f64
    var a12 = 0.0f64
    var a13 = 0.0f64
    var a22 = 0.0f64
    var a23 = 0.0f64
    var a33 = 0.0f64
    var wbuf: [512]f64 = zero
    var j = 0usize
    while j < n {
        var w = xe.exp_r(0.0f64 - 0.5f64 * ((x1[i] - x1[j]) / h1) * ((x1[i] - x1[j]) / h1)) * xe.exp_r(0.0f64 - 0.5f64 * ((x2[i] - x2[j]) / h2) * ((x2[i] - x2[j]) / h2))
        if cross && j == i { w = 0.0f64 }
        let d1 = x1[i] - x1[j]
        let d2 = x2[i] - x2[j]
        if n <= 512usize { wbuf[j] = w }
        a11 += w
        a12 += w * d1
        a13 += w * d2
        a22 += w * (d1 * d1)
        a23 += w * d1 * d2
        a33 += w * (d2 * d2)
        j += 1usize
    }
    let d = a22 * a33 - a23 * a23
    let b1 = 1.0f64 / (a11 - ((a12 * a33 - a13 * a23) * a12 + (a13 * a22 - a12 * a23) * a13) / d)
    let b2 = (a13 * a23 - a12 * a33) * b1 / d
    let b3 = (a12 * a23 - a13 * a22) * b1 / d
    var fit = 0.0f64
    *sii = 0.0f64
    j = 0usize
    while j < n {
        let d1 = x1[i] - x1[j]
        let d2 = x2[i] - x2[j]
        var w = 0.0f64
        if n <= 512usize {
            w = wbuf[j]
        } else {
            w = xe.exp_r(0.0f64 - 0.5f64 * (d1 / h1) * (d1 / h1)) * xe.exp_r(0.0f64 - 0.5f64 * (d2 / h2) * (d2 / h2))
            if cross && j == i { w = 0.0f64 }
        }
        let s =(b1 + b2 * d1 + b3 * d2) * w
        var m = 0.0f64 - s
        if j == i {
            m = 1.0f64 - s
            *sii = s
        }
        fit += m * y[j]
        j += 1usize
    }
    ret fit
}

type Crit2Ctx = struct { x1: []const f64, x2: []const f64, y: []const f64, kind: usize, df: f64, s1: f64, s2: f64 }

// the 2-d regression criteria of h.select at bandwidths (h1, h2): kind 0 cv, 1 df, 2 aicc
fn crit2_val(c: *Crit2Ctx, h1: f64, h2: f64) -> f64 {
    let n = c.x1.len
    var trl = ld.ld_zero()
    var rssl = ld.ld_zero()
    var i = 0usize
    while i < n {
        var sii = 0.0f64
        let fit = smooth_row_2d(c.x1, c.x2, c.y, i, h1, h2, c.kind == 0usize, &sii)
        trl = ld.ld_add(trl, ld.ld_from(sii))
        rssl = ld.ld_add(rssl, ld.ld_from(fit * fit))
        i += 1usize
    }
    let nn = f64(n)
    let tr = ld.ld_to(trl)
    let rss = ld.ld_to(rssl)
    if c.kind == 0usize {
        let v = rss / nn
        if v != v { ret 1.0e10f64 }
        ret v
    }
    if c.kind == 1usize { ret (tr - c.df) * (tr - c.df) }
    let v = xe.log_r(rss / nn) + (1.0f64 + 2.0f64 * (tr + 1.0f64) / (nn - tr - 2.0f64))
    if v != v { ret 1.0e10f64 }
    ret v
}

fn crit2_log(c: *Crit2Ctx, lh: f64) -> f64 {
    let h = xe.exp_r(lh)
    ret crit2_val(c, h * c.s1, h * c.s2)
}

fn crit2_common(c: *Crit2Ctx, lh: f64) -> f64 {
    let h = xe.exp_r(lh)
    ret crit2_val(c, h, h)
}

fn crit2_sep(c: *Crit2Ctx, lh: []const f64) -> f64 { ret crit2_val(c, xe.exp_r(lh[0usize]), xe.exp_r(lh[1usize])) }

// h.select(cbind(x1, x2), y, method, structure.2d = "common" (structure 1) or "separate" (2); df is not allowed for separate): the bandwidth for variable which
fn hselect_reg_2d_other(a: *mem.Arena, x1: []const f64, x2: []const f64, y: []const f64, kind: usize, df: f64, structure: usize, which: usize) -> f64 {
    var c = Crit2Ctx { x1: x1, x2: x2, y: y, kind: kind, df: df, s1: sd_of(x1), s2: sd_of(x2) }
    if structure == 1usize {
        var sp: [2]f64 = zero
        sp[0usize] = c.s1 / 2.0f64
        sp[1usize] = c.s2 / 2.0f64
        let start = ld.mean_ld(sp[0usize..2usize])
        ret xe.exp_r(fd.brent_min[Crit2Ctx](&c, crit2_common, xe.log_r(start / 8.0f64), xe.log_r(start * 4.0f64)))
    }
    var st: [2]f64 = zero
    st[0usize] = xe.log_r(c.s1 / 2.0f64)
    st[1usize] = xe.log_r(c.s2 / 2.0f64)
    var xo: [2]f64 = zero
    let (fv, cnt, fail) = rnm.nmmin[Crit2Ctx](a, &c, crit2_sep, st[0usize..2usize], 0.0f64 - 1.0e308f64, 1.0e-6f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, xo[0usize..2usize])
    let _ = fv
    let _ = cnt
    let _ = fail
    ret xe.exp_r(xo[which])
}

// h.select(cbind(x1, x2), y, method = "cv" / "df" / "aicc") with the default scaled structure (start 0.5, df 12), unbinned: the bandwidth for variable which
fn hselect_reg_2d(x1: []const f64, x2: []const f64, y: []const f64, kind: usize, df: f64, which: usize) -> f64 {
    var c = Crit2Ctx { x1: x1, x2: x2, y: y, kind: kind, df: df, s1: sd_of(x1), s2: sd_of(x2) }
    let f = xe.exp_r(fd.brent_min[Crit2Ctx](&c, crit2_log, xe.log_r(0.5f64 / 8.0f64), xe.log_r(0.5f64 * 4.0f64)))
    if which == 0usize { ret f * c.s1 }
    ret f * c.s2
}

// sm.density's variability band for an unweighted, unrestricted 1-d estimate est at bandwidth h from a sample of n: se = sqrt(dnorm(0, sd = sqrt(2)) / (4 n h)), the bounds
// (sqrt(est) +- 2 se)^2 with the lower root cut at zero; answers (se, lower, upper)
fn density_band(est: f64, n: f64, h: f64) -> (f64, f64, f64) {
    let se = math.sqrt[f64](phi(0.0f64 / math.sqrt[f64](2.0f64)) / math.sqrt[f64](2.0f64) / (4.0f64 * n * h))
    let up = math.sqrt[f64](est) + 2.0f64 * se
    var lo = math.sqrt[f64](est) - 2.0f64 * se
    if lo < 0.0f64 { lo = 0.0f64 }
    ret (se, lo * lo, up * up)
}

// sm binning(cbind(x1, x2), y, nbins): nbins equal-width bins per axis over (min - 1e-5, max]; the non-empty cells in R's order (first axis fastest) go to bx1, bx2, bf, bm, bd (each nbins * nbins long); the answer is how many are non-empty
fn binning2d(a: *mem.Arena, x1: []const f64, x2: []const f64, y: []const f64, nbins: usize, bx1: []f64, bx2: []f64, bf: []f64, bm: []f64, bd: []f64) -> (usize, err) {
    let n = x1.len
    var lo1 = x1[0usize]
    var hi1 = x1[0usize]
    var lo2 = x2[0usize]
    var hi2 = x2[0usize]
    var i = 0usize
    while i < n {
        if x1[i] < lo1 { lo1 = x1[i] }
        if x1[i] > hi1 { hi1 = x1[i] }
        if x2[i] < lo2 { lo2 = x2[i] }
        if x2[i] > hi2 { hi2 = x2[i] }
        i += 1usize
    }
    let cells = nbins * nbins
    let (cnt, e0) = mem.alloc[f64](a, cells)
    let (sum, e1) = mem.alloc[f64](a, cells)
    let (idx, e2) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    let by1 = (hi1 - lo1) / f64(nbins)
    let by2 = (hi2 - lo2) / f64(nbins)
    var k = 0usize
    while k < cells {
        cnt[k] = 0.0f64
        sum[k] = 0.0f64
        k += 1usize
    }
    i = 0usize
    while i < n {
        var j1 = 0usize
        while j1 + 1usize < nbins && x1[i] > lo1 + f64(j1 + 1usize) * by1 { j1 += 1usize }
        var j2 = 0usize
        while j2 + 1usize < nbins && x2[i] > lo2 + f64(j2 + 1usize) * by2 { j2 += 1usize }
        idx[i] = j1 + nbins * j2
        cnt[idx[i]] += 1.0f64
        sum[idx[i]] += y[i]
        i += 1usize
    }
    var m = 0usize
    k = 0usize
    while k < cells {
        if cnt[k] > 0.0f64 {
            let mean = sum[k] / cnt[k]
            var dev = 0.0f64
            i = 0usize
            while i < n {
                if idx[i] == k { dev += (y[i] - mean) * (y[i] - mean) }
                i += 1usize
            }
            let j1 = k % nbins
            let j2 = k / nbins
            bx1[m] = (brk(lo1, by1, j1) + brk(lo1, by1, j1 + 1usize)) / 2.0f64
            bx2[m] = (brk(lo2, by2, j2) + brk(lo2, by2, j2 + 1usize)) / 2.0f64
            bf[m] = cnt[k]
            bm[m] = mean
            bd[m] = dev
            m += 1usize
        }
        k += 1usize
    }
    ret (m, ok)
}

// sm.weight / sm.weight2 (local linear, Gaussian kernel, poly.index 1) of the k points x1 (x2 too when two) with themselves, written into the block at offset o of smx (stride nt); wts are the point weights, hw the per-point bandwidth multipliers, cross zeroes the diagonal weight
fn smooth_w(smx: []f64, nt: usize, o: usize, x1: []const f64, x2: []const f64, two: bool, wts: []const f64, hw: []const f64, h1: f64, h2: f64, cross: bool) {
    let k = x1.len
    var i = 0usize
    while i < k {
        var a11 = 0.0f64
        var a12 = 0.0f64
        var a13 = 0.0f64
        var a22 = 0.0f64
        var a23 = 0.0f64
        var a33 = 0.0f64
        var j = 0usize
        while j < k {
            let wd1 = x1[i] - x1[j]
            var w = math.exp[f64](0.0f64 - 0.5f64 * (wd1 / (h1 * hw[j])) * (wd1 / (h1 * hw[j])))
            var wd2 = 0.0f64
            if two {
                wd2 = x2[i] - x2[j]
                w = w * math.exp[f64](0.0f64 - 0.5f64 * (wd2 / (h2 * hw[j])) * (wd2 / (h2 * hw[j])))
            }
            w = w * wts[j]
            if cross && i == j { w = 0.0f64 }
            a11 += w
            a12 += w * wd1
            a13 += w * wd2
            a22 += w * wd1 * wd1
            a23 += w * wd1 * wd2
            a33 += w * wd2 * wd2
            j += 1usize
        }
        var b1 = 0.0f64
        var b2 = 0.0f64
        var b3 = 0.0f64
        if two {
            let d = a22 * a33 - a23 * a23
            b1 = 1.0f64 / (a11 - ((a12 * a33 - a13 * a23) * a12 + (a13 * a22 - a12 * a23) * a13) / d)
            b2 = (a13 * a23 - a12 * a33) * b1 / d
            b3 = (a12 * a23 - a13 * a22) * b1 / d
        }
        j = 0usize
        while j < k {
            let wd1 = x1[i] - x1[j]
            var w = math.exp[f64](0.0f64 - 0.5f64 * (wd1 / (h1 * hw[j])) * (wd1 / (h1 * hw[j])))
            var wd2 = 0.0f64
            if two {
                wd2 = x2[i] - x2[j]
                w = w * math.exp[f64](0.0f64 - 0.5f64 * (wd2 / (h2 * hw[j])) * (wd2 / (h2 * hw[j])))
            }
            w = w * wts[j]
            if cross && i == j { w = 0.0f64 }
            if two {
                smx[(o + i) * nt + o + j] = (b1 + b2 * wd1 + b3 * wd2) * w
            } else {
                smx[(o + i) * nt + o + j] = w * (a22 - wd1 * a12) / (a22 * a11 - a12 * a12)
            }
            j += 1usize
        }
        i += 1usize
    }
}

// the 5th smallest of the k values in v (insertion-sorted in place)
fn fifth_smallest(v: []f64) -> f64 {
    var i = 1usize
    while i < v.len {
        let t = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > t {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = t
        i += 1usize
    }
    ret v[4usize]
}

// sm.sigweight of one group's k points (rows in the group's order; 1-d x ascending) with weights wts, added into the block at offset o of bm (stride nt)
fn sigweight_block(a: *mem.Arena, bm: []f64, nt: usize, o: usize, x1: []const f64, x2: []const f64, two: bool, wts: []const f64) -> err {
    let k = x1.len
    if !two {
        var r = 1usize
        while r + 1usize < k {
            let x0 = x1[r - 1usize]
            let xm = x1[r]
            let xp = x1[r + 1usize]
            var aa = (xp - xm) / (xp - x0)
            var bb = (xm - x0) / (xp - x0)
            if xp == x0 {
                aa = 0.5f64
                bb = 0.5f64
            }
            let cc = math.sqrt[f64](aa * aa / wts[r - 1usize] + bb * bb / wts[r + 1usize] + 1.0f64 / wts[r])
            var rowv: [3]f64 = zero
            rowv[0usize] = aa / cc
            rowv[1usize] = 0.0f64 - 1.0f64 / cc
            rowv[2usize] = bb / cc
            var u = 0usize
            while u < 3usize {
                var v = 0usize
                while v < 3usize {
                    bm[(o + r - 1usize + u) * nt + o + r - 1usize + v] += rowv[u] * rowv[v]
                    v += 1usize
                }
                u += 1usize
            }
            r += 1usize
        }
        ret ok
    }
    if k < 5usize { ret mem.Full }
    let (hw, e0) = mem.alloc[f64](a, k)
    let (tmp, e1) = mem.alloc[f64](a, k)
    let (am, e2) = mem.alloc[f64](a, k * k)
    let (sm2, e3) = mem.alloc[f64](a, k * k)
    let (dg, e4) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var m1 = 0.0f64
    var m2 = 0.0f64
    var i = 0usize
    while i < k {
        m1 += x1[i]
        m2 += x2[i]
        i += 1usize
    }
    m1 = m1 / f64(k)
    m2 = m2 / f64(k)
    var v1 = 0.0f64
    var v2 = 0.0f64
    i = 0usize
    while i < k {
        v1 += (x1[i] - m1) * (x1[i] - m1)
        v2 += (x2[i] - m2) * (x2[i] - m2)
        i += 1usize
    }
    v1 = v1 / (f64(k) - 1.0f64)
    v2 = v2 / (f64(k) - 1.0f64)
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            tmp[j] = math.sqrt[f64]((x1[i] - x1[j]) * (x1[i] - x1[j]) / v1 + (x2[i] - x2[j]) * (x2[i] - x2[j]) / v2)
            j += 1usize
        }
        hw[i] = fifth_smallest(tmp) / 2.0f64
        i += 1usize
    }
    smooth_w(sm2, k, 0usize, x1, x2, true, wts, hw, math.sqrt[f64](v1), math.sqrt[f64](v2), true)
    i = 0usize
    while i < k * k {
        var v = 0.0f64
        if i / k == i % k { v = 1.0f64 }
        am[i] = v - sm2[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += am[i * k + j] * am[i * k + j]
            j += 1usize
        }
        dg[i] = s
        i += 1usize
    }
    var u = 0usize
    while u < k {
        var v = 0usize
        while v < k {
            var s = 0.0f64
            i = 0usize
            while i < k {
                s += am[i * k + u] * am[i * k + v] / dg[i]
                i += 1usize
            }
            bm[(o + u) * nt + o + v] += s
            v += 1usize
        }
        u += 1usize
    }
    ret ok
}

// sm.ancova(x, y, group, h, model = "equal" or "parallel") for one covariate (x2 empty) or two, binned to nbins per axis within each group when nbins > 0 (else unit weights); rows are ordered by group then, for one covariate, x as R does; h2 is unused for one covariate
fn ancova_gen(a: *mem.Arena, x1: []const f64, x2: []const f64, y: []const f64, group: []const f64, h1: f64, h2: f64, nbins: usize, parallel: bool) -> (f64, err) {
    let nobs = y.len
    let two = x2.len > 0usize
    let (ord, e0) = mem.alloc[usize](a, nobs)
    if e0 != ok { ret (0.0f64, e0) }
    var i = 0usize
    var rlo = x1[0usize]
    var rhi = x1[0usize]
    while i < nobs {
        ord[i] = i
        if x1[i] < rlo { rlo = x1[i] }
        if x1[i] > rhi { rhi = x1[i] }
        i += 1usize
    }
    i = 1usize
    while i < nobs {
        let v = ord[i]
        var j = i
        while j > 0usize && (group[ord[j - 1usize]] > group[v] || (!two && group[ord[j - 1usize]] == group[v] && x1[ord[j - 1usize]] > x1[v])) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    let (ox1, f1) = mem.alloc[f64](a, nobs)
    let (ox2, f2) = mem.alloc[f64](a, nobs)
    let (oy, f3) = mem.alloc[f64](a, nobs)
    let (xs, f4) = mem.alloc[f64](a, nobs)
    let (xs2, f5) = mem.alloc[f64](a, nobs)
    let (ys, f6) = mem.alloc[f64](a, nobs)
    let (ws, f7) = mem.alloc[f64](a, nobs)
    let (gs, f8) = mem.alloc[usize](a, nobs)
    let (ones, f9) = mem.alloc[f64](a, nobs)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok { ret (0.0f64, mem.Full) }
    var cap = nobs
    if nbins > 0usize {
        cap = nbins
        if two { cap = nbins * nbins }
    }
    let (tb1, g1) = mem.alloc[f64](a, cap)
    let (tb2, g2) = mem.alloc[f64](a, cap)
    let (tbf, g3) = mem.alloc[f64](a, cap)
    let (tbm, g4) = mem.alloc[f64](a, cap)
    let (tbd, g5) = mem.alloc[f64](a, cap)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok { ret (0.0f64, mem.Full) }
    i = 0usize
    while i < nobs {
        ox1[i] = x1[ord[i]]
        ox2[i] = 0.0f64
        if two { ox2[i] = x2[ord[i]] }
        oy[i] = y[ord[i]]
        ones[i] = 1.0f64
        i += 1usize
    }
    var m = 0usize
    var devsum = 0.0f64
    var ng = 0usize
    var st = 0usize
    while st < nobs {
        var en = st
        while en < nobs && group[ord[en]] == group[ord[st]] { en += 1usize }
        if nbins > 0usize {
            var cnt = 0usize
            if two {
                let (c2, eb) = binning2d(a, ox1[st..en], ox2[st..en], oy[st..en], nbins, tb1, tb2, tbf, tbm, tbd)
                if eb != ok { ret (0.0f64, eb) }
                cnt = c2
            } else {
                let (c1, eb) = binning1d(a, ox1[st..en], oy[st..en], nbins, tb1, tbf, tbm, tbd)
                if eb != ok { ret (0.0f64, eb) }
                cnt = c1
            }
            var r = 0usize
            while r < cnt {
                xs[m] = tb1[r]
                xs2[m] = 0.0f64
                if two { xs2[m] = tb2[r] }
                ys[m] = tbm[r]
                ws[m] = tbf[r]
                gs[m] = ng
                devsum += tbd[r]
                m += 1usize
                r += 1usize
            }
        } else {
            var r = st
            while r < en {
                xs[m] = ox1[r]
                xs2[m] = ox2[r]
                ys[m] = oy[r]
                ws[m] = 1.0f64
                gs[m] = ng
                m += 1usize
                r += 1usize
            }
        }
        ng += 1usize
        st = en
    }
    let nn = m * m
    let (sd, h1e) = mem.alloc[f64](a, nn)
    let (ss, h2e) = mem.alloc[f64](a, nn)
    let (bm, h3e) = mem.alloc[f64](a, nn)
    let (q, h4e) = mem.alloc[f64](a, nn)
    let (q2, h5e) = mem.alloc[f64](a, nn)
    let (t1, h6e) = mem.alloc[f64](a, nn)
    if h1e != ok || h2e != ok || h3e != ok || h4e != ok || h5e != ok || h6e != ok { ret (0.0f64, mem.Full) }
    i = 0usize
    while i < nn {
        sd[i] = 0.0f64
        ss[i] = 0.0f64
        bm[i] = 0.0f64
        i += 1usize
    }
    st = 0usize
    while st < m {
        var en = st
        while en < m && gs[en] == gs[st] { en += 1usize }
        smooth_w(sd, m, st, xs[st..en], xs2[st..en], two, ws[st..en], ones[st..en], h1, h2, false)
        let es = sigweight_block(a, bm, m, st, xs[st..en], xs2[st..en], two, ws[st..en])
        if es != ok { ret (0.0f64, es) }
        st = en
    }
    smooth_w(ss, m, 0usize, xs[0usize..m], xs2[0usize..m], two, ws[0usize..m], ones[0usize..m], h1, h2, false)
    var sig2 = devsum
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            sig2 += ys[i] * bm[i * m + j] * ys[j]
            j += 1usize
        }
        i += 1usize
    }
    var obs = 0.0f64
    if !parallel {
        i = 0usize
        while i < nn {
            t1[i] = sd[i] - ss[i]
            i += 1usize
        }
    } else {
        var halpha = h1
        if !two { halpha = 2.0f64 * (rhi - rlo) / f64(nobs) }
        let kk = ng - 1usize
        let (gsz, e10) = mem.alloc[usize](a, ng)
        let (dmat, e11) = mem.alloc[f64](a, m * kk)
        let (q0, e12) = mem.alloc[f64](a, nn)
        let (am, e13) = mem.alloc[f64](a, m * kk)
        let (gm, e14) = mem.alloc[f64](a, kk * (kk + m))
        let (dm, e15) = mem.alloc[f64](a, nn)
        if e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok { ret (0.0f64, mem.Full) }
        i = 0usize
        while i < ng {
            gsz[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < m {
            gsz[gs[i]] += 1usize
            i += 1usize
        }
        // R builds D with istart fixed at n[1] + 1 for every column, so column l marks rows n1 + 1 .. n1 + n[l + 1]
        i = 0usize
        while i < m {
            var l0 = 0usize
            while l0 < kk {
                dmat[i * kk + l0] = 0.0f64
                if i >= gsz[0usize] && i < gsz[0usize] + gsz[l0 + 1usize] { dmat[i * kk + l0] = 1.0f64 }
                l0 += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < nn {
            q0[i] = 0.0f64
            i += 1usize
        }
        smooth_w(q0, m, 0usize, xs[0usize..m], xs2[0usize..m], two, ws[0usize..m], ones[0usize..m], halpha, h2, false)
        i = 0usize
        while i < nn {
            var v = 0.0f64
            if i / m == i % m { v = 1.0f64 }
            q0[i] = v - q0[i]
            i += 1usize
        }
        // A = Q0 D; the system [A' W A | A' W Q0] is solved by Gauss-Jordan for M (kk by m)
        i = 0usize
        while i < m {
            var l = 0usize
            while l < kk {
                var v = 0.0f64
                var r = 0usize
                while r < m {
                    v += q0[i * m + r] * dmat[r * kk + l]
                    r += 1usize
                }
                am[i * kk + l] = v
                l += 1usize
            }
            i += 1usize
        }
        let wd = kk + m
        var l = 0usize
        while l < kk {
            var c2 = 0usize
            while c2 < kk {
                var v = 0.0f64
                var r = 0usize
                while r < m {
                    v += am[r * kk + l] * ws[r] * am[r * kk + c2]
                    r += 1usize
                }
                gm[l * wd + c2] = v
                c2 += 1usize
            }
            c2 = 0usize
            while c2 < m {
                var v = 0.0f64
                var r = 0usize
                while r < m {
                    v += am[r * kk + l] * ws[r] * q0[r * m + c2]
                    r += 1usize
                }
                gm[l * wd + kk + c2] = v
                c2 += 1usize
            }
            l += 1usize
        }
        var col = 0usize
        while col < kk {
            var piv = col
            var rr = col + 1usize
            while rr < kk {
                if math.abs[f64](gm[rr * wd + col]) > math.abs[f64](gm[piv * wd + col]) { piv = rr }
                rr += 1usize
            }
            var cc2 = 0usize
            while cc2 < wd {
                let tt = gm[col * wd + cc2]
                gm[col * wd + cc2] = gm[piv * wd + cc2]
                gm[piv * wd + cc2] = tt
                cc2 += 1usize
            }
            let pv = gm[col * wd + col]
            cc2 = 0usize
            while cc2 < wd {
                gm[col * wd + cc2] = gm[col * wd + cc2] / pv
                cc2 += 1usize
            }
            rr = 0usize
            while rr < kk {
                if rr != col {
                    let fct = gm[rr * wd + col]
                    cc2 = 0usize
                    while cc2 < wd {
                        gm[rr * wd + cc2] -= fct * gm[col * wd + cc2]
                        cc2 += 1usize
                    }
                }
                rr += 1usize
            }
            col += 1usize
        }
        i = 0usize
        while i < m {
            var j = 0usize
            while j < m {
                var v = 0.0f64
                var l1 = 0usize
                while l1 < kk {
                    v += dmat[i * kk + l1] * gm[l1 * wd + kk + j]
                    l1 += 1usize
                }
                dm[i * m + j] = v
                j += 1usize
            }
            i += 1usize
        }
        // Qm = DM + Ss (I - DM) - Sd, into t1
        i = 0usize
        while i < m {
            var j = 0usize
            while j < m {
                var v = dm[i * m + j] - sd[i * m + j]
                var k = 0usize
                while k < m {
                    var e = 0.0f64
                    if k == j { e = 1.0f64 }
                    v += ss[i * m + k] * (e - dm[k * m + j])
                    k += 1usize
                }
                t1[i * m + j] = v
                j += 1usize
            }
            i += 1usize
        }
    }
    // Q = t1' W t1 and obs = y' Q y / sigma^2 (the same linear map gives the parallel statistic sum(w (D alpha + ghat - ghati)^2))
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var v = 0.0f64
            var k = 0usize
            while k < m {
                v += t1[k * m + i] * ws[k] * t1[k * m + j]
                k += 1usize
            }
            q[i * m + j] = v
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            obs += ys[i] * q[i * m + j] * ys[j]
            j += 1usize
        }
        i += 1usize
    }
    obs = obs / sig2
    // p.quad.moment(Q - B obs, diag(1/w), obs, sum(w) - length(w))
    var sw = 0.0f64
    i = 0usize
    while i < m {
        sw += ws[i]
        i += 1usize
    }
    let ndevs = sw - f64(m)
    i = 0usize
    while i < nn {
        q[i] = (q[i] - bm[i] * obs) / ws[i % m]
        i += 1usize
    }
    mm(q2, q, q, m)
    mm(t1, q2, q, m)
    let k1 = trace(q, m) - obs * ndevs
    let k2 = 2.0f64 * trace(q2, m) + 2.0f64 * obs * obs * ndevs
    let k3 = 8.0f64 * trace(t1, m) - 8.0f64 * obs * obs * obs * ndevs
    let aa = math.abs[f64](k3 / (4.0f64 * k2))
    let bb = 8.0f64 * k2 * k2 * k2 / (k3 * k3)
    let cc = k1 - aa * bb
    ret (1.0f64 - nm.pchisq(0.0f64 - cc / aa, bb, true, false), ok)
}

// the model fit sm.regression reports as model.y at p (unit weights): the mean of y for no.effect (kind 0), the least-squares line for linear (kind 1)
fn model_fit(x: []const f64, y: []const f64, kind: usize, p: f64) -> f64 {
    let n = f64(x.len)
    var sx = 0.0f64
    var sy = 0.0f64
    var j = 0usize
    while j < x.len {
        sx += x[j]
        sy += y[j]
        j += 1usize
    }
    let mx = sx / n
    let my = sy / n
    if kind == 0usize { ret my }
    var sxy = 0.0f64
    var sxx = 0.0f64
    j = 0usize
    while j < x.len {
        sxy += (x[j] - mx) * (y[j] - my)
        sxx += (x[j] - mx) * (x[j] - mx)
        j += 1usize
    }
    ret my + sxy / sxx * (p - mx)
}

// sm.options() defaults that are a number or a logical (TRUE 1, FALSE 0, NA as NaN); the flag says whether name is one of them
fn option_scalar(name: str) -> (f64, bool) {
    let na = 0.0f64 / 0.0f64
    if str.eq(name, "hmult") || str.eq(name, "hscale") || str.eq(name, "vscale") || str.eq(name, "lty") || str.eq(name, "lwd") || str.eq(name, "pch") || str.eq(name, "alpha.mesh") || str.eq(name, "poly.index") || str.eq(name, "verbose") || str.eq(name, "key") || str.eq(name, "rugplot") || str.eq(name, "hull") || str.eq(name, "describe") || str.eq(name, "show.script") || str.eq(name, "eval.grid") || str.eq(name, "partial.residuals") { ret (1.0f64, true) }
    if str.eq(name, "add") || str.eq(name, "positive") || str.eq(name, "panel") || str.eq(name, "lit") || str.eq(name, "include.lower.reference") || str.eq(name, "eqscplot") { ret (0.0f64, true) }
    if str.eq(name, "theta") { ret (0.0f64 - 30.0f64, true) }
    if str.eq(name, "phi") { ret (40.0f64, true) }
    if str.eq(name, "size") || str.eq(name, "diff.ord") { ret (2.0f64, true) }
    if str.eq(name, "alpha") { ret (0.7f64, true) }
    if str.eq(name, "nboot") { ret (100.0f64, true) }
    if str.eq(name, "nlevels") { ret (20.0f64, true) }
    if str.eq(name, "h.weights") || str.eq(name, "period") || str.eq(name, "band") || str.eq(name, "nbins") || str.eq(name, "delta") || str.eq(name, "display") || str.eq(name, "xlab") || str.eq(name, "ylab") || str.eq(name, "zlab") || str.eq(name, "x1lim") || str.eq(name, "x2lim") || str.eq(name, "xlim") || str.eq(name, "ylim") || str.eq(name, "zlim") || str.eq(name, "yht") || str.eq(name, "asp") || str.eq(name, "cex") || str.eq(name, "cex.axis") || str.eq(name, "cex.lab") || str.eq(name, "labcex") || str.eq(name, "panel.plot") || str.eq(name, "ngrid") || str.eq(name, "eval.points") || str.eq(name, "col") || str.eq(name, "superimpose") || str.eq(name, "se") || str.eq(name, "test") || str.eq(name, "df") || str.eq(name, "df.max") || str.eq(name, "method") || str.eq(name, "include.mean") || str.eq(name, "colour.key") || str.eq(name, "z.key") || str.eq(name, "deriv") || str.eq(name, "deriv.order") { ret (na, true) }
    ret (0.0f64, false)
}

// sm.options() defaults that are one string; the flag says whether name is one of them
fn option_text(name: str) -> (str, bool) {
    if str.eq(name, "model") || str.eq(name, "reference") { ret ("none", true) }
    if str.eq(name, "col.band") { ret ("cyan", true) }
    if str.eq(name, "col.mesh") || str.eq(name, "col.points") { ret ("black", true) }
    if str.eq(name, "structure.2d") { ret ("scaled", true) }
    if str.eq(name, "mask.method") { ret ("hull", true) }
    if str.eq(name, "include.terms") { ret ("single", true) }
    ret ("", false)
}

// element k (from 0) of the vector defaults props, se.breaks and order; NaN past the end or for another name
fn option_vector(name: str, k: usize) -> f64 {
    let na = 0.0f64 / 0.0f64
    if str.eq(name, "props") {
        if k == 0usize { ret 75.0f64 }
        if k == 1usize { ret 50.0f64 }
        if k == 2usize { ret 25.0f64 }
        ret na
    }
    if str.eq(name, "se.breaks") {
        if k == 0usize { ret 0.0f64 - 3.0f64 }
        if k == 1usize { ret 0.0f64 - 2.0f64 }
        if k == 2usize { ret 2.0f64 }
        if k == 3usize { ret 3.0f64 }
        ret na
    }
    if str.eq(name, "order") && k < 3usize { ret f64(k + 1usize) }
    ret na
}
