// R lme4 lmer for one random intercept: y = X beta + b[group] + e, b ~ N(0, sigma_b^2), e ~ N(0, sigma^2), fitted by REML or maximum likelihood.
//
// The deviance is profiled over theta = sigma_b / sigma (every other parameter is a closed form of it) and minimised with R's Brent search; the group block of V / sigma^2 = I + theta^2 1 1'
// inverts as I - theta^2 / (1 + n_g theta^2) 1 1', so nothing larger than the p by p fixed-effect system is ever solved.
//
// Not here: crossed and nested random effects, random slopes, glmer (Laplace and Gauss-Hermite), lmerTest, predict and simulate.

use e.algo.stat.bayesmpkg as bz
use e.algo.stat.fdrtool as fd
use e.math
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

// the variance of fixed effect j, sigma^2 (X' V^-1 X)^-1_jj, at theta
fn lmm_vj(c: *Lmm, theta: f64, sigma: f64, j: usize) -> f64 {
    let _ = lmm_profile(c, theta)
    var s = 0.0f64
    var q = j
    while q < c.p {
        s += c.uinv[q * c.p + j] * c.uinv[q * c.p + j]
        q += 1usize
    }
    ret sigma * sigma * s
}

// lmerTest's Satterthwaite degrees of freedom of each fixed effect at the given (theta, sigma): df_j = 2 v_j^2 / (g_j' A g_j) with v_j the variance of the estimate, g_j its gradient in (theta, sigma) and A = 2 H^-1 the asymptotic covariance from the Hessian H of the deviance,
// both by central differences (theta, sigma as lme4 reports them); df receives p values, est the fixed effects and se their standard errors at theta (the t statistic is est / se, its p value 2 pt(-|t|, df))
fn lmer_satt(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, df: []f64, est: []f64, se: []f64) -> err {
    let (cnt, e1) = mem.alloc[f64](a, ng)
    let (w, e2) = mem.alloc[f64](a, ng)
    let (xtvx, e3) = mem.alloc[f64](a, p * p)
    let (xtvy, e4) = mem.alloc[f64](a, p)
    let (u, e5) = mem.alloc[f64](a, p * p)
    let (uinv, e6) = mem.alloc[f64](a, p * p)
    let (tv, e7) = mem.alloc[f64](a, p)
    let (beta, e8) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
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
    var ht = 0.001f64 * theta
    if theta < 0.1f64 { ht = 0.0001f64 }
    let hs = 0.001f64 * sigma
    let f0 = lmm_dev2(&c, theta, sigma)
    let ftp = lmm_dev2(&c, theta + ht, sigma)
    let ftm = lmm_dev2(&c, theta - ht, sigma)
    let fsp = lmm_dev2(&c, theta, sigma + hs)
    let fsm = lmm_dev2(&c, theta, sigma - hs)
    let fpp = lmm_dev2(&c, theta + ht, sigma + hs)
    let fpm = lmm_dev2(&c, theta + ht, sigma - hs)
    let fmp = lmm_dev2(&c, theta - ht, sigma + hs)
    let fmm = lmm_dev2(&c, theta - ht, sigma - hs)
    let h11 = (ftp - 2.0f64 * f0 + ftm) / (ht * ht)
    let h22 = (fsp - 2.0f64 * f0 + fsm) / (hs * hs)
    let h12 = (fpp - fpm - fmp + fmm) / (4.0f64 * ht * hs)
    let det = h11 * h22 - h12 * h12
    // A = 2 H^-1
    let a11 = 2.0f64 * h22 / det
    let a22 = 2.0f64 * h11 / det
    let a12 = 0.0f64 - 2.0f64 * h12 / det
    let _ = lmm_profile(&c, theta)
    var j = 0usize
    while j < p {
        est[j] = c.beta[j]
        j += 1usize
    }
    j = 0usize
    while j < p {
        let v = lmm_vj(&c, theta, sigma, j)
        se[j] = math.sqrt[f64](v)
        let gt = (lmm_vj(&c, theta + ht, sigma, j) - lmm_vj(&c, theta - ht, sigma, j)) / (2.0f64 * ht)
        let gs = (lmm_vj(&c, theta, sigma + hs, j) - lmm_vj(&c, theta, sigma - hs, j)) / (2.0f64 * hs)
        df[j] = 2.0f64 * v * v / (gt * gt * a11 + 2.0f64 * gt * gs * a12 + gs * gs * a22)
        j += 1usize
    }
    ret ok
}

