// Navigation over walkable grids: a rectangle navmesh with portals, the simple stupid
// funnel, flow fields and hierarchical A*.
//
// A grid is `[]const u8` of `w * h` cells, row-major, zero meaning blocked. Everything is
// integer except the funnel, which pulls a string through portal points the caller gives
// in world units; nothing allocates, every buffer is the caller's, as in the rest of
// `e.game`.
//
// `build_navmesh` is a simplified Recast: greedy maximal rectangles taken row-major
// (widen along the row, then deepen while the whole width stays free), each a convex
// region, and a portal for every pair of rectangles that share an edge of positive
// length. `funnel` is Mononen's simple stupid funnel over a corridor of (left, right)
// portal endpoints in a y-up frame -- with y down (screen), hand the sides swapped -- and
// answers the pulled corners, start and goal included, without repeats. `flow_field` is
// Dijkstra from the goal over per-cell entry costs (zero blocked), then a direction per
// cell to its cheapest neighbour: 1 east, 2 south, 3 west, 4 north, 0 for the goal and the
// unreachable. `build_hpa` cuts the grid into `c`-sized clusters, places an entrance
// node pair at the middle of every free run along a cluster boundary (and at both ends of
// a run of 3 or more), and connects the
// nodes of a cluster by breadth-first search (unit costs, so BFS is A* with a zero
// heuristic); `hierarchical_astar` inserts start and goal as temporary nodes, runs
// Dijkstra on the abstract graph and refines every abstract edge back to cells.

use e.mem

type Rect = struct { x: u32, y: u32, w: u32, h: u32 }
type Portal = struct { a: u32, b: u32, x0: u32, y0: u32, x1: u32, y1: u32 }
type Pt = struct { x: f64, y: f64 }
type Hpa = struct { walk: []const u8, w: usize, h: usize, c: usize, node_cell: []u32, node_of: []u32, node_count: usize, edge_from: []u32, edge_to: []u32, edge_cost: []u32, edge_count: usize, dist: []u32, came: []u32, queue: []u32, adist: []u32, acame: []u32, heap: []u64 }

error TooSmall
error Invalid
error Unreachable

const NONE: u32 = 4294967295u32

fn min_u32(a: u32, b: u32) -> u32 {
    if a < b { ret a }
    ret b
}

fn max_u32(a: u32, b: u32) -> u32 {
    if a > b { ret a }
    ret b
}

// The neighbour of `cell` in direction `d` (0 east, 1 south, 2 west, 3 north), if inside.
fn neighbour(w: usize, h: usize, cell: usize, d: usize) -> (usize, bool) {
    let x = cell % w
    let y = cell / w
    if d == 0usize {
        if x + 1usize >= w { ret (0usize, false) }
        ret (cell + 1usize, true)
    }
    if d == 1usize {
        if y + 1usize >= h { ret (0usize, false) }
        ret (cell + w, true)
    }
    if d == 2usize {
        if x == 0usize { ret (0usize, false) }
        ret (cell - 1usize, true)
    }
    if y == 0usize { ret (0usize, false) }
    ret (cell - w, true)
}

// --- navmesh -----------------------------------------------------------------------------

fn portal_between(ia: u32, ra: Rect, ib: u32, rb: Rect) -> (Portal, bool) {
    var none: Portal = zero
    if ra.x + ra.w == rb.x || rb.x + rb.w == ra.x {
        let lo = max_u32(ra.y, rb.y)
        let hi = min_u32(ra.y + ra.h, rb.y + rb.h)
        if lo < hi {
            var ex = ra.x
            if ra.x + ra.w == rb.x { ex = rb.x }
            ret (Portal { a: ia, b: ib, x0: ex, y0: lo, x1: ex, y1: hi }, true)
        }
    }
    if ra.y + ra.h == rb.y || rb.y + rb.h == ra.y {
        let lo = max_u32(ra.x, rb.x)
        let hi = min_u32(ra.x + ra.w, rb.x + rb.w)
        if lo < hi {
            var ey = ra.y
            if ra.y + ra.h == rb.y { ey = rb.y }
            ret (Portal { a: ia, b: ib, x0: lo, y0: ey, x1: hi, y1: ey }, true)
        }
    }
    ret (none, false)
}

