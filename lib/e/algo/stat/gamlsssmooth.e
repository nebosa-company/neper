// R gamlss smoothers for the additive fit of e.algo.stat.gamlssfit: pb() (P-splines, gamlss.pb) with the ML estimate of lambda, a fixed lambda, or a fixed extra df.
// pb follows pb.R of gamlss 5.5-5: the truncated-power B-spline basis, the QR of the weighted basis, the SVD of the penalised triangle and the uniroot search on log(lambda).

use e.algo.linalg.decomp as dc
use e.algo.linalg.lapack_base as lb
use e.algo.linalg.lapack_gesdd as gs
use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.loessfit as lf
use e.algo.stat.smspline as sps
use e.algo.stat.gbmfit as gb
use e.math
use e.math.nmath as nm
use e.mem

error BadSmooth

// one smoother term: kind 1 pb. b is the n by p basis, d the nd by p penalty (both column-major), start the lambda the ML iteration starts from
type Smo = struct {
    kind: usize,
    n: usize,
    p: usize,
    nd: usize,
    order: usize,
    b: []f64,
    d: []f64,
    df: f64,
    lam: f64,
    start: f64,
    meth: usize,
    kk: f64,
}

type Pbr = struct { beta: []f64, edf: f64 }

// dqrdc2 of decomp.e with the Blue dnrm2 of the LAPACK 3.12 BLAS that R 4.6 bundles
fn qr_blue(a: *mem.Arena, x: []const f64, n: usize, p: usize, tol: f64) -> (dc.Qr, err) {
    var empty: dc.Qr = zero
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
        qraux[j] = lb.dnrm2(i64(n), q[j * n..], 1i64)
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
            var nrmxl = lb.dnrm2(i64(n - l), q[l * n + l..], 1i64)
            if nrmxl != 0.0f64 {
                if q[l * n + l] != 0.0f64 {
                    if q[l * n + l] < 0.0f64 { nrmxl = 0.0f64 - math.abs[f64](nrmxl) } else { nrmxl = math.abs[f64](nrmxl) }
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
                        var tt = 1.0f64 - (math.abs[f64](q[c * n + l]) / qraux[c]) * (math.abs[f64](q[c * n + l]) / qraux[c])
                        if tt < 0.0f64 { tt = 0.0f64 }
                        let t2 = tt
                        if math.abs[f64](t2) < 0.000001f64 {
                            qraux[c] = lb.dnrm2(i64(n - l - 1usize), q[c * n + l + 1usize..], 1i64)
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
    ret (dc.Qr { qr: q, qraux: qraux, pivot: jpvt, rank: rank, n: n, p: p }, ok)
}


fn eps() -> f64 { ret 2.220446049250313e-16f64 }

fn fpow(b: f64, e: usize) -> f64 {
    if e == 2usize { ret b * b }
    if e == 3usize { ret b * b * b }
    ret math.pow[f64](b, f64(e))
}

fn binom(n: usize, k: usize) -> f64 {
    var r = 1.0f64
    var i = 1usize
    while i <= k {
        r = r * f64(n + 1usize - i) / f64(i)
        i += 1usize
    }
    ret r
}

// pb(x, df, lambda, control = pb.control(inter, degree, order, start, method, k)): the basis and penalty; df and lam are negative when not given
fn pb_build(a: *mem.Arena, x: []const f64, inter0: usize, deg: usize, order: usize, df0: f64, lam: f64, start: f64, meth: usize, kk: f64) -> (Smo, err) {
    var t: Smo = zero
    let n = x.len
    var inter = inter0
    if n < 99usize { inter = 10usize }
    // the number of distinct values
    var nd_vals = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < i {
            if x[j] == x[i] { seen = true }
            j += 1usize
        }
        if !seen { nd_vals += 1usize }
        i += 1usize
    }
    if nd_vals <= inter { inter = nd_vals }
    var xl = x[0usize]
    var xr = x[0usize]
    i = 1usize
    while i < n {
        if x[i] < xl { xl = x[i] }
        if x[i] > xr { xr = x[i] }
        i += 1usize
    }
    let xmax = xr + 0.01f64 * (xr - xl)
    let xmin = xl - 0.01f64 * (xr - xl)
    let dx = (xmax - xmin) / f64(inter)
    let nk = inter + 2usize * deg + 1usize
    let (knots, e1) = mem.alloc[f64](a, nk)
    if e1 != ok { ret (t, e1) }
    let from = xmin - f64(deg) * dx
    let to = xmax + f64(deg) * dx
    var j = 0usize
    while j < nk {
        var kv = from + f64(j) * dx
        if kv > to { kv = to }
        knots[j] = kv
        j += 1usize
    }
    let p = nk - (deg + 1usize)
    let (bm, e2) = mem.alloc[f64](a, n * p)
    if e2 != ok { ret (t, e2) }
    var gam = 1.0f64
    var g = 2usize
    while g <= deg {
        gam = gam * f64(g)
        g += 1usize
    }
    let den = gam * fpow(dx, deg)
    var sgn = 1.0f64
    if (deg + 1usize) % 2usize == 1usize { sgn = 0.0f64 - 1.0f64 }
    j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            var acc = 0.0f64
            var m = 0usize
            while m <= deg + 1usize {
                let tj = knots[j + m]
                var pv = 0.0f64
                if x[i] > tj { pv = fpow(x[i] - tj, deg) }
                var cm = binom(deg + 1usize, m)
                if (deg + 1usize - m) % 2usize == 1usize { cm = 0.0f64 - cm }
                let dv = cm / den
                if dv != 0.0f64 { acc += pv * dv }
                m += 1usize
            }
            bm[j * n + i] = sgn * acc
            i += 1usize
        }
        j += 1usize
    }
    let ndr = p - order
    let (dm, e3) = mem.alloc[f64](a, ndr * p + 1usize)
    if e3 != ok { ret (t, e3) }
    var k = 0usize
    while k < ndr * p {
        dm[k] = 0.0f64
        k += 1usize
    }
    var r = 0usize
    while r < ndr {
        var m = 0usize
        while m <= order {
            var cm = binom(order, m)
            if (order - m) % 2usize == 1usize { cm = 0.0f64 - cm }
            dm[(r + m) * ndr + r] = cm
            m += 1usize
        }
        r += 1usize
    }
    var df = df0
    if df0 > -0.5f64 {
        // the extra degrees of freedom: more than ncol - 2 are replaced by 3, then 2 is added
        if df > f64(p) - 2.0f64 { df = 3.0f64 }
        if df < 0.0f64 { df = 2.0f64 } else { df = df + 2.0f64 }
    } else {
        df = 0.0f64 - 1.0f64
    }
    t = Smo { kind: 1usize, n: n, p: p, nd: ndr, order: order, b: bm, d: dm, df: df, lam: lam, start: start, meth: meth, kk: kk }
    ret (t, ok)
}

