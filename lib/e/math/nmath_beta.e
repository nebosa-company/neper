// The beta side of nmath: lbeta, d and p of the beta distribution (p through the TOMS 708 ratio
// bratio), the binomial density through the saddle-point terms (stirlerr, bd0) and the binomial
// distribution function through pbeta.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.toms708 as tm

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn lbeta(a: f64, b: f64) -> f64 {
    if a != a || b != b { ret a + b }
    var p = a
    var q = a
    if b < p { p = b }
    if b > q { q = b }
    if p < 0.0f64 { ret nan() }
    if p == 0.0f64 { ret inf() }
    if !finite(q) { ret 0.0f64 - inf() }
    if p >= 10.0f64 {
        let corr = nm.lgammacor(p) + nm.lgammacor(q) - nm.lgammacor(p + q)
        ret math.log[f64](q) * -0.5f64 + 0.918938533204672741780329736406f64 + corr + (p - 0.5f64) * math.log[f64](p / (p + q)) + q * dist.log1p(0.0f64 - p / (p + q))
    }
    if q >= 10.0f64 {
        let corr = nm.lgammacor(q) - nm.lgammacor(p + q)
        ret nm.lgammafn(p) + corr + p - p * math.log[f64](p + q) + (q - 0.5f64) * dist.log1p(0.0f64 - p / (p + q))
    }
    if p < 1e-306f64 { ret nm.lgammafn(p) + (nm.lgammafn(q) - nm.lgammafn(p + q)) }
    ret math.log[f64](nm.gammafn(p) * (nm.gammafn(q) / nm.gammafn(p + q)))
}

fn pbeta_raw(x: f64, a: f64, b: f64, lower: bool, lg: bool) -> f64 {
    if x >= 1.0f64 { ret dist.dt1(lower, lg) }
    if a == 0.0f64 || b == 0.0f64 || !finite(a) || !finite(b) {
        if a == 0.0f64 && b == 0.0f64 {
            if lg { ret -0.693147180559945309417232121458f64 }
            ret 0.5f64
        }
        if a == 0.0f64 || a / b == 0.0f64 { ret dist.dt1(lower, lg) }
        if b == 0.0f64 || b / a == 0.0f64 { ret dist.dt0(lower, lg) }
        if x < 0.5f64 { ret dist.dt0(lower, lg) }
        ret dist.dt1(lower, lg)
    }
    if x <= 0.0f64 { ret dist.dt0(lower, lg) }
    let x1 = 0.5f64 - x + 0.5f64
    let (w, wc, ierr) = tm.bratio(a, b, x, x1, lg)
    if lower { ret w }
    ret wc
}

fn pbeta(x: f64, a: f64, b: f64, lower: bool, lg: bool) -> f64 {
    if x != x || a != a || b != b { ret x + a + b }
    if a < 0.0f64 || b < 0.0f64 { ret nan() }
    ret pbeta_raw(x, a, b, lower, lg)
}

fn pow1p(x: f64, y: f64) -> f64 {
    if y != y {
        if x == 0.0f64 { ret 1.0f64 }
        ret y
    }
    if 0.0f64 <= y && y == math.trunc[f64](y) && y <= 4.0f64 {
        let k = i64(y)
        if k == 0i64 { ret 1.0f64 }
        if k == 1i64 { ret x + 1.0f64 }
        if k == 2i64 { ret x * (x + 2.0f64) + 1.0f64 }
        if k == 3i64 { ret x * (x * (x + 3.0f64) + 3.0f64) + 1.0f64 }
        ret x * (x * (x * (x + 4.0f64) + 6.0f64) + 4.0f64) + 1.0f64
    }
    let xp1 = x + 1.0f64
    let x_ = xp1 - 1.0f64
    if x_ == x || nm.abs_of(x) > 0.5f64 || x != x { ret math.pow[f64](xp1, y) }
    ret math.exp[f64](y * dist.log1p(x))
}

