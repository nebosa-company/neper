// Traversals, components and shortest paths over `e.data.graph`'s CSR adjacency. Every
// order here is fixed by node order and each adjacency list's insertion order, so the
// same graph gives the same answer on every run and every target. Every slice returned
// is the caller's arena's.

use e.mem
use e.data.graph as graph
use e.data.heap as heap

type Traversal = struct { order: []const graph.NodeId, parent: []const graph.NodeId }
type Components = struct { component: []const u32, count: u32 }
type Paths = struct { distance: []const f64, previous: []const graph.NodeId }
error Cycle
error InvalidWeight
error TooLarge

// A parent table with every node unreached (`graph.NONE`) and the start its own parent.
fn fresh_parents(a: *mem.Arena, count: usize, start: graph.NodeId) -> ([]graph.NodeId, err) {
    let (parent, parent_error) = mem.alloc[graph.NodeId](a, count)
    if parent_error != ok { ret (zero, parent_error) }
    var at = 0usize
    while at < count {
        parent[at] = graph.NONE
        at += 1usize
    }
    parent[usize(start)] = start
    ret (parent, ok)
}

fn bfs[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId) -> (Traversal, err) {
    let count = graph.node_count[E](g)
    if usize(start) >= count { ret (zero, graph.InvalidNode) }
    let (parent, parent_error) = fresh_parents(a, count, start)
    if parent_error != ok { ret (zero, parent_error) }
    // The visit order doubles as the queue: what is appended is what is dequeued next.
    let (order, order_error) = mem.alloc[graph.NodeId](a, count)
    if order_error != ok { ret (zero, order_error) }
    var head = 0usize
    var tail = 1usize
    order[0usize] = start
    while head < tail {
        let node = order[head]
        head += 1usize
        let (edges, edges_error) = graph.neighbors[E](g, node)
        if edges_error != ok { ret (zero, edges_error) }
        var it = edges
        while true {
            let (edge, has_edge) = graph.neighbors_next[E](&it)
            if !has_edge { break }
            if parent[usize(edge.to)] == graph.NONE {
                parent[usize(edge.to)] = node
                order[tail] = edge.to
                tail += 1usize
            }
        }
    }
    var result: Traversal = zero
    result.order = order[..tail]
    result.parent = parent[0..]
    ret (result, ok)
}

// Preorder, with an explicit stack of (node, next edge index) so that the order is the
// recursive one -- a node's first unvisited neighbour goes deeper before its second.
fn dfs[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId) -> (Traversal, err) {
    let count = graph.node_count[E](g)
    if usize(start) >= count { ret (zero, graph.InvalidNode) }
    let (parent, parent_error) = fresh_parents(a, count, start)
    if parent_error != ok { ret (zero, parent_error) }
    let (order, order_error) = mem.alloc[graph.NodeId](a, count)
    if order_error != ok { ret (zero, order_error) }
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, count)
    if stack_error != ok { ret (zero, stack_error) }
    let (cursor, cursor_error) = mem.alloc[usize](a, count)
    if cursor_error != ok { ret (zero, cursor_error) }
    var visited = 0usize
    var depth = 1usize
    stack[0usize] = start
    cursor[usize(start)] = 0usize
    order[0usize] = start
    visited = 1usize
    while depth > 0usize {
        let node = stack[depth - 1usize]
        let (edges, edges_error) = graph.neighbors[E](g, node)
        if edges_error != ok { ret (zero, edges_error) }
        var it = edges
        it.index = cursor[usize(node)]
        var descended = false
        while true {
            let (edge, has_edge) = graph.neighbors_next[E](&it)
            if !has_edge { break }
            if parent[usize(edge.to)] == graph.NONE {
                parent[usize(edge.to)] = node
                order[visited] = edge.to
                visited += 1usize
                cursor[usize(node)] = it.index
                cursor[usize(edge.to)] = 0usize
                stack[depth] = edge.to
                depth += 1usize
                descended = true
                break
            }
        }
        if !descended { depth -= 1usize }
    }
    var result: Traversal = zero
    result.order = order[..visited]
    result.parent = parent[0..]
    ret (result, ok)
}

// Kahn's algorithm with the smallest available node first, by a min-heap of the
// ready nodes; a leftover node means a cycle, and then nothing is returned.
fn topological[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err) {
    let count = graph.node_count[E](g)
    let (indegree, indegree_error) = mem.alloc[usize](a, count)
    if indegree_error != ok { ret (zero, indegree_error) }
    var at = 0usize
    while at < count {
        indegree[at] = 0usize
        at += 1usize
    }
    at = 0usize
    while at < g.edges.len {
        indegree[usize(g.edges[at].to)] += 1usize
        at += 1usize
    }
    let (ready_heap, heap_error) = heap.init[u32](a, count)
    if heap_error != ok { ret (zero, heap_error) }
    var ready = ready_heap
    at = 0usize
    while at < count {
        if indegree[at] == 0usize {
            let push_error = heap.push[u32](&ready, u32(at))
            if push_error != ok { ret (zero, push_error) }
        }
        at += 1usize
    }
    let (order, order_error) = mem.alloc[graph.NodeId](a, count)
    if order_error != ok { ret (zero, order_error) }
    var placed = 0usize
    while true {
        let (node, has_node) = heap.pop[u32](&ready)
        if !has_node { break }
        order[placed] = node
        placed += 1usize
        let (edges, edges_error) = graph.neighbors[E](g, node)
        if edges_error != ok { ret (zero, edges_error) }
        var it = edges
        while true {
            let (edge, has_edge) = graph.neighbors_next[E](&it)
            if !has_edge { break }
            indegree[usize(edge.to)] -= 1usize
            if indegree[usize(edge.to)] == 0usize {
                let push_error = heap.push[u32](&ready, edge.to)
                if push_error != ok { ret (zero, push_error) }
            }
        }
    }
    if placed != count { ret (zero, Cycle) }
    ret (order[0..], ok)
}

// Components of the graph with every edge read both ways, numbered by their smallest
// node: a scan in node order, flooding from each node not yet placed.
fn weak_components[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (Components, err) {
    let count = graph.node_count[E](g)
    if count > 4294967295usize { ret (zero, TooLarge) }
    // Reverse adjacency, so that an edge is followed from either end.
    let (reverse_offsets, offsets_error) = mem.alloc[usize](a, count + 1usize)
    if offsets_error != ok { ret (zero, offsets_error) }
    let (reverse, reverse_error) = mem.alloc[graph.NodeId](a, g.edges.len)
    if reverse_error != ok { ret (zero, reverse_error) }
    build_reverse[E](g, reverse_offsets, reverse)
    let (component, component_error) = mem.alloc[u32](a, count)
    if component_error != ok { ret (zero, component_error) }
    var at = 0usize
    while at < count {
        component[at] = 4294967295u32
        at += 1usize
    }
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, count)
    if stack_error != ok { ret (zero, stack_error) }
    var next_id = 0u32
    at = 0usize
    while at < count {
        if component[at] == 4294967295u32 {
            let id = next_id
            next_id += 1u32
            component[at] = id
            var depth = 1usize
            stack[0usize] = u32(at)
            while depth > 0usize {
                depth -= 1usize
                let node = stack[depth]
                var e = g.offsets[usize(node)]
                while e < g.offsets[usize(node) + 1usize] {
                    let to = g.edges[e].to
                    if component[usize(to)] == 4294967295u32 {
                        component[usize(to)] = id
                        stack[depth] = to
                        depth += 1usize
                    }
                    e += 1usize
                }
                e = reverse_offsets[usize(node)]
                while e < reverse_offsets[usize(node) + 1usize] {
                    let from = reverse[e]
                    if component[usize(from)] == 4294967295u32 {
                        component[usize(from)] = id
                        stack[depth] = from
                        depth += 1usize
                    }
                    e += 1usize
                }
            }
        }
        at += 1usize
    }
    var result: Components = zero
    result.component = component[0..]
    result.count = next_id
    ret (result, ok)
}

