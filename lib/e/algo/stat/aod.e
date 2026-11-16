// R aod: varbin (the binomial, ratio, arithmetic and jackknife estimates of a proportion over clusters, with their variances and normal limits) and iccbin
// method "C" (the one-way ANOVA intra-cluster correlation of binary data).
//
// Not here: the bootstrap row of varbin, iccbin methods A and B (mixed-model based), betabin, negbin, quasibin, quasipois, wald.test, anova, donner, splitbin, drs.

use e.algo.stat.desctools as dt
use e.math
use e.math.dist as dist

// varbin(n, y)$tab: part 0 the estimate, 1 its variance, 2 the lower and 3 the upper limit of row `row`
// (0 binomial, 1 ratio, 2 arithmetic, 3 jackknife) at level 1 - alpha
fn varbin(n: []const f64, y: []const f64, alpha: f64, row: usize, part: usize) -> f64 {
    let k = n.len
    let kf = f64(k)
    var ntot = 0.0f64
    var ytot = 0.0f64
    var i = 0usize
    while i < k {
        ntot += n[i]
        ytot += y[i]
        i += 1usize
    }
    let p = ytot / ntot
    var est = 0.0f64
    var v = 0.0f64
    if row == 0usize {
        est = p
        v = p * (1.0f64 - p) / (ntot - 1.0f64)
    } else if row == 1usize {
        var s = 0.0f64
        i = 0usize
        while i < k {
            let r = y[i] - n[i] * p
            s += r * r
            i += 1usize
        }
        est = p
        v = kf / (kf - 1.0f64) / (ntot * ntot) * s
    } else if row == 2usize {
        let (m, w) = prop_stats(n, y)
        est = m
        v = w
    } else {
        // the jackknife pseudovalues p + (k - 1) (y_i - n_i p) / (ntot - n_i)
        var m = 0.0f64
        i = 0usize
        while i < k {
            m += p + (kf - 1.0f64) * (y[i] - n[i] * p) / (ntot - n[i])
            i += 1usize
        }
        m = m / kf
        var ss = 0.0f64
        i = 0usize
        while i < k {
            let ps = p + (kf - 1.0f64) * (y[i] - n[i] * p) / (ntot - n[i])
            ss += (ps - m) * (ps - m)
            i += 1usize
        }
        est = m
        v = ss / (kf - 1.0f64) / kf
    }
    if part == 0usize { ret est }
    if part == 1usize { ret v }
    let z = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
    if part == 2usize { ret dt.max_f(0.0f64, est - z * math.sqrt[f64](v)) }
    ret dt.min_f(1.0f64, est + z * math.sqrt[f64](v))
}

// the mean of y_i / n_i and the variance of that mean
fn prop_stats(n: []const f64, y: []const f64) -> (f64, f64) {
    let k = n.len
    var m = 0.0f64
    var i = 0usize
    while i < k {
        m += y[i] / n[i]
        i += 1usize
    }
    m = m / f64(k)
    var ss = 0.0f64
    i = 0usize
    while i < k {
        let r = y[i] / n[i] - m
        ss += r * r
        i += 1usize
    }
    ret (m, ss / f64(k - 1usize) / f64(k))
}

// iccbin(n, y, method = "C")@rho: (MSA - MSE) / (MSA + (nA - 1) MSE) of the one-way ANOVA of the binary observations on the cluster
fn iccbin_c(n: []const f64, y: []const f64) -> f64 {
    let k = n.len
    var ntot = 0.0f64
    var ytot = 0.0f64
    var s2 = 0.0f64
    var sn2 = 0.0f64
    var i = 0usize
    while i < k {
        ntot += n[i]
        ytot += y[i]
        s2 += y[i] * y[i] / n[i]
        sn2 += n[i] * n[i]
        i += 1usize
    }
    let ssa = s2 - ytot * ytot / ntot
    let sse = ytot - s2
    let msa = ssa / (f64(k) - 1.0f64)
    let mse = sse / (ntot - f64(k))
    let na = (ntot - sn2 / ntot) / (f64(k) - 1.0f64)
    ret (msa - mse) / (msa + (na - 1.0f64) * mse)
}
