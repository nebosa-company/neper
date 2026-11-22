// R actuar loss distributions: the transformed beta family (`tb_*`: density, distribution, quantile, raw moment and limited expected
// value of the transformed beta, with Burr, inverse Burr, Pareto, inverse Pareto, loglogistic, paralogistic, inverse paralogistic and
// generalised Pareto as parameter maps), the transformed gamma family (`tg_*`, with gamma, Weibull and exponential as maps) and its
// inverse (`itg_*`: inverse gamma, inverse Weibull and inverse exponential), and the single-parameter Pareto (`p1_*`). Moments and
// limited expected values are given for orders inside the range where they are finite.
//
// Not here: the other distributions of the package, the random generators, aggregateDist, ruin, cm and the grouped-data tools.

use e.math
use e.math.nmath as nm
use e.math.quadpack as qp
use e.math.dist as dsa
use e.math.nmath_beta as nb
use e.algo.linalg.mexp as mexp
use e.algo.rand.r as rr
use e.algo.rand.rdist as rd
use e.algo.stat.gparot as gp
use e.algo.stat.fcast as fcast
use e.algo.linalg.decomp as dc
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn lgam(x: f64) -> f64 { ret nm.lgammafn(x) }

// ---- transformed beta (shape1 a, shape2 g, shape3 t, scale th): u = v / (1 + v), v = (x / th)^g; F = pbeta(u, t, a)

fn tb_u(x: f64, g: f64, th: f64) -> f64 {
    let v = math.pow[f64](x / th, g)
    ret v / (1.0f64 + v)
}

fn tb_d(x: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let v = math.pow[f64](x / th, g)
    let u = v / (1.0f64 + v)
    let lg = math.log[f64](g) + t * math.log[f64](u) + a * math.log[f64](1.0f64 - u) - math.log[f64](x) - nb.lbeta(a, t)
    ret math.exp[f64](lg)
}

fn tb_p(x: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret nb.pbeta(tb_u(x, g, th), t, a, true, false)
}

fn tb_q(p: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    let u = nb.qbeta(p, t, a, true, false)
    ret th * math.pow[f64](u / (1.0f64 - u), 1.0f64 / g)
}

// E[X^k] for -t g < k < a g
fn tb_m(k: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    ret math.pow[f64](th, k) * math.exp[f64](lgam(t + k / g) + lgam(a - k / g) - lgam(a) - lgam(t))
}

// E[min(X, x)^k]
fn tb_lev(x: f64, k: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    let u = tb_u(x, g, th)
    let c = math.pow[f64](th, k) * math.exp[f64](lgam(t + k / g) + lgam(a - k / g) - lgam(a) - lgam(t))
    ret c * nb.pbeta(u, t + k / g, a - k / g, true, false) + math.pow[f64](x, k) * (1.0f64 - nb.pbeta(u, t, a, true, false))
}

// the parameter maps: kind 0 burr (shape1 = a, shape2 = g), 1 invburr (shape1 = t, shape2 = g), 2 pareto (a), 3 invpareto (t),
// 4 llogis (g), 5 paralogis (a), 6 invparalogis (t), 7 genpareto (shape1 = a, shape2 = t), 8 trbeta (a, g, t); returns (a, g, t)
fn tb_params(kind: u8, s1: f64, s2: f64, s3: f64) -> (f64, f64, f64) {
    if kind == 0u8 { ret (s1, s2, 1.0f64) }
    if kind == 1u8 { ret (1.0f64, s2, s1) }
    if kind == 2u8 { ret (s1, 1.0f64, 1.0f64) }
    if kind == 3u8 { ret (1.0f64, 1.0f64, s1) }
    if kind == 4u8 { ret (1.0f64, s1, 1.0f64) }
    if kind == 5u8 { ret (s1, s1, 1.0f64) }
    if kind == 6u8 { ret (1.0f64, s1, s1) }
    if kind == 7u8 { ret (s1, 1.0f64, s2) }
    ret (s1, s2, s3)
}

// ---- transformed gamma (shape1 a, shape2 t, scale th): u = (x / th)^t, F = pgamma(u, a)

fn tg_d(x: f64, a: f64, t: f64, th: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let u = math.pow[f64](x / th, t)
    ret math.exp[f64](math.log[f64](t) + a * math.log[f64](u) - u - math.log[f64](x) - lgam(a))
}

fn tg_p(x: f64, a: f64, t: f64, th: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret nm.pgamma(math.pow[f64](x / th, t), a, 1.0f64, true, false)
}

fn tg_q(p: f64, a: f64, t: f64, th: f64) -> f64 { ret th * math.pow[f64](nm.qgamma(p, a, 1.0f64, true, false), 1.0f64 / t) }

fn tg_m(k: f64, a: f64, t: f64, th: f64) -> f64 { ret math.pow[f64](th, k) * math.exp[f64](lgam(a + k / t) - lgam(a)) }

fn tg_lev(x: f64, k: f64, a: f64, t: f64, th: f64) -> f64 {
    let u = math.pow[f64](x / th, t)
    ret math.pow[f64](th, k) * math.exp[f64](lgam(a + k / t) - lgam(a)) * nm.pgamma(u, a + k / t, 1.0f64, true, false) + math.pow[f64](x, k) * nm.pgamma(u, a, 1.0f64, false, false)
}

// ---- inverse transformed gamma: u = (th / x)^t, F = 1 - pgamma(u, a)

fn itg_d(x: f64, a: f64, t: f64, th: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let u = math.pow[f64](th / x, t)
    ret math.exp[f64](math.log[f64](t) + a * math.log[f64](u) - u - math.log[f64](x) - lgam(a))
}

fn itg_p(x: f64, a: f64, t: f64, th: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret nm.pgamma(math.pow[f64](th / x, t), a, 1.0f64, false, false)
}

fn itg_q(p: f64, a: f64, t: f64, th: f64) -> f64 { ret th * math.pow[f64](nm.qgamma(p, a, 1.0f64, false, false), 0.0f64 - 1.0f64 / t) }

// for k < a t
fn itg_m(k: f64, a: f64, t: f64, th: f64) -> f64 { ret math.pow[f64](th, k) * math.exp[f64](lgam(a - k / t) - lgam(a)) }

fn itg_lev(x: f64, k: f64, a: f64, t: f64, th: f64) -> f64 {
    let u = math.pow[f64](th / x, t)
    ret math.pow[f64](th, k) * math.exp[f64](lgam(a - k / t) - lgam(a)) * nm.pgamma(u, a - k / t, 1.0f64, false, false) + math.pow[f64](x, k) * nm.pgamma(u, a, 1.0f64, true, false)
}

// ---- single-parameter Pareto (shape a, min m): F = 1 - (m / x)^a for x > m

fn p1_d(x: f64, a: f64, m: f64) -> f64 {
    if x < m { ret 0.0f64 }
    ret a * math.pow[f64](m, a) / math.pow[f64](x, a + 1.0f64)
}

fn p1_p(x: f64, a: f64, m: f64) -> f64 {
    if x <= m { ret 0.0f64 }
    ret 1.0f64 - math.pow[f64](m / x, a)
}

fn p1_q(p: f64, a: f64, m: f64) -> f64 { ret m / math.pow[f64](1.0f64 - p, 1.0f64 / a) }

fn p1_m(k: f64, a: f64, m: f64) -> f64 { ret a * math.pow[f64](m, k) / (a - k) }

fn p1_lev(x: f64, k: f64, a: f64, m: f64) -> f64 {
    ret a * math.pow[f64](m, k) / (a - k) - k * math.pow[f64](m, a) / ((a - k) * math.pow[f64](x, a - k))
}

// actuar aggregateDist("recursive"): Panjer's recursion for the aggregate claim probabilities fs[0 .. nn] from the discretised severity fx (fx[0] the mass at zero) and a frequency of the (a, b, 0) class: kind 0 Poisson(p1 = lambda),
// 1 binomial(p1 = size, p2 = prob), 2 negative binomial(p1 = size, p2 = prob), 3 geometric(p1 = prob); fs[x] = (1 / (1 - a fx[0])) sum_{y = 1..x} (a + b y / x) fx[y] fs[x - y]
fn panjer(kind: usize, p1: f64, p2: f64, fx: []const f64, nn: usize, fs: []f64) {
    let f0 = fx[0usize]
    var a = 0.0f64
    var b = 0.0f64
    var s0 = 0.0f64
    if kind == 0usize {
        b = p1
        s0 = math.exp[f64](p1 * (f0 - 1.0f64))
    } else if kind == 1usize {
        a = p2 / (p2 - 1.0f64)
        b = 0.0f64 - (p1 + 1.0f64) * a
        s0 = math.exp[f64](p1 * dsa.log1p(p2 * (f0 - 1.0f64)))
    } else if kind == 2usize {
        a = 1.0f64 - p2
        b = (p1 - 1.0f64) * a
        s0 = math.exp[f64](0.0f64 - p1 * dsa.log1p(0.0f64 - a / p2 * (f0 - 1.0f64)))
    } else {
        a = 1.0f64 - p1
        s0 = math.exp[f64](0.0f64 - 1.0f64 * dsa.log1p(0.0f64 - a / p1 * (f0 - 1.0f64)))
    }
    fs[0usize] = s0
    var x = 1usize
    while x <= nn {
        var s = 0.0f64
        var y = 1usize
        while y <= x && y < fx.len {
            s += (a + b * f64(y) / f64(x)) * fx[y] * fs[x - y]
            y += 1usize
        }
        fs[x] = s / (1.0f64 - a * f0)
        x += 1usize
    }
}

// actuar discretize(cdf, from, to, step, method) from the cdf values ff[k] at from + k step / 2 (k = 0 .. 2 n, n = (to - from) / step): method 0 "upper" (n values F(x + h) - F(x)), 1 "lower" (n + 1 values: zero, then F(x) - F(x - h)),
// 2 "rounding" (n values: F(from + h / 2) - F(from), then F(x + h / 2) - F(x - h / 2) for the interior points); the answer is how many values went into out
fn discretize_cdf(method: usize, ff: []const f64, n: usize, out: []f64) -> usize {
    if method == 0usize {
        var j = 0usize
        while j < n {
            out[j] = ff[2usize * (j + 1usize)] - ff[2usize * j]
            j += 1usize
        }
        ret n
    }
    if method == 1usize {
        out[0usize] = 0.0f64
        var j = 1usize
        while j <= n {
            out[j] = ff[2usize * j] - ff[2usize * (j - 1usize)]
            j += 1usize
        }
        ret n + 1usize
    }
    out[0usize] = ff[1usize] - ff[0usize]
    var j = 1usize
    while j < n {
        out[j] = ff[2usize * j + 1usize] - ff[2usize * j - 1usize]
        j += 1usize
    }
    ret n
}

// actuar aggregateDist("convolution"): the aggregate probabilities fs[0 .. nn] = sum_n pn[n] f^(*n) with pn the frequency probabilities (n = 0 .. pn.len - 1) and f the discretised severity fx (mass at 0, 1, 2 ...); work (2 * (nn + 1) floats) is scratch
fn aggregate_convolution(pn: []const f64, fx: []const f64, nn: usize, fs: []f64, work: []f64) {
    var x = 0usize
    while x <= nn {
        fs[x] = 0.0f64
        work[x] = 0.0f64
        x += 1usize
    }
    // work holds f^(*n), starting with the point mass at 0
    work[0usize] = 1.0f64
    var n = 0usize
    while n < pn.len {
        x = 0usize
        while x <= nn {
            fs[x] += pn[n] * work[x]
            x += 1usize
        }
        // work <- work * fx, into the second half of the scratch and back
        x = 0usize
        while x <= nn {
            var s = 0.0f64
            var y = 0usize
            while y <= x && y < fx.len {
                s += fx[y] * work[x - y]
                y += 1usize
            }
            work[nn + 1usize + x] = s
            x += 1usize
        }
        x = 0usize
        while x <= nn {
            work[x] = work[nn + 1usize + x]
            x += 1usize
        }
        n += 1usize
    }
}

// actuar aggregateDist("normal", moments = c(mean, variance)): the normal approximation of the aggregate claims
fn agg_normal(x: f64, mean: f64, variance: f64) -> f64 { ret dsa.pnorm(x, mean, math.sqrt[f64](variance), true, false) }

