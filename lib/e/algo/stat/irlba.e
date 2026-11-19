// irlba (the R package): irlba, the augmented implicitly restarted Lanczos bidiagonalization, ported from the package's R code statement for statement
// (restarts, the convergence test, the smallest-values harmonic restart, the invariant-subspace repairs), with R's rnorm start under rr.seed and the sign-exact
// LAPACK dgesdd of R's svd for the small bidiagonal problems; svdr (power iteration with qr.Q), partial_eigen, prcomp_irlba and ssvd on top of it.
// Matrices are column-major, as R stores them. Not ported: the deflation (list) form of the v argument, complex matrices, the tiny-problem path with a scale.

use e.algo.linalg.lapack_gesdd as gs
use e.algo.rand.r as rr
use e.math
use e.mem

error BadArg
error NearNull

type Opts = struct {
    nv: usize, nu: usize, maxit: usize, work: usize, reorth: bool, tol: f64, svtol: f64, right_only: bool, smallest: bool, maxritz: usize,
    center: []f64, scale: []f64, has_shift: bool, shift: f64, v: []f64
}

// a result: d (k values), u (ur by nu), v (vr by nv), column-major; u and v are empty with right_only
type Fit = struct { d: []f64, u: []f64, v: []f64, ur: usize, vr: usize, nu: usize, nv: usize, iter: usize, mprod: usize, converged: bool }

// irlba(A, nv) defaults
fn default_opts(nv: usize) -> Opts {
    var o: Opts = zero
    o.nv = nv
    o.nu = nv
    o.maxit = 1000usize
    o.work = nv + 16usize
    o.reorth = true
    o.tol = 1.0e-7f64
    o.svtol = 1.0e-7f64
    o.maxritz = 3usize
    ret o
}

fn zalloc(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (p, e) = mem.alloc[f64](a, n)
    if e != ok { ret (p, e) }
    var i = 0usize
    while i < n {
        p[i] = 0.0f64
        i += 1usize
    }
    ret (p, ok)
}

fn dotp(x: []const f64, y: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i] * y[i]
        i += 1usize
    }
    ret s
}

// R's colMeans/mean of x[0..n]: the long-double sum divided in long double, here the two-sum accumulation divided by a corrected quotient
fn mean_ld(x: []const f64, n: usize) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < n {
        let t = hi + x[i]
        let bb = t - hi
        lo += (hi - (t - bb)) + (x[i] - bb)
        hi = t
        i += 1usize
    }
    let dn = f64(n)
    let q = hi / dn
    // the exact product q * dn by Dekker's split
    let c = 134217729.0f64
    let qs = c * q
    let qh = qs - (qs - q)
    let ql = q - qh
    let ds = c * dn
    let dh = ds - (ds - dn)
    let dl = dn - dh
    let ph = q * dn
    let pl = ((qh * dh - ph) + qh * dl + ql * dh) + ql * dl
    let rem = ((hi - ph) - pl) + lo
    ret q + rem / dn
}

// R's sum(): long-double accumulation, here by error-free two-sum accumulation (hi + lo)
fn sum_ld(x: []const f64, n: usize) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < n {
        let t = hi + x[i]
        let bb = t - hi
        let err1 = (hi - (t - bb)) + (x[i] - bb)
        hi = t
        lo += err1
        i += 1usize
    }
    ret hi + lo
}

fn norm2(x: []const f64, n: usize) -> f64 { ret math.sqrt[f64](math.abs[f64](dotp(x, x, n))) }

// out = x v (x is pm by pn), or x' v with tr
fn gemv(x: []const f64, pm: usize, pn: usize, tr: bool, v: []const f64, out: []f64) {
    if !tr {
        var i = 0usize
        while i < pm {
            out[i] = 0.0f64
            i += 1usize
        }
        var j = 0usize
        while j < pn {
            let c = v[j]
            i = 0usize
            while i < pm {
                out[i] += x[j * pm + i] * c
                i += 1usize
            }
            j += 1usize
        }
    } else {
        var j = 0usize
        while j < pn {
            var s = 0.0f64
            var i = 0usize
            while i < pm {
                s += x[j * pm + i] * v[i]
                i += 1usize
            }
            out[j] = s
            j += 1usize
        }
    }
}

// c (r by cc) = a (r by kk) b (kk by cc), column-major, c apart from a and b
fn mmul(a: []const f64, b: []const f64, r: usize, kk: usize, cc: usize, c: []f64) {
    var j = 0usize
    while j < cc {
        var i = 0usize
        while i < r {
            c[j * r + i] = 0.0f64
            i += 1usize
        }
        var l = 0usize
        while l < kk {
            let t = b[j * kk + l]
            i = 0usize
            while i < r {
                c[j * r + i] += a[l * r + i] * t
                i += 1usize
            }
            l += 1usize
        }
        j += 1usize
    }
}

