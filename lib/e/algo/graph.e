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
