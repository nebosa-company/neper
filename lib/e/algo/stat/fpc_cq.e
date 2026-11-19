// R fpc: cqcluster.stats (the cluster quality indices of Hennig's cluster benchmark) on a dissimilarity matrix d (n by n row-major) and labels 1..cn. The
// indices shared with cluster.stats come from fp.cstats.
//
// out: scalars 0 n, 1 cluster.number, 2 min.cluster.size, 3 noisen, 4 avebetween, 5 avewithin, 6 maxdiameter, 7 minsep, 8 withinss, 9 asw, 10 g2, 11 g3, 12 pearsongamma,
// 13 dunn, 14 dunn2, 15 entropy, 16 wb.ratio, 17 ch, 18 widestgap, 19 corrected.rand, 20 vi, 21 sindex, 22 stan, 23 mnnd, 24 pamc, 25 dindex, 26 denscut, 27 highdgap,
// 28 parsimony, 29 cvnnd, 30 n.between, 31 n.within, 32 length of svec; from 40: cvnndc[cn], npenalty[cn], dpenalty[cn], pamcentroids[cn], then n slots each:
// withindensp, densoc, percwdens, percdensoc, psep, svec, pclosetomode, distto, pdistto (the last three flattened over the clusters in order, the first entry of a cluster's
// distto and pdistto, which R leaves NA, is 0). A value R leaves NA is NaN.

use e.algo.stat.fpc as fp
use e.algo.stat.fpc_coord as fc
use e.algo.stat.fpc_misc as fm
use e.math
use e.mem

error Malformed

fn cq_len(cn: usize, n: usize) -> usize { ret 40usize + 4usize * cn + 9usize * n }

fn sorted(v: []f64, m: usize) { fp.cs_sort(v, m) }

fn dsm(v: []const f64, m: usize) -> f64 {
    var sh = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < m {
        let (h1, l1) = fp.dd_add(sh, sl, v[i], 0.0f64)
        sh = h1
        sl = l1
        i += 1usize
    }
    ret sh + sl
}

// sd of m values (var's two pass mean, extended sums)
fn sd_r(v: []const f64, m: usize) -> f64 {
    let mu = fc.r_mean(v, m)
    var sh = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < m {
        let t = v[i] - mu
        let (h1, l1) = fp.dd_add(sh, sl, t * t, 0.0f64)
        sh = h1
        sl = l1
        i += 1usize
    }
    ret math.sqrt[f64]((sh + sl) / f64(m - 1usize))
}

