// R gsl, synchrotron_1, synchrotron_2 and transport_2 to transport_5 with gsl_sf_result.err. Each returns (value, error); a domain error or underflow returns (0, 0).

use e.math
use e.algo.stat.gslcheb2 as ch
use e.algo.stat.gslerr as ge

fn s_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn sa(x: f64) -> f64 { ret math.abs[f64](x) }
fn s_cbrt(x: f64) -> f64 { ret math.pow[f64](x, 1.0f64 / 3.0f64) }

fn synchrotron_1(x: f64) -> (f64, f64) {
    if x < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 2.0f64 * 1.4142135623730950488f64 * 1.4901161193847656e-08f64 {
        let z = s_cbrt(x)
        let cf = 1.0f64 - 8.43812762813205e-01f64 * z * z
        let v = 2.14952824153447863671f64 * z * cf
        ret (v, s_eps() * v)
    }
    if x <= 4.0f64 {
        let c0 = 3.141592653589793238462643383279f64 / 1.7320508075688772935f64
        let px = s_cbrt(x)
        let (p11, _pe) = ge.e_pow_int(px, 11i64)
        let t = x * x / 8.0f64 - 1.0f64
        let (c1v, c1e) = ch.cvv_synchrotron_synchrotron1(t)
        let (c2v, c2e) = ch.cvv_synchrotron_synchrotron2(t)
        let v = px * c1v - p11 * c2v - c0 * x
        var er = px * c1e + p11 * c2e + c0 * x * s_eps()
        er += 2.0f64 * s_eps() * sa(v)
        ret (v, er)
    }
    if x < 8.0f64 * 708.39641853226408f64 / 7.0f64 {
        let c0 = 0.2257913526447274323630976f64
        let t = (12.0f64 - x) / (x + 4.0f64)
        let (cv, _ce) = ch.cvv_synchrotron_synchrotron1a(t)
        let v = math.sqrt[f64](x) * cv * math.exp[f64](c0 - x)
        ret (v, 2.0f64 * s_eps() * v * (sa(c0 - x) + 1.0f64))
    }
    ret (0.0f64, 0.0f64)
}

fn synchrotron_2(x: f64) -> (f64, f64) {
    if x < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 2.0f64 * 1.4142135623730950488f64 * 1.4901161193847656e-08f64 {
        let z = s_cbrt(x)
        let cf = 1.0f64 - 1.17767156510235e+00f64 * z * x
        let v = 1.07476412076723931836f64 * z * cf
        ret (v, 2.0f64 * s_eps() * v)
    }
    if x <= 4.0f64 {
        let px = s_cbrt(x)
        let (p5, _pe) = ge.e_pow_int(px, 5i64)
        let t = x * x / 8.0f64 - 1.0f64
        let (c1v, c1e) = ch.cvv_synchrotron_synchrotron21(t)
        let (c2v, c2e) = ch.cvv_synchrotron_synchrotron22(t)
        let v = px * c1v - p5 * c2v
        ret (v, px * c1e + p5 * c2e + 2.0f64 * s_eps() * sa(v))
    }
    if x < 8.0f64 * 708.39641853226408f64 / 7.0f64 {
        let c0 = 0.22579135264472743236f64
        let t = (10.0f64 - x) / (x + 2.0f64)
        let (cv, _ce) = ch.cvv_synchrotron_synchrotron2a(t)
        let v = math.sqrt[f64](x) * math.exp[f64](c0 - x) * cv
        ret (v, s_eps() * v * (sa(c0 - x) + 1.0f64))
    }
    ret (0.0f64, 0.0f64)
}

fn transport_sumexp(numexp: i64, order: i64, t: f64, x: f64) -> f64 {
    var rk = f64(numexp)
    var sumexp = 0.0f64
    var k = 1i64
    while k <= numexp {
        var sum2 = 1.0f64
        let xk = 1.0f64 / (rk * x)
        var xk1 = 1.0f64
        var j = 1i64
        while j <= order {
            sum2 = sum2 * xk1 * xk + 1.0f64
            xk1 += 1.0f64
            j += 1i64
        }
        sumexp = sumexp * t
        sumexp += sum2
        rk -= 1.0f64
        k += 1i64
    }
    ret sumexp
}

