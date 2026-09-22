// Subgraph and graph isomorphism over `e.data.graph` by VF2-style
// backtracking in caller storage: pattern nodes are matched in order, each
// candidate host node checked for degree and for every edge to an
// already matched pattern node (and, for `isomorphic`, every non-edge).
// `subgraph_vf2` finds a monomorphism of the pattern into the host graph,
// `isomorphic` an isomorphism between two graphs of one size; both write
// the mapping and answer whether one exists. Exponential in the worst
// case, as the problem is. `is_planar` is the LR planarity test.

use e.mem
use e.data.graph as graph

error TooSmall

fn degree[E: type](g: *const graph.Graph[E], v: usize) -> usize { ret g.offsets[v + 1usize] - g.offsets[v] }

fn adjacent[E: type](g: *const graph.Graph[E], v: usize, w: usize) -> bool {
    var e = g.offsets[v]
    while e < g.offsets[v + 1usize] {
        if usize(g.edges[e].to) == w { ret true }
        e += 1usize
    }
    ret false
}

// Can pattern node `p` map to host node `t` given the mapping so far?
fn feasible[E: type](pattern: *const graph.Graph[E], host: *const graph.Graph[E], mapping: []const u32, used: []const u8, p: usize, t: usize, induced: bool) -> bool {
    if used[t] != 0u8 { ret false }
    if degree[E](host, t) < degree[E](pattern, p) { ret false }
    if induced && degree[E](host, t) != degree[E](pattern, p) { ret false }
    // Every matched pattern neighbour of p must be a host neighbour of t.
    var e = pattern.offsets[p]
    while e < pattern.offsets[p + 1usize] {
        let q = usize(pattern.edges[e].to)
        if mapping[q] != graph.NONE && !adjacent[E](host, t, usize(mapping[q])) { ret false }
        e += 1usize
    }
    if induced {
        // And every matched pattern non-neighbour must be a host non-neighbour.
        var q = 0usize
        while q < graph.node_count[E](pattern) {
            if q != p && mapping[q] != graph.NONE && !adjacent[E](pattern, p, q) && adjacent[E](host, t, usize(mapping[q])) { ret false }
            q += 1usize
        }
    }
    ret true
}

fn search[E: type](pattern: *const graph.Graph[E], host: *const graph.Graph[E], mapping: []u32, used: []u8, p: usize, induced: bool) -> bool {
    let np = graph.node_count[E](pattern)
    if p == np { ret true }
    let nt = graph.node_count[E](host)
    var t = 0usize
    while t < nt {
        if feasible[E](pattern, host, mapping, used, p, t, induced) {
            mapping[p] = u32(t)
            used[t] = 1u8
            if search[E](pattern, host, mapping, used, p + 1usize, induced) { ret true }
            mapping[p] = graph.NONE
            used[t] = 0u8
        }
        t += 1usize
    }
    ret false
}

// A monomorphism of `pattern` into `host`: `mapping` (pattern node ->
// host node) and `used.len >= host nodes` scratch.
fn subgraph_vf2[E: type](pattern: *const graph.Graph[E], host: *const graph.Graph[E], mapping: []u32, used: []u8) -> (bool, err) {
    let np = graph.node_count[E](pattern)
    let nt = graph.node_count[E](host)
    if mapping.len < np || used.len < nt { ret (false, TooSmall) }
    if np > nt { ret (false, ok) }
    var i = 0usize
    while i < np {
        mapping[i] = graph.NONE
        i += 1usize
    }
    i = 0usize
    while i < nt {
        used[i] = 0u8
        i += 1usize
    }
    ret (search[E](pattern, host, mapping, used, 0usize, false), ok)
}

// An isomorphism between `a` and `b` (same node and edge counts).
fn isomorphic[E: type](a: *const graph.Graph[E], b: *const graph.Graph[E], mapping: []u32, used: []u8) -> (bool, err) {
    let n = graph.node_count[E](a)
    if mapping.len < n || used.len < n { ret (false, TooSmall) }
    if n != graph.node_count[E](b) || a.edges.len != b.edges.len { ret (false, ok) }
    var i = 0usize
    while i < n {
        mapping[i] = graph.NONE
        used[i] = 0u8
        i += 1usize
    }
    ret (search[E](a, b, mapping, used, 0usize, true), ok)
}

