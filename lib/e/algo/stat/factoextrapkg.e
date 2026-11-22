// R factoextra: get_eigenvalue, hcut (hclust on get_dist with the silhouette information) and the wss and silhouette curves of fviz_nbclust over hcut, plus the NbClust
// package's indices over an hclust tree: kl, ch, hartigan, scott, marriot, trcovw, tracew, friedman, rubin, cindex, db, silhouette, ratkowsky, ball, ptbiserial, frey,
// mcclain, gamma, gplus, tau, dunn, hubert, sdindex, dindex, sdbw and the number of clusters the simple selection rules pick.
// get_pca_var and get_pca_ind return the FactoMineR blocks unchanged (e.algo.stat.factominepkg.pca).
// Also ccc, duda, pseudot2, beale, gap and the selection rules of every index but Frey, Hubert and Dindex (the last two are graphical in NbClust).
// Not here: NbClust's kmeans method, the "binary", "canberra" and "minkowski" distances, nc = 1, get_pca_var of prcomp and princomp, Spearman and Kendall in get_dist.

use e.algo.stat.clusterpkg as cpk
use e.algo.stat.hclust as hcl
use e.algo.rand.r as rg
use e.math
use e.math.nmath_beta as nbeta
use e.mem

fn fx_zf(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

// get_eigenvalue: eigenvalue, variance.percent, cumulative.variance.percent (each nd), from the eigenvalues and their percentages
fn get_eigenvalue(eig: []const f64, pct: []const f64, nd: usize, out: []f64) {
    var run = 0.0f64
    var i = 0usize
    while i < nd {
        run += pct[i]
        out[i] = eig[i]
        out[nd + i] = pct[i]
        out[2usize * nd + i] = run
        i += 1usize
    }
}

// get_dist: metric 0 euclidean, 1 maximum, 2 manhattan, 3 pearson (1 - cor of the rows); d is n by n
fn get_dist(a: *mem.Arena, x: []const f64, n: usize, p: usize, metric: usize, d: []f64) -> err {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            if metric == 3usize {
                var mi = 0.0f64
                var mj = 0.0f64
                var k = 0usize
                while k < p {
                    mi += x[i * p + k]
                    mj += x[j * p + k]
                    k += 1usize
                }
                mi = mi / f64(p)
                mj = mj / f64(p)
                var sxy = 0.0f64
                var sxx = 0.0f64
                var syy = 0.0f64
                k = 0usize
                while k < p {
                    let u = x[i * p + k] - mi
                    let v = x[j * p + k] - mj
                    sxy += u * v
                    sxx += u * u
                    syy += v * v
                    k += 1usize
                }
                s = 1.0f64 - sxy / math.sqrt[f64](sxx * syy)
                if i == j { s = 0.0f64 }
            } else {
                var k = 0usize
                while k < p {
                    var t = x[i * p + k] - x[j * p + k]
                    if t < 0.0f64 { t = 0.0f64 - t }
                    if metric == 0usize { s += t * t }
                    if metric == 1usize {
                        if t > s { s = t }
                    }
                    if metric == 2usize { s += t }
                    k += 1usize
                }
                if metric == 0usize { s = math.sqrt[f64](s) }
            }
            d[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// hcut(x, k, hc_func = "hclust", hc_method, hc_metric, stand): stand scales the columns (n - 1 divisor). method is e.algo.stat.hclust's code. out: cluster (n),
// size (k), silhouette width (n, observation order), neighbour (n), cluster average widths (k), average width (1), merge a (n-1), merge b (n-1), height (n-1), order (n)
fn hcut(a: *mem.Arena, x0: []const f64, n: usize, p: usize, k: usize, method: usize, metric: usize, stand: bool, out: []f64) -> err {
    let (x, e1) = fx_zf(a, n * p)
    let (d, e2) = fx_zf(a, n * n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n * p {
        x[i] = x0[i]
        i += 1usize
    }
    if stand {
        var j = 0usize
        while j < p {
            var m = 0.0f64
            i = 0usize
            while i < n {
                m += x[i * p + j]
                i += 1usize
            }
            m = m / f64(n)
            var s2 = 0.0f64
            i = 0usize
            while i < n {
                let t = x[i * p + j] - m
                s2 += t * t
                i += 1usize
            }
            let sd = math.sqrt[f64](s2 / f64(n - 1usize))
            i = 0usize
            while i < n {
                x[i * p + j] = (x[i * p + j] - m) / sd
                i += 1usize
            }
            j += 1usize
        }
    }
    let e3 = get_dist(a, x, n, p, metric, d)
    if e3 != ok { ret e3 }
    let (tr, e4) = hcl.hclust(a, d, n, method)
    if e4 != ok { ret e4 }
    let (cl, e5) = mem.alloc[usize](a, n)
    let (si, e6) = fx_zf(a, n)
    let (nbr, e7) = mem.alloc[usize](a, n)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    let e8 = hcl.cutree(a, &tr, n, k, cl)
    if e8 != ok { ret e8 }
    let e9 = cpk.sildist(a, d, n, cl, k, true, si, nbr)
    if e9 != ok { ret e9 }
    let m = n - 1usize
    let o_size = n
    let o_si = o_size + k
    let o_nb = o_si + n
    let o_cav = o_nb + n
    let o_avg = o_cav + k
    let o_ma = o_avg + 1usize
    let o_mb = o_ma + m
    let o_ht = o_mb + m
    let o_ord = o_ht + m
    i = 0usize
    while i < k {
        out[o_size + i] = 0.0f64
        out[o_cav + i] = 0.0f64
        i += 1usize
    }
    var tot = 0.0f64
    i = 0usize
    while i < n {
        out[i] = f64(cl[i])
        out[o_size + cl[i] - 1usize] += 1.0f64
        out[o_si + i] = si[i]
        out[o_nb + i] = f64(nbr[i])
        out[o_cav + cl[i] - 1usize] += si[i]
        tot += si[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        out[o_cav + i] = out[o_cav + i] / out[o_size + i]
        i += 1usize
    }
    out[o_avg] = tot / f64(n)
    i = 0usize
    while i < m {
        out[o_ma + i] = f64(tr.merge_a[i])
        out[o_mb + i] = f64(tr.merge_b[i])
        out[o_ht + i] = tr.height[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[o_ord + i] = f64(tr.order[i])
        i += 1usize
    }
    ret ok
}

// fviz_nbclust over hcut on d (n by n): wss[k] (k = 1..kmax) is .get_withinSS, sil[k] the average silhouette width (k >= 2; index 0 unused). out: wss (kmax), sil (kmax)
fn nbclust_curves(a: *mem.Arena, d: []const f64, n: usize, kmax: usize, method: usize, out: []f64) -> err {
    let (tr, e1) = hcl.hclust(a, d, n, method)
    if e1 != ok { ret e1 }
    let (cl, e2) = mem.alloc[usize](a, n)
    let (si, e3) = fx_zf(a, n)
    let (nbr, e4) = mem.alloc[usize](a, n)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var k = 1usize
    while k <= kmax {
        let e5 = hcl.cutree(a, &tr, n, k, cl)
        if e5 != ok { ret e5 }
        var w = 0.0f64
        var c = 1usize
        while c <= k {
            var cnt = 0usize
            var s = 0.0f64
            var i = 0usize
            while i < n {
                if cl[i] == c {
                    cnt += 1usize
                    var j = 0usize
                    while j < i {
                        if cl[j] == c { s += d[i * n + j] * d[i * n + j] }
                        j += 1usize
                    }
                }
                i += 1usize
            }
            if cnt > 1usize { w += s / f64(cnt) }
            c += 1usize
        }
        out[k - 1usize] = w
        out[kmax + k - 1usize] = 0.0f64
        if k >= 2usize {
            let e6 = cpk.sildist(a, d, n, cl, k, true, si, nbr)
            if e6 != ok { ret e6 }
            var t = 0.0f64
            var i = 0usize
            while i < n {
                t += si[i]
                i += 1usize
            }
            out[kmax + k - 1usize] = t / f64(n)
        }
        k += 1usize
    }
    ret ok
}

fn fx_cent(x: []const f64, n: usize, p: usize, cl: []const usize, k: usize, cen: []f64, cnt: []f64) {
    var i = 0usize
    while i < k * p {
        cen[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        cnt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let c = cl[i] - 1usize
        cnt[c] += 1.0f64
        var j = 0usize
        while j < p {
            cen[c * p + j] += x[i * p + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < p {
            cen[i * p + j] = cen[i * p + j] / cnt[i]
            j += 1usize
        }
        i += 1usize
    }
}

fn fx_wgss(x: []const f64, n: usize, p: usize, cl: []const usize, cen: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            let t = x[i * p + j] - cen[(cl[i] - 1usize) * p + j]
            s += t * t
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn fx_tss(x: []const f64, n: usize, p: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x[i * p + j]
            i += 1usize
        }
        m = m / f64(n)
        i = 0usize
        while i < n {
            let t = x[i * p + j] - m
            s += t * t
            i += 1usize
        }
        j += 1usize
    }
    ret s
}

// within-cluster sum of squares with k clusters
fn fx_w(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, k: usize) -> (f64, err) {
    let (cen, e1) = fx_zf(a, k * p)
    let (cnt, e2) = fx_zf(a, k)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    fx_cent(x, n, p, cl, k, cen, cnt)
    ret (fx_wgss(x, n, p, cl, cen), ok)
}

// determinant and the diagonal of the inverse of the p by p matrix m (row-major) by Gauss-Jordan with partial pivoting; m is destroyed
fn fx_det_inv_diag(a: *mem.Arena, m: []f64, p: usize, invd: []f64) -> (f64, err) {
    let (inv, e1) = fx_zf(a, p * p)
    if e1 != ok { ret (0.0f64, e1) }
    var i = 0usize
    while i < p {
        inv[i * p + i] = 1.0f64
        i += 1usize
    }
    var det = 1.0f64
    var c = 0usize
    while c < p {
        var piv = c
        var best = m[c * p + c]
        if best < 0.0f64 { best = 0.0f64 - best }
        var r = c + 1usize
        while r < p {
            var v = m[r * p + c]
            if v < 0.0f64 { v = 0.0f64 - v }
            if v > best {
                best = v
                piv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret (0.0f64, ok) }
        if piv != c {
            var q = 0usize
            while q < p {
                let t1 = m[c * p + q]
                m[c * p + q] = m[piv * p + q]
                m[piv * p + q] = t1
                let t2 = inv[c * p + q]
                inv[c * p + q] = inv[piv * p + q]
                inv[piv * p + q] = t2
                q += 1usize
            }
            det = 0.0f64 - det
        }
        let pv = m[c * p + c]
        det = det * pv
        var q = 0usize
        while q < p {
            m[c * p + q] = m[c * p + q] / pv
            inv[c * p + q] = inv[c * p + q] / pv
            q += 1usize
        }
        r = 0usize
        while r < p {
            if r != c {
                let f = m[r * p + c]
                q = 0usize
                while q < p {
                    m[r * p + q] = m[r * p + q] - f * m[c * p + q]
                    inv[r * p + q] = inv[r * p + q] - f * inv[c * p + q]
                    q += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < p {
        invd[i] = inv[i * p + i]
        i += 1usize
    }
    ret (det, ok)
}

fn fx_det(a: *mem.Arena, m0: []const f64, p: usize) -> (f64, err) {
    let (m, e1) = fx_zf(a, p * p)
    let (dg, e2) = fx_zf(a, p)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    var i = 0usize
    while i < p * p {
        m[i] = m0[i]
        i += 1usize
    }
    let (dt, e3) = fx_det_inv_diag(a, m, p, dg)
    ret (dt, e3)
}

// Average.scattering: scatt and stdev
fn fx_scatter(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, k: usize, cen: []const f64, cnt: []const f64) -> (f64, f64, err) {
    let (vc, e1) = fx_zf(a, k * p)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    var i = 0usize
    while i < n {
        let u = cl[i] - 1usize
        var j = 0usize
        while j < p {
            let t = x[i * p + j] - cen[u * p + j]
            vc[u * p + j] += t * t
            j += 1usize
        }
        i += 1usize
    }
    var sv = 0.0f64
    var u = 0usize
    while u < k {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            vc[u * p + j] = vc[u * p + j] / cnt[u]
            s += vc[u * p + j] * vc[u * p + j]
            j += 1usize
        }
        sv += math.sqrt[f64](s)
        u += 1usize
    }
    var vm2 = 0.0f64
    var j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += x[i * p + j]
            i += 1usize
        }
        m = m / f64(n)
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            let t = x[i * p + j] - m
            s2 += t * t
            i += 1usize
        }
        let v = s2 / f64(n - 1usize) * f64(n - 1usize) / f64(n)
        vm2 += v * v
        j += 1usize
    }
    let stdev = (1.0f64 / f64(k)) * math.sqrt[f64](sv)
    let scat = (1.0f64 / f64(k)) * (sv / math.sqrt[f64](vm2))
    ret (scat, stdev, ok)
}

// Dis of NbClust: centre separation factor
fn fx_dis(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, k: usize) -> (f64, err) {
    let (cen, e1) = fx_zf(a, k * p)
    let (cnt, e2) = fx_zf(a, k)
    let (dc, e3) = fx_zf(a, k * k)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    if e3 != ok { ret (0.0f64, e3) }
    fx_cent(x, n, p, cl, k, cen, cnt)
    var dmin = 1.0e300f64
    var dmax = 0.0f64
    var u = 0usize
    while u < k {
        var v = 0usize
        while v < k {
            var s = 0.0f64
            var j = 0usize
            while j < p {
                let t = cen[u * p + j] - cen[v * p + j]
                s += t * t
                j += 1usize
            }
            let dd = math.sqrt[f64](s)
            dc[u * k + v] = dd
            if v > u {
                if dd < dmin { dmin = dd }
                if dd > dmax { dmax = dd }
            }
            v += 1usize
        }
        u += 1usize
    }
    var s2 = 0.0f64
    u = 0usize
    while u < k {
        var s1 = 0.0f64
        var v = 0usize
        while v < k {
            s1 += dc[u * k + v]
            v += 1usize
        }
        s2 += 1.0f64 / s1
        u += 1usize
    }
    ret ((dmax / dmin) * s2, ok)
}

// the table of NbClust (res) for nc = minc..maxc over hclust(method) on the euclidean (metric 0), maximum or manhattan distance of x; minc >= 2, maxc + 1 <= n.
// Columns are R's: 0 KL 1 CH 2 Hartigan 4 Scott 5 Marriot 6 TrCovW 7 TraceW 8 Friedman 9 Rubin 10 Cindex 11 DB 12 Silhouette 16 Ratkowsky 17 Ball 18 Ptbiserial 20 Frey
// 21 McClain 22 Gamma 23 Gplus 24 Tau 25 Dunn 26 Hubert 27 SDindex 28 Dindex 29 SDbw (the rest stay 0).
// out: res (rows by 30, row-major), then best nc per column (30; 0 where there is no simple rule here)
fn nbclust(a: *mem.Arena, x: []const f64, n: usize, p: usize, method: usize, metric: usize, minc: usize, maxc: usize, out: []f64) -> err {
    let rows = maxc - minc + 1usize
    let (md, e1) = fx_zf(a, n * n)
    if e1 != ok { ret e1 }
    let e2 = get_dist(a, x, n, p, metric, md)
    if e2 != ok { ret e2 }
    let (tr, e3) = hcl.hclust(a, md, n, method)
    if e3 != ok { ret e3 }
    let (cl0, e4) = mem.alloc[usize](a, n)
    let (cl1, e5) = mem.alloc[usize](a, n)
    let (cl2, e6) = mem.alloc[usize](a, n)
    let (clm, e7) = mem.alloc[usize](a, n)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    let (cen, e8) = fx_zf(a, (maxc + 2usize) * p)
    let (cnt, e9) = fx_zf(a, maxc + 2usize)
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    let (pm, e10) = fx_zf(a, p * p)
    let (wm, e11) = fx_zf(a, p * p)
    let (wc, e12) = fx_zf(a, p * p)
    let (idg, e13) = fx_zf(a, p)
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    let nn = f64(n)
    var i = 0usize
    while i < rows * 34usize + 30usize {
        out[i] = 0.0f64
        i += 1usize
    }
    // P = X'X (uncentred)
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += x[i * p + r] * x[i * p + c]
                i += 1usize
            }
            pm[r * p + c] = s
            c += 1usize
        }
        r += 1usize
    }
    let e14 = hcl.cutree(a, &tr, n, maxc, clm)
    if e14 != ok { ret e14 }
    let (alpha, e15) = fx_dis(a, x, n, p, clm, maxc)
    if e15 != ok { ret e15 }
    let (detp, e16) = fx_det(a, pm, p)
    if e16 != ok { ret e16 }
    let tss = fx_tss(x, n, p)
    var trp = 0.0f64
    r = 0usize
    while r < p {
        trp += pm[r * p + r]
        r += 1usize
    }
    let pf = 2.0f64 / f64(p)
    // singular values of the uncentred matrix as NbClust's ccc takes them: sqrt of the eigenvalues of X'X / (n - 1), zeros replaced by 1
    let (ev, e30) = fx_zf(a, p)
    let (ssv, e31) = fx_zf(a, p)
    let (uu, e32) = fx_zf(a, p)
    if e30 != ok { ret e30 }
    if e31 != ok { ret e31 }
    if e32 != ok { ret e32 }
    let e33 = fx_eigsym(a, pm, p, nn - 1.0f64, ev)
    if e33 != ok { ret e33 }
    var vv = 1.0f64
    i = 0usize
    while i < p {
        var sq = 0.0f64
        if ev[i] > 0.0f64 { sq = math.sqrt[f64](ev[i]) }
        ssv[i] = 1.0f64
        if sq != 0.0f64 { ssv[i] = sq }
        vv = vv * ssv[i]
        i += 1usize
    }
    let ocr = rows * 30usize + 30usize
    // reference data of the gap statistic: every column is runif(n, min, max) after set.seed(1), so the draws repeat and the reference sets are all the same
    let (xnew, e34) = fx_zf(a, n * p)
    let (dxn, e35) = fx_zf(a, n * n)
    if e34 != ok { ret e34 }
    if e35 != ok { ret e35 }
    var gr: rg.Rng = zero
    var j0 = 0usize
    while j0 < p {
        var lo = x[j0]
        var hi = x[j0]
        i = 0usize
        while i < n {
            if x[i * p + j0] < lo { lo = x[i * p + j0] }
            if x[i * p + j0] > hi { hi = x[i * p + j0] }
            i += 1usize
        }
        rg.seed(&gr, 1i64)
        i = 0usize
        while i < n {
            xnew[i * p + j0] = rg.runif(&gr, lo, hi)
            i += 1usize
        }
        j0 += 1usize
    }
    let e36 = get_dist(a, xnew, n, p, 0usize, dxn)
    if e36 != ok { ret e36 }
    let (tr2, e37) = hcl.hclust(a, dxn, n, method)
    if e37 != ok { ret e37 }
    var row = 0usize
    while row < rows {
        let nc = minc + row
        let e17 = hcl.cutree(a, &tr, n, nc - 1usize, cl0)
        if e17 != ok { ret e17 }
        let e18 = hcl.cutree(a, &tr, n, nc, cl1)
        if e18 != ok { ret e18 }
        let e19 = hcl.cutree(a, &tr, n, nc + 1usize, cl2)
        if e19 != ok { ret e19 }
        let o = row * 30usize
        let (w0, e20) = fx_w(a, x, n, p, cl0, nc - 1usize)
        let (w1, e21) = fx_w(a, x, n, p, cl1, nc)
        let (w2, e22) = fx_w(a, x, n, p, cl2, nc + 1usize)
        if e20 != ok { ret e20 }
        if e21 != ok { ret e21 }
        if e22 != ok { ret e22 }
        let g = f64(nc)
        let bg = tss - w1
        out[o + 0usize] = abs_f(math.pow64(g - 1.0f64, pf) * w0 - math.pow64(g, pf) * w1) / abs_f(math.pow64(g, pf) * w1 - math.pow64(g + 1.0f64, pf) * w2)
        out[o + 1usize] = (bg / (g - 1.0f64)) / (w1 / (nn - g))
        out[o + 2usize] = (w1 / w2 - 1.0f64) * (nn - (g - 1.0f64) - 1.0f64)
        out[o + 17usize] = w1 / g
        fx_cent(x, n, p, cl1, nc, cen, cnt)
        // Ratkowsky
        var rs = 0.0f64
        var j = 0usize
        while j < p {
            var mj = 0.0f64
            i = 0usize
            while i < n {
                mj += x[i * p + j]
                i += 1usize
            }
            mj = mj / nn
            var tj = 0.0f64
            var wj = 0.0f64
            i = 0usize
            while i < n {
                let t = x[i * p + j] - mj
                tj += t * t
                let u = x[i * p + j] - cen[(cl1[i] - 1usize) * p + j]
                wj += u * u
                i += 1usize
            }
            rs += math.sqrt[f64]((tj - wj) / tj)
            j += 1usize
        }
        out[o + 16usize] = (rs / f64(p)) / math.sqrt[f64](g)
        // traces: W = P - sum_k n_k m_k m_k'
        r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                var s = pm[r * p + c]
                var q = 0usize
                while q < nc {
                    s -= cnt[q] * cen[q * p + r] * cen[q * p + c]
                    q += 1usize
                }
                wm[r * p + c] = s
                c += 1usize
            }
            r += 1usize
        }
        var trw = 0.0f64
        r = 0usize
        while r < p {
            trw += wm[r * p + r]
            r += 1usize
        }
        i = 0usize
        while i < p * p {
            wc[i] = wm[i]
            i += 1usize
        }
        let (detw, e23) = fx_det(a, wm, p)
        if e23 != ok { ret e23 }
        i = 0usize
        while i < p * p {
            wc[i] = wm[i]
            i += 1usize
        }
        let (dw2, e24) = fx_det_inv_diag(a, wc, p, idg)
        if e24 != ok { ret e24 }
        var fr = 0.0f64
        r = 0usize
        while r < p {
            var bd = pm[r * p + r] - wm[r * p + r]
            fr += idg[r] * bd
            r += 1usize
        }
        var tc = 0.0f64
        var c2 = 0usize
        while c2 < p {
            var mu = 0.0f64
            r = 0usize
            while r < p {
                mu += wm[r * p + c2]
                r += 1usize
            }
            mu = mu / f64(p)
            var s2 = 0.0f64
            r = 0usize
            while r < p {
                let t = wm[r * p + c2] - mu
                s2 += t * t
                r += 1usize
            }
            tc += s2 / f64(p - 1usize)
            c2 += 1usize
        }
        out[o + 4usize] = nn * math.log[f64](detp / detw)
        out[o + 5usize] = g * g * detw
        out[o + 6usize] = tc
        out[o + 7usize] = trw
        out[o + 8usize] = fr
        out[o + 9usize] = trp / trw
        // ccc
        let r2 = 1.0f64 - trw / trp
        var cc = math.pow64(vv / g, 1.0f64 / f64(p))
        var k1 = 0usize
        i = 0usize
        while i < p {
            uu[i] = ssv[i] / cc
            if uu[i] >= 1.0f64 { k1 += 1usize }
            i += 1usize
        }
        var p1 = k1
        if nc - 1usize < p1 { p1 = nc - 1usize }
        var e_r2 = 0.0f64
        var cccv = 0.0f64
        if p1 > 0usize && p1 < p {
            var v1 = 1.0f64
            i = 0usize
            while i < p1 {
                v1 = v1 * ssv[i]
                i += 1usize
            }
            cc = math.pow64(v1 / g, 1.0f64 / f64(p1))
            var su2 = 0.0f64
            var b1 = 0.0f64
            var b2 = 0.0f64
            i = 0usize
            while i < p {
                uu[i] = ssv[i] / cc
                su2 += uu[i] * uu[i]
                if i < p1 { b1 += 1.0f64 / (nn + uu[i]) } else { b2 += uu[i] * uu[i] / (nn + uu[i]) }
                i += 1usize
            }
            e_r2 = 1.0f64 - ((b1 + b2) / su2) * ((nn - g) * (nn - g) / nn) * (1.0f64 + 4.0f64 / nn)
            cccv = math.log[f64]((1.0f64 - e_r2) / (1.0f64 - r2)) * (math.sqrt[f64](nn * f64(p1) / 2.0f64) / math.pow64(0.001f64 + e_r2, 1.2f64))
        } else {
            var su2 = 0.0f64
            var b1 = 0.0f64
            i = 0usize
            while i < p {
                su2 += uu[i] * uu[i]
                b1 += 1.0f64 / (nn + uu[i])
                i += 1usize
            }
            e_r2 = 1.0f64 - (b1 / su2) * ((nn - g) * (nn - g) / nn) * (1.0f64 + 4.0f64 / nn)
            cccv = math.log[f64]((1.0f64 - e_r2) / (1.0f64 - r2)) * (math.sqrt[f64](nn * f64(p) / 2.0f64) / math.pow64(0.001f64 + e_r2, 1.2f64))
        }
        out[o + 3usize] = cccv
        // duda, pseudot2, beale with their critical values
        var g1 = 1usize
        var cnt1 = 0usize
        var cnt2 = 0usize
        var more = true
        while more {
            cnt1 = 0usize
            cnt2 = 0usize
            i = 0usize
            while i < n {
                if cl1[i] == g1 { cnt1 += 1usize }
                if cl2[i] == g1 { cnt2 += 1usize }
                i += 1usize
            }
            if cnt1 == cnt2 && g1 <= nc { g1 += 1usize } else { more = false }
        }
        var g2 = nc + 1usize
        var h2 = nc
        more = true
        while more {
            cnt1 = 0usize
            cnt2 = 0usize
            i = 0usize
            while i < n {
                if cl1[i] == h2 { cnt1 += 1usize }
                if cl2[i] == g2 { cnt2 += 1usize }
                i += 1usize
            }
            if cnt1 == cnt2 && h2 >= 1usize {
                g2 -= 1usize
                h2 -= 1usize
            } else { more = false }
        }
        let nk = fx_count(cl2, n, g1)
        let nl = fx_count(cl2, n, g2)
        let nm = fx_count(cl1, n, g1)
        let wk = fx_wss_sub(x, n, p, cl2, g1)
        let wl = fx_wss_sub(x, n, p, cl2, g2)
        let wmm = fx_wss_sub(x, n, p, cl1, g1)
        let pp = f64(p)
        let bkl = wmm - wk - wl
        let beale = (bkl / (wk + wl)) / (((nm - 1.0f64) / (nm - 2.0f64)) * (math.pow64(2.0f64, 2.0f64 / pp) - 1.0f64))
        let zzz = 3.2f64 * math.sqrt[f64](2.0f64 * (1.0f64 - 8.0f64 / (3.141592653589793f64 * 3.141592653589793f64 * pp)) / (nm * pp))
        let crit = 1.0f64 - (2.0f64 / (3.141592653589793f64 * pp)) - zzz
        out[o + 13usize] = (wk + wl) / wmm
        out[o + 14usize] = bkl / ((wk + wl) / (nk + nl - 2.0f64))
        out[o + 15usize] = beale
        let (gp1, sd1, e38) = fx_gap_one(a, x, xnew, &tr2, n, p, cl1, nc)
        if e38 != ok { ret e38 }
        let (gp2, sd2, e39) = fx_gap_one(a, x, xnew, &tr2, n, p, cl2, nc + 1usize)
        if e39 != ok { ret e39 }
        out[o + 19usize] = gp1
        out[ocr + row * 4usize + 3usize] = gp1 - (gp2 - sd2)
        out[ocr + row * 4usize] = crit
        out[ocr + row * 4usize + 1usize] = ((1.0f64 - crit) / crit) * (nk + nl - 2.0f64)
        out[ocr + row * 4usize + 2usize] = nbeta.pf(beale, pp, (nm - 2.0f64) * pp, false, false)
        // distance based: within and between sets for cl1 and cl2
        var sw1 = 0.0f64
        var sb1 = 0.0f64
        var nw1 = 0.0f64
        var nb1 = 0.0f64
        var sw2 = 0.0f64
        var sb2 = 0.0f64
        var nw2 = 0.0f64
        var nb2 = 0.0f64
        i = 1usize
        while i < n {
            j = 0usize
            while j < i {
                let dd = md[i * n + j]
                if cl1[i] == cl1[j] {
                    sw1 += dd
                    nw1 += 1.0f64
                } else {
                    sb1 += dd
                    nb1 += 1.0f64
                }
                if cl2[i] == cl2[j] {
                    sw2 += dd
                    nw2 += 1.0f64
                } else {
                    sb2 += dd
                    nb2 += 1.0f64
                }
                j += 1usize
            }
            i += 1usize
        }
        out[o + 20usize] = (sb2 / nb2 - sb1 / nb1) / (sw2 / nw2 - sw1 / nw1)
        out[o + 21usize] = ((sw1 / nw1) / nw1) / ((sb1 / nb1) / nb1)
        // point-biserial: x = distances, y = 1 when between
        let pairs = nw1 + nb1
        let mean_all = (sw1 + sb1) / pairs
        var ssd = 0.0f64
        i = 1usize
        while i < n {
            j = 0usize
            while j < i {
                let t = md[i * n + j] - mean_all
                ssd += t * t
                j += 1usize
            }
            i += 1usize
        }
        let sdx = math.sqrt[f64](ssd / (pairs - 1.0f64))
        let prob = nb1 / pairs
        out[o + 18usize] = (sb1 / nb1 - sw1 / nw1) * math.sqrt[f64](prob * (1.0f64 - prob)) / sdx
        // gamma, gplus, tau
        var splus = 0.0f64
        var smin = 0.0f64
        var i1 = 1usize
        while i1 < n {
            var j1 = 0usize
            while j1 < i1 {
                if cl1[i1] == cl1[j1] {
                    let wv = md[i1 * n + j1]
                    var i2 = 1usize
                    while i2 < n {
                        var j2 = 0usize
                        while j2 < i2 {
                            if cl1[i2] != cl1[j2] {
                                let bv = md[i2 * n + j2]
                                if bv > wv { splus += 1.0f64 }
                                if bv < wv { smin += 1.0f64 }
                            }
                            j2 += 1usize
                        }
                        i2 += 1usize
                    }
                }
                j1 += 1usize
            }
            i1 += 1usize
        }
        let mm = nn * (nn - 1.0f64) / 2.0f64
        let ttau = nw1 * nb1 - (splus + smin)
        out[o + 22usize] = (splus - smin) / (splus + smin)
        out[o + 23usize] = (2.0f64 * smin) / (nn * (nn - 1.0f64))
        out[o + 24usize] = (splus - smin) / math.sqrt[f64]((mm - ttau) * mm)
        // cindex, dunn
        var du = 0.0f64
        var rr = 0.0f64
        var vmax = 1.0f64
        var vmin = 1.0f64
        var first = true
        var kk = 1usize
        while kk <= nc {
            var sz = 0usize
            i = 0usize
            while i < n {
                if cl1[i] == kk { sz += 1usize }
                i += 1usize
            }
            var vmx = 1.0f64
            var vmn = 1.0f64
            if sz > 1usize {
                var tsum = 0.0f64
                var zeros = 0usize
                var tmax = 0.0f64
                var tmin = 1.0e300f64
                i = 0usize
                while i < n {
                    if cl1[i] == kk {
                        j = 0usize
                        while j < n {
                            if cl1[j] == kk {
                                let v = md[i * n + j]
                                tsum += v
                                if v == 0.0f64 { zeros += 1usize }
                                if v > tmax { tmax = v }
                                if v != 0.0f64 && v < tmin { tmin = v }
                            }
                            j += 1usize
                        }
                    }
                    i += 1usize
                }
                du += tsum / 2.0f64
                vmx = tmax
                if zeros == sz { vmn = tmin } else { vmn = 0.0f64 }
                rr += f64(sz) * f64(sz - 1usize) / 2.0f64
            }
            if first {
                vmax = vmx
                vmin = vmn
                first = false
            } else {
                if vmx > vmax { vmax = vmx }
                if vmn < vmin { vmin = vmn }
            }
            kk += 1usize
        }
        var cidx = 0.0f64 / 0.0f64
        if vmin != vmax { cidx = (du - rr * vmin) / (vmax * rr - vmin * rr) }
        out[o + 10usize] = cidx
        var inter = 1.0e300f64
        var intra = 0.0f64
        i = 0usize
        while i < n {
            j = 0usize
            while j < n {
                let dd = md[i * n + j]
                if cl1[i] == cl1[j] {
                    if dd > intra { intra = dd }
                } else if cl1[i] < cl1[j] {
                    if dd < inter { inter = dd }
                }
                j += 1usize
            }
            i += 1usize
        }
        out[o + 25usize] = inter / intra
        // silhouette of NbClust (a singleton cluster counts 1)
        var sil = 0.0f64
        kk = 1usize
        while kk <= nc {
            if cnt[kk - 1usize] <= 1.0f64 {
                sil += 1.0f64
            } else {
                i = 0usize
                while i < n {
                    if cl1[i] == kk {
                        var ai = 0.0f64
                        j = 0usize
                        while j < n {
                            if cl1[j] == kk { ai += md[i * n + j] }
                            j += 1usize
                        }
                        ai = ai / (cnt[kk - 1usize] - 1.0f64)
                        var bi = 1.0e300f64
                        var q = 1usize
                        while q <= nc {
                            if q != kk {
                                var sq = 0.0f64
                                j = 0usize
                                while j < n {
                                    if cl1[j] == q { sq += md[i * n + j] }
                                    j += 1usize
                                }
                                sq = sq / cnt[q - 1usize]
                                if sq < bi { bi = sq }
                            }
                            q += 1usize
                        }
                        var mxv = ai
                        if bi > mxv { mxv = bi }
                        sil += (bi - ai) / mxv
                    }
                    i += 1usize
                }
            }
            kk += 1usize
        }
        out[o + 12usize] = sil / nn
        // Davies-Bouldin with centroids
        let (sdb, e25) = fx_zf(a, nc)
        if e25 != ok { ret e25 }
        i = 0usize
        while i < n {
            let u = cl1[i] - 1usize
            var s = 0.0f64
            j = 0usize
            while j < p {
                let t = x[i * p + j] - cen[u * p + j]
                s += t * t
                j += 1usize
            }
            sdb[u] += s
            i += 1usize
        }
        kk = 0usize
        while kk < nc {
            if cnt[kk] > 1.0f64 { sdb[kk] = math.sqrt[f64](sdb[kk] / cnt[kk]) } else { sdb[kk] = 0.0f64 }
            kk += 1usize
        }
        var rsum = 0.0f64
        var rcnt = 0.0f64
        kk = 0usize
        while kk < nc {
            var rmax = 0.0f64 - 1.0e300f64
            var fnd = false
            var q = 0usize
            while q < nc {
                var s = 0.0f64
                j = 0usize
                while j < p {
                    let t = cen[kk * p + j] - cen[q * p + j]
                    s += t * t
                    j += 1usize
                }
                let rv = (sdb[kk] + sdb[q]) / math.sqrt[f64](s)
                if rv == rv && rv < 1.0e300f64 && rv > 0.0f64 - 1.0e300f64 {
                    fnd = true
                    if rv > rmax { rmax = rv }
                }
                q += 1usize
            }
            if fnd {
                rsum += rmax
                rcnt += 1.0f64
            }
            kk += 1usize
        }
        out[o + 11usize] = rsum / rcnt
        // Hubert
        let (qm, e26) = fx_zf(a, n * n)
        if e26 != ok { ret e26 }
        var meanp = 0.0f64
        var meanq = 0.0f64
        i = 0usize
        while i < n {
            j = 0usize
            while j < n {
                var s = 0.0f64
                var q = 0usize
                while q < p {
                    let t = cen[(cl1[i] - 1usize) * p + q] - cen[(cl1[j] - 1usize) * p + q]
                    s += t * t
                    q += 1usize
                }
                qm[i * n + j] = math.sqrt[f64](s)
                meanp += md[i * n + j]
                meanq += qm[i * n + j]
                j += 1usize
            }
            i += 1usize
        }
        meanp = meanp / (nn * nn)
        meanq = meanq / (nn * nn)
        var vp2 = 0.0f64
        var vq2 = 0.0f64
        j = 0usize
        while j < n {
            var mp = 0.0f64
            var mq = 0.0f64
            i = 0usize
            while i < n {
                mp += md[i * n + j]
                mq += qm[i * n + j]
                i += 1usize
            }
            mp = mp / nn
            mq = mq / nn
            var sp = 0.0f64
            var sq = 0.0f64
            i = 0usize
            while i < n {
                let tp = md[i * n + j] - mp
                let tq = qm[i * n + j] - mq
                sp += tp * tp
                sq += tq * tq
                i += 1usize
            }
            let vp = sp / (nn - 1.0f64) * (nn - 1.0f64) / nn
            let vq = sq / (nn - 1.0f64) * (nn - 1.0f64) / nn
            vp2 += vp * vp
            vq2 += vq * vq
            j += 1usize
        }
        var sh = 0.0f64
        i = 0usize
        while i + 1usize < n {
            j = i + 1usize
            while j < n {
                sh += (md[i * n + j] - meanp) * (qm[i * n + j] - meanq)
                j += 1usize
            }
            i += 1usize
        }
        out[o + 26usize] = sh / (mm * math.sqrt[f64](vp2) * math.sqrt[f64](vq2))
        // scattering based: SDindex, Dindex, SDbw
        let (scat, stdev, e27) = fx_scatter(a, x, n, p, cl1, nc, cen, cnt)
        if e27 != ok { ret e27 }
        let (dis0, e28) = fx_dis(a, x, n, p, cl1, nc)
        if e28 != ok { ret e28 }
        out[o + 27usize] = alpha * scat + dis0
        let (dens, e29) = fx_zf(a, nc)
        if e29 != ok { ret e29 }
        var dsum = 0.0f64
        i = 0usize
        while i < n {
            let u = cl1[i] - 1usize
            var s = 0.0f64
            j = 0usize
            while j < p {
                let t = x[i * p + j] - cen[u * p + j]
                s += t * t
                j += 1usize
            }
            let dd = math.sqrt[f64](s)
            dsum += dd
            if dd <= stdev { dens[u] += 1.0f64 }
            i += 1usize
        }
        out[o + 28usize] = dsum / nn
        var sbw = 0.0f64
        var u = 0usize
        while u < nc {
            var v = 0usize
            while v < nc {
                if v != u {
                    var bwc = 0.0f64
                    i = 0usize
                    while i < n {
                        if cl1[i] == u + 1usize || cl1[i] == v + 1usize {
                            var s = 0.0f64
                            j = 0usize
                            while j < p {
                                let mo = (cen[u * p + j] + cen[v * p + j]) / 2.0f64
                                let t = x[i * p + j] - mo
                                s += t * t
                                j += 1usize
                            }
                            if math.sqrt[f64](s) <= stdev { bwc += 1.0f64 }
                        }
                        i += 1usize
                    }
                    var dm = dens[u]
                    if dens[v] > dm { dm = dens[v] }
                    if dm != 0.0f64 { sbw += bwc / dm }
                }
                v += 1usize
            }
            u += 1usize
        }
        out[o + 29usize] = scat + sbw / (g * (g - 1.0f64))
        row += 1usize
    }
    // the simple selection rules
    let ob = rows * 30usize
    var col = 0usize
    while col < 30usize {
        var kind = 0usize
        if col == 0usize || col == 1usize || col == 3usize || col == 16usize || col == 25usize || col == 12usize || col == 18usize || col == 22usize || col == 24usize { kind = 1usize }
        if col == 11usize || col == 21usize || col == 23usize || col == 10usize || col == 27usize || col == 29usize { kind = 2usize }
        if kind != 0usize {
            var bi = 0usize
            var bv = out[col]
            row = 1usize
            while row < rows {
                let v = out[row * 30usize + col]
                if kind == 1usize && v > bv {
                    bv = v
                    bi = row
                }
                if kind == 2usize && v < bv {
                    bv = v
                    bi = row
                }
                row += 1usize
            }
            out[ob + col] = f64(minc + bi)
        }
        col += 1usize
    }
    // difference-level rules: Hartigan, Scott, TrCovW, Friedman and Ball take the largest absolute first difference, Marriot and TraceW the largest and Rubin the smallest second difference
    out[ob + 2usize] = fx_pick_diff(out, rows, 2usize, 0usize, minc)
    out[ob + 4usize] = fx_pick_diff(out, rows, 4usize, 0usize, minc)
    out[ob + 5usize] = fx_pick_diff(out, rows, 5usize, 1usize, minc)
    out[ob + 6usize] = fx_pick_diff(out, rows, 6usize, 0usize, minc)
    out[ob + 7usize] = fx_pick_diff(out, rows, 7usize, 1usize, minc)
    out[ob + 8usize] = fx_pick_diff(out, rows, 8usize, 0usize, minc)
    out[ob + 9usize] = fx_pick_diff(out, rows, 9usize, 2usize, minc)
    out[ob + 17usize] = fx_pick_diff(out, rows, 17usize, 0usize, minc)
    // Duda, pseudo-t2 and Beale: the first nc past the critical value (0 when none)
    row = 0usize
    var fd = false
    var fp = false
    var fb = false
    var fg = false
    while row < rows {
        let nc = f64(minc + row)
        if !fg && out[ocr + row * 4usize + 3usize] >= 0.0f64 {
            fg = true
            out[ob + 19usize] = nc
        }
        if !fd && out[row * 30usize + 13usize] >= out[ocr + row * 4usize] {
            fd = true
            out[ob + 13usize] = nc
        }
        if !fp && out[row * 30usize + 14usize] <= out[ocr + row * 4usize + 1usize] {
            fp = true
            out[ob + 14usize] = nc
        }
        if !fb && out[ocr + row * 4usize + 2usize] >= 0.1f64 {
            fb = true
            out[ob + 15usize] = nc
        }
        row += 1usize
    }
    ret ok
}

// eigenvalues (descending) of m / div for the symmetric p by p m, by cyclic Jacobi rotations
fn fx_eigsym(a: *mem.Arena, m: []const f64, p: usize, div: f64, vals: []f64) -> err {
    let (s, e1) = fx_zf(a, p * p)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < p * p {
        s[i] = m[i] / div
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 100usize {
        var off = 0.0f64
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                if i != j { off += s[i * p + j] * s[i * p + j] }
                j += 1usize
            }
            i += 1usize
        }
        if off < 1.0e-60f64 { break }
        var q = 0usize
        while q + 1usize < p {
            var r = q + 1usize
            while r < p {
                let apq = s[q * p + r]
                if apq != 0.0f64 {
                    let theta = (s[r * p + r] - s[q * p + q]) / (2.0f64 * apq)
                    var t = 1.0f64 / (abs_f(theta) + math.sqrt[f64](theta * theta + 1.0f64))
                    if theta < 0.0f64 { t = 0.0f64 - t }
                    let c = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let sn = t * c
                    var k = 0usize
                    while k < p {
                        let akp = s[k * p + q]
                        let akq = s[k * p + r]
                        s[k * p + q] = c * akp - sn * akq
                        s[k * p + r] = sn * akp + c * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let apk = s[q * p + k]
                        let aqk = s[r * p + k]
                        s[q * p + k] = c * apk - sn * aqk
                        s[r * p + k] = sn * apk + c * aqk
                        k += 1usize
                    }
                }
                r += 1usize
            }
            q += 1usize
        }
        sweep += 1usize
    }
    i = 0usize
    while i < p {
        vals[i] = s[i * p + i]
        i += 1usize
    }
    // descending
    i = 1usize
    while i < p {
        let cur = vals[i]
        var j = i
        while j > 0usize && vals[j - 1usize] < cur {
            vals[j] = vals[j - 1usize]
            j -= 1usize
        }
        vals[j] = cur
        i += 1usize
    }
    ret ok
}

// mode 0: largest |res[r] - res[r-1]|, 1: largest and 2: smallest (res[r+1] - res[r]) - (res[r] - res[r-1]); rows without both neighbours are NA and skipped; the first best row wins
fn fx_pick_diff(out: []const f64, rows: usize, col: usize, mode: usize, minc: usize) -> f64 {
    var best = 0.0f64
    var bi = 0usize
    var have = false
    var r = 0usize
    while r < rows {
        var ok2 = false
        var dv = 0.0f64
        if mode == 0usize && r >= 1usize {
            dv = abs_f(out[r * 30usize + col] - out[(r - 1usize) * 30usize + col])
            ok2 = true
        }
        if mode != 0usize && r >= 1usize && r + 1usize < rows {
            dv = (out[(r + 1usize) * 30usize + col] - out[r * 30usize + col]) - (out[r * 30usize + col] - out[(r - 1usize) * 30usize + col])
            ok2 = true
        }
        if ok2 && dv == dv {
            if !have {
                have = true
                best = dv
                bi = r
            } else if mode != 2usize && dv > best {
                best = dv
                bi = r
            } else if mode == 2usize && dv < best {
                best = dv
                bi = r
            }
        }
        r += 1usize
    }
    ret f64(minc + bi)
}

// sum(diag(var(rows of cluster g))): a one-row cluster reaches var as a vector, and diag of that scalar is an identity matrix of size as.integer(var), so its trace is floor(var)
fn fx_trace_var(x: []const f64, n: usize, p: usize, cl: []const usize, g: usize) -> f64 {
    let cnt = fx_count(cl, n, g)
    var s = 0.0f64
    if cnt == 1.0f64 {
        var i = 0usize
        while cl[i] != g { i += 1usize }
        var m = 0.0f64
        var j = 0usize
        while j < p {
            m += x[i * p + j]
            j += 1usize
        }
        m = m / f64(p)
        j = 0usize
        while j < p {
            s += (x[i * p + j] - m) * (x[i * p + j] - m)
            j += 1usize
        }
        let v = s / f64(p - 1usize)
        ret f64(i64(v))
    }
    var j = 0usize
    while j < p {
        var sm = 0.0f64
        var i = 0usize
        while i < n {
            if cl[i] == g { sm += x[i * p + j] }
            i += 1usize
        }
        let mu = sm / cnt
        i = 0usize
        while i < n {
            if cl[i] == g { s += (x[i * p + j] - mu) * (x[i * p + j] - mu) / (cnt - 1.0f64) }
            i += 1usize
        }
        j += 1usize
    }
    ret s
}

// Indice.Gap's GAP for the partition cl of x into k clusters, B = 10 reference sets (all equal to xnew), clustered by the tree tr2 of xnew: (Sgap, Sdgap)
fn fx_gap_one(a: *mem.Arena, x: []const f64, xnew: []const f64, tr2: *const hcl.Tree, n: usize, p: usize, cl: []const usize, k: usize) -> (f64, f64, err) {
    let (pp2, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    let e2 = hcl.cutree(a, tr2, n, k, pp2)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    var wk0 = 0.0f64
    var w1 = 0.0f64
    var w2 = 0.0f64
    let den = f64(n - k)
    var z = 1usize
    while z <= k {
        let l1 = fx_count(cl, n, z)
        let l2 = fx_count(pp2, n, z)
        wk0 += fx_trace_var(x, n, p, cl, z) * (l1 - 1.0f64) / den
        let t2 = fx_trace_var(xnew, n, p, pp2, z)
        w1 += t2 * (l2 - 1.0f64) / den
        w2 += t2 * l2 / den
        z += 1usize
    }
    let la = math.log[f64](w1)
    let lb = math.log[f64](w2)
    let mean = (la + 9.0f64 * lb) / 10.0f64
    let v = ((la - mean) * (la - mean) + 9.0f64 * (lb - mean) * (lb - mean)) / 9.0f64
    let sdg = math.sqrt[f64](1.0f64 + 1.0f64 / 10.0f64) * math.sqrt[f64](v) * math.sqrt[f64](9.0f64 / 10.0f64)
    ret (mean - math.log[f64](wk0), sdg, ok)
}

fn fx_count(cl: []const usize, n: usize, g: usize) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < n {
        if cl[i] == g { c += 1.0f64 }
        i += 1usize
    }
    ret c
}

// NbClust's wss of the rows of cluster g. A one-row cluster reaches it as a vector, which as.matrix turns into one column, so the row is centred on its own mean
fn fx_wss_sub(x: []const f64, n: usize, p: usize, cl: []const usize, g: usize) -> f64 {
    let cnt = fx_count(cl, n, g)
    var s = 0.0f64
    if cnt == 1.0f64 {
        var i = 0usize
        while cl[i] != g { i += 1usize }
        var m = 0.0f64
        var j = 0usize
        while j < p {
            m += x[i * p + j]
            j += 1usize
        }
        m = m / f64(p)
        j = 0usize
        while j < p {
            s += (x[i * p + j] - m) * (x[i * p + j] - m)
            j += 1usize
        }
        ret s
    }
    var j = 0usize
    while j < p {
        var sm = 0.0f64
        var i = 0usize
        while i < n {
            if cl[i] == g { sm += x[i * p + j] }
            i += 1usize
        }
        let mu = sm / cnt
        i = 0usize
        while i < n {
            if cl[i] == g { s += (x[i * p + j] - mu) * (x[i * p + j] - mu) }
            i += 1usize
        }
        j += 1usize
    }
    ret s
}

fn abs_f(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}
