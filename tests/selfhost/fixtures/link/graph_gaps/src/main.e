// `e.algo.graph.*` gap fillers over LCG graphs replicated in the Python reference:
// Leiden on two cliques plus loose nodes agrees with a deterministic replica and
// scores at least Louvain; max-min fair rates by progressive filling; LR planarity
// on K5, K3,3, Petersen, a grid, a wheel and twenty random graphs against NetworkX;
// the auction assignment equals Hungarian and SciPy; greedy best-first against a
// replica, Suurballe against a min-cost flow, Yen's five costs against NetworkX;
// LCA by binary lifting and by Euler-tour RMQ against NetworkX; AHU isomorphism,
// rooted and unrooted. Each check exits with its own code.

use e.algo.graph.community as community
use e.algo.graph.flow as flow
use e.algo.graph.iso as iso
use e.algo.graph.match as match
use e.algo.graph.path as path
use e.algo.graph.tree as tree
use e.data.graph as graph
use e.io
use e.mem
use e.os

type Lcg = struct { state: u64 }
type Ctx = struct { unused: u8 }

fn rnd(r: *Lcg) -> u64 {
    r.state = r.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret r.state >> 33u32
}

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.000000001f64
}

fn weight_of(ctx: *Ctx, e: graph.Edge[i64]) -> f64 { ret f64(e.value) }
fn heuristic_of(ctx: *Ctx, node: graph.NodeId) -> f64 { ret f64((u64(node) * 7u64 + 3u64) % 11u64) }

// An undirected graph on `n` nodes from flattened (u, v) pairs.
fn undirected(a: *mem.Arena, pairs: []const u32, n: usize) -> (graph.Graph[u8], err) {
    let (b0, b_error) = graph.builder[u8](a, n, pairs.len)
    if b_error != ok { ret (zero, b_error) }
    var b = b0
    var i = 0usize
    while i + 1usize < pairs.len {
        let add_error = graph.add_undirected[u8](&b, pairs[i], pairs[i + 1usize], 0u8)
        if add_error != ok { ret (zero, add_error) }
        i += 2usize
    }
    let (g, g_error) = graph.finish[u8](a, &b)
    ret (g, g_error)
}

// Appends the edge (u, v) once; answers the new pair count.
fn add_pair(pairs: []u32, have: []u8, n: usize, u: usize, v: usize, count: usize) -> usize {
    if have[u * n + v] == 1u8 { ret count }
    have[u * n + v] = 1u8
    have[v * n + u] = 1u8
    pairs[2usize * count] = u32(u)
    pairs[2usize * count + 1usize] = u32(v)
    ret count + 1usize
}

fn clique(pairs: []u32, have: []u8, n: usize, lo: usize, hi: usize, count: usize) -> usize {
    var c = count
    var i = lo
    while i < hi {
        var j = i + 1usize
        while j < hi {
            c = add_pair(pairs, have, n, i, j, c)
            j += 1usize
        }
        i += 1usize
    }
    ret c
}

// 1: Leiden on two 5-cliques plus four loose nodes with two LCG edges each.
fn check_leiden(a: *mem.Arena) {
    let n = 14usize
    var pairs: [56]u32 = zero
    var have: [196]u8 = zero
    var count = clique(pairs[..], have[..], n, 0usize, 5usize, 0usize)
    count = clique(pairs[..], have[..], n, 5usize, 10usize, count)
    var r = Lcg { state: 7u64 }
    var v = 10usize
    while v < n {
        var added = 0usize
        while added < 2usize {
            let u = usize(rnd(&r) % u64(v))
            if have[u * n + v] == 1u8 { continue }
            count = add_pair(pairs[..], have[..], n, u, v, count)
            added += 1usize
        }
        v += 1usize
    }
    if count != 28usize { os.exit(1i32) }
    let (g, g_error) = undirected(a, pairs[..], n)
    if g_error != ok { os.exit(1i32) }
    var labels: [14]u32 = zero
    let (q, q_error) = community.leiden[u8](a, &g, labels[..])
    if q_error != ok { os.exit(1i32) }
    var h = 0u32
    var i = 0usize
    while i < n {
        h = h *% 31u32 +% labels[i]
        i += 1usize
    }
    if h != 852414210u32 || !near(q, 0.43431122448979614f64) { os.exit(1i32) }
    var louvain_labels: [14]u32 = zero
    let (ql, ql_error) = community.louvain[u8](a, &g, louvain_labels[..])
    if ql_error != ok || ql > q + 0.000000001f64 { os.exit(1i32) }
    if !near(community.modularity[u8](&g, labels[..]), q) { os.exit(1i32) }
}

