// R hexbin: `hexbin` (Carr's hexagonal binning as the Fortran routine hbin does it, single-precision
// constants included), the cell centres `hcell2xy` and `hexcoords` (the six corners of a hexagon).
//
// And `hex_tapply`, `smooth` (smooth.hexbin) and `erode` (erode.hexbin). Not here: the plotting.

use e.math
use e.mem

type Bin = struct { cell: []i64, count: []i64, xcm: []f64, ycm: []f64, cid: []i64, imax: i64, jmax: i64, ncells: usize }

// int(x): truncation toward zero
fn itrunc(x: f64) -> i64 { ret i64(x) }

// hexbin(x, y, xbins, shape, xbnds, ybnds); the answers are in cell order (ascending)
fn hexbin(a: *mem.Arena, x: []const f64, y: []const f64, xbins: f64, shape: f64, xlo: f64, xhi: f64, ylo: f64, yhi: f64) -> (Bin, err) {
    var none: Bin = zero
    let n = x.len
    let jmax = i64(math.floor[f64](xbins + 1.5001f64))
    let c1i = 2.0f64 * math.floor[f64]((xbins * shape) / math.sqrt[f64](3.0f64) + 1.5001f64)
    let imax = i64(math.trunc[f64](f64(jmax) * c1i - 1.0f64) / f64(jmax) + 1.0f64)
    let lmax = usize(jmax * imax)
    let (cnt, ce) = mem.alloc[i64](a, lmax + 1usize)
    let (xs, xe) = mem.alloc[f64](a, lmax + 1usize)
    let (ys, ye) = mem.alloc[f64](a, lmax + 1usize)
    let (cid, cie) = mem.alloc[i64](a, n)
    if cie != ok { ret (none, cie) }
    if ce != ok { ret (none, ce) }
    if xe != ok { ret (none, xe) }
    if ye != ok { ret (none, ye) }
    var l = 0usize
    while l <= lmax {
        cnt[l] = 0i64
        xs[l] = 0.0f64
        ys[l] = 0.0f64
        l += 1usize
    }
    let xr = xhi - xlo
    let yr = yhi - ylo
    // the Fortran has sqrt(3.) as a REAL and 1.0/3.0 as a REAL
    let sqrt3 = f64(f32(math.sqrt[f64](3.0f64)))
    let c1 = xbins / xr
    let c2 = xbins * shape / (yr * sqrt3)
    let jinc = jmax
    let lat = jinc + 1i64
    let iinc = 2i64 * jinc
    let con1 = 0.25f64
    let con2 = f64(f32(1.0f64 / 3.0f64))
    var i = 0usize
    while i < n {
        let sx = c1 * (x[i] - xlo)
        let sy = c2 * (y[i] - ylo)
        let j1 = itrunc(sx + 0.5f64)
        let i1 = itrunc(sy + 0.5f64)
        let dist1 = (sx - f64(j1)) * (sx - f64(j1)) + 3.0f64 * (sy - f64(i1)) * (sy - f64(i1))
        var cl = 0i64
        if dist1 < con1 {
            cl = i1 * iinc + j1 + 1i64
        } else if dist1 > con2 {
            cl = itrunc(sy) * iinc + itrunc(sx) + lat
        } else {
            let j2 = itrunc(sx)
            let i2 = itrunc(sy)
            if dist1 <= (sx - f64(j2) - 0.5f64) * (sx - f64(j2) - 0.5f64) + 3.0f64 * (sy - f64(i2) - 0.5f64) * (sy - f64(i2) - 0.5f64) {
                cl = i1 * iinc + j1 + 1i64
            } else {
                cl = i2 * iinc + j2 + lat
            }
        }
        cid[i] = cl
        let u = usize(cl)
        cnt[u] += 1i64
        xs[u] = xs[u] + (x[i] - xs[u]) / f64(cnt[u])
        ys[u] = ys[u] + (y[i] - ys[u]) / f64(cnt[u])
        i += 1usize
    }
    var nc = 0usize
    l = 1usize
    while l <= lmax {
        if cnt[l] > 0i64 { nc += 1usize }
        l += 1usize
    }
    let (cell, cle) = mem.alloc[i64](a, nc)
    let (cc, cce) = mem.alloc[i64](a, nc)
    let (cx, cxe) = mem.alloc[f64](a, nc)
    let (cy, cye) = mem.alloc[f64](a, nc)
    if cle != ok { ret (none, cle) }
    if cce != ok { ret (none, cce) }
    if cxe != ok { ret (none, cxe) }
    if cye != ok { ret (none, cye) }
    var k = 0usize
    l = 1usize
    while l <= lmax {
        if cnt[l] > 0i64 {
            cell[k] = i64(l)
            cc[k] = cnt[l]
            cx[k] = xs[l]
            cy[k] = ys[l]
            k += 1usize
        }
        l += 1usize
    }
    ret (Bin { cell: cell, count: cc, xcm: cx, ycm: cy, cid: cid, imax: imax, jmax: jmax, ncells: nc }, ok)
}

