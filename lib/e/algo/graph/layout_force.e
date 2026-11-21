// R igraph force-directed and spectral layouts, ported from igraph 2.3.4 (C core layout/*.c): layout_with_fr (with and without the grid),
// layout_with_kk, layout_with_graphopt and layout_with_mds on a connected graph. Random starts draw from R's streams
// through e.algo.graph.games.gunif, as igraph's R binding does. Coordinates are row-major, n rows of 2. An edge list is
// flat pairs, as e.algo.graph.games builds them.
//
// Not here: 3-D variants, minx/maxx style bounds. layout_with_mds on a disconnected graph is in e.algo.graph.layout_merge.

use e.algo.graph.games as gg
use e.algo.linalg.lapack_syevr as lap
use e.algo.rand.r as rg
use e.math
use e.mem
use e.os

fn pi() -> f64 { ret 3.141592653589793f64 }

// the vertex count of the component of vertex 0 (weak), by union-find on the pairs
fn connected(a: *mem.Arena, n: usize, ed: []const i64) -> bool {
    if n <= 1usize { ret true }
    let par = gg.zi(a, n)
    var i = 0usize
    while i < n {
        par[i] = i64(i)
        i += 1usize
    }
    var k = 0usize
    while k + 1usize < ed.len {
        var x = ed[k]
        var y = ed[k + 1usize]
        while par[usize(x)] != x { x = par[usize(x)] }
        while par[usize(y)] != y { y = par[usize(y)] }
        if x != y { par[usize(x)] = y }
        k += 2usize
    }
    var r0 = 0i64
    while par[usize(r0)] != r0 { r0 = par[usize(r0)] }
    let root = r0
    i = 1usize
    while i < n {
        var z = i64(i)
        while par[usize(z)] != z { z = par[usize(z)] }
        if z != root { ret false }
        i += 1usize
    }
    ret true
}

// layout_with_fr(niter, start.temp), random start, without the grid; weights empty for none
fn fr(a: *mem.Arena, r: *rg.Rng, n: usize, ed: []const i64, niter: usize, start_temp: f64, weights: []const f64) -> []f64 {
    ret fr_run(a, r, n, ed, niter, start_temp, weights, false)
}

// layout_with_fr(grid = "grid"): repulsion only between vertices in neighbouring cells of a fixed 2 x 2 grid, as igraph runs above 1000 vertices
fn fr_grid(a: *mem.Arena, r: *rg.Rng, n: usize, ed: []const i64, niter: usize, start_temp: f64, weights: []const f64) -> []f64 {
    ret fr_run(a, r, n, ed, niter, start_temp, weights, true)
}

fn grid_cell(c: f64, lo: f64, hi: f64, delta: f64, steps: usize) -> usize {
    if c <= lo { ret 0usize }
    if c >= hi { ret steps - 1usize }
    ret usize(math.floor[f64]((c - lo) / delta))
}

