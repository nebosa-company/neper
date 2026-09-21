// Spanning structures and connectivity over `e.data.graph`: minimum spanning
// trees by Kruskal, Prim and Borůvka (each answering the chosen edge indices
// and the total weight), bridges and articulation points by Tarjan's low-link
// walk, Eulerian paths and circuits by Hierholzer, and the transitive closure
// as a bit matrix. Undirected graphs are those built with `add_undirected`,
// where every edge appears in both adjacency lists; the MST and connectivity
// routines assume that form.

use e.mem
use e.data.graph as graph
use e.algo.disjoint_set as dsu

type Forest = struct { edges: []const usize, weight: f64, trees: usize }
error InvalidNode
error TooSmall
error NotEulerian

// Kruskal: edge indices (into `g.edges`, one per undirected edge) sorted by
// weight and joined when they connect different components. `trees` counts the
// components the forest has.
fn kruskal[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Forest, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    let (order, order_error) = mem.alloc[usize](a, m)
    if order_error != ok { ret (zero, order_error) }
    let (weights, weights_error) = mem.alloc[f64](a, m)
    if weights_error != ok { ret (zero, weights_error) }
    var k = 0usize
    while k < m {
        order[k] = k
        weights[k] = weight(ctx, g.edges[k])
        k += 1usize
    }
    sort_by_weight(order, weights)
    let (parent, parent_error) = mem.alloc[u32](a, n)
    if parent_error != ok { ret (zero, parent_error) }
    let (rank, rank_error) = mem.alloc[u8](a, n)
    if rank_error != ok { ret (zero, rank_error) }
    let (set0, set_error) = dsu.init(parent, rank, n)
    if set_error != ok { ret (zero, set_error) }
    var sets = set0
    let (chosen, chosen_error) = mem.alloc[usize](a, n)
    if chosen_error != ok { ret (zero, chosen_error) }
    var count = 0usize
    var total = 0.0f64
    k = 0usize
    while k < m {
        let e = g.edges[order[k]]
        // Each undirected edge is listed twice; only its from < to copy is considered.
        if e.from < e.to && dsu.join(&sets, e.from, e.to) {
            chosen[count] = order[k]
            count += 1usize
            total += weights[order[k]]
        }
        k += 1usize
    }
    ret (Forest { edges: chosen[..count], weight: total, trees: dsu.set_count(&sets) }, ok)
}

// Heapsort of `order` by `weights`, ties by index so the answer is deterministic.
fn sort_by_weight(order: []usize, weights: []const f64) {
    let n = order.len
    var start = n / 2usize
    while start > 0usize {
        start -= 1usize
        sift(order, weights, start, n)
    }
    var end = n
    while end > 1usize {
        end -= 1usize
        let carried = order[0usize]
        order[0usize] = order[end]
        order[end] = carried
        sift(order, weights, 0usize, end)
    }
}

fn lighter(weights: []const f64, a: usize, b: usize) -> bool {
    if weights[a] != weights[b] { ret weights[a] < weights[b] }
    ret a < b
}

fn sift(order: []usize, weights: []const f64, at: usize, end: usize) {
    var here = at
    while true {
        let left = here * 2usize + 1usize
        if left >= end { break }
        var largest = left
        let right = left + 1usize
        if right < end && lighter(weights, order[left], order[right]) { largest = right }
        if !lighter(weights, order[here], order[largest]) { break }
        let carried = order[here]
        order[here] = order[largest]
        order[largest] = carried
        here = largest
    }
}

// Prim from `start`, with an `O(n^2)` selection: the tree of `start`'s
// component (`trees` is 1 when the graph is connected from `start`).
fn prim[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Forest, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n { ret (zero, InvalidNode) }
    let (best, best_error) = mem.alloc[f64](a, n)
    if best_error != ok { ret (zero, best_error) }
    let (via, via_error) = mem.alloc[usize](a, n)
    if via_error != ok { ret (zero, via_error) }
    let (done, done_error) = mem.alloc[u8](a, n)
    if done_error != ok { ret (zero, done_error) }
    let (chosen, chosen_error) = mem.alloc[usize](a, n)
    if chosen_error != ok { ret (zero, chosen_error) }
    let none = 18446744073709551615usize
    var i = 0usize
    while i < n {
        best[i] = 1.0e300f64
        via[i] = none
        done[i] = 0u8
        i += 1usize
    }
    best[usize(start)] = 0.0f64
    var count = 0usize
    var total = 0.0f64
    var reached = 0usize
    while true {
        var pick = n
        i = 0usize
        while i < n {
            if done[i] == 0u8 && via[i] != none || (done[i] == 0u8 && i == usize(start)) {
                if pick == n || best[i] < best[pick] { pick = i }
            }
            i += 1usize
        }
        if pick == n { break }
        done[pick] = 1u8
        reached += 1usize
        if via[pick] != none {
            chosen[count] = via[pick]
            count += 1usize
            total += best[pick]
        }
        var k = g.offsets[pick]
        while k < g.offsets[pick + 1usize] {
            let e = g.edges[k]
            let w = weight(ctx, e)
            if done[usize(e.to)] == 0u8 && w < best[usize(e.to)] {
                best[usize(e.to)] = w
                via[usize(e.to)] = k
            }
            k += 1usize
        }
    }
    ret (Forest { edges: chosen[..count], weight: total, trees: n - reached + 1usize }, ok)
}

