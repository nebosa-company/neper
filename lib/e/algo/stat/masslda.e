// R MASS lda and qda (methods moment, mle, mve, t), their leave-one-out CV, and predict.lda / predict.qda (plug-in,
// predictive, debiased, looCV). Ports of lda.default, predict.lda, qda.default and predict.qda of MASS 7.3-65.
// Matrices are column-major; groups are 0-based codes held in f64; every group must be non-empty.

use e.algo.linalg.decomp as decomp
use e.algo.linalg.lapack_gesdd as gesdd
use e.algo.rand.r as rng
use e.algo.stat as sx
use e.algo.stat.masscov as mc
use e.math
use e.mem

error BadInput
error Rank

type Disc = struct {
    n: usize,
    p: usize,
    ng: usize,
    rank: usize,
    prior: []f64,
    counts: []f64,
    means: []f64,
    scaling: []f64,
    svd: []f64,
    ldet: []f64,
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// A (m by k) times B (k by n)
fn matmul(a: *mem.Arena, am: []const f64, m: usize, k: usize, bm: []const f64, n: usize) -> ([]f64, err) {
    let (c, e) = mem.alloc[f64](a, m * n + 1usize)
    if e != ok { ret (c, e) }
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < m {
            var s = 0.0f64
            var q = 0usize
            while q < k {
                s += am[i + m * q] * bm[q + k * j]
                q += 1usize
            }
            c[i + m * j] = s
            i += 1usize
        }
        j += 1usize
    }
    ret (c, ok)
}

fn group_means(x: []const f64, n: usize, p: usize, g: []const f64, ng: usize, counts: []f64, means: []f64) {
    var k = 0usize
    while k < ng {
        counts[k] = 0.0f64
        var j = 0usize
        while j < p {
            means[k + ng * j] = 0.0f64
            j += 1usize
        }
        k += 1usize
    }
    var i = 0usize
    while i < n {
        let gi = usize(g[i])
        counts[gi] += 1.0f64
        var j = 0usize
        while j < p {
            means[gi + ng * j] += x[i + n * j]
            j += 1usize
        }
        i += 1usize
    }
    k = 0usize
    while k < ng {
        var j = 0usize
        while j < p {
            means[k + ng * j] = means[k + ng * j] / counts[k]
            j += 1usize
        }
        k += 1usize
    }
}

