// R Epi: twoby2 for a 2 by 2 table: the risk of the outcome in each row with its logit-type interval, the risk ratio and the odds ratio with Wald
// intervals, the probability difference with Newcombe's score interval (ci.pd, method "Nc"), the asymptotic p value of the log odds ratio and the exact
// Fisher p value.
//
// Not here: the conditional maximum-likelihood odds ratio and its exact interval, ci.pd's "AC" method, ci.ratio, the Lexis machinery, clogistic,
// ROC and the rate and survival tools of the package.


use e.algo.stat.test as tst
use e.math
use e.math.nmath as nm

// (estimate, lower, upper) of the row risk x / n, as twoby2's bin.ci: the factor exp(z / sqrt(x (n - x) / n)) around the odds
fn bin_ci(x: f64, n: f64, z: f64) -> (f64, f64, f64) {
    let ef = math.exp[f64](z / math.sqrt[f64](x * (n - x) / n))
    let p = x / n
    ret (p, p / (p + (1.0f64 - p) * ef), p / (p + (1.0f64 - p) / ef))
}

// the roots of the Wilson quadratic for x / n: (lower, upper)
fn wilson(x: f64, n: f64, zz: f64) -> (f64, f64) {
    let aa = 1.0f64 + zz / n
    let bb = 0.0f64 - 2.0f64 * x / n - zz / n
    let cc = (x / n) * (x / n)
    let dd = bb * bb - 4.0f64 * aa * cc
    let s = math.sqrt[f64](dd)
    ret ((0.0f64 - bb - s) / (2.0f64 * aa), (0.0f64 - bb + s) / (2.0f64 * aa))
}

// ci.pd(method = "Nc") for x1 / n1 - x2 / n2: (difference, lower, upper)
fn newcombe(x1: f64, n1: f64, x2: f64, n2: f64, z: f64) -> (f64, f64, f64) {
    let zz = z * z
    let (l1, u1) = wilson(x1, n1, zz)
    let (l2, u2) = wilson(x2, n2, zz)
    let p1 = x1 / n1
    let p2 = x2 / n2
    let dlt = math.sqrt[f64]((p1 - l1) * (p1 - l1) + (u2 - p2) * (u2 - p2))
    let eps = math.sqrt[f64]((p1 - u1) * (p1 - u1) + (l2 - p2) * (l2 - p2))
    ret (p1 - p2, p1 - p2 - dlt, p1 - p2 + eps)
}

// the table is exposed row (a, b) and unexposed row (c, d), the outcome in the first column; alpha is 1 - confidence level
fn asymptotic_p(a: f64, b: f64, c: f64, d: f64) -> f64 {
    let or = (a / b) / (c / d)
    let l = math.log[f64](or)
    let x = l * l / (1.0f64 / a + 1.0f64 / b + 1.0f64 / c + 1.0f64 / d)
    ret 1.0f64 - nm.pchisq(x, 1.0f64, true, false)
}

fn fisher_p(a: f64, b: f64, c: f64, d: f64) -> f64 { ret tst.fisher_exact(u64(a), u64(b), u64(c), u64(d)).p_value }

// Epi::ROC(test, stat): row k of the table of cutpoints (row 0 is -Inf, row k the k-th smallest distinct test value) as (sensitivity, specificity, pvp, pvn, cutpoint), the package's
// cumulative counts at or below the cutpoint; stat is 0 or 1
fn roc_cut(test: []const f64, k: usize) -> f64 {
    if k == 0usize { ret 0.0f64 - 1.0f64 / 0.0f64 }
    var prev = 0.0f64 - 1.0f64 / 0.0f64
    var at = 0usize
    while at < k {
        var nextv = 1.0f64 / 0.0f64
        var i = 0usize
        while i < test.len {
            if test[i] > prev && test[i] < nextv { nextv = test[i] }
            i += 1usize
        }
        prev = nextv
        at += 1usize
    }
    ret prev
}

fn roc_count(test: []const f64, stat: []const f64, cut: f64) -> (f64, f64, f64, f64) {
    var neg = 0.0f64
    var pos = 0.0f64
    var cn = 0.0f64
    var cp = 0.0f64
    var i = 0usize
    while i < test.len {
        if stat[i] == 1.0f64 { pos += 1.0f64 } else { neg += 1.0f64 }
        if test[i] <= cut {
            if stat[i] == 1.0f64 { cp += 1.0f64 } else { cn += 1.0f64 }
        }
        i += 1usize
    }
    ret (neg, pos, cn, cp)
}

fn roc_distinct(test: []const f64) -> usize {
    var cnt = 0usize
    var i = 0usize
    while i < test.len {
        var seen = false
        var j = 0usize
        while j < i {
            if test[j] == test[i] { seen = true }
            j += 1usize
        }
        if !seen { cnt += 1usize }
        i += 1usize
    }
    ret cnt
}

// col 0 sens, 1 spec, 2 pvp, 3 pvn, 4 cutpoint
fn roc_value(test: []const f64, stat: []const f64, k: usize, col: usize) -> f64 {
    let cut = roc_cut(test, k)
    let (neg, pos, cn, cp) = roc_count(test, stat, cut)
    if col == 0usize { ret (pos - cp) / pos }
    if col == 1usize { ret cn / neg }
    if col == 2usize { ret cp / (cp + cn) }
    if col == 3usize { ret (neg - cn) / ((neg + pos) - (cp + cn)) }
    ret cut
}

// the area under the curve by the trapezoid rule over the table's rows
fn roc_auc(test: []const f64, stat: []const f64) -> f64 {
    let rows = roc_distinct(test) + 1usize
    var area = 0.0f64
    var k = 1usize
    while k < rows {
        let s0 = roc_value(test, stat, k - 1usize, 0usize)
        let s1 = roc_value(test, stat, k, 0usize)
        let p0 = 1.0f64 - roc_value(test, stat, k - 1usize, 1usize)
        let p1 = 1.0f64 - roc_value(test, stat, k, 1usize)
        area += (s1 + s0) / 2.0f64 * math.abs[f64](p1 - p0)
        k += 1usize
    }
    ret area
}

// the cutpoint maximising sensitivity + specificity (the first such row)
fn roc_max_cut(test: []const f64, stat: []const f64) -> f64 {
    let rows = roc_distinct(test) + 1usize
    var best = 0.0f64 - 1.0f64
    var bk = 0usize
    var k = 0usize
    while k < rows {
        let v = roc_value(test, stat, k, 0usize) + roc_value(test, stat, k, 1usize)
        if v > best {
            best = v
            bk = k
        }
        k += 1usize
    }
    ret roc_cut(test, bk)
}
