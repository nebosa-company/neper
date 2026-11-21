// R lme4 lmer for one random intercept: y = X beta + b[group] + e, b ~ N(0, sigma_b^2), e ~ N(0, sigma^2), fitted by REML or maximum likelihood.
//
// The deviance is profiled over theta = sigma_b / sigma (every other parameter is a closed form of it) and minimised with R's Brent search; the group block of V / sigma^2 = I + theta^2 1 1'
// inverts as I - theta^2 / (1 + n_g theta^2) 1 1', so nothing larger than the p by p fixed-effect system is ever solved.
//
// Not here: crossed and nested random effects, random slopes, glmer (Laplace and Gauss-Hermite), lmerTest, predict and simulate.

use e.algo.stat.bayesmpkg as bz
use e.algo.stat.ica as ica
use e.algo.stat.fdrtool as fd
use e.math
use e.math.nmath as nmx
use e.math.nmath_beta as nb
use e.mem

type Lmm = struct { n: usize, p: usize, ng: usize, reml: bool, x: []const f64, y: []const f64, g: []const usize, cnt: []f64, w: []f64, xtvx: []f64, xtvy: []f64, beta: []f64, u: []f64, uinv: []f64, tv: []f64, r2: f64, logdet: f64 }

// the profiled quantities at theta: fills beta, r2 (the weighted residual sum of squares) and the log determinants; returns the deviance
fn lmm_profile(c: *Lmm, theta: f64) -> f64 {
    let n = c.n
    let p = c.p
    let t2 = theta * theta
    var logv = 0.0f64
    var k = 0usize
    while k < c.ng {
        logv += math.log[f64](1.0f64 + c.cnt[k] * t2)
        c.w[k] = t2 / (1.0f64 + c.cnt[k] * t2)
        k += 1usize
    }
    // group sums of x and y
    var j = 0usize
    while j < p {
        var j2 = 0usize
        while j2 < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += c.x[j * n + i] * c.x[j2 * n + i]
                i += 1usize
            }
            c.xtvx[j2 * p + j] = s
            j2 += 1usize
        }
        var sy = 0.0f64
        var i = 0usize
        while i < n {
            sy += c.x[j * n + i] * c.y[i]
            i += 1usize
        }
        c.xtvy[j] = sy
        j += 1usize
    }
    // subtract the group-mean part: X'V^-1 X = X'X - sum_g w_g (sum x)(sum x)'
    k = 0usize
    while k < c.ng {
        j = 0usize
        while j < p {
            var sxj = 0.0f64
            var syk = 0.0f64
            var i = 0usize
            while i < n {
                if c.g[i] == k {
                    sxj += c.x[j * n + i]
                    syk += c.y[i]
                }
                i += 1usize
            }
            var j2 = 0usize
            while j2 < p {
                var sxj2 = 0.0f64
                i = 0usize
                while i < n {
                    if c.g[i] == k { sxj2 += c.x[j2 * n + i] }
                    i += 1usize
                }
                c.xtvx[j2 * p + j] -= c.w[k] * sxj * sxj2
                j2 += 1usize
            }
            c.xtvy[j] -= c.w[k] * sxj * syk
            j += 1usize
        }
        k += 1usize
    }
    if !bz.chol_upper(c.xtvx, p, c.u) { ret 1.0e300f64 }
    bz.inv_upper(c.u, p, c.uinv)
    // beta = (X'V^-1 X)^-1 X'V^-1 y = Ui (Ui' xtvy), Ui upper triangular stored column-major
    j = 0usize
    while j < p {
        var t = 0.0f64
        var q = 0usize
        while q <= j {
            t += c.uinv[j * p + q] * c.xtvy[q]
            q += 1usize
        }
        c.tv[j] = t
        j += 1usize
    }
    var q2 = 0usize
    while q2 < p {
        var bsum = 0.0f64
        j = q2
        while j < p {
            bsum += c.uinv[j * p + q2] * c.tv[j]
            j += 1usize
        }
        c.beta[q2] = bsum
        q2 += 1usize
    }
    // the residual quadratic form r' V^-1 r
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        var f = 0.0f64
        j = 0usize
        while j < p {
            f += c.x[j * n + i] * c.beta[j]
            j += 1usize
        }
        let r = c.y[i] - f
        rss += r * r
        i += 1usize
    }
    k = 0usize
    while k < c.ng {
        var sr = 0.0f64
        i = 0usize
        while i < n {
            if c.g[i] == k {
                var f = 0.0f64
                j = 0usize
                while j < p {
                    f += c.x[j * n + i] * c.beta[j]
                    j += 1usize
                }
                sr += c.y[i] - f
            }
            i += 1usize
        }
        rss -= c.w[k] * sr * sr
        k += 1usize
    }
    c.r2 = rss
    c.logdet = logv
    var ldx = 0.0f64
    j = 0usize
    while j < p {
        ldx += 2.0f64 * math.log[f64](c.u[j * p + j])
        j += 1usize
    }
    let two_pi = 6.283185307179586f64
    if c.reml {
        let nm = f64(n - p)
        ret logv + ldx + nm * (1.0f64 + math.log[f64](two_pi * rss / nm))
    }
    ret logv + f64(n) * (1.0f64 + math.log[f64](two_pi * rss / f64(n)))
}

fn lmm_obj(c: *Lmm, theta: f64) -> f64 { ret lmm_profile(c, theta) }

