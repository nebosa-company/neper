// R gmm for the linear model y = X b with instruments Z (n by q, q >= p), one equation: the two-step, iterated and continuously updated (CUE) estimators, the weighting
// vcov = "iid", "MDS" or "HAC" (the five kernels, a fixed bandwidth or the Andrews (bwAndrews, AR(1)) and Newey-West (bwNeweyWest) selectors, with or without the VAR(1) prewhitening
// of sandwich's vcovHAC), the coefficient covariance, the Hansen J statistic with its p-value and the linear hypothesis Wald and F tests of car::linearHypothesis.
//
// Not here: nonlinear moment functions, several equations, the ARMA(1,1) bandwidth approximation, bwWilhelm, eqConst, the Kleibergen K tests and optfct other than optim
// (Nelder-Mead or BFGS with the numerical gradient).

use e.algo.stat.carlmtest as ols
use e.algo.stat.rbfgs as bf
use e.algo.stat.rnm as rn
use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Spec = struct { a: *mem.Arena, y: []const f64, x: []const f64, z: []const f64, n: usize, p: usize, q: usize, vcov: usize, kernel: usize, bwmode: usize, bw: f64, prewhite: usize, zint: bool }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// a zeroed scratch vector; the arena is sized by the caller
fn nf(a: *mem.Arena, n: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](a, n)
    var i = 0usize
    while i < v.len {
        v[i] = 0.0f64
        i += 1usize
    }
    ret v
}

fn invert(a: *mem.Arena, m: []const f64, p: usize, out: []f64) -> bool { ret ols.inverse(a, m, p, out) == ok }

