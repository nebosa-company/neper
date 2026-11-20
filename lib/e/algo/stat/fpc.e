// R fpc: cluster.stats (with its noise-cluster option) from a full distance matrix and a clustering with labels 1..k: the within and between averages,
// diameters, separation, within-cluster sum of squares, the Calinski-Harabasz index, silhouette widths, Dunn indices, entropy, the
// Pearson gamma, G2 and G3, the widest gap, the separation index, and against a second clustering the corrected Rand index and the
// variation of information.
//
// Not here: the plot coordinates batcoord and batvarcoord (they need LAPACK dgeev).

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
// R's cov (cov.c) sums in long double: the mean is refined by a second pass and every sum of products is carried in 64 bits, then rounded to double.
// A double-double carries at least as many bits, so rounding it to double agrees with R's long double result except where the two differ by under
// 2^-64 relative and a double rounding falls between them.
fn dd_two_sum(x: f64, y: f64) -> (f64, f64) {
    let s = x + y
    let bb = s - x
    let e = (x - (s - bb)) + (y - bb)
    ret (s, e)
}

fn dd_norm(h: f64, l: f64) -> (f64, f64) {
    let s = h + l
    let e = l - (s - h)
    ret (s, e)
}

fn dd_add(h: f64, l: f64, vh: f64, vl: f64) -> (f64, f64) {
    let (s, e) = dd_two_sum(h, vh)
    let (rh, rl) = dd_norm(s, e + (l + vl))
    ret (rh, rl)
}

fn dd_split(x: f64) -> (f64, f64) {
    let t = 134217729.0f64 * x
    let hi = t - (t - x)
    ret (hi, x - hi)
}

fn dd_mul(ah: f64, al: f64, bh: f64, bl: f64) -> (f64, f64) {
    let (a1, a2) = dd_split(ah)
    let (b1, b2) = dd_split(bh)
    let p = ah * bh
    let pe = ((a1 * b1 - p) + a1 * b2 + a2 * b1) + a2 * b2
    let (rh, rl) = dd_norm(p, pe + (ah * bl + al * bh))
    ret (rh, rl)
}

