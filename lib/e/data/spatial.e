// Spatial indexes over caller storage. `KdTree` orders point indices in
// place by alternating median splits (`kd_build`) and answers the nearest
// point with sphere pruning (`kd_nearest`); `QuadTree` and `OcTree`
// subdivide a square (cube) when a cell exceeds its capacity over a node
// pool (`quadtree_insert`, `quadtree_range`, `octree_insert`,
// `octree_range`); `interval_overlap` lists intervals meeting a query
// range through a centred interval tree built by `interval_build`;
// `HashGrid` buckets points into fixed cells for neighbour queries.
// Points are `d` coordinates each in a row-major array.

use e.math

error TooSmall
error Invalid

type KdTree = struct { points: []const f64, d: usize, order: []usize }
type QuadTree = struct { x0: f64, y0: f64, size: f64, capacity: usize, child: []u32, first: []u32, count: []u32, next: []u32, used: usize, items: usize, xs: []f64, ys: []f64 }
type OcTree = struct { x0: f64, y0: f64, z0: f64, size: f64, capacity: usize, child: []u32, first: []u32, count: []u32, next: []u32, used: usize, items: usize, xs: []f64, ys: []f64, zs: []f64 }
type IntervalTree = struct { starts: []const f64, ends: []const f64, order: []usize, left: []u32, right: []u32, centre: []f64, first: []u32, count: []u32, used: usize }
type Best = struct { node: usize, distance: f64 }
type HashGrid = struct { cell: f64, x0: f64, y0: f64, columns: usize, rows: usize, head: []u32, next: []u32, xs: []f64, ys: []f64, count: usize }

const NONE: u32 = 4294967295u32

fn coordinate(t: *const KdTree, i: usize, axis: usize) -> f64 { ret t.points[i * t.d + axis] }

fn build_range(t: *const KdTree, lo: usize, hi: usize, depth: usize) {
    if hi - lo < 2usize { ret }
    let axis = depth % t.d
    let mid = lo + (hi - lo) / 2usize
    // ponytail: insertion sort per range (O(n^2) build); quickselect if builds dominate.
    var i = lo + 1usize
    while i < hi {
        let v = t.order[i]
        var k = i
        while k > lo && coordinate(t, t.order[k - 1usize], axis) > coordinate(t, v, axis) {
            t.order[k] = t.order[k - 1usize]
            k -= 1usize
        }
        t.order[k] = v
        i += 1usize
    }
    build_range(t, lo, mid, depth + 1usize)
    build_range(t, mid + 1usize, hi, depth + 1usize)
}

// Arrange `order` (indices `0..n`) as an implicit k-d tree: the middle of
// every range is its node, split on `depth % d`.
fn kd_build(points: []const f64, n: usize, d: usize, order: []usize) -> (KdTree, err) {
    if points.len < n * d || order.len < n { ret (zero, TooSmall) }
    if d == 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    let t = KdTree { points: points, d: d, order: order[..n] }
    build_range(&t, 0usize, n, 0usize)
    ret (t, ok)
}

fn distance_squared(t: *const KdTree, i: usize, query: []const f64) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < t.d {
        let v = t.points[i * t.d + k] - query[k]
        s += v * v
        k += 1usize
    }
    ret s
}

// The running best rides in one record: a `*f64` parameter past the register
// arguments is misread by the Linux back end (see the task filed with D857).
fn nearest_range(t: *const KdTree, lo: usize, hi: usize, depth: usize, query: []const f64, best: *Best) {
    if hi <= lo { ret }
    let axis = depth % t.d
    let mid = lo + (hi - lo) / 2usize
    let node = t.order[mid]
    let dist = distance_squared(t, node, query)
    if dist < best.distance {
        best.distance = dist
        best.node = node
    }
    let gap = query[axis] - coordinate(t, node, axis)
    if gap < 0.0f64 {
        nearest_range(t, lo, mid, depth + 1usize, query, best)
        if gap * gap < best.distance { nearest_range(t, mid + 1usize, hi, depth + 1usize, query, best) }
    } else {
        nearest_range(t, mid + 1usize, hi, depth + 1usize, query, best)
        if gap * gap < best.distance { nearest_range(t, lo, mid, depth + 1usize, query, best) }
    }
}

// The nearest point to `query` and its squared distance.
fn kd_nearest(t: *const KdTree, query: []const f64) -> (usize, f64, err) {
    if query.len < t.d { ret (0usize, 0.0f64, TooSmall) }
    if t.order.len == 0usize { ret (0usize, 0.0f64, Invalid) }
    var best = Best { node: t.order[0usize], distance: 1.0e300f64 }
    nearest_range(t, 0usize, t.order.len, 0usize, query, &best)
    ret (best.node, best.distance, ok)
}

// A quadtree over the square at (x0, y0) of side `size`, with node pools
// (`child`: 4 per node, `first`/`count`: the node's item list) and item
// pools (`next`, `xs`, `ys`); a cell holding more than `capacity` items splits.
fn quadtree(x0: f64, y0: f64, size: f64, capacity: usize, child: []u32, first: []u32, count: []u32, next: []u32, xs: []f64, ys: []f64) -> (QuadTree, err) {
    if child.len < 4usize || first.len < 1usize || count.len < 1usize { ret (zero, TooSmall) }
    if size <= 0.0f64 || capacity == 0usize { ret (zero, Invalid) }
    child[0usize] = NONE
    first[0usize] = NONE
    count[0usize] = 0u32
    ret (QuadTree { x0: x0, y0: y0, size: size, capacity: capacity, child: child, first: first, count: count, next: next, used: 1usize, items: 0usize, xs: xs, ys: ys }, ok)
}

fn quadrant(x: f64, y: f64, cx: f64, cy: f64) -> usize {
    var q = 0usize
    if x >= cx { q += 1usize }
    if y >= cy { q += 2usize }
    ret q
}

