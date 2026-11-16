// R SuppDists, the exact and closed-form members: the inverse Gaussian (`d`, `p`, `q`), Kendall's tau and
// Spearman's rho for small N (the exact permutation counts, with SuppDists' reading of a value that is not on the
// support: the inversion count or squared-rank-difference sum is rounded to the nearest, a half going down), and Johnson's system (families SN,
// SL, SB, SU: `d`, `p`, `q`).
//
// Not here: the Edgeworth approximations for large N, the Friedman, Kruskal-Wallis, normal-scores, maximum F-ratio,
// Pearson and hypergeometric distributions, moments, the Johnson fit, random variates.

use e.math
use e.math.dist as dist
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
