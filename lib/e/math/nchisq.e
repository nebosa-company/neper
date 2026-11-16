// The non-central chi-squared distribution function of R's nmath (pnchisq.c, AS 275 with R's underflow regimes). R accumulates
// in long double; this is f64 throughout, so results agree to about 1e-14 relative rather than bit for bit.

use e.math
use e.math.dist as dist
use e.math.nmath as nm

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn dbl_min_exp() -> f64 { ret 0.693147180559945309417232121458f64 * (0.0f64 - 1021.0f64) }

fn logspace_add(lx: f64, ly: f64) -> f64 {
    var m = lx
    if ly > lx { m = ly }
    var d = lx - ly
    if d < 0.0f64 { d = 0.0f64 - d }
    ret m + dist.log1p(math.exp[f64](0.0f64 - d))
}

fn pnchisq_raw(x: f64, f: f64, theta: f64, errmax: f64, reltol: f64, itrmax: i64, lower: bool, lg: bool) -> f64 {
    if x <= 0.0f64 {
        if x == 0.0f64 && f == 0.0f64 {
            let l = 0.0f64 - 0.5f64 * theta
            if lower {
                if lg { ret l }
                ret math.exp[f64](l)
            }
            if lg { ret dist.log1_exp(l) }
            ret 0.0f64 - dist.expm1(l)
        }
        ret dist.dt0(lower, lg)
    }
    if !finite(x) { ret dist.dt1(lower, lg) }
    let dme = dbl_min_exp()
    if theta < 80.0f64 {
        if lower && f > 0.0f64 && math.log[f64](x) < 0.693147180559945309417232121458f64 + 2.0f64 / f * (nm.lgammafn(f / 2.0f64 + 1.0f64) + dme) {
            let lambda = 0.5f64 * theta
            let log_lam = math.log[f64](lambda)
            var pr = 0.0f64 - lambda
            var sum = 0.0f64 - inf()
            var sum2 = 0.0f64 - inf()
            var i = 0i64
            while i < 110i64 {
                sum2 = logspace_add(sum2, pr)
                sum = logspace_add(sum, pr + nm.pchisq(x, f + 2.0f64 * f64(i), lower, true))
                if sum2 >= 0.0f64 - 1.0e-15f64 { break }
                i += 1i64
                pr += log_lam - math.log[f64](f64(i))
            }
            let ans = sum - sum2
            if lg { ret ans }
            ret math.exp[f64](ans)
        }
        let lambda = 0.5f64 * theta
        var sum = 0.0f64
        var sum2 = 0.0f64
        var pr = math.exp[f64](0.0f64 - lambda)
        var i = 0i64
        while i < 110i64 {
            sum2 += pr
            sum += pr * nm.pchisq(x, f + 2.0f64 * f64(i), lower, false)
            if sum2 >= 1.0f64 - 1.0e-15f64 { break }
            i += 1i64
            pr *= lambda / f64(i)
        }
        let ans = sum / sum2
        if lg { ret math.log[f64](ans) }
        ret ans
    }
    let lam = 0.5f64 * theta
    var lam_sml = 0.0f64 - lam < dme
    var u = 0.0f64
    var lu = 0.0f64 - 1.0f64
    var l_lam = 0.0f64 - 1.0f64
    if lam_sml {
        lu = 0.0f64 - lam
        l_lam = math.log[f64](lam)
    } else {
        u = math.exp[f64](0.0f64 - lam)
    }
    var v = u
    let x2 = 0.5f64 * x
    let f2 = 0.5f64 * f
    var f_x_2n = f - x
    var t = x2 - f2
    var lt = 0.0f64
    var at = t
    if at < 0.0f64 { at = 0.0f64 - at }
    if f2 * 2.220446049250313e-16f64 > 0.125f64 && at < math.sqrt[f64](2.220446049250313e-16f64) * f2 {
        lt = (1.0f64 - t) * (2.0f64 - t / (f2 + 1.0f64)) - 0.918938533204672741780329736406f64 - 0.5f64 * math.log[f64](f2 + 1.0f64)
    } else {
        lt = f2 * math.log[f64](x2) - x2 - nm.lgammafn(f2 + 1.0f64)
    }
    var t_sml = lt < dme
    var l_x = 0.0f64 - 1.0f64
    var ans = 0.0f64
    var term = 0.0f64
    if t_sml {
        if x > f + theta + 5.0f64 * math.sqrt[f64](2.0f64 * (f + 2.0f64 * theta)) { ret dist.dt1(lower, lg) }
        l_x = math.log[f64](x)
        t = 0.0f64
    } else {
        t = math.exp[f64](lt)
        term = v * t
        ans = term
    }
    var n = 1i64
    var f_2n = f + 2.0f64
    f_x_2n += 2.0f64
    while n <= itrmax {
        if f_x_2n > 0.0f64 {
            let bound = t * x / f_x_2n
            if bound <= errmax && term <= reltol * ans { break }
        }
        if lam_sml {
            lu += l_lam - math.log[f64](f64(n))
            if lu >= dme {
                u = math.exp[f64](lu)
                v = u
                lam_sml = false
            }
        } else {
            u *= lam / f64(n)
            v += u
        }
        if t_sml {
            lt += l_x - math.log[f64](f_2n)
            if lt >= dme {
                t = math.exp[f64](lt)
                t_sml = false
            }
        } else {
            t *= x / f_2n
        }
        if !lam_sml && !t_sml {
            term = v * t
            ans += term
        }
        n += 1i64
        f_2n += 2.0f64
        f_x_2n += 2.0f64
    }
    if lower { ret dist.dval(ans, lg) }
    ret dist.dclog(ans, lg)
}

fn pnchisq(x: f64, df: f64, ncp: f64, lower: bool, lg: bool) -> f64 {
    if x != x || df != df || ncp != ncp { ret x + df + ncp }
    if !finite(df) || !finite(ncp) { ret nan() }
    if df < 0.0f64 || ncp < 0.0f64 { ret nan() }
    var ans = pnchisq_raw(x, df, ncp, 1.0e-12f64, 8.0f64 * 2.220446049250313e-16f64, 1000000i64, lower, lg)
    if x <= 0.0f64 || x == inf() { ret ans }
    if ncp >= 80.0f64 {
        if lower {
            let one = dist.d1(lg)
            if one < ans { ans = one }
        } else {
            if !lg && ans < 0.0f64 { ans = 0.0f64 }
        }
    }
    if !lg || ans < 0.0f64 - 1.0e-8f64 { ret ans }
    let other = pnchisq_raw(x, df, ncp, 1.0e-12f64, 8.0f64 * 2.220446049250313e-16f64, 1000000i64, !lower, false)
    ret dist.log1p(0.0f64 - other)
}
