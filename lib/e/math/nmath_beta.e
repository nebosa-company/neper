// The beta side of nmath: lbeta, d and p of the beta distribution (p through the TOMS 708 ratio
// bratio), the binomial density through the saddle-point terms (stirlerr, bd0) and the binomial
// distribution function through pbeta.

use e.math
use e.math.dist as dist
use e.math.special as special
use e.mem
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

// --- t and F

fn dt(x: f64, n: f64, lg: bool) -> f64 {
    if x != x || n != n { ret x + n }
    if n <= 0.0f64 { ret nan() }
    if !finite(x) { ret dist.d0(lg) }
    if !finite(n) { ret dist.dnorm(x, 0.0f64, 1.0f64, lg) }
    let t = 0.0f64 - nm.bd0(n / 2.0f64, (n + 1.0f64) / 2.0f64) + nm.stirlerr((n + 1.0f64) / 2.0f64) - nm.stirlerr(n / 2.0f64)
    let x2n = x * x / n
    var ax = 0.0f64
    var l_x2n = 0.0f64
    var u = 0.0f64
    let lrg = x2n > 1.0f64 / 2.220446049250313e-16f64
    if lrg {
        ax = nm.abs_of(x)
        l_x2n = math.log[f64](ax) - math.log[f64](n) / 2.0f64
        u = n * l_x2n
    } else if x2n > 0.2f64 {
        l_x2n = math.log[f64](1.0f64 + x2n) / 2.0f64
        u = n * l_x2n
    } else {
        l_x2n = dist.log1p(x2n) / 2.0f64
        u = 0.0f64 - nm.bd0(n / 2.0f64, (n + x * x) / 2.0f64) + x * x / 2.0f64
    }
    if lg { ret t - u - (0.918938533204672741780329736406f64 + l_x2n) }
    var i_sqrt = 0.0f64
    if lrg { i_sqrt = math.sqrt[f64](n) / ax } else { i_sqrt = math.exp[f64](0.0f64 - l_x2n) }
    ret math.exp[f64](t - u) * 0.398942280401432677939946059934f64 * i_sqrt
}

fn pt(x: f64, n: f64, lower0: bool, lg: bool) -> f64 {
    var lower = lower0
    if x != x || n != n { ret x + n }
    if n <= 0.0f64 { ret nan() }
    if !finite(x) {
        if x < 0.0f64 { ret dist.dt0(lower, lg) }
        ret dist.dt1(lower, lg)
    }
    if !finite(n) { ret dist.pnorm(x, 0.0f64, 1.0f64, lower, lg) }
    let nx = 1.0f64 + (x / n) * x
    var val = 0.0f64
    if nx > 1e100f64 {
        let lval = -0.5f64 * n * (2.0f64 * math.log[f64](nm.abs_of(x)) - math.log[f64](n)) - lbeta(0.5f64 * n, 0.5f64) - math.log[f64](0.5f64 * n)
        if lg { val = lval } else { val = math.exp[f64](lval) }
    } else if n > x * x {
        val = pbeta(x * x / (n + x * x), 0.5f64, n / 2.0f64, false, lg)
    } else {
        val = pbeta(1.0f64 / nx, n / 2.0f64, 0.5f64, true, lg)
    }
    if x <= 0.0f64 { lower = !lower }
    if lg {
        if lower { ret dist.log1p(-0.5f64 * math.exp[f64](val)) }
        ret val - 0.693147180559945309417232121458f64
    }
    val = val / 2.0f64
    if lower { ret 0.5f64 - val + 0.5f64 }
    ret val
}

fn df(x: f64, m: f64, n: f64, lg: bool) -> f64 {
    if x != x || m != m || n != n { ret x + m + n }
    if m <= 0.0f64 || n <= 0.0f64 { ret nan() }
    if x < 0.0f64 { ret dist.d0(lg) }
    if x == 0.0f64 {
        if m > 2.0f64 { ret dist.d0(lg) }
        if m == 2.0f64 { ret dist.d1(lg) }
        ret inf()
    }
    if !finite(m) && !finite(n) {
        if x == 1.0f64 { ret inf() }
        ret dist.d0(lg)
    }
    if !finite(n) { ret nm.dgamma(x, m / 2.0f64, 2.0f64 / m, lg) }
    if m > 1e14f64 {
        let dens = nm.dgamma(1.0f64 / x, n / 2.0f64, 2.0f64 / n, lg)
        if lg { ret dens - 2.0f64 * math.log[f64](x) }
        ret dens / (x * x)
    }
    var f = 1.0f64 / (n + x * m)
    let q = n * f
    let p = x * m * f
    var dens = 0.0f64
    if m >= 2.0f64 {
        f = m * q / 2.0f64
        dens = dbinom_raw((m - 2.0f64) / 2.0f64, (m + n - 2.0f64) / 2.0f64, p, q, lg)
    } else {
        f = m * m * q / (2.0f64 * p * (m + n))
        dens = dbinom_raw(m / 2.0f64, (m + n) / 2.0f64, p, q, lg)
    }
    if lg { ret math.log[f64](f) + dens }
    ret f * dens
}

fn pf(x0: f64, df1: f64, df2: f64, lower: bool, lg: bool) -> f64 {
    var x = x0
    if x != x || df1 != df1 || df2 != df2 { ret x + df2 + df1 }
    if df1 <= 0.0f64 || df2 <= 0.0f64 { ret nan() }
    if x <= 0.0f64 { ret dist.dt0(lower, lg) }
    if x >= inf() { ret dist.dt1(lower, lg) }
    if df2 == inf() {
        if df1 == inf() {
            if x < 1.0f64 { ret dist.dt0(lower, lg) }
            if x == 1.0f64 {
                if lg { ret -0.693147180559945309417232121458f64 }
                ret 0.5f64
            }
            ret dist.dt1(lower, lg)
        }
        ret nm.pchisq(x * df1, df1, lower, lg)
    }
    if df1 == inf() { ret nm.pchisq(df2 / x, df2, !lower, lg) }
    if df1 * x > df2 {
        x = pbeta(df2 / (df2 + df1 * x), df2 / 2.0f64, df1 / 2.0f64, !lower, lg)
    } else {
        x = pbeta(df1 * x / (df2 + df1 * x), df1 / 2.0f64, df2 / 2.0f64, lower, lg)
    }
    if x != x { ret nan() }
    ret x
}

// --- geometric and negative binomial

fn dgeom(x0: f64, p: f64, lg: bool) -> f64 {
    if x0 != x0 || p != p { ret x0 + p }
    if p <= 0.0f64 || p > 1.0f64 { ret nan() }
    if nonint(x0) { ret dist.d0(lg) }
    if x0 < 0.0f64 || !finite(x0) || p == 0.0f64 { ret dist.d0(lg) }
    let x = math.round[f64](x0)
    let prob = dbinom_raw(0.0f64, x, p, 1.0f64 - p, lg)
    if lg { ret math.log[f64](p) + prob }
    ret p * prob
}

fn pgeom(x0: f64, p: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || p != p { ret x0 + p }
    if p <= 0.0f64 || p > 1.0f64 { ret nan() }
    if x0 < 0.0f64 { ret dist.dt0(lower, lg) }
    if !finite(x0) { ret dist.dt1(lower, lg) }
    var x = math.floor[f64](x0 + 1e-7f64)
    if p == 1.0f64 {
        if lower { x = 1.0f64 } else { x = 0.0f64 }
        if lg { ret math.log[f64](x) }
        ret x
    }
    x = dist.log1p(0.0f64 - p) * (x + 1.0f64)
    if lg { ret dist.dt_clog(x, lower, lg) }
    if lower { ret 0.0f64 - dist.expm1(x) }
    ret math.exp[f64](x)
}

fn dnbinom(x0: f64, size0: f64, prob: f64, lg: bool) -> f64 {
    var size = size0
    if x0 != x0 || size != size || prob != prob { ret x0 + size + prob }
    if prob <= 0.0f64 || prob > 1.0f64 || size < 0.0f64 { ret nan() }
    if nonint(x0) { ret dist.d0(lg) }
    if x0 < 0.0f64 || !finite(x0) { ret dist.d0(lg) }
    let x = math.round[f64](x0)
    if x == 0.0f64 {
        if size == 0.0f64 { ret dist.d1(lg) }
        if lg { ret size * math.log[f64](prob) }
        ret math.pow[f64](prob, size)
    }
    if !finite(size) { size = 1.7976931348623157e308f64 }
    if x < 1e-10f64 * size {
        var xx2s = 0.0f64
        if x < math.sqrt[f64](1.7976931348623157e308f64) {
            xx2s = (x * (x - 1.0f64)) / 2.0f64 / size
        } else {
            xx2s = x * (x / 2.0f64 / size)
        }
        let v = size * math.log[f64](prob) + x * (math.log[f64](size) + dist.log1p(0.0f64 - prob)) - nm.lgamma1p(x) + dist.log1p(xx2s)
        if lg { ret v }
        ret math.exp[f64](v)
    }
    var p = size / (size + x)
    if lg {
        if x < size { p = dist.log1p(0.0f64 - x / (size + x)) } else { p = math.log[f64](size / (size + x)) }
    }
    let ans = dbinom_raw(size, x + size, prob, 1.0f64 - prob, lg)
    if lg { ret p + ans }
    ret p * ans
}

