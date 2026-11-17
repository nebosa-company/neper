// R cluster (Maechler et al., 2.1.8.2): clusGap, the gap statistic for the number of clusters, and maxSE, its choice rules.
//
//   clus_gap   log W_k of the data and its expectation over B reference data sets drawn uniformly in the range of the data
//              (spaceH0 "original") or of its principal components (spaceH0 "scaledPCA", given the rotation V that
//              svd(centred x) answers), for k = 1..K.max, with the gap and the simulation standard error
//   max_se     maxSE: the number of clusters the five rules (firstSEmax, Tibs2001SEmax, globalSEmax, firstmax, globalmax) pick
//
// The clustering function is one of the package's own: 1 pam, 2 agnes (average) cut by cutree, 3 diana cut by cutree, 4 clara
// (samples 3, the default sampsize), 5 fanny (the defaults), all on the euclidean dissimilarity. x is n by p row-major, no NaN; V is
// p by p column-major. The reference data come from R's generator, rg, which the caller seeds as set.seed does.
//
// Not here: a user-supplied clustering function (kmeans, a closure) and the plot and print methods; the svd of the PCA is the
// caller's, as its signs are LAPACK's.

use e.algo.rand.r as rr
use e.algo.stat.clusterdiss as cd
use e.algo.stat.clusterfanny as cf
use e.algo.stat.clusterpam as cp
use e.algo.stat.clustertwins as ct
use e.algo.stat.hclust as hc
use e.math
use e.mem

error GapFailed

type GapOut = struct { logw: []f64, elogw: []f64, gap: []f64, se: []f64 }

// the clustering of the n rows of x into k clusters by clustering function fun; labels get one integer per row
fn gap_cluster(a: *mem.Arena, x: []const f64, n: usize, p: usize, k: usize, fun: usize, labels: []usize) -> err {
    if fun == 5usize {
        let (dss, e1) = mem.alloc[f64](a, n * (n - 1usize) / 2usize)
        if e1 != ok { ret e1 }
        if cf.fanny_dysta(x, n, p, 1usize, dss) != 0usize { ret GapFailed }
        let empty: []const f64 = zero
        let (r, e2) = cf.fanny_core(a, dss, n, k, empty, 2.0f64, 1.0e-15f64, 500usize, false)
        if e2 != ok { ret e2 }
        var i = 0usize
        while i < n {
            labels[i] = r.clu[i]
            i += 1usize
        }
        ret ok
    }
    if fun == 4usize {
        var ss = 40usize + 2usize * k
        if n < ss { ss = n }
        var rg: rr.Rng = zero
        let (r, e3) = cp.clara_core(a, x, n, p, k, 3usize, ss, 1usize, false, false, true, &rg)
        if e3 != ok { ret e3 }
        if r.jstop != 0usize { ret GapFailed }
        var i = 0usize
        while i < n {
            labels[i] = r.clustering[i]
            i += 1usize
        }
        ret ok
    }
    let (dys, e4) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
    if e4 != ok { ret e4 }
    if cd.dysta(x, n, p, 1usize, dys) != 0usize { ret GapFailed }
    if fun == 1usize {
        let empty: []const usize = zero
        let (r, e5) = cp.pam_core(a, dys, n, k, empty, true, 0usize, false)
        if e5 != ok { ret e5 }
        var i = 0usize
        while i < n {
            labels[i] = r.clu[i]
            i += 1usize
        }
        ret ok
    }
    var alpha: [4]f64 = zero
    var tw: ct.TwinsOut = zero
    if fun == 2usize {
        let (r, e6) = ct.agnes_core(a, dys, n, 1usize, alpha[0usize..4usize])
        if e6 != ok { ret e6 }
        tw = r
    } else {
        let (r, e7) = ct.diana_core(a, dys, n)
        if e7 != ok { ret e7 }
        tw = r
    }
    let (t, e8) = ct.twins_tree(a, tw, n)
    if e8 != ok { ret e8 }
    ret hc.cutree(a, &t, n, k, labels)
}

fn gap_pow(v: f64, d: f64) -> f64 {
    if d == 1.0f64 { ret v }
    if d == 2.0f64 { ret v * v }
    ret math.pow[f64](v, d)
}

