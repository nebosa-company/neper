// `e.algo.privacy`: ten Laplace samples and the Gaussian sigma match a Python
// replica of the same PCG64 to 1e-12; over 4000 draws the Laplace mean absolute
// noise sits within 5% of its scale and the Gaussian sample variance within 5% of
// sigma^2; the exponential mechanism picks the replica's index for eight seeds and
// its empirical frequencies land within 3 pp of the exact probabilities; randomized
// response debiases to the true fraction; the compositions match to 1e-12; and bad
// parameters are refused. Each check exits with its own code.

use e.algo.privacy
use e.algo.rand
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: ten Laplace samples, seed (1, 2), sensitivity 1, epsilon 0.5.
    let want10 = [10]f64{ -2.3346450135721475, -0.91345011296104084, 1.2298081126905058, -4.5826594211448564, 0.87408273092018174, 0.8691796706702829, -3.2428840708047888, -1.3965042033442572, -3.1923351739972574, 2.7992640338997199 }
    var r = rand.pcg64(1u64, 2u64)
    var i = 0usize
    while i < 10usize {
        let (x, e) = privacy.laplace(0.0f64, 1.0f64, 0.5f64, &r)
        if e != ok || !near(x, want10[i], 0.000000000001f64) { os.exit(1i32) }
        i += 1usize
    }

    // 2: the analytic Gaussian sigma.
    let (sigma, sigma_error) = privacy.gaussian_sigma(1.0f64, 0.5f64, 0.00001f64)
    if sigma_error != ok || !near(sigma, 9.689610525210778f64, 0.000000000001f64) { os.exit(2i32) }

    // 3: 4000 Laplace draws: mean |noise| within 5% of b = 2, and equal to the replica.
    r = rand.pcg64(3u64, 4u64)
    var sum_abs = 0.0f64
    i = 0usize
    while i < 4000usize {
        let (x, e) = privacy.laplace(0.0f64, 1.0f64, 0.5f64, &r)
        if e != ok { os.exit(3i32) }
        var m = x
        if m < 0.0f64 { m = 0.0f64 - m }
        sum_abs += m
        i += 1usize
    }
    let mean_abs = sum_abs / 4000.0f64
    if !near(mean_abs, 2.0f64, 0.1f64) || !near(mean_abs, 2.0159472077885687f64, 0.000000001f64) { os.exit(3i32) }

    // 4: 4000 Gaussian draws through laplace_vector's sibling: variance within 5% of sigma^2.
    r = rand.pcg64(5u64, 6u64)
    var draws: [4000]f64 = zero
    var sum = 0.0f64
    i = 0usize
    while i < 4000usize {
        let (x, e) = privacy.gaussian(0.0f64, 1.0f64, 0.5f64, 0.00001f64, &r)
        if e != ok { os.exit(4i32) }
        draws[i] = x
        sum += x
        i += 1usize
    }
    let mean = sum / 4000.0f64
    var sum2 = 0.0f64
    i = 0usize
    while i < 4000usize {
        let d = draws[i] - mean
        sum2 += d * d
        i += 1usize
    }
    let variance = sum2 / 4000.0f64
    let sigma2 = sigma * sigma
    if !near(variance, sigma2, 0.05f64 * sigma2) || !near(variance, 94.44504625283821f64, 0.000000001f64) { os.exit(4i32) }

    // 5: exponential mechanism picks for eight seeds (k, 11).
    let scores = [5]f64{ 3.0, 1.0, 4.0, 1.5, 2.0 }
    let picks = [8]usize{ 2usize, 0usize, 4usize, 2usize, 1usize, 2usize, 2usize, 0usize }
    var k = 1u64
    while k <= 8u64 {
        var rk = rand.pcg64(k, 11u64)
        let (pick, e) = privacy.exponential(scores[..], 1.0f64, 1.0f64, &rk)
        if e != ok || pick != picks[usize(k - 1u64)] { os.exit(5i32) }
        k += 1u64
    }

    // 6: empirical frequencies over 2000 draws within 3 pp of the exact probabilities.
    let probs = [5]f64{ 0.24417055471094196, 0.089825327217582407, 0.40256918723057938, 0.11533800320966899, 0.14809692763122728 }
    let want_counts = [5]usize{ 464usize, 211usize, 801usize, 245usize, 279usize }
    var counts: [5]usize = zero
    r = rand.pcg64(9u64, 10u64)
    i = 0usize
    while i < 2000usize {
        let (pick, e) = privacy.exponential(scores[..], 1.0f64, 1.0f64, &r)
        if e != ok { os.exit(6i32) }
        counts[pick] += 1usize
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        if counts[i] != want_counts[i] { os.exit(6i32) }
        if !near(f64(counts[i]) / 2000.0f64, probs[i], 0.03f64) { os.exit(6i32) }
        i += 1usize
    }

    // 7: randomized response over 4000 LCG bits (true fraction ~0.3), p = 0.75.
    var state = 12345u64
    var true_ones = 0usize
    var ones = 0usize
    r = rand.pcg64(7u64, 8u64)
    i = 0usize
    while i < 4000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let bit = (state >> 33u32) % 10u64 < 3u64
        if bit { true_ones += 1usize }
        if privacy.randomized_response(bit, 0.75f64, &r) { ones += 1usize }
        i += 1usize
    }
    let estimate = privacy.randomized_response_estimate(ones, 4000usize, 0.75f64)
    if ones != 1577usize || true_ones != 1183usize { os.exit(7i32) }
    if !near(estimate, 0.28849999999999998f64, 0.000000000001f64) || !near(estimate, f64(true_ones) / 4000.0f64, 0.05f64) { os.exit(7i32) }

    // 8: compositions, clip, laplace_vector, report_noisy_max.
    let budget = [4]f64{ 0.1, 0.2, 0.3, 0.4 }
    if !near(privacy.compose_basic(budget[..]), 1.0f64, 0.000000000001f64) { os.exit(8i32) }
    let (advanced, advanced_error) = privacy.compose_advanced(0.1f64, 100usize, 0.000001f64)
    if advanced_error != ok || !near(advanced, 6.3082309505134093f64, 0.000000000001f64) { os.exit(8i32) }
    if privacy.clip(5.0f64, 0.0f64, 1.0f64) != 1.0f64 || privacy.clip(-5.0f64, 0.0f64, 1.0f64) != 0.0f64 || privacy.clip(0.5f64, 0.0f64, 1.0f64) != 0.5f64 { os.exit(8i32) }
    var noisy: [5]f64 = zero
    r = rand.pcg64(1u64, 2u64)
    if privacy.laplace_vector(scores[..], 1.0f64, 0.5f64, &r, noisy[..]) != ok { os.exit(9i32) }
    i = 0usize
    while i < 5usize {
        if !near(noisy[i], scores[i] + want10[i], 0.000000000001f64) { os.exit(9i32) }
        i += 1usize
    }
    let (arg, arg_error) = privacy.report_noisy_max(scores[..], 1.0f64, 1000.0f64, &r)
    if arg_error != ok || arg != 2usize { os.exit(9i32) }

    // 10: refusals.
    let (_, bad_epsilon) = privacy.laplace(0.0f64, 1.0f64, 0.0f64, &r)
    if bad_epsilon != privacy.Invalid { os.exit(10i32) }
    let (_, bad_delta) = privacy.gaussian_sigma(1.0f64, 0.5f64, 1.0f64)
    if bad_delta != privacy.Invalid { os.exit(10i32) }
    let (_, bad_delta_low) = privacy.gaussian(0.0f64, 1.0f64, 0.5f64, 0.0f64, &r)
    if bad_delta_low != privacy.Invalid { os.exit(10i32) }
    let (_, bad_empty) = privacy.exponential(scores[..0usize], 1.0f64, 1.0f64, &r)
    if bad_empty != privacy.Invalid { os.exit(10i32) }
    let (_, bad_empty_max) = privacy.report_noisy_max(scores[..0usize], 1.0f64, 1.0f64, &r)
    if bad_empty_max != privacy.Invalid { os.exit(10i32) }
    if privacy.laplace_vector(scores[..], 1.0f64, 0.5f64, &r, noisy[..3usize]) != privacy.Invalid { os.exit(10i32) }
    let (_, bad_compose) = privacy.compose_advanced(0.1f64, 100usize, 0.0f64)
    if bad_compose != privacy.Invalid { os.exit(10i32) }

    try io.print("algo privacy ok\n")
    ret ok
}
