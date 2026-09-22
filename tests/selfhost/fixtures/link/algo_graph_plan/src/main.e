// `e.algo.graph`'s plan routines over LCG-generated graphs (replicated in the Python
// reference that produced every expected value): an undirected weighted graph U for the
// three MSTs, Dijkstra by dial and radix heap, Bellman-Ford, low links and path
// reconstruction; a directed graph D with negative edges for Bellman-Ford, Floyd-Warshall,
// Johnson and the arborescence; a DAG A for the transitive closure; a dense graph C for
// triangles, cores, trusses, cliques, center and diameter; an Eulerian multigraph P.
// Every check has its own exit code.
use e.os
use e.io
use e.mem
use e.data.graph as graph
use e.algo.graph as algo

type Lcg = struct { state: u64 }
type Cliques = struct { count: u64, fold: u64, widest: usize }

fn rnd(r: *Lcg) -> u64 {
    r.state = r.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret r.state >> 33u32
}

fn w_f64(ctx: *u8, e: graph.Edge[i64]) -> f64 { ret f64(e.value) }
fn w_usize(ctx: *u8, e: graph.Edge[i64]) -> usize { ret usize(e.value) }
fn w_u32(ctx: *u8, e: graph.Edge[i64]) -> u32 { ret u32(e.value) }

fn on_clique(c: *Cliques, nodes: []const graph.NodeId) {
    var sum = 0u64
    var i = 0usize
    while i < nodes.len {
        sum += u64(nodes[i] + 1u32) * u64(nodes[i] + 1u32)
        i += 1usize
    }
    c.count += 1u64
    c.fold += u64(nodes.len) * sum
    if nodes.len > c.widest { c.widest = nodes.len }
}

// U: a random tree over 48 nodes plus 18 extra edges, weights 1..20.
fn build_u(a: *mem.Arena, b: *graph.Builder[i64], have: []u8) -> err {
    let n = 48usize
    var r = Lcg { state: 11u64 }
    var i = 1usize
    while i < n {
        let u = usize(rnd(&r) % u64(i))
        let w = i64(1u64 + rnd(&r) % 20u64)
        try graph.add_undirected[i64](b, u32(u), u32(i), w)
        have[u * n + i] = 1u8
        have[i * n + u] = 1u8
        i += 1usize
    }
    var added = 0usize
    while added < 18usize {
        let u = usize(rnd(&r) % u64(n))
        let v = usize(rnd(&r) % u64(n))
        let w = i64(1u64 + rnd(&r) % 20u64)
        if u == v || have[u * n + v] == 1u8 { continue }
        have[u * n + v] = 1u8
        have[v * n + u] = 1u8
        try graph.add_undirected[i64](b, u32(u), u32(v), w)
        added += 1usize
    }
    ret ok
}

// D: 40 nodes, a tree from 0 plus 100 extra directed edges, weights from potentials so
// that some are negative and no cycle is.
fn build_d(a: *mem.Arena, b: *graph.Builder[i64], have: []u8, potential: []i64) -> err {
    let n = 40usize
    var r = Lcg { state: 23u64 }
    var i = 0usize
    while i < n {
        potential[i] = i64(rnd(&r) % 30u64)
        i += 1usize
    }
    i = 1usize
    while i < n {
        let u = usize(rnd(&r) % u64(i))
        let w = potential[i] - potential[u] + i64(rnd(&r) % 10u64)
        try graph.add_directed[i64](b, u32(u), u32(i), w)
        have[u * n + i] = 1u8
        i += 1usize
    }
    var added = 0usize
    while added < 100usize {
        let u = usize(rnd(&r) % u64(n))
        let v = usize(rnd(&r) % u64(n))
        let w = potential[v] - potential[u] + i64(rnd(&r) % 10u64)
        if u == v || have[u * n + v] == 1u8 { continue }
        have[u * n + v] = 1u8
        try graph.add_directed[i64](b, u32(u), u32(v), w)
        added += 1usize
    }
    ret ok
}

