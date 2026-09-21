// Maximum flow over `e.data.graph`'s adjacency: the residual network is built
// once in the caller's arena from a capacity function over the graph's edges,
// then Edmonds-Karp (shortest augmenting paths), Dinic (blocking flows over a
// level graph) or push-relabel (highest label with global relabelling omitted)
// computes the maximum flow from `source` to `sink`. `min_cut` reads the
// source side of a minimum cut off a saturated network. Capacities are `i64`
// and a directed edge of the input becomes a forward arc with its capacity and
// a reverse arc of zero; an undirected input edge is two forward arcs.

use e.mem
use e.data.graph as graph

type Network = struct { head: []u32, next: []u32, to: []u32, capacity: []i64, arcs: usize, nodes: usize, source: u32, sink: u32 }
error InvalidNode
error InvalidCapacity

const NONE: u32 = 4294967295u32

// Builds the residual network; `capacity(ctx, edge)` must be non-negative.
fn build[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], source: graph.NodeId, sink: graph.NodeId, ctx: *Ctx, capacity: fn(*Ctx, graph.Edge[E]) -> i64) -> (Network, err) {
    let n = graph.node_count[E](g)
    if usize(source) >= n || usize(sink) >= n || source == sink { ret (zero, InvalidNode) }
    let m = graph.edge_count[E](g)
    let (head, head_error) = mem.alloc[u32](a, n)
    if head_error != ok { ret (zero, head_error) }
    let (next, next_error) = mem.alloc[u32](a, 2usize * m)
    if next_error != ok { ret (zero, next_error) }
    let (to, to_error) = mem.alloc[u32](a, 2usize * m)
    if to_error != ok { ret (zero, to_error) }
    let (cap, cap_error) = mem.alloc[i64](a, 2usize * m)
    if cap_error != ok { ret (zero, cap_error) }
    var i = 0usize
    while i < n {
        head[i] = NONE
        i += 1usize
    }
    var net = Network { head: head, next: next, to: to, capacity: cap, arcs: 0usize, nodes: n, source: source, sink: sink }
    var it = graph.nodes[E](g)
    while true {
        let (node, has_node) = graph.nodes_next(&it)
        if !has_node { break }
        let (edges, edges_error) = graph.neighbors[E](g, node)
        if edges_error != ok { ret (zero, edges_error) }
        var walk = edges
        while true {
            let (edge, has_edge) = graph.neighbors_next[E](&walk)
            if !has_edge { break }
            let c = capacity(ctx, edge)
            if c < 0i64 { ret (zero, InvalidCapacity) }
            add_arc(&net, edge.from, edge.to, c)
        }
    }
    ret (net, ok)
}

// Appends a forward arc and its reverse; arc `k` and `k ^ 1` are partners.
fn add_arc(net: *Network, from: u32, to: u32, capacity: i64) {
    let k = net.arcs
    net.to[k] = to
    net.capacity[k] = capacity
    net.next[k] = net.head[usize(from)]
    net.head[usize(from)] = u32(k)
    net.to[k + 1usize] = from
    net.capacity[k + 1usize] = 0i64
    net.next[k + 1usize] = net.head[usize(to)]
    net.head[usize(to)] = u32(k + 1usize)
    net.arcs += 2usize
}

// Edmonds-Karp: augment along shortest paths until none remains.
fn edmonds_karp(a: *mem.Arena, net: *Network) -> (i64, err) {
    let n = net.nodes
    let (parent_arc, parent_error) = mem.alloc[u32](a, n)
    if parent_error != ok { ret (0i64, parent_error) }
    let (queue, queue_error) = mem.alloc[u32](a, n)
    if queue_error != ok { ret (0i64, queue_error) }
    var flow = 0i64
    while true {
        var i = 0usize
        while i < n {
            parent_arc[i] = NONE
            i += 1usize
        }
        var head = 0usize
        var tail = 1usize
        queue[0usize] = net.source
        parent_arc[usize(net.source)] = 4294967294u32
        var found = false
        while head < tail && !found {
            let u = queue[head]
            head += 1usize
            var arc = net.head[usize(u)]
            while arc != NONE {
                let v = net.to[usize(arc)]
                if net.capacity[usize(arc)] > 0i64 && parent_arc[usize(v)] == NONE {
                    parent_arc[usize(v)] = arc
                    if v == net.sink {
                        found = true
                        break
                    }
                    queue[tail] = v
                    tail += 1usize
                }
                arc = net.next[usize(arc)]
            }
        }
        if !found { break }
        // The bottleneck along the path, then the augmentation.
        var bottleneck = 9223372036854775807i64
        var v = net.sink
        while v != net.source {
            let arc = parent_arc[usize(v)]
            if net.capacity[usize(arc)] < bottleneck { bottleneck = net.capacity[usize(arc)] }
            v = net.to[usize(arc) ^ 1usize]
        }
        v = net.sink
        while v != net.source {
            let arc = parent_arc[usize(v)]
            net.capacity[usize(arc)] -= bottleneck
            net.capacity[usize(arc) ^ 1usize] += bottleneck
            v = net.to[usize(arc) ^ 1usize]
        }
        flow += bottleneck
    }
    ret (flow, ok)
}

