// exp and log as R on Windows computes them: the compiler runtime evaluates them in the x87 extended type (64-bit mantissa) and rounds the result to double, so a result that lies within
// 2^-11 of a rounding boundary of the double grid is rounded twice. The value is formed in double-double (gbmfit's), rounded to a 64-bit mantissa, then to 53 bits.
// Against R's own exp and log on 5000 arguments this agrees where a correctly rounded value misses about one in 1500.

use e.algo.stat.gbmfit as gb
use e.math
use e.mem

// hi + lo (hi the double nearest the sum) rounded to 64 mantissa bits with ties to even, then to double
fn r64(hi: f64, lo: f64) -> f64 {
    let bits = mem.bitcast[u64](math.abs[f64](hi))
    let ex = i64((bits >> 52u64) & 2047u64) - 1023i64
    if ex < -1000i64 || ex > 1000i64 { ret hi + lo }
    let c2 = 1.5f64 * math.power_of_two(ex - 11i64)
    let lr = (lo + c2) - c2
    ret hi + lr
}

fn exp_r(x: f64) -> f64 {
    if x != x || x > 700.0f64 || x < 0.0f64 - 700.0f64 { ret gb.cr_exp(x) }
    var k = 0i64
    var hi = 0.0f64
    var lo = 0.0f64
    gb.exp_dd(x, &k, &hi, &lo)
    let sc = math.power_of_two(k)
    ret r64(hi * sc, lo * sc)
}

fn log_r(x: f64) -> f64 {
    if !(x > 1.0e-290f64) || x > 1.0e290f64 { ret math.log[f64](x) }
    let y0 = math.log[f64](x)
    var k = 0i64
    var hi = 0.0f64
    var lo = 0.0f64
    gb.exp_dd(y0, &k, &hi, &lo)
    let sc = math.power_of_two(k)
    let e0h = hi * sc
    let e0l = lo * sc
    let t = ((x - e0h) - e0l) / e0h
    let (yh, yl) = gb.two_sum(y0, t)
    ret r64(yh, yl)
}
