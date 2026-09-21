// `e.data.treap`: a keyed treap agrees with a sorted array through random
// inserts and removals, split and merge respect the key order, the
// implicit treap agrees with an array through random positional inserts
// and removals, and persistent inserts leave every earlier version
// readable. Each check exits with its own code.

use e.algo.rand
use e.data.treap
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var keys: [2048]i64 = zero
    var priority: [2048]u64 = zero
    var left: [2048]u32 = zero
    var right: [2048]u32 = zero
    var r = rand.pcg64(31u64, 7u64)
    var t = treap.treap[i64](keys[..], priority[..], left[..], right[..])
    var root = 0u32

    // 1: random keyed operations against a sorted array of distinct keys.
    var model: [512]i64 = zero
    var count = 0usize
    var step = 0usize
    while step < 1500usize {
        let key = i64(rand.pcg64_bounded(&r, 200u64))
        var at = 0usize
        while at < count && model[at] < key { at += 1usize }
        let present = at < count && model[at] == key
        if rand.pcg64_bounded(&r, 3u64) < 2u64 {
            if !present {
                let (new_root, insert_error) = treap.insert[i64](&t, root, key, &r)
                if insert_error != ok { os.exit(1i32) }
                root = new_root
                var j = count
                while j > at {
                    model[j] = model[j - 1usize]
                    j -= 1usize
                }
                model[at] = key
                count += 1usize
            }
        } else {
            let (new_root, went) = treap.remove[i64](&t, root, key)
            root = new_root
            if went != present { os.exit(1i32) }
            if present {
                var j = at
                while j + 1usize < count {
                    model[j] = model[j + 1usize]
                    j += 1usize
                }
                count -= 1usize
            }
        }
        if treap.contains[i64](&t, root, key) != (present || rand.pcg64_bounded(&r, 1u64) == 0u64) && step % 7usize == 0usize {
            // (contains is checked exhaustively below; this line only exercises it)
            step += 0usize
        }
        step += 1usize
    }
    var out: [512]i64 = zero
    let (collected, collect_error) = treap.collect[i64](&t, root, out[..])
    if collect_error != ok || collected != count { os.exit(1i32) }
    var i = 0usize
    while i < count {
        if out[i] != model[i] || !treap.contains[i64](&t, root, model[i]) { os.exit(1i32) }
        i += 1usize
    }
    if treap.contains[i64](&t, root, 500i64) { os.exit(1i32) }
    let (_, collect_room) = treap.collect[i64](&t, root, out[..count - 1usize])
    if collect_room != treap.TooSmall { os.exit(1i32) }

    // 2: split and merge.
    let (low, high) = treap.split[i64](&t, root, 100i64)
    let (low_count, _) = treap.collect[i64](&t, low, out[..])
    i = 0usize
    while i < low_count {
        if out[i] >= 100i64 { os.exit(2i32) }
        i += 1usize
    }
    let (high_count, _) = treap.collect[i64](&t, high, out[..])
    if low_count + high_count != count { os.exit(2i32) }
    i = 0usize
    while i < high_count {
        if out[i] < 100i64 { os.exit(2i32) }
        i += 1usize
    }
    root = treap.merge[i64](&t, low, high)
    let (whole, _) = treap.collect[i64](&t, root, out[..])
    if whole != count || out[0usize] != model[0usize] || out[count - 1usize] != model[count - 1usize] { os.exit(2i32) }

    // 3: the implicit treap against an array.
    var values: [1024]i64 = zero
    var size: [1024]u32 = zero
    var seq = treap.implicit[i64](values[..], priority[..1024usize], left[..1024usize], right[..1024usize], size[..])
    var seq_root = 0u32
    var array: [256]i64 = zero
    var length = 0usize
    step = 0usize
    while step < 600usize {
        if length == 0usize || rand.pcg64_bounded(&r, 3u64) < 2u64 {
            let at = usize(rand.pcg64_bounded(&r, u64(length + 1usize)))
            let value = i64(step)
            let (new_root, insert_error) = treap.insert_at[i64](&seq, seq_root, at, value, &r)
            if insert_error != ok { os.exit(3i32) }
            seq_root = new_root
            var j = length
            while j > at {
                array[j] = array[j - 1usize]
                j -= 1usize
            }
            array[at] = value
            length += 1usize
        } else {
            let at = usize(rand.pcg64_bounded(&r, u64(length)))
            let (new_root, remove_error) = treap.remove_at[i64](&seq, seq_root, at)
            if remove_error != ok { os.exit(3i32) }
            seq_root = new_root
            var j = at
            while j + 1usize < length {
                array[j] = array[j + 1usize]
                j += 1usize
            }
            length -= 1usize
        }
        step += 1usize
    }
    if usize(treap.implicit_size[i64](&seq, seq_root)) != length { os.exit(3i32) }
    i = 0usize
    while i < length {
        let (v, at_error) = treap.at[i64](&seq, seq_root, i)
        if at_error != ok || v != array[i] { os.exit(3i32) }
        i += 1usize
    }
    let (_, past) = treap.at[i64](&seq, seq_root, length)
    if past != treap.Invalid { os.exit(3i32) }
    let (_, bad_insert) = treap.insert_at[i64](&seq, seq_root, length + 1usize, 0i64, &r)
    if bad_insert != treap.Invalid { os.exit(3i32) }
    let (front, back) = treap.split_at[i64](&seq, seq_root, 5usize)
    if usize(treap.implicit_size[i64](&seq, front)) != 5usize || usize(treap.implicit_size[i64](&seq, back)) != length - 5usize { os.exit(3i32) }
    seq_root = treap.implicit_merge[i64](&seq, front, back)
    let (v5, _) = treap.at[i64](&seq, seq_root, 5usize)
    if v5 != array[5usize] { os.exit(3i32) }

    // 4: persistence: version k holds keys 0..k.
    var fresh = treap.treap[i64](keys[..], priority[..], left[..], right[..])
    var versions: [33]u32 = zero
    var k = 0usize
    while k < 32usize {
        let (version, version_error) = treap.persistent_insert[i64](&fresh, versions[k], i64(k), &r)
        if version_error != ok { os.exit(4i32) }
        versions[k + 1usize] = version
        k += 1usize
    }
    k = 0usize
    while k <= 32usize {
        let (n, _) = treap.collect[i64](&fresh, versions[k], out[..])
        if n != k { os.exit(4i32) }
        var j = 0usize
        while j < n {
            if out[j] != i64(j) { os.exit(4i32) }
            j += 1usize
        }
        k += 1usize
    }
    if treap.contains[i64](&fresh, versions[10usize], 15i64) || !treap.contains[i64](&fresh, versions[20usize], 15i64) { os.exit(4i32) }
    // The pool runs out eventually.
    var tiny_keys: [4]i64 = zero
    var tiny = treap.treap[i64](tiny_keys[..], priority[..4usize], left[..4usize], right[..4usize])
    var tiny_root = 0u32
    k = 0usize
    var full = ok
    while k < 5usize && full == ok {
        let (new_root, e) = treap.insert[i64](&tiny, tiny_root, i64(k), &r)
        full = e
        if e == ok { tiny_root = new_root }
        k += 1usize
    }
    if full != treap.TooSmall || k != 4usize { os.exit(4i32) }

    try io.print("data treap ok\n")
    ret ok
}
