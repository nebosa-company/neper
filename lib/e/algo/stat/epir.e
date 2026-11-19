// R epiR: the measures of association of a 2 by 2 cohort table (epi.2by2, method "cohort.count"): risk ratio and odds ratio with Wald (Taylor)
// intervals, the risk difference with its Wald interval, the number needed to treat, the population attributable risk, the Wald tests of
// the ratios and the Pearson chi-squared statistics with and without Yates' correction.
//
// Not here: the score, Koopman, conditional and mid-p intervals, attributable fractions, the stratified (Mantel-Haenszel) tables and the
// other study designs of epi.2by2.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb

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

// Clopper-Pearson interval of x successes in n trials: (est, lower, upper)
fn exact_prop(x: f64, n: f64, level: f64) -> (f64, f64, f64) {
    let al = 1.0f64 - level
    var lo = 0.0f64
    var hi = 1.0f64
    if x > 0.0f64 { lo = nb.qbeta(al / 2.0f64, x, n - x + 1.0f64, true, false) }
    if x < n { hi = nb.qbeta(1.0f64 - al / 2.0f64, x + 1.0f64, n - x, true, false) }
    ret (x / n, lo, hi)
}

// population attributable fraction as epiR reports it for the 2 by 2 table: (risk in the population - risk in the unexposed) / risk in the
// population, the bounds taken over the exact intervals of the two risks (min and max of the two limit ratios): (est, lower, upper)
fn paf_risk(t: Table2, level: f64) -> (f64, f64, f64) {
    let n = t.a + t.b + t.c + t.d
    let (po, ol, ou) = exact_prop(t.c, t.c + t.d, level)
    let (pp, pl, pu) = exact_prop(t.a + t.c, n, level)
    let r1 = (pl - ol) / pl
    let r2 = (pu - ou) / pu
    ret ((pp - po) / pp, math.min[f64](r1, r2), math.max[f64](r1, r2))
}

// population attributable risk with its Wald interval (kind 0) or Pirikahu's delta-method interval (kind 1): (est, lower, upper)
fn par_risk_ci(t: Table2, level: f64, units: f64, kind: usize) -> (f64, f64, f64) {
    let n = t.a + t.b + t.c + t.d
    let m1 = t.a + t.c
    let n0 = t.c + t.d
    let est = (m1 / n - t.c / n0) * units
    var se = 0.0f64
    if kind == 0usize {
        se = math.sqrt[f64](m1 * (n - m1) / (n * n * n) + t.c * (n0 - t.c) / (n0 * n0 * n0)) * units
    } else {
        let d1 = 1.0f64 / n - m1 / (n * n)
        let d2 = 0.0f64 - m1 / (n * n)
        let d3 = t.c / (n0 * n0) - m1 / (n * n) + 1.0f64 / n - 1.0f64 / n0
        let d4 = t.c / (n0 * n0) - m1 / (n * n)
        se = math.sqrt[f64](d1 * d1 * t.a + d2 * d2 * t.b + d3 * d3 * t.c + d4 * d4 * t.d) * units
    }
    let z = z_of(level)
    ret (est, est - z * se, est + z * se)
}

// epiR zRRscore, the interior case (0 < a < a + b and 0 < c < c + d): the score (Miettinen-Nurminen) risk-ratio interval from the roots of the
// score cubic; (est, lower, upper)
fn rr_score(t: Table2, level: f64) -> (f64, f64, f64) {
    let z = z_of(level)
    let a = t.a
    let b = t.b
    let c = t.c
    let n1 = t.a + t.b
    let n0 = t.c + t.d
    let est = (a / n1) / (c / n0)
    let z2 = z * z
    let a1 = n0 * (n0 * (n0 + n1) * a + n1 * (n0 + a) * z2)
    let a2 = 0.0f64 - n0 * (n0 * n1 * (c + a) + 2.0f64 * (n0 + n1) * c * a + n1 * (n0 + c + 2.0f64 * a) * z2)
    let a3 = 2.0f64 * n0 * n1 * c * (c + a) + (n0 + n1) * c * c * a + n0 * n1 * (c + a) * z2
    let a4 = 0.0f64 - n1 * c * c * (c + a)
    let b1 = a2 / a1
    let b2 = a3 / a1
    let b3 = a4 / a1
    let c1 = b2 - b1 * b1 / 3.0f64
    let c2 = b3 - b1 * b2 / 3.0f64 + 2.0f64 * b1 * b1 * b1 / 27.0f64
    var ax = math.sqrt[f64](27.0f64) * c2 / (2.0f64 * c1 * math.sqrt[f64](0.0f64 - c1))
    if ax <= -1.0f64 || ax >= 1.0f64 { ax = 0.0f64 }
    let ceta = math.acos[f64](ax)
    let pi = 3.141592653589793f64
    let s = 2.0f64 * math.sqrt[f64](0.0f64 - c1 / 3.0f64)
    let p01 = 0.0f64 - s * math.cos[f64](pi / 3.0f64 - ceta / 3.0f64) - b1 / 3.0f64
    let p02 = 0.0f64 - s * math.cos[f64](pi / 3.0f64 + ceta / 3.0f64) - b1 / 3.0f64
    let p03 = s * math.cos[f64](ceta / 3.0f64) - b1 / 3.0f64
    let p0sum = p01 + p02 + p03
    let p0up = math.min[f64](p01, math.min[f64](p02, p03))
    let p0low = p0sum - p0up - math.max[f64](p01, math.max[f64](p02, p03))
    let lo = (1.0f64 - (n1 - a) * (1.0f64 - p0low) / (c + n1 - (n0 + n1) * p0low)) / p0low
    let hi = (1.0f64 - (n1 - a) * (1.0f64 - p0up) / (c + n1 - (n0 + n1) * p0up)) / p0up
    ret (est, lo, hi)
}

