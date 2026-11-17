// R fastICA 1.2-8: fastICA(x, n.comp, method = "C") with the defaults (alg.typ "parallel", fun "logcosh", alpha 1, maxit 200, tol 1e-4, centred
// columns), the path the NMF "ica" seed takes. The C code reads the column-major n by p matrix as the row-major p by n one, so the whitening works on the
// p by p covariance of the transposed data; every matrix here is column-major and written as the true matrix, the transposes of the C buffers made explicit.
// x is n by p, wi the e by e starting matrix (rnorm(e^2) in R); answers S (n by e) and A (e by p) with x ~ S A. Signs come from the dgesdd port.

use e.algo.linalg.lapack_gesdd as lapack
use e.math
use e.math.scale as scale
use e.mem

// out (m by q) = x (m by k) * y (k by q)
fn fica_mm(x: []const f64, y: []const f64, m: usize, k: usize, q: usize, out: []f64) {
    var j = 0usize
    while j < q {
        var i = 0usize
        while i < m {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += x[i + l * m] * y[l + j * k]
                l += 1usize
            }
            out[i + j * m] = s
            i += 1usize
        }
        j += 1usize
    }
}

// out (n by m) = x (m by n) transposed
fn fica_tr(x: []const f64, m: usize, n: usize, out: []f64) {
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < m {
            out[j + i * n] = x[i + j * m]
            i += 1usize
        }
        j += 1usize
    }
}

// u diag(1 / d) u' x for the e by e matrix x (the symmetric orthogonalisation of the C code's orthog_mat_JM)
fn fica_orthog(a: *mem.Arena, x: []const f64, e: usize, out: []f64) -> err {
    let (s, e1) = mem.alloc[f64](a, e)
    let (u, e2) = mem.alloc[f64](a, e * e)
    let (vt, e3) = mem.alloc[f64](a, e * e)
    let (t1, e4) = mem.alloc[f64](a, e * e)
    let (t2, e5) = mem.alloc[f64](a, e * e)
    let (t3, e6) = mem.alloc[f64](a, e * e)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    let er = lapack.svd_all(a, x, e, e, s, u, vt)
    if er != ok { ret er }
    var j = 0usize
    while j < e {
        var i = 0usize
        while i < e {
            t1[i + j * e] = u[i + j * e] / s[j]
            i += 1usize
        }
        j += 1usize
    }
    fica_tr(u, e, e, t2)
    fica_mm(t1, t2, e, e, e, t3)
    fica_mm(t3, x, e, e, e, out)
    ret ok
}

// one symmetric logcosh step (Symm_logcosh_JM) from w (e by e) on the whitened data d (e by m): w2 is the new matrix, the tolerance is returned
fn fica_step(a: *mem.Arena, w: []const f64, d: []const f64, e: usize, m: usize, w2: []f64) -> (f64, err) {
    let (m1, e1) = mem.alloc[f64](a, e * m)
    let (dt, e2) = mem.alloc[f64](a, m * e)
    let (m3, e3) = mem.alloc[f64](a, e * e)
    let (m4, e4) = mem.alloc[f64](a, e * e)
    let (m5, e5) = mem.alloc[f64](a, e * e)
    let (wt, e6) = mem.alloc[f64](a, e * e)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, mem.Full) }
    fica_mm(w, d, e, e, m, m1)
    var q = 0usize
    while q < e * m {
        m1[q] = scale.tanh(m1[q])
        q += 1usize
    }
    fica_tr(d, e, m, dt)
    q = 0usize
    while q < e * m {
        dt[q] = dt[q] / f64(m)
        q += 1usize
    }
    fica_mm(m1, dt, e, m, e, m3)
    q = 0usize
    while q < e * m {
        m1[q] = 1.0f64 * (1.0f64 - m1[q] * m1[q])
        q += 1usize
    }
    q = 0usize
    while q < e * e {
        m4[q] = 0.0f64
        q += 1usize
    }
    var i = 0usize
    while i < e {
        var mean = 0.0f64
        var j = 0usize
        while j < m {
            mean += m1[i + j * e] / f64(m)
            j += 1usize
        }
        m4[i + i * e] = mean
        i += 1usize
    }
    fica_mm(m4, w, e, e, e, m5)
    q = 0usize
    while q < e * e {
        m4[q] = m3[q] - m5[q]
        q += 1usize
    }
    fica_tr(w, e, e, wt)
    let er = fica_orthog(a, m4, e, w2)
    if er != ok { ret (0.0f64, er) }
    fica_mm(w2, wt, e, e, e, m5)
    var tol = 0.0f64
    i = 0usize
    while i < e {
        let dv = math.abs[f64](1.0f64 - math.abs[f64](m5[i + i * e]))
        if dv > tol { tol = dv }
        i += 1usize
    }
    ret (tol, ok)
}

