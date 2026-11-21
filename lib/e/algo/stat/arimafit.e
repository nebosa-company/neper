// R stats::arima (forecast::Arima) with seasonal terms: ARIMA(p, d, q)(P, D, Q)[m] with an optional intercept or drift regressor,
// fitted by "CSS", "ML" or "CSS-ML" with optim's BFGS (numerical gradient, ndeps 1e-3, parscale), the Hessian-based
// check forecast::auto.arima makes (a negative variance means the fit is refused), the information criteria, and the
// state-space model `$model` the fit leaves behind (makeARIMA, then run over the series so a, P and Pn are the final
// filtered state, which is what imputeTS smooths from).
//
// The initial state covariance of the stationary part is R's getQ0 (Gardner 1980, ported step for step), which is what
// SSinit = "Gardner1980" computes. Not here: user regressors, SSinit = "Rossignol2011".

use e.math
use e.math.dist as dist
use e.mem
use e.algo.stat.kalman as kal
use e.algo.stat.lbfgsb as lbf
use e.algo.stat.pracma as pr
use e.algo.stat.olsfit as olsf

type ArCtx = struct {
    ar: *mem.Arena, x: []const f64, xreg: []const f64, p: usize, q: usize, d: usize, narma: usize, ncx: usize,
    nfree: usize, coefv: []f64, delta: []f64, kappa: f64, ncond: usize, trans: bool, mode: usize, sp: usize, sq: usize, sd: usize, per: usize,
    parscale: []f64, full: []f64, gb: []f64, bad: bool
}

type ArFit = struct {
    good: bool, p: usize, q: usize, d: usize, nfree: usize, coef: []f64, aic: f64, value: f64, sigma2: f64, nused: usize,
    model: kal.SsModel, phi: []f64, theta: []f64, varok: bool, convergence: i64, resid: []f64
}

fn fa(ar: *mem.Arena, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](ar, n)
    ret s
}

fn ar_nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }

fn ar_isnan(x: f64) -> bool { ret x != x }

fn tanh_r(x: f64) -> f64 {
    var ax = math.abs[f64](x)
    if ax > 20.0f64 { ax = 20.0f64 }
    let em = dist.expm1(2.0f64 * ax)
    let t = em / (em + 2.0f64)
    if x < 0.0f64 { ret 0.0f64 - t }
    ret t
}

fn atanh_r(y: f64) -> f64 { ret 0.5f64 * (dist.log1p(y) - dist.log1p(0.0f64 - y)) }

// R's partrans: the tanh of the raw values mapped through the Durbin-Levinson recursion to stationary AR coefficients
fn partrans(p: usize, raw: []const f64, newv: []f64) {
    var work: [32]f64 = zero
    var j = 0usize
    while j < p {
        newv[j] = tanh_r(raw[j])
        work[j] = newv[j]
        j += 1usize
    }
    j = 1usize
    while j < p {
        let a1 = newv[j]
        var k = 0usize
        while k < j {
            work[k] -= a1 * newv[j - k - 1usize]
            k += 1usize
        }
        k = 0usize
        while k < j {
            newv[k] = work[k]
            k += 1usize
        }
        j += 1usize
    }
}

fn invpartrans(p: usize, phi: []const f64, newv: []f64) {
    var work: [32]f64 = zero
    var j = 0usize
    while j < p {
        newv[j] = phi[j]
        work[j] = phi[j]
        j += 1usize
    }
    j = p
    while j > 1usize {
        let jj = j - 1usize
        let a1 = newv[jj]
        var k = 0usize
        while k < jj {
            work[k] = (newv[k] + a1 * newv[jj - k - 1usize]) / (1.0f64 - a1 * a1)
            k += 1usize
        }
        k = 0usize
        while k < jj {
            newv[k] = work[k]
            k += 1usize
        }
        j -= 1usize
    }
    j = 0usize
    while j < p {
        newv[j] = atanh_r(newv[j])
        j += 1usize
    }
}