// The transpose in CSR form: `reverse[reverse_offsets[n] .. reverse_offsets[n + 1]]`
// are the sources of the edges into `n`.
fn build_reverse[E: type](g: *const graph.Graph[E], reverse_offsets: []usize, reverse: []graph.NodeId) {
    let count = graph.node_count[E](g)
    var at = 0usize
    while at <= count {
        reverse_offsets[at] = 0usize
        at += 1usize
    }
    at = 0usize
    while at < g.edges.len {
        reverse_offsets[usize(g.edges[at].to) + 1usize] += 1usize
        at += 1usize
    }
    at = 1usize
    while at <= count {
        reverse_offsets[at] += reverse_offsets[at - 1usize]
        at += 1usize
    }
    // Place each edge at its target's cursor, `reverse_offsets[to]` serving as the cursor;
    // afterwards every offset has moved up to the next node's start, so shift them back.
    at = 0usize
    while at < g.edges.len {
        let to = usize(g.edges[at].to)
        reverse[reverse_offsets[to]] = g.edges[at].from
        reverse_offsets[to] += 1usize
        at += 1usize
    }
    at = count
    while at > 0usize {
        reverse_offsets[at] = reverse_offsets[at - 1usize]
        at -= 1usize
    }
    reverse_offsets[0usize] = 0usize
}

// Kosaraju: a finishing order over the graph, then a flood over the transpose in
// reverse finishing order, with each component renumbered by its smallest node so the
// identifiers are the ones the surface promises.
fn strong_components[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (Components, err) {
    let count = graph.node_count[E](g)
    if count > 4294967295usize { ret (zero, TooLarge) }
    let (reverse_offsets, offsets_error) = mem.alloc[usize](a, count + 1usize)
    if offsets_error != ok { ret (zero, offsets_error) }
    let (reverse, reverse_error) = mem.alloc[graph.NodeId](a, g.edges.len)
    if reverse_error != ok { ret (zero, reverse_error) }
    build_reverse[E](g, reverse_offsets, reverse)
    let (seen, seen_error) = mem.alloc[bool](a, count)
    if seen_error != ok { ret (zero, seen_error) }
    let (finished, finished_error) = mem.alloc[graph.NodeId](a, count)
    if finished_error != ok { ret (zero, finished_error) }
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, count)
    if stack_error != ok { ret (zero, stack_error) }
    let (cursor, cursor_error) = mem.alloc[usize](a, count)
    if cursor_error != ok { ret (zero, cursor_error) }
    var at = 0usize
    while at < count {
        seen[at] = false
        at += 1usize
    }
    // Pass one: iterative DFS over the forward graph, recording nodes as they finish.
    var finished_count = 0usize
    at = 0usize
    while at < count {
        if !seen[at] {
            seen[at] = true
            var depth = 1usize
            stack[0usize] = u32(at)
            cursor[at] = g.offsets[at]
            while depth > 0usize {
                let node = stack[depth - 1usize]
                var descended = false
                while cursor[usize(node)] < g.offsets[usize(node) + 1usize] {
                    let to = g.edges[cursor[usize(node)]].to
                    cursor[usize(node)] += 1usize
                    if !seen[usize(to)] {
                        seen[usize(to)] = true
                        cursor[usize(to)] = g.offsets[usize(to)]
                        stack[depth] = to
                        depth += 1usize
                        descended = true
                        break
                    }
                }
                if !descended {
                    finished[finished_count] = node
                    finished_count += 1usize
                    depth -= 1usize
                }
            }
        }
        at += 1usize
    }
    // Pass two: flood the transpose from the latest-finished node not yet placed.
    let (component, component_error) = mem.alloc[u32](a, count)
    if component_error != ok { ret (zero, component_error) }
    at = 0usize
    while at < count {
        component[at] = 4294967295u32
        at += 1usize
    }
    var next_id = 0u32
    var f = finished_count
    while f > 0usize {
        f -= 1usize
        let root = finished[f]
        if component[usize(root)] == 4294967295u32 {
            let id = next_id
            next_id += 1u32
            component[usize(root)] = id
            var depth = 1usize
            stack[0usize] = root
            while depth > 0usize {
                depth -= 1usize
                let node = stack[depth]
                var e = reverse_offsets[usize(node)]
                while e < reverse_offsets[usize(node) + 1usize] {
                    let from = reverse[e]
                    if component[usize(from)] == 4294967295u32 {
                        component[usize(from)] = id
                        stack[depth] = from
                        depth += 1usize
                    }
                    e += 1usize
                }
            }
        }
    }
    // Renumber by smallest node: the first node seen with a given raw id fixes its number.
    let (renumber, renumber_error) = mem.alloc[u32](a, usize(next_id))
    if renumber_error != ok { ret (zero, renumber_error) }
    at = 0usize
    while at < usize(next_id) {
        renumber[at] = 4294967295u32
        at += 1usize
    }
    var assigned = 0u32
    at = 0usize
    while at < count {
        let raw = component[at]
        if renumber[usize(raw)] == 4294967295u32 {
            renumber[usize(raw)] = assigned
            assigned += 1u32
        }
        component[at] = renumber[usize(raw)]
        at += 1usize
    }
    var result: Components = zero
    result.component = component[0..]
    result.count = next_id
    ret (result, ok)
}

type Entry = struct { distance: f64, node: graph.NodeId }

fn entry_cmp(ctx: *u8, x: Entry, y: Entry) -> i32 {
    if x.distance < y.distance { ret -1i32 }
    if x.distance > y.distance { ret 1i32 }
    if x.node < y.node { ret -1i32 }
    if x.node > y.node { ret 1i32 }
    ret 0i32
}

fn dijkstra[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Paths, err) {
    let count = graph.node_count[E](g)
    if usize(start) >= count { ret (zero, graph.InvalidNode) }
    let (distance, distance_error) = mem.alloc[f64](a, count)
    if distance_error != ok { ret (zero, distance_error) }
    let (previous, previous_error) = mem.alloc[graph.NodeId](a, count)
    if previous_error != ok { ret (zero, previous_error) }
    let (settled, settled_error) = mem.alloc[bool](a, count)
    if settled_error != ok { ret (zero, settled_error) }
    let infinity = mem.bitcast[f64](9218868437227405312u64)
    var at = 0usize
    while at < count {
        distance[at] = infinity
        previous[at] = graph.NONE
        settled[at] = false
        at += 1usize
    }
    distance[usize(start)] = 0.0
    var tie = 0u8
    let (initial_queue, queue_error) = heap.init_by[Entry, u8](a, count, &tie, entry_cmp)
    if queue_error != ok { ret (zero, queue_error) }
    var queue = initial_queue
    let seed_error = heap.push_by[Entry, u8](&queue, Entry { distance: 0.0, node: start })
    if seed_error != ok { ret (zero, seed_error) }
    while true {
        let (entry, has_entry) = heap.pop_by[Entry, u8](&queue)
        if !has_entry { break }
        if !settled[usize(entry.node)] {
            settled[usize(entry.node)] = true
            let (edges, edges_error) = graph.neighbors[E](g, entry.node)
            if edges_error != ok { ret (zero, edges_error) }
            var it = edges
            while true {
                let (edge, has_edge) = graph.neighbors_next[E](&it)
                if !has_edge { break }
                let w = weight(ctx, edge)
                if !(w >= 0.0) || w == infinity { ret (zero, InvalidWeight) }
                let candidate = entry.distance + w
                if candidate < distance[usize(edge.to)] {
                    distance[usize(edge.to)] = candidate
                    previous[usize(edge.to)] = entry.node
                    let push_error = heap.push_by[Entry, u8](&queue, Entry { distance: candidate, node: edge.to })
                    if push_error != ok { ret (zero, push_error) }
                }
            }
        }
    }
    var result: Paths = zero
    result.distance = distance[0..]
    result.previous = previous[0..]
    ret (result, ok)
}

