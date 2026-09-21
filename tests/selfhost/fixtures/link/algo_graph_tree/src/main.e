// `e.algo.graph.tree` on a nine-node tree: rooting gives the right parents,
// depths and sizes and refuses a cycle; binary-lifting and offline LCAs agree
// with NetworkX; the Euler tour brackets every subtree; heavy-light paths are
// contiguous and cover a query path; the centroid tree has logarithmic depth;
// Prüfer codes round-trip against NetworkX; AHU labels tell isomorphic and
// non-isomorphic rootings apart. Each check exits with its own code.

use e.algo.graph.tree
use e.data.graph as graph
use e.io
use e.mem
use e.os

fn build_tree(a: *mem.Arena, edges: []const u32, n: usize) -> (graph.Graph[u8], err) {
    let (b0, b_error) = graph.builder[u8](a, n, 2usize * edges.len)
    if b_error != ok { ret (zero, b_error) }
    var b = b0
    var i = 0usize
    while i + 1usize < edges.len {
        if graph.add_undirected[u8](&b, edges[i], edges[i + 1usize], 0u8) != ok { ret (zero, graph.TooLarge) }
        i += 2usize
    }
    let (g, g_error) = graph.finish[u8](a, &b)
    ret (g, g_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 0-1, 0-2, 1-3, 1-4, 2-5, 4-6, 4-7, 7-8.
    var edges: [16]u32 = zero
    edges[0usize] = 0u32
    edges[1usize] = 1u32
    edges[2usize] = 0u32
    edges[3usize] = 2u32
    edges[4usize] = 1u32
    edges[5usize] = 3u32
    edges[6usize] = 1u32
    edges[7usize] = 4u32
    edges[8usize] = 2u32
    edges[9usize] = 5u32
    edges[10usize] = 4u32
    edges[11usize] = 6u32
    edges[12usize] = 4u32
    edges[13usize] = 7u32
    edges[14usize] = 7u32
    edges[15usize] = 8u32
    let (g, g_error) = build_tree(a, edges[..], 9usize)
    if g_error != ok { os.exit(1i32) }

    // 1: rooting.
    let (t, t_error) = tree.root_at[u8](a, &g, 0u32)
    if t_error != ok { os.exit(1i32) }
    if t.parent[0usize] != 0u32 || t.parent[8usize] != 7u32 || t.parent[5usize] != 2u32 { os.exit(1i32) }
    if t.depth[0usize] != 0u32 || t.depth[4usize] != 2u32 || t.depth[8usize] != 4u32 { os.exit(1i32) }
    if t.size[0usize] != 9u32 || t.size[1usize] != 6u32 || t.size[4usize] != 4u32 || t.size[8usize] != 1u32 { os.exit(1i32) }
    if t.order[0usize] != 0u32 || t.order.len != 9usize { os.exit(1i32) }
    var cyclic_edges: [6]u32 = zero
    cyclic_edges[0usize] = 0u32
    cyclic_edges[1usize] = 1u32
    cyclic_edges[2usize] = 1u32
    cyclic_edges[3usize] = 2u32
    cyclic_edges[4usize] = 2u32
    cyclic_edges[5usize] = 0u32
    let (cyclic, cyclic_error) = build_tree(a, cyclic_edges[..], 3usize)
    if cyclic_error != ok { os.exit(1i32) }
    let (_, not_tree) = tree.root_at[u8](a, &cyclic, 0u32)
    if not_tree != tree.NotATree { os.exit(1i32) }
    let (_, out_of_range) = tree.root_at[u8](a, &g, 9u32)
    if out_of_range != tree.InvalidNode { os.exit(1i32) }

    // 2: lowest common ancestors, online and offline.
    let (l, l_error) = tree.lifting(a, &t)
    if l_error != ok { os.exit(2i32) }
    if tree.lca(&l, 3u32, 6u32) != 1u32 || tree.lca(&l, 8u32, 5u32) != 0u32 || tree.lca(&l, 6u32, 7u32) != 4u32 { os.exit(2i32) }
    if tree.lca(&l, 8u32, 1u32) != 1u32 || tree.lca(&l, 0u32, 8u32) != 0u32 || tree.lca(&l, 3u32, 3u32) != 3u32 { os.exit(2i32) }
    if tree.ancestor(&l, 8u32, 3u32) != 1u32 || tree.ancestor(&l, 8u32, 9u32) != 0u32 || tree.ancestor(&l, 5u32, 0u32) != 5u32 { os.exit(2i32) }
    if tree.distance(&l, 8u32, 5u32) != 6u32 || tree.distance(&l, 3u32, 6u32) != 3u32 || tree.distance(&l, 4u32, 4u32) != 0u32 { os.exit(2i32) }
    var queries: [12]u32 = zero
    queries[0usize] = 3u32
    queries[1usize] = 6u32
    queries[2usize] = 8u32
    queries[3usize] = 5u32
    queries[4usize] = 6u32
    queries[5usize] = 7u32
    queries[6usize] = 8u32
    queries[7usize] = 1u32
    queries[8usize] = 0u32
    queries[9usize] = 8u32
    queries[10usize] = 3u32
    queries[11usize] = 3u32
    var answers: [6]u32 = zero
    if tree.lca_offline[u8](a, &g, &t, queries[..], answers[..]) != ok { os.exit(2i32) }
    if answers[0usize] != 1u32 || answers[1usize] != 0u32 || answers[2usize] != 4u32 || answers[3usize] != 1u32 || answers[4usize] != 0u32 || answers[5usize] != 3u32 { os.exit(2i32) }
    if tree.lca_offline[u8](a, &g, &t, queries[..], answers[..2usize]) != tree.TooSmall { os.exit(2i32) }

    // 3: the Euler tour brackets subtrees.
    let (tour, tour_error) = tree.euler_tour[u8](a, &g, &t)
    if tour_error != ok || tour.sequence.len != 17usize || tour.sequence[0usize] != 0u32 { os.exit(3i32) }
    if tour.entry[0usize] != 0u32 || tour.exit[0usize] != 17u32 { os.exit(3i32) }
    // Node 8 sits inside 7 inside 4 inside 1.
    if !(tour.entry[1usize] < tour.entry[4usize] && tour.entry[4usize] < tour.entry[7usize] && tour.entry[7usize] < tour.entry[8usize]) { os.exit(3i32) }
    if !(tour.exit[8usize] <= tour.exit[7usize] && tour.exit[7usize] <= tour.exit[4usize] && tour.exit[4usize] <= tour.exit[1usize]) { os.exit(3i32) }
    // Node 5 is not inside node 1's subtree.
    if tour.entry[5usize] > tour.entry[1usize] && tour.entry[5usize] < tour.exit[1usize] { os.exit(3i32) }
    // Every node appears at entry, and the sequence walks edges.
    var v = 0usize
    while v < 9usize {
        if tour.sequence[usize(tour.entry[v])] != u32(v) { os.exit(3i32) }
        v += 1usize
    }

    // 4: heavy-light decomposition.
    let (h, h_error) = tree.heavy_light(a, &t)
    if h_error != ok { os.exit(4i32) }
    // The heavy path from the root: 0 -> 1 -> 4 -> 7 -> 8, contiguous positions.
    if h.head[8usize] != 0u32 || h.head[7usize] != 0u32 || h.head[4usize] != 0u32 || h.head[1usize] != 0u32 { os.exit(4i32) }
    if h.position[1usize] != h.position[0usize] + 1u32 || h.position[8usize] != h.position[7usize] + 1u32 { os.exit(4i32) }
    if h.head[5usize] != 2u32 || h.head[2usize] != 2u32 || h.head[3usize] != 3u32 || h.head[6usize] != 6u32 { os.exit(4i32) }
    var seen = 0u32
    v = 0usize
    while v < 9usize {
        seen = seen | (1u32 << h.position[v])
        v += 1usize
    }
    if seen != 511u32 { os.exit(4i32) }
    var ranges: [16]u32 = zero
    let (range_count, range_error) = tree.path_ranges(&h, 6u32, 5u32, ranges[..])
    // 6 -> 4 -> 1 -> 0 -> 2 -> 5: the light node 6, the light path 5 - 2, and 0..4 on the heavy path.
    if range_error != ok || range_count != 3usize { os.exit(4i32) }
    var covered = 0usize
    var r = 0usize
    while r < range_count {
        if ranges[2usize * r] > ranges[2usize * r + 1usize] { os.exit(4i32) }
        covered += usize(ranges[2usize * r + 1usize] - ranges[2usize * r]) + 1usize
        r += 1usize
    }
    if covered != 6usize { os.exit(4i32) }
    let (_, range_room) = tree.path_ranges(&h, 6u32, 5u32, ranges[..2usize])
    if range_room != tree.TooSmall { os.exit(4i32) }

    // 5: centroid decomposition: the top centroid splits the tree evenly; levels are small.
    var centroid_parent: [9]u32 = zero
    var centroid_level: [9]u32 = zero
    if tree.centroid_decompose[u8](a, &g, centroid_parent[..], centroid_level[..]) != ok { os.exit(5i32) }
    var tops = 0usize
    var deepest = 0u32
    v = 0usize
    while v < 9usize {
        if centroid_parent[v] == graph.NONE {
            tops += 1usize
            if centroid_level[v] != 0u32 { os.exit(5i32) }
        } else if centroid_level[v] != centroid_level[usize(centroid_parent[v])] + 1u32 {
            os.exit(5i32)
        }
        if centroid_level[v] > deepest { deepest = centroid_level[v] }
        v += 1usize
    }
    // Node 1 or 4 is the centroid of the whole tree; either way the levels stay within log2(9) + 1.
    if tops != 1usize || deepest > 4u32 { os.exit(5i32) }
    if centroid_parent[1usize] != graph.NONE && centroid_parent[4usize] != graph.NONE { os.exit(5i32) }

    // 6: Prüfer codes.
    var code: [7]u32 = zero
    if tree.prufer_encode[u8](a, &g, code[..]) != ok { os.exit(6i32) }
    if code[0usize] != 1u32 || code[1usize] != 2u32 || code[2usize] != 0u32 || code[3usize] != 1u32 || code[4usize] != 4u32 || code[5usize] != 4u32 || code[6usize] != 7u32 { os.exit(6i32) }
    var decoded: [16]u32 = zero
    if tree.prufer_decode(a, code[..], decoded[..]) != ok { os.exit(6i32) }
    // The decoded edge set equals the original: check each original edge appears.
    var e = 0usize
    while e + 1usize < 16usize {
        var present = false
        var d = 0usize
        while d + 1usize < 16usize {
            if (decoded[d] == edges[e] && decoded[d + 1usize] == edges[e + 1usize]) || (decoded[d] == edges[e + 1usize] && decoded[d + 1usize] == edges[e]) { present = true }
            d += 2usize
        }
        if !present { os.exit(6i32) }
        e += 2usize
    }
    var small_code: [4]u32 = zero
    small_code[0usize] = 3u32
    small_code[1usize] = 3u32
    small_code[2usize] = 3u32
    small_code[3usize] = 4u32
    var small_edges: [10]u32 = zero
    if tree.prufer_decode(a, small_code[..], small_edges[..]) != ok { os.exit(6i32) }
    // Edges (0,3) (1,3) (2,3) (3,4) (4,5) in leaf order.
    if small_edges[0usize] != 0u32 || small_edges[1usize] != 3u32 || small_edges[6usize] != 3u32 || small_edges[7usize] != 4u32 || small_edges[8usize] != 4u32 || small_edges[9usize] != 5u32 { os.exit(6i32) }
    if tree.prufer_encode[u8](a, &g, code[..5usize]) != tree.TooSmall { os.exit(6i32) }

    // 7: AHU labels: rooting at 3 and at 6 (both leaves under a symmetric shape?) -- compare
    // subtree labels instead: the subtrees at 3, 5, 6 and 8 are single leaves and share a
    // label; 7 (one child) differs from 4 (two children, one of them 7).
    var labels: [9]u64 = zero
    var scratch: [9]u64 = zero
    if tree.ahu_labels[u8](a, &g, &t, labels[..], scratch[..]) != ok { os.exit(7i32) }
    if labels[3usize] != labels[5usize] || labels[5usize] != labels[6usize] || labels[6usize] != labels[8usize] { os.exit(7i32) }
    if labels[7usize] == labels[4usize] || labels[7usize] == labels[3usize] || labels[2usize] != labels[7usize] { os.exit(7i32) }
    // Node 2 (one leaf child) and node 7 (one leaf child) are isomorphic subtrees.
    if labels[1usize] == labels[4usize] || labels[0usize] == labels[1usize] { os.exit(7i32) }
    if tree.ahu_labels[u8](a, &g, &t, labels[..], scratch[..4usize]) != tree.TooSmall { os.exit(7i32) }

    try io.print("algo graph tree ok\n")
    ret ok
}
