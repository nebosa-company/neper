// RSpectra (the R package, Spectra 0.x): eigs and eigs_sym for symmetric matrices (the implicitly restarted Lanczos method of Spectra's SymEigsSolver and
// SymEigsShiftSolver, with its LCG start vector, its tridiagonal QR eigen solver adapted from Eigen's, restarts, ncv, tol, maxitr and which = LM, LA, SM,
// SA, BE, shift-invert with sigma) and svds (the same solver on the Gram operator, tall or wide, with centring and scaling). Ported statement for
// statement from RSpectra 0.16-2 so the Ritz values and vectors, with their signs, are the ones RSpectra returns. Column-major matrices.
//
// Not here: general (Arnoldi) eigs, complex shifts, sparse operators (a dense copy of a sparse matrix goes through the same code).

use e.algo.stat.irlba as il
use e.math
use e.mem

error BadArg

// the selection rules: 0 LM (largest magnitude), 1 LA, 2 SM, 3 SA, 4 BE
// op kinds: 0 symmetric A (lower triangle) product, 1 shift-invert (A - sigma I)^-1 on the lower triangle, 2 svds tall (A'A), 3 svds wide (AA')
type Op = struct {
    kind: usize, a: []const f64, m: usize, n: usize, dim: usize, lu: []f64, piv: []usize,
    center: bool, scale: bool, ctr: []const f64, scl: []const f64, wm: []f64, wn: []f64
}

type EigsOut = struct { vals: []f64, vecs: []f64, nconv: usize, niter: usize, nops: usize }

fn next_rand(seed: u64) -> u64 {
    let a = 16807u64
    let mx = 2147483647u64
    var lo = a * (seed & 65535u64)
    let hi = a * (seed >> 16u64)
    lo += (hi & 32767u64) << 16u64
    if lo > mx {
        lo = lo & mx
        lo += 1u64
    }
    lo += hi >> 15u64
    if lo > mx {
        lo = lo & mx
        lo += 1u64
    }
    ret lo
}

// SimpleRandom(seed).random_vec(len)
fn random_vec(seed: u64, len: usize, out: []f64) {
    var r = seed & 2147483647u64
    if seed == 0u64 { r = 1u64 }
    var i = 0usize
    while i < len {
        r = next_rand(r)
        out[i] = f64(r) / 2147483647.0f64 - 0.5f64
        i += 1usize
    }
}

fn vdot(x: []const f64, y: []const f64, n: usize) -> f64 { ret il.dotp(x, y, n) }

fn vnorm(x: []const f64, n: usize) -> f64 { ret math.sqrt[f64](il.dotp(x, x, n)) }

// the operator: y = Op x
fn apply(o: *Op, x: []const f64, y: []f64) {
    let n = o.n
    if o.kind == 0usize {
        var i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j < n {
                var v = 0.0f64
                if i >= j { v = o.a[j * n + i] } else { v = o.a[i * n + j] }
                s += v * x[j]
                j += 1usize
            }
            y[i] = s
            i += 1usize
        }
        ret
    }
    if o.kind == 1usize {
        var i = 0usize
        while i < n {
            y[i] = x[i]
            i += 1usize
        }
        // solve with the LU (row-pivoted, unit lower) held in o.lu
        var c = 0usize
        while c < n {
            let p = o.piv[c]
            if p != c {
                let t = y[c]
                y[c] = y[p]
                y[p] = t
            }
            c += 1usize
        }
        c = 0usize
        while c < n {
            var r = c + 1usize
            while r < n {
                y[r] = y[r] - o.lu[c * n + r] * y[c]
                r += 1usize
            }
            c += 1usize
        }
        c = n
        while c > 0usize {
            c -= 1usize
            y[c] = y[c] / o.lu[c * n + c]
            var r = 0usize
            while r < c {
                y[r] = y[r] - o.lu[c * n + r] * y[c]
                r += 1usize
            }
        }
        ret
    }
    let m = o.m
    if o.kind == 2usize {
        // tall: y = S^-1 (A' (A S^-1 x - c'S^-1 x 1) - sum(.) c)
        if !(o.center || o.scale) {
            il.gemv(o.a, m, n, false, x, o.wm)
            il.gemv(o.a, m, n, true, o.wm, y)
        } else {
            var i = 0usize
            while i < n {
                o.wn[i] = x[i] / o.scl[i]
                i += 1usize
            }
            il.gemv(o.a, m, n, false, o.wn, o.wm)
            let cd = il.dotp(o.ctr, o.wn, n)
            i = 0usize
            while i < m {
                o.wm[i] = o.wm[i] - cd
                i += 1usize
            }
            il.gemv(o.a, m, n, true, o.wm, o.wn)
            let sm = sum_of(o.wm, m)
            i = 0usize
            while i < n {
                o.wn[i] = o.wn[i] - sm * o.ctr[i]
                y[i] = o.wn[i] / o.scl[i]
                i += 1usize
            }
        }
        ret
    }
    // wide: y = A (A'x - sum(x) c) / s^2 - c'(.) 1
    il.gemv(o.a, m, n, true, x, o.wn)
    if !(o.center || o.scale) {
        il.gemv(o.a, m, n, false, o.wn, y)
    } else {
        let sx = sum_of(x, m)
        var i = 0usize
        while i < n {
            o.wn[i] = o.wn[i] - sx * o.ctr[i]
            o.wn[i] = o.wn[i] / (o.scl[i] * o.scl[i])
            i += 1usize
        }
        il.gemv(o.a, m, n, false, o.wn, y)
        let cd = il.dotp(o.ctr, o.wn, n)
        i = 0usize
        while i < m {
            y[i] = y[i] - cd
            i += 1usize
        }
    }
}

