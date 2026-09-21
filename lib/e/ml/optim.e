// Parameter update rules over flat `f64` parameter and gradient vectors in
// caller storage, one step each: plain SGD, momentum, RMSprop, Adam and
// AdamW (decoupled weight decay), the cosine learning-rate schedule with
// warm restarts, and online gradient descent with a `1 / sqrt(t)` step.
// State vectors (velocity, cache, moments) are the caller's and start at
// zero.

use e.math

error TooSmall
error Invalid

fn sgd(parameters: []f64, gradient: []const f64, rate: f64) -> err {
    if gradient.len < parameters.len { ret TooSmall }
    var i = 0usize
    while i < parameters.len {
        parameters[i] -= rate * gradient[i]
        i += 1usize
    }
    ret ok
}

// `v = beta v + g; p -= rate v`.
fn momentum(parameters: []f64, gradient: []const f64, velocity: []f64, rate: f64, beta: f64) -> err {
    if gradient.len < parameters.len || velocity.len < parameters.len { ret TooSmall }
    var i = 0usize
    while i < parameters.len {
        velocity[i] = beta * velocity[i] + gradient[i]
        parameters[i] -= rate * velocity[i]
        i += 1usize
    }
    ret ok
}

// `c = decay c + (1 - decay) g²; p -= rate g / (sqrt(c) + epsilon)`.
fn rmsprop(parameters: []f64, gradient: []const f64, cache: []f64, rate: f64, decay: f64, epsilon: f64) -> err {
    if gradient.len < parameters.len || cache.len < parameters.len { ret TooSmall }
    var i = 0usize
    while i < parameters.len {
        cache[i] = decay * cache[i] + (1.0f64 - decay) * gradient[i] * gradient[i]
        parameters[i] -= rate * gradient[i] / (math.sqrt[f64](cache[i]) + epsilon)
        i += 1usize
    }
    ret ok
}

// Adam with bias correction at step `t` (from 1); AdamW when `weight_decay > 0`
// (the decay applied to the parameters directly, not through the gradient).
fn adamw(parameters: []f64, gradient: []const f64, first: []f64, second: []f64, t: u64, rate: f64, beta1: f64, beta2: f64, epsilon: f64, weight_decay: f64) -> err {
    if gradient.len < parameters.len || first.len < parameters.len || second.len < parameters.len { ret TooSmall }
    if t == 0u64 { ret Invalid }
    let correction1 = 1.0f64 - math.pow[f64](beta1, f64(t))
    let correction2 = 1.0f64 - math.pow[f64](beta2, f64(t))
    var i = 0usize
    while i < parameters.len {
        first[i] = beta1 * first[i] + (1.0f64 - beta1) * gradient[i]
        second[i] = beta2 * second[i] + (1.0f64 - beta2) * gradient[i] * gradient[i]
        let m = first[i] / correction1
        let v = second[i] / correction2
        parameters[i] -= rate * (m / (math.sqrt[f64](v) + epsilon) + weight_decay * parameters[i])
        i += 1usize
    }
    ret ok
}

fn adam(parameters: []f64, gradient: []const f64, first: []f64, second: []f64, t: u64, rate: f64, beta1: f64, beta2: f64, epsilon: f64) -> err {
    ret adamw(parameters, gradient, first, second, t, rate, beta1, beta2, epsilon, 0.0f64)
}

// The cosine schedule with warm restarts: within each `period` steps the
// rate falls from `base` to `minimum` along a half cosine, restarting at
// `base`.
fn cosine_schedule(base: f64, minimum: f64, step: u64, period: u64) -> f64 {
    if period == 0u64 { ret base }
    let phase = f64(step % period) / f64(period)
    ret minimum + 0.5f64 * (base - minimum) * (1.0f64 + math.cos[f64](3.141592653589793f64 * phase))
}

// Online gradient descent: the step at round `t` (from 1) is `base / sqrt(t)`;
// answers the rate used.
fn online_gd(parameters: []f64, gradient: []const f64, t: u64, base: f64) -> (f64, err) {
    if t == 0u64 { ret (0.0f64, Invalid) }
    let rate = base / math.sqrt[f64](f64(t))
    let step_error = sgd(parameters, gradient, rate)
    ret (rate, step_error)
}
