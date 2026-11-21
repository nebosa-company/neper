// R igraph layout_with_mds on a disconnected graph, ported from igraph 2.3.4 (layout/mds.c, merge_dla.c, merge_grid.c, core/indheap.c):
// each weak component is laid out by e.algo.graph.layout_force.mds in the order igraph_subcomponent visits it, then the layouts are
// merged by diffusion-limited aggregation over R's random streams (largest component at the origin, the others by random walks onto a
// 200 x 200 grid). A connected graph goes straight to layout_force.mds. Two dimensions only, as igraph's merge is.
//
// Rows are (x, y), n rows. An edge list is flat pairs.

use e.algo.graph.games as gg
use e.algo.graph.layout_force as lf
use e.algo.rand.r as rg
use e.math
use e.mem

const STEPS: usize = 200usize

type Grid = struct { minx: f64, maxx: f64, dx: f64, miny: f64, maxy: f64, dy: f64, data: []i64 }

fn cell_of(g: *Grid, xc: f64, yc: f64) -> (usize, usize) {
    var x = 0usize
    var y = 0usize
    if xc <= g.minx {
        x = 0usize
    } else if xc >= g.maxx {
        x = STEPS - 1usize
    } else {
        x = usize(math.floor[f64]((xc - g.minx) / g.dx))
    }
    if yc <= g.miny {
        y = 0usize
    } else if yc >= g.maxy {
        y = STEPS - 1usize
    } else {
        y = usize(math.floor[f64]((yc - g.miny) / g.dy))
    }
    ret (x, y)
}

fn dist2(x: f64, y: f64, gx: f64, gy: f64) -> f64 {
    let ux = x - gx
    let uy = y - gy
    ret math.sqrt[f64](ux * ux + uy * uy)
}

fn mat(g: *Grid, i: i64, j: i64) -> i64 { ret g.data[usize(i64(STEPS) * j + i)] }

fn set_mat(g: *Grid, i: i64, j: i64, v: i64) { g.data[usize(i64(STEPS) * j + i)] = v }

fn place_sphere(g: *Grid, x: f64, y: f64, r: f64, id: i64) {
    let (ucx, ucy) = cell_of(g, x, y)
    let cx = i64(ucx)
    let cy = i64(ucy)
    let st = i64(STEPS)
    set_mat(g, cx, cy, id + 1i64)
    var i = 0i64
    while cx + i < st && dist2(x, y, g.minx + f64(cx + i) * g.dx, g.miny + f64(cy) * g.dy) < r {
        var j = 0i64
        while cy + j < st && dist2(x, y, g.minx + f64(cx + i) * g.dx, g.miny + f64(cy + j) * g.dy) < r {
            set_mat(g, cx + i, cy + j, id + 1i64)
            j += 1i64
        }
        i += 1i64
    }
    i = 0i64
    while cx + i < st && dist2(x, y, g.minx + f64(cx + i) * g.dx, g.miny + f64(cy + 1i64) * g.dy) < r {
        var j = 1i64
        while cy - j > 0i64 && dist2(x, y, g.minx + f64(cx + i) * g.dx, g.miny + f64(cy - j + 1i64) * g.dy) < r {
            set_mat(g, cx + i, cy - j, id + 1i64)
            j += 1i64
        }
        i += 1i64
    }
    i = 1i64
    while cx - i > 0i64 && dist2(x, y, g.minx + f64(cx - i + 1i64) * g.dx, g.miny + f64(cy) * g.dy) < r {
        var j = 0i64
        while cy + j < st && dist2(x, y, g.minx + f64(cx - i + 1i64) * g.dx, g.miny + f64(cy + j) * g.dy) < r {
            set_mat(g, cx - i, cy + j, id + 1i64)
            j += 1i64
        }
        i += 1i64
    }
    i = 1i64
    while cx - i > 0i64 && dist2(x, y, g.minx + f64(cx - i + 1i64) * g.dx, g.miny + f64(cy + 1i64) * g.dy) < r {
        var j = 1i64
        while cy - j > 0i64 && dist2(x, y, g.minx + f64(cx - i + 1i64) * g.dx, g.miny + f64(cy - j + 1i64) * g.dy) < r {
            set_mat(g, cx - i, cy - j, id + 1i64)
            j += 1i64
        }
        i += 1i64
    }
}

