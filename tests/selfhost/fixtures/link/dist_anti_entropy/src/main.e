// `e.dist.anti_entropy`: two replicas of 500 LCG keys that differ in seven
// (five versions, one missing, one extra) build Merkle trees over 64
// buckets, the sync walk names exactly the seven buckets a Python replica
// names with the same comparison count, the key diff lists the seven keys,
// identical trees cost one comparison, and the short-output and bad-shape
// paths answer their errors. Each check exits with its own code.

use e.dist.anti_entropy as ae
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 12345u64
    var ea: [500]ae.Entry = zero
    var eb: [500]ae.Entry = zero
    var i = 0usize
    while i < 500usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let k = u64(i) * 8u64 + (state >> 33u32) % 7u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        ea[i] = ae.Entry { key: k, version: state >> 33u32 }
        i += 1usize
    }
    i = 0usize
    while i < 500usize {
        eb[i] = ea[i]
        i += 1usize
    }
    let bump = [5]usize { 17usize, 100usize, 250usize, 333usize, 499usize }
    i = 0usize
    while i < 5usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        eb[bump[i]].version += 1u64 + (state >> 33u32) % 5u64
        i += 1usize
    }
    // Drop index 60 and insert key 1607 after index 200.
    i = 60usize
    while i < 200usize {
        eb[i] = eb[i + 1usize]
        i += 1usize
    }
    eb[200usize] = ae.Entry { key: 1607u64, version: 77u64 }
    if ea[0usize].key != 6u64 || ea[0usize].version != 569910583u64 || ea[499usize].key != 3997u64 { os.exit(1i32) }

    // 1: build both trees.
    var ha: [128]u64 = zero
    var hb: [128]u64 = zero
    let (ta, e1) = ae.merkle_build(ea[..], 64u64, ha[..])
    let (tb, e2) = ae.merkle_build(eb[..], 64u64, hb[..])
    if e1 != ok || e2 != ok { os.exit(1i32) }
    if ha[1usize] != 14839796023637106634u64 || hb[1usize] != 10404076904420280754u64 { os.exit(1i32) }

    // 2: the sync walk names the seven buckets with the replica's comparison count.
    var buckets: [16]usize = zero
    let (nb, comparisons, e3) = ae.merkle_sync(&ta, &tb, buckets[..])
    if e3 != ok || nb != 7usize || comparisons != 53usize { os.exit(2i32) }
    let want_b = [7]usize { 2usize, 7usize, 12usize, 25usize, 31usize, 41usize, 62usize }
    i = 0usize
    while i < 7usize {
        if buckets[i] != want_b[i] { os.exit(2i32) }
        i += 1usize
    }

    // 3: the differing keys inside those buckets.
    var keys: [16]u64 = zero
    let (nk, e4) = ae.merkle_diff_keys(ea[..], eb[..], 64u64, buckets[..nb], keys[..])
    if e4 != ok || nk != 7usize { os.exit(3i32) }
    let want_k = [7]u64 { 141u64, 483u64, 804u64, 1607u64, 2006u64, 2668u64, 3997u64 }
    i = 0usize
    while i < 7usize {
        if keys[i] != want_k[i] { os.exit(3i32) }
        i += 1usize
    }

    // 4: identical trees cost one comparison; short outputs and bad shapes.
    let (same, one, e5) = ae.merkle_sync(&ta, &ta, buckets[..])
    if e5 != ok || same != 0usize || one != 1usize { os.exit(4i32) }
    let (nb2, c2, e6) = ae.merkle_sync(&ta, &tb, buckets[..3usize])
    if e6 != ae.TooSmall || nb2 != 7usize || c2 != 53usize { os.exit(4i32) }
    let (nk2, e7) = ae.merkle_diff_keys(ea[..], eb[..], 64u64, buckets[..nb], keys[..2usize])
    if e7 != ae.TooSmall || nk2 != 7usize { os.exit(4i32) }
    var odd: [12]u64 = zero
    let (_, e8) = ae.merkle_build(ea[..], 64u64, odd[..])
    if e8 != ae.Invalid { os.exit(4i32) }
    var tiny: [8]u64 = zero
    let (_, e9) = ae.merkle_build(ea[..], 64u64, tiny[..])
    if e9 != ae.Invalid { os.exit(4i32) }
    let (tc, e10) = ae.merkle_build(ea[..], 128u64, ha[..])
    if e10 != ok { os.exit(4i32) }
    let (_, _, e11) = ae.merkle_sync(&tc, &tb, buckets[..])
    if e11 != ae.Invalid { os.exit(4i32) }

    try io.print("dist anti_entropy ok\n")
    ret ok
}
