// R fpc: nselectboot and prediction.strength under set.seed, with hclustCBI or disthclustCBI as the clustering method, and classifnp / classifdist for the
// classification step (averagedist, fn, knn with nnk = 1, and centroid on data points). Matrices are row-major.
//
// Not here: kmeansCBI, claraCBI and the other clustering methods, the lda and qda classifications, knn with nnk > 1.

use e.algo.rand.r as rg
use e.algo.stat.classknn as ck
use e.algo.stat.fpc as fp
use e.algo.stat.fpc_boot as fb
use e.algo.stat.fpc_coord as fc
use e.math
use e.mem

error Malformed



// class::knn(train, test, cl, k = 1) for the point i against the labelled points (cl > 0), the C code of VR_knn with its fuzz on ties and its draws of
// uniforms for the zero-vote classes in front of the winner; returns the factor code of the winner
fn knn1_point(a: *mem.Arena, rng: *rg.Rng, data: []const f64, n: usize, p: usize, cl: []const i64, i: usize, code: []const usize, nlev: usize) -> usize {
    let fence = 0.99f64 * 1.7976931348623157e308f64
    let eps = 0.0001f64
    let (nnd, e1) = mem.alloc[f64](a, n + 3usize)
    let (pos, e2) = mem.alloc[usize](a, n + 3usize)
    let (votes, e3) = mem.alloc[usize](a, nlev + 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    var kn = 1usize
    nnd[0usize] = fence
    nnd[1usize] = fence
    var j = 0usize
    while j < n {
        if cl[j] > 0i64 {
            var dist = 0.0f64
            var q = 0usize
            while q < p {
                let t = data[i * p + q] - data[j * p + q]
                dist += t * t
                q += 1usize
            }
            if dist <= nnd[0usize] * (1.0f64 + eps) {
                var kk = 0usize
                while kk <= kn {
                    if dist < nnd[kk] {
                        var k1 = kn
                        while k1 > kk {
                            nnd[k1] = nnd[k1 - 1usize]
                            pos[k1] = pos[k1 - 1usize]
                            k1 -= 1usize
                        }
                        nnd[kk] = dist
                        pos[kk] = j
                        if nnd[kn] <= nnd[0usize] { kn += 1usize }
                        kk = kn + 1usize
                    } else {
                        kk += 1usize
                    }
                }
            }
            nnd[kn] = fence
        }
        j += 1usize
    }
    var v = 0usize
    while v <= nlev {
        votes[v] = 0usize
        v += 1usize
    }
    votes[code[usize(cl[pos[0usize]])]] += 1usize
    var e = 1usize
    while e < kn {
        if nnd[e] > nnd[0usize] * (1.0f64 + eps) {
            e = kn
        } else {
            votes[code[usize(cl[pos[e]])]] += 1usize
            e += 1usize
        }
    }
    var mm = 0usize
    var index = 0usize
    var ntie = 1usize
    v = 1usize
    while v <= nlev {
        if votes[v] > mm {
            ntie = 1usize
            index = v
            mm = votes[v]
        } else if votes[v] == mm {
            ntie += 1usize
            if f64(ntie) * rg.runif(rng, 0.0f64, 1.0f64) < 1.0f64 { index = v }
        }
        v += 1usize
    }
    ret index
}

// class::knn1(centroids, point, 1:k): VR_knn1 with its relative fuzz of 1e-4 on tied distances and the reservoir draw among the tied classes
fn knn1_centroid(a: *mem.Arena, rng: *rg.Rng, data: []const f64, p: usize, cen: []const f64, k: usize, i: usize) -> usize {
    let (ind, e1) = mem.alloc[usize](a, k + 1usize)
    let (votes, e2) = mem.alloc[usize](a, k + 2usize)
    if e1 != ok || e2 != ok { ret 0usize }
    let eps = 0.0001f64
    var dm = 1.7976931348623157e308f64
    var nind = 0usize
    var j = 0usize
    while j < k {
        var dist = 0.0f64
        var q = 0usize
        while q < p {
            let t = data[i * p + q] - cen[j * p + q]
            dist += t * t
            q += 1usize
        }
        if dist <= dm * (1.0f64 + eps) {
            if dist < dm * (1.0f64 - eps) {
                nind = 0usize
            } else {
                nind += 1usize
            }
            dm = dist
            ind[nind] = j
        }
        j += 1usize
    }
    if nind == 0usize { ret ind[0usize] + 1usize }
    var v = 0usize
    while v <= k {
        votes[v] = 0usize
        v += 1usize
    }
    v = 0usize
    while v <= nind {
        votes[ind[v] + 1usize] += 1usize
        v += 1usize
    }
    var top = votes[1usize]
    var index = 1usize
    var ntie = 1usize
    v = 2usize
    while v <= k {
        if votes[v] > top {
            ntie = 1usize
            index = v
            top = votes[v]
        } else if votes[v] == top {
            ntie += 1usize
            if f64(ntie) * rg.runif(rng, 0.0f64, 1.0f64) < 1.0f64 { index = v }
        }
        v += 1usize
    }
    ret index
}

// classifnp / classifdist for the n points: cl[i] is a label 1..k or -1 for a point to classify; method 1 averagedist, 2 centroid, 3 fn, 4 knn (nnk = 1).
// d is the n by n dissimilarity matrix, data the n by p points (centroid only). out receives the completed labels.
fn classify(a: *mem.Arena, rng: *rg.Rng, distances: bool, d: []const f64, data: []const f64, n: usize, p: usize, method0: usize, cl: []const i64, k: usize, out: []usize, gcen: []const f64) -> err {
    // method0 carries the method in its units digit and nnk - 1 above it
    let method = method0 % 10usize
    let nnk = method0 / 10usize + 1usize
    var maxd = 0.0f64
    if method == 4usize && distances && nnk > 1usize {
        var q = 0usize
        while q < n * n {
            if d[q] > maxd { maxd = d[q] }
            q += 1usize
        }
    }
    let (cen, e1) = mem.alloc[f64](a, k * p)
    if e1 != ok { ret Malformed }
    var i = 0usize
    while i < n {
        if cl[i] > 0i64 { out[i] = usize(cl[i]) } else { out[i] = 0usize }
        i += 1usize
    }
    if method == 2usize {
        let (sel, e2) = mem.alloc[usize](a, n)
        let (mu, e3) = mem.alloc[f64](a, p)
        if e2 != ok || e3 != ok { ret Malformed }
        var j = 1usize
        while j <= k {
            i = 0usize
            while i < n {
                sel[i] = 0usize
                if cl[i] == i64(j) { sel[i] = 1usize }
                i += 1usize
            }
            fc.col_means(data, n, p, sel, 1usize, mu)
            var cnt1 = 0usize
            i = 0usize
            while i < n {
                cnt1 += sel[i]
                i += 1usize
            }
            // data[clustering == j, ] of a single row is a vector, as.matrix makes it one column and colMeans gives one value for every coordinate
            if cnt1 == 1usize && p > 1usize {
                var sh = 0.0f64
                var sl = 0.0f64
                var q0 = 0usize
                while q0 < p {
                    let (h1, l1) = fp.dd_add(sh, sl, mu[q0] * 1.0f64, 0.0f64)
                    sh = h1
                    sl = l1
                    q0 += 1usize
                }
                let (qh, ql) = fp.dd_div(sh, sl, f64(p))
                q0 = 0usize
                while q0 < p {
                    mu[q0] = qh + ql
                    q0 += 1usize
                }
            }
            var q = 0usize
            while q < p {
                cen[(j - 1usize) * p + q] = mu[q]
                q += 1usize
            }
            j += 1usize
        }
    }
    if method == 2usize && gcen.len >= k * p {
        var gi = 0usize
        while gi < k * p {
            cen[gi] = gcen[gi]
            gi += 1usize
        }
    }
    let (code, e0c) = mem.alloc[usize](a, k + 2usize)
    if e0c != ok { ret Malformed }
    var li = 0usize
    while li <= k + 1usize {
        code[li] = 0usize
        li += 1usize
    }
    i = 0usize
    while i < n {
        if cl[i] > 0i64 && usize(cl[i]) <= k { code[usize(cl[i])] = 1usize }
        i += 1usize
    }
    var nlev = 0usize
    li = 1usize
    while li <= k {
        if code[li] == 1usize {
            nlev += 1usize
            code[li] = nlev
        }
        li += 1usize
    }
    if method == 4usize && !distances && nnk > 1usize {
        // class::knn(train, test, factor(labels), k = nnk) on all the points to classify at once
        var ntr = 0usize
        var nte = 0usize
        i = 0usize
        while i < n {
            if cl[i] > 0i64 { ntr += 1usize } else { nte += 1usize }
            i += 1usize
        }
        let (trn, g1) = mem.alloc[f64](a, ntr * p)
        let (tst, g2) = mem.alloc[f64](a, nte * p)
        let (tcl, g3) = mem.alloc[i64](a, ntr)
        let (lev, g4) = mem.alloc[usize](a, nlev + 1usize)
        if g1 != ok || g2 != ok || g3 != ok || g4 != ok { ret Malformed }
        var tr = 0usize
        var te = 0usize
        i = 0usize
        while i < n {
            var q = 0usize
            if cl[i] > 0i64 {
                while q < p {
                    trn[tr * p + q] = data[i * p + q]
                    q += 1usize
                }
                tcl[tr] = i64(code[usize(cl[i])])
                lev[code[usize(cl[i])]] = usize(cl[i])
                tr += 1usize
            } else {
                while q < p {
                    tst[te * p + q] = data[i * p + q]
                    q += 1usize
                }
                te += 1usize
            }
            i += 1usize
        }
        let (res, pr, e9) = ck.knn(a, rng, trn, tcl, tst, p, nlev, nnk, 0i64, false, true)
        if e9 != ok { ret e9 }
        te = 0usize
        i = 0usize
        while i < n {
            if cl[i] < 0i64 {
                out[i] = lev[usize(res[te])]
                te += 1usize
            }
            i += 1usize
        }
        ret ok
    }
    i = 0usize
    while i < n {
        if cl[i] < 0i64 && method == 4usize && distances && nnk > 1usize {
            // classifdist with nnk > 1: the k nearest (k the number of clusters, as fpc codes it) among the points, the earlier predictions counted
            let (ord, g5) = mem.alloc[usize](a, n)
            if g5 != ok { ret Malformed }
            var q = 0usize
            while q < n {
                ord[q] = q
                q += 1usize
            }
            q = 1usize
            while q < n {
                let t = ord[q]
                var tv = d[i * n + t]
                if cl[t] < 0i64 { tv = maxd + 1.0f64 }
                var w = q
                while w > 0usize {
                    var pv = d[i * n + ord[w - 1usize]]
                    if cl[ord[w - 1usize]] < 0i64 { pv = maxd + 1.0f64 }
                    if pv > tv {
                        ord[w] = ord[w - 1usize]
                        w -= 1usize
                    } else {
                        break
                    }
                }
                ord[w] = t
                q += 1usize
            }
            var bestc = 1usize
            var bestn = 0usize
            var j = 1usize
            while j <= k {
                var cnt = 0usize
                q = 0usize
                while q < k && q < n {
                    if out[ord[q]] == j { cnt += 1usize }
                    q += 1usize
                }
                if cnt > bestn {
                    bestn = cnt
                    bestc = j
                }
                j += 1usize
            }
            out[i] = bestc
        } else if cl[i] < 0i64 {
            var best = 0usize
            var bv = 1.0e300f64
            var j = 1usize
            while j <= k {
                var v = 0.0f64
                if method == 1usize {
                    var sh = 0.0f64
                    var sl = 0.0f64
                    var cnt = 0usize
                    var r = 0usize
                    while r < n {
                        if cl[r] == i64(j) {
                            let (h1, l1) = fp.dd_add(sh, sl, d[i * n + r], 0.0f64)
                            sh = h1
                            sl = l1
                            cnt += 1usize
                        }
                        r += 1usize
                    }
                    v = 1.0e300f64
                    if cnt > 0usize {
                        let (qh, ql) = fp.dd_div(sh, sl, f64(cnt))
                        v = qh + ql
                    }
                }
                if method == 3usize {
                    var mx = -1.0e300f64
                    var r = 0usize
                    while r < n {
                        if cl[r] == i64(j) && d[i * n + r] > mx { mx = d[i * n + r] }
                        r += 1usize
                    }
                    v = mx
                    if mx < -1.0e299f64 { v = 1.0e300f64 }
                }
                if method == 2usize {
                    var s = 0.0f64
                    var q = 0usize
                    while q < p {
                        let t = data[i * p + q] - cen[(j - 1usize) * p + q]
                        s += t * t
                        q += 1usize
                    }
                    v = s
                }
                if method != 4usize && v < bv {
                    bv = v
                    best = j
                }
                j += 1usize
            }
            if method == 4usize && distances {
                var r = 0usize
                while r < n {
                    if cl[r] > 0i64 && d[i * n + r] < bv {
                        bv = d[i * n + r]
                        best = usize(cl[r])
                    }
                    r += 1usize
                }
            }
            if method == 4usize && !distances { best = knn1_point(a, rng, data, n, p, cl, i, code, nlev) }
            if method == 2usize { best = knn1_centroid(a, rng, data, p, cen, k, i) }
            out[i] = best
        }
        i += 1usize
    }
    ret ok
}


// nselectboot(data, B, distances, clustermethod = hclustCBI/disthclustCBI with cp = (method, k placeholder, scaling, noisecut), classification, krange kmin..kmax):
// stab (B by kmax + 1 columns, row-major, 1-based k as column k), stabk (kmax + 1) with NaN for k < kmin, kopt (largeisgood handled by the caller)
fn nselectboot(a: *mem.Arena, data: []const f64, n: usize, p: usize, distances: bool, bcount: usize, cp: []const f64, classification: usize, kmin: usize, kmax: usize, seedv: i64, stab: []f64, stabk: []f64) -> (usize, err) {
    var rng: rg.Rng = zero
    rg.seed(&rng, seedv)
    let (cenv, ecv) = mem.alloc[f64](a, 128usize * p)
    if ecv != ok { ret (0usize, Malformed) }
    let (dm, e1) = mem.alloc[f64](a, n * n)
    let (cj1, e2) = mem.alloc[i64](a, n)
    let (cj2, e3) = mem.alloc[i64](a, n)
    let (cp2, e4) = mem.alloc[f64](a, 4usize)
    let (part, e5) = mem.alloc[usize](a, n)
    let (cl1, e6) = mem.alloc[usize](a, n)
    let (cl2, e7) = mem.alloc[usize](a, n)
    let (md0, e8) = mem.alloc[f64](a, n * p + n * n)
    let (col, e9) = mem.alloc[f64](a, bcount)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (0usize, Malformed) }
    if distances {
        var i = 0usize
        while i < n * n {
            dm[i] = data[i]
            i += 1usize
        }
    } else {
        fc.euclid(data, n, p, dm)
    }
    var cm = 1usize
    if distances { cm = 3usize }
    if cp.len > 4usize && cp[4usize] > 0.5f64 { cm = usize(cp[4usize]) }
    var k = 0usize
    while k <= kmax {
        stabk[k] = 0.0f64 / 0.0f64
        k += 1usize
    }
    k = kmin
    while k <= kmax {
        var rep = 0usize
        while rep < bcount {
            let start = mem.mark(a)
            let (s1, e10) = rg.sample_int(a, &rng, i64(n), i64(n), true)
            let (s2, e11) = rg.sample_int(a, &rng, i64(n), i64(n), true)
            if e10 != ok || e11 != ok { ret (0usize, Malformed) }
            var nc_a = 0usize
            var nc_b = 0usize
            var side = 0usize
            while side < 2usize {
                var sm = s1
                if side == 1usize { sm = s2 }
                var i = 0usize
                while i < n {
                    var j = 0usize
                    if distances {
                        while j < n {
                            md0[i * n + j] = data[(usize(sm[i]) - 1usize) * n + (usize(sm[j]) - 1usize)]
                            j += 1usize
                        }
                    } else {
                        while j < p {
                            md0[i * p + j] = data[(usize(sm[i]) - 1usize) * p + j]
                            j += 1usize
                        }
                    }
                    i += 1usize
                }
                cp2[0usize] = cp[0usize]
                cp2[1usize] = f64(k)
                cp2[2usize] = cp[2usize]
                cp2[3usize] = cp[3usize]
                var gsl = cenv[0usize..0usize]
                if cm == 4usize { gsl = cenv[side * 64usize * p..side * 64usize * p + 64usize * p] }
                let (nc, _, e12) = fb.cluster_run(a, &rng, md0, n, p, cm, cp2, part, gsl)
                if e12 != ok { ret (0usize, e12) }
                var cj = cj1
                if side == 1usize { cj = cj2 }
                i = 0usize
                while i < n {
                    cj[i] = -1i64
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    cj[usize(sm[i]) - 1usize] = i64(part[i])
                    i += 1usize
                }
                if side == 0usize { nc_a = nc } else { nc_b = nc }
                side += 1usize
            }
            // R clusters both resamples before it classifies either, which matters when the clustering draws random numbers
            side = 0usize
            while side < 2usize {
                var cj = cj1
                if side == 1usize { cj = cj2 }
                var kk = nc_a
                if side == 1usize { kk = nc_b }
                if kk < 1usize { kk = 1usize }
                var out = cl1
                if side == 1usize { out = cl2 }
                var gsl = cenv[0usize..0usize]
                if cm == 4usize { gsl = cenv[side * 64usize * p..side * 64usize * p + 64usize * p] }
                let e13 = classify(a, &rng, distances, dm, data, n, p, classification, cj, kk, out, gsl)
                if e13 != ok { ret (0usize, e13) }
                side += 1usize
            }
            // sum(nck1^2 - rowSums(ctable^2)) over the labels 1..kmax
            var tot = 0.0f64
            var l1 = 1usize
            while l1 <= k {
                var nck = 0.0f64
                var sq = 0.0f64
                var l2 = 1usize
                while l2 <= k {
                    var cnt = 0.0f64
                    var i = 0usize
                    while i < n {
                        if cl1[i] == l1 && cl2[i] == l2 { cnt += 1.0f64 }
                        i += 1usize
                    }
                    nck += cnt
                    sq += cnt * cnt
                    l2 += 1usize
                }
                tot += nck * nck - sq
                l1 += 1usize
            }
            stab[rep * (kmax + 1usize) + k] = tot / (f64(n) * f64(n))
            mem.reset(a, start)
            rep += 1usize
        }
        var r = 0usize
        while r < bcount {
            col[r] = stab[r * (kmax + 1usize) + k]
            r += 1usize
        }
        stabk[k] = fc.r_mean(col, bcount)
        k += 1usize
    }
    var kopt = kmin
    k = kmin
    while k <= kmax {
        if stabk[k] < stabk[kopt] { kopt = k }
        k += 1usize
    }
    ret (kopt, ok)
}