// the id of a placed sphere touching a sphere of radius r at (x, y), or -1
fn get_sphere(g: *Grid, x: f64, y: f64, r: f64) -> i64 {
    if x - r <= g.minx || x + r >= g.maxx || y - r <= g.miny || y + r >= g.maxy { ret 0i64 - 1i64 }
    let (ucx, ucy) = cell_of(g, x, y)
    let cx = i64(ucx)
    let cy = i64(ucy)
    let st = i64(STEPS)
    var ret_id = mat(g, cx, cy) - 1i64
    var i = 0i64
    while ret_id < 0i64 && cx + i < st && dist2(x, y, g.minx + f64(cx + i) * g.dx, g.miny + f64(cy) * g.dy) < r {
        var j = 0i64
        while ret_id < 0i64 && cy + j < st && dist2(x, y, g.minx + f64(cx + i) * g.dx, g.miny + f64(cy + j) * g.dy) < r {
            ret_id = mat(g, cx + i, cy + j) - 1i64
            j += 1i64
        }
        i += 1i64
    }
    i = 0i64
    while ret_id < 0i64 && cx + i < st && dist2(x, y, g.minx + f64(cx + i) * g.dx, g.miny + f64(cy + 1i64) * g.dy) < r {
        var j = 1i64
        while ret_id < 0i64 && cy - j > 0i64 && dist2(x, y, g.minx + f64(cx + i) * g.dx, g.miny + f64(cy - j + 1i64) * g.dy) < r {
            ret_id = mat(g, cx + i, cy - j) - 1i64
            j += 1i64
        }
        i += 1i64
    }
    i = 1i64
    while ret_id < 0i64 && cx - i > 0i64 && dist2(x, y, g.minx + f64(cx - i + 1i64) * g.dx, g.miny + f64(cy) * g.dy) < r {
        var j = 0i64
        while ret_id < 0i64 && cy + j < st && dist2(x, y, g.minx + f64(cx - i + 1i64) * g.dx, g.miny + f64(cy + j) * g.dy) < r {
            ret_id = mat(g, cx - i, cy + j) - 1i64
            j += 1i64
        }
        i += 1i64
    }
    // igraph tests `cx + i > 0` and `cy + i > 0` in this last pass, and reads outside the grid if it gets there; here that reads nothing
    i = 1i64
    while ret_id < 0i64 && cx + i > 0i64 && dist2(x, y, g.minx + f64(cx - i + 1i64) * g.dx, g.miny + f64(cy + 1i64) * g.dy) < r {
        var j = 1i64
        while ret_id < 0i64 && cy + i > 0i64 && dist2(x, y, g.minx + f64(cx - i + 1i64) * g.dx, g.miny + f64(cy - j + 1i64) * g.dy) < r {
            if cx - i >= 0i64 && cy - j >= 0i64 { ret_id = mat(g, cx - i, cy - j) - 1i64 }
            j += 1i64
        }
        i += 1i64
    }
    ret ret_id
}

// igraph's max-heap of (value, index + 1), used by igraph_vector_order2: indices, largest value first, ties as the heap leaves them
fn heap_switch(v: []f64, ix: []i64, e1: usize, e2: usize) {
    if e1 != e2 {
        let t = v[e1]
        v[e1] = v[e2]
        v[e2] = t
        let u = ix[e1]
        ix[e1] = ix[e2]
        ix[e2] = u
    }
}

fn heap_sink(v: []f64, ix: []i64, size: usize, head: usize) {
    let l = (head + 1usize) * 2usize - 1usize
    let rt = (head + 1usize) * 2usize
    if l >= size {
        ret
    }
    if rt == size || v[l] >= v[rt] {
        if v[head] < v[l] {
            heap_switch(v, ix, head, l)
            heap_sink(v, ix, size, l)
        }
    } else {
        if v[head] < v[rt] {
            heap_switch(v, ix, head, rt)
            heap_sink(v, ix, size, rt)
        }
    }
}