// LR planarity (de Fraysseix & Rosenstiehl, the algorithm behind
// `networkx.check_planarity`): a depth-first search orients every edge as a
// tree or back edge and computes lowpoints and nesting depths, then a second
// walk in nesting order keeps a stack of conflict pairs of return-edge
// intervals; the graph is planar exactly when no pair is forced to have both
// sides conflicting. Undirected input (every edge in both lists); self loops
// are ignored and a parallel edge collapses into the first. Edges are indexed
// as in `g.edges`; `NONE` marks an absent edge. Recursive in the tree depth.
type Planarity = struct { height: []u32, parent_edge: []u32, lowpt: []u32, lowpt2: []u32, nesting: []u32, oriented: []u8, ordered: []u32, out_count: []usize, lowpt_edge: []u32, chain: []u32, bottom: []usize, stack: []u32, top: usize }

fn already_oriented[E: type](g: *const graph.Graph[E], s: *Planarity, v: usize, w: usize) -> bool {
    var k = g.offsets[v]
    while k < g.offsets[v + 1usize] {
        if s.oriented[k] == 1u8 && usize(g.edges[k].to) == w { ret true }
        k += 1usize
    }
    k = g.offsets[w]
    while k < g.offsets[w + 1usize] {
        if s.oriented[k] == 1u8 && usize(g.edges[k].to) == v { ret true }
        k += 1usize
    }
    ret false
}

fn min_u32(x: u32, y: u32) -> u32 {
    if x < y { ret x }
    ret y
}

fn dfs_orientation[E: type](g: *const graph.Graph[E], s: *Planarity, v: usize) {
    let e = s.parent_edge[v]
    var k = g.offsets[v]
    while k < g.offsets[v + 1usize] {
        let w = usize(g.edges[k].to)
        if w == v || already_oriented[E](g, s, v, w) {
            k += 1usize
            continue
        }
        s.oriented[k] = 1u8
        s.lowpt[k] = s.height[v]
        s.lowpt2[k] = s.height[v]
        if s.height[w] == graph.NONE {
            s.parent_edge[w] = u32(k)
            s.height[w] = s.height[v] + 1u32
            dfs_orientation[E](g, s, w)
        } else {
            s.lowpt[k] = s.height[w]
        }
        s.nesting[k] = 2u32 * s.lowpt[k]
        if s.lowpt2[k] < s.height[v] { s.nesting[k] += 1u32 }
        if e != graph.NONE {
            let pe = usize(e)
            if s.lowpt[k] < s.lowpt[pe] {
                s.lowpt2[pe] = min_u32(s.lowpt[pe], s.lowpt2[k])
                s.lowpt[pe] = s.lowpt[k]
            } else if s.lowpt[k] > s.lowpt[pe] {
                s.lowpt2[pe] = min_u32(s.lowpt2[pe], s.lowpt[k])
            } else {
                s.lowpt2[pe] = min_u32(s.lowpt2[pe], s.lowpt2[k])
            }
        }
        k += 1usize
    }
}

fn interval_empty(s: *const Planarity, at: usize) -> bool { ret s.stack[at] == graph.NONE && s.stack[at + 1usize] == graph.NONE }

// Does the interval at `at` (low, high) conflict with edge `b`?
fn conflicting(s: *const Planarity, at: usize, b: usize) -> bool {
    if interval_empty(s, at) { ret false }
    ret s.lowpt[usize(s.stack[at + 1usize])] > s.lowpt[b]
}

fn swap_sides(s: *Planarity, p: usize) {
    let ll = s.stack[4usize * p]
    let lh = s.stack[4usize * p + 1usize]
    s.stack[4usize * p] = s.stack[4usize * p + 2usize]
    s.stack[4usize * p + 1usize] = s.stack[4usize * p + 3usize]
    s.stack[4usize * p + 2usize] = ll
    s.stack[4usize * p + 3usize] = lh
}

