// R arm bayespolr: the proportional odds model with t priors on the coefficients and pseudo-counts for the bins, fitted the way the function does it: bayesglm.fit starting values,
// the augmented data, optim's BFGS (R's vmmin) on the negative log posterior with its analytic gradient, then optim's numerical Hessian of the gradient.
//
// Methods: 0 logistic, 1 probit, 2 cloglog, 3 cauchit. Quirks kept: the prior scale is not divided by the spread of the inputs in the posterior (only in the starting fit), the cloglog
// starting fit is a probit, and the standard errors of display come from the Hessian in the parameters (beta, theta) carried to (beta, zeta) by the Jacobian, as vcov.polr does.
// Not here: offsets in the formula interface other than a supplied vector, rank-deficient designs.

use e.algo.stat.armx87 as xe
use e.algo.stat.arm as ar
use e.algo.stat.armglm as ag
use e.algo.stat.armextra as ax
use e.algo.stat.armld as ld
use e.algo.stat.armnorm as an
use e.algo.stat.armtan as tn
use e.algo.stat.armdt as dr
use e.algo.linalg.lapack_gesdd as gsd
use e.algo.stat.rbfgs as bf
use e.algo.stat.gbmfit as gb
use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem
use e.algo.rand.r as rng

type PolrCtx = struct { n: usize, pc: usize, q: usize, x: []const f64, y: []const f64, wt: []const f64, off: []const f64, method: usize, pm: f64, ps: f64, pdf: f64, eta: []f64, pr: []f64, p1: []f64, p2: []f64, v: []f64, gam: []f64, tmp: []f64, g2: []f64, fcount: usize, gcount: usize }

fn pfun(m: usize, x: f64) -> f64 {
    if m == 0usize { ret 1.0f64 / (1.0f64 + xe.exp_r(0.0f64 - x)) }
    if m == 1usize { ret an.pnorm_cr(x) }
    if m == 2usize { ret xe.exp_r(0.0f64 - xe.exp_r(0.0f64 - x)) }
    ret tn.pcauchy_c(x)
}

fn dfun(m: usize, x: f64) -> f64 {
    if m == 0usize {
        let xa = math.abs[f64](x)
        let e = xe.exp_r(0.0f64 - xa)
        let f = 1.0f64 + e
        ret e / (f * f)
    }
    if m == 1usize { ret an.dnorm_cr(x) }
    if m == 2usize { ret xe.exp_r(0.0f64 - x - xe.exp_r(0.0f64 - x)) }
    ret dist.dcauchy(x, 0.0f64, 1.0f64, false)
}

// gamm, eta and the cell probabilities of the augmented data at beta = (coefficients, theta); answers whether every probability is positive
fn polr_prep(c: *PolrCtx, b: []const f64) -> bool {
    let pc = c.pc
    let q = c.q
    c.gam[0usize] = 0.0f64 - 100.0f64
    // cumsum accumulates in a long double and rounds each partial sum to double
    var s = ld.ld_from(b[pc])
    c.gam[1usize] = b[pc]
    var l = 1usize
    while l < q {
        s = ld.ld_add(s, ld.ld_from(xe.exp_r(b[pc + l])))
        c.gam[1usize + l] = ld.ld_to(s)
        l += 1usize
    }
    c.gam[q + 1usize] = 100.0f64
    var allpos = true
    var i = 0usize
    while i < c.n {
        var e = 0.0f64
        var j = 0usize
        while j < pc {
            e += c.x[i * pc + j] * b[j]
            j += 1usize
        }
        c.eta[i] = c.off[i] + e
        let cat = usize(c.y[i])
        c.pr[i] = pfun(c.method, c.gam[cat] - c.eta[i]) - pfun(c.method, c.gam[cat - 1usize] - c.eta[i])
        if !(c.pr[i] > 0.0f64) { allpos = false }
        i += 1usize
    }
    ret allpos
}