// prediction.strength(xdata, Gmin, Gmax, M, clustermethod = hclustCBI/disthclustCBI, classification, cutoff): corr gets the M values of corrpred[[k]] at (k - gmin) * M + l,
// meanpred (index k, gmax + 1 entries) the mean.pred vector; returns optimalk
fn predstr(a: *mem.Arena, data: []const f64, n: usize, p: usize, distances: bool, gmin: usize, gmax: usize, mcount: usize, cp: []const f64, classification: usize, cutoff: f64, seedv: i64, corr: []f64, meanpred: []f64) -> (usize, err) {
    var rng: rg.Rng = zero
    rg.seed(&rng, seedv)
    let (cenv, ecv) = mem.alloc[f64](a, 128usize * p)
    if ecv != ok { ret (0usize, Malformed) }
    let nf0 = n / 2usize
    let (dm, e1) = mem.alloc[f64](a, n * n)
    let (cp2, e2) = mem.alloc[f64](a, 4usize)
    let (md0, e3) = mem.alloc[f64](a, n * p + n * n)
    let (ind, e4) = mem.alloc[usize](a, 2usize * n)
    let (part, e5) = mem.alloc[usize](a, 2usize * n)
    let (jcl, e6) = mem.alloc[i64](a, n)
    let (cls, e7) = mem.alloc[usize](a, 2usize * n)
    let (col, e8) = mem.alloc[f64](a, mcount)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (0usize, Malformed) }
    if distances {
        var i = 0usize
        while i < n * n {
            dm[i] = data[i]
            i += 1usize
        }
    } else {
        fc.euclid(data, n, p, dm)
    }
    var cm = 1usize
    if distances { cm = 3usize }
    if cp.len > 4usize && cp[4usize] > 0.5f64 { cm = usize(cp[4usize]) }
    var k = 0usize
    while k <= gmax {
        meanpred[k] = 0.0f64 / 0.0f64
        k += 1usize
    }
    if gmin > 1usize { meanpred[1usize] = 1.0f64 }
    k = gmin
    while k <= gmax {
        var l = 0usize
        while l < mcount {
            let start = mem.mark(a)
            let (perm, e10) = rg.sample_int(a, &rng, i64(n), i64(n), false)
            if e10 != ok { ret (0usize, e10) }
            var side = 0usize
            while side < 2usize {
                var m = nf0
                var off = 0usize
                if side == 1usize {
                    m = n - nf0
                    off = nf0
                }
                var i = 0usize
                while i < m {
                    ind[side * n + i] = usize(perm[off + i]) - 1usize
                    i += 1usize
                }
                i = 0usize
                while i < m {
                    var j = 0usize
                    if distances {
                        while j < m {
                            md0[i * m + j] = data[ind[side * n + i] * n + ind[side * n + j]]
                            j += 1usize
                        }
                    } else {
                        while j < p {
                            md0[i * p + j] = data[ind[side * n + i] * p + j]
                            j += 1usize
                        }
                    }
                    i += 1usize
                }
                cp2[0usize] = cp[0usize]
                cp2[1usize] = f64(k)
                cp2[2usize] = cp[2usize]
                cp2[3usize] = cp[3usize]
                var gsl = cenv[0usize..0usize]
                if cm == 4usize { gsl = cenv[side * 64usize * p..side * 64usize * p + 64usize * p] }
                let (nc, _, e11) = fb.cluster_run(a, &rng, md0, m, p, cm, cp2, part[side * n..side * n + m], gsl)
                if e11 != ok { ret (0usize, e11) }
                i = 0usize
                while i < n {
                    jcl[i] = -1i64
                    i += 1usize
                }
                i = 0usize
                while i < m {
                    jcl[ind[side * n + i]] = i64(part[side * n + i])
                    i += 1usize
                }
                let e12 = classify(a, &rng, distances, dm, data, n, p, classification, jcl, nc, cls[side * n..side * n + n], gsl)
                if e12 != ok { ret (0usize, e12) }
                side += 1usize
            }
            // half i: its own partition against the classification of its points by the other half's clustering
            var mn = 0.0f64
            var h = 0usize
            while h < 2usize {
                var m = nf0
                if h == 1usize { m = n - nf0 }
                var minps = 1.0e300f64
                var kk = 1usize
                while kk <= k {
                    var nik = 0.0f64
                    var tot = 0.0f64
                    var c2 = 1usize
                    while c2 <= k {
                        var cnt = 0.0f64
                        var t = 0usize
                        while t < m {
                            if part[h * n + t] == kk && cls[(1usize - h) * n + ind[h * n + t]] == c2 { cnt += 1.0f64 }
                            t += 1usize
                        }
                        tot += cnt * cnt - cnt
                        c2 += 1usize
                    }
                    var t = 0usize
                    while t < m {
                        if part[h * n + t] == kk { nik += 1.0f64 }
                        t += 1usize
                    }
                    var psv = 1.0f64
                    if nik > 1.0f64 { psv = tot / (nik * (nik - 1.0f64)) }
                    if psv < minps { minps = psv }
                    kk += 1usize
                }
                mn += minps
                h += 1usize
            }
            corr[(k - gmin) * mcount + l] = mn / 2.0f64
            mem.reset(a, start)
            l += 1usize
        }
        var r = 0usize
        while r < mcount {
            col[r] = corr[(k - gmin) * mcount + r]
            r += 1usize
        }
        meanpred[k] = fc.r_mean(col, mcount)
        k += 1usize
    }
    var opt = 0usize
    k = 1usize
    while k <= gmax {
        if meanpred[k] > cutoff { opt = k }
        k += 1usize
    }
    ret (opt, ok)
}
