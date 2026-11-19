// R gsl: erf, erfc, log_erfc, erf_Q and the hazard function with gsl's error estimates, a port of specfunc/erfc.c over the generated Chebyshev tables. Returns (value, error).

use e.math
use e.algo.stat.gslcheb as ch

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn mpi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn sqrtpi() -> f64 { ret 1.7724538509055160273f64 }

fn erfc8_sum(x: f64) -> f64 { ret ch.pv_erfc_P(x) / ch.pv_erfc_Q(x) }

fn erfc(x: f64) -> (f64, f64) {
    let ax = fa(x)
    var ev = 0.0f64
    var ee = 0.0f64
    if ax <= 1.0f64 {
        let (cv, ce) = ch.cvv_erfc_erfc_xlt1(2.0f64 * ax - 1.0f64)
        ev = cv
        ee = ce
    }
    if ax > 1.0f64 && ax <= 5.0f64 {
        let ex2 = math.exp[f64](0.0f64 - x * x)
        let (cv, ce) = ch.cvv_erfc_erfc_x15(0.5f64 * (ax - 3.0f64))
        ev = ex2 * cv
        ee = ex2 * (ce + 2.0f64 * fa(x) * c_eps())
    }
    if ax > 5.0f64 && ax < 10.0f64 {
        let exterm = math.exp[f64](0.0f64 - x * x) / ax
        let (cv, ce) = ch.cvv_erfc_erfc_x510((2.0f64 * ax - 15.0f64) / 5.0f64)
        ev = exterm * cv
        ee = exterm * (ce + 2.0f64 * fa(x) * c_eps() + c_eps())
    }
    if ax >= 10.0f64 {
        ev = erfc8_sum(ax) * math.exp[f64](0.0f64 - ax * ax)
        ee = (x * x + 1.0f64) * c_eps() * fa(ev)
    }
    var v = ev
    if x < 0.0f64 { v = 2.0f64 - ev }
    ret (v, ee + 2.0f64 * c_eps() * fa(v))
}

fn erf(x: f64) -> (f64, f64) {
    if fa(x) < 1.0f64 {
        var coef = x
        var e = coef
        var del = 0.0f64
        var k = 1usize
        while k < 30usize {
            coef *= 0.0f64 - x * x / f64(k)
            del = coef / (2.0f64 * f64(k) + 1.0f64)
            e += del
            k += 1usize
        }
        ret (2.0f64 / sqrtpi() * e, 2.0f64 / sqrtpi() * (fa(del) + c_eps()))
    }
    let (cv, ce) = erfc(x)
    let v = 1.0f64 - cv
    ret (v, ce + 2.0f64 * c_eps() * fa(v))
}

fn log_erfc(x: f64) -> (f64, f64) {
    if x * x < 10.0f64 * 2.4607833005759251e-03f64 {
        let y = x / sqrtpi()
        let pi = mpi()
        let c3 = (4.0f64 - pi) / 3.0f64
        let c4 = 2.0f64 * (1.0f64 - pi / 3.0f64)
        let c5 = -0.001829764677455021f64
        let c6 = 0.02629651521057465f64
        let c7 = -0.01621575378835404f64
        let c8 = 0.00125993961762116f64
        let c9 = 0.00556964649138f64
        let c10 = -0.0045563339802f64
        let c11 = 0.0009461589032f64
        let c12 = 0.0013200243174f64
        let c13 = -0.00142906f64
        let c14 = 0.00048204f64
        var series = c8 + y * (c9 + y * (c10 + y * (c11 + y * (c12 + y * (c13 + c14 * y)))))
        series = y * (1.0f64 + y * (1.0f64 + y * (c3 + y * (c4 + y * (c5 + y * (c6 + y * (c7 + y * series)))))))
        let v = -2.0f64 * series
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    if x > 8.0f64 {
        let v = math.log[f64](erfc8_sum(x)) - x * x
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    let (rv, re) = erfc(x)
    let v = math.log[f64](rv)
    ret (v, fa(re / rv) + 2.0f64 * c_eps() * fa(v))
}

fn erf_q(x: f64) -> (f64, f64) {
    let (rv, re) = erfc(x / 1.4142135623730950488f64)
    let v = 0.5f64 * rv
    ret (v, 0.5f64 * re + 2.0f64 * c_eps() * fa(v))
}

fn hazard(x: f64) -> (f64, f64) {
    if x < 25.0f64 {
        let (lv, le) = log_erfc(x / 1.4142135623730950488f64)
        let lnc = -0.22579135264472743236f64
        let arg = lnc - 0.5f64 * x * x - lv
        let v = math.exp[f64](arg)
        var e = 2.0f64 * c_eps() * fa(v)
        e += 3.0f64 * (1.0f64 + fa(x)) * c_eps() * fa(v)
        e += fa(le * v)
        ret (v, e)
    }
    let ix2 = 1.0f64 / (x * x)
    let corr_b = 1.0f64 - 9.0f64 * ix2 * (1.0f64 - 11.0f64 * ix2)
    let corr_m = 1.0f64 - 5.0f64 * ix2 * (1.0f64 - 7.0f64 * ix2 * corr_b)
    let corr_t = 1.0f64 - ix2 * (1.0f64 - 3.0f64 * ix2 * corr_m)
    let v = x / corr_t
    ret (v, 2.0f64 * c_eps() * fa(v))
}
