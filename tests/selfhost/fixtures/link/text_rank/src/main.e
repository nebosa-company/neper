// `e.text.rank`: TF-IDF and BM25 over four small documents against the
// formulas worked in Python, reciprocal rank fusion of two rankings with
// ties broken by id, and maximal marginal relevance skipping the near
// duplicate. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.rank

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var docs: [4]str = zero
    docs[0usize] = "the cat sat on the mat"
    docs[1usize] = "the dog sat"
    docs[2usize] = "cats and dogs"
    docs[3usize] = "the the the"

    // 1: term statistics and TF-IDF.
    if rank.word_count(docs[0usize]) != 6usize || rank.word_count("") != 0usize || rank.word_count("  a  ") != 1usize { os.exit(1i32) }
    if rank.term_frequency(docs[0usize], "the") != 2usize || rank.term_frequency(docs[0usize], "cats") != 0usize { os.exit(1i32) }
    if rank.document_frequency(docs[..], "the") != 3usize || rank.document_frequency(docs[..], "zebra") != 0usize { os.exit(1i32) }
    if !near(rank.tf_idf(docs[..], 0usize, "cat"), 0.23104906018664842f64, 0.000000000001f64) { os.exit(1i32) }
    if !near(rank.tf_idf(docs[..], 0usize, "the"), 0.09589402415059362f64, 0.000000000001f64) { os.exit(1i32) }
    if !near(rank.tf_idf(docs[..], 3usize, "the"), 0.28768207245178085f64, 0.000000000001f64) { os.exit(1i32) }
    if rank.tf_idf(docs[..], 1usize, "cat") != 0.0f64 || rank.tf_idf(docs[..], 1usize, "zebra") != 0.0f64 { os.exit(1i32) }

    // 2: BM25.
    if !near(rank.bm25(docs[..], 0usize, "cat sat", 1.2f64, 0.75f64), 1.5232350243609267f64, 0.000000000001f64) { os.exit(2i32) }
    if !near(rank.bm25(docs[..], 1usize, "cat sat", 1.2f64, 0.75f64), 0.7549127709068711f64, 0.000000000001f64) { os.exit(2i32) }
    if !near(rank.bm25(docs[..], 3usize, "the", 1.2f64, 0.75f64), 0.5855857288546353f64, 0.000000000001f64) { os.exit(2i32) }
    if rank.bm25(docs[..], 2usize, "zebra", 1.2f64, 0.75f64) != 0.0f64 || rank.bm25(docs[..0usize], 0usize, "the", 1.2f64, 0.75f64) != 0.0f64 { os.exit(2i32) }

    // 3: reciprocal rank fusion.
    var rankings: [6]usize = zero
    rankings[0usize] = 2usize
    rankings[1usize] = 0usize
    rankings[2usize] = 1usize
    rankings[3usize] = 2usize
    rankings[4usize] = 0usize
    rankings[5usize] = 3usize
    var starts: [2]usize = zero
    starts[1usize] = 3usize
    var scores: [5]f64 = zero
    var order: [5]usize = zero
    let (fused, fused_error) = rank.reciprocal_rank_fusion(rankings[..], starts[..], 60.0f64, scores[..], order[..])
    if fused_error != ok || fused != 4usize || order[0usize] != 2usize || order[1usize] != 0usize || order[2usize] != 1usize || order[3usize] != 3usize { os.exit(3i32) }
    if !near(scores[2usize], 2.0f64 / 61.0f64, 0.000000000001f64) || !near(scores[1usize], 1.0f64 / 63.0f64, 0.000000000001f64) || scores[4usize] != 0.0f64 { os.exit(3i32) }
    let (_, fused_room) = rank.reciprocal_rank_fusion(rankings[..], starts[..], 60.0f64, scores[..], order[..2usize])
    if fused_room != rank.TooSmall { os.exit(3i32) }
    let (_, fused_invalid) = rank.reciprocal_rank_fusion(rankings[..], starts[..], 60.0f64, scores[..2usize], order[..])
    if fused_invalid != rank.Invalid { os.exit(3i32) }

    // 4: maximal marginal relevance.
    var relevance: [3]f64 = zero
    relevance[0usize] = 0.9f64
    relevance[1usize] = 0.8f64
    relevance[2usize] = 0.7f64
    var similarity: [9]f64 = zero
    similarity[0usize] = 1.0f64
    similarity[1usize] = 0.95f64
    similarity[2usize] = 0.1f64
    similarity[3usize] = 0.95f64
    similarity[4usize] = 1.0f64
    similarity[5usize] = 0.1f64
    similarity[6usize] = 0.1f64
    similarity[7usize] = 0.1f64
    similarity[8usize] = 1.0f64
    var chosen: [3]usize = zero
    var marks: [3]usize = zero
    let (picked, picked_error) = rank.maximal_marginal_relevance(relevance[..], similarity[..], 0.5f64, 2usize, chosen[..], marks[..])
    if picked_error != ok || picked != 2usize || chosen[0usize] != 0usize || chosen[1usize] != 2usize { os.exit(4i32) }
    let (all, all_error) = rank.maximal_marginal_relevance(relevance[..], similarity[..], 1.0f64, 3usize, chosen[..], marks[..])
    if all_error != ok || all != 3usize || chosen[0usize] != 0usize || chosen[1usize] != 1usize || chosen[2usize] != 2usize { os.exit(4i32) }
    let (_, too_many) = rank.maximal_marginal_relevance(relevance[..], similarity[..], 0.5f64, 4usize, chosen[..], marks[..])
    if too_many != rank.TooSmall { os.exit(4i32) }

    try io.print("text rank ok\n")
    ret ok
}
