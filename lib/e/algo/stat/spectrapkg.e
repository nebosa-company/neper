// RSpectra and irlba: the k leading singular triplets (svds, irlba) and the k wanted eigenpairs of a symmetric (eigs_sym) or general (eigs) matrix, from the matrix-free Krylov-Schur iteration of e.algo.stat.arpack
// (Lanczos for symmetric, Arnoldi for general problems, restarted until RSpectra's Ritz test passes) on a dense matrix, a compressed-column sparse matrix or an operator f(ctx, x, y) = A x. Shift-invert (sigma, and SM on a matrix)
// factors A - sigma I once and iterates with its inverse, as RSpectra does. The default Krylov size is RSpectra's, min(n, max(2k + 1, 20)); the start vector is a fixed one (R draws its own: the converged pairs do not depend on it).
// Dense symmetric and svds matrices are row-major, general ones column-major (R's layout).
//
// Not here: complex input matrices (RSpectra has none), ARPACK's own shift strategy (the same pairs by another path).

use e.algo.linalg.decomp as dc
use e.algo.rand.r as rr
use e.algo.linalg.matrix as mx
use e.algo.linalg.sparse as sp
use e.algo.stat.arpack as ar
use e.math
use e.mem

error Singular

// a dense matrix operator: y = A x (A is nr by nc; row-major if rowmaj, else column-major)
type MatOp = struct { x: []const f64, nr: usize, nc: usize, rowmaj: bool }

fn at(c: *MatOp, r: usize, q: usize) -> f64 {
    if c.rowmaj { ret c.x[r * c.nc + q] }
    ret c.x[q * c.nr + r]
}

fn mat_mul(c: *MatOp, x: []const f64, y: []f64) {
    var r = 0usize
    while r < c.nr {
        var s = 0.0f64
        var q = 0usize
        while q < c.nc {
            s += at(c, r, q) * x[q]
            q += 1usize
        }
        y[r] = s
        r += 1usize
    }
}

fn mat_tmul(c: *MatOp, x: []const f64, y: []f64) {
    var q = 0usize
    while q < c.nc {
        var s = 0.0f64
        var r = 0usize
        while r < c.nr {
            s += at(c, r, q) * x[r]
            r += 1usize
        }
        y[q] = s
        q += 1usize
    }
}

// a compressed-column sparse operator
type SpOp = struct { m: sp.Csc }

fn sp_mul(c: *SpOp, x: []const f64, y: []f64) {
    var r = 0usize
    while r < c.m.nrow {
        y[r] = 0.0f64
        r += 1usize
    }
    var j = 0usize
    while j < c.m.ncol {
        var p = c.m.colptr[j]
        while p < c.m.colptr[j + 1usize] {
            y[c.m.rowidx[p]] += c.m.val[p] * x[j]
            p += 1usize
        }
        j += 1usize
    }
}

fn sp_tmul(c: *SpOp, x: []const f64, y: []f64) {
    var j = 0usize
    while j < c.m.ncol {
        var s = 0.0f64
        var p = c.m.colptr[j]
        while p < c.m.colptr[j + 1usize] {
            s += c.m.val[p] * x[c.m.rowidx[p]]
            p += 1usize
        }
        y[j] = s
        j += 1usize
    }
}

// the operator x -> (A - sigma I)^-1 x from an LU factorisation
type LuOp = struct { f: mx.ConstMatrix[f64], perm: []usize }

fn lu_apply(c: *LuOp, x: []const f64, y: []f64) {
    let e = mx.solve_lu(c.f, c.perm, y, x)
    if e != ok { y[0usize] = 0.0f64 }
}

