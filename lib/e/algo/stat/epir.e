// R epiR: the measures of association of a 2 by 2 cohort table (epi.2by2, method "cohort.count"): risk ratio and odds ratio with Wald (Taylor)
// intervals, the risk difference with its Wald interval, the number needed to treat, the population attributable risk, the Wald tests of
// the ratios and the Pearson chi-squared statistics with and without Yates' correction.
//
// Not here: the score, Koopman, conditional and mid-p intervals, attributable fractions, the stratified (Mantel-Haenszel) tables and the
// other study designs of epi.2by2.

use e.math
use e.mem
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.algo.stat.pwr as pw

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

// epi.tests (method 0 exact, 1 Wilson, 2 Agresti-Coull, 3 Jeffreys for the proportions) for a table with test positive and disease positive a, test positive and disease negative b, test negative
// and disease positive c, test negative and disease negative d; stat 0 apparent prevalence, 1 true prevalence, 2 sensitivity, 3 specificity,
// 4 diagnostic accuracy, 5 diagnostic odds ratio, 6 number needed to diagnose, 7 Youden's index, 8 positive predictive value, 9 negative
// predictive value, 10 positive likelihood ratio, 11 negative likelihood ratio: (est, lower, upper)
fn epi_tests(t: Table2, level: f64, stat: usize, method: usize) -> (f64, f64, f64) {
    let a = t.a
    let b = t.b
    let c = t.c
    let d = t.d
    let n = a + b + c + d
    let m1 = a + c
    let m0 = b + d
    let z = z_of(level)
    if stat == 0usize {
        let (pe0, pl0, pu0) = prop_ci(a + b, n, level, method)
        ret (pe0, pl0, pu0)
    }
    if stat == 1usize {
        let (pe1, pl1, pu1) = prop_ci(a + c, n, level, method)
        ret (pe1, pl1, pu1)
    }
    if stat == 2usize {
        let (pe2, pl2, pu2) = prop_ci(a, m1, level, method)
        ret (pe2, pl2, pu2)
    }
    if stat == 3usize {
        let (pe3, pl3, pu3) = prop_ci(d, m0, level, method)
        ret (pe3, pl3, pu3)
    }
    if stat == 4usize {
        let (pe4, pl4, pu4) = prop_ci(a + d, n, level, method)
        ret (pe4, pl4, pu4)
    }
    if stat == 8usize {
        let (pe8, pl8, pu8) = prop_ci(a, a + b, level, method)
        ret (pe8, pl8, pu8)
    }
    if stat == 9usize {
        let (pe9, pl9, pu9) = prop_ci(d, c + d, level, method)
        ret (pe9, pl9, pu9)
    }
    let (se, sel, seu) = prop_ci(a, m1, level, method)
    let (sp, spl, spu) = prop_ci(d, m0, level, method)
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

// epiR zlimit: walk theta by factors of 1.001 (down for the lower limit, up for the upper) until the score statistic passes the chi-squared quantile
fn or_zlimit(x1: f64, n1: f64, x2: f64, n2: f64, level: f64, start: f64, upper: bool) -> f64 {
    let zq = nm.qchisq(level, 1.0f64, true, false)
    let px = x1 / n1
    var lim = start
    var ci = start
    var it = 0usize
    while it < 100000usize {
        var p2d = 0.0f64
        var p1d = 0.0f64
        if math.abs[f64](lim - 1.0f64) < 1.0e-10f64 {
            p2d = (x1 + x2) / (n1 + n2)
            p1d = p2d
        } else {
            let a1 = n2 * (lim - 1.0f64)
            let b1 = n1 * lim + n2 - (x1 + x2) * (lim - 1.0f64)
            let c1 = 0.0f64 - (x1 + x2)
            p2d = (0.0f64 - b1 + math.sqrt[f64](b1 * b1 - 4.0f64 * a1 * c1)) / (2.0f64 * a1)
            p1d = p2d * lim / (1.0f64 + p2d * (lim - 1.0f64))
        }
        let d1 = n1 * (px - p1d)
        let score = d1 * d1 * (1.0f64 / (n1 * p1d * (1.0f64 - p1d)) + 1.0f64 / (n2 * p2d * (1.0f64 - p2d)))
        ci = lim
        if upper { lim = ci * 1.001f64 } else { lim = ci / 1.001f64 }
        if score > zq { break }
        it += 1usize
    }
    ret ci
}

// epiR zORscore for an interior table (0 < a < a + b, 0 < c < c + d): the score interval of the odds ratio; (est, lower, upper)
fn or_score(t: Table2, level: f64) -> (f64, f64, f64) {
    let x1 = t.a
    let n1 = t.a + t.b
    let x2 = t.c
    let n2 = t.c + t.d
    let px = x1 / n1
    let py = x2 / n2
    let base = px / (1.0f64 - px) / (py / (1.0f64 - py))
    let lo = or_zlimit(x1, n1, x2, n2, level, base / 1.1f64, false)
    let hi = or_zlimit(x1, n1, x2, n2, level, base * 1.1f64, true)
    ret ((t.a / t.b) / (t.c / t.d), lo, hi)
}

// attributable fraction of the case-control table from the score odds-ratio interval (epi.2by2 reports the crude path): (est, lower, upper)
fn af_est(t: Table2, level: f64) -> (f64, f64, f64) {
    let (o, lo, hi) = or_score(t, level)
    let f1 = (lo - 1.0f64) / lo
    let f2 = (hi - 1.0f64) / hi
    ret ((o - 1.0f64) / o, math.min[f64](f1, f2), math.max[f64](f1, f2))
}

// epi.ccc, Lin's concordance correlation of x and y with the interval answers; out = (rho_c, asymptotic lower, asymptotic upper, z-transform lower,
// z-transform upper, scale shift v, location shift u, bias correction C_b, mean difference x - y, sd of the differences)
fn epi_ccc(x: []const f64, y: []const f64, level: f64, out: []f64) {
    let k = f64(x.len)
    let zv = z_of(level)
    var xb = 0.0f64
    var yb = 0.0f64
    var i = 0usize
    while i < x.len {
        xb += x[i]
        yb += y[i]
        i += 1usize
    }
    xb = xb / k
    yb = yb / k
    var sxx = 0.0f64
    var syy = 0.0f64
    var sxy0 = 0.0f64
    var sdd = 0.0f64
    var dm = 0.0f64
    i = 0usize
    while i < x.len {
        sxx += (x[i] - xb) * (x[i] - xb)
        syy += (y[i] - yb) * (y[i] - yb)
        sxy0 += (x[i] - xb) * (y[i] - yb)
        dm += x[i] - y[i]
        i += 1usize
    }
    dm = dm / k
    i = 0usize
    while i < x.len {
        let dd = x[i] - y[i] - dm
        sdd += dd * dd
        i += 1usize
    }
    let sx2 = sxx / k
    let sy2 = syy / k
    let sd1 = math.sqrt[f64](syy / (k - 1.0f64))
    let sd2 = math.sqrt[f64](sxx / (k - 1.0f64))
    let r = sxy0 / math.sqrt[f64](sxx * syy)
    let sxy = r * math.sqrt[f64](sx2 * sy2)
    let p = 2.0f64 * sxy / (sx2 + sy2 + (yb - xb) * (yb - xb))
    let v = sd1 / sd2
    let u = (yb - xb) / math.pow[f64](sx2 * sy2, 0.25f64)
    let cb = p / r
    let sep = math.sqrt[f64](((1.0f64 - r * r) * p * p * (1.0f64 - p * p) / (r * r) + 2.0f64 * p * p * p * (1.0f64 - p) * u * u / r - 0.5f64 * p * p * p * p * u * u * u * u / (r * r)) / (k - 2.0f64))
    let tt = math.log[f64]((1.0f64 + p) / (1.0f64 - p)) / 2.0f64
    let set = sep / (1.0f64 - p * p)
    let llt = tt - zv * set
    let ult = tt + zv * set
    out[0usize] = p
    out[1usize] = p - zv * sep
    out[2usize] = p + zv * sep
    out[3usize] = (math.exp[f64](2.0f64 * llt) - 1.0f64) / (math.exp[f64](2.0f64 * llt) + 1.0f64)
    out[4usize] = (math.exp[f64](2.0f64 * ult) - 1.0f64) / (math.exp[f64](2.0f64 * ult) + 1.0f64)
    out[5usize] = v
    out[6usize] = u
    out[7usize] = cb
    out[8usize] = dm
    out[9usize] = math.sqrt[f64](sdd / (k - 1.0f64))
}

// epi.sscohortc, sample size from the two incidence risks and the power: (n exposed, n unexposed, n total); finite <= 0 means no finite population, frac keeps fractional counts
fn sscohort_n(irexp1: f64, irexp0: f64, power: f64, r: f64, design: f64, finite: f64, sided: f64, frac: bool, level: f64) -> (f64, f64, f64) {
    let za = dist.qnorm(1.0f64 - (1.0f64 - level) / sided, 0.0f64, 1.0f64, true, false)
    let zb = dist.qnorm(power, 0.0f64, 1.0f64, true, false)
    let lam = irexp1 / irexp0
    let pi = irexp0
    let pc = pi * (r * lam + 1.0f64) / (r + 1.0f64)
    let p1 = (r + 1.0f64) / (r * (lam - 1.0f64) * (lam - 1.0f64) * pi * pi)
    let p2 = za * math.sqrt[f64]((r + 1.0f64) * pc * (1.0f64 - pc))
    let p3 = zb * math.sqrt[f64](lam * pi * (1.0f64 - lam * pi) + r * pi * (1.0f64 - pi))
    var n = p1 * (p2 + p3) * (p2 + p3) * design
    if finite > 0.0f64 { n = n / (1.0f64 + n / finite) }
    if frac {
        let e1 = n / (r + 1.0f64) * r
        let e0 = n / (r + 1.0f64)
        ret (e1, e0, e1 + e0)
    }
    let e1c = math.ceil[f64](n / (r + 1.0f64)) * r
    let e0c = math.ceil[f64](n / (r + 1.0f64))
    ret (e1c, e0c, e1c + e0c)
}

// epi.sscohortc, the power reached by a total sample size n
fn sscohort_power(irexp1: f64, irexp0: f64, n0: f64, r: f64, design: f64, finite: f64, sided: f64, level: f64) -> f64 {
    let za = dist.qnorm(1.0f64 - (1.0f64 - level) / sided, 0.0f64, 1.0f64, true, false)
    let lam = irexp1 / irexp0
    let pi = irexp0
    let pc = pi * (r * lam + 1.0f64) / (r + 1.0f64)
    let n = n0 / design
    var nn = n
    if finite > 0.0f64 { nn = (n * finite - n) / (finite - n) }
    var t1 = pi * (1.0f64 - lam) * math.sqrt[f64](nn * r)
    if lam >= 1.0f64 { t1 = pi * (lam - 1.0f64) * math.sqrt[f64](nn * r) }
    let t2 = za * (r + 1.0f64) * math.sqrt[f64](pc * (1.0f64 - pc))
    let t3 = (r + 1.0f64) * (lam * pi * (1.0f64 - lam * pi) + r * pi * (1.0f64 - pi))
    ret dist.pnorm((t1 - t2) / math.sqrt[f64](t3), 0.0f64, 1.0f64, true, false)
}

// epi.sscc, unmatched case-control sample size for an odds ratio and a power: (cases, controls, total); finite <= 0 means no finite population
fn sscc_n(orr: f64, p0: f64, power: f64, r: f64, design: f64, finite: f64, sided: f64, frac: bool, level: f64) -> (f64, f64, f64) {
    let za = dist.qnorm(1.0f64 - (1.0f64 - level) / sided, 0.0f64, 1.0f64, true, false)
    let zb = dist.qnorm(1.0f64 - power, 0.0f64, 1.0f64, false, false)
    let pc = p0 / (r + 1.0f64) * (r * orr / (1.0f64 + (orr - 1.0f64) * p0) + 1.0f64)
    let t1 = (r + 1.0f64) * (1.0f64 + (orr - 1.0f64) * p0) * (1.0f64 + (orr - 1.0f64) * p0)
    let t2 = r * p0 * p0 * (p0 - 1.0f64) * (p0 - 1.0f64) * (orr - 1.0f64) * (orr - 1.0f64)
    let t3 = za * math.sqrt[f64]((r + 1.0f64) * pc * (1.0f64 - pc))
    let t5 = 1.0f64 + (orr - 1.0f64) * p0
    let t6 = orr * p0 * (1.0f64 - p0) / (t5 * t5)
    let t7 = r * p0 * (1.0f64 - p0)
    let t8 = zb * math.sqrt[f64](t6 + t7)
    let n = t1 / t2 * (t3 + t8) * (t3 + t8)
    let n1c = n / (1.0f64 + r) * design
    let n0c = r * n1c
    let ntc = n0c + n1c
    var n1 = n1c
    var n0 = n0c
    if finite > 0.0f64 {
        let nta = ntc / (1.0f64 + ntc / finite)
        n1 = n1c / ntc * nta
        n0 = n0c / ntc * nta
    }
    if !frac {
        n1 = math.ceil[f64](n1)
        n0 = math.ceil[f64](n0)
    }
    ret (n1, n0, n1 + n0)
}

// epi.sscc, the power reached by a total n (unmatched)
fn sscc_power(orr: f64, p0: f64, n: f64, r: f64, sided: f64, level: f64) -> f64 {
    let za = dist.qnorm(1.0f64 - (1.0f64 - level) / sided, 0.0f64, 1.0f64, true, false)
    let pc = p0 / (r + 1.0f64) * (r * orr / (1.0f64 + (orr - 1.0f64) * p0) + 1.0f64)
    let m = math.abs[f64]((orr - 1.0f64) * (p0 - 1.0f64) / (1.0f64 + (orr - 1.0f64) * p0))
    let tn1 = m * p0 * math.sqrt[f64](n * r) / math.sqrt[f64](r + 1.0f64)
    let tn2 = za * math.sqrt[f64]((r + 1.0f64) * pc * (1.0f64 - pc))
    let td1 = orr * p0 * (1.0f64 - p0) / ((1.0f64 + (orr - 1.0f64) * p0) * (1.0f64 + (orr - 1.0f64) * p0))
    let td2 = r * p0 * (1.0f64 - p0)
    ret dist.pnorm((tn1 - tn2) / math.sqrt[f64](td1 + td2), 0.0f64, 1.0f64, true, false)
}

// epi.dsl: DerSimonian-Laird random-effects pooling of k two-by-two tables (ev_t, n_t, ev_c, n_c per study, a half added to a table with a cell below 1) for odds
// ratios, or risk ratios when rr is set (where Q is taken about the Mantel-Haenszel-weighted ratio, weights b c / N, as epiR does);
// out = (tau squared, pooled ratio, lower, upper, Cochran's Q, heterogeneity p value, I squared in percent)
fn epi_dsl_or(evt: []const f64, nt: []const f64, evc: []const f64, nc: []const f64, rr: bool, level: f64, out: []f64) {
    let k = evt.len
    let z = z_of(level)
    var sw = 0.0f64
    var sw2 = 0.0f64
    var swo = 0.0f64
    var smw = 0.0f64
    var smr = 0.0f64
    var i = 0usize
    while i < k {
        let (l, v) = study_lnor(evt[i], nt[i], evc[i], nc[i], rr)
        let ratio = math.exp[f64](l)
        let w = 1.0f64 / v
        sw += w
        sw2 += w * w
        swo += w * ratio
        var a = evt[i]
        var b = nt[i] - evt[i]
        var c = evc[i]
        var d = nc[i] - evc[i]
        if a < 1.0f64 || b < 1.0f64 || c < 1.0f64 || d < 1.0f64 {
            a += 0.5f64
            b += 0.5f64
            c += 0.5f64
            d += 0.5f64
        }
        let wm = b * c / (a + b + c + d)
        smw += wm
        smr += wm * ratio
        i += 1usize
    }
    var lnmh = math.log[f64](swo / sw)
    if rr { lnmh = math.log[f64](smr / smw) }
    var q = 0.0f64
    i = 0usize
    while i < k {
        let (l, v) = study_lnor(evt[i], nt[i], evc[i], nc[i], rr)
        q += (l - lnmh) * (l - lnmh) / v
        i += 1usize
    }
    let df = f64(k) - 1.0f64
    var tau2 = 0.0f64
    if q >= df { tau2 = (q - df) / (sw - sw2 / sw) }
    var swd = 0.0f64
    var swdl = 0.0f64
    i = 0usize
    while i < k {
        let (l, v) = study_lnor(evt[i], nt[i], evc[i], nc[i], rr)
        let wd = 1.0f64 / (v + tau2)
        swd += wd
        swdl += wd * l
        i += 1usize
    }
    let lnd = swdl / swd
    let sed = 1.0f64 / math.sqrt[f64](swd)
    let hsq = q / df
    out[0usize] = tau2
    out[1usize] = math.exp[f64](lnd)
    out[2usize] = math.exp[f64](lnd - z * sed)
    out[3usize] = math.exp[f64](lnd + z * sed)
    out[4usize] = q
    out[5usize] = 1.0f64 - nm.pchisq(q, df, true, false)
    out[6usize] = (hsq - 1.0f64) / hsq * 100.0f64
}

// ln odds ratio and its variance of study i with epiR's half-correction (a half added to every cell of a table with a cell below 1): (ln OR, variance)
fn study_lnor(evt: f64, nt: f64, evc: f64, nc: f64, rr: bool) -> (f64, f64) {
    var a = evt
    var b = nt - evt
    var c = evc
    var d = nc - evc
    if a < 1.0f64 || b < 1.0f64 || c < 1.0f64 || d < 1.0f64 {
        a += 0.5f64
        b += 0.5f64
        c += 0.5f64
        d += 0.5f64
    }
    if rr {
        let n1 = a + b
        let n2 = c + d
        ret (math.log[f64]((a / n1) / (c / n2)), 1.0f64 / a + 1.0f64 / c - 1.0f64 / n1 - 1.0f64 / n2)
    }
    ret (math.log[f64](a * d / (b * c)), 1.0f64 / a + 1.0f64 / b + 1.0f64 / c + 1.0f64 / d)
}

// epi.iv for odds ratios, or risk ratios when rr is set (inverse-variance fixed effect); out = (pooled OR, lower, upper, Q, heterogeneity p, I squared, H squared, H squared lower,
// H squared upper, I squared lower, I squared upper, effect z, effect p two-sided)
fn epi_iv_or(evt: []const f64, nt: []const f64, evc: []const f64, nc: []const f64, rr: bool, level: f64, out: []f64) {
    let k = f64(evt.len)
    let z = z_of(level)
    var sw = 0.0f64
    var swl = 0.0f64
    var i = 0usize
    while i < evt.len {
        let (l, v) = study_lnor(evt[i], nt[i], evc[i], nc[i], rr)
        sw += 1.0f64 / v
        swl += l / v
        i += 1usize
    }
    let lniv = swl / sw
    var q = 0.0f64
    i = 0usize
    while i < evt.len {
        let (l, v) = study_lnor(evt[i], nt[i], evc[i], nc[i], rr)
        q += (l - lniv) * (l - lniv) / v
        i += 1usize
    }
    let se = 1.0f64 / math.sqrt[f64](sw)
    let df = k - 1.0f64
    let hsq = q / df
    var lse = 0.0f64
    if q > k {
        lse = (math.log[f64](q) - math.log[f64](k - 1.0f64)) / (2.0f64 * math.sqrt[f64](2.0f64 * q) - math.sqrt[f64](2.0f64 * (k - 3.0f64)))
    } else {
        lse = math.sqrt[f64](1.0f64 / (2.0f64 * (k - 2.0f64)) * (1.0f64 - 1.0f64 / (3.0f64 * (k - 2.0f64) * (k - 2.0f64))))
    }
    let hl = math.exp[f64](math.log[f64](hsq) - z * lse)
    let hu = math.exp[f64](math.log[f64](hsq) + z * lse)
    let ez = lniv / se
    out[0usize] = math.exp[f64](lniv)
    out[1usize] = math.exp[f64](lniv - z * se)
    out[2usize] = math.exp[f64](lniv + z * se)
    out[3usize] = q
    out[4usize] = 1.0f64 - nm.pchisq(q, df, true, false)
    out[5usize] = (hsq - 1.0f64) / hsq * 100.0f64
    out[6usize] = hsq
    out[7usize] = hl
    out[8usize] = hu
    out[9usize] = (hl - 1.0f64) / hl * 100.0f64
    out[10usize] = (hu - 1.0f64) / hu * 100.0f64
    out[11usize] = ez
    out[12usize] = 2.0f64 * dist.pnorm(math.abs[f64](ez), 0.0f64, 1.0f64, false, false)
}

// epi.sssimpleestb: sample size to estimate a true prevalence py from a test of sensitivity se and specificity sp within epsilon (relative or absolute error); finite <= 0 means no finite population
fn sssimpleestb(finite: f64, py: f64, epsilon: f64, absolute: bool, se: f64, sp: f64, frac: bool, level: f64) -> f64 {
    let z = z_of(level)
    var ea = py * epsilon
    if absolute { ea = epsilon }
    let p01 = (z / ea) * (z / ea)
    let ap = se * py + (1.0f64 - sp) * (1.0f64 - py)
    let p02u = ap * (1.0f64 - ap)
    let p02l = (se + sp - 1.0f64) * (se + sp - 1.0f64)
    let nc = p01 * (p02u / p02l)
    var n = nc
    if finite > 0.0f64 { n = nc / (1.0f64 + nc / finite) }
    if frac { ret n }
    ret math.ceil[f64](n)
}

// epi.2by2 on a stack of K cohort tables (a, b, c, d per stratum): Mantel-Haenszel risk ratio and odds ratio with their intervals, the Mantel-Haenszel
// chi-squared statistic and Woolf's homogeneity statistics; out = (RR, lower, upper, OR, lower, upper, MH chi2, RR homogeneity, OR homogeneity)
fn strata_mh(a: []const f64, b: []const f64, c: []const f64, d: []const f64, level: f64, out: []f64) {
    let k = a.len
    let z = z_of(level)
    var rn = 0.0f64
    var rd = 0.0f64
    var rv = 0.0f64
    var g = 0.0f64
    var h = 0.0f64
    var gp = 0.0f64
    var gqhp = 0.0f64
    var hq = 0.0f64
    var ea = 0.0f64
    var va = 0.0f64
    var oa = 0.0f64
    var i = 0usize
    while i < k {
        let n1 = a[i] + b[i]
        let n0 = c[i] + d[i]
        let m1 = a[i] + c[i]
        let m0 = b[i] + d[i]
        let t = n1 + n0
        rn += a[i] * n0 / t
        rd += c[i] * n1 / t
        rv += m1 * n1 * n0 / (t * t) - a[i] * c[i] / t
        let gi = a[i] * d[i] / t
        let hi = b[i] * c[i] / t
        let pi = (a[i] + d[i]) / t
        let qi = (b[i] + c[i]) / t
        g += gi
        h += hi
        gp += gi * pi
        hq += hi * qi
        gqhp += gi * qi + hi * pi
        oa += a[i]
        ea += n1 * m1 / t
        va += n1 * n0 * m1 * m0 / (t * t * (t - 1.0f64))
        i += 1usize
    }
    let rr = rn / rd
    let sre = math.sqrt[f64](rv / (rn * rd))
    let orr = g / h
    let sor = math.sqrt[f64](gp / (2.0f64 * g * g) + gqhp / (2.0f64 * g * h) + hq / (2.0f64 * h * h))
    out[0usize] = rr
    out[1usize] = math.exp[f64](math.log[f64](rr) - z * sre)
    out[2usize] = math.exp[f64](math.log[f64](rr) + z * sre)
    out[3usize] = orr
    out[4usize] = math.exp[f64](math.log[f64](orr) - z * sor)
    out[5usize] = math.exp[f64](math.log[f64](orr) + z * sor)
    out[6usize] = (oa - ea) * (oa - ea) / va
    var sw = 0.0f64
    var swl = 0.0f64
    var sv = 0.0f64
    var svl = 0.0f64
    i = 0usize
    while i < k {
        let lr = math.log[f64]((a[i] / (a[i] + b[i])) / (c[i] / (c[i] + d[i])))
        let wr = 1.0f64 / (b[i] / (a[i] * (a[i] + b[i])) + d[i] / (c[i] * (c[i] + d[i])))
        sw += wr
        swl += wr * lr
        let lo = math.log[f64](((a[i] + 0.5f64) * (d[i] + 0.5f64)) / ((b[i] + 0.5f64) * (c[i] + 0.5f64)))
        let wo = 1.0f64 / (1.0f64 / (a[i] + 0.5f64) + 1.0f64 / (b[i] + 0.5f64) + 1.0f64 / (c[i] + 0.5f64) + 1.0f64 / (d[i] + 0.5f64))
        sv += wo
        svl += wo * lo
        i += 1usize
    }
    let mr = swl / sw
    let mo = svl / sv
    var hr = 0.0f64
    var ho = 0.0f64
    i = 0usize
    while i < k {
        let lr = math.log[f64]((a[i] / (a[i] + b[i])) / (c[i] / (c[i] + d[i])))
        let wr = 1.0f64 / (b[i] / (a[i] * (a[i] + b[i])) + d[i] / (c[i] * (c[i] + d[i])))
        hr += wr * (lr - mr) * (lr - mr)
        let lo = math.log[f64](((a[i] + 0.5f64) * (d[i] + 0.5f64)) / ((b[i] + 0.5f64) * (c[i] + 0.5f64)))
        let wo = 1.0f64 / (1.0f64 / (a[i] + 0.5f64) + 1.0f64 / (b[i] + 0.5f64) + 1.0f64 / (c[i] + 0.5f64) + 1.0f64 / (d[i] + 0.5f64))
        ho += wo * (lo - mo) * (lo - mo)
        i += 1usize
    }
    out[7usize] = hr
    out[8usize] = ho
}

// Mantel-Haenszel risk difference with its Wald interval and the number needed to treat from it, for K cohort tables; out = (RD, lower, upper, NNT, lower, upper)
fn strata_mh_rd(a: []const f64, b: []const f64, c: []const f64, d: []const f64, level: f64, units: f64, out: []f64) {
    let k = a.len
    let z = z_of(level)
    var num = 0.0f64
    var den = 0.0f64
    var vs = 0.0f64
    var i = 0usize
    while i < k {
        let n1 = a[i] + b[i]
        let n0 = c[i] + d[i]
        let t = n1 + n0
        let w = n1 * n0 / t
        num += (a[i] * n0 - c[i] * n1) / t
        den += w
        var v = a[i] * d[i] / (n1 * n1 * (n1 - 1.0f64)) + c[i] * b[i] / (n0 * n0 * (n0 - 1.0f64))
        if n0 == 1.0f64 || n1 == 1.0f64 { v = 0.0f64 }
        vs += w * w * v
        i += 1usize
    }
    let est = num / den * units
    let se = math.sqrt[f64](vs / (den * den)) * units
    let lo = est - z * se
    let hi = est + z * se
    let n_est = 1.0f64 / (est / units)
    let n1v = 1.0f64 / (lo / units)
    let n2v = 1.0f64 / (hi / units)
    let nl = math.min[f64](n1v, n2v)
    out[0usize] = est
    out[1usize] = lo
    out[2usize] = hi
    out[3usize] = n_est
    out[4usize] = nl
    out[5usize] = math.max[f64](n1v, n2v)
}

// Mantel-Haenszel risk difference of K cohort tables with the Sato (kind 0) or Greenland-Robins (kind 1) variance: (RD, lower, upper) scaled by units
fn strata_mh_rd_var(a: []const f64, b: []const f64, c: []const f64, d: []const f64, level: f64, units: f64, kind: usize) -> (f64, f64, f64) {
    let k = a.len
    let z = z_of(level)
    var num = 0.0f64
    var w = 0.0f64
    var p = 0.0f64
    var q = 0.0f64
    var i = 0usize
    while i < k {
        let c1 = a[i]
        let c2 = a[i] + b[i]
        let c3 = c[i]
        let c4 = c[i] + d[i]
        num += (c1 * c4 - c3 * c2) / (c2 + c4)
        w += c2 * c4 / (c2 + c4)
        p += (c2 * c2 * c3 - c4 * c4 * c1 + 0.5f64 * c2 * c4 * (c4 - c2)) / ((c2 + c4) * (c2 + c4))
        q += (c1 * (c4 - c3) + c3 * (c2 - c1)) / (2.0f64 * (c2 + c4))
        i += 1usize
    }
    let dm = num / w
    var v = (dm * p + q) / (w * w)
    if kind == 1usize {
        var s = 0.0f64
        i = 0usize
        while i < k {
            let c1 = a[i]
            let c2 = a[i] + b[i]
            let c3 = c[i]
            let c4 = c[i] + d[i]
            let dn = c2 * c4 / (c2 + c4)
            let p1 = c1 / c2
            let p2 = c3 / c4
            s += dn * dn * (p1 * (1.0f64 - p1) / c2 + p2 * (1.0f64 - p2) / c4)
            i += 1usize
        }
        v = s / (w * w)
    }
    let h = z * math.sqrt[f64](v)
    ret (dm * units, (dm - h) * units, (dm + h) * units)
}

// Breslow-Day homogeneity statistic of the odds ratio over K tables, as epi.2by2 computes it (expected count from the Mantel-Haenszel odds ratio, root chosen inside [0, min(row1, col1)])
fn breslow_day(a: []const f64, b: []const f64, c: []const f64, d: []const f64) -> f64 {
    let k = a.len
    var g = 0.0f64
    var h = 0.0f64
    var i = 0usize
    while i < k {
        let t = a[i] + b[i] + c[i] + d[i]
        g += a[i] * d[i] / t
        h += b[i] * c[i] / t
        i += 1usize
    }
    let so = g / h
    var s = 0.0f64
    i = 0usize
    while i < k {
        let r1 = a[i] + b[i]
        let r2 = c[i] + d[i]
        let c1 = a[i] + c[i]
        var amax = r1
        if c1 < amax { amax = c1 }
        let bb = r2 + r1 * so - c1 * (1.0f64 - so)
        let det = math.sqrt[f64](bb * bb + 4.0f64 * (1.0f64 - so) * so * r1 * c1)
        let lo = (0.0f64 - bb - det) / (2.0f64 - 2.0f64 * so)
        let hi = (0.0f64 - bb + det) / (2.0f64 - 2.0f64 * so)
        var ast = hi
        if lo <= amax && lo >= 0.0f64 { ast = lo }
        let bst = r1 - ast
        let cst = c1 - ast
        let dst = r2 - c1 + ast
        let v = 1.0f64 / (1.0f64 / ast + 1.0f64 / bst + 1.0f64 / cst + 1.0f64 / dst)
        s += (a[i] - ast) * (a[i] - ast) / v
        i += 1usize
    }
    ret s
}

type KoopCtx = struct { m: f64, n: f64, x: f64, y: f64, x2: f64 }

fn koop_u(c: *KoopCtx, a: f64) -> f64 {
    let t = a * (c.m + c.y) + c.x + c.n
    let p = (t - math.sqrt[f64](t * t - 4.0f64 * a * (c.m + c.n) * (c.x + c.y))) / (2.0f64 * (c.m + c.n))
    ret ((c.x - c.m * p) * (c.x - c.m * p)) / (c.m * p * (1.0f64 - p)) * (1.0f64 + c.m * (a - p) / (c.n * (1.0f64 - p))) - c.x2
}

// epiR zRRkoopman for an interior table (0 < a < a + b, 0 < c < c + d): the Koopman score interval of the risk ratio, each end the root (R's uniroot, tolerance eps^0.25) of the score
// statistic minus the chi-squared quantile on a bracket built from the log-scale standard error; (est, lower, upper)
fn rr_koopman(t: Table2, level: f64) -> (f64, f64, f64) {
    let z = z_of(level)
    var c = KoopCtx { m: t.a + t.c, n: t.b + t.d, x: t.a, y: t.b, x2: nm.qchisq(level, 1.0f64, true, false) }
    let est = (c.x / c.m) / (c.y / c.n)
    let varhat = 1.0f64 / c.x - 1.0f64 / c.m + 1.0f64 / c.y - 1.0f64 / c.n
    let la = est * math.exp[f64](0.0f64 - z * math.sqrt[f64](varhat)) / 4.0f64
    let hb = est * math.exp[f64](z * math.sqrt[f64](varhat)) * 4.0f64
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let lo = pw.zeroin[KoopCtx](&c, koop_u, la, est, tol, 1000i64)
    let hi = pw.zeroin[KoopCtx](&c, koop_u, est, hb, tol, 1000i64)
    ret (est, lo, hi)
}

// ---- fisher.test's conditional MLE of the odds ratio and its exact confidence interval for a 2 by 2 table (epiR zORml): the non-central hypergeometric law of a on the support lo .. hi,
// and R's uniroot (the existing `pwr.zeroin`, tolerance eps^0.25) on the brackets (0, 1) and (eps, 1) with the inverted argument, exactly as fisher.test sets them up.
type FiCtx = struct { lo: f64, hi: f64, x: f64, alpha: f64, mode: usize, logdc: []f64, buf: []f64, len: usize }

fn fi_dn(c: *FiCtx, ncp: f64) {
    var mx = -1.0e300f64
    var i = 0usize
    while i < c.len {
        let v = c.logdc[i] + math.log[f64](ncp) * (c.lo + f64(i))
        c.buf[i] = v
        if v > mx { mx = v }
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < c.len {
        c.buf[i] = math.exp[f64](c.buf[i] - mx)
        s += c.buf[i]
        i += 1usize
    }
    i = 0usize
    while i < c.len {
        c.buf[i] = c.buf[i] / s
        i += 1usize
    }
}

fn fi_mn(c: *FiCtx, ncp: f64) -> f64 {
    if ncp == 0.0f64 { ret c.lo }
    if ncp > 1.0e300f64 { ret c.hi }
    fi_dn(c, ncp)
    var s = 0.0f64
    var i = 0usize
    while i < c.len {
        s += (c.lo + f64(i)) * c.buf[i]
        i += 1usize
    }
    ret s
}

fn fi_pn(c: *FiCtx, ncp: f64, upper: bool) -> f64 {
    if ncp == 0.0f64 {
        if upper { if c.x <= c.lo { ret 1.0f64 } else { ret 0.0f64 } }
        if c.x >= c.lo { ret 1.0f64 } else { ret 0.0f64 }
    }
    if ncp > 1.0e300f64 {
        if upper { if c.x <= c.hi { ret 1.0f64 } else { ret 0.0f64 } }
        if c.x >= c.hi { ret 1.0f64 } else { ret 0.0f64 }
    }
    fi_dn(c, ncp)
    var s = 0.0f64
    var i = 0usize
    while i < c.len {
        let sv = c.lo + f64(i)
        if upper { if sv >= c.x { s += c.buf[i] } } else { if sv <= c.x { s += c.buf[i] } }
        i += 1usize
    }
    ret s
}

fn fi_f(c: *FiCtx, t: f64) -> f64 {
    if c.mode == 0usize { ret fi_mn(c, t) - c.x }
    if c.mode == 1usize { ret fi_mn(c, 1.0f64 / t) - c.x }
    if c.mode == 2usize { ret fi_pn(c, t, false) - c.alpha }
    if c.mode == 3usize { ret fi_pn(c, 1.0f64 / t, false) - c.alpha }
    if c.mode == 4usize { ret fi_pn(c, t, true) - c.alpha }
    if c.mode == 5usize { ret fi_pn(c, 1.0f64 / t, true) - c.alpha }
    // modes 6 and 7: the mid-p functions of the Cornfield interval, sum of the law above (6) or below (7) the observed count minus half its mass minus alpha
    fi_dn(c, t)
    var sm = 0.0f64
    var i = 0usize
    while i < c.len {
        let sv = c.lo + f64(i)
        if c.mode == 6usize { if sv >= c.x { sm += c.buf[i] } } else { if sv <= c.x { sm += c.buf[i] } }
        i += 1usize
    }
    ret sm - c.buf[usize(c.x - c.lo)] / 2.0f64 - c.alpha
}

// (conditional MLE, lower, upper) of the odds ratio of the table a b / c d at the confidence level
fn fisher_or(a: *mem.Arena, t: Table2, level: f64) -> (f64, f64, f64, err) {
    let m = t.a + t.c
    let nn = t.b + t.d
    let k = t.a + t.b
    var lo = 0.0f64
    if k - nn > 0.0f64 { lo = k - nn }
    var hi = k
    if m < hi { hi = m }
    let len = usize(hi - lo) + 1usize
    let (lg, e1) = mem.alloc[f64](a, len)
    let (bf, e2) = mem.alloc[f64](a, len)
    if e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e1) }
    var i = 0usize
    while i < len {
        let s = lo + f64(i)
        lg[i] = nm.lgammafn(m + 1.0f64) - nm.lgammafn(s + 1.0f64) - nm.lgammafn(m - s + 1.0f64) + nm.lgammafn(nn + 1.0f64) - nm.lgammafn(k - s + 1.0f64) - nm.lgammafn(nn - k + s + 1.0f64) - (nm.lgammafn(m + nn + 1.0f64) - nm.lgammafn(k + 1.0f64) - nm.lgammafn(m + nn - k + 1.0f64))
        i += 1usize
    }
    var c = FiCtx { lo: lo, hi: hi, x: t.a, alpha: (1.0f64 - level) / 2.0f64, mode: 0usize, logdc: lg, buf: bf, len: len }
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let eps = 2.220446049250313e-16f64
    var mle = 1.0f64
    if t.a == lo { mle = 0.0f64 } else if t.a == hi { mle = 1.0f64 / 0.0f64 } else {
        let mu = fi_mn(&c, 1.0f64)
        if mu > t.a {
            c.mode = 0usize
            mle = pw.zeroin[FiCtx](&c, fi_f, 0.0f64, 1.0f64, tol, 1000i64)
        } else if mu < t.a {
            c.mode = 1usize
            mle = 1.0f64 / pw.zeroin[FiCtx](&c, fi_f, eps, 1.0f64, tol, 1000i64)
        }
    }
    var upper = 1.0f64
    if t.a == hi { upper = 1.0f64 / 0.0f64 } else {
        let p = fi_pn(&c, 1.0f64, false)
        if p < c.alpha {
            c.mode = 2usize
            upper = pw.zeroin[FiCtx](&c, fi_f, 0.0f64, 1.0f64, tol, 1000i64)
        } else if p > c.alpha {
            c.mode = 3usize
            upper = 1.0f64 / pw.zeroin[FiCtx](&c, fi_f, eps, 1.0f64, tol, 1000i64)
        }
    }
    var lower = 1.0f64
    if t.a == lo { lower = 0.0f64 } else {
        let p2 = fi_pn(&c, 1.0f64, true)
        if p2 > c.alpha {
            c.mode = 4usize
            lower = pw.zeroin[FiCtx](&c, fi_f, 0.0f64, 1.0f64, tol, 1000i64)
        } else if p2 < c.alpha {
            c.mode = 5usize
            lower = 1.0f64 / pw.zeroin[FiCtx](&c, fi_f, eps, 1.0f64, tol, 1000i64)
        }
    }
    ret (mle, lower, upper, ok)
}