// C (n by m) = A (n by k) B (k by m), row-major
fn mmul(x: []const f64, y: []const f64, n: usize, k: usize, m: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < m {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += x[i * k + l] * y[l * m + j]
                l += 1usize
            }
            out[i * m + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// A' B for A (n by p) and B (n by q), row-major, into out (p by q)
fn crossp(x: []const f64, y: []const f64, n: usize, p: usize, q: usize, out: []f64) {
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += x[r * p + i] * y[r * q + j]
                r += 1usize
            }
            out[i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// the GMM step with weight matrix w (q by q): b = (X'Z W Z'X)^-1 X'Z W Z'y; xz is p by q, zy is q
fn gmm_step(a: *mem.Arena, xz: []const f64, zy: []const f64, w: []const f64, p: usize, q: usize, beta: []f64) -> bool {
    let xzw = nf(a, p * q)
    mmul(xz, w, p, q, q, xzw)
    let m = nf(a, p * p)
    let mi = nf(a, p * p)
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < q {
                s += xzw[i * q + k] * xz[j * q + k]
                k += 1usize
            }
            m[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    if !invert(a, m, p, mi) { ret false }
    i = 0usize
    while i < p {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            var t = 0.0f64
            var k = 0usize
            while k < q {
                t += xzw[j * q + k] * zy[k]
                k += 1usize
            }
            s += mi[i * p + j] * t
            j += 1usize
        }
        beta[i] = s
        i += 1usize
    }
    ret true
}

fn resid(s: *Spec, th: []const f64, e: []f64) {
    var i = 0usize
    while i < s.n {
        var fit = 0.0f64
        var j = 0usize
        while j < s.p {
            fit += s.x[i * s.p + j] * th[j]
            j += 1usize
        }
        e[i] = s.y[i] - fit
        i += 1usize
    }
}

// g_i = z_i e_i (n by q)
fn moments(s: *Spec, e: []const f64, g: []f64) {
    var i = 0usize
    while i < s.n {
        var j = 0usize
        while j < s.q {
            g[i * s.q + j] = s.z[i * s.q + j] * e[i]
            j += 1usize
        }
        i += 1usize
    }
}

fn colmeans(g: []const f64, n: usize, q: usize, m: []f64) {
    var j = 0usize
    while j < q {
        var t = 0.0f64
        var i = 0usize
        while i < n {
            t += g[i * q + j]
            i += 1usize
        }
        m[j] = t / f64(n)
        j += 1usize
    }
}

fn center(a: *mem.Arena, g: []f64, n: usize, q: usize) {
    let m = nf(a, q)
    colmeans(g, n, q, m)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < q {
            g[i * q + j] = g[i * q + j] - m[j]
            j += 1usize
        }
        i += 1usize
    }
}

fn qs(x: f64) -> f64 {
    let pi = 3.141592653589793238462643383279f64
    let y = 6.0f64 * pi * x / 5.0f64
    let r = 1.0f64 / y
    ret 3.0f64 * (r * r) * (math.sin[f64](y) / y - math.cos[f64](y))
}

// sandwich's kweights: kernel 0 Quadratic Spectral, 1 Truncated, 2 Bartlett, 3 Parzen, 4 Tukey-Hanning
fn kweight(kind: usize, x: f64) -> f64 {
    let pi = 3.141592653589793238462643383279f64
    let ax = math.abs[f64](x)
    if kind == 0usize {
        if ax < 0.001f64 {
            let cf = 1.0e6f64 * math.log[f64](qs(0.001f64))
            ret math.exp[f64](cf * (x * x))
        }
        ret qs(x)
    }
    if ax > 1.0f64 { ret 0.0f64 }
    if kind == 1usize { ret 1.0f64 }
    if kind == 2usize { ret 1.0f64 - ax }
    if kind == 3usize {
        if ax < 0.5f64 { ret 1.0f64 - 6.0f64 * (x * x) + 6.0f64 * math.pow[f64](ax, 3.0f64) }
        ret 2.0f64 * math.pow[f64](1.0f64 - ax, 3.0f64)
    }
    ret (1.0f64 + math.cos[f64](pi * x)) / 2.0f64
}

// ar(u, order.max = 1, demean = FALSE, aic = FALSE, method = "ols") on the n by q matrix g: the residuals of rows 2 to n into u ((n - 1) by q) and D = (I - A)^-1 into d (q by q)
fn prewhiten(s: *Spec, g: []const f64, u: []f64, d: []f64) {
    let a = s.a
    let n = s.n
    let q = s.q
    let xx = nf(a, q * q)
    let xy = nf(a, q * q)
    var r = 0usize
    while r + 1usize < n {
        var j = 0usize
        while j < q {
            var k = 0usize
            while k < q {
                xx[j * q + k] += g[r * q + j] * g[r * q + k]
                xy[j * q + k] += g[r * q + j] * g[(r + 1usize) * q + k]
                k += 1usize
            }
            j += 1usize
        }
        r += 1usize
    }
    let xxi = nf(a, q * q)
    let b = nf(a, q * q)
    if !invert(a, xx, q, xxi) { ret }
    mmul(xxi, xy, q, q, q, b)
    r = 0usize
    while r + 1usize < n {
        var i = 0usize
        while i < q {
            var fit = 0.0f64
            var j = 0usize
            while j < q {
                fit += g[r * q + j] * b[j * q + i]
                j += 1usize
            }
            u[r * q + i] = g[(r + 1usize) * q + i] - fit
            i += 1usize
        }
        r += 1usize
    }
    let ima = nf(a, q * q)
    var i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            var dg = 0.0f64
            if i == j { dg = 1.0f64 }
            ima[i * q + j] = dg - b[j * q + i]
            j += 1usize
        }
        i += 1usize
    }
    if !invert(a, ima, q, d) { ret }
}

