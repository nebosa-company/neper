// `e.dist.dht`: 64 LCG node ids on a 10-bit ring; the Chord finger tables
// and 40 lookups (owner and hop count folded into one word each) agree with
// a Python replica, the Kademlia bucket counts of one node and 40 iterative
// lookups (closest four and rounds, folded) agree too, and the bad-input
// paths answer their errors. Each check exits with its own code.

use e.dist.dht
use e.io
use e.mem
use e.os

fn next(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn fold(h: u64, v: usize) -> u64 { ret h *% 1000003u64 +% u64(v) }

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 4242u64
    var nodes: [64]u64 = zero
    var i = 0usize
    while i < 64usize {
        nodes[i] = u64(i) * 16u64 + next(&state) % 16u64
        i += 1usize
    }
    if nodes[0usize] != 14u64 || nodes[63usize] != 1015u64 { os.exit(1i32) }

    // 1: Chord finger tables and lookups.
    var fingers: [640]u32 = zero
    if dht.chord_finger_tables(nodes[..], 10u32, fingers[..]) != ok { os.exit(1i32) }
    if fingers[5usize * 10usize + 3usize] != 6u32 || fingers[63usize * 10usize + 9usize] != 32u32 { os.exit(1i32) }
    var fold_owner = 0u64
    var fold_hops = 0u64
    var t = 0usize
    while t < 40usize {
        let r = next(&state)
        let (owner, hops) = dht.chord_lookup(nodes[..], 10u32, fingers[..], usize(r % 64u64), (r >> 8u32) % 1024u64)
        if t == 0usize && (r % 64u64 != 18u64 || owner != 30usize || hops != 3usize) { os.exit(1i32) }
        if hops > 5usize { os.exit(1i32) }
        fold_owner = fold(fold_owner, owner)
        fold_hops = fold(fold_hops, hops)
        t += 1usize
    }
    if fold_owner != 12514072028992193646u64 || fold_hops != 11209781958697938993u64 { os.exit(1i32) }

    // 2: Kademlia buckets of node 7.
    var counts: [10]usize = zero
    if dht.kademlia_buckets(nodes[..], 7usize, counts[..]) != ok { os.exit(2i32) }
    let want = [10]usize { 0usize, 0usize, 0usize, 0usize, 1usize, 2usize, 4usize, 8usize, 16usize, 32usize }
    i = 0usize
    while i < 10usize {
        if counts[i] != want[i] { os.exit(2i32) }
        i += 1usize
    }
    if dht.kademlia_bucket(nodes[7usize], nodes[7usize]) != 0u32 || dht.kademlia_bucket(0u64, 1023u64) != 9u32 { os.exit(2i32) }

    // 3: Kademlia lookups, k = 4, alpha = 3.
    var out: [4]usize = zero
    var scratch: [132]usize = zero
    var fold_c = 0u64
    var fold_r = 0u64
    t = 0usize
    while t < 40usize {
        let r = next(&state)
        let (count, rounds, e) = dht.kademlia_lookup(nodes[..], usize(r % 64u64), (r >> 8u32) % 1024u64, 4usize, 3usize, out[..], scratch[..])
        if e != ok { os.exit(3i32) }
        if t == 0usize && (count != 4usize || rounds != 2usize || out[0usize] != 2usize || out[1usize] != 3usize || out[2usize] != 0usize || out[3usize] != 1usize) { os.exit(3i32) }
        i = 0usize
        while i < count {
            fold_c = fold(fold_c, out[i])
            i += 1usize
        }
        fold_c = fold(fold_c, count)
        fold_r = fold(fold_r, rounds)
        t += 1usize
    }
    if fold_c != 7980978953501313180u64 || fold_r != 8435091747338699422u64 { os.exit(3i32) }

    // 4: bad inputs.
    if dht.chord_finger_tables(nodes[..], 10u32, fingers[..600usize]) != dht.Invalid { os.exit(4i32) }
    if dht.chord_finger_tables(nodes[..], 9u32, fingers[..]) != dht.Invalid { os.exit(4i32) }
    var unsorted = [3]u64 { 5u64, 3u64, 9u64 }
    if dht.chord_finger_tables(unsorted[..], 4u32, fingers[..]) != dht.Invalid { os.exit(4i32) }
    if dht.kademlia_buckets(nodes[..], 7usize, counts[..9usize]) != dht.TooSmall { os.exit(4i32) }
    let (_, _, e1) = dht.kademlia_lookup(nodes[..], 64usize, 5u64, 4usize, 3usize, out[..], scratch[..])
    let (_, _, e2) = dht.kademlia_lookup(nodes[..], 0usize, 5u64, 4usize, 3usize, out[..], scratch[..100usize])
    let (_, _, e3) = dht.kademlia_lookup(nodes[..], 0usize, 5u64, 0usize, 3usize, out[..], scratch[..])
    if e1 != dht.Invalid || e2 != dht.Invalid || e3 != dht.Invalid { os.exit(4i32) }
    // One node owns everything and needs no hops.
    if dht.chord_finger_tables(nodes[..1usize], 10u32, fingers[..]) != ok { os.exit(4i32) }
    let (only, none) = dht.chord_lookup(nodes[..1usize], 10u32, fingers[..], 0usize, 900u64)
    if only != 0usize || none != 0usize { os.exit(4i32) }

    try io.print("dist dht ok\n")
    ret ok
}
