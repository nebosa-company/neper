// R MuMIn on lm and glm fits: the fits themselves (lm.fit through the R QR, glm.fit's IRLS with its start values, stopping rule and
// the dispersion it reads off the last pass), the information criteria (AIC, AICc, BIC, QAIC, QAICc, Cp, QIC), std.coef (sd and
// partial.sd), r.squaredGLMM for lm and glm, and stdize.
//
// A model is a set of columns of one design matrix x (n by q, column-major, column 0 the intercept): cols lists them.
// Families: the bigglm ids (0 gaussian, 1 binomial(logit), 2 poisson, 3 Gamma(inverse), 4 Gamma(log), 5 gaussian(log), 6 binomial(probit),
// 7 binomial(cloglog), 8 inverse.gaussian(log)) plus 200 lm, 201 quasipoisson(log), 202 quasibinomial(logit).
//
// Not here: aliased (rank deficient) designs, prior weights and offsets, negative binomial, glmer, lmer other than the closed form of
// r2glmm over its variance components.

use e.algo.linalg.decomp as dc
use e.algo.stat as sta
use e.algo.stat.bigglm as bg
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem
use e.os

type Model = struct { nc: usize, n: usize, fam: u8, cols: []usize, xs: []f64, coef: []f64, se: []f64, vcov: []f64, dev: f64, dfres: f64, ll: f64, npar: f64, disp: f64, iter: usize, rank: usize, theta: f64, theta_fam: f64, wt: []const f64, off: []const f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nan(x: f64) -> bool { ret x != x }

fn zalloc(a: *mem.Arena, n: usize) -> []f64 {
    let (b, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { os.exit(70) }
    var i = 0usize
    while i < n + 1usize {
        b[i] = 0.0f64
        i += 1usize
    }
    ret b[0usize..n]
}

fn is_nb(fam: u8) -> bool { ret fam == 9u8 || fam == 10u8 }

// 200 lm, 201 quasipoisson, 202 quasibinomial and the negative binomials (9 fixed theta, 10 glm.nb) map to the bigglm id of their link
fn base_fam(fam: u8) -> u8 {
    if fam == 200u8 { ret 0u8 }
    if fam == 201u8 || fam == 9u8 || fam == 10u8 { ret 2u8 }
    if fam == 202u8 { ret 1u8 }
    ret fam
}

// dispersion estimated (summary.glm): gaussian, Gamma, inverse.gaussian, the quasi families, lm
fn est_disp(fam: u8) -> bool {
    let bk = bg.base_kind(base_fam(fam))
    if fam == 201u8 || fam == 202u8 { ret true }
    if fam == 10u8 { ret false }
    if fam == 9u8 { ret true }
    ret bk == 0u8 || bk == 3u8 || bk == 4u8
}

fn link_fun(fam: u8, mu: f64) -> f64 {
    let lk = bg.link_kind(base_fam(fam))
    if lk == 0u8 { ret mu }
    if lk == 1u8 { ret math.log[f64](mu / (1.0f64 - mu)) }
    if lk == 2u8 { ret math.log[f64](mu) }
    if lk == 3u8 { ret 1.0f64 / mu }
    if lk == 4u8 { ret dist.qnorm(mu, 0.0f64, 1.0f64, true, false) }
    ret math.log[f64](0.0f64 - math.log[f64](1.0f64 - mu))
}

fn f_var(fam: u8, mu: f64, th: f64) -> f64 {
    if is_nb(fam) { ret mu + mu * mu / th }
    ret bg.variance(base_fam(fam), mu)
}

fn f_dev(fam: u8, y: f64, mu: f64, w: f64, th: f64) -> f64 {
    if is_nb(fam) {
        var m = 1.0f64
        if y > 1.0f64 { m = y }
        ret 2.0f64 * w * (y * math.log[f64](m / mu) - (y + th) * math.log[f64]((y + th) / (mu + th)))
    }
    ret bg.dev_resid(base_fam(fam), y, mu, w)
}

// MASS::theta.ml: scoring from the moment start, at most limit - 1 steps, stopping when the step is under eps
fn theta_ml(y: []const f64, mu: []const f64, wt: []const f64, limit: usize) -> f64 {
    let n = y.len
    var sw = 0.0f64
    var s0 = 0.0f64
    var i = 0usize
    while i < n {
        var w = 1.0f64
        if wt.len > 0usize { w = wt[i] }
        sw += w
        s0 += w * (y[i] / mu[i] - 1.0f64) * (y[i] / mu[i] - 1.0f64)
        i += 1usize
    }
    var t0 = sw / s0
    var it = 0usize
    var del = 1.0f64
    let eps = 1.220703125e-4f64
    var go = true
    while go {
        it += 1usize
        if !(it < limit && (del > eps || del < 0.0f64 - eps)) { go = false }
        if go {
            if t0 < 0.0f64 { t0 = 0.0f64 - t0 }
            var sc = 0.0f64
            var inf = 0.0f64
            i = 0usize
            while i < n {
                var w = 1.0f64
                if wt.len > 0usize { w = wt[i] }
                sc += w * (sta.digamma(t0 + y[i]) - sta.digamma(t0) + math.log[f64](t0) + 1.0f64 - math.log[f64](t0 + mu[i]) - (y[i] + t0) / (mu[i] + t0))
                inf += w * (0.0f64 - sta.trigamma(t0 + y[i]) + sta.trigamma(t0) - 1.0f64 / t0 + 2.0f64 / (mu[i] + t0) - (y[i] + t0) / ((mu[i] + t0) * (mu[i] + t0)))
                i += 1usize
            }
            del = sc / inf
            t0 = t0 + del
        }
    }
    if t0 < 0.0f64 { t0 = 0.0f64 }
    ret t0
}

fn nb_loglik(y: []const f64, mu: []const f64, wt: []const f64, th: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        var w = 1.0f64
        if wt.len > 0usize { w = wt[i] }
        var m1 = mu[i]
        if y[i] == 0.0f64 { m1 = mu[i] + 1.0f64 }
        s += w * (nm.lgammafn(th + y[i]) - nm.lgammafn(th) - nm.lgammafn(y[i] + 1.0f64) + th * math.log[f64](th) + y[i] * math.log[f64](m1) - (th + y[i]) * math.log[f64](th + mu[i]))
        i += 1usize
    }
    ret s
}

// Householder least squares of z on the n by nc matrix xw: coefficients and (X'X)^-1 with NaN for the aliased (pivoted out) columns; answers (rss, rank)
fn wls(a: *mem.Arena, xw: []const f64, n: usize, nc: usize, zw: []const f64, tol: f64, coef: []f64, covu: []f64) -> (f64, usize) {
    let (f, qe) = dc.qr(a, xw, n, nc, tol)
    if qe != ok { os.exit(71) }
    let rk = f.rank
    let qty = zalloc(a, n)
    var i = 0usize
    while i < n {
        qty[i] = zw[i]
        i += 1usize
    }
    dc.qr_qty(&f, qty)
    let cp = zalloc(a, nc)
    let rinv = zalloc(a, nc * nc)
    var j = 0usize
    while j < rk {
        var r = rk
        while r > 0usize {
            r -= 1usize
            var s = 0.0f64
            if r == j { s = 1.0f64 }
            var c = r + 1usize
            while c < rk {
                s = s - f.qr[c * n + r] * rinv[j * nc + c]
                c += 1usize
            }
            rinv[j * nc + r] = s / f.qr[r * n + r]
        }
        j += 1usize
    }
    j = rk
    while j > 0usize {
        j -= 1usize
        var s = qty[j]
        var c = j + 1usize
        while c < rk {
            s = s - f.qr[c * n + j] * cp[c]
            c += 1usize
        }
        cp[j] = s / f.qr[j * n + j]
    }
    i = 0usize
    while i < nc {
        coef[i] = nan()
        j = 0usize
        while j < nc {
            covu[j * nc + i] = nan()
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < rk {
        coef[f.pivot[j]] = cp[j]
        var k = 0usize
        while k < rk {
            var s = 0.0f64
            var m = 0usize
            while m < rk {
                s += rinv[m * nc + j] * rinv[m * nc + k]
                m += 1usize
            }
            covu[f.pivot[k] * nc + f.pivot[j]] = s
            k += 1usize
        }
        j += 1usize
    }
    var rss = 0.0f64
    i = rk
    while i < n {
        rss += qty[i] * qty[i]
        i += 1usize
    }
    ret (rss, rk)
}

// the family's aic term without the 2 rank (family()$aic) with prior weights wt (empty: 1); NaN for the quasi families
fn fam_aic(fam: u8, y: []const f64, mu: []const f64, wt: []const f64, n: usize, dev: f64, th: f64) -> f64 {
    if fam == 201u8 || fam == 202u8 { ret nan() }
    let nn = f64(n)
    var s = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len > 0usize { sw += wt[i] } else { sw += 1.0f64 }
        i += 1usize
    }
    if fam == 9u8 {
        i = 0usize
        while i < n {
            var w = 1.0f64
            if wt.len > 0usize { w = wt[i] }
            let term = (y[i] + th) * math.log[f64](mu[i] + th) - y[i] * math.log[f64](mu[i]) + nm.lgammafn(y[i] + 1.0f64) - th * math.log[f64](th) + nm.lgammafn(th) - nm.lgammafn(th + y[i])
            s += term * w
            i += 1usize
        }
        ret 2.0f64 * s
    }
    let bk = bg.base_kind(fam)
    if bk == 0u8 {
        i = 0usize
        while i < n {
            if wt.len > 0usize { s += math.log[f64](wt[i]) }
            i += 1usize
        }
        ret nn * (math.log[f64](2.0f64 * 3.141592653589793238462643383279f64 * dev / nn) + 1.0f64) + 2.0f64 - s
    }
    i = 0usize
    while i < n {
        var w = 1.0f64
        if wt.len > 0usize { w = wt[i] }
        if bk == 1u8 {
            let xx = math.round[f64](w * y[i])
            s += nm.lgammafn(w + 1.0f64) - nm.lgammafn(xx + 1.0f64) - nm.lgammafn(w - xx + 1.0f64) + xx * math.log[f64](mu[i]) + (w - xx) * math.log[f64](1.0f64 - mu[i])
        }
        if bk == 2u8 { s += w * (y[i] * math.log[f64](mu[i]) - mu[i] - nm.lgammafn(y[i] + 1.0f64)) }
        if bk == 3u8 {
            let disp = dev / sw
            let shape = 1.0f64 / disp
            let sc = mu[i] * disp
            s += w * ((shape - 1.0f64) * math.log[f64](y[i]) - y[i] / sc - shape * math.log[f64](sc) - nm.lgammafn(shape))
        }
        if bk == 4u8 { s += math.log[f64](y[i]) * w }
        i += 1usize
    }
    if bk == 1u8 || bk == 2u8 { ret 0.0f64 - 2.0f64 * s }
    if bk == 3u8 { ret 0.0f64 - 2.0f64 * s + 2.0f64 }
    let disp = dev / sw
    ret sw * (math.log[f64](disp * 2.0f64 * 3.141592653589793238462643383279f64) + 1.0f64) + 3.0f64 * s + 2.0f64
}

type Irls = struct { coef: []f64, covu: []f64, dev: f64, rank: usize, iter: usize, mu: []f64, eta: []f64, w2: []f64 }

// glm.fit: IRLS with the family's start values (or etastart when eta0 is not empty), prior weights wt and offset off (empty: none)
fn irls(a: *mem.Arena, xs: []const f64, n: usize, nc: usize, y: []const f64, fam: u8, th: f64, wt: []const f64, off: []const f64, eta0: []const f64) -> Irls {
    let bk = bg.base_kind(base_fam(fam))
    var r: Irls = zero
    r.coef = zalloc(a, nc)
    r.covu = zalloc(a, nc * nc)
    r.mu = zalloc(a, n)
    r.eta = zalloc(a, n)
    r.w2 = zalloc(a, n)
    let z = zalloc(a, n)
    let xw = zalloc(a, n * nc)
    let cf = zalloc(a, nc)
    var i = 0usize
    while i < n {
        var w = 1.0f64
        if wt.len > 0usize { w = wt[i] }
        if eta0.len > 0usize {
            r.eta[i] = eta0[i]
        } else {
            var ms = y[i]
            if is_nb(fam) { if y[i] == 0.0f64 { ms = y[i] + 1.0f64 / 6.0f64 } }
            if !is_nb(fam) && bk == 1u8 { ms = (w * y[i] + 0.5f64) / (w + 1.0f64) }
            if !is_nb(fam) && bk == 2u8 { ms = y[i] + 0.1f64 }
            r.eta[i] = link_fun(fam, ms)
        }
        r.mu[i] = f_linkinv(fam, r.eta[i])
        i += 1usize
    }
    var devold = 0.0f64
    i = 0usize
    while i < n {
        var w = 1.0f64
        if wt.len > 0usize { w = wt[i] }
        devold += f_dev(fam, y[i], r.mu[i], w, th)
        i += 1usize
    }
    var dev = devold
    var it = 0usize
    var done = false
    while !done && it < 25usize {
        it += 1usize
        i = 0usize
        while i < n {
            var w = 1.0f64
            if wt.len > 0usize { w = wt[i] }
            var o = 0.0f64
            if off.len > 0usize { o = off[i] }
            let me = f_mu_eta(fam, r.eta[i])
            let wv = math.sqrt[f64](w * me * me / f_var(fam, r.mu[i], th))
            r.w2[i] = wv * wv
            z[i] = (r.eta[i] - o + (y[i] - r.mu[i]) / me) * wv
            var j = 0usize
            while j < nc {
                xw[j * n + i] = xs[j * n + i] * wv
                j += 1usize
            }
            i += 1usize
        }
        let (rs0, rk) = wls(a, xw, n, nc, z, 1.0e-11f64, r.coef, r.covu)
        let _ = rs0
        r.rank = rk
        var j = 0usize
        while j < nc {
            cf[j] = r.coef[j]
            if is_nan(cf[j]) { cf[j] = 0.0f64 }
            j += 1usize
        }
        dev = 0.0f64
        i = 0usize
        while i < n {
            var w = 1.0f64
            if wt.len > 0usize { w = wt[i] }
            var s = 0.0f64
            if off.len > 0usize { s = off[i] }
            j = 0usize
            while j < nc {
                s += xs[j * n + i] * cf[j]
                j += 1usize
            }
            r.eta[i] = s
            r.mu[i] = f_linkinv(fam, s)
            dev += f_dev(fam, y[i], r.mu[i], w, th)
            i += 1usize
        }
        var df = dev - devold
        if df < 0.0f64 { df = 0.0f64 - df }
        var ad = dev
        if ad < 0.0f64 { ad = 0.0f64 - ad }
        if df / (ad + 0.1f64) < 1.0e-8f64 { done = true }
        devold = dev
    }
    r.iter = it
    r.dev = dev
    ret r
}

fn f_linkinv(fam: u8, eta: f64) -> f64 {
    if is_nb(fam) { ret math.exp[f64](eta) }
    ret bg.linkinv(base_fam(fam), eta)
}

fn f_mu_eta(fam: u8, eta: f64) -> f64 { ret bg.mu_eta(base_fam(fam), eta) }

// lm (fam 200) or glm of y on the columns cols of x, with prior weights wt and offset off (empty slices: none); theta is the negative binomial theta of fam 9
fn fit_ext(a: *mem.Arena, x: []const f64, n: usize, cols: []const usize, y: []const f64, fam: u8, wt: []const f64, off: []const f64, theta: f64) -> Model {
    let nc = cols.len
    let xs = zalloc(a, n * nc)
    var j = 0usize
    while j < nc {
        var i = 0usize
        while i < n {
            xs[j * n + i] = x[cols[j] * n + i]
            i += 1usize
        }
        j += 1usize
    }
    var m: Model = zero
    let (cc, ce) = mem.alloc[usize](a, nc + 1usize)
    if ce != ok { os.exit(70) }
    j = 0usize
    while j < nc {
        cc[j] = cols[j]
        j += 1usize
    }
    m.nc = nc
    m.n = n
    m.fam = fam
    m.cols = cc[0usize..nc]
    m.xs = xs
    m.coef = zalloc(a, nc)
    m.se = zalloc(a, nc)
    m.vcov = zalloc(a, nc * nc)
    m.wt = wt
    m.off = off
    let covu = zalloc(a, nc * nc)
    let nn = f64(n)
    let pi = 3.141592653589793238462643383279f64
    m.theta = theta
    m.theta_fam = theta
    var disp = 1.0f64
    if fam == 200u8 {
        let xw = zalloc(a, n * nc)
        let zw = zalloc(a, n)
        var slw = 0.0f64
        var i = 0usize
        while i < n {
            var w = 1.0f64
            if wt.len > 0usize { w = wt[i] }
            var o = 0.0f64
            if off.len > 0usize { o = off[i] }
            let sw = math.sqrt[f64](w)
            slw += math.log[f64](w)
            zw[i] = (y[i] - o) * sw
            j = 0usize
            while j < nc {
                xw[j * n + i] = xs[j * n + i] * sw
                j += 1usize
            }
            i += 1usize
        }
        let (rss, rk) = wls(a, xw, n, nc, zw, 1.0e-7f64, m.coef, covu)
        m.rank = rk
        m.dev = rss
        m.dfres = nn - f64(rk)
        disp = rss / m.dfres
        m.ll = 0.5f64 * (slw - nn * (math.log[f64](2.0f64 * pi) + 1.0f64 - math.log[f64](nn) + math.log[f64](rss)))
        m.npar = f64(rk) + 1.0f64
    } else {
        var f0 = fam
        if fam == 10u8 {
            f0 = 2u8
            if theta > 0.0f64 { f0 = 9u8 }
        }
        var fit = irls(a, xs, n, nc, y, f0, theta, wt, off, zalloc(a, 0usize))
        var th = theta
        if fam == 10u8 {
            let mu0 = zalloc(a, n)
            var i = 0usize
            while i < n {
                mu0[i] = fit.mu[i]
                i += 1usize
            }
            th = theta_ml(y, mu0, wt, 25usize)
            var mu = mu0
            let d1 = math.sqrt[f64](2.0f64 * math.max[f64](1.0f64, nn - f64(fit.rank)))
            var del = 1.0f64
            var lm = nb_loglik(y, mu, wt, th)
            var lm0 = lm + 2.0f64 * d1
            var iter = 0usize
            while iter < 25usize && (math.abs[f64](lm0 - lm) / d1 + math.abs[f64](del)) > 1.0e-8f64 {
                iter += 1usize
                let eta = zalloc(a, n)
                i = 0usize
                while i < n {
                    eta[i] = math.log[f64](mu[i])
                    i += 1usize
                }
                m.theta_fam = th
                fit = irls(a, xs, n, nc, y, 10u8, th, wt, off, eta)
                let t0 = th
                th = theta_ml(y, mu, wt, 25usize)
                mu = fit.mu
                del = t0 - th
                lm0 = lm
                lm = nb_loglik(y, mu, wt, th)
            }
            m.theta = th
            m.ll = lm
            m.npar = f64(fit.rank) + 1.0f64
        }
        m.rank = fit.rank
        m.dev = fit.dev
        m.dfres = nn - f64(fit.rank)
        j = 0usize
        while j < nc {
            m.coef[j] = fit.coef[j]
            j += 1usize
        }
        j = 0usize
        while j < nc * nc {
            covu[j] = fit.covu[j]
            j += 1usize
        }
        if est_disp(fam) {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                let r = (y[i] - fit.mu[i]) / f_mu_eta(fam, fit.eta[i])
                s += fit.w2[i] * r * r
                i += 1usize
            }
            disp = s / m.dfres
        }
        if fam != 10u8 {
            var p = f64(fit.rank)
            let bk = bg.base_kind(base_fam(fam))
            if !is_nb(fam) && (bk == 0u8 || bk == 3u8 || bk == 4u8 || fam == 201u8 || fam == 202u8) { p += 1.0f64 }
            m.npar = p
            m.ll = p - f64(fit.rank) - fam_aic(fam, y, fit.mu, wt, n, fit.dev, theta) / 2.0f64
            if fam == 201u8 || fam == 202u8 { m.ll = nan() }
        }
    }
    m.disp = disp
    j = 0usize
    while j < nc * nc {
        m.vcov[j] = covu[j] * disp
        j += 1usize
    }
    j = 0usize
    while j < nc {
        m.se[j] = math.sqrt[f64](m.vcov[j * nc + j])
        j += 1usize
    }
    ret m
}

fn fit_cols(a: *mem.Arena, x: []const f64, n: usize, cols: []const usize, y: []const f64, fam: u8) -> Model {
    ret fit_ext(a, x, n, cols, y, fam, zalloc(a, 0usize), zalloc(a, 0usize), 1.0f64)
}


// the linear predictor of a model at the rows of newx (n2 by q, same column layout as the fitting matrix)
fn linpred(m: *const Model, newx: []const f64, n2: usize, out: []f64) {
    var i = 0usize
    while i < n2 {
        var s = 0.0f64
        var j = 0usize
        while j < m.nc {
            s += newx[m.cols[j] * n2 + i] * m.coef[j]
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
}

// --- criteria. kinds: 0 AICc, 1 AIC, 2 BIC, 3 QAIC, 4 QAICc, 5 Cp

fn crit_aic(ll: f64, df: f64, k: f64) -> f64 { ret 0.0f64 - 2.0f64 * ll + k * df }

fn crit_bic(ll: f64, df: f64, n: f64) -> f64 { ret 0.0f64 - 2.0f64 * ll + math.log[f64](n) * df }

fn crit_aicc(ll: f64, df: f64, n: f64) -> f64 { ret 0.0f64 - 2.0f64 * ll + 2.0f64 * df * (1.0f64 + (df + 1.0f64) / (n - df - 1.0f64)) }

// QAIC / QAICc: the dispersion c-hat counts as one more parameter unless it is 1; c-hat below 1 is raised to 1
fn crit_qaic(ll: f64, df: f64, n: f64, chat0: f64, corrected: bool) -> f64 {
    var chat = chat0
    if chat < 1.0f64 { chat = 1.0f64 }
    var d = df
    if chat != 1.0f64 { d = df + 1.0f64 }
    if corrected { ret 0.0f64 - 2.0f64 * ll / chat + 2.0f64 * d * (1.0f64 + (d + 1.0f64) / (n - d - 1.0f64)) }
    ret 0.0f64 - 2.0f64 * ll / chat + 2.0f64 * d
}

// Mallows-type Cp of MuMIn: deviance + 2 scale (n - df.residual); scale is disp when it is a number, 1 for poisson and binomial, deviance / df.residual otherwise
fn crit_cp(m: *const Model, disp: f64) -> f64 {
    var scale = disp
    if is_nan(disp) {
        let bk = bg.base_kind(base_fam(m.fam))
        if (bk == 1u8 || bk == 2u8) && m.fam != 201u8 && m.fam != 202u8 && !is_nb(m.fam) { scale = 1.0f64 } else {
            if m.dfres > 0.0f64 { scale = m.dev / m.dfres } else { scale = nan() }
        }
    }
    ret m.dev + 2.0f64 * scale * (f64(m.n) - m.dfres)
}

fn ic_of(m: *const Model, kind: u8, chat: f64) -> f64 {
    let n = f64(m.n)
    if kind == 0u8 { ret crit_aicc(m.ll, m.npar, n) }
    if kind == 1u8 { ret crit_aic(m.ll, m.npar, 2.0f64) }
    if kind == 2u8 { ret crit_bic(m.ll, m.npar, n) }
    if kind == 3u8 { ret crit_qaic(m.ll, m.npar, n, chat, false) }
    if kind == 4u8 { ret crit_qaic(m.ll, m.npar, n, chat, true) }
    ret crit_cp(m, nan())
}

fn crit_weights(ic: []const f64, w: []f64) {
    var mn = ic[0usize]
    var i = 1usize
    while i < ic.len {
        if ic[i] < mn { mn = ic[i] }
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < ic.len {
        w[i] = math.exp[f64](0.0f64 - (ic[i] - mn) / 2.0f64)
        s += w[i]
        i += 1usize
    }
    i = 0usize
    while i < ic.len {
        w[i] = w[i] / s
        i += 1usize
    }
}

// --- small dense helpers

// inverse of the p by p matrix a (column-major) into out; false when singular
fn mat_inv(a: *mem.Arena, m: []const f64, p: usize, out: []f64) -> bool {
    let w = zalloc(a, p * p)
    var i = 0usize
    while i < p * p {
        w[i] = m[i]
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        out[i * p + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < p {
        var piv = c
        var r = c + 1usize
        while r < p {
            var u = w[c * p + r]
            if u < 0.0f64 { u = 0.0f64 - u }
            var v = w[c * p + piv]
            if v < 0.0f64 { v = 0.0f64 - v }
            if u > v { piv = r }
            r += 1usize
        }
        if w[c * p + piv] == 0.0f64 { ret false }
        if piv != c {
            var k = 0usize
            while k < p {
                let t1 = w[k * p + c]
                w[k * p + c] = w[k * p + piv]
                w[k * p + piv] = t1
                let t2 = out[k * p + c]
                out[k * p + c] = out[k * p + piv]
                out[k * p + piv] = t2
                k += 1usize
            }
        }
        let d = w[c * p + c]
        var k = 0usize
        while k < p {
            w[k * p + c] = w[k * p + c] / d
            out[k * p + c] = out[k * p + c] / d
            k += 1usize
        }
        r = 0usize
        while r < p {
            if r != c {
                let f = w[c * p + r]
                if f != 0.0f64 {
                    k = 0usize
                    while k < p {
                        w[k * p + r] = w[k * p + r] - f * w[k * p + c]
                        out[k * p + r] = out[k * p + r] - f * out[k * p + c]
                        k += 1usize
                    }
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    ret true
}

fn sample_sd(x: []const f64) -> f64 {
    let n = f64(x.len)
    var mu = 0.0f64
    var i = 0usize
    while i < x.len {
        mu += x[i]
        i += 1usize
    }
    mu = mu / n
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += (x[i] - mu) * (x[i] - mu)
        i += 1usize
    }
    ret math.sqrt[f64](s / (n - 1.0f64))
}

// --- std.coef: est and se of the fit scaled by sd(x) / sd(y) (partial false) or by MuMIn's partial standard deviation (true)
fn std_coef(a: *mem.Arena, m: *const Model, y: []const f64, partial: bool, est: []f64, se: []f64) {
    let nc = m.nc
    let n = m.n
    let sdy = sample_sd(y)
    let bx = zalloc(a, nc)
    var j = 0usize
    while j < nc {
        bx[j] = sample_sd(m.xs[j * n..j * n + n]) / sdy
        j += 1usize
    }
    if partial {
        let q = nc - 1usize
        let vif = zalloc(a, nc)
        vif[0usize] = 1.0f64
        if q > 0usize {
            let cr = zalloc(a, q * q)
            let ci = zalloc(a, q * q)
            var u = 0usize
            while u < q {
                var v = 0usize
                while v < q {
                    cr[v * q + u] = m.vcov[(v + 1usize) * nc + u + 1usize] / (math.sqrt[f64](m.vcov[(u + 1usize) * nc + u + 1usize]) * math.sqrt[f64](m.vcov[(v + 1usize) * nc + v + 1usize]))
                    v += 1usize
                }
                u += 1usize
            }
            if !mat_inv(a, cr, q, ci) { os.exit(72) }
            u = 0usize
            while u < q {
                vif[u + 1usize] = ci[u * q + u]
                u += 1usize
            }
        }
        // MuMIn passes p = sum(attr(mm, "assign") != 0) of a column-subsetted matrix, whose assign attribute is gone: p is 0
        let nn = f64(n)
        j = 0usize
        while j < nc {
            bx[j] = bx[j] * sdy * math.sqrt[f64](1.0f64 / vif[j]) * math.sqrt[f64]((nn - 1.0f64) / nn)
            j += 1usize
        }
    }
    j = 0usize
    while j < nc {
        est[j] = m.coef[j] * bx[j]
        se[j] = m.se[j] * bx[j]
        j += 1usize
    }
}

// --- r.squaredGLMM. link ids: 0 identity, 1 logit, 2 log, 3 inverse, 4 probit, 5 cloglog, 6 sqrt; family class 0 gaussian, 1 binomial, 2 poisson/quasipoisson, 3 Gamma.
// Writes the (R2m, R2c) pairs of the variance types r2glmm reports (binomial: theoretical, delta; poisson and Gamma(log): delta, lognormal, trigamma; gaussian and sqrt-link poisson: one)
// and answers how many pairs; 0 where MuMIn stops ("do not know how to calculate variance").
fn r2glmm(cls: u8, link: u8, var_fe: f64, var_re: f64, var_resid: f64, pmean: f64, lambda: f64, omega: f64, n: f64, out: []f64) -> usize {
    let vtot = var_fe + var_re
    var k = 0usize
    var pr: [3]f64 = zero
    if cls == 0u8 {
        pr[0usize] = var_resid
        k = 1usize
    }
    if cls == 1u8 {
        if link == 1u8 {
            pr[0usize] = 3.28986813369645f64 / n
            pr[1usize] = 1.0f64 / (n * pmean * (1.0f64 - pmean))
            k = 2usize
        }
        if link == 4u8 {
            let q = dist.qnorm(pmean, 0.0f64, 1.0f64, true, false) / 1.4142135623731f64
            let e = math.exp[f64](q * q)
            pr[0usize] = 1.0f64 / n
            pr[1usize] = 6.28318530717959f64 / n * pmean * (1.0f64 - pmean) * e * e
            k = 2usize
        }
        if link == 5u8 {
            let l1 = math.log[f64](1.0f64 - pmean)
            pr[0usize] = 1.64493406684823f64 / n
            pr[1usize] = pmean / n / (l1 * l1) / (1.0f64 - pmean)
            k = 2usize
        }
    }
    if cls == 4u8 {
        let vd = 1.0f64 / lambda + 1.0f64 / omega
        pr[0usize] = vd
        pr[1usize] = math.log[f64](1.0f64 + vd)
        pr[2usize] = sta.trigamma(1.0f64 / vd)
        k = 3usize
    }
    if (cls == 2u8 || cls == 3u8) && link == 2u8 {
        pr[0usize] = omega / lambda
        pr[1usize] = math.log[f64](1.0f64 + omega / lambda)
        pr[2usize] = sta.trigamma(lambda / omega)
        k = 3usize
    }
    if cls == 2u8 && link == 6u8 {
        pr[0usize] = 0.25f64 * omega
        k = 1usize
    }
    var i = 0usize
    while i < k {
        out[2usize * i] = var_fe / (vtot + pr[i])
        out[2usize * i + 1usize] = vtot / (vtot + pr[i])
        i += 1usize
    }
    ret k
}

fn sample_var_of(x: []const f64) -> f64 {
    let s = sample_sd(x)
    ret s * s
}

// r.squaredGLMM of an lm/glm fit m: varFE the variance of the fixed-effect linear predictor; the null (intercept only) fit gives pmean and lambda
fn r2_fit(a: *mem.Arena, x: []const f64, y: []const f64, m: *const Model, out: []f64) -> usize {
    let n = m.n
    let fit = zalloc(a, n)
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < m.nc {
            if !is_nan(m.coef[j]) { s += m.xs[j * n + i] * m.coef[j] }
            j += 1usize
        }
        fit[i] = s
        i += 1usize
    }
    let var_fe = sample_var_of(fit)
    let fb = base_fam(m.fam)
    let bk = bg.base_kind(fb)
    var lk = bg.link_kind(fb)
    let sigma = math.sqrt[f64](m.disp)
    var cls = 0u8
    if bk == 1u8 { cls = 1u8 }
    if bk == 2u8 { cls = 2u8 }
    if bk == 3u8 { cls = 3u8 }
    if bk == 4u8 { ret 0usize }
    if is_nb(m.fam) { cls = 4u8 }
    var nbin = 1.0f64
    if m.wt.len > 0usize {
        var sw = 0.0f64
        var q = 0usize
        while q < n {
            sw += m.wt[q]
            q += 1usize
        }
        nbin = sw / f64(n)
    }
    // intercept-only fit of the same family
    var one: [1]usize = zero
    one[0usize] = 0usize
    var pmean = 0.0f64
    var lambda = 0.0f64
    var omega = 1.0f64
    if cls == 1u8 || cls == 2u8 || cls == 4u8 {
        let nm0 = fit_ext(a, x, n, one[0usize..1usize], y, m.fam, m.wt, m.off, m.theta)
        if cls == 1u8 { pmean = bg.linkinv(fb, nm0.coef[0usize]) }
        if cls == 2u8 || cls == 4u8 { lambda = math.exp[f64](nm0.coef[0usize]) }
        if m.fam == 201u8 { omega = sigma }
        if cls == 4u8 { omega = m.theta_fam }
    }
    if cls == 3u8 {
        lambda = 1.0f64 / (sigma * sigma)
        omega = 1.0f64
    }
    ret r2glmm(cls, lk, var_fe, 0.0f64, sigma * sigma, pmean, lambda, omega, nbin, out)
}

// --- QIC and QICu (MuMIn getQIC): y, the fitted means mu (of the independence fit, or of the model itself for typeR), the robust covariance of the model, the naive covariance of the
// independence fit (p by p, column-major), the family class (0 gaussian, 1 binomial, 2 poisson, 3 Gamma, 4 inverse.gaussian) and the scale; out = (QIC, QICu, n)
fn qic(a: *mem.Arena, y: []const f64, mu: []const f64, vbeta: []const f64, vnaive: []const f64, p: usize, cls: u8, scale: f64, out: []f64) {
    let n = y.len
    var ql = 0.0f64
    var i = 0usize
    while i < n {
        if cls == 0u8 { ql += (y[i] - mu[i]) * (y[i] - mu[i]) }
        if cls == 1u8 { ql += y[i] * math.log[f64](mu[i] / (1.0f64 - mu[i])) + math.log[f64](1.0f64 - mu[i]) }
        if cls == 2u8 { ql += y[i] * math.log[f64](mu[i]) - mu[i] }
        if cls == 3u8 { ql += y[i] / mu[i] + math.log[f64](mu[i]) }
        if cls == 4u8 { ql += (mu[i] - 0.5f64 * y[i]) / (mu[i] * mu[i]) }
        i += 1usize
    }
    if cls == 0u8 { ql = 0.0f64 - 0.5f64 * ql / scale }
    if cls == 3u8 { ql = 0.0f64 - ql / scale }
    if cls == 4u8 { ql = ql / scale }
    let ai = zalloc(a, p * p)
    if !mat_inv(a, vnaive, p, ai) { os.exit(73) }
    var tr = 0.0f64
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            tr += ai[v * p + u] * vbeta[u * p + v]
            v += 1usize
        }
        u += 1usize
    }
    out[0usize] = 2.0f64 * (tr - ql)
    out[1usize] = 2.0f64 * (f64(p) - ql)
    out[2usize] = f64(n)
}

// --- stdize: (x - center) / scale per column of the n by nc matrix x. kinds: 0 numeric, 1 binary (0/1), 2 omitted. binary mode: 0 center, 1 scale, 2 binary (left as is), 3 half, 4 omit.
// center_on / scale_on switch the centring and the scaling of the numeric columns; sdmult multiplies the sd (stdize(scale = function(x) 2 * sd(x))). A zero scale becomes 1.
// out is the new matrix, centers and scales the used values (NaN where the column is untouched).
fn stdize_cols(x: []const f64, n: usize, nc: usize, kind: []const u8, binary: u8, center_on: bool, scale_on: bool, sdmult: f64, out: []f64, centers: []f64, scales: []f64) {
    var j = 0usize
    while j < nc {
        var do_c = false
        var do_s = false
        var cval = 0.0f64
        var sval = 1.0f64
        var mean = 0.0f64
        var i = 0usize
        while i < n {
            mean += x[j * n + i]
            i += 1usize
        }
        mean = mean / f64(n)
        if kind[j] == 0u8 {
            do_c = center_on
            do_s = scale_on
            cval = mean
            sval = sdmult * sample_sd(x[j * n..j * n + n])
        }
        if kind[j] == 1u8 && binary != 4u8 {
            if binary == 0u8 {
                do_c = true
                cval = mean
            }
            if binary == 1u8 {
                do_c = true
                do_s = true
                cval = mean
                sval = sdmult * sample_sd(x[j * n..j * n + n])
            }
            if binary == 3u8 {
                do_c = true
                cval = 0.5f64
            }
            if binary == 2u8 { do_c = true }
        }
        if do_s && sval == 0.0f64 { do_s = false }
        if !do_c && !do_s {
            centers[j] = nan()
            scales[j] = nan()
        }
        if do_c || do_s {
            if !do_c { cval = 0.0f64 }
            if !do_s { sval = 1.0f64 }
            centers[j] = cval
            scales[j] = sval
        }
        i = 0usize
        while i < n {
            if do_c || do_s { out[j * n + i] = (x[j * n + i] - cval) / sval } else { out[j * n + i] = x[j * n + i] }
            i += 1usize
        }
        j += 1usize
    }
}

// --- r.squaredGLMM of a mixed model from its pieces (MuMIn r.squaredGLMM.merMod): the fixed-effect predictions fe (n), for each random term the design columns z (n by q)
// and covariance sig (q by q); the null model's intercept fixef0 and covariances.

// .varRESum for one term: sum_i z_i' Sigma z_i / n
fn var_re_sum(z: []const f64, sig: []const f64, n: usize, q: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < q {
            var k = 0usize
            while k < q {
                s += z[j * n + i] * sig[k * q + j] * z[k * n + i]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret s / f64(n)
}

// cls 0 gaussian (var_resid = sigma^2), 1 binomial (link ids as r2glmm, nbin the mean prior weight), 2 poisson / quasipoisson (omega 1 or sigma), 3 Gamma(log) (var_resid = sigma^2, nu = 1 / sigma^2),
// 4 negative binomial (log; omega = theta). var_re and vt (the null model's variance sum) come from var_re_sum.
fn r2_mixed(cls: u8, link: u8, var_fe: f64, var_re: f64, var_resid: f64, fixef0: f64, vt: f64, omega: f64, nbin: f64, out: []f64) -> usize {
    var pmean = 0.0f64
    var lambda = 0.0f64
    if cls == 1u8 {
        var fam = 1u8
        if link == 4u8 { fam = 6u8 }
        if link == 5u8 { fam = 7u8 }
        let u = fixef0 * (1.0f64 + 2.0f64 * math.exp[f64](0.0f64 - 0.5f64 * vt)) / 6.0f64
        let e2 = math.exp[f64](2.0f64 * u)
        pmean = bg.linkinv(fam, fixef0 - 0.5f64 * vt * (e2 - 1.0f64) / (e2 + 1.0f64))
    }
    if cls == 2u8 || cls == 4u8 { lambda = math.exp[f64](fixef0 + 0.5f64 * vt) }
    if cls == 3u8 { lambda = 1.0f64 / var_resid }
    ret r2glmm(cls, link, var_fe, var_re, var_resid, pmean, lambda, omega, nbin, out)
}
