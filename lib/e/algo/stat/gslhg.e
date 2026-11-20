// R gsl, hyperg_1F1, hyperg_1F1_int, hyperg_U, hyperg_U_int and hyperg_2F0 with gsl_sf_result.err: a port of specfunc/hyperg_1F1.c, hyperg_U.c, hyperg_2F0.c and the helpers of hyperg.c, over the
// gamma, Pochhammer, Bessel and Laguerre pieces of the sibling gsl modules. 1F1 and U call each other, so they share this file. A function returns (value, error) plus a status where gsl's flow
// reads it (0 success, 1 domain error, 2 overflow, 3 underflow, 4 maximum iterations); an _e10 function also returns the decimal exponent.
// Not here: hyperg_2F1 (gslh2f1).

use e.math
use e.math.dist as md
use e.mem
use e.algo.stat.gslnu as gu
use e.algo.stat.gslbessel as gb
use e.algo.stat.gslbn as gn
use e.algo.stat.gslbj as gj
use e.algo.stat.gslerr as ge
use e.algo.stat.gslgam as gm
use e.algo.stat.gslerr2 as g2
use e.algo.stat.gslpoch as gp
use e.algo.stat.gslginc as gi

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn c_inf() -> f64 { ret 1.0f64 / 0.0f64 }
fn c_nan() -> f64 { ret 0.0f64 / 0.0f64 }
fn c_lmax() -> f64 { ret 7.0978271289338397e+02f64 }
fn c_lmin() -> f64 { ret -7.0839641853226408e+02f64 }
fn c_dmax() -> f64 { ret 1.7976931348623157e+308f64 }
fn c_smax() -> f64 { ret 1.3407807929942596e+154f64 }
fn c_smin() -> f64 { ret 1.4916681462400413e-154f64 }
fn c_seps() -> f64 { ret 1.4901161193847656e-08f64 }
fn c_r3eps() -> f64 { ret 6.0554544523933429e-06f64 }
fn c_leps() -> f64 { ret -3.6043653389117156e+01f64 }
fn c_ln10() -> f64 { ret 2.30258509299404568401799145468f64 }
fn c_pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn c_lnpi() -> f64 { ret 1.14472988584940017414342735135f64 }
fn c_e() -> f64 { ret 2.71828182845904523536028747135f64 }
fn c_sqrt2() -> f64 { ret 1.41421356237309504880168872421f64 }
fn c_imax() -> f64 { ret 2147483647.0f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}
fn fmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}
fn sgn1(x: f64) -> f64 {
    if x >= 0.0f64 { ret 1.0f64 }
    ret -1.0f64
}
fn odd(n: i64) -> bool { ret n % 2i64 != 0i64 }
fn fl(x: f64) -> f64 { ret math.floor[f64](x) }
fn lg(x: f64) -> f64 { ret math.log[f64](x) }
fn ex(x: f64) -> f64 { ret math.exp[f64](x) }

// gsl_sf_exp_e
fn exp_e(x: f64) -> (f64, f64, i64) {
    if x > c_lmax() { ret (c_inf(), c_inf(), 2i64) }
    if x < c_lmin() { ret (0.0f64, 2.2250738585072014e-308f64, 3i64) }
    let v = ex(x)
    ret (v, 2.0f64 * c_eps() * fa(v), 0i64)
}

// gsl_sf_exp_e10_e
fn exp_e10(x: f64) -> (f64, f64, i64, i64) {
    if x > 2147483646.0f64 { ret (c_inf(), c_inf(), 0i64, 2i64) }
    if x < -2147483646.0f64 { ret (0.0f64, 2.2250738585072014e-308f64, 0i64, 3i64) }
    var n = 0i64
    if x > c_lmax() || x < c_lmin() { n = i64(fl(x / c_ln10())) }
    let v = ex(x - f64(n) * c_ln10())
    ret (v, 2.0f64 * (fa(x) + 1.0f64) * c_eps() * fa(v), n, 0i64)
}

// gsl_sf_exp_err_e
fn exp_err(x: f64, dx: f64) -> (f64, f64, i64) {
    let adx = fa(dx)
    if x + adx > c_lmax() { ret (c_inf(), c_inf(), 2i64) }
    if x - adx < c_lmin() { ret (0.0f64, 2.2250738585072014e-308f64, 3i64) }
    let v = ex(x)
    let edx = ex(adx)
    ret (v, v * fmax(c_eps(), edx - 1.0f64 / edx) + 2.0f64 * c_eps() * fa(v), 0i64)
}

// gsl_sf_exp_err_e10_e
fn exp_err_e10(x: f64, dx: f64) -> (f64, f64, i64, i64) {
    let adx = fa(dx)
    if x + adx > 2147483646.0f64 { ret (c_inf(), c_inf(), 0i64, 2i64) }
    if x - adx < -2147483646.0f64 { ret (0.0f64, 2.2250738585072014e-308f64, 0i64, 3i64) }
    let n = i64(fl(x / c_ln10()))
    let v = ex(x - f64(n) * c_ln10())
    ret (v, v * (2.0f64 * c_eps() * (fa(x) + 1.0f64) + adx), n, 0i64)
}

// gsl_sf_exp_mult_err_e
fn emx(x: f64, dx: f64, y: f64, dy: f64) -> (f64, f64, i64) {
    let ay = fa(y)
    if y == 0.0f64 { ret (0.0f64, fa(dy * ex(x)), 0i64) }
    if x < 0.5f64 * c_lmax() && x > 0.5f64 * c_lmin() && ay < 0.8f64 * c_smax() && ay > 1.2f64 * c_smin() {
        let e1 = ex(x)
        let v = y * e1
        ret (v, e1 * (fa(dy) + fa(y * dx)) + 2.0f64 * c_eps() * fa(v), 0i64)
    }
    let ly = lg(ay)
    let lnr = x + ly
    if lnr > c_lmax() - 0.01f64 { ret (c_inf(), c_inf(), 2i64) }
    if lnr < c_lmin() + 0.01f64 { ret (0.0f64, 2.2250738585072014e-308f64, 3i64) }
    let sy = sgn1(y)
    let mm = fl(x)
    let nn = fl(ly)
    let a = x - mm
    let b = ly - nn
    let emn = ex(mm + nn)
    let eab = ex(a + b)
    let v = sy * emn * eab
    var er = emn * eab * 2.0f64 * c_eps()
    er += emn * eab * fa(dy / y)
    er += emn * eab * fa(dx)
    ret (v, er, 0i64)
}

// gsl_sf_exp_mult_e: (value, error, status)
fn emu(x: f64, y: f64) -> (f64, f64, i64) {
    let ay = fa(y)
    if y == 0.0f64 { ret (0.0f64, 0.0f64, 0i64) }
    if x < 0.5f64 * c_lmax() && x > 0.5f64 * c_lmin() && ay < 0.8f64 * c_smax() && ay > 1.2f64 * c_smin() {
        let v = y * ex(x)
        ret (v, (2.0f64 + fa(x)) * c_eps() * fa(v), 0i64)
    }
    let ly = lg(ay)
    let lnr = x + ly
    if lnr > c_lmax() - 0.01f64 { ret (c_inf(), c_inf(), 2i64) }
    if lnr < c_lmin() + 0.01f64 { ret (0.0f64, 2.2250738585072014e-308f64, 3i64) }
    let sy = sgn1(y)
    let mm = fl(x)
    let nn = fl(ly)
    let a = x - mm
    let b = ly - nn
    let berr = 2.0f64 * c_eps() * (fa(ly) + fa(nn))
    let v = sy * ex(mm + nn) * ex(a + b)
    ret (v, berr * fa(v) + 2.0f64 * c_eps() * (mm + nn + 1.0f64) * fa(v), 0i64)
}

// gsl_sf_exp_mult_err_e10_e: (value, error, e10, status)
fn emx10(x: f64, dx: f64, y: f64, dy: f64) -> (f64, f64, i64, i64) {
    let ay = fa(y)
    if y == 0.0f64 { ret (0.0f64, fa(dy * ex(x)), 0i64, 0i64) }
    if x < 0.5f64 * c_lmax() && x > 0.5f64 * c_lmin() && ay < 0.8f64 * c_smax() && ay > 1.2f64 * c_smin() {
        let e1 = ex(x)
        let v = y * e1
        ret (v, e1 * (fa(dy) + fa(y * dx)) + 2.0f64 * c_eps() * fa(v), 0i64, 0i64)
    }
    let ly = lg(ay)
    let l10 = (x + ly) / c_ln10()
    if l10 > 2147483646.0f64 { ret (c_inf(), c_inf(), 0i64, 2i64) }
    if l10 < -2147483646.0f64 { ret (0.0f64, 2.2250738585072014e-308f64, 0i64, 3i64) }
    let sy = sgn1(y)
    let n = i64(fl(l10))
    let argv = (l10 - f64(n)) * c_ln10()
    let arge = dy / fa(y) + dx + 2.0f64 * c_eps() * fa(argv)
    let v = sy * ex(argv)
    ret (v, arge * fa(v) + 2.0f64 * c_eps() * fa(v), n, 0i64)
}

// gsl_sf_result_smash_e
fn smash(v: f64, e: f64, n: i64) -> (f64, f64, i64) {
    if n == 0i64 { ret (v, e, 0i64) }
    let av = fa(v)
    let ae = fa(e)
    let nf = f64(n)
    if c_smin() < av && av < c_smax() && c_smin() < ae && ae < c_smax() && 0.49f64 * c_lmin() < nf && nf < 0.49f64 * c_lmax() {
        let sc = ex(nf * c_ln10())
        ret (v * sc, e * sc, 0i64)
    }
    let (rv, re, st) = emx(nf * c_ln10(), 0.0f64, v, e)
    ret (rv, re, st)
}

fn expm1_e(x: f64) -> (f64, f64) {
    let (v, e) = gp.e_expm1(x)
    ret (v, e)
}

// gsl_sf_exprel_e
fn exprel_e(x: f64) -> (f64, f64, i64) {
    let cut = 0.002f64
    if x < c_lmin() {
        let v = -1.0f64 / x
        ret (v, c_eps() * fa(v), 0i64)
    }
    if x < -cut {
        let v = (ex(x) - 1.0f64) / x
        ret (v, 2.0f64 * c_eps() * fa(v), 0i64)
    }
    if x < cut {
        let v = 1.0f64 + 0.5f64 * x * (1.0f64 + x / 3.0f64 * (1.0f64 + 0.25f64 * x * (1.0f64 + 0.2f64 * x)))
        ret (v, 2.0f64 * c_eps() * fa(v), 0i64)
    }
    if x < c_lmax() {
        let v = (ex(x) - 1.0f64) / x
        ret (v, 2.0f64 * c_eps() * fa(v), 0i64)
    }
    ret (c_inf(), c_inf(), 2i64)
}

// gsl_sf_exprel_2_e
fn exprel_2_e(x: f64) -> (f64, f64, i64) {
    let cut = 0.002f64
    if x < c_lmin() {
        let v = -2.0f64 / x * (1.0f64 + 1.0f64 / x)
        ret (v, 2.0f64 * c_eps() * fa(v), 0i64)
    }
    if x < -cut {
        let v = 2.0f64 * (ex(x) - 1.0f64 - x) / (x * x)
        ret (v, 2.0f64 * c_eps() * fa(v), 0i64)
    }
    if x < cut {
        let v = 1.0f64 + 1.0f64 / 3.0f64 * x * (1.0f64 + 0.25f64 * x * (1.0f64 + 0.2f64 * x * (1.0f64 + 1.0f64 / 6.0f64 * x)))
        ret (v, 2.0f64 * c_eps() * fa(v), 0i64)
    }
    if x < c_lmax() {
        let v = 2.0f64 * (ex(x) - 1.0f64 - x) / (x * x)
        ret (v, 2.0f64 * c_eps() * fa(v), 0i64)
    }
    ret (c_inf(), c_inf(), 2i64)
}

// gsl_sf_exprel_n_e
fn exprel_n_e(n: i64, x: f64) -> (f64, f64, i64) {
    if n < 0i64 { ret (c_nan(), c_nan(), 1i64) }
    if x == 0.0f64 { ret (1.0f64, 0.0f64, 0i64) }
    let nf = f64(n)
    if fa(x) < c_r3eps() * nf { ret (1.0f64 + x / (nf + 1.0f64) * (1.0f64 + x / (nf + 2.0f64)), 2.0f64 * c_eps(), 0i64) }
    if n == 0i64 {
        let (v0, e0, s0) = exp_e(x)
        ret (v0, e0, s0)
    }
    if n == 1i64 {
        let (v1, e1, s1) = exprel_e(x)
        ret (v1, e1, s1)
    }
    if n == 2i64 {
        let (v2, e2, s2) = exprel_2_e(x)
        ret (v2, e2, s2)
    }
    if x > nf && (0.0f64 - x + nf * (1.0f64 + lg(x / nf)) < c_leps()) {
        let (fv, fe) = g2.e_lnfact(usize(n))
        let lnterm = nf * lg(x)
        let lnrv = x + fv - lnterm
        let lnre = c_eps() * (fa(x) + fa(fv) + fa(lnterm)) + fe
        let (rv, re, rs) = exp_err(lnrv, lnre)
        ret (rv, re, rs)
    }
    if x > nf {
        let lnx = lg(x)
        let (fv, fe) = g2.e_lnfact(usize(n))
        let lgn = fv - lg(nf)
        let lnprev = x + fv - nf * lnx
        let lnpree = c_eps() * (fa(x) + fa(fv) + fa(nf * lnx)) + fe
        if lnprev < c_lmax() - 5.0f64 {
            let (pv, pe, ps) = exp_err(lnprev, lnpree)
            let lnbig = 0.0f64 - x + (nf - 1.0f64) * lnx - lgn
            var bsum = 1.0f64
            var term = 1.0f64
            var k = 1i64
            while k < n {
                term = term * (f64(n - k) / x)
                bsum += term
                k += 1i64
            }
            let (bv, be, bs) = emu(lnbig, bsum)
            if bs == 0i64 {
                let v = pv * (1.0f64 - bv)
                let e = pv * (2.0f64 * c_eps() + be) + pe * fa(1.0f64 - bv) + 2.0f64 * c_eps() * fa(v)
                ret (v, e, ps)
            }
            ret (0.0f64, 0.0f64, bs)
        }
        ret (c_inf(), c_inf(), 2i64)
    }
    if x > -10.0f64 * nf {
        let (cv, ce) = gi.exprel_n_cf(nf, x)
        ret (cv, ce, 0i64)
    }
    var sum = 1.0f64
    var term2 = 1.0f64
    var k2 = 1i64
    while k2 < n {
        term2 = term2 * (f64(n - k2) / x)
        sum += term2
        k2 += 1i64
    }
    let v3 = 0.0f64 - nf / x * sum
    ret (v3, 2.0f64 * c_eps() * fa(v3), 0i64)
}

// (value, error, sign, status): gsl_sf_lngamma_sgn_e
fn lngamma_sgn(x: f64) -> (f64, f64, f64, i64) {
    if x <= 0.0f64 && x == fl(x) { ret (c_nan(), c_nan(), 0.0f64, 1i64) }
    let (v, e, sg) = gm.lngamma_sgn(x)
    ret (v, e, sg, 0i64)
}

fn lngamma(x: f64) -> (f64, f64, i64) {
    let (v, e, _s, st) = lngamma_sgn(x)
    ret (v, e, st)
}

// gsl_sf_beta_e for x, y > 0
fn beta_e(x: f64, y: f64) -> (f64, f64) {
    if x < 50.0f64 && y < 50.0f64 {
        let (gx, gxe) = g2.e_gamma(x)
        let (gy, gye) = g2.e_gamma(y)
        let (gxy, gxye) = g2.e_gamma(x + y)
        let v = (gx * gy) / gxy
        var e = gxe * fa(gy / gxy)
        e += gye * fa(gx / gxy)
        e += fa((gx * gy) / (gxy * gxy)) * gxye
        e += 2.0f64 * c_eps() * fa(v)
        ret (v, e)
    }
    let (lv, le) = g2.e_lnbeta(x, y)
    let (ev, ee, _s) = exp_err(lv, le)
    ret (ev, ee)
}

