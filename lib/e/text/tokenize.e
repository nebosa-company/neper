// Tokenisation over bytes in caller storage. `shingles` cuts a text into
// its `k`-byte windows and `word_shingles` into its `k`-word windows;
// `word_break` segments a text into dictionary words by dynamic
// programming; `bpe_train` learns byte-pair merges from a corpus of words in
// the caller's arena and `bpe_encode` applies them; `wordpiece` is the
// greedy longest-match-first segmentation over a vocabulary whose
// continuation pieces start with `##`; `unigram` is the Viterbi
// segmentation over a vocabulary with log probabilities and
// `unigram_sample` draws one segmentation by forward filtering and backward
// sampling, sharpened by a temperature.

use e.algo.rand
use e.math
use e.mem

type Bpe = struct { left: []str, right: []str, count: usize }
error TooSmall
error Invalid
error Unknown

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Every window of `k` bytes, in order (`text.len - k + 1` of them).
fn shingles(text: str, k: usize, out: []str) -> (usize, err) {
    if k == 0usize { ret (0usize, Invalid) }
    if text.len < k { ret (0usize, ok) }
    let count = text.len - k + 1usize
    if out.len < count { ret (0usize, TooSmall) }
    var i = 0usize
    while i < count {
        out[i] = text[i..i + k]
        i += 1usize
    }
    ret (count, ok)
}

// Every window of `k` consecutive words as the text from the first to the
// last; `scratch.len >= 2 * words`.
fn word_shingles(text: str, k: usize, out: []str, scratch: []usize) -> (usize, err) {
    if k == 0usize { ret (0usize, Invalid) }
    var words = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 32u8 {
            i += 1usize
        } else {
            let start = i
            while i < text.len && text[i] != 32u8 { i += 1usize }
            if 2usize * words + 1usize >= scratch.len { ret (0usize, TooSmall) }
            scratch[2usize * words] = start
            scratch[2usize * words + 1usize] = i
            words += 1usize
        }
    }
    if words < k { ret (0usize, ok) }
    let count = words - k + 1usize
    if out.len < count { ret (0usize, TooSmall) }
    i = 0usize
    while i < count {
        out[i] = text[scratch[2usize * i]..scratch[2usize * (i + k - 1usize) + 1usize]]
        i += 1usize
    }
    ret (count, ok)
}

// Segment `text` into words of `dictionary`, preferring the fewest words;
// `breaks` receives the end of each word, `scratch.len >= 2 * (text.len + 1)`.
// Answers the word count, or `Unknown` when no segmentation exists.
fn word_break(text: str, dictionary: []const str, breaks: []usize, scratch: []usize) -> (usize, err) {
    let n = text.len
    if scratch.len < 2usize * (n + 1usize) { ret (0usize, TooSmall) }
    var best = scratch[..n + 1usize]
    var from = scratch[n + 1usize..2usize * (n + 1usize)]
    let none = 0usize -% 1usize
    best[0usize] = 0usize
    var j = 1usize
    while j <= n {
        best[j] = none
        var d = 0usize
        while d < dictionary.len {
            let w = dictionary[d]
            if w.len > 0usize && w.len <= j && best[j - w.len] != none && same(text[j - w.len..j], w) {
                if best[j] == none || best[j - w.len] + 1usize < best[j] {
                    best[j] = best[j - w.len] + 1usize
                    from[j] = j - w.len
                }
            }
            d += 1usize
        }
        j += 1usize
    }
    if best[n] == none { ret (0usize, Unknown) }
    let count = best[n]
    if breaks.len < count { ret (0usize, TooSmall) }
    var k = count
    j = n
    while j > 0usize {
        k -= 1usize
        breaks[k] = j
        j = from[j]
    }
    ret (count, ok)
}

