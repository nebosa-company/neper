// R interp and fields: the Delaunay triangulation of points in general position (tri.mesh: triangles, arcs, hull, circumcircles), the areas of the interior
// Voronoi cells (voronoi.mosaic and voronoi.area), linear interpolation on the triangulation (interp / interpp with linear = TRUE, NA outside the hull) and bilinear
// interpolation on a rectangular grid (interp::bilinear and fields::interp.surface).
// tri_answer: args = [op, idx, n, nq, x (n), y (n), z (n), xq (nq), yq (nq)]; op 0 number of triangles  1 number of arcs  2 hull vertices  3 sum of triangle areas
// 4 sum of circumradii  5 sum of circumcentre x  6 sum of circumcentre y  7 sum over triangles of (i * 131 + j) * 131 + k with i < j < k one-based
// 8 interior cells  9 sum of interior cell areas  10 query idx inside the hull (1 or 0)  11 linear interpolated value at query idx  12 Akima (interp method = "akima": local cubic fits, quintic per
// triangle, three vertex rotations weighted barycentrically; needs n > 10)  13 voronoi.mosaic dummy nodes  14 their summed x  15 their summed y.
// bil_answer: args = [op, idx, nx, ny, x (nx), y (ny), z (nx * ny column major), nq, xq (nq), yq (nq)]; op 0 inside the grid, 1 value.
//
// op 16-18 n1 n2 n3 after the dummy nodes, 19 and 20 ordered dummy x and y, 21-23 voronoi.findvertices lists (x and y of the vertices), 24-32 trlist columns, 33 and 34 arcs, 35 chull, 36-40 cclist
// columns: position-weighted sums in R's own order (the triangulation is the s_hull_pro.cpp port in e.algo.stat.shull).
// Not here: duplicate handling, other smooth interpolants, constrained meshes, the plotting helpers (circles, plot.voronoi) and the jitter retry R makes when s-hull needs too many flips.

use e.algo.stat.fieldspkg as fp
use e.algo.stat.shull as sh
use e.math
use e.mem

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

