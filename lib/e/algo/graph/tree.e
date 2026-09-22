// Rooted trees over `e.data.graph`'s undirected adjacency: depths, parents and
// subtree sizes from a root; lowest common ancestors by binary lifting and by
// Tarjan's offline union-find; the Euler tour with entry and exit times;
// heavy-light decomposition into paths; centroid decomposition; Prüfer codes;
// AHU canonical forms for rooted-tree isomorphism, LCA by Euler-tour RMQ and
// tree isomorphism rooted and unrooted. Every table is the caller's arena's,
// indexed by node.

use e.mem
use e.data.graph as graph
use e.algo.graph as algo
use e.algo.disjoint_set as dsu

type Rooted = struct { parent: []graph.NodeId, depth: []u32, size: []u32, order: []graph.NodeId }
type Lifting = struct { up: []graph.NodeId, depth: []const u32, levels: usize, count: usize }
type EulerTour = struct { entry: []u32, exit: []u32, sequence: []graph.NodeId }
type HeavyLight = struct { head: []graph.NodeId, position: []u32, parent: []graph.NodeId, depth: []const u32 }
error InvalidNode
error NotATree
error TooSmall

// Parents, depths, subtree sizes and a preorder from `root`; `NotATree` when a
// node is reached twice or some node never.
fn root_at[E: type](a: *mem.Arena, g: *const graph.Graph[E], root: graph.NodeId) -> (Rooted, err) {
    let n = graph.node_count[E](g)
    if usize(root) >= n { ret (zero, InvalidNode) }
    let (parent, parent_error) = mem.alloc[graph.NodeId](a, n)
    if parent_error != ok { ret (zero, parent_error) }
    let (depth, depth_error) = mem.alloc[u32](a, n)
    if depth_error != ok { ret (zero, depth_error) }
    let (size, size_error) = mem.alloc[u32](a, n)
    if size_error != ok { ret (zero, size_error) }
    let (order, order_error) = mem.alloc[graph.NodeId](a, n)
    if order_error != ok { ret (zero, order_error) }
    var i = 0usize
    while i < n {
        parent[i] = graph.NONE
        size[i] = 1u32
        i += 1usize
    }
    // BFS order doubles as the queue.
    parent[usize(root)] = root
    depth[usize(root)] = 0u32
    order[0usize] = root
    var head = 0usize
    var tail = 1usize
    while head < tail {
        let u = order[head]
        head += 1usize
        var k = g.offsets[usize(u)]
        while k < g.offsets[usize(u) + 1usize] {
            let v = g.edges[k].to
            if v != parent[usize(u)] || u == root {
                if v == u { ret (zero, NotATree) }
                if parent[usize(v)] != graph.NONE {
                    if !(u == root && v == root) { ret (zero, NotATree) }
                } else {
                    parent[usize(v)] = u
                    depth[usize(v)] = depth[usize(u)] + 1u32
                    order[tail] = v
                    tail += 1usize
                }
            }
            k += 1usize
        }
    }
    if tail != n { ret (zero, NotATree) }
    // Sizes accumulate from the leaves up the BFS order.
    i = n
    while i > 1usize {
        i -= 1usize
        let v = order[i]
        size[usize(parent[usize(v)])] += size[usize(v)]
    }
    ret (Rooted { parent: parent, depth: depth, size: size, order: order }, ok)
}

// The binary-lifting table: `up[level * count + v]` is the 2^level-th ancestor.
fn lifting(a: *mem.Arena, tree: *const Rooted) -> (Lifting, err) {
    let n = tree.parent.len
    var levels = 1usize
    while (1usize << levels) < n { levels += 1usize }
    let (up, up_error) = mem.alloc[graph.NodeId](a, levels * n)
    if up_error != ok { ret (zero, up_error) }
    var v = 0usize
    while v < n {
        up[v] = tree.parent[v]
        v += 1usize
    }
    var level = 1usize
    while level < levels {
        v = 0usize
        while v < n {
            let half = up[(level - 1usize) * n + v]
            up[level * n + v] = up[(level - 1usize) * n + usize(half)]
            v += 1usize
        }
        level += 1usize
    }
    ret (Lifting { up: up, depth: tree.depth[0..], levels: levels, count: n }, ok)
}