// aggregateDist("npower", moments = c(mean, variance, skewness)): the Normal Power approximation, undefined (NaN, actuar's NA) at or below the mean
fn agg_npower(x: f64, mean: f64, variance: f64, skewness: f64) -> f64 {
    if x <= mean { ret 0.0f64 / 0.0f64 }
    ret dsa.pnorm(math.sqrt[f64](1.0f64 + 9.0f64 / (skewness * skewness) + 6.0f64 * (x - mean) / (math.sqrt[f64](variance) * skewness)) - 3.0f64 / skewness, 0.0f64, 1.0f64, true, false)
}

// actuar grouped data with class boundaries cj (r + 1 values) and class counts nj (r values): ogive(gd)(x), the piecewise-linear empirical cdf through the cumulative proportions at the boundaries
fn grouped_ogive(cj: []const f64, nj: []const f64, x: f64) -> f64 {
    let r = nj.len
    var tot = 0.0f64
    var j = 0usize
    while j < r {
        tot += nj[j]
        j += 1usize
    }
    if x <= cj[0usize] { ret 0.0f64 }
    if x >= cj[r] { ret 1.0f64 }
    var cum = 0.0f64
    j = 0usize
    while j < r {
        if x < cj[j + 1usize] {
            ret (cum + nj[j] * (x - cj[j]) / (cj[j + 1usize] - cj[j])) / tot
        }
        cum += nj[j]
        j += 1usize
    }
    ret 1.0f64
}

// emm(gd, order): the empirical raw moment of order k of grouped data under the uniform-within-class assumption
fn grouped_emm(cj: []const f64, nj: []const f64, k: f64) -> f64 {
    var tot = 0.0f64
    var s = 0.0f64
    var j = 0usize
    while j < nj.len {
        tot += nj[j]
        s += nj[j] * (math.pow[f64](cj[j + 1usize], k + 1.0f64) - math.pow[f64](cj[j], k + 1.0f64)) / ((k + 1.0f64) * (cj[j + 1usize] - cj[j]))
        j += 1usize
    }
    ret s / tot
}

// elev(gd)(x): the empirical limited expected value E[min(X, x)] of grouped data, uniform within each class
fn grouped_elev(cj: []const f64, nj: []const f64, x: f64) -> f64 {
    var tot = 0.0f64
    var s = 0.0f64
    var j = 0usize
    while j < nj.len {
        tot += nj[j]
        let lo = cj[j]
        let hi = cj[j + 1usize]
        let w = hi - lo
        var m = 0.0f64
        if x >= hi {
            m = 0.5f64 * (lo + hi)
        } else if x <= lo {
            m = x
        } else {
            m = (x * x - lo * lo) / (2.0f64 * w) + x * (hi - x) / w
        }
        s += nj[j] * m
        j += 1usize
    }
    ret s / tot
}

// actuar discretize(method = "unbiased"): ex = the limited expected value at from + k h (k = 0 .. n), f0 and f1 the cdf at from and to; out receives the n + 1 masses (the first at from, the last at to)
fn discretize_unbiased(ex: []const f64, n: usize, h: f64, f0: f64, f1: f64, out: []f64) -> usize {
    out[0usize] = 0.0f64 - (ex[1usize] - ex[0usize]) / h + 1.0f64 - f0
    var j = 1usize
    while j < n {
        out[j] = (2.0f64 * ex[j] - ex[j - 1usize] - ex[j + 1usize]) / h
        j += 1usize
    }
    out[n] = (ex[n] - ex[n - 1usize]) / h - 1.0f64 + f1
    ret n + 1usize
}

// actuar cm(): Buhlmann-Straub credibility for I contracts; ns[i] the years of contract i, x and w (ratios and weights) the years of contract 0 first, then contract 1 and so on; out = (within variance s2, between variance a, k = s2 / a, collective mean m); the credibility premium of contract i is z_i xbar_i + (1 - z_i) m with z_i = w_i / (w_i + k)
fn cm_buhlmann_straub(ns: []const usize, x: []const f64, w: []const f64, out: []f64) {
    let ni = ns.len
    var wtot = 0.0f64
    var ws2 = 0.0f64
    var xw = 0.0f64
    var s2num = 0.0f64
    var df = 0.0f64
    var pos = 0usize
    var i = 0usize
    while i < ni {
        var wi = 0.0f64
        var si = 0.0f64
        var j = 0usize
        while j < ns[i] {
            wi += w[pos + j]
            si += w[pos + j] * x[pos + j]
            j += 1usize
        }
        let xb = si / wi
        j = 0usize
        while j < ns[i] {
            let d = x[pos + j] - xb
            s2num += w[pos + j] * d * d
            j += 1usize
        }
        df += f64(ns[i]) - 1.0f64
        wtot += wi
        ws2 += wi * wi
        xw += si
        pos += ns[i]
        i += 1usize
    }
    let s2 = s2num / df
    let xbar = xw / wtot
    var bn = 0.0f64
    pos = 0usize
    i = 0usize
    while i < ni {
        var wi = 0.0f64
        var si = 0.0f64
        var j = 0usize
        while j < ns[i] {
            wi += w[pos + j]
            si += w[pos + j] * x[pos + j]
            j += 1usize
        }
        let d = si / wi - xbar
        bn += wi * d * d
        pos += ns[i]
        i += 1usize
    }
    let a = (bn - (f64(ni) - 1.0f64) * s2) / (wtot - ws2 / wtot)
    let k = s2 / a
    var zs = 0.0f64
    var zx = 0.0f64
    pos = 0usize
    i = 0usize
    while i < ni {
        var wi = 0.0f64
        var si = 0.0f64
        var j = 0usize
        while j < ns[i] {
            wi += w[pos + j]
            si += w[pos + j] * x[pos + j]
            j += 1usize
        }
        let z = wi / (wi + k)
        zs += z
        zx += z * si / wi
        pos += ns[i]
        i += 1usize
    }
    out[0usize] = s2
    out[1usize] = a
    out[2usize] = k
    out[3usize] = zx / zs
}

// actuar ruin() with exponential claims (rate beta) and exponential waiting times (rate lambda) at premium rate c: the Cramer-Lundberg ruin probability psi(u) = lambda / (c beta) exp(-(beta - lambda / c) u)
fn ruin_exp_exp(u: f64, beta: f64, lambda: f64, c: f64) -> f64 {
    ret lambda / (c * beta) * math.exp[f64](0.0f64 - (beta - lambda / c) * u)
}

// actuar phase-type distribution with initial probabilities prob[m] and sub-intensity matrix t (m x m, row-major): the density pi exp(T x) (-T 1) and the survival pi exp(T x) 1 at x >= 0, answered as (d, sf)
fn ph_dens_surv(a: *mem.Arena, prob: []const f64, t: []const f64, m: usize, x: f64) -> (f64, f64) {
    let (sx, e1) = mem.alloc[f64](a, m * m)
    let (ex, e2) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok { ret (nan(), nan()) }
    var i = 0usize
    while i < m * m {
        sx[i] = t[i] * x
        i += 1usize
    }
    let ee = mexp.expm(a, sx, m, ex)
    if ee != ok { ret (nan(), nan()) }
    var d = 0.0f64
    var sf = 0.0f64
    i = 0usize
    while i < m {
        var rs = 0.0f64
        var j = 0usize
        while j < m {
            rs += ex[i * m + j]
            j += 1usize
        }
        var pe = 0.0f64
        j = 0usize
        while j < m {
            pe += ex[i * m + j] * (0.0f64 - rowsum(t, m, j))
            j += 1usize
        }
        d += prob[i] * pe
        sf += prob[i] * rs
        i += 1usize
    }
    ret (d, sf)
}

fn rowsum(t: []const f64, m: usize, i: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < m {
        s += t[i * m + j]
        j += 1usize
    }
    ret s
}

// actuar mphtype: the raw moment of integer order k, k! pi (-T)^(-k) 1
fn ph_moment(a: *mem.Arena, prob: []const f64, t: []const f64, m: usize, k: usize) -> f64 {
    let (neg, e1) = mem.alloc[f64](a, m * m)
    let (v, e2) = mem.alloc[f64](a, m)
    let (nv, e3) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok { ret nan() }
    var i = 0usize
    while i < m * m {
        neg[i] = 0.0f64 - t[i]
        i += 1usize
    }
    let (inv, ei) = gp.invert(a, neg, m)
    if ei != ok { ret nan() }
    i = 0usize
    while i < m {
        v[i] = 1.0f64
        i += 1usize
    }
    var s = 0usize
    while s < k {
        i = 0usize
        while i < m {
            var acc = 0.0f64
            var j = 0usize
            while j < m {
                acc += inv[i * m + j] * v[j]
                j += 1usize
            }
            nv[i] = acc
            i += 1usize
        }
        i = 0usize
        while i < m {
            v[i] = nv[i]
            i += 1usize
        }
        s += 1usize
    }
    var r = 0.0f64
    i = 0usize
    while i < m {
        r += prob[i] * v[i]
        i += 1usize
    }
    var f = 1.0f64
    s = 2usize
    while s <= k {
        f *= f64(s)
        s += 1usize
    }
    ret f * r
}

// ---- loggamma (shapelog a, ratelog r; x > 1): F = pgamma(log x, a, rate r)
fn lg_d(x: f64, a: f64, r: f64) -> f64 {
    if x <= 1.0f64 { ret 0.0f64 }
    ret math.exp[f64](a * math.log[f64](r) + (a - 1.0f64) * math.log[f64](math.log[f64](x)) - (r + 1.0f64) * math.log[f64](x) - lgam(a))
}

fn lg_p(x: f64, a: f64, r: f64) -> f64 {
    if x <= 1.0f64 { ret 0.0f64 }
    ret nm.pgamma(math.log[f64](x), a, 1.0f64 / r, true, false)
}

fn lg_q(p: f64, a: f64, r: f64) -> f64 { ret math.exp[f64](nm.qgamma(p, a, 1.0f64 / r, true, false)) }

// the raw moment (r / (r - k))^a, finite for k < r
fn lg_m(k: f64, a: f64, r: f64) -> f64 { ret math.pow[f64](r / (r - k), a) }

// ---- Gumbel (alpha location, scale)
fn gu_d(x: f64, al: f64, sc: f64) -> f64 {
    let u = (x - al) / sc
    ret math.exp[f64](0.0f64 - (u + math.exp[f64](0.0f64 - u))) / sc
}

fn gu_p(x: f64, al: f64, sc: f64) -> f64 { ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - (x - al) / sc)) }

fn gu_q(p: f64, al: f64, sc: f64) -> f64 { ret al - sc * math.log[f64](0.0f64 - math.log[f64](p)) }

// ---- zero-truncated and zero-modified counts over a base law: kind 0 Poisson(a), 1 negative binomial(size a, prob b), 2 binomial(size a, prob b), 3 geometric(prob b)
fn cnt_d(kind: usize, x: f64, a: f64, b: f64) -> f64 {
    if kind == 0usize { ret nm.dpois(x, a, false) }
    if kind == 2usize { ret nb.dbinom(x, a, b, false) }
    if kind == 3usize { ret nb.dgeom(x, b, false) }
    ret nb.dnbinom(x, a, b, false)
}

fn cnt_p(kind: usize, x: f64, a: f64, b: f64) -> f64 {
    if kind == 0usize { ret nm.ppois(x, a, true, false) }
    if kind == 2usize { ret nb.pbinom(x, a, b, true, false) }
    if kind == 3usize { ret nb.pgeom(x, b, true, false) }
    ret nb.pnbinom(x, a, b, true, false)
}

fn zt_d(kind: usize, x: f64, a: f64, b: f64) -> f64 {
    if x < 1.0f64 { ret 0.0f64 }
    ret cnt_d(kind, x, a, b) / (1.0f64 - cnt_d(kind, 0.0f64, a, b))
}

fn zt_p(kind: usize, x: f64, a: f64, b: f64) -> f64 {
    if x < 1.0f64 { ret 0.0f64 }
    let f0 = cnt_d(kind, 0.0f64, a, b)
    ret (cnt_p(kind, x, a, b) - f0) / (1.0f64 - f0)
}

fn zm_d(kind: usize, x: f64, a: f64, b: f64, p0: f64) -> f64 {
    if x == 0.0f64 { ret p0 }
    ret (1.0f64 - p0) * zt_d(kind, x, a, b)
}

