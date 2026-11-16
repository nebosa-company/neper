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
