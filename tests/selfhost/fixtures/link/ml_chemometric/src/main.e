// Chemometric extensions: PLS coefficients against a NIPALS reference with
// the degenerate cases, UMAP's PCA start against hand-computed values, a
// 200-epoch layout keeping two groups apart, and the storage and parameter
// cases. Each check exits with its own code.

use e.algo.rand
use e.mem
use e.ml.linear as linear
use e.ml.reduce as reduce
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn dist2(ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    let dx = ax - bx
    let dy = ay - by
    ret dx * dx + dy * dy
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [18]f64 = zero
    x[0usize] = 1.0f64
    x[1usize] = 2.0f64
    x[2usize] = 3.0f64
    x[3usize] = 2.0f64
    x[4usize] = 1.0f64
    x[5usize] = 4.0f64
    x[6usize] = 3.0f64
    x[7usize] = 4.0f64
    x[8usize] = 1.0f64
    x[9usize] = 4.0f64
    x[10usize] = 3.0f64
    x[11usize] = 2.0f64
    x[12usize] = 5.0f64
    x[13usize] = 1.0f64
    x[14usize] = 3.0f64
    x[15usize] = 1.0f64
    x[16usize] = 5.0f64
    x[17usize] = 2.0f64
    var y: [6]f64 = zero
    y[0usize] = 3.1f64
    y[1usize] = 4.2f64
    y[2usize] = 2.8f64
    y[3usize] = 5.1f64
    y[4usize] = 4.9f64
    y[5usize] = 3.7f64
    var coefficients: [4]f64 = zero
    var scratch: [64]f64 = zero

    // 1: PLS with two components.
    if linear.pls(x[..], y[..], 6usize, 3usize, 2usize, coefficients[..], scratch[..]) != ok { os.exit(1i32) }
    if !near(coefficients[0usize], 0.416009681447497f64, 0.000000001f64) { os.exit(1i32) }
    if !near(coefficients[1usize], 0.0f64 - 0.013223927775313615f64, 0.000000001f64) { os.exit(1i32) }
    if !near(coefficients[2usize], 0.14599915816356165f64, 0.000000001f64) { os.exit(1i32) }
    if !near(coefficients[3usize], 2.52757342813194f64, 0.000000001f64) { os.exit(1i32) }

    // 2: PLS degenerate and storage cases.
    if linear.pls(x[..], y[..], 6usize, 3usize, 0usize, coefficients[..], scratch[..]) != linear.Invalid { os.exit(21i32) }
    if linear.pls(x[..], y[..], 6usize, 3usize, 4usize, coefficients[..], scratch[..]) != linear.Invalid { os.exit(22i32) }
    if linear.pls(x[..], y[..], 6usize, 3usize, 2usize, coefficients[..], scratch[..10usize]) != linear.TooSmall { os.exit(23i32) }
    var flat: [6]f64 = zero
    var f = 0usize
    while f < 6usize {
        flat[f] = 1.0f64
        f += 1usize
    }
    if linear.pls(x[..], flat[..], 6usize, 3usize, 2usize, coefficients[..], scratch[..]) != ok { os.exit(24i32) }
    if !near(coefficients[0usize], 0.0f64, 0.000000001f64) { os.exit(24i32) }
    if !near(coefficients[1usize], 0.0f64, 0.000000001f64) { os.exit(24i32) }
    if !near(coefficients[2usize], 0.0f64, 0.000000001f64) { os.exit(24i32) }
    if !near(coefficients[3usize], 1.0f64, 0.000000001f64) { os.exit(24i32) }

    // 3: UMAP with zero epochs keeps the scaled PCA start.
    var points: [18]f64 = zero
    points[0usize] = 0.0f64
    points[1usize] = 0.0f64
    points[2usize] = 0.2f64
    points[3usize] = 0.1f64
    points[4usize] = 0.0f64 - 0.1f64
    points[5usize] = 0.2f64
    points[6usize] = 0.1f64
    points[7usize] = 0.0f64 - 0.2f64
    points[8usize] = 0.0f64 - 0.2f64
    points[9usize] = 0.0f64 - 0.1f64
    points[10usize] = 10.0f64
    points[11usize] = 0.0f64
    points[12usize] = 10.2f64
    points[13usize] = 0.1f64
    points[14usize] = 9.9f64
    points[15usize] = 0.0f64 - 0.1f64
    points[16usize] = 10.1f64
    points[17usize] = 0.2f64
    var layout: [18]f64 = zero
    var fscratch: [140]f64 = zero
    var iscratch: [27]usize = zero
    var rng = rand.pcg64(42u64, 54u64)
    if reduce.umap(points[..], 9usize, 2usize, 3usize, 1.576f64, 0.895f64, 0u32, 1.0f64, 5usize, layout[..], &rng, fscratch[..], iscratch[..]) != ok { os.exit(3i32) }
    if !near(layout[0usize], 0.0f64 - 4.807215900718377f64, 0.000000001f64) { os.exit(3i32) }
    if !near(layout[1usize], 0.0f64, 0.000000001f64) { os.exit(3i32) }
    if !near(layout[4usize], 0.0f64 - 4.902369292226967f64, 0.000000001f64) { os.exit(3i32) }
    if !near(layout[5usize], 5.0f64, 0.000000001f64) { os.exit(3i32) }
    if !near(layout[10usize], 4.8072159007183775f64, 0.000000001f64) { os.exit(3i32) }
    if !near(layout[11usize], 0.0f64 - 1.2850210539517555f64, 0.000000001f64) { os.exit(3i32) }

    // 4: two hundred epochs keep the two groups apart (squared distances, so
    // no square root is needed): each within-group diameter under 16 against
    // about 6.9 measured, and every cross-group gap above 36 against about
    // 72 measured, margins that absorb libm rounding across hosts.
    rng = rand.pcg64(42u64, 54u64)
    if reduce.umap(points[..], 9usize, 2usize, 3usize, 1.576f64, 0.895f64, 200u32, 1.0f64, 5usize, layout[..], &rng, fscratch[..], iscratch[..]) != ok { os.exit(4i32) }
    var worst = 0.0f64
    var p = 0usize
    while p < 5usize {
        var q = p + 1usize
        while q < 5usize {
            let gap = dist2(layout[2usize * p], layout[2usize * p + 1usize], layout[2usize * q], layout[2usize * q + 1usize])
            if gap > worst { worst = gap }
            q += 1usize
        }
        p += 1usize
    }
    p = 5usize
    while p < 9usize {
        var q = p + 1usize
        while q < 9usize {
            let gap = dist2(layout[2usize * p], layout[2usize * p + 1usize], layout[2usize * q], layout[2usize * q + 1usize])
            if gap > worst { worst = gap }
            q += 1usize
        }
        p += 1usize
    }
    if worst >= 16.0f64 { os.exit(4i32) }
    var best = dist2(layout[0usize], layout[1usize], layout[10usize], layout[11usize])
    p = 0usize
    while p < 5usize {
        var q = 5usize
        while q < 9usize {
            let gap = dist2(layout[2usize * p], layout[2usize * p + 1usize], layout[2usize * q], layout[2usize * q + 1usize])
            if gap < best { best = gap }
            q += 1usize
        }
        p += 1usize
    }
    if best <= 36.0f64 { os.exit(4i32) }

    // 5: UMAP parameter and storage cases.
    rng = rand.pcg64(42u64, 54u64)
    if reduce.umap(points[..], 9usize, 2usize, 1usize, 1.576f64, 0.895f64, 200u32, 1.0f64, 5usize, layout[..], &rng, fscratch[..], iscratch[..]) != reduce.Invalid { os.exit(5i32) }
    if reduce.umap(points[..6usize], 3usize, 2usize, 3usize, 1.576f64, 0.895f64, 200u32, 1.0f64, 5usize, layout[..6usize], &rng, fscratch[..], iscratch[..]) != reduce.Invalid { os.exit(5i32) }
    if reduce.umap(points[..], 9usize, 2usize, 3usize, 0.0f64, 0.895f64, 200u32, 1.0f64, 5usize, layout[..], &rng, fscratch[..], iscratch[..]) != reduce.Invalid { os.exit(5i32) }
    if reduce.umap(points[..], 9usize, 2usize, 3usize, 1.576f64, 0.895f64, 200u32, 1.0f64, 5usize, layout[..], &rng, fscratch[..10usize], iscratch[..]) != reduce.TooSmall { os.exit(5i32) }
    ret ok
}
