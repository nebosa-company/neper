// R stats::kmeans (Hartigan-Wong, AS 136 as in R's kmns.f with its single-precision BIG), fpc::kmeansruns and fpc::pamk. Matrices are row-major; cluster labels are
// 1-based. R's random draws are taken in R's order: sample.int of the centers, then unique(x) when nstart >= 2 or the first draw holds a duplicate row.

use e.algo.rand.r as rg
use e.algo.stat.clusterpkg as cp
use e.algo.stat.fpc as fp
use e.algo.stat.fpc_misc as fm
use e.math
use e.mem

error Malformed

fn sqd_row(x: []const f64, xi: usize, c: []const f64, ci: usize, p: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < p {
        let t = x[xi * p + j] - c[ci * p + j]
        s += t * t
        j += 1usize
    }
    ret s
}

// OPTRA: indices i, l are 1-based as in the Fortran; the data row is i - 1 and the center row l - 1
fn optra(x: []const f64, m: usize, p: usize, c: []f64, k: usize, ic1: []usize, ic2: []usize, nc: []usize, an1: []f64, an2: []f64, ncp: []i64, d: []f64, itran: []usize, live: []i64, indx0: usize) -> usize {
    let big = f64(1.0e30f32)
    var indx = indx0
    var l = 1usize
    while l <= k {
        if itran[l] == 1usize { live[l] = i64(m) + 1i64 }
        l += 1usize
    }
    var i = 1usize
    var done = false
    while i <= m && !done {
        indx += 1usize
        let l1 = ic1[i]
        var l2 = ic2[i]
        let ll = l2
        if nc[l1] != 1usize {
            if ncp[l1] != 0i64 {
                d[i] = sqd_row(x, i - 1usize, c, l1 - 1usize, p) * an1[l1]
            }
            var r2 = sqd_row(x, i - 1usize, c, l2 - 1usize, p) * an2[l2]
            l = 1usize
            while l <= k {
                let skip = (i64(i) >= live[l1] && i64(i) >= live[l]) || l == l1 || l == ll
                if !skip {
                    let rr = r2 / an2[l]
                    var dc = 0.0f64
                    var early = false
                    var j = 0usize
                    while j < p && !early {
                        let dd = x[(i - 1usize) * p + j] - c[(l - 1usize) * p + j]
                        dc = dc + dd * dd
                        if dc >= rr { early = true }
                        j += 1usize
                    }
                    if !early {
                        r2 = dc * an2[l]
                        l2 = l
                    }
                }
                l += 1usize
            }
            if r2 >= d[i] {
                ic2[i] = l2
            } else {
                indx = 0usize
                live[l1] = i64(m + i)
                live[l2] = i64(m + i)
                ncp[l1] = i64(i)
                ncp[l2] = i64(i)
                let al1 = f64(nc[l1])
                let alw = al1 - 1.0f64
                let al2 = f64(nc[l2])
                let alt = al2 + 1.0f64
                var j = 0usize
                while j < p {
                    c[(l1 - 1usize) * p + j] = (c[(l1 - 1usize) * p + j] * al1 - x[(i - 1usize) * p + j]) / alw
                    c[(l2 - 1usize) * p + j] = (c[(l2 - 1usize) * p + j] * al2 + x[(i - 1usize) * p + j]) / alt
                    j += 1usize
                }
                nc[l1] -= 1usize
                nc[l2] += 1usize
                an2[l1] = alw / al1
                an1[l1] = big
                if alw > 1.0f64 { an1[l1] = alw / (alw - 1.0f64) }
                an1[l2] = alt / al2
                an2[l2] = alt / (alt + 1.0f64)
                ic1[i] = l2
                ic2[i] = l1
            }
        }
        if indx == m { done = true }
        i += 1usize
    }
    if !done {
        l = 1usize
        while l <= k {
            itran[l] = 0usize
            live[l] = live[l] - i64(m)
            l += 1usize
        }
    }
    ret indx
}

