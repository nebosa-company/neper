// RSpectra and irlba: the k leading singular triplets (svds, irlba) and the k wanted eigenpairs of a symmetric matrix (eigs_sym), taken from the full Jacobi decompositions of e.algo.linalg.matrix rather than from Lanczos iterations, so they match R to its convergence tolerance. Matrices are row-major.
//
// Not here: shift-invert, general (Arnoldi) and complex eigs, sparse and operator inputs, restarts and augmentation settings.

use e.algo.linalg.decomp as dc
use e.algo.rand.r as rr
use e.algo.linalg.matrix as mx
use e.algo.linalg.sparse as sp
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

// eigs(A, k, which) for a general real n by n matrix (the values, and the moduli of the unit-norm vectors, which are defined up to phase; vmod is n by k row-major): the k eigenvalues selected by which (0 LM largest modulus, 1 LR largest real part, 2 SR smallest real part, 3 LI largest |imaginary|,
// 4 SI smallest |imaginary|), listed in decreasing modulus with the positive imaginary part first within a conjugate pair, as RSpectra returns them. x is column-major (R's layout)
fn eigs_general(a: *mem.Arena, x: []const f64, n: usize, k: usize, which: usize, re: []f64, im: []f64, vmod: []f64) -> err {
    let (ev, e0) = dc.eigen(a, x, n)
    if e0 != ok { ret e0 }
    let (key, e1) = mem.alloc[f64](a, n)
    let (pick, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        pick[i] = i
        let r = ev.re[i]
        let m = ev.im[i]
        if which == 0usize { key[i] = math.sqrt[f64](r * r + m * m) }
        if which == 1usize { key[i] = r }
        if which == 2usize { key[i] = 0.0f64 - r }
        if which == 3usize { key[i] = math.abs[f64](m) }
        if which == 4usize { key[i] = 0.0f64 - math.abs[f64](m) }
        i += 1usize
    }
    // selection: decreasing key, positive imaginary part first on a tie
    i = 1usize
    while i < n {
        let t = pick[i]
        var j = i
        while j > 0usize && (key[pick[j - 1usize]] < key[t] - 1.0e-10f64 * (1.0f64 + math.abs[f64](key[t])) || (math.abs[f64](key[pick[j - 1usize]] - key[t]) <= 1.0e-10f64 * (1.0f64 + math.abs[f64](key[t])) && ev.im[pick[j - 1usize]] < ev.im[t])) {
            pick[j] = pick[j - 1usize]
            j -= 1usize
        }
        pick[j] = t
        i += 1usize
    }
    // the chosen k by decreasing modulus, positive imaginary part first on a tie
    i = 1usize
    while i < k {
        let t = pick[i]
        let mt = math.sqrt[f64](ev.re[t] * ev.re[t] + ev.im[t] * ev.im[t])
        var j = i
        while j > 0usize {
            let q = pick[j - 1usize]
            let mq = math.sqrt[f64](ev.re[q] * ev.re[q] + ev.im[q] * ev.im[q])
            if mq < mt - 1.0e-10f64 * (1.0f64 + mt) || (math.abs[f64](mq - mt) <= 1.0e-10f64 * (1.0f64 + mt) && ev.im[q] < ev.im[t]) {
                pick[j] = pick[j - 1usize]
                j -= 1usize
            } else {
                break
            }
        }
        pick[j] = t
        i += 1usize
    }
    var c = 0usize
    while c < k {
        re[c] = ev.re[pick[c]]
        im[c] = ev.im[pick[c]]
        var rrw = 0usize
        while rrw < n {
            let vr0 = ev.vre[pick[c] * n + rrw]
            let vi0 = ev.vim[pick[c] * n + rrw]
            vmod[rrw * k + c] = math.sqrt[f64](vr0 * vr0 + vi0 * vi0)
            rrw += 1usize
        }
        c += 1usize
    }
    ret ok
}

// orthonormalise the columns of the r by c row-major matrix y in place (modified Gram-Schmidt, twice): the same column space as R's qr.Q, which is all the power iteration of svdr depends on
fn orth_cols(y: []f64, r: usize, c: usize) {
    var pass = 0usize
    while pass < 2usize {
        var j = 0usize
        while j < c {
            var l = 0usize
            while l < j {
                var dot = 0.0f64
                var i = 0usize
                while i < r {
                    dot += y[i * c + l] * y[i * c + j]
                    i += 1usize
                }
                i = 0usize
                while i < r {
                    y[i * c + j] = y[i * c + j] - dot * y[i * c + l]
                    i += 1usize
                }
                l += 1usize
            }
            var nrm = 0.0f64
            var i2 = 0usize
            while i2 < r {
                nrm += y[i2 * c + j] * y[i2 * c + j]
                i2 += 1usize
            }
            nrm = math.sqrt[f64](nrm)
            if nrm > 0.0f64 {
                i2 = 0usize
                while i2 < r {
                    y[i2 * c + j] = y[i2 * c + j] / nrm
                    i2 += 1usize
                }
            }
            j += 1usize
        }
        pass += 1usize
    }
}

