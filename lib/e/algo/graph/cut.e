// Global minimum cuts of undirected graphs. `stoer_wagner` works on a
// dense weight matrix (`n × n`, symmetric) in caller storage and answers
// the minimum cut weight and one side of it; `karger` contracts random
// edges of an `e.data.graph` graph (through the caller's PCG and a
// disjoint set over the arena) and answers the cut a run finds, which is
// the minimum with probability at least `2 / n(n - 1)` per run; `karger_best`
// keeps the best of several runs.

use e.algo.rand
use e.mem
use e.data.graph as graph

error TooSmall
error Invalid

// Stoer-Wagner over `w` (destroyed); `side` receives 1 for the nodes on the
// cut's smaller-indexed side. `scratch` needs `2 n` floats and `marks.len >= 2 n`.
fn stoer_wagner(w: []f64, n: usize, side: []u8, scratch: []f64, marks: []usize) -> (f64, err) {
    if w.len < n * n || side.len < n || scratch.len < 2usize * n || marks.len < 2usize * n { ret (0.0f64, TooSmall) }
    if n < 2usize { ret (0.0f64, Invalid) }
    var weight = scratch[..n]
    var merged_into = marks[..n]
    var added = marks[n..2usize * n]
    // Each node keeps a "group" bit list through merged_into: group[v] = v if alive.
    var i = 0usize
    while i < n {
        merged_into[i] = i
        side[i] = 0u8
        i += 1usize
    }
    var best = 0.0f64
    var have_best = false
    var alive = n
    var best_last = 0usize
    while alive > 1usize {
        // Maximum adjacency ordering among alive nodes.
        i = 0usize
        while i < n {
            weight[i] = 0.0f64
            added[i] = 0usize
            i += 1usize
        }
        var previous = n
        var last = n
        var step = 0usize
        while step < alive {
            var pick = n
            i = 0usize
            while i < n {
                if merged_into[i] == i && added[i] == 0usize && (pick == n || weight[i] > weight[pick]) { pick = i }
                i += 1usize
            }
            added[pick] = 1usize
            previous = last
            last = pick
            i = 0usize
            while i < n {
                if merged_into[i] == i && added[i] == 0usize { weight[i] += w[pick * n + i] }
                i += 1usize
            }
            step += 1usize
        }
        // The cut of the phase: `last` against the rest.
        let phase = weight[last]
        if !have_best || phase < best {
            best = phase
            have_best = true
            best_last = last
            // Record the side: every node merged into `last`.
            i = 0usize
            while i < n {
                var root = i
                while merged_into[root] != root { root = merged_into[root] }
                if root == last { side[i] = 1u8 } else { side[i] = 0u8 }
                i += 1usize
            }
        }
        // Merge last into previous.
        i = 0usize
        while i < n {
            w[previous * n + i] += w[last * n + i]
            w[i * n + previous] = w[previous * n + i]
            i += 1usize
        }
        w[previous * n + previous] = 0.0f64
        merged_into[last] = previous
        alive -= 1usize
    }
    ret (best, ok)
}

fn find(parent: []u32, v: u32) -> u32 {
    var r = v
    while parent[usize(r)] != r { r = parent[usize(r)] }
    var t = v
    while parent[usize(t)] != r {
        let next = parent[usize(t)]
        parent[usize(t)] = r
        t = next
    }
    ret r
}

// One Karger run: edges (each undirected edge once, `from < to`) in a
// random order are contracted until two groups remain; `side` receives
// the group of each node (0 or 1). Answers the crossing edge count.
fn karger[E: type](a: *mem.Arena, g: *const graph.Graph[E], r: *rand.Pcg64, side: []u8) -> (usize, err) {
    let n = graph.node_count[E](g)
    if side.len < n { ret (0usize, TooSmall) }
    if n < 2usize { ret (0usize, Invalid) }
    let (parent, parent_error) = mem.alloc[u32](a, n)
    if parent_error != ok { ret (0usize, parent_error) }
    let (order, order_error) = mem.alloc[usize](a, g.edges.len)
    if order_error != ok { ret (0usize, order_error) }
    var i = 0usize
    while i < n {
        parent[i] = u32(i)
        i += 1usize
    }
    var m = 0usize
    i = 0usize
    while i < g.edges.len {
        if g.edges[i].from < g.edges[i].to {
            order[m] = i
            m += 1usize
        }
        i += 1usize
    }
    // Fisher-Yates.
    i = m
    while i > 1usize {
        let j = usize(rand.pcg64_bounded(r, u64(i)))
        let t = order[i - 1usize]
        order[i - 1usize] = order[j]
        order[j] = t
        i -= 1usize
    }
    var groups = n
    i = 0usize
    while i < m && groups > 2usize {
        let e = g.edges[order[i]]
        let ra = find(parent, e.from)
        let rb = find(parent, e.to)
        if ra != rb {
            parent[usize(rb)] = ra
            groups -= 1usize
        }
        i += 1usize
    }
    if groups > 2usize { ret (0usize, Invalid) }
    let first = find(parent, 0u32)
    i = 0usize
    while i < n {
        if find(parent, u32(i)) == first { side[i] = 0u8 } else { side[i] = 1u8 }
        i += 1usize
    }
    var crossing = 0usize
    i = 0usize
    while i < g.edges.len {
        let e = g.edges[i]
        if e.from < e.to && side[usize(e.from)] != side[usize(e.to)] { crossing += 1usize }
        i += 1usize
    }
    ret (crossing, ok)
}

// The best cut of `runs` Karger runs; `best_side` keeps its sides,
// `side` is scratch for each run.
fn karger_best[E: type](a: *mem.Arena, g: *const graph.Graph[E], runs: usize, r: *rand.Pcg64, best_side: []u8, side: []u8) -> (usize, err) {
    let n = graph.node_count[E](g)
    if best_side.len < n { ret (0usize, TooSmall) }
    var best = 0usize
    var have = false
    var run = 0usize
    while run < runs {
        let (cut, run_error) = karger[E](a, g, r, side)
        if run_error != ok { ret (0usize, run_error) }
        if !have || cut < best {
            best = cut
            have = true
            var i = 0usize
            while i < n {
                best_side[i] = side[i]
                i += 1usize
            }
        }
        run += 1usize
    }
    ret (best, ok)
}
