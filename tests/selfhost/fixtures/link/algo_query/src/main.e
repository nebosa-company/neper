// `e.algo.query`: Mo's ordering of 60 LCG queries over 200 values agrees
// with a Python replica (order hash, pointer moves below the naive sum),
// `mo_run` with a distinct-count context answers every query like brute
// force, and the Hilbert order's move count matches. Each check exits with
// its own code.

use e.algo.query
use e.io
use e.mem
use e.os

type Distinct = struct { values: []const u32, seen: []u32, distinct: usize, out: []usize }

fn add(c: *Distinct, i: usize) {
    let v = usize(c.values[i])
    if c.seen[v] == 0u32 { c.distinct += 1usize }
    c.seen[v] += 1u32
}

fn remove(c: *Distinct, i: usize) {
    let v = usize(c.values[i])
    c.seen[v] -= 1u32
    if c.seen[v] == 0u32 { c.distinct -= 1usize }
}

fn answer(c: *Distinct, q: usize) {
    c.out[q] = c.distinct
}

fn main(a: *mem.Arena, args: []str) -> err {
    var values: [200]u32 = zero
    var lefts: [60]usize = zero
    var rights: [60]usize = zero
    var state = 12345u64
    var i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        values[i] = u32((state >> 33u32) & 15u64)
        i += 1usize
    }
    i = 0usize
    while i < 60usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let x = usize((state >> 33u32) % 200u64)
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let y = usize((state >> 33u32) % 200u64)
        lefts[i] = x
        rights[i] = y
        if x > y {
            lefts[i] = y
            rights[i] = x
        }
        i += 1usize
    }

    // 1: block size and argument validation.
    let block = query.mo_block_size(200usize, 60usize)
    if block != 25usize { os.exit(1i32) }
    var order: [60]usize = zero
    if query.mo_order(lefts[..], rights[..], 0usize, order[..]) != query.Invalid { os.exit(1i32) }
    if query.mo_order(lefts[..], rights[..59usize], block, order[..]) != query.Invalid { os.exit(1i32) }

    // 2: Mo order matches the replica.
    if query.mo_order(lefts[..], rights[..], block, order[..]) != ok { os.exit(2i32) }
    var h = 0u64
    i = 0usize
    while i < 60usize {
        h = h *% 31u64 +% u64(order[i])
        i += 1usize
    }
    if h != 9297809943355075388u64 { os.exit(2i32) }

    // 3: pointer moves match and beat the naive sum of lengths.
    let moves = query.mo_pointer_moves(lefts[..], rights[..], order[..])
    if moves != 1372usize { os.exit(3i32) }
    var naive = 0usize
    i = 0usize
    while i < 60usize {
        naive += rights[i] - lefts[i] + 1usize
        i += 1usize
    }
    if naive != 3948usize || moves >= naive { os.exit(3i32) }

    // 4: mo_run with a distinct-count context agrees with brute force.
    var seen: [16]u32 = zero
    var out: [60]usize = zero
    var ctx = Distinct { values: values[..], seen: seen[..], distinct: 0usize, out: out[..] }
    if query.mo_run[Distinct](&ctx, lefts[..], rights[..], order[..], add, remove, answer) != ok { os.exit(4i32) }
    h = 0u64
    i = 0usize
    while i < 60usize {
        var mask = 0u32
        var j = lefts[i]
        while j <= rights[i] {
            mask = mask | (1u32 << values[j])
            j += 1usize
        }
        var count = 0usize
        var bit = 0u32
        while bit < 16u32 {
            if ((mask >> bit) & 1u32) == 1u32 { count += 1usize }
            bit += 1u32
        }
        if out[i] != count { os.exit(4i32) }
        h = h *% 31u64 +% u64(out[i])
        i += 1usize
    }
    if h != 14518777893988462u64 { os.exit(4i32) }

    // 5: Hilbert order matches the replica.
    if query.mo_order_hilbert(lefts[..], rights[..], 200usize, order[..]) != ok { os.exit(5i32) }
    h = 0u64
    i = 0usize
    while i < 60usize {
        h = h *% 31u64 +% u64(order[i])
        i += 1usize
    }
    if h != 3395692039018239730u64 { os.exit(5i32) }
    if query.mo_pointer_moves(lefts[..], rights[..], order[..]) != 1536usize { os.exit(5i32) }

    try io.print("algo query ok\n")
    ret ok
}
