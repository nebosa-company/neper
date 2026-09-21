// `e.ratelimit`: each limiter's allow/deny sequence over 200 LCG-timed
// requests folds to the hash a Python replica computed, a fixed window
// admits a double burst at its boundary while the sliding log and sliding
// window do not, a small ring caps the log, and an idle token bucket
// refills. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.ratelimit

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: token bucket.
    var state = 1u64
    var now = 0u64
    var h = 0u64
    var admitted = 0u64
    let (tb, tb_error) = ratelimit.token_bucket(10u64, 1u64, 25u64, 0u64)
    if tb_error != ok { os.exit(1i32) }
    var bucket = tb
    var i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += (state >> 33u32) % 100u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let cost = 1u64 + (state >> 33u32) % 3u64
        var bit = 0u64
        if ratelimit.token_bucket_allow(&bucket, now, cost) { bit = 1u64 }
        h = h *% 3u64 +% bit
        admitted += bit
        i += 1usize
    }
    if h != 12695717117798291510u64 || admitted != 184u64 { os.exit(1i32) }
    let (_, bad_tb) = ratelimit.token_bucket(10u64, 1u64, 0u64, 0u64)
    if bad_tb != ratelimit.Invalid { os.exit(1i32) }

    // 2: leaky bucket.
    state = 2u64
    now = 0u64
    h = 0u64
    admitted = 0u64
    let (lb, lb_error) = ratelimit.leaky_bucket(10u64, 1u64, 25u64, 0u64)
    if lb_error != ok { os.exit(2i32) }
    var leaky = lb
    i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += (state >> 33u32) % 100u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let cost = 1u64 + (state >> 33u32) % 3u64
        var bit = 0u64
        if ratelimit.leaky_bucket_allow(&leaky, now, cost) { bit = 1u64 }
        h = h *% 3u64 +% bit
        admitted += bit
        i += 1usize
    }
    if h != 4224356592107771649u64 || admitted != 195u64 { os.exit(2i32) }

    // 3: fixed window.
    state = 3u64
    now = 0u64
    h = 0u64
    admitted = 0u64
    let (fw, fw_error) = ratelimit.fixed_window(6u64, 250u64)
    if fw_error != ok { os.exit(3i32) }
    var fixed = fw
    i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += (state >> 33u32) % 100u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let cost = 1u64 + (state >> 33u32) % 3u64
        var bit = 0u64
        if ratelimit.fixed_window_allow(&fixed, now, cost) { bit = 1u64 }
        h = h *% 3u64 +% bit
        admitted += bit
        i += 1usize
    }
    if h != 13401982824538506796u64 || admitted != 120u64 { os.exit(3i32) }

    // 4: sliding log.
    state = 4u64
    now = 0u64
    h = 0u64
    admitted = 0u64
    var stamps: [8]u64 = zero
    let (sl, sl_error) = ratelimit.sliding_log(6u64, 250u64, stamps[..])
    if sl_error != ok { os.exit(4i32) }
    var log = sl
    i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += (state >> 33u32) % 100u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        var bit = 0u64
        if ratelimit.sliding_log_allow(&log, now) { bit = 1u64 }
        h = h *% 3u64 +% bit
        admitted += bit
        i += 1usize
    }
    if h != 15559825340222529691u64 || admitted != 181u64 { os.exit(4i32) }
    if ratelimit.sliding_log_count(&log, now + 250u64) != 0u64 { os.exit(4i32) }

    // 5: sliding window counter.
    state = 5u64
    now = 0u64
    h = 0u64
    admitted = 0u64
    let (sw, sw_error) = ratelimit.sliding_window(6u64, 250u64)
    if sw_error != ok { os.exit(5i32) }
    var sliding = sw
    i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += (state >> 33u32) % 100u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let cost = 1u64 + (state >> 33u32) % 3u64
        var bit = 0u64
        if ratelimit.sliding_window_allow(&sliding, now, cost) { bit = 1u64 }
        h = h *% 3u64 +% bit
        admitted += bit
        i += 1usize
    }
    if h != 6706470317136287945u64 || admitted != 119u64 { os.exit(5i32) }

    // 6: the boundary burst: ten at 999 then ten at 1000 with limit 10 per 1000.
    let (bf, _) = ratelimit.fixed_window(10u64, 1000u64)
    var burst_fixed = bf
    var ring: [16]u64 = zero
    let (bl, _) = ratelimit.sliding_log(10u64, 1000u64, ring[..])
    var burst_log = bl
    let (bw, _) = ratelimit.sliding_window(10u64, 1000u64)
    var burst_window = bw
    var fixed_count = 0u64
    var log_count = 0u64
    var window_count = 0u64
    var t = 999u64
    while t <= 1000u64 {
        i = 0usize
        while i < 10usize {
            if ratelimit.fixed_window_allow(&burst_fixed, t, 1u64) { fixed_count += 1u64 }
            if ratelimit.sliding_log_allow(&burst_log, t) { log_count += 1u64 }
            if ratelimit.sliding_window_allow(&burst_window, t, 1u64) { window_count += 1u64 }
            i += 1usize
        }
        t += 1u64
    }
    if fixed_count != 20u64 || log_count != 10u64 || window_count != 10u64 { os.exit(6i32) }
    if ratelimit.sliding_window_count(&burst_window, 1500u64) != 5u64 { os.exit(6i32) }

    // 7: a ring smaller than the limit caps the log; an idle bucket refills.
    var small: [4]u64 = zero
    let (sr, _) = ratelimit.sliding_log(10u64, 1000u64, small[..])
    var small_log = sr
    var small_count = 0u64
    i = 0usize
    while i < 6usize {
        if ratelimit.sliding_log_allow(&small_log, 0u64) { small_count += 1u64 }
        i += 1usize
    }
    if small_count != 4u64 { os.exit(7i32) }
    let (rb, _) = ratelimit.token_bucket(10u64, 1u64, 25u64, 0u64)
    var refilling = rb
    if !ratelimit.token_bucket_allow(&refilling, 0u64, 10u64) { os.exit(7i32) }
    if ratelimit.token_bucket_allow(&refilling, 0u64, 1u64) { os.exit(7i32) }
    if ratelimit.token_bucket_tokens(&refilling, 100u64) != 4u64 { os.exit(7i32) }
    if ratelimit.token_bucket_tokens(&refilling, 100000u64) != 10u64 { os.exit(7i32) }
    let (eb, _) = ratelimit.leaky_bucket(10u64, 1u64, 25u64, 0u64)
    var emptying = eb
    if !ratelimit.leaky_bucket_allow(&emptying, 0u64, 10u64) { os.exit(7i32) }
    if ratelimit.leaky_bucket_allow(&emptying, 0u64, 1u64) { os.exit(7i32) }
    if ratelimit.leaky_bucket_level(&emptying, 100u64) != 6u64 { os.exit(7i32) }
    if ratelimit.leaky_bucket_level(&emptying, 100000u64) != 0u64 { os.exit(7i32) }

    try io.print("ratelimit ok\n")
    ret ok
}
