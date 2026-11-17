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

type Model = struct { nc: usize, n: usize, fam: u8, cols: []usize, xs: []f64, coef: []f64, se: []f64, vcov: []f64, dev: f64, dfres: f64, ll: f64, npar: f64, disp: f64, iter: usize }

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

fn base_fam(fam: u8) -> u8 {
    if fam == 200u8 { ret 0u8 }
    if fam == 201u8 { ret 2u8 }
    if fam == 202u8 { ret 1u8 }
    ret fam
}

// dispersion estimated (summary.glm): gaussian, Gamma, inverse.gaussian, the quasi families, lm
fn est_disp(fam: u8) -> bool {
    let bk = bg.base_kind(base_fam(fam))
    if fam == 201u8 || fam == 202u8 { ret true }
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

// Householder least squares of z on the n by nc matrix xw: coefficients, (X'X)^-1 and the residual sum of squares
fn wls(a: *mem.Arena, xw: []const f64, n: usize, nc: usize, zw: []const f64, tol: f64, coef: []f64, covu: []f64) -> f64 {
    let (f, qe) = dc.qr(a, xw, n, nc, tol)
    if qe != ok { os.exit(71) }
    let qty = zalloc(a, n)
    var i = 0usize
    while i < n {
        qty[i] = zw[i]
        i += 1usize
    }
    dc.qr_qty(&f, qty)
    let rinv = zalloc(a, nc * nc)
    var j = 0usize
    while j < nc {
        // column j of R^-1: back substitution of e_j
        var r = nc
        while r > 0usize {
            r -= 1usize
            var s = 0.0f64
            if r == j { s = 1.0f64 }
            var c = r + 1usize
            while c < nc {
                s = s - f.qr[c * n + r] * rinv[j * nc + c]
                c += 1usize
            }
            rinv[j * nc + r] = s / f.qr[r * n + r]
        }
        j += 1usize
    }
    j = nc
    while j > 0usize {
        j -= 1usize
        var s = qty[j]
        var c = j + 1usize
        while c < nc {
            s = s - f.qr[c * n + j] * coef[c]
            c += 1usize
        }
        coef[j] = s / f.qr[j * n + j]
    }
    j = 0usize
    while j < nc {
        var k = 0usize
        while k < nc {
            var s = 0.0f64
            var m = 0usize
            while m < nc {
                s += rinv[m * nc + j] * rinv[m * nc + k]
                m += 1usize
            }
            covu[k * nc + j] = s
            k += 1usize
        }
        j += 1usize
    }
    var rss = 0.0f64
    i = nc
    while i < n {
        rss += qty[i] * qty[i]
        i += 1usize
    }
    ret rss
}

// the family's aic term without the 2 rank (family()$aic), unit prior weights; NaN for the quasi families
fn fam_aic(fam: u8, y: []const f64, mu: []const f64, n: usize, dev: f64) -> f64 {
    if fam == 201u8 || fam == 202u8 { ret nan() }
    let bk = bg.base_kind(fam)
    let nn = f64(n)
    var s = 0.0f64
    var i = 0usize
    if bk == 0u8 { ret nn * (math.log[f64](2.0f64 * 3.141592653589793238462643383279f64 * dev / nn) + 1.0f64) + 2.0f64 }
    if bk == 1u8 {
        while i < n {
            if y[i] > 0.5f64 { s += math.log[f64](mu[i]) } else { s += math.log[f64](1.0f64 - mu[i]) }
            i += 1usize
        }
        ret 0.0f64 - 2.0f64 * s
    }
    if bk == 2u8 {
        while i < n {
            s += y[i] * math.log[f64](mu[i]) - mu[i] - nm.lgammafn(y[i] + 1.0f64)
            i += 1usize
        }
        ret 0.0f64 - 2.0f64 * s
    }
    if bk == 3u8 {
        let disp = dev / nn
        let shape = 1.0f64 / disp
        while i < n {
            let sc = mu[i] * disp
            s += (shape - 1.0f64) * math.log[f64](y[i]) - y[i] / sc - shape * math.log[f64](sc) - nm.lgammafn(shape)
            i += 1usize
        }
        ret 0.0f64 - 2.0f64 * s + 2.0f64
    }
    let disp = dev / nn
    while i < n {
        s += math.log[f64](y[i])
        i += 1usize
    }
    ret nn * (math.log[f64](disp * 2.0f64 * 3.141592653589793238462643383279f64) + 1.0f64) + 3.0f64 * s + 2.0f64
}

// lm (fam 200) or glm of y on the columns cols of x
fn fit_cols(a: *mem.Arena, x: []const f64, n: usize, cols: []const usize, y: []const f64, fam: u8) -> Model {
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
    let covu = zalloc(a, nc * nc)
    let nn = f64(n)
    m.dfres = nn - f64(nc)
    let pi = 3.141592653589793238462643383279f64
    if fam == 200u8 {
        let rss = wls(a, xs, n, nc, y, 1.0e-7f64, m.coef, covu)
        m.dev = rss
        m.disp = rss / m.dfres
        m.ll = 0.5f64 * (0.0f64 - nn * (math.log[f64](2.0f64 * pi) + 1.0f64 - math.log[f64](nn) + math.log[f64](rss)))
        m.npar = f64(nc) + 1.0f64
        j = 0usize
        while j < nc * nc {
            m.vcov[j] = covu[j] * m.disp
            j += 1usize
        }
        j = 0usize
        while j < nc {
            m.se[j] = math.sqrt[f64](m.vcov[j * nc + j])
            j += 1usize
        }
        ret m
    }
    let fb = base_fam(fam)
    let bk = bg.base_kind(fb)
    let mu = zalloc(a, n)
    let eta = zalloc(a, n)
    let z = zalloc(a, n)
    let xw = zalloc(a, n * nc)
    let wv = zalloc(a, n)
    let wsave = zalloc(a, n)
    var i = 0usize
    while i < n {
        var ms = y[i]
        if bk == 1u8 { ms = (y[i] + 0.5f64) / 2.0f64 }
        if bk == 2u8 { ms = y[i] + 0.1f64 }
        eta[i] = link_fun(fb, ms)
        mu[i] = bg.linkinv(fb, eta[i])
        i += 1usize
    }
    var devold = 0.0f64
    i = 0usize
    while i < n {
        devold += bg.dev_resid(fb, y[i], mu[i], 1.0f64)
        i += 1usize
    }
    var dev = devold
    var it = 0usize
    var done = false
    while !done && it < 25usize {
        it += 1usize
        i = 0usize
        while i < n {
            let me = bg.mu_eta(fb, eta[i])
            z[i] = eta[i] + (y[i] - mu[i]) / me
            wv[i] = math.sqrt[f64](me * me / bg.variance(fb, mu[i]))
            wsave[i] = wv[i] * wv[i]
            j = 0usize
            while j < nc {
                xw[j * n + i] = xs[j * n + i] * wv[i]
                j += 1usize
            }
            z[i] = z[i] * wv[i]
            i += 1usize
        }
        let _ = wls(a, xw, n, nc, z, 1.0e-11f64, m.coef, covu)
        i = 0usize
        while i < n {
            var s = 0.0f64
            j = 0usize
            while j < nc {
                s += xs[j * n + i] * m.coef[j]
                j += 1usize
            }
            eta[i] = s
            mu[i] = bg.linkinv(fb, s)
            i += 1usize
        }
        dev = 0.0f64
        i = 0usize
        while i < n {
            dev += bg.dev_resid(fb, y[i], mu[i], 1.0f64)
            i += 1usize
        }
        var df = dev - devold
        if df < 0.0f64 { df = 0.0f64 - df }
        var ad = dev
        if ad < 0.0f64 { ad = 0.0f64 - ad }
        if df / (ad + 0.1f64) < 1.0e-8f64 { done = true }
        devold = dev
    }
    m.iter = it
    m.dev = dev
    var disp = 1.0f64
    if est_disp(fam) {
        var s = 0.0f64
        i = 0usize
        while i < n {
            let r = (y[i] - mu[i]) / bg.mu_eta(fb, eta[i])
            s += wsave[i] * r * r
            i += 1usize
        }
        disp = s / m.dfres
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
    var p = f64(nc)
    if bk == 0u8 || bk == 3u8 || bk == 4u8 || fam == 201u8 || fam == 202u8 { p += 1.0f64 }
    m.npar = p
    m.ll = f64(0usize) + p - f64(nc) - fam_aic(fam, y, mu, n, dev) / 2.0f64
    if fam == 201u8 || fam == 202u8 { m.ll = nan() }
    ret m
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
        if (bk == 1u8 || bk == 2u8) && m.fam != 201u8 && m.fam != 202u8 { scale = 1.0f64 } else {
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
            s += m.xs[j * n + i] * m.coef[j]
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
    // intercept-only fit of the same family
    var one: [1]usize = zero
    one[0usize] = 0usize
    var pmean = 0.0f64
    var lambda = 0.0f64
    var omega = 1.0f64
    if cls == 1u8 || cls == 2u8 {
        let nm0 = fit_cols(a, x, n, one[0usize..1usize], y, m.fam)
        if cls == 1u8 { pmean = bg.linkinv(fb, nm0.coef[0usize]) }
        if cls == 2u8 { lambda = math.exp[f64](nm0.coef[0usize]) }
        if m.fam == 201u8 { omega = sigma }
    }
    if cls == 3u8 {
        lambda = 1.0f64 / (sigma * sigma)
        omega = 1.0f64
    }
    ret r2glmm(cls, lk, var_fe, 0.0f64, sigma * sigma, pmean, lambda, omega, 1.0f64, out)
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
