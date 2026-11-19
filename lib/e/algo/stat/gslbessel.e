// R gsl: the modified Bessel functions of order 0 and 1 (I0, I1, K0, K1 and their scaled forms) with gsl's error estimates, ports of specfunc/bessel_I0.c, bessel_I1.c, bessel_K0.c and
// bessel_K1.c over the generated Chebyshev tables in gslcheb. Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.algo.stat.gslcheb as ch
use e.algo.stat.gslairy as ga

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }

fn i0_scaled(x: f64) -> (f64, f64) {
    let y = fa(x)
    if y < 2.0f64 * 1.4901161193847656e-08f64 { ret (1.0f64 - y, 0.5f64 * y * y) }
    if y <= 3.0f64 {
        let ey = math.exp[f64](0.0f64 - y)
        let (cv, ce) = ch.cvv_bessel_I0_bi0(y * y / 4.5f64 - 1.0f64)
        let v = ey * (2.75f64 + cv)
        ret (v, c_eps() * fa(v) + ey * ce)
    }
    let sy = math.sqrt[f64](y)
    var cv = 0.0f64
    var ce = 0.0f64
    if y <= 8.0f64 {
        let (a, b) = ch.cvv_bessel_I0_ai0((48.0f64 / y - 11.0f64) / 5.0f64)
        cv = a
        ce = b
    }
    if y > 8.0f64 {
        let (a, b) = ch.cvv_bessel_I0_ai02(16.0f64 / y - 1.0f64)
        cv = a
        ce = b
    }
    let v = (0.375f64 + cv) / sy
    var e = 2.0f64 * c_eps() * (0.375f64 + fa(cv)) / sy
    e += ce / sy
    e += 2.0f64 * c_eps() * fa(v)
    ret (v, e)
}

fn i0(x: f64) -> (f64, f64) {
    let y = fa(x)
    if y < 2.0f64 * 1.4901161193847656e-08f64 { ret (1.0f64, 0.5f64 * y * y) }
    if y <= 3.0f64 {
        let (cv, ce) = ch.cvv_bessel_I0_bi0(y * y / 4.5f64 - 1.0f64)
        let v = 2.75f64 + cv
        var e = c_eps() * (2.75f64 + fa(cv))
        e += ce
        e += 2.0f64 * c_eps() * fa(v)
        ret (v, e)
    }
    if y < 7.0978271289338397e+02f64 - 1.0f64 {
        let ey = math.exp[f64](y)
        let (sv, se) = i0_scaled(x)
        let v = ey * sv
        ret (v, ey * se + y * c_eps() * fa(v) + 2.0f64 * c_eps() * fa(v))
    }
    ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64)
}

fn i1_scaled(x: f64) -> (f64, f64) {
    let xmin = 2.0f64 * 2.2250738585072014e-308f64
    let x_small = 2.0f64 * 1.4142135623730950488f64 * 1.4901161193847656e-08f64
    let y = fa(x)
    if y == 0.0f64 { ret (0.0f64, 0.0f64) }
    if y < xmin { ret (0.0f64, 0.0f64) }
    if y < x_small { ret (0.5f64 * x, 0.0f64) }
    if y <= 3.0f64 {
        let ey = math.exp[f64](0.0f64 - y)
        let (cv, ce) = ch.cvv_bessel_I1_bi1(y * y / 4.5f64 - 1.0f64)
        let v = x * ey * (0.875f64 + cv)
        ret (v, ey * ce + y * c_eps() * fa(v) + 2.0f64 * c_eps() * fa(v))
    }
    let sy = math.sqrt[f64](y)
    var cv = 0.0f64
    var ce = 0.0f64
    if y <= 8.0f64 {
        let (a, b) = ch.cvv_bessel_I1_ai1((48.0f64 / y - 11.0f64) / 5.0f64)
        cv = a
        ce = b
    }
    if y > 8.0f64 {
        let (a, b) = ch.cvv_bessel_I1_ai12(16.0f64 / y - 1.0f64)
        cv = a
        ce = b
    }
    let b = (0.375f64 + cv) / sy
    var s = -1.0f64
    if x > 0.0f64 { s = 1.0f64 }
    let v = s * b
    ret (v, ce / sy + 2.0f64 * c_eps() * fa(v))
}

