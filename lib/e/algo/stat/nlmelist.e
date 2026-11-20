// R nlme: lme (random effects at one grouping level with optional gls correlation and variance structures, REML and ML),
// lmList, and the nls self-start models SSlogis, SSasymp, SSmicmen, SSfpl and SSgompertz with an nls-style fit.
//
// lme is the gls profile objective of e.algo.stat.gls with the within-group covariance Lambda + Z D Z' (D the random-effects
// covariance relative to sigma^2, log-Cholesky parametrised), minimised by nlminb; the estimates are the optimum nlme's own
// iterations converge to; a Newton polish on five-point differences reaches the exact optimum. Output ends with the fixed-effect t limits and the
// intervals.lme var-cov limits. Not here: nested or crossed random effects, pdDiag and the other pdMat classes, nlme (non-linear mixed models).

use e.algo.stat.gls as g
use e.algo.stat.minpacklm as lm
use e.algo.stat.nlminb as nlb
use e.algo.stat.psych as ps
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

// ---------------------------------------------------------------- lme

// output of lme_fit: coef (p), sigma, logLik, AIC, BIC, random-effect sd (q), random-effect correlations (lower triangle by
// columns), natural correlation parameters, natural variance parameters, se (p), ranef (group-major, q per group)
fn vc_len(s: *const g.Spec) -> usize {
    let q = s.q
    ret q + q * (q - 1usize) / 2usize + g.ncnat(s) + g.nvnat(s) + 1usize
}

// then: lower and upper 95% limits of the fixed effects (p each), and of the natural variance parameters (random-effect sds and
// correlation, correlation and variance parameters, sigma; vc_len each, NaN beyond two random effects)
fn lme_len(s: *const g.Spec) -> usize {
    let q = s.q
    ret 4usize + 4usize * s.p + q + q * (q - 1usize) / 2usize + g.ncnat(s) + g.nvnat(s) + s.ng * q + 2usize * vc_len(s)
}

// five-point central-difference gradient of the lme objective: nlminb's own forward differences leave the estimates ~1e-6 from the optimum
fn lme_grad(c: *g.Ctx, par: []const f64, gr: []f64) {
    let st = mem.mark(c.a)
    let (w, e) = mem.alloc[f64](c.a, par.len)
    if e == ok {
        var i = 0usize
        while i < par.len {
            w[i] = par[i]
            i += 1usize
        }
        i = 0usize
        while i < par.len {
            var ab = par[i]
            if ab < 0.0f64 { ab = 0.0f64 - ab }
            let h = 1.0e-3f64 * (1.0f64 + ab)
            w[i] = par[i] + h
            let f1 = g.obj(c, w)
            w[i] = par[i] - h
            let m1 = g.obj(c, w)
            w[i] = par[i] + 2.0f64 * h
            let f2 = g.obj(c, w)
            w[i] = par[i] - 2.0f64 * h
            let m2 = g.obj(c, w)
            w[i] = par[i]
            gr[i] = (8.0f64 * (f1 - m1) - (f2 - m2)) / (12.0f64 * h)
            i += 1usize
        }
    }
    mem.reset(c.a, st)
}

