// Subgraph and graph isomorphism over `e.data.graph` by VF2-style
// backtracking in caller storage: pattern nodes are matched in order, each
// candidate host node checked for degree and for every edge to an
// already matched pattern node (and, for `isomorphic`, every non-edge).
// `subgraph_vf2` finds a monomorphism of the pattern into the host graph,
// `isomorphic` an isomorphism between two graphs of one size; both write
// the mapping and answer whether one exists. Exponential in the worst
// case, as the problem is.

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
