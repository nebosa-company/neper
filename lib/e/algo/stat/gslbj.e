// R gsl: Bessel J0, J1, Y0, Y1 and Jn (the continued-fraction, asymptotic-in-x and large-x branches) with gsl's error estimates: ports of specfunc/bessel_J0.c, bessel_J1.c, bessel_Y0.c,
// bessel_Y1.c, bessel_Jn.c and the helpers of bessel.c. The Taylor branch (x^2 < 10 (n+1) eps^(1/5), n >= 2) and the Olver branch (n > 50) of Jn are in gslnu (jn_full).
// Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.algo.stat.gslcheb as ch

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn mpi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn sqrt_eps() -> f64 { ret 1.4901161193847656e-08f64 }
fn root5_eps() -> f64 { ret 7.4009597974140505e-04f64 }

// gsl_sf_bessel_cos_pi4_e (cosine = true) and sin_pi4_e: (value, error)
fn pi4(y: f64, ep: f64, cosine: bool) -> (f64, f64) {
    let sy = math.sin[f64](y)
    let cy = math.cos[f64](y)
    let s = sy + cy
    let d = sy - cy
    let abs_sum = fa(cy) + fa(sy)
    var seps = 0.0f64
    var ceps = 0.0f64
    if fa(ep) < root5_eps() {
        let e2 = ep * ep
        seps = ep * (1.0f64 - e2 / 6.0f64 * (1.0f64 - e2 / 20.0f64))
        ceps = 1.0f64 - e2 / 2.0f64 * (1.0f64 - e2 / 12.0f64)
    }
    if !(fa(ep) < root5_eps()) {
        seps = math.sin[f64](ep)
        ceps = math.cos[f64](ep)
    }
    let r2 = 1.4142135623730950488f64
    var v = (ceps * d + seps * s) / r2
    if cosine { v = (ceps * s - seps * d) / r2 }
    var e = 2.0f64 * c_eps() * (fa(ceps) + fa(seps)) * abs_sum / r2
    if y > 1.0f64 / c_eps() {
        e *= 0.5f64 * y
    }
    if !(y > 1.0f64 / c_eps()) && y > 1.0f64 / sqrt_eps() {
        e *= 256.0f64 * y * sqrt_eps()
    }
    ret (v, e)
}

fn j0(x: f64) -> (f64, f64) {
    let y = fa(x)
    if y < 2.0f64 * sqrt_eps() { ret (1.0f64, y * y) }
    if y <= 4.0f64 {
        let (v, e) = ch.cvv_bessel_J0_bj0(0.125f64 * y * y - 1.0f64)
        ret (v, e)
    }
    let z = 32.0f64 / (y * y) - 1.0f64
    let (cav, cae) = ch.cvv_bessel_amp_phase__gsl_sf_bessel_amp_phase_bm0(z)
    let (ctv, _cte) = ch.cvv_bessel_amp_phase__gsl_sf_bessel_amp_phase_bth0(z)
    let (cpv, cpe) = pi4(y, ctv / y, true)
    let sqrty = math.sqrt[f64](y)
    let ampl = (0.75f64 + cav) / sqrty
    let v = ampl * cpv
    ret (v, fa(cpv) * cae / sqrty + fa(ampl) * cpe + c_eps() * fa(v))
}

fn j1(x: f64) -> (f64, f64) {
    let y = fa(x)
    if y == 0.0f64 { ret (0.0f64, 0.0f64) }
    if y < 2.0f64 * 2.2250738585072014e-308f64 { ret (0.0f64, 0.0f64) }
    if y < 2.0f64 * 1.4142135623730950488f64 * sqrt_eps() { ret (0.5f64 * x, 0.0f64) }
    if y < 4.0f64 {
        let (cv, ce) = ch.cvv_bessel_J1_bj1(0.125f64 * y * y - 1.0f64)
        ret (x * (0.25f64 + cv), fa(x * ce))
    }
    let z = 32.0f64 / (y * y) - 1.0f64
    let (cav, cae) = ch.cvv_bessel_amp_phase__gsl_sf_bessel_amp_phase_bm1(z)
    let (ctv, _cte) = ch.cvv_bessel_amp_phase__gsl_sf_bessel_amp_phase_bth1(z)
    let (spv, spe) = pi4(y, ctv / y, false)
    let sqrty = math.sqrt[f64](y)
    let ampl = (0.75f64 + cav) / sqrty
    var a = ampl
    if x < 0.0f64 { a = 0.0f64 - ampl }
    let v = a * spv
    ret (v, fa(spv) * cae / sqrty + fa(ampl) * spe + c_eps() * fa(v))
}

