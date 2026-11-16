// R metafor rma.uni for an intercept-only model: the fixed-effect (FE) and random-effects estimates with the between-study variance by DerSimonian-Laird (DL), Hedges (HE),
// Hunter-Schmidt (HS), Sidik-Jonkman (SJ), the empirical Bayes and Paule-Mandel root (EB and PM, which solve the same Q(tau2) = k - 1 equation), and the ML and REML maxima,
// with the Wald test, the Q test and I2 and H2.
//
// Not here: moderators, the Knapp-Hartung test, the other estimators (GENQ and the rest), rma.mv, escalc, trimfill, regtest, ranktest, influence and permutest.

use e.math
use e.math.dist as dist
use e.math.nmath as nm

// Q(tau2) = sum w (y - ybar_w)^2 with w = 1 / (v + tau2)
fn q_of(y: []const f64, v: []const f64, tau2: f64) -> f64 {
    var sw = 0.0f64
    var swy = 0.0f64
    var i = 0usize
    while i < y.len {
        let w = 1.0f64 / (v[i] + tau2)
        sw += w
        swy += w * y[i]
        i += 1usize
    }
    let yb = swy / sw
    var q = 0.0f64
    i = 0usize
    while i < y.len {
        q += (y[i] - yb) * (y[i] - yb) / (v[i] + tau2)
        i += 1usize
    }
    ret q
}

// the log-likelihood (ML) or restricted log-likelihood (REML) at tau2, up to a constant
fn loglik(y: []const f64, v: []const f64, tau2: f64, reml: bool) -> f64 {
    var sw = 0.0f64
    var swy = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < y.len {
        let w = 1.0f64 / (v[i] + tau2)
        sw += w
        swy += w * y[i]
        sl += math.log[f64](v[i] + tau2)
        i += 1usize
    }
    let q = q_of(y, v, tau2)
    var r = sl + q
    if reml { r += math.log[f64](sw) }
    ret 0.0f64 - 0.5f64 * r
}

// the between-study variance by method: 0 FE (zero), 1 DL, 2 HE, 3 HS, 4 SJ, 5 PM or EB, 6 ML, 7 REML
fn tau2_of(y: []const f64, v: []const f64, method: usize) -> f64 {
    let k = f64(y.len)
    var sw = 0.0f64
    var sw2 = 0.0f64
    var my = 0.0f64
    var mv = 0.0f64
    var i = 0usize
    while i < y.len {
        let w = 1.0f64 / v[i]
        sw += w
        sw2 += w * w
        my += y[i]
        mv += v[i]
        i += 1usize
    }
    my = my / k
    mv = mv / k
    let q = q_of(y, v, 0.0f64)
    if method == 0usize { ret 0.0f64 }
    if method == 1usize {
        let t = (q - (k - 1.0f64)) / (sw - sw2 / sw)
        if t < 0.0f64 { ret 0.0f64 }
        ret t
    }
    var vy = 0.0f64
    i = 0usize
    while i < y.len {
        vy += (y[i] - my) * (y[i] - my)
        i += 1usize
    }
    if method == 2usize {
        let t = vy / (k - 1.0f64) - mv
        if t < 0.0f64 { ret 0.0f64 }
        ret t
    }
    if method == 3usize {
        let t = (q - k) / sw
        if t < 0.0f64 { ret 0.0f64 }
        ret t
    }
    if method == 4usize {
        let t0 = vy / k
        ret t0 * q_of(y, v, t0) / (k - 1.0f64)
    }
    if method == 5usize {
        if q_of(y, v, 0.0f64) <= k - 1.0f64 { ret 0.0f64 }
        var lo = 0.0f64
        var hi = 1.0f64
        while q_of(y, v, hi) > k - 1.0f64 { hi = hi * 2.0f64 }
        var it = 0usize
        while it < 200usize {
            let mid = 0.5f64 * (lo + hi)
            if q_of(y, v, mid) > k - 1.0f64 { lo = mid } else { hi = mid }
            it += 1usize
        }
        ret 0.5f64 * (lo + hi)
    }
    // ML and REML: golden-section search of the (restricted) log-likelihood on [0, 10 * max(var(y), mean v) + 1]
    let reml = method == 7usize
    var a = 0.0f64
    var b = 10.0f64 * (vy / k + mv) + 1.0f64
    let gr = 0.6180339887498949f64
    var c = b - gr * (b - a)
    var d = a + gr * (b - a)
    var fc = loglik(y, v, c, reml)
    var fd = loglik(y, v, d, reml)
    var it = 0usize
    while it < 300usize {
        if fc > fd {
            b = d
            d = c
            fd = fc
            c = b - gr * (b - a)
            fc = loglik(y, v, c, reml)
        } else {
            a = c
            c = d
            fc = fd
            d = a + gr * (b - a)
            fd = loglik(y, v, d, reml)
        }
        it += 1usize
    }
    let t = 0.5f64 * (a + b)
    // the boundary at zero when the likelihood is decreasing there
    if loglik(y, v, 0.0f64, reml) >= loglik(y, v, t, reml) { ret 0.0f64 }
    ret t
}

// what: 0 beta, 1 se, 2 tau2, 3 I2, 4 H2, 5 QE, 6 QEp, 7 zval, 8 pval, 9 ci.lb, 10 ci.ub
fn rma(y: []const f64, v: []const f64, method: usize, what: usize) -> f64 {
    let k = f64(y.len)
    let tau2 = tau2_of(y, v, method)
    var sw = 0.0f64
    var swy = 0.0f64
    var s0w = 0.0f64
    var s0w2 = 0.0f64
    var i = 0usize
    while i < y.len {
        let w = 1.0f64 / (v[i] + tau2)
        sw += w
        swy += w * y[i]
        s0w += 1.0f64 / v[i]
        s0w2 += 1.0f64 / (v[i] * v[i])
        i += 1usize
    }
    let beta = swy / sw
    let se = math.sqrt[f64](1.0f64 / sw)
    let qe = q_of(y, v, 0.0f64)
    // I2 and H2 from the DerSimonian-Laird variance for FE and from the estimate itself otherwise
    let s2 = (k - 1.0f64) / (s0w - s0w2 / s0w)
    var t2 = tau2
    if method == 0usize { t2 = tau2_of(y, v, 1usize) }
    var h2 = (t2 + s2) / s2
    var i2 = 100.0f64 * t2 / (t2 + s2)
    if method == 0usize {
        h2 = qe / (k - 1.0f64)
        i2 = 0.0f64
        if qe > k - 1.0f64 { i2 = 100.0f64 * (qe - (k - 1.0f64)) / qe }
    }
    if what == 0usize { ret beta }
    if what == 1usize { ret se }
    if what == 2usize { ret tau2 }
    if what == 3usize { ret i2 }
    if what == 4usize { ret h2 }
    if what == 5usize { ret qe }
    if what == 6usize { ret nm.pchisq(qe, k - 1.0f64, false, false) }
    let z = beta / se
    if what == 7usize { ret z }
    if what == 8usize { ret 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false) }
    let zc = dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false)
    if what == 9usize { ret beta - zc * se }
    ret beta + zc * se
}
