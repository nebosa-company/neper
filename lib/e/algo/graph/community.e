// Community detection on undirected `e.data.graph` graphs (every edge in
// both lists, unit weights): `label_propagation` (each node takes its
// neighbours' most frequent label until nothing changes), `louvain` (local
// moving to the neighbouring community with the best modularity gain,
// then aggregation over a dense community matrix, repeated while the
// modularity improves) and `girvan_newman` (the edge of highest
// betweenness removed until the graph gains a component) and `leiden`
// (Louvain's moves followed by a refinement into well-connected
// sub-communities before each aggregation). `modularity` scores any partition. Communities are labels per node; the caller's
// arena holds the working sets.

use e.mem
use e.data.graph as graph

error TooSmall
error Invalid

fn degree[E: type](g: *const graph.Graph[E], v: usize) -> usize { ret g.offsets[v + 1usize] - g.offsets[v] }

// Modularity of `labels` (`m` = undirected edge count = edges / 2).
fn modularity[E: type](g: *const graph.Graph[E], labels: []const u32) -> f64 {
    let n = graph.node_count[E](g)
    let two_m = f64(g.edges.len)
    if two_m == 0.0f64 { ret 0.0f64 }
    // Σ over pairs of one community of A_vw - k_v k_w / 2m, all over 2m.
    var q = 0.0f64
    var v = 0usize
    while v < n {
        var e = g.offsets[v]
        while e < g.offsets[v + 1usize] {
            if labels[v] == labels[usize(g.edges[e].to)] { q += 1.0f64 }
            e += 1usize
        }
        var w = 0usize
        while w < n {
            if labels[v] == labels[w] { q -= f64(degree[E](g, v)) * f64(degree[E](g, w)) / two_m }
            w += 1usize
        }
        v += 1usize
    }
    ret q / two_m
}

// Label propagation from singleton labels until a full sweep changes
// nothing or `max_sweeps` pass; ties go to the smallest label. `counts.len >= n`.
// Answers the sweeps.
fn label_propagation[E: type](g: *const graph.Graph[E], labels: []u32, counts: []usize, max_sweeps: u32) -> (u32, err) {
    let n = graph.node_count[E](g)
    if labels.len < n || counts.len < n { ret (0u32, TooSmall) }
    var i = 0usize
    while i < n {
        labels[i] = u32(i)
        counts[i] = 0usize
        i += 1usize
    }
    var sweeps = 0u32
    var changed = true
    while changed && sweeps < max_sweeps {
        changed = false
        var v = 0usize
        while v < n {
            // Count neighbouring labels (labels are node ids, so counts is indexed by them).
            var e = g.offsets[v]
            while e < g.offsets[v + 1usize] {
                counts[usize(labels[usize(g.edges[e].to)])] += 1usize
                e += 1usize
            }
            var best = labels[v]
            var best_count = 0usize
            e = g.offsets[v]
            while e < g.offsets[v + 1usize] {
                let l = labels[usize(g.edges[e].to)]
                let c = counts[usize(l)]
                if c > best_count || (c == best_count && l < best) {
                    best = l
                    best_count = c
                }
                e += 1usize
            }
            e = g.offsets[v]
            while e < g.offsets[v + 1usize] {
                counts[usize(labels[usize(g.edges[e].to)])] = 0usize
                e += 1usize
            }
            if best_count > 0usize && best != labels[v] {
                labels[v] = best
                changed = true
            }
            v += 1usize
        }
        sweeps += 1u32
    }
    ret (sweeps, ok)
}

// Relabel to 0..k by first appearance; answers k.
fn compact(labels: []u32, n: usize, map: []u32) -> usize {
    var i = 0usize
    while i < n {
        map[i] = graph.NONE
        i += 1usize
    }
    var k = 0u32
    i = 0usize
    while i < n {
        if map[usize(labels[i])] == graph.NONE {
            map[usize(labels[i])] = k
            k += 1u32
        }
        labels[i] = map[usize(labels[i])]
        i += 1usize
    }
    ret usize(k)
}