// svd with nu = 0: d (k) and v (nc by k, column-major) of the nr by nc matrix
fn svd_dv(a: *mem.Arena, xm: []const f64, nr: usize, nc: usize, d: []f64, v: []f64) -> err {
    var k = nr
    if nc < nr { k = nc }
    let (u, e1) = mem.alloc[f64](a, nr * k)
    let (vt, e2) = mem.alloc[f64](a, k * nc)
    if e1 != ok || e2 != ok { ret mem.Full }
    let se = gesdd.svd_all(a, xm, nr, nc, d, u, vt)
    if se != ok { ret se }
    var j = 0usize
    while j < k {
        var i = 0usize
        while i < nc {
            v[i + nc * j] = vt[j + k * i]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// lda.default. g holds 0-based group codes; prior_in is read when use_prior; method 0 moment, 1 mle, 2 mve, 3 t
fn lda(a: *mem.Arena, r: *rng.Rng, x: []const f64, n: usize, p: usize, g: []const f64, ng: usize, prior_in: []const f64, use_prior: bool, tol: f64, method: usize, nu: f64) -> (Disc, err) {
    var out: Disc = zero
    let (counts, e1) = mem.alloc[f64](a, ng)
    let (gm, e2) = mem.alloc[f64](a, ng * p)
    let (prior, e3) = mem.alloc[f64](a, ng)
    let (res, e4) = mem.alloc[f64](a, n * p)
    let (scal, e5) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (out, mem.Full) }
    group_means(x, n, p, g, ng, counts, gm)
    var k = 0usize
    while k < ng {
        if counts[k] == 0.0f64 { ret (out, BadInput) }
        if use_prior { prior[k] = prior_in[k] } else { prior[k] = counts[k] / f64(n) }
        k += 1usize
    }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            res[i + n * j] = x[i + n * j] - gm[usize(g[i]) + ng * j]
            j += 1usize
        }
        i += 1usize
    }
    // f1 = sqrt(diag(var(res)))
    let (f1, e6) = mem.alloc[f64](a, p)
    if e6 != ok { ret (out, mem.Full) }
    var j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += res[i + n * j]
            i += 1usize
        }
        m /= f64(n)
        var v = 0.0f64
        i = 0usize
        while i < n {
            v += (res[i + n * j] - m) * (res[i + n * j] - m)
            i += 1usize
        }
        f1[j] = math.sqrt[f64](v / f64(n - 1usize))
        if f1[j] < tol { ret (out, Rank) }
        j += 1usize
    }
    i = 0usize
    while i < p * p {
        scal[i] = 0.0f64
        i += 1usize
    }
    j = 0usize
    while j < p {
        scal[j + p * j] = 1.0f64 / f1[j]
        j += 1usize
    }
    var sc = scal
    var rank = p
    let (xs, e7) = mem.alloc[f64](a, n * p)
    let (dd, e8) = mem.alloc[f64](a, p + n)
    let (vv, e9) = mem.alloc[f64](a, p * p + n)
    if e7 != ok || e8 != ok || e9 != ok { ret (out, mem.Full) }
    if method == 2usize {
        j = 0usize
        while j < p {
            i = 0usize
            while i < n {
                xs[i + n * j] = res[i + n * j] * scal[j + p * j]
                i += 1usize
            }
            j += 1usize
        }
        let (rb, re) = mc.cov_rob(a, r, xs, n, p, 0usize, -1.0f64, -1.0f64)
        if re != ok { ret (out, re) }
        let (cv, e10) = mem.alloc[f64](a, p * p)
        if e10 != ok { ret (out, mem.Full) }
        let fnn = f64(n) / f64(n - ng)
        i = 0usize
        while i < p * p {
            cv[i] = fnn * rb.cov[i]
            i += 1usize
        }
        let se = svd_dv(a, cv, p, p, dd, vv)
        if se != ok { ret (out, se) }
        rank = 0usize
        j = 0usize
        while j < p {
            if dd[j] > tol * tol { rank += 1usize }
            j += 1usize
        }
        if rank == 0usize { ret (out, Rank) }
        let (s2, e11) = mem.alloc[f64](a, p * rank)
        if e11 != ok { ret (out, mem.Full) }
        j = 0usize
        while j < rank {
            i = 0usize
            while i < p {
                s2[i + p * j] = (scal[i + p * i] * vv[i + p * j]) * math.sqrt[f64](1.0f64 / dd[j])
                i += 1usize
            }
            j += 1usize
        }
        sc = s2
    } else if method == 3usize {
        if nu <= 2.0f64 { ret (out, BadInput) }
        let (w, e10) = mem.alloc[f64](a, n)
        let (w0, e11) = mem.alloc[f64](a, n)
        let (xx, e12) = mem.alloc[f64](a, n * p)
        if e10 != ok || e11 != ok || e12 != ok { ret (out, mem.Full) }
        i = 0usize
        while i < n {
            w[i] = 1.0f64
            i += 1usize
        }
        var go = true
        while go {
            i = 0usize
            while i < n {
                w0[i] = w[i]
                i += 1usize
            }
            j = 0usize
            while j < p {
                i = 0usize
                while i < n {
                    let rv = x[i + n * j] - gm[usize(g[i]) + ng * j]
                    xs[i + n * j] = math.sqrt[f64]((1.0f64 + f64(p) / nu) * w[i] / f64(n)) * rv
                    xx[i + n * j] = rv
                    i += 1usize
                }
                j += 1usize
            }
            let se = svd_dv(a, xs, n, p, dd, vv)
            if se != ok { ret (out, se) }
            let (xt, me) = matmul(a, xx, n, p, vv, p)
            if me != ok { ret (out, me) }
            i = 0usize
            while i < n {
                var s2 = 0.0f64
                j = 0usize
                while j < p {
                    let t = xt[i + n * j] * (1.0f64 / dd[j])
                    s2 += t * t
                    j += 1usize
                }
                w[i] = 1.0f64 / (1.0f64 + s2 / nu)
                i += 1usize
            }
            // group.means <- tapply(w * x, ..., sum) / tapply(w, g, sum)
            var kk = 0usize
            while kk < ng {
                var sw = 0.0f64
                i = 0usize
                while i < n {
                    if usize(g[i]) == kk { sw += w[i] }
                    i += 1usize
                }
                j = 0usize
                while j < p {
                    var sv = 0.0f64
                    i = 0usize
                    while i < n {
                        if usize(g[i]) == kk { sv += w[i] * x[i + n * j] }
                        i += 1usize
                    }
                    gm[kk + ng * j] = sv / sw
                    j += 1usize
                }
                kk += 1usize
            }
            go = false
            i = 0usize
            while i < n {
                if !(math.abs[f64](w[i] - w0[i]) < 0.01f64) { go = true }
                i += 1usize
            }
        }
        j = 0usize
        while j < p {
            i = 0usize
            while i < n {
                xs[i + n * j] = math.sqrt[f64](nu / (nu - 2.0f64) * (1.0f64 + f64(p) / nu) / f64(n) * w[i]) * (x[i + n * j] - gm[usize(g[i]) + ng * j]) * scal[j + p * j]
                i += 1usize
            }
            j += 1usize
        }
        let se = svd_dv(a, xs, n, p, dd, vv)
        if se != ok { ret (out, se) }
        rank = 0usize
        j = 0usize
        while j < p {
            if dd[j] > tol { rank += 1usize }
            j += 1usize
        }
        if rank == 0usize { ret (out, Rank) }
        let (s2, e13) = mem.alloc[f64](a, p * rank)
        if e13 != ok { ret (out, mem.Full) }
        j = 0usize
        while j < rank {
            i = 0usize
            while i < p {
                s2[i + p * j] = (scal[i + p * i] * vv[i + p * j]) * (1.0f64 / dd[j])
                i += 1usize
            }
            j += 1usize
        }
        sc = s2
    } else {
        var fac = 1.0f64 / f64(n - ng)
        if method == 1usize { fac = 1.0f64 / f64(n) }
        j = 0usize
        while j < p {
            i = 0usize
            while i < n {
                xs[i + n * j] = math.sqrt[f64](fac) * (res[i + n * j] * scal[j + p * j])
                i += 1usize
            }
            j += 1usize
        }
        let se = svd_dv(a, xs, n, p, dd, vv)
        if se != ok { ret (out, se) }
        rank = 0usize
        j = 0usize
        while j < p {
            if dd[j] > tol { rank += 1usize }
            j += 1usize
        }
        if rank == 0usize { ret (out, Rank) }
        let (s2, e11) = mem.alloc[f64](a, p * rank)
        if e11 != ok { ret (out, mem.Full) }
        j = 0usize
        while j < rank {
            i = 0usize
            while i < p {
                s2[i + p * j] = (scal[i + p * i] * vv[i + p * j]) * (1.0f64 / dd[j])
                i += 1usize
            }
            j += 1usize
        }
        sc = s2
    }
    out = Disc { n: n, p: p, ng: ng, rank: rank, prior: prior, counts: counts, means: gm, scaling: sc, svd: dd, ldet: counts }
    ret (out, ok)
}

