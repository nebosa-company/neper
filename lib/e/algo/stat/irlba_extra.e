// The rest of the irlba package on top of e.algo.stat.irlba: svdr (the randomised power iteration, with qr.Q and R's svd), partial_eigen, prcomp_irlba and ssvd.
// Column-major matrices, R's rnorm start under rr.seed, the signs of R's qr and svd.

use e.algo.rand.r as rr
use e.algo.stat.irlba as il
use e.math
use e.mem

// out (c1 by c2) = a' b for the r by c1 and r by c2 matrices a and b
fn gemm_tn(a: []const f64, b: []const f64, r: usize, c1: usize, c2: usize, out: []f64) {
    var j = 0usize
    while j < c2 {
        var i = 0usize
        while i < c1 {
            out[j * c1 + i] = il.dotp(a[i * r..(i + 1usize) * r], b[j * r..(j + 1usize) * r], r)
            i += 1usize
        }
        j += 1usize
    }
}

fn transpose(a: []const f64, r: usize, c: usize, out: []f64) {
    var j = 0usize
    while j < c {
        var i = 0usize
        while i < r {
            out[i * c + j] = a[j * r + i]
            i += 1usize
        }
        j += 1usize
    }
}

// the x %*% q of svdr, minus rep(1, m) %*% crossprod(center, q) with a centre; xq is m by nq
fn project(x: []const f64, m: usize, n: usize, q: []const f64, nq: usize, center: []const f64, xq: []f64) {
    il.mmul(x, q, m, n, nq, xq)
    if center.len > 0usize {
        var j = 0usize
        while j < nq {
            let cq = il.dotp(center, q[j * n..(j + 1usize) * n], n)
            var i = 0usize
            while i < m {
                xq[j * m + i] = xq[j * m + i] - cq
                i += 1usize
            }
            j += 1usize
        }
    }
}

