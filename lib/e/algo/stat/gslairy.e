// R gsl: the Airy functions Ai, Bi, their exponentially scaled forms and the derivatives, with gsl's error estimates, a port of specfunc/airy.c and airy_der.c over the generated
// Chebyshev tables in gslcheb. `mode` is gsl's precision mode (0 double; the others use the shorter single-precision series). Every function returns (value, error).

use e.math
use e.algo.stat.gslcheb as ch
use e.algo.stat.gslerr as ge

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn mpi() -> f64 { ret 3.141592653589793238462643383279f64 }

// gsl_sf_exp_mult_err_e(x, dx, y, dy)
fn exp_mult_err(x: f64, dx: f64, y: f64, dy: f64) -> (f64, f64) {
    let ay = fa(y)
    if y == 0.0f64 { ret (0.0f64, fa(dy * math.exp[f64](x))) }
    if x < 0.5f64 * 7.0978271289338397e+02f64 && x > 0.5f64 * -7.0839641853226408e+02f64 && ay < 0.8f64 * 1.3407807929942596e+154f64 && ay > 1.2f64 * 1.4916681462400413e-154f64 {
        let ex = math.exp[f64](x)
        let v = y * ex
        ret (v, ex * (fa(dy) + fa(y * dx)) + 2.0f64 * c_eps() * fa(v))
    }
    let ly = math.log[f64](ay)
    let lnr = x + ly
    if lnr > 7.0978271289338397e+02f64 - 0.01f64 { ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64) }
    if lnr < -7.0839641853226408e+02f64 + 0.01f64 { ret (0.0f64, 0.0f64) }
    var sy = 1.0f64
    if y < 0.0f64 { sy = -1.0f64 }
    let mm = math.floor[f64](x)
    let nn = math.floor[f64](ly)
    let a = x - mm
    let b = ly - nn
    let emn = math.exp[f64](mm + nn)
    let eab = math.exp[f64](a + b)
    let v = sy * emn * eab
    var e = emn * eab * 2.0f64 * c_eps()
    e += emn * eab * fa(dy / y)
    e += emn * eab * fa(dx)
    ret (v, e)
}

// airy_mod_phase for x < -1: (modulus, its error, phase, its error)
fn mod_phase(x: f64, mode: usize) -> (f64, f64, f64, f64) {
    var rmv = 0.0f64
    var rme = 0.0f64
    var rpv = 0.0f64
    var rpe = 0.0f64
    if x < -2.0f64 {
        let z = 16.0f64 / (x * x * x) + 1.0f64
        let (a1, a2) = ch.cev_airy_am21(z, mode)
        let (b1, b2) = ch.cev_airy_ath1(z, mode)
        rmv = a1
        rme = a2
        rpv = b1
        rpe = b2
    }
    if x >= -2.0f64 {
        let z = (16.0f64 / (x * x * x) + 9.0f64) / 7.0f64
        let (a1, a2) = ch.cev_airy_am22(z, mode)
        let (b1, b2) = ch.cev_airy_ath2(z, mode)
        rmv = a1
        rme = a2
        rpv = b1
        rpe = b2
    }
    let m = 0.3125f64 + rmv
    let p = -0.625f64 + rpv
    let sqx = math.sqrt[f64](0.0f64 - x)
    let mv = math.sqrt[f64](m / sqx)
    let me = fa(mv) * (c_eps() + fa(rme / rmv))
    let pv = mpi() / 4.0f64 - x * sqx * p
    let pe = fa(pv) * (c_eps() + fa(rpe / rpv))
    ret (mv, me, pv, pe)
}

fn aie(x: f64, mode: usize) -> (f64, f64) {
    let sqx = math.sqrt[f64](x)
    let z = 2.0f64 / (x * sqx) - 1.0f64
    let y = math.sqrt[f64](sqx)
    let (cv, ce) = ch.cev_airy_aip(z, mode)
    let v = (0.28125f64 + cv) / y
    ret (v, ce / y + c_eps() * fa(v))
}

fn bie(x: f64, mode: usize) -> (f64, f64) {
    let atr = 8.7506905708484345f64
    let btr = -2.0938363213560543f64
    let sqx = math.sqrt[f64](x)
    let y = math.sqrt[f64](sqx)
    if x < 4.0f64 {
        let z = atr / (x * sqx) + btr
        let (cv, ce) = ch.cev_airy_bip(z, mode)
        let v = (0.625f64 + cv) / y
        ret (v, ce / y + c_eps() * fa(v))
    }
    let z = 16.0f64 / (x * sqx) - 1.0f64
    let (cv, ce) = ch.cev_airy_bip2(z, mode)
    let v = (0.625f64 + cv) / y
    ret (v, ce / y + c_eps() * fa(v))
}