fn fastica(a: *mem.Arena, x: []const f64, n: usize, p: usize, e: usize, wi: []const f64, maxit: usize, lim: f64, sout: []f64, aout: []f64) -> err {
    // dc: the p by n transpose of x with each column of x centred
    let (dc, e1) = mem.alloc[f64](a, p * n)
    let (dct, e2) = mem.alloc[f64](a, n * p)
    let (cov, e3) = mem.alloc[f64](a, p * p)
    let (sv, e4) = mem.alloc[f64](a, p)
    let (uu, e5) = mem.alloc[f64](a, p * p)
    let (vv, e6) = mem.alloc[f64](a, p * p)
    let (k1, e7) = mem.alloc[f64](a, e * p)
    let (d1, e8) = mem.alloc[f64](a, e * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var j = 0usize
    while j < p {
        var tmp = 0.0f64
        var i = 0usize
        while i < n {
            tmp += x[i + j * n] / f64(n)
            i += 1usize
        }
        i = 0usize
        while i < n {
            dc[j + i * p] = x[i + j * n] - tmp
            i += 1usize
        }
        j += 1usize
    }
    fica_tr(dc, p, n, dct)
    fica_mm(dc, dct, p, n, p, cov)
    var q = 0usize
    while q < p * p {
        cov[q] = cov[q] / f64(n)
        q += 1usize
    }
    let se = lapack.svd_all(a, cov, p, p, sv, uu, vv)
    if se != ok { ret se }
    var i2 = 0usize
    while i2 < e {
        let sc = 1.0f64 / math.sqrt[f64](sv[i2])
        j = 0usize
        while j < p {
            k1[i2 + j * e] = sc * uu[j + i2 * p]
            j += 1usize
        }
        i2 += 1usize
    }
    fica_mm(k1, dc, e, p, n, d1)
    let (w0, e9) = mem.alloc[f64](a, e * e)
    let (w, e10) = mem.alloc[f64](a, e * e)
    let (wn, e11) = mem.alloc[f64](a, e * e)
    if e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    fica_tr(wi, e, e, w0)
    let oe = fica_orthog(a, w0, e, w)
    if oe != ok { ret oe }
    let (t0, r0) = fica_step(a, w, d1, e, n, wn)
    if r0 != ok { ret r0 }
    var tol = t0
    q = 0usize
    while q < e * e {
        w[q] = wn[q]
        q += 1usize
    }
    var it = 2usize
    while tol > lim && it < maxit {
        let (t1, r1) = fica_step(a, w, d1, e, n, wn)
        if r1 != ok { ret r1 }
        tol = t1
        q = 0usize
        while q < e * e {
            w[q] = wn[q]
            q += 1usize
        }
        it += 1usize
    }
    // calc_A_JM: um = w k1 (e by p), the sources um dc (e by n), A = (um um')^+ symmetric inverse applied to um
    let (um, e12) = mem.alloc[f64](a, e * p)
    let (un, e13) = mem.alloc[f64](a, e * n)
    let (umt, e14) = mem.alloc[f64](a, p * e)
    let (uut, e15) = mem.alloc[f64](a, e * e)
    let (s2, e16) = mem.alloc[f64](a, e)
    let (u2, e17) = mem.alloc[f64](a, e * e)
    let (v2, e18) = mem.alloc[f64](a, e * e)
    if e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret mem.Full }
    fica_mm(w, k1, e, e, p, um)
    fica_mm(um, dc, e, p, n, un)
    fica_tr(um, e, p, umt)
    fica_mm(um, umt, e, p, e, uut)
    let ae = lapack.svd_all(a, uut, e, e, s2, u2, v2)
    if ae != ok { ret ae }
    // vd = v diag(1 / d) with v the transpose of v2 (v2 is v')
    let (vd, e19) = mem.alloc[f64](a, e * e)
    let (u2t, e20) = mem.alloc[f64](a, e * e)
    let (pinv, e21) = mem.alloc[f64](a, e * e)
    if e19 != ok || e20 != ok || e21 != ok { ret mem.Full }
    j = 0usize
    while j < e {
        var i = 0usize
        while i < e {
            vd[i + j * e] = v2[j + i * e] * (1.0f64 / s2[j])
            i += 1usize
        }
        j += 1usize
    }
    fica_tr(u2, e, e, u2t)
    fica_mm(vd, u2t, e, e, e, pinv)
    // the C answer Ac = umt pinv is p by e row-major, so R's A (e by p) is pinv' um
    let (pt, e22) = mem.alloc[f64](a, e * e)
    if e22 != ok { ret mem.Full }
    fica_tr(pinv, e, e, pt)
    fica_mm(pt, um, e, e, p, aout)
    fica_tr(un, e, n, sout)
    ret ok
}
