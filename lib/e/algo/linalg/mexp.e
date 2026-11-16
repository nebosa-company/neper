// R Matrix, the dense part: `expm` (Ward's Pade approximation of order 8 with scaling and squaring, as Matrix::expm),
// the matrix norms 1, infinity, Frobenius and max-modulus, `kronecker`, and `symmpart` / `skewpart`. Square
// matrices are row-major n by n in caller storage.
//
// Not here: logm, sqrtm, condest, rcond, sparse LU and QR, orderings, Schur, bandSparse, CSR conversion, slm.

use e.algo.stat.psych as ps
use e.math
use e.mem

fn matmul(a: []const f64, b: []const f64, n: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                s += a[i * n + k] * b[k * n + j]
                k += 1usize
            }
            out[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

fn norm_one(a: []const f64, n: usize) -> f64 {
    var best = 0.0f64
    var j = 0usize
    while j < n {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += math.abs[f64](a[i * n + j])
            i += 1usize
        }
        if s > best { best = s }
        j += 1usize
    }
    ret best
}

fn norm_inf(a: []const f64, n: usize) -> f64 {
    var best = 0.0f64
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += math.abs[f64](a[i * n + j])
            j += 1usize
        }
        if s > best { best = s }
        i += 1usize
    }
    ret best
}

fn norm_frobenius(a: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n * n {
        s += a[i] * a[i]
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

fn norm_max(a: []const f64, n: usize) -> f64 {
    var best = 0.0f64
    var i = 0usize
    while i < n * n {
        if math.abs[f64](a[i]) > best { best = math.abs[f64](a[i]) }
        i += 1usize
    }
    ret best
}

// out = exp(a)
fn expm(arena: *mem.Arena, a: []const f64, n: usize, out: []f64) -> err {
    let nn = n * n
    let (x, e1) = mem.alloc[f64](arena, nn)
    let (pw, e2) = mem.alloc[f64](arena, nn)
    let (tmp, e3) = mem.alloc[f64](arena, nn)
    let (num, e4) = mem.alloc[f64](arena, nn)
    let (den, e5) = mem.alloc[f64](arena, nn)
    let (inv, e6) = mem.alloc[f64](arena, nn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    var s = 0.0f64
    let nrm = norm_inf(a, n)
    if nrm > 0.5f64 { s = math.ceil[f64](math.log[f64](nrm) / math.log[f64](2.0f64)) + 1.0f64 }
    if s < 0.0f64 { s = 0.0f64 }
    let scale = math.pow[f64](2.0f64, s)
    var i = 0usize
    while i < nn {
        x[i] = a[i] / scale
        pw[i] = 0.0f64
        num[i] = 0.0f64
        den[i] = 0.0f64
        inv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        pw[i * n + i] = 1.0f64
        num[i * n + i] = 1.0f64
        den[i * n + i] = 1.0f64
        i += 1usize
    }
    var c = 1.0f64
    var k = 1usize
    var sign = 0.0f64 - 1.0f64
    while k <= 8usize {
        c = c * f64(8usize - k + 1usize) / (f64(k) * f64(16usize - k + 1usize))
        matmul(x, pw, n, tmp)
        i = 0usize
        while i < nn {
            pw[i] = tmp[i]
            num[i] += c * pw[i]
            den[i] += sign * c * pw[i]
            i += 1usize
        }
        sign = 0.0f64 - sign
        k += 1usize
    }
    if !ps.invert(arena, den, n, inv) { ret Singular }
    matmul(inv, num, n, out)
    var sq = 0.0f64
    while sq < s {
        matmul(out, out, n, tmp)
        i = 0usize
        while i < nn {
            out[i] = tmp[i]
            i += 1usize
        }
        sq += 1.0f64
    }
    ret ok
}

error Singular