fn heap_build(v: []f64, ix: []i64, size: usize, head: usize) {
    let l = (head + 1usize) * 2usize - 1usize
    let rt = (head + 1usize) * 2usize
    if rt < size {
        heap_build(v, ix, size, l)
        heap_build(v, ix, size, rt)
        heap_sink(v, ix, size, head)
    } else if l < size {
        heap_build(v, ix, size, l)
        heap_sink(v, ix, size, head)
    }
}

fn order_desc(a: *mem.Arena, vals: []const f64) -> []usize {
    let n = vals.len
    let v = gg.zf(a, n)
    let ix = gg.zi(a, n)
    var i = 0usize
    while i < n {
        v[i] = vals[i]
        ix[i] = i64(i + 1usize)
        i += 1usize
    }
    heap_build(v, ix, n, 0usize)
    let out = gg.alloc_u(a, n)
    var size = n
    i = 0usize
    while i < n {
        out[i] = usize(ix[0usize] - 1i64)
        heap_switch(v, ix, 0usize, size - 1usize)
        size -= 1usize
        heap_sink(v, ix, size, 0usize)
        i += 1usize
    }
    ret out[0usize..n]
}

// igraph_layout_merge_dla: coords holds the layouts back to back (rows of 2), counts the rows of each
fn merge_dla(a: *mem.Arena, r: *rg.Rng, coords: []const f64, counts: []const usize) -> []f64 {
    let m = counts.len
    let sizes = gg.zf(a, m)
    let x = gg.zf(a, m)
    let y = gg.zf(a, m)
    let rad = gg.zf(a, m)
    let nx = gg.zf(a, m)
    let ny = gg.zf(a, m)
    let nr = gg.zf(a, m)
    var allnodes = 0usize
    var area = 0.0f64
    let off = gg.alloc_u(a, m + 1usize)
    var i = 0usize
    while i < m {
        let size = counts[i]
        off[i] = allnodes
        allnodes += size
        sizes[i] = f64(size)
        rad[i] = math.pow[f64](f64(size), 0.75f64)
        area += rad[i] * rad[i]
        var xmin = coords[2usize * off[i]]
        var xmax = xmin
        var ymin = coords[2usize * off[i] + 1usize]
        var ymax = ymin
        var k = 1usize
        while k < size {
            let px = coords[2usize * (off[i] + k)]
            let py = coords[2usize * (off[i] + k) + 1usize]
            if px < xmin { xmin = px } else if px > xmax { xmax = px }
            if py < ymin { ymin = py } else if py > ymax { ymax = py }
            k += 1usize
        }
        nx[i] = (xmin + xmax) / 2.0f64
        ny[i] = (ymin + ymax) / 2.0f64
        nr[i] = math.sqrt[f64]((xmax - xmin) * (xmax - xmin) + (ymax - ymin) * (ymax - ymin)) / 2.0f64
        i += 1usize
    }
    let order = order_desc(a, sizes[0usize..m])
    let lim = math.sqrt[f64](5.0f64 * area)
    let maxx = lim
    var g = Grid { minx: 0.0f64 - lim, maxx: lim, dx: (lim - (0.0f64 - lim)) / f64(STEPS), miny: 0.0f64 - lim, maxy: lim, dy: (lim - (0.0f64 - lim)) / f64(STEPS), data: gg.zi(a, STEPS * STEPS) }
    var jpos = 0usize
    let first = order[jpos]
    jpos += 1usize
    place_sphere(&g, 0.0f64, 0.0f64, rad[first], i64(first))
    let twopi = 2.0f64 * 3.141592653589793f64
    while jpos < m {
        let actg = order[jpos]
        jpos += 1usize
        let startr = maxx
        let killr = maxx + 5.0f64
        let rr = rad[actg]
        var sp = 0i64 - 1i64
        var px = 0.0f64
        var py = 0.0f64
        while sp < 0i64 {
            var more = true
            while more {
                let angle = gg.gunif(r, 0.0f64, twopi)
                let len = gg.gunif(r, 0.5f64 * startr, startr)
                px = len * math.cos[f64](angle)
                py = len * math.sin[f64](angle)
                sp = get_sphere(&g, px, py, rr)
                more = sp >= 0i64
            }
            while sp < 0i64 && math.sqrt[f64](px * px + py * py) < killr {
                let angle = gg.gunif(r, 0.0f64, twopi)
                let len = gg.gunif(r, 0.0f64, startr / 100.0f64)
                let qx = px + len * math.cos[f64](angle)
                let qy = py + len * math.sin[f64](angle)
                sp = get_sphere(&g, qx, qy, rr)
                if sp < 0i64 {
                    px = qx
                    py = qy
                }
            }
        }
        x[actg] = px
        y[actg] = py
        place_sphere(&g, px, py, rr, i64(actg))
    }
    let res = gg.zf(a, 2usize * allnodes)
    i = 0usize
    while i < m {
        var rr = rad[i] / nr[i]
        if nr[i] == 0.0f64 { rr = 1.0f64 }
        var k = 0usize
        while k < counts[i] {
            let row = off[i] + k
            res[2usize * row] = rr * (coords[2usize * row] - nx[i])
            res[2usize * row + 1usize] = rr * (coords[2usize * row + 1usize] - ny[i])
            res[2usize * row] += x[i]
            res[2usize * row + 1usize] += y[i]
            k += 1usize
        }
        i += 1usize
    }
    ret res[0usize..2usize * allnodes]
}

