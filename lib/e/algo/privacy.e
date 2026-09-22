// Differential privacy mechanisms: the Laplace and Gaussian mechanisms, the
// exponential mechanism and report-noisy-max over a score vector, Warner's
// randomized response with its debiasing estimate, and privacy-budget
// composition (basic sum and the Dwork-Rothblum-Vadhan advanced bound).
//
// Noise comes from a caller-owned `*rand.Pcg64`, so a run reproduces bit for bit:
// the Laplace variate is one uniform through the inverse CDF, the Gaussian is
// `dist.normal`. Every parameter check refuses with `Invalid` rather than
// returning silently unprivate output.

use e.algo.rand
use e.algo.rand.dist
use e.math

error Invalid

fn clip(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

// A Laplace variate with scale `b`: `-b * sign(u - 1/2) * ln(1 - 2|u - 1/2|)` from
// one uniform in (0, 1).
fn laplace_noise(b: f64, r: *rand.Pcg64) -> f64 {
    let d = dist.uniform_open(r) - 0.5f64
    if d == 0.0f64 { ret 0.0f64 }
    var mag = d
    var sign = 1.0f64
    if d < 0.0f64 {
        mag = 0.0f64 - d
        sign = 0.0f64 - 1.0f64
    }
    ret 0.0f64 - b * sign * math.log[f64](1.0f64 - 2.0f64 * mag)
}

// `value + Lap(sensitivity / epsilon)`: epsilon-differentially private.
fn laplace(value: f64, sensitivity: f64, epsilon: f64, r: *rand.Pcg64) -> (f64, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 { ret (0.0f64, Invalid) }
    ret (value + laplace_noise(sensitivity / epsilon, r), ok)
}

// Independent Laplace noise on every entry; `sensitivity` is the L1 sensitivity
// of the whole vector. `out` as long as `values`.
fn laplace_vector(values: []const f64, sensitivity: f64, epsilon: f64, r: *rand.Pcg64, out: []f64) -> err {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || out.len != values.len { ret Invalid }
    let b = sensitivity / epsilon
    var i = 0usize
    while i < values.len {
        out[i] = values[i] + laplace_noise(b, r)
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
fn gaussian(value: f64, sensitivity: f64, epsilon: f64, delta: f64, r: *rand.Pcg64) -> (f64, err) {
    let (sigma, e) = gaussian_sigma(sensitivity, epsilon, delta)
    if e != ok { ret (0.0f64, e) }
    ret (value + sigma * dist.normal(r), ok)
}

// The exponential mechanism: index `i` with probability proportional to
// `exp(epsilon * scores[i] / (2 sensitivity))`, computed with the maximum score
// subtracted so no weight overflows, and sampled by inverse CDF from one uniform.
fn exponential(scores: []const f64, sensitivity: f64, epsilon: f64, r: *rand.Pcg64) -> (usize, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || scores.len == 0usize { ret (0usize, Invalid) }
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
    let u = rand.pcg64_f64(r) * total
    var acc = 0.0f64
    i = 0usize
    while i < scores.len {
        acc += math.exp[f64](scale * (scores[i] - top))
        if u < acc { ret (i, ok) }
        i += 1usize
    }
    ret (scores.len - 1usize, ok)
}

// Report noisy max: `Lap(sensitivity / epsilon)` on every score, the argmax
// returned; epsilon-differentially private for scores of sensitivity `sensitivity`.
fn report_noisy_max(scores: []const f64, sensitivity: f64, epsilon: f64, r: *rand.Pcg64) -> (usize, err) {
    if epsilon <= 0.0f64 || sensitivity <= 0.0f64 || scores.len == 0usize { ret (0usize, Invalid) }
    let b = sensitivity / epsilon
    var best = 0usize
    var best_value = scores[0usize] + laplace_noise(b, r)
    var i = 1usize
    while i < scores.len {
        let noisy = scores[i] + laplace_noise(b, r)
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
fn randomized_response(bit: bool, p: f64, r: *rand.Pcg64) -> bool {
    if rand.pcg64_f64(r) < p { ret bit }
    ret !bit
}

// The unbiased estimate of the true fraction of ones from `count_ones` responses
// out of `n` collected with `randomized_response(_, p, _)`.
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
