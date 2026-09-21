// `e.data.segment_tree` against direct scans: a max tree under point updates
// over every window, the lazy tree's sums and minima under overlapping range
// additions, and the persistent tree answering every old version after a run
// of updates. Each check exits with its own code.

use e.data.segment_tree
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

fn larger(ctx: *Nothing, a: i64, b: i64) -> i64 {
    if b > a { ret b }
    ret a
}

fn main(a: *mem.Arena, args: []str) -> err {
    var values: [11]i64 = zero
    var i = 0usize
    while i < 11usize {
        values[i] = i64((i * 5usize + 3usize) % 11usize) - 5i64
        i += 1usize
    }
    var nothing = Nothing { unused: 0u8 }

    // 1: a max tree over every window, before and after point updates.
    var nodes: [44]i64 = zero
    let (tree, build_error) = segment_tree.build[i64, Nothing](nodes[..], values[..], 0i64 - 1000000i64, &nothing, larger)
    if build_error != ok { os.exit(1i32) }
    var t = tree
    var round = 0usize
    while round < 3usize {
        var low = 0usize
        while low <= 11usize {
            var high = low
            while high <= 11usize {
                var want = 0i64 - 1000000i64
                var k = low
                while k < high {
                    if values[k] > want { want = values[k] }
                    k += 1usize
                }
                let (got, query_error) = segment_tree.query[i64, Nothing](&t, low, high, &nothing, larger)
                if query_error != ok || got != want { os.exit(1i32) }
                high += 1usize
            }
            low += 1usize
        }
        let at = (round * 7usize + 2usize) % 11usize
        values[at] = 100i64 * i64(round + 1usize) - 150i64
        if segment_tree.update[i64, Nothing](&t, at, values[at], &nothing, larger) != ok { os.exit(1i32) }
        round += 1usize
    }
    let (_, past) = segment_tree.query[i64, Nothing](&t, 0usize, 12usize, &nothing, larger)
    if past != segment_tree.Invalid { os.exit(1i32) }
    if segment_tree.update[i64, Nothing](&t, 11usize, 0i64, &nothing, larger) != segment_tree.Invalid { os.exit(1i32) }
    let (_, room) = segment_tree.build[i64, Nothing](nodes[..40usize], values[..], 0i64, &nothing, larger)
    if room != segment_tree.TooSmall { os.exit(1i32) }

    // 2: the lazy tree under overlapping range additions.
    var base: [11]i64 = zero
    i = 0usize
    while i < 11usize {
        base[i] = i64(i) * 3i64 - 10i64
        i += 1usize
    }
    var sums: [44]i64 = zero
    var mins: [44]i64 = zero
    var pending: [44]i64 = zero
    let (lazy, lazy_error) = segment_tree.lazy_build(sums[..], mins[..], pending[..], base[..])
    if lazy_error != ok { os.exit(2i32) }
    var l = lazy
    var step = 0usize
    while step < 6usize {
        let from = (step * 3usize) % 9usize
        let to = from + 2usize + step % 3usize
        let delta = i64(step) * 7i64 - 12i64
        if segment_tree.lazy_add(&l, from, to, delta) != ok { os.exit(2i32) }
        var k = from
        while k < to {
            base[k] += delta
            k += 1usize
        }
        var low = 0usize
        while low < 11usize {
            var high = low + 1usize
            while high <= 11usize {
                var want_sum = 0i64
                var want_min = base[low]
                k = low
                while k < high {
                    want_sum += base[k]
                    if base[k] < want_min { want_min = base[k] }
                    k += 1usize
                }
                let (got_sum, sum_error) = segment_tree.lazy_sum(&l, low, high)
                let (got_min, min_error) = segment_tree.lazy_min(&l, low, high)
                if sum_error != ok || min_error != ok || got_sum != want_sum || got_min != want_min { os.exit(2i32) }
                high += 1usize
            }
            low += 1usize
        }
        step += 1usize
    }
    let (empty_sum, empty_error) = segment_tree.lazy_sum(&l, 4usize, 4usize)
    if empty_error != ok || empty_sum != 0i64 { os.exit(2i32) }
    let (_, empty_min) = segment_tree.lazy_min(&l, 4usize, 4usize)
    if empty_min != segment_tree.Invalid { os.exit(2i32) }
    if segment_tree.lazy_add(&l, 0usize, 12usize, 1i64) != segment_tree.Invalid { os.exit(2i32) }

    // 3: the persistent tree keeps every version.
    var left: [128]u32 = zero
    var right: [128]u32 = zero
    var psums: [128]i64 = zero
    var start: [7]i64 = zero
    i = 0usize
    while i < 7usize {
        start[i] = i64(i) + 1i64
        i += 1usize
    }
    let (persistent, root0, persistent_error) = segment_tree.persistent_build(left[..], right[..], psums[..], start[..])
    if persistent_error != ok { os.exit(3i32) }
    var p = persistent
    var roots: [8]u32 = zero
    roots[0usize] = root0
    var version = 1usize
    while version < 8usize {
        let index = (version * 3usize) % 7usize
        let (next_root, add_error) = segment_tree.persistent_add(&p, roots[version - 1usize], index, i64(version) * 10i64)
        if add_error != ok { os.exit(3i32) }
        roots[version] = next_root
        version += 1usize
    }
    // Version v holds start plus the first v updates.
    version = 0usize
    while version < 8usize {
        var expected: [7]i64 = zero
        i = 0usize
        while i < 7usize {
            expected[i] = start[i]
            i += 1usize
        }
        var v = 1usize
        while v <= version {
            expected[(v * 3usize) % 7usize] += i64(v) * 10i64
            v += 1usize
        }
        var low = 0usize
        while low <= 7usize {
            var high = low
            while high <= 7usize {
                var want = 0i64
                var k = low
                while k < high {
                    want += expected[k]
                    k += 1usize
                }
                let (got, sum_error) = segment_tree.persistent_sum(&p, roots[version], low, high)
                if sum_error != ok || got != want { os.exit(3i32) }
                high += 1usize
            }
            low += 1usize
        }
        version += 1usize
    }
    // 13 nodes for the build (7 leaves, 6 inner), then a fresh path per update: six of
    // four nodes and one of three (index 6 sits one level higher): 40 used.
    if p.used != 40usize { os.exit(3i32) }
    var small_left: [16]u32 = zero
    var small_right: [16]u32 = zero
    var small_sums: [16]i64 = zero
    let (small, small_root, small_error) = segment_tree.persistent_build(small_left[..], small_right[..], small_sums[..], start[..])
    if small_error != ok { os.exit(3i32) }
    var q = small
    let (_, full_error) = segment_tree.persistent_add(&q, small_root, 0usize, 1i64)
    if full_error != segment_tree.TooSmall { os.exit(3i32) }
    let (_, index_error) = segment_tree.persistent_add(&p, roots[7usize], 7usize, 1i64)
    if index_error != segment_tree.Invalid { os.exit(3i32) }

    try io.print("data segment tree ok\n")
    ret ok
}