// the oscillatory side x < -1: Ai = mod cos(phase), Bi = mod sin(phase)
fn osc(x: f64, mode: usize, cosine: bool) -> (f64, f64) {
    let (mv, me, pv, pe) = mod_phase(x, mode)
    var tv = 0.0f64
    var te = 0.0f64
    if cosine {
        let (a, b) = ge.e_cos(pv)
        tv = a
        te = b + fa(math.sin[f64](pv) * pe) + c_eps() * fa(a)
    }
    if !cosine {
        let (a, b) = ge.e_sin(pv)
        tv = a
        te = b + fa(math.cos[f64](pv) * pe) + c_eps() * fa(a)
    }
    let v = mv * tv
    ret (v, fa(mv * te) + fa(tv * me) + c_eps() * fa(v))
}

fn airy_ai(x: f64, mode: usize) -> (f64, f64) {
    if x < -1.0f64 {
        let (v, e) = osc(x, mode, true)
        ret (v, e)
    }
    if x <= 1.0f64 {
        let z = x * x * x
        let (c0, e0) = ch.cev_airy_aif(z, mode)
        let (c1, e1) = ch.cev_airy_aig(z, mode)
        let v = 0.375f64 + (c0 - x * (0.25f64 + c1))
        ret (v, e0 + fa(x * e1) + c_eps() * fa(v))
    }
    let x32 = x * math.sqrt[f64](x)
    let s = math.exp[f64](-2.0f64 * x32 / 3.0f64)
    let (av, ae) = aie(x, mode)
    let v = av * s
    ret (v, ae * s + v * x32 * c_eps() + c_eps() * fa(v))
}

fn airy_ai_scaled(x: f64, mode: usize) -> (f64, f64) {
    if x < -1.0f64 {
        let (v, e) = osc(x, mode, true)
        ret (v, e)
    }
    if x <= 1.0f64 {
        let z = x * x * x
        let (c0, e0) = ch.cev_airy_aif(z, mode)
        let (c1, e1) = ch.cev_airy_aig(z, mode)
        var v = 0.375f64 + (c0 - x * (0.25f64 + c1))
        var e = e0 + fa(x * e1)
        e += c_eps() * fa(v)
        if x > 0.0f64 {
            let scale = math.exp[f64](2.0f64 / 3.0f64 * math.sqrt[f64](z))
            v *= scale
            e *= scale
        }
        ret (v, e)
    }
    let (v, e) = aie(x, mode)
    ret (v, e)
}

fn airy_bi(x: f64, mode: usize) -> (f64, f64) {
    if x < -1.0f64 {
        let (v, e) = osc(x, mode, false)
        ret (v, e)
    }
    if x < 1.0f64 {
        let z = x * x * x
        let (c0, e0) = ch.cev_airy_bif(z, mode)
        let (c1, e1) = ch.cev_airy_big(z, mode)
        let v = 0.625f64 + c0 + x * (0.4375f64 + c1)
        ret (v, e0 + fa(x * e1) + c_eps() * fa(v))
    }
    if x <= 2.0f64 {
        let z = (2.0f64 * x * x * x - 9.0f64) / 7.0f64
        let (c0, e0) = ch.cev_airy_bif2(z, mode)
        let (c1, e1) = ch.cev_airy_big2(z, mode)
        let v = 1.125f64 + c0 + x * (0.625f64 + c1)
        ret (v, e0 + fa(x * e1) + c_eps() * fa(v))
    }
    let y = 2.0f64 * x * math.sqrt[f64](x) / 3.0f64
    let s = math.exp[f64](y)
    if y > 7.0978271289338397e+02f64 - 1.0f64 { ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64) }
    let (bv, be) = bie(x, mode)
    let v = bv * s
    ret (v, be * s + fa(1.5f64 * y * (c_eps() * v)) + c_eps() * fa(v))
}