// factor A - shift I (dense, row-major copy x) into op
fn lu_make(a: *mem.Arena, x: []const f64, n: usize, shift: f64, op: *LuOp) -> err {
    let (cp, e0) = mem.alloc[f64](a, n * n)
    let (fa, e1) = mem.alloc[f64](a, n * n)
    let (pm, e2) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n * n {
        cp[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        cp[i * n + i] = cp[i * n + i] - shift
        i += 1usize
    }
    let (fm, e3) = mx.view[f64](fa, n, n, n)
    let (src, e4) = mx.view_const[f64](cp, n, n, n)
    if e3 != ok || e4 != ok { ret mx.Shape }
    let (sgn, e5) = mx.lu_factor(fm, pm, src)
    if e5 != ok { ret e5 }
    if sgn == 0.0f64 { ret Singular }
    let (fc, e6) = mx.view_const[f64](fa, n, n, n)
    if e6 != ok { ret e6 }
    op.f = fc
    op.perm = pm
    ret ok
}

fn default_ncv(n: usize, k: usize) -> usize {
    var c = 2usize * k + 1usize
    if c < 20usize { c = 20usize }
    if c > n { c = n }
    ret c
}

fn start_vec(v: []f64) {
    var i = 0usize
    while i < v.len {
        v[i] = 0.5f64 + math.sin[f64](f64(i + 1usize) * 1.3f64)
        i += 1usize
    }
}

// order the k computed pairs: bymod false, decreasing real part (RSpectra's symmetric listing); true, decreasing modulus with the positive imaginary part first inside a conjugate pair (its general listing)
fn sort_pairs(a: *mem.Arena, ore: []f64, oim: []f64, vre: []f64, vim: []f64, n: usize, k: usize, bymod: bool) -> err {
    let (pk, e0) = mem.alloc[usize](a, k)
    let (tr, e1) = mem.alloc[f64](a, k)
    let (ti, e2) = mem.alloc[f64](a, k)
    let (wr, e3) = mem.alloc[f64](a, n * k)
    let (wi, e4) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < k {
        pk[i] = i
        i += 1usize
    }
    i = 1usize
    while i < k {
        let t = pk[i]
        var mt = ore[t]
        if bymod { mt = math.sqrt[f64](ore[t] * ore[t] + oim[t] * oim[t]) }
        var j = i
        while j > 0usize {
            let q = pk[j - 1usize]
            var mq = ore[q]
            if bymod { mq = math.sqrt[f64](ore[q] * ore[q] + oim[q] * oim[q]) }
            let tie = math.abs[f64](mq - mt) <= 1.0e-10f64 * (1.0f64 + math.abs[f64](mt))
            if bymod && (mq < mt - 1.0e-10f64 * (1.0f64 + math.abs[f64](mt)) || (tie && oim[q] < oim[t])) {
                pk[j] = q
                j -= 1usize
            } else {
                if !bymod && mq < mt {
                    pk[j] = q
                    j -= 1usize
                } else {
                    break
                }
            }
        }
        pk[j] = t
        i += 1usize
    }
    i = 0usize
    while i < k {
        tr[i] = ore[pk[i]]
        ti[i] = oim[pk[i]]
        var r = 0usize
        while r < n {
            wr[r * k + i] = vre[r * k + pk[i]]
            wi[r * k + i] = vim[r * k + pk[i]]
            r += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < k {
        ore[i] = tr[i]
        oim[i] = ti[i]
        i += 1usize
    }
    i = 0usize
    while i < n * k {
        vre[i] = wr[i]
        vim[i] = wi[i]
        i += 1usize
    }
    ret ok
}

// eigs_sym through an operator: which 0 LM, 1 LA, 2 SA, 3 SM (smallest modulus of the operator itself), 5 BE; ncv the Krylov size, tol the Ritz tolerance, v0 the start vector; vals listed decreasing, vecs n by k row-major
fn eigs_sym_ks[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), n: usize, k: usize, which: usize, ncv: usize, tol: f64, v0: []const f64, vals: []f64, vecs: []f64) -> err {
    let (oi, e0) = mem.alloc[f64](a, k)
    let (vi, e1) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok { ret mem.Full }
    var kw = which
    if which == 3usize { kw = 6usize }
    let (it, e2) = ar.krylov[Ctx](a, ctx, f, n, k, kw, true, ncv, tol, 5000usize, v0, vals, oi, vecs, vi)
    if e2 != ok { ret e2 }
    ret sort_pairs(a, vals, oi, vecs, vi, n, k, false)
}

// eigs through an operator for a general real A: which 0 LM, 1 LR, 2 SR, 3 LI, 4 SI, 5 SM (of the operator itself); the values listed by decreasing modulus (positive imaginary part first), vectors n by k row-major, unit norm, up to a complex phase
fn eigs_gen_ks[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), n: usize, k: usize, which: usize, ncv: usize, tol: f64, v0: []const f64, re: []f64, im: []f64, vre: []f64, vim: []f64) -> err {
    var kw = which
    if which == 5usize { kw = 6usize }
    let (it, e2) = ar.krylov[Ctx](a, ctx, f, n, k, kw, false, ncv, tol, 5000usize, v0, re, im, vre, vim)
    if e2 != ok { ret e2 }
    ret sort_pairs(a, re, im, vre, vim, n, k, true)
}

// the inverse-operator values theta become sigma + 1 / theta
fn unshift(re: []f64, im: []f64, k: usize, shift: f64) {
    var i = 0usize
    while i < k {
        let q = re[i] * re[i] + im[i] * im[i]
        re[i] = shift + re[i] / q
        im[i] = 0.0f64 - im[i] / q
        i += 1usize
    }
}

// eigs_sym on a symmetric operator or matrix: which 0 LM, 1 LA, 2 SA, 3 SM, 4 the eigenvalues nearest sigma, 5 BE (3 and 4 invert A - sigma I, so they need xd, the dense row-major copy; sigma is 0 for SM)
fn eigs_sym_core[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), xd: []const f64, n: usize, k: usize, which: usize, sigma: f64, vals: []f64, vecs: []f64) -> err {
    let (v0, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret mem.Full }
    start_vec(v0)
    let ncv = default_ncv(n, k)
    if which == 3usize || which == 4usize {
        var shift = 0.0f64
        if which == 4usize { shift = sigma }
        var lu: LuOp = zero
        let el = lu_make(a, xd, n, shift, &lu)
        if el != ok { ret el }
        let e1 = eigs_sym_ks[LuOp](a, &lu, lu_apply, n, k, 0usize, ncv, 1.0e-14f64, v0, vals, vecs)
        if e1 != ok { ret e1 }
        let (zi, e2) = mem.alloc[f64](a, k)
        let (zv, e3) = mem.alloc[f64](a, n * k)
        if e2 != ok || e3 != ok { ret mem.Full }
        var i = 0usize
        while i < k {
            zi[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < n * k {
            zv[i] = 0.0f64
            i += 1usize
        }
        unshift(vals, zi, k, shift)
        ret sort_pairs(a, vals, zi, vecs, zv, n, k, false)
    }
    ret eigs_sym_ks[Ctx](a, ctx, f, n, k, which, ncv, 1.0e-14f64, v0, vals, vecs)
}

// eigs for a general matrix or operator: which 0 LM, 1 LR, 2 SR, 3 LI, 4 SI, 5 SM, 6 the eigenvalues nearest sigma (5 and 6 invert A - sigma I, so they need xd, the dense row-major copy)
fn eigs_gen_core[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), xd: []const f64, n: usize, k: usize, which: usize, sigma: f64, re: []f64, im: []f64, vre: []f64, vim: []f64) -> err {
    let (v0, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret mem.Full }
    start_vec(v0)
    let ncv = default_ncv(n, k)
    if which == 5usize && xd.len == 0usize {
        ret eigs_gen_ks[Ctx](a, ctx, f, n, k, 5usize, ncv, 1.0e-14f64, v0, re, im, vre, vim)
    }
    if which >= 5usize {
        var shift = 0.0f64
        if which == 6usize { shift = sigma }
        var lu: LuOp = zero
        let el = lu_make(a, xd, n, shift, &lu)
        if el != ok { ret el }
        let e1 = eigs_gen_ks[LuOp](a, &lu, lu_apply, n, k, 0usize, ncv, 1.0e-14f64, v0, re, im, vre, vim)
        if e1 != ok { ret e1 }
        unshift(re, im, k, shift)
        ret sort_pairs(a, re, im, vre, vim, n, k, true)
    }
    ret eigs_gen_ks[Ctx](a, ctx, f, n, k, which, ncv, 1.0e-14f64, v0, re, im, vre, vim)
}

// eigs_sym on a dense symmetric n by n matrix (row-major): the k values selected by which (0 LM, 1 LA, 2 SA, 3 SM, 4 nearest sigma, 5 BE), listed decreasing as RSpectra does, and their vectors into vecs (n by k)
fn eigs_sym(a: *mem.Arena, x: []const f64, n: usize, k: usize, which: usize, sigma: f64, vals: []f64, vecs: []f64) -> err {
    var op = MatOp { x: x, nr: n, nc: n, rowmaj: true }
    ret eigs_sym_core[MatOp](a, &op, mat_mul, x, n, k, which, sigma, vals, vecs)
}

// eigs(A, k, which) for a general real n by n matrix x (column-major): which 0 LM, 1 LR, 2 SR, 3 LI, 4 SI, 5 SM, 6 nearest sigma. The values come listed in decreasing modulus with the positive imaginary part first inside a conjugate pair, as RSpectra returns them;
// the unit-norm vectors are n by k row-major in vre/vim, each up to a complex phase
fn eigs_general(a: *mem.Arena, x: []const f64, n: usize, k: usize, which: usize, sigma: f64, re: []f64, im: []f64, vre: []f64, vim: []f64) -> err {
    var op = MatOp { x: x, nr: n, nc: n, rowmaj: false }
    var xr: []const f64 = x
    if which >= 5usize {
        let (t, e0) = mem.alloc[f64](a, n * n)
        if e0 != ok { ret mem.Full }
        var r = 0usize
        while r < n {
            var q = 0usize
            while q < n {
                t[r * n + q] = x[q * n + r]
                q += 1usize
            }
            r += 1usize
        }
        xr = t
    }
    ret eigs_gen_core[MatOp](a, &op, mat_mul, xr, n, k, which, sigma, re, im, vre, vim)
}

// the pair of Gram operators of svds: y = A' A x (the n side) or y = A A' x (the m side) from the operators of A and A'
type Gram[Ctx: type] = struct { c: *Ctx, f: fn(*Ctx, []const f64, []f64), ft: fn(*Ctx, []const f64, []f64), t: []f64 }

fn gram_n[Ctx: type](g: *Gram[Ctx], x: []const f64, y: []f64) {
    g.f(g.c, x, g.t)
    g.ft(g.c, g.t, y)
}

fn gram_m[Ctx: type](g: *Gram[Ctx], x: []const f64, y: []f64) {
    g.ft(g.c, x, g.t)
    g.f(g.c, g.t, y)
}

// svds through the operators f (A x, x of length n) and ft (A' x, x of length m), A being m by n: the k largest singular values into d, left vectors into u (m by k) and right vectors into v (n by k), row-major; the Lanczos runs on the Gram matrix of the smaller side
fn svds_core[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), ft: fn(*Ctx, []const f64, []f64), m: usize, n: usize, k: usize, d: []f64, u: []f64, v: []f64) -> err {
    var nside = n
    if m < n { nside = m }
    let (w, e0) = mem.alloc[f64](a, nside * k)
    let (lam, e1) = mem.alloc[f64](a, k)
    let (t, e2) = mem.alloc[f64](a, nside)
    let (xs, e3) = mem.alloc[f64](a, n)
    let (ys, e4) = mem.alloc[f64](a, m)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    // the Gram operator needs the other side's length for its temporary
    var tl = m
    if n > m { tl = n }
    let (tt, e5) = mem.alloc[f64](a, tl)
    if e5 != ok { ret mem.Full }
    var g = Gram[Ctx] { c: ctx, f: f, ft: ft, t: tt }
    var e = ok
    if n <= m {
        g.t = tt[0usize..m]
        e = eigs_sym_core[Gram[Ctx]](a, &g, gram_n[Ctx], tt[0usize..0usize], nside, k, 1usize, 0.0f64, lam, w)
    } else {
        g.t = tt[0usize..n]
        e = eigs_sym_core[Gram[Ctx]](a, &g, gram_m[Ctx], tt[0usize..0usize], nside, k, 1usize, 0.0f64, lam, w)
    }
    if e != ok { ret e }
    var j = 0usize
    while j < k {
        var sv = lam[j]
        if sv < 0.0f64 { sv = 0.0f64 }
        sv = math.sqrt[f64](sv)
        d[j] = sv
        var i = 0usize
        if n <= m {
            while i < n {
                xs[i] = w[i * k + j]
                v[i * k + j] = xs[i]
                i += 1usize
            }
            f(ctx, xs, ys)
            i = 0usize
            while i < m {
                var q = 0.0f64
                if sv > 0.0f64 { q = ys[i] / sv }
                u[i * k + j] = q
                i += 1usize
            }
        } else {
            while i < m {
                ys[i] = w[i * k + j]
                u[i * k + j] = ys[i]
                i += 1usize
            }
            ft(ctx, ys, xs)
            i = 0usize
            while i < n {
                var q = 0.0f64
                if sv > 0.0f64 { q = xs[i] / sv }
                v[i * k + j] = q
                i += 1usize
            }
        }
        j += 1usize
    }
    ret ok
}

