// R SuppDists, the exact and closed-form members: the inverse Gaussian (`d`, `p`, `q`), Kendall's tau and
// Spearman's rho for small N (the exact permutation counts, with SuppDists' reading of a value that is not on the
// support: the inversion count or squared-rank-difference sum is rounded to the nearest, a half going down), and Johnson's system (families SN,
// SL, SB, SU: `d`, `p`, `q`).
//
// And the Pearson correlation (SuppDists' own SQRT2 constant, 1.41413562..., is part of its answer). Not here: the Edgeworth approximations for large N, the Friedman, Kruskal-Wallis, normal-scores, maximum F-ratio,
// Pearson and hypergeometric distributions, moments, the Johnson fit, random variates.

use e.math
use e.math.dist as dist
use e.math.nmath as nmt
use e.math.nmath_beta as nb
use e.mem
use e.algo.rand.r as rng
use e.algo.rand.rdist as rd

fn pnorm(z: f64) -> f64 { ret dist.pnorm(z, 0.0f64, 1.0f64, true, false) }

fn dinv_gauss(x: f64, nu: f64, lam: f64) -> f64 {
    ret math.sqrt[f64](lam / (2.0f64 * 3.141592653589793f64 * x * x * x)) * math.exp[f64](0.0f64 - lam * (x - nu) * (x - nu) / (2.0f64 * nu * nu * x))
}

fn pinv_gauss(x: f64, nu: f64, lam: f64) -> f64 {
    let s = math.sqrt[f64](lam / x)
    ret pnorm(s * (x / nu - 1.0f64)) + math.exp[f64](2.0f64 * lam / nu) * pnorm(0.0f64 - s * (x / nu + 1.0f64))
}

// quantile by bracketing then bisection on the cdf
fn qinv_gauss(p: f64, nu: f64, lam: f64) -> f64 {
    var lo = 0.0f64
    var hi = nu
    while pinv_gauss(hi, nu, lam) < p { hi = hi * 2.0f64 }
    var it = 0usize
    while it < 200usize {
        let mid = (lo + hi) / 2.0f64
        if mid <= 0.0f64 { break }
        if pinv_gauss(mid, nu, lam) < p { lo = mid } else { hi = mid }
        it += 1usize
    }
    ret (lo + hi) / 2.0f64
}

// the number of permutations of 1..n with k inversions, k = 0 ..= n(n-1)/2, in counts (f64); returns the length
fn mahonian(n: usize, counts: []f64) -> usize {
    let top = n * (n - 1usize) / 2usize
    var k = 0usize
    while k <= top {
        counts[k] = 0.0f64
        k += 1usize
    }
    counts[0usize] = 1.0f64
    var m = 2usize
    var hi = 0usize
    while m <= n {
        let newhi = hi + m - 1usize
        // counts_m[k] = sum_{j = 0}^{m - 1} counts_{m-1}[k - j]
        var kk = newhi
        while true {
            var s = 0.0f64
            var j = 0usize
            while j < m && j <= kk {
                if kk - j <= hi { s += counts[kk - j] }
                j += 1usize
            }
            counts[kk] = s
            if kk == 0usize { break }
            kk -= 1usize
        }
        hi = newhi
        m += 1usize
    }
    ret top + 1usize
}

fn factorial(n: usize) -> f64 {
    var v = 1.0f64
    var i = 2usize
    while i <= n {
        v *= f64(i)
        i += 1usize
    }
    ret v
}

// Kendall: inversions k = round((1 - tau) N (N - 1) / 4); d = count[k] / N!; p = sum_{j >= k} count[j] / N!
fn kendall_index(tau: f64, n: usize) -> f64 { ret math.ceil[f64]((1.0f64 - tau) * f64(n) * f64(n - 1usize) / 4.0f64 - 0.5f64 - 1.0e-9f64) }

fn dkendall(a: *mem.Arena, tau: f64, n: usize) -> (f64, err) {
    let (c, e) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 2usize)
    if e != ok { ret (0.0f64, e) }
    let len = mahonian(n, c)
    let k = kendall_index(tau, n)
    if k < 0.0f64 || k >= f64(len) { ret (0.0f64, ok) }
    ret (c[usize(k)] / factorial(n), ok)
}

fn pkendall(a: *mem.Arena, tau: f64, n: usize) -> (f64, err) {
    let (c, e) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 2usize)
    if e != ok { ret (0.0f64, e) }
    let len = mahonian(n, c)
    let k = kendall_index(tau, n)
    if k < 0.0f64 { ret (1.0f64, ok) }
    if k >= f64(len) { ret (0.0f64, ok) }
    var s = 0.0f64
    var j = usize(k)
    while j < len {
        s += c[j]
        j += 1usize
    }
    ret (s / factorial(n), ok)
}

// counts[s] = the number of permutations of 1..n with sum of squared rank differences s, by a DP over subsets
fn spearman_counts(a: *mem.Arena, n: usize, counts: []f64) -> err {
    let smax = n * (n * n - 1usize) / 3usize
    let width = smax + 1usize
    let masks = 1usize << n
    let (f, e) = mem.alloc[f64](a, masks * width)
    if e != ok { ret e }
    var i = 0usize
    while i < masks * width {
        f[i] = 0.0f64
        i += 1usize
    }
    f[0usize] = 1.0f64
    var mask = 0usize
    while mask < masks {
        // position = popcount(mask)
        var pc = 0usize
        var t = mask
        while t > 0usize {
            pc += t & 1usize
            t = t >> 1usize
        }
        if pc < n {
            var j = 0usize
            while j < n {
                if (mask >> j) & 1usize == 0usize {
                    var d = j
                    if pc > j { d = pc - j } else { d = j - pc }
                    let add = d * d
                    var s = 0usize
                    while s + add < width {
                        if f[mask * width + s] != 0.0f64 { f[(mask | (1usize << j)) * width + s + add] += f[mask * width + s] }
                        s += 1usize
                    }
                }
                j += 1usize
            }
        }
        mask += 1usize
    }
    var s = 0usize
    while s < width {
        counts[s] = f[(masks - 1usize) * width + s]
        s += 1usize
    }
    ret ok
}

// Spearman: S = round((1 - rho) N (N^2 - 1) / 6), exact at the rho of an actual permutation; between support points R picks a neighbouring one by a rule not reproduced here; d = count[S] / N!; p = sum_{s >= S} count[s] / N!
fn spearman_index(rho: f64, n: usize) -> f64 { ret math.ceil[f64]((1.0f64 - rho) * f64(n) * (f64(n) * f64(n) - 1.0f64) / 6.0f64 - 0.5f64 - 1.0e-9f64) }

fn dspearman(a: *mem.Arena, rho: f64, n: usize) -> (f64, err) {
    let smax = n * (n * n - 1usize) / 3usize
    let (c, e) = mem.alloc[f64](a, smax + 1usize)
    if e != ok { ret (0.0f64, e) }
    let ee = spearman_counts(a, n, c)
    if ee != ok { ret (0.0f64, ee) }
    let s = spearman_index(rho, n)
    if s < 0.0f64 || s > f64(smax) { ret (0.0f64, ok) }
    ret (c[usize(s)] / factorial(n), ok)
}

fn pspearman(a: *mem.Arena, rho: f64, n: usize) -> (f64, err) {
    let smax = n * (n * n - 1usize) / 3usize
    let (c, e) = mem.alloc[f64](a, smax + 1usize)
    if e != ok { ret (0.0f64, e) }
    let ee = spearman_counts(a, n, c)
    if ee != ok { ret (0.0f64, ee) }
    let s = spearman_index(rho, n)
    if s < 0.0f64 { ret (1.0f64, ok) }
    if s > f64(smax) { ret (0.0f64, ok) }
    var sum = 0.0f64
    var j = usize(s)
    while j <= smax {
        sum += c[j]
        j += 1usize
    }
    ret (sum / factorial(n), ok)
}

// Johnson: type 0 SN, 1 SL (lambda = +1), 2 SB, 3 SU
fn djohnson(x: f64, gamma: f64, delta: f64, xi: f64, lambda: f64, kind: u8) -> f64 {
    let s2p = math.sqrt[f64](2.0f64 * 3.141592653589793f64)
    let u = (x - xi) / lambda
    if kind == 0u8 {
        let z = gamma + delta * u
        ret delta / lambda / s2p * math.exp[f64](0.0f64 - z * z / 2.0f64)
    }
    if kind == 1u8 {
        if x <= xi { ret 0.0f64 }
        let z = gamma + delta * math.log[f64](x - xi)
        ret delta / (x - xi) / s2p * math.exp[f64](0.0f64 - z * z / 2.0f64)
    }
    if kind == 2u8 {
        if u <= 0.0f64 || u >= 1.0f64 { ret 0.0f64 }
        let z = gamma + delta * math.log[f64](u / (1.0f64 - u))
        ret delta / (lambda * s2p * u * (1.0f64 - u)) * math.exp[f64](0.0f64 - z * z / 2.0f64)
    }
    let z = gamma + delta * math.log[f64](u + math.sqrt[f64](u * u + 1.0f64))
    ret delta / (lambda * s2p * math.sqrt[f64](u * u + 1.0f64)) * math.exp[f64](0.0f64 - z * z / 2.0f64)
}

fn pjohnson(x: f64, gamma: f64, delta: f64, xi: f64, lambda: f64, kind: u8) -> f64 {
    let u = (x - xi) / lambda
    if kind == 0u8 { ret pnorm(gamma + delta * u) }
    if kind == 1u8 {
        if x <= xi { ret 0.0f64 }
        ret pnorm(gamma + delta * math.log[f64](x - xi))
    }
    if kind == 2u8 {
        if u <= 0.0f64 { ret 0.0f64 }
        if u >= 1.0f64 { ret 1.0f64 }
        ret pnorm(gamma + delta * math.log[f64](u / (1.0f64 - u)))
    }
    ret pnorm(gamma + delta * math.log[f64](u + math.sqrt[f64](u * u + 1.0f64)))
}

fn qjohnson(p: f64, gamma: f64, delta: f64, xi: f64, lambda: f64, kind: u8) -> f64 {
    let z = dist.qnorm(p, 0.0f64, 1.0f64, true, false)
    let w = (z - gamma) / delta
    if kind == 0u8 { ret xi + lambda * w }
    if kind == 1u8 { ret xi + math.exp[f64](w) }
    if kind == 2u8 { ret xi + lambda / (1.0f64 + math.exp[f64](0.0f64 - w)) }
    ret xi + lambda * (math.exp[f64](w) - math.exp[f64](0.0f64 - w)) / 2.0f64
}

// ghyper(a, k, N): the hypergeometric of k draws with a successes among N
fn ghyper_d(x: f64, a: f64, k: f64, n: f64) -> f64 { ret nb.dhyper(x, a, n - a, k, false) }
fn ghyper_p(x: f64, a: f64, k: f64, n: f64) -> f64 { ret nb.phyper(x, a, n - a, k, true, false) }
fn ghyper_q(p: f64, a: f64, k: f64, n: f64) -> f64 {
    var x = nb.qhyper(p, a, n - a, k, true, false)
    if nb.phyper(x, a, n - a, k, true, false) <= p * (1.0f64 + 1.0e-12f64) { x += 1.0f64 }
    ret x
}

// ---- the distribution of the Pearson correlation coefficient (dcorr, pcorr, qcorr) ----

fn pik_loggamma(x0: f64) -> f64 {
    var x = x0
    if x == 1.0f64 || x == 2.0f64 { ret 0.0f64 }
    var f = 0.0f64
    if x < 7.0f64 {
        f = 1.0f64
        while x < 7.0f64 {
            f = f * x
            x = x + 1.0f64
        }
        f = 0.0f64 - math.log[f64](f)
    }
    let z = 1.0f64 / (x * x)
    f = f + (x - 0.5f64) * math.log[f64](x) - x + 0.918938533204672741780329736406f64
    let t = ((1.0f64 / 1188.0f64) * z - 1.0f64 / 1680.0f64) * z + 1.0f64 / 1260.0f64
    f = f + ((t * z - 1.0f64 / 360.0f64) * z + 1.0f64 / 12.0f64) / x
    ret f
}