fn airy_bi_scaled(x: f64, mode: usize) -> (f64, f64) {
    if x < -1.0f64 {
        let (v, e) = osc(x, mode, false)
        ret (v, e)
    }
    if x < 1.0f64 {
        let z = x * x * x
        let (c0, e0) = ch.cev_airy_bif(z, mode)
        let (c1, e1) = ch.cev_airy_big(z, mode)
        var v = 0.625f64 + c0 + x * (0.4375f64 + c1)
        var e = e0 + fa(x * e1)
        e += c_eps() * fa(v)
        if x > 0.0f64 {
            let scale = math.exp[f64](-2.0f64 / 3.0f64 * math.sqrt[f64](z))
            v *= scale
            e *= scale
        }
        ret (v, e)
    }
    if x <= 2.0f64 {
        let x3 = x * x * x
        let z = (2.0f64 * x3 - 9.0f64) / 7.0f64
        let s = math.exp[f64](-2.0f64 / 3.0f64 * math.sqrt[f64](x3))
        let (c0, e0) = ch.cev_airy_bif2(z, mode)
        let (c1, e1) = ch.cev_airy_big2(z, mode)
        let v = s * (1.125f64 + c0 + x * (0.625f64 + c1))
        ret (v, s * (e0 + fa(x * e1)) + c_eps() * fa(v))
    }
    let (v, e) = bie(x, mode)
    ret (v, e)
}

// airy_deriv_mod_phase for x < -1: (amplitude, error, phase, error)
fn deriv_mod_phase(x: f64, mode: usize) -> (f64, f64, f64, f64) {
    let pi34 = 2.356194490192344928847f64
    var rav = 0.0f64
    var rae = 0.0f64
    var rpv = 0.0f64
    var rpe = 0.0f64
    if x <= -4.0f64 {
        let z = 128.0f64 / (x * x * x) + 1.0f64
        let (a1, a2) = ch.cev_airy_der_an20(z, mode)
        let (b1, b2) = ch.cev_airy_der_aph0(z, mode)
        rav = a1
        rae = a2
        rpv = b1
        rpe = b2
    }
    if x > -4.0f64 && x <= -2.0f64 {
        let z = (128.0f64 / (x * x * x) + 9.0f64) / 7.0f64
        let (a1, a2) = ch.cev_airy_der_an21(z, mode)
        let (b1, b2) = ch.cev_airy_der_aph1(z, mode)
        rav = a1
        rae = a2
        rpv = b1
        rpe = b2
    }
    if x > -2.0f64 {
        let z = (16.0f64 / (x * x * x) + 9.0f64) / 7.0f64
        let (a1, a2) = ch.cev_airy_der_an22(z, mode)
        let (b1, b2) = ch.cev_airy_der_aph2(z, mode)
        rav = a1
        rae = a2
        rpv = b1
        rpe = b2
    }
    let a = 0.3125f64 + rav
    let p = -0.625f64 + rpv
    let sqx = math.sqrt[f64](0.0f64 - x)
    let av = math.sqrt[f64](a * sqx)
    let ae = fa(av) * (c_eps() + fa(rae / rav))
    let pv = pi34 - x * sqx * p
    let pe = fa(pv) * (c_eps() + fa(rpe / rpv))
    ret (av, ae, pv, pe)
}

fn deriv_osc(x: f64, mode: usize, cosine: bool) -> (f64, f64) {
    let (av, ae, pv, pe) = deriv_mod_phase(x, mode)
    var c = math.sin[f64](pv)
    if cosine { c = math.cos[f64](pv) }
    let v = av * c
    ret (v, fa(v * pe) + fa(c * ae) + c_eps() * fa(v))
}

fn airy_ai_deriv_scaled(x: f64, mode: usize) -> (f64, f64) {
    if x < -1.0f64 {
        let (v, e) = deriv_osc(x, mode, true)
        ret (v, e)
    }
    if x <= 1.0f64 {
        let x3 = x * x * x
        let x2 = x * x
        let (c0, e0) = ch.cev_airy_der_aif(x3, mode)
        let (c1, e1) = ch.cev_airy_der_aig(x3, mode)
        var v = (x2 * (0.125f64 + c0) - c1) - 0.25f64
        var e = fa(x2 * c0) + e1
        e += c_eps() * fa(v)
        let r3e = 6.0554544523933429e-06f64
        if x > r3e * r3e {
            let s = math.exp[f64](2.0f64 * x * math.sqrt[f64](x) / 3.0f64)
            v *= s
            e *= s
        }
        let _unused = e0
        ret (v, e)
    }
    let sqrtx = math.sqrt[f64](x)
    let s = math.sqrt[f64](sqrtx)
    if x <= 4.0f64 {
        let z = (16.0f64 / (x * sqrtx) - 9.0f64) / 7.0f64
        let (c0, e0) = ch.cev_airy_der_aip1(z, mode)
        let v = -(0.28125f64 + c0) * s
        ret (v, e0 * s + c_eps() * fa(v))
    }
    let z = 16.0f64 / (x * sqrtx) - 1.0f64
    let (c0, e0) = ch.cev_airy_der_aip2(z, mode)
    let v = -(0.28125f64 + c0) * s
    ret (v, e0 * s + c_eps() * fa(v))
}