// epiR zORcfield for an interior table: Cornfield's exact mid-p odds-ratio interval, each end the uniroot (tolerance eps^0.25) on (1e-8, 1e8) of the mid-p tail probability minus
// (1 - level) / 2 under Fisher's non-central hypergeometric law; (est, lower, upper)
fn or_cfield(a: *mem.Arena, t: Table2, level: f64) -> (f64, f64, f64, err) {
    let m = t.a + t.c
    let nn = t.b + t.d
    let k = t.a + t.b
    var lo = 0.0f64
    if k - nn > 0.0f64 { lo = k - nn }
    var hi = k
    if m < hi { hi = m }
    let len = usize(hi - lo) + 1usize
    let (lg, e1) = mem.alloc[f64](a, len)
    let (bf, e2) = mem.alloc[f64](a, len)
    if e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e1) }
    var i = 0usize
    while i < len {
        let s = lo + f64(i)
        lg[i] = nm.lgammafn(m + 1.0f64) - nm.lgammafn(s + 1.0f64) - nm.lgammafn(m - s + 1.0f64) + nm.lgammafn(nn + 1.0f64) - nm.lgammafn(k - s + 1.0f64) - nm.lgammafn(nn - k + s + 1.0f64) - (nm.lgammafn(m + nn + 1.0f64) - nm.lgammafn(k + 1.0f64) - nm.lgammafn(m + nn - k + 1.0f64))
        i += 1usize
    }
    var c = FiCtx { lo: lo, hi: hi, x: t.a, alpha: (1.0f64 - level) / 2.0f64, mode: 6usize, logdc: lg, buf: bf, len: len }
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let ll = pw.zeroin[FiCtx](&c, fi_f, 1.0e-8f64, 1.0e8f64, tol, 1000i64)
    c.mode = 7usize
    let ul = pw.zeroin[FiCtx](&c, fi_f, 1.0e-8f64, 1.0e8f64, tol, 1000i64)
    ret ((t.a / t.b) / (t.c / t.d), ll, ul, ok)
}