// Borůvka: every component picks its cheapest outgoing edge per round.
fn boruvka[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Forest, err) {
    let n = graph.node_count[E](g)
    let (parent, parent_error) = mem.alloc[u32](a, n)
    if parent_error != ok { ret (zero, parent_error) }
    let (rank, rank_error) = mem.alloc[u8](a, n)
    if rank_error != ok { ret (zero, rank_error) }
    let (set0, set_error) = dsu.init(parent, rank, n)
    if set_error != ok { ret (zero, set_error) }
    var sets = set0
    let (cheapest, cheapest_error) = mem.alloc[usize](a, n)
    if cheapest_error != ok { ret (zero, cheapest_error) }
    let (chosen, chosen_error) = mem.alloc[usize](a, n)
    if chosen_error != ok { ret (zero, chosen_error) }
    let none = 18446744073709551615usize
    var count = 0usize
    var total = 0.0f64
    while true {
        var i = 0usize
        while i < n {
            cheapest[i] = none
            i += 1usize
        }
        var k = 0usize
        while k < g.edges.len {
            let e = g.edges[k]
            let ra = dsu.find(&sets, e.from)
            let rb = dsu.find(&sets, e.to)
            if ra != rb {
                let w = weight(ctx, e)
                if cheapest[usize(ra)] == none || w < weight(ctx, g.edges[cheapest[usize(ra)]]) || (w == weight(ctx, g.edges[cheapest[usize(ra)]]) && k < cheapest[usize(ra)]) { cheapest[usize(ra)] = k }
            }
            k += 1usize
        }
        var merged = false
        i = 0usize
        while i < n {
            if cheapest[i] != none {
                let e = g.edges[cheapest[i]]
                if dsu.join(&sets, e.from, e.to) {
                    // Record the edge by its from < to copy so callers see one index per edge.
                    var index = cheapest[i]
                    if e.from > e.to { index = twin[E](g, cheapest[i]) }
                    chosen[count] = index
                    count += 1usize
                    total += weight(ctx, e)
                    merged = true
                }
            }
            i += 1usize
        }
        if !merged { break }
    }
    ret (Forest { edges: chosen[..count], weight: total, trees: dsu.set_count(&sets) }, ok)
}

// The index of the reverse copy of undirected edge `k`.
fn twin[E: type](g: *const graph.Graph[E], k: usize) -> usize {
    let e = g.edges[k]
    var j = g.offsets[usize(e.to)]
    while j < g.offsets[usize(e.to) + 1usize] {
        if g.edges[j].to == e.from { ret j }
        j += 1usize
    }
    ret k
}