// the density of r for the population correlation rho and sample size n (Johnson and Kotz 6.5, the series for F[1/2, 1/2; n - 1/2, (1 + rho r) / 2])
fn fcorrelation(r: f64, rho: f64, nn: i64) -> f64 {
    let n = f64(nn)
    if nn < 3i64 || r < 0.0f64 - 1.0f64 || r > 1.0f64 || rho < 0.0f64 - 1.0f64 || rho > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if math.abs[f64](r) >= 1.0f64 { ret 0.0f64 }
    let scale = (n - 2.0f64) / (1.414135623730950488f64 * (n - 1.0f64))
    var lf = 0.5f64 * (n - 1.0f64) * math.log[f64](1.0f64 - rho * rho) + 0.5f64 * (n - 4.0f64) * math.log[f64](1.0f64 - r * r)
    lf = lf + (1.5f64 - n) * math.log[f64](1.0f64 - rho * r) + pik_loggamma(n) - pik_loggamma(n - 0.5f64) - 0.5723649429247001f64
    let c = n - 0.5f64
    let x = 0.5f64 * (1.0f64 + rho * r)
    var sum = 0.0f64
    var term = 1.0f64
    var j = 1i64
    var going = true
    while going {
        let dj = f64(j)
        sum = sum + term
        let value = f64(2i64 * j - 1i64)
        term = term * ((0.25f64 * (value * value) / (c + dj - 1.0f64)) * (x / dj))
        j += 1i64
        if sum + term == sum || j > 100i64 { going = false }
    }
    ret scale * math.exp[f64](lf) * sum
}

type Corr = struct { rho: f64, n: i64, p: f64 }

fn corr_density(c: *Corr, r: f64) -> f64 { ret fcorrelation(r, c.rho, c.n) }

// SuppDists' Integral: Romberg iteration on halved steps, stopping when two diagonal values agree to tol (relative)
fn romberg[C: type](ctx: *C, f: fn(*C, f64) -> f64, lo: f64, hi: f64, tol: f64) -> f64 {
    let h = hi - lo
    var a: [16][16]f64 = zero
    var delta = h
    var value = 0.0f64
    a[0usize][0usize] = (h / 2.0f64) * (f(ctx, lo) + f(ctx, hi))
    var two_power = 1.0f64
    var k = 0usize
    var n = 1usize
    var going = true
    while going {
        k += 1usize
        delta = delta * 0.5f64
        if k > 1usize { n = n * 2usize }
        two_power = two_power * 2.0f64
        var sum = 0.0f64
        var z = hi - delta
        var m = n
        while m > 0usize {
            m -= 1usize
            sum = sum + f(ctx, z)
            z = z - 2.0f64 * delta
        }
        a[0usize][k] = a[0usize][k - 1usize] / 2.0f64 + h * sum / two_power
        var four_power = 1.0f64
        var i = 1usize
        while i <= k {
            four_power = four_power * 4.0f64
            a[i][k - i] = (four_power * a[i - 1usize][k - i + 1usize] - a[i - 1usize][k - i]) / (four_power - 1.0f64)
            i += 1usize
        }
        value = a[k][0usize]
        if math.abs[f64]((value - a[k - 1usize][0usize]) / value) < tol { break }
        if k >= 15usize { going = false }
    }
    ret value
}

fn pcorrelation(r: f64, rho: f64, nn: i64) -> f64 {
    if nn < 3i64 || r < 0.0f64 - 1.0f64 || r > 1.0f64 || rho < 0.0f64 - 1.0f64 || rho > 1.0f64 { ret 0.0f64 / 0.0f64 }
    var c = Corr { rho: rho, n: nn, p: 0.0f64 }
    var p = romberg[Corr](&c, corr_density, 0.0f64 - 1.0f64, r, 3.0e-8f64)
    if p < 0.0f64 - 0.0001f64 || p > 1.0001f64 { ret 0.0f64 / 0.0f64 }
    if p < 0.0f64 { p = 0.0f64 }
    if p > 1.0f64 { p = 1.0f64 }
    ret p
}

fn corr_dev(c: *Corr, r: f64) -> f64 { ret 0.0f64 - c.p + pcorrelation(r, c.rho, c.n) }

// SuppDists' NewtonRoot (the step is (f / 2 f') damped by a scale that halves when the step grows)
fn newton_root[C: type](ctx: *C, guess: f64, f: fn(*C, f64) -> f64, df: fn(*C, f64) -> f64, tol: f64) -> f64 {
    var x = guess
    var z = x
    var ho = 1.7976931348623157e308f64
    var scale = 1.0f64
    var m = 0i64
    var more = true
    var going = true
    while going {
        var retry = false
        let fcn = f(ctx, x)
        let deriv = df(ctx, x)
        let h = scale * 0.5f64 * fcn / (deriv + 2.220446049250313e-16f64 * math.abs[f64](fcn))
        z = z - h
        more = math.abs[f64](h / z) > tol
        if ho <= math.abs[f64](h) {
            scale = scale / 2.0f64
            z = z + h
            more = true
            retry = true
        }
        if !retry {
            if scale < 1.0f64 { scale = scale * 2.0f64 }
            ho = math.abs[f64](h)
            x = z
        }
        let cond = m > 100i64 || !more
        m += 1i64
        if cond { going = false }
    }
    ret x
}

fn qcorrelation(p: f64, rho: f64, nn: i64) -> f64 {
    if nn < 3i64 || p < 0.0f64 || p > 1.0f64 || rho < 0.0f64 - 1.0f64 || rho > 1.0f64 { ret 0.0f64 / 0.0f64 }
    var c = Corr { rho: rho, n: nn, p: p }
    var z = 0.5f64 * math.log[f64]((1.0f64 + rho) / (1.0f64 - rho)) + dist.qnorm(p, 0.0f64, 1.0f64, true, false) / math.sqrt[f64](f64(nn - 3i64))
    z = math.exp[f64](2.0f64 * z)
    let guess = (z - 1.0f64) / (z + 1.0f64)
    ret newton_root[Corr](&c, guess, corr_dev, corr_density, 3.0e-8f64)
}

// ---- Kruskal-Wallis and normal scores (the beta approximations of Wallace 1959 and Lu and Smith 1979) ----

fn kw_max_u(c: i64, n: i64) -> f64 { ret f64(c - 1i64) + 1.0f64 / f64(n - (c - 1i64)) }

fn var_kruskal_wallis(n: f64, c: f64, u: f64) -> f64 {
    var f = 2.0f64 * (c - 1.0f64)
    f = f - 0.4f64 * (3.0f64 * c * c - 6.0f64 * c + n * (2.0f64 * c * c - 6.0f64 * c + 1.0f64)) / (n * (n + 1.0f64))
    f = f - 1.2f64 * u
    ret f
}

fn var_normal_scores(n: f64, c: f64, u: f64) -> f64 {
    let alpha = 0.375f64
    let np = n + 1.0f64
    let nm = n - 1.0f64
    let nc = n - c
    let cm = c - 1.0f64
    let den = 1.0f64 - 2.0f64 * alpha
    let cnt = i64(0.1f64 + n / 2.0f64)
    var e2 = 0.0f64
    var e4 = 0.0f64
    var i = 1i64
    while i <= cnt {
        var e = dist.qnorm((f64(i) - alpha) / (n + den), 0.0f64, 1.0f64, true, false)
        e = e * e
        e2 = e2 + e
        e4 = e4 + e * e
        i += 1i64
    }
    e2 = e2 * (4.0f64 * e2)
    let g = (np * n * nm * nm * 2.0f64 * e4 - 3.0f64 * nm * nm * nm * e2) / (nm * (n - 2.0f64) * (n - 3.0f64) * e2)
    var v = 2.0f64 * cm * nc / np
    v = v - g * (np * c * c + 2.0f64 * cm * nc - n * np * u) / (n * np)
    ret v
}

// the beta parameters (f1, f2) of the approximation
fn kw_beta(c: i64, n: i64, u: f64, normal_score: bool) -> (f64, f64) {
    let cc = f64(c)
    let nn = f64(n)
    var v = var_kruskal_wallis(nn, cc, u)
    if normal_score { v = var_normal_scores(nn, cc, u) }
    let d = ((nn - cc) * (cc - 1.0f64) - v) / ((nn - 1.0f64) * v)
    ret ((cc - 1.0f64) * d, (nn - cc) * d)
}

fn pkruskal_wallis(h: f64, c: i64, n: i64, u: f64, normal_score: bool) -> f64 {
    if h < 0.0f64 || u <= 0.0f64 || u > kw_max_u(c, n) { ret 0.0f64 / 0.0f64 }
    let (f1, f2) = kw_beta(c, n, u, normal_score)
    ret nb.pbeta(h / (f64(n) - 1.0f64), f1, f2, true, false)
}

fn qkruskal_wallis_upper(h: f64, c: i64, n: i64, u: f64, normal_score: bool) -> f64 {
    if h < 0.0f64 || u <= 0.0f64 || u > kw_max_u(c, n) { ret 0.0f64 / 0.0f64 }
    ret 1.0f64 - pkruskal_wallis(h, c, n, u, normal_score)
}

fn xkruskal_wallis(p: f64, c: i64, n: i64, u: f64, normal_score: bool) -> f64 {
    if p < 0.0f64 || p > 1.0f64 || u <= 0.0f64 || u > kw_max_u(c, n) { ret 0.0f64 / 0.0f64 }
    let (f1, f2) = kw_beta(c, n, u, normal_score)
    ret (f64(n) - 1.0f64) * nb.qbeta(p, f1, f2, true, false)
}

// the density is the forward difference quotient of the cdf over 0.001, as SuppDists computes it
fn fkruskal_wallis(h: f64, c: i64, n: i64, u: f64, normal_score: bool) -> f64 {
    let delta = 0.001f64
    ret (pkruskal_wallis(h + delta, c, n, u, normal_score) - pkruskal_wallis(h, c, n, u, normal_score)) / delta
}

// ---- the maximum F ratio (Hartley's) of N mean squares on df degrees of freedom each ----

fn mf_integrand_p(x: f64, f: f64, df: i64, n: i64, logc: f64) -> f64 {
    var logv = logc - 0.5f64 * x
    logv = logv + (0.5f64 * f64(df) - 1.0f64) * math.log[f64](x) + f64(n - 1i64) * math.log[f64](nmt.pchisq(x * f, f64(df), true, false) - nmt.pchisq(x, f64(df), true, false))
    ret math.exp[f64](logv)
}

fn mf_integrand_d(x: f64, f: f64, df: i64, n: i64, logc: f64) -> f64 {
    var logv = logc - 0.5f64 * x * (1.0f64 + f)
    logv = logv + (f64(df) - 1.0f64) * math.log[f64](x) + (0.5f64 * f64(df) - 1.0f64) * math.log[f64](f)
    logv = logv + f64(n - 2i64) * math.log[f64](math.abs[f64](nmt.pchisq(x * f, f64(df), true, false) - nmt.pchisq(x, f64(df), true, false)))
    ret math.exp[f64](logv)
}

fn mf_eval(x: f64, f: f64, df: i64, n: i64, logc: f64, dens: bool) -> f64 {
    if dens { ret mf_integrand_d(x, f, df, n, logc) }
    ret mf_integrand_p(x, f, df, n, logc)
}

