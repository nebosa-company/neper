// R fpc: clusterboot under set.seed: the bootstrap, subset, jitter, bootstrap-plus-jitter and noise resampling with the Jaccard comparison of the original
// clusters against their best match in each resampled clustering. The clustering methods are hclustCBI (scaled data, Euclidean distances), disthclustCBI
// (a dissimilarity matrix), dbscanCBI, kmeansCBI, pamkCBI, claraCBI and the stupidk methods, each with R's noisecut and noise-cluster rules. Matrices are row-major.
//
// The clusters compared are membership rows, so the overlapping lists of mahalCBI, hclusttreeCBI and disthclusttreeCBI work as the partitions do.
//
// Not here: the methods that need mclust, tclust, kernlab or pdfCluster (noisemclustCBI, distnoisemclustCBI, mergenormCBI, tclustCBI, speccCBI, pdfclustCBI), and dbscanCBI on a dissimilarity matrix.

use e.algo.linalg.lapack_syevr as sy
use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.algo.stat.fpc as fp
use e.algo.stat.fpc_coord as fc
use e.algo.stat.fpc_fix as ff
use e.algo.stat.fpc_km as fk
use e.algo.stat.fpc_misc as fm
use e.algo.stat.hclust as hc
use e.math
use e.mem

error Malformed

