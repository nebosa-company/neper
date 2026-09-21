// `e.data.cartesian_tree`: over 48 LCG arrays of 1..64 keys drawn from 0..7
// (so ties are common), the parent arrays, every range minimum and random
// LCAs match the Python brute force by checksum, every tree passes
// `is_valid`, and the error paths answer. Each check exits with its own code.

use e.data.cartesian_tree as ct
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var keys: [64]i64 = zero
    var left: [64]u32 = zero
    var right: [64]u32 = zero
    var parent: [64]u32 = zero
    var state = 12345u64
    var hp = 0u64
    var hm = 0u64
    var hl = 0u64
    var trial = 0usize
    while trial < 48usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let n = 1usize + usize((state >> 33u32) % 64u64)
        var i = 0usize
        while i < n {
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            keys[i] = i64((state >> 33u32) % 8u64)
            i += 1usize
        }
        // 1: build and validate.
        let (t, build_error) = ct.build[i64](keys[..n], left[..], right[..], parent[..])
        if build_error != ok { os.exit(1i32) }
        if !ct.is_valid[i64](keys[..n], &t) { os.exit(1i32) }
        i = 0usize
        while i < n {
            hp = hp *% 31u64 +% u64(parent[i])
            i += 1usize
        }
        // 2: every range minimum.
        var lo = 0usize
        while lo < n {
            var hi = lo + 1usize
            while hi <= n {
                let (m, min_error) = ct.range_min(&t, lo, hi)
                if min_error != ok { os.exit(2i32) }
                hm = hm *% 31u64 +% u64(m)
                hi += 1usize
            }
            lo += 1usize
        }
        // 3: random LCAs.
        var q = 0usize
        while q < 16usize {
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            let x = usize((state >> 33u32) % u64(n))
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            let y = usize((state >> 33u32) % u64(n))
            let (l, lca_error) = ct.lca(&t, x, y)
            if lca_error != ok { os.exit(3i32) }
            hl = hl *% 31u64 +% u64(l)
            q += 1usize
        }
        trial += 1usize
    }
    if hp != 124168966343516097u64 { os.exit(1i32) }
    if hm != 12169213642329906565u64 { os.exit(2i32) }
    if hl != 14400434077352215337u64 { os.exit(3i32) }

    // 4: error paths and a broken tree.
    let (_, small) = ct.build[i64](keys[..], left[..], right[..], parent[..32usize])
    if small != ct.TooSmall { os.exit(4i32) }
    let (t8, _) = ct.build[i64](keys[..8usize], left[..], right[..], parent[..])
    let (_, empty_range) = ct.range_min(&t8, 3usize, 3usize)
    if empty_range != ct.Invalid { os.exit(4i32) }
    let (_, past) = ct.range_min(&t8, 0usize, 9usize)
    if past != ct.Invalid { os.exit(4i32) }
    let (_, bad_lca) = ct.lca(&t8, 8usize, 0usize)
    if bad_lca != ct.Invalid { os.exit(4i32) }
    if !ct.is_valid[i64](keys[..8usize], &t8) { os.exit(4i32) }
    keys[usize(t8.root)] = 100i64
    if ct.is_valid[i64](keys[..8usize], &t8) { os.exit(4i32) }
    let (empty, empty_error) = ct.build[i64](keys[..0usize], left[..], right[..], parent[..])
    if empty_error != ok || empty.root != ct.NONE || !ct.is_valid[i64](keys[..0usize], &empty) { os.exit(4i32) }

    try io.print("data cartesian_tree ok\n")
    ret ok
}