// Learn `merges` byte-pair merges from `corpus` (one entry per word
// occurrence): each round the most frequent adjacent token pair, ties to
// the earliest seen, becomes one token. Fewer merges are learned when no
// pair repeats.
// ponytail: pair counting is a quadratic scan over the current tokens; a
// hashed pair table is the upgrade for large corpora.
fn bpe_train(a: *mem.Arena, corpus: []const str, merges: usize) -> (Bpe, err) {
    var total = 0usize
    var w = 0usize
    while w < corpus.len {
        total += corpus[w].len
        w += 1usize
    }
    // Token spans: for word w, tokens are `starts[first[w]..first[w + 1]]` as
    // start offsets within the word, live count in `live[w]`.
    let (first, first_error) = mem.alloc[usize](a, corpus.len + 1usize)
    if first_error != ok { ret (zero, first_error) }
    let (starts, starts_error) = mem.alloc[usize](a, total)
    if starts_error != ok { ret (zero, starts_error) }
    let (live, live_error) = mem.alloc[usize](a, corpus.len)
    if live_error != ok { ret (zero, live_error) }
    let (left, left_error) = mem.alloc[str](a, merges)
    if left_error != ok { ret (zero, left_error) }
    let (right, right_error) = mem.alloc[str](a, merges)
    if right_error != ok { ret (zero, right_error) }
    var at = 0usize
    w = 0usize
    while w < corpus.len {
        first[w] = at
        var i = 0usize
        while i < corpus[w].len {
            starts[at] = i
            at += 1usize
            i += 1usize
        }
        live[w] = corpus[w].len
        w += 1usize
    }
    first[corpus.len] = at
    var learned = 0usize
    var searching = true
    while learned < merges && searching {
        // The most frequent pair: for each candidate pair (the first occurrence
        // of it decides its identity), count its occurrences everywhere.
        var best_count = 1usize
        var best_left = ""
        var best_right = ""
        w = 0usize
        while w < corpus.len {
            var t = 0usize
            while t + 1usize < live[w] {
                let (l, r) = pair_at(corpus[w], starts, first[w], live[w], t)
                if !seen_before(corpus, starts, first, live, w, t, l, r) {
                    let count = count_pair(corpus, starts, first, live, l, r)
                    if count > best_count {
                        best_count = count
                        best_left = l
                        best_right = r
                    }
                }
                t += 1usize
            }
            w += 1usize
        }
        if best_count < 2usize {
            searching = false
        } else {
            left[learned] = best_left
            right[learned] = best_right
            learned += 1usize
            // Apply the merge everywhere.
            w = 0usize
            while w < corpus.len {
                live[w] = merge_word(corpus[w], starts, first[w], live[w], best_left, best_right)
                w += 1usize
            }
        }
    }
    ret (Bpe { left: left[..learned], right: right[..learned], count: learned }, ok)
}

fn token_at(word: str, starts: []const usize, base: usize, live: usize, t: usize) -> str {
    var end = word.len
    if t + 1usize < live { end = starts[base + t + 1usize] }
    ret word[starts[base + t]..end]
}

fn pair_at(word: str, starts: []const usize, base: usize, live: usize, t: usize) -> (str, str) {
    ret (token_at(word, starts, base, live, t), token_at(word, starts, base, live, t + 1usize))
}

// Did the pair (l, r) occur before position t of word w, in any earlier word
// or earlier in this one?
fn seen_before(corpus: []const str, starts: []const usize, first: []const usize, live: []const usize, w: usize, t: usize, l: str, r: str) -> bool {
    var v = 0usize
    while v <= w {
        var u = 0usize
        var limit = live[v]
        if v == w { limit = t + 1usize }
        while u + 1usize < limit {
            let (a, b) = pair_at(corpus[v], starts, first[v], live[v], u)
            if same(a, l) && same(b, r) { ret true }
            u += 1usize
        }
        v += 1usize
    }
    ret false
}

