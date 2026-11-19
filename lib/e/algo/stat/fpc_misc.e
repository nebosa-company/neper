// R fpc: dudahart2, con.comp, stupidkcentroids, stupidknn, stupidkfn, stupidkaven, distcritmulti, cvnn and mahalanodisc. Matrices are row-major.
//
// Not here: solvecov's singular path (it needs dgecon's reciprocal condition number), cdbw, cqcluster.stats, pamk, kmeansruns (Hartigan-Wong).

use e.algo.rand.r as rg
use e.algo.stat.fpc as fp
use e.algo.stat.fpc_coord as fc
use e.math
use e.math.dist as dist
use e.mem

error Malformed

// dudahart2 for the two-cluster labels 1 and 2: out gets p.value, dh, compare, cluster1, alpha, z
fn dudahart2(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, alpha: f64, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, p * p)
    let (cc, e2) = mem.alloc[f64](a, p * p)
    let (ct, e3) = mem.alloc[f64](a, p * p)
    let (ones, e4) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret Malformed }
    var i = 0usize
    while i < p * p {
        w[i] = 0.0f64
        i += 1usize
    }
    var g = 1usize
    while g <= 2usize {
        let (kc, e5) = fp.cov_rows(a, x, n, p, cl, g, cc)
        if e5 != ok { ret e5 }
        i = 0usize
        while i < p * p {
            var v = cc[i]
            if kc < 2usize { v = 0.0f64 }
            w[i] = w[i] + f64(kc - 1usize) * v
            i += 1usize
        }
        g += 1usize
    }
    i = 0usize
    while i < n {
        ones[i] = 1usize
        i += 1usize
    }
    let (_, e6) = fp.cov_rows(a, x, n, p, ones, 1usize, ct)
    if e6 != ok { ret e6 }
    var sw = 0.0f64
    var sc = 0.0f64
    var s1 = 0.0f64
    var s1c = 0.0f64
    i = 0usize
    while i < p {
        let (h1, l1) = fp.dd_add(sw, sc, w[i * p + i], 0.0f64)
        sw = h1
        sc = l1
        let (h2, l2) = fp.dd_add(s1, s1c, f64(n - 1usize) * ct[i * p + i], 0.0f64)
        s1 = h2
        s1c = l2
        i += 1usize
    }
    let dh = (sw + sc) / (s1 + s1c)
    let z = dist.qnorm(1.0f64 - alpha, 0.0f64, 1.0f64, true, false)
    let pf = f64(p)
    let nf = f64(n)
    let pi = 3.141592653589793f64
    let compare = 1.0f64 - 2.0f64 / (pi * pf) - z * math.sqrt[f64](2.0f64 * (1.0f64 - 8.0f64 / (pi * pi * pf)) / (nf * pf))
    let qz = (0.0f64 - dh + 1.0f64 - 2.0f64 / (pi * pf)) / math.sqrt[f64](2.0f64 * (1.0f64 - 8.0f64 / (pi * pi * pf)) / (nf * pf))
    out[0usize] = 1.0f64 - dist.pnorm(qz, 0.0f64, 1.0f64, true, false)
    out[1usize] = dh
    out[2usize] = compare
    out[3usize] = 0.0f64
    if dh >= compare { out[3usize] = 1.0f64 }
    out[4usize] = alpha
    out[5usize] = z
    ret ok
}

// con.comp(comat): comat is nc by nc row-major, nonzero for TRUE; ccn gets the component numbers
fn con_comp(comat: []const f64, nc: usize, ccn: []usize) {
    var fhist: [4096]bool = zero
    var i = 0usize
    while i < nc {
        ccn[i] = 0usize
        fhist[i] = false
        i += 1usize
    }
    var stn = 0usize
    var pn = 1usize
    while pn > 0usize {
        stn += 1usize
        var go = true
        while go {
            var sm = 0usize
            ccn[pn - 1usize] = stn
            fhist[pn - 1usize] = true
            if nc > 1usize {
                i = 2usize
                while i <= nc {
                    if ccn[i - 1usize] == 0usize && comat[(i - 1usize) * nc + (pn - 1usize)] != 0.0f64 { ccn[i - 1usize] = stn }
                    if sm == 0usize && ccn[i - 1usize] == stn && !fhist[i - 1usize] { sm = i }
                    i += 1usize
                }
            }
            if sm > 0usize {
                pn = sm
            } else {
                go = false
            }
        }
        pn = 0usize
        i = 2usize
        while i <= nc {
            if ccn[i - 1usize] == 0usize {
                pn = i
                i = nc
            }
            i += 1usize
        }
    }
}