// 2: max-min fair rates over six LCG links and eight flows.
fn check_flow(a: *mem.Arena) {
    var r = Lcg { state: 11u64 }
    var caps: [6]f64 = zero
    var l = 0usize
    while l < 6usize {
        caps[l] = f64(1u64 + rnd(&r) % 20u64)
        l += 1usize
    }
    var offsets: [9]usize = zero
    var links: [24]u32 = zero
    var total = 0usize
    var f = 0usize
    while f < 8usize {
        let k = 1usize + usize(rnd(&r) % 3u64)
        offsets[f] = total
        var got = 0usize
        while got < k {
            let link = u32(rnd(&r) % 6u64)
            var dup = false
            var i = offsets[f]
            while i < total {
                if links[i] == link { dup = true }
                i += 1usize
            }
            if dup { continue }
            links[total] = link
            total += 1usize
            got += 1usize
        }
        f += 1usize
    }
    offsets[8usize] = total
    var rates: [8]f64 = zero
    let (rounds, rounds_error) = flow.max_min_fair(a, caps[..], offsets[..], links[..total], rates[..])
    if rounds_error != ok || rounds != 4usize { os.exit(2i32) }
    var weighted = 0.0f64
    f = 0usize
    while f < 8usize {
        weighted += rates[f] * f64(f + 1usize)
        f += 1usize
    }
    if !near(weighted, 133.4f64) || !near(rates[5usize], 10.4f64) || !near(rates[0usize], 0.8f64) { os.exit(2i32) }
    let (_, short) = flow.max_min_fair(a, caps[..], offsets[..], links[..total], rates[..3usize])
    if short != flow.TooSmall { os.exit(2i32) }
}

fn planar_of(a: *mem.Arena, pairs: []const u32, n: usize, code: i32) -> bool {
    let (g, g_error) = undirected(a, pairs, n)
    if g_error != ok { os.exit(code) }
    let (planar, planar_error) = iso.is_planar[u8](a, &g)
    if planar_error != ok { os.exit(code) }
    ret planar
}