// attributable fraction in the exposed from the score interval of the risk ratio: (RR - 1) / RR, the bounds the min and max of the two limit maps
fn af_risk(t: Table2, level: f64) -> (f64, f64, f64) {
    let (rr, lo, hi) = rr_score(t, level)
    let f1 = (lo - 1.0f64) / lo
    let f2 = (hi - 1.0f64) / hi
    ret ((rr - 1.0f64) / rr, math.min[f64](f1, f2), math.max[f64](f1, f2))
}

// epi.tests with the exact method for a table with test positive and disease positive a, test positive and disease negative b, test negative
// and disease positive c, test negative and disease negative d; stat 0 apparent prevalence, 1 true prevalence, 2 sensitivity, 3 specificity,
// 4 diagnostic accuracy, 5 diagnostic odds ratio, 6 number needed to diagnose, 7 Youden's index, 8 positive predictive value, 9 negative
// predictive value, 10 positive likelihood ratio, 11 negative likelihood ratio: (est, lower, upper)
fn epi_tests(t: Table2, level: f64, stat: usize) -> (f64, f64, f64) {
    let a = t.a
    let b = t.b
    let c = t.c
    let d = t.d
    let n = a + b + c + d
    let m1 = a + c
    let m0 = b + d
    let z = z_of(level)
    if stat == 0usize {
        let (pe0, pl0, pu0) = exact_prop(a + b, n, level)
        ret (pe0, pl0, pu0)
    }
    if stat == 1usize {
        let (pe1, pl1, pu1) = exact_prop(a + c, n, level)
        ret (pe1, pl1, pu1)
    }
    if stat == 2usize {
        let (pe2, pl2, pu2) = exact_prop(a, m1, level)
        ret (pe2, pl2, pu2)
    }
    if stat == 3usize {
        let (pe3, pl3, pu3) = exact_prop(d, m0, level)
        ret (pe3, pl3, pu3)
    }
    if stat == 4usize {
        let (pe4, pl4, pu4) = exact_prop(a + d, n, level)
        ret (pe4, pl4, pu4)
    }
    if stat == 8usize {
        let (pe8, pl8, pu8) = exact_prop(a, a + b, level)
        ret (pe8, pl8, pu8)
    }
    if stat == 9usize {
        let (pe9, pl9, pu9) = exact_prop(d, c + d, level)
        ret (pe9, pl9, pu9)
    }
    let (se, sel, seu) = exact_prop(a, m1, level)
    let (sp, spl, spu) = exact_prop(d, m0, level)
    if stat == 5usize {
        let o = a * d / (b * c)
        let s = z * math.sqrt[f64](1.0f64 / a + 1.0f64 / b + 1.0f64 / c + 1.0f64 / d)
        ret (o, math.exp[f64](math.log[f64](o) - s), math.exp[f64](math.log[f64](o) + s))
    }
    if stat == 6usize || stat == 7usize {
        let j = se - (1.0f64 - sp)
        let j1 = sel - (1.0f64 - spl)
        let j2 = seu - (1.0f64 - spu)
        if stat == 7usize { ret (j, math.min[f64](j1, j2), math.max[f64](j1, j2)) }
        let k1 = 1.0f64 / j1
        let k2 = 1.0f64 / j2
        ret (1.0f64 / j, math.min[f64](k1, k2), math.max[f64](k1, k2))
    }
    if stat == 10usize {
        let l = (a / m1) / (1.0f64 - d / m0)
        let s = z * math.sqrt[f64]((1.0f64 - se) / (m1 * se) + sp / (m0 * (1.0f64 - sp)))
        ret (l, math.exp[f64](math.log[f64](l) - s), math.exp[f64](math.log[f64](l) + s))
    }
    let l = (1.0f64 - a / m1) / (d / m0)
    let s = z * math.sqrt[f64](se / (m1 * (1.0f64 - se)) + (1.0f64 - sp) / (m0 * sp))
    ret (l, math.exp[f64](math.log[f64](l) - s), math.exp[f64](math.log[f64](l) + s))
}

// epi.conf for a proportion x / n: method 0 exact (Clopper-Pearson), 1 Wilson, 2 Agresti-Coull (the estimate is the adjusted proportion), 3 Jeffreys: (est, lower, upper)
fn prop_ci(x: f64, n: f64, level: f64, method: usize) -> (f64, f64, f64) {
    if method == 0usize {
        let (e0, l0, u0) = exact_prop(x, n, level)
        ret (e0, l0, u0)
    }
    let z = z_of(level)
    let p = x / n
    if method == 1usize {
        let lim = z * math.sqrt[f64]((p * (1.0f64 - p) + z * z / (4.0f64 * n)) / n) / (1.0f64 + z * z / n)
        let pest = (p + z * z / (2.0f64 * n)) / (1.0f64 + z * z / n)
        ret (p, pest - lim, pest + lim)
    }
    if method == 2usize {
        let pa = (x + z * z / 2.0f64) / (n + z * z)
        let h = z * math.sqrt[f64](pa * (1.0f64 - pa) / (n + z * z))
        ret (pa, pa - h, pa + h)
    }
    let al = 1.0f64 - level
    ret (p, nb.qbeta(al / 2.0f64, x + 0.5f64, n - x + 0.5f64, true, false), nb.qbeta(1.0f64 - al / 2.0f64, x + 0.5f64, n - x + 0.5f64, true, false))
}
