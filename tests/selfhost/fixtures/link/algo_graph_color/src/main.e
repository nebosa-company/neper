// `e.algo.graph.color`: Welsh-Powell and DSATUR colour the karate club
// properly with five colours (as NetworkX does), a bipartite graph with two,
// and the complete graph on five nodes with five. Each check exits with
// its own code.

use e.algo.graph.color as color
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (g, g_error) = karate(a)
    if g_error != ok { os.exit(1i32) }
    var colors: [34]u32 = zero
    var order: [34]usize = zero
    var used: [35]usize = zero

    // 1: the club.
    let (greedy_count, greedy_error) = color.greedy[i64](&g, colors[..], order[..], used[..])
    if greedy_error != ok || greedy_count != 5usize || !color.is_proper[i64](&g, colors[..]) { os.exit(1i32) }
    let (dsatur_count, dsatur_error) = color.dsatur[i64](&g, colors[..], order[..], used[..])
    if dsatur_error != ok || dsatur_count != 5usize || !color.is_proper[i64](&g, colors[..]) { os.exit(1i32) }
    colors[1usize] = colors[0usize]
    if color.is_proper[i64](&g, colors[..]) { os.exit(1i32) }
    let (_, room) = color.greedy[i64](&g, colors[..10usize], order[..], used[..])
    if room != color.TooSmall { os.exit(1i32) }

    // 2: a 6-cycle takes two colours; K5 takes five.
    let (b0, b_error) = graph.builder[i64](a, 6usize, 12usize)
    if b_error != ok { ret b_error }
    var b = b0
    var i = 0usize
    while i < 6usize {
        if graph.add_undirected[i64](&b, u32(i), u32((i + 1usize) % 6usize), 1i64) != ok { os.exit(2i32) }
        i += 1usize
    }
    let (cycle, cycle_error) = graph.finish[i64](a, &b)
    if cycle_error != ok { ret cycle_error }
    let (c1, c1_error) = color.greedy[i64](&cycle, colors[..], order[..], used[..])
    if c1_error != ok || c1 != 2usize || !color.is_proper[i64](&cycle, colors[..]) { os.exit(2i32) }
    let (c2, c2_error) = color.dsatur[i64](&cycle, colors[..], order[..], used[..])
    if c2_error != ok || c2 != 2usize || !color.is_proper[i64](&cycle, colors[..]) { os.exit(2i32) }
    let (k0, k_error) = graph.builder[i64](a, 5usize, 20usize)
    if k_error != ok { ret k_error }
    var k = k0
    i = 0usize
    while i < 5usize {
        var j = i + 1usize
        while j < 5usize {
            if graph.add_undirected[i64](&k, u32(i), u32(j), 1i64) != ok { os.exit(2i32) }
            j += 1usize
        }
        i += 1usize
    }
    let (complete, complete_error) = graph.finish[i64](a, &k)
    if complete_error != ok { ret complete_error }
    let (c3, c3_error) = color.dsatur[i64](&complete, colors[..], order[..], used[..])
    if c3_error != ok || c3 != 5usize || !color.is_proper[i64](&complete, colors[..]) { os.exit(2i32) }

    try io.print("algo graph color ok\n")
    ret ok
}