// the centre of cell number `cell` (1-based) of a bin with these settings
fn hcell2xy(cell: i64, jmax: i64, xbins: f64, shape: f64, xlo: f64, xhi: f64, ylo: f64, yhi: f64) -> (f64, f64) {
    let c3 = (xhi - xlo) / xbins
    let c4 = ((yhi - ylo) * math.sqrt[f64](3.0f64)) / (2.0f64 * shape * xbins)
    let c0 = cell - 1i64
    let i = c0 / jmax
    let j = c0 % jmax
    let y = c4 * f64(i) + ylo
    var jj = f64(j)
    if i % 2i64 != 0i64 { jj += 0.5f64 }
    ret (c3 * jj + xlo, y)
}

// hexTapply(hbin, dat, FUN): FUN of the observations of each cell, in cell order; fun 0 sum, 1 mean, 2 length, 3 min, 4 max.
// The Bin needs its per-observation cell ids (cid).
fn hex_tapply(a: *mem.Arena, b: Bin, dat: []const f64, fun: u8) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, b.ncells)
    if e != ok { ret (out, e) }
    var c = 0usize
    while c < b.ncells {
        var s = 0.0f64
        var cnt = 0usize
        var lo = 0.0f64
        var hi = 0.0f64
        var i = 0usize
        while i < dat.len {
            if b.cid[i] == b.cell[c] {
                if cnt == 0usize {
                    lo = dat[i]
                    hi = dat[i]
                } else {
                    if dat[i] < lo { lo = dat[i] }
                    if dat[i] > hi { hi = dat[i] }
                }
                s += dat[i]
                cnt += 1usize
            }
            i += 1usize
        }
        if fun == 0u8 { out[c] = s }
        if fun == 1u8 { out[c] = s / f64(cnt) }
        if fun == 2u8 { out[c] = f64(cnt) }
        if fun == 3u8 { out[c] = lo }
        if fun == 4u8 { out[c] = hi }
        c += 1usize
    }
    ret (out, ok)
}

type Smooth = struct { cell: []i64, count: []i64, imax: i64, jmax: i64, ncells: usize }