// the stupidk* family on the n by n dissimilarities d: mode 0 stupidkcentroids (distances = TRUE), 1 stupidknn, 2 stupidkfn, 3 stupidkaven; labels 1..k
fn stupidk(a: *mem.Arena, d: []const f64, n: usize, k: usize, mode: usize, seedv: i64, cl: []usize) -> err {
    var rng: rg.Rng = zero
    rg.seed(&rng, seedv)
    ret stupidk_g(a, &rng, d, n, k, mode, cl)
}

// the same on a running generator g (what clusterboot hands its clustering method)
fn stupidk_g(a: *mem.Arena, gen: *rg.Rng, d: []const f64, n: usize, k: usize, mode: usize, cl: []usize) -> err {
    let (kc, e1) = rg.sample_int(a, gen, i64(n), i64(k), false)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        cl[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < k {
        cl[usize(kc[i]) - 1usize] = i + 1usize
        i += 1usize
    }
    if mode == 0usize {
        i = 0usize
        while i < n {
            if cl[i] == 0usize {
                var best = 0usize
                var bv = 1.0e300f64
                var j = 0usize
                while j < k {
                    let v = d[i * n + (usize(kc[j]) - 1usize)]
                    if v < bv {
                        bv = v
                        best = j + 1usize
                    }
                    j += 1usize
                }
                cl[i] = best
            }
            i += 1usize
        }
        ret ok
    }
    let (opt, e2) = mem.alloc[usize](a, k + 1usize)
    let (mmx, e3) = mem.alloc[f64](a, k + 1usize)
    let (rowv, e4) = mem.alloc[f64](a, n)
    if e2 != ok || e3 != ok || e4 != ok { ret Malformed }
    var done = k
    while done < n {
        if mode == 1usize {
            var br = n
            var bc = n
            var bv = 1.0e300f64
            var c = 0usize
            while c < n {
                if cl[c] > 0usize {
                    var r = 0usize
                    while r < n {
                        if cl[r] == 0usize && d[r * n + c] < bv {
                            bv = d[r * n + c]
                            br = r
                            bc = c
                        }
                        r += 1usize
                    }
                }
                c += 1usize
            }
            cl[br] = cl[bc]
        } else {
            var g = 1usize
            while g <= k {
                var bestv = 1.0e300f64
                var bestr = n
                var r = 0usize
                while r < n {
                    if cl[r] == 0usize {
                        var v = -1.0e300f64
                        if mode == 3usize {
                            var cnt = 0usize
                            var c = 0usize
                            while c < n {
                                if cl[c] == g {
                                    rowv[cnt] = d[r * n + c]
                                    cnt += 1usize
                                }
                                c += 1usize
                            }
                            v = fc.r_mean(rowv, cnt)
                        } else {
                            var c = 0usize
                            while c < n {
                                if cl[c] == g && d[r * n + c] > v { v = d[r * n + c] }
                                c += 1usize
                            }
                        }
                        if v < bestv {
                            bestv = v
                            bestr = r
                        }
                    }
                    r += 1usize
                }
                mmx[g] = bestv
                opt[g] = bestr
                g += 1usize
            }
            var kopt = 1usize
            g = 2usize
            while g <= k {
                if mmx[g] < mmx[kopt] { kopt = g }
                g += 1usize
            }
            cl[opt[kopt]] = kopt
        }
        done += 1usize
    }
    ret ok
}

// distcritmulti(x, clustering, ns, criterion, seed) with the default part (equal blocks, the remainder in the last): criterion 0 asw, 1 pearsongamma.
// sub gets the ns criterion values; returns (overall, sd)
fn distcritmulti(a: *mem.Arena, x: []const f64, n: usize, p: usize, clustering: []const usize, ns: usize, crit: usize, seedv: i64, sub: []f64) -> (f64, f64, err) {
    var rng: rg.Rng = zero
    rg.seed(&rng, seedv)
    let pn1 = n / ns
    let (perm, e1) = rg.sample_int(a, &rng, i64(n), i64(n), false)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    var off = 0usize
    var s = 0usize
    var tot = 0.0f64
    while s < ns {
        var m = pn1
        if s == ns - 1usize { m = pn1 + n % ns }
        let start = mem.mark(a)
        let (xs, e2) = mem.alloc[f64](a, m * p)
        let (d, e3) = mem.alloc[f64](a, m * m)
        let (cl, e4) = mem.alloc[usize](a, m)
        let (lv, e5) = mem.alloc[usize](a, n + 2usize)
        if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, 0.0f64, Malformed) }
        var i = 0usize
        while i < m {
            var j = 0usize
            while j < p {
                xs[i * p + j] = x[(usize(perm[off + i]) - 1usize) * p + j]
                j += 1usize
            }
            cl[i] = clustering[usize(perm[off + i]) - 1usize]
            i += 1usize
        }
        fc.euclid(xs, m, p, d)
        // renumber the labels present to 1..cn in increasing order
        i = 0usize
        while i <= n + 1usize {
            lv[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < m {
            lv[cl[i]] = 1usize
            i += 1usize
        }
        var cn = 0usize
        i = 0usize
        while i <= n + 1usize {
            if lv[i] == 1usize {
                cn += 1usize
                lv[i] = cn
            }
            i += 1usize
        }
        i = 0usize
        while i < m {
            cl[i] = lv[cl[i]]
            i += 1usize
        }
        let (out, e6) = mem.alloc[f64](a, fp.cs_len(cn))
        if e6 != ok { ret (0.0f64, 0.0f64, Malformed) }
        var flags = 1usize
        if crit == 1usize { flags = 0usize }
        let e7 = fp.cstats(a, d, m, cl, cn, false, flags, true, 0.1f64, out)
        if e7 != ok { ret (0.0f64, 0.0f64, e7) }
        var v = out[5usize]
        if crit == 1usize { v = out[8usize] }
        mem.reset(a, start)
        sub[s] = v
        tot += f64(m) * v
        off += m
        s += 1usize
    }
    var sdv = 0.0f64
    let (ones, e8) = mem.alloc[usize](a, ns)
    let (cv, e9) = mem.alloc[f64](a, 1usize)
    if e8 != ok || e9 != ok { ret (0.0f64, 0.0f64, Malformed) }
    var i = 0usize
    while i < ns {
        ones[i] = 1usize
        i += 1usize
    }
    let (_, e10) = fp.cov_rows(a, sub, ns, 1usize, ones, 1usize, cv)
    if e10 != ok { ret (0.0f64, 0.0f64, e10) }
    sdv = math.sqrt[f64](cv[0usize])
    ret (tot / f64(n), sdv, ok)
}

// cvnn(d, clusterings, k): the clusterings are lc rows of n labels 1..max; idx, sep and comp get lc values
fn cvnn(a: *mem.Arena, d: []const f64, n: usize, cls: []const usize, lc: usize, k: usize, idx: []f64, sep: []f64, comp: []f64) -> err {
    let (nb, e1) = mem.alloc[usize](a, n * k)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        var q = 0usize
        while q < n {
            var rank = 0usize
            var r = 0usize
            while r < n {
                if d[i * n + r] < d[i * n + q] || (d[i * n + r] == d[i * n + q] && r < q) { rank += 1usize }
                r += 1usize
            }
            if rank >= 1usize && rank <= k { nb[i * k + rank - 1usize] = q }
            q += 1usize
        }
        i += 1usize
    }
    var l = 0usize
    while l < lc {
        var cnum = 0usize
        i = 0usize
        while i < n {
            if cls[l * n + i] > cnum { cnum = cls[l * n + i] }
            i += 1usize
        }
        var cs = 0.0f64
        var nji = 0.0f64
        var sepmax = -1.0e300f64
        var j = 1usize
        while j <= cnum {
            var nj = 0.0f64
            var sh = 0.0f64
            var sl = 0.0f64
            var outn = 0.0f64
            i = 0usize
            while i < n {
                if cls[l * n + i] == j {
                    nj += 1.0f64
                    var c = 0usize
                    while c < k {
                        if cls[l * n + nb[i * k + c]] != j { outn += 1.0f64 }
                        c += 1usize
                    }
                    var r = 0usize
                    while r < n {
                        if cls[l * n + r] == j {
                            let (h1, l1) = fp.dd_add(sh, sl, d[i * n + r], 0.0f64)
                            sh = h1
                            sl = l1
                        }
                        r += 1usize
                    }
                }
                i += 1usize
            }
            nji += nj * (nj - 1.0f64)
            cs = cs + (sh + sl)
            let sj = outn / (f64(k) * nj)
            if sj > sepmax { sepmax = sj }
            j += 1usize
        }
        sep[l] = sepmax
        comp[l] = cs / nji
        l += 1usize
    }
    var ms = -1.0e300f64
    var mc = -1.0e300f64
    l = 0usize
    while l < lc {
        if sep[l] > ms { ms = sep[l] }
        if comp[l] > mc { mc = comp[l] }
        l += 1usize
    }
    l = 0usize
    while l < lc {
        idx[l] = sep[l] / ms + comp[l] / mc
        l += 1usize
    }
    ret ok
}

