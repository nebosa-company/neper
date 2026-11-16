// Classical (Torgerson) multidimensional scaling of a distance matrix, as R's cmdscale: double-centre the squared distances, take the leading k eigenpairs, scale the eigenvectors by the square roots of their eigenvalues; the Johnson-Lindenstrauss dimension bound.
//
// Not here: metric and non-metric MDS by stress majorisation (SMACOF), the additive constant of cmdscale(add = TRUE), Gaussian and sparse random projection.

use e.algo.linalg.matrix as mx
use e.math
use e.mem

// d is n by n row-major (symmetric, zero diagonal); coords receives n by k and eig the k leading eigenvalues of the centred matrix
fn cmdscale(a: *mem.Arena, d: []const f64, n: usize, k: usize, coords: []f64, eig: []f64) -> err {
    let (b, e1) = mem.alloc[f64](a, n * n)
    let (rm, e2) = mem.alloc[f64](a, n)
    let (vv, e3) = mem.alloc[f64](a, n * n)
    let (ev, e4) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        rm[i] = 0.0f64
        var j = 0usize
        while j < n {
            let v = d[i * n + j] * d[i * n + j]
            b[i * n + j] = v
            rm[i] += v / f64(n)
            j += 1usize
        }
        tot += rm[i] / f64(n)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            b[i * n + j] = 0.0f64 - 0.5f64 * (b[i * n + j] - rm[i] - rm[j] + tot)
            j += 1usize
        }
        i += 1usize
    }
    let (vm, e5) = mx.view[f64](vv, n, n, n)
    let (src, e6) = mx.view_const[f64](b, n, n, n)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    let r = mx.eigen(a, ev, vm, src, 1.0e-14f64, 200u32)
    if r != ok { ret r }
    var c = 0usize
    while c < k {
        eig[c] = ev[c]
        var s = 0.0f64
        if ev[c] > 0.0f64 { s = math.sqrt[f64](ev[c]) }
        i = 0usize
        while i < n {
            coords[i * k + c] = vv[i * n + c] * s
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// the smallest dimension that keeps n points within 1 +- eps of their pairwise distances: 4 ln n / (eps^2 / 2 - eps^3 / 3), rounded up
fn jl_dimension(n: usize, eps: f64) -> usize {
    let v = 4.0f64 * math.log[f64](f64(n)) / (eps * eps / 2.0f64 - eps * eps * eps / 3.0f64)
    ret usize(math.ceil[f64](v))
}