fn polr_f(c: *PolrCtx, b: []const f64) -> f64 {
    c.fcount += 1usize
    let allpos = polr_prep(c, b)
    var f = 1.0f64 / 0.0f64
    if allpos {
        var i = 0usize
        while i < c.n {
            c.tmp[i] = c.wt[i] * xe.log_r(c.pr[i])
            i += 1usize
        }
        f = 0.0f64 - ax.csum(c.tmp[0usize..c.n])
    }
    if c.pc > 0usize {
        var j = 0usize
        while j < c.pc {
            c.tmp[j] = dr.dt_r((b[j] - c.pm) / c.ps, c.pdf, true)
            j += 1usize
        }
        f = f - ax.csum(c.tmp[0usize..c.pc])
    }
    ret f
}

fn polr_g(c: *PolrCtx, b: []const f64, g: []f64) {
    c.gcount += 1usize
    let pc = c.pc
    let q = c.q
    let allpos = polr_prep(c, b)
    var j = 0usize
    while j < pc + q {
        g[j] = 0.0f64 / 0.0f64
        j += 1usize
    }
    if !allpos { ret }
    var i = 0usize
    while i < c.n {
        let cat = usize(c.y[i])
        c.p1[i] = dfun(c.method, c.gam[cat] - c.eta[i])
        c.p2[i] = dfun(c.method, c.gam[cat - 1usize] - c.eta[i])
        c.v[i] = (c.wt[i] * (c.p1[i] - c.p2[i])) / c.pr[i]
        i += 1usize
    }
    j = 0usize
    while j < pc {
        var s = 0.0f64
        i = 0usize
        while i < c.n {
            s += c.x[i * pc + j] * c.v[i]
            i += 1usize
        }
        // dt.deriv of the prior on this coefficient
        let d = 0.001f64
        let dd = (dr.dt_r((b[j] + d - c.pm) / c.ps, c.pdf, true) - dr.dt_r((b[j] - d - c.pm) / c.ps, c.pdf, true)) / (2.0f64 * d)
        g[j] = s - dd
        j += 1usize
    }
    // g2 = -t(xx) (wt / pr), then t(g2) times the Jacobian of theta
    var l = 0usize
    while l < q {
        var s = 0.0f64
        i = 0usize
        while i < c.n {
            let cat = usize(c.y[i])
            var xx = 0.0f64
            var t1 = 0.0f64
            var t2 = 0.0f64
            if cat == l + 1usize { t1 = c.p1[i] }
            if cat == l + 2usize { t2 = c.p2[i] }
            xx = t1 - t2
            s += xx * (c.wt[i] / c.pr[i])
            i += 1usize
        }
        c.g2[l] = 0.0f64 - s
        l += 1usize
    }
    var m = 0usize
    while m < q {
        var s = 0.0f64
        l = 0usize
        while l < q {
            var jv = 0.0f64
            if m == 0usize { jv = 1.0f64 } else {
                if l >= m { jv = xe.exp_r(b[pc + m]) }
            }
            s += c.g2[l] * jv
            l += 1usize
        }
        g[pc + m] = s
        m += 1usize
    }
}

