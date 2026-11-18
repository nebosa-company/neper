// R agricolae: the pairwise comparisons of group means after a one-way analysis of variance: LSD.test (no p adjustment), HSD.test
// (Tukey) and scheffe.test, each giving the difference of means, its p value and the confidence limits, for balanced or unbalanced groups.
//
// Not here: SNK.test and duncan.test (the package's standard error for unbalanced groups is not the pairwise one and was not recovered), waller.test,
// the non-parametric post-hoc tests, the experimental designs and AMMI.

use e.math
use e.math.nmath_beta as nb
use e.mem

type OneWay = struct { mse: f64, df: f64, k: usize }

// y with group labels 1..k: the group means and sizes go to mean and size (k each); the residual mean square and its degrees of freedom are returned
fn one_way(y: []const f64, grp: []const usize, k: usize, mean: []f64, size: []f64) -> OneWay {
    var i = 0usize
    while i < k {
        mean[i] = 0.0f64
        size[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < y.len {
        mean[grp[i] - 1usize] += y[i]
        size[grp[i] - 1usize] += 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        mean[i] = mean[i] / size[i]
        i += 1usize
    }
    var ss = 0.0f64
    i = 0usize
    while i < y.len {
        let r = y[i] - mean[grp[i] - 1usize]
        ss += r * r
        i += 1usize
    }
    let df = f64(y.len) - f64(k)
    ret OneWay { mse: ss / df, df: df, k: k }
}

// kind 0 LSD (unadjusted t), 1 HSD (Tukey), 2 Scheffe, 3 SNK, 4 Duncan; the pair (i, j) answers difference mean_i - mean_j, the p value and the 95 percent limits at level alpha
fn pairwise(w: OneWay, mean: []const f64, size: []const f64, i: usize, j: usize, kind: usize, alpha: f64) -> (f64, f64, f64, f64) {
    if kind >= 3usize {
        let (od, op, ol, oh) = ordered_pair(w, mean, size, i, j, kind, alpha)
        ret (od, op, ol, oh)
    }
    let d = mean[i] - mean[j]
    let inv = 1.0f64 / size[i] + 1.0f64 / size[j]
    let se = math.sqrt[f64](w.mse * inv)
    var ad = d
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    if kind == 0usize {
        let p = 2.0f64 * nb.pt(0.0f64 - ad / se, w.df, true, false)
        let h = nb.qt(1.0f64 - alpha / 2.0f64, w.df, true, false) * se
        ret (d, p, d - h, d + h)
    }
    if kind == 1usize {
        let s = math.sqrt[f64](w.mse / 2.0f64 * inv)
        let p = nb.ptukey(ad / s, 1.0f64, f64(w.k), w.df, false, false)
        let h = nb.qtukey(1.0f64 - alpha, 1.0f64, f64(w.k), w.df, true, false) * s
        ret (d, p, d - h, d + h)
    }
    let km1 = f64(w.k) - 1.0f64
    let p = nb.pf(d * d / (km1 * w.mse * inv), km1, w.df, false, false)
    let h = math.sqrt[f64](km1 * nb.qf(1.0f64 - alpha, km1, w.df, true, false)) * se
    ret (d, p, d - h, d + h)
}

// the SNK (kind 3) and Duncan (kind 4) comparisons of agricolae: the means are ranked in decreasing order (ties by position), a pair is compared over the number of
// ranks it spans, with the standard error sqrt(mse / n) (n the common size, or the harmonic mean of the sizes), the studentised-range critical value of that span,
// the p value rounded to four decimals as the package does, and limits dif -/+ critical value
fn ordered_pair(w: OneWay, mean: []const f64, size: []const f64, i: usize, j: usize, kind: usize, alpha: f64) -> (f64, f64, f64, f64) {
    let d = mean[i] - mean[j]
    var ad = d
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    var ri = 1usize
    var rj = 1usize
    var q = 0usize
    while q < w.k {
        if mean[q] > mean[i] || (mean[q] == mean[i] && q < i) { ri += 1usize }
        if mean[q] > mean[j] || (mean[q] == mean[j] && q < j) { rj += 1usize }
        q += 1usize
    }
    var span = 1usize
    if ri >= rj { span = ri - rj + 1usize } else { span = rj - ri + 1usize }
    var same = true
    q = 1usize
    while q < w.k {
        if size[q] != size[0usize] { same = false }
        q += 1usize
    }
    var nr = size[0usize]
    if !same {
        var s = 0.0f64
        q = 0usize
        while q < w.k {
            s += 1.0f64 / size[q]
            q += 1usize
        }
        nr = 1.0f64 / (s / f64(w.k))
    }
    let sd = math.sqrt[f64](w.mse / nr)
    var pw = 1.0f64
    var level = 1.0f64 - alpha
    if kind == 4usize {
        pw = 1.0f64 / (f64(span) - 1.0f64)
        level = math.pow[f64](1.0f64 - alpha, f64(span) - 1.0f64)
    }
    let pt = nb.ptukey(ad / sd, 1.0f64, f64(span), w.df, true, false)
    let p0 = 1.0f64 - math.pow[f64](pt, pw)
    let p = math.floor[f64](p0 * 10000.0f64 + 0.5f64) / 10000.0f64
    let crit = nb.qtukey(level, 1.0f64, f64(span), w.df, true, false) * sd
    ret (d, p, d - crit, d + crit)
}