// gsl_sf_laguerre_n_e pieces
fn lag_cp(n: i64, a: f64, x: f64) -> (f64, f64, i64) {
    let nf = f64(n)
    let (fv, fe) = g2.e_lnfact(usize(n))
    let (g1v, g1e, _s1, st1) = lngamma_sgn(a + 1.0f64 + nf)
    let (g2v, g2e, _s2, st2) = lngamma_sgn(a + 1.0f64)
    var pv = 1.0f64
    var pe = 0.0f64
    let lnpv = (g1v - g2v) - fv
    let lnpe = g1e + g2e + fe + 2.0f64 * c_eps() * fa(lnpv)
    var k = n - 1i64
    while k >= 0i64 {
        let t = f64(k - n) / (a + 1.0f64 + f64(k)) * (x / f64(k + 1i64))
        let r = t + 1.0f64 / pv
        if r > 0.9f64 * c_dmax() / pv { ret (0.0f64, 0.0f64, 2i64) }
        pv = 1.0f64 + t * pv
        pe += c_eps() + fa(t) * pe
        k -= 1i64
    }
    let (v, e, st) = emx(lnpv, lnpe, pv, pe)
    var s = st
    if s == 0i64 { s = st1 }
    if s == 0i64 { s = st2 }
    ret (v, e, s)
}

fn lag_poly_safe(n: i64, a: f64, x: f64) -> (f64, f64, i64) {
    let b = a + 1.0f64
    let mx = 0.0f64 - x
    var tcs = 1.0f64
    if x >= 0.0f64 {
        tcs = 1.0f64
        if odd(n) { tcs = -1.0f64 }
    }
    let (tv, te) = g2.e_taylorcoeff(n, fa(x))
    if tv == c_inf() { ret (0.0f64, 0.0f64, 2i64) }
    var term = tv * tcs
    var sv = term
    var se = te
    var k = n - 1i64
    while k >= 0i64 {
        term = term * (((b + f64(k)) / f64(n - k)) * (f64(k) + 1.0f64) / mx)
        sv += term
        se += 4.0f64 * c_eps() * fa(term)
        k -= 1i64
    }
    ret (sv, se + 2.0f64 * c_eps() * fa(sv), 0i64)
}

fn lag_large_n(n: i64, alpha: f64, x: f64) -> (f64, f64, i64) {
    let nf = f64(n)
    let a = 0.0f64 - nf
    let b = alpha + 1.0f64
    let eta = 2.0f64 * b - 4.0f64 * a
    let cos2th = x / eta
    let sin2th = 1.0f64 - cos2th
    let eps = math.asin[f64](math.sqrt[f64](cos2th))
    let pre_h = 0.25f64 * c_pi() * c_pi() * eta * eta * cos2th * sin2th
    let (lgv, lge, _st) = lngamma(b + nf)
    let (fv, fe) = g2.e_lnfact(usize(n))
    let pt1 = 0.5f64 * (1.0f64 - b) * lg(0.25f64 * x * eta)
    let pt2 = 0.25f64 * lg(pre_h)
    let lnpv = lgv - fv + 0.5f64 * x + pt1 - pt2
    let lnpe = lge + fe + c_eps() * (fa(pt1) + fa(pt2))
    let phi1 = 0.25f64 * eta * (2.0f64 * eps + math.sin[f64](2.0f64 * eps))
    let st1 = 0.0f64 - math.sin[f64](phi1)
    let aa1 = (1.0f64 / 12.0f64) * (5.0f64 / (4.0f64 * sin2th) + (3.0f64 * b * b - 6.0f64 * b + 2.0f64) * sin2th - 1.0f64)
    let st2 = 0.0f64 - aa1 * math.cos[f64](phi1) / (0.25f64 * eta * math.sin[f64](2.0f64 * eps))
    let sv = st1 + st2
    let se = st2 * st2 + c_eps() * (fa(st1) + fa(st2))
    let (v, e, s) = emx(lnpv, lnpe, sv, se)
    ret (v, e + 2.0f64 * c_seps() * fa(v), s)
}

// gsl_sf_laguerre_n_e(n, a, x)
fn laguerre_n(n: i64, a: f64, x: f64) -> (f64, f64, i64) {
    if n < 0i64 { ret (c_nan(), c_nan(), 1i64) }
    if n == 0i64 { ret (1.0f64, 0.0f64, 0i64) }
    let nf = f64(n)
    if n == 1i64 { ret (1.0f64 + a - x, 2.0f64 * c_eps() * (1.0f64 + fa(a) + fa(x)), 0i64) }
    if x == 0.0f64 {
        var product = a + 1.0f64
        var k = 2i64
        while k <= n {
            product = product * ((a + f64(k)) / f64(k))
            k += 1i64
        }
        ret (product, 2.0f64 * (nf + 1.0f64) * c_eps() * fa(product) + c_eps(), 0i64)
    }
    if x < 0.0f64 && a > -1.0f64 {
        let (v1, e1, s1) = lag_cp(n, a, x)
        ret (v1, e1, s1)
    }
    if n < 5i64 || (x > 0.0f64 && a < 0.0f64 - nf - 1.0f64) {
        let (v2, e2, s2) = lag_cp(n, a, x)
        if s2 == 0i64 { ret (v2, e2, 0i64) }
        let (v3, e3, s3) = lag_poly_safe(n, a, x)
        ret (v3, e3, s3)
    }
    if nf > 1.0e+07f64 && x > 0.0f64 && a > -1.0f64 && x < 2.0f64 * (a + 1.0f64) + 4.0f64 * nf {
        let (v4, e4, s4) = lag_large_n(n, a, x)
        ret (v4, e4, s4)
    }
    if a >= 0.0f64 || (x > 0.0f64 && a < 0.0f64 - nf - 1.0f64) {
        let (l2v, l2e) = ge.e_laguerre_2(a, x)
        var lkm1 = 1.0f64 + a - x
        var lk = l2v
        var k = 2i64
        while k < n {
            let kf = f64(k)
            let lkp1 = (0.0f64 - (kf + a) * lkm1 + (2.0f64 * kf + a + 1.0f64 - x) * lk) / (kf + 1.0f64)
            lkm1 = lk
            lk = lkp1
            k += 1i64
        }
        ret (lk, (fa(l2e / l2v) + c_eps()) * nf * fa(lk), 0i64)
    }
    let (v5, e5, s5) = lag_poly_safe(n, a, x)
    ret (v5, e5, s5)
}

// hyperg.c: gsl_sf_hyperg_1F1_series_e
fn f_series(a: f64, b: f64, x: f64) -> (f64, f64, i64) {
    var an = a
    var bn = b
    var n = 1.0f64
    var del = 1.0f64
    var abs_del = 1.0f64
    var max_abs_del = 1.0f64
    var sum_val = 1.0f64
    var sum_err = 0.0f64
    while abs_del / fa(sum_val) > 0.25f64 * c_eps() {
        if bn == 0.0f64 { ret (c_nan(), c_nan(), 1i64) }
        if an == 0.0f64 { ret (sum_val, sum_err + 2.0f64 * c_eps() * n * fa(sum_val), 0i64) }
        if n > 10000.0f64 { ret (sum_val, sum_err, 5i64) }
        let u = x * (an / (bn * n))
        let abs_u = fa(u)
        if abs_u > 1.0f64 && max_abs_del > c_dmax() / abs_u { ret (sum_val, fa(sum_val), 2i64) }
        del = del * u
        sum_val += del
        if fa(sum_val) > 1.0e-5f64 * c_dmax() { ret (sum_val, fa(sum_val), 2i64) }
        abs_del = fa(del)
        max_abs_del = fmax(abs_del, max_abs_del)
        sum_err += 2.0f64 * c_eps() * abs_del
        an += 1.0f64
        bn += 1.0f64
        n += 1.0f64
    }
    ret (sum_val, sum_err + abs_del + 2.0f64 * c_eps() * n * fa(sum_val), 0i64)
}

// hyperg.c: gsl_sf_hyperg_1F1_large_b_e
fn f_large_b(a: f64, b: f64, x: f64) -> (f64, f64, i64) {
    if fa(x / b) < 1.0f64 {
        let u = x / b
        let v = 1.0f64 / (1.0f64 - u)
        let pre = math.pow[f64](v, a)
        let uv = u * v
        let uv2 = uv * uv
        let t1 = a * (a + 1.0f64) / (2.0f64 * b) * uv2
        let t2a = a * (a + 1.0f64) / (24.0f64 * b * b) * uv2
        let t2b = 12.0f64 + 16.0f64 * (a + 2.0f64) * uv + 3.0f64 * (a + 2.0f64) * (a + 3.0f64) * uv2
        let t2 = t2a * t2b
        let val = pre * (1.0f64 - t1 + t2)
        let er = pre * c_eps() * (1.0f64 + fa(t1) + fa(t2)) + 2.0f64 * c_eps() * fa(val)
        ret (val, er, 0i64)
    }
    ret (c_nan(), c_nan(), 1i64)
}

// hyperg.c: gsl_sf_hyperg_U_large_b_e: (value, error, ln_multiplier)
fn u_large_b(a: f64, b: f64, x: f64) -> (f64, f64, f64) {
    let nn = fl(b)
    let epsb = b - nn
    if fa(epsb) < c_seps() {
        var lnpv = 0.0f64
        var lnpe = 0.0f64
        var mv = 0.0f64
        var me = 0.0f64
        if b > 1.0f64 {
            let tmp = (1.0f64 - b) * lg(x)
            let (bv, be, _s0) = lngamma(b - 1.0f64)
            let (av, ae, _s1) = lngamma(a)
            lnpv = tmp + x + bv - av
            lnpe = be + ae + c_eps() * (fa(x) + fa(tmp))
            let (m1, m2, _s2) = f_large_b(1.0f64 - a, 2.0f64 - b, 0.0f64 - x)
            mv = m1
            me = m2
        } else {
            let (v1, e1, _s3) = lngamma(1.0f64 - b)
            let (v2, e2, _s4) = lngamma(1.0f64 + a - b)
            lnpv = v1 - v2
            lnpe = e1 + e2
            let (m1, m2, _s5) = f_large_b(a, b, x)
            mv = m1
            me = m2
        }
        if lnpv > c_lmax() - 10.0f64 { ret (mv, me, lnpv) }
        let (pv, pe, _s6) = exp_err(lnpv, lnpe)
        let v = pv * mv
        ret (v, pv * me + pe * fa(mv) + 2.0f64 * c_eps() * fa(v), 0.0f64)
    }
    let omb_lnx = (1.0f64 - b) * lg(x)
    let (l1v, l1e, g1, _t1) = lngamma_sgn(1.0f64 - b)
    let (l2v, l2e, g2s, _t2) = lngamma_sgn(1.0f64 + a - b)
    let (l3v, l3e, g3, _t3) = lngamma_sgn(b - 1.0f64)
    let (l4v, l4e, g4, _t4) = lngamma_sgn(a)
    let (m1v, m1e, _u1) = f_large_b(a, b, x)
    let (m2v, m2e, _u2) = f_large_b(1.0f64 - a, 2.0f64 - b, x)
    let lnp1v = l1v - l2v
    let lnp1e = l1e + l2e
    let lnp2v = l3v - l4v - omb_lnx - x
    let lnp2e = l3e + l4e + c_eps() * (fa(omb_lnx) + fa(x))
    let sg1 = g1 * g2s
    let sg2 = g3 * g4
    if lnp1v > c_lmax() - 10.0f64 || lnp2v > c_lmax() - 10.0f64 {
        let mlv = fmax(lnp1v, lnp2v)
        let mle = fmax(lnp1e, lnp2e)
        let t1 = sg1 * ex(lnp1v - mlv)
        let t2 = sg2 * ex(lnp2v - mlv)
        let v = t1 * m1v + t2 * m2v
        var e = fa(t1) * m1e + fa(t2) * m2e
        e += c_eps() * ex(mle) * (fa(t1 * m1v) + fa(t2 * m2v))
        e += 2.0f64 * c_eps() * fa(v)
        ret (v, e, mlv)
    }
    let t1 = sg1 * ex(lnp1v)
    let t2 = sg2 * ex(lnp2v)
    let v = t1 * m1v + t2 * m2v
    var e = fa(t1) * m1e + fa(t2) * m2e
    e += c_eps() * (ex(lnp1e) * fa(t1 * m1v) + ex(lnp2e) * fa(t2 * m2v))
    e += 2.0f64 * c_eps() * fa(v)
    ret (v, e, 0.0f64)
}

// hyperg.c: gsl_sf_hyperg_2F0_series_e(a, b, x, n_trunc): (value, error, status)
fn f2f0_series(a: f64, b: f64, x: f64, n_trunc: i64) -> (f64, f64, i64) {
    var an = a
    var bn = b
    var n = 1.0f64
    var sum = 1.0f64
    var del = 1.0f64
    var abs_del = 1.0f64
    var max_abs_del = 1.0f64
    var last_abs_del = 1.0f64
    while abs_del / fa(sum) > c_eps() && n < 2000.0f64 {
        let u = an * (bn / n * x)
        let abs_u = fa(u)
        if abs_u > 1.0f64 && max_abs_del > c_dmax() / abs_u { ret (sum, fa(sum), 2i64) }
        del = del * u
        sum += del
        abs_del = fa(del)
        if abs_del > last_abs_del { break }
        last_abs_del = abs_del
        max_abs_del = fmax(abs_del, max_abs_del)
        an += 1.0f64
        bn += 1.0f64
        n += 1.0f64
        if an == 0.0f64 || bn == 0.0f64 { break }
        if n_trunc >= 0i64 && n >= f64(n_trunc) { break }
    }
    var st = 0i64
    if n >= 2000.0f64 { st = 4i64 }
    ret (sum, c_eps() * n + abs_del, st)
}

// ---- hyperg_1F1.c ----

fn f_asymp_negx(a: f64, b: f64, x: f64) -> (f64, f64) {
    let (lbv, lbe, sb, st1) = lngamma_sgn(b)
    let (lmv, lme, sm, st2) = lngamma_sgn(b - a)
    if st1 == 0i64 && st2 == 0i64 {
        let (fv, fe, _sf) = f2f0_series(a, 1.0f64 + a - b, -1.0f64 / x, -1i64)
        if fv != 0.0f64 {
            let ltv = a * lg(0.0f64 - x)
            let lte = 2.0f64 * c_eps() * (fa(a) + fa(ltv))
            let lpv = lbv - lmv - ltv
            let lpe = lbe + lme + lte
            let (v, e, _s) = emx(lpv, lpe, sm * sb * fv, fe)
            ret (v, e)
        }
        ret (0.0f64, 0.0f64)
    }
    ret (c_nan(), c_nan())
}

fn f_asymp_posx(a: f64, b: f64, x: f64) -> (f64, f64) {
    let (lbv, lbe, sb, st1) = lngamma_sgn(b)
    let (lav, lae, sa, st2) = lngamma_sgn(a)
    if st1 == 0i64 && st2 == 0i64 {
        let (fv, fe, fs) = f2f0_series(b - a, 1.0f64 - a, 1.0f64 / x, -1i64)
        if fs == 0i64 && fv != 0.0f64 {
            let lnx = lg(x)
            let ltv = (a - b) * lnx
            let lte = 2.0f64 * c_eps() * (fa(a) + fa(b)) * fa(lnx) + 2.0f64 * c_eps() * fa(a - b)
            let lpv = lbv - lav + ltv + x
            let lpe = lbe + lae + lte + 2.0f64 * c_eps() * fa(x)
            let (v, e, _s) = emx(lpv, lpe, sa * sb * fv, fe)
            ret (v, e)
        }
        ret (0.0f64, 0.0f64)
    }
    ret (c_nan(), c_nan())
}

