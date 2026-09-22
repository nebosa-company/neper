// Decoding over logit vectors in caller storage: `softmax` with a
// temperature, `top_k` and `top_p` (nucleus) draws through the caller's
// PCG generator, `contrastive` decoding between an expert and an amateur,
// and `beam_search` over a caller's scoring step keeping the `width` best
// prefixes by total log probability.

use e.algo.rand
use e.math

error TooSmall
error Invalid

// `out[i] = exp(logits[i] / temp) / sum`.
fn softmax(logits: []const f64, temp: f64, out: []f64) -> err {
    let n = logits.len
    if out.len < n { ret TooSmall }
    if n == 0usize || temp <= 0.0f64 { ret Invalid }
    var largest = logits[0usize]
    var i = 1usize
    while i < n {
        if logits[i] > largest { largest = logits[i] }
        i += 1usize
    }
    var total = 0.0f64
    i = 0usize
    while i < n {
        out[i] = math.exp[f64]((logits[i] - largest) / temp)
        total += out[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = out[i] / total
        i += 1usize
    }
    ret ok
}

// Sort indices `order[..n]` by descending probability (insertion sort).
fn rank(probabilities: []const f64, order: []usize) {
    var i = 0usize
    while i < order.len {
        var k = i
        while k > 0usize && probabilities[order[k - 1usize]] < probabilities[i] {
            order[k] = order[k - 1usize]
            k -= 1usize
        }
        order[k] = i
        i += 1usize
    }
}

fn draw(probabilities: []const f64, order: []const usize, count: usize, r: *rand.Pcg64) -> usize {
    var total = 0.0f64
    var i = 0usize
    while i < count {
        total += probabilities[order[i]]
        i += 1usize
    }
    var u = rand.pcg64_f64(r) * total
    i = 0usize
    while i + 1usize < count {
        u -= probabilities[order[i]]
        if u <= 0.0f64 { ret order[i] }
        i += 1usize
    }
    ret order[count - 1usize]
}

// A draw among the `k` most probable tokens after `softmax` at `temperature`;
// `probabilities.len >= n`, `order.len >= n`.
fn top_k(logits: []const f64, temp: f64, k: usize, r: *rand.Pcg64, probabilities: []f64, order: []usize) -> (usize, err) {
    let n = logits.len
    if order.len < n { ret (0usize, TooSmall) }
    if k == 0usize || k > n { ret (0usize, Invalid) }
    let soft_error = softmax(logits, temp, probabilities)
    if soft_error != ok { ret (0usize, soft_error) }
    rank(probabilities, order[..n])
    ret (draw(probabilities, order, k, r), ok)
}

// Nucleus sampling: a draw among the most probable tokens whose probability
// first reaches `p`.
fn top_p(logits: []const f64, temp: f64, p: f64, r: *rand.Pcg64, probabilities: []f64, order: []usize) -> (usize, err) {
    let n = logits.len
    if order.len < n { ret (0usize, TooSmall) }
    if p <= 0.0f64 || p > 1.0f64 { ret (0usize, Invalid) }
    let soft_error = softmax(logits, temp, probabilities)
    if soft_error != ok { ret (0usize, soft_error) }
    rank(probabilities, order[..n])
    var count = 0usize
    var mass = 0.0f64
    while count < n && mass < p {
        mass += probabilities[order[count]]
        count += 1usize
    }
    ret (draw(probabilities, order, count, r), ok)
}

// Contrastive decoding: among the tokens whose expert probability is at
// least `alpha` times the largest, the one maximising
// `log p_expert - log p_amateur`; `scratch.len >= 2 n`.
fn contrastive(expert: []const f64, amateur: []const f64, alpha: f64, scratch: []f64) -> (usize, err) {
    let n = expert.len
    if amateur.len < n || scratch.len < 2usize * n { ret (0usize, TooSmall) }
    if n == 0usize || alpha <= 0.0f64 || alpha > 1.0f64 { ret (0usize, Invalid) }
    var pe = scratch[..n]
    var pa = scratch[n..2usize * n]
    let e1 = softmax(expert, 1.0f64, pe)
    if e1 != ok { ret (0usize, e1) }
    let e2 = softmax(amateur, 1.0f64, pa)
    if e2 != ok { ret (0usize, e2) }
    var largest = 0.0f64
    var i = 0usize
    while i < n {
        if pe[i] > largest { largest = pe[i] }
        i += 1usize
    }
    var best = n
    var best_score = 0.0f64
    i = 0usize
    while i < n {
        if pe[i] >= alpha * largest {
            let score = math.log[f64](pe[i]) - math.log[f64](pa[i])
            if best == n || score > best_score {
                best = i
                best_score = score
            }
        }
        i += 1usize
    }
    ret (best, ok)
}

// Beam search over `length` steps with vocabulary `n`: `score(ctx, prefix,
// logits)` fills the log probabilities of the next token after `prefix`.
// The `width` best prefixes by total log probability survive each step; the
// best final sequence goes to `out` (`length` tokens) and its score is
// answered. `tokens.len >= 2 * width * length`, `scores.len >= 2 * width + n`.
fn beam_search[Ctx: type](ctx: *Ctx, score: fn(*Ctx, []const usize, []f64), n: usize, width: usize, length: usize, out: []usize, tokens: []usize, scores: []f64) -> (f64, err) {
    if out.len < length || tokens.len < 2usize * width * length || scores.len < 2usize * width + n { ret (0.0f64, TooSmall) }
    if n == 0usize || width == 0usize || length == 0usize { ret (0.0f64, Invalid) }
    var beams = tokens[..width * length]
    var next = tokens[width * length..2usize * width * length]
    var beam_scores = scores[..width]
    var next_scores = scores[width..2usize * width]
    var logits = scores[2usize * width..2usize * width + n]
    var live = 1usize
    beam_scores[0usize] = 0.0f64
    var step = 0usize
    while step < length {
        // Every (beam, token) candidate is offered to the next set, kept sorted
        // by total score and capped at `width`.
        var count = 0usize
        var b = 0usize
        while b < live {
            score(ctx, beams[b * length..b * length + step], logits)
            var t = 0usize
            while t < n {
                let total = beam_scores[b] + logits[t]
                var at = 0usize
                while at < count && next_scores[at] >= total { at += 1usize }
                if at < width {
                    var m = count
                    if m == width { m = width - 1usize }
                    while m > at {
                        next_scores[m] = next_scores[m - 1usize]
                        var q = 0usize
                        while q <= step {
                            next[m * length + q] = next[(m - 1usize) * length + q]
                            q += 1usize
                        }
                        m -= 1usize
                    }
                    next_scores[at] = total
                    var q = 0usize
                    while q < step {
                        next[at * length + q] = beams[b * length + q]
                        q += 1usize
                    }
                    next[at * length + step] = t
                    if count < width { count += 1usize }
                }
                t += 1usize
            }
            b += 1usize
        }
        live = count
        b = 0usize
        while b < live {
            beam_scores[b] = next_scores[b]
            var q = 0usize
            while q <= step {
                beams[b * length + q] = next[b * length + q]
                q += 1usize
            }
            b += 1usize
        }
        step += 1usize
    }
    var q = 0usize
    while q < length {
        out[q] = beams[q]
        q += 1usize
    }
    ret (beam_scores[0usize], ok)
}

// Temperature scaling: `out[i] = logits[i] / t`.
fn temperature(logits: []const f64, t: f64, out: []f64) -> err {
    if out.len < logits.len { ret TooSmall }
    if t <= 0.0f64 { ret Invalid }
    var i = 0usize
    while i < logits.len {
        out[i] = logits[i] / t
        i += 1usize
    }
    ret ok
}

// A draw from `softmax(logits / t)` by inverse transform of one uniform
// from `r` in token order; `probabilities.len >= n`.
fn sample_temperature(r: *rand.Pcg64, logits: []const f64, t: f64, probabilities: []f64) -> (usize, err) {
    let n = logits.len
    let soft_error = softmax(logits, t, probabilities)
    if soft_error != ok { ret (0usize, soft_error) }
    var u = rand.pcg64_f64(r)
    var i = 0usize
    while i + 1usize < n {
        u -= probabilities[i]
        if u <= 0.0f64 { ret (i, ok) }
        i += 1usize
    }
    ret (n - 1usize, ok)
}