fn dnbinom_mu(x0: f64, size: f64, mu: f64, lg: bool) -> f64 {
    if x0 != x0 || size != size || mu != mu { ret x0 + size + mu }
    if mu < 0.0f64 || size < 0.0f64 { ret nan() }
    if nonint(x0) { ret dist.d0(lg) }
    if x0 < 0.0f64 || !finite(x0) { ret dist.d0(lg) }
    if x0 == 0.0f64 && size == 0.0f64 { ret dist.d1(lg) }
    let x = math.round[f64](x0)
    if !finite(size) { ret nm.dpois_raw(x, mu, lg) }
    if x == 0.0f64 {
        var v = 0.0f64
        if size < mu { v = size * math.log[f64](size / (size + mu)) } else { v = size * dist.log1p(0.0f64 - mu / (size + mu)) }
        if lg { ret v }
        ret math.exp[f64](v)
    }
    if x < 1e-10f64 * size {
        var p = 0.0f64
        if size < mu { p = math.log[f64](size / (1.0f64 + size / mu)) } else { p = math.log[f64](mu / (1.0f64 + mu / size)) }
        var xx2s = 0.0f64
        if x < math.sqrt[f64](1.7976931348623157e308f64) {
            xx2s = (x * (x - 1.0f64)) / 2.0f64 / size
        } else {
            xx2s = x * (x / 2.0f64 / size)
        }
        let v = x * p - mu - nm.lgamma1p(x) + dist.log1p(xx2s)
        if lg { ret v }
        ret math.exp[f64](v)
    }
    var p = size / (size + x)
    if lg {
        if x < size { p = dist.log1p(0.0f64 - x / (size + x)) } else { p = math.log[f64](size / (size + x)) }
    }
    let ans = dbinom_raw(size, x + size, size / (size + mu), mu / (size + mu), lg)
    if lg { ret p + ans }
    ret p * ans
}

fn pnbinom(x0: f64, size: f64, prob: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || size != size || prob != prob { ret x0 + size + prob }
    if !finite(size) || !finite(prob) { ret nan() }
    if size < 0.0f64 || prob <= 0.0f64 || prob > 1.0f64 { ret nan() }
    if size == 0.0f64 {
        if x0 >= 0.0f64 { ret dist.dt1(lower, lg) }
        ret dist.dt0(lower, lg)
    }
    if x0 < 0.0f64 { ret dist.dt0(lower, lg) }
    if !finite(x0) { ret dist.dt1(lower, lg) }
    let x = math.floor[f64](x0 + 1e-7f64)
    ret pbeta(prob, size, x + 1.0f64, lower, lg)
}

fn pnbinom_mu(x0: f64, size: f64, mu: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || size != size || mu != mu { ret x0 + size + mu }
    if !finite(mu) { ret nan() }
    if size < 0.0f64 || mu < 0.0f64 { ret nan() }
    if size == 0.0f64 {
        if x0 >= 0.0f64 { ret dist.dt1(lower, lg) }
        ret dist.dt0(lower, lg)
    }
    if x0 < 0.0f64 { ret dist.dt0(lower, lg) }
    if !finite(x0) { ret dist.dt1(lower, lg) }
    if !finite(size) { ret nm.ppois(x0, mu, lower, lg) }
    let x = math.floor[f64](x0 + 1e-7f64)
    let (w, wc, ierr) = tm.bratio(size, x + 1.0f64, size / (size + mu), mu / (size + mu), lg)
    if lower { ret w }
    ret wc
}

// --- the discrete quantile search of qDiscrete_search.h: dist 0 binomial (n, pr), 1 negative binomial (size, prob)

fn pdisc(d: u8, y: f64, a: f64, b: f64, lower: bool, lg: bool) -> f64 {
    if d == 0u8 { ret pbinom(y, a, b, lower, lg) }
    if d == 2u8 { ret pnbinom_mu(y, a, b, lower, lg) }
    ret pnbinom(y, a, b, lower, lg)
}

fn do_search_disc(d: u8, y0: f64, z: f64, p: f64, a: f64, b: f64, incr: f64, lower: bool, lg: bool) -> (f64, f64) {
    var y = y0
    var zz = z
    var left = zz < p
    if lower { left = zz >= p }
    if left {
        var go = true
        while go {
            var newz = -1.0f64
            if y > 0.0f64 {
                newz = pdisc(d, y - incr, a, b, lower, lg)
            } else if y < 0.0f64 {
                y = 0.0f64
            }
            var stop = y == 0.0f64 || newz != newz
            if !stop {
                if lower { stop = newz < p } else { stop = newz >= p }
            }
            if stop { ret (y, zz) }
            y = nm.max2(0.0f64, y - incr)
            zz = newz
        }
    }
    while true {
        let prevy = y
        y += incr
        var newz = -1.0f64
        var at_max = false
        if d == 0u8 {
            if y < a {
                newz = pdisc(d, y, a, b, lower, lg)
            } else if y > a {
                y = a
            }
            at_max = y == a
        } else {
            newz = pdisc(d, y, a, b, lower, lg)
        }
        var stop = at_max || newz != newz
        if !stop {
            if lower { stop = newz >= p } else { stop = newz < p }
        }
        if stop {
            if incr <= 1.0f64 { ret (y, newz) }
            ret (prevy, zz)
        }
        zz = newz
    }
    ret (y, zz)
}

fn q_discrete(d: u8, p0: f64, a: f64, b: f64, mu: f64, sigma: f64, gam: f64, lower: bool, lg: bool) -> f64 {
    var p = p0
    let zq = dist.qnorm(p, 0.0f64, 1.0f64, lower, lg)
    var y = nm.rint(mu + sigma * (zq + gam * (zq * zq - 1.0f64) / 6.0f64))
    if d == 0u8 {
        if y > a { y = a } else if y < 0.0f64 { y = 0.0f64 }
    } else if y < 0.0f64 {
        y = 0.0f64
    }
    var z = pdisc(d, y, a, b, lower, lg)
    let eps = 2.220446049250313e-16f64
    if lg {
        let e = 2.0f64 * eps
        if lower && p > -1.7976931348623157e308f64 { p = p * (1.0f64 + e) } else { p = p * (1.0f64 - e) }
    } else {
        let e = 8.0f64 * eps
        if lower {
            p = p * (1.0f64 - e)
        } else if 1.0f64 - p > 4.0f64 * e {
            p = p * (1.0f64 + e)
        }
    }
    if y < 4096.0f64 {
        let (yy, zz) = do_search_disc(d, y, z, p, a, b, 1.0f64, lower, lg)
        ret yy
    }
    var incr = math.floor[f64](y * (1.0f64 / 64.0f64))
    var go = true
    while go {
        let oldincr = incr
        let (yy, zz) = do_search_disc(d, y, z, p, a, b, incr, lower, lg)
        y = yy
        z = zz
        incr = nm.max2(1.0f64, math.floor[f64](incr / 8.0f64))
        go = oldincr > 1.0f64 && incr > y * 1e-15f64
    }
    ret y
}

fn qbinom(p: f64, n0: f64, pr: f64, lower: bool, lg: bool) -> f64 {
    if p != p || n0 != n0 || pr != pr { ret p + n0 + pr }
    if !finite(n0) || !finite(pr) { ret nan() }
    if !finite(p) && !lg { ret nan() }
    let n = math.round[f64](n0)
    if pr < 0.0f64 || pr > 1.0f64 || n < 0.0f64 { ret nan() }
    if lg {
        if p > 0.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret n }
            ret 0.0f64
        }
        if p == 0.0f64 - inf() {
            if lower { ret 0.0f64 }
            ret n
        }
    } else {
        if p < 0.0f64 || p > 1.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret 0.0f64 }
            ret n
        }
        if p == 1.0f64 {
            if lower { ret n }
            ret 0.0f64
        }
    }
    if pr == 0.0f64 || n == 0.0f64 { ret 0.0f64 }
    if pr == 1.0f64 { ret n }
    let q = 1.0f64 - pr
    let mu = n * pr
    let sigma = math.sqrt[f64](n * pr * q)
    let gam = (q - pr) / sigma
    ret q_discrete(0u8, p, n, pr, mu, sigma, gam, lower, lg)
}

