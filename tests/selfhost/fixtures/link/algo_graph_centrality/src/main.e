// `e.algo.graph.centrality` on the karate club (unweighted) against NetworkX:
// PageRank, HITS hubs, eigenvector, closeness and betweenness at the
// leaders (nodes 0 and 33), a peripheral node and a middle one. Each check
// exits with its own code.

use e.algo.graph.centrality as centrality
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
    if g_error != ok || graph.node_count[i64](&g) != 34usize || g.edges.len != 156usize { os.exit(1i32) }
    var scores: [34]f64 = zero
    var scratch: [34]f64 = zero

    // 1: PageRank.
    let (rounds, pr_error) = centrality.pagerank[i64](&g, 0.85f64, 0.000000000001f64, 1000u32, scores[..], scratch[..])
    if pr_error != ok || rounds == 1000u32 { os.exit(1i32) }
    if !near(scores[0usize], 0.096997f64, 0.00001f64) || !near(scores[33usize], 0.100919f64, 0.00001f64) || !near(scores[1usize], 0.052877f64, 0.00001f64) || !near(scores[11usize], 0.009565f64, 0.00001f64) { os.exit(1i32) }
    var total = 0.0f64
    var i = 0usize
    while i < 34usize {
        total += scores[i]
        i += 1usize
    }
    if !near(total, 1.0f64, 0.000001f64) { os.exit(1i32) }
    let (_, pr_invalid) = centrality.pagerank[i64](&g, 1.5f64, 0.000001f64, 10u32, scores[..], scratch[..])
    if pr_invalid != centrality.Invalid { os.exit(1i32) }

    // 2: HITS and eigenvector centrality (unit length).
    var hub: [34]f64 = zero
    let (_, hits_error) = centrality.hits[i64](&g, 0.000000000001f64, 1000u32, scores[..], hub[..])
    if hits_error != ok || !near(hub[0usize], 0.355491f64, 0.00001f64) || !near(hub[33usize], 0.373363f64, 0.00001f64) || !near(hub[11usize], 0.052856f64, 0.00001f64) { os.exit(2i32) }
    // An undirected graph's authorities equal its hubs.
    if !near(scores[0usize], hub[0usize], 0.00001f64) { os.exit(2i32) }
    let (_, eig_error) = centrality.eigenvector[i64](&g, 0.000000000001f64, 1000u32, scores[..], scratch[..])
    if eig_error != ok || !near(scores[0usize], 0.355491f64, 0.00001f64) || !near(scores[33usize], 0.373363f64, 0.00001f64) || !near(scores[11usize], 0.052856f64, 0.00001f64) { os.exit(2i32) }

    // 3: closeness and betweenness.
    var queue: [34]u32 = zero
    var distance: [34]u32 = zero
    if centrality.closeness[i64](&g, scores[..], queue[..], distance[..]) != ok { os.exit(3i32) }
    if !near(scores[0usize], 0.568966f64, 0.00001f64) || !near(scores[33usize], 0.55f64, 0.00001f64) || !near(scores[11usize], 0.366667f64, 0.00001f64) { os.exit(3i32) }
    var sigma: [34]f64 = zero
    var delta: [34]f64 = zero
    var first_pred: [34]u32 = zero
    var pred: [156]u32 = zero
    var next_pred: [156]u32 = zero
    if centrality.betweenness[i64](&g, true, scores[..], queue[..], distance[..], sigma[..], delta[..], first_pred[..], pred[..], next_pred[..]) != ok { os.exit(3i32) }
    if !near(scores[0usize], 231.071429f64, 0.0001f64) || !near(scores[33usize], 160.551587f64, 0.0001f64) || scores[11usize] != 0.0f64 || !near(scores[2usize], 75.850794f64, 0.0001f64) { os.exit(3i32) }
    if centrality.betweenness[i64](&g, true, scores[..], queue[..], distance[..], sigma[..], delta[..], first_pred[..], pred[..10usize], next_pred[..]) != centrality.TooSmall { os.exit(3i32) }

    try io.print("algo graph centrality ok\n")
    ret ok
}
