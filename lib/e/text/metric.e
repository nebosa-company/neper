// Text similarity scores between a candidate and one reference, both as
// space-separated words compared byte for byte, in caller storage: `bleu`
// (clipped n-gram precisions up to `max_n`, geometric mean, brevity
// penalty; zero when any order has no match), `rouge_n` (n-gram recall,
// precision and F1), `rouge_l` (the same over the longest common word
// subsequence) and `meteor` restricted to exact matches (the harmonic mean
// weighted toward recall, times the fragmentation penalty). Word bounds and
// the LCS rows live in `scratch`, sized per declaration.

use e.math

type Rouge = struct { precision: f64, recall: f64, f1: f64 }
error TooSmall
error Invalid

fn split(text: str, bounds: []usize) -> (usize, err) {
    var count = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 32u8 {
            i += 1usize
        } else {
            let start = i
            while i < text.len && text[i] != 32u8 { i += 1usize }
            if 2usize * count + 1usize >= bounds.len { ret (count, TooSmall) }
            bounds[2usize * count] = start
            bounds[2usize * count + 1usize] = i
            count += 1usize
        }
    }
    ret (count, ok)
}

fn word_equal(a: str, ab: []const usize, i: usize, b: str, bb: []const usize, j: usize) -> bool {
    let x = a[ab[2usize * i]..ab[2usize * i + 1usize]]
    let y = b[bb[2usize * j]..bb[2usize * j + 1usize]]
    if x.len != y.len { ret false }
    var k = 0usize
    while k < x.len {
        if x[k] != y[k] { ret false }
        k += 1usize
    }
    ret true
}

fn gram_equal(a: str, ab: []const usize, i: usize, b: str, bb: []const usize, j: usize, n: usize) -> bool {
    var k = 0usize
    while k < n {
        if !word_equal(a, ab, i + k, b, bb, j + k) { ret false }
        k += 1usize
    }
    ret true
}

// The clipped count of `n`-gram matches: for each distinct candidate
// n-gram, the smaller of its candidate and reference counts.
fn clipped(c: str, cb: []const usize, cn: usize, r: str, rb: []const usize, rn: usize, n: usize) -> usize {
    var total = 0usize
    if cn < n { ret 0usize }
    var i = 0usize
    while i + n <= cn {
        var first = true
        var j = 0usize
        while j < i && first {
            if gram_equal(c, cb, j, c, cb, i, n) { first = false }
            j += 1usize
        }
        if first {
            var in_candidate = 0usize
            j = i
            while j + n <= cn {
                if gram_equal(c, cb, j, c, cb, i, n) { in_candidate += 1usize }
                j += 1usize
            }
            var in_reference = 0usize
            j = 0usize
            while j + n <= rn {
                if gram_equal(r, rb, j, c, cb, i, n) { in_reference += 1usize }
                j += 1usize
            }
            if in_reference < in_candidate { total += in_reference } else { total += in_candidate }
        }
        i += 1usize
    }
    ret total
}

fn bounds_of(candidate: str, reference: str, scratch: []usize) -> (usize, usize, err) {
    let (cn, c_error) = split(candidate, scratch)
    if c_error != ok { ret (0usize, 0usize, c_error) }
    let (rn, r_error) = split(reference, scratch[2usize * cn..])
    if r_error != ok { ret (0usize, 0usize, r_error) }
    ret (cn, rn, ok)
}

// BLEU with uniform weights over orders 1..`max_n`;
// `scratch.len >= 2 * (candidate words + reference words)`.
fn bleu(candidate: str, reference: str, max_n: usize, scratch: []usize) -> (f64, err) {
    if max_n == 0usize { ret (0.0f64, Invalid) }
    let (cn, rn, split_error) = bounds_of(candidate, reference, scratch)
    if split_error != ok { ret (0.0f64, split_error) }
    if cn == 0usize || rn == 0usize { ret (0.0f64, ok) }
    let cb = scratch[..2usize * cn]
    let rb = scratch[2usize * cn..2usize * (cn + rn)]
    var log_sum = 0.0f64
    var n = 1usize
    while n <= max_n {
        if cn < n { ret (0.0f64, ok) }
        let matched = clipped(candidate, cb, cn, reference, rb, rn, n)
        if matched == 0usize { ret (0.0f64, ok) }
        log_sum += math.log[f64](f64(matched) / f64(cn + 1usize - n))
        n += 1usize
    }
    var penalty = 1.0f64
    if cn < rn { penalty = math.exp[f64](1.0f64 - f64(rn) / f64(cn)) }
    ret (penalty * math.exp[f64](log_sum / f64(max_n)), ok)
}

