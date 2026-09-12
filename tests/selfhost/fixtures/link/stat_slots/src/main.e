// `e.algo.stat` against closed-form answers, and `e.data.slot_map`'s keys: stale after
// removal, reused slots with a new generation, retirement at the last generation,
// and `clear` invalidating everything. Every check has its own exit code.
use e.os
use e.mem
use e.algo.stat as stat
use e.data.slot_map as slots

fn near(got: f64, want: f64) -> bool {
    var diff = got - want
    if diff < 0.0 { diff = 0.0 - diff }
    ret diff <= 0.000000001
}

fn statistics() {
    var m = stat.moments()
    let (_, none) = stat.variance_population(&m)
    if none { os.exit(10) }
    stat.moments_add(&m, 2.0)
    stat.moments_add(&m, 4.0)
    stat.moments_add(&m, 4.0)
    stat.moments_add(&m, 4.0)
    stat.moments_add(&m, 5.0)
    stat.moments_add(&m, 5.0)
    stat.moments_add(&m, 7.0)
    stat.moments_add(&m, 9.0)
    if m.count != 8u64 || !near(m.mean, 5.0) || m.min != 2.0 || m.max != 9.0 { os.exit(11) }
    let (vp, has_vp) = stat.variance_population(&m)
    if !has_vp || !near(vp, 4.0) { os.exit(12) }
    let (sp, has_sp) = stat.standard_deviation_population(&m)
    if !has_sp || !near(sp, 2.0) { os.exit(13) }
    let (vs, has_vs) = stat.variance_sample(&m)
    if !has_vs || !near(vs, 32.0 / 7.0) { os.exit(14) }
    // Merging two halves gives the whole's moments.
    var left = stat.moments()
    var right = stat.moments()
    stat.moments_add(&left, 2.0)
    stat.moments_add(&left, 4.0)
    stat.moments_add(&left, 4.0)
    stat.moments_add(&right, 4.0)
    stat.moments_add(&right, 5.0)
    stat.moments_add(&right, 5.0)
    stat.moments_add(&right, 7.0)
    stat.moments_add(&right, 9.0)
    stat.moments_merge(&left, &right)
    let (merged, _) = stat.variance_population(&left)
    if left.count != 8u64 || !near(left.mean, 5.0) || !near(merged, 4.0) || left.min != 2.0 || left.max != 9.0 { os.exit(15) }
    var one = stat.moments()
    stat.moments_add(&one, 3.0)
    let (_, sample_of_one) = stat.variance_sample(&one)
    if sample_of_one { os.exit(16) }
    // y = 2x + 1 exactly: slope 2, intercept 1, correlation 1.
    var r = stat.regression()
    let (_, no_slope) = stat.regression_slope(&r)
    if no_slope { os.exit(17) }
    stat.regression_add(&r, 1.0, 3.0)
    stat.regression_add(&r, 2.0, 5.0)
    stat.regression_add(&r, 3.0, 7.0)
    stat.regression_add(&r, 4.0, 9.0)
    let (slope, has_slope) = stat.regression_slope(&r)
    let (intercept, has_intercept) = stat.regression_intercept(&r)
    let (rho, has_rho) = stat.correlation(&r)
    if !has_slope || !near(slope, 2.0) || !has_intercept || !near(intercept, 1.0) || !has_rho || !near(rho, 1.0) { os.exit(18) }
    // A negative relation, not exact: x = 1..4, y = 4, 3, 3, 1 -> slope -0.9, intercept 5.
    var d = stat.regression()
    stat.regression_add(&d, 1.0, 4.0)
    stat.regression_add(&d, 2.0, 3.0)
    stat.regression_add(&d, 3.0, 3.0)
    stat.regression_add(&d, 4.0, 1.0)
    let (down, _) = stat.regression_slope(&d)
    let (up, _) = stat.regression_intercept(&d)
    let (anti, _) = stat.correlation(&d)
    if !near(down, -0.9) || !near(up, 5.0) || anti >= 0.0 || anti < -1.0 { os.exit(19) }
    // No spread in x: no line.
    var flat = stat.regression()
    stat.regression_add(&flat, 1.0, 1.0)
    stat.regression_add(&flat, 1.0, 2.0)
    let (_, has_flat) = stat.regression_slope(&flat)
    if has_flat { os.exit(20) }
}