// 3: planarity of the named graphs and twenty LCG graphs on eight nodes.
fn check_planar(a: *mem.Arena) {
    var pairs: [40]u32 = zero
    var have: [144]u8 = zero
    var count = clique(pairs[..], have[..], 5usize, 0usize, 5usize, 0usize)
    if count != 10usize || planar_of(a, pairs[..2usize * count], 5usize, 3i32) { os.exit(3i32) }
    // K3,3.
    var i = 0usize
    while i < 144usize {
        have[i] = 0u8
        i += 1usize
    }
    count = 0usize
    i = 0usize
    while i < 3usize {
        var j = 3usize
        while j < 6usize {
            count = add_pair(pairs[..], have[..], 6usize, i, j, count)
            j += 1usize
        }
        i += 1usize
    }
    if planar_of(a, pairs[..2usize * count], 6usize, 3i32) { os.exit(3i32) }
    // Petersen: outer cycle, spokes, inner pentagram.
    i = 0usize
    while i < 144usize {
        have[i] = 0u8
        i += 1usize
    }
    count = 0usize
    i = 0usize
    while i < 5usize {
        count = add_pair(pairs[..], have[..], 10usize, i, (i + 1usize) % 5usize, count)
        count = add_pair(pairs[..], have[..], 10usize, i, i + 5usize, count)
        count = add_pair(pairs[..], have[..], 10usize, i + 5usize, (i + 2usize) % 5usize + 5usize, count)
        i += 1usize
    }
    if count != 15usize || planar_of(a, pairs[..2usize * count], 10usize, 3i32) { os.exit(3i32) }
    // A 3 x 4 grid.
    i = 0usize
    while i < 144usize {
        have[i] = 0u8
        i += 1usize
    }
    count = 0usize
    var row = 0usize
    while row < 3usize {
        var col = 0usize
        while col < 4usize {
            if col < 3usize { count = add_pair(pairs[..], have[..], 12usize, row * 4usize + col, row * 4usize + col + 1usize, count) }
            if row < 2usize { count = add_pair(pairs[..], have[..], 12usize, row * 4usize + col, (row + 1usize) * 4usize + col, count) }
            col += 1usize
        }
        row += 1usize
    }
    if count != 17usize || !planar_of(a, pairs[..2usize * count], 12usize, 4i32) { os.exit(4i32) }
    // The wheel on seven nodes.
    i = 0usize
    while i < 144usize {
        have[i] = 0u8
        i += 1usize
    }
    count = 0usize
    i = 1usize
    while i < 7usize {
        count = add_pair(pairs[..], have[..], 7usize, 0usize, i, count)
        count = add_pair(pairs[..], have[..], 7usize, i, i % 6usize + 1usize, count)
        i += 1usize
    }
    if count != 12usize || !planar_of(a, pairs[..2usize * count], 7usize, 4i32) { os.exit(4i32) }
    // Twenty LCG graphs against NetworkX's answers, as a bitmask.
    var r = Lcg { state: 23u64 }
    var mask = 0u32
    var t = 0usize
    while t < 20usize {
        let m = 13usize + usize(rnd(&r) % 6u64)
        i = 0usize
        while i < 64usize {
            have[i] = 0u8
            i += 1usize
        }
        count = 0usize
        while count < m {
            let u = usize(rnd(&r) % 8u64)
            let v = usize(rnd(&r) % 8u64)
            if u == v || have[u * 8usize + v] == 1u8 { continue }
            count = add_pair(pairs[..], have[..], 8usize, u, v, count)
        }
        if planar_of(a, pairs[..2usize * count], 8usize, 5i32) { mask = mask | (1u32 << u32(t)) }
        t += 1usize
    }
    if mask != 680277u32 { os.exit(5i32) }
}

// 4: the auction assignment over a 12 x 12 LCG benefit matrix.
fn check_auction(a: *mem.Arena) {
    var r = Lcg { state: 31u64 }
    let n = 12usize
    var benefit: [144]f64 = zero
    var costs: [144]f64 = zero
    var i = 0usize
    while i < 144usize {
        benefit[i] = f64(1u64 + rnd(&r) % 99u64)
        costs[i] = 0.0f64 - benefit[i]
        i += 1usize
    }
    var assignment: [12]usize = zero
    var prices: [12]f64 = zero
    var owner: [12]usize = zero
    let (total, total_error) = match.auction(benefit[..], n, assignment[..], prices[..], owner[..], 0.05f64)
    if total_error != ok || !near(total, 1048.0f64) { os.exit(6i32) }
    var seen: [12]u8 = zero
    var check = 0.0f64
    i = 0usize
    while i < n {
        if assignment[i] >= n || seen[assignment[i]] == 1u8 { os.exit(6i32) }
        seen[assignment[i]] = 1u8
        check += benefit[i * n + assignment[i]]
        i += 1usize
    }
    if !near(check, total) { os.exit(6i32) }
    var assignment2: [12]usize = zero
    var scratch: [52]f64 = zero
    var used: [26]usize = zero
    let (cost, cost_error) = match.hungarian(costs[..], n, assignment2[..], scratch[..], used[..])
    if cost_error != ok || !near(0.0f64 - cost, total) { os.exit(6i32) }
    let (_, bad) = match.auction(benefit[..], n, assignment[..], prices[..], owner[..], 0.0f64)
    if bad != match.Invalid { os.exit(6i32) }
}

