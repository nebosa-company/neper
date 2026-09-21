// Naive Bayes classifiers over row-major `f64` samples in caller storage,
// labels in `0..classes`: the Gaussian form fits a mean and variance per
// class and feature (a floor keeps a constant feature usable) and the
// multinomial form fits Laplace-smoothed feature log probabilities from
// count features; each predicts the class of the largest log posterior,
// ties to the smaller class.

use e.math

error TooSmall
error Invalid

// Fit `means`, `variances` (`classes × d`) and `priors` (`classes`);
// `scratch.len >= classes` counts. A class with no samples gets prior 0.
fn gaussian_fit(x: []const f64, labels: []const usize, n: usize, d: usize, classes: usize, means: []f64, variances: []f64, priors: []f64, scratch: []usize) -> err {
    if x.len < n * d || labels.len < n || means.len < classes * d || variances.len < classes * d || priors.len < classes || scratch.len < classes { ret TooSmall }
    if classes == 0usize || n == 0usize { ret Invalid }
    var counts = scratch[..classes]
    var c = 0usize
    while c < classes {
        counts[c] = 0usize
        var j = 0usize
        while j < d {
            means[c * d + j] = 0.0f64
            variances[c * d + j] = 0.0f64
            j += 1usize
        }
        c += 1usize
    }
    var i = 0usize
    while i < n {
        if labels[i] >= classes { ret Invalid }
        counts[labels[i]] += 1usize
        var j = 0usize
        while j < d {
            means[labels[i] * d + j] += x[i * d + j]
            j += 1usize
        }
        i += 1usize
    }
    c = 0usize
    while c < classes {
        priors[c] = f64(counts[c]) / f64(n)
        if counts[c] > 0usize {
            var j = 0usize
            while j < d {
                means[c * d + j] = means[c * d + j] / f64(counts[c])
                j += 1usize
            }
        }
        c += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            let t = x[i * d + j] - means[labels[i] * d + j]
            variances[labels[i] * d + j] += t * t
            j += 1usize
        }
        i += 1usize
    }
    c = 0usize
    while c < classes {
        if counts[c] > 0usize {
            var j = 0usize
            while j < d {
                variances[c * d + j] = math.max[f64](variances[c * d + j] / f64(counts[c]), 1.0e-9f64)
                j += 1usize
            }
        }
        c += 1usize
    }
    ret ok
}

// The log posterior (up to a constant) of `query` under class `c`.
fn gaussian_log_posterior(query: []const f64, d: usize, c: usize, means: []const f64, variances: []const f64, priors: []const f64) -> f64 {
    if priors[c] <= 0.0f64 { ret 0.0f64 - 1.0e300f64 }
    var s = math.log[f64](priors[c])
    var j = 0usize
    while j < d {
        let v = variances[c * d + j]
        let t = query[j] - means[c * d + j]
        s -= 0.5f64 * (math.log[f64](6.283185307179586f64 * v) + t * t / v)
        j += 1usize
    }
    ret s
}

fn gaussian_predict(query: []const f64, d: usize, classes: usize, means: []const f64, variances: []const f64, priors: []const f64) -> usize {
    var best = 0usize
    var best_score = gaussian_log_posterior(query, d, 0usize, means, variances, priors)
    var c = 1usize
    while c < classes {
        let s = gaussian_log_posterior(query, d, c, means, variances, priors)
        if s > best_score {
            best = c
            best_score = s
        }
        c += 1usize
    }
    ret best
}

// Multinomial fit from count features: `log_probability` (`classes × d`)
// receives `ln((count + alpha) / (total + alpha d))` per class and
// `log_prior` (`classes`) the class shares (`-1e300` for an empty class);
// `scratch.len >= classes`.
fn multinomial_fit(x: []const f64, labels: []const usize, n: usize, d: usize, classes: usize, alpha: f64, log_probability: []f64, log_prior: []f64, scratch: []usize) -> err {
    if x.len < n * d || labels.len < n || log_probability.len < classes * d || log_prior.len < classes || scratch.len < classes { ret TooSmall }
    if classes == 0usize || n == 0usize || alpha < 0.0f64 { ret Invalid }
    var counts = scratch[..classes]
    var c = 0usize
    while c < classes {
        counts[c] = 0usize
        var j = 0usize
        while j < d {
            log_probability[c * d + j] = 0.0f64
            j += 1usize
        }
        c += 1usize
    }
    var i = 0usize
    while i < n {
        if labels[i] >= classes { ret Invalid }
        counts[labels[i]] += 1usize
        var j = 0usize
        while j < d {
            log_probability[labels[i] * d + j] += x[i * d + j]
            j += 1usize
        }
        i += 1usize
    }
    c = 0usize
    while c < classes {
        if counts[c] == 0usize {
            log_prior[c] = 0.0f64 - 1.0e300f64
        } else {
            log_prior[c] = math.log[f64](f64(counts[c]) / f64(n))
        }
        var total = 0.0f64
        var j = 0usize
        while j < d {
            total += log_probability[c * d + j]
            j += 1usize
        }
        j = 0usize
        while j < d {
            log_probability[c * d + j] = math.log[f64]((log_probability[c * d + j] + alpha) / (total + alpha * f64(d)))
            j += 1usize
        }
        c += 1usize
    }
    ret ok
}

fn multinomial_predict(query: []const f64, d: usize, classes: usize, log_probability: []const f64, log_prior: []const f64) -> usize {
    var best = 0usize
    var best_score = 0.0f64
    var c = 0usize
    while c < classes {
        var s = log_prior[c]
        var j = 0usize
        while j < d {
            s += query[j] * log_probability[c * d + j]
            j += 1usize
        }
        if c == 0usize || s > best_score {
            best = c
            best_score = s
        }
        c += 1usize
    }
    ret best
}
