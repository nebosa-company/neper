// Shortest paths beyond `e.algo.graph.dijkstra`: Bellman-Ford with negative
// cycle detection, Floyd-Warshall over a distance matrix, Johnson's
// reweighting for all pairs with negative edges, Dial's bucket queue for small
// integer weights, A* and bidirectional breadth-first search between two
// nodes, iterative deepening (plain and A*), and reconstruction of a path from
// a predecessor table; greedy best-first search, Suurballe's two edge-disjoint
// routes and Yen's K loopless routes.
//
// Weights come from a function over the graph's edges; distances are `f64`
// with `infinity()` for unreachable. Everything allocates from the arena.

use e.mem
use e.data.graph as graph
use e.algo.graph as algo

type Route = struct { nodes: []const graph.NodeId, cost: f64 }
error NegativeCycle
error InvalidNode
error TooSmall
error NoPath

// The distance of an unreachable node (a float constant cannot be a module constant).
fn infinity() -> f64 { ret 1.0e300f64 }

// The path from `start` to `goal` implied by a predecessor table (`start` is its
// own predecessor); empty when `goal` was not reached.
fn path_to(a: *mem.Arena, previous: []const graph.NodeId, start: graph.NodeId, goal: graph.NodeId) -> ([]const graph.NodeId, err) {
    if usize(goal) >= previous.len || usize(start) >= previous.len { ret (zero, InvalidNode) }
    if previous[usize(goal)] == graph.NONE { ret (zero, NoPath) }
    var length = 1usize
    var at = goal
    while at != start {
        at = previous[usize(at)]
        if at == graph.NONE { ret (zero, NoPath) }
        length += 1usize
        if length > previous.len { ret (zero, NoPath) }
    }
    let (out, out_error) = mem.alloc[graph.NodeId](a, length)
    if out_error != ok { ret (zero, out_error) }
    at = goal
    var i = length
    while i > 0usize {
        i -= 1usize
        out[i] = at
        at = previous[usize(at)]
    }
    ret (out[0..], ok)
}

