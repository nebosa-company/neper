// `e.ml.nn`: the perceptron separates two groups in a few epochs, the
// autodiff tape differentiates a small expression (against derivatives by
// hand), attention and its causal form match a NumPy computation, a
// two-head attention over identity projections reduces to the single-head
// one, and rotary embedding rotates pairs as written. Each check exits with
// its own code.

use e.io
use e.mem
use e.ml.nn
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: the perceptron.
    var x: [8]f64 = zero
    x[0usize] = 0.0f64
    x[1usize] = 0.0f64
    x[2usize] = 1.0f64
    x[3usize] = 0.0f64
    x[4usize] = 3.0f64
    x[5usize] = 3.0f64
    x[6usize] = 4.0f64
    x[7usize] = 2.0f64
    var y: [4]f64 = zero
    y[0usize] = 0.0f64 - 1.0f64
    y[1usize] = 0.0f64 - 1.0f64
    y[2usize] = 1.0f64
    y[3usize] = 1.0f64
    var w: [3]f64 = zero
    var epochs = 0usize
    var mistakes = 1usize
    while mistakes > 0usize && epochs < 100usize {
        let (m, epoch_error) = nn.perceptron_epoch(x[..], y[..], 4usize, 2usize, w[..], 0.5f64)
        if epoch_error != ok { os.exit(1i32) }
        mistakes = m
        epochs += 1usize
    }
    if mistakes != 0usize || epochs > 20usize || nn.perceptron_predict(x[..2usize], w[..]) != 0.0f64 - 1.0f64 || nn.perceptron_predict(x[4usize..6usize], w[..]) != 1.0f64 { os.exit(1i32) }
    let (_, room) = nn.perceptron_epoch(x[..], y[..], 4usize, 2usize, w[..2usize], 0.5f64)
    if room != nn.TooSmall { os.exit(1i32) }

    // 2: autodiff of f(a, b) = tanh(a * b + exp(a)) / b at a = 0.5, b = 2.
    var ops: [16]nn.Op = zero
    var left: [16]usize = zero
    var right: [16]usize = zero
    var value: [16]f64 = zero
    var gradient: [16]f64 = zero
    var t = nn.tape(ops[..], left[..], right[..], value[..], gradient[..])
    let (ia, _) = nn.input(&t, 0.5f64)
    let (ib, _) = nn.input(&t, 2.0f64)
    let (ab, _) = nn.mul(&t, ia, ib)
    let (ea, _) = nn.exp(&t, ia)
    let (sum, _) = nn.add(&t, ab, ea)
    let (th, _) = nn.tanh(&t, sum)
    let (f, f_error) = nn.div(&t, th, ib)
    if f_error != ok || t.count != 7usize { os.exit(2i32) }
    // sum = 1 + e^0.5 = 2.6487; tanh = 0.99004; f = 0.4950205.
    if !near(t.value[f], 0.4950205430355286f64, 0.000000001f64) { os.exit(2i32) }
    if nn.backward(&t, f) != ok { os.exit(2i32) }
    // df/da = (1 - tanh²)(b + e^a) / b; df/db = (1 - tanh²) a / b - tanh / b².
    let sech2 = 1.0f64 - t.value[th] * t.value[th]
    if !near(t.gradient[ia], sech2 * (2.0f64 + 1.6487212707001282f64) / 2.0f64, 0.000000001f64) { os.exit(2i32) }
    if !near(t.gradient[ib], sech2 * 0.5f64 / 2.0f64 - t.value[th] / 4.0f64, 0.000000001f64) { os.exit(2i32) }
    if nn.backward(&t, 9usize) != nn.Invalid { os.exit(2i32) }
    let (r1, _) = nn.relu(&t, ia)
    let (n1, _) = nn.neg(&t, ib)
    let (r2, _) = nn.relu(&t, n1)
    let (s1, _) = nn.sigmoid(&t, ia)
    let (l1, _) = nn.log(&t, ib)
    let (d1, _) = nn.sub(&t, r1, r2)
    let (d2, d2_error) = nn.add(&t, d1, s1)
    let (d3, d3_error) = nn.add(&t, d2, l1)
    if d2_error != ok || d3_error != ok || nn.backward(&t, d3) != ok { os.exit(2i32) }
    // d/da = 1 (relu) + sigmoid(0.5)(1 - sigmoid(0.5)); d/db = 0 (relu of -2) + 1/2.
    if !near(t.gradient[ia], 1.0f64 + 0.6224593312018546f64 * 0.3775406687981454f64, 0.000000001f64) || !near(t.gradient[ib], 0.5f64, 0.000000001f64) { os.exit(2i32) }
    var small_ops: [2]nn.Op = zero
    var small = nn.tape(small_ops[..], left[..], right[..], value[..], gradient[..])
    let (_, _) = nn.input(&small, 1.0f64)
    let (_, _) = nn.input(&small, 1.0f64)
    let (_, full) = nn.input(&small, 1.0f64)
    if full != nn.TooSmall { os.exit(2i32) }

    // 3: attention.
    var q: [4]f64 = zero
    q[0usize] = 1.0f64
    q[3usize] = 1.0f64
    var k: [6]f64 = zero
    k[0usize] = 1.0f64
    k[3usize] = 1.0f64
    k[4usize] = 1.0f64
    k[5usize] = 1.0f64
    var v: [6]f64 = zero
    var i = 0usize
    while i < 6usize {
        v[i] = f64(i + 1usize)
        i += 1usize
    }
    var out: [8]f64 = zero
    var scratch: [64]f64 = zero
    if nn.attention(q[..], k[..], v[..], 2usize, 3usize, 2usize, 2usize, false, out[..], scratch[..]) != ok { os.exit(3i32) }
    if !near(out[0usize], 3.0f64, 0.000000001f64) || !near(out[1usize], 4.0f64, 0.000000001f64) || !near(out[2usize], 3.40667256f64, 0.00000001f64) || !near(out[3usize], 4.40667256f64, 0.00000001f64) { os.exit(3i32) }
    if nn.attention(q[..], k[..], v[..], 2usize, 3usize, 2usize, 2usize, true, out[..], scratch[..]) != ok { os.exit(3i32) }
    if !near(out[0usize], 1.0f64, 0.000000001f64) || !near(out[2usize], 2.3395231f64, 0.0000001f64) || !near(out[3usize], 3.3395231f64, 0.0000001f64) { os.exit(3i32) }
    if nn.attention(q[..], k[..], v[..], 2usize, 3usize, 2usize, 2usize, false, out[..], scratch[..2usize]) != nn.TooSmall { os.exit(3i32) }
    // Two heads over identity projections of a 2 x 4 input: each head attends over its half.
    var xin: [8]f64 = zero
    xin[0usize] = 1.0f64
    xin[3usize] = 1.0f64
    xin[5usize] = 1.0f64
    xin[6usize] = 1.0f64
    var identity: [16]f64 = zero
    i = 0usize
    while i < 4usize {
        identity[i * 4usize + i] = 1.0f64
        i += 1usize
    }
    if nn.multi_head_attention(xin[..], 2usize, 4usize, 2usize, identity[..], identity[..], identity[..], identity[..], false, out[..], scratch[..]) != ok { os.exit(3i32) }
    // Head 0 sees rows (1, 0) and (0, 1); head 1 sees the same rows swapped, so its
    // output rows are the single-head rows swapped.
    var single: [4]f64 = zero
    var half_q: [4]f64 = zero
    half_q[0usize] = 1.0f64
    half_q[3usize] = 1.0f64
    if nn.attention(half_q[..], half_q[..], half_q[..], 2usize, 2usize, 2usize, 2usize, false, single[..], scratch[..]) != ok { os.exit(3i32) }
    if !near(out[0usize], single[0usize], 0.000000001f64) || !near(out[1usize], single[1usize], 0.000000001f64) || !near(out[2usize], single[2usize], 0.000000001f64) || !near(out[3usize], single[3usize], 0.000000001f64) { os.exit(3i32) }
    if !near(out[4usize], single[2usize], 0.000000001f64) || !near(out[5usize], single[3usize], 0.000000001f64) || !near(out[6usize], single[0usize], 0.000000001f64) || !near(out[7usize], single[1usize], 0.000000001f64) { os.exit(3i32) }
    if nn.multi_head_attention(xin[..], 2usize, 4usize, 3usize, identity[..], identity[..], identity[..], identity[..], false, out[..], scratch[..]) != nn.Invalid { os.exit(3i32) }

    // 4: rotary embedding.
    var vec: [4]f64 = zero
    vec[0usize] = 1.0f64
    vec[2usize] = 1.0f64
    if nn.rope(vec[..], 3u64, 10000.0f64) != ok { os.exit(4i32) }
    if !near(vec[0usize], 0.0f64 - 0.9899925f64, 0.0000001f64) || !near(vec[1usize], 0.14112001f64, 0.0000001f64) || !near(vec[2usize], 0.99955003f64, 0.0000001f64) || !near(vec[3usize], 0.0299955f64, 0.0000001f64) { os.exit(4i32) }
    if nn.rope(vec[..3usize], 3u64, 10000.0f64) != nn.Invalid { os.exit(4i32) }
    vec[0usize] = 1.0f64
    vec[1usize] = 0.0f64
    if nn.rope(vec[..2usize], 0u64, 10000.0f64) != ok || vec[0usize] != 1.0f64 || vec[1usize] != 0.0f64 { os.exit(4i32) }

    try io.print("ml nn ok\n")
    ret ok
}
