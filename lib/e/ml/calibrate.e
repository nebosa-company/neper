// Probability calibration and its scores (L063): Platt's sigmoid fitted by
// Newton's method on scikit-learn's smoothed-target log loss, isotonic
// regression by pool-adjacent-violators with linear interpolation and clipping
// outside the data, the Brier score, the log loss, and reliability bins with
// the expected calibration error.
//
// Labels are 0 and 1 as `f64`; scores are any real number for the calibrators
// and probabilities for the metrics. Storage is the caller's.

use e.math

type Sigmoid = struct { a: f64, b: f64 }

error Invalid
error TooSmall

fn expit(z: f64) -> f64 {
    if z >= 0.0f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - z)) }
    let e = math.exp[f64](z)
    ret e / (1.0f64 + e)
}

// The calibrated probability `1 / (1 + exp(a score + b))`.
fn platt_apply(s: Sigmoid, score: f64) -> f64 { ret expit(0.0f64 - (s.a * score + s.b)) }

fn platt_loss(scores: []const f64, targets: []const f64, n: usize, a: f64, b: f64) -> f64 {
    var loss = 0.0f64
    var i = 0usize
    while i < n {
        let z = a * scores[i] + b
        // -T log P - (1 - T) log (1 - P) with P = expit(-z), stably.
        let log_p = 0.0f64 - softplus(z)
        let log_q = 0.0f64 - softplus(0.0f64 - z)
        loss -= targets[i] * log_p + (1.0f64 - targets[i]) * log_q
        i += 1usize
    }
    ret loss
}

fn softplus(z: f64) -> f64 {
    if z > 30.0f64 { ret z }
    if z < 0.0f64 - 30.0f64 { ret math.exp[f64](z) }
    ret math.log[f64](1.0f64 + math.exp[f64](z))
}

// Platt scaling as scikit-learn fits it: targets `(N+ + 1) / (N+ + 2)` for
// positives and `1 / (N- + 2)` for negatives, start `(0, ln((N- + 1)/(N+ + 1)))`,
// Newton steps with backtracking until the gradient's largest entry is under
// `tolerance`. `targets` wants `n` floats of scratch.
fn platt_fit(scores: []const f64, labels: []const f64, n: usize, tolerance: f64, max_iterations: u32, targets: []f64) -> (Sigmoid, err) {
    var fit: Sigmoid = zero
    if n < 2usize || scores.len < n || labels.len < n { ret (fit, Invalid) }
    if targets.len < n { ret (fit, TooSmall) }
    var positives = 0.0f64
    var negatives = 0.0f64
    var i = 0usize
    while i < n {
        if labels[i] > 0.0f64 { positives += 1.0f64 } else { negatives += 1.0f64 }
        i += 1usize
    }
    if positives == 0.0f64 || negatives == 0.0f64 { ret (fit, Invalid) }
    i = 0usize
    while i < n {
        if labels[i] > 0.0f64 { targets[i] = (positives + 1.0f64) / (positives + 2.0f64) } else { targets[i] = 1.0f64 / (negatives + 2.0f64) }
        i += 1usize
    }
    var a = 0.0f64
    var b = math.log[f64]((negatives + 1.0f64) / (positives + 1.0f64))
    var loss = platt_loss(scores, targets, n, a, b)
    var iteration = 0u32
    while iteration < max_iterations {
        var ga = 0.0f64
        var gb = 0.0f64
        var haa = 0.0f64
        var hab = 0.0f64
        var hbb = 0.0f64
        i = 0usize
        while i < n {
            let p = expit(0.0f64 - (a * scores[i] + b))
            let d = targets[i] - p
            let w = p * (1.0f64 - p)
            ga += scores[i] * d
            gb += d
            haa += scores[i] * scores[i] * w
            hab += scores[i] * w
            hbb += w
            i += 1usize
        }
        var biggest = math.abs[f64](ga)
        if math.abs[f64](gb) > biggest { biggest = math.abs[f64](gb) }
        if biggest < tolerance { break }
        // Solve H step = g (a tiny ridge keeps a flat Hessian invertible).
        let ridge = 1.0e-12f64 * (haa + hbb + 1.0f64)
        let det = (haa + ridge) * (hbb + ridge) - hab * hab
        let step_a = ((hbb + ridge) * ga - hab * gb) / det
        let step_b = ((haa + ridge) * gb - hab * ga) / det
        // (ga, gb) is the loss gradient, so the Newton move is minus the step.
        var t = 1.0f64
        var moved = false
        var trial = 0usize
        while trial < 30usize {
            let na = a - t * step_a
            let nb = b - t * step_b
            let nl = platt_loss(scores, targets, n, na, nb)
            if nl <= loss + 1.0e-14f64 * math.abs[f64](loss) {
                a = na
                b = nb
                loss = nl
                moved = true
                break
            }
            t = t * 0.5f64
            trial += 1usize
        }
        if !moved { break }
        iteration += 1u32
    }
    fit = Sigmoid { a: a, b: b }
    ret (fit, ok)
}