// shullDeltri.cpp's circum: the centre, radius and area are single precision (the CC struct holds floats; the radius is measured from the rounded centre to the first vertex), the
// inscribed-to-circumscribed ratio is double. out = [centre x, centre y, radius, area, ratio]
fn circum(x: []const f64, y: []const f64, ia: usize, ib: usize, ic: usize, out: []f64) {
    let x1 = x[ia]
    let y1 = y[ia]
    let x2 = x[ib]
    let y2 = y[ib]
    let x3 = x[ic]
    let y3 = y[ic]
    let d = (x1 - x3) * (y2 - y3) - (x2 - x3) * (y1 - y3)
    let ha = ((x1 - x3) * (x1 + x3) + (y1 - y3) * (y1 + y3)) / 2.0f64
    let hb = ((x2 - x3) * (x2 + x3) + (y2 - y3) * (y2 + y3)) / 2.0f64
    let xc = f64(f32((ha * (y2 - y3) - hb * (y1 - y3)) / d))
    let yc = f64(f32((hb * (x1 - x3) - ha * (x2 - x3)) / d))
    let rc = f64(f32(math.sqrt[f64]((x1 - xc) * (x1 - xc) + (y1 - yc) * (y1 - yc))))
    let ar = f64(f32(math.abs[f64](x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2)) / 2.0f64))
    let s12 = math.sqrt[f64]((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
    let s23 = math.sqrt[f64]((x3 - x2) * (x3 - x2) + (y3 - y2) * (y3 - y2))
    let s31 = math.sqrt[f64]((x1 - x3) * (x1 - x3) + (y1 - y3) * (y1 - y3))
    let ir = ar / (0.5f64 * (s12 + s23 + s31))
    out[0usize] = xc
    out[1usize] = yc
    out[2usize] = rc
    out[3usize] = ar
    out[4usize] = ir / rc
}

// voronoi.mosaic's dummy.node
fn dummy_node(xy: []const f64, n: usize, x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64, d0: f64, out: []f64) {
    let dx = x2 - x1
    let dy = y2 - y1
    let nx = 0.0f64 - dy
    let ny = dx
    let rx = (x1 + x2) / 2.0f64 - x0
    let ry = (y1 + y2) / 2.0f64 - y0
    let lr = math.sqrt[f64](rx * rx + ry * ry)
    let ln = math.sqrt[f64](nx * nx + ny * ny)
    var d = d0
    var vx = 0.0f64
    var vy = 0.0f64
    if lr > ln {
        vx = rx / lr
        vy = ry / lr
        if !fp.in_hull(xy, n, 2usize, x0, y0) { d = 0.0f64 - d }
    } else {
        vx = nx / ln
        vy = ny / ln
        if fp.in_hull(xy, n, 2usize, (x1 + x2) / 2.0f64 + 1.0e-7f64 * vx, (y1 + y2) / 2.0f64 + 1.0e-7f64 * vy) { d = 0.0f64 - d }
    }
    out[0usize] = x0 + d * vx
    out[1usize] = y0 + d * vy
}

// position-weighted sums of tri.mesh's lists (op 24-40): trlist columns i1 i2 i3 j1 j2 j3 k1 k2 k3 (24-32, one-based, 0 for no neighbour), arcs from and to (33, 34), chull (35),
// cclist columns x y r area ratio (36-40); a sum is over positions 1, 2, ... of (position * value)
fn ordered_tri(a: *mem.Arena, op: usize, td: []const i64, nt: usize, cc: []const f64) -> f64 {
    var sum = 0.0f64
    var t = 0usize
    if op >= 36usize {
        while t < nt {
            sum += f64(t + 1usize) * cc[5usize * t + (op - 36usize)]
            t += 1usize
        }
        ret sum
    }
    if op < 30usize {
        while t < nt {
            sum += f64(t + 1usize) * f64(td[6usize * t + (op - 24usize)] + 1i64)
            t += 1usize
        }
        ret sum
    }
    if op == 35usize {
        let cp1 = sh.ai(a, 3usize * nt + 3usize)
        let cp2 = sh.ai(a, 3usize * nt + 3usize)
        var nch = 0usize
        while t < nt {
            let i1 = td[6usize * t]
            let i2 = td[6usize * t + 1usize]
            let i3 = td[6usize * t + 2usize]
            if td[6usize * t + 3usize] < 0i64 {
                cp1[nch] = i2
                cp2[nch] = i3
                nch += 1usize
            }
            if td[6usize * t + 4usize] < 0i64 {
                cp1[nch] = i3
                cp2[nch] = i1
                nch += 1usize
            }
            if td[6usize * t + 5usize] < 0i64 {
                cp1[nch] = i1
                cp2[nch] = i2
                nch += 1usize
            }
            t += 1usize
        }
        let ch = sh.ai(a, nch + 3usize)
        ch[0usize] = cp1[0usize]
        ch[1usize] = cp2[0usize]
        var j = 1usize
        while j + 1usize < nch {
            var found = false
            var i = 1usize
            while i < nch {
                if ch[j] == cp1[i] {
                    ch[j + 1usize] = cp2[i]
                    found = true
                }
                i += 1usize
            }
            if !found {
                i = 1usize
                while i < nch {
                    if ch[j] == cp2[i] {
                        ch[j + 1usize] = cp1[i]
                        found = true
                    }
                    i += 1usize
                }
            }
            j += 1usize
        }
        j = 0usize
        while j < nch {
            sum += f64(j + 1usize) * f64(ch[j] + 1i64)
            j += 1usize
        }
        ret sum
    }
    // arcs in order of first appearance, and the arc each triangle edge uses
    let a1 = sh.ai(a, 3usize * nt + 3usize)
    let a2 = sh.ai(a, 3usize * nt + 3usize)
    let kk = sh.ai(a, 3usize * nt + 3usize)
    var ia = 0usize
    while t < nt {
        var s = 0usize
        while s < 3usize {
            let i1 = td[6usize * t]
            let i2 = td[6usize * t + 1usize]
            let i3 = td[6usize * t + 2usize]
            var p = i2
            var q = i3
            if s == 1usize {
                p = i3
                q = i1
            }
            if s == 2usize {
                p = i1
                q = i2
            }
            var found = false
            var j = 0usize
            while j < ia && !found {
                if (a1[j] == p && a2[j] == q) || (a1[j] == q && a2[j] == p) {
                    found = true
                    kk[3usize * t + s] = i64(j)
                }
                j += 1usize
            }
            if !found {
                a1[ia] = p
                a2[ia] = q
                kk[3usize * t + s] = i64(ia)
                ia += 1usize
            }
            s += 1usize
        }
        t += 1usize
    }
    var e = 0usize
    if op >= 33usize {
        while e < ia {
            if op == 33usize { sum += f64(e + 1usize) * f64(a1[e] + 1i64) }
            if op == 34usize { sum += f64(e + 1usize) * f64(a2[e] + 1i64) }
            e += 1usize
        }
        ret sum
    }
    t = 0usize
    while t < nt {
        sum += f64(t + 1usize) * f64(kk[3usize * t + (op - 30usize)] + 1i64)
        t += 1usize
    }
    ret sum
}

// the Voronoi side of tri.mesh: voronoi.mosaic's dummy nodes in R's order and the neighbour slots they fill (op 13-20: count, summed x and y, n1 n2 n3 hashes, ordered x and y
// hashes), and voronoi.findvertices' ordered vertex list per site (op 8 sites with a closed cell, 9 their summed areas, 21 vertex-list hash, 22 and 23 vertex x and y hashes)
fn ord_answer(a: *mem.Arena, op: usize, x: []const f64, y: []const f64, n: usize, td: []const i64, nt: usize, cc: []const f64, onhull: []const usize) -> f64 {
    if op >= 24usize { ret ordered_tri(a, op, td, nt, cc) }
    var t = 0usize
    if op <= 9usize || op >= 21usize {
        let vt = sh.ai(a, nt + 3usize)
        let m1 = sh.ai(a, nt + 3usize)
        let m2 = sh.ai(a, nt + 3usize)
        let ordv = sh.ai(a, nt + 3usize)
        var cells = 0usize
        var total = 0.0f64
        var h21 = 0.0f64
        var h22 = 0.0f64
        var h23 = 0.0f64
        var site = 0usize
        while site < n {
            let sid = i64(site)
            var cv = 0usize
            var col = 0usize
            while col < 3usize {
                t = 0usize
                while t < nt {
                    if td[6usize * t + col] == sid {
                        vt[cv] = i64(t)
                        var o1 = td[6usize * t]
                        var o2 = td[6usize * t + 1usize]
                        if col == 0usize {
                            o1 = td[6usize * t + 1usize]
                            o2 = td[6usize * t + 2usize]
                        }
                        if col == 1usize {
                            o1 = td[6usize * t]
                            o2 = td[6usize * t + 2usize]
                        }
                        m1[cv] = o1
                        m2[cv] = o2
                        cv += 1usize
                    }
                    t += 1usize
                }
                col += 1usize
            }
            var vn = 0usize
            if cv > 0usize {
                ordv[0usize] = vt[0usize]
                vn = 1usize
                let firstv = m1[0usize]
                var nextv = m2[0usize]
                m1[0usize] = -1i64
                m2[0usize] = -1i64
                var looking = true
                var closed = true
                while looking {
                    var row = cv
                    var side = 0usize
                    var r = 0usize
                    while r < cv && row == cv {
                        if m1[r] == nextv {
                            row = r
                            side = 1usize
                        }
                        r += 1usize
                    }
                    r = 0usize
                    while r < cv && row == cv {
                        if m2[r] == nextv {
                            row = r
                            side = 2usize
                        }
                        r += 1usize
                    }
                    if row == cv {
                        closed = false
                        looking = false
                    } else {
                        ordv[vn] = vt[row]
                        vn += 1usize
                        if side == 1usize {
                            nextv = m2[row]
                        } else {
                            nextv = m1[row]
                        }
                        m1[row] = -1i64
                        m2[row] = -1i64
                        if nextv == firstv { looking = false }
                    }
                }
                if !closed { vn = 0usize }
            }
            if vn > 0usize {
                cells += 1usize
                var s2 = 0.0f64
                var k = 0usize
                while k < vn {
                    let nk = (k + 1usize) % vn
                    let v = usize(ordv[k])
                    let w = usize(ordv[nk])
                    s2 += cc[5usize * v] * cc[5usize * w + 1usize] - cc[5usize * v + 1usize] * cc[5usize * w]
                    h21 += f64(site + 1usize) * f64(k + 1usize) * f64(ordv[k] + 1i64)
                    h22 += f64(site + 1usize) * f64(k + 1usize) * cc[5usize * v]
                    h23 += f64(site + 1usize) * f64(k + 1usize) * cc[5usize * v + 1usize]
                    k += 1usize
                }
                total += math.abs[f64](s2) / 2.0f64
            }
            site += 1usize
        }
        if op == 8usize { ret f64(cells) }
        if op == 9usize { ret total }
        if op == 21usize { ret h21 }
        if op == 22usize { ret h22 }
        ret h23
    }
    var xlo = cc[0usize]
    var xhi = cc[0usize]
    var ylo = cc[1usize]
    var yhi = cc[1usize]
    t = 1usize
    while t < nt {
        if cc[5usize * t] < xlo { xlo = cc[5usize * t] }
        if cc[5usize * t] > xhi { xhi = cc[5usize * t] }
        if cc[5usize * t + 1usize] < ylo { ylo = cc[5usize * t + 1usize] }
        if cc[5usize * t + 1usize] > yhi { yhi = cc[5usize * t + 1usize] }
        t += 1usize
    }
    var dmax = xhi - xlo
    if yhi - ylo > dmax { dmax = yhi - ylo }
    let xy = sh.af(a, 2usize * n)
    var i = 0usize
    while i < n {
        xy[2usize * i] = x[i]
        xy[2usize * i + 1usize] = y[i]
        i += 1usize
    }
    let nn = sh.ai(a, 3usize * nt + 3usize)
    let dxs = sh.af(a, 3usize * nt + 3usize)
    let dys = sh.af(a, 3usize * nt + 3usize)
    let dm = sh.af(a, 2usize)
    let pp = sh.ai(a, 3usize)
    t = 0usize
    while t < nt {
        nn[3usize * t] = td[6usize * t + 3usize] + 1i64
        nn[3usize * t + 1usize] = td[6usize * t + 4usize] + 1i64
        nn[3usize * t + 2usize] = td[6usize * t + 5usize] + 1i64
        t += 1usize
    }
    var cnt = 0usize
    t = 0usize
    while t < nt {
        if cc[5usize * t + 3usize] > 0.0f64 {
            let z0 = nn[3usize * t] == 0i64
            let z1 = nn[3usize * t + 1usize] == 0i64
            let z2 = nn[3usize * t + 2usize] == 0i64
            var zc = 0usize
            if z0 { zc += 1usize }
            if z1 { zc += 1usize }
            if z2 { zc += 1usize }
            pp[0usize] = td[6usize * t]
            pp[1usize] = td[6usize * t + 1usize]
            pp[2usize] = td[6usize * t + 2usize]
            let x0 = cc[5usize * t]
            let y0 = cc[5usize * t + 1usize]
            if zc == 1usize {
                var ns1 = n
                var ns2 = n
                var e = 0usize
                while e < 3usize {
                    if onhull[usize(pp[e])] == 1usize {
                        if ns1 == n {
                            ns1 = usize(pp[e])
                        } else if ns2 == n {
                            ns2 = usize(pp[e])
                        }
                    }
                    e += 1usize
                }
                var hv = 0usize
                e = 0usize
                while e < 3usize {
                    hv += onhull[usize(pp[e])]
                    e += 1usize
                }
                if hv == 2usize {
                    dummy_node(xy, n, x0, y0, x[ns1], y[ns1], x[ns2], y[ns2], dmax, dm)
                    dxs[cnt] = dm[0usize]
                    dys[cnt] = dm[1usize]
                    cnt += 1usize
                    var slot = 0usize
                    if z1 { slot = 1usize }
                    if z2 { slot = 2usize }
                    nn[3usize * t + slot] = 0i64 - i64(cnt)
                }
            }
            if zc >= 2usize {
                var id = 0usize
                while id < 3usize {
                    let opp = (id + 2usize) % 3usize
                    var on_b = z0
                    if opp == 1usize { on_b = z1 }
                    if opp == 2usize { on_b = z2 }
                    if on_b {
                        let f = usize(pp[id])
                        let g = usize(pp[(id + 1usize) % 3usize])
                        dummy_node(xy, n, x0, y0, x[f], y[f], x[g], y[g], dmax, dm)
                        dxs[cnt] = dm[0usize]
                        dys[cnt] = dm[1usize]
                        cnt += 1usize
                        if nn[3usize * t] == 0i64 {
                            nn[3usize * t] = 0i64 - i64(cnt)
                        } else if nn[3usize * t + 1usize] == 0i64 {
                            nn[3usize * t + 1usize] = 0i64 - i64(cnt)
                        } else if nn[3usize * t + 2usize] == 0i64 {
                            nn[3usize * t + 2usize] = 0i64 - i64(cnt)
                        }
                    }
                    id += 1usize
                }
            }
        }
        t += 1usize
    }
    if op == 13usize { ret f64(cnt) }
    var sum = 0.0f64
    var k = 0usize
    while k < cnt {
        if op == 14usize { sum += dxs[k] }
        if op == 15usize { sum += dys[k] }
        if op == 19usize { sum += f64(k + 1usize) * dxs[k] }
        if op == 20usize { sum += f64(k + 1usize) * dys[k] }
        k += 1usize
    }
    if op >= 16usize && op <= 18usize {
        t = 0usize
        while t < nt {
            sum += f64(t + 1usize) * f64(nn[3usize * t + (op - 16usize)])
            t += 1usize
        }
    }
    ret sum
}

// interp's local cubic fit at (px, py) (pD in partDeriv.cpp, degree 3, gaussian kernel, h = 0, QR solver): the bandwidth is the nnx-th sorted distance from data point 0
// to the data points and the query (extendNN), nnx = 10 (n - 1 when that is n); weights sqrt of the product gaussian kernel at bw / 3; weighted unpivoted Householder QR
// as Eigen's HouseholderQR. out = [z, zx, zy, zxy, zxx, zyy] in the interp sign convention. Needs n > 10.
fn pd_fit(a: *mem.Arena, x: []const f64, y: []const f64, z: []const f64, n: usize, px: f64, py: f64, out: []f64) -> bool {
    let (d, e1) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok { ret false }
    var i = 0usize
    while i < n {
        let dx = x[0usize] - x[i]
        let dy = y[0usize] - y[i]
        d[i] = math.sqrt[f64](dx * dx + dy * dy)
        i += 1usize
    }
    let qx = x[0usize] - px
    let qy = y[0usize] - py
    d[n] = math.sqrt[f64](qx * qx + qy * qy)
    // insertion sort of the n + 1 distances
    i = 1usize
    while i <= n {
        let v = d[i]
        var j = i
        while j > 0usize && d[j - 1usize] > v {
            d[j] = d[j - 1usize]
            j -= 1usize
        }
        d[j] = v
        i += 1usize
    }
    var nnx = 10usize
    if nnx == n { nnx = n - 1usize }
    let bw = d[nnx] / 3.0f64
    let pi = 3.14159265358979323846f64
    let (m, e2) = mem.alloc[f64](a, n * 10usize)
    if e2 != ok { ret false }
    let (rhs, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret false }
    i = 0usize
    while i < n {
        let ux = px - x[i]
        let uy = py - y[i]
        let t1 = (x[i] - px) / bw
        let t2 = (y[i] - py) / bw
        let w = math.sqrt[f64](1.0f64 / (2.0f64 * pi) * math.exp[f64](-0.5f64 * (t1 * t1 + t2 * t2)))
        m[i * 10usize] = w
        m[i * 10usize + 1usize] = w * ux
        m[i * 10usize + 2usize] = w * uy
        m[i * 10usize + 3usize] = w * (ux * uy)
        m[i * 10usize + 4usize] = w * (ux * ux)
        m[i * 10usize + 5usize] = w * (uy * uy)
        m[i * 10usize + 6usize] = w * (ux * ux * uy)
        m[i * 10usize + 7usize] = w * (ux * uy * uy)
        m[i * 10usize + 8usize] = w * (ux * ux * ux)
        m[i * 10usize + 9usize] = w * (uy * uy * uy)
        rhs[i] = w * z[i]
        i += 1usize
    }
    var k = 0usize
    while k < 10usize {
        var tail = 0.0f64
        i = k + 1usize
        while i < n {
            tail += m[i * 10usize + k] * m[i * 10usize + k]
            i += 1usize
        }
        let c0 = m[k * 10usize + k]
        var tau = 0.0f64
        var beta = c0
        if tail > 2.2250738585072014e-308f64 {
            beta = math.sqrt[f64](c0 * c0 + tail)
            if c0 >= 0.0f64 { beta = -beta }
            tau = (beta - c0) / beta
            i = k + 1usize
            while i < n {
                m[i * 10usize + k] = m[i * 10usize + k] / (c0 - beta)
                i += 1usize
            }
        } else {
            i = k + 1usize
            while i < n {
                m[i * 10usize + k] = 0.0f64
                i += 1usize
            }
        }
        m[k * 10usize + k] = beta
        var col = k + 1usize
        while col <= 10usize {
            // column 10 is the right-hand side
            var tmp = 0.0f64
            if col < 10usize { tmp = m[k * 10usize + col] } else { tmp = rhs[k] }
            i = k + 1usize
            while i < n {
                if col < 10usize { tmp += m[i * 10usize + k] * m[i * 10usize + col] } else { tmp += m[i * 10usize + k] * rhs[i] }
                i += 1usize
            }
            if col < 10usize { m[k * 10usize + col] = m[k * 10usize + col] - tau * tmp } else { rhs[k] = rhs[k] - tau * tmp }
            i = k + 1usize
            while i < n {
                if col < 10usize { m[i * 10usize + col] = m[i * 10usize + col] - tau * m[i * 10usize + k] * tmp } else { rhs[i] = rhs[i] - tau * m[i * 10usize + k] * tmp }
                i += 1usize
            }
            col += 1usize
        }
        k += 1usize
    }
    let (bh, e4) = mem.alloc[f64](a, 10usize)
    if e4 != ok { ret false }
    var r = 10usize
    while r > 0usize {
        r -= 1usize
        var s = rhs[r]
        var c = r + 1usize
        while c < 10usize {
            s = s - m[r * 10usize + c] * bh[c]
            c += 1usize
        }
        bh[r] = s / m[r * 10usize + r]
    }
    out[0usize] = bh[0usize]
    out[1usize] = -bh[1usize]
    out[2usize] = -bh[2usize]
    out[3usize] = bh[3usize]
    out[4usize] = 2.0f64 * bh[4usize]
    out[5usize] = 2.0f64 * bh[5usize]
    ret true
}

// one rotation of the Akima quintic on a triangle (a, b, c): value of the quintic at (px, py) times the barycentric weight of a; d* = [zx, zy, zxy, zxx, zyy] at the vertex
fn akima_rot(xa: f64, ya: f64, za: f64, xb: f64, yb: f64, zb: f64, xc: f64, yc: f64, zc: f64, dv: []const f64, oa: usize, ob: usize, oc: usize, px: f64, py: f64, out: []f64) {
    let a = xb - xa
    let b = xc - xa
    let c = yb - ya
    let d = yc - ya
    let dlt = a * d - b * c
    let ap = d / dlt
    let bp = -b / dlt
    let cp = -c / dlt
    let dp = a / dlt
    let ex = -ap * xa - bp * ya
    let ey = -cp * xa - dp * ya
    // gradient and Hessian in (u, v): M^T g and M H M^T with M = A^-1 = [[a, b], [c, d]]
    let z_u_a = a * dv[oa + 0usize] + c * dv[oa + 1usize]
    let z_v_a = b * dv[oa + 0usize] + d * dv[oa + 1usize]
    let z_u_b = a * dv[ob + 0usize] + c * dv[ob + 1usize]
    let z_u_c = a * dv[oc + 0usize] + c * dv[oc + 1usize]
    let z_v_c = b * dv[oc + 0usize] + d * dv[oc + 1usize]
    let z_v_b = b * dv[ob + 0usize] + d * dv[ob + 1usize]
    let z_uu_a = (a * dv[oa + 3usize] + b * dv[oa + 2usize]) * a + (a * dv[oa + 2usize] + b * dv[oa + 4usize]) * b
    let z_vv_a = (c * dv[oa + 3usize] + d * dv[oa + 2usize]) * c + (c * dv[oa + 2usize] + d * dv[oa + 4usize]) * d
    let z_uu_b = (a * dv[ob + 3usize] + b * dv[ob + 2usize]) * a + (a * dv[ob + 2usize] + b * dv[ob + 4usize]) * b
    let z_uv_b = (c * dv[ob + 3usize] + d * dv[ob + 2usize]) * a + (c * dv[ob + 2usize] + d * dv[ob + 4usize]) * b
    let z_vv_b = (c * dv[ob + 3usize] + d * dv[ob + 2usize]) * c + (c * dv[ob + 2usize] + d * dv[ob + 4usize]) * d
    let z_uu_c = (a * dv[oc + 3usize] + b * dv[oc + 2usize]) * a + (a * dv[oc + 2usize] + b * dv[oc + 4usize]) * b
    let z_uv_c = (c * dv[oc + 3usize] + d * dv[oc + 2usize]) * a + (c * dv[oc + 2usize] + d * dv[oc + 4usize]) * b
    let z_vv_c = (c * dv[oc + 3usize] + d * dv[oc + 2usize]) * c + (c * dv[oc + 2usize] + d * dv[oc + 4usize]) * d
    let z_uv_a = (c * dv[oa + 3usize] + d * dv[oa + 2usize]) * a + (c * dv[oa + 2usize] + d * dv[oa + 4usize]) * b
    let a00 = za
    let a10 = z_u_a
    let a01 = z_v_a
    let a20 = z_uu_a * 0.5f64
    let a11 = z_uv_a
    let a02 = z_vv_a * 0.5f64
    var h1 = zb - a00 - a10 - a20
    var h2 = z_u_b - a10 - z_uu_a
    var h3 = z_uu_b - z_uu_a
    let a30 = 10.0f64 * h1 - 4.0f64 * h2 + 0.5f64 * h3
    let a40 = -15.0f64 * h1 + 7.0f64 * h2 - h3
    let a50 = 6.0f64 * h1 - 3.0f64 * h2 + 0.5f64 * h3
    h1 = zc - a00 - a01 - a02
    h2 = z_v_c - a01 - z_vv_a
    h3 = z_vv_c - z_vv_a
    let a03 = 10.0f64 * h1 - 4.0f64 * h2 + 0.5f64 * h3
    let a04 = -15.0f64 * h1 + 7.0f64 * h2 - h3
    let a05 = 6.0f64 * h1 - 3.0f64 * h2 + 0.5f64 * h3
    let lusq = a * a + c * c
    let lvsq = b * b + d * d
    let spuv = a * b + c * d
    let a41 = 5.0f64 * spuv / lusq * a50
    let a14 = 5.0f64 * spuv / lvsq * a05
    h1 = z_v_b - a01 - a11 - a41
    h2 = z_uv_b - a11 - 4.0f64 * a41
    let a21 = 3.0f64 * h1 - h2
    let a31 = -2.0f64 * h1 + h2
    h1 = z_u_c - a10 - a11 - a14
    h2 = z_uv_c - a11 - 4.0f64 * a14
    let a12 = 3.0f64 * h1 - h2
    let a13 = -2.0f64 * h1 + h2
    let e1 = (lvsq - spuv) / ((lvsq - spuv) + (lusq - spuv))
    let e2 = 1.0f64 - e1
    let g1 = 5.0f64 * e1 - 2.0f64
    let g2 = 1.0f64 - g1
    h1 = 5.0f64 * (e1 * (a50 - a41) + e2 * (a05 - a14)) + (a41 + a14)
    h2 = 0.5f64 * z_vv_b - a02 - a12
    h3 = 0.5f64 * z_uu_c - a20 - a21
    let a22 = h1 + g1 * h2 + g2 * h3
    let a32 = h2 - a22
    let a23 = h3 - a22
    let u = ap * px + bp * py + ex
    let v = cp * px + dp * py + ey
    out[0usize] = v * (a01 + u * (u * (a21 + u * (a41 * u + a31)) + a11) + v * (v * (a03 + u * (a23 * u + a13) + v * (a05 * v + a14 * u + a04)) + u * (a12 + u * (a32 * u + a22)) + a02)) + u * (a10 + u * (u * (a30 + u * (a50 * u + a40)) + a20)) + a00
    out[1usize] = ((yb - yc) * (px - xc) + (xc - xb) * (py - yc)) / ((yb - yc) * (xa - xc) + (xc - xb) * (ya - yc))
}

// interp(linear = FALSE) in the triangle (ia, ib, ic): the quintic averaged over the three vertex rotations with barycentric weights (baryweight = TRUE)
fn akima_value(a: *mem.Arena, x: []const f64, y: []const f64, z: []const f64, n: usize, ia: usize, ib: usize, ic: usize, px: f64, py: f64) -> f64 {
    let (dv, e1) = mem.alloc[f64](a, 18usize)
    if e1 != ok { ret nan_value() }
    let (fit, e2) = mem.alloc[f64](a, 6usize)
    if e2 != ok { ret nan_value() }
    let (one, e3) = mem.alloc[f64](a, 2usize)
    if e3 != ok { ret nan_value() }
    var s = 0usize
    while s < 3usize {
        var v = ia
        if s == 1usize { v = ib }
        if s == 2usize { v = ic }
        if !pd_fit(a, x, y, z, n, x[v], y[v], fit) { ret nan_value() }
        var q = 0usize
        while q < 5usize {
            dv[s * 6usize + q] = fit[q + 1usize]
            q += 1usize
        }
        s += 1usize
    }
    var total = 0.0f64
    var o = 0usize
    while o < 3usize {
        var i0 = ia
        var i1 = ib
        var i2 = ic
        var s0 = 0usize
        var s1 = 1usize
        var s2 = 2usize
        if o == 1usize {
            i0 = ib
            i1 = ic
            i2 = ia
            s0 = 1usize
            s1 = 2usize
            s2 = 0usize
        }
        if o == 2usize {
            i0 = ic
            i1 = ia
            i2 = ib
            s0 = 2usize
            s1 = 0usize
            s2 = 1usize
        }
        akima_rot(x[i0], y[i0], z[i0], x[i1], y[i1], z[i1], x[i2], y[i2], z[i2], dv, s0 * 6usize, s1 * 6usize, s2 * 6usize, px, py, one)
        total += one[1usize] * one[0usize]
        o += 1usize
    }
    ret total
}

fn tri_answer(a: *mem.Arena, g: []const f64) -> f64 {
    let op = usize(g[0usize])
    let idx = usize(g[1usize])
    let n = usize(g[2usize])
    let nq = usize(g[3usize])
    let (x, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret nan_value() }
    let (y, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret nan_value() }
    let (z, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret nan_value() }
    var i = 0usize
    while i < n {
        x[i] = g[4usize + i]
        y[i] = g[4usize + n + i]
        z[i] = g[4usize + 2usize * n + i]
        i += 1usize
    }
    let qx = 4usize + 3usize * n
    let qy = qx + nq
    let td = sh.ai(a, 6usize * (2usize * n + 8usize))
    let nt0 = sh.shull(a, x, y, n, td)
    if nt0 < 0i64 { ret nan_value() }
    let nt = usize(nt0)
    let (tri, e4) = mem.alloc[usize](a, 3usize * nt + 3usize)
    if e4 != ok { ret nan_value() }
    var t = 0usize
    while t < nt {
        tri[3usize * t] = usize(td[6usize * t])
        tri[3usize * t + 1usize] = usize(td[6usize * t + 1usize])
        tri[3usize * t + 2usize] = usize(td[6usize * t + 2usize])
        t += 1usize
    }
    // a neighbour of -1 is a hull edge
    var nh = 0usize
    let (onhull, e5) = mem.alloc[usize](a, n)
    if e5 != ok { ret nan_value() }
    i = 0usize
    while i < n {
        onhull[i] = 0usize
        i += 1usize
    }
    t = 0usize
    while t < nt {
        var s = 0usize
        while s < 3usize {
            if td[6usize * t + 3usize + s] < 0i64 {
                nh += 1usize
                onhull[tri[3usize * t + (s + 1usize) % 3usize]] = 1usize
                onhull[tri[3usize * t + (s + 2usize) % 3usize]] = 1usize
            }
            s += 1usize
        }
        t += 1usize
    }
    if op == 0usize { ret f64(nt) }
    if op == 1usize { ret f64((3usize * nt + nh) / 2usize) }
    if op == 2usize { ret f64(nh) }
    let (cc, e6) = mem.alloc[f64](a, 5usize * nt + 5usize)
    if e6 != ok { ret nan_value() }
    var sarea = 0.0f64
    var sr = 0.0f64
    var sx = 0.0f64
    var sy = 0.0f64
    var hash = 0.0f64
    t = 0usize
    let (one, e7) = mem.alloc[f64](a, 5usize)
    if e7 != ok { ret nan_value() }
    while t < nt {
        let ia = tri[3usize * t]
        let ib = tri[3usize * t + 1usize]
        let ic = tri[3usize * t + 2usize]
        circum(x, y, ia, ib, ic, one)
        var f = 0usize
        while f < 5usize {
            cc[5usize * t + f] = one[f]
            f += 1usize
        }
        sx += one[0usize]
        sy += one[1usize]
        sr += one[2usize]
        sarea += one[3usize]
        // sort the three indices
        var s1 = ia
        var s2 = ib
        var s3 = ic
        if s1 > s2 {
            let w = s1
            s1 = s2
            s2 = w
        }
        if s2 > s3 {
            let w = s2
            s2 = s3
            s3 = w
        }
        if s1 > s2 {
            let w = s1
            s1 = s2
            s2 = w
        }
        hash += f64(((s1 + 1usize) * 131usize + (s2 + 1usize)) * 131usize + (s3 + 1usize))
        t += 1usize
    }
    if op == 3usize { ret sarea }
    if op == 4usize { ret sr }
    if op == 5usize { ret sx }
    if op == 6usize { ret sy }
    if op == 7usize { ret hash }
    if op == 8usize || op == 9usize || (op >= 13usize && op <= 40usize) {
        ret ord_answer(a, op, x, y, n, td, nt, cc, onhull)
    }
    // linear interpolation at query idx
    let px = g[qx + idx]
    let py = g[qy + idx]
    var found = false
    var ft = 0usize
    var val = 0.0f64
    t = 0usize
    while t < nt && !found {
        let ia = tri[3usize * t]
        let ib = tri[3usize * t + 1usize]
        let ic = tri[3usize * t + 2usize]
        let dd = (x[ib] - x[ia]) * (y[ic] - y[ia]) - (y[ib] - y[ia]) * (x[ic] - x[ia])
        let l2 = ((px - x[ia]) * (y[ic] - y[ia]) - (py - y[ia]) * (x[ic] - x[ia])) / dd
        let l3 = ((x[ib] - x[ia]) * (py - y[ia]) - (y[ib] - y[ia]) * (px - x[ia])) / dd
        let l1 = 1.0f64 - l2 - l3
        if l1 >= 0.0f64 && l2 >= 0.0f64 && l3 >= 0.0f64 {
            found = true
            ft = t
            val = l1 * z[ia] + l2 * z[ib] + l3 * z[ic]
        }
        t += 1usize
    }
    if op == 10usize {
        if found { ret 1.0f64 }
        ret 0.0f64
    }
    if op == 12usize {
        if !found { ret nan_value() }
        ret akima_value(a, x, y, z, n, tri[3usize * ft], tri[3usize * ft + 1usize], tri[3usize * ft + 2usize], px, py)
    }
    ret val
}

// interp::circles: the polyline it passes to lines() for each circle, 360 points at phi = seq(0, 2 * pi, length = 360) and then (x + r, y).
// args = [op, n, x (n), y (n), r (n)]; op 0 the sum of position * x over every point of every polyline, 1 the same with y, 2 the number of points (positions run across the circles)
fn circles_answer(g: []const f64) -> f64 {
    let op = usize(g[0usize])
    let n = usize(g[1usize])
    let pi = 3.14159265358979323846f64
    let by = 2.0f64 * pi / 359.0f64
    var sum = 0.0f64
    var pos = 0usize
    var i = 0usize
    while i < n {
        let cx = g[2usize + i]
        let cy = g[2usize + n + i]
        let cr = g[2usize + 2usize * n + i]
        var k = 0usize
        while k < 361usize {
            var px = cx + cr
            var py = cy
            if k < 360usize {
                let phi = f64(k) * by
                px = cx + cr * math.cos[f64](phi)
                py = cy + cr * math.sin[f64](phi)
            }
            pos += 1usize
            if op == 0usize { sum += f64(pos) * px }
            if op == 1usize { sum += f64(pos) * py }
            k += 1usize
        }
        i += 1usize
    }
    if op == 2usize { ret f64(pos) }
    ret sum
}

fn bil_answer(a: *mem.Arena, g: []const f64) -> f64 {
    let op = usize(g[0usize])
    let idx = usize(g[1usize])
    let nx = usize(g[2usize])
    let ny = usize(g[3usize])
    let xb = 4usize
    let yb = xb + nx
    let zb = yb + ny
    let nq = usize(g[zb + nx * ny])
    let qx = zb + nx * ny + 1usize
    let qy = qx + nq
    let px = g[qx + idx]
    let py = g[qy + idx]
    let inside = px >= g[xb] && px <= g[xb + nx - 1usize] && py >= g[yb] && py <= g[yb + ny - 1usize]
    if op == 0usize {
        if inside { ret 1.0f64 }
        ret 0.0f64
    }
    var i = 0usize
    while i + 2usize < nx && g[xb + i + 1usize] <= px { i += 1usize }
    var j = 0usize
    while j + 2usize < ny && g[yb + j + 1usize] <= py { j += 1usize }
    let ex = (px - g[xb + i]) / (g[xb + i + 1usize] - g[xb + i])
    let ey = (py - g[yb + j]) / (g[yb + j + 1usize] - g[yb + j])
    let z00 = g[zb + j * nx + i]
    let z10 = g[zb + j * nx + i + 1usize]
    let z01 = g[zb + (j + 1usize) * nx + i]
    let z11 = g[zb + (j + 1usize) * nx + i + 1usize]
    ret z00 * (1.0f64 - ex) * (1.0f64 - ey) + z10 * ex * (1.0f64 - ey) + z01 * (1.0f64 - ex) * ey + z11 * ex * ey
}
