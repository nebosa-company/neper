// `e.data.fenwick` and `e.data.sparse_table` against direct scans: prefix and
// range sums under point updates, the linear build, the lower-bound descent over
// a prefix total; range minimum and maximum over every window of a non-power-of-
// two array, and the disjoint table's sums over the same windows. Each check
// exits with its own code.

use e.data.fenwick
use e.data.sparse_table
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var values: [13]i64 = zero
    var i = 0usize
    while i < 13usize {
        // 1, 8, 2, -4, 3, -3, 4, -2, 5, -1, 6, 0, 7
        values[i] = i64((i * 7usize + 5usize) % 13usize) - 4i64
        i += 1usize
    }

    // 1: Fenwick prefix and range sums agree with a scan, before and after updates.
    var storage: [13]i64 = zero
    var f = fenwick.init(storage[..])
    if fenwick.len(&f) != 13usize || fenwick.prefix_sum(&f, 13usize) != 0i64 { os.exit(1i32) }
    i = 0usize
    while i < 13usize {
        fenwick.add(&f, i, values[i])
        i += 1usize
    }
    var low = 0usize
    while low <= 13usize {
        var high = low
        while high <= 13usize {
            var want = 0i64
            var k = low
            while k < high {
                want += values[k]
                k += 1usize
            }
            if fenwick.range_sum(&f, low, high) != want { os.exit(1i32) }
            high += 1usize
        }
        if fenwick.prefix_sum(&f, low) != fenwick.range_sum(&f, 0usize, low) { os.exit(1i32) }
        low += 1usize
    }
    fenwick.add(&f, 4usize, 100i64)
    values[4usize] += 100i64
    fenwick.set(&f, 12usize, 0i64 - 50i64)
    values[12usize] = 0i64 - 50i64
    if fenwick.get(&f, 4usize) != values[4usize] || fenwick.get(&f, 12usize) != 0i64 - 50i64 { os.exit(1i32) }
    var total = 0i64
    i = 0usize
    while i < 13usize {
        total += values[i]
        i += 1usize
    }
    if fenwick.prefix_sum(&f, 13usize) != total { os.exit(1i32) }
    if fenwick.range_sum(&f, 5usize, 5usize) != 0i64 || fenwick.range_sum(&f, 6usize, 2usize) != 0i64 { os.exit(1i32) }

    // 2: the linear build matches the incremental one.
    var copy: [13]i64 = zero
    i = 0usize
    while i < 13usize {
        copy[i] = values[i]
        i += 1usize
    }
    let g = fenwick.from_values(copy[..])
    i = 0usize
    while i <= 13usize {
        if fenwick.prefix_sum(&g, i) != fenwick.prefix_sum(&f, i) { os.exit(2i32) }
        i += 1usize
    }

    // 3: lower_bound over non-negative counts: the first prefix reaching a total.
    var counts: [10]i64 = zero
    var h = fenwick.init(counts[..])
    // 2, 0, 3, 0, 0, 5, 1, 0, 0, 4: prefix sums 2 2 5 5 5 10 11 11 11 15.
    fenwick.add(&h, 0usize, 2i64)
    fenwick.add(&h, 2usize, 3i64)
    fenwick.add(&h, 5usize, 5i64)
    fenwick.add(&h, 6usize, 1i64)
    fenwick.add(&h, 9usize, 4i64)
    if fenwick.lower_bound(&h, 1i64) != 1usize || fenwick.lower_bound(&h, 2i64) != 1usize { os.exit(3i32) }
    if fenwick.lower_bound(&h, 3i64) != 3usize || fenwick.lower_bound(&h, 5i64) != 3usize { os.exit(3i32) }
    if fenwick.lower_bound(&h, 6i64) != 6usize || fenwick.lower_bound(&h, 11i64) != 7usize { os.exit(3i32) }
    if fenwick.lower_bound(&h, 15i64) != 10usize || fenwick.lower_bound(&h, 16i64) != 11usize { os.exit(3i32) }
    if fenwick.lower_bound(&h, 0i64) != 1usize { os.exit(3i32) }

    // 4: range minimum and maximum over every window.
    if sparse_table.levels_for(13usize) != 4usize || sparse_table.levels_for(0usize) != 1usize || sparse_table.levels_for(16usize) != 5usize { os.exit(4i32) }
    var min_storage: [52]i64 = zero
    var max_storage: [52]i64 = zero
    let (mins, min_error) = sparse_table.build[i64](min_storage[..], values[..], false)
    let (maxes, max_error) = sparse_table.build[i64](max_storage[..], values[..], true)
    if min_error != ok || max_error != ok { os.exit(4i32) }
    low = 0usize
    while low < 13usize {
        var high = low + 1usize
        while high <= 13usize {
            var least = values[low]
            var most = values[low]
            var k = low
            while k < high {
                if values[k] < least { least = values[k] }
                if values[k] > most { most = values[k] }
                k += 1usize
            }
            let (got_min, min_query_error) = sparse_table.query[i64](&mins, low, high)
            let (got_max, max_query_error) = sparse_table.query[i64](&maxes, low, high)
            if min_query_error != ok || max_query_error != ok || got_min != least || got_max != most { os.exit(4i32) }
            high += 1usize
        }
        low += 1usize
    }
    let (_, empty_error) = sparse_table.query[i64](&mins, 3usize, 3usize)
    if empty_error != sparse_table.Invalid { os.exit(4i32) }
    let (_, past_error) = sparse_table.query[i64](&mins, 0usize, 14usize)
    if past_error != sparse_table.Invalid { os.exit(4i32) }
    let (_, room_error) = sparse_table.build[i64](min_storage[..40usize], values[..], false)
    if room_error != sparse_table.TooSmall { os.exit(4i32) }

    // 5: the disjoint table's sums over every window.
    var sum_storage: [52]i64 = zero
    let (sums, sums_error) = sparse_table.disjoint_build(sum_storage[..], values[..])
    if sums_error != ok { os.exit(5i32) }
    low = 0usize
    while low < 13usize {
        var high = low + 1usize
        while high <= 13usize {
            var want = 0i64
            var k = low
            while k < high {
                want += values[k]
                k += 1usize
            }
            let (got, sum_error) = sparse_table.disjoint_query(&sums, low, high)
            if sum_error != ok || got != want { os.exit(5i32) }
            high += 1usize
        }
        low += 1usize
    }
    let (_, sum_empty) = sparse_table.disjoint_query(&sums, 2usize, 2usize)
    if sum_empty != sparse_table.Invalid { os.exit(5i32) }
    var eight: [8]i64 = zero
    i = 0usize
    while i < 8usize {
        eight[i] = i64(i) * 3i64 - 7i64
        i += 1usize
    }
    var eight_storage: [32]i64 = zero
    let (eight_sums, eight_error) = sparse_table.disjoint_build(eight_storage[..], eight[..])
    if eight_error != ok { os.exit(5i32) }
    let (whole, whole_error) = sparse_table.disjoint_query(&eight_sums, 0usize, 8usize)
    if whole_error != ok || whole != 28i64 { os.exit(5i32) }

    try io.print("data range query ok\n")
    ret ok
}