fn fr_run(a: *mem.Arena, r: *rg.Rng, n: usize, ed: []const i64, niter: usize, start_temp: f64, weights: []const f64, grid: bool) -> []f64 {
    let res = gg.zf(a, 2usize * n)
    let dispx = gg.zf(a, n)
    let dispy = gg.zf(a, n)
    let ne = ed.len / 2usize
    var temp = start_temp
    let difftemp = start_temp / f64(niter)
    let conn = connected(a, n, ed)
    var cc = 0.0f64
    let nf = f64(n)
    if !conn { cc = nf * math.sqrt[f64](nf) }
    let half = math.sqrt[f64](nf) / 2.0f64
    var q = 0usize
    while q < 2usize * n {
        res[q] = gg.gunif(r, 0.0f64 - half, half)
        q += 1usize
    }
    // the grid is filled once from the start layout and never updated; a cell chain lists its vertices last-added first
    let gw = math.sqrt[f64](nf)
    var sx = usize(math.ceil[f64](gw / 2.0f64))
    var sy = sx
    if !grid {
        sx = 1usize
        sy = 1usize
    }
    let start = gg.alloc_u(a, sx * sy)
    let nxt = gg.alloc_u(a, n)
    let ncell = gg.alloc_u(a, 4usize)
    var z = 0usize
    while z < sx * sy {
        start[z] = 0usize
        z += 1usize
    }
    if grid {
        z = 0usize
        while z < n {
            let cx = grid_cell(res[z * 2usize], 0.0f64 - gw / 2.0f64, gw / 2.0f64, 2.0f64, sx)
            let cy = grid_cell(res[z * 2usize + 1usize], 0.0f64 - gw / 2.0f64, gw / 2.0f64, 2.0f64, sy)
            nxt[z] = start[cy * sx + cx]
            start[cy * sx + cx] = z + 1usize
            z += 1usize
        }
    }
    var it = 0usize
    while it < niter {
        var v = 0usize
        while v < n {
            dispx[v] = 0.0f64
            dispy[v] = 0.0f64
            v += 1usize
        }
        var cy = 0usize
        while grid && cy < sy {
            var cx = 0usize
            while cx < sx {
                var vi = start[cy * sx + cx]
                while vi != 0usize {
                    let gv = vi - 1usize
                    // after the rest of v's own cell: the diagonal, up and right cells, in that order
                    var nc = 0usize
                    if cx != sx - 1usize && cy != sy - 1usize {
                        ncell[nc] = (cy + 1usize) * sx + cx + 1usize
                        nc += 1usize
                    }
                    if cy != sy - 1usize {
                        ncell[nc] = (cy + 1usize) * sx + cx
                        nc += 1usize
                    }
                    if cx != sx - 1usize {
                        ncell[nc] = cy * sx + cx + 1usize
                        nc += 1usize
                    }
                    var ui = nxt[gv]
                    var ci = 0usize
                    var more = true
                    while more {
                        if ui == 0usize {
                            if ci < nc {
                                ui = start[ncell[ci]]
                                ci += 1usize
                            } else {
                                more = false
                            }
                        } else {
                            let gu = ui - 1usize
                            var dx = res[gv * 2usize] - res[gu * 2usize]
                            var dy = res[gv * 2usize + 1usize] - res[gu * 2usize + 1usize]
                            var dlen = dx * dx + dy * dy
                            while dlen == 0.0f64 {
                                dx = gg.gunif(r, 0.0f64 - 1e-9f64, 1e-9f64)
                                dy = gg.gunif(r, 0.0f64 - 1e-9f64, 1e-9f64)
                                dlen = dx * dx + dy * dy
                            }
                            if dlen < 4.0f64 {
                                dispx[gv] += dx / dlen
                                dispy[gv] += dy / dlen
                                dispx[gu] -= dx / dlen
                                dispy[gu] -= dy / dlen
                            }
                            ui = nxt[gu]
                        }
                    }
                    vi = nxt[gv]
                }
                cx += 1usize
            }
            cy += 1usize
        }
        v = 0usize
        while v < n && !grid {
            var u = v + 1usize
            while u < n {
                var dx = res[v * 2usize] - res[u * 2usize]
                var dy = res[v * 2usize + 1usize] - res[u * 2usize + 1usize]
                var dlen = dx * dx + dy * dy
                while dlen == 0.0f64 {
                    dx = gg.gunif(r, 0.0f64 - 1e-9f64, 1e-9f64)
                    dy = gg.gunif(r, 0.0f64 - 1e-9f64, 1e-9f64)
                    dlen = dx * dx + dy * dy
                }
                if conn {
                    dispx[v] += dx / dlen
                    dispy[v] += dy / dlen
                    dispx[u] -= dx / dlen
                    dispy[u] -= dy / dlen
                } else {
                    let rdlen = math.sqrt[f64](dlen)
                    dispx[v] += dx * (cc - dlen * rdlen) / (dlen * cc)
                    dispy[v] += dy * (cc - dlen * rdlen) / (dlen * cc)
                    dispx[u] -= dx * (cc - dlen * rdlen) / (dlen * cc)
                    dispy[u] -= dy * (cc - dlen * rdlen) / (dlen * cc)
                }
                u += 1usize
            }
            v += 1usize
        }
        var e = 0usize
        while e < ne {
            let v2 = usize(ed[2usize * e])
            let u2 = usize(ed[2usize * e + 1usize])
            let dx = res[v2 * 2usize] - res[u2 * 2usize]
            let dy = res[v2 * 2usize + 1usize] - res[u2 * 2usize + 1usize]
            var w = 1.0f64
            if weights.len > 0usize { w = weights[e] }
            let dlen = math.sqrt[f64](dx * dx + dy * dy) * w
            dispx[v2] -= dx * dlen
            dispy[v2] -= dy * dlen
            dispx[u2] += dx * dlen
            dispy[u2] += dy * dlen
            e += 1usize
        }
        v = 0usize
        while v < n {
            var dx = dispx[v] + gg.gunif(r, 0.0f64 - 1e-9f64, 1e-9f64)
            var dy = dispy[v] + gg.gunif(r, 0.0f64 - 1e-9f64, 1e-9f64)
            let displen = math.sqrt[f64](dx * dx + dy * dy)
            if displen > temp {
                dx *= temp / displen
                dy *= temp / displen
            }
            if displen > 0.0f64 {
                res[v * 2usize] += dx
                res[v * 2usize + 1usize] += dy
            }
            v += 1usize
        }
        temp -= difftemp
        it += 1usize
    }
    ret res[0usize..2usize * n]
}

