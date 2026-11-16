// Performance metrics of R yardstick and ModelMetrics on plain vectors. Numeric: rmse, mae, mse, rsq (the
// squared correlation), rsq_trad, ccc, huber_loss, mape, smape, mase (lag 1). Binary classification with a
// 0/1 truth (1 the event) and either a probability or a 0/1 prediction: accuracy, kap, f_meas, mcc,
// bal_accuracy, j_index, precision, recall, specificity, ppv and npv at a cutoff (a prediction is positive
// when the probability is above the cutoff), auc, gini, logloss, brier and the classification error.
//
// And multiclass averaging (macro, micro, macro_weighted) of the class metrics, pr_auc, gain_capture, lift_curve and iic. Not here: the
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

// iic: the correlation times the ratio of the smaller to the larger mean absolute error of the under- and over-predictions
fn iic(t: []const f64, e: []const f64) -> f64 {
    var sn = 0.0f64
    var sp = 0.0f64
    var nn = 0usize
    var np = 0usize
    var i = 0usize
    while i < t.len {
        let d = t[i] - e[i]
        if d < 0.0f64 {
            sn += math.abs[f64](d)
            nn += 1usize
        } else {
            sp += math.abs[f64](d)
            np += 1usize
        }
        i += 1usize
    }
    let mn = sn / f64(nn)
    let mp = sp / f64(np)
    var lo = mn
    var hi = mp
    if mp < mn {
        lo = mp
        hi = mn
    }
    ret cor(t, e) * (lo / hi)
}

// a stable ordering of x, largest first (ties keep their positions), as R's order(x, decreasing = TRUE)
fn order_desc(a: *mem.Arena, x: []const f64) -> ([]usize, err) {
    let n = x.len
    let (idx, e1) = mem.alloc[usize](a, n)
    let (buf, e2) = mem.alloc[usize](a, n)
    if e1 != ok { ret (idx, e1) }
    if e2 != ok { ret (idx, e2) }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    var w = 1usize
    while w < n {
        var lo = 0usize
        while lo < n {
            var mid = lo + w
            if mid > n { mid = n }
            var hi = lo + 2usize * w
            if hi > n { hi = n }
            var l = lo
            var r = mid
            var b = lo
            while l < mid && r < hi {
                if x[idx[r]] > x[idx[l]] {
                    buf[b] = idx[r]
                    r += 1usize
                } else {
                    buf[b] = idx[l]
                    l += 1usize
                }
                b += 1usize
            }
            while l < mid {
                buf[b] = idx[l]
                l += 1usize
                b += 1usize
            }
            while r < hi {
                buf[b] = idx[r]
                r += 1usize
                b += 1usize
            }
            lo = lo + 2usize * w
        }
        i = 0usize
        while i < n {
            idx[i] = buf[i]
            i += 1usize
        }
        w = w * 2usize
    }
    ret (idx, ok)
}

// pr_auc for a 0/1 truth (1 the event) and a probability: the trapezoid area under precision against recall, thresholds from the
// largest estimate down with the point (recall 0, precision 1) first
fn pr_auc(a: *mem.Arena, t: []const f64, p: []const f64) -> f64 {
    let n = t.len
    let (ord, e) = order_desc(a, p)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        if t[i] == 1.0f64 { tot += 1.0f64 }
        i += 1usize
    }
    var tp = 0.0f64
    var fp = 0.0f64
    var prev_r = 0.0f64
    var prev_p = 1.0f64
    var area = 0.0f64
    i = 0usize
    while i < n {
        if t[ord[i]] == 1.0f64 { tp += 1.0f64 } else { fp += 1.0f64 }
        let last_of_tie = i + 1usize == n || p[ord[i + 1usize]] != p[ord[i]]
        if last_of_tie {
            let r = tp / tot
            let pr = tp / (tp + fp)
            area += (r - prev_r) * ((prev_p + pr) / 2.0f64)
            prev_r = r
            prev_p = pr
        }
        i += 1usize
    }
    ret area
}

