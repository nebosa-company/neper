// Support vector classification over row-major `f64` samples in caller
// storage: `kernel` evaluates the linear, polynomial `(x·y + c)^degree` or
// RBF `exp(-gamma |x - y|^2)` kernel of two samples, `smo` trains the dual
// (labels `±1`) by the simplified sequential minimal optimisation with a
// random partner per violating multiplier, and `decide` evaluates the
// kernel expansion over the support vectors.

use e.algo.rand
use e.math

type Kind = enum u8 { Linear, Polynomial, Rbf }
type Kernel = struct { kind: Kind, gamma: f64, degree: f64, offset: f64 }
type Model = struct { alphas: []f64, bias: f64, kernel: Kernel }
error TooSmall
error Invalid

fn kernel(k: Kernel, x: []const f64, d: usize, i: usize, y: []const f64, j: usize) -> f64 {
    if k.kind == .Rbf {
        var sum = 0.0f64
        var m = 0usize
        while m < d {
            let t = x[i * d + m] - y[j * d + m]
            sum += t * t
            m += 1usize
        }
        ret math.exp[f64](0.0f64 - k.gamma * sum)
    }
    var dot = 0.0f64
    var m = 0usize
    while m < d {
        dot += x[i * d + m] * y[j * d + m]
        m += 1usize
    }
    if k.kind == .Linear { ret dot }
    ret math.pow[f64](dot + k.offset, k.degree)
}

// The decision value of sample `j` of `q` under the model over the training
// set `x` with labels `y`.
fn decide(m: *const Model, x: []const f64, y: []const f64, n: usize, d: usize, q: []const f64, j: usize) -> f64 {
    var s = m.bias
    var i = 0usize
    while i < n {
        if m.alphas[i] > 0.0f64 { s += m.alphas[i] * y[i] * kernel(m.kernel, x, d, i, q, j) }
        i += 1usize
    }
    ret s
}

// Train on labels `y` in {-1, +1} with box constraint `c` and KKT tolerance
// `tolerance`; the search ends after `passes` full sweeps without a change
// or `max_sweeps` in all. `alphas.len >= n` receives the multipliers.
// Answers the model and the sweeps taken.
fn smo(x: []const f64, y: []const f64, n: usize, d: usize, k: Kernel, c: f64, tolerance: f64, passes: u32, max_sweeps: u32, r: *rand.Pcg64, alphas: []f64) -> (Model, u32, err) {
    if x.len < n * d || y.len < n || alphas.len < n { ret (zero, 0u32, TooSmall) }
    if n == 0usize || c <= 0.0f64 { ret (zero, 0u32, Invalid) }
    var i = 0usize
    while i < n {
        if y[i] != 1.0f64 && y[i] != 0.0f64 - 1.0f64 { ret (zero, 0u32, Invalid) }
        alphas[i] = 0.0f64
        i += 1usize
    }
    var m = Model { alphas: alphas, bias: 0.0f64, kernel: k }
    var quiet = 0u32
    var sweeps = 0u32
    while quiet < passes && sweeps < max_sweeps {
        var changed = 0usize
        i = 0usize
        while i < n {
            let ei = decide(&m, x, y, n, d, x, i) - y[i]
            if (y[i] * ei < 0.0f64 - tolerance && alphas[i] < c) || (y[i] * ei > tolerance && alphas[i] > 0.0f64) {
                var j = usize(rand.pcg64_bounded(r, u64(n - 1usize)))
                if j >= i { j += 1usize }
                let ej = decide(&m, x, y, n, d, x, j) - y[j]
                let old_i = alphas[i]
                let old_j = alphas[j]
                var low = 0.0f64
                var high = c
                if y[i] != y[j] {
                    low = math.max[f64](0.0f64, old_j - old_i)
                    high = math.min[f64](c, c + old_j - old_i)
                } else {
                    low = math.max[f64](0.0f64, old_i + old_j - c)
                    high = math.min[f64](c, old_i + old_j)
                }
                if low < high {
                    let kii = kernel(k, x, d, i, x, i)
                    let kjj = kernel(k, x, d, j, x, j)
                    let kij = kernel(k, x, d, i, x, j)
                    let eta = 2.0f64 * kij - kii - kjj
                    if eta < 0.0f64 {
                        var aj = old_j - y[j] * (ei - ej) / eta
                        if aj > high { aj = high }
                        if aj < low { aj = low }
                        if math.abs[f64](aj - old_j) > 1.0e-5f64 {
                            let ai = old_i + y[i] * y[j] * (old_j - aj)
                            alphas[i] = ai
                            alphas[j] = aj
                            let b1 = m.bias - ei - y[i] * (ai - old_i) * kii - y[j] * (aj - old_j) * kij
                            let b2 = m.bias - ej - y[i] * (ai - old_i) * kij - y[j] * (aj - old_j) * kjj
                            if ai > 0.0f64 && ai < c {
                                m.bias = b1
                            } else if aj > 0.0f64 && aj < c {
                                m.bias = b2
                            } else {
                                m.bias = 0.5f64 * (b1 + b2)
                            }
                            changed += 1usize
                        }
                    }
                }
            }
            i += 1usize
        }
        sweeps += 1u32
        if changed == 0usize { quiet += 1u32 } else { quiet = 0u32 }
    }
    ret (m, sweeps, ok)
}