// weightsAndrews and meatHAC (adjust = FALSE, sandwich = FALSE) for the centred moments g at bandwidth bw, tolerance 1e-7
fn hac_meat(s: *Spec, g: []const f64, bw: f64, out: []f64) {
    let a = s.a
    let n0 = s.n
    let q = s.q
    var n = n0
    var u: []const f64 = g
    let dm = nf(a, q * q)
    if s.prewhite > 0usize {
        n = n0 - 1usize
        let uw = nf(a, n * q)
        prewhiten(s, g, uw, dm)
        u = uw
    }
    let wk = nf(a, n)
    var last = 0usize
    var l = 0usize
    while l < n {
        wk[l] = kweight(s.kernel, f64(l) / bw)
        if math.abs[f64](wk[l]) > 1.0e-7f64 { last = l }
        l += 1usize
    }
    let utu = nf(a, q * q)
    l = 0usize
    while l <= last {
        var wt = wk[l]
        if l == 0usize { wt = 0.5f64 * wt }
        var j = 0usize
        while j < q {
            var k = 0usize
            while k < q {
                var t = 0.0f64
                var i = 0usize
                while i + l < n {
                    t += u[i * q + j] * u[(i + l) * q + k]
                    i += 1usize
                }
                utu[j * q + k] += wt * t
                k += 1usize
            }
            j += 1usize
        }
        l += 1usize
    }
    let sym = nf(a, q * q)
    var j = 0usize
    while j < q {
        var k = 0usize
        while k < q {
            sym[j * q + k] = utu[j * q + k] + utu[k * q + j]
            k += 1usize
        }
        j += 1usize
    }
    if s.prewhite > 0usize {
        let t1 = nf(a, q * q)
        let dt = nf(a, q * q)
        mmul(dm, sym, q, q, q, t1)
        j = 0usize
        while j < q {
            var k = 0usize
            while k < q {
                dt[j * q + k] = dm[k * q + j]
                k += 1usize
            }
            j += 1usize
        }
        mmul(t1, dt, q, q, q, sym)
    }
    j = 0usize
    while j < q * q {
        out[j] = sym[j] / f64(n0)
        j += 1usize
    }
}

// the moment weights of bwAndrews and bwNeweyWest: 0 for an instrument named "(Intercept)", 1 otherwise, all 1 when none is left
fn bw_weights(s: *Spec, wts: []f64) {
    var j = 0usize
    while j < s.q {
        wts[j] = 1.0f64
        j += 1usize
    }
    if s.zint { wts[0usize] = 0.0f64 }
    var any = false
    j = 0usize
    while j < s.q {
        if wts[j] > 0.0f64 { any = true }
        j += 1usize
    }
    if !any {
        j = 0usize
        while j < s.q {
            wts[j] = 1.0f64
            j += 1usize
        }
    }
}

// ar(x, order.max = 1, aic = FALSE, method = "ols") of column j of u (n by q): (rho, sqrt(var.pred))
fn ar1(u: []const f64, n: usize, q: usize, j: usize) -> (f64, f64) {
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += u[i * q + j]
        i += 1usize
    }
    mean = mean / f64(n)
    let m = f64(n - 1usize)
    var my = 0.0f64
    var mx = 0.0f64
    i = 1usize
    while i < n {
        my += u[i * q + j] - mean
        mx += u[(i - 1usize) * q + j] - mean
        i += 1usize
    }
    my = my / m
    mx = mx / m
    var sxy = 0.0f64
    var sxx = 0.0f64
    i = 1usize
    while i < n {
        let yy = u[i * q + j] - mean - my
        let xv = u[(i - 1usize) * q + j] - mean - mx
        sxy += yy * xv
        sxx += xv * xv
        i += 1usize
    }
    let rho = sxy / sxx
    var rss = 0.0f64
    i = 1usize
    while i < n {
        let yy = u[i * q + j] - mean - my
        let xv = u[(i - 1usize) * q + j] - mean - mx
        let r = yy - rho * xv
        rss += r * r
        i += 1usize
    }
    ret (rho, math.sqrt[f64](rss / m))
}

