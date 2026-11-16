// R Hmisc, the closed-form part: `binconf` (exact, Wilson and asymptotic binomial confidence limits),
// `wtd_mean`, `wtd_var` (unbiased), `somers2` (the concordance index C and Somers' Dxy of a 0/1 response,
// unweighted, ties by mid-ranks) and `rank_avg`.
//
// Not here: rcorr, hdquantile, the weighted quantiles, ranks and tables, cut2, rcspline, describe, varclus,
// redun and the bootstrap summaries.

use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb

fn qn(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

// binconf(x, n, alpha): which 0 exact, 1 wilson, 2 asymptotic; answers (lower, upper)
fn binconf(x: f64, n: f64, alpha: f64, which: u8) -> (f64, f64) {
    let nu1 = 2.0f64 * (n - x + 1.0f64)
    let nu2 = 2.0f64 * x
    var ll = 0.0f64
    if x > 0.0f64 { ll = x / (x + nb.qf(1.0f64 - alpha / 2.0f64, nu1, nu2, true, false) * (n - x + 1.0f64)) }
    let nu1p = nu2 + 2.0f64
    let nu2p = nu1 - 2.0f64
    var pp = 1.0f64
    if x < n { pp = nb.qf(1.0f64 - alpha / 2.0f64, nu1p, nu2p, true, false) }
    let ul = ((x + 1.0f64) * pp) / (n - x + (x + 1.0f64) * pp)
    let zcrit = 0.0f64 - qn(alpha / 2.0f64)
    let z2 = zcrit * zcrit
    let p = x / n
    var cl0 = (p + z2 / 2.0f64 / n - zcrit * math.sqrt[f64]((p * (1.0f64 - p) + z2 / 4.0f64 / n) / n)) / (1.0f64 + z2 / n)
    var cl1 = (p + z2 / 2.0f64 / n + zcrit * math.sqrt[f64]((p * (1.0f64 - p) + z2 / 4.0f64 / n) / n)) / (1.0f64 + z2 / n)
    if x == 1.0f64 { cl0 = 0.0f64 - math.log[f64](1.0f64 - alpha) / n }
    if x == n - 1.0f64 { cl1 = 1.0f64 + math.log[f64](1.0f64 - alpha) / n }
    let za = qn(1.0f64 - alpha / 2.0f64)
    let al = x / n - za * math.sqrt[f64](((x / n) * (1.0f64 - x / n)) / n)
    let au = x / n + za * math.sqrt[f64](((x / n) * (1.0f64 - x / n)) / n)
    if which == 0u8 { ret (ll, ul) }
    if which == 1u8 { ret (cl0, cl1) }
    ret (al, au)
}

fn wtd_mean(x: []const f64, w: []const f64) -> f64 {
    var s = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < x.len {
        s += w[i] * x[i]
        sw += w[i]
        i += 1usize
    }
    ret s / sw
}

fn wtd_var(x: []const f64, w: []const f64) -> f64 {
    var sw = 0.0f64
    var i = 0usize
    while i < x.len {
        sw += w[i]
        i += 1usize
    }
    let xbar = wtd_mean(x, w)
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += w[i] * (x[i] - xbar) * (x[i] - xbar)
        i += 1usize
    }
    ret s / (sw - 1.0f64)
}

// the average rank of x[i] (ties share the mean of their ranks), 1-based
fn rank_avg(x: []const f64, i: usize) -> f64 {
    var less = 0.0f64
    var eq = 0.0f64
    var j = 0usize
    while j < x.len {
        if x[j] < x[i] { less += 1.0f64 } else if x[j] == x[i] { eq += 1.0f64 }
        j += 1usize
    }
    ret less + (eq + 1.0f64) / 2.0f64
}

// somers2(x, y) for a 0/1 y: (C, Dxy)
fn somers2(x: []const f64, y: []const f64) -> (f64, f64) {
    let n = f64(x.len)
    var n1 = 0.0f64
    var sr = 0.0f64
    var i = 0usize
    while i < x.len {
        if y[i] == 1.0f64 {
            n1 += 1.0f64
            sr += rank_avg(x, i)
        }
        i += 1usize
    }
    let c = (sr / n1 - (n1 + 1.0f64) / 2.0f64) / (n - n1)
    ret (c, 2.0f64 * (c - 0.5f64))
}