// The lowest lowpoint of the pair at `p` (`NONE` when both sides are empty).
fn lowest(s: *const Planarity, p: usize) -> u32 {
    let left = interval_empty(s, 4usize * p)
    let right = interval_empty(s, 4usize * p + 2usize)
    if left && right { ret graph.NONE }
    if left { ret s.lowpt[usize(s.stack[4usize * p + 2usize])] }
    if right { ret s.lowpt[usize(s.stack[4usize * p])] }
    ret min_u32(s.lowpt[usize(s.stack[4usize * p])], s.lowpt[usize(s.stack[4usize * p + 2usize])])
}

fn add_constraints(s: *Planarity, ei: usize, e: usize) -> bool {
    var pl_low = graph.NONE
    var pl_high = graph.NONE
    var pr_low = graph.NONE
    var pr_high = graph.NONE
    // Merge the return edges of `ei` into the right side.
    var merging = true
    while merging && s.top > 0usize {
        s.top -= 1usize
        let q = 4usize * s.top
        if !interval_empty(s, q) { swap_sides(s, s.top) }
        if !interval_empty(s, q) { ret false }
        let qr_low = s.stack[q + 2usize]
        let qr_high = s.stack[q + 3usize]
        if s.lowpt[usize(qr_low)] > s.lowpt[e] {
            if pr_low == graph.NONE && pr_high == graph.NONE {
                pr_high = qr_high
            } else {
                s.chain[usize(pr_low)] = qr_high
            }
            pr_low = qr_low
        } else {
            s.chain[usize(qr_low)] = s.lowpt_edge[e]
        }
        if s.top == s.bottom[ei] { merging = false }
    }
    // Merge the conflicting return edges of the earlier siblings into the left side.
    while s.top > 0usize && (conflicting(s, 4usize * (s.top - 1usize), ei) || conflicting(s, 4usize * (s.top - 1usize) + 2usize, ei)) {
        s.top -= 1usize
        let q = 4usize * s.top
        if conflicting(s, q + 2usize, ei) { swap_sides(s, s.top) }
        if conflicting(s, q + 2usize, ei) { ret false }
        if pr_low != graph.NONE { s.chain[usize(pr_low)] = s.stack[q + 3usize] }
        if s.stack[q + 2usize] != graph.NONE { pr_low = s.stack[q + 2usize] }
        if pl_low == graph.NONE && pl_high == graph.NONE {
            pl_high = s.stack[q + 1usize]
        } else {
            s.chain[usize(pl_low)] = s.stack[q + 1usize]
        }
        pl_low = s.stack[q]
    }
    if !(pl_low == graph.NONE && pl_high == graph.NONE && pr_low == graph.NONE && pr_high == graph.NONE) {
        let p = 4usize * s.top
        s.stack[p] = pl_low
        s.stack[p + 1usize] = pl_high
        s.stack[p + 2usize] = pr_low
        s.stack[p + 3usize] = pr_high
        s.top += 1usize
    }
    ret true
}

fn remove_back_edges[E: type](g: *const graph.Graph[E], s: *Planarity, e: usize) {
    let u = g.edges[e].from
    // Drop the pairs made only of edges returning to `u`.
    while s.top > 0usize && lowest(s, s.top - 1usize) == s.height[usize(u)] { s.top -= 1usize }
    if s.top > 0usize {
        let p = 4usize * (s.top - 1usize)
        while s.stack[p + 1usize] != graph.NONE && g.edges[usize(s.stack[p + 1usize])].to == u { s.stack[p + 1usize] = s.chain[usize(s.stack[p + 1usize])] }
        if s.stack[p + 1usize] == graph.NONE && s.stack[p] != graph.NONE {
            s.chain[usize(s.stack[p])] = s.stack[p + 2usize]
            s.stack[p] = graph.NONE
        }
        while s.stack[p + 3usize] != graph.NONE && g.edges[usize(s.stack[p + 3usize])].to == u { s.stack[p + 3usize] = s.chain[usize(s.stack[p + 3usize])] }
        if s.stack[p + 3usize] == graph.NONE && s.stack[p + 2usize] != graph.NONE {
            s.chain[usize(s.stack[p + 2usize])] = s.stack[p]
            s.stack[p + 2usize] = graph.NONE
        }
    }
    if s.lowpt[e] < s.height[usize(u)] && s.top > 0usize {
        let hl = s.stack[4usize * (s.top - 1usize) + 1usize]
        let hr = s.stack[4usize * (s.top - 1usize) + 3usize]
        if hl != graph.NONE && (hr == graph.NONE || s.lowpt[usize(hl)] > s.lowpt[usize(hr)]) {
            s.chain[e] = hl
        } else {
            s.chain[e] = hr
        }
    }
}

