// R NMF: non-negative matrix factorisation by the multiplicative updates of Lee and Seung (and the nsNMF smoothing of Pascual-Montano), value for value with
// nmf(x, rank, method = "brunet" or "lee", seed = <integer>) after the package's own set.seed: the "random" seed
// method (W then H as uniform draws scaled by max(x), column by column), the update rules, the clamp of brunet at
// the machine epsilon every 10th iteration, the unit column sums of W for lee, and the "connectivity" stopping rule
// (the sample classification by the largest entry of each column of H unchanged for more than 40 checks made every 10
// iterations, at most `maxiter` iterations).
//
// Not here: the other algorithms (KL as a separate name, offset, nsNMF, ls-nmf, snmf, pe-nmf), the nndsvd and ica
// seeds, several runs and the rank survey.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.math
use e.mem

// v is n by p column-major, w n by r, h r by p; method 0 brunet (Kullback-Leibler), 1 lee (Frobenius); out[0] receives the iteration count
fn nmf_fit(a: *mem.Arena, v: []const f64, n: usize, p: usize, rk: usize, method: usize, seed: i64, maxiter: usize, theta: f64, init: usize, w: []f64, h: []f64, out: []f64) -> err {
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    var q = 0usize
    if init == 0usize {
        var mx = v[0usize]
        q = 1usize
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
    } else {
        let ne = nndsvd(a, v, n, p, rk, init, w, h)
        if ne != ok { ret ne }
    }
    let (wh, e1) = mem.alloc[f64](a, n * p)
    let (t1, e2) = mem.alloc[f64](a, rk * p)
    let (t2, e3) = mem.alloc[f64](a, n * rk)
    let (cs, e4) = mem.alloc[f64](a, rk)
    let (g, e5) = mem.alloc[f64](a, rk * rk)
    let (old, e6) = mem.alloc[f64](a, p * p)
    let (cur, e7) = mem.alloc[f64](a, p * p)
    let (idx, e8) = mem.alloc[usize](a, p)
    let (off, e12) = mem.alloc[f64](a, n)
    let (rsh, e13) = mem.alloc[f64](a, rk)
    if e12 != ok || e13 != ok { ret mem.Full }
    let (sm, e9) = mem.alloc[f64](a, rk * rk)
    let (ws, e10) = mem.alloc[f64](a, n * rk)
    let (sh, e11) = mem.alloc[f64](a, rk * p)
    if e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    q = 0usize
    while q < rk * rk {
        sm[q] = theta / f64(rk)
        q += 1usize
    }
    q = 0usize
    while q < rk {
        sm[q * rk + q] += 1.0f64 - theta
        q += 1usize
    }
    q = 0usize
    while q < p * p {
        old[q] = 0.0f64
        q += 1usize
    }
    let eps = 2.220446049250313e-16f64
    let eps9 = 1.0e-9f64
    // the offset model seeds a random offset after W and H: uniform on (0, max(W, H))
    var wmax = 0.0f64
    q = 0usize
    while q < n * rk {
        if w[q] > wmax { wmax = w[q] }
        q += 1usize
    }
    q = 0usize
    while q < rk * p {
        if h[q] > wmax { wmax = h[q] }
        q += 1usize
    }
    q = 0usize
    while q < n {
        off[q] = 0.0f64
        if method == 5usize { off[q] = rng.unif(&r) * wmax }
        q += 1usize
    }
    var inc = 0usize
    var sn = 0usize
    var smax = 0.0f64 - 1.0f64 / 0.0f64
    var smin = 1.0f64 / 0.0f64
    var okind = 1usize
    if method == 2usize { okind = 0usize }
    if method == 6usize { okind = 2usize }
    if method == 2usize || method == 3usize || method == 6usize {
        let c0 = nmf_objective(v, w, h, n, p, rk, okind, wh)
        sn = 1usize
        smax = c0
        smin = c0
    }
    var it = 1usize
    var done = false
    while it <= maxiter && !done {
        if method == 4usize {
            // nsNMF: H from the smoothed basis W S, then W against S H, columns of W rescaled
            matmul(w, sm, ws, n, rk, rk)
            matmul(ws, h, wh, n, rk, p)
            var k = 0usize
            while k < rk {
                var s = 0.0f64
                var i = 0usize
                while i < n {
                    s += ws[k * n + i]
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
                        s += ws[k * n + i] * (v[j * n + i] / wh[j * n + i])
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
            matmul(sm, h, sh, rk, rk, p)
            matmul(w, sh, wh, n, rk, p)
            k = 0usize
            while k < rk {
                var s = 0.0f64
                j = 0usize
                while j < p {
                    s += sh[j * rk + k]
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
                        s += (v[j * n + i] / wh[j * n + i]) * sh[j * rk + k]
                        j += 1usize
                    }
                    t2[k * n + i] = w[k * n + i] * s / cs[k]
                    i += 1usize
                }
                k += 1usize
            }
            k = 0usize
            while k < rk {
                var s = 0.0f64
                var i = 0usize
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
        } else if method == 6usize {
            // ls-nmf with unit weights: the package's R-level Euclidean updates, each term clamped at 1e-9, no rescaling, H from W'(WH) and W from (WH) H' with WH refreshed in between
            matmul(w, h, wh, n, rk, p)
            var j = 0usize
            while j < p {
                var k = 0usize
                while k < rk {
                    var num = 0.0f64
                    var den = 0.0f64
                    var i = 0usize
                    while i < n {
                        num += w[k * n + i] * v[j * n + i]
                        den += w[k * n + i] * wh[j * n + i]
                        i += 1usize
                    }
                    var tv = h[j * rk + k] * num
                    if tv < eps9 { tv = eps9 }
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
            matmul(w, h, wh, n, rk, p)
            var k2 = 0usize
            while k2 < rk {
                var i = 0usize
                while i < n {
                    var num = 0.0f64
                    var den = 0.0f64
                    j = 0usize
                    while j < p {
                        num += v[j * n + i] * h[j * rk + k2]
                        den += wh[j * n + i] * h[j * rk + k2]
                        j += 1usize
                    }
                    var tv = w[k2 * n + i] * num
                    if tv < eps9 { tv = eps9 }
                    t2[k2 * n + i] = tv / (den + eps9)
                    i += 1usize
                }
                k2 += 1usize
            }
            q = 0usize
            while q < n * rk {
                w[q] = t2[q]
                q += 1usize
            }
        } else if method % 2usize == 0usize {
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
                    if method == 5usize {
                        var ad = 0.0f64
                        var u2 = n
                        while u2 > 0usize {
                            u2 -= 1usize
                            ad += w[k * n + u2] * off[u2]
                        }
                        den += ad
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
            // W = max(W (v h'), eps) / (W (h h') + eps) row by row, then unit column sums (none for the offset model, whose denominator adds off * rowSums(H))
            k = 0usize
            while k < rk {
                var s = 0.0f64
                var u3 = p
                while u3 > 0usize {
                    u3 -= 1usize
                    s += h[u3 * rk + k]
                }
                rsh[k] = s
                k += 1usize
            }
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
                    if method == 5usize { den += off[i] * rsh[k] }
                    var tv = w[k * n + i] * num
                    if tv < eps9 { tv = eps9 }
                    t2[k * n + i] = tv / (den + eps9)
                    k += 1usize
                }
                i += 1usize
            }
            k = 0usize
            while k < rk {
                var s = 1.0f64
                if method != 5usize {
                    s = 0.0f64
                    i = 0usize
                    while i < n {
                        s += t2[k * n + i]
                        i += 1usize
                    }
                }
                i = 0usize
                while i < n {
                    w[k * n + i] = t2[k * n + i] / s
                    i += 1usize
                }
                k += 1usize
            }
            if method == 5usize {
                matmul(w, h, wh, n, rk, p)
                i = 0usize
                while i < n {
                    var rv = 0.0f64
                    var rf = 0.0f64
                    j = 0usize
                    while j < p {
                        rv += v[j * n + i]
                        rf += wh[j * n + i] + off[i]
                        j += 1usize
                    }
                    var rvm = rv
                    if rvm < eps9 { rvm = eps9 }
                    off[i] = off[i] * rvm / (rf + eps9)
                    i += 1usize
                }
            }
        }
        if (method < 2usize || method == 4usize || method == 5usize) && it % 10usize == 0usize {
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
        if method == 2usize || method == 3usize || method == 6usize {
            if sn != 0usize || it % 50usize == 0usize {
                let cv = nmf_objective(v, w, h, n, p, rk, okind, wh)
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
    if kind == 2usize {
        // sum(((x - fit) * weight)^2) / 2 as R evaluates it: a long-double running sum over the entries in storage order, stood in for by a compensated sum
        var s2 = 0.0f64
        var c2 = 0.0f64
        var q = 0usize
        while q < n * p {
            let d = v[q] - wh[q]
            let term = d * d
            let tt = s2 + term
            if math.abs[f64](s2) >= math.abs[f64](term) { c2 += (s2 - tt) + term } else { c2 += (term - tt) + s2 }
            s2 = tt
            q += 1usize
        }
        ret (s2 + c2) / 2.0f64
    }
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

// the NNDSVD seed of Boutsidis and Gallopoulos as the package ports it: the first singular triplet as absolute values, each later one as the larger of its positive and negative parts,
// values under 1e-10 set to zero; init 1 leaves the zeros, init 2 fills them with the mean of the data (the `average` densify)
fn nndsvd(a: *mem.Arena, v: []const f64, n: usize, p: usize, rk: usize, init: usize, w: []f64, h: []f64) -> err {
    let (sv, e) = decomp.svd(a, v, n, p)
    if e != ok { ret e }
    var q = 0usize
    while q < n * rk {
        w[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < rk * p {
        h[q] = 0.0f64
        q += 1usize
    }
    let s0 = math.sqrt[f64](sv.d[0usize])
    var i = 0usize
    while i < n {
        w[i] = s0 * math.abs[f64](sv.u[i])
        i += 1usize
    }
    var j = 0usize
    while j < p {
        h[j * rk] = s0 * math.abs[f64](sv.v[j])
        j += 1usize
    }
    var k = 1usize
    while k < rk {
        var nup = 0.0f64
        var nun = 0.0f64
        var nvp = 0.0f64
        var nvn = 0.0f64
        i = 0usize
        while i < n {
            let x = sv.u[k * n + i]
            if x >= 0.0f64 { nup += x * x } else { nun += x * x }
            i += 1usize
        }
        j = 0usize
        while j < p {
            let x = sv.v[k * p + j]
            if x >= 0.0f64 { nvp += x * x } else { nvn += x * x }
            j += 1usize
        }
        nup = math.sqrt[f64](nup)
        nun = math.sqrt[f64](nun)
        nvp = math.sqrt[f64](nvp)
        nvn = math.sqrt[f64](nvn)
        let termp = nup * nvp
        let termn = nun * nvn
        var pos = termp >= termn
        var term = termn
        var nu = nun
        var nv = nvn
        if pos {
            term = termp
            nu = nup
            nv = nvp
        }
        let sc = math.sqrt[f64](sv.d[k] * term)
        i = 0usize
        while i < n {
            let x = sv.u[k * n + i]
            var y = 0.0f64
            if pos { if x >= 0.0f64 { y = x } } else { if x < 0.0f64 { y = 0.0f64 - x } }
            w[k * n + i] = sc * y / nu
            i += 1usize
        }
        j = 0usize
        while j < p {
            let x = sv.v[k * p + j]
            var y = 0.0f64
            if pos { if x >= 0.0f64 { y = x } } else { if x < 0.0f64 { y = 0.0f64 - x } }
            h[j * rk + k] = sc * y / nv
            j += 1usize
        }
        k += 1usize
    }
    q = 0usize
    var sm = 0.0f64
    while q < n * p {
        sm += v[q]
        q += 1usize
    }
    let avg = sm / f64(n * p)
    q = 0usize
    while q < n * rk {
        if w[q] < 1.0e-10f64 { w[q] = 0.0f64 }
        if w[q] == 0.0f64 && init == 2usize { w[q] = avg }
        q += 1usize
    }
    q = 0usize
    while q < rk * p {
        if h[q] < 1.0e-10f64 { h[q] = 0.0f64 }
        if h[q] == 0.0f64 && init == 2usize { h[q] = avg }
        q += 1usize
    }
    ret ok
}
