// Matrix decompositions over column-major f64 data, as R's base functions answer them:
// `qr` (LINPACK dqrdc2, Householder with limited column pivoting: a column whose norm falls
// below `tol` of its original is moved to the end), `lm.fit` through dqrsl (coefficients,
// residuals, effects, rank), `svd` (one-sided Jacobi, singular values descending), `eigen` of a
// general real matrix (Hessenberg reduction, shifted complex QR, eigenvectors from the Schur form;
// values come in the order the iteration deflates them, vectors have unit norm) and `ldlt`
// (L unit lower, D the diagonal, no pivoting).
//
// Signs: a singular or eigen vector is as unique as its definition leaves it, so a caller compares
// absolute values or residuals, as the fixture does. Not here: LAPACK's dgesdd or dgeev code path
// (the values agree to rounding, the order of equal values and the phase of a vector may not),
// complex input, `LAPACK = TRUE` qr, and the balancing dgeev applies.

use e.math
use e.mem

error Singular
error NoConvergence

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn norm2(x: []const f64, from: usize, count: usize) -> f64 {
    // dnrm2: scaled sum of squares
    var scale = 0.0f64
    var ssq = 1.0f64
    var i = 0usize
    while i < count {
        let v = x[from + i]
        if v != 0.0f64 {
            let a = abs_of(v)
            if scale < a {
                ssq = 1.0f64 + ssq * (scale / a) * (scale / a)
                scale = a
            } else {
                ssq = ssq + (a / scale) * (a / scale)
            }
        }
        i += 1usize
    }
    ret scale * math.sqrt[f64](ssq)
}

type Qr = struct { qr: []f64, qraux: []f64, pivot: []usize, rank: usize, n: usize, p: usize }

// qr(x, tol, LAPACK = FALSE): x is n by p; pivot is 0-based.
fn qr(a: *mem.Arena, x: []const f64, n: usize, p: usize, tol: f64) -> (Qr, err) {
    var empty: Qr = zero
    let (q, qe) = mem.alloc[f64](a, n * p + 1usize)
    let (qraux, ae) = mem.alloc[f64](a, p + 1usize)
    let (jpvt, je) = mem.alloc[usize](a, p + 1usize)
    let (w1, w1e) = mem.alloc[f64](a, p + 1usize)
    let (w2, w2e) = mem.alloc[f64](a, p + 1usize)
    if qe != ok { ret (empty, qe) }
    if ae != ok { ret (empty, ae) }
    if je != ok { ret (empty, je) }
    if w1e != ok { ret (empty, w1e) }
    if w2e != ok { ret (empty, w2e) }
    var i = 0usize
    while i < n * p {
        q[i] = x[i]
        i += 1usize
    }
    var j = 0usize
    while j < p {
        jpvt[j] = j
        qraux[j] = norm2(q, j * n, n)
        w1[j] = qraux[j]
        w2[j] = qraux[j]
        if w2[j] == 0.0f64 { w2[j] = 1.0f64 }
        j += 1usize
    }
    var lup = n
    if p < lup { lup = p }
    var k = p + 1usize
    var l = 0usize
    var stop = false
    while l < lup && !stop {
        // cycle the columns from l to p until one with a non-negligible norm is found
        while l + 1usize < k && qraux[l] < w2[l] * tol {
            let lp1 = l + 1usize
            var r = 0usize
            while r < n {
                let t = q[l * n + r]
                var c = lp1
                while c < p {
                    q[(c - 1usize) * n + r] = q[c * n + r]
                    c += 1usize
                }
                q[(p - 1usize) * n + r] = t
                r += 1usize
            }
            let ii = jpvt[l]
            let t = qraux[l]
            let tt = w1[l]
            let ttt = w2[l]
            var c = lp1
            while c < p {
                jpvt[c - 1usize] = jpvt[c]
                qraux[c - 1usize] = qraux[c]
                w1[c - 1usize] = w1[c]
                w2[c - 1usize] = w2[c]
                c += 1usize
            }
            jpvt[p - 1usize] = ii
            qraux[p - 1usize] = t
            w1[p - 1usize] = tt
            w2[p - 1usize] = ttt
            k -= 1usize
        }
        if l + 1usize == n {
            stop = true
        } else {
            // Householder transformation for column l
            var nrmxl = norm2(q, l * n + l, n - l)
            if nrmxl != 0.0f64 {
                if q[l * n + l] != 0.0f64 {
                    if q[l * n + l] < 0.0f64 { nrmxl = 0.0f64 - abs_of(nrmxl) } else { nrmxl = abs_of(nrmxl) }
                }
                let inv = 1.0f64 / nrmxl
                var r = l
                while r < n {
                    q[l * n + r] = q[l * n + r] * inv
                    r += 1usize
                }
                q[l * n + l] = 1.0f64 + q[l * n + l]
                // apply to the remaining columns, updating the norms
                var c = l + 1usize
                while c < p {
                    var dot = 0.0f64
                    r = l
                    while r < n {
                        dot = dot + q[l * n + r] * q[c * n + r]
                        r += 1usize
                    }
                    let t = 0.0f64 - dot / q[l * n + l]
                    r = l
                    while r < n {
                        q[c * n + r] = q[c * n + r] + t * q[l * n + r]
                        r += 1usize
                    }
                    if qraux[c] != 0.0f64 {
                        var tt = 1.0f64 - (abs_of(q[c * n + l]) / qraux[c]) * (abs_of(q[c * n + l]) / qraux[c])
                        if tt < 0.0f64 { tt = 0.0f64 }
                        let t2 = tt
                        if abs_of(t2) < 0.000001f64 {
                            qraux[c] = norm2(q, c * n + l + 1usize, n - l - 1usize)
                            w1[c] = qraux[c]
                        } else {
                            qraux[c] = qraux[c] * math.sqrt[f64](t2)
                        }
                    }
                    c += 1usize
                }
                qraux[l] = q[l * n + l]
                q[l * n + l] = 0.0f64 - nrmxl
            }
            l += 1usize
        }
    }
    var rank = k - 1usize
    if n < rank { rank = n }
    ret (Qr { qr: q, qraux: qraux, pivot: jpvt, rank: rank, n: n, p: p }, ok)
}

