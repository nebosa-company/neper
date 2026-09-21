// `e.algo.align`: Needleman-Wunsch, Smith-Waterman and Gotoh scores of
// five pairs against a NumPy dynamic programme, and Hirschberg answering
// the global score with an operation list that replays to both strings
// and scores the same. Each check exits with its own code.

use e.algo.align
use e.io
use e.mem
use e.os

fn check_pair(a: str, b: str, want_global: i64, want_local: i64, end_a: usize, end_b: usize, want_affine: i64) {
    var scratch: [64]i64 = zero
    let s = align.Scores { match_score: 2i64, mismatch: 0i64 - 1i64, gap: 0i64 - 2i64 }
    let (g, g_error) = align.global(a, b, s, scratch[..])
    if g_error != ok || g != want_global { os.exit(1i32) }
    let (l, la, lb, l_error) = align.local(a, b, s, scratch[..])
    if l_error != ok || l != want_local || la != end_a || lb != end_b { os.exit(2i32) }
    let (af, af_error) = align.affine_gap(a, b, s, 0i64 - 3i64, 0i64 - 1i64, scratch[..])
    if af_error != ok || af != want_affine { os.exit(3i32) }
    // Hirschberg: same score, and the operations consume both strings and score the same.
    var ops: [32]align.Op = zero
    let (h, count, h_error) = align.global_linear_space(a, b, s, ops[..], scratch[..])
    if h_error != ok || h != want_global { os.exit(4i32) }
    var i = 0usize
    var j = 0usize
    var total = 0i64
    var k = 0usize
    while k < count {
        if ops[k] == .Match {
            if i >= a.len || j >= b.len { os.exit(4i32) }
            if a[i] == b[j] { total += 2i64 } else { total -= 1i64 }
            i += 1usize
            j += 1usize
        } else if ops[k] == .Delete {
            if i >= a.len { os.exit(4i32) }
            total -= 2i64
            i += 1usize
        } else {
            if j >= b.len { os.exit(4i32) }
            total -= 2i64
            j += 1usize
        }
        k += 1usize
    }
    if i != a.len || j != b.len || total != want_global { os.exit(4i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    check_pair("GATTACA", "GCATGCU", 2i64, 4i64, 3usize, 4usize, 2i64)
    check_pair("ACGTACGT", "ACGGT", 4i64, 6i64, 3usize, 3usize, 4i64)
    check_pair("AAAA", "AA", 0i64, 4i64, 2usize, 2usize, 0i64 - 1i64)
    check_pair("ABCDEFGH", "BCDXEFG", 6i64, 10i64, 7usize, 7usize, 0i64)
    check_pair("", "ABC", 0i64 - 6i64, 0i64, 0usize, 0usize, 0i64 - 6i64)
    check_pair("ABC", "", 0i64 - 6i64, 0i64, 0usize, 0usize, 0i64 - 6i64)
    check_pair("SAME", "SAME", 8i64, 8i64, 4usize, 4usize, 8i64)
    var scratch: [4]i64 = zero
    let s = align.Scores { match_score: 2i64, mismatch: 0i64 - 1i64, gap: 0i64 - 2i64 }
    let (_, room) = align.global("GATTACA", "GCATGCU", s, scratch[..])
    if room != align.TooSmall { os.exit(5i32) }
    var ops: [4]align.Op = zero
    var more: [64]i64 = zero
    let (_, _, ops_room) = align.global_linear_space("GATTACA", "GCATGCU", s, ops[..], more[..])
    if ops_room != align.TooSmall { os.exit(5i32) }

    try io.print("algo align ok\n")
    ret ok
}
