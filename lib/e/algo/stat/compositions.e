// R compositions, the Aitchison geometry of the simplex on positive data (acomp): closure, the centred, additive and isometric log-ratio
// transforms and their inverses (the default ilr basis is the normalised Helmert contrasts), the Aitchison norm and distance,
// perturbation and powering, the compositional mean (the closed geometric mean), the clr covariance and the variation matrix.
// Data are n by D, row-major.
//
// Not here: zeros and missing values, the robust estimates, the balance bases and the normality tests.

use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// clo: every row divided by its sum
fn clo(x: []const f64, n: usize, d: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            s += x[i * d + j]
            j += 1usize
        }
        j = 0usize
        while j < d {
            out[i * d + j] = x[i * d + j] / s
            j += 1usize
        }
        i += 1usize
    }
}

// clr: log(x) minus its row mean (of the closed row: the same, the closure shifts every log by a constant)
fn clr(x: []const f64, n: usize, d: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var m = 0.0f64
        var j = 0usize
        while j < d {
            m += math.log[f64](x[i * d + j])
            j += 1usize
        }
        m = m / f64(d)
        j = 0usize
        while j < d {
            out[i * d + j] = math.log[f64](x[i * d + j]) - m
            j += 1usize
        }
        i += 1usize
    }
}

// the clr of closed data, as R takes it: acomp closes the rows first
fn clr_closed(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    clo(x, n, d, c)
    clr(c, n, d, out)
    ret ok
}

// clrInv: closed exp of the centred coordinates
fn clr_inv(z: []const f64, n: usize, d: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            s += math.exp[f64](z[i * d + j])
            j += 1usize
        }
        j = 0usize
        while j < d {
            out[i * d + j] = math.exp[f64](z[i * d + j]) / s
            j += 1usize
        }
        i += 1usize
    }
}

// alr with the last part as the divisor (ivar = D) or part ivar (0-based) removed: n by (D - 1)
fn alr(a: *mem.Arena, x: []const f64, n: usize, d: usize, ivar: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    clo(x, n, d, c)
    var i = 0usize
    while i < n {
        var k = 0usize
        var j = 0usize
        while j < d {
            if j != ivar {
                out[i * (d - 1usize) + k] = math.log[f64](c[i * d + j]) - math.log[f64](c[i * d + ivar])
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// alrInv: the z (n by D - 1) with an implicit zero for the divisor part ivar, closed after exp
fn alr_inv(z: []const f64, n: usize, d: usize, ivar: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var k = 0usize
        var j = 0usize
        while j < d {
            if j == ivar {
                out[i * d + j] = 1.0f64
            } else {
                out[i * d + j] = math.exp[f64](z[i * (d - 1usize) + k])
                k += 1usize
            }
            s += out[i * d + j]
            j += 1usize
        }
        j = 0usize
        while j < d {
            out[i * d + j] = out[i * d + j] / s
            j += 1usize
        }
        i += 1usize
    }
}

// the entry (i, j) of the default ilr basis V (D by D - 1): normalised Helmert contrasts
fn ilr_v(i: usize, j: usize) -> f64 {
    let jj = f64(j + 1usize)
    let nrm = math.sqrt[f64](jj * (jj + 1.0f64))
    if i <= j { ret (0.0f64 - 1.0f64) / nrm }
    if i == j + 1usize { ret jj / nrm }
    ret 0.0f64
}

// ilr: clr(x) V, n by (D - 1)
fn ilr(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    let e2 = clr_closed(a, x, n, d, c)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < d - 1usize {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += c[i * d + k] * ilr_v(k, j)
                k += 1usize
            }
            out[i * (d - 1usize) + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// ilrInv: closed exp(z V')
fn ilr_inv(a: *mem.Arena, z: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        var k = 0usize
        while k < d {
            var s = 0.0f64
            var j = 0usize
            while j < d - 1usize {
                s += z[i * (d - 1usize) + j] * ilr_v(k, j)
                j += 1usize
            }
            c[i * d + k] = s
            k += 1usize
        }
        i += 1usize
    }
    clr_inv(c, n, d, out)
    ret ok
}

// the Aitchison norm of every row: the Euclidean norm of its clr
fn norm_rows(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    let e2 = clr_closed(a, x, n, d, c)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            s += c[i * d + j] * c[i * d + j]
            j += 1usize
        }
        out[i] = math.sqrt[f64](s)
        i += 1usize
    }
    ret ok
}

// the Aitchison distance between row i of x and row i of y
fn dist_rows(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (cx, e1) = mem.alloc[f64](a, n * d)
    let (cy, e2) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    let e3 = clr_closed(a, x, n, d, cx)
    if e3 != ok { ret e3 }
    let e4 = clr_closed(a, y, n, d, cy)
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            s += (cx[i * d + j] - cy[i * d + j]) * (cx[i * d + j] - cy[i * d + j])
            j += 1usize
        }
        out[i] = math.sqrt[f64](s)
        i += 1usize
    }
    ret ok
}

// perturbation x (+) y: the closed product, row by row
fn perturb(x: []const f64, y: []const f64, n: usize, d: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            out[i * d + j] = x[i * d + j] * y[i * d + j]
            s += out[i * d + j]
            j += 1usize
        }
        j = 0usize
        while j < d {
            out[i * d + j] = out[i * d + j] / s
            j += 1usize
        }
        i += 1usize
    }
}

// powering p (.) x: the closed power of every row
fn power(x: []const f64, p: f64, n: usize, d: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            out[i * d + j] = math.pow[f64](x[i * d + j], p)
            s += out[i * d + j]
            j += 1usize
        }
        j = 0usize
        while j < d {
            out[i * d + j] = out[i * d + j] / s
            j += 1usize
        }
        i += 1usize
    }
}

// mean.acomp: the closed geometric mean (ilrInv of the mean ilr, which is the same composition)
fn mean_acomp(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    let e2 = clr_closed(a, x, n, d, c)
    if e2 != ok { ret e2 }
    let (m, e3) = mem.alloc[f64](a, d)
    if e3 != ok { ret e3 }
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += c[i * d + j]
            i += 1usize
        }
        m[j] = s / f64(n)
        j += 1usize
    }
    clr_inv(m, 1usize, d, out)
    ret ok
}

// var.acomp: the covariance matrix (n - 1) of the clr coordinates, D by D
fn var_acomp(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    let e2 = clr_closed(a, x, n, d, c)
    if e2 != ok { ret e2 }
    let (m, e3) = mem.alloc[f64](a, d)
    if e3 != ok { ret e3 }
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += c[i * d + j]
            i += 1usize
        }
        m[j] = s / f64(n)
        j += 1usize
    }
    var p = 0usize
    while p < d {
        var q = 0usize
        while q < d {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (c[i * d + p] - m[p]) * (c[i * d + q] - m[q])
                i += 1usize
            }
            out[p * d + q] = s / f64(n - 1usize)
            q += 1usize
        }
        p += 1usize
    }
    ret ok
}

// variation.acomp: the matrix of var(log(x_i / x_j)) = -2 cov + var_i + var_j of the clr covariance
fn variation(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (cv, e) = mem.alloc[f64](a, d * d)
    if e != ok { ret e }
    let e2 = var_acomp(a, x, n, d, cv)
    if e2 != ok { ret e2 }
    var p = 0usize
    while p < d {
        var q = 0usize
        while q < d {
            out[p * d + q] = 0.0f64 - 2.0f64 * cv[p * d + q] + cv[q * d + q] + cv[p * d + p]
            q += 1usize
        }
        p += 1usize
    }
    ret ok
}
