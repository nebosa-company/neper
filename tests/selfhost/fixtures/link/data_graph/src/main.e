// `e.data.graph`: CSR adjacency from a builder, insertion order kept within a node,
// undirected edges as two directed ones, dense nodes grown by the edges that reach
// them, and the two iterators. Every check has its own exit code.
use e.os
use e.mem
use e.data.graph as graph

fn main(a: *mem.Arena, args: []str) -> err {
    let (initial, builder_error) = graph.builder[i32](a, 2usize, 2usize)
    if builder_error != ok { os.exit(10) }
    var b = initial
    if graph.add_directed[i32](&b, 0u32, 1u32, 5i32) != ok { os.exit(11) }
    if graph.add_directed[i32](&b, 0u32, 3u32, 7i32) != ok { os.exit(12) }
    if graph.add_undirected[i32](&b, 1u32, 2u32, 9i32) != ok { os.exit(13) }
    if graph.add_directed[i32](&b, 0u32, 2u32, 1i32) != ok { os.exit(14) }
    if b.node_count != 4usize || b.edges.len != 5usize { os.exit(15) }
    let (g, finish_error) = graph.finish[i32](a, &b)
    if finish_error != ok { os.exit(16) }
    if graph.node_count[i32](&g) != 4usize || graph.edge_count[i32](&g) != 5usize { os.exit(17) }
    // Node 0's edges in the order added: to 1, to 3, to 2.
    let (from_zero, n0_error) = graph.neighbors[i32](&g, 0u32)
    if n0_error != ok { os.exit(18) }
    var it0 = from_zero
    let (e1, h1) = graph.neighbors_next[i32](&it0)
    let (e2, h2) = graph.neighbors_next[i32](&it0)
    let (e3, h3) = graph.neighbors_next[i32](&it0)
    let (_, h4) = graph.neighbors_next[i32](&it0)
    if !h1 || !h2 || !h3 || h4 { os.exit(19) }
    if e1.to != 1u32 || e1.value != 5i32 || e2.to != 3u32 || e2.value != 7i32 || e3.to != 2u32 || e3.value != 1i32 || e1.from != 0u32 { os.exit(20) }
    // The undirected edge appears from both ends.
    let (from_two, _) = graph.neighbors[i32](&g, 2u32)
    var it2 = from_two
    let (back, has_back) = graph.neighbors_next[i32](&it2)
    let (_, more) = graph.neighbors_next[i32](&it2)
    if !has_back || more || back.to != 1u32 || back.value != 9i32 { os.exit(21) }
    // Node 3 has no edges out; node 4 does not exist.
    let (from_three, n3_error) = graph.neighbors[i32](&g, 3u32)
    var it3 = from_three
    let (_, h3out) = graph.neighbors_next[i32](&it3)
    if n3_error != ok || h3out { os.exit(22) }
    let (_, n4_error) = graph.neighbors[i32](&g, 4u32)
    if n4_error != graph.InvalidNode { os.exit(23) }
    // Every node once, in order.
    var nodes = graph.nodes[i32](&g)
    var expected = 0u32
    while true {
        let (id, has_id) = graph.nodes_next(&nodes)
        if !has_id { break }
        if id != expected { os.exit(24) }
        expected += 1u32
    }
    if expected != 4u32 { os.exit(25) }
    // An empty graph.
    let (empty_builder, _) = graph.builder[i32](a, 0usize, 0usize)
    let (empty, empty_error) = graph.finish[i32](a, &empty_builder)
    var none = graph.nodes[i32](&empty)
    let (_, any) = graph.nodes_next(&none)
    if empty_error != ok || graph.node_count[i32](&empty) != 0usize || any { os.exit(26) }
    let (_, too_large) = graph.builder[i32](a, 4294967295usize, 0usize)
    if too_large != graph.TooLarge { os.exit(27) }
    os.exit(0)
    ret ok
}