fn y0(x: f64) -> (f64, f64) {
    let two_over_pi = 2.0f64 / mpi()
    let xmax = 1.0f64 / c_eps()
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 4.0f64 {
        let (j0v, _j0e) = j0(x)
        let (cv, ce) = ch.cvv_bessel_Y0_by0(0.125f64 * x * x - 1.0f64)
        let v = two_over_pi * (0.0f64 - 0.693147180559945309417232121458f64 + math.log[f64](x)) * j0v + 0.375f64 + cv
        ret (v, 2.0f64 * c_eps() * fa(v) + ce)
    }
    if x < xmax {
        let z = 32.0f64 / (x * x) - 1.0f64
        let (c1v, c1e) = ch.cvv_bessel_amp_phase__gsl_sf_bessel_amp_phase_bm0(z)
        let (c2v, _c2e) = ch.cvv_bessel_amp_phase__gsl_sf_bessel_amp_phase_bth0(z)
        let (spv, spe) = pi4(x, c2v / x, false)
        let sqrtx = math.sqrt[f64](x)
        let ampl = (0.75f64 + c1v) / sqrtx
        let v = ampl * spv
        ret (v, fa(spv) * c1e / sqrtx + fa(ampl) * spe + 2.0f64 * c_eps() * fa(v))
    }
    ret (0.0f64, 0.0f64)
}

fn y1(x: f64) -> (f64, f64) {
    let two_over_pi = 2.0f64 / mpi()
    let xmin = 1.571f64 * 2.2250738585072014e-308f64
    let x_small = 2.0f64 * sqrt_eps()
    let xmax = 1.0f64 / c_eps()
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < xmin { ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64) }
    if x < 4.0f64 {
        let lnterm = math.log[f64](0.5f64 * x)
        var arg = -1.0f64
        if !(x < x_small) { arg = 0.125f64 * x * x - 1.0f64 }
        let (cv, ce) = ch.cvv_bessel_Y1_by1(arg)
        let (j1v, j1e) = j1(x)
        let v = two_over_pi * lnterm * j1v + (0.5f64 + cv) / x
        ret (v, fa(lnterm) * (fa(c_eps() * j1v) + j1e) + ce / x)
    }
    if x < xmax {
        let z = 32.0f64 / (x * x) - 1.0f64
        let (cav, cae) = ch.cvv_bessel_amp_phase__gsl_sf_bessel_amp_phase_bm1(z)
        let (ctv, _cte) = ch.cvv_bessel_amp_phase__gsl_sf_bessel_amp_phase_bth1(z)
        let (cpv, cpe) = pi4(x, ctv / x, true)
        let sqrtx = math.sqrt[f64](x)
        let ampl = (0.75f64 + cav) / sqrtx
        let v = 0.0f64 - ampl * cpv
        ret (v, fa(cpv) * cae / sqrtx + fa(ampl) * cpe + c_eps() * fa(v))
    }
    ret (0.0f64, 0.0f64)
}