// Insert point `(x, y)`; answers its item index.
fn quadtree_insert(t: *QuadTree, x: f64, y: f64) -> (usize, err) {
    if x < t.x0 || y < t.y0 || x > t.x0 + t.size || y > t.y0 + t.size { ret (0usize, Invalid) }
    if t.items >= t.next.len || t.items >= t.xs.len || t.items >= t.ys.len { ret (0usize, TooSmall) }
    let item = t.items
    t.items += 1usize
    t.xs[item] = x
    t.ys[item] = y
    var node = 0usize
    var nx = t.x0
    var ny = t.y0
    var size = t.size
    var depth = 0usize
    while t.child[node * 4usize] != NONE {
        let q = quadrant(x, y, nx + size / 2.0f64, ny + size / 2.0f64)
        node = usize(t.child[node * 4usize + q])
        if q % 2usize == 1usize { nx += size / 2.0f64 }
        if q >= 2usize { ny += size / 2.0f64 }
        size = size / 2.0f64
        depth += 1usize
    }
    t.next[item] = t.first[node]
    t.first[node] = u32(item)
    t.count[node] += 1u32
    // Split a full leaf (unless it is already tiny, where coincident points would recurse forever).
    if usize(t.count[node]) > t.capacity && depth < 24usize {
        if t.used + 4usize > t.first.len || t.used + 4usize > t.count.len || (t.used + 4usize) * 4usize > t.child.len { ret (item, TooSmall) }
        var q = 0usize
        while q < 4usize {
            let c = t.used + q
            t.child[node * 4usize + q] = u32(c)
            var k = 0usize
            while k < 4usize {
                t.child[c * 4usize + k] = NONE
                k += 1usize
            }
            t.first[c] = NONE
            t.count[c] = 0u32
            q += 1usize
        }
        t.used += 4usize
        var it = t.first[node]
        t.first[node] = NONE
        t.count[node] = 0u32
        while it != NONE {
            let after = t.next[usize(it)]
            let q2 = quadrant(t.xs[usize(it)], t.ys[usize(it)], nx + size / 2.0f64, ny + size / 2.0f64)
            let c = usize(t.child[node * 4usize + q2])
            t.next[usize(it)] = t.first[c]
            t.first[c] = it
            t.count[c] += 1u32
            it = after
        }
    }
    ret (item, ok)
}

// Every item inside the rectangle `[x1, x2] × [y1, y2]` into `out`; answers the count.
fn quadtree_range(t: *const QuadTree, x1: f64, y1: f64, x2: f64, y2: f64, out: []usize) -> (usize, err) {
    var found = 0usize
    let e = quadtree_range_node(t, 0usize, t.x0, t.y0, t.size, x1, y1, x2, y2, out, &found)
    ret (found, e)
}

fn quadtree_range_node(t: *const QuadTree, node: usize, nx: f64, ny: f64, size: f64, x1: f64, y1: f64, x2: f64, y2: f64, out: []usize, found: *usize) -> err {
    if nx > x2 || ny > y2 || nx + size < x1 || ny + size < y1 { ret ok }
    if t.child[node * 4usize] == NONE {
        var it = t.first[node]
        while it != NONE {
            let x = t.xs[usize(it)]
            let y = t.ys[usize(it)]
            if x >= x1 && x <= x2 && y >= y1 && y <= y2 {
                if *found >= out.len { ret TooSmall }
                out[*found] = usize(it)
                *found += 1usize
            }
            it = t.next[usize(it)]
        }
        ret ok
    }
    let half = size / 2.0f64
    var q = 0usize
    while q < 4usize {
        var cx = nx
        var cy = ny
        if q % 2usize == 1usize { cx += half }
        if q >= 2usize { cy += half }
        let e = quadtree_range_node(t, usize(t.child[node * 4usize + q]), cx, cy, half, x1, y1, x2, y2, out, found)
        if e != ok { ret e }
        q += 1usize
    }
    ret ok
}

// An octree over the cube at (x0, y0, z0) of side `size`; pools as the quadtree with 8 children per node.
fn octree(x0: f64, y0: f64, z0: f64, size: f64, capacity: usize, child: []u32, first: []u32, count: []u32, next: []u32, xs: []f64, ys: []f64, zs: []f64) -> (OcTree, err) {
    if child.len < 8usize || first.len < 1usize || count.len < 1usize { ret (zero, TooSmall) }
    if size <= 0.0f64 || capacity == 0usize { ret (zero, Invalid) }
    child[0usize] = NONE
    first[0usize] = NONE
    count[0usize] = 0u32
    ret (OcTree { x0: x0, y0: y0, z0: z0, size: size, capacity: capacity, child: child, first: first, count: count, next: next, used: 1usize, items: 0usize, xs: xs, ys: ys, zs: zs }, ok)
}

fn octant(x: f64, y: f64, z: f64, cx: f64, cy: f64, cz: f64) -> usize {
    var q = 0usize
    if x >= cx { q += 1usize }
    if y >= cy { q += 2usize }
    if z >= cz { q += 4usize }
    ret q
}

fn octree_insert(t: *OcTree, x: f64, y: f64, z: f64) -> (usize, err) {
    if x < t.x0 || y < t.y0 || z < t.z0 || x > t.x0 + t.size || y > t.y0 + t.size || z > t.z0 + t.size { ret (0usize, Invalid) }
    if t.items >= t.next.len || t.items >= t.xs.len || t.items >= t.ys.len || t.items >= t.zs.len { ret (0usize, TooSmall) }
    let item = t.items
    t.items += 1usize
    t.xs[item] = x
    t.ys[item] = y
    t.zs[item] = z
    var node = 0usize
    var nx = t.x0
    var ny = t.y0
    var nz = t.z0
    var size = t.size
    var depth = 0usize
    while t.child[node * 8usize] != NONE {
        let q = octant(x, y, z, nx + size / 2.0f64, ny + size / 2.0f64, nz + size / 2.0f64)
        node = usize(t.child[node * 8usize + q])
        if q % 2usize == 1usize { nx += size / 2.0f64 }
        if (q / 2usize) % 2usize == 1usize { ny += size / 2.0f64 }
        if q >= 4usize { nz += size / 2.0f64 }
        size = size / 2.0f64
        depth += 1usize
    }
    t.next[item] = t.first[node]
    t.first[node] = u32(item)
    t.count[node] += 1u32
    if usize(t.count[node]) > t.capacity && depth < 24usize {
        if t.used + 8usize > t.first.len || t.used + 8usize > t.count.len || (t.used + 8usize) * 8usize > t.child.len { ret (item, TooSmall) }
        var q = 0usize
        while q < 8usize {
            let c = t.used + q
            t.child[node * 8usize + q] = u32(c)
            var k = 0usize
            while k < 8usize {
                t.child[c * 8usize + k] = NONE
                k += 1usize
            }
            t.first[c] = NONE
            t.count[c] = 0u32
            q += 1usize
        }
        t.used += 8usize
        var it = t.first[node]
        t.first[node] = NONE
        t.count[node] = 0u32
        while it != NONE {
            let after = t.next[usize(it)]
            let q2 = octant(t.xs[usize(it)], t.ys[usize(it)], t.zs[usize(it)], nx + size / 2.0f64, ny + size / 2.0f64, nz + size / 2.0f64)
            let c = usize(t.child[node * 8usize + q2])
            t.next[usize(it)] = t.first[c]
            t.first[c] = it
            t.count[c] += 1u32
            it = after
        }
    }
    ret (item, ok)
}