// The ancestor `steps` levels above `v` (the root when past it).
fn ancestor(l: *const Lifting, v: graph.NodeId, steps: u32) -> graph.NodeId {
    var at = v
    var remaining = steps
    var level = 0usize
    while remaining > 0u32 && level < l.levels {
        if (remaining & 1u32) == 1u32 { at = l.up[level * l.count + usize(at)] }
        remaining = remaining >> 1u32
        level += 1usize
    }
    ret at
}

// The lowest common ancestor in `O(log n)`.
fn lca(l: *const Lifting, a: graph.NodeId, b: graph.NodeId) -> graph.NodeId {
    var x = a
    var y = b
    if l.depth[usize(x)] < l.depth[usize(y)] {
        let swap = x
        x = y
        y = swap
    }
    x = ancestor(l, x, l.depth[usize(x)] - l.depth[usize(y)])
    if x == y { ret x }
    var level = l.levels
    while level > 0usize {
        level -= 1usize
        let px = l.up[level * l.count + usize(x)]
        let py = l.up[level * l.count + usize(y)]
        if px != py {
            x = px
            y = py
        }
    }
    ret l.up[usize(x)]
}

// The distance in edges between two nodes.
fn distance(l: *const Lifting, a: graph.NodeId, b: graph.NodeId) -> u32 {
    let c = lca(l, a, b)
    ret l.depth[usize(a)] + l.depth[usize(b)] - 2u32 * l.depth[usize(c)]
}

// Tarjan's offline LCA: answers every query pair in one traversal with a
// union-find; `queries` is pairs `(a, b)` flattened, `out` one answer per pair.
fn lca_offline[E: type](a: *mem.Arena, g: *const graph.Graph[E], tree: *const Rooted, queries: []const graph.NodeId, out: []graph.NodeId) -> err {
    let n = tree.parent.len
    let q = queries.len / 2usize
    if out.len < q { ret TooSmall }
    let (parent_set, ps_error) = mem.alloc[u32](a, n)
    if ps_error != ok { ret ps_error }
    let (rank, rank_error) = mem.alloc[u8](a, n)
    if rank_error != ok { ret rank_error }
    let (set0, set_error) = dsu.init(parent_set, rank, n)
    if set_error != ok { ret set_error }
    var sets = set0
    let (highest, highest_error) = mem.alloc[graph.NodeId](a, n)
    if highest_error != ok { ret highest_error }
    let (done, done_error) = mem.alloc[u8](a, n)
    if done_error != ok { ret done_error }
    var i = 0usize
    while i < n {
        highest[i] = u32(i)
        done[i] = 0u8
        i += 1usize
    }
    // A depth-first walk; Tarjan's steps happen when a node is finished.
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, n)
    if stack_error != ok { ret stack_error }
    let (cursor, cursor_error) = mem.alloc[usize](a, n)
    if cursor_error != ok { ret cursor_error }
    let root = tree.order[0usize]
    var depth = 1usize
    stack[0usize] = root
    cursor[usize(root)] = g.offsets[usize(root)]
    while depth > 0usize {
        let u = stack[depth - 1usize]
        var descended = false
        while cursor[usize(u)] < g.offsets[usize(u) + 1usize] {
            let v = g.edges[cursor[usize(u)]].to
            cursor[usize(u)] += 1usize
            if tree.parent[usize(v)] == u && v != u {
                stack[depth] = v
                depth += 1usize
                cursor[usize(v)] = g.offsets[usize(v)]
                descended = true
                break
            }
        }
        if descended { continue }
        // `u` is finished: answer its queries, then fold it into its parent.
        done[usize(u)] = 1u8
        var k = 0usize
        while k < q {
            let x = queries[2usize * k]
            let y = queries[2usize * k + 1usize]
            if x == u && done[usize(y)] == 1u8 {
                out[k] = highest[usize(dsu.find(&sets, y))]
            } else if y == u && done[usize(x)] == 1u8 {
                out[k] = highest[usize(dsu.find(&sets, x))]
            }
            k += 1usize
        }
        if u != root {
            let p = tree.parent[usize(u)]
            let joined = dsu.join(&sets, u, p)
            if !joined { ret NotATree }
            highest[usize(dsu.find(&sets, u))] = p
        }
        depth -= 1usize
    }
    ret ok
}

