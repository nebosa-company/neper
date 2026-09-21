// `e.algo.rand.dist` and the sampling added to `e.algo.rand`: sample moments
// of the normal, exponential, Poisson, binomial, gamma and beta variates land
// near their parameters over 20,000 draws; Dirichlet sums to one; a
// multivariate normal reproduces its covariance; inverse-transform and
// rejection sampling recover an exponential; the alias table and weighted
// reservoir follow their weights; a shuffle is a permutation and the reservoir
// is uniform; stratified, Latin hypercube, Halton and Sobol points sit where
// the definitions and SciPy put them. Each check exits with its own code.

use e.algo.rand
use e.algo.rand.dist
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

// The quantile of the exponential with rate 2: -ln(1 - u) / 2.
fn exponential_quantile(ctx: *Nothing, u: f64) -> f64 { ret 0.0f64 - ln(1.0f64 - u) / 2.0f64 }

// Natural logarithm by range reduction and the atanh series, so the fixture
// does not depend on `e.math` for its reference.
fn ln(x: f64) -> f64 {
    var v = x
    var scale = 0.0f64
    while v > 1.5f64 {
        v = v / 2.0f64
        scale += 0.6931471805599453f64
    }
    while v < 0.75f64 {
        v = v * 2.0f64
        scale -= 0.6931471805599453f64
    }
    let y = (v - 1.0f64) / (v + 1.0f64)
    var term = y
    var sum = 0.0f64
    var n = 1.0f64
    var i = 0usize
    while i < 60usize {
        sum += term / n
        term = term * y * y
        n += 2.0f64
        i += 1usize
    }
    ret scale + 2.0f64 * sum
}

