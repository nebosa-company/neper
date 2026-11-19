// RSpectra and irlba: the k leading singular triplets (svds, irlba) and the k wanted eigenpairs of a symmetric matrix (eigs_sym), taken from the full Jacobi decompositions of e.algo.linalg.matrix rather than from Lanczos iterations, so they match R to its convergence tolerance. Matrices are row-major.
//
// Not here: shift-invert, general (Arnoldi) and complex eigs, sparse and operator inputs, restarts and augmentation settings.

use e.algo.linalg.matrix as mx
use e.math
use e.mem

// the k largest singular values into d, left vectors into u (m by k) and right vectors into v (n by k)
fn svds(a: *mem.Arena, x: []const f64, m: usize, n: usize, k: usize, d: []f64, u: []f64, v: []f64) -> err {
    var kk = n
    if m < kk { kk = m }
    let (uf, e1) = mem.alloc[f64](a, m * kk)
    let (vf, e2) = mem.alloc[f64](a, n * kk)
    let (sf, e3) = mem.alloc[f64](a, kk)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    let (um, e4) = mx.view[f64](uf, m, kk, kk)
    let (vm, e5) = mx.view[f64](vf, n, kk, kk)
    let (src, e6) = mx.view_const[f64](x, m, n, n)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    let r = mx.svd(a, um, sf, vm, src, 1.0e-14f64, 200u32)
    if r != ok { ret r }
    var j = 0usize
    while j < k {
        d[j] = sf[j]
        var i = 0usize
        while i < m {
            u[i * k + j] = uf[i * kk + j]
            i += 1usize
        }
        i = 0usize
        while i < n {
            v[i * k + j] = vf[i * kk + j]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// eigs_sym: which 0 LM, 1 LA, 2 SA, 3 SM, 4 the eigenvalues nearest sigma (shift-invert, sigma unused otherwise); the k values into vals, selected by which and listed decreasing, as RSpectra does and their vectors into vecs (n by k)
fn eigs_sym(a: *mem.Arena, x: []const f64, n: usize, k: usize, which: usize, sigma: f64, vals: []f64, vecs: []f64) -> err {
    let (vf, e1) = mem.alloc[f64](a, n * n)
    let (ev, e2) = mem.alloc[f64](a, n)
    let (key, e3) = mem.alloc[f64](a, n)
    let (pick, e4) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    let (vm, e5) = mx.view[f64](vf, n, n, n)
    let (src, e6) = mx.view_const[f64](x, n, n, n)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    let r = mx.eigen(a, ev, vm, src, 1.0e-14f64, 200u32)
    if r != ok { ret r }
    var i = 0usize
    while i < n {
        pick[i] = i
        if which == 0usize { key[i] = math.abs[f64](ev[i]) }
        if which == 1usize { key[i] = ev[i] }
        if which == 2usize { key[i] = 0.0f64 - ev[i] }
        if which == 3usize { key[i] = 0.0f64 - math.abs[f64](ev[i]) }
        if which == 4usize { key[i] = 0.0f64 - math.abs[f64](ev[i] - sigma) }
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = pick[i]
        var j = i
        while j > 0usize && key[pick[j - 1usize]] < key[t] {
            pick[j] = pick[j - 1usize]
            j -= 1usize
        }
        pick[j] = t
        i += 1usize
    }
    i = 1usize
    while i < k {
        let t = pick[i]
        var j = i
        while j > 0usize && ev[pick[j - 1usize]] < ev[t] {
            pick[j] = pick[j - 1usize]
            j -= 1usize
        }
        pick[j] = t
        i += 1usize
    }
    var c = 0usize
    while c < k {
        let p = pick[c]
        vals[c] = ev[p]
        i = 0usize
        while i < n {
            vecs[i * k + c] = vf[i * n + p]
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}
