// `e.data.skip_list`: random inserts and removals of distinct keys agree
// with a sorted array, duplicates are refused, lower bounds and the bottom
// chain read the order, freed nodes are reused, and the pool and level
// checks answer. Each check exits with its own code.

use e.algo.rand
use e.data.skip_list
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var keys: [300]i64 = zero
    var forward: [2400]u32 = zero
    var height: [300]u8 = zero
    var r = rand.pcg64(17u64, 3u64)
    let (s0, make_error) = skip_list.skip_list[i64](keys[..], forward[..], height[..], 8usize)
    if make_error != ok { os.exit(1i32) }
    var s = s0
    var model: [300]i64 = zero
    var count = 0usize

    // 1: random operations against the sorted model.
    var step = 0usize
    while step < 2000usize {
        let key = i64(rand.pcg64_bounded(&r, 250u64))
        var at = 0usize
        while at < count && model[at] < key { at += 1usize }
        let present = at < count && model[at] == key
        if rand.pcg64_bounded(&r, 3u64) < 2u64 {
            let insert_error = skip_list.insert[i64](&s, key, &r)
            if present {
                if insert_error != skip_list.Invalid { os.exit(1i32) }
            } else {
                if insert_error != ok { os.exit(1i32) }
                var j = count
                while j > at {
                    model[j] = model[j - 1usize]
                    j -= 1usize
                }
                model[at] = key
                count += 1usize
            }
        } else {
            if skip_list.remove[i64](&s, key) != present { os.exit(1i32) }
            if present {
                var j = at
                while j + 1usize < count {
                    model[j] = model[j + 1usize]
                    j += 1usize
                }
                count -= 1usize
            }
        }
        if s.count != count { os.exit(1i32) }
        step += 1usize
    }
    var out: [300]i64 = zero
    let (collected, collect_error) = skip_list.collect[i64](&s, out[..])
    if collect_error != ok || collected != count { os.exit(1i32) }
    var i = 0usize
    while i < count {
        if out[i] != model[i] || !skip_list.contains[i64](&s, model[i]) { os.exit(1i32) }
        i += 1usize
    }
    if skip_list.contains[i64](&s, 1000i64) || skip_list.contains[i64](&s, 0i64 - 1i64) { os.exit(1i32) }
    // Removed slots were reused: the pool never grew past the keys array.
    if s.used > 300usize { os.exit(1i32) }

    // 2: lower bounds and the chain.
    let first = skip_list.lower_bound[i64](&s, 0i64 - 5i64)
    if first != skip_list.next[i64](&s, 0u32) || s.keys[usize(first)] != model[0usize] { os.exit(2i32) }
    let none = skip_list.lower_bound[i64](&s, 1000i64)
    if none != skip_list.NONE { os.exit(2i32) }
    let middle = skip_list.lower_bound[i64](&s, model[count / 2usize])
    if s.keys[usize(middle)] != model[count / 2usize] { os.exit(2i32) }
    var node = skip_list.next[i64](&s, 0u32)
    i = 0usize
    while node != skip_list.NONE {
        if s.keys[usize(node)] != model[i] { os.exit(2i32) }
        node = skip_list.next[i64](&s, node)
        i += 1usize
    }
    if i != count { os.exit(2i32) }
    let (_, collect_room) = skip_list.collect[i64](&s, out[..2usize])
    if collect_room != skip_list.TooSmall { os.exit(2i32) }

    // 3: the pool and level checks.
    let (_, no_levels) = skip_list.skip_list[i64](keys[..], forward[..], height[..], 0usize)
    if no_levels != skip_list.Invalid { os.exit(3i32) }
    let (_, short_forward) = skip_list.skip_list[i64](keys[..], forward[..100usize], height[..], 8usize)
    if short_forward != skip_list.TooSmall { os.exit(3i32) }
    var few_keys: [3]i64 = zero
    let (tiny0, tiny_error) = skip_list.skip_list[i64](few_keys[..], forward[..], height[..], 2usize)
    if tiny_error != ok { os.exit(3i32) }
    var tiny = tiny0
    if skip_list.insert[i64](&tiny, 1i64, &r) != ok || skip_list.insert[i64](&tiny, 2i64, &r) != ok || skip_list.insert[i64](&tiny, 3i64, &r) != skip_list.TooSmall { os.exit(3i32) }
    if !skip_list.remove[i64](&tiny, 1i64) || skip_list.insert[i64](&tiny, 3i64, &r) != ok || !skip_list.contains[i64](&tiny, 3i64) || skip_list.contains[i64](&tiny, 1i64) { os.exit(3i32) }

    try io.print("data skip list ok\n")
    ret ok
}