// Every item inside the box into `out`; answers the count.
fn octree_range(t: *const OcTree, x1: f64, y1: f64, z1: f64, x2: f64, y2: f64, z2: f64, out: []usize) -> (usize, err) {
    var found = 0usize
    let e = octree_range_node(t, 0usize, t.x0, t.y0, t.z0, t.size, x1, y1, z1, x2, y2, z2, out, &found)
    ret (found, e)
}

fn octree_range_node(t: *const OcTree, node: usize, nx: f64, ny: f64, nz: f64, size: f64, x1: f64, y1: f64, z1: f64, x2: f64, y2: f64, z2: f64, out: []usize, found: *usize) -> err {
    if nx > x2 || ny > y2 || nz > z2 || nx + size < x1 || ny + size < y1 || nz + size < z1 { ret ok }
    if t.child[node * 8usize] == NONE {
        var it = t.first[node]
        while it != NONE {
            let i = usize(it)
            if t.xs[i] >= x1 && t.xs[i] <= x2 && t.ys[i] >= y1 && t.ys[i] <= y2 && t.zs[i] >= z1 && t.zs[i] <= z2 {
                if *found >= out.len { ret TooSmall }
                out[*found] = i
                *found += 1usize
            }
            it = t.next[i]
        }
        ret ok
    }
    let half = size / 2.0f64
    var q = 0usize
    while q < 8usize {
        var cx = nx
        var cy = ny
        var cz = nz
        if q % 2usize == 1usize { cx += half }
        if (q / 2usize) % 2usize == 1usize { cy += half }
        if q >= 4usize { cz += half }
        let e = octree_range_node(t, usize(t.child[node * 8usize + q]), cx, cy, cz, half, x1, y1, z1, x2, y2, z2, out, found)
        if e != ok { ret e }
        q += 1usize
    }
    ret ok
}

// A centred interval tree over `starts`/`ends` (`n` intervals): each node
// keeps the intervals crossing its centre (a list through `order`), the
// rest go left or right. Pools of `n` nodes: `left`, `right`, `centre`,
// `first`, `count`; `order.len >= n` holds the item chain.
fn interval_build(starts: []const f64, ends: []const f64, n: usize, order: []usize, left: []u32, right: []u32, centre: []f64, first: []u32, count: []u32) -> (IntervalTree, err) {
    if starts.len < n || ends.len < n || order.len < n || left.len < n + 1usize || right.len < n + 1usize || centre.len < n + 1usize || first.len < n + 1usize || count.len < n + 1usize { ret (zero, TooSmall) }
    var t = IntervalTree { starts: starts, ends: ends, order: order, left: left, right: right, centre: centre, first: first, count: count, used: 0usize }
    // Start with every interval in a chain, then partition recursively.
    var i = 0usize
    while i < n {
        order[i] = i + 2usize
        i += 1usize
    }
    if n > 0usize { order[n - 1usize] = 0usize }
    // Chains are 1-based through `order` (0 ends a chain); the head of the full chain is 1.
    var head = 0usize
    if n > 0usize { head = 1usize }
    let (_, e) = interval_node(&t, head)
    if e != ok { ret (zero, e) }
    ret (t, ok)
}

// Build the node for the chain at `head` (1-based item ids); answers the node index + 1 (0 for none).
fn interval_node(t: *IntervalTree, head: usize) -> (u32, err) {
    if head == 0usize { ret (0u32, ok) }
    // Centre: the median of the interval midpoints (approximated by the mean).
    var total = 0.0f64
    var n = 0usize
    var it = head
    while it != 0usize {
        total += 0.5f64 * (t.starts[it - 1usize] + t.ends[it - 1usize])
        n += 1usize
        it = t.order[it - 1usize]
    }
    let c = total / f64(n)
    if t.used >= t.centre.len { ret (0u32, TooSmall) }
    let node = t.used
    t.used += 1usize
    t.centre[node] = c
    t.first[node] = NONE
    t.count[node] = 0u32
    var left_head = 0usize
    var right_head = 0usize
    var here_head = 0usize
    it = head
    while it != 0usize {
        let after = t.order[it - 1usize]
        if t.ends[it - 1usize] < c {
            t.order[it - 1usize] = left_head
            left_head = it
        } else if t.starts[it - 1usize] > c {
            t.order[it - 1usize] = right_head
            right_head = it
        } else {
            t.order[it - 1usize] = here_head
            here_head = it
            t.count[node] += 1u32
        }
        it = after
    }
    if here_head != 0usize { t.first[node] = u32(here_head) }
    // Every interval crossing the centre is here; the sides recurse unless nothing moved
    // (all crossing), which ends the recursion.
    let (l, le) = interval_node(t, left_head)
    if le != ok { ret (0u32, le) }
    let (r, re) = interval_node(t, right_head)
    if re != ok { ret (0u32, re) }
    t.left[node] = l
    t.right[node] = r
    ret (u32(node + 1usize), ok)
}

// Every interval overlapping `[lo, hi]` into `out`; answers the count.
fn interval_overlap(t: *const IntervalTree, lo: f64, hi: f64, out: []usize) -> (usize, err) {
    var found = 0usize
    if t.used == 0usize { ret (0usize, ok) }
    let e = interval_overlap_node(t, 0usize, lo, hi, out, &found)
    ret (found, e)
}

fn interval_overlap_node(t: *const IntervalTree, node: usize, lo: f64, hi: f64, out: []usize, found: *usize) -> err {
    var it = t.first[node]
    while it != NONE {
        let i = usize(it) - 1usize
        if t.starts[i] <= hi && t.ends[i] >= lo {
            if *found >= out.len { ret TooSmall }
            out[*found] = i
            *found += 1usize
        }
        let after = t.order[i]
        if after == 0usize { it = NONE } else { it = u32(after) }
    }
    if lo < t.centre[node] && t.left[node] != 0u32 {
        let e = interval_overlap_node(t, usize(t.left[node]) - 1usize, lo, hi, out, found)
        if e != ok { ret e }
    }
    if hi > t.centre[node] && t.right[node] != 0u32 {
        let e = interval_overlap_node(t, usize(t.right[node]) - 1usize, lo, hi, out, found)
        if e != ok { ret e }
    }
    ret ok
}

