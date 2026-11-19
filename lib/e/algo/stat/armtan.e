// tan as R computes it. R calls the C runtime's tan, which is not always the correctly rounded value (the Windows runtime's differs from it in a few percent of arguments, and so does
// glibc's in other ones), so the platform variants of this module call the runtime itself; this portable file is the correctly rounded value, used where no variant exists.

use e.algo.stat.gbmfit as gb
use e.math
use e.math.dist as dist

fn tan_c(x: f64) -> f64 { ret cr_tan_pos(x) }

fn atan_c(x: f64) -> f64 { ret math.atan[f64](x) }

// pcauchy(x), lower tail, no log, with the atan R calls
fn pcauchy_c(x: f64) -> f64 {
    if x != x { ret x }
    if math.abs[f64](x) > 1.0f64 {
        let y = atan_c(1.0f64 / x) / 3.141592653589793238462643383280f64
        if x > 0.0f64 { ret (0.5f64 - y) + 0.5f64 }
        ret 0.0f64 - y
    }
    ret 0.5f64 + atan_c(x) / 3.141592653589793238462643383280f64
}

fn dd_add(ah: f64, al: f64, bh: f64, bl: f64) -> (f64, f64) {
    let (s, e0) = gb.two_sum(ah, bh)
    let (r, t) = gb.two_sum(s, e0 + (al + bl))
    ret (r, t)
}

// tan of x in (0, 1.6) correctly rounded: sin and cos by their Taylor series in double-double (x is a double, so x * x is exact), the quotient rounded once. The C runtime's tan,
// which R calls, is within half an ulp but not always correctly rounded; this agrees with it far more often than a fdlibm kernel does
fn cr_tan_pos(x: f64) -> f64 {
    let (x2h, x2l) = gb.two_prod(x, x)
    var sh = x
    var sl = 0.0f64
    var th = x
    var tl = 0.0f64
    var ch = 1.0f64
    var cl = 0.0f64
    var ch2 = 1.0f64
    var cl2 = 0.0f64
    var k = 1usize
    while k <= 22usize {
        let kf = f64(2usize * k)
        let (ah, al) = gb.dd_mul(th, tl, x2h, x2l)
        let (bh, bl) = gb.dd_div_d(ah, al, (kf * (kf + 1.0f64)))
        th = 0.0f64 - bh
        tl = 0.0f64 - bl
        let (nh, nl) = dd_add(sh, sl, th, tl)
        sh = nh
        sl = nl
        let (ah2, al2) = gb.dd_mul(ch2, cl2, x2h, x2l)
        let (bh2, bl2) = gb.dd_div_d(ah2, al2, (kf * (kf - 1.0f64)))
        ch2 = 0.0f64 - bh2
        cl2 = 0.0f64 - bl2
        let (mh, ml) = dd_add(ch, cl, ch2, cl2)
        ch = mh
        cl = ml
        k += 1usize
    }
    let q1 = sh / ch
    let (p, pe) = gb.two_prod(q1, ch)
    let r = (((sh - p) - pe) + sl) - q1 * cl
    let q2 = r / ch
    let (qh, ql) = gb.two_sum(q1, q2)
    ret qh + ql
}

