// `e.algo.stat.gbmpkg`: gaussian boosting of a step function that is worked out by hand.
// y = 0, 0, 10, 10 on x = 1..4, one split of depth 1, shrinkage 0.5: the start is the mean 5,
// the first tree's leaves move by -5 and +5 times 0.5, the second by -2.5 and +2.5 times 0.5 again, away from the mean: 1.25 and 8.75.
// Also the recorded trees (split count, leaf, variable, threshold midpoint, start), predict at
// new rows with one and two trees, and the relative influence of a useless and a useful variable.
// Every check has its own exit code.
use e.os
use e.mem
use e.algo.stat.gbmpkg as gbm

fn near(a: f64, b: f64) -> bool {
    var d = a - b
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.000000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [4]f64 = [4]f64{ 1.0, 2.0, 3.0, 4.0 }
    var y: [4]f64 = [4]f64{ 0.0, 0.0, 10.0, 10.0 }
    var fitted: [4]f64 = zero
    var rec: [13]f64 = zero
    let e1 = gbm.gaussian_model(a, x[0..], y[0..], 4usize, 1usize, 2usize, 0.5f64, 1usize, 1usize, fitted[0..], rec[0..])
    if e1 != ok { os.exit(1) }
    if !near(fitted[0], 1.25f64) || !near(fitted[1], 1.25f64) { os.exit(2) }
    if !near(fitted[2], 8.75f64) || !near(fitted[3], 8.75f64) { os.exit(3) }
    // tree 0: one split on leaf 0, variable 0, at the midpoint of 2 and 3
    if !near(rec[0], 1.0f64) || !near(rec[1], 0.0f64) || !near(rec[2], 0.0f64) || !near(rec[3], 2.5f64) { os.exit(4) }
    if !near(rec[12], 5.0f64) { os.exit(5) }
    var xnew: [2]f64 = [2]f64{ 1.5, 3.5 }
    var out: [2]f64 = zero
    gbm.predict_model(rec[0..], 2usize, 1usize, 1usize, xnew[0..], 2usize, out[0..])
    if !near(out[0], 2.5f64) || !near(out[1], 7.5f64) { os.exit(6) }
    gbm.predict_model(rec[0..], 2usize, 1usize, 2usize, xnew[0..], 2usize, out[0..])
    if !near(out[0], 1.25f64) || !near(out[1], 8.75f64) { os.exit(7) }
    // two variables, column-major: the first cannot separate y, the second can
    var x2: [8]f64 = [8]f64{ 1.0, 2.0, 1.0, 2.0, 1.0, 2.0, 3.0, 4.0 }
    var fitted2: [4]f64 = zero
    var inf: [2]f64 = zero
    let e2 = gbm.gaussian_influence(a, x2[0..], y[0..], 4usize, 2usize, 1usize, 0.5f64, 1usize, 1usize, fitted2[0..], inf[0..])
    if e2 != ok { os.exit(8) }
    if !near(inf[0], 0.0f64) || !near(inf[1], 100.0f64) { os.exit(9) }
    ret ok
}