// BFS (unweighted) or Dijkstra distances from every vertex, undirected; unreachable is infinity
fn distances(a: *mem.Arena, n: usize, ed: []const i64, weights: []const f64) -> []f64 {
    let inf = 1.0f64 / 0.0f64
    let d = gg.zf(a, n * n)
    let ne = ed.len / 2usize
    let done = gg.zb(a, n)
    var s = 0usize
    while s < n {
        var i = 0usize
        while i < n {
            d[s * n + i] = inf
            done[i] = false
            i += 1usize
        }
        d[s * n + s] = 0.0f64
        var round = 0usize
        while round < n {
            var best = inf
            var bv = n
            i = 0usize
            while i < n {
                if !done[i] && d[s * n + i] < best {
                    best = d[s * n + i]
                    bv = i
                }
                i += 1usize
            }
            if bv == n { break }
            done[bv] = true
            var e = 0usize
            while e < ne {
                let x = usize(ed[2usize * e])
                let y = usize(ed[2usize * e + 1usize])
                var w = 1.0f64
                if weights.len > 0usize { w = weights[e] }
                if x == bv && d[s * n + bv] + w < d[s * n + y] { d[s * n + y] = d[s * n + bv] + w }
                if y == bv && d[s * n + bv] + w < d[s * n + x] { d[s * n + x] = d[s * n + bv] + w }
                e += 1usize
            }
            round += 1usize
        }
        s += 1usize
    }
    ret d
}