// sandwich::bwAndrews with the AR(1) approximation on the centred moments g
fn bw_andrews(s: *Spec, g: []const f64) -> f64 {
    let a = s.a
    let q = s.q
    var n = s.n
    var u: []const f64 = g
    if s.prewhite > 0usize {
        n = s.n - 1usize
        let uw = nf(a, n * q)
        let dm = nf(a, q * q)
        prewhiten(s, g, uw, dm)
        u = uw
    }
    let wts = nf(a, q)
    bw_weights(s, wts)
    var denum = 0.0f64
    var num2 = 0.0f64
    var num1 = 0.0f64
    var j = 0usize
    while j < q {
        let (rho, sg) = ar1(u, n, q, j)
        let om = 1.0f64 - rho
        denum += wts[j] * math.pow[f64](sg / om, 4.0f64)
        num2 += wts[j] * 4.0f64 * (rho * rho) * math.pow[f64](sg, 4.0f64) / math.pow[f64](om, 8.0f64)
        num1 += wts[j] * 4.0f64 * (rho * rho) * math.pow[f64](sg, 4.0f64) / (math.pow[f64](om, 6.0f64) * ((1.0f64 + rho) * (1.0f64 + rho)))
        j += 1usize
    }
    let alpha2 = num2 / denum
    let alpha1 = num1 / denum
    let nn = f64(n)
    if s.kernel == 1usize { ret 0.6611f64 * math.pow[f64](nn * alpha2, 1.0f64 / 5.0f64) }
    if s.kernel == 2usize { ret 1.1447f64 * math.pow[f64](nn * alpha1, 1.0f64 / 3.0f64) }
    if s.kernel == 3usize { ret 2.6614f64 * math.pow[f64](nn * alpha2, 1.0f64 / 5.0f64) }
    if s.kernel == 4usize { ret 1.7462f64 * math.pow[f64](nn * alpha2, 1.0f64 / 5.0f64) }
    ret 1.3221f64 * math.pow[f64](nn * alpha2, 1.0f64 / 5.0f64)
}

// sandwich::bwNeweyWest (Bartlett, Parzen or Quadratic Spectral) on the centred moments g
fn bw_neweywest(s: *Spec, g: []const f64) -> f64 {
    let a = s.a
    let q = s.q
    let n0 = s.n
    var n = n0
    var u: []const f64 = g
    let wts = nf(a, q)
    bw_weights(s, wts)
    var mrate = 2.0f64 / 9.0f64
    if s.kernel == 3usize { mrate = 4.0f64 / 25.0f64 }
    if s.kernel == 0usize { mrate = 2.0f64 / 25.0f64 }
    var mult = 4.0f64
    if s.prewhite > 0usize { mult = 3.0f64 }
    let m = usize(math.floor[f64](mult * math.pow[f64](f64(n0) / 100.0f64, mrate)))
    if s.prewhite > 0usize {
        n = n0 - 1usize
        let uw = nf(a, n * q)
        let dm = nf(a, q * q)
        prewhiten(s, g, uw, dm)
        u = uw
    }
    let hw = nf(a, n)
    var i = 0usize
    while i < n {
        var t = 0.0f64
        var j = 0usize
        while j < q {
            t += u[i * q + j] * wts[j]
            j += 1usize
        }
        hw[i] = t
        i += 1usize
    }
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var lag = 0usize
    while lag <= m {
        var t = 0.0f64
        i = 0usize
        while i + lag < n {
            t += hw[i] * hw[i + lag]
            i += 1usize
        }
        let sg = t / f64(n)
        if lag == 0usize {
            s0 += sg
        } else {
            s0 += 2.0f64 * sg
            s1 += 2.0f64 * f64(lag) * sg
            s2 += 2.0f64 * (f64(lag) * f64(lag)) * sg
        }
        lag += 1usize
    }
    var qrate = 1.0f64 / 5.0f64
    if s.kernel == 2usize { qrate = 1.0f64 / 3.0f64 }
    var c = 1.1447f64
    var ratio = s1 / s0
    if s.kernel == 3usize {
        c = 2.6614f64
        ratio = s2 / s0
    }
    if s.kernel == 0usize {
        c = 1.3221f64
        ratio = s2 / s0
    }
    ret c * math.pow[f64](ratio * ratio, qrate) * math.pow[f64](f64(n + s.prewhite), qrate)
}

