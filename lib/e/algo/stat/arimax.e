// TSA::arimax with transfer-function (intervention) terms and innovative-outlier columns: an ARIMA(p, d, q)(P, D, Q)[m] fit by
// "ML" or "CSS-ML" with optim's BFGS (numerical gradient, parscale from lm), the regressors xreg (an intercept first when
// include.mean and no differencing), and for every transfer term the input column filtered by 1 / (1 - d1 B - ...) and
// then by (w0 + w1 B + ...) before it is taken from the series. Columns with more than one regressor are rotated by the
// right singular vectors of xreg exactly as arimax does, and the coefficients and variance are rotated back at the end.
// The objective, the BFGS driver, the Hessian and the state-space filter are those of arimafit (ArCtx with ext set); the
// variance of the transformed AR part uses arimax's analytic Jacobian of the PACF transform.
//
// Not here: missing values in x or the regressors, fixed coefficients, method "CSS", n.cond, init.

use e.math
use e.mem
use e.algo.stat.arimafit as af
use e.algo.stat.olsfit as olsf
use e.algo.linalg.lapack_gesdd as gs

type ArxFit = struct { good: bool, nfree: usize, coef: []f64, sigma2: f64, loglik: f64, aic: f64, vcov: []f64, resid: []f64, code: i64, nused: usize }

// arimax's deriv(u): out[i * p + j] = d phi_j / d u_i for the PACF transform phi = levinson(tanh(u))
fn pacf_jacobian(ar: *mem.Arena, u: []const f64, p: usize, out: []f64) {
    if p == 1usize {
        let e2 = math.exp[f64](2.0f64 * u[0usize])
        out[0usize] = 4.0f64 * e2 / ((1.0f64 + e2) * (1.0f64 + e2))
        ret
    }
    let st = mem.mark(ar)
    let pacf = af.fa(ar, p)
    let oldphi = af.fa(ar, p)
    let newphi = af.fa(ar, p)
    let oldd = af.fa(ar, p)
    let newd = af.fa(ar, p)
    var i = 0usize
    while i < p {
        pacf[i] = af.tanh_r(u[i])
        i += 1usize
    }
    i = 0usize
    while i < p {
        let e2 = math.exp[f64](2.0f64 * u[i])
        let dscale = 4.0f64 * e2 / ((1.0f64 + e2) * (1.0f64 + e2))
        var k = 0usize
        while k < p {
            oldd[k] = 0.0f64
            if k == i { oldd[k] = 1.0f64 }
            k += 1usize
        }
        oldphi[0usize] = pacf[0usize]
        k = 1usize
        while k < p {
            let mult = pacf[k]
            newphi[k] = pacf[k]
            newd[k] = 0.0f64
            if k == i { newd[k] = 1.0f64 }
            let mult1 = newd[k]
            var j = 0usize
            while j < k {
                newphi[j] = oldphi[j] - mult * oldphi[k - 1usize - j]
                newd[j] = oldd[j] - mult * oldd[k - 1usize - j] - mult1 * oldphi[k - 1usize - j]
                j += 1usize
            }
            j = 0usize
            while j <= k {
                oldphi[j] = newphi[j]
                oldd[j] = newd[j]
                j += 1usize
            }
            k += 1usize
        }
        var j2 = 0usize
        while j2 < p {
            out[i * p + j2] = dscale * oldd[j2]
            j2 += 1usize
        }
        i += 1usize
    }
    mem.reset(ar, st)
}

