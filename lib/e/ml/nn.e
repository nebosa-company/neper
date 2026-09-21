// Neural network pieces over `f64` vectors and row-major matrices in caller
// storage: the perceptron rule, a scalar reverse-mode autodiff tape
// (`Tape` records every operation; `backward` fills the gradients),
// scaled dot-product attention, multi-head attention over caller
// projection matrices, and rotary position embedding.

use e.math

type Op = enum u8 { Input, Add, Sub, Mul, Div, Neg, Exp, Log, Tanh, Relu, Sigmoid }
type Tape = struct { op: []Op, left: []usize, right: []usize, value: []f64, gradient: []f64, count: usize }
error TooSmall
error Invalid

// One perceptron epoch over `x` (`n × d`) with labels `y` in {-1, +1}:
// `weights` (`d + 1`, bias last) move by `rate y x` on each mistake.
// Answers the mistakes made.
fn perceptron_epoch(x: []const f64, y: []const f64, n: usize, d: usize, weights: []f64, rate: f64) -> (usize, err) {
    if x.len < n * d || y.len < n || weights.len < d + 1usize { ret (0usize, TooSmall) }
    var mistakes = 0usize
    var i = 0usize
    while i < n {
        if perceptron_predict(x[i * d..(i + 1usize) * d], weights) != y[i] {
            var j = 0usize
            while j < d {
                weights[j] += rate * y[i] * x[i * d + j]
                j += 1usize
            }
            weights[d] += rate * y[i]
            mistakes += 1usize
        }
        i += 1usize
    }
    ret (mistakes, ok)
}

// `+1` when `w·x + b >= 0`, else `-1`.
fn perceptron_predict(sample: []const f64, weights: []f64) -> f64 {
    let d = sample.len
    var s = weights[d]
    var j = 0usize
    while j < d {
        s += weights[j] * sample[j]
        j += 1usize
    }
    if s >= 0.0f64 { ret 1.0f64 }
    ret 0.0f64 - 1.0f64
}

// A tape over caller arrays of one capacity each.
fn tape(op: []Op, left: []usize, right: []usize, value: []f64, gradient: []f64) -> Tape {
    ret Tape { op: op, left: left, right: right, value: value, gradient: gradient, count: 0usize }
}

fn record(t: *Tape, op: Op, left: usize, right: usize, value: f64) -> (usize, err) {
    if t.count >= t.op.len || t.count >= t.left.len || t.count >= t.right.len || t.count >= t.value.len || t.count >= t.gradient.len { ret (0usize, TooSmall) }
    let id = t.count
    t.op[id] = op
    t.left[id] = left
    t.right[id] = right
    t.value[id] = value
    t.count += 1usize
    ret (id, ok)
}

// A leaf holding `value`; answers its node id.
fn input(t: *Tape, value: f64) -> (usize, err) {
    let (id, record_error) = record(t, .Input, 0usize, 0usize, value)
    ret (id, record_error)
}
fn add(t: *Tape, a: usize, b: usize) -> (usize, err) {
    let (id, record_error) = record(t, .Add, a, b, t.value[a] + t.value[b])
    ret (id, record_error)
}
fn sub(t: *Tape, a: usize, b: usize) -> (usize, err) {
    let (id, record_error) = record(t, .Sub, a, b, t.value[a] - t.value[b])
    ret (id, record_error)
}
fn mul(t: *Tape, a: usize, b: usize) -> (usize, err) {
    let (id, record_error) = record(t, .Mul, a, b, t.value[a] * t.value[b])
    ret (id, record_error)
}
fn div(t: *Tape, a: usize, b: usize) -> (usize, err) {
    let (id, record_error) = record(t, .Div, a, b, t.value[a] / t.value[b])
    ret (id, record_error)
}
fn neg(t: *Tape, a: usize) -> (usize, err) {
    let (id, record_error) = record(t, .Neg, a, 0usize, 0.0f64 - t.value[a])
    ret (id, record_error)
}
fn exp(t: *Tape, a: usize) -> (usize, err) {
    let (id, record_error) = record(t, .Exp, a, 0usize, math.exp[f64](t.value[a]))
    ret (id, record_error)
}
fn log(t: *Tape, a: usize) -> (usize, err) {
    let (id, record_error) = record(t, .Log, a, 0usize, math.log[f64](t.value[a]))
    ret (id, record_error)
}
fn tanh(t: *Tape, a: usize) -> (usize, err) {
    let e2 = math.exp[f64](2.0f64 * t.value[a])
    let (id, record_error) = record(t, .Tanh, a, 0usize, (e2 - 1.0f64) / (e2 + 1.0f64))
    ret (id, record_error)
}
fn relu(t: *Tape, a: usize) -> (usize, err) {
    var v = t.value[a]
    if v < 0.0f64 { v = 0.0f64 }
    let (id, record_error) = record(t, .Relu, a, 0usize, v)
    ret (id, record_error)
}
fn sigmoid(t: *Tape, a: usize) -> (usize, err) {
    let (id, record_error) = record(t, .Sigmoid, a, 0usize, 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t.value[a])))
    ret (id, record_error)
}

