// R ggm, the numerical part: `pcor`, `parcor` and `pcor_test` (partial correlations), `fitdag` (the maximum-likelihood
// fit of a Gaussian DAG by regressions on the parents), `fitcongraph` (the iterative fit of a concentration graph,
// the package's third algorithm) and `fitcovgraph` (a covariance graph by the iterative conditional fitting of
// Chaudhuri, Drton and Richardson). Matrices are row-major p by p; graphs are 0/1 adjacency matrices where, for a
// DAG, amat[j, i] = 1 is an arrow from j to i.
//
// Not here: the graph algorithms (d-separation, ancestral graphs, MAGs), the clique algorithms of `fitConGraph`,
// the dual algorithm of `fitCovGraph` and `fitAncestralGraph`.

use e.algo.stat.psych as ps
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

error Singular

// out (r by c) = x (r by k) times y (k by c)
fn gg_mul(x: []const f64, y: []const f64, r: usize, k: usize, c: usize, out: []f64) {
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            var s = 0.0f64
            var q = 0usize
            while q < k {
                s += x[i * k + q] * y[q * c + j]
                q += 1usize
            }
            out[i * c + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// the rows ri and columns ci of the p-column matrix m, as a new |ri| by |ci| matrix
fn gg_sub(a: *mem.Arena, m: []const f64, p: usize, ri: []const usize, ci: []const usize) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, ri.len * ci.len + 1usize)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < ri.len {
        var j = 0usize
        while j < ci.len {
            out[i * ci.len + j] = m[ri[i] * p + ci[j]]
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

fn gg_inv(a: *mem.Arena, m: []const f64, p: usize) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, p * p + 1usize)
    if e != ok { ret (out, e) }
    if p == 0usize { ret (out, ok) }
    if !ps.invert(a, m[0usize..p * p], p, out) { ret (out, Singular) }
    ret (out, ok)
}

// pcor(u, S): the partial correlation of the first two variables of u given the others of u (u 0-based)
fn pcor(a: *mem.Arena, u: []const usize, s: []const f64, p: usize) -> (f64, err) {
    let (sub, e1) = gg_sub(a, s, p, u, u)
    if e1 != ok { ret (0.0f64, e1) }
    let (k, e2) = gg_inv(a, sub, u.len)
    if e2 != ok { ret (0.0f64, e2) }
    let m = u.len
    ret (0.0f64 - k[1usize] / math.sqrt[f64](k[0usize] * k[m + 1usize]), ok)
}

// parcor(S): the matrix of partial correlations of each pair given all the others (2 I - the scaled inverse)
fn parcor(a: *mem.Arena, s: []const f64, p: usize, out: []f64) -> err {
    let (k, e) = gg_inv(a, s, p)
    if e != ok { ret e }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var v = k[i * p + j] / math.sqrt[f64](k[i * p + i] * k[j * p + j])
            if i == j { v = 2.0f64 - v } else { v = 0.0f64 - v }
            out[i * p + j] = v
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// pcor.test(r, q, n): the t statistic, its degrees of freedom and the two-sided p-value for a partial correlation r given q variables from n observations
fn pcor_test(r: f64, q: f64, n: f64) -> (f64, f64, f64) {
    let df = n - 2.0f64 - q
    let tval = r * math.sqrt[f64](df) / math.sqrt[f64](1.0f64 - r * r)
    let pv = 2.0f64 * nb.pt(0.0f64 - math.abs[f64](tval), df, true, false)
    ret (tval, df, pv)
}

// the Gaussian deviance n (tr(S K) - log det(S K) - k)
fn likgau(a: *mem.Arena, kmat: []const f64, s: []const f64, n: f64, k: usize) -> (f64, err) {
    let (sk, e) = mem.alloc[f64](a, k * k)
    if e != ok { ret (0.0f64, e) }
    gg_mul(s, kmat, k, k, k, sk)
    var tr = 0.0f64
    var i = 0usize
    while i < k {
        tr += sk[i * k + i]
        i += 1usize
    }
    ret ((tr - ps.logdet(a, sk, k) - f64(k)) * n, ok)
}

type DagFit = struct { dev: f64, df: f64 }

// fitDag(amat, S, n): shat (p by p), ahat (p by p, I minus the path coefficients) and dhat (the p residual variances) out; the deviance and degrees of freedom answered
fn fitdag(a: *mem.Arena, amat: []const f64, s: []const f64, p: usize, n: f64, shat: []f64, ahat: []f64, dhat: []f64) -> (DagFit, err) {
    var res: DagFit = zero
    let (v, e0) = mem.alloc[usize](a, p)
    let (one, e1) = mem.alloc[usize](a, 1usize)
    if e0 != ok || e1 != ok { ret (res, e0) }
    var i = 0usize
    while i < p * p {
        ahat[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        var nv = 0usize
        var j = 0usize
        while j < p {
            if j != i && amat[j * p + i] == 1.0f64 {
                v[nv] = j
                nv += 1usize
            }
            j += 1usize
        }
        one[0usize] = i
        ahat[i * p + i] = 1.0f64
        if nv == 0usize {
            dhat[i] = s[i * p + i]
        } else {
            let (svv, e2) = gg_sub(a, s, p, v[0usize..nv], v[0usize..nv])
            let (svi, e3) = gg_sub(a, s, p, v[0usize..nv], one)
            if e2 != ok || e3 != ok { ret (res, e2) }
            let (iv, e4) = gg_inv(a, svv, nv)
            if e4 != ok { ret (res, e4) }
            let (beta, e5) = mem.alloc[f64](a, nv)
            if e5 != ok { ret (res, e5) }
            gg_mul(iv, svi, nv, nv, 1usize, beta)
            var dv = s[i * p + i]
            j = 0usize
            while j < nv {
                ahat[i * p + v[j]] = 0.0f64 - beta[j]
                dv -= svi[j] * beta[j]
                j += 1usize
            }
            dhat[i] = dv
        }
        i += 1usize
    }
    let (b, e6) = gg_inv(a, ahat, p)
    if e6 != ok { ret (res, e6) }
    let (bd, e7) = mem.alloc[f64](a, p * p)
    let (bt, e8) = mem.alloc[f64](a, p * p)
    if e7 != ok || e8 != ok { ret (res, e7) }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            bd[i * p + j] = b[i * p + j] * dhat[j]
            bt[i * p + j] = b[j * p + i]
            j += 1usize
        }
        i += 1usize
    }
    gg_mul(bd, bt, p, p, p, shat)
    let (kh, e9) = gg_inv(a, shat, p)
    if e9 != ok { ret (res, e9) }
    let (hm, e10) = mem.alloc[f64](a, p * p)
    if e10 != ok { ret (res, e10) }
    gg_mul(s, kh, p, p, p, hm)
    var tr = 0.0f64
    i = 0usize
    while i < p {
        tr += hm[i * p + i]
        i += 1usize
    }
    res.dev = (tr - ps.logdet(a, hm, p) - f64(p)) * n
    var ne = 0.0f64
    i = 0usize
    while i < p * p {
        if amat[i] == 1.0f64 { ne += 1.0f64 }
        i += 1usize
    }
    res.df = f64(p) * (f64(p) + 1.0f64) / 2.0f64 - ne - f64(p)
    ret (res, ok)
}

type ConFit = struct { dev: f64, df: f64, it: i64 }

// fitConGraph(amat, S, n) with no cliques (the package's algorithm 3): the maximum-likelihood covariance of the concentration graph (a symmetric 0/1 matrix with at least one edge) in `w`
fn fitcongraph(a: *mem.Arena, amat: []const f64, s: []const f64, p: usize, n: f64, tol: f64, w: []f64) -> (ConFit, err) {
    var res: ConFit = zero
    let k = p
    let (w0, e0) = mem.alloc[f64](a, k * k)
    let (w11, e1) = mem.alloc[f64](a, k * k)
    let (idx, e2) = mem.alloc[usize](a, k)
    let (par, e3) = mem.alloc[usize](a, k)
    let (rest, e4) = mem.alloc[usize](a, k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (res, e0) }
    var i = 0usize
    while i < k * k {
        w0[i] = s[i]
        w[i] = s[i]
        i += 1usize
    }
    var it = 0i64
    var converge = false
    while !converge {
        it += 1i64
        var j = 0usize
        while j < k {
            var nr = 0usize
            var q = 0usize
            while q < k {
                if q != j {
                    rest[nr] = q
                    nr += 1usize
                }
                q += 1usize
            }
            var np = 0usize
            q = 0usize
            while q < nr {
                if amat[j * k + rest[q]] == 1.0f64 {
                    par[np] = q
                    np += 1usize
                }
                q += 1usize
            }
            // w[-j, j] = W11 beta with beta nonzero on the neighbours of j
            let (wsub, es) = gg_sub(a, w, k, rest[0usize..nr], rest[0usize..nr])
            if es != ok { ret (res, es) }
            let (wv, ev) = mem.alloc[f64](a, nr)
            if ev != ok { ret (res, ev) }
            if np == 0usize {
                q = 0usize
                while q < nr {
                    wv[q] = 0.0f64
                    q += 1usize
                }
            } else {
                // beta[par] = solve(W11[par, par], s12[par])
                let (wpp, e5) = gg_sub(a, wsub, nr, par[0usize..np], par[0usize..np])
                let (s12, e6) = mem.alloc[f64](a, np)
                if e5 != ok || e6 != ok { ret (res, e5) }
                q = 0usize
                while q < np {
                    s12[q] = s[rest[par[q]] * k + j]
                    q += 1usize
                }
                let (ipp, e7) = gg_inv(a, wpp, np)
                if e7 != ok { ret (res, e7) }
                let (bpar, e8) = mem.alloc[f64](a, np)
                if e8 != ok { ret (res, e8) }
                gg_mul(ipp, s12, np, np, 1usize, bpar)
                q = 0usize
                while q < nr {
                    var sum = 0.0f64
                    var r = 0usize
                    while r < np {
                        sum += wsub[q * nr + par[r]] * bpar[r]
                        r += 1usize
                    }
                    wv[q] = sum
                    q += 1usize
                }
            }
            q = 0usize
            while q < nr {
                w[rest[q] * k + j] = wv[q]
                w[j * k + rest[q]] = wv[q]
                q += 1usize
            }
            j += 1usize
        }
        // the one norm of W0 - W: the largest column sum of absolute values
        var di = 0.0f64
        var c = 0usize
        while c < k {
            var cs = 0.0f64
            var r = 0usize
            while r < k {
                cs += math.abs[f64](w0[r * k + c] - w[r * k + c])
                r += 1usize
            }
            if cs > di { di = cs }
            c += 1usize
        }
        if di < tol {
            converge = true
        } else {
            i = 0usize
            while i < k * k {
                w0[i] = w[i]
                i += 1usize
            }
        }
    }
    var zeros = 0.0f64
    i = 0usize
    while i < k * k {
        zeros += 1.0f64 - amat[i]
        i += 1usize
    }
    res.df = (zeros - f64(k)) / 2.0f64
    let (kh, e9) = gg_inv(a, w, k)
    if e9 != ok { ret (res, e9) }
    let (dv, e10) = likgau(a, kh, s, n, k)
    if e10 != ok { ret (res, e10) }
    res.dev = dv
    res.it = it
    ret (res, ok)
}

type CovFit = struct { dev: f64, df: f64, it: i64 }

// fitCovGraph(amat, S, n) by iterative conditional fitting (alg = "icf", from the diagonal start): the bi-directed graph is a symmetric 0/1 matrix; the fitted covariance goes to `sigma`
fn fitcovgraph(a: *mem.Arena, amat: []const f64, s: []const f64, p: usize, n: f64, tol: f64, sigma: []f64) -> (CovFit, err) {
    var res: CovFit = zero
    let (spo, e0) = mem.alloc[usize](a, p)
    let (nsp, e1) = mem.alloc[usize](a, p)
    let (oth, e2) = mem.alloc[usize](a, p)
    let (old, e3) = mem.alloc[f64](a, p * p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret (res, e0) }
    var i = 0usize
    while i < p * p {
        sigma[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        sigma[i * p + i] = s[i * p + i]
        i += 1usize
    }
    // vertices with at least one spouse
    var any = false
    i = 0usize
    while i < p * p {
        if i / p != i % p && amat[i] != 0.0f64 { any = true }
        i += 1usize
    }
    var iters = 0i64
    if !any {
        res.it = 1i64
    } else {
        var going = true
        while going {
            iters += 1i64
            i = 0usize
            while i < p * p {
                old[i] = sigma[i]
                i += 1usize
            }
            var v = 0usize
            while v < p {
                var nspo = 0usize
                var nn = 0usize
                var no = 0usize
                var q = 0usize
                while q < p {
                    if q != v {
                        oth[no] = q
                        no += 1usize
                        if amat[q * p + v] != 0.0f64 {
                            spo[nspo] = q
                            nspo += 1usize
                        } else {
                            nsp[nn] = q
                            nn += 1usize
                        }
                    }
                    q += 1usize
                }
                if nspo > 0usize {
                    var vone: [1]usize = zero
                    vone[0usize] = v
                    let vs = vone[0usize..1usize]
                    let (b, eb) = mem.alloc[f64](a, no)
                    if eb != ok { ret (res, eb) }
                    var lambda = 0.0f64
                    if nn == 0usize {
                        // B = S[v, -v] S[-v, -v]^-1, lambda = S[v, v] - B S[-v, v]
                        let (sov, e4) = gg_sub(a, s, p, oth[0usize..no], oth[0usize..no])
                        let (svo, e5) = gg_sub(a, s, p, vs, oth[0usize..no])
                        if e4 != ok || e5 != ok { ret (res, e4) }
                        let (iso, e6) = gg_inv(a, sov, no)
                        if e6 != ok { ret (res, e6) }
                        gg_mul(svo, iso, 1usize, no, no, b)
                        var bs = 0.0f64
                        q = 0usize
                        while q < no {
                            bs += b[q] * svo[q]
                            q += 1usize
                        }
                        lambda = s[v * p + v] - bs
                    } else {
                        let sp = spo[0usize..nspo]
                        let ns = nsp[0usize..nn]
                        let (sig_sn, e4) = gg_sub(a, sigma, p, sp, ns)
                        let (sig_nn, e5) = gg_sub(a, sigma, p, ns, ns)
                        if e4 != ok || e5 != ok { ret (res, e4) }
                        let (inn, e6) = gg_inv(a, sig_nn, nn)
                        if e6 != ok { ret (res, e6) }
                        let (bsn, e7) = mem.alloc[f64](a, nspo * nn)
                        if e7 != ok { ret (res, e7) }
                        gg_mul(sig_sn, inn, nspo, nn, nn, bsn)
                        // YZ = S[v, spo] - S[v, nsp] Bsn'
                        let (s_vs, e8) = gg_sub(a, s, p, vs, sp)
                        let (s_vn, e9) = gg_sub(a, s, p, vs, ns)
                        let (yz, e10) = mem.alloc[f64](a, nspo)
                        if e8 != ok || e9 != ok || e10 != ok { ret (res, e8) }
                        q = 0usize
                        while q < nspo {
                            var t = s_vs[q]
                            var r = 0usize
                            while r < nn {
                                t -= s_vn[r] * bsn[q * nn + r]
                                r += 1usize
                            }
                            yz[q] = t
                            q += 1usize
                        }
                        // M1 = S[sp,sp] - S[sp,ns] Bsn' - Bsn S[ns,sp] + Bsn S[ns,ns] Bsn'
                        let (s_ss, e11) = gg_sub(a, s, p, sp, sp)
                        let (s_sn, e12) = gg_sub(a, s, p, sp, ns)
                        let (s_nn, e13) = gg_sub(a, s, p, ns, ns)
                        if e11 != ok || e12 != ok || e13 != ok { ret (res, e11) }
                        let (m1, e14) = mem.alloc[f64](a, nspo * nspo)
                        let (t1, e15) = mem.alloc[f64](a, nspo * nn)
                        if e14 != ok || e15 != ok { ret (res, e14) }
                        // t1 = Bsn S[ns, ns]
                        gg_mul(bsn, s_nn, nspo, nn, nn, t1)
                        var r1 = 0usize
                        while r1 < nspo {
                            var c1 = 0usize
                            while c1 < nspo {
                                var t = s_ss[r1 * nspo + c1]
                                var r = 0usize
                                while r < nn {
                                    // - S[sp,ns] Bsn' : (r1, c1) = sum_r s_sn[r1, r] bsn[c1, r]
                                    t -= s_sn[r1 * nn + r] * bsn[c1 * nn + r]
                                    // - Bsn S[ns,sp] : sum_r bsn[r1, r] s_sn[c1, r]
                                    t -= bsn[r1 * nn + r] * s_sn[c1 * nn + r]
                                    // + t1 Bsn' : sum_r t1[r1, r] bsn[c1, r]
                                    t += t1[r1 * nn + r] * bsn[c1 * nn + r]
                                    r += 1usize
                                }
                                m1[r1 * nspo + c1] = t
                                c1 += 1usize
                            }
                            r1 += 1usize
                        }
                        let (im1, e16) = gg_inv(a, m1, nspo)
                        if e16 != ok { ret (res, e16) }
                        let (bspo, e17) = mem.alloc[f64](a, nspo)
                        if e17 != ok { ret (res, e17) }
                        gg_mul(yz, im1, 1usize, nspo, nspo, bspo)
                        var ly = 0.0f64
                        q = 0usize
                        while q < nspo {
                            ly += bspo[q] * yz[q]
                            q += 1usize
                        }
                        lambda = s[v * p + v] - ly
                        // B over all p, then without v
                        let (bfull, e18) = mem.alloc[f64](a, p)
                        if e18 != ok { ret (res, e18) }
                        q = 0usize
                        while q < p {
                            bfull[q] = 0.0f64
                            q += 1usize
                        }
                        q = 0usize
                        while q < nspo {
                            bfull[spo[q]] = bspo[q]
                            q += 1usize
                        }
                        q = 0usize
                        while q < nn {
                            var t = 0.0f64
                            var r = 0usize
                            while r < nspo {
                                t -= bspo[r] * bsn[r * nn + q]
                                r += 1usize
                            }
                            bfull[nsp[q]] = t
                            q += 1usize
                        }
                        q = 0usize
                        while q < no {
                            b[q] = bfull[oth[q]]
                            q += 1usize
                        }
                    }
                    // Sigma[v, -v] = B Sigma[-v, -v]; zero the non-spouses; mirror; the diagonal
                    let (sg_oo, e19) = gg_sub(a, sigma, p, oth[0usize..no], oth[0usize..no])
                    if e19 != ok { ret (res, e19) }
                    let (row, e20) = mem.alloc[f64](a, no)
                    if e20 != ok { ret (res, e20) }
                    gg_mul(b, sg_oo, 1usize, no, no, row)
                    q = 0usize
                    while q < no {
                        sigma[v * p + oth[q]] = row[q]
                        q += 1usize
                    }
                    q = 0usize
                    while q < nn {
                        sigma[v * p + nsp[q]] = 0.0f64
                        q += 1usize
                    }
                    q = 0usize
                    while q < no {
                        sigma[oth[q] * p + v] = sigma[v * p + oth[q]]
                        q += 1usize
                    }
                    var bs2 = 0.0f64
                    q = 0usize
                    while q < no {
                        bs2 += b[q] * sigma[oth[q] * p + v]
                        q += 1usize
                    }
                    sigma[v * p + v] = lambda + bs2
                }
                v += 1usize
            }
            var diff = 0.0f64
            i = 0usize
            while i < p * p {
                diff += math.abs[f64](old[i] - sigma[i])
                i += 1usize
            }
            if diff < tol { going = false }
        }
        res.it = iters
    }
    var zeros = 0.0f64
    var r = 0usize
    while r < p {
        var c = r + 1usize
        while c < p {
            if amat[r * p + c] == 0.0f64 { zeros += 1.0f64 }
            c += 1usize
        }
        r += 1usize
    }
    res.df = zeros
    let (kh, e21) = gg_inv(a, sigma, p)
    if e21 != ok { ret (res, e21) }
    let (dv, e22) = likgau(a, kh, s, n, p)
    if e22 != ok { ret (res, e22) }
    res.dev = dv
    ret (res, ok)
}

// ---- d-separation and the marginal log-linear parametrisation ----

// dSep(amat, first, second, cond): are the sets `first` and `second` d-separated given `cond` in the DAG amat (amat[j, i] = 1 an arrow from j to i)? By the moral graph of the ancestors of the three sets: marry the parents of each node, drop the arrow directions, remove `cond` and look for a path from `first` to `second`
fn dsep(a: *mem.Arena, amat: []const f64, p: usize, first: []const usize, second: []const usize, cond: []const usize) -> (bool, err) {
    let (anc, e1) = mem.alloc[bool](a, p)
    let (blocked, e2) = mem.alloc[bool](a, p)
    let (adj, e3) = mem.alloc[bool](a, p * p)
    let (seen, e4) = mem.alloc[bool](a, p)
    let (queue, e5) = mem.alloc[usize](a, p)
    let (tgt, e6) = mem.alloc[bool](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (false, e1) }
    var i = 0usize
    while i < p {
        anc[i] = false
        blocked[i] = false
        seen[i] = false
        tgt[i] = false
        i += 1usize
    }
    i = 0usize
    while i < p * p {
        adj[i] = false
        i += 1usize
    }
    i = 0usize
    while i < first.len {
        anc[first[i]] = true
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        anc[second[i]] = true
        tgt[second[i]] = true
        i += 1usize
    }
    i = 0usize
    while i < cond.len {
        anc[cond[i]] = true
        blocked[cond[i]] = true
        i += 1usize
    }
    // close the set under parents
    var changed = true
    while changed {
        changed = false
        var v = 0usize
        while v < p {
            if anc[v] {
                var u = 0usize
                while u < p {
                    if amat[u * p + v] == 1.0f64 && !anc[u] {
                        anc[u] = true
                        changed = true
                    }
                    u += 1usize
                }
            }
            v += 1usize
        }
    }
    var v = 0usize
    while v < p {
        if anc[v] {
            var u = 0usize
            while u < p {
                if anc[u] && amat[u * p + v] == 1.0f64 {
                    adj[u * p + v] = true
                    adj[v * p + u] = true
                    var w = 0usize
                    while w < p {
                        if anc[w] && w != u && amat[w * p + v] == 1.0f64 {
                            adj[u * p + w] = true
                            adj[w * p + u] = true
                        }
                        w += 1usize
                    }
                }
                u += 1usize
            }
        }
        v += 1usize
    }
    var head = 0usize
    var tail = 0usize
    i = 0usize
    while i < first.len {
        if !blocked[first[i]] && !seen[first[i]] {
            seen[first[i]] = true
            queue[tail] = first[i]
            tail += 1usize
        }
        i += 1usize
    }
    while head < tail {
        let x = queue[head]
        head += 1usize
        if tgt[x] { ret (false, ok) }
        var y = 0usize
        while y < p {
            if adj[x * p + y] && !blocked[y] && !seen[y] {
                seen[y] = true
                queue[tail] = y
                tail += 1usize
            }
            y += 1usize
        }
    }
    ret (true, ok)
}

type Mat = struct { rows: usize, cols: usize, d: []f64 }

fn mat_new(a: *mem.Arena, r: usize, c: usize) -> (Mat, err) {
    let (d, e) = mem.alloc[f64](a, r * c + 1usize)
    var m = Mat { rows: r, cols: c, d: d }
    if e != ok { ret (m, e) }
    var i = 0usize
    while i < r * c {
        d[i] = 0.0f64
        i += 1usize
    }
    ret (m, ok)
}

// x kron y
fn mat_kron(a: *mem.Arena, x: Mat, y: Mat) -> (Mat, err) {
    let (m, e) = mat_new(a, x.rows * y.rows, x.cols * y.cols)
    if e != ok { ret (m, e) }
    var i = 0usize
    while i < x.rows {
        var j = 0usize
        while j < x.cols {
            var k = 0usize
            while k < y.rows {
                var l = 0usize
                while l < y.cols {
                    m.d[(i * y.rows + k) * m.cols + j * y.cols + l] = x.d[i * x.cols + j] * y.d[k * y.cols + l]
                    l += 1usize
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (m, ok)
}

// a kind of rows-by-columns factor: 0 identity-like blocks; see marg_param
type MargParam = struct { c: Mat, m: Mat, g: Mat }

// marg.param(lev, type): the matrices C (contrasts), M (marginalisation, per the type l g c r of each variable's logit) and G (the design) of the marginal log-linear parametrisation of a table with the given numbers of levels; types are the bytes l, g, c, r
fn marg_param(a: *mem.Arena, lev: []const usize, typ: []const u8) -> (MargParam, err) {
    var res: MargParam = zero
    let r = lev.len
    let nsub = (1usize << r) - 1usize
    // the subsets in expand.grid order (first variable fastest), stable by size, the empty set dropped
    let (order, e0) = mem.alloc[usize](a, nsub + 1usize)
    if e0 != ok { ret (res, e0) }
    var cnt = 0usize
    var size = 1usize
    while size <= r {
        var code = 1usize
        while code <= nsub {
            var bits = 0usize
            var h = 0usize
            while h < r {
                if (code >> h) & 1usize == 1usize { bits += 1usize }
                h += 1usize
            }
            if bits == size {
                order[cnt] = code
                cnt += 1usize
            }
            code += 1usize
        }
        size += 1usize
    }
    var cm: Mat = zero
    var mm: Mat = zero
    var gm: Mat = zero
    var first = true
    var q = 0usize
    while q < nsub {
        let code = order[q]
        let (ci0, ea) = mat_new(a, 1usize, 1usize)
        let (mi0, eb) = mat_new(a, 1usize, 1usize)
        let (gi0, ec) = mat_new(a, 1usize, 1usize)
        if ea != ok || eb != ok || ec != ok { ret (res, ea) }
        ci0.d[0usize] = 1.0f64
        mi0.d[0usize] = 1.0f64
        gi0.d[0usize] = 1.0f64
        var ci = ci0
        var mi = mi0
        var gi = gi0
        var h = 0usize
        while h < r {
            let lh = lev[h] - 1usize
            if (code >> h) & 1usize == 1usize {
                // Ci <- cbind(-I, I) %x% Ci
                let (f1, ef1) = mat_new(a, lh, 2usize * lh)
                if ef1 != ok { ret (res, ef1) }
                var d = 0usize
                while d < lh {
                    f1.d[d * 2usize * lh + d] = 0.0f64 - 1.0f64
                    f1.d[d * 2usize * lh + lh + d] = 1.0f64
                    d += 1usize
                }
                let (nc, enc) = mat_kron(a, f1, ci)
                if enc != ok { ret (res, enc) }
                ci = nc
                // Mi factor by type, (2 lh) by (lh + 1): [[X, 0], [0, Y]] with X and Y identity or the lower triangle (or its transpose)
                let (f2, ef2) = mat_new(a, 2usize * lh, lh + 1usize)
                if ef2 != ok { ret (res, ef2) }
                let t = typ[h]
                var rr = 0usize
                while rr < lh {
                    var cc = 0usize
                    while cc < lh {
                        var tri = 0.0f64
                        if cc <= rr { tri = 1.0f64 }
                        var tri_t = 0.0f64
                        if rr <= cc { tri_t = 1.0f64 }
                        var id = 0.0f64
                        if rr == cc { id = 1.0f64 }
                        var top = id
                        var bot = id
                        if t == 103u8 {
                            top = tri
                            bot = tri_t
                        } else if t == 99u8 {
                            bot = tri_t
                        } else if t == 114u8 {
                            top = tri
                        }
                        f2.d[rr * (lh + 1usize) + cc] = top
                        f2.d[(lh + rr) * (lh + 1usize) + 1usize + cc] = bot
                        cc += 1usize
                    }
                    rr += 1usize
                }
                let (nm2, enm) = mat_kron(a, f2, mi)
                if enm != ok { ret (res, enm) }
                mi = nm2
                // Gi factor: lower triangle (lev by lev) without its first column
                let lv = lev[h]
                let (f3, ef3) = mat_new(a, lv, lv - 1usize)
                if ef3 != ok { ret (res, ef3) }
                rr = 0usize
                while rr < lv {
                    var cc = 1usize
                    while cc < lv {
                        if cc <= rr { f3.d[rr * (lv - 1usize) + cc - 1usize] = 1.0f64 }
                        cc += 1usize
                    }
                    rr += 1usize
                }
                let (ng, eng) = mat_kron(a, f3, gi)
                if eng != ok { ret (res, eng) }
                gi = ng
            } else {
                let lv = lev[h]
                let (f2, ef2) = mat_new(a, 1usize, lv)
                let (f3, ef3) = mat_new(a, lv, 1usize)
                if ef2 != ok || ef3 != ok { ret (res, ef2) }
                var d = 0usize
                while d < lv {
                    f2.d[d] = 1.0f64
                    f3.d[d] = 1.0f64
                    d += 1usize
                }
                let (nm2, enm) = mat_kron(a, f2, mi)
                let (ng, eng) = mat_kron(a, f3, gi)
                if enm != ok || eng != ok { ret (res, enm) }
                mi = nm2
                gi = ng
            }
            h += 1usize
        }
        if first {
            cm = ci
            mm = mi
            gm = gi
            first = false
        } else {
            // C <- blkdiag(C, Ci); M <- rbind(M, Mi); G <- cbind(G, Gi)
            let (nc, e1) = mat_new(a, cm.rows + ci.rows, cm.cols + ci.cols)
            let (nm3, e2) = mat_new(a, mm.rows + mi.rows, mm.cols)
            let (ng, e3) = mat_new(a, gm.rows, gm.cols + gi.cols)
            if e1 != ok || e2 != ok || e3 != ok { ret (res, e1) }
            var i = 0usize
            while i < cm.rows {
                var j = 0usize
                while j < cm.cols {
                    nc.d[i * nc.cols + j] = cm.d[i * cm.cols + j]
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < ci.rows {
                var j = 0usize
                while j < ci.cols {
                    nc.d[(cm.rows + i) * nc.cols + cm.cols + j] = ci.d[i * ci.cols + j]
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < mm.rows * mm.cols {
                nm3.d[i] = mm.d[i]
                i += 1usize
            }
            i = 0usize
            while i < mi.rows * mi.cols {
                nm3.d[mm.rows * mm.cols + i] = mi.d[i]
                i += 1usize
            }
            i = 0usize
            while i < gm.rows {
                var j = 0usize
                while j < gm.cols {
                    ng.d[i * ng.cols + j] = gm.d[i * gm.cols + j]
                    j += 1usize
                }
                j = 0usize
                while j < gi.cols {
                    ng.d[i * ng.cols + gm.cols + j] = gi.d[i * gi.cols + j]
                    j += 1usize
                }
                i += 1usize
            }
            cm = nc
            mm = nm3
            gm = ng
        }
        q += 1usize
    }
    res.c = cm
    res.m = mm
    res.g = gm
    ret (res, ok)
}

// ---- fitAncestralGraph: the iterative conditional fitting of a maximal ancestral graph (RICF) ----

fn gg_t(a: *mem.Arena, m: []const f64, r: usize, c: usize) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, r * c + 1usize)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            out[j * r + i] = m[i * c + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

type AgFit = struct { dev: f64, df: f64, it: i64 }

// fitAncestralGraph(mag, S, n): the mixed matrix of the graph is coded as in ggm (1 arrow j -> i at [j, i], 10 line, 100 bi-directed arc, sums for several edges); shat, bhat (I minus the path coefficients), ohat (the error covariance, zero on the undirected part) and lhat (the covariance of the non-undirected part) are written out
fn fitancestral(a: *mem.Arena, mag: []const f64, s: []const f64, p: usize, n: f64, tol: f64, shat: []f64, bhat: []f64, ohat: []f64, lhat: []f64) -> (AgFit, err) {
    var res: AgFit = zero
    let (dg, e0) = mem.alloc[f64](a, p * p)
    let (ug, e1) = mem.alloc[f64](a, p * p)
    let (bg, e2) = mem.alloc[f64](a, p * p)
    let (omega, e3) = mem.alloc[f64](a, p * p)
    let (bm, e4) = mem.alloc[f64](a, p * p)
    let (oldo, e5) = mem.alloc[f64](a, p * p)
    let (oldb, e6) = mem.alloc[f64](a, p * p)
    let (allc, e7) = mem.alloc[usize](a, p)
    let (inug, e8) = mem.alloc[usize](a, p)
    let (isug, e9) = mem.alloc[bool](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (res, e0) }
    var i = 0usize
    while i < p * p {
        let v = i64(mag[i])
        dg[i] = f64(v % 10i64)
        ug[i] = f64((v / 10i64) % 10i64)
        bg[i] = f64((v / 100i64) % 10i64)
        i += 1usize
    }
    i = 0usize
    while i < p {
        allc[i] = i
        i += 1usize
    }
    i = 0usize
    while i < p * p {
        omega[i] = 0.0f64
        bm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        omega[i * p + i] = s[i * p + i]
        bm[i * p + i] = 1.0f64
        i += 1usize
    }
    // the undirected part: nodes with no parent and no spouse
    var nu = 0usize
    i = 0usize
    while i < p {
        var cs = 0.0f64
        var r = 0usize
        while r < p {
            cs += dg[r * p + i] + bg[r * p + i]
            r += 1usize
        }
        isug[i] = cs == 0.0f64
        if isug[i] {
            inug[nu] = i
            nu += 1usize
        }
        i += 1usize
    }
    if nu > 0usize {
        let (ugs, ea) = gg_sub(a, ug, p, inug[0usize..nu], inug[0usize..nu])
        let (ss, eb) = gg_sub(a, s, p, inug[0usize..nu], inug[0usize..nu])
        let (lam, ec) = mem.alloc[f64](a, nu * nu + 1usize)
        if ea != ok || eb != ok || ec != ok { ret (res, ea) }
        var any = false
        i = 0usize
        while i < nu * nu {
            if ugs[i] != 0.0f64 { any = true }
            i += 1usize
        }
        if any {
            let (cf, ef) = fitcongraph(a, ugs, ss, nu, f64(p) + 1.0f64, tol, lam)
            if ef != ok { ret (res, ef) }
        } else {
            i = 0usize
            while i < nu * nu {
                lam[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < nu {
                lam[i * nu + i] = ss[i * nu + i]
                i += 1usize
            }
        }
        i = 0usize
        while i < nu {
            var j = 0usize
            while j < nu {
                omega[inug[i] * p + inug[j]] = lam[i * nu + j]
                j += 1usize
            }
            i += 1usize
        }
    }
    let (spo, e10) = mem.alloc[usize](a, p)
    let (pars, e11) = mem.alloc[usize](a, p)
    let (oth, e12) = mem.alloc[usize](a, p)
    if e10 != ok || e11 != ok || e12 != ok { ret (res, e10) }
    var it = 0i64
    var going = true
    while going {
        it += 1i64
        i = 0usize
        while i < p * p {
            oldo[i] = omega[i]
            oldb[i] = bm[i]
            i += 1usize
        }
        var v = 0usize
        while v < p {
            if !isug[v] {
                var nsp = 0usize
                var npar = 0usize
                var no = 0usize
                var q = 0usize
                while q < p {
                    if q != v {
                        oth[no] = q
                        no += 1usize
                    }
                    if bg[q * p + v] == 1.0f64 {
                        spo[nsp] = q
                        nsp += 1usize
                    }
                    if dg[q * p + v] == 1.0f64 {
                        pars[npar] = q
                        npar += 1usize
                    }
                    q += 1usize
                }
                if nsp == 0usize {
                    if npar != 0usize && it == 1i64 {
                        let (spp, ea) = gg_sub(a, s, p, pars[0usize..npar], pars[0usize..npar])
                        if ea != ok { ret (res, ea) }
                        let (ispp, eb) = gg_inv(a, spp, npar)
                        if eb != ok { ret (res, eb) }
                        var acc = 0.0f64
                        q = 0usize
                        while q < npar {
                            var c = 0.0f64
                            var r = 0usize
                            while r < npar {
                                c += s[v * p + pars[r]] * ispp[r * npar + q]
                                r += 1usize
                            }
                            bm[v * p + pars[q]] = 0.0f64 - c
                            acc += bm[v * p + pars[q]] * s[pars[q] * p + v]
                            q += 1usize
                        }
                        omega[v * p + v] = s[v * p + v] + acc
                    }
                } else {
                    // Z = Oinv[spo, -v] B[-v, ]
                    let (oo, ea) = gg_sub(a, omega, p, oth[0usize..no], oth[0usize..no])
                    if ea != ok { ret (res, ea) }
                    let (ioo, eb) = gg_inv(a, oo, no)
                    if eb != ok { ret (res, eb) }
                    // rows of the full Oinv for spo, columns -v, in the coordinates of `oth`
                    let (zs, ec) = mem.alloc[f64](a, nsp * no + 1usize)
                    if ec != ok { ret (res, ec) }
                    var r = 0usize
                    while r < nsp {
                        var pos = 0usize
                        q = 0usize
                        while q < no {
                            if oth[q] == spo[r] { pos = q }
                            q += 1usize
                        }
                        q = 0usize
                        while q < no {
                            zs[r * no + q] = ioo[pos * no + q]
                            q += 1usize
                        }
                        r += 1usize
                    }
                    let (bo, ed) = gg_sub(a, bm, p, oth[0usize..no], allc[0usize..p])
                    if ed != ok { ret (res, ed) }
                    let (z, ee) = mem.alloc[f64](a, nsp * p + 1usize)
                    if ee != ok { ret (res, ee) }
                    gg_mul(zs, bo, nsp, no, p, z)
                    let (zt, ef) = gg_t(a, z, nsp, p)
                    if ef != ok { ret (res, ef) }
                    // S t(Z) (p by nsp) and Z S t(Z) (nsp by nsp)
                    let (stz, eg) = mem.alloc[f64](a, p * nsp + 1usize)
                    let (zstz, eh) = mem.alloc[f64](a, nsp * nsp + 1usize)
                    if eg != ok || eh != ok { ret (res, eg) }
                    gg_mul(s, zt, p, p, nsp, stz)
                    gg_mul(z, stz, nsp, p, nsp, zstz)
                    let tot = npar + nsp
                    let (xx, ei) = mem.alloc[f64](a, tot * tot + 1usize)
                    let (yx, ej) = mem.alloc[f64](a, tot + 1usize)
                    if ei != ok || ej != ok { ret (res, ei) }
                    r = 0usize
                    while r < npar {
                        q = 0usize
                        while q < npar {
                            xx[r * tot + q] = s[pars[r] * p + pars[q]]
                            q += 1usize
                        }
                        q = 0usize
                        while q < nsp {
                            xx[r * tot + npar + q] = stz[pars[r] * nsp + q]
                            xx[(npar + q) * tot + r] = stz[pars[r] * nsp + q]
                            q += 1usize
                        }
                        yx[r] = s[v * p + pars[r]]
                        r += 1usize
                    }
                    r = 0usize
                    while r < nsp {
                        q = 0usize
                        while q < nsp {
                            xx[(npar + r) * tot + npar + q] = zstz[r * nsp + q]
                            q += 1usize
                        }
                        yx[npar + r] = stz[v * nsp + r]
                        r += 1usize
                    }
                    let (ixx, ek) = gg_inv(a, xx, tot)
                    if ek != ok { ret (res, ek) }
                    let (temp, el) = mem.alloc[f64](a, tot + 1usize)
                    if el != ok { ret (res, el) }
                    gg_mul(yx, ixx, 1usize, tot, tot, temp)
                    r = 0usize
                    while r < npar {
                        bm[v * p + pars[r]] = 0.0f64 - temp[r]
                        r += 1usize
                    }
                    r = 0usize
                    while r < nsp {
                        omega[v * p + spo[r]] = temp[npar + r]
                        omega[spo[r] * p + v] = temp[npar + r]
                        r += 1usize
                    }
                    var tv = s[v * p + v]
                    r = 0usize
                    while r < tot {
                        tv -= temp[r] * yx[r]
                        r += 1usize
                    }
                    // Omega[v, v] = tv + Omega[v, spo] Oinv[spo, spo] Omega[spo, v]; Oinv[spo, spo] is the spo block of ioo
                    var quad = 0.0f64
                    r = 0usize
                    while r < nsp {
                        var pr = 0usize
                        q = 0usize
                        while q < no {
                            if oth[q] == spo[r] { pr = q }
                            q += 1usize
                        }
                        var c = 0usize
                        while c < nsp {
                            var pc = 0usize
                            q = 0usize
                            while q < no {
                                if oth[q] == spo[c] { pc = q }
                                q += 1usize
                            }
                            quad += omega[v * p + spo[r]] * ioo[pr * no + pc] * omega[spo[c] * p + v]
                            c += 1usize
                        }
                        r += 1usize
                    }
                    omega[v * p + v] = tv + quad
                }
            }
            v += 1usize
        }
        var diff = 0.0f64
        i = 0usize
        while i < p * p {
            diff += math.abs[f64](oldo[i] - omega[i]) + math.abs[f64](oldb[i] - bm[i])
            i += 1usize
        }
        if diff < tol { going = false }
    }
    // Sigma = B^-1 Omega B^-T; Lambda: Omega off the undirected part
    let (ib, ef1) = gg_inv(a, bm, p)
    let (ibt, ef2) = gg_t(a, ib, p, p)
    let (tmp, ef3) = mem.alloc[f64](a, p * p)
    if ef1 != ok || ef2 != ok || ef3 != ok { ret (res, ef1) }
    gg_mul(ib, omega, p, p, p, tmp)
    gg_mul(tmp, ibt, p, p, p, shat)
    i = 0usize
    while i < p * p {
        lhat[i] = 0.0f64
        bhat[i] = bm[i]
        i += 1usize
    }
    if nu > 0usize {
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                if !isug[i] && !isug[j] { lhat[i * p + j] = omega[i * p + j] }
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < nu {
            var j = 0usize
            while j < nu {
                omega[inug[i] * p + inug[j]] = 0.0f64
                j += 1usize
            }
            i += 1usize
        }
    }
    i = 0usize
    while i < p * p {
        ohat[i] = omega[i]
        i += 1usize
    }
    var nz = 0.0f64
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            if mag[i * p + j] + mag[j * p + i] != 0.0f64 { nz += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    res.df = f64(p) * (f64(p) - 1.0f64) / 2.0f64 - nz / 2.0f64
    let (kh, eh2) = gg_inv(a, shat, p)
    if eh2 != ok { ret (res, eh2) }
    let (dv, ed2) = likgau(a, kh, s, n, p)
    if ed2 != ok { ret (res, ed2) }
    res.dev = dv
    res.it = it
    ret (res, ok)
}