// A grid of `columns × rows` cells of side `cell` from (x0, y0); `head.len >= columns * rows`.
fn hash_grid(x0: f64, y0: f64, cell: f64, columns: usize, rows: usize, head: []u32, next: []u32, xs: []f64, ys: []f64) -> (HashGrid, err) {
    if head.len < columns * rows { ret (zero, TooSmall) }
    if cell <= 0.0f64 || columns == 0usize || rows == 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i < columns * rows {
        head[i] = NONE
        i += 1usize
    }
    ret (HashGrid { cell: cell, x0: x0, y0: y0, columns: columns, rows: rows, head: head, next: next, xs: xs, ys: ys, count: 0usize }, ok)
}

fn cell_of(g: *const HashGrid, x: f64, y: f64) -> (usize, usize) {
    var cx = (x - g.x0) / g.cell
    var cy = (y - g.y0) / g.cell
    if cx < 0.0f64 { cx = 0.0f64 }
    if cy < 0.0f64 { cy = 0.0f64 }
    var col = usize(cx)
    var row = usize(cy)
    if col >= g.columns { col = g.columns - 1usize }
    if row >= g.rows { row = g.rows - 1usize }
    ret (col, row)
}

fn hash_grid_insert(g: *HashGrid, x: f64, y: f64) -> (usize, err) {
    if g.count >= g.next.len || g.count >= g.xs.len || g.count >= g.ys.len { ret (0usize, TooSmall) }
    let item = g.count
    g.count += 1usize
    g.xs[item] = x
    g.ys[item] = y
    let (col, row) = cell_of(g, x, y)
    let c = row * g.columns + col
    g.next[item] = g.head[c]
    g.head[c] = u32(item)
    ret (item, ok)
}

// Every item within `radius` of `(x, y)` (the cells around it scanned) into `out`.
fn hash_grid_near(g: *const HashGrid, x: f64, y: f64, radius: f64, out: []usize) -> (usize, err) {
    let (c1, r1) = cell_of(g, x - radius, y - radius)
    let (c2, r2) = cell_of(g, x + radius, y + radius)
    var found = 0usize
    var row = r1
    while row <= r2 {
        var col = c1
        while col <= c2 {
            var it = g.head[row * g.columns + col]
            while it != NONE {
                let i = usize(it)
                let dx = g.xs[i] - x
                let dy = g.ys[i] - y
                if dx * dx + dy * dy <= radius * radius {
                    if found >= out.len { ret (found, TooSmall) }
                    out[found] = i
                    found += 1usize
                }
                it = g.next[i]
            }
            col += 1usize
        }
        row += 1usize
    }
    ret (found, ok)
}

// An R-tree over caller rectangles (`items`: 4 numbers each, x1 y1 x2
// y2) with `fanout` entries per node: node pools `box` (4 per node),
// `child` (`fanout` per node: item indices in a leaf, node indices
// otherwise), `count` and `leaf`. A full node splits quadratically.
type RTree = struct { items: []const f64, fanout: usize, box: []f64, child: []u32, count: []u32, leaf: []u8, used: usize, root: usize }

fn rtree(items: []const f64, fanout: usize, box: []f64, child: []u32, count: []u32, leaf: []u8) -> (RTree, err) {
    if fanout < 2usize || fanout > 64usize { ret (zero, Invalid) }
    if box.len < 4usize || child.len < fanout || count.len < 1usize || leaf.len < 1usize { ret (zero, TooSmall) }
    count[0usize] = 0u32
    leaf[0usize] = 1u8
    ret (RTree { items: items, fanout: fanout, box: box, child: child, count: count, leaf: leaf, used: 1usize, root: 0usize }, ok)
}

fn rtree_new_node(t: *RTree, is_leaf: bool) -> (usize, err) {
    if (t.used + 1usize) * 4usize > t.box.len || (t.used + 1usize) * t.fanout > t.child.len || t.used >= t.count.len || t.used >= t.leaf.len { ret (0usize, TooSmall) }
    let n = t.used
    t.used += 1usize
    t.count[n] = 0u32
    t.leaf[n] = 0u8
    if is_leaf { t.leaf[n] = 1u8 }
    ret (n, ok)
}

// The box of entry `e` of `node` into `out[..4]`.
fn rtree_entry_box(t: *const RTree, node: usize, e: u32, out: []f64) {
    var k = 0usize
    if t.leaf[node] == 1u8 {
        while k < 4usize {
            out[k] = t.items[usize(e) * 4usize + k]
            k += 1usize
        }
    } else {
        while k < 4usize {
            out[k] = t.box[usize(e) * 4usize + k]
            k += 1usize
        }
    }
}

fn box_area(b: []const f64) -> f64 { ret (b[2usize] - b[0usize]) * (b[3usize] - b[1usize]) }

fn box_union(a: []const f64, b: []const f64, out: []f64) {
    out[0usize] = a[0usize]
    if b[0usize] < out[0usize] { out[0usize] = b[0usize] }
    out[1usize] = a[1usize]
    if b[1usize] < out[1usize] { out[1usize] = b[1usize] }
    out[2usize] = a[2usize]
    if b[2usize] > out[2usize] { out[2usize] = b[2usize] }
    out[3usize] = a[3usize]
    if b[3usize] > out[3usize] { out[3usize] = b[3usize] }
}

fn box_intersects(a: []const f64, b: []const f64) -> bool {
    ret a[0usize] <= b[2usize] && b[0usize] <= a[2usize] && a[1usize] <= b[3usize] && b[1usize] <= a[3usize]
}

// Recompute the box of `node` from its entries.
fn rtree_fit(t: *RTree, node: usize) {
    var b: [4]f64 = zero
    var u: [4]f64 = zero
    var e = 0usize
    while e < usize(t.count[node]) {
        rtree_entry_box(t, node, t.child[node * t.fanout + e], b[..])
        if e == 0usize {
            var k = 0usize
            while k < 4usize {
                u[k] = b[k]
                k += 1usize
            }
        } else {
            var merged: [4]f64 = zero
            box_union(u[..], b[..], merged[..])
            u = merged
        }
        e += 1usize
    }
    var k = 0usize
    while k < 4usize {
        t.box[node * 4usize + k] = u[k]
        k += 1usize
    }
}