// The Euler tour: `sequence` lists each node on entry and after each child,
// `2n - 1` entries; `entry[v]` and `exit[v]` bound `v`'s subtree in it.
fn euler_tour[E: type](a: *mem.Arena, g: *const graph.Graph[E], tree: *const Rooted) -> (EulerTour, err) {
    let n = tree.parent.len
    let (entry, entry_error) = mem.alloc[u32](a, n)
    if entry_error != ok { ret (zero, entry_error) }
    let (exit, exit_error) = mem.alloc[u32](a, n)
    if exit_error != ok { ret (zero, exit_error) }
    let (sequence, sequence_error) = mem.alloc[graph.NodeId](a, 2usize * n)
    if sequence_error != ok { ret (zero, sequence_error) }
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, n)
    if stack_error != ok { ret (zero, stack_error) }
    let (cursor, cursor_error) = mem.alloc[usize](a, n)
    if cursor_error != ok { ret (zero, cursor_error) }
    let root = tree.order[0usize]
    var depth = 1usize
    stack[0usize] = root
    cursor[usize(root)] = g.offsets[usize(root)]
    var written = 0usize
    sequence[0usize] = root
    entry[usize(root)] = 0u32
    written = 1usize
    while depth > 0usize {
        let u = stack[depth - 1usize]
        var descended = false
        while cursor[usize(u)] < g.offsets[usize(u) + 1usize] {
            let v = g.edges[cursor[usize(u)]].to
            cursor[usize(u)] += 1usize
            if tree.parent[usize(v)] == u && v != u {
                stack[depth] = v
                depth += 1usize
                cursor[usize(v)] = g.offsets[usize(v)]
                entry[usize(v)] = u32(written)
                sequence[written] = v
                written += 1usize
                descended = true
                break
            }
        }
        if !descended {
            exit[usize(u)] = u32(written)
            depth -= 1usize
            if depth > 0usize {
                sequence[written] = stack[depth - 1usize]
                written += 1usize
            }
        }
    }
    ret (EulerTour { entry: entry, exit: exit, sequence: sequence[..written] }, ok)
}

// Heavy-light decomposition: `head[v]` is the top of `v`'s heavy path and
// `position[v]` its index in a layout where every heavy path is contiguous, so
// a root-to-node path is `O(log n)` contiguous ranges.
fn heavy_light(a: *mem.Arena, tree: *const Rooted) -> (HeavyLight, err) {
    let n = tree.parent.len
    let (heavy, heavy_error) = mem.alloc[graph.NodeId](a, n)
    if heavy_error != ok { ret (zero, heavy_error) }
    let (head, head_error) = mem.alloc[graph.NodeId](a, n)
    if head_error != ok { ret (zero, head_error) }
    let (position, position_error) = mem.alloc[u32](a, n)
    if position_error != ok { ret (zero, position_error) }
    var i = 0usize
    while i < n {
        heavy[i] = graph.NONE
        i += 1usize
    }
    // The heavy child is the one with the largest subtree, found from the BFS order.
    i = 1usize
    while i < n {
        let v = tree.order[i]
        let p = tree.parent[usize(v)]
        if heavy[usize(p)] == graph.NONE || tree.size[usize(v)] > tree.size[usize(heavy[usize(p)])] { heavy[usize(p)] = v }
        i += 1usize
    }
    // Positions: walk the BFS order; a node continues its parent's path when it
    // is the heavy child, otherwise starts a new one. Contiguity is arranged by
    // assigning positions along each heavy path first.
    var next_position = 0u32
    i = 0usize
    while i < n {
        let v = tree.order[i]
        if i == 0usize || heavy[usize(tree.parent[usize(v)])] != v {
            // Head of a path: lay the whole chain out.
            var at = v
            while at != graph.NONE {
                head[usize(at)] = v
                position[usize(at)] = next_position
                next_position += 1u32
                at = heavy[usize(at)]
            }
        }
        i += 1usize
    }
    ret (HeavyLight { head: head, position: position, parent: tree.parent, depth: tree.depth[0..] }, ok)
}

