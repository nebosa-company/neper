// `e.data.window`: the monotonic queue answers the window minimum and
// maximum of a random stream against a scan, the two-stack window folds a
// non-invertible operation (the maximum) like a scan, and the exponential
// histogram counts the ones of the last hundred bits within its error
// bound. Each check exits with its own code.

use e.algo.rand
use e.data.window
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

fn larger(ctx: *Nothing, a: i64, b: i64) -> i64 {
    if a > b { ret a }
    ret b
}

fn main(a: *mem.Arena, args: []str) -> err {
    var r = rand.pcg64(23u64, 5u64)
    var stream: [500]i64 = zero
    var i = 0usize
    while i < 500usize {
        stream[i] = i64(rand.pcg64_bounded(&r, 1000u64))
        i += 1usize
    }

    // 1: the monotonic queue.
    var values: [16]i64 = zero
    var positions: [16]u64 = zero
    let (q0, q_error) = window.monotonic_queue(values[..], positions[..], 16usize, true)
    if q_error != ok { os.exit(1i32) }
    var q = q0
    let (_, empty) = window.monotonic_extreme(&q)
    if empty != window.Invalid { os.exit(1i32) }
    var big_values: [16]i64 = zero
    var big_positions: [16]u64 = zero
    let (b0, b_error) = window.monotonic_queue(big_values[..], big_positions[..], 16usize, false)
    if b_error != ok { os.exit(1i32) }
    var big = b0
    i = 0usize
    while i < 500usize {
        window.monotonic_push(&q, stream[i])
        window.monotonic_push(&big, stream[i])
        var start = 0usize
        if i >= 15usize { start = i - 15usize }
        var least = stream[start]
        var most = stream[start]
        var j = start
        while j <= i {
            if stream[j] < least { least = stream[j] }
            if stream[j] > most { most = stream[j] }
            j += 1usize
        }
        let (got_min, min_error) = window.monotonic_extreme(&q)
        let (got_max, max_error) = window.monotonic_extreme(&big)
        if min_error != ok || max_error != ok || got_min != least || got_max != most { os.exit(1i32) }
        i += 1usize
    }
    let (_, bad_width) = window.monotonic_queue(values[..], positions[..], 0usize, true)
    if bad_width != window.Invalid { os.exit(1i32) }
    let (_, small) = window.monotonic_queue(values[..], positions[..], 20usize, true)
    if small != window.TooSmall { os.exit(1i32) }

    // 2: the two-stack window over the maximum with a moving width.
    var nothing = Nothing { unused: 0u8 }
    var front: [32]i64 = zero
    var folds: [32]i64 = zero
    var back: [32]i64 = zero
    var w = window.two_stack[i64](front[..], folds[..], back[..], 0i64 - 1i64)
    var head = 0usize
    i = 0usize
    while i < 500usize {
        if window.two_stack_push[i64](&w, stream[i]) != ok { os.exit(2i32) }
        // Keep between 1 and 20 elements: pop when the random width says so.
        if i - head >= 20usize || (i > head && rand.pcg64_bounded(&r, 3u64) == 0u64) {
            let (popped, pop_error) = window.two_stack_pop[i64, Nothing](&w, &nothing, larger)
            if pop_error != ok || popped != stream[head] { os.exit(2i32) }
            head += 1usize
        }
        var most = stream[head]
        var j = head
        while j <= i {
            if stream[j] > most { most = stream[j] }
            j += 1usize
        }
        if window.two_stack_query[i64, Nothing](&w, &nothing, larger) != most { os.exit(2i32) }
        i += 1usize
    }
    while head < 500usize {
        let (popped, pop_error) = window.two_stack_pop[i64, Nothing](&w, &nothing, larger)
        if pop_error != ok || popped != stream[head] { os.exit(2i32) }
        head += 1usize
    }
    let (_, drained) = window.two_stack_pop[i64, Nothing](&w, &nothing, larger)
    if drained != window.Invalid || window.two_stack_query[i64, Nothing](&w, &nothing, larger) != 0i64 - 1i64 { os.exit(2i32) }

    // 3: the exponential histogram with k = 4 over a window of 100 bits.
    var sizes: [64]u64 = zero
    var stamps: [64]u64 = zero
    let (h0, h_error) = window.exponential_histogram(sizes[..], stamps[..], 100u64, 4usize)
    if h_error != ok { os.exit(3i32) }
    var h = h0
    var bits: [2000]bool = zero
    i = 0usize
    while i < 2000usize {
        bits[i] = rand.pcg64_bounded(&r, 4u64) != 0u64
        if window.histogram_push(&h, bits[i]) != ok { os.exit(3i32) }
        if i >= 100usize {
            var exact = 0u64
            var j = i + 1usize - 100usize
            while j <= i {
                if bits[j] { exact += 1u64 }
                j += 1usize
            }
            let estimate = window.histogram_estimate(&h)
            // Relative error at most 1 / k = 25 percent.
            var difference = 0u64
            if estimate > exact { difference = estimate - exact } else { difference = exact - estimate }
            if difference * 4u64 > exact { os.exit(3i32) }
        }
        i += 1usize
    }
    if h.count > 64usize { os.exit(3i32) }
    let (_, bad_k) = window.exponential_histogram(sizes[..], stamps[..], 100u64, 0usize)
    if bad_k != window.Invalid { os.exit(3i32) }
    let (_, few_buckets) = window.exponential_histogram(sizes[..10usize], stamps[..10usize], 100u64, 4usize)
    if few_buckets != window.TooSmall { os.exit(3i32) }

    try io.print("data window ok\n")
    ret ok
}
