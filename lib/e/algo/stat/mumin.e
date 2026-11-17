// R MuMIn: AICc, the Akaike weights of a set of models, and the model-averaged coefficient (full average, a missing term counting as 0) with
// its Std. Error sqrt(sum w (se^2 + (b - bar)^2)).
//
// Also here: the "Adjusted SE" of the full average.
//
// Over summaries only (log likelihood, coefficients, standard errors). The fits, dredge, model.sel, model.avg on a table, QIC, BIC, Cp, std.coef,
// r.squaredGLMM and stdize are in mumin_fit and mumin_dredge.

use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb

// AICc = -2 logLik + 2 k + 2 k (k + 1) / (n - k - 1); k counts every estimated parameter, the residual variance included
fn aicc(loglik: f64, k: f64, n: f64) -> f64 { ret 0.0f64 - 2.0f64 * loglik + 2.0f64 * k * (1.0f64 + (k + 1.0f64) / (n - k - 1.0f64)) }

// the Akaike weights of m criterion values into w
fn akaike_weights(ic: []const f64, w: []f64) {
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

// the full-average estimate and its Std. Error for one coefficient from the per-model estimates and standard errors (0 where absent)
fn average_full(est: []const f64, se: []const f64, w: []const f64) -> (f64, f64) {
    var bar = 0.0f64
    var i = 0usize
    while i < est.len {
        bar += w[i] * est[i]
        i += 1usize
    }
    var v = 0.0f64
    i = 0usize
    while i < est.len {
        v += w[i] * (se[i] * se[i] + (est[i] - bar) * (est[i] - bar))
        i += 1usize
    }
    ret (bar, math.sqrt[f64](v))
}

// the conditional average of one coefficient: only the models that contain the term (present[i] true), weights renormalised over them;
// (estimate, Std. Error, relative importance = the summed weight of those models)
fn average_conditional(est: []const f64, se: []const f64, w: []const f64, present: []const bool) -> (f64, f64, f64) {
    var sw = 0.0f64
    var i = 0usize
    while i < est.len {
        if present[i] { sw += w[i] }
        i += 1usize
    }
    var bar = 0.0f64
    i = 0usize
    while i < est.len {
        if present[i] { bar += w[i] / sw * est[i] }
        i += 1usize
    }
    var v = 0.0f64
    i = 0usize
    while i < est.len {
        if present[i] { v += w[i] / sw * (se[i] * se[i] + (est[i] - bar) * (est[i] - bar)) }
        i += 1usize
    }
    ret (bar, math.sqrt[f64](v), sw)
}

// QAIC and QAICc of a model of log likelihood ll with k estimated parameters (the dispersion c-hat counted as one more) fitted to n observations
fn qaic(ll: f64, k: f64, n: f64, chat: f64, corrected: bool) -> f64 {
    let df = k + 1.0f64
    var v = 0.0f64 - 2.0f64 * ll / chat + 2.0f64 * df
    if corrected { v = 0.0f64 - 2.0f64 * ll / chat + 2.0f64 * df * (1.0f64 + (df + 1.0f64) / (n - df - 1.0f64)) }
    ret v
}

// the full average with the "Adjusted SE" of par.avg: each model's variance is inflated by (qt(0.975, df) / qnorm(0.975))^2, df the model's residual degrees of freedom, or infinite (factor 1) where the term is absent (df[i] <= 0);
// answers (estimate, Std. Error, Adjusted SE)
fn average_full_adj(est: []const f64, se: []const f64, df: []const f64, w: []const f64) -> (f64, f64, f64) {
    var bar = 0.0f64
    var i = 0usize
    while i < est.len {
        bar += w[i] * est[i]
        i += 1usize
    }
    let zq = dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false)
    var v = 0.0f64
    var va = 0.0f64
    i = 0usize
    while i < est.len {
        var z = 1.0f64
        if df[i] > 0.0f64 {
            let t = nb.qt(0.975f64, df[i], true, false) / zq
            z = t * t
        }
        let d2 = (est[i] - bar) * (est[i] - bar)
        v += w[i] * (se[i] * se[i] + d2)
        va += w[i] * (se[i] * se[i] * z + d2)
        i += 1usize
    }
    ret (bar, math.sqrt[f64](v), math.sqrt[f64](va))
}

// the conditional average's "Adjusted SE": the same inflation over only the models that contain the term (present[i]), weights renormalised over them
fn average_conditional_adj(est: []const f64, se: []const f64, df: []const f64, w: []const f64, present: []const bool) -> f64 {
    var sw = 0.0f64
    var i = 0usize
    while i < est.len {
        if present[i] { sw += w[i] }
        i += 1usize
    }
    var bar = 0.0f64
    i = 0usize
    while i < est.len {
        if present[i] { bar += w[i] / sw * est[i] }
        i += 1usize
    }
    let zq = dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false)
    var va = 0.0f64
    i = 0usize
    while i < est.len {
        if present[i] {
            let t = nb.qt(0.975f64, df[i], true, false) / zq
            va += w[i] / sw * (se[i] * se[i] * t * t + (est[i] - bar) * (est[i] - bar))
        }
        i += 1usize
    }
    ret math.sqrt[f64](va)
}
