// Differential privacy mechanisms: the Laplace and Gaussian mechanisms, the
// exponential mechanism and report-noisy-max over a score vector, Warner's
// randomized response with its debiasing estimate, and privacy-budget
// composition (basic sum and the Dwork-Rothblum-Vadhan advanced bound).
//
// Noise comes from the system CSPRNG (`os.random`) by default; every noise
// function has a `_seeded` sibling that draws from a caller `*rand.Pcg64`, so a
// run reproduces bit for bit. The Laplace variate is one uniform through the
// inverse CDF, the Gaussian is the polar method. Every parameter check refuses
// with `Invalid` rather than returning silently unprivate output.

use e.algo.rand
use e.algo.rand.dist
use e.math
use e.os

error Invalid

fn clip(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

// 8 system bytes into a little-endian u64.
fn random_u64() -> (u64, err) {
    var raw: [8]u8 = zero
    let e = os.random(raw[0..])
    if e != ok { ret (0u64, e) }
    var value = 0u64
    var i = 0usize
    while i < 8usize {
        value = value | (u64(raw[i]) << u32(i * 8usize))
        i += 1usize
    }
    ret (value, ok)
}

// A uniform in [0, 1) from the system CSPRNG: the top 53 bits over 2^53, the
// same spacing as `rand.pcg64_f64`.
fn random_uniform() -> (f64, err) {
    let (value, e) = random_u64()
    if e != ok { ret (0.0f64, e) }
    ret (f64(value >> 11u64) / 9007199254740992.0f64, ok)
}

// A uniform in (0, 1), redrawing a zero (the Laplace inverse CDF needs it).
fn random_uniform_open() -> (f64, err) {
    let (u, e) = random_uniform()
    if e != ok { ret (0.0f64, e) }
    var value = u
    while value == 0.0f64 {
        let (next, next_error) = random_uniform()
        if next_error != ok { ret (0.0f64, next_error) }
        value = next
    }
    ret (value, ok)
}

// A standard normal by Marsaglia's polar method over the system CSPRNG.
fn random_normal() -> (f64, err) {
    while true {
        let (u, ue) = random_uniform()
        if ue != ok { ret (0.0f64, ue) }
        let (v, ve) = random_uniform()
        if ve != ok { ret (0.0f64, ve) }
        let a = 2.0f64 * u - 1.0f64
        let b = 2.0f64 * v - 1.0f64
        let s = a * a + b * b
        if s > 0.0f64 && s < 1.0f64 {
            ret (a * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s) / s), ok)
        }
    }
    ret (0.0f64, ok)
}

// The Laplace inverse CDF at a uniform `u` in (0, 1):
// `-b * sign(u - 1/2) * ln(1 - 2|u - 1/2|)`.
fn laplace_from_uniform(b: f64, u: f64) -> f64 {
    let d = u - 0.5f64
    if d == 0.0f64 { ret 0.0f64 }
    var mag = d
    var sign = 1.0f64
    if d < 0.0f64 {
        mag = 0.0f64 - d
        sign = 0.0f64 - 1.0f64
    }
    ret 0.0f64 - b * sign * math.log[f64](1.0f64 - 2.0f64 * mag)
}

// A Laplace variate with scale `b` from the system CSPRNG.
fn laplace_noise(b: f64) -> (f64, err) {
    let (u, e) = random_uniform_open()
    if e != ok { ret (0.0f64, e) }
    ret (laplace_from_uniform(b, u), ok)
}

// The deterministic variant: one uniform from `r` through the inverse CDF.
fn laplace_noise_seeded(b: f64, r: *rand.Pcg64) -> f64 {
    ret laplace_from_uniform(b, dist.uniform_open(r))
}

// `value + Lap(sensitivity / epsilon)`: epsilon-differentially private.
fn laplace(value: f64, sensitivity: f64, epsilon: f64) -> (f64, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 { ret (0.0f64, Invalid) }
    let (noise, e) = laplace_noise(sensitivity / epsilon)
    if e != ok { ret (0.0f64, e) }
    ret (value + noise, ok)
}

