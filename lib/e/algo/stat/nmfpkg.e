// R NMF: non-negative matrix factorisation by the multiplicative updates of Lee and Seung, value for value with
// nmf(x, rank, method = "brunet" or "lee", seed = <integer>) after the package's own set.seed: the "random" seed
// method (W then H as uniform draws scaled by max(x), column by column), the update rules, the clamp of brunet at
// the machine epsilon every 10th iteration, the unit column sums of W for lee, and the "connectivity" stopping rule
// (the sample classification by the largest entry of each column of H unchanged for more than 40 checks made every 10
// iterations, at most `maxiter` iterations).
//
// Not here: the other algorithms (KL as a separate name, offset, nsNMF, ls-nmf, snmf, pe-nmf), the nndsvd and ica
// seeds, several runs and the rank survey.

use e.algo.rand.r as rng
use e.math
use e.mem

// v is n by p column-major, w n by r, h r by p; method 0 brunet (Kullback-Leibler), 1 lee (Frobenius); out[0] receives the iteration count
fn nmf_fit(a: *mem.Arena, v: []const f64, n: usize, p: usize, rk: usize, method: usize, seed: i64, maxiter: usize, w: []f64, h: []f64, out: []f64) -> err {
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    var mx = v[0usize]
    var q = 1usize
    while q < n * p {
        if v[q] > mx { mx = v[q] }
        q += 1usize
    }
    q = 0usize
    while q < n * rk {
        w[q] = rng.unif(&r) * mx
        q += 1usize
    }
    q = 0usize
    while q < rk * p {
        h[q] = rng.unif(&r) * mx
        q += 1usize
    }
    let (wh, e1) = mem.alloc[f64](a, n * p)
    let (t1, e2) = mem.alloc[f64](a, rk * p)
    let (t2, e3) = mem.alloc[f64](a, n * rk)
    let (cs, e4) = mem.alloc[f64](a, rk)
    let (g, e5) = mem.alloc[f64](a, rk * rk)
    let (old, e6) = mem.alloc[f64](a, p * p)
    let (cur, e7) = mem.alloc[f64](a, p * p)
    let (idx, e8) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    q = 0usize
    while q < p * p {
        old[q] = 0.0f64
        q += 1usize
    }
    let eps = 2.220446049250313e-16f64
    let eps9 = 1.0e-9f64
    var inc = 0usize
    var sn = 0usize
    var smax = 0.0f64 - 1.0f64 / 0.0f64
    var smin = 1.0f64 / 0.0f64
    if method >= 2usize {
        let c0 = nmf_objective(v, w, h, n, p, rk, method % 2usize, wh)
        sn = 1usize
        smax = c0
        smin = c0
    }
    var it = 1usize
    var done = false
    while it <= maxiter && !done {
        if method % 2usize == 0usize {
            matmul(w, h, wh, n, rk, p)
            // h[k, j] *= sum_i w[i, k] v[i, j] / wh[i, j] / colSums(w)[k]
            var k = 0usize
            while k < rk {
                var s = 0.0f64
                var i = 0usize
                while i < n {
                    s += w[k * n + i]
                    i += 1usize
                }
                cs[k] = s
                k += 1usize
            }
            var j = 0usize
            while j < p {
                k = 0usize
                while k < rk {
                    var s = 0.0f64
                    var i = 0usize
                    while i < n {
                        s += w[k * n + i] * (v[j * n + i] / wh[j * n + i])
                        i += 1usize
                    }
                    t1[j * rk + k] = h[j * rk + k] * s / cs[k]
                    k += 1usize
                }
                j += 1usize
            }
            q = 0usize
            while q < rk * p {
                h[q] = t1[q]
                q += 1usize
            }
            matmul(w, h, wh, n, rk, p)
            k = 0usize
            while k < rk {
                var s = 0.0f64
                j = 0usize
                while j < p {
                    s += h[j * rk + k]
                    j += 1usize
                }
                cs[k] = s
                k += 1usize
            }
            k = 0usize
            while k < rk {
                var i = 0usize
                while i < n {
                    var s = 0.0f64
                    j = 0usize
                    while j < p {
                        s += (v[j * n + i] / wh[j * n + i]) * h[j * rk + k]
                        j += 1usize
                    }
                    t2[k * n + i] = w[k * n + i] * s / cs[k]
                    i += 1usize
                }
                k += 1usize
            }
            q = 0usize
            while q < n * rk {
                w[q] = t2[q]
                q += 1usize
            }
            if it % 10usize == 0usize {
                q = 0usize
                while q < rk * p {
                    if h[q] < eps { h[q] = eps }
                    q += 1usize
                }
                q = 0usize
                while q < n * rk {
                    if w[q] < eps { w[q] = eps }
                    q += 1usize
                }
            }
        } else {
            // H = max(H (w'v), eps) / ((w'w) H + eps), every sum in the package's descending order and from the old H
            var k = 0usize
            while k < rk {
                var l = 0usize
                while l < rk {
                    var s = 0.0f64
                    var u = n
                    while u > 0usize {
                        u -= 1usize
                        s += w[k * n + u] * w[l * n + u]
                    }
                    g[l * rk + k] = s
                    l += 1usize
                }
                k += 1usize
            }
            var j = 0usize
            while j < p {
                k = 0usize
                while k < rk {
                    var num = 0.0f64
                    var u = n
                    while u > 0usize {
                        u -= 1usize
                        num += w[k * n + u] * v[j * n + u]
                    }
                    var den = 0.0f64
                    var l = rk
                    while l > 0usize {
                        l -= 1usize
                        den += g[l * rk + k] * h[j * rk + l]
                    }
                    var tv = h[j * rk + k] * num
                    if !(tv > eps9) { tv = eps9 }
                    t1[j * rk + k] = tv / (den + eps9)
                    k += 1usize
                }
                j += 1usize
            }
            q = 0usize
            while q < rk * p {
                h[q] = t1[q]
                q += 1usize
            }
            // W = max(W (v h'), eps) / (W (h h') + eps) row by row, then unit column sums
            k = 0usize
            while k < rk {
                var l = 0usize
                while l < rk {
                    var s = 0.0f64
                    var u = p
                    while u > 0usize {
                        u -= 1usize
                        s += h[u * rk + k] * h[u * rk + l]
                    }
                    g[l * rk + k] = s
                    l += 1usize
                }
                k += 1usize
            }
            var i = 0usize
            while i < n {
                k = 0usize
                while k < rk {
                    var num = 0.0f64
                    var u = p
                    while u > 0usize {
                        u -= 1usize
                        num += v[u * n + i] * h[u * rk + k]
                    }
                    var den = 0.0f64
                    var l = rk
                    while l > 0usize {
                        l -= 1usize
                        den += w[l * n + i] * g[k * rk + l]
                    }
                    var tv = w[k * n + i] * num
                    if tv < eps9 { tv = eps9 }
                    t2[k * n + i] = tv / (den + eps9)
                    k += 1usize
                }
                i += 1usize
            }
            k = 0usize
            while k < rk {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += t2[k * n + i]
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    w[k * n + i] = t2[k * n + i] / s
                    i += 1usize
                }
                k += 1usize
            }
        }
        if method < 2usize && it % 10usize == 0usize {
            var j = 0usize
            while j < p {
                var best = 0usize
                var k = 1usize
                while k < rk {
                    if h[j * rk + k] > h[j * rk + best] { best = k }
                    k += 1usize
                }
                idx[j] = best
                j += 1usize
            }
            var changed = false
            j = 0usize
            while j < p {
                var j2 = 0usize
                while j2 < p {
                    var c = 0.0f64
                    if idx[j] == idx[j2] { c = 1.0f64 }
                    cur[j2 * p + j] = c
                    if c != old[j2 * p + j] { changed = true }
                    j2 += 1usize
                }
                j += 1usize
            }
            if !changed {
                inc += 1usize
            } else {
                q = 0usize
                while q < p * p {
                    old[q] = cur[q]
                    q += 1usize
                }
                inc = 0usize
            }
            if inc > 40usize { done = true }
        }
        if method >= 2usize {
            if sn != 0usize || it % 50usize == 0usize {
                let cv = nmf_objective(v, w, h, n, p, rk, method % 2usize, wh)
                if cv != cv {
                    done = true
                } else {
                    sn += 1usize
                    if cv > smax { smax = cv }
                    if cv < smin { smin = cv }
                    if sn == 11usize {
                        if (smax - smin) / 10.0f64 <= eps { done = true }
                        sn = 0usize
                        smax = 0.0f64 - 1.0f64 / 0.0f64
                        smin = 1.0f64 / 0.0f64
                    }
                }
            }
        }
        if !done { it += 1usize }
    }
    if it > maxiter { it = maxiter }
    out[0usize] = f64(it)
    ret ok
}

// c (n by p) = a (n by k) times b (k by p), all column-major
fn matmul(a: []const f64, b: []const f64, c: []f64, n: usize, k: usize, p: usize) {
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < n {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += a[l * n + i] * b[j * k + l]
                l += 1usize
            }
            c[j * n + i] = s
            i += 1usize
        }
        j += 1usize
    }
}

// the fit measure of nmf as the package's C code sums it (rows then columns, both descending): kind 0 the Kullback-Leibler divergence (a zero entry of v adds the fit), kind 1 half the squared Frobenius distance
fn nmf_objective(v: []const f64, w: []const f64, h: []const f64, n: usize, p: usize, rk: usize, kind: usize, wh: []f64) -> f64 {
    matmul(w, h, wh, n, rk, p)
    var s = 0.0f64
    var i = n
    while i > 0usize {
        i -= 1usize
        var j = p
        while j > 0usize {
            j -= 1usize
            let x = v[j * n + i]
            let y = wh[j * n + i]
            if kind == 0usize {
                var dv = y
                if x != 0.0f64 { dv = x * math.log[f64](x / y) - x + y }
                s += dv
            } else {
                let d = x - y
                s += d * d
            }
        }
    }
    if kind == 1usize { s = s / 2.0f64 }
    ret s
}