// the second stage of lda.default: the between-groups svd and the final scaling (needs the p by rank scaling of lda())
fn lda_final(a: *mem.Arena, d0: *const Disc, method: usize, tol: f64) -> (Disc, err) {
    var out = *d0
    let n = d0.n
    let p = d0.p
    let ng = d0.ng
    let rank = d0.rank
    let (xbar, e1) = mem.alloc[f64](a, p)
    let (cm, e2) = mem.alloc[f64](a, ng * p)
    if e1 != ok || e2 != ok { ret (out, mem.Full) }
    var j = 0usize
    var k = 0usize
    while j < p {
        var s = 0.0f64
        k = 0usize
        while k < ng {
            s += d0.prior[k] * d0.means[k + ng * j]
            k += 1usize
        }
        xbar[j] = s
        k = 0usize
        while k < ng {
            cm[k + ng * j] = d0.means[k + ng * j] - s
            k += 1usize
        }
        j += 1usize
    }
    let (xm, me) = matmul(a, cm, ng, p, d0.scaling, rank)
    if me != ok { ret (out, me) }
    var fac = 1.0f64 / f64(ng - 1usize)
    if method == 1usize { fac = 1.0f64 / f64(ng) }
    k = 0usize
    while k < ng {
        let f = math.sqrt[f64]((f64(n) * d0.prior[k]) * fac)
        j = 0usize
        while j < rank {
            xm[k + ng * j] = f * xm[k + ng * j]
            j += 1usize
        }
        k += 1usize
    }
    var kk = ng
    if rank < ng { kk = rank }
    let (dd, e3) = mem.alloc[f64](a, kk)
    let (vv, e4) = mem.alloc[f64](a, rank * kk)
    if e3 != ok || e4 != ok { ret (out, mem.Full) }
    let se = svd_dv(a, xm, ng, rank, dd, vv)
    if se != ok { ret (out, se) }
    var r2 = 0usize
    j = 0usize
    while j < kk {
        if dd[j] > tol * dd[0usize] { r2 += 1usize }
        j += 1usize
    }
    if r2 == 0usize { ret (out, Rank) }
    let (fs, e5) = matmul(a, d0.scaling, p, rank, vv[0usize..rank * r2], r2)
    if e5 != ok { ret (out, e5) }
    out.scaling = fs
    out.svd = dd[0usize..r2]
    out.rank = r2
    ret (out, ok)
}

