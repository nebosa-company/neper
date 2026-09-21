// Retrieval scoring in caller storage. A document is a string of
// space-separated words, compared byte for byte. `tf_idf` and `bm25` score
// one document of a collection against a term or a query; `reciprocal_rank_fusion`
// merges several rankings of document ids into one; `maximal_marginal_relevance`
// re-ranks by relevance minus redundancy against what is already chosen.

use e.math

error TooSmall
error Invalid

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// The number of words of `doc`.
fn word_count(doc: str) -> usize {
    var count = 0usize
    var i = 0usize
    while i < doc.len {
        if doc[i] == 32u8 {
            i += 1usize
        } else {
            while i < doc.len && doc[i] != 32u8 { i += 1usize }
            count += 1usize
        }
    }
    ret count
}

// How many times `term` occurs as a word of `doc`.
fn term_frequency(doc: str, term: str) -> usize {
    var count = 0usize
    var i = 0usize
    while i < doc.len {
        if doc[i] == 32u8 {
            i += 1usize
        } else {
            let start = i
            while i < doc.len && doc[i] != 32u8 { i += 1usize }
            if same(doc[start..i], term) { count += 1usize }
        }
    }
    ret count
}

// How many documents contain `term`.
fn document_frequency(docs: []const str, term: str) -> usize {
    var count = 0usize
    var d = 0usize
    while d < docs.len {
        if term_frequency(docs[d], term) > 0usize { count += 1usize }
        d += 1usize
    }
    ret count
}

// TF-IDF of `term` in `docs[index]`: the term's share of the document's
// words times `ln(N / df)`; zero when the term is absent everywhere.
fn tf_idf(docs: []const str, index: usize, term: str) -> f64 {
    let df = document_frequency(docs, term)
    if df == 0usize { ret 0.0f64 }
    let words = word_count(docs[index])
    if words == 0usize { ret 0.0f64 }
    let tf = f64(term_frequency(docs[index], term)) / f64(words)
    ret tf * math.log[f64](f64(docs.len) / f64(df))
}

// Okapi BM25 of `docs[index]` for the words of `query`, with the usual
// `k1 = 1.2`, `b = 0.75` and the idf `ln(1 + (N - df + 0.5) / (df + 0.5))`.
fn bm25(docs: []const str, index: usize, query: str, k1: f64, b: f64) -> f64 {
    var total_words = 0usize
    var d = 0usize
    while d < docs.len {
        total_words += word_count(docs[d])
        d += 1usize
    }
    if docs.len == 0usize { ret 0.0f64 }
    let average = f64(total_words) / f64(docs.len)
    let length = f64(word_count(docs[index]))
    var score = 0.0f64
    var i = 0usize
    while i < query.len {
        if query[i] == 32u8 {
            i += 1usize
        } else {
            let start = i
            while i < query.len && query[i] != 32u8 { i += 1usize }
            let term = query[start..i]
            let df = f64(document_frequency(docs, term))
            let tf = f64(term_frequency(docs[index], term))
            if tf > 0.0f64 {
                let idf = math.log[f64](1.0f64 + (f64(docs.len) - df + 0.5f64) / (df + 0.5f64))
                var norm = 1.0f64
                if average > 0.0f64 { norm = 1.0f64 - b + b * length / average }
                score += idf * tf * (k1 + 1.0f64) / (tf + k1 * norm)
            }
        }
    }
    ret score
}

// Reciprocal rank fusion: `rankings` is a flat list of document ids and
// `starts` its list boundaries (`starts.len` lists, each `starts[i]..starts[i + 1]`
// or to the end); every id gets `sum 1 / (k + rank)` over the lists it
// appears in (ranks from 1). `scores` (one per id, `scores.len` ids) receives
// the totals and `order` the ids with a score, best first. Answers the count.
fn reciprocal_rank_fusion(rankings: []const usize, starts: []const usize, k: f64, scores: []f64, order: []usize) -> (usize, err) {
    var i = 0usize
    while i < scores.len {
        scores[i] = 0.0f64
        i += 1usize
    }
    var l = 0usize
    while l < starts.len {
        var end = rankings.len
        if l + 1usize < starts.len { end = starts[l + 1usize] }
        var r = starts[l]
        var rank = 1usize
        while r < end {
            if rankings[r] >= scores.len { ret (0usize, Invalid) }
            scores[rankings[r]] += 1.0f64 / (k + f64(rank))
            r += 1usize
            rank += 1usize
        }
        l += 1usize
    }
    // Insertion sort of the scored ids, ties by id.
    var count = 0usize
    i = 0usize
    while i < scores.len {
        if scores[i] > 0.0f64 {
            if count >= order.len { ret (count, TooSmall) }
            var j = count
            while j > 0usize && scores[order[j - 1usize]] < scores[i] {
                order[j] = order[j - 1usize]
                j -= 1usize
            }
            order[j] = i
            count += 1usize
        }
        i += 1usize
    }
    ret (count, ok)
}

// Maximal marginal relevance: `relevance` scores `n` items and `similarity`
// is their row-major `n × n` similarity; each step takes the item with the
// largest `lambda * relevance - (1 - lambda) * max similarity to the chosen`,
// until `count` are chosen into `order`. `scratch.len >= n` marks the chosen.
fn maximal_marginal_relevance(relevance: []const f64, similarity: []const f64, lambda: f64, count: usize, order: []usize, scratch: []usize) -> (usize, err) {
    let n = relevance.len
    if similarity.len < n * n || scratch.len < n || order.len < count { ret (0usize, TooSmall) }
    if count > n { ret (0usize, Invalid) }
    var i = 0usize
    while i < n {
        scratch[i] = 0usize
        i += 1usize
    }
    var chosen = 0usize
    while chosen < count {
        var best = n
        var best_score = 0.0f64
        i = 0usize
        while i < n {
            if scratch[i] == 0usize {
                var redundancy = 0.0f64
                var c = 0usize
                while c < chosen {
                    let s = similarity[i * n + order[c]]
                    if c == 0usize || s > redundancy { redundancy = s }
                    c += 1usize
                }
                let score = lambda * relevance[i] - (1.0f64 - lambda) * redundancy
                if best == n || score > best_score {
                    best = i
                    best_score = score
                }
            }
            i += 1usize
        }
        order[chosen] = best
        scratch[best] = 1usize
        chosen += 1usize
    }
    ret (chosen, ok)
}
