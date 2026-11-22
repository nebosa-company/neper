// R ks, two dimensions: the gridded kernel density estimate kde(x, H) (151 by 151 grid over the data and 3.7 bandwidths, each kernel summed over its
// rectangular support), its interpolation at the data (predict.kde, interp2d) and the probability contour levels contourLevels(kde, cont) of the
// density-ordered observations, and rkde, random draws from the estimate under set.seed.
//
// Not here: the binned estimate above 500 observations, positive and unit-interval support, weights other than one, kde in 1, 3 and 4 dimensions.

use e.algo.rand.r as rr
use e.algo.rand.rdist as rd
use e.algo.stat.classint as ci
use e.algo.stat.ks2d as k2
use e.algo.stat.mvtnorm as mv
use e.math
use e.mem

error Failed

// seq(lo, hi, length = m)
fn seq_len_out(lo: f64, hi: f64, m: usize, g: []f64) {
    let by = (hi - lo) / f64(m - 1usize)
    g[0usize] = lo
    var i = 1usize
    while i < m - 1usize {
        g[i] = lo + f64(i) * by
        i += 1usize
    }
    g[m - 1usize] = hi
}

// the number of grid points at or below v
fn count_le(g: []const f64, v: f64) -> usize {
    var c = 0usize
    var i = 0usize
    while i < g.len {
        if v >= g[i] { c += 1usize }
        i += 1usize
    }
    ret c
}

