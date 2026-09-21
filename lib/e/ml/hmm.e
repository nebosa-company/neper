// Hidden Markov models with discrete emissions in caller storage: `start`
// (`s` states), `transition` (`s × s`) and `emission` (`s × k` symbols) are
// row-major probabilities. `forward` answers the log likelihood of an
// observation sequence (scaled per step), `viterbi` the most probable state
// path, and `baum_welch` re-estimates the parameters from a sequence by one
// expectation-maximisation pass per call, answering the log likelihood
// before the update.

use e.math

error TooSmall
error Invalid

// The log likelihood of `observed`; `scratch.len >= 2 s`.
fn forward(start: []const f64, transition: []const f64, emission: []const f64, s: usize, k: usize, observed: []const usize, scratch: []f64) -> (f64, err) {
    if start.len < s || transition.len < s * s || emission.len < s * k || scratch.len < 2usize * s { ret (0.0f64, TooSmall) }
    if s == 0usize || k == 0usize { ret (0.0f64, Invalid) }
    var alpha = scratch[..s]
    var next = scratch[s..2usize * s]
    var log_likelihood = 0.0f64
    var t = 0usize
    while t < observed.len {
        let o = observed[t]
        if o >= k { ret (0.0f64, Invalid) }
        var total = 0.0f64
        var j = 0usize
        while j < s {
            var p = 0.0f64
            if t == 0usize {
                p = start[j]
            } else {
                var i = 0usize
                while i < s {
                    p += alpha[i] * transition[i * s + j]
                    i += 1usize
                }
            }
            next[j] = p * emission[j * k + o]
            total += next[j]
            j += 1usize
        }
        if total <= 0.0f64 { ret (0.0f64 - 1.0e300f64, ok) }
        j = 0usize
        while j < s {
            alpha[j] = next[j] / total
            j += 1usize
        }
        log_likelihood += math.log[f64](total)
        t += 1usize
    }
    ret (log_likelihood, ok)
}

// The most probable state path into `path` (one state per observation),
// and its log probability; `scratch.len >= 2 s`, `back.len >= s * observed.len`.
fn viterbi(start: []const f64, transition: []const f64, emission: []const f64, s: usize, k: usize, observed: []const usize, path: []usize, scratch: []f64, back: []usize) -> (f64, err) {
    let n = observed.len
    if start.len < s || transition.len < s * s || emission.len < s * k || path.len < n || scratch.len < 2usize * s || back.len < s * n { ret (0.0f64, TooSmall) }
    if s == 0usize || k == 0usize { ret (0.0f64, Invalid) }
    if n == 0usize { ret (0.0f64, ok) }
    let none = 0.0f64 - 1.0e300f64
    var score = scratch[..s]
    var next = scratch[s..2usize * s]
    var t = 0usize
    while t < n {
        let o = observed[t]
        if o >= k { ret (0.0f64, Invalid) }
        var j = 0usize
        while j < s {
            var best = none
            var from = 0usize
            if t == 0usize {
                if start[j] > 0.0f64 { best = math.log[f64](start[j]) }
            } else {
                var i = 0usize
                while i < s {
                    if score[i] > none && transition[i * s + j] > 0.0f64 {
                        let candidate = score[i] + math.log[f64](transition[i * s + j])
                        if candidate > best {
                            best = candidate
                            from = i
                        }
                    }
                    i += 1usize
                }
            }
            if best > none && emission[j * k + o] > 0.0f64 {
                next[j] = best + math.log[f64](emission[j * k + o])
            } else {
                next[j] = none
            }
            back[t * s + j] = from
            j += 1usize
        }
        j = 0usize
        while j < s {
            score[j] = next[j]
            j += 1usize
        }
        t += 1usize
    }
    var last = 0usize
    var j = 1usize
    while j < s {
        if score[j] > score[last] { last = j }
        j += 1usize
    }
    if score[last] <= none { ret (none, Invalid) }
    t = n
    var state = last
    while t > 0usize {
        t -= 1usize
        path[t] = state
        state = back[t * s + state]
    }
    ret (score[last], ok)
}

