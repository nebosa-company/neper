// Student t density, log scale, the way R 4.6 computes it with the C runtime's log, log1p and exp, so the last bit agrees with R's (bayespolr's prior gradient is a difference of two of
// these over 0.002, which magnifies one bit of either to 1e-13). The halves table of stirlerr and its other branches stay with e.math.nmath.

use e.algo.stat.armx87 as xe
use e.algo.stat.gbmfit as gb
use e.math
use e.math.dist as dist
use e.math.nmath as nm

// log1p correctly rounded: R's comes from the compiler runtime's extended precision code, which agrees with the correctly rounded value, not with the C runtime's log1p or a fdlibm one
fn log1p_r(x: f64) -> f64 {
    if x != x { ret x }
    if x <= 0.0f64 - 0.5f64 || x > 1.0e15f64 { ret math.log[f64](1.0f64 + x) }
    let ax = math.abs[f64](x)
    if ax < 1.0e-15f64 { ret x - x * x / 2.0f64 }
    let (uh, ul) = gb.two_sum(1.0f64, x)
    let y0 = dist.log1p(x)
    var k = 0i64
    var hi = 0.0f64
    var lo = 0.0f64
    gb.exp_dd(y0, &k, &hi, &lo)
    let sc = math.power_of_two(k)
    let e0h = hi * sc
    let e0l = lo * sc
    let t = (((uh - e0h) + ul) - e0l) / e0h
    ret y0 + t
}

fn bd0_r(x: f64, np: f64) -> f64 {
    if !dist.finite(x) || !dist.finite(np) || np == 0.0f64 { ret 0.0f64 / 0.0f64 }
    if math.abs[f64](x - np) < 0.1f64 * (x + np) {
        let d = x - np
        var v = d / (x + np)
        if d != 0.0f64 && v == 0.0f64 {
            let x_ = x / 4.0f64
            let n_ = np / 4.0f64
            v = (x_ - n_) / (x_ + n_)
        }
        var s = d / 2.0f64 * v
        if math.abs[f64](s * 2.0f64) < 2.2250738585072014e-308f64 { ret s * 2.0f64 }
        var ej = x * v
        v = v * v
        var j = 1i64
        while j < 1000i64 {
            ej = ej * v
            let s_ = s
            s = s + ej / f64(2i64 * j + 1i64)
            if s == s_ { ret s * 2.0f64 }
            j += 1i64
        }
    }
    var lg = 0.0f64
    let q = x / np
    if dist.finite(q) { lg = xe.log_r(q) } else { lg = xe.log_r(x) - xe.log_r(np) }
    if x > np { ret x * (lg - 1.0f64) + np }
    ret x * lg + np - x
}

// dt(x, n, log = TRUE) (lg) or dt(x, n)
fn dt_r(x: f64, n: f64, lg: bool) -> f64 {
    if x != x || n != n { ret x + n }
    if n <= 0.0f64 { ret 0.0f64 / 0.0f64 }
    if !dist.finite(x) { ret dist.d0(lg) }
    if !dist.finite(n) { ret dist.dnorm(x, 0.0f64, 1.0f64, lg) }
    let t = 0.0f64 - bd0_r(n / 2.0f64, (n + 1.0f64) / 2.0f64) + nm.stirlerr((n + 1.0f64) / 2.0f64) - nm.stirlerr(n / 2.0f64)
    let x2n = x * x / n
    var ax = 0.0f64
    var l_x2n = 0.0f64
    var u = 0.0f64
    let lrg = x2n > 1.0f64 / 2.220446049250313e-16f64
    if lrg {
        ax = math.abs[f64](x)
        l_x2n = xe.log_r(ax) - xe.log_r(n) / 2.0f64
        u = n * l_x2n
    } else if x2n > 0.2f64 {
        l_x2n = xe.log_r(1.0f64 + x2n) / 2.0f64
        u = n * l_x2n
    } else {
        l_x2n = log1p_r(x2n) / 2.0f64
        u = 0.0f64 - bd0_r(n / 2.0f64, (n + x * x) / 2.0f64) + x * x / 2.0f64
    }
    if lg {
        ret t - u - (0.918938533204672741780329736406f64 + l_x2n)
    }
    var i_sqrt = 0.0f64
    if lrg { i_sqrt = math.sqrt[f64](n) / ax } else { i_sqrt = xe.exp_r(0.0f64 - l_x2n) }
    ret xe.exp_r(t - u) * 0.398942280401432677939946059934f64 * i_sqrt
}