fn slot_maps(a: *mem.Arena) {
    let (initial, init_error) = slots.init[i64](a, 3usize)
    if init_error != ok { os.exit(30) }
    var m = initial
    if slots.len[i64](&m) != 0usize || slots.capacity[i64](&m) != 3usize { os.exit(31) }
    let (k1, e1) = slots.insert[i64](&m, 100i64)
    let (k2, e2) = slots.insert[i64](&m, 200i64)
    let (k3, e3) = slots.insert[i64](&m, 300i64)
    if e1 != ok || e2 != ok || e3 != ok || slots.len[i64](&m) != 3usize { os.exit(32) }
    let (_, full) = slots.insert[i64](&m, 400i64)
    if full != slots.Full { os.exit(33) }
    let (p2, has_p2) = slots.get[i64](&m, k2)
    if !has_p2 || *p2 != 200i64 { os.exit(34) }
    let (w2, has_w2) = slots.get_mut[i64](&m, k2)
    if !has_w2 { os.exit(35) }
    *w2 = 250i64
    let (again, _) = slots.get[i64](&m, k2)
    if *again != 250i64 { os.exit(36) }
    let (removed, was_live) = slots.remove[i64](&m, k2)
    if !was_live || removed != 250i64 || slots.len[i64](&m) != 2usize { os.exit(37) }
    // The old key is stale now, and a second removal with it does nothing.
    let (_, stale) = slots.get[i64](&m, k2)
    let (_, removed_twice) = slots.remove[i64](&m, k2)
    if stale || removed_twice { os.exit(38) }
    // The slot is reused with the next generation; the new key is distinct.
    let (k4, e4) = slots.insert[i64](&m, 400i64)
    if e4 != ok || k4.slot != k2.slot || k4.generation != k2.generation + 1u32 { os.exit(39) }
    let (p4, has_p4) = slots.get[i64](&m, k4)
    let (_, still_stale) = slots.get[i64](&m, k2)
    if !has_p4 || *p4 != 400i64 || still_stale { os.exit(40) }
    // Iteration visits every live value with its key, in slot order.
    var it = slots.iter[i64](&m)
    var total = 0i64
    var visited = 0usize
    while true {
        let (key, value, has_value) = slots.iter_next[i64](&it)
        if !has_value { break }
        let (p, has_p) = slots.get[i64](&m, key)
        if !has_p || *p != value { os.exit(41) }
        total += value
        visited += 1usize
    }
    if visited != 3usize || total != 800i64 { os.exit(42) }
    // A slot at its last generation retires instead of coming back.
    let s = mem.cast[*slots.State[i64]](m.state)
    s.generations[usize(k1.slot)] = 4294967295u32
    let k1_last = slots.Key { slot: k1.slot, generation: 4294967295u32 }
    let (_, removed_last) = slots.remove[i64](&m, k1_last)
    if !removed_last || slots.len[i64](&m) != 2usize { os.exit(43) }
    let (k5, e5) = slots.insert[i64](&m, 500i64)
    if e5 != slots.Full { os.exit(44) }
    // clear invalidates every key and frees the unretired slots.
    slots.clear[i64](&m)
    let (_, after_clear) = slots.get[i64](&m, k4)
    if after_clear || slots.len[i64](&m) != 0usize { os.exit(45) }
    let (k6, e6) = slots.insert[i64](&m, 600i64)
    let (k7, e7) = slots.insert[i64](&m, 700i64)
    let (_, e8) = slots.insert[i64](&m, 800i64)
    if e6 != ok || e7 != ok || e8 != slots.Full || k6.slot == k1.slot || k7.slot == k1.slot { os.exit(46) }
    let (_, too_large) = slots.init[i64](a, 4294967295usize)
    if too_large != slots.TooLarge { os.exit(47) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    statistics()
    slot_maps(a)
    os.exit(0)
    ret ok
}