fn f_largebx(a: f64, b: f64, x: f64) -> (f64, f64) {
    let y = x / b
    let f = ex(0.0f64 - a * md.log1p(0.0f64 - y))
    let t1 = 0.0f64 - ((a * (a + 1.0f64)) / (2.0f64 * b)) * math.pow[f64](y / (1.0f64 - y), 2.0f64)
    let t2 = (1.0f64 / (24.0f64 * b * b)) * ((a * (a + 1.0f64) * y * y) / math.pow[f64](1.0f64 - y, 4.0f64)) * (12.0f64 + 8.0f64 * (2.0f64 * a + 1.0f64) * y + (3.0f64 * a * a - a - 2.0f64) * y * y)
    let t3 = (-1.0f64 / (48.0f64 * b * b * b * math.pow[f64](1.0f64 - y, 6.0f64))) * a * ((a + 1.0f64) * ((y * ((a + 1.0f64) * (a * (y * (y * ((y * (a - 2.0f64) + 16.0f64) * (a - 1.0f64)) + 72.0f64)) + 96.0f64)) + 24.0f64) * math.pow[f64](y, 2.0f64)))
    let v = f * (1.0f64 + t1 + t2 + t3)
    ret (v, 2.0f64 * fa(f * t3) + 2.0f64 * c_eps() * fa(v))
}

fn f_large2bm4a(a: f64, b: f64, x: f64) -> (f64, f64) {
    let eta = 2.0f64 * b - 4.0f64 * a
    let cos2th = x / eta
    let sin2th = 1.0f64 - cos2th
    let th = math.acos[f64](math.sqrt[f64](cos2th))
    let pre_h = 0.25f64 * c_pi() * c_pi() * eta * eta * cos2th * sin2th
    let (lbv, lbe, _sl) = lngamma(b)
    let t1 = 0.5f64 * (1.0f64 - b) * lg(0.25f64 * x * eta)
    let t2 = 0.25f64 * lg(pre_h)
    let lpv = lbv + 0.5f64 * x + t1 - t2
    let lpe = lbe + 2.0f64 * c_eps() * (fa(0.5f64 * x) + fa(t1) + fa(t2))
    let s1 = math.sin[f64](a * c_pi())
    let s2 = math.sin[f64](0.25f64 * eta * (2.0f64 * th - math.sin[f64](2.0f64 * th)) + 0.25f64 * c_pi())
    let sv = s1 + s2
    let se = 2.0f64 * c_eps() * (fa(s1) + fa(s2))
    let (v, e, _s) = emx(lpv, lpe, sv, se)
    ret (v, e)
}

fn f_luke(a: f64, c: f64, xin: f64) -> (f64, f64) {
    let big = 1.0e+50f64
    var n = 3i64
    let x = 0.0f64 - xin
    let x3 = x * x * x
    let t0 = a / c
    let t1 = (a + 1.0f64) / (2.0f64 * c)
    let t2 = (a + 2.0f64) / (2.0f64 * (c + 1.0f64))
    var fv = 1.0f64
    var prec = 0.0f64
    var bnm3 = 1.0f64
    var bnm2 = 1.0f64 + t1 * x
    var bnm1 = 1.0f64 + t2 * x * (1.0f64 + t1 / 3.0f64 * x)
    var anm3 = 1.0f64
    var anm2 = bnm2 - t0 * x
    var anm1 = bnm1 - t0 * (1.0f64 + t2 * x) * x + t0 * t1 * (c / (c + 1.0f64)) * x * x
    while true {
        let nf = f64(n)
        let npam1 = nf + a - 1.0f64
        let npcm1 = nf + c - 1.0f64
        let npam2 = nf + a - 2.0f64
        let npcm2 = nf + c - 2.0f64
        let tnm1 = 2.0f64 * nf - 1.0f64
        let tnm3 = 2.0f64 * nf - 3.0f64
        let tnm5 = 2.0f64 * nf - 5.0f64
        let f1 = (nf - a - 2.0f64) / (2.0f64 * tnm3 * npcm1)
        let f2 = (nf + a) * npam1 / (4.0f64 * tnm1 * tnm3 * npcm2 * npcm1)
        let f3 = 0.0f64 - npam2 * npam1 * (nf - a - 2.0f64) / (8.0f64 * tnm3 * tnm3 * tnm5 * (nf + c - 3.0f64) * npcm2 * npcm1)
        let ee = 0.0f64 - npam1 * (nf - c - 1.0f64) / (2.0f64 * tnm3 * npcm2 * npcm1)
        var an = (1.0f64 + f1 * x) * anm1 + (ee + f2 * x) * x * anm2 + f3 * x3 * anm3
        var bn = (1.0f64 + f1 * x) * bnm1 + (ee + f2 * x) * x * bnm2 + f3 * x3 * bnm3
        let r = an / bn
        prec = fa((fv - r) / fv)
        fv = r
        if prec < c_eps() || n > 5000i64 { break }
        if fa(an) > big || fa(bn) > big {
            an = an / big
            bn = bn / big
            anm1 = anm1 / big
            bnm1 = bnm1 / big
            anm2 = anm2 / big
            bnm2 = bnm2 / big
            anm3 = anm3 / big
            bnm3 = bnm3 / big
        } else {
            if fa(an) < 1.0f64 / big || fa(bn) < 1.0f64 / big {
                an = an * big
                bn = bn * big
                anm1 = anm1 * big
                bnm1 = bnm1 * big
                anm2 = anm2 * big
                bnm2 = bnm2 * big
                anm3 = anm3 * big
                bnm3 = bnm3 * big
            }
        }
        n += 1i64
        bnm3 = bnm2
        bnm2 = bnm1
        bnm1 = bn
        anm3 = anm2
        anm2 = anm1
        anm1 = an
    }
    var er = 2.0f64 * fa(fv * prec)
    er += 2.0f64 * c_eps() * (f64(n) - 1.0f64) * fa(fv)
    ret (fv, er)
}

fn f_1_series(b: f64, x: f64) -> (f64, f64) {
    var sum_val = 1.0f64
    var sum_err = 0.0f64
    var term = 1.0f64
    var n = 1.0f64
    while fa(term / sum_val) > 0.25f64 * c_eps() {
        term = term * (x / (b + n - 1.0f64))
        sum_val += term
        sum_err += 8.0f64 * c_eps() * fa(term) + c_eps() * fa(sum_val)
        n += 1.0f64
    }
    ret (sum_val, sum_err + 2.0f64 * fa(term))
}

fn f_1_int(b: i64, x: f64) -> (f64, f64) {
    if b < 1i64 { ret (c_nan(), c_nan()) }
    if b == 1i64 {
        let (v, e, _s) = exp_e(x)
        ret (v, e)
    }
    if b == 2i64 {
        let (v, e, _s) = exprel_e(x)
        ret (v, e)
    }
    if b == 3i64 {
        let (v, e, _s) = exprel_2_e(x)
        ret (v, e)
    }
    let (v2, e2, _s2) = exprel_n_e(b - 1i64, x)
    ret (v2, e2)
}

fn f_1(b: f64, x: f64) -> (f64, f64) {
    let ax = fa(x)
    let ib = fl(b + 0.1f64)
    if b < 1.0f64 { ret (c_nan(), c_nan()) }
    if b == 1.0f64 {
        let (v, e, _s) = exp_e(x)
        ret (v, e)
    }
    if b >= 1.4f64 * ax {
        let (v1, e1) = f_1_series(b, x)
        ret (v1, e1)
    }
    if fa(b - ib) < 100.0f64 * c_eps() && ib < c_imax() {
        let (v2, e2) = f_1_int(i64(ib), x)
        ret (v2, e2)
    }
    if x > 0.0f64 {
        if x > 100.0f64 && b < 0.75f64 * x {
            let (v3, e3) = f_asymp_posx(1.0f64, b, x)
            ret (v3, e3)
        }
        if b < 1.0e+05f64 {
            let off = math.ceil[f64](1.4f64 * x - b) + 1.0f64
            var bp = b + off
            let (mv, me) = f_1_series(bp, x)
            var m = mv
            let err_rat = me / fa(mv)
            while bp > b + 0.1f64 {
                bp -= 1.0f64
                m = 1.0f64 + x / bp * m
            }
            var er = err_rat * fa(m)
            er += 2.0f64 * c_eps() * (fa(off) + 1.0f64) * fa(m)
            ret (m, er)
        }
        if fa(x) < fa(b) && fa(x) < math.sqrt[f64](fa(b)) * fa(b - x) {
            let (v4, e4) = f_largebx(1.0f64, b, x)
            ret (v4, e4)
        }
        if fa(x) > fa(b) {
            let (v5, e5) = f_1_series(b, x)
            ret (v5, e5)
        }
        let (v6, e6) = f_large2bm4a(1.0f64, b, x)
        ret (v6, e6)
    }
    if ax < 10.0f64 && b < 10.0f64 {
        let (v7, e7) = f_1_series(b, x)
        ret (v7, e7)
    }
    if ax >= 100.0f64 && fmax(fa(2.0f64 - b), 1.0f64) < 0.99f64 * ax {
        let (v8, e8) = f_asymp_negx(1.0f64, b, x)
        ret (v8, e8)
    }
    let (v9, e9) = f_luke(1.0f64, b, x)
    ret (v9, e9)
}

fn f_renorm_b0(ar: *mem.Arena, a: f64, x: f64) -> (f64, f64) {
    let eta = a * x
    if eta > 0.0f64 {
        let re = math.sqrt[f64](eta)
        let (i1v, i1e) = gb.i1_scaled(2.0f64 * re)
        if i1v <= 0.0f64 { ret (0.0f64, 0.0f64) }
        let (i2v, _i2e) = gu.in_scaled_full(ar, 2i64, 2.0f64 * re)
        let corr1 = (2.0f64 / 3.0f64) * a * math.pow[f64](x / (4.0f64 * a), 1.5f64) * i2v
        let lnrv = 0.5f64 * x + 0.5f64 * lg(eta) + fa(2.0f64 * re) + lg(i1v + corr1)
        let lnre = c_eps() * (1.5f64 * fa(x) + 1.0f64) + fa((i1e + corr1) / i1v)
        let (v, e, _s) = exp_err(lnrv, lnre)
        ret (v, e)
    }
    if eta == 0.0f64 { ret (0.0f64, 0.0f64) }
    let re2 = math.sqrt[f64](0.0f64 - eta)
    let (j1v, j1e) = gj.j1(2.0f64 * re2)
    if j1v <= 0.0f64 { ret (0.0f64, 0.0f64) }
    let t1 = 0.5f64 * x
    let t2 = 0.5f64 * lg(0.0f64 - eta)
    let t3 = fa(x)
    let t4 = lg(j1v)
    let lnrv2 = t1 + t2 + t3 + t4
    let lnre2 = c_eps() * (1.5f64 * fa(x) + 1.0f64) + fa(j1e / j1v)
    let (xv, xe, _s2) = exp_err(lnrv2, lnre2)
    ret (0.0f64 - xv, xe)
}

fn f_cf1_p_ser(a: f64, b: f64, x: f64) -> f64 {
    if a == 0.0f64 { ret 0.0f64 }
    var sum = 1.0f64
    var pk = 1.0f64
    var rhok = 0.0f64
    var k = 1i64
    while k < 5000i64 {
        let kf = f64(k)
        let ak = (a + kf) * x / ((b - x + kf - 1.0f64) * (b - x + kf))
        rhok = 0.0f64 - ak * (1.0f64 + rhok) / (1.0f64 + ak * (1.0f64 + rhok))
        pk = pk * rhok
        sum += pk
        if fa(pk / sum) < 2.0f64 * c_eps() { break }
        k += 1i64
    }
    ret a / (b - x) * sum
}

fn f_small_a_bgt0(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    let bma = b - a
    let oma = 1.0f64 - a
    let ap1mb = 1.0f64 + a - b
    let abs_bma = fa(bma)
    let abs_oma = fa(oma)
    let abs_ap1mb = fa(ap1mb)
    let ax = fa(x)
    if a == 0.0f64 { ret (1.0f64, 0.0f64) }
    if a == 1.0f64 && b >= 1.0f64 {
        let (v0, e0) = f_1(b, x)
        ret (v0, e0)
    }
    if a == -1.0f64 {
        let v = 1.0f64 + a / b * x
        var e = c_eps() * (1.0f64 + fa(a / b * x))
        e += 2.0f64 * c_eps() * fa(v)
        ret (v, e)
    }
    if b >= 1.4f64 * ax {
        let (v1, e1, _s1) = f_series(a, b, x)
        ret (v1, e1)
    }
    if x > 0.0f64 {
        if x > 100.0f64 && abs_bma * abs_oma < 0.5f64 * x {
            let (v2, e2) = f_asymp_posx(a, b, x)
            ret (v2, e2)
        }
        if b < 5.0e+06f64 {
            let b_del = math.ceil[f64](1.4f64 * x - b) + 1.0f64
            var bp = b + b_del
            let (mp1v, mp1e, _s2) = f_series(a, bp + 1.0f64, x)
            let (mbv, mbe, _s3) = f_series(a, bp, x)
            let err_rat = fa(mp1e / mp1v) + fa(mbe / mbv)
            var mbp1 = mp1v
            var mb = mbv
            while bp > b + 0.1f64 {
                let mbm1 = ((x + bp - 1.0f64) * mb - x * (bp - a) / bp * mbp1) / (bp - 1.0f64)
                bp -= 1.0f64
                mbp1 = mb
                mb = mbm1
            }
            var er = err_rat * (fa(b_del) + 1.0f64) * fa(mb)
            er += 2.0f64 * c_eps() * fa(mb)
            ret (mb, er)
        }
        if fa(x) < fa(b) && fa(a * x) < math.sqrt[f64](fa(b)) * fa(b - x) {
            let (v3, e3) = f_largebx(a, b, x)
            ret (v3, e3)
        }
        let (v4, e4) = f_large2bm4a(a, b, x)
        ret (v4, e4)
    }
    if ax < 10.0f64 && b < 10.0f64 {
        let (v5, e5, _s5) = f_series(a, b, x)
        ret (v5, e5)
    }
    if ax >= 100.0f64 && fmax(abs_ap1mb, 1.0f64) < 0.99f64 * ax {
        let (v6, e6) = f_asymp_negx(a, b, x)
        ret (v6, e6)
    }
    let (v7, e7) = f_luke(a, b, x)
    ret (v7, e7)
}

fn f_beps_bgt0(ar: *mem.Arena, eps: f64, b: f64, x: f64) -> (f64, f64) {
    if b > fa(x) && fa(eps) < c_seps() {
        let a = b + eps
        let (exv, exe, _s) = exp_e(a * x / b)
        let v2 = a / (2.0f64 * b * b * (b + 1.0f64))
        let v3 = a * (b - 2.0f64 * a) / (3.0f64 * b * b * b * (b + 1.0f64) * (b + 2.0f64))
        let v = v2 + v3 * x
        let f = 1.0f64 - eps * x * x * v
        let rv = exv * f
        var er = exe * fa(f)
        er += fa(exv) * c_eps() * (1.0f64 + fa(eps * x * x * v))
        er += 4.0f64 * c_eps() * fa(rv)
        ret (rv, er)
    }
    let (kv, ke) = f_small_a_bgt0(ar, 0.0f64 - eps, b, 0.0f64 - x)
    if kv != 0.0f64 {
        let (v, e, _s2) = emx(x, 2.0f64 * c_eps() * fa(x), kv, ke)
        ret (v, e)
    }
    ret (0.0f64, 0.0f64)
}

fn f_beq2a_pos(ar: *mem.Arena, a: f64, x: f64) -> (f64, f64) {
    if x == 0.0f64 { ret (1.0f64, 0.0f64) }
    let (iv, ie) = gu.inu_scaled(ar, a - 0.5f64, 0.5f64 * fa(x))
    let (lv, le, _sl) = lngamma(a + 0.5f64)
    let ln_term = (0.5f64 - a) * lg(0.25f64 * fa(x))
    let lpv = lv + fmax(x, 0.0f64) + ln_term
    let lpe = le + c_eps() * (fa(ln_term) + fa(x))
    let (v, e, _s) = emx(lpv, lpe, iv, ie)
    ret (v, e)
}