// Reverse-mode pass from node `root`: `gradient[i]` becomes d root / d node i.
fn backward(t: *Tape, root: usize) -> err {
    if root >= t.count { ret Invalid }
    var i = 0usize
    while i < t.count {
        t.gradient[i] = 0.0f64
        i += 1usize
    }
    t.gradient[root] = 1.0f64
    i = t.count
    while i > 0usize {
        i -= 1usize
        let g = t.gradient[i]
        let a = t.left[i]
        let b = t.right[i]
        let op = t.op[i]
        if op == .Add {
            t.gradient[a] += g
            t.gradient[b] += g
        } else if op == .Sub {
            t.gradient[a] += g
            t.gradient[b] -= g
        } else if op == .Mul {
            t.gradient[a] += g * t.value[b]
            t.gradient[b] += g * t.value[a]
        } else if op == .Div {
            t.gradient[a] += g / t.value[b]
            t.gradient[b] -= g * t.value[a] / (t.value[b] * t.value[b])
        } else if op == .Neg {
            t.gradient[a] -= g
        } else if op == .Exp {
            t.gradient[a] += g * t.value[i]
        } else if op == .Log {
            t.gradient[a] += g / t.value[a]
        } else if op == .Tanh {
            t.gradient[a] += g * (1.0f64 - t.value[i] * t.value[i])
        } else if op == .Relu {
            if t.value[a] > 0.0f64 { t.gradient[a] += g }
        } else if op == .Sigmoid {
            t.gradient[a] += g * t.value[i] * (1.0f64 - t.value[i])
        }
    }
    ret ok
}

// Scaled dot-product attention: `queries` (`n × d`), `keys` (`m × d`),
// `values` (`m × dv`) give `out` (`n × dv`); `scratch.len >= m` holds one
// row of weights. With `causal`, query `i` sees keys `0..=i` only.
fn attention(queries: []const f64, keys: []const f64, values: []const f64, n: usize, m: usize, d: usize, dv: usize, causal: bool, out: []f64, scratch: []f64) -> err {
    if queries.len < n * d || keys.len < m * d || values.len < m * dv || out.len < n * dv || scratch.len < m { ret TooSmall }
    if d == 0usize { ret Invalid }
    let scale = 1.0f64 / math.sqrt[f64](f64(d))
    var i = 0usize
    while i < n {
        var visible = m
        if causal && i + 1usize < m { visible = i + 1usize }
        var largest = 0.0f64
        var j = 0usize
        while j < visible {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += queries[i * d + k] * keys[j * d + k]
                k += 1usize
            }
            scratch[j] = s * scale
            if j == 0usize || scratch[j] > largest { largest = scratch[j] }
            j += 1usize
        }
        var total = 0.0f64
        j = 0usize
        while j < visible {
            scratch[j] = math.exp[f64](scratch[j] - largest)
            total += scratch[j]
            j += 1usize
        }
        var c = 0usize
        while c < dv {
            var s = 0.0f64
            j = 0usize
            while j < visible {
                s += scratch[j] / total * values[j * dv + c]
                j += 1usize
            }
            out[i * dv + c] = s
            c += 1usize
        }
        i += 1usize
    }
    ret ok
}

