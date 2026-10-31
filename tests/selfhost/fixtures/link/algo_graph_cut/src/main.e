// `e.algo.graph.cut`: Stoer-Wagner finds the karate club's minimum cut of
// one edge isolating node 11 (as NetworkX does on the unweighted club) and the cut of a small
// weighted graph, Karger runs reach the same minimum over enough tries,
// and the argument checks answer. Each check exits with its own code.

use e.algo.graph.cut as cut
use e.algo.rand
use e.data.graph as graph
use e.io
use e.mem
use e.os

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

fn disconnected_graph(a: *mem.Arena) -> (graph.Graph[i64], err) {
    let (builder_value, builder_error) = graph.builder[i64](a, 4usize, 2usize)
    if builder_error != ok { ret (zero, builder_error) }
    var builder = builder_value
    let edge_error = graph.add_undirected[i64](&builder, 0u32, 1u32, 1i64)
    if edge_error != ok { ret (zero, edge_error) }
    let (g, finish_error) = graph.finish[i64](a, &builder)
    ret (g, finish_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (g, g_error) = karate(a)
    if g_error != ok { os.exit(1i32) }

    // 1: Stoer-Wagner on the club's adjacency.
    let (w, w_error) = mem.alloc[f64](a, 34usize * 34usize)
    if w_error != ok { ret w_error }
    var i = 0usize
    while i < 34usize * 34usize {
        w[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < 156usize {
        let e = g.edges[i]
        w[usize(e.from) * 34usize + usize(e.to)] = 1.0f64
        i += 1usize
    }
    var side: [34]u8 = zero
    var scratch: [68]f64 = zero
    var marks: [68]usize = zero
    let (weight, sw_error) = cut.stoer_wagner(w, 34usize, side[..], scratch[..], marks[..])
    if sw_error != ok || weight != 1.0f64 { os.exit(1i32) }
    var ones = 0usize
    i = 0usize
    while i < 34usize {
        if side[i] == 1u8 { ones += 1usize }
        i += 1usize
    }
    // Node 11 alone on one side (either side of the record).
    if !((ones == 1usize && side[11usize] == 1u8) || (ones == 33usize && side[11usize] == 0u8)) { os.exit(1i32) }
    // A weighted four-node example: 0-1 (3), 1-2 (1), 2-3 (3), 3-0 (1): cut 2 between {0,1} and {2,3}.
    var small: [16]f64 = zero
    small[1usize] = 3.0f64
    small[4usize] = 3.0f64
    small[6usize] = 1.0f64
    small[9usize] = 1.0f64
    small[11usize] = 3.0f64
    small[14usize] = 3.0f64
    small[3usize] = 1.0f64
    small[12usize] = 1.0f64
    let (small_cut, small_error) = cut.stoer_wagner(small[..], 4usize, side[..], scratch[..], marks[..])
    if small_error != ok || small_cut != 2.0f64 || side[0usize] != side[1usize] || side[2usize] != side[3usize] || side[0usize] == side[2usize] { os.exit(1i32) }
    let (_, sw_invalid) = cut.stoer_wagner(small[..], 1usize, side[..], scratch[..], marks[..])
    if sw_invalid != cut.Invalid { os.exit(1i32) }

    // 2: Karger.
    var r = rand.pcg64(8u64, 3u64)
    var best_side: [34]u8 = zero
    let no_runs_at = a.off
    let (_, no_runs_error) = cut.karger_best[i64](a, &g, 0usize, &r, best_side[..], side[..])
    if no_runs_error != cut.Invalid || a.off != no_runs_at { os.exit(2i32) }
    let scratch_start = a.off
    let (best, karger_error) = cut.karger_best[i64](a, &g, 400usize, &r, best_side[..], side[..])
    if karger_error != ok || best != 1usize || a.off - scratch_start > 2048usize { os.exit(2i32) }
    ones = 0usize
    i = 0usize
    while i < 34usize {
        if best_side[i] == 1u8 { ones += 1usize }
        i += 1usize
    }
    if ones != 1usize && ones != 33usize { os.exit(2i32) }
    let (single, single_error) = cut.karger[i64](a, &g, &r, side[..])
    if single_error != ok || single < 1usize { os.exit(2i32) }
    let (_, karger_room) = cut.karger[i64](a, &g, &r, side[..3usize])
    if karger_room != cut.TooSmall { os.exit(2i32) }

    let (disconnected, disconnected_error) = disconnected_graph(a)
    if disconnected_error != ok { os.exit(3i32) }
    var disconnected_random = rand.pcg64(11u64, 5u64)
    var disconnected_side: [4]u8 = zero
    let (disconnected_cut, disconnected_karger_error) = cut.karger[i64](a, &disconnected, &disconnected_random, disconnected_side[..])
    if disconnected_karger_error != ok || disconnected_cut != 0usize || disconnected_side[0usize] != disconnected_side[1usize] { os.exit(3i32) }
    var disconnected_zeros = 0usize
    var disconnected_ones = 0usize
    var disconnected_i = 0usize
    while disconnected_i < 4usize {
        if disconnected_side[disconnected_i] == 0u8 { disconnected_zeros += 1usize }
        if disconnected_side[disconnected_i] == 1u8 { disconnected_ones += 1usize }
        if disconnected_side[disconnected_i] > 1u8 { os.exit(3i32) }
        disconnected_i += 1usize
    }
    if disconnected_zeros == 0usize || disconnected_ones == 0usize { os.exit(3i32) }
    var disconnected_best_side: [4]u8 = zero
    let (disconnected_best, disconnected_best_error) = cut.karger_best[i64](a, &disconnected, 8usize, &disconnected_random, disconnected_best_side[..], disconnected_side[..])
    if disconnected_best_error != ok || disconnected_best != 0usize || disconnected_best_side[0usize] != disconnected_best_side[1usize] { os.exit(3i32) }
    disconnected_ones = 0usize
    disconnected_i = 0usize
    while disconnected_i < 4usize {
        if disconnected_best_side[disconnected_i] > 1u8 { os.exit(3i32) }
        if disconnected_best_side[disconnected_i] == 1u8 { disconnected_ones += 1usize }
        disconnected_i += 1usize
    }
    if disconnected_ones == 0usize || disconnected_ones == 4usize { os.exit(3i32) }

    try io.print("algo graph cut ok\n")
    ret ok
}