// layout_with_kk(maxiter, epsilon, kkconst), circle start; maxiter and kkconst as R's defaults are 50 n and n
fn kk(a: *mem.Arena, n: usize, ed: []const i64, maxiter: usize, epsilon: f64, kkconst: f64, weights: []const f64) -> []f64 {
    let res = gg.zf(a, 2usize * n)
    let nf = f64(n)
    let l0 = math.sqrt[f64](nf)
    var i = 0usize
    while i < n {
        let phi = 2.0f64 * pi() / nf * f64(i)
        res[i * 2usize] = math.cos[f64](phi) * (0.36f64 * l0)
        res[i * 2usize + 1usize] = math.sin[f64](phi) * (0.36f64 * l0)
        i += 1usize
    }
    if n <= 1usize { ret res[0usize..2usize * n] }
    let dij = distances(a, n, ed, weights)
    var maxd = 0.0f64
    var j = 0usize
    while j < n {
        i = j + 1usize
        while i < n {
            let x = dij[i * n + j]
            if x - x == 0.0f64 && x > maxd { maxd = x }
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            if dij[i * n + j] > maxd { dij[i * n + j] = maxd }
            i += 1usize
        }
        j += 1usize
    }
    let ll = l0 / maxd
    let kij = gg.zf(a, n * n)
    let lij = gg.zf(a, n * n)
    j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            if i != j {
                let tmp = dij[i * n + j] * dij[i * n + j]
                kij[i * n + j] = kkconst / tmp
                lij[i * n + j] = ll * dij[i * n + j]
            }
            i += 1usize
        }
        j += 1usize
    }
    let d1 = gg.zf(a, n)
    let d2 = gg.zf(a, n)
    i = 0usize
    while i < n {
        var m = 0usize
        while m < n {
            if i != m {
                let dx = res[m * 2usize] - res[i * 2usize]
                let dy = res[m * 2usize + 1usize] - res[i * 2usize + 1usize]
                let md = math.sqrt[f64](dx * dx + dy * dy)
                d1[m] += kij[m * n + i] * (dx - lij[m * n + i] * dx / md)
                d2[m] += kij[m * n + i] * (dy - lij[m * n + i] * dy / md)
            }
            m += 1usize
        }
        i += 1usize
    }
    var it = 0usize
    while it < maxiter {
        var m = 0usize
        var maxdelta = 0.0f64 - 1.0f64
        i = 0usize
        while i < n {
            let delta = d1[i] * d1[i] + d2[i] * d2[i]
            if delta > maxdelta {
                m = i
                maxdelta = delta
            }
            i += 1usize
        }
        if maxdelta < epsilon { break }
        let oldx = res[m * 2usize]
        let oldy = res[m * 2usize + 1usize]
        var ca = 0.0f64
        var cb = 0.0f64
        var cc = 0.0f64
        i = 0usize
        while i < n {
            if i != m {
                let dx = oldx - res[i * 2usize]
                let dy = oldy - res[i * 2usize + 1usize]
                let dist = math.sqrt[f64](dx * dx + dy * dy)
                let den = dist * (dx * dx + dy * dy)
                ca += kij[m * n + i] * (1.0f64 - lij[m * n + i] * dy * dy / den)
                cb += kij[m * n + i] * lij[m * n + i] * dx * dy / den
                cc += kij[m * n + i] * (1.0f64 - lij[m * n + i] * dx * dx / den)
            }
            i += 1usize
        }
        let myd1 = d1[m]
        let myd2 = d2[m]
        var deltax = 0.0f64
        var deltay = 0.0f64
        if !(myd1 * myd1 + myd2 * myd2 < 1e-13f64 * 1e-13f64) {
            let det = cc * ca - cb * cb
            deltay = (cb * myd1 - ca * myd2) / det
            deltax = (cb * myd2 - cc * myd1) / det
        }
        let newx = oldx + deltax
        let newy = oldy + deltay
        d1[m] = 0.0f64
        d2[m] = 0.0f64
        i = 0usize
        while i < n {
            if i != m {
                let odx = oldx - res[i * 2usize]
                let ody = oldy - res[i * 2usize + 1usize]
                let omd = math.sqrt[f64](odx * odx + ody * ody)
                let ndx = newx - res[i * 2usize]
                let ndy = newy - res[i * 2usize + 1usize]
                let nmd = math.sqrt[f64](ndx * ndx + ndy * ndy)
                d1[i] -= kij[m * n + i] * (0.0f64 - odx + lij[m * n + i] * odx / omd)
                d2[i] -= kij[m * n + i] * (0.0f64 - ody + lij[m * n + i] * ody / omd)
                d1[i] += kij[m * n + i] * (0.0f64 - ndx + lij[m * n + i] * ndx / nmd)
                d2[i] += kij[m * n + i] * (0.0f64 - ndy + lij[m * n + i] * ndy / nmd)
                d1[m] += kij[m * n + i] * (ndx - lij[m * n + i] * ndx / nmd)
                d2[m] += kij[m * n + i] * (ndy - lij[m * n + i] * ndy / nmd)
            }
            i += 1usize
        }
        res[m * 2usize] = newx
        res[m * 2usize + 1usize] = newy
        it += 1usize
    }
    ret res[0usize..2usize * n]
}

