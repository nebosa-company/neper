// Vertex colouring of undirected `e.data.graph` graphs in caller storage:
// `greedy` is Welsh-Powell (nodes by falling degree, each taking the
// smallest colour no neighbour has) and `dsatur` picks the node with the
// most distinct neighbouring colours next (ties by degree). Both answer
// the colour count; `is_proper` checks a colouring.

use e.data.graph as graph

error TooSmall

fn degree[E: type](g: *const graph.Graph[E], v: usize) -> usize { ret g.offsets[v + 1usize] - g.offsets[v] }

// The smallest colour unused by `v`'s coloured neighbours; `used.len >= n + 1`
// is a scratch of stamps (the current node's index + 1).
fn smallest_free[E: type](g: *const graph.Graph[E], v: usize, colors: []const u32, used: []usize, stamp: usize) -> u32 {
    var e = g.offsets[v]
    while e < g.offsets[v + 1usize] {
        let w = usize(g.edges[e].to)
        if colors[w] != graph.NONE { used[usize(colors[w])] = stamp }
        e += 1usize
    }
    var c = 0u32
    while used[usize(c)] == stamp { c += 1u32 }
    ret c
}

// Welsh-Powell; `colors` receives a colour per node, `order.len >= n`,
// `used.len >= n + 1`.
fn greedy[E: type](g: *const graph.Graph[E], colors: []u32, order: []usize, used: []usize) -> (usize, err) {
    let n = graph.node_count[E](g)
    if colors.len < n || order.len < n || used.len < n + 1usize { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        colors[i] = graph.NONE
        order[i] = i
        used[i] = 0usize
        i += 1usize
    }
    used[n] = 0usize
    // Insertion sort by falling degree, ties by index.
    i = 1usize
    while i < n {
        let v = order[i]
        var k = i
        while k > 0usize && degree[E](g, order[k - 1usize]) < degree[E](g, v) {
            order[k] = order[k - 1usize]
            k -= 1usize
        }
        order[k] = v
        i += 1usize
    }
    var count = 0usize
    i = 0usize
    while i < n {
        let v = order[i]
        let c = smallest_free[E](g, v, colors, used, i + 1usize)
        colors[v] = c
        if usize(c) + 1usize > count { count = usize(c) + 1usize }
        i += 1usize
    }
    ret (count, ok)
}

// DSATUR; `saturation.len >= n` counts distinct neighbouring colours,
// `used.len >= n + 1` is scratch.
fn dsatur[E: type](g: *const graph.Graph[E], colors: []u32, saturation: []usize, used: []usize) -> (usize, err) {
    let n = graph.node_count[E](g)
    if colors.len < n || saturation.len < n || used.len < n + 1usize { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        colors[i] = graph.NONE
        saturation[i] = 0usize
        used[i] = 0usize
        i += 1usize
    }
    used[n] = 0usize
    var count = 0usize
    var done = 0usize
    while done < n {
        // The uncoloured node with the largest saturation, then degree.
        var pick = n
        i = 0usize
        while i < n {
            if colors[i] == graph.NONE {
                if pick == n || saturation[i] > saturation[pick] || (saturation[i] == saturation[pick] && degree[E](g, i) > degree[E](g, pick)) { pick = i }
            }
            i += 1usize
        }
        let c = smallest_free[E](g, pick, colors, used, done + 1usize)
        colors[pick] = c
        if usize(c) + 1usize > count { count = usize(c) + 1usize }
        // Neighbours gain saturation when this colour is new to them.
        var e = g.offsets[pick]
        while e < g.offsets[pick + 1usize] {
            let w = usize(g.edges[e].to)
            if colors[w] == graph.NONE {
                var seen = false
                var f = g.offsets[w]
                while f < g.offsets[w + 1usize] && !seen {
                    let u = usize(g.edges[f].to)
                    if u != pick && colors[u] == c { seen = true }
                    f += 1usize
                }
                if !seen { saturation[w] += 1usize }
            }
            e += 1usize
        }
        done += 1usize
    }
    ret (count, ok)
}

// Does no edge join two nodes of one colour?
fn is_proper[E: type](g: *const graph.Graph[E], colors: []const u32) -> bool {
    let n = graph.node_count[E](g)
    var v = 0usize
    while v < n {
        var e = g.offsets[v]
        while e < g.offsets[v + 1usize] {
            if colors[usize(g.edges[e].to)] == colors[v] { ret false }
            e += 1usize
        }
        v += 1usize
    }
    ret true
}
