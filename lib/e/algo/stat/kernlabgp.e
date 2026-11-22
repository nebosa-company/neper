// R kernlab gausspr, regression: alpha = solve(K + var I) %*% y, predictions kernelMult(k, new, x, alpha), and the predictive variance
// diag(k(new, new) - Kt' sol Kt) of variance.model = TRUE. The inverse is R's solve(): dgesv on the identity (LAPACK dgetrf2 order), the products
// are reference-BLAS dot products in order. Matrices are row-major; the kernel matrices come from kernlabmmd.cross.
//
// Not here: classification (the Laplace approximation with solveiter and the incomplete Cholesky route), scaled = TRUE and cross-validation.

use e.algo.stat.kernlabqp as qp
use e.mem

// inv (m by m) = solve(K + var I)
fn inverse(a: *mem.Arena, k: []const f64, m: usize, v: f64, inv: []f64) -> err {
    let (kv, e1) = mem.alloc[f64](a, m * m)
    let (rhs, e2) = mem.alloc[f64](a, m)
    let (col, e3) = mem.alloc[f64](a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            kv[i * m + j] = k[i * m + j]
            if i == j { kv[i * m + j] = k[i * m + j] + v }
            j += 1usize
        }
        i += 1usize
    }
    var c = 0usize
    while c < m {
        i = 0usize
        while i < m {
            rhs[i] = 0.0f64
            i += 1usize
        }
        rhs[c] = 1.0f64
        let e = qp.solve_ap(a, kv, rhs, col, m)
        if e != ok { ret e }
        i = 0usize
        while i < m {
            inv[i * m + c] = col[i]
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// alpha = inv %*% y
fn coefficients(inv: []const f64, y: []const f64, m: usize, alpha: []f64) {
    var i = 0usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            s += inv[i * m + j] * y[j]
            j += 1usize
        }
        alpha[i] = s
        i += 1usize
    }
}

// kt is the nt by m cross kernel (new rows), alpha the coefficients: the predictions
fn predict(kt: []const f64, alpha: []const f64, m: usize, nt: usize, out: []f64) {
    var t = 0usize
    while t < nt {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            s += kt[t * m + j] * alpha[j]
            j += 1usize
        }
        out[t] = s
        t += 1usize
    }
}

// the predictive variance of test point t: k(t, t) - kt' sol kt (kt is the nt by m cross kernel, kself the diagonal of k(new, new))
fn variance(kt: []const f64, inv: []const f64, kself: []const f64, m: usize, nt: usize, out: []f64) {
    var t = 0usize
    while t < nt {
        var q = 0.0f64
        var j = 0usize
        while j < m {
            var s = 0.0f64
            var i = 0usize
            while i < m {
                s += kt[t * m + i] * inv[i * m + j]
                i += 1usize
            }
            q += s * kt[t * m + j]
            j += 1usize
        }
        out[t] = kself[t] - q
        t += 1usize
    }
}