// gsl_sf_bessel_J_CF1: (ratio J_{nu+1}/J_nu, sign)
fn j_cf1(nu: f64, x: f64) -> (f64, f64) {
    let big = 1.3407807929942596e+154f64
    let small = 1.4916681462400413e-154f64
    var n = 1i64
    var anm2 = 1.0f64
    var bnm2 = 0.0f64
    var anm1 = 0.0f64
    var bnm1 = 1.0f64
    let a1 = x / (2.0f64 * (nu + 1.0f64))
    var an_ = anm1 + a1 * anm2
    var bn_ = bnm1 + a1 * bnm2
    var fn_ = an_ / bn_
    var dn = a1
    var s = 1.0f64
    while n < 10000i64 {
        n += 1i64
        anm2 = anm1
        bnm2 = bnm1
        anm1 = an_
        bnm1 = bn_
        let an = 0.0f64 - x * x / (4.0f64 * (nu + f64(n) - 1.0f64) * (nu + f64(n)))
        an_ = anm1 + an * anm2
        bn_ = bnm1 + an * bnm2
        if fa(an_) > big || fa(bn_) > big {
            an_ /= big
            bn_ /= big
            anm1 /= big
            bnm1 /= big
            anm2 /= big
        }
        if !(fa(an_) > big || fa(bn_) > big) && (fa(an_) < small || fa(bn_) < small) {
            an_ /= small
            bn_ /= small
            anm1 /= small
            bnm1 /= small
            anm2 /= small
            bnm2 /= small
        }
        let old_fn = fn_
        fn_ = an_ / bn_
        let del = old_fn / fn_
        dn = 1.0f64 / (2.0f64 * (nu + f64(n)) / x - dn)
        if dn < 0.0f64 { s = 0.0f64 - s }
        if fa(del - 1.0f64) < 2.0f64 * c_eps() { break }
    }
    ret (fn_, s)
}

// gsl_sf_bessel_Jnu_asympx_e
fn jnu_asympx(nu: f64, x: f64) -> (f64, f64) {
    let mu = 4.0f64 * nu * nu
    let chi = x - (0.5f64 * nu + 0.25f64) * mpi()
    var p = 0.0f64
    var q = 0.0f64
    var k = 0.0f64
    var t = 1.0f64
    while k < 1000.0f64 {
        if k != 0.0f64 { t *= 0.0f64 - (mu - (2.0f64 * k - 1.0f64) * (2.0f64 * k - 1.0f64)) / (k * (8.0f64 * x)) }
        let conv_p = fa(t) < c_eps() * fa(p)
        p += t
        k += 1.0f64
        t *= (mu - (2.0f64 * k - 1.0f64) * (2.0f64 * k - 1.0f64)) / (k * (8.0f64 * x))
        let conv_q = fa(t) < c_eps() * fa(q)
        q += t
        if conv_p && conv_q && k > nu / 2.0f64 { break }
        k += 1.0f64
    }
    let pre = math.sqrt[f64](2.0f64 / (mpi() * x))
    let c = math.cos[f64](chi)
    let s = math.sin[f64](chi)
    ret (pre * (c * p - s * q), pre * c_eps() * (fa(c * p) + fa(s * q) + fa(t)) * (1.0f64 + fa(x)))
}

// J_n(x) for integer n, without the Taylor and Olver branches (gslnu.jn_full adds them)
fn jn(n0: i64, x0: f64) -> (f64, f64) {
    var n = n0
    var x = x0
    var sign = 1.0f64
    if n < 0i64 {
        n = 0i64 - n
        if n % 2i64 == 1i64 { sign = -sign }
    }
    if x < 0.0f64 {
        x = 0.0f64 - x
        if n % 2i64 == 1i64 { sign = -sign }
    }
    if n == 0i64 {
        let (v, e) = j0(x)
        ret (sign * v, e)
    }
    if n == 1i64 {
        let (v, e) = j1(x)
        ret (sign * v, e)
    }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    let nf = f64(n)
    if 1.2207031250000000e-04f64 * x > nf * nf + 1.0f64 || x > 1000.0f64 {
        let (v, e) = jnu_asympx(nf, x)
        ret (sign * v, e)
    }
    let (ratio, _sgn) = j_cf1(nf, x)
    let smin = 1.4916681462400413e-154f64
    var jkp1 = smin * ratio
    var jk = smin
    var k = n
    while k > 0i64 {
        let jkm1 = 2.0f64 * f64(k) / x * jk - jkp1
        jkp1 = jk
        jk = jkm1
        k -= 1i64
    }
    if fa(jkp1) > fa(jk) {
        let (b1v, b1e) = j1(x)
        ret (sign * (b1v / jkp1 * smin), fa(b1e / jkp1 * smin))
    }
    let (b0v, b0e) = j0(x)
    ret (sign * (b0v / jk * smin), fa(b0e / jk * smin))
}