// Dinic: BFS levels, then DFS blocking flows with a per-node arc pointer.
fn dinic(a: *mem.Arena, net: *Network) -> (i64, err) {
    let n = net.nodes
    let (level, level_error) = mem.alloc[u32](a, n)
    if level_error != ok { ret (0i64, level_error) }
    let (pointer, pointer_error) = mem.alloc[u32](a, n)
    if pointer_error != ok { ret (0i64, pointer_error) }
    let (queue, queue_error) = mem.alloc[u32](a, n)
    if queue_error != ok { ret (0i64, queue_error) }
    // An explicit DFS stack of (node, arc) so deep paths need no recursion.
    let (stack_node, stack_error) = mem.alloc[u32](a, n + 1usize)
    if stack_error != ok { ret (0i64, stack_error) }
    let (stack_arc, stack_arc_error) = mem.alloc[u32](a, n + 1usize)
    if stack_arc_error != ok { ret (0i64, stack_arc_error) }
    var flow = 0i64
    while true {
        var i = 0usize
        while i < n {
            level[i] = NONE
            i += 1usize
        }
        var head = 0usize
        var tail = 1usize
        queue[0usize] = net.source
        level[usize(net.source)] = 0u32
        while head < tail {
            let u = queue[head]
            head += 1usize
            var arc = net.head[usize(u)]
            while arc != NONE {
                let v = net.to[usize(arc)]
                if net.capacity[usize(arc)] > 0i64 && level[usize(v)] == NONE {
                    level[usize(v)] = level[usize(u)] + 1u32
                    queue[tail] = v
                    tail += 1usize
                }
                arc = net.next[usize(arc)]
            }
        }
        if level[usize(net.sink)] == NONE { break }
        i = 0usize
        while i < n {
            pointer[i] = net.head[i]
            i += 1usize
        }
        // Repeated augmenting DFS along level-increasing arcs.
        while true {
            var depth = 0usize
            stack_node[0usize] = net.source
            var pushed = 0i64
            var reached = false
            while true {
                let u = stack_node[depth]
                if u == net.sink {
                    reached = true
                    break
                }
                var arc = pointer[usize(u)]
                var advanced = false
                while arc != NONE {
                    let v = net.to[usize(arc)]
                    if net.capacity[usize(arc)] > 0i64 && level[usize(v)] == level[usize(u)] + 1u32 {
                        stack_arc[depth] = arc
                        depth += 1usize
                        stack_node[depth] = v
                        advanced = true
                        break
                    }
                    arc = net.next[usize(arc)]
                    pointer[usize(u)] = arc
                }
                if !advanced {
                    if depth == 0usize { break }
                    // Dead end: retreat and skip the arc that led here.
                    depth -= 1usize
                    let back = stack_node[depth]
                    pointer[usize(back)] = net.next[usize(stack_arc[depth])]
                }
            }
            if !reached { break }
            var bottleneck = 9223372036854775807i64
            var d = 0usize
            while d < depth {
                if net.capacity[usize(stack_arc[d])] < bottleneck { bottleneck = net.capacity[usize(stack_arc[d])] }
                d += 1usize
            }
            d = 0usize
            while d < depth {
                net.capacity[usize(stack_arc[d])] -= bottleneck
                net.capacity[usize(stack_arc[d]) ^ 1usize] += bottleneck
                d += 1usize
            }
            pushed = bottleneck
            flow += pushed
        }
    }
    ret (flow, ok)
}