// ---- epi.conf, the closed-form types: mean.single (t interval of a mean), mean.unpaired (pooled-variance t interval of the difference of two group means), mean.paired (t interval of the
// mean paired difference x2 - x1), inc.rate (exact chi-squared or Byar interval of a count over person-time), smr (exact interval of an observed count over its expectation from the
// pooled rate) and odds (the qbinom interval of a / b); each answers what epi.conf lists
fn conf_mean_single(x: []const f64, level: f64) -> (f64, f64, f64, f64) {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / n
    var v = 0.0f64
    i = 0usize
    while i < x.len {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    v = v / (n - 1.0f64)
    let se = math.sqrt[f64](v) / math.sqrt[f64](n)
    let t = math.abs[f64](nb.qt((1.0f64 - level) / 2.0f64, n - 1.0f64, true, false))
    ret (m, se, m - t * se, m + t * se)
}

fn conf_mean_unpaired(x1: []const f64, x2: []const f64, level: f64) -> (f64, f64, f64, f64) {
    let (m1, s1, l1, u1) = conf_mean_single(x1, level)
    let (m2, s2, l2, u2) = conf_mean_single(x2, level)
    let n1 = f64(x1.len)
    let n2 = f64(x2.len)
    let v1 = s1 * s1 * n1
    let v2 = s2 * s2 * n2
    let sp = math.sqrt[f64](((n1 - 1.0f64) * v1 + (n2 - 1.0f64) * v2) / (n1 + n2 - 2.0f64))
    let se = sp * math.sqrt[f64](1.0f64 / n1 + 1.0f64 / n2)
    let t = math.abs[f64](nb.qt((1.0f64 - level) / 2.0f64, n1 + n2 - 2.0f64, true, false))
    let _ = l1
    let _ = u1
    let _ = l2
    let _ = u2
    ret (m1 - m2, se, m1 - m2 - t * se, m1 - m2 + t * se)
}

fn conf_mean_paired(a: *mem.Arena, x1: []const f64, x2: []const f64, level: f64) -> (f64, f64, f64, f64) {
    let (d, e) = mem.alloc[f64](a, x1.len)
    if e != ok { ret (0.0f64, 0.0f64, 0.0f64, 0.0f64) }
    var i = 0usize
    while i < x1.len {
        d[i] = x2[i] - x1[i]
        i += 1usize
    }
    let (pm, ps, pl, pu) = conf_mean_single(d, level)
    ret (pm, ps, pl, pu)
}

// (est, lower, upper) of the incidence rate a / pt by the exact chi-squared method (byar false) or Byar's approximation
fn conf_inc_rate(a: f64, pt: f64, level: f64, byar: bool) -> (f64, f64, f64) {
    let nq = 1.0f64 - (1.0f64 - level) / 2.0f64
    let p = a / pt
    if !byar { ret (p, nm.qchisq(1.0f64 - nq, 2.0f64 * a, true, false) / 2.0f64 / pt, nm.qchisq(nq, 2.0f64 * (a + 1.0f64), true, false) / 2.0f64 / pt) }
    let z = z_of(level)
    let ap = a + 0.5f64
    let cl = 1.0f64 - 1.0f64 / (9.0f64 * ap) - z / 3.0f64 * math.sqrt[f64](1.0f64 / ap)
    let cu = 1.0f64 - 1.0f64 / (9.0f64 * ap) + z / 3.0f64 * math.sqrt[f64](1.0f64 / ap)
    ret (p, ap * cl * cl * cl / pt, ap * cu * cu * cu / pt)
}

// row i of the standardised mortality ratio table (observed counts obs, person-time pt): (smr, se, lower, upper)
fn conf_smr(obs: []const f64, pt: []const f64, i: usize, level: f64) -> (f64, f64, f64, f64) {
    var so = 0.0f64
    var sp = 0.0f64
    var j = 0usize
    while j < obs.len {
        so += obs[j]
        sp += pt[j]
        j += 1usize
    }
    let ex = so / sp * pt[i]
    let nq = 1.0f64 - (1.0f64 - level) / 2.0f64
    var lo = 0.0f64
    if obs[i] > 0.0f64 { lo = nm.qchisq(nq, 2.0f64 * obs[i], false, false) / 2.0f64 / ex }
    var hi = nm.qchisq(1.0f64 - nq, 2.0f64, false, false) / 2.0f64 / ex
    if obs[i] > 0.0f64 { hi = nm.qchisq(1.0f64 - nq, 2.0f64 * (obs[i] + 1.0f64), false, false) / 2.0f64 / ex }
    ret (obs[i] / ex, math.sqrt[f64](pt[i]) / ex, lo, hi)
}

// (odds a / b, lower, upper) with the qbinom ends of epi.conf(ctype = "odds")
fn conf_odds(a: f64, b: f64, level: f64) -> (f64, f64, f64) {
    let nq = 1.0f64 - (1.0f64 - level) / 2.0f64
    let al = nb.qbinom(1.0f64 - nq, a + b, a / (a + b), true, false) / (a + b)
    let au = nb.qbinom(nq, a + b, a / (a + b), true, false) / (a + b)
    ret (a / b, al / (1.0f64 - al), au / (1.0f64 - au))
}

// epi.conf's internal .propsingle (Wilson score, with the standard error of the proportion): the row (r successes, m failures) answers (p, se, lower, upper)
fn conf_prop_single(r: f64, m: f64, level: f64) -> (f64, f64, f64, f64) {
    let z = z_of(level)
    let n = r + m
    let p = r / n
    let q = 1.0f64 - r / n
    let se = math.sqrt[f64](p * q / n)
    let aa = 2.0f64 * r + z * z
    let bb = z * math.sqrt[f64](z * z + 4.0f64 * r * q)
    let cc = 2.0f64 * (n + z * z)
    ret (p, se, (aa - bb) / cc, (aa + bb) / cc)
}

// prop.unpaired: the difference of two independent proportions (r1, m1) and (r2, m2) with the Newcombe hybrid-score interval: (est, se, lower, upper)
fn conf_prop_unpaired(r1: f64, m1: f64, r2: f64, m2: f64, level: f64) -> (f64, f64, f64, f64) {
    let (p1, s1, l1, u1) = conf_prop_single(r1, m1, level)
    let (p2, s2, l2, u2) = conf_prop_single(r2, m2, level)
    let n1 = r1 + m1
    let n2 = r2 + m2
    let d = p1 - p2
    let se = math.sqrt[f64](p1 * (1.0f64 - p1) / n1 + p2 * (1.0f64 - p2) / n2)
    let _ = s1
    let _ = s2
    ret (d, se, d - math.sqrt[f64]((p1 - l1) * (p1 - l1) + (u2 - p2) * (u2 - p2)), d + math.sqrt[f64]((p2 - l2) * (p2 - l2) + (u1 - p1) * (u1 - p1)))
}

// prop.paired: the difference of two paired proportions from the 2 by 2 counts (r, s, t, u) with Newcombe's correlation-corrected interval: (est, se, lower, upper)
fn conf_prop_paired(r: f64, s: f64, t: f64, u: f64, level: f64) -> (f64, f64, f64, f64) {
    let n = r + s + t + u
    let p1 = (r + s) / n
    let p2 = (r + t) / n
    let d = (s - t) / n
    let aa = (r + s) * (t + u) * (r + t) * (s + u)
    let bb = r * u - s * t
    let se = math.sqrt[f64](s + t - (s - t) * (s - t) / n) / n
    var cc = 0.0f64
    if bb > n / 2.0f64 { cc = bb - n / 2.0f64 }
    if bb < 0.0f64 { cc = bb }
    var phi = cc / math.sqrt[f64](aa)
    if r + s == 0.0f64 || t + u == 0.0f64 || r + t == 0.0f64 || s + u == 0.0f64 { phi = 0.0f64 }
    let (e1, s1, l1, u1) = conf_prop_single(r + s, n - (r + s), level)
    let (e2, s2, l2, u2) = conf_prop_single(r + t, n - (r + t), level)
    let _ = e1
    let _ = s1
    let _ = e2
    let _ = s2
    let lo = d - math.sqrt[f64]((p1 - l1) * (p1 - l1) - 2.0f64 * phi * (p1 - l1) * (u2 - p2) + (u2 - p2) * (u2 - p2))
    let hi = d + math.sqrt[f64]((p2 - l2) * (p2 - l2) - 2.0f64 * phi * (p2 - l2) * (u1 - p1) + (u1 - p1) * (u1 - p1))
    ret (d, se, lo, hi)
}

// ---- epi.2by2(method = "cohort.time"): a and c are the cases of the exposed and unexposed, b and d their person-time. Answers are (est, lower, upper) unless noted.
// IRR: the incidence rate ratio with epiR's exact F-based interval
fn ct_irr(a: f64, b: f64, c: f64, d: f64, level: f64) -> (f64, f64, f64) {
    let al = (1.0f64 - level) / 2.0f64
    let est = (a / b) / (c / d)
    let lo = d / b * (a / (c + 1.0f64)) / nb.qf(al, 2.0f64 * (c + 1.0f64), 2.0f64 * a, false, false)
    let hi = d / b * ((a + 1.0f64) / c) * nb.qf(al, 2.0f64 * (a + 1.0f64), 2.0f64 * c, false, false)
    ret (est, lo, hi)
}

// the attributable rate (a / b - c / d) units with its Wald interval
fn ct_arate(a: f64, b: f64, c: f64, d: f64, level: f64, units: f64) -> (f64, f64, f64) {
    let z = z_of(level)
    let est = (a / b - c / d) * units
    let se = math.sqrt[f64](a / (b * b) + c / (d * d)) * units
    ret (est, est - z * se, est + z * se)
}

// the attributable fraction in the exposed from the exact rate-ratio interval: (IRR - 1) / IRR at the estimate and both ends
fn ct_afrate(a: f64, b: f64, c: f64, d: f64, level: f64) -> (f64, f64, f64) {
    let (e, l, u) = ct_irr(a, b, c, d, level)
    ret ((e - 1.0f64) / e, (l - 1.0f64) / l, (u - 1.0f64) / u)
}

// the population attributable rate (M1 / M0 - c / d) units with its Wald interval, M1 = a + c and M0 = b + d
fn ct_parate(a: f64, b: f64, c: f64, d: f64, level: f64, units: f64) -> (f64, f64, f64) {
    let z = z_of(level)
    let m1 = a + c
    let m0 = b + d
    let est = (m1 / m0 - c / d) * units
    let se = math.sqrt[f64](m1 / (m0 * m0) + c / (d * d)) * units
    ret (est, est - z * se, est + z * se)
}

// the population attributable fraction (Sullivan): (rate of the population - rate of the unexposed) / rate of the population, the bounds the min and max of the two limit ratios over
// the exact (chi-squared) intervals of the two rates
fn ct_pafrate(a: f64, b: f64, c: f64, d: f64, level: f64) -> (f64, f64, f64) {
    let (pe, pl, pu) = conf_inc_rate(a + c, b + d, level, false)
    let (oe, ol, ou) = conf_inc_rate(c, d, level, false)
    let r1 = (pl - ol) / pl
    let r2 = (pu - ou) / pu
    ret ((pe - oe) / pe, math.min[f64](r1, r2), math.max[f64](r1, r2))
}

// the case-control population attributable fraction epi.2by2 reports (PAFest): (odds of the population - odds of the second row) / odds of the population, with the qbinom odds intervals of
// `conf_odds` for the totals (a + c over b + d) and for the row (c over d), the bounds the min and max of the two limit ratios
fn paf_est(a: f64, b: f64, c: f64, d: f64, level: f64) -> (f64, f64, f64) {
    let (pe, pl, pu) = conf_odds(a + c, b + d, level)
    let (oe, ol, ou) = conf_odds(c, d, level)
    let r1 = (pl - ol) / pl
    let r2 = (pu - ou) / pu
    ret ((pe - oe) / pe, math.min[f64](r1, r2), math.max[f64](r1, r2))
}

// epiR zRRscore for every table: the cubic of `rr_score` for the interior and the cases it names (a zero count, or a whole row), and the two 1.0001-step searches of the original for the
// tables with a full unexposed or exposed row (c = N0 or a = N1); (est, lower, upper) with 1 / 0 for the infinite end
fn rr_score_all(t: Table2, level: f64) -> (f64, f64, f64) {
    let inf = 1.0f64 / 0.0f64
    let z = z_of(level)
    let a = t.a
    let c = t.c
    let n1 = t.a + t.b
    let n0 = t.c + t.d
    let est = (a / n1) / (c / n0)
    if c == 0.0f64 && a == 0.0f64 { ret (est, 0.0f64, inf) }
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
    let fl = (1.0f64 - (n1 - a) * (1.0f64 - p0low) / (c + n1 - (n0 + n1) * p0low)) / p0low
    let fu = (1.0f64 - (n1 - a) * (1.0f64 - p0up) / (c + n1 - (n0 + n1) * p0up)) / p0up
    if c == 0.0f64 && a != 0.0f64 { ret (est, fl, inf) }
    if c != n0 && a == 0.0f64 { ret (est, 0.0f64, fu) }
    if c == n0 && a == n1 { ret (est, n1 / (n1 + z2), (n0 + z2) / n0) }
    if a == n1 || c == n0 {
        var ll = 0.0f64
        if c == n0 && a != 0.0f64 {
            let x1 = a
            let nn1 = n1
            let x2 = c
            let nn2 = n0
            let phat1 = x2 / nn2
            let phat2 = x1 / nn1
            let phihat = phat2 / phat1
            var phil = level * phihat
            var chiv = 0.0f64
            var it = 0usize
            while chiv <= z && it < 200000usize {
                let aa = (nn2 + nn1) * phil
                let bb = 0.0f64 - ((x2 + nn1) * phil + x1 + nn2)
                let cc = x2 + x1
                let p1hat = (0.0f64 - bb - math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)) / (2.0f64 * aa)
                let p2hat = p1hat * phil
                let q2hat = 1.0f64 - p2hat
                let vr = (nn2 * nn1 * p2hat) / (nn1 * (phil - p2hat) + nn2 * q2hat)
                chiv = ((x1 - nn1 * p2hat) / q2hat) / math.sqrt[f64](vr)
                ll = phil
                phil = ll / 1.0001f64
                it += 1usize
            }
        }
        var i = c
        var j = a
        var ni = n0
        var nj = n1
        if a == n1 {
            i = a
            j = c
            ni = n1
            nj = n0
        }
        let phat1 = i / ni
        let phat2 = j / nj
        let phihat = phat2 / phat1
        var phiu = 1.1f64 * phihat
        if c == n0 && a == 0.0f64 {
            if n0 < 100.0f64 { phiu = 0.01f64 } else { phiu = 0.001f64 }
        }
        var chi1 = 0.0f64
        var phiu1 = phiu
        var it2 = 0usize
        while chi1 >= 0.0f64 - z && it2 < 200000usize {
            let aa = (ni + nj) * phiu
            let bb = 0.0f64 - ((i + nj) * phiu + j + ni)
            let cc = i + j
            let p1hat = (0.0f64 - bb - math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)) / (2.0f64 * aa)
            let p2hat = p1hat * phiu
            let q2hat = 1.0f64 - p2hat
            let vr = (ni * nj * p2hat) / (nj * (phiu - p2hat) + ni * q2hat)
            chi1 = ((j - nj * p2hat) / q2hat) / math.sqrt[f64](vr)
            phiu1 = phiu
            phiu = 1.0001f64 * phiu1
            it2 += 1usize
        }
        if a == n1 { ret (est, 1.0f64 / phiu1, fu) }
        ret (est, ll, phiu1)
    }
    ret (est, fl, fu)
}