// Split the full `node` plus `extra` into `node` and a new node (quadratic seeds, then least enlargement); answers the new node.
fn rtree_split(t: *RTree, node: usize, extra: u32) -> (usize, err) {
    var entries: [65]u32 = zero
    var boxes: [260]f64 = zero
    let total = usize(t.count[node]) + 1usize
    var e = 0usize
    while e < total - 1usize {
        entries[e] = t.child[node * t.fanout + e]
        e += 1usize
    }
    entries[total - 1usize] = extra
    e = 0usize
    while e < total {
        rtree_entry_box(t, node, entries[e], boxes[e * 4usize..e * 4usize + 4usize])
        e += 1usize
    }
    // Seeds: the pair wasting the most area together.
    var seed_a = 0usize
    var seed_b = 1usize
    var worst = 0.0f64 - 1.0f64
    var i = 0usize
    while i < total {
        var j = i + 1usize
        while j < total {
            var u: [4]f64 = zero
            box_union(boxes[i * 4usize..i * 4usize + 4usize], boxes[j * 4usize..j * 4usize + 4usize], u[..])
            let waste = box_area(u[..]) - box_area(boxes[i * 4usize..i * 4usize + 4usize]) - box_area(boxes[j * 4usize..j * 4usize + 4usize])
            if waste > worst {
                worst = waste
                seed_a = i
                seed_b = j
            }
            j += 1usize
        }
        i += 1usize
    }
    let (other, new_error) = rtree_new_node(t, t.leaf[node] == 1u8)
    if new_error != ok { ret (0usize, new_error) }
    var group: [65]u8 = zero
    var a_box: [4]f64 = zero
    var b_box: [4]f64 = zero
    var k = 0usize
    while k < 4usize {
        a_box[k] = boxes[seed_a * 4usize + k]
        b_box[k] = boxes[seed_b * 4usize + k]
        k += 1usize
    }
    group[seed_a] = 1u8
    group[seed_b] = 2u8
    var count_a = 1usize
    var count_b = 1usize
    let minimum = t.fanout / 2usize
    var placed = 2usize
    while placed < total {
        // The entry with the greatest preference, or every remainder to a group that needs them.
        var pick = total
        var pick_group = 0u8
        var best_gap = 0.0f64 - 1.0f64
        e = 0usize
        while e < total {
            if group[e] == 0u8 {
                let remaining = total - placed
                if count_a + remaining <= minimum {
                    pick = e
                    pick_group = 1u8
                } else if count_b + remaining <= minimum {
                    pick = e
                    pick_group = 2u8
                } else {
                    var ua: [4]f64 = zero
                    var ub: [4]f64 = zero
                    box_union(a_box[..], boxes[e * 4usize..e * 4usize + 4usize], ua[..])
                    box_union(b_box[..], boxes[e * 4usize..e * 4usize + 4usize], ub[..])
                    let grow_a = box_area(ua[..]) - box_area(a_box[..])
                    let grow_b = box_area(ub[..]) - box_area(b_box[..])
                    var gap = grow_a - grow_b
                    if gap < 0.0f64 { gap = 0.0f64 - gap }
                    if gap > best_gap {
                        best_gap = gap
                        pick = e
                        pick_group = 1u8
                        if grow_b < grow_a || (grow_b == grow_a && count_b < count_a) { pick_group = 2u8 }
                    }
                }
            }
            e += 1usize
        }
        group[pick] = pick_group
        var u: [4]f64 = zero
        if pick_group == 1u8 {
            box_union(a_box[..], boxes[pick * 4usize..pick * 4usize + 4usize], u[..])
            a_box = u
            count_a += 1usize
        } else {
            box_union(b_box[..], boxes[pick * 4usize..pick * 4usize + 4usize], u[..])
            b_box = u
            count_b += 1usize
        }
        placed += 1usize
    }
    t.count[node] = 0u32
    e = 0usize
    while e < total {
        if group[e] == 1u8 {
            t.child[node * t.fanout + usize(t.count[node])] = entries[e]
            t.count[node] += 1u32
        } else {
            t.child[other * t.fanout + usize(t.count[other])] = entries[e]
            t.count[other] += 1u32
        }
        e += 1usize
    }
    rtree_fit(t, node)
    rtree_fit(t, other)
    ret (other, ok)
}

// Insert item `item` (its rectangle in `items`).
fn rtree_insert(t: *RTree, item: usize) -> err {
    if (item + 1usize) * 4usize > t.items.len { ret Invalid }
    var path: [64]usize = zero
    var depth = 0usize
    var node = t.root
    let b = t.items[item * 4usize..item * 4usize + 4usize]
    while t.leaf[node] == 0u8 {
        if depth >= 64usize { ret TooSmall }
        path[depth] = node
        depth += 1usize
        // The child whose box grows least.
        var pick = 0usize
        var best_grow = 1.0e300f64
        var best_area = 1.0e300f64
        var e = 0usize
        while e < usize(t.count[node]) {
            let c = usize(t.child[node * t.fanout + e])
            let cb = t.box[c * 4usize..c * 4usize + 4usize]
            var u: [4]f64 = zero
            box_union(cb, b, u[..])
            let grow = box_area(u[..]) - box_area(cb)
            if grow < best_grow || (grow == best_grow && box_area(cb) < best_area) {
                best_grow = grow
                best_area = box_area(cb)
                pick = c
            }
            e += 1usize
        }
        node = pick
    }
    var extra = u32(item)
    var pending = true
    while pending {
        if usize(t.count[node]) < t.fanout {
            t.child[node * t.fanout + usize(t.count[node])] = extra
            t.count[node] += 1u32
            rtree_fit(t, node)
            pending = false
        } else {
            let (other, split_error) = rtree_split(t, node, extra)
            if split_error != ok { ret split_error }
            if depth == 0usize {
                // The root split: a new root over both halves.
                let (r, root_error) = rtree_new_node(t, false)
                if root_error != ok { ret root_error }
                t.child[r * t.fanout] = u32(node)
                t.child[r * t.fanout + 1usize] = u32(other)
                t.count[r] = 2u32
                rtree_fit(t, r)
                t.root = r
                pending = false
            } else {
                depth -= 1usize
                node = path[depth]
                extra = u32(other)
            }
        }
    }
    // Ancestors grow to cover the new box.
    while depth > 0usize {
        depth -= 1usize
        rtree_fit(t, path[depth])
    }
    ret ok
}

// Every item whose rectangle meets the query rectangle into `out`; answers the count.
fn rtree_search(t: *const RTree, x1: f64, y1: f64, x2: f64, y2: f64, out: []usize) -> (usize, err) {
    var query: [4]f64 = zero
    query[0usize] = x1
    query[1usize] = y1
    query[2usize] = x2
    query[3usize] = y2
    var found = 0usize
    let e = rtree_search_node(t, t.root, query[..], out, &found)
    ret (found, e)
}