// Newton steps on the lme objective from nlminb's answer: gradient by lme_grad, Hessian by central differences of it; a step that
// does not lower the objective ends the polish
fn lme_polish(a: *mem.Arena, c: *g.Ctx, pv: []f64) {
    let np = pv.len
    let st = mem.mark(a)
    let (gr, e1) = mem.alloc[f64](a, np)
    let (gp, e2) = mem.alloc[f64](a, np)
    let (gm, e3) = mem.alloc[f64](a, np)
    let (hs, e4) = mem.alloc[f64](a, np * np)
    let (hi, e5) = mem.alloc[f64](a, np * np)
    let (pn, e6) = mem.alloc[f64](a, np)
    if e1 == ok && e2 == ok && e3 == ok && e4 == ok && e5 == ok && e6 == ok {
        var it = 0usize
        while it < 12usize {
            lme_grad(c, pv, gr)
            var j = 0usize
            while j < np {
                var ab = pv[j]
                if ab < 0.0f64 { ab = 0.0f64 - ab }
                let h = 1.0e-4f64 * (1.0f64 + ab)
                let pj = pv[j]
                pv[j] = pj + h
                lme_grad(c, pv, gp)
                pv[j] = pj - h
                lme_grad(c, pv, gm)
                pv[j] = pj
                var i = 0usize
                while i < np {
                    hs[i * np + j] = (gp[i] - gm[i]) / (2.0f64 * h)
                    i += 1usize
                }
                j += 1usize
            }
            var i = 0usize
            while i < np {
                j = 0usize
                while j < i {
                    let m = (hs[i * np + j] + hs[j * np + i]) / 2.0f64
                    hs[i * np + j] = m
                    hs[j * np + i] = m
                    j += 1usize
                }
                i += 1usize
            }
            if !ps.invert(a, hs, np, hi) { break }
            var big = 0.0f64
            i = 0usize
            while i < np {
                var sv = 0.0f64
                j = 0usize
                while j < np {
                    sv += hi[i * np + j] * gr[j]
                    j += 1usize
                }
                pn[i] = pv[i] - sv
                if sv < 0.0f64 { sv = 0.0f64 - sv }
                if sv > big { big = sv }
                i += 1usize
            }
            if g.obj(c, pn) > g.obj(c, pv) + 1.0e-13f64 { break }
            i = 0usize
            while i < np {
                pv[i] = pn[i]
                i += 1usize
            }
            if big < 1.0e-7f64 { break }
            it += 1usize
        }
    }
    mem.reset(a, st)
}

// full log-likelihood (sigma explicit) at th = (log sd and correlation logit of the random effects, correlation and variance
// parameters, log sigma): the parametrisation of nlme's lmeApVar. Built from the profile fit g.core at the equivalent
// log-Cholesky parameters
fn ll_full(c: *g.Ctx, th: []const f64) -> f64 {
    let s = &c.s
    let q = s.q
    let nr = g.nre(s)
    let bt = th.len - 1usize
    let ls = th[bt]
    let st = mem.mark(c.a)
    let (par, e1) = mem.alloc[f64](c.a, bt + 1usize)
    let (coef, e2) = mem.alloc[f64](c.a, s.p)
    let (xi, e3) = mem.alloc[f64](c.a, s.p * s.p)
    var v = 0.0f64 - 1.0e300f64
    if e1 == ok && e2 == ok && e3 == ok {
        if q == 1usize {
            par[0usize] = th[0usize] - ls
        } else {
            let ex = math.exp[f64](th[2usize])
            let r = (ex - 1.0f64) / (ex + 1.0f64)
            let sg = math.exp[f64](ls)
            let sd2 = math.exp[f64](th[1usize])
            par[0usize] = th[0usize] - ls
            par[1usize] = r * sd2 / sg
            par[2usize] = th[1usize] + 0.5f64 * math.log[f64](1.0f64 - r * r) - ls
        }
        var i = nr
        while i < bt {
            par[i] = th[i]
            i += 1usize
        }
        let f = g.core(c.a, s, par[0usize..bt], coef, xi)
        if f.good {
            let nobs = f64(s.n) - f64(s.p) * g.if_reml(s.reml)
            let s2 = f.sigma * f.sigma
            let two_pi = 2.0f64 * 3.141592653589793f64
            let lc = 0.0f64 - 2.0f64 * (f.loglik + nobs / 2.0f64 * math.log[f64](two_pi * s2) + nobs / 2.0f64)
            let sig2 = math.exp[f64](2.0f64 * ls)
            v = 0.0f64 - nobs / 2.0f64 * math.log[f64](two_pi * sig2) - lc / 2.0f64 - s2 * nobs / (2.0f64 * sig2)
        }
    }
    mem.reset(c.a, st)
    ret v
}

// central-difference Hessian of ll_full at step h (per coordinate); out is P by P
fn hess_level(c: *g.Ctx, th: []const f64, hh: []const f64, f0: f64, w: []f64, out: []f64) {
    let np = th.len
    var i = 0usize
    while i < np {
        w[i] = th[i]
        i += 1usize
    }
    i = 0usize
    while i < np {
        w[i] = th[i] + hh[i]
        let fp = ll_full(c, w)
        w[i] = th[i] - hh[i]
        let fm = ll_full(c, w)
        w[i] = th[i]
        out[i * np + i] = (fp - 2.0f64 * f0 + fm) / (hh[i] * hh[i])
        var j = i + 1usize
        while j < np {
            w[i] = th[i] + hh[i]
            w[j] = th[j] + hh[j]
            let fpp = ll_full(c, w)
            w[j] = th[j] - hh[j]
            let fpm = ll_full(c, w)
            w[i] = th[i] - hh[i]
            let fmm = ll_full(c, w)
            w[j] = th[j] + hh[j]
            let fmp = ll_full(c, w)
            w[i] = th[i]
            w[j] = th[j]
            let m = (fpp - fpm - fmp + fmm) / (4.0f64 * hh[i] * hh[j])
            out[i * np + j] = m
            out[j * np + i] = m
            j += 1usize
        }
        i += 1usize
    }
}

