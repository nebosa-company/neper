// `e.ml.loss`: InfoNCE, the triplet hinge, the distillation KL and the CTC
// negative log likelihood (against a brute-force sum over every alignment)
// on small hand-worked inputs, with the invalid cases. Each check exits
// with its own code.

use e.io
use e.mem
use e.math
use e.ml.loss
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var scratch: [16]f64 = zero

    // 1: InfoNCE and the triplet hinge.
    var anchor: [2]f64 = zero
    anchor[0usize] = 1.0f64
    var candidates: [6]f64 = zero
    candidates[0usize] = 0.9f64
    candidates[1usize] = 0.1f64
    candidates[3usize] = 1.0f64
    candidates[4usize] = 0.0f64 - 1.0f64
    let (nce, nce_error) = loss.info_nce(anchor[..], candidates[..], 3usize, 2usize, 0usize, 0.5f64, scratch[..])
    if nce_error != ok || !near(nce, 0.1719931183659007f64, 0.000000000001f64) { os.exit(1i32) }
    let (_, nce_invalid) = loss.info_nce(anchor[..], candidates[..], 3usize, 2usize, 3usize, 0.5f64, scratch[..])
    if nce_invalid != loss.Invalid { os.exit(1i32) }
    let (_, nce_room) = loss.info_nce(anchor[..], candidates[..], 3usize, 2usize, 0usize, 0.5f64, scratch[..2usize])
    if nce_room != loss.TooSmall { os.exit(1i32) }
    let (hinge, hinge_error) = loss.triplet(anchor[..], candidates[..2usize], candidates[2usize..4usize], 2usize, 1.0f64)
    if hinge_error != ok || hinge != 0.0f64 { os.exit(1i32) }
    // Swapping positive and negative: 2 - 0.02 + 1.
    let (active, active_error) = loss.triplet(anchor[..], candidates[2usize..4usize], candidates[..2usize], 2usize, 1.0f64)
    if active_error != ok || !near(active, 2.98f64, 0.000000000001f64) { os.exit(1i32) }

    // 2: distillation.
    var teacher: [3]f64 = zero
    teacher[0usize] = 2.0f64
    teacher[1usize] = 1.0f64
    teacher[2usize] = 0.1f64
    var student: [3]f64 = zero
    student[0usize] = 1.0f64
    student[1usize] = 1.0f64
    student[2usize] = 1.0f64
    let (kl, kl_error) = loss.distillation_kl(teacher[..], student[..], 3usize, 2.0f64, scratch[..])
    if kl_error != ok || !near(kl, 0.28947344035967654f64, 0.000000000001f64) { os.exit(2i32) }
    let (same, same_error) = loss.distillation_kl(teacher[..], teacher[..], 3usize, 2.0f64, scratch[..])
    if same_error != ok || !near(same, 0.0f64, 0.000000000001f64) { os.exit(2i32) }
    let (_, kl_invalid) = loss.distillation_kl(teacher[..], student[..], 3usize, 0.0f64, scratch[..])
    if kl_invalid != loss.Invalid { os.exit(2i32) }

    // 3: CTC over four frames of three classes (blank 0).
    var logp: [12]f64 = zero
    var probs: [12]f64 = zero
    probs[0usize] = 0.6f64
    probs[1usize] = 0.3f64
    probs[2usize] = 0.1f64
    probs[3usize] = 0.2f64
    probs[4usize] = 0.5f64
    probs[5usize] = 0.3f64
    probs[6usize] = 0.1f64
    probs[7usize] = 0.2f64
    probs[8usize] = 0.7f64
    probs[9usize] = 0.5f64
    probs[10usize] = 0.3f64
    probs[11usize] = 0.2f64
    var i = 0usize
    while i < 12usize {
        logp[i] = math.log[f64](probs[i])
        i += 1usize
    }
    var labels: [2]usize = zero
    labels[0usize] = 1usize
    let (c1, c1_error) = loss.ctc(logp[..], 4usize, 3usize, 0usize, labels[..1usize], scratch[..])
    if c1_error != ok || !near(c1, 2.117766656001504f64, 0.000000001f64) { os.exit(3i32) }
    labels[1usize] = 2usize
    let (c2, c2_error) = loss.ctc(logp[..], 4usize, 3usize, 0usize, labels[..], scratch[..])
    if c2_error != ok || !near(c2, 1.10412746935622f64, 0.000000001f64) { os.exit(3i32) }
    labels[1usize] = 1usize
    let (c3, c3_error) = loss.ctc(logp[..], 4usize, 3usize, 0usize, labels[..], scratch[..])
    if c3_error != ok || !near(c3, 3.692887475511475f64, 0.000000001f64) { os.exit(3i32) }
    labels[0usize] = 2usize
    let (c4, c4_error) = loss.ctc(logp[..], 4usize, 3usize, 0usize, labels[..], scratch[..])
    if c4_error != ok || !near(c4, 2.0915141229141057f64, 0.000000001f64) { os.exit(3i32) }
    let (_, blank_label) = loss.ctc(logp[..], 4usize, 3usize, 1usize, labels[..], scratch[..])
    if blank_label != loss.Invalid { os.exit(3i32) }
    // Two repeated labels cannot fit in two frames (a blank must separate them).
    labels[0usize] = 1usize
    let (_, too_short) = loss.ctc(logp[..6usize], 2usize, 3usize, 0usize, labels[..], scratch[..])
    if too_short != loss.Invalid { os.exit(3i32) }
    let (_, ctc_room) = loss.ctc(logp[..], 4usize, 3usize, 0usize, labels[..], scratch[..5usize])
    if ctc_room != loss.TooSmall { os.exit(3i32) }

    try io.print("ml loss ok\n")
    ret ok
}