// Bellman-Ford from `start`: distances and predecessors, or `NegativeCycle`.
fn bellman_ford[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (algo.Paths, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n { ret (zero, InvalidNode) }
    let (distance, distance_error) = mem.alloc[f64](a, n)
    if distance_error != ok { ret (zero, distance_error) }
    let (previous, previous_error) = mem.alloc[graph.NodeId](a, n)
    if previous_error != ok { ret (zero, previous_error) }
    var i = 0usize
    while i < n {
        distance[i] = infinity()
        previous[i] = graph.NONE
        i += 1usize
    }
    distance[usize(start)] = 0.0f64
    previous[usize(start)] = start
    var round = 0usize
    while round < n {
        var relaxed = false
        var k = 0usize
        while k < g.edges.len {
            let e = g.edges[k]
            if distance[usize(e.from)] < infinity() {
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
    ret (algo.Paths { distance: distance[0..], previous: previous[0..] }, ok)
}

// Floyd-Warshall: the `n x n` row-major distance matrix, `infinity()` where no path.
fn floyd_warshall[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> ([]f64, err) {
    let n = graph.node_count[E](g)
    let (d, d_error) = mem.alloc[f64](a, n * n)
    if d_error != ok { ret (zero, d_error) }
    var i = 0usize
    while i < n * n {
        d[i] = infinity()
        i += 1usize
    }
    i = 0usize
    while i < n {
        d[i * n + i] = 0.0f64
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
            if d[i * n + via] < infinity() {
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
        if d[i * n + i] < 0.0f64 { ret (zero, NegativeCycle) }
        i += 1usize
    }
    ret (d, ok)
}

// Dial's algorithm for non-negative integer weights at most `max_weight`:
// buckets indexed by distance replace the heap.
fn dial[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, max_weight: usize, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> usize) -> ([]usize, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n { ret (zero, InvalidNode) }
    let (distance, distance_error) = mem.alloc[usize](a, n)
    if distance_error != ok { ret (zero, distance_error) }
    let buckets = max_weight + 1usize
    // Each bucket is a singly linked list through `next`; `head` per bucket.
    let (head, head_error) = mem.alloc[u32](a, buckets)
    if head_error != ok { ret (zero, head_error) }
    let (next, next_error) = mem.alloc[u32](a, n)
    if next_error != ok { ret (zero, next_error) }
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
    next[usize(start)] = graph.NONE
    head[0usize] = start
    var current = 0usize
    var remaining = 1usize
    while remaining > 0usize {
        let bucket = current % buckets
        while head[bucket] != graph.NONE {
            let u = head[bucket]
            head[bucket] = next[usize(u)]
            remaining -= 1usize
            if distance[usize(u)] != current { continue }
            var k = g.offsets[usize(u)]
            while k < g.offsets[usize(u) + 1usize] {
                let e = g.edges[k]
                let w = weight(ctx, e)
                if w > max_weight { ret (zero, TooSmall) }
                let candidate = current + w
                if candidate < distance[usize(e.to)] {
                    distance[usize(e.to)] = candidate
                    let slot = candidate % buckets
                    next[usize(e.to)] = head[slot]
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

// Johnson: all-pairs distances with negative edges, by a Bellman-Ford
// reweighting then Dijkstra from every node. Answers the `n x n` matrix.
fn johnson[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> ([]f64, err) {
    let n = graph.node_count[E](g)
    // Potentials by Bellman-Ford from a virtual source: every node starts at 0.
    let (h, h_error) = mem.alloc[f64](a, n)
    if h_error != ok { ret (zero, h_error) }
    var i = 0usize
    while i < n {
        h[i] = 0.0f64
        i += 1usize
    }
    var round = 0usize
    while round < n {
        var relaxed = false
        var k = 0usize
        while k < g.edges.len {
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
    let (d, d_error) = mem.alloc[f64](a, n * n)
    if d_error != ok { ret (zero, d_error) }
    // Dijkstra per source over reweighted edges, with a simple O(n^2) selection
    // so no heap over a closure is needed.
    let (done, done_error) = mem.alloc[u8](a, n)
    if done_error != ok { ret (zero, done_error) }
    var s = 0usize
    while s < n {
        var row = d[s * n..(s + 1usize) * n]
        i = 0usize
        while i < n {
            row[i] = infinity()
            done[i] = 0u8
            i += 1usize
        }
        row[s] = 0.0f64
        var steps = 0usize
        while steps < n {
            var best = n
            i = 0usize
            while i < n {
                if done[i] == 0u8 && row[i] < infinity() && (best == n || row[i] < row[best]) { best = i }
                i += 1usize
            }
            if best == n { break }
            done[best] = 1u8
            var k = g.offsets[best]
            while k < g.offsets[best + 1usize] {
                let e = g.edges[k]
                let w = weight(ctx, e) + h[best] - h[usize(e.to)]
                if row[best] + w < row[usize(e.to)] { row[usize(e.to)] = row[best] + w }
                k += 1usize
            }
            steps += 1usize
        }
        i = 0usize
        while i < n {
            if row[i] < infinity() { row[i] = row[i] - h[s] + h[i] }
            i += 1usize
        }
        s += 1usize
    }
    ret (d, ok)
}

// A*: the cheapest route from `start` to `goal` under a consistent heuristic;
// `O(n^2)` selection, which suits the small graphs a library caller has in hand.
fn astar[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, heuristic: fn(*Ctx, graph.NodeId) -> f64) -> (Route, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n || usize(goal) >= n { ret (zero, InvalidNode) }
    let (score, score_error) = mem.alloc[f64](a, n)
    if score_error != ok { ret (zero, score_error) }
    let (previous, previous_error) = mem.alloc[graph.NodeId](a, n)
    if previous_error != ok { ret (zero, previous_error) }
    let (state, state_error) = mem.alloc[u8](a, n)
    if state_error != ok { ret (zero, state_error) }
    var i = 0usize
    while i < n {
        score[i] = infinity()
        previous[i] = graph.NONE
        state[i] = 0u8
        i += 1usize
    }
    score[usize(start)] = 0.0f64
    previous[usize(start)] = start
    state[usize(start)] = 1u8
    while true {
        var best = n
        var best_f = infinity()
        i = 0usize
        while i < n {
            if state[i] == 1u8 {
                let f = score[i] + heuristic(ctx, u32(i))
                if best == n || f < best_f {
                    best = i
                    best_f = f
                }
            }
            i += 1usize
        }
        if best == n { ret (zero, NoPath) }
        if best == usize(goal) { break }
        state[best] = 2u8
        var k = g.offsets[best]
        while k < g.offsets[best + 1usize] {
            let e = g.edges[k]
            let candidate = score[best] + weight(ctx, e)
            if candidate < score[usize(e.to)] {
                score[usize(e.to)] = candidate
                previous[usize(e.to)] = u32(best)
                state[usize(e.to)] = 1u8
            }
            k += 1usize
        }
    }
    let (nodes, nodes_error) = path_to(a, previous[0..], start, goal)
    if nodes_error != ok { ret (zero, nodes_error) }
    ret (Route { nodes: nodes, cost: score[usize(goal)] }, ok)
}

// Bidirectional breadth-first search over unit weights, with the reverse
// adjacency built on the fly; answers the fewest-edge route.
fn bidirectional[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId) -> (Route, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n || usize(goal) >= n { ret (zero, InvalidNode) }
    let (reverse_offsets, ro_error) = mem.alloc[usize](a, n + 1usize)
    if ro_error != ok { ret (zero, ro_error) }
    let (reverse, r_error) = mem.alloc[graph.NodeId](a, g.edges.len)
    if r_error != ok { ret (zero, r_error) }
    algo.build_reverse[E](g, reverse_offsets, reverse)
    let (parent_f, pf_error) = mem.alloc[graph.NodeId](a, n)
    if pf_error != ok { ret (zero, pf_error) }
    let (parent_b, pb_error) = mem.alloc[graph.NodeId](a, n)
    if pb_error != ok { ret (zero, pb_error) }
    let (queue_f, qf_error) = mem.alloc[graph.NodeId](a, n)
    if qf_error != ok { ret (zero, qf_error) }
    let (queue_b, qb_error) = mem.alloc[graph.NodeId](a, n)
    if qb_error != ok { ret (zero, qb_error) }
    var i = 0usize
    while i < n {
        parent_f[i] = graph.NONE
        parent_b[i] = graph.NONE
        i += 1usize
    }
    parent_f[usize(start)] = start
    parent_b[usize(goal)] = goal
    queue_f[0usize] = start
    queue_b[0usize] = goal
    var head_f = 0usize
    var tail_f = 1usize
    var head_b = 0usize
    var tail_b = 1usize
    var meeting = graph.NONE
    if start == goal { meeting = start }
    while meeting == graph.NONE && head_f < tail_f && head_b < tail_b {
        // Expand one layer forward.
        let end_f = tail_f
        while head_f < end_f && meeting == graph.NONE {
            let u = queue_f[head_f]
            head_f += 1usize
            var k = g.offsets[usize(u)]
            while k < g.offsets[usize(u) + 1usize] {
                let v = g.edges[k].to
                if parent_f[usize(v)] == graph.NONE {
                    parent_f[usize(v)] = u
                    queue_f[tail_f] = v
                    tail_f += 1usize
                    if parent_b[usize(v)] != graph.NONE {
                        meeting = v
                        break
                    }
                }
                k += 1usize
            }
        }
        if meeting != graph.NONE { break }
        // Expand one layer backward.
        let end_b = tail_b
        while head_b < end_b && meeting == graph.NONE {
            let u = queue_b[head_b]
            head_b += 1usize
            var k = reverse_offsets[usize(u)]
            while k < reverse_offsets[usize(u) + 1usize] {
                let v = reverse[k]
                if parent_b[usize(v)] == graph.NONE {
                    parent_b[usize(v)] = u
                    queue_b[tail_b] = v
                    tail_b += 1usize
                    if parent_f[usize(v)] != graph.NONE {
                        meeting = v
                        break
                    }
                }
                k += 1usize
            }
        }
    }
    if meeting == graph.NONE { ret (zero, NoPath) }
    // Stitch: start .. meeting from the forward tree, then meeting .. goal from the backward one.
    let (front, front_error) = path_to(a, parent_f[0..], start, meeting)
    if front_error != ok { ret (zero, front_error) }
    var back_length = 0usize
    var at = meeting
    while at != goal {
        at = parent_b[usize(at)]
        back_length += 1usize
    }
    let (nodes, nodes_error) = mem.alloc[graph.NodeId](a, front.len + back_length)
    if nodes_error != ok { ret (zero, nodes_error) }
    i = 0usize
    while i < front.len {
        nodes[i] = front[i]
        i += 1usize
    }
    at = meeting
    while at != goal {
        at = parent_b[usize(at)]
        nodes[i] = at
        i += 1usize
    }
    ret (Route { nodes: nodes[0..], cost: f64(front.len + back_length - 1usize) }, ok)
}

// Iterative deepening depth-first search over unit weights: the depth bound
// grows until `goal` is reached or `max_depth` is exhausted.
fn iddfs[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, max_depth: usize) -> (Route, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n || usize(goal) >= n { ret (zero, InvalidNode) }
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, max_depth + 2usize)
    if stack_error != ok { ret (zero, stack_error) }
    let (cursor, cursor_error) = mem.alloc[usize](a, max_depth + 2usize)
    if cursor_error != ok { ret (zero, cursor_error) }
    var bound = 0usize
    while bound <= max_depth {
        var depth = 0usize
        stack[0usize] = start
        cursor[0usize] = g.offsets[usize(start)]
        while true {
            let u = stack[depth]
            if u == goal {
                let (nodes, nodes_error) = mem.alloc[graph.NodeId](a, depth + 1usize)
                if nodes_error != ok { ret (zero, nodes_error) }
                var i = 0usize
                while i <= depth {
                    nodes[i] = stack[i]
                    i += 1usize
                }
                ret (Route { nodes: nodes[0..], cost: f64(depth) }, ok)
            }
            var descended = false
            if depth < bound {
                while cursor[depth] < g.offsets[usize(u) + 1usize] {
                    let v = g.edges[cursor[depth]].to
                    cursor[depth] += 1usize
                    // Skip a node already on the path.
                    var on_path = false
                    var i = 0usize
                    while i <= depth {
                        if stack[i] == v { on_path = true }
                        i += 1usize
                    }
                    if !on_path {
                        depth += 1usize
                        stack[depth] = v
                        cursor[depth] = g.offsets[usize(v)]
                        descended = true
                        break
                    }
                }
            }
            if !descended {
                if depth == 0usize { break }
                depth -= 1usize
            }
        }
        bound += 1usize
    }
    ret (zero, NoPath)
}

// Iterative deepening A* with an admissible heuristic over `weight`: the cost
// bound grows to the smallest exceeded value each round.
fn ida_star[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, max_depth: usize, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, heuristic: fn(*Ctx, graph.NodeId) -> f64) -> (Route, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n || usize(goal) >= n { ret (zero, InvalidNode) }
    let (stack, stack_error) = mem.alloc[graph.NodeId](a, max_depth + 2usize)
    if stack_error != ok { ret (zero, stack_error) }
    let (cursor, cursor_error) = mem.alloc[usize](a, max_depth + 2usize)
    if cursor_error != ok { ret (zero, cursor_error) }
    let (cost, cost_error) = mem.alloc[f64](a, max_depth + 2usize)
    if cost_error != ok { ret (zero, cost_error) }
    var bound = heuristic(ctx, start)
    var rounds = 0usize
    while rounds < 1000usize {
        var next_bound = infinity()
        var depth = 0usize
        stack[0usize] = start
        cursor[0usize] = g.offsets[usize(start)]
        cost[0usize] = 0.0f64
        while true {
            let u = stack[depth]
            if u == goal {
                let (nodes, nodes_error) = mem.alloc[graph.NodeId](a, depth + 1usize)
                if nodes_error != ok { ret (zero, nodes_error) }
                var i = 0usize
                while i <= depth {
                    nodes[i] = stack[i]
                    i += 1usize
                }
                ret (Route { nodes: nodes[0..], cost: cost[depth] }, ok)
            }
            var descended = false
            if depth < max_depth {
                while cursor[depth] < g.offsets[usize(u) + 1usize] {
                    let e = g.edges[cursor[depth]]
                    cursor[depth] += 1usize
                    let f = cost[depth] + weight(ctx, e) + heuristic(ctx, e.to)
                    var on_path = false
                    var i = 0usize
                    while i <= depth {
                        if stack[i] == e.to { on_path = true }
                        i += 1usize
                    }
                    if on_path { continue }
                    if f > bound {
                        if f < next_bound { next_bound = f }
                        continue
                    }
                    depth += 1usize
                    stack[depth] = e.to
                    cursor[depth] = g.offsets[usize(e.to)]
                    cost[depth] = cost[depth - 1usize] + weight(ctx, e)
                    descended = true
                    break
                }
            }
            if !descended {
                if depth == 0usize { break }
                depth -= 1usize
            }
        }
        if next_bound >= infinity() { ret (zero, NoPath) }
        bound = next_bound
        rounds += 1usize
    }
    ret (zero, NoPath)
}

type Pair = struct { first: []const graph.NodeId, second: []const graph.NodeId, cost: f64 }
type Routes = struct { offsets: []const usize, nodes: []const graph.NodeId, costs: []const f64 }

// Greedy best-first search: the open node of least heuristic is expanded
// (ties to the lowest id), a node keeps the first predecessor that found it,
// and the route is the one the discovery tree holds when `goal` is taken
// (its cost summed along it; not the cheapest in general).
fn best_first[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, heuristic: fn(*Ctx, graph.NodeId) -> f64) -> (Route, err) {
    let n = graph.node_count[E](g)
    if usize(start) >= n || usize(goal) >= n { ret (zero, InvalidNode) }
    let (score, score_error) = mem.alloc[f64](a, n)
    if score_error != ok { ret (zero, score_error) }
    let (previous, previous_error) = mem.alloc[graph.NodeId](a, n)
    if previous_error != ok { ret (zero, previous_error) }
    let (state, state_error) = mem.alloc[u8](a, n)
    if state_error != ok { ret (zero, state_error) }
    var i = 0usize
    while i < n {
        previous[i] = graph.NONE
        state[i] = 0u8
        i += 1usize
    }
    score[usize(start)] = 0.0f64
    previous[usize(start)] = start
    state[usize(start)] = 1u8
    var searching = true
    while searching {
        var best = n
        var best_h = 0.0f64
        i = 0usize
        while i < n {
            if state[i] == 1u8 {
                let h = heuristic(ctx, u32(i))
                if best == n || h < best_h {
                    best = i
                    best_h = h
                }
            }
            i += 1usize
        }
        if best == n { ret (zero, NoPath) }
        if best == usize(goal) {
            searching = false
        } else {
            state[best] = 2u8
            var k = g.offsets[best]
            while k < g.offsets[best + 1usize] {
                let e = g.edges[k]
                if state[usize(e.to)] == 0u8 {
                    state[usize(e.to)] = 1u8
                    previous[usize(e.to)] = u32(best)
                    score[usize(e.to)] = score[best] + weight(ctx, e)
                }
                k += 1usize
            }
        }
    }
    let (nodes, nodes_error) = path_to(a, previous[0..], start, goal)
    if nodes_error != ok { ret (zero, nodes_error) }
    ret (Route { nodes: nodes, cost: score[usize(goal)] }, ok)
}

// Dijkstra by `O(n^2)` selection that skips blocked edges and nodes and
// records the edge each node was reached by (`NONE` when unreached).
fn dijkstra_masked[E: type, Ctx: type](g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, blocked_edge: []const u8, blocked_node: []const u8, distance: []f64, by_edge: []u32, done: []u8) {
    let n = graph.node_count[E](g)
    var i = 0usize
    while i < n {
        distance[i] = infinity()
        by_edge[i] = graph.NONE
        done[i] = 0u8
        i += 1usize
    }
    distance[usize(start)] = 0.0f64
    var steps = 0usize
    while steps < n {
        var best = n
        i = 0usize
        while i < n {
            if done[i] == 0u8 && blocked_node[i] == 0u8 && distance[i] < infinity() && (best == n || distance[i] < distance[best]) { best = i }
            i += 1usize
        }
        if best == n { ret }
        done[best] = 1u8
        var k = g.offsets[best]
        while k < g.offsets[best + 1usize] {
            let e = g.edges[k]
            if blocked_edge[k] == 0u8 && blocked_node[usize(e.to)] == 0u8 {
                let candidate = distance[best] + weight(ctx, e)
                if candidate < distance[usize(e.to)] {
                    distance[usize(e.to)] = candidate
                    by_edge[usize(e.to)] = u32(k)
                }
            }
            k += 1usize
        }
        steps += 1usize
    }
}

// Follows `chosen` edges from `start` to `goal`, clearing each one taken,
// into `out`; answers the node count or 0 when the walk fails.
fn walk_chosen[E: type](g: *const graph.Graph[E], chosen: []u8, start: graph.NodeId, goal: graph.NodeId, out: []graph.NodeId) -> usize {
    var at = start
    var count = 1usize
    out[0usize] = start
    while at != goal {
        var taken = graph.NONE
        var k = g.offsets[usize(at)]
        while k < g.offsets[usize(at) + 1usize] && taken == graph.NONE {
            if chosen[k] == 1u8 { taken = u32(k) }
            k += 1usize
        }
        if taken == graph.NONE || count >= out.len { ret 0usize }
        chosen[usize(taken)] = 0u8
        at = g.edges[usize(taken)].to
        out[count] = at
        count += 1usize
    }
    ret count
}

fn copy_nodes(a: *mem.Arena, from: []const graph.NodeId, count: usize) -> ([]const graph.NodeId, err) {
    let (out, out_error) = mem.alloc[graph.NodeId](a, count)
    if out_error != ok { ret (zero, out_error) }
    var i = 0usize
    while i < count {
        out[i] = from[i]
        i += 1usize
    }
    ret (out[0..], ok)
}

// Suurballe: two edge-disjoint routes from `start` to `goal` of least total
// weight (non-negative weights). Dijkstra gives the first route and
// potentials; in the residual graph with reduced costs and the first route's
// edges reversed at cost zero a second Dijkstra finds the second; edges used
// in both directions cancel and the rest is split into the two routes.
fn suurballe[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Pair, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    if usize(start) >= n || usize(goal) >= n || start == goal { ret (zero, InvalidNode) }
    let (distance, distance_error) = mem.alloc[f64](a, n)
    if distance_error != ok { ret (zero, distance_error) }
    let (second, second_error) = mem.alloc[f64](a, n)
    if second_error != ok { ret (zero, second_error) }
    let (by_edge, by_error) = mem.alloc[u32](a, n)
    if by_error != ok { ret (zero, by_error) }
    let (by_edge2, by2_error) = mem.alloc[u32](a, n)
    if by2_error != ok { ret (zero, by2_error) }
    let (flags, flags_error) = mem.alloc[u8](a, 2usize * n + 2usize * m)
    if flags_error != ok { ret (zero, flags_error) }
    let (buffer, buffer_error) = mem.alloc[graph.NodeId](a, n + 1usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    var done = flags[..n]
    var blocked_node = flags[n..2usize * n]
    var on_first = flags[2usize * n..2usize * n + m]
    var chosen = flags[2usize * n + m..2usize * n + 2usize * m]
    var i = 0usize
    while i < n {
        blocked_node[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < m {
        on_first[i] = 0u8
        chosen[i] = 0u8
        i += 1usize
    }
    dijkstra_masked[E, Ctx](g, start, ctx, weight, chosen, blocked_node, distance, by_edge, done)
    if distance[usize(goal)] >= infinity() { ret (zero, NoPath) }
    var at = goal
    while at != start {
        let k = by_edge[usize(at)]
        on_first[usize(k)] = 1u8
        at = g.edges[usize(k)].from
    }
    // The second Dijkstra over the residual graph, scanning every edge per settled node.
    i = 0usize
    while i < n {
        second[i] = infinity()
        by_edge2[i] = graph.NONE
        done[i] = 0u8
        i += 1usize
    }
    second[usize(start)] = 0.0f64
    var steps = 0usize
    while steps < n {
        var best = n
        i = 0usize
        while i < n {
            if done[i] == 0u8 && second[i] < infinity() && (best == n || second[i] < second[best]) { best = i }
            i += 1usize
        }
        if best == n {
            steps = n
        } else {
            done[best] = 1u8
            var k = 0usize
            while k < m {
                let e = g.edges[k]
                if on_first[k] == 1u8 {
                    if usize(e.to) == best && second[best] < second[usize(e.from)] {
                        second[usize(e.from)] = second[best]
                        by_edge2[usize(e.from)] = u32(k)
                    }
                } else if usize(e.from) == best && distance[usize(e.to)] < infinity() {
                    var reduced = weight(ctx, e) + distance[best] - distance[usize(e.to)]
                    if reduced < 0.0f64 { reduced = 0.0f64 }
                    if second[best] + reduced < second[usize(e.to)] {
                        second[usize(e.to)] = second[best] + reduced
                        by_edge2[usize(e.to)] = u32(k)
                    }
                }
                k += 1usize
            }
            steps += 1usize
        }
    }
    if second[usize(goal)] >= infinity() { ret (zero, NoPath) }
    // Untangle: a reversed first-route edge cancels, every other edge is kept.
    at = goal
    while at != start {
        let k = usize(by_edge2[usize(at)])
        if on_first[k] == 1u8 {
            on_first[k] = 0u8
            at = g.edges[k].to
        } else {
            chosen[k] = 1u8
            at = g.edges[k].from
        }
    }
    var cost = 0.0f64
    i = 0usize
    while i < m {
        if on_first[i] == 1u8 { chosen[i] = 1u8 }
        if chosen[i] == 1u8 { cost += weight(ctx, g.edges[i]) }
        i += 1usize
    }
    let first_count = walk_chosen[E](g, chosen, start, goal, buffer)
    if first_count == 0usize { ret (zero, NoPath) }
    let (first, first_error) = copy_nodes(a, buffer[0..], first_count)
    if first_error != ok { ret (zero, first_error) }
    let second_count = walk_chosen[E](g, chosen, start, goal, buffer)
    if second_count == 0usize { ret (zero, NoPath) }
    let (second_route, second_route_error) = copy_nodes(a, buffer[0..], second_count)
    if second_route_error != ok { ret (zero, second_route_error) }
    ret (Pair { first: first, second: second_route, cost: cost }, ok)
}

// Yen's K loopless shortest routes (non-negative weights): the shortest
// route first, then for every node of the last route taken as a spur, the
// root before it is fixed, the edge every known route with that root leaves
// it by is blocked, the root's nodes are blocked, and a Dijkstra from the
// spur proposes root + spur; the cheapest proposal (ties to the earliest)
// is the next route. Routes are edge sequences, so parallel edges are
// distinct routes. Fewer than `k_paths` when the graph runs out.
fn yen_k_shortest[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, k_paths: usize, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Routes, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    if usize(start) >= n || usize(goal) >= n || start == goal { ret (zero, InvalidNode) }
    if k_paths == 0usize { ret (zero, TooSmall) }
    let (distance, distance_error) = mem.alloc[f64](a, n)
    if distance_error != ok { ret (zero, distance_error) }
    let (by_edge, by_error) = mem.alloc[u32](a, n)
    if by_error != ok { ret (zero, by_error) }
    let (flags, flags_error) = mem.alloc[u8](a, 2usize * n + m)
    if flags_error != ok { ret (zero, flags_error) }
    var done = flags[..n]
    var blocked_node = flags[n..2usize * n]
    var blocked_edge = flags[2usize * n..2usize * n + m]
    // Known routes (A) and proposals (B) as edge sequences of at most n - 1 edges.
    let slots = k_paths * n
    let (a_edges, a_edges_error) = mem.alloc[u32](a, k_paths * n)
    if a_edges_error != ok { ret (zero, a_edges_error) }
    let (a_len, a_len_error) = mem.alloc[usize](a, k_paths)
    if a_len_error != ok { ret (zero, a_len_error) }
    let (a_cost, a_cost_error) = mem.alloc[f64](a, k_paths)
    if a_cost_error != ok { ret (zero, a_cost_error) }
    let (b_edges, b_edges_error) = mem.alloc[u32](a, slots * n)
    if b_edges_error != ok { ret (zero, b_edges_error) }
    let (b_len, b_len_error) = mem.alloc[usize](a, slots)
    if b_len_error != ok { ret (zero, b_len_error) }
    let (b_cost, b_cost_error) = mem.alloc[f64](a, slots)
    if b_cost_error != ok { ret (zero, b_cost_error) }
    let (b_taken, b_taken_error) = mem.alloc[u8](a, slots)
    if b_taken_error != ok { ret (zero, b_taken_error) }
    var i = 0usize
    while i < n {
        blocked_node[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < m {
        blocked_edge[i] = 0u8
        i += 1usize
    }
    dijkstra_masked[E, Ctx](g, start, ctx, weight, blocked_edge, blocked_node, distance, by_edge, done)
    if distance[usize(goal)] >= infinity() { ret (zero, NoPath) }
    var count = 1usize
    a_len[0usize] = 0usize
    a_cost[0usize] = distance[usize(goal)]
    var at = goal
    while at != start {
        a_len[0usize] += 1usize
        at = g.edges[usize(by_edge[usize(at)])].from
    }
    at = goal
    i = a_len[0usize]
    while at != start {
        i -= 1usize
        a_edges[i] = by_edge[usize(at)]
        at = g.edges[usize(a_edges[i])].from
    }
    var proposals = 0usize
    var p = 0usize
    var growing = true
    while growing && count < k_paths {
        let last = (count - 1usize) * n
        var spur_index = 0usize
        while spur_index < a_len[count - 1usize] {
            var spur = start
            if spur_index > 0usize { spur = g.edges[usize(a_edges[last + spur_index - 1usize])].to }
            i = 0usize
            while i < m {
                blocked_edge[i] = 0u8
                i += 1usize
            }
            i = 0usize
            while i < n {
                blocked_node[i] = 0u8
                i += 1usize
            }
            var root_cost = 0.0f64
            i = 0usize
            while i < spur_index {
                let k = usize(a_edges[last + i])
                root_cost += weight(ctx, g.edges[k])
                blocked_node[usize(g.edges[k].from)] = 1u8
                i += 1usize
            }
            p = 0usize
            while p < count {
                var same = a_len[p] > spur_index
                i = 0usize
                while same && i < spur_index {
                    if a_edges[p * n + i] != a_edges[last + i] { same = false }
                    i += 1usize
                }
                if same { blocked_edge[usize(a_edges[p * n + spur_index])] = 1u8 }
                p += 1usize
            }
            dijkstra_masked[E, Ctx](g, spur, ctx, weight, blocked_edge, blocked_node, distance, by_edge, done)
            if distance[usize(goal)] < infinity() && proposals < slots {
                // root + spur into the next proposal slot, then drop it if already proposed.
                let slot = proposals * n
                i = 0usize
                while i < spur_index {
                    b_edges[slot + i] = a_edges[last + i]
                    i += 1usize
                }
                var length = spur_index
                at = goal
                while at != spur {
                    length += 1usize
                    at = g.edges[usize(by_edge[usize(at)])].from
                }
                at = goal
                i = length
                while at != spur {
                    i -= 1usize
                    b_edges[slot + i] = by_edge[usize(at)]
                    at = g.edges[usize(b_edges[slot + i])].from
                }
                b_len[proposals] = length
                b_cost[proposals] = root_cost + distance[usize(goal)]
                b_taken[proposals] = 0u8
                var fresh = true
                p = 0usize
                while fresh && p < proposals {
                    var same = b_len[p] == length
                    i = 0usize
                    while same && i < length {
                        if b_edges[p * n + i] != b_edges[slot + i] { same = false }
                        i += 1usize
                    }
                    if same { fresh = false }
                    p += 1usize
                }
                if fresh { proposals += 1usize }
            }
            spur_index += 1usize
        }
        // The cheapest untaken proposal becomes the next route.
        var pick = slots
        p = 0usize
        while p < proposals {
            if b_taken[p] == 0u8 && (pick == slots || b_cost[p] < b_cost[pick]) { pick = p }
            p += 1usize
        }
        if pick == slots {
            growing = false
        } else {
            b_taken[pick] = 1u8
            i = 0usize
            while i < b_len[pick] {
                a_edges[count * n + i] = b_edges[pick * n + i]
                i += 1usize
            }
            a_len[count] = b_len[pick]
            a_cost[count] = b_cost[pick]
            count += 1usize
        }
    }
    // Routes as node sequences.
    let (offsets, offsets_error) = mem.alloc[usize](a, count + 1usize)
    if offsets_error != ok { ret (zero, offsets_error) }
    var total = 0usize
    p = 0usize
    while p < count {
        offsets[p] = total
        total += a_len[p] + 1usize
        p += 1usize
    }
    offsets[count] = total
    let (nodes, nodes_error) = mem.alloc[graph.NodeId](a, total)
    if nodes_error != ok { ret (zero, nodes_error) }
    p = 0usize
    while p < count {
        nodes[offsets[p]] = start
        i = 0usize
        while i < a_len[p] {
            nodes[offsets[p] + i + 1usize] = g.edges[usize(a_edges[p * n + i])].to
            i += 1usize
        }
        p += 1usize
    }
    ret (Routes { offsets: offsets[0..], nodes: nodes[0..], costs: a_cost[..count] }, ok)
}
