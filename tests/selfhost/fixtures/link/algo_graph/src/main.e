// `e.algo.graph` over a small directed graph: BFS and DFS orders and parents, the
// smallest-first topological order and its refusal on a cycle, weak and strong components
// numbered by smallest node, and Dijkstra with a weight callback, including a negative
// weight refused. Every check has its own exit code.
use e.os
use e.mem
use e.data.graph as graph
use e.algo.graph as algo

fn weight_of(ctx: *u8, e: graph.Edge[f64]) -> f64 { ret e.value }

fn main(a: *mem.Arena, args: []str) -> err {
    let (b0, _) = graph.builder[f64](a, 0usize, 8usize)
    var b = b0
    if graph.add_directed[f64](&b, 0u32, 1u32, 1.0) != ok { os.exit(99) }
    if graph.add_directed[f64](&b, 0u32, 2u32, 4.0) != ok { os.exit(99) }
    if graph.add_directed[f64](&b, 1u32, 2u32, 2.0) != ok { os.exit(99) }
    if graph.add_directed[f64](&b, 2u32, 3u32, 1.0) != ok { os.exit(99) }
    if graph.add_directed[f64](&b, 4u32, 0u32, 1.0) != ok { os.exit(99) }
    let (g, _) = graph.finish[f64](a, &b)
    let (t, bfs_error) = algo.bfs[f64](a, &g, 0u32)
    if bfs_error != ok { os.exit(1) }
    if t.order.len != 4usize || t.order[0] != 0u32 || t.order[1] != 1u32 || t.order[2] != 2u32 || t.order[3] != 3u32 { os.exit(2) }
    if t.parent[0] != 0u32 || t.parent[2] != 0u32 || t.parent[3] != 2u32 || t.parent[4] != graph.NONE { os.exit(3) }
    let (d, dfs_error) = algo.dfs[f64](a, &g, 0u32)
    if dfs_error != ok || d.order.len != 4usize || d.order[1] != 1u32 || d.order[2] != 2u32 || d.order[3] != 3u32 || d.parent[2] != 1u32 { os.exit(4) }
    let (topo, topo_error) = algo.topological[f64](a, &g)
    if topo_error != ok || topo.len != 5usize || topo[0] != 4u32 || topo[1] != 0u32 || topo[2] != 1u32 || topo[3] != 2u32 || topo[4] != 3u32 { os.exit(5) }
    let (weak, weak_error) = algo.weak_components[f64](a, &g)
    if weak_error != ok || weak.count != 1u32 || weak.component[4] != 0u32 { os.exit(6) }
    let (strong, strong_error) = algo.strong_components[f64](a, &g)
    if strong_error != ok || strong.count != 5u32 || strong.component[0] != 0u32 || strong.component[4] != 4u32 { os.exit(7) }
    var ctx = 0u8
    let (paths, path_error) = algo.dijkstra[f64, u8](a, &g, 0u32, &ctx, weight_of)
    if path_error != ok { os.exit(8) }
    if paths.distance[0] != 0.0 || paths.distance[1] != 1.0 || paths.distance[2] != 3.0 || paths.distance[3] != 4.0 { os.exit(9) }
    if paths.previous[2] != 1u32 || paths.previous[3] != 2u32 || paths.previous[4] != graph.NONE || paths.distance[4] <= 1000000.0 { os.exit(10) }
    // A cycle: 1 -> 0 makes 0,1 one strong component and defeats the topological order.
    if graph.add_directed[f64](&b, 1u32, 0u32, 1.0) != ok { os.exit(99) }
    let (cyclic, _) = graph.finish[f64](a, &b)
    let (_, cycle_error) = algo.topological[f64](a, &cyclic)
    if cycle_error != algo.Cycle { os.exit(11) }
    let (s2, _) = algo.strong_components[f64](a, &cyclic)
    if s2.count != 4u32 || s2.component[0] != s2.component[1] || s2.component[0] != 0u32 || s2.component[4] != 3u32 { os.exit(12) }
    if graph.add_directed[f64](&b, 3u32, 4u32, -1.0) != ok { os.exit(99) }
    let (bad, _) = graph.finish[f64](a, &b)
    let (_, bad_weight) = algo.dijkstra[f64, u8](a, &bad, 0u32, &ctx, weight_of)
    if bad_weight != algo.InvalidWeight { os.exit(13) }
    os.exit(0)
    ret ok
}