// smooth.hexbin(bin, wts): the integer kernel of hsm.f (centre wts[0], first ring wts[1], second ring wts[2]) on the bin padded by two
// cells on every side; the answer is in cell order of the (imax + 4) by (jmax + 4) lattice.
fn smooth(a: *mem.Arena, cell: []const i64, cnt: []const i64, imax: i64, jmax: i64, wta: i64, wtb: i64, wtc: i64) -> (Smooth, err) {
    var none: Smooth = zero
    let ncol = jmax + 4i64
    let nrow = imax + 4i64
    let nmax = usize(ncol * nrow)
    let (sm, e1) = mem.alloc[i64](a, nmax + 1usize)
    if e1 != ok { ret (none, e1) }
    var i = 0usize
    while i <= nmax {
        sm[i] = 0i64
        i += 1usize
    }
    let n = cell.len
    let (pc, e2) = mem.alloc[i64](a, n)
    if e2 != ok { ret (none, e2) }
    i = 0usize
    while i < n {
        let c0 = cell[i] - 1i64
        pc[i] = (c0 / jmax + 2i64) * ncol + (c0 % jmax + 3i64)
        sm[usize(pc[i])] = wta * cnt[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        let loc = pc[i]
        let row = (loc - 1i64) / ncol + 1i64
        let c1 = wtb * cnt[i]
        let c2 = wtc * cnt[i]
        if row % 2i64 == 1i64 {
            sm[usize(loc - 1i64)] += c1
            sm[usize(loc + ncol - 1i64)] += c1
            sm[usize(loc + ncol)] += c1
            sm[usize(loc + 1i64)] += c1
            sm[usize(loc - ncol)] += c1
            sm[usize(loc - ncol - 1i64)] += c1
            sm[usize(loc - 2i64)] += c2
            sm[usize(loc + ncol - 2i64)] += c2
            sm[usize(loc + 2i64 * ncol - 1i64)] += c2
            sm[usize(loc + 2i64 * ncol)] += c2
            sm[usize(loc + 2i64 * ncol + 1i64)] += c2
            sm[usize(loc + ncol + 1i64)] += c2
            sm[usize(loc + 2i64)] += c2
            sm[usize(loc - ncol + 1i64)] += c2
            sm[usize(loc - 2i64 * ncol + 1i64)] += c2
            sm[usize(loc - 2i64 * ncol)] += c2
            sm[usize(loc - 2i64 * ncol - 1i64)] += c2
            sm[usize(loc - ncol - 2i64)] += c2
        } else {
            sm[usize(loc - 1i64)] += c1
            sm[usize(loc + ncol)] += c1
            sm[usize(loc + ncol + 1i64)] += c1
            sm[usize(loc + 1i64)] += c1
            sm[usize(loc - ncol + 1i64)] += c1
            sm[usize(loc - ncol)] += c1
            sm[usize(loc - 2i64)] += c2
            sm[usize(loc + ncol - 1i64)] += c2
            sm[usize(loc + 2i64 * ncol - 1i64)] += c2
            sm[usize(loc + 2i64 * ncol)] += c2
            sm[usize(loc + 2i64 * ncol + 1i64)] += c2
            sm[usize(loc + ncol + 2i64)] += c2
            sm[usize(loc + 2i64)] += c2
            sm[usize(loc - ncol + 2i64)] += c2
            sm[usize(loc - 2i64 * ncol + 1i64)] += c2
            sm[usize(loc - 2i64 * ncol)] += c2
            sm[usize(loc - 2i64 * ncol - 1i64)] += c2
            sm[usize(loc - ncol - 1i64)] += c2
        }
        i += 1usize
    }
    var k = 0usize
    i = 1usize
    while i <= nmax {
        if sm[i] > 0i64 { k += 1usize }
        i += 1usize
    }
    let (oc, e3) = mem.alloc[i64](a, k)
    let (on, e4) = mem.alloc[i64](a, k)
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    k = 0usize
    i = 1usize
    while i <= nmax {
        if sm[i] > 0i64 {
            oc[k] = i64(i)
            on[k] = sm[i]
            k += 1usize
        }
        i += 1usize
    }
    ret (Smooth { cell: oc, count: on, imax: nrow, jmax: ncol, ncells: k }, ok)
}

type Erode = struct { erode: []i64, good: []bool, nsel: usize }

// erode.hexbin(bin, cdfcut): the gray-level erosion order of herode.f for the cells whose count reaches the cdfcut quantile of the
// sorted counts. `good` marks the selected cells of the bin and `erode` has one value per selected cell.
fn erode(a: *mem.Arena, cell: []const i64, cnt: []const i64, imax: i64, jmax: i64, cdfcut: f64) -> (Erode, err) {
    var none: Erode = zero
    let nb = cell.len
    let (srt, e0) = mem.alloc[f64](a, nb)
    let (good, eg) = mem.alloc[bool](a, nb)
    if e0 != ok { ret (none, e0) }
    if eg != ok { ret (none, eg) }
    var total = 0.0f64
    var i = 0usize
    while i < nb {
        srt[i] = f64(cnt[i])
        total += f64(cnt[i])
        i += 1usize
    }
    // insertion sort of the counts (small)
    i = 1usize
    while i < nb {
        let v = srt[i]
        var j = i
        while j > 0usize && srt[j - 1usize] > v {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = v
        i += 1usize
    }
    var run = 0.0f64
    var crit = 0.0f64
    var any = false
    i = 0usize
    while i < nb {
        run += srt[i]
        if cdfcut <= run / total {
            if !any {
                crit = srt[i]
                any = true
            } else if srt[i] < crit {
                crit = srt[i]
            }
        }
        i += 1usize
    }
    if !any { ret (none, ok) }
    var n = 0usize
    i = 0usize
    while i < nb {
        good[i] = crit <= f64(cnt[i])
        if good[i] { n += 1usize }
        i += 1usize
    }
    let nrow = imax
    let ncol = jmax
    let lmax = usize(nrow * ncol)
    let (cl, e1) = mem.alloc[i64](a, n + 1usize)
    let (cn, e2) = mem.alloc[i64](a, n + 1usize)
    let (er, e3) = mem.alloc[i64](a, lmax + 2usize)
    let (ncnt, e4) = mem.alloc[i64](a, lmax + 2usize)
    let (ncell, e5) = mem.alloc[i64](a, lmax + 2usize)
    let (sides, e6) = mem.alloc[i64](a, lmax + 2usize)
    let (neib, e7) = mem.alloc[i64](a, 6usize * (lmax + 2usize))
    let (exist, e8) = mem.alloc[bool](a, lmax + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (none, e1) }
    var q = 0usize
    i = 0usize
    while i < nb {
        if good[i] {
            q += 1usize
            cl[q] = cell[i]
            cn[q] = cnt[i]
        }
        i += 1usize
    }
    i = 0usize
    while i <= lmax + 1usize {
        er[i] = 0i64
        ncnt[i] = 0i64
        ncell[i] = 0i64
        sides[i] = 0i64
        exist[i] = false
        i += 1usize
    }
    i = 0usize
    while i < 6usize * (lmax + 2usize) {
        neib[i] = 0i64
        i += 1usize
    }
    var maxcnt = 0i64
    i = 1usize
    while i <= n {
        let ic = usize(cl[i])
        ncnt[ic] = cn[i]
        exist[ic] = true
        if cn[i] > maxcnt { maxcnt = cn[i] }
        i += 1usize
    }
    let inc1a = 1i64
    let inc1b = ncol - 1i64
    let inc1c = 0i64 - ncol - 1i64
    let inc1d = ncol
    let inc1e = 0i64 - 1i64
    let inc1f = 0i64 - ncol
    let inc2a = 1i64
    let inc2b = ncol
    let inc2c = 0i64 - ncol
    let inc2d = ncol + 1i64
    let inc2e = 0i64 - 1i64
    let inc2f = 0i64 - ncol + 1i64
    i = 1usize
    while i <= n {
        let l = cl[i]
        let lu = usize(l)
        let k = l - 1i64
        let r = k / ncol + 1i64
        let c = k % ncol + 1i64
        let base = 6usize * lu
        if r % 2i64 == 1i64 {
            neib[base + 0usize] = l + inc1a
            neib[base + 1usize] = l + inc1b
            neib[base + 2usize] = l + inc1c
            neib[base + 3usize] = l + inc1d
            neib[base + 4usize] = l + inc1e
            neib[base + 5usize] = l + inc1f
            if c == 1i64 {
                neib[base + 1usize] = 0i64
                neib[base + 2usize] = 0i64
                neib[base + 4usize] = 0i64
            } else if c == ncol {
                neib[base + 0usize] = 0i64
            }
            if r == 1i64 {
                neib[base + 2usize] = 0i64
                neib[base + 5usize] = 0i64
            } else if r == nrow {
                neib[base + 1usize] = 0i64
                neib[base + 3usize] = 0i64
            }
        } else {
            neib[base + 0usize] = l + inc2a
            neib[base + 1usize] = l + inc2b
            neib[base + 2usize] = l + inc2c
            neib[base + 3usize] = l + inc2d
            neib[base + 4usize] = l + inc2e
            neib[base + 5usize] = l + inc2f
            if c == 1i64 {
                neib[base + 4usize] = 0i64
            } else if c == ncol {
                neib[base + 0usize] = 0i64
                neib[base + 3usize] = 0i64
                neib[base + 5usize] = 0i64
            }
            if r == nrow {
                neib[base + 1usize] = 0i64
                neib[base + 3usize] = 0i64
            }
        }
        i += 1usize
    }
    i = 1usize
    while i <= n {
        let ic = usize(cl[i])
        sides[ic] = 0i64
        var j = 0usize
        while j < 6usize {
            if !exist[usize(neib[6usize * ic + j])] { sides[ic] += 1i64 }
            j += 1usize
        }
        i += 1usize
    }
    var nc = 0usize
    i = 1usize
    while i <= n {
        if sides[usize(cl[i])] > 0i64 {
            nc += 1usize
            ncell[nc] = cl[i]
        }
        i += 1usize
    }
    var m = nc
    var order = 0i64
    while m > 0usize {
        var loop = maxcnt
        i = 1usize
        while i <= m {
            let ic = usize(ncell[i])
            let v = (ncnt[ic] - 1i64) / sides[ic]
            if v < loop { loop = v }
            i += 1usize
        }
        loop += 1i64
        nc = 0usize
        order += 6i64
        var ninc = m
        i = 1usize
        while i <= m {
            let ic = usize(ncell[i])
            ncnt[ic] = ncnt[ic] - sides[ic] * loop
            if ncnt[ic] <= 0i64 {
                exist[ic] = false
                er[ic] = order + ncnt[ic]
                var j = 0usize
                while j < 6usize {
                    let nbr = usize(neib[6usize * ic + j])
                    if exist[nbr] {
                        if sides[nbr] == 0i64 {
                            ninc += 1usize
                            ncell[ninc] = i64(nbr)
                        }
                        sides[nbr] += 1i64
                    }
                    j += 1usize
                }
            } else {
                nc += 1usize
                ncell[nc] = ncell[i]
            }
            i += 1usize
        }
        i = m + 1usize
        while i <= ninc {
            nc += 1usize
            ncell[nc] = ncell[i]
            i += 1usize
        }
        m = nc
    }
    let (res, e9) = mem.alloc[i64](a, n)
    if e9 != ok { ret (none, e9) }
    i = 0usize
    while i < n {
        res[i] = er[usize(cl[i + 1usize])]
        i += 1usize
    }
    ret (Erode { erode: res, good: good, nsel: n }, ok)
}