// 5: best-first, Suurballe and Yen on a 10-node LCG digraph with 30 edges.
fn check_paths(a: *mem.Arena) {
    var r = Lcg { state: 47u64 }
    let n = 10usize
    let (b0, b_error) = graph.builder[i64](a, n, 30usize)
    if b_error != ok { os.exit(7i32) }
    var b = b0
    var have: [100]u8 = zero
    var i = 1usize
    while i < n {
        let u = usize(rnd(&r) % u64(i))
        let w = i64(1u64 + rnd(&r) % 9u64)
        if graph.add_directed[i64](&b, u32(u), u32(i), w) != ok { os.exit(7i32) }
        have[u * n + i] = 1u8
        i += 1usize
    }
    var edges = 9usize
    while edges < 30usize {
        let u = usize(rnd(&r) % u64(n))
        let v = usize(rnd(&r) % u64(n))
        let w = i64(1u64 + rnd(&r) % 9u64)
        if u == v || have[u * n + v] == 1u8 { continue }
        have[u * n + v] = 1u8
        if graph.add_directed[i64](&b, u32(u), u32(v), w) != ok { os.exit(7i32) }
        edges += 1usize
    }
    let (g, g_error) = graph.finish[i64](a, &b)
    if g_error != ok { os.exit(7i32) }
    var ctx = Ctx { unused: 0u8 }
    // Best-first: the replica's route and its cost.
    let (greedy, greedy_error) = path.best_first[i64, Ctx](a, &g, 0u32, 9u32, &ctx, weight_of, heuristic_of)
    if greedy_error != ok || !near(greedy.cost, 14.0f64) { os.exit(7i32) }
    var h = 0u32
    i = 0usize
    while i < greedy.nodes.len {
        h = h *% 31u32 +% greedy.nodes[i]
        i += 1usize
    }
    if h != 195u32 { os.exit(7i32) }
    let (_, greedy_none) = path.best_first[i64, Ctx](a, &g, 3u32, 0u32, &ctx, weight_of, heuristic_of)
    if greedy_none != path.NoPath { os.exit(7i32) }
    // Suurballe: two edge-disjoint routes costing what a min-cost flow of two units costs.
    let (pair, pair_error) = path.suurballe[i64, Ctx](a, &g, 0u32, 9u32, &ctx, weight_of)
    if pair_error != ok || !near(pair.cost, 27.0f64) { os.exit(8i32) }
    if pair.first[0usize] != 0u32 || pair.first[pair.first.len - 1usize] != 9u32 { os.exit(8i32) }
    if pair.second[0usize] != 0u32 || pair.second[pair.second.len - 1usize] != 9u32 { os.exit(8i32) }
    i = 0usize
    while i + 1usize < pair.first.len {
        var j = 0usize
        while j + 1usize < pair.second.len {
            if pair.first[i] == pair.second[j] && pair.first[i + 1usize] == pair.second[j + 1usize] { os.exit(8i32) }
            j += 1usize
        }
        i += 1usize
    }
    // Yen: the five cheapest loopless routes cost what NetworkX says.
    let (routes, routes_error) = path.yen_k_shortest[i64, Ctx](a, &g, 0u32, 9u32, 5usize, &ctx, weight_of)
    if routes_error != ok || routes.costs.len != 5usize { os.exit(9i32) }
    var want: [5]f64 = zero
    want[0usize] = 13.0f64
    want[1usize] = 14.0f64
    want[2usize] = 16.0f64
    want[3usize] = 19.0f64
    want[4usize] = 23.0f64
    i = 0usize
    while i < 5usize {
        if !near(routes.costs[i], want[i]) { os.exit(9i32) }
        if routes.nodes[routes.offsets[i]] != 0u32 || routes.nodes[routes.offsets[i + 1usize] - 1usize] != 9u32 { os.exit(9i32) }
        i += 1usize
    }
    if routes.offsets[5usize] != routes.nodes.len { os.exit(9i32) }
}