fn sum_of(x: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i]
        i += 1usize
    }
    ret s
}

// Eigen's JacobiRotation::makeGivens for real p, q: (c, s)
fn make_givens(p: f64, q: f64) -> (f64, f64) {
    var c = 0.0f64
    var s = 0.0f64
    if q == 0.0f64 {
        c = 1.0f64
        if p < 0.0f64 { c = -1.0f64 }
        s = 0.0f64
    } else {
        if p == 0.0f64 {
            c = 0.0f64
            s = -1.0f64
            if q < 0.0f64 { s = 1.0f64 }
        } else {
            if math.abs[f64](p) > math.abs[f64](q) {
                let t = q / p
                var u = math.sqrt[f64](1.0f64 + t * t)
                if p < 0.0f64 { u = 0.0f64 - u }
                c = 1.0f64 / u
                s = (0.0f64 - t) * c
            } else {
                let t = p / q
                var u = math.sqrt[f64](1.0f64 + t * t)
                if q < 0.0f64 { u = 0.0f64 - u }
                s = (0.0f64 - 1.0f64) / u
                c = (0.0f64 - t) * s
            }
        }
    }
    ret (c, s)
}

// TridiagEigen(H): the eigenvalues (unsorted) into ev and the eigenvectors into q (n by n, column-major); H is the n by n symmetric tridiagonal matrix
fn tridiag_eigen(a: *mem.Arena, h: []const f64, n: usize, ev: []f64, q: []f64) -> err {
    var i = 0usize
    while i < n * n {
        q[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        q[i * n + i] = 1.0f64
        i += 1usize
    }
    var scale = 0.0f64
    i = 0usize
    while i < n {
        if math.abs[f64](h[i * n + i]) > scale { scale = math.abs[f64](h[i * n + i]) }
        if i + 1usize < n {
            if math.abs[f64](h[i * n + i + 1usize]) > scale { scale = math.abs[f64](h[i * n + i + 1usize]) }
        }
        i += 1usize
    }
    if scale < 2.2250738585072014e-307f64 * 10.0f64 {
        i = 0usize
        while i < n {
            ev[i] = 0.0f64
            i += 1usize
        }
        ret ok
    }
    let (sd, e1) = il.zalloc(a, n)
    if e1 != ok { ret e1 }
    i = 0usize
    while i < n {
        ev[i] = h[i * n + i] / scale
        if i + 1usize < n { sd[i] = h[i * n + i + 1usize] / scale }
        i += 1usize
    }
    var endi = n - 1usize
    var start = 0usize
    var iter = 0usize
    let tiny = 2.2250738585072014e-308f64
    let precision = 2.0f64 * 2.220446049250313e-16f64
    while endi > 0usize {
        i = start
        while i < endi {
            let dd = (math.abs[f64](ev[i]) + math.abs[f64](ev[i + 1usize])) * precision
            if math.abs[f64](sd[i]) <= tiny || math.abs[f64](sd[i]) <= dd { sd[i] = 0.0f64 }
            i += 1usize
        }
        while endi > 0usize && sd[endi - 1usize] == 0.0f64 { endi -= 1usize }
        if endi == 0usize { break }
        iter += 1usize
        if iter > 30usize * n { ret BadArg }
        start = endi - 1usize
        while start > 0usize && sd[start - 1usize] != 0.0f64 { start -= 1usize }
        // tridiagonal_qr_step(diag, subdiag, start, end, Q)
        let td = (ev[endi - 1usize] - ev[endi]) * 0.5f64
        let e = sd[endi - 1usize]
        var mu = ev[endi]
        if td == 0.0f64 {
            mu = mu - math.abs[f64](e)
        } else {
            let e2 = e * e
            let hh = math.sqrt[f64](td * td + e * e)
            if e2 == 0.0f64 {
                var den = td - 1.0f64
                if td > 0.0f64 { den = td + 1.0f64 }
                mu = mu - (e / den) * (e / hh)
            } else {
                var den = td - hh
                if td > 0.0f64 { den = td + hh }
                mu = mu - e2 / den
            }
        }
        var x = ev[start] - mu
        var z = sd[start]
        var k = start
        while k < endi {
            let (c, s) = make_givens(x, z)
            let sdk = s * ev[k] + c * sd[k]
            let dkp1 = s * sd[k] + c * ev[k + 1usize]
            ev[k] = c * (c * ev[k] - s * sd[k]) - s * (c * sd[k] - s * ev[k + 1usize])
            ev[k + 1usize] = s * sdk + c * dkp1
            sd[k] = c * sdk - s * dkp1
            if k > start { sd[k - 1usize] = c * sd[k - 1usize] - s * z }
            x = sd[k]
            if k < endi - 1usize {
                z = (0.0f64 - s) * sd[k + 1usize]
                sd[k + 1usize] = c * sd[k + 1usize]
            }
            // Q = Q G: x' = c x - s y, y' = s x + c y on columns k and k + 1
            var r = 0usize
            while r < n {
                let xi = q[k * n + r]
                let yi = q[(k + 1usize) * n + r]
                q[k * n + r] = c * xi + (0.0f64 - s) * yi
                q[(k + 1usize) * n + r] = s * xi + c * yi
                r += 1usize
            }
            k += 1usize
        }
    }
    i = 0usize
    while i < n {
        ev[i] = ev[i] * scale
        i += 1usize
    }
    ret ok
}

// sorting targets of Spectra's SortEigenvalue: the index order that sorts the n values by rule (ascending target)
fn sort_index(vals: []const f64, n: usize, rule: usize, ind: []usize) {
    var i = 0usize
    while i < n {
        ind[i] = i
        i += 1usize
    }
    // stable insertion sort on the target
    i = 1usize
    while i < n {
        let cur = ind[i]
        let tc = sort_key(vals[cur], rule)
        var j = i
        while j > 0usize && sort_key(vals[ind[j - 1usize]], rule) > tc {
            ind[j] = ind[j - 1usize]
            j -= 1usize
        }
        ind[j] = cur
        i += 1usize
    }
}

fn sort_key(x: f64, rule: usize) -> f64 {
    if rule == 0usize { ret 0.0f64 - math.abs[f64](x) }
    if rule == 1usize || rule == 4usize { ret 0.0f64 - x }
    if rule == 2usize { ret math.abs[f64](x) }
    ret x
}

// TridiagQR of H - shift I: cos and sin sequences into rc and rs, and the R factor into d (diag), us (1st upper), us2 (2nd upper)
fn compute_rotation(x: f64, y: f64) -> (f64, f64, f64) {
    var xsign = 0.0f64
    if x > 0.0f64 { xsign = 1.0f64 }
    if x < 0.0f64 { xsign = -1.0f64 }
    var ysign = 0.0f64
    if y > 0.0f64 { ysign = 1.0f64 }
    if y < 0.0f64 { ysign = -1.0f64 }
    let xabs = x * xsign
    let yabs = y * ysign
    var r = 0.0f64
    var c = 0.0f64
    var s = 0.0f64
    if xabs > yabs {
        let ratio = yabs / xabs
        let common = math.sqrt[f64](1.0f64 + ratio * ratio)
        c = xsign / common
        r = xabs * common
        s = (0.0f64 - y) / r
    } else {
        if yabs == 0.0f64 {
            ret (0.0f64, 1.0f64, 0.0f64)
        }
        let ratio = xabs / yabs
        let common = math.sqrt[f64](1.0f64 + ratio * ratio)
        s = (0.0f64 - ysign) / common
        r = yabs * common
        c = x / r
    }
    ret (r, c, s)
}

// the whole Lanczos solver state
type Lz = struct {
    n: usize, ncv: usize, nev: usize, v: []f64, h: []f64, f: []f64, beta: f64, k: usize, nops: usize,
    rv: []f64, rvec: []f64, rest: []f64, rconv: []bool
}

// expand_basis: a random f orthogonal to the first cols columns of V, fnorm its norm
fn expand_basis(z: *Lz, cols: usize, seed: u64, vf: []f64, tmp: []f64) {
    let n = z.n
    let thresh = 2.220446049250313e-16f64 * math.sqrt[f64](f64(n))
    var iter = 0usize
    while iter < 5usize {
        random_vec(seed + 123u64 * u64(iter), n, z.f)
        // Vf = V' f; f -= V Vf
        var c = 0usize
        while c < cols {
            vf[c] = il.dotp(z.v[c * n..(c + 1usize) * n], z.f, n)
            c += 1usize
        }
        var i = 0usize
        while i < n {
            tmp[i] = 0.0f64
            i += 1usize
        }
        c = 0usize
        while c < cols {
            i = 0usize
            while i < n {
                tmp[i] += z.v[c * n + i] * vf[c]
                i += 1usize
            }
            c += 1usize
        }
        i = 0usize
        while i < n {
            z.f[i] = z.f[i] - tmp[i]
            i += 1usize
        }
        z.beta = vnorm(z.f, n)
        if z.beta >= thresh { ret }
        iter += 1usize
    }
}

// Lanczos::factorize_from(from_k, to_m)
fn factorize_from(o: *Op, z: *Lz, from_k: usize, to_m: usize, w: []f64, vf: []f64, tmp: []f64) {
    if to_m <= from_k { ret }
    let n = z.n
    let m = z.ncv
    let eps = 2.220446049250313e-16f64
    let beta_thresh = eps * math.sqrt[f64](f64(n))
    let near0 = 2.2250738585072014e-307f64 * 10.0f64
    // keep the upper-left from_k by from_k part of H, zero the rest
    var c = from_k
    while c < m {
        var r = 0usize
        while r < m {
            z.h[c * m + r] = 0.0f64
            r += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < from_k {
        var r = from_k
        while r < m {
            z.h[c * m + r] = 0.0f64
            r += 1usize
        }
        c += 1usize
    }
    var i = from_k
    while i <= to_m - 1usize {
        var restart = false
        if z.beta < near0 {
            expand_basis(z, i, u64(2usize * i), vf, tmp)
            restart = true
        }
        var r = 0usize
        while r < n {
            z.v[i * n + r] = z.f[r] / z.beta
            r += 1usize
        }
        if restart { z.h[(i - 1usize) * m + i] = 0.0f64 } else { z.h[(i - 1usize) * m + i] = z.beta }
        apply(o, z.v[i * n..(i + 1usize) * n], w)
        z.nops += 1usize
        z.h[i * m + (i - 1usize)] = z.h[(i - 1usize) * m + i]
        z.h[i * m + i] = vdot(z.v[i * n..(i + 1usize) * n], w, n)
        let hii = z.h[i * m + i]
        let hsub = z.h[(i - 1usize) * m + i]
        r = 0usize
        while r < n {
            if restart {
                z.f[r] = w[r] - hii * z.v[i * n + r]
            } else {
                z.f[r] = (w[r] - hsub * z.v[(i - 1usize) * n + r]) - hii * z.v[i * n + r]
            }
            r += 1usize
        }
        z.beta = vnorm(z.f, n)
        let i1 = i + 1usize
        var cc = 0usize
        var oerr = 0.0f64
        while cc < i1 {
            vf[cc] = il.dotp(z.v[cc * n..(cc + 1usize) * n], z.f, n)
            if math.abs[f64](vf[cc]) > oerr { oerr = math.abs[f64](vf[cc]) }
            cc += 1usize
        }
        var count = 0usize
        while count < 5usize && oerr > eps * z.beta {
            if z.beta < beta_thresh {
                r = 0usize
                while r < n {
                    z.f[r] = 0.0f64
                    r += 1usize
                }
                z.beta = 0.0f64
                break
            }
            r = 0usize
            while r < n {
                tmp[r] = 0.0f64
                r += 1usize
            }
            cc = 0usize
            while cc < i1 {
                r = 0usize
                while r < n {
                    tmp[r] += z.v[cc * n + r] * vf[cc]
                    r += 1usize
                }
                cc += 1usize
            }
            r = 0usize
            while r < n {
                z.f[r] = z.f[r] - tmp[r]
                r += 1usize
            }
            z.h[i * m + (i - 1usize)] = z.h[(i - 1usize) * m + i] + vf[i - 1usize]
            z.h[(i - 1usize) * m + i] = z.h[i * m + (i - 1usize)]
            z.h[i * m + i] = z.h[i * m + i] + vf[i]
            z.beta = vnorm(z.f, n)
            cc = 0usize
            oerr = 0.0f64
            while cc < i1 {
                vf[cc] = il.dotp(z.v[cc * n..(cc + 1usize) * n], z.f, n)
                if math.abs[f64](vf[cc]) > oerr { oerr = math.abs[f64](vf[cc]) }
                cc += 1usize
            }
            count += 1usize
        }
        i += 1usize
    }
    z.k = to_m
}

// retrieve_ritzpair: the eigen decomposition of H, sorted by rule
fn retrieve_ritzpair(a: *mem.Arena, z: *Lz, rule: usize, ev: []f64, evec: []f64, ind: []usize, ind2: []usize) -> err {
    let m = z.ncv
    let e = tridiag_eigen(a, z.h, m, ev, evec)
    if e != ok { ret e }
    sort_index(ev, m, rule, ind)
    if rule == 4usize {
        var i = 0usize
        while i < m {
            ind2[i] = ind[i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            if i % 2usize == 0usize { ind[i] = ind2[i / 2usize] } else { ind[i] = ind2[m - 1usize - i / 2usize] }
            i += 1usize
        }
    }
    var i = 0usize
    while i < m {
        z.rv[i] = ev[ind[i]]
        z.rest[i] = evec[ind[i] * m + (m - 1usize)]
        i += 1usize
    }
    i = 0usize
    while i < z.nev {
        var r = 0usize
        while r < m {
            z.rvec[i * m + r] = evec[ind[i] * m + r]
            r += 1usize
        }
        i += 1usize
    }
    ret ok
}

// SymEigsSolver / SymEigsShiftSolver compute(): nev Ritz pairs of the operator, sorted decreasing algebraically (after the shift-invert back transform)
fn eigs_run(a: *mem.Arena, o: *Op, n: usize, nev: usize, ncv0: usize, rule: usize, maxit: usize, tol: f64, shifted: bool, sigma: f64, init: []const f64, out: *EigsOut) -> err {
    var ncv = ncv0
    if ncv > n { ncv = n }
    if nev < 1usize || nev + 1usize > n || ncv <= nev { ret BadArg }
    let eps = 2.220446049250313e-16f64
    let eps23 = math.pow[f64](eps, 2.0f64 / 3.0f64)
    let near0 = 2.2250738585072014e-307f64 * 10.0f64
    let (v, e1) = il.zalloc(a, n * ncv)
    let (h, e2) = il.zalloc(a, ncv * ncv)
    let (f, e3) = il.zalloc(a, n)
    let (rv, e4) = il.zalloc(a, ncv)
    let (rvec, e5) = il.zalloc(a, ncv * nev)
    let (rest, e6) = il.zalloc(a, ncv)
    let (w, e7) = il.zalloc(a, n)
    let (vf, e8) = il.zalloc(a, ncv + 1usize)
    let (tmp, e9) = il.zalloc(a, n)
    let (ev, e10) = il.zalloc(a, ncv)
    let (evec, e11) = il.zalloc(a, ncv * ncv)
    let (qm, e12) = il.zalloc(a, ncv * ncv)
    let (qh, e13) = il.zalloc(a, ncv * ncv)
    let (rc, e14) = il.zalloc(a, ncv)
    let (rs, e15) = il.zalloc(a, ncv)
    let (td, e16) = il.zalloc(a, ncv)
    let (tu, e17) = il.zalloc(a, ncv)
    let (ind, e18) = mem.alloc[usize](a, ncv)
    let (ind2, e19) = mem.alloc[usize](a, ncv)
    let (conv, e20) = mem.alloc[bool](a, nev)
    let (vs, e21) = il.zalloc(a, n * (ncv + 1usize))
    let (v0, e22) = il.zalloc(a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok { ret mem.Full }
    var z: Lz = zero
    z.n = n
    z.ncv = ncv
    z.nev = nev
    z.v = v
    z.h = h
    z.f = f
    z.rv = rv
    z.rvec = rvec
    z.rest = rest
    z.k = 0usize
    z.nops = 0usize
    var i = 0usize
    while i < nev {
        conv[i] = false
        i += 1usize
    }
    // init: the start vector, the 1-step factorization
    if init.len == n {
        i = 0usize
        while i < n {
            v0[i] = init[i]
            i += 1usize
        }
    } else {
        random_vec(0u64, n, v0)
    }
    let v0n = vnorm(v0, n)
    if v0n < near0 { ret BadArg }
    i = 0usize
    while i < n {
        z.v[i] = v0[i] / v0n
        i += 1usize
    }
    apply(o, z.v[0usize..n], w)
    z.nops += 1usize
    z.h[0usize] = vdot(z.v[0usize..n], w, n)
    var fmax = 0.0f64
    i = 0usize
    while i < n {
        z.f[i] = w[i] - z.v[i] * z.h[0usize]
        if math.abs[f64](z.f[i]) > fmax { fmax = math.abs[f64](z.f[i]) }
        i += 1usize
    }
    if fmax < eps {
        i = 0usize
        while i < n {
            z.f[i] = 0.0f64
            i += 1usize
        }
        z.beta = 0.0f64
    } else {
        z.beta = vnorm(z.f, n)
    }
    z.k = 1usize
    // compute()
    factorize_from(o, &z, 1usize, ncv, w, vf, tmp)
    let er = retrieve_ritzpair(a, &z, rule, ev, evec, ind, ind2)
    if er != ok { ret er }
    var it = 0usize
    var nconv = 0usize
    while it < maxit {
        // num_converged
        nconv = 0usize
        i = 0usize
        while i < nev {
            var th = math.abs[f64](z.rv[i])
            if eps23 > th { th = eps23 }
            th = tol * th
            let res = math.abs[f64](z.rest[i]) * z.beta
            conv[i] = res < th
            if conv[i] { nconv += 1usize }
            i += 1usize
        }
        if nconv >= nev { break }
        // nev_adjusted
        var nev_new = nev
        i = nev
        while i < ncv {
            if math.abs[f64](z.rest[i]) < near0 { nev_new += 1usize }
            i += 1usize
        }
        var half = (ncv - nev_new) / 2usize
        if nconv < half { half = nconv }
        nev_new += half
        if nev_new == 1usize && ncv >= 6usize {
            nev_new = ncv / 2usize
        } else {
            if nev_new == 1usize && ncv > 2usize { nev_new = 2usize }
        }
        if nev_new > ncv - 1usize { nev_new = ncv - 1usize }
        // restart(nev_new)
        let kk = nev_new
        if kk < ncv {
            i = 0usize
            while i < ncv * ncv {
                qm[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < ncv {
                qm[i * ncv + i] = 1.0f64
                i += 1usize
            }
            var ii = kk
            while ii < ncv {
                let shift = z.rv[ii]
                // TridiagQR::compute(H, shift)
                i = 0usize
                while i < ncv {
                    td[i] = z.h[i * ncv + i] - shift
                    i += 1usize
                }
                // lower subdiagonal copy into qh (reused as lsub), upper subdiagonal into tu
                let n1 = ncv - 1usize
                i = 0usize
                while i < n1 {
                    qh[i] = z.h[i * ncv + i + 1usize]
                    tu[i] = qh[i]
                    i += 1usize
                }
                i = 0usize
                while i < n1 {
                    let (r, c, s) = compute_rotation(td[i], qh[i])
                    rc[i] = c
                    rs[i] = s
                    td[i] = r
                    qh[i] = 0.0f64
                    let tmp1 = tu[i]
                    tu[i] = c * tmp1 - s * td[i + 1usize]
                    td[i + 1usize] = s * tmp1 + c * td[i + 1usize]
                    if i < n1 - 1usize { tu[i + 1usize] = tu[i + 1usize] * c }
                    i += 1usize
                }
                // apply_YQ(Q): Y[, i:(i+1)] = Y[, i:(i+1)] Gi
                i = 0usize
                while i < n1 {
                    let c = rc[i]
                    let s = rs[i]
                    var r = 0usize
                    while r < ncv {
                        let t = qm[i * ncv + r]
                        qm[i * ncv + r] = c * t - s * qm[(i + 1usize) * ncv + r]
                        qm[(i + 1usize) * ncv + r] = s * t + c * qm[(i + 1usize) * ncv + r]
                        r += 1usize
                    }
                    i += 1usize
                }
                // compress_H: H = Q'HQ = RQ + shift I (tridiagonal), k--
                i = 0usize
                while i < ncv * ncv {
                    z.h[i] = 0.0f64
                    i += 1usize
                }
                i = 0usize
                while i < ncv {
                    z.h[i * ncv + i] = td[i]
                    i += 1usize
                }
                i = 0usize
                while i < n1 {
                    let c = rc[i]
                    let s = rs[i]
                    let m11 = z.h[i * ncv + i]
                    let m12 = tu[i]
                    let m22 = td[i + 1usize]
                    z.h[i * ncv + i] = c * m11 - s * m12
                    z.h[i * ncv + i + 1usize] = (0.0f64 - s) * m22
                    z.h[(i + 1usize) * ncv + (i + 1usize)] = c * m22
                    i += 1usize
                }
                i = 0usize
                while i < n1 {
                    z.h[(i + 1usize) * ncv + i] = z.h[i * ncv + i + 1usize]
                    i += 1usize
                }
                i = 0usize
                while i < ncv {
                    z.h[i * ncv + i] = z.h[i * ncv + i] + shift
                    i += 1usize
                }
                z.k -= 1usize
                ii += 1usize
            }
            // compress_V(Q)
            i = 0usize
            while i < z.k {
                let nnz = ncv - z.k + i + 1usize
                var r = 0usize
                while r < n {
                    vs[i * n + r] = 0.0f64
                    r += 1usize
                }
                var c = 0usize
                while c < nnz {
                    let q = qm[i * ncv + c]
                    r = 0usize
                    while r < n {
                        vs[i * n + r] += z.v[c * n + r] * q
                        r += 1usize
                    }
                    c += 1usize
                }
                i += 1usize
            }
            var rr0 = 0usize
            while rr0 < n {
                vs[z.k * n + rr0] = 0.0f64
                rr0 += 1usize
            }
            var cc = 0usize
            while cc < ncv {
                let q = qm[z.k * ncv + cc]
                rr0 = 0usize
                while rr0 < n {
                    vs[z.k * n + rr0] += z.v[cc * n + rr0] * q
                    rr0 += 1usize
                }
                cc += 1usize
            }
            i = 0usize
            while i < n * (z.k + 1usize) {
                z.v[i] = vs[i]
                i += 1usize
            }
            let qlast = qm[(z.k - 1usize) * ncv + (ncv - 1usize)]
            let hk = z.h[(z.k - 1usize) * ncv + z.k]
            i = 0usize
            while i < n {
                z.f[i] = z.f[i] * qlast + z.v[z.k * n + i] * hk
                i += 1usize
            }
            z.beta = vnorm(z.f, n)
            factorize_from(o, &z, kk, ncv, w, vf, tmp)
            let er2 = retrieve_ritzpair(a, &z, rule, ev, evec, ind, ind2)
            if er2 != ok { ret er2 }
        }
        it += 1usize
    }
    // sort_ritzpair(LARGEST_ALGE), after the shift-invert back transform
    if shifted {
        i = 0usize
        while i < nev {
            z.rv[i] = 1.0f64 / z.rv[i] + sigma
            i += 1usize
        }
    }
    sort_index(z.rv, nev, 1usize, ind)
    let (nv2, g1) = il.zalloc(a, ncv)
    let (nvec, g2) = il.zalloc(a, ncv * nev)
    if g1 != ok || g2 != ok { ret mem.Full }
    var nconv_final = 0usize
    i = 0usize
    while i < nev {
        nv2[i] = z.rv[ind[i]]
        var r = 0usize
        while r < ncv {
            nvec[i * ncv + r] = z.rvec[ind[i] * ncv + r]
            r += 1usize
        }
        i += 1usize
    }
    let (cvals, g3) = il.zalloc(a, nev)
    let (cvecs, g4) = il.zalloc(a, n * nev)
    if g3 != ok || g4 != ok { ret mem.Full }
    // converged flags follow the sort
    var j = 0usize
    i = 0usize
    while i < nev {
        if conv[ind[i]] {
            cvals[j] = nv2[i]
            // vector: V * nvec[, i]
            var r = 0usize
            while r < n {
                var sm = 0.0f64
                var c = 0usize
                while c < ncv {
                    sm += z.v[c * n + r] * nvec[i * ncv + c]
                    c += 1usize
                }
                cvecs[j * n + r] = sm
                r += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    nconv_final = j
    out.vals = cvals
    out.vecs = cvecs
    out.nconv = nconv_final
    out.niter = it + 1usize
    out.nops = z.nops
    ret ok
}

// the LU of (A - sigma I) on the lower triangle of the n by n a, with row pivoting; lu is n by n and piv the pivot rows
fn prepare_shift(a: []const f64, n: usize, sigma: f64, lu: []f64, piv: []usize) {
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            var v = 0.0f64
            if i >= j { v = a[j * n + i] } else { v = a[i * n + j] }
            if i == j { v = v - sigma }
            lu[j * n + i] = v
            i += 1usize
        }
        j += 1usize
    }
    var c = 0usize
    while c < n {
        var p = c
        var best = math.abs[f64](lu[c * n + c])
        var r = c + 1usize
        while r < n {
            if math.abs[f64](lu[c * n + r]) > best {
                best = math.abs[f64](lu[c * n + r])
                p = r
            }
            r += 1usize
        }
        piv[c] = p
        if p != c {
            var cc = 0usize
            while cc < n {
                let t = lu[cc * n + c]
                lu[cc * n + c] = lu[cc * n + p]
                lu[cc * n + p] = t
                cc += 1usize
            }
        }
        r = c + 1usize
        while r < n {
            let f = lu[c * n + r] / lu[c * n + c]
            lu[c * n + r] = f
            var cc = c + 1usize
            while cc < n {
                lu[cc * n + r] = lu[cc * n + r] - f * lu[cc * n + c]
                cc += 1usize
            }
            r += 1usize
        }
        c += 1usize
    }
}

// RSpectra::eigs_sym / eigs for a symmetric n by n matrix (lower triangle used): which 0 LM, 1 LA, 2 SM, 3 SA, 4 BE; has_sigma selects shift-invert;
// ncv = 0 takes RSpectra's default min(n, max(2 k + 1, 20)), tol 1e-10 and maxitr 1000 as there when passed as 0
fn eigs_sym(a: *mem.Arena, x: []const f64, n: usize, k: usize, which: usize, has_sigma: bool, sigma: f64, ncv: usize, tol: f64, maxitr: usize, init: []const f64, out: *EigsOut) -> err {
    var nc = ncv
    if nc == 0usize {
        nc = 2usize * k + 1usize
        if nc < 20usize { nc = 20usize }
        if nc > n { nc = n }
    }
    var tl = tol
    if tl == 0.0f64 { tl = 1.0e-10f64 }
    var mi = maxitr
    if mi == 0usize { mi = 1000usize }
    var op: Op = zero
    op.a = x
    op.n = n
    op.dim = n
    if has_sigma {
        let (lu, e1) = il.zalloc(a, n * n)
        let (piv, e2) = mem.alloc[usize](a, n)
        if e1 != ok || e2 != ok { ret mem.Full }
        prepare_shift(x, n, sigma, lu, piv)
        op.kind = 1usize
        op.lu = lu
        op.piv = piv
    }
    ret eigs_run(a, &op, n, k, nc, which, mi, tl, has_sigma, sigma, init, out)
}

// RSpectra::svds on the m by n matrix x (column-major): d (nconv values), u (m by nu) and v (n by nv); center and scale vectors may be empty
type SvdsOut = struct { d: []f64, u: []f64, v: []f64, nconv: usize, niter: usize, nops: usize }

fn svds(a: *mem.Arena, x: []const f64, m: usize, n: usize, k: usize, nu0: usize, nv0: usize, ncv: usize, tol: f64, maxitr: usize, ctr0: []const f64, scl0: []const f64, out: *SvdsOut) -> err {
    let (ctr, ec) = il.zalloc(a, n)
    let (scl, es) = il.zalloc(a, n)
    if ec != ok || es != ok { ret mem.Full }
    var q0 = 0usize
    while q0 < n {
        scl[q0] = 1.0f64
        if ctr0.len == n { ctr[q0] = ctr0[q0] }
        if scl0.len == n { scl[q0] = scl0[q0] }
        q0 += 1usize
    }
    var wd = m
    if n < wd { wd = n }
    var nc = ncv
    if nc == 0usize {
        nc = 2usize * k + 1usize
        if nc < 20usize { nc = 20usize }
        if nc > wd { nc = wd }
    }
    var tl = tol
    if tl == 0.0f64 { tl = 1.0e-10f64 }
    var mi = maxitr
    if mi == 0usize { mi = 1000usize }
    var op: Op = zero
    op.a = x
    op.m = m
    op.n = n
    op.dim = wd
    op.center = ctr0.len == n
    op.scale = scl0.len == n
    op.ctr = ctr
    op.scl = scl
    let (wm, e1) = il.zalloc(a, m)
    let (wn, e2) = il.zalloc(a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    op.wm = wm
    op.wn = wn
    if m > n { op.kind = 2usize } else { op.kind = 3usize }
    var eo: EigsOut = zero
    let e = eigs_run(a, &op, wd, k, nc, 1usize, mi, tl, false, 0.0f64, x[0usize..0usize], &eo)
    if e != ok { ret e }
    var nu = nu0
    var nv = nv0
    if eo.nconv < nu { nu = eo.nconv }
    if eo.nconv < nv { nv = eo.nconv }
    let (d, e3) = il.zalloc(a, eo.nconv)
    let (u, e4) = il.zalloc(a, m * nu)
    let (v, e5) = il.zalloc(a, n * nv)
    if e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    while i < eo.nconv {
        d[i] = math.sqrt[f64](eo.vals[i])
        i += 1usize
    }
    let hasc = ctr0.len == n
    if m > n {
        // evecs are the right vectors; u_i = B v_i / d_i with B = (A - 1 c') S^-1
        i = 0usize
        while i < nv {
            var r = 0usize
            while r < n {
                v[i * n + r] = eo.vecs[i * n + r]
                r += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < nu {
            var r = 0usize
            while r < n {
                var dv = d[i]
                if scl0.len == n { dv = d[i] * scl[r] }
                wn[r] = eo.vecs[i * n + r] / dv
                r += 1usize
            }
            il.gemv(x, m, n, false, wn, u[i * m..(i + 1usize) * m])
            if hasc {
                let cd = il.dotp(ctr, wn, n)
                r = 0usize
                while r < m {
                    u[i * m + r] = u[i * m + r] - cd
                    r += 1usize
                }
            }
            i += 1usize
        }
    } else {
        i = 0usize
        while i < nu {
            var r = 0usize
            while r < m {
                u[i * m + r] = eo.vecs[i * m + r]
                r += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < nv {
            il.gemv(x, m, n, true, eo.vecs[i * m..(i + 1usize) * m], v[i * n..(i + 1usize) * n])
            var sx = 0.0f64
            var r = 0usize
            while r < m {
                sx += eo.vecs[i * m + r]
                r += 1usize
            }
            r = 0usize
            while r < n {
                if hasc { v[i * n + r] = v[i * n + r] - sx * ctr[r] }
                var dv = d[i]
                if scl0.len == n { dv = d[i] * scl[r] }
                v[i * n + r] = v[i * n + r] / dv
                r += 1usize
            }
            i += 1usize
        }
    }
    out.d = d
    out.u = u
    out.v = v
    out.nconv = eo.nconv
    out.niter = eo.niter
    out.nops = eo.nops * 2usize + nv
    if m > n { out.nops = eo.nops * 2usize + nu }
    ret ok
}