fn rtree_search_node(t: *const RTree, node: usize, query: []const f64, out: []usize, found: *usize) -> err {
    var e = 0usize
    while e < usize(t.count[node]) {
        let c = t.child[node * t.fanout + e]
        var b: [4]f64 = zero
        rtree_entry_box(t, node, c, b[..])
        if box_intersects(b[..], query) {
            if t.leaf[node] == 1u8 {
                if *found >= out.len { ret TooSmall }
                out[*found] = usize(c)
                *found += 1usize
            } else {
                let child_error = rtree_search_node(t, usize(c), query, out, found)
                if child_error != ok { ret child_error }
            }
        }
        e += 1usize
    }
    ret ok
}

// The Hilbert index of cell `(x, y)` on a `2^order` grid.
fn hilbert_index(order: u32, x: u64, y: u64) -> u64 {
    var d = 0u64
    var px = x
    var py = y
    let full = 1u64 << order
    var s = full / 2u64
    while s > 0u64 {
        var rx = 0u64
        if (px & s) > 0u64 { rx = 1u64 }
        var ry = 0u64
        if (py & s) > 0u64 { ry = 1u64 }
        d += s * s * ((3u64 * rx) ^ ry)
        if ry == 0u64 {
            if rx == 1u64 {
                px = full - 1u64 - px
                py = full - 1u64 - py
            }
            let tmp = px
            px = py
            py = tmp
        }
        s = s >> 1u32
    }
    ret d
}

fn sift_keys(keys: []u64, order: []usize, start: usize, end: usize) {
    var root = start
    while root * 2usize + 1usize < end {
        var child = root * 2usize + 1usize
        if child + 1usize < end && keys[child + 1usize] > keys[child] { child += 1usize }
        if keys[root] >= keys[child] { ret }
        let k = keys[root]
        keys[root] = keys[child]
        keys[child] = k
        let o = order[root]
        order[root] = order[child]
        order[child] = o
        root = child
    }
}

// Heap sort `order[..n]` by `keys[..n]` (the keys move with them).
fn sort_by_key(keys: []u64, order: []usize, n: usize) {
    if n < 2usize { ret }
    var start = n / 2usize
    while start > 0usize {
        start -= 1usize
        sift_keys(keys, order, start, n)
    }
    var end = n
    while end > 1usize {
        end -= 1usize
        let k = keys[0usize]
        keys[0usize] = keys[end]
        keys[end] = k
        let o = order[0usize]
        order[0usize] = order[end]
        order[end] = o
        sift_keys(keys, order, 0usize, end)
    }
}

// Bulk-load an R-tree over `items[..n]` packed along the Hilbert curve of
// the rectangle centres; `keys` and `order` are scratch of `n`.
fn rtree_hilbert(items: []const f64, n: usize, fanout: usize, box: []f64, child: []u32, count: []u32, leaf: []u8, keys: []u64, order: []usize) -> (RTree, err) {
    if keys.len < n || order.len < n || items.len < n * 4usize { ret (zero, TooSmall) }
    let (t0, make_error) = rtree(items, fanout, box, child, count, leaf)
    if make_error != ok { ret (zero, make_error) }
    var t = t0
    if n == 0usize { ret (t, ok) }
    // Centres scaled to a 2^16 grid over the overall bounds.
    var lo_x = items[0usize]
    var lo_y = items[1usize]
    var hi_x = items[2usize]
    var hi_y = items[3usize]
    var i = 1usize
    while i < n {
        if items[i * 4usize] < lo_x { lo_x = items[i * 4usize] }
        if items[i * 4usize + 1usize] < lo_y { lo_y = items[i * 4usize + 1usize] }
        if items[i * 4usize + 2usize] > hi_x { hi_x = items[i * 4usize + 2usize] }
        if items[i * 4usize + 3usize] > hi_y { hi_y = items[i * 4usize + 3usize] }
        i += 1usize
    }
    var span_x = hi_x - lo_x
    var span_y = hi_y - lo_y
    if span_x <= 0.0f64 { span_x = 1.0f64 }
    if span_y <= 0.0f64 { span_y = 1.0f64 }
    i = 0usize
    while i < n {
        let cx = 0.5f64 * (items[i * 4usize] + items[i * 4usize + 2usize])
        let cy = 0.5f64 * (items[i * 4usize + 1usize] + items[i * 4usize + 3usize])
        var gx = u64((cx - lo_x) / span_x * 65535.0f64)
        var gy = u64((cy - lo_y) / span_y * 65535.0f64)
        if gx > 65535u64 { gx = 65535u64 }
        if gy > 65535u64 { gy = 65535u64 }
        keys[i] = hilbert_index(16u32, gx, gy)
        order[i] = i
        i += 1usize
    }
    sort_by_key(keys, order, n)
    // Leaves in Hilbert order; the root leaf holds the first group.
    var level_first = 0usize
    var level_count = 0usize
    i = 0usize
    while i < n {
        var node = 0usize
        if i > 0usize {
            let (fresh, new_error) = rtree_new_node(&t, true)
            if new_error != ok { ret (zero, new_error) }
            node = fresh
        }
        var e = 0usize
        while e < fanout && i < n {
            t.child[node * fanout + e] = u32(order[i])
            e += 1usize
            i += 1usize
        }
        t.count[node] = u32(e)
        rtree_fit(&t, node)
        level_count += 1usize
    }
    // Pack each level into parents until one node remains (levels are contiguous in the pool).
    while level_count > 1usize {
        let next_first = t.used
        var c = 0usize
        while c < level_count {
            let (parent, new_error) = rtree_new_node(&t, false)
            if new_error != ok { ret (zero, new_error) }
            var e = 0usize
            while e < fanout && c < level_count {
                t.child[parent * fanout + e] = u32(level_first + c)
                e += 1usize
                c += 1usize
            }
            t.count[parent] = u32(e)
            rtree_fit(&t, parent)
        }
        level_count = t.used - next_first
        level_first = next_first
    }
    t.root = level_first
    ret (t, ok)
}

// A bounding volume hierarchy over primitive boxes (`boxes`: 6 numbers
// each, x1 y1 z1 x2 y2 z2) split at the median centroid of the widest
// axis; `order` receives the primitive permutation, node pools of `2n`:
// `box` (6 per node), `left`, `right` (`NONE` at a leaf), `first`, `count`.
type Bvh = struct { boxes: []const f64, order: []usize, box: []f64, left: []u32, right: []u32, first: []u32, count: []u32, used: usize }