fn qnbinom(p: f64, size: f64, prob: f64, lower: bool, lg: bool) -> f64 {
    if p != p || size != size || prob != prob { ret p + size + prob }
    if prob == 0.0f64 && size == 0.0f64 { ret 0.0f64 }
    if prob <= 0.0f64 || prob > 1.0f64 || size < 0.0f64 { ret nan() }
    if prob == 1.0f64 || size == 0.0f64 { ret 0.0f64 }
    if lg {
        if p > 0.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret inf() }
            ret 0.0f64
        }
        if p == 0.0f64 - inf() {
            if lower { ret 0.0f64 }
            ret inf()
        }
    } else {
        if p < 0.0f64 || p > 1.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret 0.0f64 }
            ret inf()
        }
        if p == 1.0f64 {
            if lower { ret inf() }
            ret 0.0f64
        }
    }
    let qq = 1.0f64 / prob
    let pp = (1.0f64 - prob) * qq
    let mu = size * pp
    let sigma = math.sqrt[f64](size * pp * qq)
    let gam = (qq + pp) / sigma
    ret q_discrete(1u8, p, size, prob, mu, sigma, gam, lower, lg)
}

fn qnbinom_mu(p: f64, size: f64, mu: f64, lower: bool, lg: bool) -> f64 {
    if p != p || size != size || mu != mu { ret p + size + mu }
    if size == inf() { ret nm.qpois(p, mu, lower, lg) }
    if mu == 0.0f64 || size == 0.0f64 { ret 0.0f64 }
    if mu < 0.0f64 || size < 0.0f64 { ret nan() }
    if lg {
        if p > 0.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret inf() }
            ret 0.0f64
        }
        if p == 0.0f64 - inf() {
            if lower { ret 0.0f64 }
            ret inf()
        }
    } else {
        if p < 0.0f64 || p > 1.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret 0.0f64 }
            ret inf()
        }
        if p == 1.0f64 {
            if lower { ret inf() }
            ret 0.0f64
        }
    }
    let qq = 1.0f64 + mu / size
    let pp = mu / size
    let sigma = math.sqrt[f64](size * pp * qq)
    let gam = (qq + pp) / sigma
    ret q_discrete(2u8, p, size, mu, mu, sigma, gam, lower, lg)
}

fn qgeom(p: f64, prob: f64, lower: bool, lg: bool) -> f64 {
    if p != p || prob != prob { ret p + prob }
    if prob <= 0.0f64 || prob > 1.0f64 { ret nan() }
    if dist.bad_p(p, lg) { ret nan() }
    if prob == 1.0f64 { ret 0.0f64 }
    if p == dist.dt0(lower, lg) { ret 0.0f64 }
    if p == dist.dt1(lower, lg) { ret inf() }
    ret nm.max2(0.0f64, math.ceil[f64](dist.dt_clog(p, lower, lg) / dist.log1p(0.0f64 - prob) - 1.0f64 - 1e-12f64))
}

// --- hypergeometric

fn dhyper(x0: f64, r0: f64, b0: f64, n0: f64, lg: bool) -> f64 {
    if x0 != x0 || r0 != r0 || b0 != b0 || n0 != n0 { ret x0 + r0 + b0 + n0 }
    if r0 < 0.0f64 || nonint(r0) || b0 < 0.0f64 || nonint(b0) || n0 < 0.0f64 || nonint(n0) || n0 > r0 + b0 { ret nan() }
    if x0 < 0.0f64 { ret dist.d0(lg) }
    if nonint(x0) { ret dist.d0(lg) }
    let x = math.round[f64](x0)
    let r = math.round[f64](r0)
    let b = math.round[f64](b0)
    let n = math.round[f64](n0)
    if n < x || r < x || n - x > b { ret dist.d0(lg) }
    if n == 0.0f64 {
        if x == 0.0f64 { ret dist.d1(lg) }
        ret dist.d0(lg)
    }
    let p = n / (r + b)
    let q = (r + b - n) / (r + b)
    let p1 = dbinom_raw(x, r, p, q, lg)
    let p2 = dbinom_raw(n - x, b, p, q, lg)
    let p3 = dbinom_raw(n, r + b, p, q, lg)
    if lg { ret p1 + p2 - p3 }
    ret p1 * p2 / p3
}

fn pdhyper(x0: f64, nr: f64, nb: f64, n: f64, lg: bool) -> f64 {
    var x = x0
    var sum = 0.0f64
    var term = 1.0f64
    while x > 0.0f64 && term >= 2.220446049250313e-16f64 * sum {
        term = term * (x * (nb - n + x) / (n + 1.0f64 - x) / (nr + 1.0f64 - x))
        sum = sum + term
        x -= 1.0f64
    }
    if lg { ret dist.log1p(sum) }
    ret 1.0f64 + sum
}

fn phyper(x0: f64, nr0: f64, nb0: f64, n0: f64, lower0: bool, lg: bool) -> f64 {
    var lower = lower0
    if x0 != x0 || nr0 != nr0 || nb0 != nb0 || n0 != n0 { ret x0 + nr0 + nb0 + n0 }
    var x = math.floor[f64](x0 + 1e-7f64)
    var nr = math.round[f64](nr0)
    var nb = math.round[f64](nb0)
    let n = math.round[f64](n0)
    if nr < 0.0f64 || nb < 0.0f64 || !finite(nr + nb) || n < 0.0f64 || n > nr + nb { ret nan() }
    if x * (nr + nb) > n * nr {
        let old_nb = nb
        nb = nr
        nr = old_nb
        x = n - x - 1.0f64
        lower = !lower
    }
    if x < 0.0f64 || x < n - nb { ret dist.dt0(lower, lg) }
    if x >= nr || x >= n { ret dist.dt1(lower, lg) }
    let d = dhyper(x, nr, nb, n, lg)
    if (!lg && d == 0.0f64) || (lg && d == 0.0f64 - inf()) { ret dist.dt0(lower, lg) }
    let pd = pdhyper(x, nr, nb, n, lg)
    if lg {
        if lower { ret d + pd }
        ret dist.log1_exp(d + pd)
    }
    if lower { ret d * pd }
    ret 0.5f64 - d * pd + 0.5f64
}

fn lfastchoose(n: f64, k: f64) -> f64 { ret 0.0f64 - math.log[f64](n + 1.0f64) - lbeta(n - k + 1.0f64, k + 1.0f64) }

fn qhyper(p0: f64, nr0: f64, nb0: f64, n0: f64, lower: bool, lg: bool) -> f64 {
    var p = p0
    if p != p || nr0 != nr0 || nb0 != nb0 || n0 != n0 { ret p + nr0 + nb0 + n0 }
    if !finite(p) || !finite(nr0) || !finite(nb0) || !finite(n0) { ret nan() }
    var nr = math.round[f64](nr0)
    var nb = math.round[f64](nb0)
    let nn = nr + nb
    let n = math.round[f64](n0)
    if nr < 0.0f64 || nb < 0.0f64 || n < 0.0f64 || n > nn { ret nan() }
    var xstart = 0.0f64
    if n - nb > 0.0f64 { xstart = n - nb }
    var xend = n
    if nr < n { xend = nr }
    if lg {
        if p > 0.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret xend }
            ret xstart
        }
        if p == 0.0f64 - inf() {
            if lower { ret xstart }
            ret xend
        }
    } else {
        if p < 0.0f64 || p > 1.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret xstart }
            ret xend
        }
        if p == 1.0f64 {
            if lower { ret xend }
            ret xstart
        }
    }
    var xr = xstart
    var xb = n - xr
    let small_n = nn < 1000.0f64
    var term = lfastchoose(nr, xr) + lfastchoose(nb, xb) - lfastchoose(nn, n)
    if small_n { term = math.exp[f64](term) }
    nr -= xr
    nb -= xb
    if !lower || lg { p = dist.dt_qiv(p, lower, lg) }
    p = p * (1.0f64 - 1000.0f64 * 2.220446049250313e-16f64)
    var sum = 0.0f64
    if small_n { sum = term } else { sum = math.exp[f64](term) }
    while sum < p && xr < xend {
        xr += 1.0f64
        nb += 1.0f64
        if small_n {
            term = term * ((nr / xr) * (xb / nb))
        } else {
            term = term + math.log[f64]((nr / xr) * (xb / nb))
        }
        if small_n { sum += term } else { sum += math.exp[f64](term) }
        xb -= 1.0f64
        nr -= 1.0f64
    }
    ret xr
}

// --- Wilcoxon signed rank and rank sum

// The counts w[0..c] of the signed-rank statistic for n (csignrank's table), c = n (n + 1) / 4 floored.
fn signrank_table(a: *mem.Arena, n: i64) -> ([]f64, err) {
    let u = n * (n + 1i64) / 2i64
    let c = u / 2i64
    let (w, e) = mem.alloc[f64](a, usize(c) + 2usize)
    if e != ok { ret (w, e) }
    var i = 0usize
    while i <= usize(c) {
        w[i] = 0.0f64
        i += 1usize
    }
    w[0usize] = 1.0f64
    if c >= 1i64 { w[1usize] = 1.0f64 }
    var j = 2i64
    while j < n + 1i64 {
        var end = j * (j + 1i64) / 2i64
        if c < end { end = c }
        var k = end
        while k >= j {
            w[usize(k)] = w[usize(k)] + w[usize(k - j)]
            k -= 1i64
        }
        j += 1i64
    }
    ret (w, ok)
}

