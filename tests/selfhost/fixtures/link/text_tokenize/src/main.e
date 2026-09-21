// `e.text.tokenize`: byte and word shingles, dictionary word breaking with
// the fewest words, byte-pair merges learned from the classic corpus (the
// same five merges a Python replica learns) and applied to new words,
// WordPiece on `unaffable`, the unigram Viterbi segmentation and a sampler
// whose draws follow the segmentation probabilities. Each check exits with
// its own code.

use e.algo.rand
use e.io
use e.math
use e.mem
use e.os
use e.text.tokenize

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var out: [16]str = zero
    var scratch: [64]usize = zero

    // 1: shingles.
    let (s1, s1_error) = tokenize.shingles("abcd", 2usize, out[..])
    if s1_error != ok || s1 != 3usize || !same(out[0usize], "ab") || !same(out[1usize], "bc") || !same(out[2usize], "cd") { os.exit(1i32) }
    let (s2, s2_error) = tokenize.shingles("ab", 3usize, out[..])
    if s2_error != ok || s2 != 0usize { os.exit(1i32) }
    let (_, s_invalid) = tokenize.shingles("abcd", 0usize, out[..])
    if s_invalid != tokenize.Invalid { os.exit(1i32) }
    let (_, s_room) = tokenize.shingles("abcd", 1usize, out[..2usize])
    if s_room != tokenize.TooSmall { os.exit(1i32) }
    let (w1, w1_error) = tokenize.word_shingles("a bb  c d", 3usize, out[..], scratch[..])
    if w1_error != ok || w1 != 2usize || !same(out[0usize], "a bb  c") || !same(out[1usize], "bb  c d") { os.exit(1i32) }
    let (w2, w2_error) = tokenize.word_shingles("a b", 3usize, out[..], scratch[..])
    if w2_error != ok || w2 != 0usize { os.exit(1i32) }

    // 2: word breaking.
    var dictionary: [6]str = zero
    dictionary[0usize] = "apple"
    dictionary[1usize] = "pie"
    dictionary[2usize] = "app"
    dictionary[3usize] = "le"
    dictionary[4usize] = "pi"
    dictionary[5usize] = "e"
    var breaks: [8]usize = zero
    let (b1, b1_error) = tokenize.word_break("applepie", dictionary[..], breaks[..], scratch[..])
    if b1_error != ok || b1 != 2usize || breaks[0usize] != 5usize || breaks[1usize] != 8usize { os.exit(2i32) }
    let (b2, b2_error) = tokenize.word_break("applepiex", dictionary[..], breaks[..], scratch[..])
    if b2_error != tokenize.Unknown || b2 != 0usize { os.exit(2i32) }
    let (b3, b3_error) = tokenize.word_break("", dictionary[..], breaks[..], scratch[..])
    if b3_error != ok || b3 != 0usize { os.exit(2i32) }
    let (b4, b4_error) = tokenize.word_break("piee", dictionary[..], breaks[..], scratch[..])
    if b4_error != ok || b4 != 2usize || breaks[0usize] != 3usize { os.exit(2i32) }
    let (_, b_room) = tokenize.word_break("applepie", dictionary[..], breaks[..1usize], scratch[..])
    if b_room != tokenize.TooSmall { os.exit(2i32) }

    // 3: byte-pair encoding.
    var corpus: [7]str = zero
    corpus[0usize] = "low"
    corpus[1usize] = "low"
    corpus[2usize] = "lower"
    corpus[3usize] = "newest"
    corpus[4usize] = "widest"
    corpus[5usize] = "newest"
    corpus[6usize] = "lowest"
    let (bpe, bpe_error) = tokenize.bpe_train(a, corpus[..], 5usize)
    if bpe_error != ok || bpe.count != 5usize { os.exit(3i32) }
    if !same(bpe.left[0usize], "l") || !same(bpe.right[0usize], "o") || !same(bpe.left[1usize], "lo") || !same(bpe.right[1usize], "w") { os.exit(3i32) }
    if !same(bpe.left[2usize], "e") || !same(bpe.right[2usize], "s") || !same(bpe.left[3usize], "es") || !same(bpe.right[3usize], "t") || !same(bpe.left[4usize], "n") || !same(bpe.right[4usize], "e") { os.exit(3i32) }
    let (t1, t1_error) = tokenize.bpe_encode(&bpe, "lowest", out[..], scratch[..])
    if t1_error != ok || t1 != 2usize || !same(out[0usize], "low") || !same(out[1usize], "est") { os.exit(3i32) }
    let (t2, t2_error) = tokenize.bpe_encode(&bpe, "newer", out[..], scratch[..])
    if t2_error != ok || t2 != 4usize || !same(out[0usize], "ne") || !same(out[1usize], "w") || !same(out[2usize], "e") || !same(out[3usize], "r") { os.exit(3i32) }
    let (t3, t3_error) = tokenize.bpe_encode(&bpe, "xyz", out[..], scratch[..])
    if t3_error != ok || t3 != 3usize || !same(out[2usize], "z") { os.exit(3i32) }
    let (few, few_error) = tokenize.bpe_train(a, corpus[..2usize], 10usize)
    if few_error != ok || few.count != 2usize { os.exit(3i32) }
    let (_, t_room) = tokenize.bpe_encode(&bpe, "lowest", out[..], scratch[..3usize])
    if t_room != tokenize.TooSmall { os.exit(3i32) }

    // 4: WordPiece.
    var vocabulary: [6]str = zero
    vocabulary[0usize] = "un"
    vocabulary[1usize] = "##aff"
    vocabulary[2usize] = "##able"
    vocabulary[3usize] = "##a"
    vocabulary[4usize] = "aff"
    vocabulary[5usize] = "able"
    let (p1, p1_error) = tokenize.wordpiece("unaffable", vocabulary[..], out[..])
    if p1_error != ok || p1 != 3usize || !same(out[0usize], "un") || !same(out[1usize], "##aff") || !same(out[2usize], "##able") { os.exit(4i32) }
    let (p2, p2_error) = tokenize.wordpiece("able", vocabulary[..], out[..])
    if p2_error != ok || p2 != 1usize || !same(out[0usize], "able") { os.exit(4i32) }
    let (_, p3_error) = tokenize.wordpiece("unaffab", vocabulary[..], out[..])
    if p3_error != tokenize.Unknown { os.exit(4i32) }
    let (_, p4_error) = tokenize.wordpiece("xun", vocabulary[..], out[..])
    if p4_error != tokenize.Unknown { os.exit(4i32) }
    let (p5, p5_error) = tokenize.wordpiece("", vocabulary[..], out[..])
    if p5_error != ok || p5 != 0usize { os.exit(4i32) }

    // 5: unigram Viterbi and sampling.
    var pieces: [6]str = zero
    pieces[0usize] = "a"
    pieces[1usize] = "b"
    pieces[2usize] = "ab"
    pieces[3usize] = "ba"
    pieces[4usize] = "abab"
    pieces[5usize] = "c"
    var logp: [6]f64 = zero
    logp[0usize] = math.log[f64](0.3f64)
    logp[1usize] = math.log[f64](0.3f64)
    logp[2usize] = math.log[f64](0.15f64)
    logp[3usize] = math.log[f64](0.1f64)
    logp[4usize] = math.log[f64](0.1f64)
    logp[5usize] = math.log[f64](0.05f64)
    var scores: [16]f64 = zero
    let (u1, u1_error) = tokenize.unigram("abab", pieces[..], logp[..], out[..], scores[..], scratch[..])
    if u1_error != ok || u1 != 1usize || !same(out[0usize], "abab") { os.exit(5i32) }
    let (u2, u2_error) = tokenize.unigram("ababa", pieces[..], logp[..], out[..], scores[..], scratch[..])
    if u2_error != ok || u2 != 2usize || !same(out[0usize], "abab") || !same(out[1usize], "a") { os.exit(5i32) }
    let (u3, u3_error) = tokenize.unigram("bab", pieces[..], logp[..], out[..], scores[..], scratch[..])
    if u3_error != ok || u3 != 2usize || !same(out[0usize], "b") || !same(out[1usize], "ab") { os.exit(5i32) }
    let (_, u4_error) = tokenize.unigram("abd", pieces[..], logp[..], out[..], scores[..], scratch[..])
    if u4_error != tokenize.Unknown { os.exit(5i32) }
    // Sampling: the whole-word piece has probability 0.6002 among the six segmentations
    // of `abab`; over 4000 draws the share lands within 0.03 of it.
    var r = rand.pcg64(8u64, 8u64)
    var whole = 0usize
    var draws = 0usize
    while draws < 4000usize {
        let (count, draw_error) = tokenize.unigram_sample("abab", pieces[..], logp[..], 1.0f64, &r, out[..], scores[..], scratch[..])
        if draw_error != ok || count == 0usize { os.exit(5i32) }
        if count == 1usize { whole += 1usize }
        draws += 1usize
    }
    if whole < 2280usize || whole > 2520usize { os.exit(5i32) }
    // A cold temperature makes the best segmentation nearly certain.
    whole = 0usize
    draws = 0usize
    while draws < 200usize {
        let (count, draw_error) = tokenize.unigram_sample("abab", pieces[..], logp[..], 0.1f64, &r, out[..], scores[..], scratch[..])
        if draw_error != ok { os.exit(5i32) }
        if count == 1usize { whole += 1usize }
        draws += 1usize
    }
    if whole < 195usize { os.exit(5i32) }
    let (_, sample_invalid) = tokenize.unigram_sample("abab", pieces[..], logp[..], 0.0f64, &r, out[..], scores[..], scratch[..])
    if sample_invalid != tokenize.Invalid { os.exit(5i32) }
    let (_, sample_unknown) = tokenize.unigram_sample("abd", pieces[..], logp[..], 1.0f64, &r, out[..], scores[..], scratch[..])
    if sample_unknown != tokenize.Unknown { os.exit(5i32) }

    try io.print("text tokenize ok\n")
    ret ok
}
