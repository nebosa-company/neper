// R igraph, the closed-form structure measures of a simple undirected graph given as a row-major 0/1 adjacency
// matrix: `transitivity` (global, local and average, isolates counted as zero), `coreness`,
// `assortativity_degree`, Jaccard and Dice `similarity`, `eccentricity`, `radius` and `diameter`.
//
// Not here: the directed variants, weights, cluster_walktrap, cluster_fast_greedy, cluster_infomap,
// cluster_optimal, motifs, triad_census, dominator_tree, bridges, gomory_hu_tree, connectivity, cohesive_blocks.

use e.math

fn degree(adj: []const f64, n: usize, v: usize) -> f64 {
    var d = 0.0f64
    var j = 0usize
    while j < n {
        if j != v { d += adj[v * n + j] }
        j += 1usize
    }
    ret d
}

// triangles through v
fn triangles(adj: []const f64, n: usize, v: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            if i != v && j != v && adj[v * n + i] != 0.0f64 && adj[v * n + j] != 0.0f64 && adj[i * n + j] != 0.0f64 { t += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    ret t
}

// global transitivity: 3 * triangles / connected triples
fn transitivity_global(adj: []const f64, n: usize) -> f64 {
    var tri = 0.0f64
    var trip = 0.0f64
    var v = 0usize
    while v < n {
        tri += triangles(adj, n, v)
        let d = degree(adj, n, v)
        trip += d * (d - 1.0f64) / 2.0f64
        v += 1usize
    }
    ret tri / trip
}

fn transitivity_local(adj: []const f64, n: usize, v: usize) -> f64 {
    let d = degree(adj, n, v)
    if d < 2.0f64 { ret 0.0f64 }
    ret triangles(adj, n, v) / (d * (d - 1.0f64) / 2.0f64)
}

fn transitivity_average(adj: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var v = 0usize
    while v < n {
        s += transitivity_local(adj, n, v)
        v += 1usize
    }
    ret s / f64(n)
}

// coreness of every vertex by repeated removal of the minimum-degree vertex; out has n slots
fn coreness(adj: []const f64, n: usize, out: []f64, deg: []f64, gone: []bool) {
    var v = 0usize
    while v < n {
        deg[v] = degree(adj, n, v)
        gone[v] = false
        v += 1usize
    }
    var k = 0.0f64
    var left = n
    while left > 0usize {
        var best = n
        v = 0usize
        while v < n {
            if !gone[v] && (best == n || deg[v] < deg[best]) { best = v }
            v += 1usize
        }
        if deg[best] > k { k = deg[best] }
        out[best] = k
        gone[best] = true
        var j = 0usize
        while j < n {
            if !gone[j] && j != best && adj[best * n + j] != 0.0f64 { deg[j] -= 1.0f64 }
            j += 1usize
        }
        left -= 1usize
    }
}

// degree assortativity: the Pearson correlation of the degrees at the two ends of every edge (both orientations)
fn assortativity_degree(adj: []const f64, n: usize) -> f64 {
    var m = 0.0f64
    var sx = 0.0f64
    var sxx = 0.0f64
    var sxy = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if i != j && adj[i * n + j] != 0.0f64 {
                let a = degree(adj, n, i)
                let b = degree(adj, n, j)
                m += 1.0f64
                sx += a
                sxx += a * a
                sxy += a * b
            }
            j += 1usize
        }
        i += 1usize
    }
    let mean = sx / m
    ret (sxy / m - mean * mean) / (sxx / m - mean * mean)
}

// neighbour-set similarity of i and j: dice false is Jaccard
fn similarity(adj: []const f64, n: usize, i: usize, j: usize, dice: bool) -> f64 {
    var both = 0.0f64
    var either = 0.0f64
    var ni = 0.0f64
    var nj = 0.0f64
    var k = 0usize
    while k < n {
        let a = k != i && adj[i * n + k] != 0.0f64
        let b = k != j && adj[j * n + k] != 0.0f64
        if a { ni += 1.0f64 }
        if b { nj += 1.0f64 }
        if a && b { both += 1.0f64 }
        if a || b { either += 1.0f64 }
        k += 1usize
    }
    if dice {
        if ni + nj == 0.0f64 { ret 0.0f64 }
        ret 2.0f64 * both / (ni + nj)
    }
    if either == 0.0f64 { ret 0.0f64 }
    ret both / either
}

// breadth-first distances from s into dist (-1 for unreachable)
fn distances(adj: []const f64, n: usize, s: usize, dist: []i64, queue: []usize) {
    var i = 0usize
    while i < n {
        dist[i] = 0i64 - 1i64
        i += 1usize
    }
    dist[s] = 0i64
    queue[0usize] = s
    var head = 0usize
    var tail = 1usize
    while head < tail {
        let u = queue[head]
        head += 1usize
        var j = 0usize
        while j < n {
            if j != u && adj[u * n + j] != 0.0f64 && dist[j] < 0i64 {
                dist[j] = dist[u] + 1i64
                queue[tail] = j
                tail += 1usize
            }
            j += 1usize
        }
    }
}

fn eccentricity(adj: []const f64, n: usize, v: usize, dist: []i64, queue: []usize) -> f64 {
    distances(adj, n, v, dist, queue)
    var best = 0i64
    var i = 0usize
    while i < n {
        if dist[i] > best { best = dist[i] }
        i += 1usize
    }
    ret f64(best)
}
