// kernlab's TRON for the bound-constrained quadratic subproblems of BSVM (dtron, dcauchy, dspcg, dtrpcg, dprsrch, dgpstep, dbreakpt, dtrqsol,
// dgpnrm, dprecond through dpotf2) on the reference BLAS routines R ships (ddot unrolled by five, dnrm2 as a plain sum of squares for values in the
// normal range, dsymv upper, dtrsv lower, dgemv, daxpy, dscal), in the same order of operations. Matrices are n by n, row i, column j at i * n + j,
// and symmetric, so the column-major reads of the C code agree.
//
// dprecond keeps a static lambda in C that doubles whenever the shifted factorisation also fails; here it is the caller's f64 (see lam), shared
// across solves the way the C static is shared across a session.

use e.math
use e.mem

type W = struct { n: usize, xl: []f64, xc: []f64, s: []f64, wa: []f64, g: []f64, bm: []f64, lm: []f64, w: []f64, wa2: []f64, wsp: []f64, wxl: []f64, wxu: []f64, gfree: []f64, p: []f64, q: []f64, t: []f64, r: []f64, z: []f64, wa1: []f64, free: []usize, nfev: usize, lam: *f64 }

fn dmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn dmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn ddot(n: usize, x: []const f64, y: []const f64) -> f64 {
    var t = 0.0f64
    let m = n % 5usize
    var i = 0usize
    while i < m {
        t = t + x[i] * y[i]
        i += 1usize
    }
    if n < 5usize { ret t }
    i = m
    while i < n {
        t = t + x[i] * y[i] + x[i + 1usize] * y[i + 1usize] + x[i + 2usize] * y[i + 2usize] + x[i + 3usize] * y[i + 3usize] + x[i + 4usize] * y[i + 4usize]
        i += 5usize
    }
    ret t
}

fn dnrm2(n: usize, x: []const f64) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        t += x[i] * x[i]
        i += 1usize
    }
    ret math.sqrt[f64](t)
}

fn daxpy(n: usize, a: f64, x: []const f64, y: []f64) {
    var i = 0usize
    while i < n {
        y[i] = y[i] + a * x[i]
        i += 1usize
    }
}

// y = alpha * A * x + beta * y, upper triangle of the symmetric n by n matrix a
fn dsymv(n: usize, alpha: f64, a: []const f64, x: []const f64, beta: f64, y: []f64) {
    var i = 0usize
    if beta != 1.0f64 {
        while i < n {
            if beta == 0.0f64 {
                y[i] = 0.0f64
            } else {
                y[i] = beta * y[i]
            }
            i += 1usize
        }
    }
    if alpha == 0.0f64 { ret }
    var j = 0usize
    while j < n {
        let t1 = alpha * x[j]
        var t2 = 0.0f64
        i = 0usize
        while i < j {
            y[i] = y[i] + t1 * a[i * n + j]
            t2 = t2 + a[i * n + j] * x[i]
            i += 1usize
        }
        y[j] = y[j] + t1 * a[j * n + j] + alpha * t2
        j += 1usize
    }
}

// solve L x = b (trans false) or L' x = b (trans true), L lower with non-unit diagonal, in place
fn dtrsv(n: usize, l: []const f64, x: []f64, trans: bool) {
    var i = 0usize
    if !trans {
        var j = 0usize
        while j < n {
            if x[j] != 0.0f64 {
                x[j] = x[j] / l[j * n + j]
                let t = x[j]
                i = j + 1usize
                while i < n {
                    x[i] = x[i] - t * l[i * n + j]
                    i += 1usize
                }
            }
            j += 1usize
        }
        ret
    }
    var jj = n
    while jj > 0usize {
        let j = jj - 1usize
        var t = x[j]
        i = n
        while i > j + 1usize {
            t = t - l[(i - 1usize) * n + j] * x[i - 1usize]
            i -= 1usize
        }
        t = t / l[j * n + j]
        x[j] = t
        jj -= 1usize
    }
}