// irlba::svdr(x, k, tol, it, extra, center): x is m by n; res.d (k), res.u (m by k), res.v (n by k), res.mprod = 2 j + 1. Needs m and n at least min(n, k + extra).
fn svdr(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, n: usize, k: usize, extra: usize, tol: f64, it: usize, center: []const f64, res: *il.Fit) -> err {
    var nq = k + extra
    if n < nq { nq = n }
    if m < nq || k > nq || k == 0usize { ret il.BadArg }
    let (q, e1) = il.zalloc(a, n * nq)
    let (d, e2) = il.zalloc(a, k)
    let (d1, e3) = il.zalloc(a, nq)
    let (xq, e4) = il.zalloc(a, m * nq)
    let (q1, e5) = il.zalloc(a, m * nq)
    let (rm, e6) = il.zalloc(a, nq * nq)
    let (b, e7) = il.zalloc(a, n * nq)
    let (bt, e8) = il.zalloc(a, n * nq)
    let (qn, e9) = il.zalloc(a, n * nq)
    let (cs, e10) = il.zalloc(a, nq)
    let (sv, e11) = il.zalloc(a, nq)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    var i = 0usize
    while i < n * nq {
        q[i] = rr.rnorm(g, 0.0f64, 1.0f64)
        i += 1usize
    }
    let eps2 = math.pow[f64](2.220446049250313e-16f64, 0.8f64)
    let hasc = center.len > 0usize
    var j = 1usize
    while j <= it {
        let mk = mem.mark(a)
        project(x, m, n, q, nq, center, xq)
        let eq1 = il.qr_thin(a, xq, m, nq, q1, rm)
        if eq1 != ok { ret eq1 }
        var kd = 0usize
        if !hasc {
            gemm_tn(x, q1, m, n, nq, b)
            let eq2 = il.qr_thin(a, b, n, nq, q, rm)
            if eq2 != ok { ret eq2 }
            let (uu, f1) = il.zalloc(a, n * nq)
            let (vv, f2) = il.zalloc(a, nq * nq)
            if f1 != ok || f2 != ok { ret mem.Full }
            let es = il.svd_cols(a, b, n, nq, sv, uu, vv)
            if es != ok { ret es }
            kd = nq
        } else {
            // B = crossprod(q1, x) - tcrossprod(colSums(q1), center), nq by n
            gemm_tn(q1, x, m, nq, n, bt)
            var c = 0usize
            while c < nq {
                var sm = 0.0f64
                var r = 0usize
                while r < m {
                    sm += q1[c * m + r]
                    r += 1usize
                }
                cs[c] = sm
                c += 1usize
            }
            var cc = 0usize
            while cc < n {
                c = 0usize
                while c < nq {
                    bt[cc * nq + c] = bt[cc * nq + c] - cs[c] * center[cc]
                    c += 1usize
                }
                cc += 1usize
            }
            transpose(bt, nq, n, b)
            let eq3 = il.qr_thin(a, b, n, nq, q, rm)
            if eq3 != ok { ret eq3 }
            let (uu, f1) = il.zalloc(a, nq * nq)
            let (vv, f2) = il.zalloc(a, n * nq)
            if f1 != ok || f2 != ok { ret mem.Full }
            let es = il.svd_cols(a, bt, nq, n, sv, uu, vv)
            if es != ok { ret es }
            kd = nq
        }
        let _ = kd
        i = 0usize
        while i < k {
            d1[i] = sv[i]
            i += 1usize
        }
        mem.reset(a, mk)
        // idx = d1 > eps2; stop when none, or when the relative change of those is below tol
        var any = false
        var worst = 0.0f64
        i = 0usize
        while i < k {
            if d1[i] > eps2 {
                any = true
                var rel = math.abs[f64]((d1[i] - d[i]) / d[i])
                if d[i] == 0.0f64 { rel = math.inf64() }
                if rel > worst { worst = rel }
            }
            i += 1usize
        }
        if !any { break }
        if worst < tol { break }
        i = 0usize
        while i < k {
            d[i] = d1[i]
            i += 1usize
        }
        j += 1usize
    }
    if j > it { j = it }
    // the final pass
    project(x, m, n, q, nq, center, xq)
    let eqf = il.qr_thin(a, xq, m, nq, q1, rm)
    if eqf != ok { ret eqf }
    let (bf, f3) = il.zalloc(a, nq * n)
    let (su, f4) = il.zalloc(a, nq * nq)
    let (sw, f5) = il.zalloc(a, n * nq)
    let (sd, f6) = il.zalloc(a, nq)
    let (uf, f7) = il.zalloc(a, m * nq)
    if f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok { ret mem.Full }
    gemm_tn(q1, x, m, nq, n, bf)
    if hasc {
        var c = 0usize
        while c < nq {
            var sm = 0.0f64
            var r = 0usize
            while r < m {
                sm += q1[c * m + r]
                r += 1usize
            }
            cs[c] = sm
            c += 1usize
        }
        var cc = 0usize
        while cc < n {
            c = 0usize
            while c < nq {
                bf[cc * nq + c] = bf[cc * nq + c] - cs[c] * center[cc]
                c += 1usize
            }
            cc += 1usize
        }
    }
    let ef = il.svd_cols(a, bf, nq, n, sd, su, sw)
    if ef != ok { ret ef }
    il.mmul(q1, su, m, nq, nq, uf)
    let (dk, f8) = il.zalloc(a, k)
    let (uk, f9) = il.zalloc(a, m * k)
    let (vk, f10) = il.zalloc(a, n * k)
    if f8 != ok || f9 != ok || f10 != ok { ret mem.Full }
    i = 0usize
    while i < k {
        dk[i] = sd[i]
        i += 1usize
    }
    i = 0usize
    while i < m * k {
        uk[i] = uf[i]
        i += 1usize
    }
    i = 0usize
    while i < n * k {
        vk[i] = sw[i]
        i += 1usize
    }
    res.d = dk
    res.u = uk
    res.v = vk
    res.ur = m
    res.vr = n
    res.nu = k
    res.nv = k
    res.iter = j
    res.mprod = 2usize * j + 1usize
    res.converged = true
    ret ok
}