// the moment covariance at coefficients th (gmm's .weightFct on the centred moments): bwo[0] receives the HAC bandwidth, so the matrix
fn weight_s(s: *Spec, th: []const f64, bwo: []f64, so: []f64) {
    let a = s.a
    let n = s.n
    let q = s.q
    let e = nf(a, n)
    resid(s, th, e)
    if s.vcov == 0usize {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += e[i]
            i += 1usize
        }
        m = m / f64(n)
        var sg = 0.0f64
        i = 0usize
        while i < n {
            sg += (e[i] - m) * (e[i] - m)
            i += 1usize
        }
        sg = sg / f64(n)
        let zz = nf(a, q * q)
        crossp(s.z, s.z, n, q, q, zz)
        i = 0usize
        while i < q * q {
            so[i] = sg * zz[i] / f64(n)
            i += 1usize
        }
        ret
    }
    let g = nf(a, n * q)
    moments(s, e, g)
    center(a, g, n, q)
    if s.vcov == 1usize {
        crossp(g, g, n, q, q, so)
        var i = 0usize
        while i < q * q {
            so[i] = so[i] / f64(n)
            i += 1usize
        }
        ret
    }
    var bw = s.bw
    if s.bwmode == 1usize { bw = bw_andrews(s, g) }
    if s.bwmode == 2usize { bw = bw_neweywest(s, g) }
    bwo[0usize] = bw
    hac_meat(s, g, bw, so)
}

// the criterion gbar' W^-1 gbar of the uncentred moments at th for a covariance smat
fn criterion(s: *Spec, th: []const f64, smat: []const f64) -> f64 {
    let a = s.a
    let q = s.q
    let e = nf(a, s.n)
    resid(s, th, e)
    let g = nf(a, s.n * q)
    moments(s, e, g)
    let gb = nf(a, q)
    colmeans(g, s.n, q, gb)
    let wi = nf(a, q * q)
    if !invert(a, smat, q, wi) { ret nan() }
    var v = 0.0f64
    var i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            v += gb[i] * wi[i * q + j] * gb[j]
            j += 1usize
        }
        i += 1usize
    }
    ret v
}

// the CUE objective at th: the covariance is recomputed at th
fn cue_obj(s: *Spec, th: []const f64) -> f64 {
    let start = mem.mark(s.a)
    let bwo = nf(s.a, 1usize)
    let sm = nf(s.a, s.q * s.q)
    weight_s(s, th, bwo, sm)
    let v = criterion(s, th, sm)
    mem.reset(s.a, start)
    ret v
}

// optim's numerical gradient (central differences, ndeps 1e-3)
fn cue_gr(s: *Spec, th: []const f64, df: []f64) {
    let tmp = nf(s.a, th.len)
    var i = 0usize
    while i < th.len {
        var k = 0usize
        while k < th.len {
            tmp[k] = th[k]
            k += 1usize
        }
        tmp[i] = th[i] + 0.001f64
        let v1 = cue_obj(s, tmp)
        tmp[i] = th[i] - 0.001f64
        let v2 = cue_obj(s, tmp)
        df[i] = (v1 - v2) / 0.002f64
        i += 1usize
    }
}

// one weighted step: the estimate for the covariance smat into par and the criterion at it
fn gmm_est(s: *Spec, xz: []const f64, zy: []const f64, smat: []const f64, par: []f64) -> f64 {
    let a = s.a
    let wi = nf(a, s.q * s.q)
    if !invert(a, smat, s.q, wi) { ret nan() }
    if !gmm_step(a, xz, zy, wi, s.p, s.q, par) { ret nan() }
    ret criterion(s, par, smat)
}

