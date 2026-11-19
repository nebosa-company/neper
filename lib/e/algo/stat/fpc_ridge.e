// R fpc: ridgeline, dridgeline, piridge, piridge.zeroes, ridgeline.diagnosis and mergenormals with method "ridge.uni" and "ridge.ratio". Matrices are row-major,
// the covariance array is k blocks of d by d.
//
// mergenormals with "dipuni" and "diptantrum" (dipm) goes through diptest.multi. Not here: "predictive" and the plots.

use e.algo.rand.r as rg
use e.algo.stat.fpc as fp
use e.algo.stat.fpc_dip as fd
use e.algo.stat.fpc_coord as fc
use e.math
use e.math.dist as dist
use e.mem

error Malformed

// the density of N(mu, sg) at x: dnorm for one dimension, mvtnorm::dmvnorm (Cholesky) otherwise
fn dens(a: *mem.Arena, x: []const f64, mu: []const f64, sg: []const f64, d: usize) -> f64 {
    if d == 1usize { ret dist.dnorm(x[0usize], mu[0usize], math.sqrt[f64](sg[0usize]), false) }
    let (u, e1) = mem.alloc[f64](a, d * d)
    let (t, e2) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < d * d {
        u[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < d {
        i = 0usize
        while i <= j {
            var s = sg[i * d + j]
            var q = 0usize
            while q < i {
                s -= u[q * d + i] * u[q * d + j]
                q += 1usize
            }
            if i == j {
                u[j * d + j] = math.sqrt[f64](s)
            } else {
                u[i * d + j] = s / u[i * d + i]
            }
            i += 1usize
        }
        j += 1usize
    }
    // solve t(u) tmp = x - mu, forward
    var rss = 0.0f64
    var logdet = 0.0f64
    i = 0usize
    while i < d {
        var s = x[i] - mu[i]
        var q = 0usize
        while q < i {
            s -= u[q * d + i] * t[q]
            q += 1usize
        }
        t[i] = s / u[i * d + i]
        rss += t[i] * t[i]
        logdet += math.log[f64](u[i * d + i])
        i += 1usize
    }
    ret math.exp[f64](0.0f64 - logdet - 0.5f64 * f64(d) * math.log[f64](2.0f64 * 3.141592653589793f64) - 0.5f64 * rss)
}

// ridgeline(alpha, mu1, mu2, Sigma1, Sigma2) with the inverses s1i and s2i of the covariances given
fn ridgeline(a: *mem.Arena, alpha: f64, mu1: []const f64, mu2: []const f64, s1i: []const f64, s2i: []const f64, d: usize, out: []f64) -> err {
    let (am, e1) = mem.alloc[f64](a, d * d)
    let (ai, e2) = mem.alloc[f64](a, d * d)
    let (b1, e3) = mem.alloc[f64](a, d)
    let (b2, e4) = mem.alloc[f64](a, d)
    let (bb, e5) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret Malformed }
    let alpha2 = 1.0f64 - alpha
    var i = 0usize
    while i < d * d {
        am[i] = alpha * s1i[i] + alpha2 * s2i[i]
        i += 1usize
    }
    fc.mm(s1i, d, d, mu1, 1usize, b1)
    fc.mm(s2i, d, d, mu2, 1usize, b2)
    i = 0usize
    while i < d {
        bb[i] = alpha * b1[i] + alpha2 * b2[i]
        i += 1usize
    }
    let e6 = fp.lu_inverse(a, am, d, ai)
    if e6 != ok { ret e6 }
    fc.mm(ai, d, d, bb, 1usize, out)
    ret ok
}

// the density of the mixture prop N1 + (1 - prop) N2 on the ridgeline point for alpha (dridgeline) and the posterior piridge
fn ridge_values(a: *mem.Arena, alpha: f64, prop: f64, mu1: []const f64, mu2: []const f64, s1: []const f64, s2: []const f64, s1i: []const f64, s2i: []const f64, d: usize) -> (f64, f64, err) {
    let (r, e1) = mem.alloc[f64](a, d)
    if e1 != ok { ret (0.0f64, 0.0f64, Malformed) }
    let e2 = ridgeline(a, alpha, mu1, mu2, s1i, s2i, d, r)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    let f1 = dens(a, r, mu1, s1, d)
    let f2 = dens(a, r, mu2, s2, d)
    let dr = prop * f1 + (1.0f64 - prop) * f2
    let alpha2 = 1.0f64 - alpha
    var pir = 1.0f64 / (1.0f64 + alpha2 * f1 / (alpha * f2))
    if pir != pir && alpha < 1.0e-8f64 { pir = 0.0f64 }
    if pir != pir && alpha > 1.0f64 - 1.0e-8f64 { pir = 1.0f64 }
    ret (dr, pir, ok)
}

// piridge.zeroes(prop, mu1, mu2, S1, S2, by) followed by dridgeline at the roots: nz, the roots (ascending, into roots) and their densities (into dens_out)
fn piridge_zeroes(a: *mem.Arena, prop: f64, mu1: []const f64, mu2: []const f64, s1: []const f64, s2: []const f64, d: usize, by: f64, roots: []f64, dens_out: []f64) -> (usize, err) {
    let (s1i, e1) = mem.alloc[f64](a, d * d)
    let (s2i, e2) = mem.alloc[f64](a, d * d)
    if e1 != ok || e2 != ok { ret (0usize, Malformed) }
    let e3 = fp.lu_inverse(a, s1, d, s1i)
    if e3 != ok { ret (0usize, e3) }
    let e4 = fp.lu_inverse(a, s2, d, s2i)
    if e4 != ok { ret (0usize, e4) }
    let la = usize(math.floor[f64](1.0f64 / by + 1.0e-10f64)) + 1usize
    let (sgn, e5) = mem.alloc[f64](a, la)
    if e5 != ok { ret (0usize, Malformed) }
    var i = 0usize
    while i < la {
        let al = f64(i) * by
        let start = mem.mark(a)
        let (_, pir, e6) = ridge_values(a, al, prop, mu1, mu2, s1, s2, s1i, s2i, d)
        mem.reset(a, start)
        if e6 != ok { ret (0usize, e6) }
        var v = pir - prop
        if v != v { v = 0.0f64 }
        sgn[i] = 0.0f64
        if v > 0.0f64 { sgn[i] = 1.0f64 }
        if v < 0.0f64 { sgn[i] = -1.0f64 }
        i += 1usize
    }
    var nz = 0usize
    i = 0usize
    while i < la {
        if sgn[i] == 0.0f64 {
            roots[nz] = f64(i) * by
            nz += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < la {
        var df = sgn[i] - sgn[i - 1usize]
        if df < 0.0f64 { df = 0.0f64 - df }
        if df == 2.0f64 {
            roots[nz] = f64(i) * by - by / 2.0f64
            nz += 1usize
        }
        i += 1usize
    }
    fp.cs_sort(roots, nz)
    i = 0usize
    while i < nz {
        let start = mem.mark(a)
        let (dr, _, e7) = ridge_values(a, roots[i], prop, mu1, mu2, s1, s2, s1i, s2i, d)
        mem.reset(a, start)
        if e7 != ok { ret (0usize, e7) }
        dens_out[i] = dr
        i += 1usize
    }
    ret (nz, ok)
}

// the pair (i, j) of ridgeline.diagnosis: returns (number of zeroes, ratio, ratio_is_one_sided)
fn ridge_pair(a: *mem.Arena, probs: []const f64, mu: []const f64, sg: []const f64, d: usize, i: usize, j: usize, by: f64) -> (usize, f64, err) {
    let la = usize(math.floor[f64](1.0f64 / by + 1.0e-10f64)) + 1usize
    let (roots, e1) = mem.alloc[f64](a, 2usize * la)
    let (dv, e2) = mem.alloc[f64](a, 2usize * la)
    if e1 != ok || e2 != ok { ret (0usize, 0.0f64, Malformed) }
    let propij = probs[i] / (probs[i] + probs[j])
    let (nz, e3) = piridge_zeroes(a, propij, mu[i * d..i * d + d], mu[j * d..j * d + d], sg[i * d * d..(i + 1usize) * d * d], sg[j * d * d..(j + 1usize) * d * d], d, by, roots, dv)
    if e3 != ok { ret (0usize, 0.0f64, e3) }
    var ratio = 1.0f64
    if nz >= 1usize {
        var mn = dv[0usize]
        var q = 0usize
        while q < nz {
            if dv[q] < mn { mn = dv[q] }
            q += 1usize
        }
        var ends = dv[0usize]
        if dv[nz - 1usize] < ends { ends = dv[nz - 1usize] }
        if ends > 0.0f64 { ratio = mn / ends }
    }
    ret (nz, ratio, ok)
}

// ridgeline.diagnosis(probs, mu, Sigma, k, ipairs = "all", compute.ratio, by, ratiocutoff): con (k by k, 0/1) and rat (k by k) for all pairs i < j
fn ridge_diag(a: *mem.Arena, probs: []const f64, mu: []const f64, sg: []const f64, d: usize, k: usize, compute_ratio: bool, by: f64, ratiocutoff: f64, use_cutoff: bool, con: []f64, rat: []f64) -> err {
    var i = 0usize
    while i < k * k {
        con[i] = 0.0f64
        rat[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        con[i * k + i] = 1.0f64
        rat[i * k + i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i + 1usize < k {
        var j = i + 1usize
        while j < k {
            let (nz, ratio, e1) = ridge_pair(a, probs, mu, sg, d, i, j, by)
            if e1 != ok { ret e1 }
            var cv = 0.0f64
            if nz < 2usize { cv = 1.0f64 }
            if compute_ratio {
                rat[i * k + j] = ratio
                rat[j * k + i] = ratio
                if use_cutoff {
                    cv = 0.0f64
                    if ratio >= ratiocutoff { cv = 1.0f64 }
                }
            }
            con[i * k + j] = cv
            con[j * k + i] = cv
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// diptest.multi of the points of the original components i and j (0-based; labels i + 1 and j + 1 of clu)
fn dipm_pair(a: *mem.Arena, g: *rg.Rng, x: []const f64, n: usize, d: usize, clu: []const usize, i: usize, j: usize) -> (f64, err) {
    var m = 0usize
    var r = 0usize
    while r < n {
        if clu[r] == i + 1usize || clu[r] == j + 1usize { m += 1usize }
        r += 1usize
    }
    let (xs, e1) = mem.alloc[f64](a, m * d)
    let (ls, e2) = mem.alloc[usize](a, m)
    if e1 != ok || e2 != ok { ret (0.0f64, Malformed) }
    var t = 0usize
    r = 0usize
    while r < n {
        if clu[r] == i + 1usize || clu[r] == j + 1usize {
            var c = 0usize
            while c < d {
                xs[t * d + c] = x[r * d + c]
                c += 1usize
            }
            ls[t] = clu[r]
            t += 1usize
        }
        r += 1usize
    }
    let (pv, e3) = fd.diptest_multi(a, g, xs, m, d, ls, 100usize)
    ret (pv, e3)
}

// mergenormals(method = "ridge.uni" (ratio false) or "ridge.ratio" (ratio true)); the arguments and results are those of merge_bhat in e.algo.stat.fpc
fn merge_ridge(a: *mem.Arena, x: []const f64, n: usize, d: usize, k: usize, probs: []f64, mu: []f64, sg: []f64, z: []f64, cutoff: f64, by: f64, ratio: bool, map: []usize, vals: []f64, dipm: bool, clu: []const usize, g: *rg.Rng) -> (usize, err) {
    let (bm, e0) = mem.alloc[f64](a, k * k)
    let (dead, e1) = mem.alloc[bool](a, k)
    let (dec, e2) = mem.alloc[f64](a, k * k)
    let (join, e3) = mem.alloc[f64](a, k * k)
    let (con, e4) = mem.alloc[f64](a, k * k)
    let (rat, e5) = mem.alloc[f64](a, k * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0usize, mem.Full) }
    var i = 0usize
    while i < k {
        dead[i] = false
        map[i] = i
        i += 1usize
    }
    i = 0usize
    while i < k * k {
        bm[i] = 0.0f64
        dec[i] = 0.0f64
        join[i] = 0.0f64
        i += 1usize
    }
    var nv = 0usize
    var all = true
    var upi = 0usize
    var nup = 1usize
    var loop = true
    while loop {
        if nup != 0usize {
            // the connection (and ratio) of the pairs to refresh: every pair, then those against the merged component upi
            let e6 = ridge_diag(a, probs, mu, sg, d, k, ratio, by, cutoff, ratio && !dipm, con, rat)
            if e6 != ok { ret (0usize, e6) }
            var p = 0usize
            while p < k {
                var q = p + 1usize
                while q < k {
                    var need = all
                    if !all && ((p == upi && q != upi) || (q == upi && p != upi)) && !dead[p] && !dead[q] { need = true }
                    if need && !dead[p] && !dead[q] {
                        if ratio {
                            join[p * k + q] = con[p * k + q]
                            if dipm { join[p * k + q] = rat[p * k + q] }
                            dec[p * k + q] = rat[p * k + q]
                        } else {
                            join[p * k + q] = con[p * k + q]
                            let (bd, eb) = fp.bhattacharyya_dist(a, mu[p * d..p * d + d], mu[q * d..q * d + d], sg[p * d * d..(p + 1usize) * d * d], sg[q * d * d..(q + 1usize) * d * d], d)
                            if eb != ok { ret (0usize, eb) }
                            bm[p * k + q] = math.exp[f64](0.0f64 - bd)
                        }
                    } else if !ratio && !all {
                        // ridge.uni builds the connection matrix from the refreshed pairs alone
                        join[p * k + q] = 0.0f64
                    }
                    q += 1usize
                }
                p += 1usize
            }
            if !ratio {
                p = 0usize
                while p < k * k {
                    dec[p] = bm[p]
                    p += 1usize
                }
            }
            p = 0usize
            while p < k {
                if dead[p] {
                    var q = 0usize
                    while q < k {
                        join[p * k + q] = 0.0f64
                        join[q * k + p] = 0.0f64
                        dec[p * k + q] = 0.0f64
                        dec[q * k + p] = 0.0f64
                        q += 1usize
                    }
                }
                p += 1usize
            }
            // the lower triangle and the diagonal are zero
            p = 0usize
            while p < k {
                var q = 0usize
                while q <= p {
                    join[p * k + q] = 0.0f64
                    dec[p * k + q] = 0.0f64
                    q += 1usize
                }
                p += 1usize
            }
            if dipm {
                // dipuni / diptantrum: the pairs whose ratio is 1 are tested with diptest.multi on the original labels of the two components; the best p value decides
                var q2 = 0usize
                while q2 < k * k {
                    dec[q2] = join[q2]
                    q2 += 1usize
                }
                var pi0 = k
                var pj0 = k
                var jb = 0.0f64
                var njp = 0usize
                var c3 = 0usize
                while c3 < k {
                    var r3 = 0usize
                    while r3 < c3 {
                        if join[r3 * k + c3] == 1.0f64 { njp += 1usize }
                        r3 += 1usize
                    }
                    c3 += 1usize
                }
                // fpc tests the pairs one by one only when more than one has ratio 1
                c3 = 0usize
                while c3 < k && njp > 1usize {
                    var r3 = 0usize
                    while r3 < c3 {
                        if join[r3 * k + c3] == 1.0f64 {
                            let (v, ev) = dipm_pair(a, g, x, n, d, clu, r3, c3)
                            if ev != ok { ret (0usize, ev) }
                            if pi0 == k || v > jb {
                                jb = v
                                pi0 = r3
                                pj0 = c3
                            }
                        }
                        r3 += 1usize
                    }
                    c3 += 1usize
                }
                if njp > 1usize { dec[pi0 * k + pj0] = 1.0f64 + jb }
                var mx3 = dec[0usize]
                q2 = 1usize
                while q2 < k * k {
                    if dec[q2] > mx3 { mx3 = dec[q2] }
                    q2 += 1usize
                }
                if mx3 <= 1.0f64 {
                    var fi = k
                    var fj = k
                    c3 = 0usize
                    while c3 < k {
                        var r3 = 0usize
                        while r3 < k {
                            if fi == k && dec[r3 * k + c3] == mx3 {
                                fi = r3
                                fj = c3
                            }
                            r3 += 1usize
                        }
                        c3 += 1usize
                    }
                    let (v, ev) = dipm_pair(a, g, x, n, d, clu, fi, fj)
                    if ev != ok { ret (0usize, ev) }
                    jb = v
                }
                if jb < cutoff {
                    q2 = 0usize
                    while q2 < k * k {
                        join[q2] = 0.0f64
                        q2 += 1usize
                    }
                }
                vals[nv] = jb
                nv += 1usize
            }
        }
        all = false
        var anyj = false
        var best = 0.0f64
        var bi = k
        var bj = k
        var c = 0usize
        while c < k {
            var r = 0usize
            while r < c {
                if join[r * k + c] != 0.0f64 { anyj = true }
                if dec[r * k + c] > best {
                    best = dec[r * k + c]
                    bi = r
                    bj = c
                }
                r += 1usize
            }
            c += 1usize
        }
        if !anyj || nup == 0usize {
            if ratio && !dipm {
                vals[nv] = best
                nv += 1usize
            }
            break
        }
        if ratio {
            if !dipm {
                vals[nv] = best
                nv += 1usize
            }
        } else {
            // ridge.uni: among the connected pairs (column-major order) the one with the largest bhat, the first on ties
            bi = k
            bj = k
            var bv = -1.0e300f64
            c = 0usize
            while c < k {
                var r = 0usize
                while r < c {
                    if join[r * k + c] != 0.0f64 && (bi == k || dec[r * k + c] > bv) {
                        bv = dec[r * k + c]
                        bi = r
                        bj = c
                    }
                    r += 1usize
                }
                c += 1usize
            }
        }
        // merge component bj into bi
        dead[bj] = true
        i = 0usize
        while i < k {
            if map[i] == bj { map[i] = bi }
            i += 1usize
        }
        probs[bi] = probs[bi] + probs[bj]
        var tot = 0.0f64
        i = 0usize
        while i < n {
            z[i * k + bi] = z[i * k + bi] + z[i * k + bj]
            tot += z[i * k + bi]
            i += 1usize
        }
        var r2 = 0usize
        while r2 < d {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += z[i * k + bi] * x[i * d + r2]
                i += 1usize
            }
            mu[bi * d + r2] = s / tot
            r2 += 1usize
        }
        r2 = 0usize
        while r2 < d {
            var c2 = 0usize
            while c2 < d {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += z[i * k + bi] * (x[i * d + r2] - mu[bi * d + r2]) * (x[i * d + c2] - mu[bi * d + c2])
                    i += 1usize
                }
                sg[bi * d * d + r2 * d + c2] = s / tot
                c2 += 1usize
            }
            r2 += 1usize
        }
        upi = bi
        nup = 0usize
        i = 0usize
        while i < k {
            if !dead[i] && i != bi { nup += 1usize }
            i += 1usize
        }
    }
    var cln = 1usize
    var lab = 0usize
    while lab < k {
        var used = false
        i = 0usize
        while i < k {
            if map[i] == lab { used = true }
            i += 1usize
        }
        if used {
            i = 0usize
            while i < k {
                if map[i] == lab { map[i] = 1000usize + cln }
                i += 1usize
            }
            cln += 1usize
        }
        lab += 1usize
    }
    i = 0usize
    while i < k {
        map[i] = map[i] - 1000usize
        i += 1usize
    }
    if nv == k { nv -= 1usize }
    ret (nv, ok)
}
