// R's pnorm and dnorm on a standard normal argument with the correctly rounded exp and log R's C runtime gives (Neper's own math.exp differs in the last bit for one argument in ten);
// the code is dist.e's, line for line. Used where a fit must follow R's iteration to the bit (probit link).

use e.algo.stat.armx87 as xe
use e.algo.stat.gbmfit as gb
use e.math
use e.math.dist as dist

fn pnorm_both_cr(x: f64, i_tail: i64, lg: bool) -> (f64, f64) {
    let a0 = 2.2352520354606839287f64
    let a1 = 161.02823106855587881f64
    let a2 = 1067.6894854603709582f64
    let a3 = 18154.981253343561249f64
    let a4 = 0.065682337918207449113f64
    let b0 = 47.20258190468824187f64
    let b1 = 976.09855173777669322f64
    let b2 = 10260.932208618978205f64
    let b3 = 45507.789335026729956f64
    let c0 = 0.39894151208813466764f64
    let c1 = 8.8831497943883759412f64
    let c2 = 93.506656132177855979f64
    let c3 = 597.27027639480026226f64
    let c4 = 2494.5375852903726711f64
    let c5 = 6848.1904505362823326f64
    let c6 = 11602.651437647350124f64
    let c7 = 9842.7148383839780218f64
    let c8 = 1.0765576773720192317e-8f64
    let d0v = 22.266688044328115691f64
    let d1v = 235.38790178262499861f64
    let d2v = 1519.377599407554805f64
    let d3v = 6485.558298266760755f64
    let d4v = 18615.571640885098091f64
    let d5v = 34900.952721145977266f64
    let d6v = 38912.003286093271411f64
    let d7v = 19685.429676859990727f64
    let p0 = 0.21589853405795699f64
    let p1 = 0.1274011611602473639f64
    let p2 = 0.022235277870649807f64
    let p3 = 0.001421619193227893466f64
    let p4 = 2.9112874951168792e-5f64
    let p5 = 0.02307344176494017303f64
    let q0 = 1.28426009614491121f64
    let q1 = 0.468238212480865118f64
    let q2 = 0.0659881378689285515f64
    let q3 = 0.00378239633202758244f64
    let q4 = 7.29751555083966205e-5f64
    if x != x { ret (x, x) }
    let eps = 2.220446049250313e-16f64 * 0.5f64
    let lower = i_tail != 1i64
    let upper = i_tail != 0i64
    let y = math.abs[f64](x)
    var cum = 0.0f64
    var ccum = 0.0f64
    if y <= 0.67448975f64 {
        var xnum = 0.0f64
        var xden = 0.0f64
        if y > eps {
            let xsq = x * x
            xnum = a4 * xsq
            xden = xsq
            xnum = (xnum + a0) * xsq
            xden = (xden + b0) * xsq
            xnum = (xnum + a1) * xsq
            xden = (xden + b1) * xsq
            xnum = (xnum + a2) * xsq
            xden = (xden + b2) * xsq
        }
        let temp = x * (xnum + a3) / (xden + b3)
        if lower { cum = 0.5f64 + temp }
        if upper { ccum = 0.5f64 - temp }
        if lg {
            if lower { cum = xe.log_r(cum) }
            if upper { ccum = xe.log_r(ccum) }
        }
        ret (cum, ccum)
    }
    var temp = 0.0f64
    var xsq = 0.0f64
    var big = false
    if y <= 5.656854249492380195206754896838f64 {
        var xnum = c8 * y
        var xden = y
        xnum = (xnum + c0) * y
        xden = (xden + d0v) * y
        xnum = (xnum + c1) * y
        xden = (xden + d1v) * y
        xnum = (xnum + c2) * y
        xden = (xden + d2v) * y
        xnum = (xnum + c3) * y
        xden = (xden + d3v) * y
        xnum = (xnum + c4) * y
        xden = (xden + d4v) * y
        xnum = (xnum + c5) * y
        xden = (xden + d5v) * y
        xnum = (xnum + c6) * y
        xden = (xden + d6v) * y
        temp = (xnum + c7) / (xden + d7v)
    } else if (lg && y < 1.0e170f64) || (lower && -38.4674f64 < x && x < 8.2924f64) || (upper && -8.2924f64 < x && x < 38.4674f64) {
        let xs = 1.0f64 / (x * x)
        var xnum = p5 * xs
        var xden = xs
        xnum = (xnum + p0) * xs
        xden = (xden + q0) * xs
        xnum = (xnum + p1) * xs
        xden = (xden + q1) * xs
        xnum = (xnum + p2) * xs
        xden = (xden + q2) * xs
        xnum = (xnum + p3) * xs
        xden = (xden + q3) * xs
        temp = xs * (xnum + p4) / (xden + q4)
        temp = (0.398942280401432677939946059934f64 - temp) / y
        big = true
    } else {
        if x > 0.0f64 {
            cum = dist.d1(lg)
            ccum = dist.d0(lg)
        } else {
            cum = dist.d0(lg)
            ccum = dist.d1(lg)
        }
        ret (cum, ccum)
    }
    // do_del(X): X is y in the middle range and x in the tail
    var xx = y
    if big { xx = x }
    xsq = math.trunc[f64](xx * 16.0f64) / 16.0f64
    let del = (xx - xsq) * (xx + xsq)
    if lg {
        cum = (0.0f64 - xsq * (xsq / 2.0f64)) - del / 2.0f64 + xe.log_r(temp)
        if (lower && x > 0.0f64) || (upper && x <= 0.0f64) {
            ccum = dist.log1p(0.0f64 - xe.exp_r(0.0f64 - xsq * (xsq / 2.0f64)) * xe.exp_r(0.0f64 - del / 2.0f64) * temp)
        }
    } else {
        cum = xe.exp_r(0.0f64 - xsq * (xsq / 2.0f64)) * xe.exp_r(0.0f64 - del / 2.0f64) * temp
        ccum = 1.0f64 - cum
    }
    if x > 0.0f64 {
        let t = cum
        if lower { cum = ccum }
        ccum = t
    }
    ret (cum, ccum)
}

// pnorm(x) lower tail, no log
fn pnorm_cr(x: f64) -> f64 {
    if x != x { ret x }
    let (cum, ccum) = pnorm_both_cr(x, 0i64, false)
    let _ = ccum
    ret cum
}

// dnorm(x) with mean 0 and sd 1, no log
fn dnorm_cr(x0: f64) -> f64 {
    let x = math.abs[f64](x0)
    if x < 5.0f64 { ret 0.398942280401432677939946059934f64 * xe.exp_r(-0.5f64 * x * x) / 1.0f64 }
    if x > 38.56804624911f64 { ret 0.0f64 }
    let x1 = math.round[f64](x * 65536.0f64) / 65536.0f64
    let x2 = x - x1
    ret 0.398942280401432677939946059934f64 / 1.0f64 * (xe.exp_r(-0.5f64 * x1 * x1) * xe.exp_r((0.0f64 - 0.5f64 * x2 - x1) * x2))
}
