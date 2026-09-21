// `e.algo.graph.match`: Hopcroft-Karp finds a perfect matching where one
// exists and the right size where none does; the Hungarian algorithm agrees
// with SciPy's linear_sum_assignment on two matrices; Gale-Shapley produces a
// stable, proposer-optimal marriage; the blossom algorithm matches a graph of
// two odd cycles and the Petersen graph. Each check exits with its own code.

use e.algo.graph.match
use e.data.graph as graph
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: Hopcroft-Karp. Left 0..3, right 3..6: 0-3, 0-4, 1-3, 2-4, 2-5.
    let (b0, b_error) = graph.builder[u8](a, 6usize, 5usize)
    if b_error != ok { os.exit(1i32) }
    var b = b0
    if graph.add_directed[u8](&b, 0u32, 3u32, 0u8) != ok { os.exit(1i32) }
    if graph.add_directed[u8](&b, 0u32, 4u32, 0u8) != ok { os.exit(1i32) }
    if graph.add_directed[u8](&b, 1u32, 3u32, 0u8) != ok { os.exit(1i32) }
    if graph.add_directed[u8](&b, 2u32, 4u32, 0u8) != ok { os.exit(1i32) }
    if graph.add_directed[u8](&b, 2u32, 5u32, 0u8) != ok { os.exit(1i32) }
    let (g, g_error) = graph.finish[u8](a, &b)
    if g_error != ok { os.exit(1i32) }
    var match_left: [3]u32 = zero
    var match_right: [3]u32 = zero
    let (size, size_error) = match.hopcroft_karp[u8](a, &g, 3usize, match_left[..], match_right[..])
    if size_error != ok || size != 3usize { os.exit(1i32) }
    // A valid matching: consistent both ways, each pair an edge.
    var l = 0usize
    while l < 3usize {
        let r = match_left[l]
        if r == match.NONE || match_right[usize(r) - 3usize] != u32(l) { os.exit(1i32) }
        var is_edge = false
        var k = g.offsets[l]
        while k < g.offsets[l + 1usize] {
            if g.edges[k].to == r { is_edge = true }
            k += 1usize
        }
        if !is_edge { os.exit(1i32) }
        l += 1usize
    }
    // Two left nodes competing for one right node: size 1 of 2... plus a free pair: 2 of 3.
    let (c0, c_error) = graph.builder[u8](a, 6usize, 3usize)
    if c_error != ok { os.exit(1i32) }
    var c = c0
    if graph.add_directed[u8](&c, 0u32, 3u32, 0u8) != ok { os.exit(1i32) }
    if graph.add_directed[u8](&c, 1u32, 3u32, 0u8) != ok { os.exit(1i32) }
    if graph.add_directed[u8](&c, 2u32, 5u32, 0u8) != ok { os.exit(1i32) }
    let (h, h_error) = graph.finish[u8](a, &c)
    if h_error != ok { os.exit(1i32) }
    let (size2, size2_error) = match.hopcroft_karp[u8](a, &h, 3usize, match_left[..], match_right[..])
    if size2_error != ok || size2 != 2usize || match_right[1usize] != match.NONE { os.exit(1i32) }
    let (_, room) = match.hopcroft_karp[u8](a, &h, 3usize, match_left[..2usize], match_right[..])
    if room != match.TooSmall { os.exit(1i32) }

    // 2: the Hungarian algorithm.
    var costs: [9]f64 = zero
    costs[0usize] = 4.0f64
    costs[1usize] = 1.0f64
    costs[2usize] = 3.0f64
    costs[3usize] = 2.0f64
    costs[4usize] = 0.0f64
    costs[5usize] = 5.0f64
    costs[6usize] = 3.0f64
    costs[7usize] = 2.0f64
    costs[8usize] = 2.0f64
    var assignment: [5]usize = zero
    var scratch: [24]f64 = zero
    var used: [12]usize = zero
    let (total, total_error) = match.hungarian(costs[..], 3usize, assignment[..], scratch[..], used[..])
    if total_error != ok || total != 5.0f64 || assignment[0usize] != 1usize || assignment[1usize] != 0usize || assignment[2usize] != 2usize { os.exit(2i32) }
    var costs5: [25]f64 = zero
    let rows = "9 11 14 11 7 6 15 13 13 10 12 13 6 8 8 11 9 10 12 9 7 12 14 10 14"
    var at = 0usize
    var cell = 0usize
    while at < rows.len {
        var value = 0.0f64
        while at < rows.len && rows[at] != 32u8 {
            value = value * 10.0f64 + f64(rows[at] - 48u8)
            at += 1usize
        }
        costs5[cell] = value
        cell += 1usize
        at += 1usize
    }
    let (total5, total5_error) = match.hungarian(costs5[..], 5usize, assignment[..], scratch[..], used[..])
    if total5_error != ok || total5 != 38.0f64 { os.exit(2i32) }
    if assignment[0usize] != 4usize || assignment[1usize] != 0usize || assignment[2usize] != 2usize || assignment[3usize] != 1usize || assignment[4usize] != 3usize { os.exit(2i32) }
    let (_, hungarian_room) = match.hungarian(costs5[..], 5usize, assignment[..], scratch[..20usize], used[..])
    if hungarian_room != match.TooSmall { os.exit(2i32) }

    // 3: stable marriage: the textbook 3x3 instance.
    // Proposers: A: X Y Z; B: Y X Z; C: X Y Z. Receivers: X: B A C; Y: A B C; Z: A B C.
    var proposers: [9]usize = zero
    proposers[0usize] = 0usize
    proposers[1usize] = 1usize
    proposers[2usize] = 2usize
    proposers[3usize] = 1usize
    proposers[4usize] = 0usize
    proposers[5usize] = 2usize
    proposers[6usize] = 0usize
    proposers[7usize] = 1usize
    proposers[8usize] = 2usize
    var receivers: [9]usize = zero
    receivers[0usize] = 1usize
    receivers[1usize] = 0usize
    receivers[2usize] = 2usize
    receivers[3usize] = 0usize
    receivers[4usize] = 1usize
    receivers[5usize] = 2usize
    receivers[6usize] = 0usize
    receivers[7usize] = 1usize
    receivers[8usize] = 2usize
    var married: [3]usize = zero
    var marriage_scratch: [9]usize = zero
    if match.stable_marriage(proposers[..], receivers[..], 3usize, married[..], marriage_scratch[..]) != ok { os.exit(3i32) }
    // Proposer-optimal: A gets X, B gets Y, C gets Z.
    if married[0usize] != 0usize || married[1usize] != 1usize || married[2usize] != 2usize { os.exit(3i32) }
    // Stability: no proposer prefers a receiver who prefers them back.
    var p = 0usize
    while p < 3usize {
        var rank_mine = 0usize
        while proposers[p * 3usize + rank_mine] != married[p] { rank_mine += 1usize }
        var better = 0usize
        while better < rank_mine {
            let r = proposers[p * 3usize + better]
            var partner = 0usize
            while married[partner] != r { partner += 1usize }
            var rank_p = 0usize
            while receivers[r * 3usize + rank_p] != p { rank_p += 1usize }
            var rank_partner = 0usize
            while receivers[r * 3usize + rank_partner] != partner { rank_partner += 1usize }
            if rank_p < rank_partner { os.exit(3i32) }
            better += 1usize
        }
        p += 1usize
    }
    if match.stable_marriage(proposers[..], receivers[..], 3usize, married[..], marriage_scratch[..6usize]) != match.TooSmall { os.exit(3i32) }

    // 4: the blossom algorithm on two triangles joined by a bridge plus a pendant, and Petersen.
    let (d0, d_error) = graph.builder[u8](a, 7usize, 16usize)
    if d_error != ok { os.exit(4i32) }
    var d = d0
    if graph.add_undirected[u8](&d, 0u32, 1u32, 0u8) != ok { os.exit(4i32) }
    if graph.add_undirected[u8](&d, 1u32, 2u32, 0u8) != ok { os.exit(4i32) }
    if graph.add_undirected[u8](&d, 2u32, 0u32, 0u8) != ok { os.exit(4i32) }
    if graph.add_undirected[u8](&d, 2u32, 3u32, 0u8) != ok { os.exit(4i32) }
    if graph.add_undirected[u8](&d, 3u32, 4u32, 0u8) != ok { os.exit(4i32) }
    if graph.add_undirected[u8](&d, 4u32, 5u32, 0u8) != ok { os.exit(4i32) }
    if graph.add_undirected[u8](&d, 5u32, 3u32, 0u8) != ok { os.exit(4i32) }
    if graph.add_undirected[u8](&d, 1u32, 6u32, 0u8) != ok { os.exit(4i32) }
    let (odd, odd_error) = graph.finish[u8](a, &d)
    if odd_error != ok { os.exit(4i32) }
    var mate: [10]u32 = zero
    let (matched, matched_error) = match.blossom[u8](a, &odd, mate[..])
    if matched_error != ok || matched != 3usize { os.exit(4i32) }
    var v = 0usize
    while v < 7usize {
        if mate[v] != match.NONE {
            if mate[usize(mate[v])] != u32(v) { os.exit(4i32) }
            var is_edge = false
            var k = odd.offsets[v]
            while k < odd.offsets[v + 1usize] {
                if odd.edges[k].to == mate[v] { is_edge = true }
                k += 1usize
            }
            if !is_edge { os.exit(4i32) }
        }
        v += 1usize
    }
    // Petersen: outer 5-cycle 0..4, inner pentagram 5..9, spokes i -- i + 5.
    let (p0, p_error) = graph.builder[u8](a, 10usize, 30usize)
    if p_error != ok { os.exit(4i32) }
    var pb = p0
    var i = 0u32
    while i < 5u32 {
        if graph.add_undirected[u8](&pb, i, (i + 1u32) % 5u32, 0u8) != ok { os.exit(4i32) }
        if graph.add_undirected[u8](&pb, 5u32 + i, 5u32 + (i + 2u32) % 5u32, 0u8) != ok { os.exit(4i32) }
        if graph.add_undirected[u8](&pb, i, i + 5u32, 0u8) != ok { os.exit(4i32) }
        i += 1u32
    }
    let (petersen, petersen_error) = graph.finish[u8](a, &pb)
    if petersen_error != ok { os.exit(4i32) }
    let (perfect, perfect_error) = match.blossom[u8](a, &petersen, mate[..])
    if perfect_error != ok || perfect != 5usize { os.exit(4i32) }
    let (_, blossom_room) = match.blossom[u8](a, &petersen, mate[..4usize])
    if blossom_room != match.TooSmall { os.exit(4i32) }

    try io.print("algo graph match ok\n")
    ret ok
}
