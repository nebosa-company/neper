// The D883 additions to `e.data.heap` against a Python reference: the leftist,
// skew, pairing, binomial and randomized meldable heaps each run the same LCG
// script of 2000 inserts, pops, merges (and, for the pairing heap, decrease-keys)
// over two heaps sharing one pool, and the folded pop sequence must equal the
// reference min-heap's; the leftist rank property and the pairing heap's order
// and links are checked after every operation. Then the min-max heap under the
// same script with pops from both ends, and `heapify`/`heapify_by` over 500
// values. Each check exits with its own code.

use e.data.heap
use e.io
use e.mem
use e.os

type Gen = struct { state: u64 }
type Flip = struct { calls: usize }

fn draw(g: *Gen) -> u64 {
    g.state = g.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret g.state >> 33u32
}

fn fold_add(fold: i64, key: i64) -> i64 { ret fold *% 31i64 +% key +% 7i64 }

fn desc(c: *Flip, a: i64, b: i64) -> i32 {
    c.calls += 1usize
    if a > b { ret 0i32 - 1i32 }
    if a < b { ret 1i32 }
    ret 0i32
}

fn leftist_ok(p: *heap.Pool[i64], root: u32) -> bool {
    if root == 0u32 { ret true }
    let n = usize(root)
    let l = p.left[n]
    let r = p.right[n]
    if p.rank[usize(l)] < p.rank[usize(r)] || p.rank[n] != p.rank[usize(r)] + 1u32 { ret false }
    if l != 0u32 && p.keys[usize(l)] < p.keys[n] { ret false }
    if r != 0u32 && p.keys[usize(r)] < p.keys[n] { ret false }
    ret leftist_ok(p, l) && leftist_ok(p, r)
}

fn pairing_children_ok(p: *heap.Pool[i64], n: u32) -> bool {
    var c = p.left[usize(n)]
    var prev = n
    while c != 0u32 {
        if p.keys[usize(c)] < p.keys[usize(n)] || p.up[usize(c)] != prev { ret false }
        if !pairing_children_ok(p, c) { ret false }
        prev = c
        c = p.right[usize(c)]
    }
    ret true
}

fn pairing_ok(p: *heap.Pool[i64], root: u32) -> bool {
    if root == 0u32 { ret true }
    if p.up[usize(root)] != 0u32 || p.right[usize(root)] != 0u32 { ret false }
    ret pairing_children_ok(p, root)
}

// mode: 0 leftist, 1 skew, 2 pairing, 3 binomial, 4 meldable.
fn merge_of(p: *heap.Pool[i64], mode: usize, a: u32, b: u32, coin: *u64) -> u32 {
    if mode == 0usize { ret heap.leftist_merge[i64](p, a, b) }
    if mode == 1usize { ret heap.skew_merge[i64](p, a, b) }
    if mode == 2usize { ret heap.pairing_merge[i64](p, a, b) }
    if mode == 3usize { ret heap.binomial_merge[i64](p, a, b) }
    ret heap.meldable_merge[i64](p, a, b, coin)
}

fn insert_of(p: *heap.Pool[i64], mode: usize, root: u32, key: i64, coin: *u64) -> (u32, err) {
    if mode == 0usize {
        let (r0, e0) = heap.leftist_insert[i64](p, root, key)
        ret (r0, e0)
    }
    if mode == 1usize {
        let (r1, e1) = heap.skew_insert[i64](p, root, key)
        ret (r1, e1)
    }
    if mode == 2usize {
        let (r2, e2) = heap.pairing_insert[i64](p, root, key)
        ret (r2, e2)
    }
    if mode == 3usize {
        let (r3, e3) = heap.binomial_insert[i64](p, root, key)
        ret (r3, e3)
    }
    let (r4, e4) = heap.meldable_insert[i64](p, root, key, coin)
    ret (r4, e4)
}

fn pop_of(p: *heap.Pool[i64], mode: usize, root: u32, coin: *u64) -> (u32, u32) {
    if mode == 0usize {
        let (r0, n0) = heap.leftist_pop[i64](p, root)
        ret (r0, n0)
    }
    if mode == 1usize {
        let (r1, n1) = heap.skew_pop[i64](p, root)
        ret (r1, n1)
    }
    if mode == 2usize {
        let (r2, n2) = heap.pairing_pop[i64](p, root)
        ret (r2, n2)
    }
    if mode == 3usize {
        let (r3, n3) = heap.binomial_pop[i64](p, root)
        ret (r3, n3)
    }
    let (r4, n4) = heap.meldable_pop[i64](p, root, coin)
    ret (r4, n4)
}

