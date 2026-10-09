// `e.algo.search`: binary search and its bounds over duplicates, the probe form,
// linear, exponential and interpolation search, ternary search of a unimodal
// function, saddleback search of a sorted matrix, quickselect and median of
// medians over a shuffled range, and both cycle finders over a modular map.
// Each check exits with its own code.

use e.algo.search
use e.io
use e.mem
use e.os

type Probe = struct { key: i64, calls: usize }
type Peak = struct { top: i64 }
type Map = struct { steps: usize }

fn probe_key(ctx: *Probe, item: i64) -> i32 {
    ctx.calls += 1usize
    if item < ctx.key { ret 0i32 - 1i32 }
    if item > ctx.key { ret 1i32 }
    ret 0i32
}

fn hill(ctx: *Peak, x: i64) -> i64 { ret 0i64 - (x - ctx.top) * (x - ctx.top) }

// x -> (x * x + 1) mod 255: from 3 the orbit enters a cycle after a short tail.
fn step(ctx: *Map, x: u64) -> u64 {
    ctx.steps += 1usize
    ret (x * x + 1u64) % 255u64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var sorted: [10]i64 = zero
    sorted[0usize] = 1i64
    sorted[1usize] = 3i64
    sorted[2usize] = 3i64
    sorted[3usize] = 3i64
    sorted[4usize] = 7i64
    sorted[5usize] = 9i64
    sorted[6usize] = 12i64
    sorted[7usize] = 20i64
    sorted[8usize] = 20i64
    sorted[9usize] = 31i64

    // 1: binary finds a present key and names the insertion point of an absent one.
    let (at7, found7) = search.binary[i64](sorted[..], 7i64)
    if !found7 || at7 != 4usize { os.exit(1i32) }
    let (at8, found8) = search.binary[i64](sorted[..], 8i64)
    if found8 || at8 != 5usize { os.exit(1i32) }
    let (at0, found0) = search.binary[i64](sorted[..], 0i64)
    if found0 || at0 != 0usize { os.exit(1i32) }
    let (at99, found99) = search.binary[i64](sorted[..], 99i64)
    if found99 || at99 != 10usize { os.exit(1i32) }
    var none: [0]i64 = zero
    let (at_none, found_none) = search.binary[i64](none[..], 1i64)
    if found_none || at_none != 0usize { os.exit(1i32) }

    // 2: the bounds bracket a run of duplicates and meet for an absent key.
    if search.lower_bound[i64](sorted[..], 3i64) != 1usize { os.exit(2i32) }
    if search.upper_bound[i64](sorted[..], 3i64) != 4usize { os.exit(2i32) }
    let (lo20, hi20) = search.equal_range[i64](sorted[..], 20i64)
    if lo20 != 7usize || hi20 != 9usize { os.exit(2i32) }
    let (lo8, hi8) = search.equal_range[i64](sorted[..], 8i64)
    if lo8 != 5usize || hi8 != 5usize { os.exit(2i32) }
    if search.lower_bound[i64](sorted[..], 40i64) != 10usize { os.exit(2i32) }

    // 3: the probe form sees O(log n) elements.
    var probe = Probe { key: 12i64, calls: 0usize }
    let (at12, found12) = search.binary_by[i64, Probe](sorted[..], &probe, probe_key)
    if !found12 || at12 != 6usize || probe.calls > 4usize { os.exit(3i32) }

    // 4: linear search over an unordered slice.
    var mixed: [5]i64 = zero
    mixed[0usize] = 4i64
    mixed[1usize] = 0i64 - 2i64
    mixed[2usize] = 9i64
    mixed[3usize] = 4i64
    mixed[4usize] = 6i64
    let (at9, found9) = search.linear[i64](mixed[..], 9i64)
    if !found9 || at9 != 2usize { os.exit(4i32) }
    let (at4, found4) = search.linear[i64](mixed[..], 4i64)
    if !found4 || at4 != 0usize { os.exit(4i32) }
    let (_, found5) = search.linear[i64](mixed[..], 5i64)
    if found5 { os.exit(4i32) }

    // 5: exponential search agrees with binary search on every key.
    var key = 0i64
    while key < 35i64 {
        let (b_at, b_found) = search.binary[i64](sorted[..], key)
        let (e_at, e_found) = search.exponential[i64](sorted[..], key)
        if b_found != e_found { os.exit(5i32) }
        if b_found && sorted[b_at] != sorted[e_at] { os.exit(5i32) }
        if !b_found && b_at != e_at { os.exit(5i32) }
        key += 1i64
    }

    // 6: interpolation search on evenly spaced keys, present and absent.
    var even: [50]i64 = zero
    var i = 0usize
    while i < 50usize {
        even[i] = i64(i) * 10i64
        i += 1usize
    }
    let (at370, found370) = search.interpolation(even[..], 370i64)
    if !found370 || at370 != 37usize { os.exit(6i32) }
    let (_, found375) = search.interpolation(even[..], 375i64)
    if found375 { os.exit(6i32) }
    let (_, found_neg) = search.interpolation(even[..], 0i64 - 5i64)
    if found_neg { os.exit(6i32) }
    let (at490, found490) = search.interpolation(even[..], 490i64)
    if !found490 || at490 != 49usize { os.exit(6i32) }
    let (at_first, found_first) = search.interpolation(sorted[..], 1i64)
    if !found_first || at_first != 0usize { os.exit(6i32) }

    // 7: ternary search finds the peak of a parabola.
    var peak = Peak { top: 17i64 }
    if search.ternary_max[Peak](0i64 - 100i64, 100i64, &peak, hill) != 17i64 { os.exit(7i32) }
    peak.top = 0i64 - 100i64
    if search.ternary_max[Peak](0i64 - 100i64, 100i64, &peak, hill) != 0i64 - 100i64 { os.exit(7i32) }
    peak.top = 3i64
    if search.ternary_max[Peak](3i64, 3i64, &peak, hill) != 3i64 { os.exit(7i32) }

    // 8: saddleback search over a 3x4 matrix sorted along both axes.
    var matrix: [12]i64 = zero
    matrix[0usize] = 1i64
    matrix[1usize] = 4i64
    matrix[2usize] = 7i64
    matrix[3usize] = 11i64
    matrix[4usize] = 2i64
    matrix[5usize] = 5i64
    matrix[6usize] = 8i64
    matrix[7usize] = 12i64
    matrix[8usize] = 3i64
    matrix[9usize] = 6i64
    matrix[10usize] = 9i64
    matrix[11usize] = 16i64
    let (row5, col5, found_m5) = search.matrix_sorted[i64](matrix[..], 4usize, 5i64)
    if !found_m5 || row5 != 1usize || col5 != 1usize { os.exit(8i32) }
    let (row16, col16, found_m16) = search.matrix_sorted[i64](matrix[..], 4usize, 16i64)
    if !found_m16 || row16 != 2usize || col16 != 3usize { os.exit(8i32) }
    let (_, _, found_m10) = search.matrix_sorted[i64](matrix[..], 4usize, 10i64)
    if found_m10 { os.exit(8i32) }
    let (_, _, found_m0) = search.matrix_sorted[i64](matrix[..], 0usize, 1i64)
    if found_m0 { os.exit(8i32) }

    // 9: both selections agree with the sorted order of a scrambled range.
    var scrambled: [23]i64 = zero
    i = 0usize
    while i < 23usize {
        scrambled[i] = i64((i * 7usize + 3usize) % 23usize)
        i += 1usize
    }
    var k = 0usize
    while k < 23usize {
        var copy_a: [23]i64 = zero
        var copy_b: [23]i64 = zero
        i = 0usize
        while i < 23usize {
            copy_a[i] = scrambled[i]
            copy_b[i] = scrambled[i]
            i += 1usize
        }
        if search.kth[i64](copy_a[..], k) != i64(k) { os.exit(9i32) }
        if search.kth_deterministic[i64](copy_b[..], k) != i64(k) { os.exit(9i32) }
        // The chosen element sits at `k` after quickselect partitions around it.
        if copy_a[k] != i64(k) { os.exit(9i32) }
        k += 1usize
    }
    var dupes: [6]i64 = zero
    dupes[0usize] = 5i64
    dupes[1usize] = 1i64
    dupes[2usize] = 5i64
    dupes[3usize] = 1i64
    dupes[4usize] = 5i64
    dupes[5usize] = 2i64
    if search.kth[i64](dupes[..], 2usize) != 2i64 { os.exit(9i32) }
    if search.kth_deterministic[i64](dupes[..], 3usize) != 5i64 { os.exit(9i32) }
    var one: [1]i64 = zero
    one[0usize] = 8i64
    if search.kth[i64](one[..], 0usize) != 8i64 || search.kth_deterministic[i64](one[..], 0usize) != 8i64 { os.exit(9i32) }

    // 10: the cycle finders agree, and Brent calls the map fewer times.
    var floyd_map = Map { steps: 0usize }
    let (mu_f, lambda_f) = search.cycle_floyd[Map](3u64, &floyd_map, step)
    var brent_map = Map { steps: 0usize }
    let (mu_b, lambda_b) = search.cycle_brent[Map](3u64, &brent_map, step)
    if mu_f != mu_b || lambda_f != lambda_b || lambda_f == 0usize { os.exit(10i32) }
    if brent_map.steps >= floyd_map.steps { os.exit(10i32) }
    // Walking mu steps then lambda more lands on the same value.
    var x = 3u64
    i = 0usize
    while i < mu_f {
        x = step(&floyd_map, x)
        i += 1usize
    }
    var y = x
    i = 0usize
    while i < lambda_f {
        y = step(&floyd_map, y)
        i += 1usize
    }
    if x != y { os.exit(10i32) }
    try io.print("algo search ok\n")
    ret ok
}