// QTRAN: returns (indx, maxq) with maxq -1 when the step limit was reached
fn qtran(x: []const f64, m: usize, p: usize, c: []f64, k: usize, ic1: []usize, ic2: []usize, nc: []usize, an1: []f64, an2: []f64, ncp: []i64, d: []f64, itran: []usize, indx0: usize, maxq0: i64) -> (usize, i64) {
    let big = f64(1.0e30f32)
    var indx = indx0
    var icoun = 0usize
    var istep = 0i64
    var fin = false
    var maxq = maxq0
    while !fin {
        var i = 1usize
        while i <= m && !fin {
            icoun += 1usize
            istep += 1i64
            if istep >= maxq0 {
                maxq = -1i64
                fin = true
            } else {
                let l1 = ic1[i]
                let l2 = ic2[i]
                if nc[l1] != 1usize {
                    if istep <= ncp[l1] {
                        d[i] = sqd_row(x, i - 1usize, c, l1 - 1usize, p) * an1[l1]
                    }
                    if istep < ncp[l1] || istep < ncp[l2] {
                        let r2 = d[i] / an2[l2]
                        var dd = 0.0f64
                        var early = false
                        var j = 0usize
                        while j < p && !early {
                            let de = x[(i - 1usize) * p + j] - c[(l2 - 1usize) * p + j]
                            dd = dd + de * de
                            if dd >= r2 { early = true }
                            j += 1usize
                        }
                        if !early {
                            icoun = 0usize
                            indx = 0usize
                            itran[l1] = 1usize
                            itran[l2] = 1usize
                            ncp[l1] = istep + i64(m)
                            ncp[l2] = istep + i64(m)
                            let al1 = f64(nc[l1])
                            let alw = al1 - 1.0f64
                            let al2 = f64(nc[l2])
                            let alt = al2 + 1.0f64
                            j = 0usize
                            while j < p {
                                c[(l1 - 1usize) * p + j] = (c[(l1 - 1usize) * p + j] * al1 - x[(i - 1usize) * p + j]) / alw
                                c[(l2 - 1usize) * p + j] = (c[(l2 - 1usize) * p + j] * al2 + x[(i - 1usize) * p + j]) / alt
                                j += 1usize
                            }
                            nc[l1] -= 1usize
                            nc[l2] += 1usize
                            an2[l1] = alw / al1
                            an1[l1] = big
                            if alw > 1.0f64 { an1[l1] = alw / (alw - 1.0f64) }
                            an1[l2] = alt / al2
                            an2[l2] = alt / (alt + 1.0f64)
                            ic1[i] = l2
                            ic2[i] = l1
                        }
                    }
                }
                if icoun == m { fin = true }
            }
            i += 1usize
        }
    }
    ret (indx, maxq)
}