// dqrsl: y becomes Q'y (the first `rank` Householder transformations).
fn qr_qty(f: *const Qr, y: []f64) {
    let n = f.n
    var ju = f.rank
    if n - 1usize < ju { ju = n - 1usize }
    var j = 0usize
    while j < ju {
        if f.qraux[j] != 0.0f64 {
            let temp = f.qr[j * n + j]
            // x(j,j) = qraux(j)
            var dot = f.qraux[j] * y[j]
            var i = j + 1usize
            while i < n {
                dot = dot + f.qr[j * n + i] * y[i]
                i += 1usize
            }
            let t = 0.0f64 - dot / f.qraux[j]
            y[j] = y[j] + t * f.qraux[j]
            i = j + 1usize
            while i < n {
                y[i] = y[i] + t * f.qr[j * n + i]
                i += 1usize
            }
            let _ = temp
        }
        j += 1usize
    }
}

// y becomes Qy.
fn qr_qy(f: *const Qr, y: []f64) {
    let n = f.n
    var ju = f.rank
    if n - 1usize < ju { ju = n - 1usize }
    var jj = ju
    while jj > 0usize {
        jj -= 1usize
        let j = jj
        if f.qraux[j] != 0.0f64 {
            var dot = f.qraux[j] * y[j]
            var i = j + 1usize
            while i < n {
                dot = dot + f.qr[j * n + i] * y[i]
                i += 1usize
            }
            let t = 0.0f64 - dot / f.qraux[j]
            y[j] = y[j] + t * f.qraux[j]
            i = j + 1usize
            while i < n {
                y[i] = y[i] + t * f.qr[j * n + i]
                i += 1usize
            }
        }
    }
}

type Fit = struct { coef: []f64, residuals: []f64, effects: []f64, rank: usize, pivot: []usize }