// bayespolr(y ~ x, method, prior.mean, prior.scale, prior.df, prior.counts.for.bins = 1 / (q + 1), scaled): x is n by pc row-major without the intercept, y the category 1..J (J >= 3), wt and
// off are n long (or empty). Outputs: beta (pc), zeta (J - 1), info = deviance, f.evals, g.evals, the Hessian (pc + q squared, row-major) and fitted (n by J row-major). Answers 0 on failure.
fn bayespolr(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, pc: usize, jl: usize, wts: []const f64, offs: []const f64, method: usize, prior_mean: f64, prior_scale0: f64, prior_df: f64, scaled: bool, beta: []f64, zeta: []f64, info: []f64, hess: []f64, fitted: []f64) -> usize {
    let q = jl - 1usize
    let np = pc + q
    var psc = prior_scale0
    if method == 1usize { psc = psc * 1.6f64 }
    let na = n + q + 1usize
    let (wt, e1) = mem.alloc[f64](a, na)
    let (off, e2) = mem.alloc[f64](a, na)
    let (xa, e3) = mem.alloc[f64](a, na * pc)
    let (ya, e4) = mem.alloc[f64](a, na)
    let (xi, e5) = mem.alloc[f64](a, n * (pc + 1usize))
    let (y1, e6) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0usize }
    var i = 0usize
    while i < n {
        wt[i] = 1.0f64
        off[i] = 0.0f64
        if wts.len == n { wt[i] = wts[i] }
        if offs.len == n { off[i] = offs[i] }
        ya[i] = y[i]
        var j = 0usize
        xi[i * (pc + 1usize)] = 1.0f64
        while j < pc {
            xi[i * (pc + 1usize) + 1usize + j] = x[i * pc + j]
            xa[i * pc + j] = x[i * pc + j]
            j += 1usize
        }
        i += 1usize
    }
    // starting values: bayesglm.fit on y > length(lev) %/% 2
    let q1 = jl / 2usize
    i = 0usize
    while i < n {
        y1[i] = 0.0f64
        if y[i] > f64(q1) { y1[i] = 1.0f64 }
        i += 1usize
    }
    var link = 3usize
    if method == 1usize || method == 2usize { link = 4usize }
    if method == 3usize { link = 5usize }
    let k = pc + 1usize
    let (pm, e7) = mem.alloc[f64](a, k)
    let (pd, e8) = mem.alloc[f64](a, k)
    let (ps, e9) = mem.alloc[f64](a, k)
    let (c0, e10) = mem.alloc[f64](a, k)
    let (inf0, e11) = mem.alloc[f64](a, 4usize)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret 0usize }
    var j = 0usize
    while j < k {
        pm[j] = prior_mean
        pd[j] = prior_df
        ps[j] = psc
        if j == 0usize {
            pm[j] = 0.0f64
            pd[j] = 1.0f64
            ps[j] = 10.0f64
        }
        j += 1usize
    }
    var nocov: []f64 = zero
    let wsl: []const f64 = wt[0usize..n]
    let osl: []const f64 = off[0usize..n]
    if ag.bayesglm_gen(a, xi, y1, n, k, 1usize, link, wsl, osl, pm, pd, ps, scaled, true, c0, inf0, nocov) == 0usize { ret 0usize }
    var spacing = 0.0f64
    let (gam0, e12) = mem.alloc[f64](a, q)
    let (start, e13) = mem.alloc[f64](a, np)
    if e12 != ok || e13 != ok { ret 0usize }
    var l = 0usize
    while l < q {
        let p = f64(l + 1usize) / f64(q + 1usize)
        spacing = xe.log_r(p / (1.0f64 - p))
        if method != 0usize { spacing = spacing / 1.7f64 }
        gam0[l] = spacing
        l += 1usize
    }
    let sq1 = gam0[q1 - 1usize]
    l = 0usize
    while l < q {
        gam0[l] = (0.0f64 - c0[0usize] + gam0[l]) - sq1
        l += 1usize
    }
    j = 0usize
    while j < pc {
        start[j] = c0[1usize + j]
        j += 1usize
    }
    start[pc] = gam0[0usize]
    l = 1usize
    while l < q {
        start[pc + l] = xe.log_r(gam0[l] - gam0[l - 1usize])
        l += 1usize
    }
    // the augmented data: one row per bin at the column means, with prior.counts.for.bins weights
    let (cm, e14) = mem.alloc[f64](a, pc)
    let (tmpc, e15) = mem.alloc[f64](a, n)
    if e14 != ok || e15 != ok { ret 0usize }
    j = 0usize
    while j < pc {
        i = 0usize
        while i < n {
            tmpc[i] = x[i * pc + j]
            i += 1usize
        }
        cm[j] = ld.colmean_ld(tmpc[0usize..n])
        j += 1usize
    }
    l = 0usize
    while l < q + 1usize {
        ya[n + l] = f64(l + 1usize)
        wt[n + l] = 1.0f64 / f64(q + 1usize)
        off[n + l] = 0.0f64
        j = 0usize
        while j < pc {
            xa[(n + l) * pc + j] = cm[j]
            j += 1usize
        }
        l += 1usize
    }
    let (eta, e16) = mem.alloc[f64](a, na)
    let (pr, e17) = mem.alloc[f64](a, na)
    let (p1, e18) = mem.alloc[f64](a, na)
    let (p2, e19) = mem.alloc[f64](a, na)
    let (vv, e20) = mem.alloc[f64](a, na)
    let (gam, e21) = mem.alloc[f64](a, q + 2usize)
    let (tmp, e22) = mem.alloc[f64](a, na + np)
    let (g2, e23) = mem.alloc[f64](a, q)
    if e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok { ret 0usize }
    var c = PolrCtx { n: na, pc: pc, q: q, x: xa, y: ya, wt: wt, off: off, method: method, pm: prior_mean, ps: psc, pdf: prior_df, eta: eta, pr: pr, p1: p1, p2: p2, v: vv, gam: gam, tmp: tmp, g2: g2, fcount: 0usize, gcount: 0usize }
    let fmin = bf.vmmin[PolrCtx](a, &c, polr_f, polr_g, start, 1.4901161193847656e-08f64, 100usize)
    // optim's numerical Hessian: central differences of the gradient with step 1e-3, then symmetrised
    let (g1, e24) = mem.alloc[f64](a, np)
    let (g3, e25) = mem.alloc[f64](a, np)
    let (bb, e26) = mem.alloc[f64](a, np)
    if e24 != ok || e25 != ok || e26 != ok { ret 0usize }
    let fev = c.fcount
    let gev = c.gcount
    j = 0usize
    while j < np {
        bb[j] = start[j]
        j += 1usize
    }
    // optimhess moves one coordinate by + eps, then - 2 eps, then + eps, and the restored value is not always the starting one
    var r = 0usize
    while r < np {
        bb[r] = bb[r] + 0.001f64
        polr_g(&c, bb, g1)
        bb[r] = bb[r] - 2.0f64 * 0.001f64
        polr_g(&c, bb, g3)
        j = 0usize
        while j < np {
            hess[r * np + j] = (g1[j] - g3[j]) / (2.0f64 * 0.001f64)
            j += 1usize
        }
        bb[r] = bb[r] + 0.001f64
        r += 1usize
    }
    r = 0usize
    while r < np {
        j = r + 1usize
        while j < np {
            let t = 0.5f64 * (hess[r * np + j] + hess[j * np + r])
            hess[r * np + j] = t
            hess[j * np + r] = t
            j += 1usize
        }
        r += 1usize
    }
    j = 0usize
    while j < pc {
        beta[j] = start[j]
        j += 1usize
    }
    var sz = ld.ld_from(start[pc])
    zeta[0usize] = start[pc]
    l = 1usize
    while l < q {
        sz = ld.ld_add(sz, ld.ld_from(xe.exp_r(start[pc + l])))
        zeta[l] = ld.ld_to(sz)
        l += 1usize
    }
    info[0usize] = 2.0f64 * fmin
    info[1usize] = f64(fev)
    info[2usize] = f64(gev)
    // fitted: the differences of the cumulative probabilities
    i = 0usize
    while i < n {
        var e = 0.0f64
        j = 0usize
        while j < pc {
            e += x[i * pc + j] * beta[j]
            j += 1usize
        }
        var prev = 0.0f64
        l = 0usize
        while l < q {
            let cp = pfun(method, zeta[l] - e)
            fitted[i * jl + l] = cp - prev
            prev = cp
            l += 1usize
        }
        fitted[i * jl + q] = 1.0f64 - prev
        i += 1usize
    }
    ret 1usize
}