fn count_pair(corpus: []const str, starts: []const usize, first: []const usize, live: []const usize, l: str, r: str) -> usize {
    var count = 0usize
    var w = 0usize
    while w < corpus.len {
        var t = 0usize
        while t + 1usize < live[w] {
            let (a, b) = pair_at(corpus[w], starts, first[w], live[w], t)
            if same(a, l) && same(b, r) {
                count += 1usize
                t += 2usize
            } else {
                t += 1usize
            }
        }
        w += 1usize
    }
    ret count
}

// Merge every adjacent (l, r) in word `w`'s tokens; answers the new count.
fn merge_word(word: str, starts: []usize, base: usize, live: usize, l: str, r: str) -> usize {
    var out = 0usize
    var t = 0usize
    while t < live {
        if t + 1usize < live {
            let (a, b) = pair_at(word, starts, base, live, t)
            if same(a, l) && same(b, r) {
                starts[base + out] = starts[base + t]
                out += 1usize
                t += 2usize
            } else {
                starts[base + out] = starts[base + t]
                out += 1usize
                t += 1usize
            }
        } else {
            starts[base + out] = starts[base + t]
            out += 1usize
            t += 1usize
        }
    }
    ret out
}

// Tokenise `word` by the learned merges, in order; `out` receives the
// tokens as slices of the word, `scratch.len >= word.len`.
fn bpe_encode(b: *const Bpe, word: str, out: []str, scratch: []usize) -> (usize, err) {
    if scratch.len < word.len || out.len < word.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < word.len {
        scratch[i] = i
        i += 1usize
    }
    var live = word.len
    var m = 0usize
    while m < b.count {
        live = merge_word(word, scratch, 0usize, live, b.left[m], b.right[m])
        m += 1usize
    }
    i = 0usize
    while i < live {
        out[i] = token_at(word, scratch, 0usize, live, i)
        i += 1usize
    }
    ret (live, ok)
}

// WordPiece: from each position the longest vocabulary piece is taken, a
// continuation piece (`##` prefix) after the first; `Unknown` when no piece
// fits. `out` receives the pieces as vocabulary entries.
fn wordpiece(word: str, vocabulary: []const str, out: []str) -> (usize, err) {
    var count = 0usize
    var i = 0usize
    while i < word.len {
        var best = vocabulary.len
        var best_len = 0usize
        var v = 0usize
        while v < vocabulary.len {
            let piece = vocabulary[v]
            var body = piece
            var continuation = false
            if piece.len >= 2usize && piece[0usize] == 35u8 && piece[1usize] == 35u8 {
                body = piece[2usize..]
                continuation = true
            }
            if continuation == (i > 0usize) && body.len > best_len && body.len <= word.len - i && same(word[i..i + body.len], body) {
                best = v
                best_len = body.len
            }
            v += 1usize
        }
        if best == vocabulary.len { ret (count, Unknown) }
        if count >= out.len { ret (count, TooSmall) }
        out[count] = vocabulary[best]
        count += 1usize
        i += best_len
    }
    ret (count, ok)
}

// The unigram (Viterbi) segmentation: the pieces whose log probabilities
// sum highest; `out` receives them as slices of the word,
// `scores.len >= word.len + 1`, `scratch.len >= word.len + 1`.
fn unigram(word: str, vocabulary: []const str, log_probability: []const f64, out: []str, scores: []f64, scratch: []usize) -> (usize, err) {
    let n = word.len
    if scores.len < n + 1usize || scratch.len < n + 1usize || vocabulary.len != log_probability.len { ret (0usize, TooSmall) }
    let none = 0usize -% 1usize
    scores[0usize] = 0.0f64
    scratch[0usize] = none
    var j = 1usize
    while j <= n {
        scratch[j] = none
        var v = 0usize
        while v < vocabulary.len {
            let piece = vocabulary[v]
            if piece.len > 0usize && piece.len <= j && scratch[j - piece.len] != none || (piece.len > 0usize && piece.len == j) {
                if same(word[j - piece.len..j], piece) {
                    let s = scores[j - piece.len] + log_probability[v]
                    if scratch[j] == none || s > scores[j] {
                        scores[j] = s
                        scratch[j] = j - piece.len
                    }
                }
            }
            v += 1usize
        }
        j += 1usize
    }
    if n > 0usize && scratch[n] == none { ret (0usize, Unknown) }
    ret (collect(word, scratch, n, out), ok)
}

