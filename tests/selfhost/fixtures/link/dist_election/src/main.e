// `e.dist.election`: the bully algorithm's leader and message count match a
// Python replica over several alive patterns, the recorded messages are the
// classic Election/OK/Coordinator sequence, the ring algorithm costs two
// messages per alive node and hops only between alive nodes, and a dead
// initiator or a short buffer answers its error. Each check exits with its
// own code.

use e.dist.election as election
use e.io
use e.mem
use e.os

fn count_kind(msgs: []const election.Message, n: usize, kind: election.Kind) -> usize {
    var c = 0usize
    var i = 0usize
    while i < n {
        if msgs[i].kind == kind { c += 1usize }
        i += 1usize
    }
    ret c
}

fn main(a: *mem.Arena, args: []str) -> err {
    var out: [64]election.Message = zero

    // 1: all six alive, initiator 2.
    var all = [6]bool { true, true, true, true, true, true }
    let (l1, c1, e1) = election.bully(all[..], 2usize, out[..])
    if e1 != ok || l1 != 5usize || c1 != 17usize { os.exit(1i32) }
    if count_kind(out[..], c1, .Election) != 6usize || count_kind(out[..], c1, .Ok) != 6usize || count_kind(out[..], c1, .Coordinator) != 5usize { os.exit(1i32) }
    if out[0usize].kind != .Election || out[0usize].from != 2u32 || out[0usize].to != 3u32 { os.exit(1i32) }
    if out[c1 - 1usize].kind != .Coordinator || out[c1 - 1usize].from != 5u32 || out[c1 - 1usize].to != 4u32 { os.exit(1i32) }

    // 2: holes in the alive pattern.
    var some = [8]bool { true, true, false, true, false, true, false, false }
    let (l2, c2, e2) = election.bully(some[..], 1usize, out[..])
    if e2 != ok || l2 != 5usize || c2 != 18usize { os.exit(2i32) }
    var other = [6]bool { true, false, true, true, false, false }
    let (l3, c3, e3) = election.bully(other[..], 3usize, out[..])
    if e3 != ok || l3 != 3usize || c3 != 4usize { os.exit(2i32) }
    var low = [8]bool { true, true, true, true, false, false, false, false }
    let (l4, c4, e4) = election.bully(low[..], 0usize, out[..])
    if e4 != ok || l4 != 3usize || c4 != 31usize { os.exit(2i32) }

    // 3: errors: a dead initiator, and a buffer too small still counts.
    let (_, _, dead) = election.bully(some[..], 2usize, out[..])
    if dead != election.Invalid { os.exit(3i32) }
    let (l5, c5, small) = election.bully(all[..], 2usize, out[..4usize])
    if small != election.TooSmall || l5 != 5usize || c5 != 17usize { os.exit(3i32) }

    // 4: the ring.
    var order = [8]usize { 3usize, 1usize, 4usize, 0usize, 6usize, 2usize, 5usize, 7usize }
    let (l6, c6, e6) = election.ring(some[..], order[..], 1usize, out[..])
    if e6 != ok || l6 != 5usize || c6 != 8usize { os.exit(4i32) }
    // Alive in ring order after 1: 0, 5, 3, then back to 1; twice.
    if out[0usize].from != 1u32 || out[0usize].to != 0u32 || out[1usize].to != 5u32 || out[2usize].to != 3u32 || out[3usize].to != 1u32 { os.exit(4i32) }
    if out[3usize].kind != .Election || out[4usize].kind != .Coordinator || out[4usize].from != 1u32 || out[4usize].to != 0u32 || out[7usize].to != 1u32 { os.exit(4i32) }
    let (_, _, e7) = election.ring(some[..], order[..], 2usize, out[..])
    if e7 != election.Invalid { os.exit(4i32) }
    let (_, _, e8) = election.ring(all[..], order[..], 2usize, out[..])
    if e8 != election.Invalid { os.exit(4i32) }
    let (l9, c9, e9) = election.ring(some[..], order[..], 1usize, out[..3usize])
    if e9 != election.TooSmall || l9 != 5usize || c9 != 8usize { os.exit(4i32) }

    try io.print("dist election ok\n")
    ret ok
}