fn dbinom_raw(x: f64, n0: f64, p: f64, q: f64, lg: bool) -> f64 {
    var n = n0
    if p == 0.0f64 {
        if x == 0.0f64 { ret dist.d1(lg) }
        ret dist.d0(lg)
    }
    if q == 0.0f64 {
        if x == n { ret dist.d1(lg) }
        ret dist.d0(lg)
    }
    if x == 0.0f64 {
        if n == 0.0f64 { ret dist.d1(lg) }
        if p > q {
            if lg { ret n * math.log[f64](q) }
            ret math.pow[f64](q, n)
        }
        if lg { ret n * dist.log1p(0.0f64 - p) }
        ret pow1p(0.0f64 - p, n)
    }
    if x == n {
        if p > q {
            if lg { ret n * dist.log1p(0.0f64 - q) }
            ret pow1p(0.0f64 - q, n)
        }
        if lg { ret n * math.log[f64](p) }
        ret math.pow[f64](p, n)
    }
    if x < 0.0f64 || x > n { ret dist.d0(lg) }
    if !finite(n) {
        if finite(x) { ret dist.d0(lg) }
        n = 1.7976931348623157e308f64
    }
    let lc = nm.stirlerr(n) - nm.stirlerr(x) - nm.stirlerr(n - x) - nm.bd0(x, n * p) - nm.bd0(n - x, n * q)
    let lf = 1.837877066409345483560659472811f64 + math.log[f64](x) + dist.log1p(0.0f64 - x / n)
    if lg { ret lc - 0.5f64 * lf }
    ret math.exp[f64](lc - 0.5f64 * lf)
}

fn dbeta(x: f64, a: f64, b: f64, lg: bool) -> f64 {
    if x != x || a != a || b != b { ret x + a + b }
    if a < 0.0f64 || b < 0.0f64 { ret nan() }
    if x < 0.0f64 || x > 1.0f64 { ret dist.d0(lg) }
    if a == 0.0f64 || b == 0.0f64 || !finite(a) || !finite(b) {
        if a == 0.0f64 && b == 0.0f64 {
            if x == 0.0f64 || x == 1.0f64 { ret inf() }
            ret dist.d0(lg)
        }
        if a == 0.0f64 || a / b == 0.0f64 {
            if x == 0.0f64 { ret inf() }
            ret dist.d0(lg)
        }
        if b == 0.0f64 || b / a == 0.0f64 {
            if x == 1.0f64 { ret inf() }
            ret dist.d0(lg)
        }
        if x == 0.5f64 { ret inf() }
        ret dist.d0(lg)
    }
    if x == 0.0f64 {
        if a > 1.0f64 { ret dist.d0(lg) }
        if a < 1.0f64 { ret inf() }
        ret dist.dval(b, lg)
    }
    if x == 1.0f64 {
        if b > 1.0f64 { ret dist.d0(lg) }
        if b < 1.0f64 { ret inf() }
        ret dist.dval(a, lg)
    }
    var lval = 0.0f64
    if a <= 2.0f64 || b <= 2.0f64 {
        lval = (a - 1.0f64) * math.log[f64](x) + (b - 1.0f64) * dist.log1p(0.0f64 - x) - lbeta(a, b)
    } else {
        lval = math.log[f64](a + b - 1.0f64) + dbinom_raw(a - 1.0f64, a + b - 2.0f64, x, 1.0f64 - x, true)
    }
    if lg { ret lval }
    ret math.exp[f64](lval)
}

fn nonint(x: f64) -> bool { ret nm.abs_of(x - math.round[f64](x)) > 1e-9f64 * nm.max2(1.0f64, nm.abs_of(x)) }

fn dbinom(x0: f64, n0: f64, p: f64, lg: bool) -> f64 {
    if x0 != x0 || n0 != n0 || p != p { ret x0 + n0 + p }
    if p < 0.0f64 || p > 1.0f64 || n0 < 0.0f64 || nonint(n0) { ret nan() }
    if nonint(x0) { ret dist.d0(lg) }
    if x0 < 0.0f64 || !finite(x0) { ret dist.d0(lg) }
    ret dbinom_raw(math.round[f64](x0), math.round[f64](n0), p, 1.0f64 - p, lg)
}

fn pbinom(x0: f64, n0: f64, p: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || n0 != n0 || p != p { ret x0 + n0 + p }
    if !finite(n0) || !finite(p) { ret nan() }
    if nonint(n0) { ret nan() }
    let n = math.round[f64](n0)
    if n < 0.0f64 || p < 0.0f64 || p > 1.0f64 { ret nan() }
    if x0 < 0.0f64 { ret dist.dt0(lower, lg) }
    let x = math.floor[f64](x0 + 1e-7f64)
    if n <= x { ret dist.dt1(lower, lg) }
    ret pbeta(p, x + 1.0f64, n - x, !lower, lg)
}