// mahalanodisc(x2, mg, covg, modus): the Mahalanobis distances (squared, or its root for modus "md") of the n rows of x2
fn mahalanodisc(a: *mem.Arena, x2: []const f64, n: usize, p: usize, mg: []const f64, covg: []const f64, md: bool, out: []f64) -> err {
    let (cinv, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    let e2 = fp.lu_inverse(a, covg, p, cinv)
    if e2 != ok { ret e2 }
    let e3 = fc.mahal_rows(a, x2, n, p, mg, cinv, out)
    if e3 != ok { ret e3 }
    if md {
        var i = 0usize
        while i < n {
            out[i] = math.sqrt[f64](out[i])
            i += 1usize
        }
    }
    ret ok
}

// R's scale(x) (center and scale to unit sd) of the n by p matrix x
fn scale_cols(a: *mem.Arena, x: []const f64, n: usize, p: usize, out: []f64) -> err {
    let (ones, e1) = mem.alloc[usize](a, n)
    let (mu, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret Malformed }
    var i = 0usize
    while i < n {
        ones[i] = 1usize
        i += 1usize
    }
    fc.col_means(x, n, p, ones, 1usize, mu)
    var j = 0usize
    while j < p {
        var sh = 0.0f64
        var sl = 0.0f64
        i = 0usize
        while i < n {
            let v = x[i * p + j] - mu[j]
            out[i * p + j] = v
            let (h1, l1) = fp.dd_add(sh, sl, v * v, 0.0f64)
            sh = h1
            sl = l1
            i += 1usize
        }
        let sc = math.sqrt[f64]((sh + sl) / f64(n - 1usize))
        i = 0usize
        while i < n {
            out[i * p + j] = out[i * p + j] / sc
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// predict.dbscan(object, data, newdata): the cluster of the nearest seed point of each new point, 0 beyond eps
fn dbscan_predict(a: *mem.Arena, x: []const f64, n: usize, p: usize, cv: []const i64, isseed: []const bool, eps: f64, nw: []const f64, m: usize, out: []i64) {
    var i = 0usize
    while i < m {
        var bv = 1.0e300f64
        var bj = n
        var j = 0usize
        while j < n {
            if isseed[j] {
                var s = 0.0f64
                var q = 0usize
                while q < p {
                    let t = nw[i * p + q] - x[j * p + q]
                    s += t * t
                    q += 1usize
                }
                if s < bv {
                    bv = s
                    bj = j
                }
            }
            j += 1usize
        }
        out[i] = 0i64
        if bj < n {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                let t = x[bj * p + q] - nw[i * p + q]
                s += t * t
                q += 1usize
            }
            if math.sqrt[f64](s) <= eps { out[i] = cv[bj] }
        }
        i += 1usize
    }
}

// ---- cluster.varstats' remaining numbers: the clusterwise mean, sd and quartiles, table(clusteri, x) and the varwise tables of an uncategorised or categorised variable,
// with proportions.

// R's quantile(x, p) type 7 of the sorted s
fn q7r(s: []const f64, m: usize, p: f64) -> f64 {
    let index = 1.0f64 + f64(m - 1usize) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    var qs = s[usize(lo) - 1usize]
    let xh = s[usize(hi) - 1usize]
    if index > lo && xh != qs {
        let h = index - lo
        qs = (1.0f64 - h) * qs + h * xh
    }
    ret qs
}

// the mean, sd and the five quartile points (0, .25 .. 1) of the values of x whose cluster is i (all rows when i == 0): out[0] mean, out[1] sd, out[2..7] quantiles
fn clusterwise(a: *mem.Arena, x: []const f64, clustering: []const usize, n: usize, i: usize, out: []f64) -> err {
    let (v, e1) = mem.alloc[f64](a, n)
    let (ones, e2) = mem.alloc[usize](a, n)
    let (cv, e3) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret Malformed }
    var m = 0usize
    var r = 0usize
    while r < n {
        if i == 0usize || clustering[r] == i {
            v[m] = x[r]
            ones[m] = 1usize
            m += 1usize
        }
        r += 1usize
    }
    out[0usize] = fc.r_mean(v, m)
    let (_, e4) = fp.cov_rows(a, v, m, 1usize, ones, 1usize, cv)
    if e4 != ok { ret e4 }
    out[1usize] = math.sqrt[f64](cv[0usize])
    fp.cs_sort(v, m)
    var k = 0usize
    while k < 5usize {
        out[2usize + k] = q7r(v, m, f64(k) * 0.25f64)
        k += 1usize
    }
    ret ok
}

// the table of two integer-valued or real factors: the rows are the sorted distinct values of rows_v, the columns those of cols_v; counts[r * nc + c]; returns (nr, nc)
fn table2(a: *mem.Arena, rv: []const f64, cv: []const f64, n: usize, counts: []f64) -> (usize, usize, err) {
    let (ur, e1) = mem.alloc[f64](a, n)
    let (uc, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (0usize, 0usize, Malformed) }
    var nr = 0usize
    var nc = 0usize
    var i = 0usize
    while i < n {
        var f = false
        var j = 0usize
        while j < nr {
            if ur[j] == rv[i] { f = true }
            j += 1usize
        }
        if !f {
            ur[nr] = rv[i]
            nr += 1usize
        }
        f = false
        j = 0usize
        while j < nc {
            if uc[j] == cv[i] { f = true }
            j += 1usize
        }
        if !f {
            uc[nc] = cv[i]
            nc += 1usize
        }
        i += 1usize
    }
    fp.cs_sort(ur, nr)
    fp.cs_sort(uc, nc)
    i = 0usize
    while i < nr * nc {
        counts[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var r = 0usize
        while ur[r] != rv[i] { r += 1usize }
        var c = 0usize
        while uc[c] != cv[i] { c += 1usize }
        counts[r * nc + c] += 1.0f64
        i += 1usize
    }
    ret (nr, nc, ok)
}

// the varwise table of cluster.varstats for the variable x: cats > 0 categorises it (the quantile cut); rows are the clusters 1..ncl and the margin row (column sums);
// with prop every row is divided by its sum. out holds (ncl + 1) * nc values row-major; returns nc
fn varwise_table(a: *mem.Arena, x: []const f64, clustering: []const usize, n: usize, ncl: usize, cats: usize, prop: bool, out: []f64) -> (usize, err) {
    let (vx, e1) = mem.alloc[f64](a, n)
    let (cf, e2) = mem.alloc[f64](a, n)
    let (srt, e3) = mem.alloc[f64](a, n)
    let (cnt, e4) = mem.alloc[f64](a, ncl * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0usize, Malformed) }
    var i = 0usize
    while i < n {
        srt[i] = x[i]
        cf[i] = f64(clustering[i])
        i += 1usize
    }
    fp.cs_sort(srt, n)
    i = 0usize
    while i < n {
        vx[i] = x[i]
        if cats > 0usize {
            vx[i] = 1.0f64
            var j = 2usize
            while j <= cats {
                let q = q7r(srt, n, f64(j - 1usize) * (1.0f64 / f64(cats)))
                if x[i] > q { vx[i] = f64(j) }
                j += 1usize
            }
        }
        i += 1usize
    }
    let (nr, nc, e5) = table2(a, cf, vx, n, cnt)
    if e5 != ok { ret (0usize, e5) }
    var c = 0usize
    while c < nc {
        var s = 0.0f64
        var r = 0usize
        while r < nr {
            out[r * nc + c] = cnt[r * nc + c]
            s += cnt[r * nc + c]
            r += 1usize
        }
        out[nr * nc + c] = s
        c += 1usize
    }
    if prop {
        var r = 0usize
        while r <= nr {
            var s = 0.0f64
            c = 0usize
            while c < nc {
                s += out[r * nc + c]
                c += 1usize
            }
            c = 0usize
            while c < nc {
                out[r * nc + c] = out[r * nc + c] / s
                c += 1usize
            }
            r += 1usize
        }
    }
    ret (nc, ok)
}

// table(clusteri, x) with clusteri the 0/1 membership of cluster i: rows FALSE and TRUE (those present), as counts or proportions of the row; returns (rows, columns)
fn table_in_cluster(a: *mem.Arena, x: []const f64, clustering: []const usize, n: usize, i: usize, prop: bool, out: []f64) -> (usize, usize, err) {
    let (rv, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (0usize, 0usize, Malformed) }
    var r = 0usize
    while r < n {
        rv[r] = 0.0f64
        if clustering[r] == i { rv[r] = 1.0f64 }
        r += 1usize
    }
    let (nr, nc, e2) = table2(a, rv, x, n, out)
    if e2 != ok { ret (0usize, 0usize, e2) }
    if prop {
        r = 0usize
        while r < nr {
            var s = 0.0f64
            var c = 0usize
            while c < nc {
                s += out[r * nc + c]
                c += 1usize
            }
            c = 0usize
            while c < nc {
                out[r * nc + c] = out[r * nc + c] / s
                c += 1usize
            }
            r += 1usize
        }
    }
    ret (nr, nc, ok)
}