fn collect(word: str, from: []const usize, n: usize, out: []str) -> usize {
    var count = 0usize
    var j = n
    while j > 0usize {
        count += 1usize
        j = from[j]
    }
    var k = count
    j = n
    while j > 0usize {
        k -= 1usize
        if k < out.len { out[k] = word[from[j]..j] }
        j = from[j]
    }
    ret count
}

// One segmentation drawn with probability proportional to its likelihood
// raised to `1 / temperature` (forward filtering, backward sampling);
// storage as `unigram`.
fn unigram_sample(word: str, vocabulary: []const str, log_probability: []const f64, temperature: f64, r: *rand.Pcg64, out: []str, scores: []f64, scratch: []usize) -> (usize, err) {
    let n = word.len
    if scores.len < n + 1usize || scratch.len < n + 1usize || vocabulary.len != log_probability.len { ret (0usize, TooSmall) }
    if temperature <= 0.0f64 { ret (0usize, Invalid) }
    let none = 0usize -% 1usize
    let unreachable_score = 0.0f64 - 1.0e300f64
    // Forward: scores[j] = log of the total weight of segmentations of word[..j].
    scores[0usize] = 0.0f64
    var j = 1usize
    while j <= n {
        var total = unreachable_score
        var v = 0usize
        while v < vocabulary.len {
            let piece = vocabulary[v]
            if piece.len > 0usize && piece.len <= j && scores[j - piece.len] > unreachable_score && same(word[j - piece.len..j], piece) {
                let s = scores[j - piece.len] + log_probability[v] / temperature
                total = log_add(total, s)
            }
            v += 1usize
        }
        scores[j] = total
        j += 1usize
    }
    if n > 0usize && scores[n] <= unreachable_score { ret (0usize, Unknown) }
    // Backward: at j pick a piece ending there with probability its share of scores[j].
    j = n
    while j > 0usize {
        var pick = rand.pcg64_f64(r)
        var chosen = none
        var v = 0usize
        while v < vocabulary.len && chosen == none {
            let piece = vocabulary[v]
            if piece.len > 0usize && piece.len <= j && scores[j - piece.len] > unreachable_score && same(word[j - piece.len..j], piece) {
                let share = math.exp[f64](scores[j - piece.len] + log_probability[v] / temperature - scores[j])
                pick -= share
                if pick <= 0.0f64 { chosen = v }
            }
            v += 1usize
        }
        if chosen == none {
            // Rounding left the last candidate: take the last matching piece.
            v = vocabulary.len
            while v > 0usize && chosen == none {
                v -= 1usize
                let piece = vocabulary[v]
                if piece.len > 0usize && piece.len <= j && scores[j - piece.len] > unreachable_score && same(word[j - piece.len..j], piece) { chosen = v }
            }
        }
        scratch[j] = j - vocabulary[chosen].len
        j = scratch[j]
    }
    ret (collect(word, scratch, n, out), ok)
}

fn log_add(a: f64, b: f64) -> f64 {
    if a < b { ret b + math.log[f64](1.0f64 + math.exp[f64](a - b)) }
    ret a + math.log[f64](1.0f64 + math.exp[f64](b - a))
}

// Byte-pair encoding of one word by the learned merges, in rank order: the plan's
// name for `bpe_encode`. An end-of-word marker is the caller's: append it to every
// corpus word before `bpe_train` and to the word here, and it merges like any byte.
fn bpe(b: *const Bpe, word: str, out: []str, scratch: []usize) -> (usize, err) {
    let (count, count_error) = bpe_encode(b, word, out, scratch)
    ret (count, count_error)
}