// Romberg's rule over (qchisq(1e-4), qchisq(0.9999)) to a relative 1e-4 and at most 15 halvings, as the package does
fn mf_romberg(f: f64, df: i64, n: i64, logc: f64, dens: bool) -> f64 {
    let up = nmt.qchisq(0.9999f64, f64(df), true, false)
    let lo = nmt.qchisq(0.0001f64, f64(df), true, false)
    let h = up - lo
    var arr: [256]f64 = zero
    var delta = h
    var value = 0.0f64
    arr[0usize] = (h / 2.0f64) * (mf_eval(lo, f, df, n, logc, dens) + mf_eval(up, f, df, n, logc, dens))
    var two_power = 1.0f64
    var k = 0usize
    var cnt = 1usize
    var going = true
    while going {
        k += 1usize
        delta = delta * 0.5f64
        if k > 1usize { cnt = cnt * 2usize }
        two_power = two_power * 2.0f64
        var sum = 0.0f64
        var z = up - delta
        var m = cnt
        while m > 0usize {
            m -= 1usize
            sum += mf_eval(z, f, df, n, logc, dens)
            z = z - 2.0f64 * delta
        }
        arr[k] = arr[k - 1usize] / 2.0f64 + h * sum / two_power
        var four_power = 1.0f64
        var i = 1usize
        while i <= k {
            four_power = four_power * 4.0f64
            arr[i * 16usize + (k - i)] = (four_power * arr[(i - 1usize) * 16usize + (k - i + 1usize)] - arr[(i - 1usize) * 16usize + (k - i)]) / (four_power - 1.0f64)
            i += 1usize
        }
        value = arr[k * 16usize]
        if math.abs[f64]((value - arr[(k - 1usize) * 16usize]) / value) < 1.0e-4f64 { break }
        if k >= 15usize { going = false }
    }
    ret value
}

fn pmaxfratio(f: f64, df: i64, n: i64) -> f64 {
    if f <= 0.0f64 || df < 1i64 || n < 1i64 { ret 0.0f64 / 0.0f64 }
    if n == 2i64 { ret 1.0f64 - 2.0f64 * (1.0f64 - nb.pf(f, f64(df), f64(df), true, false)) }
    let logc = math.log[f64](f64(n)) - (0.5f64 * f64(df)) * 0.6931471805599453094172321f64 - pik_loggamma(0.5f64 * f64(df))
    ret mf_romberg(f, df, n, logc, false)
}

fn qmaxfratio_upper(f: f64, df: i64, n: i64) -> f64 {
    if f <= 0.0f64 || df < 1i64 || n < 1i64 { ret 0.0f64 / 0.0f64 }
    ret 1.0f64 - pmaxfratio(f, df, n)
}

fn fmaxfratio(f: f64, df: i64, n: i64) -> f64 {
    if f <= 0.0f64 || df < 1i64 || n < 1i64 { ret 0.0f64 / 0.0f64 }
    if n == 2i64 { ret 2.0f64 * nb.df(f, f64(df), f64(df), false) }
    let logc = math.log[f64](f64(n * (n - 1i64))) - f64(df) * 0.6931471805599453094172321f64 - 2.0f64 * pik_loggamma(f64(df) / 2.0f64)
    ret mf_romberg(f, df, n, logc, true)
}

// the Johnson parameters (gamma, delta, xi, lambda, kind: 2 SB, 3 SU) closest to df and N, the starting point of the Newton inversion
fn mf_start(p: f64, df: i64, n: i64) -> f64 {
    var gm: [28]f64 = zero
    var dl: [28]f64 = zero
    var xi: [28]f64 = zero
    var lm: [28]f64 = zero
    var kd: [28]u8 = zero
    let tab = "-1.019 0.510 2.750 0.915 3|-1.000 0.512 7.904 2.941 3|-0.996 0.512 14.124 5.302 3|-0.995 0.512 21.008 7.887 3|-1.542 0.834 1.425 0.616 3|-1.403 0.857 2.919 1.519 3|-1.372 0.862 4.317 2.235 3|-1.358 0.865 5.612 2.858 3|-2.892 1.252 0.927 0.271 3|-2.043 1.302 1.625 0.872 3|-1.931 1.314 2.184 1.175 3|-1.883 1.319 2.649 1.395 3|4.014 1.447 0.862 15.467 2|-3.054 1.848 1.127 0.523 3|-2.712 1.860 1.439 0.705 3|-2.571 1.862 1.681 0.814 3|2.995 1.509 0.896 4.930 2|-5.061 2.518 0.884 0.268 3|-3.699 2.480 1.126 0.457 3|-3.524 2.497 1.261 0.514 3|2.439 1.528 0.927 2.357 2|8.346 2.888 0.832 13.668 2|-6.664 3.306 0.907 0.209 3|-4.496 3.145 1.083 0.348 3|2.326 1.620 0.937 1.515 2|8.411 3.231 0.851 7.635 2|-7.810 3.947 0.880 0.163 3|-4.428 3.497 1.062 0.277 3"
    var entry = 0usize
    var field = 0usize
    var i = 0usize
    var cur = 0.0f64
    var neg = false
    var frac = 0.0f64
    var infrac = false
    while i <= tab.len {
        var ch = 124u8
        if i < tab.len { ch = tab[i] }
        if ch == 32u8 || ch == 124u8 {
            var v = cur
            if neg { v = 0.0f64 - cur }
            if field == 0usize { gm[entry] = v }
            if field == 1usize { dl[entry] = v }
            if field == 2usize { xi[entry] = v }
            if field == 3usize { lm[entry] = v }
            if field == 4usize { kd[entry] = u8(v) }
            field += 1usize
            cur = 0.0f64
            neg = false
            infrac = false
            frac = 0.0f64
            if ch == 124u8 {
                entry += 1usize
                field = 0usize
            }
        } else if ch == 45u8 {
            neg = true
        } else if ch == 46u8 {
            infrac = true
            frac = 0.1f64
        } else {
            let dgt = f64(ch - 48u8)
            if infrac {
                cur = cur + dgt * frac
                frac = frac / 10.0f64
            } else {
                cur = cur * 10.0f64 + dgt
            }
        }
        i += 1usize
    }
    var col = i64(math.floor[f64](0.5f64 + f64(n) / 3.0f64)) - 1i64
    if col < 0i64 { col = 0i64 }
    if col > 3i64 { col = 3i64 }
    let ddf = math.log[f64](f64(df)) / 0.69314718055994172321f64
    var row = i64(math.floor[f64](0.5f64 + ddf)) - 1i64
    if row < 0i64 { row = 0i64 }
    if row > 6i64 { row = 6i64 }
    let at = usize(row * 4i64 + col)
    ret qjohnson(p, gm[at], dl[at], xi[at], lm[at], kd[at])
}

// the quantile by Newton's method from the Johnson fit; NaN beyond df 160 or N 24, as the package answers
fn xmaxfratio(p: f64, df: i64, n: i64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 || df < 1i64 || n < 1i64 { ret 0.0f64 / 0.0f64 }
    if n == 2i64 { ret nb.qf(1.0f64 - 0.5f64 * (1.0f64 - p), f64(df), f64(df), true, false) }
    if df > 160i64 || n > 24i64 { ret 0.0f64 / 0.0f64 }
    var x = mf_start(p, df, n)
    if x < 1.000001f64 { x = 1.000001f64 }
    var ho = 1.0e6f64
    var m = 0i64
    var going = true
    while going {
        let h = (p - pmaxfratio(x, df, n)) / fmaxfratio(x, df, n)
        x = x + h
        var more = math.abs[f64](h / x) > 3.0e-8f64
        if ho < math.abs[f64](h) {
            more = false
            x = x - h
        }
        ho = math.abs[f64](h)
        let prev = m
        m += 1i64
        if prev > 20i64 || !more { going = false }
    }
    if x < 1.0f64 { x = 1.000001f64 }
    ret x
}

// ---- Friedman's chi-square for r treatments in n blocks: the exact Kendall-Babington Smith distribution where the package has it
// (r = 3 with n <= 30, r = 4 with n <= 15, r = 5 with n <= 8), Walsh's beta approximation elsewhere ----

type Fdist = struct { has: bool, s: []i64, q: []f64 }

fn friedman_exact_ok(r: i64, n: i64) -> bool {
    if r == 3i64 { ret n <= 30i64 }
    if r == 4i64 { ret n <= 15i64 }
    if r == 5i64 { ret n <= 8i64 }
    ret false
}

// the permutations of the base ranks (r! rows of r values, row-major); the base is the centred ranks, doubled for even r
fn friedman_perms(a: *mem.Arena, r: usize) -> ([]i64, usize, err) {
    var np = 1usize
    var i = 2usize
    while i <= r {
        np *= i
        i += 1usize
    }
    let (out, e) = mem.alloc[i64](a, np * r)
    if e != ok { ret (out, 0usize, e) }
    var step = 1i64
    var x0 = (1i64 - i64(r)) / 2i64
    if r % 2usize == 0usize {
        step = 2i64
        x0 = 1i64 - i64(r)
    }
    var idx: [8]usize = zero
    i = 0usize
    while i < r {
        idx[i] = i
        i += 1usize
    }
    // Heap-style enumeration by lexicographic next permutation
    var row = 0usize
    var going = true
    while going {
        i = 0usize
        while i < r {
            out[row * r + i] = x0 + step * i64(idx[i])
            i += 1usize
        }
        row += 1usize
        var k = r - 1usize
        var found = false
        while k > 0usize && !found {
            if idx[k - 1usize] < idx[k] { found = true } else { k -= 1usize }
        }
        if !found {
            going = false
        } else {
            let pivot = k - 1usize
            var l = r - 1usize
            while idx[l] < idx[pivot] { l -= 1usize }
            let t = idx[pivot]
            idx[pivot] = idx[l]
            idx[l] = t
            var lo = k
            var hi = r - 1usize
            while lo < hi {
                let u = idx[lo]
                idx[lo] = idx[hi]
                idx[hi] = u
                lo += 1usize
                hi -= 1usize
            }
        }
    }
    ret (out, np, ok)
}