// W.k(): half the sum over clusters of the within-cluster distances (raised to d_power), each divided by the cluster size
fn gap_wk(a: *mem.Arena, x: []const f64, n: usize, p: usize, k: usize, fun: usize, d_power: f64) -> (f64, err) {
    let (lab, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (0.0f64, e1) }
    var i = 0usize
    if k > 1usize {
        let e2 = gap_cluster(a, x, n, p, k, fun, lab)
        if e2 != ok { ret (0.0f64, e2) }
    } else {
        while i < n {
            lab[i] = 1usize
            i += 1usize
        }
    }
    var total = 0.0f64
    var lo = 0usize
    var first = true
    var done = 0usize
    while done < n {
        var cur = 0usize
        var have = false
        i = 0usize
        while i < n {
            if first || lab[i] > lo {
                if !have || lab[i] < cur {
                    cur = lab[i]
                    have = true
                }
            }
            i += 1usize
        }
        var size = 0usize
        i = 0usize
        while i < n {
            if lab[i] == cur { size += 1usize }
            i += 1usize
        }
        var s = 0.0f64
        i = 0usize
        while i < n {
            if lab[i] == cur {
                var j = i + 1usize
                while j < n {
                    if lab[j] == cur {
                        var dd = 0.0f64
                        var c = 0usize
                        while c < p {
                            let dv = x[i * p + c] - x[j * p + c]
                            dd += dv * dv
                            c += 1usize
                        }
                        s += gap_pow(math.sqrt[f64](dd), d_power) / f64(size)
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        total += s
        done += size
        lo = cur
        first = false
    }
    ret (0.5f64 * total, ok)
}

// clusGap(x, FUNcluster, K.max, B, d.power, spaceH0); v is read only when pca
fn clus_gap(a: *mem.Arena, x: []const f64, n: usize, p: usize, kmax: usize, bb: usize, d_power: f64, pca: bool, v: []const f64, fun: usize, rg: *rr.Rng) -> (GapOut, err) {
    let (logw, e1) = mem.alloc[f64](a, kmax)
    if e1 != ok { ret (zero, e1) }
    let (elogw, e2) = mem.alloc[f64](a, kmax)
    if e2 != ok { ret (zero, e2) }
    let (gap, e3) = mem.alloc[f64](a, kmax)
    if e3 != ok { ret (zero, e3) }
    let (se, e4) = mem.alloc[f64](a, kmax)
    if e4 != ok { ret (zero, e4) }
    var k = 1usize
    while k <= kmax {
        let (w, e5) = gap_wk(a, x, n, p, k, fun, d_power)
        if e5 != ok { ret (zero, e5) }
        logw[k - 1usize] = math.log[f64](w)
        k += 1usize
    }
    // the centred data and, for scaledPCA, its rotation
    let (cen, e6) = mem.alloc[f64](a, p)
    if e6 != ok { ret (zero, e6) }
    let (xs, e7) = mem.alloc[f64](a, n * p)
    if e7 != ok { ret (zero, e7) }
    let (col, e8) = mem.alloc[f64](a, n)
    if e8 != ok { ret (zero, e8) }
    var c = 0usize
    var i = 0usize
    while c < p {
        i = 0usize
        while i < n {
            col[i] = x[i * p + c]
            i += 1usize
        }
        cen[c] = cd.mean_of(col, n)
        i = 0usize
        while i < n {
            xs[i * p + c] = x[i * p + c] - cen[c]
            i += 1usize
        }
        c += 1usize
    }
    let (rot, e9) = mem.alloc[f64](a, n * p)
    if e9 != ok { ret (zero, e9) }
    i = 0usize
    while i < n {
        c = 0usize
        while c < p {
            var s = 0.0f64
            if pca {
                var l = 0usize
                while l < p {
                    s += xs[i * p + l] * v[l + p * c]
                    l += 1usize
                }
            } else {
                s = xs[i * p + c]
            }
            rot[i * p + c] = s
            c += 1usize
        }
        i += 1usize
    }
    let (rlo, e10) = mem.alloc[f64](a, p)
    if e10 != ok { ret (zero, e10) }
    let (rhi, e11) = mem.alloc[f64](a, p)
    if e11 != ok { ret (zero, e11) }
    c = 0usize
    while c < p {
        rlo[c] = rot[c]
        rhi[c] = rot[c]
        i = 1usize
        while i < n {
            if rot[i * p + c] < rlo[c] { rlo[c] = rot[i * p + c] }
            if rot[i * p + c] > rhi[c] { rhi[c] = rot[i * p + c] }
            i += 1usize
        }
        c += 1usize
    }
    let (z1, e12) = mem.alloc[f64](a, n * p)
    if e12 != ok { ret (zero, e12) }
    let (z, e13) = mem.alloc[f64](a, n * p)
    if e13 != ok { ret (zero, e13) }
    let (lw, e14) = mem.alloc[f64](a, bb * kmax)
    if e14 != ok { ret (zero, e14) }
    var b = 0usize
    while b < bb {
        c = 0usize
        while c < p {
            i = 0usize
            while i < n {
                z1[i * p + c] = rr.runif(rg, rlo[c], rhi[c])
                i += 1usize
            }
            c += 1usize
        }
        i = 0usize
        while i < n {
            c = 0usize
            while c < p {
                var s = 0.0f64
                if pca {
                    var l = 0usize
                    while l < p {
                        s += z1[i * p + l] * v[c + p * l]
                        l += 1usize
                    }
                } else {
                    s = z1[i * p + c]
                }
                z[i * p + c] = s + cen[c]
                c += 1usize
            }
            i += 1usize
        }
        k = 1usize
        while k <= kmax {
            let (w, e15) = gap_wk(a, z, n, p, k, fun, d_power)
            if e15 != ok { ret (zero, e15) }
            lw[b * kmax + (k - 1usize)] = math.log[f64](w)
            k += 1usize
        }
        b += 1usize
    }
    k = 0usize
    while k < kmax {
        var s = 0.0f64
        b = 0usize
        while b < bb {
            s += lw[b * kmax + k]
            b += 1usize
        }
        let m0 = s / f64(bb)
        // R's mean(): the residuals' mean is added back
        var t = 0.0f64
        b = 0usize
        while b < bb {
            t += lw[b * kmax + k] - m0
            b += 1usize
        }
        let m = m0 + t / f64(bb)
        elogw[k] = m
        var ss = 0.0f64
        b = 0usize
        while b < bb {
            let dv = lw[b * kmax + k] - m
            ss += dv * dv
            b += 1usize
        }
        let vr = ss / f64(bb - 1usize)
        se[k] = math.sqrt[f64]((1.0f64 + 1.0f64 / f64(bb)) * vr)
        gap[k] = elogw[k] - logw[k]
        k += 1usize
    }
    ret (GapOut { logw: logw, elogw: elogw, gap: gap, se: se }, ok)
}

// maxSE(f, SE.f, method, SE.factor); method 1 firstSEmax, 2 Tibs2001SEmax, 3 globalSEmax, 4 firstmax, 5 globalmax. The answer is
// the 1-based number of clusters.
fn max_se(f: []const f64, sef: []const f64, kk: usize, method: usize, se_factor: f64) -> usize {
    var gmax = 1usize
    var i = 1usize
    while i < kk {
        if f[i] > f[gmax - 1usize] { gmax = i + 1usize }
        i += 1usize
    }
    if method == 5usize { ret gmax }
    var firstdecr = 0usize
    i = 0usize
    while i + 1usize < kk && firstdecr == 0usize {
        if f[i + 1usize] - f[i] <= 0.0f64 { firstdecr = i + 1usize }
        i += 1usize
    }
    if method == 4usize {
        if firstdecr > 0usize { ret firstdecr }
        ret kk
    }
    if method == 2usize {
        i = 0usize
        while i + 1usize < kk {
            if f[i] >= f[i + 1usize] - se_factor * sef[i + 1usize] { ret i + 1usize }
            i += 1usize
        }
        ret kk
    }
    var nc = kk
    if method == 1usize {
        if firstdecr > 0usize { nc = firstdecr }
    } else {
        nc = gmax
    }
    i = 0usize
    while i + 1usize < nc {
        if f[i] >= f[nc - 1usize] - se_factor * sef[nc - 1usize] { ret i + 1usize }
        i += 1usize
    }
    ret nc
}