// irlba::partial_eigen(x, n = nev, symmetric): res.d the eigenvalues, res.u the eigenvectors (n by nev); the non-symmetric form answers the right singular vectors and the squared values
fn partial_eigen(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, n: usize, nev: usize, symmetric: bool, o0: il.Opts, res: *il.Fit) -> err {
    var o = o0
    o.nv = nev
    o.nu = nev
    var l: il.Fit = zero
    let e1 = il.irlba(a, g, x, m, n, o, &l)
    if e1 != ok { ret e1 }
    if !symmetric {
        var i = 0usize
        while i < nev {
            l.d[i] = l.d[i] * l.d[i]
            i += 1usize
        }
        res.d = l.d
        res.u = l.v
        res.ur = l.vr
        res.nu = l.nv
        ret ok
    }
    var allpos = true
    var c = 0usize
    while c < nev {
        if !(l.u[c * l.ur] * l.v[c * l.vr] > 0.0f64) { allpos = false }
        c += 1usize
    }
    if allpos {
        res.d = l.d
        res.u = l.u
        res.ur = l.ur
        res.nu = l.nu
        ret ok
    }
    // all(s > 0) failed: the first negative sign (a zero product is not positive, but only a negative one is searched for)
    var neg = nev
    c = 0usize
    while c < nev {
        let sgn = l.u[c * l.ur] * l.v[c * l.vr]
        if sgn < 0.0f64 {
            if neg == nev { neg = c }
        }
        c += 1usize
    }
    if neg == nev { ret il.BadArg }
    let shift = l.d[neg]
    o.has_shift = true
    o.shift = shift
    var l2: il.Fit = zero
    let e2 = il.irlba(a, g, x, m, n, o, &l2)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < nev {
        l2.d[i] = l2.d[i] - shift
        i += 1usize
    }
    res.d = l2.d
    res.u = l2.u
    res.ur = l2.ur
    res.nu = l2.nu
    ret ok
}

type Prcomp = struct { sdev: []f64, rot: []f64, scores: []f64, totalvar: f64, iter: usize }

// irlba::prcomp_irlba(x, n, center, scale.): x is m by p column-major
fn prcomp_irlba(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, p: usize, nv: usize, center: bool, scale: bool, o0: il.Opts, out: *Prcomp) -> err {
    var o = o0
    o.nv = nv
    o.nu = nv
    var denom = 1.0f64
    if m > 1usize { denom = f64(m - 1usize) }
    let (cen, e1) = il.zalloc(a, p)
    let (sc, e2) = il.zalloc(a, p)
    let (tmp, e3) = il.zalloc(a, m)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var totalvar = 0.0f64
    var j = 0usize
    if center {
        j = 0usize
        while j < p {
            cen[j] = il.mean_ld(x[j * m..(j + 1usize) * m], m)
            j += 1usize
        }
        o.center = cen
        j = 0usize
        while j < p {
            var i = 0usize
            while i < m {
                let dv = x[j * m + i] - cen[j]
                tmp[i] = dv * dv
                i += 1usize
            }
            sc[j] = math.sqrt[f64](il.sum_ld(tmp, m) / f64(m - 1usize))
            j += 1usize
        }
        if scale {
            totalvar = f64(p)
            o.scale = sc
        } else {
            j = 0usize
            while j < p {
                totalvar += sc[j] * sc[j]
                j += 1usize
            }
        }
    } else {
        if scale {
            j = 0usize
            while j < p {
                var i = 0usize
                while i < m {
                    tmp[i] = x[j * m + i] * x[j * m + i]
                    i += 1usize
                }
                sc[j] = math.sqrt[f64](il.sum_ld(tmp, m) / denom)
                j += 1usize
            }
            j = 0usize
            while j < p {
                var i = 0usize
                while i < m {
                    let dv = x[j * m + i] / sc[j]
                    tmp[i] = dv * dv
                    i += 1usize
                }
                let f = math.sqrt[f64](il.sum_ld(tmp, m) / f64(m - 1usize))
                totalvar += f * f
                j += 1usize
            }
            o.scale = sc
        } else {
            j = 0usize
            while j < p {
                var i = 0usize
                while i < m {
                    tmp[i] = x[j * m + i] * x[j * m + i]
                    i += 1usize
                }
                totalvar += il.sum_ld(tmp, m) / f64(m - 1usize)
                j += 1usize
            }
        }
    }
    var s: il.Fit = zero
    let e = il.irlba(a, g, x, m, p, o, &s)
    if e != ok { ret e }
    let rs = math.sqrt[f64](denom)
    j = 0usize
    while j < nv {
        s.d[j] = s.d[j]
        j += 1usize
    }
    let (sd, e4) = il.zalloc(a, nv)
    let (scores, e5) = il.zalloc(a, m * nv)
    if e4 != ok || e5 != ok { ret mem.Full }
    j = 0usize
    while j < nv {
        sd[j] = s.d[j] / rs
        var i = 0usize
        while i < m {
            scores[j * m + i] = s.u[j * m + i] * s.d[j]
            i += 1usize
        }
        j += 1usize
    }
    out.sdev = sd
    out.rot = s.v
    out.scores = scores
    out.totalvar = totalvar
    out.iter = s.iter
    ret ok
}