// lm.fit(x, y): coefficients in the original column order, NaN for the aliased ones.
fn lm_fit(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, tol: f64) -> (Fit, err) {
    var empty: Fit = zero
    let (f, qe) = qr(a, x, n, p, tol)
    if qe != ok { ret (empty, qe) }
    let (qty, ye) = mem.alloc[f64](a, n + 1usize)
    let (coef, ce) = mem.alloc[f64](a, p + 1usize)
    let (res, re) = mem.alloc[f64](a, n + 1usize)
    let (b, be) = mem.alloc[f64](a, p + 1usize)
    if ye != ok { ret (empty, ye) }
    if ce != ok { ret (empty, ce) }
    if re != ok { ret (empty, re) }
    if be != ok { ret (empty, be) }
    var i = 0usize
    while i < n {
        qty[i] = y[i]
        i += 1usize
    }
    qr_qty(&f, qty)
    let k = f.rank
    // back substitution R b = qty[0..k]
    var jj = k
    while jj > 0usize {
        jj -= 1usize
        var s = qty[jj]
        var c = jj + 1usize
        while c < k {
            s = s - f.qr[c * n + jj] * b[c]
            c += 1usize
        }
        b[jj] = s / f.qr[jj * n + jj]
    }
    i = 0usize
    while i < p {
        coef[i] = nan()
        i += 1usize
    }
    i = 0usize
    while i < k {
        coef[f.pivot[i]] = b[i]
        i += 1usize
    }
    // residuals: Q [0; qty[k..n]]
    i = 0usize
    while i < n {
        if i < k { res[i] = 0.0f64 } else { res[i] = qty[i] }
        i += 1usize
    }
    qr_qy(&f, res)
    ret (Fit { coef: coef[0usize..p], residuals: res[0usize..n], effects: qty[0usize..n], rank: k, pivot: f.pivot }, ok)
}

// --- svd (one-sided Jacobi)

type Svd = struct { d: []f64, u: []f64, v: []f64, m: usize, n: usize, k: usize }

