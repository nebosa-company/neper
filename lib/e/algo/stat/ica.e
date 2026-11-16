// R ica: `icafast` (FastICA with the symmetric "par" update and the logcosh, kurtosis or exp contrast) for
// a data matrix of at least as many rows as columns, answering the sources S, the mixing matrix M, the
// variance accounted for by each component (sorted decreasingly), the iteration count and convergence.
// Matrices are row-major. Signs and the order of the components follow the rotation the iteration
// reaches, as in R; callers compare quantities that do not depend on them (vafs, S M').
//
// And icajade, icaimax (Newton and gradient infomax, tanh, log and ext contrasts) and icafast_gen (parallel or deflation update, any shape).

use e.algo.linalg.decomp as decomp
use e.math
use e.math.scale as scale
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

// ---- icajade and icaimax: the shared whitening and the common finish

type Whit = struct { x: []f64, mprt: []f64, pmat: []f64, xw: []f64, nc: usize }

// centre X (n by p, row-major, n >= p) and whiten it to nc components: Mprt = D V' (nc by p), Pmat = V D^-1 (p by nc), Xw = X Pmat
fn prewhiten(a: *mem.Arena, x0: []const f64, n: usize, p: usize, nc: usize) -> (Whit, err) {
    var none: Whit = zero
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
    ret (Whit { x: x, mprt: mprt, pmat: pmat, xw: xw, nc: nc }, ok)
}

