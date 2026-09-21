// Node centralities over `e.data.graph` in caller storage: PageRank by
// power iteration with a damping factor (dangling mass spread evenly),
// HITS hub and authority scores, eigenvector centrality by power
// iteration on the adjacency (undirected graphs), closeness as the
// reciprocal of the mean hop distance to reachable nodes, and betweenness
// by Brandes' algorithm over unweighted shortest paths (normalised for an
// undirected graph by halving).

use e.data.graph as graph

error TooSmall
error Invalid

fn out_degree[E: type](g: *const graph.Graph[E], v: usize) -> usize { ret g.offsets[v + 1usize] - g.offsets[v] }

// PageRank with damping `d` until the largest change is under `tolerance`
// or `max_iterations`; `scores` receives the distribution (summing to 1),
// `scratch.len >= n`. Answers the iterations.
fn pagerank[E: type](g: *const graph.Graph[E], damping: f64, tolerance: f64, max_iterations: u32, scores: []f64, scratch: []f64) -> (u32, err) {
    let n = graph.node_count[E](g)
    if scores.len < n || scratch.len < n { ret (0u32, TooSmall) }
    if n == 0usize || damping < 0.0f64 || damping > 1.0f64 { ret (0u32, Invalid) }
    var i = 0usize
    while i < n {
        scores[i] = 1.0f64 / f64(n)
        i += 1usize
    }
    var iteration = 0u32
    var settled = false
    while iteration < max_iterations && !settled {
        var dangling = 0.0f64
        i = 0usize
        while i < n {
            scratch[i] = 0.0f64
            if out_degree[E](g, i) == 0usize { dangling += scores[i] }
            i += 1usize
        }
        i = 0usize
        while i < n {
            let degree = out_degree[E](g, i)
            if degree > 0usize {
                var e = g.offsets[i]
                while e < g.offsets[i + 1usize] {
                    scratch[usize(g.edges[e].to)] += scores[i] / f64(degree)
                    e += 1usize
                }
            }
            i += 1usize
        }
        var change = 0.0f64
        i = 0usize
        while i < n {
            let fresh = (1.0f64 - damping) / f64(n) + damping * (scratch[i] + dangling / f64(n))
            var d = fresh - scores[i]
            if d < 0.0f64 { d = 0.0f64 - d }
            if d > change { change = d }
            scores[i] = fresh
            i += 1usize
        }
        iteration += 1u32
        if change < tolerance { settled = true }
    }
    ret (iteration, ok)
}

fn normalise(v: []f64) {
    var total = 0.0f64
    var i = 0usize
    while i < v.len {
        total += v[i] * v[i]
        i += 1usize
    }
    if total > 0.0f64 {
        let scale = 1.0f64 / sqrt(total)
        i = 0usize
        while i < v.len {
            v[i] = v[i] * scale
            i += 1usize
        }
    }
}

fn sqrt(x: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    var r = x
    var k = 0usize
    while k < 60usize {
        r = 0.5f64 * (r + x / r)
        k += 1usize
    }
    ret r
}