// The deterministic variant for tests.
fn laplace_seeded(value: f64, sensitivity: f64, epsilon: f64, r: *rand.Pcg64) -> (f64, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 { ret (0.0f64, Invalid) }
    ret (value + laplace_noise_seeded(sensitivity / epsilon, r), ok)
}

// Independent Laplace noise on every entry; `sensitivity` is the L1 sensitivity
// of the whole vector. `out` as long as `values`.
fn laplace_vector(values: []const f64, sensitivity: f64, epsilon: f64, out: []f64) -> err {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || out.len != values.len { ret Invalid }
    let b = sensitivity / epsilon
    var i = 0usize
    while i < values.len {
        let (noise, e) = laplace_noise(b)
        if e != ok { ret e }
        out[i] = values[i] + noise
        i += 1usize
    }
    ret ok
}

// The deterministic variant for tests.
fn laplace_vector_seeded(values: []const f64, sensitivity: f64, epsilon: f64, r: *rand.Pcg64, out: []f64) -> err {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || out.len != values.len { ret Invalid }
    let b = sensitivity / epsilon
    var i = 0usize
    while i < values.len {
        out[i] = values[i] + laplace_noise_seeded(b, r)
        i += 1usize
    }
    ret ok
}

// The classic analytic bound: `sigma = sensitivity * sqrt(2 ln(1.25 / delta)) / epsilon`
// gives (epsilon, delta)-differential privacy for epsilon in (0, 1).
fn gaussian_sigma(sensitivity: f64, epsilon: f64, delta: f64) -> (f64, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || delta <= 0.0f64 || delta >= 1.0f64 { ret (0.0f64, Invalid) }
    ret (sensitivity * math.sqrt[f64](2.0f64 * math.log[f64](1.25f64 / delta)) / epsilon, ok)
}

// `value + N(0, sigma^2)` with `sigma` from `gaussian_sigma`.
fn gaussian(value: f64, sensitivity: f64, epsilon: f64, delta: f64) -> (f64, err) {
    let (sigma, e) = gaussian_sigma(sensitivity, epsilon, delta)
    if e != ok { ret (0.0f64, e) }
    let (noise, ne) = random_normal()
    if ne != ok { ret (0.0f64, ne) }
    ret (value + sigma * noise, ok)
}

// The deterministic variant for tests.
fn gaussian_seeded(value: f64, sensitivity: f64, epsilon: f64, delta: f64, r: *rand.Pcg64) -> (f64, err) {
    let (sigma, e) = gaussian_sigma(sensitivity, epsilon, delta)
    if e != ok { ret (0.0f64, e) }
    ret (value + sigma * dist.normal(r), ok)
}

// The exponential mechanism, sampled by inverse CDF from a uniform `draw` in
// [0, 1): the maximum score is subtracted so no weight overflows.
fn exponential_from_uniform(scores: []const f64, sensitivity: f64, epsilon: f64, draw: f64) -> usize {
    var top = scores[0usize]
    var i = 1usize
    while i < scores.len {
        if scores[i] > top { top = scores[i] }
        i += 1usize
    }
    let scale = epsilon / (2.0f64 * sensitivity)
    var total = 0.0f64
    i = 0usize
    while i < scores.len {
        total += math.exp[f64](scale * (scores[i] - top))
        i += 1usize
    }
    let u = draw * total
    var acc = 0.0f64
    i = 0usize
    while i < scores.len {
        acc += math.exp[f64](scale * (scores[i] - top))
        if u < acc { ret i }
        i += 1usize
    }
    ret scores.len - 1usize
}

