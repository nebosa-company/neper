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
use e.algo.rand.lecuyer as lc
use e.algo.rand.r as rng
use e.algo.stat.hclust as hc
use e.math
use e.mem

// v is n by p column-major, w n by r, h r by p; method 0 brunet (Kullback-Leibler), 1 lee (Frobenius); out[0] receives the iteration count
fn nmf_fit(a: *mem.Arena, v: []const f64, n: usize, p: usize, rk: usize, method: usize, seed: i64, maxiter: usize, theta: f64, init: usize, stream: i64, w: []f64, h: []f64, out: []f64) -> err {
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    var ly: lc.State = zero
    let use_ly = stream >= 0i64
    if use_ly {
        ly = lc.rngseq_start(rng.unif(&r))
        var sj = 0i64
        while sj < stream {
            ly = lc.jump(ly, 0u8)
            sj += 1i64
        }
    }
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
            w[q] = nm_unif(use_ly, &r, &ly) * mx
            q += 1usize
        }
        q = 0usize
        while q < rk * p {
            h[q] = nm_unif(use_ly, &r, &ly) * mx
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
        if method == 5usize { off[q] = nm_unif(use_ly, &r, &ly) * wmax }
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

fn nm_unif(use_ly: bool, r: *rng.Rng, st: *lc.State) -> f64 {
    if use_ly { ret lc.unif(st) }
    ret rng.unif(r)
}

// nmf(x, rank, method, seed, nrun = nrun): the runs take the streams of rngtools::RNGseq(nrun, seed) (each run's random start drawn from its L'Ecuyer-CMRG stream), and the fit with the
// smallest residual is kept (the first of equals); methods 0 to 3. out[0] iterations of the kept run, out[1] its 1-based index, out[2] its residual
fn nmf_runs(a: *mem.Arena, v: []const f64, n: usize, p: usize, rk: usize, method: usize, seed: i64, maxiter: usize, nrun: usize, w: []f64, h: []f64, cons: []f64, out: []f64) -> err {
    let (w1, e1) = mem.alloc[f64](a, n * rk)
    let (h1, e2) = mem.alloc[f64](a, rk * p)
    let (wh, e3) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var kind = 1usize
    if method % 2usize == 0usize { kind = 0usize }
    let (idx, e4) = mem.alloc[usize](a, p)
    if e4 != ok { ret mem.Full }
    var qc = 0usize
    while qc < p * p {
        cons[qc] = 0.0f64
        qc += 1usize
    }
    var best = 1.0f64 / 0.0f64
    var k = 0usize
    while k < nrun {
        var o1: [4]f64 = zero
        let fe = nmf_fit(a, v, n, p, rk, method, seed, maxiter, 0.5f64, 0usize, i64(k), w1, h1, o1[0usize..4usize])
        if fe != ok { ret fe }
        let rs = nmf_objective(v, w1, h1, n, p, rk, kind, wh)
        var jj = 0usize
        while jj < p {
            var bi = 0usize
            var kk = 1usize
            while kk < rk {
                if h1[jj * rk + kk] > h1[jj * rk + bi] { bi = kk }
                kk += 1usize
            }
            idx[jj] = bi
            jj += 1usize
        }
        jj = 0usize
        while jj < p {
            var j2 = 0usize
            while j2 < p {
                if idx[jj] == idx[j2] { cons[j2 * p + jj] += 1.0f64 }
                j2 += 1usize
            }
            jj += 1usize
        }
        if rs < best {
            best = rs
            var q = 0usize
            while q < n * rk {
                w[q] = w1[q]
                q += 1usize
            }
            q = 0usize
            while q < rk * p {
                h[q] = h1[q]
                q += 1usize
            }
            out[0usize] = o1[0usize]
            out[1usize] = f64(k + 1usize)
            out[2usize] = rs
        }
        k += 1usize
    }
    qc = 0usize
    while qc < p * p {
        cons[qc] = cons[qc] / f64(nrun)
        qc += 1usize
    }
    ret ok
}

// cophcor of a consensus matrix: the correlation of the cophenetic distances of the average-linkage tree of 1 - C with those dissimilarities (the lower triangle, column by column, as `dist` stores it)
fn nmf_cophcor(a: *mem.Arena, cons: []const f64, p: usize) -> f64 {
    let (d, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var q = 0usize
    while q < p * p {
        d[q] = 1.0f64 - cons[q]
        q += 1usize
    }
    let (tr, e2) = hc.hclust(a, d, p, 4usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var cnt = 0.0f64
    var sx = 0.0f64
    var sy = 0.0f64
    var j = 0usize
    while j < p {
        var i = j + 1usize
        while i < p {
            sx += d[i * p + j]
            sy += hc.cophenetic(a, &tr, p, i, j)
            cnt += 1.0f64
            i += 1usize
        }
        j += 1usize
    }
    let mx = sx / cnt
    let my = sy / cnt
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    j = 0usize
    while j < p {
        var i = j + 1usize
        while i < p {
            let dx = d[i * p + j] - mx
            let dy = hc.cophenetic(a, &tr, p, i, j) - my
            sxy += dx * dy
            sxx += dx * dx
            syy += dy * dy
            i += 1usize
        }
        j += 1usize
    }
    ret sxy / math.sqrt[f64](sxx * syy)
}

// dispersion of a consensus matrix: the mean of 4 (C - 1/2)^2 over all its entries
fn nmf_dispersion(cons: []const f64) -> f64 {
    var s = 0.0f64
    var q = 0usize
    while q < cons.len {
        s += 4.0f64 * (cons[q] - 0.5f64) * (cons[q] - 0.5f64)
        q += 1usize
    }
    ret s / f64(cons.len)
}

// the average silhouette width of a clustering `cl` (labels 0..) of p points under the dissimilarity d (p by p): the mean of (b - a) / max(a, b), a the mean distance to the other members of
// the point's cluster, b the least mean distance to another cluster, 0 for a singleton, as cluster::silhouette
fn silhouette_avg(a: *mem.Arena, d: []const f64, cl: []const usize, p: usize) -> f64 {
    var kmax = 0usize
    var i = 0usize
    while i < p {
        if cl[i] + 1usize > kmax { kmax = cl[i] + 1usize }
        i += 1usize
    }
    let (cnt, e1) = mem.alloc[f64](a, kmax)
    let (sm, e2) = mem.alloc[f64](a, kmax)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var z0 = 0usize
    while z0 < kmax {
        cnt[z0] = 0.0f64
        z0 += 1usize
    }
    i = 0usize
    while i < p {
        cnt[cl[i]] += 1.0f64
        i += 1usize
    }
    var used = 0usize
    var c = 0usize
    while c < kmax {
        if cnt[c] > 0.0f64 { used += 1usize }
        c += 1usize
    }
    if used < 2usize { ret 0.0f64 / 0.0f64 }
    var tot = 0.0f64
    i = 0usize
    while i < p {
        c = 0usize
        while c < kmax {
            sm[c] = 0.0f64
            c += 1usize
        }
        var j = 0usize
        while j < p {
            if j != i { sm[cl[j]] += d[j * p + i] }
            j += 1usize
        }
        var si = 0.0f64
        if cnt[cl[i]] > 1.0f64 {
            let av = sm[cl[i]] / (cnt[cl[i]] - 1.0f64)
            var bv = 1.0f64 / 0.0f64
            c = 0usize
            while c < kmax {
                if c != cl[i] && cnt[c] > 0.0f64 {
                    let m = sm[c] / cnt[c]
                    if m < bv { bv = m }
                }
                c += 1usize
            }
            var mx = av
            if bv > mx { mx = bv }
            si = (bv - av) / mx
        }
        tot += si
        i += 1usize
    }
    ret tot / f64(p)
}

// summary()$silhouette.consensus: the clusters are the average-linkage tree of 1 - C cut into rk groups, the dissimilarity 1 - C
fn nmf_silhouette_consensus(a: *mem.Arena, cons: []const f64, p: usize, rk: usize) -> f64 {
    let (d, e1) = mem.alloc[f64](a, p * p)
    let (cl, e2) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var q = 0usize
    while q < p * p {
        d[q] = 1.0f64 - cons[q]
        q += 1usize
    }
    let (tr, e3) = hc.hclust(a, d, p, 4usize)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let ce = hc.cutree(a, &tr, p, rk, cl)
    if ce != ok { ret 0.0f64 / 0.0f64 }
    var mn = cl[0usize]
    q = 1usize
    while q < p {
        if cl[q] < mn { mn = cl[q] }
        q += 1usize
    }
    q = 0usize
    while q < p {
        cl[q] -= mn
        q += 1usize
    }
    ret silhouette_avg(a, d, cl, p)
}

// summary()$silhouette.coef: the samples are clustered by the row of the largest entry of their column of H, the dissimilarity 1 - cor of the columns of H
fn nmf_silhouette_coef(a: *mem.Arena, h: []const f64, rk: usize, p: usize) -> f64 {
    let (d, e1) = mem.alloc[f64](a, p * p)
    let (cl, e2) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < p {
        var best = 0usize
        var k = 1usize
        while k < rk {
            if h[j * rk + k] > h[j * rk + best] { best = k }
            k += 1usize
        }
        cl[j] = best
        j += 1usize
    }
    j = 0usize
    while j < p {
        var j2 = 0usize
        while j2 < p {
            var mj = 0.0f64
            var m2 = 0.0f64
            var k = 0usize
            while k < rk {
                mj += h[j * rk + k]
                m2 += h[j2 * rk + k]
                k += 1usize
            }
            mj = mj / f64(rk)
            m2 = m2 / f64(rk)
            var sxy = 0.0f64
            var sxx = 0.0f64
            var syy = 0.0f64
            k = 0usize
            while k < rk {
                let x = h[j * rk + k] - mj
                let y = h[j2 * rk + k] - m2
                sxy += x * y
                sxx += x * x
                syy += y * y
                k += 1usize
            }
            d[j2 * p + j] = 1.0f64 - sxy / math.sqrt[f64](sxx * syy)
            j2 += 1usize
        }
        j += 1usize
    }
    ret silhouette_avg(a, d, cl, p)
}