fn f_ab_posint(ar: *mem.Arena, a: i64, b: i64, x: f64) -> (f64, f64) {
    let ax = fa(x)
    let af = f64(a)
    let bf = f64(b)
    if a == b {
        let (v0, e0, _s0) = exp_e(x)
        ret (v0, e0)
    }
    if a == 1i64 {
        let (v1, e1, _s1) = exprel_n_e(b - 1i64, x)
        ret (v1, e1)
    }
    if b == a + 1i64 {
        let (kv, ke, _s2) = exprel_n_e(a, 0.0f64 - x)
        let (v2, e2, _s3) = emx(x, 2.0f64 * c_eps() * fa(x), kv, ke)
        ret (v2, e2)
    }
    if a == b + 1i64 {
        let (exv, exe, _s4) = exp_e(x)
        let v3 = exv * (1.0f64 + x / bf)
        var e3 = exe * (1.0f64 + x / bf)
        e3 += exv * c_eps() * (1.0f64 + fa(x / bf))
        e3 += 2.0f64 * c_eps() * fa(v3)
        ret (v3, e3)
    }
    if a == b + 2i64 {
        let (exv, exe, _s5) = exp_e(x)
        let poly = 1.0f64 + x / bf * (2.0f64 + x / (bf + 1.0f64))
        let v4 = exv * poly
        var e4 = exe * fa(poly)
        e4 += exv * c_eps() * (1.0f64 + fa(x / bf) * (2.0f64 + fa(x / (bf + 1.0f64))))
        e4 += 2.0f64 * c_eps() * fa(v4)
        ret (v4, e4)
    }
    if b == 2i64 * a {
        let (v5, e5) = f_beq2a_pos(ar, af, x)
        ret (v5, e5)
    }
    if (b < 10i64 && a < 10i64 && ax < 5.0f64) || (bf > af * ax) || (b > a && ax < 5.0f64) {
        let (v6, e6, _s6) = f_series(af, bf, x)
        ret (v6, e6)
    }
    if b > a && bf >= f64(2i64 * a) + x {
        let rap = f_cf1_p_ser(af, bf, x)
        let ra = 1.0f64 + x / af * rap
        let ma = c_smin()
        let map1 = ra * ma
        var mnp1 = map1
        var mn = ma
        var n = a
        while n > 0i64 {
            let nf = f64(n)
            let mnm1 = (nf * mnp1 - (f64(2i64 * n - b) + x) * mn) / (bf - nf)
            mnp1 = mn
            mn = mnm1
            n -= 1i64
        }
        ret (ma / mn, 2.0f64 * c_eps() * (fa(af) + 1.0f64) * fa(ma / mn))
    }
    if b > a && bf < f64(2i64 * a) + x && bf > x {
        let rap2 = f_cf1_p_ser(af, bf, x)
        let ra2 = 1.0f64 + x / af * rap2
        let ma2 = c_smin()
        let map12 = ra2 * ma2
        var mnm1 = ma2
        var mn2 = map12
        var n2 = a + 1i64
        while n2 < b {
            let nf = f64(n2)
            let mnp1b = ((bf - nf) * mnm1 + (f64(2i64 * n2 - b) + x) * mn2) / nf
            mnm1 = mn2
            mn2 = mnp1b
            n2 += 1i64
        }
        let (exv, exe, _s7) = exp_e(x)
        let v7 = exv * ma2 / mn2
        var e7 = exe * fa(ma2 / mn2)
        e7 += 4.0f64 * c_eps() * (fa(bf - af) + 1.0f64) * fa(v7)
        ret (v7, e7)
    }
    if x >= 0.0f64 {
        if b < a {
            if x + lg(fa(x / bf)) < c_lmax() - 2.0f64 {
                let exx = ex(x)
                var mnm1 = exx
                var mn = exx * (1.0f64 + x / bf)
                var n = b + 1i64
                while n < a {
                    let nf = f64(n)
                    let mnp1 = ((bf - nf) * mnm1 + (f64(2i64 * n - b) + x) * mn) / nf
                    mnm1 = mn
                    mn = mnp1
                    n += 1i64
                }
                var er = (x + 1.0f64) * c_eps() * fa(mn)
                er = er * (fa(af - bf) + 1.0f64)
                ret (mn, er)
            }
            ret (c_inf(), c_inf())
        }
        let (rmv, rme, _s8) = exprel_n_e(b - 1i64, x)
        var mnm1c = 1.0f64
        var mnc = rmv
        var nc = 1i64
        while nc < a {
            let nf = f64(nc)
            let mnp1c = ((bf - nf) * mnm1c + (f64(2i64 * nc - b) + x) * mnc) / nf
            mnm1c = mnc
            mnc = mnp1c
            nc += 1i64
        }
        var erc = fa(mnc) * (1.0f64 + fa(af)) * fa(rme / rmv)
        erc += 2.0f64 * c_eps() * fa(mnc)
        ret (mnc, erc)
    }
    if af <= 0.5f64 * (bf - x) || af >= 0.0f64 - x {
        let exx = ex(x)
        var manp1 = exx
        var man = exx * (1.0f64 + x / (af - 1.0f64))
        var n = a - 1i64
        while n > b {
            let nf = f64(n)
            let manm1 = (0.0f64 - nf * (1.0f64 - nf - x) * man - x * (nf - af) * manp1) / (nf * (nf - 1.0f64))
            manp1 = man
            man = manm1
            n -= 1i64
        }
        var er = (fa(x) + 1.0f64) * c_eps() * fa(man)
        er = er * (fa(bf - af) + 1.0f64)
        ret (man, er)
    }
    let a0 = i64(math.ceil[f64](0.5f64 * (bf - x)))
    let a0f = f64(a0)
    let exx = ex(x)
    var ma0np1 = exx
    var ma0n = exx * (1.0f64 + x / (a0f - 1.0f64))
    var n = a0 - 1i64
    while n > b {
        let nf = f64(n)
        let ma0nm1 = (0.0f64 - nf * (1.0f64 - nf - x) * ma0n - x * (nf - a0f) * ma0np1) / (nf * (nf - 1.0f64))
        ma0np1 = ma0n
        ma0n = ma0nm1
        n -= 1i64
    }
    let ma0bp1 = ma0np1
    let ma0b = ma0n
    let ma0p1b = (bf * (a0f + x) * ma0b + x * (a0f - bf) * ma0bp1) / (a0f * bf)
    var mn = 0.0f64
    if a0 >= a {
        mn = ma0b
    } else {
        if a0 + 1i64 >= a {
            mn = ma0p1b
        } else {
            var mnm1 = ma0b
            mn = ma0p1b
            var m = a0 + 1i64
            while m < a {
                let mf = f64(m)
                let mnp1 = ((bf - mf) * mnm1 + (f64(2i64 * m - b) + x) * mn) / mf
                mnm1 = mn
                mn = mnp1
                m += 1i64
            }
        }
    }
    var er2 = (fa(x) + 1.0f64) * c_eps() * fa(mn)
    er2 = er2 * (fa(bf - af) + 1.0f64)
    ret (mn, er2)
}

fn f_a_negint_poly(a: i64, b: f64, x: f64) -> (f64, f64) {
    if a == 0i64 { ret (1.0f64, 1.0f64) }
    let nn = 0i64 - a
    var poly = 1.0f64
    var k = nn - 1i64
    while k >= 0i64 {
        let t = f64(a + k) / (b + f64(k)) * (x / f64(k + 1i64))
        let r = t + 1.0f64 / poly
        if r > 0.9f64 * c_dmax() / poly { ret (c_inf(), c_inf()) }
        poly = poly * r
        k -= 1i64
    }
    ret (poly, 2.0f64 * (math.sqrt[f64](f64(nn)) + 1.0f64) * c_eps() * fa(poly))
}

fn f_a_negint_lag(a: i64, b: f64, x: f64) -> (f64, f64) {
    let n = 0i64 - a
    let nf = f64(n)
    let (lagv, lage, _sl) = laguerre_n(n, b - 1.0f64, x)
    if b < 0.0f64 {
        let (fv, fe) = g2.e_lnfact(usize(n))
        let (g1v, g1e, s1, _t1) = lngamma_sgn(b + nf)
        let (g2v, g2e, s2, _t2) = lngamma_sgn(b)
        let lnpv = fv - (g1v - g2v)
        let lnpe = fe + g1e + g2e + 2.0f64 * c_eps() * fa(lnpv)
        let (v, e, _s) = emx(lnpv, lnpe, s1 * s2 * lagv, lage)
        ret (v, e)
    }
    let (lbv, lbe) = g2.e_lnbeta(b, nf)
    if fa(lbv) < 0.1f64 {
        let ltv = lg(1.25f64 * nf)
        let lte = 2.0f64 * c_eps() * ltv
        let (bv, _be) = beta_e(b, nf)
        let (v2, e2, _s2) = emx(ltv, lte, lagv, lage)
        ret (v2 * bv / 1.25f64, e2 * bv / 1.25f64)
    }
    let ln_n = lg(nf)
    let ltv2 = lbv + ln_n
    let lte2 = lbe + 2.0f64 * c_eps() * fa(ln_n)
    let (v3, e3, _s3) = emx(ltv2, lte2, lagv, lage)
    ret (v3, e3)
}

fn f_ab_negint(a: i64, b: i64, x: f64) -> (f64, f64) {
    if x == 0.0f64 { ret (1.0f64, 0.0f64) }
    if x > 0.0f64 {
        let (v, e) = f_a_negint_poly(a, f64(b), x)
        ret (v, e)
    }
    let (kv, ke) = f_a_negint_poly(b - a, f64(b), 0.0f64 - x)
    let (v2, e2, _s) = emx(x, 2.0f64 * c_eps() * fa(x), kv, ke)
    ret (v2, e2)
}

// hyperg_1F1_U: A&S 13.1.3
fn f_u(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    let bp = 2.0f64 - b
    let ap = a - b + 1.0f64
    let (lapv, lape, sgap, _t0) = lngamma_sgn(ap)
    let (lbpv, lbpe, _t1) = lngamma(bp)
    let t1 = (bp - 1.0f64) * lg(x)
    let lnpv = lapv - lbpv + t1
    let lnpe = lape + lbpe + 2.0f64 * c_eps() * fa(t1)
    let (l2v, l2e, s2, _t2) = lngamma_sgn(2.0f64 - bp)
    let (l3v, l3e, s3, _t3) = lngamma_sgn(1.0f64 + ap - bp)
    let lnc1v = l2v - l3v
    let lnc1e = l2e + l3e + c_eps() * (fa(l2v) + fa(l3v))
    let (mv, me) = f_e(ar, ap, bp, x)
    let (uv, ue, un) = u_e10(ar, ap, bp, x)
    let (tmv, tme, tmn, _t4) = emx10(lnc1v, lnc1e, s2 * s3 * mv, me)
    let ombp = 1.0f64 - bp
    let uev = f64(un) * c_ln10()
    let uee = 2.0f64 * c_eps() * fa(uev)
    let mev = f64(tmn) * c_ln10()
    let mee = 2.0f64 * c_eps() * fa(mev)
    if uev > mev {
        let fm = ex(mev - uev)
        let fme = 2.0f64 * c_eps() * (fa(mev - uev) + 1.0f64) * fm
        let inv = tmv * fm - ombp * uv
        let ine = tme * fm + fa(ombp) * ue + fa(tmv) * fme + c_eps() * (fa(tmv * fm) + fa(ombp * uv))
        let (v, e, _s) = emx(lnpv + uev, lnpe + uee, sgap * inv, ine)
        ret (v, e)
    }
    let fu = ex(uev - mev)
    let fue = 2.0f64 * c_eps() * (fa(mev - uev) + 1.0f64) * fu
    let inv2 = tmv - ombp * fu * uv
    let ine2 = tme + fa(ombp * fu * ue) + fa(ombp * fue * uv) + c_eps() * (fa(tmv) + fa(ombp * fu * uv))
    let (v2, e2, _s2) = emx(lnpv + mev, lnpe + mee, sgap * inv2, ine2)
    ret (v2, e2)
}