// irlba:::orthog(y, X): y - X (X' y) for the r by c matrix X; tmp has length r
fn orthog(y: []f64, xm: []const f64, r: usize, c: usize, tmp: []f64) {
    var i = 0usize
    while i < r {
        tmp[i] = 0.0f64
        i += 1usize
    }
    var l = 0usize
    while l < c {
        let dd = dotp(xm[l * r..(l + 1usize) * r], y, r)
        i = 0usize
        while i < r {
            tmp[i] += xm[l * r + i] * dd
            i += 1usize
        }
        l += 1usize
    }
    i = 0usize
    while i < r {
        y[i] = y[i] - tmp[i]
        i += 1usize
    }
}

// R's qr (LINPACK dqrdc2, no pivoting needed for full-rank input) then qr.Q and qr.R: q is r by c, rm is c by c (upper triangle), x is r by c with r >= c
fn qr_thin(a: *mem.Arena, x: []const f64, r: usize, c: usize, q: []f64, rm: []f64) -> err {
    let (w, e1) = zalloc(a, r * c)
    let (qa, e2) = zalloc(a, c)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < r * c {
        w[i] = x[i]
        i += 1usize
    }
    var l = 0usize
    while l < c {
        if l + 1usize < r {
            var nrm = norm2(w[l * r + l..(l + 1usize) * r], r - l)
            if nrm != 0.0f64 {
                if w[l * r + l] != 0.0f64 {
                    if w[l * r + l] < 0.0f64 { nrm = 0.0f64 - nrm }
                }
                i = l
                while i < r {
                    w[l * r + i] = w[l * r + i] * (1.0f64 / nrm)
                    i += 1usize
                }
                w[l * r + l] = w[l * r + l] + 1.0f64
                var jj = l + 1usize
                while jj < c {
                    let t = (0.0f64 - dotp(w[l * r + l..(l + 1usize) * r], w[jj * r + l..(jj + 1usize) * r], r - l)) / w[l * r + l]
                    i = l
                    while i < r {
                        w[jj * r + i] += t * w[l * r + i]
                        i += 1usize
                    }
                    jj += 1usize
                }
                qa[l] = w[l * r + l]
                w[l * r + l] = 0.0f64 - nrm
            }
        }
        l += 1usize
    }
    var jc = 0usize
    while jc < c {
        i = 0usize
        while i < c {
            rm[jc * c + i] = 0.0f64
            if i <= jc { rm[jc * c + i] = w[jc * r + i] }
            i += 1usize
        }
        jc += 1usize
    }
    i = 0usize
    while i < r * c {
        q[i] = 0.0f64
        i += 1usize
    }
    jc = 0usize
    while jc < c {
        q[jc * r + jc] = 1.0f64
        jc += 1usize
    }
    l = c
    while l > 0usize {
        l -= 1usize
        if qa[l] != 0.0f64 {
            jc = 0usize
            while jc < c {
                var s = qa[l] * q[jc * r + l]
                i = l + 1usize
                while i < r {
                    s += w[l * r + i] * q[jc * r + i]
                    i += 1usize
                }
                let t = (0.0f64 - s) / qa[l]
                q[jc * r + l] += t * qa[l]
                i = l + 1usize
                while i < r {
                    q[jc * r + i] += t * w[l * r + i]
                    i += 1usize
                }
                jc += 1usize
            }
        }
    }
    ret ok
}

// svd(b) for the nr by nc column-major b through R's dgesdd: s (min), u (nr by min), v (nc by min, column-major; the transpose of vt)
fn svd_cols(a: *mem.Arena, b: []const f64, nr: usize, nc: usize, s: []f64, u: []f64, v: []f64) -> err {
    var kk = nr
    if nc < nr { kk = nc }
    let (vt, e1) = zalloc(a, kk * nc)
    if e1 != ok { ret e1 }
    let mk = mem.mark(a)
    let es = gs.svd_all(a, b, nr, nc, s, u, vt)
    mem.reset(a, mk)
    if es != ok { ret es }
    var l = 0usize
    while l < kk {
        var i = 0usize
        while i < nc {
            v[l * nc + i] = vt[i * kk + l]
            i += 1usize
        }
        l += 1usize
    }
    ret ok
}

