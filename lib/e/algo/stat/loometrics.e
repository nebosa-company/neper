// R loo's diagnostics tables and predictive metrics: pareto_k_table's counts and smallest n_eff, pareto_k_ids, mcse_loo and loo_predictive_metric (mae, rmse, mse, acc, balanced_acc) on top of e.algo.stat.looextra.
//
// Not here: the printed layouts, loo_predictive_metric's other methods.

use e.algo.stat.looextra as lx
use e.math
use e.mem

// the Pareto k threshold min(1 - 1 / log10(S), 0.7)
fn khat_threshold(s: usize) -> f64 {
    let t = 1.0f64 - 1.0f64 / math.log10[f64](f64(s))
    if t < 0.7f64 { ret t }
    ret 0.7f64
}

// pareto_k_table of loo_full's table (nobs rows of elpd, mcse, p_loo, k, n_eff) into out: counts of the three classes (k <= threshold, up to 1, above 1) and the smallest n_eff of the good class (NaN where empty)
fn pareto_k_table(tab: []const f64, nobs: usize, s: usize, out: []f64) {
    let thr = khat_threshold(s)
    out[0usize] = 0.0f64
    out[1usize] = 0.0f64
    out[2usize] = 0.0f64
    out[3usize] = 0.0f64 / 0.0f64
    var o = 0usize
    while o < nobs {
        let k = tab[o * 5usize + 3usize]
        if k <= thr {
            out[0usize] += 1.0f64
            let ne = tab[o * 5usize + 4usize]
            if out[3usize] != out[3usize] || ne < out[3usize] { out[3usize] = ne }
        } else if k <= 1.0f64 {
            out[1usize] += 1.0f64
        } else {
            out[2usize] += 1.0f64
        }
        o += 1usize
    }
}

// mcse_loo: sqrt of the summed squared pointwise Monte Carlo errors, NaN when any k is above the threshold
fn mcse_loo(tab: []const f64, nobs: usize, s: usize) -> f64 {
    let thr = khat_threshold(s)
    var ss = 0.0f64
    var o = 0usize
    while o < nobs {
        if tab[o * 5usize + 3usize] > thr { ret 0.0f64 / 0.0f64 }
        ss += tab[o * 5usize + 1usize] * tab[o * 5usize + 1usize]
        o += 1usize
    }
    ret math.sqrt[f64](ss)
}

// the estimate and standard error of metric (0 mae, 1 rmse, 2 mse, 3 acc, 4 balanced_acc) of predictions yhat against y
fn metric(y: []const f64, yhat: []const f64, kind: usize) -> (f64, f64) {
    let n = y.len
    let nf = f64(n)
    if kind <= 2usize {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            var e = (y[i] - yhat[i]) * (y[i] - yhat[i])
            if kind == 0usize { e = math.abs[f64](y[i] - yhat[i]) }
            m += e
            i += 1usize
        }
        m = m / nf
        var v = 0.0f64
        i = 0usize
        while i < n {
            var e = (y[i] - yhat[i]) * (y[i] - yhat[i])
            if kind == 0usize { e = math.abs[f64](y[i] - yhat[i]) }
            v += (e - m) * (e - m)
            i += 1usize
        }
        let se = math.sqrt[f64](v / (nf - 1.0f64)) / math.sqrt[f64](nf)
        if kind == 1usize { ret (math.sqrt[f64](m), math.sqrt[f64](se * se / m / 4.0f64)) }
        ret (m, se)
    }
    if kind == 3usize {
        var hit = 0.0f64
        var i = 0usize
        while i < n {
            var yh = 0.0f64
            if yhat[i] > 0.5f64 { yh = 1.0f64 }
            if yh == y[i] { hit += 1.0f64 }
            i += 1usize
        }
        let est = hit / nf
        ret (est, math.sqrt[f64](est * (1.0f64 - est) / nf))
    }
    var tn = 0.0f64
    var nz = 0.0f64
    var tp = 0.0f64
    var np = 0.0f64
    var i = 0usize
    while i < n {
        var yh = 0.0f64
        if yhat[i] > 0.5f64 { yh = 1.0f64 }
        if y[i] == 0.0f64 {
            nz += 1.0f64
            if yh == 0.0f64 { tn += 1.0f64 }
        } else {
            np += 1.0f64
            if yh == y[i] { tp += 1.0f64 }
        }
        i += 1usize
    }
    let ptn = tn / nz
    let ptp = tp / np
    let v = (ptp * (1.0f64 - ptp) + ptn * (1.0f64 - ptn)) / 4.0f64
    ret ((ptp + ptn) / 2.0f64, math.sqrt[f64](v / nf))
}

// loo_predictive_metric(x, y, log_lik, metric): x and ll are nobs blocks of s draws; the prediction of each observation is E_loo's mean under the psis weights of -ll (r_eff = 1)
fn predictive_metric(a: *mem.Arena, x: []const f64, ll: []const f64, y: []const f64, s: usize, kind: usize) -> (f64, f64, err) {
    let nobs = y.len
    let (lr, e1) = mem.alloc[f64](a, s)
    let (pred, e2) = mem.alloc[f64](a, nobs)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    var o = 0usize
    while o < nobs {
        var i = 0usize
        while i < s {
            lr[i] = 0.0f64 - ll[o * s + i]
            i += 1usize
        }
        let (v, k, e) = lx.e_loo(a, x[o * s..(o + 1usize) * s], lr, 1.0f64, 0usize, 0.0f64)
        if e != ok { ret (0.0f64, 0.0f64, e) }
        pred[o] = v
        o += 1usize
    }
    let (est, se) = metric(y, pred, kind)
    ret (est, se, ok)
}
