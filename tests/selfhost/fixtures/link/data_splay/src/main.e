// `e.data.splay`: a balanced build reads back in order, splaying by
// position keeps the sequence, random range reversals agree with an array
// reversed in place, and the position checks answer. Each check exits with
// its own code.

use e.algo.rand
use e.data.splay
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var values: [128]i64 = zero
    var left: [128]u32 = zero
    var right: [128]u32 = zero
    var parent: [128]u32 = zero
    var size: [128]u32 = zero
    var reversed: [128]bool = zero
    var t = splay.splay_tree[i64](values[..], left[..], right[..], parent[..], size[..], reversed[..])
    var items: [64]i64 = zero
    var i = 0usize
    while i < 64usize {
        items[i] = i64(i)
        i += 1usize
    }

    // 1: build and read.
    let (root0, build_error) = splay.build[i64](&t, items[..])
    if build_error != ok || root0 == 0u32 || t.size[usize(root0)] != 64u32 { os.exit(1i32) }
    var root = root0
    var out: [64]i64 = zero
    let (n, collect_error) = splay.collect[i64](&t, root, out[..])
    if collect_error != ok || n != 64usize { os.exit(1i32) }
    i = 0usize
    while i < 64usize {
        if out[i] != i64(i) { os.exit(1i32) }
        i += 1usize
    }
    let (_, collect_room) = splay.collect[i64](&t, root, out[..10usize])
    if collect_room != splay.TooSmall { os.exit(1i32) }
    var small_values: [3]i64 = zero
    var small = splay.splay_tree[i64](small_values[..], left[..], right[..], parent[..], size[..], reversed[..])
    let (_, build_room) = splay.build[i64](&small, items[..])
    if build_room != splay.TooSmall { os.exit(1i32) }

    // 2: splaying by position keeps the sequence and moves the node to the root.
    var r = rand.pcg64(19u64, 19u64)
    var step = 0usize
    while step < 200usize {
        let position = usize(rand.pcg64_bounded(&r, 64u64))
        let (v, new_root, at_error) = splay.at[i64](&t, root, position)
        if at_error != ok || v != i64(position) || t.values[usize(new_root)] != i64(position) || t.parent[usize(new_root)] != 0u32 { os.exit(2i32) }
        root = new_root
        step += 1usize
    }
    let (_, _, past) = splay.at[i64](&t, root, 64usize)
    if past != splay.Invalid { os.exit(2i32) }

    // 3: random range reversals against an array.
    var model: [64]i64 = zero
    i = 0usize
    while i < 64usize {
        model[i] = i64(i)
        i += 1usize
    }
    step = 0usize
    while step < 300usize {
        var low = usize(rand.pcg64_bounded(&r, 64u64))
        var high = usize(rand.pcg64_bounded(&r, 64u64))
        if low > high {
            let tmp = low
            low = high
            high = tmp
        }
        let (new_root, reverse_error) = splay.reverse_range[i64](&t, root, low, high)
        if reverse_error != ok { os.exit(3i32) }
        root = new_root
        var x = low
        var y = high
        while x < y {
            let tmp = model[x]
            model[x] = model[y]
            model[y] = tmp
            x += 1usize
            y -= 1usize
        }
        if step % 25usize == 0usize {
            let (m, e) = splay.collect[i64](&t, root, out[..])
            if e != ok || m != 64usize { os.exit(3i32) }
            i = 0usize
            while i < 64usize {
                if out[i] != model[i] { os.exit(3i32) }
                i += 1usize
            }
        } else {
            let position = usize(rand.pcg64_bounded(&r, 64u64))
            let (v, at_root, at_error) = splay.at[i64](&t, root, position)
            if at_error != ok || v != model[position] { os.exit(3i32) }
            root = at_root
        }
        step += 1usize
    }
    let (m, e) = splay.collect[i64](&t, root, out[..])
    if e != ok || m != 64usize { os.exit(3i32) }
    i = 0usize
    while i < 64usize {
        if out[i] != model[i] { os.exit(3i32) }
        i += 1usize
    }
    let (_, bad_range) = splay.reverse_range[i64](&t, root, 10usize, 64usize)
    if bad_range != splay.Invalid { os.exit(3i32) }
    let (_, backwards) = splay.reverse_range[i64](&t, root, 20usize, 10usize)
    if backwards != splay.Invalid { os.exit(3i32) }

    try io.print("data splay ok\n")
    ret ok
}