// the k largest singular values of the dense m by n row-major x into d, left vectors into u (m by k) and right vectors into v (n by k)
fn svds(a: *mem.Arena, x: []const f64, m: usize, n: usize, k: usize, d: []f64, u: []f64, v: []f64) -> err {
    var op = MatOp { x: x, nr: m, nc: n, rowmaj: true }
    ret svds_core[MatOp](a, &op, mat_mul, mat_tmul, m, n, k, d, u, v)
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

// the dense row-major copy of a compressed-column matrix (the factorisation of shift-invert wants one)
fn densify(a: *mem.Arena, m: sp.Csc) -> ([]f64, err) {
    let (d, e0) = mem.alloc[f64](a, m.nrow * m.ncol)
    if e0 != ok { ret (d, mem.Full) }
    var i = 0usize
    while i < m.nrow * m.ncol {
        d[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < m.ncol {
        var p = m.colptr[c]
        while p < m.colptr[c + 1usize] {
            d[m.rowidx[p] * m.ncol + c] = m.val[p]
            p += 1usize
        }
        c += 1usize
    }
    ret (d, ok)
}

// RSpectra::svds on a sparse matrix (compressed-column, as Matrix::dgCMatrix stores it): d the k largest singular values, u (nrow by k) and v (ncol by k) the vectors, row-major
fn svds_sparse(a: *mem.Arena, m: sp.Csc, k: usize, d: []f64, u: []f64, v: []f64) -> err {
    var op = SpOp { m: m }
    ret svds_core[SpOp](a, &op, sp_mul, sp_tmul, m.nrow, m.ncol, k, d, u, v)
}

// RSpectra::eigs_sym on a sparse symmetric matrix (both triangles stored): which and sigma as eigs_sym; vals the k values, vecs the vectors (n by k)
fn eigs_sym_sparse(a: *mem.Arena, m: sp.Csc, k: usize, which: usize, sigma: f64, vals: []f64, vecs: []f64) -> err {
    var op = SpOp { m: m }
    var xd: []const f64 = vals[0usize..0usize]
    if which == 3usize || which == 4usize {
        let (dn, e0) = densify(a, m)
        if e0 != ok { ret e0 }
        xd = dn
    }
    ret eigs_sym_core[SpOp](a, &op, sp_mul, xd, m.ncol, k, which, sigma, vals, vecs)
}

// RSpectra::eigs on a sparse general matrix: which and the outputs as eigs_general
fn eigs_sparse(a: *mem.Arena, m: sp.Csc, k: usize, which: usize, sigma: f64, re: []f64, im: []f64, vre: []f64, vim: []f64) -> err {
    var op = SpOp { m: m }
    var xd: []const f64 = re[0usize..0usize]
    if which >= 5usize {
        let (dn, e0) = densify(a, m)
        if e0 != ok { ret e0 }
        xd = dn
    }
    ret eigs_gen_core[SpOp](a, &op, sp_mul, xd, m.ncol, k, which, sigma, re, im, vre, vim)
}

// RSpectra::eigs_sym with a matrix-free operator: f(ctx, x, y) writes A x into y for a symmetric n by n A; which 0 LM, 1 LA, 2 SA, 3 SM (of the operator itself, as RSpectra does for a function), 5 BE
fn eigs_sym_op[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), n: usize, k: usize, which: usize, vals: []f64, vecs: []f64) -> err {
    let (v0, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret mem.Full }
    start_vec(v0)
    ret eigs_sym_ks[Ctx](a, ctx, f, n, k, which, default_ncv(n, k), 1.0e-14f64, v0, vals, vecs)
}

// RSpectra::svds with matrix-free operators: f(ctx, x, y) writes A x (x of length n, y of length m) and ft(ctx, x, y) writes A' x; d the k largest singular values, u (m by k) and v (n by k) the vectors
fn svds_op[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), ft: fn(*Ctx, []const f64, []f64), m: usize, n: usize, k: usize, d: []f64, u: []f64, v: []f64) -> err {
    ret svds_core[Ctx](a, ctx, f, ft, m, n, k, d, u, v)
}

// RSpectra::eigs with a general real operator f(ctx, x, y) = A x; which 0 LM, 1 LR, 2 SR, 3 LI, 4 SI, 5 SM (of the operator itself); outputs as eigs_general
fn eigs_op[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), n: usize, k: usize, which: usize, re: []f64, im: []f64, vre: []f64, vim: []f64) -> err {
    ret eigs_gen_core[Ctx](a, ctx, f, re[0usize..0usize], n, k, which, 0.0f64, re, im, vre, vim)
}