// predict.lda: method 0 plug-in, 1 predictive, 2 debiased. post (m * ng) and ld (m * dimen) are filled; cls gets 0-based classes.
fn lda_predict(a: *mem.Arena, d: *const Disc, xn: []const f64, m: usize, prior: []const f64, dimen_in: usize, method: usize, cls: []f64, post: []f64, ld: []f64) -> err {
    let p = d.p
    let ng = d.ng
    let nn = f64(d.n)
    let (means, e1) = mem.alloc[f64](a, p)
    let (xc, e2) = mem.alloc[f64](a, m * p)
    let (dc, e3) = mem.alloc[f64](a, ng * p)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var k = 0usize
        while k < ng {
            s += prior[k] * d.means[k + ng * j]
            k += 1usize
        }
        means[j] = s
        var i = 0usize
        while i < m {
            xc[i + m * j] = xn[i + m * j] - s
            i += 1usize
        }
        k = 0usize
        while k < ng {
            dc[k + ng * j] = d.means[k + ng * j] - s
            k += 1usize
        }
        j += 1usize
    }
    let (x, me) = matmul(a, xc, m, p, d.scaling, d.rank)
    if me != ok { ret me }
    let (dm, me2) = matmul(a, dc, ng, p, d.scaling, d.rank)
    if me2 != ok { ret me2 }
    var dimen = d.rank
    if dimen_in < dimen { dimen = dimen_in }
    let (dist, e4) = mem.alloc[f64](a, m * ng)
    if e4 != ok { ret mem.Full }
    let ngf = f64(ng)
    var i = 0usize
    while i < m {
        var k = 0usize
        while k < ng {
            var dd = 0.0f64
            if method == 1usize {
                let nk = d.counts[k]
                var s2 = 0.0f64
                j = 0usize
                while j < d.rank {
                    let dv = x[i + m * j] * math.sqrt[f64](nn / (nn - ngf)) - dm[k + ng * j]
                    s2 += dv * dv
                    j += 1usize
                }
                let dv1 = 1.0f64 + s2 * nk / (nn * (nk + 1.0f64))
                dd = prior[k] * math.pow[f64](nk / (nk + 1.0f64), f64(p) / 2.0f64) * math.pow[f64](dv1, 0.0f64 - (nn - ngf + 1.0f64) / 2.0f64)
            } else {
                var s2 = 0.0f64
                var cr = 0.0f64
                j = 0usize
                while j < dimen {
                    s2 += dm[k + ng * j] * dm[k + ng * j]
                    cr += x[i + m * j] * dm[k + ng * j]
                    j += 1usize
                }
                if method == 0usize {
                    dd = (0.5f64 * s2 - math.log[f64](prior[k])) - cr
                } else {
                    dd = 0.5f64 * s2 - cr
                    dd = (nn - ngf - f64(dimen) - 1.0f64) / (nn - ngf) * dd - (math.log[f64](prior[k]) - f64(dimen) / d.counts[k])
                }
            }
            dist[i + m * k] = dd
            k += 1usize
        }
        if method != 1usize {
            var mn = dist[i]
            k = 1usize
            while k < ng {
                if dist[i + m * k] < mn { mn = dist[i + m * k] }
                k += 1usize
            }
            k = 0usize
            while k < ng {
                dist[i + m * k] = math.exp[f64](0.0f64 - (dist[i + m * k] - mn))
                k += 1usize
            }
        }
        var tot = 0.0f64
        k = 0usize
        while k < ng {
            tot += dist[i + m * k]
            k += 1usize
        }
        var best = 0usize
        k = 0usize
        while k < ng {
            post[i + m * k] = dist[i + m * k] / tot
            if post[i + m * k] > post[i + m * best] { best = k }
            k += 1usize
        }
        cls[i] = f64(best)
        i += 1usize
    }
    j = 0usize
    while j < dimen {
        i = 0usize
        while i < m {
            ld[i + m * j] = x[i + m * j]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// lda(CV = TRUE) for the moment and mle methods: leave-one-out classes and posteriors
fn lda_cv(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: []const f64, d: *const Disc, method: usize, cls: []f64, post: []f64) -> err {
    let ng = d.ng
    let rank = d.rank
    let (xs, me) = matmul(a, x, n, p, d.scaling, rank)
    if me != ok { ret me }
    let (dm, me2) = matmul(a, d.means, ng, p, d.scaling, rank)
    if me2 != ok { ret me2 }
    var kc = 0.0f64
    if method == 0usize { kc = f64(ng) }
    let (dist2, e1) = mem.alloc[f64](a, n * ng)
    let (dist, e2) = mem.alloc[f64](a, n * ng)
    if e1 != ok || e2 != ok { ret mem.Full }
    var k = 0usize
    while k < ng {
        var i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j < rank {
                let dv = xs[i + n * j] - dm[k + ng * j]
                s += dv * dv
                j += 1usize
            }
            dist2[i + n * k] = s
            i += 1usize
        }
        k += 1usize
    }
    let nf = f64(n)
    k = 0usize
    while k < ng {
        var i = 0usize
        while i < n {
            let gi = usize(g[i])
            let nc = d.counts[gi]
            let cc = nc / ((nc - 1.0f64) * (nf - kc))
            var tmp = 0.0f64
            var j = 0usize
            while j < rank {
                let dv = xs[i + n * j] - dm[k + ng * j]
                let dv2 = xs[i + n * j] - dm[gi + ng * j]
                tmp += dv * dv2
                j += 1usize
            }
            dist[i + n * k] = (nf - 1.0f64 - kc) / (nf - kc) * (dist2[i + n * k] + cc * tmp * tmp / (1.0f64 - cc * dist2[i + n * gi]))
            i += 1usize
        }
        k += 1usize
    }
    var i = 0usize
    while i < n {
        let gi = usize(g[i])
        let nc = d.counts[gi]
        let cc = nc / ((nc - 1.0f64) * (nf - kc))
        dist[i + n * gi] = dist2[i + n * gi] * (nf - 1.0f64 - kc) / (nf - kc) * (nc / (nc - 1.0f64)) * (nc / (nc - 1.0f64)) / (1.0f64 - cc * dist2[i + n * gi])
        i += 1usize
    }
    var mn = 1.0e300f64
    i = 0usize
    while i < n {
        k = 0usize
        while k < ng {
            dist[i + n * k] = 0.5f64 * dist[i + n * k] - math.log[f64](d.prior[k])
            if dist[i + n * k] < mn { mn = dist[i + n * k] }
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var tot = 0.0f64
        k = 0usize
        while k < ng {
            dist[i + n * k] = math.exp[f64](0.0f64 - (dist[i + n * k] - mn))
            tot += dist[i + n * k]
            k += 1usize
        }
        var best = 0usize
        k = 0usize
        while k < ng {
            post[i + n * k] = dist[i + n * k] / tot
            if post[i + n * k] > post[i + n * best] { best = k }
            k += 1usize
        }
        cls[i] = f64(best)
        i += 1usize
    }
    ret ok
}

// ---- qda ----

// scaling (p * p * ng, group i at offset i * p * p) and ldet are filled
fn qda(a: *mem.Arena, r: *rng.Rng, x: []const f64, n: usize, p: usize, g: []const f64, ng: usize, prior_in: []const f64, use_prior: bool, method: usize, nu: f64) -> (Disc, err) {
    var out: Disc = zero
    let (counts, e1) = mem.alloc[f64](a, ng)
    let (gm, e2) = mem.alloc[f64](a, ng * p)
    let (prior, e3) = mem.alloc[f64](a, ng)
    let (scaling, e4) = mem.alloc[f64](a, p * p * ng)
    let (ldet, e5) = mem.alloc[f64](a, ng)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (out, mem.Full) }
    group_means(x, n, p, g, ng, counts, gm)
    var k = 0usize
    while k < ng {
        if counts[k] < f64(p + 1usize) { ret (out, BadInput) }
        if use_prior { prior[k] = prior_in[k] } else { prior[k] = counts[k] / f64(n) }
        k += 1usize
    }
    k = 0usize
    while k < ng {
        let m = usize(counts[k])
        let (xg, e6) = mem.alloc[f64](a, m * p)
        let (xc, e7) = mem.alloc[f64](a, m * p)
        if e6 != ok || e7 != ok { ret (out, mem.Full) }
        var row = 0usize
        var i = 0usize
        while i < n {
            if usize(g[i]) == k {
                var j = 0usize
                while j < p {
                    xg[row + m * j] = x[i + n * j]
                    j += 1usize
                }
                row += 1usize
            }
            i += 1usize
        }
        let base = k * p * p
        if method == 2usize {
            let (rb, re) = mc.cov_rob(a, r, xg, m, p, 0usize, -1.0f64, -1.0f64)
            if re != ok { ret (out, re) }
            let (dd, e8) = mem.alloc[f64](a, p)
            let (vv, e9) = mem.alloc[f64](a, p * p)
            if e8 != ok || e9 != ok { ret (out, mem.Full) }
            var j = 0usize
            while j < p {
                gm[k + ng * j] = rb.center[j]
                j += 1usize
            }
            let se = svd_dv(a, rb.cov, p, p, dd, vv)
            if se != ok { ret (out, se) }
            var ld = 0.0f64
            j = 0usize
            while j < p {
                i = 0usize
                while i < p {
                    scaling[base + i + p * j] = vv[i + p * j] * math.sqrt[f64](1.0f64 / dd[j])
                    i += 1usize
                }
                ld += math.log[f64](dd[j])
                j += 1usize
            }
            ldet[k] = ld
        } else {
            var nk = counts[k]
            if method == 0usize { nk = counts[k] - 1.0f64 }
            var j = 0usize
            if method == 3usize {
                if nu <= 2.0f64 { ret (out, BadInput) }
                let (w, e8) = mem.alloc[f64](a, m)
                let (w0, e9) = mem.alloc[f64](a, m)
                let (xs, e10) = mem.alloc[f64](a, m * p)
                let (dd, e11) = mem.alloc[f64](a, p)
                let (vv, e12) = mem.alloc[f64](a, p * p)
                if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (out, mem.Full) }
                i = 0usize
                while i < m {
                    w[i] = 1.0f64
                    i += 1usize
                }
                var go = true
                while go {
                    i = 0usize
                    while i < m {
                        w0[i] = w[i]
                        i += 1usize
                    }
                    j = 0usize
                    while j < p {
                        i = 0usize
                        while i < m {
                            xc[i + m * j] = xg[i + m * j] - gm[k + ng * j]
                            xs[i + m * j] = math.sqrt[f64]((1.0f64 + f64(p) / nu) * w[i] / f64(m)) * xc[i + m * j]
                            i += 1usize
                        }
                        j += 1usize
                    }
                    let se = svd_dv(a, xs, m, p, dd, vv)
                    if se != ok { ret (out, se) }
                    let (wt, me) = matmul(a, xc, m, p, vv, p)
                    if me != ok { ret (out, me) }
                    i = 0usize
                    while i < m {
                        var s2 = 0.0f64
                        j = 0usize
                        while j < p {
                            let t = wt[i + m * j] * (1.0f64 / dd[j])
                            s2 += t * t
                            j += 1usize
                        }
                        w[i] = 1.0f64 / (1.0f64 + s2 / nu)
                        i += 1usize
                    }
                    var sw = 0.0f64
                    i = 0usize
                    while i < m {
                        sw += w[i]
                        i += 1usize
                    }
                    j = 0usize
                    while j < p {
                        var sv = 0.0f64
                        i = 0usize
                        while i < m {
                            sv += w[i] * xg[i + m * j]
                            i += 1usize
                        }
                        gm[k + ng * j] = sv / sw
                        j += 1usize
                    }
                    go = false
                    i = 0usize
                    while i < m {
                        if !(math.abs[f64](w[i] - w0[i]) < 0.01f64) { go = true }
                        i += 1usize
                    }
                }
                j = 0usize
                while j < p {
                    i = 0usize
                    while i < m {
                        xc[i + m * j] = math.sqrt[f64](w[i]) * (xg[i + m * j] - gm[k + ng * j])
                        i += 1usize
                    }
                    j += 1usize
                }
                nk = f64(m)
            } else {
                j = 0usize
                while j < p {
                    i = 0usize
                    while i < m {
                        xc[i + m * j] = (xg[i + m * j] - gm[k + ng * j]) / math.sqrt[f64](nk)
                        i += 1usize
                    }
                    j += 1usize
                }
            }
            let (qf, qe) = decomp.qr(a, xc, m, p, 1.0e-7f64)
            if qe != ok { ret (out, qe) }
            if qf.rank < p { ret (out, Rank) }
            var sc = 1.0f64
            if method == 3usize { sc = math.sqrt[f64]((1.0f64 + f64(p) / nu) / f64(m)) }
            // scaling = backsolve(R, I), R the upper triangle of qr * sc; ldet = 2 sum log|diag R|
            var col = 0usize
            while col < p {
                var rr = p
                while rr > 0usize {
                    rr -= 1usize
                    var s = 0.0f64
                    if rr == col { s = 1.0f64 }
                    var cc = rr + 1usize
                    while cc < p {
                        s -= (qf.qr[rr + m * cc] * sc) * scaling[base + cc + p * col]
                        cc += 1usize
                    }
                    scaling[base + rr + p * col] = s / (qf.qr[rr + m * rr] * sc)
                }
                col += 1usize
            }
            var ld = 0.0f64
            j = 0usize
            while j < p {
                ld += math.log[f64](math.abs[f64](qf.qr[j + m * j] * sc))
                j += 1usize
            }
            ldet[k] = 2.0f64 * ld
        }
        k += 1usize
    }
    out = Disc { n: n, p: p, ng: ng, rank: p, prior: prior, counts: counts, means: gm, scaling: scaling, svd: ldet, ldet: ldet }
    ret (out, ok)
}

