// `e.algo.graph.flow`: the three maximum-flow algorithms agree with the
// textbook value on CLRS's six-node network (23), on a network with parallel
// and anti-parallel arcs, and on a bipartite matching instance; the minimum
// cut's capacity equals the flow; edge flows respect conservation; invalid
// endpoints and negative capacities are refused. Each check exits with its own
// code.

use e.algo.graph.flow
use e.data.graph as graph
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

fn cap_of(ctx: *Nothing, edge: graph.Edge[i64]) -> i64 { ret edge.value }

fn clrs(a: *mem.Arena) -> (graph.Graph[i64], err) {
    let (b0, b_error) = graph.builder[i64](a, 6usize, 10usize)
    if b_error != ok { ret (zero, b_error) }
    var b = b0
    if graph.add_directed[i64](&b, 0u32, 1u32, 16i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 0u32, 2u32, 13i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 1u32, 2u32, 10i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 2u32, 1u32, 4i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 1u32, 3u32, 12i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 3u32, 2u32, 9i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 2u32, 4u32, 14i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 4u32, 3u32, 7i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 3u32, 5u32, 20i64) != ok { ret (zero, graph.TooLarge) }
    if graph.add_directed[i64](&b, 4u32, 5u32, 4i64) != ok { ret (zero, graph.TooLarge) }
    let (g, finish_error) = graph.finish[i64](a, &b)
    ret (g, finish_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var nothing = Nothing { unused: 0u8 }
    let (g, g_error) = clrs(a)
    if g_error != ok { os.exit(1i32) }

    // 1: the three algorithms find 23.
    let (n1, n1_error) = flow.build[i64, Nothing](a, &g, 0u32, 5u32, &nothing, cap_of)
    if n1_error != ok { os.exit(1i32) }
    var net1 = n1
    let (f1, f1_error) = flow.edmonds_karp(a, &net1)
    if f1_error != ok || f1 != 23i64 { os.exit(1i32) }
    let (n2, n2_error) = flow.build[i64, Nothing](a, &g, 0u32, 5u32, &nothing, cap_of)
    if n2_error != ok { os.exit(1i32) }
    var net2 = n2
    let (f2, f2_error) = flow.dinic(a, &net2)
    if f2_error != ok || f2 != 23i64 { os.exit(1i32) }
    let (n3, n3_error) = flow.build[i64, Nothing](a, &g, 0u32, 5u32, &nothing, cap_of)
    if n3_error != ok { os.exit(1i32) }
    var net3 = n3
    let (f3, f3_error) = flow.push_relabel(a, &net3)
    if f3_error != ok || f3 != 23i64 { os.exit(1i32) }
    // A second run on a saturated network adds nothing.
    let (again, again_error) = flow.dinic(a, &net2)
    if again_error != ok || again != 0i64 { os.exit(1i32) }

    // 2: the minimum cut and edge flows.
    var side: [6]u8 = zero
    if flow.min_cut(a, &net1, side[..]) != ok || side[0usize] != 1u8 || side[5usize] != 0u8 { os.exit(2i32) }
    // The cut's capacity, summed over input arcs leaving the source side, is the flow.
    var cut = 0i64
    var conserved = true
    var k = 0usize
    while k < g.edges.len {
        let e = g.edges[k]
        if side[usize(e.from)] == 1u8 && side[usize(e.to)] == 0u8 { cut += e.value }
        let carried = flow.edge_flow(&net1, k)
        if carried < 0i64 || carried > e.value { conserved = false }
        k += 1usize
    }
    if cut != 23i64 || !conserved { os.exit(2i32) }
    // Conservation at every inner node, and the source's outflow is the flow.
    var node = 0usize
    while node < 6usize {
        var balance = 0i64
        k = 0usize
        while k < g.edges.len {
            let carried = flow.edge_flow(&net1, k)
            if usize(g.edges[k].from) == node { balance -= carried }
            if usize(g.edges[k].to) == node { balance += carried }
            k += 1usize
        }
        if node == 0usize && balance != 0i64 - 23i64 { os.exit(2i32) }
        if node == 5usize && balance != 23i64 { os.exit(2i32) }
        if node != 0usize && node != 5usize && balance != 0i64 { os.exit(2i32) }
        node += 1usize
    }

    // 3: parallel and anti-parallel arcs.
    let (b0, b_error) = graph.builder[i64](a, 4usize, 8usize)
    if b_error != ok { os.exit(3i32) }
    var b = b0
    if graph.add_directed[i64](&b, 0u32, 1u32, 5i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&b, 0u32, 1u32, 5i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&b, 1u32, 0u32, 100i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&b, 1u32, 2u32, 7i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&b, 0u32, 2u32, 1i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&b, 2u32, 3u32, 6i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&b, 1u32, 3u32, 1i64) != ok { os.exit(3i32) }
    let (h, h_error) = graph.finish[i64](a, &b)
    if h_error != ok { os.exit(3i32) }
    let (m1, m1_error) = flow.build[i64, Nothing](a, &h, 0u32, 3u32, &nothing, cap_of)
    if m1_error != ok { os.exit(3i32) }
    var netm1 = m1
    let (fm1, fm1_error) = flow.edmonds_karp(a, &netm1)
    let (m2, m2_error) = flow.build[i64, Nothing](a, &h, 0u32, 3u32, &nothing, cap_of)
    if m2_error != ok { os.exit(3i32) }
    var netm2 = m2
    let (fm2, fm2_error) = flow.dinic(a, &netm2)
    let (m3, m3_error) = flow.build[i64, Nothing](a, &h, 0u32, 3u32, &nothing, cap_of)
    if m3_error != ok { os.exit(3i32) }
    var netm3 = m3
    let (fm3, fm3_error) = flow.push_relabel(a, &netm3)
    // Into node 3: 6 through node 2 (fed by 7 + 1) and 1 direct: 7.
    if fm1_error != ok || fm2_error != ok || fm3_error != ok || fm1 != 7i64 || fm2 != 7i64 || fm3 != 7i64 { os.exit(3i32) }

    // 4: bipartite matching as a flow: 3 left, 3 right, a perfect matching exists.
    let (c0, c_error) = graph.builder[i64](a, 8usize, 12usize)
    if c_error != ok { os.exit(4i32) }
    var c = c0
    // Source 0, left 1..3, right 4..6, sink 7. Left 1 -> 4, 5; left 2 -> 4; left 3 -> 5, 6.
    if graph.add_directed[i64](&c, 0u32, 1u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 0u32, 2u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 0u32, 3u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 1u32, 4u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 1u32, 5u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 2u32, 4u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 3u32, 5u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 3u32, 6u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 4u32, 7u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 5u32, 7u32, 1i64) != ok { os.exit(4i32) }
    if graph.add_directed[i64](&c, 6u32, 7u32, 1i64) != ok { os.exit(4i32) }
    let (bip, bip_error) = graph.finish[i64](a, &c)
    if bip_error != ok { os.exit(4i32) }
    let (p, p_error) = flow.build[i64, Nothing](a, &bip, 0u32, 7u32, &nothing, cap_of)
    if p_error != ok { os.exit(4i32) }
    var netp = p
    let (matched, matched_error) = flow.push_relabel(a, &netp)
    if matched_error != ok || matched != 3i64 { os.exit(4i32) }

    // 5: refusals.
    let (_, same) = flow.build[i64, Nothing](a, &g, 2u32, 2u32, &nothing, cap_of)
    if same != flow.InvalidNode { os.exit(5i32) }
    let (_, past) = flow.build[i64, Nothing](a, &g, 0u32, 9u32, &nothing, cap_of)
    if past != flow.InvalidNode { os.exit(5i32) }
    let (d0, d_error) = graph.builder[i64](a, 2usize, 1usize)
    if d_error != ok { os.exit(5i32) }
    var d = d0
    if graph.add_directed[i64](&d, 0u32, 1u32, 0i64 - 1i64) != ok { os.exit(5i32) }
    let (neg, neg_error) = graph.finish[i64](a, &d)
    if neg_error != ok { os.exit(5i32) }
    let (_, negative) = flow.build[i64, Nothing](a, &neg, 0u32, 1u32, &nothing, cap_of)
    if negative != flow.InvalidCapacity { os.exit(5i32) }

    try io.print("algo graph flow ok\n")
    ret ok
}