fn f_ab_pos(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    let ax = fa(x)
    if (b < 10.0f64 && a < 10.0f64 && ax < 5.0f64) || (b > a * ax) || (b > a && ax < 5.0f64) {
        let (v0, e0, _s0) = f_series(a, b, x)
        ret (v0, e0)
    }
    if x < -100.0f64 && fmax(fa(a), 1.0f64) * fmax(fa(1.0f64 + a - b), 1.0f64) < 0.7f64 * fa(x) {
        let (v1, e1) = f_asymp_negx(a, b, x)
        ret (v1, e1)
    }
    if x > 100.0f64 && fmax(fa(b - a), 1.0f64) * fmax(fa(1.0f64 - a), 1.0f64) < 0.7f64 * fa(x) {
        let (v2, e2) = f_asymp_posx(a, b, x)
        ret (v2, e2)
    }
    if fa(b - a) <= 1.0f64 {
        let (v3, e3) = f_beps_bgt0(ar, a - b, b, x)
        ret (v3, e3)
    }
    if b > a && b >= 2.0f64 * a + x {
        let rap = f_cf1_p_ser(a, b, x)
        let ra = 1.0f64 + x / a * rap
        let ma = c_smin()
        let map1 = ra * ma
        var mnp1 = map1
        var mn = ma
        var n = a
        while n > 0.5f64 {
            let mnm1 = (n * mnp1 - (2.0f64 * n - b + x) * mn) / (b - n)
            mnp1 = mn
            mn = mnm1
            n -= 1.0f64
        }
        let (tv, te) = f_small_a_bgt0(ar, n, b, x)
        let v4 = (ma / mn) * tv
        var e4 = fa(ma / mn) * te
        e4 += 2.0f64 * c_eps() * (fa(a) + 1.0f64) * fa(v4)
        ret (v4, e4)
    }
    if b > a && b < 2.0f64 * a + x && b > x {
        let rap2 = f_cf1_p_ser(a, b, x)
        let ra2 = 1.0f64 + x / a * rap2
        let ma2 = c_smin()
        var mnm1 = ma2
        var mn2 = ra2 * mnm1
        var n2 = a + 1.0f64
        while n2 < b - 0.5f64 {
            let mnp1b = ((b - n2) * mnm1 + (2.0f64 * n2 - b + x) * mn2) / n2
            mnm1 = mn2
            mn2 = mnp1b
            n2 += 1.0f64
        }
        let (tv2, te2) = f_beps_bgt0(ar, n2 - b, b, x)
        let v5 = ma2 / mn2 * tv2
        var e5 = fa(ma2 / mn2) * te2
        e5 += 2.0f64 * c_eps() * (fa(b - a) + 1.0f64) * fa(v5)
        ret (v5, e5)
    }
    if x >= 0.0f64 {
        if b < a {
            let nn = fl(a - b)
            let eps = a - b - nn
            let (m0v, m0e) = f_beps_bgt0(ar, eps - 1.0f64, b, x)
            let (m1v, m1e) = f_beps_bgt0(ar, eps, b, x)
            var mam1 = m0v
            var ma = m1v
            let start_pair = fa(m0v) + fa(m1v)
            var minim_pair = c_dmax()
            let rat0 = fa(m0e / m0v)
            let rat1 = fa(m1e / m1v)
            var ap = b + eps
            while ap < a - 0.1f64 {
                let map1b = ((b - ap) * mam1 + (2.0f64 * ap - b + x) * ma) / ap
                mam1 = ma
                ma = map1b
                minim_pair = fmin(fa(mam1) + fa(ma), minim_pair)
                ap += 1.0f64
            }
            let pair_ratio = start_pair / minim_pair
            var e6 = 2.0f64 * (rat0 + rat1 + c_eps()) * (fa(b - a) + 1.0f64) * fa(ma)
            e6 += 2.0f64 * (rat0 + rat1) * pair_ratio * pair_ratio * fa(ma)
            e6 += 2.0f64 * c_eps() * fa(ma)
            ret (ma, e6)
        }
        let eps2 = a - fl(a)
        let (n0v, n0e) = f_small_a_bgt0(ar, eps2, b, x)
        let (n1v, n1e) = f_small_a_bgt0(ar, eps2 + 1.0f64, b, x)
        var mnm1c = n0v
        var mnc = n1v
        let start2 = fa(mnc) + fa(mnm1c)
        var minim2 = c_dmax()
        let rt0 = fa(n0e / n0v)
        let rt1 = fa(n1e / n1v)
        var nc = eps2 + 1.0f64
        while nc < a - 0.1f64 {
            let mnp1c = ((b - nc) * mnm1c + (2.0f64 * nc - b + x) * mnc) / nc
            mnm1c = mnc
            mnc = mnp1c
            minim2 = fmin(fa(mnc) + fa(mnm1c), minim2)
            nc += 1.0f64
        }
        let pr2 = start2 / minim2
        var e7 = 2.0f64 * (rt0 + rt1 + c_eps()) * (fa(a) + 1.0f64) * fa(mnc)
        e7 += 2.0f64 * (rt0 + rt1) * pr2 * pr2 * fa(mnc)
        e7 += 2.0f64 * c_eps() * fa(mnc)
        ret (mnc, e7)
    }
    if a <= 0.5f64 * (b - x) || a >= 0.0f64 - x {
        let nn = fl(a - b)
        let eps = 1.0f64 + nn - a + b
        let (p1v, p1e) = f_beps_bgt0(ar, 0.0f64 - eps, a + eps, x)
        let (p0v, p0e) = f_beps_bgt0(ar, 1.0f64 - eps, a + eps - 1.0f64, x)
        var manp1 = p1v
        var man = p0v
        let start3 = fa(manp1) + fa(man)
        var minim3 = c_dmax()
        let rr0 = fa(p1e / p1v)
        let rr1 = fa(p0e / p0v)
        var n = a + eps - 1.0f64
        while n > b + 0.1f64 {
            let manm1 = (0.0f64 - n * (1.0f64 - n - x) * man - x * (n - a) * manp1) / (n * (n - 1.0f64))
            manp1 = man
            man = manm1
            minim3 = fmin(fa(manp1) + fa(man), minim3)
            n -= 1.0f64
        }
        let pr3 = start3 / minim3
        var e8 = 2.0f64 * (rr0 + rr1 + c_eps()) * (fa(b - a) + 1.0f64) * fa(man)
        e8 = e8 * (pr3 * pr3 + 1.0f64)
        ret (man, e8)
    }
    let epsa = a - fl(a)
    let a0 = fl(0.5f64 * (b - x)) + epsa
    let nn2 = fl(a0 - b)
    let epsb = 1.0f64 + nn2 - a0 + b
    let (q1v, q1e) = f_beps_bgt0(ar, 0.0f64 - epsb, a0 + epsb, x)
    let (q0v, q0e) = f_beps_bgt0(ar, 1.0f64 - epsb, a0 + epsb - 1.0f64, x)
    var ma0np1 = q1v
    var ma0n = q0v
    let err_rat = fa(q1e / q1v) + fa(q0e / q0v)
    var nq = a0 + epsb - 1.0f64
    while nq > b + 0.1f64 {
        let ma0nm1 = (0.0f64 - nq * (1.0f64 - nq - x) * ma0n - x * (nq - a0) * ma0np1) / (nq * (nq - 1.0f64))
        ma0np1 = ma0n
        ma0n = ma0nm1
        nq -= 1.0f64
    }
    let ma0bp1 = ma0np1
    let ma0b = ma0n
    let ma0p1b = (b * (a0 + x) * ma0b + x * (a0 - b) * ma0bp1) / (a0 * b)
    var mn3 = 0.0f64
    if a0 >= a - 0.1f64 {
        mn3 = ma0b
    } else {
        if a0 + 1.0f64 >= a - 0.1f64 {
            mn3 = ma0p1b
        } else {
            var mnm1d = ma0b
            mn3 = ma0p1b
            var nd = a0 + 1.0f64
            while nd < a - 0.1f64 {
                let mnp1d = ((b - nd) * mnm1d + (2.0f64 * nd - b + x) * mn3) / nd
                mnm1d = mn3
                mn3 = mnp1d
                nd += 1.0f64
            }
        }
    }
    ret (mn3, (err_rat + c_eps()) * (fa(b - a) + 1.0f64) * fa(mn3))
}

fn f_ab_neg(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    let bma = b - a
    let abs_x = fa(x)
    let abs_a = fa(a)
    let abs_b = fa(b)
    let size_a = fmax(abs_a, 1.0f64)
    let size_b = fmax(abs_b, 1.0f64)
    let bma_integer = bma - fl(bma + 0.5f64) < 100.0f64 * c_eps()
    if (abs_a < 10.0f64 && abs_b < 10.0f64 && abs_x < 5.0f64) || (b > 0.8f64 * fmax(fa(a), 1.0f64) * fa(x)) {
        let (v0, e0, _s0) = f_series(a, b, x)
        ret (v0, e0)
    }
    if x > 0.0f64 && size_b > size_a && size_a * lg(c_e() * x / size_b) < c_leps() + 7.0f64 {
        let (v1, e1, _s1) = f_series(a, b, x)
        ret (v1, e1)
    }
    if (abs_x < 5.0f64 && fa(bma) < 10.0f64 && abs_b < 10.0f64) || (b > 0.8f64 * fmax(fa(bma), 1.0f64) * abs_x) {
        let (kv, ke, _s2) = f_series(bma, b, 0.0f64 - x)
        let (v2, e2, _s3) = emx(x, c_eps() * fa(x), kv, ke)
        ret (v2, e2)
    }
    if x < -30.0f64 && fmax(fa(a), 1.0f64) * fmax(fa(1.0f64 + a - b), 1.0f64) < 0.99f64 * fa(x) {
        let (v3, e3) = f_asymp_negx(a, b, x)
        ret (v3, e3)
    }
    if x > 100.0f64 && fmax(fa(bma), 1.0f64) * fmax(fa(1.0f64 - a), 1.0f64) < 0.99f64 * fa(x) {
        let (v4, e4) = f_asymp_posx(a, b, x)
        ret (v4, e4)
    }
    if x > 0.0f64 && !(bma_integer && bma > 0.0f64) {
        let (v5, e5) = f_u(ar, a, b, x)
        ret (v5, e5)
    }
    if x < 0.0f64 {
        let (v6, e6, _s6) = f_series(b - a, b, 0.0f64 - x)
        let kf = ex(x)
        ret (v6 * kf, e6 * kf)
    }
    let (v7, e7, _s7) = f_series(a, b, x)
    ret (v7, e7)
}

// gsl_sf_hyperg_1F1_int_e
fn f_int_e(ar: *mem.Arena, a: i64, b: i64, x: f64) -> (f64, f64) {
    let af = f64(a)
    let bf = f64(b)
    if x == 0.0f64 { ret (1.0f64, 0.0f64) }
    if a == b {
        let (v0, e0, _s0) = exp_e(x)
        ret (v0, e0)
    }
    if b == 0i64 { ret (c_nan(), c_nan()) }
    if a == 0i64 { ret (1.0f64, 0.0f64) }
    if b < 0i64 && (a < b || a > 0i64) { ret (c_nan(), c_nan()) }
    if x > 100.0f64 && fmax(1.0f64, fa(bf - af)) * fmax(1.0f64, fa(1.0f64 - af)) < 0.5f64 * x {
        let (v1, e1) = f_asymp_posx(af, bf, x)
        ret (v1, e1)
    }
    if x < -100.0f64 && fmax(1.0f64, fa(af)) * fmax(1.0f64, fa(1.0f64 + af - bf)) < 0.5f64 * fa(x) {
        let (v2, e2) = f_asymp_negx(af, bf, x)
        ret (v2, e2)
    }
    if a < 0i64 && b < 0i64 {
        let (v3, e3) = f_ab_negint(a, b, x)
        ret (v3, e3)
    }
    if a < 0i64 && b > 0i64 {
        let (kv, ke) = f_ab_posint(ar, b - a, b, 0.0f64 - x)
        let (v4, e4, _s4) = emx(x, c_eps() * fa(x), kv, ke)
        ret (v4, e4)
    }
    let (v5, e5) = f_ab_posint(ar, a, b, x)
    ret (v5, e5)
}

// gsl_sf_hyperg_1F1_e
fn f_e(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    let thr = 100.0f64 * c_eps()
    let bma = b - a
    let rinta = fl(a + 0.5f64)
    let rintb = fl(b + 0.5f64)
    let rintbma = fl(bma + 0.5f64)
    let a_integer = fa(a - rinta) < thr && rinta > -2147483648.0f64 && rinta < c_imax()
    let b_integer = fa(b - rintb) < thr && rintb > -2147483648.0f64 && rintb < c_imax()
    let bma_integer = fa(bma - rintbma) < thr && rintbma > -2147483648.0f64 && rintbma < c_imax()
    let b_neg_integer = b < -0.1f64 && b_integer
    let a_neg_integer = a < -0.1f64 && a_integer
    let bma_neg_integer = bma < -0.1f64 && bma_integer
    if x == 0.0f64 { ret (1.0f64, 0.0f64) }
    if b == 0.0f64 { ret (c_nan(), c_nan()) }
    if a == 0.0f64 { ret (1.0f64, 0.0f64) }
    if a == b {
        let (v0, e0, _s0) = exp_e(x)
        ret (v0, e0)
    }
    if fa(b) < thr && fa(a) < thr {
        let (xv, xe) = expm1_e(x)
        var sa = -1.0f64
        if a > 0.0f64 { sa = 1.0f64 }
        var sb = -1.0f64
        if b > 0.0f64 { sb = 1.0f64 }
        let lnab = lg(fa(a / b))
        let (hv, he, _s1) = emx(lnab, c_eps() * fa(lnab), sa * sb * xv, xe)
        var rv = 1.0f64 + hv
        if hv == c_dmax() { rv = hv }
        ret (rv, he)
    }
    if fa(b) < thr && fa(x * a) < 1.0f64 {
        let m_arg = 1.0f64 / (0.5f64 * b)
        let (fv, fe) = f_renorm_b0(ar, a, x)
        let mv = m_arg * (0.5f64 * fv)
        let me = fa(2.0f64 * c_eps() * m_arg * (0.5f64 * fv)) + fa(0.5f64 * fe * m_arg) + 2.0f64 * c_eps() * fa(mv)
        ret (mv, me)
    }
    if a_integer && b_integer {
        let (v2, e2) = f_int_e(ar, i64(rinta), i64(rintb), x)
        ret (v2, e2)
    }
    if b_neg_integer && !(a_neg_integer && a > b) { ret (c_nan(), c_nan()) }
    if a_neg_integer {
        let (v3, e3) = f_a_negint_lag(i64(rinta), b, x)
        ret (v3, e3)
    }
    if b > 0.0f64 {
        if -1.0f64 <= a && a <= 1.0f64 {
            let (v4, e4) = f_small_a_bgt0(ar, a, b, x)
            ret (v4, e4)
        }
        if bma_neg_integer {
            let (kv, ke) = f_a_negint_lag(i64(rintbma), b, 0.0f64 - x)
            let (v5, e5, _s5) = emx(x, c_eps() * fa(x), kv, ke)
            ret (v5, e5)
        }
        if a < 0.0f64 && fa(x) < 2.0f64 * c_lmax() {
            let (kv2, ke2) = f_ab_pos(ar, b - a, b, 0.0f64 - x)
            let (v6, e6, _s6) = emx(x, c_eps() * fa(x), kv2, ke2)
            ret (v6, e6)
        }
        if a > 0.0f64 {
            let (v7, e7) = f_ab_pos(ar, a, b, x)
            ret (v7, e7)
        }
        let (v8, e8, _s8) = f_series(a, b, x)
        ret (v8, e8)
    }
    if bma_neg_integer && x < 0.0f64 {
        var kv3 = 0.0f64
        var ke3 = 0.0f64
        if a < 0.0f64 {
            let (pv, pe) = f_a_negint_poly(i64(rintbma), b, 0.0f64 - x)
            kv3 = pv
            ke3 = pe
        } else {
            let (pv2, pe2) = f_a_negint_lag(i64(rintbma), b, 0.0f64 - x)
            kv3 = pv2
            ke3 = pe2
        }
        let (v9, e9, _s9) = emx(x, c_eps() * fa(x), kv3, ke3)
        ret (v9, e9)
    }
    if a > 0.0f64 {
        let (kv4, ke4) = f_ab_neg(ar, b - a, b, 0.0f64 - x)
        let (v10, e10, _s10) = emx(x, c_eps() * fa(x), kv4, ke4)
        ret (v10, e10)
    }
    let (v11, e11) = f_ab_neg(ar, a, b, x)
    ret (v11, e11)
}

// ---- hyperg_U.c ----

fn ithr() -> f64 { ret 1000.0f64 * c_eps() }

fn series_ok(a: f64, b: f64, x: f64) -> bool {
    ret (fa(a) < 5.0f64 && b < 5.0f64 && x < 2.0f64) || (fa(a) < 10.0f64 && b < 10.0f64 && x < 1.0f64)
}

fn asymp_ok(a: f64, b: f64, x: f64) -> bool {
    ret fmax(fa(a), 1.0f64) * fmax(fa(1.0f64 + a - b), 1.0f64) < 0.99f64 * fa(x)
}

fn u_lnu_beq2a(a: f64, x: f64) -> (f64, f64) {
    let lx = lg(x)
    let nu = a - 0.5f64
    let lnpre = 0.5f64 * (x - c_lnpi()) - nu * lx
    let (kv, ke) = gu.bessel_lnknu(nu, 0.5f64 * x)
    let v = lnpre + kv
    var e = 2.0f64 * c_eps() * (fa(0.5f64 * x) + 0.5f64 * c_lnpi() + fa(nu * lx))
    e += ke
    e += 2.0f64 * c_eps() * fa(v)
    ret (v, e)
}

// hyperg_U_CF1: (u_{N+1}/u_N, iteration count)
fn u_cf1(a: f64, b: f64, nn: i64, x: f64) -> (f64, i64) {
    let big = c_smax()
    let nf = f64(nn)
    var n = 1i64
    var anm2 = 1.0f64
    var bnm2 = 0.0f64
    var anm1 = 0.0f64
    var bnm1 = 1.0f64
    let a1 = 0.0f64 - (a + nf)
    let b1 = b - 2.0f64 * a - x - 2.0f64 * (nf + 1.0f64)
    var an = b1 * anm1 + a1 * anm2
    var bn = b1 * bnm1 + a1 * bnm2
    var fq = an / bn
    while n < 20000i64 {
        n += 1i64
        let kf = f64(n)
        anm2 = anm1
        bnm2 = bnm1
        anm1 = an
        bnm1 = bn
        let aq = 0.0f64 - (a + nf + kf - b) * (a + nf + kf - 1.0f64)
        let bq = b - 2.0f64 * a - x - 2.0f64 * (nf + kf)
        an = bq * anm1 + aq * anm2
        bn = bq * bnm1 + aq * bnm2
        if fa(an) > big || fa(bn) > big {
            an = an / big
            bn = bn / big
            anm1 = anm1 / big
            bnm1 = bnm1 / big
            anm2 = anm2 / big
            bnm2 = bnm2 / big
        }
        let old_fn = fq
        fq = an / bn
        let del = old_fn / fq
        if fa(del - 1.0f64) < 10.0f64 * c_eps() { break }
    }
    ret (fq, n)
}

