// R's mvtnorm densities and generators for matrices given row-major: `dmvnorm` and `dmvt` (log
// densities by the Cholesky factor, as R does, with the point mass at the mean when sigma is singular),
// `rmvnorm` by the symmetric square root (methods "eigen" and "svd" give the same matrix) and by the
// pivoted Cholesky (method "chol"), and `rmvt` (shifted). The normal draws come from e.algo.rand.r in
// the order R takes them: n * p draws filled by row, then the chi-squared draws for rmvt.
//
// Not here: the probabilities and quantiles (pmvnorm, pmvt, qmvnorm, qmvt).

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.math
use e.math.dist as dist
use e.math.special as special
use e.mem

error NotPositive

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// the upper Cholesky factor U (U'U = s), row-major; false when s is not positive definite
fn chol_upper(s: []const f64, p: usize, u: []f64) -> bool {
    var i = 0usize
    while i < p * p {
        u[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var k = 0usize
        var d = s[j * p + j]
        while k < j {
            d -= u[k * p + j] * u[k * p + j]
            k += 1usize
        }
        if !(d > 0.0f64) { ret false }
        let ujj = math.sqrt[f64](d)
        u[j * p + j] = ujj
        var c = j + 1usize
        while c < p {
            var t = s[j * p + c]
            k = 0usize
            while k < j {
                t -= u[k * p + j] * u[k * p + c]
                k += 1usize
            }
            u[j * p + c] = t / ujj
            c += 1usize
        }
        j += 1usize
    }
    ret true
}

// the sum of squares of U'^-1 (x - m) and the sum of log diagonal of U
fn rss_of(u: []const f64, p: usize, x: []const f64, m: []const f64, w: []f64) -> f64 {
    var rss = 0.0f64
    var i = 0usize
    while i < p {
        var t = x[i] - m[i]
        var k = 0usize
        while k < i {
            t -= u[k * p + i] * w[k]
            k += 1usize
        }
        w[i] = t / u[i * p + i]
        rss += w[i] * w[i]
        i += 1usize
    }
    ret rss
}

// log density of one point; the mean carries all the mass when sigma is not positive definite
fn dmvnorm(a: *mem.Arena, x: []const f64, mean: []const f64, sigma: []const f64, p: usize) -> (f64, err) {
    let (u, ue) = mem.alloc[f64](a, p * p)
    if ue != ok { ret (0.0f64, ue) }
    let (w, we) = mem.alloc[f64](a, p)
    if we != ok { ret (0.0f64, we) }
    if !chol_upper(sigma, p, u) {
        var same = true
        var i = 0usize
        while i < p {
            if x[i] != mean[i] { same = false }
            i += 1usize
        }
        if same { ret (1.0f64 / 0.0f64, ok) }
        ret (0.0f64 - 1.0f64 / 0.0f64, ok)
    }
    let rss = rss_of(u, p, x, mean, w)
    var sl = 0.0f64
    var i = 0usize
    while i < p {
        sl += math.log[f64](u[i * p + i])
        i += 1usize
    }
    ret (0.0f64 - sl - 0.5f64 * f64(p) * math.log[f64](2.0f64 * 3.141592653589793f64) - 0.5f64 * rss, ok)
}

fn dmvt(a: *mem.Arena, x: []const f64, delta: []const f64, sigma: []const f64, p: usize, df: f64) -> (f64, err) {
    if df == 0.0f64 || df > 1.7976931348623157e308f64 {
        let (v, e) = dmvnorm(a, x, delta, sigma, p)
        ret (v, e)
    }
    let (u, ue) = mem.alloc[f64](a, p * p)
    if ue != ok { ret (0.0f64, ue) }
    let (w, we) = mem.alloc[f64](a, p)
    if we != ok { ret (0.0f64, we) }
    if !chol_upper(sigma, p, u) {
        var same = true
        var i = 0usize
        while i < p {
            if x[i] != delta[i] { same = false }
            i += 1usize
        }
        if same { ret (1.0f64 / 0.0f64, ok) }
        ret (0.0f64 - 1.0f64 / 0.0f64, ok)
    }
    let rss = rss_of(u, p, x, delta, w)
    var sl = 0.0f64
    var i = 0usize
    while i < p {
        sl += math.log[f64](u[i * p + i])
        i += 1usize
    }
    let pf = f64(p)
    ret (special.lgamma((pf + df) / 2.0f64) - (special.lgamma(df / 2.0f64) + sl + pf / 2.0f64 * math.log[f64](3.141592653589793f64 * df)) - 0.5f64 * (df + pf) * dist.log1p(rss / df), ok)
}

// the symmetric square root by cyclic Jacobi rotations: V diag(sqrt(max(l, 0))) V'
fn sym_sqrt(a: *mem.Arena, s: []const f64, p: usize, out: []f64) -> err {
    let (m, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    let (v, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < p * p {
        m[i] = s[i]
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        v[i * p + i] = 1.0f64
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 100usize {
        var off = 0.0f64
        var q = 0usize
        while q < p {
            var r = q + 1usize
            while r < p {
                off += m[q * p + r] * m[q * p + r]
                r += 1usize
            }
            q += 1usize
        }
        if off < 1.0e-300f64 { break }
        q = 0usize
        while q + 1usize < p {
            var r = q + 1usize
            while r < p {
                let apq = m[q * p + r]
                if apq != 0.0f64 {
                    let theta = (m[r * p + r] - m[q * p + q]) / (2.0f64 * apq)
                    var t = 1.0f64 / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0f64))
                    if theta < 0.0f64 { t = 0.0f64 - t }
                    let c = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let sn = t * c
                    var k = 0usize
                    while k < p {
                        let akp = m[k * p + q]
                        let akq = m[k * p + r]
                        m[k * p + q] = c * akp - sn * akq
                        m[k * p + r] = sn * akp + c * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let apk = m[q * p + k]
                        let aqk = m[r * p + k]
                        m[q * p + k] = c * apk - sn * aqk
                        m[r * p + k] = sn * apk + c * aqk
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let vkp = v[k * p + q]
                        let vkq = v[k * p + r]
                        v[k * p + q] = c * vkp - sn * vkq
                        v[k * p + r] = sn * vkp + c * vkq
                        k += 1usize
                    }
                }
                r += 1usize
            }
            q += 1usize
        }
        sweep += 1usize
    }
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var t = 0.0f64
            var k = 0usize
            while k < p {
                var lam = m[k * p + k]
                if lam < 0.0f64 { lam = 0.0f64 }
                t += v[r * p + k] * math.sqrt[f64](lam) * v[c * p + k]
                k += 1usize
            }
            out[r * p + c] = t
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// the pivoted Cholesky of LAPACK's dpstrf, R[, order(pivot)]: an upper factor whose crossproduct is sigma
fn chol_pivot(a: *mem.Arena, s: []const f64, p: usize, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    let (piv, e2) = mem.alloc[usize](a, p)
    if e2 != ok { ret e2 }
    var i = 0usize
    var maxd = 0.0f64
    while i < p * p {
        w[i] = s[i]
        i += 1usize
    }
    i = 0usize
    while i < p {
        piv[i] = i
        if s[i * p + i] > maxd { maxd = s[i * p + i] }
        i += 1usize
    }
    let stop = f64(p) * 2.220446049250313e-16f64 * maxd
    var j = 0usize
    while j < p {
        // largest remaining diagonal
        var pv = j
        var best = w[j * p + j]
        i = j + 1usize
        while i < p {
            if w[i * p + i] > best {
                best = w[i * p + i]
                pv = i
            }
            i += 1usize
        }
        if pv != j {
            var k = 0usize
            while k < p {
                let t = w[j * p + k]
                w[j * p + k] = w[pv * p + k]
                w[pv * p + k] = t
                k += 1usize
            }
            k = 0usize
            while k < p {
                let t = w[k * p + j]
                w[k * p + j] = w[k * p + pv]
                w[k * p + pv] = t
                k += 1usize
            }
            let t2 = piv[j]
            piv[j] = piv[pv]
            piv[pv] = t2
        }
        let d = w[j * p + j]
        if !(d > stop) && j > 0usize { ret NotPositive }
        if !(d > 0.0f64) { ret NotPositive }
        let ujj = math.sqrt[f64](d)
        w[j * p + j] = ujj
        var c = j + 1usize
        while c < p {
            w[j * p + c] = w[j * p + c] / ujj
            c += 1usize
        }
        // update the trailing block
        var r = j + 1usize
        while r < p {
            c = r
            while c < p {
                w[r * p + c] -= w[j * p + r] * w[j * p + c]
                w[c * p + r] = w[r * p + c]
                c += 1usize
            }
            r += 1usize
        }
        j += 1usize
    }
    // out[, order(piv)] of the upper triangle: column piv[k] of the result is column k of the factor
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            out[r * p + c] = 0.0f64
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < p {
        var c = r
        while c < p {
            out[r * p + piv[c]] = w[r * p + c]
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// rmvnorm(n, mean, sigma, method): method 0 eigen or svd, 1 chol; the n x p result row-major
fn rmvnorm(a: *mem.Arena, r: *rng.Rng, n: usize, mean: []const f64, sigma: []const f64, p: usize, method: u8) -> ([]f64, err) {
    var none: []f64 = zero
    let (fac, fe) = mem.alloc[f64](a, p * p)
    if fe != ok { ret (none, fe) }
    var e = ok
    if method == 1u8 { e = chol_pivot(a, sigma, p, fac) } else { e = sym_sqrt(a, sigma, p, fac) }
    if e != ok { ret (none, e) }
    let (z, ze) = mem.alloc[f64](a, n * p)
    if ze != ok { ret (none, ze) }
    var i = 0usize
    while i < n * p {
        z[i] = rng.norm(r)
        i += 1usize
    }
    let (out, oe) = mem.alloc[f64](a, n * p)
    if oe != ok { ret (none, oe) }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            var t = 0.0f64
            var k = 0usize
            while k < p {
                t += z[i * p + k] * fac[k * p + j]
                k += 1usize
            }
            out[i * p + j] = t + mean[j]
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// rmvt(n, sigma, df, delta) of type "shifted"
fn rmvt(a: *mem.Arena, r: *rng.Rng, n: usize, sigma: []const f64, p: usize, df: f64, delta: []const f64, method: u8) -> ([]f64, err) {
    var zero_mean: []f64 = zero
    let (zm, ze) = mem.alloc[f64](a, p)
    if ze != ok { ret (zero_mean, ze) }
    var i = 0usize
    while i < p {
        zm[i] = 0.0f64
        i += 1usize
    }
    let (sims, se) = rmvnorm(a, r, n, zm, sigma, p, method)
    if se != ok { ret (zero_mean, se) }
    i = 0usize
    while i < n {
        let w = math.sqrt[f64](rd.rchisq(r, df) / df)
        var j = 0usize
        while j < p {
            sims[i * p + j] = sims[i * p + j] / w + delta[j]
            j += 1usize
        }
        i += 1usize
    }
    ret (sims, ok)
}