// the gain curve of a 0/1 truth: percent tested and percent found at every distinct estimate, after the origin
fn gain_curve(a: *mem.Arena, t: []const f64, p: []const f64) -> ([]f64, []f64, []f64, []f64, err) {
    let n = t.len
    let (ord, e) = order_desc(a, p)
    let (ptest, e1) = mem.alloc[f64](a, n + 1usize)
    let (pfound, e2) = mem.alloc[f64](a, n + 1usize)
    let (cn, e3) = mem.alloc[f64](a, n + 1usize)
    let (cf, e4) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (ptest, pfound, cn, cf, e) }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (ptest, pfound, cn, cf, e1) }
    var nev = 0.0f64
    var i = 0usize
    while i < n {
        if t[i] == 1.0f64 { nev += 1.0f64 }
        i += 1usize
    }
    ptest[0usize] = 0.0f64
    pfound[0usize] = 0.0f64
    cn[0usize] = 0.0f64
    cf[0usize] = 0.0f64
    var tested = 0.0f64
    var found = 0.0f64
    var m = 1usize
    i = 0usize
    while i < n {
        tested += 1.0f64
        if t[ord[i]] == 1.0f64 { found += 1.0f64 }
        let last_of_tie = i + 1usize == n || p[ord[i + 1usize]] != p[ord[i]]
        if last_of_tie {
            ptest[m] = (tested / f64(n)) * 100.0f64
            pfound[m] = (found / nev) * 100.0f64
            cn[m] = tested
            cf[m] = found
            m += 1usize
        }
        i += 1usize
    }
    ret (ptest[0usize..m], pfound[0usize..m], cn[0usize..m], cf[0usize..m], ok)
}

// gain_capture for a 0/1 truth: the gain-curve area against the no-skill baseline, scaled by the perfect curve
fn gain_capture(a: *mem.Arena, t: []const f64, p: []const f64) -> f64 {
    let (pt, pf, cn, cf, e) = gain_curve(a, t, p)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var area = 0.0f64
    var i = 0usize
    while i + 1usize < pt.len {
        area += ((pf[i] + pf[i + 1usize]) / 2.0f64) * (pt[i + 1usize] - pt[i])
        i += 1usize
    }
    let scaler = 1.0f64 / (100.0f64 * 100.0f64)
    area = area * scaler
    var maxev = cf[0usize]
    i = 0usize
    while i < cf.len {
        if cf[i] > maxev { maxev = cf[i] }
        i += 1usize
    }
    let slope = 1.0f64 / (maxev / cn[cn.len - 1usize])
    let perfect = 100.0f64 / slope
    let tri = (perfect * 100.0f64) / 2.0f64
    let rect = (100.0f64 - perfect) * 100.0f64
    let perf_auc = (rect + tri) * scaler
    ret (area - 0.5f64) / (perf_auc - 0.5f64)
}

// the lift curve values percent found / percent tested at the gain-curve points after the origin
fn lift_curve(a: *mem.Arena, t: []const f64, p: []const f64) -> ([]f64, err) {
    let (pt, pf, cn, cf, e) = gain_curve(a, t, p)
    if e != ok { ret (pt, e) }
    let (out, oe) = mem.alloc[f64](a, pt.len)
    if oe != ok { ret (out, oe) }
    var i = 1usize
    while i < pt.len {
        out[i - 1usize] = pf[i] / pt[i]
        i += 1usize
    }
    ret (out[0usize..pt.len - 1usize], ok)
}