// Decomposes the path between `a` and `b` into position ranges `[lo, hi]`
// (inclusive, at most `2 log n` of them) written as pairs to `out`; answers
// how many pairs, or `TooSmall`.
fn path_ranges(h: *const HeavyLight, a: graph.NodeId, b: graph.NodeId, out: []u32) -> (usize, err) {
    var x = a
    var y = b
    var written = 0usize
    while h.head[usize(x)] != h.head[usize(y)] {
        if h.depth[usize(h.head[usize(x)])] < h.depth[usize(h.head[usize(y)])] {
            let swap = x
            x = y
            y = swap
        }
        let top = h.head[usize(x)]
        if written + 2usize > out.len { ret (0usize, TooSmall) }
        out[written] = h.position[usize(top)]
        out[written + 1usize] = h.position[usize(x)]
        written += 2usize
        x = h.parent[usize(top)]
    }
    if written + 2usize > out.len { ret (0usize, TooSmall) }
    var lo = h.position[usize(x)]
    var hi = h.position[usize(y)]
    if lo > hi {
        let swap = lo
        lo = hi
        hi = swap
    }
    out[written] = lo
    out[written + 1usize] = hi
    ret (written / 2usize + 1usize, ok)
}

// Centroid decomposition: `centroid_parent[v]` is `v`'s parent in the centroid
// tree (`NONE` at the top), `centroid_level[v]` its depth there.
fn centroid_decompose[E: type](a: *mem.Arena, g: *const graph.Graph[E], centroid_parent: []graph.NodeId, centroid_level: []u32) -> err {
    let n = graph.node_count[E](g)
    if centroid_parent.len < n || centroid_level.len < n { ret TooSmall }
    let (removed, removed_error) = mem.alloc[u8](a, n)
    if removed_error != ok { ret removed_error }
    let (size, size_error) = mem.alloc[u32](a, n)
    if size_error != ok { ret size_error }
    let (order, order_error) = mem.alloc[graph.NodeId](a, n)
    if order_error != ok { ret order_error }
    let (parent, parent_error) = mem.alloc[graph.NodeId](a, n)
    if parent_error != ok { ret parent_error }
    // Work list of (component root, centroid parent, level), processed iteratively.
    let (work_root, wr_error) = mem.alloc[graph.NodeId](a, n)
    if wr_error != ok { ret wr_error }
    let (work_parent, wp_error) = mem.alloc[graph.NodeId](a, n)
    if wp_error != ok { ret wp_error }
    let (work_level, wl_error) = mem.alloc[u32](a, n)
    if wl_error != ok { ret wl_error }
    var i = 0usize
    while i < n {
        removed[i] = 0u8
        centroid_parent[i] = graph.NONE
        centroid_level[i] = 0u32
        i += 1usize
    }
    if n == 0usize { ret ok }
    var work_count = 1usize
    work_root[0usize] = 0u32
    work_parent[0usize] = graph.NONE
    work_level[0usize] = 0u32
    while work_count > 0usize {
        work_count -= 1usize
        let start = work_root[work_count]
        let above = work_parent[work_count]
        let level = work_level[work_count]
        // BFS the component to size its subtrees.
        var head = 0usize
        var tail = 1usize
        order[0usize] = start
        parent[usize(start)] = start
        while head < tail {
            let u = order[head]
            head += 1usize
            size[usize(u)] = 1u32
            var k = g.offsets[usize(u)]
            while k < g.offsets[usize(u) + 1usize] {
                let v = g.edges[k].to
                if removed[usize(v)] == 0u8 && v != parent[usize(u)] && v != u {
                    parent[usize(v)] = u
                    order[tail] = v
                    tail += 1usize
                }
                k += 1usize
            }
        }
        let total = tail
        i = total
        while i > 1usize {
            i -= 1usize
            size[usize(parent[usize(order[i])])] += size[usize(order[i])]
        }
        // The centroid: walk down into any child holding more than half.
        var c = start
        while true {
            var heavy = graph.NONE
            var k = g.offsets[usize(c)]
            while k < g.offsets[usize(c) + 1usize] {
                let v = g.edges[k].to
                if removed[usize(v)] == 0u8 && v != parent[usize(c)] && v != c && usize(size[usize(v)]) * 2usize > total { heavy = v }
                k += 1usize
            }
            if heavy == graph.NONE { break }
            c = heavy
        }
        centroid_parent[usize(c)] = above
        centroid_level[usize(c)] = level
        removed[usize(c)] = 1u8
        var k = g.offsets[usize(c)]
        while k < g.offsets[usize(c) + 1usize] {
            let v = g.edges[k].to
            if removed[usize(v)] == 0u8 && v != c {
                if work_count >= n { ret TooSmall }
                work_root[work_count] = v
                work_parent[work_count] = c
                work_level[work_count] = level + 1u32
                work_count += 1usize
            }
            k += 1usize
        }
    }
    ret ok
}

