// R ks ksupp in two dimensions: the grid points of kde(x, H) above the contour level of the cont percent region, and the convex hull (chull) of them.
//
// The hull is summarised order free: out = (the number of points above the level, the hull vertex count, the sum of the vertex x, the sum of the vertex y, the hull area).

use e.algo.stat.classint as ci
use e.algo.stat.ks2dkde as kk
use e.math
use e.mem

// Andrew's monotone chain on the points (px, py) sorted by x then y: the hull vertices without collinear ones, counter-clockwise, into hx, hy; returns the count
fn hull(px: []const f64, py: []const f64, n: usize, hx: []f64, hy: []f64) -> usize {
    if n < 3usize {
        var i = 0usize
        while i < n {
            hx[i] = px[i]
            hy[i] = py[i]
            i += 1usize
        }
        ret n
    }
    var k = 0usize
    var i = 0usize
    while i < n {
        while k >= 2usize && cross(hx[k - 2usize], hy[k - 2usize], hx[k - 1usize], hy[k - 1usize], px[i], py[i]) <= 0.0f64 { k -= 1usize }
        hx[k] = px[i]
        hy[k] = py[i]
        k += 1usize
        i += 1usize
    }
    let lo = k + 1usize
    i = n - 1usize
    while i > 0usize {
        i -= 1usize
        while k >= lo && cross(hx[k - 2usize], hy[k - 2usize], hx[k - 1usize], hy[k - 1usize], px[i], py[i]) <= 0.0f64 { k -= 1usize }
        hx[k] = px[i]
        hy[k] = py[i]
        k += 1usize
    }
    ret k - 1usize
}

fn cross(ox: f64, oy: f64, ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    ret (ax - ox) * (by - oy) - (ay - oy) * (bx - ox)
}

fn ksupp2(a: *mem.Arena, x: []const f64, n: usize, h: []const f64, m: usize, cont: f64, out: []f64) -> err {
    let (gx, e1) = mem.alloc[f64](a, m)
    let (gy, e2) = mem.alloc[f64](a, m)
    let (grid, e3) = mem.alloc[f64](a, m * m)
    let (d, e4) = mem.alloc[f64](a, n)
    let (px, e5) = mem.alloc[f64](a, m * m)
    let (py, e6) = mem.alloc[f64](a, m * m)
    let (hx, e7) = mem.alloc[f64](a, m * m + 2usize)
    let (hy, e8) = mem.alloc[f64](a, m * m + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret e1 }
    kk.kde_grid2d(a, x, n, h, m, gx, gy, grid)
    var i = 0usize
    while i < n {
        d[i] = kk.interp2d(gx, gy, grid, x[i * 2usize], x[i * 2usize + 1usize])
        i += 1usize
    }
    let (s, se) = ci.sorted_copy(a, d)
    if se != ok { ret se }
    let level = ci.quantile7(s, (100.0f64 - cont) / 100.0f64)
    // the points in x order (x fastest in the grid, so sort by x then y by walking columns of constant x)
    var cnt = 0usize
    var jx = 0usize
    while jx < m {
        var jy = 0usize
        while jy < m {
            if grid[jy * m + jx] > level {
                px[cnt] = gx[jx]
                py[cnt] = gy[jy]
                cnt += 1usize
            }
            jy += 1usize
        }
        jx += 1usize
    }
    var nh = 0usize
    if cnt > 0usize { nh = hull(px, py, cnt, hx, hy) }
    var sx = 0.0f64
    var sy = 0.0f64
    var area = 0.0f64
    i = 0usize
    while i < nh {
        sx += hx[i]
        sy += hy[i]
        var j = i + 1usize
        if j == nh { j = 0usize }
        area += hx[i] * hy[j] - hx[j] * hy[i]
        i += 1usize
    }
    out[0usize] = f64(cnt)
    out[1usize] = f64(nh)
    out[2usize] = sx
    out[3usize] = sy
    out[4usize] = math.abs[f64](area) / 2.0f64
    ret ok
}