fn dd_div(h: f64, l: f64, d: f64) -> (f64, f64) {
    let q1 = h / d
    let (ah, al) = dd_split(q1)
    let (bh, bl) = dd_split(d)
    let p = q1 * d
    let pe = ((ah * bh - p) + ah * bl + al * bh) + al * bl
    let r = ((h - p) - pe) + l
    let q2 = r / d
    let (rh, rl) = dd_norm(q1, q2)
    ret (rh, rl)
}

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
    let kf = f64(k)
    var j = 0usize
    while j < p {
        var sh = 0.0f64
        var sl = 0.0f64
        i = 0usize
        while i < n {
            if cl[i] == l {
                let (h1, l1) = dd_add(sh, sl, x[i * p + j], 0.0f64)
                sh = h1
                sl = l1
            }
            i += 1usize
        }
        let (th, tl) = dd_div(sh, sl, kf)
        var rh = 0.0f64
        var rl = 0.0f64
        i = 0usize
        while i < n {
            if cl[i] == l {
                let (vh, vl) = dd_add(x[i * p + j], 0.0f64, -th, -tl)
                let (h2, l2) = dd_add(rh, rl, vh, vl)
                rh = h2
                rl = l2
            }
            i += 1usize
        }
        let (qh, ql) = dd_div(rh, rl, kf)
        let (mh, ml) = dd_add(th, tl, qh, ql)
        mu[j] = mh + ml
        j += 1usize
    }
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var sh = 0.0f64
            var sl = 0.0f64
            i = 0usize
            while i < n {
                if cl[i] == l {
                    let (dxh, dxl) = dd_two_sum(x[i * p + r], -mu[r])
                    let (dyh, dyl) = dd_two_sum(x[i * p + c], -mu[c])
                    let (th, tl) = dd_mul(dxh, dxl, dyh, dyl)
                    let (h1, l1) = dd_add(sh, sl, th, tl)
                    sh = h1
                    sl = l1
                }
                i += 1usize
            }
            if k < 2usize {
                out[r * p + c] = 0.0f64 / 0.0f64
            } else {
                let (qh, ql) = dd_div(sh, sl, f64(k - 1usize))
                out[r * p + c] = qh + ql
            }
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
    let e5 = lu_inverse(a, tm, p, tinv)
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
    // Z = (t(Tinv) B) Tinv, the left product first as R evaluates it; LAPACK reads the lower triangle of the column-major matrix, which is the upper
    // triangle of this row-major one, so the other half is made equal to R's lower triangle
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += tinv[q * p + r] * bm[q * p + c]
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
                s += tb[r * p + q] * tinv[q * p + c]
                q += 1usize
            }
            zm[r * p + c] = s
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < p {
        var c = r + 1usize
        while c < p {
            zm[r * p + c] = zm[c * p + r]
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

// ---- dbscan (fpc::dbscan, any of its methods: they give the same answer): the points scanned in order, a point whose neighbourhood count (within eps, among the points not
// yet in a cluster plus those that already counted it) reaches MinPts starting a cluster that grows through the reachable points; cv gets the cluster number (0 noise),
// isseed marks the core points. x is n by p, row-major.
fn dbscan(a: *mem.Arena, x: []const f64, n: usize, p: usize, eps: f64, min_pts: usize, cv: []i64, isseed: []bool) -> err {
    let (classn, e0) = mem.alloc[usize](a, n)
    let (un, e1) = mem.alloc[bool](a, n)
    let (reach, e2) = mem.alloc[usize](a, n)
    let (ap, e3) = mem.alloc[usize](a, n)
    let (jr, e4) = mem.alloc[usize](a, n)
    let (inr, e5) = mem.alloc[bool](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        classn[i] = 0usize
        cv[i] = 0i64
        isseed[i] = false
        i += 1usize
    }
    var cn = 0i64
    i = 0usize
    while i < n {
        // unclass: the points with cv < 1
        var q = 0usize
        var any = false
        while q < n {
            un[q] = cv[q] < 1i64
            if un[q] { any = true }
            q += 1usize
        }
        if cv[i] == 0i64 {
            var nr = 0usize
            q = 0usize
            while q < n {
                if un[q] && dist_xy(x, p, i, q) <= eps {
                    reach[nr] = q
                    nr += 1usize
                }
                q += 1usize
            }
            if nr + classn[i] < min_pts {
                cv[i] = 0i64 - 1i64
            } else {
                cn += 1i64
                cv[i] = cn
                isseed[i] = true
                // reachables without i; unclass without i
                var m = 0usize
                q = 0usize
                while q < nr {
                    if reach[q] != i {
                        reach[m] = reach[q]
                        m += 1usize
                    }
                    q += 1usize
                }
                nr = m
                un[i] = false
                q = 0usize
                while q < nr {
                    classn[reach[q]] += 1usize
                    q += 1usize
                }
                while nr > 0usize {
                    q = 0usize
                    while q < nr {
                        cv[reach[q]] = cn
                        ap[q] = reach[q]
                        q += 1usize
                    }
                    let nap = nr
                    nr = 0usize
                    q = 0usize
                    while q < n {
                        inr[q] = false
                        q += 1usize
                    }
                    var i2 = 0usize
                    while i2 < nap {
                        let j = ap[i2]
                        var njr = 0usize
                        q = 0usize
                        while q < n {
                            if un[q] && dist_xy(x, p, j, q) <= eps {
                                jr[njr] = q
                                njr += 1usize
                            }
                            q += 1usize
                        }
                        if njr + classn[j] >= min_pts {
                            isseed[j] = true
                            var t = 0usize
                            while t < njr {
                                if cv[jr[t]] < 0i64 { cv[jr[t]] = cn }
                                t += 1usize
                            }
                            t = 0usize
                            while t < njr {
                                if cv[jr[t]] == 0i64 && !inr[jr[t]] {
                                    inr[jr[t]] = true
                                    reach[nr] = jr[t]
                                    nr += 1usize
                                }
                                t += 1usize
                            }
                        }
                        var t2 = 0usize
                        while t2 < njr {
                            classn[jr[t2]] += 1usize
                            t2 += 1usize
                        }
                        un[j] = false
                        i2 += 1usize
                    }
                }
            }
        }
        // the loop stops once no unclassified point is left
        var left = false
        q = 0usize
        while q < n {
            if un[q] { left = true }
            q += 1usize
        }
        if !left && !any { break }
        if !left { break }
        i += 1usize
    }
    i = 0usize
    while i < n {
        if cv[i] == 0i64 - 1i64 { cv[i] = 0i64 }
        i += 1usize
    }
    ret ok
}

fn dist_xy(x: []const f64, p: usize, i: usize, j: usize) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < p {
        let d = x[i * p + k] - x[j * p + k]
        s += d * d
        k += 1usize
    }
    ret math.sqrt[f64](s)
}

// ---- R's solve(): the inverse of an n by n matrix as LAPACK's dgesv answers it with the identity as right-hand side (dgetrf2, the recursive LU with partial pivoting, then
// dgetrs with the reference dtrsm), operation for operation so that the rounding is R's. The arrays are column-major (element (i, j) at i + j * n).

// the element index of (i, j) of the block starting at off
fn lu_at(off: usize, lda: usize, i: usize, j: usize) -> usize { ret off + i + j * lda }

// dlaswp on ncols columns starting at column coff: the rows k1..k2-1 (0-based) exchanged with ipiv (0-based absolute row)
fn lu_laswp(aa: []f64, lda: usize, coff: usize, ncols: usize, k1: usize, k2: usize, ipiv: []const usize) {
    var i = k1
    while i < k2 {
        let ip = ipiv[i]
        if ip != i {
            var c = 0usize
            while c < ncols {
                let x1 = (coff + c) * lda + i
                let x2 = (coff + c) * lda + ip
                let t = aa[x1]
                aa[x1] = aa[x2]
                aa[x2] = t
                c += 1usize
            }
        }
        i += 1usize
    }
}

// dgetrf2 on the m by n block at off; ipiv[ioff ..] receives the pivots relative to the block's first row (0-based)
fn lu_getrf2(aa: []f64, lda: usize, off: usize, m: usize, n: usize, ipiv: []usize, ioff: usize) {
    if m == 1usize {
        ipiv[ioff] = 0usize
        ret
    }
    if n == 1usize {
        var imax = 0usize
        var best = math.abs[f64](aa[off])
        var i = 1usize
        while i < m {
            let v = math.abs[f64](aa[off + i])
            if v > best {
                best = v
                imax = i
            }
            i += 1usize
        }
        ipiv[ioff] = imax
        if aa[off + imax] != 0.0f64 {
            if imax != 0usize {
                let t = aa[off]
                aa[off] = aa[off + imax]
                aa[off + imax] = t
            }
            let sfmin = 2.2250738585072014e-308f64
            if math.abs[f64](aa[off]) >= sfmin {
                let r = 1.0f64 / aa[off]
                i = 1usize
                while i < m {
                    aa[off + i] = aa[off + i] * r
                    i += 1usize
                }
            } else {
                i = 1usize
                while i < m {
                    aa[off + i] = aa[off + i] / aa[off]
                    i += 1usize
                }
            }
        }
        ret
    }
    var mn = m
    if n < mn { mn = n }
    let n1 = mn / 2usize
    let n2 = n - n1
    lu_getrf2(aa, lda, off, m, n1, ipiv, ioff)
    // A12: the rows exchanged
    var i = 0usize
    while i < n1 {
        let ip = ipiv[ioff + i]
        if ip != i {
            var c = 0usize
            while c < n2 {
                let x1 = off + (n1 + c) * lda + i
                let x2 = off + (n1 + c) * lda + ip
                let t = aa[x1]
                aa[x1] = aa[x2]
                aa[x2] = t
                c += 1usize
            }
        }
        i += 1usize
    }
    // dtrsm L, L, N, U: A12 = L11^-1 A12
    var j = 0usize
    while j < n2 {
        var k = 0usize
        while k < n1 {
            let bkj = aa[off + k + (n1 + j) * lda]
            if bkj != 0.0f64 {
                var r = k + 1usize
                while r < n1 {
                    aa[off + r + (n1 + j) * lda] = aa[off + r + (n1 + j) * lda] - bkj * aa[off + r + k * lda]
                    r += 1usize
                }
            }
            k += 1usize
        }
        j += 1usize
    }
    // dgemm: A22 = A22 - A21 A12
    j = 0usize
    while j < n2 {
        var l = 0usize
        while l < n1 {
            let temp = 0.0f64 - aa[off + l + (n1 + j) * lda]
            var r = 0usize
            while r < m - n1 {
                aa[off + n1 + r + (n1 + j) * lda] = aa[off + n1 + r + (n1 + j) * lda] + temp * aa[off + n1 + r + l * lda]
                r += 1usize
            }
            l += 1usize
        }
        j += 1usize
    }
    lu_getrf2(aa, lda, off + n1 + n1 * lda, m - n1, n2, ipiv, ioff + n1)
    i = n1
    while i < mn {
        ipiv[ioff + i] += n1
        i += 1usize
    }
    // exchange the rows of A21 with the second block's pivots
    i = n1
    while i < mn {
        let ip = ipiv[ioff + i]
        if ip != i {
            var c = 0usize
            while c < n1 {
                let x1 = off + c * lda + i
                let x2 = off + c * lda + ip
                let t = aa[x1]
                aa[x1] = aa[x2]
                aa[x2] = t
                c += 1usize
            }
        }
        i += 1usize
    }
}

// the inverse of the n by n row-major matrix m, as solve(m): out is n by n row-major
fn lu_inverse(a: *mem.Arena, m: []const f64, n: usize, out: []f64) -> err {
    let (aa, e0) = mem.alloc[f64](a, n * n)
    let (bb, e1) = mem.alloc[f64](a, n * n)
    let (ipiv, e2) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            aa[i + j * n] = m[i * n + j]
            bb[i + j * n] = 0.0f64
            if i == j { bb[i + j * n] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    lu_getrf2(aa, n, 0usize, n, n, ipiv, 0usize)
    i = 0usize
    while i < n {
        if aa[i + i * n] == 0.0f64 { ret Malformed }
        i += 1usize
    }
    // dgetrs: the row exchanges on B, then L (unit lower) and U
    lu_laswp(bb, n, 0usize, n, 0usize, n, ipiv)
    var j = 0usize
    while j < n {
        var k = 0usize
        while k < n {
            if bb[k + j * n] != 0.0f64 {
                var r = k + 1usize
                while r < n {
                    bb[r + j * n] = bb[r + j * n] - bb[k + j * n] * aa[r + k * n]
                    r += 1usize
                }
            }
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < n {
        var k = n
        while k > 0usize {
            k -= 1usize
            if bb[k + j * n] != 0.0f64 {
                bb[k + j * n] = bb[k + j * n] / aa[k + k * n]
                var r = 0usize
                while r < k {
                    bb[r + j * n] = bb[r + j * n] - bb[k + j * n] * aa[r + k * n]
                    r += 1usize
                }
            }
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < n {
            out[i * n + j] = bb[i + j * n]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// Neumaier step: R's colMeans, rowSums and sum() accumulate in long double, which a compensated sum reproduces
fn cstep(s: f64, c: f64, v: f64) -> (f64, f64) {
    let t = s + v
    var cc = c
    if math.abs[f64](s) >= math.abs[f64](v) { cc += (s - t) + v } else { cc += (v - t) + s }
    ret (t, cc)
}

// ---- ncoord (fpc): neighbourhood-based discriminant coordinates. x is n by p row-major, cl the 0-based class of every point, nn the neighbourhood size; sphere is the
// covariance matrix to sphere the data by (p by p, row-major) or an empty slice for no sphering ("none"). ev (p), units (p by p) and proj (n by p) receive the eigenvalues in
// decreasing order, the coordinate directions (columns, in R's eigenvector order and sign) and the projections of the original data.
fn ncoord(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, kn: usize, nn: usize, weighted: bool, sphere: []const f64, ev: []f64, units: []f64, proj: []f64) -> err {
    let (z, e0) = mem.alloc[f64](a, n * p)
    let (yy, e1) = mem.alloc[f64](a, p * p)
    if e0 != ok || e1 != ok { ret mem.Full }
    var i = 0usize
    while i < p * p {
        yy[i] = 0.0f64
        i += 1usize
    }
    if sphere.len > 0usize {
        let (tm, e2) = mem.alloc[f64](a, p * p)
        if e2 != ok { ret e2 }
        let e3 = tdecomp(a, sphere, p, tm)
        if e3 != ok { ret e3 }
        let e4 = lu_inverse(a, tm, p, yy)
        if e4 != ok { ret e4 }
        i = 0usize
        while i < n {
            var j = 0usize
            while j < p {
                var s = 0.0f64
                var q = 0usize
                while q < p {
                    s += x[i * p + q] * yy[q * p + j]
                    q += 1usize
                }
                z[i * p + j] = s
                j += 1usize
            }
            i += 1usize
        }
    } else {
        i = 0usize
        while i < p {
            yy[i * p + i] = 1.0f64
            i += 1usize
        }
        i = 0usize
        while i < n * p {
            z[i] = x[i]
            i += 1usize
        }
    }
    let (b, e5) = mem.alloc[f64](a, p * p)
    let (bi, e6) = mem.alloc[f64](a, p * p)
    let (mds, e7) = mem.alloc[f64](a, n)
    let (omah, e8) = mem.alloc[usize](a, nn)
    let (mi, e9) = mem.alloc[f64](a, p)
    let (v, e10) = mem.alloc[f64](a, p)
    if e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
    i = 0usize
    while i < p * p {
        b[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var t = 0usize
        while t < p * p {
            bi[t] = 0.0f64
            t += 1usize
        }
        var q = 0usize
        while q < n {
            var d = 0.0f64
            var dc = 0.0f64
            var j = 0usize
            while j < p {
                let df = z[q * p + j] - z[i * p + j]
                let (d1, d2) = cstep(d, dc, df * df)
                d = d1
                dc = d2
                j += 1usize
            }
            mds[q] = d + dc
            q += 1usize
        }
        // order(mds)[1:nn]: the nn smallest, ties by position
        q = 0usize
        while q < n {
            var rank = 0usize
            var r = 0usize
            while r < n {
                if mds[r] < mds[q] || (mds[r] == mds[q] && r < q) { rank += 1usize }
                r += 1usize
            }
            if rank < nn { omah[rank] = q }
            q += 1usize
        }
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var sc = 0.0f64
            var r = 0usize
            while r < nn {
                let (s1, s2) = cstep(s, sc, z[omah[r] * p + j])
                s = s1
                sc = s2
                r += 1usize
            }
            let (m1, m2) = dd_norm(s, sc)
            let (m3, m4) = dd_div(m1, m2, f64(nn))
            mi[j] = m3 + m4
            j += 1usize
        }
        var c = 0usize
        while c < kn {
            var nj = 0usize
            var r = 0usize
            while r < nn {
                if cl[omah[r]] == c { nj += 1usize }
                r += 1usize
            }
            let pij = f64(nj) / f64(nn)
            j = 0usize
            while j < p {
                v[j] = 0.0f64
                j += 1usize
            }
            if nj > 0usize {
                j = 0usize
                while j < p {
                    var s = 0.0f64
                    var sc = 0.0f64
                    r = 0usize
                    while r < nn {
                        if cl[omah[r]] == c {
                            let (s1, s2) = cstep(s, sc, z[omah[r] * p + j])
                            s = s1
                            sc = s2
                        }
                        r += 1usize
                    }
                    let (m1, m2) = dd_norm(s, sc)
                    let (m3, m4) = dd_div(m1, m2, f64(nj))
                    v[j] = (m3 + m4) - mi[j]
                    j += 1usize
                }
            }
            var u1 = 0usize
            while u1 < p {
                var u2 = 0usize
                while u2 < p {
                    bi[u1 * p + u2] += pij * (v[u1] * v[u2])
                    u2 += 1usize
                }
                u1 += 1usize
            }
            c += 1usize
        }
        if weighted {
            var sb0 = 0.0f64
            var sbc = 0.0f64
            var d2 = 0usize
            while d2 < p {
                let (t1, t2) = cstep(sb0, sbc, bi[d2 * p + d2])
                sb0 = t1
                sbc = t2
                d2 += 1usize
            }
            let sb = sb0 + sbc
            if sb > 0.0f64 {
                var u = 0usize
                while u < p * p {
                    bi[u] = bi[u] / sb
                    u += 1usize
                }
            }
        }
        var u = 0usize
        while u < p * p {
            b[u] += bi[u]
            u += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p * p {
        b[i] = b[i] / f64(n)
        i += 1usize
    }
    let (w, e11) = mem.alloc[f64](a, p)
    let (vv, e12) = mem.alloc[f64](a, p * p)
    if e11 != ok || e12 != ok { ret mem.Full }
    let e13 = sy.dsyevr_all(a, b, p, w, vv)
    if e13 != ok { ret e13 }
    let (u0, e14) = mem.alloc[f64](a, p * p)
    if e14 != ok { ret e14 }
    var k = 0usize
    while k < p {
        ev[k] = w[p - 1usize - k]
        var r = 0usize
        while r < p {
            u0[r * p + k] = vv[(p - 1usize - k) * p + r]
            r += 1usize
        }
        k += 1usize
    }
    // units = Y %*% units (the identity without sphering), proj = x %*% units
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += yy[r * p + q] * u0[q * p + c]
                q += 1usize
            }
            units[r * p + c] = s
            c += 1usize
        }
        r += 1usize
    }
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

// log |det m| and m^-1 v of the d by d row-major matrix m (copied) by LU with partial pivoting; the solution goes to sol
fn logdet_solve(a: *mem.Arena, m: []const f64, v: []const f64, d: usize, sol: []f64) -> (f64, err) {
    let (w, e0) = mem.alloc[f64](a, d * (d + 1usize))
    if e0 != ok { ret (0.0f64, e0) }
    var r = 0usize
    while r < d {
        var c = 0usize
        while c < d {
            w[r * (d + 1usize) + c] = m[r * d + c]
            c += 1usize
        }
        w[r * (d + 1usize) + d] = v[r]
        r += 1usize
    }
    var ld = 0.0f64
    var col = 0usize
    while col < d {
        var piv = col
        var rr = col + 1usize
        while rr < d {
            if math.abs[f64](w[rr * (d + 1usize) + col]) > math.abs[f64](w[piv * (d + 1usize) + col]) { piv = rr }
            rr += 1usize
        }
        var cc = 0usize
        while cc <= d {
            let t = w[col * (d + 1usize) + cc]
            w[col * (d + 1usize) + cc] = w[piv * (d + 1usize) + cc]
            w[piv * (d + 1usize) + cc] = t
            cc += 1usize
        }
        let pv = w[col * (d + 1usize) + col]
        ld += math.log[f64](math.abs[f64](pv))
        rr = col + 1usize
        while rr < d {
            let f = w[rr * (d + 1usize) + col] / pv
            cc = col
            while cc <= d {
                w[rr * (d + 1usize) + cc] -= f * w[col * (d + 1usize) + cc]
                cc += 1usize
            }
            rr += 1usize
        }
        col += 1usize
    }
    var i = d
    while i > 0usize {
        let q = i - 1usize
        var s = w[q * (d + 1usize) + d]
        var k = q + 1usize
        while k < d {
            s -= w[q * (d + 1usize) + k] * sol[k]
            k += 1usize
        }
        sol[q] = s / w[q * (d + 1usize) + q]
        i -= 1usize
    }
    ret (ld, ok)
}

// fpc bhattacharyya.dist(mu1, mu2, Sigma1, Sigma2) for d-dimensional Gaussian components
fn bhattacharyya_dist(a: *mem.Arena, mu1: []const f64, mu2: []const f64, s1: []const f64, s2: []const f64, d: usize) -> (f64, err) {
    let (sg, e0) = mem.alloc[f64](a, d * d)
    let (df, e1) = mem.alloc[f64](a, d)
    let (sol, e2) = mem.alloc[f64](a, d)
    let (sol2, e3) = mem.alloc[f64](a, d)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < d * d {
        sg[i] = (s1[i] + s2[i]) / 2.0f64
        i += 1usize
    }
    i = 0usize
    while i < d {
        df[i] = mu1[i] - mu2[i]
        i += 1usize
    }
    let (lds, ea) = logdet_solve(a, sg, df, d, sol)
    if ea != ok { ret (0.0f64, ea) }
    let (lds1, eb) = logdet_solve(a, s1, df, d, sol2)
    if eb != ok { ret (0.0f64, eb) }
    let (lds2, ec) = logdet_solve(a, s2, df, d, sol2)
    if ec != ok { ret (0.0f64, ec) }
    var mh = 0.0f64
    i = 0usize
    while i < d {
        mh += df[i] * sol[i]
        i += 1usize
    }
    ret (mh / 8.0f64 + 0.5f64 * lds - 0.25f64 * lds1 - 0.25f64 * lds2, ok)
}

// fpc confusion(z, pro, i, j): the share of component j'"'"'s weight sitting on the points that the pair (i, j) assigns to i (the larger z, ties to i)
fn zconfusion(z: []const f64, n: usize, k: usize, probs: []const f64, i: usize, j: usize) -> f64 {
    var s = 0.0f64
    var r = 0usize
    while r < n {
        if z[r * k + i] >= z[r * k + j] { s += z[r * k + j] }
        r += 1usize
    }
    ret s / (f64(n) * probs[j])
}

// nstop > 0 is numberstop (the caller passes cutoff 0): merging stops at that many live components.
// mergenormals(xdata, clustering, probs, muarray, Sigmaarray, z, method = "bhat" or (demp = true) "demp", cutoff): merge Gaussian mixture components while the largest exp(-Bhattacharyya distance) among the live pairs reaches the cutoff.
// x is n by d (row-major), mu is k by d (row j the mean of component j), sg is k blocks of d by d, z is n by k; probs, mu, sg and z are updated in place by the merges (mergeparameters: summed z weights, weighted ML mean and covariance of the data).
// map receives mergedtonumbers (1-based, renumbered to 1..m in increasing order of the surviving numbers, as renumber = TRUE does when every component owns some data) and vals the decision values valuemerged; the answer is how many values.
fn merge_bhat(a: *mem.Arena, x: []const f64, n: usize, d: usize, k: usize, probs: []f64, mu: []f64, sg: []f64, z: []f64, cutoff: f64, map: []usize, vals: []f64, demp: bool, nstop: usize) -> (usize, err) {
    let (bm, e0) = mem.alloc[f64](a, k * k)
    let (dead, e1) = mem.alloc[bool](a, k)
    let (dec, e2) = mem.alloc[f64](a, k * k)
    if e0 != ok || e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    var i = 0usize
    while i < k {
        dead[i] = false
        map[i] = i
        i += 1usize
    }
    var nv = 0usize
    var nmerged = 0usize
    var all = true
    var upi = 0usize
    var loop = true
    while loop {
        // refresh the bhat matrix: every pair the first time, then the pairs against the merged component (upi)
        var p = 0usize
        while p < k {
            var q = p + 1usize
            while q < k {
                var need = all
                if !all && ((p == upi && q != upi) || (q == upi && p != upi)) { need = true }
                if need && !dead[p] && !dead[q] && demp {
                    let c1 = zconfusion(z, n, k, probs, p, q)
                    let c2 = zconfusion(z, n, k, probs, q, p)
                    bm[p * k + q] = c1
                    if c2 > c1 { bm[p * k + q] = c2 }
                } else if need && !dead[p] && !dead[q] {
                    let (bd, eb) = bhattacharyya_dist(a, mu[p * d..p * d + d], mu[q * d..q * d + d], sg[p * d * d..(p + 1usize) * d * d], sg[q * d * d..(q + 1usize) * d * d], d)
                    if eb != ok { ret (0usize, eb) }
                    bm[p * k + q] = math.exp[f64](0.0f64 - bd)
                }
                q += 1usize
            }
            p += 1usize
        }
        all = false
        // the decision matrix: live upper-triangle entries only
        var best = 0.0f64
        var bi = k
        var bj = k
        var any = false
        var c = 0usize
        while c < k {
            var r = 0usize
            while r < c {
                var v = 0.0f64
                if !dead[r] && !dead[c] { v = bm[r * k + c] }
                dec[r * k + c] = v
                if v >= cutoff { any = true }
                if bi == k || v > best {
                    best = v
                    bi = r
                    bj = c
                }
                r += 1usize
            }
            c += 1usize
        }
        vals[nv] = best
        nv += 1usize
        if !any || (nstop > 0usize && nstop == k - nmerged) { break }
        nmerged += 1usize
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
        if nstop > 0usize && nstop == k - nmerged { break }
    }
    // renumber the surviving numbers to 1 .. m in increasing order
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

// the quantile of the sorted sample at probability p, type 7
fn varwise_q7(s: []const f64, p: f64) -> f64 {
    let n = s.len
    let h = f64(n - 1usize) * p
    let lo = math.floor[f64](h)
    let i = usize(lo)
    if i + 1usize >= n { ret s[n - 1usize] }
    ret s[i] + (h - lo) * (s[i + 1usize] - s[i])
}

// fpc cluster.varstats' varwise table of a categorised variable: the variable is cut at its cats quantiles (category 1, or j when above the (j - 1)-th of the cats - 1 inner quantile points
// as the package writes it) and the counts per cluster (1 .. ncl) and category fill out (ncl rows by cats columns, row-major)
fn varwise_counts(a: *mem.Arena, x: []const f64, clustering: []const usize, ncl: usize, cats: usize, out: []f64) -> err {
    let n = x.len
    let (srt, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < n {
        srt[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = srt[i]
        var j = i
        while j > 0usize && srt[j - 1usize] > v {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = v
        i += 1usize
    }
    i = 0usize
    while i < ncl * cats {
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var cat = 1usize
        var j = 2usize
        while j <= cats {
            let q = varwise_q7(srt, f64(j - 1usize) / f64(cats))
            if x[i] > q { cat = j }
            j += 1usize
        }
        out[(clustering[i] - 1usize) * cats + cat - 1usize] += 1.0f64
        i += 1usize
    }
    ret ok
}

// ---- small exports: calinhara, neginc, cov.wml, cweight, clujaccard, cmahal, confusion

// det(m) of the n by n row-major m by dgetrf2's LU
fn lu_det(a: *mem.Arena, m: []const f64, n: usize) -> (f64, err) {
    let (aa, e0) = mem.alloc[f64](a, n * n)
    let (ipiv, e2) = mem.alloc[usize](a, n)
    if e0 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            aa[i + j * n] = m[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    lu_getrf2(aa, n, 0usize, n, n, ipiv, 0usize)
    var d = 1.0f64
    i = 0usize
    while i < n {
        d = d * aa[i + i * n]
        if ipiv[i] != i { d = -d }
        i += 1usize
    }
    ret (d, ok)
}

// the trace of the covariance of the rows of x with label l, and their count
fn cov_trace(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, l: usize) -> (f64, usize, err) {
    let (c, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret (0.0f64, 0usize, e1) }
    let (k, e2) = cov_rows(a, x, n, p, cl, l, c)
    var t = 0.0f64
    var i = 0usize
    while i < p {
        t += c[i * p + i]
        i += 1usize
    }
    ret (t, k, e2)
}

// calinhara(x, clustering, cn): labels 1..cn
fn calinhara(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, cn: usize) -> (f64, err) {
    let (zlab, e0) = mem.alloc[usize](a, n)
    if e0 != ok { ret (0.0f64, e0) }
    var i = 0usize
    while i < n {
        zlab[i] = 0usize
        i += 1usize
    }
    let (ts, _, e1) = cov_trace(a, x, n, p, zlab, 0usize)
    if e1 != ok { ret (0.0f64, e1) }
    var tw = 0.0f64
    var l = 1usize
    while l <= cn {
        let (t, k, e2) = cov_trace(a, x, n, p, cl, l)
        if e2 != ok { ret (0.0f64, e2) }
        if k >= 2usize { tw += f64(k - 1usize) * t }
        l += 1usize
    }
    let tb = f64(n - 1usize) * ts - tw
    ret (f64(n - cn) * tb / (f64(cn - 1usize) * tw), ok)
}

// neginc(x, clustering): labels 1..cn
fn neginc(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, cn: usize) -> (f64, err) {
    let (c, e1) = mem.alloc[f64](a, p * p)
    let (zlab, e0) = mem.alloc[usize](a, n)
    if e1 != ok || e0 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < n {
        zlab[i] = 0usize
        i += 1usize
    }
    let (_, e2) = cov_rows(a, x, n, p, zlab, 0usize, c)
    if e2 != ok { ret (0.0f64, e2) }
    let (dall, e3) = lu_det(a, c, p)
    if e3 != ok { ret (0.0f64, e3) }
    var s = 0.0f64
    var l = 1usize
    while l <= cn {
        let (k, e4) = cov_rows(a, x, n, p, cl, l, c)
        if e4 != ok { ret (0.0f64, e4) }
        var dl = 0.0f64
        if k >= 2usize {
            let (dd, e5) = lu_det(a, c, p)
            if e5 != ok { ret (0.0f64, e5) }
            dl = dd
        }
        let pri = f64(k) / f64(n)
        s += pri * math.log[f64](dl) * 0.5f64 - pri * math.log[f64](pri)
        l += 1usize
    }
    ret (s - 0.5f64 * math.log[f64](dall), ok)
}

// cov.wml(x, wt, center = TRUE)$cov element (r, c): weights normalised to sum 1 (x n by p row-major)
fn cov_wml(x: []const f64, n: usize, p: usize, wt: []const f64, r: usize, c: usize) -> f64 {
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += wt[i]
        i += 1usize
    }
    var mr = 0.0f64
    var mc = 0.0f64
    i = 0usize
    while i < n {
        mr += wt[i] / sw * x[i * p + r]
        mc += wt[i] / sw * x[i * p + c]
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < n {
        let w = wt[i] / sw
        s += math.sqrt[f64](w) * (x[i * p + r] - mr) * (math.sqrt[f64](w) * (x[i * p + c] - mc))
        i += 1usize
    }
    ret s
}

fn cweight(x: f64, ca: f64) -> f64 {
    var out = 1.0f64
    if x > ca { out = ca / x }
    ret out
}

// clujaccard of two logical vectors given as 0/1; a zlab union answers zero_by_zero
fn clujaccard(c1: []const f64, c2: []const f64, n: usize, zero_by_zero: f64) -> f64 {
    var s1 = 0.0f64
    var s2 = 0.0f64
    var both = 0.0f64
    var i = 0usize
    while i < n {
        if c1[i] != 0.0f64 { s1 += 1.0f64 }
        if c2[i] != 0.0f64 { s2 += 1.0f64 }
        if c1[i] != 0.0f64 && c2[i] != 0.0f64 { both += 1.0f64 }
        i += 1usize
    }
    if s1 + s2 - both == 0.0f64 { ret zero_by_zero }
    ret both / (s1 + s2 - both)
}

// cmahal(n, p, nmin, cmin, nc1, c1, q)[pos] (pos 1-based); R's loop reassignment of i does not stop the loop, and neither does this
fn cmahal(a: *mem.Arena, n: usize, p: f64, nmin: usize, cmin: f64, nc1: usize, c1: f64, q: f64, pos: usize) -> (f64, err) {
    var len = n
    if nc1 > len { len = nc1 }
    let (cs, e1) = mem.alloc[f64](a, len + 2usize)
    if e1 != ok { ret (0.0f64, e1) }
    var i = 0usize
    while i < len + 2usize {
        cs[i] = c1
        i += 1usize
    }
    i = nc1 - 1usize
    while i >= nmin {
        cs[i] = cs[i + 1usize] + q * (cs[i + 1usize] - p) / (f64(i) + 1.0f64 - q)
        i -= 1usize
    }
    i = 1usize
    while i < nmin {
        cs[i] = cs[nmin]
        i += 1usize
    }
    if n > nc1 {
        i = nc1 + 1usize
        while i <= n {
            cs[i] = cs[i - 1usize] - q * (cs[i - 1usize] - p) / f64(i)
            if cs[i] <= cmin { cs[i] = cmin }
            i += 1usize
        }
    }
    ret (cs[pos], ok)
}

// confusion(z, pro, i, j): z n by k row-major, i and j 1-based
fn confusion(z: []const f64, n: usize, k: usize, pro: []const f64, i: usize, j: usize) -> f64 {
    var s = 0.0f64
    var r = 0usize
    while r < n {
        // which.max picks the first of a tie, cluster i
        if z[r * k + j - 1usize] <= z[r * k + i - 1usize] { s += z[r * k + j - 1usize] }
        r += 1usize
    }
    ret s / (f64(n) * pro[j - 1usize])
}

// ---- cluster.stats in full: noise cluster (the last label), every vector and matrix output.
// out layout (cn = number of clusters): 0 average.between 1 average.within 2 max.diameter 3 min.separation 4 within.cluster.ss 5 avg.silwidth
// 6 g2 7 g3 8 pearsongamma 9 dunn 10 dunn2 11 entropy 12 wb.ratio 13 ch 14 widestgap 15 sindex 16 corrected.rand 17 vi 18 n.between 19 n.within
// 20 min.cluster.size 21 noisen 22 ave.within.cluster.ss; vectors of length cn from 24 + j * cn: 0 cluster.size 1 diameter 2 average.distance
// 3 median.distance 4 separation 5 average.toother 6 clus.avg.silwidths 7 cwidegap; then separation.matrix and ave.between.matrix (cn by cn).
// flags: 1 silhouette 2 G2 4 G3 8 wgap 16 sepindex. A value R leaves NA or NULL is NaN here.
fn cs_len(cn: usize) -> usize { ret 24usize + 8usize * cn + 2usize * cn * cn }

fn cs_sort(v: []f64, m: usize) {
    var i = 1usize
    while i < m {
        let t = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > t {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = t
        i += 1usize
    }
}

fn cstats(a: *mem.Arena, d: []const f64, n: usize, cl: []const usize, cn: usize, noise: bool, flags: usize, sepwn: bool, sepprob: f64, out: []f64) -> err {
    let nan = 0.0f64 / 0.0f64
    var cwn = cn
    var noisen = 0usize
    var i = 0usize
    while i < cs_len(cn) {
        out[i] = nan
        i += 1usize
    }
    let vb = 24usize
    let mb = 24usize + 8usize * cn
    let pairs = n * (n - 1usize) / 2usize
    let (size, e1) = mem.alloc[f64](a, cn)
    let (wd, e2) = mem.alloc[f64](a, pairs + 1usize)
    let (bd, e3) = mem.alloc[f64](a, pairs + 1usize)
    let (tmp, e4) = mem.alloc[f64](a, pairs + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    i = 0usize
    while i < cn {
        size[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        size[cl[i] - 1usize] += 1.0f64
        i += 1usize
    }
    if noise {
        cwn = cn - 1usize
        noisen = usize(size[cn - 1usize])
    }
    var h1 = 0.0f64
    i = 0usize
    while i < cn {
        let p = size[i] / f64(n)
        if p > 0.0f64 { h1 -= p * math.log[f64](p) }
        out[vb + i] = size[i]
        i += 1usize
    }
    out[11usize] = h1
    var tot2 = 0.0f64
    var nn2 = 0.0f64
    var nnn = 0.0f64
    i = 0usize
    while i < n {
        if cl[i] <= cwn { nnn += 1.0f64 }
        var j = i + 1usize
        while j < n {
            tot2 += d[i * n + j] * d[i * n + j]
            if cl[i] <= cwn && cl[j] <= cwn { nn2 += d[i * n + j] * d[i * n + j] }
            j += 1usize
        }
        i += 1usize
    }
    let overall = tot2 / f64(n)
    var nonnoise = overall
    if noise { nonnoise = nn2 / nnn }
    var nw = 0usize
    var nb = 0usize
    var wcss = 0.0f64
    var avw_num = 0.0f64
    var avw_den = 0.0f64
    var c = 0usize
    while c < cn {
        var m = 0usize
        var sd = 0.0f64
        var sd2 = 0.0f64
        var mx = 0.0f64
        var j = 0usize
        while j < n {
            if cl[j] - 1usize == c {
                var k = j + 1usize
                while k < n {
                    if cl[k] - 1usize == c {
                        let v = d[j * n + k]
                        tmp[m] = v
                        m += 1usize
                        sd += v
                        sd2 += v * v
                        if v > mx { mx = v }
                        if c < cwn {
                            wd[nw] = v
                            nw += 1usize
                        }
                    }
                    k += 1usize
                }
            }
            j += 1usize
        }
        if c < cwn { wcss += sd2 / size[c] }
        if m > 0usize {
            out[vb + 1usize * cn + c] = mx
            out[vb + 2usize * cn + c] = sd / f64(m)
            cs_sort(tmp, m)
            var md = tmp[m / 2usize]
            if m % 2usize == 0usize { md = (tmp[m / 2usize - 1usize] + tmp[m / 2usize]) / 2.0f64 }
            out[vb + 3usize * cn + c] = md
            avw_num += (sd / f64(m)) * size[c]
            avw_den += size[c]
        }
        var bmin = 1.0e300f64
        var bs = 0.0f64
        var bc = 0.0f64
        var c2 = 0usize
        while c2 < cn {
            if c2 != c {
                var smin = 1.0e300f64
                var ssum = 0.0f64
                var scnt = 0.0f64
                j = 0usize
                while j < n {
                    if cl[j] - 1usize == c {
                        var k = 0usize
                        while k < n {
                            if cl[k] - 1usize == c2 {
                                let v = d[j * n + k]
                                if v < smin { smin = v }
                                ssum += v
                                scnt += 1.0f64
                                if c < c2 && c2 < cwn {
                                    bd[nb] = v
                                    nb += 1usize
                                }
                            }
                            k += 1usize
                        }
                    }
                    j += 1usize
                }
                if smin < bmin { bmin = smin }
                bs += ssum
                bc += scnt
                if c < c2 {
                    out[mb + c * cn + c2] = smin
                    out[mb + c2 * cn + c] = smin
                    out[mb + cn * cn + c * cn + c2] = ssum / scnt
                    out[mb + cn * cn + c2 * cn + c] = ssum / scnt
                }
            }
            c2 += 1usize
        }
        out[vb + 4usize * cn + c] = bmin
        out[vb + 5usize * cn + c] = bs / bc
        c += 1usize
    }
    c = 0usize
    while c < cn {
        out[mb + c * cn + c] = 0.0f64
        out[mb + cn * cn + c * cn + c] = 0.0f64
        c += 1usize
    }
    var sbw = 0.0f64
    i = 0usize
    while i < nb {
        sbw += bd[i]
        i += 1usize
    }
    var swd = 0.0f64
    i = 0usize
    while i < nw {
        swd += wd[i]
        i += 1usize
    }
    let ave_b = sbw / f64(nb)
    let ave_w = avw_num / avw_den
    out[0usize] = ave_b
    out[1usize] = ave_w
    out[4usize] = wcss
    out[12usize] = ave_w / ave_b
    out[13usize] = (nonnoise - wcss) * (f64(n) - f64(noisen) - f64(cwn)) / (wcss * (f64(cwn) - 1.0f64))
    out[18usize] = f64(nb)
    out[19usize] = f64(nw)
    out[22usize] = wcss / (f64(n) - f64(noisen))
    var maxd = -1.0e300f64
    var minsz = 1.0e300f64
    var mins = 1.0e300f64
    var minsall = 1.0e300f64
    var maxavg = -1.0e300f64
    var mindiff = 1.0e300f64
    c = 0usize
    while c < cn {
        if out[vb + 4usize * cn + c] < minsall { minsall = out[vb + 4usize * cn + c] }
        if c < cwn {
            if out[vb + 1usize * cn + c] > maxd { maxd = out[vb + 1usize * cn + c] }
            if size[c] < minsz { minsz = size[c] }
            if out[vb + 4usize * cn + c] < mins { mins = out[vb + 4usize * cn + c] }
            if out[vb + 2usize * cn + c] > maxavg { maxavg = out[vb + 2usize * cn + c] }
            var c3 = c + 1usize
            while c3 < cwn {
                if out[mb + cn * cn + c * cn + c3] < mindiff { mindiff = out[mb + cn * cn + c * cn + c3] }
                c3 += 1usize
            }
        }
        c += 1usize
    }
    out[2usize] = maxd
    out[20usize] = minsz
    out[21usize] = f64(noisen)
    if sepwn {
        out[3usize] = minsall
    } else {
        out[3usize] = mins
    }
    out[9usize] = mins / maxd
    out[10usize] = mindiff / maxavg
    let nt = f64(nw + nb)
    var sxx = 0.0f64
    i = 0usize
    while i < nw {
        sxx += wd[i] * wd[i]
        i += 1usize
    }
    i = 0usize
    while i < nb {
        sxx += bd[i] * bd[i]
        i += 1usize
    }
    let sx = swd + sbw
    out[8usize] = (sbw - sx * f64(nb) / nt) / math.sqrt[f64]((sxx - sx * sx / nt) * (f64(nb) - f64(nb) * f64(nb) / nt))
    if (flags / 2usize) % 2usize == 1usize {
        var splus = 0.0f64
        var sminus = 0.0f64
        i = 0usize
        while i < nw {
            var j = 0usize
            while j < nb {
                if wd[i] < bd[j] { splus += 1.0f64 }
                if wd[i] > bd[j] { sminus += 1.0f64 }
                j += 1usize
            }
            i += 1usize
        }
        out[6usize] = (splus - sminus) / (splus + sminus)
    }
    if (flags / 4usize) % 2usize == 1usize {
        let (all, e6) = mem.alloc[f64](a, pairs + 1usize)
        if e6 != ok { ret mem.Full }
        i = 0usize
        while i < nw {
            all[i] = wd[i]
            i += 1usize
        }
        i = 0usize
        while i < nb {
            all[nw + i] = bd[i]
            i += 1usize
        }
        cs_sort(all, nw + nb)
        var dmin = 0.0f64
        var dmax = 0.0f64
        i = 0usize
        while i < nw {
            dmin += all[i]
            dmax += all[nw + nb - 1usize - i]
            i += 1usize
        }
        out[7usize] = (swd - dmin) / (dmax - dmin)
    }
    if flags % 2usize == 1usize {
        var tot = 0.0f64
        var totn = 0.0f64
        let (cs_sum, e7) = mem.alloc[f64](a, cn)
        let (cs_cnt, e8) = mem.alloc[f64](a, cn)
        if e7 != ok || e8 != ok { ret mem.Full }
        c = 0usize
        while c < cn {
            cs_sum[c] = 0.0f64
            cs_cnt[c] = 0.0f64
            c += 1usize
        }
        i = 0usize
        while i < n {
            let ci = cl[i] - 1usize
            var s = 0.0f64
            if size[ci] > 1.0f64 {
                var ai = 0.0f64
                var j = 0usize
                while j < n {
                    if j != i && cl[j] - 1usize == ci { ai += d[i * n + j] }
                    j += 1usize
                }
                ai = ai / (size[ci] - 1.0f64)
                var bi = 1.0e300f64
                var c2 = 0usize
                while c2 < cn {
                    if c2 != ci {
                        var sm = 0.0f64
                        j = 0usize
                        while j < n {
                            if cl[j] - 1usize == c2 { sm += d[i * n + j] }
                            j += 1usize
                        }
                        if sm / size[c2] < bi { bi = sm / size[c2] }
                    }
                    c2 += 1usize
                }
                var mxab = ai
                if bi > mxab { mxab = bi }
                s = (bi - ai) / mxab
            }
            cs_sum[ci] += s
            cs_cnt[ci] += 1.0f64
            if !noise || ci < cwn {
                tot += s
                totn += 1.0f64
            }
            i += 1usize
        }
        c = 0usize
        while c < cn {
            out[vb + 6usize * cn + c] = cs_sum[c] / cs_cnt[c]
            c += 1usize
        }
        out[5usize] = tot / totn
    }
    if (flags / 8usize) % 2usize == 1usize {
        var worst = 0.0f64
        c = 0usize
        while c < cwn {
            var cw = 0.0f64
            if size[c] > 1.0f64 {
                let (inn, e9) = mem.alloc[bool](a, n)
                let (best, e10) = mem.alloc[f64](a, n)
                if e9 != ok || e10 != ok { ret mem.Full }
                var start = n
                i = 0usize
                while i < n {
                    inn[i] = false
                    best[i] = 1.0e300f64
                    if cl[i] - 1usize == c && start == n { start = i }
                    i += 1usize
                }
                var cur = start
                var added = 1usize
                inn[cur] = true
                while added < usize(size[c]) {
                    var j = 0usize
                    while j < n {
                        if cl[j] - 1usize == c && !inn[j] && d[cur * n + j] < best[j] { best[j] = d[cur * n + j] }
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
                    if pv > cw { cw = pv }
                    inn[pick] = true
                    cur = pick
                    added += 1usize
                }
            }
            out[vb + 7usize * cn + c] = cw
            if cw > worst { worst = cw }
            c += 1usize
        }
        out[14usize] = worst
    }
    if (flags / 16usize) % 2usize == 1usize {
        let (ps, e11) = mem.alloc[f64](a, n)
        if e11 != ok { ret mem.Full }
        var m = 0usize
        i = 0usize
        while i < n {
            if sepwn || !noise || cl[i] <= cwn {
                var mm = 1.0e300f64
                var j = 0usize
                while j < n {
                    if cl[j] != cl[i] && (sepwn || !noise || cl[j] <= cwn) && d[i * n + j] < mm { mm = d[i * n + j] }
                    j += 1usize
                }
                ps[m] = mm
                m += 1usize
            }
            i += 1usize
        }
        cs_sort(ps, m)
        var take = usize(math.floor[f64](f64(m) * sepprob))
        if take == 0usize { take = 1usize }
        var sm = 0.0f64
        i = 0usize
        while i < take {
            sm += ps[i]
            i += 1usize
        }
        out[15usize] = sm / f64(take)
    }
    ret ok
}
