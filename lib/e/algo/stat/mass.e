// R MASS, the closed-form part: `mad`, `huber` and `hubers` (Huber's location and scale M-estimates by the
// package's own iteration), `fitdistr` for the families with closed-form maximum likelihood (normal,
// exponential, Poisson, geometric, log-normal) with standard errors and log-likelihood, `boxcox_loglik`
// (the profile log-likelihood of the Box-Cox transform for an intercept-only or given-design model) and
// `bandwidth_nrd`.
//
// Not here: rlm, lqs, cov.rob, kde2d, bw.ucv, bw.bcv, bw.SJ, isoMDS, sammon, mvrnorm, stepAIC and the
// numerically optimised fitdistr families.

use e.algo.linalg.decomp as decomp
use e.algo.sort
use e.math
use e.math.dist as dist
use e.mem

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn median_of(a: *mem.Arena, v: []const f64) -> f64 {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    let n = v.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

// mad(x): 1.4826 * median(|x - median(x)|)
fn mad(a: *mem.Arena, x: []const f64) -> f64 {
    let m = median_of(a, x)
    let (d, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        d[i] = math.abs[f64](x[i] - m)
        i += 1usize
    }
    ret 1.4826f64 * median_of(a, d)
}

fn clamp(v: f64, lo: f64, hi: f64) -> f64 {
    if v < lo { ret lo }
    if v > hi { ret hi }
    ret v
}

// huber(y, k): (mu, s) with s the MAD
fn huber(a: *mem.Arena, y: []const f64, k: f64, tol: f64) -> (f64, f64) {
    let n = f64(y.len)
    var mu = median_of(a, y)
    let s = mad(a, y)
    var go = true
    var mu1 = mu
    while go {
        var sum = 0.0f64
        var i = 0usize
        while i < y.len {
            sum += clamp(y[i], mu - k * s, mu + k * s)
            i += 1usize
        }
        mu1 = sum / n
        if math.abs[f64](mu - mu1) < tol * s { go = false } else { mu = mu1 }
    }
    ret (mu, s)
}

// hubers(y, k) with both location and scale estimated (the defaults of MASS)
fn hubers(a: *mem.Arena, y: []const f64, k: f64, tol: f64) -> (f64, f64) {
    let n = f64(y.len)
    let n1 = n - 1.0f64
    var mu0 = median_of(a, y)
    var s0 = mad(a, y)
    if s0 == 0.0f64 { ret (mu0, 0.0f64) }
    let th = 2.0f64 * dist.pnorm(k, 0.0f64, 1.0f64, true, false) - 1.0f64
    let beta = th + k * k * (1.0f64 - th) - 2.0f64 * k * dist.dnorm(k, 0.0f64, 1.0f64, false)
    var it = 0usize
    var mu1 = mu0
    var s1 = s0
    while it < 30usize {
        var sum = 0.0f64
        var i = 0usize
        while i < y.len {
            sum += clamp(y[i], mu0 - k * s0, mu0 + k * s0)
            i += 1usize
        }
        mu1 = sum / n
        var ss = 0.0f64
        i = 0usize
        while i < y.len {
            let yy = clamp(y[i], mu0 - k * s0, mu0 + k * s0)
            ss += (yy - mu1) * (yy - mu1)
            i += 1usize
        }
        s1 = math.sqrt[f64](ss / n1 / beta)
        if math.abs[f64](mu0 - mu1) < tol * s0 && math.abs[f64](s0 - s1) < tol * s0 { break }
        mu0 = mu1
        s0 = s1
        it += 1usize
    }
    ret (mu0, s0)
}

// fitdistr: which 0 normal 1 exponential 2 poisson 3 geometric 4 log-normal; answers (est1, est2, se1, se2, loglik)
// (the second entries are NaN for the one-parameter families)
fn fitdistr(a: *mem.Arena, x: []const f64, which: u8) -> (f64, f64, f64, f64, f64, err) {
    let n = f64(x.len)
    let nanv = 0.0f64 / 0.0f64
    var m = 0.0f64
    var i = 0usize
    if which == 4u8 {
        let (lx, le) = mem.alloc[f64](a, x.len)
        if le != ok { ret (nanv, nanv, nanv, nanv, nanv, le) }
        i = 0usize
        var sl = 0.0f64
        while i < x.len {
            lx[i] = math.log[f64](x[i])
            sl += lx[i]
            i += 1usize
        }
        let mu = sl / n
        var ss = 0.0f64
        i = 0usize
        while i < x.len {
            ss += (lx[i] - mu) * (lx[i] - mu)
            i += 1usize
        }
        let sd = math.sqrt[f64](ss / n)
        var ll = 0.0f64
        i = 0usize
        while i < x.len {
            ll += dist.dnorm(lx[i], mu, sd, true) - lx[i]
            i += 1usize
        }
        ret (mu, sd, sd / math.sqrt[f64](n), sd / math.sqrt[f64](2.0f64 * n), ll, ok)
    }
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    m = s / n
    if which == 0u8 {
        var ss = 0.0f64
        i = 0usize
        while i < x.len {
            ss += (x[i] - m) * (x[i] - m)
            i += 1usize
        }
        let sd = math.sqrt[f64](ss / n)
        var ll = 0.0f64
        i = 0usize
        while i < x.len {
            ll += dist.dnorm(x[i], m, sd, true)
            i += 1usize
        }
        ret (m, sd, sd / math.sqrt[f64](n), sd / math.sqrt[f64](2.0f64 * n), ll, ok)
    }
    if which == 1u8 {
        let rate = 1.0f64 / m
        ret (rate, nanv, rate / math.sqrt[f64](n), nanv, n * math.log[f64](rate) - rate * s, ok)
    }
    if which == 2u8 {
        var ll = 0.0f64
        i = 0usize
        while i < x.len {
            ll += x[i] * math.log[f64](m) - m - lgam(x[i] + 1.0f64)
            i += 1usize
        }
        ret (m, nanv, math.sqrt[f64](m / n), nanv, ll, ok)
    }
    let p = 1.0f64 / (1.0f64 + m)
    var ll = 0.0f64
    i = 0usize
    while i < x.len {
        ll += math.log[f64](p) + x[i] * math.log[f64](1.0f64 - p)
        i += 1usize
    }
    ret (p, nanv, math.sqrt[f64](p * p * (1.0f64 - p) / n), nanv, ll, ok)
}

fn lgam(x: f64) -> f64 {
    var s = 0.0f64
    var k = 2.0f64
    while k < x {
        s += math.log[f64](k)
        k += 1.0f64
    }
    ret s
}

// the Box-Cox profile log-likelihood at lambda for the response y and the design x (n x p, column-major)
fn boxcox_loglik(a: *mem.Arena, y: []const f64, x: []const f64, p: usize, lam: f64) -> (f64, err) {
    let n = y.len
    var gm = 0.0f64
    var i = 0usize
    while i < n {
        gm += math.log[f64](y[i])
        i += 1usize
    }
    gm = math.exp[f64](gm / f64(n))
    let (yt, ye) = mem.alloc[f64](a, n)
    if ye != ok { ret (0.0f64, ye) }
    i = 0usize
    while i < n {
        let yy = y[i] / gm
        let ly = math.log[f64](yy)
        if math.abs[f64](lam) > 0.02f64 {
            yt[i] = (math.pow[f64](yy, lam) - 1.0f64) / lam
        } else {
            yt[i] = ly * (1.0f64 + (lam * ly) / 2.0f64 * (1.0f64 + (lam * ly) / 3.0f64 * (1.0f64 + (lam * ly) / 4.0f64)))
        }
        i += 1usize
    }
    let (fit, fe) = decomp.lm_fit(a, x, n, p, yt, 1.0e-7f64)
    if fe != ok { ret (0.0f64, fe) }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        rss += fit.residuals[i] * fit.residuals[i]
        i += 1usize
    }
    ret (0.0f64 - f64(n) / 2.0f64 * math.log[f64](rss), ok)
}

fn bandwidth_nrd(a: *mem.Arena, x: []const f64) -> f64 {
    let n = f64(x.len)
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    var m = 0.0f64
    while i < x.len {
        s[i] = x[i]
        m += x[i]
        i += 1usize
    }
    m = m / n
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        ss += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / (n - 1.0f64))
    let q1 = quant7(s, 0.25f64)
    let q3 = quant7(s, 0.75f64)
    let h = (q3 - q1) / 1.34f64
    var mn = sd
    if h < mn { mn = h }
    ret 4.0f64 * 1.06f64 * mn * math.pow[f64](n, 0.0f64 - 0.2f64)
}

fn quant7(s: []const f64, p: f64) -> f64 {
    let index = 1.0f64 + (f64(s.len) - 1.0f64) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    let q = s[usize(lo) - 1usize]
    let xh = s[usize(hi) - 1usize]
    if index > lo && xh != q { ret (1.0f64 - (index - lo)) * q + (index - lo) * xh }
    ret q
}
