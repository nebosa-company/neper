// R fpc: cluster.stats (no noise cluster) from a full distance matrix and a clustering with labels 1..k: the within and between averages,
// diameters, separation, within-cluster sum of squares, the Calinski-Harabasz index, silhouette widths, Dunn indices, entropy, the
// Pearson gamma, G2 and G3, the widest gap, the separation index, and against a second clustering the corrected Rand index and the
// variation of information.
//
// Not here: noise clusters, clusterboot, nselectboot, mergenormals, dbscan, cluster.varstats and the plotting coordinates.

use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.wrs2 as wr
use e.math
use e.mem

error Malformed

fn at(d: []const f64, n: usize, i: usize, j: usize) -> f64 { ret d[i * n + j] }

// kind: 0 average.between 1 average.within 2 max.diameter 3 min.separation 4 within.cluster.ss 5 avg.silwidth 6 g2 7 g3 8 pearsongamma
// 9 dunn 10 dunn2 11 entropy 12 wb.ratio 13 ch 14 widestgap 15 sindex (sepprob 0.1)
fn stat(a: *mem.Arena, d: []const f64, n: usize, cl: []const usize, k: usize, kind: usize) -> f64 {
    let (size, e1) = mem.alloc[f64](a, k)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (diam, e2) = mem.alloc[f64](a, k)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (avgd, e3) = mem.alloc[f64](a, k)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let (sep, e4) = mem.alloc[f64](a, k)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    let (btw, e5) = mem.alloc[f64](a, k * k)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    let (nbt, e6) = mem.alloc[f64](a, k * k)
    if e6 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < k {
        size[i] = 0.0f64
        diam[i] = 0.0f64
        avgd[i] = 0.0f64
        sep[i] = 1.0e300f64
        i += 1usize
    }
    i = 0usize
    while i < k * k {
        btw[i] = 0.0f64
        nbt[i] = 0.0f64
        i += 1usize
    }
    var nw = 0.0f64
    var nb = 0.0f64
    var sw = 0.0f64
    var sb = 0.0f64
    var ss_within = 0.0f64
    let (wsum, e7) = mem.alloc[f64](a, k)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    let (wcnt, e8) = mem.alloc[f64](a, k)
    if e8 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < k {
        wsum[i] = 0.0f64
        wcnt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        size[cl[i] - 1usize] += 1.0f64
        i += 1usize
    }
    var tot2 = 0.0f64
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let v = at(d, n, i, j)
            tot2 += v * v
            let ci = cl[i] - 1usize
            let cj = cl[j] - 1usize
            if ci == cj {
                nw += 1.0f64
                sw += v
                wsum[ci] += v
                wcnt[ci] += 1.0f64
                ss_within += v * v / size[ci]
                if v > diam[ci] { diam[ci] = v }
            } else {
                nb += 1.0f64
                sb += v
                btw[ci * k + cj] += v
                btw[cj * k + ci] += v
                nbt[ci * k + cj] += 1.0f64
                nbt[cj * k + ci] += 1.0f64
                if v < sep[ci] { sep[ci] = v }
                if v < sep[cj] { sep[cj] = v }
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    var wavg_num = 0.0f64
    var wavg_den = 0.0f64
    var maxdiam = 0.0f64
    var maxavg = 0.0f64
    var minsep = 1.0e300f64
    var mindiff = 1.0e300f64
    while i < k {
        if wcnt[i] > 0.0f64 {
            avgd[i] = wsum[i] / wcnt[i]
            wavg_num += avgd[i] * size[i]
            wavg_den += size[i]
            if avgd[i] > maxavg { maxavg = avgd[i] }
        }
        if diam[i] > maxdiam { maxdiam = diam[i] }
        if sep[i] < minsep { minsep = sep[i] }
        i += 1usize
    }
    let ave_between = sb / nb
    let ave_within = wavg_num / wavg_den
    if kind == 0usize { ret ave_between }
    if kind == 1usize { ret ave_within }
    if kind == 2usize { ret maxdiam }
    if kind == 3usize { ret minsep }
    if kind == 4usize { ret ss_within }
    if kind == 12usize { ret ave_within / ave_between }
    if kind == 13usize {
        let tot_ss = tot2 / f64(n)
        ret (tot_ss - ss_within) * (f64(n) - f64(k)) / (ss_within * (f64(k) - 1.0f64))
    }
    if kind == 9usize {
        var mnsep = 1.0e300f64
        i = 0usize
        while i < k {
            if sep[i] < mnsep { mnsep = sep[i] }
            i += 1usize
        }
        ret mnsep / maxdiam
    }
    if kind == 10usize {
        var j = 0usize
        i = 0usize
        while i < k {
            j = i + 1usize
            while j < k {
                let m = btw[i * k + j] / nbt[i * k + j]
                if m < mindiff { mindiff = m }
                j += 1usize
            }
            i += 1usize
        }
        ret mindiff / maxavg
    }
    if kind == 11usize {
        var h = 0.0f64
        i = 0usize
        while i < k {
            let p = size[i] / f64(n)
            if p > 0.0f64 { h -= p * math.log[f64](p) }
            i += 1usize
        }
        ret h
    }
    if kind == 5usize {
        var sum = 0.0f64
        i = 0usize
        while i < n {
            let ci = cl[i] - 1usize
            var s = 0.0f64
            if size[ci] > 1.0f64 {
                var ai = 0.0f64
                var j = 0usize
                while j < n {
                    if j != i && cl[j] - 1usize == ci { ai += at(d, n, i, j) }
                    j += 1usize
                }
                ai = ai / (size[ci] - 1.0f64)
                var bi = 1.0e300f64
                var c2 = 0usize
                while c2 < k {
                    if c2 != ci {
                        var sm = 0.0f64
                        j = 0usize
                        while j < n {
                            if cl[j] - 1usize == c2 { sm += at(d, n, i, j) }
                            j += 1usize
                        }
                        let m = sm / size[c2]
                        if m < bi { bi = m }
                    }
                    c2 += 1usize
                }
                var mxab = ai
                if bi > mxab { mxab = bi }
                s = (bi - ai) / mxab
            }
            sum += s
            i += 1usize
        }
        ret sum / f64(n)
    }
    if kind == 8usize {
        // the Pearson correlation of the distances (within first, then between) with the 0/1 indicator
        let nt = nw + nb
        let sx = sw + sb
        var sxx = 0.0f64
        i = 0usize
        while i < n {
            var j = i + 1usize
            while j < n {
                sxx += at(d, n, i, j) * at(d, n, i, j)
                j += 1usize
            }
            i += 1usize
        }
        let cov = sb - sx * nb / nt
        let vx = sxx - sx * sx / nt
        let vy = nb - nb * nb / nt
        ret cov / math.sqrt[f64](vx * vy)
    }
    if kind == 6usize || kind == 7usize {
        var splus = 0.0f64
        var sminus = 0.0f64
        var sdw = 0.0f64
        i = 0usize
        while i < n {
            var j = i + 1usize
            while j < n {
                if cl[i] == cl[j] {
                    let w = at(d, n, i, j)
                    var p = 0usize
                    while p < n {
                        var q = p + 1usize
                        while q < n {
                            if cl[p] != cl[q] {
                                let b = at(d, n, p, q)
                                if w < b { splus += 1.0f64 }
                                if w > b { sminus += 1.0f64 }
                            }
                            q += 1usize
                        }
                        p += 1usize
                    }
                    sdw += w
                }
                j += 1usize
            }
            i += 1usize
        }
        if kind == 6usize { ret (splus - sminus) / (splus + sminus) }
        // g3: the sum of the nw smallest and the nw largest of all distances
        let tn = usize(nw + nb)
        let (all, e9) = mem.alloc[f64](a, tn)
        if e9 != ok { ret 0.0f64 / 0.0f64 }
        var c = 0usize
        i = 0usize
        while i < n {
            var j = i + 1usize
            while j < n {
                all[c] = at(d, n, i, j)
                c += 1usize
                j += 1usize
            }
            i += 1usize
        }
        i = 1usize
        while i < tn {
            let t = all[i]
            var j = i
            while j > 0usize && all[j - 1usize] > t {
                all[j] = all[j - 1usize]
                j -= 1usize
            }
            all[j] = t
            i += 1usize
        }
        var dmin = 0.0f64
        var dmax = 0.0f64
        let nwi = usize(nw)
        i = 0usize
        while i < nwi {
            dmin += all[i]
            dmax += all[tn - 1usize - i]
            i += 1usize
        }
        ret (sdw - dmin) / (dmax - dmin)
    }
    if kind == 14usize {
        // the largest single-linkage height inside any cluster: the longest edge of its minimum spanning tree
        var worst = 0.0f64
        var c = 0usize
        while c < k {
            let (inn, e10) = mem.alloc[bool](a, n)
            if e10 != ok { ret 0.0f64 / 0.0f64 }
            let (best, e11) = mem.alloc[f64](a, n)
            if e11 != ok { ret 0.0f64 / 0.0f64 }
            var start = n
            i = 0usize
            while i < n {
                inn[i] = false
                best[i] = 1.0e300f64
                if cl[i] - 1usize == c && start == n { start = i }
                i += 1usize
            }
            if start < n && size[c] > 1.0f64 {
                var cur = start
                var added = 1usize
                inn[cur] = true
                while added < usize(size[c]) {
                    var j = 0usize
                    while j < n {
                        if cl[j] - 1usize == c && !inn[j] {
                            let v = at(d, n, cur, j)
                            if v < best[j] { best[j] = v }
                        }
                        j += 1usize
                    }
                    var pick = n
                    var pv = 1.0e300f64
                    j = 0usize
                    while j < n {
                        if cl[j] - 1usize == c && !inn[j] && best[j] < pv {
                            pv = best[j]
                            pick = j
                        }
                        j += 1usize
                    }
                    if pv > worst { worst = pv }
                    inn[pick] = true
                    cur = pick
                    added += 1usize
                }
            }
            c += 1usize
        }
        ret worst
    }
    // kind 15: the mean of the floor(0.1 n) smallest distances from a point to the nearest point of another cluster
    let (ps, e12) = mem.alloc[f64](a, n)
    if e12 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < n {
        var m = 1.0e300f64
        var j = 0usize
        while j < n {
            if cl[j] != cl[i] && at(d, n, i, j) < m { m = at(d, n, i, j) }
            j += 1usize
        }
        ps[i] = m
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = ps[i]
        var j = i
        while j > 0usize && ps[j - 1usize] > t {
            ps[j] = ps[j - 1usize]
            j -= 1usize
        }
        ps[j] = t
        i += 1usize
    }
    let mcount = usize(math.floor[f64](f64(n) * 0.1f64))
    var sm = 0.0f64
    i = 0usize
    while i < mcount {
        sm += ps[i]
        i += 1usize
    }
    ret sm / f64(mcount)
}

fn choose2(v: f64) -> f64 {
    if v >= 2.0f64 { ret v * (v - 1.0f64) / 2.0f64 }
    ret 0.0f64
}

// kind 16 corrected.rand, 17 vi, for two clusterings with labels 1..k1 and 1..k2
fn compare(a: *mem.Arena, c1: []const usize, k1: usize, c2: []const usize, k2: usize, kind: usize) -> f64 {
    let n = c1.len
    let nf = f64(n)
    let (tab, e) = mem.alloc[f64](a, k1 * k2)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let (r, e2) = mem.alloc[f64](a, k1)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (c, e3) = mem.alloc[f64](a, k2)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < k1 * k2 {
        tab[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k1 {
        r[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k2 {
        c[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        tab[(c1[i] - 1usize) * k2 + (c2[i] - 1usize)] += 1.0f64
        r[c1[i] - 1usize] += 1.0f64
        c[c2[i] - 1usize] += 1.0f64
        i += 1usize
    }
    if kind == 16usize {
        var dsum = 0.0f64
        i = 0usize
        while i < k1 * k2 {
            dsum += choose2(tab[i])
            i += 1usize
        }
        var s1 = 0.0f64
        i = 0usize
        while i < k1 {
            s1 += choose2(r[i])
            i += 1usize
        }
        var s2 = 0.0f64
        i = 0usize
        while i < k2 {
            s2 += choose2(c[i])
            i += 1usize
        }
        let cn = choose2(nf)
        ret (dsum - s1 * s2 / cn) / ((s1 + s2) / 2.0f64 - s1 * s2 / cn)
    }
    var h1 = 0.0f64
    i = 0usize
    while i < k1 {
        let p = r[i] / nf
        if p > 0.0f64 { h1 -= p * math.log[f64](p) }
        i += 1usize
    }
    var h2 = 0.0f64
    i = 0usize
    while i < k2 {
        let p = c[i] / nf
        if p > 0.0f64 { h2 -= p * math.log[f64](p) }
        i += 1usize
    }
    var icc = 0.0f64
    var a1 = 0usize
    while a1 < k1 {
        var b1 = 0usize
        while b1 < k2 {
            let p12 = tab[a1 * k2 + b1] / nf
            if p12 > 0.0f64 { icc += p12 * math.log[f64](p12 / ((r[a1] / nf) * (c[b1] / nf))) }
            b1 += 1usize
        }
        a1 += 1usize
    }
    ret h1 + h2 - 2.0f64 * icc
}

// ---- discrcoord: fpc's discriminant coordinates. tdecomp(m) is t(V diag(sqrt(lambda))) of the symmetric eigen decomposition of m, with eigenvalues
// below 1e-6 raised to 1e-6, and the eigenvectors in R's order (decreasing eigenvalues; LAPACK gives them ascending).

// the covariance (n - 1 divisor) of the rows of x (n by p row-major) with the labels cl equal to l; k is the count of those rows; out p by p
fn cov_rows(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, l: usize, out: []f64) -> (usize, err) {
    var k = 0usize
    var i = 0usize
    while i < n {
        if cl[i] == l { k += 1usize }
        i += 1usize
    }
    let (mu, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret (k, e1) }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            if cl[i] == l { s += x[i * p + j] }
            i += 1usize
        }
        mu[j] = s / f64(k)
        j += 1usize
    }
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                if cl[i] == l { s += (x[i * p + r] - mu[r]) * (x[i * p + c] - mu[c]) }
                i += 1usize
            }
            out[r * p + c] = s / f64(k - 1usize)
            c += 1usize
        }
        r += 1usize
    }
    ret (k, ok)
}

// tdecomp(m) for the symmetric p by p m (row-major) into out (row-major)
fn tdecomp(a: *mem.Arena, m: []const f64, p: usize, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret e1 }
    let (v, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    let e3 = sy.dsyevr_all(a, m, p, w, v)
    if e3 != ok { ret e3 }
    // R's column i is LAPACK's column p - 1 - i
    var i = 0usize
    while i < p {
        let li = p - 1usize - i
        var wv = w[li]
        if math.abs[f64](wv) < 0.000001f64 { wv = 0.000001f64 }
        let s = math.sqrt[f64](wv)
        var j = 0usize
        while j < p {
            out[i * p + j] = v[li * p + j] * s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// discrcoord(x, cl, pool): the pooled within-group covariance W (pool 0 "n": the sum of (n_i - 1) cov_i; pool 1 "equal": (n - 1) cov_i / K summed),
// T = tdecomp(W), the between-group matrix B = (n - 1) cov(x) - W, the eigen decomposition of Z = t(T^-1) B T^-1 (eigenvalues in R's decreasing order),
// units = T^-1 V sqrt(n - K) and proj = x units. Returns ev (p), units (p by p), proj (n by p) and W (p by p).
fn discrcoord(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, kn: usize, pool: usize, ev: []f64, units: []f64, proj: []f64, wout: []f64) -> err {
    let (w, e0) = mem.alloc[f64](a, p * p)
    let (cc, e1) = mem.alloc[f64](a, p * p)
    if e0 != ok || e1 != ok { ret Malformed }
    var zi = 0usize
    while zi < p * p {
        w[zi] = 0.0f64
        zi += 1usize
    }
    var l = 1usize
    while l <= kn {
        let (kc, ec) = cov_rows(a, x, n, p, cl, l, cc)
        if ec != ok { ret ec }
        var zz = 0usize
        while zz < p * p {
            var coef = f64(kc - 1usize)
            if pool == 1usize { coef = f64(n - 1usize) / f64(kn) }
            if kc < 2usize { cc[zz] = 0.0f64 }
            w[zz] += coef * cc[zz]
            zz += 1usize
        }
        l += 1usize
    }
    var z = 0usize
    while z < p * p {
        wout[z] = w[z]
        z += 1usize
    }
    let (tm, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    let e3 = tdecomp(a, w, p, tm)
    if e3 != ok { ret e3 }
    let (tinv, e4) = mem.alloc[f64](a, p * p)
    if e4 != ok { ret e4 }
    let e5 = wr.invert_small(a, tm, p, tinv)
    if e5 != ok { ret e5 }
    // the total covariance of x: all rows as one label
    let (ones, e6) = mem.alloc[usize](a, n)
    if e6 != ok { ret e6 }
    var i = 0usize
    while i < n {
        ones[i] = 1usize
        i += 1usize
    }
    let (ct, e7) = mem.alloc[f64](a, p * p)
    if e7 != ok { ret e7 }
    let (_, e8) = cov_rows(a, x, n, p, ones, 1usize, ct)
    if e8 != ok { ret e8 }
    // B = (n - 1) ct - W; Z = tinv' B tinv
    let (bm, e9) = mem.alloc[f64](a, p * p)
    if e9 != ok { ret e9 }
    z = 0usize
    while z < p * p {
        bm[z] = f64(n - 1usize) * ct[z] - w[z]
        z += 1usize
    }
    let (tb, e10) = mem.alloc[f64](a, p * p)
    let (zm, e11) = mem.alloc[f64](a, p * p)
    if e10 != ok || e11 != ok { ret Malformed }
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += bm[r * p + q] * tinv[q * p + c]
                q += 1usize
            }
            tb[r * p + c] = s
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += tinv[q * p + r] * tb[q * p + c]
                q += 1usize
            }
            zm[r * p + c] = s
            c += 1usize
        }
        r += 1usize
    }
    let (wv, e12) = mem.alloc[f64](a, p)
    let (vv, e13) = mem.alloc[f64](a, p * p)
    if e12 != ok || e13 != ok { ret Malformed }
    let e14 = sy.dsyevr_all(a, zm, p, wv, vv)
    if e14 != ok { ret e14 }
    // R's order: column k of the eigenvectors is LAPACK's column p - 1 - k; the values decrease
    var kk = 0usize
    while kk < p {
        ev[kk] = wv[p - 1usize - kk]
        kk += 1usize
    }
    // units = tinv V sqrt(n - K), V in R's order
    let scale = math.sqrt[f64](f64(n - kn))
    r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += tinv[r * p + q] * vv[(p - 1usize - c) * p + q]
                q += 1usize
            }
            units[r * p + c] = s * scale
            c += 1usize
        }
        r += 1usize
    }
    // proj = x units
    i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += x[i * p + q] * units[q * p + c]
                q += 1usize
            }
            proj[i * p + c] = s
            c += 1usize
        }
        i += 1usize
    }
    ret ok
}