// the exact distribution: states are the sorted column sums of centred ranks, frequencies are carried in doubles as the package does
fn friedman_exact(a: *mem.Arena, r: i64, n: i64) -> (Fdist, err) {
    var res: Fdist = zero
    if !friedman_exact_ok(r, n) { ret (res, ok) }
    let ru = usize(r)
    let (perms, np, pe) = friedman_perms(a, ru)
    if pe != ok { ret (res, pe) }
    let cap = 400000usize
    let (keys, e1) = mem.alloc[u64](a, cap * 2usize)
    let (freq, e2) = mem.alloc[f64](a, cap * 2usize)
    let (cur_key, e3) = mem.alloc[u64](a, cap)
    let (cur_freq, e4) = mem.alloc[f64](a, cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (res, e1) }
    var base: [8]i64 = zero
    var i = 0usize
    while i < ru {
        base[i] = perms[i]
        i += 1usize
    }
    // the first generation: the base itself (sorted ascending), frequency 1
    var ncur = 1usize
    var v: [8]i64 = zero
    i = 0usize
    while i < ru {
        v[i] = base[i]
        i += 1usize
    }
    cur_key[0usize] = pack_sorted(v[0usize..ru])
    cur_freq[0usize] = 1.0f64
    var gen = 1i64
    while gen < n {
        var q = 0usize
        while q < cap * 2usize {
            keys[q] = 0u64
            freq[q] = 0.0f64
            q += 1usize
        }
        var nxt = 0usize
        var c = 0usize
        while c < ncur {
            unpack_sorted(cur_key[c], v[0usize..ru])
            var p = 0usize
            while p < np {
                var w: [8]i64 = zero
                i = 0usize
                while i < ru {
                    w[i] = v[i] + perms[p * ru + i]
                    i += 1usize
                }
                // insertion sort of w
                var s1 = 1usize
                while s1 < ru {
                    let t = w[s1]
                    var s2 = s1
                    while s2 > 0usize && w[s2 - 1usize] > t {
                        w[s2] = w[s2 - 1usize]
                        s2 -= 1usize
                    }
                    w[s2] = t
                    s1 += 1usize
                }
                let kk = pack_sorted(w[0usize..ru]) + 1u64
                var h = usize((kk *% 11400714819323198485u64) >> 40u64) % (cap * 2usize)
                while keys[h] != 0u64 && keys[h] != kk { h = (h + 1usize) % (cap * 2usize) }
                if keys[h] == 0u64 {
                    keys[h] = kk
                    nxt += 1usize
                    if nxt >= cap { ret (res, mem.Invalid) }
                }
                freq[h] = freq[h] + cur_freq[c]
                p += 1usize
            }
            c += 1usize
        }
        var m = 0usize
        q = 0usize
        while q < cap * 2usize {
            if keys[q] != 0u64 {
                cur_key[m] = keys[q] - 1u64
                cur_freq[m] = freq[q]
                m += 1usize
            }
            q += 1usize
        }
        ncur = m
        gen += 1i64
    }
    // S per state, then by S ascending with the upper-tail sums
    let (sv, e5) = mem.alloc[i64](a, ncur)
    if e5 != ok { ret (res, e5) }
    let (ord, e6) = mem.alloc[usize](a, ncur)
    if e6 != ok { ret (res, e6) }
    var c2 = 0usize
    while c2 < ncur {
        unpack_sorted(cur_key[c2], v[0usize..ru])
        var s = 0i64
        i = 0usize
        while i < ru {
            s += v[i] * v[i]
            i += 1usize
        }
        sv[c2] = s
        ord[c2] = c2
        c2 += 1usize
    }
    // sort the states by S (insertion sort is too slow at 40k states: use a shell sort)
    var gap = ncur / 2usize
    while gap > 0usize {
        var ii = gap
        while ii < ncur {
            let t = ord[ii]
            var jj = ii
            while jj >= gap && sv[ord[jj - gap]] > sv[t] {
                ord[jj] = ord[jj - gap]
                jj -= gap
            }
            ord[jj] = t
            ii += 1usize
        }
        gap = gap / 2usize
    }
    let total = math.exp[f64](f64(n - 1i64) * pik_loggamma(f64(r + 1i64)))
    let (qt, e7) = mem.alloc[f64](a, ncur)
    if e7 != ok { ret (res, e7) }
    var sum = 0.0f64
    var t2 = ncur
    while t2 > 0usize {
        t2 -= 1usize
        sum += cur_freq[ord[t2]] / total
        qt[t2] = sum
    }
    // pool equal S: the first (lowest) entry of a group carries the cumulative from there up
    let (ss, e8) = mem.alloc[i64](a, ncur)
    let (qq, e9) = mem.alloc[f64](a, ncur)
    if e8 != ok || e9 != ok { ret (res, e8) }
    var j = 0usize
    var cs = sv[ord[0usize]]
    var cq = qt[0usize]
    var ii2 = 1usize
    while ii2 < ncur {
        if cs != sv[ord[ii2]] {
            ss[j] = cs
            qq[j] = cq
            cs = sv[ord[ii2]]
            cq = qt[ii2]
            j += 1usize
        }
        ii2 += 1usize
    }
    ss[j] = cs
    qq[j] = cq
    res.has = true
    res.s = ss[0usize..j + 1usize]
    res.q = qq[0usize..j + 1usize]
    ret (res, ok)
}

fn pack_sorted(v: []const i64) -> u64 {
    var k = 0u64
    var i = 0usize
    while i < v.len {
        k = k * 256u64 + u64(v[i] + 128i64)
        i += 1usize
    }
    ret k
}

fn unpack_sorted(k0: u64, v: []i64) {
    var k = k0
    var i = v.len
    while i > 0usize {
        i -= 1usize
        v[i] = i64(k % 256u64) - 128i64
        k = k / 256u64
    }
}

fn friedman_find_s(ss: i64, max_s: i64, s: []const i64, ns: usize, lower: bool) -> usize {
    let guess = f64(ss) / f64(max_s)
    var k = usize(f64(ns - 1usize) * guess)
    if k > ns - 1usize { k = ns - 1usize }
    var larger = false
    if lower { larger = s[k] > ss } else { larger = s[k] >= ss }
    while larger {
        if k == 0usize { ret k }
        if !lower && ss == s[k] { ret k }
        k -= 1usize
        larger = s[k] > ss
        if !larger {
            if lower { ret k + 1usize }
            ret k
        }
    }
    while !larger {
        if k == ns - 1usize { ret k }
        k += 1usize
        if lower { larger = s[k] > ss } else { larger = s[k] >= ss }
        if larger {
            if lower || s[k] == ss { ret k }
            ret k - 1usize
        }
    }
    ret 0usize
}

fn friedman_ss(x: f64, r: i64, n: i64, rho: bool) -> i64 {
    var ss = i64(0.5f64 + x * f64(n * r * (r + 1i64)) / 12.0f64)
    if rho { ss = i64(0.5f64 + (f64(r * (r * r - 1i64)) / 6.0f64) * (1.0f64 + x)) }
    if r % 2i64 == 0i64 { ss = ss * 4i64 }
    ret ss
}

fn friedman_m(r: i64, n: i64) -> f64 { ret f64(n * n * r * (r * r - 1i64)) / 12.0f64 }

// the lower tail up to and including X
fn pfrie(d: *const Fdist, x: f64, r: i64, n0: i64, rho: bool) -> f64 {
    var n = n0
    if rho { n = 2i64 }
    if r < 3i64 || n < 2i64 { ret 0.0f64 / 0.0f64 }
    let m = friedman_m(r, n)
    var s = x * f64(n * r * (r + 1i64)) / 12.0f64
    if rho { s = (m / 2.0f64) * (1.0f64 + x) }
    if s > m || s < 0.0f64 { ret 0.0f64 / 0.0f64 }
    var is_ = i64(math.ceil[f64](s))
    is_ = 2i64 * (is_ / 2i64)
    s = f64(is_)
    if s < 1.0f64 { s = 1.0f64 }
    if d.has {
        let ss = friedman_ss(x, r, n, rho)
        let k = friedman_find_s(ss, d.s[d.s.len - 1usize], d.s, d.s.len, true)
        ret 1.0f64 - d.q[k]
    }
    let w = (s - 1.0f64) / (m + 2.0f64)
    let aa = f64(r - 1i64) - 2.0f64 / f64(n)
    let bb = aa * f64(n - 1i64)
    ret 1.0f64 - nb.pbeta(1.0f64 - w, bb / 2.0f64, aa / 2.0f64, true, false)
}

// the upper tail excluding X
fn qfrie(d: *const Fdist, x: f64, r: i64, n0: i64, rho: bool) -> f64 {
    var n = n0
    if rho { n = 2i64 }
    if r < 3i64 || n < 2i64 { ret 0.0f64 / 0.0f64 }
    let m = friedman_m(r, n)
    var s = x * f64(n * r * (r + 1i64)) / 12.0f64
    if rho { s = (m / 2.0f64) * (1.0f64 + x) }
    if s > m || s < 0.0f64 { ret 0.0f64 / 0.0f64 }
    var is_ = i64(math.floor[f64](s))
    is_ = 2i64 * (is_ / 2i64)
    s = f64(is_)
    if s < 1.0f64 { s = 1.0f64 }
    if d.has {
        let ss = friedman_ss(x, r, n, rho)
        let k = friedman_find_s(ss, d.s[d.s.len - 1usize], d.s, d.s.len, true)
        ret d.q[k]
    }
    let w = (s - 1.0f64) / (m + 2.0f64)
    let aa = f64(r - 1i64) - 2.0f64 / f64(n)
    let bb = aa * f64(n - 1i64)
    ret nb.pbeta(1.0f64 - w, bb / 2.0f64, aa / 2.0f64, true, false)
}

// the probability mass at X (exact) or the difference of the approximation's cdf
fn ffrie(d: *const Fdist, x: f64, r: i64, n0: i64, rho: bool) -> f64 {
    var n = n0
    if rho { n = 2i64 }
    if r < 3i64 || n < 2i64 { ret 0.0f64 / 0.0f64 }
    let m = friedman_m(r, n)
    var s = x * f64(n * r * (r + 1i64)) / 12.0f64
    if rho { s = (m / 2.0f64) * (1.0f64 + x) }
    if s > m || s < 0.0f64 { ret 0.0f64 / 0.0f64 }
    s = s - 2.0f64
    var is_ = i64(math.floor[f64](s))
    is_ = 2i64 * (is_ / 2i64)
    s = f64(is_)
    if s < 1.0f64 { s = 1.0f64 }
    if d.has {
        let ss = friedman_ss(x, r, n, rho)
        let k = friedman_find_s(ss, d.s[d.s.len - 1usize], d.s, d.s.len, false)
        var f = d.q[k]
        if k < d.s.len - 1usize { f = f - d.q[k + 1usize] }
        ret f
    }
    let w = (s - 1.0f64) / (m + 2.0f64)
    let aa = f64(r - 1i64) - 2.0f64 / f64(n)
    let bb = aa * f64(n - 1i64)
    ret nb.pbeta(1.0f64 - w, bb / 2.0f64, aa / 2.0f64, true, false) - nb.pbeta(1.0f64 - w - 2.0f64 / (m + 2.0f64), bb / 2.0f64, aa / 2.0f64, true, false)
}

// the quantile: a step search on the distribution function from the beta approximation's guess
fn xfrie(d: *const Fdist, p: f64, r: i64, n: i64) -> f64 {
    if r < 3i64 || n < 2i64 { ret 0.0f64 / 0.0f64 }
    let m = friedman_m(r, n)
    let aa = f64(r - 1i64) - 2.0f64 / f64(n)
    let bb = aa * f64(n - 1i64)
    let w = 1.0f64 - nb.qbeta(1.0f64 - p, bb / 2.0f64, aa / 2.0f64, true, false)
    var s = 1.0f64 + (m + 2.0f64) * w
    var is_ = i64(math.ceil[f64](s))
    if 0.0f64 > p || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    is_ = 2i64 * (is_ / 2i64)
    s = f64(is_)
    if s < 1.0f64 { s = 1.0f64 }
    let step = 12.0f64 / f64(n * r * (r + 1i64))
    let mx = m * step
    var x = s * step
    if x < 0.0f64 { x = 0.0f64 }
    if x > mx { x = mx }
    var larger = p <= pfrie(d, x, r, n, false)
    while larger {
        if x <= 0.0f64 { ret 0.0f64 }
        x = x - step
        if x < 0.0f64 {
            larger = false
        } else {
            larger = p <= pfrie(d, x, r, n, false)
        }
        if !larger {
            x = x + step
            ret x
        }
    }
    while !larger {
        if x + step >= mx { ret mx }
        x = x + step
        larger = p <= pfrie(d, x, r, n, false)
        if larger { ret x }
    }
    ret 0.0f64
}

// ---- the moments the s* functions return: mean, median, mode, variance and the third and fourth central moments ----

type Mom = struct { mean: f64, median: f64, mode: f64, variance: f64, third: f64, fourth: f64 }

// a density and the power of (x - centre) weighting it, for the package's Romberg integral (tolerance 1e-4)
type MomCtx = struct { kind: u8, centre: f64, df: i64, k: i64, c: i64, n: i64, u: f64, ns: bool, g: f64, dl: f64, xi: f64, lm: f64, jk: u8, rho: f64 }

fn mom_density(c: *MomCtx, x: f64) -> f64 {
    if c.kind == 0u8 { ret fmaxfratio(x, c.df, c.k) }
    ret djohnson(x, c.g, c.dl, c.xi, c.lm, c.jk)
}

fn mom_power(c: *MomCtx, x: f64, pw: i64) -> f64 {
    var f = mom_density(c, x)
    if pw == 1i64 { ret x * f }
    let d = x - c.centre
    var i = 0i64
    while i < pw {
        f = f * d
        i += 1i64
    }
    ret f
}

