// `e.text.metric`: BLEU against NLTK's sentence_bleu (uniform weights, no
// smoothing) on the cat and the Party-commands examples, ROUGE-1, ROUGE-2
// and ROUGE-L against counts done by hand in Python, METEOR over exact
// matches with its fragmentation penalty, and the degenerate cases. Each
// check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.metric

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var scratch: [256]usize = zero
    let ref1 = "the cat is on the mat"
    let cand1 = "the cat the cat on the mat"
    let ref2 = "It is a guide to action that ensures that the military will forever heed Party commands"
    let cand2 = "It is a guide to action which ensures that the military always obeys the commands of the party"
    let cand3 = "It is to insure the troops forever hearing the activity guidebook that party direct"

    // 1: BLEU.
    let (b1, b1_error) = metric.bleu(cand1, ref1, 2usize, scratch[..])
    if b1_error != ok || !near(b1, 0.5976143046671969f64, 0.000000000001f64) { os.exit(1i32) }
    let (b2, b2_error) = metric.bleu(cand1, ref1, 1usize, scratch[..])
    if b2_error != ok || !near(b2, 0.7142857142857143f64, 0.000000000001f64) { os.exit(1i32) }
    let (b3, b3_error) = metric.bleu(cand1, ref1, 4usize, scratch[..])
    if b3_error != ok || b3 != 0.0f64 { os.exit(1i32) }
    let (b4, b4_error) = metric.bleu(cand2, ref2, 4usize, scratch[..])
    if b4_error != ok || !near(b4, 0.41180376356915777f64, 0.000000000001f64) { os.exit(1i32) }
    let (b5, b5_error) = metric.bleu(cand2, ref2, 2usize, scratch[..])
    if b5_error != ok || !near(b5, 0.5362664443598958f64, 0.000000000001f64) { os.exit(1i32) }
    let (b6, b6_error) = metric.bleu(cand3, ref2, 1usize, scratch[..])
    if b6_error != ok || !near(b6, 0.37151909989293497f64, 0.000000000001f64) { os.exit(1i32) }
    let (b7, b7_error) = metric.bleu(ref2, ref2, 4usize, scratch[..])
    if b7_error != ok || !near(b7, 1.0f64, 0.000000000001f64) { os.exit(1i32) }
    let (b8, b8_error) = metric.bleu("", ref1, 4usize, scratch[..])
    if b8_error != ok || b8 != 0.0f64 { os.exit(1i32) }
    let (_, b_invalid) = metric.bleu(cand1, ref1, 0usize, scratch[..])
    if b_invalid != metric.Invalid { os.exit(1i32) }
    let (_, b_room) = metric.bleu(cand1, ref1, 1usize, scratch[..10usize])
    if b_room != metric.TooSmall { os.exit(1i32) }

    // 2: ROUGE-N.
    let (r1, r1_error) = metric.rouge_n(cand1, ref1, 1usize, scratch[..])
    if r1_error != ok || !near(r1.precision, 0.7142857142857143f64, 0.000000000001f64) || !near(r1.recall, 0.8333333333333334f64, 0.000000000001f64) || !near(r1.f1, 0.7692307692307692f64, 0.000000000001f64) { os.exit(2i32) }
    let (r2, r2_error) = metric.rouge_n(cand1, ref1, 2usize, scratch[..])
    if r2_error != ok || !near(r2.precision, 0.5f64, 0.000000000001f64) || !near(r2.recall, 0.6f64, 0.000000000001f64) || !near(r2.f1, 0.5454545454545454f64, 0.000000000001f64) { os.exit(2i32) }
    let (r3, r3_error) = metric.rouge_n(cand3, ref2, 2usize, scratch[..])
    if r3_error != ok || !near(r3.precision, 0.07692307692307693f64, 0.000000000001f64) || !near(r3.recall, 0.06666666666666667f64, 0.000000000001f64) { os.exit(2i32) }
    let (r4, r4_error) = metric.rouge_n("a", "b c", 3usize, scratch[..])
    if r4_error != ok || r4.precision != 0.0f64 || r4.recall != 0.0f64 || r4.f1 != 0.0f64 { os.exit(2i32) }
    let (_, r_invalid) = metric.rouge_n(cand1, ref1, 0usize, scratch[..])
    if r_invalid != metric.Invalid { os.exit(2i32) }

    // 3: ROUGE-L.
    let (l1, l1_error) = metric.rouge_l(cand1, ref1, scratch[..])
    if l1_error != ok || !near(l1.f1, 0.7692307692307692f64, 0.000000000001f64) { os.exit(3i32) }
    let (l2, l2_error) = metric.rouge_l(cand3, ref2, scratch[..])
    if l2_error != ok || !near(l2.precision, 0.35714285714285715f64, 0.000000000001f64) || !near(l2.recall, 0.3125f64, 0.000000000001f64) || !near(l2.f1, 0.3333333333333333f64, 0.000000000001f64) { os.exit(3i32) }
    let (l3, l3_error) = metric.rouge_l("", ref1, scratch[..])
    if l3_error != ok || l3.f1 != 0.0f64 { os.exit(3i32) }
    let (_, l_room) = metric.rouge_l(cand1, ref1, scratch[..30usize])
    if l_room != metric.TooSmall { os.exit(3i32) }

    // 4: METEOR.
    let (m1, m1_error) = metric.meteor(cand1, ref1, scratch[..])
    if m1_error != ok || !near(m1, 0.6098360655737705f64, 0.000000000001f64) { os.exit(4i32) }
    let (m2, m2_error) = metric.meteor(cand2, ref2, scratch[..])
    if m2_error != ok || !near(m2, 0.6471278440975411f64, 0.000000000001f64) { os.exit(4i32) }
    let (m3, m3_error) = metric.meteor(cand3, ref2, scratch[..])
    if m3_error != ok || !near(m3, 0.2698663853727145f64, 0.000000000001f64) { os.exit(4i32) }
    let (m4, m4_error) = metric.meteor(ref1, ref1, scratch[..])
    if m4_error != ok || !near(m4, 0.9976851851851852f64, 0.000000000001f64) { os.exit(4i32) }
    let (m5, m5_error) = metric.meteor("x y z", ref1, scratch[..])
    if m5_error != ok || m5 != 0.0f64 { os.exit(4i32) }
    let (_, m_room) = metric.meteor(cand1, ref1, scratch[..27usize])
    if m_room != metric.TooSmall { os.exit(4i32) }

    try io.print("text metric ok\n")
    ret ok
}