fn d9chu(a: f64, b: f64, x: f64) -> (f64, f64) {
    let eps8 = 8.0f64 * c_eps()
    var aa0 = 1.0f64
    var aa1 = 0.0f64
    var aa2 = 0.0f64
    var aa3 = 0.0f64
    var bb0 = 1.0f64
    var bb1 = 0.0f64
    var bb2 = 0.0f64
    var bb3 = 0.0f64
    let bp = 1.0f64 + a - b
    let ab = a * bp
    var ct2 = 2.0f64 * (x - ab)
    let sab = a + bp
    var ct3 = sab + 1.0f64 + ab
    var anbn = ct3 + sab + 3.0f64
    var ct1 = 1.0f64 + 2.0f64 * x / anbn
    bb1 = 1.0f64 + 2.0f64 * x / ct3
    aa1 = 1.0f64 + ct2 / ct3
    bb2 = 1.0f64 + 6.0f64 * ct1 * x / ct3
    aa2 = 1.0f64 + 6.0f64 * ab / anbn + 3.0f64 * ct1 * ct2 / ct3
    var i = 4i64
    while i < 500i64 {
        let x2i1 = f64(2i64 * i - 3i64)
        ct1 = x2i1 / (x2i1 - 2.0f64)
        anbn += x2i1 + sab
        ct2 = (x2i1 - 1.0f64) / anbn
        let c2 = x2i1 * ct2 - 1.0f64
        let d1z = 2.0f64 * x2i1 * x / anbn
        ct3 = sab * ct2
        let g1 = d1z + ct1 * (c2 + ct3)
        let g2v = d1z - c2
        let g3 = ct1 * (1.0f64 - ct3 - 2.0f64 * ct2)
        bb3 = g1 * bb2 + g2v * bb1 + g3 * bb0
        aa3 = g1 * aa2 + g2v * aa1 + g3 * aa0
        if fa(aa3 * bb0 - aa0 * bb3) < eps8 * fa(bb3 * bb0) { break }
        aa0 = aa1
        bb0 = bb1
        aa1 = aa2
        bb1 = bb2
        aa2 = aa3
        bb2 = bb3
        i += 1i64
    }
    let v = aa3 / bb3
    ret (v, 8.0f64 * c_eps() * fa(v))
}

fn u_zau_asymp(a: f64, b: f64, x: f64) -> (f64, f64) {
    let ap = a
    let bp = 1.0f64 + a - b
    let rintap = fl(ap + 0.5f64)
    let rintbp = fl(bp + 0.5f64)
    let ap_neg_int = ap < 0.0f64 && fa(ap - rintap) < ithr()
    let bp_neg_int = bp < 0.0f64 && fa(bp - rintbp) < ithr()
    if ap_neg_int || bp_neg_int {
        let mxi = -1.0f64 / x
        let nmax = 0.0f64 - f64(i64(fmin(ap, bp) - 0.1f64))
        var tn = 1.0f64
        var sum = 1.0f64
        var n = 1.0f64
        var sum_err = 0.0f64
        while n <= nmax {
            let apn = ap + n - 1.0f64
            let bpn = bp + n - 1.0f64
            tn = tn * (((apn / n) * mxi) * bpn)
            sum += tn
            sum_err += 2.0f64 * c_eps() * fa(tn)
            n += 1.0f64
        }
        ret (sum, sum_err + 2.0f64 * c_eps() * (fa(nmax) + 1.0f64) * fa(sum))
    }
    let (v, e) = d9chu(a, b, x)
    ret (v, e)
}

fn u_finite_sum(ar: *mem.Arena, nn: i64, a: f64, b: f64, x: f64, xeps: f64) -> (f64, f64) {
    if nn <= 0i64 {
        var t_val = 1.0f64
        var t_err = 0.0f64
        var sum_val = 1.0f64
        var sum_err = 0.0f64
        var i = 1i64
        while i <= 0i64 - nn {
            let xi1 = f64(i - 1i64)
            let mult = (a + xi1) * x / ((b + xi1) * (xi1 + 1.0f64))
            t_val = t_val * mult
            t_err += fa(mult) * t_err + fa(t_val) * 8.0f64 * 2.0f64 * c_eps()
            sum_val += t_val
            sum_err += t_err
            i += 1i64
        }
        let (pv, pe) = gp.poch(ar, 1.0f64 + a - b, 0.0f64 - a)
        let v = sum_val * pv
        var e = fa(sum_val) * pe + sum_err * fa(pv)
        e += fa(pv) * (fa(f64(nn)) + 2.0f64) * c_eps() * fa(sum_val)
        e += 2.0f64 * c_eps() * fa(v)
        e = e * 2.0f64
        ret (v, e)
    }
    let m = nn - 2i64
    if m < 0i64 { ret (0.0f64, 0.0f64) }
    var t_val = 1.0f64
    var t_err = 0.0f64
    var sum_val = 1.0f64
    var sum_err = 0.0f64
    var i = 1i64
    while i <= m {
        let fi = f64(i)
        let mult = (a - b + fi) * x / ((1.0f64 - b + fi) * fi)
        t_val = t_val * mult
        t_err += t_err * fa(mult) + fa(t_val) * 8.0f64 * 2.0f64 * c_eps()
        sum_val += t_val
        sum_err += t_err
        i += 1i64
    }
    let (gbv, gbe) = g2.e_gamma(b - 1.0f64)
    let (grv, gre) = gp.e_gammainv(a)
    let (pwv, pwe) = ge.e_pow_int(x, 1i64 - nn)
    let pev = pwv * xeps
    let pee = pwe * fa(xeps) + 2.0f64 * c_eps() * fa(pev)
    let cv = gbv * grv * pev
    let ce = gbe * fa(grv * pev) + gre * fa(gbv * pev) + fa(gbv * grv) * pee + 2.0f64 * c_eps() * fa(cv)
    let v2 = sum_val * cv
    var e2 = fa(sum_val) * ce + sum_err * fa(cv)
    e2 += 2.0f64 * c_eps() * (f64(m) + 2.0f64) * fa(v2)
    e2 = e2 * 2.0f64
    ret (v2, e2)
}

fn u_inf_stable(ar: *mem.Arena, nn: i64, a: f64, bint: f64, b: f64, beps: f64, x: f64, xeps: f64, sumv: f64, sume: f64) -> (f64, f64) {
    let eps2 = 2.0f64 * c_eps()
    var istrt = 0i64
    if nn < 1i64 { istrt = 1i64 - nn }
    let xi = f64(istrt)
    let (gv, ge1) = gp.e_gammainv(1.0f64 + a - b)
    let (pwv, pwe) = ge.e_pow_int(x, istrt)
    let sarg = beps * c_pi()
    var sfact = 1.0f64
    if sarg != 0.0f64 { sfact = sarg / math.sin[f64](sarg) }
    var sgn = 1.0f64
    if odd(nn) { sgn = -1.0f64 }
    let fv = sfact * sgn * gv * pwv
    let fe = fa(gv) * pwe + fa(pwv) * ge1 + 2.0f64 * c_eps() * fa(fv)
    let (pav, pae) = gp.poch(ar, a, xi)
    let (g1v, g1e) = gp.e_gammainv(xi + 1.0f64)
    let (gnv, gne) = gp.e_gammainv(bint + xi)
    let (pbv, pbe) = gp.poch(ar, a, xi - beps)
    let (gxv, gxe) = gp.e_gammainv(xi + 1.0f64 - beps)
    var b0v = fv * pbv * gnv * gxv
    var b0e = fa(fv * pbv * gnv) * gxe + fa(fv * pbv * gxv) * gne + fa(fv * gnv * gxv) * pbe + fa(pbv * gnv * gxv) * fe + 2.0f64 * c_eps() * fa(b0v)
    let (dgv, dge) = gp.e_gammainv(b + xi)
    var a0v = fv * pav * dgv * g1v / beps
    var a0e = fa(fv * pav * dgv / beps) * g1e + fa(fv * pav * g1v / beps) * dge + fa(fv * dgv * g1v / beps) * pae + fa(pav * dgv * g1v / beps) * fe + 2.0f64 * c_eps() * fa(a0v)
    b0v = xeps * b0v / beps
    b0e = fa(xeps / beps) * b0e + 4.0f64 * c_eps() * fa(b0v)
    var dv = sumv + a0v - b0v
    var de = sume + a0e + b0e + 2.0f64 * c_eps() * (fa(sumv) + fa(a0v) + fa(b0v))
    var tv = 0.0f64
    var i = 1i64
    while i < 2000i64 {
        let xii = f64(istrt + i)
        let xii1 = f64(istrt + i - 1i64)
        let a0m = (a + xii1) * x / ((b + xii1) * xii)
        let b0m = (a + xii1 - beps) * x / ((bint + xii1) * (xii - beps))
        a0v = a0v * a0m
        a0e += fa(a0m) * a0e
        b0v = b0v * b0m
        b0e += fa(b0m) * b0e
        tv = a0v - b0v
        let te = a0e + b0e
        dv += tv
        de += te
        if fa(tv) < eps2 * fa(dv) { break }
        i += 1i64
    }
    var er = 2.0f64 * de
    er += 2.0f64 * fa(tv)
    er += 4.0f64 * c_eps() * (f64(i) + 2.0f64) * fa(dv)
    er = er * 2.0f64
    ret (dv, er)
}

fn u_inf_simple(ar: *mem.Arena, nn: i64, a: f64, bint: f64, b: f64, beps: f64, x: f64, xeps: f64, sumv: f64, sume: f64) -> (f64, f64) {
    let eps2 = 2.0f64 * c_eps()
    var istrt = 0i64
    if nn < 1i64 { istrt = 1i64 - nn }
    let xi = f64(istrt)
    let (pwv, pwe) = ge.e_pow_int(x, istrt)
    let sarg = beps * c_pi()
    var sfact = 1.0f64
    if sarg != 0.0f64 { sfact = sarg / math.sin[f64](sarg) }
    var sgn = 1.0f64
    if odd(nn) { sgn = -1.0f64 }
    let fv = sfact * sgn * pwv
    let fe = fa(pwe) + 2.0f64 * c_eps() * fa(fv)
    let (pav, pae) = gp.poch(ar, a, xi)
    let (g1v, g1e) = gp.e_gammainv(xi + 1.0f64)
    let (gnv, gne) = gp.e_gammainv(bint + xi)
    let (pbv, pbe) = gp.poch(ar, a, xi - beps)
    let (gxv, gxe) = gp.e_gammainv(xi + 1.0f64 - beps)
    let (pplain, _pe2) = gp.poch(ar, 1.0f64 + a - b, xi - 1.0f64 + b - beps)
    let (gav, _gae) = gp.e_gammainv(a)
    let xx = sfact * sgn * pwv * pplain * gav
    var b0v = xx * gnv * gxv
    var b0e = fa(fv * pbv * gnv) * gxe + fa(fv * pbv * gxv) * gne + fa(fv * gnv * gxv) * pbe + fa(pbv * gnv * gxv) * fe + 2.0f64 * c_eps() * fa(b0v)
    let (gv, ge1) = gp.e_gammainv(1.0f64 + a - b)
    let (dgv, dge) = gp.e_gammainv(b + xi)
    var a0v = fv * gv * pav * dgv * g1v / beps
    var a0e = fa(fv * pav * dgv * g1v / beps) * ge1 + fa(fv * gv * dgv * g1v / beps) * pae + fa(fv * gv * pav * g1v / beps) * dge + fa(fv * gv * pav * dgv / beps) * g1e + fa(pav * gv * dgv * g1v / beps) * fe + 2.0f64 * c_eps() * fa(a0v)
    b0v = xeps * b0v / beps
    b0e = fa(xeps / beps) * b0e + 4.0f64 * c_eps() * fa(b0v)
    var dv = sumv + a0v - b0v
    var de = sume + a0e + b0e + 2.0f64 * c_eps() * (fa(sumv) + fa(a0v) + fa(b0v))
    var tv = 0.0f64
    var i = 1i64
    while i < 2000i64 {
        let xii = f64(istrt + i)
        let xii1 = f64(istrt + i - 1i64)
        let a0m = (a + xii1) * x / ((b + xii1) * xii)
        let b0m = (a + xii1 - beps) * x / ((bint + xii1) * (xii - beps))
        a0v = a0v * a0m
        a0e += fa(a0m) * a0e
        b0v = b0v * b0m
        b0e += fa(b0m) * b0e
        tv = a0v - b0v
        let te = a0e + b0e
        dv += tv
        de += te
        if tv - tv != 0.0f64 || fa(tv) < eps2 * fa(dv) { break }
        i += 1i64
    }
    var er = 2.0f64 * de
    er += 2.0f64 * fa(tv)
    er += 4.0f64 * c_eps() * (f64(i) + 2.0f64) * fa(dv)
    er = er * 2.0f64
    ret (dv, er)
}

fn u_inf_improved(ar: *mem.Arena, nn: i64, a: f64, bint: f64, b: f64, beps: f64, x: f64, xeps: f64, sumv: f64, sume: f64) -> (f64, f64) {
    let eps2 = 2.0f64 * c_eps()
    let lnx = lg(x)
    var istrt = 0i64
    if nn < 1i64 { istrt = 1i64 - nn }
    let xi = f64(istrt)
    let (gv, ge1) = gp.e_gammainv(1.0f64 + a - b)
    let (pwv, pwe) = ge.e_pow_int(x, istrt)
    let sarg = beps * c_pi()
    var sfact = 1.0f64
    if sarg != 0.0f64 { sfact = sarg / math.sin[f64](sarg) }
    var sgn = 1.0f64
    if odd(nn) { sgn = -1.0f64 }
    let fv = sfact * sgn * gv * pwv
    let fe = fa(gv) * pwe + fa(pwv) * ge1 + 2.0f64 * c_eps() * fa(fv)
    let (pav, pae) = gp.poch(ar, a, xi)
    let (g1v, g1e) = gp.e_gammainv(xi + 1.0f64)
    let (gnv, gne) = gp.e_gammainv(bint + xi)
    let (pbv, pbe) = gp.poch(ar, a, xi - beps)
    let (gxv, gxe) = gp.e_gammainv(xi + 1.0f64 - beps)
    var b0v = fv * pbv * gnv * gxv
    var b0e = fa(fv * pbv * gnv) * gxe + fa(fv * pbv * gxv) * gne + fa(fv * gnv * gxv) * pbe + fa(pbv * gnv * gxv) * fe + 2.0f64 * c_eps() * fa(b0v)
    let (p1av, p1ae) = gp.pochrel(ar, a + xi, 0.0f64 - beps)
    let (p1iv, p1ie) = gp.pochrel(ar, xi + 1.0f64 - beps, beps)
    let (p1bv, p1be) = gp.pochrel(ar, b + xi, 0.0f64 - beps)
    let c0t1v = beps * p1av * p1iv
    let c0t1e = fa(beps) * fa(p1av) * p1ie + fa(beps) * fa(p1iv) * p1ae + 2.0f64 * c_eps() * fa(c0t1v)
    let c0t2v = 0.0f64 - p1bv + p1av - p1iv + c0t1v
    let c0t2e = p1be + p1ae + p1ie + c0t1e + 2.0f64 * c_eps() * fa(c0t2v)
    var c0v = fv * pav * gnv * g1v * c0t2v
    var c0e = fa(fv * pav * gnv * g1v) * c0t2e + fa(fv * pav * gnv * c0t2v) * g1e + fa(fv * pav * g1v * c0t2v) * gne + fa(fv * gnv * g1v * c0t2v) * pae + fa(pav * gnv * g1v * c0t2v) * fe + 2.0f64 * c_eps() * fa(c0v)
    let (dxv, dxe, _ds) = exprel_e(0.0f64 - beps * lnx)
    let xe1v = lnx * dxv
    let xe1e = 2.0f64 * c_eps() * (1.0f64 + fa(beps * lnx)) * fa(dxv) + fa(lnx) * dxe + 2.0f64 * c_eps() * fa(xe1v)
    var dv = sumv + c0v + xe1v * b0v
    var de = sume + c0e + fa(xe1v) * b0e + xe1e * fa(b0v) + fa(b0v * lnx) * dxe + 2.0f64 * c_eps() * (fa(sumv) + fa(c0v) + fa(xe1v * b0v))
    let xn = f64(nn)
    var tv = 0.0f64
    var i = 1i64
    while i < 2000i64 {
        let xii = f64(istrt + i)
        let xii1 = f64(istrt + i - 1i64)
        let tmp = (a - 1.0f64) * (xn + 2.0f64 * xii - 1.0f64) + xii * (xii - beps)
        let b0m = (a + xii1 - beps) * x / ((xn + xii1) * (xii - beps))
        let c0m1 = (a + xii1) * x / ((b + xii1) * xii)
        let c0m2 = tmp / (xii * (b + xii1) * (a + xii1 - beps))
        b0v = b0v * b0m
        b0e += fa(b0m) * b0e + fa(b0v) * 8.0f64 * 2.0f64 * c_eps()
        c0v = c0m1 * c0v - c0m2 * b0v
        c0e = fa(c0m1) * c0e + fa(c0m2) * b0e + fa(c0v) * 8.0f64 * 2.0f64 * c_eps() + fa(b0v * c0m2) * 16.0f64 * 2.0f64 * c_eps()
        tv = c0v + xe1v * b0v
        var te = c0e + fa(xe1v) * b0e
        te += fa(b0v * lnx) * dxe
        te += fa(b0v) * xe1e
        dv += tv
        de += te
        if fa(tv) < eps2 * fa(dv) { break }
        i += 1i64
    }
    var er = 2.0f64 * de
    er += 2.0f64 * fa(tv)
    er += 4.0f64 * c_eps() * (f64(i) + 2.0f64) * fa(dv)
    er = er * 2.0f64
    ret (dv, er)
}