fn identity(a: *mem.Arena, k: usize) -> ([]f64, err) {
    let (m, e) = mem.alloc[f64](a, k * k)
    if e != ok { ret (m, e) }
    var i = 0usize
    while i < k * k {
        m[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        m[i * k + i] = 1.0f64
        i += 1usize
    }
    ret (m, ok)
}

// the end of icajade and icaimax: M = R' Mprt, the vafs sorted decreasingly with the rotation reordered to match, S = Xw R
fn finish_ica(a: *mem.Arena, w: Whit, rmat: []const f64, n: usize, p: usize, iter: i64, conv: bool) -> (Result, err) {
    var none: Result = zero
    let nc = w.nc
    let nf = f64(n)
    let (rt, rte) = transpose(a, rmat, nc, nc)
    if rte != ok { ret (none, rte) }
    let (mm, mme) = matmul(a, rt, w.mprt, nc, nc, p)
    if mme != ok { ret (none, mme) }
    let (vaf, vfe) = mem.alloc[f64](a, nc)
    let (ord, oe) = mem.alloc[usize](a, nc)
    if vfe != ok { ret (none, vfe) }
    if oe != ok { ret (none, oe) }
    var tot = 0.0f64
    var i = 0usize
    while i < n * p {
        tot += w.x[i] * w.x[i]
        i += 1usize
    }
    var k = 0usize
    while k < nc {
        var s = 0.0f64
        var j = 0usize
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
        var j = 0usize
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
    let (s, sse) = matmul(a, w.xw, rs, n, nc, nc)
    if sse != ok { ret (none, sse) }
    let (mt, mte) = transpose(a, ms, nc, p)
    if mte != ok { ret (none, mte) }
    ret (Result { s: s, m: mt, vafs: vs, iter: iter, converged: conv }, ok)
}

// icajade(X, nc, center = TRUE, maxit, tol): joint diagonalisation of the fourth-order cumulant matrices by Jacobi rotations
fn icajade(a: *mem.Arena, x0: []const f64, n: usize, p: usize, nc: usize, maxit: i64, tol: f64) -> (Result, err) {
    var none: Result = zero
    let (w, we) = prewhiten(a, x0, n, p, nc)
    if we != ok { ret (none, we) }
    let (rmat, re) = identity(a, nc)
    if re != ok { ret (none, re) }
    let nf = f64(n)
    let ncstar = nc * (nc + 1usize) / 2usize
    let width = nc * ncstar
    let (em, ee) = mem.alloc[f64](a, nc * width)
    if ee != ok { ret (none, ee) }
    let sq2 = math.sqrt[f64](2.0f64)
    var crng = 0usize
    var i = 0usize
    while i < nc {
        var step = 0usize
        while step <= i {
            var j = i
            if step > 0usize { j = step - 1usize }
            // block of columns crng..crng+nc: Xw' diag(Xi Xj / n) Xw minus the identity terms
            var r = 0usize
            while r < nc {
                var c = 0usize
                while c < nc {
                    var s = 0.0f64
                    var t = 0usize
                    while t < n {
                        let wt = w.xw[t * nc + i] * w.xw[t * nc + j] / nf
                        s += wt * w.xw[t * nc + r] * w.xw[t * nc + c]
                        t += 1usize
                    }
                    var q = s
                    if i == j {
                        if r == c { q -= 1.0f64 }
                        if r == i && c == i { q -= 2.0f64 }
                        em[r * width + crng + c] = q
                    } else {
                        if r == i && c == j { q -= 1.0f64 }
                        if r == j && c == i { q -= 1.0f64 }
                        em[r * width + crng + c] = sq2 * q
                    }
                    c += 1usize
                }
                r += 1usize
            }
            crng += nc
            step += 1usize
        }
        i += 1usize
    }
    let npairs = nc * (nc - 1usize) / 2usize
    let (thetas, te) = mem.alloc[f64](a, npairs)
    if te != ok { ret (none, te) }
    i = 0usize
    while i < npairs {
        thetas[i] = 1.0f64
        i += 1usize
    }
    var iter = 0i64
    var vtol = 1.0f64
    while vtol > tol && iter < maxit {
        var pp = 0usize
        while pp + 1usize < nc {
            var qq = pp + 1usize
            while qq < nc {
                var g11 = 0.0f64
                var g22 = 0.0f64
                var g12 = 0.0f64
                var b = 0usize
                while b < ncstar {
                    let ip = pp + nc * b
                    let iq = qq + nc * b
                    let r1 = em[pp * width + ip] - em[qq * width + iq]
                    let r2 = em[pp * width + iq] + em[qq * width + ip]
                    g11 += r1 * r1
                    g22 += r2 * r2
                    g12 += r1 * r2
                    b += 1usize
                }
                let ton = g11 - g22
                let toff = g12 + g12
                let theta = 0.5f64 * math.atan2[f64](toff, ton + math.sqrt[f64](ton * ton + toff * toff))
                // 1-based index nc (p - 1) - p (p - 1) / 2 + q - p, written 0-based
                let p1 = pp + 1usize
                let q1 = qq + 1usize
                thetas[nc * (p1 - 1usize) - p1 * (p1 - 1usize) / 2usize + q1 - p1 - 1usize] = theta
                let cc = math.cos[f64](theta)
                let ss = math.sin[f64](theta)
                var r = 0usize
                while r < nc {
                    let rp = rmat[r * nc + pp]
                    let rq = rmat[r * nc + qq]
                    rmat[r * nc + pp] = rp * cc + rq * ss
                    rmat[r * nc + qq] = 0.0f64 - rp * ss + rq * cc
                    r += 1usize
                }
                var c = 0usize
                while c < width {
                    let ep = em[pp * width + c]
                    let eq = em[qq * width + c]
                    em[pp * width + c] = cc * ep + ss * eq
                    em[qq * width + c] = 0.0f64 - ss * ep + cc * eq
                    c += 1usize
                }
                b = 0usize
                while b < ncstar {
                    let ip = pp + nc * b
                    let iq = qq + nc * b
                    r = 0usize
                    while r < nc {
                        let cp = em[r * width + ip]
                        let cq = em[r * width + iq]
                        em[r * width + ip] = cc * cp + ss * cq
                        em[r * width + iq] = 0.0f64 - ss * cp + cc * cq
                        r += 1usize
                    }
                    b += 1usize
                }
                qq += 1usize
            }
            pp += 1usize
        }
        var mx = 0.0f64
        i = 0usize
        while i < npairs {
            if math.abs[f64](thetas[i]) > mx { mx = math.abs[f64](thetas[i]) }
            i += 1usize
        }
        vtol = mx
        iter += 1i64
    }
    let (fin, fe) = finish_ica(a, w, rmat, n, p, iter, vtol <= tol)
    ret (fin, fe)
}

fn sgn_of(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

// fun1d and fun2d of icaimax: fun 0 tanh, 1 log, 2 ext (with the column sign sg)
fn im_f1(fun: u8, x: f64, sg: f64) -> f64 {
    if fun == 1u8 { ret 2.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) - 1.0f64 }
    if fun == 2u8 { ret x + scale.tanh(x) * sg }
    ret scale.tanh(x)
}

fn im_f2(fun: u8, x: f64, sg: f64) -> f64 {
    if fun == 1u8 { ret 1.0f64 / (scale.cosh(x) + 1.0f64) }
    let th = scale.tanh(x)
    if fun == 2u8 { ret 1.0f64 + (1.0f64 - th * th) * sg }
    ret 1.0f64 - th * th
}

// icaimax(X, nc, maxit, tol, alg, fun, signs, signswitch, rate, rateanneal): infomax with the Newton (alg 0) or gradient (alg 1) update;
// ra0 and ra1 are rateanneal (ra0 <= 0 for none)
fn icaimax(a: *mem.Arena, x0: []const f64, n: usize, p: usize, nc: usize, maxit: i64, tol: f64, alg: u8, fun: u8, signs0: []const f64, signswitch: bool, rate0: f64, ra0: f64, ra1: f64) -> (Result, err) {
    var none: Result = zero
    let (w, we) = prewhiten(a, x0, n, p, nc)
    if we != ok { ret (none, we) }
    let (rmat, re) = identity(a, nc)
    if re != ok { ret (none, re) }
    let nf = f64(n)
    let (sg, sge) = mem.alloc[f64](a, nc)
    if sge != ok { ret (none, sge) }
    var j = 0usize
    while j < nc {
        sg[j] = signs0[j]
        j += 1usize
    }
    var sw = signswitch
    if fun != 2u8 { sw = false }
    var rate = rate0
    var iter = 0i64
    var vtol = 1.0f64
    while vtol > tol && iter < maxit {
        let mark = mem.mark(a)
        let (smat, se) = matmul(a, w.xw, rmat, n, nc, nc)
        if se != ok { ret (none, se) }
        if sw {
            j = 0usize
            while j < nc {
                var s = 0.0f64
                var t = 0usize
                while t < n {
                    let ch = scale.cosh(smat[t * nc + j])
                    s += 1.0f64 / (ch * ch) - scale.tanh(smat[t * nc + j]) * smat[t * nc + j]
                    t += 1usize
                }
                sg[j] = sgn_of(s / nf)
                j += 1usize
            }
        }
        let (f1, f1e) = mem.alloc[f64](a, n * nc)
        if f1e != ok { ret (none, f1e) }
        var t = 0usize
        while t < n {
            j = 0usize
            while j < nc {
                f1[t * nc + j] = im_f1(fun, smat[t * nc + j], sg[j])
                j += 1usize
            }
            t += 1usize
        }
        let (xwt, xwte) = transpose(a, w.xw, n, nc)
        if xwte != ok { ret (none, xwte) }
        let (gm, gme) = matmul(a, xwt, f1, nc, n, nc)
        if gme != ok { ret (none, gme) }
        let (rnew0, rne) = mem.alloc[f64](a, nc * nc)
        if rne != ok { ret (none, rne) }
        j = 0usize
        while j < nc {
            var h = 0.0f64
            if alg == 0u8 {
                t = 0usize
                while t < n {
                    h += im_f2(fun, smat[t * nc + j], sg[j])
                    t += 1usize
                }
                h = h / nf
            }
            var r = 0usize
            while r < nc {
                let g = gm[r * nc + j] / nf
                if alg == 0u8 {
                    rnew0[r * nc + j] = rmat[r * nc + j] - g / h
                } else {
                    rnew0[r * nc + j] = rmat[r * nc + j] - rate * g
                }
                r += 1usize
            }
            j += 1usize
        }
        let (pol, pe2) = polar(a, rnew0, nc)
        if pe2 != ok { ret (none, pe2) }
        var mn = 1.0e300f64
        j = 0usize
        while j < nc {
            var cs = 0.0f64
            var r = 0usize
            while r < nc {
                cs += rmat[r * nc + j] * pol[r * nc + j]
                r += 1usize
            }
            if math.abs[f64](cs) < mn { mn = math.abs[f64](cs) }
            j += 1usize
        }
        vtol = 1.0f64 - mn
        iter += 1i64
        var q = 0usize
        while q < nc * nc {
            rmat[q] = pol[q]
            q += 1usize
        }
        mem.reset(a, mark)
        if alg == 1u8 && ra0 > 0.0f64 {
            if math.acos[f64](1.0f64 - vtol) * 180.0f64 / 3.141592653589793f64 < ra0 { rate = rate * ra1 }
        }
    }
    let (fin, fe) = finish_ica(a, w, rmat, n, p, iter, vtol <= tol)
    ret (fin, fe)
}

// ---- icafast with either update scheme and for any shape of X

// the whitening of prewhiten for n < p: the eigenvectors of X X' / n (n by n) give Xw = V sqrt(n), Mprt = V' X / sqrt(n),
// Pmat = Mprt' diag(1 / values)
fn prewhiten_wide(a: *mem.Arena, x0: []const f64, n: usize, p: usize, nc: usize) -> (Whit, err) {
    var none: Whit = zero
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
    let (cc, ce) = matmul(a, x, xt, n, p, n)
    if ce != ok { ret (none, ce) }
    var i = 0usize
    while i < n * n {
        cc[i] = cc[i] / nf
        i += 1usize
    }
    let (vals, vecs, ee) = eigen_sym(a, cc, n)
    if ee != ok { ret (none, ee) }
    let (mprt, me) = mem.alloc[f64](a, nc * p)
    let (pmat, pe) = mem.alloc[f64](a, p * nc)
    let (xw, xwe) = mem.alloc[f64](a, n * nc)
    if me != ok { ret (none, me) }
    if pe != ok { ret (none, pe) }
    if xwe != ok { ret (none, xwe) }
    let sn = math.sqrt[f64](nf)
    var k = 0usize
    while k < nc {
        j = 0usize
        while j < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += vecs[i * n + k] * x[i * p + j]
                i += 1usize
            }
            mprt[k * p + j] = s / sn
            pmat[j * nc + k] = (s / sn) / vals[k]
            j += 1usize
        }
        i = 0usize
        while i < n {
            xw[i * nc + k] = vecs[i * n + k] * sn
            i += 1usize
        }
        k += 1usize
    }
    ret (Whit { x: x, mprt: mprt, pmat: pmat, xw: xw, nc: nc }, ok)
}