// One Baum-Welch pass over `observed`: the scaled forward and backward
// variables (`alpha`, `beta`: `n × s` each) give the expected counts that
// replace `start`, `transition` and `emission` in place. Answers the log
// likelihood under the parameters before the update.
// `scratch.len >= 2 n s + 2 s + s * s + s * k`.
fn baum_welch(start: []f64, transition: []f64, emission: []f64, s: usize, k: usize, observed: []const usize, scratch: []f64) -> (f64, err) {
    let n = observed.len
    if start.len < s || transition.len < s * s || emission.len < s * k || scratch.len < 2usize * n * s + 2usize * s + s * s + s * k { ret (0.0f64, TooSmall) }
    if s == 0usize || k == 0usize || n == 0usize { ret (0.0f64, Invalid) }
    var alpha = scratch[..n * s]
    var beta = scratch[n * s..2usize * n * s]
    var at = 2usize * n * s
    var scale = scratch[at..at + s]
    at += s
    var gamma_sum = scratch[at..at + s]
    at += s
    var xi_sum = scratch[at..at + s * s]
    at += s * s
    var emit_sum = scratch[at..at + s * k]
    // Forward with per-step scaling (scale[t] would need n entries; we keep the
    // log likelihood and normalise alpha rows to sum to one).
    var log_likelihood = 0.0f64
    var t = 0usize
    while t < n {
        let o = observed[t]
        if o >= k { ret (0.0f64, Invalid) }
        var total = 0.0f64
        var j = 0usize
        while j < s {
            var p = 0.0f64
            if t == 0usize {
                p = start[j]
            } else {
                var i = 0usize
                while i < s {
                    p += alpha[(t - 1usize) * s + i] * transition[i * s + j]
                    i += 1usize
                }
            }
            alpha[t * s + j] = p * emission[j * k + o]
            total += alpha[t * s + j]
            j += 1usize
        }
        if total <= 0.0f64 { ret (0.0f64, Invalid) }
        j = 0usize
        while j < s {
            alpha[t * s + j] = alpha[t * s + j] / total
            j += 1usize
        }
        log_likelihood += math.log[f64](total)
        t += 1usize
    }
    // Backward, each row normalised to sum to one (the scaling cancels in the ratios).
    var j = 0usize
    while j < s {
        beta[(n - 1usize) * s + j] = 1.0f64 / f64(s)
        j += 1usize
    }
    t = n - 1usize
    while t > 0usize {
        t -= 1usize
        let o = observed[t + 1usize]
        var total = 0.0f64
        var i = 0usize
        while i < s {
            var p = 0.0f64
            j = 0usize
            while j < s {
                p += transition[i * s + j] * emission[j * k + o] * beta[(t + 1usize) * s + j]
                j += 1usize
            }
            beta[t * s + i] = p
            total += p
            i += 1usize
        }
        i = 0usize
        while i < s {
            beta[t * s + i] = beta[t * s + i] / total
            i += 1usize
        }
    }
    // Expected counts.
    j = 0usize
    while j < s * s {
        xi_sum[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < s * k {
        emit_sum[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < s {
        gamma_sum[j] = 0.0f64
        scale[j] = 0.0f64
        j += 1usize
    }
    t = 0usize
    while t < n {
        // gamma_t(i) ∝ alpha_t(i) beta_t(i).
        var total = 0.0f64
        var i = 0usize
        while i < s {
            scale[i] = alpha[t * s + i] * beta[t * s + i]
            total += scale[i]
            i += 1usize
        }
        i = 0usize
        while i < s {
            let g = scale[i] / total
            if t == 0usize { start[i] = g }
            emit_sum[i * k + observed[t]] += g
            if t + 1usize < n { gamma_sum[i] += g }
            i += 1usize
        }
        if t + 1usize < n {
            // xi_t(i, j) ∝ alpha_t(i) a_ij b_j(o_{t+1}) beta_{t+1}(j).
            let o = observed[t + 1usize]
            var xi_total = 0.0f64
            i = 0usize
            while i < s {
                j = 0usize
                while j < s {
                    xi_total += alpha[t * s + i] * transition[i * s + j] * emission[j * k + o] * beta[(t + 1usize) * s + j]
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < s {
                j = 0usize
                while j < s {
                    xi_sum[i * s + j] += alpha[t * s + i] * transition[i * s + j] * emission[j * k + o] * beta[(t + 1usize) * s + j] / xi_total
                    j += 1usize
                }
                i += 1usize
            }
        }
        t += 1usize
    }
    var i = 0usize
    while i < s {
        if gamma_sum[i] > 0.0f64 {
            j = 0usize
            while j < s {
                transition[i * s + j] = xi_sum[i * s + j] / gamma_sum[i]
                j += 1usize
            }
        }
        var occupancy = 0.0f64
        j = 0usize
        while j < k {
            occupancy += emit_sum[i * k + j]
            j += 1usize
        }
        if occupancy > 0.0f64 {
            j = 0usize
            while j < k {
                emission[i * k + j] = emit_sum[i * k + j] / occupancy
                j += 1usize
            }
        }
        i += 1usize
    }
    ret (log_likelihood, ok)
}
