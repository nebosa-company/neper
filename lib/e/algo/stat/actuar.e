// R actuar loss distributions: the transformed beta family (`tb_*`: density, distribution, quantile, raw moment and limited expected
// value of the transformed beta, with Burr, inverse Burr, Pareto, inverse Pareto, loglogistic, paralogistic, inverse paralogistic and
// generalised Pareto as parameter maps), the transformed gamma family (`tg_*`, with gamma, Weibull and exponential as maps) and its
// inverse (`itg_*`: inverse gamma, inverse Weibull and inverse exponential), and the single-parameter Pareto (`p1_*`). Moments and
// limited expected values are given for orders inside the range where they are finite.
//
// Not here: the other distributions of the package, the random generators, aggregateDist, ruin, cm and the grouped-data tools.

use e.math
use e.math.nmath as nm
use e.math.dist as dsa
use e.math.nmath_beta as nb
use e.algo.linalg.mexp as mexp
use e.algo.rand.r as rr
use e.algo.rand.rdist as rd
use e.algo.stat.gparot as gp
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
        a = 0.0f64 - p2 / (1.0f64 - p2)
        b = (p1 + 1.0f64) * p2 / (1.0f64 - p2)
        s0 = math.pow[f64](1.0f64 - p2 + p2 * f0, p1)
    } else if kind == 2usize {
        a = 1.0f64 - p2
        b = (p1 - 1.0f64) * (1.0f64 - p2)
        s0 = math.pow[f64](p2 / (1.0f64 - (1.0f64 - p2) * f0), p1)
    } else {
        a = 1.0f64 - p1
        s0 = p1 / (1.0f64 - (1.0f64 - p1) * f0)
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
// 2 rinvgamma (p1, sc), 3 rgumbel (alpha p1, scale p2), 4 rlgamma (shapelog p1, ratelog p2), 5 rpareto1 (shape p1, min p2), 6 rinvtrgamma (p1, p2, sc), 7 rinvweibull (shape p1, scale sc), 8 rinvexp (scale sc), 9 rgenbeta (shape1 p1, shape2 p2, shape3 p3, scale sc)
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
    ret sc * math.pow[f64](rd.rbeta(g, p1, p2), 1.0f64 / p3)
}

// actuar random draw for the transformed beta maps (tb_params kinds 0 burr .. 6 invparalogis): the inversion runs on 1 - u for burr, pareto, llogis and paralogis and on u for the inverse families
fn rand_tb(g: *rr.Rng, kind: u8, s1: f64, s2: f64, sc: f64) -> f64 {
    let (a, ga, t) = tb_params(kind, s1, s2, 1.0f64)
    let u = rr.unif(g)
    if kind == 1u8 || kind == 3u8 || kind == 6u8 { ret tb_q(u, a, ga, t, sc) }
    ret tb_q(1.0f64 - u, a, ga, t, sc)
}