// A: a DAG over 40 nodes with 90 edges u < v, weights 1..9.
fn build_a(a: *mem.Arena, b: *graph.Builder[i64], have: []u8) -> err {
    let n = 40usize
    var r = Lcg { state: 37u64 }
    var added = 0usize
    while added < 90usize {
        let u = usize(rnd(&r) % u64(n))
        let v = usize(rnd(&r) % u64(n))
        let w = i64(1u64 + rnd(&r) % 9u64)
        if u >= v || have[u * n + v] == 1u8 { continue }
        have[u * n + v] = 1u8
        try graph.add_directed[i64](b, u32(u), u32(v), w)
        added += 1usize
    }
    ret ok
}

// C: 30 nodes, each pair an edge with probability 0.3.
fn build_c(a: *mem.Arena, b: *graph.Builder[i64]) -> err {
    let n = 30usize
    var r = Lcg { state: 41u64 }
    var u = 0usize
    while u < n {
        var v = u + 1usize
        while v < n {
            if rnd(&r) % 10u64 < 3u64 { try graph.add_undirected[i64](b, u32(u), u32(v), 1i64) }
            v += 1usize
        }
        u += 1usize
    }
    ret ok
}

// P: three random cyclic permutations of 12 nodes, so every node has in = out.
fn build_p(a: *mem.Arena, b: *graph.Builder[i64]) -> err {
    let n = 12usize
    var r = Lcg { state: 53u64 }
    var perm: [12]u32 = zero
    var round = 0usize
    while round < 3usize {
        var i = 0usize
        while i < n {
            perm[i] = u32(i)
            i += 1usize
        }
        i = n - 1usize
        while i > 0usize {
            let j = usize(rnd(&r) % u64(i + 1usize))
            let carried = perm[i]
            perm[i] = perm[j]
            perm[j] = carried
            i -= 1usize
        }
        var k = 0usize
        while k < n {
            try graph.add_directed[i64](b, perm[k], perm[(k + 1usize) % n], 1i64)
            k += 1usize
        }
        round += 1usize
    }
    ret ok
}

fn zeroed(a: *mem.Arena, n: usize) -> ([]u8, err) {
    let (out, out_error) = mem.alloc[u8](a, n)
    if out_error != ok { ret (zero, out_error) }
    var i = 0usize
    while i < n {
        out[i] = 0u8
        i += 1usize
    }
    ret (out, ok)
}