// 6: LCA by lifting and RMQ on an LCG tree, and AHU isomorphism.
fn check_tree(a: *mem.Arena) {
    var r = Lcg { state: 53u64 }
    let n = 14usize
    var parent: [14]u32 = zero
    var pairs: [26]u32 = zero
    var i = 1usize
    while i < n {
        parent[i] = u32(rnd(&r) % u64(i))
        pairs[2usize * (i - 1usize)] = parent[i]
        pairs[2usize * (i - 1usize) + 1usize] = u32(i)
        i += 1usize
    }
    let (g1, g1_error) = undirected(a, pairs[..], n)
    if g1_error != ok { os.exit(10i32) }
    var queries: [24]u32 = zero
    i = 0usize
    while i < 24usize {
        queries[i] = u32(rnd(&r) % u64(n))
        i += 1usize
    }
    let (l, l_error) = tree.lca_binary_lifting[u8](a, &g1, 0u32)
    if l_error != ok { os.exit(10i32) }
    let (t, t_error) = tree.root_at[u8](a, &g1, 0u32)
    if t_error != ok { os.exit(10i32) }
    let (rq, rq_error) = tree.lca_rmq[u8](a, &g1, &t)
    if rq_error != ok { os.exit(10i32) }
    var by_lifting = 0u64
    var by_rmq = 0u64
    var q = 0usize
    while q < 12usize {
        let x = queries[2usize * q]
        let y = queries[2usize * q + 1usize]
        let first = tree.lca(&l, x, y)
        let second = tree.lca_rmq_query(&rq, x, y)
        if first != second { os.exit(10i32) }
        by_lifting += u64(first) * u64(q + 1usize)
        by_rmq += u64(second) * u64(q + 1usize)
        q += 1usize
    }
    if by_lifting != 111u64 || by_rmq != 111u64 { os.exit(10i32) }
    // A relabelled copy is isomorphic, a re-parented leaf is not.
    var perm: [14]u32 = zero
    i = 0usize
    while i < n {
        perm[i] = u32(i)
        i += 1usize
    }
    i = n - 1usize
    while i > 0usize {
        let j = usize(rnd(&r) % u64(i + 1usize))
        let swap = perm[i]
        perm[i] = perm[j]
        perm[j] = swap
        i -= 1usize
    }
    var pairs2: [26]u32 = zero
    var pairs3: [26]u32 = zero
    i = 0usize
    while i < 26usize {
        pairs2[i] = perm[usize(pairs[i])]
        pairs3[i] = pairs[i]
        i += 1usize
    }
    pairs3[24usize] = (parent[13usize] + 1u32) % 13u32
    let (g2, g2_error) = undirected(a, pairs2[..], n)
    if g2_error != ok { os.exit(11i32) }
    let (g3, g3_error) = undirected(a, pairs3[..], n)
    if g3_error != ok { os.exit(11i32) }
    let (same12, same12_error) = tree.is_isomorphic[u8](a, &g1, &g2)
    if same12_error != ok || !same12 { os.exit(11i32) }
    let (same13, same13_error) = tree.is_isomorphic[u8](a, &g1, &g3)
    if same13_error != ok || same13 { os.exit(11i32) }
    let (rooted12, rooted12_error) = tree.is_isomorphic_rooted[u8](a, &g1, 0u32, &g2, perm[0usize])
    if rooted12_error != ok || !rooted12 { os.exit(11i32) }
    let (rooted11, rooted11_error) = tree.is_isomorphic_rooted[u8](a, &g1, 0u32, &g1, 5u32)
    if rooted11_error != ok || rooted11 { os.exit(11i32) }
    let (rooted13, rooted13_error) = tree.is_isomorphic_rooted[u8](a, &g1, 0u32, &g3, 0u32)
    if rooted13_error != ok || rooted13 { os.exit(11i32) }
    // Two centres: a path of four against a relabelled path and against a star.
    var p4: [6]u32 = zero
    p4[1usize] = 1u32
    p4[2usize] = 1u32
    p4[3usize] = 2u32
    p4[4usize] = 2u32
    p4[5usize] = 3u32
    var p4b: [6]u32 = zero
    p4b[0usize] = 2u32
    p4b[3usize] = 3u32
    p4b[4usize] = 3u32
    p4b[5usize] = 1u32
    var star: [6]u32 = zero
    star[1usize] = 1u32
    star[3usize] = 2u32
    star[5usize] = 3u32
    let (pa, pa_error) = undirected(a, p4[..], 4usize)
    let (pb, pb_error) = undirected(a, p4b[..], 4usize)
    let (st, st_error) = undirected(a, star[..], 4usize)
    if pa_error != ok || pb_error != ok || st_error != ok { os.exit(12i32) }
    let (paths_same, paths_error) = tree.is_isomorphic[u8](a, &pa, &pb)
    if paths_error != ok || !paths_same { os.exit(12i32) }
    let (star_same, star_error) = tree.is_isomorphic[u8](a, &pa, &st)
    if star_error != ok || star_same { os.exit(12i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    check_leiden(a)
    check_flow(a)
    check_planar(a)
    check_auction(a)
    check_paths(a)
    check_tree(a)
    try io.print("graph gaps ok\n")
    ret ok
}