// Louvain over a dense weighted matrix `w` (`k × k`, symmetric, self loops
// on the diagonal counted once) with node strengths `strength`; moves
// nodes between communities while the modularity gain is positive.
// `community` is in/out; answers whether anything moved.
fn local_moving(w: []const f64, strength: []const f64, k: usize, two_m: f64, community: []u32, total: []f64, link: []f64) -> bool {
    var c = 0usize
    while c < k {
        total[c] = 0.0f64
        c += 1usize
    }
    var i = 0usize
    while i < k {
        total[usize(community[i])] += strength[i]
        i += 1usize
    }
    var moved = false
    var improving = true
    while improving {
        improving = false
        i = 0usize
        while i < k {
            // Weight from i to each community.
            c = 0usize
            while c < k {
                link[c] = 0.0f64
                c += 1usize
            }
            var j = 0usize
            while j < k {
                if j != i { link[usize(community[j])] += w[i * k + j] }
                j += 1usize
            }
            let own = usize(community[i])
            total[own] -= strength[i]
            var best = own
            var best_gain = link[own] - total[own] * strength[i] / two_m
            c = 0usize
            while c < k {
                if c != own && link[c] > 0.0f64 {
                    let gain = link[c] - total[c] * strength[i] / two_m
                    if gain > best_gain + 1.0e-12f64 {
                        best_gain = gain
                        best = c
                    }
                }
                c += 1usize
            }
            total[best] += strength[i]
            if best != own {
                community[i] = u32(best)
                moved = true
                improving = true
            }
            i += 1usize
        }
    }
    ret moved
}