fn mom_p1(c: *MomCtx, x: f64) -> f64 { ret mom_power(c, x, 1i64) }
fn mom_p2(c: *MomCtx, x: f64) -> f64 { ret mom_power(c, x, 2i64) }
fn mom_p3(c: *MomCtx, x: f64) -> f64 { ret mom_power(c, x, 3i64) }
fn mom_p4(c: *MomCtx, x: f64) -> f64 { ret mom_power(c, x, 4i64) }

// FindDistributionMode: the largest density over 128 equally spaced points of [lo, hi]
fn mom_mode(c: *MomCtx, lo: f64, hi: f64) -> f64 {
    var mode = 0.0f64
    var fmode = 0.0f64 - 1.0f64
    let step = (hi - lo) / 127.0f64
    var x = lo
    var i = 0usize
    while i < 128usize {
        let v = mom_density(c, x)
        if v > fmode {
            fmode = v
            mode = x
        }
        x = x + step
        i += 1usize
    }
    ret mode
}

fn mom_integrals(c: *MomCtx, lo: f64, hi: f64, m: *Mom) {
    c.centre = 0.0f64
    m.mean = romberg[MomCtx](c, mom_p1, lo, hi, 0.0001f64)
    c.centre = m.mean
    m.variance = romberg[MomCtx](c, mom_p2, lo, hi, 0.0001f64)
    m.third = romberg[MomCtx](c, mom_p3, lo, hi, 0.0001f64)
    m.fourth = romberg[MomCtx](c, mom_p4, lo, hi, 0.0001f64)
}

// sinvGauss
fn moments_inv_gauss(nu: f64, lam: f64) -> Mom {
    var m: Mom = zero
    let factor = nu * nu / lam
    let vr = nu * factor
    let k3 = 3.0f64 * vr * factor
    let k4 = 5.0f64 * k3 * factor
    m.mean = nu
    m.median = qinv_gauss(0.5f64, nu, lam)
    m.variance = vr
    m.mode = 0.0f64 - 1.5f64 * factor + nu * math.sqrt[f64](1.0f64 + 2.25f64 * (nu / lam) * (nu / lam))
    m.third = k3
    m.fourth = k4 + 3.0f64 * vr * vr
    ret m
}

// sJohnson; kind 0 SN, 1 SL, 2 SB, 3 SU as in djohnson
fn moments_johnson(gamma0: f64, delta: f64, xi0: f64, lambda: f64, kind: u8) -> Mom {
    var m: Mom = zero
    var gamma = gamma0
    if math.abs[f64](gamma) < 1.0e-15f64 { gamma = 0.0f64 }
    var xi = xi0
    if math.abs[f64](xi) < 1.0e-15f64 { xi = 0.0f64 }
    let w = math.exp[f64](1.0f64 / (delta * delta))
    let gd = gamma / delta
    let egd = math.exp[f64](0.0f64 - gd)
    if kind == 0u8 {
        m.mean = xi - gamma * lambda / delta
        m.median = m.mean
        m.mode = m.mean
        var v = lambda / delta
        v = v * v
        m.variance = v
        m.third = 0.0f64
        m.fourth = 3.0f64 * v * v
        ret m
    }
    if kind == 1u8 {
        m.mean = xi + math.sqrt[f64](w) * egd * lambda
        m.median = xi + egd * lambda
        m.mode = xi + lambda * egd / w
        m.variance = w * (w - 1.0f64) * egd * egd * lambda * lambda
        m.third = egd * egd * egd * math.sqrt[f64](w * w * w) * (w - 1.0f64) * (w - 1.0f64) * (w + 2.0f64)
        m.third = m.third * lambda * lambda * lambda
        m.fourth = m.variance * m.variance * (((w + 2.0f64) * w + 3.0f64) * w * w - 3.0f64)
        ret m
    }
    let lo = qjohnson(0.001f64, gamma0, delta, xi0, lambda, kind)
    let hi = qjohnson(0.999f64, gamma0, delta, xi0, lambda, kind)
    var c = MomCtx { kind: 1u8, centre: 0.0f64, df: 0i64, k: 0i64, c: 0i64, n: 0i64, u: 0.0f64, ns: false, g: gamma0, dl: delta, xi: xi0, lm: lambda, jk: kind, rho: 0.0f64 }
    m.mode = mom_mode(&c, lo, hi)
    if kind == 3u8 {
        let sh = (math.exp[f64](gd) - math.exp[f64](0.0f64 - gd)) / 2.0f64
        let ch = (math.exp[f64](gd) + math.exp[f64](0.0f64 - gd)) / 2.0f64
        m.mean = xi - lambda * math.sqrt[f64](w) * sh
        let c2 = (math.exp[f64](2.0f64 * gd) + math.exp[f64](0.0f64 - 2.0f64 * gd)) / 2.0f64
        m.variance = 0.5f64 * lambda * lambda * (w - 1.0f64) * (w * c2 + 1.0f64)
        m.median = xi - lambda * sh
        let s3 = (math.exp[f64](3.0f64 * gd) - math.exp[f64](0.0f64 - 3.0f64 * gd)) / 2.0f64
        var t3 = 0.25f64 * math.sqrt[f64](w) * (w - 1.0f64) * (w - 1.0f64) * (w * (w + 2.0f64) * s3 + 3.0f64 * sh)
        t3 = t3 * lambda * lambda * lambda
        if gamma >= 0.0f64 { t3 = 0.0f64 - t3 }
        m.third = t3
        let c4 = (math.exp[f64](4.0f64 * gd) + math.exp[f64](0.0f64 - 4.0f64 * gd)) / 2.0f64
        var t4 = 0.125f64 * (w - 1.0f64) * (w - 1.0f64) * (w * w * (((w + 2.0f64) * w + 3.0f64) * w * w - 3.0f64) * c4 + 4.0f64 * w * w * (w + 2.0f64) * c2 + 3.0f64 * (2.0f64 * w + 1.0f64))
        t4 = t4 * lambda * lambda * lambda * lambda
        m.fourth = t4
        ret m
    }
    mom_integrals(&c, lo, hi, &m)
    m.median = qjohnson(0.5f64, gamma0, delta, xi0, lambda, kind)
    ret m
}

// smaxFratio
fn moments_maxfratio(df: i64, k: i64) -> Mom {
    var m: Mom = zero
    if df < 1i64 || k < 1i64 {
        let nan = 0.0f64 / 0.0f64
        m.mean = nan
        m.median = nan
        m.mode = nan
        m.variance = nan
        m.third = nan
        m.fourth = nan
        ret m
    }
    let lo = xmaxfratio(0.01f64, df, k)
    let hi = xmaxfratio(0.99f64, df, k)
    var c = MomCtx { kind: 0u8, centre: 0.0f64, df: df, k: k, c: 0i64, n: 0i64, u: 0.0f64, ns: false, g: 0.0f64, dl: 0.0f64, xi: 0.0f64, lm: 0.0f64, jk: 0u8, rho: 0.0f64 }
    mom_integrals(&c, lo, hi, &m)
    m.median = xmaxfratio(0.5f64, df, k)
    m.mode = mom_mode(&c, lo, hi)
    ret m
}

// sKruskalWallis / sNormScore: the mean is c - 1, the median the quantile, the variance the approximation's, the mode and the third and fourth
// central moments from 128 equally spaced points between the 1% and 99% quantiles
fn moments_kruskal_wallis(c: i64, n: i64, u: f64, ns: bool) -> Mom {
    var m: Mom = zero
    m.mean = f64(c - 1i64)
    m.median = xkruskal_wallis(0.5f64, c, n, u, ns)
    if u <= 0.0f64 || u > kw_max_u(c, n) {
        let nan = 0.0f64 / 0.0f64
        m.mode = nan
        m.variance = nan
        m.third = nan
        m.fourth = nan
        ret m
    }
    if ns { m.variance = var_normal_scores(f64(n), f64(c), u) } else { m.variance = var_kruskal_wallis(f64(n), f64(c), u) }
    let min_h = xkruskal_wallis(0.01f64, c, n, u, ns)
    let max_h = xkruskal_wallis(0.99f64, c, n, u, ns)
    var md = 0.0f64
    var max_v = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    var sum = 0.0f64
    let delta = (max_h - min_h) / 127.0f64
    var h = min_h
    var i = 0usize
    while i < 128usize {
        let val = fkruskal_wallis(h, c, n, u, ns)
        if max_v < val {
            max_v = val
            md = h
        }
        sum += val
        let dh = h - m.mean
        m3 += val * dh * dh * dh
        m4 += val * dh * dh * dh * dh
        h = h + delta
        i += 1usize
    }
    m.mode = md
    m.third = m3 / sum
    m.fourth = m4 / sum
    ret m
}

// sFriedman (rho false): the Friedman statistic; the median interpolates between support points on the exact distribution
fn moments_friedman(d: *const Fdist, r: i64, n: i64) -> Mom {
    var m: Mom = zero
    if r < 3i64 || n < 2i64 {
        let nan = 0.0f64 / 0.0f64
        m.mean = nan
        m.median = nan
        m.mode = nan
        m.variance = nan
        m.third = nan
        m.fourth = nan
        ret m
    }
    let rr = f64(r)
    let nn = f64(n)
    m.mean = rr - 1.0f64
    // medianfrie
    if !friedman_exact_ok(r, n) {
        m.median = xfrie(d, 0.5f64, r, n)
    } else {
        let high = xfrie(d, 0.5f64, r, n)
        let phigh = pfrie(d, high, r, n, false)
        var low = high
        var same = true
        var plow = 0.0f64
        var two_s = 24.0f64 / (nn * rr * (rr + 1.0f64))
        if r % 2i64 == 0i64 { two_s = two_s * 4.0f64 }
        while same {
            low = low - two_s
            plow = pfrie(d, low, r, n, false)
            same = phigh == plow
        }
        let alpha = (phigh - 0.5f64) / (phigh - plow)
        m.median = alpha * low + (1.0f64 - alpha) * high
    }
    // modefrie
    let max_x = nn * (rr - 1.0f64)
    var mode = 0.0f64
    var mode_val = 0.0f64
    let step = max_x / 127.0f64
    var x = 0.0f64
    var i = 0usize
    while i < 128usize {
        let cur = ffrie(d, x, r, n, false)
        if mode_val < cur {
            mode_val = cur
            mode = x
        }
        x = x + step
        i += 1usize
    }
    m.mode = mode
    m.variance = f64(2i64 * (r - 1i64) * (n - 1i64)) / nn
    m.third = m.variance * f64(4i64 * (n - 2i64)) / nn
    m.fourth = m.variance * (rr - 1.0f64) / (nn * nn) * (f64(72i64 + r * (0i64 - 35i64 + r * (0i64 - 38i64 + r * 25i64))) / f64(25i64 * r * (r * r - 1i64)) + f64(2i64 * (r - 1i64) * (n - 2i64)) + 0.5f64 * f64((r + 3i64) * (n - 2i64) * (n - 3i64)))
    ret m
}

// sSpearman (rho true): the Friedman code with n = 2 and the rho scale
fn moments_spearman(r: i64) -> Mom {
    var m: Mom = zero
    if r < 3i64 {
        let nan = 0.0f64 / 0.0f64
        m.mean = nan
        m.median = nan
        m.mode = nan
        m.variance = nan
        m.third = nan
        m.fourth = nan
        ret m
    }
    m.mean = 0.0f64
    m.median = 0.0f64
    m.mode = 0.0f64
    m.variance = 1.0f64 / f64(r - 1i64)
    m.third = 0.0f64
    m.fourth = (3.0f64 * m.variance / f64(r - 1i64)) * (f64(72i64 + r * (0i64 - 35i64 + r * (0i64 - 38i64 + r * 25i64))) / f64(25i64 * r * (r * r - 1i64)))
    ret m
}

