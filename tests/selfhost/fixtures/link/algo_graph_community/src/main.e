// `e.algo.graph.community` on the karate club: modularity of the two
// factions as NetworkX scores it, label propagation settling on a proper
// partition, Louvain reaching a modularity at least as high as the
// factions', and Girvan-Newman splitting the club into NetworkX's two
// groups by removing edge (0, 31) first. Each check exits with its own code.

use e.algo.graph.community as community
use e.data.graph as graph
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}
// Zachary's karate club: 34 nodes, 78 undirected edges, as NetworkX lists them.
fn karate(a: *mem.Arena) -> (graph.Graph[i64], err) {
    let text = "0 1 0 2 0 3 0 4 0 5 0 6 0 7 0 8 0 10 0 11 0 12 0 13 0 17 0 19 0 21 0 31 1 2 1 3 1 7 1 13 1 17 1 19 1 21 1 30 2 3 2 7 2 8 2 9 2 13 2 27 2 28 2 32 3 7 3 12 3 13 4 6 4 10 5 6 5 10 5 16 6 16 8 30 8 32 8 33 9 33 13 33 14 32 14 33 15 32 15 33 18 32 18 33 19 33 20 32 20 33 22 32 22 33 23 25 23 27 23 29 23 32 23 33 24 25 24 27 24 31 25 31 26 29 26 33 27 33 28 31 28 33 29 32 29 33 30 32 30 33 31 32 31 33 32 33"
    let (b0, b_error) = graph.builder[i64](a, 34usize, 160usize)
    if b_error != ok { ret (zero, b_error) }
    var b = b0
    // Parse pairs of numbers.
    var at = 0usize
    var first = 0u32
    var seen = 0usize
    while at < text.len {
        var value = 0u32
        while at < text.len && text[at] != 32u8 {
            value = value * 10u32 + u32(text[at] - 48u8)
            at += 1usize
        }
        at += 1usize
        if seen % 2usize == 0usize {
            first = value
        } else {
            if graph.add_undirected[i64](&b, first, value, 1i64) != ok { ret (zero, graph.TooLarge) }
        }
        seen += 1usize
    }
    let (g, g_error) = graph.finish[i64](a, &b)
    ret (g, g_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (g, g_error) = karate(a)
    if g_error != ok { os.exit(1i32) }
    var labels: [34]u32 = zero

    // 1: modularity of the factions.
    let faction = "0 0 1 0 0 0 0 0 1 1 0 0 0 0 1 1 0 0 1 0 1 0 1 1 1 1 1 1 1 1 1 1 1 1"
    var i = 0usize
    var at = 0usize
    while i < 34usize {
        labels[i] = u32(faction[at] - 48u8)
        at += 2usize
        i += 1usize
    }
    if !near(community.modularity[i64](&g, labels[..]), 0.3599605522682445f64, 0.000000001f64) { os.exit(1i32) }
    i = 0usize
    while i < 34usize {
        labels[i] = u32(i)
        i += 1usize
    }
    if community.modularity[i64](&g, labels[..]) >= 0.0f64 { os.exit(1i32) }

    // 2: label propagation.
    var counts: [34]usize = zero
    let (sweeps, lp_error) = community.label_propagation[i64](&g, labels[..], counts[..], 100u32)
    if lp_error != ok || sweeps < 2u32 || sweeps == 100u32 { os.exit(2i32) }
    // Every node shares its label with at least one neighbour.
    i = 0usize
    while i < 34usize {
        var joined = false
        var e = g.offsets[i]
        while e < g.offsets[i + 1usize] {
            if labels[usize(g.edges[e].to)] == labels[i] { joined = true }
            e += 1usize
        }
        if !joined { os.exit(2i32) }
        i += 1usize
    }

    // 3: Louvain.
    let (q, louvain_error) = community.louvain[i64](a, &g, labels[..])
    if louvain_error != ok || q < 0.36f64 || q > 0.45f64 { os.exit(3i32) }
    var groups = 0usize
    i = 0usize
    while i < 34usize {
        if usize(labels[i]) + 1usize > groups { groups = usize(labels[i]) + 1usize }
        i += 1usize
    }
    if groups < 3usize || groups > 6usize { os.exit(3i32) }
    if !near(community.modularity[i64](&g, labels[..]), q, 0.000000001f64) { os.exit(3i32) }

    // 4: Girvan-Newman.
    var removed: [156]u8 = zero
    var scores: [156]f64 = zero
    var order: [34]u32 = zero
    var distance: [34]u32 = zero
    var sigma: [34]f64 = zero
    var delta: [34]f64 = zero
    if community.edge_betweenness[i64](&g, removed[..], scores[..], order[..], distance[..], sigma[..], delta[..]) != ok { os.exit(4i32) }
    // Edge (0, 31) has the largest betweenness, 71.39.
    var best = 0usize
    i = 1usize
    while i < 156usize {
        if scores[i] > scores[best] { best = i }
        i += 1usize
    }
    if !near(scores[best], 71.39285714285712f64, 0.0001f64) || !(usize(g.edges[best].to) == 31usize || usize(g.edges[best].to) == 0usize) { os.exit(4i32) }
    let (removals, gn_error) = community.girvan_newman[i64](&g, removed[..], scores[..], labels[..], order[..], distance[..], sigma[..], delta[..])
    if gn_error != ok || removals < 5usize || removals > 15usize { os.exit(4i32) }
    let split = "0 0 1 0 0 0 0 0 1 1 0 0 0 0 1 1 0 0 1 0 1 0 1 1 1 1 1 1 1 1 1 1 1 1"
    i = 0usize
    at = 0usize
    while i < 34usize {
        let want = u32(split[at] - 48u8)
        // Labels are component ids by first appearance: node 0 is 0, node 2 is 1.
        if labels[i] != want { os.exit(4i32) }
        at += 2usize
        i += 1usize
    }

    try io.print("algo graph community ok\n")
    ret ok
}