// ---- graphopt ----

fn gopt_dist(c: []const f64, x: usize, y: usize) -> f64 {
    let dx = c[x * 2usize] - c[y * 2usize]
    let dy = c[x * 2usize + 1usize] - c[y * 2usize + 1usize]
    ret math.sqrt[f64](dx * dx + dy * dy)
}

// the (x, y) force on this_node from other_node of strength directed_force
fn gopt_axial(c: []const f64, directed_force: f64, distance: f64, other: usize, this: usize) -> (f64, f64) {
    var yd = c[other * 2usize + 1usize] - c[this * 2usize + 1usize]
    if yd < 0.0f64 { yd = 0.0f64 - yd }
    var y = (0.0f64 - 1.0f64) * ((directed_force * yd) / distance)
    var xd = c[other * 2usize] - c[this * 2usize]
    if xd < 0.0f64 { xd = 0.0f64 - xd }
    var x = (0.0f64 - 1.0f64) * ((directed_force * xd) / distance)
    if c[other * 2usize] < c[this * 2usize] { x = x * (0.0f64 - 1.0f64) }
    if c[other * 2usize + 1usize] < c[this * 2usize + 1usize] { y = y * (0.0f64 - 1.0f64) }
    ret (x, y)
}

// layout_with_graphopt: random start in [-1, 1], column by column
fn graphopt(a: *mem.Arena, r: *rg.Rng, n: usize, ed: []const i64, niter: usize, charge: f64, mass: f64, spring_length: f64, spring_constant: f64, max_move: f64) -> []f64 {
    let res = gg.zf(a, 2usize * n)
    let px = gg.zf(a, n)
    let py = gg.zf(a, n)
    let ne = ed.len / 2usize
    var j = 0usize
    while j < 2usize {
        var i = 0usize
        while i < n {
            res[i * 2usize + j] = gg.gunif(r, 0.0f64 - 1.0f64, 1.0f64)
            i += 1usize
        }
        j += 1usize
    }
    var it = niter
    while it > 0usize {
        var v = 0usize
        while v < n {
            px[v] = 0.0f64
            py[v] = 0.0f64
            v += 1usize
        }
        if charge != 0.0f64 {
            var t = 0usize
            while t < n {
                var o = t + 1usize
                while o < n {
                    let distance = gopt_dist(res, t, o)
                    if distance != 0.0f64 && distance < 500.0f64 {
                        let force = 8987500000.0f64 * ((charge * charge) / (distance * distance))
                        let (fx, fy) = gopt_axial(res, force, distance, o, t)
                        px[t] += fx
                        py[t] += fy
                        px[o] -= fx
                        py[o] -= fy
                    }
                    o += 1usize
                }
                t += 1usize
            }
        }
        var e = 0usize
        while e < ne {
            let t = usize(ed[2usize * e])
            let o = usize(ed[2usize * e + 1usize])
            let distance = gopt_dist(res, o, t)
            if distance != 0.0f64 {
                var disp = distance - spring_length
                if disp < 0.0f64 { disp = 0.0f64 - disp }
                let force = (0.0f64 - 1.0f64) * spring_constant * disp
                var fx = 0.0f64
                var fy = 0.0f64
                if distance != spring_length {
                    let (ax, ay) = gopt_axial(res, force, distance, o, t)
                    fx = ax
                    fy = ay
                    if distance < spring_length {
                        fx = (0.0f64 - 1.0f64) * fx
                        fy = (0.0f64 - 1.0f64) * fy
                    }
                    fx = 0.5f64 * fx
                    fy = 0.5f64 * fy
                }
                px[t] += fx
                py[t] += fy
                px[o] -= fx
                py[o] -= fy
            }
            e += 1usize
        }
        v = 0usize
        while v < n {
            var xm = px[v] / mass
            if xm > max_move {
                xm = max_move
            } else if xm < 0.0f64 - max_move {
                xm = 0.0f64 - max_move
            }
            var ym = py[v] / mass
            if ym > max_move {
                ym = max_move
            } else if ym < 0.0f64 - max_move {
                ym = 0.0f64 - max_move
            }
            res[v * 2usize] += xm
            res[v * 2usize + 1usize] += ym
            v += 1usize
        }
        it -= 1usize
    }
    ret res[0usize..2usize * n]
}

