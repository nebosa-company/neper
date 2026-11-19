// R fpc: findrep and cdbw (cluster density based validity). Matrices are row-major.

use e.algo.stat.fpc as fp
use e.algo.stat.fpc_coord as fc
use e.math
use e.mem

error Malformed

// mahalanobis(row, centre, diag(p)): the squared distance, summed in extended precision as rowSums does
fn sqd(x: []const f64, at: usize, p: usize, ctr: []const f64) -> f64 {
    var sh = 0.0f64
    var sl = 0.0f64
    var j = 0usize
    while j < p {
        let d = x[at * p + j] - ctr[j]
        let (h1, l1) = fp.dd_add(sh, sl, d * d, 0.0f64)
        sh = h1
        sl = l1
        j += 1usize
    }
    ret sh + sl
}

fn dsum(v: []const f64, m: usize) -> f64 {
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

// findrep for the cluster whose rows are xc (nc by p): repxi gets the local indices of the representatives (r of them at most); the count and wvar are returned
fn findrep(a: *mem.Arena, xc: []const f64, nc: usize, p: usize, xcen: []const f64, r: usize, repxi: []usize) -> (usize, f64, err) {
    let (d1, e1) = mem.alloc[f64](a, nc)
    let (mn, e2) = mem.alloc[f64](a, nc)
    let (cen, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret (0usize, 0.0f64, Malformed) }
    var i = 0usize
    while i < nc {
        d1[i] = sqd(xc, i, p, xcen)
        i += 1usize
    }
    var wvar = 0.0f64
    if nc > 1usize { wvar = dsum(d1, nc) / f64(nc - 1usize) }
    var best = 0usize
    i = 1usize
    while i < nc {
        if d1[i] > d1[best] { best = i }
        i += 1usize
    }
    repxi[0usize] = best
    var maxr = r
    var ri = 1usize
    while ri < r {
        var j = 0usize
        while j < p {
            cen[j] = xc[repxi[ri - 1usize] * p + j]
            j += 1usize
        }
        i = 0usize
        while i < nc {
            let dd = sqd(xc, i, p, cen)
            if ri == 1usize || dd < mn[i] { mn[i] = dd }
            i += 1usize
        }
        var bi = 0usize
        i = 1usize
        while i < nc {
            if mn[i] > mn[bi] { bi = i }
            i += 1usize
        }
        if mn[bi] > 0.0f64 {
            repxi[ri] = bi
        } else {
            maxr = ri
            break
        }
        ri += 1usize
    }
    ret (maxr, wvar, ok)
}

// cdbw(x, clustering, r, s, clusterstdev): out gets cdbw, cohesion, compactness, sep; the labels are 1..cn
fn cdbw(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, cn: usize, r: usize, s: []const f64, clusterstdev: bool, out: []f64) -> err {
    let (nc, e1) = mem.alloc[usize](a, cn)
    let (xcc, e2) = mem.alloc[f64](a, cn * p)
    let (repr, e3) = mem.alloc[usize](a, cn)
    let (wvar, e4) = mem.alloc[f64](a, cn)
    let (repc, e5) = mem.alloc[usize](a, cn * r)
    let (repx, e6) = mem.alloc[usize](a, cn * r)
    let (xc, e7) = mem.alloc[f64](a, n * p)
    let (rows, e8) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret Malformed }
    var i = 0usize
    var tot = 0usize
    while i < cn {
        var m = 0usize
        var q = 0usize
        while q < n {
            if cl[q] == i + 1usize {
                rows[m] = q
                var j = 0usize
                while j < p {
                    xc[m * p + j] = x[q * p + j]
                    j += 1usize
                }
                m += 1usize
            }
            q += 1usize
        }
        nc[i] = m
        fc.col_means(x, n, p, cl, i + 1usize, xcc[i * p..i * p + p])
        let (mr, wv, e9) = findrep(a, xc, m, p, xcc[i * p..i * p + p], r, repx[i * r..i * r + r])
        if e9 != ok { ret e9 }
        repr[i] = mr
        wvar[i] = wv
        q = 0usize
        while q < mr {
            repc[i * r + q] = rows[repx[i * r + q]]
            q += 1usize
        }
        tot += mr
        i += 1usize
    }
    let (sdv, e10) = mem.alloc[f64](a, cn)
    if e10 != ok { ret e10 }
    i = 0usize
    while i < cn {
        sdv[i] = math.sqrt[f64](wvar[i])
        i += 1usize
    }
    let stdev = fc.r_mean(sdv, cn)
    let (vx, e11) = mem.alloc[f64](a, tot * p)
    let (dv, e12) = mem.alloc[f64](a, tot * tot)
    let (start, e13) = mem.alloc[usize](a, cn)
    if e11 != ok || e12 != ok || e13 != ok { ret Malformed }
    var at = 0usize
    i = 0usize
    while i < cn {
        start[i] = at
        var q = 0usize
        while q < repr[i] {
            var j = 0usize
            while j < p {
                vx[at * p + j] = x[repc[i * r + q] * p + j]
                j += 1usize
            }
            at += 1usize
            q += 1usize
        }
        i += 1usize
    }
    fc.euclid(vx, tot, p, dv)
    let (dens, e14) = mem.alloc[f64](a, cn * cn)
    let (dk, e15) = mem.alloc[f64](a, cn * cn)
    let (ii, e16) = mem.alloc[usize](a, r)
    let (ij, e17) = mem.alloc[usize](a, r)
    let (pu, e18) = mem.alloc[f64](a, p)
    if e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret Malformed }
    i = 0usize
    while i < cn * cn {
        dens[i] = 0.0f64
        dk[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i + 1usize < cn {
        var jj = i + 1usize
        while jj < cn {
            var k = 0usize
            while k < repr[i] {
                var b = 0usize
                var l = 1usize
                while l < repr[jj] {
                    if dv[(start[i] + k) * tot + start[jj] + l] < dv[(start[i] + k) * tot + start[jj] + b] { b = l }
                    l += 1usize
                }
                ii[k] = b
                k += 1usize
            }
            k = 0usize
            while k < repr[jj] {
                var b = 0usize
                var l = 1usize
                while l < repr[i] {
                    if dv[(start[i] + l) * tot + start[jj] + k] < dv[(start[i] + b) * tot + start[jj] + k] { b = l }
                    l += 1usize
                }
                ij[k] = b
                k += 1usize
            }
            let wsd = sdv[i]
            var nrcr = 0usize
            k = 0usize
            while k < repr[i] {
                if k == ij[ii[k]] {
                    nrcr += 1usize
                    let ga = repc[i * r + k]
                    let gb = repc[jj * r + ii[k]]
                    var j = 0usize
                    while j < p {
                        pu[j] = (x[ga * p + j] + x[gb * p + j]) / 2.0f64
                        j += 1usize
                    }
                    var cnt = 0usize
                    var q = 0usize
                    while q < n {
                        if cl[q] == i + 1usize || cl[q] == jj + 1usize {
                            if math.sqrt[f64](sqd(x, q, p, pu)) < wsd { cnt += 1usize }
                        }
                        q += 1usize
                    }
                    var sh = 0.0f64
                    var sl = 0.0f64
                    j = 0usize
                    while j < p {
                        let d = x[ga * p + j] - x[gb * p + j]
                        let (h1, l1) = fp.dd_add(sh, sl, d * d, 0.0f64)
                        sh = h1
                        sl = l1
                        j += 1usize
                    }
                    let dkd = math.sqrt[f64](sh + sl)
                    dk[i * cn + jj] += dkd
                    dens[i * cn + jj] += dkd * f64(cnt) / (2.0f64 * wsd * f64(nc[i] + nc[jj]))
                }
                k += 1usize
            }
            dens[i * cn + jj] = dens[i * cn + jj] / f64(nrcr)
            dens[jj * cn + i] = dens[i * cn + jj]
            dk[i * cn + jj] = dk[i * cn + jj] / f64(nrcr)
            dk[jj * cn + i] = dk[i * cn + jj]
            jj += 1usize
        }
        i += 1usize
    }
    let (maxd, e19) = mem.alloc[f64](a, cn)
    let (mind, e20) = mem.alloc[f64](a, cn)
    if e19 != ok || e20 != ok { ret Malformed }
    i = 0usize
    while i < cn {
        var mx = dens[i * cn]
        var mi = 0.0f64
        var first = true
        var j = 0usize
        while j < cn {
            if dens[i * cn + j] > mx { mx = dens[i * cn + j] }
            if j != i {
                if first || dk[i * cn + j] < mi { mi = dk[i * cn + j] }
                first = false
            }
            j += 1usize
        }
        maxd[i] = mx
        mind[i] = mi
        i += 1usize
    }
    let interdens = fc.r_mean(maxd, cn)
    i = 0usize
    while i < cn {
        mind[i] = mind[i] / (1.0f64 + interdens)
        i += 1usize
    }
    let sep = fc.r_mean(mind, cn)
    let ns = s.len
    let (intradens, e21) = mem.alloc[f64](a, ns)
    let (col, e22) = mem.alloc[f64](a, cn)
    let (srep, e23) = mem.alloc[f64](a, p)
    if e21 != ok || e22 != ok || e23 != ok { ret Malformed }
    i = 0usize
    while i < ns {
        var j = 0usize
        while j < cn {
            var stj = stdev
            if clusterstdev { stj = sdv[j] }
            var dc = 0.0f64
            var k = 0usize
            while k < repr[j] {
                let lg = repc[j * r + k]
                var q = 0usize
                while q < p {
                    srep[q] = (1.0f64 - s[i]) * x[lg * p + q] + s[i] * xcc[j * p + q]
                    q += 1usize
                }
                var cnt = 0usize
                q = 0usize
                while q < n {
                    if cl[q] == j + 1usize {
                        if sqd(x, q, p, srep) < stj { cnt += 1usize }
                    }
                    q += 1usize
                }
                dc += f64(cnt) / f64(nc[j])
                k += 1usize
            }
            col[j] = dc / f64(repr[j])
            j += 1usize
        }
        intradens[i] = dsum(col, cn) / (f64(cn) * stdev)
        i += 1usize
    }
    let compactness = fc.r_mean(intradens, ns)
    let (ic, e24) = mem.alloc[f64](a, ns)
    if e24 != ok { ret Malformed }
    i = 0usize
    while i + 1usize < ns {
        ic[i] = intradens[i + 1usize] - intradens[i]
        i += 1usize
    }
    let intrachange = dsum(ic, ns - 1usize) / f64(ns - 1usize)
    let cohesion = compactness / (1.0f64 + intrachange)
    let sc = sep * compactness
    out[0usize] = cohesion * sc
    out[1usize] = cohesion
    out[2usize] = compactness
    out[3usize] = sep
    ret ok
}
