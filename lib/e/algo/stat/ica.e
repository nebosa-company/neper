// R ica: `icafast` (FastICA with the symmetric "par" update and the logcosh, kurtosis or exp contrast) for
// a data matrix of at least as many rows as columns, answering the sources S, the mixing matrix M, the
// variance accounted for by each component (sorted decreasingly), the iteration count and convergence.
// Matrices are row-major. Signs and the order of the components follow the rotation the iteration
// reaches, as in R; callers compare quantities that do not depend on them (vafs, S M').
//
// Not here: the deflation algorithm "def", the n < p branch, icaimax and icajade.

use e.algo.linalg.decomp as decomp
use e.math
use e.mem

type Result = struct { s: []f64, m: []f64, vafs: []f64, iter: i64, converged: bool }

fn matmul(a: *mem.Arena, x: []const f64, y: []const f64, m: usize, n: usize, q: usize) -> ([]f64, err) {
    let (c, e) = mem.alloc[f64](a, m * q)
    if e != ok { ret (c, e) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                s += x[i * n + k] * y[k * q + j]
                k += 1usize
            }
            c[i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret (c, ok)
}

fn transpose(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> ([]f64, err) {
    let (t, e) = mem.alloc[f64](a, m * n)
    if e != ok { ret (t, e) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            t[j * m + i] = x[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (t, ok)
}

// symmetric eigen by cyclic Jacobi: values descending, vectors in the columns (row-major p x p)
fn eigen_sym(a: *mem.Arena, s: []const f64, p: usize) -> ([]f64, []f64, err) {
    var none: []f64 = zero
    let (m, e1) = mem.alloc[f64](a, p * p)
    let (v, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret (none, none, e1) }
    if e2 != ok { ret (none, none, e2) }
    var i = 0usize
    while i < p * p {
        m[i] = s[i]
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        v[i * p + i] = 1.0f64
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 100usize {
        var off = 0.0f64
        var q = 0usize
        while q < p {
            var r = q + 1usize
            while r < p {
                off += m[q * p + r] * m[q * p + r]
                r += 1usize
            }
            q += 1usize
        }
        if off < 1.0e-300f64 { break }
        q = 0usize
        while q + 1usize < p {
            var r = q + 1usize
            while r < p {
                let apq = m[q * p + r]
                if apq != 0.0f64 {
                    let theta = (m[r * p + r] - m[q * p + q]) / (2.0f64 * apq)
                    var t = 1.0f64 / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0f64))
                    if theta < 0.0f64 { t = 0.0f64 - t }
                    let c = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let sn = t * c
                    var k = 0usize
                    while k < p {
                        let akp = m[k * p + q]
                        let akq = m[k * p + r]
                        m[k * p + q] = c * akp - sn * akq
                        m[k * p + r] = sn * akp + c * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let apk = m[q * p + k]
                        let aqk = m[r * p + k]
                        m[q * p + k] = c * apk - sn * aqk
                        m[r * p + k] = sn * apk + c * aqk
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let vkp = v[k * p + q]
                        let vkq = v[k * p + r]
                        v[k * p + q] = c * vkp - sn * vkq
                        v[k * p + r] = sn * vkp + c * vkq
                        k += 1usize
                    }
                }
                r += 1usize
            }
            q += 1usize
        }
        sweep += 1usize
    }
    // order by descending eigenvalue
    let (vals, e3) = mem.alloc[f64](a, p)
    let (vecs, e4) = mem.alloc[f64](a, p * p)
    let (ord, e5) = mem.alloc[usize](a, p)
    if e3 != ok { ret (none, none, e3) }
    if e4 != ok { ret (none, none, e4) }
    if e5 != ok { ret (none, none, e5) }
    i = 0usize
    while i < p {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < p {
        var j = i
        while j > 0usize && m[ord[j - 1usize] * p + ord[j - 1usize]] < m[ord[j] * p + ord[j]] {
            let t = ord[j]
            ord[j] = ord[j - 1usize]
            ord[j - 1usize] = t
            j -= 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        vals[i] = m[ord[i] * p + ord[i]]
        var r = 0usize
        while r < p {
            vecs[r * p + i] = v[r * p + ord[i]]
            r += 1usize
        }
        i += 1usize
    }
    ret (vals, vecs, ok)
}

fn fun1(f: u8, x: f64, alpha: f64) -> f64 {
    if f == 1u8 { ret x * x * x }
    if f == 2u8 { ret x * math.exp[f64](0.0f64 - x * x / 2.0f64) }
    let e = math.exp[f64](2.0f64 * alpha * x)
    ret (e - 1.0f64) / (e + 1.0f64)
}

fn fun2(f: u8, x: f64, alpha: f64) -> f64 {
    if f == 1u8 { ret 3.0f64 * x * x }
    if f == 2u8 { ret math.exp[f64](0.0f64 - x * x / 2.0f64) * (1.0f64 - x * x) }
    let t = fun1(0u8, x, alpha)
    ret alpha * (1.0f64 - t * t)
}

// polar factor of a row-major k x k matrix (decomp is column-major, so t(Vr) Ur)
fn polar(a: *mem.Arena, x: []const f64, k: usize) -> ([]f64, err) {
    let (sv, e) = decomp.svd(a, x, k, k)
    if e != ok {
        var none: []f64 = zero
        ret (none, e)
    }
    let (vt, vte) = transpose(a, sv.v, k, k)
    if vte != ok { ret (vt, vte) }
    let (r, re) = matmul(a, vt, sv.u, k, k, k)
    ret (r, re)
}

// icafast(X, nc, center = TRUE, maxit, tol, alg = "par", fun): fun 0 logcosh, 1 kur, 2 exp
fn icafast(a: *mem.Arena, x0: []const f64, n: usize, p: usize, nc: usize, maxit: i64, tol: f64, fun: u8, alpha: f64) -> (Result, err) {
    var none: Result = zero
    let (x, xe) = mem.alloc[f64](a, n * p)
    if xe != ok { ret (none, xe) }
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x0[i * p + j]
            i += 1usize
        }
        m = m / f64(n)
        i = 0usize
        while i < n {
            x[i * p + j] = x0[i * p + j] - m
            i += 1usize
        }
        j += 1usize
    }
    let nf = f64(n)
    let (xt, xte) = transpose(a, x, n, p)
    if xte != ok { ret (none, xte) }
    let (cc, ce) = matmul(a, xt, x, p, n, p)
    if ce != ok { ret (none, ce) }
    var i = 0usize
    while i < p * p {
        cc[i] = cc[i] / nf
        i += 1usize
    }
    let (vals, vecs, ee) = eigen_sym(a, cc, p)
    if ee != ok { ret (none, ee) }
    // Mprt = D V' (nc x p), Pmat = V D^-1 (p x nc)
    let (mprt, me) = mem.alloc[f64](a, nc * p)
    let (pmat, pe) = mem.alloc[f64](a, p * nc)
    if me != ok { ret (none, me) }
    if pe != ok { ret (none, pe) }
    var k = 0usize
    while k < nc {
        let d = math.sqrt[f64](vals[k])
        j = 0usize
        while j < p {
            mprt[k * p + j] = d * vecs[j * p + k]
            pmat[j * nc + k] = vecs[j * p + k] / d
            j += 1usize
        }
        k += 1usize
    }
    let (xw, xwe) = matmul(a, x, pmat, n, p, nc)
    if xwe != ok { ret (none, xwe) }
    let (rmat0, re0) = mem.alloc[f64](a, nc * nc)
    if re0 != ok { ret (none, re0) }
    i = 0usize
    while i < nc * nc {
        rmat0[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nc {
        rmat0[i * nc + i] = 1.0f64
        i += 1usize
    }
    var rmat = rmat0
    var vtol = 1.0f64
    var iter = 0i64
    while vtol > tol && iter < maxit {
        let mark = mem.mark(a)
        let (smat, se) = matmul(a, xw, rmat, n, nc, nc)
        if se != ok { ret (none, se) }
        let (g, ge) = mem.alloc[f64](a, n * nc)
        if ge != ok { ret (none, ge) }
        i = 0usize
        while i < n * nc {
            g[i] = fun1(fun, smat[i], alpha)
            i += 1usize
        }
        let (xwt, xwte) = transpose(a, xw, n, nc)
        if xwte != ok { ret (none, xwte) }
        let (rn, rne) = matmul(a, xwt, g, nc, n, nc)
        if rne != ok { ret (none, rne) }
        j = 0usize
        while j < nc {
            var cm = 0.0f64
            i = 0usize
            while i < n {
                cm += fun2(fun, smat[i * nc + j], alpha)
                i += 1usize
            }
            cm = cm / nf
            i = 0usize
            while i < nc {
                rn[i * nc + j] = rn[i * nc + j] / nf - rmat[i * nc + j] * cm
                i += 1usize
            }
            j += 1usize
        }
        let (pol, pe2) = polar(a, rn, nc)
        if pe2 != ok { ret (none, pe2) }
        var mn = 1.0e300f64
        j = 0usize
        while j < nc {
            var cs = 0.0f64
            i = 0usize
            while i < nc {
                cs += rmat[i * nc + j] * pol[i * nc + j]
                i += 1usize
            }
            if math.abs[f64](cs) < mn { mn = math.abs[f64](cs) }
            j += 1usize
        }
        vtol = 1.0f64 - mn
        iter += 1i64
        // keep the new rotation across the arena rewind
        i = 0usize
        while i < nc * nc {
            rmat0[i] = pol[i]
            i += 1usize
        }
        mem.reset(a, mark)
        rmat = rmat0
    }
    // M = t(Rmat) Mprt (nc x p); vafs = rowSums(M^2), sorted decreasingly with the order applied to R
    let (rt, rte) = transpose(a, rmat, nc, nc)
    if rte != ok { ret (none, rte) }
    let (mm, mme) = matmul(a, rt, mprt, nc, nc, p)
    if mme != ok { ret (none, mme) }
    let (vaf, vfe) = mem.alloc[f64](a, nc)
    let (ord, oe) = mem.alloc[usize](a, nc)
    if vfe != ok { ret (none, vfe) }
    if oe != ok { ret (none, oe) }
    var tot = 0.0f64
    i = 0usize
    while i < n * p {
        tot += x[i] * x[i]
        i += 1usize
    }
    k = 0usize
    while k < nc {
        var s = 0.0f64
        j = 0usize
        while j < p {
            s += mm[k * p + j] * mm[k * p + j]
            j += 1usize
        }
        vaf[k] = s
        ord[k] = k
        k += 1usize
    }
    i = 1usize
    while i < nc {
        var q = i
        while q > 0usize && vaf[ord[q - 1usize]] < vaf[ord[q]] {
            let t = ord[q]
            ord[q] = ord[q - 1usize]
            ord[q - 1usize] = t
            q -= 1usize
        }
        i += 1usize
    }
    let (rs, rse) = mem.alloc[f64](a, nc * nc)
    let (ms, mse) = mem.alloc[f64](a, nc * p)
    let (vs, vse) = mem.alloc[f64](a, nc)
    if rse != ok { ret (none, rse) }
    if mse != ok { ret (none, mse) }
    if vse != ok { ret (none, vse) }
    k = 0usize
    while k < nc {
        vs[k] = nf * vaf[ord[k]] / tot
        j = 0usize
        while j < p {
            ms[k * p + j] = mm[ord[k] * p + j]
            j += 1usize
        }
        i = 0usize
        while i < nc {
            rs[i * nc + k] = rmat[i * nc + ord[k]]
            i += 1usize
        }
        k += 1usize
    }
    let (s, sse) = matmul(a, xw, rs, n, nc, nc)
    if sse != ok { ret (none, sse) }
    // M as R returns it is t(M): p x nc
    let (mt, mte) = transpose(a, ms, nc, p)
    if mte != ok { ret (none, mte) }
    ret (Result { s: s, m: mt, vafs: vs, iter: iter, converged: vtol <= tol }, ok)
}
