// R metafor escalc for the 2x2 table, two-group, correlation, proportion, incidence-rate and single-mean measures, with the continuity correction (add, to = none, all, only0, if0all),
// drop00, the sampling variance types, and the small-sample correction of the standardised mean difference. Rows are studies; a missing value is NaN and stays NaN.
//
// measure: 0 RR 1 OR 2 RD 3 AS 4 PETO 5 PHI 6 ZPHI 7 YUQ 8 YUY 9 PBIT 10 OR2D 11 OR2DN 12 OR2DL (columns ai bi ci di)
//   20 MD 21 SMD 22 SMDH 23 SMD1 24 SMD1H 25 ROM 26 RPB 27 ZPB 28 D2OR 29 VR 30 CVR 31 D2ORN (columns m1i m2i sd1i sd2i n1i n2i)
//   40 IRR 41 IRD 42 IRSD (x1i x2i t1i t2i)   50 COR 51 ZCOR (ri ni)   60 PR 61 PLN 62 PLO 63 PRZ 64 PAS 65 PFT (xi mi)   70 IR 71 IRLN 72 IRS 73 IRFT (xi ti)
//   80 MN 81 SMN 82 MNLN 83 SDLN 84 CVLN (mi sdi ni)
// vtype: 0 the measure's default (LS), 1 UB, 2 AV, 3 H0, 4 HO, 5 LS2, 6 LS3, 7 CS, 9 AVHO
//
// Not here: the correlation corrections that need the hypergeometric function (UCOR), RTET and ZTET, the partial correlations, the paired-sample measures, ICC, R2 and the alpha measures.

use e.math
use e.math.dist as dist
use e.math.special as sp

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pi_c() -> f64 { ret 3.141592653589793f64 }

// the small-sample correction factor of Hedges (exact gamma form), or 1 when correct is false
fn cmi_of(mi: f64, correct: bool) -> f64 {
    if !correct { ret 1.0f64 }
    if mi <= 1.0f64 { ret nan() }
    ret math.exp[f64](sp.lgamma(mi / 2.0f64) - math.log[f64](math.sqrt[f64](mi / 2.0f64)) - sp.lgamma((mi - 1.0f64) / 2.0f64))
}

// the weighted mean of x with weights w over the rows where neither is NaN
fn wmean(x: []const f64, w: []const f64, k: usize) -> f64 {
    var sx = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < k {
        if x[i] == x[i] && w[i] == w[i] {
            sx += x[i] * w[i]
            sw += w[i]
        }
        i += 1usize
    }
    ret sx / sw
}

fn at(d: []const f64, ncol: usize, i: usize, j: usize) -> f64 { ret d[i * ncol + j] }

// escalc: the effects, with infinite and NaN values (either of yi and vi) recoded to NaN in both and a negative variance to NaN
fn escalc(measure: usize, vtype: usize, add: f64, to: usize, drop00: bool, correct: bool, k: usize, ncol: usize, d: []const f64, yi: []f64, vi: []f64, scratch: []f64) {
    escalc_raw(measure, vtype, add, to, drop00, correct, k, ncol, d, yi, vi, scratch)
    var i = 0usize
    while i < k {
        var bad = yi[i] - yi[i] != 0.0f64 || vi[i] - vi[i] != 0.0f64
        // a dropped 0/0 row has an NA effect but keeps its variance when that depends on the person-times only
        if measure == 42usize && drop00 && at(d, ncol, i, 0usize) == 0.0f64 && at(d, ncol, i, 1usize) == 0.0f64 {
            bad = false
            yi[i] = nan()
        }
        if bad {
            yi[i] = nan()
            vi[i] = nan()
        }
        if vi[i] < 0.0f64 { vi[i] = nan() }
        i += 1usize
    }
}