// Answers (region count, portal count). `region_of` is one `u32` per cell, `NONE` for a
// blocked cell. A portal's segment is in corner coordinates on the shared edge.
fn build_navmesh(walk: []const u8, w: usize, h: usize, regions: []Rect, portals: []Portal, region_of: []u32) -> (usize, usize, err) {
    let cells = w * h
    if walk.len < cells || region_of.len < cells { ret (0usize, 0usize, TooSmall) }
    var i = 0usize
    while i < cells {
        region_of[i] = NONE
        i += 1usize
    }
    var count = 0usize
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let start = y * w + x
            if walk[start] == 0u8 || region_of[start] != NONE {
                x += 1usize
                continue
            }
            var width = 1usize
            while x + width < w && walk[start + width] != 0u8 && region_of[start + width] == NONE { width += 1usize }
            var height = 1usize
            while y + height < h {
                let row = (y + height) * w + x
                var free = true
                var k = 0usize
                while k < width {
                    if walk[row + k] == 0u8 || region_of[row + k] != NONE {
                        free = false
                        break
                    }
                    k += 1usize
                }
                if !free { break }
                height += 1usize
            }
            if count == regions.len { ret (0usize, 0usize, TooSmall) }
            regions[count] = Rect { x: u32(x), y: u32(y), w: u32(width), h: u32(height) }
            var yy = y
            while yy < y + height {
                var xx = x
                while xx < x + width {
                    region_of[yy * w + xx] = u32(count)
                    xx += 1usize
                }
                yy += 1usize
            }
            count += 1usize
            x += width
        }
        y += 1usize
    }
    // ponytail: every pair is tested, O(regions^2); a sweep over shared edges if maps get big.
    var portal_count = 0usize
    var a = 0usize
    while a < count {
        var b = a + 1usize
        while b < count {
            let (p, touching) = portal_between(u32(a), regions[a], u32(b), regions[b])
            if touching {
                if portal_count == portals.len { ret (0usize, 0usize, TooSmall) }
                portals[portal_count] = p
                portal_count += 1usize
            }
            b += 1usize
        }
        a += 1usize
    }
    ret (count, portal_count, ok)
}

// --- funnel ------------------------------------------------------------------------------

fn tri_area2(a: Pt, b: Pt, c: Pt) -> f64 {
    ret (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y)
}

fn same(a: Pt, b: Pt) -> bool {
    ret a.x == b.x && a.y == b.y
}

// Portal `i` of the corridor: 0 is the start, `left.len + 1` the goal, both degenerate.
fn portal_at(start: Pt, goal: Pt, left: []const Pt, right: []const Pt, i: usize) -> (Pt, Pt) {
    if i == 0usize { ret (start, start) }
    if i > left.len { ret (goal, goal) }
    ret (left[i - 1usize], right[i - 1usize])
}

fn push_corner(out: []Pt, count: *usize, p: Pt) -> err {
    if *count > 0usize && same(out[*count - 1usize], p) { ret ok }
    if *count == out.len { ret TooSmall }
    out[*count] = p
    *count = *count + 1usize
    ret ok
}

