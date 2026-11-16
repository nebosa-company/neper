// R metafor small-study tests on a fixed-effect model: regtest (Egger's regression of the effects on their standard errors, weights 1 / v, the slope's z test and the intercept with its
// 95 per cent limits), ranktest (Begg and Mazumdar's Kendall tau between the standardised effects and the variances, with the exact p-value) and fsn (Rosenthal's fail-safe N).
//
// Not here: random-effects models with moderators, the other predictors and models of regtest, the other fsn methods, trimfill and the funnel plots.

use e.math
use e.algo.stat.metaforpkg as mf
use e.math.dist as dist
use e.mem

// regtest(rma(yi, vi, method = "FE")): what 0 the slope's z value, 1 its p-value, 2 the intercept estimate, 3 and 4 its 95 per cent limits, 5 the slope estimate
fn regtest(y: []const f64, v: []const f64, what: usize) -> f64 {
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var t0 = 0.0f64
    var t1 = 0.0f64
    var i = 0usize
    while i < y.len {
        let w = 1.0f64 / v[i]
        let x = math.sqrt[f64](v[i])
        s0 += w
        s1 += w * x
        s2 += w * x * x
        t0 += w * y[i]
        t1 += w * x * y[i]
        i += 1usize
    }
    let det = s0 * s2 - s1 * s1
    let b0 = (s2 * t0 - s1 * t1) / det
    let b1 = (s0 * t1 - s1 * t0) / det
    let se0 = math.sqrt[f64](s2 / det)
    let se1 = math.sqrt[f64](s0 / det)
    let z = b1 / se1
    if what == 0usize { ret z }
    if what == 1usize { ret 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false) }
    if what == 2usize { ret b0 }
    let zc = dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false)
    if what == 3usize { ret b0 - zc * se0 }
    if what == 4usize { ret b0 + zc * se0 }
    ret b1
}

// P(T <= q) for the number of discordant pairs T of a random permutation of n items, by the recurrence on the number of inversions; counts holds n (n - 1) / 2 + 1 values
fn pkendall(q: usize, n: usize, counts: []f64, next: []f64) -> f64 {
    let maxinv = n * (n - 1usize) / 2usize
    var k = 0usize
    while k <= maxinv {
        counts[k] = 0.0f64
        k += 1usize
    }
    counts[0usize] = 1.0f64
    var m = 2usize
    while m <= n {
        k = 0usize
        while k <= maxinv {
            var s = 0.0f64
            var j = 0usize
            while j < m && j <= k {
                s += counts[k - j]
                j += 1usize
            }
            next[k] = s
            k += 1usize
        }
        k = 0usize
        while k <= maxinv {
            counts[k] = next[k]
            k += 1usize
        }
        m += 1usize
    }
    var total = 0.0f64
    var below = 0.0f64
    k = 0usize
    while k <= maxinv {
        total += counts[k]
        if k <= q { below += counts[k] }
        k += 1usize
    }
    ret below / total
}

// ranktest: part 0 Kendall's tau between the standardised effects (y - ybar) / sqrt(v - 1 / sum w) and v, 1 the two-sided exact p-value (no ties)
fn ranktest(y: []const f64, v: []const f64, part: usize, counts: []f64, next: []f64) -> f64 {
    let n = y.len
    var sw = 0.0f64
    var swy = 0.0f64
    var i = 0usize
    while i < n {
        sw += 1.0f64 / v[i]
        swy += y[i] / v[i]
        i += 1usize
    }
    let yb = swy / sw
    var conc = 0.0f64
    var disc = 0.0f64
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let a = (y[i] - yb) / math.sqrt[f64](v[i] - 1.0f64 / sw) - (y[j] - yb) / math.sqrt[f64](v[j] - 1.0f64 / sw)
            let b = v[i] - v[j]
            if a * b > 0.0f64 { conc += 1.0f64 } else if a * b < 0.0f64 { disc += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    let pairs = f64(n * (n - 1usize) / 2usize)
    let tau = (conc - disc) / pairs
    if part == 0usize { ret tau }
    let q = usize(math.floor[f64]((tau + 1.0f64) * f64(n) * f64(n - 1usize) / 4.0f64 + 0.5f64))
    var p = 0.0f64
    if f64(q) > f64(n) * f64(n - 1usize) / 4.0f64 { p = 1.0f64 - pkendall(q - 1usize, n, counts, next) } else { p = pkendall(q, n, counts, next) }
    var r = 2.0f64 * p
    if r > 1.0f64 { r = 1.0f64 }
    ret r
}

// fsn(yi, vi) with type "Rosenthal" and alpha 0.05: ceiling((sum z / qnorm(0.95))^2 - k) with z = y / sqrt v
fn fsn_rosenthal(y: []const f64, v: []const f64) -> f64 {
    var sz = 0.0f64
    var i = 0usize
    while i < y.len {
        sz += y[i] / math.sqrt[f64](v[i])
        i += 1usize
    }
    let q = dist.qnorm(0.95f64, 0.0f64, 1.0f64, true, false)
    let n = (sz / q) * (sz / q) - f64(y.len)
    ret math.ceil[f64](n)
}

// leave1out(rma(yi, vi, method)): the estimate (what 0), its standard error (1), z (7 in rma's numbering, here 2), the p-value (3), tau2 (4) and Q (5) with study `drop` left out
fn leave1out(a: *mem.Arena, y: []const f64, v: []const f64, method: usize, drop: usize, what: usize) -> f64 {
    let k = y.len - 1usize
    let (ys, e1) = mem.alloc[f64](a, k)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (vs, e2) = mem.alloc[f64](a, k)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    var i = 0usize
    while i < y.len {
        if i != drop {
            ys[j] = y[i]
            vs[j] = v[i]
            j += 1usize
        }
        i += 1usize
    }
    if what == 0usize { ret mf.rma(ys, vs, method, 0usize) }
    if what == 1usize { ret mf.rma(ys, vs, method, 1usize) }
    if what == 2usize { ret mf.rma(ys, vs, method, 7usize) }
    if what == 3usize { ret mf.rma(ys, vs, method, 8usize) }
    if what == 4usize { ret mf.rma(ys, vs, method, 2usize) }
    ret mf.rma(ys, vs, method, 5usize)
}