// sim() on a bayespolr or polr fit: mvrnorm(nsims, c(coef, zeta), vcov) with vcov.polr's covariance; out is nsims by (pc + q) row-major, the coefficients first
fn sim_polr(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, pc: usize, jl: usize, wts: []const f64, offs: []const f64, method: usize, prior_mean: f64, prior_scale0: f64, prior_df: f64, scaled: bool, nsims: usize, out: []f64) -> err {
    let q = jl - 1usize
    let np = pc + q
    let (beta, e1) = mem.alloc[f64](a, pc)
    let (zeta, e2) = mem.alloc[f64](a, q)
    let (info, e3) = mem.alloc[f64](a, 3usize)
    let (hess, e4) = mem.alloc[f64](a, np * np)
    let (fit, e5) = mem.alloc[f64](a, n * jl)
    let (vc, e6) = mem.alloc[f64](a, np * np)
    let (mu, e7) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    if bayespolr(a, x, y, n, pc, jl, wts, offs, method, prior_mean, prior_scale0, prior_df, scaled, beta, zeta, info, hess, fit) == 0usize { ret mem.Full }
    let e = polr_vcov(a, hess, pc, q, zeta, vc)
    if e != ok { ret e }
    var i = 0usize
    while i < pc {
        mu[i] = beta[i]
        i += 1usize
    }
    i = 0usize
    while i < q {
        mu[pc + i] = zeta[i]
        i += 1usize
    }
    ret ag.sim_draws(a, g, vc, mu, np, nsims, out)
}

