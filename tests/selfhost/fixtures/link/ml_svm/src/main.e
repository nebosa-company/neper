// `e.ml.svm`: the three kernels evaluate as written, SMO on two linearly
// separable squares finds scikit-learn's maximum-margin boundary (x + y = 4
// with the two nearest points as support vectors), an RBF machine learns
// XOR, and the argument checks answer. Each check exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.ml.svm
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [16]f64 = zero
    x[2usize] = 1.0f64
    x[5usize] = 1.0f64
    x[6usize] = 1.0f64
    x[7usize] = 1.0f64
    x[8usize] = 3.0f64
    x[9usize] = 3.0f64
    x[10usize] = 4.0f64
    x[11usize] = 3.0f64
    x[12usize] = 3.0f64
    x[13usize] = 4.0f64
    x[14usize] = 4.0f64
    x[15usize] = 4.0f64
    var y: [8]f64 = zero
    var i = 0usize
    while i < 8usize {
        y[i] = 0.0f64 - 1.0f64
        if i >= 4usize { y[i] = 1.0f64 }
        i += 1usize
    }

    // 1: kernels.
    let linear = svm.Kernel { kind: .Linear, gamma: 0.0f64, degree: 0.0f64, offset: 0.0f64 }
    let poly = svm.Kernel { kind: .Polynomial, gamma: 0.0f64, degree: 2.0f64, offset: 1.0f64 }
    let rbf = svm.Kernel { kind: .Rbf, gamma: 0.5f64, degree: 0.0f64, offset: 0.0f64 }
    if svm.kernel(linear, x[..], 2usize, 3usize, x[..], 7usize) != 8.0f64 { os.exit(1i32) }
    if svm.kernel(poly, x[..], 2usize, 3usize, x[..], 7usize) != 81.0f64 { os.exit(1i32) }
    if !near(svm.kernel(rbf, x[..], 2usize, 0usize, x[..], 3usize), 0.36787944117144233f64, 0.000000000001f64) { os.exit(1i32) }
    if svm.kernel(rbf, x[..], 2usize, 5usize, x[..], 5usize) != 1.0f64 { os.exit(1i32) }

    // 2: a linear machine on two squares.
    var r = rand.pcg64(3u64, 3u64)
    var alphas: [8]f64 = zero
    let (m, sweeps, smo_error) = svm.smo(x[..], y[..], 8usize, 2usize, linear, 1.0f64, 0.001f64, 10u32, 500u32, &r, alphas[..])
    if smo_error != ok || sweeps == 500u32 { os.exit(2i32) }
    // The support vectors are (1, 1) and (3, 3) with multipliers 0.25; the boundary is x + y = 4.
    if !near(alphas[3usize], 0.25f64, 0.01f64) || !near(alphas[4usize], 0.25f64, 0.01f64) || alphas[0usize] > 0.01f64 || alphas[7usize] > 0.01f64 { os.exit(2i32) }
    if !near(m.bias, 0.0f64 - 2.0f64, 0.05f64) { os.exit(2i32) }
    var q: [6]f64 = zero
    q[0usize] = 2.0f64
    q[1usize] = 2.0f64
    q[2usize] = 0.5f64
    q[3usize] = 0.5f64
    q[4usize] = 3.5f64
    q[5usize] = 3.5f64
    if !near(svm.decide(&m, x[..], y[..], 8usize, 2usize, q[..], 0usize), 0.0f64, 0.05f64) { os.exit(2i32) }
    if svm.decide(&m, x[..], y[..], 8usize, 2usize, q[..], 1usize) >= 0.0f64 - 0.9f64 || svm.decide(&m, x[..], y[..], 8usize, 2usize, q[..], 2usize) <= 0.9f64 { os.exit(2i32) }
    i = 0usize
    while i < 8usize {
        if svm.decide(&m, x[..], y[..], 8usize, 2usize, x[..], i) * y[i] <= 0.0f64 { os.exit(2i32) }
        i += 1usize
    }

    // 3: XOR with the RBF kernel.
    var xx: [16]f64 = zero
    xx[2usize] = 1.0f64
    xx[3usize] = 1.0f64
    xx[5usize] = 1.0f64
    xx[6usize] = 1.0f64
    xx[8usize] = 0.1f64
    xx[9usize] = 0.1f64
    xx[10usize] = 0.9f64
    xx[11usize] = 0.9f64
    xx[12usize] = 0.1f64
    xx[13usize] = 0.9f64
    xx[14usize] = 0.9f64
    xx[15usize] = 0.1f64
    var yx: [8]f64 = zero
    yx[0usize] = 0.0f64 - 1.0f64
    yx[1usize] = 0.0f64 - 1.0f64
    yx[2usize] = 1.0f64
    yx[3usize] = 1.0f64
    yx[4usize] = 0.0f64 - 1.0f64
    yx[5usize] = 0.0f64 - 1.0f64
    yx[6usize] = 1.0f64
    yx[7usize] = 1.0f64
    let gaussian = svm.Kernel { kind: .Rbf, gamma: 1.0f64, degree: 0.0f64, offset: 0.0f64 }
    let (mx, _, xor_error) = svm.smo(xx[..], yx[..], 8usize, 2usize, gaussian, 10.0f64, 0.001f64, 10u32, 2000u32, &r, alphas[..])
    if xor_error != ok { os.exit(3i32) }
    i = 0usize
    while i < 8usize {
        if svm.decide(&mx, xx[..], yx[..], 8usize, 2usize, xx[..], i) * yx[i] <= 0.0f64 { os.exit(3i32) }
        i += 1usize
    }
    q[0usize] = 0.2f64
    q[1usize] = 0.2f64
    q[2usize] = 0.2f64
    q[3usize] = 0.8f64
    if svm.decide(&mx, xx[..], yx[..], 8usize, 2usize, q[..], 0usize) >= 0.0f64 || svm.decide(&mx, xx[..], yx[..], 8usize, 2usize, q[..], 1usize) <= 0.0f64 { os.exit(3i32) }
    // A linear machine cannot separate XOR: some training point stays on the wrong side.
    let (ml, _, linear_xor) = svm.smo(xx[..], yx[..], 8usize, 2usize, linear, 10.0f64, 0.001f64, 5u32, 200u32, &r, alphas[..])
    if linear_xor != ok { os.exit(3i32) }
    var wrong = 0usize
    i = 0usize
    while i < 8usize {
        if svm.decide(&ml, xx[..], yx[..], 8usize, 2usize, xx[..], i) * yx[i] <= 0.0f64 { wrong += 1usize }
        i += 1usize
    }
    if wrong == 0usize { os.exit(3i32) }
    y[0usize] = 0.5f64
    let (_, _, bad_label) = svm.smo(x[..], y[..], 8usize, 2usize, linear, 1.0f64, 0.001f64, 10u32, 500u32, &r, alphas[..])
    if bad_label != svm.Invalid { os.exit(3i32) }
    y[0usize] = 0.0f64 - 1.0f64
    let (_, _, no_box) = svm.smo(x[..], y[..], 8usize, 2usize, linear, 0.0f64, 0.001f64, 10u32, 500u32, &r, alphas[..])
    if no_box != svm.Invalid { os.exit(3i32) }
    let (_, _, room) = svm.smo(x[..], y[..], 8usize, 2usize, linear, 1.0f64, 0.001f64, 10u32, 500u32, &r, alphas[..4usize])
    if room != svm.TooSmall { os.exit(3i32) }

    try io.print("ml svm ok\n")
    ret ok
}