fn jacobi_svd(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> (Svd, err) {
    // m >= n: the columns of a work copy are rotated until orthogonal
    var empty: Svd = zero
    let (w, we) = mem.alloc[f64](a, m * n + 1usize)
    let (v, ve) = mem.alloc[f64](a, n * n + 1usize)
    if we != ok { ret (empty, we) }
    if ve != ok { ret (empty, ve) }
    var i = 0usize
    while i < m * n {
        w[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        v[i * n + i] = 1.0f64
        i += 1usize
    }
    var sweep = 0usize
    var rotated = true
    while rotated && sweep < 80usize {
        rotated = false
        var p = 0usize
        while p + 1usize < n {
            var q = p + 1usize
            while q < n {
                var alpha = 0.0f64
                var beta = 0.0f64
                var gamma = 0.0f64
                var r = 0usize
                while r < m {
                    alpha = alpha + w[p * m + r] * w[p * m + r]
                    beta = beta + w[q * m + r] * w[q * m + r]
                    gamma = gamma + w[p * m + r] * w[q * m + r]
                    r += 1usize
                }
                if gamma != 0.0f64 && abs_of(gamma) > 0.0000000000000002f64 * math.sqrt[f64](alpha * beta) {
                    rotated = true
                    let zeta = (beta - alpha) / (2.0f64 * gamma)
                    var t = 1.0f64 / (abs_of(zeta) + math.sqrt[f64](1.0f64 + zeta * zeta))
                    if zeta < 0.0f64 { t = 0.0f64 - t }
                    let c = 1.0f64 / math.sqrt[f64](1.0f64 + t * t)
                    let s = c * t
                    r = 0usize
                    while r < m {
                        let wp = w[p * m + r]
                        let wq = w[q * m + r]
                        w[p * m + r] = c * wp - s * wq
                        w[q * m + r] = s * wp + c * wq
                        r += 1usize
                    }
                    r = 0usize
                    while r < n {
                        let vp = v[p * n + r]
                        let vq = v[q * n + r]
                        v[p * n + r] = c * vp - s * vq
                        v[q * n + r] = s * vp + c * vq
                        r += 1usize
                    }
                }
                q += 1usize
            }
            p += 1usize
        }
        sweep += 1usize
    }
    if rotated { ret (empty, NoConvergence) }
    let (d, de) = mem.alloc[f64](a, n + 1usize)
    let (order, oe) = mem.alloc[usize](a, n + 1usize)
    if de != ok { ret (empty, de) }
    if oe != ok { ret (empty, oe) }
    var j = 0usize
    while j < n {
        d[j] = norm2(w, j * m, m)
        j += 1usize
    }
    j = 0usize
    while j < n {
        var q = j
        while q > 0usize && d[order[q - 1usize]] < d[j] {
            order[q] = order[q - 1usize]
            q -= 1usize
        }
        order[q] = j
        j += 1usize
    }
    let (ds, dse) = mem.alloc[f64](a, n + 1usize)
    let (us, use2) = mem.alloc[f64](a, m * n + 1usize)
    let (vs, vse) = mem.alloc[f64](a, n * n + 1usize)
    if dse != ok { ret (empty, dse) }
    if use2 != ok { ret (empty, use2) }
    if vse != ok { ret (empty, vse) }
    j = 0usize
    while j < n {
        let src = order[j]
        ds[j] = d[src]
        var r = 0usize
        while r < m {
            if d[src] > 0.0f64 { us[j * m + r] = w[src * m + r] / d[src] } else { us[j * m + r] = 0.0f64 }
            r += 1usize
        }
        r = 0usize
        while r < n {
            vs[j * n + r] = v[src * n + r]
            r += 1usize
        }
        j += 1usize
    }
    ret (Svd { d: ds[0usize..n], u: us[0usize..m * n], v: vs[0usize..n * n], m: m, n: n, k: n }, ok)
}

// svd(x): d, u (m by k) and v (n by k) with k = min(m, n).
fn svd(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> (Svd, err) {
    if m >= n {
        let (r, e) = jacobi_svd(a, x, m, n)
        ret (r, e)
    }
    let (t, te) = mem.alloc[f64](a, m * n + 1usize)
    var empty: Svd = zero
    if te != ok { ret (empty, te) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            t[i * n + j] = x[j * m + i]
            j += 1usize
        }
        i += 1usize
    }
    let (r, e) = jacobi_svd(a, t[0usize..m * n], n, m)
    if e != ok { ret (empty, e) }
    ret (Svd { d: r.d, u: r.v, v: r.u, m: m, n: n, k: m }, ok)
}

// --- ldlt

type Ldlt = struct { l: []f64, d: []f64 }

// A = L D L' for a symmetric matrix whose leading minors are non-zero; only the lower triangle is read.
fn ldlt(a: *mem.Arena, x: []const f64, n: usize) -> (Ldlt, err) {
    var empty: Ldlt = zero
    let (l, le) = mem.alloc[f64](a, n * n + 1usize)
    let (d, de) = mem.alloc[f64](a, n + 1usize)
    if le != ok { ret (empty, le) }
    if de != ok { ret (empty, de) }
    var i = 0usize
    while i < n * n {
        l[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < n {
        var dj = x[j * n + j]
        var k = 0usize
        while k < j {
            dj = dj - l[k * n + j] * l[k * n + j] * d[k]
            k += 1usize
        }
        if dj == 0.0f64 { ret (empty, Singular) }
        d[j] = dj
        l[j * n + j] = 1.0f64
        i = j + 1usize
        while i < n {
            var s = x[j * n + i]
            k = 0usize
            while k < j {
                s = s - l[k * n + i] * l[k * n + j] * d[k]
                k += 1usize
            }
            l[j * n + i] = s / dj
            i += 1usize
        }
        j += 1usize
    }
    ret (Ldlt { l: l[0usize..n * n], d: d[0usize..n] }, ok)
}

// --- eigen of a general real matrix

type Eigen = struct { re: []f64, im: []f64, vre: []f64, vim: []f64, n: usize }

fn cabs(re: f64, im: f64) -> f64 {
    let a = abs_of(re)
    let b = abs_of(im)
    if a == 0.0f64 { ret b }
    if b == 0.0f64 { ret a }
    if a > b {
        let r = b / a
        ret a * math.sqrt[f64](1.0f64 + r * r)
    }
    let r = a / b
    ret b * math.sqrt[f64](1.0f64 + r * r)
}

// (ar + i ai) / (br + i bi)
fn cdiv(ar: f64, ai: f64, br: f64, bi: f64) -> (f64, f64) {
    if abs_of(br) >= abs_of(bi) {
        let r = bi / br
        let den = br + bi * r
        ret ((ar + ai * r) / den, (ai - ar * r) / den)
    }
    let r = br / bi
    let den = bi + br * r
    ret ((ar * r + ai) / den, (ai * r - ar) / den)
}

fn csqrt(re: f64, im: f64) -> (f64, f64) {
    let m = cabs(re, im)
    if m == 0.0f64 { ret (0.0f64, 0.0f64) }
    var sr = math.sqrt[f64]((m + abs_of(re)) / 2.0f64)
    var si = im / (2.0f64 * sr)
    if re < 0.0f64 {
        let t = sr
        sr = abs_of(si)
        si = t
        if im < 0.0f64 { si = 0.0f64 - si }
    }
    ret (sr, si)
}

// eigen(x, only.values = FALSE) for a general real n by n matrix, by the complex Schur form.
fn eigen(a: *mem.Arena, x: []const f64, n: usize) -> (Eigen, err) {
    var empty: Eigen = zero
    let (hr, hre) = mem.alloc[f64](a, n * n + 1usize)
    let (hi, hie) = mem.alloc[f64](a, n * n + 1usize)
    let (zr, zre) = mem.alloc[f64](a, n * n + 1usize)
    let (zi, zie) = mem.alloc[f64](a, n * n + 1usize)
    if hre != ok { ret (empty, hre) }
    if hie != ok { ret (empty, hie) }
    if zre != ok { ret (empty, zre) }
    if zie != ok { ret (empty, zie) }
    var i = 0usize
    while i < n * n {
        hr[i] = x[i]
        hi[i] = 0.0f64
        zr[i] = 0.0f64
        zi[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        zr[i * n + i] = 1.0f64
        i += 1usize
    }
    // Hessenberg reduction by real Householder reflections, accumulated in Z
    var k = 0usize
    while k + 2usize < n {
        var alpha = 0.0f64
        var r = k + 1usize
        while r < n {
            alpha = alpha + hr[k * n + r] * hr[k * n + r]
            r += 1usize
        }
        alpha = math.sqrt[f64](alpha)
        if alpha != 0.0f64 && !(alpha == abs_of(hr[k * n + k + 1usize]) && k + 2usize >= n) {
            if hr[k * n + k + 1usize] > 0.0f64 { alpha = 0.0f64 - alpha }
            let (vv, vve) = mem.alloc[f64](a, n + 1usize)
            if vve != ok { ret (empty, vve) }
            r = 0usize
            while r < n {
                vv[r] = 0.0f64
                r += 1usize
            }
            r = k + 1usize
            while r < n {
                vv[r] = hr[k * n + r]
                r += 1usize
            }
            vv[k + 1usize] = vv[k + 1usize] - alpha
            var vn = 0.0f64
            r = k + 1usize
            while r < n {
                vn = vn + vv[r] * vv[r]
                r += 1usize
            }
            if vn != 0.0f64 {
                // H = (I - 2 v v'/vn) H (I - 2 v v'/vn)
                var c = 0usize
                while c < n {
                    var dot = 0.0f64
                    r = k + 1usize
                    while r < n {
                        dot = dot + vv[r] * hr[c * n + r]
                        r += 1usize
                    }
                    let f = 2.0f64 * dot / vn
                    r = k + 1usize
                    while r < n {
                        hr[c * n + r] = hr[c * n + r] - f * vv[r]
                        r += 1usize
                    }
                    c += 1usize
                }
                r = 0usize
                while r < n {
                    var dot = 0.0f64
                    c = k + 1usize
                    while c < n {
                        dot = dot + hr[c * n + r] * vv[c]
                        c += 1usize
                    }
                    let f = 2.0f64 * dot / vn
                    c = k + 1usize
                    while c < n {
                        hr[c * n + r] = hr[c * n + r] - f * vv[c]
                        c += 1usize
                    }
                    r = r + 1usize
                }
                r = 0usize
                while r < n {
                    var dot = 0.0f64
                    c = k + 1usize
                    while c < n {
                        dot = dot + zr[c * n + r] * vv[c]
                        c += 1usize
                    }
                    let f = 2.0f64 * dot / vn
                    c = k + 1usize
                    while c < n {
                        zr[c * n + r] = zr[c * n + r] - f * vv[c]
                        c += 1usize
                    }
                    r = r + 1usize
                }
            }
        }
        k += 1usize
    }
    // clean below the first subdiagonal
    var c0 = 0usize
    while c0 < n {
        var r0 = c0 + 2usize
        while r0 < n {
            hr[c0 * n + r0] = 0.0f64
            r0 += 1usize
        }
        c0 += 1usize
    }
    // shifted QR iteration on the Hessenberg matrix (complex), deflating from the bottom
    let (cs, cse) = mem.alloc[f64](a, n + 1usize)
    let (sr, sre) = mem.alloc[f64](a, n + 1usize)
    let (si, sie) = mem.alloc[f64](a, n + 1usize)
    if cse != ok { ret (empty, cse) }
    if sre != ok { ret (empty, sre) }
    if sie != ok { ret (empty, sie) }
    var hiend = n
    var iter = 0usize
    var total = 0usize
    while hiend > 0usize {
        let top = hiend - 1usize
        // find the active block [l, top]
        var l = top
        var found = false
        while l > 0usize && !found {
            let s = cabs(hr[(l - 1usize) * n + l - 1usize], hi[(l - 1usize) * n + l - 1usize]) + cabs(hr[l * n + l], hi[l * n + l])
            var sc = s
            if sc == 0.0f64 { sc = 1.0f64 }
            if cabs(hr[(l - 1usize) * n + l], hi[(l - 1usize) * n + l]) < 0.0000000000000002f64 * sc {
                hr[(l - 1usize) * n + l] = 0.0f64
                hi[(l - 1usize) * n + l] = 0.0f64
                found = true
            } else {
                l -= 1usize
            }
        }
        if l == top {
            hiend -= 1usize
            iter = 0usize
        } else {
            iter += 1usize
            total += 1usize
            if total > 100usize * (n + 1usize) { ret (empty, NoConvergence) }
            // Wilkinson shift from the trailing 2 by 2
            let ar = hr[(top - 1usize) * n + top - 1usize]
            let ai = hi[(top - 1usize) * n + top - 1usize]
            let br = hr[top * n + top - 1usize]
            let bi = hi[top * n + top - 1usize]
            let cr = hr[(top - 1usize) * n + top]
            let ci = hi[(top - 1usize) * n + top]
            let dr = hr[top * n + top]
            let di = hi[top * n + top]
            // eigenvalue of [[a, b'],[c', d]] nearest d: tr/2 +- sqrt((a-d)^2/4 + b c)
            let hr2 = (ar - dr) / 2.0f64
            let hi2 = (ai - di) / 2.0f64
            // disc = h^2 + (b)(c) where b is the upper-right (cr, ci) and c the lower-left (br, bi)
            let dsr = hr2 * hr2 - hi2 * hi2 + (cr * br - ci * bi)
            let dsi = 2.0f64 * hr2 * hi2 + (cr * bi + ci * br)
            let (qr2, qi2) = csqrt(dsr, dsi)
            var mur = (ar + dr) / 2.0f64 + qr2
            var mui = (ai + di) / 2.0f64 + qi2
            let mur2 = (ar + dr) / 2.0f64 - qr2
            let mui2 = (ai + di) / 2.0f64 - qi2
            if cabs(mur2 - dr, mui2 - di) < cabs(mur - dr, mui - di) {
                mur = mur2
                mui = mui2
            }
            if iter % 10usize == 9usize {
                let spread = cabs(br, bi) + cabs(cr, ci) + 0.000001f64
                mur = dr + 0.75f64 * spread
                mui = di + 0.37f64 * spread * f64(iter / 10usize + 1usize)
            }
            // H - mu I, QR by Givens, H = RQ + mu I
            var q = l
            while q <= top {
                hr[q * n + q] = hr[q * n + q] - mur
                hi[q * n + q] = hi[q * n + q] - mui
                q += 1usize
            }
            var g = l
            while g < top {
                // rotation zeroing H[g+1, g] against H[g, g]
                let pr = hr[g * n + g]
                let pi2 = hi[g * n + g]
                let qr3 = hr[g * n + g + 1usize]
                let qi3 = hi[g * n + g + 1usize]
                let nr = math.sqrt[f64](pr * pr + pi2 * pi2 + qr3 * qr3 + qi3 * qi3)
                var c = 1.0f64
                var s_r = 0.0f64
                var s_i = 0.0f64
                if nr != 0.0f64 {
                    let ap = cabs(pr, pi2)
                    if ap == 0.0f64 {
                        c = 0.0f64
                        // s = conj(q)/|q|
                        let aq = cabs(qr3, qi3)
                        s_r = qr3 / aq
                        s_i = 0.0f64 - qi3 / aq
                    } else {
                        c = ap / nr
                        // s = (p/|p|) conj(q) / nr
                        let ur = pr / ap
                        let ui = pi2 / ap
                        s_r = (ur * qr3 + ui * qi3) / nr
                        s_i = (ui * qr3 - ur * qi3) / nr
                    }
                }
                cs[g] = c
                sr[g] = s_r
                si[g] = s_i
                // rows g, g+1 across the columns g..n-1: [c s; -conj(s) c]
                var col = g
                while col < n {
                    let xr = hr[col * n + g]
                    let xi = hi[col * n + g]
                    let yr = hr[col * n + g + 1usize]
                    let yi = hi[col * n + g + 1usize]
                    hr[col * n + g] = c * xr + (s_r * yr - s_i * yi)
                    hi[col * n + g] = c * xi + (s_r * yi + s_i * yr)
                    hr[col * n + g + 1usize] = c * yr - (s_r * xr + s_i * xi)
                    hi[col * n + g + 1usize] = c * yi - (s_r * xi - s_i * xr)
                    col += 1usize
                }
                g += 1usize
            }
            // apply the rotations from the right: columns g, g+1 with the conjugate transpose
            g = l
            while g < top {
                let c = cs[g]
                let s_r = sr[g]
                let s_i = si[g]
                var row = 0usize
                var lim = g + 2usize
                if lim > top + 1usize { lim = top + 1usize }
                if lim < n { } else { lim = n }
                // rows above the block also change (the Schur form is full upper triangular)
                while row < lim {
                    let xr = hr[g * n + row]
                    let xi = hi[g * n + row]
                    let yr = hr[(g + 1usize) * n + row]
                    let yi = hi[(g + 1usize) * n + row]
                    // [x y] [c -s; conj(s)... ] : new x = c x + conj(s) y, new y = c y - s x
                    hr[g * n + row] = c * xr + (s_r * yr + s_i * yi)
                    hi[g * n + row] = c * xi + (s_r * yi - s_i * yr)
                    hr[(g + 1usize) * n + row] = c * yr - (s_r * xr - s_i * xi)
                    hi[(g + 1usize) * n + row] = c * yi - (s_r * xi + s_i * xr)
                    row += 1usize
                }
                row = 0usize
                while row < n {
                    let xr = zr[g * n + row]
                    let xi = zi[g * n + row]
                    let yr = zr[(g + 1usize) * n + row]
                    let yi = zi[(g + 1usize) * n + row]
                    zr[g * n + row] = c * xr + (s_r * yr + s_i * yi)
                    zi[g * n + row] = c * xi + (s_r * yi - s_i * yr)
                    zr[(g + 1usize) * n + row] = c * yr - (s_r * xr - s_i * xi)
                    zi[(g + 1usize) * n + row] = c * yi - (s_r * xi + s_i * xr)
                    row += 1usize
                }
                g += 1usize
            }
            q = l
            while q <= top {
                hr[q * n + q] = hr[q * n + q] + mur
                hi[q * n + q] = hi[q * n + q] + mui
                q += 1usize
            }
        }
    }
    // eigenvalues: the diagonal of the triangular T
    let (er, ere) = mem.alloc[f64](a, n + 1usize)
    let (ei, eie) = mem.alloc[f64](a, n + 1usize)
    let (vr, vre) = mem.alloc[f64](a, n * n + 1usize)
    let (vi, vie) = mem.alloc[f64](a, n * n + 1usize)
    let (yr, yre) = mem.alloc[f64](a, n + 1usize)
    let (yi, yie) = mem.alloc[f64](a, n + 1usize)
    if ere != ok { ret (empty, ere) }
    if eie != ok { ret (empty, eie) }
    if vre != ok { ret (empty, vre) }
    if vie != ok { ret (empty, vie) }
    if yre != ok { ret (empty, yre) }
    if yie != ok { ret (empty, yie) }
    var norm_t = 0.0f64
    var jj = 0usize
    while jj < n {
        er[jj] = hr[jj * n + jj]
        ei[jj] = hi[jj * n + jj]
        var rr = 0usize
        while rr <= jj {
            let v = cabs(hr[jj * n + rr], hi[jj * n + rr])
            if v > norm_t { norm_t = v }
            rr += 1usize
        }
        jj += 1usize
    }
    var small = 0.0000000000000002f64 * norm_t
    if small == 0.0f64 { small = 0.0000000000000002f64 }
    var kk = 0usize
    while kk < n {
        var t = 0usize
        while t < n {
            yr[t] = 0.0f64
            yi[t] = 0.0f64
            t += 1usize
        }
        yr[kk] = 1.0f64
        var ii = kk
        while ii > 0usize {
            ii -= 1usize
            var sr2 = 0.0f64
            var si2 = 0.0f64
            var j2 = ii + 1usize
            while j2 <= kk {
                let tr = hr[j2 * n + ii]
                let ti = hi[j2 * n + ii]
                sr2 = sr2 + (tr * yr[j2] - ti * yi[j2])
                si2 = si2 + (tr * yi[j2] + ti * yr[j2])
                j2 += 1usize
            }
            var dr2 = hr[ii * n + ii] - er[kk]
            var di2 = hi[ii * n + ii] - ei[kk]
            if cabs(dr2, di2) < small {
                dr2 = small
                di2 = 0.0f64
            }
            let (qr4, qi4) = cdiv(0.0f64 - sr2, 0.0f64 - si2, dr2, di2)
            yr[ii] = qr4
            yi[ii] = qi4
        }
        // v = Z y, normalised
        var rr = 0usize
        var nrm = 0.0f64
        while rr < n {
            var sre2 = 0.0f64
            var sie2 = 0.0f64
            var cc = 0usize
            while cc <= kk {
                sre2 = sre2 + (zr[cc * n + rr] * yr[cc] - zi[cc * n + rr] * yi[cc])
                sie2 = sie2 + (zr[cc * n + rr] * yi[cc] + zi[cc * n + rr] * yr[cc])
                cc += 1usize
            }
            vr[kk * n + rr] = sre2
            vi[kk * n + rr] = sie2
            nrm = nrm + sre2 * sre2 + sie2 * sie2
            rr += 1usize
        }
        nrm = math.sqrt[f64](nrm)
        rr = 0usize
        while rr < n {
            if nrm != 0.0f64 {
                vr[kk * n + rr] = vr[kk * n + rr] / nrm
                vi[kk * n + rr] = vi[kk * n + rr] / nrm
            }
            rr += 1usize
        }
        kk += 1usize
    }
    ret (Eigen { re: er[0usize..n], im: ei[0usize..n], vre: vr[0usize..n * n], vim: vi[0usize..n * n], n: n }, ok)
}