// the clustering of m rows (m by p data, or the m by m dissimilarities for cm 3): cm 1 hclustCBI, 2 dbscanCBI, 3 disthclustCBI
// cp: cm 1 and 3: hclust method code, k, scaling (cm 1), noisecut; cm 2: eps, MinPts. part receives the labels 1..nc, noise last.
// returns (nc, nccl)
fn cluster_run(a: *mem.Arena, g: *rg.Rng, data: []const f64, m: usize, p: usize, cm: usize, cp: []const f64, part: []usize, cent: []f64) -> (usize, usize, err) {
    var nc = 0usize
    var nccl = 0usize
    var i = 0usize
    if cm >= 4usize && cm <= 6usize {
        // 4 kmeansCBI (cp: runs, k, scaling, criterion 0 ch / 1 asw), 5 pamkCBI and claraCBI with usepam on data, 6 on dissimilarities (cp: -, k, scaling, criterion 0 asw / 2 ch)
        let kk = usize(cp[1usize])
        var kr: [1]usize = zero
        kr[0usize] = kk
        let (lab, el) = mem.alloc[usize](a, m + 1usize)
        if el != ok { ret (0usize, 0usize, Malformed) }
        if cm == 4usize {
            var dat = data
            if cp[2usize] > 0.5f64 {
                let (sd, es) = mem.alloc[f64](a, m * p)
                if es != ok { ret (0usize, 0usize, Malformed) }
                let e0 = fm.scale_cols(a, data, m, p, sd)
                if e0 != ok { ret (0usize, 0usize, e0) }
                dat = sd
            }
            let (cent0, e1) = mem.alloc[f64](a, kk * p)
            let (wss, e2) = mem.alloc[f64](a, kk)
            let (size, e3) = mem.alloc[usize](a, kk + 1usize)
            let (info, e4) = mem.alloc[f64](a, 8usize)
            let (cr, e5) = mem.alloc[f64](a, kk + 1usize)
            if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0usize, 0usize, Malformed) }
            let (bk, e6) = fk.kmeansruns(a, g, dat, m, p, kr[0usize..1usize], 1usize, cp[3usize] > 0.5f64, 100usize, usize(cp[0usize]), false, 0.001f64, 1usize, lab, cent0, wss, size, info, cr)
            if e6 != ok { ret (0usize, 0usize, e6) }
            if cent.len >= kk * p {
                i = 0usize
                while i < kk * p {
                    cent[i] = cent0[i]
                    i += 1usize
                }
            }
            i = 0usize
            while i < m {
                part[i] = lab[i + 1usize]
                i += 1usize
            }
            ret (bk, bk, ok)
        }
        let (med, e7) = mem.alloc[usize](a, kk + 1usize)
        let (cr2, e8) = mem.alloc[f64](a, kk + 1usize)
        if e7 != ok || e8 != ok { ret (0usize, 0usize, Malformed) }
        var ck = 0usize
        if cp[3usize] > 1.5f64 { ck = 2usize }
        let (bk2, e9) = fk.pamk(a, data, m, p, kr[0usize..1usize], 1usize, ck, cp[2usize] > 0.5f64, 0.001f64, cm == 6usize, 10usize, 0i64, part, med, cr2)
        if e9 != ok { ret (0usize, 0usize, e9) }
        ret (bk2, bk2, ok)
    }
    if cm >= 7usize && cm <= 10usize {
        // 7 stupidkcentroidsCBI, 8 stupidknnCBI, 9 stupidkfnCBI, 10 stupidkavenCBI on the m by m dissimilarities (cp: -, k)
        let ks = usize(cp[1usize])
        let es = fm.stupidk_g(a, g, data, m, ks, cm - 7usize, part)
        if es != ok { ret (0usize, 0usize, es) }
        ret (ks, 0usize, ok)
    }
    if cm == 11usize {
        // mahalCBI (cp: mode 0 fuzzy / 1 ml / 2 classical, ca, ca2, clustercut) with fixmahal's defaults: the clusters are the fixed point clusters whose weight exceeds
        // clustercut; cent receives their 0/1 membership, m values each. No cluster found is an error (fpc answers the first group's weights then).
        let (fo, ef) = mem.alloc[f64](a, ff.fx_len(m, m, p, 0usize))
        let (i0, ei) = mem.alloc[f64](a, 1usize)
        if ef != ok || ei != ok { ret (0usize, 0usize, Malformed) }
        let startn = 18usize + p
        let ex = ff.fixmahal(a, data, m, p, usize(cp[0usize]), cp[1usize], cp[2usize], true, startn, startn / 2usize, 0.1f64, 0.85f64, 5usize * m, f64(m) * 1.0e-5f64, i0[0usize..0usize], 0usize, true, m, fo)
        if ex != ok { ret (0usize, 0usize, ex) }
        let stn = usize(fo[4usize])
        if stn == 0usize { ret (0usize, 0usize, Malformed) }
        let sb = 5usize + 2usize * m + m * (m + 1usize)
        let gb = 5usize + 7usize * m + m * (m + 1usize) + m * p + m * p * p
        i = 0usize
        while i < stn {
            let c1 = usize(fo[sb + 4usize * m + i]) - 1usize
            let g1 = usize(fo[sb + 3usize * m + c1]) - 1usize
            var r = 0usize
            while r < m {
                cent[i * m + r] = 0.0f64
                if fo[gb + g1 * m + r] > cp[3usize] { cent[i * m + r] = 1.0f64 }
                r += 1usize
            }
            i += 1usize
        }
        ret (stn, stn, ok)
    }
    if cm == 2usize {
        let (cv, e1) = mem.alloc[i64](a, m)
        let (sd, e2) = mem.alloc[bool](a, m)
        if e1 != ok || e2 != ok { ret (0usize, 0usize, Malformed) }
        let e3 = fp.dbscan(a, data, m, p, cp[0usize], usize(cp[1usize]), cv, sd)
        if e3 != ok { ret (0usize, 0usize, e3) }
        i = 0usize
        while i < m {
            if usize(cv[i]) > nccl { nccl = usize(cv[i]) }
            i += 1usize
        }
        i = 0usize
        while i < m {
            part[i] = usize(cv[i])
            if cv[i] == 0i64 { part[i] = nccl + 1usize }
            if part[i] > nc { nc = part[i] }
            i += 1usize
        }
        ret (nc, nccl, ok)
    }
    let (d, e4) = mem.alloc[f64](a, m * m)
    if e4 != ok { ret (0usize, 0usize, Malformed) }
    if cm == 3usize || cm == 13usize {
        i = 0usize
        while i < m * m {
            d[i] = data[i]
            i += 1usize
        }
    } else {
        let (sx, e5) = mem.alloc[f64](a, m * p)
        let (ones, e6) = mem.alloc[usize](a, m)
        let (mu, e7) = mem.alloc[f64](a, p)
        if e5 != ok || e6 != ok || e7 != ok { ret (0usize, 0usize, Malformed) }
        i = 0usize
        while i < m {
            ones[i] = 1usize
            i += 1usize
        }
        fc.col_means(data, m, p, ones, 1usize, mu)
        var j = 0usize
        while j < p {
            var sh = 0.0f64
            var sl = 0.0f64
            i = 0usize
            while i < m {
                let v = data[i * p + j] - mu[j]
                sx[i * p + j] = v
                let (h1, l1) = fp.dd_add(sh, sl, v * v, 0.0f64)
                sh = h1
                sl = l1
                i += 1usize
            }
            var dv = f64(m - 1usize)
            if dv < 1.0f64 { dv = 1.0f64 }
            let sc = math.sqrt[f64]((sh + sl) / dv)
            i = 0usize
            while i < m {
                if cp[2usize] > 0.5f64 { sx[i * p + j] = sx[i * p + j] / sc }
                i += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < m {
            j = 0usize
            while j < m {
                var s = 0.0f64
                var q = 0usize
                while q < p {
                    let t = sx[i * p + q] - sx[j * p + q]
                    s += t * t
                    q += 1usize
                }
                d[i * m + j] = math.sqrt[f64](s)
                j += 1usize
            }
            i += 1usize
        }
    }
    let (tree, e8) = hc.hclust(a, d, m, usize(cp[0usize]))
    if e8 != ok { ret (0usize, 0usize, e8) }
    if cm >= 12usize {
        // hclusttreeCBI and disthclusttreeCBI (cp: method, minlevel, scaling): every merge of the tree is a cluster, the singletons first when minlevel is 1; cent receives
        // the 0/1 membership of the rows, m values each
        var off = 0usize
        if cp[1usize] < 1.5f64 { off = m }
        i = 0usize
        while i < (off + m) * m {
            cent[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < off {
            cent[i * m + i] = 1.0f64
            i += 1usize
        }
        var s = 0usize
        while s + 2usize < m {
            var side = 0usize
            while side < 2usize {
                var v = tree.merge_a[s]
                if side == 1usize { v = tree.merge_b[s] }
                if v < 0i32 {
                    cent[(off + s) * m + usize(0i32 - v) - 1usize] = 1.0f64
                } else {
                    i = 0usize
                    while i < m {
                        if cent[(off + usize(v) - 1usize) * m + i] > 0.5f64 { cent[(off + s) * m + i] = 1.0f64 }
                        i += 1usize
                    }
                }
                side += 1usize
            }
            s += 1usize
        }
        ret (off + m - 2usize, off + m - 2usize, ok)
    }
    let e9 = hc.cutree(a, &tree, m, usize(cp[1usize]), part)
    if e9 != ok { ret (0usize, 0usize, e9) }
    i = 0usize
    while i < m {
        if part[i] > nc { nc = part[i] }
        i += 1usize
    }
    let (cs, e10) = mem.alloc[usize](a, nc + 1usize)
    let (newn, e11) = mem.alloc[usize](a, nc + 1usize)
    if e10 != ok || e11 != ok { ret (0usize, 0usize, Malformed) }
    var c = 0usize
    while c <= nc {
        cs[c] = 0usize
        c += 1usize
    }
    i = 0usize
    while i < m {
        cs[part[i]] += 1usize
        i += 1usize
    }
    var ncn = 0usize
    c = 1usize
    while c <= nc {
        newn[c] = 0usize
        if f64(cs[c]) > cp[3usize] {
            ncn += 1usize
            newn[c] = ncn
        }
        c += 1usize
    }
    nccl = ncn
    if ncn < nc {
        i = 0usize
        while i < m {
            if newn[part[i]] == 0usize {
                part[i] = ncn + 1usize
            } else {
                part[i] = newn[part[i]]
            }
            i += 1usize
        }
        nc = ncn + 1usize
    }
    ret (nc, nccl, ok)
}

// R's quantile type 7 of the sorted v[0..m]
fn quantile7(v: []const f64, m: usize, prob: f64) -> f64 {
    let index = 1.0f64 + f64(m - 1usize) * prob
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    var qs = v[usize(lo) - 1usize]
    let xh = v[usize(hi) - 1usize]
    if index > lo && xh != qs {
        let h = index - lo
        qs = (1.0f64 - h) * qs + h * xh
    }
    ret qs
}

// the membership rows of a clustering: cluster j (0-based) of cm 11 .. 13 is row j of cent (m values), of the others the rows with label j + 1
fn members(part: []const usize, cent: []const f64, m: usize, cm: usize, nc: usize, out: []usize) {
    var j = 0usize
    while j < nc {
        var r = 0usize
        while r < m {
            out[j * m + r] = 0usize
            if cm >= 11usize {
                if cent[j * m + r] > 0.5f64 { out[j * m + r] = 1usize }
            } else {
                if part[r] == j + 1usize { out[j * m + r] = 1usize }
            }
            r += 1usize
        }
        j += 1usize
    }
}

fn jaccard(m1: []const usize, st1: usize, j: usize, idx1: []const usize, m2: []const usize, st2: usize, k: usize, idx2: []const usize, len: usize) -> f64 {
    var s1 = 0.0f64
    var s2 = 0.0f64
    var both = 0.0f64
    var t = 0usize
    while t < len {
        let x = m1[j * st1 + idx1[t]] == 1usize
        let y = m2[k * st2 + idx2[t]] == 1usize
        if x { s1 += 1.0f64 }
        if y { s2 += 1.0f64 }
        if x && y { both += 1.0f64 }
        t += 1usize
    }
    if s1 + s2 - both == 0.0f64 { ret 0.0f64 }
    ret both / (s1 + s2 - both)
}

// bootmethods: the codes in order, 1 boot 2 subset 3 jitter 4 bojit 5 noise. res (5 * (n + 1) * bcount) receives, for the method of code m, cluster j and
// replication i, res[(m - 1) * nc * bcount + j * bcount + i]. Returns the number of clusters nc of the original clustering.
fn clusterboot(a: *mem.Arena, data: []const f64, n: usize, p: usize, distances: bool, bcount: usize, methods: []const f64, multipleboot: bool, bscompare: bool, jt: f64, nt1: f64, nt2: f64, subtuning: usize, cm: usize, cp: []const f64, noisemethod: bool, seedv: i64, res: []f64) -> (usize, err) {
    var rng: rg.Rng = zero
    rg.seed(&rng, seedv)
    let (nocent, enc) = mem.alloc[f64](a, 2usize * n * n)
    let (mem1, em1) = mem.alloc[usize](a, 2usize * n * n)
    let (mem2, em2) = mem.alloc[usize](a, 2usize * n * n)
    if enc != ok || em1 != ok || em2 != ok { ret (0usize, Malformed) }
    let (part1, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (0usize, Malformed) }
    let (nc, nccl0, e2) = cluster_run(a, &rng, data, n, p, cm, cp, part1, nocent)
    if e2 != ok { ret (0usize, e2) }
    members(part1, nocent, n, cm, nc, mem1)
    var nccl = nccl0
    if !noisemethod { nccl = nc }
    var ri = 0usize
    while ri < 5usize * nc * bcount {
        res[ri] = 0.0f64
        ri += 1usize
    }
    let (jsd, e3) = mem.alloc[f64](a, p)
    let (evec, e4) = mem.alloc[f64](a, p * p)
    let (evals, e5) = mem.alloc[f64](a, p)
    let (mdv, e6) = mem.alloc[f64](a, p)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0usize, Malformed) }
    var needjit = false
    var needeig = false
    var l = 0usize
    while l < methods.len {
        if methods[l] == 3.0f64 || methods[l] == 4.0f64 { needjit = true }
        if methods[l] == 3.0f64 || methods[l] == 4.0f64 || methods[l] == 5.0f64 { needeig = true }
        l += 1usize
    }
    let (ones, e7) = mem.alloc[usize](a, n)
    if e7 != ok { ret (0usize, Malformed) }
    var i = 0usize
    while i < n {
        ones[i] = 1usize
        i += 1usize
    }
    if needeig {
        let (cod, e8) = mem.alloc[f64](a, p * p)
        let (wv, e9) = mem.alloc[f64](a, p)
        let (vv, e10) = mem.alloc[f64](a, p * p)
        if e8 != ok || e9 != ok || e10 != ok { ret (0usize, Malformed) }
        let (_, e11) = fp.cov_rows(a, data, n, p, ones, 1usize, cod)
        if e11 != ok { ret (0usize, e11) }
        fc.sym_lower(cod, p)
        let e12 = sy.dsyevr_all(a, cod, p, wv, vv)
        if e12 != ok { ret (0usize, e12) }
        var k = 0usize
        while k < p {
            evals[k] = wv[p - 1usize - k]
            if evals[k] < 0.0f64 { evals[k] = 0.0f64 }
            var r = 0usize
            while r < p {
                evec[r * p + k] = vv[(p - 1usize - k) * p + r]
                r += 1usize
            }
            k += 1usize
        }
        fc.col_means(data, n, p, ones, 1usize, mdv)
        if needjit {
            let (tv, e13) = mem.alloc[f64](a, p * p)
            let (tinv, e14) = mem.alloc[f64](a, p * p)
            let (rot, e15) = mem.alloc[f64](a, n * p)
            let (sx, e16) = mem.alloc[f64](a, n)
            if e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret (0usize, Malformed) }
            fc.transpose(evec, p, p, tv)
            let e17 = fp.lu_inverse(a, tv, p, tinv)
            if e17 != ok { ret (0usize, e17) }
            fc.mm(data, n, p, tinv, p, rot)
            var j = 0usize
            while j < p {
                i = 0usize
                while i < n {
                    sx[i] = rot[i * p + j]
                    i += 1usize
                }
                fp.cs_sort(sx, n)
                var cnt = 0usize
                i = 1usize
                while i < n {
                    let dx = sx[i] - sx[i - 1usize]
                    if dx > 0.0f64 {
                        sx[cnt] = dx
                        cnt += 1usize
                    }
                    i += 1usize
                }
                fp.cs_sort(sx, cnt)
                jsd[j] = quantile7(sx, cnt, jt)
                j += 1usize
            }
        }
    }
    let (bsamp, e18) = mem.alloc[usize](a, n)
    let (md0, e19) = mem.alloc[f64](a, n * p + n * n)
    let (bc, e20) = mem.alloc[usize](a, n)
    let (idx1, e21) = mem.alloc[usize](a, n)
    let (idx2, e22) = mem.alloc[usize](a, n)
    let (noiseind, e23) = mem.alloc[bool](a, n)
    let (jn, e24) = mem.alloc[f64](a, n * p)
    let (jn2, e25) = mem.alloc[f64](a, n * p)
    let (vt, e26) = mem.alloc[f64](a, p * p)
    if e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok || e24 != ok || e25 != ok || e26 != ok { ret (0usize, Malformed) }
    fc.transpose(evec, p, p, vt)
    l = 0usize
    while l < methods.len {
        let meth = usize(methods[l])
        var rep = 0usize
        while rep < bcount {
            let start = mem.mark(a)
            var bl = 0usize
            var msz = n
            if meth == 1usize || meth == 4usize {
                let (sm, e27) = rg.sample_int(a, &rng, i64(n), i64(n), true)
                if e27 != ok { ret (0usize, e27) }
                i = 0usize
                while i < n {
                    let v = usize(sm[i]) - 1usize
                    var dup = false
                    if meth == 1usize && !multipleboot {
                        var q = 0usize
                        while q < bl {
                            if bsamp[q] == v { dup = true }
                            q += 1usize
                        }
                    }
                    if !dup {
                        bsamp[bl] = v
                        bl += 1usize
                    }
                    i += 1usize
                }
                msz = bl
            }
            if meth == 2usize {
                let (sm, e27) = rg.sample_int(a, &rng, i64(n), i64(subtuning), false)
                if e27 != ok { ret (0usize, e27) }
                i = 0usize
                while i < subtuning {
                    bsamp[i] = usize(sm[i]) - 1usize
                    i += 1usize
                }
                bl = subtuning
                msz = bl
            }
            if meth == 3usize {
                i = 0usize
                while i < n {
                    bsamp[i] = i
                    i += 1usize
                }
                bl = n
            }
            // the data of this replication
            if meth == 1usize || meth == 2usize || meth == 4usize || meth == 3usize {
                var r = 0usize
                while r < msz {
                    var c = 0usize
                    if distances {
                        while c < msz {
                            md0[r * msz + c] = data[bsamp[r] * n + bsamp[c]]
                            c += 1usize
                        }
                    } else {
                        while c < p {
                            md0[r * p + c] = data[bsamp[r] * p + c]
                            c += 1usize
                        }
                    }
                    r += 1usize
                }
            }
            if meth == 3usize || meth == 4usize {
                var j = 0usize
                while j < p {
                    i = 0usize
                    while i < n {
                        jn[i * p + j] = rg.rnorm(&rng, 0.0f64, jsd[j])
                        i += 1usize
                    }
                    j += 1usize
                }
                fc.mm(jn, n, p, vt, p, jn2)
                i = 0usize
                while i < n * p {
                    md0[i] = md0[i] + jn2[i]
                    i += 1usize
                }
                if meth == 4usize { bl = n }
            }
            if meth == 5usize {
                var nn = 0usize
                i = 0usize
                while i < n {
                    noiseind[i] = rd.rbinom(&rng, 1.0f64, nt1) > 0.5f64
                    if noiseind[i] { nn += 1usize }
                    i += 1usize
                }
                var j = 0usize
                while j < p {
                    var rr = 0usize
                    while rr < nn {
                        jn[rr * p + j] = rg.runif(&rng, 0.0f64 - nt2 * math.sqrt[f64](evals[j]), nt2 * math.sqrt[f64](evals[j]))
                        rr += 1usize
                    }
                    j += 1usize
                }
                fc.mm(jn, nn, p, vt, p, jn2)
                i = 0usize
                var nr = 0usize
                bl = 0usize
                while i < n {
                    var j2 = 0usize
                    while j2 < p {
                        if noiseind[i] {
                            md0[i * p + j2] = jn2[nr * p + j2] + mdv[j2]
                        } else {
                            md0[i * p + j2] = data[i * p + j2]
                        }
                        j2 += 1usize
                    }
                    if noiseind[i] {
                        nr += 1usize
                    } else {
                        bsamp[bl] = i
                        bl += 1usize
                    }
                    i += 1usize
                }
                msz = n
            }
            let (bnc, bnccl0, e28) = cluster_run(a, &rng, md0, msz, p, cm, cp, bc, nocent)
            if e28 != ok { ret (0usize, e28) }
            members(bc, nocent, msz, cm, bnc, mem2)
            var bnccl = bnccl0
            if !noisemethod { bnccl = bnc }
            // the cases compared
            var len = bl
            if meth == 1usize || meth == 4usize {
                if multipleboot {
                    if bscompare {
                        len = n
                        i = 0usize
                        while i < n {
                            idx1[i] = bsamp[i]
                            idx2[i] = i
                            i += 1usize
                        }
                    } else {
                        len = 1usize
                        idx1[0usize] = bsamp[0usize]
                        idx2[0usize] = 0usize
                        if n >= 2usize && bsamp[1usize] != bsamp[0usize] {
                            len = 2usize
                            idx1[1usize] = bsamp[1usize]
                            idx2[1usize] = 1usize
                        }
                    }
                } else {
                    i = 0usize
                    while i < bl {
                        idx1[i] = bsamp[i]
                        idx2[i] = i
                        i += 1usize
                    }
                }
            }
            if meth == 2usize {
                i = 0usize
                while i < bl {
                    idx1[i] = bsamp[i]
                    idx2[i] = i
                    i += 1usize
                }
            }
            if meth == 3usize {
                i = 0usize
                while i < n {
                    idx1[i] = i
                    idx2[i] = i
                    i += 1usize
                }
            }
            if meth == 5usize {
                i = 0usize
                while i < bl {
                    idx1[i] = bsamp[i]
                    idx2[i] = bsamp[i]
                    i += 1usize
                }
            }
            let base = (meth - 1usize) * nc * bcount
            var j = 1usize
            while j <= nccl {
                var mg = 0.0f64
                var k = 1usize
                while k <= bnccl {
                    let cg = jaccard(mem1, n, j - 1usize, idx1, mem2, msz, k - 1usize, idx2, len)
                    if cg > mg { mg = cg }
                    k += 1usize
                }
                res[base + (j - 1usize) * bcount + rep] = mg
                j += 1usize
            }
            if noisemethod && nc > nccl {
                var mg = 0.0f64
                if bnc > bnccl { mg = jaccard(mem1, n, nc - 1usize, idx1, mem2, msz, bnc - 1usize, idx2, len) }
                res[base + (nc - 1usize) * bcount + rep] = mg
            }
            mem.reset(a, start)
            rep += 1usize
        }
        l += 1usize
    }
    ret (nc, ok)
}