// Push-relabel (FIFO active set, no heuristics): `O(V^3)` worst case.
fn push_relabel(a: *mem.Arena, net: *Network) -> (i64, err) {
    let n = net.nodes
    let (height, height_error) = mem.alloc[u32](a, n)
    if height_error != ok { ret (0i64, height_error) }
    let (excess, excess_error) = mem.alloc[i64](a, n)
    if excess_error != ok { ret (0i64, excess_error) }
    let (queue, queue_error) = mem.alloc[u32](a, n + 1usize)
    if queue_error != ok { ret (0i64, queue_error) }
    let (queued, queued_error) = mem.alloc[u8](a, n)
    if queued_error != ok { ret (0i64, queued_error) }
    var i = 0usize
    while i < n {
        height[i] = 0u32
        excess[i] = 0i64
        queued[i] = 0u8
        i += 1usize
    }
    height[usize(net.source)] = u32(n)
    var head = 0usize
    var tail = 0usize
    let ring = n + 1usize
    // Saturate every arc out of the source.
    var arc = net.head[usize(net.source)]
    while arc != NONE {
        let c = net.capacity[usize(arc)]
        if c > 0i64 {
            let v = net.to[usize(arc)]
            net.capacity[usize(arc)] = 0i64
            net.capacity[usize(arc) ^ 1usize] += c
            excess[usize(v)] += c
            excess[usize(net.source)] -= c
            if v != net.sink && queued[usize(v)] == 0u8 {
                queue[tail] = v
                tail = (tail + 1usize) % ring
                queued[usize(v)] = 1u8
            }
        }
        arc = net.next[usize(arc)]
    }
    while head != tail {
        let u = queue[head]
        head = (head + 1usize) % ring
        queued[usize(u)] = 0u8
        // Discharge: push along admissible arcs, relabel when none remains.
        while excess[usize(u)] > 0i64 {
            var lowest = NONE
            var pushed_any = false
            arc = net.head[usize(u)]
            while arc != NONE && excess[usize(u)] > 0i64 {
                let v = net.to[usize(arc)]
                if net.capacity[usize(arc)] > 0i64 {
                    if height[usize(u)] == height[usize(v)] + 1u32 {
                        var amount = excess[usize(u)]
                        if net.capacity[usize(arc)] < amount { amount = net.capacity[usize(arc)] }
                        net.capacity[usize(arc)] -= amount
                        net.capacity[usize(arc) ^ 1usize] += amount
                        excess[usize(u)] -= amount
                        excess[usize(v)] += amount
                        pushed_any = true
                        if v != net.source && v != net.sink && queued[usize(v)] == 0u8 {
                            queue[tail] = v
                            tail = (tail + 1usize) % ring
                            queued[usize(v)] = 1u8
                        }
                    } else if lowest == NONE || height[usize(v)] < lowest {
                        lowest = height[usize(v)]
                    }
                }
                arc = net.next[usize(arc)]
            }
            if excess[usize(u)] > 0i64 && !pushed_any {
                if lowest == NONE { break }
                height[usize(u)] = lowest + 1u32
            }
        }
    }
    ret (excess[usize(net.sink)], ok)
}

// After a maximum flow: marks the nodes reachable from the source in the
// residual network (`side[i] = 1`), which is the source side of a minimum cut.
fn min_cut(a: *mem.Arena, net: *const Network, side: []u8) -> err {
    let n = net.nodes
    if side.len < n { ret InvalidNode }
    let (queue, queue_error) = mem.alloc[u32](a, n)
    if queue_error != ok { ret queue_error }
    var i = 0usize
    while i < n {
        side[i] = 0u8
        i += 1usize
    }
    var head = 0usize
    var tail = 1usize
    queue[0usize] = net.source
    side[usize(net.source)] = 1u8
    while head < tail {
        let u = queue[head]
        head += 1usize
        var arc = net.head[usize(u)]
        while arc != NONE {
            let v = net.to[usize(arc)]
            if net.capacity[usize(arc)] > 0i64 && side[usize(v)] == 0u8 {
                side[usize(v)] = 1u8
                queue[tail] = v
                tail += 1usize
            }
            arc = net.next[usize(arc)]
        }
    }
    ret ok
}

// The flow carried by input edge `k` (in the graph's edge order): the reverse
// arc's residual capacity.
fn edge_flow(net: *const Network, edge_index: usize) -> i64 {
    ret net.capacity[2usize * edge_index + 1usize]
}
