// `e.gfx.vision` total-least-squares lines: an exact slope, a vertical line
// OLS cannot touch, one outlier-rejection pass recovering y = x, distances,
// and every refusal. Each check exits with its own code.

use e.gfx.vision
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn abs(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: y = 2x + 1 through five exact points aims along (1, 2).
    var pts: [5]vision.Point = zero
    var i = 0usize
    while i < 5usize {
        pts[i] = vision.Point { x: f64(i), y: 2.0f64 * f64(i) + 1.0f64 }
        i += 1usize
    }
    let (fit, fit_error) = vision.fit_line_tls(pts[..], 5usize)
    if fit_error != ok { os.exit(1i32) }
    if !near(fit.point.x, 2.0f64, 0.000000001f64) || !near(fit.point.y, 5.0f64, 0.000000001f64) { os.exit(1i32) }
    if !near(abs(fit.direction.x), 0.4472135955f64, 0.000000001f64) { os.exit(1i32) }
    if !near(abs(fit.direction.y), 0.894427191f64, 0.000000001f64) { os.exit(1i32) }
    if !near(vision.tls_distance(fit, pts[2usize]), 0.0f64, 0.000000001f64) { os.exit(1i32) }

    // 2: the vertical x = 3 aims along (0, 1).
    var vert: [3]vision.Point = zero
    vert[0usize] = vision.Point { x: 3.0f64, y: 0.0f64 }
    vert[1usize] = vision.Point { x: 3.0f64, y: 2.0f64 }
    vert[2usize] = vision.Point { x: 3.0f64, y: 5.0f64 }
    let (vfit, vfit_error) = vision.fit_line_tls(vert[..], 3usize)
    if vfit_error != ok { os.exit(2i32) }
    if !near(abs(vfit.direction.x), 0.0f64, 0.000000001f64) { os.exit(2i32) }
    if !near(abs(vfit.direction.y), 1.0f64, 0.000000001f64) { os.exit(2i32) }
    if !near(vfit.point.x, 3.0f64, 0.000000001f64) { os.exit(2i32) }

    // 3: eight points of y = x plus (3.5, 10): the pass drops the outlier
    // and returns the diagonal.
    var noisy: [9]vision.Point = zero
    i = 0usize
    while i < 8usize {
        noisy[i] = vision.Point { x: f64(i), y: f64(i) }
        i += 1usize
    }
    noisy[8usize] = vision.Point { x: 3.5f64, y: 10.0f64 }
    var flags: [9]bool = zero
    var rfit: vision.TlsLine = zero
    let (kept, robust_error) = vision.fit_line_tls_robust(noisy[..], 9usize, 1.8f64, &rfit, flags[..])
    if robust_error != ok || kept != 8usize { os.exit(3i32) }
    if flags[8usize] { os.exit(3i32) }
    if !near(abs(rfit.direction.x), 0.707106781187f64, 0.000000001f64) { os.exit(3i32) }
    if !near(abs(rfit.direction.y), 0.707106781187f64, 0.000000001f64) { os.exit(3i32) }

    // 4: the refusals -- one point, identical points, a dead threshold, a
    // pass that keeps nobody, and short storage.
    let (_, single) = vision.fit_line_tls(pts[..1usize], 1usize)
    if single != vision.Invalid { os.exit(4i32) }
    var same: [3]vision.Point = zero
    same[0usize] = vision.Point { x: 1.0f64, y: 1.0f64 }
    same[1usize] = vision.Point { x: 1.0f64, y: 1.0f64 }
    same[2usize] = vision.Point { x: 1.0f64, y: 1.0f64 }
    let (_, flat) = vision.fit_line_tls(same[..], 3usize)
    if flat != vision.Invalid { os.exit(4i32) }
    var rfit2: vision.TlsLine = zero
    let (_, dead) = vision.fit_line_tls_robust(noisy[..], 6usize, 0.0f64, &rfit2, flags[..])
    if dead != vision.Invalid { os.exit(4i32) }
    let (_, wiped) = vision.fit_line_tls_robust(noisy[..], 9usize, 0.000000001f64, &rfit2, flags[..])
    if wiped != vision.Invalid { os.exit(4i32) }
    let (_, short) = vision.fit_line_tls(pts[..], 6usize)
    if short != vision.TooSmall { os.exit(4i32) }

    try io.print("gfx vision tls ok\n")
    ret ok
}