// lmer(y ~ X - 1 + (1 | group), REML = reml): out = (deviance, theta, sigma, sigma_b); beta receives the fixed effects (x is n by p column-major, group codes 0 .. ng - 1) and ranef the conditional modes
fn lmer_ri(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, beta: []f64, ranef: []f64, out: []f64) -> err {
    let (cnt, e1) = mem.alloc[f64](a, ng)
    let (w, e2) = mem.alloc[f64](a, ng)
    let (xtvx, e3) = mem.alloc[f64](a, p * p)
    let (xtvy, e4) = mem.alloc[f64](a, p)
    let (u, e5) = mem.alloc[f64](a, p * p)
    let (uinv, e6) = mem.alloc[f64](a, p * p)
    let (tv, e7) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var k = 0usize
    while k < ng {
        cnt[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < n {
        cnt[g[i]] += 1.0f64
        i += 1usize
    }
    var c = Lmm{ n: n, p: p, ng: ng, reml: reml, x: x, y: y, g: g, cnt: cnt, w: w, xtvx: xtvx, xtvy: xtvy, beta: beta, u: u, uinv: uinv, tv: tv, r2: 0.0f64, logdet: 0.0f64 }
    let theta = fd.brent_min_tol[Lmm](&c, lmm_obj, 0.0f64, 30.0f64, 1.0e-10f64)
    var th = theta
    // lme4 bounds theta at zero: a fit at the boundary is reported there
    let dev0 = lmm_profile(&c, 0.0f64)
    let dev1 = lmm_profile(&c, th)
    if dev0 <= dev1 { th = 0.0f64 }
    let dev = lmm_profile(&c, th)
    var df = f64(n)
    if reml { df = f64(n - p) }
    let sigma2 = c.r2 / df
    out[0usize] = dev
    out[1usize] = th
    out[2usize] = math.sqrt[f64](sigma2)
    out[3usize] = th * math.sqrt[f64](sigma2)
    // conditional modes b_g = theta^2 / (1 + n_g theta^2) sum of the group residuals
    k = 0usize
    while k < ng {
        var sr = 0.0f64
        i = 0usize
        while i < n {
            if g[i] == k {
                var f = 0.0f64
                var j = 0usize
                while j < p {
                    f += x[j * n + i] * beta[j]
                    j += 1usize
                }
                sr += y[i] - f
            }
            i += 1usize
        }
        ranef[k] = th * th / (1.0f64 + cnt[k] * th * th) * sr
        k += 1usize
    }
    ret ok
}

// the deviance as a function of (theta, sigma) with the fixed effects profiled out: the REML criterion (reml) or the ML deviance
fn lmm_dev2(c: *Lmm, theta: f64, sigma: f64) -> f64 {
    let _ = lmm_profile(c, theta)
    var ldx = 0.0f64
    var j = 0usize
    while j < c.p {
        ldx += 2.0f64 * math.log[f64](c.u[j * c.p + j])
        j += 1usize
    }
    let two_pi = 6.283185307179586f64
    var dfn = f64(c.n)
    if c.reml {
        dfn = f64(c.n - c.p)
        ret c.logdet + ldx + dfn * math.log[f64](two_pi * sigma * sigma) + c.r2 / (sigma * sigma)
    }
    ret c.logdet + dfn * math.log[f64](two_pi * sigma * sigma) + c.r2 / (sigma * sigma)
}

// zeroed f64 storage from the arena (mem.alloc does not clear)
fn lmt_alloc(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (b, e) = mem.alloc[f64](a, n)
    if e != ok { ret (b, e) }
    var i = 0usize
    while i < n {
        b[i] = 0.0f64
        i += 1usize
    }
    ret (b, ok)
}

// the profiling state for one model
fn lmm_new(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool) -> (Lmm, err) {
    var none: Lmm = zero
    let (cnt, e1) = lmt_alloc(a, ng)
    let (w, e2) = lmt_alloc(a, ng)
    let (xtvx, e3) = lmt_alloc(a, p * p)
    let (xtvy, e4) = lmt_alloc(a, p)
    let (u, e5) = lmt_alloc(a, p * p)
    let (uinv, e6) = lmt_alloc(a, p * p)
    let (tv, e7) = lmt_alloc(a, p)
    let (beta, e8) = lmt_alloc(a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (none, mem.Full) }
    var i = 0usize
    while i < n {
        cnt[g[i]] += 1.0f64
        i += 1usize
    }
    ret (Lmm{ n: n, p: p, ng: ng, reml: reml, x: x, y: y, g: g, cnt: cnt, w: w, xtvx: xtvx, xtvy: xtvy, beta: beta, u: u, uinv: uinv, tv: tv, r2: 0.0f64, logdet: 0.0f64 }, ok)
}

// row-major products: o (m by nc) = x (m by k) y (k by nc); lmt_mmt: x y' with y nc by k; lmt_tmm: x' y with x k by m
fn lmt_mm(o: []f64, x: []const f64, y: []const f64, m: usize, k: usize, nc: usize) {
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < nc {
            var s = 0.0f64
            var q = 0usize
            while q < k {
                s += x[i * k + q] * y[q * nc + j]
                q += 1usize
            }
            o[i * nc + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

fn lmt_mmt(o: []f64, x: []const f64, y: []const f64, m: usize, k: usize, nc: usize) {
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < nc {
            var s = 0.0f64
            var q = 0usize
            while q < k {
                s += x[i * k + q] * y[j * k + q]
                q += 1usize
            }
            o[i * nc + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

fn lmt_tmm(o: []f64, x: []const f64, y: []const f64, m: usize, k: usize, nc: usize) {
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < nc {
            var s = 0.0f64
            var q = 0usize
            while q < k {
                s += x[q * m + i] * y[q * nc + j]
                q += 1usize
            }
            o[i * nc + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// inverse of the q by q row-major m by Gauss-Jordan with partial pivoting; false when singular
fn lmt_inv(a: *mem.Arena, m: []const f64, q: usize, out: []f64) -> bool {
    let (w, e) = lmt_alloc(a, q * 2usize * q)
    if e != ok { ret false }
    let q2 = 2usize * q
    var i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            w[i * q2 + j] = m[i * q + j]
            j += 1usize
        }
        w[i * q2 + q + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < q {
        var piv = c
        var r = c + 1usize
        while r < q {
            if math.abs[f64](w[r * q2 + c]) > math.abs[f64](w[piv * q2 + c]) { piv = r }
            r += 1usize
        }
        if w[piv * q2 + c] == 0.0f64 { ret false }
        if piv != c {
            var j = 0usize
            while j < q2 {
                let tmp = w[c * q2 + j]
                w[c * q2 + j] = w[piv * q2 + j]
                w[piv * q2 + j] = tmp
                j += 1usize
            }
        }
        let d = w[c * q2 + c]
        var j = 0usize
        while j < q2 {
            w[c * q2 + j] = w[c * q2 + j] / d
            j += 1usize
        }
        r = 0usize
        while r < q {
            if r != c {
                let f = w[r * q2 + c]
                j = 0usize
                while j < q2 {
                    w[r * q2 + j] -= f * w[c * q2 + j]
                    j += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            out[i * q + j] = w[i * q2 + q + j]
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// numDeriv's Richardson extrapolation of r columns held in d (v = 2): the 4^m pass of genD and jacobian
fn lmt_rich(d: []f64, r: usize) {
    var m = 1usize
    var pw = 4.0f64
    while m < r {
        var k = 0usize
        while k < r - m {
            d[k] = (d[k + 1usize] * pw - d[k]) / (pw - 1.0f64)
            k += 1usize
        }
        pw *= 4.0f64
        m += 1usize
    }
}

// numDeriv's initial step abs(d x) + eps (abs(x) < zero.tol), eps = 1e-4
fn lmt_h0(d: f64, x: f64) -> f64 {
    let ax = math.abs[f64](x)
    var h = d * ax
    if ax < math.sqrt[f64](2.220446049250313e-16f64 / 7.0e-7f64) { h += 0.0001f64 }
    ret h
}

// numDeriv::hessian (Richardson, d = 0.1, r = 4) of the deviance in (theta, sigma): out = row-major 2 by 2
fn lmt_hess(c: *Lmm, x0: f64, x1: f64, out: []f64, da: []f64, ha: []f64) {
    let f0 = lmm_dev2(c, x0, x1)
    let hs0 = lmt_h0(0.1f64, x0)
    let hs1 = lmt_h0(0.1f64, x1)
    var hd0 = 0.0f64
    var hd1 = 0.0f64
    var i = 0usize
    while i < 2usize {
        var h = hs0
        if i == 1usize { h = hs1 }
        var k = 0usize
        while k < 4usize {
            var f1 = 0.0f64
            var f2 = 0.0f64
            if i == 0usize {
                f1 = lmm_dev2(c, x0 + h, x1)
                f2 = lmm_dev2(c, x0 - h, x1)
            } else {
                f1 = lmm_dev2(c, x0, x1 + h)
                f2 = lmm_dev2(c, x0, x1 - h)
            }
            ha[k] = (f1 - 2.0f64 * f0 + f2) / (h * h)
            h = h / 2.0f64
            k += 1usize
        }
        lmt_rich(ha, 4usize)
        if i == 0usize {
            hd0 = ha[0usize]
        } else {
            hd1 = ha[0usize]
        }
        i += 1usize
    }
    var hx = hs0
    var hy = hs1
    var k = 0usize
    while k < 4usize {
        let f1 = lmm_dev2(c, x0 + hx, x1 + hy)
        let f2 = lmm_dev2(c, x0 - hx, x1 - hy)
        da[k] = (f1 - 2.0f64 * f0 + f2 - hd1 * hy * hy - hd0 * hx * hx) / (2.0f64 * hx * hy)
        hx = hx / 2.0f64
        hy = hy / 2.0f64
        k += 1usize
    }
    lmt_rich(da, 4usize)
    out[0usize] = hd0
    out[1usize] = da[0usize]
    out[2usize] = da[0usize]
    out[3usize] = hd1
}

// vcov(beta) = sigma^2 (X' V^-1 X)^-1 at (theta, sigma), row-major p by p
fn lmt_covb(c: *Lmm, theta: f64, sigma: f64, out: []f64) {
    let p = c.p
    let _ = lmm_profile(c, theta)
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var q = i
            if j > i { q = j }
            while q < p {
                s += c.uinv[q * p + i] * c.uinv[q * p + j]
                q += 1usize
            }
            out[i * p + j] = sigma * sigma * s
            j += 1usize
        }
        i += 1usize
    }
}

// numDeriv::jacobian (Richardson, d = 1e-4, r = 4) of vcov(beta) in (theta, sigma): jac[i * p * p + e] is the derivative of entry e by parameter i
fn lmt_jac(c: *Lmm, x0: f64, x1: f64, p: usize, jac: []f64, aw: []f64, plus: []f64, minus: []f64) {
    let pp = p * p
    var i = 0usize
    while i < 2usize {
        var xv = x0
        if i == 1usize { xv = x1 }
        var h = lmt_h0(0.0001f64, xv)
        var k = 0usize
        while k < 4usize {
            if i == 0usize {
                lmt_covb(c, x0 + h, x1, plus)
                lmt_covb(c, x0 - h, x1, minus)
            } else {
                lmt_covb(c, x0, x1 + h, plus)
                lmt_covb(c, x0, x1 - h, minus)
            }
            var e = 0usize
            while e < pp {
                aw[k * pp + e] = (plus[e] - minus[e]) / (2.0f64 * h)
                e += 1usize
            }
            h = h / 2.0f64
            k += 1usize
        }
        var m = 1usize
        var pw = 4.0f64
        while m < 4usize {
            k = 0usize
            while k < 4usize - m {
                var e = 0usize
                while e < pp {
                    aw[k * pp + e] = (aw[(k + 1usize) * pp + e] * pw - aw[k * pp + e]) / (pw - 1.0f64)
                    e += 1usize
                }
                k += 1usize
            }
            pw *= 4.0f64
            m += 1usize
        }
        var e = 0usize
        while e < pp {
            jac[i * pp + e] = aw[e]
            e += 1usize
        }
        i += 1usize
    }
}

// what lmerTest keeps of a fit: the fixed effects, vcov(beta), the Jacobian of vcov(beta) in (theta, sigma), the covariance of (theta, sigma) (2 H^-1) and, for REML fits on request,
// pbkrtest's adjusted covariance, its P matrices and W
type LmT = struct { p: usize, sigma: f64, beta: []f64, covb: []f64, jac: []f64, vv: []f64, padj: []f64, pk: []f64, ww: []f64 }

fn lmt_make(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, kr: bool) -> (LmT, err) {
    var none: LmT = zero
    let (c0, ce) = lmm_new(a, x, y, g, n, p, ng, reml)
    if ce != ok { ret (none, ce) }
    var c = c0
    let pp = p * p
    let (beta, e1) = lmt_alloc(a, p)
    let (covb, e2) = lmt_alloc(a, pp)
    let (jac, e3) = lmt_alloc(a, 2usize * pp)
    let (vv, e4) = lmt_alloc(a, 4usize)
    let (padj, e5) = lmt_alloc(a, pp)
    let (pk, e6) = lmt_alloc(a, 2usize * pp)
    let (ww, e7) = lmt_alloc(a, 4usize)
    let (hh, e8) = lmt_alloc(a, 4usize)
    let (aw, e9) = lmt_alloc(a, 4usize * pp)
    let (plus, e10) = lmt_alloc(a, pp)
    let (minus, e11) = lmt_alloc(a, pp)
    let (da, e12) = lmt_alloc(a, 4usize)
    let (ha, e13) = lmt_alloc(a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret (none, mem.Full) }
    lmt_hess(&c, theta, sigma, hh, da, ha)
    let (ev, vecs, ee) = ica.eigen_sym(a, hh, 2usize)
    if ee != ok { ret (none, ee) }
    var m = 0usize
    while m < 2usize {
        if ev[m] > 0.00000001f64 {
            var i = 0usize
            while i < 2usize {
                var j = 0usize
                while j < 2usize {
                    vv[i * 2usize + j] += 2.0f64 * vecs[i * 2usize + m] * vecs[j * 2usize + m] / ev[m]
                    j += 1usize
                }
                i += 1usize
            }
        }
        m += 1usize
    }
    let _ = lmm_profile(&c, theta)
    var j = 0usize
    while j < p {
        beta[j] = c.beta[j]
        j += 1usize
    }
    lmt_covb(&c, theta, sigma, covb)
    lmt_jac(&c, theta, sigma, p, jac, aw, plus, minus)
    var t = LmT{ p: p, sigma: sigma, beta: beta, covb: covb, jac: jac, vv: vv, padj: padj, pk: pk, ww: ww }
    if kr {
        let ek = lmt_kr(a, &c, theta, sigma, &t)
        if ek != ok { ret (none, ek) }
    }
    ret (t, ok)
}

// pbkrtest's vcovAdj for the one-intercept model: Sigma = sigma_b^2 G1 + sigma^2 I with G1 the group indicator blocks. Dense n by n; everything else is p by p
fn lmt_kr(a: *mem.Arena, c: *Lmm, theta: f64, sigma: f64, t: *LmT) -> err {
    let n = c.n
    let p = c.p
    let pp = p * p
    let s2 = sigma * sigma
    let t2 = theta * theta
    let _ = lmm_profile(c, theta)
    let (si, e1) = lmt_alloc(a, n * n)
    let (h1, e2) = lmt_alloc(a, n * n)
    let (xm, e3) = lmt_alloc(a, n * p)
    let (tt, e4) = lmt_alloc(a, n * p)
    let (o1, e5) = lmt_alloc(a, n * p)
    let (s1, e6) = lmt_alloc(a, n * p)
    let (s2m, e7) = lmt_alloc(a, n * p)
    let (p1, e8) = lmt_alloc(a, pp)
    let (p2, e9) = lmt_alloc(a, pp)
    let (q11, e10) = lmt_alloc(a, pp)
    let (q12, e11) = lmt_alloc(a, pp)
    let (q22, e12) = lmt_alloc(a, pp)
    let (m1, e13) = lmt_alloc(a, pp)
    let (m2, e14) = lmt_alloc(a, pp)
    let (m3, e15) = lmt_alloc(a, pp)
    let (uu, e16) = lmt_alloc(a, pp)
    let (ie2, e17) = lmt_alloc(a, 4usize)
    let (ie2i, e18) = lmt_alloc(a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            xm[i * p + j] = c.x[j * n + i]
            j += 1usize
        }
        var k = 0usize
        while k < n {
            if c.g[i] == c.g[k] {
                var v = 0.0f64 - c.w[c.g[i]] / s2
                if i == k { v += 1.0f64 / s2 }
                si[i * n + k] = v
                h1[i * n + k] = 1.0f64 / (s2 * (1.0f64 + c.cnt[c.g[i]] * t2))
            }
            k += 1usize
        }
        i += 1usize
    }
    lmt_mm(tt, si, xm, n, n, p)
    lmt_mm(o1, h1, xm, n, n, p)
    lmt_mm(s1, si, o1, n, n, p)
    lmt_mm(s2m, si, tt, n, n, p)
    lmt_tmm(p1, o1, tt, p, n, p)
    lmt_tmm(p2, tt, tt, p, n, p)
    i = 0usize
    while i < pp {
        p1[i] = 0.0f64 - p1[i]
        p2[i] = 0.0f64 - p2[i]
        i += 1usize
    }
    lmt_tmm(q11, o1, s1, p, n, p)
    lmt_tmm(q12, o1, s2m, p, n, p)
    lmt_tmm(q22, tt, s2m, p, n, p)
    // Ktrace[r, s] = sum over i, k of H_r[k, i] H_s[i, k]
    var k11 = 0.0f64
    var k12 = 0.0f64
    var k22 = 0.0f64
    i = 0usize
    while i < n {
        var k = 0usize
        while k < n {
            k11 += h1[k * n + i] * h1[i * n + k]
            k12 += h1[k * n + i] * si[i * n + k]
            k22 += si[k * n + i] * si[i * n + k]
            k += 1usize
        }
        i += 1usize
    }
    let phi = t.covb
    // IE2[r, s] = Ktrace - 2 sum(Phi * Q_rs) + sum((Phi P_r) * (P_s Phi))
    var r = 0usize
    while r < 2usize {
        var s = r
        while s < 2usize {
            var pr = p1
            if r == 1usize { pr = p2 }
            var ps = p1
            if s == 1usize { ps = p2 }
            var qrs = q11
            if r == 0usize && s == 1usize { qrs = q12 }
            if r == 1usize { qrs = q22 }
            var kt = k11
            if r == 0usize && s == 1usize { kt = k12 }
            if r == 1usize { kt = k22 }
            lmt_mm(m1, phi, pr, p, p, p)
            lmt_mm(m2, ps, phi, p, p, p)
            var sq = 0.0f64
            var sp = 0.0f64
            i = 0usize
            while i < pp {
                sq += phi[i] * qrs[i]
                sp += m1[i] * m2[i]
                i += 1usize
            }
            let v = kt - 2.0f64 * sq + sp
            ie2[r * 2usize + s] = v
            ie2[s * 2usize + r] = v
            s += 1usize
        }
        r += 1usize
    }
    if !lmt_inv(a, ie2, 2usize, ie2i) { ret mem.Full }
    i = 0usize
    while i < 4usize {
        t.ww[i] = 2.0f64 * ie2i[i]
        i += 1usize
    }
    // UU = W12 (Q12 - P1 Phi P2) + its transpose, plus W11 (Q11 - P1 Phi P1) + W22 (Q22 - P2 Phi P2)
    lmt_mm(m1, p1, phi, p, p, p)
    lmt_mm(m2, m1, p2, p, p, p)
    i = 0usize
    while i < pp {
        m3[i] = t.ww[1usize] * (q12[i] - m2[i])
        i += 1usize
    }
    var a1 = 0usize
    while a1 < p {
        var b1 = 0usize
        while b1 < p {
            uu[a1 * p + b1] = m3[a1 * p + b1] + m3[b1 * p + a1]
            b1 += 1usize
        }
        a1 += 1usize
    }
    lmt_mm(m2, m1, p1, p, p, p)
    i = 0usize
    while i < pp {
        uu[i] += t.ww[0usize] * (q11[i] - m2[i])
        i += 1usize
    }
    lmt_mm(m1, p2, phi, p, p, p)
    lmt_mm(m2, m1, p2, p, p, p)
    i = 0usize
    while i < pp {
        uu[i] += t.ww[3usize] * (q22[i] - m2[i])
        i += 1usize
    }
    lmt_mm(m1, phi, uu, p, p, p)
    lmt_mm(m2, m1, phi, p, p, p)
    i = 0usize
    while i < pp {
        t.padj[i] = phi[i] + 2.0f64 * m2[i]
        t.pk[i] = p1[i]
        t.pk[pp + i] = p2[i]
        i += 1usize
    }
    ret ok
}

// pbkrtest's .KR_adjust for the q by p contrast lmat: res = (unscaled F, F scaling, denominator df, variance L PhiA L' (q = 1 only))
fn lmt_krf(a: *mem.Arena, t: *LmT, lmat: []const f64, q: usize, res: []f64) -> err {
    let p = t.p
    let pp = p * p
    let (tmp1, e1) = lmt_alloc(a, q * p)
    let (lpl, e2) = lmt_alloc(a, q * q)
    let (il, e3) = lmt_alloc(a, q * q)
    let (s1, e4) = lmt_alloc(a, q * p)
    let (th, e5) = lmt_alloc(a, pp)
    let (thphi, e6) = lmt_alloc(a, pp)
    let (u0, e7) = lmt_alloc(a, pp)
    let (u1, e8) = lmt_alloc(a, pp)
    let (m1, e9) = lmt_alloc(a, pp)
    let (lpa, e10) = lmt_alloc(a, q * q)
    let (ilpa, e11) = lmt_alloc(a, q * q)
    let (lb, e12) = lmt_alloc(a, q)
    let (tq, e13) = lmt_alloc(a, q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    lmt_mm(tmp1, lmat, t.covb, q, p, p)
    lmt_mmt(lpl, tmp1, lmat, q, p, q)
    if !lmt_inv(a, lpl, q, il) { ret mem.Full }
    lmt_mm(s1, il, lmat, q, q, p)
    lmt_tmm(th, lmat, s1, p, q, p)
    lmt_mm(thphi, th, t.covb, p, p, p)
    lmt_mm(m1, thphi, t.pk[0usize..pp], p, p, p)
    lmt_mm(u0, m1, t.covb, p, p, p)
    lmt_mm(m1, thphi, t.pk[pp..2usize * pp], p, p, p)
    lmt_mm(u1, m1, t.covb, p, p, p)
    var a1 = 0.0f64
    var a2 = 0.0f64
    var ii = 0usize
    while ii < 2usize {
        var jj = ii
        while jj < 2usize {
            var e = 2.0f64
            if ii == jj { e = 1.0f64 }
            var ui = u0
            if ii == 1usize { ui = u1 }
            var uj = u0
            if jj == 1usize { uj = u1 }
            var tri = 0.0f64
            var trj = 0.0f64
            var sx = 0.0f64
            var r = 0usize
            while r < p {
                tri += ui[r * p + r]
                trj += uj[r * p + r]
                var c = 0usize
                while c < p {
                    sx += ui[r * p + c] * uj[c * p + r]
                    c += 1usize
                }
                r += 1usize
            }
            a1 += e * t.ww[ii * 2usize + jj] * tri * trj
            a2 += e * t.ww[ii * 2usize + jj] * sx
            jj += 1usize
        }
        ii += 1usize
    }
    let qf = f64(q)
    let bb = (1.0f64 / (2.0f64 * qf)) * (a1 + 6.0f64 * a2)
    let gg = ((qf + 1.0f64) * a1 - (qf + 4.0f64) * a2) / ((qf + 2.0f64) * a2)
    let den = 3.0f64 * qf + 2.0f64 * (1.0f64 - gg)
    let c1 = gg / den
    let c2 = (qf - gg) / den
    let c3 = (qf + 2.0f64 - gg) / den
    var v0 = 1.0f64 + c1 * bb
    let v1 = 1.0f64 - c2 * bb
    let v2 = 1.0f64 - c3 * bb
    if math.abs[f64](v0) < 0.0000000001f64 { v0 = 0.0f64 }
    let xr = 1.0f64 - a2 / qf
    var dz = xr / v1
    if math.abs[f64](xr) < 0.00000000000001f64 && math.abs[f64](v1) < 0.00000000000001f64 { dz = 1.0f64 }
    let rho = 1.0f64 / qf * dz * dz * v0 / v2
    let df2 = 4.0f64 + (qf + 2.0f64) / (qf * rho - 1.0f64)
    var fsc = df2 * (1.0f64 - a2 / qf) / (df2 - 2.0f64)
    if math.abs[f64](df2 - 2.0f64) < 0.01f64 { fsc = 1.0f64 }
    // Wald statistic with the adjusted covariance
    lmt_mm(tmp1, lmat, t.padj, q, p, p)
    lmt_mmt(lpa, tmp1, lmat, q, p, q)
    if !lmt_inv(a, lpa, q, ilpa) { ret mem.Full }
    var i = 0usize
    while i < q {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            s += lmat[i * p + j] * t.beta[j]
            j += 1usize
        }
        lb[i] = s
        i += 1usize
    }
    lmt_mm(tq, ilpa, lb, q, q, 1usize)
    var wald = 0.0f64
    i = 0usize
    while i < q {
        wald += lb[i] * tq[i]
        i += 1usize
    }
    res[0usize] = wald / qf
    res[1usize] = fsc
    res[2usize] = df2
    res[3usize] = lpa[0usize]
    ret ok
}

fn lmt_qf(l: []const f64, m: []const f64, p: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            s += l[i] * m[i * p + j] * l[j]
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// lmerTest's contest1D for the contrast L' beta (Satterthwaite or, with kr, Kenward-Roger): out = (estimate, standard error, df, t value, p value)
fn lmt_1d(a: *mem.Arena, t: *LmT, lv: []const f64, kr: bool, out: []f64) -> err {
    let p = t.p
    let pp = p * p
    var est = 0.0f64
    var j = 0usize
    while j < p {
        est += lv[j] * t.beta[j]
        j += 1usize
    }
    var v = lmt_qf(lv, t.covb, p)
    var df = 0.0f64
    if kr {
        let (res, er) = lmt_alloc(a, 4usize)
        if er != ok { ret er }
        let ek = lmt_krf(a, t, lv, 1usize, res)
        if ek != ok { ret ek }
        v = res[3usize]
        df = res[2usize]
    } else {
        let g0 = lmt_qf(lv, t.jac[0usize..pp], p)
        let g1 = lmt_qf(lv, t.jac[pp..2usize * pp], p)
        let sd = g0 * g0 * t.vv[0usize] + 2.0f64 * g0 * g1 * t.vv[1usize] + g1 * g1 * t.vv[3usize]
        df = 2.0f64 * v * v / sd
    }
    let se = math.sqrt[f64](v)
    out[0usize] = est
    out[1usize] = se
    out[2usize] = df
    out[3usize] = est / se
    out[4usize] = 2.0f64 * nb.pt(math.abs[f64](est / se), df, false, false)
    ret ok
}

// lmerTest's contestMD for the q by p contrast lmat: out = (Sum Sq, Mean Sq, NumDF, DenDF, F value, p value)
fn lmt_md(a: *mem.Arena, t: *LmT, lmat: []const f64, q: usize, kr: bool, out: []f64) -> err {
    let p = t.p
    let pp = p * p
    let sg2 = t.sigma * t.sigma
    let nan = 0.0f64 / 0.0f64
    if kr {
        let (res, er) = lmt_alloc(a, 4usize)
        if er != ok { ret er }
        let ek = lmt_krf(a, t, lmat, q, res)
        if ek != ok { ret ek }
        let qf = f64(q)
        let ms = res[0usize] * sg2
        let fs = res[0usize] * res[1usize]
        out[0usize] = ms * qf
        out[1usize] = ms
        out[2usize] = qf
        out[3usize] = res[2usize]
        out[4usize] = fs
        out[5usize] = nb.pf(fs, qf, res[2usize], false, false)
        ret ok
    }
    let (o1, e0) = lmt_alloc(a, 5usize)
    if e0 != ok { ret e0 }
    if q == 1usize {
        let e1 = lmt_1d(a, t, lmat, false, o1)
        if e1 != ok { ret e1 }
        let f1 = o1[3usize] * o1[3usize]
        out[0usize] = f1 * sg2
        out[1usize] = f1 * sg2
        out[2usize] = 1.0f64
        out[3usize] = o1[2usize]
        out[4usize] = f1
        out[5usize] = nb.pf(f1, 1.0f64, o1[2usize], false, false)
        ret ok
    }
    let (tmp1, e2) = lmt_alloc(a, q * p)
    let (vl, e3) = lmt_alloc(a, q * q)
    let (ptl, e4) = lmt_alloc(a, q * p)
    let (nu, e5) = lmt_alloc(a, q)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    lmt_mm(tmp1, lmat, t.covb, q, p, p)
    lmt_mmt(vl, tmp1, lmat, q, p, q)
    let (ev, vecs, ee) = ica.eigen_sym(a, vl, q)
    if ee != ok { ret ee }
    var tol = 0.000000014901161193847656f64 * ev[0usize]
    if tol < 0.0f64 { tol = 0.0f64 }
    var qq = 0usize
    while qq < q && ev[qq] > tol { qq += 1usize }
    if qq == 0usize {
        var z = 0usize
        while z < 6usize {
            out[z] = nan
            z += 1usize
        }
        ret ok
    }
    var m = 0usize
    while m < qq {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var r = 0usize
            while r < q {
                s += vecs[r * q + m] * lmat[r * p + k]
                r += 1usize
            }
            ptl[m * p + k] = s
            k += 1usize
        }
        m += 1usize
    }
    if qq == 1usize {
        let e7 = lmt_1d(a, t, ptl[0usize..p], false, o1)
        if e7 != ok { ret e7 }
        let f1 = o1[3usize] * o1[3usize]
        out[0usize] = f1 * sg2
        out[1usize] = f1 * sg2
        out[2usize] = 1.0f64
        out[3usize] = o1[2usize]
        out[4usize] = f1
        out[5usize] = nb.pf(f1, 1.0f64, o1[2usize], false, false)
        ret ok
    }
    var fsum = 0.0f64
    m = 0usize
    while m < qq {
        var bt = 0.0f64
        var k = 0usize
        while k < p {
            bt += ptl[m * p + k] * t.beta[k]
            k += 1usize
        }
        fsum += bt * bt / ev[m]
        let g0 = lmt_qf(ptl[m * p..m * p + p], t.jac[0usize..pp], p)
        let g1 = lmt_qf(ptl[m * p..m * p + p], t.jac[pp..2usize * pp], p)
        nu[m] = 2.0f64 * ev[m] * ev[m] / (g0 * g0 * t.vv[0usize] + 2.0f64 * g0 * g1 * t.vv[1usize] + g1 * g1 * t.vv[3usize])
        m += 1usize
    }
    let qf = f64(qq)
    let fv = fsum / qf
    // get_Fstat_ddf: equal nu give their mean, any nu <= 2 gives 2, otherwise 2 E / (E - q) with E = sum nu / (nu - 2)
    var same = true
    m = 1usize
    while m < qq {
        if math.abs[f64](nu[m] - nu[m - 1usize]) >= 0.00000001f64 { same = false }
        m += 1usize
    }
    var dd = 0.0f64
    if same {
        m = 0usize
        while m < qq {
            dd += nu[m]
            m += 1usize
        }
        dd = dd / qf
    } else {
        var small = false
        var et = 0.0f64
        m = 0usize
        while m < qq {
            if nu[m] <= 2.0f64 { small = true }
            et += nu[m] / (nu[m] - 2.0f64)
            m += 1usize
        }
        if small {
            dd = 2.0f64
        } else {
            dd = 2.0f64 * et / (et - qf)
        }
    }
    out[0usize] = fv * sg2 * qf
    out[1usize] = fv * sg2
    out[2usize] = qf
    out[3usize] = dd
    out[4usize] = fv
    out[5usize] = nb.pf(fv, qf, dd, false, false)
    ret ok
}

// lmerTest's Satterthwaite degrees of freedom of each fixed effect at the given (theta, sigma): df receives p values, est the fixed effects and se their standard errors (the t statistic is est / se, its p value 2 pt(-|t|, df))
fn lmer_satt(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, df: []f64, est: []f64, se: []f64) -> err {
    let (t0, e) = lmt_make(a, x, y, g, n, p, ng, reml, theta, sigma, false)
    if e != ok { ret e }
    var t = t0
    let (lv, e1) = lmt_alloc(a, p)
    let (o, e2) = lmt_alloc(a, 5usize)
    if e1 != ok || e2 != ok { ret mem.Full }
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            lv[i] = 0.0f64
            i += 1usize
        }
        lv[j] = 1.0f64
        let ec = lmt_1d(a, &t, lv, false, o)
        if ec != ok { ret ec }
        est[j] = o[0usize]
        se[j] = o[1usize]
        df[j] = o[2usize]
        j += 1usize
    }
    ret ok
}

// contest1D for the contrast lv, Satterthwaite (kr false) or Kenward-Roger: out = (estimate, standard error, df, t value, p value)
fn lmer_contest(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, lv: []const f64, kr: bool, out: []f64) -> err {
    let (t0, e) = lmt_make(a, x, y, g, n, p, ng, reml, theta, sigma, kr)
    if e != ok { ret e }
    var t = t0
    ret lmt_1d(a, &t, lv, kr, out)
}

// contest (joint) for the q rows of lmat (q by p, row-major): out = (Sum Sq, Mean Sq, NumDF, DenDF, F value, p value)
fn lmer_contest_joint(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, lmat: []const f64, q: usize, kr: bool, out: []f64) -> err {
    let (t0, e) = lmt_make(a, x, y, g, n, p, ng, reml, theta, sigma, kr)
    if e != ok { ret e }
    var t = t0
    ret lmt_md(a, &t, lmat, q, kr, out)
}

// lmerTest ranova for the one-intercept model: the criterion -2 logLik of the reduced lm(y ~ X) (logLik.lm, REML = reml: N (log(2 pi RSS / N) + 1) + log det(X' X) with N = n - p, or N = n for ML), the full model's criterion
// at (theta, sigma) as lme4 reports them, and the likelihood-ratio test on one degree of freedom;
// out = (npar full, logLik full, AIC full, npar reduced, logLik reduced, AIC reduced, LRT, Df, p value)
fn lmer_ranova(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, out: []f64) -> err {
    let (c0, ce) = lmm_new(a, x, y, g, n, p, ng, reml)
    if ce != ok { ret ce }
    var c = c0
    let full = lmm_dev2(&c, theta, sigma)
    // the reduced model: theta = 0 makes V = I, so the profiled quantities are those of ordinary least squares
    let _ = lmm_profile(&c, 0.0f64)
    var ldx = 0.0f64
    var j = 0usize
    while j < p {
        ldx += 2.0f64 * math.log[f64](c.u[j * p + j])
        j += 1usize
    }
    var nn = f64(n)
    var red = 0.0f64
    let two_pi = 6.283185307179586f64
    if reml {
        nn = f64(n - p)
        red = nn * (math.log[f64](two_pi * c.r2 / nn) + 1.0f64) + ldx
    } else {
        red = nn * (math.log[f64](two_pi * c.r2 / nn) + 1.0f64)
    }
    let lrt = red - full
    let npf = f64(p + 2usize)
    let npr = f64(p + 1usize)
    out[0usize] = npf
    out[1usize] = 0.0f64 - full / 2.0f64
    out[2usize] = full + 2.0f64 * npf
    out[3usize] = npr
    out[4usize] = 0.0f64 - red / 2.0f64
    out[5usize] = red + 2.0f64 * npr
    out[6usize] = lrt
    out[7usize] = 1.0f64
    out[8usize] = nmx.pchisq(lrt, 1.0f64, false, false)
    ret ok
}

// the term structure of a fixed-effects design: asgn gives each column of X its term (0 the intercept, otherwise 1-based), order the interaction order of each term,
// contain[k * nterm + s] = 1 when term s contains term k, rdx (n by r, column-major) is lmerTest's get_rdX (the full-dummy coding of each term) and xmap[a] the rdx column named like column a of X
type Terms = struct { nterm: usize, asgn: []const usize, order: []const usize, contain: []const f64, r: usize, rdx: []const f64, xmap: []const usize }

// R's round(x, digits) for a power of ten p10 = 10^digits
fn lmt_round(x: f64, p10: f64) -> f64 {
    let xs = x * p10
    let lo = math.floor[f64](xs)
    let d = xs - lo
    if d < 0.5f64 { ret lo / p10 }
    if d > 0.5f64 { ret (lo + 1.0f64) / p10 }
    if lo - 2.0f64 * math.floor[f64](lo / 2.0f64) == 0.0f64 { ret lo / p10 }
    ret (lo + 1.0f64) / p10
}

// zapsmall(v) with 7 digits
fn lmt_zap(v: []f64, cnt: usize) {
    var mx = 0.0f64
    var i = 0usize
    while i < cnt {
        if math.abs[f64](v[i]) > mx { mx = math.abs[f64](v[i]) }
        i += 1usize
    }
    if mx <= 0.0f64 { ret }
    var d = 7.0f64 - math.log10[f64](mx)
    if d < 0.0f64 { d = 0.0f64 }
    let p10 = math.pow[f64](10.0f64, math.floor[f64](d + 0.5f64))
    i = 0usize
    while i < cnt {
        v[i] = lmt_round(v[i], p10)
        i += 1usize
    }
}

// t(L) of lmerTest's doolittle(crossprod(X)) (eps 1e-6), row-major p by p: the type I contrasts
fn lmt_dool1(a: *mem.Arena, x: []const f64, n: usize, p: usize, lt: []f64) -> err {
    let (xtx, e1) = lmt_alloc(a, p * p)
    let (lo, e2) = lmt_alloc(a, p * p)
    let (up, e3) = lmt_alloc(a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += x[i * n + r] * x[j * n + r]
                r += 1usize
            }
            xtx[i * p + j] = s
            j += 1usize
        }
        lo[i * p + i] = 1.0f64
        i += 1usize
    }
    let eps = 0.000001f64
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = xtx[i * p + j]
            var k = 0usize
            while k < i {
                s -= lo[i * p + k] * up[k * p + j]
                k += 1usize
            }
            up[i * p + j] = s
            j += 1usize
        }
        j = i + 1usize
        while j < p {
            var s = xtx[j * p + i]
            var k = 0usize
            while k < i {
                s -= lo[j * p + k] * up[k * p + i]
                k += 1usize
            }
            if math.abs[f64](up[i * p + i]) < eps {
                s = 0.0f64
            } else {
                s = s / up[i * p + i]
            }
            lo[j * p + i] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var v = lo[j * p + i]
            if math.abs[f64](v) < eps { v = 0.0f64 }
            lt[i * p + j] = v
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the rows of lmerTest's type III (typ 3) or type I (typ 1) contrasts for term k (0-based) into lmat, q rows; type III with a single term or column is type I
fn lmt_type3(a: *mem.Arena, x: []const f64, n: usize, p: usize, tm: *const Terms, typ: usize, lsq: []f64) -> err {
    let nt = tm.nterm
    if typ == 1usize || nt <= 1usize || p <= 1usize { ret lmt_dool1(a, x, n, p, lsq) }
    let r = tm.r
    let (xtx, e1) = lmt_alloc(a, p * p)
    let (xti, e2) = lmt_alloc(a, p * p)
    let (xr, e3) = lmt_alloc(a, p * r)
    let (l0, e4) = lmt_alloc(a, r * p)
    let (gm, e5) = lmt_alloc(a, p * r)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var q = 0usize
            while q < n {
                s += x[i * n + q] * x[j * n + q]
                q += 1usize
            }
            xtx[i * p + j] = s
            j += 1usize
        }
        j = 0usize
        while j < r {
            var s = 0.0f64
            var q = 0usize
            while q < n {
                s += x[i * n + q] * tm.rdx[j * n + q]
                q += 1usize
            }
            xr[i * r + j] = s
            j += 1usize
        }
        i += 1usize
    }
    if !lmt_inv(a, xtx, p, xti) { ret mem.Full }
    lmt_mm(gm, xti, xr, p, p, r)
    i = 0usize
    while i < r {
        var j = 0usize
        while j < p {
            l0[i * p + j] = gm[j * r + i]
            j += 1usize
        }
        i += 1usize
    }
    lmt_zap(l0, r * p)
    // orthogonalise the columns of each term against the terms that contain it, highest order first
    var maxo = 0usize
    var k = 0usize
    while k < nt {
        if tm.order[k] > maxo { maxo = tm.order[k] }
        k += 1usize
    }
    var ord = maxo
    while ord >= 1usize {
        k = 0usize
        while k < nt {
            if tm.order[k] == ord {
                var m = 0usize
                var nk = 0usize
                var c = 0usize
                while c < p {
                    if tm.asgn[c] == k + 1usize { nk += 1usize }
                    var s = 0usize
                    while s < nt {
                        if tm.contain[k * nt + s] != 0.0f64 && tm.asgn[c] == s + 1usize { m += 1usize }
                        s += 1usize
                    }
                    c += 1usize
                }
                if m > 0usize {
                    let (hc, f1) = lmt_alloc(a, r * m)
                    let (yc, f2) = lmt_alloc(a, r * nk)
                    let (hh, f3) = lmt_alloc(a, m * m)
                    let (hhi, f4) = lmt_alloc(a, m * m)
                    let (hy, f5) = lmt_alloc(a, m * nk)
                    let (bm, f6) = lmt_alloc(a, m * nk)
                    let (fit, f7) = lmt_alloc(a, r * nk)
                    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok { ret mem.Full }
                    var cm = 0usize
                    var ct = 0usize
                    c = 0usize
                    while c < p {
                        if tm.asgn[c] == k + 1usize {
                            var rr = 0usize
                            while rr < r {
                                yc[rr * nk + ct] = l0[rr * p + c]
                                rr += 1usize
                            }
                            ct += 1usize
                        }
                        var s = 0usize
                        while s < nt {
                            if tm.contain[k * nt + s] != 0.0f64 && tm.asgn[c] == s + 1usize {
                                var rr = 0usize
                                while rr < r {
                                    hc[rr * m + cm] = l0[rr * p + c]
                                    rr += 1usize
                                }
                                cm += 1usize
                            }
                            s += 1usize
                        }
                        c += 1usize
                    }
                    lmt_tmm(hh, hc, hc, m, r, m)
                    if !lmt_inv(a, hh, m, hhi) { ret mem.Full }
                    lmt_tmm(hy, hc, yc, m, r, nk)
                    lmt_mm(bm, hhi, hy, m, m, nk)
                    lmt_mm(fit, hc, bm, r, m, nk)
                    var q = 0usize
                    while q < r * nk {
                        yc[q] = yc[q] - fit[q]
                        q += 1usize
                    }
                    lmt_zap(yc, r * nk)
                    ct = 0usize
                    c = 0usize
                    while c < p {
                        if tm.asgn[c] == k + 1usize {
                            var rr = 0usize
                            while rr < r {
                                l0[rr * p + c] = yc[rr * nk + ct]
                                rr += 1usize
                            }
                            ct += 1usize
                        }
                        c += 1usize
                    }
                }
            }
            k += 1usize
        }
        ord -= 1usize
    }
    // lsq[b][a]: column b of L (the X column), row xmap[a]; the rows of a term's hypothesis are its columns of this matrix transposed
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            lsq[j * p + i] = l0[tm.xmap[i] * p + j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// anova(model, type = 3 or 1) of the one-intercept model: for each term, out[6 k ..] = (Sum Sq, Mean Sq, NumDF, DenDF, F value, p value), NaN when the term has no estimable contrast
fn lmer_anova(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, tm: *const Terms, typ: usize, kr: bool, out: []f64) -> err {
    let nt = tm.nterm
    let (t0, e) = lmt_make(a, x, y, g, n, p, ng, reml, theta, sigma, kr)
    if e != ok { ret e }
    var t = t0
    let (lsq, e1) = lmt_alloc(a, p * p)
    let (lmat, e2) = lmt_alloc(a, p * p)
    let (o6, e3) = lmt_alloc(a, 6usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var tp = typ
    if nt <= 1usize || p <= 1usize { tp = 1usize }
    let et = lmt_type3(a, x, n, p, tm, typ, lsq)
    if et != ok { ret et }
    let nan = 0.0f64 / 0.0f64
    var k = 0usize
    while k < nt {
        var q = 0usize
        var c = 0usize
        while c < p {
            if tm.asgn[c] == k + 1usize {
                var s = 0.0f64
                var b = 0usize
                while b < p {
                    let v = lsq[c * p + b]
                    lmat[q * p + b] = v
                    s += math.abs[f64](v)
                    b += 1usize
                }
                if tp == 1usize || s > 0.00000001f64 { q += 1usize }
            }
            c += 1usize
        }
        if q == 0usize {
            var z = 0usize
            while z < 6usize {
                out[6usize * k + z] = nan
                z += 1usize
            }
        } else {
            let em = lmt_md(a, &t, lmat[0usize..q * p], q, kr, o6)
            if em != ok { ret em }
            var z = 0usize
            while z < 6usize {
                out[6usize * k + z] = o6[z]
                z += 1usize
            }
        }
        k += 1usize
    }
    ret ok
}

// difflsmeans for a factor with K levels whose K - 1 non-baseline indicator columns are cols (treatment coding, main effects): every pair (i < j) in combn order, out[7 m ..] =
// (Estimate, Std. Error, df, t value, lower, upper, Pr(>|t|)) of the contrast e_i - e_j
fn lmer_diffls(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, cols: []const usize, kk: usize, level: f64, kr: bool, out: []f64) -> err {
    let (t0, e) = lmt_make(a, x, y, g, n, p, ng, reml, theta, sigma, kr)
    if e != ok { ret e }
    var t = t0
    let (lv, e1) = lmt_alloc(a, p)
    let (o5, e2) = lmt_alloc(a, 5usize)
    if e1 != ok || e2 != ok { ret mem.Full }
    var m = 0usize
    var i = 0usize
    while i < kk {
        var j = i + 1usize
        while j < kk {
            var b = 0usize
            while b < p {
                lv[b] = 0.0f64
                b += 1usize
            }
            if i >= 1usize { lv[cols[i - 1usize]] = 1.0f64 }
            lv[cols[j - 1usize]] = -1.0f64
            let ec = lmt_1d(a, &t, lv, kr, o5)
            if ec != ok { ret ec }
            let tq = nb.qt(1.0f64 - (1.0f64 - level) / 2.0f64, o5[2usize], true, false)
            out[7usize * m] = o5[0usize]
            out[7usize * m + 1usize] = o5[1usize]
            out[7usize * m + 2usize] = o5[2usize]
            out[7usize * m + 3usize] = o5[3usize]
            out[7usize * m + 4usize] = o5[0usize] - tq * o5[1usize]
            out[7usize * m + 5usize] = o5[0usize] + tq * o5[1usize]
            out[7usize * m + 6usize] = o5[4usize]
            m += 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the lmer fit of x: out = (theta, sigma)
fn lmt_fit(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, o2: []f64) -> err {
    let (beta, e1) = lmt_alloc(a, p)
    let (re, e2) = lmt_alloc(a, ng)
    let (o4, e3) = lmt_alloc(a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let ef = lmer_ri(a, x, y, g, n, p, ng, reml, beta, re, o4)
    if ef != ok { ret ef }
    o2[0usize] = o4[1usize]
    o2[1usize] = o4[2usize]
    ret ok
}

// the columns of x selected by sel (n by m column-major copy)
fn lmt_xsub(a: *mem.Arena, x: []const f64, n: usize, sel: []const usize, m: usize) -> ([]f64, err) {
    let (o, e) = lmt_alloc(a, n * m)
    if e != ok { ret (o, e) }
    var j = 0usize
    while j < m {
        var i = 0usize
        while i < n {
            o[j * n + i] = x[sel[j] * n + i]
            i += 1usize
        }
        j += 1usize
    }
    ret (o, ok)
}

// the residual sum of squares of y on x (ordinary least squares)
fn lmt_rss(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, m: usize, ng: usize) -> (f64, err) {
    let (c0, ce) = lmm_new(a, x, y, g, n, m, ng, false)
    if ce != ok { ret (0.0f64, ce) }
    var c = c0
    let _ = lmm_profile(&c, 0.0f64)
    ret (c.r2, ok)
}

// lmerTest step() on the one-intercept model with main-effect terms: the random intercept is tested first (ranova, dropped when its p value exceeds alr, which turns the model into lm), then fixed terms are dropped one at a time,
// the largest p value above alf first, by drop1 (Satterthwaite F tests for lmer, F tests for lm). Every model is refitted here.
// out: [0] 1 when the random intercept is kept, [1] the number of dropped terms, [2 + i] the i-th dropped term (1-based), [2 + nt + i] its p value, [2 + 2 nt + 3 k ..] F, DenDF and p of term k in the final model (NaN when dropped),
// [2 + 5 nt] the p value and [3 + 5 nt] the statistic of the random-intercept test
fn lmer_step(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, tm: *const Terms, alr: f64, alf: f64, out: []f64) -> err {
    let nt = tm.nterm
    let nan = 0.0f64 / 0.0f64
    let (act, e1) = lmt_alloc(a, nt)
    let (sel, e2) = mem.alloc[usize](a, p)
    let (cterm, e3) = lmt_alloc(a, p)
    let (pv, e4) = lmt_alloc(a, nt)
    let (fv, e5) = lmt_alloc(a, nt)
    let (dv, e6) = lmt_alloc(a, nt)
    let (o2, e7) = lmt_alloc(a, 2usize)
    let (ro, e8) = lmt_alloc(a, 9usize)
    let (o6, e9) = lmt_alloc(a, 6usize)
    let (lmat, e10) = lmt_alloc(a, p * p)
    let (lt, e11) = lmt_alloc(a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    var z = 0usize
    while z < 4usize + 5usize * nt {
        out[z] = 0.0f64
        z += 1usize
    }
    var k = 0usize
    while k < nt {
        act[k] = 1.0f64
        k += 1usize
    }
    // the random intercept
    let ef = lmt_fit(a, x, y, g, n, p, ng, reml, o2)
    if ef != ok { ret ef }
    let er = lmer_ranova(a, x, y, g, n, p, ng, reml, o2[0usize], o2[1usize], ro)
    if er != ok { ret er }
    out[2usize + 5usize * nt] = ro[8usize]
    out[3usize + 5usize * nt] = ro[6usize]
    var lmo = false
    if ro[8usize] > alr { lmo = true }
    out[0usize] = 1.0f64
    if lmo { out[0usize] = 0.0f64 }
    var nel = 0usize
    var going = true
    while going {
        // the current design: the intercept columns and the columns of the active terms
        var pc = 0usize
        var c = 0usize
        while c < p {
            var keep = tm.asgn[c] == 0usize
            if tm.asgn[c] > 0usize && act[tm.asgn[c] - 1usize] != 0.0f64 { keep = true }
            if keep {
                sel[pc] = c
                cterm[pc] = f64(tm.asgn[c])
                pc += 1usize
            }
            c += 1usize
        }
        let (xs, ex) = lmt_xsub(a, x, n, sel[0usize..pc], pc)
        if ex != ok { ret ex }
        var nact = 0usize
        k = 0usize
        while k < nt {
            pv[k] = nan
            fv[k] = nan
            dv[k] = nan
            if act[k] != 0.0f64 { nact += 1usize }
            k += 1usize
        }
        if lmo {
            let (rf, er1) = lmt_rss(a, xs, y, g, n, pc, ng)
            if er1 != ok { ret er1 }
            let dfres = f64(n - pc)
            k = 0usize
            while k < nt {
                if act[k] != 0.0f64 {
                    var m2 = 0usize
                    var c2 = 0usize
                    while c2 < pc {
                        if usize(cterm[c2]) != k + 1usize {
                            sel[m2] = c2
                            m2 += 1usize
                        }
                        c2 += 1usize
                    }
                    let dft = f64(pc - m2)
                    let (xr, ex2) = lmt_xsub(a, xs, n, sel[0usize..m2], m2)
                    if ex2 != ok { ret ex2 }
                    let (rr, er2) = lmt_rss(a, xr, y, g, n, m2, ng)
                    if er2 != ok { ret er2 }
                    let fs = ((rr - rf) / dft) / (rf / dfres)
                    fv[k] = fs
                    dv[k] = dfres
                    pv[k] = nb.pf(fs, dft, dfres, false, false)
                }
                k += 1usize
            }
        } else if nact > 0usize {
            let ef2 = lmt_fit(a, xs, y, g, n, pc, ng, reml, o2)
            if ef2 != ok { ret ef2 }
            let (t0, em) = lmt_make(a, xs, y, g, n, pc, ng, reml, o2[0usize], o2[1usize], false)
            if em != ok { ret em }
            var t = t0
            if nact == 1usize {
                let ed = lmt_dool1(a, xs, n, pc, lt)
                if ed != ok { ret ed }
            }
            k = 0usize
            while k < nt {
                if act[k] != 0.0f64 {
                    var q = 0usize
                    var c2 = 0usize
                    while c2 < pc {
                        if usize(cterm[c2]) == k + 1usize {
                            var b = 0usize
                            while b < pc {
                                var v = 0.0f64
                                if nact == 1usize {
                                    v = lt[c2 * pc + b]
                                } else {
                                    if b == c2 { v = 1.0f64 }
                                }
                                lmat[q * pc + b] = v
                                b += 1usize
                            }
                            q += 1usize
                        }
                        c2 += 1usize
                    }
                    let em2 = lmt_md(a, &t, lmat[0usize..q * pc], q, false, o6)
                    if em2 != ok { ret em2 }
                    fv[k] = o6[4usize]
                    dv[k] = o6[3usize]
                    pv[k] = o6[5usize]
                }
                k += 1usize
            }
        }
        // the largest p value; drop it when above alf
        var worst = nt
        var wp = 0.0f64
        k = 0usize
        while k < nt {
            if act[k] != 0.0f64 && pv[k] == pv[k] && (worst == nt || pv[k] > wp) {
                worst = k
                wp = pv[k]
            }
            k += 1usize
        }
        if worst < nt && wp > alf {
            out[2usize + nel] = f64(worst + 1usize)
            out[2usize + nt + nel] = wp
            nel += 1usize
            act[worst] = 0.0f64
        } else {
            going = false
        }
    }
    out[1usize] = f64(nel)
    k = 0usize
    while k < nt {
        out[2usize + 2usize * nt + 3usize * k] = fv[k]
        out[2usize + 2usize * nt + 3usize * k + 1usize] = dv[k]
        out[2usize + 2usize * nt + 3usize * k + 2usize] = pv[k]
        k += 1usize
    }
    ret ok
}