// Answers (fold of popped keys, invariants held throughout, node count).
fn drive(p: *heap.Pool[i64], mode: usize, alive: []bool, owner: []u8, seed: u64) -> (i64, bool, usize) {
    var g = Gen { state: seed }
    var coin = heap.meldable(seed | 1u64)
    var roots: [2]u32 = zero
    var fold = 0i64
    var held = true
    var i = 0usize
    while i < alive.len {
        alive[i] = false
        i += 1usize
    }
    var step = 0usize
    while step < 2000usize {
        let r = draw(&g)
        let kind = r % 8u64
        let which = usize((r >> 3u64) & 1u64)
        let key = i64((r >> 4u64) % 1000u64)
        if kind < 4u64 {
            let (root, insert_error) = insert_of(p, mode, roots[which], key, &coin)
            if insert_error != ok { os.exit(13i32) }
            roots[which] = root
            alive[p.used - 1usize] = true
            owner[p.used - 1usize] = u8(which)
        } else if kind == 6u64 {
            roots[0usize] = merge_of(p, mode, roots[0usize], roots[1usize], &coin)
            roots[1usize] = 0u32
            var n = 1usize
            while n < p.used {
                owner[n] = 0u8
                n += 1usize
            }
        } else if kind < 6u64 || mode != 2usize {
            let (root, node) = pop_of(p, mode, roots[which], &coin)
            roots[which] = root
            if node == 0u32 {
                fold = fold_add(fold, 0i64 - 1000000i64)
            } else {
                alive[usize(node)] = false
                fold = fold_add(fold, p.keys[usize(node)])
            }
        } else if p.used > 1usize {
            let node = 1usize + usize((r >> 14u64) % u64(p.used - 1usize))
            if alive[node] {
                let o = usize(owner[node])
                let lowered = p.keys[node] - i64((r >> 24u64) % 50u64)
                roots[o] = heap.pairing_decrease_key[i64](p, roots[o], u32(node), lowered)
            }
        }
        if mode == 0usize && (!leftist_ok(p, roots[0usize]) || !leftist_ok(p, roots[1usize])) { held = false }
        if mode == 2usize && (!pairing_ok(p, roots[0usize]) || !pairing_ok(p, roots[1usize])) { held = false }
        step += 1usize
    }
    var h = 0usize
    while h < 2usize {
        while true {
            let (root, node) = pop_of(p, mode, roots[h], &coin)
            roots[h] = root
            if node == 0u32 { break }
            fold = fold_add(fold, p.keys[usize(node)])
        }
        h += 1usize
    }
    ret (fold, held, p.used - 1usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var keys: [1024]i64 = zero
    var left: [1024]u32 = zero
    var right: [1024]u32 = zero
    var up: [1024]u32 = zero
    var rank: [1024]u32 = zero
    var alive: [1024]bool = zero
    var owner: [1024]u8 = zero
    let plain = 2370785287578615372i64
    let lowered_fold = 0i64 - 8523827444195715345i64

    // 1-8: the five pool heaps against the reference pop sequence.
    var mode = 0usize
    while mode < 5usize {
        var p = heap.pool[i64](keys[..], left[..], right[..], up[..], rank[..])
        let (fold, held, nodes) = drive(&p, mode, alive[..], owner[..], 17u64)
        var want = plain
        if mode == 2usize { want = lowered_fold }
        if fold != want { os.exit(i32(mode) + 1i32) }
        if !held { os.exit(6i32) }
        if nodes != 971usize { os.exit(7i32) }
        mode += 1usize
    }
    var tiny = heap.pool[i64](keys[..2usize], left[..2usize], right[..2usize], up[..2usize], rank[..2usize])
    let (_, first_error) = heap.leftist_insert[i64](&tiny, 0u32, 1i64)
    let (_, second_error) = heap.leftist_insert[i64](&tiny, 1u32, 2i64)
    if first_error != ok || second_error != heap.TooSmall { os.exit(8i32) }

    // 9-11: the min-max heap popped from both ends.
    var slots: [128]i64 = zero
    var mm = heap.min_max[i64](slots[..])
    var g = Gen { state: 29u64 }
    var fold = 0i64
    var step = 0usize
    while step < 2000usize {
        let r = draw(&g)
        let kind = r % 8u64
        if kind < 4u64 {
            try heap.min_max_push[i64](&mm, i64((r >> 4u64) % 1000u64))
        } else {
            var popped = 0i64
            var any = false
            if kind < 6u64 {
                let (v, has) = heap.pop_min[i64](&mm)
                popped = v
                any = has
            } else {
                let (v, has) = heap.pop_max[i64](&mm)
                popped = v
                any = has
            }
            if !any { popped = 0i64 - 1000000i64 }
            fold = fold_add(fold, popped)
        }
        step += 1usize
    }
    if fold != 3469659567225007586i64 { os.exit(9i32) }
    let (low, has_low) = heap.peek_min[i64](&mm)
    let (high, has_high) = heap.peek_max[i64](&mm)
    if mm.count != 42usize || !has_low || !has_high || low != 93i64 || high != 919i64 { os.exit(10i32) }
    var small = heap.min_max[i64](slots[..2usize])
    try heap.min_max_push[i64](&small, 5i64)
    try heap.min_max_push[i64](&small, 3i64)
    if heap.min_max_push[i64](&small, 4i64) != heap.TooSmall { os.exit(11i32) }
    let (small_low, _) = heap.peek_min[i64](&small)
    let (small_high, _) = heap.peek_max[i64](&small)
    if small_low != 3i64 || small_high != 5i64 { os.exit(11i32) }

    // 12-13: heapify and heapify_by over 500 values.
    var values: [500]i64 = zero
    var vg = Gen { state: 5u64 }
    var total = 0i64
    var i = 0usize
    while i < 500usize {
        values[i] = i64(draw(&vg) % 100000u64)
        total += values[i]
        i += 1usize
    }
    heap.heapify[i64](values[..])
    if values[0usize] != 184i64 { os.exit(12i32) }
    i = 1usize
    while i < 500usize {
        if values[(i - 1usize) / 2usize] > values[i] { os.exit(12i32) }
        i += 1usize
    }
    var flip = Flip { calls: 0usize }
    heap.heapify_by[i64, Flip](values[..], &flip, desc)
    if values[0usize] != 99967i64 || flip.calls == 0usize { os.exit(13i32) }
    var after = values[0usize]
    i = 1usize
    while i < 500usize {
        if values[(i - 1usize) / 2usize] < values[i] { os.exit(13i32) }
        after += values[i]
        i += 1usize
    }
    if total != 25027818i64 || after != total { os.exit(13i32) }

    try io.print("data heap plan ok\n")
    ret ok
}
