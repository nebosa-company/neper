// `e.algo.graph.path` on a weighted digraph with a negative edge: Bellman-Ford,
// Floyd-Warshall and Johnson agree with each other and with Dijkstra where
// weights are positive, and all three refuse a negative cycle; Dial matches
// Dijkstra on integer weights; A* with a consistent heuristic and IDA* find
// the cheapest route; bidirectional search and IDDFS find the fewest-edge
// route; `path_to` reconstructs and reports an unreachable goal. Each check
// exits with its own code.

use e.algo.graph as algo
use e.algo.graph.path
use e.data.graph as graph
use e.io
use e.mem
use e.os

type Weights = struct { unused: u8 }

fn weight_of(ctx: *Weights, e: graph.Edge[i64]) -> f64 { ret f64(e.value) }
fn integer_weight(ctx: *Weights, e: graph.Edge[i64]) -> usize { ret usize(e.value) }
fn no_heuristic(ctx: *Weights, node: graph.NodeId) -> f64 { ret 0.0f64 }
// A consistent heuristic for the grid-like graph below: distance to node 5 in hops times the
// smallest weight (1).
fn hops_to_five(ctx: *Weights, node: graph.NodeId) -> f64 {
    if node == 5u32 { ret 0.0f64 }
    if node == 3u32 || node == 4u32 { ret 1.0f64 }
    if node == 1u32 || node == 2u32 { ret 2.0f64 }
    ret 3.0f64
}

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.000000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var w = Weights { unused: 0u8 }
    // 0 -> 1 (4), 0 -> 2 (2), 1 -> 3 (5), 2 -> 1 (1), 2 -> 3 (8), 2 -> 4 (10), 3 -> 4 (2), 3 -> 5 (6), 4 -> 5 (3); 6 isolated.
    let (b0, b_error) = graph.builder[i64](a, 7usize, 12usize)
    if b_error != ok { os.exit(1i32) }
    var b = b0
    if graph.add_directed[i64](&b, 0u32, 1u32, 4i64) != ok { os.exit(1i32) }
    if graph.add_directed[i64](&b, 0u32, 2u32, 2i64) != ok { os.exit(1i32) }
    if graph.add_directed[i64](&b, 1u32, 3u32, 5i64) != ok { os.exit(1i32) }
    if graph.add_directed[i64](&b, 2u32, 1u32, 1i64) != ok { os.exit(1i32) }
    if graph.add_directed[i64](&b, 2u32, 3u32, 8i64) != ok { os.exit(1i32) }
    if graph.add_directed[i64](&b, 2u32, 4u32, 10i64) != ok { os.exit(1i32) }
    if graph.add_directed[i64](&b, 3u32, 4u32, 2i64) != ok { os.exit(1i32) }
    if graph.add_directed[i64](&b, 3u32, 5u32, 6i64) != ok { os.exit(1i32) }
    if graph.add_directed[i64](&b, 4u32, 5u32, 3i64) != ok { os.exit(1i32) }
    let (g, g_error) = graph.finish[i64](a, &b)
    if g_error != ok { os.exit(1i32) }
    // Distances from 0: 0, 3, 2, 8, 10, 13, unreachable.

    // 1: Bellman-Ford, Floyd-Warshall and Johnson agree with Dijkstra.
    let (dj, dj_error) = algo.dijkstra[i64, Weights](a, &g, 0u32, &w, weight_of)
    if dj_error != ok { os.exit(1i32) }
    let (bf, bf_error) = path.bellman_ford[i64, Weights](a, &g, 0u32, &w, weight_of)
    if bf_error != ok { os.exit(1i32) }
    let (fw, fw_error) = path.floyd_warshall[i64, Weights](a, &g, &w, weight_of)
    if fw_error != ok { os.exit(1i32) }
    let (jn, jn_error) = path.johnson[i64, Weights](a, &g, &w, weight_of)
    if jn_error != ok { os.exit(1i32) }
    var expected: [7]f64 = zero
    expected[0usize] = 0.0f64
    expected[1usize] = 3.0f64
    expected[2usize] = 2.0f64
    expected[3usize] = 8.0f64
    expected[4usize] = 10.0f64
    expected[5usize] = 13.0f64
    expected[6usize] = path.infinity()
    var i = 0usize
    while i < 7usize {
        if i < 6usize {
            if !near(bf.distance[i], expected[i]) || !near(dj.distance[i], expected[i]) { os.exit(1i32) }
            if !near(fw[i], expected[i]) || !near(jn[i], expected[i]) { os.exit(1i32) }
        } else {
            if bf.distance[i] < path.infinity() || fw[i] < path.infinity() || jn[i] < path.infinity() { os.exit(1i32) }
        }
        i += 1usize
    }
    // All pairs: 2 -> 5 is 13 - 2 = 11 by the same route; 5 -> 0 is unreachable.
    if !near(fw[2usize * 7usize + 5usize], 11.0f64) || !near(jn[2usize * 7usize + 5usize], 11.0f64) || fw[5usize * 7usize] < path.infinity() { os.exit(1i32) }
    if bf.previous[5usize] != 4u32 || bf.previous[1usize] != 2u32 || bf.previous[6usize] != graph.NONE { os.exit(1i32) }

    // 2: a negative edge is fine, a negative cycle is refused by all three.
    let (c0, c_error) = graph.builder[i64](a, 3usize, 4usize)
    if c_error != ok { os.exit(2i32) }
    var c = c0
    if graph.add_directed[i64](&c, 0u32, 1u32, 4i64) != ok { os.exit(2i32) }
    if graph.add_directed[i64](&c, 1u32, 2u32, 0i64 - 3i64) != ok { os.exit(2i32) }
    if graph.add_directed[i64](&c, 0u32, 2u32, 2i64) != ok { os.exit(2i32) }
    let (neg, neg_error) = graph.finish[i64](a, &c)
    if neg_error != ok { os.exit(2i32) }
    let (bf2, bf2_error) = path.bellman_ford[i64, Weights](a, &neg, 0u32, &w, weight_of)
    if bf2_error != ok || !near(bf2.distance[2usize], 1.0f64) { os.exit(2i32) }
    let (jn2, jn2_error) = path.johnson[i64, Weights](a, &neg, &w, weight_of)
    if jn2_error != ok || !near(jn2[2usize], 1.0f64) || !near(jn2[1usize * 3usize + 2usize], 0.0f64 - 3.0f64) { os.exit(2i32) }
    let (fw2, fw2_error) = path.floyd_warshall[i64, Weights](a, &neg, &w, weight_of)
    if fw2_error != ok || !near(fw2[2usize], 1.0f64) { os.exit(2i32) }
    let (d0, d_error) = graph.builder[i64](a, 3usize, 4usize)
    if d_error != ok { os.exit(2i32) }
    var d = d0
    if graph.add_directed[i64](&d, 0u32, 1u32, 1i64) != ok { os.exit(2i32) }
    if graph.add_directed[i64](&d, 1u32, 2u32, 0i64 - 2i64) != ok { os.exit(2i32) }
    if graph.add_directed[i64](&d, 2u32, 1u32, 1i64) != ok { os.exit(2i32) }
    let (cycle, cycle_error) = graph.finish[i64](a, &d)
    if cycle_error != ok { os.exit(2i32) }
    let (_, bf_cycle) = path.bellman_ford[i64, Weights](a, &cycle, 0u32, &w, weight_of)
    let (_, fw_cycle) = path.floyd_warshall[i64, Weights](a, &cycle, &w, weight_of)
    let (_, jn_cycle) = path.johnson[i64, Weights](a, &cycle, &w, weight_of)
    if bf_cycle != path.NegativeCycle || fw_cycle != path.NegativeCycle || jn_cycle != path.NegativeCycle { os.exit(2i32) }

    // 3: Dial matches Dijkstra.
    let (dial, dial_error) = path.dial[i64, Weights](a, &g, 0u32, 10usize, &w, integer_weight)
    if dial_error != ok { os.exit(3i32) }
    i = 0usize
    while i < 6usize {
        if f64(dial[i]) != expected[i] { os.exit(3i32) }
        i += 1usize
    }
    if dial[6usize] != 18446744073709551615usize { os.exit(3i32) }
    let (_, dial_small) = path.dial[i64, Weights](a, &g, 0u32, 5usize, &w, integer_weight)
    if dial_small != path.TooSmall { os.exit(3i32) }

    // 4: A* and IDA* find the cheapest route 0 -> 2 -> 1 -> 3 -> 4 -> 5 (13).
    let (star, star_error) = path.astar[i64, Weights](a, &g, 0u32, 5u32, &w, weight_of, hops_to_five)
    if star_error != ok || !near(star.cost, 13.0f64) || star.nodes.len != 6usize { os.exit(4i32) }
    if star.nodes[0usize] != 0u32 || star.nodes[1usize] != 2u32 || star.nodes[2usize] != 1u32 || star.nodes[5usize] != 5u32 { os.exit(4i32) }
    let (plain, plain_error) = path.astar[i64, Weights](a, &g, 0u32, 5u32, &w, weight_of, no_heuristic)
    if plain_error != ok || !near(plain.cost, 13.0f64) { os.exit(4i32) }
    let (_, star_none) = path.astar[i64, Weights](a, &g, 0u32, 6u32, &w, weight_of, no_heuristic)
    if star_none != path.NoPath { os.exit(4i32) }
    let (ida, ida_error) = path.ida_star[i64, Weights](a, &g, 0u32, 5u32, 10usize, &w, weight_of, hops_to_five)
    if ida_error != ok || !near(ida.cost, 13.0f64) || ida.nodes.len != 6usize || ida.nodes[1usize] != 2u32 { os.exit(4i32) }
    let (_, ida_none) = path.ida_star[i64, Weights](a, &g, 0u32, 6u32, 10usize, &w, weight_of, no_heuristic)
    if ida_none != path.NoPath { os.exit(4i32) }

    // 5: fewest edges: 0 -> 2 -> 4 -> 5 or 0 -> 1 -> 3 -> 5 (3 edges).
    let (bi, bi_error) = path.bidirectional[i64](a, &g, 0u32, 5u32)
    if bi_error != ok || bi.nodes.len != 4usize || bi.nodes[0usize] != 0u32 || bi.nodes[3usize] != 5u32 || !near(bi.cost, 3.0f64) { os.exit(5i32) }
    let (self_route, self_error) = path.bidirectional[i64](a, &g, 3u32, 3u32)
    if self_error != ok || self_route.nodes.len != 1usize { os.exit(5i32) }
    let (_, bi_none) = path.bidirectional[i64](a, &g, 5u32, 0u32)
    if bi_none != path.NoPath { os.exit(5i32) }
    let (deep, deep_error) = path.iddfs[i64](a, &g, 0u32, 5u32, 10usize)
    if deep_error != ok || deep.nodes.len != 4usize || !near(deep.cost, 3.0f64) { os.exit(5i32) }
    let (_, too_shallow) = path.iddfs[i64](a, &g, 0u32, 5u32, 2usize)
    if too_shallow != path.NoPath { os.exit(5i32) }

    // 6: path reconstruction.
    let (route, route_error) = path.path_to(a, dj.previous, 0u32, 5u32)
    if route_error != ok || route.len != 6usize || route[0usize] != 0u32 || route[1usize] != 2u32 || route[5usize] != 5u32 { os.exit(6i32) }
    let (_, not_reached) = path.path_to(a, dj.previous, 0u32, 6u32)
    if not_reached != path.NoPath { os.exit(6i32) }
    let (_, out_of_range) = path.path_to(a, dj.previous, 0u32, 9u32)
    if out_of_range != path.InvalidNode { os.exit(6i32) }

    try io.print("algo graph path ok\n")
    ret ok
}
