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

type MeanCtx = struct { unused: u8 }

fn sample_mean(ctx: *MeanCtx, values: []const f64) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        total += values[i]
        i += 1usize
    }
    ret total / f64(values.len)
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

    // 4: jackknife keeps the spread of leave-one-out statistics far from zero.
    var shifted: [5]f64 = zero
    var s = 0usize
    while s < 5usize {
        shifted[s] = 1000000000.0f64 + f64(s) * 0.1f64
        s += 1usize
    }
    var jk_scratch: [5]f64 = zero
    var mean_ctx = MeanCtx { unused: 0u8 }
    let (jk, jk_error) = stat.jackknife[MeanCtx](shifted[..], &mean_ctx, sample_mean, jk_scratch[..])
    if jk_error != ok || !near(jk.standard_error, 0.07071067811865476f64, 0.00000001f64) { os.exit(4i32) }
    // 5: EWMA lambda is bounded to (0, 1].
    var ewma_out: [3]stat.AttributeControlPoint = zero
    var ewma_values: [3]f64 = zero
    ewma_values[0usize] = 1.0f64
    ewma_values[1usize] = 2.0f64
    ewma_values[2usize] = 3.0f64
    if stat.ewma_control(ewma_values[..], 2.0f64, 1.0f64, 1.5f64, 3.0f64, ewma_out[..]) != stat.Invalid { os.exit(5i32) }
    if stat.ewma_control(ewma_values[..], 2.0f64, 1.0f64, 0.5f64, 3.0f64, ewma_out[..]) != ok { os.exit(5i32) }
    // 6: the Box-Cox profile is continuous at the log transform.
    var bc_values: [3]f64 = zero
    bc_values[0usize] = 1.0f64
    bc_values[1usize] = 2.0f64
    bc_values[2usize] = 4.0f64
    let (bc_zero, bc_zero_error) = stat.box_cox_llf(bc_values[..], 0.0f64)
    let (bc_tiny, bc_tiny_error) = stat.box_cox_llf(bc_values[..], 1.0e-12f64)
    if bc_zero_error != ok || bc_tiny_error != ok || !near(bc_tiny, bc_zero, 0.00000001f64) { os.exit(6i32) }
    // 7: populations past the documented bound refuse rather than lose their digits.
    let (huge_pmf, huge_pmf_error) = stat.hypergeometric_pmf(1000000000000000u64, 1u64, 1u64, 1u64)
    if huge_pmf_error != stat.Invalid { os.exit(7i32) }
    let (bound_pmf, bound_pmf_error) = stat.hypergeometric_pmf(1000000000u64, 1u64, 1u64, 1u64)
    if bound_pmf_error != ok || !near(bound_pmf, 1.0e-9f64, 1.0e-14f64) { os.exit(7i32) }
    // 8: a support wider than the term bound refuses instead of summing forever.
    let (wide_cdf, wide_cdf_error) = stat.hypergeometric_cdf(1000000000u64, 500000000u64, 500000000u64, 250000000u64)
    if wide_cdf_error != stat.Invalid { os.exit(8i32) }
    let (far_cdf, far_cdf_error) = stat.hypergeometric_cdf(4611686018427387904u64, 2305843009213693952u64, 2305843009213693952u64, 1152921504606846976u64)
    if far_cdf_error != stat.Invalid { os.exit(8i32) }
    // 9: a converged MLE is still reported converged.
    var mle_values: [5]f64 = zero
    mle_values[0usize] = 1.0f64
    mle_values[1usize] = 2.0f64
    mle_values[2usize] = 3.0f64
    mle_values[3usize] = 4.0f64
    mle_values[4usize] = 5.0f64
    let (gamma_fit, gamma_error) = stat.fit_mle(mle_values[..], .Gamma)
    if gamma_error != ok || !(gamma_fit.a > 0.0f64) { os.exit(9i32) }
    try io.print("algo stat hyper ok\n")
    ret ok
}