fn csignrank(w: []const f64, k0: i64, n: i64) -> f64 {
    let u = n * (n + 1i64) / 2i64
    let c = u / 2i64
    var k = k0
    if k < 0i64 || k > u { ret 0.0f64 }
    if k > c { k = u - k }
    if n == 1i64 { ret 1.0f64 }
    ret w[usize(k)]
}

fn dt_val(p: f64, lower: bool, lg: bool) -> f64 {
    if lower { ret dist.dval(p, lg) }
    ret dist.dclog(p, lg)
}

fn dsignrank(a: *mem.Arena, x0: f64, n0: f64, lg: bool) -> f64 {
    if x0 != x0 || n0 != n0 { ret x0 + n0 }
    let n = math.round[f64](n0)
    if n <= 0.0f64 { ret nan() }
    if nonint(x0) { ret dist.d0(lg) }
    let x = math.round[f64](x0)
    if x < 0.0f64 || x > n * (n + 1.0f64) / 2.0f64 { ret dist.d0(lg) }
    let nn = i64(n)
    let (w, e) = signrank_table(a, nn)
    if e != ok { ret nan() }
    let v = math.log[f64](csignrank(w, i64(x), nn)) - n * 0.693147180559945309417232121458f64
    if lg { ret v }
    ret math.exp[f64](v)
}

fn psignrank(a: *mem.Arena, x0: f64, n0: f64, lower0: bool, lg: bool) -> f64 {
    var lower = lower0
    if x0 != x0 || n0 != n0 { ret x0 + n0 }
    if !finite(n0) { ret nan() }
    let n = math.round[f64](n0)
    if n <= 0.0f64 { ret nan() }
    var x = math.floor[f64](x0 + 1e-7f64)
    if x < 0.0f64 { ret dist.dt0(lower, lg) }
    if x >= n * (n + 1.0f64) / 2.0f64 { ret dist.dt1(lower, lg) }
    let nn = i64(n)
    let (w, e) = signrank_table(a, nn)
    if e != ok { ret nan() }
    let f = math.exp[f64](0.0f64 - n * 0.693147180559945309417232121458f64)
    var p = 0.0f64
    if x <= n * (n + 1.0f64) / 4.0f64 {
        var i = 0i64
        while f64(i) <= x {
            p += csignrank(w, i, nn) * f
            i += 1i64
        }
    } else {
        x = n * (n + 1.0f64) / 2.0f64 - x
        var i = 0i64
        while f64(i) < x {
            p += csignrank(w, i, nn) * f
            i += 1i64
        }
        lower = !lower
    }
    ret dt_val(p, lower, lg)
}

fn qsignrank(a: *mem.Arena, x0: f64, n0: f64, lower: bool, lg: bool) -> f64 {
    var x = x0
    if x != x || n0 != n0 { ret x + n0 }
    if !finite(x) || !finite(n0) { ret nan() }
    if dist.bad_p(x, lg) { ret nan() }
    let n = math.round[f64](n0)
    if n <= 0.0f64 { ret nan() }
    if x == dist.dt0(lower, lg) { ret 0.0f64 }
    if x == dist.dt1(lower, lg) { ret n * (n + 1.0f64) / 2.0f64 }
    if lg || !lower { x = dist.dt_qiv(x, lower, lg) }
    let nn = i64(n)
    let (w, e) = signrank_table(a, nn)
    if e != ok { ret nan() }
    let f = math.exp[f64](0.0f64 - n * 0.693147180559945309417232121458f64)
    var p = 0.0f64
    var q = 0i64
    if x <= 0.5f64 {
        x = x - 10.0f64 * 2.220446049250313e-16f64
        var go = true
        while go {
            p += csignrank(w, q, nn) * f
            if p >= x { go = false } else { q += 1i64 }
        }
    } else {
        x = 1.0f64 - x + 10.0f64 * 2.220446049250313e-16f64
        var go = true
        while go {
            p += csignrank(w, q, nn) * f
            if p > x {
                q = i64(n * (n + 1.0f64) / 2.0f64) - q
                go = false
            } else {
                q += 1i64
            }
        }
    }
    ret f64(q)
}

// cwilcox's table for (m, n) with m <= n: w[0..k] by the divisor-sum recursion.
fn wilcox_table(a: *mem.Arena, m: i64, n: i64, kmax: i64) -> ([]f64, err) {
    let (w, e) = mem.alloc[f64](a, usize(kmax) + 2usize)
    let (sg, se) = mem.alloc[i64](a, usize(kmax) + 2usize)
    if e != ok { ret (w, e) }
    if se != ok { ret (w, se) }
    var k = 0i64
    while k <= kmax {
        if k == 0i64 {
            w[0usize] = 1.0f64
        } else {
            var s = 0i64
            var iter1 = m
            if k < m { iter1 = k }
            var iter2 = m + n
            if k < m + n { iter2 = k }
            var d = 1i64
            while d <= iter1 {
                if k % d == 0i64 { s += d }
                d += 1i64
            }
            d = n + 1i64
            while d <= iter2 {
                if k % d == 0i64 { s -= d }
                d += 1i64
            }
            sg[usize(k)] = s
            var acc = 0.0f64
            var i = 0i64
            while i < k {
                acc += w[usize(i)] * f64(sg[usize(k - i)])
                i += 1i64
            }
            w[usize(k)] = acc / f64(k)
        }
        k += 1i64
    }
    ret (w, ok)
}

fn cwilcox(w: []const f64, k0: i64, m: i64, n: i64) -> f64 {
    let u = m * n
    var k = k0
    if k < 0i64 || k > u { ret 0.0f64 }
    let c = u / 2i64
    if k > c { k = u - k }
    if m == 0i64 || n == 0i64 || k == 0i64 {
        if k == 0i64 { ret 1.0f64 }
        ret 0.0f64
    }
    ret w[usize(k)]
}

fn dwilcox(a: *mem.Arena, x0: f64, m0: f64, n0: f64, lg: bool) -> f64 {
    if x0 != x0 || m0 != m0 || n0 != n0 { ret x0 + m0 + n0 }
    let m = math.round[f64](m0)
    let n = math.round[f64](n0)
    if m <= 0.0f64 || n <= 0.0f64 { ret nan() }
    if nonint(x0) { ret dist.d0(lg) }
    let x = math.round[f64](x0)
    if x < 0.0f64 || x > m * n { ret dist.d0(lg) }
    var mi = i64(m)
    var ni = i64(n)
    if mi > ni {
        let t = mi
        mi = ni
        ni = t
    }
    let (w, e) = wilcox_table(a, mi, ni, mi * ni / 2i64)
    if e != ok { ret nan() }
    let cw = cwilcox(w, i64(x), mi, ni)
    if lg { ret math.log[f64](cw) - lchoose_int(m + n, n) }
    ret cw / special.choose(m + n, n)
}

fn lchoose_int(n: f64, k: f64) -> f64 {
    if k < 2.0f64 {
        if k < 0.0f64 { ret 0.0f64 - inf() }
        if k == 0.0f64 { ret 0.0f64 }
        ret math.log[f64](nm.abs_of(n))
    }
    if n - k < 2.0f64 { ret lchoose_int(n, n - k) }
    ret lfastchoose(n, k)
}

fn pwilcox(a: *mem.Arena, q0: f64, m0: f64, n0: f64, lower0: bool, lg: bool) -> f64 {
    var lower = lower0
    if q0 != q0 || m0 != m0 || n0 != n0 { ret q0 + m0 + n0 }
    if !finite(m0) || !finite(n0) { ret nan() }
    let m = math.round[f64](m0)
    let n = math.round[f64](n0)
    if m <= 0.0f64 || n <= 0.0f64 { ret nan() }
    var q = math.floor[f64](q0 + 1e-7f64)
    if q < 0.0f64 { ret dist.dt0(lower, lg) }
    if q >= m * n { ret dist.dt1(lower, lg) }
    var mi = i64(m)
    var ni = i64(n)
    if mi > ni {
        let t = mi
        mi = ni
        ni = t
    }
    let (w, e) = wilcox_table(a, mi, ni, mi * ni / 2i64)
    if e != ok { ret nan() }
    let c = special.choose(m + n, n)
    var p = 0.0f64
    if q <= m * n / 2.0f64 {
        var i = 0i64
        while f64(i) <= q {
            p += cwilcox(w, i, mi, ni) / c
            i += 1i64
        }
    } else {
        q = m * n - q
        var i = 0i64
        while f64(i) < q {
            p += cwilcox(w, i, mi, ni) / c
            i += 1i64
        }
        lower = !lower
    }
    ret dt_val(p, lower, lg)
}