// kde.grid.2d: grid (m by m, first variable fastest) and the grid points gx, gy
fn kde_grid2d(a: *mem.Arena, x: []const f64, n: usize, h: []const f64, m: usize, gx: []f64, gy: []f64, grid: []f64) {
    var hs: [4]f64 = zero
    k2.sqrt2(h, hs[0usize..4usize])
    let tx = 3.7f64 * hs[0usize]
    let ty = 3.7f64 * hs[3usize]
    var x0 = x[0usize]
    var x1 = x[0usize]
    var y0 = x[1usize]
    var y1 = x[1usize]
    var i = 1usize
    while i < n {
        if x[i * 2usize] < x0 { x0 = x[i * 2usize] }
        if x[i * 2usize] > x1 { x1 = x[i * 2usize] }
        if x[i * 2usize + 1usize] < y0 { y0 = x[i * 2usize + 1usize] }
        if x[i * 2usize + 1usize] > y1 { y1 = x[i * 2usize + 1usize] }
        i += 1usize
    }
    seq_len_out(x0 - tx, x1 + tx, m, gx)
    seq_len_out(y0 - ty, y1 + ty, m, gy)
    i = 0usize
    while i < m * m {
        grid[i] = 0.0f64
        i += 1usize
    }
    let det = h[0usize] * h[3usize] - h[1usize] * h[2usize]
    let i11 = h[3usize] / det
    let i12 = 0.0f64 - h[1usize] / det
    let i22 = h[0usize] / det
    let k = 1.0f64 / (2.0f64 * 3.141592653589793f64 * math.sqrt[f64](det))
    i = 0usize
    while i < n {
        let px = x[i * 2usize]
        let py = x[i * 2usize + 1usize]
        var ax = count_le(gx, px - tx)
        if ax == 0usize { ax = 1usize }
        let bx = count_le(gx, px + tx)
        var ay = count_le(gy, py - ty)
        if ay == 0usize { ay = 1usize }
        let by = count_le(gy, py + ty)
        var jy = ay
        while jy <= by {
            var jx = ax
            while jx <= bx {
                let dx = gx[jx - 1usize] - px
                let dy = gy[jy - 1usize] - py
                grid[(jy - 1usize) * m + jx - 1usize] += k * math.exp[f64](0.0f64 - 0.5f64 * (dx * dx * i11 + 2.0f64 * dx * dy * i12 + dy * dy * i22))
                jx += 1usize
            }
            jy += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m * m {
        grid[i] = grid[i] / f64(n)
        i += 1usize
    }
}

// interp2d at one point
fn interp2d(gx: []const f64, gy: []const f64, grid: []const f64, px: f64, py: f64) -> f64 {
    let m1 = gx.len
    let m2 = gy.len
    let d1 = (gx[m1 - 1usize] - gx[0usize]) / f64(m1 - 1usize)
    let d2 = (gy[m2 - 1usize] - gy[0usize]) / f64(m2 - 1usize)
    let p1 = (px - gx[0usize]) / d1
    let p2 = (py - gy[0usize]) / d2
    let i1 = i64(math.floor[f64](p1))
    let i2 = i64(math.floor[f64](p2))
    let f1 = p1 - f64(i1)
    let f2 = p2 - f64(i2)
    let mx1 = i64(m1) - 2i64
    let mx2 = i64(m2) - 2i64
    if i1 >= 0i64 && i1 <= mx1 && i2 >= 0i64 && i2 <= mx2 {
        let u1 = usize(i1)
        let u2 = usize(i2)
        ret grid[u2 * m1 + u1] * (1.0f64 - f1) * (1.0f64 - f2) + grid[u2 * m1 + u1 + 1usize] * f1 * (1.0f64 - f2) + grid[(u2 + 1usize) * m1 + u1] * (1.0f64 - f1) * f2 + grid[(u2 + 1usize) * m1 + u1 + 1usize] * f1 * f2
    }
    ret 0.0f64
}

// contourLevels(kde, cont = c): the (100 - c) / 100 quantile (type 7) of the estimate interpolated at the data
fn kde_contour(a: *mem.Arena, x: []const f64, n: usize, h: []const f64, m: usize, cont: f64) -> f64 {
    let (gx, e1) = mem.alloc[f64](a, m)
    let (gy, e2) = mem.alloc[f64](a, m)
    let (grid, e3) = mem.alloc[f64](a, m * m)
    let (d, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    kde_grid2d(a, x, n, h, m, gx, gy, grid)
    var i = 0usize
    while i < n {
        d[i] = interp2d(gx, gy, grid, x[i * 2usize], x[i * 2usize + 1usize])
        i += 1usize
    }
    let (s, se) = ci.sorted_copy(a, d)
    if se != ok { ret 0.0f64 / 0.0f64 }
    ret ci.quantile7(s, (100.0f64 - cont) / 100.0f64)
}

// rkde(n, kde(x, H)) (d = 2, equal weights) under the seed: the draw at row `row`, column `col`
fn rkde2(a: *mem.Arena, seed: i64, x: []const f64, nobs: usize, h: []const f64, size: usize, out: []f64) -> err {
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    let (w, we) = mem.alloc[f64](a, nobs)
    if we != ok { ret we }
    var i = 0usize
    while i < nobs {
        w[i] = 1.0f64
        i += 1usize
    }
    let (ind, ie) = rd.sample_prob(a, &g, nobs, size, true, w)
    if ie != ok { ret ie }
    var id2: [4]f64 = zero
    id2[0usize] = 1.0f64
    id2[3usize] = 1.0f64
    var zero2: [2]f64 = zero
    let (z, ze) = mv.rmvnorm(a, &g, size, zero2[0usize..2usize], id2[0usize..4usize], 2usize, 0u8)
    if ze != ok { ret ze }
    var hs: [4]f64 = zero
    k2.sqrt2(h, hs[0usize..4usize])
    i = 0usize
    while i < size {
        let r = usize(ind[i]) - 1usize
        out[i * 2usize] = x[r * 2usize] + (z[i * 2usize] * hs[0usize] + z[i * 2usize + 1usize] * hs[2usize])
        out[i * 2usize + 1usize] = x[r * 2usize + 1usize] + (z[i * 2usize] * hs[1usize] + z[i * 2usize + 1usize] * hs[3usize])
        i += 1usize
    }
    ret ok
}

// rkde(n, kde(x, h = h)) in one dimension
fn rkde1(a: *mem.Arena, seed: i64, x: []const f64, h: f64, size: usize, out: []f64) -> err {
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    let nobs = x.len
    let (w, we) = mem.alloc[f64](a, nobs)
    if we != ok { ret we }
    var i = 0usize
    while i < nobs {
        w[i] = 1.0f64
        i += 1usize
    }
    let (ind, ie) = rd.sample_prob(a, &g, nobs, size, true, w)
    if ie != ok { ret ie }
    i = 0usize
    while i < size {
        out[i] = x[usize(ind[i]) - 1usize] + h * rr.rnorm(&g, 0.0f64, 1.0f64)
        i += 1usize
    }
    ret ok
}