// Hessian of ll_full: central differences at steps h, h/2, h/4 (h = 0.02 (1 + |th|)), extrapolated twice
fn ll_hessian(a: *mem.Arena, c: *g.Ctx, th: []const f64, out: []f64) -> err {
    let np = th.len
    let (hh, e1) = mem.alloc[f64](a, np)
    let (w, e2) = mem.alloc[f64](a, np)
    let (d0, e3) = mem.alloc[f64](a, np * np)
    let (d1, e4) = mem.alloc[f64](a, np * np)
    let (d2, e5) = mem.alloc[f64](a, np * np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret g.Singular }
    let f0 = ll_full(c, th)
    var s = 0usize
    while s < 3usize {
        var i = 0usize
        while i < np {
            var ab = th[i]
            if ab < 0.0f64 { ab = 0.0f64 - ab }
            hh[i] = 0.02f64 * (1.0f64 + ab) / math.pow[f64](2.0f64, f64(s))
            i += 1usize
        }
        if s == 0usize { hess_level(c, th, hh, f0, w, d0) }
        if s == 1usize { hess_level(c, th, hh, f0, w, d1) }
        if s == 2usize { hess_level(c, th, hh, f0, w, d2) }
        s += 1usize
    }
    var k = 0usize
    while k < np * np {
        out[k] = (16.0f64 * (4.0f64 * d2[k] - d1[k]) / 3.0f64 - (4.0f64 * d1[k] - d0[k]) / 3.0f64) / 15.0f64
        k += 1usize
    }
    ret ok
}

// denominator degrees of freedom of the fixed effects (nlme getFixDF, one grouping level): columns constant over the whole data
// are intercepts; the others sit in the group stratum (constant inside every group) or the residual stratum
fn fix_df(s: *const g.Spec, df: []f64) {
    let n = s.n
    let p = s.p
    var df0 = f64(s.ng)
    var df1 = f64(n) - f64(s.ng)
    var inner: [64]bool = zero
    var cst: [64]bool = zero
    var j = 0usize
    var anyc = false
    while j < p {
        let x0 = s.x[j * n]
        var allc = true
        var i = 1usize
        while i < n {
            var dv = s.x[j * n + i] - x0
            if x0 != 0.0f64 { dv = s.x[j * n + i] / x0 - 1.0f64 }
            if dv < 0.0f64 { dv = 0.0f64 - dv }
            if dv >= 1.0e-8f64 { allc = false }
            i += 1usize
        }
        cst[j] = allc
        if allc { anyc = true }
        var st = 0usize
        var gi = 0usize
        var vary = false
        while gi < s.ng {
            let m = usize(s.gs[gi])
            i = 1usize
            while i < m {
                if s.x[j * n + st + i] != s.x[j * n + st] { vary = true }
                i += 1usize
            }
            st += m
            gi += 1usize
        }
        inner[j] = vary
        j += 1usize
    }
    j = 0usize
    while j < p {
        if !cst[j] {
            if inner[j] { df1 -= 1.0f64 } else { df0 -= 1.0f64 }
        }
        j += 1usize
    }
    if anyc {
        df0 -= 1.0f64
    } else {
        df1 += 1.0f64
    }
    var mx = df0
    if df1 > mx { mx = df1 }
    j = 0usize
    while j < p {
        df[j] = mx
        if !cst[j] {
            df[j] = df0
            if inner[j] { df[j] = df1 }
        }
        j += 1usize
    }
}