fn qda_dev2(d: *const Disc, x: []const f64, m: usize, i: usize, k: usize) -> f64 {
    let p = d.p
    var s = 0.0f64
    var j = 0usize
    while j < p {
        var t = 0.0f64
        var q = 0usize
        while q < p {
            t += (x[i + m * q] - d.means[k + d.ng * q]) * d.scaling[k * p * p + q + p * j]
            q += 1usize
        }
        s += t * t
        j += 1usize
    }
    ret s
}

// predict.qda / qda(CV = TRUE): method 0 plug-in, 1 predictive, 2 debiased, 3 looCV (needs g, the 0-based groups of x and mle for NG)
fn qda_predict(a: *mem.Arena, d: *const Disc, x: []const f64, m: usize, prior: []const f64, method: usize, g: []const f64, mle: bool, cls: []f64, post: []f64) -> err {
    let ng = d.ng
    let p = d.p
    let pf = f64(p)
    let (dist, e1) = mem.alloc[f64](a, m * ng)
    let (ldet, e2) = mem.alloc[f64](a, m * ng)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    var k = 0usize
    while k < ng {
        i = 0usize
        while i < m {
            let s2 = qda_dev2(d, x, m, i, k)
            let nk = d.counts[k]
            if method == 0usize {
                dist[i + m * k] = 0.5f64 * s2 + 0.5f64 * d.ldet[k] - math.log[f64](prior[k])
            } else if method == 3usize {
                dist[i + m * k] = s2
                ldet[i + m * k] = d.ldet[k]
            } else if method == 2usize {
                var dg = 0.0f64
                var q = 1usize
                while q <= ng {
                    dg += sx.digamma(0.5f64 * (nk - f64(q)))
                    q += 1usize
                }
                let bm = pf * math.log[f64]((nk - 1.0f64) / 2.0f64) - dg
                dist[i + m * k] = 0.5f64 * (1.0f64 - (pf - 1.0f64) / (nk - 1.0f64)) * s2 + 0.5f64 * d.ldet[k] - math.log[f64](prior[k]) + 0.5f64 * bm - pf / (2.0f64 * nk)
            } else {
                let dv = 1.0f64 + s2 / (nk + 1.0f64)
                dist[i + m * k] = prior[k] * math.exp[f64](0.0f64 - d.ldet[k] / 2.0f64) * math.pow[f64](dv, 0.0f64 - nk / 2.0f64) * math.pow[f64](1.0f64 + nk, 0.0f64 - pf / 2.0f64)
            }
            i += 1usize
        }
        k += 1usize
    }
    if method == 3usize {
        var ng0 = 1.0f64
        if mle { ng0 = 0.0f64 }
        i = 0usize
        while i < m {
            let gi = usize(g[i])
            let nc = d.counts[gi]
            var fac = 1.0f64 - nc / (nc - 1.0f64) / (nc - ng0) * dist[i + m * gi]
            if fac < 1.0e-10f64 { fac = 1.0e-10f64 }
            ldet[i + m * gi] = math.log[f64](fac) + pf * math.log[f64]((nc - ng0) / (nc - 1.0f64 - ng0)) + ldet[i + m * gi]
            dist[i + m * gi] = dist[i + m * gi] * (nc * nc / ((nc - 1.0f64) * (nc - 1.0f64))) * (nc - 1.0f64 - ng0) / (nc - ng0) / fac
            i += 1usize
        }
        k = 0usize
        while k < ng {
            i = 0usize
            while i < m {
                dist[i + m * k] = 0.5f64 * dist[i + m * k] + 0.5f64 * ldet[i + m * k] - math.log[f64](prior[k])
                i += 1usize
            }
            k += 1usize
        }
    }
    i = 0usize
    while i < m {
        if method == 0usize || method == 2usize || method == 3usize {
            var mn = dist[i]
            k = 1usize
            while k < ng {
                if dist[i + m * k] < mn { mn = dist[i + m * k] }
                k += 1usize
            }
            k = 0usize
            while k < ng {
                dist[i + m * k] = math.exp[f64](0.0f64 - (dist[i + m * k] - mn))
                k += 1usize
            }
        }
        var tot = 0.0f64
        k = 0usize
        while k < ng {
            tot += dist[i + m * k]
            k += 1usize
        }
        var best = 0usize
        k = 0usize
        while k < ng {
            post[i + m * k] = dist[i + m * k] / tot
            if post[i + m * k] > post[i + m * best] { best = k }
            k += 1usize
        }
        cls[i] = f64(best)
        i += 1usize
    }
    ret ok
}
