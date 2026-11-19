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