// The Prüfer code of a labelled tree on `n` nodes: `n - 2` labels written to
// `out`, by repeatedly removing the smallest leaf.
fn prufer_encode[E: type](a: *mem.Arena, g: *const graph.Graph[E], out: []graph.NodeId) -> err {
    let n = graph.node_count[E](g)
    if n < 2usize { ret NotATree }
    if out.len < n - 2usize { ret TooSmall }
    let (degree, degree_error) = mem.alloc[u32](a, n)
    if degree_error != ok { ret degree_error }
    var i = 0usize
    while i < n {
        degree[i] = u32(g.offsets[i + 1usize] - g.offsets[i])
        i += 1usize
    }
    // The smallest leaf pointer only moves forward: a classic O(n) walk.
    var pointer = 0usize
    while pointer < n && degree[pointer] != 1u32 { pointer += 1usize }
    if pointer == n { ret NotATree }
    var leaf = pointer
    var written = 0usize
    while written < n - 2usize {
        // The leaf's one live neighbour.
        var neighbour = graph.NONE
        var k = g.offsets[leaf]
        while k < g.offsets[leaf + 1usize] {
            let v = g.edges[k].to
            if degree[usize(v)] > 0u32 && v != u32(leaf) { neighbour = v }
            k += 1usize
        }
        if neighbour == graph.NONE { ret NotATree }
        out[written] = neighbour
        written += 1usize
        degree[leaf] = 0u32
        degree[usize(neighbour)] -= 1u32
        if degree[usize(neighbour)] == 1u32 && usize(neighbour) < pointer {
            leaf = usize(neighbour)
        } else {
            pointer += 1usize
            while pointer < n && degree[pointer] != 1u32 { pointer += 1usize }
            leaf = pointer
        }
    }
    ret ok
}