// the phase that makes the largest-modulus component of each column (n by k, row-major, real part vre and imaginary part vim) real and positive: ARPACK fixes no phase, so this is how vectors are compared
fn rotate_phase(vre: []f64, vim: []f64, n: usize, k: usize) {
    var j = 0usize
    while j < k {
        var best = 0.0f64
        var br = 1.0f64
        var bi = 0.0f64
        var i = 0usize
        while i < n {
            let md = math.sqrt[f64](vre[i * k + j] * vre[i * k + j] + vim[i * k + j] * vim[i * k + j])
            if md > best {
                best = md
                br = vre[i * k + j] / md
                bi = 0.0f64 - vim[i * k + j] / md
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            let xr = vre[i * k + j] * br - vim[i * k + j] * bi
            let xi = vre[i * k + j] * bi + vim[i * k + j] * br
            vre[i * k + j] = xr
            vim[i * k + j] = xi
            i += 1usize
        }
        j += 1usize
    }
}

// the sign that makes the largest component of each column of u (m by k) positive, applied to the same column of v (n by k)
fn svd_sign(u: []f64, v: []f64, m: usize, n: usize, k: usize) {
    var j = 0usize
    while j < k {
        var best = 0.0f64
        var sg = 1.0f64
        var i = 0usize
        while i < m {
            if math.abs[f64](u[i * k + j]) > best {
                best = math.abs[f64](u[i * k + j])
                sg = 1.0f64
                if u[i * k + j] < 0.0f64 { sg = -1.0f64 }
            }
            i += 1usize
        }
        i = 0usize
        while i < m {
            u[i * k + j] = u[i * k + j] * sg
            i += 1usize
        }
        i = 0usize
        while i < n {
            v[i * k + j] = v[i * k + j] * sg
            i += 1usize
        }
        j += 1usize
    }
}

// sum of x[r, c] * (position of the element in R's column-major order, from 1) over an r by c row-major matrix: the checksum the oracle groups compare
fn wsum(x: []const f64, rows: usize, cols: usize) -> f64 {
    var s = 0.0f64
    var r = 0usize
    while r < rows {
        var c = 0usize
        while c < cols {
            s += x[r * cols + c] * f64(c * rows + r + 1usize)
            c += 1usize
        }
        r += 1usize
    }
    ret s
}