fn u_series(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    let sqrt_eps = c_sqrt2() * c_seps()
    var bint = fl(b + 0.5f64)
    if b < 0.0f64 { bint = math.ceil[f64](b - 0.5f64) }
    var beps = b - bint
    let a_beps = a - beps
    let r_a_beps = fl(a_beps + 0.5f64)
    let a_beps_int = fa(a_beps - r_a_beps) < ithr()
    if a_beps_int && a_beps <= 0.0f64 {
        beps = beps - 1.0f64 + fl(a_beps)
        bint = bint + 1.0f64 - fl(a_beps)
    }
    if fa(1.0f64 + a - b) < sqrt_eps {
        let lnr = 0.0f64 - a * lg(x)
        let (v, e, _s) = exp_e(lnr)
        ret (v, e + 2.0f64 * sqrt_eps * fa(v))
    }
    let nn = i64(bint)
    let lnx = lg(x)
    let xeps = ex(0.0f64 - beps * lnx)
    let (sv, se) = u_finite_sum(ar, nn, a, b, x, xeps)
    if fa(xeps - 1.0f64) > 0.5f64 {
        let (v1, e1) = u_inf_stable(ar, nn, a, bint, b, beps, x, xeps, sv, se)
        ret (v1, e1)
    }
    if 1.0f64 + a - b < 0.0f64 && 1.0f64 + a - b == fl(1.0f64 + a - b) && beps != 0.0f64 {
        let (v2, e2) = u_inf_simple(ar, nn, a, bint, b, beps, x, xeps, sv, se)
        ret (v2, e2)
    }
    let (v3, e3) = u_inf_improved(ar, nn, a, bint, b, beps, x, xeps, sv, se)
    ret (v3, e3)
}

fn u_small_ab(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    if a == -1.0f64 {
        let v = 0.0f64 - b + x
        ret (v, 2.0f64 * c_eps() * (fa(b) + fa(x)) + 2.0f64 * c_eps() * fa(v))
    }
    if a == 0.0f64 { ret (1.0f64, 0.0f64) }
    if asymp_ok(a, b, x) {
        let p = math.pow[f64](x, 0.0f64 - a)
        let (av, ae) = u_zau_asymp(a, b, x)
        let v2 = av * p
        var e2 = ae * p
        e2 += fa(av) * c_eps() * fa(a) * p
        e2 += 2.0f64 * c_eps() * fa(v2)
        ret (v2, e2)
    }
    let (v3, e3) = u_series(ar, a, b, x)
    ret (v3, e3)
}

// hyperg_U_small_a_bgt0: (value, error, ln_multiplier)
fn u_small_a_bgt0(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64, f64) {
    if a == 0.0f64 { ret (1.0f64, 0.0f64, 0.0f64) }
    if (b > 5000.0f64 && x < 0.90f64 * fa(b)) || (b > 500.0f64 && x < 0.50f64 * fa(b)) {
        let (v, e, lm) = u_large_b(a, b, x)
        ret (v, e, lm)
    }
    if b > 15.0f64 {
        let eps = b - fl(b)
        let b0 = 1.0f64 + eps
        let (u0v, u0e) = u_small_ab(ar, a, b0, x)
        let (u1v, u1e) = u_small_ab(ar, a, b0 + 1.0f64, x)
        var ubm1 = u0v
        var ub = u1v
        var bp = b0 + 1.0f64
        while bp < b - 0.1f64 {
            let ubp1 = ((1.0f64 + a - bp) * ubm1 + (bp + x - 1.0f64) * ub) / x
            ubm1 = ub
            ub = ubp1
            bp += 1.0f64
        }
        var er = (fa(u0e / u0v) + fa(u1e / u1v)) * fa(ub)
        er += 2.0f64 * c_eps() * (fa(b - b0) + 1.0f64) * fa(ub)
        ret (ub, er, 0.0f64)
    }
    let (v2, e2) = u_small_ab(ar, a, b, x)
    ret (v2, e2, 0.0f64)
}

// RESCALE_2
fn rescale2(u0: f64, u1: f64, factor: f64, count: i64) -> (f64, f64, i64) {
    let au0 = fa(u0)
    if au0 > factor { ret (u0 / factor, u1 / factor, count + 1i64) }
    if au0 < 1.0f64 / factor { ret (u0 * factor, u1 * factor, count - 1i64) }
    ret (u0, u1, count)
}

// hyperg_U_int_bge1: (value, error, e10)
fn u_int_bge1(ar: *mem.Arena, a: i64, b: i64, x: f64) -> (f64, f64, i64) {
    let af = f64(a)
    let bf = f64(b)
    if a == 0i64 { ret (1.0f64, 0.0f64, 0i64) }
    if a == -1i64 {
        let v = 0.0f64 - bf + x
        ret (v, 2.0f64 * c_eps() * (fa(bf) + fa(x)) + 2.0f64 * c_eps() * fa(v), 0i64)
    }
    if b == a + 1i64 {
        let (v1, e1, n1, _s1) = exp_e10(0.0f64 - af * lg(x))
        ret (v1, e1, n1)
    }
    if asymp_ok(af, bf, x) {
        let lpv = 0.0f64 - af * lg(x)
        let lpe = 2.0f64 * c_eps() * fa(lpv)
        let (av, ae) = u_zau_asymp(af, bf, x)
        let (v2, e2, n2, _s2) = emx10(lpv, lpe, av, ae)
        ret (v2, e2, n2)
    }
    if series_ok(af, bf, x) && 1i64 + a - b > 0i64 {
        let (v3, e3) = u_series(ar, af, bf, x)
        ret (v3, e3, 0i64)
    }
    let scale = c_smax()
    if a < 0i64 {
        var scount = 0i64
        var uap1 = 1.0f64
        var ua = 0.0f64 - bf + x
        var ap = -1i64
        while ap > a {
            let apf = f64(ap)
            let uam1 = apf * (bf - apf - 1.0f64) * uap1 + (x + 2.0f64 * apf - bf) * ua
            uap1 = ua
            ua = uam1
            let (r0, r1, rc) = rescale2(ua, uap1, scale, scount)
            ua = r0
            uap1 = r1
            scount = rc
            ap -= 1i64
        }
        let lnscale = lg(scale)
        let lnmv = f64(scount) * lnscale
        let lnme = 2.0f64 * c_eps() * fa(lnmv)
        let ye = 4.0f64 * c_eps() * (fa(af) + 1.0f64) * fa(ua)
        let (v4, e4, n4, _s4) = emx10(lnmv, lnme, ua, ye)
        ret (v4, e4, n4)
    }
    if bf >= 2.0f64 * af + x {
        var scount = 0i64
        let (rav, rae, lm) = u_small_a_bgt0(ar, 1.0f64, bf, x)
        var uam1 = 1.0f64
        var ua = rav
        uam1 = uam1 * ex(0.0f64 - lm)
        var ap = 1i64
        while ap < a {
            let apf = f64(ap)
            let uap1 = 0.0f64 - (uam1 + (bf - 2.0f64 * apf - x) * ua) / (apf * (1.0f64 + apf - bf))
            uam1 = ua
            ua = uap1
            let (r0, r1, rc) = rescale2(ua, uam1, scale, scount)
            ua = r0
            uam1 = r1
            scount = rc
            ap += 1i64
        }
        let lnscale = lg(scale)
        let lnmv = lm + f64(scount) * lnscale
        let lnme = 2.0f64 * c_eps() * (fa(lm) + fa(f64(scount) * lnscale))
        var ye = fa(rae / rav) * fa(ua)
        ye += 2.0f64 * c_eps() * (fa(af) + 1.0f64) * fa(ua)
        let (v5, e5, n5, _s5) = emx10(lnmv, lnme, ua, ye)
        ret (v5, e5, n5)
    }
    if bf <= x {
        var scount = 0i64
        var atarget = 0i64
        var lnut = 0.0f64
        if b < a + 1i64 {
            atarget = b - 1i64
            lnut = 0.0f64 - f64(atarget) * lg(x)
        }
        let (ru, cf1c) = u_cf1(af, bf, 0i64, x)
        var ua = 1.0f64
        var uap1 = ru / af * ua
        var ap = a
        while ap > atarget {
            let apf = f64(ap)
            let uam1 = 0.0f64 - ((bf - 2.0f64 * apf - x) * ua + apf * (1.0f64 + apf - bf) * uap1)
            uap1 = ua
            ua = uam1
            let (r0, r1, rc) = rescale2(ua, uap1, scale, scount)
            ua = r0
            uap1 = r1
            scount = rc
            ap -= 1i64
        }
        if ua == 0.0f64 { ret (0.0f64, 0.0f64, 0i64) }
        let lnscl = 0.0f64 - f64(scount) * lg(scale)
        let lnpv = lnut + lnscl
        let lnpe = 2.0f64 * c_eps() * (fa(lnut) + fa(lnscl))
        let oue = 2.0f64 * (fa(f64(atarget - a)) + f64(cf1c) + 1.0f64) * c_eps() * fa(1.0f64 / ua)
        let (v6, e6, n6, _s6) = emx10(lnpv, lnpe, 1.0f64 / ua, oue)
        ret (v6, e6, n6)
    }
    var scount_for = 0i64
    var scount_bck = 0i64
    let a0 = 1i64
    let a1 = a0 + i64(math.ceil[f64](0.5f64 * (bf - x) - f64(a0)))
    var ua1_bck_val = 0.0f64
    var ua1_bck_err = 0.0f64
    let (ru2, cf1c2) = u_cf1(af, bf, 0i64, x)
    var ub = 1.0f64
    var ubp1 = ru2 / af * ub
    var apb = a
    while apb > a1 {
        let apf = f64(apb)
        let ubm1 = 0.0f64 - ((bf - 2.0f64 * apf - x) * ub + apf * (1.0f64 + apf - bf) * ubp1)
        ubp1 = ub
        ub = ubm1
        let (r0, r1, rc) = rescale2(ub, ubp1, scale, scount_bck)
        ub = r0
        ubp1 = r1
        scount_bck = rc
        apb -= 1i64
    }
    ua1_bck_val = ub
    ua1_bck_err = 2.0f64 * c_eps() * (fa(f64(a1 - a)) + f64(cf1c2) + 1.0f64) * fa(ub)
    var lmfv = 0.0f64
    var lmfe = 0.0f64
    var ua1_for_val = 0.0f64
    var ua1_for_err = 0.0f64
    if b == 2i64 * a1 && a1 > 1i64 {
        let (lv, le) = u_lnu_beq2a(f64(a1), x)
        lmfv = lv
        lmfe = le
        ua1_for_val = 1.0f64
        ua1_for_err = 0.0f64
    } else {
        if b == 2i64 * a1 - 1i64 && a1 > 1i64 {
            let (l00v, l00e) = u_lnu_beq2a(f64(a1) - 1.0f64, x)
            let (l12v, l12e) = u_lnu_beq2a(f64(a1), x)
            var u00v = 0.0f64
            var u00e = 0.0f64
            var u12v = 0.0f64
            var u12e = 0.0f64
            if l00v > l12v {
                lmfv = l00v
                lmfe = l00e
                u00v = 1.0f64
                u00e = 0.0f64
                let (qv, qe, _qs) = exp_err(l12v - lmfv, l12e + lmfe)
                u12v = qv
                u12e = qe
            } else {
                lmfv = l12v
                lmfe = l12e
                u12v = 1.0f64
                u12e = 0.0f64
                let (qv2, qe2, _qs2) = exp_err(l00v - lmfv, l00e + lmfe)
                u00v = qv2
                u00e = qe2
            }
            ua1_for_val = (x * u12v - u00v) / (2.0f64 * f64(a1) - 2.0f64)
            ua1_for_err = (fa(x) * u12e + u00e) / fa(2.0f64 * f64(a1) - 2.0f64)
            ua1_for_err += 2.0f64 * c_eps() * fa(ua1_for_val)
        } else {
            let (rav, rae, lml) = u_small_a_bgt0(ar, f64(a0), bf, x)
            var ua = rav
            var uam1 = 1.0f64 * ex(0.0f64 - lml)
            lmfv = lml
            lmfe = 0.0f64
            var apc = a0
            while apc < a1 {
                let apf = f64(apc)
                let uap1 = 0.0f64 - (uam1 + (bf - 2.0f64 * apf - x) * ua) / (apf * (1.0f64 + apf - bf))
                uam1 = ua
                ua = uap1
                let (r0, r1, rc) = rescale2(ua, uam1, scale, scount_for)
                ua = r0
                uam1 = r1
                scount_for = rc
                apc += 1i64
            }
            ua1_for_val = ua
            ua1_for_err = fa(ua) * fa(rae / rav)
            ua1_for_err += 2.0f64 * c_eps() * (fa(f64(a1 - a0)) + 1.0f64) * fa(ua1_for_val)
        }
    }
    if ua1_bck_val == 0.0f64 { ret (0.0f64, 0.0f64, 0i64) }
    if ua1_for_val == 0.0f64 { ret (0.0f64, 2.2250738585072014e-308f64, 0i64) }
    let lns = f64(scount_for - scount_bck) * lg(scale)
    let lnfv = lg(fa(ua1_for_val))
    let lnfe = c_eps() + fa(ua1_for_err / ua1_for_val)
    let lnbv = lg(fa(ua1_bck_val))
    let lnbe = c_eps() + fa(ua1_bck_err / ua1_bck_val)
    let lnrv = lmfv + lnfv - lnbv + lns
    let lnre = lmfe + lnfe + lnbe + 2.0f64 * c_eps() * (fa(lmfv) + fa(lnfv) + fa(lnbv) + fa(lns))
    let sg = sgn1(ua1_for_val) * sgn1(ua1_bck_val)
    let (rv, re, rn, _rs) = exp_err_e10(lnrv, lnre)
    ret (rv * sg, re, rn)
}

