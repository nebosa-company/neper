// `e.algo.graph.span`: Kruskal, Prim and Borůvka agree with NetworkX's
// minimum spanning tree of CLRS's nine-node graph (37) and count the trees of
// a forest; bridges and articulation points of two triangles joined by a
// bridge with a pendant; Hierholzer's circuit and path, and a refusal;
// Warshall's closure. Each check exits with its own code.

use e.algo.graph.span
use e.data.graph as graph
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

fn weight_of(ctx: *Nothing, e: graph.Edge[i64]) -> f64 { ret f64(e.value) }

fn add_edges(b: *graph.Builder[i64], spec: []const i64) -> err {
    var i = 0usize
    while i + 2usize < spec.len {
        if graph.add_undirected[i64](b, u32(spec[i]), u32(spec[i + 1usize]), spec[i + 2usize]) != ok { ret graph.TooLarge }
        i += 3usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var nothing = Nothing { unused: 0u8 }
    // CLRS figure 23.1: 14 weighted edges on 9 nodes.
    var spec: [42]i64 = zero
    let text = "0 1 4 0 7 8 1 2 8 1 7 11 2 3 7 2 8 2 2 5 4 3 4 9 3 5 14 4 5 10 5 6 2 6 7 1 6 8 6 7 8 7"
    var at = 0usize
    var cell = 0usize
    while at < text.len {
        var value = 0i64
        while at < text.len && text[at] != 32u8 {
            value = value * 10i64 + i64(text[at] - 48u8)
            at += 1usize
        }
        spec[cell] = value
        cell += 1usize
        at += 1usize
    }
    let (b0, b_error) = graph.builder[i64](a, 9usize, 28usize)
    if b_error != ok { os.exit(1i32) }
    var b = b0
    if add_edges(&b, spec[..]) != ok { os.exit(1i32) }
    let (g, g_error) = graph.finish[i64](a, &b)
    if g_error != ok { os.exit(1i32) }

    // 1: the three MSTs weigh 37 with 8 edges, all distinct, from < to.
    let (k, k_error) = span.kruskal[i64, Nothing](a, &g, &nothing, weight_of)
    if k_error != ok || k.weight != 37.0f64 || k.edges.len != 8usize || k.trees != 1usize { os.exit(1i32) }
    let (p, p_error) = span.prim[i64, Nothing](a, &g, 0u32, &nothing, weight_of)
    if p_error != ok || p.weight != 37.0f64 || p.edges.len != 8usize || p.trees != 1usize { os.exit(1i32) }
    let (bo, bo_error) = span.boruvka[i64, Nothing](a, &g, &nothing, weight_of)
    if bo_error != ok || bo.weight != 37.0f64 || bo.edges.len != 8usize || bo.trees != 1usize { os.exit(1i32) }
    var i = 0usize
    while i < 8usize {
        let e = g.edges[k.edges[i]]
        if e.from >= e.to { os.exit(1i32) }
        let f = g.edges[bo.edges[i]]
        if f.from >= f.to { os.exit(1i32) }
        var j = 0usize
        while j < i {
            if k.edges[j] == k.edges[i] || bo.edges[j] == bo.edges[i] { os.exit(1i32) }
            j += 1usize
        }
        i += 1usize
    }
    // Kruskal picks the unique MST: edge (2,3) of weight 7 is in it, (7,8) of weight 7 is not.
    var has_23 = false
    var has_78 = false
    i = 0usize
    while i < 8usize {
        let e = g.edges[k.edges[i]]
        if e.from == 2u32 && e.to == 3u32 { has_23 = true }
        if e.from == 7u32 && e.to == 8u32 { has_78 = true }
        i += 1usize
    }
    if !has_23 || has_78 { os.exit(1i32) }
    let (_, prim_invalid) = span.prim[i64, Nothing](a, &g, 9u32, &nothing, weight_of)
    if prim_invalid != span.InvalidNode { os.exit(1i32) }
    // A forest: two components, one isolated node.
    let (c0, c_error) = graph.builder[i64](a, 5usize, 8usize)
    if c_error != ok { os.exit(1i32) }
    var c = c0
    var forest_spec: [9]i64 = zero
    forest_spec[0usize] = 0i64
    forest_spec[1usize] = 1i64
    forest_spec[2usize] = 3i64
    forest_spec[3usize] = 2i64
    forest_spec[4usize] = 3i64
    forest_spec[5usize] = 5i64
    forest_spec[6usize] = 1i64
    forest_spec[7usize] = 0i64
    forest_spec[8usize] = 9i64
    if add_edges(&c, forest_spec[..]) != ok { os.exit(1i32) }
    let (forest, forest_error) = graph.finish[i64](a, &c)
    if forest_error != ok { os.exit(1i32) }
    let (kf, kf_error) = span.kruskal[i64, Nothing](a, &forest, &nothing, weight_of)
    if kf_error != ok || kf.weight != 8.0f64 || kf.edges.len != 2usize || kf.trees != 3usize { os.exit(1i32) }
    let (bf, bf_error) = span.boruvka[i64, Nothing](a, &forest, &nothing, weight_of)
    if bf_error != ok || bf.weight != 8.0f64 || bf.trees != 3usize { os.exit(1i32) }
    let (pf, pf_error) = span.prim[i64, Nothing](a, &forest, 0u32, &nothing, weight_of)
    if pf_error != ok || pf.weight != 3.0f64 || pf.edges.len != 1usize || pf.trees != 4usize { os.exit(1i32) }

    // 2: bridges and articulation points.
    let (d0, d_error) = graph.builder[i64](a, 7usize, 16usize)
    if d_error != ok { os.exit(2i32) }
    var d = d0
    var cut_spec: [24]i64 = zero
    let cut_text = "0 1 1 1 2 1 2 0 1 2 3 1 3 4 1 4 5 1 5 3 1 1 6 1"
    at = 0usize
    cell = 0usize
    while at < cut_text.len {
        var value = 0i64
        while at < cut_text.len && cut_text[at] != 32u8 {
            value = value * 10i64 + i64(cut_text[at] - 48u8)
            at += 1usize
        }
        cut_spec[cell] = value
        cell += 1usize
        at += 1usize
    }
    if add_edges(&d, cut_spec[..]) != ok { os.exit(2i32) }
    let (h, h_error) = graph.finish[i64](a, &d)
    if h_error != ok { os.exit(2i32) }
    var is_bridge: [16]u8 = zero
    var is_cut: [7]u8 = zero
    if span.bridges_and_cuts[i64](a, &h, is_bridge[..], is_cut[..]) != ok { os.exit(2i32) }
    var bridges = 0usize
    var e = 0usize
    while e < h.edges.len {
        if is_bridge[e] == 1u8 {
            bridges += 1usize
            let edge = h.edges[e]
            if edge.from >= edge.to { os.exit(2i32) }
            if !((edge.from == 1u32 && edge.to == 6u32) || (edge.from == 2u32 && edge.to == 3u32)) { os.exit(2i32) }
        }
        e += 1usize
    }
    if bridges != 2usize { os.exit(2i32) }
    if is_cut[1usize] != 1u8 || is_cut[2usize] != 1u8 || is_cut[3usize] != 1u8 { os.exit(2i32) }
    if is_cut[0usize] != 0u8 || is_cut[4usize] != 0u8 || is_cut[5usize] != 0u8 || is_cut[6usize] != 0u8 { os.exit(2i32) }
    if span.bridges_and_cuts[i64](a, &h, is_bridge[..4usize], is_cut[..]) != span.TooSmall { os.exit(2i32) }

    // 3: Eulerian circuit, path and refusal.
    let (e0, e_error) = graph.builder[i64](a, 5usize, 8usize)
    if e_error != ok { os.exit(3i32) }
    var eb = e0
    if graph.add_directed[i64](&eb, 0u32, 1u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&eb, 1u32, 2u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&eb, 2u32, 0u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&eb, 0u32, 3u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&eb, 3u32, 4u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&eb, 4u32, 0u32, 0i64) != ok { os.exit(3i32) }
    let (circuit_graph, cg_error) = graph.finish[i64](a, &eb)
    if cg_error != ok { os.exit(3i32) }
    let (circuit, circuit_error) = span.euler_path[i64](a, &circuit_graph)
    if circuit_error != ok || circuit.len != 7usize || circuit[0usize] != circuit[6usize] { os.exit(3i32) }
    // Consecutive nodes are edges, each edge used once.
    var used: [8]u8 = zero
    i = 0usize
    while i + 1usize < circuit.len {
        var found = false
        var k2 = circuit_graph.offsets[usize(circuit[i])]
        while k2 < circuit_graph.offsets[usize(circuit[i]) + 1usize] {
            if circuit_graph.edges[k2].to == circuit[i + 1usize] && used[k2] == 0u8 && !found {
                used[k2] = 1u8
                found = true
            }
            k2 += 1usize
        }
        if !found { os.exit(3i32) }
        i += 1usize
    }
    let (f0, f_error) = graph.builder[i64](a, 4usize, 4usize)
    if f_error != ok { os.exit(3i32) }
    var fb = f0
    if graph.add_directed[i64](&fb, 0u32, 1u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&fb, 1u32, 2u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&fb, 2u32, 0u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&fb, 0u32, 3u32, 0i64) != ok { os.exit(3i32) }
    let (path_graph, pg_error) = graph.finish[i64](a, &fb)
    if pg_error != ok { os.exit(3i32) }
    let (path, path_error) = span.euler_path[i64](a, &path_graph)
    if path_error != ok || path.len != 5usize || path[0usize] != 0u32 || path[4usize] != 3u32 { os.exit(3i32) }
    let (n0, n_error) = graph.builder[i64](a, 3usize, 4usize)
    if n_error != ok { os.exit(3i32) }
    var nb = n0
    if graph.add_directed[i64](&nb, 0u32, 1u32, 0i64) != ok { os.exit(3i32) }
    if graph.add_directed[i64](&nb, 0u32, 2u32, 0i64) != ok { os.exit(3i32) }
    let (no_graph, ng_error) = graph.finish[i64](a, &nb)
    if ng_error != ok { os.exit(3i32) }
    let (_, not_eulerian) = span.euler_path[i64](a, &no_graph)
    if not_eulerian != span.NotEulerian { os.exit(3i32) }

    // 4: transitive closure of the path graph.
    var reach: [16]u8 = zero
    if span.transitive_closure[i64](&path_graph, reach[..]) != ok { os.exit(4i32) }
    // 0, 1, 2 reach each other and 3; 3 reaches only itself.
    if reach[0usize * 4usize + 3usize] != 1u8 || reach[2usize * 4usize + 1usize] != 1u8 || reach[3usize * 4usize + 0usize] != 0u8 || reach[3usize * 4usize + 3usize] != 1u8 { os.exit(4i32) }
    if span.transitive_closure[i64](&path_graph, reach[..9usize]) != span.TooSmall { os.exit(4i32) }

    try io.print("algo graph span ok\n")
    ret ok
}