// icafast(X, nc, maxit, tol, alg = "par" or "def", fun, alpha) for n >= p or n < p; iters has one count per component for "def" and one
// for "par"
fn icafast_gen(a: *mem.Arena, x0: []const f64, n: usize, p: usize, nc: usize, maxit: i64, tol: f64, fun: u8, alpha: f64, deflate: bool) -> (Result, []i64, err) {
    var none: Result = zero
    var nonei: []i64 = zero
    var w: Whit = zero
    var we = ok
    if n >= p {
        let (w1, e1) = prewhiten(a, x0, n, p, nc)
        w = w1
        we = e1
    } else {
        let (w2, e2) = prewhiten_wide(a, x0, n, p, nc)
        w = w2
        we = e2
    }
    if we != ok { ret (none, nonei, we) }
    let (rmat, re) = identity(a, nc)
    if re != ok { ret (none, nonei, re) }
    let nf = f64(n)
    let (iters, ie) = mem.alloc[i64](a, nc)
    if ie != ok { ret (none, nonei, ie) }
    var vtol = 1.0f64
    var total = 0i64
    if deflate {
        let (sv, se) = mem.alloc[f64](a, n)
        let (rn, rne) = mem.alloc[f64](a, nc)
        if se != ok { ret (none, nonei, se) }
        if rne != ok { ret (none, nonei, rne) }
        var j = 0usize
        while j < nc {
            // normalise column j, then orthogonalise it against the earlier ones
            var nrm = 0.0f64
            var r = 0usize
            while r < nc {
                nrm += rmat[r * nc + j] * rmat[r * nc + j]
                r += 1usize
            }
            nrm = math.sqrt[f64](nrm)
            r = 0usize
            while r < nc {
                rmat[r * nc + j] = rmat[r * nc + j] / nrm
                r += 1usize
            }
            if j >= 1usize {
                var acc = 0.0f64
                r = 0usize
                while r < nc {
                    rn[r] = 0.0f64
                    r += 1usize
                }
                var k = 0usize
                while k < j {
                    var d = 0.0f64
                    r = 0usize
                    while r < nc {
                        d += rmat[r * nc + k] * rmat[r * nc + j]
                        r += 1usize
                    }
                    r = 0usize
                    while r < nc {
                        rn[r] += d * rmat[r * nc + k]
                        r += 1usize
                    }
                    k += 1usize
                }
                r = 0usize
                while r < nc {
                    rmat[r * nc + j] = rmat[r * nc + j] - rn[r]
                    acc += rmat[r * nc + j] * rmat[r * nc + j]
                    r += 1usize
                }
                acc = math.sqrt[f64](acc)
                r = 0usize
                while r < nc {
                    rmat[r * nc + j] = rmat[r * nc + j] / acc
                    r += 1usize
                }
            }
            var iter = 0i64
            vtol = 1.0f64
            while vtol > tol && iter < maxit {
                var t = 0usize
                while t < n {
                    var s = 0.0f64
                    r = 0usize
                    while r < nc {
                        s += w.xw[t * nc + r] * rmat[r * nc + j]
                        r += 1usize
                    }
                    sv[t] = s
                    t += 1usize
                }
                // rnew = colMeans(Xw * f1(svec)) - mean(f2(svec)) R[, j]
                var m2 = 0.0f64
                t = 0usize
                while t < n {
                    m2 += fun2(fun, sv[t], alpha)
                    t += 1usize
                }
                m2 = m2 / nf
                r = 0usize
                while r < nc {
                    var s = 0.0f64
                    t = 0usize
                    while t < n {
                        s += w.xw[t * nc + r] * fun1(fun, sv[t], alpha)
                        t += 1usize
                    }
                    rn[r] = s / nf - m2 * rmat[r * nc + j]
                    r += 1usize
                }
                var q = 0.0f64
                r = 0usize
                while r < nc {
                    q += rn[r] * rn[r]
                    r += 1usize
                }
                q = math.sqrt[f64](q)
                r = 0usize
                while r < nc {
                    rn[r] = rn[r] / q
                    r += 1usize
                }
                if j >= 1usize {
                    // remove the components along the earlier columns, then renormalise
                    var k = 0usize
                    var proj0 = 0.0f64
                    let (pv, pve) = mem.alloc[f64](a, nc)
                    if pve != ok { ret (none, nonei, pve) }
                    r = 0usize
                    while r < nc {
                        pv[r] = 0.0f64
                        r += 1usize
                    }
                    while k < j {
                        var d = 0.0f64
                        r = 0usize
                        while r < nc {
                            d += rmat[r * nc + k] * rn[r]
                            r += 1usize
                        }
                        r = 0usize
                        while r < nc {
                            pv[r] += d * rmat[r * nc + k]
                            r += 1usize
                        }
                        k += 1usize
                    }
                    r = 0usize
                    while r < nc {
                        rn[r] = rn[r] - pv[r]
                        proj0 += rn[r] * rn[r]
                        r += 1usize
                    }
                    proj0 = math.sqrt[f64](proj0)
                    r = 0usize
                    while r < nc {
                        rn[r] = rn[r] / proj0
                        r += 1usize
                    }
                }
                var dot = 0.0f64
                r = 0usize
                while r < nc {
                    dot += rmat[r * nc + j] * rn[r]
                    r += 1usize
                }
                vtol = 1.0f64 - math.abs[f64](dot)
                iter += 1i64
                r = 0usize
                while r < nc {
                    rmat[r * nc + j] = rn[r]
                    r += 1usize
                }
            }
            iters[j] = iter
            total += iter
            j += 1usize
        }
    } else {
        var iter = 0i64
        var j = 0usize
        while vtol > tol && iter < maxit {
            let mark = mem.mark(a)
            let (smat, se) = matmul(a, w.xw, rmat, n, nc, nc)
            if se != ok { ret (none, nonei, se) }
            let (g, ge) = mem.alloc[f64](a, n * nc)
            if ge != ok { ret (none, nonei, ge) }
            var i = 0usize
            while i < n * nc {
                g[i] = fun1(fun, smat[i], alpha)
                i += 1usize
            }
            let (xwt, xwte) = transpose(a, w.xw, n, nc)
            if xwte != ok { ret (none, nonei, xwte) }
            let (rn, rne) = matmul(a, xwt, g, nc, n, nc)
            if rne != ok { ret (none, nonei, rne) }
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
            if pe2 != ok { ret (none, nonei, pe2) }
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
            i = 0usize
            while i < nc * nc {
                rmat[i] = pol[i]
                i += 1usize
            }
            mem.reset(a, mark)
        }
        iters[0usize] = iter
        total = iter
    }
    let (fin, fe) = finish_ica(a, w, rmat, n, p, total, vtol <= tol)
    ret (fin, iters, fe)
}
