// `e.dist.deadlock`: four hand wait-for graphs over two or three sites; the
// DFS cycle check answers the verdicts and cycle lengths a Python replica
// answers, the Chandy-Misra-Haas probe chase answers the same verdicts and
// exact probe counts from two initiators (including the graph where the
// initiator waits on a cycle it is not part of), the probes land in the
// pool in sending order, and the short-pool and bad-graph paths answer
// their errors. Each check exits with its own code.

use e.dist.deadlock as dl
use e.io
use e.mem
use e.os

fn edge(from: usize, to: usize) -> dl.Edge { ret dl.Edge { from: u32(from), to: u32(to) } }

fn check(edges: []const dl.Edge, site: []const u32, want_cycle: bool, want_length: usize, want_dead: bool, want_probes: usize, want_dead1: bool, want_probes1: usize) -> bool {
    var scratch: [16]usize = zero
    var flags: [16]bool = zero
    var probes: [32]dl.Probe = zero
    let (cycle, length, e1) = dl.wait_for_graph_cycle(edges, site.len, scratch[..])
    if e1 != ok || cycle != want_cycle || length != want_length { ret false }
    let (dead, sent, e2) = dl.chandy_misra_haas(edges, site, 0usize, probes[..], flags[..])
    if e2 != ok || dead != want_dead || sent != want_probes { ret false }
    let (dead1, sent1, e3) = dl.chandy_misra_haas(edges, site, 1usize, probes[..], flags[..])
    if e3 != ok || dead1 != want_dead1 || sent1 != want_probes1 { ret false }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: a six-process ring over three sites, with and without the closing edge.
    var g1: [6]dl.Edge = zero
    var i = 0usize
    while i < 6usize {
        g1[i] = edge(i, (i + 1usize) % 6usize)
        i += 1usize
    }
    let s1 = [6]u32 { 0u32, 0u32, 1u32, 1u32, 2u32, 2u32 }
    if !check(g1[..], s1[..], true, 6usize, true, 3usize, false, 4usize) { os.exit(1i32) }
    if !check(g1[..5usize], s1[..], false, 0usize, false, 2usize, false, 2usize) { os.exit(1i32) }

    // 2: the initiator waits on a cycle it is not part of: the graph has a
    // cycle of length 4 but the chase from 0 never comes home; from 1 it does.
    var g3: [9]dl.Edge = zero
    g3[0usize] = edge(0usize, 1usize)
    g3[1usize] = edge(0usize, 2usize)
    g3[2usize] = edge(1usize, 3usize)
    g3[3usize] = edge(2usize, 6usize)
    g3[4usize] = edge(3usize, 4usize)
    g3[5usize] = edge(4usize, 5usize)
    g3[6usize] = edge(5usize, 1usize)
    g3[7usize] = edge(6usize, 7usize)
    g3[8usize] = edge(7usize, 2usize)
    let s3 = [8]u32 { 0u32, 0u32, 0u32, 1u32, 1u32, 1u32, 2u32, 2u32 }
    if !check(g3[..], s3[..], true, 4usize, false, 6usize, true, 2usize) { os.exit(2i32) }

    // 3: two paths back to the initiator, and the probes in sending order.
    var g4: [6]dl.Edge = zero
    g4[0usize] = edge(0usize, 1usize)
    g4[1usize] = edge(0usize, 3usize)
    g4[2usize] = edge(1usize, 2usize)
    g4[3usize] = edge(2usize, 0usize)
    g4[4usize] = edge(3usize, 4usize)
    g4[5usize] = edge(4usize, 0usize)
    let s4 = [5]u32 { 0u32, 1u32, 1u32, 2u32, 2u32 }
    if !check(g4[..], s4[..], true, 3usize, true, 4usize, true, 4usize) { os.exit(3i32) }
    var probes: [8]dl.Probe = zero
    var flags: [10]bool = zero
    let (dead, sent, e) = dl.chandy_misra_haas(g4[..], s4[..], 0usize, probes[..], flags[..])
    if e != ok || !dead || sent != 4usize { os.exit(3i32) }
    let from = [4]u32 { 0u32, 0u32, 2u32, 4u32 }
    let to = [4]u32 { 1u32, 3u32, 0u32, 0u32 }
    i = 0usize
    while i < 4usize {
        if probes[i].initiator != 0u32 || probes[i].from != from[i] || probes[i].to != to[i] { os.exit(3i32) }
        i += 1usize
    }

    // 4: a short pool stops the chase with an exact count so far; bad inputs.
    let (_, short_sent, e2) = dl.chandy_misra_haas(g4[..], s4[..], 0usize, probes[..2usize], flags[..])
    if e2 != dl.TooSmall || short_sent != 4usize { os.exit(4i32) }
    let (_, _, e3) = dl.chandy_misra_haas(g4[..], s4[..], 5usize, probes[..], flags[..])
    if e3 != dl.Invalid { os.exit(4i32) }
    let (_, _, e4) = dl.chandy_misra_haas(g4[..], s4[..3usize], 0usize, probes[..], flags[..])
    if e4 != dl.Invalid { os.exit(4i32) }
    var scratch: [4]usize = zero
    let (_, _, e5) = dl.wait_for_graph_cycle(g4[..], 5usize, scratch[..])
    if e5 != dl.Invalid { os.exit(4i32) }
    let (_, _, e6) = dl.wait_for_graph_cycle(g4[..], 3usize, scratch[..])
    if e6 != dl.Invalid { os.exit(4i32) }
    let (none, _, e7) = dl.wait_for_graph_cycle(g4[..0usize], 2usize, scratch[..])
    if e7 != ok || none { os.exit(4i32) }

    try io.print("dist deadlock ok\n")
    ret ok
}