// Isotonic (non-decreasing) regression of `y` on `x`: ties in `x` are merged
// by weighted mean, then pool-adjacent-violators. The knots (`count` of them,
// answered) land in `knots_x` / `knots_y`; `order` wants `n` indices and
// `weight` `n` floats of scratch, and `knots_*` `n` floats each.
fn isotonic_fit(x: []const f64, y: []const f64, n: usize, order: []usize, weight: []f64, knots_x: []f64, knots_y: []f64) -> (usize, err) {
    if n == 0usize || x.len < n || y.len < n { ret (0usize, Invalid) }
    if order.len < n || weight.len < n || knots_x.len < n || knots_y.len < n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    var gap = n / 2usize
    while gap > 0usize {
        i = gap
        while i < n {
            let held = order[i]
            var j = i
            while j >= gap && x[order[j - gap]] > x[held] {
                order[j] = order[j - gap]
                j -= gap
            }
            order[j] = held
            i += 1usize
        }
        gap = gap / 2usize
    }
    // Unique x with weighted-mean y.
    var count = 0usize
    i = 0usize
    while i < n {
        let xv = x[order[i]]
        var sum = 0.0f64
        var c = 0usize
        while i < n && x[order[i]] == xv {
            sum += y[order[i]]
            c += 1usize
            i += 1usize
        }
        knots_x[count] = xv
        knots_y[count] = sum / f64(c)
        weight[count] = f64(c)
        count += 1usize
    }
    // Pool adjacent violators over blocks stored in place.
    var blocks = 0usize
    var k = 0usize
    while k < count {
        knots_y[blocks] = knots_y[k]
        weight[blocks] = weight[k]
        var size_of_block = 1usize
        // `order` doubles as block sizes.
        order[blocks] = size_of_block
        blocks += 1usize
        while blocks > 1usize && knots_y[blocks - 2usize] > knots_y[blocks - 1usize] {
            let w = weight[blocks - 2usize] + weight[blocks - 1usize]
            knots_y[blocks - 2usize] = (knots_y[blocks - 2usize] * weight[blocks - 2usize] + knots_y[blocks - 1usize] * weight[blocks - 1usize]) / w
            weight[blocks - 2usize] = w
            order[blocks - 2usize] += order[blocks - 1usize]
            blocks -= 1usize
        }
        k += 1usize
    }
    // Expand blocks back over the unique x, from the end so nothing is overwritten.
    var end = count
    var b = blocks
    while b > 0usize {
        b -= 1usize
        let v = knots_y[b]
        let size = order[b]
        var q = 0usize
        while q < size {
            end -= 1usize
            knots_y[end] = v
            q += 1usize
        }
    }
    ret (count, ok)
}

// The isotonic fit at `v`: linear between knots, flat beyond the ends.
fn isotonic_predict(knots_x: []const f64, knots_y: []const f64, count: usize, v: f64) -> f64 {
    if count == 0usize { ret 0.0f64 / 0.0f64 }
    if v <= knots_x[0usize] { ret knots_y[0usize] }
    if v >= knots_x[count - 1usize] { ret knots_y[count - 1usize] }
    var lo = 0usize
    var hi = count - 1usize
    while hi - lo > 1usize {
        let mid = lo + (hi - lo) / 2usize
        if knots_x[mid] <= v { lo = mid } else { hi = mid }
    }
    let t = (v - knots_x[lo]) / (knots_x[hi] - knots_x[lo])
    ret knots_y[lo] + t * (knots_y[hi] - knots_y[lo])
}

// Mean squared difference between probability and 0/1 label.
fn brier_score(prob: []const f64, labels: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < prob.len {
        sum += (prob[i] - labels[i]) * (prob[i] - labels[i])
        i += 1usize
    }
    ret sum / f64(prob.len)
}

// Mean negative log-likelihood, probabilities clipped to `[eps, 1 - eps]`.
fn log_loss(prob: []const f64, labels: []const f64, eps: f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < prob.len {
        var p = prob[i]
        if p < eps { p = eps }
        if p > 1.0f64 - eps { p = 1.0f64 - eps }
        if labels[i] > 0.0f64 { sum -= math.log[f64](p) } else { sum -= math.log[f64](1.0f64 - p) }
        i += 1usize
    }
    ret sum / f64(prob.len)
}

// Reliability bins over `[0, 1]` of equal width (scikit-learn's `uniform`
// strategy): per bin the count, the mean predicted probability and the
// fraction of positives (both 0 for an empty bin).
fn reliability(prob: []const f64, labels: []const f64, bins: usize, count: []usize, mean_predicted: []f64, fraction_positive: []f64) -> err {
    if bins < 1usize || prob.len == 0usize || labels.len < prob.len { ret Invalid }
    if count.len < bins || mean_predicted.len < bins || fraction_positive.len < bins { ret TooSmall }
    var b = 0usize
    while b < bins {
        count[b] = 0usize
        mean_predicted[b] = 0.0f64
        fraction_positive[b] = 0.0f64
        b += 1usize
    }
    let width = (1.0f64 + 1.0e-8f64) / f64(bins)
    var i = 0usize
    while i < prob.len {
        // The number of inner edges strictly below the probability.
        var id = 0usize
        var e = 1usize
        while e < bins {
            if f64(e) * width < prob[i] { id += 1usize }
            e += 1usize
        }
        count[id] += 1usize
        mean_predicted[id] += prob[i]
        if labels[i] > 0.0f64 { fraction_positive[id] += 1.0f64 }
        i += 1usize
    }
    b = 0usize
    while b < bins {
        if count[b] > 0usize {
            mean_predicted[b] = mean_predicted[b] / f64(count[b])
            fraction_positive[b] = fraction_positive[b] / f64(count[b])
        }
        b += 1usize
    }
    ret ok
}

// Expected calibration error: the count-weighted mean gap between the
// fraction of positives and the mean predicted probability per bin.
fn expected_calibration_error(count: []const usize, mean_predicted: []const f64, fraction_positive: []const f64, bins: usize) -> f64 {
    var total = 0usize
    var sum = 0.0f64
    var b = 0usize
    while b < bins {
        total += count[b]
        sum += f64(count[b]) * math.abs[f64](fraction_positive[b] - mean_predicted[b])
        b += 1usize
    }
    if total == 0usize { ret 0.0f64 }
    ret sum / f64(total)
}