// irlba::svdr(x, k, tol, it, extra): the randomised SVD by power iteration on a Gaussian start Q (n by min(n, k + extra), column-major draws of the generator g, as matrix(rnorm(...), ncol(x)) fills it);
// x is m by n row-major, d receives the k singular values; the answer is the number of iterations plus the final pass (R's mprod = 2 j + 1 is 2 * iterations + 1)
fn svdr(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, n: usize, k: usize, extra: usize, tol: f64, it: usize, d: []f64) -> (usize, err) {
    var nq = k + extra
    if n < nq { nq = n }
    let (q, e0) = mem.alloc[f64](a, n * nq)
    let (y, e1) = mem.alloc[f64](a, m * nq)
    let (b, e2) = mem.alloc[f64](a, n * nq)
    let (dd, e3) = mem.alloc[f64](a, k)
    let (u1, e4) = mem.alloc[f64](a, n * k)
    let (v1, e5) = mem.alloc[f64](a, nq * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0usize, mem.Full) }
    var j = 0usize
    while j < nq {
        var i = 0usize
        while i < n {
            q[i * nq + j] = rr.rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        j += 1usize
    }
    var s = 0usize
    while s < k {
        d[s] = 0.0f64
        s += 1usize
    }
    let eps2 = math.pow[f64](2.220446049250313e-16f64, 0.8f64)
    var iter = 1usize
    while iter <= it {
        // y = x q, orthonormalised; b = x' y; q = orth(b)
        var r = 0usize
        while r < m {
            var c = 0usize
            while c < nq {
                var v = 0.0f64
                var l = 0usize
                while l < n {
                    v += x[r * n + l] * q[l * nq + c]
                    l += 1usize
                }
                y[r * nq + c] = v
                c += 1usize
            }
            r += 1usize
        }
        orth_cols(y, m, nq)
        r = 0usize
        while r < n {
            var c = 0usize
            while c < nq {
                var v = 0.0f64
                var l = 0usize
                while l < m {
                    v += x[l * n + r] * y[l * nq + c]
                    l += 1usize
                }
                b[r * nq + c] = v
                q[r * nq + c] = v
                c += 1usize
            }
            r += 1usize
        }
        orth_cols(q, n, nq)
        let es = svds(a, b, n, nq, k, dd, u1, v1)
        if es != ok { ret (0usize, es) }
        var any = false
        var worst = 0.0f64
        s = 0usize
        while s < k {
            if dd[s] > eps2 {
                any = true
                var rel = math.abs[f64]((dd[s] - d[s]) / d[s])
                if d[s] == 0.0f64 { rel = math.inf64() }
                if rel > worst { worst = rel }
            }
            s += 1usize
        }
        if !any { break }
        if worst < tol { break }
        s = 0usize
        while s < k {
            d[s] = dd[s]
            s += 1usize
        }
        iter += 1usize
    }
    if iter > it { iter = it }
    // the final pass: q = orth(x q), b = q' x (nq by n), d = its k largest singular values
    var r = 0usize
    while r < m {
        var c = 0usize
        while c < nq {
            var v = 0.0f64
            var l = 0usize
            while l < n {
                v += x[r * n + l] * q[l * nq + c]
                l += 1usize
            }
            y[r * nq + c] = v
            c += 1usize
        }
        r += 1usize
    }
    orth_cols(y, m, nq)
    let (bt, e6) = mem.alloc[f64](a, nq * n)
    if e6 != ok { ret (0usize, mem.Full) }
    r = 0usize
    while r < nq {
        var c = 0usize
        while c < n {
            var v = 0.0f64
            var l = 0usize
            while l < m {
                v += y[l * nq + r] * x[l * n + c]
                l += 1usize
            }
            bt[r * n + c] = v
            c += 1usize
        }
        r += 1usize
    }
    let (uu, e7) = mem.alloc[f64](a, nq * k)
    let (vv, e8) = mem.alloc[f64](a, n * k)
    if e7 != ok || e8 != ok { ret (0usize, mem.Full) }
    let ef = svds(a, bt, nq, n, k, d, uu, vv)
    if ef != ok { ret (0usize, ef) }
    ret (iter, ok)
}

