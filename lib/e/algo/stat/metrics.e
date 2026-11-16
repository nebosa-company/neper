// Performance metrics of R yardstick and ModelMetrics on plain vectors. Numeric: rmse, mae, mse, rsq (the
// squared correlation), rsq_trad, ccc, huber_loss, mape, smape, mase (lag 1). Binary classification with a
// 0/1 truth (1 the event) and either a probability or a 0/1 prediction: accuracy, kap, f_meas, mcc,
// bal_accuracy, j_index, precision, recall, specificity, ppv and npv at a cutoff (a prediction is positive
// when the probability is above the cutoff), auc, gini, logloss, brier and the classification error.
//
// Not here: multiclass averaging (macro, micro, weighted), pr_auc, gain_capture, lift_curve, iic and the
// grouped and resampled forms.

use e.algo.sort
use e.math
use e.mem

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    var m = s / f64(x.len)
    var t = 0.0f64
    i = 0usize
    while i < x.len {
        t += x[i] - m
        i += 1usize
    }
    ret m + t / f64(x.len)
}

fn mse(t: []const f64, e: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < t.len {
        s += (t[i] - e[i]) * (t[i] - e[i])
        i += 1usize
    }
    ret s / f64(t.len)
}

fn rmse(t: []const f64, e: []const f64) -> f64 { ret math.sqrt[f64](mse(t, e)) }

fn mae(t: []const f64, e: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < t.len {
        s += math.abs[f64](t[i] - e[i])
        i += 1usize
    }
    ret s / f64(t.len)
}

fn cor(t: []const f64, e: []const f64) -> f64 {
    let mt = mean_of(t)
    let me = mean_of(e)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < t.len {
        sxy += (t[i] - mt) * (e[i] - me)
        sxx += (t[i] - mt) * (t[i] - mt)
        syy += (e[i] - me) * (e[i] - me)
        i += 1usize
    }
    ret sxy / math.sqrt[f64](sxx * syy)
}

fn rsq(t: []const f64, e: []const f64) -> f64 {
    let r = cor(t, e)
    ret r * r
}

fn rsq_trad(t: []const f64, e: []const f64) -> f64 {
    let mt = mean_of(t)
    var rss = 0.0f64
    var tss = 0.0f64
    var i = 0usize
    while i < t.len {
        rss += (t[i] - e[i]) * (t[i] - e[i])
        tss += (t[i] - mt) * (t[i] - mt)
        i += 1usize
    }
    ret 1.0f64 - rss / tss
}

// Lin's concordance correlation coefficient with the divisor n - 1 in the covariance and variances
fn ccc(t: []const f64, e: []const f64) -> f64 {
    let n = f64(t.len)
    let mt = mean_of(t)
    let me = mean_of(e)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < t.len {
        sxy += (t[i] - mt) * (e[i] - me)
        sxx += (t[i] - mt) * (t[i] - mt)
        syy += (e[i] - me) * (e[i] - me)
        i += 1usize
    }
    ret 2.0f64 * (sxy / (n - 1.0f64)) / (sxx / (n - 1.0f64) + syy / (n - 1.0f64) + (mt - me) * (mt - me))
}

fn huber_loss(t: []const f64, e: []const f64, delta: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < t.len {
        let er = math.abs[f64](t[i] - e[i])
        if er <= delta { s += 0.5f64 * er * er } else { s += delta * (er - 0.5f64 * delta) }
        i += 1usize
    }
    ret s / f64(t.len)
}

fn mape(t: []const f64, e: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < t.len {
        s += math.abs[f64]((t[i] - e[i]) / t[i])
        i += 1usize
    }
    ret 100.0f64 * s / f64(t.len)
}

fn smape(t: []const f64, e: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < t.len {
        s += math.abs[f64](t[i] - e[i]) / ((math.abs[f64](t[i]) + math.abs[f64](e[i])) / 2.0f64)
        i += 1usize
    }
    ret 100.0f64 * s / f64(t.len)
}

// mase with the naive one-step forecast of the truth as the scale
fn mase(t: []const f64, e: []const f64) -> f64 {
    var scale = 0.0f64
    var i = 1usize
    while i < t.len {
        scale += math.abs[f64](t[i] - t[i - 1usize])
        i += 1usize
    }
    scale = scale / f64(t.len - 1usize)
    ret mae(t, e) / scale
}

// confusion counts of a 0/1 truth against a 0/1 prediction: (tp, fp, fn, tn)
fn confusion(t: []const f64, pred: []const f64) -> (f64, f64, f64, f64) {
    var tp = 0.0f64
    var fp = 0.0f64
    var fnn = 0.0f64
    var tn = 0.0f64
    var i = 0usize
    while i < t.len {
        let a = t[i] == 1.0f64
        let b = pred[i] == 1.0f64
        if a && b { tp += 1.0f64 } else if !a && b { fp += 1.0f64 } else if a && !b { fnn += 1.0f64 } else { tn += 1.0f64 }
        i += 1usize
    }
    ret (tp, fp, fnn, tn)
}

