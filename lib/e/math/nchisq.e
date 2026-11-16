// The non-central distributions of R's nmath: chi-squared (pnchisq.c, AS 275), t (pnt.c, AS 243) and F (pnf.c over pnbeta.c, AS 226). R accumulates
// in long double; this is f64 throughout, so results agree to about 1e-14 relative rather than bit for bit.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.toms708 as tm

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

// pnt: the non-central t distribution function (AS 243, Lenth 1989) with R's tail handling
fn pnt(t: f64, df: f64, ncp: f64, lower0: bool, lg: bool) -> f64 {
    if t != t || df != df || ncp != ncp { ret t + df + ncp }
    if df <= 0.0f64 { ret nan() }
    if ncp == 0.0f64 { ret nb.pt(t, df, lower0, lg) }
    if !finite(t) {
        if t < 0.0f64 { ret dist.dt0(lower0, lg) }
        ret dist.dt1(lower0, lg)
    }
    var negdel = false
    var tt = t
    var del = ncp
    if t < 0.0f64 {
        if ncp > 40.0f64 && (!lg || !lower0) { ret dist.dt0(lower0, lg) }
        negdel = true
        tt = 0.0f64 - t
        del = 0.0f64 - ncp
    }
    if df > 4.0e5f64 || del * del > 2.0f64 * 0.693147180559945309417232121458f64 * 1021.0f64 {
        let s = 1.0f64 / (4.0f64 * df)
        ret dist.pnorm(tt * (1.0f64 - s), del, math.sqrt[f64](1.0f64 + tt * tt * 2.0f64 * s), lower0 != negdel, lg)
    }
    var x = t * t
    var rxb = df / (x + df)
    x = x / (x + df)
    var tnc = 0.0f64
    if x > 0.0f64 {
        let lambda = del * del
        var p = 0.5f64 * math.exp[f64](0.0f64 - 0.5f64 * lambda)
        if p == 0.0f64 { ret dist.dt0(lower0, lg) }
        var q = 0.797884560802865355879892119869f64 * p * del
        var s = 0.5f64 - p
        if s < 1.0e-7f64 { s = 0.0f64 - 0.5f64 * dist.expm1(0.0f64 - 0.5f64 * lambda) }
        var a = 0.5f64
        let b = 0.5f64 * df
        rxb = math.pow[f64](rxb, b)
        let albeta = 0.572364942924700087071713675677f64 + nm.lgammafn(b) - nm.lgammafn(0.5f64 + b)
        var xodd = nb.pbeta(x, a, b, true, false)
        var godd = 2.0f64 * rxb * math.exp[f64](a * math.log[f64](x) - albeta)
        tnc = b * x
        var xeven = 1.0f64 - rxb
        if tnc < 2.220446049250313e-16f64 { xeven = tnc }
        var geven = tnc * rxb
        tnc = p * xodd + q * xeven
        var it = 1i64
        var stop = false
        while it <= 1000i64 && !stop {
            a += 1.0f64
            xodd -= godd
            xeven -= geven
            godd *= x * (a + b - 1.0f64) / a
            geven *= x * (a + b - 0.5f64) / (a + 0.5f64)
            p *= lambda / f64(2i64 * it)
            q *= lambda / f64(2i64 * it + 1i64)
            tnc += p * xodd + q * xeven
            s -= p
            if s < 0.0f64 - 1.0e-10f64 {
                stop = true
            } else if s <= 0.0f64 && it > 1i64 {
                stop = true
            } else {
                let errbd = 2.0f64 * s * (xodd - godd)
                if math.abs[f64](errbd) < 1.0e-12f64 { stop = true }
            }
            it += 1i64
        }
    }
    tnc += dist.pnorm(0.0f64 - del, 0.0f64, 1.0f64, true, false)
    let lower = lower0 != negdel
    var tc = tnc
    if tc > 1.0f64 { tc = 1.0f64 }
    ret nb.dt_val(tc, lower, lg)
}

// pnbeta2: AS 226 with R84 and R95, x and o_x = 1 - x given separately
fn pnbeta2(x: f64, o_x: f64, a: f64, b: f64, ncp: f64, lower: bool, lg: bool) -> f64 {
    if ncp < 0.0f64 || a <= 0.0f64 || b <= 0.0f64 { ret nan() }
    var ans = 0.0f64
    if x < 0.0f64 || o_x > 1.0f64 || (x == 0.0f64 && o_x == 1.0f64) {
        ans = 0.0f64
    } else if x > 1.0f64 || o_x < 0.0f64 || (x == 1.0f64 && o_x == 0.0f64) {
        ans = 1.0f64
    } else {
        let c = ncp / 2.0f64
        var x0 = c - 7.0f64 * math.sqrt[f64](c)
        if x0 < 0.0f64 { x0 = 0.0f64 }
        x0 = math.floor[f64](x0)
        let a0 = a + x0
        let lbet = nb.lbeta(a0, b)
        let (temp0, tc, ie) = tm.bratio(a0, b, x, o_x, false)
        var temp = temp0
        var lx = math.log[f64](o_x)
        if x < 0.5f64 { lx = dist.log1p(0.0f64 - x) }
        var gx = math.exp[f64](a0 * math.log[f64](x) + b * lx - lbet - math.log[f64](a0))
        var q = math.exp[f64](0.0f64 - c)
        if a0 > a { q = math.exp[f64](0.0f64 - c + x0 * math.log[f64](c) - nm.lgammafn(x0 + 1.0f64)) }
        var sumq = 1.0f64 - q
        ans = q * temp
        var j = x0
        var errbd = 1.0f64
        var go = true
        while go {
            j += 1.0f64
            temp -= gx
            gx *= x * (a + b + j - 1.0f64) / (a + j)
            q *= c / j
            sumq -= q
            let ax = temp * q
            ans += ax
            errbd = (temp - gx) * sumq
            go = errbd > 1.0e-9f64 && j < 10000.0f64 + x0
        }
    }
    if lower {
        if lg { ret math.log[f64](ans) }
        ret ans
    }
    if ans > 1.0f64 { ans = 1.0f64 }
    if lg { ret dist.log1p(0.0f64 - ans) }
    ret 1.0f64 - ans
}

// pnf: the non-central F distribution function
fn pnf(x: f64, df1: f64, df2: f64, ncp: f64, lower: bool, lg: bool) -> f64 {
    if x != x || df1 != df1 || df2 != df2 || ncp != ncp { ret x + df2 + df1 + ncp }
    if df1 <= 0.0f64 || df2 <= 0.0f64 || ncp < 0.0f64 { ret nan() }
    if !finite(ncp) { ret nan() }
    if !finite(df1) && !finite(df2) { ret nan() }
    if x <= 0.0f64 { ret dist.dt0(lower, lg) }
    if x == inf() { ret dist.dt1(lower, lg) }
    if df2 > 1.0e8f64 { ret pnchisq(x * df1, df1, ncp, lower, lg) }
    let y = (df1 / df2) * x
    ret pnbeta2(y / (1.0f64 + y), 1.0f64 / (1.0f64 + y), df1 / 2.0f64, df2 / 2.0f64, ncp, lower, lg)
}
