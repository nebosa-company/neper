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
use e.algo.rand.r as rng
use e.mem

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

// ---- the resampling indices of caret, drawing with R's sample.int ----

// createResample(y, times = 1): one bootstrap sample of the n positions, sorted (1-based)
fn create_resample(a: *mem.Arena, r: *rng.Rng, n: usize, out: []i64) -> err {
    let (s, e) = rng.sample_int(a, r, i64(n), i64(n), true)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        out[i] = s[i]
        i += 1usize
    }
    var j = 1usize
    while j < n {
        let key = out[j]
        var q = j
        while q > 0usize && out[q - 1usize] > key {
            out[q] = out[q - 1usize]
            q -= 1usize
        }
        out[q] = key
        j += 1usize
    }
    ret ok
}

// createFolds(y, k, list = FALSE) for a factor y given as class codes 0.. in the order of its levels: the fold (1-based) of every observation
fn create_folds(a: *mem.Arena, r: *rng.Rng, cls: []const i64, k: usize, fold: []i64) -> err {
    let n = cls.len
    var i = 0usize
    if k >= n {
        while i < n {
            fold[i] = i64(i + 1usize)
            i += 1usize
        }
        ret ok
    }
    var m = 0i64
    while i < n {
        if cls[i] + 1i64 > m { m = cls[i] + 1i64 }
        fold[i] = 0i64
        i += 1usize
    }
    var c = 0i64
    while c < m {
        var cnt = 0usize
        i = 0usize
        while i < n {
            if cls[i] == c { cnt += 1usize }
            i += 1usize
        }
        if cnt > 0usize {
            let minr = cnt / k
            let (seqv, e1) = mem.alloc[i64](a, cnt)
            if e1 != ok { ret e1 }
            if minr > 0usize {
                let spares = cnt % k
                var q = 0usize
                while q < minr * k {
                    seqv[q] = i64(q % k + 1usize)
                    q += 1usize
                }
                if spares > 0usize {
                    let (sp, e2) = rng.sample_int(a, r, i64(k), i64(spares), false)
                    if e2 != ok { ret e2 }
                    var t = 0usize
                    while t < spares {
                        seqv[minr * k + t] = sp[t]
                        t += 1usize
                    }
                }
                let (perm, e3) = rng.sample_int(a, r, i64(cnt), i64(cnt), false)
                if e3 != ok { ret e3 }
                var at = 0usize
                i = 0usize
                while i < n {
                    if cls[i] == c {
                        fold[i] = seqv[usize(perm[at] - 1i64)]
                        at += 1usize
                    }
                    i += 1usize
                }
            } else {
                let (sp, e4) = rng.sample_int(a, r, i64(k), i64(cnt), false)
                if e4 != ok { ret e4 }
                var at = 0usize
                i = 0usize
                while i < n {
                    if cls[i] == c {
                        fold[i] = sp[at]
                        at += 1usize
                    }
                    i += 1usize
                }
            }
        }
        c += 1i64
    }
    ret ok
}

// groupKFold(group, k): each group (a code 0.. in order of first appearance, m groups) goes to one of k folds drawn with replacement; the test fold of every observation (1-based)
fn group_kfold(a: *mem.Arena, r: *rng.Rng, grp: []const i64, m: usize, k: usize, fold: []i64) -> err {
    let (gf, e) = rng.sample_int(a, r, i64(k), i64(m), true)
    if e != ok { ret e }
    var i = 0usize
    while i < grp.len {
        fold[i] = gf[usize(grp[i])]
        i += 1usize
    }
    ret ok
}

// createTimeSlices(y, initialWindow, horizon, fixedWindow, skip): the number of slices, and for slice s (0-based) the 1-based training start and stop and test start and stop in out[4 s ..]
fn create_time_slices(n: usize, initial: usize, horizon: usize, fixed: bool, skip: usize, out: []i64) -> usize {
    var cnt = 0usize
    var stop = initial
    while stop + horizon <= n {
        var start = 1usize
        if fixed { start = stop - initial + 1usize }
        out[4usize * cnt] = i64(start)
        out[4usize * cnt + 1usize] = i64(stop)
        out[4usize * cnt + 2usize] = i64(stop + 1usize)
        out[4usize * cnt + 3usize] = i64(stop + horizon)
        cnt += 1usize
        stop += skip + 1usize
    }
    ret cnt
}
