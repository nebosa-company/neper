// `e.data.btree`: a B+ tree of order 4 agrees with a sorted array through
// random inserts, overwrites and removals, keeps its height small, scans
// ranges in order, and the pool and order checks answer. Each check exits
// with its own code.

use e.algo.rand
use e.data.btree
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var keys: [2048]u64 = zero
    var values: [2048]u32 = zero
    var count: [512]u32 = zero
    var leaf: [512]bool = zero
    var next: [512]u32 = zero
    let (t0, make_error) = btree.btree(keys[..], values[..], count[..], leaf[..], next[..], 4usize)
    if make_error != ok { os.exit(1i32) }
    var t = t0
    var r = rand.pcg64(41u64, 2u64)
    var model_keys: [400]u64 = zero
    var model_values: [400]u32 = zero
    var n = 0usize

    // 1: random inserts, overwrites and removals against the sorted model.
    var step = 0usize
    while step < 3000usize {
        let key = rand.pcg64_bounded(&r, 300u64)
        var at = 0usize
        while at < n && model_keys[at] < key { at += 1usize }
        let present = at < n && model_keys[at] == key
        if rand.pcg64_bounded(&r, 3u64) < 2u64 {
            let value = u32(step)
            if btree.insert(&t, key, value) != ok { os.exit(1i32) }
            if present {
                model_values[at] = value
            } else {
                var j = n
                while j > at {
                    model_keys[j] = model_keys[j - 1usize]
                    model_values[j] = model_values[j - 1usize]
                    j -= 1usize
                }
                model_keys[at] = key
                model_values[at] = value
                n += 1usize
            }
        } else {
            if btree.remove(&t, key) != present { os.exit(1i32) }
            if present {
                var j = at
                while j + 1usize < n {
                    model_keys[j] = model_keys[j + 1usize]
                    model_values[j] = model_values[j + 1usize]
                    j += 1usize
                }
                n -= 1usize
            }
        }
        if step % 50usize == 0usize {
            var i = 0usize
            while i < n {
                let (v, found) = btree.get(&t, model_keys[i])
                if !found || v != model_values[i] { os.exit(1i32) }
                i += 1usize
            }
        }
        step += 1usize
    }
    let (_, missing) = btree.get(&t, 1000u64)
    if missing { os.exit(1i32) }
    if t.height > 10usize || t.used > 512usize { os.exit(1i32) }

    // 2: full and partial scans in order.
    var scan_keys: [400]u64 = zero
    var scan_values: [400]u32 = zero
    let (all, all_error) = btree.scan(&t, 0u64, 1000u64, scan_keys[..], scan_values[..])
    if all_error != ok || all != n { os.exit(2i32) }
    var i = 0usize
    while i < n {
        if scan_keys[i] != model_keys[i] || scan_values[i] != model_values[i] { os.exit(2i32) }
        i += 1usize
    }
    let (part, part_error) = btree.scan(&t, 100u64, 150u64, scan_keys[..], scan_values[..])
    if part_error != ok { os.exit(2i32) }
    var expected = 0usize
    i = 0usize
    while i < n {
        if model_keys[i] >= 100u64 && model_keys[i] < 150u64 {
            if scan_keys[expected] != model_keys[i] { os.exit(2i32) }
            expected += 1usize
        }
        i += 1usize
    }
    if part != expected { os.exit(2i32) }
    let (none, none_error) = btree.scan(&t, 500u64, 600u64, scan_keys[..], scan_values[..])
    if none_error != ok || none != 0usize { os.exit(2i32) }
    let (_, scan_room) = btree.scan(&t, 0u64, 1000u64, scan_keys[..3usize], scan_values[..])
    if scan_room != btree.TooSmall { os.exit(2i32) }

    // 3: emptying the tree, then the argument checks.
    i = 0usize
    while i < n {
        if !btree.remove(&t, model_keys[i]) { os.exit(3i32) }
        i += 1usize
    }
    let (empty, empty_error) = btree.scan(&t, 0u64, 1000u64, scan_keys[..], scan_values[..])
    if empty_error != ok || empty != 0usize || t.height != 1usize { os.exit(3i32) }
    if btree.remove(&t, 5u64) { os.exit(3i32) }
    let (_, bad_order) = btree.btree(keys[..], values[..], count[..], leaf[..], next[..], 2usize)
    if bad_order != btree.Invalid { os.exit(3i32) }
    let (_, short_pool) = btree.btree(keys[..10usize], values[..], count[..], leaf[..], next[..], 4usize)
    if short_pool != btree.TooSmall { os.exit(3i32) }
    let (tiny0, tiny_error) = btree.btree(keys[..12usize], values[..12usize], count[..3usize], leaf[..3usize], next[..3usize], 4usize)
    if tiny_error != ok { os.exit(3i32) }
    var tiny = tiny0
    var k = 0u64
    var full = ok
    while k < 20u64 && full == ok {
        full = btree.insert(&tiny, k, 0u32)
        k += 1u64
    }
    if full != btree.TooSmall { os.exit(3i32) }

    try io.print("data btree ok\n")
    ret ok
}
