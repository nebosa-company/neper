// `e.resilience`: the breaker walks a scripted sequence of failures,
// successes and clock advances through Closed/Open/HalfOpen exactly as the
// Python replica; exponential backoff saturates, full jitter stays under its
// ceiling and decorrelated jitter within [base, cap]; the heartbeat sweep
// reports the unseen; the shedder admits by band against an EWMA; the
// bulkhead bounds permits; health folds probes; rollout buckets match FNV
// computed in Python. Each check exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.os
use e.resilience as res

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: circuit breaker script (threshold 3, timeout 100, 2 probes).
    var b = res.circuit_breaker(3u32, 100u64, 2u32)
    let ops: [18]u8 = [18]u8{ 0u8, 2u8, 2u8, 1u8, 2u8, 2u8, 2u8, 0u8, 0u8, 0u8, 2u8, 0u8, 0u8, 1u8, 0u8, 1u8, 0u8, 2u8 }
    let nows: [18]u64 = [18]u64{ 0u64, 1u64, 2u64, 3u64, 4u64, 5u64, 6u64, 7u64, 50u64, 106u64, 107u64, 108u64, 207u64, 208u64, 209u64, 210u64, 211u64, 212u64 }
    let states: [18]u8 = [18]u8{ 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8, 1u8, 1u8, 2u8, 1u8, 1u8, 2u8, 2u8, 2u8, 0u8, 0u8, 0u8 }
    let allows: [8]bool = [8]bool{ true, false, false, true, false, true, true, true }
    var allow_at = 0usize
    var i = 0usize
    while i < 18usize {
        if ops[i] == 0u8 {
            if res.breaker_allow(&b, nows[i]) != allows[allow_at] { os.exit(1i32) }
            allow_at += 1usize
        } else if ops[i] == 1u8 {
            res.breaker_success(&b)
        } else {
            res.breaker_failure(&b, nows[i])
        }
        var st = 0u8
        if b.state == .Open { st = 1u8 }
        if b.state == .HalfOpen { st = 2u8 }
        if st != states[i] { os.exit(1i32) }
        i += 1usize
    }

    // 2: exponential backoff saturates.
    let attempts: [8]u32 = [8]u32{ 0u32, 1u32, 5u32, 8u32, 9u32, 63u32, 64u32, 200u32 }
    let expo: [8]u64 = [8]u64{ 100u64, 200u64, 3200u64, 25600u64, 30000u64, 30000u64, 30000u64, 30000u64 }
    i = 0usize
    while i < 8usize {
        if res.backoff_exponential(attempts[i], 100u64, 30000u64) != expo[i] { os.exit(2i32) }
        i += 1usize
    }
    let top = 18446744073709551615u64
    if res.backoff_exponential(60u32, 1024u64, top) != top { os.exit(2i32) }
    if res.backoff_exponential(3u32, 4611686018427387904u64, top) != top { os.exit(2i32) }

    // 3: full jitter within [0, ceiling], decorrelated within [base, cap].
    var r = rand.pcg64(9u64, 3u64)
    var attempt = 0u32
    var saw_high = false
    while attempt < 12u32 {
        var k = 0usize
        while k < 50usize {
            let d = res.backoff(attempt, 100u64, 30000u64, &r)
            if d > res.backoff_exponential(attempt, 100u64, 30000u64) { os.exit(3i32) }
            if d > 15000u64 { saw_high = true }
            k += 1usize
        }
        attempt += 1u32
    }
    if !saw_high { os.exit(3i32) }
    if res.backoff(3u32, 7u64, top, &r) > 56u64 { os.exit(3i32) }
    var previous = 0u64
    var saw_cap = false
    i = 0usize
    while i < 200usize {
        previous = res.backoff_decorrelated(previous, 100u64, 5000u64, &r)
        if previous < 100u64 || previous > 5000u64 { os.exit(3i32) }
        if previous == 5000u64 { saw_cap = true }
        i += 1usize
    }
    if !saw_cap { os.exit(3i32) }
    if res.backoff_decorrelated(top, 100u64, top, &r) < 100u64 { os.exit(3i32) }
    if res.backoff_decorrelated(0u64, 10u64, 10u64, &r) != 10u64 { os.exit(3i32) }

    // 4: heartbeat observe and sweep.
    var ids: [4]u64 = zero
    var seen: [4]u64 = zero
    var dead: [4]u64 = zero
    var h = res.heartbeat(ids[..], seen[..])
    if res.heartbeat_observe(&h, 1u64, 10u64) != ok { os.exit(4i32) }
    if res.heartbeat_observe(&h, 2u64, 12u64) != ok { os.exit(4i32) }
    if res.heartbeat_observe(&h, 3u64, 14u64) != ok { os.exit(4i32) }
    if res.heartbeat_observe(&h, 1u64, 20u64) != ok { os.exit(4i32) }
    if h.count != 3usize { os.exit(4i32) }
    if !res.heartbeat_alive(&h, 1u64, 25u64, 10u64) || res.heartbeat_alive(&h, 2u64, 25u64, 10u64) { os.exit(4i32) }
    let (dead1, sweep1) = res.heartbeat_sweep(&h, 25u64, 10u64, dead[..])
    if sweep1 != ok || dead1 != 2usize || dead[0usize] != 2u64 || dead[1usize] != 3u64 || h.count != 1usize { os.exit(4i32) }
    if res.heartbeat_observe(&h, 4u64, 26u64) != ok { os.exit(4i32) }
    let (dead2, sweep2) = res.heartbeat_sweep(&h, 40u64, 10u64, dead[..])
    if sweep2 != ok || dead2 != 2usize || dead[0usize] != 1u64 || dead[1usize] != 4u64 || h.count != 0usize { os.exit(4i32) }
    let (dead3, sweep3) = res.heartbeat_sweep(&h, 100u64, 10u64, dead[..])
    if sweep3 != ok || dead3 != 0usize { os.exit(4i32) }
    i = 0usize
    while i < 4usize {
        if res.heartbeat_observe(&h, u64(i), 1u64) != ok { os.exit(4i32) }
        i += 1usize
    }
    if res.heartbeat_observe(&h, 9u64, 1u64) != res.TooSmall { os.exit(4i32) }
    let (_, sweep_room) = res.heartbeat_sweep(&h, 100u64, 10u64, dead[..1usize])
    if sweep_room != res.TooSmall { os.exit(4i32) }

    // 5: load shedding by band.
    let thresholds: [3]f64 = [3]f64{ 0.9f64, 0.7f64, 0.4f64 }
    var s = res.load_shed(0.5f64, thresholds[..])
    let samples: [7]f64 = [7]f64{ 0.2f64, 0.6f64, 1.0f64, 1.0f64, 0.3f64, 0.0f64, 0.0f64 }
    let admits: [28]bool = [28]bool{ true, true, true, true, true, true, true, true, true, true, false, false, true, false, false, false, true, true, false, false, true, true, true, true, true, true, true, true }
    i = 0usize
    while i < 7usize {
        res.load_shed_observe(&s, samples[i])
        var p = 0usize
        while p < 4usize {
            if res.load_shed_admit(&s, p) != admits[i * 4usize + p] { os.exit(5i32) }
            p += 1usize
        }
        i += 1usize
    }

    // 6: bulkhead permits.
    let limits: [2]u32 = [2]u32{ 2u32, 0u32 }
    var used: [2]u32 = zero
    var bh = res.bulkhead(limits[..], used[..])
    if !res.bulkhead_acquire(&bh, 0usize) || !res.bulkhead_acquire(&bh, 0usize) { os.exit(6i32) }
    if res.bulkhead_acquire(&bh, 0usize) || res.bulkhead_available(&bh, 0usize) != 0u32 { os.exit(6i32) }
    res.bulkhead_release(&bh, 0usize)
    if res.bulkhead_available(&bh, 0usize) != 1u32 || !res.bulkhead_acquire(&bh, 0usize) { os.exit(6i32) }
    if res.bulkhead_acquire(&bh, 1usize) || res.bulkhead_acquire(&bh, 5usize) { os.exit(6i32) }
    res.bulkhead_release(&bh, 1usize)
    res.bulkhead_release(&bh, 5usize)
    if used[1usize] != 0u32 { os.exit(6i32) }

    // 7: health aggregation.
    var up: [3]bool = [3]bool{ true, true, true }
    let critical: [3]bool = [3]bool{ true, false, false }
    if res.health(up[..], critical[..]) != .Live { os.exit(7i32) }
    up[1usize] = false
    let degraded = res.health(up[..], critical[..])
    if degraded != .Degraded || !res.health_ready(degraded) || !res.health_live(degraded) { os.exit(7i32) }
    up[0usize] = false
    let not_ready = res.health(up[..], critical[..])
    if not_ready != .NotReady || res.health_ready(not_ready) || !res.health_live(not_ready) { os.exit(7i32) }
    up[2usize] = false
    let gone = res.health(up[..], critical[..])
    if gone != .Dead || res.health_ready(gone) || res.health_live(gone) { os.exit(7i32) }
    if res.health(up[..0usize], critical[..0usize]) != .Live { os.exit(7i32) }

    // 8: rollout buckets from Python FNV-1a.
    if res.rollout_bucket("user-1", "dark-mode") != 9058u32 { os.exit(8i32) }
    if res.rollout_bucket("user-2", "dark-mode") != 1439u32 { os.exit(8i32) }
    if res.rollout_bucket("", "") != 8253u32 { os.exit(8i32) }
    if res.rollout_bucket("alice", "beta") != 2209u32 { os.exit(8i32) }
    if res.rollout_bucket("user-1", "other") != 2780u32 { os.exit(8i32) }
    if res.rollout_enabled("user-2", "dark-mode", 1439u32) || !res.rollout_enabled("user-2", "dark-mode", 1440u32) { os.exit(8i32) }
    if !res.rollout_enabled("user-1", "dark-mode", 10000u32) || res.rollout_enabled("user-1", "dark-mode", 0u32) { os.exit(8i32) }

    try io.print("resilience ok\n")
    ret ok
}