// regpen: the penalised fit for lambda from the QR triangle r (p by p, column-major) and Qy
fn regpen(a: *mem.Arena, t: *const Smo, r: []const f64, qy: []const f64, lambda: f64) -> (Pbr, err) {
    let p = t.p
    let nd = t.nd
    let nr = p + nd
    var out: Pbr = zero
    let (rd, e1) = mem.alloc[f64](a, nr * p)
    let (s, e2) = mem.alloc[f64](a, p)
    let (u, e3) = mem.alloc[f64](a, nr * p)
    let (vt, e4) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (out, mem.Full) }
    let sl = math.sqrt[f64](lambda)
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            rd[j * nr + i] = r[j * p + i]
            i += 1usize
        }
        i = 0usize
        while i < nd {
            rd[j * nr + p + i] = sl * t.d[j * nd + i]
            i += 1usize
        }
        j += 1usize
    }
    let se = gs.svd_all(a, rd, nr, p, s, u, vt)
    if se != ok { ret (out, se) }
    let thr = s[0usize] * math.pow[f64](eps(), 0.8f64)
    var rank = 0usize
    j = 0usize
    while j < p {
        if s[j] > thr { rank += 1usize }
        j += 1usize
    }
    let (beta, e5) = mem.alloc[f64](a, p)
    var edf = 0.0f64
    var rr = 0usize
    j = 0usize
    while j < p {
        beta[j] = 0.0f64
        j += 1usize
    }
    while rr < rank {
        var y1 = 0.0f64
        var i = 0usize
        while i < p {
            y1 += u[rr * nr + i] * qy[i]
            edf += u[rr * nr + i] * u[rr * nr + i]
            i += 1usize
        }
        let c = y1 / s[rr]
        j = 0usize
        while j < p {
            beta[j] += vt[rr + j * p] * c
            j += 1usize
        }
        rr += 1usize
    }
    if e5 != ok { ret (out, e5) }
    out = Pbr { beta: beta, edf: edf }
    ret (out, ok)
}