fn rouge_of(matched: usize, candidate_count: usize, reference_count: usize) -> Rouge {
    var precision = 0.0f64
    var recall = 0.0f64
    if candidate_count > 0usize { precision = f64(matched) / f64(candidate_count) }
    if reference_count > 0usize { recall = f64(matched) / f64(reference_count) }
    var f1 = 0.0f64
    if precision + recall > 0.0f64 { f1 = 2.0f64 * precision * recall / (precision + recall) }
    ret Rouge { precision: precision, recall: recall, f1: f1 }
}

// ROUGE-N; `scratch.len >= 2 * (candidate words + reference words)`.
fn rouge_n(candidate: str, reference: str, n: usize, scratch: []usize) -> (Rouge, err) {
    if n == 0usize { ret (zero, Invalid) }
    let (cn, rn, split_error) = bounds_of(candidate, reference, scratch)
    if split_error != ok { ret (zero, split_error) }
    let cb = scratch[..2usize * cn]
    let rb = scratch[2usize * cn..2usize * (cn + rn)]
    let matched = clipped(candidate, cb, cn, reference, rb, rn, n)
    var candidate_grams = 0usize
    if cn >= n { candidate_grams = cn + 1usize - n }
    var reference_grams = 0usize
    if rn >= n { reference_grams = rn + 1usize - n }
    ret (rouge_of(matched, candidate_grams, reference_grams), ok)
}

// ROUGE-L over the longest common subsequence of words;
// `scratch.len >= 2 * (candidate words + reference words) + 2 * (reference words + 1)`.
fn rouge_l(candidate: str, reference: str, scratch: []usize) -> (Rouge, err) {
    let (cn, rn, split_error) = bounds_of(candidate, reference, scratch)
    if split_error != ok { ret (zero, split_error) }
    let at = 2usize * (cn + rn)
    if scratch.len < at + 2usize * (rn + 1usize) { ret (zero, TooSmall) }
    let cb = scratch[..2usize * cn]
    let rb = scratch[2usize * cn..at]
    var previous = scratch[at..at + rn + 1usize]
    var current = scratch[at + rn + 1usize..at + 2usize * (rn + 1usize)]
    var j = 0usize
    while j <= rn {
        previous[j] = 0usize
        j += 1usize
    }
    var i = 0usize
    while i < cn {
        current[0usize] = 0usize
        j = 0usize
        while j < rn {
            if word_equal(candidate, cb, i, reference, rb, j) {
                current[j + 1usize] = previous[j] + 1usize
            } else if previous[j + 1usize] > current[j] {
                current[j + 1usize] = previous[j + 1usize]
            } else {
                current[j + 1usize] = current[j]
            }
            j += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        i += 1usize
    }
    ret (rouge_of(previous[rn], cn, rn), ok)
}

// METEOR over exact matches: each candidate word aligns to the first
// unmatched identical reference word, F = 10PR / (R + 9P), the penalty is
// 0.5 (chunks / matches)^3, and the score is F (1 - penalty);
// `scratch.len >= 2 * (candidate words + reference words) + reference words`.
fn meteor(candidate: str, reference: str, scratch: []usize) -> (f64, err) {
    let (cn, rn, split_error) = bounds_of(candidate, reference, scratch)
    if split_error != ok { ret (0.0f64, split_error) }
    let at = 2usize * (cn + rn)
    if scratch.len < at + rn { ret (0.0f64, TooSmall) }
    if cn == 0usize || rn == 0usize { ret (0.0f64, ok) }
    let cb = scratch[..2usize * cn]
    let rb = scratch[2usize * cn..at]
    // taken[j] = 1 + the candidate index aligned to reference word j, 0 when none.
    var taken = scratch[at..at + rn]
    var j = 0usize
    while j < rn {
        taken[j] = 0usize
        j += 1usize
    }
    var matches = 0usize
    var chunks = 0usize
    var previous_j = rn
    var in_chunk = false
    var i = 0usize
    while i < cn {
        var found = rn
        j = 0usize
        while j < rn && found == rn {
            if taken[j] == 0usize && word_equal(candidate, cb, i, reference, rb, j) { found = j }
            j += 1usize
        }
        if found == rn {
            in_chunk = false
        } else {
            taken[found] = i + 1usize
            matches += 1usize
            if !(in_chunk && previous_j + 1usize == found) { chunks += 1usize }
            in_chunk = true
            previous_j = found
        }
        i += 1usize
    }
    if matches == 0usize { ret (0.0f64, ok) }
    let precision = f64(matches) / f64(cn)
    let recall = f64(matches) / f64(rn)
    let mean = 10.0f64 * precision * recall / (recall + 9.0f64 * precision)
    let fragmentation = f64(chunks) / f64(matches)
    let penalty = 0.5f64 * fragmentation * fragmentation * fragmentation
    ret (mean * (1.0f64 - penalty), ok)
}
