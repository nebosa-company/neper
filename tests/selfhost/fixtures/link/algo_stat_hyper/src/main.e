// `e.algo.stat` hypergeometric: the PMF against exact integer arithmetic, the
// at-most and at-least tails against their complements, out-of-support zeros
// and inconsistent-population refusals. Each check exits with its own code.

use e.algo.stat
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: hearts in a poker hand -- N = 52, K = 13, n = 5.
    let (p0, e0) = stat.hypergeometric_pmf(52u64, 13u64, 5u64, 0u64)
    if e0 != ok || !near(p0, 0.221533613445f64, 0.000000001f64) { os.exit(1i32) }
    let (p2, e2) = stat.hypergeometric_pmf(52u64, 13u64, 5u64, 2u64)
    if e2 != ok || !near(p2, 0.274279711885f64, 0.000000001f64) { os.exit(1i32) }
    let (p5, e5) = stat.hypergeometric_pmf(52u64, 13u64, 5u64, 5u64)
    if e5 != ok || !near(p5, 0.000495198079f64, 0.000000001f64) { os.exit(1i32) }
    let (c2, c2_error) = stat.hypergeometric_cdf(52u64, 13u64, 5u64, 2u64)
    if c2_error != ok || !near(c2, 0.907232893157f64, 0.000000001f64) { os.exit(1i32) }
    let (s2, s2_error) = stat.hypergeometric_sf(52u64, 13u64, 5u64, 2u64)
    if s2_error != ok || !near(s2, 0.367046818727f64, 0.000000001f64) { os.exit(1i32) }

    // 2: the MTG opening hand -- N = 60, K = 20, n = 7.
    let (m3, m3_error) = stat.hypergeometric_pmf(60u64, 20u64, 7u64, 3u64)
    if m3_error != ok || !near(m3, 0.269763680050f64, 0.000000001f64) { os.exit(2i32) }
    let (mc, mc_error) = stat.hypergeometric_cdf(60u64, 20u64, 7u64, 3u64)
    if mc_error != ok || !near(mc, 0.840526834682f64, 0.000000001f64) { os.exit(2i32) }
    let (ms, ms_error) = stat.hypergeometric_sf(60u64, 20u64, 7u64, 3u64)
    if ms_error != ok || !near(ms, 0.429236845368f64, 0.000000001f64) { os.exit(2i32) }
    if !near(mc + ms - m3, 1.0f64, 0.000000001f64) { os.exit(2i32) }

    // 3: edges -- outside the support is zero, past the top is one, and an
    // inconsistent population refuses.
    let (past, past_error) = stat.hypergeometric_pmf(52u64, 13u64, 5u64, 6u64)
    if past_error != ok || past != 0.0f64 { os.exit(3i32) }
    let (whole, whole_error) = stat.hypergeometric_cdf(52u64, 13u64, 5u64, 9u64)
    if whole_error != ok || whole != 1.0f64 { os.exit(3i32) }
    let (all, all_error) = stat.hypergeometric_sf(52u64, 13u64, 5u64, 0u64)
    if all_error != ok || all != 1.0f64 { os.exit(3i32) }
    let (_, bad_pop) = stat.hypergeometric_pmf(52u64, 60u64, 5u64, 2u64)
    if bad_pop != stat.Invalid { os.exit(3i32) }
    let (_, bad_draw) = stat.hypergeometric_cdf(52u64, 13u64, 60u64, 2u64)
    if bad_draw != stat.Invalid { os.exit(3i32) }
    let (_, bad_sf) = stat.hypergeometric_sf(52u64, 60u64, 5u64, 2u64)
    if bad_sf != stat.Invalid { os.exit(3i32) }

    try io.print("algo stat hyper ok\n")
    ret ok
}
