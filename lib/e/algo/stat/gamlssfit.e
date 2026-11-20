// R gamlss gamlss(): the RS (Rigby-Stasinopoulos), CG (Cole-Green) and mixed fitting algorithms for models whose parameters are linear
// in a given design matrix (no smoothers), on the families NO, GA, PO, WEI and BCCG with the identity, log and other links of e.algo.stat.gamlsslink.
// A port of RS, CG, mixed and glim.fit of gamlss 5.5-5, with lm.wfit as the weighted least squares step.
//
// Not here: the pb, cs, lo and ga smoothers, the other families, centiles(), lms, stepGAIC, the worm plot and the output methods.

use e.algo.stat as st
use e.algo.stat.gamlssdist as gd
use e.algo.stat.gamlsslink as gl
use e.algo.stat.massrlm as mr
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.special as sp
use e.mem
use e.algo.stat.gamlsssmooth as sm

error BadInput

// families: 0 NO, 1 GA, 2 PO, 3 WEI, 4 BCCG
fn npar(fam: usize) -> usize {
    if fam == 2usize { ret 1usize }
    if fam == 4usize { ret 3usize }
    ret 2usize
}

fn lg(x: f64) -> f64 { ret math.log[f64](x) }

// the first derivative of the log-likelihood with respect to parameter k (the family's dldm, dldd, dldv)
fn dl(fam: usize, k: usize, y: f64, m: f64, s: f64, v: f64) -> f64 {
    if fam == 0usize {
        if k == 0usize { ret (1.0f64 / (s * s)) * (y - m) }
        ret ((y - m) * (y - m) - s * s) / math.pow[f64](s, 3.0f64)
    }
    if fam == 1usize {
        if k == 0usize { ret (y - m) / ((s * s) * (m * m)) }
        ret (2.0f64 / math.pow[f64](s, 3.0f64)) * ((y / m) - lg(y) + lg(m) + lg(s * s) - 1.0f64 + st.digamma(1.0f64 / (s * s)))
    }
    if fam == 2usize { ret (y - m) / m }
    if fam == 3usize {
        if k == 0usize { ret (math.pow[f64](y / m, s) - 1.0f64) * (s / m) }
        ret 1.0f64 / s - lg(y / m) * (math.pow[f64](y / m, s) - 1.0f64)
    }
    var z = lg(y / m) / s
    if v != 0.0f64 { z = (math.pow[f64](y / m, v) - 1.0f64) / (v * s) }
    if k == 0usize { ret ((z / s) + v * (z * z - 1.0f64)) / m }
    let h = dist.dnorm(1.0f64 / (s * math.abs[f64](v)), 0.0f64, 1.0f64, false) / dist.pnorm(1.0f64 / (s * math.abs[f64](v)), 0.0f64, 1.0f64, true, false)
    if k == 1usize { ret (z * z - 1.0f64) / s + h / (s * s * math.abs[f64](v)) }
    let l = lg(y / m)
    var sg = 0.0f64
    if v > 0.0f64 { sg = 1.0f64 }
    if v < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    var d = (z - (l / s)) * (z / v) - l * (z * z - 1.0f64)
    d = d + sg * h / (s * v * v)
    ret d
}

// the second derivative d2l/dp2 of parameter k
fn d2l(fam: usize, k: usize, y: f64, m: f64, s: f64, v: f64) -> f64 {
    if fam == 0usize {
        if k == 0usize { ret 0.0f64 - (1.0f64 / (s * s)) }
        ret 0.0f64 - (2.0f64 / (s * s))
    }
    if fam == 1usize {
        if k == 0usize { ret (0.0f64 - 1.0f64) / ((s * s) * (m * m)) }
        ret (4.0f64 / math.pow[f64](s, 4.0f64)) - (4.0f64 / math.pow[f64](s, 6.0f64)) * st.trigamma(1.0f64 / (s * s))
    }
    if fam == 2usize { ret (0.0f64 - 1.0f64) / m }
    if fam == 3usize {
        if k == 0usize { ret (0.0f64 - s * s) / (m * m) }
        ret (0.0f64 - 1.82368f64) / (s * s)
    }
    if k == 0usize {
        let a = 0.0f64 - (1.0f64 + 2.0f64 * v * v * s * s)
        ret a / (m * m * s * s)
    }
    if k == 1usize { ret (0.0f64 - 2.0f64) / (s * s) }
    ret (0.0f64 - 7.0f64) * s * s / 4.0f64
}