fn exponential_density(ctx: *Nothing, x: f64) -> f64 {
    // 2 e^{-2x} on [0, 5] by the series for e^{-2x}, which cancels badly past that,
    // so the density is cut to zero there.
    if x > 5.0f64 { ret 0.0f64 }
    var term = 1.0f64
    var sum = 1.0f64
    var n = 1.0f64
    var i = 0usize
    while i < 80usize {
        term = term * (0.0f64 - 2.0f64 * x) / n
        sum += term
        n += 1.0f64
        i += 1usize
    }
    ret 2.0f64 * sum
}

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var r = rand.pcg64(42u64, 54u64)
    var nothing = Nothing { unused: 0u8 }
    let draws = 20000usize

    // 1: normal (both forms), exponential, Poisson, binomial, gamma, beta moments.
    var sum = 0.0f64
    var sum2 = 0.0f64
    var i = 0usize
    while i < draws {
        let x = dist.normal(&r)
        sum += x
        sum2 += x * x
        i += 1usize
    }
    var mean = sum / f64(draws)
    var variance = sum2 / f64(draws) - mean * mean
    if !near(mean, 0.0f64, 0.03f64) || !near(variance, 1.0f64, 0.05f64) { os.exit(1i32) }
    sum = 0.0f64
    sum2 = 0.0f64
    i = 0usize
    while i < draws / 2usize {
        let (x, y) = dist.normal_box_muller(&r)
        sum += x + y
        sum2 += x * x + y * y
        i += 1usize
    }
    mean = sum / f64(draws)
    variance = sum2 / f64(draws) - mean * mean
    if !near(mean, 0.0f64, 0.03f64) || !near(variance, 1.0f64, 0.05f64) { os.exit(1i32) }
    sum = 0.0f64
    i = 0usize
    while i < draws {
        let x = dist.exponential(&r, 2.0f64)
        if x < 0.0f64 { os.exit(1i32) }
        sum += x
        i += 1usize
    }
    if !near(sum / f64(draws), 0.5f64, 0.02f64) { os.exit(1i32) }
    sum = 0.0f64
    sum2 = 0.0f64
    i = 0usize
    while i < draws {
        let k = f64(dist.poisson(&r, 4.0f64))
        sum += k
        sum2 += k * k
        i += 1usize
    }
    mean = sum / f64(draws)
    variance = sum2 / f64(draws) - mean * mean
    if !near(mean, 4.0f64, 0.08f64) || !near(variance, 4.0f64, 0.3f64) { os.exit(1i32) }
    sum = 0.0f64
    i = 0usize
    while i < draws {
        sum += f64(dist.poisson(&r, 800.0f64))
        i += 1usize
    }
    if !near(sum / f64(draws), 800.0f64, 2.0f64) { os.exit(1i32) }
    sum = 0.0f64
    sum2 = 0.0f64
    i = 0usize
    while i < draws {
        let k = dist.binomial(&r, 20u64, 0.3f64)
        if k > 20u64 { os.exit(1i32) }
        sum += f64(k)
        sum2 += f64(k) * f64(k)
        i += 1usize
    }
    mean = sum / f64(draws)
    variance = sum2 / f64(draws) - mean * mean
    if !near(mean, 6.0f64, 0.08f64) || !near(variance, 4.2f64, 0.3f64) { os.exit(1i32) }
    sum = 0.0f64
    i = 0usize
    while i < draws {
        sum += f64(dist.binomial(&r, 1000u64, 0.5f64))
        i += 1usize
    }
    if !near(sum / f64(draws), 500.0f64, 1.0f64) { os.exit(1i32) }
    if dist.binomial(&r, 10u64, 1.0f64) != 10u64 || dist.binomial(&r, 10u64, 0.0f64) != 0u64 { os.exit(1i32) }
    sum = 0.0f64
    sum2 = 0.0f64
    i = 0usize
    while i < draws {
        let x = dist.gamma(&r, 3.0f64, 2.0f64)
        sum += x
        sum2 += x * x
        i += 1usize
    }
    mean = sum / f64(draws)
    variance = sum2 / f64(draws) - mean * mean
    // Shape 3, scale 2: mean 6, variance 12.
    if !near(mean, 6.0f64, 0.15f64) || !near(variance, 12.0f64, 1.2f64) { os.exit(1i32) }
    sum = 0.0f64
    i = 0usize
    while i < draws {
        sum += dist.gamma(&r, 0.5f64, 1.0f64)
        i += 1usize
    }
    if !near(sum / f64(draws), 0.5f64, 0.03f64) { os.exit(1i32) }
    sum = 0.0f64
    i = 0usize
    while i < draws {
        let x = dist.beta(&r, 2.0f64, 5.0f64)
        if x < 0.0f64 || x > 1.0f64 { os.exit(1i32) }
        sum += x
        i += 1usize
    }
    // Beta(2, 5) has mean 2/7.
    if !near(sum / f64(draws), 0.2857142857f64, 0.01f64) { os.exit(1i32) }

    // 2: Dirichlet and the multivariate normal.
    var alphas: [3]f64 = zero
    alphas[0usize] = 1.0f64
    alphas[1usize] = 2.0f64
    alphas[2usize] = 3.0f64
    var simplex: [3]f64 = zero
    var third = 0.0f64
    i = 0usize
    while i < draws {
        if dist.dirichlet(&r, alphas[..], simplex[..]) != ok { os.exit(2i32) }
        if !near(simplex[0usize] + simplex[1usize] + simplex[2usize], 1.0f64, 0.000000001f64) { os.exit(2i32) }
        third += simplex[2usize]
        i += 1usize
    }
    if !near(third / f64(draws), 0.5f64, 0.01f64) { os.exit(2i32) }
    if dist.dirichlet(&r, alphas[..], simplex[..2usize]) != dist.TooSmall { os.exit(2i32) }
    var covariance: [4]f64 = zero
    covariance[0usize] = 4.0f64
    covariance[1usize] = 1.2f64
    covariance[2usize] = 1.2f64
    covariance[3usize] = 1.0f64
    var factor: [4]f64 = zero
    if dist.cholesky(covariance[..], 2usize, factor[..]) != ok { os.exit(2i32) }
    if !near(factor[0usize], 2.0f64, 0.000000001f64) || !near(factor[2usize], 0.6f64, 0.000000001f64) || factor[1usize] != 0.0f64 { os.exit(2i32) }
    if !near(factor[3usize] * factor[3usize], 1.0f64 - 0.36f64, 0.000000001f64) { os.exit(2i32) }
    var means: [2]f64 = zero
    means[0usize] = 10.0f64
    means[1usize] = 0.0f64 - 3.0f64
    var sample: [2]f64 = zero
    var scratch: [2]f64 = zero
    var sx = 0.0f64
    var sy = 0.0f64
    var sxy = 0.0f64
    var sxx = 0.0f64
    i = 0usize
    while i < draws {
        if dist.multivariate_normal(&r, means[..], factor[..], 2usize, sample[..], scratch[..]) != ok { os.exit(2i32) }
        sx += sample[0usize]
        sy += sample[1usize]
        sxy += (sample[0usize] - 10.0f64) * (sample[1usize] + 3.0f64)
        sxx += (sample[0usize] - 10.0f64) * (sample[0usize] - 10.0f64)
        i += 1usize
    }
    if !near(sx / f64(draws), 10.0f64, 0.06f64) || !near(sy / f64(draws), 0.0f64 - 3.0f64, 0.03f64) { os.exit(2i32) }
    if !near(sxy / f64(draws), 1.2f64, 0.1f64) || !near(sxx / f64(draws), 4.0f64, 0.2f64) { os.exit(2i32) }
    var not_positive: [4]f64 = zero
    not_positive[0usize] = 1.0f64
    not_positive[1usize] = 2.0f64
    not_positive[2usize] = 2.0f64
    not_positive[3usize] = 1.0f64
    if dist.cholesky(not_positive[..], 2usize, factor[..]) != dist.Invalid { os.exit(2i32) }

    // 3: inverse transform and rejection recover the exponential with rate 2.
    sum = 0.0f64
    i = 0usize
    while i < draws {
        sum += dist.inverse_transform[Nothing](&r, &nothing, exponential_quantile)
        i += 1usize
    }
    if !near(sum / f64(draws), 0.5f64, 0.02f64) { os.exit(3i32) }
    sum = 0.0f64
    var accepted = 0usize
    i = 0usize
    while i < draws {
        let (x, got) = dist.rejection[Nothing](&r, 0.0f64, 5.0f64, 2.0f64, 100u32, &nothing, exponential_density)
        if got {
            sum += x
            accepted += 1usize
        }
        i += 1usize
    }
    if accepted < draws - 5usize || !near(sum / f64(accepted), 0.5f64, 0.02f64) { os.exit(3i32) }
    let (_, starved) = dist.rejection[Nothing](&r, 10.0f64, 20.0f64, 2.0f64, 5u32, &nothing, exponential_density)
    if starved { os.exit(3i32) }
    if !near(dist.importance_weight[Nothing](0.25f64, &nothing, exponential_density, exponential_density), 1.0f64, 0.000000001f64) { os.exit(3i32) }

    // 4: the alias table and the weighted reservoir follow their weights.
    var weights: [4]f64 = zero
    weights[0usize] = 1.0f64
    weights[1usize] = 2.0f64
    weights[2usize] = 3.0f64
    weights[3usize] = 4.0f64
    var probability: [4]f64 = zero
    var alias: [4]usize = zero
    var alias_scratch: [4]usize = zero
    let (table, table_error) = dist.alias_build(weights[..], probability[..], alias[..], alias_scratch[..])
    if table_error != ok { os.exit(4i32) }
    var counts: [4]usize = zero
    i = 0usize
    while i < draws {
        counts[dist.alias_sample(&table, &r)] += 1usize
        i += 1usize
    }
    var w = 0usize
    while w < 4usize {
        let want = f64(w + 1usize) / 10.0f64
        if !near(f64(counts[w]) / f64(draws), want, 0.015f64) { os.exit(4i32) }
        w += 1usize
    }
    var zero_weights: [2]f64 = zero
    let (_, bad_table) = dist.alias_build(zero_weights[..], probability[..], alias[..], alias_scratch[..])
    if bad_table != dist.Invalid { os.exit(4i32) }
    var picks: [1]u64 = zero
    var keys: [1]f64 = zero
    var heavy_wins = 0usize
    var round = 0usize
    while round < 2000usize {
        let (res, res_error) = dist.weighted_reservoir(picks[..], keys[..])
        if res_error != ok { os.exit(4i32) }
        var s = res
        dist.weighted_reservoir_offer(&s, &r, 1u64, 1.0f64)
        dist.weighted_reservoir_offer(&s, &r, 9u64, 9.0f64)
        dist.weighted_reservoir_offer(&s, &r, 0u64, 0.0f64)
        if s.count != 1usize { os.exit(4i32) }
        if picks[0usize] == 9u64 { heavy_wins += 1usize }
        round += 1usize
    }
    if heavy_wins < 1700usize || heavy_wins > 1900usize { os.exit(4i32) }

    // 5: shuffles are permutations and the reservoir is uniform.
    var items: [10]u64 = zero
    i = 0usize
    while i < 10usize {
        items[i] = u64(i)
        i += 1usize
    }
    rand.shuffle[u64](&r, items[..])
    var seen = 0u64
    i = 0usize
    while i < 10usize {
        seen = seen | (1u64 << items[i])
        i += 1usize
    }
    if seen != 1023u64 { os.exit(5i32) }
    i = 0usize
    while i < 10usize {
        items[i] = u64(i)
        i += 1usize
    }
    rand.cycle_permutation[u64](&r, items[..])
    // One cycle: following the permutation from 0 visits all ten before returning.
    var at = 0usize
    var steps = 0usize
    while true {
        at = usize(items[at])
        steps += 1usize
        if at == 0usize { break }
        if steps > 10usize { os.exit(5i32) }
    }
    if steps != 10usize { os.exit(5i32) }
    var hits: [100]usize = zero
    var storage: [5]u64 = zero
    round = 0usize
    while round < 4000usize {
        var res = rand.reservoir[u64](storage[..])
        var n = 0u64
        while n < 100u64 {
            rand.reservoir_offer[u64](&res, &r, n)
            n += 1u64
        }
        let taken = rand.reservoir_sample[u64](&res)
        if taken.len != 5usize { os.exit(5i32) }
        i = 0usize
        while i < 5usize {
            hits[usize(taken[i])] += 1usize
            i += 1usize
        }
        round += 1usize
    }
    // Each of the 100 items is expected 200 times.
    i = 0usize
    while i < 100usize {
        if hits[i] < 140usize || hits[i] > 260usize { os.exit(5i32) }
        i += 1usize
    }
    var partial = rand.reservoir[u64](storage[..])
    rand.reservoir_offer[u64](&partial, &r, 7u64)
    rand.reservoir_offer[u64](&partial, &r, 8u64)
    let two = rand.reservoir_sample[u64](&partial)
    if two.len != 2usize || two[0usize] != 7u64 || two[1usize] != 8u64 { os.exit(5i32) }

    // 6: stratified, Latin hypercube, Halton and Sobol.
    var strata: [10]f64 = zero
    dist.stratified(&r, strata[..])
    i = 0usize
    while i < 10usize {
        if strata[i] < f64(i) / 10.0f64 || strata[i] >= f64(i + 1usize) / 10.0f64 { os.exit(6i32) }
        i += 1usize
    }
    var cube: [30]f64 = zero
    var cube_scratch: [10]usize = zero
    if dist.latin_hypercube(&r, 10usize, 3usize, cube[..], cube_scratch[..]) != ok { os.exit(6i32) }
    var d = 0usize
    while d < 3usize {
        var filled = 0u64
        i = 0usize
        while i < 10usize {
            let v = cube[i * 3usize + d]
            if v < 0.0f64 || v >= 1.0f64 { os.exit(6i32) }
            filled = filled | (1u64 << u64(v * 10.0f64))
            i += 1usize
        }
        if filled != 1023u64 { os.exit(6i32) }
        d += 1usize
    }
    var point: [3]f64 = zero
    if dist.halton(1u64, point[..]) != ok || !near(point[0usize], 0.5f64, 0.000000000001f64) || !near(point[1usize], 0.3333333333333333f64, 0.000000000001f64) || !near(point[2usize], 0.2f64, 0.000000000001f64) { os.exit(6i32) }
    if dist.halton(3u64, point[..]) != ok || !near(point[0usize], 0.75f64, 0.000000000001f64) || !near(point[1usize], 0.1111111111111111f64, 0.000000000001f64) { os.exit(6i32) }
    var wide: [17]f64 = zero
    if dist.halton(1u64, wide[..]) != dist.Invalid { os.exit(6i32) }
    var sobol_point: [4]f64 = zero
    if dist.sobol(0u64, sobol_point[..]) != ok || sobol_point[0usize] != 0.0f64 || sobol_point[3usize] != 0.0f64 { os.exit(6i32) }
    if dist.sobol(1u64, sobol_point[..]) != ok || sobol_point[0usize] != 0.5f64 || sobol_point[1usize] != 0.5f64 || sobol_point[2usize] != 0.5f64 || sobol_point[3usize] != 0.5f64 { os.exit(6i32) }
    if dist.sobol(2u64, sobol_point[..]) != ok || sobol_point[0usize] != 0.75f64 || sobol_point[1usize] != 0.25f64 || sobol_point[2usize] != 0.25f64 || sobol_point[3usize] != 0.25f64 { os.exit(6i32) }
    if dist.sobol(4u64, sobol_point[..]) != ok || sobol_point[0usize] != 0.375f64 || sobol_point[1usize] != 0.375f64 || sobol_point[2usize] != 0.625f64 || sobol_point[3usize] != 0.875f64 { os.exit(6i32) }
    if dist.sobol(7u64, sobol_point[..]) != ok || sobol_point[0usize] != 0.125f64 || sobol_point[1usize] != 0.625f64 || sobol_point[2usize] != 0.375f64 || sobol_point[3usize] != 0.125f64 { os.exit(6i32) }
    var five: [5]f64 = zero
    if dist.sobol(1u64, five[..]) != dist.Invalid { os.exit(6i32) }

    try io.print("algo rand dist ok\n")
    ret ok
}