fn bvh_centroid(b: *const Bvh, p: usize, axis: usize) -> f64 { ret 0.5f64 * (b.boxes[p * 6usize + axis] + b.boxes[p * 6usize + 3usize + axis]) }

fn bvh_node(b: *Bvh, lo: usize, hi: usize, leaf_size: usize) -> (u32, err) {
    if b.used >= b.left.len || b.used >= b.right.len || b.used >= b.first.len || b.used >= b.count.len || (b.used + 1usize) * 6usize > b.box.len { ret (0u32, TooSmall) }
    let node = b.used
    b.used += 1usize
    var k = 0usize
    while k < 6usize {
        b.box[node * 6usize + k] = b.boxes[b.order[lo] * 6usize + k]
        k += 1usize
    }
    var i = lo + 1usize
    while i < hi {
        k = 0usize
        while k < 3usize {
            if b.boxes[b.order[i] * 6usize + k] < b.box[node * 6usize + k] { b.box[node * 6usize + k] = b.boxes[b.order[i] * 6usize + k] }
            if b.boxes[b.order[i] * 6usize + 3usize + k] > b.box[node * 6usize + 3usize + k] { b.box[node * 6usize + 3usize + k] = b.boxes[b.order[i] * 6usize + 3usize + k] }
            k += 1usize
        }
        i += 1usize
    }
    b.first[node] = u32(lo)
    b.count[node] = u32(hi - lo)
    b.left[node] = NONE
    b.right[node] = NONE
    if hi - lo <= leaf_size { ret (u32(node), ok) }
    // Split on the axis where the centroids spread most.
    var axis = 0usize
    var best_spread = 0.0f64 - 1.0f64
    k = 0usize
    while k < 3usize {
        var lo_c = bvh_centroid(b, b.order[lo], k)
        var hi_c = lo_c
        i = lo + 1usize
        while i < hi {
            let c = bvh_centroid(b, b.order[i], k)
            if c < lo_c { lo_c = c }
            if c > hi_c { hi_c = c }
            i += 1usize
        }
        if hi_c - lo_c > best_spread {
            best_spread = hi_c - lo_c
            axis = k
        }
        k += 1usize
    }
    // ponytail: insertion sort of the range by centroid; a median select if builds dominate.
    i = lo + 1usize
    while i < hi {
        let v = b.order[i]
        var j = i
        while j > lo && bvh_centroid(b, b.order[j - 1usize], axis) > bvh_centroid(b, v, axis) {
            b.order[j] = b.order[j - 1usize]
            j -= 1usize
        }
        b.order[j] = v
        i += 1usize
    }
    let mid = lo + (hi - lo) / 2usize
    let (l, l_error) = bvh_node(b, lo, mid, leaf_size)
    if l_error != ok { ret (0u32, l_error) }
    let (r, r_error) = bvh_node(b, mid, hi, leaf_size)
    if r_error != ok { ret (0u32, r_error) }
    b.left[node] = l
    b.right[node] = r
    ret (u32(node), ok)
}

fn bvh_build(boxes: []const f64, n: usize, leaf_size: usize, order: []usize, box: []f64, left: []u32, right: []u32, first: []u32, count: []u32) -> (Bvh, err) {
    if boxes.len < n * 6usize || order.len < n { ret (zero, TooSmall) }
    if n == 0usize || leaf_size == 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    var b = Bvh { boxes: boxes, order: order[..n], box: box, left: left, right: right, first: first, count: count, used: 0usize }
    let (_, e) = bvh_node(&b, 0usize, n, leaf_size)
    if e != ok { ret (zero, e) }
    ret (b, ok)
}

// Does the ray from `origin` along `direction` meet the box (slab test)?
fn ray_hits_box(box: []const f64, origin: []const f64, direction: []const f64) -> bool {
    var t_near = 0.0f64 - 1.0e300f64
    var t_far = 1.0e300f64
    var k = 0usize
    while k < 3usize {
        if direction[k] == 0.0f64 {
            if origin[k] < box[k] || origin[k] > box[3usize + k] { ret false }
        } else {
            var t1 = (box[k] - origin[k]) / direction[k]
            var t2 = (box[3usize + k] - origin[k]) / direction[k]
            if t1 > t2 {
                let tmp = t1
                t1 = t2
                t2 = tmp
            }
            if t1 > t_near { t_near = t1 }
            if t2 < t_far { t_far = t2 }
            if t_near > t_far || t_far < 0.0f64 { ret false }
        }
        k += 1usize
    }
    ret true
}

// Every primitive whose box the ray meets into `out`; answers the count.
fn bvh_traverse(b: *const Bvh, origin: []const f64, direction: []const f64, out: []usize) -> (usize, err) {
    if origin.len < 3usize || direction.len < 3usize { ret (0usize, TooSmall) }
    var stack: [128]u32 = zero
    stack[0usize] = 0u32
    var top = 1usize
    var found = 0usize
    while top > 0usize {
        top -= 1usize
        let node = usize(stack[top])
        if ray_hits_box(b.box[node * 6usize..node * 6usize + 6usize], origin, direction) {
            if b.left[node] == NONE {
                var i = 0usize
                while i < usize(b.count[node]) {
                    let p = b.order[usize(b.first[node]) + i]
                    if ray_hits_box(b.boxes[p * 6usize..p * 6usize + 6usize], origin, direction) {
                        if found >= out.len { ret (found, TooSmall) }
                        out[found] = p
                        found += 1usize
                    }
                    i += 1usize
                }
            } else {
                if top + 2usize > 128usize { ret (found, TooSmall) }
                stack[top] = b.left[node]
                stack[top + 1usize] = b.right[node]
                top += 2usize
            }
        }
    }
    ret (found, ok)
}

// A 2-d range tree: `order` holds the points sorted by x, and level `L`
// of `pool` (`n` entries per level, `levels >= ceil(log2 n) + 1`) holds
// the range of every node at that level sorted by y. Queries take O(log^2 n + k).
type RangeTree = struct { xs: []const f64, ys: []const f64, n: usize, order: []usize, pool: []usize, levels: usize }