// the cross derivative d2l/(dp_j dp_k), j < k
fn d2x(fam: usize, j: usize, k: usize, y: f64, m: f64, s: f64, v: f64) -> f64 {
    if fam == 3usize { if j == 0usize && k == 1usize { ret 0.422784f64 / m } }
    if fam == 4usize {
        if j == 0usize && k == 1usize { ret (0.0f64 - 2.0f64) * v / (m * s) }
        if j == 0usize && k == 2usize { ret 1.0f64 / (2.0f64 * m) }
        if j == 1usize && k == 2usize { ret (0.0f64 - s) * v }
    }
    ret 0.0f64
}

// the global deviance increment -2 log f(y)
fn di(fam: usize, y: f64, m: f64, s: f64, v: f64) -> f64 {
    if fam == 0usize { ret (0.0f64 - 2.0f64) * dist.dnorm(y, m, s, true) }
    if fam == 1usize {
        let s2 = s * s
        let ll = (1.0f64 / s2) * lg(y / (m * s2)) - y / (m * s2) - lg(y) - sp.lgamma(1.0f64 / s2)
        ret (0.0f64 - 2.0f64) * ll
    }
    if fam == 2usize { ret (0.0f64 - 2.0f64) * nm.dpois(y, m, true) }
    if fam == 3usize { ret (0.0f64 - 2.0f64) * dist.dweibull(y, s, m, true) }
    var z = lg(y / m) / s
    if v != 0.0f64 { z = (math.pow[f64](y / m, v) - 1.0f64) / (v * s) }
    var ll = v * lg(y / m) - lg(s) - (z * z) / 2.0f64 - lg(y) - (lg(2.0f64 * gd.pi())) / 2.0f64
    ll = ll - lg(dist.pnorm(1.0f64 / (s * math.abs[f64](v)), 0.0f64, 1.0f64, true, false))
    ret (0.0f64 - 2.0f64) * ll
}

fn mean_of(x: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i]
        i += 1usize
    }
    let m = s / f64(n)
    var t = 0.0f64
    i = 0usize
    while i < n {
        t += x[i] - m
        i += 1usize
    }
    ret m + t / f64(n)
}

fn var_of(x: []const f64, n: usize) -> f64 {
    let m = mean_of(x, n)
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / f64(n - 1usize)
}

// the family's initial value for parameter k, written to out (length n)
fn initial(fam: usize, k: usize, y: []const f64, n: usize, out: []f64) {
    let my = mean_of(y, n)
    var i = 0usize
    if fam == 3usize {
        var sum = 0.0f64
        var tmp = 0.0f64
        i = 0usize
        while i < n {
            sum += lg(y[i])
            i += 1usize
        }
        let ml = sum / f64(n)
        i = 0usize
        while i < n {
            tmp += (lg(y[i]) - ml) * (lg(y[i]) - ml)
            i += 1usize
        }
        let lv = tmp / f64(n - 1usize)
        let sds = 1.283f64 / math.sqrt[f64](lv)
        i = 0usize
        while i < n {
            if k == 0usize { out[i] = math.exp[f64](lg(y[i]) + 0.5772f64 / sds) } else { out[i] = sds }
            i += 1usize
        }
        ret
    }
    i = 0usize
    while i < n {
        var v = 0.0f64
        if k == 0usize { v = (y[i] + my) / 2.0f64 }
        if k == 1usize {
            if fam == 0usize { v = math.sqrt[f64](var_of(y, n)) }
            if fam == 1usize { v = 1.0f64 }
            if fam == 4usize { v = 0.1f64 }
        }
        if k == 2usize { v = 0.5f64 }
        out[i] = v
        i += 1usize
    }
}

type Ctx = struct {
    a: *mem.Arena,
    fam: usize,
    n: usize,
    np: usize,
    y: []const f64,
    w: []const f64,
    xs: []const f64,
    xoff: []usize,
    ncol: []const usize,
    link: []const usize,
    step: []const f64,
    off: []const f64,
    par: []f64,
    eta: []f64,
    wv: []f64,
    wt: []f64,
    coef: []f64,
    coff: []usize,
    c_crit: f64,
    i_cc: f64,
    i_cyc: usize,
    autostep: bool,
    smo: []sm.Smo,
    soff: []usize,
    ss: []f64,
    sold: []f64,
    sdf: []f64,
    slam: []f64,
    nldf: []f64,
    pen: []f64,
    bf_cyc: usize,
    bf_tol: f64,
    eta_o: []f64,
    ss_o: []f64,
}