// kmns: c is the k by p starting centers and receives the final ones; ic1 (m + 1) the 1-based labels, nc (k + 1) the sizes from index 1, wss (k) the
// within sums of squares. Returns (ifault, iter): 1 empty cluster, 2 no convergence, 3 bad k, 4 quick-transfer limit
fn kmns(a: *mem.Arena, x: []const f64, m: usize, p: usize, c: []f64, k: usize, iter_max: usize, ic1: []usize, nc: []usize, wss: []f64) -> (usize, usize, err) {
    let big = f64(1.0e30f32)
    if k <= 1usize || k >= m { ret (3usize, 0usize, ok) }
    let (ic2, e1) = mem.alloc[usize](a, m + 1usize)
    let (an1, e2) = mem.alloc[f64](a, k + 1usize)
    let (an2, e3) = mem.alloc[f64](a, k + 1usize)
    let (ncp, e4) = mem.alloc[i64](a, k + 1usize)
    let (itran, e5) = mem.alloc[usize](a, k + 1usize)
    let (live, e6) = mem.alloc[i64](a, k + 1usize)
    let (d, e7) = mem.alloc[f64](a, m + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0usize, 0usize, Malformed) }
    var i = 1usize
    while i <= m {
        ic1[i] = 1usize
        ic2[i] = 2usize
        var dt0 = sqd_row(x, i - 1usize, c, 0usize, p)
        var dt1 = sqd_row(x, i - 1usize, c, 1usize, p)
        if dt0 > dt1 {
            ic1[i] = 2usize
            ic2[i] = 1usize
            let t = dt0
            dt0 = dt1
            dt1 = t
        }
        var l = 3usize
        while l <= k {
            var db = 0.0f64
            var early = false
            var j = 0usize
            while j < p && !early {
                let dc = x[(i - 1usize) * p + j] - c[(l - 1usize) * p + j]
                db = db + dc * dc
                if db >= dt1 { early = true }
                j += 1usize
            }
            if !early {
                if db >= dt0 {
                    dt1 = db
                    ic2[i] = l
                } else {
                    dt1 = dt0
                    ic2[i] = ic1[i]
                    dt0 = db
                    ic1[i] = l
                }
            }
            l += 1usize
        }
        i += 1usize
    }
    var l = 1usize
    while l <= k {
        nc[l] = 0usize
        var j = 0usize
        while j < p {
            c[(l - 1usize) * p + j] = 0.0f64
            j += 1usize
        }
        l += 1usize
    }
    i = 1usize
    while i <= m {
        let li = ic1[i]
        nc[li] += 1usize
        var j = 0usize
        while j < p {
            c[(li - 1usize) * p + j] = c[(li - 1usize) * p + j] + x[(i - 1usize) * p + j]
            j += 1usize
        }
        i += 1usize
    }
    l = 1usize
    while l <= k {
        if nc[l] == 0usize { ret (1usize, 0usize, ok) }
        l += 1usize
    }
    l = 1usize
    while l <= k {
        let aa = f64(nc[l])
        var j = 0usize
        while j < p {
            c[(l - 1usize) * p + j] = c[(l - 1usize) * p + j] / aa
            j += 1usize
        }
        an2[l] = aa / (aa + 1.0f64)
        an1[l] = big
        if aa > 1.0f64 { an1[l] = aa / (aa - 1.0f64) }
        itran[l] = 1usize
        ncp[l] = -1i64
        l += 1usize
    }
    var indx = 0usize
    var maxq = i64(50usize * m)
    var ij = 1usize
    var fault = 0usize
    var fin = false
    while ij <= iter_max && !fin {
        indx = optra(x, m, p, c, k, ic1, ic2, nc, an1, an2, ncp, d, itran, live, indx)
        if indx == m {
            fin = true
        } else {
            let (ix, mq) = qtran(x, m, p, c, k, ic1, ic2, nc, an1, an2, ncp, d, itran, indx, maxq)
            indx = ix
            if mq < 0i64 {
                fault = 4usize
                fin = true
            } else if k == 2usize {
                fin = true
            } else {
                l = 1usize
                while l <= k {
                    ncp[l] = 0i64
                    l += 1usize
                }
            }
        }
        if !fin { ij += 1usize }
    }
    if !fin { fault = 2usize }
    l = 1usize
    while l <= k {
        wss[l - 1usize] = 0.0f64
        var j = 0usize
        while j < p {
            c[(l - 1usize) * p + j] = 0.0f64
            j += 1usize
        }
        l += 1usize
    }
    i = 1usize
    while i <= m {
        let li = ic1[i]
        var j = 0usize
        while j < p {
            c[(li - 1usize) * p + j] = c[(li - 1usize) * p + j] + x[(i - 1usize) * p + j]
            j += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < p {
        l = 1usize
        while l <= k {
            c[(l - 1usize) * p + j] = c[(l - 1usize) * p + j] / f64(nc[l])
            l += 1usize
        }
        i = 1usize
        while i <= m {
            let li = ic1[i]
            let da = x[(i - 1usize) * p + j] - c[(li - 1usize) * p + j]
            wss[li - 1usize] = wss[li - 1usize] + da * da
            i += 1usize
        }
        j += 1usize
    }
    ret (fault, ij, ok)
}

fn sum_dd(v: []const f64, n: usize) -> f64 {
    var h = 0.0f64
    var l = 0.0f64
    var i = 0usize
    while i < n {
        let (h1, l1) = fp.dd_add(h, l, v[i], 0.0f64)
        h = h1
        l = l1
        i += 1usize
    }
    ret h + l
}

fn rows_equal(x: []const f64, i: usize, j: usize, p: usize) -> bool {
    var q = 0usize
    while q < p {
        if x[i * p + q] != x[j * p + q] { ret false }
        q += 1usize
    }
    ret true
}

// kmeans(x, k, iter.max, nstart) with centers drawn by R. Fills cl (m + 1, 1-based), cent (k by p), wss (k), size (k + 1, from 1); info gets
// totss, tot.withinss, betweenss, iter, ifault. Returns ifault (1 is R's "empty cluster" error, 3 a bad k, else the Fortran one)
fn kmeans_hw(a: *mem.Arena, g: *rg.Rng, x: []const f64, m: usize, p: usize, k: usize, iter_max: usize, nstart: usize, cl: []usize, cent: []f64, wss: []f64, size: []usize, info: []f64) -> (usize, err) {
    let (ctr, e1) = mem.alloc[f64](a, k * p)
    let (cn, e2) = mem.alloc[f64](a, m * p)
    if e1 != ok || e2 != ok { ret (0usize, Malformed) }
    var mm = 0usize
    var i = 0usize
    var needu = nstart >= 2usize
    if nstart == 1usize {
        let (dr, e3) = rg.sample_int(a, g, i64(m), i64(k), false)
        if e3 != ok { ret (0usize, e3) }
        i = 0usize
        while i < k {
            var j = 0usize
            while j < p {
                ctr[i * p + j] = x[(usize(dr[i]) - 1usize) * p + j]
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < k {
            var j = i + 1usize
            while j < k {
                if rows_equal(ctr, i, j, p) { needu = true }
                j += 1usize
            }
            i += 1usize
        }
    }
    if needu {
        i = 0usize
        while i < m {
            var seen = false
            var q = 0usize
            while q < p {
                cn[mm * p + q] = x[i * p + q]
                q += 1usize
            }
            var j = 0usize
            while j < mm {
                if rows_equal(cn, j, mm, p) { seen = true }
                j += 1usize
            }
            if !seen { mm += 1usize }
            i += 1usize
        }
        if mm < k { ret (0usize, Malformed) }
        let (dr, e4) = rg.sample_int(a, g, i64(mm), i64(k), false)
        if e4 != ok { ret (0usize, e4) }
        i = 0usize
        while i < k {
            var j = 0usize
            while j < p {
                ctr[i * p + j] = cn[(usize(dr[i]) - 1usize) * p + j]
                j += 1usize
            }
            i += 1usize
        }
    }
    let (c1, e5) = mem.alloc[usize](a, m + 1usize)
    let (nc1, e6) = mem.alloc[usize](a, k + 1usize)
    let (w1, e7) = mem.alloc[f64](a, k)
    if e5 != ok || e6 != ok || e7 != ok { ret (0usize, Malformed) }
    let (flt, iter, e8) = kmns(a, x, m, p, ctr, k, iter_max, c1, nc1, w1)
    if e8 != ok { ret (0usize, e8) }
    if flt == 1usize || flt == 3usize { ret (flt, ok) }
    var itr = iter
    if flt == 2usize && itr < iter_max + 1usize { itr = iter_max + 1usize }
    var best = sum_dd(w1, k)
    i = 0usize
    while i <= m {
        cl[i] = c1[i]
        i += 1usize
    }
    i = 0usize
    while i < k * p {
        cent[i] = ctr[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        wss[i] = w1[i]
        i += 1usize
    }
    i = 0usize
    while i <= k {
        size[i] = nc1[i]
        i += 1usize
    }
    var fault = flt
    var itrb = itr
    var s = 2usize
    while nstart >= 2usize && s <= nstart {
        let (dr, e9) = rg.sample_int(a, g, i64(mm), i64(k), false)
        if e9 != ok { ret (0usize, e9) }
        i = 0usize
        while i < k {
            var j = 0usize
            while j < p {
                ctr[i * p + j] = cn[(usize(dr[i]) - 1usize) * p + j]
                j += 1usize
            }
            i += 1usize
        }
        let (f2, it2, e10) = kmns(a, x, m, p, ctr, k, iter_max, c1, nc1, w1)
        if e10 != ok { ret (0usize, e10) }
        if f2 == 1usize { ret (1usize, ok) }
        var it2b = it2
        if f2 == 2usize && it2b < iter_max + 1usize { it2b = iter_max + 1usize }
        let z = sum_dd(w1, k)
        if z < best {
            best = z
            fault = f2
            itrb = it2b
            i = 0usize
            while i <= m {
                cl[i] = c1[i]
                i += 1usize
            }
            i = 0usize
            while i < k * p {
                cent[i] = ctr[i]
                i += 1usize
            }
            i = 0usize
            while i < k {
                wss[i] = w1[i]
                i += 1usize
            }
            i = 0usize
            while i <= k {
                size[i] = nc1[i]
                i += 1usize
            }
        }
        s += 1usize
    }
    // totss = sum(scale(x, scale = FALSE)^2), column-major as R sums it
    var th = 0.0f64
    var tl = 0.0f64
    var j = 0usize
    while j < p {
        var mh = 0.0f64
        var ml = 0.0f64
        i = 0usize
        while i < m {
            let (h1, l1) = fp.dd_add(mh, ml, x[i * p + j], 0.0f64)
            mh = h1
            ml = l1
            i += 1usize
        }
        let mu = (mh + ml) / f64(m)
        i = 0usize
        while i < m {
            let v = x[i * p + j] - mu
            let (h2, l2) = fp.dd_add(th, tl, v * v, 0.0f64)
            th = h2
            tl = l2
            i += 1usize
        }
        j += 1usize
    }
    info[0usize] = th + tl
    info[1usize] = best
    info[2usize] = th + tl - best
    info[3usize] = f64(itrb)
    info[4usize] = f64(fault)
    ret (fault, ok)
}

fn euclid_full(data: []const f64, n: usize, p: usize, d: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            d[i * n + j] = math.sqrt[f64](sqd_row(data, i, data, j, p))
            j += 1usize
        }
        i += 1usize
    }
}

// kmeansruns(data, krange, criterion, iter.max, runs, scaledata, alpha, nstart); crit_asw false is "ch". krange lists the k values (2 must be there when 1 is).
// Outputs for the chosen k: cl (n + 1), cent, wss, size (k + 1), info as kmeans_hw; crit (maxk + 1, from index 1). Returns the bestk
fn kmeansruns(a: *mem.Arena, g: *rg.Rng, data0: []const f64, n: usize, p: usize, krange: []const usize, nk: usize, crit_asw: bool, iter_max: usize, runs: usize, scaledata: bool, alpha: f64, nstart: usize, cl: []usize, cent: []f64, wss: []f64, size: []usize, info: []f64, crit: []f64) -> (usize, err) {
    var data = data0
    if scaledata {
        let (sd, e0) = mem.alloc[f64](a, n * p)
        if e0 != ok { ret (0usize, Malformed) }
        let e00 = fm.scale_cols(a, data0, n, p, sd)
        if e00 != ok { ret (0usize, e00) }
        data = sd
    }
    var maxk = 0usize
    var cluster1 = false
    var q = 0usize
    while q < nk {
        if krange[q] > maxk { maxk = krange[q] }
        if krange[q] == 1usize { cluster1 = true }
        q += 1usize
    }
    let (sdist, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (0usize, Malformed) }
    if crit_asw { euclid_full(data, n, p, sdist) }
    let (kcl, e2) = mem.alloc[usize](a, (maxk + 1usize) * (n + 1usize))
    let (kcent, e3) = mem.alloc[f64](a, (maxk + 1usize) * maxk * p)
    let (kwss, e4) = mem.alloc[f64](a, (maxk + 1usize) * maxk)
    let (ksize, e5) = mem.alloc[usize](a, (maxk + 1usize) * (maxk + 1usize))
    let (kinfo, e6) = mem.alloc[f64](a, (maxk + 1usize) * 5usize)
    let (tcl, e7) = mem.alloc[usize](a, n + 1usize)
    let (tcent, e8) = mem.alloc[f64](a, maxk * p)
    let (twss, e9) = mem.alloc[f64](a, maxk)
    let (tsize, e10) = mem.alloc[usize](a, maxk + 1usize)
    let (tinfo, e11) = mem.alloc[f64](a, 5usize)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (0usize, Malformed) }
    var i = 0usize
    while i <= maxk {
        crit[i] = 0.0f64
        i += 1usize
    }
    q = 0usize
    while q < nk {
        let k = krange[q]
        if k > 1usize {
            var minss = 1.0f64 / 0.0f64
            var r = 0usize
            while r < runs {
                var tries = 0usize
                var okk = false
                while !okk && tries < 1000usize {
                    let (f, e12) = kmeans_hw(a, g, data, n, p, k, iter_max, nstart, tcl, tcent, twss, tsize, tinfo)
                    if e12 != ok { ret (0usize, e12) }
                    if f != 1usize { okk = true }
                    tries += 1usize
                }
                if !okk { ret (0usize, Malformed) }
                let swss = sum_dd(twss, k)
                if swss < minss {
                    minss = swss
                    i = 0usize
                    while i <= n {
                        kcl[k * (n + 1usize) + i] = tcl[i]
                        i += 1usize
                    }
                    i = 0usize
                    while i < k * p {
                        kcent[k * maxk * p + i] = tcent[i]
                        i += 1usize
                    }
                    i = 0usize
                    while i < k {
                        kwss[k * maxk + i] = twss[i]
                        i += 1usize
                    }
                    i = 0usize
                    while i <= k {
                        ksize[k * (maxk + 1usize) + i] = tsize[i]
                        i += 1usize
                    }
                    i = 0usize
                    while i < 5usize {
                        kinfo[k * 5usize + i] = tinfo[i]
                        i += 1usize
                    }
                }
                r += 1usize
            }
            let (lab, e13) = mem.alloc[usize](a, n)
            if e13 != ok { ret (0usize, Malformed) }
            i = 0usize
            while i < n {
                lab[i] = kcl[k * (n + 1usize) + i + 1usize]
                i += 1usize
            }
            if crit_asw {
                let (cs, e14) = mem.alloc[f64](a, fp.cs_len(k))
                if e14 != ok { ret (0usize, Malformed) }
                let e15 = fp.cstats(a, sdist, n, lab, k, false, 1usize, false, 0.1f64, cs)
                if e15 != ok { ret (0usize, e15) }
                crit[k] = cs[5usize]
            } else {
                let (ch, e16) = fp.calinhara(a, data, n, p, lab, k)
                if e16 != ok { ret (0usize, e16) }
                crit[k] = ch
            }
        }
        q += 1usize
    }
    if cluster1 {
        let (lab2, e17) = mem.alloc[usize](a, n)
        let (dh, e18) = mem.alloc[f64](a, 6usize)
        if e17 != ok || e18 != ok { ret (0usize, Malformed) }
        i = 0usize
        while i < n {
            lab2[i] = kcl[2usize * (n + 1usize) + i + 1usize]
            i += 1usize
        }
        let e19 = fm.dudahart2(a, data, n, p, lab2, alpha, dh)
        if e19 != ok { ret (0usize, e19) }
        cluster1 = dh[3usize] > 0.5f64
    }
    var kbest = 1usize
    var best = -1.0f64 / 0.0f64
    i = 1usize
    while i <= maxk {
        if crit[i] > best {
            best = crit[i]
            kbest = i
        }
        i += 1usize
    }
    if cluster1 { kbest = 1usize }
    if kbest >= 2usize {
        i = 0usize
        while i <= n {
            cl[i] = kcl[kbest * (n + 1usize) + i]
            i += 1usize
        }
        i = 0usize
        while i < kbest * p {
            cent[i] = kcent[kbest * maxk * p + i]
            i += 1usize
        }
        i = 0usize
        while i < kbest {
            wss[i] = kwss[kbest * maxk + i]
            i += 1usize
        }
        i = 0usize
        while i <= kbest {
            size[i] = ksize[kbest * (maxk + 1usize) + i]
            i += 1usize
        }
        i = 0usize
        while i < 5usize {
            info[i] = kinfo[kbest * 5usize + i]
            i += 1usize
        }
    }
    ret (kbest, ok)
}

// pamk(data, krange, criterion, usepam = TRUE, scaling, alpha, diss, ns, seed): crit_kind 0 asw, 1 multiasw, 2 ch. data is n by p, or n by n dissimilarities
// when diss. Fills cl (n, 1-based), med (the medoid rows of the chosen k, 1-based) and crit (maxk + 1, from index 1, entry 1 holding dudahart2's
// p.value when 1 is in krange and not diss). Returns nc
fn pamk(a: *mem.Arena, data0: []const f64, n: usize, p: usize, krange: []const usize, nk: usize, crit_kind: usize, scaling: bool, alpha: f64, diss: bool, ns: usize, seedv: i64, cl: []usize, med: []usize, crit: []f64) -> (usize, err) {
    var sdata = data0
    if scaling && !diss {
        let (sd, e0) = mem.alloc[f64](a, n * p)
        if e0 != ok { ret (0usize, Malformed) }
        let e00 = fm.scale_cols(a, data0, n, p, sd)
        if e00 != ok { ret (0usize, e00) }
        sdata = sd
    }
    var maxk = 0usize
    var cluster1 = false
    var q = 0usize
    while q < nk {
        if krange[q] > maxk { maxk = krange[q] }
        if krange[q] == 1usize { cluster1 = true }
        q += 1usize
    }
    let (dfull, e1) = mem.alloc[f64](a, n * n)
    let (dys, e2) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
    if e1 != ok || e2 != ok { ret (0usize, Malformed) }
    var i = 0usize
    if diss {
        i = 0usize
        while i < n * n {
            dfull[i] = sdata[i]
            i += 1usize
        }
    } else {
        euclid_full(sdata, n, p, dfull)
    }
    cp.pack_full(dfull, n, dys)
    let (pcl, e3) = mem.alloc[usize](a, (maxk + 1usize) * n)
    let (pmed, e4) = mem.alloc[usize](a, (maxk + 1usize) * maxk)
    if e3 != ok || e4 != ok { ret (0usize, Malformed) }
    i = 0usize
    while i <= maxk {
        crit[i] = 0.0f64
        i += 1usize
    }
    q = 0usize
    while q < nk {
        let k = krange[q]
        if k >= 2usize && k < n {
            let (given, e5) = mem.alloc[usize](a, 1usize)
            if e5 != ok { ret (0usize, Malformed) }
            let (fit, e6) = cp.pam(a, dys, n, k, given, false, true, 0usize, true)
            if e6 != ok { ret (0usize, e6) }
            i = 0usize
            while i < n {
                pcl[k * n + i] = fit.clu[i]
                i += 1usize
            }
            i = 0usize
            while i < k {
                pmed[k * maxk + i] = fit.med[i]
                i += 1usize
            }
            if crit_kind == 0usize {
                crit[k] = fit.ttsil
            } else if crit_kind == 1usize {
                let (sub, e7) = mem.alloc[f64](a, ns)
                if e7 != ok { ret (0usize, Malformed) }
                let (ov, _, e8) = fm.distcritmulti(a, sdata, n, p, fit.clu, ns, 0usize, seedv, sub)
                if e8 != ok { ret (0usize, e8) }
                crit[k] = ov
            } else {
                if diss {
                    let (cs, e9) = mem.alloc[f64](a, fp.cs_len(k))
                    if e9 != ok { ret (0usize, Malformed) }
                    let e10 = fp.cstats(a, dfull, n, fit.clu, k, false, 0usize, false, 0.1f64, cs)
                    if e10 != ok { ret (0usize, e10) }
                    crit[k] = cs[13usize]
                } else {
                    let (ch, e11) = fp.calinhara(a, sdata, n, p, fit.clu, k)
                    if e11 != ok { ret (0usize, e11) }
                    crit[k] = ch
                }
            }
        }
        q += 1usize
    }
    var kbest = 1usize
    var best = -1.0f64 / 0.0f64
    i = 1usize
    while i <= maxk {
        if crit[i] > best {
            best = crit[i]
            kbest = i
        }
        i += 1usize
    }
    if cluster1 {
        if !diss {
            let (dh, e12) = mem.alloc[f64](a, 6usize)
            let (lab2, e13) = mem.alloc[usize](a, n)
            if e12 != ok || e13 != ok { ret (0usize, Malformed) }
            i = 0usize
            while i < n {
                lab2[i] = pcl[2usize * n + i]
                i += 1usize
            }
            let e14 = fm.dudahart2(a, sdata, n, p, lab2, alpha, dh)
            if e14 != ok { ret (0usize, e14) }
            crit[1usize] = dh[0usize]
            if dh[3usize] > 0.5f64 { kbest = 1usize }
        }
    }
    if kbest >= 2usize {
        i = 0usize
        while i < n {
            cl[i] = pcl[kbest * n + i]
            i += 1usize
        }
        i = 0usize
        while i < kbest {
            med[i] = pmed[kbest * maxk + i]
            i += 1usize
        }
    }
    ret (kbest, ok)
}
