// R gsl: the real dilogarithm Li_2(x) with gsl's error estimate, a port of gsl_sf_dilog_e (specfunc/dilog.c). Returns (value, error).

use e.math

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn pi2() -> f64 {
    let p = 3.141592653589793238462643383279f64
    ret p * p
}

fn series_1(x: f64) -> (f64, f64) {
    var sum = x
    var term = x
    var k = 2usize
    while k < 1000usize {
        let rk = (f64(k) - 1.0f64) / f64(k)
        term *= x
        term *= rk * rk
        sum += term
        if fa(term / sum) < c_eps() { break }
        k += 1usize
    }
    ret (sum, 2.0f64 * fa(term) + 2.0f64 * c_eps() * fa(sum))
}

fn series_2(r: f64) -> (f64, f64) {
    var rk = r
    var sum = 0.5f64 * r
    var k = 2usize
    while k < 10usize {
        rk *= r
        sum += rk / (f64(k * k) * (f64(k) + 1.0f64))
        k += 1usize
    }
    while k < 100usize {
        rk *= r
        let ds = rk / (f64(k * k) * (f64(k) + 1.0f64))
        sum += ds
        if fa(ds / sum) < 0.5f64 * c_eps() { break }
        k += 1usize
    }
    ret (sum, 2.0f64 * 100.0f64 * c_eps() * fa(sum))
}

fn dilog_series_2(x: f64) -> (f64, f64) {
    let (sv, se) = series_2(x)
    var t = 0.0f64
    if x > 0.01f64 {
        t = (1.0f64 - x) * math.log[f64](1.0f64 - x) / x
    }
    if !(x > 0.01f64) {
        let t68 = 1.0f64 / 6.0f64 + x * (1.0f64 / 7.0f64 + x * (1.0f64 / 8.0f64))
        let t38 = 1.0f64 / 3.0f64 + x * (1.0f64 / 4.0f64 + x * (1.0f64 / 5.0f64 + x * t68))
        t = (x - 1.0f64) * (1.0f64 + x * (0.5f64 + x * t38))
    }
    ret (sv + 1.0f64 + t, se + 2.0f64 * c_eps() * fa(t))
}

fn dilog_xge0(x: f64) -> (f64, f64) {
    if x > 2.0f64 {
        let (sv, se) = dilog_series_2(1.0f64 / x)
        let log_x = math.log[f64](x)
        let t1 = pi2() / 3.0f64
        let t2 = sv
        let t3 = 0.5f64 * log_x * log_x
        let v = t1 - t2 - t3
        var e = c_eps() * fa(log_x) + se
        e += c_eps() * (fa(t1) + fa(t2) + fa(t3))
        e += 2.0f64 * c_eps() * fa(v)
        ret (v, e)
    }
    if x > 1.01f64 {
        let (sv, se) = dilog_series_2(1.0f64 - 1.0f64 / x)
        let log_x = math.log[f64](x)
        let log_term = log_x * (math.log[f64](1.0f64 - 1.0f64 / x) + 0.5f64 * log_x)
        let t1 = pi2() / 6.0f64
        let t2 = sv
        let t3 = log_term
        let v = t1 + t2 - t3
        var e = c_eps() * fa(log_x) + se
        e += c_eps() * (fa(t1) + fa(t2) + fa(t3))
        e += 2.0f64 * c_eps() * fa(v)
        ret (v, e)
    }
    if x > 1.0f64 {
        let ep = x - 1.0f64
        let lne = math.log[f64](ep)
        let c0 = pi2() / 6.0f64
        let c1 = 1.0f64 - lne
        let c2 = 0.0f64 - (1.0f64 - 2.0f64 * lne) / 4.0f64
        let c3 = (1.0f64 - 3.0f64 * lne) / 9.0f64
        let c4 = 0.0f64 - (1.0f64 - 4.0f64 * lne) / 16.0f64
        let c5 = (1.0f64 - 5.0f64 * lne) / 25.0f64
        let c6 = 0.0f64 - (1.0f64 - 6.0f64 * lne) / 36.0f64
        let c7 = (1.0f64 - 7.0f64 * lne) / 49.0f64
        let c8 = 0.0f64 - (1.0f64 - 8.0f64 * lne) / 64.0f64
        let v = c0 + ep * (c1 + ep * (c2 + ep * (c3 + ep * (c4 + ep * (c5 + ep * (c6 + ep * (c7 + ep * c8)))))))
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    if x == 1.0f64 { ret (pi2() / 6.0f64, 2.0f64 * c_eps() * pi2() / 6.0f64) }
    if x > 0.5f64 {
        let (sv, se) = dilog_series_2(1.0f64 - x)
        let log_x = math.log[f64](x)
        let t1 = pi2() / 6.0f64
        let t2 = sv
        let t3 = log_x * math.log[f64](1.0f64 - x)
        let v = t1 - t2 - t3
        var e = c_eps() * fa(log_x) + se
        e += c_eps() * (fa(t1) + fa(t2) + fa(t3))
        e += 2.0f64 * c_eps() * fa(v)
        ret (v, e)
    }
    if x > 0.25f64 {
        let (v, e) = dilog_series_2(x)
        ret (v, e)
    }
    if x > 0.0f64 {
        let (v, e) = series_1(x)
        ret (v, e)
    }
    ret (0.0f64, 0.0f64)
}

fn dilog(x: f64) -> (f64, f64) {
    if x >= 0.0f64 {
        let (v, e) = dilog_xge0(x)
        ret (v, e)
    }
    let (d1v, d1e) = dilog_xge0(0.0f64 - x)
    let (d2v, d2e) = dilog_xge0(x * x)
    let v = 0.0f64 - d1v + 0.5f64 * d2v
    ret (v, d1e + 0.5f64 * d2e + 2.0f64 * c_eps() * fa(v))
}