// escalc: d is k rows of ncol columns; yi and vi receive the k effects and variances. scratch needs 6 k values
fn escalc_raw(measure: usize, vtype: usize, add: f64, to: usize, drop00: bool, correct: bool, k: usize, ncol: usize, d: []const f64, yi: []f64, vi: []f64, scratch: []f64) {
    var i = 0usize
    // working copies of up to four count columns (the unadjusted values are the d itself)
    if measure <= 12usize || (measure >= 120usize && measure <= 124usize) {
        let p1u = scratch[0usize..k]
        let p2u = scratch[k..2usize * k]
        var any0 = false
        i = 0usize
        while i < k {
            let a0 = at(d, ncol, i, 0usize)
            let b0 = at(d, ncol, i, 1usize)
            let c0 = at(d, ncol, i, 2usize)
            let d0 = at(d, ncol, i, 3usize)
            if a0 == 0.0f64 || b0 == 0.0f64 || c0 == 0.0f64 || d0 == 0.0f64 { any0 = true }
            i += 1usize
        }
        var s1 = 0.0f64
        var s1n = 0.0f64
        var s2 = 0.0f64
        var s2n = 0.0f64
        i = 0usize
        while i < k {
            var a = at(d, ncol, i, 0usize)
            var b = at(d, ncol, i, 1usize)
            var c = at(d, ncol, i, 2usize)
            var dd = at(d, ncol, i, 3usize)
            if drop00 && ((a == 0.0f64 && c == 0.0f64) || (b == 0.0f64 && dd == 0.0f64)) {
                a = nan()
                b = nan()
                c = nan()
                dd = nan()
            }
            let au = a
            let bu = b
            let cu = c
            let du = dd
            let z = a == 0.0f64 || b == 0.0f64 || c == 0.0f64 || dd == 0.0f64
            var adj = false
            if to == 1usize { adj = true }
            if to == 2usize && z { adj = true }
            if to == 3usize && any0 { adj = true }
            if adj {
                a = a + add
                b = b + add
                c = c + add
                dd = dd + add
            }
            let n1 = a + b
            let n2 = c + dd
            let ni = n1 + n2
            let p1 = a / n1
            let p2 = c / n2
            let n1u = au + bu
            let n2u = cu + du
            // the unadjusted proportions are what the effect uses when no correction is applied: addyi and addvi are both TRUE here, so the adjusted values are used throughout
            var y = nan()
            var v = nan()
            if measure == 0usize {
                y = math.log[f64](p1) - math.log[f64](p2)
                v = 1.0f64 / a - 1.0f64 / n1 + 1.0f64 / c - 1.0f64 / n2
            }
            if measure == 1usize || (measure >= 10usize && measure <= 12usize) {
                y = math.log[f64](p1 / (1.0f64 - p1)) - math.log[f64](p2 / (1.0f64 - p2))
                v = 1.0f64 / a + 1.0f64 / b + 1.0f64 / c + 1.0f64 / dd
                if measure == 10usize || measure == 12usize {
                    y = math.sqrt[f64](3.0f64) / pi_c() * y
                    v = 3.0f64 / (pi_c() * pi_c()) * v
                }
                if measure == 11usize {
                    y = y / 1.65f64
                    v = v / (1.65f64 * 1.65f64)
                }
            }
            if measure == 2usize {
                y = p1 - p2
                if vtype == 1usize { v = p1 * (1.0f64 - p1) / (n1 - 1.0f64) + p2 * (1.0f64 - p2) / (n2 - 1.0f64) } else { v = p1 * (1.0f64 - p1) / n1 + p2 * (1.0f64 - p2) / n2 }
            }
            if measure == 3usize {
                y = math.asin[f64](math.sqrt[f64](p1)) - math.asin[f64](math.sqrt[f64](p2))
                v = 1.0f64 / (4.0f64 * n1) + 1.0f64 / (4.0f64 * n2)
            }
            if measure == 4usize {
                let xt = a + c
                let yt = b + dd
                let ei = xt * n1 / ni
                let vv = xt * yt * (n1 / ni) * (n2 / ni) / (ni - 1.0f64)
                y = (a - ei) / vv
                v = 1.0f64 / vv
            }
            if measure == 5usize || measure == 6usize {
                y = (a * dd - b * c) / math.sqrt[f64]((a + b) * (c + dd) * (a + c) * (b + dd))
                let p1d = (a + b) / ni
                let p2d = (c + dd) / ni
                let q1d = (a + c) / ni
                let q2d = (b + dd) / ni
                v = 1.0f64 / ni * (1.0f64 - y * y + y * (1.0f64 + 0.5f64 * y * y) * (p1d - p2d) * (q1d - q2d) / math.sqrt[f64](p1d * p2d * q1d * q2d) - 0.75f64 * y * y * ((p1d - p2d) * (p1d - p2d) / (p1d * p2d) + (q1d - q2d) * (q1d - q2d) / (q1d * q2d)))
                if measure == 6usize {
                    var y2 = y * y
                    if y2 > 1.0f64 { y2 = 1.0f64 }
                    v = v / ((1.0f64 - y2) * (1.0f64 - y2))
                    y = 0.5f64 * math.log[f64]((1.0f64 + y) / (1.0f64 - y))
                }
            }
            if measure == 7usize {
                let q = (a / b) / (c / dd)
                y = (q - 1.0f64) / (q + 1.0f64)
                v = 0.25f64 * (1.0f64 - y * y) * (1.0f64 - y * y) * (1.0f64 / a + 1.0f64 / b + 1.0f64 / c + 1.0f64 / dd)
            }
            if measure == 8usize {
                let q = (a / b) / (c / dd)
                y = (math.sqrt[f64](q) - 1.0f64) / (math.sqrt[f64](q) + 1.0f64)
                v = 1.0f64 / 16.0f64 * (1.0f64 - y * y) * (1.0f64 - y * y) * (1.0f64 / a + 1.0f64 / b + 1.0f64 / c + 1.0f64 / dd)
            }
            if measure == 9usize {
                let z1 = dist.qnorm(p1, 0.0f64, 1.0f64, true, false)
                let z2 = dist.qnorm(p2, 0.0f64, 1.0f64, true, false)
                y = z1 - z2
                v = 2.0f64 * pi_c() * p1 * (1.0f64 - p1) * math.exp[f64](z1 * z1) / n1 + 2.0f64 * pi_c() * p2 * (1.0f64 - p2) * math.exp[f64](z2 * z2) / n2
            }
            if measure >= 120usize {
                // the matched-pair measures: pi12 = b / n, pi21 = c / n, the marginal proportions of the pairs
                let p12 = b / ni
                let p21 = c / ni
                let m1 = (a + b) / ni
                let m2 = (a + c) / ni
                if measure == 120usize {
                    y = m1 - m2
                    v = p12 * (1.0f64 - p12) / ni + 2.0f64 * p12 * p21 / ni + p21 * (1.0f64 - p21) / ni
                }
                if measure == 121usize {
                    y = math.log[f64](m1) - math.log[f64](m2)
                    v = (p12 + p21) / (ni * m1 * m2)
                }
                if measure == 122usize {
                    y = math.log[f64](m1 / (1.0f64 - m1)) - math.log[f64](m2 / (1.0f64 - m2))
                    v = (p12 * (1.0f64 - p12) + p21 * (1.0f64 - p21) + 2.0f64 * p12 * p21) / (ni * m1 * (1.0f64 - m1) * m2 * (1.0f64 - m2))
                }
                if measure == 123usize {
                    y = math.log[f64](b) - math.log[f64](c)
                    v = 1.0f64 / b + 1.0f64 / c
                }
                if measure == 124usize {
                    let ei = (b + c) / 2.0f64
                    let vv = (b + c) / 4.0f64
                    y = (b - ei) / vv
                    v = 1.0f64 / vv
                }
            }
            yi[i] = y
            vi[i] = v
            p1u[i] = p1
            p2u[i] = p2
            // weighted means of the proportions for the average variance types
            if p1 == p1 && n1 == n1 {
                s1 += p1 * n1
                s1n += n1
            }
            if p2 == p2 && n2 == n2 {
                s2 += p2 * n2
                s2n += n2
            }
            let _ = n1u
            let _ = n2u
            i += 1usize
        }
        if vtype == 2usize || vtype == 3usize {
            // AV and H0 for RR, OR and RD recomputed from the group totals
            let m1 = s1 / s1n
            let m2 = s2 / s2n
            i = 0usize
            while i < k {
                var a = at(d, ncol, i, 0usize)
                var b = at(d, ncol, i, 1usize)
                var c = at(d, ncol, i, 2usize)
                var dd = at(d, ncol, i, 3usize)
                let z = a == 0.0f64 || b == 0.0f64 || c == 0.0f64 || dd == 0.0f64
                var adj = false
                if to == 1usize { adj = true }
                if to == 2usize && z { adj = true }
                if to == 3usize && any0 { adj = true }
                if adj {
                    a = a + add
                    b = b + add
                    c = c + add
                    dd = dd + add
                }
                let n1 = a + b
                let n2 = c + dd
                let pp = (a + c) / (n1 + n2)
                if measure == 0usize {
                    if vtype == 2usize { vi[i] = (1.0f64 - m1) / (m1 * n1) + (1.0f64 - m2) / (m2 * n2) } else { vi[i] = (1.0f64 - pp) / pp * (1.0f64 / n1 + 1.0f64 / n2) }
                }
                if measure == 1usize {
                    if vtype == 2usize { vi[i] = 1.0f64 / (m1 * (1.0f64 - m1) * n1) + 1.0f64 / (m2 * (1.0f64 - m2) * n2) } else { vi[i] = 1.0f64 / (pp * (1.0f64 - pp)) * (1.0f64 / n1 + 1.0f64 / n2) }
                }
                if measure == 2usize {
                    if vtype == 2usize { vi[i] = m1 * (1.0f64 - m1) / n1 + m2 * (1.0f64 - m2) / n2 } else { vi[i] = (1.0f64 / n1 + 1.0f64 / n2) * pp * (1.0f64 - pp) }
                }
                i += 1usize
            }
        }
        ret
    }
    if measure >= 100usize && measure <= 109usize {
        // paired means (m1i m2i sd1i sd2i ni ri): 100 MC, 101 SMCC, 103 SMCRH, 104 SMCRP, 105 SMCRPH, 106 CLESCN, 107 ROMC, 108 VRC, 109 CVRC
        i = 0usize
        while i < k {
            let m1 = at(d, ncol, i, 0usize)
            let m2 = at(d, ncol, i, 1usize)
            let s1 = at(d, ncol, i, 2usize)
            let s2 = at(d, ncol, i, 3usize)
            let n = at(d, ncol, i, 4usize)
            let r = at(d, ncol, i, 5usize)
            let mi = n - 1.0f64
            let sdd = math.sqrt[f64](s1 * s1 + s2 * s2 - 2.0f64 * r * s1 * s2)
            let sdp = math.sqrt[f64]((s1 * s1 + s2 * s2) / 2.0f64)
            var y = nan()
            var v = nan()
            if measure == 100usize {
                y = m1 - m2
                v = sdd * sdd / n
            }
            if measure == 101usize {
                let cm = cmi_of(mi, correct)
                let dv = (m1 - m2) / sdd
                y = cm * dv
                if vtype == 0usize { v = 1.0f64 / n + y * y / (2.0f64 * n) }
                if vtype == 5usize { v = cm * cm * (1.0f64 / n + dv * dv / (2.0f64 * n)) }
                if vtype == 1usize { v = 1.0f64 / n + (1.0f64 - (mi - 2.0f64) / (mi * cm * cm)) * y * y }
                if vtype == 3usize {
                    if mi > 2.0f64 { v = cm * cm / n * mi / (mi - 2.0f64) }
                }
            }
            if measure == 103usize {
                let cm = cmi_of(mi, correct)
                let dv = (m1 - m2) / s1
                y = cm * dv
                if vtype == 5usize { v = sdd * sdd / (s1 * s1 * n) + y * y / (2.0f64 * n) } else { v = sdd * sdd / (s1 * s1 * (n - 1.0f64)) + y * y / (2.0f64 * (n - 1.0f64)) }
            }
            if measure == 104usize || measure == 105usize {
                let mp = 2.0f64 * (n - 1.0f64) / (1.0f64 + r * r)
                let cm = cmi_of(mp, correct)
                y = cm * (m1 - m2) / sdp
                if measure == 104usize { v = 2.0f64 * (1.0f64 - r) / n + y * y * (1.0f64 + r * r) / (4.0f64 * n) }
                if measure == 105usize {
                    let q = (s1 * s1 * s1 * s1 + s2 * s2 * s2 * s2 + 2.0f64 * r * r * s1 * s1 * s2 * s2)
                    if vtype == 5usize { v = sdd * sdd / (sdp * sdp * n) + y * y * q / (8.0f64 * sdp * sdp * sdp * sdp * n) } else { v = sdd * sdd / (sdp * sdp * (n - 1.0f64)) + y * y * q / (8.0f64 * sdp * sdp * sdp * sdp * (n - 1.0f64)) }
                }
            }
            if measure == 106usize {
                let dv = (m1 - m2) / sdp
                y = dist.pnorm(dv / math.sqrt[f64](2.0f64), 0.0f64, 1.0f64, true, false)
                v = math.exp[f64](0.0f64 - dv * dv / 2.0f64) / (4.0f64 * pi_c()) * (sdd * sdd / (sdp * sdp * (n - 1.0f64)) + dv * dv * (s1 * s1 * s1 * s1 + s2 * s2 * s2 * s2 + 2.0f64 * r * r * s1 * s1 * s2 * s2) / (8.0f64 * sdp * sdp * sdp * sdp * (n - 1.0f64)))
            }
            if measure == 107usize {
                if correct { y = math.log[f64](m1 / m2) + 0.5f64 * (s1 * s1 / (n * m1 * m1) - s2 * s2 / (n * m2 * m2)) } else { y = math.log[f64](m1 / m2) }
                v = s1 * s1 / (n * m1 * m1) + s2 * s2 / (n * m2 * m2) - 2.0f64 * r * s1 * s2 / (m1 * m2 * n)
                if vtype == 5usize { v = v + s1 * s1 * s1 * s1 / (2.0f64 * n * n * m1 * m1 * m1 * m1) + s2 * s2 * s2 * s2 / (2.0f64 * n * n * m2 * m2 * m2 * m2) - r * r * s1 * s1 * s2 * s2 / (n * n * m1 * m1 * m2 * m2) }
            }
            if measure == 108usize {
                y = math.log[f64](s1 / s2)
                if vtype == 5usize { v = (1.0f64 - r * r) / (n - 1.0f64) + (1.0f64 - r * r * r * r) / ((n - 1.0f64) * (n - 1.0f64)) } else { v = (1.0f64 - r * r) / (n - 1.0f64) }
            }
            if measure == 109usize {
                if correct { y = math.log[f64](s1 / m1) - math.log[f64](s2 / m2) + 0.5f64 * (s2 * s2 / (n * m2 * m2) - s1 * s1 / (n * m1 * m1)) } else { y = math.log[f64](s1 / m1) - math.log[f64](s2 / m2) }
                v = s1 * s1 / (n * m1 * m1) + s2 * s2 / (n * m2 * m2) - 2.0f64 * r * s1 * s2 / (m1 * m2 * n) + (1.0f64 - r * r) / (n - 1.0f64)
                if vtype == 5usize { v = v - (1.0f64 - r * r) / (n - 1.0f64) + s1 * s1 * s1 * s1 / (2.0f64 * n * n * m1 * m1 * m1 * m1) + s2 * s2 * s2 * s2 / (2.0f64 * n * n * m2 * m2 * m2 * m2) - r * r * s1 * s1 * s2 * s2 / (n * n * m1 * m1 * m2 * m2) + (1.0f64 - r * r) / (n - 1.0f64) + (1.0f64 - r * r * r * r) / ((n - 1.0f64) * (n - 1.0f64)) }
            }
            yi[i] = y
            vi[i] = v
            i += 1usize
        }
        ret
    }
    if measure >= 130usize && measure <= 133usize {
        // 130 ARAW, 131 AHW, 132 ABT (ai mi ni), 133 REH (ai bi ci)
        i = 0usize
        while i < k {
            let a = at(d, ncol, i, 0usize)
            let m = at(d, ncol, i, 1usize)
            let n = at(d, ncol, i, 2usize)
            if measure == 130usize {
                yi[i] = a
                vi[i] = 2.0f64 * m * (1.0f64 - a) * (1.0f64 - a) / ((m - 1.0f64) * (n - 2.0f64))
            }
            if measure == 131usize {
                yi[i] = 1.0f64 - math.pow[f64](1.0f64 - a, 1.0f64 / 3.0f64)
                vi[i] = 18.0f64 * m * (n - 1.0f64) * math.pow[f64](1.0f64 - a, 2.0f64 / 3.0f64) / ((m - 1.0f64) * (9.0f64 * n - 11.0f64) * (9.0f64 * n - 11.0f64))
            }
            if measure == 132usize {
                yi[i] = 0.0f64 - math.log[f64](1.0f64 - a)
                vi[i] = 2.0f64 * m / ((m - 1.0f64) * (n - 2.0f64))
            }
            if measure == 133usize {
                let b = m
                let c = n
                let nn = a + b + c
                let p0 = a / nn
                let p1 = b / nn
                let p2 = c / nn
                yi[i] = math.log[f64](p1) - math.log[f64](2.0f64 * math.sqrt[f64](p0 * p2))
                vi[i] = ((1.0f64 - p1) / (4.0f64 * p0 * p2) + 1.0f64 / p1) / nn
            }
            i += 1usize
        }
        ret
    }
    if measure >= 20usize && measure <= 31usize {
        var mnwy = 0.0f64
        let ys = scratch[0usize..k]
        let ns = scratch[k..2usize * k]
        var cv1 = 0.0f64
        var cv2 = 0.0f64
        var s1 = 0.0f64
        var s2 = 0.0f64
        var s1n = 0.0f64
        var s2n = 0.0f64
        var scv = 0.0f64
        var scn = 0.0f64
        i = 0usize
        while i < k {
            let m1 = at(d, ncol, i, 0usize)
            let m2 = at(d, ncol, i, 1usize)
            let s1i = at(d, ncol, i, 2usize)
            let s2i = at(d, ncol, i, 3usize)
            let n1 = at(d, ncol, i, 4usize)
            let n2 = at(d, ncol, i, 5usize)
            let ni = n1 + n2
            var mi = ni - 2.0f64
            var sdp = math.sqrt[f64](((n1 - 1.0f64) * s1i * s1i + (n2 - 1.0f64) * s2i * s2i) / mi)
            var npi = ni
            if measure == 23usize || measure == 24usize {
                mi = n2 - 1.0f64
                sdp = s2i
                npi = n2
            }
            let dval = (m1 - m2) / sdp
            let cm = cmi_of(mi, correct)
            if measure == 21usize || measure == 23usize {
                ys[i] = cm * dval
                ns[i] = ni
            }
            s1 += n1 * s1i / m1
            s1n += n1
            s2 += n2 * s2i / m2
            s2n += n2
            scv += n1 * (s1i / m1) + n2 * (s2i / m2)
            scn += ni
            let _ = cv1
            let _ = cv2
            i += 1usize
        }
        if measure == 21usize || measure == 23usize { mnwy = wmean(ys, ns, k) }
        let mn1 = s1 / s1n
        let mn2 = s2 / s2n
        let mnw = scv / scn
        i = 0usize
        while i < k {
            let m1 = at(d, ncol, i, 0usize)
            let m2 = at(d, ncol, i, 1usize)
            let s1i = at(d, ncol, i, 2usize)
            let s2i = at(d, ncol, i, 3usize)
            let n1 = at(d, ncol, i, 4usize)
            let n2 = at(d, ncol, i, 5usize)
            let ni = n1 + n2
            var mi = ni - 2.0f64
            var sdp = math.sqrt[f64](((n1 - 1.0f64) * s1i * s1i + (n2 - 1.0f64) * s2i * s2i) / mi)
            var npi = ni
            if measure == 23usize || measure == 24usize {
                mi = n2 - 1.0f64
                sdp = s2i
                npi = n2
            }
            let dval = (m1 - m2) / sdp
            let cm = cmi_of(mi, correct)
            var y = nan()
            var v = nan()
            if measure == 20usize {
                y = m1 - m2
                if vtype == 4usize { v = sdp * sdp * (1.0f64 / n1 + 1.0f64 / n2) } else { v = s1i * s1i / n1 + s2i * s2i / n2 }
            }
            if measure == 21usize || measure == 23usize {
                y = cm * dval
                if vtype == 0usize { v = 1.0f64 / n1 + 1.0f64 / n2 + y * y / (2.0f64 * npi) }
                if vtype == 5usize { v = cm * cm * (1.0f64 / n1 + 1.0f64 / n2 + dval * dval / (2.0f64 * npi)) }
                if vtype == 6usize { v = 1.0f64 / n1 + 1.0f64 / n2 + y * y / (2.0f64 * (npi - 3.94f64)) }
                if vtype == 1usize { v = 1.0f64 / n1 + 1.0f64 / n2 + (1.0f64 - (mi - 2.0f64) / (mi * cm * cm)) * y * y }
                if vtype == 2usize { v = 1.0f64 / n1 + 1.0f64 / n2 + mnwy * mnwy / (2.0f64 * npi) }
                if vtype == 3usize {
                    if mi > 2.0f64 { v = cm * cm * (1.0f64 / n1 + 1.0f64 / n2) * mi / (mi - 2.0f64) }
                }
            }
            if measure == 22usize {
                let sd2 = math.sqrt[f64]((s1i * s1i + s2i * s2i) / 2.0f64)
                y = cm * (m1 - m2) / sd2
                if vtype == 0usize { v = y * y * (s1i * s1i * s1i * s1i / (n1 - 1.0f64) + s2i * s2i * s2i * s2i / (n2 - 1.0f64)) / (8.0f64 * sd2 * sd2 * sd2 * sd2) + (s1i * s1i / (n1 - 1.0f64) + s2i * s2i / (n2 - 1.0f64)) / (sd2 * sd2) }
                if vtype == 5usize { v = s1i * s1i / (n1 * sd2 * sd2) + s2i * s2i / (n2 * sd2 * sd2) + y * y / (8.0f64 * sd2 * sd2 * sd2 * sd2) * (s1i * s1i * s1i * s1i / n1 + s2i * s2i * s2i * s2i / n2) }
                if vtype == 6usize { v = s1i * s1i / (n1 * sd2 * sd2) + s2i * s2i / (n2 * sd2 * sd2) + y * y / (8.0f64 * sd2 * sd2 * sd2 * sd2) * (s1i * s1i * s1i * s1i / (n1 - 1.0f64) + s2i * s2i * s2i * s2i / (n2 - 1.0f64)) }
            }
            if measure == 24usize {
                y = cm * dval
                v = (s1i * s1i / (s2i * s2i)) / (n1 - 1.0f64) + 1.0f64 / (n2 - 1.0f64) + y * y / (2.0f64 * (n2 - 1.0f64))
            }
            if measure == 25usize {
                if correct { y = math.log[f64](m1 / m2) + 0.5f64 * (s1i * s1i / (n1 * m1 * m1) - s2i * s2i / (n2 * m2 * m2)) } else { y = math.log[f64](m1 / m2) }
                if vtype == 0usize { v = s1i * s1i / (n1 * m1 * m1) + s2i * s2i / (n2 * m2 * m2) }
                if vtype == 4usize { v = sdp * sdp / (n1 * m1 * m1) + sdp * sdp / (n2 * m2 * m2) }
                if vtype == 2usize { v = mn1 * mn1 / n1 + mn2 * mn2 / n2 }
                if vtype == 9usize { v = mnw * mnw * (1.0f64 / n1 + 1.0f64 / n2) }
                if vtype == 5usize { v = s1i * s1i / (n1 * m1 * m1) + s2i * s2i / (n2 * m2 * m2) + s1i * s1i * s1i * s1i / (2.0f64 * n1 * n1 * m1 * m1 * m1 * m1) + s2i * s2i * s2i * s2i / (2.0f64 * n2 * n2 * m2 * m2 * m2 * m2) }
            }
            if measure == 26usize || measure == 27usize {
                let hi = mi / n1 + mi / n2
                y = dval / math.sqrt[f64](dval * dval + hi)
                if vtype == 7usize { v = (1.0f64 - y * y) * (1.0f64 - y * y) * (ni * y * y / (4.0f64 * n1 * n2) + (2.0f64 - 3.0f64 * y * y) / (2.0f64 * ni)) } else { v = hi * hi / ((hi + dval * dval) * (hi + dval * dval) * (hi + dval * dval)) * (1.0f64 / n1 + 1.0f64 / n2 + dval * dval / (2.0f64 * ni)) }
                if measure == 27usize {
                    var y2 = y * y
                    if y2 > 1.0f64 { y2 = 1.0f64 }
                    v = v / ((1.0f64 - y2) * (1.0f64 - y2))
                    y = 0.5f64 * math.log[f64]((1.0f64 + y) / (1.0f64 - y))
                }
            }
            if measure == 28usize {
                y = pi_c() / math.sqrt[f64](3.0f64) * dval
                v = pi_c() * pi_c() / 3.0f64 * (1.0f64 / n1 + 1.0f64 / n2 + dval * dval / (2.0f64 * ni))
            }
            if measure == 31usize {
                y = 1.65f64 * dval
                v = 1.65f64 * 1.65f64 * (1.0f64 / n1 + 1.0f64 / n2 + dval * dval / (2.0f64 * ni))
            }
            if measure == 29usize {
                if correct { y = math.log[f64](s1i / s2i) + 1.0f64 / (2.0f64 * (n1 - 1.0f64)) - 1.0f64 / (2.0f64 * (n2 - 1.0f64)) } else { y = math.log[f64](s1i / s2i) }
                if vtype == 5usize { v = 0.5f64 * (n1 / ((n1 - 1.0f64) * (n1 - 1.0f64)) + n2 / ((n2 - 1.0f64) * (n2 - 1.0f64))) } else { v = 1.0f64 / (2.0f64 * (n1 - 1.0f64)) + 1.0f64 / (2.0f64 * (n2 - 1.0f64)) }
            }
            if measure == 30usize {
                if correct {
                    y = math.log[f64](s1i / m1) - math.log[f64](s2i / m2) + 1.0f64 / (2.0f64 * (n1 - 1.0f64)) - 1.0f64 / (2.0f64 * (n2 - 1.0f64)) + 0.5f64 * (s2i * s2i / (n2 * m2 * m2) - s1i * s1i / (n1 * m1 * m1))
                } else {
                    y = math.log[f64](s1i / m1) - math.log[f64](s2i / m2)
                }
                if vtype == 5usize {
                    v = s1i * s1i / (n1 * m1 * m1) + s2i * s2i / (n2 * m2 * m2) + s1i * s1i * s1i * s1i / (2.0f64 * n1 * n1 * m1 * m1 * m1 * m1) + s2i * s2i * s2i * s2i / (2.0f64 * n2 * n2 * m2 * m2 * m2 * m2) + 0.5f64 * (n1 / ((n1 - 1.0f64) * (n1 - 1.0f64)) + n2 / ((n2 - 1.0f64) * (n2 - 1.0f64)))
                } else {
                    v = 1.0f64 / (2.0f64 * (n1 - 1.0f64)) + s1i * s1i / (n1 * m1 * m1) + 1.0f64 / (2.0f64 * (n2 - 1.0f64)) + s2i * s2i / (n2 * m2 * m2)
                }
            }
            yi[i] = y
            vi[i] = v
            i += 1usize
        }
        ret
    }
    if measure >= 40usize && measure <= 42usize {
        var any0 = false
        i = 0usize
        while i < k {
            if at(d, ncol, i, 0usize) == 0.0f64 || at(d, ncol, i, 1usize) == 0.0f64 { any0 = true }
            i += 1usize
        }
        i = 0usize
        while i < k {
            var x1 = at(d, ncol, i, 0usize)
            var x2 = at(d, ncol, i, 1usize)
            let t1 = at(d, ncol, i, 2usize)
            let t2 = at(d, ncol, i, 3usize)
            if drop00 && x1 == 0.0f64 && x2 == 0.0f64 {
                x1 = nan()
                x2 = nan()
            }
            let z = x1 == 0.0f64 || x2 == 0.0f64
            var adj = false
            if to == 1usize { adj = true }
            if to == 2usize && z { adj = true }
            if to == 3usize && any0 { adj = true }
            if adj {
                x1 = x1 + add
                x2 = x2 + add
            }
            let r1 = x1 / t1
            let r2 = x2 / t2
            if measure == 40usize {
                yi[i] = math.log[f64](r1) - math.log[f64](r2)
                vi[i] = 1.0f64 / x1 + 1.0f64 / x2
            }
            if measure == 41usize {
                yi[i] = r1 - r2
                vi[i] = r1 / t1 + r2 / t2
            }
            if measure == 42usize {
                yi[i] = math.sqrt[f64](r1) - math.sqrt[f64](r2)
                vi[i] = 1.0f64 / (4.0f64 * t1) + 1.0f64 / (4.0f64 * t2)
            }
            i += 1usize
        }
        ret
    }
    if measure == 50usize || measure == 51usize {
        var mnw = 0.0f64
        if measure == 50usize {
            let rr = scratch[0usize..k]
            let nn = scratch[k..2usize * k]
            i = 0usize
            while i < k {
                rr[i] = at(d, ncol, i, 0usize)
                nn[i] = at(d, ncol, i, 1usize)
                i += 1usize
            }
            mnw = wmean(rr, nn, k)
        }
        i = 0usize
        while i < k {
            let r = at(d, ncol, i, 0usize)
            let n = at(d, ncol, i, 1usize)
            if measure == 50usize {
                yi[i] = r
                if vtype == 0usize { vi[i] = (1.0f64 - r * r) * (1.0f64 - r * r) / (n - 1.0f64) }
                if vtype == 2usize { vi[i] = (1.0f64 - mnw * mnw) * (1.0f64 - mnw * mnw) / (n - 1.0f64) }
                if vtype == 3usize { vi[i] = (1.0f64 - r * r) / (n - 2.0f64) }
                if vtype == 8usize { vi[i] = 1.0f64 / n }
            } else {
                yi[i] = 0.5f64 * math.log[f64]((1.0f64 + r) / (1.0f64 - r))
                vi[i] = 1.0f64 / (n - 3.0f64)
            }
            if n <= 3.0f64 { vi[i] = nan() }
            i += 1usize
        }
        ret
    }
    if measure >= 60usize && measure <= 65usize {
        var any0 = false
        i = 0usize
        while i < k {
            if at(d, ncol, i, 0usize) == 0.0f64 || at(d, ncol, i, 1usize) == 0.0f64 { any0 = true }
            i += 1usize
        }
        let pr = scratch[0usize..k]
        let nn = scratch[k..2usize * k]
        i = 0usize
        while i < k {
            var x = at(d, ncol, i, 0usize)
            var m = at(d, ncol, i, 1usize)
            let z = x == 0.0f64 || m == 0.0f64
            var adj = false
            if to == 1usize { adj = true }
            if to == 2usize && z { adj = true }
            if to == 3usize && any0 { adj = true }
            if adj {
                x = x + add
                m = m + add
            }
            pr[i] = x / (x + m)
            nn[i] = x + m
            i += 1usize
        }
        let mnp = wmean(pr, nn, k)
        i = 0usize
        while i < k {
            var x = at(d, ncol, i, 0usize)
            var m = at(d, ncol, i, 1usize)
            let z = x == 0.0f64 || m == 0.0f64
            var adj = false
            if to == 1usize { adj = true }
            if to == 2usize && z { adj = true }
            if to == 3usize && any0 { adj = true }
            if adj {
                x = x + add
                m = m + add
            }
            let n = x + m
            let p = x / n
            if measure == 60usize {
                yi[i] = p
                if vtype == 1usize { vi[i] = p * (1.0f64 - p) / (n - 1.0f64) }
                if vtype == 2usize { vi[i] = mnp * (1.0f64 - mnp) / n }
                if vtype == 0usize { vi[i] = p * (1.0f64 - p) / n }
            }
            if measure == 61usize {
                yi[i] = math.log[f64](p)
                if vtype == 2usize { vi[i] = 1.0f64 / (mnp * n) - 1.0f64 / n } else { vi[i] = 1.0f64 / x - 1.0f64 / n }
            }
            if measure == 62usize {
                yi[i] = math.log[f64](p / (1.0f64 - p))
                if vtype == 2usize { vi[i] = 1.0f64 / (mnp * n) + 1.0f64 / ((1.0f64 - mnp) * n) } else { vi[i] = 1.0f64 / x + 1.0f64 / m }
            }
            if measure == 63usize {
                yi[i] = dist.qnorm(p, 0.0f64, 1.0f64, true, false)
                vi[i] = 2.0f64 * pi_c() * p * (1.0f64 - p) * math.exp[f64](yi[i] * yi[i]) / n
            }
            if measure == 64usize {
                yi[i] = math.asin[f64](math.sqrt[f64](p))
                vi[i] = 1.0f64 / (4.0f64 * n)
            }
            if measure == 65usize {
                yi[i] = 0.5f64 * (math.asin[f64](math.sqrt[f64](x / (n + 1.0f64))) + math.asin[f64](math.sqrt[f64]((x + 1.0f64) / (n + 1.0f64))))
                vi[i] = 1.0f64 / (4.0f64 * n + 2.0f64)
            }
            i += 1usize
        }
        ret
    }
    if measure >= 70usize && measure <= 73usize {
        var any0 = false
        i = 0usize
        while i < k {
            if at(d, ncol, i, 0usize) == 0.0f64 { any0 = true }
            i += 1usize
        }
        i = 0usize
        while i < k {
            var x = at(d, ncol, i, 0usize)
            let t = at(d, ncol, i, 1usize)
            let xu = x
            var adj = false
            if to == 1usize { adj = true }
            if to == 2usize && x == 0.0f64 { adj = true }
            if to == 3usize && any0 { adj = true }
            if adj { x = x + add }
            let _ = xu
            let ir = x / t
            if measure == 70usize {
                yi[i] = ir
                vi[i] = ir / t
            }
            if measure == 71usize {
                yi[i] = math.log[f64](ir)
                vi[i] = 1.0f64 / x
            }
            if measure == 72usize {
                yi[i] = math.sqrt[f64](ir)
                vi[i] = 1.0f64 / (4.0f64 * t)
            }
            if measure == 73usize {
                yi[i] = 0.5f64 * (math.sqrt[f64](ir) + math.sqrt[f64](ir + 1.0f64 / t))
                vi[i] = 1.0f64 / (4.0f64 * t)
            }
            i += 1usize
        }
        ret
    }
    if measure >= 80usize && measure <= 84usize {
        var sd2 = 0.0f64
        var sdn = 0.0f64
        i = 0usize
        while i < k {
            let sd = at(d, ncol, i, 1usize)
            let n = at(d, ncol, i, 2usize)
            sd2 += (n - 1.0f64) * sd * sd
            sdn += n - 1.0f64
            i += 1usize
        }
        let sdp = math.sqrt[f64](sd2 / sdn)
        i = 0usize
        while i < k {
            let m = at(d, ncol, i, 0usize)
            let sd = at(d, ncol, i, 1usize)
            let n = at(d, ncol, i, 2usize)
            if measure == 80usize {
                yi[i] = m
                if vtype == 4usize { vi[i] = sdp * sdp / n } else { vi[i] = sd * sd / n }
            }
            if measure == 81usize {
                yi[i] = cmi_of(n - 1.0f64, correct) * m / sd
                vi[i] = 1.0f64 / n + yi[i] * yi[i] / (2.0f64 * n)
            }
            if measure == 82usize {
                yi[i] = math.log[f64](m)
                vi[i] = sd * sd / (n * m * m)
            }
            if measure == 83usize {
                if correct { yi[i] = math.log[f64](sd) + 1.0f64 / (2.0f64 * (n - 1.0f64)) } else { yi[i] = math.log[f64](sd) }
                vi[i] = 1.0f64 / (2.0f64 * (n - 1.0f64))
            }
            if measure == 84usize {
                if correct { yi[i] = math.log[f64](sd / m) + 1.0f64 / (2.0f64 * (n - 1.0f64)) } else { yi[i] = math.log[f64](sd / m) }
                vi[i] = 1.0f64 / (2.0f64 * (n - 1.0f64)) + sd * sd / (n * m * m)
            }
            i += 1usize
        }
    }
}