// natural parameters at th: sds, random-effect correlation, then the correlation and variance parameters, then sigma
fn th_natural(a: *mem.Arena, s: *const g.Spec, th: []const f64, out: []f64) -> err {
    let q = s.q
    let nr = g.nre(s)
    let bt = th.len - 1usize
    var o = 0usize
    var k = 0usize
    while k < q {
        out[o] = math.exp[f64](th[k])
        o += 1usize
        k += 1usize
    }
    if q == 2usize {
        let ex = math.exp[f64](th[2usize])
        out[o] = (ex - 1.0f64) / (ex + 1.0f64)
        o += 1usize
    }
    let (tmp, e1) = mem.alloc[f64](a, g.out_len(s) + 1usize)
    if e1 != ok { ret e1 }
    let nat = g.natural(s, th[nr..bt], tmp)
    k = 0usize
    while k < nat {
        out[o + k] = tmp[k]
        k += 1usize
    }
    o += nat
    out[o] = math.exp[f64](th[bt])
    ret ok
}

fn lme_fit(a: *mem.Arena, s: g.Spec, out: []f64) -> err {
    let n = s.n
    let p = s.p
    let q = s.q
    let nr = g.nre(&s)
    let nc = g.ncor(&s)
    let np = nr + nc + g.nvar(&s)
    let (par, e1) = mem.alloc[f64](a, np + 1usize)
    let (coef, e2) = mem.alloc[f64](a, p)
    let (xi, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    let pv = par[0usize..np]
    var i = 0usize
    while i < np {
        pv[i] = 0.0f64
        i += 1usize
    }
    g.start_pars(&s, pv[nr..np])
    let nobs = f64(n) - f64(p) * g.if_reml(s.reml)
    let cst = nobs * (math.log[f64](nobs) - (1.0f64 + math.log[f64](2.0f64 * 3.141592653589793f64))) / 2.0f64
    var c = g.Ctx { a: a, s: s, cst: cst }
    var ctl: [6]f64 = zero
    ctl[0usize] = 400.0f64
    ctl[1usize] = 150.0f64
    ctl[2usize] = 0.0f64
    ctl[3usize] = 1.0e-12f64
    ctl[4usize] = 1.0e-9f64
    ctl[5usize] = 1.0e-12f64
    let r = nlb.nlminb[g.Ctx](a, &c, g.obj, lme_grad, true, pv, ctl[0usize..6usize])
    if r.iterations == 0usize && r.fevals == 0usize { ret g.Singular }
    lme_polish(a, &c, pv)
    let f = g.core(a, &s, pv, coef, xi)
    if !f.good { ret g.Singular }
    var j = 0usize
    while j < p {
        out[j] = coef[j]
        j += 1usize
    }
    out[p] = f.sigma
    out[p + 1usize] = f.loglik
    let npar = f64(p + np + 1usize)
    out[p + 2usize] = 0.0f64 - 2.0f64 * f.loglik + 2.0f64 * npar
    out[p + 3usize] = 0.0f64 - 2.0f64 * f.loglik + npar * math.log[f64](nobs)
    var o = p + 4usize
    var d: [64]f64 = zero
    g.re_cov(q, pv[0usize..nr], d[0usize..64usize])
    var k = 0usize
    while k < q {
        out[o + k] = f.sigma * math.sqrt[f64](d[k * q + k])
        k += 1usize
    }
    o += q
    var l = 0usize
    while l < q {
        k = l + 1usize
        while k < q {
            out[o] = d[k * q + l] / math.sqrt[f64](d[k * q + k] * d[l * q + l])
            o += 1usize
            k += 1usize
        }
        l += 1usize
    }
    // natural correlation and variance parameters: gls_fit's own conversions on the tail of the parameter vector
    let (tmp, e4) = mem.alloc[f64](a, g.out_len(&s) + 1usize)
    if e4 != ok { ret e4 }
    let nat = g.natural(&s, pv[nr..np], tmp)
    k = 0usize
    while k < nat {
        out[o + k] = tmp[k]
        k += 1usize
    }
    o += nat
    // standard errors of the fixed effects
    j = 0usize
    while j < p {
        out[o + j] = f.sigma * math.sqrt[f64](xi[j * p + j])
        j += 1usize
    }
    o += p
    // BLUPs b_i = D Z_i' V_i^-1 (y_i - X_i beta)
    let (v, e5) = mem.alloc[f64](a, n * n)
    let (vi, e6) = mem.alloc[f64](a, n * n)
    let (sd, e7) = mem.alloc[f64](a, n)
    if e5 != ok || e6 != ok || e7 != ok { ret e5 }
    g.fill_corr(&s, pv[nr..nr + nc], v)
    g.fill_sd(&s, pv[nr + nc..np], sd)
    i = 0usize
    while i < n {
        j = 0usize
        while j < n {
            v[i * n + j] = v[i * n + j] * sd[i] * sd[j]
            j += 1usize
        }
        i += 1usize
    }
    g.add_re(&s, pv[0usize..nr], v)
    if !ps.invert(a, v, n, vi) { ret g.Singular }
    var st = 0usize
    var gi = 0usize
    while gi < s.ng {
        let m = usize(s.gs[gi])
        var a1 = 0usize
        while a1 < q {
            var tot = 0.0f64
            var b1 = 0usize
            while b1 < q {
                // (D Z_i')_{a1,row} summed with V_i^-1 resid: tot += D[a1,b1] * sum_rows Z[b1,row] * (V^-1 resid)[row]
                var zs = 0.0f64
                var r1 = 0usize
                while r1 < m {
                    var vr = 0.0f64
                    var r2 = 0usize
                    while r2 < m {
                        var res = s.y[st + r2]
                        var jj = 0usize
                        while jj < p {
                            res -= s.x[jj * n + st + r2] * coef[jj]
                            jj += 1usize
                        }
                        vr += vi[(st + r1) * n + st + r2] * res
                        r2 += 1usize
                    }
                    zs += s.z[b1 * n + st + r1] * vr
                    r1 += 1usize
                }
                tot += d[a1 * q + b1] * zs
                b1 += 1usize
            }
            out[o + gi * q + a1] = tot
            a1 += 1usize
        }
        st += m
        gi += 1usize
    }
    // intervals: fixed effects (t with the denominator df), then the approximate intervals of intervals.lme(which = "var-cov")
    let ro = o + s.ng * q
    let (df, e8) = mem.alloc[f64](a, p)
    if e8 != ok { ret e8 }
    fix_df(&s, df)
    j = 0usize
    while j < p {
        let tq = nb.qt(0.975f64, df[j], true, false)
        out[ro + j] = coef[j] - tq * out[o - p + j]
        out[ro + p + j] = coef[j] + tq * out[o - p + j]
        j += 1usize
    }
    let vo = ro + 2usize * p
    let mn = vc_len(&s)
    let bt = np + 1usize
    let (th, e9) = mem.alloc[f64](a, bt)
    let (hm, e10) = mem.alloc[f64](a, bt * bt)
    let (hi, e11) = mem.alloc[f64](a, bt * bt)
    let (tw, e12) = mem.alloc[f64](a, bt)
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret e9 }
    k = 0usize
    while k < mn * 2usize {
        out[vo + k] = 0.0f64 / 0.0f64
        k += 1usize
    }
    if q > 2usize { ret ok }
    if q == 1usize {
        th[0usize] = math.log[f64](f.sigma * math.sqrt[f64](d[0usize]))
    } else {
        th[0usize] = math.log[f64](f.sigma * math.sqrt[f64](d[0usize]))
        th[1usize] = math.log[f64](f.sigma * math.sqrt[f64](d[3usize]))
        let rr = d[1usize] / math.sqrt[f64](d[0usize] * d[3usize])
        th[2usize] = math.log[f64]((1.0f64 + rr) / (1.0f64 - rr))
    }
    k = nr
    while k < np {
        th[k] = pv[k]
        k += 1usize
    }
    th[np] = math.log[f64](f.sigma)
    if ll_hessian(a, &c, th, hm) != ok { ret ok }
    k = 0usize
    while k < bt * bt {
        hm[k] = 0.0f64 - hm[k]
        k += 1usize
    }
    if !ps.invert(a, hm, bt, hi) { ret ok }
    let z = dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false)
    k = 0usize
    while k < bt {
        tw[k] = th[k] - z * math.sqrt[f64](hi[k * bt + k])
        k += 1usize
    }
    if th_natural(a, &s, tw, out[vo..vo + mn]) != ok { ret ok }
    k = 0usize
    while k < bt {
        tw[k] = th[k] + z * math.sqrt[f64](hi[k * bt + k])
        k += 1usize
    }
    if th_natural(a, &s, tw, out[vo + mn..vo + 2usize * mn]) != ok { ret ok }
    ret ok
}

