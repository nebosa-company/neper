// Monte Carlo estimation of `E[f(Z)]` over a standard normal `Z`, with the
// two classic variance reductions: antithetic variates average `f(z)` with
// `f(-z)`, and a control variate subtracts `beta (g(z) - E[g])` for a `g`
// whose mean the caller knows, with `beta` estimated from the same sample.
//
// Every estimator answers the mean and the standard error of that mean from
// `count` draws of the caller's PCG generator.

use e.algo.rand
use e.algo.rand.dist
use e.math

type Estimate = struct { mean: f64, standard_error: f64, count: usize }
error Invalid

// The plain estimator.
fn estimate[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, r: *rand.Pcg64, count: usize) -> (Estimate, err) {
    if count < 2usize { ret (zero, Invalid) }
    var sum = 0.0f64
    var sum2 = 0.0f64
    var i = 0usize
    while i < count {
        let v = f(ctx, dist.normal(r))
        sum += v
        sum2 += v * v
        i += 1usize
    }
    ret (finish(sum, sum2, count), ok)
}

// Antithetic variates: `count` pairs, each the average of `f(z)` and `f(-z)`.
fn antithetic[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, r: *rand.Pcg64, count: usize) -> (Estimate, err) {
    if count < 2usize { ret (zero, Invalid) }
    var sum = 0.0f64
    var sum2 = 0.0f64
    var i = 0usize
    while i < count {
        let z = dist.normal(r)
        let v = 0.5f64 * (f(ctx, z) + f(ctx, 0.0f64 - z))
        sum += v
        sum2 += v * v
        i += 1usize
    }
    ret (finish(sum, sum2, count), ok)
}

// A control variate `g` with known mean `g_mean`: the estimate is the mean of
// `f(z) - beta (g(z) - g_mean)` with `beta = cov(f, g) / var(g)` from the
// sample; `samples.len >= 2 * count` holds the paired draws meanwhile.
fn control_variate[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, g: fn(*Ctx, f64) -> f64, g_mean: f64, r: *rand.Pcg64, count: usize, samples: []f64) -> (Estimate, err) {
    if count < 2usize || samples.len < 2usize * count { ret (zero, Invalid) }
    var f_sum = 0.0f64
    var g_sum = 0.0f64
    var i = 0usize
    while i < count {
        let z = dist.normal(r)
        samples[2usize * i] = f(ctx, z)
        samples[2usize * i + 1usize] = g(ctx, z)
        f_sum += samples[2usize * i]
        g_sum += samples[2usize * i + 1usize]
        i += 1usize
    }
    let f_avg = f_sum / f64(count)
    let g_avg = g_sum / f64(count)
    var cov = 0.0f64
    var g_var = 0.0f64
    i = 0usize
    while i < count {
        let df = samples[2usize * i] - f_avg
        let dg = samples[2usize * i + 1usize] - g_avg
        cov += df * dg
        g_var += dg * dg
        i += 1usize
    }
    var beta = 0.0f64
    if g_var > 0.0f64 { beta = cov / g_var }
    var sum = 0.0f64
    var sum2 = 0.0f64
    i = 0usize
    while i < count {
        let v = samples[2usize * i] - beta * (samples[2usize * i + 1usize] - g_mean)
        sum += v
        sum2 += v * v
        i += 1usize
    }
    ret (finish(sum, sum2, count), ok)
}

fn finish(sum: f64, sum2: f64, count: usize) -> Estimate {
    let n = f64(count)
    let mean = sum / n
    var variance = (sum2 - n * mean * mean) / (n - 1.0f64)
    if variance < 0.0f64 { variance = 0.0f64 }
    ret Estimate { mean: mean, standard_error: math.sqrt[f64](variance / n), count: count }
}
