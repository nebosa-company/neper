// Offline range queries: Mo's algorithm over caller storage. `mo_block_size`
// picks the block, `mo_order` sorts query indices by block of the left
// endpoint with the right endpoint ascending in even blocks and descending
// in odd ones (`mo_order_hilbert` orders by the Hilbert index of (l, r)
// instead), `mo_pointer_moves` counts the pointer work of an order, and
// `mo_run` walks the queries in that order, expanding the window before
// shrinking it, calling `add`/`remove` per element and `answer` per query.
// Every query is inclusive: `[lefts[i], rights[i]]`.

use e.algo.sort
use e.data.spatial
use e.math

error Invalid

type MoKey = struct { lefts: []const usize, rights: []const usize, block: usize }
type HilbertKey = struct { lefts: []const usize, rights: []const usize, bits: u32 }

// max(1, n / sqrt(q)).
fn mo_block_size(n: usize, q: usize) -> usize {
    if q == 0usize || n == 0usize { ret 1usize }
    let b = usize(f64(n) / math.sqrt[f64](f64(q)))
    if b == 0usize { ret 1usize }
    ret b
}

fn mo_compare(k: *MoKey, a: usize, b: usize) -> i32 {
    let ba = k.lefts[a] / k.block
    let bb = k.lefts[b] / k.block
    if ba < bb { ret 0i32 - 1i32 }
    if ba > bb { ret 1i32 }
    var ra = k.rights[a]
    var rb = k.rights[b]
    if (ba & 1usize) == 1usize {
        ra = k.rights[b]
        rb = k.rights[a]
    }
    if ra < rb { ret 0i32 - 1i32 }
    if ra > rb { ret 1i32 }
    if a < b { ret 0i32 - 1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// Fills `order` with every query index in Mo order (ties by index).
fn mo_order(lefts: []const usize, rights: []const usize, block: usize, order: []usize) -> err {
    if block == 0usize || rights.len != lefts.len || order.len != lefts.len { ret Invalid }
    var i = 0usize
    while i < order.len {
        order[i] = i
        i += 1usize
    }
    var k = MoKey { lefts: lefts, rights: rights, block: block }
    sort.in_place_by[usize, MoKey](order, &k, mo_compare)
    ret ok
}

fn hilbert_compare(k: *HilbertKey, a: usize, b: usize) -> i32 {
    let ha = spatial.hilbert_index(k.bits, u64(k.lefts[a]), u64(k.rights[a]))
    let hb = spatial.hilbert_index(k.bits, u64(k.lefts[b]), u64(k.rights[b]))
    if ha < hb { ret 0i32 - 1i32 }
    if ha > hb { ret 1i32 }
    if a < b { ret 0i32 - 1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// Fills `order` by the Hilbert index of (l, r) on the smallest 2^k x 2^k grid
// holding positions below `n` (ties by index).
fn mo_order_hilbert(lefts: []const usize, rights: []const usize, n: usize, order: []usize) -> err {
    if rights.len != lefts.len || order.len != lefts.len { ret Invalid }
    var bits = 1u32
    while (1usize << bits) < n { bits += 1u32 }
    var i = 0usize
    while i < order.len {
        order[i] = i
        i += 1usize
    }
    var k = HilbertKey { lefts: lefts, rights: rights, bits: bits }
    sort.in_place_by[usize, HilbertKey](order, &k, hilbert_compare)
    ret ok
}

fn distance(a: i64, b: i64) -> usize {
    if a < b { ret usize(b - a) }
    ret usize(a - b)
}

// Total |dl| + |dr| visiting the queries in `order` from the empty window
// l = 0, r = -1; answers 0 on a length mismatch.
fn mo_pointer_moves(lefts: []const usize, rights: []const usize, order: []const usize) -> usize {
    if rights.len != lefts.len || order.len != lefts.len { ret 0usize }
    var l = 0i64
    var r = 0i64 - 1i64
    var total = 0usize
    var i = 0usize
    while i < order.len {
        let q = order[i]
        total += distance(l, i64(lefts[q])) + distance(r, i64(rights[q]))
        l = i64(lefts[q])
        r = i64(rights[q])
        i += 1usize
    }
    ret total
}

// Walk the queries in `order`: the window grows first (left down, right up),
// then shrinks (left up, right down); `answer(ctx, q)` once it matches query `q`.
fn mo_run[Ctx: type](ctx: *Ctx, lefts: []const usize, rights: []const usize, order: []const usize, add: fn(*Ctx, usize), remove: fn(*Ctx, usize), answer: fn(*Ctx, usize)) -> err {
    if rights.len != lefts.len || order.len != lefts.len { ret Invalid }
    var l = 0i64
    var r = 0i64 - 1i64
    var i = 0usize
    while i < order.len {
        let q = order[i]
        let ql = i64(lefts[q])
        let qr = i64(rights[q])
        while l > ql {
            l -= 1i64
            add(ctx, usize(l))
        }
        while r < qr {
            r += 1i64
            add(ctx, usize(r))
        }
        while l < ql {
            remove(ctx, usize(l))
            l += 1i64
        }
        while r > qr {
            remove(ctx, usize(r))
            r -= 1i64
        }
        answer(ctx, q)
        i += 1usize
    }
    ret ok
}