fn chosen_weight(g: *const graph.Graph[i64], f: algo.Forest) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < f.edges.len {
        let e = g.edges[f.edges[i]]
        if e.from > e.to { ret -1.0f64 }
        sum += f64(e.value)
        i += 1usize
    }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    var ctx = 0u8
    let (have_u, _) = zeroed(a, 48usize * 48usize)
    let (bu0, _) = graph.builder[i64](a, 48usize, 160usize)
    var bu = bu0
    if build_u(a, &bu, have_u) != ok { os.exit(99) }
    let (gu, gu_error) = graph.finish[i64](a, &bu)
    if gu_error != ok || graph.edge_count[i64](&gu) != 130usize { os.exit(99) }
    let (have_d, _) = zeroed(a, 40usize * 40usize)
    let (potential, _) = mem.alloc[i64](a, 40usize)
    let (bd0, _) = graph.builder[i64](a, 40usize, 160usize)
    var bd = bd0
    if build_d(a, &bd, have_d, potential) != ok { os.exit(99) }
    let (gd, gd_error) = graph.finish[i64](a, &bd)
    if gd_error != ok || graph.edge_count[i64](&gd) != 139usize { os.exit(99) }
    let (have_a, _) = zeroed(a, 40usize * 40usize)
    let (ba0, _) = graph.builder[i64](a, 40usize, 100usize)
    var ba = ba0
    if build_a(a, &ba, have_a) != ok { os.exit(99) }
    let (ga, ga_error) = graph.finish[i64](a, &ba)
    if ga_error != ok || graph.edge_count[i64](&ga) != 90usize { os.exit(99) }
    let (bc0, _) = graph.builder[i64](a, 30usize, 300usize)
    var bc = bc0
    if build_c(a, &bc) != ok { os.exit(99) }
    let (gc, gc_error) = graph.finish[i64](a, &bc)
    if gc_error != ok || graph.edge_count[i64](&gc) != 276usize { os.exit(99) }
    let (bp0, _) = graph.builder[i64](a, 12usize, 40usize)
    var bp = bp0
    if build_p(a, &bp) != ok { os.exit(99) }
    let (gp, gp_error) = graph.finish[i64](a, &bp)
    if gp_error != ok || graph.edge_count[i64](&gp) != 36usize { os.exit(99) }

    // 1-4: the three MSTs agree with networkx (439) and with their own edge lists.
    let (chosen, _) = mem.alloc[usize](a, 48usize)
    let (kruskal, kruskal_error) = algo.mst_kruskal[i64, u8](a, &gu, &ctx, w_f64, chosen)
    if kruskal_error != ok || kruskal.weight != 439.0f64 || kruskal.trees != 1usize { os.exit(1) }
    if kruskal.edges.len != 47usize || chosen_weight(&gu, kruskal) != 439.0f64 { os.exit(1) }
    let (prim, prim_error) = algo.mst_prim[i64, u8](a, &gu, 5u32, &ctx, w_f64, chosen)
    if prim_error != ok || prim.weight != 439.0f64 || prim.trees != 1usize { os.exit(2) }
    if prim.edges.len != 47usize || chosen_weight(&gu, prim) != 439.0f64 { os.exit(2) }
    let (boruvka, boruvka_error) = algo.mst_boruvka[i64, u8](a, &gu, &ctx, w_f64, chosen)
    if boruvka_error != ok || boruvka.weight != 439.0f64 || boruvka.trees != 1usize { os.exit(3) }
    if boruvka.edges.len != 47usize || chosen_weight(&gu, boruvka) != 439.0f64 { os.exit(3) }
    // 5-8: single-source distances on U from 0 four ways (fold 34829).
    let (paths, paths_error) = algo.dijkstra[i64, u8](a, &gu, 0u32, &ctx, w_f64)
    if paths_error != ok { os.exit(5) }
    let (buckets, buckets_error) = algo.dial[i64, u8](a, &gu, 0u32, 20usize, &ctx, w_usize)
    if buckets_error != ok { os.exit(6) }
    let (radix, radix_error) = algo.dijkstra_radix_heap[i64, u8](a, &gu, 0u32, &ctx, w_u32)
    if radix_error != ok { os.exit(7) }
    let (bellman, bellman_error) = algo.bellman_ford[i64, u8](a, &gu, 0u32, &ctx, w_f64)
    if bellman_error != ok { os.exit(8) }
    var fold_d = 0.0f64
    var fold_dial = 0usize
    var fold_radix = 0u64
    var fold_bf = 0.0f64
    var v = 0usize
    while v < 48usize {
        fold_d += paths.distance[v] * f64(v + 1usize)
        fold_dial += buckets[v] * (v + 1usize)
        fold_radix += u64(radix[v]) * u64(v + 1usize)
        fold_bf += bellman.distance[v] * f64(v + 1usize)
        v += 1usize
    }
    if fold_d != 34829.0f64 { os.exit(5) }
    if fold_dial != 34829usize { os.exit(6) }
    if fold_radix != 34829u64 { os.exit(7) }
    if fold_bf != 34829.0f64 { os.exit(8) }
    // 9: Bellman-Ford on D with negative edges (fold -7030, every node reached).
    let (bd_paths, bd_error) = algo.bellman_ford[i64, u8](a, &gd, 0u32, &ctx, w_f64)
    if bd_error != ok { os.exit(9) }
    var fold_bd = 0.0f64
    v = 0usize
    while v < 40usize {
        if bd_paths.distance[v] >= 1.0e300f64 { os.exit(9) }
        fold_bd += bd_paths.distance[v] * f64(v + 1usize)
        v += 1usize
    }
    if fold_bd != -7030.0f64 { os.exit(9) }
    // 10-11: Floyd-Warshall and Johnson agree with networkx and each other.
    let (fw, fw_error) = algo.floyd_warshall[i64, u8](a, &gd, &ctx, w_f64)
    if fw_error != ok { os.exit(10) }
    let (jo, jo_error) = algo.johnson[i64, u8](a, &gd, &ctx, w_f64)
    if jo_error != ok { os.exit(11) }
    var fold_fw = 0.0f64
    var finite = 0usize
    var cell = 0usize
    while cell < 1600usize {
        if fw[cell] < 1.0e300f64 {
            fold_fw += fw[cell] * f64(cell + 1usize)
            finite += 1usize
            if jo[cell] != fw[cell] { os.exit(11) }
        } else if jo[cell] < 1.0e300f64 { os.exit(11) }
        cell += 1usize
    }
    if finite != 1522usize || fold_fw != 11871569.0f64 { os.exit(10) }
    // 12: the arborescence rooted at 0 weighs -208 and uses 39 edges of distinct targets.
    let (arb, arb_error) = algo.arborescence[i64, u8](a, &gd, 0u32, &ctx, w_f64, chosen)
    if arb_error != ok || arb.weight != -208.0f64 || arb.edges.len != 39usize { os.exit(12) }
    let (seen_target, _) = zeroed(a, 40usize)
    var t = 0usize
    while t < 39usize {
        let to = usize(gd.edges[arb.edges[t]].to)
        if to == 0usize || seen_target[to] == 1u8 { os.exit(12) }
        seen_target[to] = 1u8
        t += 1usize
    }
    // 13: 132 triangles in C.
    let (triangles, triangles_error) = algo.count_triangles[i64](a, &gc)
    if triangles_error != ok || triangles != 132u64 { os.exit(13) }
    // 14: core numbers (fold 2772, largest 6).
    let (core, core_error) = algo.k_core[i64](a, &gc)
    if core_error != ok { os.exit(14) }
    var fold_core = 0u64
    var core_max = 0u32
    v = 0usize
    while v < 30usize {
        fold_core += u64(core[v]) * u64(v + 1usize)
        if core[v] > core_max { core_max = core[v] }
        v += 1usize
    }
    if fold_core != 2772u64 || core_max != 6u32 { os.exit(14) }
    // 15: the 4-truss keeps 92 edges (fold 33813 over u * 30 + v).
    let (truss, truss_error) = algo.k_truss[i64](a, &gc, 4u32)
    if truss_error != ok { os.exit(15) }
    var truss_count = 0usize
    var fold_truss = 0usize
    var k = 0usize
    while k < 276usize {
        let e = gc.edges[k]
        if truss[k] == 1u8 && e.from < e.to {
            truss_count += 1usize
            fold_truss += usize(e.from) * 30usize + usize(e.to)
        }
        k += 1usize
    }
    if truss_count != 92usize || fold_truss != 33813usize { os.exit(15) }
    // 16: 78 maximal cliques, the largest of 4 nodes (fold 328711).
    var cliques = Cliques { count: 0u64, fold: 0u64, widest: 0usize }
    let (clique_count, clique_error) = algo.max_cliques[i64, Cliques](a, &gc, &cliques, on_clique)
    if clique_error != ok || clique_count != 78usize || cliques.count != 78u64 { os.exit(16) }
    if cliques.fold != 328711u64 || cliques.widest != 4usize { os.exit(16) }
    // 17-18: center (19 nodes, fold 280) and diameter 3.
    let (middle, middle_error) = algo.center[i64](a, &gc)
    if middle_error != ok || middle.len != 19usize { os.exit(17) }
    var fold_center = 0u64
    v = 0usize
    while v < middle.len {
        fold_center += u64(middle[v]) + 1u64
        v += 1usize
    }
    if fold_center != 280u64 { os.exit(17) }
    let (width, width_error) = algo.diameter[i64](a, &gc)
    if width_error != ok || width != 3u32 { os.exit(18) }
    // 19-20: articulation points (11, fold 106) and bridges (16, fold 7052) of U.
    let (cuts, cuts_error) = algo.articulation_points[i64](a, &gu)
    if cuts_error != ok || cuts.len != 11usize { os.exit(19) }
    var fold_cuts = 0u64
    v = 0usize
    while v < cuts.len {
        fold_cuts += u64(cuts[v]) + 1u64
        v += 1usize
    }
    if fold_cuts != 106u64 { os.exit(19) }
    let (spans, spans_error) = algo.bridges[i64](a, &gu)
    if spans_error != ok || spans.len != 16usize { os.exit(20) }
    var fold_spans = 0usize
    v = 0usize
    while v < spans.len {
        let e = gu.edges[spans[v]]
        if e.from > e.to { os.exit(20) }
        fold_spans += usize(e.from) * 48usize + usize(e.to)
        v += 1usize
    }
    if fold_spans != 7052usize { os.exit(20) }
    // 21: transitive closure of A: 291 reachable pairs off the diagonal (fold 126243).
    let (reach, _) = zeroed(a, 1600usize)
    if algo.transitive_closure[i64](&ga, reach) != ok { os.exit(21) }
    var reach_count = 0usize
    var fold_reach = 0usize
    cell = 0usize
    while cell < 1600usize {
        if reach[cell] == 1u8 && cell / 40usize != cell % 40usize {
            reach_count += 1usize
            fold_reach += cell
        }
        cell += 1usize
    }
    if reach_count != 291usize || fold_reach != 126243usize { os.exit(21) }
    // 22: the path 0 .. 47 from Dijkstra's predecessors walks edges summing to 23.
    let (route, route_error) = algo.path_to(a, paths.previous, 0u32, 47u32)
    if route_error != ok || route.len < 2usize || route[0] != 0u32 || route[route.len - 1usize] != 47u32 { os.exit(22) }
    var along = 0i64
    var step = 0usize
    while step + 1usize < route.len {
        var found = false
        var j = gu.offsets[usize(route[step])]
        while j < gu.offsets[usize(route[step]) + 1usize] {
            if gu.edges[j].to == route[step + 1usize] {
                along += gu.edges[j].value
                found = true
            }
            j += 1usize
        }
        if !found { os.exit(22) }
        step += 1usize
    }
    if along != 23i64 { os.exit(22) }
    let (_, no_route) = algo.path_to(a, bd_paths.previous, 3u32, 0u32)
    if no_route != algo.NoPath { os.exit(22) }
    // 23-24: P's Eulerian circuit uses every edge once; A has none.
    let (walk, walk_error) = algo.euler_path[i64](a, &gp)
    if walk_error != ok || walk.len != 37usize || walk[0] != walk[36] { os.exit(23) }
    let (used, _) = zeroed(a, 36usize)
    step = 0usize
    while step < 36usize {
        var found = false
        var j = gp.offsets[usize(walk[step])]
        while j < gp.offsets[usize(walk[step]) + 1usize] {
            if !found && used[j] == 0u8 && gp.edges[j].to == walk[step + 1usize] {
                used[j] = 1u8
                found = true
            }
            j += 1usize
        }
        if !found { os.exit(23) }
        step += 1usize
    }
    let (_, not_euler) = algo.euler_path[i64](a, &ga)
    if not_euler != algo.NotEulerian { os.exit(24) }
    try io.print("algo graph plan ok\n")
    ret ok
}