fn qwilcox(a: *mem.Arena, x0: f64, m0: f64, n0: f64, lower: bool, lg: bool) -> f64 {
    var x = x0
    if x != x || m0 != m0 || n0 != n0 { ret x + m0 + n0 }
    if !finite(x) || !finite(m0) || !finite(n0) { ret nan() }
    if dist.bad_p(x, lg) { ret nan() }
    let m = math.round[f64](m0)
    let n = math.round[f64](n0)
    if m <= 0.0f64 || n <= 0.0f64 { ret nan() }
    if x == dist.dt0(lower, lg) { ret 0.0f64 }
    if x == dist.dt1(lower, lg) { ret m * n }
    if lg || !lower { x = dist.dt_qiv(x, lower, lg) }
    var mi = i64(m)
    var ni = i64(n)
    if mi > ni {
        let t = mi
        mi = ni
        ni = t
    }
    let (w, e) = wilcox_table(a, mi, ni, mi * ni / 2i64)
    if e != ok { ret nan() }
    let c = special.choose(m + n, n)
    var p = 0.0f64
    var q = 0i64
    if x <= 0.5f64 {
        x = x - 10.0f64 * 2.220446049250313e-16f64
        var go = true
        while go {
            p += cwilcox(w, q, mi, ni) / c
            if p >= x { go = false } else { q += 1i64 }
        }
    } else {
        x = 1.0f64 - x + 10.0f64 * 2.220446049250313e-16f64
        var go = true
        while go {
            p += cwilcox(w, q, mi, ni) / c
            if p > x {
                q = i64(m * n) - q
                go = false
            } else {
                q += 1i64
            }
        }
    }
    ret f64(q)
}

// --- studentized range

fn wprob(w: f64, rr: f64, cc: f64) -> f64 {
    let c1 = -30.0f64
    let c2 = -50.0f64
    let c3 = 60.0f64
    let bb = 8.0f64
    let wlar = 3.0f64
    var xleg: [6]f64 = zero
    xleg[0usize] = 0.981560634246719250690549090149f64
    xleg[1usize] = 0.904117256370474856678465866119f64
    xleg[2usize] = 0.769902674194304687036893833213f64
    xleg[3usize] = 0.587317954286617447296702418941f64
    xleg[4usize] = 0.367831498998180193752691536644f64
    xleg[5usize] = 0.125233408511468915472441369464f64
    var aleg: [6]f64 = zero
    aleg[0usize] = 0.047175336386511827194615961485f64
    aleg[1usize] = 0.106939325995318430960254718194f64
    aleg[2usize] = 0.160078328543346226334652529543f64
    aleg[3usize] = 0.203167426723065921749064455810f64
    aleg[4usize] = 0.233492536538354808760849898925f64
    aleg[5usize] = 0.249147045813402785000562436043f64
    let qsqz = w * 0.5f64
    if qsqz >= bb { ret 1.0f64 }
    var pr_w = 2.0f64 * dist.pnorm(qsqz, 0.0f64, 1.0f64, true, false) - 1.0f64
    if pr_w >= math.exp[f64](c2 / cc) { pr_w = math.pow[f64](pr_w, cc) } else { pr_w = 0.0f64 }
    var wincr = 3.0f64
    if w > wlar { wincr = 2.0f64 }
    var blb = qsqz
    let binc = (bb - qsqz) / wincr
    var bub = blb + binc
    var einsum = 0.0f64
    let cc1 = cc - 1.0f64
    var wi = 1.0f64
    while wi <= wincr {
        var elsum = 0.0f64
        let a = 0.5f64 * (bub + blb)
        let b = 0.5f64 * (bub - blb)
        var jj = 1i64
        var stop = false
        while jj <= 12i64 && !stop {
            var j = 0usize
            var xx = 0.0f64
            if 6i64 < jj {
                j = usize(12i64 - jj)
                xx = xleg[j]
            } else {
                j = usize(jj - 1i64)
                xx = 0.0f64 - xleg[j]
            }
            let c = b * xx
            let ac = a + c
            let qexpo = ac * ac
            if qexpo > c3 {
                stop = true
            } else {
                let pplus = 2.0f64 * dist.pnorm(ac, 0.0f64, 1.0f64, true, false)
                let pminus = 2.0f64 * dist.pnorm(ac, w, 1.0f64, true, false)
                var rinsum = pplus * 0.5f64 - pminus * 0.5f64
                if rinsum >= math.exp[f64](c1 / cc1) {
                    rinsum = (aleg[j] * math.exp[f64](0.0f64 - 0.5f64 * qexpo)) * math.pow[f64](rinsum, cc1)
                    elsum += rinsum
                }
            }
            jj += 1i64
        }
        elsum = elsum * (((2.0f64 * b) * cc) * 0.398942280401432677939946059934f64)
        einsum += elsum
        blb = bub
        bub += binc
        wi += 1.0f64
    }
    pr_w += einsum
    if pr_w <= math.exp[f64](c1 / rr) { ret 0.0f64 }
    pr_w = math.pow[f64](pr_w, rr)
    if pr_w >= 1.0f64 { ret 1.0f64 }
    ret pr_w
}

fn ptukey(q: f64, rr: f64, cc: f64, dof: f64, lower: bool, lg: bool) -> f64 {
    let eps1 = -30.0f64
    let eps2 = 1.0e-14f64
    var xlegq: [8]f64 = zero
    xlegq[0usize] = 0.989400934991649932596154173450f64
    xlegq[1usize] = 0.944575023073232576077988415535f64
    xlegq[2usize] = 0.865631202387831743880467897712f64
    xlegq[3usize] = 0.755404408355003033895101194847f64
    xlegq[4usize] = 0.617876244402643748446671764049f64
    xlegq[5usize] = 0.458016777657227386342419442984f64
    xlegq[6usize] = 0.281603550779258913230460501460f64
    xlegq[7usize] = 0.0950125098376374401853193354250f64
    var alegq: [8]f64 = zero
    alegq[0usize] = 0.0271524594117540948517805724560f64
    alegq[1usize] = 0.0622535239386478928628438369944f64
    alegq[2usize] = 0.0951585116824927848099251076022f64
    alegq[3usize] = 0.124628971255533872052476282192f64
    alegq[4usize] = 0.149595988816576732081501730547f64
    alegq[5usize] = 0.169156519395002538189312079030f64
    alegq[6usize] = 0.182603415044923588866763667969f64
    alegq[7usize] = 0.189450610455068496285396723208f64
    if q != q || rr != rr || cc != cc || dof != dof { ret nan() }
    if q <= 0.0f64 { ret dist.dt0(lower, lg) }
    if dof < 2.0f64 || rr < 1.0f64 || cc < 2.0f64 { ret nan() }
    if !finite(q) { ret dist.dt1(lower, lg) }
    if dof > 25000.0f64 { ret dt_val(wprob(q, rr, cc), lower, lg) }
    let f2 = dof * 0.5f64
    var f2lf = ((f2 * math.log[f64](dof)) - (dof * 0.693147180559945309417232121458f64)) - nm.lgammafn(f2)
    let f21 = f2 - 1.0f64
    let ff4 = dof * 0.25f64
    var ulen = 0.125f64
    if dof <= 100.0f64 { ulen = 1.0f64 } else if dof <= 800.0f64 { ulen = 0.5f64 } else if dof <= 5000.0f64 { ulen = 0.25f64 }
    f2lf += math.log[f64](ulen)
    var ans = 0.0f64
    var otsum = 0.0f64
    var i = 1i64
    var done = false
    while i <= 50i64 && !done {
        otsum = 0.0f64
        let twa1 = f64(2i64 * i - 1i64) * ulen
        var jj = 1i64
        while jj <= 16i64 {
            var j = 0usize
            var t1 = 0.0f64
            if 8i64 < jj {
                j = usize(jj - 9i64)
                t1 = (f2lf + (f21 * math.log[f64](twa1 + (xlegq[j] * ulen)))) - (((xlegq[j] * ulen) + twa1) * ff4)
            } else {
                j = usize(jj - 1i64)
                t1 = (f2lf + (f21 * math.log[f64](twa1 - (xlegq[j] * ulen)))) + (((xlegq[j] * ulen) - twa1) * ff4)
            }
            if t1 >= eps1 {
                var qsqz = 0.0f64
                if 8i64 < jj {
                    qsqz = q * math.sqrt[f64](((xlegq[j] * ulen) + twa1) * 0.5f64)
                } else {
                    qsqz = q * math.sqrt[f64](((0.0f64 - (xlegq[j] * ulen)) + twa1) * 0.5f64)
                }
                let wprb = wprob(qsqz, rr, cc)
                otsum += (wprb * alegq[j]) * math.exp[f64](t1)
            }
            jj += 1i64
        }
        if f64(i) * ulen >= 1.0f64 && otsum <= eps2 {
            done = true
        } else {
            ans += otsum
            i += 1i64
        }
    }
    if ans > 1.0f64 { ans = 1.0f64 }
    ret dt_val(ans, lower, lg)
}

