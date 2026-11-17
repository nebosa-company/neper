// The numerics R mice's samplers share, in the form micefull.e calls them: the Cholesky inverse of a symmetric positive definite matrix (what mice's estimice
// takes from lm.fit's R), `matchindex` (the predictive-mean-matching donor draw of mice's C++ code, ties shuffled by a permutation of the donors first),
// Rubin's pool.scalar, the logit family's clamps and binomial deviance, and glm.fit's weighted logit with its Cholesky factor (chol_lower). The sampler itself is micefull.e.

use e.algo.rand.r as rng
use e.math
use e.mem

error Singular

// the inverse of the symmetric positive definite q by q matrix a (row-major) into inv by Cholesky; false when not positive definite
fn spd_inverse(a: []const f64, q: usize, inv: []f64, l: []f64) -> bool {
    var i = 0usize
    while i < q {
        var j = 0usize
        while j <= i {
            var s = a[i * q + j]
            var k = 0usize
            while k < j {
                s -= l[i * q + k] * l[j * q + k]
                k += 1usize
            }
            if i == j {
                if s <= 0.0f64 { ret false }
                l[i * q + i] = math.sqrt[f64](s)
            } else {
                l[i * q + j] = s / l[j * q + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    // inverse columns by forward and back substitution
    var c = 0usize
    while c < q {
        var y: [32]f64 = zero
        i = 0usize
        while i < q {
            var s = 0.0f64
            if i == c { s = 1.0f64 }
            var k = 0usize
            while k < i {
                s -= l[i * q + k] * y[k]
                k += 1usize
            }
            y[i] = s / l[i * q + i]
            i += 1usize
        }
        i = q
        while i > 0usize {
            i -= 1usize
            var s = y[i]
            var k = i + 1usize
            while k < q {
                s -= l[k * q + i] * inv[k * q + c]
                k += 1usize
            }
            inv[i * q + c] = s / l[i * q + i]
        }
        c += 1usize
    }
    ret true
}

// mice's matchindex: the 0-based index in d of a donor drawn among the k nearest to each target (ties shuffled by a permutation of the donors, then a pre-drawn rank in 1..k per target)
fn matchindex(a: *mem.Arena, r: *rng.Rng, d: []const f64, tv: []const f64, k0: usize) -> ([]usize, err) {
    var none: []usize = zero
    let n1 = d.len
    let n0 = tv.len
    let (ish, e1) = rng.sample_int(a, r, i64(n1), i64(n1), false)
    if e1 != ok { ret (none, e1) }
    let (srt, e2) = mem.alloc[usize](a, n1)
    let (id, e3) = mem.alloc[usize](a, n1)
    let (ys, e4) = mem.alloc[f64](a, n1)
    let (idx, e5) = mem.alloc[usize](a, n0)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (none, mem.Full) }
    var i = 0usize
    while i < n1 {
        srt[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n1 {
        let ti = srt[i]
        let tvv = d[usize(ish[ti]) - 1usize]
        var j = i
        while j > 0usize && d[usize(ish[srt[j - 1usize]]) - 1usize] > tvv {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = ti
        i += 1usize
    }
    i = 0usize
    while i < n1 {
        id[i] = usize(ish[srt[i]]) - 1usize
        ys[i] = d[id[i]]
        i += 1usize
    }
    var k = k0
    if k > n1 { k = n1 }
    if k < 1usize { k = 1usize }
    let (h, e6) = rng.sample_int(a, r, i64(k), i64(n0), true)
    if e6 != ok { ret (none, e6) }
    i = 0usize
    while i < n0 {
        let val = tv[i]
        let hi = usize(h[i])
        var count = 0usize
        var lo = 0usize
        var hi2 = n1
        while lo < hi2 {
            let mid = (lo + hi2) / 2usize
            if ys[mid] < val { lo = mid + 1usize } else { hi2 = mid }
        }
        var rr = lo
        var ll = i64(lo) - 1i64
        var res = 0usize
        while count < hi && ll >= 0i64 && rr < n1 {
            if val - ys[usize(ll)] < ys[rr] - val {
                res = id[usize(ll)]
                ll -= 1i64
            } else {
                res = id[rr]
                rr += 1usize
            }
            count += 1usize
        }
        while count < hi && ll >= 0i64 {
            res = id[usize(ll)]
            ll -= 1i64
            count += 1usize
        }
        while count < hi && rr < n1 {
            res = id[rr]
            rr += 1usize
            count += 1usize
        }
        idx[i] = res
        i += 1usize
    }
    ret (idx, ok)
}

fn bin_dev(y: f64, mu: f64, w: f64) -> f64 {
    var t1 = 0.0f64
    if y > 0.0f64 { t1 = y * math.log[f64](y / mu) }
    var t2 = 0.0f64
    if y < 1.0f64 { t2 = (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
    ret 2.0f64 * w * (t1 + t2)
}

// mice::pool.scalar (Rubin 1987): out receives qbar, ubar, b, t, df, r and fmi for the m estimates q with variances u, a complete-data df of n - k (n infinite when not finite)
fn pool_scalar(q: []const f64, u: []const f64, n: f64, k: f64, out: []f64) {
    let m = q.len
    let mf = f64(m)
    var qb = 0.0f64
    var ub = 0.0f64
    var i = 0usize
    while i < m {
        qb += q[i]
        ub += u[i]
        i += 1usize
    }
    qb = qb / mf
    ub = ub / mf
    var b = 0.0f64
    i = 0usize
    while i < m {
        b += (q[i] - qb) * (q[i] - qb)
        i += 1usize
    }
    b = b / (mf - 1.0f64)
    let r = (1.0f64 + 1.0f64 / mf) * b / ub
    let t = ub + (mf + 1.0f64) * b / mf
    let lambda = (1.0f64 + 1.0f64 / mf) * b / t
    let dfold = (mf - 1.0f64) / (lambda * lambda)
    var df = dfold
    let dfcom = n - k
    if dfcom - dfcom == 0.0f64 {
        let tmp = (1.0f64 - lambda) * (1.0f64 + dfcom) * dfcom
        df = (mf - 1.0f64) * tmp / ((dfcom + 3.0f64) * (mf - 1.0f64) + lambda * lambda * tmp)
    }
    out[0usize] = qb
    out[1usize] = ub
    out[2usize] = b
    out[3usize] = t
    out[4usize] = df
    out[5usize] = r
    out[6usize] = (r + 2.0f64 / (df + 3.0f64)) / (r + 1.0f64)
}

// R's logit family: the linear predictor is clamped at +-30 (linkinv at DBL_EPSILON and its reciprocal, mu.eta at DBL_EPSILON)
fn logit_inv(eta: f64) -> f64 {
    var tmp = 0.0f64
    if eta < 0.0f64 - 30.0f64 {
        tmp = 2.220446049250313e-16f64
    } else if eta > 30.0f64 {
        tmp = 1.0f64 / 2.220446049250313e-16f64
    } else {
        tmp = math.exp[f64](eta)
    }
    ret tmp / (1.0f64 + tmp)
}

fn logit_mu_eta(eta: f64) -> f64 {
    if eta > 30.0f64 || eta < 0.0f64 - 30.0f64 { ret 2.220446049250313e-16f64 }
    let e = math.exp[f64](eta)
    ret e / ((1.0f64 + e) * (1.0f64 + e))
}

// the lower Cholesky factor of the symmetric positive definite q by q matrix c (row-major) into l; false when it is not positive definite
fn chol_lower(c: []const f64, q: usize, l: []f64) -> bool {
    var s1 = 0usize
    while s1 < q {
        var s2 = 0usize
        while s2 <= s1 {
            var s = c[s1 * q + s2]
            var k = 0usize
            while k < s2 {
                s -= l[s1 * q + k] * l[s2 * q + k]
                k += 1usize
            }
            if s1 == s2 {
                if s <= 0.0f64 { ret false }
                l[s1 * q + s1] = math.sqrt[f64](s)
            } else {
                l[s1 * q + s2] = s / l[s2 * q + s2]
            }
            s2 += 1usize
        }
        s1 += 1usize
    }
    ret true
}

// glm.fit(x, y, weights, quasibinomial()): x is n by cd column-major with the intercept, coef the coefficients and covu the unscaled covariance of the last iteration (row-major); the answer is whether it converged in 25 iterations
fn glm_logit(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, cd: usize, coef: []f64, covu: []f64) -> (bool, err) {
    let (eta, e1) = mem.alloc[f64](a, n)
    let (xtx, e2) = mem.alloc[f64](a, cd * cd)
    let (xtz, e3) = mem.alloc[f64](a, cd)
    let (lw, e4) = mem.alloc[f64](a, cd * cd)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (false, mem.Full) }
    var q = 0usize
    while q < n {
        let mu0 = (w[q] * y[q] + 0.5f64) / (w[q] + 1.0f64)
        eta[q] = math.log[f64](mu0 / (1.0f64 - mu0))
        q += 1usize
    }
    var devold = 0.0f64
    q = 0usize
    while q < n {
        devold += bin_dev(y[q], logit_inv(eta[q]), w[q])
        q += 1usize
    }
    var conv = false
    var iter = 0usize
    while !conv && iter < 25usize {
        iter += 1usize
        var s1 = 0usize
        while s1 < cd {
            xtz[s1] = 0.0f64
            var s2 = 0usize
            while s2 < cd {
                xtx[s1 * cd + s2] = 0.0f64
                s2 += 1usize
            }
            s1 += 1usize
        }
        q = 0usize
        while q < n {
            let mu = logit_inv(eta[q])
            let me = logit_mu_eta(eta[q])
            let wq = w[q] * me * me / (mu * (1.0f64 - mu))
            let z = eta[q] + (y[q] - mu) / me
            s1 = 0usize
            while s1 < cd {
                xtz[s1] += wq * x[s1 * n + q] * z
                var s2 = 0usize
                while s2 < cd {
                    xtx[s1 * cd + s2] += wq * x[s1 * n + q] * x[s2 * n + q]
                    s2 += 1usize
                }
                s1 += 1usize
            }
            q += 1usize
        }
        if !spd_inverse(xtx, cd, covu, lw) { ret (false, Singular) }
        s1 = 0usize
        while s1 < cd {
            var s = 0.0f64
            var s2 = 0usize
            while s2 < cd {
                s += covu[s1 * cd + s2] * xtz[s2]
                s2 += 1usize
            }
            coef[s1] = s
            s1 += 1usize
        }
        var dev = 0.0f64
        q = 0usize
        while q < n {
            var e = 0.0f64
            s1 = 0usize
            while s1 < cd {
                e += x[s1 * n + q] * coef[s1]
                s1 += 1usize
            }
            eta[q] = e
            dev += bin_dev(y[q], logit_inv(e), w[q])
            q += 1usize
        }
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 {
            conv = true
        } else {
            devold = dev
        }
    }
    ret (conv, ok)
}