// the variance of the contrast L' beta, sigma^2 L' (X' V^-1 X)^-1 L = sigma^2 |Ui' L|^2, at theta
fn lmm_vl(c: *Lmm, theta: f64, sigma: f64, lv: []const f64) -> f64 {
    let _ = lmm_profile(c, theta)
    var s = 0.0f64
    var q = 0usize
    while q < c.p {
        var t = 0.0f64
        var j = 0usize
        while j <= q {
            t += c.uinv[q * c.p + j] * lv[j]
            j += 1usize
        }
        s += t * t
        q += 1usize
    }
    ret sigma * sigma * s
}

// lmerTest's contest1D for the contrast L' beta: out = (estimate, standard error, Satterthwaite df, t value, p value), at the given (theta, sigma)
fn lmer_contest(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, theta: f64, sigma: f64, lv: []const f64, out: []f64) -> err {
    let (cnt, e1) = mem.alloc[f64](a, ng)
    let (w, e2) = mem.alloc[f64](a, ng)
    let (xtvx, e3) = mem.alloc[f64](a, p * p)
    let (xtvy, e4) = mem.alloc[f64](a, p)
    let (u, e5) = mem.alloc[f64](a, p * p)
    let (uinv, e6) = mem.alloc[f64](a, p * p)
    let (tv, e7) = mem.alloc[f64](a, p)
    let (beta, e8) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
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
    var ht = 0.001f64 * theta
    if theta < 0.1f64 { ht = 0.0001f64 }
    let hs = 0.001f64 * sigma
    let f0 = lmm_dev2(&c, theta, sigma)
    let ftp = lmm_dev2(&c, theta + ht, sigma)
    let ftm = lmm_dev2(&c, theta - ht, sigma)
    let fsp = lmm_dev2(&c, theta, sigma + hs)
    let fsm = lmm_dev2(&c, theta, sigma - hs)
    let fpp = lmm_dev2(&c, theta + ht, sigma + hs)
    let fpm = lmm_dev2(&c, theta + ht, sigma - hs)
    let fmp = lmm_dev2(&c, theta - ht, sigma + hs)
    let fmm = lmm_dev2(&c, theta - ht, sigma - hs)
    let h11 = (ftp - 2.0f64 * f0 + ftm) / (ht * ht)
    let h22 = (fsp - 2.0f64 * f0 + fsm) / (hs * hs)
    let h12 = (fpp - fpm - fmp + fmm) / (4.0f64 * ht * hs)
    let det = h11 * h22 - h12 * h12
    let a11 = 2.0f64 * h22 / det
    let a22 = 2.0f64 * h11 / det
    let a12 = 0.0f64 - 2.0f64 * h12 / det
    let v = lmm_vl(&c, theta, sigma, lv)
    let gt = (lmm_vl(&c, theta + ht, sigma, lv) - lmm_vl(&c, theta - ht, sigma, lv)) / (2.0f64 * ht)
    let gs = (lmm_vl(&c, theta, sigma + hs, lv) - lmm_vl(&c, theta, sigma - hs, lv)) / (2.0f64 * hs)
    let df = 2.0f64 * v * v / (gt * gt * a11 + 2.0f64 * gt * gs * a12 + gs * gs * a22)
    let _ = lmm_profile(&c, theta)
    var est = 0.0f64
    var j = 0usize
    while j < p {
        est += lv[j] * c.beta[j]
        j += 1usize
    }
    let se = math.sqrt[f64](v)
    out[0usize] = est
    out[1usize] = se
    out[2usize] = df
    out[3usize] = est / se
    out[4usize] = 2.0f64 * nb.pt(0.0f64 - math.abs[f64](est / se), df, true, false)
    ret ok
}