// xr: ncu user columns (n each, column-major) and iof their innovative-outlier flags; tf: nt transfer inputs (n each) with the
// orders (tfp, tfq0) of arimax's transfer = list(c(p, q), ...) (the numerator has q + 1 coefficients); method0 0 CSS-ML, 1 ML.
// The coefficient order is ar, ma, sar, sma, [intercept], xreg columns, then each transfer term's AR then MA coefficients.
fn arimax_fit(ar: *mem.Arena, x: []const f64, p: usize, d: usize, q: usize, sp: usize, sd: usize, sq: usize, per: usize,
              xr: []const f64, iof: []const f64, ncu: usize, mean: bool, tf: []const f64, tfp: []const f64, tfq0: []const f64, nt: usize, method0: usize) -> ArxFit {
    var fit: ArxFit = zero
    fit.good = false
    let n = x.len
    let narma = p + q + sp + sq
    let pl = p + per * sp
    let ql = q + per * sq
    let delta = af.ar_delta(ar, d, sd, per)
    if af.ar_count_ok(x) != n || n <= delta.len { ret fit }
    let nused = n - delta.len
    let addint = mean && d + sd == 0usize
    var ncx = ncu
    if addint { ncx += 1usize }
    let xm = af.fa(ar, n * ncx + 1usize)
    let iofm = af.fa(ar, ncx + 1usize)
    var off = 0usize
    if addint {
        var i0 = 0usize
        while i0 < n {
            xm[i0] = 1.0f64
            i0 += 1usize
        }
        iofm[0usize] = 0.0f64
        off = 1usize
    }
    var k = 0usize
    while k < ncu {
        var i1 = 0usize
        while i1 < n {
            xm[(off + k) * n + i1] = xr[k * n + i1]
            i1 += 1usize
        }
        iofm[off + k] = iof[k]
        k += 1usize
    }
    let tfq = af.fa(ar, nt + 1usize)
    var ntransf = 0usize
    k = 0usize
    while k < nt {
        tfq[k] = tfq0[k] + 1.0f64
        ntransf += usize(tfp[k]) + usize(tfq[k])
        k += 1usize
    }
    // the SVD rotation of several regressors (arimax's orig.xreg is FALSE then)
    let vmat = af.fa(ar, ncx * ncx + 1usize)
    var rotated = false
    if ncx > 1usize {
        rotated = true
        let sv = af.fa(ar, ncx)
        let uu = af.fa(ar, n * ncx + 1usize)
        let vt = af.fa(ar, ncx * ncx)
        if gs.svd_all(ar, xm[0usize..n * ncx], n, ncx, sv, uu, vt) != ok { ret fit }
        var i2 = 0usize
        while i2 < ncx {
            var j2 = 0usize
            while j2 < ncx {
                vmat[i2 + j2 * ncx] = vt[j2 + i2 * ncx]
                j2 += 1usize
            }
            i2 += 1usize
        }
        let rot = af.fa(ar, n * ncx + 1usize)
        var j3 = 0usize
        while j3 < ncx {
            var t = 0usize
            while t < n {
                var s = 0.0f64
                var l = 0usize
                while l < ncx {
                    s += xm[l * n + t] * vmat[l + j3 * ncx]
                    l += 1usize
                }
                rot[j3 * n + t] = s
                t += 1usize
            }
            j3 += 1usize
        }
        var m2 = 0usize
        while m2 < n * ncx {
            xm[m2] = rot[m2]
            m2 += 1usize
        }
    }
    let ntot = narma + ncx + ntransf
    let init = af.fa(ar, ntot + 1usize)
    let parscale = af.fa(ar, ntot + 1usize)
    var i = 0usize
    while i < ntot {
        init[i] = 0.0f64
        parscale[i] = 1.0f64
        i += 1usize
    }
    if ncx > 0usize {
        if addint {
            let (o1, e1) = olsf.fit(ar, xm[0usize..n * ncx], n, ncx, x)
            if e1 != ok { ret fit }
            i = 0usize
            while i < ncx {
                init[narma + i] = o1.coef[i]
                parscale[narma + i] = 10.0f64 * o1.se[i]
                i += 1usize
            }
        } else {
            let dm = af.fa(ar, n * (ncx + 1usize))
            i = 0usize
            while i < n {
                dm[i] = 1.0f64
                i += 1usize
            }
            i = 0usize
            while i < n * ncx {
                dm[n + i] = xm[i]
                i += 1usize
            }
            let (o2, e2) = olsf.fit(ar, dm, n, ncx + 1usize, x)
            if e2 != ok { ret fit }
            i = 0usize
            while i < ncx {
                init[narma + i] = o2.coef[i + 1usize]
                parscale[narma + i] = 10.0f64 * o2.se[i + 1usize]
                i += 1usize
            }
        }
    }
    var at = narma + ncx
    k = 0usize
    while k < nt {
        let dm3 = af.fa(ar, n * 2usize)
        i = 0usize
        while i < n {
            dm3[i] = 1.0f64
            dm3[n + i] = tf[k * n + i]
            i += 1usize
        }
        let (o3, e3) = olsf.fit(ar, dm3, n, 2usize, x)
        if e3 != ok { ret fit }
        let cnt = usize(tfp[k]) + usize(tfq[k])
        i = 0usize
        while i < cnt {
            parscale[at + i] = 10.0f64 * o3.se[1usize]
            i += 1usize
        }
        at += cnt
        k += 1usize
    }
    var method = method0
    let nfree = ntot
    let coefv = af.fa(ar, ntot + 1usize)
    i = 0usize
    while i < ntot {
        coefv[i] = af.ar_nan()
        i += 1usize
    }
    let full = af.fa(ar, ntot + 1usize)
    let gb = af.fa(ar, nfree + 1usize)
    var ncond = 0usize
    if method == 0usize { ncond = d + sd * per + pl }
    var trans = true
    var c = af.ArCtx{ ar: ar, x: x, xreg: xm, p: p, q: q, d: d, narma: narma, ncx: ncx, nfree: nfree, coefv: coefv, delta: delta, kappa: 1.0e6f64, ncond: ncond, trans: trans, mode: 1usize, sp: sp, sq: sq, sd: sd, per: per, parscale: parscale, full: full, gb: gb, bad: false, ext: true, nout: nused, ntr: nt, tf: tf, tfp: tfp, tfq: tfq, iof: iofm }
    let b = af.fa(ar, nfree + 1usize)
    let coef = af.fa(ar, ntot + 1usize)
    var conv = 0i64
    if method == 0usize {
        i = 0usize
        while i < nfree {
            b[i] = init[i] / parscale[i]
            i += 1usize
        }
        let (fv, fl) = af.vmmin_f(ar, &c, b[0usize..nfree], 1.4901161193847656e-08f64, 100usize)
        if fl == 0i64 {
            i = 0usize
            while i < nfree {
                init[i] = b[i] * parscale[i]
                i += 1usize
            }
            // undotrans: the AR blocks back from the PACF scale
            if p > 0usize {
                let ud = af.fa(ar, p)
                af.partrans(p, init[0usize..p], ud)
                i = 0usize
                while i < p {
                    init[i] = ud[i]
                    i += 1usize
                }
            }
            if sp > 0usize {
                let ud2 = af.fa(ar, sp)
                af.partrans(sp, init[p + q..p + q + sp], ud2)
                i = 0usize
                while i < sp {
                    init[p + q + i] = ud2[i]
                    i += 1usize
                }
            }
        }
        if c.bad { ret fit }
        if p > 0usize {
            if !af.ar_check(ar, init[0usize..p]) { ret fit }
        }
        if sp > 0usize {
            if !af.ar_check(ar, init[p + q..p + q + sp]) { ret fit }
        }
        c.ncond = 0usize
    }
    // transformpar: the AR blocks to the PACF scale, the MA blocks inverted
    let inv = af.fa(ar, ntot + 1usize)
    i = 0usize
    while i < ntot {
        inv[i] = init[i]
        i += 1usize
    }
    af.invpartrans(p, init[0usize..p], inv[0usize..p])
    if sp > 0usize { af.invpartrans(sp, init[p + q..p + q + sp], inv[p + q..p + q + sp]) }
    i = 0usize
    while i < ntot {
        init[i] = inv[i]
        i += 1usize
    }
    if q > 0usize { af.ma_invert(ar, init[p..p + q]) }
    if sq > 0usize { af.ma_invert(ar, init[p + q + sp..p + q + sp + sq]) }
    c.mode = 0usize
    c.trans = trans
    c.bad = false
    i = 0usize
    while i < nfree {
        b[i] = init[i] / parscale[i]
        i += 1usize
    }
    let (rv0, cfl) = af.vmmin_f(ar, &c, b[0usize..nfree], 1.4901161193847656e-08f64, 100usize)
    var resvalue = rv0
    conv = cfl
    i = 0usize
    while i < nfree {
        coef[i] = b[i] * parscale[i]
        i += 1usize
    }
    // maInvert on the fitted MA blocks; if it moved them, the value is re-evaluated there (optim with maxit = 0)
    let msv = af.fa(ar, ntot + 1usize)
    i = 0usize
    while i < ntot {
        msv[i] = coef[i]
        i += 1usize
    }
    if q > 0usize { af.ma_invert(ar, coef[p..p + q]) }
    if sq > 0usize { af.ma_invert(ar, coef[p + q + sp..p + q + sp + sq]) }
    var changed = false
    i = 0usize
    while i < ntot {
        if msv[i] != coef[i] { changed = true }
        i += 1usize
    }
    if changed {
        i = 0usize
        while i < nfree {
            b[i] = coef[i] / parscale[i]
            i += 1usize
        }
        resvalue = af.ar_obj(&c, b)
    }
    let hess = af.fa(ar, nfree * nfree + 1usize)
    af.ar_hessian(&c, coef, hess)
    i = 0usize
    while i < nfree * nfree {
        hess[i] = hess[i] * f64(nused)
        i += 1usize
    }
    let vi = af.fa(ar, nfree * nfree + 1usize)
    if !af.invert_checked(ar, hess, nfree, vi) { ret fit }
    // var = A' (H n)^-1 A, A the analytic Jacobian of the AR transforms (identity elsewhere)
    let am = af.fa(ar, nfree * nfree + 1usize)
    i = 0usize
    while i < nfree * nfree {
        am[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nfree {
        am[i * nfree + i] = 1.0f64
        i += 1usize
    }
    var blk = 0usize
    while blk < 2usize {
        var bo = 0usize
        var len = p
        if blk == 1usize {
            bo = p + q
            len = sp
        }
        if len > 0usize {
            let jm = af.fa(ar, len * len)
            pacf_jacobian(ar, coef[bo..bo + len], len, jm)
            var r1 = 0usize
            while r1 < len {
                var c1 = 0usize
                while c1 < len {
                    am[(bo + r1) * nfree + bo + c1] = jm[r1 * len + c1]
                    c1 += 1usize
                }
                r1 += 1usize
            }
        }
        blk += 1usize
    }
    let vcov = af.fa(ar, nfree * nfree + 1usize)
    let t1 = af.fa(ar, nfree * nfree + 1usize)
    i = 0usize
    while i < nfree {
        var j = 0usize
        while j < nfree {
            var s = 0.0f64
            var l = 0usize
            while l < nfree {
                s += vi[i * nfree + l] * am[l * nfree + j]
                l += 1usize
            }
            t1[i * nfree + j] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nfree {
        var j = 0usize
        while j < nfree {
            var s = 0.0f64
            var l = 0usize
            while l < nfree {
                s += am[l * nfree + i] * t1[l * nfree + j]
                l += 1usize
            }
            vcov[i * nfree + j] = s
            j += 1usize
        }
        i += 1usize
    }
    // undotrans
    if p > 0usize {
        let ud = af.fa(ar, p)
        af.partrans(p, coef[0usize..p], ud)
        i = 0usize
        while i < p {
            coef[i] = ud[i]
            i += 1usize
        }
    }
    if sp > 0usize {
        let ud2 = af.fa(ar, sp)
        af.partrans(sp, coef[p + q..p + q + sp], ud2)
        i = 0usize
        while i < sp {
            coef[p + q + i] = ud2[i]
            i += 1usize
        }
    }
    // the final inner fit: sigma2 and the residuals
    let phi = af.fa(ar, pl + 1usize)
    let th0 = af.fa(ar, ql + 1usize)
    af.trans_pars(coef, p, q, sp, sq, per, false, phi[0usize..pl], th0[0usize..ql])
    var r0 = pl
    if ql + 1usize > r0 { r0 = ql + 1usize }
    let theta = af.fa(ar, r0)
    i = 0usize
    while i < ql {
        theta[i] = th0[i]
        i += 1usize
    }
    let x2 = af.fa(ar, n)
    af.ar_ext_x2(&c, coef, phi[0usize..pl], th0[0usize..ql], x2)
    let (mdl, mgood) = af.make_arima(ar, phi[0usize..pl], theta[0usize..r0 - 1usize], delta, 1.0e6f64)
    if !mgood { ret fit }
    var mm = mdl
    let resv = af.fa(ar, n)
    let (ssq, sl, nu2) = af.arima_like(ar, &mm, phi[0usize..pl], theta[0usize..r0 - 1usize], delta, x2, resv)
    let nin = af.ar_count_ok(x2) - delta.len
    // back to the original regressor basis
    if rotated {
        let tmpc = af.fa(ar, ncx)
        i = 0usize
        while i < ncx {
            var s = 0.0f64
            var j = 0usize
            while j < ncx {
                s += vmat[i + j * ncx] * coef[narma + j]
                j += 1usize
            }
            tmpc[i] = s
            i += 1usize
        }
        i = 0usize
        while i < ncx {
            coef[narma + i] = tmpc[i]
            i += 1usize
        }
        let aa = af.fa(ar, nfree * nfree + 1usize)
        i = 0usize
        while i < nfree {
            aa[i * nfree + i] = 1.0f64
            i += 1usize
        }
        i = 0usize
        while i < ncx {
            var j = 0usize
            while j < ncx {
                aa[(narma + i) * nfree + narma + j] = vmat[i + j * ncx]
                j += 1usize
            }
            i += 1usize
        }
        let t2 = af.fa(ar, nfree * nfree + 1usize)
        i = 0usize
        while i < nfree {
            var j = 0usize
            while j < nfree {
                var s = 0.0f64
                var l = 0usize
                while l < nfree {
                    s += aa[i * nfree + l] * vcov[l * nfree + j]
                    l += 1usize
                }
                t2[i * nfree + j] = s
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < nfree {
            var j = 0usize
            while j < nfree {
                var s = 0.0f64
                var l = 0usize
                while l < nfree {
                    s += t2[i * nfree + l] * aa[j * nfree + l]
                    l += 1usize
                }
                vcov[i * nfree + j] = s
                j += 1usize
            }
            i += 1usize
        }
    }
    let value = 2.0f64 * f64(nused) * resvalue + f64(nused) + f64(nused) * math.log[f64](2.0f64 * 3.141592653589793f64)
    fit = ArxFit{ good: true, nfree: nfree, coef: coef[0usize..ntot], sigma2: ssq / f64(nin), loglik: 0.0f64 - 0.5f64 * value, aic: value + 2.0f64 * f64(nfree), vcov: vcov[0usize..nfree * nfree], resid: resv, code: conv, nused: nused }
    ret fit
}