fn dfs_testing[E: type](g: *const graph.Graph[E], s: *Planarity, v: usize) -> bool {
    let e = s.parent_edge[v]
    var i = 0usize
    while i < s.out_count[v] {
        let ei = usize(s.ordered[g.offsets[v] + i])
        let w = usize(g.edges[ei].to)
        s.bottom[ei] = s.top
        if s.parent_edge[w] == u32(ei) {
            if !dfs_testing[E](g, s, w) { ret false }
        } else {
            s.lowpt_edge[ei] = u32(ei)
            let p = 4usize * s.top
            s.stack[p] = graph.NONE
            s.stack[p + 1usize] = graph.NONE
            s.stack[p + 2usize] = u32(ei)
            s.stack[p + 3usize] = u32(ei)
            s.top += 1usize
        }
        if s.lowpt[ei] < s.height[v] && e != graph.NONE {
            if i == 0usize {
                s.lowpt_edge[usize(e)] = s.lowpt_edge[ei]
            } else if !add_constraints(s, ei, usize(e)) {
                ret false
            }
        }
        i += 1usize
    }
    if e != graph.NONE { remove_back_edges[E](g, s, usize(e)) }
    ret true
}

// Is the undirected graph planar? Linear space in the edges, from the arena.
fn is_planar[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (bool, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    let (height, height_error) = mem.alloc[u32](a, n)
    if height_error != ok { ret (false, height_error) }
    let (parent_edge, parent_error) = mem.alloc[u32](a, n)
    if parent_error != ok { ret (false, parent_error) }
    let (out_count, out_error) = mem.alloc[usize](a, n)
    if out_error != ok { ret (false, out_error) }
    let (words, words_error) = mem.alloc[u32](a, 6usize * m)
    if words_error != ok { ret (false, words_error) }
    let (oriented, oriented_error) = mem.alloc[u8](a, m)
    if oriented_error != ok { ret (false, oriented_error) }
    let (bottom, bottom_error) = mem.alloc[usize](a, m)
    if bottom_error != ok { ret (false, bottom_error) }
    let (stack, stack_error) = mem.alloc[u32](a, 4usize * (m + 1usize))
    if stack_error != ok { ret (false, stack_error) }
    var s = Planarity { height: height, parent_edge: parent_edge, lowpt: words[..m], lowpt2: words[m..2usize * m], nesting: words[2usize * m..3usize * m], oriented: oriented, ordered: words[3usize * m..4usize * m], out_count: out_count, lowpt_edge: words[4usize * m..5usize * m], chain: words[5usize * m..6usize * m], bottom: bottom, stack: stack, top: 0usize }
    var i = 0usize
    while i < n {
        height[i] = graph.NONE
        parent_edge[i] = graph.NONE
        i += 1usize
    }
    i = 0usize
    while i < m {
        oriented[i] = 0u8
        s.chain[i] = graph.NONE
        i += 1usize
    }
    var v = 0usize
    while v < n {
        if height[v] == graph.NONE {
            height[v] = 0u32
            dfs_orientation[E](g, &s, v)
        }
        v += 1usize
    }
    // Each node's oriented edges in nesting order (insertion sort, stable).
    v = 0usize
    while v < n {
        var count = 0usize
        var k = g.offsets[v]
        while k < g.offsets[v + 1usize] {
            if oriented[k] == 1u8 {
                var t = count
                while t > 0usize && s.nesting[usize(s.ordered[g.offsets[v] + t - 1usize])] > s.nesting[k] {
                    s.ordered[g.offsets[v] + t] = s.ordered[g.offsets[v] + t - 1usize]
                    t -= 1usize
                }
                s.ordered[g.offsets[v] + t] = u32(k)
                count += 1usize
            }
            k += 1usize
        }
        out_count[v] = count
        v += 1usize
    }
    v = 0usize
    while v < n {
        if parent_edge[v] == graph.NONE {
            if !dfs_testing[E](g, &s, v) { ret (false, ok) }
        }
        v += 1usize
    }
    ret (true, ok)
}