// epiR zORscore for every table (x1 = a, n1 = a + b, x2 = c, n2 = c + d): the interior walk of `or_score` and the boundary rules (a zero count or a full row): both ends 0 and Inf for a
// pair of empty or full rows, lower 0 and a search from 0.01 / n2 when x1 = 0 or x2 = n2, upper Inf and a search from 100 n1 when x1 = n1 or x2 = 0; (est, lower, upper)
fn or_score_all(t: Table2, level: f64) -> (f64, f64, f64) {
    let inf = 1.0f64 / 0.0f64
    let x1 = t.a
    let n1 = t.a + t.b
    let x2 = t.c
    let n2 = t.c + t.d
    let est = (t.a / t.b) / (t.c / t.d)
    if (x1 == 0.0f64 && x2 == 0.0f64) || (x1 == n1 && x2 == n2) { ret (est, 0.0f64, inf) }
    if x1 == 0.0f64 || x2 == n2 {
        let ul = or_zlimit(x1, n1, x2, n2, level, 0.01f64 / n2, true)
        ret (est, 0.0f64, ul)
    }
    if x1 == n1 || x2 == 0.0f64 {
        let ll = or_zlimit(x1, n1, x2, n2, level, 100.0f64 * n1, false)
        ret (est, ll, inf)
    }
    let px = x1 / n1
    let py = x2 / n2
    let base = px / (1.0f64 - px) / (py / (1.0f64 - py))
    let lo = or_zlimit(x1, n1, x2, n2, level, base / 1.1f64, false)
    let hi = or_zlimit(x1, n1, x2, n2, level, base * 1.1f64, true)
    ret (est, lo, hi)
}