// The exponential mechanism: index `i` with probability proportional to
// `exp(epsilon * scores[i] / (2 sensitivity))`.
fn exponential(scores: []const f64, sensitivity: f64, epsilon: f64) -> (usize, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || scores.len == 0usize { ret (0usize, Invalid) }
    let (draw, e) = random_uniform()
    if e != ok { ret (0usize, e) }
    ret (exponential_from_uniform(scores, sensitivity, epsilon, draw), ok)
}

// The deterministic variant for tests.
fn exponential_seeded(scores: []const f64, sensitivity: f64, epsilon: f64, r: *rand.Pcg64) -> (usize, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || scores.len == 0usize { ret (0usize, Invalid) }
    ret (exponential_from_uniform(scores, sensitivity, epsilon, rand.pcg64_f64(r)), ok)
}

// Report noisy max: `Lap(sensitivity / epsilon)` on every score, the argmax
// returned; epsilon-differentially private for scores of sensitivity `sensitivity`.
fn report_noisy_max(scores: []const f64, sensitivity: f64, epsilon: f64) -> (usize, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || scores.len == 0usize { ret (0usize, Invalid) }
    let b = sensitivity / epsilon
    let (first, e) = laplace_noise(b)
    if e != ok { ret (0usize, e) }
    var best = 0usize
    var best_value = scores[0usize] + first
    var i = 1usize
    while i < scores.len {
        let (noise, ne) = laplace_noise(b)
        if ne != ok { ret (0usize, ne) }
        let noisy = scores[i] + noise
        if noisy > best_value {
            best_value = noisy
            best = i
        }
        i += 1usize
    }
    ret (best, ok)
}

// The deterministic variant for tests.
fn report_noisy_max_seeded(scores: []const f64, sensitivity: f64, epsilon: f64, r: *rand.Pcg64) -> (usize, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || scores.len == 0usize { ret (0usize, Invalid) }
    let b = sensitivity / epsilon
    var best = 0usize
    var best_value = scores[0usize] + laplace_noise_seeded(b, r)
    var i = 1usize
    while i < scores.len {
        let noisy = scores[i] + laplace_noise_seeded(b, r)
        if noisy > best_value {
            best_value = noisy
            best = i
        }
        i += 1usize
    }
    ret (best, ok)
}

// Warner's randomized response: the truth with probability `p`, its negation
// otherwise; `ln(p / (1 - p))`-differentially private.
fn randomized_response(bit: bool, p: f64) -> (bool, err) {
    let (u, e) = random_uniform()
    if e != ok { ret (false, e) }
    if u < p { ret (bit, ok) }
    ret (!bit, ok)
}

// The deterministic variant for tests.
fn randomized_response_seeded(bit: bool, p: f64, r: *rand.Pcg64) -> bool {
    if rand.pcg64_f64(r) < p { ret bit }
    ret !bit
}

// The unbiased estimate of the true fraction of ones from `count_ones` responses
// out of `n` collected with `randomized_response(_, p)`.
fn randomized_response_estimate(count_ones: usize, n: usize, p: f64) -> f64 {
    ret (f64(count_ones) / f64(n) - (1.0f64 - p)) / (2.0f64 * p - 1.0f64)
}

// Basic composition: the budgets add.
fn compose_basic(epsilons: []const f64) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < epsilons.len {
        total += epsilons[i]
        i += 1usize
    }
    ret total
}

// Advanced composition (Dwork-Rothblum-Vadhan): `k` mechanisms each
// epsilon-differentially private are together
// `epsilon sqrt(2 k ln(1 / delta')) + k epsilon (e^epsilon - 1)`, delta'-private.
fn compose_advanced(epsilon: f64, k: usize, delta_prime: f64) -> (f64, err) {
    if epsilon <= 0.0f64 || delta_prime <= 0.0f64 || delta_prime >= 1.0f64 { ret (0.0f64, Invalid) }
    let kf = f64(k)
    let first = epsilon * math.sqrt[f64](2.0f64 * kf * math.log[f64](1.0f64 / delta_prime))
    ret (first + kf * epsilon * (math.exp[f64](epsilon) - 1.0f64), ok)
}
