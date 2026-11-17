// R DHARMa: the quantile (PIT) residuals of a simulated response matrix (createDHARMa with method = "PIT", set.seed(seed) for the tie
// randomisation), the Kolmogorov-Smirnov statistic of the residuals against the uniform, and the exact binomial outlier test (testOutliers,
// type = "binomial", margin "both", two-sided).
//
// Also here: the traditional method with integer jitter and the rotation of recalculateResiduals, the simulate() draws of lm, glm
// (gaussian, poisson, binomial, Gamma) and conditional lmer and glmer in R's stream order, the bootstrap outlier test, recalculateResiduals,
// the exact Durbin-Watson p value, the one-sided KS tests, the Pearson chi-square dispersion test and testCategorical.
//
// Not here: refit = TRUE residuals and testQuantiles (qgam).

use e.algo.rand.r as rr
use e.algo.rand.rdist as rd
use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.dist as dist
use e.mem

error Unsupported

// sims is n by nsim row-major; out receives the n scaled residuals
fn pit(a: *mem.Arena, sims: []const f64, obs: []const f64, nsim: usize, seed: i64, out: []f64) -> err {
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    ret pit_g(a, &g, sims, obs, nsim, out)
}

// the same, drawing the tie randomisation from the caller's stream
fn pit_g(a: *mem.Arena, g: *rr.Rng, sims: []const f64, obs: []const f64, nsim: usize, out: []f64) -> err {
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
    i = 0usize
    while i < n {
        let u = rr.runif(g, lo[i], hi[i])
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
    sort_f64(s)
    ret (s, ok)
}

fn sift_down(v: []f64, root0: usize, last: usize) {
    var root = root0
    while true {
        var child = 2usize * root + 1usize
        if child >= last { break }
        if child + 1usize < last && v[child] < v[child + 1usize] { child += 1usize }
        if v[root] >= v[child] { break }
        let t = v[root]
        v[root] = v[child]
        v[child] = t
        root = child
    }
}

fn sort_f64(v: []f64) {
    let n = v.len
    var start = n / 2usize
    while start > 0usize {
        start -= 1usize
        sift_down(v, start, n)
    }
    var last = n
    while last > 1usize {
        last -= 1usize
        let t = v[0usize]
        v[0usize] = v[last]
        v[last] = t
        sift_down(v, 0usize, last)
    }
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

// testGeneric's p value over the simulated summaries: alternative 0 two.sided, 1 greater, 2 less
fn get_p(sim: []const f64, obs: f64, alt: usize) -> f64 {
    var ge = 0.0f64
    var le = 0.0f64
    var i = 0usize
    while i < sim.len {
        if sim[i] >= obs { ge += 1.0f64 }
        if sim[i] <= obs { le += 1.0f64 }
        i += 1usize
    }
    let n = f64(sim.len)
    if alt == 1usize { ret ge / n }
    if alt == 2usize { ret le / n }
    var m = le / n
    if ge / n < m { m = ge / n }
    var p = m * 2.0f64
    if p > 1.0f64 { p = 1.0f64 }
    ret p
}

fn var_of(x: []const f64) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / f64(x.len)
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / (f64(x.len) - 1.0f64)
}

// kind 0 testZeroInflation (the count of zeros), 1 testDispersion (var(x - fitted) / var(all simulations)); answers (observed / mean simulated, p)
fn test_generic(a: *mem.Arena, sims: []const f64, obs: []const f64, fitted: []const f64, nsim: usize, kind: usize, alt: usize) -> (f64, f64) {
    let n = obs.len
    let (col, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let (summ, e2) = mem.alloc[f64](a, nsim)
    if e2 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    var ev = 1.0f64
    if kind == 1usize { ev = var_of(sims) }
    var observed = 0.0f64
    var j = 0usize
    while j <= nsim {
        var i = 0usize
        while i < n {
            var v = obs[i]
            if j < nsim { v = sims[i * nsim + j] }
            if kind == 0usize { col[i] = v } else { col[i] = v - fitted[i] }
            i += 1usize
        }
        var s = 0.0f64
        if kind == 0usize {
            i = 0usize
            while i < n {
                if col[i] == 0.0f64 { s += 1.0f64 }
                i += 1usize
            }
        } else {
            s = var_of(col) / ev
        }
        if j < nsim { summ[j] = s } else { observed = s }
        j += 1usize
    }
    var ms = 0.0f64
    j = 0usize
    while j < nsim {
        ms += summ[j]
        j += 1usize
    }
    ms = ms / f64(nsim)
    ret (observed / ms, get_p(summ, observed, alt))
}

// testSpatialAutocorrelation: ape::Moran.I of the scaled residuals with inverse-distance weights (zero diagonal), row-standardised; returns the observed I, its standard deviation and the two-sided p value
fn moran_i(a: *mem.Arena, r: []const f64, xs: []const f64, ys: []const f64) -> (f64, f64, f64) {
    var none: []const f64 = zero
    let (o, s, p) = moran_full(a, r, xs, ys, none, 0usize)
    ret (o, s, p)
}

// alt 0 two.sided, 1 greater, 2 less; dm is an n by n distance matrix that replaces the coordinates when it is given
fn moran_full(a: *mem.Arena, r: []const f64, xs: []const f64, ys: []const f64, dm: []const f64, alt: usize) -> (f64, f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let n = r.len
    let (w, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (nan, nan, nan) }
    var i = 0usize
    while i < n {
        var rs = 0.0f64
        var j = 0usize
        while j < n {
            var v = 0.0f64
            if i != j {
                if dm.len == n * n {
                    v = 1.0f64 / dm[i * n + j]
                } else {
                    v = 1.0f64 / math.sqrt[f64]((xs[i] - xs[j]) * (xs[i] - xs[j]) + (ys[i] - ys[j]) * (ys[i] - ys[j]))
                }
            }
            w[i * n + j] = v
            rs += v
            j += 1usize
        }
        if rs == 0.0f64 { rs = 1.0f64 }
        j = 0usize
        while j < n {
            w[i * n + j] = w[i * n + j] / rs
            j += 1usize
        }
        i += 1usize
    }
    var s = 0.0f64
    var m = 0.0f64
    i = 0usize
    while i < n {
        m += r[i]
        i += 1usize
    }
    m = m / f64(n)
    var cv = 0.0f64
    var v2 = 0.0f64
    var v4 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    i = 0usize
    while i < n {
        let yi = r[i] - m
        v2 += yi * yi
        v4 += yi * yi * yi * yi
        var rsum = 0.0f64
        var csum = 0.0f64
        var j = 0usize
        while j < n {
            let yj = r[j] - m
            s += w[i * n + j]
            cv += w[i * n + j] * yi * yj
            let sym = w[i * n + j] + w[j * n + i]
            s1 += 0.5f64 * sym * sym
            rsum += w[i * n + j]
            csum += w[j * n + i]
            j += 1usize
        }
        s2 += (rsum + csum) * (rsum + csum)
        i += 1usize
    }
    let nf = f64(n)
    let obs = (nf / s) * (cv / v2)
    let ei = -1.0f64 / (nf - 1.0f64)
    let ssq = s * s
    let k = (v4 / nf) / ((v2 / nf) * (v2 / nf))
    let sdi = math.sqrt[f64]((nf * ((nf * nf - 3.0f64 * nf + 3.0f64) * s1 - nf * s2 + 3.0f64 * ssq) - k * (nf * (nf - 1.0f64) * s1 - 2.0f64 * nf * s2 + 6.0f64 * ssq)) / ((nf - 1.0f64) * (nf - 2.0f64) * (nf - 3.0f64) * ssq) - 1.0f64 / ((nf - 1.0f64) * (nf - 1.0f64)))
    var pv = dist.pnorm(obs, ei, sdi, true, false)
    if alt == 1usize {
        pv = 1.0f64 - pv
    } else if alt == 0usize {
        if obs <= ei { pv = 2.0f64 * pv } else { pv = 2.0f64 * (1.0f64 - pv) }
    }
    ret (obs, sdi, pv)
}

// testTemporalAutocorrelation's statistic: the Durbin-Watson d of the scaled residuals centred and ordered by the (unique) times
fn dw_time(a: *mem.Arena, r: []const f64, time: []const f64) -> f64 {
    let n = r.len
    let (ord, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && time[ord[j - 1usize]] > time[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    var m = 0.0f64
    i = 0usize
    while i < n {
        m += r[i]
        i += 1usize
    }
    m = m / f64(n)
    var num = 0.0f64
    var den = 0.0f64
    i = 0usize
    while i < n {
        let e = r[ord[i]] - m
        den += e * e
        if i > 0usize {
            let d = e - (r[ord[i - 1usize]] - m)
            num += d * d
        }
        i += 1usize
    }
    ret num / den
}

// ---- rotation and the traditional method (getQuantile) ----

// l = the lower Cholesky factor of the n by n row-major sigma; false when sigma is not positive definite
fn chol_lower(sigma: []const f64, l: []f64, n: usize) -> bool {
    var i = 0usize
    while i < n * n {
        l[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = sigma[i * n + j]
            var k = 0usize
            while k < j {
                s -= l[i * n + k] * l[j * n + k]
                k += 1usize
            }
            if i == j {
                if !(s > 0.0f64) { ret false }
                l[i * n + i] = math.sqrt[f64](s)
            } else {
                l[i * n + j] = s / l[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// forwardsolve(L, obs) and forwardsolve(L, sims) for L = t(chol(sigma)); an empty sigma means cov(t(sims)) ("estimated")
fn rotate(a: *mem.Arena, sims: []const f64, obs: []const f64, nsim: usize, sigma: []const f64, rs: []f64, ro: []f64) -> err {
    let n = obs.len
    let (cv, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    let (l, e2) = mem.alloc[f64](a, n * n)
    if e2 != ok { ret e2 }
    var i = 0usize
    if sigma.len == n * n {
        while i < n * n {
            cv[i] = sigma[i]
            i += 1usize
        }
    } else {
        let (mu, e3) = mem.alloc[f64](a, n)
        if e3 != ok { ret e3 }
        while i < n {
            var m = 0.0f64
            var j = 0usize
            while j < nsim {
                m += sims[i * nsim + j]
                j += 1usize
            }
            mu[i] = m / f64(nsim)
            i += 1usize
        }
        i = 0usize
        while i < n {
            var k = 0usize
            while k < n {
                var s = 0.0f64
                var j = 0usize
                while j < nsim {
                    s += (sims[i * nsim + j] - mu[i]) * (sims[k * nsim + j] - mu[k])
                    j += 1usize
                }
                cv[i * n + k] = s / (f64(nsim) - 1.0f64)
                k += 1usize
            }
            i += 1usize
        }
    }
    if !chol_lower(cv, l, n) { ret Unsupported }
    i = 0usize
    while i < n {
        var s = obs[i]
        var k = 0usize
        while k < i {
            s -= l[i * n + k] * ro[k]
            k += 1usize
        }
        ro[i] = s / l[i * n + i]
        i += 1usize
    }
    var j = 0usize
    while j < nsim {
        i = 0usize
        while i < n {
            var s = sims[i * nsim + j]
            var k = 0usize
            while k < i {
                s -= l[i * n + k] * rs[k * nsim + j]
                k += 1usize
            }
            rs[i * nsim + j] = s / l[i * n + i]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// DHARMa.ecdf evaluated at v: ux the unique sorted values, uy their cumulative counts over (m + 1); R's approx with yleft = 0, yright = 1
fn ecdf_eval(ux: []const f64, uy: []const f64, u: usize, v: f64) -> f64 {
    if v < ux[0usize] { ret 0.0f64 }
    if v > ux[u - 1usize] { ret 1.0f64 }
    var i = 0usize
    var j = u - 1usize
    while i + 1usize < j {
        let ij = (i + j) / 2usize
        if v < ux[ij] { j = ij } else { i = ij }
    }
    if v == ux[j] { ret uy[j] }
    if v == ux[i] { ret uy[i] }
    ret uy[i] + (uy[j] - uy[i]) * ((v - ux[i]) / (ux[j] - ux[i]))
}

// method = "traditional": per observation the ecdf of the simulations, jittered by runif(-0.5, 0.5) for an integer response; a continuous
// response whose simulations hold duplicated whole numbers is switched to integer, as getQuantile does
fn trad_g(a: *mem.Arena, g: *rr.Rng, sims: []const f64, obs: []const f64, nsim: usize, integer0: bool, out: []f64) -> err {
    let n = obs.len
    var integer = integer0
    if !integer {
        let (all, e0) = sorted(a, sims[0usize..n * nsim])
        if e0 != ok { ret e0 }
        var dup = false
        var whole = true
        var i = 1usize
        while i < all.len {
            if all[i] == all[i - 1usize] {
                dup = true
                if all[i] - math.floor[f64](all[i]) != 0.0f64 { whole = false }
            }
            i += 1usize
        }
        if dup && whole { integer = true }
    }
    let (row, e1) = mem.alloc[f64](a, nsim)
    if e1 != ok { ret e1 }
    let (ux, e2) = mem.alloc[f64](a, nsim)
    if e2 != ok { ret e2 }
    let (uy, e3) = mem.alloc[f64](a, nsim)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < nsim {
            row[j] = sims[i * nsim + j]
            if integer { row[j] = row[j] + rr.runif(g, 0.0f64 - 0.5f64, 0.5f64) }
            j += 1usize
        }
        sort_f64(row)
        var u = 0usize
        j = 0usize
        while j < nsim {
            var k = j
            while k + 1usize < nsim && row[k + 1usize] == row[j] { k += 1usize }
            ux[u] = row[j]
            uy[u] = f64(k + 1usize) / f64(nsim + 1usize)
            u += 1usize
            j = k + 1usize
        }
        var v = obs[i]
        if integer { v = v + rr.runif(g, 0.0f64 - 0.5f64, 0.5f64) }
        out[i] = ecdf_eval(ux, uy, u, v)
        i += 1usize
    }
    ret ok
}

// getQuantile: method 0 PIT, 1 traditional; rot 0 none, 1 estimated, 2 the matrix sigma (PIT only)
fn quantile_g(a: *mem.Arena, g: *rr.Rng, sims: []const f64, obs: []const f64, nsim: usize, method: usize, integer: bool, rot: usize, sigma: []const f64, out: []f64) -> err {
    if method == 1usize {
        if rot != 0usize { ret Unsupported }
        ret trad_g(a, g, sims, obs, nsim, integer, out)
    }
    if rot == 0usize { ret pit_g(a, g, sims, obs, nsim, out) }
    let n = obs.len
    let (rs, e1) = mem.alloc[f64](a, n * nsim)
    if e1 != ok { ret e1 }
    let (ro, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    var sg: []const f64 = zero
    if rot == 2usize { sg = sigma }
    let er = rotate(a, sims, obs, nsim, sg, rs, ro)
    if er != ok { ret er }
    ret pit_g(a, g, rs, ro, nsim, out)
}

// ---- simulate() of lm, glm and conditional merMod models; out is n by nsim row-major, R draws it column by column ----

// gaussian with one standard deviation (lmer: sigma)
fn sim_gaussian_sd(g: *rr.Rng, mu: []const f64, sd: f64, nsim: usize, out: []f64) {
    let n = mu.len
    var j = 0usize
    while j < nsim {
        var i = 0usize
        while i < n {
            out[i * nsim + j] = mu[i] + rr.rnorm(g, 0.0f64, sd)
            i += 1usize
        }
        j += 1usize
    }
}

// lm and gaussian glm: sd = sqrt(deviance / df / weight); an empty wts means unweighted
fn sim_gaussian_lm(g: *rr.Rng, mu: []const f64, dev: f64, df: f64, wts: []const f64, nsim: usize, out: []f64) {
    let n = mu.len
    let vars = dev / df
    var j = 0usize
    while j < nsim {
        var i = 0usize
        while i < n {
            var v = vars
            if wts.len == n { v = vars / wts[i] }
            out[i * nsim + j] = mu[i] + rr.rnorm(g, 0.0f64, math.sqrt[f64](v))
            i += 1usize
        }
        j += 1usize
    }
}

fn sim_poisson(g: *rr.Rng, mu: []const f64, nsim: usize, out: []f64) {
    let n = mu.len
    var j = 0usize
    while j < nsim {
        var i = 0usize
        while i < n {
            out[i * nsim + j] = rd.rpois(g, mu[i])
            i += 1usize
        }
        j += 1usize
    }
}

// mode 0: rbinom(size = wts, prob) / wts times wts again, as DHARMa does for a weighted model; mode 1: the counts
fn sim_binomial(g: *rr.Rng, mu: []const f64, wts: []const f64, nsim: usize, mode: usize, out: []f64) {
    let n = mu.len
    var j = 0usize
    while j < nsim {
        var i = 0usize
        while i < n {
            var w = 1.0f64
            if wts.len == n { w = wts[i] }
            let k = rd.rbinom(g, w, mu[i])
            if mode == 0usize { out[i * nsim + j] = (k / w) * w } else { out[i * nsim + j] = k }
            i += 1usize
        }
        j += 1usize
    }
}

// rgamma(shape, rate = shape / fitted); shape is the per observation vector MASS::gamma.shape()$alpha * weights
fn sim_gamma(g: *rr.Rng, mu: []const f64, shape: []const f64, nsim: usize, out: []f64) {
    let n = mu.len
    var j = 0usize
    while j < nsim {
        var i = 0usize
        while i < n {
            out[i * nsim + j] = rd.rgamma(g, shape[i], 1.0f64 / (shape[i] / mu[i]))
            i += 1usize
        }
        j += 1usize
    }
}

fn digamma_pos(x: f64) -> f64 {
    var result = 0.0f64
    var t = x
    while t < 10.0f64 {
        result -= 1.0f64 / t
        t += 1.0f64
    }
    let r = 1.0f64 / (t * t)
    result += math.log[f64](t) - 0.5f64 / t
    result -= r * (1.0f64 / 12.0f64 - r * (1.0f64 / 120.0f64 - r * (1.0f64 / 252.0f64 - r * (1.0f64 / 240.0f64 - r * (1.0f64 / 132.0f64 - r * 691.0f64 / 32760.0f64)))))
    ret result
}

fn trigamma_pos(x: f64) -> f64 {
    var result = 0.0f64
    var t = x
    while t < 10.0f64 {
        result += 1.0f64 / (t * t)
        t += 1.0f64
    }
    let r = 1.0f64 / (t * t)
    result += 1.0f64 / t + 0.5f64 * r
    result += r / t * (1.0f64 / 6.0f64 - r * (1.0f64 / 30.0f64 - r * (1.0f64 / 42.0f64 - r * (1.0f64 / 30.0f64 - r * (5.0f64 / 66.0f64 - r * 691.0f64 / 2730.0f64)))))
    ret result
}

// MASS::gamma.shape.glm: alpha from the response y, the fitted mu, the prior weights w, the deviance and the residual df
fn gamma_shape(y: []const f64, mu: []const f64, w: []const f64, dev: f64, df: f64) -> f64 {
    let n = y.len
    let dbar = dev / df
    var alpha = (6.0f64 + 2.0f64 * dbar) / (dbar * (6.0f64 + dbar))
    let epsmax = 0.0001220703125f64
    var eps = 1.0f64
    var itr = 0i64
    while true {
        if !(math.abs[f64](eps) > epsmax) { break }
        itr += 1i64
        if itr > 10i64 { break }
        var sc = 0.0f64
        var inf = 0.0f64
        var i = 0usize
        while i < n {
            var yz = y[i]
            if y[i] == 0.0f64 { yz = y[i] + 1.0f64 }
            let fixed = 0.0f64 - y[i] / mu[i] - math.log[f64](mu[i]) + math.log[f64](w[i]) + 1.0f64 + math.log[f64](yz)
            sc += w[i] * (fixed + math.log[f64](alpha) - digamma_pos(w[i] * alpha))
            inf += w[i] * (w[i] * trigamma_pos(w[i] * alpha) - 1.0f64 / alpha)
            i += 1usize
        }
        eps = sc / inf
        alpha += eps
    }
    ret alpha
}

// ---- tests on the scaled residuals ----

// the outlier count of testOutliers(type = "binomial"): margin 0 both, 1 upper, 2 lower
fn outlier_count_m(r: []const f64, nsim: usize, margin: usize) -> usize {
    let eps = 1.0f64 / f64(nsim + 1usize)
    var c = 0usize
    var i = 0usize
    while i < r.len {
        if margin != 1usize && r[i] < eps { c += 1usize }
        if margin != 2usize && r[i] > 1.0f64 - eps { c += 1usize }
        i += 1usize
    }
    ret c
}

// binom.test(x, n, p, alternative): alt 0 two.sided, 1 greater, 2 less
fn binom_test_alt(x: usize, n: usize, p: f64, alt: usize) -> f64 {
    if alt == 1usize {
        if x == 0usize { ret 1.0f64 }
        ret nb.pbinom(f64(x) - 1.0f64, f64(n), p, false, false)
    }
    if alt == 2usize { ret nb.pbinom(f64(x), f64(n), p, true, false) }
    ret binom_test_p(x, n, p)
}

// testOutliers(type = "binomial"): (outliers, p value)
fn outlier_binomial(r: []const f64, nsim: usize, margin: usize, alt: usize) -> (usize, f64) {
    let c = outlier_count_m(r, nsim, margin)
    var p0 = 1.0f64 / f64(nsim + 1usize)
    if margin == 0usize { p0 = p0 * 2.0f64 }
    ret (c, binom_test_alt(c, r.len, p0, alt))
}

fn outlier_freq(r: []const f64, margin: usize) -> f64 {
    var z = 0.0f64
    var o = 0.0f64
    var i = 0usize
    while i < r.len {
        if r[i] == 0.0f64 { z += 1.0f64 }
        if r[i] == 1.0f64 { o += 1.0f64 }
        i += 1usize
    }
    let n = f64(r.len)
    if margin == 1usize { ret o / n }
    if margin == 2usize { ret z / n }
    ret z / n + o / n
}

// testOutliers(type = "bootstrap"): sr the scaled residuals of the object, sims its simulated response; res receives
// (statistic, p value, conf.int low, conf.int high, mean bootstrap frequency). g must be seeded as R was just before the call.
fn outlier_boot(a: *mem.Arena, g: *rr.Rng, sims: []const f64, sr: []const f64, nsim: usize, nboot0: usize, method: usize, integer: bool, margin: usize, alt: usize, res: []f64) -> err {
    let n = sr.len
    var nboot = nboot0
    if nboot > nsim { nboot = nsim }
    let observed = outlier_freq(sr, margin)
    let (freq, e1) = mem.alloc[f64](a, nboot)
    if e1 != ok { ret e1 }
    var sg: []const f64 = zero
    var b = 1usize
    while b <= nboot {
        let start = mem.mark(a)
        let (pick, e2) = rr.sample_int(a, g, i64(nsim) - 1i64, i64(nsim), true)
        if e2 != ok { ret e2 }
        let (ss, e3) = mem.alloc[f64](a, n * nsim)
        if e3 != ok { ret e3 }
        let (ob, e4) = mem.alloc[f64](a, n)
        if e4 != ok { ret e4 }
        let (qr, e5) = mem.alloc[f64](a, n)
        if e5 != ok { ret e5 }
        var c = 0usize
        while c < nsim {
            var idx = usize(pick[c])
            if idx >= b { idx += 1usize }
            var i = 0usize
            while i < n {
                ss[i * nsim + c] = sims[i * nsim + idx - 1usize]
                i += 1usize
            }
            c += 1usize
        }
        var i = 0usize
        while i < n {
            ob[i] = sims[i * nsim + b - 1usize]
            i += 1usize
        }
        let eq = quantile_g(a, g, ss, ob, nsim, method, integer, 0usize, sg, qr)
        if eq != ok { ret eq }
        var f = 0.0f64
        let ones = outlier_freq(qr, 1usize)
        let zeros = outlier_freq(qr, 2usize)
        if margin == 0usize { f = ones + zeros }
        if margin == 1usize { f = ones }
        if margin == 2usize { f = zeros }
        mem.reset(a, start)
        freq[b - 1usize] = f
        b += 1usize
    }
    res[0usize] = observed * f64(n)
    res[1usize] = get_p(freq, observed, alt)
    let (so, e6) = sorted(a, freq)
    if e6 != ok { ret e6 }
    var m = 0.0f64
    var k = 0usize
    while k < nboot {
        m += freq[k]
        k += 1usize
    }
    res[4usize] = m / f64(nboot)
    k = 0usize
    while k < 2usize {
        var pr = 0.025f64
        if k == 1usize { pr = 0.975f64 }
        let index = 1.0f64 + f64(nboot - 1usize) * pr
        let lo = math.floor[f64](index)
        let hi = math.ceil[f64](index)
        let h = index - lo
        var q = so[usize(lo) - 1usize]
        if index > lo && so[usize(hi) - 1usize] != q { q = (1.0f64 - h) * q + h * so[usize(hi) - 1usize] }
        res[2usize + k] = q
        k += 1usize
    }
    ret ok
}

// ---- recalculateResiduals ----

// agg 0 sum, 1 mean, 2 max, 3 min of the selected rows of group gval; v is read at v[row * step + offset]
fn aggregate_group(agg: usize, v: []const f64, step: usize, offset: usize, idx: []const usize, gv: []const f64, gval: f64) -> f64 {
    var acc = 0.0f64
    var cnt = 0usize
    var k = 0usize
    while k < idx.len {
        if gv[k] == gval {
            let x = v[idx[k] * step + offset]
            if cnt == 0usize {
                acc = x
            } else if agg == 2usize {
                if x > acc { acc = x }
            } else if agg == 3usize {
                if x < acc { acc = x }
            } else {
                acc += x
            }
            cnt += 1usize
        }
        k += 1usize
    }
    if agg == 1usize { acc = acc / f64(cnt) }
    ret acc
}

// recalculateResiduals(group, sel, aggregateBy, seed, method, rotation): an empty group means one group per observation, an empty sel
// means every row; the groups come out in ascending order of their value. Answers the number of groups; sr, aobs, afit and asims
// (groups by nsim, row-major) hold the new residuals, observed and fitted responses and simulations.
fn recalc(a: *mem.Arena, sims: []const f64, obs: []const f64, fitted: []const f64, nsim: usize, group: []const f64, sel: []const f64, agg: usize, seed: i64, method: usize, integer: bool, rot: usize, sigma: []const f64, sr: []f64, aobs: []f64, afit: []f64, asims: []f64) -> (usize, err) {
    let n = obs.len
    let (idx, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (0usize, e1) }
    let (gv, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (0usize, e2) }
    var m = 0usize
    var i = 0usize
    while i < n {
        if sel.len != n || sel[i] != 0.0f64 {
            idx[m] = i
            if group.len == n { gv[m] = group[i] } else { gv[m] = f64(i) }
            m += 1usize
        }
        i += 1usize
    }
    let (ug, e3) = mem.alloc[f64](a, m)
    if e3 != ok { ret (0usize, e3) }
    i = 0usize
    while i < m {
        ug[i] = gv[i]
        i += 1usize
    }
    sort_f64(ug)
    var ng = 0usize
    i = 0usize
    while i < m {
        if i == 0usize || ug[i] != ug[i - 1usize] {
            ug[ng] = ug[i]
            ng += 1usize
        }
        i += 1usize
    }
    let sub = idx[0usize..m]
    let gvs = gv[0usize..m]
    var k = 0usize
    while k < ng {
        aobs[k] = aggregate_group(agg, obs, 1usize, 0usize, sub, gvs, ug[k])
        afit[k] = aggregate_group(agg, fitted, 1usize, 0usize, sub, gvs, ug[k])
        var j = 0usize
        while j < nsim {
            asims[k * nsim + j] = aggregate_group(agg, sims, nsim, j, sub, gvs, ug[k])
            j += 1usize
        }
        k += 1usize
    }
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    let eq = quantile_g(a, &g, asims[0usize..ng * nsim], aobs[0usize..ng], nsim, method, integer, rot, sigma, sr[0usize..ng])
    if eq != ok { ret (0usize, eq) }
    ret (ng, ok)
}

// ---- Durbin-Watson p value (lmtest::dwtest on scaledResiduals ~ 1, order.by = time) ----

// Fortran DO trip count: the number of values of l = from, from + step, ... not past to
fn do_trips(from: i64, to: i64, step: i64) -> i64 {
    let t = (to - from + step) / step
    if t < 0i64 { ret 0i64 }
    ret t
}

// lmtest src/pan.f (Farebrother AS 153, as amended by Cummins): P(sum a_i u_i^2 < x * sum u_i^2 + c); aa[0] = x, aa[1..m] the
// eigenvalues in either order, n the number of series terms (dwtest iterations)
fn pan(aa: []const f64, m: i64, c: f64, n: i64) -> f64 {
    let x = aa[0usize]
    var h = 0i64
    var k = 0i64
    var last = 0i64
    if aa[1usize] > aa[usize(m)] {
        h = m
        k = 0i64 - 1i64
        last = 1i64
    } else {
        h = 1i64
        k = 1i64
        last = m
    }
    var nu = h
    var found = false
    var t = 0i64
    let trips = do_trips(h, last, k)
    while t < trips {
        nu = h + t * k
        if aa[usize(nu)] >= x {
            found = true
            break
        }
        t += 1i64
    }
    if !found {
        nu = h + trips * k
        if c >= 0.0f64 { ret 1.0f64 }
    }
    if nu == h && c <= 0.0f64 { ret 0.0f64 }
    if k == 1i64 { nu = nu - 1i64 }
    h = m - nu
    var y = 0.0f64
    if c == 0.0f64 { y = f64(h - nu) } else { y = c * (aa[1usize] - aa[usize(m)]) }
    var d = 0i64
    var j1 = 0i64
    var j2 = 0i64
    var j3 = 0i64
    var j4 = 0i64
    if y >= 0.0f64 {
        d = 2i64
        h = nu
        k = 0i64 - k
        j1 = 0i64
        j2 = 2i64
        j3 = 3i64
        j4 = 1i64
    } else {
        d = 0i64 - 2i64
        nu = nu + 1i64
        j1 = m - 2i64
        j2 = m - 1i64
        j3 = m + 1i64
        j4 = m
    }
    let pin = 2.0f64 * math.atan[f64](1.0f64) / f64(n)
    var sum = 0.5f64 * f64(k + 1i64)
    var sgn = f64(k) / f64(n)
    let n2 = n + n - 1i64
    var l1 = h - 2i64 * (h / 2i64)
    while l1 >= 0i64 {
        let t2 = do_trips(j2, nu, d)
        var q = 0i64
        while q < t2 {
            let l2 = j2 + q * d
            var sum1 = aa[usize(j4)]
            var prod = aa[usize(l2)]
            let u = 0.5f64 * (sum1 + prod)
            let v = 0.5f64 * (sum1 - prod)
            sum1 = 0.0f64
            var i = 1i64
            while i <= n2 {
                let yy = u - v * math.cos[f64](f64(i) * pin)
                let num = yy - x
                prod = math.exp[f64](0.0f64 - c / num)
                var kk = 1i64
                while kk <= j1 {
                    prod = prod * num / (yy - aa[usize(kk)])
                    kk += 1i64
                }
                kk = j3
                while kk <= m {
                    prod = prod * num / (yy - aa[usize(kk)])
                    kk += 1i64
                }
                sum1 = sum1 + math.sqrt[f64](math.abs[f64](prod))
                i += 2i64
            }
            sgn = 0.0f64 - sgn
            sum = sum + sgn * sum1
            j1 = j1 + d
            j3 = j3 + d
            j4 = j4 + d
            q += 1i64
        }
        if d == 2i64 { j3 = j3 - 1i64 } else { j1 = j1 + 1i64 }
        j2 = 0i64
        nu = 0i64
        l1 -= 1i64
    }
    ret sum
}

// P(DW < dw) for n residuals of an intercept-only model: pan over the eigenvalues 2 - 2 cos(pi j / n), j = n-1 down to 1 (the order eigen() gives)
fn dw_cdf(a: *mem.Arena, dw: f64, n: usize) -> f64 {
    let pi = 3.141592653589793238462643383279f64
    let (lam, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    lam[0usize] = dw
    var j = 1usize
    while j < n {
        lam[j] = 2.0f64 - 2.0f64 * math.cos[f64](pi * f64(n - j) / f64(n))
        j += 1usize
    }
    ret pan(lam, i64(n) - 1i64, 0.0f64, 15i64)
}

// the p value of dwtest: the exact one (Pan) below 100 observations, the normal approximation otherwise; alt 0 two.sided, 1 greater, 2 less
fn dw_pvalue(a: *mem.Arena, dw: f64, n: usize, alt: usize) -> f64 {
    if n < 3usize { ret 1.0f64 }
    if n < 100usize {
        let pd = dw_cdf(a, dw, n)
        var p = pd
        if alt == 0usize {
            var q = 1.0f64 - pd
            if pd < q { q = pd }
            p = 2.0f64 * q
        }
        if alt == 2usize { p = 1.0f64 - pd }
        if p >= 0.0f64 && p <= 1.0f64 { ret p }
    }
    if n < 5usize { ret 1.0f64 }
    let nf = f64(n)
    let pp = 2.0f64 * (nf - 1.0f64)
    let qq = 2.0f64 * (3.0f64 * nf - 4.0f64)
    let dmean = pp / (nf - 1.0f64)
    let dvar = 2.0f64 / ((nf - 1.0f64) * (nf - 1.0f64 + 2.0f64)) * (qq - pp * dmean)
    let sd = math.sqrt[f64](dvar)
    if alt == 0usize { ret 2.0f64 * dist.pnorm(math.abs[f64](dw - dmean), 0.0f64, sd, false, false) }
    if alt == 2usize { ret dist.pnorm(dw, dmean, sd, false, false) }
    ret dist.pnorm(dw, dmean, sd, true, false)
}

// ---- ks.test with an alternative, the Pearson dispersion test, testGeneric and testCategorical ----

// alt 0 two.sided (D), 1 greater (D+), 2 less (D-)
fn ks_stat_alt(a: *mem.Arena, r: []const f64, alt: usize) -> f64 {
    if alt == 0usize { ret ks_uniform(a, r) }
    let (s, e) = sorted(a, r)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = f64(s.len)
    var d = 0.0f64 - 1.0f64
    var i = 0usize
    while i < s.len {
        var x = 0.0f64
        if alt == 1usize { x = 1.0f64 / n - (s[i] - f64(i) / n) } else { x = s[i] - f64(i) / n }
        if x > d { d = x }
        i += 1usize
    }
    ret d
}

fn ks_pvalue_alt(a: *mem.Arena, r: []const f64, alt: usize) -> f64 {
    if alt == 0usize { ret ks_pvalue(a, r) }
    let n = r.len
    let q = ks_stat_alt(a, r, alt)
    var p = 0.0f64
    if n < 100usize && !has_ties(a, r) {
        let nf = f64(n)
        var j = 0usize
        let jmax = usize(math.floor[f64](nf * (1.0f64 - q)))
        var sum = 0.0f64
        while j <= jmax {
            var lc = 0.0f64
            var i = 1usize
            while i <= j {
                lc += math.log[f64](f64(n - j + i) / f64(i))
                i += 1usize
            }
            let b = 1.0f64 - q - f64(j) / nf
            if b > 0.0f64 { sum += math.exp[f64](lc + (nf - f64(j)) * math.log[f64](b) + (f64(j) - 1.0f64) * math.log[f64](q + f64(j) / nf)) }
            j += 1usize
        }
        p = q * sum
    } else {
        p = math.exp[f64](0.0f64 - 2.0f64 * f64(n) * q * q)
    }
    if p > 1.0f64 { p = 1.0f64 }
    if p < 0.0f64 { p = 0.0f64 }
    ret p
}

// testDispersion(type = "PearsonChisq"): (sum(rp^2) / rdf, p value); alt 0 two.sided, 1 greater, 2 less
fn pearson_chisq(rp: []const f64, rdf: f64, alt: usize) -> (f64, f64) {
    var s = 0.0f64
    var i = 0usize
    while i < rp.len {
        s += rp[i] * rp[i]
        i += 1usize
    }
    var p = 0.0f64
    if alt == 1usize {
        p = nm.pchisq(s, rdf, false, false)
    } else if alt == 2usize {
        p = nm.pchisq(s, rdf, true, false)
    } else {
        let lo = nm.pchisq(s, rdf, true, false)
        let up = nm.pchisq(s, rdf, false, false)
        var q = lo
        if up < q { q = up }
        p = q * 2.0f64
        if p > 1.0f64 { p = 1.0f64 }
    }
    ret (s / rdf, p)
}

// testGeneric over summaries already computed: sim holds the summary of every simulation; answers (observed / mean(sim), p)
fn generic_test(sim: []const f64, observed: f64, alt: usize) -> (f64, f64) {
    var ms = 0.0f64
    var i = 0usize
    while i < sim.len {
        ms += sim[i]
        i += 1usize
    }
    ms = ms / f64(sim.len)
    ret (observed / ms, get_p(sim, observed, alt))
}

fn median_of(a: *mem.Arena, v: []const f64) -> f64 {
    let (s, e) = sorted(a, v)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = s.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

// testCategorical: the KS uniformity p value of every level of grp (ascending), its Holm adjustment, and Levene's F and p
// (anova of |r - level median| on the level). p and padj need one slot per level; answers the number of levels.
fn test_categorical(a: *mem.Arena, r: []const f64, grp: []const f64, p: []f64, padj: []f64, lev: []f64) -> (usize, err) {
    let n = r.len
    let (ug, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (0usize, e1) }
    var i = 0usize
    while i < n {
        ug[i] = grp[i]
        i += 1usize
    }
    sort_f64(ug)
    var ng = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || ug[i] != ug[i - 1usize] {
            ug[ng] = ug[i]
            ng += 1usize
        }
        i += 1usize
    }
    let (sub, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (0usize, e2) }
    let (z, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret (0usize, e3) }
    let (zm, e4) = mem.alloc[f64](a, ng)
    if e4 != ok { ret (0usize, e4) }
    var k = 0usize
    while k < ng {
        var m = 0usize
        i = 0usize
        while i < n {
            if grp[i] == ug[k] {
                sub[m] = r[i]
                m += 1usize
            }
            i += 1usize
        }
        p[k] = ks_pvalue(a, sub[0usize..m])
        let med = median_of(a, sub[0usize..m])
        var zs = 0.0f64
        i = 0usize
        while i < n {
            if grp[i] == ug[k] {
                z[i] = math.abs[f64](r[i] - med)
                zs += z[i]
            }
            i += 1usize
        }
        zm[k] = zs / f64(m)
        k += 1usize
    }
    // Holm: ascending order statistics, multiplier ng - rank, running maximum, capped at 1
    let (ord, e5) = mem.alloc[usize](a, ng)
    if e5 != ok { ret (0usize, e5) }
    k = 0usize
    while k < ng {
        ord[k] = k
        k += 1usize
    }
    k = 1usize
    while k < ng {
        let v = ord[k]
        var j = k
        while j > 0usize && p[ord[j - 1usize]] > p[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        k += 1usize
    }
    var run = 0.0f64
    k = 0usize
    while k < ng {
        var v = f64(ng - k) * p[ord[k]]
        if v > 1.0f64 { v = 1.0f64 }
        if v > run { run = v }
        padj[ord[k]] = run
        k += 1usize
    }
    lev[0usize] = 0.0f64 / 0.0f64
    lev[1usize] = 0.0f64 / 0.0f64
    if ng > 1usize {
        var gm = 0.0f64
        i = 0usize
        while i < n {
            gm += z[i]
            i += 1usize
        }
        gm = gm / f64(n)
        var ssb = 0.0f64
        var ssw = 0.0f64
        k = 0usize
        while k < ng {
            var cnt = 0.0f64
            i = 0usize
            while i < n {
                if grp[i] == ug[k] {
                    cnt += 1.0f64
                    ssw += (z[i] - zm[k]) * (z[i] - zm[k])
                }
                i += 1usize
            }
            ssb += cnt * (zm[k] - gm) * (zm[k] - gm)
            k += 1usize
        }
        let d1 = f64(ng) - 1.0f64
        let d2 = f64(n) - f64(ng)
        let f = (ssb / d1) / (ssw / d2)
        lev[0usize] = f
        lev[1usize] = nb.pf(f, d1, d2, false, false)
    }
    ret (ng, ok)
}