// the two inner roots of the cubic of the score risk-ratio interval for x of m and y of n (p0 low and up)
fn koop_p0(x: f64, y: f64, m: f64, n: f64, z: f64) -> (f64, f64) {
    let z2 = z * z
    let a1 = n * (n * (n + m) * x + m * (n + x) * z2)
    let a2 = 0.0f64 - n * (n * m * (y + x) + 2.0f64 * (n + m) * y * x + m * (n + y + 2.0f64 * x) * z2)
    let a3 = 2.0f64 * n * m * y * (y + x) + (n + m) * y * y * x + n * m * (y + x) * z2
    let a4 = 0.0f64 - m * y * y * (y + x)
    let b1 = a2 / a1
    let b2 = a3 / a1
    let b3 = a4 / a1
    let c1 = b2 - b1 * b1 / 3.0f64
    let c2 = b3 - b1 * b2 / 3.0f64 + 2.0f64 * b1 * b1 * b1 / 27.0f64
    let ceta = math.acos[f64](math.sqrt[f64](27.0f64) * c2 / (2.0f64 * c1 * math.sqrt[f64](0.0f64 - c1)))
    let pi = 3.141592653589793f64
    let s = 2.0f64 * math.sqrt[f64](0.0f64 - c1 / 3.0f64)
    let p01 = 0.0f64 - s * math.cos[f64](pi / 3.0f64 - ceta / 3.0f64) - b1 / 3.0f64
    let p02 = 0.0f64 - s * math.cos[f64](pi / 3.0f64 + ceta / 3.0f64) - b1 / 3.0f64
    let p03 = s * math.cos[f64](ceta / 3.0f64) - b1 / 3.0f64
    let up = math.min[f64](p01, math.min[f64](p02, p03))
    let low = p01 + p02 + p03 - up - math.max[f64](p01, math.max[f64](p02, p03))
    ret (low, up)
}