// `out = x · w` for `x` (`n × d`) and `w` (`d × e`).
fn matmul(x: []const f64, w: []const f64, n: usize, d: usize, e: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < e {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += x[i * d + k] * w[k * e + c]
                k += 1usize
            }
            out[i * e + c] = s
            c += 1usize
        }
        i += 1usize
    }
}

// Multi-head attention: `x` (`n × d`) is projected by `wq`, `wk`, `wv`
// (`d × d` each, the columns split into `heads` of `d / heads`), each head
// attends, the heads concatenate and `wo` (`d × d`) projects the result into
// `out` (`n × d`). `scratch.len >= 7 * n * d + n`.
fn multi_head_attention(x: []const f64, n: usize, d: usize, heads: usize, wq: []const f64, wk: []const f64, wv: []const f64, wo: []const f64, causal: bool, out: []f64, scratch: []f64) -> err {
    if x.len < n * d || wq.len < d * d || wk.len < d * d || wv.len < d * d || wo.len < d * d || out.len < n * d || scratch.len < 7usize * n * d + n { ret TooSmall }
    if heads == 0usize || d % heads != 0usize { ret Invalid }
    let hd = d / heads
    var q = scratch[..n * d]
    var k = scratch[n * d..2usize * n * d]
    var v = scratch[2usize * n * d..3usize * n * d]
    var mixed = scratch[3usize * n * d..4usize * n * d]
    var weights = scratch[4usize * n * d..4usize * n * d + n]
    var gathered = scratch[4usize * n * d + n..7usize * n * d + n]
    matmul(x, wq, n, d, d, q)
    matmul(x, wk, n, d, d, k)
    matmul(x, wv, n, d, d, v)
    // Each head works on its column block; gather it, attend, scatter back.
    var h = 0usize
    while h < heads {
        // Gather the head's column block of q, k and v into contiguous rows.
        var i = 0usize
        while i < n {
            var c = 0usize
            while c < hd {
                gathered[i * hd + c] = q[i * d + h * hd + c]
                gathered[n * hd + i * hd + c] = k[i * d + h * hd + c]
                gathered[2usize * n * hd + i * hd + c] = v[i * d + h * hd + c]
                c += 1usize
            }
            i += 1usize
        }
        let head_error = attention(gathered[..n * hd], gathered[n * hd..2usize * n * hd], gathered[2usize * n * hd..3usize * n * hd], n, n, hd, hd, causal, mixed[..n * hd], weights)
        if head_error != ok { ret head_error }
        // The head's rows are contiguous in mixed[..n * hd]; move them to their columns of q (reused).
        i = 0usize
        while i < n {
            var c = 0usize
            while c < hd {
                q[i * d + h * hd + c] = mixed[i * hd + c]
                c += 1usize
            }
            i += 1usize
        }
        h += 1usize
    }
    matmul(q, wo, n, d, d, out)
    ret ok
}

// Rotary position embedding of `x` (even length) at position `p`: each pair
// `(x[2i], x[2i + 1])` rotates by `p · base^(-2i / len)`.
fn rope(x: []f64, p: u64, base: f64) -> err {
    let d = x.len
    if d % 2usize != 0usize || base <= 0.0f64 { ret Invalid }
    var i = 0usize
    while i < d / 2usize {
        let theta = f64(p) * math.pow[f64](base, 0.0f64 - f64(2usize * i) / f64(d))
        let c = math.cos[f64](theta)
        let s = math.sin[f64](theta)
        let a = x[2usize * i]
        let b = x[2usize * i + 1usize]
        x[2usize * i] = a * c - b * s
        x[2usize * i + 1usize] = a * s + b * c
        i += 1usize
    }
    ret ok
}