// irlba::prcomp_irlba(x, n = k, center, scale.): sdev = the k leading singular values of the centred (and, with scale., unit-variance) x over sqrt(m - 1), rotation the right singular vectors
// (n by k into rot, up to sign), totalvar the sum of the column variances of the processed x; x is m by n row-major
fn prcomp_irlba(a: *mem.Arena, x: []const f64, m: usize, n: usize, k: usize, center: bool, scale: bool, sdev: []f64, rot: []f64, totalvar: *f64) -> err {
    let (z, e0) = mem.alloc[f64](a, m * n)
    let (u, e1) = mem.alloc[f64](a, m * k)
    let (d, e2) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var c = 0usize
    var tv = 0.0f64
    while c < n {
        var mean = 0.0f64
        var i = 0usize
        while i < m {
            mean += x[i * n + c]
            i += 1usize
        }
        mean = mean / f64(m)
        if !center { mean = 0.0f64 }
        var ss = 0.0f64
        i = 0usize
        while i < m {
            ss += (x[i * n + c] - mean) * (x[i * n + c] - mean)
            i += 1usize
        }
        var sd = math.sqrt[f64](ss / f64(m - 1usize))
        if !scale { sd = 1.0f64 }
        i = 0usize
        while i < m {
            z[i * n + c] = (x[i * n + c] - mean) / sd
            i += 1usize
        }
        tv += ss / f64(m - 1usize) / (sd * sd)
        c += 1usize
    }
    let e = svds(a, z, m, n, k, d, u, rot)
    if e != ok { ret e }
    var j = 0usize
    while j < k {
        sdev[j] = d[j] / math.sqrt[f64](f64(m - 1usize))
        j += 1usize
    }
    *totalvar = tv
    ret ok
}

// RSpectra::svds on a sparse matrix (compressed-column, as Matrix::dgCMatrix stores it): the k largest singular values as the square roots of the k largest eigenvalues of the Gram matrix A'A
// (formed by sparse products, then the dense symmetric eigensolver); d receives k values. Accurate for the leading values, which is what svds returns
fn svds_sparse(a: *mem.Arena, m: sp.Csc, k: usize, d: []f64) -> err {
    let (at, e0) = sp.transpose(a, m)
    if e0 != ok { ret e0 }
    let (g, e1) = sp.multiply(a, at, m)
    if e1 != ok { ret e1 }
    let n = m.ncol
    let (dense, e2) = mem.alloc[f64](a, n * n)
    let (vals, e3) = mem.alloc[f64](a, k)
    let (vecs, e4) = mem.alloc[f64](a, n * k)
    if e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < n * n {
        dense[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < n {
        var p = g.colptr[c]
        while p < g.colptr[c + 1usize] {
            dense[g.rowidx[p] * n + c] = g.val[p]
            p += 1usize
        }
        c += 1usize
    }
    let e = eigs_sym(a, dense, n, k, 1usize, 0.0f64, vals, vecs)
    if e != ok { ret e }
    var j = 0usize
    while j < k {
        var v = vals[j]
        if v < 0.0f64 { v = 0.0f64 }
        d[j] = math.sqrt[f64](v)
        j += 1usize
    }
    ret ok
}

// RSpectra::eigs_sym on a sparse symmetric matrix (both triangles stored): the dense copy goes through eigs_sym; which and sigma as there
fn eigs_sym_sparse(a: *mem.Arena, m: sp.Csc, k: usize, which: usize, sigma: f64, vals: []f64) -> err {
    let n = m.ncol
    let (dense, e0) = mem.alloc[f64](a, n * n)
    let (vecs, e1) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok { ret mem.Full }
    var i = 0usize
    while i < n * n {
        dense[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < n {
        var p = m.colptr[c]
        while p < m.colptr[c + 1usize] {
            dense[m.rowidx[p] * n + c] = m.val[p]
            p += 1usize
        }
        c += 1usize
    }
    ret eigs_sym(a, dense, n, k, which, sigma, vals, vecs)
}

// RSpectra::eigs_sym with a matrix-free operator: f(ctx, x, y) writes A x into y for a symmetric n by n A. The operator is applied to the unit vectors to recover the matrix, which then goes through
// eigs_sym (exact, where RSpectra's Lanczos would only ever apply f); vals receives the k values selected by which as there
fn eigs_sym_op[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), n: usize, k: usize, which: usize, sigma: f64, vals: []f64) -> err {
    let (dense, e0) = mem.alloc[f64](a, n * n)
    let (ex, e1) = mem.alloc[f64](a, n)
    let (ey, e2) = mem.alloc[f64](a, n)
    let (vecs, e3) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            ex[i] = 0.0f64
            i += 1usize
        }
        ex[j] = 1.0f64
        f(ctx, ex, ey)
        i = 0usize
        while i < n {
            dense[i * n + j] = ey[i]
            i += 1usize
        }
        j += 1usize
    }
    ret eigs_sym(a, dense, n, k, which, sigma, vals, vecs)
}