type Out = struct {
    coef: []f64,
    par: []f64,
    eta: []f64,
    wv: []f64,
    wt: []f64,
    gdev: f64,
    iter: usize,
    conv: bool,
    df: f64,
    pen: f64,
    nl: f64,
    ss: []f64,
    slam: []f64,
    sdf: []f64,
    nldf: []f64,
    penk: []f64,
}

fn at(c: *const Ctx, k: usize, i: usize) -> f64 { ret c.par[k * c.n + i] }

fn inc(c: *const Ctx, i: usize) -> f64 {
    ret di(c.fam, c.y[i], c.par[i], c.par[c.n + i], c.par[2usize * c.n + i])
}

fn gdev(c: *const Ctx) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < c.n {
        s += c.w[i] * inc(c, i)
        i += 1usize
    }
    ret s
}

fn pscore(c: *const Ctx, k: usize, i: usize) -> f64 {
    ret dl(c.fam, k, c.y[i], c.par[i], c.par[c.n + i], c.par[2usize * c.n + i])
}

fn pscore2(c: *const Ctx, k: usize, i: usize) -> f64 {
    ret d2l(c.fam, k, c.y[i], c.par[i], c.par[c.n + i], c.par[2usize * c.n + i])
}

fn pcross(c: *const Ctx, j: usize, k: usize, i: usize) -> f64 {
    ret d2x(c.fam, j, k, c.y[i], c.par[i], c.par[c.n + i], c.par[2usize * c.n + i])
}

// lm.wfit with the residuals returned
fn wls2(c: *Ctx, k: usize, z: []const f64, wt: []const f64, fit: []f64, resid: []f64) -> err {
    let n = c.n
    let p = c.ncol[k]
    let ce = mr.wfit(c.a, c.xs[c.xoff[k]..c.xoff[k] + n * p], n, p, z, wt, c.coef[c.coff[k]..c.coff[k] + p], resid)
    if ce != ok { ret ce }
    var i = 0usize
    while i < n {
        fit[i] = z[i] - resid[i]
        i += 1usize
    }
    ret ok
}

fn wmean2(x: []const f64, w: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        s += w[i] * x[i]
        sw += w[i]
        i += 1usize
    }
    ret s / sw
}

// additive.fit for parameter k: s is the n by (its smoothers) matrix of smooth terms, updated; fit gets the linear predictor without the offset
fn additive(c: *Ctx, k: usize, wv: []const f64, w: []const f64, s: []f64, maxit: usize, fit: []f64) -> err {
    let n = c.n
    let sb = c.soff[k]
    let ns = c.soff[k + 1usize] - sb
    let start = mem.mark(c.a)
    let (res, e1) = mem.alloc[f64](c.a, n + 1usize)
    let (z, e2) = mem.alloc[f64](c.a, n)
    let (fp, e3) = mem.alloc[f64](c.a, n)
    let (r2, e4) = mem.alloc[f64](c.a, n + 1usize)
    let (fv, e5) = mem.alloc[f64](c.a, n)
    let (dd, e6) = mem.alloc[f64](c.a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var rs = 0.0f64
        var j = 0usize
        while j < ns {
            rs += s[j * n + i]
            j += 1usize
        }
        res[i] = wv[i] - rs
        fp[i] = 0.0f64
        i += 1usize
    }
    var ratio = c.bf_tol + 1.0f64
    var nit = 0usize
    while ratio > c.bf_tol && nit < maxit {
        nit += 1usize
        i = 0usize
        while i < n {
            z[i] = res[i] + fp[i]
            i += 1usize
        }
        let we = wls2(c, k, z, w, fp, r2)
        if we != ok { ret we }
        i = 0usize
        while i < n {
            res[i] = r2[i]
            i += 1usize
        }
        var deltaf = 0.0f64
        var j = 0usize
        while j < ns {
            i = 0usize
            while i < n {
                z[i] = res[i] + s[j * n + i]
                i += 1usize
            }
            let (nl, lam, fe) = sm.smo_fit(c.a, &c.smo[sb + j], z, w, fv)
            if fe != ok { ret fe }
            c.sdf[sb + j] = nl
            c.slam[sb + j] = lam
            i = 0usize
            while i < n {
                res[i] = z[i] - fv[i]
                let sn = z[i] - res[i]
                dd[i] = (sn - s[j * n + i]) * (sn - s[j * n + i])
                s[j * n + i] = sn
                i += 1usize
            }
            deltaf += wmean2(dd, w, n)
            j += 1usize
        }
        var den = 0.0f64
        i = 0usize
        while i < n {
            var rs = 0.0f64
            j = 0usize
            while j < ns {
                rs += s[j * n + i]
                j += 1usize
            }
            den += w[i] * rs * rs
            i += 1usize
        }
        ratio = math.sqrt[f64](deltaf / den)
    }
    var tot = 0.0f64
    var j = 0usize
    while j < ns {
        tot += c.sdf[sb + j]
        j += 1usize
    }
    c.nldf[k] = tot
    i = 0usize
    while i < n {
        fit[i] = wv[i] - res[i]
        i += 1usize
    }
    mem.reset(c.a, start)
    ret ok
}

