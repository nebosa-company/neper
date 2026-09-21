// `e.algo.graph.iso`: a path and a triangle are found inside the karate
// club and a 4-cycle is not found inside a tree, two drawings of the
// Petersen graph are isomorphic while a 10-node cycle is not, and the
// storage check answers. Each check exits with its own code.

use e.algo.graph.iso as iso
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

fn small(a: *mem.Arena, n: usize, spec: []const u32) -> (graph.Graph[i64], err) {
    let (b0, b_error) = graph.builder[i64](a, n, 2usize * spec.len)
    if b_error != ok { ret (zero, b_error) }
    var b = b0
    var i = 0usize
    while i + 1usize < spec.len {
        if graph.add_undirected[i64](&b, spec[i], spec[i + 1usize], 1i64) != ok { ret (zero, graph.TooLarge) }
        i += 2usize
    }
    let (g, g_error) = graph.finish[i64](a, &b)
    ret (g, g_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (club, club_error) = karate(a)
    if club_error != ok { os.exit(1i32) }
    var mapping: [34]u32 = zero
    var used: [34]u8 = zero

    // 1: subgraphs of the club.
    var triangle: [6]u32 = zero
    triangle[1usize] = 1u32
    triangle[2usize] = 1u32
    triangle[3usize] = 2u32
    triangle[4usize] = 2u32
    let (tri, tri_error) = small(a, 3usize, triangle[..])
    if tri_error != ok { ret tri_error }
    let (found, find_error) = iso.subgraph_vf2[i64](&tri, &club, mapping[..], used[..])
    if find_error != ok || !found { os.exit(1i32) }
    // The mapped nodes form a triangle in the club.
    if !iso.adjacent[i64](&club, usize(mapping[0usize]), usize(mapping[1usize])) || !iso.adjacent[i64](&club, usize(mapping[1usize]), usize(mapping[2usize])) || !iso.adjacent[i64](&club, usize(mapping[0usize]), usize(mapping[2usize])) { os.exit(1i32) }
    // A 4-cycle is not inside a path of five nodes.
    var square: [8]u32 = zero
    square[1usize] = 1u32
    square[2usize] = 1u32
    square[3usize] = 2u32
    square[4usize] = 2u32
    square[5usize] = 3u32
    square[6usize] = 3u32
    let (sq, sq_error) = small(a, 4usize, square[..])
    if sq_error != ok { ret sq_error }
    var path_spec: [8]u32 = zero
    path_spec[1usize] = 1u32
    path_spec[2usize] = 1u32
    path_spec[3usize] = 2u32
    path_spec[4usize] = 2u32
    path_spec[5usize] = 3u32
    path_spec[6usize] = 3u32
    path_spec[7usize] = 4u32
    let (path, path_error) = small(a, 5usize, path_spec[..])
    if path_error != ok { ret path_error }
    let (in_path, in_path_error) = iso.subgraph_vf2[i64](&sq, &path, mapping[..], used[..])
    if in_path_error != ok || in_path { os.exit(1i32) }
    let (path_in_club, pic_error) = iso.subgraph_vf2[i64](&path, &club, mapping[..], used[..])
    if pic_error != ok || !path_in_club { os.exit(1i32) }
    let (_, room) = iso.subgraph_vf2[i64](&path, &club, mapping[..2usize], used[..])
    if room != iso.TooSmall { os.exit(1i32) }

    // 2: the Petersen graph in two labellings, and a 10-cycle.
    var p1: [30]u32 = zero
    let outer = "0 1 1 2 2 3 3 4 4 0"
    let spokes = "0 5 1 6 2 7 3 8 4 9"
    let inner = "5 7 7 9 9 6 6 8 8 5"
    var i = 0usize
    var k = 0usize
    while k < 3usize {
        var text = outer
        if k == 1usize { text = spokes } else if k == 2usize { text = inner }
        var at = 0usize
        while at < text.len {
            if text[at] != 32u8 {
                p1[i] = u32(text[at] - 48u8)
                i += 1usize
            }
            at += 1usize
        }
        k += 1usize
    }
    let (petersen, p_error) = small(a, 10usize, p1[..])
    if p_error != ok { ret p_error }
    // Relabel by v -> (3 v + 1) mod 10.
    var p2: [30]u32 = zero
    i = 0usize
    while i < 30usize {
        p2[i] = (3u32 * p1[i] + 1u32) % 10u32
        i += 1usize
    }
    let (petersen2, p2_error) = small(a, 10usize, p2[..])
    if p2_error != ok { ret p2_error }
    let (same, same_error) = iso.isomorphic[i64](&petersen, &petersen2, mapping[..], used[..])
    if same_error != ok || !same { os.exit(2i32) }
    // The mapping preserves every edge.
    i = 0usize
    while i < 30usize {
        if !iso.adjacent[i64](&petersen2, usize(mapping[usize(p1[i])]), usize(mapping[usize(p1[i + 1usize])])) { os.exit(2i32) }
        i += 2usize
    }
    var ring: [20]u32 = zero
    i = 0usize
    while i < 10usize {
        ring[2usize * i] = u32(i)
        ring[2usize * i + 1usize] = u32((i + 1usize) % 10usize)
        i += 1usize
    }
    let (cycle, cycle_error) = small(a, 10usize, ring[..])
    if cycle_error != ok { ret cycle_error }
    let (different, diff_error) = iso.isomorphic[i64](&petersen, &cycle, mapping[..], used[..])
    if diff_error != ok || different { os.exit(2i32) }
    let (inside, inside_error) = iso.subgraph_vf2[i64](&cycle, &petersen, mapping[..], used[..])
    if inside_error != ok || inside { os.exit(2i32) }

    try io.print("algo graph iso ok\n")
    ret ok
}