// phi (p) and theta (q) from the parameter vector, the AR part transformed when trans
fn trans_pars(par: []const f64, p: usize, q: usize, sp: usize, sq: usize, per: usize, trans: bool, phi: []f64, theta: []f64) {
    var prm: [64]f64 = zero
    let tot = p + q + sp + sq
    var i = 0usize
    while i < tot {
        prm[i] = par[i]
        i += 1usize
    }
    if trans {
        var tmp: [64]f64 = zero
        if p > 0usize {
            partrans(p, par, tmp[0usize..p])
            i = 0usize
            while i < p {
                prm[i] = tmp[i]
                i += 1usize
            }
        }
        if sp > 0usize {
            partrans(sp, par[p + q..p + q + sp], tmp[0usize..sp])
            i = 0usize
            while i < sp {
                prm[p + q + i] = tmp[i]
                i += 1usize
            }
        }
    }
    i = 0usize
    while i < phi.len {
        phi[i] = 0.0f64
        if i < p { phi[i] = prm[i] }
        i += 1usize
    }
    i = 0usize
    while i < theta.len {
        theta[i] = 0.0f64
        if i < q { theta[i] = prm[p + i] }
        i += 1usize
    }
    var j = 0usize
    while j < sp {
        phi[(j + 1usize) * per - 1usize] += prm[p + q + j]
        i = 0usize
        while i < p {
            phi[(j + 1usize) * per + i] -= prm[i] * prm[p + q + j]
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < sq {
        theta[(j + 1usize) * per - 1usize] += prm[p + q + sp + j]
        i = 0usize
        while i < q {
            theta[(j + 1usize) * per + i] += prm[p + i] * prm[p + q + sp + j]
            i += 1usize
        }
        j += 1usize
    }
}

// AS154 inclu2: includes the row xnext and the value ynext in the Givens triangulation (d, rbar, thetab)
fn inclu2(np: usize, xnext: []const f64, xrow: []f64, ynext0: f64, d: []f64, rbar: []f64, thetab: []f64) {
    var ynext = ynext0
    var i = 0usize
    while i < np {
        xrow[i] = xnext[i]
        i += 1usize
    }
    var ithisr = 0usize
    i = 0usize
    while i < np {
        if xrow[i] != 0.0f64 {
            let xi = xrow[i]
            let di = d[i]
            let dpi = di + xi * xi
            d[i] = dpi
            let cbar = di / dpi
            let sbar = xi / dpi
            var k = i + 1usize
            while k < np {
                let xk = xrow[k]
                let rbthis = rbar[ithisr]
                xrow[k] = xk - xi * rbthis
                rbar[ithisr] = cbar * rbthis + sbar * xk
                ithisr += 1usize
                k += 1usize
            }
            let xk2 = ynext
            ynext = xk2 - xi * thetab[i]
            thetab[i] = cbar * thetab[i] + sbar * xk2
            if di == 0.0f64 { ret }
        } else {
            ithisr = ithisr + np - i - 1usize
        }
        i += 1usize
    }
}

// R's getQ0 (Gardner 1980, the default SSinit): the stationary covariance of the ARMA state, solved by Givens
// triangulation with the equations reordered; r = max(p, q + 1) and outm is r x r. Like R's it never fails, which is also
// why it is inexact for some near-nonstationary models (that is what Arima reports).
fn get_q0(ar: *mem.Arena, phi: []const f64, theta: []const f64, r: usize, outm: []f64) -> bool {
    let p = phi.len
    let q = theta.len
    if r == 1usize {
        outm[0usize] = 1.0f64
        if p > 0usize { outm[0usize] = 1.0f64 / (1.0f64 - phi[0usize] * phi[0usize]) }
        ret true
    }
    let np = r * (r + 1usize) / 2usize
    let nrbar = np * (np - 1usize) / 2usize
    let st = mem.mark(ar)
    let xnext = fa(ar, np)
    let xrow = fa(ar, np)
    let rbar = fa(ar, nrbar)
    let thetab = fa(ar, np)
    let vv = fa(ar, np)
    let pp = fa(ar, r * r)
    var ind = 0usize
    var j = 0usize
    var i = 0usize
    while j < r {
        var vj = 0.0f64
        if j == 0usize { vj = 1.0f64 } else if j - 1usize < q { vj = theta[j - 1usize] }
        i = j
        while i < r {
            var vi = 0.0f64
            if i == 0usize { vi = 1.0f64 } else if i - 1usize < q { vi = theta[i - 1usize] }
            vv[ind] = vi * vj
            ind += 1usize
            i += 1usize
        }
        j += 1usize
    }
    if p > 0usize {
        i = 0usize
        while i < nrbar {
            rbar[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < np {
            pp[i] = 0.0f64
            thetab[i] = 0.0f64
            xnext[i] = 0.0f64
            i += 1usize
        }
        ind = 0usize
        var ind1 = 0i64 - 1i64
        let npr = np - r
        let npr1 = npr + 1usize
        var indj = npr
        var ind2 = i64(npr) - 1i64
        j = 0usize
        while j < r {
            var phij = 0.0f64
            if j < p { phij = phi[j] }
            xnext[indj] = 0.0f64
            indj += 1usize
            var indi = npr1 + j
            i = j
            while i < r {
                let ynext = vv[ind]
                ind += 1usize
                var phii = 0.0f64
                if i < p { phii = phi[i] }
                if j != r - 1usize {
                    xnext[indj] = 0.0f64 - phii
                    if i != r - 1usize {
                        xnext[indi] -= phij
                        ind1 += 1i64
                        xnext[usize(ind1)] = 0.0f64 - 1.0f64
                    }
                }
                xnext[npr] = 0.0f64 - phii * phij
                ind2 += 1i64
                if usize(ind2) >= np { ind2 = 0i64 }
                xnext[usize(ind2)] += 1.0f64
                inclu2(np, xnext, xrow, ynext, pp, rbar, thetab)
                xnext[usize(ind2)] = 0.0f64
                if i != r - 1usize {
                    xnext[indi] = 0.0f64
                    indi += 1usize
                    xnext[usize(ind1)] = 0.0f64
                }
                i += 1usize
            }
            j += 1usize
        }
        var ithisr = i64(nrbar) - 1i64
        var im = i64(np) - 1i64
        i = 0usize
        while i < np {
            var bi = thetab[usize(im)]
            var jm = i64(np) - 1i64
            j = 0usize
            while j < i {
                bi -= rbar[usize(ithisr)] * pp[usize(jm)]
                ithisr -= 1i64
                jm -= 1i64
                j += 1usize
            }
            pp[usize(im)] = bi
            im -= 1i64
            i += 1usize
        }
        ind = npr
        i = 0usize
        while i < r {
            xnext[i] = pp[ind]
            ind += 1usize
            i += 1usize
        }
        i = 0usize
        while i < npr {
            pp[np - 1usize - i] = pp[npr - 1usize - i]
            i += 1usize
        }
        i = 0usize
        while i < r {
            pp[i] = xnext[i]
            i += 1usize
        }
    } else {
        var indn = np
        ind = np
        i = 0usize
        while i < r {
            j = 0usize
            while j <= i {
                ind -= 1usize
                pp[ind] = vv[ind]
                if j != 0usize {
                    indn -= 1usize
                    pp[ind] += pp[indn]
                }
                j += 1usize
            }
            i += 1usize
        }
    }
    ind = np
    i = r - 1usize
    while i > 0usize {
        j = r - 1usize
        while j >= i {
            ind -= 1usize
            pp[r * i + j] = pp[ind]
            j -= 1usize
        }
        i -= 1usize
    }
    i = 0usize
    while i + 1usize < r {
        j = i + 1usize
        while j < r {
            pp[i + r * j] = pp[j + r * i]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < r * r {
        outm[i] = pp[i]
        i += 1usize
    }
    mem.reset(ar, st)
    ret true
}

// stats::makeARIMA(phi, theta, Delta, kappa); good is false when the initial covariance cannot be formed
fn make_arima(ar: *mem.Arena, phi: []const f64, theta: []const f64, delta: []const f64, kappa: f64) -> (kal.SsModel, bool) {
    let p = phi.len
    let q = theta.len
    var r = p
    if q + 1usize > r { r = q + 1usize }
    let d = delta.len
    let rd = r + d
    let tm = fa(ar, rd * rd)
    let zv = fa(ar, rd)
    let vm = fa(ar, rd * rd)
    let av = fa(ar, rd)
    let pm = fa(ar, rd * rd)
    let pn = fa(ar, rd * rd)
    let rv = fa(ar, rd)
    var i = 0usize
    while i < rd * rd {
        tm[i] = 0.0f64
        pm[i] = 0.0f64
        pn[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < rd {
        zv[i] = 0.0f64
        av[i] = 0.0f64
        rv[i] = 0.0f64
        i += 1usize
    }
    zv[0usize] = 1.0f64
    i = 0usize
    while i < d {
        zv[r + i] = delta[i]
        i += 1usize
    }
    i = 0usize
    while i < p {
        tm[i * rd] = phi[i]
        i += 1usize
    }
    i = 0usize
    while i + 1usize < r {
        tm[i * rd + i + 1usize] = 1.0f64
        i += 1usize
    }
    if d > 0usize {
        i = 0usize
        while i < rd {
            tm[r * rd + i] = zv[i]
            i += 1usize
        }
        i = 1usize
        while i < d {
            tm[(r + i) * rd + (r + i - 1usize)] = 1.0f64
            i += 1usize
        }
    }
    rv[0usize] = 1.0f64
    i = 0usize
    while i < q {
        rv[1usize + i] = theta[i]
        i += 1usize
    }
    i = 0usize
    while i < rd {
        var j = 0usize
        while j < rd {
            vm[i * rd + j] = rv[i] * rv[j]
            j += 1usize
        }
        i += 1usize
    }
    var good = true
    if r > 1usize {
        let q0 = fa(ar, r * r)
        good = get_q0(ar, phi, theta, r, q0)
        if good {
            i = 0usize
            while i < r {
                var j = 0usize
                while j < r {
                    pn[i * rd + j] = q0[i * r + j]
                    j += 1usize
                }
                i += 1usize
            }
        }
    } else {
        if p > 0usize { pn[0usize] = 1.0f64 / (1.0f64 - phi[0usize] * phi[0usize]) } else { pn[0usize] = 1.0f64 }
    }
    i = 0usize
    while i < d {
        pn[(r + i) * rd + r + i] = kappa
        i += 1usize
    }
    ret (kal.SsModel{ p: rd, tm: tm, zv: zv, h: 0.0f64, vm: vm, av: av, pm: pm, pn: pn }, good)
}

// ARIMA_CSS: the conditional sum of squares per observation (NaN terms skipped); resid receives the residuals when not empty
fn css_value(ar: *mem.Arena, y: []const f64, p: usize, q: usize, d: usize, sd: usize, per: usize, phi: []const f64, theta: []const f64, ncond: usize, resid: []f64) -> f64 {
    let n = y.len
    let st = mem.mark(ar)
    let w = fa(ar, n)
    let rs = fa(ar, n)
    var i = 0usize
    while i < n {
        w[i] = y[i]
        rs[i] = 0.0f64
        i += 1usize
    }
    var k = 0usize
    while k < d {
        var l = n
        while l > 1usize {
            w[l - 1usize] -= w[l - 2usize]
            l -= 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < sd {
        var l2 = n
        while l2 > per {
            w[l2 - 1usize] -= w[l2 - 1usize - per]
            l2 -= 1usize
        }
        k += 1usize
    }
    var ssq = 0.0f64
    var nu = 0usize
    var l = ncond
    while l < n {
        var tmp = w[l]
        var j = 0usize
        while j < p {
            if l >= j + 1usize { tmp -= phi[j] * w[l - j - 1usize] }
            j += 1usize
        }
        var jm = q
        if l - ncond < jm { jm = l - ncond }
        j = 0usize
        while j < jm {
            if l >= j + 1usize { tmp -= theta[j] * rs[l - j - 1usize] }
            j += 1usize
        }
        rs[l] = tmp
        if !ar_isnan(tmp) {
            nu += 1usize
            ssq += tmp * tmp
        }
        l += 1usize
    }
    if resid.len > 0usize {
        i = 0usize
        while i < n {
            resid[i] = rs[i]
            i += 1usize
        }
    }
    mem.reset(ar, st)
    ret ssq / f64(nu)
}

// ARIMA_Like: the Kalman filter for the ARIMA state with the structure of T used (the C routine of stats, term by term); P and Pn are
// column-major here (they are symmetric). The first step uses Pn as it stands, later steps recompute it from P. A gain of 1e4 or more
// (the diffuse start of a differenced series) is left out of the sums. Returns (sum of squares, sum of logs, count); the model is changed in place.
fn arima_like(ar: *mem.Arena, m: *kal.SsModel, phi: []const f64, theta: []const f64, delta: []const f64, y: []const f64, resid: []f64) -> (f64, f64, usize) {
    let rd = m.p
    let p = phi.len
    let q = theta.len
    let d = delta.len
    let r = rd - d
    let n = y.len
    let st = mem.mark(ar)
    let anew = fa(ar, rd)
    let mv = fa(ar, rd)
    let mm = fa(ar, rd * rd)
    var ssq = 0.0f64
    var sumlog = 0.0f64
    var nu = 0usize
    var l = 0usize
    while l < n {
        var i = 0usize
        while i < r {
            var tmp = 0.0f64
            if i + 1usize < r { tmp = m.av[i + 1usize] }
            if i < p { tmp += phi[i] * m.av[0usize] }
            anew[i] = tmp
            i += 1usize
        }
        if d > 0usize {
            i = r + 1usize
            while i < rd {
                anew[i] = m.av[i - 1usize]
                i += 1usize
            }
            var tmp = m.av[0usize]
            i = 0usize
            while i < d {
                tmp += delta[i] * m.av[r + i]
                i += 1usize
            }
            anew[r] = tmp
        }
        if l > 0usize {
            if d == 0usize {
                i = 0usize
                while i < r {
                    var vi = 0.0f64
                    if i == 0usize {
                        vi = 1.0f64
                    } else if i - 1usize < q {
                        vi = theta[i - 1usize]
                    }
                    var j = 0usize
                    while j < r {
                        var tmp = 0.0f64
                        if j == 0usize {
                            tmp = vi
                        } else if j - 1usize < q {
                            tmp = vi * theta[j - 1usize]
                        }
                        if i < p && j < p { tmp += phi[i] * phi[j] * m.pm[0usize] }
                        if i + 1usize < r && j + 1usize < r { tmp += m.pm[i + 1usize + r * (j + 1usize)] }
                        if i < p && j + 1usize < r { tmp += phi[i] * m.pm[j + 1usize] }
                        if j < p && i + 1usize < r { tmp += phi[j] * m.pm[i + 1usize] }
                        m.pn[i + r * j] = tmp
                        j += 1usize
                    }
                    i += 1usize
                }
            } else {
                i = 0usize
                while i < r {
                    var j = 0usize
                    while j < rd {
                        var tmp = 0.0f64
                        if i < p { tmp += phi[i] * m.pm[rd * j] }
                        if i + 1usize < r { tmp += m.pm[i + 1usize + rd * j] }
                        mm[i + rd * j] = tmp
                        j += 1usize
                    }
                    i += 1usize
                }
                var j = 0usize
                while j < rd {
                    var tmp = m.pm[rd * j]
                    var k = 0usize
                    while k < d {
                        tmp += delta[k] * m.pm[r + k + rd * j]
                        k += 1usize
                    }
                    mm[r + rd * j] = tmp
                    j += 1usize
                }
                i = 1usize
                while i < d {
                    j = 0usize
                    while j < rd {
                        mm[r + i + rd * j] = m.pm[r + i - 1usize + rd * j]
                        j += 1usize
                    }
                    i += 1usize
                }
                i = 0usize
                while i < r {
                    j = 0usize
                    while j < rd {
                        var tmp = 0.0f64
                        if i < p { tmp += phi[i] * mm[j] }
                        if i + 1usize < r { tmp += mm[rd * (i + 1usize) + j] }
                        m.pn[j + rd * i] = tmp
                        j += 1usize
                    }
                    i += 1usize
                }
                j = 0usize
                while j < rd {
                    var tmp = mm[j]
                    var k = 0usize
                    while k < d {
                        tmp += delta[k] * mm[rd * (r + k) + j]
                        k += 1usize
                    }
                    m.pn[rd * r + j] = tmp
                    j += 1usize
                }
                i = 1usize
                while i < d {
                    j = 0usize
                    while j < rd {
                        m.pn[rd * (r + i) + j] = mm[rd * (r + i - 1usize) + j]
                        j += 1usize
                    }
                    i += 1usize
                }
                i = 0usize
                while i <= q {
                    var ti = 1.0f64
                    if i > 0usize { ti = theta[i - 1usize] }
                    j = 0usize
                    while j <= q {
                        var tj = 1.0f64
                        if j > 0usize { tj = theta[j - 1usize] }
                        m.pn[i + rd * j] += ti * tj
                        j += 1usize
                    }
                    i += 1usize
                }
            }
        }
        if !ar_isnan(y[l]) {
            var resid0 = y[l] - anew[0usize]
            var i2 = 0usize
            while i2 < d {
                resid0 -= delta[i2] * anew[r + i2]
                i2 += 1usize
            }
            i2 = 0usize
            while i2 < rd {
                var tmp = m.pn[i2]
                var j2 = 0usize
                while j2 < d {
                    tmp += m.pn[i2 + (r + j2) * rd] * delta[j2]
                    j2 += 1usize
                }
                mv[i2] = tmp
                i2 += 1usize
            }
            var gain = mv[0usize]
            i2 = 0usize
            while i2 < d {
                gain += delta[i2] * mv[r + i2]
                i2 += 1usize
            }
            if gain < 1.0e4f64 {
                nu += 1usize
                ssq += resid0 * resid0 / gain
                sumlog += math.log[f64](gain)
            }
            if resid.len > l { resid[l] = resid0 / math.sqrt[f64](gain) }
            i2 = 0usize
            while i2 < rd {
                m.av[i2] = anew[i2] + mv[i2] * resid0 / gain
                i2 += 1usize
            }
            i2 = 0usize
            while i2 < rd {
                var j2 = 0usize
                while j2 < rd {
                    m.pm[i2 + j2 * rd] = m.pn[i2 + j2 * rd] - mv[i2] * mv[j2] / gain
                    j2 += 1usize
                }
                i2 += 1usize
            }
        } else {
            if resid.len > l { resid[l] = ar_nan() }
            var i2 = 0usize
            while i2 < rd {
                m.av[i2] = anew[i2]
                i2 += 1usize
            }
            i2 = 0usize
            while i2 < rd * rd {
                m.pm[i2] = m.pn[i2]
                i2 += 1usize
            }
        }
        l += 1usize
    }
    mem.reset(ar, st)
    ret (ssq, sumlog, nu)
}

// the objective in scaled coordinates: the Gaussian ML (mode 0) or half the log CSS (mode 1)
fn ar_obj(c: *ArCtx, b: []const f64) -> f64 {
    let full = c.full
    var i = 0usize
    while i < c.nfree {
        full[i] = b[i] * c.parscale[i]
        i += 1usize
    }
    while i < c.narma + c.ncx {
        full[i] = c.coefv[i]
        i += 1usize
    }
    let n = c.x.len
    let st = mem.mark(c.ar)
    let phi = fa(c.ar, c.p + c.per * c.sp)
    let theta = fa(c.ar, c.q + c.per * c.sq)
    let x2 = fa(c.ar, n)
    i = 0usize
    while i < n {
        x2[i] = c.x[i]
        if c.ncx > 0usize { x2[i] = c.x[i] - c.xreg[i] * full[c.narma] }
        i += 1usize
    }
    var res = 0.0f64
    if c.mode == 1usize {
        trans_pars(full, c.p, c.q, c.sp, c.sq, c.per, false, phi, theta)
        let v = css_value(c.ar, x2, phi.len, theta.len, c.d, c.sd, c.per, phi, theta, c.ncond, zero)
        res = 0.5f64 * math.log[f64](v)
    } else {
        trans_pars(full, c.p, c.q, c.sp, c.sq, c.per, c.trans, phi, theta)
        let (mdl, good) = make_arima(c.ar, phi, theta, c.delta, c.kappa)
        if !good {
            res = 1.7976931348623157e308f64
        } else {
            var m = mdl
            let (ssq, sumlog, nu) = arima_like(c.ar, &m, phi, theta, c.delta, x2, x2[0usize..0usize])
            let s2 = ssq / f64(nu)
            res = 0.5f64 * (math.log[f64](s2) + sumlog / f64(nu))
        }
    }
    mem.reset(c.ar, st)
    ret res
}

// optim's numerical gradient (central differences, ndeps 1e-3) in scaled coordinates
fn ar_grad(c: *ArCtx, b: []const f64, g: []f64) {
    let eps = 0.001f64
    var i = 0usize
    while i < c.nfree {
        c.gb[i] = b[i]
        i += 1usize
    }
    i = 0usize
    while i < c.nfree {
        c.gb[i] = b[i] + eps
        let v1 = ar_obj(c, c.gb)
        c.gb[i] = b[i] - eps
        let v2 = ar_obj(c, c.gb)
        g[i] = (v1 - v2) / (2.0f64 * eps)
        if !(g[i] - g[i] == 0.0f64) { c.bad = true }
        c.gb[i] = b[i]
        i += 1usize
    }
}

// R's vmmin (optim BFGS, abstol -Inf); b is the start and the answer; returns (minimum, fail code)
fn vmmin_f(ar: *mem.Arena, c: *ArCtx, b: []f64, reltol: f64, maxit: usize) -> (f64, i64) {
    let n = b.len
    var f = ar_obj(c, b)
    if maxit == 0usize { ret (f, 0i64) }
    if !(f - f == 0.0f64) {
        c.bad = true
        ret (f, 1i64)
    }
    let g = fa(ar, n)
    let t = fa(ar, n)
    let xv = fa(ar, n)
    let cv = fa(ar, n)
    let bm = fa(ar, n * n)
    var fmin = f
    ar_grad(c, b, g)
    var gradcount = 1usize
    var iter = 1usize
    var ilast = gradcount
    var count = 0usize
    var go = true
    while go {
        var i = 0usize
        if ilast == gradcount {
            i = 0usize
            while i < n {
                var j = 0usize
                while j < i {
                    bm[i * n + j] = 0.0f64
                    j += 1usize
                }
                bm[i * n + i] = 1.0f64
                i += 1usize
            }
        }
        i = 0usize
        while i < n {
            xv[i] = b[i]
            cv[i] = g[i]
            i += 1usize
        }
        var gradproj = 0.0f64
        i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j <= i {
                s -= bm[i * n + j] * g[j]
                j += 1usize
            }
            j = i + 1usize
            while j < n {
                s -= bm[j * n + i] * g[j]
                j += 1usize
            }
            t[i] = s
            gradproj += s * g[i]
            i += 1usize
        }
        if gradproj < 0.0f64 {
            var steplength = 1.0f64
            var accpoint = false
            var again = true
            while again {
                count = 0usize
                i = 0usize
                while i < n {
                    b[i] = xv[i] + steplength * t[i]
                    if 10.0f64 + xv[i] == 10.0f64 + b[i] { count += 1usize }
                    i += 1usize
                }
                if count < n {
                    f = ar_obj(c, b)
                    accpoint = f - f == 0.0f64 && f <= fmin + gradproj * steplength * 0.0001f64
                    if !accpoint { steplength *= 0.2f64 }
                }
                again = !(count == n || accpoint)
            }
            let enough = math.abs[f64](f - fmin) > reltol * (math.abs[f64](fmin) + reltol)
            if !enough {
                count = n
                fmin = f
            }
            if count < n {
                fmin = f
                ar_grad(c, b, g)
                gradcount += 1usize
                iter += 1usize
                var d1 = 0.0f64
                i = 0usize
                while i < n {
                    t[i] = steplength * t[i]
                    cv[i] = g[i] - cv[i]
                    d1 += t[i] * cv[i]
                    i += 1usize
                }
                if d1 > 0.0f64 {
                    var d2 = 0.0f64
                    i = 0usize
                    while i < n {
                        var s = 0.0f64
                        var j = 0usize
                        while j <= i {
                            s += bm[i * n + j] * cv[j]
                            j += 1usize
                        }
                        j = i + 1usize
                        while j < n {
                            s += bm[j * n + i] * cv[j]
                            j += 1usize
                        }
                        xv[i] = s
                        d2 += s * cv[i]
                        i += 1usize
                    }
                    d2 = 1.0f64 + d2 / d1
                    i = 0usize
                    while i < n {
                        var j = 0usize
                        while j <= i {
                            bm[i * n + j] += (d2 * t[i] * t[j] - xv[i] * t[j] - t[i] * xv[j]) / d1
                            j += 1usize
                        }
                        i += 1usize
                    }
                } else {
                    ilast = gradcount
                }
            } else if ilast < gradcount {
                count = 0usize
                ilast = gradcount
            }
        } else {
            count = 0usize
            if ilast == gradcount { count = n } else { ilast = gradcount }
        }
        if iter >= maxit { go = false }
        if go {
            if gradcount - ilast > 2usize * n { ilast = gradcount }
            go = count != n || ilast != gradcount
        }
    }
    var fail = 0i64
    if iter >= maxit { fail = 1i64 }
    ret (fmin, fail)
}

// optimhess in scaled coordinates at the unscaled parameters pv: the symmetrised Hessian of the objective, nfree x nfree
fn ar_hessian(c: *ArCtx, pv: []const f64, hess: []f64) {
    let n = c.nfree
    let ar = c.ar
    let st = mem.mark(ar)
    let dpar = fa(ar, n)
    let df1 = fa(ar, n)
    let df2 = fa(ar, n)
    var i = 0usize
    while i < n {
        dpar[i] = pv[i] / c.parscale[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        let eps = 0.001f64 / c.parscale[i]
        dpar[i] = dpar[i] + eps
        ar_grad(c, dpar, df1)
        dpar[i] = dpar[i] - eps - eps
        ar_grad(c, dpar, df2)
        var j = 0usize
        while j < n {
            hess[i * n + j] = (df1[j] - df2[j]) / (2.0f64 * eps * c.parscale[i] * c.parscale[j])
            j += 1usize
        }
        dpar[i] = dpar[i] + eps
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < i {
            let tmp = 0.5f64 * (hess[i * n + j] + hess[j * n + i])
            hess[i * n + j] = tmp
            hess[j * n + i] = tmp
            j += 1usize
        }
        i += 1usize
    }
    mem.reset(ar, st)
}

// the 1-norm of an n x n row-major matrix
fn norm1(a1: []const f64, n: usize) -> f64 {
    var best = 0.0f64
    var j = 0usize
    while j < n {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += math.abs[f64](a1[i * n + j])
            i += 1usize
        }
        if s > best { best = s }
        j += 1usize
    }
    ret best
}

// inv = a^-1 for the n x n row-major a; false when singular to working precision (R's solve: rcond < eps)
fn invert_checked(ar: *mem.Arena, a1: []const f64, n: usize, inv: []f64) -> bool {
    let st = mem.mark(ar)
    let wk = fa(ar, n * n)
    let bv = fa(ar, n)
    var good = true
    var c = 0usize
    while c < n && good {
        var i = 0usize
        while i < n * n {
            wk[i] = a1[i]
            if !(a1[i] - a1[i] == 0.0f64) { good = false }
            i += 1usize
        }
        i = 0usize
        while i < n {
            bv[i] = 0.0f64
            i += 1usize
        }
        bv[c] = 1.0f64
        if good { good = lbf.lb_solve(wk, bv, n) }
        if good {
            i = 0usize
            while i < n {
                inv[i * n + c] = bv[i]
                i += 1usize
            }
        }
        c += 1usize
    }
    if good {
        let rc = 1.0f64 / (norm1(a1, n) * norm1(inv, n))
        if !(rc >= 2.220446049250313e-16f64) { good = false }
    }
    mem.reset(ar, st)
    ret good
}

fn last_nonzero(v: []const f64) -> usize {
    var k = 0usize
    var i = 0usize
    while i < v.len {
        if v[i] != 0.0f64 { k = i + 1usize }
        i += 1usize
    }
    ret k
}

// arCheck: the roots of 1 - ar1 z - ... all lie outside the unit circle
fn ar_check(ar: *mem.Arena, phi: []const f64) -> bool {
    let p = last_nonzero(phi)
    if p == 0usize { ret true }
    let st = mem.mark(ar)
    let z = fa(ar, p + 1usize)
    let re = fa(ar, p)
    let im = fa(ar, p)
    z[0usize] = 1.0f64
    var i = 0usize
    while i < p {
        z[i + 1usize] = 0.0f64 - phi[i]
        i += 1usize
    }
    let deg = pr.polyroot_c(ar, z, re, im)
    var good = deg >= 0i64
    i = 0usize
    while good && i < usize(deg) {
        if !(math.sqrt[f64](re[i] * re[i] + im[i] * im[i]) > 1.0f64) { good = false }
        i += 1usize
    }
    mem.reset(ar, st)
    ret good
}

// maInvert: moves any root of the MA polynomial inside the unit circle to its reciprocal; ma is replaced in place
fn ma_invert(ar: *mem.Arena, ma: []f64) {
    let q = ma.len
    let q0 = last_nonzero(ma)
    if q0 == 0usize { ret }
    let st = mem.mark(ar)
    let z = fa(ar, q0 + 1usize)
    let re = fa(ar, q0)
    let im = fa(ar, q0)
    z[0usize] = 1.0f64
    var i = 0usize
    while i < q0 {
        z[i + 1usize] = ma[i]
        i += 1usize
    }
    let deg = pr.polyroot_c(ar, z, re, im)
    if deg < 0i64 {
        mem.reset(ar, st)
        ret
    }
    var anyin = false
    i = 0usize
    while i < q0 {
        if math.sqrt[f64](re[i] * re[i] + im[i] * im[i]) < 1.0f64 { anyin = true }
        i += 1usize
    }
    if !anyin {
        mem.reset(ar, st)
        ret
    }
    if q0 == 1usize {
        let v = 1.0f64 / ma[0usize]
        ma[0usize] = v
        i = 1usize
        while i < q {
            ma[i] = 0.0f64
            i += 1usize
        }
        mem.reset(ar, st)
        ret
    }
    i = 0usize
    while i < q0 {
        let md2 = re[i] * re[i] + im[i] * im[i]
        if math.sqrt[f64](md2) < 1.0f64 {
            re[i] = re[i] / md2
            im[i] = 0.0f64 - im[i] / md2
        }
        i += 1usize
    }
    let xr = fa(ar, q0 + 2usize)
    let xi = fa(ar, q0 + 2usize)
    xr[0usize] = 1.0f64
    xi[0usize] = 0.0f64
    var len = 1usize
    i = 0usize
    while i < q0 {
        // x <- c(x, 0) - c(0, x) / root
        let md2 = re[i] * re[i] + im[i] * im[i]
        let ir = re[i] / md2
        let ii = 0.0f64 - im[i] / md2
        var k = len
        while k > 0usize {
            // new[k] = old[k] - old[k-1] * (1/root); computed from the top so old values are still in place
            let ore = xr[k - 1usize]
            let oim = xi[k - 1usize]
            let pre = ore * ir - oim * ii
            let pim = ore * ii + oim * ir
            if k == len {
                xr[k] = 0.0f64 - pre
                xi[k] = 0.0f64 - pim
            } else {
                xr[k] = xr[k] - pre
                xi[k] = xi[k] - pim
            }
            k -= 1usize
        }
        len += 1usize
        i += 1usize
    }
    i = 0usize
    while i < q0 {
        ma[i] = xr[i + 1usize]
        i += 1usize
    }
    i = q0
    while i < q {
        ma[i] = 0.0f64
        i += 1usize
    }
    mem.reset(ar, st)
}

// arima(x, order = c(p, d, q), include.mean, xreg = intercept (kind 1) or drift (kind 2) with the coefficient free (xfixed NaN) or fixed,
// method 0 CSS-ML, 1 ML, 2 CSS)
fn arima_fit(ar: *mem.Arena, x: []const f64, p: usize, d: usize, q: usize, kind: usize, xfixed: f64, method0: usize) -> ArFit {
    let f0 = arima_fit_s(ar, x, p, d, q, 0usize, 0usize, 0usize, 1usize, kind, xfixed, method0)
    ret f0
}

// arima with a seasonal part: (P, D, Q) = (sp, sd, sq) of period per; the coefficient layout is ar, ma, sar, sma, regressor
fn arima_fit_s(ar: *mem.Arena, x: []const f64, p: usize, d: usize, q: usize, sp: usize, sd: usize, sq: usize, per: usize, kind: usize, xfixed: f64, method0: usize) -> ArFit {
    var fit: ArFit = zero
    fit.good = false
    let n = x.len
    let narma = p + q + sp + sq
    let pl = p + per * sp
    let ql = q + per * sq
    var ncx = 0usize
    if kind > 0usize { ncx = 1usize }
    let xreg = fa(ar, n)
    let resv = fa(ar, n)
    var i = 0usize
    while i < n {
        xreg[i] = 1.0f64
        if kind == 2usize { xreg[i] = f64(i + 1usize) }
        i += 1usize
    }
    var method = method0
    var nna = 0usize
    var anyna = false
    i = 0usize
    while i < n {
        if ar_isnan(x[i]) { anyna = true } else { nna += 1usize }
        i += 1usize
    }
    if method == 0usize && anyna { method = 1usize }
    let dtot = d + sd * per
    if nna <= dtot { ret fit }
    let nused = nna - dtot
    var ncond = 0usize
    if method != 1usize { ncond = dtot + pl }
    // Delta: the differencing polynomial
    let delta = fa(ar, dtot)
    let dpoly = fa(ar, dtot + 2usize)
    i = 0usize
    while i < dtot + 2usize {
        dpoly[i] = 0.0f64
        i += 1usize
    }
    dpoly[0usize] = 1.0f64
    var dl = 1usize
    var k = 0usize
    while k < d + sd {
        var lag = 1usize
        if k >= d { lag = per }
        var j = dl + lag - 1usize
        while j >= lag {
            dpoly[j] = dpoly[j] - dpoly[j - lag]
            j -= 1usize
        }
        dl += lag
        k += 1usize
    }
    i = 0usize
    while i < dtot {
        delta[i] = 0.0f64 - dpoly[i + 1usize]
        i += 1usize
    }
    var xfree = false
    if ncx == 1usize && ar_isnan(xfixed) { xfree = true }
    var nfree = narma
    if xfree { nfree = narma + 1usize }
    let noopt = nfree == 0usize
    var trans = !noopt
    let ntot = narma + ncx
    let init = fa(ar, ntot)
    let parscale = fa(ar, ntot)
    i = 0usize
    while i < ntot {
        init[i] = 0.0f64
        parscale[i] = 1.0f64
        i += 1usize
    }
    if xfree {
        // lm(dx ~ dxreg - 1, na.omit) on the differenced series, else on the series
        let dx = fa(ar, n)
        let dxr = fa(ar, n)
        i = 0usize
        while i < n {
            dx[i] = x[i]
            dxr[i] = xreg[i]
            i += 1usize
        }
        var dn = n
        k = 0usize
        while k < d {
            i = 0usize
            while i + 1usize < dn {
                dx[i] = dx[i + 1usize] - dx[i]
                dxr[i] = dxr[i + 1usize] - dxr[i]
                i += 1usize
            }
            dn -= 1usize
            k += 1usize
        }
        k = 0usize
        while k < sd {
            i = 0usize
            while i + per < dn {
                dx[i] = dx[i + per] - dx[i]
                dxr[i] = dxr[i + per] - dxr[i]
                i += 1usize
            }
            dn -= per
            k += 1usize
        }
        var sxy = 0.0f64
        var sxx = 0.0f64
        var cnt = 0usize
        var useraw = false
        if dn <= 1usize { useraw = true }
        if !useraw {
            i = 0usize
            while i < dn {
                if !ar_isnan(dx[i]) {
                    sxy += dx[i] * dxr[i]
                    sxx += dxr[i] * dxr[i]
                    cnt += 1usize
                }
                i += 1usize
            }
            if sxx == 0.0f64 { useraw = true }
        }
        var sdx: []const f64 = dx
        var sdr: []const f64 = dxr
        var sn = dn
        if useraw {
            sdx = x
            sdr = xreg
            sn = n
            sxy = 0.0f64
            sxx = 0.0f64
            cnt = 0usize
            i = 0usize
            while i < sn {
                if !ar_isnan(sdx[i]) {
                    sxy += sdx[i] * sdr[i]
                    sxx += sdr[i] * sdr[i]
                    cnt += 1usize
                }
                i += 1usize
            }
        }
        if cnt == 0usize || sxx == 0.0f64 { ret fit }
        // lm(dx ~ dxreg - 1): the QR coefficient and standard error, as summary(lm) computes them
        let cy = fa(ar, cnt)
        let cxr = fa(ar, cnt)
        var m1 = 0usize
        i = 0usize
        while i < sn {
            if !ar_isnan(sdx[i]) {
                cy[m1] = sdx[i]
                cxr[m1] = sdr[i]
                m1 += 1usize
            }
            i += 1usize
        }
        let (lmo, lme) = olsf.fit(ar, cxr[0usize..m1], m1, 1usize, cy[0usize..m1])
        if lme != ok { ret fit }
        init[narma] = lmo.coef[0usize]
        parscale[narma] = 10.0f64 * lmo.se[0usize]
    }
    let coefv = fa(ar, ntot)
    i = 0usize
    while i < ntot {
        coefv[i] = ar_nan()
        i += 1usize
    }
    if ncx == 1usize && !xfree { coefv[narma] = xfixed }
    let full = fa(ar, ntot)
    let gb = fa(ar, nfree + 1usize)
    var c = ArCtx{ ar: ar, x: x, xreg: xreg, p: p, q: q, d: d, narma: narma, ncx: ncx, nfree: nfree, coefv: coefv, delta: delta, kappa: 1.0e6f64, ncond: ncond, trans: false, mode: 1usize, sp: sp, sq: sq, sd: sd, per: per, parscale: parscale, full: full, gb: gb, bad: false }
    let b = fa(ar, nfree + 1usize)
    let coef = fa(ar, ntot)
    let hess = fa(ar, nfree * nfree + 1usize)
    var resvalue = 0.0f64
    var conv = 0i64
    var hessok = true
    var sigma2 = 0.0f64
    let vcov = fa(ar, nfree * nfree + 1usize)
    var aic = ar_nan()
    var finalmodel: kal.SsModel = zero
    let phi = fa(ar, pl)
    let theta0 = fa(ar, ql)
    var r0 = pl
    if ql + 1usize > r0 { r0 = ql + 1usize }
    let theta = fa(ar, r0 - 1usize)
    if method == 2usize {
        // CSS
        c.mode = 1usize
        c.ncond = ncond
        i = 0usize
        while i < nfree {
            b[i] = init[i] / parscale[i]
            i += 1usize
        }
        if noopt {
            resvalue = ar_obj(&c, b)
        } else {
            let (fv, fl) = vmmin_f(ar, &c, b[0usize..nfree], 1.4901161193847656e-08f64, 100usize)
            resvalue = fv
            conv = fl
        }
        i = 0usize
        while i < ntot {
            coef[i] = coefv[i]
            i += 1usize
        }
        i = 0usize
        while i < nfree {
            coef[i] = b[i] * parscale[i]
            i += 1usize
        }
        if !noopt {
            ar_hessian(&c, coef, hess)
            i = 0usize
            while i < nfree * nfree {
                hess[i] = hess[i] * f64(nused)
                i += 1usize
            }
            let vi = fa(ar, nfree * nfree)
            hessok = invert_checked(ar, hess, nfree, vi)
            if hessok {
                i = 0usize
                while i < nfree * nfree {
                    vcov[i] = vi[i]
                    i += 1usize
                }
            }
        }
        trans_pars(coef, p, q, sp, sq, per, false, phi, theta0)
        i = 0usize
        while i < ql {
            theta[i] = theta0[i]
            i += 1usize
        }
        i = ql
        while i + 1usize < r0 {
            theta[i] = 0.0f64
            i += 1usize
        }
        let (mdl, mgood) = make_arima(ar, phi, theta, delta, 1.0e6f64)
        var mm = mdl
        let x2 = fa(ar, n)
        i = 0usize
        while i < n {
            x2[i] = x[i]
            if ncx > 0usize { x2[i] = x[i] - xreg[i] * coef[narma] }
            i += 1usize
        }
        if !mgood { ret fit }
        let (q1, q2, q3) = arima_like(ar, &mm, phi, theta, delta, x2, x2[0usize..0usize])
        finalmodel = mm
        sigma2 = css_value(ar, x2, pl, ql, d, sd, per, phi, theta0, ncond, resv)
    } else {
        if method == 0usize {
            // the CSS stage
            c.mode = 1usize
            c.ncond = ncond
            i = 0usize
            while i < nfree {
                b[i] = init[i] / parscale[i]
                i += 1usize
            }
            var cssv = 0.0f64
            var cssconv = 0i64
            if noopt {
                cssv = ar_obj(&c, b)
            } else {
                let (fv, fl) = vmmin_f(ar, &c, b[0usize..nfree], 1.4901161193847656e-08f64, 100usize)
                cssv = fv
                cssconv = fl
            }
            if cssconv == 0i64 {
                i = 0usize
                while i < nfree {
                    init[i] = b[i] * parscale[i]
                    i += 1usize
                }
            }
            if c.bad { ret fit }
            if p > 0usize {
                if !ar_check(ar, init[0usize..p]) { ret fit }
            }
            if sp > 0usize {
                if !ar_check(ar, init[p + q..p + q + sp]) { ret fit }
            }
            ncond = 0usize
            c.ncond = 0usize
        }
        if trans {
            // init <- Invtrans(init); maInvert on the MA part
            let inv = fa(ar, ntot)
            i = 0usize
            while i < ntot {
                inv[i] = init[i]
                i += 1usize
            }
            invpartrans(p, init, inv)
            if sp > 0usize { invpartrans(sp, init[p + q..p + q + sp], inv[p + q..p + q + sp]) }
            i = 0usize
            while i < ntot {
                init[i] = inv[i]
                i += 1usize
            }
            if q > 0usize { ma_invert(ar, init[p..p + q]) }
            if sq > 0usize { ma_invert(ar, init[p + q + sp..p + q + sp + sq]) }
        }
        c.mode = 0usize
        c.trans = trans
        c.bad = false
        i = 0usize
        while i < nfree {
            b[i] = init[i] / parscale[i]
            i += 1usize
        }
        if noopt {
            resvalue = ar_obj(&c, b)
        } else {
            let (fv, fl) = vmmin_f(ar, &c, b[0usize..nfree], 1.4901161193847656e-08f64, 100usize)
            resvalue = fv
            conv = fl
        }
        i = 0usize
        while i < ntot {
            coef[i] = coefv[i]
            i += 1usize
        }
        i = 0usize
        while i < nfree {
            coef[i] = b[i] * parscale[i]
            i += 1usize
        }
        if trans {
            var changed = false
            let msv = fa(ar, ntot)
            i = 0usize
            while i < ntot {
                msv[i] = coef[i]
                i += 1usize
            }
            if q > 0usize { ma_invert(ar, coef[p..p + q]) }
            if sq > 0usize { ma_invert(ar, coef[p + q + sp..p + q + sp + sq]) }
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
                resvalue = ar_obj(&c, b)
            }
            ar_hessian(&c, coef, hess)
            i = 0usize
            while i < nfree * nfree {
                hess[i] = hess[i] * f64(nused)
                i += 1usize
            }
            let vi = fa(ar, nfree * nfree)
            hessok = invert_checked(ar, hess, nfree, vi)
            if hessok {
                // var = A' (H n)^-1 A with A the Jacobian of the AR transform on the free coefficients
                let am = fa(ar, nfree * nfree)
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
                    var off = 0usize
                    var len = p
                    if blk == 1usize {
                        off = p + q
                        len = sp
                    }
                    if len > 0usize {
                        let w1 = fa(ar, len)
                        let w2 = fa(ar, len)
                        let w3 = fa(ar, len)
                        i = 0usize
                        while i < len {
                            w1[i] = coef[off + i]
                            i += 1usize
                        }
                        partrans(len, w1, w2)
                        i = 0usize
                        while i < len {
                            w1[i] += 0.001f64
                            partrans(len, w1, w3)
                            var j = 0usize
                            while j < len {
                                am[(off + i) * nfree + off + j] = (w3[j] - w2[j]) / 0.001f64
                                j += 1usize
                            }
                            w1[i] -= 0.001f64
                            i += 1usize
                        }
                    }
                    blk += 1usize
                }
                let t1 = fa(ar, nfree * nfree)
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
            }
            // undoPars: the AR part back to coefficients
            if p > 0usize {
                let ud = fa(ar, p)
                partrans(p, coef, ud)
                i = 0usize
                while i < p {
                    coef[i] = ud[i]
                    i += 1usize
                }
            }
            if sp > 0usize {
                let ud2 = fa(ar, sp)
                partrans(sp, coef[p + q..p + q + sp], ud2)
                i = 0usize
                while i < sp {
                    coef[p + q + i] = ud2[i]
                    i += 1usize
                }
            }
        } else if !noopt {
            ar_hessian(&c, coef, hess)
            i = 0usize
            while i < nfree * nfree {
                hess[i] = hess[i] * f64(nused)
                i += 1usize
            }
            let vi = fa(ar, nfree * nfree)
            hessok = invert_checked(ar, hess, nfree, vi)
            if hessok {
                i = 0usize
                while i < nfree * nfree {
                    vcov[i] = vi[i]
                    i += 1usize
                }
            }
        }
        trans_pars(coef, p, q, sp, sq, per, false, phi, theta0)
        i = 0usize
        while i < ql {
            theta[i] = theta0[i]
            i += 1usize
        }
        i = ql
        while i + 1usize < r0 {
            theta[i] = 0.0f64
            i += 1usize
        }
        let (mdl, mgood) = make_arima(ar, phi, theta, delta, 1.0e6f64)
        var mm = mdl
        if !mgood { ret fit }
        let x2 = fa(ar, n)
        i = 0usize
        while i < n {
            x2[i] = x[i]
            if ncx > 0usize { x2[i] = x[i] - xreg[i] * coef[narma] }
            i += 1usize
        }
        let (ssq, sl, nu2) = arima_like(ar, &mm, phi, theta, delta, x2, resv)
        finalmodel = mm
        sigma2 = ssq / f64(nused)
    }
    if c.bad || !hessok { ret fit }
    var varok = true
    i = 0usize
    while i < nfree {
        if !(vcov[i * nfree + i] >= 0.0f64) { varok = false }
        i += 1usize
    }
    let value = 2.0f64 * f64(nused) * resvalue + f64(nused) + f64(nused) * math.log[f64](2.0f64 * 3.141592653589793f64)
    if method != 2usize { aic = value + 2.0f64 * f64(nfree) + 2.0f64 }
    fit = ArFit{ good: true, p: p, q: q, d: d, nfree: nfree, coef: coef, aic: aic, value: value, sigma2: sigma2, nused: nused, model: finalmodel, phi: phi, theta: theta, varok: varok, convergence: conv, resid: resv }
    ret fit
}