fn irlba(a: *mem.Arena, g: *rr.Rng, x: []const f64, m0: usize, n0: usize, o: Opts, res: *Fit) -> err {
    var m = m0
    var n = n0
    var ichg = false
    let eps = 2.220446049250313e-16f64
    var nu = o.nu
    let nv = o.nv
    var k = nu
    if nv > k { k = nv }
    var mn = m
    if n < mn { mn = n }
    if k == 0usize || k + 1usize > mn { ret BadArg }
    var work = o.work
    if work <= 1usize || o.maxit == 0usize || o.tol < 0.0f64 { ret BadArg }
    if work <= k && !o.right_only { work = k + 1usize }
    if work >= mn {
        work = 1usize
        if mn > 3usize { work = mn - 2usize }
        if work <= k { work = k + 1usize }
    }
    let k_org = k
    let hasc = o.center.len > 0usize
    let hass = o.scale.len > 0usize
    if n > m && o.smallest {
        if o.right_only { ret BadArg }
        ichg = true
        let t = m
        m = n
        n = t
    }
    let eps2 = math.pow[f64](eps, 0.8f64)
    // logical dims: A_l is m by n; physical x is m0 by n0
    if mn < 6usize {
        if hass { ret BadArg }
        let (aa, e0) = zalloc(a, m0 * n0)
        if e0 != ok { ret e0 }
        var i = 0usize
        while i < m0 * n0 {
            aa[i] = x[i]
            i += 1usize
        }
        if o.has_shift {
            i = 0usize
            while i < m0 && i < n0 {
                aa[i * m0 + i] += o.shift
                i += 1usize
            }
        }
        if hasc {
            var j = 0usize
            while j < n0 {
                i = 0usize
                while i < m0 {
                    aa[j * m0 + i] = aa[j * m0 + i] - o.center[j]
                    i += 1usize
                }
                j += 1usize
            }
        }
        var kk = m0
        if n0 < kk { kk = n0 }
        let (s0, e1) = zalloc(a, kk)
        let (u0, e2) = zalloc(a, m0 * kk)
        let (v0, e3) = zalloc(a, n0 * kk)
        if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
        let es = svd_cols(a, aa, m0, n0, s0, u0, v0)
        if es != ok { ret es }
        let (d, e4) = zalloc(a, k)
        let (uo, e5) = zalloc(a, m0 * nu)
        let (vo, e6) = zalloc(a, n0 * nv)
        if e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
        var first = 0usize
        if o.smallest { first = kk - k }
        i = 0usize
        while i < k {
            d[i] = s0[first + i]
            i += 1usize
        }
        var c = 0usize
        while c < nu {
            i = 0usize
            while i < m0 {
                uo[c * m0 + i] = u0[(first + c) * m0 + i]
                i += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < nv {
            i = 0usize
            while i < n0 {
                vo[c * n0 + i] = v0[(first + c) * n0 + i]
                i += 1usize
            }
            c += 1usize
        }
        res.d = d
        res.u = uo
        res.v = vo
        res.ur = m0
        res.vr = n0
        res.nu = nu
        res.nv = nv
        res.iter = 0usize
        res.mprod = 0usize
        res.converged = true
        ret ok
    }
    let wcap = mn
    var wdim = work
    if o.right_only { wdim = 1usize }
    let wide = !o.right_only
    var wcols = wcap
    if !wide { wcols = 1usize }
    let (vm, e10) = zalloc(a, n * wcap)
    let (wm, e11) = zalloc(a, m * wcols)
    let (fv, e12) = zalloc(a, n)
    let (tmpn, e13) = zalloc(a, n)
    let (tmpm, e14) = zalloc(a, m)
    let (tmp2, e15) = zalloc(a, n + m)
    let bs = wcap + 1usize
    let (bm, e16) = zalloc(a, bs * bs)
    let (bq, e17) = zalloc(a, wcap * wcap)
    let (bsv, e18) = zalloc(a, wcap)
    let (bu, e19) = zalloc(a, wcap * wcap)
    let (bv, e20) = zalloc(a, wcap * wcap)
    let (lastsv, e21) = zalloc(a, wcap)
    let (rrow, e22) = zalloc(a, wcap + 1usize)
    let (tb, e23) = zalloc(a, wcap * wcap + n * wcap + m * wcap)
    if e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok { ret mem.Full }
    // wdim is only used as a flag below; the matrices have wcap columns
    var i = 0usize
    if o.v.len > 0usize {
        i = 0usize
        while i < o.v.len && i < n * work {
            vm[i] = o.v[i]
            i += 1usize
        }
    } else {
        i = 0usize
        while i < n {
            vm[i] = rr.rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
    }
    var reorth = o.reorth
    var nrb = 0usize
    var ncb = 0usize
    let eps23 = math.pow[f64](eps, 2.0f64 / 3.0f64)
    let sqrteps = math.sqrt[f64](eps)
    var iter = 1usize
    var mprod = 0usize
    var smax = 1.0f64
    var smin = 0.0f64
    var s = 0.0f64
    var maxritz = o.maxritz
    var clustered = 0usize
    var converged = false
    var bsz = 0usize
    var rf = 0.0f64
    var have_last = false
    var bfail = false
    while iter <= o.maxit {
        var j = 1usize
        if iter == 1usize {
            let nn = norm2(vm[0usize..n], n)
            i = 0usize
            while i < n {
                vm[i] = vm[i] / nn
                i += 1usize
            }
        } else {
            j = k + 1usize
        }
        var jw = 1usize
        if wide { jw = j }
        // W[, jw] = A V[, j] (scaled, shifted, centred)
        i = 0usize
        while i < n {
            tmpn[i] = vm[(j - 1usize) * n + i]
            if hass { tmpn[i] = tmpn[i] / o.scale[i] }
            i += 1usize
        }
        gemv(x, m0, n0, ichg, tmpn, tmpm)
        mprod += 1usize
        i = 0usize
        while i < m {
            wm[(jw - 1usize) * m + i] = tmpm[i]
            i += 1usize
        }
        if o.has_shift {
            i = 0usize
            while i < m {
                wm[(jw - 1usize) * m + i] += o.shift * tmpn[i % n]
                i += 1usize
            }
        }
        if hasc {
            let cs = dotp(o.center, tmpn, n)
            i = 0usize
            while i < m {
                wm[(jw - 1usize) * m + i] = wm[(jw - 1usize) * m + i] - cs
                i += 1usize
            }
        }
        if iter != 1usize && wide && reorth {
            orthog(wm[(j - 1usize) * m..j * m], wm[0usize..(j - 1usize) * m], m, j - 1usize, tmpm)
        }
        s = norm2(wm[(jw - 1usize) * m..jw * m], m)
        if (s != s || s < eps2) && j == 1usize { ret NearNull }
        if s != s || s < eps2 {
            i = 0usize
            while i < m {
                wm[(jw - 1usize) * m + i] = rr.rnorm(g, 0.0f64, 1.0f64)
                i += 1usize
            }
            if wide { orthog(wm[(j - 1usize) * m..j * m], wm[0usize..(j - 1usize) * m], m, j - 1usize, tmpm) }
            let nn = norm2(wm[(jw - 1usize) * m..jw * m], m)
            i = 0usize
            while i < m {
                wm[(jw - 1usize) * m + i] = wm[(jw - 1usize) * m + i] / nn
                i += 1usize
            }
            s = 0.0f64
        } else {
            i = 0usize
            while i < m {
                wm[(jw - 1usize) * m + i] = wm[(jw - 1usize) * m + i] / s
                i += 1usize
            }
        }
        while j <= work {
            var invs = 0usize
            jw = 1usize
            if wide { jw = j }
            // F = A' W[, jw] (shift, scale, centre)
            gemv(x, m0, n0, !ichg, wm[(jw - 1usize) * m..jw * m], fv)
            if o.has_shift {
                i = 0usize
                while i < n {
                    fv[i] += o.shift * wm[(jw - 1usize) * m + (i % m)]
                    i += 1usize
                }
            }
            if hass {
                i = 0usize
                while i < n {
                    fv[i] = fv[i] / o.scale[i]
                    i += 1usize
                }
            }
            if hasc {
                let sw = sum_ld(wm[(jw - 1usize) * m..jw * m], m)
                i = 0usize
                while i < n {
                    var sub = sw * o.center[i]
                    if hass { sub = sub / o.scale[i] }
                    fv[i] = fv[i] - sub
                    i += 1usize
                }
            }
            mprod += 1usize
            i = 0usize
            while i < n {
                fv[i] = fv[i] - s * vm[(j - 1usize) * n + i]
                i += 1usize
            }
            orthog(fv, vm[0usize..j * n], n, j, tmpn)
            var rr1 = 0.0f64
            if j + 1usize <= work {
                rr1 = norm2(fv, n)
                if rr1 != rr1 || rr1 < eps2 {
                    invs += 1usize
                    i = 0usize
                    while i < n {
                        fv[i] = rr.rnorm(g, 0.0f64, 1.0f64)
                        i += 1usize
                    }
                    orthog(fv, vm[0usize..j * n], n, j, tmpn)
                    let nn = norm2(fv, n)
                    i = 0usize
                    while i < n {
                        vm[j * n + i] = fv[i] / nn
                        i += 1usize
                    }
                    rr1 = 0.0f64
                } else {
                    i = 0usize
                    while i < n {
                        vm[j * n + i] = fv[i] / rr1
                        i += 1usize
                    }
                }
                if nrb == 0usize {
                    bm[0usize] = s
                    bm[1usize] = rr1
                    nrb = 1usize
                    ncb = 2usize
                } else {
                    // rbind(cbind(B, 0), c(rep(0, ncol(B) - 1), S, R))
                    bm[nrb * bs + (ncb - 1usize)] = s
                    bm[nrb * bs + ncb] = rr1
                    nrb += 1usize
                    ncb += 1usize
                }
                let jj1 = j + 1usize
                var jp = 1usize
                if wide { jp = jj1 }
                // w_old
                i = 0usize
                while i < m {
                    tmpm[i] = wm[(jw - 1usize) * m + i]
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    tmpn[i] = vm[j * n + i]
                    if hass { tmpn[i] = tmpn[i] / o.scale[i] }
                    i += 1usize
                }
                gemv(x, m0, n0, ichg, tmpn, tmp2[0usize..m])
                mprod += 1usize
                i = 0usize
                while i < m {
                    wm[(jp - 1usize) * m + i] = tmp2[i]
                    i += 1usize
                }
                if o.has_shift {
                    i = 0usize
                    while i < m {
                        wm[(jp - 1usize) * m + i] += o.shift * tmpn[i % n]
                        i += 1usize
                    }
                }
                if hasc {
                    let cs = dotp(o.center, tmpn, n)
                    i = 0usize
                    while i < m {
                        wm[(jp - 1usize) * m + i] = wm[(jp - 1usize) * m + i] - cs
                        i += 1usize
                    }
                }
                i = 0usize
                while i < m {
                    wm[(jp - 1usize) * m + i] = wm[(jp - 1usize) * m + i] - rr1 * tmpm[i]
                    i += 1usize
                }
                if reorth && wide { orthog(wm[j * m..(j + 1usize) * m], wm[0usize..j * m], m, j, tmpm) }
                s = norm2(wm[(jp - 1usize) * m..jp * m], m)
                if s != s || s < eps2 {
                    invs += 1usize
                    i = 0usize
                    while i < m {
                        wm[(jp - 1usize) * m + i] = rr.rnorm(g, 0.0f64, 1.0f64)
                        i += 1usize
                    }
                    if wide { orthog(wm[j * m..(j + 1usize) * m], wm[0usize..j * m], m, j, tmpm) }
                    let nn = norm2(wm[(jp - 1usize) * m..jp * m], m)
                    i = 0usize
                    while i < m {
                        wm[(jp - 1usize) * m + i] = wm[(jp - 1usize) * m + i] / nn
                        i += 1usize
                    }
                    s = 0.0f64
                } else {
                    i = 0usize
                    while i < m {
                        wm[(jp - 1usize) * m + i] = wm[(jp - 1usize) * m + i] / s
                        i += 1usize
                    }
                }
            } else {
                bm[nrb * bs + (j - 1usize)] = s
                nrb += 1usize
            }
            if invs > 3usize {
                var wn = work + 5usize
                if mn - 1usize < wn { wn = mn - 1usize }
                if wn > work { work = wn }
                invs = 0usize
            }
            j += 1usize
        }
        bsz = nrb
        rf = norm2(fv, n)
        i = 0usize
        while i < n {
            fv[i] = fv[i] / rf
            i += 1usize
        }
        // B (bsz by bsz, column-major) and its svd
        var jc = 0usize
        while jc < bsz {
            i = 0usize
            while i < bsz {
                bq[jc * bsz + i] = bm[i * bs + jc]
                i += 1usize
            }
            jc += 1usize
        }
        let es = svd_cols(a, bq[0usize..bsz * bsz], bsz, bsz, bsv, bu, bv)
        if es != ok {
            bfail = true
            break
        }
        if iter == 1usize {
            smax = bsv[0usize]
            smin = bsv[bsz - 1usize]
        } else {
            if bsv[0usize] > smax { smax = bsv[0usize] }
            if bsv[bsz - 1usize] < smin { smin = bsv[bsz - 1usize] }
        }
        if eps23 > smax { smax = eps23 }
        if !reorth && smin / smax < sqrteps { reorth = true }
        if o.smallest {
            // reverse the order of the columns of u, v and of d
            var lo = 0usize
            var hi = bsz - 1usize
            while lo < hi {
                let t = bsv[lo]
                bsv[lo] = bsv[hi]
                bsv[hi] = t
                i = 0usize
                while i < bsz {
                    let t1 = bu[lo * bsz + i]
                    bu[lo * bsz + i] = bu[hi * bsz + i]
                    bu[hi * bsz + i] = t1
                    let t2 = bv[lo * bsz + i]
                    bv[lo * bsz + i] = bv[hi * bsz + i]
                    bv[hi * bsz + i] = t2
                    i += 1usize
                }
                lo += 1usize
                hi -= 1usize
            }
        }
        // R = R_F * Bsvd$u[Bsz, ]
        i = 0usize
        while i < bsz {
            rrow[i] = rf * bu[i * bsz + (bsz - 1usize)]
            i += 1usize
        }
        // convtests
        var len_res = 0usize
        i = 0usize
        while i < k_org {
            var sub_ok = math.abs[f64](rrow[i]) < o.tol * smax
            let lv = lastsv[i]
            var lastv = 0.0f64
            if have_last { lastv = lv }
            let dlt = math.abs[f64](bsv[i] - lastv) / bsv[i]
            var dok = dlt < o.svtol
            if dlt != dlt { dok = false }
            if sub_ok && dok { len_res += 1usize }
            i += 1usize
        }
        var conv_now = false
        if len_res >= k_org || s == 0.0f64 { conv_now = true }
        var knew = k
        if !conv_now {
            knew = k
            if k_org + len_res > knew { knew = k_org + len_res }
            var cap = 1usize
            if bsz > 4usize { cap = bsz - 3usize }
            if cap < knew { knew = cap }
        }
        // lastsv <- Bsvd$d
        i = 0usize
        while i < bsz {
            lastsv[i] = bsv[i]
            i += 1usize
        }
        have_last = true
        if !conv_now && k_org < bsz {
            var gap = math.abs[f64](bsv[1usize] - bsv[0usize])
            i = 1usize
            while i + 1usize < bsz {
                let dd = math.abs[f64](bsv[i + 1usize] - bsv[i])
                if dd < gap { gap = dd }
                i += 1usize
            }
            var den = math.abs[f64](bsv[k_org - 1usize])
            if eps * smax > den { den = eps * smax }
            let ext_gap = gap / den
            // lastsv was just overwritten, so the relative change is zero
            if ext_gap < math.sqrt[f64](eps) && 0.0f64 < o.svtol {
                clustered += 1usize
                maxritz += 1usize
            } else {
                clustered = 0usize
            }
            if clustered > 1usize {
                var wn = work + 5usize
                if mn - 1usize < wn { wn = mn - 1usize }
                if wn > work {
                    work = wn
                    clustered = 0usize
                }
            }
        }
        k = knew
        if conv_now {
            converged = true
            break
        }
        if iter >= o.maxit { break }
        if o.smallest && smin / smax > sqrteps {
            // the harmonic Ritz restart
            let (b2, f1) = zalloc(a, bsz * (bsz + 1usize))
            let (b2s, f2) = zalloc(a, bsz)
            let (b2u, f3) = zalloc(a, bsz * bsz)
            let (b2v, f4) = zalloc(a, (bsz + 1usize) * bsz)
            if f1 != ok || f2 != ok || f3 != ok || f4 != ok { ret mem.Full }
            jc = 0usize
            while jc < bsz {
                b2[jc * bsz + jc] = bsv[jc]
                jc += 1usize
            }
            i = 0usize
            while i < bsz {
                b2[bsz * bsz + i] = rrow[i]
                i += 1usize
            }
            let e2s = svd_cols(a, b2, bsz, bsz + 1usize, b2s, b2u, b2v)
            if e2s != ok { ret e2s }
            var lo = 0usize
            var hi = bsz - 1usize
            while lo < hi {
                let t = b2s[lo]
                b2s[lo] = b2s[hi]
                b2s[hi] = t
                i = 0usize
                while i < bsz {
                    let t1 = b2u[lo * bsz + i]
                    b2u[lo * bsz + i] = b2u[hi * bsz + i]
                    b2u[hi * bsz + i] = t1
                    i += 1usize
                }
                i = 0usize
                while i < bsz + 1usize {
                    let t2 = b2v[lo * (bsz + 1usize) + i]
                    b2v[lo * (bsz + 1usize) + i] = b2v[hi * (bsz + 1usize) + i]
                    b2v[hi * (bsz + 1usize) + i] = t2
                    i += 1usize
                }
                lo += 1usize
                hi -= 1usize
            }
            i = 0usize
            while i < bsz {
                bsv[i] = b2s[i]
                i += 1usize
            }
            // Bsvd$u = Bsvd$u %*% Bsvd2$u
            let (nu2, f5) = zalloc(a, bsz * bsz)
            if f5 != ok { ret mem.Full }
            mmul(bu[0usize..bsz * bsz], b2u, bsz, bsz, bsz, nu2)
            i = 0usize
            while i < bsz * bsz {
                bu[i] = nu2[i]
                i += 1usize
            }
            // Bsvd$v = cbind(rbind(Bsvd$v, 0), e_last) %*% Bsvd2$v, (bsz + 1) by bsz
            let (ext, f6) = zalloc(a, (bsz + 1usize) * (bsz + 1usize))
            let (nv2, f7) = zalloc(a, (bsz + 1usize) * bsz)
            if f6 != ok || f7 != ok { ret mem.Full }
            jc = 0usize
            while jc < bsz {
                i = 0usize
                while i < bsz {
                    ext[jc * (bsz + 1usize) + i] = bv[jc * bsz + i]
                    i += 1usize
                }
                jc += 1usize
            }
            ext[bsz * (bsz + 1usize) + bsz] = 1.0f64
            mmul(ext, b2v, bsz + 1usize, bsz + 1usize, bsz, nv2)
            // V_B_last = Bsvd$v[Bsz + 1, 1:k]
            let (vbl, f8) = zalloc(a, k)
            if f8 != ok { ret mem.Full }
            i = 0usize
            while i < k {
                vbl[i] = nv2[i * (bsz + 1usize) + bsz]
                i += 1usize
            }
            // s = R_F * solve(B, e_last)
            let (sv, f9) = zalloc(a, bsz)
            let (lu, f10) = zalloc(a, bsz * bsz)
            if f9 != ok || f10 != ok { ret mem.Full }
            i = 0usize
            while i < bsz * bsz {
                lu[i] = bm[(i % bsz) * bs + (i / bsz)]
                i += 1usize
            }
            sv[bsz - 1usize] = 1.0f64
            // Gaussian elimination with partial pivoting (column-major lu, rhs sv)
            var cc = 0usize
            while cc < bsz {
                var pv = cc
                var pmax = math.abs[f64](lu[cc * bsz + cc])
                i = cc + 1usize
                while i < bsz {
                    if math.abs[f64](lu[cc * bsz + i]) > pmax {
                        pmax = math.abs[f64](lu[cc * bsz + i])
                        pv = i
                    }
                    i += 1usize
                }
                if pv != cc {
                    var c2 = 0usize
                    while c2 < bsz {
                        let t = lu[c2 * bsz + cc]
                        lu[c2 * bsz + cc] = lu[c2 * bsz + pv]
                        lu[c2 * bsz + pv] = t
                        c2 += 1usize
                    }
                    let t3 = sv[cc]
                    sv[cc] = sv[pv]
                    sv[pv] = t3
                }
                i = cc + 1usize
                while i < bsz {
                    let f = lu[cc * bsz + i] / lu[cc * bsz + cc]
                    var c2 = cc
                    while c2 < bsz {
                        lu[c2 * bsz + i] = lu[c2 * bsz + i] - f * lu[c2 * bsz + cc]
                        c2 += 1usize
                    }
                    sv[i] = sv[i] - f * sv[cc]
                    i += 1usize
                }
                cc += 1usize
            }
            i = bsz
            while i > 0usize {
                i -= 1usize
                if sv[i] != 0.0f64 {
                    sv[i] = sv[i] / lu[i * bsz + i]
                    var c2 = 0usize
                    while c2 < i {
                        sv[c2] = sv[c2] - sv[i] * lu[i * bsz + c2]
                        c2 += 1usize
                    }
                }
            }
            i = 0usize
            while i < bsz {
                sv[i] = rf * sv[i]
                i += 1usize
            }
            // Bsvd$v = nv2[1:bsz, ] + s %*% nv2[bsz + 1, ]; kept in bv
            jc = 0usize
            while jc < bsz {
                i = 0usize
                while i < bsz {
                    bv[jc * bsz + i] = nv2[jc * (bsz + 1usize) + i] + sv[i] * nv2[jc * (bsz + 1usize) + bsz]
                    i += 1usize
                }
                jc += 1usize
            }
            // qr(cbind(rbind(Bsvd$v[, 1:k], 0), rbind(-s, 1)))
            let (mq, f11) = zalloc(a, (bsz + 1usize) * (k + 1usize))
            let (qq, f12) = zalloc(a, (bsz + 1usize) * (k + 1usize))
            let (rq, f13) = zalloc(a, (k + 1usize) * (k + 1usize))
            if f11 != ok || f12 != ok || f13 != ok { ret mem.Full }
            jc = 0usize
            while jc < k {
                i = 0usize
                while i < bsz {
                    mq[jc * (bsz + 1usize) + i] = bv[jc * bsz + i]
                    i += 1usize
                }
                jc += 1usize
            }
            i = 0usize
            while i < bsz {
                mq[k * (bsz + 1usize) + i] = 0.0f64 - sv[i]
                i += 1usize
            }
            mq[k * (bsz + 1usize) + bsz] = 1.0f64
            let mk = mem.mark(a)
            let eq = qr_thin(a, mq, bsz + 1usize, k + 1usize, qq, rq)
            mem.reset(a, mk)
            if eq != ok { ret eq }
            // V[, 1:(k + 1)] = cbind(V, F) %*% Q
            let (vx, f14) = zalloc(a, n * (bsz + 1usize))
            let (vn, f15) = zalloc(a, n * (k + 1usize))
            if f14 != ok || f15 != ok { ret mem.Full }
            i = 0usize
            while i < n * bsz {
                vx[i] = vm[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                vx[bsz * n + i] = fv[i]
                i += 1usize
            }
            mmul(vx, qq, n, bsz + 1usize, k + 1usize, vn)
            i = 0usize
            while i < n * (k + 1usize) {
                vm[i] = vn[i]
                i += 1usize
            }
            // UT = t(R[1:(k+1), 1:k] + R[, k+1] %*% t(V_B_last)); B = diag(d[1:k]) (UT * upper.tri(UT, diag = TRUE))
            i = 0usize
            while i < bs * bs {
                bm[i] = 0.0f64
                i += 1usize
            }
            var rw = 0usize
            while rw < k {
                var cl = 0usize
                while cl < k + 1usize {
                    if cl >= rw {
                        // UT[rw, cl] = R[cl, rw] + R[cl, k] * vbl[rw]
                        bm[rw * bs + cl] = bsv[rw] * (rq[rw * (k + 1usize) + cl] + rq[k * (k + 1usize) + cl] * vbl[rw])
                    }
                    cl += 1usize
                }
                rw += 1usize
            }
            nrb = k
            ncb = k + 1usize
        } else {
            // V[, 1:(k + 1)] = cbind(V[, 1:bsz] %*% Bsvd$v[, 1:k], F); B = cbind(diag(d[1:k]), R[1:k])
            mmul(vm[0usize..n * bsz], bv[0usize..bsz * bsz], n, bsz, k, tb[0usize..n * k])
            i = 0usize
            while i < n * k {
                vm[i] = tb[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                vm[k * n + i] = fv[i]
                i += 1usize
            }
            i = 0usize
            while i < bs * bs {
                bm[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < k {
                bm[i * bs + i] = bsv[i]
                bm[i * bs + k] = rrow[i]
                i += 1usize
            }
            nrb = k
            ncb = k + 1usize
        }
        if wide {
            mmul(wm[0usize..m * bsz], bu[0usize..bsz * bsz], m, bsz, k, tb[0usize..m * k])
            i = 0usize
            while i < m * k {
                wm[i] = tb[i]
                i += 1usize
            }
        }
        iter += 1usize
    }
    if bfail { ret BadArg }
    // d, U, V from the last Bsvd
    let (d, g1) = zalloc(a, k_org)
    let (vo, g2) = zalloc(a, n * nv)
    if g1 != ok || g2 != ok { ret mem.Full }
    var uo: []f64 = zero
    if wide {
        let (uu, g3) = zalloc(a, m * nu)
        if g3 != ok { ret mem.Full }
        uo = uu
    }
    i = 0usize
    while i < k_org {
        d[i] = bsv[i]
        i += 1usize
    }
    // U = W[, 1:bsz] Bsvd$u[, 1:k_org]; V = V[, 1:bsz] Bsvd$v[, 1:k_org]; then reversed for smallest, then cut to nu and nv columns
    var uc = k_org
    if nu < uc { uc = nu }
    let (ufull, g4) = zalloc(a, m * k_org)
    let (vfull, g5) = zalloc(a, n * k_org)
    if g4 != ok || g5 != ok { ret mem.Full }
    if wide { mmul(wm[0usize..m * bsz], bu[0usize..bsz * bsz], m, bsz, k_org, ufull) }
    mmul(vm[0usize..n * bsz], bv[0usize..bsz * bsz], n, bsz, k_org, vfull)
    if o.smallest {
        i = 0usize
        while i < k_org {
            d[i] = bsv[k_org - 1usize - i]
            i += 1usize
        }
    }
    var c = 0usize
    while c < nu {
        var sc = c
        if o.smallest { sc = k_org - 1usize - c }
        if wide {
            i = 0usize
            while i < m {
                uo[c * m + i] = ufull[sc * m + i]
                i += 1usize
            }
        }
        c += 1usize
    }
    c = 0usize
    while c < nv {
        var sc = c
        if o.smallest { sc = k_org - 1usize - c }
        i = 0usize
        while i < n {
            vo[c * n + i] = vfull[sc * n + i]
            i += 1usize
        }
        c += 1usize
    }
    res.d = d
    res.iter = iter
    res.mprod = mprod
    res.converged = converged
    if ichg {
        res.u = vo
        res.ur = n
        res.nu = nv
        res.v = uo
        res.vr = m
        res.nv = nu
    } else {
        res.u = uo
        res.ur = m
        res.nu = nu
        res.v = vo
        res.vr = n
        res.nv = nv
    }
    if o.right_only {
        res.u = uo
        res.nu = 0usize
    }
    let _w = wdim
    let _r = maxritz
    ret ok
}
