// A matrix-free Krylov-Schur iteration (the thick-restart form of the implicitly restarted Lanczos and Arnoldi iterations of ARPACK's dsaupd and dnaupd, which RSpectra wraps):
// the operator f(ctx, x, y) writes A x into y; V holds an orthonormal Krylov basis built with Gram-Schmidt (twice), H the projected matrix, and after each pass of ncv steps the wanted Ritz
// subspace is kept (an orthonormal basis of the real span of the wanted Ritz vectors, so a complex pair stays together) and the iteration resumes from the residual vector.
// Symmetric problems solve the projected matrix with the Jacobi eigensolver, general ones with dc.eigen. Not ARPACK's shifts: the converged pairs are the same, the path to them is not.

use e.algo.linalg.decomp as dc
use e.algo.linalg.matrix as mx
use e.math
use e.mem

error NoConv
error BadArg

fn ks_dot(x: []const f64, y: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i] * y[i]
        i += 1usize
    }
    ret s
}

fn ks_alloc(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (p, e) = mem.alloc[f64](a, n)
    if e != ok { ret (p, e) }
    var i = 0usize
    while i < n {
        p[i] = 0.0f64
        i += 1usize
    }
    ret (p, ok)
}

// the columns from..ncv of vb (n by ncv + 1, column-major) by Arnoldi steps; the coefficients go to h ((ncv + 1) by ncv, row-major). A breakdown continues with a fixed vector orthogonal to the basis (the subdiagonal stays zero)
fn ks_expand[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), n: usize, vb: []f64, h: []f64, ncv: usize, from: usize) {
    var j = from
    while j < ncv {
        let w = vb[(j + 1usize) * n..(j + 2usize) * n]
        f(ctx, vb[j * n..(j + 1usize) * n], w)
        let before = math.sqrt[f64](ks_dot(w, w, n))
        var i = 0usize
        while i <= j {
            h[i * ncv + j] = 0.0f64
            i += 1usize
        }
        var pass = 0usize
        while pass < 2usize {
            i = 0usize
            while i <= j {
                let vi = vb[i * n..(i + 1usize) * n]
                let d = ks_dot(vi, w, n)
                var r = 0usize
                while r < n {
                    w[r] = w[r] - d * vi[r]
                    r += 1usize
                }
                h[i * ncv + j] += d
                i += 1usize
            }
            pass += 1usize
        }
        var beta = math.sqrt[f64](ks_dot(w, w, n))
        if beta <= 1.0e-13f64 * before || beta == 0.0f64 {
            h[(j + 1usize) * ncv + j] = 0.0f64
            var tries = 0usize
            while tries < 3usize {
                var r = 0usize
                while r < n {
                    w[r] = math.sin[f64](f64(r + 1usize) * (1.0f64 + 0.7548776662f64 * f64(j + 1usize + 5usize * tries)))
                    r += 1usize
                }
                pass = 0usize
                while pass < 2usize {
                    i = 0usize
                    while i <= j {
                        let vi = vb[i * n..(i + 1usize) * n]
                        let d = ks_dot(vi, w, n)
                        r = 0usize
                        while r < n {
                            w[r] = w[r] - d * vi[r]
                            r += 1usize
                        }
                        i += 1usize
                    }
                    pass += 1usize
                }
                beta = math.sqrt[f64](ks_dot(w, w, n))
                if beta > 1.0e-8f64 { break }
                tries += 1usize
            }
            var r2 = 0usize
            while r2 < n {
                w[r2] = w[r2] / beta
                r2 += 1usize
            }
        } else {
            h[(j + 1usize) * ncv + j] = beta
            var r = 0usize
            while r < n {
                w[r] = w[r] / beta
                r += 1usize
            }
        }
        j += 1usize
    }
}

