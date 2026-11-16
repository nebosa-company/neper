// R metafor escalc for the common effect sizes with their large-sample sampling variances: MD (raw mean difference), SMD (Hedges' g), ROM (log ratio of means with metafor's small-sample bias term),
// RR (log risk ratio), OR (log odds ratio), RD (risk difference), COR (raw correlation) and ZCOR (Fisher's z). No continuity correction is applied (add = 0 behaviour
// for tables without zero cells).
//
// Not here: the other measures, the zero-cell correction, the other variance types and the SMD with the unbiased variance estimator.

use e.math
use e.math.special as sp

// the measure and the part (0 yi, 1 vi); a, b, c, d are the four inputs of the measure in the package's argument order
// 0 MD (m1, m2, sd1, sd2, n1, n2), 1 SMD (same), 2 ROM (same), 3 RR (ai, bi, ci, di), 4 OR, 5 RD, 6 COR (ri, ni), 7 ZCOR
fn effect(measure: usize, part: usize, v: []const f64) -> f64 {
    if measure <= 2usize {
        let m1 = v[0usize]
        let m2 = v[1usize]
        let s1 = v[2usize]
        let s2 = v[3usize]
        let n1 = v[4usize]
        let n2 = v[5usize]
        if measure == 0usize {
            if part == 0usize { ret m1 - m2 }
            ret s1 * s1 / n1 + s2 * s2 / n2
        }
        if measure == 1usize {
            let df = n1 + n2 - 2.0f64
            let sp2 = ((n1 - 1.0f64) * s1 * s1 + (n2 - 1.0f64) * s2 * s2) / df
            let d = (m1 - m2) / math.sqrt[f64](sp2)
            let j = math.exp[f64](sp.lgamma(df / 2.0f64) - math.log[f64](math.sqrt[f64](df / 2.0f64)) - sp.lgamma((df - 1.0f64) / 2.0f64))
            let g = j * d
            if part == 0usize { ret g }
            ret 1.0f64 / n1 + 1.0f64 / n2 + g * g / (2.0f64 * (n1 + n2))
        }
        if part == 0usize { ret math.log[f64](m1 / m2) + 0.5f64 * (s1 * s1 / (n1 * m1 * m1) - s2 * s2 / (n2 * m2 * m2)) }
        ret s1 * s1 / (n1 * m1 * m1) + s2 * s2 / (n2 * m2 * m2)
    }
    if measure <= 5usize {
        let ai = v[0usize]
        let bi = v[1usize]
        let ci = v[2usize]
        let di = v[3usize]
        let n1 = ai + bi
        let n2 = ci + di
        if measure == 3usize {
            if part == 0usize { ret math.log[f64]((ai / n1) / (ci / n2)) }
            ret 1.0f64 / ai - 1.0f64 / n1 + 1.0f64 / ci - 1.0f64 / n2
        }
        if measure == 4usize {
            if part == 0usize { ret math.log[f64](ai * di / (bi * ci)) }
            ret 1.0f64 / ai + 1.0f64 / bi + 1.0f64 / ci + 1.0f64 / di
        }
        if part == 0usize { ret ai / n1 - ci / n2 }
        ret ai * bi / (n1 * n1 * n1) + ci * di / (n2 * n2 * n2)
    }
    let r = v[0usize]
    let n = v[1usize]
    if measure == 6usize {
        if part == 0usize { ret r }
        ret (1.0f64 - r * r) * (1.0f64 - r * r) / (n - 1.0f64)
    }
    if part == 0usize { ret 0.5f64 * math.log[f64]((1.0f64 + r) / (1.0f64 - r)) }
    ret 1.0f64 / (n - 3.0f64)
}