// ---------------------------------------------------------------- lmList

// out per group (p + 1 + 3 p values): coef, sigma, se, lower and upper 95% limits; then the pooled sd of lmList
fn lmlist_len(p: usize, ng: usize) -> usize { ret ng * (3usize * p + 1usize + p) + 1usize }

fn lmlist_fit(a: *mem.Arena, n: usize, p: usize, x: []const f64, y: []const f64, gs: []const f64, ng: usize, out: []f64) -> err {
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    let (xi, e2) = mem.alloc[f64](a, p * p)
    let (xty, e3) = mem.alloc[f64](a, p)
    let (cf, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    var st = 0usize
    var gi = 0usize
    var rss_all = 0.0f64
    var df_all = 0.0f64
    var o = 0usize
    while gi < ng {
        let m = usize(gs[gi])
        var j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                var v = 0.0f64
                var i = 0usize
                while i < m {
                    v += x[j * n + st + i] * x[k * n + st + i]
                    i += 1usize
                }
                xtx[j * p + k] = v
                k += 1usize
            }
            var v = 0.0f64
            var i = 0usize
            while i < m {
                v += x[j * n + st + i] * y[st + i]
                i += 1usize
            }
            xty[j] = v
            j += 1usize
        }
        if !ps.invert(a, xtx, p, xi) { ret g.Singular }
        j = 0usize
        while j < p {
            var v = 0.0f64
            var k = 0usize
            while k < p {
                v += xi[j * p + k] * xty[k]
                k += 1usize
            }
            cf[j] = v
            j += 1usize
        }
        var rss = 0.0f64
        var i = 0usize
        while i < m {
            var r = y[st + i]
            j = 0usize
            while j < p {
                r -= x[j * n + st + i] * cf[j]
                j += 1usize
            }
            rss += r * r
            i += 1usize
        }
        let df = f64(m) - f64(p)
        let sig = math.sqrt[f64](rss / df)
        let tq = nb.qt(0.975f64, df, true, false)
        j = 0usize
        while j < p {
            let se = sig * math.sqrt[f64](xi[j * p + j])
            out[o + j] = cf[j]
            out[o + p + 1usize + j] = se
            out[o + 2usize * p + 1usize + j] = cf[j] - tq * se
            out[o + 3usize * p + 1usize + j] = cf[j] + tq * se
            j += 1usize
        }
        out[o + p] = sig
        o += 4usize * p + 1usize
        rss_all += rss
        df_all += df
        st += m
        gi += 1usize
    }
    out[o] = math.sqrt[f64](rss_all / df_all)
    ret ok
}