// the Ritz values listed best first: which 0 LM (largest modulus), 1 LR (largest real part), 2 SR, 3 LI (largest |imaginary part|), 4 SI, 5 BE (alternately the largest and smallest real part, largest first), 6 SM (smallest modulus)
fn ks_order(rv: []const f64, iv: []const f64, m: usize, which: usize, ord: []usize, key: []f64, tmp: []usize) {
    var i = 0usize
    while i < m {
        ord[i] = i
        let r = rv[i]
        let q = iv[i]
        if which == 0usize { key[i] = math.sqrt[f64](r * r + q * q) }
        if which == 1usize || which == 5usize { key[i] = r }
        if which == 2usize { key[i] = 0.0f64 - r }
        if which == 3usize { key[i] = math.abs[f64](q) }
        if which == 4usize { key[i] = 0.0f64 - math.abs[f64](q) }
        if which == 6usize { key[i] = 0.0f64 - math.sqrt[f64](r * r + q * q) }
        i += 1usize
    }
    i = 1usize
    while i < m {
        let t = ord[i]
        var j = i
        while j > 0usize && (key[ord[j - 1usize]] < key[t] - 1.0e-12f64 * (1.0f64 + math.abs[f64](key[t])) || (math.abs[f64](key[ord[j - 1usize]] - key[t]) <= 1.0e-12f64 * (1.0f64 + math.abs[f64](key[t])) && iv[ord[j - 1usize]] < iv[t])) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = t
        i += 1usize
    }
    if which == 5usize {
        var lo = 0usize
        var hi = m - 1usize
        var c = 0usize
        while c < m {
            if c % 2usize == 0usize {
                tmp[c] = ord[lo]
                lo += 1usize
            } else {
                tmp[c] = ord[hi]
                hi -= 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < m {
            ord[c] = tmp[c]
            c += 1usize
        }
    }
}

// a count cut through a conjugate pair takes the pair whole
fn ks_close(rv: []const f64, iv: []const f64, ord: []const usize, cnt: usize, m: usize) -> usize {
    if cnt > 0usize && cnt < m {
        let p = ord[cnt - 1usize]
        let q = ord[cnt]
        if iv[p] > 0.0f64 && iv[q] < 0.0f64 && math.abs[f64](rv[p] - rv[q]) <= 1.0e-12f64 * (1.0f64 + math.abs[f64](rv[p])) { ret cnt + 1usize }
    }
    ret cnt
}

// the k wanted eigenpairs of the operator f (n by n; sym says it is symmetric): which as ks_order (5, BE, symmetric only), ncv the Krylov dimension (clamped to k + 2 ..= n), tol the relative Ritz residual
// (ARPACK's test), maxit the number of restarts, v0 the start vector (n numbers, not all zero). The values go to ore/oim best first (the first k of the wanted order) and the unit-norm vectors to vre/vim (n by k, row-major);
// the answer is the number of passes, NoConv if the tolerance was not reached (the outputs still hold the last Ritz estimates)
fn krylov[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), n: usize, k: usize, which: usize, sym: bool, ncv0: usize, tol: f64, maxit: usize, v0: []const f64, ore: []f64, oim: []f64, vre: []f64, vim: []f64) -> (usize, err) {
    if k == 0usize || k + 1usize > n || v0.len < n { ret (0usize, BadArg) }
    var ncv = ncv0
    if ncv < k + 2usize { ncv = k + 2usize }
    if ncv > n { ncv = n }
    let (vb, e0) = ks_alloc(a, n * (ncv + 1usize))
    let (hh, e1) = ks_alloc(a, (ncv + 1usize) * ncv)
    let (hm, e2) = ks_alloc(a, ncv * ncv)
    let (rv, e3) = ks_alloc(a, ncv)
    let (iv, e4) = ks_alloc(a, ncv)
    let (yr, e5) = ks_alloc(a, ncv * ncv)
    let (yi, e6) = ks_alloc(a, ncv * ncv)
    let (yt, e7) = ks_alloc(a, ncv * ncv)
    let (key, e8) = ks_alloc(a, ncv)
    let (yy, e9) = ks_alloc(a, ncv * ncv)
    let (hy, e10) = ks_alloc(a, ncv * ncv)
    let (bb, e11) = ks_alloc(a, ncv * ncv)
    let (tv, e12) = ks_alloc(a, n * ncv)
    let (ord, e13) = mem.alloc[usize](a, ncv)
    let (otmp, e14b) = mem.alloc[usize](a, ncv)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14b != ok { ret (0usize, mem.Full) }
    var s0 = 0.0f64
    var i = 0usize
    while i < n {
        vb[i] = v0[i]
        s0 += v0[i] * v0[i]
        i += 1usize
    }
    s0 = math.sqrt[f64](s0)
    if s0 == 0.0f64 { ret (0usize, BadArg) }
    i = 0usize
    while i < n {
        vb[i] = vb[i] / s0
        i += 1usize
    }
    let eps23 = math.pow[f64](2.220446049250313e-16f64, 2.0f64 / 3.0f64)
    let m = ncv
    var l = 0usize
    var it = 0usize
    var done = false
    var fail = false
    while !done {
        it += 1usize
        ks_expand[Ctx](ctx, f, n, vb, hh, ncv, l)
        let beta = hh[ncv * ncv + (ncv - 1usize)]
        let mk = mem.mark(a)
        if sym {
            var r = 0usize
            while r < m {
                var c = 0usize
                while c < m {
                    hm[r * m + c] = 0.5f64 * (hh[r * ncv + c] + hh[c * ncv + r])
                    c += 1usize
                }
                r += 1usize
            }
            let (vm, e14) = mx.view[f64](yt, m, m, m)
            let (src, e15) = mx.view_const[f64](hm, m, m, m)
            if e14 != ok || e15 != ok { ret (it, mx.Shape) }
            let er = mx.eigen(a, rv, vm, src, 1.0e-15f64, 200u32)
            if er != ok { ret (it, er) }
            var p = 0usize
            while p < m {
                iv[p] = 0.0f64
                r = 0usize
                while r < m {
                    yr[p * m + r] = yt[r * m + p]
                    yi[p * m + r] = 0.0f64
                    r += 1usize
                }
                p += 1usize
            }
        } else {
            var r = 0usize
            while r < m {
                var c = 0usize
                while c < m {
                    hm[c * m + r] = hh[r * ncv + c]
                    c += 1usize
                }
                r += 1usize
            }
            let (eg, eg_err) = dc.eigen(a, hm, m)
            if eg_err != ok { ret (it, eg_err) }
            var p = 0usize
            while p < m {
                rv[p] = eg.re[p]
                iv[p] = eg.im[p]
                var nn = 0.0f64
                r = 0usize
                while r < m {
                    yr[p * m + r] = eg.vre[p * m + r]
                    yi[p * m + r] = eg.vim[p * m + r]
                    nn += yr[p * m + r] * yr[p * m + r] + yi[p * m + r] * yi[p * m + r]
                    r += 1usize
                }
                nn = math.sqrt[f64](nn)
                r = 0usize
                while r < m {
                    yr[p * m + r] = yr[p * m + r] / nn
                    yi[p * m + r] = yi[p * m + r] / nn
                    r += 1usize
                }
                // the complex Schur form leaves a real eigenvalue with a rounding-sized imaginary part: make it real, with a real vector
                if math.abs[f64](iv[p]) <= 1.0e-10f64 * (1.0f64 + math.abs[f64](rv[p])) {
                    iv[p] = 0.0f64
                    var big = 0.0f64
                    var cr = 1.0f64
                    var ci = 0.0f64
                    r = 0usize
                    while r < m {
                        let md = math.sqrt[f64](yr[p * m + r] * yr[p * m + r] + yi[p * m + r] * yi[p * m + r])
                        if md > big {
                            big = md
                            cr = yr[p * m + r] / md
                            ci = 0.0f64 - yi[p * m + r] / md
                        }
                        r += 1usize
                    }
                    var n2 = 0.0f64
                    r = 0usize
                    while r < m {
                        let xr = yr[p * m + r] * cr - yi[p * m + r] * ci
                        yr[p * m + r] = xr
                        yi[p * m + r] = 0.0f64
                        n2 += xr * xr
                        r += 1usize
                    }
                    n2 = math.sqrt[f64](n2)
                    r = 0usize
                    while r < m {
                        yr[p * m + r] = yr[p * m + r] / n2
                        r += 1usize
                    }
                }
                p += 1usize
            }
        }
        mem.reset(a, mk)
        ks_order(rv, iv, m, which, ord, key, otmp)
        var nsel = k
        if !sym { nsel = ks_close(rv, iv, ord, k, m) }
        var anorm = 0.0f64
        i = 0usize
        while i < m {
            let q = math.sqrt[f64](rv[i] * rv[i] + iv[i] * iv[i])
            if q > anorm { anorm = q }
            i += 1usize
        }
        var conv = true
        var c = 0usize
        while c < nsel {
            let p = ord[c]
            let yl = math.sqrt[f64](yr[p * m + m - 1usize] * yr[p * m + m - 1usize] + yi[p * m + m - 1usize] * yi[p * m + m - 1usize])
            let th = math.sqrt[f64](rv[p] * rv[p] + iv[p] * iv[p])
            var thr = tol * math.max[f64](eps23, th)
            thr = math.max[f64](thr, 8.0f64 * 2.220446049250313e-16f64 * anorm)
            if math.abs[f64](beta) * yl > thr { conv = false }
            c += 1usize
        }
        if conv || it >= maxit {
            done = true
            if !conv { fail = true }
            c = 0usize
            while c < k {
                let p = ord[c]
                ore[c] = rv[p]
                oim[c] = iv[p]
                var nn = 0.0f64
                i = 0usize
                while i < n {
                    var sr = 0.0f64
                    var si = 0.0f64
                    var r = 0usize
                    while r < m {
                        sr += vb[r * n + i] * yr[p * m + r]
                        si += vb[r * n + i] * yi[p * m + r]
                        r += 1usize
                    }
                    vre[i * k + c] = sr
                    vim[i * k + c] = si
                    nn += sr * sr + si * si
                    i += 1usize
                }
                nn = math.sqrt[f64](nn)
                i = 0usize
                while i < n {
                    vre[i * k + c] = vre[i * k + c] / nn
                    vim[i * k + c] = vim[i * k + c] / nn
                    i += 1usize
                }
                c += 1usize
            }
        } else {
            var lw = nsel + (ncv - nsel) / 2usize
            if lw > ncv - 1usize { lw = ncv - 1usize }
            let lc = ks_close(rv, iv, ord, lw, m)
            if lc > ncv - 1usize { lw = lw - 1usize } else { lw = lc }
            // Y: orthonormal real basis of the wanted Ritz vectors (a pair gives its real and imaginary parts)
            var col = 0usize
            c = 0usize
            while c < lw {
                let p = ord[c]
                if iv[p] == 0.0f64 {
                    var r = 0usize
                    while r < m {
                        yy[r * lw + col] = yr[p * m + r]
                        r += 1usize
                    }
                    col += 1usize
                } else {
                    if iv[p] > 0.0f64 {
                        var r = 0usize
                        while r < m {
                            yy[r * lw + col] = yr[p * m + r]
                            yy[r * lw + col + 1usize] = yi[p * m + r]
                            r += 1usize
                        }
                        col += 2usize
                    }
                }
                c += 1usize
            }
            lw = col
            var pass = 0usize
            while pass < 2usize {
                var j = 0usize
                while j < lw {
                    var q = 0usize
                    while q < j {
                        var d = 0.0f64
                        var r = 0usize
                        while r < m {
                            d += yy[r * lw + q] * yy[r * lw + j]
                            r += 1usize
                        }
                        r = 0usize
                        while r < m {
                            yy[r * lw + j] = yy[r * lw + j] - d * yy[r * lw + q]
                            r += 1usize
                        }
                        q += 1usize
                    }
                    var nn = 0.0f64
                    var r2 = 0usize
                    while r2 < m {
                        nn += yy[r2 * lw + j] * yy[r2 * lw + j]
                        r2 += 1usize
                    }
                    nn = math.sqrt[f64](nn)
                    if nn > 0.0f64 {
                        r2 = 0usize
                        while r2 < m {
                            yy[r2 * lw + j] = yy[r2 * lw + j] / nn
                            r2 += 1usize
                        }
                    }
                    j += 1usize
                }
                pass += 1usize
            }
            // B = Y' H Y with H the m by m block of hh
            var r = 0usize
            while r < m {
                var j = 0usize
                while j < lw {
                    var s = 0.0f64
                    var q = 0usize
                    while q < m {
                        s += hh[r * ncv + q] * yy[q * lw + j]
                        q += 1usize
                    }
                    hy[r * lw + j] = s
                    j += 1usize
                }
                r += 1usize
            }
            r = 0usize
            while r < lw {
                var j = 0usize
                while j < lw {
                    var s = 0.0f64
                    var q = 0usize
                    while q < m {
                        s += yy[q * lw + r] * hy[q * lw + j]
                        q += 1usize
                    }
                    bb[r * lw + j] = s
                    j += 1usize
                }
                r += 1usize
            }
            // V = V Y, the residual vector becomes column lw
            var j = 0usize
            while j < lw {
                i = 0usize
                while i < n {
                    var s = 0.0f64
                    var q = 0usize
                    while q < m {
                        s += vb[q * n + i] * yy[q * lw + j]
                        q += 1usize
                    }
                    tv[j * n + i] = s
                    i += 1usize
                }
                j += 1usize
            }
            i = 0usize
            while i < n {
                vb[lw * n + i] = vb[m * n + i]
                i += 1usize
            }
            j = 0usize
            while j < lw {
                i = 0usize
                while i < n {
                    vb[j * n + i] = tv[j * n + i]
                    i += 1usize
                }
                j += 1usize
            }
            var z = 0usize
            while z < (ncv + 1usize) * ncv {
                hh[z] = 0.0f64
                z += 1usize
            }
            r = 0usize
            while r < lw {
                var q = 0usize
                while q < lw {
                    hh[r * ncv + q] = bb[r * lw + q]
                    q += 1usize
                }
                hh[lw * ncv + r] = beta * yy[(m - 1usize) * lw + r]
                r += 1usize
            }
            l = lw
        }
    }
    if fail { ret (it, NoConv) }
    ret (it, ok)
}