// the multiclass average of a one-vs-all binary metric: which 0 pr_auc, 1 gain_capture, 2 roc_auc; probs is n by k row-major, truth the 0-based
// class; estimator 0 macro, 2 macro_weighted
fn one_vs_all(a: *mem.Arena, truth: []const f64, probs: []const f64, k: usize, which: u8, estimator: u8) -> f64 {
    let n = truth.len
    let (tb, e1) = mem.alloc[f64](a, n)
    let (pb, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var num = 0.0f64
    var den = 0.0f64
    var c = 0usize
    while c < k {
        var cnt = 0.0f64
        var i = 0usize
        while i < n {
            tb[i] = 0.0f64
            if truth[i] == f64(c) {
                tb[i] = 1.0f64
                cnt += 1.0f64
            }
            pb[i] = probs[i * k + c]
            i += 1usize
        }
        var v = 0.0f64
        if which == 0u8 { v = pr_auc(a, tb, pb) } else if which == 1u8 { v = gain_capture(a, tb, pb) } else { v = auc(tb, pb) }
        var w = 1.0f64 / f64(k)
        if estimator == 2u8 { w = cnt / f64(n) }
        num += v * w
        den += w
        c += 1usize
    }
    ret num / den
}

// a multiclass class metric from the k by k confusion matrix (rows the estimate, columns the truth, row-major): which 0 precision,
// 1 recall, 2 spec, 3 f_meas, 4 bal_accuracy, 5 j_index, 6 kap, 7 mcc, 8 accuracy; estimator 0 macro, 1 micro, 2 macro_weighted
fn multiclass(conf: []const f64, k: usize, which: u8, estimator: u8, beta: f64) -> f64 {
    var total = 0.0f64
    var tr = 0.0f64
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            total += conf[i * k + j]
            j += 1usize
        }
        tr += conf[i * k + i]
        i += 1usize
    }
    if which == 8u8 { ret tr / total }
    var sr2 = 0.0f64
    var sc2 = 0.0f64
    var pe = 0.0f64
    var cross = 0.0f64
    i = 0usize
    while i < k {
        var r = 0.0f64
        var c = 0.0f64
        var j = 0usize
        while j < k {
            r += conf[i * k + j]
            c += conf[j * k + i]
            j += 1usize
        }
        sr2 += r * r
        sc2 += c * c
        pe += r * c
        cross += r * c
        i += 1usize
    }
    if which == 6u8 {
        let po = tr / total
        let pexp = pe / (total * total)
        ret (po - pexp) / (1.0f64 - pexp)
    }
    if which == 7u8 {
        ret (tr * total - cross) / math.sqrt[f64]((total * total - sr2) * (total * total - sc2))
    }
    // per-class pieces; micro sums numerators and denominators
    var num = 0.0f64
    var wsum = 0.0f64
    var micro_pn = 0.0f64
    var micro_pd = 0.0f64
    var micro_rn = 0.0f64
    var micro_rd = 0.0f64
    var micro_sn = 0.0f64
    var micro_sd = 0.0f64
    i = 0usize
    while i < k {
        var rs = 0.0f64
        var cs = 0.0f64
        var j = 0usize
        while j < k {
            rs += conf[i * k + j]
            cs += conf[j * k + i]
            j += 1usize
        }
        let tp = conf[i * k + i]
        let tn = total - (rs + cs - tp)
        let fp = rs - tp
        micro_pn += tp
        micro_pd += rs
        micro_rn += tp
        micro_rd += cs
        micro_sn += tn
        micro_sd += tn + fp
        if estimator != 1u8 {
            let prec = tp / rs
            let rec = tp / cs
            let sp = tn / (tn + fp)
            var v = 0.0f64
            if which == 0u8 { v = prec }
            if which == 1u8 { v = rec }
            if which == 2u8 { v = sp }
            if which == 3u8 {
                v = (1.0f64 + beta * beta) * prec * rec / ((beta * beta * prec) + rec)
                if prec == 0.0f64 && rec == 0.0f64 { v = 0.0f64 }
            }
            if which == 4u8 { v = (rec + sp) / 2.0f64 }
            if which == 5u8 { v = rec + sp - 1.0f64 }
            var w = 1.0f64 / f64(k)
            if estimator == 2u8 { w = cs / total }
            num += v * w
            wsum += w
        }
        i += 1usize
    }
    if estimator == 1u8 {
        let prec = micro_pn / micro_pd
        let rec = micro_rn / micro_rd
        let sp = micro_sn / micro_sd
        if which == 0u8 { ret prec }
        if which == 1u8 { ret rec }
        if which == 2u8 { ret sp }
        if which == 3u8 {
            if prec == 0.0f64 && rec == 0.0f64 { ret 0.0f64 }
            ret (1.0f64 + beta * beta) * prec * rec / ((beta * beta * prec) + rec)
        }
        if which == 4u8 { ret (rec + sp) / 2.0f64 }
        ret rec + sp - 1.0f64
    }
    ret num / wsum
}