// The edges of the tree with Prüfer code `code` (on `code.len + 2` nodes),
// written as `from, to` pairs to `edges` (`2 * (n - 1)` entries).
fn prufer_decode(a: *mem.Arena, code: []const graph.NodeId, edges: []graph.NodeId) -> err {
    let n = code.len + 2usize
    if edges.len < 2usize * (n - 1usize) { ret TooSmall }
    let (degree, degree_error) = mem.alloc[u32](a, n)
    if degree_error != ok { ret degree_error }
    var i = 0usize
    while i < n {
        degree[i] = 1u32
        i += 1usize
    }
    i = 0usize
    while i < code.len {
        if usize(code[i]) >= n { ret InvalidNode }
        degree[usize(code[i])] += 1u32
        i += 1usize
    }
    var pointer = 0usize
    while degree[pointer] != 1u32 { pointer += 1usize }
    var leaf = pointer
    var written = 0usize
    i = 0usize
    while i < code.len {
        let v = code[i]
        edges[written] = u32(leaf)
        edges[written + 1usize] = v
        written += 2usize
        degree[leaf] = 0u32
        degree[usize(v)] -= 1u32
        if degree[usize(v)] == 1u32 && usize(v) < pointer {
            leaf = usize(v)
        } else {
            pointer += 1usize
            while pointer < n && degree[pointer] != 1u32 { pointer += 1usize }
            leaf = pointer
        }
        i += 1usize
    }
    // The last two nodes with degree 1.
    var first = graph.NONE
    i = 0usize
    while i < n {
        if degree[i] == 1u32 {
            if first == graph.NONE { first = u32(i) } else {
                edges[written] = first
                edges[written + 1usize] = u32(i)
                written += 2usize
            }
        }
        i += 1usize
    }
    ret ok
}

// AHU canonical labels: `label[v]` is equal for two nodes exactly when their
// rooted subtrees are isomorphic (within the trees labelled together), so two
// rooted trees are isomorphic when their roots share a label. Labels are
// assigned by sorting each node's children's labels, over `scratch.len >= n`.
fn ahu_labels[E: type](a: *mem.Arena, g: *const graph.Graph[E], tree: *const Rooted, label: []u64, scratch: []u64) -> err {
    let n = tree.parent.len
    if label.len < n || scratch.len < n { ret TooSmall }
    // Children's sorted label sequences hash into a 64-bit label; equality of
    // sequences is what the hash approximates (collisions are astronomically rare).
    var i = n
    while i > 0usize {
        i -= 1usize
        let v = tree.order[i]
        var count = 0usize
        var k = g.offsets[usize(v)]
        while k < g.offsets[usize(v) + 1usize] {
            let c = g.edges[k].to
            if tree.parent[usize(c)] == v && c != v {
                scratch[count] = label[usize(c)]
                count += 1usize
            }
            k += 1usize
        }
        var s = 1usize
        while s < count {
            var t = s
            while t > 0usize && scratch[t] < scratch[t - 1usize] {
                let swap = scratch[t]
                scratch[t] = scratch[t - 1usize]
                scratch[t - 1usize] = swap
                t -= 1usize
            }
            s += 1usize
        }
        var h = 1469598103934665603u64
        var j = 0usize
        while j < count {
            h = (h ^ scratch[j]) *% 1099511628211u64
            h = h ^ (h >> 29u64)
            j += 1usize
        }
        label[usize(v)] = (h *% 2u64) +% 1u64
        if count == 0usize { label[usize(v)] = 3u64 }
    }
    ret ok
}

type LcaRmq = struct { entry: []const u32, sequence: []const graph.NodeId, depth: []const u32, table: []graph.NodeId, levels: usize, count: usize }

// The binary-lifting table straight from a graph and its root (`root_at`
// then `lifting`); query it with `lca`, `ancestor` and `distance`.
fn lca_binary_lifting[E: type](a: *mem.Arena, g: *const graph.Graph[E], root: graph.NodeId) -> (Lifting, err) {
    let (tree, tree_error) = root_at[E](a, g, root)
    if tree_error != ok { ret (zero, tree_error) }
    let (l, l_error) = lifting(a, &tree)
    ret (l, l_error)
}

