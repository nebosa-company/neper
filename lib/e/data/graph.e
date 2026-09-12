// Immutable compressed-sparse-row adjacency, built through a `Builder` that only
// collects edges. `finish` counts each node's edges, turns the counts into offsets and
// places the edges so that node `n`'s are `edges[offsets[n] .. offsets[n + 1]]`, in the
// order they were added. Nodes are dense `0..node_count`, and a node named by an edge
// past that count grows the count -- the graph is whatever its edges reach.

use e.mem
use e.data.list as list

type NodeId = u32
const NONE: NodeId = 4294967295
type Edge[E: type] = struct { from: NodeId, to: NodeId, value: E }
type Builder[E: type] = struct { node_count: usize, edges: list.List[Edge[E]] }
type Graph[E: type] = struct { node_count: usize, offsets: []const usize, edges: []const Edge[E] }
type Neighbors[E: type] = struct { edges: []const Edge[E], index: usize }
type Nodes = struct { next: NodeId, end: NodeId }
error InvalidNode
error TooLarge

fn builder[E: type](a: *mem.Arena, initial_nodes: usize, edge_capacity: usize) -> (Builder[E], err) {
    if initial_nodes >= usize(NONE) { ret (zero, TooLarge) }
    let (edges, init_error) = list.init[Edge[E]](a, edge_capacity)
    if init_error != ok { ret (zero, init_error) }
    var b: Builder[E] = zero
    b.node_count = initial_nodes
    b.edges = edges
    ret (b, ok)
}

fn add_directed[E: type](b: *Builder[E], from: NodeId, to: NodeId, value: E) -> err {
    if from == NONE || to == NONE { ret TooLarge }
    var edge: Edge[E] = zero
    edge.from = from
    edge.to = to
    edge.value = value
    try list.push[Edge[E]](&b.edges, edge)
    if usize(from) >= b.node_count { b.node_count = usize(from) + 1usize }
    if usize(to) >= b.node_count { b.node_count = usize(to) + 1usize }
    ret ok
}

// Two directed edges, both reserved first so that a failure leaves the builder as it was.
fn add_undirected[E: type](b: *Builder[E], a: NodeId, b_node: NodeId, value: E) -> err {
    if a == NONE || b_node == NONE { ret TooLarge }
    try list.reserve[Edge[E]](&b.edges, b.edges.len + 2usize)
    try add_directed[E](b, a, b_node, value)
    ret add_directed[E](b, b_node, a, value)
}

fn finish[E: type](a: *mem.Arena, b: *const Builder[E]) -> (Graph[E], err) {
    var empty: Graph[E] = zero
    if b.node_count >= usize(NONE) { ret (empty, TooLarge) }
    let (offsets, offsets_error) = mem.alloc[usize](a, b.node_count + 1usize)
    if offsets_error != ok { ret (empty, offsets_error) }
    let (placed, placed_error) = mem.alloc[Edge[E]](a, b.edges.len)
    if placed_error != ok { ret (empty, placed_error) }
    var at = 0usize
    while at <= b.node_count {
        offsets[at] = 0usize
        at += 1usize
    }
    // Count into offsets[from + 1], then prefix-sum: offsets[n] is where node n starts.
    at = 0usize
    while at < b.edges.len {
        let from = usize(b.edges.items[at].from) + 1usize
        offsets[from] += 1usize
        at += 1usize
    }
    at = 1usize
    while at <= b.node_count {
        offsets[at] += offsets[at - 1usize]
        at += 1usize
    }
    // Place each edge at its node's next free position, walking the edges in order so
    // that a node's edges keep the order they were added in.
    let (cursor, cursor_error) = mem.alloc[usize](a, b.node_count + 1usize)
    if cursor_error != ok { ret (empty, cursor_error) }
    at = 0usize
    while at <= b.node_count {
        cursor[at] = offsets[at]
        at += 1usize
    }
    at = 0usize
    while at < b.edges.len {
        let edge = b.edges.items[at]
        placed[cursor[usize(edge.from)]] = edge
        cursor[usize(edge.from)] += 1usize
        at += 1usize
    }
    var g: Graph[E] = zero
    g.node_count = b.node_count
    g.offsets = offsets[0..]
    g.edges = placed[0..]
    ret (g, ok)
}

fn node_count[E: type](g: *const Graph[E]) -> usize { ret g.node_count }

fn edge_count[E: type](g: *const Graph[E]) -> usize { ret g.edges.len }

fn nodes[E: type](g: *const Graph[E]) -> Nodes {
    ret Nodes { next: 0u32, end: u32(g.node_count) }
}

fn nodes_next(it: *Nodes) -> (NodeId, bool) {
    if it.next >= it.end { ret (NONE, false) }
    let id = it.next
    it.next += 1u32
    ret (id, true)
}

fn neighbors[E: type](g: *const Graph[E], node: NodeId) -> (Neighbors[E], err) {
    if usize(node) >= g.node_count { ret (zero, InvalidNode) }
    var it: Neighbors[E] = zero
    it.edges = g.edges[g.offsets[usize(node)]..g.offsets[usize(node) + 1usize]]
    it.index = 0usize
    ret (it, ok)
}

fn neighbors_next[E: type](it: *Neighbors[E]) -> (Edge[E], bool) {
    if it.index >= it.edges.len { ret (zero, false) }
    let edge = it.edges[it.index]
    it.index += 1usize
    ret (edge, true)
}