fn zm_p(kind: usize, x: f64, a: f64, b: f64, p0: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret p0 + (1.0f64 - p0) * zt_p(kind, x, a, b)
}

// ---- inverse Gaussian (mean mu, shape s)
fn ig_d(x: f64, mu: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let d = x - mu
    ret math.sqrt[f64](s / (2.0f64 * 3.141592653589793f64 * x * x * x)) * math.exp[f64](0.0f64 - s * d * d / (2.0f64 * mu * mu * x))
}

fn ig_p(x: f64, mu: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let r = math.sqrt[f64](s / x)
    ret dsa.pnorm(r * (x / mu - 1.0f64), 0.0f64, 1.0f64, true, false) + math.exp[f64](2.0f64 * s / mu) * dsa.pnorm(0.0f64 - r * (x / mu + 1.0f64), 0.0f64, 1.0f64, true, false)
}

// ---- logarithmic (prob q): f(x) = -q^x / (x log(1 - q)), x >= 1
fn logd_d(x: f64, q: f64) -> f64 {
    if x < 1.0f64 { ret 0.0f64 }
    ret 0.0f64 - math.pow[f64](q, x) / (x * math.log[f64](1.0f64 - q))
}

fn logd_p(x: f64, q: f64) -> f64 {
    var s = 0.0f64
    var k = 1.0f64
    while k <= math.floor[f64](x) {
        s += logd_d(k, q)
        k += 1.0f64
    }
    ret s
}

// ---- generalised beta (shape1 a, shape2 b, shape3 t, scale th): X = th B^(1/t) with B ~ Beta(a, b), support (0, th)
fn gb_d(x: f64, a: f64, b: f64, t: f64, th: f64) -> f64 {
    if x <= 0.0f64 || x >= th { ret 0.0f64 }
    let u = math.pow[f64](x / th, t)
    ret t * u / x * nb.dbeta(u, a, b, false)
}

fn gb_p(x: f64, a: f64, b: f64, t: f64, th: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    if x >= th { ret 1.0f64 }
    ret nb.pbeta(math.pow[f64](x / th, t), a, b, true, false)
}

fn gb_q(p: f64, a: f64, b: f64, t: f64, th: f64) -> f64 { ret th * math.pow[f64](nb.qbeta(p, a, b, true, false), 1.0f64 / t) }

fn gb_m(k: f64, a: f64, b: f64, t: f64, th: f64) -> f64 {
    ret math.pow[f64](th, k) * math.exp[f64](lgam(a + b) + lgam(a + k / t) - lgam(a) - lgam(a + b + k / t))
}

// loggamma limited moment E[min(X, x)^k], k < r
fn lg_lev(x: f64, k: f64, a: f64, r: f64) -> f64 {
    if x <= 1.0f64 { ret 0.0f64 }
    let lx = math.log[f64](x)
    ret math.pow[f64](r / (r - k), a) * nm.pgamma(lx, a, 1.0f64 / (r - k), true, false) + math.pow[f64](x, k) * nm.pgamma(lx, a, 1.0f64 / r, false, false)
}

// inverse Gaussian raw moment of order 1, 2 or 3
fn ig_m(k: usize, mu: f64, s: f64) -> f64 {
    if k == 1usize { ret mu }
    if k == 2usize { ret mu * mu + mu * mu * mu / s }
    ret mu * mu * mu + 3.0f64 * mu * mu * mu * mu / s + 3.0f64 * mu * mu * mu * mu * mu / (s * s)
}

// generalised beta limited moment E[min(X, x)^k]
fn gb_lev(x: f64, k: f64, a: f64, b: f64, t: f64, th: f64) -> f64 {
    if x >= th { ret gb_m(k, a, b, t, th) }
    let u = math.pow[f64](x / th, t)
    ret gb_m(k, a, b, t, th) * nb.pbeta(u, a + k / t, b, true, false) + math.pow[f64](x, k) * nb.pbeta(u, a, b, false, false)
}

// Gumbel raw moment of order 1 or 2 (actuar answers NaN above 2): X = alpha + scale G
fn gu_m(k: usize, al: f64, sc: f64) -> f64 {
    let g = 0.5772156649015329f64
    let pi2 = 9.869604401089358f64
    if k == 1usize { ret al + sc * g }
    if k == 2usize { ret al * al + 2.0f64 * al * sc * g + sc * sc * (g * g + pi2 / 6.0f64) }
    ret nan()
}

// quantile of the base count law by search (smallest x with cdf >= p, R's 1 - 64 eps fuzz)
fn cnt_q(kind: usize, p: f64, a: f64, b: f64) -> f64 {
    let goal = p * (1.0f64 - 64.0f64 * 2.220446049250313e-16f64)
    var x = 0.0f64
    while cnt_p(kind, x, a, b) < goal && x < 1.0e6f64 { x += 1.0f64 }
    ret x
}

// zero-truncated quantile: the base quantile at p + (1 - p) f(0)
fn zt_q(kind: usize, p: f64, a: f64, b: f64) -> f64 {
    ret cnt_q(kind, p + (1.0f64 - p) * cnt_d(kind, 0.0f64, a, b), a, b)
}

// zero-modified quantile: 0 up to p0, then the zero-truncated quantile of the rescaled probability
fn zm_q(kind: usize, p: f64, a: f64, b: f64, p0: f64) -> f64 {
    if p <= p0 { ret 0.0f64 }
    ret zt_q(kind, (p - p0) / (1.0f64 - p0), a, b)
}

// inverse Gaussian quantile by bisection on the cdf
fn ig_q(p: f64, mu: f64, s: f64) -> f64 {
    var lo = 0.0f64
    var hi = mu
    while ig_p(hi, mu, s) < p && hi < 1.0e300f64 { hi *= 2.0f64 }
    var i = 0usize
    while i < 200usize {
        let mid = 0.5f64 * (lo + hi)
        if ig_p(mid, mu, s) < p { lo = mid } else { hi = mid }
        i += 1usize
    }
    ret 0.5f64 * (lo + hi)
}

// one actuar random draw under the R streams: kind 0 rburr (shape1 p1, shape2 p2, scale sc; the inversion runs on 1 - u), 1 rtrgamma (p1, p2, sc),
// 2 rinvgamma (p1, sc), 3 rgumbel (alpha p1, scale p2), 4 rlgamma (shapelog p1, ratelog p2), 5 rpareto1 (shape p1, min p2), 6 rinvtrgamma (p1, p2, sc), 7 rinvweibull (shape p1, scale sc), 8 rinvexp (scale sc), 9 rgenbeta (shape1 p1, shape2 p2, shape3 p3, scale sc), 10 rtrbeta (shape1 p1, shape2 p2, shape3 p3, scale sc), 11 rgenpareto (shape1 p1, shape2 p2, scale sc)
fn rand_draw(g: *rr.Rng, kind: usize, p1: f64, p2: f64, p3: f64, sc: f64) -> f64 {
    if kind == 0usize { ret tb_q(1.0f64 - rr.unif(g), p1, p2, 1.0f64, sc) }
    if kind == 1usize { ret sc * math.pow[f64](rr.rgamma(g, p1, 1.0f64), 1.0f64 / p2) }
    if kind == 2usize { ret sc / rr.rgamma(g, p1, 1.0f64) }
    if kind == 3usize { ret p1 - p2 * math.log[f64](rr.rexp(g, 1.0f64)) }
    if kind == 4usize { ret math.exp[f64](rr.rgamma(g, p1, 1.0f64 / p2)) }
    if kind == 5usize { ret p2 / math.pow[f64](rr.unif(g), 1.0f64 / p1) }
    if kind == 6usize { ret sc * math.pow[f64](rr.rgamma(g, p1, 1.0f64), 0.0f64 - 1.0f64 / p2) }
    if kind == 7usize { ret sc * math.pow[f64](rr.rexp(g, 1.0f64), 0.0f64 - 1.0f64 / p1) }
    if kind == 8usize { ret sc / rr.rexp(g, 1.0f64) }
    if kind == 9usize { ret sc * math.pow[f64](rd.rbeta(g, p1, p2), 1.0f64 / p3) }
    if kind == 10usize {
        let bt = rd.rbeta(g, p3, p1)
        ret sc * math.pow[f64](bt / (1.0f64 - bt), 1.0f64 / p2)
    }
    let bg = rd.rbeta(g, p2, p1)
    ret sc * bg / (1.0f64 - bg)
}

// actuar random draw for the transformed beta maps (tb_params kinds 0 burr .. 6 invparalogis): the inversion runs on 1 - u for burr, pareto, llogis and paralogis and on u for the inverse families
fn rand_tb(g: *rr.Rng, kind: u8, s1: f64, s2: f64, sc: f64) -> f64 {
    let (a, ga, t) = tb_params(kind, s1, s2, 1.0f64)
    let u = rr.unif(g)
    if kind == 1u8 || kind == 3u8 || kind == 6u8 { ret tb_q(u, a, ga, t, sc) }
    ret tb_q(1.0f64 - u, a, ga, t, sc)
}

// one actuar random count under the R streams by inversion of the uniform: kinds 0 to 3 are the zero-truncated Poisson, negative binomial, binomial and geometric
// (the base kinds of cnt_d), kind 4 the logarithmic law with prob a
fn rand_count(g: *rr.Rng, kind: usize, a: f64, b: f64) -> f64 {
    let u = rr.unif(g)
    if kind < 4usize { ret zt_q(kind, u, a, b) }
    let goal = u * (1.0f64 - 64.0f64 * 2.220446049250313e-16f64)
    var x = 1.0f64
    while logd_p(x, a) < goal && x < 1.0e6f64 { x += 1.0f64 }
    ret x
}

// actuar ruin() with phase-type claims (prob, sub-intensity t) and exponential waiting times (rate lambda) at premium rate c: psi(u) = pi+ exp((T + t pi+) u) 1 with
// pi+ = -(lambda / c) pi T^(-1) and t = -T 1
fn ruin_ph_exp(a: *mem.Arena, prob: []const f64, t: []const f64, m: usize, u: f64, lambda: f64, c: f64) -> f64 {
    let (neg, e1) = mem.alloc[f64](a, m * m)
    let (qu, e2) = mem.alloc[f64](a, m * m)
    let (ex, e3) = mem.alloc[f64](a, m * m)
    let (pp, e4) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan() }
    var i = 0usize
    while i < m * m {
        neg[i] = 0.0f64 - t[i]
        i += 1usize
    }
    let (inv, ei) = gp.invert(a, neg, m)
    if ei != ok { ret nan() }
    // pi+ = (lambda / c) pi (-T)^(-1)
    var j = 0usize
    while j < m {
        var s = 0.0f64
        i = 0usize
        while i < m {
            s += prob[i] * inv[i * m + j]
            i += 1usize
        }
        pp[j] = lambda / c * s
        j += 1usize
    }
    i = 0usize
    while i < m {
        var ti = 0.0f64
        j = 0usize
        while j < m {
            ti -= t[i * m + j]
            j += 1usize
        }
        j = 0usize
        while j < m {
            qu[i * m + j] = (t[i * m + j] + ti * pp[j]) * u
            j += 1usize
        }
        i += 1usize
    }
    let ee = mexp.expm(a, qu, m, ex)
    if ee != ok { ret nan() }
    var r = 0.0f64
    i = 0usize
    while i < m {
        j = 0usize
        while j < m {
            r += pp[i] * ex[i * m + j]
            j += 1usize
        }
        i += 1usize
    }
    ret r
}

