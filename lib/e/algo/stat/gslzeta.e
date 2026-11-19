// R gsl: the Riemann zeta function for s >= 0, zeta - 1, the eta function and the integer-argument forms for n >= 2 (n >= 0 for eta) with gsl's error estimates, a port of specfunc/zeta.c
// over the generated Chebyshev tables in gslcheb. The reflection branch for s < 0 (which needs gsl's Gamma) is not here. Every function returns (value, error).

use e.math
use e.algo.stat.gslcheb as ch

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }

// zeta(s) for s >= 0, s != 1
fn zeta(s: f64) -> (f64, f64) {
    if s < 1.0f64 {
        let (cv, ce) = ch.cvv_zeta_zeta_xlt1(2.0f64 * s - 1.0f64)
        let v = cv / (s - 1.0f64)
        ret (v, ce / fa(s - 1.0f64) + c_eps() * fa(v))
    }
    if s <= 20.0f64 {
        let x = (2.0f64 * s - 21.0f64) / 19.0f64
        let (cv, ce) = ch.cvv_zeta_zeta_xgt1(x)
        let v = cv / (s - 1.0f64)
        ret (v, ce / (s - 1.0f64) + c_eps() * fa(v))
    }
    let f2 = 1.0f64 - math.pow[f64](2.0f64, 0.0f64 - s)
    let f3 = 1.0f64 - math.pow[f64](3.0f64, 0.0f64 - s)
    let f5 = 1.0f64 - math.pow[f64](5.0f64, 0.0f64 - s)
    let f7 = 1.0f64 - math.pow[f64](7.0f64, 0.0f64 - s)
    let v = 1.0f64 / (f2 * f3 * f5 * f7)
    ret (v, 3.0f64 * c_eps() * fa(v))
}

fn zeta_minus_1_intermediate(s: f64) -> (f64, f64) {
    let t = (s - 10.0f64) / 5.0f64
    let (cv, ce) = ch.cvv_zeta_zetam1_inter(t)
    let v = math.exp[f64](cv) + math.pow[f64](2.0f64, 0.0f64 - s)
    ret (v, (ce + 2.0f64 * c_eps()) * v)
}

fn zeta_minus1_large_s(s: f64) -> (f64, f64) {
    let a = math.pow[f64](2.0f64, 0.0f64 - s)
    let b = math.pow[f64](3.0f64, 0.0f64 - s)
    let c = math.pow[f64](5.0f64, 0.0f64 - s)
    let d = math.pow[f64](7.0f64, 0.0f64 - s)
    let e = math.pow[f64](11.0f64, 0.0f64 - s)
    let f = math.pow[f64](13.0f64, 0.0f64 - s)
    let t1 = a + b + c + d + e + f
    let t2 = a * (b + c + d + e + f) + b * (c + d + e + f) + c * (d + e + f) + d * (e + f) + e * f
    let numt = t1 - t2
    let z = 1.0f64 / ((1.0f64 - a) * (1.0f64 - b) * (1.0f64 - c) * (1.0f64 - d) * (1.0f64 - e) * (1.0f64 - f))
    let v = numt * z
    ret (v, (15.0f64 / s + 1.0f64) * 6.0f64 * c_eps() * v)
}

fn zetam1(s: f64) -> (f64, f64) {
    if s <= 5.0f64 {
        let (v, e) = zeta(s)
        ret (v - 1.0f64, e)
    }
    if s < 15.0f64 {
        let (v, e) = zeta_minus_1_intermediate(s)
        ret (v, e)
    }
    let (v, e) = zeta_minus1_large_s(s)
    ret (v, e)
}

// zeta(n) of an integer n >= 2: gsl reads a table of correctly rounded values (error 2 eps |value|); beyond 100 the value is 1
fn zeta_int(n: usize) -> (f64, f64) {
    if n > 100usize { ret (1.0f64, c_eps()) }
    let (v, _e) = zeta(f64(n))
    ret (v, 2.0f64 * c_eps() * fa(v))
}

fn zetam1_int(n: usize) -> (f64, f64) {
    if n <= 100usize {
        var v = 0.0f64
        if n <= 5usize {
            let (z, _e) = zeta(f64(n))
            v = z - 1.0f64
        }
        if n > 5usize && n < 15usize {
            let (z, _e) = zeta_minus_1_intermediate(f64(n))
            v = z
        }
        if n >= 15usize {
            let (z, _e) = zeta_minus1_large_s(f64(n))
            v = z
        }
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    let (v2, e2) = zetam1(f64(n))
    ret (v2, e2)
}

fn eta(s: f64) -> (f64, f64) {
    if s > 100.0f64 { ret (1.0f64, c_eps()) }
    if fa(s - 1.0f64) < 10.0f64 * 7.4009597974140505e-04f64 {
        let del = s - 1.0f64
        let ln2 = 0.693147180559945309417232121458f64
        let c0 = ln2
        let c1 = ln2 * (0.577215664901532860606512090082f64 - 0.5f64 * ln2)
        let c2 = -0.0326862962794492996f64
        let c3 = 0.0015689917054155150f64
        let c4 = 0.00074987242112047532f64
        let v = c0 + del * (c1 + del * (c2 + del * (c3 + del * c4)))
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    let (zv, ze) = zeta(s)
    let ln2 = 0.693147180559945309417232121458f64
    let pv = math.exp[f64]((1.0f64 - s) * ln2)
    let pe = 2.0f64 * c_eps() * fa(pv)
    let v = (1.0f64 - pv) * zv
    var e = fa(pe * (ln2 * (1.0f64 - s)) * zv) + ze * fa(pv)
    e += 2.0f64 * c_eps() * fa(v)
    ret (v, e)
}

// eta(n) for an integer n >= 0: gsl reads a table (error 2 eps |value|); eta(0) = 1/2, eta(1) = ln 2
fn eta_int(n: usize) -> (f64, f64) {
    if n > 100usize { ret (1.0f64, c_eps()) }
    if n == 0usize { ret (0.5f64, 2.0f64 * c_eps() * 0.5f64) }
    if n == 1usize { ret (0.693147180559945309417232121458f64, 2.0f64 * c_eps() * 0.693147180559945309417232121458f64) }
    let (z, _e) = zeta(f64(n))
    let v = (1.0f64 - math.pow[f64](2.0f64, 1.0f64 - f64(n))) * z
    ret (v, 2.0f64 * c_eps() * fa(v))
}