// stdmode 0 max, 1 ave, 2 q90, 3 none; flags: 1 silhouette 2 G2 4 G3 8 wgap 16 averagegap; alt holds the labels 1..k2 of alt.clustering (k2 = 0: none)
fn cq(a: *mem.Arena, d: []const f64, n: usize, cl: []const usize, cn: usize, noise: bool, flags: usize, stdmode: usize, sepall: bool, sepwn: bool, sepprob: f64, dq: f64, nnk: usize, nndist: bool, alt: []const usize, k2: usize, out: []f64) -> err {
    let nan = 0.0f64 / 0.0f64
    var cwn = cn
    var noisen = 0usize
    var i = 0usize
    while i < cq_len(cn, n) {
        out[i] = nan
        i += 1usize
    }
    if noise { cwn = cn - 1usize }
    // R stops on sepall = FALSE (svec is never defined), so only the sepall path exists
    if !sepall { ret Malformed }
    i = 0usize
    while i < n {
        if noise && cl[i] == cn { noisen += 1usize }
        i += 1usize
    }
    let pairs = n * (n - 1usize) / 2usize
    let (cs, e1) = mem.alloc[f64](a, fp.cs_len(cn))
    let (dp, e2) = mem.alloc[f64](a, pairs)
    let (size, e3) = mem.alloc[f64](a, cn)
    let (pk1, e4) = mem.alloc[f64](a, cn)
    let (tmp, e5) = mem.alloc[f64](a, n)
    let (tmp2, e6) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret Malformed }
    let e0 = fp.cstats(a, d, n, cl, cn, noise, flags & 15usize, sepwn, sepprob, cs)
    if e0 != ok { ret e0 }
    let vb = 24usize
    var np = 0usize
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            dp[np] = d[i * n + j]
            np += 1usize
            j += 1usize
        }
        i += 1usize
    }
    var stan = 1.0f64
    var dmax = dp[0usize]
    var dsq = 0.0f64
    i = 0usize
    while i < pairs {
        if dp[i] > dmax { dmax = dp[i] }
        i += 1usize
    }
    // overall.ss = sum(d^2) / n
    var sh = 0.0f64
    var sl = 0.0f64
    i = 0usize
    while i < pairs {
        let (h1, l1) = fp.dd_add(sh, sl, dp[i] * dp[i], 0.0f64)
        sh = h1
        sl = l1
        i += 1usize
    }
    dsq = (sh + sl) / f64(n)
    let (sp, e7) = mem.alloc[f64](a, pairs)
    if e7 != ok { ret Malformed }
    i = 0usize
    while i < pairs {
        sp[i] = dp[i]
        i += 1usize
    }
    sorted(sp, pairs)
    if stdmode == 0usize { stan = dmax }
    if stdmode == 1usize { stan = fc.r_mean(dp, pairs) }
    if stdmode == 2usize { stan = fm.q7r(sp, pairs, 0.9f64) }
    let std = stdmode != 3usize
    i = 0usize
    while i < cn {
        size[i] = cs[vb + i]
        pk1[i] = size[i] / f64(n)
        i += 1usize
    }
    out[0usize] = f64(n)
    out[1usize] = f64(cn)
    var mcs = size[0usize]
    i = 1usize
    while i < cwn {
        if size[i] < mcs { mcs = size[i] }
        i += 1usize
    }
    out[2usize] = mcs
    out[3usize] = f64(noisen)
    out[4usize] = cs[0usize] / stan
    out[5usize] = cs[1usize] / stan
    out[6usize] = cs[2usize] / stan
    out[7usize] = cs[3usize] / stan
    var wss = cs[4usize]
    if std { wss = wss / dsq }
    out[8usize] = wss
    out[9usize] = cs[5usize]
    out[10usize] = cs[6usize]
    out[11usize] = cs[7usize]
    var pg = cs[8usize]
    if std { pg = (pg + 1.0f64) / 2.0f64 }
    out[12usize] = pg
    out[13usize] = cs[9usize]
    out[14usize] = cs[10usize]
    out[16usize] = out[5usize] / out[4usize]
    out[17usize] = cs[13usize]
    out[30usize] = cs[18usize]
    out[31usize] = cs[19usize]
    if (flags & 8usize) != 0usize {
        let wg = cs[vb + 7usize * cn..vb + 8usize * cn]
        if (flags & 16usize) != 0usize {
            out[18usize] = fc.r_mean(wg, cwn) / stan
        } else {
            var m = wg[0usize]
            i = 1usize
            while i < cwn {
                if wg[i] > m { m = wg[i] }
                i += 1usize
            }
            out[18usize] = m / stan
        }
    }
    // entropy
    var k = 0usize
    i = 0usize
    while i < cn {
        if pk1[i] > 0.0f64 {
            tmp[k] = pk1[i] * math.log[f64](pk1[i])
            k += 1usize
        }
        i += 1usize
    }
    var h1v = 0.0f64 - dsm(tmp, k)
    if std {
        i = 0usize
        while i < cn {
            let pm = 1.0f64 / f64(cn)
            tmp[i] = pm * math.log[f64](pm)
            i += 1usize
        }
        h1v = 0.0f64 - h1v / dsm(tmp, cn)
    }
    out[15usize] = h1v
    if k2 > 0usize {
        out[19usize] = fp.compare(a, cl, cn, alt, k2, 16usize)
        let (cs2, e8) = mem.alloc[f64](a, k2)
        let (nij, e9) = mem.alloc[f64](a, cn * k2)
        if e8 != ok || e9 != ok { ret Malformed }
        i = 0usize
        while i < k2 {
            cs2[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < cn * k2 {
            nij[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            cs2[alt[i] - 1usize] += 1.0f64
            nij[(cl[i] - 1usize) * k2 + alt[i] - 1usize] += 1.0f64
            i += 1usize
        }
        var kk = 0usize
        i = 0usize
        while i < k2 {
            let q = cs2[i] / f64(n)
            if q > 0.0f64 {
                tmp[kk] = q * math.log[f64](q)
                kk += 1usize
            }
            i += 1usize
        }
        let h2 = 0.0f64 - dsm(tmp, kk)
        var icc = 0.0f64
        i = 0usize
        while i < cn {
            var j = 0usize
            while j < k2 {
                let p12 = nij[i * k2 + j] / f64(n)
                if p12 > 0.0f64 { icc += p12 * math.log[f64](p12 / (pk1[i] * (cs2[j] / f64(n)))) }
                j += 1usize
            }
            i += 1usize
        }
        out[20usize] = h1v + h2 - 2.0f64 * icc
    }
    out[22usize] = stan
    out[28usize] = f64(cn) / 10.0f64
    let cb = 40usize
    // sindex, psep, svec
    let pb = cb + 4usize * cn + 4usize * n
    let sb = cb + 4usize * cn + 5usize * n
    i = 0usize
    while i < n {
        var mi = 0.0f64
        var first = true
        var j = 0usize
        while j < n {
            if cl[j] != cl[i] {
                if first || d[i * n + j] < mi { mi = d[i * n + j] }
                first = false
            }
            j += 1usize
        }
        out[pb + i] = mi
        i += 1usize
    }
    var nsv = 0usize
    if sepall {
        var lcn = cwn
        if sepwn && noise { lcn = cwn + 1usize }
        var j = 0usize
        while j < lcn {
            var m = 0usize
            i = 0usize
            while i < n {
                if cl[i] == j + 1usize {
                    tmp[m] = out[pb + i]
                    tmp2[m] = out[pb + i]
                    m += 1usize
                }
                i += 1usize
            }
            sorted(tmp2, m)
            let q = fm.q7r(tmp2, m, sepprob)
            i = 0usize
            while i < m {
                if tmp[i] <= q {
                    out[sb + nsv] = tmp[i]
                    nsv += 1usize
                }
                i += 1usize
            }
            j += 1usize
        }
        out[21usize] = fc.r_mean(out[sb..sb + nsv], nsv) / stan
    }
    out[32usize] = f64(nsv)
    // pamc
    var pamc = 0.0f64
    var c = 0usize
    while c < cwn {
        var mind = 1.0f64 / 0.0f64
        var j = 0usize
        while j < n {
            if cl[j] == c + 1usize {
                var q = 0usize
                var m = 0usize
                while q < n {
                    if cl[q] == c + 1usize {
                        tmp[m] = d[j * n + q]
                        m += 1usize
                    }
                    q += 1usize
                }
                let ds = dsm(tmp, m)
                if ds <= mind {
                    mind = ds
                    out[cb + 3usize * cn + c] = f64(j + 1usize)
                }
            }
            j += 1usize
        }
        pamc += mind
        c += 1usize
    }
    out[24usize] = pamc / (f64(n) * stan)
    // densities
    let cutdist = fm.q7r(sp, pairs, dq)
    let wb = cb + 4usize * cn
    i = 0usize
    while i < n {
        out[wb + i] = 0.0f64
        out[wb + n + i] = 0.0f64
        i += 1usize
    }
    c = 0usize
    while c < cwn {
        var j = 0usize
        while j < n {
            if cl[j] == c + 1usize {
                var s1 = 0.0f64
                var s2 = 0.0f64
                var q = 0usize
                while q < n {
                    var lw = 0.0f64
                    if d[j * n + q] < cutdist { lw = (0.0f64 - d[j * n + q]) / cutdist + 1.0f64 }
                    s1 += lw
                    if cl[q] != c + 1usize { s2 += lw }
                    q += 1usize
                }
                out[wb + j] = s1
                out[wb + n + j] = s2
            }
            j += 1usize
        }
        c += 1usize
    }
    var mwd = out[wb]
    i = 1usize
    while i < n {
        if out[wb + i] > mwd { mwd = out[wb + i] }
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[wb + 2usize * n + i] = out[wb + i] / mwd
        out[wb + 3usize * n + i] = out[wb + n + i] / mwd
        i += 1usize
    }
    c = 0usize
    while c < cwn {
        var s = 0.0f64
        i = 0usize
        while i < n {
            if cl[i] == c + 1usize { s += out[wb + 3usize * n + i] * out[wb + 2usize * n + i] }
            i += 1usize
        }
        out[cb + cn + c] = s
        out[cb + 2usize * cn + c] = 0.0f64
        c += 1usize
    }
    let (dm, e10) = mem.alloc[f64](a, n * n)
    let (oidx, e11) = mem.alloc[usize](a, n)
    let (ctm, e12) = mem.alloc[usize](a, n)
    let (minval, e13) = mem.alloc[f64](a, n)
    let (thg, e14) = mem.alloc[f64](a, n)
    if e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret Malformed }
    var nth = 0usize
    var fcur = 0usize
    let inf = 1.0f64 / 0.0f64
    c = 0usize
    while c < cwn {
        var m = 0usize
        i = 0usize
        while i < n {
            if cl[i] == c + 1usize {
                oidx[m] = i
                m += 1usize
            }
            i += 1usize
        }
        var r = 0usize
        while r < m {
            var q = 0usize
            while q < m {
                dm[r * m + q] = d[oidx[r] * n + oidx[q]]
                q += 1usize
            }
            r += 1usize
        }
        if m > 0usize {
            var mode = 0usize
            r = 1usize
            while r < m {
                if out[wb + oidx[r]] > out[wb + oidx[mode]] { mode = r }
                r += 1usize
            }
            var q = 0usize
            while q < m {
                dm[mode * m + q] = inf
                q += 1usize
            }
            ctm[0usize] = mode
            out[wb + 7usize * n + fcur] = 0.0f64
            out[wb + 8usize * n + fcur] = 0.0f64
            var j = 1usize
            while j < m {
                r = 0usize
                while r < m {
                    var mv = dm[r * m + ctm[0usize]]
                    var t = 1usize
                    while t < j {
                        if dm[r * m + ctm[t]] < mv { mv = dm[r * m + ctm[t]] }
                        t += 1usize
                    }
                    minval[r] = mv
                    r += 1usize
                }
                var mrem = 0.0f64 - inf
                r = 0usize
                while r < m {
                    var inctm = false
                    var t = 0usize
                    while t < j {
                        if ctm[t] == r { inctm = true }
                        t += 1usize
                    }
                    if !inctm && out[wb + 2usize * n + oidx[r]] > mrem { mrem = out[wb + 2usize * n + oidx[r]] }
                    r += 1usize
                }
                var best = 0usize
                r = 1usize
                while r < m {
                    if minval[r] < minval[best] { best = r }
                    r += 1usize
                }
                ctm[j] = best
                var mt = 0usize
                var t = 1usize
                while t < j {
                    if dm[best * m + ctm[t]] < dm[best * m + ctm[mt]] { mt = t }
                    t += 1usize
                }
                let minctm = oidx[ctm[mt]]
                let newp = oidx[best]
                thg[nth] = minval[best] * mrem
                nth += 1usize
                let dto = out[wb + 2usize * n + newp] - out[wb + 2usize * n + minctm]
                out[wb + 7usize * n + fcur + j] = dto
                if out[wb + 2usize * n + newp] > out[wb + 2usize * n + minctm] { out[cb + 2usize * cn + c] += dto * dto }
                q = 0usize
                while q < m {
                    dm[best * m + q] = inf
                    q += 1usize
                }
                out[wb + 8usize * n + fcur + j] = f64(minctm + 1usize)
                j += 1usize
            }
            j = 0usize
            while j < m {
                out[wb + 6usize * n + fcur + j] = f64(oidx[ctm[j]] + 1usize)
                j += 1usize
            }
            fcur += m
        }
        c += 1usize
    }
    var hg = thg[0usize]
    i = 1usize
    while i < nth {
        if thg[i] > hg { hg = thg[i] }
        i += 1usize
    }
    if std { hg = hg / stan }
    out[27usize] = hg
    out[25usize] = math.sqrt[f64](dsm(out[cb + 2usize * cn..cb + 3usize * cn], cwn) / f64(n))
    out[26usize] = dsm(out[cb + cn..cb + 2usize * cn], cwn) / f64(n)
    // nearest neighbour distances
    if nndist {
        var nnd = 0usize
        var sw = 0.0f64
        var sx = 0.0f64
        let (allnnd, e15) = mem.alloc[f64](a, n)
        let (row, e16) = mem.alloc[f64](a, n)
        let (wx, e17) = mem.alloc[f64](a, cn)
        let (ww, e18) = mem.alloc[f64](a, cn)
        if e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret Malformed }
        var nw = 0usize
        c = 0usize
        while c < cn {
            if size[c] > f64(nnk) {
                var m = 0usize
                i = 0usize
                while i < n {
                    if cl[i] == c + 1usize {
                        var q = 0usize
                        var mm = 0usize
                        while q < n {
                            if cl[q] == c + 1usize {
                                row[mm] = d[i * n + q]
                                mm += 1usize
                            }
                            q += 1usize
                        }
                        sorted(row, mm)
                        tmp[m] = row[nnk]
                        allnnd[nnd] = row[nnk]
                        nnd += 1usize
                        m += 1usize
                    }
                    i += 1usize
                }
                let cv = sd_r(tmp, m) / fc.r_mean(tmp, m)
                out[cb + c] = cv
                if cv == cv {
                    wx[nw] = cv * pk1[c]
                    ww[nw] = pk1[c]
                    nw += 1usize
                }
            }
            c += 1usize
        }
        sw = dsm(ww, nw)
        sx = dsm(wx, nw)
        var cvnnd = sx / sw
        var mnnd = fc.r_mean(allnnd, nnd)
        if std {
            var mx = 0.0f64
            i = 0usize
            while i < n {
                var q = 0usize
                while q < n {
                    row[q] = d[i * n + q]
                    q += 1usize
                }
                sorted(row, n)
                if row[nnk] > mx { mx = row[nnk] }
                i += 1usize
            }
            mnnd = mnnd / mx
            cvnnd = cvnnd / math.sqrt[f64](f64(n))
        }
        out[23usize] = mnnd
        out[29usize] = cvnnd
    }
    ret ok
}