// ---------------------------------------------------------------- self-start models

// 1 SSlogis(Asym, xmid, scal), 2 SSasymp(Asym, R0, lrc), 3 SSmicmen(Vm, K), 4 SSfpl(A, B, xmid, scal), 5 SSgompertz(Asym, b2, b3)
fn ss_np(kind: i64) -> usize {
    if kind == 3i64 { ret 2usize }
    if kind == 4i64 { ret 4usize }
    ret 3usize
}

// value of the model; gr receives the gradient with respect to the parameters
fn ss_eval(kind: i64, x: f64, par: []const f64, gr: []f64) -> f64 {
    if kind == 1i64 {
        let e = math.exp[f64]((par[1usize] - x) / par[2usize])
        let den = 1.0f64 + e
        gr[0usize] = 1.0f64 / den
        gr[1usize] = 0.0f64 - par[0usize] * e / (par[2usize] * den * den)
        gr[2usize] = par[0usize] * e * (par[1usize] - x) / (par[2usize] * par[2usize] * den * den)
        ret par[0usize] / den
    }
    if kind == 2i64 {
        let rc = math.exp[f64](par[2usize])
        let e = math.exp[f64](0.0f64 - rc * x)
        gr[0usize] = 1.0f64 - e
        gr[1usize] = e
        gr[2usize] = (par[1usize] - par[0usize]) * e * (0.0f64 - rc * x)
        ret par[0usize] + (par[1usize] - par[0usize]) * e
    }
    if kind == 3i64 {
        let den = par[1usize] + x
        gr[0usize] = x / den
        gr[1usize] = 0.0f64 - par[0usize] * x / (den * den)
        ret par[0usize] * x / den
    }
    if kind == 4i64 {
        let e = math.exp[f64]((par[2usize] - x) / par[3usize])
        let den = 1.0f64 + e
        let dd = par[1usize] - par[0usize]
        gr[0usize] = 1.0f64 - 1.0f64 / den
        gr[1usize] = 1.0f64 / den
        gr[2usize] = 0.0f64 - dd * e / (par[3usize] * den * den)
        gr[3usize] = dd * e * (par[2usize] - x) / (par[3usize] * par[3usize] * den * den)
        ret par[0usize] + dd / den
    }
    let t = math.pow[f64](par[2usize], x)
    let e = math.exp[f64](0.0f64 - par[1usize] * t)
    gr[0usize] = e
    gr[1usize] = 0.0f64 - par[0usize] * e * t
    gr[2usize] = 0.0f64 - par[0usize] * e * par[1usize] * x * math.pow[f64](par[2usize], x - 1.0f64)
    ret par[0usize] * e
}