// The pulled string from `start` to `goal` through the portals, as corner points.
fn funnel(start: Pt, goal: Pt, left: []const Pt, right: []const Pt, out: []Pt) -> (usize, err) {
    if left.len != right.len { ret (0usize, Invalid) }
    let n = left.len + 2usize
    var count = 0usize
    let e0 = push_corner(out, &count, start)
    if e0 != ok { ret (0usize, e0) }
    var apex = start
    var pl = start
    var pr = start
    var apex_i = 0usize
    var left_i = 0usize
    var right_i = 0usize
    var i = 1usize
    while i < n {
        let (l, r) = portal_at(start, goal, left, right, i)
        if tri_area2(apex, pr, r) <= 0.0f64 {
            if same(apex, pr) || tri_area2(apex, pl, r) > 0.0f64 {
                pr = r
                right_i = i
            } else {
                let e1 = push_corner(out, &count, pl)
                if e1 != ok { ret (0usize, e1) }
                apex = pl
                apex_i = left_i
                pr = apex
                right_i = apex_i
                i = apex_i + 1usize
                continue
            }
        }
        if tri_area2(apex, pl, l) >= 0.0f64 {
            if same(apex, pl) || tri_area2(apex, pr, l) < 0.0f64 {
                pl = l
                left_i = i
            } else {
                let e2 = push_corner(out, &count, pr)
                if e2 != ok { ret (0usize, e2) }
                apex = pr
                apex_i = right_i
                pl = apex
                left_i = apex_i
                i = apex_i + 1usize
                continue
            }
        }
        i += 1usize
    }
    let e3 = push_corner(out, &count, goal)
    if e3 != ok { ret (0usize, e3) }
    ret (count, ok)
}

// --- a binary heap of (key << 32 | cell) over caller storage --------------------------------

fn heap_push(heap: []u64, count: *usize, v: u64) -> err {
    if *count == heap.len { ret TooSmall }
    var i = *count
    heap[i] = v
    *count = i + 1usize
    while i > 0usize {
        let parent = (i - 1usize) / 2usize
        if heap[parent] <= heap[i] { break }
        let held = heap[parent]
        heap[parent] = heap[i]
        heap[i] = held
        i = parent
    }
    ret ok
}

fn heap_pop(heap: []u64, count: *usize) -> u64 {
    let top = heap[0usize]
    *count = *count - 1usize
    heap[0usize] = heap[*count]
    var i = 0usize
    while true {
        let l = i * 2usize + 1usize
        let r = l + 1usize
        var smallest = i
        if l < *count && heap[l] < heap[smallest] { smallest = l }
        if r < *count && heap[r] < heap[smallest] { smallest = r }
        if smallest == i { break }
        let held = heap[smallest]
        heap[smallest] = heap[i]
        heap[i] = held
        i = smallest
    }
    ret top
}

// --- flow field -----------------------------------------------------------------------------