fn qinv(p: f64, c: f64, v: f64) -> f64 {
    let p0 = 0.322232421088f64
    let q0 = 0.993484626060e-01f64
    let p1 = -1.0f64
    let q1 = 0.588581570495f64
    let p2 = -0.342242088547f64
    let q2 = 0.531103462366f64
    let p3 = -0.204231210125f64
    let q3 = 0.103537752850f64
    let p4 = -0.453642210148e-04f64
    let q4 = 0.38560700634e-02f64
    let c1 = 0.8832f64
    let c2 = 0.2368f64
    let c3 = 1.214f64
    let c4 = 1.208f64
    let c5 = 1.4142f64
    let ps = 0.5f64 - 0.5f64 * p
    let yi = math.sqrt[f64](math.log[f64](1.0f64 / (ps * ps)))
    var t = yi + ((((yi * p4 + p3) * yi + p2) * yi + p1) * yi + p0) / ((((yi * q4 + q3) * yi + q2) * yi + q1) * yi + q0)
    if v < 120.0f64 { t += (t * t * t + t) / v / 4.0f64 }
    var q = c1 - c2 * t
    if v < 120.0f64 { q += 0.0f64 - c3 / v + c4 * t / v }
    ret t * (q * math.log[f64](c - 1.0f64) + c5)
}

fn qtukey(p0: f64, rr: f64, cc: f64, dof: f64, lower: bool, lg: bool) -> f64 {
    let eps = 0.0001f64
    if p0 != p0 || rr != rr || cc != cc || dof != dof { ret p0 + rr + cc + dof }
    if dof < 2.0f64 || rr < 1.0f64 || cc < 2.0f64 { ret nan() }
    if dist.bad_p(p0, lg) { ret nan() }
    if p0 == dist.dt0(lower, lg) { ret 0.0f64 }
    if p0 == dist.dt1(lower, lg) { ret inf() }
    let p = dist.dt_qiv(p0, lower, lg)
    var x0 = qinv(p, cc, dof)
    var valx0 = ptukey(x0, rr, cc, dof, true, false) - p
    var x1 = 0.0f64
    if valx0 > 0.0f64 { x1 = nm.max2(0.0f64, x0 - 1.0f64) } else { x1 = x0 + 1.0f64 }
    var valx1 = ptukey(x1, rr, cc, dof, true, false) - p
    var ans = 0.0f64
    var iter = 1i64
    while iter < 50i64 {
        ans = x1 - ((valx1 * (x1 - x0)) / (valx1 - valx0))
        valx0 = valx1
        x0 = x1
        if ans < 0.0f64 {
            ans = 0.0f64
            valx1 = 0.0f64 - p
        }
        valx1 = ptukey(ans, rr, cc, dof, true, false) - p
        x1 = ans
        if nm.abs_of(x1 - x0) < eps { ret ans }
        iter += 1i64
    }
    ret ans
}

// --- qbeta (AS 109 start, Newton steps on x or on log x, tail swaps)

fn dt_civ(alpha: f64, lower: bool, lg: bool) -> f64 {
    if lg {
        if lower { ret 0.0f64 - dist.expm1(alpha) }
        ret math.exp[f64](alpha)
    }
    if lower { ret 0.5f64 - alpha + 0.5f64 }
    ret alpha
}