fn airy_ai_deriv(x: f64, mode: usize) -> (f64, f64) {
    if x < -1.0f64 {
        let (v, e) = deriv_osc(x, mode, true)
        ret (v, e)
    }
    if x < 1.0f64 {
        let x3 = x * x * x
        let (c1, e1) = ch.cev_airy_der_aif(x3, mode)
        let (c2, e2) = ch.cev_airy_der_aig(x3, mode)
        let v = (x * x * (0.125f64 + c1) - c2) - 0.25f64
        ret (v, fa(x * x * e1) + e2 + c_eps() * fa(v))
    }
    if x * x * x < 9.0f64 / 4.0f64 * 7.0839641853226408e+02f64 * 7.0839641853226408e+02f64 {
        let arg = -2.0f64 * x * math.sqrt[f64](x) / 3.0f64
        let (sv, se) = airy_ai_deriv_scaled(x, mode)
        let (v, e) = exp_mult_err(arg, 1.5f64 * fa(arg * c_eps()), sv, se)
        ret (v, e)
    }
    ret (0.0f64, 0.0f64)
}

fn airy_bi_deriv_scaled(x: f64, mode: usize) -> (f64, f64) {
    let atr = 8.7506905708484345f64
    let btr = -2.0938363213560543f64
    if x < -1.0f64 {
        let (v, e) = deriv_osc(x, mode, false)
        ret (v, e)
    }
    if x < 1.0f64 {
        let x3 = x * x * x
        let x2 = x * x
        let (c1, e1) = ch.cev_airy_der_bif(x3, mode)
        let (c2, e2) = ch.cev_airy_der_big(x3, mode)
        var v = x2 * (c1 + 0.25f64) + c2 + 0.5f64
        var e = x2 * e1 + e2
        e += c_eps() * fa(v)
        let r3e = 6.0554544523933429e-06f64
        if x > r3e * r3e {
            let s = math.exp[f64](-2.0f64 * x * math.sqrt[f64](x) / 3.0f64)
            v *= s
            e *= s
        }
        ret (v, e)
    }
    if x < 2.0f64 {
        let z = (2.0f64 * x * x * x - 9.0f64) / 7.0f64
        let s = math.exp[f64](-2.0f64 * x * math.sqrt[f64](x) / 3.0f64)
        let (c0, e0) = ch.cev_airy_der_bif2(z, mode)
        let (c1, e1) = ch.cev_airy_der_big2(z, mode)
        let v = s * (x * x * (0.25f64 + c0) + 0.5f64 + c1)
        ret (v, s * (x * x * e0 + e1) + c_eps() * fa(v))
    }
    let sqrtx = math.sqrt[f64](x)
    let s = math.sqrt[f64](sqrtx)
    if x < 4.0f64 {
        let z = atr / (x * sqrtx) + btr
        let (c0, e0) = ch.cev_airy_der_bip1(z, mode)
        let v = s * (0.625f64 + c0)
        ret (v, s * e0 + c_eps() * fa(v))
    }
    let z = 16.0f64 / (x * sqrtx) - 1.0f64
    let (c0, e0) = ch.cev_airy_der_bip2(z, mode)
    let v = s * (0.625f64 + c0)
    ret (v, s * e0 + c_eps() * fa(v))
}

fn airy_bi_deriv(x: f64, mode: usize) -> (f64, f64) {
    if x < -1.0f64 {
        let (v, e) = deriv_osc(x, mode, false)
        ret (v, e)
    }
    if x < 1.0f64 {
        let x3 = x * x * x
        let x2 = x * x
        let (c1, e1) = ch.cev_airy_der_bif(x3, mode)
        let (c2, e2) = ch.cev_airy_der_big(x3, mode)
        let v = x2 * (c1 + 0.25f64) + c2 + 0.5f64
        ret (v, x2 * e1 + e2 + c_eps() * fa(v))
    }
    if x < 2.0f64 {
        let z = (2.0f64 * x * x * x - 9.0f64) / 7.0f64
        let (c1, e1) = ch.cev_airy_der_bif2(z, mode)
        let (c2, e2) = ch.cev_airy_der_big2(z, mode)
        let v = x * x * (c1 + 0.25f64) + c2 + 0.5f64
        ret (v, x * x * e1 + e2 + c_eps() * fa(v))
    }
    if x < 5.643803094122362e+102f64 * 5.643803094122362e+102f64 {
        let arg = 2.0f64 * (x * math.sqrt[f64](x) / 3.0f64)
        let (bv, be) = airy_bi_deriv_scaled(x, mode)
        let (v, e) = exp_mult_err(arg, 1.5f64 * fa(arg * c_eps()), bv, be)
        ret (v, e)
    }
    ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64)
}