// layout_with_mds(dim = 2), a connected or disconnected graph
fn mds2(a: *mem.Arena, r: *rg.Rng, n: usize, ed: []const i64) -> []f64 {
    // adjacency lists, neighbours ascending
    let adj = gg.zb(a, n * n)
    var k = 0usize
    while k + 1usize < ed.len {
        let u = usize(ed[k])
        let v = usize(ed[k + 1usize])
        adj[u * n + v] = true
        adj[v * n + u] = true
        k += 2usize
    }
    let comp = gg.alloc_u(a, n)
    let seen = gg.zb(a, n)
    let vorder = gg.alloc_u(a, n)
    let layouts = gg.zf(a, 2usize * n)
    let counts = gg.alloc_u(a, n)
    let lidx = gg.alloc_u(a, n)
    let cid = gg.zi(a, n)
    var nc = 0usize
    var done = 0usize
    var s = 0usize
    while s < n {
        if !seen[s] {
            // igraph_subcomponent: breadth first from s, neighbours in id order
            var head = 0usize
            var tail = 1usize
            comp[0usize] = s
            seen[s] = true
            while head < tail {
                let v = comp[head]
                head += 1usize
                var w = 0usize
                while w < n {
                    if adj[v * n + w] && !seen[w] {
                        seen[w] = true
                        comp[tail] = w
                        tail += 1usize
                    }
                    w += 1usize
                }
            }
            var q = 0usize
            while q < tail {
                lidx[comp[q]] = q
                cid[comp[q]] = i64(nc + 1usize)
                vorder[comp[q]] = done + q
                q += 1usize
            }
            var sube = gg.new_el(a)
            // edges of the induced subgraph: a component holds both ends of each of its edges
            var e = 0usize
            while e + 1usize < ed.len {
                let u = usize(ed[e])
                let v = usize(ed[e + 1usize])
                if cid[u] == i64(nc + 1usize) { gg.push(a, &sube, i64(lidx[u]), i64(lidx[v])) }
                e += 2usize
            }
            let lay = lf.mds(a, tail, sube.b[0usize..2usize * gg.count(&sube)], 2usize)
            q = 0usize
            while q < 2usize * tail {
                layouts[2usize * done + q] = lay[q]
                q += 1usize
            }
            counts[nc] = tail
            nc += 1usize
            done += tail
        }
        s += 1usize
    }
    if nc == 1usize { ret layouts[0usize..2usize * n] }
    let merged = merge_dla(a, r, layouts[0usize..2usize * n], counts[0usize..nc])
    let res = gg.zf(a, 2usize * n)
    var v = 0usize
    while v < n {
        res[2usize * v] = merged[2usize * vorder[v]]
        res[2usize * v + 1usize] = merged[2usize * vorder[v] + 1usize]
        v += 1usize
    }
    ret res[0usize..2usize * n]
}