// the class metrics from counts: which 0 accuracy 1 kap 2 f_meas(beta) 3 mcc 4 bal_accuracy 5 j_index 6 precision 7 recall 8 specificity 9 npv
fn class_metric(tp: f64, fp: f64, fnn: f64, tn: f64, which: u8, beta: f64) -> f64 {
    let n = tp + fp + fnn + tn
    let prec = tp / (tp + fp)
    let rec = tp / (tp + fnn)
    let spec = tn / (tn + fp)
    if which == 0u8 { ret (tp + tn) / n }
    if which == 1u8 {
        let po = (tp + tn) / n
        let pe = ((tp + fp) * (tp + fnn) + (fnn + tn) * (fp + tn)) / (n * n)
        ret (po - pe) / (1.0f64 - pe)
    }
    if which == 2u8 { ret (1.0f64 + beta * beta) * prec * rec / (beta * beta * prec + rec) }
    if which == 3u8 { ret (tp * tn - fp * fnn) / math.sqrt[f64]((tp + fp) * (tp + fnn) * (tn + fp) * (tn + fnn)) }
    if which == 4u8 { ret (rec + spec) / 2.0f64 }
    if which == 5u8 { ret rec + spec - 1.0f64 }
    if which == 6u8 { ret prec }
    if which == 7u8 { ret rec }
    if which == 8u8 { ret spec }
    ret tn / (tn + fnn)
}

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// the area under the ROC curve by the Mann-Whitney statistic with ties counting one half
fn auc(t: []const f64, p: []const f64) -> f64 {
    var npos = 0.0f64
    var nneg = 0.0f64
    var s = 0.0f64
    var i = 0usize
    while i < t.len {
        if t[i] == 1.0f64 {
            npos += 1.0f64
            var j = 0usize
            while j < t.len {
                if t[j] != 1.0f64 {
                    if p[i] > p[j] { s += 1.0f64 } else if p[i] == p[j] { s += 0.5f64 }
                }
                j += 1usize
            }
        } else {
            nneg += 1.0f64
        }
        i += 1usize
    }
    ret s / (npos * nneg)
}

// ModelMetrics gini: the normalised Gini of the actuals ordered by decreasing prediction (ties keep their
// order) over that of the actuals sorted decreasingly, each (sum(cumsum(a) / sum(a)) - (n + 1) / 2) / n
fn gini_part(a: []const f64) -> f64 {
    let n = f64(a.len)
    var tot = 0.0f64
    var i = 0usize
    while i < a.len {
        tot += a[i]
        i += 1usize
    }
    var cum = 0.0f64
    var s = 0.0f64
    i = 0usize
    while i < a.len {
        cum += a[i]
        s += cum / tot
        i += 1usize
    }
    ret (s - (n + 1.0f64) / 2.0f64) / n
}

fn gini(arena: *mem.Arena, t: []const f64, p: []const f64) -> (f64, err) {
    let n = t.len
    let (ord, oe) = mem.alloc[usize](arena, n)
    if oe != ok { ret (0.0f64, oe) }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    // insertion sort by decreasing prediction, stable
    i = 1usize
    while i < n {
        var j = i
        while j > 0usize && p[ord[j - 1usize]] < p[ord[j]] {
            let tmp = ord[j]
            ord[j] = ord[j - 1usize]
            ord[j - 1usize] = tmp
            j -= 1usize
        }
        i += 1usize
    }
    let (a1, e1) = mem.alloc[f64](arena, n)
    let (a2, e2) = mem.alloc[f64](arena, n)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    var ones = 0usize
    i = 0usize
    while i < n {
        a1[i] = t[ord[i]]
        if t[i] == 1.0f64 { ones += 1usize }
        i += 1usize
    }
    i = 0usize
    while i < n {
        if i < ones { a2[i] = 1.0f64 } else { a2[i] = 0.0f64 }
        i += 1usize
    }
    ret (gini_part(a1) / gini_part(a2), ok)
}

fn logloss(t: []const f64, p: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < t.len {
        s += t[i] * math.log[f64](p[i]) + (1.0f64 - t[i]) * math.log[f64](1.0f64 - p[i])
        i += 1usize
    }
    ret 0.0f64 - s / f64(t.len)
}

// the probabilities as 0/1 predictions at a cutoff: positive when above it (or at it with `inclusive`)
fn threshold(a: *mem.Arena, p: []const f64, cutoff: f64, inclusive: bool) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, p.len)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < p.len {
        if p[i] > cutoff || (inclusive && p[i] == cutoff) { r[i] = 1.0f64 } else { r[i] = 0.0f64 }
        i += 1usize
    }
    ret (r, ok)
}
