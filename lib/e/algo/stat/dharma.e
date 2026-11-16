// R DHARMa: the quantile (PIT) residuals of a simulated response matrix (createDHARMa with method = "PIT", set.seed(seed) for the tie
// randomisation), the Kolmogorov-Smirnov statistic of the residuals against the uniform, and the exact binomial outlier test (testOutliers,
// type = "binomial", margin "both", two-sided).
//
// Not here: the traditional method and rotation, testDispersion, testZeroInflation, testTemporalAutocorrelation, refitted residuals and
// the bootstrap outlier test.

use e.algo.rand.r as rr
use e.math
use e.math.nmath_beta as nb
use e.mem

// sims is n by nsim row-major; out receives the n scaled residuals
fn pit(a: *mem.Arena, sims: []const f64, obs: []const f64, nsim: usize, seed: i64, out: []f64) -> err {
    let n = obs.len
    let (lo, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    let (hi, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    var any = false
    var i = 0usize
    while i < n {
        var c1 = 0.0f64
        var c2 = 0.0f64
        var j = 0usize
        while j < nsim {
            if sims[i * nsim + j] < obs[i] { c1 += 1.0f64 }
            if sims[i * nsim + j] <= obs[i] { c2 += 1.0f64 }
            j += 1usize
        }
        lo[i] = c1 / f64(nsim)
        hi[i] = c2 / f64(nsim)
        if lo[i] != hi[i] { any = true }
        i += 1usize
    }
    if !any {
        i = 0usize
        while i < n {
            out[i] = lo[i]
            i += 1usize
        }
        ret ok
    }
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    i = 0usize
    while i < n {
        let u = rr.runif(&g, lo[i], hi[i])
        if lo[i] != hi[i] { out[i] = u } else { out[i] = lo[i] }
        i += 1usize
    }
    ret ok
}

fn sorted(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    ret (s, ok)
}

// the two-sided Kolmogorov-Smirnov statistic against the uniform distribution on [0, 1]
fn ks_uniform(a: *mem.Arena, r: []const f64) -> f64 {
    let (s, e) = sorted(a, r)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = f64(s.len)
    var d = 0.0f64
    var i = 0usize
    while i < s.len {
        let up = f64(i + 1usize) / n - s[i]
        let dn = s[i] - f64(i) / n
        if up > d { d = up }
        if dn > d { d = dn }
        i += 1usize
    }
    ret d
}

// the outliers: scaled residuals below 1 / (nsim + 1) or above 1 - 1 / (nsim + 1)
fn outlier_count(r: []const f64, nsim: usize) -> usize {
    let eps = 1.0f64 / f64(nsim + 1usize)
    var c = 0usize
    var i = 0usize
    while i < r.len {
        if r[i] < eps { c += 1usize }
        if r[i] > 1.0f64 - eps { c += 1usize }
        i += 1usize
    }
    ret c
}

// binom.test(x, n, p) two-sided: the sum of the probabilities not above that of x (relative tolerance 1 + 1e-7), as R does
fn binom_test_p(x: usize, n: usize, p: f64) -> f64 {
    if p == 0.0f64 {
        if x == 0usize { ret 1.0f64 }
        ret 0.0f64
    }
    if p == 1.0f64 {
        if x == n { ret 1.0f64 }
        ret 0.0f64
    }
    let rel = 1.0000001f64
    let xf = f64(x)
    let nf = f64(n)
    let d = nb.dbinom(xf, nf, p, false)
    let m = nf * p
    var pv = 0.0f64
    if xf == m {
        pv = 1.0f64
    } else if xf < m {
        // the lower tail up to x, plus the upper-tail values whose probability does not exceed d
        var y = 0usize
        var k = usize(math.ceil[f64](m))
        while k <= n {
            if nb.dbinom(f64(k), nf, p, false) <= d * rel { y += 1usize }
            k += 1usize
        }
        pv = nb.pbinom(xf, nf, p, true, false) + nb.pbinom(f64(n - y), nf, p, false, false)
        if y == 0usize { pv = nb.pbinom(xf, nf, p, true, false) }
    } else {
        var y = 0usize
        var k = 0usize
        while k <= usize(math.floor[f64](m)) {
            if nb.dbinom(f64(k), nf, p, false) <= d * rel { y += 1usize }
            k += 1usize
        }
        pv = nb.pbinom(f64(y) - 1.0f64, nf, p, true, false) + nb.pbinom(xf - 1.0f64, nf, p, false, false)
        if y == 0usize { pv = nb.pbinom(xf - 1.0f64, nf, p, false, false) }
    }
    if pv > 1.0f64 { pv = 1.0f64 }
    ret pv
}

fn mat_mul(a: []const f64, b: []const f64, c: []f64, m: usize) {
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var s = 0.0f64
            var k = 0usize
            while k < m {
                s += a[i * m + k] * b[k * m + j]
                k += 1usize
            }
            c[i * m + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// Marsaglia-Tsang-Wang: V = A^n scaled, with the base-10 exponent in the second answer
fn mat_power(arena: *mem.Arena, a: []const f64, ea: i64, v: []f64, m: usize, n: usize) -> (i64, err) {
    if n == 1usize {
        var i = 0usize
        while i < m * m {
            v[i] = a[i]
            i += 1usize
        }
        ret (ea, ok)
    }
    let (ev, e1) = mat_power(arena, a, ea, v, m, n / 2usize)
    if e1 != ok { ret (0i64, e1) }
    let (b, e2) = mem.alloc[f64](arena, m * m)
    if e2 != ok { ret (0i64, e2) }
    mat_mul(v, v, b, m)
    var eb = 2i64 * ev
    var res = ev
    if n % 2usize == 0usize {
        var i = 0usize
        while i < m * m {
            v[i] = b[i]
            i += 1usize
        }
        res = eb
    } else {
        mat_mul(a, b, v, m)
        res = ea + eb
    }
    if v[(m / 2usize) * m + m / 2usize] > 1.0e140f64 {
        var i = 0usize
        while i < m * m {
            v[i] = v[i] * 1.0e-140f64
            i += 1usize
        }
        res += 140i64
    }
    ret (res, ok)
}

// the exact two-sided Kolmogorov-Smirnov distribution function P(D_n < d)
fn ks_exact_cdf(arena: *mem.Arena, n: usize, d: f64) -> f64 {
    let k = usize(f64(n) * d) + 1usize
    let m = 2usize * k - 1usize
    let h = f64(k) - f64(n) * d
    let (hm, e1) = mem.alloc[f64](arena, m * m)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (q, e2) = mem.alloc[f64](arena, m * m)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            if i + 1usize < j { hm[i * m + j] = 0.0f64 } else { hm[i * m + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        hm[i * m] = hm[i * m] - math.pow[f64](h, f64(i + 1usize))
        hm[(m - 1usize) * m + i] = hm[(m - 1usize) * m + i] - math.pow[f64](h, f64(m - i))
        i += 1usize
    }
    if 2.0f64 * h - 1.0f64 > 0.0f64 { hm[(m - 1usize) * m] = hm[(m - 1usize) * m] + math.pow[f64](2.0f64 * h - 1.0f64, f64(m)) }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            if i + 1usize > j {
                var g = 1usize
                while g <= i - j + 1usize {
                    hm[i * m + j] = hm[i * m + j] / f64(g)
                    g += 1usize
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    let (eq, e3) = mat_power(arena, hm, 0i64, q, m, n)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var s = q[(k - 1usize) * m + k - 1usize]
    var ex = eq
    i = 1usize
    while i <= n {
        s = s * f64(i) / f64(n)
        if s < 1.0e-140f64 {
            s = s * 1.0e140f64
            ex -= 140i64
        }
        i += 1usize
    }
    ret s * math.pow[f64](10.0f64, f64(ex))
}

fn has_ties(a: *mem.Arena, r: []const f64) -> bool {
    let (s, e) = sorted(a, r)
    if e != ok { ret false }
    var i = 1usize
    while i < s.len {
        if s[i] == s[i - 1usize] { ret true }
        i += 1usize
    }
    ret false
}

// the Kolmogorov-Smirnov p value of ks.test(r, "punif"): exact below 100 observations without ties, the limiting distribution otherwise
fn ks_pvalue(a: *mem.Arena, r: []const f64) -> f64 {
    let n = r.len
    let d = ks_uniform(a, r)
    if n < 100usize && !has_ties(a, r) { ret 1.0f64 - ks_exact_cdf(a, n, d) }
    let x = math.sqrt[f64](f64(n)) * d
    var lower = 0.0f64
    let tol = 1.0e-6f64
    let pi = 3.141592653589793238462643383279f64
    if x > 0.0f64 && x < 1.0f64 {
        let kmax = usize(math.sqrt[f64](2.0f64 - math.log[f64](tol)))
        let z = 0.0f64 - (pi / 2.0f64 * pi / 4.0f64) / (x * x)
        let w = math.log[f64](x)
        var s = 0.0f64
        var k = 1usize
        while k < kmax {
            s += math.exp[f64](f64(k * k) * z - w)
            k += 2usize
        }
        lower = s / (1.0f64 / math.sqrt[f64](2.0f64 * pi))
    } else if x >= 1.0f64 {
        let z = 0.0f64 - 2.0f64 * x * x
        var s = 0.0f64 - 1.0f64
        var k = 1usize
        var old = 0.0f64
        var nw = 1.0f64
        while math.abs[f64](old - nw) > tol {
            old = nw
            nw += 2.0f64 * s * math.exp[f64](z * f64(k * k))
            s = 0.0f64 - s
            k += 1usize
        }
        lower = nw
    }
    ret 1.0f64 - lower
}
