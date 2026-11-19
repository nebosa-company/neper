// R sm: the normal-reference bandwidth hnorm, sm.density in one and two dimensions with the Gaussian kernel, and sm.regression at evaluation points
// (local constant or local linear, Gaussian kernel), all on unbinned data (sm bins only above 100 observations).
//
// Not here: h.select dispatch, bands and standard errors, sm.ancova, sm.survival and sm.options.

use e.math
use e.mem
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