fn transport_cheb(n: usize, t: f64) -> (f64, f64) {
    if n == 2usize {
        let (v, e) = ch.cvv_transport_transport2(t)
        ret (v, e)
    }
    if n == 3usize {
        let (v, e) = ch.cvv_transport_transport3(t)
        ret (v, e)
    }
    if n == 4usize {
        let (v, e) = ch.cvv_transport_transport4(t)
        ret (v, e)
    }
    let (v5, e5) = ch.cvv_transport_transport5(t)
    ret (v5, e5)
}

// the tail val_infinity - exp(t) shared by the three large-x branches; plus1 is whether the error carries (|t| + 1) or |t|
fn transport_tail(vinf: f64, t: f64, plus1: bool) -> (f64, f64) {
    if t < -36.04365338911715f64 { ret (vinf, 2.0f64 * s_eps() * vinf) }
    let et = math.exp[f64](t)
    var w = sa(t)
    if plus1 { w = sa(t) + 1.0f64 }
    ret (vinf - et, 2.0f64 * s_eps() * (vinf + w * et))
}

fn transport(n: usize, x: f64) -> (f64, f64) {
    var vinf = 3.289868133696452873f64
    if n == 3usize { vinf = 7.212341418957565712f64 }
    if n == 4usize { vinf = 25.97575760906731660f64 }
    if n == 5usize { vinf = 124.4313306172043912f64 }
    let fn_ = f64(n)
    if x < 0.0f64 { ret (0.0f64, 0.0f64) }
    if n > 2usize && x == 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 3.0f64 * 1.4901161193847656e-08f64 {
        if n == 2usize { ret (x, s_eps() * sa(x) + x * x / 2.0f64) }
        if n == 3usize {
            let v = 0.5f64 * x * x
            ret (v, 2.0f64 * s_eps() * v)
        }
        if n == 4usize {
            let v = x * x * x / 3.0f64
            ret (v, 3.0f64 * s_eps() * v)
        }
        let v5 = x * x * x * x / 4.0f64
        ret (v5, 4.0f64 * s_eps() * v5)
    }
    if x <= 4.0f64 {
        let x2 = x * x
        let t = (x2 / 8.0f64 - 0.5f64) - 0.5f64
        let (cv, ce) = transport_cheb(n, t)
        var pre = x
        if n == 3usize { pre = x2 }
        if n == 4usize { pre = x2 * x }
        if n == 5usize { pre = x2 * x2 }
        let v = pre * cv
        var k = 2.0f64
        if n == 3usize { k = 1.0f64 }
        ret (v, pre * ce + k * s_eps() * sa(v))
    }
    var limit = 2.0f64
    if n >= 3usize { limit = 3.0f64 }
    let plus1 = n >= 4usize
    if x < 36.04365338911715f64 {
        let numexp = i64(36.04365338911715f64 / x) + 1i64
        let sumexp = transport_sumexp(numexp, i64(n), math.exp[f64](0.0f64 - x), x)
        let t = fn_ * math.log[f64](x) - x + math.log[f64](sumexp)
        let (v, e) = transport_tail(vinf, t, plus1)
        ret (v, e)
    }
    if x < limit / s_eps() {
        let sumexp2 = transport_sumexp(1i64, i64(n), 1.0f64, x)
        let t2 = fn_ * math.log[f64](x) - x + math.log[f64](sumexp2)
        let (v2, e2) = transport_tail(vinf, t2, true)
        ret (v2, e2)
    }
    let t3 = fn_ * math.log[f64](x) - x
    let (v3, e3) = transport_tail(vinf, t3, true)
    ret (v3, e3)
}