// dpotf2 lower on the n by n matrix a (column j holds L(., j) at i * n + j): the info of LAPACK, 0 on success
fn dpotf2(n: usize, a: []f64) -> usize {
    var j = 0usize
    while j < n {
        var dot = 0.0f64
        var k = 0usize
        while k < j {
            dot = dot + a[j * n + k] * a[j * n + k]
            k += 1usize
        }
        var ajj = a[j * n + j] - dot
        if ajj <= 0.0f64 || ajj != ajj {
            a[j * n + j] = ajj
            ret j + 1usize
        }
        ajj = math.sqrt[f64](ajj)
        a[j * n + j] = ajj
        if j + 1usize < n {
            k = 0usize
            while k < j {
                let t = 0.0f64 - a[j * n + k]
                var i = j + 1usize
                while i < n {
                    a[i * n + j] = a[i * n + j] + t * a[i * n + k]
                    i += 1usize
                }
                k += 1usize
            }
            let sc = 1.0f64 / ajj
            var i = j + 1usize
            while i < n {
                a[i * n + j] = sc * a[i * n + j]
                i += 1usize
            }
        }
        j += 1usize
    }
    ret 0usize
}

fn dcholfact(n: usize, a: []const f64, l: []f64, lam: *f64) {
    var i = 0usize
    while i < n * n {
        l[i] = a[i]
        i += 1usize
    }
    let ind = dpotf2(n, l)
    if ind != 0usize {
        i = 0usize
        while i < n * n {
            l[i] = a[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            l[i * n + i] += *lam
            i += 1usize
        }
        let ind2 = dpotf2(n, l)
        if ind2 != 0usize { *lam = *lam * 2.0f64 }
    }
}

fn dgpnrm(n: usize, x: []const f64, xl: []const f64, xu: []const f64, g: []const f64) -> f64 {
    var norm = 0.0f64
    var i = 0usize
    while i < n {
        if xl[i] != xu[i] {
            if !((g[i] <= 0.0f64 && x[i] == xu[i]) || (g[i] >= 0.0f64 && x[i] == xl[i])) {
                if math.abs[f64](g[i]) > norm { norm = math.abs[f64](g[i]) }
            }
        }
        i += 1usize
    }
    ret norm
}

fn dbreakpt(n: usize, x: []const f64, xl: []const f64, xu: []const f64, w: []const f64) -> (usize, f64, f64) {
    var nb = 0usize
    var mn = 0.0f64
    var mx = 0.0f64
    var i = 0usize
    while i < n {
        var hit = false
        var brpt = 0.0f64
        if x[i] < xu[i] && w[i] > 0.0f64 {
            hit = true
            brpt = (xu[i] - x[i]) / w[i]
        } else {
            if x[i] > xl[i] && w[i] < 0.0f64 {
                hit = true
                brpt = (xl[i] - x[i]) / w[i]
            }
        }
        if hit {
            nb += 1usize
            if nb == 1usize {
                mn = brpt
                mx = brpt
            } else {
                mn = dmin(brpt, mn)
                mx = dmax(brpt, mx)
            }
        }
        i += 1usize
    }
    if nb == 0usize {
        mn = 0.0f64
        mx = 0.0f64
    }
    ret (nb, mn, mx)
}

fn dgpstep(n: usize, x: []const f64, xl: []const f64, xu: []const f64, alpha: f64, w: []const f64, s: []f64) {
    var i = 0usize
    while i < n {
        if x[i] + alpha * w[i] < xl[i] {
            s[i] = xl[i] - x[i]
        } else {
            if x[i] + alpha * w[i] > xu[i] {
                s[i] = xu[i] - x[i]
            } else {
                s[i] = alpha * w[i]
            }
        }
        i += 1usize
    }
}

fn dtrqsol(n: usize, x: []const f64, p: []const f64, delta: f64) -> f64 {
    let dsq = delta * delta
    let ptx = ddot(n, p, x)
    let ptp = ddot(n, p, p)
    let xtx = ddot(n, x, x)
    var rad = ptx * ptx + ptp * (dsq - xtx)
    rad = math.sqrt[f64](dmax(rad, 0.0f64))
    if ptx > 0.0f64 { ret (dsq - xtx) / (ptx + rad) }
    if rad > 0.0f64 { ret (rad - ptx) / ptp }
    ret 0.0f64
}

fn dcauchy(w: *W, n: usize, x: []const f64, xl: []const f64, xu: []const f64, a: []const f64, g: []const f64, delta: f64, alpha: *f64, s: []f64) {
    let mu0 = 0.01f64
    let interpf = 0.1f64
    let extrapf = 10.0f64
    let wa = w.wa
    var i = 0usize
    while i < n {
        wa[i] = 0.0f64 - g[i]
        i += 1usize
    }
    let (nb, bmin, bmax) = dbreakpt(n, x, xl, xu, wa)
    if nb < 0usize { ret }
    dgpstep(n, x, xl, xu, 0.0f64 - *alpha, g, s)
    var interp = false
    var gts = 0.0f64
    var q = 0.0f64
    if dnrm2(n, s) > delta {
        interp = true
    } else {
        dsymv(n, 1.0f64, a, s, 0.0f64, wa)
        gts = ddot(n, g, s)
        q = 0.5f64 * ddot(n, s, wa) + gts
        interp = q >= mu0 * gts
    }
    if interp {
        var search = true
        while search {
            *alpha = *alpha * interpf
            dgpstep(n, x, xl, xu, 0.0f64 - *alpha, g, s)
            if dnrm2(n, s) <= delta {
                dsymv(n, 1.0f64, a, s, 0.0f64, wa)
                gts = ddot(n, g, s)
                q = 0.5f64 * ddot(n, s, wa) + gts
                search = q > mu0 * gts
            }
        }
    } else {
        var search = true
        var alphas = *alpha
        while search && *alpha <= bmax {
            alphas = *alpha
            *alpha = *alpha * extrapf
            dgpstep(n, x, xl, xu, 0.0f64 - *alpha, g, s)
            if dnrm2(n, s) <= delta {
                dsymv(n, 1.0f64, a, s, 0.0f64, wa)
                gts = ddot(n, g, s)
                q = 0.5f64 * ddot(n, s, wa) + gts
                search = q < mu0 * gts
            } else {
                search = false
            }
        }
        *alpha = alphas
        dgpstep(n, x, xl, xu, 0.0f64 - *alpha, g, s)
    }
}

fn dprsrch(w: *W, n: usize, x: []f64, xl: []const f64, xu: []const f64, a: []const f64, g: []const f64, wv: []f64) {
    let mu0 = 0.01f64
    let interpf = 0.5f64
    let wa1 = w.wa1
    let wa2 = w.wa2
    var alpha = 1.0f64
    var search = true
    let (nb, bmin, bmax) = dbreakpt(n, x, xl, xu, wv)
    if nb < 0usize { ret }
    while search && alpha > bmin {
        dgpstep(n, x, xl, xu, alpha, wv, wa1)
        dsymv(n, 1.0f64, a, wa1, 0.0f64, wa2)
        let gts = ddot(n, g, wa1)
        let q = 0.5f64 * ddot(n, wa1, wa2) + gts
        if q <= mu0 * gts {
            search = false
        } else {
            alpha = alpha * interpf
        }
    }
    if alpha < 1.0f64 && alpha < bmin { alpha = bmin }
    dgpstep(n, x, xl, xu, alpha, wv, wa1)
    daxpy(n, alpha, wv, x)
    var i = 0usize
    while i < n {
        x[i] = dmax(xl[i], dmin(x[i], xu[i]))
        wv[i] = wa1[i]
        i += 1usize
    }
}

// answers info (1 .. 5) and the iteration count
fn dtrpcg(w: *W, n: usize, a: []const f64, g: []const f64, delta: f64, l: []const f64, tol: f64, stol: f64, wv: []f64) -> (usize, usize) {
    let p = w.p
    let q = w.q
    let t = w.t
    let r = w.r
    let z = w.z
    var i = 0usize
    while i < n {
        wv[i] = 0.0f64
        r[i] = 0.0f64 - g[i]
        t[i] = 0.0f64 - g[i]
        i += 1usize
    }
    dtrsv(n, l, r, false)
    i = 0usize
    while i < n {
        p[i] = r[i]
        i += 1usize
    }
    var rho = ddot(n, r, r)
    let rnorm0 = math.sqrt[f64](rho)
    if rnorm0 <= stol { ret (1usize, 0usize) }
    var iters = 1usize
    while iters <= n {
        i = 0usize
        while i < n {
            z[i] = p[i]
            i += 1usize
        }
        dtrsv(n, l, z, true)
        dsymv(n, 1.0f64, a, z, 0.0f64, q)
        i = 0usize
        while i < n {
            z[i] = q[i]
            i += 1usize
        }
        dtrsv(n, l, q, false)
        let ptq = ddot(n, p, q)
        var alpha = 0.0f64
        if ptq > 0.0f64 { alpha = rho / ptq }
        let sigma = dtrqsol(n, wv, p, delta)
        if ptq <= 0.0f64 || alpha >= sigma {
            daxpy(n, sigma, p, wv)
            if ptq <= 0.0f64 { ret (3usize, iters) }
            ret (4usize, iters)
        }
        let malpha = 0.0f64 - alpha
        daxpy(n, alpha, p, wv)
        daxpy(n, malpha, q, r)
        daxpy(n, malpha, z, t)
        let rtr = ddot(n, r, r)
        let rnorm = math.sqrt[f64](rtr)
        let tnorm = math.sqrt[f64](ddot(n, t, t))
        if tnorm <= tol { ret (1usize, iters) }
        if rnorm <= stol { ret (2usize, iters) }
        let beta = rtr / rho
        i = 0usize
        while i < n {
            p[i] = beta * p[i]
            p[i] = p[i] + r[i]
            i += 1usize
        }
        rho = rtr
        iters += 1usize
    }
    ret (5usize, iters)
}

// the projected-search step: s on entry is the Cauchy step, on exit the final step
fn dspcg(w: *W, n: usize, x: []f64, xl: []const f64, xu: []const f64, a: []const f64, g: []const f64, delta: f64, rtol: f64, s: []f64) {
    let stol = 1e-16f64
    let wv = w.w
    let wa = w.wsp
    let bm = w.bm
    let lm = w.lm
    let wxl = w.wxl
    let wxu = w.wxu
    let gfree = w.gfree
    let fr = w.free
    dsymv(n, 1.0f64, a, s, 0.0f64, wv)
    var j = 0usize
    while j < n {
        x[j] = x[j] + s[j]
        x[j] = dmax(xl[j], dmin(x[j], xu[j]))
        j += 1usize
    }
    var nfaces = 0usize
    while nfaces < n {
        var nfree = 0usize
        j = 0usize
        while j < n {
            if xl[j] < x[j] && x[j] < xu[j] {
                fr[nfree] = j
                nfree += 1usize
            }
            j += 1usize
        }
        if nfree == 0usize { ret }
        var i = 0usize
        while i < nfree {
            j = 0usize
            while j < nfree {
                bm[i * nfree + j] = a[fr[i] * n + fr[j]]
                j += 1usize
            }
            wa[i] = g[fr[i]]
            gfree[i] = wv[fr[i]] + wa[i]
            i += 1usize
        }
        let gfnorm = dnrm2(nfree, wa)
        dcholfact(nfree, bm, lm, w.lam)
        let (infotr, itertr) = dtrpcg(w, nfree, bm, gfree, delta, lm, rtol * gfnorm, stol, wv)
        dtrsv(nfree, lm, wv, true)
        j = 0usize
        while j < nfree {
            wa[j] = x[fr[j]]
            wxl[j] = xl[fr[j]]
            wxu[j] = xu[fr[j]]
            j += 1usize
        }
        dprsrch(w, nfree, wa, wxl, wxu, bm, gfree, wv)
        j = 0usize
        while j < nfree {
            x[fr[j]] = wa[j]
            s[fr[j]] = s[fr[j]] + wv[j]
            j += 1usize
        }
        dsymv(n, 1.0f64, a, s, 0.0f64, wv)
        j = 0usize
        while j < nfree {
            gfree[j] = wv[fr[j]] + g[fr[j]]
            j += 1usize
        }
        let gfnormf = dnrm2(nfree, gfree)
        if gfnormf <= rtol * gfnorm { ret }
        if infotr == 3usize || infotr == 4usize { ret }
        nfaces += 1usize
    }
}

fn ufv(w: *W, n: usize, a: []const f64, g0: []const f64, x: []const f64) -> f64 {
    let t = w.wa1
    dsymv(n, 1.0f64, a, x, 0.0f64, t)
    w.nfev += 1usize
    ret ddot(n, x, g0) + 0.5f64 * ddot(n, x, t)
}

fn ugrad(n: usize, a: []const f64, g0: []const f64, x: []const f64, g: []f64) {
    var i = 0usize
    while i < n {
        g[i] = g0[i]
        i += 1usize
    }
    dsymv(n, 1.0f64, a, x, 1.0f64, g)
}

// min 0.5 x'Ax + g0'x over 0 <= x <= xu, x updated in place (solvebqp / dtron with the constants of BSVM)
fn solvebqp(w: *W, n: usize, a: []const f64, g0: []const f64, x: []f64, xu: []const f64, gtol: f64) {
    let eta0 = 1e-4f64
    let eta1 = 0.25f64
    let eta2 = 0.75f64
    let sigma1 = 0.25f64
    let sigma2 = 0.5f64
    let sigma3 = 4.0f64
    let frtol = 1e-12f64
    let fatol = 0.0f64
    let fmin = 0.0f64 - 1e32f64
    let cgtol = 0.1f64
    let maxfev = 1000usize
    let xl = w.xl
    let xc = w.xc
    let s = w.s
    let wa = w.wa
    let g = w.g
    var i = 0usize
    while i < n {
        xl[i] = 0.0f64
        i += 1usize
    }
    w.nfev = 0usize
    var alphac = 1.0f64
    var iter = 1usize
    ugrad(n, a, g0, x, g)
    var f = ufv(w, n, a, g0, x)
    let gnorm0 = dnrm2(n, g)
    var delta = 1000.0f64 * gnorm0
    var gnorm = dgpnrm(n, x, xl, xu, g)
    var search = true
    if gnorm <= gtol * gnorm0 { search = false }
    while search {
        let fc = f
        i = 0usize
        while i < n {
            xc[i] = x[i]
            i += 1usize
        }
        dcauchy(w, n, x, xl, xu, a, g, delta, &alphac, s)
        dspcg(w, n, x, xl, xu, a, g, delta, cgtol, s)
        f = ufv(w, n, a, g0, x)
        if w.nfev > maxfev {
            search = false
        } else {
            i = 0usize
            while i < n {
                wa[i] = g[i]
                i += 1usize
            }
            dsymv(n, 0.5f64, a, s, 1.0f64, wa)
            let prered = 0.0f64 - ddot(n, s, wa)
            let actred = fc - f
            let snorm = dnrm2(n, s)
            if iter == 1usize { delta = dmin(delta, snorm) }
            let gs = ddot(n, g, s)
            var alpha = sigma3
            if f - fc - gs > 0.0f64 { alpha = dmax(sigma1, 0.0f64 - 0.5f64 * (gs / (f - fc - gs))) }
            if actred < eta0 * prered {
                delta = dmin(dmax(alpha, sigma1) * snorm, sigma2 * delta)
            } else {
                if actred < eta1 * prered {
                    delta = dmax(sigma1 * delta, dmin(alpha * snorm, sigma2 * delta))
                } else {
                    if actred < eta2 * prered {
                        delta = dmax(sigma1 * delta, dmin(alpha * snorm, sigma3 * delta))
                    } else {
                        delta = dmax(delta, dmin(alpha * snorm, sigma3 * delta))
                    }
                }
            }
            var cont = true
            if actred > eta0 * prered {
                iter += 1usize
                ugrad(n, a, g0, x, g)
                gnorm = dgpnrm(n, x, xl, xu, g)
                if gnorm <= gtol * gnorm0 {
                    search = false
                    cont = false
                }
            } else {
                i = 0usize
                while i < n {
                    x[i] = xc[i]
                    i += 1usize
                }
                f = fc
            }
            if cont {
                if f < fmin {
                    search = false
                } else {
                    if math.abs[f64](actred) <= fatol && prered <= fatol {
                        search = false
                    } else {
                        if math.abs[f64](actred) <= frtol * math.abs[f64](f) && prered <= frtol * math.abs[f64](f) { search = false }
                    }
                }
            }
        }
    }
}