// LCA by range-minimum over the Euler tour: `table[level * count + i]` is the
// shallowest node of `sequence[i .. i + 2^level]`, so a query is two lookups.
fn lca_rmq[E: type](a: *mem.Arena, g: *const graph.Graph[E], tree: *const Rooted) -> (LcaRmq, err) {
    let (tour, tour_error) = euler_tour[E](a, g, tree)
    if tour_error != ok { ret (zero, tour_error) }
    let count = tour.sequence.len
    var levels = 1usize
    while (1usize << levels) <= count { levels += 1usize }
    let (table, table_error) = mem.alloc[graph.NodeId](a, levels * count)
    if table_error != ok { ret (zero, table_error) }
    var i = 0usize
    while i < count {
        table[i] = tour.sequence[i]
        i += 1usize
    }
    var level = 1usize
    while level < levels {
        let half = 1usize << (level - 1usize)
        i = 0usize
        while i + 2usize * half <= count {
            let x = table[(level - 1usize) * count + i]
            let y = table[(level - 1usize) * count + i + half]
            table[level * count + i] = x
            if tree.depth[usize(y)] < tree.depth[usize(x)] { table[level * count + i] = y }
            i += 1usize
        }
        level += 1usize
    }
    ret (LcaRmq { entry: tour.entry[0..], sequence: tour.sequence, depth: tree.depth[0..], table: table, levels: levels, count: count }, ok)
}

// The lowest common ancestor in `O(1)`.
fn lca_rmq_query(r: *const LcaRmq, a: graph.NodeId, b: graph.NodeId) -> graph.NodeId {
    var lo = usize(r.entry[usize(a)])
    var hi = usize(r.entry[usize(b)])
    if lo > hi {
        let swap = lo
        lo = hi
        hi = swap
    }
    var level = 0usize
    while (2usize << level) <= hi - lo + 1usize { level += 1usize }
    let x = r.table[level * r.count + lo]
    let y = r.table[level * r.count + hi + 1usize - (1usize << level)]
    if r.depth[usize(y)] < r.depth[usize(x)] { ret y }
    ret x
}

// Rooted isomorphism: the AHU labels of the two roots agree.
fn is_isomorphic_rooted[E: type](a: *mem.Arena, first: *const graph.Graph[E], first_root: graph.NodeId, second: *const graph.Graph[E], second_root: graph.NodeId) -> (bool, err) {
    let n = graph.node_count[E](first)
    if n != graph.node_count[E](second) || first.edges.len != second.edges.len { ret (false, ok) }
    if n == 0usize { ret (true, ok) }
    let (t1, t1_error) = root_at[E](a, first, first_root)
    if t1_error != ok { ret (false, t1_error) }
    let (t2, t2_error) = root_at[E](a, second, second_root)
    if t2_error != ok { ret (false, t2_error) }
    let (labels, labels_error) = mem.alloc[u64](a, 3usize * n)
    if labels_error != ok { ret (false, labels_error) }
    let l1_error = ahu_labels[E](a, first, &t1, labels[..n], labels[2usize * n..3usize * n])
    if l1_error != ok { ret (false, l1_error) }
    let l2_error = ahu_labels[E](a, second, &t2, labels[n..2usize * n], labels[2usize * n..3usize * n])
    if l2_error != ok { ret (false, l2_error) }
    ret (labels[usize(first_root)] == labels[n + usize(second_root)], ok)
}

// Unrooted isomorphism: each tree rooted at its centre (both, when the
// centre is an edge) and compared as rooted trees.
fn is_isomorphic[E: type](a: *mem.Arena, first: *const graph.Graph[E], second: *const graph.Graph[E]) -> (bool, err) {
    let n = graph.node_count[E](first)
    if n != graph.node_count[E](second) || first.edges.len != second.edges.len { ret (false, ok) }
    if n == 0usize { ret (true, ok) }
    let (c1, c1_error) = algo.center[E](a, first)
    if c1_error != ok { ret (false, c1_error) }
    let (c2, c2_error) = algo.center[E](a, second)
    if c2_error != ok { ret (false, c2_error) }
    if c1.len != c2.len || c1.len == 0usize || c1.len > 2usize { ret (false, ok) }
    var i = 0usize
    while i < c1.len {
        let (same, same_error) = is_isomorphic_rooted[E](a, first, c1[i], second, c2[0usize])
        if same_error != ok { ret (false, same_error) }
        if same { ret (true, ok) }
        i += 1usize
    }
    ret (false, ok)
}