// scorr: the Pearson correlation
fn moments_pearson(rho: f64, nn: i64) -> Mom {
    var m: Mom = zero
    if nn < 3i64 || rho < 0.0f64 - 1.0f64 || rho > 1.0f64 {
        let nan = 0.0f64 / 0.0f64
        m.mean = nan
        m.median = nan
        m.mode = nan
        m.variance = nan
        m.third = nan
        m.fourth = nan
        ret m
    }
    let mm = 1.0f64 / (f64(nn) + 6.0f64)
    let m2 = mm * mm
    let rho2 = rho * rho
    let rho4 = rho2 * rho2
    let one_min = 1.0f64 - rho2
    let om2 = one_min * one_min
    let om3 = om2 * one_min
    let om4 = om2 * om2
    m.mean = rho - 0.5f64 * mm * rho * one_min * (1.0f64 + 2.25f64 * mm * (3.0f64 + rho2) + 0.375f64 * m2 * (121.0f64 + 70.0f64 * rho2 + 25.0f64 * rho4))
    m.median = qcorrelation(0.5f64, rho, nn)
    var best = 0.0f64
    var fbest = 0.0f64 - 1.0f64
    let step = 2.0f64 / 127.0f64
    var x = 0.0f64 - 1.0f64
    var i = 0usize
    while i < 128usize {
        let v = fcorrelation(x, rho, nn)
        if v > fbest {
            fbest = v
            best = x
        }
        x = x + step
        i += 1usize
    }
    m.mode = best
    m.third = 0.0f64 - m2 * rho * om3 * (6.0f64 + mm * (69.0f64 + 88.0f64 * rho2) + 0.75f64 * m2 * (797.0f64 + 1691.0f64 * rho2 + 1560.0f64 * rho4))
    m.fourth = 3.0f64 * m2 * om4 * (1.0f64 + mm * (12.0f64 + 35.0f64 * rho2) + 0.25f64 * m2 * (436.0f64 + 2028.0f64 * rho2 + 3025.0f64 * rho4))
    m.variance = mm * om2 * (1.0f64 + 0.5f64 * mm * (14.0f64 + 11.0f64 * rho2) + 0.5f64 * m2 * (98.0f64 + 130.0f64 * rho2 + 75.0f64 * rho4))
    ret m
}

// ---- Kendall's tau as the package answers it: exact counts up to N = 12, the Edgeworth series beyond ----

fn ken_edge_p(t: f64, n: f64, mean: f64) -> f64 {
    let s = n * (n + 1.0f64) * (2.0f64 * n + 1.0f64) / 6.0f64
    let f = ((n + 1.0f64) * 3.0f64 * n - 1.0f64) / 5.0f64
    let g = (((n * n + 2.0f64) * n - 1.0f64) * 3.0f64 * n + 1.0f64) / 7.0f64
    var sd = s - n
    let l4 = 0.0f64 - 1.2f64 * (s * f - n) / (sd * sd)
    let l6 = (48.0f64 / 7.0f64) * (s * g - n) / (sd * sd * sd)
    sd = math.sqrt[f64](sd / 12.0f64)
    let x = (t + 0.5f64 - mean) / sd
    let z = 0.398942280401433f64 * math.exp[f64](0.0f64 - 0.5f64 * x * x)
    let x2 = x * x
    let phi3 = z * x * (3.0f64 - x2)
    let phi5 = 0.0f64 - z * x * ((x2 - 10.0f64) * x2 + 15.0f64)
    let phi7 = z * x * (((0.0f64 - x2 + 21.0f64) * x2 - 105.0f64) * x2 + 105.0f64)
    var p = dist.pnorm(x, 0.0f64, 1.0f64, true, false)
    p = p + ((35.0f64 * l4 * l4 * phi7 / 56.0f64 + l6 * phi5) / 30.0f64 + l4 * phi3) / 24.0f64
    ret p
}

// the cumulative or point probability of T = k from the exact counts (n <= 12)
fn ken_exact(a: *mem.Arena, n: usize, k: usize, density: bool) -> (f64, err) {
    let (c, e) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 2usize)
    if e != ok { ret (0.0f64, e) }
    let len = mahonian(n, c)
    var sum = 0.0f64
    if density {
        if k < len { sum = c[k] }
    } else {
        var i = 0usize
        while i <= k && i < len {
            sum += c[i]
            i += 1usize
        }
    }
    ret (math.exp[f64](math.log[f64](sum) - pik_loggamma(f64(n + 1usize))), ok)
}

// pkendall(n, tau): Pr(T <= tau)
fn pkendall_pkg(a: *mem.Arena, ni: i64, tau: f64) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    if tau > 1.0f64 || tau < 0.0f64 - 1.0f64 || ni < 2i64 { ret (nan, ok) }
    let n = f64(ni)
    let mm = n * (n - 1.0f64) / 2.0f64
    let mean = mm / 2.0f64
    let kf = 0.5f64 + (1.0f64 + tau) * mean
    if kf < 0.0f64 { ret (0.0f64, ok) }
    let k = math.floor[f64](kf)
    if k > mm { ret (1.0f64, ok) }
    if ni <= 12i64 {
        let (xv, xe) = ken_exact(a, usize(ni), usize(k), false)
        ret (xv, xe)
    }
    ret (ken_edge_p(k, n, mean), ok)
}

fn fkendall_pkg(a: *mem.Arena, ni: i64, tau: f64) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    if tau > 1.0f64 || tau < 0.0f64 - 1.0f64 { ret (nan, ok) }
    let n = f64(ni)
    let mm = n * (n - 1.0f64) / 2.0f64
    let mean = mm / 2.0f64
    let kf = 0.5f64 + (1.0f64 + tau) * mean
    if kf < 0.0f64 { ret (0.0f64, ok) }
    var t = math.floor[f64](kf)
    if t > mm { ret (0.0f64, ok) }
    if ni <= 12i64 {
        let (yv, ye) = ken_exact(a, usize(ni), usize(t), true)
        ret (yv, ye)
    }
    let p1 = ken_edge_p(t, n, mean)
    t = t - 1.0f64
    var p0 = 0.0f64
    if t >= 0.0f64 { p0 = ken_edge_p(t, n, mean) }
    ret (p1 - p0, ok)
}

fn qkendall_pkg(a: *mem.Arena, ni: i64, tau: f64) -> (f64, err) {
    if tau > 1.0f64 || tau < 0.0f64 - 1.0f64 || ni < 2i64 { ret (0.0f64 / 0.0f64, ok) }
    let (p, e) = pkendall_pkg(a, ni, tau)
    ret (1.0f64 - p, e)
}

// xkendall(p, n): the smallest tau with p <= Pr(T <= tau)
fn xkendall_pkg(a: *mem.Arena, pr: f64, ni: i64) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    if 0.0f64 >= pr || pr >= 1.0f64 || ni < 2i64 { ret (nan, ok) }
    let n = f64(ni)
    let mean = 0.25f64 * n * (n - 1.0f64)
    var sd = n * (2.0f64 * n + 1.0f64) * (n + 1.0f64) / 6.0f64 - n
    sd = math.sqrt[f64](sd / 12.0f64)
    let kq = 0.5f64 + mean + sd * dist.qnorm(pr, 0.0f64, 1.0f64, true, false)
    var k = i64(kq)
    var tau = 4.0f64 * f64(k) / (n * (n - 1.0f64)) - 1.0f64
    let (p0, e0) = pkendall_pkg(a, ni, tau)
    if e0 != ok { ret (nan, e0) }
    var larger = pr <= p0
    while larger {
        if k == 0i64 { ret (4.0f64 * f64(k) / (n * (n - 1.0f64)) - 1.0f64, ok) }
        k -= 1i64
        tau = 4.0f64 * f64(k) / (n * (n - 1.0f64)) - 1.0f64
        let (p1, e1) = pkendall_pkg(a, ni, tau)
        if e1 != ok { ret (nan, e1) }
        larger = pr <= p1
        if !larger {
            k += 1i64
            ret (4.0f64 * f64(k) / (n * (n - 1.0f64)) - 1.0f64, ok)
        }
    }
    while !larger {
        k += 1i64
        tau = 4.0f64 * f64(k) / (n * (n - 1.0f64)) - 1.0f64
        let (p2, e2) = pkendall_pkg(a, ni, tau)
        if e2 != ok { ret (nan, e2) }
        larger = pr <= p2
        if larger { ret (4.0f64 * f64(k) / (n * (n - 1.0f64)) - 1.0f64, ok) }
    }
    ret (nan, ok)
}

// the fourth central moment: 128 equally spaced points between the 1% and 99% quantiles
fn fourth_kendall(a: *mem.Arena, ni: i64) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    if ni < 4i64 { ret (nan, ok) }
    let (lo, e1) = xkendall_pkg(a, 0.01f64, ni)
    let (hi, e2) = xkendall_pkg(a, 0.99f64, ni)
    if e1 != ok || e2 != ok { ret (nan, e1) }
    let delta = (hi - lo) / 127.0f64
    var tau = lo
    var m4 = 0.0f64
    var sum = 0.0f64
    var i = 0usize
    while i < 128usize {
        let (v, e) = fkendall_pkg(a, ni, tau)
        if e != ok { ret (nan, e) }
        m4 += v * tau * tau * tau * tau
        sum += v
        tau = tau + delta
        i += 1usize
    }
    ret (m4 / sum, ok)
}

// Spearman's rho is the Friedman statistic with two blocks, X = (r - 1)(1 + rho); its exact distribution (r < 12) comes from the
// counts of the sum of squared rank differences: S = c^2 (r (r^2 - 1) / 3 - D2), with c = 2 for even r (the package doubles the ranks)
fn friedman_exact_rho(a: *mem.Arena, r: i64) -> (Fdist, err) {
    var res: Fdist = zero
    if r < 3i64 || r > 11i64 { ret (res, ok) }
    let ru = usize(r)
    let smax = ru * (ru * ru - 1usize) / 3usize
    let (counts, e1) = mem.alloc[f64](a, smax + 2usize)
    if e1 != ok { ret (res, e1) }
    let se = spearman_counts(a, ru, counts)
    if se != ok { ret (res, se) }
    let scale = f64(1i64)
    var cc = 1i64
    if r % 2i64 == 0i64 { cc = 2i64 }
    let total = math.exp[f64](pik_loggamma(f64(r + 1i64)))
    // ascending S is descending D2: q[S] = Pr(S' >= S) = Pr(D2' <= D2)
    var nd = 0usize
    var d2 = 0usize
    while d2 <= smax {
        if counts[d2] > 0.0f64 { nd += 1usize }
        d2 += 1usize
    }
    let (ss, e2) = mem.alloc[i64](a, nd)
    let (qq, e3) = mem.alloc[f64](a, nd)
    if e2 != ok || e3 != ok { ret (res, e2) }
    var cum = 0.0f64
    var idx = nd
    d2 = 0usize
    while d2 <= smax {
        if counts[d2] > 0.0f64 {
            cum += counts[d2] / total
            idx -= 1usize
            ss[idx] = cc * cc * (i64(smax) - i64(d2))
            qq[idx] = cum
        }
        d2 += 1usize
    }
    res.has = true
    res.s = ss
    res.q = qq
    ret (res, ok)
}

// the Spearman functions through the Friedman ones
fn pspearman_pkg(d: *const Fdist, rho: f64, r: i64) -> f64 { ret pfrie(d, rho, r, 2i64, true) }
fn qspearman_pkg(d: *const Fdist, rho: f64, r: i64) -> f64 { ret qfrie(d, rho, r, 2i64, true) }
fn fspearman_pkg(d: *const Fdist, rho: f64, r: i64) -> f64 { ret ffrie(d, rho, r, 2i64, true) }
fn xspearman_pkg(d: *const Fdist, p: f64, r: i64) -> f64 {
    let x = xfrie(d, p, r, 2i64)
    ret x / f64(r - 1i64) - 1.0f64
}

// ---- fitting the Johnson system (Wheeler 1980 from five quantiles; Hill, Hill and Holder's AS 99 from moments) ----

type JFit = struct { gamma: f64, delta: f64, xi: f64, lambda: f64, kind: u8, ok_: bool }

