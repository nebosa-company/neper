// R epiR: the measures of association of a 2 by 2 cohort table (epi.2by2, method "cohort.count"): risk ratio and odds ratio with Wald (Taylor)
// intervals, the risk difference with its Wald interval, the number needed to treat, the population attributable risk, the Wald tests of
// the ratios and the Pearson chi-squared statistics with and without Yates' correction.
//
// Not here: the score, Koopman, conditional and mid-p intervals, attributable fractions, the stratified (Mantel-Haenszel) tables and the
// other study designs of epi.2by2.

use e.math
use e.math.dist as dist
use e.math.nmath as nm

// the table is exposed with outcome (a), exposed without (b), unexposed with (c), unexposed without (d); units scales the risk difference
type Table2 = struct { a: f64, b: f64, c: f64, d: f64 }

fn z_of(level: f64) -> f64 { ret dist.qnorm(1.0f64 - (1.0f64 - level) / 2.0f64, 0.0f64, 1.0f64, true, false) }

// (estimate, lower, upper)
fn risk_ratio(t: Table2, level: f64) -> (f64, f64, f64) {
    let n1 = t.a + t.b
    let n0 = t.c + t.d
    let rr = (t.a / n1) / (t.c / n0)
    let se = math.sqrt[f64](t.b / (t.a * n1) + t.d / (t.c * n0))
    let z = z_of(level)
    ret (rr, math.exp[f64](math.log[f64](rr) - z * se), math.exp[f64](math.log[f64](rr) + z * se))
}

fn odds_ratio(t: Table2, level: f64) -> (f64, f64, f64) {
    let or = (t.a * t.d) / (t.b * t.c)
    let se = math.sqrt[f64](1.0f64 / t.a + 1.0f64 / t.b + 1.0f64 / t.c + 1.0f64 / t.d)
    let z = z_of(level)
    ret (or, math.exp[f64](math.log[f64](or) - z * se), math.exp[f64](math.log[f64](or) + z * se))
}

// the risk difference per `units` exposed, with its Wald interval
fn risk_difference(t: Table2, level: f64, units: f64) -> (f64, f64, f64) {
    let n1 = t.a + t.b
    let n0 = t.c + t.d
    let rd = t.a / n1 - t.c / n0
    let se = math.sqrt[f64](t.a * t.b / (n1 * n1 * n1) + t.c * t.d / (n0 * n0 * n0))
    let z = z_of(level)
    ret (rd * units, (rd - z * se) * units, (rd + z * se) * units)
}

// the number needed to treat per `units`: units over the risk difference, the limits from the difference's limits
fn nnt(t: Table2, level: f64, units: f64) -> (f64, f64, f64) {
    let (rd, lo, hi) = risk_difference(t, level, units)
    var l = units / hi
    var u = units / lo
    if l > u {
        l = units / lo
        u = units / hi
    }
    ret (units / rd, l, u)
}

fn par_risk(t: Table2, units: f64) -> f64 {
    let n = t.a + t.b + t.c + t.d
    ret ((t.a + t.c) / n - t.c / (t.c + t.d)) * units
}

// the Wald z statistic of the log ratio and its two-sided p value; kind 0 risk ratio, 1 odds ratio
fn wald_test(t: Table2, kind: usize) -> (f64, f64) {
    let n1 = t.a + t.b
    let n0 = t.c + t.d
    var lg = 0.0f64
    var se = 0.0f64
    if kind == 0usize {
        lg = math.log[f64]((t.a / n1) / (t.c / n0))
        se = math.sqrt[f64](t.b / (t.a * n1) + t.d / (t.c * n0))
    } else {
        lg = math.log[f64]((t.a * t.d) / (t.b * t.c))
        se = math.sqrt[f64](1.0f64 / t.a + 1.0f64 / t.b + 1.0f64 / t.c + 1.0f64 / t.d)
    }
    let z = lg / se
    ret (z, 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false))
}

// the Pearson chi-squared statistic and its p value; yates applies the continuity correction
fn chi2(t: Table2, yates: bool) -> (f64, f64) {
    let n = t.a + t.b + t.c + t.d
    let r1 = t.a + t.b
    let r2 = t.c + t.d
    let c1 = t.a + t.c
    let c2 = t.b + t.d
    var num = math.abs[f64](t.a * t.d - t.b * t.c)
    if yates { num = num - n / 2.0f64 }
    if yates && num < 0.0f64 { num = 0.0f64 }
    let x = n * num * num / (r1 * r2 * c1 * c2)
    ret (x, nm.pchisq(x, 1.0f64, false, false))
}
