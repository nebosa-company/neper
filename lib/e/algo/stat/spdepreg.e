// R spatialreg and spdep regression diagnostics on a dense row-major n by n weights matrix w and a column-major n by m design x:
// lagsarlm and errorsarlm by maximum likelihood with the eigenvalue Jacobian (R's optimize on 1 / range of the real eigenvalues, asymptotic standard errors), impacts of the lag model (eigenvalue and trace forms), lm.RStests (lm.LMtests) and lm.morantest.
//
// sacsarlm is sac_ml (one weights matrix for both parts).
// Not here: Durbin and mixed models, the numerical-Hessian and non-eigen Jacobian methods, impacts by simulation (R =), zero.policy rows in the models.

use e.algo.linalg.decomp as dc
use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.fcast as fc
use e.algo.stat.nlminb as nl
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem


fn pi2() -> f64 { ret 6.283185307179586f64 }

// row-major k by k inverse by Gauss-Jordan with partial pivoting; false when singular
fn ginv(a: []const f64, k: usize, out: []f64, work: []f64) -> bool {
    var i = 0usize
    while i < k * k {
        work[i] = a[i]
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        out[i * k + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < k {
        var piv = c
        var best = math.abs[f64](work[c * k + c])
        var r = c + 1usize
        while r < k {
            if math.abs[f64](work[r * k + c]) > best {
                best = math.abs[f64](work[r * k + c])
                piv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret false }
        if piv != c {
            var j = 0usize
            while j < k {
                let t = work[c * k + j]
                work[c * k + j] = work[piv * k + j]
                work[piv * k + j] = t
                let u = out[c * k + j]
                out[c * k + j] = out[piv * k + j]
                out[piv * k + j] = u
                j += 1usize
            }
        }
        let d = work[c * k + c]
        var j = 0usize
        while j < k {
            work[c * k + j] = work[c * k + j] / d
            out[c * k + j] = out[c * k + j] / d
            j += 1usize
        }
        r = 0usize
        while r < k {
            if r != c {
                let f = work[r * k + c]
                if f != 0.0f64 {
                    j = 0usize
                    while j < k {
                        work[r * k + j] = work[r * k + j] - f * work[c * k + j]
                        out[r * k + j] = out[r * k + j] - f * out[c * k + j]
                        j += 1usize
                    }
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    ret true
}

// eigenvalues of w the way spatialreg takes them: dsyevr when w is symmetric, or when sim is 1 and the pattern is symmetric (the similar symmetric matrix sqrt(w_ij w_ji)), otherwise the general eigen
fn weig(a: *mem.Arena, w: []const f64, n: usize, sim: usize, re: []f64, im: []f64) -> err {
    var symm = true
    var pat = true
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if w[i * n + j] != w[j * n + i] { symm = false }
            if (w[i * n + j] != 0.0f64) != (w[j * n + i] != 0.0f64) { pat = false }
            j += 1usize
        }
        i += 1usize
    }
    if symm || (sim == 1usize && pat) {
        let (m, e1) = mem.alloc[f64](a, n * n)
        let (z, e2) = mem.alloc[f64](a, n * n)
        if e1 != ok { ret e1 }
        if e2 != ok { ret e2 }
        i = 0usize
        while i < n * n {
            m[i] = w[i]
            i += 1usize
        }
        if !symm {
            i = 0usize
            while i < n {
                var j = 0usize
                while j < n {
                    m[j * n + i] = 0.0f64
                    if w[i * n + j] != 0.0f64 { m[j * n + i] = math.sqrt[f64](w[i * n + j] * w[j * n + i]) }
                    j += 1usize
                }
                i += 1usize
            }
        }
        let e3 = sy.dsyevr_all(a, m, n, re, z)
        if e3 != ok { ret e3 }
        i = 0usize
        while i < n {
            im[i] = 0.0f64
            i += 1usize
        }
        ret ok
    }
    // dc.eigen reads column-major; the eigenvalues of the transpose are the same
    let (eg, e4) = dc.eigen(a, w, n)
    if e4 != ok { ret e4 }
    i = 0usize
    while i < n {
        re[i] = eg.re[i]
        im[i] = eg.im[i]
        if math.abs[f64](im[i]) < 1.0e-9f64 { im[i] = 0.0f64 }
        i += 1usize
    }
    ret ok
}

// the real eigenvalue range: out = 1 / min, 1 / max
fn eig_interval(re: []const f64, im: []const f64, n: usize, out: []f64) {
    var lo = 1.0e300f64
    var hi = 0.0f64 - 1.0e300f64
    var i = 0usize
    while i < n {
        if im[i] == 0.0f64 {
            if re[i] < lo { lo = re[i] }
            if re[i] > hi { hi = re[i] }
        }
        i += 1usize
    }
    out[0usize] = 1.0f64 / lo
    out[1usize] = 1.0f64 / hi
}

// Re(sum(log(1 - c * eig)))
fn ldet_eig(re: []const f64, im: []const f64, n: usize, c: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        if im[i] == 0.0f64 {
            s += math.log[f64](1.0f64 - c * re[i])
        } else {
            let a = 1.0f64 - c * re[i]
            let b = c * im[i]
            s += math.log[f64](math.sqrt[f64](a * a + b * b))
        }
        i += 1usize
    }
    ret s
}

fn matvec(w: []const f64, n: usize, v: []const f64, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += w[i * n + j] * v[j]
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
}

// logLik of lm: n residuals with sum of squares sse
fn lm_loglik(n: usize, sse: f64) -> f64 {
    let nf = f64(n)
    ret 0.0f64 - 0.5f64 * nf * (math.log[f64](pi2()) + 1.0f64 - math.log[f64](nf) + math.log[f64](sse))
}

type LagCtx = struct { n: f64, ea: f64, eb: f64, ec: f64, re: []const f64, im: []const f64, k: usize }

fn lag_f(c: *LagCtx, rho: f64) -> f64 {
    let sse = c.ea - 2.0f64 * rho * c.eb + rho * rho * c.ec
    let s2 = sse / c.n
    let ld = ldet_eig(c.re, c.im, c.k, rho)
    ret 0.0f64 - (ld - (c.n / 2.0f64) * math.log[f64](pi2()) - (c.n / 2.0f64) * math.log[f64](s2) - (1.0f64 / (2.0f64 * s2)) * sse)
}

// lagsarlm(y ~ x - 1, method = "eigen"): out = rho, LL, s2, SSE, rho.se, LMtest, logLik of the lm, then m coefficients and m standard errors (2 * m + 7 values). sim: see weig
fn lag_ml(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, m: usize, w: []const f64, sim: usize, out: []f64) -> err {
    let nf = f64(n)
    let (wy, e0) = mem.alloc[f64](a, n)
    let (re, e1) = mem.alloc[f64](a, n)
    let (im, e2) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    matvec(w, n, y, wy)
    let (f0, e3) = dc.lm_fit(a, x, n, m, y, 1.0e-7f64)
    if e3 != ok { ret e3 }
    let (f1, e4) = dc.lm_fit(a, x, n, m, wy, 1.0e-7f64)
    if e4 != ok { ret e4 }
    var ea = 0.0f64
    var eb = 0.0f64
    var ec = 0.0f64
    var i = 0usize
    while i < n {
        ea += f0.residuals[i] * f0.residuals[i]
        eb += f1.residuals[i] * f0.residuals[i]
        ec += f1.residuals[i] * f1.residuals[i]
        i += 1usize
    }
    let e5 = weig(a, w, n, sim, re, im)
    if e5 != ok { ret e5 }
    var iv: [2]f64 = zero
    eig_interval(re, im, n, iv[0usize..2usize])
    var ctx = LagCtx { n: nf, ea: ea, eb: eb, ec: ec, re: re, im: im, k: n }
    let rho = fc.brent_fmin[LagCtx](&ctx, lag_f, iv[0usize], iv[1usize], 1.4901161193847656e-8f64)
    let ll = 0.0f64 - lag_f(&ctx, rho)
    let (yl, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret e6 }
    i = 0usize
    while i < n {
        yl[i] = y[i] - rho * wy[i]
        i += 1usize
    }
    let (f2, e7) = dc.lm_fit(a, x, n, m, yl, 1.0e-7f64)
    if e7 != ok { ret e7 }
    var sse = 0.0f64
    i = 0usize
    while i < n {
        sse += f2.residuals[i] * f2.residuals[i]
        i += 1usize
    }
    let s2 = sse / nf
    // asymptotic variance
    let (mi, e8) = mem.alloc[f64](a, n * n)
    let (aa, e9) = mem.alloc[f64](a, n * n)
    let (wk, e10) = mem.alloc[f64](a, n * n)
    let (aw, e11) = mem.alloc[f64](a, n * n)
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    i = 0usize
    while i < n * n {
        mi[i] = 0.0f64 - rho * w[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        mi[i * n + i] += 1.0f64
        i += 1usize
    }
    if !ginv(mi, n, aa, wk) { ret dc.Singular }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += aa[i * n + t] * w[t * n + j]
                t += 1usize
            }
            aw[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    var omega = 0.0f64
    i = 0usize
    while i < n {
        let d_re = 1.0f64 - rho * re[i]
        let d_im = 0.0f64 - rho * im[i]
        let dd = d_re * d_re + d_im * d_im
        let q_re = (re[i] * d_re + im[i] * d_im) / dd
        let q_im = (im[i] * d_re - re[i] * d_im) / dd
        omega += q_re * q_re - q_im * q_im
        i += 1usize
    }
    var tr_aw = 0.0f64
    var tr_awaw = 0.0f64
    i = 0usize
    while i < n {
        tr_aw += aw[i * n + i]
        var j = 0usize
        while j < n {
            tr_awaw += aw[i * n + j] * aw[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    let (xb, e12) = mem.alloc[f64](a, n)
    let (awxb, e13) = mem.alloc[f64](a, n)
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            s += x[j * n + i] * f2.coef[j]
            j += 1usize
        }
        xb[i] = s
        i += 1usize
    }
    matvec(aw, n, xb, awxb)
    var nrm = 0.0f64
    i = 0usize
    while i < n {
        nrm += awxb[i] * awxb[i]
        i += 1usize
    }
    let k = m + 2usize
    let (inf, e14) = mem.alloc[f64](a, k * k)
    let (vb, e15) = mem.alloc[f64](a, k * k)
    let (wk2, e16) = mem.alloc[f64](a, k * k)
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    if e16 != ok { ret e16 }
    i = 0usize
    while i < k * k {
        inf[i] = 0.0f64
        i += 1usize
    }
    inf[0usize] = nf / 2.0f64
    inf[1usize] = s2 * tr_aw
    inf[k] = s2 * tr_aw
    inf[k + 1usize] = s2 * (s2 * tr_awaw + nrm) + omega * s2 * s2
    var jc = 0usize
    while jc < m {
        var xt = 0.0f64
        i = 0usize
        while i < n {
            xt += x[jc * n + i] * awxb[i]
            i += 1usize
        }
        inf[1usize * k + 2usize + jc] = s2 * xt
        inf[(2usize + jc) * k + 1usize] = s2 * xt
        var jd = 0usize
        while jd < m {
            var xx = 0.0f64
            i = 0usize
            while i < n {
                xx += x[jc * n + i] * x[jd * n + i]
                i += 1usize
            }
            inf[(2usize + jc) * k + 2usize + jd] = s2 * xx
            jd += 1usize
        }
        jc += 1usize
    }
    if !ginv(inf, k, vb, wk2) { ret dc.Singular }
    i = 0usize
    while i < k * k {
        vb[i] = vb[i] * s2 * s2
        i += 1usize
    }
    let rho_se = math.sqrt[f64](vb[k + 1usize])
    // LM test on the residuals
    var t22 = 0.0f64
    var t21a = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            // TW = W W + W'W
            var ww = 0.0f64
            var wtw = 0.0f64
            var t = 0usize
            while t < n {
                ww += w[i * n + t] * w[t * n + j]
                wtw += w[t * n + i] * w[t * n + j]
                t += 1usize
            }
            if i == j { t22 += ww + wtw }
            // sum_ij TW_ij A_ji
            t21a += (ww + wtw) * aa[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    let (wr, e17) = mem.alloc[f64](a, n)
    if e17 != ok { ret e17 }
    matvec(w, n, f2.residuals, wr)
    var rwr = 0.0f64
    i = 0usize
    while i < n {
        rwr += f2.residuals[i] * wr[i]
        i += 1usize
    }
    let lmt = ((rwr / s2) * (rwr / s2)) / (t22 - (t21a * t21a) * (rho_se * rho_se))
    out[0usize] = rho
    out[1usize] = ll
    out[2usize] = s2
    out[3usize] = sse
    out[4usize] = rho_se
    out[5usize] = lmt
    out[6usize] = lm_loglik(n, ea)
    i = 0usize
    while i < m {
        out[7usize + i] = f2.coef[i]
        out[7usize + m + i] = math.sqrt[f64](vb[(2usize + i) * k + 2usize + i])
        i += 1usize
    }
    ret ok
}

type ErrCtx = struct { a: *mem.Arena, y: []const f64, wy: []const f64, x: []const f64, wx: []const f64, n: usize, m: usize, re: []const f64, im: []const f64 }

// the filtered response and design for lambda; xl is column-major
fn err_filter(c: *ErrCtx, lam: f64, yl: []f64, xl: []f64) {
    var i = 0usize
    while i < c.n {
        yl[i] = c.y[i] - lam * c.wy[i]
        i += 1usize
    }
    i = 0usize
    while i < c.n * c.m {
        xl[i] = c.x[i] - lam * c.wx[i]
        i += 1usize
    }
}

fn err_ll(c: *ErrCtx, lam: f64) -> f64 {
    let n = c.n
    let nf = f64(n)
    let start = mem.mark(c.a)
    let (yl, e1) = mem.alloc[f64](c.a, n)
    let (xl, e2) = mem.alloc[f64](c.a, n * c.m)
    let (qty, e3) = mem.alloc[f64](c.a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    err_filter(c, lam, yl, xl)
    let (f, e4) = dc.qr(c.a, xl, n, c.m, 1.0e-7f64)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    var yy = 0.0f64
    var i = 0usize
    while i < n {
        qty[i] = yl[i]
        yy += yl[i] * yl[i]
        i += 1usize
    }
    // R forms qr.Q explicitly and takes crossprod(t(Q) y)
    var qq = 0.0f64
    var j = 0usize
    while j < c.m {
        i = 0usize
        while i < n {
            qty[i] = 0.0f64
            i += 1usize
        }
        qty[j] = 1.0f64
        dc.qr_qy(&f, qty)
        var d = 0.0f64
        i = 0usize
        while i < n {
            d += qty[i] * yl[i]
            i += 1usize
        }
        qq += d * d
        j += 1usize
    }
    let sse = yy - qq
    let s2 = sse / nf
    let ld = ldet_eig(c.re, c.im, n, lam)
    mem.reset(c.a, start)
    ret ld - ((nf / 2.0f64) * math.log[f64](pi2())) - (nf / 2.0f64) * math.log[f64](s2) - (1.0f64 / (2.0f64 * s2)) * sse
}

fn err_f(c: *ErrCtx, lam: f64) -> f64 { ret 0.0f64 - err_ll(c, lam) }

// errorsarlm(y ~ x - 1, method = "eigen"): out = lambda, LL, s2, SSE, lambda.se, logLik of the lm, then m coefficients and m standard errors (2 * m + 6 values)
fn err_ml(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, m: usize, w: []const f64, sim: usize, out: []f64) -> err {
    let nf = f64(n)
    let (wy, e0) = mem.alloc[f64](a, n)
    let (wx, e0b) = mem.alloc[f64](a, n * m)
    let (re, e1) = mem.alloc[f64](a, n)
    let (im, e2) = mem.alloc[f64](a, n)
    let (col, e2b) = mem.alloc[f64](a, n)
    let (colw, e2c) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    if e0b != ok { ret e0b }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e2b != ok { ret e2b }
    if e2c != ok { ret e2c }
    matvec(w, n, y, wy)
    var j = 0usize
    while j < m {
        var i = 0usize
        while i < n {
            col[i] = x[j * n + i]
            i += 1usize
        }
        matvec(w, n, col, colw)
        i = 0usize
        while i < n {
            wx[j * n + i] = colw[i]
            i += 1usize
        }
        j += 1usize
    }
    let e5 = weig(a, w, n, sim, re, im)
    if e5 != ok { ret e5 }
    var iv: [2]f64 = zero
    eig_interval(re, im, n, iv[0usize..2usize])
    var ctx = ErrCtx { a: a, y: y, wy: wy, x: x, wx: wx, n: n, m: m, re: re, im: im }
    let lam = fc.brent_fmin[ErrCtx](&ctx, err_f, iv[0usize], iv[1usize], 1.4901161193847656e-8f64)
    let ll = err_ll(&ctx, lam)
    let (yl, e6) = mem.alloc[f64](a, n)
    let (xl, e7) = mem.alloc[f64](a, n * m)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    err_filter(&ctx, lam, yl, xl)
    let (f2, e8) = dc.lm_fit(a, xl, n, m, yl, 1.0e-7f64)
    if e8 != ok { ret e8 }
    var sse = 0.0f64
    var i = 0usize
    while i < n {
        sse += f2.residuals[i] * f2.residuals[i]
        i += 1usize
    }
    let s2 = sse / nf
    // (Xl'Xl)^-1
    let (xtx, e9) = mem.alloc[f64](a, m * m)
    let (xti, e10) = mem.alloc[f64](a, m * m)
    let (wk, e11) = mem.alloc[f64](a, m * m)
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    var jc = 0usize
    while jc < m {
        var jd = 0usize
        while jd < m {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += xl[jc * n + i] * xl[jd * n + i]
                i += 1usize
            }
            xtx[jc * m + jd] = s
            jd += 1usize
        }
        jc += 1usize
    }
    if !ginv(xtx, m, xti, wk) { ret dc.Singular }
    // asymptotic variance of lambda
    let (mi, e12) = mem.alloc[f64](a, n * n)
    let (aa, e13) = mem.alloc[f64](a, n * n)
    let (wk3, e14) = mem.alloc[f64](a, n * n)
    let (wa, e15) = mem.alloc[f64](a, n * n)
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    i = 0usize
    while i < n * n {
        mi[i] = 0.0f64 - lam * w[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        mi[i * n + i] += 1.0f64
        i += 1usize
    }
    if !ginv(mi, n, aa, wk3) { ret dc.Singular }
    i = 0usize
    while i < n {
        var jj = 0usize
        while jj < n {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += w[i * n + t] * aa[t * n + jj]
                t += 1usize
            }
            wa[i * n + jj] = s
            jj += 1usize
        }
        i += 1usize
    }
    var tr_wa = 0.0f64
    var t22 = 0.0f64
    i = 0usize
    while i < n {
        tr_wa += wa[i * n + i]
        var jj = 0usize
        while jj < n {
            t22 += wa[i * n + jj] * wa[jj * n + i] + wa[i * n + jj] * wa[i * n + jj]
            jj += 1usize
        }
        i += 1usize
    }
    let k = m + 2usize
    let (av, e16) = mem.alloc[f64](a, k * k)
    let (avi, e17) = mem.alloc[f64](a, k * k)
    let (wk4, e18) = mem.alloc[f64](a, k * k)
    if e16 != ok { ret e16 }
    if e17 != ok { ret e17 }
    if e18 != ok { ret e18 }
    i = 0usize
    while i < k * k {
        av[i] = 0.0f64
        i += 1usize
    }
    av[0usize] = nf / (2.0f64 * s2 * s2)
    av[1usize] = tr_wa / s2
    av[k] = tr_wa / s2
    av[k + 1usize] = t22
    jc = 0usize
    while jc < m {
        var jd = 0usize
        while jd < m {
            av[(2usize + jc) * k + 2usize + jd] = xtx[jc * m + jd] / s2
            jd += 1usize
        }
        jc += 1usize
    }
    if !ginv(av, k, avi, wk4) { ret dc.Singular }
    out[0usize] = lam
    out[1usize] = ll
    out[2usize] = s2
    out[3usize] = sse
    out[4usize] = math.sqrt[f64](avi[k + 1usize])
    // logLik of lm(y ~ x - 1)
    let (f0, e19) = dc.lm_fit(a, x, n, m, y, 1.0e-7f64)
    if e19 != ok { ret e19 }
    var s0 = 0.0f64
    i = 0usize
    while i < n {
        s0 += f0.residuals[i] * f0.residuals[i]
        i += 1usize
    }
    out[5usize] = lm_loglik(n, s0)
    i = 0usize
    while i < m {
        out[6usize + i] = f2.coef[i]
        out[6usize + m + i] = math.sqrt[f64](xti[i * m + i] * sse / nf)
        i += 1usize
    }
    ret ok
}

// SSE of yl on xl the way spatialreg takes it: crossprod(yl) - crossprod(crossprod(qr.Q(qr(xl)), yl)); false when the QR fails
fn sse_q(a: *mem.Arena, xl: []const f64, yl: []const f64, n: usize, m: usize, sse: *f64) -> bool {
    let start = mem.mark(a)
    let (qty, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret false }
    let (f, e4) = dc.qr(a, xl, n, m, 1.0e-7f64)
    if e4 != ok { ret false }
    var yy = 0.0f64
    var i = 0usize
    while i < n {
        yy += yl[i] * yl[i]
        i += 1usize
    }
    var qq = 0.0f64
    var j = 0usize
    while j < m {
        i = 0usize
        while i < n {
            qty[i] = 0.0f64
            i += 1usize
        }
        qty[j] = 1.0f64
        dc.qr_qy(&f, qty)
        var d = 0.0f64
        i = 0usize
        while i < n {
            d += qty[i] * yl[i]
            i += 1usize
        }
        qq += d * d
        j += 1usize
    }
    mem.reset(a, start)
    *sse = yy - qq
    ret true
}

type SacCtx = struct { a: *mem.Arena, y: []const f64, wy: []const f64, wwy: []const f64, x: []const f64, wx: []const f64, n: usize, m: usize, re: []const f64, im: []const f64 }

// the filtered response and design of the sac model: y - rho Wy - lambda Wy + rho lambda WWy and x - lambda Wx
fn sac_filter(c: *SacCtx, rho: f64, lam: f64, yl: []f64, xl: []f64) {
    var i = 0usize
    while i < c.n {
        yl[i] = c.y[i] - rho * c.wy[i] - lam * c.wy[i] + rho * lam * c.wwy[i]
        i += 1usize
    }
    i = 0usize
    while i < c.n * c.m {
        xl[i] = c.x[i] - lam * c.wx[i]
        i += 1usize
    }
}

// sacsar.f: minus the log likelihood
fn sac_f(c: *SacCtx, p: []const f64) -> f64 {
    let n = c.n
    let nf = f64(n)
    let start = mem.mark(c.a)
    let (yl, e1) = mem.alloc[f64](c.a, n)
    let (xl, e2) = mem.alloc[f64](c.a, n * c.m)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    sac_filter(c, p[0usize], p[1usize], yl, xl)
    var sse = 0.0f64
    if !sse_q(c.a, xl, yl, n, c.m, &sse) { ret 0.0f64 / 0.0f64 }
    let s2 = sse / nf
    let ld1 = ldet_eig(c.re, c.im, n, p[0usize])
    let ld2 = ldet_eig(c.re, c.im, n, p[1usize])
    mem.reset(c.a, start)
    let ll = ld1 + ld2 - ((nf / 2.0f64) * math.log[f64](pi2())) - (nf / 2.0f64) * math.log[f64](s2) - (1.0f64 / (2.0f64 * s2)) * sse
    ret 0.0f64 - ll
}

fn sac_gr(c: *SacCtx, p: []const f64, g: []f64) {}

// row-major n by n product
fn mmul(x: []const f64, y: []const f64, n: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += x[i * n + t] * y[t * n + j]
                t += 1usize
            }
            out[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

fn mtrace(x: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i * n + i]
        i += 1usize
    }
    ret s
}

// sacsarlm(y ~ x - 1, method = "eigen", listw2 = listw): out = rho, lambda, LL, s2, SSE, rho.se, lambda.se, logLik of the lm, then m coefficients and m standard errors (2 * m + 8 values).
// nlminb with bounds from the four starts 0.8 * (lo1, 0, hi1, hi1) by 0.8 * (hi2, 0, hi2, lo2), the first best one kept, asymptotic covariance of sac.m
fn sac_ml(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, m: usize, w: []const f64, sim: usize, out: []f64) -> err {
    let nf = f64(n)
    let (wy, e0) = mem.alloc[f64](a, n)
    let (wwy, e0a) = mem.alloc[f64](a, n)
    let (wx, e0b) = mem.alloc[f64](a, n * m)
    let (re, e1) = mem.alloc[f64](a, n)
    let (im, e2) = mem.alloc[f64](a, n)
    let (col, e2b) = mem.alloc[f64](a, n)
    let (colw, e2c) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    if e0a != ok { ret e0a }
    if e0b != ok { ret e0b }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e2b != ok { ret e2b }
    if e2c != ok { ret e2c }
    matvec(w, n, y, wy)
    matvec(w, n, wy, wwy)
    var j = 0usize
    while j < m {
        var i = 0usize
        while i < n {
            col[i] = x[j * n + i]
            i += 1usize
        }
        matvec(w, n, col, colw)
        i = 0usize
        while i < n {
            wx[j * n + i] = colw[i]
            i += 1usize
        }
        j += 1usize
    }
    let e5 = weig(a, w, n, sim, re, im)
    if e5 != ok { ret e5 }
    var iv: [2]f64 = zero
    eig_interval(re, im, n, iv[0usize..2usize])
    var ctx = SacCtx { a: a, y: y, wy: wy, wwy: wwy, x: x, wx: wx, n: n, m: m, re: re, im: im }
    var lo: [2]f64 = zero
    var hi: [2]f64 = zero
    lo[0usize] = iv[0usize]
    lo[1usize] = iv[0usize]
    hi[0usize] = iv[1usize]
    hi[1usize] = iv[1usize]
    var best: [2]f64 = zero
    var bobj = 0.0f64
    var st = 0usize
    while st < 4usize {
        var par: [2]f64 = zero
        if st == 0usize {
            par[0usize] = iv[0usize] * 0.8f64
            par[1usize] = iv[1usize] * 0.8f64
        }
        if st == 1usize {
            par[0usize] = 0.0f64
            par[1usize] = 0.0f64
        }
        if st == 2usize {
            par[0usize] = iv[1usize] * 0.8f64
            par[1usize] = iv[1usize] * 0.8f64
        }
        if st == 3usize {
            par[0usize] = iv[1usize] * 0.8f64
            par[1usize] = iv[0usize] * 0.8f64
        }
        var none: [1]f64 = zero
        let r = nl.nlminb_bounded[SacCtx](a, &ctx, sac_f, sac_gr, false, par[0usize..2usize], none[0usize..0usize], lo[0usize..2usize], hi[0usize..2usize])
        if st == 0usize || r.objective < bobj {
            bobj = r.objective
            best[0usize] = par[0usize]
            best[1usize] = par[1usize]
        }
        st += 1usize
    }
    let rho = best[0usize]
    let lam = best[1usize]
    let (yl, e6) = mem.alloc[f64](a, n)
    let (xl, e7) = mem.alloc[f64](a, n * m)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    sac_filter(&ctx, rho, lam, yl, xl)
    let (f2, e8) = dc.lm_fit(a, xl, n, m, yl, 1.0e-7f64)
    if e8 != ok { ret e8 }
    var sse = 0.0f64
    var i = 0usize
    while i < n {
        sse += f2.residuals[i] * f2.residuals[i]
        i += 1usize
    }
    let s2 = sse / nf
    // asymptotic covariance, spatialreg's translation of sac.m; the unknowns are sigma, rho, lambda and the m slopes
    let nn = n * n
    let (blk, e9) = mem.alloc[f64](a, 12usize * nn)
    if e9 != ok { ret e9 }
    let am = blk[0usize..nn]
    let ai = blk[nn..2usize * nn]
    let bm = blk[2usize * nn..3usize * nn]
    let bi = blk[3usize * nn..4usize * nn]
    let wa = blk[4usize * nn..5usize * nn]
    let wb = blk[5usize * nn..6usize * nn]
    let t1 = blk[6usize * nn..7usize * nn]
    let t2 = blk[7usize * nn..8usize * nn]
    let wk = blk[8usize * nn..9usize * nn]
    var q = 0usize
    while q < nn {
        am[q] = 0.0f64 - rho * w[q]
        bm[q] = 0.0f64 - lam * w[q]
        q += 1usize
    }
    i = 0usize
    while i < n {
        am[i * n + i] += 1.0f64
        bm[i * n + i] += 1.0f64
        i += 1usize
    }
    if !ginv(am, n, ai, wk) { ret dc.Singular }
    if !ginv(bm, n, bi, wk) { ret dc.Singular }
    mmul(w, ai, n, wa)
    mmul(w, bi, n, wb)
    let p3 = m + 3usize
    let (av, e10) = mem.alloc[f64](a, p3 * p3)
    let (avi, e11) = mem.alloc[f64](a, p3 * p3)
    let (wk2, e12) = mem.alloc[f64](a, p3 * p3)
    let (bx, e13) = mem.alloc[f64](a, n * m)
    let (vv, e14) = mem.alloc[f64](a, n)
    let (tv, e15) = mem.alloc[f64](a, n)
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    q = 0usize
    while q < p3 * p3 {
        av[q] = 0.0f64
        q += 1usize
    }
    // Bx column by column
    j = 0usize
    while j < m {
        i = 0usize
        while i < n {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += bm[i * n + t] * x[j * n + t]
                t += 1usize
            }
            bx[j * n + i] = s
            i += 1usize
        }
        j += 1usize
    }
    // v = B WA x bhat
    i = 0usize
    while i < n {
        var s = 0.0f64
        j = 0usize
        while j < m {
            s += x[j * n + i] * f2.coef[j]
            j += 1usize
        }
        tv[i] = s
        i += 1usize
    }
    matvec(wa, n, tv, vv)
    i = 0usize
    while i < n {
        tv[i] = vv[i]
        i += 1usize
    }
    matvec(bm, n, tv, vv)
    var jc = 0usize
    while jc < m {
        var jd = 0usize
        while jd < m {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += bx[jc * n + i] * bx[jd * n + i]
                i += 1usize
            }
            av[(3usize + jc) * p3 + 3usize + jd] = s / s2
            jd += 1usize
        }
        jc += 1usize
    }
    av[0usize] = nf / (2.0f64 * s2 * s2)
    // BWABI = B WA BI
    mmul(bm, wa, n, t1)
    mmul(t1, bi, n, t2)
    mmul(wa, wa, n, t1)
    let term1 = mtrace(t1, n)
    var term2 = 0.0f64
    q = 0usize
    while q < nn {
        term2 += (s2 * t2[q]) * ((1.0f64 / s2) * t2[q])
        q += 1usize
    }
    var vsq = 0.0f64
    i = 0usize
    while i < n {
        vsq += vv[i] * ((1.0f64 / s2) * vv[i])
        i += 1usize
    }
    av[p3 + 1usize] = term1 + term2 + vsq
    mmul(wb, wb, n, t1)
    var term2b = 0.0f64
    q = 0usize
    while q < nn {
        term2b += (s2 * wb[q]) * ((1.0f64 / s2) * wb[q])
        q += 1usize
    }
    av[2usize * p3 + 2usize] = mtrace(t1, n) + term2b
    jc = 0usize
    while jc < m {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += bx[jc * n + i] * vv[i]
            i += 1usize
        }
        av[p3 + 3usize + jc] = (1.0f64 / s2) * s
        av[(3usize + jc) * p3 + 1usize] = (1.0f64 / s2) * s
        jc += 1usize
    }
    mmul(w, ai, n, t1)
    av[p3] = (1.0f64 / s2) * mtrace(t1, n)
    av[1usize] = av[p3]
    mmul(w, bi, n, t1)
    av[2usize * p3] = (1.0f64 / s2) * mtrace(t1, n)
    av[2usize] = av[2usize * p3]
    // tr(t(WB) omegi BWABI omeg) + tr(W WA BI)
    var tr1 = 0.0f64
    q = 0usize
    while q < nn {
        tr1 += wb[q] * (t2[q] * s2) * (1.0f64 / s2)
        q += 1usize
    }
    mmul(w, wa, n, t1)
    mmul(t1, bi, n, wk)
    av[2usize * p3 + 1usize] = tr1 + mtrace(wk, n)
    av[p3 + 2usize] = av[2usize * p3 + 1usize]
    if !ginv(av, p3, avi, wk2) { ret dc.Singular }
    out[0usize] = rho
    out[1usize] = lam
    out[2usize] = 0.0f64 - bobj
    out[3usize] = s2
    out[4usize] = sse
    out[5usize] = math.sqrt[f64](avi[p3 + 1usize])
    out[6usize] = math.sqrt[f64](avi[2usize * p3 + 2usize])
    let (f0, e19) = dc.lm_fit(a, x, n, m, y, 1.0e-7f64)
    if e19 != ok { ret e19 }
    var s0 = 0.0f64
    i = 0usize
    while i < n {
        s0 += f0.residuals[i] * f0.residuals[i]
        i += 1usize
    }
    out[7usize] = lm_loglik(n, s0)
    i = 0usize
    while i < m {
        out[8usize + i] = f2.coef[i]
        out[8usize + m + i] = math.sqrt[f64](avi[(3usize + i) * p3 + 3usize + i])
        i += 1usize
    }
    ret ok
}

// lag impacts from the eigenvalues: out = direct (p), indirect (p), total (p) for the p slopes in beta
fn impacts_eig(re: []const f64, im: []const f64, n: usize, rho: f64, beta: []const f64, p: usize, out: []f64) {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        let a = 1.0f64 - rho * re[i]
        let b = 0.0f64 - rho * im[i]
        s += a / (a * a + b * b)
        i += 1usize
    }
    i = 0usize
    while i < p {
        let direct = (beta[i] * s) / f64(n)
        let total = beta[i] / (1.0f64 - rho)
        out[i] = direct
        out[p + i] = total - direct
        out[2usize * p + i] = total
        i += 1usize
    }
}

// lag impacts from the power-series traces tr(W^k), k = 1..mt - 1 (trW(W, m = mt, type = "mult")): out as impacts_eig
fn impacts_trace(a: *mem.Arena, w: []const f64, n: usize, mt: usize, rho: f64, beta: []const f64, p: usize, out: []f64) -> err {
    let (pw, e1) = mem.alloc[f64](a, n * n)
    let (nx, e2) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n * n {
        pw[i] = w[i]
        i += 1usize
    }
    var dsum = 1.0f64
    var gsum = 1.0f64
    var g = 1.0f64
    var kk = 1usize
    while kk < mt {
        g = g * rho
        var tr = 0.0f64
        i = 0usize
        while i < n {
            tr += pw[i * n + i]
            i += 1usize
        }
        dsum += g * (tr / f64(n))
        gsum += g
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                var s = 0.0f64
                var t = 0usize
                while t < n {
                    s += w[i * n + t] * pw[t * n + j]
                    t += 1usize
                }
                nx[i * n + j] = s
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < n * n {
            pw[i] = nx[i]
            i += 1usize
        }
        kk += 1usize
    }
    i = 0usize
    while i < p {
        let direct = beta[i] * dsum
        let total = beta[i] * gsum
        out[i] = direct
        out[p + i] = total - direct
        out[2usize * p + i] = total
        i += 1usize
    }
    ret ok
}

// lm.RStests on the ols of y on x: out = RSerr, RSlag, adjRSerr, adjRSlag, SARMA statistics then their p values (1 - pchisq)
fn rs_tests(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, m: usize, w: []const f64, out: []f64) -> err {
    let nf = f64(n)
    let (f0, e1) = dc.lm_fit(a, x, n, m, y, 1.0e-7f64)
    if e1 != ok { ret e1 }
    let (u, e2) = mem.alloc[f64](a, n)
    let (yhat, e3) = mem.alloc[f64](a, n)
    let (wu, e4) = mem.alloc[f64](a, n)
    let (wy, e5) = mem.alloc[f64](a, n)
    let (wyh, e6) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var uu = 0.0f64
    var i = 0usize
    while i < n {
        u[i] = f0.residuals[i]
        yhat[i] = y[i] - u[i]
        uu += u[i] * u[i]
        i += 1usize
    }
    let sigma2 = uu / nf
    var trw = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            trw += w[i * n + j] * w[i * n + j] + w[i * n + j] * w[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    matvec(w, n, u, wu)
    matvec(w, n, y, wy)
    matvec(w, n, yhat, wyh)
    let (xtx, e7) = mem.alloc[f64](a, m * m)
    let (xti, e8) = mem.alloc[f64](a, m * m)
    let (wk, e9) = mem.alloc[f64](a, m * m)
    let (xtw, e10) = mem.alloc[f64](a, m)
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    var jc = 0usize
    while jc < m {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += x[jc * n + i] * wyh[i]
            i += 1usize
        }
        xtw[jc] = s
        var jd = 0usize
        while jd < m {
            var q = 0.0f64
            i = 0usize
            while i < n {
                q += x[jc * n + i] * x[jd * n + i]
                i += 1usize
            }
            xtx[jc * m + jd] = q
            jd += 1usize
        }
        jc += 1usize
    }
    if !ginv(xtx, m, xti, wk) { ret dc.Singular }
    var wyhwyh = 0.0f64
    var utwu = 0.0f64
    var utwy = 0.0f64
    i = 0usize
    while i < n {
        wyhwyh += wyh[i] * wyh[i]
        utwu += u[i] * wu[i]
        utwy += u[i] * wy[i]
        i += 1usize
    }
    var quad = 0.0f64
    jc = 0usize
    while jc < m {
        var jd = 0usize
        while jd < m {
            quad += xtw[jc] * xti[jc * m + jd] * xtw[jd]
            jd += 1usize
        }
        jc += 1usize
    }
    let dutwu = utwu / sigma2
    let resa = (dutwu * dutwu) / trw
    let jj = (1.0f64 / (nf * sigma2)) * ((wyhwyh - quad) + trw * sigma2)
    let dutwy = utwy / sigma2
    let nj = nf * jj
    out[0usize] = resa
    out[1usize] = (dutwy * dutwy) / nj
    let adj_e = dutwu - (trw * (1.0f64 / nj)) * dutwy
    out[2usize] = (adj_e * adj_e) / (trw * (1.0f64 - trw * (1.0f64 / nj)))
    let adj_l = dutwy - dutwu
    out[3usize] = (adj_l * adj_l) / (nj - trw)
    out[4usize] = out[3usize] + resa
    i = 0usize
    while i < 5usize {
        var df = 1.0f64
        if i == 4usize { df = 2.0f64 }
        out[5usize + i] = 1.0f64 - nm.pchisq(out[i], df, true, false)
        i += 1usize
    }
    ret ok
}

// lm.morantest: out = I, E, Var, z, p (alt: 0 greater, 1 less, 2 two.sided)
fn lm_moran(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, m: usize, w: []const f64, alt: usize, out: []f64) -> err {
    let nf0 = f64(n)
    let (f0, e1) = dc.lm_fit(a, x, n, m, y, 1.0e-7f64)
    if e1 != ok { ret e1 }
    let (uw, e2) = mem.alloc[f64](a, n * n)
    if e2 != ok { ret e2 }
    var s0 = 0.0f64
    var s1 = 0.0f64
    var eff = 0.0f64
    var i = 0usize
    while i < n {
        var card = 0usize
        var j = 0usize
        while j < n {
            uw[i * n + j] = 0.5f64 * (w[i * n + j] + w[j * n + i])
            s0 += uw[i * n + j]
            s1 += 0.5f64 * (2.0f64 * uw[i * n + j]) * (2.0f64 * uw[i * n + j])
            if w[i * n + j] != 0.0f64 { card += 1usize }
            j += 1usize
        }
        if card > 0usize { eff += 1.0f64 }
        i += 1usize
    }
    var nf = nf0
    nf = eff
    let (lu, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret e3 }
    matvec(uw, n, f0.residuals, lu)
    var ulu = 0.0f64
    var uu = 0.0f64
    i = 0usize
    while i < n {
        ulu += f0.residuals[i] * lu[i]
        uu += f0.residuals[i] * f0.residuals[i]
        i += 1usize
    }
    let ii = (nf / s0) * (ulu / uu)
    let (xtx, e4) = mem.alloc[f64](a, m * m)
    let (xti, e5) = mem.alloc[f64](a, m * m)
    let (wk, e6) = mem.alloc[f64](a, m * m)
    let (z, e7) = mem.alloc[f64](a, n * m)
    let (c1, e8) = mem.alloc[f64](a, m * m)
    let (c2, e9) = mem.alloc[f64](a, m * m)
    let (c3, e10) = mem.alloc[f64](a, m * m)
    let (col, e11) = mem.alloc[f64](a, n)
    let (zc, e12) = mem.alloc[f64](a, n)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    var jc = 0usize
    while jc < m {
        i = 0usize
        while i < n {
            col[i] = x[jc * n + i]
            i += 1usize
        }
        matvec(uw, n, col, zc)
        i = 0usize
        while i < n {
            z[jc * n + i] = zc[i]
            i += 1usize
        }
        jc += 1usize
    }
    jc = 0usize
    while jc < m {
        var jd = 0usize
        while jd < m {
            var q = 0.0f64
            var q1 = 0.0f64
            var q2 = 0.0f64
            i = 0usize
            while i < n {
                q += x[jc * n + i] * x[jd * n + i]
                q1 += x[jc * n + i] * z[jd * n + i]
                q2 += z[jc * n + i] * z[jd * n + i]
                i += 1usize
            }
            xtx[jc * m + jd] = q
            c1[jc * m + jd] = q1
            c2[jc * m + jd] = q2
            jd += 1usize
        }
        jc += 1usize
    }
    if !ginv(xtx, m, xti, wk) { ret dc.Singular }
    var tra = 0.0f64
    var trb = 0.0f64
    var tra2 = 0.0f64
    jc = 0usize
    while jc < m {
        var jd = 0usize
        while jd < m {
            var s = 0.0f64
            var s2 = 0.0f64
            var t = 0usize
            while t < m {
                s += xti[jc * m + t] * c1[t * m + jd]
                s2 += xti[jc * m + t] * c2[t * m + jd]
                t += 1usize
            }
            c3[jc * m + jd] = s
            if jc == jd {
                tra += s
                trb += 4.0f64 * s2
            }
            jd += 1usize
        }
        jc += 1usize
    }
    jc = 0usize
    while jc < m {
        var jd = 0usize
        while jd < m {
            tra2 += c3[jc * m + jd] * c3[jd * m + jc]
            jd += 1usize
        }
        jc += 1usize
    }
    let pf = f64(m)
    let ei = 0.0f64 - ((nf * tra) / ((nf - pf) * s0))
    let vi = ((nf * nf) / ((s0 * s0) * (nf - pf) * (nf - pf + 2.0f64))) * (s1 + 2.0f64 * tra2 - trb - ((2.0f64 * (tra * tra)) / (nf - pf)))
    let zi = (ii - ei) / math.sqrt[f64](vi)
    out[0usize] = ii
    out[1usize] = ei
    out[2usize] = vi
    out[3usize] = zi
    var pv = 0.0f64
    if alt == 0usize { pv = dist.pnorm(zi, 0.0f64, 1.0f64, false, false) }
    if alt == 1usize { pv = dist.pnorm(zi, 0.0f64, 1.0f64, true, false) }
    if alt == 2usize { pv = 2.0f64 * dist.pnorm(math.abs[f64](zi), 0.0f64, 1.0f64, false, false) }
    out[4usize] = pv
    ret ok
}
