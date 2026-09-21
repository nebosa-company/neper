// `e.ml.hmm` on a two-state, three-symbol model: the forward log
// likelihood, the Viterbi path and score, and one Baum-Welch pass against
// a NumPy reference, the re-estimated model likelier, and the argument
// checks. Each check exits with its own code.

use e.io
use e.mem
use e.ml.hmm
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var start: [2]f64 = zero
    start[0usize] = 0.6f64
    start[1usize] = 0.4f64
    var transition: [4]f64 = zero
    transition[0usize] = 0.7f64
    transition[1usize] = 0.3f64
    transition[2usize] = 0.4f64
    transition[3usize] = 0.6f64
    var emission: [6]f64 = zero
    emission[0usize] = 0.5f64
    emission[1usize] = 0.4f64
    emission[2usize] = 0.1f64
    emission[3usize] = 0.1f64
    emission[4usize] = 0.3f64
    emission[5usize] = 0.6f64
    var observed: [6]usize = zero
    observed[1usize] = 1usize
    observed[2usize] = 2usize
    observed[3usize] = 2usize
    observed[4usize] = 1usize
    var scratch: [64]f64 = zero

    // 1: forward.
    let (ll, ll_error) = hmm.forward(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], scratch[..])
    if ll_error != ok || !near(ll, 0.0f64 - 6.519354992901578f64, 0.000000000001f64) { os.exit(1i32) }
    let (empty, empty_error) = hmm.forward(start[..], transition[..], emission[..], 2usize, 3usize, observed[..0usize], scratch[..])
    if empty_error != ok || empty != 0.0f64 { os.exit(1i32) }
    observed[5usize] = 7usize
    let (_, bad) = hmm.forward(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], scratch[..])
    if bad != hmm.Invalid { os.exit(1i32) }
    observed[5usize] = 0usize
    let (_, room) = hmm.forward(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], scratch[..3usize])
    if room != hmm.TooSmall { os.exit(1i32) }

    // 2: Viterbi.
    var path: [6]usize = zero
    var back: [12]usize = zero
    let (score, v_error) = hmm.viterbi(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], path[..], scratch[..], back[..])
    if v_error != ok || !near(score, 0.0f64 - 8.095791744009718f64, 0.000000000001f64) { os.exit(2i32) }
    if path[0usize] != 0usize || path[1usize] != 0usize || path[2usize] != 1usize || path[3usize] != 1usize || path[4usize] != 0usize || path[5usize] != 0usize { os.exit(2i32) }
    let (_, v_room) = hmm.viterbi(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], path[..], scratch[..], back[..5usize])
    if v_room != hmm.TooSmall { os.exit(2i32) }
    // An impossible observation (zero emission everywhere) is Invalid.
    emission[2usize] = 0.0f64
    emission[5usize] = 0.0f64
    let (_, impossible) = hmm.viterbi(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], path[..], scratch[..], back[..])
    if impossible != hmm.Invalid { os.exit(2i32) }
    emission[2usize] = 0.1f64
    emission[5usize] = 0.6f64

    // 3: one Baum-Welch pass.
    let (before, bw_error) = hmm.baum_welch(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], scratch[..])
    if bw_error != ok || !near(before, 0.0f64 - 6.519354992901578f64, 0.000000000001f64) { os.exit(3i32) }
    if !near(start[0usize], 0.87426687f64, 0.00000001f64) || !near(transition[0usize], 0.59230664f64, 0.00000001f64) || !near(transition[3usize], 0.63468822f64, 0.00000001f64) { os.exit(3i32) }
    if !near(emission[0usize], 0.53530355f64, 0.00000001f64) || !near(emission[4usize], 0.28649881f64, 0.00000001f64) || !near(emission[5usize], 0.61744961f64, 0.00000001f64) { os.exit(3i32) }
    let (after, after_error) = hmm.forward(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], scratch[..])
    if after_error != ok || !near(after, 0.0f64 - 6.109162719768476f64, 0.00000001f64) { os.exit(3i32) }
    let (_, bw_room) = hmm.baum_welch(start[..], transition[..], emission[..], 2usize, 3usize, observed[..], scratch[..10usize])
    if bw_room != hmm.TooSmall { os.exit(3i32) }
    let (_, bw_invalid) = hmm.baum_welch(start[..], transition[..], emission[..], 2usize, 3usize, observed[..0usize], scratch[..])
    if bw_invalid != hmm.Invalid { os.exit(3i32) }

    try io.print("ml hmm ok\n")
    ret ok
}