fn qbeta_raw(alpha: f64, p: f64, q: f64, lower: bool, lg: bool, log_q_cut: f64, n_n: i64) -> (f64, f64) {
    let dbl_very_min = 2.2250738585072014e-308f64 / 4.0f64
    let dbl_log_v_min = 0.693147180559945309417232121458f64 * -1023.0f64
    let dbl_1_eps = 0.99999999999999988898f64
    let fpu = 3e-308f64
    let acu_min = 1e-300f64
    let p_lo = fpu
    let p_hi = 1.0f64 - 2.22e-16f64
    let const1 = 2.30753f64
    let const2 = 0.27061f64
    let const3 = 0.99229f64
    let const4 = 0.04481f64
    var use_log_x = false
    var add_n_step = true
    var warned = false
    if alpha == dist.dt0(lower, lg) { ret (0.0f64, 1.0f64) }
    if alpha == dist.dt1(lower, lg) { ret (1.0f64, 0.0f64) }
    if (lg && alpha > 0.0f64) || (!lg && (alpha < 0.0f64 || alpha > 1.0f64)) { ret (nan(), nan()) }
    if p == 0.0f64 || q == 0.0f64 || !finite(p) || !finite(q) {
        var half = 0.5f64
        if lg { half = -0.693147180559945309417232121458f64 }
        if p == 0.0f64 && q == 0.0f64 {
            if alpha < half { ret (0.0f64, 1.0f64) }
            if alpha > half { ret (1.0f64, 0.0f64) }
            ret (0.5f64, 0.5f64)
        } else if p == 0.0f64 || p / q == 0.0f64 {
            ret (0.0f64, 1.0f64)
        } else if q == 0.0f64 || q / p == 0.0f64 {
            ret (1.0f64, 0.0f64)
        }
        ret (0.5f64, 0.5f64)
    }
    let p_ = dist.dt_qiv(alpha, lower, lg)
    let logbeta = lbeta(p, q)
    var swap_tail = p_ > 0.5f64
    var n_maybe_swaps = 0i64
    var a = 0.0f64
    var la = 0.0f64
    var pp = 0.0f64
    var qq = 0.0f64
    var acu = 0.0f64
    var u0 = 0.0f64
    var rp = 0.0f64
    var u = 0.0f64
    var xinbta = 0.0f64
    var tx = 0.0f64
    var u_n = 1.0f64
    var y = -1.0f64
    var w = 0.0f64
    var r = 0.0f64
    var t = 0.0f64
    var s = 0.0f64
    var h = 0.0f64
    var g = 0.0f64
    var state = 0i64
    while true {
        if state == 0i64 {
            if swap_tail {
                a = dt_civ(alpha, lower, lg)
                la = dist.dt_clog(alpha, lower, lg)
                pp = q
                qq = p
            } else {
                a = p_
                la = nm.dt_log(alpha, lower, lg)
                pp = p
                qq = q
            }
            n_maybe_swaps += 1i64
            acu = nm.max2(acu_min, math.pow[f64](10.0f64, -13.0f64 - 2.5f64 / (pp * pp) - 0.5f64 / (a * a)))
            u0 = (la + math.log[f64](pp) + logbeta) / pp
            rp = pp * (1.0f64 - qq) / (pp + 1.0f64)
            t = 0.2f64
            let log_eps_c = 0.693147180559945309417232121458f64 * (1.0f64 - 53.0f64)
            let u0_maybe = 0.693147180559945309417232121458f64 * -1021.0f64 < u0 && u0 < -0.01f64
            u_n = 1.0f64
            var to_newton = false
            if u0_maybe && u0 < (t * log_eps_c - math.log[f64](nm.abs_of(pp * (1.0f64 - qq) * (2.0f64 - qq) / (2.0f64 * (pp + 2.0f64))))) / 2.0f64 {
                rp = rp * math.exp[f64](u0)
                if rp > -1.0f64 { u = u0 - dist.log1p(rp) / pp } else { u = u0 }
                xinbta = math.exp[f64](u)
                tx = xinbta
                use_log_x = true
                to_newton = true
            }
            var to_return = false
            if !to_newton {
                r = math.sqrt[f64](0.0f64 - 2.0f64 * la)
                y = r - (const1 + const2 * r) / (1.0f64 + (const3 + const4 * r) * r)
                if pp > 1.0f64 && qq > 1.0f64 {
                    r = (y * y - 3.0f64) / 6.0f64
                    s = 1.0f64 / (pp + pp - 1.0f64)
                    t = 1.0f64 / (qq + qq - 1.0f64)
                    h = 2.0f64 / (s + t)
                    w = y * math.sqrt[f64](h + r) / h - (t - s) * (r + 5.0f64 / 6.0f64 - 2.0f64 / (3.0f64 * h))
                    if w > 300.0f64 {
                        t = w + w + math.log[f64](qq) - math.log[f64](pp)
                        if t <= 18.0f64 { u = 0.0f64 - dist.log1p(math.exp[f64](t)) } else { u = 0.0f64 - t - math.exp[f64](0.0f64 - t) }
                        xinbta = math.exp[f64](u)
                    } else {
                        xinbta = pp / (pp + qq * math.exp[f64](w + w))
                        u = 0.0f64 - dist.log1p(qq / pp * math.exp[f64](w + w))
                    }
                } else {
                    r = qq + qq
                    t = 1.0f64 / (3.0f64 * math.sqrt[f64](qq))
                    let cube = 1.0f64 + t * (0.0f64 - t + y)
                    t = r * (cube * cube * cube)
                    s = 4.0f64 * pp + r - 2.0f64
                    if t == 0.0f64 || (t < 0.0f64 && s >= t) {
                        var l1ma = nm.dt_log(alpha, lower, lg)
                        if swap_tail { l1ma = nm.dt_log(alpha, lower, lg) } else { l1ma = dist.dt_clog(alpha, lower, lg) }
                        let xx = (l1ma + math.log[f64](qq) + logbeta) / qq
                        if xx <= 0.0f64 {
                            xinbta = 0.0f64 - dist.expm1(xx)
                            u = dist.log1_exp(xx)
                        } else {
                            let r_ = rp * math.exp[f64](u0)
                            if r_ > -1.0f64 { u = u0 - dist.log1p(r_) / pp } else { u = u0 }
                            xinbta = math.exp[f64](u)
                        }
                    } else {
                        t = s / t
                        if t <= 1.0f64 {
                            u = u0
                            xinbta = math.exp[f64](u)
                        } else {
                            xinbta = 1.0f64 - 2.0f64 / (t + 1.0f64)
                            u = dist.log1p(0.0f64 - 2.0f64 / (t + 1.0f64))
                        }
                    }
                }
                if (swap_tail && u >= 0.0f64 - math.exp[f64](log_q_cut)) || (!swap_tail && u >= 0.0f64 - math.exp[f64](4.0f64 * log_q_cut) && pp / qq < 1000.0f64) {
                    swap_tail = !swap_tail
                    if swap_tail {
                        a = dt_civ(alpha, lower, lg)
                        la = dist.dt_clog(alpha, lower, lg)
                        pp = q
                        qq = p
                    } else {
                        a = p_
                        la = nm.dt_log(alpha, lower, lg)
                        pp = p
                        qq = q
                    }
                    u = dist.log1_exp(u)
                    xinbta = math.exp[f64](u)
                }
                if !use_log_x { use_log_x = u < log_q_cut }
                let bad_u = !finite(u)
                let bad_init = bad_u || xinbta > p_hi
                tx = xinbta
                if bad_u || u < log_q_cut {
                    w = pbeta_raw(dbl_very_min, pp, qq, true, lg)
                    var lim = a
                    if lg { lim = la }
                    if w > lim {
                        if lg || nm.abs_of(w - a) < nm.abs_of(0.0f64 - a) {
                            tx = dbl_very_min
                            u_n = dbl_log_v_min
                        } else {
                            tx = 0.0f64
                            u_n = 0.0f64 - inf()
                        }
                        use_log_x = lg
                        add_n_step = false
                        to_return = true
                    } else if u < dbl_log_v_min {
                        u = dbl_log_v_min
                        xinbta = dbl_very_min
                    }
                }
                if !to_return && bad_init && !(use_log_x && tx > 0.0f64) {
                    if u == 0.0f64 - inf() {
                        u = 0.693147180559945309417232121458f64 * -1021.0f64
                        xinbta = 2.2250738585072014e-308f64
                    } else {
                        if xinbta > 1.1f64 {
                            xinbta = 0.5f64
                        } else if xinbta < p_lo {
                            xinbta = math.exp[f64](u)
                        } else {
                            xinbta = p_hi
                        }
                        if bad_u { u = math.log[f64](xinbta) }
                    }
                }
            }
            if to_return { state = 3i64 } else { state = 1i64 }
        }
        if state == 1i64 {
            r = 1.0f64 - pp
            t = 1.0f64 - qq
            var wprev = 0.0f64
            var prev = 1.0f64
            var adj = 1.0f64
            var converged = false
            var again = false
            var give_up = false
            var i_pb = 0i64
            if use_log_x {
                while i_pb < 1000i64 && !converged && !again && !give_up {
                    y = pbeta_raw(xinbta, pp, qq, true, true)
                    if y == 0.0f64 - inf() {
                        w = 0.0f64
                    } else {
                        w = (y - la) * math.exp[f64](y - u + logbeta + r * u + t * dist.log1_exp(u))
                    }
                    if !finite(w) {
                        if n_maybe_swaps <= 1i64 { again = true } else { give_up = true }
                    } else {
                        if i_pb >= n_n && w * wprev <= 0.0f64 { prev = nm.max2(nm.abs_of(adj), fpu) }
                        g = 1.0f64
                        var i_inn = 0i64
                        var brk = false
                        while i_inn < 1000i64 && !converged && !brk {
                            adj = g * w
                            if nm.abs_of(adj) < prev {
                                u_n = u - adj
                                if u_n <= 0.0f64 {
                                    if prev <= acu || nm.abs_of(w) <= acu {
                                        converged = true
                                    } else {
                                        brk = true
                                    }
                                }
                            }
                            if !converged && !brk { g = g / 3.0f64 }
                            i_inn += 1i64
                        }
                        if !converged {
                            var dd = nm.abs_of(adj)
                            if nm.abs_of(u_n - u) < dd { dd = nm.abs_of(u_n - u) }
                            if dd <= 4e-16f64 * nm.abs_of(u_n + u) {
                                converged = true
                            } else {
                                u = u_n
                                xinbta = math.exp[f64](u)
                                wprev = w
                            }
                        }
                    }
                    i_pb += 1i64
                }
            } else {
                var stop_zero = false
                while i_pb < 1000i64 && !converged && !again && !give_up && !stop_zero {
                    y = pbeta_raw(xinbta, pp, qq, true, lg)
                    if lg {
                        w = (y - la) * math.exp[f64](y + logbeta + r * math.log[f64](xinbta) + t * dist.log1p(0.0f64 - xinbta))
                    } else {
                        w = (y - a) * math.exp[f64](logbeta + r * math.log[f64](xinbta) + t * dist.log1p(0.0f64 - xinbta))
                    }
                    if !finite(w) {
                        if n_maybe_swaps <= 2i64 {
                            if !lg && n_maybe_swaps == 2i64 { use_log_x = true }
                            if !lg || n_maybe_swaps <= 1i64 { again = true }
                        }
                        if !again { give_up = true }
                    } else {
                        if i_pb >= n_n && w * wprev <= 0.0f64 { prev = nm.max2(nm.abs_of(adj), fpu) }
                        g = 1.0f64
                        var i_inn = 0i64
                        var brk = false
                        while i_inn < 1000i64 && !converged && !brk {
                            adj = g * w
                            if i_pb < n_n || nm.abs_of(adj) < prev {
                                tx = xinbta - adj
                                if 0.0f64 <= tx && tx <= 1.0f64 {
                                    if prev <= acu || nm.abs_of(w) <= acu {
                                        converged = true
                                    } else if tx != 0.0f64 && tx != 1.0f64 {
                                        brk = true
                                    }
                                }
                            }
                            if !converged && !brk { g = g / 3.0f64 }
                            i_inn += 1i64
                        }
                        if !converged {
                            if nm.abs_of(tx - xinbta) <= 4e-16f64 * (tx + xinbta) {
                                converged = true
                            } else {
                                xinbta = tx
                                if tx == 0.0f64 {
                                    stop_zero = true
                                } else {
                                    wprev = w
                                }
                            }
                        }
                    }
                    i_pb += 1i64
                }
            }
            if again {
                state = 0i64
            } else if give_up {
                ret (nan(), nan())
            } else {
                if !converged { warned = true }
                state = 2i64
            }
        }
        if state == 2i64 {
            let log_ = lg || use_log_x
            if (log_ && y == 0.0f64 - inf()) || (!log_ && y == 0.0f64) {
                w = pbeta_raw(dbl_very_min, pp, qq, true, log_)
                if log_ || nm.abs_of(w - a) <= nm.abs_of(y - a) {
                    tx = dbl_very_min
                    u_n = dbl_log_v_min
                }
                add_n_step = false
            }
            state = 3i64
        }
        if state == 3i64 {
            if use_log_x {
                if add_n_step {
                    if u_n != 1.0f64 { xinbta = math.exp[f64](u_n) }
                    y = pbeta_raw(xinbta, pp, qq, true, lg)
                    if lg {
                        w = (y - la) * math.exp[f64](y + logbeta + r * math.log[f64](xinbta) + t * dist.log1p(0.0f64 - xinbta))
                    } else {
                        w = (y - a) * math.exp[f64](logbeta + r * math.log[f64](xinbta) + t * dist.log1p(0.0f64 - xinbta))
                    }
                    if finite(w) { tx = xinbta - w } else { tx = xinbta }
                } else {
                    if swap_tail { ret (0.0f64 - dist.expm1(u_n), math.exp[f64](u_n)) }
                    ret (math.exp[f64](u_n), 0.0f64 - dist.expm1(u_n))
                }
            }
            if swap_tail { ret (1.0f64 - tx, tx) }
            ret (tx, 1.0f64 - tx)
        }
    }
    ret (nan(), nan())
}

fn qbeta(alpha: f64, p: f64, q: f64, lower: bool, lg: bool) -> f64 {
    if p != p || q != q || alpha != alpha { ret p + q + alpha }
    if p < 0.0f64 || q < 0.0f64 { ret nan() }
    let (q0, q1) = qbeta_raw(alpha, p, q, lower, lg, -5.0f64, 4i64)
    ret q0
}

fn qf(p0: f64, df1: f64, df2: f64, lower: bool, lg: bool) -> f64 {
    var p = p0
    if p != p || df1 != df1 || df2 != df2 { ret p + df1 + df2 }
    if df1 <= 0.0f64 || df2 <= 0.0f64 { ret nan() }
    if lg {
        if p > 0.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret inf() }
            ret 0.0f64
        }
        if p == 0.0f64 - inf() {
            if lower { ret 0.0f64 }
            ret inf()
        }
    } else {
        if p < 0.0f64 || p > 1.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret 0.0f64 }
            ret inf()
        }
        if p == 1.0f64 {
            if lower { ret inf() }
            ret 0.0f64
        }
    }
    if df1 <= df2 && df2 > 4e5f64 {
        if !finite(df1) { ret 1.0f64 }
        ret nm.qchisq(p, df1, lower, lg) / df1
    } else if df1 > 4e5f64 {
        ret df2 / nm.qchisq(p, df2, !lower, lg)
    }
    p = (1.0f64 / qbeta(p, df2 / 2.0f64, df1 / 2.0f64, !lower, lg) - 1.0f64) * (df2 / df1)
    if p != p { ret nan() }
    ret p
}

