// R gsl, hyperg_0F1 with gsl_sf_result.err: a port of specfunc/hyperg_0F1.c over the real-order Bessel functions of gslnu. Returns (value, error); a domain error returns (0, 0).
// Not here: hyperg_1F1, hyperg_U, hyperg_2F1 and hyperg_2F0 with error estimates (specfunc/hyperg_1F1.c, hyperg_U.c, hyperg_2F1.c).

use e.math
use e.mem
use e.algo.stat.gslnu as gu
use e.algo.stat.gslairy as ga
use e.algo.stat.gslerr as ge

fn h_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn h_a(x: f64) -> f64 { ret math.abs[f64](x) }
fn h_pi() -> f64 { ret 3.141592653589793238462643383279f64 }

// hyperg_0F1_bessel_I: I_nu(x) for any non-integer-negative nu, x > 0
fn bessel_i(ar: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    if x > 7.0978271289338397e+02f64 { ret (0.0f64, 0.0f64) }
    if nu < 0.0f64 {
        let anu = 0.0f64 - nu
        let s = 2.0f64 / h_pi() * math.sin[f64](anu * h_pi())
        let ex = math.exp[f64](x)
        let (iv, ie) = gu.inu_scaled(ar, anu, x)
        let (kv, ke) = gu.knu_scaled(anu, x)
        let v = ex * iv + s * (kv / ex)
        var er = ex * ie + h_a(s * ke / ex)
        er += h_a(s * (kv / ex)) * h_eps() * anu * h_pi()
        ret (v, er)
    }
    let ex = math.exp[f64](x)
    let (iv, ie) = gu.inu_scaled(ar, nu, x)
    let v = ex * iv
    ret (v, ex * ie + h_eps() * h_a(v))
}

// hyperg_0F1_bessel_J
fn bessel_j(ar: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    if nu < 0.0f64 {
        let anu = 0.0f64 - nu
        let s = math.sin[f64](anu * h_pi())
        let c = math.cos[f64](anu * h_pi())
        let (jv, je) = gu.bessel_jnu(ar, anu, x)
        let (yv, ye) = gu.bessel_ynu(ar, anu, x)
        let v = c * jv - s * yv
        var er = h_a(c * je) + h_a(s * ye)
        er += h_a(anu * h_pi()) * h_eps() * h_a(jv + yv)
        ret (v, er)
    }
    let (v2, e2) = gu.bessel_jnu(ar, nu, x)
    ret (v2, e2)
}

// gsl_sf_hyperg_0F1_e(c, x)
fn hyperg_0f1(ar: *mem.Arena, c: f64, x: f64) -> (f64, f64) {
    let rintc = math.floor[f64](c + 0.5f64)
    if c == 0.0f64 || (c < 0.0f64 && h_a(c - rintc) < 1000.0f64 * h_eps()) { ret (0.0f64, 0.0f64) }
    if x < 0.0f64 {
        let (lgv, lge, sgn) = ge.e_lngamma_sgn(c)
        let (jv, je) = bessel_j(ar, c - 1.0f64, 2.0f64 * math.sqrt[f64](0.0f64 - x))
        if jv == 0.0f64 { ret (0.0f64, 0.0f64) }
        let tl = math.log[f64](0.0f64 - x) * 0.5f64 * (1.0f64 - c)
        let (v, e) = ga.exp_mult_err(lgv + tl, lge + 2.0f64 * h_eps() * h_a(tl), sgn * jv, je)
        ret (v, e)
    }
    if x == 0.0f64 { ret (1.0f64, 1.0f64) }
    let (lgv2, lge2, sgn2) = ge.e_lngamma_sgn(c)
    let (iv, ie) = bessel_i(ar, c - 1.0f64, 2.0f64 * math.sqrt[f64](x))
    if iv == 0.0f64 { ret (0.0f64, 0.0f64) }
    let tl2 = math.log[f64](x) * 0.5f64 * (1.0f64 - c)
    let (v2, e2) = ga.exp_mult_err(lgv2 + tl2, lge2 + 2.0f64 * h_eps() * h_a(tl2), sgn2 * iv, ie)
    ret (v2, e2)
}