// actuar rcompound(n, rpois(lambda), rgamma(shape, rate)): n counts first, then sum(N) severities in one run, summed per simulation in order; out receives the n aggregates
fn rcompound_pois_gamma(a: *mem.Arena, g: *rr.Rng, n: usize, lambda: f64, shape: f64, rate: f64, out: []f64) -> err {
    let (cnt, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        cnt[i] = usize(rd.rpois(g, lambda))
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var k = 0usize
        while k < cnt[i] {
            out[i] += rd.rgamma(g, shape, 1.0f64 / rate)
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

// actuar bayes(x, likelihood, prior): linear Bayes credibility from the observations x. kind 0 Poisson (Gamma prior shape p1, scale p2), 1 Bernoulli (Beta shape1 p1, shape2 p2), 2 binomial
// (Beta p1, p2, size p3), 3 geometric (Beta p1, p2), 4 negative binomial (Beta p1, p2, size p3), 5 exponential (Gamma p1, p2), 6 gamma (Gamma p1, p2, shape of the likelihood p3), 7 normal
// (prior mean p1, prior sd p2, likelihood sd p3), 8 Pareto (Gamma p1, p2, lower bound p3); out = (collective mean, individual mean, credibility factor, first variance, second variance)
fn bayes_linear(kind: usize, p1: f64, p2: f64, p3: f64, x: []const f64, out: []f64) {
    let n = f64(x.len)
    var coll = 0.0f64
    var k = 0.0f64
    var v1 = 0.0f64
    var v2 = 0.0f64
    var ind = 0.0f64
    var cred = 0.0f64
    if kind == 8usize {
        coll = p1 * p2
        v1 = 0.0f64 / 0.0f64
        v2 = v1
        var sl = 0.0f64
        var i = 0usize
        while i < x.len {
            sl += math.log[f64](x[i])
            i += 1usize
        }
        sl = sl - n * math.log[f64](p3)
        ind = n / sl
        cred = 1.0f64 / (1.0f64 + 1.0f64 / (p2 * sl))
    } else {
        if kind == 0usize {
            coll = p1 * p2
            v1 = coll * p2
            v2 = coll
            k = 1.0f64 / p2
        } else if kind == 1usize {
            k = p1 + p2
            coll = p1 / k
            v1 = p1 * p2 * 1.0f64 / (k * k * (k + 1.0f64))
            v2 = p1 * p2 * k / (k * k * (k + 1.0f64))
        } else if kind == 2usize {
            k = (p1 + p2) / p3
            coll = p1 / k
            v1 = p1 * p2 * 1.0f64 / (k * k * (p1 + p2 + 1.0f64))
            v2 = p1 * p2 * k / (k * k * (p1 + p2 + 1.0f64))
        } else if kind == 3usize {
            k = p1 - 1.0f64
            coll = p2 / k
            let vv = p2 * (p1 + p2 - 1.0f64) / (k * (k - 1.0f64))
            v1 = vv / k
            v2 = vv
        } else if kind == 4usize {
            k = (p1 - 1.0f64) / p3
            coll = p2 / k
            let vv = p2 * (p1 + p2 - 1.0f64) / (k * (p1 - 2.0f64))
            v1 = vv / k
            v2 = vv
        } else if kind == 5usize {
            k = p1 - 1.0f64
            coll = 1.0f64 / (k * p2)
            v1 = coll * coll / (p1 - 2.0f64)
            v2 = coll / p2 / (p1 - 2.0f64)
        } else if kind == 6usize {
            k = (p1 - 1.0f64) / p3
            coll = 1.0f64 / (k * p2)
            v1 = coll * coll / (p1 - 2.0f64)
            v2 = coll / p2 / (p1 - 2.0f64)
        } else {
            coll = p1
            v1 = p2 * p2
            v2 = p3 * p3
            k = v2 / v1
        }
        var s = 0.0f64
        var i = 0usize
        while i < x.len {
            s += x[i]
            i += 1usize
        }
        ind = s / n
        cred = n / (n + k)
    }
    out[0usize] = coll
    out[1usize] = ind
    out[2usize] = cred
    out[3usize] = v1
    out[4usize] = v2
}

// actuar hache.origin (the regression credibility model of Hachemeister, iterative estimator without the barycentre adjustment) for full data: ratios and weights are n contracts by t periods
// (row-major), xreg the t by p design. Each contract's weighted regression gives its coefficients beta_i, its residual variance and (X' W X)^-1; the iteration re-estimates the between
// covariance A and the credibility matrices A (A + s2 W_i)^-1 until the collective coefficients settle (relative change below tol, at most maxit rounds). out = (collective coefficients [p],
// A [p * p], s2, the summed credibility matrix [p * p], iterations)
fn hache_origin(a: *mem.Arena, ratios: []const f64, weights: []const f64, xreg: []const f64, n: usize, t: usize, p: usize, tol: f64, maxit: usize, out: []f64) -> err {
    let (beta, e1) = mem.alloc[f64](a, n * p)
    let (wi, e2) = mem.alloc[f64](a, n * p * p)
    let (cred, e3) = mem.alloc[f64](a, n * p * p)
    let (coll, e4) = mem.alloc[f64](a, p)
    let (coll1, e5) = mem.alloc[f64](a, p)
    let (am, e6) = mem.alloc[f64](a, p * p)
    let (tmp, e7) = mem.alloc[f64](a, p * p)
    let (crs, e8) = mem.alloc[f64](a, p * p)
    let (rhs, e9) = mem.alloc[f64](a, p)
    let (s2v, e10) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret e1 }
    var i = 0usize
    while i < n {
        let start = mem.mark(a)
        let (xtx, f1) = mem.alloc[f64](a, p * p)
        let (xty, f2) = mem.alloc[f64](a, p)
        if f1 != ok || f2 != ok { ret f1 }
        var r = 0usize
        while r < p * p {
            xtx[r] = 0.0f64
            r += 1usize
        }
        r = 0usize
        while r < p {
            xty[r] = 0.0f64
            r += 1usize
        }
        var k = 0usize
        while k < t {
            let w = weights[i * t + k]
            var c1 = 0usize
            while c1 < p {
                xty[c1] += w * xreg[k * p + c1] * ratios[i * t + k]
                var c2 = 0usize
                while c2 < p {
                    xtx[c1 * p + c2] += w * xreg[k * p + c1] * xreg[k * p + c2]
                    c2 += 1usize
                }
                c1 += 1usize
            }
            k += 1usize
        }
        let (inv, f3) = mem.alloc[f64](a, p * p)
        if f3 != ok { ret f3 }
        if !small_inverse(a, xtx, p, inv) { ret mem.Full }
        r = 0usize
        while r < p {
            var v = 0.0f64
            var c = 0usize
            while c < p {
                v += inv[r * p + c] * xty[c]
                wi[i * p * p + r * p + c] = inv[r * p + c]
                c += 1usize
            }
            beta[i * p + r] = v
            r += 1usize
        }
        var sse = 0.0f64
        k = 0usize
        while k < t {
            var fit = 0.0f64
            var c = 0usize
            while c < p {
                fit += xreg[k * p + c] * beta[i * p + c]
                c += 1usize
            }
            let res = ratios[i * t + k] - fit
            sse += weights[i * t + k] * res * res
            k += 1usize
        }
        s2v[i] = sse / f64(t - p)
        mem.reset(a, start)
        i += 1usize
    }
    var s2 = 0.0f64
    i = 0usize
    while i < n {
        s2 += s2v[i]
        i += 1usize
    }
    s2 = s2 / f64(n)
    var r = 0usize
    while r < n * p * p {
        cred[r] = 0.0f64
        r += 1usize
    }
    i = 0usize
    while i < n {
        r = 0usize
        while r < p {
            cred[i * p * p + r * p + r] = 1.0f64
            r += 1usize
        }
        i += 1usize
    }
    r = 0usize
    while r < p {
        var v = 0.0f64
        i = 0usize
        while i < n {
            v += beta[i * p + r]
            i += 1usize
        }
        coll[r] = v / f64(n)
        r += 1usize
    }
    var count = 0usize
    var iters = 0usize
    while true {
        r = 0usize
        while r < p {
            coll1[r] = coll[r]
            r += 1usize
        }
        count += 1usize
        if maxit < count { break }
        hache_a(cred, beta, coll, n, p, am, tmp)
        let hc1 = hache_cred(a, am, wi, s2, n, p, cred, crs)
        if hc1 != ok { ret hc1 }
        r = 0usize
        while r < p {
            var v = 0.0f64
            i = 0usize
            while i < n {
                var c = 0usize
                while c < p {
                    v += cred[i * p * p + r * p + c] * beta[i * p + c]
                    c += 1usize
                }
                i += 1usize
            }
            rhs[r] = v
            r += 1usize
        }
        let (ci, ce) = mem.alloc[f64](a, p * p)
        if ce != ok { ret ce }
        if !small_inverse(a, crs, p, ci) { ret mem.Full }
        r = 0usize
        while r < p {
            var v = 0.0f64
            var c = 0usize
            while c < p {
                v += ci[r * p + c] * rhs[c]
                c += 1usize
            }
            coll[r] = v
            r += 1usize
        }
        var mx = 0.0f64
        r = 0usize
        while r < p {
            let d = math.abs[f64]((coll[r] - coll1[r]) / coll1[r])
            if d > mx { mx = d }
            r += 1usize
        }
        iters = count
        if mx < tol { break }
    }
    hache_a(cred, beta, coll, n, p, am, tmp)
    let hc2 = hache_cred(a, am, wi, s2, n, p, cred, tmp)
    if hc2 != ok { ret hc2 }
    r = 0usize
    while r < p {
        out[r] = coll[r]
        r += 1usize
    }
    r = 0usize
    while r < p * p {
        out[p + r] = am[r]
        out[p + p * p + 1usize + r] = crs[r]
        r += 1usize
    }
    out[p + p * p] = s2
    out[p + 2usize * p * p + 1usize] = f64(iters)
    ret ok
}

// A = sum_i cred_i (beta_i - coll)(beta_i - coll)' / (n - 1), symmetrised
fn hache_a(cred: []const f64, beta: []const f64, coll: []const f64, n: usize, p: usize, am: []f64, tmp: []f64) {
    var r = 0usize
    while r < p * p {
        tmp[r] = 0.0f64
        r += 1usize
    }
    var i = 0usize
    while i < n {
        var c1 = 0usize
        while c1 < p {
            var c2 = 0usize
            while c2 < p {
                let outer = (beta[i * p + c1] - coll[c1]) * (beta[i * p + c2] - coll[c2])
                var k = 0usize
                var v = 0.0f64
                while k < p {
                    v += cred[i * p * p + c1 * p + k] * (beta[i * p + k] - coll[k]) * (beta[i * p + c2] - coll[c2])
                    k += 1usize
                }
                let _ = outer
                tmp[c1 * p + c2] += v
                c2 += 1usize
            }
            c1 += 1usize
        }
        i += 1usize
    }
    var c1 = 0usize
    while c1 < p {
        var c2 = 0usize
        while c2 < p {
            am[c1 * p + c2] = (tmp[c1 * p + c2] + tmp[c2 * p + c1]) / (2.0f64 * f64(n - 1usize))
            c2 += 1usize
        }
        c1 += 1usize
    }
}

// cred_i = A (A + s2 W_i)^-1 for every contract and their sum into crs
fn hache_cred(a: *mem.Arena, am: []const f64, wi: []const f64, s2: f64, n: usize, p: usize, cred: []f64, crs: []f64) -> err {
    var r = 0usize
    while r < p * p {
        crs[r] = 0.0f64
        r += 1usize
    }
    var i = 0usize
    while i < n {
        let start = mem.mark(a)
        let (m1, f1) = mem.alloc[f64](a, p * p)
        if f1 != ok { ret f1 }
        r = 0usize
        while r < p * p {
            m1[r] = am[r] + s2 * wi[i * p * p + r]
            r += 1usize
        }
        let (inv, ie) = mem.alloc[f64](a, p * p)
        if ie != ok { ret ie }
        if !small_inverse(a, m1, p, inv) { ret mem.Full }
        var c1 = 0usize
        while c1 < p {
            var c2 = 0usize
            while c2 < p {
                var v = 0.0f64
                var k = 0usize
                while k < p {
                    v += am[c1 * p + k] * inv[k * p + c2]
                    k += 1usize
                }
                cred[i * p * p + c1 * p + c2] = v
                crs[c1 * p + c2] += v
                c2 += 1usize
            }
            c1 += 1usize
        }
        mem.reset(a, start)
        i += 1usize
    }
    ret ok
}

// the inverse of the p by p matrix m (row-major) by Gauss-Jordan with partial pivoting in double precision; false when singular
fn small_inverse(a: *mem.Arena, m: []const f64, p: usize, out: []f64) -> bool {
    let start = mem.mark(a)
    let (w, e) = mem.alloc[f64](a, p * 2usize * p)
    if e != ok { ret false }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            w[i * 2usize * p + j] = m[i * p + j]
            if i == j { w[i * 2usize * p + p + j] = 1.0f64 } else { w[i * 2usize * p + p + j] = 0.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    var col = 0usize
    while col < p {
        var piv = col
        var best = math.abs[f64](w[col * 2usize * p + col])
        var r = col + 1usize
        while r < p {
            let v = math.abs[f64](w[r * 2usize * p + col])
            if v > best {
                best = v
                piv = r
            }
            r += 1usize
        }
        if best < 1.0e-300f64 {
            mem.reset(a, start)
            ret false
        }
        if piv != col {
            var k = 0usize
            while k < 2usize * p {
                let tmp = w[col * 2usize * p + k]
                w[col * 2usize * p + k] = w[piv * 2usize * p + k]
                w[piv * 2usize * p + k] = tmp
                k += 1usize
            }
        }
        let d = w[col * 2usize * p + col]
        var k = 0usize
        while k < 2usize * p {
            w[col * 2usize * p + k] = w[col * 2usize * p + k] / d
            k += 1usize
        }
        r = 0usize
        while r < p {
            if r != col {
                let f = w[r * 2usize * p + col]
                k = 0usize
                while k < 2usize * p {
                    w[r * 2usize * p + k] = w[r * 2usize * p + k] - f * w[col * 2usize * p + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            out[i * p + j] = w[i * 2usize * p + p + j]
            j += 1usize
        }
        i += 1usize
    }
    mem.reset(a, start)
    ret true
}

// sums of vals over the groups grp (0-based) into out (ng entries)
fn hier_tsum(vals: []const f64, grp: []const usize, ng: usize, out: []f64) {
    var g = 0usize
    while g < ng {
        out[g] = 0.0f64
        g += 1usize
    }
    var i = 0usize
    while i < vals.len {
        out[grp[i]] += vals[i]
        i += 1usize
    }
}

fn offp_of(clen: []const usize, lv: usize) -> usize {
    var s = 0usize
    var i = 0usize
    while i < lv {
        s += clen[i]
        i += 1usize
    }
    ret s
}

// actuar cm() hierarchical model, methods Buhlmann-Gisler (meth 0) and Ohlsson (meth 1): nr rows (the contracts) of nt periods, ratios and weights row-major with NaN for a missing weight
// in the same cells as the missing ratios; par maps level i + 1 nodes to level i nodes (the last map takes the rows to the level nl nodes), parlen[i] the length of map i, 0-based; nn[i] the
// number of nodes of level i. out gets b (nl entries then the within variance), then the credibility factors of each level (one per child), then the weighted means of the levels and the rows.
fn cm_hierarchical(a: *mem.Arena, nl: usize, nr: usize, nt: usize, meth: usize, ratios: []const f64, weights: []const f64, par: []const usize, parlen: []const usize, nn: []const usize, out: []f64) -> err {
    let (ws, e0) = mem.alloc[f64](a, nr)
    let (rw, e1) = mem.alloc[f64](a, nr)
    if e0 != ok || e1 != ok { ret e0 }
    var cells = 0usize
    var r = 0usize
    while r < nr {
        var sw = 0.0f64
        var sx = 0.0f64
        var t = 0usize
        while t < nt {
            let w = weights[r * nt + t]
            if w == w {
                sw += w
                sx += w * ratios[r * nt + t]
                cells += 1usize
            }
            t += 1usize
        }
        ws[r] = sw
        rw[r] = 0.0f64
        if sw > 0.0f64 { rw[r] = sx / sw }
        r += 1usize
    }
    var total = 0usize
    var lv = 0usize
    while lv < nl {
        total += nn[lv]
        lv += 1usize
    }
    let (eff, e2) = mem.alloc[f64](a, total + 1usize)
    let (offs, e3) = mem.alloc[usize](a, nl + 1usize)
    let (pofs, e3b) = mem.alloc[usize](a, nl + 1usize)
    if e2 != ok || e3 != ok || e3b != ok { ret e2 }
    var o = 0usize
    var offp = 0usize
    lv = 0usize
    while lv < nl {
        offs[lv] = o
        o += nn[lv]
        pofs[lv] = offp
        offp += parlen[lv]
        lv += 1usize
    }
    let (wcur, e4) = mem.alloc[f64](a, nr + 1usize)
    let (wnext, e5) = mem.alloc[f64](a, nr + 1usize)
    if e4 != ok || e5 != ok { ret e4 }
    r = 0usize
    while r < nr {
        wcur[r] = ws[r]
        r += 1usize
    }
    var curlen = nr
    lv = nl
    while lv > 0usize {
        lv -= 1usize
        var g = 0usize
        while g < nn[lv] {
            eff[offs[lv] + g] = 0.0f64
            g += 1usize
        }
        var c = 0usize
        while c < curlen {
            if wcur[c] > 0.0f64 { eff[offs[lv] + par[pofs[lv] + c]] += 1.0f64 }
            c += 1usize
        }
        hier_tsum(wcur[0usize..curlen], par[pofs[lv]..pofs[lv] + curlen], nn[lv], wnext[0usize..nn[lv]])
        curlen = nn[lv]
        c = 0usize
        while c < curlen {
            wcur[c] = wnext[c]
            c += 1usize
        }
    }
    var sumeff_last = 0.0f64
    var g0 = 0usize
    while g0 < nn[nl - 1usize] {
        sumeff_last += eff[offs[nl - 1usize] + g0]
        g0 += 1usize
    }
    var s2n = 0.0f64
    r = 0usize
    while r < nr {
        var t = 0usize
        while t < nt {
            let w = weights[r * nt + t]
            if w == w {
                let dlt = ratios[r * nt + t] - rw[r]
                s2n += w * dlt * dlt
            }
            t += 1usize
        }
        r += 1usize
    }
    let s2 = s2n / (f64(cells) - sumeff_last)
    var b: [17]f64 = zero
    b[nl] = s2
    let (tw, e6) = mem.alloc[f64](a, total + nr)
    let (wm, e7) = mem.alloc[f64](a, total + nr)
    let (cr, e8) = mem.alloc[f64](a, total + nr)
    let (tmp1, e9) = mem.alloc[f64](a, total + nr)
    let (tmp2, e10) = mem.alloc[f64](a, total + nr)
    let (bi, e11) = mem.alloc[f64](a, total + nr)
    let (ci, e12) = mem.alloc[f64](a, total + nr)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret e6 }
    r = 0usize
    while r < nr {
        tw[total + r] = ws[r]
        wm[total + r] = rw[r]
        r += 1usize
    }
    lv = nl
    while lv > 0usize {
        lv -= 1usize
        let ng = nn[lv]
        let cl = parlen[lv]
        let tl = offs[lv]
        var cb = total
        if lv + 1usize < nl { cb = offs[lv + 1usize] }
        let pg = par[pofs[lv]..pofs[lv] + cl]
        var c = 0usize
        hier_tsum(tw[cb..cb + cl], pg, ng, tw[tl..tl + ng])
        c = 0usize
        while c < cl {
            tmp1[c] = tw[cb + c] * wm[cb + c]
            c += 1usize
        }
        hier_tsum(tmp1[0usize..cl], pg, ng, tmp2[0usize..ng])
        var g = 0usize
        while g < ng {
            wm[tl + g] = 0.0f64
            if tw[tl + g] > 0.0f64 { wm[tl + g] = tmp2[g] / tw[tl + g] }
            g += 1usize
        }
        var between = 0.0f64
        var bj = 0usize
        while bj <= nl {
            if b[bj] != 0.0f64 {
                between = b[bj]
                break
            }
            bj += 1usize
        }
        c = 0usize
        while c < cl {
            let dm = wm[cb + c] - wm[tl + pg[c]]
            tmp1[c] = tw[cb + c] * dm * dm
            c += 1usize
        }
        hier_tsum(tmp1[0usize..cl], pg, ng, bi[0usize..ng])
        c = 0usize
        while c < cl {
            tmp1[c] = tw[cb + c] * tw[cb + c]
            c += 1usize
        }
        hier_tsum(tmp1[0usize..cl], pg, ng, ci[0usize..ng])
        g = 0usize
        var sb = 0.0f64
        var sc = 0.0f64
        var mean_b = 0.0f64
        while g < ng {
            let bgv = bi[g] - (eff[tl + g] - 1.0f64) * between
            let cgv = tw[tl + g] - ci[g] / tw[tl + g]
            sb += bgv
            sc += cgv
            var q = 0.0f64
            if cgv != 0.0f64 { q = bgv / cgv }
            if q < 0.0f64 { q = 0.0f64 }
            mean_b += q
            g += 1usize
        }
        if meth == 0usize { b[lv] = mean_b / f64(ng) } else { b[lv] = sb / sc }
        let co = offp_of(parlen, lv)
        if b[lv] != 0.0f64 {
            c = 0usize
            while c < cl {
                cr[co + c] = 1.0f64 / (1.0f64 + between / (b[lv] * tw[cb + c]))
                tmp1[c] = cr[co + c]
                c += 1usize
            }
            hier_tsum(tmp1[0usize..cl], pg, ng, tw[tl..tl + ng])
            c = 0usize
            while c < cl {
                tmp1[c] = cr[co + c] * wm[cb + c]
                c += 1usize
            }
            hier_tsum(tmp1[0usize..cl], pg, ng, tmp2[0usize..ng])
            g = 0usize
            while g < ng {
                wm[tl + g] = 0.0f64
                if tw[tl + g] > 0.0f64 { wm[tl + g] = tmp2[g] / tw[tl + g] }
                g += 1usize
            }
        } else {
            c = 0usize
            while c < cl {
                cr[co + c] = 0.0f64
                c += 1usize
            }
        }
    }
    if meth == 2usize {
        // iterative estimators (hierarc.c): the Ohlsson estimators above are the starting values; denominators den[i] = (effective nodes below level i) - (effective nodes of level i - 1)
        var den: [17]f64 = zero
        var prev = 1.0f64
        lv = 0usize
        while lv < nl {
            var sg = 0.0f64
            var gq = 0usize
            while gq < nn[lv] {
                sg += eff[offs[lv] + gq]
                gq += 1usize
            }
            den[lv] = sg - prev
            prev = sg
            lv += 1usize
        }
        var bt: [17]f64 = zero
        var anyp = false
        lv = 0usize
        while lv < nl {
            if b[lv] < 0.0f64 { b[lv] = 0.0f64 }
            if b[lv] > 0.0f64 { anyp = true }
            lv += 1usize
        }
        if b[nl] < 0.0f64 { b[nl] = 0.0f64 }
        let tol = 1.4901161193847656e-8f64
        var count = 0usize
        var diff = 1.0f64
        while anyp && diff >= tol {
            count += 1usize
            if count > 100usize { break }
            lv = 0usize
            while lv < nl {
                bt[lv] = b[lv]
                lv += 1usize
            }
            lv = nl
            while lv > 0usize {
                lv -= 1usize
                let ng = nn[lv]
                let cl = parlen[lv]
                let tl = offs[lv]
                var cb = total
                if lv + 1usize < nl { cb = offs[lv + 1usize] }
                let pg = par[pofs[lv]..pofs[lv] + cl]
                let co = offp_of(parlen, lv)
                var jj = 1usize
                while b[lv + jj] == 0.0f64 { jj += 1usize }
                let bw = b[lv + jj]
                var pass = 0usize
                while pass < 2usize {
                    var g = 0usize
                    while g < ng {
                        tw[tl + g] = 0.0f64
                        wm[tl + g] = 0.0f64
                        g += 1usize
                    }
                    var c = 0usize
                    while c < cl {
                        cr[co + c] = 1.0f64 / (1.0f64 + bw / (b[lv] * tw[cb + c]))
                        var wgt = cr[co + c]
                        if wgt == 0.0f64 { wgt = tw[cb + c] }
                        tw[tl + pg[c]] += wgt
                        wm[tl + pg[c]] += wgt * wm[cb + c]
                        c += 1usize
                    }
                    g = 0usize
                    while g < ng {
                        if tw[tl + g] > 0.0f64 { wm[tl + g] = wm[tl + g] / tw[tl + g] } else { wm[tl + g] = 0.0f64 }
                        g += 1usize
                    }
                    if pass == 0usize && bt[lv] > 0.0f64 {
                        var nbv = 0.0f64
                        c = 0usize
                        while c < cl {
                            var wgt = cr[co + c]
                            if wgt == 0.0f64 { wgt = tw[cb + c] }
                            let dm = wm[cb + c] - wm[tl + pg[c]]
                            nbv += wgt * dm * dm
                            c += 1usize
                        }
                        nbv = nbv / den[lv]
                        if nbv <= tol * tol { nbv = 0.0f64 }
                        b[lv] = nbv
                    }
                    pass += 1usize
                }
            }
            diff = 0.0f64
            lv = 0usize
            while lv < nl {
                if b[lv] > 0.0f64 {
                    let dd = math.abs[f64](b[lv] - bt[lv]) / bt[lv]
                    if dd > diff { diff = dd }
                }
                lv += 1usize
            }
        }
    }
    var k = 0usize
    while k <= nl {
        out[k] = b[k]
        k += 1usize
    }
    var oo = nl + 1usize
    lv = 0usize
    while lv < nl {
        var c = 0usize
        while c < parlen[lv] {
            out[oo] = cr[offp_of(parlen, lv) + c]
            oo += 1usize
            c += 1usize
        }
        lv += 1usize
    }
    lv = 0usize
    while lv < nl {
        var g = 0usize
        while g < nn[lv] {
            out[oo] = wm[offs[lv] + g]
            oo += 1usize
            g += 1usize
        }
        lv += 1usize
    }
    r = 0usize
    while r < nr {
        out[oo] = wm[total + r]
        oo += 1usize
        r += 1usize
    }
    ret ok
}

// ---- ruin() with phase-type waiting times, and adjCoef (the Cramer-Lundberg adjustment coefficient)

// actuar ruin(claims phase-type (probc, tc: n x n), wait phase-type (probw, tw: m x m)) at premium rate c: the fixed point Q <- T - t0pi A (Q (x) I + B)^(-1) C from Q = T until
// max row sum of |Q - Q1| < tol or maxit passes, then pi = colSums(Q - T) / (-sum(T) c); psi(u) = pi exp(Q u) 1
fn ruin_ph_ph(a: *mem.Arena, probc: []const f64, tc: []const f64, n: usize, probw: []const f64, tw: []const f64, m: usize, u: f64, c: f64) -> f64 {
    let nm_ = n * m
    let (q, e1) = mem.alloc[f64](a, n * n)
    let (q1, e2) = mem.alloc[f64](a, n * n)
    let (kk, e3) = mem.alloc[f64](a, nm_ * nm_)
    let (st, e4) = mem.alloc[f64](a, nm_ * n)
    let (pi, e5) = mem.alloc[f64](a, n)
    let (rsw, e6) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret nan() }
    var i = 0usize
    var j = 0usize
    var s = 0usize
    var r = 0usize
    while i < m {
        rsw[i] = rowsum(tw, m, i)
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        q[i] = tc[i]
        i += 1usize
    }
    var count = 0usize
    var done = false
    while !done {
        count += 1usize
        if count > 200usize { break }
        i = 0usize
        while i < n * n {
            q1[i] = q[i]
            i += 1usize
        }
        // K = Q (x) I_m + I_n (x) Tw, indices (i m + s, j m + r)
        i = 0usize
        while i < n {
            s = 0usize
            while s < m {
                j = 0usize
                while j < n {
                    r = 0usize
                    while r < m {
                        var v = 0.0f64
                        if s == r { v += q[i * n + j] }
                        if i == j { v += tw[s * m + r] }
                        kk[(i * m + s) * nm_ + j * m + r] = v
                        r += 1usize
                    }
                    j += 1usize
                }
                s += 1usize
            }
            i += 1usize
        }
        let (kin, ek) = gp.invert(a, kk, nm_)
        if ek != ok { ret nan() }
        // S = K^(-1) C with C[(i m + s), j] = delta_ij (-rsw[s]); then Q = T - t0pi A S with (t0pi A)[i, (j m + r)] = (-rowsum(T)_i probc_j) probw_r
        i = 0usize
        while i < nm_ {
            j = 0usize
            while j < n {
                var v = 0.0f64
                s = 0usize
                while s < m {
                    v += kin[i * nm_ + j * m + s] * (0.0f64 - rsw[s])
                    s += 1usize
                }
                st[i * n + j] = v
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            j = 0usize
            while j < n {
                var v = 0.0f64
                var k2 = 0usize
                while k2 < n {
                    r = 0usize
                    while r < m {
                        v += (0.0f64 - rowsum(tc, n, i)) * probc[k2] * probw[r] * st[(k2 * m + r) * n + j]
                        r += 1usize
                    }
                    k2 += 1usize
                }
                q[i * n + j] = tc[i * n + j] - v
                j += 1usize
            }
            i += 1usize
        }
        var mx = 0.0f64
        i = 0usize
        while i < n {
            var rs = 0.0f64
            j = 0usize
            while j < n {
                rs += math.abs[f64](q[i * n + j] - q1[i * n + j])
                j += 1usize
            }
            if rs > mx { mx = rs }
            i += 1usize
        }
        if mx < 1.4901161193847656e-8f64 { done = true }
    }
    var tot = 0.0f64
    i = 0usize
    while i < n * n {
        tot += tc[i]
        i += 1usize
    }
    j = 0usize
    while j < n {
        var cs = 0.0f64
        i = 0usize
        while i < n {
            cs += q[i * n + j] - tc[i * n + j]
            i += 1usize
        }
        pi[j] = cs / (0.0f64 - tot * c)
        j += 1usize
    }
    let (d0, sf) = ph_dens_surv(a, pi, q, n, u)
    ret sf
}

// the moment generating functions of actuar: kind 0 exponential (rate p1), 1 gamma (shape p1, rate p2), 2 uniform (min p1, max p2), 3 normal (mean p1, sd p2)
fn mgf_k(kind: usize, t: f64, p1: f64, p2: f64) -> f64 {
    if kind == 0usize {
        if t >= p1 { ret nan() }
        ret 1.0f64 / (1.0f64 - (1.0f64 / p1) * t)
    }
    if kind == 1usize {
        if t >= p2 { ret nan() }
        ret math.pow[f64](1.0f64 - (1.0f64 / p2) * t, 0.0f64 - p1)
    }
    if kind == 2usize {
        if t == 0.0f64 { ret 1.0f64 }
        ret (math.exp[f64](t * p2) - math.exp[f64](t * p1)) / (t * (p2 - p1))
    }
    ret math.exp[f64](t * p1 + t * t * p2 * p2 / 2.0f64)
}

type AdjCtx = struct {
    mode: usize,
    ck: usize,
    c1: f64,
    c2: f64,
    wk: usize,
    w1: f64,
    w2: f64,
    pa: f64,
    pb: f64,
    y: f64
}

// (h(r) - 1)^2 with h(r) = mgf.claim(r) mgf.wait(-r c): mode 0 no reinsurance (premium rate pa), 1 proportional (the claim is y X, X exponential rate c1) and 2 excess-of-loss
// (the claim is min(X, y)), both with premium rate pa + pb y
fn adj_f(c: *AdjCtx, r: f64) -> f64 {
    var mx = 0.0f64
    var prem = c.pa
    if c.mode == 0usize { mx = mgf_k(c.ck, r, c.c1, c.c2) }
    if c.mode == 1usize {
        mx = mgf_k(0usize, r * c.y, c.c1, 0.0f64)
        prem = c.pa + c.pb * c.y
    }
    if c.mode == 2usize {
        let b = c.c1
        let e = math.exp[f64](0.0f64 - (b - r) * c.y)
        mx = b * (1.0f64 - e) / (b - r) + e
        prem = c.pa + c.pb * c.y
    }
    let h = mx * mgf_k(c.wk, 0.0f64 - r * prem, c.w1, c.w2)
    ret (h - 1.0f64) * (h - 1.0f64)
}

fn adj_coef(c: *AdjCtx, upper: f64) -> f64 {
    ret fcast.brent_fmin[AdjCtx](c, adj_f, 0.0f64, upper - 2.220446049250313e-16f64, 1.4901161193847656e-8f64)
}

// adjCoef(..., reinsurance, from, to, n)(v): the coefficient on the grid seq(from, to, length.out = n) joined by approxfun(rule = 2)
fn adj_coef_re(a: *mem.Arena, c: *AdjCtx, upper: f64, from: f64, to: f64, n: usize, v: f64) -> f64 {
    let (co, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret nan() }
    let by = (to - from) / f64(n - 1usize)
    var i = 0usize
    while i < n {
        c.y = from + f64(i) * by
        co[i] = adj_coef(c, upper)
        i += 1usize
    }
    if v <= from { ret co[0usize] }
    if v >= to { ret co[n - 1usize] }
    var lo = 0usize
    var hi = n - 1usize
    while lo + 1usize < hi {
        let mid = (lo + hi) / 2usize
        if v < from + f64(mid) * by { hi = mid } else { lo = mid }
    }
    let xl = from + f64(lo) * by
    let xh = from + f64(hi) * by
    if v == xh { ret co[hi] }
    if v == xl { ret co[lo] }
    ret co[lo] + (co[hi] - co[lo]) * ((v - xl) / (xh - xl))
}

// ---- the shifted transformed beta laws: Pareto II (a = shape, g = t = 1), Pareto III (a = t = 1, g = shape), Pareto IV (a = shape1, g = shape2, t = 1) and Feller-Pareto
// (a = shape1, g = shape2, t = shape3); X = min + Y with Y transformed beta(a, g, t, th)

fn sh_d(x: f64, mn: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    if x < mn { ret 0.0f64 }
    if x == mn {
        if g * t < 1.0f64 { ret 1.0f64 / 0.0f64 }
        if g * t > 1.0f64 { ret 0.0f64 }
        ret g / (th * math.exp[f64](lgam(t) + lgam(a) - lgam(a + t)))
    }
    ret tb_d(x - mn, a, g, t, th)
}

fn sh_p(x: f64, mn: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    if x <= mn { ret 0.0f64 }
    ret tb_p(x - mn, a, g, t, th)
}

fn sh_q(p: f64, mn: f64, a: f64, g: f64, t: f64, th: f64) -> f64 { ret mn + tb_q(p, a, g, t, th) }

fn choose_i(k: usize, i: usize) -> f64 {
    var r = 1.0f64
    var j = 1usize
    while j <= i {
        r = r * f64(k - i + j) / f64(j)
        j += 1usize
    }
    ret r
}

// min = 0 keeps the whole range of orders of the unshifted law; otherwise the order is a non-negative integer below a g
fn sh_m(k: f64, mn: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    if mn == 0.0f64 { ret tb_m(k, a, g, t, th) }
    if k < 0.0f64 { ret nan() }
    if k >= a * g { ret 1.0f64 / 0.0f64 }
    let kk = usize(k + 0.5f64)
    var s = 0.0f64
    var i = 0usize
    while i <= kk {
        var m = 1.0f64
        if i > 0usize { m = tb_m(f64(i), a, g, t, th) }
        s += choose_i(kk, i) * math.pow[f64](mn, f64(kk - i)) * m
        i += 1usize
    }
    ret s
}

fn sh_lev(x: f64, k: f64, mn: f64, a: f64, g: f64, t: f64, th: f64) -> f64 {
    if x <= mn { ret 0.0f64 }
    if mn == 0.0f64 { ret tb_lev(x, k, a, g, t, th) }
    if k < 0.0f64 { ret nan() }
    let kk = usize(k + 0.5f64)
    var s = 0.0f64
    var i = 0usize
    while i <= kk {
        var m = 1.0f64
        if i > 0usize { m = tb_lev(x - mn, f64(i), a, g, t, th) }
        s += choose_i(kk, i) * math.pow[f64](mn, f64(kk - i)) * m
        i += 1usize
    }
    ret s
}

// the raw moment (stat 0), limited expected value (stat 1, limit v) and moment generating function (stat 2, argument v) of the base laws of actuar: kind 0 lognormal (meanlog p1, sdlog p2),
// 1 beta (p1, p2), 2 uniform (min p1, max p2), 3 normal (mean p1, sd p2; integer order), 4 exponential (rate p1), 5 gamma (shape p1, rate p2), 6 Weibull (shape p1, scale p2),
// 7 chi-square (df p1), 8 inverse Gaussian (mean p1, shape p2; mgf only)
fn bm(stat: usize, kind: usize, p1: f64, p2: f64, v: f64, k: f64) -> f64 {
    if stat == 2usize {
        if kind == 7usize { ret math.exp[f64](0.0f64 - p1 / 2.0f64 * dsa.log1p(0.0f64 - 2.0f64 * v)) }
        if kind == 8usize {
            let phi = 1.0f64 / p2
            let phm = phi * p1
            let tm = v * p1
            ret math.exp[f64]((1.0f64 - math.sqrt[f64](1.0f64 - 2.0f64 * phm * tm)) / phm)
        }
        if kind == 4usize { ret mgf_k(0usize, v, p1, 0.0f64) }
        if kind == 5usize { ret mgf_k(1usize, v, p1, p2) }
        ret mgf_k(kind, v, p1, p2)
    }
    if kind == 0usize {
        let mm = math.exp[f64](k * p1 + k * k * p2 * p2 / 2.0f64)
        if stat == 0usize { ret mm }
        if v <= 0.0f64 { ret 0.0f64 }
        let lx = math.log[f64](v)
        ret mm * dsa.pnorm((lx - p1 - k * p2 * p2) / p2, 0.0f64, 1.0f64, true, false) + math.pow[f64](v, k) * dsa.pnorm((lx - p1) / p2, 0.0f64, 1.0f64, false, false)
    }
    if kind == 1usize {
        let mm = math.exp[f64](nb.lbeta(p1 + k, p2) - nb.lbeta(p1, p2))
        if stat == 0usize { ret mm }
        if v <= 0.0f64 { ret 0.0f64 }
        ret mm * nb.pbeta(v, p1 + k, p2, true, false) + math.pow[f64](v, k) * nb.pbeta(v, p1, p2, false, false)
    }
    if kind == 2usize {
        let mm = (math.pow[f64](p2, k + 1.0f64) - math.pow[f64](p1, k + 1.0f64)) / ((k + 1.0f64) * (p2 - p1))
        if stat == 0usize { ret mm }
        if v <= p1 { ret 0.0f64 }
        if v >= p2 { ret mm }
        ret (math.pow[f64](v, k + 1.0f64) - math.pow[f64](p1, k + 1.0f64)) / ((k + 1.0f64) * (p2 - p1)) + math.pow[f64](v, k) * (p2 - v) / (p2 - p1)
    }
    if kind == 3usize {
        let n = usize(k + 0.5f64)
        if n == 0usize { ret 1.0f64 }
        var r = 0.0f64
        var i = 0usize
        while i <= n / 2usize {
            r += math.pow[f64](p2, f64(2usize * i)) * math.pow[f64](p1, f64(n - 2usize * i)) / (math.pow[f64](2.0f64, f64(i)) * math.exp[f64](lgam(f64(i) + 1.0f64)) * math.exp[f64](lgam(k - 2.0f64 * f64(i) + 1.0f64)))
            i += 1usize
        }
        ret math.exp[f64](lgam(k + 1.0f64)) * r
    }
    var a = 1.0f64
    var t = 1.0f64
    var th = 1.0f64 / p1
    if kind == 5usize {
        a = p1
        th = 1.0f64 / p2
    }
    if kind == 6usize {
        t = p1
        th = p2
    }
    if kind == 7usize {
        a = p1 / 2.0f64
        th = 2.0f64
    }
    if stat == 0usize { ret tg_m(k, a, t, th) }
    ret tg_lev(v, k, a, t, th)
}

// mgfphtype: 1 - pi (e + (x I + T)^(-1) t) with t = -T e
fn ph_mgf(a: *mem.Arena, prob: []const f64, tm: []const f64, m: usize, x: f64) -> f64 {
    if x == 0.0f64 { ret 1.0f64 }
    let (w, e1) = mem.alloc[f64](a, m * m)
    if e1 != ok { ret nan() }
    var i = 0usize
    while i < m * m {
        w[i] = tm[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        w[i * m + i] += x
        i += 1usize
    }
    let (inv, e2) = gp.invert(a, w, m)
    if e2 != ok { ret nan() }
    var z = 0.0f64
    i = 0usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            s += inv[i * m + j] * (0.0f64 - rowsum(tm, m, j))
            j += 1usize
        }
        z += prob[i] * (1.0f64 + s)
        i += 1usize
    }
    ret 1.0f64 - z
}

// actuar bvar.unbiased and bvar.iterative: the between-contract variance of the values x with weights w, within variance, n contracts
fn bvar_unb(x: []const f64, w: []const f64, within: f64, n: usize) -> f64 {
    var ws = 0.0f64
    var w2 = 0.0f64
    var sx = 0.0f64
    var i = 0usize
    while i < x.len {
        ws += w[i]
        w2 += w[i] * w[i]
        sx += w[i] * x[i]
        i += 1usize
    }
    let xw = sx / ws
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        ss += w[i] * (x[i] - xw) * (x[i] - xw)
        i += 1usize
    }
    ret ws * (ss - f64(n - 1usize) * within) / (ws * ws - w2)
}

fn bvar_iter(x: []const f64, w: []const f64, within: f64, n: usize, start: f64) -> f64 {
    var a = start
    var count = 0usize
    while true {
        let a1 = a
        count += 1usize
        if count > 100usize { break }
        var sz = 0.0f64
        var szx = 0.0f64
        var i = 0usize
        while i < x.len {
            let z = 1.0f64 / (1.0f64 + within / (w[i] * a))
            sz += z
            szx += z * x[i]
            i += 1usize
        }
        let xz = szx / sz
        var ss = 0.0f64
        i = 0usize
        while i < x.len {
            let z = 1.0f64 / (1.0f64 + within / (w[i] * a))
            ss += z * (x[i] - xz) * (x[i] - xz)
            i += 1usize
        }
        a = ss / f64(n - 1usize)
        if math.abs[f64]((a - a1) / a1) < 1.4901161193847656e-8f64 { break }
    }
    ret a
}

// actuar cm() with method = "iterative" and no hierarchy (bstraub): ns[i] the years of contract i, x and w contract by contract; out = (within variance, between variance, collective mean, credibility factor of contract 0)
fn cm_bs_iter(a: *mem.Arena, ns: []const usize, x: []const f64, w: []const f64, out: []f64) -> err {
    let ni = ns.len
    let (rw, e1) = mem.alloc[f64](a, ni)
    let (wsv, e2) = mem.alloc[f64](a, ni)
    if e1 != ok || e2 != ok { ret e1 }
    var pos = 0usize
    var cells = 0usize
    var s2n = 0.0f64
    var wmin = 1.0e300f64
    var wmax = 0.0f64 - 1.0e300f64
    var i = 0usize
    while i < ni {
        var sw = 0.0f64
        var sx = 0.0f64
        var j = 0usize
        while j < ns[i] {
            sw += w[pos + j]
            sx += w[pos + j] * x[pos + j]
            if w[pos + j] < wmin { wmin = w[pos + j] }
            if w[pos + j] > wmax { wmax = w[pos + j] }
            j += 1usize
        }
        wsv[i] = sw
        rw[i] = sx / sw
        j = 0usize
        while j < ns[i] {
            s2n += w[pos + j] * (x[pos + j] - rw[i]) * (x[pos + j] - rw[i])
            j += 1usize
        }
        cells += ns[i]
        pos += ns[i]
        i += 1usize
    }
    let s2 = s2n / f64(cells - ni)
    var av = bvar_unb(rw, wsv, s2, ni)
    if wmax - wmin > 1.4901161193847656e-8f64 {
        if av > 0.0f64 { av = bvar_iter(rw, wsv, s2, ni, av) } else { av = 0.0f64 }
    }
    var sc = 0.0f64
    var scx = 0.0f64
    var c0 = 0.0f64
    i = 0usize
    while i < ni {
        var z = 0.0f64
        if av > 0.0f64 { z = 1.0f64 / (1.0f64 + s2 / (wsv[i] * av)) }
        if i == 0usize { c0 = z }
        sc += z
        scx += z * rw[i]
        i += 1usize
    }
    out[0usize] = s2
    out[1usize] = av
    out[2usize] = scx / sc
    out[3usize] = c0
    ret ok
}

// actuar hache.barycenter (cm with regformula and adj.intercept = TRUE): n contracts of t periods, xreg t by p row-major, meth 0 unbiased and 1 iterative; a contract whose weights are all missing or zero is skipped as in actuar (individual coefficients 0, credibility 0).
// out = diagonal of the between matrix (p), within variance, collective coefficients (p), then by contract the individual coefficients (p), the credibility diagonal (p) and the credibility premium coefficients (p)
fn hache_bary(a: *mem.Arena, ratios: []const f64, weights: []const f64, xreg: []const f64, n: usize, t: usize, p: usize, meth: usize, out: []f64) -> err {
    let (wcol, e1) = mem.alloc[f64](a, t)
    let (xs, e2) = mem.alloc[f64](a, t * p)
    let (xo, e3) = mem.alloc[f64](a, t * p)
    let (ind, e4) = mem.alloc[f64](a, n * p)
    let (wd, e5) = mem.alloc[f64](a, n * p)
    let (sig, e6) = mem.alloc[f64](a, n)
    let (col, e7) = mem.alloc[f64](a, n)
    let (cr, e8) = mem.alloc[f64](a, n * p)
    let (gm, e9) = mem.alloc[f64](a, p * p)
    let (bv, e10) = mem.alloc[f64](a, p)
    let (qy, e11) = mem.alloc[f64](a, t)
    let (wsv, e12) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret e1 }
    var tot = 0.0f64
    var c = 0usize
    var j = 0usize
    var i = 0usize
    var wmin = 1.0e300f64
    var wmax = 0.0f64 - 1.0e300f64
    while j < t {
        wcol[j] = 0.0f64
        j += 1usize
    }
    c = 0usize
    while c < n {
        wsv[c] = 0.0f64
        j = 0usize
        while j < t {
            let w = weights[c * t + j]
            if w == w {
                wcol[j] += w
                wsv[c] += w
                tot += w
                if w < wmin { wmin = w }
                if w > wmax { wmax = w }
            }
            j += 1usize
        }
        c += 1usize
    }
    j = 0usize
    while j < t {
        wcol[j] = wcol[j] / tot
        i = 0usize
        while i < p {
            xs[i * t + j] = xreg[j * p + i] * math.sqrt[f64](wcol[j])
            i += 1usize
        }
        j += 1usize
    }
    let (fq, eq) = dc.qr(a, xs, t, p, 1.0e-7f64)
    if eq != ok { ret eq }
    i = 0usize
    while i < p {
        j = 0usize
        while j < t {
            qy[j] = 0.0f64
            j += 1usize
        }
        qy[i] = 1.0f64
        dc.qr_qy(&fq, qy)
        j = 0usize
        while j < t {
            xo[j * p + i] = qy[j] / math.sqrt[f64](wcol[j])
            j += 1usize
        }
        i += 1usize
    }
    var s2sum = 0.0f64
    var ne = 0usize
    c = 0usize
    while c < n {
        var k = 0usize
        while k < p * p {
            gm[k] = 0.0f64
            k += 1usize
        }
        i = 0usize
        while i < p {
            bv[i] = 0.0f64
            i += 1usize
        }
        var nobs = 0usize
        j = 0usize
        while j < t {
            let w = weights[c * t + j]
            if w == w {
                nobs += 1usize
                i = 0usize
                while i < p {
                    k = 0usize
                    while k < p {
                        gm[i * p + k] += w * xo[j * p + i] * xo[j * p + k]
                        k += 1usize
                    }
                    bv[i] += w * xo[j * p + i] * ratios[c * t + j]
                    i += 1usize
                }
            }
            j += 1usize
        }
        if wsv[c] > 0.0f64 {
        ne += 1usize
        let (gi, eg) = gp.invert(a, gm, p)
        if eg != ok { ret eg }
        i = 0usize
        while i < p {
            var s = 0.0f64
            k = 0usize
            while k < p {
                s += gi[i * p + k] * bv[k]
                k += 1usize
            }
            ind[c * p + i] = s
            i += 1usize
        }
        var rss = 0.0f64
        j = 0usize
        while j < t {
            let w = weights[c * t + j]
            if w == w {
                var fit = 0.0f64
                i = 0usize
                while i < p {
                    fit += xo[j * p + i] * ind[c * p + i]
                    i += 1usize
                }
                rss += w * (ratios[c * t + j] - fit) * (ratios[c * t + j] - fit)
            }
            j += 1usize
        }
        sig[c] = rss / f64(nobs - p)
        s2sum += sig[c]
        wd[c * p] = wsv[c]
        i = 1usize
        while i < p {
            var s = 0.0f64
            j = 0usize
            while j < t {
                let w = weights[c * t + j]
                if w == w { s += w * xo[j * p + i] * xo[j * p + i] }
                j += 1usize
            }
            wd[c * p + i] = s
            i += 1usize
        }
        } else {
            i = 0usize
            while i < p {
                ind[c * p + i] = 0.0f64
                wd[c * p + i] = 0.0f64
                i += 1usize
            }
        }
        c += 1usize
    }
    let s2 = s2sum / f64(ne)
    let (xv, e13) = mem.alloc[f64](a, n)
    let (wv, e14) = mem.alloc[f64](a, n)
    if e13 != ok || e14 != ok { ret e13 }
    i = 0usize
    while i < p {
        var m = 0usize
        c = 0usize
        while c < n {
            cr[c * p + i] = 0.0f64
            if wsv[c] > 0.0f64 {
                xv[m] = ind[c * p + i]
                wv[m] = wd[c * p + i]
                m += 1usize
            }
            c += 1usize
        }
        var av = bvar_unb(xv[0usize..m], wv[0usize..m], s2, m)
        if meth == 1usize && wmax - wmin > 1.4901161193847656e-8f64 {
            if av > 0.0f64 { av = bvar_iter(xv[0usize..m], wv[0usize..m], s2, m, av) } else { av = 0.0f64 }
        }
        out[i] = av
        var sz = 0.0f64
        var szx = 0.0f64
        c = 0usize
        m = 0usize
        while c < n {
            if wsv[c] > 0.0f64 {
                var z = 0.0f64
                if av > 0.0f64 { z = 1.0f64 / (1.0f64 + s2 / (wv[m] * av)) } else { z = wv[m] }
                if av > 0.0f64 { cr[c * p + i] = z }
                sz += z
                szx += z * xv[m]
                m += 1usize
            }
            c += 1usize
        }
        out[p + 1usize + i] = szx / sz
        i += 1usize
    }
    out[p] = s2
    c = 0usize
    while c < n {
        i = 0usize
        while i < p {
            let o = p + 1usize + p + c * 3usize * p
            out[o + i] = ind[c * p + i]
            out[o + p + i] = cr[c * p + i]
            out[o + 2usize * p + i] = out[p + 1usize + i] + cr[c * p + i] * (ind[c * p + i] - out[p + 1usize + i])
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// actuar poisson-inverse Gaussian pmf at the integer x >= 0 (mean mu, dispersion phi), by the recursion of dpoisinvgauss_raw, and the cdf by successive sums
fn pig_d(x: f64, mu: f64, phi: f64) -> f64 {
    let twophi = phi + phi
    let mu2 = mu * mu
    let twophimu2 = twophi * mu2
    var p = (1.0f64 - math.sqrt[f64](1.0f64 + twophimu2)) / phi / mu
    if x == 0.0f64 { ret math.exp[f64](p) }
    var pi2m = math.exp[f64](p)
    p = math.log[f64](mu) + p - dsa.log1p(twophimu2) / 2.0f64
    if x == 1.0f64 { ret math.exp[f64](p) }
    var pi1m = math.exp[f64](p)
    let ac = 1.0f64 / (1.0f64 + 1.0f64 / twophimu2)
    let bc = mu2 / (1.0f64 + twophimu2)
    var i = 2.0f64
    var r = pi1m
    while i <= x {
        r = ac * (1.0f64 - 1.5f64 / i) * pi1m + (bc * pi2m) / (i * (i - 1.0f64))
        pi2m = pi1m
        pi1m = r
        i += 1.0f64
    }
    ret r
}

fn pig_p(q: f64, mu: f64, phi: f64) -> f64 {
    var s = 0.0f64
    var x = 0.0f64
    while x <= q {
        s += pig_d(x, mu, phi)
        x += 1.0f64
    }
    ret s
}

// actuar SampleSingleValue: the state in 0..n drawn from the probabilities p[0..n) (the last state n takes the remainder) with one uniform
fn sample_single(g: *rr.Rng, n: usize, p: []const f64) -> usize {
    var pcum = p[0usize]
    let u = rr.unif(g)
    var i = 0usize
    while u > pcum && i < n {
        if i + 1usize < n { pcum += p[i + 1usize] }
        i += 1usize
    }
    ret i
}

// actuar rphtype (Neuts): the chain starts from prob, moves with the transition rows of tm (t(i, j) / rate_i for j != i, rate_i = -t(i, i)) until it is absorbed in state m, and the draw is the
// sum of one exponential per visit divided by the rate of the visited state; m is at most 16
fn rphtype1(g: *rr.Rng, prob: []const f64, tm: []const f64, m: usize) -> f64 {
    var nv: [16]usize = zero
    var row: [16]f64 = zero
    var state = sample_single(g, m, prob)
    while state != m {
        nv[state] += 1usize
        let rate = 0.0f64 - tm[state * m + state]
        var j = 0usize
        while j < m {
            row[j] = 0.0f64
            if j != state { row[j] = tm[state * m + j] / rate }
            j += 1usize
        }
        state = sample_single(g, m, row[0usize..m])
    }
    var z = 0.0f64
    var i = 0usize
    while i < m {
        var k = 0usize
        while k < nv[i] {
            z += rr.rexp(g, 1.0f64) / (0.0f64 - tm[i * m + i])
            k += 1usize
        }
        i += 1usize
    }
    ret z
}

// the generators of actuar, one uniform (or one beta for Feller-Pareto) per draw: kind 0 Pareto II, 1 Pareto III, 2 Pareto IV, 3 Feller-Pareto
fn sh_rand(g: *rr.Rng, kind: usize, mn: f64, s1: f64, s2: f64, s3: f64, sc: f64) -> f64 {
    if kind == 0usize { ret mn + sc * (math.pow[f64](rr.unif(g), 0.0f64 - 1.0f64 / s1) - 1.0f64) }
    if kind == 1usize { ret mn + sc * math.pow[f64](1.0f64 / rr.unif(g) - 1.0f64, 1.0f64 / s1) }
    if kind == 2usize { ret mn + sc * math.pow[f64](math.pow[f64](rr.unif(g), 0.0f64 - 1.0f64 / s1) - 1.0f64, 1.0f64 / s2) }
    ret mn + sc * math.pow[f64](1.0f64 / rd.rbeta(g, s1, s3) - 1.0f64, 1.0f64 / s2)
}

// levinvpareto as actuar computes it: R's integrate() (dqags, 100 subdivisions, eps^0.25 tolerances) of x^(t+k-1) (1-x)^(-k) over (0, limit / (limit + scale))
type IpCtx = struct { shape: f64, order: f64 }

fn ip_fn(c: *IpCtx, x: f64) -> f64 { ret math.pow[f64](x, c.shape + c.order - 1.0f64) * math.pow[f64](1.0f64 - x, 0.0f64 - c.order) }

fn log1pexp(x: f64) -> f64 {
    if x <= 18.0f64 { ret dsa.log1p(math.exp[f64](x)) }
    if x > 33.3f64 { ret x }
    ret x + math.exp[f64](0.0f64 - x)
}

// the fault code of the integration is in the second result: 0 ok
fn levinvpareto(a: *mem.Arena, limit: f64, shape: f64, scale: f64, order: f64) -> f64 {
    if shape <= 0.0f64 || scale <= 0.0f64 { ret nan() }
    if order <= 0.0f64 - shape { ret 1.0f64 / 0.0f64 }
    if limit <= 0.0f64 { ret 0.0f64 }
    var c = IpCtx { shape: shape, order: order }
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let (r, e) = qp.qags[IpCtx](a, &c, ip_fn, 0.0f64, limit / (limit + scale), tol, tol, 100usize)
    if r.ier != 0i64 { ret nan() }
    let u = math.exp[f64](0.0f64 - log1pexp(math.log[f64](scale) - math.log[f64](limit)))
    ret math.pow[f64](scale, order) * shape * r.result + math.pow[f64](limit, order) * (0.5f64 - math.pow[f64](u, shape) + 0.5f64)
}

// ---- aggregateDist: quantile (VaR) and conditional tail expectation ----

// the length of the vector aggregateDist("recursive") returns: the recursion runs while the cumulative probability stays below 1 - 1e-6 (tol) and stops after maxit steps
fn panjer_len(fs: []const f64, tol: f64, maxit: usize) -> usize {
    var cumul = fs[0usize]
    var x = 1usize
    while true {
        if x > maxit { break }
        cumul += fs[x]
        x += 1usize
        if cumul >= tol { break }
    }
    ret x
}

// quantile.aggregateDist of a step cdf: R's approxfun(y, x, yleft = 0, yright = max(x), f = 1) (smooth false) or its linear version, the ogive (smooth true); y holds the cdf values at the knots xs
fn agg_inv(xs: []const f64, ys: []const f64, p: f64, smooth: bool) -> f64 {
    let n = ys.len
    if p < ys[0usize] { ret 0.0f64 }
    var mx = xs[0usize]
    var k = 0usize
    while k < n {
        if xs[k] > mx { mx = xs[k] }
        k += 1usize
    }
    if p > ys[n - 1usize] { ret mx }
    var i = 0usize
    var j = n - 1usize
    while i + 1usize < j {
        let ij = (i + j) / 2usize
        if p < ys[ij] { j = ij } else { i = ij }
    }
    if p == ys[j] { ret xs[j] }
    if p == ys[i] { ret xs[i] }
    if smooth { ret xs[i] + (xs[j] - xs[i]) * ((p - ys[i]) / (ys[j] - ys[i])) }
    ret xs[j]
}

// CTE.aggregateDist of a step cdf: the pmf-weighted mean of the knots above the VaR
fn agg_cte(xs: []const f64, fs: []const f64, ys: []const f64, level: f64) -> f64 {
    let v = agg_inv(xs, ys, level, false)
    var num = 0.0f64
    var den = 0.0f64
    var k = 0usize
    while k < xs.len {
        if xs[k] > v {
            num += xs[k] * fs[k]
            den += fs[k]
        }
        k += 1usize
    }
    ret num / den
}

// the Normal and Normal Power approximations: quantile (npower undefined at or below one half) and CTE
fn agg_normal_q(p: f64, mean: f64, variance: f64) -> f64 { ret dsa.qnorm(p, mean, math.sqrt[f64](variance), true, false) }

fn agg_normal_cte(level: f64, mean: f64, variance: f64) -> f64 {
    ret mean + math.sqrt[f64](variance) * dsa.dnorm(dsa.qnorm(level, 0.0f64, 1.0f64, true, false), 0.0f64, 1.0f64, false) / (1.0f64 - level)
}

fn agg_npower_q(p: f64, mean: f64, variance: f64, skewness: f64) -> f64 {
    if p <= 0.5f64 { ret nan() }
    let q = dsa.qnorm(p, 0.0f64, 1.0f64, true, false)
    ret mean + math.sqrt[f64](variance) * (q + skewness * (q * q - 1.0f64) / 6.0f64)
}

fn agg_npower_cte(level: f64, mean: f64, variance: f64, skewness: f64) -> f64 {
    let q = dsa.qnorm(level, 0.0f64, 1.0f64, true, false)
    ret mean + math.sqrt[f64](variance) * dsa.dnorm(q, 0.0f64, 1.0f64, false) * (1.0f64 + skewness * q / 6.0f64) / (1.0f64 - level)
}

// the sorted sample as aggregateDist("simulation") keeps it: distinct values in xs and their relative frequencies in fs (xs and fs hold at least n entries); the answer is the number of distinct values
fn agg_sim_table(sample: []f64, xs: []f64, fs: []f64) -> usize {
    let n = sample.len
    var i = 1usize
    while i < n {
        let v = sample[i]
        var j = i
        while j > 0usize && sample[j - 1usize] > v {
            sample[j] = sample[j - 1usize]
            j -= 1usize
        }
        sample[j] = v
        i += 1usize
    }
    var m = 0usize
    i = 0usize
    while i < n {
        if m > 0usize && xs[m - 1usize] == sample[i] {
            fs[m - 1usize] += 1.0f64
        } else {
            xs[m] = sample[i]
            fs[m] = 1.0f64
            m += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        fs[i] = fs[i] / f64(n)
        i += 1usize
    }
    ret m
}
