// R actuar loss distributions: the transformed beta family (`tb_*`: density, distribution, quantile, raw moment and limited expected
// value of the transformed beta, with Burr, inverse Burr, Pareto, inverse Pareto, loglogistic, paralogistic, inverse paralogistic and
// generalised Pareto as parameter maps), the transformed gamma family (`tg_*`, with gamma, Weibull and exponential as maps) and its
// inverse (`itg_*`: inverse gamma, inverse Weibull and inverse exponential), and the single-parameter Pareto (`p1_*`). Moments and
// limited expected values are given for orders inside the range where they are finite.
//
// Not here: the other distributions of the package, the random generators, aggregateDist, ruin, cm and the grouped-data tools.

use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb

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
