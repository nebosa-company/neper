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

fn qgeom(p: f64, prob: f64, lower: bool, lg: bool) -> f64 {
    if p != p || prob != prob { ret p + prob }
    if prob <= 0.0f64 || prob > 1.0f64 { ret nan() }
    if dist.bad_p(p, lg) { ret nan() }
    if prob == 1.0f64 { ret 0.0f64 }
    if p == dist.dt0(lower, lg) { ret 0.0f64 }
    if p == dist.dt1(lower, lg) { ret inf() }
    ret nm.max2(0.0f64, math.ceil[f64](dist.dt_clog(p, lower, lg) / dist.log1p(0.0f64 - prob) - 1.0f64 - 1e-12f64))
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