type KoopCtx0 = struct { m: f64, n: f64, x2: f64 }

fn koop_u0(c: *KoopCtx0, a: f64) -> f64 {
    if a <= 1.0f64 { ret c.m * (1.0f64 - a) / a - c.x2 }
    ret c.n * (a - 1.0f64) - c.x2
}

// epiR zRRkoopman for every table, following its sequential branches (each later branch overwrites the earlier ends): the uniroot brackets, the closed forms from the cubic, and
// the 1.0001-step searches; the table is read as in `rr_koopman` (x = a, m = a + c, y = b, n = b + d); (est, lower, upper)
fn rr_koopman_all(t: Table2, level: f64) -> (f64, f64, f64) {
    let inf = 1.0f64 / 0.0f64
    let z = z_of(level)
    let x = t.a
    let m = t.a + t.c
    let y = t.b
    let n = t.b + t.d
    let x2 = nm.qchisq(level, 1.0f64, true, false)
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    if x == 0.0f64 && y == 0.0f64 { ret (0.0f64, 0.0f64, inf) }
    let (p0low, p0up) = koop_p0(x, y, m, n, z)
    var c = KoopCtx { m: m, n: n, x: x, y: y, x2: x2 }
    var c0 = KoopCtx0 { m: m, n: n, x2: x2 }
    let est = (x / m) / (y / n)
    var nrat = est
    var varhat = 1.0f64 / x - 1.0f64 / m + 1.0f64 / y - 1.0f64 / n
    if x == 0.0f64 && y != 0.0f64 {
        nrat = ((x + 0.5f64) / m) / (y / n)
        varhat = 1.0f64 / (x + 0.5f64) - 1.0f64 / m + 1.0f64 / y - 1.0f64 / n
    }
    if y == 0.0f64 && x != 0.0f64 {
        nrat = (x / m) / ((y + 0.5f64) / n)
        varhat = 1.0f64 / x - 1.0f64 / m + 1.0f64 / (y + 0.5f64) - 1.0f64 / n
    }
    if y == n && x == m {
        nrat = 1.0f64
        varhat = 1.0f64 / (m - 0.5f64) - 1.0f64 / m + 1.0f64 / (n - 0.5f64) - 1.0f64 / n
    }
    let la = nrat * math.exp[f64](0.0f64 - z * math.sqrt[f64](varhat)) / 4.0f64
    let lb = nrat
    let ha = nrat
    let hb = nrat * math.exp[f64](z * math.sqrt[f64](varhat)) * 4.0f64
    var lower = 0.0f64
    var upper = 0.0f64
    if x != 0.0f64 && y == 0.0f64 {
        if x == m {
            lower = (1.0f64 - (m - x) * (1.0f64 - p0low) / (y + m - (n + m) * p0low)) / p0low
            upper = inf
        } else {
            lower = pw.zeroin[KoopCtx](&c, koop_u, la, lb, tol, 1000i64)
            upper = inf
        }
    }
    if x == 0.0f64 && y != n {
        upper = pw.zeroin[KoopCtx](&c, koop_u, ha, hb, tol, 1000i64)
        lower = 0.0f64
    }
    if (x == m || y == n) && y != 0.0f64 {
        if x == m && y == n {
            lower = pw.zeroin[KoopCtx0](&c0, koop_u0, la, est, tol, 1000i64)
            upper = pw.zeroin[KoopCtx0](&c0, koop_u0, est, hb, tol, 1000i64)
        }
        if x == m && y != n {
            let phihat = (y / n) / (x / m)
            var phiu = 1.1f64 * phihat
            var r = 0.0f64
            var phiu1 = phiu
            var it = 0usize
            while r >= 0.0f64 - z && it < 200000usize {
                let aa = (m + n) * phiu
                let bb = 0.0f64 - ((x + n) * phiu + y + m)
                let cc = x + y
                let p1hat = (0.0f64 - bb - math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)) / (2.0f64 * aa)
                let p2hat = p1hat * phiu
                let q2hat = 1.0f64 - p2hat
                let vr = (m * n * p2hat) / (n * (phiu - p2hat) + m * q2hat)
                r = ((y - n * p2hat) / q2hat) / math.sqrt[f64](vr)
                phiu1 = phiu
                phiu = 1.0001f64 * phiu1
                it += 1usize
            }
            upper = (1.0f64 - (m - x) * (1.0f64 - p0up) / (y + m - (n + m) * p0up)) / p0up
            lower = 1.0f64 / phiu1
        }
        if y == n && x != m {
            let phihat = (x / m) / (y / n)
            var phil = 0.95f64 * phihat
            var r = 0.0f64
            if x != 0.0f64 {
                var it = 0usize
                while r <= z && it < 200000usize {
                    let aa = (n + m) * phil
                    let bb = 0.0f64 - ((y + m) * phil + x + n)
                    let cc = y + x
                    let p1hat = (0.0f64 - bb - math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)) / (2.0f64 * aa)
                    let p2hat = p1hat * phil
                    let q2hat = 1.0f64 - p2hat
                    let vr = (n * m * p2hat) / (m * (phil - p2hat) + n * q2hat)
                    r = ((x - m * p2hat) / q2hat) / math.sqrt[f64](vr)
                    lower = phil
                    phil = lower / 1.0001f64
                    it += 1usize
                }
            }
            var phiu = 1.1f64 * phihat
            if x == 0.0f64 {
                lower = 0.0f64
                if n < 100.0f64 { phiu = 0.01f64 } else { phiu = 0.001f64 }
            }
            r = 0.0f64
            var phiu1 = phiu
            var it2 = 0usize
            while r >= 0.0f64 - z && it2 < 200000usize {
                let aa = (n + m) * phiu
                let bb = 0.0f64 - ((y + m) * phiu + x + n)
                let cc = y + x
                let p1hat = (0.0f64 - bb - math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)) / (2.0f64 * aa)
                let p2hat = p1hat * phiu
                let q2hat = 1.0f64 - p2hat
                let vr = (n * m * p2hat) / (m * (phiu - p2hat) + n * q2hat)
                r = ((x - m * p2hat) / q2hat) / math.sqrt[f64](vr)
                phiu1 = phiu
                phiu = 1.0001f64 * phiu1
                it2 += 1usize
            }
            upper = phiu1
        }
    } else if y != n && x != m && x != 0.0f64 && y != 0.0f64 {
        lower = pw.zeroin[KoopCtx](&c, koop_u, la, lb, tol, 1000i64)
        upper = pw.zeroin[KoopCtx](&c, koop_u, ha, hb, tol, 1000i64)
    }
    ret (est, lower, upper)
}
