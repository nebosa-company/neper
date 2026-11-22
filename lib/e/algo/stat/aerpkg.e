// R AER: ivreg (two-stage least squares with its summary and the three diagnostics: weak instruments, Wu-Hausman, Sargan) and dispersiontest for a Poisson fit.
//
// Matrices are row-major. For ivreg, x is the n by p regressor matrix with endo[j] = 1 for an endogenous column, and z is the n by q instrument matrix whose first p - (number endogenous) columns are the exogenous regressors in the order of x, then the excluded instruments.
//
// Not here: weights, offsets, robust covariance inside summary, tobit.

use e.algo.stat.gparot as gp
use e.algo.stat.plmpanel as pp
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Iv = struct { n: usize, p: usize, q: usize, nendo: usize, coef: []f64, vc: []f64, res: []f64, sigma: f64, r2: f64, adjr2: f64, wald: f64, waldp: f64, diag: []f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// fitted values and rss of y on the columns cols[0..m) of x (n by c)
fn lm_cols(a: *mem.Arena, x: []const f64, c: usize, cols: []const usize, m: usize, y: []const f64, n: usize, fitted: []f64) -> f64 {
    let (xs, e1) = pp.zeros(a, n * m)
    let (co, e2) = pp.zeros(a, m)
    let (xi, e3) = pp.zeros(a, m * m)
    let (rs, e4) = pp.zeros(a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan() }
    var t = 0usize
    while t < n {
        var j = 0usize
        while j < m {
            xs[t * m + j] = x[t * c + cols[j]]
            j += 1usize
        }
        t += 1usize
    }
    let rss = pp.ols_core(a, xs, y, n, m, co, xi, rs)
    t = 0usize
    while t < n {
        fitted[t] = y[t] - rs[t]
        t += 1usize
    }
    ret rss
}

// the F statistic of the nested linear models: columns c0 (m0 of them) inside c1 (m1) of x, out = (df1, df2, F, p)
fn nested_f(a: *mem.Arena, x: []const f64, c: usize, c0: []const usize, m0: usize, c1: []const usize, m1: usize, y: []const f64, n: usize, out: []f64) -> err {
    let (fv, e1) = pp.zeros(a, n)
    if e1 != ok { ret e1 }
    let r0 = lm_cols(a, x, c, c0, m0, y, n, fv)
    let r1 = lm_cols(a, x, c, c1, m1, y, n, fv)
    if r0 != r0 || r1 != r1 { ret gp.Singular }
    let d1 = f64(m1 - m0)
    let d2 = f64(n - m1)
    let w = ((r0 - r1) / d1) / (r1 / d2)
    out[0usize] = d1
    out[1usize] = d2
    out[2usize] = w
    out[3usize] = nb.pf(w, d1, d2, false, false)
    ret ok
}

// two-stage least squares into iv; diag holds the rows (df1, df2, statistic, p) of Weak instruments (one per endogenous regressor), Wu-Hausman, Sargan
fn ivreg(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, endo: []const f64, n: usize, p: usize, q: usize, intercept: bool, iv: *Iv) -> err {
    var nendo = 0usize
    var j = 0usize
    while j < p {
        if endo[j] != 0.0f64 { nendo += 1usize }
        j += 1usize
    }
    let nexo = p - nendo
    // first stage: fitted regressors
    let (zc, e0) = pp.zeros_u(a, q)
    if e0 != ok { ret e0 }
    j = 0usize
    while j < q {
        zc[j] = j
        j += 1usize
    }
    let (xh, e1) = pp.zeros(a, n * p)
    let (col, e2) = pp.zeros(a, n)
    let (fv, e3) = pp.zeros(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    j = 0usize
    while j < p {
        var t = 0usize
        while t < n {
            col[t] = x[t * p + j]
            t += 1usize
        }
        let r = lm_cols(a, z, q, zc, q, col, n, fv)
        if r != r { ret gp.Singular }
        t = 0usize
        while t < n {
            xh[t * p + j] = fv[t]
            t += 1usize
        }
        j += 1usize
    }
    let (co, e4) = pp.zeros(a, p)
    let (xi, e5) = pp.zeros(a, p * p)
    let (rs, e6) = pp.zeros(a, n)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    let rss0 = pp.ols_core(a, xh, y, n, p, co, xi, rs)
    if rss0 != rss0 { ret gp.Singular }
    // residuals use the original regressors
    var rss = 0.0f64
    var t2 = 0usize
    while t2 < n {
        var f = 0.0f64
        var c = 0usize
        while c < p {
            f += x[t2 * p + c] * co[c]
            c += 1usize
        }
        rs[t2] = y[t2] - f
        rss += rs[t2] * rs[t2]
        t2 += 1usize
    }
    let dfr = f64(n - p)
    let s2 = rss / dfr
    let (vc, e7) = pp.zeros(a, p * p)
    if e7 != ok { ret e7 }
    j = 0usize
    while j < p * p {
        vc[j] = s2 * xi[j]
        j += 1usize
    }
    var ym = 0.0f64
    t2 = 0usize
    while t2 < n {
        ym += y[t2]
        t2 += 1usize
    }
    ym = ym / f64(n)
    var tss = 0.0f64
    var dfi = 0.0f64
    t2 = 0usize
    while t2 < n {
        if intercept {
            tss += (y[t2] - ym) * (y[t2] - ym)
        } else {
            tss += y[t2] * y[t2]
        }
        t2 += 1usize
    }
    if intercept { dfi = 1.0f64 }
    iv.n = n
    iv.p = p
    iv.q = q
    iv.nendo = nendo
    iv.coef = co
    iv.vc = vc
    iv.res = rs
    iv.sigma = math.sqrt[f64](s2)
    iv.r2 = 1.0f64 - rss / tss
    iv.adjr2 = 1.0f64 - (1.0f64 - iv.r2) * ((f64(n) - dfi) / dfr)
    // the Wald F test of every coefficient but the intercept (the first column when there is one)
    var lo = 0usize
    if intercept { lo = 1usize }
    let m = p - lo
    let (sub, e8) = pp.zeros(a, m * m)
    if e8 != ok { ret e8 }
    var u = 0usize
    while u < m {
        var v = 0usize
        while v < m {
            sub[u * m + v] = vc[(lo + u) * p + lo + v]
            v += 1usize
        }
        u += 1usize
    }
    let (si, e9) = gp.invert(a, sub, m)
    if e9 != ok { ret e9 }
    var wq = 0.0f64
    u = 0usize
    while u < m {
        var v = 0usize
        while v < m {
            wq += co[lo + u] * si[u * m + v] * co[lo + v]
            v += 1usize
        }
        u += 1usize
    }
    iv.wald = wq / f64(m)
    iv.waldp = nb.pf(iv.wald, f64(m), dfr, false, false)
    // diagnostics
    let ninst = q - nexo
    let nd = nendo + 2usize
    let (dg, e10) = pp.zeros(a, nd * 4usize)
    if e10 != ok { ret e10 }
    let (c0, e11) = pp.zeros_u(a, q)
    if e11 != ok { ret e11 }
    j = 0usize
    while j < nexo {
        c0[j] = j
        j += 1usize
    }
    var ie = 0usize
    j = 0usize
    while j < p {
        if endo[j] != 0.0f64 {
            var t3 = 0usize
            while t3 < n {
                col[t3] = x[t3 * p + j]
                t3 += 1usize
            }
            let (wk, e12) = pp.zeros(a, 4usize)
            if e12 != ok { ret e12 }
            let ef = nested_f(a, z, q, c0, nexo, zc, q, col, n, wk)
            if ef != ok { ret ef }
            var k4 = 0usize
            while k4 < 4usize {
                dg[ie * 4usize + k4] = wk[k4]
                k4 += 1usize
            }
            ie += 1usize
        }
        j += 1usize
    }
    // Wu-Hausman: y on x against y on x plus the first-stage fits of the endogenous columns
    let (xe, e13) = pp.zeros(a, n * (p + nendo))
    if e13 != ok { ret e13 }
    t2 = 0usize
    while t2 < n {
        var c2 = 0usize
        while c2 < p {
            xe[t2 * (p + nendo) + c2] = x[t2 * p + c2]
            c2 += 1usize
        }
        var ke = 0usize
        c2 = 0usize
        while c2 < p {
            if endo[c2] != 0.0f64 {
                xe[t2 * (p + nendo) + p + ke] = xh[t2 * p + c2]
                ke += 1usize
            }
            c2 += 1usize
        }
        t2 += 1usize
    }
    let (ca, e14) = pp.zeros_u(a, p + nendo)
    if e14 != ok { ret e14 }
    j = 0usize
    while j < p + nendo {
        ca[j] = j
        j += 1usize
    }
    let (wk2, e15) = pp.zeros(a, 4usize)
    if e15 != ok { ret e15 }
    let ew = nested_f(a, xe, p + nendo, ca, p, ca, p + nendo, y, n, wk2)
    if ew != ok { ret ew }
    var k5 = 0usize
    while k5 < 4usize {
        dg[nendo * 4usize + k5] = wk2[k5]
        k5 += 1usize
    }
    // Sargan: n (1 - rss of the iv residuals on z / their centred sum of squares)
    let sdf = ninst - nendo
    dg[(nendo + 1usize) * 4usize] = f64(sdf)
    dg[(nendo + 1usize) * 4usize + 1usize] = nan()
    dg[(nendo + 1usize) * 4usize + 2usize] = nan()
    dg[(nendo + 1usize) * 4usize + 3usize] = nan()
    if sdf > 0usize {
        let rss_s = lm_cols(a, z, q, zc, q, rs, n, fv)
        var rm = 0.0f64
        t2 = 0usize
        while t2 < n {
            rm += rs[t2]
            t2 += 1usize
        }
        rm = rm / f64(n)
        var rssr = 0.0f64
        t2 = 0usize
        while t2 < n {
            rssr += (rs[t2] - rm) * (rs[t2] - rm)
            t2 += 1usize
        }
        let st = f64(n) * (1.0f64 - rss_s / rssr)
        dg[(nendo + 1usize) * 4usize + 2usize] = st
        dg[(nendo + 1usize) * 4usize + 3usize] = nm.pchisq(st, f64(sdf), false, false)
    }
    iv.diag = dg
    ret ok
}

// a Poisson log-link glm.fit: the fitted means into mu, R's start (y + 0.1), deviance convergence 1e-8, at most 25 iterations
fn poisson_fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, mu: []f64) -> err {
    let (eta, e1) = pp.zeros(a, n)
    let (xw, e2) = pp.zeros(a, n * p)
    let (zw, e3) = pp.zeros(a, n)
    let (co, e4) = pp.zeros(a, p)
    let (xi, e5) = pp.zeros(a, p * p)
    let (rs, e6) = pp.zeros(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var t = 0usize
    while t < n {
        mu[t] = y[t] + 0.1f64
        eta[t] = math.log[f64](mu[t])
        t += 1usize
    }
    var devold = poisson_dev(y, mu, n)
    var it = 0usize
    while it < 25usize {
        t = 0usize
        while t < n {
            let wt = math.sqrt[f64](mu[t])
            zw[t] = (eta[t] + (y[t] - mu[t]) / mu[t]) * wt
            var c = 0usize
            while c < p {
                xw[t * p + c] = x[t * p + c] * wt
                c += 1usize
            }
            t += 1usize
        }
        let rss = pp.ols_core(a, xw, zw, n, p, co, xi, rs)
        if rss != rss { ret gp.Singular }
        t = 0usize
        while t < n {
            var f = 0.0f64
            var c2 = 0usize
            while c2 < p {
                f += x[t * p + c2] * co[c2]
                c2 += 1usize
            }
            eta[t] = f
            mu[t] = math.exp[f64](f)
            t += 1usize
        }
        let dev = poisson_dev(y, mu, n)
        it += 1usize
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 { ret ok }
        devold = dev
    }
    ret ok
}

fn poisson_dev(y: []const f64, mu: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var t = 0usize
    while t < n {
        var r = mu[t]
        if y[t] > 0.0f64 { r = y[t] * math.log[f64](y[t] / mu[t]) - (y[t] - mu[t]) }
        s += 2.0f64 * r
        t += 1usize
    }
    ret s
}

// AER::dispersiontest on a Poisson fit of y on x (n by p): trafo 0 is the default (mean) test, 1 and 2 are the auxiliary regression on mu^trafo / mu; alt 0 greater, 1 two.sided, 2 less. out = (z statistic, p value, estimate)
fn dispersiontest(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, trafo: f64, alt: usize, out: []f64) -> err {
    let (mu, e1) = pp.zeros(a, n)
    let (aux, e2) = pp.zeros(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    let fe = poisson_fit(a, x, y, n, p, mu)
    if fe != ok { ret fe }
    var t = 0usize
    var m = 0.0f64
    while t < n {
        aux[t] = ((y[t] - mu[t]) * (y[t] - mu[t]) - y[t]) / mu[t]
        m += aux[t]
        t += 1usize
    }
    let nf = f64(n)
    m = m / nf
    var stat = 0.0f64
    var est = 0.0f64
    if trafo == 0.0f64 {
        var ss = 0.0f64
        t = 0usize
        while t < n {
            ss += (aux[t] - m) * (aux[t] - m)
            t += 1usize
        }
        stat = math.sqrt[f64](nf) * m / math.sqrt[f64](ss / (nf - 1.0f64))
        est = m + 1.0f64
    } else {
        // no-intercept regression of aux on mu^trafo / mu: the t statistic of its one coefficient
        var sxx = 0.0f64
        var sxy = 0.0f64
        t = 0usize
        while t < n {
            let r = math.pow[f64](mu[t], trafo) / mu[t]
            sxx += r * r
            sxy += r * aux[t]
            t += 1usize
        }
        let b = sxy / sxx
        var rss = 0.0f64
        t = 0usize
        while t < n {
            let r2 = math.pow[f64](mu[t], trafo) / mu[t]
            rss += (aux[t] - b * r2) * (aux[t] - b * r2)
            t += 1usize
        }
        stat = b / math.sqrt[f64](rss / (nf - 1.0f64) / sxx)
        est = b
    }
    var pv = 0.0f64
    if alt == 0usize { pv = dist.pnorm(stat, 0.0f64, 1.0f64, false, false) }
    if alt == 1usize { pv = dist.pnorm(math.abs[f64](stat), 0.0f64, 1.0f64, false, false) * 2.0f64 }
    if alt == 2usize { pv = dist.pnorm(stat, 0.0f64, 1.0f64, true, false) }
    out[0usize] = stat
    out[1usize] = pv
    out[2usize] = est
    ret ok
}

// log density of a standard normal ratio: lambda(c) = phi(c) / Phi(c), by logs so the far tail holds
fn inv_mills(c: f64) -> f64 {
    ret math.exp[f64](dist.dnorm(c, 0.0f64, 1.0f64, true) - dist.pnorm(c, 0.0f64, 1.0f64, true, true))
}

// log likelihood, gradient (p + 1) and Hessian (p + 1 square) of the Tobit model at par = (beta, log sigma); y <= left is censored at left, y >= right at right
fn tobit_derivs(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, left: f64, right: f64, par: []const f64, g: []f64, h: []f64) -> f64 {
    let m = p + 1usize
    let sg = math.exp[f64](par[p])
    var ll = 0.0f64
    var i = 0usize
    while i < m {
        g[i] = 0.0f64
        var j = 0usize
        while j < m {
            h[i * m + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    var t = 0usize
    while t < n {
        var mu = 0.0f64
        var c0 = 0usize
        while c0 < p {
            mu += x[t * p + c0] * par[c0]
            c0 += 1usize
        }
        var gm = 0.0f64
        var gs = 0.0f64
        var hmm = 0.0f64
        var hms = 0.0f64
        var hss = 0.0f64
        if y[t] <= left || y[t] >= right {
            var tau = 0.0f64 - 1.0f64
            var bound = left
            if y[t] >= right {
                tau = 1.0f64
                bound = right
            }
            let c = tau * (mu - bound) / sg
            let lam = inv_mills(c)
            ll += dist.pnorm(c, 0.0f64, 1.0f64, true, true)
            let q = c * (c + lam)
            gm = lam * tau / sg
            gs = 0.0f64 - lam * c
            hmm = 0.0f64 - lam * (c + lam) / (sg * sg)
            hms = tau * (lam / sg) * (q - 1.0f64)
            hss = c * lam * (1.0f64 - q)
        } else {
            let z = (y[t] - mu) / sg
            ll += 0.0f64 - par[p] + dist.dnorm(z, 0.0f64, 1.0f64, true)
            gm = z / sg
            gs = z * z - 1.0f64
            hmm = 0.0f64 - 1.0f64 / (sg * sg)
            hms = 0.0f64 - 2.0f64 * z / sg
            hss = 0.0f64 - 2.0f64 * z * z
        }
        var u = 0usize
        while u < p {
            g[u] += gm * x[t * p + u]
            var v = 0usize
            while v < p {
                h[u * m + v] += hmm * x[t * p + u] * x[t * p + v]
                v += 1usize
            }
            h[u * m + p] += hms * x[t * p + u]
            h[p * m + u] += hms * x[t * p + u]
            u += 1usize
        }
        g[p] += gs
        h[p * m + p] += hss
        t += 1usize
    }
    ret ll
}

// AER::tobit (gaussian): Newton's method from the least-squares start to full convergence. out = (beta (p), log sigma, loglik, the covariance of (beta, log sigma) (p + 1 square))
fn tobit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, left: f64, right: f64, out: []f64) -> err {
    let m = p + 1usize
    let (par, e1) = pp.zeros(a, m)
    let (g, e2) = pp.zeros(a, m)
    let (h, e3) = pp.zeros(a, m * m)
    let (xi, e4) = pp.zeros(a, p * p)
    let (rs, e5) = pp.zeros(a, n)
    let (np2, e6) = pp.zeros(a, m)
    let (g2, e7) = pp.zeros(a, m)
    let (h2, e8) = pp.zeros(a, m * m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    let rss = pp.ols_core(a, x, y, n, p, par, xi, rs)
    if rss != rss { ret gp.Singular }
    par[p] = 0.5f64 * math.log[f64](rss / f64(n))
    var ll = tobit_derivs(a, x, y, n, p, left, right, par, g, h)
    var it = 0usize
    while it < 200usize {
        let (hi, ei) = gp.invert(a, h, m)
        if ei != ok { ret ei }
        // Newton step: par - H^-1 g, halved while the log likelihood falls
        var scale = 1.0f64
        var tries = 0usize
        var nll = ll
        while tries < 40usize {
            var u = 0usize
            while u < m {
                var s = 0.0f64
                var v = 0usize
                while v < m {
                    s += hi[u * m + v] * g[v]
                    v += 1usize
                }
                np2[u] = par[u] - scale * s
                u += 1usize
            }
            nll = tobit_derivs(a, x, y, n, p, left, right, np2, g2, h2)
            if nll >= ll - 1.0e-14f64 { tries = 100usize } else {
                scale = scale * 0.5f64
                tries += 1usize
            }
        }
        var big = 0.0f64
        var u2 = 0usize
        while u2 < m {
            let d = math.abs[f64](np2[u2] - par[u2])
            if d > big { big = d }
            par[u2] = np2[u2]
            u2 += 1usize
        }
        u2 = 0usize
        while u2 < m {
            g[u2] = g2[u2]
            u2 += 1usize
        }
        u2 = 0usize
        while u2 < m * m {
            h[u2] = h2[u2]
            u2 += 1usize
        }
        ll = nll
        it += 1usize
        if big < 1.0e-13f64 { it = 1000usize }
    }
    let (hv, ej) = gp.invert(a, h, m)
    if ej != ok { ret ej }
    var k = 0usize
    while k < m {
        out[k] = par[k]
        k += 1usize
    }
    out[m] = ll
    k = 0usize
    while k < m * m {
        out[m + 1usize + k] = 0.0f64 - hv[k]
        k += 1usize
    }
    ret ok
}
