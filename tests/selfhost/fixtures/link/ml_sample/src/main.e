// `e.ml.sample`: softmax with a temperature, top-k and nucleus draws whose
// frequencies follow the truncated distributions, contrastive decoding
// preferring the token the amateur underrates, and beam search finding the
// best four-token path of a toy transition model where greedy decoding
// does not. Each check exits with its own code.

use e.algo.rand
use e.io
use e.math
use e.mem
use e.ml.sample
use e.os

type Toy = struct { unused: u8 }

// Log probabilities of the next token after `prefix` in a three-token chain.
fn score(t: *Toy, prefix: []const usize, logits: []f64) {
    if prefix.len == 0usize {
        logits[0usize] = math.log[f64](0.5f64)
        logits[1usize] = math.log[f64](0.3f64)
        logits[2usize] = math.log[f64](0.2f64)
        ret
    }
    let last = prefix[prefix.len - 1usize]
    if last == 0usize {
        logits[0usize] = math.log[f64](0.1f64)
        logits[1usize] = math.log[f64](0.8f64)
        logits[2usize] = math.log[f64](0.1f64)
    } else if last == 1usize {
        logits[0usize] = math.log[f64](0.4f64)
        logits[1usize] = math.log[f64](0.1f64)
        logits[2usize] = math.log[f64](0.5f64)
    } else {
        logits[0usize] = math.log[f64](0.3f64)
        logits[1usize] = math.log[f64](0.3f64)
        logits[2usize] = math.log[f64](0.4f64)
    }
}

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var logits: [4]f64 = zero
    logits[0usize] = 2.0f64
    logits[1usize] = 1.0f64
    logits[2usize] = 0.0f64
    logits[3usize] = 0.0f64 - 1.0f64
    var probabilities: [4]f64 = zero
    var order: [4]usize = zero

    // 1: softmax.
    if sample.softmax(logits[..], 1.0f64, probabilities[..]) != ok { os.exit(1i32) }
    if !near(probabilities[0usize], 0.6439142598879724f64, 0.000000000001f64) || !near(probabilities[3usize], 0.03205860328008499f64, 0.000000000001f64) { os.exit(1i32) }
    if sample.softmax(logits[..], 100.0f64, probabilities[..]) != ok || !near(probabilities[0usize], 0.25f64, 0.01f64) { os.exit(1i32) }
    if sample.softmax(logits[..], 0.0f64, probabilities[..]) != sample.Invalid || sample.softmax(logits[..], 1.0f64, probabilities[..2usize]) != sample.TooSmall { os.exit(1i32) }

    // 2: top-k and top-p draws.
    var r = rand.pcg64(6u64, 6u64)
    var counts: [4]usize = zero
    var draws = 0usize
    while draws < 4000usize {
        let (t, t_error) = sample.top_k(logits[..], 1.0f64, 2usize, &r, probabilities[..], order[..])
        if t_error != ok || t > 1usize { os.exit(2i32) }
        counts[t] += 1usize
        draws += 1usize
    }
    // Restricted to the top two: token 0 has 0.731 of the mass.
    if counts[0usize] < 2800usize || counts[0usize] > 3050usize || counts[2usize] != 0usize { os.exit(2i32) }
    counts[0usize] = 0usize
    counts[1usize] = 0usize
    draws = 0usize
    while draws < 4000usize {
        let (t, t_error) = sample.top_p(logits[..], 1.0f64, 0.85f64, &r, probabilities[..], order[..])
        if t_error != ok { os.exit(2i32) }
        counts[t] += 1usize
        draws += 1usize
    }
    // 0.644 + 0.237 = 0.881 reaches 0.85 with two tokens.
    if counts[2usize] != 0usize || counts[3usize] != 0usize || counts[0usize] < 2800usize || counts[0usize] > 3050usize { os.exit(2i32) }
    let (only, only_error) = sample.top_k(logits[..], 1.0f64, 1usize, &r, probabilities[..], order[..])
    if only_error != ok || only != 0usize { os.exit(2i32) }
    let (_, k_invalid) = sample.top_k(logits[..], 1.0f64, 5usize, &r, probabilities[..], order[..])
    if k_invalid != sample.Invalid { os.exit(2i32) }
    let (_, p_invalid) = sample.top_p(logits[..], 1.0f64, 1.5f64, &r, probabilities[..], order[..])
    if p_invalid != sample.Invalid { os.exit(2i32) }

    // 3: contrastive decoding.
    var amateur: [4]f64 = zero
    amateur[0usize] = 2.5f64
    amateur[1usize] = 0.0f64
    amateur[2usize] = 0.0f64
    amateur[3usize] = 0.0f64
    var scratch: [8]f64 = zero
    // The amateur also loves token 0; token 1 gains most against it, and token 3 is below the floor.
    let (pick, pick_error) = sample.contrastive(logits[..], amateur[..], 0.1f64, scratch[..])
    if pick_error != ok || pick != 1usize { os.exit(3i32) }
    let (strict, strict_error) = sample.contrastive(logits[..], amateur[..], 1.0f64, scratch[..])
    if strict_error != ok || strict != 0usize { os.exit(3i32) }
    let (_, c_invalid) = sample.contrastive(logits[..], amateur[..], 0.0f64, scratch[..])
    if c_invalid != sample.Invalid { os.exit(3i32) }

    // 4: beam search against the brute-force best path (0, 1, 0, 1); greedy gives 0, 1, 2, 2.
    var toy = Toy { unused: 0u8 }
    var out: [4]usize = zero
    var tokens: [24]usize = zero
    var scores: [16]f64 = zero
    let (best, beam_error) = sample.beam_search[Toy](&toy, score, 3usize, 3usize, 4usize, out[..], tokens[..], scores[..])
    if beam_error != ok || !near(best, 0.0f64 - 2.05572501506252f64, 0.000000001f64) { os.exit(4i32) }
    if out[0usize] != 0usize || out[1usize] != 1usize || out[2usize] != 0usize || out[3usize] != 1usize { os.exit(4i32) }
    let (greedy, greedy_error) = sample.beam_search[Toy](&toy, score, 3usize, 1usize, 4usize, out[..], tokens[..8usize], scores[..])
    if greedy_error != ok || !near(greedy, 0.0f64 - 2.525728644308255f64, 0.000000001f64) || out[2usize] != 2usize || out[3usize] != 2usize { os.exit(4i32) }
    let (_, beam_room) = sample.beam_search[Toy](&toy, score, 3usize, 3usize, 4usize, out[..], tokens[..], scores[..4usize])
    if beam_room != sample.TooSmall { os.exit(4i32) }
    let (_, beam_invalid) = sample.beam_search[Toy](&toy, score, 3usize, 0usize, 4usize, out[..], tokens[..], scores[..])
    if beam_invalid != sample.Invalid { os.exit(4i32) }

    try io.print("ml sample ok\n")
    ret ok
}