fn jf_bad() -> JFit {
    var r: JFit = zero
    r.ok_ = false
    ret r
}

// Rotate3: the Givens rotation of a three element row into the 3 by 3 matrix (row-major, weights on the diagonal)
fn jf_rotate3(v: []f64, m: []f64) {
    var w = 1.0f64
    var skip = false
    var i = 0usize
    while i < 2usize {
        if !skip {
            let x = v[i]
            if x == 0.0f64 {
                i += 1usize
                continue
            }
            let d = m[i * 3usize + i]
            let dp = d + w * x * x
            m[i * 3usize + i] = dp
            let c = d / dp
            let s = w * x / dp
            if d == 0.0f64 { skip = true } else { w = w * c }
            var j = i + 1usize
            while j < 3usize {
                let r = m[i * 3usize + j]
                m[i * 3usize + j] = s * v[j] + c * r
                v[j] = v[j] - x * r
                j += 1usize
            }
        }
        i += 1usize
    }
}

// JohnsonFit(xn = x95, xm = x79.4, x0 = x50, xk = x20.6, xp = x5)
fn johnson_fit_quantiles(xn: f64, xm: f64, x0: f64, xk: f64, xp: f64) -> JFit {
    let zn = 1.64485363f64
    var res: JFit = zero
    var m: [9]f64 = zero
    var delta = 0.0f64
    var gamma = 0.0f64
    var kind = 0u8
    let t = (xn - x0) / (x0 - xp)
    var tu = (xn - xp) / (xm - xk)
    var tb = 0.5f64 * (((xm - x0) * (xn - xp)) / ((xn - xm) * (x0 - xp)) + ((xk - x0) * (xp - xn)) / ((xp - xk) * (x0 - xn)))
    let tbu = tb / tu
    if math.abs[f64](math.abs[f64](tbu) - 1.0f64) < 0.1f64 && math.abs[f64](math.abs[f64](t - 1.0f64)) < 0.1f64 {
        kind = 0u8
        delta = 1.0f64
        gamma = 0.0f64
    } else if math.abs[f64](math.abs[f64](tbu) - 1.0f64) < 0.1f64 {
        kind = 1u8
        delta = zn / math.log[f64](t)
        if delta != delta || delta > 1.0e300f64 || delta < 0.0f64 - 1.0e300f64 { ret jf_bad() }
    } else if tbu > 1.0f64 {
        kind = 2u8
        tb = tb * 0.5f64
        var b = tb + math.sqrt[f64](tb * tb - 1.0f64)
        delta = zn / (2.0f64 * math.log[f64](b))
        b = b * b
        if t > b || t < 1.0f64 / b { ret jf_bad() }
        let a = (t - b) / (1.0f64 - t * b)
        gamma = 0.0f64 - delta * math.log[f64](a)
    } else {
        kind = 3u8
        tu = tu * 0.5f64
        var b = tu + math.sqrt[f64](tu * tu - 1.0f64)
        delta = zn / (2.0f64 * math.log[f64](b))
        b = b * b
        if t > b || t < 1.0f64 / b { ret jf_bad() }
        let a = (1.0f64 - t * b) / (t - b)
        gamma = 0.0f64 - 0.5f64 * delta * math.log[f64](a)
    }
    var zs: [5]f64 = zero
    var xs: [5]f64 = zero
    zs[0usize] = zn
    xs[0usize] = xn
    zs[1usize] = zn / 2.0f64
    xs[1usize] = xm
    zs[2usize] = 0.0f64
    xs[2usize] = x0
    zs[3usize] = 0.0f64 - zn / 2.0f64
    xs[3usize] = xk
    zs[4usize] = 0.0f64 - zn
    xs[4usize] = xp
    var i = 0usize
    while i < 5usize {
        var row: [3]f64 = zero
        row[0usize] = 1.0f64
        var u = zs[i]
        if kind != 0u8 {
            if kind == 1u8 {
                u = math.exp[f64](u / delta)
            } else {
                u = math.exp[f64]((u - gamma) / delta)
                if kind == 2u8 { u = u / (1.0f64 + u) } else { u = (u * u - 1.0f64) / (2.0f64 * u) }
            }
        }
        row[1usize] = u
        row[2usize] = xs[i]
        jf_rotate3(row[0usize..3usize], m[0usize..9usize])
        i += 1usize
    }
    let lambda = m[5usize]
    res.gamma = gamma
    res.delta = delta
    res.lambda = lambda
    res.xi = m[2usize] - lambda * m[1usize]
    res.kind = kind
    res.ok_ = true
    ret res
}

// JohnsonMOM: the first six moments of the SB density by a trapezoidal series; false when it does not converge
fn jf_mom(gamma: f64, delta: f64, mo: []f64) -> bool {
    let n = 6usize
    let iter_limit = 500i64
    let inner_tol = 1.0e-8f64
    let outer_tol = 1.0e-5f64
    let recip_sqrt_pi = 0.5641895835477562869480795f64
    let exp_a = 2.3025850929940456840179915f64 * 308.0f64
    let exp_b = 0.0f64 - math.log[f64](2.220446049250313e-16f64)
    var old: [6]f64 = zero
    let w = gamma / delta
    if w > exp_a { ret false }
    var h = 0.75f64
    let exp_w = math.exp[f64](w) + 1.0f64
    if delta < 3.0f64 { h = delta / 4.0f64 }
    var count = 0i64
    var more = false
    var outer = true
    while outer {
        if count != 0i64 {
            var i = 0usize
            while i < n {
                old[i] = mo[i]
                i += 1usize
            }
            h = h * 0.5f64
        }
        var t = w
        var u = w
        var y = h * h
        let x = 2.0f64 * y
        mo[0usize] = 1.0f64 / exp_w
        var i = 1usize
        while i < n {
            mo[i] = mo[i - 1usize] / exp_w
            i += 1usize
        }
        var v = y
        let f = 1.414135623730950488f64 * h / delta
        var count_inner = 0i64
        var inner = true
        while inner {
            var b: [6]f64 = zero
            i = 0usize
            while i < n {
                b[i] = mo[i]
                i += 1usize
            }
            u = u - f
            var z = 1.0f64
            if u > 0.0f64 - exp_b { z = z + math.exp[f64](u) }
            t = t + f
            var bl = t > exp_b
            var s = 0.0f64
            if !bl { s = math.exp[f64](t) + 1.0f64 }
            var p = math.exp[f64](0.0f64 - v)
            var q = p
            i = 0usize
            while i < n {
                var aa = mo[i]
                p = p / z
                var ab = aa
                aa = aa + p
                if aa == ab { break }
                if !bl {
                    q = q / s
                    ab = aa
                    aa = aa + q
                    bl = aa == ab
                }
                mo[i] = aa
                i += 1usize
            }
            y = y + x
            v = v + y
            more = false
            i = 0usize
            while i < n {
                if mo[i] == 0.0f64 { ret false }
                if math.abs[f64](mo[i] - b[i]) / mo[i] > inner_tol { more = true }
                i += 1usize
            }
            let ci = count_inner
            count_inner += 1i64
            if !more || ci > iter_limit { inner = false }
        }
        if more { ret false }
        i = 0usize
        while i < n {
            mo[i] = mo[i] * recip_sqrt_pi * h
            i += 1usize
        }
        more = false
        i = 0usize
        while i < n {
            if mo[i] == 0.0f64 { ret false }
            if math.abs[f64](mo[i] - old[i]) / mo[i] > outer_tol { more = true }
            i += 1usize
        }
        let cc = count
        count += 1i64
        if !more || cc > iter_limit { outer = false }
    }
    ret !more
}

fn jf_pow(x: f64, e: f64) -> f64 { ret math.pow[f64](x, e) }

// JohnsonMomentSb
fn jf_moment_sb(mean: f64, sd: f64, sqrt_b1: f64, b2: f64) -> JFit {
    var res: JFit = zero
    let tol_sb = 0.01f64
    let t_tol = 1.0e-2f64
    let iter_limit = 50i64
    let abs_sqrt_b1 = math.abs[f64](sqrt_b1)
    let b1 = sqrt_b1 * sqrt_b1
    let negative_b1 = sqrt_b1 < 0.0f64
    var delta = 0.0f64
    let x = 1.0f64 + 0.5f64 * b1
    let y = abs_sqrt_b1 * math.sqrt[f64](1.0f64 + b1 / 4.0f64)
    let w0 = jf_pow(x + y, 1.0f64 / 3.0f64) + jf_pow(x - y, 1.0f64 / 3.0f64) - 1.0f64
    var f = w0 * w0 * (3.0f64 + w0 * (2.0f64 + w0)) - 3.0f64
    var e = 1.0f64 + b1
    e = (b2 - e) / (f - e)
    if abs_sqrt_b1 <= tol_sb {
        f = 2.0f64
    } else {
        delta = 1.0f64 / math.sqrt[f64](math.log[f64](w0))
        if delta < 0.64f64 {
            f = 1.25f64 * delta
        } else {
            f = 2.0f64 - 8.5245f64 / (delta * (delta * (delta - 2.163f64) + 11.346f64))
        }
    }
    f = 1.0f64 + e * f
    if f < 1.8f64 {
        delta = 0.8f64 * (f - 1.0f64)
    } else {
        delta = (0.626f64 * f - 0.408f64) * jf_pow(3.0f64 - f, 0.0f64 - 0.479f64)
    }
    var gamma = 0.0f64
    if b1 >= t_tol {
        if delta <= 1.0f64 {
            gamma = (0.7466f64 * jf_pow(delta, 1.7973f64) + 0.5955f64) * jf_pow(b1, 0.485f64)
        } else {
            if delta <= 2.5f64 {
                gamma = jf_pow(b1, 0.0623f64 * delta + 0.4043f64)
            } else {
                gamma = jf_pow(b1, 0.0124f64 * delta + 0.5291f64)
            }
            gamma = gamma * (0.9281f64 + delta * (1.0614f64 * delta - 0.7077f64))
        }
    }
    var count = 0i64
    var more = false
    var error_set = false
    var mo: [6]f64 = zero
    var h2 = 0.0f64
    var old_dg = 100.0f64
    var old_dd = 100.0f64
    var going = true
    while going {
        if jf_mom(gamma, delta, mo[0usize..6usize]) {
            h2 = mo[1usize] - mo[0usize] * mo[0usize]
            if h2 > 0.0f64 {
                let h2a = math.sqrt[f64](h2) * h2
                let h2b = h2 * h2
                let h3 = mo[2usize] - mo[0usize] * (3.0f64 * mo[1usize] - 2.0f64 * mo[0usize] * mo[0usize])
                let rbet = h3 / h2a
                let h4 = mo[3usize] - mo[0usize] * (4.0f64 * mo[2usize] - mo[0usize] * (6.0f64 * mo[1usize] - 3.0f64 * mo[0usize] * mo[0usize]))
                let bet2 = h4 / h2b
                let w = gamma * delta
                let u = delta * delta
                var dd: [6]f64 = zero
                var deriv: [6]f64 = zero
                var j = 0usize
                while j < 2usize {
                    var k = 0usize
                    while k < 4usize {
                        let t = f64(k)
                        var s = 0.0f64
                        if j == 0usize {
                            s = mo[k + 1usize] - mo[k]
                        } else {
                            s = ((w - t) * (mo[k] - mo[k + 1usize]) + (1.0f64 + t) * (mo[k + 1usize] - mo[k + 2usize])) / u
                        }
                        dd[k] = t * s / delta
                        k += 1usize
                    }
                    let t = 2.0f64 * mo[0usize] * dd[0usize]
                    let s = mo[0usize] * dd[1usize]
                    let yy = dd[1usize] - t
                    deriv[j] = (dd[2usize] - 3.0f64 * (s + mo[1usize] * dd[0usize] - t * mo[0usize]) - 1.5f64 * h3 * yy / h2) / h2a
                    deriv[j + 2usize] = (dd[3usize] - 4.0f64 * (dd[2usize] * mo[0usize] + dd[0usize] * mo[2usize]) + 6.0f64 * (mo[1usize] * t + mo[0usize] * (s - t * mo[0usize])) - 2.0f64 * h4 * yy / h2) / h2b
                    j += 1usize
                }
                let tt = 1.0f64 / (deriv[0usize] * deriv[3usize] - deriv[1usize] * deriv[2usize])
                var delta_gamma = (deriv[3usize] * (rbet - abs_sqrt_b1) - deriv[1usize] * (bet2 - b2)) * tt
                var delta_delta = (deriv[0usize] * (bet2 - b2) - deriv[2usize] * (rbet - abs_sqrt_b1)) * tt
                gamma = gamma - delta_gamma
                if b1 == 0.0f64 || gamma < 0.0f64 { gamma = 0.0f64 }
                delta = delta - delta_delta
                delta_gamma = math.abs[f64](delta_gamma)
                delta_delta = math.abs[f64](delta_delta)
                more = delta_gamma > t_tol || delta_delta > t_tol
                error_set = delta_gamma > old_dg || delta_delta > old_dd
                old_dg = delta_gamma
                old_dd = delta_delta
            }
        }
        let cc = count
        count += 1i64
        if !more || error_set || cc > iter_limit { going = false }
    }
    if !error_set && !more {
        res.delta = delta
        res.lambda = sd / math.sqrt[f64](h2)
        if negative_b1 {
            gamma = 0.0f64 - gamma
            mo[0usize] = 1.0f64 - mo[0usize]
        }
        res.gamma = gamma
        res.xi = mean - res.lambda * mo[0usize]
        res.kind = 2u8
        res.ok_ = true
        ret res
    }
    ret jf_bad()
}