fn i1(x: f64) -> (f64, f64) {
    let xmin = 2.0f64 * 2.2250738585072014e-308f64
    let x_small = 2.0f64 * 1.4142135623730950488f64 * 1.4901161193847656e-08f64
    let y = fa(x)
    if y == 0.0f64 { ret (0.0f64, 0.0f64) }
    if y < xmin { ret (0.0f64, 0.0f64) }
    if y < x_small { ret (0.5f64 * x, 0.0f64) }
    if y <= 3.0f64 {
        let (cv, ce) = ch.cvv_bessel_I1_bi1(y * y / 4.5f64 - 1.0f64)
        let v = x * (0.875f64 + cv)
        ret (v, y * ce + 2.0f64 * c_eps() * fa(v))
    }
    if y < 7.0978271289338397e+02f64 {
        let ey = math.exp[f64](y)
        let (sv, se) = i1_scaled(x)
        let v = ey * sv
        ret (v, ey * se + y * c_eps() * fa(v) + 2.0f64 * c_eps() * fa(v))
    }
    ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64)
}

fn k0_scaled(x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 1.0f64 {
        let lx = math.log[f64](x)
        let ex = math.exp[f64](x)
        let x2 = x * x
        let v = ex * (ch.pv_bessel_K0_k0_poly(x2) - lx * (1.0f64 + 0.25f64 * x2 * ch.pv_bessel_K0_i0_poly(0.25f64 * x2)))
        ret (v, ex * (1.6f64 + fa(lx) * 0.6f64) * c_eps() + 2.0f64 * c_eps() * fa(v))
    }
    let sx = math.sqrt[f64](x)
    if x <= 8.0f64 {
        let (cv, ce) = ch.cvv_bessel_K0_ak0((16.0f64 / x - 9.0f64) / 7.0f64)
        let v = (1.203125f64 + cv) / sx
        ret (v, ce / sx + 2.0f64 * c_eps() * fa(v))
    }
    let (cv, ce) = ch.cvv_bessel_K0_ak02(16.0f64 / x - 1.0f64)
    let v = (1.25f64 + cv) / sx
    ret (v, (ce + c_eps()) / sx + 2.0f64 * c_eps() * fa(v))
}

fn k0(x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 1.0f64 {
        let lx = math.log[f64](x)
        let x2 = x * x
        let v = ch.pv_bessel_K0_k0_poly(x2) - lx * (1.0f64 + 0.25f64 * x2 * ch.pv_bessel_K0_i0_poly(0.25f64 * x2))
        ret (v, (1.6f64 + fa(lx) * 0.6f64) * c_eps() + 2.0f64 * c_eps() * fa(v))
    }
    let (sv, se) = k0_scaled(x)
    let (v, e) = ga.exp_mult_err(0.0f64 - x, c_eps() * fa(x), sv, se)
    ret (v, e)
}

fn k1_scaled(x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 2.0f64 * 2.2250738585072014e-308f64 { ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64) }
    if x < 1.0f64 {
        let lx = math.log[f64](x)
        let ex = math.exp[f64](x)
        let x2 = x * x
        let t = 0.25f64 * x2
        let i1v = 0.5f64 * x * (1.0f64 + t * (0.5f64 + t * ch.pv_bessel_K1_i1_poly(t)))
        let v = ex * (x2 * ch.pv_bessel_K1_k1_poly(x2) + x * lx * i1v + 1.0f64) / x
        ret (v, ex * (1.6f64 + fa(lx) * 0.6f64) * c_eps() + 2.0f64 * c_eps() * fa(v))
    }
    let sx = math.sqrt[f64](x)
    if x <= 8.0f64 {
        let (cv, ce) = ch.cvv_bessel_K1_ak1((16.0f64 / x - 9.0f64) / 7.0f64)
        let v = (1.375f64 + cv) / sx
        ret (v, ce / sx + 2.0f64 * c_eps() * fa(v))
    }
    let (cv, ce) = ch.cvv_bessel_K1_ak12(16.0f64 / x - 1.0f64)
    let v = (1.25f64 + cv) / sx
    ret (v, ce / sx + 2.0f64 * c_eps() * fa(v))
}

fn k1(x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 2.0f64 * 2.2250738585072014e-308f64 { ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64) }
    if x < 1.0f64 {
        let lx = math.log[f64](x)
        let x2 = x * x
        let t = 0.25f64 * x2
        let i1v = 0.5f64 * x * (1.0f64 + t * (0.5f64 + t * ch.pv_bessel_K1_i1_poly(t)))
        let v = (x2 * ch.pv_bessel_K1_k1_poly(x2) + x * lx * i1v + 1.0f64) / x
        ret (v, (1.6f64 + fa(lx) * 0.6f64) * c_eps() + 2.0f64 * c_eps() * fa(v))
    }
    let (sv, se) = k1_scaled(x)
    let (v, _e) = ga.exp_mult_err(0.0f64 - x, 0.0f64, sv, se)
    ret (v, fa(v) * (c_eps() * fa(x) + se / sv))
}