// MASS::ginv of the symmetric n by n h as R computes it: svd (dgesdd), then v %*% ((1 / d) * t(u)) over the singular values above sqrt(eps) * d[1], every dot product in ascending order
fn ginv_r(a: *mem.Arena, h: []const f64, n: usize) -> ([]f64, err) {
    let (s, e1) = mem.alloc[f64](a, n)
    let (u, e2) = mem.alloc[f64](a, n * n)
    let (vt, e3) = mem.alloc[f64](a, n * n)
    let (out, e4) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (out, mem.Full) }
    let e = gsd.svd_all(a, h, n, n, s, u, vt)
    if e != ok { ret (out, e) }
    let tol = 1.4901161193847656e-8f64 * s[0usize]
    var r = 0usize
    while r < n {
        var c = 0usize
        while c < n {
            var acc = 0.0f64
            var j = 0usize
            while j < n {
                if s[j] > tol { acc += vt[r * n + j] * ((1.0f64 / s[j]) * u[j * n + c]) }
                j += 1usize
            }
            out[r * n + c] = acc
            c += 1usize
        }
        r += 1usize
    }
    ret (out, ok)
}

// vcov.polr: the inverse Hessian carried from (beta, theta) to (beta, zeta); h and the answer are (pc + q) squared row-major; zeta is the fitted cut points
fn polr_vcov(a: *mem.Arena, h: []const f64, pc: usize, q: usize, zeta: []const f64, out: []f64) -> err {
    let np = pc + q
    let (vc, e) = ginv_r(a, h, np)
    if e != ok { ret e }
    let (am, e1) = mem.alloc[f64](a, np * np)
    let (tm, e2) = mem.alloc[f64](a, np * np)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < np * np {
        am[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < np {
        am[i * np + i] = 1.0f64
        i += 1usize
    }
    // theta = c(zeta[1], log(diff(zeta))); the Jacobian block: column 0 ones, column m the exp(theta_m) from row m down
    var m = 0usize
    while m < q {
        var l = 0usize
        while l < q {
            var jv = 0.0f64
            if m == 0usize { jv = 1.0f64 } else {
                if l >= m { jv = zeta[m] - zeta[m - 1usize] }
            }
            am[(pc + l) * np + pc + m] = jv
            l += 1usize
        }
        m += 1usize
    }
    // out = A vc A'
    var r = 0usize
    while r < np {
        var c = 0usize
        while c < np {
            var s = 0.0f64
            var t = 0usize
            while t < np {
                s += am[r * np + t] * vc[t * np + c]
                t += 1usize
            }
            tm[r * np + c] = s
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < np {
        var c = 0usize
        while c < np {
            var s = 0.0f64
            var t = 0usize
            while t < np {
                s += tm[r * np + t] * am[c * np + t]
                t += 1usize
            }
            out[r * np + c] = s
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}
