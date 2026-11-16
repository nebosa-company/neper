// R caret, the evaluation statistics: `confusion2` (confusionMatrix of a two-class table with the first level as the
// positive class: accuracy with its exact Clopper-Pearson interval, kappa, the no-information rate and its one-sided
// binomial p value, McNemar's p value, sensitivity, specificity, predictive values, F1, prevalence, detection rate and
// prevalence, balanced accuracy) and `post_resample` (RMSE, R squared as the squared correlation, MAE).
//
// Not here: multi-class tables, the `prevalence` argument, createDataPartition and the resampling indices,
// preProcess, varImp.

use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb

type Conf = struct { accuracy: f64, kappa: f64, lower: f64, upper: f64, nir: f64, pvalue: f64, mcnemar: f64, sens: f64, spec: f64, ppv: f64, npv: f64, f1: f64, prevalence: f64, detection_rate: f64, detection_prevalence: f64, balanced: f64 }

// tp: predicted and actual positive; fp: predicted positive, actually negative; fnn: predicted negative, actually positive
fn confusion2(tp: f64, fp: f64, fnn: f64, tn: f64, level: f64) -> Conf {
    var c: Conf = zero
    let n = tp + fp + fnn + tn
    let x = tp + tn
    c.accuracy = x / n
    let po = c.accuracy
    let pe = ((tp + fp) * (tp + fnn) + (fnn + tn) * (fp + tn)) / (n * n)
    c.kappa = (po - pe) / (1.0f64 - pe)
    let alpha = 1.0f64 - level
    if x == 0.0f64 { c.lower = 0.0f64 } else { c.lower = nb.qbeta(alpha / 2.0f64, x, n - x + 1.0f64, true, false) }
    if x == n { c.upper = 1.0f64 } else { c.upper = nb.qbeta(1.0f64 - alpha / 2.0f64, x + 1.0f64, n - x, true, false) }
    var big = tp + fnn
    if fp + tn > big { big = fp + tn }
    c.nir = big / n
    // binom.test(x, n, p = nir, alternative = "greater"): P(X >= x)
    c.pvalue = nb.pbinom(x - 1.0f64, n, c.nir, false, false)
    let d = math.abs[f64](fp - fnn) - 1.0f64
    if fp + fnn == 0.0f64 {
        c.mcnemar = 1.0f64 / 0.0f64 - 1.0f64 / 0.0f64
    } else {
        c.mcnemar = nm.pchisq(d * d / (fp + fnn), 1.0f64, false, false)
    }
    c.sens = tp / (tp + fnn)
    c.spec = tn / (fp + tn)
    c.ppv = tp / (tp + fp)
    c.npv = tn / (fnn + tn)
    c.f1 = 2.0f64 * c.ppv * c.sens / (c.ppv + c.sens)
    c.prevalence = (tp + fnn) / n
    c.detection_rate = tp / n
    c.detection_prevalence = (tp + fp) / n
    c.balanced = (c.sens + c.spec) / 2.0f64
    ret c
}

// postResample(pred, obs): (RMSE, R squared, MAE)
fn post_resample(pred: []const f64, obs: []const f64) -> (f64, f64, f64) {
    let n = f64(pred.len)
    var mp = 0.0f64
    var mo = 0.0f64
    var i = 0usize
    while i < pred.len {
        mp += pred[i]
        mo += obs[i]
        i += 1usize
    }
    mp = mp / n
    mo = mo / n
    var se = 0.0f64
    var ae = 0.0f64
    var spp = 0.0f64
    var soo = 0.0f64
    var spo = 0.0f64
    i = 0usize
    while i < pred.len {
        let d = pred[i] - obs[i]
        se += d * d
        ae += math.abs[f64](d)
        spp += (pred[i] - mp) * (pred[i] - mp)
        soo += (obs[i] - mo) * (obs[i] - mo)
        spo += (pred[i] - mp) * (obs[i] - mo)
        i += 1usize
    }
    ret (math.sqrt[f64](se / n), spo * spo / (spp * soo), ae / n)
}