// R_zeroin2 on f(ll) = sum(1 / (1 + exp(ll) * ev)) - tgt
fn edfm(ev: []const f64, tgt: f64, ll: f64) -> f64 {
    let lam = math.exp[f64](ll)
    var s = 0.0f64
    var i = 0usize
    while i < ev.len {
        s += 1.0f64 / (1.0f64 + lam * ev[i])
        i += 1usize
    }
    ret s - tgt
}

fn zeroin(ev: []const f64, tgt: f64, lower: f64, upper: f64, tol: f64, maxit: i64) -> f64 {
    var a = lower
    var b = upper
    var c = a
    var fa = edfm(ev, tgt, a)
    var fb = edfm(ev, tgt, b)
    var fc = fa
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    var left = maxit + 1i64
    while left > 0i64 {
        left -= 1i64
        let prev = b - a
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps() * math.abs[f64](b) + tol / 2.0f64
        var step = (c - b) / 2.0f64
        if math.abs[f64](step) <= tol_act || fb == 0.0f64 { ret b }
        if math.abs[f64](prev) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = c - b
            var pp = 0.0f64
            var qq = 0.0f64
            if a == c {
                let t1 = fb / fa
                pp = cb * t1
                qq = 1.0f64 - t1
            } else {
                qq = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                pp = t2 * (cb * qq * (qq - t1) - (b - a) * (t1 - 1.0f64))
                qq = (qq - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if pp > 0.0f64 { qq = 0.0f64 - qq } else { pp = 0.0f64 - pp }
            if pp < (0.75f64 * cb * qq - math.abs[f64](tol_act * qq) / 2.0f64) && pp < math.abs[f64](prev * qq / 2.0f64) { step = pp / qq }
        }
        if math.abs[f64](step) < tol_act {
            if step > 0.0f64 { step = tol_act } else { step = 0.0f64 - tol_act }
        }
        a = b
        fa = fb
        b += step
        fb = edfm(ev, tgt, b)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret b
}

// the eigenvalues of t(Rinv) %*% t(D) %*% D %*% Rinv
fn eig_rsr(a: *mem.Arena, t: *const Smo, r: []const f64, ev: []f64) -> err {
    let p = t.p
    let nd = t.nd
    let (rinv, e1) = mem.alloc[f64](a, p * p)
    let (sm, e2) = mem.alloc[f64](a, p * p)
    let (tm, e3) = mem.alloc[f64](a, p * p)
    let (mm, e4) = mem.alloc[f64](a, p * p)
    let (z, e5) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    // solve(R): dgetrs on the identity, the column-oriented dtrsm of the reference BLAS (U = R exactly: no row exchange, unit lower factor)
    var c = 0usize
    while c < p {
        var i0 = 0usize
        while i0 < p {
            rinv[c * p + i0] = 0.0f64
            if i0 == c { rinv[c * p + i0] = 1.0f64 }
            i0 += 1usize
        }
        var k = p
        while k > 0usize {
            k -= 1usize
            if rinv[c * p + k] != 0.0f64 {
                rinv[c * p + k] = rinv[c * p + k] / r[k * p + k]
                var i = 0usize
                while i < k {
                    rinv[c * p + i] = rinv[c * p + i] - rinv[c * p + k] * r[k * p + i]
                    i += 1usize
                }
            }
        }
        c += 1usize
    }
    // S = t(D) %*% D
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < nd {
                s += t.d[i * nd + k] * t.d[j * nd + k]
                k += 1usize
            }
            sm[j * p + i] = s
            j += 1usize
        }
        i += 1usize
    }
    // (t(Rinv) %*% S) %*% Rinv, each product accumulated over the inner index in order as the reference dgemm does
    var j = 0usize
    while j < p {
        i = 0usize
        while i < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += rinv[i * p + k] * sm[j * p + k]
                k += 1usize
            }
            tm[j * p + i] = s
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        i = 0usize
        while i < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += tm[k * p + i] * rinv[j * p + k]
                k += 1usize
            }
            mm[j * p + i] = s
            i += 1usize
        }
        j += 1usize
    }
    // eigen(symmetric = TRUE, only.values = TRUE): dsyevr with jobz N, uplo L, abstol 0
    let nn = i64(p)
    let (isuppz, e6) = mem.alloc[i64](a, 2usize * p)
    if e6 != ok { ret mem.Full }
    var m = 0i64
    var info = 0i64
    var wk: [1]f64 = zero
    var iwk: [1]i64 = zero
    sy.dsyevr("N", "A", "L", nn, mm[0usize..], nn, 0.0f64, 0.0f64, 1i64, 1i64, 0.0f64, &m, ev, z, nn, isuppz[0usize..], wk[0usize..], -1i64, iwk[0usize..], -1i64, &info)
    if info != 0i64 { ret mem.Full }
    let lwork = usize(i64(wk[0usize]))
    let liwork = usize(iwk[0usize])
    let (work, e7) = mem.alloc[f64](a, lwork)
    let (iwork, e8) = mem.alloc[i64](a, liwork)
    if e7 != ok || e8 != ok { ret mem.Full }
    sy.dsyevr("N", "A", "L", nn, mm[0usize..], nn, 0.0f64, 0.0f64, 1i64, 1i64, 0.0f64, &m, ev, z, nn, isuppz[0usize..], work[0usize..], i64(lwork), iwork[0usize..], i64(liwork), &info)
    if info != 0i64 { ret mem.Full }
    ret ok
}