// ---- The plan's remaining routines: more shortest paths, spanning structures,
// low-link connectivity, Eulerian walks, reachability and the density measures.
// Undirected graphs are those built with `add_undirected` (every edge in both
// adjacency lists), and the MST, low-link and density routines assume that form and
// a simple graph. `Forest.edges` are indices into `g.edges` of the from < to copy,
// written into the caller's `chosen`.

type Forest = struct { edges: []const usize, weight: f64, trees: usize }
type WeightedEdge = struct { weight: f64, index: usize }
type LowLinks = struct { disc: []u32, low: []u32, is_bridge: []u8, is_cut: []u8, time: u32 }
error NegativeCycle
error NoPath
error NoArborescence
error NotEulerian
error Disconnected
error TooSmall

// The distance of an unreached node.
fn unreached() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

// The path `start .. goal` implied by a predecessor table; `NoPath` when `goal` was
// not reached.
fn path_to(a: *mem.Arena, previous: []const graph.NodeId, start: graph.NodeId, goal: graph.NodeId) -> ([]const graph.NodeId, err) {
    if usize(goal) >= previous.len || usize(start) >= previous.len { ret (zero, graph.InvalidNode) }
    var length = 1usize
    var node = goal
    while node != start {
        node = previous[usize(node)]
        if node == graph.NONE || length >= previous.len { ret (zero, NoPath) }
        length += 1usize
    }
    let (out, out_error) = mem.alloc[graph.NodeId](a, length)
    if out_error != ok { ret (zero, out_error) }
    node = goal
    var i = length
    while i > 0usize {
        i -= 1usize
        out[i] = node
        node = previous[usize(node)]
    }
    ret (out[0..], ok)
}

// Bellman-Ford from `start`, edges in any sign; `NegativeCycle` when a round of
// relaxation still improves after `n - 1` rounds.
fn bellman_ford[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Paths, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n { ret (zero, graph.InvalidNode) }
    let (distance, distance_error) = mem.alloc[f64](a, n)
    if distance_error != ok { ret (zero, distance_error) }
    let (previous, previous_error) = mem.alloc[graph.NodeId](a, n)
    if previous_error != ok { ret (zero, previous_error) }
    var i = 0usize
    while i < n {
        distance[i] = unreached()
        previous[i] = graph.NONE
        i += 1usize
    }
    distance[usize(start)] = 0.0
    var round = 0usize
    while round < n {
        var relaxed = false
        var k = 0usize
        while k < g.edges.len {
            let e = g.edges[k]
            if distance[usize(e.from)] < unreached() {
                let candidate = distance[usize(e.from)] + weight(ctx, e)
                if candidate < distance[usize(e.to)] {
                    distance[usize(e.to)] = candidate
                    previous[usize(e.to)] = e.from
                    relaxed = true
                }
            }
            k += 1usize
        }
        if !relaxed { break }
        if round == n - 1usize { ret (zero, NegativeCycle) }
        round += 1usize
    }
    ret (Paths { distance: distance[0..], previous: previous[0..] }, ok)
}