type Nls = struct { kind: i64, n: usize, x: []const f64, y: []const f64 }

fn nls_resid(c: *Nls, par: []const f64, fv: []f64) {
    var gr: [4]f64 = zero
    var i = 0usize
    while i < c.n {
        fv[i] = c.y[i] - ss_eval(c.kind, c.x[i], par, gr[0usize..4usize])
        i += 1usize
    }
}

fn nls_jac(c: *Nls, par: []const f64, fj: []f64) {
    var gr: [4]f64 = zero
    let np = ss_np(c.kind)
    var i = 0usize
    while i < c.n {
        let v = ss_eval(c.kind, c.x[i], par, gr[0usize..4usize])
        var j = 0usize
        while j < np {
            fj[j * c.n + i] = 0.0f64 - gr[j]
            j += 1usize
        }
        i += 1usize
    }
}

// straight line through (u, w): intercept and slope
fn line(u: []const f64, w: []const f64, m: usize, ab: []f64) {
    var su = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < m {
        su += u[i]
        sw += w[i]
        i += 1usize
    }
    let mu = su / f64(m)
    let mw = sw / f64(m)
    var suu = 0.0f64
    var suw = 0.0f64
    i = 0usize
    while i < m {
        suu += (u[i] - mu) * (u[i] - mu)
        suw += (u[i] - mu) * (w[i] - mw)
        i += 1usize
    }
    ab[1usize] = suw / suu
    ab[0usize] = mw - ab[1usize] * mu
}

// starting values: a linearising regression for each model (positive, increasing data for logistic, fpl and Gompertz)
fn ss_start(a: *mem.Arena, kind: i64, n: usize, x: []const f64, y: []const f64, par: []f64) -> err {
    let (u, e1) = mem.alloc[f64](a, n)
    let (w, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret e1 }
    var ab: [2]f64 = zero
    var ymax = y[0usize]
    var ymin = y[0usize]
    var xmax = x[0usize]
    var xmin = x[0usize]
    var ylast = y[0usize]
    var yfirst = y[0usize]
    var i = 1usize
    while i < n {
        if y[i] > ymax { ymax = y[i] }
        if y[i] < ymin { ymin = y[i] }
        if x[i] > xmax {
            xmax = x[i]
            ylast = y[i]
        }
        if x[i] < xmin {
            xmin = x[i]
            yfirst = y[i]
        }
        i += 1usize
    }
    if kind == 1i64 {
        let asym = 1.05f64 * ymax
        var m = 0usize
        i = 0usize
        while i < n {
            let z = y[i] / asym
            if z > 0.0f64 && z < 1.0f64 {
                u[m] = x[i]
                w[m] = math.log[f64](z / (1.0f64 - z))
                m += 1usize
            }
            i += 1usize
        }
        line(u, w, m, ab[0usize..2usize])
        par[0usize] = asym
        par[1usize] = 0.0f64 - ab[0usize] / ab[1usize]
        par[2usize] = 1.0f64 / ab[1usize]
    } else if kind == 2i64 {
        let asym = ylast + 0.1f64 * (ylast - yfirst)
        var sgn = 1.0f64
        if yfirst < asym { sgn = 0.0f64 - 1.0f64 }
        i = 0usize
        while i < n {
            u[i] = x[i]
            w[i] = math.log[f64](math.abs[f64](y[i] - asym))
            i += 1usize
        }
        line(u, w, n, ab[0usize..2usize])
        par[0usize] = asym
        par[1usize] = asym - sgn * math.exp[f64](ab[0usize])
        par[2usize] = math.log[f64](0.0f64 - ab[1usize])
    } else if kind == 3i64 {
        i = 0usize
        while i < n {
            u[i] = 1.0f64 / x[i]
            w[i] = 1.0f64 / y[i]
            i += 1usize
        }
        line(u, w, n, ab[0usize..2usize])
        par[0usize] = 1.0f64 / ab[0usize]
        par[1usize] = ab[1usize] / ab[0usize]
    } else if kind == 4i64 {
        let lo = ymin - 0.1f64 * (ymax - ymin)
        let hi = ymax + 0.1f64 * (ymax - ymin)
        var m = 0usize
        i = 0usize
        while i < n {
            let z = (y[i] - lo) / (hi - lo)
            if z > 0.0f64 && z < 1.0f64 {
                u[m] = x[i]
                w[m] = math.log[f64](z / (1.0f64 - z))
                m += 1usize
            }
            i += 1usize
        }
        line(u, w, m, ab[0usize..2usize])
        par[0usize] = lo
        par[1usize] = hi
        par[2usize] = 0.0f64 - ab[0usize] / ab[1usize]
        par[3usize] = 1.0f64 / ab[1usize]
    } else {
        let asym = 1.05f64 * ymax
        var m = 0usize
        i = 0usize
        while i < n {
            let z = y[i] / asym
            if z > 0.0f64 && z < 1.0f64 {
                u[m] = x[i]
                w[m] = math.log[f64](0.0f64 - math.log[f64](z))
                m += 1usize
            }
            i += 1usize
        }
        line(u, w, m, ab[0usize..2usize])
        par[0usize] = asym
        par[1usize] = math.exp[f64](ab[0usize])
        par[2usize] = math.exp[f64](ab[1usize])
    }
    ret ok
}