// lm.wfit of the working variable on parameter k's design matrix: the coefficients go to coef, the fitted values to fit
fn wls(c: *Ctx, k: usize, z: []const f64, wt: []const f64, fit: []f64) -> err {
    let n = c.n
    let start = mem.mark(c.a)
    let (resid, e1) = mem.alloc[f64](c.a, n + 1usize)
    if e1 != ok { ret e1 }
    let ce = wls2(c, k, z, wt, fit, resid)
    mem.reset(c.a, start)
    ret ce
}

// the RS inner iteration of glim.fit for parameter k; the fitted values stay in par
fn glim(c: *Ctx, k: usize) -> err {
    let n = c.n
    let (lp, e1) = mem.alloc[f64](c.a, n)
    let (lpold, e2) = mem.alloc[f64](c.a, n)
    let (dr, e3) = mem.alloc[f64](c.a, n)
    let (wtw, e4) = mem.alloc[f64](c.a, n)
    let (fit, e5) = mem.alloc[f64](c.a, n)
    let sb = c.soff[k]
    let ns = c.soff[k + 1usize] - sb
    let (sloc, e6) = mem.alloc[f64](c.a, ns * n + 1usize)
    let (sold, e7) = mem.alloc[f64](c.a, ns * n + 1usize)
    let (sfit, e8) = mem.alloc[f64](c.a, ns * n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    let kind = c.link[k]
    let step = c.step[k]
    var i = 0usize
    while i < ns * n {
        sloc[i] = c.ss[sb * n + i]
        sfit[i] = c.ss[sb * n + i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        c.eta[k * n + i] = gl.linkfun(kind, c.par[k * n + i])
        lp[i] = c.eta[k * n + i]
        dr[i] = 1.0f64 / gl.mu_eta(kind, c.eta[k * n + i])
        i += 1usize
    }
    var dv = gdev(c)
    var olddv = dv + 1.0f64
    i = 0usize
    while i < n {
        var d2 = pscore2(c, k, i)
        if !(d2 < 0.0f64 - 1.0e-15f64) { d2 = 0.0f64 - 1.0e-15f64 }
        var wt = 0.0f64 - (d2 / (dr[i] * dr[i]))
        if wt > 1.0e10f64 { wt = 1.0e10f64 }
        if wt < 1.0e-10f64 { wt = 1.0e-10f64 }
        c.wt[k * n + i] = wt
        c.wv[k * n + i] = (c.eta[k * n + i] - c.off[k * n + i]) + pscore(c, k, i) / (dr[i] * wt)
        i += 1usize
    }
    var itn = 0usize
    while math.abs[f64](olddv - dv) > c.i_cc && itn < c.i_cyc {
        itn += 1usize
        i = 0usize
        while i < n {
            lpold[i] = lp[i]
            wtw[i] = c.wt[k * n + i] * c.w[i]
            i += 1usize
        }
        if ns == 0usize {
            let we = wls(c, k, c.wv[k * n..k * n + n], wtw, fit)
            if we != ok { ret we }
        } else {
            i = 0usize
            while i < ns * n {
                sold[i] = sloc[i]
                sfit[i] = sloc[i]
                i += 1usize
            }
            let we = additive(c, k, c.wv[k * n..k * n + n], wtw, sfit, c.bf_cyc, fit)
            if we != ok { ret we }
            i = 0usize
            while i < ns * n {
                if itn == 1usize { sloc[i] = sfit[i] } else { sloc[i] = step * sfit[i] + (1.0f64 - step) * sold[i] }
                i += 1usize
            }
        }
        i = 0usize
        while i < n {
            if itn == 1usize { lp[i] = fit[i] } else { lp[i] = step * fit[i] + (1.0f64 - step) * lpold[i] }
            c.eta[k * n + i] = lp[i] + c.off[k * n + i]
            c.par[k * n + i] = gl.linkinv(kind, c.eta[k * n + i])
            i += 1usize
        }
        olddv = dv
        dv = gdev(c)
        if dv > olddv && itn >= 2usize && c.autostep {
            var tries = 0usize
            while tries < 5usize {
                tries += 1usize
                i = 0usize
                while i < n {
                    lp[i] = (lp[i] + lpold[i]) / 2.0f64
                    c.eta[k * n + i] = lp[i] + c.off[k * n + i]
                    c.par[k * n + i] = gl.linkinv(kind, c.eta[k * n + i])
                    i += 1usize
                }
                i = 0usize
                while i < ns * n {
                    sloc[i] = (sloc[i] + sold[i]) / 2.0f64
                    i += 1usize
                }
                dv = gdev(c)
                if (olddv - dv) > c.i_cc { tries = 5usize }
            }
        }
        i = 0usize
        while i < n {
            dr[i] = 1.0f64 / gl.mu_eta(kind, c.eta[k * n + i])
            var d2 = pscore2(c, k, i)
            if !(d2 < 0.0f64 - 1.0e-15f64) { d2 = 0.0f64 - 1.0e-15f64 }
            var wt = 0.0f64 - (d2 / (dr[i] * dr[i]))
            if wt > 1.0e10f64 { wt = 1.0e10f64 }
            if wt < 1.0e-10f64 { wt = 1.0e-10f64 }
            c.wt[k * n + i] = wt
            c.wv[k * n + i] = (c.eta[k * n + i] - c.off[k * n + i]) + pscore(c, k, i) / (dr[i] * wt)
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        c.eta_o[k * n + i] = c.eta[k * n + i]
        i += 1usize
    }
    if ns > 0usize {
        i = 0usize
        var pn = 0.0f64
        while i < ns * n {
            c.ss[sb * n + i] = sfit[i]
            c.ss_o[sb * n + i] = sfit[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            pn += c.eta[k * n + i] * c.wt[k * n + i] * (c.wv[k * n + i] - c.eta[k * n + i])
            i += 1usize
        }
        c.pen[k] = pn
    }
    ret ok
}

// RS: the outer loop; returns the iteration count and whether it converged
fn run_rs(c: *Ctx, n_cyc: usize) -> (usize, bool, err) {
    var iter = 0usize
    var g = gdev(c)
    var gold = g + 1.0f64
    while math.abs[f64](gold - g) > c.c_crit && iter < n_cyc {
        var k = 0usize
        while k < c.np {
            let ge = glim(c, k)
            if ge != ok { ret (iter, false, ge) }
            k += 1usize
        }
        gold = g
        g = gdev(c)
        iter += 1usize
    }
    ret (iter, math.abs[f64](gold - g) < c.c_crit, ok)
}

// CG: the outer loop with the inner backfitting-free cycle over the parameters and the cross-derivative adjustment
fn run_cg(c: *Ctx, n_cyc: usize) -> (usize, bool, err) {
    let n = c.n
    let np = c.np
    let (u, e1) = mem.alloc[f64](c.a, 4usize * n)
    let (z, e2) = mem.alloc[f64](c.a, 4usize * n)
    let (dr, e3) = mem.alloc[f64](c.a, 4usize * n)
    let (w1, e4) = mem.alloc[f64](c.a, 4usize * n)
    let (wc, e5) = mem.alloc[f64](c.a, 16usize * n)
    let (eold, e6) = mem.alloc[f64](c.a, 4usize * n)
    let (wv, e7) = mem.alloc[f64](c.a, n)
    let (wtw, e8) = mem.alloc[f64](c.a, n)
    let (fit, e9) = mem.alloc[f64](c.a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (0usize, false, mem.Full) }
    var i = 0usize
    while i < 4usize * n {
        c.eta[i] = 0.0f64
        eold[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < 16usize * n {
        wc[i] = 0.0f64
        i += 1usize
    }
    var iter = 0usize
    var g = gdev(c)
    var gold = g + 1.0f64
    while math.abs[f64](gold - g) > c.c_crit && iter < n_cyc {
        var k = 0usize
        while k < np {
            let kind = c.link[k]
            i = 0usize
            while i < n {
                let e = gl.linkfun(kind, c.par[k * n + i])
                c.eta[k * n + i] = e
                eold[k * n + i] = e
                u[k * n + i] = pscore(c, k, i)
                dr[k * n + i] = 1.0f64 / gl.mu_eta(kind, e)
                w1[k * n + i] = 0.0f64 - pscore2(c, k, i) / (dr[k * n + i] * dr[k * n + i])
                z[k * n + i] = (e - c.off[k * n + i]) + c.step[k] * u[k * n + i] / (dr[k * n + i] * w1[k * n + i])
                var j = 0usize
                while j < k {
                    let cw = 0.0f64 - pcross(c, j, k, i) / (dr[j * n + i] * dr[k * n + i])
                    wc[(j * 4usize + k) * n + i] = cw
                    wc[(k * 4usize + j) * n + i] = cw
                    j += 1usize
                }
                i += 1usize
            }
            k += 1usize
        }
        var gin = g + 1.0f64
        var ig = g
        var iiter = 0usize
        while math.abs[f64](gin - ig) > c.i_cc && iiter < c.i_cyc {
            k = 0usize
            while k < np {
                i = 0usize
                while i < n {
                    var s = 0.0f64
                    var j = 0usize
                    while j < 4usize {
                        if j != k { s += wc[(j * 4usize + k) * n + i] * (c.eta[j * n + i] - eold[j * n + i]) }
                        j += 1usize
                    }
                    wv[i] = z[k * n + i] + (0.0f64 - s) / w1[k * n + i]
                    wtw[i] = w1[k * n + i] * c.w[i]
                    i += 1usize
                }
                let sb = c.soff[k]
                let ns = c.soff[k + 1usize] - sb
                if ns == 0usize {
                    let we = wls(c, k, wv, wtw, fit)
                    if we != ok { ret (iter, false, we) }
                } else {
                    i = 0usize
                    while i < ns * n {
                        c.sold[sb * n + i] = c.ss[sb * n + i]
                        i += 1usize
                    }
                    let we = additive(c, k, wv, wtw, c.ss[sb * n..(sb + ns) * n], 1usize, fit)
                    if we != ok { ret (iter, false, we) }
                }
                var pn = 0.0f64
                i = 0usize
                while i < n {
                    c.eta[k * n + i] = fit[i] + c.off[k * n + i]
                    c.par[k * n + i] = gl.linkinv(c.link[k], c.eta[k * n + i])
                    c.wv[k * n + i] = wv[i]
                    c.wt[k * n + i] = w1[k * n + i]
                    pn += c.eta[k * n + i] * w1[k * n + i] * (wv[i] - c.eta[k * n + i])
                    c.eta_o[k * n + i] = c.eta[k * n + i]
                    i += 1usize
                }
                i = sb * n
                while i < (sb + ns) * n {
                    c.ss_o[i] = c.ss[i]
                    i += 1usize
                }
                if ns > 0usize { c.pen[k] = pn }
                k += 1usize
            }
            gin = ig
            ig = gdev(c)
            iiter += 1usize
        }
        gold = g
        g = gdev(c)
        if g > gold && iter >= 2usize && c.autostep {
            var tries = 0usize
            while tries < 5usize {
                tries += 1usize
                k = 0usize
                while k < np {
                    i = 0usize
                    while i < n {
                        c.eta[k * n + i] = (c.eta[k * n + i] + eold[k * n + i]) / 2.0f64
                        c.par[k * n + i] = gl.linkinv(c.link[k], c.eta[k * n + i])
                        i += 1usize
                    }
                    i = c.soff[k] * n
                    while i < c.soff[k + 1usize] * n {
                        c.ss[i] = (c.ss[i] + c.sold[i]) / 2.0f64
                        i += 1usize
                    }
                    k += 1usize
                }
                g = gdev(c)
                if g < gold { tries = 5usize }
            }
        }
        iter += 1usize
    }
    ret (iter, math.abs[f64](gold - g) < c.c_crit, ok)
}

// gamlss(): algo 0 RS, 1 CG, 2 mixed (n1 RS cycles then n2 CG cycles). xs holds the parameters' design matrices one after the other, column-major;
// off and start are four n-vectors one after the other (start used for parameter k when has_start[k] is 1)
fn fit_smo(a: *mem.Arena, smo: []sm.Smo, scount: []const usize, fam: usize, algo: usize, y: []const f64, w: []const f64, xs: []const f64, ncol: []const usize, link: []const usize, off: []const f64, start: []const f64, has_start: []const usize, step: []const f64, c_crit: f64, n_cyc: usize, i_cc: f64, i_cyc: usize, autostep: bool, n1: usize, n2: usize) -> (Out, err) {
    let n = y.len
    let np = npar(fam)
    let (par, e1) = mem.alloc[f64](a, 4usize * n)
    let (eta, e2) = mem.alloc[f64](a, 4usize * n)
    let (wv, e3) = mem.alloc[f64](a, 4usize * n)
    let (wt, e4) = mem.alloc[f64](a, 4usize * n)
    let (xoff, e5) = mem.alloc[usize](a, 5usize)
    let (coff, e6) = mem.alloc[usize](a, 5usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (Out { coef: par, par: par, eta: eta, wv: wv, wt: wt, gdev: 0.0f64, iter: 0usize, conv: false, df: 0.0f64, pen: 0.0f64, nl: 0.0f64, ss: par, slam: par, sdf: par, nldf: par, penk: par }, mem.Full) }
    var tot = 0usize
    var k = 0usize
    var xo = 0usize
    while k < 4usize {
        xoff[k] = xo
        coff[k] = tot
        if k < np {
            xo += n * ncol[k]
            tot += ncol[k]
        }
        k += 1usize
    }
    let (coef, e7) = mem.alloc[f64](a, tot + 1usize)
    if e7 != ok { ret (Out { coef: par, par: par, eta: eta, wv: wv, wt: wt, gdev: 0.0f64, iter: 0usize, conv: false, df: 0.0f64, pen: 0.0f64, nl: 0.0f64, ss: par, slam: par, sdf: par, nldf: par, penk: par }, mem.Full) }
    var i = 0usize
    while i < 4usize * n {
        par[i] = 1.0f64
        eta[i] = 0.0f64
        wv[i] = 0.0f64
        wt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < tot + 1usize {
        coef[i] = 0.0f64
        i += 1usize
    }
    k = 0usize
    while k < np {
        if has_start[k] == 1usize {
            i = 0usize
            while i < n {
                par[k * n + i] = start[k * n + i]
                i += 1usize
            }
        } else {
            initial(fam, k, y, n, par[k * n..k * n + n])
        }
        k += 1usize
    }
    let (soff, e8) = mem.alloc[usize](a, 5usize)
    var nsm = 0usize
    k = 0usize
    while k < 4usize {
        soff[k] = nsm
        if k < 3usize { nsm += scount[k] }
        k += 1usize
    }
    soff[4usize] = nsm
    let (ss, e9) = mem.alloc[f64](a, nsm * n + 1usize)
    let (sold, e10) = mem.alloc[f64](a, nsm * n + 1usize)
    let (sdf, e11) = mem.alloc[f64](a, nsm + 1usize)
    let (slam, e12) = mem.alloc[f64](a, nsm + 1usize)
    let (nldf, e13) = mem.alloc[f64](a, 5usize)
    let (eta_o, e15) = mem.alloc[f64](a, 4usize * n)
    let (ss_o, e16) = mem.alloc[f64](a, nsm * n + 1usize)
    let (penk, e14) = mem.alloc[f64](a, 5usize)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret (Out { coef: par, par: par, eta: eta, wv: wv, wt: wt, gdev: 0.0f64, iter: 0usize, conv: false, df: 0.0f64, pen: 0.0f64, nl: 0.0f64, ss: par, slam: par, sdf: par, nldf: par, penk: par }, mem.Full) }
    i = 0usize
    while i < nsm * n {
        ss[i] = 0.0f64
        sold[i] = 0.0f64
        ss_o[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < 4usize * n {
        eta_o[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        nldf[i] = 0.0f64
        penk[i] = 0.0f64
        i += 1usize
    }
    var c = Ctx { a: a, fam: fam, n: n, np: np, y: y, w: w, xs: xs, xoff: xoff, ncol: ncol, link: link, step: step, off: off, par: par, eta: eta, wv: wv, wt: wt, coef: coef, coff: coff, c_crit: c_crit, i_cc: i_cc, i_cyc: i_cyc, autostep: autostep, smo: smo, soff: soff, ss: ss, sold: sold, sdf: sdf, slam: slam, nldf: nldf, pen: penk, bf_cyc: 30usize, bf_tol: 0.001f64, eta_o: eta_o, ss_o: ss_o }
    var iter = 0usize
    var conv = false
    if algo == 0usize {
        let (it, cv, re) = run_rs(&c, n_cyc)
        if re != ok { ret (Out { coef: coef, par: par, eta: eta, wv: wv, wt: wt, gdev: 0.0f64, iter: it, conv: false, df: 0.0f64, pen: 0.0f64, nl: 0.0f64, ss: par, slam: par, sdf: par, nldf: par, penk: par }, re) }
        iter = it
        conv = cv
    }
    if algo == 1usize {
        let (it, cv, re) = run_cg(&c, n_cyc)
        if re != ok { ret (Out { coef: coef, par: par, eta: eta, wv: wv, wt: wt, gdev: 0.0f64, iter: it, conv: false, df: 0.0f64, pen: 0.0f64, nl: 0.0f64, ss: par, slam: par, sdf: par, nldf: par, penk: par }, re) }
        iter = it
        conv = cv
    }
    if algo == 2usize {
        let (it0, cv0, re0) = run_rs(&c, n1)
        if re0 != ok { ret (Out { coef: coef, par: par, eta: eta, wv: wv, wt: wt, gdev: 0.0f64, iter: it0, conv: false, df: 0.0f64, pen: 0.0f64, nl: 0.0f64, ss: par, slam: par, sdf: par, nldf: par, penk: par }, re0) }
        // RS keeps its smooth terms in a local copy of the parameter object, so the CG that follows starts them from zero
        i = 0usize
        while i < nsm * n {
            ss[i] = 0.0f64
            i += 1usize
        }
        let (it, cv, re) = run_cg(&c, n2)
        if re != ok { ret (Out { coef: coef, par: par, eta: eta, wv: wv, wt: wt, gdev: 0.0f64, iter: it, conv: false, df: 0.0f64, pen: 0.0f64, nl: 0.0f64, ss: par, slam: par, sdf: par, nldf: par, penk: par }, re) }
        iter = it
        conv = cv
    }
    var nl = 0.0f64
    var pn = 0.0f64
    k = 0usize
    while k < np {
        nl += nldf[k]
        pn += penk[k]
        k += 1usize
    }
    // a design column of zeros (lo() returns one) is aliased, its coefficient is NA and it adds no degree of freedom
    var nzero = 0usize
    var zc = 0usize
    while zc < tot {
        var allz = true
        var zi = 0usize
        while zi < n {
            if xs[zc * n + zi] != 0.0f64 { allz = false }
            zi += 1usize
        }
        if allz { nzero += 1usize }
        zc += 1usize
    }
    ret (Out { coef: coef, par: par, eta: eta_o, wv: wv, wt: wt, gdev: gdev(&c), iter: iter, conv: conv, df: f64(tot - nzero) + nl, pen: pn, nl: nl, ss: ss_o, slam: slam, sdf: sdf, nldf: nldf, penk: penk }, ok)
}

// the design-matrix models without smoothers
fn fit_model(a: *mem.Arena, fam: usize, algo: usize, y: []const f64, w: []const f64, xs: []const f64, ncol: []const usize, link: []const usize, off: []const f64, start: []const f64, has_start: []const usize, step: []const f64, c_crit: f64, n_cyc: usize, i_cc: f64, i_cyc: usize, autostep: bool, n1: usize, n2: usize) -> (Out, err) {
    let (sc, e1) = mem.alloc[usize](a, 3usize)
    let (smo, e2) = mem.alloc[sm.Smo](a, 1usize)
    if e1 != ok || e2 != ok {
        var zo: Out = zero
        ret (zo, mem.Full)
    }
    sc[0usize] = 0usize
    sc[1usize] = 0usize
    sc[2usize] = 0usize
    let (o, e) = fit_smo(a, smo[0usize..0usize], sc, fam, algo, y, w, xs, ncol, link, off, start, has_start, step, c_crit, n_cyc, i_cc, i_cyc, autostep, n1, n2)
    ret (o, e)
}

// the randomised-free quantile residual of a continuous family, qnorm(F(y)), for observation i of a fitted model
fn rqres(fam: usize, y: f64, m: f64, s: f64, v: f64) -> f64 {
    var p = 0.0f64
    if fam == 0usize { p = gd.pno(y, m, s) }
    if fam == 1usize { p = gd.pga(y, m, s) }
    if fam == 3usize { p = gd.pwei(y, m, s) }
    if fam == 4usize { p = gd.pbccg(y, m, s, v) }
    ret dist.qnorm(p, 0.0f64, 1.0f64, true, false)
}

// the p-quantile of a family at the given parameters (the centile curve value)
fn centile(fam: usize, p: f64, m: f64, s: f64, v: f64) -> f64 {
    if fam == 0usize { ret gd.qno(p, m, s) }
    if fam == 1usize { ret gd.qga(p, m, s) }
    if fam == 2usize { ret gd.qpo(p, m) }
    if fam == 3usize { ret gd.qwei(p, m, s) }
    ret gd.qbccg(p, m, s, v)
}