// gamlss.pb(x, y, w): fv gets the fitted smooth, the result is (nl.df, lambda); t.start is the lambda the next call starts from
fn pb_fit(a: *mem.Arena, t: *Smo, y: []const f64, w: []const f64, fv: []f64) -> (f64, f64, err) {
    let n = t.n
    let p = t.p
    let nd = t.nd
    let mark = mem.mark(a)
    let (xw, e1) = mem.alloc[f64](a, n * p)
    let (qyv, e2) = mem.alloc[f64](a, n)
    let (r, e3) = mem.alloc[f64](a, p * p)
    let (qy, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var nn = 0usize
    var i = 0usize
    while i < n {
        let sw = math.sqrt[f64](w[i])
        if w[i] != 0.0f64 { nn += 1usize }
        qyv[i] = sw * y[i]
        var j = 0usize
        while j < p {
            xw[j * n + i] = sw * t.b[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    let (qr, qe) = qr_blue(a, xw, n, p, math.pow[f64](eps(), 0.8f64))
    if qe != ok { ret (0.0f64, 0.0f64, qe) }
    if qr.rank < p { ret (0.0f64, 0.0f64, BadSmooth) }
    var j = 0usize
    while j < p {
        i = 0usize
        while i < p {
            r[j * p + i] = 0.0f64
            if i <= j { r[j * p + i] = qr.qr[j * n + i] }
            i += 1usize
        }
        j += 1usize
    }
    dc.qr_qty(&qr, qyv)
    i = 0usize
    while i < p {
        qy[i] = qyv[i]
        i += 1usize
    }
    var lambda = t.start
    var fit: Pbr = zero
    var fe: err = ok
    if t.lam > -0.5f64 || t.df < -0.5f64 {
        if t.lam > -0.5f64 {
            lambda = t.lam
            if t.start >= 1.0e7f64 { lambda = 1.0e7f64 }
            if t.start <= 1.0e-7f64 { lambda = 1.0e-7f64 }
            let (f1, e) = regpen(a, t, r, qy, lambda)
            fit = f1
            fe = e
        } else {
            // method ML
            let order = f64(t.order)
            var it = 0usize
            var brk = false
            while it < 50usize && !brk {
                it += 1usize
                let (f1, e) = regpen(a, t, r, qy, lambda)
                if e != ok { ret (0.0f64, 0.0f64, e) }
                fit = f1
                var ss = 0.0f64
                i = 0usize
                while i < n {
                    var s = 0.0f64
                    j = 0usize
                    while j < p {
                        s += t.b[j * n + i] * fit.beta[j]
                        j += 1usize
                    }
                    ss += w[i] * (y[i] - s) * (y[i] - s)
                    i += 1usize
                }
                var gg = 0.0f64
                i = 0usize
                while i < nd {
                    var s = 0.0f64
                    j = 0usize
                    while j < p {
                        s += t.d[j * nd + i] * fit.beta[j]
                        j += 1usize
                    }
                    gg += s * s
                    i += 1usize
                }
                let sig2 = ss / (f64(nn) - fit.edf)
                var tau2 = gg / (fit.edf - order)
                if tau2 < 1.0e-7f64 { tau2 = 1.0e-7f64 }
                let lold = lambda
                lambda = sig2 / tau2
                if lambda < 1.0e-7f64 { lambda = 1.0e-7f64 }
                if lambda > 1.0e7f64 { lambda = 1.0e7f64 }
                if math.abs[f64](lambda - lold) < 1.0e-7f64 || lambda > 1.0e10f64 { brk = true } else { t.start = lambda }
            }
        }
    } else {
        let (ev, e5) = mem.alloc[f64](a, p)
        if e5 != ok { ret (0.0f64, 0.0f64, e5) }
        let ee = eig_rsr(a, t, r, ev)
        if ee != ok { ret (0.0f64, 0.0f64, ee) }
        let f1 = edfm(ev, t.df, 0.0f64 - 30.0f64)
        let f2 = edfm(ev, t.df, 30.0f64)
        var ll = 30.0f64
        let same = (f1 > 0.0f64 && f2 > 0.0f64) || (f1 < 0.0f64 && f2 < 0.0f64) || (f1 == 0.0f64 && f2 == 0.0f64)
        if !same { ll = zeroin(ev, t.df, 0.0f64 - 30.0f64, 30.0f64, math.pow[f64](eps(), 0.25f64), 1000i64) }
        lambda = math.exp[f64](ll)
        let (f3, e) = regpen(a, t, r, qy, lambda)
        fit = f3
        fe = e
    }
    if fe != ok { ret (0.0f64, 0.0f64, fe) }
    i = 0usize
    while i < n {
        var s = 0.0f64
        j = 0usize
        while j < p {
            s += t.b[j * n + i] * fit.beta[j]
            j += 1usize
        }
        fv[i] = s
        i += 1usize
    }
    let nl = fit.edf - 2.0f64
    mem.reset(a, mark)
    ret (nl, lambda, ok)
}

// one smoother's fit of the working response z with weights w: fv gets the fitted smooth, the result is (nl.df, lambda or span)
fn smo_fit(a: *mem.Arena, t: *Smo, z: []const f64, w: []const f64, fv: []f64) -> (f64, f64, err) {
    if t.kind == 3usize {
        let (nl3, lam3, e3) = lo_fit(a, t, z, w, fv)
        ret (nl3, lam3, e3)
    }
    if t.kind == 2usize {
        let (nl2, lam2, e2) = cs_fit(a, t, z, w, fv)
        ret (nl2, lam2, e2)
    }
    let (nl, lam, e) = pb_fit(a, t, z, w, fv)
    ret (nl, lam, e)
}

// loess(y ~ x, weights = wts, span, degree)$fitted for n rows (cell = 0.2 as the default control)
fn lo_fitted(a: *mem.Arena, x: []const f64, y: []const f64, wts: []const f64, n: usize, span: f64, degree: usize, fitted: []f64) -> err {
    var bad = 0usize
    let w = gb.af(a, n, &bad)
    let idx = gb.au(a, n, &bad)
    let tmp = gb.au(a, n, &bad)
    let xs = gb.af(a, n, &bad)
    let cuts = gb.af(a, n + 2usize, &bad)
    let stl = gb.au(a, 2usize * n + 8usize, &bad)
    let stu = gb.au(a, 2usize * n + 8usize, &bad)
    let stlo = gb.af(a, 2usize * n + 8usize, &bad)
    let sthi = gb.af(a, 2usize * n + 8usize, &bad)
    let vv = gb.af(a, n + 4usize, &bad)
    let g0 = gb.af(a, n + 4usize, &bad)
    let g1 = gb.af(a, n + 4usize, &bad)
    if bad != 0usize { ret gb.NoMemory }
    var i = 0usize
    while i < n {
        w[i] = wts[i]
        idx[i] = i
        i += 1usize
    }
    gb.msort(x, idx, tmp, n)
    i = 0usize
    while i < n {
        xs[i] = x[idx[i]]
        i += 1usize
    }
    var alpha = xs[0usize]
    var beta = xs[n - 1usize]
    var mx = math.abs[f64](alpha)
    if math.abs[f64](beta) > mx { mx = math.abs[f64](beta) }
    var spread = beta - alpha
    let floor_w = 1.0e-10f64 * mx + 1.0e-30f64
    if floor_w > spread { spread = floor_w }
    let mu = 0.005f64 * spread
    alpha = alpha - mu
    beta = beta + mu
    let nf0 = math.floor[f64](f64(n) * span + 1.0e-5f64)
    var nf = usize(nf0)
    if nf > n { nf = n }
    if nf == 0usize { ret gb.NoMemory }
    let fc = usize(math.floor[f64](f64(n) * span * 0.2f64))
    let nc = lf.kd_cuts(xs, n, fc, alpha, beta, cuts, stl, stu, stlo, sthi)
    // the cuts in order make the vertices, the bounds at either end
    var c = 0usize
    while c < nc {
        idx[c] = c
        c += 1usize
    }
    gb.msort(cuts, idx, tmp, nc)
    vv[0usize] = alpha
    c = 0usize
    while c < nc {
        vv[c + 1usize] = cuts[idx[c]]
        c += 1usize
    }
    vv[nc + 1usize] = beta
    let nv = nc + 2usize
    let o2 = gb.af(a, 2usize, &bad)
    if bad != 0usize { ret gb.NoMemory }
    var v = 0usize
    while v < nv {
        let e = lf.local_fit(a, x, y, w, n, nf, span, degree, vv[v], o2)
        if e != ok { ret e }
        g0[v] = o2[0usize]
        g1[v] = o2[1usize]
        v += 1usize
    }
    i = 0usize
    while i < n {
        // the cell holding x[i]: the cuts it lies strictly right of
        var cell = 0usize
        while cell + 1usize < nv - 1usize && x[i] > vv[cell + 1usize] { cell += 1usize }
        let wd = vv[cell + 1usize] - vv[cell]
        let h = (x[i] - vv[cell]) / wd
        let phi0 = (1.0f64 - h) * (1.0f64 - h) * (1.0f64 + 2.0f64 * h)
        let phi1 = h * h * (3.0f64 - 2.0f64 * h)
        let psi0 = h * (1.0f64 - h) * (1.0f64 - h)
        let psi1 = h * h * (h - 1.0f64)
        fitted[i] = phi0 * g0[cell] + phi1 * g0[cell + 1usize] + (psi0 * g1[cell] + psi1 * g1[cell + 1usize]) * wd
        i += 1usize
    }
    ret ok
}


// lo(): loess with the weights of the backfit; nl.df is the trace of the smoother matrix minus one, taken from the fits of the unit vectors
fn lo_fit(a: *mem.Arena, t: *Smo, y: []const f64, w: []const f64, fv: []f64) -> (f64, f64, err) {
    let n = t.n
    let mark = mem.mark(a)
    var span = t.lam
    if t.df > 0.0f64 { span = lf.span_for_enp(t.df, t.order) }
    let (u, e1) = mem.alloc[f64](a, n)
    let (o, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    let e3 = lo_fitted(a, t.b, y, w, n, span, t.order, fv)
    if e3 != ok { ret (0.0f64, 0.0f64, e3) }
    var tr = 0.0f64
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            u[i] = 0.0f64
            i += 1usize
        }
        u[j] = 1.0f64
        let e4 = lo_fitted(a, t.b, u, w, n, span, t.order, o)
        if e4 != ok { ret (0.0f64, 0.0f64, e4) }
        tr += o[j]
        j += 1usize
    }
    mem.reset(a, mark)
    ret (tr - 1.0f64, span, ok)
}

fn lo_build(a: *mem.Arena, x: []const f64, span: f64, degree: usize, df: f64) -> (Smo, err) {
    var t: Smo = zero
    let n = x.len
    let (xb, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (t, e1) }
    var i = 0usize
    while i < n {
        xb[i] = x[i]
        i += 1usize
    }
    t = Smo { kind: 3usize, n: n, p: 1usize, nd: 0usize, order: degree, b: xb, d: xb, df: df, lam: span, start: 0.0f64, meth: 0usize, kk: 0.0f64 }
    ret (t, ok)
}

// cs(): gamlss.cs, smooth.spline of the distinct sorted x (signif 5) with df + 2 effective df (t.df > 0) or the given spar (t.lam); nl.df is the df minus 2, lambda that of the fit
fn cs_fit(a: *mem.Arena, t: *Smo, y: []const f64, w: []const f64, fv: []f64) -> (f64, f64, err) {
    let n = t.n
    let mark = mem.mark(a)
    let (ord, e1) = mem.alloc[usize](a, n)
    let (xs, e2) = mem.alloc[f64](a, n)
    let (ys, e3) = mem.alloc[f64](a, n)
    let (ws, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var k = i
        while k > 0usize && t.b[ord[k - 1usize]] > t.b[v] {
            ord[k] = ord[k - 1usize]
            k -= 1usize
        }
        ord[k] = v
        i += 1usize
    }
    var sw = 0.0f64
    var npos = 0.0f64
    i = 0usize
    while i < n {
        sw += w[i]
        if w[i] > 0.0f64 { npos += 1.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < n {
        xs[i] = t.b[ord[i]]
        ys[i] = y[ord[i]]
        ws[i] = w[ord[i]] * npos / sw
        if i > 0usize && xs[i] == xs[i - 1usize] { ret (0.0f64, 0.0f64, BadSmooth) }
        i += 1usize
    }
    var f: sps.SmSpline = zero
    if t.df > 0.0f64 {
        let spar = cs_search(a, xs, ys, ws, t.df)
        if spar != spar { ret (0.0f64, 0.0f64, BadSmooth) }
        let fe0 = sps.fit(a, xs, ys, ws, spar, &f)
        if fe0 != ok { ret (0.0f64, 0.0f64, fe0) }
    } else {
        let fe = sps.fit(a, xs, ys, ws, t.lam, &f)
        if fe != ok { ret (0.0f64, 0.0f64, fe) }
    }
    i = 0usize
    while i < n {
        fv[i] = sps.predict(a, &f, t.b[i])
        i += 1usize
    }
    let nl = f.df - 2.0f64
    let lam = f.lambda
    mem.reset(a, mark)
    ret (nl, lam, ok)
}

// cs(x, df, spar): df is the extra df of the call (target df + 2) or -1 when spar is given; x is signif(x, 5)
fn cs_build(a: *mem.Arena, x: []const f64, df: f64, spar: f64) -> (Smo, err) {
    var t: Smo = zero
    let n = x.len
    let (xb, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (t, e1) }
    var i = 0usize
    while i < n {
        var v = x[i]
        if v != 0.0f64 {
            // signif(x, 5)
            let e10 = math.floor[f64](math.log10[f64](math.abs[f64](v)))
            let sc = math.pow[f64](10.0f64, 4.0f64 - e10)
            v = nm.rint(v * sc) / sc
        }
        xb[i] = v
        i += 1usize
    }
    var d = df
    if df > 0.0f64 { d = df + 2.0f64 }
    t = Smo { kind: 2usize, n: n, p: 1usize, nd: 0usize, order: 0usize, b: xb, d: xb, df: d, lam: spar, start: 0.0f64, meth: 0usize, kk: 0.0f64 }
    ret (t, ok)
}

fn crit3(a: *mem.Arena, xs: []const f64, ys: []const f64, ws: []const f64, df: f64, spar: f64) -> f64 {
    let mk = mem.mark(a)
    var f: sps.SmSpline = zero
    var v = 1.0e300f64
    if sps.fit(a, xs, ys, ws, spar, &f) == ok { v = 3.0f64 + (df - f.df) * (df - f.df) }
    mem.reset(a, mk)
    ret v
}

fn fsign(x: f64, y: f64) -> f64 {
    let ax = math.abs[f64](x)
    if y >= 0.0f64 { ret ax }
    ret 0.0f64 - ax
}

// the spar search of R sbart.c for the df criterion (3 + (df - trace)^2) on [-1.5, 2] with tol 1e-4 and eps 2e-8: Brent as there, the answer is the LAST spar evaluated
// (the coefficients of the fit are those of that evaluation, not of the best one)
fn cs_search(a: *mem.Arena, xs: []const f64, ys: []const f64, ws: []const f64, df: f64) -> f64 {
    let gold = 0.3819660112501051518f64
    let tol = 0.0001f64
    let epsb = 0.00000002f64
    var lo = 0.0f64 - 1.5f64
    var hi = 2.0f64
    var v = lo + gold * (hi - lo)
    var w = v
    var x = v
    var d = 0.0f64
    var e = 0.0f64
    var fx = crit3(a, xs, ys, ws, df, x)
    var fv = fx
    var fw = fx
    var last = x
    var it = 0usize
    var go = true
    while go {
        let xm = (lo + hi) * 0.5f64
        let tol1 = epsb * math.abs[f64](x) + tol / 3.0f64
        let tol2 = tol1 * 2.0f64
        it += 1usize
        if math.abs[f64](x - xm) <= tol2 - (hi - lo) * 0.5f64 || it > 500usize {
            go = false
        } else {
            var golden = true
            if !(math.abs[f64](e) <= tol1 || fx != fx || fv != fv || fw != fw || fx > 1.0e299f64 || fv > 1.0e299f64 || fw > 1.0e299f64) {
                var r = (x - w) * (fx - fv)
                var q = (x - v) * (fx - fw)
                var p = (x - v) * q - (x - w) * r
                q = (q - r) * 2.0f64
                if q > 0.0f64 { p = 0.0f64 - p }
                q = math.abs[f64](q)
                r = e
                e = d
                if !(math.abs[f64](p) >= math.abs[f64](0.5f64 * q * r) || q == 0.0f64) {
                    if !(p <= q * (lo - x) || p >= q * (hi - x)) {
                        d = p / q
                        let u0 = x + d
                        if u0 - lo < tol2 || hi - u0 < tol2 { d = fsign(tol1, xm - x) }
                        golden = false
                    }
                }
            }
            if golden {
                if x >= xm { e = lo - x } else { e = hi - x }
                d = gold * e
            }
            var u = x + fsign(tol1, d)
            if math.abs[f64](d) >= tol1 { u = x + d }
            last = u
            let fu = crit3(a, xs, ys, ws, df, u)
            if fu <= fx {
                if u >= x { lo = x } else { hi = x }
                v = w
                fv = fw
                w = x
                fw = fx
                x = u
                fx = fu
            } else {
                if u < x { lo = u } else { hi = u }
                if fu <= fw || w == x {
                    v = w
                    fv = fw
                    w = u
                    fw = fu
                } else if fu <= fv || v == x || v == w {
                    v = u
                    fv = fu
                }
            }
        }
    }
    ret last
}
