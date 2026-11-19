// R gsl: Dawson's integral, the Clausen function and the exponential integrals E1, E2 and Ei with gsl's error estimates, ports of specfunc/dawson.c, clausen.c and expint.c over the
// generated Chebyshev tables in gslcheb. Every function returns (value, error).

use e.math
use e.algo.stat.gslcheb as ch

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn mpi() -> f64 { ret 3.141592653589793238462643383279f64 }

fn dawson(x: f64) -> (f64, f64) {
    let xsml = 1.225f64 * 1.4901161193847656e-08f64
    let xbig = 1.0f64 / (1.4142135623730950488f64 * 1.4901161193847656e-08f64)
    let xmax = 0.1f64 * 1.7976931348623157e308f64
    let y = fa(x)
    if y < xsml { ret (x, 0.0f64) }
    if y < 1.0f64 {
        let (cv, ce) = ch.cheb_eval(ch.tid_dawson_daw(), ch.tord_dawson_daw(), ch.ta_dawson_daw(), ch.tb_dawson_daw(), 2.0f64 * y * y - 1.0f64)
        let v = x * (0.75f64 + cv)
        ret (v, y * ce + 2.0f64 * c_eps() * fa(v))
    }
    if y < 4.0f64 {
        let (cv, ce) = ch.cheb_eval(ch.tid_dawson_daw2(), ch.tord_dawson_daw2(), ch.ta_dawson_daw2(), ch.tb_dawson_daw2(), 0.125f64 * y * y - 1.0f64)
        let v = x * (0.25f64 + cv)
        ret (v, y * ce + 2.0f64 * c_eps() * fa(v))
    }
    if y < xbig {
        let (cv, ce) = ch.cheb_eval(ch.tid_dawson_dawa(), ch.tord_dawson_dawa(), ch.ta_dawson_dawa(), ch.tb_dawson_dawa(), 32.0f64 / (y * y) - 1.0f64)
        let v = (0.5f64 + cv) / x
        ret (v, ce / y + 2.0f64 * c_eps() * fa(v))
    }
    if y < xmax {
        let v = 0.5f64 / x
        ret (v, 2.0f64 * c_eps() * v)
    }
    ret (0.0f64, 0.0f64)
}

// gsl_sf_angle_restrict_pos_e: the argument reduced to [0, 2 pi) with the synthetic extended precision constants
fn angle_restrict_pos(theta: f64) -> f64 {
    let p1 = 4.0f64 * 7.85398125648498535156e-01f64
    let p2 = 4.0f64 * 3.77489470793079817668e-08f64
    let p3 = 4.0f64 * 2.69515142907905952645e-15f64
    let two_pi = 2.0f64 * (p1 + p2 + p3)
    let y = 2.0f64 * math.floor[f64](theta / two_pi)
    var r = ((theta - y * p1) - y * p2) - y * p3
    if r > two_pi { r = ((r - 2.0f64 * p1) - 2.0f64 * p2) - 2.0f64 * p3 }
    if !(r > two_pi) && r < 0.0f64 { r = ((r + 2.0f64 * p1) + 2.0f64 * p2) + 2.0f64 * p3 }
    ret r
}

fn clausen(x0: f64) -> (f64, f64) {
    let x_cut = mpi() * 1.4901161193847656e-08f64
    var sgn = 1.0f64
    var x = x0
    if x < 0.0f64 {
        x = 0.0f64 - x
        sgn = -1.0f64
    }
    x = angle_restrict_pos(x)
    if x > mpi() {
        let p0 = 6.28125f64
        let p1 = 0.19353071795864769253e-02f64
        x = (p0 - x) + p1
        sgn = 0.0f64 - sgn
    }
    var v = 0.0f64
    var e = 0.0f64
    if x == 0.0f64 {
        v = 0.0f64
        e = 0.0f64
    }
    if x != 0.0f64 && x < x_cut {
        v = x * (1.0f64 - math.log[f64](x))
        e = x * c_eps()
    }
    if x >= x_cut {
        let t = 2.0f64 * (x * x / (mpi() * mpi()) - 0.5f64)
        let (cv, ce) = ch.cheb_eval(ch.tid_clausen_aclaus(), ch.tord_clausen_aclaus(), ch.ta_clausen_aclaus(), ch.tb_clausen_aclaus(), t)
        v = x * (cv - math.log[f64](x))
        e = x * (ce + c_eps())
    }
    ret (v * sgn, e)
}