fn range_tree_fill(t: *RangeTree, level: usize, lo: usize, hi: usize) -> err {
    if hi - lo == 0usize { ret ok }
    if level >= t.levels { ret TooSmall }
    let base = level * t.n
    if hi - lo == 1usize {
        t.pool[base + lo] = t.order[lo]
        ret ok
    }
    let mid = lo + (hi - lo) / 2usize
    let e1 = range_tree_fill(t, level + 1usize, lo, mid)
    if e1 != ok { ret e1 }
    let e2 = range_tree_fill(t, level + 1usize, mid, hi)
    if e2 != ok { ret e2 }
    // Merge the y-sorted lists of the children.
    let below = (level + 1usize) * t.n
    var i = lo
    var j = mid
    var k = lo
    while k < hi {
        if j >= hi || (i < mid && t.ys[t.pool[below + i]] <= t.ys[t.pool[below + j]]) {
            t.pool[base + k] = t.pool[below + i]
            i += 1usize
        } else {
            t.pool[base + k] = t.pool[below + j]
            j += 1usize
        }
        k += 1usize
    }
    ret ok
}

fn range_tree_build(xs: []const f64, ys: []const f64, n: usize, order: []usize, pool: []usize) -> (RangeTree, err) {
    if xs.len < n || ys.len < n || order.len < n { ret (zero, TooSmall) }
    var levels = 1usize
    var span = 1usize
    while span < n {
        span *= 2usize
        levels += 1usize
    }
    if pool.len < levels * n { ret (zero, TooSmall) }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    // ponytail: insertion sort by x; O(n^2) build ceiling.
    i = 1usize
    while i < n {
        let v = order[i]
        var j = i
        while j > 0usize && xs[order[j - 1usize]] > xs[v] {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = v
        i += 1usize
    }
    var t = RangeTree { xs: xs, ys: ys, n: n, order: order[..n], pool: pool, levels: levels }
    let e = range_tree_fill(&t, 0usize, 0usize, n)
    if e != ok { ret (zero, e) }
    ret (t, ok)
}

fn range_tree_query_node(t: *const RangeTree, level: usize, lo: usize, hi: usize, x1: f64, x2: f64, y1: f64, y2: f64, out: []usize, found: *usize) -> err {
    if hi <= lo { ret ok }
    let first_x = t.xs[t.order[lo]]
    let last_x = t.xs[t.order[hi - 1usize]]
    if last_x < x1 || first_x > x2 { ret ok }
    if first_x >= x1 && last_x <= x2 {
        // A canonical node: binary search its y-list for the first y >= y1.
        let base = level * t.n
        var a = lo
        var b = hi
        while a < b {
            let m = a + (b - a) / 2usize
            if t.ys[t.pool[base + m]] < y1 { a = m + 1usize } else { b = m }
        }
        while a < hi && t.ys[t.pool[base + a]] <= y2 {
            if *found >= out.len { ret TooSmall }
            out[*found] = t.pool[base + a]
            *found += 1usize
            a += 1usize
        }
        ret ok
    }
    if hi - lo == 1usize { ret ok }
    let mid = lo + (hi - lo) / 2usize
    let e1 = range_tree_query_node(t, level + 1usize, lo, mid, x1, x2, y1, y2, out, found)
    if e1 != ok { ret e1 }
    ret range_tree_query_node(t, level + 1usize, mid, hi, x1, x2, y1, y2, out, found)
}

// Every point in `[x1, x2] × [y1, y2]` into `out`; answers the count.
// ponytail: no fractional cascading (O(log^2 n)); add cascading pointers if queries dominate.
fn range_tree_query(t: *const RangeTree, x1: f64, y1: f64, x2: f64, y2: f64, out: []usize) -> (usize, err) {
    var found = 0usize
    let e = range_tree_query_node(t, 0usize, 0usize, t.n, x1, x2, y1, y2, out, &found)
    ret (found, e)
}

// A ball tree: the k-d order (`kd_build`) with a centroid (`centre`,
// `d` per point position) and radius per implicit node, so `ball_tree_nearest`
// prunes by the triangle inequality.
type BallTree = struct { tree: KdTree, centre: []f64, radius: []f64 }

fn ball_fill(b: *BallTree, lo: usize, hi: usize) {
    if hi <= lo { ret }
    let d = b.tree.d
    let mid = lo + (hi - lo) / 2usize
    var k = 0usize
    while k < d {
        var s = 0.0f64
        var i = lo
        while i < hi {
            s += coordinate(&b.tree, b.tree.order[i], k)
            i += 1usize
        }
        b.centre[mid * d + k] = s / f64(hi - lo)
        k += 1usize
    }
    var r = 0.0f64
    var i = lo
    while i < hi {
        let dist = distance_squared(&b.tree, b.tree.order[i], b.centre[mid * d..mid * d + d])
        if dist > r { r = dist }
        i += 1usize
    }
    b.radius[mid] = math.sqrt[f64](r)
    ball_fill(b, lo, mid)
    ball_fill(b, mid + 1usize, hi)
}

fn ball_tree_build(points: []const f64, n: usize, d: usize, order: []usize, centre: []f64, radius: []f64) -> (BallTree, err) {
    if centre.len < n * d || radius.len < n { ret (zero, TooSmall) }
    let (tree, e) = kd_build(points, n, d, order)
    if e != ok { ret (zero, e) }
    var b = BallTree { tree: tree, centre: centre, radius: radius }
    ball_fill(&b, 0usize, n)
    ret (b, ok)
}

fn ball_nearest_range(b: *const BallTree, lo: usize, hi: usize, query: []const f64, best: *Best) {
    if hi <= lo { ret }
    let mid = lo + (hi - lo) / 2usize
    let d = b.tree.d
    var to_centre = 0.0f64
    var k = 0usize
    while k < d {
        let v = b.centre[mid * d + k] - query[k]
        to_centre += v * v
        k += 1usize
    }
    let bound = math.sqrt[f64](to_centre) - b.radius[mid]
    if bound > 0.0f64 && bound * bound >= best.distance { ret }
    let node = b.tree.order[mid]
    let dist = distance_squared(&b.tree, node, query)
    if dist < best.distance {
        best.distance = dist
        best.node = node
    }
    ball_nearest_range(b, lo, mid, query, best)
    ball_nearest_range(b, mid + 1usize, hi, query, best)
}

// The nearest point to `query` and its squared distance.
fn ball_tree_nearest(b: *const BallTree, query: []const f64) -> (usize, f64, err) {
    if query.len < b.tree.d { ret (0usize, 0.0f64, TooSmall) }
    if b.tree.order.len == 0usize { ret (0usize, 0.0f64, Invalid) }
    var best = Best { node: b.tree.order[0usize], distance: 1.0e300f64 }
    ball_nearest_range(b, 0usize, b.tree.order.len, query, &best)
    ret (best.node, best.distance, ok)
}