// gmm(y ~ X, ~ Z, ...) for the linear model. opt: 0 type (0 twoStep, 1 iterated, 2 cue), 1 vcov (0 iid, 1 MDS, 2 HAC), 2 kernel (0 QS, 1 Truncated, 2 Bartlett, 3 Parzen, 4 Tukey-Hanning),
// 3 bandwidth (0 fixed, 1 bwAndrews, 2 bwNeweyWest), 4 the fixed bandwidth, 5 prewhite (0 or 1), 6 optim method for cue (0 Nelder-Mead, 1 BFGS), 7 the first instrument is the intercept (1) or not (0).
// out (p + p * p + 4): the coefficients, the covariance, the J statistic, its p-value, the weight's bandwidth (HAC) and the degrees of freedom q - p
fn gmm_fit(a: *mem.Arena, y: []const f64, x: []const f64, z: []const f64, n: usize, p: usize, q: usize, opt: []const f64, out: []f64) -> bool {
    var s = Spec { a: a, y: y, x: x, z: z, n: n, p: p, q: q, vcov: usize(opt[1usize]), kernel: usize(opt[2usize]), bwmode: usize(opt[3usize]), bw: opt[4usize], prewhite: usize(opt[5usize]), zint: opt[7usize] > 0.5f64 }
    let nf_ = f64(n)
    let kind = usize(opt[0usize])
    let xz = nf(a, p * q)
    let zy = nf(a, q)
    let zz = nf(a, q * q)
    let zzi = nf(a, q * q)
    crossp(x, z, n, p, q, xz)
    crossp(z, z, n, q, q, zz)
    var i = 0usize
    while i < q {
        var t = 0.0f64
        var r = 0usize
        while r < n {
            t += z[r * q + i] * y[r]
            r += 1usize
        }
        zy[i] = t
        i += 1usize
    }
    let par = nf(a, p)
    let bwo = nf(a, 1usize)
    bwo[0usize] = nan()
    var bwlast = nan()
    var value = nan()
    let sm = nf(a, q * q)
    if q == p {
        i = 0usize
        while i < q {
            sm[i * q + i] = 1.0f64
            i += 1usize
        }
        value = gmm_est(&s, xz, zy, sm, par)
    } else {
        if !invert(a, zz, q, zzi) { ret false }
        i = 0usize
        while i < q * q {
            zzi[i] = zzi[i] * nf_
            i += 1usize
        }
        if !gmm_step(a, xz, zy, zzi, p, q, par) { ret false }
        if kind == 0usize {
            weight_s(&s, par, bwo, sm)
            bwlast = bwo[0usize]
            let p2 = nf(a, p)
            value = gmm_est(&s, xz, zy, sm, p2)
            i = 0usize
            while i < p {
                par[i] = p2[i]
                i += 1usize
            }
        }
        if kind == 1usize {
            var ch = 100000.0f64
            var it = 1usize
            let tet = nf(a, p)
            while ch > 1.0e-6f64 {
                i = 0usize
                while i < p {
                    tet[i] = par[i]
                    i += 1usize
                }
                weight_s(&s, tet, bwo, sm)
                bwlast = bwo[0usize]
                value = gmm_est(&s, xz, zy, sm, par)
                var t = 0.0f64
                i = 0usize
                while i < p {
                    let r = math.abs[f64](tet[i] - par[i]) / tet[i]
                    t += r * r
                    i += 1usize
                }
                ch = math.sqrt[f64](t)
                if it > 100usize { ch = 1.0e-6f64 }
                it += 1usize
            }
        }
        if kind == 2usize {
            if s.vcov == 2usize {
                weight_s(&s, par, bwo, sm)
                s.bwmode = 0usize
                s.bw = bwo[0usize]
                bwlast = bwo[0usize]
            }
            let xo = nf(a, p)
            if opt[6usize] < 0.5f64 {
                let (fv, cnt, fail) = rn.nmmin[Spec](a, &s, cue_obj, par, 0.0f64 - 1.0e308f64, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, xo)
                value = fv
            } else {
                i = 0usize
                while i < p {
                    xo[i] = par[i]
                    i += 1usize
                }
                value = bf.vmmin[Spec](a, &s, cue_obj, cue_gr, xo, 1.4901161193847656e-08f64, 100usize)
            }
            i = 0usize
            while i < p {
                par[i] = xo[i]
                i += 1usize
            }
        }
    }
    // the covariance at the final coefficients: (G' V^-1 G)^-1 / n with G = -Z'X / n, or G^-1 V G'^-1 / n when just identified
    weight_s(&s, par, bwo, sm)
    let wi = nf(a, q * q)
    let gg = nf(a, q * p)
    i = 0usize
    while i < p {
        var l = 0usize
        while l < q {
            gg[l * p + i] = 0.0f64 - xz[i * q + l] / nf_
            l += 1usize
        }
        i += 1usize
    }
    let vc = nf(a, p * p)
    if q == p {
        let t1 = nf(a, p * p)
        if !invert(a, gg, p, t1) { ret false }
        let t2 = nf(a, p * p)
        let t1t = nf(a, p * p)
        mmul(t1, sm, p, p, p, t2)
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                t1t[i * p + j] = t1[j * p + i]
                j += 1usize
            }
            i += 1usize
        }
        mmul(t2, t1t, p, p, p, vc)
        i = 0usize
        while i < p * p {
            vc[i] = vc[i] / nf_
            i += 1usize
        }
    } else {
        if !invert(a, sm, q, wi) { ret false }
        let t1 = nf(a, q * p)
        mmul(wi, gg, q, q, p, t1)
        let m = nf(a, p * p)
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                var t = 0.0f64
                var l = 0usize
                while l < q {
                    t += gg[l * p + i] * t1[l * p + j]
                    l += 1usize
                }
                m[i * p + j] = t
                j += 1usize
            }
            i += 1usize
        }
        if !invert(a, m, p, vc) { ret false }
        i = 0usize
        while i < p * p {
            vc[i] = vc[i] / nf_
            i += 1usize
        }
    }
    i = 0usize
    while i < p {
        out[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < p * p {
        out[p + i] = vc[i]
        i += 1usize
    }
    let jv = value * nf_
    let df = f64(q) - f64(p)
    out[p + p * p] = jv
    var jp = nan()
    if df > 0.0f64 { jp = nm.pchisq(jv, df, false, false) }
    out[p + p * p + 1usize] = jp
    out[p + p * p + 2usize] = bwlast
    out[p + p * p + 3usize] = df
    ret true
}

// car::linearHypothesis for R b = rhs (m rows) on the coefficients and covariance of gmm_fit: res receives the chi-square statistic, its p-value, the F statistic (statistic / m) and its p-value on m and dfres degrees of freedom
fn wald_test(a: *mem.Arena, coef: []const f64, vc: []const f64, p: usize, rm: []const f64, rhs: []const f64, m: usize, dfres: f64, res: []f64) -> bool {
    let d = nf(a, m)
    var i = 0usize
    while i < m {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            t += rm[i * p + j] * coef[j]
            j += 1usize
        }
        d[i] = t - rhs[i]
        i += 1usize
    }
    let rv = nf(a, m * p)
    mmul(rm, vc, m, p, p, rv)
    let vm = nf(a, m * m)
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var t = 0.0f64
            var l = 0usize
            while l < p {
                t += rv[i * p + l] * rm[j * p + l]
                l += 1usize
            }
            vm[i * m + j] = t
            j += 1usize
        }
        i += 1usize
    }
    let vi = nf(a, m * m)
    if !invert(a, vm, m, vi) { ret false }
    var w = 0.0f64
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            w += d[i] * vi[i * m + j] * d[j]
            j += 1usize
        }
        i += 1usize
    }
    res[0usize] = w
    res[1usize] = nm.pchisq(w, f64(m), false, false)
    res[2usize] = w / f64(m)
    res[3usize] = nb.pf(w / f64(m), f64(m), dfres, false, false)
    ret true
}
