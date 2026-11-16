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

fn friedman_ss(x: f64, r: i64, n: i64) -> i64 {
    var ss = i64(0.5f64 + x * f64(n * r * (r + 1i64)) / 12.0f64)
    if r % 2i64 == 0i64 { ss = ss * 4i64 }
    ret ss
}

fn friedman_m(r: i64, n: i64) -> f64 { ret f64(n * n * r * (r * r - 1i64)) / 12.0f64 }

// the lower tail up to and including X
fn pfrie(d: *const Fdist, x: f64, r: i64, n: i64) -> f64 {
    if r < 3i64 || n < 2i64 { ret 0.0f64 / 0.0f64 }
    let m = friedman_m(r, n)
    var s = x * f64(n * r * (r + 1i64)) / 12.0f64
    if s > m || s < 0.0f64 { ret 0.0f64 / 0.0f64 }
    var is_ = i64(math.ceil[f64](s))
    is_ = 2i64 * (is_ / 2i64)
    s = f64(is_)
    if s < 1.0f64 { s = 1.0f64 }
    if friedman_exact_ok(r, n) && d.has {
        let ss = friedman_ss(x, r, n)
        let k = friedman_find_s(ss, d.s[d.s.len - 1usize], d.s, d.s.len, true)
        ret 1.0f64 - d.q[k]
    }
    let w = (s - 1.0f64) / (m + 2.0f64)
    let aa = f64(r - 1i64) - 2.0f64 / f64(n)
    let bb = aa * f64(n - 1i64)
    ret 1.0f64 - nb.pbeta(1.0f64 - w, bb / 2.0f64, aa / 2.0f64, true, false)
}

// the upper tail excluding X
fn qfrie(d: *const Fdist, x: f64, r: i64, n: i64) -> f64 {
    if r < 3i64 || n < 2i64 { ret 0.0f64 / 0.0f64 }
    let m = friedman_m(r, n)
    var s = x * f64(n * r * (r + 1i64)) / 12.0f64
    if s > m || s < 0.0f64 { ret 0.0f64 / 0.0f64 }
    var is_ = i64(math.floor[f64](s))
    is_ = 2i64 * (is_ / 2i64)
    s = f64(is_)
    if s < 1.0f64 { s = 1.0f64 }
    if friedman_exact_ok(r, n) && d.has {
        let ss = friedman_ss(x, r, n)
        let k = friedman_find_s(ss, d.s[d.s.len - 1usize], d.s, d.s.len, true)
        ret d.q[k]
    }
    let w = (s - 1.0f64) / (m + 2.0f64)
    let aa = f64(r - 1i64) - 2.0f64 / f64(n)
    let bb = aa * f64(n - 1i64)
    ret nb.pbeta(1.0f64 - w, bb / 2.0f64, aa / 2.0f64, true, false)
}

// the probability mass at X (exact) or the difference of the approximation's cdf
fn ffrie(d: *const Fdist, x: f64, r: i64, n: i64) -> f64 {
    if r < 3i64 || n < 2i64 { ret 0.0f64 / 0.0f64 }
    let m = friedman_m(r, n)
    var s = x * f64(n * r * (r + 1i64)) / 12.0f64
    if s > m || s < 0.0f64 { ret 0.0f64 / 0.0f64 }
    s = s - 2.0f64
    var is_ = i64(math.floor[f64](s))
    is_ = 2i64 * (is_ / 2i64)
    s = f64(is_)
    if s < 1.0f64 { s = 1.0f64 }
    if friedman_exact_ok(r, n) && d.has {
        let ss = friedman_ss(x, r, n)
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
    var larger = p <= pfrie(d, x, r, n)
    while larger {
        if x <= 0.0f64 { ret 0.0f64 }
        x = x - step
        if x < 0.0f64 {
            larger = false
        } else {
            larger = p <= pfrie(d, x, r, n)
        }
        if !larger {
            x = x + step
            ret x
        }
    }
    while !larger {
        if x + step >= mx { ret mx }
        x = x + step
        larger = p <= pfrie(d, x, r, n)
        if larger { ret x }
    }
    ret 0.0f64
}