// `cost` is the price of entering a cell, zero for blocked. `dist` gets the integrated
// cost to the goal (`NONE` when unreachable) and `dir` the step to take. `heap` needs room
// for one entry per relaxation: `4 * w * h` is always enough.
fn flow_field(cost: []const u8, w: usize, h: usize, goal: usize, dist: []u32, dir: []u8, heap: []u64) -> err {
    let cells = w * h
    if cost.len < cells || dist.len < cells || dir.len < cells { ret TooSmall }
    if goal >= cells || cost[goal] == 0u8 { ret Invalid }
    var i = 0usize
    while i < cells {
        dist[i] = NONE
        dir[i] = 0u8
        i += 1usize
    }
    dist[goal] = 0u32
    var count = 0usize
    try heap_push(heap, &count, u64(goal))
    while count > 0usize {
        let item = heap_pop(heap, &count)
        let d = u32(item >> 32u32)
        let cell = usize(item & 4294967295u64)
        if d > dist[cell] { continue }
        var k = 0usize
        while k < 4usize {
            let (n, inside) = neighbour(w, h, cell, k)
            k += 1usize
            if !inside || cost[n] == 0u8 { continue }
            let nd = d + u32(cost[n])
            if nd < dist[n] {
                dist[n] = nd
                try heap_push(heap, &count, (u64(nd) << 32u32) | u64(n))
            }
        }
    }
    i = 0usize
    while i < cells {
        if dist[i] != NONE && i != goal {
            var best = dist[i]
            var k = 0usize
            while k < 4usize {
                let (n, inside) = neighbour(w, h, i, k)
                if inside && dist[n] < best {
                    best = dist[n]
                    dir[i] = u8(k + 1usize)
                }
                k += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}

// --- HPA* ------------------------------------------------------------------------------------

fn cluster_of(g: *Hpa, cell: usize) -> usize {
    ret (cell / g.w / g.c) * ((g.w + g.c - 1usize) / g.c) + (cell % g.w) / g.c
}

fn add_edge(g: *Hpa, from: u32, to: u32, cost: u32) -> err {
    if g.edge_count == g.edge_from.len || g.edge_count == g.edge_to.len || g.edge_count == g.edge_cost.len { ret TooSmall }
    g.edge_from[g.edge_count] = from
    g.edge_to[g.edge_count] = to
    g.edge_cost[g.edge_count] = cost
    g.edge_count = g.edge_count + 1usize
    ret ok
}

fn node_at(g: *Hpa, cell: usize) -> (u32, err) {
    if g.node_of[cell] != NONE { ret (g.node_of[cell], ok) }
    if g.node_count + 2usize > g.node_cell.len { ret (0u32, TooSmall) }
    let id = u32(g.node_count)
    g.node_cell[g.node_count] = u32(cell)
    g.node_of[cell] = id
    g.node_count = g.node_count + 1usize
    ret (id, ok)
}

fn entrance(g: *Hpa, ca: usize, cb: usize) -> err {
    let (na, ea) = node_at(g, ca)
    if ea != ok { ret ea }
    let (nb, eb) = node_at(g, cb)
    if eb != ok { ret eb }
    try add_edge(g, na, nb, 1u32)
    try add_edge(g, nb, na, 1u32)
    ret ok
}

// A free run `first..=last` along the boundary at `edge` (a column when `vertical`): an
// entrance at its middle, plus one at each end when the run is 3 or longer. The paper
// keeps only the ends of a long run; on small maps that detour costs a few percent.
fn place(g: *Hpa, first: usize, last: usize, edge: usize, vertical: bool) -> err {
    var k = 0usize
    while k < 3usize {
        var along = (first + last) / 2usize
        if last + 1usize - first >= 3usize {
            if k == 1usize { along = first }
            if k == 2usize { along = last }
        } else {
            if k == 1usize { break }
        }
        if vertical {
            try entrance(g, along * g.w + edge - 1usize, along * g.w + edge)
        } else {
            try entrance(g, (edge - 1usize) * g.w + along, edge * g.w + along)
        }
        k += 1usize
    }
    ret ok
}

// Breadth-first from `source`, confined to its cluster; `dist` and `came` are valid for
// that cluster's cells afterwards.
fn bfs_cluster(g: *Hpa, source: usize) {
    let cx0 = ((source % g.w) / g.c) * g.c
    let cy0 = ((source / g.w) / g.c) * g.c
    var yy = cy0
    while yy < cy0 + g.c && yy < g.h {
        var xx = cx0
        while xx < cx0 + g.c && xx < g.w {
            g.dist[yy * g.w + xx] = NONE
            xx += 1usize
        }
        yy += 1usize
    }
    let home = cluster_of(g, source)
    g.dist[source] = 0u32
    g.came[source] = NONE
    g.queue[0usize] = u32(source)
    var head = 0usize
    var tail = 1usize
    while head < tail {
        let cell = usize(g.queue[head])
        head += 1usize
        var k = 0usize
        while k < 4usize {
            let (n, inside) = neighbour(g.w, g.h, cell, k)
            k += 1usize
            if !inside || g.walk[n] == 0u8 || cluster_of(g, n) != home { continue }
            if g.dist[n] != NONE { continue }
            g.dist[n] = g.dist[cell] + 1u32
            g.came[n] = u32(cell)
            g.queue[tail] = u32(n)
            tail += 1usize
        }
    }
}

// Every node of `source`'s cluster reached from it becomes an edge; `reverse` points the
// edge at `node` rather than from it.
fn connect(g: *Hpa, node: u32, source: usize, reverse: bool) -> err {
    bfs_cluster(g, source)
    let home = cluster_of(g, source)
    var m = 0usize
    while m < g.node_count {
        let cell = usize(g.node_cell[m])
        if u32(m) != node && cluster_of(g, cell) == home && g.dist[cell] != NONE {
            if reverse {
                try add_edge(g, u32(m), node, g.dist[cell])
            } else {
                try add_edge(g, node, u32(m), g.dist[cell])
            }
        }
        m += 1usize
    }
    ret ok
}

// Entrances along the boundaries between clusters, then intra-cluster edges. Sizes:
// `node_of`, `dist`, `came`, `queue` one per cell; `node_cell`, `adist`, `acame` one per
// node plus two; the edge arrays per edge plus one per node plus one; `heap` per edge.
fn build_hpa(g: *Hpa) -> err {
    let cells = g.w * g.h
    if g.c == 0usize { ret Invalid }
    if g.walk.len < cells || g.node_of.len < cells || g.dist.len < cells || g.came.len < cells || g.queue.len < cells { ret TooSmall }
    var i = 0usize
    while i < cells {
        g.node_of[i] = NONE
        i += 1usize
    }
    g.node_count = 0usize
    g.edge_count = 0usize
    var bx = g.c
    while bx < g.w {
        var y = 0usize
        while y < g.h {
            var stop = y + g.c
            if stop > g.h { stop = g.h }
            var run = NONE
            var yy = y
            while yy < stop {
                let open = g.walk[yy * g.w + bx - 1usize] != 0u8 && g.walk[yy * g.w + bx] != 0u8
                if open && run == NONE { run = u32(yy) }
                if run != NONE && (!open || yy + 1usize == stop) {
                    var last = yy
                    if !open { last = yy - 1usize }
                    try place(g, usize(run), last, bx, true)
                    run = NONE
                }
                yy += 1usize
            }
            y = stop
        }
        bx += g.c
    }
    var by = g.c
    while by < g.h {
        var x = 0usize
        while x < g.w {
            var stop = x + g.c
            if stop > g.w { stop = g.w }
            var run = NONE
            var xx = x
            while xx < stop {
                let open = g.walk[(by - 1usize) * g.w + xx] != 0u8 && g.walk[by * g.w + xx] != 0u8
                if open && run == NONE { run = u32(xx) }
                if run != NONE && (!open || xx + 1usize == stop) {
                    var last = xx
                    if !open { last = xx - 1usize }
                    try place(g, usize(run), last, by, false)
                    run = NONE
                }
                xx += 1usize
            }
            x = stop
        }
        by += g.c
    }
    var n = 0usize
    while n < g.node_count {
        try connect(g, u32(n), usize(g.node_cell[n]), false)
        n += 1usize
    }
    ret ok
}

// Dijkstra over the abstract graph from `s`, `total` nodes, into `adist`/`acame`.
fn abstract_search(g: *Hpa, s: u32, total: usize) -> err {
    if g.adist.len < total || g.acame.len < total { ret TooSmall }
    var i = 0usize
    while i < total {
        g.adist[i] = NONE
        g.acame[i] = NONE
        i += 1usize
    }
    g.adist[usize(s)] = 0u32
    var count = 0usize
    try heap_push(g.heap, &count, u64(s))
    // ponytail: every pop scans every edge, O(nodes * edges); an adjacency index if graphs grow.
    while count > 0usize {
        let item = heap_pop(g.heap, &count)
        let d = u32(item >> 32u32)
        let node = usize(item & 4294967295u64)
        if d > g.adist[node] { continue }
        var e = 0usize
        while e < g.edge_count {
            if usize(g.edge_from[e]) == node {
                let to = usize(g.edge_to[e])
                let nd = d + g.edge_cost[e]
                if nd < g.adist[to] {
                    g.adist[to] = nd
                    g.acame[to] = u32(node)
                    try heap_push(g.heap, &count, (u64(nd) << 32u32) | u64(to))
                }
            }
            e += 1usize
        }
    }
    ret ok
}

fn adjacent(w: usize, a: usize, b: usize) -> bool {
    if a / w == b / w { ret a + 1usize == b || b + 1usize == a }
    ret a + w == b || b + w == a
}

fn push_cell(out: []u32, count: *usize, cell: u32) -> err {
    if *count == out.len { ret TooSmall }
    out[*count] = cell
    *count = *count + 1usize
    ret ok
}

// The path from `start` to `goal` as cell indices, both included, and its cost. The
// answer is a real path whose cost is that of the abstract one, near-optimal rather than
// optimal; with `c` at least the map's size it is exact.
fn hierarchical_astar(g: *Hpa, start: usize, goal: usize, out: []u32) -> (u32, usize, err) {
    let cells = g.w * g.h
    if start >= cells || goal >= cells { ret (0u32, 0usize, Invalid) }
    if g.walk[start] == 0u8 || g.walk[goal] == 0u8 { ret (0u32, 0usize, Unreachable) }
    if start == goal {
        if out.len == 0usize { ret (0u32, 0usize, TooSmall) }
        out[0usize] = u32(start)
        ret (0u32, 1usize, ok)
    }
    let base_edges = g.edge_count
    let s = u32(g.node_count)
    let t = s + 1u32
    if usize(t) >= g.node_cell.len { ret (0u32, 0usize, TooSmall) }
    g.node_cell[usize(s)] = u32(start)
    g.node_cell[usize(t)] = u32(goal)
    let (cost, length, e) = query(g, s, t, start, goal, out)
    g.edge_count = base_edges
    ret (cost, length, e)
}

fn query(g: *Hpa, s: u32, t: u32, start: usize, goal: usize, out: []u32) -> (u32, usize, err) {
    let e0 = connect(g, s, start, false)
    if e0 != ok { ret (0u32, 0usize, e0) }
    if cluster_of(g, start) == cluster_of(g, goal) && g.dist[goal] != NONE {
        let e1 = add_edge(g, s, t, g.dist[goal])
        if e1 != ok { ret (0u32, 0usize, e1) }
    }
    let e2 = connect(g, t, goal, true)
    if e2 != ok { ret (0u32, 0usize, e2) }
    let e3 = abstract_search(g, s, usize(t) + 1usize)
    if e3 != ok { ret (0u32, 0usize, e3) }
    let total = g.adist[usize(t)]
    if total == NONE { ret (0u32, 0usize, Unreachable) }
    // Refine backwards, goal first, then reverse.
    var count = 0usize
    let e4 = push_cell(out, &count, u32(goal))
    if e4 != ok { ret (0u32, 0usize, e4) }
    var cur = t
    while cur != s {
        let prev = g.acame[usize(cur)]
        let from = usize(g.node_cell[usize(prev)])
        let to = usize(g.node_cell[usize(cur)])
        if adjacent(g.w, from, to) {
            let e5 = push_cell(out, &count, u32(from))
            if e5 != ok { ret (0u32, 0usize, e5) }
        } else {
            bfs_cluster(g, from)
            var walk = g.came[to]
            while walk != NONE {
                let e6 = push_cell(out, &count, walk)
                if e6 != ok { ret (0u32, 0usize, e6) }
                walk = g.came[usize(walk)]
            }
        }
        cur = prev
    }
    var lo = 0usize
    var hi = count - 1usize
    while lo < hi {
        let held = out[lo]
        out[lo] = out[hi]
        out[hi] = held
        lo += 1usize
        hi -= 1usize
    }
    ret (total, count, ok)
}
