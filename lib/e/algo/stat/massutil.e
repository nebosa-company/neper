// R MASS utilities: Null (the orthonormal basis of the null space of t(M) from the complete qr.Q), area (adaptive Simpson), lm.gls.

use e.algo.linalg.decomp as decomp
use e.algo.linalg.lapack_syevr as sy
use e.math
use e.mem

error BadInput

// Null(M): m is n by p column-major; out gets the n by (n - rank) matrix qr.Q(qr(M), complete = TRUE)[, -seq_len(rank)] (the first p columns when the rank is 0, as R does). Returns its column count.
fn null_space(a: *mem.Arena, m: []const f64, n: usize, p: usize, out: []f64) -> (usize, err) {
    let (q, e) = decomp.qr(a, m, n, p, 1.0e-7f64)
    if e != ok { ret (0usize, e) }
    let (col, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (0usize, e2) }
    var first = q.rank
    var last = n
    if q.rank == 0usize {
        // R: set <- seq_len(ncol(M)), the first p columns of Q
        first = 0usize
        last = p
    }
    var j = first
    while j < last {
        var i = 0usize
        while i < n {
            col[i] = 0.0f64
            i += 1usize
        }
        col[j] = 1.0f64
        decomp.qr_qy(&q, col)
        i = 0usize
        while i < n {
            out[i + n * (j - first)] = col[i]
            i += 1usize
        }
        j += 1usize
    }
    ret (last - first, ok)
}

// the integrands of the oracle: 0 sin x, 1 x^2, 2 exp(-x^2), 3 1 / (1 + x^2), 4 sqrt x, 5 |x - 0.3|, 6 exp(x) cos(3 x)
fn integrand(id: usize, x: f64) -> f64 {
    if id == 0usize { ret math.sin[f64](x) }
    if id == 1usize { ret x * x }
    if id == 2usize { ret math.exp[f64](0.0f64 - x * x) }
    if id == 3usize { ret 1.0f64 / (1.0f64 + x * x) }
    if id == 4usize { ret math.sqrt[f64](x) }
    if id == 5usize { ret math.abs[f64](x - 0.3f64) }
    ret math.exp[f64](x) * math.cos[f64](3.0f64 * x)
}

// area(f, a, b, fa, fb, limit, eps): the recursion of MASS::area (the limit warning is dropped)
fn area_rec(id: usize, a: f64, b: f64, fa: f64, fb: f64, limit: i64, eps: f64) -> f64 {
    let h = b - a
    let d = (a + b) / 2.0f64
    let fd = integrand(id, d)
    let a1 = ((fa + fb) * h) / 2.0f64
    let a2 = ((fa + 4.0f64 * fd + fb) * h) / 6.0f64
    if math.abs[f64](a1 - a2) < eps { ret a2 }
    if limit == 0i64 { ret a2 }
    ret area_rec(id, a, d, fa, fd, limit - 1i64, eps) + area_rec(id, d, b, fd, fb, limit - 1i64, eps)
}

fn area(id: usize, a: f64, b: f64, limit: i64, eps: f64) -> f64 { ret area_rec(id, a, b, integrand(id, a), integrand(id, b), limit, eps) }

type Gls = struct { coef: []f64, fitted: []f64, resid: []f64, rank: usize }

// lm.gls(y ~ x, W, inverse): x is n by p column-major, w n by n symmetric. A = diag(d^(+-1/2)) t(V), fit lm.fit(A x, A y), and the fitted values and residuals mapped back by Ainv.
fn lm_gls(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, inverse: bool) -> (Gls, err) {
    var out: Gls = zero
    let (d, e1) = mem.alloc[f64](a, n)
    let (v, e2) = mem.alloc[f64](a, n * n)
    let (am, e3) = mem.alloc[f64](a, n * n)
    let (ai, e4) = mem.alloc[f64](a, n * n)
    let (ax, e5) = mem.alloc[f64](a, n * p)
    let (ay, e6) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (out, mem.Full) }
    let ee = sy.dsyevr_all(a, w, n, d, v)
    if ee != ok { ret (out, ee) }
    var k = 0usize
    while k < n {
        if d[k] <= 0.0f64 { ret (out, BadInput) }
        k += 1usize
    }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            // A[k, j] = d_k^(1/2) V[j, k]; Ainv[j, k] = V[j, k] d_k^(-1/2) (swapped when inverse)
            let dk = d[j]
            var pa = math.sqrt[f64](dk)
            var pi = 1.0f64 / pa
            if inverse {
                pa = 1.0f64 / math.sqrt[f64](dk)
                pi = math.sqrt[f64](dk)
            }
            am[j + n * i] = pa * v[i + n * j]
            ai[i + n * j] = v[i + n * j] * pi
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += am[i + n * j] * y[j]
            j += 1usize
        }
        ay[i] = s
        var c = 0usize
        while c < p {
            var t = 0.0f64
            j = 0usize
            while j < n {
                t += am[i + n * j] * x[j + n * c]
                j += 1usize
            }
            ax[i + n * c] = t
            c += 1usize
        }
        i += 1usize
    }
    let (f, fe) = decomp.lm_fit(a, ax, n, p, ay, 1.0e-7f64)
    if fe != ok { ret (out, fe) }
    let (fit, e7) = mem.alloc[f64](a, n)
    let (res, e8) = mem.alloc[f64](a, n)
    if e7 != ok || e8 != ok { ret (out, mem.Full) }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var t = 0.0f64
        var j = 0usize
        while j < n {
            s += ai[i + n * j] * (ay[j] - f.residuals[j])
            t += ai[i + n * j] * f.residuals[j]
            j += 1usize
        }
        fit[i] = s
        res[i] = t
        i += 1usize
    }
    out = Gls { coef: f.coef, fitted: fit, resid: res, rank: f.rank }
    ret (out, ok)
}
