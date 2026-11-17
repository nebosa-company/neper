// R lme4 lmer for one random intercept: y = X beta + b[group] + e, b ~ N(0, sigma_b^2), e ~ N(0, sigma^2), fitted by REML or maximum likelihood.
//
// The deviance is profiled over theta = sigma_b / sigma (every other parameter is a closed form of it) and minimised with R's Brent search; the group block of V / sigma^2 = I + theta^2 1 1'
// inverts as I - theta^2 / (1 + n_g theta^2) 1 1', so nothing larger than the p by p fixed-effect system is ever solved.
//
// Not here: crossed and nested random effects, random slopes, glmer (Laplace and Gauss-Hermite), lmerTest, predict and simulate.

use e.algo.stat.bayesmpkg as bz
use e.algo.stat.fdrtool as fd
use e.math
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