// out: par (np), sigma, residual sum of squares, logLik, AIC, BIC, se (np)
fn nls_len(kind: i64) -> usize { ret 2usize * ss_np(kind) + 5usize }

fn nls_fit(a: *mem.Arena, kind: i64, n: usize, x: []const f64, y: []const f64, out: []f64) -> err {
    let np = ss_np(kind)
    let (par, e1) = mem.alloc[f64](a, np)
    let (lo, e2) = mem.alloc[f64](a, np)
    let (hi, e3) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    let se0 = ss_start(a, kind, n, x, y, par)
    if se0 != ok { ret se0 }
    var i = 0usize
    while i < np {
        lo[i] = 0.0f64 - 1.0e300f64
        hi[i] = 1.0e300f64
        i += 1usize
    }
    var c = Nls { kind: kind, n: n, x: x, y: y }
    let (ft, fe) = lm.nls_lm_der[Nls](a, nls_resid, nls_jac, &c, n, np, par, lo, hi, 1.0e-15f64, 1.0e-15f64, 1.0e-15f64, 5000i64, 5000i64)
    if fe != ok { ret fe }
    // J'J at the optimum
    let (jf, e4) = mem.alloc[f64](a, n * np)
    let (jj, e5) = mem.alloc[f64](a, np * np)
    let (ji, e6) = mem.alloc[f64](a, np * np)
    if e4 != ok || e5 != ok || e6 != ok { ret e4 }
    nls_jac(&c, par, jf)
    var j = 0usize
    while j < np {
        var k = 0usize
        while k < np {
            var v = 0.0f64
            i = 0usize
            while i < n {
                v += jf[j * n + i] * jf[k * n + i]
                i += 1usize
            }
            jj[j * np + k] = v
            k += 1usize
        }
        j += 1usize
    }
    if !ps.invert(a, jj, np, ji) { ret g.Singular }
    var gr: [4]f64 = zero
    var rss = 0.0f64
    i = 0usize
    while i < n {
        let r = y[i] - ss_eval(kind, x[i], par, gr[0usize..4usize])
        rss += r * r
        i += 1usize
    }
    let nf = f64(n)
    let sig = math.sqrt[f64](rss / (nf - f64(np)))
    let ll = 0.0f64 - nf / 2.0f64 * (math.log[f64](2.0f64 * 3.141592653589793f64) + 1.0f64 - math.log[f64](nf) + math.log[f64](rss))
    j = 0usize
    while j < np {
        out[j] = par[j]
        out[np + 5usize + j] = sig * math.sqrt[f64](ji[j * np + j])
        j += 1usize
    }
    out[np] = sig
    out[np + 1usize] = rss
    out[np + 2usize] = ll
    out[np + 3usize] = 0.0f64 - 2.0f64 * ll + 2.0f64 * f64(np + 1usize)
    out[np + 4usize] = 0.0f64 - 2.0f64 * ll + math.log[f64](nf) * f64(np + 1usize)
    ret ok
}
