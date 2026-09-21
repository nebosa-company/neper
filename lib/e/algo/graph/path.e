// Shortest paths beyond `e.algo.graph.dijkstra`: Bellman-Ford with negative
// cycle detection, Floyd-Warshall over a distance matrix, Johnson's
// reweighting for all pairs with negative edges, Dial's bucket queue for small
// integer weights, A* and bidirectional breadth-first search between two
// nodes, iterative deepening (plain and A*), and reconstruction of a path from
// a predecessor table.
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