// ---- mds ----

// layout_with_mds(dim) of a connected graph on n >= dim vertices
fn mds(a: *mem.Arena, n: usize, ed: []const i64, dim: usize) -> []f64 {
    let out = gg.zf(a, n * dim)
    if n == 1usize { ret out[0usize..dim] }
    if n == 2usize {
        var k = 0usize
        while k < dim {
            out[dim + k] = 1.0f64
            k += 1usize
        }
        ret out[0usize..2usize * dim]
    }
    let none = gg.zf(a, 0usize)
    let dist = distances(a, n, ed, none[0usize..0usize])
    // dist is symmetric, so row-major and column-major agree
    var i = 0usize
    while i < n * n {
        dist[i] = dist[i] * dist[i]
        i += 1usize
    }
    let nf = f64(n)
    let third = 1.0f64 / nf
    let rm = gg.zf(a, n)
    var j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            rm[i] += third * dist[i + j * n]
            i += 1usize
        }
        j += 1usize
    }
    var gm = 0.0f64
    i = 0usize
    while i < n {
        gm += rm[i]
        i += 1usize
    }
    gm = gm / nf
    i = 0usize
    while i < n * n {
        dist[i] = dist[i] + gm
        i += 1usize
    }
    j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            dist[i + j * n] = dist[i + j * n] - (rm[i] + rm[j])
            dist[i + j * n] = dist[i + j * n] * (0.0f64 - 0.5f64)
            i += 1usize
        }
        j += 1usize
    }
    let nn = i64(n)
    let il = nn - i64(dim) + 1i64
    let w = gg.zf(a, n)
    let z = gg.zf(a, n * dim)
    let (isuppz, e2) = mem.alloc[i64](a, 2usize * n)
    if e2 != ok { os.exit(9) }
    var m = 0i64
    var info = 0i64
    var wk: [1]f64 = zero
    var iwk: [1]i64 = zero
    lap.dsyevr("V", "I", "U", nn, dist[0usize..], nn, 0.0f64, 0.0f64, il, nn, 1e-14f64, &m, w[0usize..], z[0usize..], nn, isuppz[0usize..], wk[0usize..], 0i64 - 1i64, iwk[0usize..], 0i64 - 1i64, &info)
    let lwork = usize(i64(wk[0usize]))
    let liwork = usize(iwk[0usize])
    let (work, e3) = mem.alloc[f64](a, lwork)
    let (iwork, e4) = mem.alloc[i64](a, liwork)
    if e3 != ok || e4 != ok { os.exit(9) }
    lap.dsyevr("V", "I", "U", nn, dist[0usize..], nn, 0.0f64, 0.0f64, il, nn, 1e-14f64, &m, w[0usize..], z[0usize..], nn, isuppz[0usize..], work[0usize..], i64(lwork), iwork[0usize..], i64(liwork), &info)
    if info != 0i64 { os.exit(9) }
    j = 0usize
    while j < dim {
        w[j] = math.sqrt[f64](math.abs[f64](w[j]))
        j += 1usize
    }
    i = 0usize
    while i < n {
        var jj = 0usize
        var k = dim - 1usize
        while jj < dim {
            out[i * dim + k] = w[jj] * z[i + jj * n]
            jj += 1usize
            if k > 0usize { k -= 1usize }
        }
        i += 1usize
    }
    ret out[0usize..n * dim]
}