// Louvain; `labels` receives a community per node (compacted to 0..k) and
// the modularity is answered. The arena holds the dense matrices.
fn louvain[E: type](a: *mem.Arena, g: *const graph.Graph[E], labels: []u32) -> (f64, err) {
    let n = graph.node_count[E](g)
    if labels.len < n { ret (0.0f64, TooSmall) }
    if n == 0usize { ret (0.0f64, ok) }
    let two_m = f64(g.edges.len)
    if two_m == 0.0f64 {
        var i = 0usize
        while i < n {
            labels[i] = u32(i)
            i += 1usize
        }
        ret (0.0f64, ok)
    }
    let (w, w_error) = mem.alloc[f64](a, n * n)
    if w_error != ok { ret (0.0f64, w_error) }
    let (next, next_error) = mem.alloc[f64](a, n * n)
    if next_error != ok { ret (0.0f64, next_error) }
    let (strength, strength_error) = mem.alloc[f64](a, n)
    if strength_error != ok { ret (0.0f64, strength_error) }
    let (community, community_error) = mem.alloc[u32](a, n)
    if community_error != ok { ret (0.0f64, community_error) }
    let (total, total_error) = mem.alloc[f64](a, n)
    if total_error != ok { ret (0.0f64, total_error) }
    let (link, link_error) = mem.alloc[f64](a, n)
    if link_error != ok { ret (0.0f64, link_error) }
    let (map, map_error) = mem.alloc[u32](a, n)
    if map_error != ok { ret (0.0f64, map_error) }
    var i = 0usize
    while i < n * n {
        w[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var e = g.offsets[i]
        while e < g.offsets[i + 1usize] {
            w[i * n + usize(g.edges[e].to)] += 1.0f64
            e += 1usize
        }
        labels[i] = u32(i)
        i += 1usize
    }
    var k = n
    var levels = 0usize
    var progressing = true
    while progressing && levels < 64usize {
        i = 0usize
        while i < k {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += w[i * k + j]
                j += 1usize
            }
            strength[i] = s
            community[i] = u32(i)
            i += 1usize
        }
        progressing = local_moving(w, strength, k, two_m, community, total, link)
        if progressing {
            let fresh = compact(community, k, map)
            // Every node's label follows its aggregate's community.
            i = 0usize
            while i < n {
                labels[i] = community[usize(labels[i])]
                i += 1usize
            }
            // Aggregate the matrix.
            i = 0usize
            while i < fresh * fresh {
                next[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < k {
                var j = 0usize
                while j < k {
                    next[usize(community[i]) * fresh + usize(community[j])] += w[i * k + j]
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < fresh * fresh {
                w[i] = next[i]
                i += 1usize
            }
            k = fresh
            levels += 1usize
        }
    }
    ret (modularity[E](g, labels), ok)
}

// Edge betweenness of every edge (indexed like `g.edges`, both copies of an
// undirected edge receiving the pair's value, each unordered pair once) into `scores`; the other arrays
// are Brandes scratch: `order.len >= n`, `distance.len >= n`, `sigma.len >= n`,
// `delta.len >= n`. Removed edges (`removed[e] != 0`) are skipped.
fn edge_betweenness[E: type](g: *const graph.Graph[E], removed: []const u8, scores: []f64, order: []u32, distance: []u32, sigma: []f64, delta: []f64) -> err {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    if removed.len < m || scores.len < m || order.len < n || distance.len < n || sigma.len < n || delta.len < n { ret TooSmall }
    var i = 0usize
    while i < m {
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
            i += 1usize
        }
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
                if removed[e] == 0u8 {
                    let w = usize(g.edges[e].to)
                    if distance[w] == graph.NONE {
                        distance[w] = distance[v] + 1u32
                        order[tail] = u32(w)
                        tail += 1usize
                    }
                    if distance[w] == distance[v] + 1u32 { sigma[w] += sigma[v] }
                }
                e += 1usize
            }
        }
        // Dependencies flow back along the edges into each node from its predecessors.
        while tail > 0usize {
            tail -= 1usize
            let w = usize(order[tail])
            var e = g.offsets[w]
            while e < g.offsets[w + 1usize] {
                if removed[e] == 0u8 {
                    let v = usize(g.edges[e].to)
                    if distance[v] != graph.NONE && distance[v] + 1u32 == distance[w] {
                        let share = sigma[v] / sigma[w] * (1.0f64 + delta[w])
                        delta[v] += share
                        scores[e] += share
                    }
                }
                e += 1usize
            }
        }
        s += 1usize
    }
    // Both copies of an undirected edge carry the pair's total.
    var v = 0usize
    while v < n {
        var e = g.offsets[v]
        while e < g.offsets[v + 1usize] {
            let w = usize(g.edges[e].to)
            if v < w {
                // Find the twin w -> v.
                var f = g.offsets[w]
                var twin = m
                while f < g.offsets[w + 1usize] && twin == m {
                    if usize(g.edges[f].to) == v && removed[f] == 0u8 { twin = f }
                    f += 1usize
                }
                if twin != m {
                    // Both directions of every source pair were counted: halve, as
                    // NetworkX does for an undirected graph.
                    let both = 0.5f64 * (scores[e] + scores[twin])
                    scores[e] = both
                    scores[twin] = both
                }
            }
            e += 1usize
        }
        v += 1usize
    }
    ret ok
}

// Components of the graph without the removed edges; answers the count.
fn components[E: type](g: *const graph.Graph[E], removed: []const u8, labels: []u32, stack: []u32) -> usize {
    let n = graph.node_count[E](g)
    var i = 0usize
    while i < n {
        labels[i] = graph.NONE
        i += 1usize
    }
    var count = 0u32
    i = 0usize
    while i < n {
        if labels[i] == graph.NONE {
            labels[i] = count
            stack[0usize] = u32(i)
            var top = 1usize
            while top > 0usize {
                top -= 1usize
                let v = usize(stack[top])
                var e = g.offsets[v]
                while e < g.offsets[v + 1usize] {
                    let w = usize(g.edges[e].to)
                    if removed[e] == 0u8 && labels[w] == graph.NONE {
                        labels[w] = count
                        stack[top] = u32(w)
                        top += 1usize
                    }
                    e += 1usize
                }
            }
            count += 1u32
        }
        i += 1usize
    }
    ret usize(count)
}

// Girvan-Newman: remove the edge of highest betweenness until the graph
// gains a component beyond `start` components; `removed` marks the edges
// taken out, `labels` the components. Answers the removals.
// Storage: `removed.len >= edges`, `scores.len >= edges`, `labels.len >= n`,
// `order.len >= n`, `distance.len >= n`, `sigma.len >= n`, `delta.len >= n`.
fn girvan_newman[E: type](g: *const graph.Graph[E], removed: []u8, scores: []f64, labels: []u32, order: []u32, distance: []u32, sigma: []f64, delta: []f64) -> (usize, err) {
    let n = graph.node_count[E](g)
    let m = g.edges.len
    if removed.len < m || labels.len < n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < m {
        removed[i] = 0u8
        i += 1usize
    }
    let start = components[E](g, removed, labels, order)
    var removals = 0usize
    var count = start
    while count == start && removals < m {
        let score_error = edge_betweenness[E](g, removed, scores, order, distance, sigma, delta)
        if score_error != ok { ret (removals, score_error) }
        var best = m
        i = 0usize
        while i < m {
            if removed[i] == 0u8 && (best == m || scores[i] > scores[best]) { best = i }
            i += 1usize
        }
        if best == m { ret (removals, ok) }
        // Remove both copies.
        removed[best] = 1u8
        let v = usize(g.edges[best].to)
        var from = 0usize
        var u = 0usize
        while u < n {
            if g.offsets[u] <= best && best < g.offsets[u + 1usize] { from = u }
            u += 1usize
        }
        var f = g.offsets[v]
        while f < g.offsets[v + 1usize] {
            if usize(g.edges[f].to) == from && removed[f] == 0u8 {
                removed[f] = 1u8
                f = g.offsets[v + 1usize]
            } else {
                f += 1usize
            }
        }
        removals += 1usize
        count = components[E](g, removed, labels, order)
    }
    ret (removals, ok)
}

// Leiden refinement over the aggregate matrix: every node starts alone and,
// walking the nodes in id order, a node still alone joins the sub-community of
// its own community with the best modularity gain, provided the node and the
// candidate are both well connected to the community (Traag et al. 2019,
// resolution 1 / 2m). The paper's random choice is replaced by the best gain,
// ties to the lowest id. `refined[i]` is the representative node of `i`'s
// sub-community; answers the merges.
fn refine(w: []const f64, strength: []const f64, k: usize, two_m: f64, community: []const u32, refined: []u32, rtotal: []f64, rcount: []u32, ctotal: []f64, link: []f64) -> usize {
    var i = 0usize
    while i < k {
        refined[i] = u32(i)
        rtotal[i] = strength[i]
        rcount[i] = 1u32
        ctotal[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        ctotal[usize(community[i])] += strength[i]
        i += 1usize
    }
    var merges = 0usize
    var v = 0usize
    while v < k {
        if refined[v] != u32(v) || rcount[v] != 1u32 {
            v += 1usize
            continue
        }
        let s = community[v]
        var to_s = 0.0f64
        var c = 0usize
        while c < k {
            link[c] = 0.0f64
            c += 1usize
        }
        var j = 0usize
        while j < k {
            if j != v && community[j] == s {
                link[usize(refined[j])] += w[v * k + j]
                to_s += w[v * k + j]
            }
            j += 1usize
        }
        if to_s >= strength[v] * (ctotal[usize(s)] - strength[v]) / two_m {
            var best = k
            var best_gain = 0.0f64
            c = 0usize
            while c < k {
                if c != v && link[c] > 0.0f64 && refined[c] == u32(c) && community[c] == s {
                    // The candidate's links leaving it but staying inside the community.
                    var out = 0.0f64
                    i = 0usize
                    while i < k {
                        if refined[i] == u32(c) {
                            j = 0usize
                            while j < k {
                                if community[j] == s && refined[j] != u32(c) { out += w[i * k + j] }
                                j += 1usize
                            }
                        }
                        i += 1usize
                    }
                    if out >= rtotal[c] * (ctotal[usize(s)] - rtotal[c]) / two_m {
                        let gain = link[c] - rtotal[c] * strength[v] / two_m
                        if gain > best_gain + 1.0e-12f64 {
                            best_gain = gain
                            best = c
                        }
                    }
                }
                c += 1usize
            }
            if best != k {
                refined[v] = u32(best)
                rtotal[best] += strength[v]
                rcount[best] += 1u32
                merges += 1usize
            }
        }
        v += 1usize
    }
    ret merges
}

// Leiden (Traag, Waltman & van Eck 2019) over the same dense matrices as
// `louvain`: local moving, refinement of every community into well-connected
// sub-communities (`refine`), aggregation over the refined partition with the
// unrefined partition carried over as the start of the next level, until the
// refinement merges nothing or every aggregate node stands alone. Every
// choice is deterministic (best gain, ties to the lowest id). `labels`
// receives a community per node (0..k) and the modularity is answered.
fn leiden[E: type](a: *mem.Arena, g: *const graph.Graph[E], labels: []u32) -> (f64, err) {
    let n = graph.node_count[E](g)
    if labels.len < n { ret (0.0f64, TooSmall) }
    if n == 0usize { ret (0.0f64, ok) }
    let two_m = f64(g.edges.len)
    var i = 0usize
    if two_m == 0.0f64 {
        while i < n {
            labels[i] = u32(i)
            i += 1usize
        }
        ret (0.0f64, ok)
    }
    let (w, w_error) = mem.alloc[f64](a, n * n)
    if w_error != ok { ret (0.0f64, w_error) }
    let (next, next_error) = mem.alloc[f64](a, n * n)
    if next_error != ok { ret (0.0f64, next_error) }
    let (strength, strength_error) = mem.alloc[f64](a, n)
    if strength_error != ok { ret (0.0f64, strength_error) }
    let (community, community_error) = mem.alloc[u32](a, n)
    if community_error != ok { ret (0.0f64, community_error) }
    let (total, total_error) = mem.alloc[f64](a, n)
    if total_error != ok { ret (0.0f64, total_error) }
    let (link, link_error) = mem.alloc[f64](a, n)
    if link_error != ok { ret (0.0f64, link_error) }
    let (map, map_error) = mem.alloc[u32](a, n)
    if map_error != ok { ret (0.0f64, map_error) }
    let (refined, refined_error) = mem.alloc[u32](a, n)
    if refined_error != ok { ret (0.0f64, refined_error) }
    let (rtotal, rtotal_error) = mem.alloc[f64](a, n)
    if rtotal_error != ok { ret (0.0f64, rtotal_error) }
    let (rcount, rcount_error) = mem.alloc[u32](a, n)
    if rcount_error != ok { ret (0.0f64, rcount_error) }
    let (ctotal, ctotal_error) = mem.alloc[f64](a, n)
    if ctotal_error != ok { ret (0.0f64, ctotal_error) }
    let (member, member_error) = mem.alloc[u32](a, n)
    if member_error != ok { ret (0.0f64, member_error) }
    i = 0usize
    while i < n * n {
        w[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var e = g.offsets[i]
        while e < g.offsets[i + 1usize] {
            w[i * n + usize(g.edges[e].to)] += 1.0f64
            e += 1usize
        }
        member[i] = u32(i)
        community[i] = u32(i)
        i += 1usize
    }
    var k = n
    var levels = 0usize
    var progressing = true
    while progressing && levels < 64usize {
        i = 0usize
        while i < k {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += w[i * k + j]
                j += 1usize
            }
            strength[i] = s
            i += 1usize
        }
        let _ = local_moving(w, strength, k, two_m, community, total, link)
        let count = compact(community, k, map)
        if count == k {
            progressing = false
        } else {
            let merges = refine(w, strength, k, two_m, community, refined, rtotal, rcount, ctotal, link)
            if merges == 0usize {
                progressing = false
            } else {
                let fresh = compact(refined, k, map)
                // The aggregate node of each sub-community inherits its members' community.
                i = 0usize
                while i < k {
                    map[usize(refined[i])] = community[i]
                    i += 1usize
                }
                i = 0usize
                while i < fresh {
                    community[i] = map[i]
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    member[i] = refined[usize(member[i])]
                    i += 1usize
                }
                i = 0usize
                while i < fresh * fresh {
                    next[i] = 0.0f64
                    i += 1usize
                }
                i = 0usize
                while i < k {
                    var j = 0usize
                    while j < k {
                        next[usize(refined[i]) * fresh + usize(refined[j])] += w[i * k + j]
                        j += 1usize
                    }
                    i += 1usize
                }
                i = 0usize
                while i < fresh * fresh {
                    w[i] = next[i]
                    i += 1usize
                }
                k = fresh
                levels += 1usize
            }
        }
    }
    i = 0usize
    while i < n {
        labels[i] = community[usize(member[i])]
        i += 1usize
    }
    let _ = compact(labels, n, map)
    ret (modularity[E](g, labels), ok)
}