// HITS: `authority` and `hub` (unit length each) by alternating updates
// until the largest change is under `tolerance` or `max_iterations`.
fn hits[E: type](g: *const graph.Graph[E], tolerance: f64, max_iterations: u32, authority: []f64, hub: []f64) -> (u32, err) {
    let n = graph.node_count[E](g)
    if authority.len < n || hub.len < n { ret (0u32, TooSmall) }
    if n == 0usize { ret (0u32, Invalid) }
    var i = 0usize
    while i < n {
        authority[i] = 1.0f64
        hub[i] = 1.0f64
        i += 1usize
    }
    normalise(authority[..n])
    normalise(hub[..n])
    var iteration = 0u32
    var settled = false
    while iteration < max_iterations && !settled {
        // authority = Aᵀ hub, hub = A authority.
        var change = 0.0f64
        i = 0usize
        while i < n {
            authority[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            var e = g.offsets[i]
            while e < g.offsets[i + 1usize] {
                authority[usize(g.edges[e].to)] += hub[i]
                e += 1usize
            }
            i += 1usize
        }
        normalise(authority[..n])
        i = 0usize
        while i < n {
            var s = 0.0f64
            var e = g.offsets[i]
            while e < g.offsets[i + 1usize] {
                s += authority[usize(g.edges[e].to)]
                e += 1usize
            }
            var d = s - hub[i]
            hub[i] = s
            if d < 0.0f64 { d = 0.0f64 - d }
            if d > change { change = d }
            i += 1usize
        }
        normalise(hub[..n])
        iteration += 1u32
        if change < tolerance { settled = true }
    }
    ret (iteration, ok)
}

// Eigenvector centrality by power iteration on the adjacency, unit length;
// `scratch.len >= n`.
fn eigenvector[E: type](g: *const graph.Graph[E], tolerance: f64, max_iterations: u32, scores: []f64, scratch: []f64) -> (u32, err) {
    let n = graph.node_count[E](g)
    if scores.len < n || scratch.len < n { ret (0u32, TooSmall) }
    if n == 0usize { ret (0u32, Invalid) }
    var i = 0usize
    while i < n {
        scores[i] = 1.0f64
        i += 1usize
    }
    normalise(scores[..n])
    var iteration = 0u32
    var settled = false
    while iteration < max_iterations && !settled {
        i = 0usize
        while i < n {
            var s = 0.0f64
            var e = g.offsets[i]
            while e < g.offsets[i + 1usize] {
                s += scores[usize(g.edges[e].to)]
                e += 1usize
            }
            scratch[i] = s
            i += 1usize
        }
        normalise(scratch[..n])
        var change = 0.0f64
        i = 0usize
        while i < n {
            var d = scratch[i] - scores[i]
            if d < 0.0f64 { d = 0.0f64 - d }
            if d > change { change = d }
            scores[i] = scratch[i]
            i += 1usize
        }
        iteration += 1u32
        if change < tolerance { settled = true }
    }
    ret (iteration, ok)
}

// Closeness of every node: `(reached) / (sum of hop distances)` over the nodes
// it reaches (0 when it reaches none); `queue.len >= n`, `distance.len >= n`.
fn closeness[E: type](g: *const graph.Graph[E], scores: []f64, queue: []u32, distance: []u32) -> err {
    let n = graph.node_count[E](g)
    if scores.len < n || queue.len < n || distance.len < n { ret TooSmall }
    var s = 0usize
    while s < n {
        var i = 0usize
        while i < n {
            distance[i] = graph.NONE
            i += 1usize
        }
        distance[s] = 0u32
        queue[0usize] = u32(s)
        var head = 0usize
        var tail = 1usize
        var total = 0u64
        var reached = 0usize
        while head < tail {
            let v = usize(queue[head])
            head += 1usize
            var e = g.offsets[v]
            while e < g.offsets[v + 1usize] {
                let w = usize(g.edges[e].to)
                if distance[w] == graph.NONE {
                    distance[w] = distance[v] + 1u32
                    total += u64(distance[w])
                    reached += 1usize
                    queue[tail] = u32(w)
                    tail += 1usize
                }
                e += 1usize
            }
        }
        if total > 0u64 { scores[s] = f64(reached) / f64(total) } else { scores[s] = 0.0f64 }
        s += 1usize
    }
    ret ok
}

// Betweenness by Brandes over hop distances; for an undirected graph the
// raw scores count each pair twice, so `halve` divides them. Storage:
// `order.len >= n`, `distance.len >= n`, `sigma.len >= n`, `delta.len >= n`,
// `first_pred.len >= n`, `pred.len >= edges`, `next_pred.len >= edges`.
fn betweenness[E: type](g: *const graph.Graph[E], halve: bool, scores: []f64, order: []u32, distance: []u32, sigma: []f64, delta: []f64, first_pred: []u32, pred: []u32, next_pred: []u32) -> err {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    if scores.len < n || order.len < n || distance.len < n || sigma.len < n || delta.len < n || first_pred.len < n || pred.len < m || next_pred.len < m { ret TooSmall }
    var i = 0usize
    while i < n {
        scores[i] = 0.0f64
        i += 1usize
    }
    var s = 0usize
    while s < n {
        i = 0usize
        while i < n {
            distance[i] = graph.NONE
            sigma[i] = 0.0f64
            delta[i] = 0.0f64
            first_pred[i] = graph.NONE
            i += 1usize
        }
        var preds = 0usize
        distance[s] = 0u32
        sigma[s] = 1.0f64
        order[0usize] = u32(s)
        var head = 0usize
        var tail = 1usize
        while head < tail {
            let v = usize(order[head])
            head += 1usize
            var e = g.offsets[v]
            while e < g.offsets[v + 1usize] {
                let w = usize(g.edges[e].to)
                if distance[w] == graph.NONE {
                    distance[w] = distance[v] + 1u32
                    order[tail] = u32(w)
                    tail += 1usize
                }
                if distance[w] == distance[v] + 1u32 {
                    sigma[w] += sigma[v]
                    pred[preds] = u32(v)
                    next_pred[preds] = first_pred[w]
                    first_pred[w] = u32(preds)
                    preds += 1usize
                }
                e += 1usize
            }
        }
        // Accumulate dependencies in reverse order of discovery.
        while tail > 0usize {
            tail -= 1usize
            let w = usize(order[tail])
            var p = first_pred[w]
            while p != graph.NONE {
                let v = usize(pred[usize(p)])
                delta[v] += sigma[v] / sigma[w] * (1.0f64 + delta[w])
                p = next_pred[usize(p)]
            }
            if w != s { scores[w] += delta[w] }
        }
        s += 1usize
    }
    if halve {
        i = 0usize
        while i < n {
            scores[i] = scores[i] * 0.5f64
            i += 1usize
        }
    }
    ret ok
}