// Bridges (`is_bridge[k] = 1` for the from < to copy) and articulation points
// (`is_cut[v] = 1`) by one low-link depth-first walk.
fn bridges_and_cuts[E: type](a: *mem.Arena, g: *const graph.Graph[E], is_bridge: []u8, is_cut: []u8) -> err {
    let n = graph.node_count[E](g)
    if is_bridge.len < g.edges.len || is_cut.len < n { ret TooSmall }
    let (disc, disc_error) = mem.alloc[u32](a, n)
    if disc_error != ok { ret disc_error }
    let (low, low_error) = mem.alloc[u32](a, n)
    if low_error != ok { ret low_error }
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, n)
    if stack_error != ok { ret stack_error }
    let (cursor, cursor_error) = mem.alloc[usize](a, n)
    if cursor_error != ok { ret cursor_error }
    let (in_edge, in_edge_error) = mem.alloc[usize](a, n)
    if in_edge_error != ok { ret in_edge_error }
    let none = 18446744073709551615usize
    var i = 0usize
    while i < n {
        disc[i] = graph.NONE
        is_cut[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < g.edges.len {
        is_bridge[i] = 0u8
        i += 1usize
    }
    var time = 0u32
    var root = 0usize
    while root < n {
        if disc[root] != graph.NONE {
            root += 1usize
            continue
        }
        var depth = 1usize
        stack[0usize] = u32(root)
        cursor[root] = g.offsets[root]
        in_edge[root] = none
        disc[root] = time
        low[root] = time
        time += 1u32
        var root_children = 0usize
        while depth > 0usize {
            let u = stack[depth - 1usize]
            var descended = false
            while cursor[usize(u)] < g.offsets[usize(u) + 1usize] {
                let k = cursor[usize(u)]
                cursor[usize(u)] += 1usize
                let v = g.edges[k].to
                // Skip the edge we came in on (by index, so parallel edges count).
                if in_edge[usize(u)] != none && twin[E](g, in_edge[usize(u)]) == k { continue }
                if disc[usize(v)] == graph.NONE {
                    disc[usize(v)] = time
                    low[usize(v)] = time
                    time += 1u32
                    in_edge[usize(v)] = k
                    cursor[usize(v)] = g.offsets[usize(v)]
                    stack[depth] = v
                    depth += 1usize
                    if usize(u) == root { root_children += 1usize }
                    descended = true
                    break
                } else if disc[usize(v)] < low[usize(u)] {
                    low[usize(u)] = disc[usize(v)]
                }
            }
            if descended { continue }
            depth -= 1usize
            if depth > 0usize {
                let p = stack[depth - 1usize]
                if low[usize(u)] < low[usize(p)] { low[usize(p)] = low[usize(u)] }
                let k = in_edge[usize(u)]
                if low[usize(u)] > disc[usize(p)] {
                    var index = k
                    if g.edges[k].from > g.edges[k].to { index = twin[E](g, k) }
                    is_bridge[index] = 1u8
                }
                if usize(p) != root && low[usize(u)] >= disc[usize(p)] { is_cut[usize(p)] = 1u8 }
            }
        }
        if root_children > 1usize { is_cut[root] = 1u8 }
        root += 1usize
    }
    ret ok
}

// Hierholzer over a directed graph: an Eulerian circuit when every node has
// in-degree equal to out-degree, or the Eulerian path from the one node with
// an extra out-edge; `NotEulerian` otherwise. Answers the node sequence.
fn euler_path[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    if m == 0usize { ret (zero, NotEulerian) }
    let (indegree, in_error) = mem.alloc[u32](a, n)
    if in_error != ok { ret (zero, in_error) }
    var i = 0usize
    while i < n {
        indegree[i] = 0u32
        i += 1usize
    }
    var k = 0usize
    while k < m {
        indegree[usize(g.edges[k].to)] += 1u32
        k += 1usize
    }
    var start = graph.NONE
    var ends = 0usize
    var starts = 0usize
    i = 0usize
    while i < n {
        let out = g.offsets[i + 1usize] - g.offsets[i]
        if out == usize(indegree[i]) + 1usize {
            starts += 1usize
            start = u32(i)
        } else if usize(indegree[i]) == out + 1usize {
            ends += 1usize
        } else if usize(indegree[i]) != out {
            ret (zero, NotEulerian)
        }
        i += 1usize
    }
    if !((starts == 0usize && ends == 0usize) || (starts == 1usize && ends == 1usize)) { ret (zero, NotEulerian) }
    if start == graph.NONE { start = g.edges[0usize].from }
    let (cursor, cursor_error) = mem.alloc[usize](a, n)
    if cursor_error != ok { ret (zero, cursor_error) }
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, m + 1usize)
    if stack_error != ok { ret (zero, stack_error) }
    let (out, out_error) = mem.alloc[graph.NodeId](a, m + 1usize)
    if out_error != ok { ret (zero, out_error) }
    i = 0usize
    while i < n {
        cursor[i] = g.offsets[i]
        i += 1usize
    }
    var depth = 1usize
    stack[0usize] = start
    var written = 0usize
    while depth > 0usize {
        let u = stack[depth - 1usize]
        if cursor[usize(u)] < g.offsets[usize(u) + 1usize] {
            let v = g.edges[cursor[usize(u)]].to
            cursor[usize(u)] += 1usize
            stack[depth] = v
            depth += 1usize
        } else {
            out[written] = u
            written += 1usize
            depth -= 1usize
        }
    }
    if written != m + 1usize { ret (zero, NotEulerian) }
    // The circuit was collected in reverse.
    var lo = 0usize
    var hi = written
    while lo + 1usize < hi {
        hi -= 1usize
        let swap = out[lo]
        out[lo] = out[hi]
        out[hi] = swap
        lo += 1usize
    }
    ret (out[..written], ok)
}

// Warshall's transitive closure: `reach[i * n + j] = 1` when `j` is reachable
// from `i` (every node reaches itself); `reach.len >= n * n`.
fn transitive_closure[E: type](g: *const graph.Graph[E], reach: []u8) -> err {
    let n = graph.node_count[E](g)
    if reach.len < n * n { ret TooSmall }
    var i = 0usize
    while i < n * n {
        reach[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < n {
        reach[i * n + i] = 1u8
        i += 1usize
    }
    var k = 0usize
    while k < g.edges.len {
        reach[usize(g.edges[k].from) * n + usize(g.edges[k].to)] = 1u8
        k += 1usize
    }
    var via = 0usize
    while via < n {
        i = 0usize
        while i < n {
            if reach[i * n + via] == 1u8 {
                var j = 0usize
                while j < n {
                    if reach[via * n + j] == 1u8 { reach[i * n + j] = 1u8 }
                    j += 1usize
                }
            }
            i += 1usize
        }
        via += 1usize
    }
    ret ok
}