// Floyd-Warshall: the `n x n` row-major distance matrix, `unreached()` where there
// is no path; `NegativeCycle` when a diagonal entry ends up negative.
fn floyd_warshall[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> ([]f64, err) {
    let n = graph.node_count[E](g)
    let (d, d_error) = mem.alloc[f64](a, n * n)
    if d_error != ok { ret (zero, d_error) }
    var i = 0usize
    while i < n * n {
        d[i] = unreached()
        i += 1usize
    }
    i = 0usize
    while i < n {
        d[i * n + i] = 0.0
        i += 1usize
    }
    var k = 0usize
    while k < g.edges.len {
        let e = g.edges[k]
        let w = weight(ctx, e)
        if w < d[usize(e.from) * n + usize(e.to)] { d[usize(e.from) * n + usize(e.to)] = w }
        k += 1usize
    }
    var via = 0usize
    while via < n {
        i = 0usize
        while i < n {
            if d[i * n + via] < unreached() {
                var j = 0usize
                while j < n {
                    let candidate = d[i * n + via] + d[via * n + j]
                    if candidate < d[i * n + j] { d[i * n + j] = candidate }
                    j += 1usize
                }
            }
            i += 1usize
        }
        via += 1usize
    }
    i = 0usize
    while i < n {
        if d[i * n + i] < 0.0 { ret (zero, NegativeCycle) }
        i += 1usize
    }
    ret (d, ok)
}

// Dijkstra over per-edge weights `w[k]` (all non-negative), filling `distance`;
// the heap is the caller's, cleared first, so an all-pairs caller allocates it once.
fn dijkstra_indexed[E: type](g: *const graph.Graph[E], start: graph.NodeId, w: []const f64, distance: []f64, queue: *heap.HeapBy[Entry, u8]) -> err {
    let n = graph.node_count[E](g)
    var i = 0usize
    while i < n {
        distance[i] = unreached()
        i += 1usize
    }
    distance[usize(start)] = 0.0
    heap.clear_by[Entry, u8](queue)
    let seed_error = heap.push_by[Entry, u8](queue, Entry { distance: 0.0, node: start })
    if seed_error != ok { ret seed_error }
    while true {
        let (entry, has_entry) = heap.pop_by[Entry, u8](queue)
        if !has_entry { break }
        // A stale entry: the node was settled by a cheaper one.
        if entry.distance > distance[usize(entry.node)] { continue }
        var k = g.offsets[usize(entry.node)]
        while k < g.offsets[usize(entry.node) + 1usize] {
            let to = usize(g.edges[k].to)
            let candidate = entry.distance + w[k]
            if candidate < distance[to] {
                distance[to] = candidate
                let push_error = heap.push_by[Entry, u8](queue, Entry { distance: candidate, node: g.edges[k].to })
                if push_error != ok { ret push_error }
            }
            k += 1usize
        }
    }
    ret ok
}

// Johnson: all-pairs distances with negative edges, by Bellman-Ford potentials from a
// virtual source (every node starts at 0) and then Dijkstra from every node over the
// reweighted edges. The `n x n` matrix, as `floyd_warshall` answers it.
fn johnson[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> ([]f64, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    let (h, h_error) = mem.alloc[f64](a, n)
    if h_error != ok { ret (zero, h_error) }
    var i = 0usize
    while i < n {
        h[i] = 0.0
        i += 1usize
    }
    var round = 0usize
    while round < n {
        var relaxed = false
        var k = 0usize
        while k < m {
            let e = g.edges[k]
            let candidate = h[usize(e.from)] + weight(ctx, e)
            if candidate < h[usize(e.to)] {
                h[usize(e.to)] = candidate
                relaxed = true
            }
            k += 1usize
        }
        if !relaxed { break }
        if round == n - 1usize { ret (zero, NegativeCycle) }
        round += 1usize
    }
    let (w, w_error) = mem.alloc[f64](a, m)
    if w_error != ok { ret (zero, w_error) }
    var k = 0usize
    while k < m {
        let e = g.edges[k]
        w[k] = weight(ctx, e) + h[usize(e.from)] - h[usize(e.to)]
        k += 1usize
    }
    let (d, d_error) = mem.alloc[f64](a, n * n)
    if d_error != ok { ret (zero, d_error) }
    var tie = 0u8
    let (queue0, queue_error) = heap.init_by[Entry, u8](a, m + 1usize, &tie, entry_cmp)
    if queue_error != ok { ret (zero, queue_error) }
    var queue = queue0
    var s = 0usize
    while s < n {
        let row_error = dijkstra_indexed[E](g, u32(s), w[0..], d[s * n..(s + 1usize) * n], &queue)
        if row_error != ok { ret (zero, row_error) }
        var j = 0usize
        while j < n {
            if d[s * n + j] < unreached() { d[s * n + j] = d[s * n + j] - h[s] + h[j] }
            j += 1usize
        }
        s += 1usize
    }
    ret (d, ok)
}

// Dial's algorithm for non-negative integer weights at most `max_weight`: buckets
// indexed by distance modulo `max_weight + 1` replace the heap, each bucket a list
// threaded through `link`. Unreached nodes answer `usize` max.
fn dial[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, max_weight: usize, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> usize) -> ([]usize, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n { ret (zero, graph.InvalidNode) }
    let (distance, distance_error) = mem.alloc[usize](a, n)
    if distance_error != ok { ret (zero, distance_error) }
    let buckets = max_weight + 1usize
    let (head, head_error) = mem.alloc[u32](a, buckets)
    if head_error != ok { ret (zero, head_error) }
    let (link, link_error) = mem.alloc[u32](a, n)
    if link_error != ok { ret (zero, link_error) }
    let none = 18446744073709551615usize
    var i = 0usize
    while i < n {
        distance[i] = none
        i += 1usize
    }
    i = 0usize
    while i < buckets {
        head[i] = graph.NONE
        i += 1usize
    }
    distance[usize(start)] = 0usize
    link[usize(start)] = graph.NONE
    head[0usize] = start
    var current = 0usize
    var remaining = 1usize
    while remaining > 0usize {
        let bucket = current % buckets
        while head[bucket] != graph.NONE {
            let u = head[bucket]
            head[bucket] = link[usize(u)]
            remaining -= 1usize
            if distance[usize(u)] != current { continue }
            var k = g.offsets[usize(u)]
            while k < g.offsets[usize(u) + 1usize] {
                let e = g.edges[k]
                let w = weight(ctx, e)
                if w > max_weight { ret (zero, InvalidWeight) }
                let candidate = current + w
                if candidate < distance[usize(e.to)] {
                    distance[usize(e.to)] = candidate
                    let slot = candidate % buckets
                    link[usize(e.to)] = head[slot]
                    head[slot] = e.to
                    remaining += 1usize
                }
                k += 1usize
            }
        }
        current += 1usize
    }
    ret (distance, ok)
}

// The radix-heap bucket of `key` relative to the last extracted `last`: the position of
// the highest differing bit, 0 when equal.
fn bucket_of(key: u32, last: u32) -> usize {
    var x = key ^ last
    var b = 0usize
    while x != 0u32 {
        x = x >> 1u32
        b += 1usize
    }
    ret b
}

// Dijkstra over `u32` weights with a radix heap: 33 buckets keyed by the highest bit
// in which an entry differs from the last extracted distance, so that a pop only
// redistributes the first non-empty bucket. Every relaxation makes one entry, so
// `m + 1` entries suffice; a stale entry is dropped when popped. Unreached nodes
// answer `graph.NONE`.
fn dijkstra_radix_heap[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> u32) -> ([]u32, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n { ret (zero, graph.InvalidNode) }
    let (distance, distance_error) = mem.alloc[u32](a, n)
    if distance_error != ok { ret (zero, distance_error) }
    let entries = g.edges.len + 1usize
    let (key, key_error) = mem.alloc[u32](a, entries)
    if key_error != ok { ret (zero, key_error) }
    let (node, node_error) = mem.alloc[graph.NodeId](a, entries)
    if node_error != ok { ret (zero, node_error) }
    let (link, link_error) = mem.alloc[u32](a, entries)
    if link_error != ok { ret (zero, link_error) }
    var head: [33]u32 = zero
    var b = 0usize
    while b < 33usize {
        head[b] = graph.NONE
        b += 1usize
    }
    var i = 0usize
    while i < n {
        distance[i] = graph.NONE
        i += 1usize
    }
    distance[usize(start)] = 0u32
    key[0usize] = 0u32
    node[0usize] = start
    link[0usize] = graph.NONE
    head[0usize] = 0u32
    var used = 1usize
    var last = 0u32
    var remaining = 1usize
    while remaining > 0usize {
        if head[0usize] == graph.NONE {
            // The first non-empty bucket's minimum becomes `last`; its entries then all
            // land in lower buckets, the minimum ones in bucket 0.
            var bucket = 1usize
            while head[bucket] == graph.NONE { bucket += 1usize }
            var smallest = 4294967295u32
            var e = head[bucket]
            while e != graph.NONE {
                if key[usize(e)] < smallest { smallest = key[usize(e)] }
                e = link[usize(e)]
            }
            last = smallest
            e = head[bucket]
            head[bucket] = graph.NONE
            while e != graph.NONE {
                let following = link[usize(e)]
                let slot = bucket_of(key[usize(e)], last)
                link[usize(e)] = head[slot]
                head[slot] = e
                e = following
            }
        }
        let top = usize(head[0usize])
        head[0usize] = link[top]
        remaining -= 1usize
        if key[top] != distance[usize(node[top])] { continue }
        let u = usize(node[top])
        var k = g.offsets[u]
        while k < g.offsets[u + 1usize] {
            let candidate = u64(last) + u64(weight(ctx, g.edges[k]))
            if candidate >= u64(graph.NONE) { ret (zero, TooLarge) }
            let to = usize(g.edges[k].to)
            if u32(candidate) < distance[to] {
                distance[to] = u32(candidate)
                key[used] = u32(candidate)
                node[used] = g.edges[k].to
                let slot = bucket_of(u32(candidate), last)
                link[used] = head[slot]
                head[slot] = u32(used)
                used += 1usize
                remaining += 1usize
            }
            k += 1usize
        }
    }
    ret (distance, ok)
}

// Hop counts from `start` into `level` (`graph.NONE` where unreached), answering the
// largest, or `graph.NONE` when some node was not reached; `queue` is scratch of `n`.
fn bfs_levels[E: type](g: *const graph.Graph[E], start: graph.NodeId, level: []u32, queue: []graph.NodeId) -> u32 {
    let n = graph.node_count[E](g)
    var i = 0usize
    while i < n {
        level[i] = graph.NONE
        i += 1usize
    }
    level[usize(start)] = 0u32
    queue[0usize] = start
    var head = 0usize
    var tail = 1usize
    var farthest = 0u32
    while head < tail {
        let u = queue[head]
        head += 1usize
        var k = g.offsets[usize(u)]
        while k < g.offsets[usize(u) + 1usize] {
            let to = usize(g.edges[k].to)
            if level[to] == graph.NONE {
                level[to] = level[usize(u)] + 1u32
                farthest = level[to]
                queue[tail] = g.edges[k].to
                tail += 1usize
            }
            k += 1usize
        }
    }
    if tail < n { ret graph.NONE }
    ret farthest
}

// Every node's eccentricity in hops (a breadth-first search from each), or
// `Disconnected` when some node cannot reach every other.
fn eccentricities[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]u32, err) {
    let n = graph.node_count[E](g)
    let (ecc, ecc_error) = mem.alloc[u32](a, n)
    if ecc_error != ok { ret (zero, ecc_error) }
    let (level, level_error) = mem.alloc[u32](a, n)
    if level_error != ok { ret (zero, level_error) }
    let (queue, queue_error) = mem.alloc[graph.NodeId](a, n)
    if queue_error != ok { ret (zero, queue_error) }
    var s = 0usize
    while s < n {
        let farthest = bfs_levels[E](g, u32(s), level, queue)
        if farthest == graph.NONE { ret (zero, Disconnected) }
        ecc[s] = farthest
        s += 1usize
    }
    ret (ecc, ok)
}

// The nodes of least eccentricity, in node order.
fn center[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err) {
    let (ecc, ecc_error) = eccentricities[E](a, g)
    if ecc_error != ok { ret (zero, ecc_error) }
    var radius = graph.NONE
    var found = 0usize
    var i = 0usize
    while i < ecc.len {
        if ecc[i] < radius {
            radius = ecc[i]
            found = 0usize
        }
        if ecc[i] == radius { found += 1usize }
        i += 1usize
    }
    let (out, out_error) = mem.alloc[graph.NodeId](a, found)
    if out_error != ok { ret (zero, out_error) }
    var placed = 0usize
    i = 0usize
    while i < ecc.len {
        if ecc[i] == radius {
            out[placed] = u32(i)
            placed += 1usize
        }
        i += 1usize
    }
    ret (out[0..], ok)
}

// The largest eccentricity, in hops.
fn diameter[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (u32, err) {
    let (ecc, ecc_error) = eccentricities[E](a, g)
    if ecc_error != ok { ret (0u32, ecc_error) }
    var widest = 0u32
    var i = 0usize
    while i < ecc.len {
        if ecc[i] > widest { widest = ecc[i] }
        i += 1usize
    }
    ret (widest, ok)
}

// Triangles of a simple undirected graph by the forward algorithm: nodes ranked by
// (degree, id), and for each edge to a higher-ranked neighbour the already-ranked
// neighbours the two ends share are counted.
fn count_triangles[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (u64, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    // Counting sort by degree gives each node its rank and the nodes in rank order.
    let (bins, bins_error) = mem.alloc[usize](a, m + 2usize)
    if bins_error != ok { ret (0u64, bins_error) }
    let (rank, rank_error) = mem.alloc[u32](a, n)
    if rank_error != ok { ret (0u64, rank_error) }
    let (order, order_error) = mem.alloc[graph.NodeId](a, n)
    if order_error != ok { ret (0u64, order_error) }
    var i = 0usize
    while i < m + 2usize {
        bins[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        bins[g.offsets[i + 1usize] - g.offsets[i] + 1usize] += 1usize
        i += 1usize
    }
    i = 1usize
    while i < m + 2usize {
        bins[i] += bins[i - 1usize]
        i += 1usize
    }
    i = 0usize
    while i < n {
        let degree = g.offsets[i + 1usize] - g.offsets[i]
        rank[i] = u32(bins[degree])
        order[bins[degree]] = u32(i)
        bins[degree] += 1usize
        i += 1usize
    }
    // `seen[offsets[v] .. offsets[v] + seen_count[v]]` are v's lower-ranked neighbours
    // processed so far; `mark[x] == v` says x is among v's while v is being processed.
    let (seen, seen_error) = mem.alloc[graph.NodeId](a, m)
    if seen_error != ok { ret (0u64, seen_error) }
    let (seen_count, seen_count_error) = mem.alloc[usize](a, n)
    if seen_count_error != ok { ret (0u64, seen_count_error) }
    let (mark, mark_error) = mem.alloc[u32](a, n)
    if mark_error != ok { ret (0u64, mark_error) }
    i = 0usize
    while i < n {
        seen_count[i] = 0usize
        mark[i] = graph.NONE
        i += 1usize
    }
    var total = 0u64
    var p = 0usize
    while p < n {
        let v = usize(order[p])
        var j = 0usize
        while j < seen_count[v] {
            mark[usize(seen[g.offsets[v] + j])] = u32(v)
            j += 1usize
        }
        var k = g.offsets[v]
        while k < g.offsets[v + 1usize] {
            let u = usize(g.edges[k].to)
            if rank[u] > rank[v] {
                var q = 0usize
                while q < seen_count[u] {
                    if mark[usize(seen[g.offsets[u] + q])] == u32(v) { total += 1u64 }
                    q += 1usize
                }
                seen[g.offsets[u] + seen_count[u]] = u32(v)
                seen_count[u] += 1usize
            }
            k += 1usize
        }
        p += 1usize
    }
    ret (total, ok)
}

// Core numbers of a simple undirected graph by Batagelj-Zaversnik peeling: nodes
// bin-sorted by degree, the least-degree node fixed and its neighbours moved down a
// bin, in `O(m)`. `core[v]` is the largest k whose k-core holds v.
fn k_core[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]u32, err) {
    let n = graph.node_count[E](g)
    let (degree, degree_error) = mem.alloc[usize](a, n)
    if degree_error != ok { ret (zero, degree_error) }
    var top = 0usize
    var i = 0usize
    while i < n {
        degree[i] = g.offsets[i + 1usize] - g.offsets[i]
        if degree[i] > top { top = degree[i] }
        i += 1usize
    }
    let (bins, bins_error) = mem.alloc[usize](a, top + 1usize)
    if bins_error != ok { ret (zero, bins_error) }
    let (position, position_error) = mem.alloc[usize](a, n)
    if position_error != ok { ret (zero, position_error) }
    let (vert, vert_error) = mem.alloc[graph.NodeId](a, n)
    if vert_error != ok { ret (zero, vert_error) }
    i = 0usize
    while i <= top {
        bins[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        bins[degree[i]] += 1usize
        i += 1usize
    }
    var begin = 0usize
    i = 0usize
    while i <= top {
        let width = bins[i]
        bins[i] = begin
        begin += width
        i += 1usize
    }
    i = 0usize
    while i < n {
        position[i] = bins[degree[i]]
        vert[position[i]] = u32(i)
        bins[degree[i]] += 1usize
        i += 1usize
    }
    i = top
    while i > 0usize {
        bins[i] = bins[i - 1usize]
        i -= 1usize
    }
    bins[0usize] = 0usize
    i = 0usize
    while i < n {
        let v = usize(vert[i])
        var k = g.offsets[v]
        while k < g.offsets[v + 1usize] {
            let u = usize(g.edges[k].to)
            if degree[u] > degree[v] {
                // Swap u to the front of its bin, then shrink the bin from the front.
                let du = degree[u]
                let pu = position[u]
                let pw = bins[du]
                let w = usize(vert[pw])
                if u != w {
                    position[u] = pw
                    vert[pu] = u32(w)
                    position[w] = pu
                    vert[pw] = u32(u)
                }
                bins[du] += 1usize
                degree[u] -= 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    let (core, core_error) = mem.alloc[u32](a, n)
    if core_error != ok { ret (zero, core_error) }
    i = 0usize
    while i < n {
        core[i] = u32(degree[i])
        i += 1usize
    }
    ret (core, ok)
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

// The k-truss of a simple undirected graph: `alive[k] = 1` (both copies) for the edges
// left after peeling every edge in fewer than `k - 2` triangles, the supports of the
// triangles it closed dropping as it goes.
// ponytail: every removal rescans the two adjacency lists and looks up twins, O(degree)
// per triangle; a support-sorted bin order would make it O(m^1.5).
fn k_truss[E: type](a: *mem.Arena, g: *const graph.Graph[E], k: u32) -> ([]u8, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    let (alive, alive_error) = mem.alloc[u8](a, m)
    if alive_error != ok { ret (zero, alive_error) }
    let (canon, canon_error) = mem.alloc[usize](a, m)
    if canon_error != ok { ret (zero, canon_error) }
    let (support, support_error) = mem.alloc[u32](a, m)
    if support_error != ok { ret (zero, support_error) }
    let (mark, mark_error) = mem.alloc[u32](a, n)
    if mark_error != ok { ret (zero, mark_error) }
    let (mark_edge, mark_edge_error) = mem.alloc[usize](a, n)
    if mark_edge_error != ok { ret (zero, mark_edge_error) }
    var i = 0usize
    while i < n {
        mark[i] = 0u32
        i += 1usize
    }
    i = 0usize
    while i < m {
        alive[i] = 1u8
        support[i] = 0u32
        canon[i] = i
        if g.edges[i].from > g.edges[i].to { canon[i] = twin[E](g, i) }
        i += 1usize
    }
    var stamp = 0u32
    i = 0usize
    while i < m {
        let e = g.edges[i]
        if e.from < e.to {
            stamp += 1u32
            var j = g.offsets[usize(e.from)]
            while j < g.offsets[usize(e.from) + 1usize] {
                mark[usize(g.edges[j].to)] = stamp
                j += 1usize
            }
            j = g.offsets[usize(e.to)]
            while j < g.offsets[usize(e.to) + 1usize] {
                if mark[usize(g.edges[j].to)] == stamp { support[i] += 1u32 }
                j += 1usize
            }
        }
        i += 1usize
    }
    var changed = true
    while changed {
        changed = false
        i = 0usize
        while i < m {
            let e = g.edges[i]
            if alive[i] == 1u8 && e.from < e.to && support[i] + 2u32 < k {
                alive[i] = 0u8
                alive[twin[E](g, i)] = 0u8
                stamp += 1u32
                var j = g.offsets[usize(e.from)]
                while j < g.offsets[usize(e.from) + 1usize] {
                    if alive[j] == 1u8 {
                        mark[usize(g.edges[j].to)] = stamp
                        mark_edge[usize(g.edges[j].to)] = j
                    }
                    j += 1usize
                }
                j = g.offsets[usize(e.to)]
                while j < g.offsets[usize(e.to) + 1usize] {
                    let w = usize(g.edges[j].to)
                    if alive[j] == 1u8 && mark[w] == stamp {
                        support[canon[j]] -= 1u32
                        support[canon[mark_edge[w]]] -= 1u32
                    }
                    j += 1usize
                }
                changed = true
            }
            i += 1usize
        }
    }
    ret (alive, ok)
}

// Bron-Kerbosch with pivoting over `members`, which holds the candidates P in
// `members[..p_count]` and the excluded X after them; a processed candidate is swapped
// to the boundary, which moves it from P to X in place. Children take their sets from
// `scratch`. Answers how many cliques were reported.
fn clique_search[Ctx: type](ctx: *Ctx, visit: fn(*Ctx, []const graph.NodeId), adj: []const u8, n: usize, r: []graph.NodeId, depth: usize, members: []graph.NodeId, p_count: usize, scratch: []graph.NodeId) -> usize {
    if p_count == 0usize {
        if members.len == 0usize {
            visit(ctx, r[..depth])
            ret 1usize
        }
        ret 0usize
    }
    // The pivot: the node of P or X with the most neighbours in P.
    var pivot = 0usize
    var best = 0usize
    var i = 0usize
    while i < members.len {
        var c = 0usize
        var j = 0usize
        while j < p_count {
            if adj[usize(members[i]) * n + usize(members[j])] == 1u8 { c += 1usize }
            j += 1usize
        }
        if i == 0usize || c > best {
            best = c
            pivot = usize(members[i])
        }
        i += 1usize
    }
    var remaining = p_count
    var total = 0usize
    i = 0usize
    while i < remaining {
        let v = usize(members[i])
        if adj[pivot * n + v] == 1u8 {
            i += 1usize
            continue
        }
        var child_p = 0usize
        var j = 0usize
        while j < remaining {
            if j != i && adj[v * n + usize(members[j])] == 1u8 {
                scratch[child_p] = members[j]
                child_p += 1usize
            }
            j += 1usize
        }
        var child_total = child_p
        j = remaining
        while j < members.len {
            if adj[v * n + usize(members[j])] == 1u8 {
                scratch[child_total] = members[j]
                child_total += 1usize
            }
            j += 1usize
        }
        r[depth] = u32(v)
        total += clique_search[Ctx](ctx, visit, adj, n, r, depth + 1usize, scratch[..child_total], child_p, scratch[child_total..])
        // v leaves P for X: swap it to P's last slot and shrink P.
        remaining -= 1usize
        members[i] = members[remaining]
        members[remaining] = u32(v)
    }
    ret total
}

// Every maximal clique of a simple undirected graph, each reported once to `visit`
// with its nodes in discovery order; answers the count.
// ponytail: an n x n adjacency matrix and n x n scratch, fine up to a few thousand
// nodes; adjacency bitsets would cut both by 8.
fn max_cliques[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, visit: fn(*Ctx, []const graph.NodeId)) -> (usize, err) {
    let n = graph.node_count[E](g)
    if n == 0usize { ret (0usize, ok) }
    let (adj, adj_error) = mem.alloc[u8](a, n * n)
    if adj_error != ok { ret (0usize, adj_error) }
    var i = 0usize
    while i < n * n {
        adj[i] = 0u8
        i += 1usize
    }
    var k = 0usize
    while k < g.edges.len {
        let e = g.edges[k]
        if e.from != e.to {
            adj[usize(e.from) * n + usize(e.to)] = 1u8
            adj[usize(e.to) * n + usize(e.from)] = 1u8
        }
        k += 1usize
    }
    let (r, r_error) = mem.alloc[graph.NodeId](a, n)
    if r_error != ok { ret (0usize, r_error) }
    let (members, members_error) = mem.alloc[graph.NodeId](a, n)
    if members_error != ok { ret (0usize, members_error) }
    let (scratch, scratch_error) = mem.alloc[graph.NodeId](a, n * n)
    if scratch_error != ok { ret (0usize, scratch_error) }
    i = 0usize
    while i < n {
        members[i] = u32(i)
        i += 1usize
    }
    ret (clique_search[Ctx](ctx, visit, adj[0..], n, r, 0usize, members, n, scratch), ok)
}

// The live supernode `x` now stands in, following contractions without compressing
// them (expansion walks the same chain).
fn find_top(above: []const u32, x: u32) -> u32 {
    var y = x
    while above[usize(y)] != y { y = above[usize(y)] }
    ret y
}

// Chu-Liu/Edmonds: the minimum spanning arborescence rooted at `root`. Every round
// takes each supernode's cheapest incoming edge; a cycle among those is contracted
// into a fresh supernode, its incoming edges reduced by the member's own cheapest
// weight, until the picks form a tree. Contractions then expand last-first: the edge
// entering a supernode fixes which member drops its cycle edge. `chosen` takes the
// `n - 1` edge indices; `NoArborescence` when some node cannot be reached.
fn arborescence[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], root: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, chosen: []usize) -> (Forest, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    if usize(root) >= n { ret (zero, graph.InvalidNode) }
    if chosen.len + 1usize < n { ret (zero, TooSmall) }
    let limit = 2usize * n
    let (w, w_error) = mem.alloc[f64](a, m)
    if w_error != ok { ret (zero, w_error) }
    let (above, above_error) = mem.alloc[u32](a, limit)
    if above_error != ok { ret (zero, above_error) }
    let (in_edge, in_edge_error) = mem.alloc[usize](a, limit)
    if in_edge_error != ok { ret (zero, in_edge_error) }
    let (in_w, in_w_error) = mem.alloc[f64](a, limit)
    if in_w_error != ok { ret (zero, in_w_error) }
    let (visit, visit_error) = mem.alloc[u32](a, limit)
    if visit_error != ok { ret (zero, visit_error) }
    let (cyc, cyc_error) = mem.alloc[u32](a, limit)
    if cyc_error != ok { ret (zero, cyc_error) }
    let (cycle_node, cycle_node_error) = mem.alloc[u32](a, limit)
    if cycle_node_error != ok { ret (zero, cycle_node_error) }
    let (cycle_edge, cycle_edge_error) = mem.alloc[usize](a, limit)
    if cycle_edge_error != ok { ret (zero, cycle_edge_error) }
    let (level_super, level_super_error) = mem.alloc[u32](a, n + 1usize)
    if level_super_error != ok { ret (zero, level_super_error) }
    let (level_start, level_start_error) = mem.alloc[usize](a, n + 1usize)
    if level_start_error != ok { ret (zero, level_start_error) }
    let none = 18446744073709551615usize
    var i = 0usize
    while i < limit {
        above[i] = u32(i)
        visit[i] = graph.NONE
        cyc[i] = graph.NONE
        i += 1usize
    }
    var k = 0usize
    while k < m {
        w[k] = weight(ctx, g.edges[k])
        k += 1usize
    }
    var supers = n
    var levels = 0usize
    var members = 0usize
    while true {
        // The cheapest edge into every live supernode but the root.
        i = 0usize
        while i < supers {
            in_edge[i] = none
            visit[i] = graph.NONE
            i += 1usize
        }
        let r = find_top(above, root)
        k = 0usize
        while k < m {
            let u = find_top(above, g.edges[k].from)
            let v = find_top(above, g.edges[k].to)
            if u != v && v != r && (in_edge[usize(v)] == none || w[k] < in_w[usize(v)]) {
                in_edge[usize(v)] = k
                in_w[usize(v)] = w[k]
            }
            k += 1usize
        }
        i = 0usize
        while i < supers {
            if above[i] == u32(i) && u32(i) != r && in_edge[i] == none { ret (zero, NoArborescence) }
            i += 1usize
        }
        // Walk the picks from every live supernode; a walk that meets itself is a cycle.
        var found = false
        i = 0usize
        while i < supers {
            if above[i] != u32(i) || u32(i) == r || visit[i] != graph.NONE {
                i += 1usize
                continue
            }
            var x = u32(i)
            while x != r && visit[usize(x)] == graph.NONE {
                visit[usize(x)] = u32(i)
                x = find_top(above, g.edges[in_edge[usize(x)]].from)
            }
            if x != r && visit[usize(x)] == u32(i) {
                let c = u32(supers)
                supers += 1usize
                level_super[levels] = c
                level_start[levels] = members
                levels += 1usize
                var y = x
                while true {
                    cycle_node[members] = y
                    cycle_edge[members] = in_edge[usize(y)]
                    cyc[usize(y)] = c
                    members += 1usize
                    y = find_top(above, g.edges[in_edge[usize(y)]].from)
                    if y == x { break }
                }
                k = 0usize
                while k < m {
                    let v = find_top(above, g.edges[k].to)
                    if cyc[usize(v)] == c { w[k] -= in_w[usize(v)] }
                    k += 1usize
                }
                var q = level_start[levels - 1usize]
                while q < members {
                    above[usize(cycle_node[q])] = c
                    q += 1usize
                }
                visit[usize(c)] = c
                found = true
            }
            i += 1usize
        }
        if !found { break }
    }
    // Expand, last contraction first.
    var l = levels
    while l > 0usize {
        l -= 1usize
        let c = level_super[l]
        let entering = in_edge[usize(c)]
        var t = g.edges[entering].to
        while above[usize(t)] != c { t = above[usize(t)] }
        var stop = members
        if l + 1usize < levels { stop = level_start[l + 1usize] }
        var q = level_start[l]
        while q < stop {
            in_edge[usize(cycle_node[q])] = cycle_edge[q]
            q += 1usize
        }
        in_edge[usize(t)] = entering
    }
    var total = 0.0f64
    var placed = 0usize
    i = 0usize
    while i < n {
        if u32(i) != root {
            chosen[placed] = in_edge[i]
            total += weight(ctx, g.edges[in_edge[i]])
            placed += 1usize
        }
        i += 1usize
    }
    ret (Forest { edges: chosen[..placed], weight: total, trees: 1usize }, ok)
}

// Tarjan's low-link walk from `u`, entered from `from` (`graph.NONE` at a root). One
// edge back to `from` is the tree edge and is skipped; a second is a parallel edge and
// counts. A bridge is marked on the copy the walk descended along.
fn low_visit[E: type](g: *const graph.Graph[E], s: *LowLinks, u: graph.NodeId, from: graph.NodeId) {
    s.disc[usize(u)] = s.time
    s.low[usize(u)] = s.time
    s.time += 1u32
    var children = 0usize
    var skipped = false
    var k = g.offsets[usize(u)]
    while k < g.offsets[usize(u) + 1usize] {
        let v = g.edges[k].to
        if v == from && !skipped {
            skipped = true
            k += 1usize
            continue
        }
        if s.disc[usize(v)] == graph.NONE {
            children += 1usize
            low_visit[E](g, s, v, u)
            if s.low[usize(v)] < s.low[usize(u)] { s.low[usize(u)] = s.low[usize(v)] }
            if s.low[usize(v)] > s.disc[usize(u)] { s.is_bridge[k] = 1u8 }
            if from != graph.NONE && s.low[usize(v)] >= s.disc[usize(u)] { s.is_cut[usize(u)] = 1u8 }
        } else if s.disc[usize(v)] < s.low[usize(u)] {
            s.low[usize(u)] = s.disc[usize(v)]
        }
        k += 1usize
    }
    if from == graph.NONE && children > 1usize { s.is_cut[usize(u)] = 1u8 }
}

// Discovery times, low links, bridge and cut marks over the whole graph.
fn low_links[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (LowLinks, err) {
    let n = graph.node_count[E](g)
    let (disc, disc_error) = mem.alloc[u32](a, n)
    if disc_error != ok { ret (zero, disc_error) }
    let (low, low_error) = mem.alloc[u32](a, n)
    if low_error != ok { ret (zero, low_error) }
    let (is_bridge, is_bridge_error) = mem.alloc[u8](a, g.edges.len)
    if is_bridge_error != ok { ret (zero, is_bridge_error) }
    let (is_cut, is_cut_error) = mem.alloc[u8](a, n)
    if is_cut_error != ok { ret (zero, is_cut_error) }
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
    var s = LowLinks { disc: disc, low: low, is_bridge: is_bridge, is_cut: is_cut, time: 0u32 }
    i = 0usize
    while i < n {
        if disc[i] == graph.NONE { low_visit[E](g, &s, u32(i), graph.NONE) }
        i += 1usize
    }
    ret (s, ok)
}

// The nodes whose removal disconnects their component, in node order.
fn articulation_points[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err) {
    let (s, s_error) = low_links[E](a, g)
    if s_error != ok { ret (zero, s_error) }
    var found = 0usize
    var i = 0usize
    while i < s.is_cut.len {
        if s.is_cut[i] == 1u8 { found += 1usize }
        i += 1usize
    }
    let (out, out_error) = mem.alloc[graph.NodeId](a, found)
    if out_error != ok { ret (zero, out_error) }
    var placed = 0usize
    i = 0usize
    while i < s.is_cut.len {
        if s.is_cut[i] == 1u8 {
            out[placed] = u32(i)
            placed += 1usize
        }
        i += 1usize
    }
    ret (out[0..], ok)
}

// The edges whose removal disconnects their component, as indices of the from < to
// copy, in the walk's order.
fn bridges[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const usize, err) {
    let (s, s_error) = low_links[E](a, g)
    if s_error != ok { ret (zero, s_error) }
    var found = 0usize
    var k = 0usize
    while k < s.is_bridge.len {
        if s.is_bridge[k] == 1u8 { found += 1usize }
        k += 1usize
    }
    let (out, out_error) = mem.alloc[usize](a, found)
    if out_error != ok { ret (zero, out_error) }
    var placed = 0usize
    k = 0usize
    while k < s.is_bridge.len {
        if s.is_bridge[k] == 1u8 {
            out[placed] = k
            if g.edges[k].from > g.edges[k].to { out[placed] = twin[E](g, k) }
            placed += 1usize
        }
        k += 1usize
    }
    ret (out[0..], ok)
}

// Hierholzer over a directed graph: the Eulerian circuit when every node has
// in-degree equal to out-degree, else the Eulerian path from the one node with an
// extra out-edge; `NotEulerian` otherwise. The `m + 1` nodes of the walk.
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
    let (walk, walk_error) = mem.alloc[graph.NodeId](a, m + 1usize)
    if walk_error != ok { ret (zero, walk_error) }
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
            walk[written] = u
            written += 1usize
            depth -= 1usize
        }
    }
    // A disconnected edge set leaves edges unwalked; the walk was collected in reverse.
    if written != m + 1usize { ret (zero, NotEulerian) }
    var lo = 0usize
    var hi = written
    while lo + 1usize < hi {
        hi -= 1usize
        let carried = walk[lo]
        walk[lo] = walk[hi]
        walk[hi] = carried
        lo += 1usize
    }
    ret (walk[..written], ok)
}

// Warshall's transitive closure: `reach[i * n + j] = 1` when `j` is reachable from `i`
// (every node reaches itself); `reach.len >= n * n`.
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

// Union-find over `sets` (each node its own set at first), with path halving and the
// smaller root kept, so a forest's roots are its smallest nodes.
fn set_find(sets: []u32, x: u32) -> u32 {
    var y = x
    while sets[usize(y)] != y {
        sets[usize(y)] = sets[usize(sets[usize(y)])]
        y = sets[usize(y)]
    }
    ret y
}

fn set_join(sets: []u32, x: u32, y: u32) -> bool {
    let rx = set_find(sets, x)
    let ry = set_find(sets, y)
    if rx == ry { ret false }
    if rx < ry { sets[usize(ry)] = rx } else { sets[usize(rx)] = ry }
    ret true
}

fn fresh_sets(a: *mem.Arena, n: usize) -> ([]u32, err) {
    let (sets, sets_error) = mem.alloc[u32](a, n)
    if sets_error != ok { ret (zero, sets_error) }
    var i = 0usize
    while i < n {
        sets[i] = u32(i)
        i += 1usize
    }
    ret (sets, ok)
}

fn weighted_edge_cmp(ctx: *u8, x: WeightedEdge, y: WeightedEdge) -> i32 {
    if x.weight < y.weight { ret -1i32 }
    if x.weight > y.weight { ret 1i32 }
    if x.index < y.index { ret -1i32 }
    if x.index > y.index { ret 1i32 }
    ret 0i32
}

// Kruskal: the from < to copies heaped by (weight, index) and joined when they connect
// different sets. `trees` counts the forest's components.
fn mst_kruskal[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, chosen: []usize) -> (Forest, err) {
    let n = graph.node_count[E](g)
    if chosen.len + 1usize < n { ret (zero, TooSmall) }
    let (items, items_error) = mem.alloc[WeightedEdge](a, g.edges.len)
    if items_error != ok { ret (zero, items_error) }
    var m = 0usize
    var k = 0usize
    while k < g.edges.len {
        let e = g.edges[k]
        if e.from < e.to {
            items[m] = WeightedEdge { weight: weight(ctx, e), index: k }
            m += 1usize
        }
        k += 1usize
    }
    var tie = 0u8
    let (queue0, queue_error) = heap.from_slice_by[WeightedEdge, u8](a, items[..m], &tie, weighted_edge_cmp)
    if queue_error != ok { ret (zero, queue_error) }
    var queue = queue0
    let (sets, sets_error) = fresh_sets(a, n)
    if sets_error != ok { ret (zero, sets_error) }
    var placed = 0usize
    var total = 0.0f64
    while true {
        let (top, has_top) = heap.pop_by[WeightedEdge, u8](&queue)
        if !has_top { break }
        let e = g.edges[top.index]
        if set_join(sets, e.from, e.to) {
            chosen[placed] = top.index
            placed += 1usize
            total += top.weight
        }
    }
    ret (Forest { edges: chosen[..placed], weight: total, trees: n - placed }, ok)
}

// Prim from `start` with a lazy heap of (weight, node): the tree of `start`'s
// component; `trees` is 1 when the graph is connected.
fn mst_prim[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, chosen: []usize) -> (Forest, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n { ret (zero, graph.InvalidNode) }
    if chosen.len + 1usize < n { ret (zero, TooSmall) }
    let (best, best_error) = mem.alloc[f64](a, n)
    if best_error != ok { ret (zero, best_error) }
    let (via, via_error) = mem.alloc[usize](a, n)
    if via_error != ok { ret (zero, via_error) }
    let (done, done_error) = mem.alloc[bool](a, n)
    if done_error != ok { ret (zero, done_error) }
    var i = 0usize
    while i < n {
        best[i] = unreached()
        done[i] = false
        i += 1usize
    }
    best[usize(start)] = 0.0
    var tie = 0u8
    let (queue0, queue_error) = heap.init_by[Entry, u8](a, g.edges.len + 1usize, &tie, entry_cmp)
    if queue_error != ok { ret (zero, queue_error) }
    var queue = queue0
    let seed_error = heap.push_by[Entry, u8](&queue, Entry { distance: 0.0, node: start })
    if seed_error != ok { ret (zero, seed_error) }
    var placed = 0usize
    var total = 0.0f64
    var reached = 0usize
    while true {
        let (entry, has_entry) = heap.pop_by[Entry, u8](&queue)
        if !has_entry { break }
        let u = usize(entry.node)
        if done[u] { continue }
        done[u] = true
        reached += 1usize
        if entry.node != start {
            chosen[placed] = via[u]
            if g.edges[via[u]].from > g.edges[via[u]].to { chosen[placed] = twin[E](g, via[u]) }
            placed += 1usize
            total += best[u]
        }
        var k = g.offsets[u]
        while k < g.offsets[u + 1usize] {
            let to = usize(g.edges[k].to)
            if !done[to] {
                let w = weight(ctx, g.edges[k])
                if w < best[to] {
                    best[to] = w
                    via[to] = k
                    let push_error = heap.push_by[Entry, u8](&queue, Entry { distance: w, node: g.edges[k].to })
                    if push_error != ok { ret (zero, push_error) }
                }
            }
            k += 1usize
        }
    }
    ret (Forest { edges: chosen[..placed], weight: total, trees: n - reached + 1usize }, ok)
}

// Borůvka: every set picks its cheapest outgoing edge per round, ties broken by the
// from < to copy's index so that every set sees the same total order and the picks
// never close a cycle.
fn mst_boruvka[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, chosen: []usize) -> (Forest, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    if chosen.len + 1usize < n { ret (zero, TooSmall) }
    let (w, w_error) = mem.alloc[f64](a, m)
    if w_error != ok { ret (zero, w_error) }
    let (canon, canon_error) = mem.alloc[usize](a, m)
    if canon_error != ok { ret (zero, canon_error) }
    var k = 0usize
    while k < m {
        w[k] = weight(ctx, g.edges[k])
        canon[k] = k
        if g.edges[k].from > g.edges[k].to { canon[k] = twin[E](g, k) }
        k += 1usize
    }
    let (sets, sets_error) = fresh_sets(a, n)
    if sets_error != ok { ret (zero, sets_error) }
    let (cheapest, cheapest_error) = mem.alloc[usize](a, n)
    if cheapest_error != ok { ret (zero, cheapest_error) }
    let none = 18446744073709551615usize
    var placed = 0usize
    var total = 0.0f64
    while true {
        var i = 0usize
        while i < n {
            cheapest[i] = none
            i += 1usize
        }
        k = 0usize
        while k < m {
            let e = g.edges[k]
            let ra = usize(set_find(sets, e.from))
            if ra != usize(set_find(sets, e.to)) {
                let c = cheapest[ra]
                if c == none || w[k] < w[c] || (w[k] == w[c] && canon[k] < canon[c]) { cheapest[ra] = k }
            }
            k += 1usize
        }
        var merged = false
        i = 0usize
        while i < n {
            if cheapest[i] != none {
                let e = g.edges[cheapest[i]]
                if set_join(sets, e.from, e.to) {
                    chosen[placed] = canon[cheapest[i]]
                    placed += 1usize
                    total += w[cheapest[i]]
                    merged = true
                }
            }
            i += 1usize
        }
        if !merged { break }
    }
    ret (Forest { edges: chosen[..placed], weight: total, trees: n - placed }, ok)
}
