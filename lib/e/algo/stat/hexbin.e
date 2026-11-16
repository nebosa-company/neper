// R hexbin: `hexbin` (Carr's hexagonal binning as the Fortran routine hbin does it, single-precision
// constants included), the cell centres `hcell2xy` and `hexcoords` (the six corners of a hexagon).
//
// Not here: erosion, smoothing, hexTapply and the plotting.

use e.math
use e.mem

type Bin = struct { cell: []i64, count: []i64, xcm: []f64, ycm: []f64, imax: i64, jmax: i64, ncells: usize }

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
    ret (Bin { cell: cell, count: cc, xcm: cx, ycm: cy, imax: imax, jmax: jmax, ncells: nc }, ok)
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