// --- qt

fn tanpi(x0: f64) -> f64 {
    var x = x0 - math.trunc[f64](x0)
    if x <= -0.5f64 { x += 1.0f64 } else if x > 0.5f64 { x -= 1.0f64 }
    if x == 0.0f64 { ret 0.0f64 }
    if x == 0.5f64 { ret nan() }
    if x == 0.25f64 { ret 1.0f64 }
    if x == -0.25f64 { ret -1.0f64 }
    ret math.tan[f64](3.141592653589793238462643383280f64 * x)
}

fn qt(p0: f64, ndf: f64, lower: bool, lg: bool) -> f64 {
    let eps = 1e-12f64
    var p = p0
    if p != p || ndf != ndf { ret p + ndf }
    if lg {
        if p > 0.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret inf() }
            ret 0.0f64 - inf()
        }
        if p == 0.0f64 - inf() {
            if lower { ret 0.0f64 - inf() }
            ret inf()
        }
    } else {
        if p < 0.0f64 || p > 1.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret 0.0f64 - inf() }
            ret inf()
        }
        if p == 1.0f64 {
            if lower { ret inf() }
            ret 0.0f64 - inf()
        }
    }
    if ndf <= 0.0f64 { ret nan() }
    if ndf < 1.0f64 {
        let accu = 1e-13f64
        let eps2 = 1e-11f64
        p = dist.dt_qiv(p, lower, lg)
        if p > 1.0f64 - 2.220446049250313e-16f64 { ret inf() }
        var pp = nm.max2(0.0f64, 0.0f64)
        pp = 1.0f64 - 2.220446049250313e-16f64
        if p * (1.0f64 + eps2) < pp { pp = p * (1.0f64 + eps2) }
        var ux = 1.0f64
        while ux < 1.7976931348623157e308f64 && pt(ux, ndf, true, false) < pp { ux = ux * 2.0f64 }
        pp = p * (1.0f64 - eps2)
        var lx = -1.0f64
        while lx > -1.7976931348623157e308f64 && pt(lx, ndf, true, false) > pp { lx = lx * 2.0f64 }
        var iter = 0i64
        var nx = 0.0f64
        var go = true
        while go {
            nx = 0.5f64 * (lx + ux)
            if pt(nx, ndf, true, false) > p { ux = nx } else { lx = nx }
            iter += 1i64
            go = (ux - lx) / nm.abs_of(nx) > accu && iter < 1000i64
        }
        ret 0.5f64 * (lx + ux)
    }
    if ndf > 1e20f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, lower, lg) }
    var pq = 0.0f64
    if lg { pq = math.exp[f64](p) } else { pq = p }
    let neg = (!lower || pq < 0.5f64) && (lower || pq > 0.5f64)
    let is_neg_lower = lower == neg
    if neg {
        if lg {
            if lower { pq = 2.0f64 * pq } else { pq = 2.0f64 * (0.0f64 - dist.expm1(p)) }
            if !lower { pq = 2.0f64 * (0.0f64 - dist.expm1(p)) } else { pq = 2.0f64 * math.exp[f64](p) }
        } else {
            if lower { pq = 2.0f64 * p } else { pq = 2.0f64 * (0.5f64 - p + 0.5f64) }
        }
    } else {
        if lg {
            if lower { pq = 2.0f64 * (0.0f64 - dist.expm1(p)) } else { pq = 2.0f64 * math.exp[f64](p) }
        } else {
            if lower { pq = 2.0f64 * (0.5f64 - p + 0.5f64) } else { pq = 2.0f64 * p }
        }
    }
    var q = 0.0f64
    if nm.abs_of(ndf - 2.0f64) < eps {
        if pq > 2.2250738585072014e-308f64 {
            if 3.0f64 * pq < 2.220446049250313e-16f64 {
                q = 1.0f64 / math.sqrt[f64](pq)
            } else if pq > 0.9f64 {
                q = (1.0f64 - pq) * math.sqrt[f64](2.0f64 / (pq * (2.0f64 - pq)))
            } else {
                q = math.sqrt[f64](2.0f64 / (pq * (2.0f64 - pq)) - 2.0f64)
            }
        } else {
            if lg {
                if is_neg_lower { q = math.exp[f64](0.0f64 - p / 2.0f64) / 1.41421356237309504880168872421f64 } else { q = 1.0f64 / math.sqrt[f64](0.0f64 - dist.expm1(p)) }
            } else {
                q = inf()
            }
        }
    } else if ndf < 1.0f64 + eps {
        if pq == 1.0f64 {
            q = 0.0f64
        } else if pq > 0.0f64 {
            q = 1.0f64 / tanpi(pq / 2.0f64)
        } else {
            if lg {
                if is_neg_lower { q = 0.318309886183790671537767526745f64 * math.exp[f64](0.0f64 - p) } else { q = -1.0f64 / (3.141592653589793238462643383280f64 * dist.expm1(p)) }
            } else {
                q = inf()
            }
        }
    } else {
        var x = 0.0f64
        var y = 0.0f64
        var log_p2 = 0.0f64
        let a = 1.0f64 / (ndf - 0.5f64)
        let b = 48.0f64 / (a * a)
        var c = ((20700.0f64 * a / b - 98.0f64) * a - 16.0f64) * a + 96.36f64
        let d = ((94.5f64 / (b + c) - 3.0f64) / b + 1.0f64) * math.sqrt[f64](a * 1.570796326794896619231321691640f64) * ndf
        let p_ok1 = pq > 2.2250738585072014e-308f64 || !lg
        var p_ok = p_ok1
        if p_ok1 {
            y = math.pow[f64](d * pq, 2.0f64 / ndf)
            p_ok = y >= 2.220446049250313e-16f64
        }
        if !p_ok {
            if is_neg_lower { log_p2 = dist.dlog(p, lg) } else { log_p2 = dist.dlexp(p, lg) }
            x = (math.log[f64](d) + 0.693147180559945309417232121458f64 + log_p2) / ndf
            y = math.exp[f64](2.0f64 * x)
        }
        if (ndf < 2.1f64 && pq > 0.5f64) || y > 0.05f64 + a {
            if p_ok {
                x = dist.qnorm(0.5f64 * pq, 0.0f64, 1.0f64, true, false)
            } else {
                x = dist.qnorm(log_p2, 0.0f64, 1.0f64, lower, true)
            }
            y = x * x
            if ndf < 5.0f64 { c += 0.3f64 * (ndf - 4.5f64) * (x + 0.6f64) }
            c = (((0.05f64 * d * x - 5.0f64) * x - 7.0f64) * x - 2.0f64) * x + b + c
            y = (((((0.4f64 * y + 6.3f64) * y + 36.0f64) * y + 94.5f64) / c - y - 3.0f64) / b + 1.0f64) * x
            y = dist.expm1(a * y * y)
            q = math.sqrt[f64](ndf * y)
        } else if !p_ok && x < -0.693147180559945309417232121458f64 * 53.0f64 {
            q = math.sqrt[f64](ndf) * math.exp[f64](0.0f64 - x)
        } else {
            y = ((1.0f64 / (((ndf + 6.0f64) / (ndf * y) - 0.089f64 * d - 0.822f64) * (ndf + 2.0f64) * 3.0f64) + 0.5f64 / (ndf + 4.0f64)) * y - 1.0f64) * (ndf + 1.0f64) / (ndf + 2.0f64) + 1.0f64 / y
            q = math.sqrt[f64](ndf * y)
        }
        if p_ok1 {
            let mm = nm.abs_of(math.sqrt[f64](1.7976931348623157e308f64 / 2.0f64) - ndf)
            var it = 0i64
            var go = true
            while go {
                it += 1i64
                if it > 10i64 {
                    go = false
                } else {
                    y = dt(q, ndf, false)
                    if !(y > 0.0f64) {
                        go = false
                    } else {
                        x = (pt(q, ndf, false, false) - pq / 2.0f64) / y
                        if !finite(x) || !(nm.abs_of(x) > 1e-14f64 * nm.abs_of(q)) {
                            go = false
                        } else {
                            var ff = 0.0f64
                            if nm.abs_of(q) < mm {
                                ff = q * (ndf + 1.0f64) / (2.0f64 * (q * q + ndf))
                            } else {
                                ff = (ndf + 1.0f64) / (2.0f64 * (q + ndf / q))
                            }
                            let del_q = x * (1.0f64 + x * ff)
                            if finite(del_q) && finite(q + del_q) {
                                q += del_q
                            } else if finite(x) && finite(q + x) {
                                q += x
                            } else {
                                go = false
                            }
                        }
                    }
                }
            }
        }
    }
    if neg { ret 0.0f64 - q }
    ret q
}