// JohnsonMomentSu (Hill, Hill and Holder's iteration)
fn jf_moment_su(mean: f64, sd: f64, sqrt_b1: f64, b2: f64) -> JFit {
    var res: JFit = zero
    let tol_su = 0.01f64
    let b1 = sqrt_b1 * sqrt_b1
    let b2m3 = b2 - 3.0f64
    var w = math.sqrt[f64](math.sqrt[f64](2.0f64 * b2 - 2.8f64 * b1 - 2.0f64) - 1.0f64)
    var m = 0.0f64
    var z = 0.0f64
    if math.abs[f64](sqrt_b1) > tol_su {
        var count = 0i64
        var going = true
        while going {
            let wp1 = w + 1.0f64
            let wm1 = w - 1.0f64
            z = wp1 * b2m3
            var v = w * (6.0f64 + w * (3.0f64 + w))
            let a = 8.0f64 * (wm1 * (3.0f64 + w * (7.0f64 + v)) - z)
            let b = 16.0f64 * (wm1 * (6.0f64 + v) - b2m3)
            m = (math.sqrt[f64](a * a - 2.0f64 * b * (wm1 * (3.0f64 + w * (9.0f64 + w * (10.0f64 + v))) - 2.0f64 * wp1 * z)) - a) / b
            z = 4.0f64 * (w + 2.0f64) * m + 3.0f64 * wp1 * wp1
            let h = 2.0f64 * m + wp1
            z = m * wm1 * (z * z) / (2.0f64 * h * h * h)
            v = w * w
            w = math.sqrt[f64](1.0f64 - 2.0f64 * (1.5f64 - b2 + (b1 * (b2 - 1.5f64 - v * (1.0f64 + 0.5f64 * v))) / z))
            w = math.sqrt[f64](w - 1.0f64)
            let cc = count
            count += 1i64
            if math.abs[f64](b1 - z) <= tol_su || cc > 100i64 { going = false }
        }
        if count > 100i64 { ret jf_bad() }
        m = m / w
        m = math.log[f64](math.sqrt[f64](m) + math.sqrt[f64](1.0f64 + m))
        if sqrt_b1 > 0.0f64 { m = 0.0f64 - m }
    }
    res.delta = math.sqrt[f64](1.0f64 / math.log[f64](w))
    let omega = m
    res.gamma = omega * res.delta
    let ch2 = (math.exp[f64](2.0f64 * omega) + math.exp[f64](0.0f64 - 2.0f64 * omega)) / 2.0f64
    res.lambda = sd / math.sqrt[f64](0.5f64 * (w - 1.0f64) * (w * ch2 + 1.0f64))
    let sh = (math.exp[f64](omega) - math.exp[f64](0.0f64 - omega)) / 2.0f64
    res.xi = mean + (0.5f64 * math.sqrt[f64](w) * sh) * res.lambda
    res.kind = 3u8
    res.ok_ = true
    ret res
}

// JohnsonMomentFit(mean, sd, sqrtB1, B2 = 3 + excess kurtosis)
fn johnson_moment_fit(mean: f64, sd: f64, sqrt_b1: f64, b2_in: f64) -> JFit {
    var res: JFit = zero
    let tolj = 0.1f64
    let b1 = sqrt_b1 * sqrt_b1
    var b2 = b2_in
    if b2 < b1 + 1.0f64 + tolj { ret jf_bad() }
    if math.abs[f64](sqrt_b1) <= tolj && math.abs[f64](b2 - 3.0f64) <= tolj {
        res.kind = 0u8
        res.gamma = 0.0f64
        res.delta = 1.0f64
        res.lambda = sd
        res.xi = mean
        res.ok_ = true
        ret res
    }
    let x = 0.5f64 * b1 + 1.0f64
    let y = math.sqrt[f64](b1 + 0.25f64 * b1 * b1)
    let u = jf_pow(x + y, 1.0f64 / 3.0f64)
    let w = u + 1.0f64 / u - 1.0f64
    let b2est = w * w * (3.0f64 + w * (2.0f64 + w)) - 3.0f64
    if b2 < 0.0f64 { b2 = b2est }
    let test = b2est - b2
    if math.abs[f64](test) < tolj {
        res.kind = 1u8
        res.lambda = 1.0f64
        res.delta = 1.0f64 / math.sqrt[f64](math.log[f64](w))
        res.gamma = 0.5f64 * res.delta * math.log[f64](w * (w - 1.0f64) / (sd * sd))
        res.xi = mean - sd / math.sqrt[f64](w - 1.0f64)
        res.ok_ = true
        ret res
    }
    if test <= 0.0f64 { ret jf_moment_su(mean, sd, sqrt_b1, b2) }
    ret jf_moment_sb(mean, sd, sqrt_b1, b2)
}

// ---- moments of the classic hypergeometric as sghyper reports them (a draws, m marked, N items) ----

fn xhyper(p: f64, a: f64, n: f64, nn: f64) -> f64 {
    let t = nmt.qchisq(1.0f64 - p, 1.0f64, true, false)
    let z = (t * (p * (1.0f64 - p) * (a * (nn - a)))) / (nn - 1.0f64)
    var x = math.floor[f64](0.5f64 + p * a + z * z)
    let min_x = math.max[f64](0.0f64, n + a - nn)
    let max_x = math.min[f64](n, a)
    x = math.min[f64](math.max[f64](x, min_x), max_x)
    var larger = p <= nb.phyper(x, n, nn - n, a, true, false)
    while larger {
        if x == min_x { ret x }
        x -= 1.0f64
        larger = p <= nb.phyper(x, n, nn - n, a, true, false)
        if !larger { ret x + 1.0f64 }
    }
    while !larger {
        x += 1.0f64
        larger = p <= nb.phyper(x, n, nn - n, a, true, false)
        if larger { ret x }
    }
    ret 0.0f64
}

fn moments_ghyper(a: f64, m: f64, nn: f64) -> Mom {
    var r: Mom = zero
    let n = math.min[f64](m, a)
    let big_a = math.max[f64](m, a)
    let b = nn - big_a
    let t = big_a + b
    r.median = xhyper(0.5f64, a, m, nn)
    var m1 = 0.0f64
    var m2 = 0.0f64
    if n > 1.0f64 { m1 = (n * big_a) / t }
    r.mean = m1
    r.mode = math.floor[f64](((n + 1.0f64) * (big_a + 1.0f64)) / (t + 2.0f64))
    if n > 2.0f64 {
        m2 = m1 * (b * (t - n)) / (t * (t - 1.0f64))
        r.variance = m2
    }
    if n > 3.0f64 { r.third = m2 * ((b - big_a) * (t - 2.0f64 * n)) / (t * (t - 2.0f64)) }
    if n > 4.0f64 {
        r.fourth = (m2 / ((t - 2.0f64) * (t - 3.0f64))) * (t * (t + 1.0f64 - 6.0f64 * n) + 3.0f64 * big_a * b * (n - 2.0f64) + 6.0f64 * n * n + (3.0f64 * big_a * b * n * (6.0f64 - n)) / t - (18.0f64 * big_a * b * n * n) / (t * t))
    }
    ret r
}

// ---- random variates, value for value with SuppDists after set.seed (one parameter set) ----

fn rv_inv_gauss(r: *rng.Rng, x: []f64, mu: f64, lambda: f64) {
    let b = 0.5f64 * mu / lambda
    let a = mu * b
    let c = 4.0f64 * mu * lambda
    let d = mu * mu
    var i = 0usize
    while i < x.len {
        x[i] = rng.norm(r)
        i += 1usize
    }
    i = 0usize
    while i < x.len {
        let u = rng.unif(r)
        let v = x[i] * x[i]
        let y = mu + a * v - b * math.sqrt[f64](c * v + d * v * v)
        if u < mu / (mu + y) { x[i] = y } else { x[i] = d / y }
        i += 1usize
    }
}

fn rv_johnson(r: *rng.Rng, x: []f64, gamma: f64, delta: f64, xi: f64, lambda: f64, kind: u8) {
    var i = 0usize
    while i < x.len {
        let z = rng.norm(r)
        let w = (z - gamma) / delta
        if kind == 0u8 {
            x[i] = xi + lambda * w
        } else if kind == 1u8 {
            x[i] = xi + math.exp[f64](w)
        } else if kind == 2u8 {
            let u = math.exp[f64](w)
            x[i] = xi + lambda * (u / (1.0f64 + u))
        } else {
            let u = math.exp[f64](w)
            x[i] = xi + lambda * ((u * u - 1.0f64) / (2.0f64 * u))
        }
        i += 1usize
    }
}

fn rv_maxfratio(r: *rng.Rng, x: []f64, df: i64, k: i64) {
    var i = 0usize
    while i < x.len {
        var hi = 0.0f64 - 1.0f64
        var lo = 1.0e20f64
        var j = 0i64
        while j < k {
            let c = rd.rchisq(r, f64(df))
            if c > hi { hi = c }
            if c < lo { lo = c }
            j += 1i64
        }
        x[i] = hi / lo
        i += 1usize
    }
}

fn rv_corr(a: *mem.Arena, r: *rng.Rng, x: []f64, rho: f64, n: usize) -> err {
    let (xs, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    let (ys, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    let sy = math.sqrt[f64](1.0f64 - rho * rho)
    var i = 0usize
    while i < x.len {
        var j = 0usize
        while j < n {
            xs[j] = rng.norm(r)
            j += 1usize
        }
        j = 0usize
        while j < n {
            ys[j] = rng.rnorm(r, 0.0f64, sy) + rho * xs[j]
            j += 1usize
        }
        var sxx = 0.0f64
        var syy = 0.0f64
        var sxy = 0.0f64
        var xm = 0.0f64
        var ym = 0.0f64
        j = 0usize
        while j < n {
            let di = f64(j + 1usize)
            let dx = xs[j] - xm
            let dy = ys[j] - ym
            xm += dx / di
            ym += dy / di
            let dxu = xs[j] - xm
            sxx += dx * dxu
            syy += dy * (ys[j] - ym)
            sxy += dy * dxu
            j += 1usize
        }
        x[i] = sxy / math.sqrt[f64](sxx * syy)
        i += 1usize
    }
    ret ok
}
