// Training losses over `f64` vectors in caller storage: `info_nce` (the
// contrastive loss of an anchor against candidates with one positive, dot
// products scaled by a temperature), `triplet` (the hinge on squared
// distances), `distillation_kl` (the KL divergence from a teacher's
// softened distribution to a student's, times the temperature squared)
// and `ctc` (the connectionist temporal classification negative log
// likelihood by the forward algorithm in log space).

use e.math

error TooSmall
error Invalid

fn dot(a: []const f64, b: []const f64, d: usize, i: usize, j: usize) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < d {
        s += a[i * d + k] * b[j * d + k]
        k += 1usize
    }
    ret s
}

fn log_sum_exp(values: []const f64, n: usize) -> f64 {
    var largest = values[0usize]
    var i = 1usize
    while i < n {
        if values[i] > largest { largest = values[i] }
        i += 1usize
    }
    var total = 0.0f64
    i = 0usize
    while i < n {
        total += math.exp[f64](values[i] - largest)
        i += 1usize
    }
    ret largest + math.log[f64](total)
}

// InfoNCE: `-log softmax(anchor·candidate_i / temperature)[positive]` over
// `count` candidates of `d` values each; `scratch.len >= count`.
fn info_nce(anchor: []const f64, candidates: []const f64, count: usize, d: usize, positive: usize, temperature: f64, scratch: []f64) -> (f64, err) {
    if anchor.len < d || candidates.len < count * d || scratch.len < count { ret (0.0f64, TooSmall) }
    if count == 0usize || positive >= count || temperature <= 0.0f64 { ret (0.0f64, Invalid) }
    var i = 0usize
    while i < count {
        scratch[i] = dot(anchor, candidates, d, 0usize, i) / temperature
        i += 1usize
    }
    ret (log_sum_exp(scratch, count) - scratch[positive], ok)
}

fn distance_squared(a: []const f64, b: []const f64, d: usize) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < d {
        let t = a[k] - b[k]
        s += t * t
        k += 1usize
    }
    ret s
}

// `max(0, |a - p|² - |a - n|² + margin)`.
fn triplet(anchor: []const f64, positive: []const f64, negative: []const f64, d: usize, margin: f64) -> (f64, err) {
    if anchor.len < d || positive.len < d || negative.len < d { ret (0.0f64, TooSmall) }
    let loss = distance_squared(anchor, positive, d) - distance_squared(anchor, negative, d) + margin
    if loss < 0.0f64 { ret (0.0f64, ok) }
    ret (loss, ok)
}

// `T² · KL(softmax(teacher / T) || softmax(student / T))` over `n` logits;
// `scratch.len >= 2 n`.
fn distillation_kl(teacher: []const f64, student: []const f64, n: usize, temperature: f64, scratch: []f64) -> (f64, err) {
    if teacher.len < n || student.len < n || scratch.len < 2usize * n { ret (0.0f64, TooSmall) }
    if n == 0usize || temperature <= 0.0f64 { ret (0.0f64, Invalid) }
    var t = scratch[..n]
    var s = scratch[n..2usize * n]
    var i = 0usize
    while i < n {
        t[i] = teacher[i] / temperature
        s[i] = student[i] / temperature
        i += 1usize
    }
    let zt = log_sum_exp(t, n)
    let zs = log_sum_exp(s, n)
    var kl = 0.0f64
    i = 0usize
    while i < n {
        let log_pt = t[i] - zt
        let log_ps = s[i] - zs
        kl += math.exp[f64](log_pt) * (log_pt - log_ps)
        i += 1usize
    }
    ret (temperature * temperature * kl, ok)
}

fn log_add(a: f64, b: f64) -> f64 {
    if a <= 0.0f64 - 1.0e300f64 { ret b }
    if b <= 0.0f64 - 1.0e300f64 { ret a }
    if a < b { ret b + math.log[f64](1.0f64 + math.exp[f64](a - b)) }
    ret a + math.log[f64](1.0f64 + math.exp[f64](b - a))
}