type Ssvd = struct { u: []f64, v: []f64, d: []f64, lambda: []f64, iter: usize }

fn first_nonzero_sign(x: []const f64, n: usize) -> f64 {
    var i = 0usize
    while i < n {
        if x[i] != 0.0f64 {
            if x[i] > 0.0f64 { ret 1.0f64 }
            ret -1.0f64
        }
        i += 1usize
    }
    ret 0.0f64
}

// irlba::ssvd(x, k, n = nsp, maxit, tol, center, scale., alpha): sparse SVD by alternating soft-thresholded updates; x is m by p. cen and sca are the centring and scaling
// vectors (empty for none), nsp the number of variables kept per component; the irlba start (and the rest of its options) come from o
fn ssvd(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, p: usize, k: usize, nsp: usize, maxit: usize, tol: f64, cen: []f64, sca: []f64, alpha: f64, o0: il.Opts, out: *Ssvd) -> err {
    if alpha < 0.0f64 || alpha >= 1.0f64 { ret il.BadArg }
    if nsp > p - 1usize { ret il.BadArg }
    var o = o0
    o.nv = k
    o.nu = k
    o.center = cen
    o.scale = sca
    var s: il.Fit = zero
    let e0 = il.irlba(a, g, x, m, p, o, &s)
    if e0 != ok { ret e0 }
    let keep = p - nsp
    let (lam, e1) = il.zalloc(a, k)
    let (y, e2) = il.zalloc(a, p * k)
    let (xsv, e3) = il.zalloc(a, m * k)
    let (qn, e4) = il.zalloc(a, m * k)
    let (rm, e5) = il.zalloc(a, k * k)
    let (uo, e6) = il.zalloc(a, m * k)
    let (col, e7) = il.zalloc(a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var i = 0usize
    while i < p * k {
        s.v[i] = s.d[i % k] * s.v[i]
        i += 1usize
    }
    var iter = 0usize
    var delta = math.inf64()
    let hasc = cen.len == p
    let hass = sca.len == p
    while delta > tol && iter < maxit {
        i = 0usize
        while i < m * k {
            uo[i] = s.u[i]
            i += 1usize
        }
        gemm_tn(x, s.u, m, p, k, y)
        if hasc {
            let su = il.sum_ld(s.u, m * k)
            i = 0usize
            while i < p * k {
                y[i] = y[i] - su * cen[i % p]
                i += 1usize
            }
        }
        if hass {
            i = 0usize
            while i < p * k {
                y[i] = y[i] / sca[i % p]
                i += 1usize
            }
        }
        var j = 0usize
        while j < k {
            // z = sort(|y[, j]|); lambda_j = (1 - alpha) z[keep] + alpha z[keep + 1]
            i = 0usize
            while i < p {
                col[i] = math.abs[f64](y[j * p + i])
                i += 1usize
            }
            var a1 = 1usize
            while a1 < p {
                let cur = col[a1]
                var b1 = a1
                while b1 > 0usize && col[b1 - 1usize] > cur {
                    col[b1] = col[b1 - 1usize]
                    b1 -= 1usize
                }
                col[b1] = cur
                a1 += 1usize
            }
            var hi = 0.0f64
            if keep < p { hi = col[keep] }
            lam[j] = (1.0f64 - alpha) * col[keep - 1usize] + alpha * hi
            j += 1usize
        }
        j = 0usize
        while j < k {
            i = 0usize
            while i < p {
                let yv = y[j * p + i]
                var sg = 0.0f64
                if yv > 0.0f64 { sg = 1.0f64 }
                if yv < 0.0f64 { sg = -1.0f64 }
                var t = math.abs[f64](yv) - lam[j]
                if t < 0.0f64 { t = 0.0f64 }
                s.v[j * p + i] = sg * t
                i += 1usize
            }
            j += 1usize
        }
        if hass {
            i = 0usize
            while i < p * k {
                s.v[i] = s.v[i] / sca[i % p]
                i += 1usize
            }
        }
        il.mmul(x, s.v, m, p, k, xsv)
        if hasc {
            // drop(crossprod(center, v)) has length k and recycles over the m by k product by element index
            var cvs: [64]f64 = zero
            j = 0usize
            while j < k {
                cvs[j] = il.dotp(cen, s.v[j * p..(j + 1usize) * p], p)
                j += 1usize
            }
            i = 0usize
            while i < m * k {
                xsv[i] = xsv[i] - cvs[i % k]
                i += 1usize
            }
        }
        let mk = mem.mark(a)
        let eq = il.qr_thin(a, xsv, m, k, qn, rm)
        mem.reset(a, mk)
        if eq != ok { ret eq }
        j = 0usize
        while j < k {
            let f = first_nonzero_sign(xsv[j * m..(j + 1usize) * m], m) / first_nonzero_sign(qn[j * m..(j + 1usize) * m], m)
            i = 0usize
            while i < m {
                s.u[j * m + i] = qn[j * m + i] * f
                i += 1usize
            }
            j += 1usize
        }
        delta = 0.0f64
        j = 0usize
        while j < k {
            let dg = 1.0f64 - math.abs[f64](il.dotp(uo[j * m..(j + 1usize) * m], s.u[j * m..(j + 1usize) * m], m))
            if dg > delta { delta = dg }
            j += 1usize
        }
        iter += 1usize
    }
    // v <- v %*% diag(1 / sqrt(colSums(v^2))); d = crossprod(u, x %*% (v / scale) - centre term)
    var j = 0usize
    while j < k {
        let nn = 1.0f64 / math.sqrt[f64](il.dotp(s.v[j * p..(j + 1usize) * p], s.v[j * p..(j + 1usize) * p], p))
        i = 0usize
        while i < p {
            s.v[j * p + i] = s.v[j * p + i] * nn
            i += 1usize
        }
        j += 1usize
    }
    let (dv, e8) = il.zalloc(a, p * k)
    let (d1, e9) = il.zalloc(a, m * k)
    let (dd, e10) = il.zalloc(a, k * k)
    if e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
    i = 0usize
    while i < p * k {
        dv[i] = s.v[i]
        if hass { dv[i] = dv[i] / sca[i % p] }
        i += 1usize
    }
    il.mmul(x, dv, m, p, k, d1)
    if hasc {
        var cvs: [64]f64 = zero
        j = 0usize
        while j < k {
            cvs[j] = il.dotp(cen, dv[j * p..(j + 1usize) * p], p)
            j += 1usize
        }
        i = 0usize
        while i < m * k {
            d1[i] = d1[i] - cvs[i % k]
            i += 1usize
        }
    }
    gemm_tn(s.u, d1, m, k, k, dd)
    out.u = s.u
    out.v = s.v
    out.d = dd
    out.lambda = lam
    out.iter = iter
    ret ok
}