// E1 (scale = false) or e^x E1 (scale = true)
fn expint_e1(x: f64, scale: bool) -> (f64, f64) {
    let xmaxt = 7.0839641853226408e+02f64
    let xmax = xmaxt - math.log[f64](xmaxt)
    if x < 0.0f64 - xmax && !scale { ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64) }
    var sc = 1.0f64
    if x <= -10.0f64 {
        if !scale { sc = math.exp[f64](0.0f64 - x) }
        let s = 1.0f64 / x * sc
        let (cv, ce) = ch.cheb_eval(ch.tid_expint_AE11(), ch.tord_expint_AE11(), ch.ta_expint_AE11(), ch.tb_expint_AE11(), 20.0f64 / x + 1.0f64)
        let v = s * (1.0f64 + cv)
        ret (v, s * ce + 2.0f64 * c_eps() * (fa(x) + 1.0f64) * fa(v))
    }
    if x <= -4.0f64 {
        if !scale { sc = math.exp[f64](0.0f64 - x) }
        let s = 1.0f64 / x * sc
        let (cv, ce) = ch.cheb_eval(ch.tid_expint_AE12(), ch.tord_expint_AE12(), ch.ta_expint_AE12(), ch.tb_expint_AE12(), (40.0f64 / x + 7.0f64) / 3.0f64)
        let v = s * (1.0f64 + cv)
        ret (v, s * ce + 2.0f64 * c_eps() * fa(v))
    }
    if x <= -1.0f64 {
        let ln_term = 0.0f64 - math.log[f64](fa(x))
        var scale_factor = 1.0f64
        if scale { scale_factor = math.exp[f64](x) }
        let (cv, ce) = ch.cheb_eval(ch.tid_expint_E11(), ch.tord_expint_E11(), ch.ta_expint_E11(), ch.tb_expint_E11(), (2.0f64 * x + 5.0f64) / 3.0f64)
        let v = scale_factor * (ln_term + cv)
        ret (v, scale_factor * (ce + c_eps() * fa(ln_term)) + 2.0f64 * c_eps() * fa(v))
    }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    if x <= 1.0f64 {
        let ln_term = 0.0f64 - math.log[f64](fa(x))
        var scale_factor = 1.0f64
        if scale { scale_factor = math.exp[f64](x) }
        let (cv, ce) = ch.cheb_eval(ch.tid_expint_E12(), ch.tord_expint_E12(), ch.ta_expint_E12(), ch.tb_expint_E12(), x)
        let v = scale_factor * (ln_term - 0.6875f64 + x + cv)
        ret (v, scale_factor * (ce + c_eps() * fa(ln_term)) + 2.0f64 * c_eps() * fa(v))
    }
    if x <= 4.0f64 {
        if !scale { sc = math.exp[f64](0.0f64 - x) }
        let s = 1.0f64 / x * sc
        let (cv, ce) = ch.cheb_eval(ch.tid_expint_AE13(), ch.tord_expint_AE13(), ch.ta_expint_AE13(), ch.tb_expint_AE13(), (8.0f64 / x - 5.0f64) / 3.0f64)
        let v = s * (1.0f64 + cv)
        ret (v, s * ce + 2.0f64 * c_eps() * fa(v))
    }
    if x <= xmax || scale {
        if !scale { sc = math.exp[f64](0.0f64 - x) }
        let s = 1.0f64 / x * sc
        let (cv, ce) = ch.cheb_eval(ch.tid_expint_AE14(), ch.tord_expint_AE14(), ch.ta_expint_AE14(), ch.tb_expint_AE14(), 8.0f64 / x - 1.0f64)
        let v = s * (1.0f64 + cv)
        ret (v, s * (c_eps() + ce) + 2.0f64 * (x + 1.0f64) * c_eps() * fa(v))
    }
    ret (0.0f64, 0.0f64)
}

fn expint_e2(x: f64, scale: bool) -> (f64, f64) {
    let xmaxt = 7.0839641853226408e+02f64
    let xmax = xmaxt - math.log[f64](xmaxt)
    if x < 0.0f64 - xmax && !scale { ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64) }
    if x == 0.0f64 { ret (1.0f64, 0.0f64) }
    if x < 100.0f64 {
        var ex = 1.0f64
        if !scale { ex = math.exp[f64](0.0f64 - x) }
        let (e1v, e1e) = expint_e1(x, scale)
        let v = ex - x * e1v
        ret (v, c_eps() * ex + fa(x) * e1e + 2.0f64 * c_eps() * fa(v))
    }
    if x < xmax || scale {
        var s = 1.0f64
        if !scale { s = math.exp[f64](0.0f64 - x) }
        let y = 1.0f64 / x
        let sum6 = 5040.0f64 + y * (-40320.0f64 + y * (362880.0f64 + y * (-3628800.0f64 + y * (39916800.0f64 + y * (-479001600.0f64 + y * (6227020800.0f64 + y * -87178291200.0f64))))))
        let sum = y * (-2.0f64 + y * (6.0f64 + y * (-24.0f64 + y * (120.0f64 + y * (-720.0f64 + y * sum6)))))
        let v = s * (1.0f64 + sum) / x
        ret (v, 2.0f64 * (x + 1.0f64) * c_eps() * v)
    }
    ret (0.0f64, 0.0f64)
}

fn expint_ei(x: f64) -> (f64, f64) {
    let (v, e) = expint_e1(0.0f64 - x, false)
    ret (0.0f64 - v, e)
}
