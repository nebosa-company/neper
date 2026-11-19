// R gsl: the Debye functions D_1 to D_4 with gsl's error estimates, a port of specfunc/debye.c over the generated Chebyshev tables. Returns (value, error); x < 0 is a domain error (0, 0).

use e.math
use e.algo.stat.gslcheb as ch

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }

fn debye(n: usize, x: f64) -> (f64, f64) {
    if x < 0.0f64 { ret (0.0f64, 0.0f64) }
    var vinf = 1.64493406684822644f64
    if n == 2usize { vinf = 4.80822761263837714f64 }
    if n == 3usize { vinf = 19.4818182068004875f64 }
    if n == 4usize { vinf = 99.5450644937635129f64 }
    let xcut = 7.0839641853226408e+02f64
    let nf = f64(n)
    let sq = 1.4901161193847656e-08f64
    // small x
    if n == 1usize && x < 2.0f64 * sq {
        let v = 1.0f64 - 0.25f64 * x + x * x / 36.0f64
        ret (v, c_eps() * fa(v))
    }
    if n > 1usize && x < 2.0f64 * 1.4142135623730950488f64 * sq {
        var v = 1.0f64 - x / 3.0f64 + x * x / 24.0f64
        if n == 3usize { v = 1.0f64 - 3.0f64 * x / 8.0f64 + x * x / 20.0f64 }
        if n == 4usize { v = 1.0f64 - 2.0f64 * x / 5.0f64 + x * x / 18.0f64 }
        ret (v, c_eps() * v)
    }
    if x <= 4.0f64 {
        let t = x * x / 8.0f64 - 1.0f64
        var cv = 0.0f64
        var ce = 0.0f64
        var lin = 0.25f64 * x
        if n == 1usize {
            let (a, b) = ch.cvv_debye_adeb1(t)
            cv = a
            ce = b
        }
        if n == 2usize {
            let (a, b) = ch.cvv_debye_adeb2(t)
            cv = a
            ce = b
            lin = x / 3.0f64
        }
        if n == 3usize {
            let (a, b) = ch.cvv_debye_adeb3(t)
            cv = a
            ce = b
            lin = 0.375f64 * x
        }
        if n == 4usize {
            let (a, b) = ch.cvv_debye_adeb4(t)
            cv = a
            ce = b
            lin = 2.0f64 * x / 5.0f64
        }
        ret (cv - lin, ce + c_eps() * lin)
    }
    if x < 0.0f64 - (0.693147180559945309417232121458f64 - 36.04365338911715f64) {
        let nexp = math.floor[f64](xcut / x)
        let ex = math.exp[f64](0.0f64 - x)
        var sum = 0.0f64
        var xk = nexp * x
        var rk = nexp
        var i = i64(nexp)
        while i >= 1i64 {
            sum *= ex
            let xi = 1.0f64 / xk
            if n == 1usize { sum += (1.0f64 + 1.0f64 / xk) / rk }
            if n == 2usize { sum += (1.0f64 + 2.0f64 / xk + 2.0f64 / (xk * xk)) / rk }
            if n == 3usize { sum += (((6.0f64 * xi + 6.0f64) * xi + 3.0f64) * xi + 1.0f64) / rk }
            if n == 4usize { sum += ((((24.0f64 * xi + 24.0f64) * xi + 12.0f64) * xi + 4.0f64) * xi + 1.0f64) / rk }
            rk -= 1.0f64
            xk -= x
            i -= 1i64
        }
        var den = x
        if n == 2usize { den = x * x }
        if n == 3usize { den = x * x * x }
        if n == 4usize { den = x * x * x * x }
        let v = vinf / den - nf * sum * ex
        ret (v, c_eps() * fa(v))
    }
    if x < xcut {
        var v = 0.0f64
        if n == 1usize { v = (vinf - math.exp[f64](0.0f64 - x) * (x + 1.0f64)) / x }
        if n == 2usize {
            let x2 = x * x
            v = (vinf - 2.0f64 * (2.0f64 + 2.0f64 * x + x2) * math.exp[f64](0.0f64 - x)) / x2
        }
        if n == 3usize {
            let x3 = x * x * x
            v = (vinf - 3.0f64 * (6.0f64 + 6.0f64 * x + 3.0f64 * x * x + x3) * math.exp[f64](0.0f64 - x)) / x3
        }
        if n == 4usize {
            let x2 = x * x
            let x4 = x2 * x2
            v = (vinf - 4.0f64 * (24.0f64 + 24.0f64 * x + 12.0f64 * x2 + 4.0f64 * x2 * x + x4) * math.exp[f64](0.0f64 - x)) / x4
        }
        ret (v, c_eps() * fa(v))
    }
    var v = vinf / x
    if n == 2usize { v = (vinf / x) / x }
    if n == 3usize { v = ((vinf / x) / x) / x }
    if n == 4usize { v = (((vinf / x) / x) / x) / x }
    ret (v, c_eps() * fa(v))
}