// hyperg_U_bge1: (value, error, e10)
fn u_bge1(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64, i64) {
    let rinta = fl(a + 0.5f64)
    let a_neg_integer = a < 0.0f64 && fa(a - rinta) < ithr()
    let scale = c_smax()
    if a == 0.0f64 { ret (1.0f64, 0.0f64, 0i64) }
    if a_neg_integer && fa(rinta) < c_imax() {
        let n = 0i64 - i64(rinta)
        var sg = 1.0f64
        if odd(n) { sg = -1.0f64 }
        let (lv, le, _ls) = laguerre_n(n, b - 1.0f64, x)
        let (fv, fe) = g2.e_lnfact(usize(n))
        let (v0, e0, n0, _s0) = emx10(fv, fe, sg * lv, le)
        ret (v0, e0, n0)
    }
    if asymp_ok(a, b, x) {
        let lpv = 0.0f64 - a * lg(x)
        let lpe = 2.0f64 * c_eps() * fa(lpv)
        let (av, ae) = u_zau_asymp(a, b, x)
        let (v1, e1, n1, _s1) = emx10(lpv, lpe, av, ae)
        ret (v1, e1, n1)
    }
    if fa(a) <= 1.0f64 {
        let (rv, re, lmu) = u_small_a_bgt0(ar, a, b, x)
        let (v2, e2, n2, _s2) = emx10(lmu, 2.0f64 * c_eps() * fa(lmu), rv, re)
        ret (v2, e2, n2)
    }
    if series_ok(a, b, x) {
        let (v3, e3) = u_series(ar, a, b, x)
        ret (v3, e3, 0i64)
    }
    if a < 0.0f64 {
        let a0 = a - fl(a) - 1.0f64
        let b0 = b - fl(b) + 1.0f64
        var scount = 0i64
        let (r1v, r1e, lm0) = u_small_a_bgt0(ar, a0 + 1.0f64, b0, x)
        let (r0v, r0e, lm1) = u_small_a_bgt0(ar, a0, b0, x)
        var uap1 = r1v
        var ua = r0v
        let lmm = fmax(lm0, lm1)
        uap1 = uap1 * ex(lm0 - lmm)
        ua = ua * ex(lm1 - lmm)
        var ap = a0
        while ap > a + 0.1f64 {
            let uam1 = ap * (b0 - ap - 1.0f64) * uap1 + (x + 2.0f64 * ap - b0) * ua
            uap1 = ua
            ua = uam1
            let (q0, q1, qc) = rescale2(ua, uap1, scale, scount)
            ua = q0
            uap1 = q1
            scount = qc
            ap -= 1.0f64
        }
        if b < 2.0f64 {
            let lnscale = lg(scale)
            let lnmv = lmm + f64(scount) * lnscale
            let lnme = 2.0f64 * c_eps() * (fa(lmm) + f64(scount) * fa(lnscale))
            var ye = fa(r1e / r1v) * fa(ua)
            ye += fa(r0e / r0v) * fa(ua)
            ye += 2.0f64 * c_eps() * (fa(a - a0) + 1.0f64) * fa(ua)
            ye = ye * (fa(lm0 - lmm) + 1.0f64)
            ye = ye * (fa(lm1 - lmm) + 1.0f64)
            let (v4, e4, n4, _s4) = emx10(lnmv, lnme, ua, ye)
            ret (v4, e4, n4)
        }
        let err_mult = fa(b - b0) + fa(a - a0) + 1.0f64
        let lnscale = lg(scale)
        var ubm1 = ua
        var ub = (a * (b0 - a - 1.0f64) * uap1 + (a + x) * ua) / x
        var bp = b0 + 1.0f64
        while bp < b - 0.1f64 {
            let ubp1 = ((1.0f64 + a - bp) * ubm1 + (bp + x - 1.0f64) * ub) / x
            ubm1 = ub
            ub = ubp1
            let (q0, q1, qc) = rescale2(ub, ubm1, scale, scount)
            ub = q0
            ubm1 = q1
            scount = qc
            bp += 1.0f64
        }
        let lnmv = lmm + f64(scount) * lnscale
        let lnme = 2.0f64 * c_eps() * (fa(lmm) + fa(f64(scount) * lnscale))
        var ye = 2.0f64 * err_mult * fa(r1e / r1v) * fa(ub)
        ye += 2.0f64 * err_mult * fa(r0e / r0v) * fa(ub)
        ye += 2.0f64 * c_eps() * err_mult * fa(ub)
        ye = ye * (fa(lm0 - lmm) + 1.0f64)
        ye = ye * (fa(lm1 - lmm) + 1.0f64)
        let (v5, e5, n5, _s5) = emx10(lnmv, lnme, ub, ye)
        ret (v5, e5, n5)
    }
    if b >= 2.0f64 * a + x {
        var scount = 0i64
        let a0 = a - fl(a)
        let (rmv, rme, lm0) = u_small_a_bgt0(ar, a0 - 1.0f64, b, x)
        let (rav, rae, lm1) = u_small_a_bgt0(ar, a0, b, x)
        var uam1 = rmv
        var ua = rav
        let lmm = fmax(lm0, lm1)
        uam1 = uam1 * ex(lm0 - lmm)
        ua = ua * ex(lm1 - lmm)
        var ap = a0
        while ap < a - 0.1f64 {
            let uap1 = 0.0f64 - (uam1 + (b - 2.0f64 * ap - x) * ua) / (ap * (1.0f64 + ap - b))
            uam1 = ua
            ua = uap1
            let (q0, q1, qc) = rescale2(ua, uam1, scale, scount)
            ua = q0
            uam1 = q1
            scount = qc
            ap += 1.0f64
        }
        let lnscale = lg(scale)
        let lnmv = lmm + f64(scount) * lnscale
        let lnme = 2.0f64 * c_eps() * (fa(lmm) + fa(f64(scount) * lnscale))
        var ye = fa(rme / rmv) * fa(ua)
        ye += fa(rae / rav) * fa(ua)
        ye += 2.0f64 * c_eps() * (fa(a - a0) + 1.0f64) * fa(ua)
        ye = ye * (fa(lm0 - lmm) + 1.0f64)
        ye = ye * (fa(lm1 - lmm) + 1.0f64)
        let (v6, e6, n6, _s6) = emx10(lnmv, lnme, ua, ye)
        ret (v6, e6, n6)
    }
    if b <= x {
        let a0 = a - fl(a)
        var scount = 0i64
        let (ru, cf1c) = u_cf1(a, b, 0i64, x)
        let r = ru / a
        var ua = c_smin()
        var uap1 = r * ua
        var ap = a
        while ap > a0 + 0.1f64 {
            let uam1 = 0.0f64 - ((b - 2.0f64 * ap - x) * ua + ap * (1.0f64 + ap - b) * uap1)
            uap1 = ua
            ua = uam1
            let (q0, q1, qc) = rescale2(ua, uap1, scale, scount)
            ua = q0
            uap1 = q1
            scount = qc
            ap -= 1.0f64
        }
        let (u0v, u0e, lm0) = u_small_a_bgt0(ar, a0, b, x)
        let lnscale = lg(scale)
        let lnmv = lm0 - f64(scount) * lnscale
        let lnme = 2.0f64 * c_eps() * (fa(lm0) + fa(f64(scount) * lnscale))
        let yv = c_smin() * (u0v / ua)
        var ye = c_smin() * (u0e / fa(ua))
        ye += 2.0f64 * c_eps() * (fa(a0 - a) + f64(cf1c) + 1.0f64) * fa(yv)
        let (v7, e7, n7, _s7) = emx10(lnmv, lnme, yv, ye)
        ret (v7, e7, n7)
    }
    var scount_for = 0i64
    var scount_bck = 0i64
    let eps = a - fl(a)
    var a0 = eps
    if eps == 0.0f64 { a0 = 1.0f64 }
    let a1 = a0 + math.ceil[f64](0.5f64 * (b - x) - a0)
    let (ru2, cf1c2) = u_cf1(a, b, 0i64, x)
    let r2 = ru2 / a
    var ub = c_smin()
    var ubp1 = r2 * ub
    var apb = a
    while apb > a1 + 0.1f64 {
        let ubm1 = 0.0f64 - ((b - 2.0f64 * apb - x) * ub + apb * (1.0f64 + apb - b) * ubp1)
        ubp1 = ub
        ub = ubm1
        let (q0, q1, qc) = rescale2(ub, ubp1, scale, scount_bck)
        ub = q0
        ubp1 = q1
        scount_bck = qc
        apb -= 1.0f64
    }
    let ua1_bck = ub
    let (rmv2, rme2, lm0b) = u_small_a_bgt0(ar, a0 - 1.0f64, b, x)
    let (rav2, rae2, lm1b) = u_small_a_bgt0(ar, a0, b, x)
    var uam1c = rmv2
    var uac = rav2
    let lm_for = fmax(lm0b, lm1b)
    uam1c = uam1c * ex(lm0b - lm_for)
    uac = uac * ex(lm1b - lm_for)
    var apc = a0
    while apc < a1 - 0.1f64 {
        let uap1 = 0.0f64 - (uam1c + (b - 2.0f64 * apc - x) * uac) / (apc * (1.0f64 + apc - b))
        uam1c = uac
        uac = uap1
        let (q0, q1, qc) = rescale2(uac, uam1c, scale, scount_for)
        uac = q0
        uam1c = q1
        scount_for = qc
        apc += 1.0f64
    }
    let ua1_for = uac
    let lnscale = lg(scale)
    let lnmv = lm_for + f64(scount_for - scount_bck) * lnscale
    let lnme = 2.0f64 * c_eps() * (fa(lm_for) + fa(f64(scount_for - scount_bck)) * fa(lnscale))
    let yv = c_smin() * ua1_for / ua1_bck
    let ye = 2.0f64 * c_eps() * (fa(a - a0) + f64(cf1c2) + 1.0f64) * fa(yv)
    let (v8, e8, n8, _s8) = emx10(lnmv, lnme, yv, ye)
    ret (v8, e8, n8)
}

fn u_origin(ar: *mem.Arena, a: f64, b: f64) -> (f64, f64, i64) {
    let (r1v, r1e) = gp.e_gammainv(1.0f64 + a - b)
    let (r2v, r2e) = gp.e_gammainv(b)
    let factor = c_pi() / math.sin[f64](c_pi() * b)
    ret (factor * r1v * r2v, fa(factor) * (r1e + r2e), 0i64)
}

fn u_negx(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64, i64) {
    let a_int = a == fl(a)
    let b_int = b == fl(b)
    var t1 = 0.0f64
    var t1e = 0.0f64
    var t2 = 0.0f64
    var t2e = 0.0f64
    if b_int && b <= 0.0f64 && !(a_int && a <= 0.0f64 && a >= b) { ret (c_nan(), c_nan(), 0i64) }
    let (r1v, r1e) = gp.poch(ar, 1.0f64 + a - b, 0.0f64 - a)
    if r1v != 0.0f64 {
        let (mv, me) = f_e(ar, a, b, x)
        t1 = mv * r1v
        t1e = 2.0f64 * c_eps() * fa(t1) + fa(me * r1v) + fa(mv * r1e)
    }
    if b_int && b >= 2.0f64 && !(a_int && a <= b - 2.0f64) { ret (c_nan(), c_nan(), 0i64) }
    var r2v = 0.0f64
    var r2e = 0.0f64
    if !(a_int && a <= 0.0f64 && b >= 1.0f64) {
        let (pv, pe) = gp.poch(ar, a, 0.0f64 - (1.0f64 + a - b))
        r2v = pv
        r2e = pe
    }
    if r2v != 0.0f64 {
        let (mv2, me2) = f_e(ar, 1.0f64 + a - b, 2.0f64 - b, x)
        t2 = mv2 * r2v
        t2e = 2.0f64 * c_eps() * fa(t2) + fa(me2 * r2v) + fa(mv2 * r2e)
        if t2 != 0.0f64 {
            let x1mb = math.pow[f64](x, 1.0f64 - b)
            t2 = x1mb * t2
            t2e = fa(x1mb) * t2e
        }
    }
    let v = t1 + t2
    ret (v, 2.0f64 * c_eps() * fa(v) + (t1e + t2e), 0i64)
}

fn u_int_negx(ar: *mem.Arena, a: i64, b: i64, x: f64) -> (f64, f64, i64) {
    if a < b && b <= 0i64 {
        let z21z = math.pow[f64](x, 1.0f64 - f64(b))
        let (rv, re, _rn) = u_negx(ar, f64(1i64 + a - b), f64(2i64 - b), x)
        ret (z21z * rv, fa(z21z) * re, 0i64)
    }
    let (v, e, n) = u_negx(ar, f64(a), f64(b), x)
    ret (v, e, n)
}

// gsl_sf_hyperg_U_int_e10_e
fn u_int_e10(ar: *mem.Arena, a: i64, b: i64, x: f64) -> (f64, f64, i64) {
    if x == 0.0f64 && b >= 1i64 { ret (c_nan(), c_nan(), 0i64) }
    if x == 0.0f64 {
        let (v0, e0, n0) = u_origin(ar, f64(a), f64(b))
        ret (v0, e0, n0)
    }
    if x < 0.0f64 {
        let (v1, e1, n1) = u_int_negx(ar, a, b, x)
        ret (v1, e1, n1)
    }
    if b >= 1i64 {
        let (v2, e2, n2) = u_int_bge1(ar, a, b, x)
        ret (v2, e2, n2)
    }
    let ln_x = lg(x)
    let ap = 1i64 + a - b
    let bp = 2i64 - b
    let (uv, ue, un) = u_int_bge1(ar, ap, bp, x)
    let lnpv = (1.0f64 - f64(b)) * ln_x
    var lnpe = 2.0f64 * c_eps() * (fa(f64(b)) + 1.0f64) * fa(ln_x)
    lnpe += 2.0f64 * c_eps() * fa(1.0f64 - f64(b))
    let (v3, e3, n3, _s3) = emx10(lnpv + f64(un) * c_ln10(), lnpe, uv, ue)
    ret (v3, e3, n3)
}

// gsl_sf_hyperg_U_e10_e
fn u_e10(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64, i64) {
    let rinta = fl(a + 0.5f64)
    let rintb = fl(b + 0.5f64)
    let a_integer = fa(a - rinta) < ithr()
    let b_integer = fa(b - rintb) < ithr()
    if x == 0.0f64 && b >= 1.0f64 { ret (c_nan(), c_nan(), 0i64) }
    if a == 0.0f64 { ret (1.0f64, 0.0f64, 0i64) }
    if x == 0.0f64 {
        let (v0, e0, n0) = u_origin(ar, a, b)
        ret (v0, e0, n0)
    }
    if a_integer && b == a + 1.0f64 {
        let (pv, pe) = ge.e_pow_int(x, 0i64 - i64(a))
        ret (pv, pe, 0i64)
    }
    if a_integer && b_integer {
        let (v1, e1, n1) = u_int_e10(ar, i64(rinta), i64(rintb), x)
        ret (v1, e1, n1)
    }
    if x < 0.0f64 {
        let (v2, e2, n2) = u_negx(ar, a, b, x)
        ret (v2, e2, n2)
    }
    if b >= 1.0f64 {
        let (v3, e3, n3) = u_bge1(ar, a, b, x)
        ret (v3, e3, n3)
    }
    let lnx = lg(x)
    let lnpv = (1.0f64 - b) * lnx
    let lnpe = fa(lnx) * 2.0f64 * c_eps() * (1.0f64 + fa(b))
    let ap = 1.0f64 + a - b
    let bp = 2.0f64 - b
    let (uv, ue, un) = u_bge1(ar, ap, bp, x)
    let (v4, e4, n4, _s4) = emx10(lnpv + f64(un) * c_ln10(), lnpe, uv, ue)
    ret (v4, e4, n4)
}

// gsl_sf_hyperg_U_e, gsl_sf_hyperg_U_int_e
fn hyperg_u(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    let (v, e, n) = u_e10(ar, a, b, x)
    let (sv, se, _ss) = smash(v, e, n)
    ret (sv, se)
}

fn hyperg_u_int(ar: *mem.Arena, a: i64, b: i64, x: f64) -> (f64, f64) {
    let (v, e, n) = u_int_e10(ar, a, b, x)
    let (sv, se, _ss) = smash(v, e, n)
    ret (sv, se)
}

fn hyperg_1f1(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    let (v, e) = f_e(ar, a, b, x)
    ret (v, e)
}

fn hyperg_1f1_int(ar: *mem.Arena, a: i64, b: i64, x: f64) -> (f64, f64) {
    let (v, e) = f_int_e(ar, a, b, x)
    ret (v, e)
}

// gsl_sf_hyperg_2F0_e
fn hyperg_2f0(ar: *mem.Arena, a: f64, b: f64, x: f64) -> (f64, f64) {
    if x < 0.0f64 {
        let pre = math.pow[f64](-1.0f64 / x, a)
        let (uv, ue) = hyperg_u(ar, a, 1.0f64 + a - b, -1.0f64 / x)
        let v = pre * uv
        ret (v, c_eps() * fa(v) + pre * ue)
    }
    if x == 0.0f64 { ret (1.0f64, 0.0f64) }
    ret (c_nan(), c_nan())
}