// CTC: `log_probabilities` is `frames × classes` row-major (log of each
// class per frame, `blank` among them) and `labels` the target sequence;
// the negative log likelihood of every alignment collapsing to the labels.
// `scratch.len >= 2 * (2 * labels.len + 1)`. `Invalid` when the labels
// cannot fit the frames.
fn ctc(log_probabilities: []const f64, frames: usize, classes: usize, blank: usize, labels: []const usize, scratch: []f64) -> (f64, err) {
    let l = labels.len
    let s = 2usize * l + 1usize
    if log_probabilities.len < frames * classes || scratch.len < 2usize * s { ret (0.0f64, TooSmall) }
    if blank >= classes || frames == 0usize { ret (0.0f64, Invalid) }
    var i = 0usize
    while i < l {
        if labels[i] >= classes || labels[i] == blank { ret (0.0f64, Invalid) }
        i += 1usize
    }
    let none = 0.0f64 - 1.0e300f64
    var previous = scratch[..s]
    var current = scratch[s..2usize * s]
    // Extended labels: blank, l1, blank, l2, ..., blank.
    i = 0usize
    while i < s {
        previous[i] = none
        i += 1usize
    }
    previous[0usize] = log_probabilities[blank]
    if l > 0usize { previous[1usize] = log_probabilities[labels[0usize]] }
    var t = 1usize
    while t < frames {
        i = 0usize
        while i < s {
            var symbol = blank
            if i % 2usize == 1usize { symbol = labels[i / 2usize] }
            var total = previous[i]
            if i >= 1usize { total = log_add(total, previous[i - 1usize]) }
            // A skip over the blank between two different labels.
            if i >= 2usize && symbol != blank && labels[i / 2usize] != labels[i / 2usize - 1usize] { total = log_add(total, previous[i - 2usize]) }
            if total <= none {
                current[i] = none
            } else {
                current[i] = total + log_probabilities[t * classes + symbol]
            }
            i += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        t += 1usize
    }
    var likelihood = previous[s - 1usize]
    if s >= 2usize { likelihood = log_add(likelihood, previous[s - 2usize]) }
    if likelihood <= none { ret (0.0f64, Invalid) }
    ret (0.0f64 - likelihood, ok)
}

// `KL(p || q) = Σ p_i ln((p_i + epsilon) / (q_i + epsilon))` over `n`
// probabilities, or `KL(q || p)` when `reverse`; `epsilon >= 0` guards
// empty bins.
fn kl_divergence(p: []const f64, q: []const f64, n: usize, reverse: bool, epsilon: f64) -> (f64, err) {
    if p.len < n || q.len < n { ret (0.0f64, TooSmall) }
    if n == 0usize || epsilon < 0.0f64 { ret (0.0f64, Invalid) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        var a = p[i]
        var b = q[i]
        if reverse {
            a = q[i]
            b = p[i]
        }
        if a > 0.0f64 || epsilon > 0.0f64 { total += a * math.log[f64]((a + epsilon) / (b + epsilon)) }
        i += 1usize
    }
    ret (total, ok)
}

// Jensen-Shannon: `½ KL(p || m) + ½ KL(q || m)` with `m = ½ (p + q)`;
// `scratch.len >= n`.
fn js_divergence(p: []const f64, q: []const f64, n: usize, epsilon: f64, scratch: []f64) -> (f64, err) {
    if p.len < n || q.len < n || scratch.len < n { ret (0.0f64, TooSmall) }
    var m = scratch[..n]
    var i = 0usize
    while i < n {
        m[i] = 0.5f64 * (p[i] + q[i])
        i += 1usize
    }
    let (left, left_error) = kl_divergence(p, m, n, false, epsilon)
    if left_error != ok { ret (0.0f64, left_error) }
    let (right, right_error) = kl_divergence(q, m, n, false, epsilon)
    if right_error != ok { ret (0.0f64, right_error) }
    ret (0.5f64 * left + 0.5f64 * right, ok)
}
