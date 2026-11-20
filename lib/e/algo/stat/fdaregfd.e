// R fda, register.fd (crit 2, non-periodic, one variable) for B-spline curves, with its pieces monhess, regyfn, regfngrad, reghess, linesearch, stepchk and stepit.
//
// Not here: periodic registration (the shift), multivariate curves, crit 1, a W basis with a different order than the one given.

use e.algo.stat.fdalm as lm
use e.algo.stat.fdapkg as fa
use e.algo.stat.fdareg as fr
use e.math
use e.mem

// the fixed part of one registration: the curve basis (yn, yb), the W basis (wn, wb), the fine grid, the penalty on the W coefficients past the first and the Gram matrix of the curve basis
type RegCtx = struct { yn: usize, yb: []const f64, ynb: usize, wn: usize, wb: []const f64, nw: usize, nfine: usize, lo: f64, hi: f64, xfine: []f64, kmat: []f64, haspen: bool, gram: []f64, crit: usize }

fn eval_curve(a: *mem.Arena, norder: usize, breaks: []const f64, coefs: []const f64, xs: []const f64, deriv: usize, out: []f64) {
    var i = 0usize
    while i < xs.len {
        let st = mem.mark(a)
        out[i] = fa.eval_fd_bspline(a, norder, breaks, coefs, xs[i], deriv)
        mem.reset(a, st)
        i += 1usize
    }
}

// monhess(x, Wfd): the second derivatives of the monotone function with respect to the coefficient pairs, column m = j (j - 1) / 2 + k for k <= j (one based). fda sums the whole matrix of integrand values into one number per level, and so do we; out is xs.len by npair
fn mon_hess(a: *mem.Arena, norder: usize, breaks: []const f64, coefs: []const f64, xs: []const f64, out: []f64) -> err {
    let st0 = mem.mark(a)
    let nb = breaks.len + norder - 2usize
    let np = nb * (nb + 1usize) / 2usize
    let cap = 32770usize
    let (tv, e1) = mem.alloc[f64](a, cap)
    let (fv, e2) = mem.alloc[f64](a, cap * np)
    let (tt, e3) = mem.alloc[f64](a, cap)
    let (ft, e4) = mem.alloc[f64](a, cap * np)
    let (tn, e5) = mem.alloc[f64](a, cap)
    let (fnew, e6) = mem.alloc[f64](a, cap * np)
    let (sm, e7) = mem.alloc[f64](a, 17usize)
    let (hh, e8) = mem.alloc[f64](a, 17usize)
    let (v, e9) = mem.alloc[f64](a, nb + norder)
    let (cs, e10) = mem.alloc[f64](a, 5usize)
    let (ds, e11) = mem.alloc[f64](a, 5usize)
    let (ss, e12) = mem.alloc[f64](a, 1usize)
    let (dy, e13) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    let lo = breaks[0usize]
    let hi = breaks[breaks.len - 1usize]
    let width = hi - lo
    hh[0usize] = 1.0f64
    hh[1usize] = 0.25f64
    var q = 0usize
    while q < 17usize {
        sm[q] = 0.0f64
        q += 1usize
    }
    var cnt = 0usize
    var total = 0.0f64
    var side = 0usize
    while side < 2usize {
        var xe = lo
        if side == 1usize { xe = hi }
        let st = mem.mark(a)
        let e = fa.eval_bspline(a, norder, breaks, xe, 0usize, v)
        if e != ok { ret e }
        hess_row(v, nb, coefs, fv[cnt * np..cnt * np + np])
        mem.reset(a, st)
        tv[cnt] = xe
        var c = 0usize
        while c < np {
            total += fv[cnt * np + c]
            c += 1usize
        }
        cnt += 1usize
        side += 1usize
    }
    sm[0usize] = width * total / 2.0f64
    var tnm = 0.5f64
    var j = 2usize
    var done = false
    while j <= 15usize && !done {
        tnm = tnm * 2.0f64
        let del = width / tnm
        let nnew = usize(tnm)
        var sum = 0.0f64
        var k = 0usize
        while k < nnew {
            let x = lo + del / 2.0f64 + f64(k) * del
            let st = mem.mark(a)
            let e = fa.eval_bspline(a, norder, breaks, x, 0usize, v)
            if e != ok { ret e }
            hess_row(v, nb, coefs, fnew[k * np..k * np + np])
            mem.reset(a, st)
            tn[k] = x
            var c = 0usize
            while c < np {
                sum += fnew[k * np + c]
                c += 1usize
            }
            k += 1usize
        }
        var ia = 0usize
        var ib = 0usize
        var iw = 0usize
        while ia < cnt || ib < nnew {
            var takea = false
            if ia < cnt && ib < nnew {
                if tv[ia] <= tn[ib] { takea = true }
            } else if ia < cnt {
                takea = true
            }
            var c = 0usize
            if takea {
                tt[iw] = tv[ia]
                while c < np {
                    ft[iw * np + c] = fv[ia * np + c]
                    c += 1usize
                }
                ia += 1usize
            } else {
                tt[iw] = tn[ib]
                while c < np {
                    ft[iw * np + c] = fnew[ib * np + c]
                    c += 1usize
                }
                ib += 1usize
            }
            iw += 1usize
        }
        cnt = iw
        k = 0usize
        while k < cnt {
            tv[k] = tt[k]
            var c = 0usize
            while c < np {
                fv[k * np + c] = ft[k * np + c]
                c += 1usize
            }
            k += 1usize
        }
        sm[j - 1usize] = (sm[j - 2usize] + del * sum) / 2.0f64
        if j >= 7usize {
            fr.polint5(hh[j - 5usize..j], sm[j - 5usize..j], 1usize, cs, ds, ss, dy)
            if math.abs[f64](dy[0usize]) < 1.0e-4f64 * math.abs[f64](ss[0usize]) || j >= 15usize { done = true }
        }
        if !done {
            hh[j] = 0.25f64 * hh[j - 1usize]
            j += 1usize
        }
    }
    if !done { ret mem.Full }
    let step = tv[1usize] - tv[0usize]
    var c = 0usize
    while c < np {
        let f0 = fv[c]
        var run = 0.0f64
        var k = 0usize
        while k < cnt {
            run += fv[k * np + c]
            ft[k * np + c] = step * (run - 0.5f64 * (f0 + fv[k * np + c]))
            k += 1usize
        }
        k = 0usize
        while k < cnt {
            tn[k] = ft[k * np + c]
            k += 1usize
        }
        var r = 0usize
        while r < xs.len {
            out[c * xs.len + r] = fr.approx_lin(tv, tn, cnt, xs[r])
            r += 1usize
        }
        c += 1usize
    }
    mem.reset(a, st0)
    ret ok
}

// row[m] = exp(W) b_j b_k for the pairs k <= j in monhess's order
fn hess_row(v: []const f64, nb: usize, coefs: []const f64, row: []f64) {
    var w = 0.0f64
    var k = 0usize
    while k < nb {
        w += v[k] * coefs[k]
        k += 1usize
    }
    let fx = math.exp[f64](w)
    var m = 0usize
    var ib = 0usize
    while ib < nb {
        var jb = 0usize
        while jb <= ib {
            row[m] = fx * v[ib] * v[jb]
            m += 1usize
            jb += 1usize
        }
        ib += 1usize
    }
}

// the value, gradient and the pair second derivatives of the registration function for coefficients cvec (the first coefficient set to zero first, as register.fd does for the quadrature): hfine, dhfine (nfine by nw), d2h (nfine by npair, adjusted as register.fd does).
// fm holds (fmax); ffine and dffine are kept for the caller's later Hessian
fn reg_h(a: *mem.Arena, cx: *const RegCtx, cvec: []const f64, withhess: bool, ffine: []f64, dffine: []f64, hfine: []f64, dhfine: []f64, d2h: []f64, fm: []f64) -> err {
    let nw = cx.nw
    let nf = cx.nfine
    let width = cx.hi - cx.lo
    var e = fr.mon_eval(a, cx.wn, cx.wb, cvec, cx.xfine, false, ffine)
    if e != ok { ret e }
    e = fr.mon_eval(a, cx.wn, cx.wb, cvec, cx.xfine, true, dffine)
    if e != ok { ret e }
    let fmax = ffine[nf - 1usize]
    fm[0usize] = fmax
    var i = 0usize
    while i < nf {
        hfine[i] = cx.lo + width * ffine[i] / fmax
        i += 1usize
    }
    hfine[0usize] = cx.lo
    hfine[nf - 1usize] = cx.hi
    var j = 0usize
    while j < nw {
        let dfm = dffine[j * nf + nf - 1usize]
        i = 0usize
        while i < nf {
            dhfine[j * nf + i] = width * (fmax * dffine[j * nf + i] - ffine[i] * dfm) / (fmax * fmax)
            i += 1usize
        }
        j += 1usize
    }
    if !withhess { ret ok }
    e = mon_hess(a, cx.wn, cx.wb, cvec, cx.xfine, d2h)
    if e != ok { ret e }
    let np = nw * (nw + 1usize) / 2usize
    let (d2fmax, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret mem.Full }
    var m = 0usize
    while m < np {
        d2fmax[m] = d2h[m * nf + nf - 1usize]
        m += 1usize
    }
    let fmax2 = fmax * fmax
    let fmax3 = fmax * fmax2
    var jj = 1usize
    while jj < nw {
        var kk = 1usize
        while kk <= jj {
            let col = jj * (jj + 1usize) / 2usize + kk
            let dfj = dffine[jj * nf + nf - 1usize]
            let dfk = dffine[kk * nf + nf - 1usize]
            i = 0usize
            while i < nf {
                d2h[col * nf + i] = width * (2.0f64 * ffine[i] * dfj * dfk - fmax * (dffine[jj * nf + i] * dfk + dffine[kk * nf + i] * dfj) + fmax2 * d2h[col * nf + i] - ffine[i] * fmax * d2fmax[col]) / fmax3
                i += 1usize
            }
            kk += 1usize
        }
        jj += 1usize
    }
    ret ok
}

// regyfn: the registered curve's coefficients. With the W coefficients past the first all zero it is the curve itself; otherwise the penalised projection (project.basis with penalize) of the curve values onto the basis at the inverse warp
fn reg_yfn(a: *mem.Arena, cx: *const RegCtx, cvec: []const f64, hfine: []const f64, yfine: []const f64, ycoefs: []const f64, out: []f64) -> err {
    let nb = cx.ynb
    let nf = cx.nfine
    var allzero = true
    var i = 1usize
    while i < cx.nw {
        if cvec[i] != 0.0f64 { allzero = false }
        i += 1usize
    }
    if allzero {
        i = 0usize
        while i < nb {
            out[i] = ycoefs[i]
            i += 1usize
        }
        ret ok
    }
    let (hinv, e1) = mem.alloc[f64](a, nf)
    let (bm, e2) = mem.alloc[f64](a, nb * nb)
    let (rhs, e3) = mem.alloc[f64](a, nb)
    let (v, e4) = mem.alloc[f64](a, nb + cx.yn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    i = 0usize
    while i < nf {
        hinv[i] = fr.approx_lin(hfine, cx.xfine, nf, cx.xfine[i])
        i += 1usize
    }
    hinv[0usize] = cx.xfine[0usize]
    hinv[nf - 1usize] = cx.xfine[nf - 1usize]
    var q = 0usize
    while q < nb * nb {
        bm[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nb {
        rhs[q] = 0.0f64
        q += 1usize
    }
    var t = 0usize
    while t < nf {
        let st = mem.mark(a)
        let e = fa.eval_bspline(a, cx.yn, cx.yb, hinv[t], 0usize, v)
        mem.reset(a, st)
        if e != ok { ret e }
        var r = 0usize
        while r < nb {
            var c = 0usize
            while c < nb {
                bm[c * nb + r] += v[r] * v[c]
                c += 1usize
            }
            rhs[r] += v[r] * yfine[t]
            r += 1usize
        }
        t += 1usize
    }
    var gmax = cx.gram[0usize]
    q = 0usize
    while q < nb * nb {
        if cx.gram[q] > gmax { gmax = cx.gram[q] }
        q += 1usize
    }
    var trb = 0.0f64
    var trp = 0.0f64
    i = 0usize
    while i < nb {
        trb += bm[i * nb + i]
        trp += cx.gram[i * nb + i] + 1.0e-10f64 * gmax
        i += 1usize
    }
    let lam = (0.0001f64 * trb) / trp
    q = 0usize
    while q < nb * nb {
        bm[q] += lam * cx.gram[q]
        q += 1usize
    }
    i = 0usize
    while i < nb {
        bm[i * nb + i] += lam * 1.0e-10f64 * gmax
        i += 1usize
    }
    ret fr.spd_solve(a, bm, nb, rhs, 1usize, out)
}

// regfngrad with crit 2: res = (criterion, gradient norm), grad has nw entries (the first is zero)
fn reg_fg(a: *mem.Arena, cx: *const RegCtx, y0fine: []const f64, dhfine: []const f64, ycoef: []const f64, cvec: []const f64, res: []f64, grad: []f64) -> err {
    let nf = cx.nfine
    let nw = cx.nw
    let (yr, e1) = mem.alloc[f64](a, nf)
    let (dyr, e2) = mem.alloc[f64](a, nf)
    if e1 != ok || e2 != ok { ret mem.Full }
    eval_curve(a, cx.yn, cx.yb, ycoef, cx.xfine, 0usize, yr)
    eval_curve(a, cx.yn, cx.yb, ycoef, cx.xfine, 1usize, dyr)
    var aa = 0.0f64
    var bb = 0.0f64
    var cc = 0.0f64
    var i = 0usize
    while i < nf {
        aa += y0fine[i] * y0fine[i]
        bb += y0fine[i] * yr[i]
        cc += yr[i] * yr[i]
        i += 1usize
    }
    let n = f64(nf)
    aa = aa / n
    bb = bb / n
    cc = cc / n
    let ee = aa + cc
    let ff = aa - cc
    let dd = math.sqrt[f64](ff * ff + 4.0f64 * bb * bb)
    var fval = ee - dd
    if cx.crit == 1usize { fval = aa - 2.0f64 * bb + cc }
    var j = 0usize
    while j < nw {
        var sb = 0.0f64
        var sc = 0.0f64
        var sr = 0.0f64
        if j > 0usize {
            i = 0usize
            while i < nf {
                let dw = dyr[i] * dhfine[j * nf + i]
                sb += dw * y0fine[i]
                sc += dw * yr[i]
                sr += dw * (y0fine[i] - yr[i])
                i += 1usize
            }
        }
        let dbb = sb / n
        let dcc = 2.0f64 * sc / n
        let ddd = (4.0f64 * bb * dbb - ff * dcc) / dd
        grad[j] = dcc - ddd
        if cx.crit == 1usize { grad[j] = 0.0f64 - 2.0f64 * sr / n }
        j += 1usize
    }
    if cx.haspen && nw > 1usize {
        var p = 0usize
        while p < nw - 1usize {
            var kc = 0.0f64
            var q = 0usize
            while q < nw - 1usize {
                kc += cx.kmat[q * (nw - 1usize) + p] * cvec[1usize + q]
                q += 1usize
            }
            fval += cvec[1usize + p] * kc
            grad[1usize + p] += 2.0f64 * kc
            p += 1usize
        }
    }
    grad[0usize] = 0.0f64
    var nr = 0.0f64
    j = 0usize
    while j < nw {
        nr += grad[j] * grad[j]
        j += 1usize
    }
    res[0usize] = fval
    res[1usize] = math.sqrt[f64](nr)
    ret ok
}

// reghess with crit 2; d2h is modified in place for the columns reghess sets itself; hess is nw by nw
fn reg_hs(a: *mem.Arena, cx: *const RegCtx, y0fine: []const f64, dhfine: []const f64, d2h: []f64, ycoef: []const f64, hess: []f64) -> err {
    let nf = cx.nfine
    let nw = cx.nw
    let np = nw * (nw + 1usize) / 2usize
    let (yr, e1) = mem.alloc[f64](a, nf)
    let (dyr, e2) = mem.alloc[f64](a, nf)
    let (d2yr, e3) = mem.alloc[f64](a, nf)
    let (dbbv, e4) = mem.alloc[f64](a, nw)
    let (dccv, e5) = mem.alloc[f64](a, nw)
    let (hv, e6) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    eval_curve(a, cx.yn, cx.yb, ycoef, cx.xfine, 0usize, yr)
    eval_curve(a, cx.yn, cx.yb, ycoef, cx.xfine, 1usize, dyr)
    eval_curve(a, cx.yn, cx.yb, ycoef, cx.xfine, 2usize, d2yr)
    var i = 0usize
    while i < nf {
        d2h[i] = 1.0f64
        i += 1usize
    }
    var jj = 1usize
    while jj < nw {
        let col = jj * (jj + 1usize) / 2usize
        i = 0usize
        while i < nf {
            d2h[col * nf + i] = 0.0f64
            i += 1usize
        }
        jj += 1usize
    }
    var aa = 0.0f64
    var bb = 0.0f64
    var cc = 0.0f64
    i = 0usize
    while i < nf {
        aa += y0fine[i] * y0fine[i]
        bb += y0fine[i] * yr[i]
        cc += yr[i] * yr[i]
        i += 1usize
    }
    let n = f64(nf)
    aa = aa / n
    bb = bb / n
    cc = cc / n
    var j = 0usize
    while j < nw {
        var sb = 0.0f64
        var sc = 0.0f64
        if j > 0usize {
            i = 0usize
            while i < nf {
                let dw = dyr[i] * dhfine[j * nf + i]
                sb += dw * y0fine[i]
                sc += dw * yr[i]
                i += 1usize
            }
        }
        dbbv[j] = sb / n
        dccv[j] = 2.0f64 * sc / n
        j += 1usize
    }
    let ee = aa + cc
    let ff = aa - cc
    let dd = math.sqrt[f64](ff * ff + 4.0f64 * bb * bb)
    let ddsq = dd * dd
    let ddcu = ddsq * dd
    let ex = ee
    var m = 0usize
    j = 0usize
    while j < nw {
        var k = 0usize
        while k <= j {
            var s2b = 0.0f64
            var s2c = 0.0f64
            var s1 = 0.0f64
            i = 0usize
            while i < nf {
                var dhj = 0.0f64
                var dhk = 0.0f64
                if j > 0usize { dhj = dhfine[j * nf + i] }
                if k > 0usize { dhk = dhfine[k * nf + i] }
                s1 += (dyr[i] * dhj) * (dyr[i] * dhk)
                let cp = dhj * dhk * d2yr[i]
                let dyd2 = dyr[i] * d2h[m * nf + i]
                let temp = cp + dyd2
                s2b += y0fine[i] * temp
                s2c += yr[i] * temp + dyr[i] * dyr[i] * dhj * dhk
                i += 1usize
            }
            let d2bb = s2b / n
            let d2cc = 2.0f64 * (s2c / n)
            hv[m] = d2cc - (4.0f64 * dbbv[j] * dbbv[k] + 4.0f64 * bb * d2bb + dccv[j] * dccv[k] - ff * d2cc) / dd + (4.0f64 * bb * dbbv[j] - ff * dccv[j]) * (4.0f64 * bb * dbbv[k] - ff * dccv[k]) / ddcu
            if cx.crit == 1usize { hv[m] = 2.0f64 * s1 / n }
            m += 1usize
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    m = 0usize
    while j < nw {
        var k = 0usize
        while k <= j {
            hess[k * nw + j] = hv[m]
            hess[j * nw + k] = hv[m]
            m += 1usize
            k += 1usize
        }
        j += 1usize
    }
    if cx.haspen && nw > 1usize {
        var p = 1usize
        while p < nw {
            var q = 1usize
            while q < nw {
                hess[q * nw + p] += 2.0f64 * cx.kmat[(q - 1usize) * (nw - 1usize) + (p - 1usize)]
                q += 1usize
            }
            p += 1usize
        }
    }
    j = 0usize
    while j < nw {
        hess[j] = 0.0f64
        hess[j * nw] = 0.0f64
        j += 1usize
    }
    hess[0usize] = 1.0f64
    if ex < 0.0f64 { ret mem.Full }
    ret ok
}

// linesearch: the Newton direction, or steepest descent when it is not a descent direction (cosine below 1e-7); deltac receives it, the return value is the cosine
fn reg_direction(a: *mem.Arena, nw: usize, hess: []const f64, grad: []const f64, deltac: []f64) -> f64 {
    let (hc, e1) = mem.alloc[f64](a, nw * nw)
    if e1 != ok { ret 0.0f64 }
    var q = 0usize
    while q < nw * nw {
        hc[q] = hess[q]
        q += 1usize
    }
    q = 0usize
    while q < nw {
        deltac[q] = 0.0f64 - grad[q]
        q += 1usize
    }
    if !fr.lu_solve(hc, nw, deltac, 1usize) { ret 0.0f64 }
    var gd = 0.0f64
    var gg = 0.0f64
    var dd = 0.0f64
    q = 0usize
    while q < nw {
        gd += grad[q] * deltac[q]
        gg += grad[q] * grad[q]
        dd += deltac[q] * deltac[q]
        q += 1usize
    }
    let cosangle = (0.0f64 - gd) / math.sqrt[f64](gg * dd)
    if cosangle < 1.0e-7f64 {
        q = 0usize
        while q < nw {
            deltac[q] = 0.0f64 - grad[q]
            q += 1usize
        }
    }
    ret cosangle
}

// R's min over a vector holding NaN: NaN
fn min_nan(x: f64, y: f64) -> f64 {
    if x != x || y != y { ret 0.0f64 / 0.0f64 }
    if y < x { ret y }
    ret x
}

// stepchk with the limits -50 and 50: the step is shortened when it would leave them. fda indexes the length nw vectors with a logical index of length nw - 1, which R recycles; so do we. lim = (upper, lower) flags, ind[0] the status
fn step_chk(oldstep: f64, cvec: []const f64, deltac: []const f64, lim: []usize, ind: []usize, nw: usize) -> f64 {
    var newstep = oldstep
    var stepmin = oldstep * deltac[0usize]
    var stepmax = stepmin
    var i = 1usize
    while i < nw {
        let s = oldstep * deltac[i]
        if s < stepmin { stepmin = s }
        if s > stepmax { stepmax = s }
        i += 1usize
    }
    var pass = 0usize
    while pass < 2usize {
        var tgt = stepmin
        if pass == 1usize { tgt = stepmax }
        var anystep = false
        var anydelta = false
        var stepnew = 0.0f64 / 0.0f64
        var have = false
        i = 0usize
        while i < nw {
            let sel = (oldstep * deltac[1usize + i % (nw - 1usize)]) == tgt
            if sel {
                let si = oldstep * deltac[i]
                var lim_v = 0.0f64 - 50.0f64
                if pass == 1usize { lim_v = 50.0f64 }
                let room = lim_v - cvec[i]
                if pass == 0usize {
                    if si < room { anystep = true }
                } else {
                    if si > room { anystep = true }
                }
                if deltac[i] != 0.0f64 { anydelta = true }
                let ratio = room / deltac[i]
                if !have {
                    stepnew = ratio
                    have = true
                } else {
                    stepnew = min_nan(stepnew, ratio)
                }
            }
            i += 1usize
        }
        if anystep && anydelta {
            newstep = stepnew
            if pass == 0usize {
                if lim[1usize] == 1usize {
                    ind[0usize] = 1usize
                } else {
                    lim[1usize] = 1usize
                }
            } else {
                if lim[0usize] == 1usize {
                    ind[0usize] = 1usize
                } else {
                    lim[0usize] = 1usize
                }
            }
        } else {
            if pass == 0usize {
                lim[1usize] = 0usize
            } else {
                lim[0usize] = 0usize
            }
        }
        pass += 1usize
    }
    ret newstep
}

// stepit: the cubic-interpolation step logic of the registration line search; l is fda's 3 by 5 linemat (column-major), st[0] is ips, dbl the two flags; the return value is ind
fn step_it(l: []f64, st: []usize, dbl: []usize, maxstep: f64) -> usize {
    let t11 = l[14usize] <= l[2usize] + l[12usize] * l[1usize] / 20.0f64
    let t12 = math.abs[f64](l[13usize]) <= math.abs[f64](l[1usize]) / 10.0f64
    let test1 = t11 && t12
    let test2 = l[14usize] > l[2usize]
    let test3 = l[13usize] > 0.0f64
    var r = 0usize
    if (test1 || !test3) && test2 {
        st[0usize] = 0usize
        if dbl[1usize] == 1usize { ret 5usize }
        var h = l[12usize] / 2.0f64
        if h > maxstep { h = maxstep }
        l[12usize] = h
        r = 0usize
        while r < 3usize {
            l[3usize + r] = l[r]
            l[6usize + r] = l[r]
            r += 1usize
        }
        dbl[0usize] = 1usize
        ret 2usize
    }
    if test1 { ret 0usize }
    if test3 {
        st[0usize] = 1usize
        r = 0usize
        while r < 3usize {
            l[9usize + r] = l[12usize + r]
            r += 1usize
        }
        let deltaf = l[8usize] - l[14usize]
        let z = (3.0f64 / (l[12usize] - l[6usize])) * deltaf + l[7usize] + l[13usize]
        var w = z * z - l[7usize] * l[13usize]
        if math.abs[f64](l[7usize] + l[13usize] + 2.0f64 * z) >= 1.0e-5f64 && w > 0.0f64 {
            w = math.sqrt[f64](w)
            l[12usize] = l[6usize] + (1.0f64 - ((l[13usize] + w - z) / (l[13usize] - l[7usize] + 2.0f64 * w))) * (l[12usize] - l[6usize])
        } else {
            var aerror = l[6usize]
            if l[12usize] > l[6usize] { aerror = l[12usize] }
            l[12usize] = l[6usize] - l[7usize] * ((l[12usize] - l[6usize]) / (l[13usize] - l[7usize]))
            if l[12usize] > 2.0f64 * aerror { l[12usize] = 2.0f64 * aerror }
        }
        if l[12usize] > maxstep { l[12usize] = maxstep }
        dbl[0usize] = 0usize
        dbl[1usize] = 0usize
        ret 2usize
    }
    r = 0usize
    while r < 3usize {
        l[3usize + r] = l[6usize + r]
        l[6usize + r] = l[12usize + r]
        r += 1usize
    }
    if st[0usize] == 1usize {
        let deltaf = l[14usize] - l[11usize]
        let z = (3.0f64 / (l[9usize] - l[12usize])) * deltaf + l[13usize] + l[10usize]
        var w = z * z - l[13usize] * l[10usize]
        if math.abs[f64](l[13usize] + l[10usize] + 2.0f64 * z) >= 1.0e-5f64 && w > 0.0f64 {
            w = math.sqrt[f64](w)
            l[12usize] = l[12usize] + (1.0f64 - ((l[10usize] + w - z) / (l[10usize] - l[13usize] + 2.0f64 * w))) * (l[9usize] - l[12usize])
        } else {
            var aerror = l[12usize]
            if l[9usize] > l[12usize] { aerror = l[9usize] }
            l[12usize] = l[12usize] - l[13usize] * ((l[9usize] - l[12usize]) / (l[10usize] - l[13usize]))
            if l[12usize] > 2.0f64 * aerror { l[12usize] = 2.0f64 * aerror }
        }
        if l[12usize] > maxstep { l[12usize] = maxstep }
        dbl[0usize] = 0usize
        dbl[1usize] = 0usize
        ret 2usize
    }
    if (l[7usize] - l[4usize]) * (l[6usize] - l[3usize]) > 0.0f64 {
        let z = (3.0f64 / (l[6usize] - l[3usize])) * (l[5usize] - l[8usize]) + l[4usize] + l[7usize]
        var w = z * z - l[4usize] * l[7usize]
        if math.abs[f64](l[4usize] + l[7usize] + 2.0f64 * z) >= 1.0e-5f64 && w > 0.0f64 {
            w = math.sqrt[f64](w)
            l[12usize] = l[3usize] + (1.0f64 - ((l[7usize] + w - z) / (l[7usize] - l[4usize] + 2.0f64 * w))) * (l[6usize] - l[3usize])
        } else {
            l[12usize] = l[3usize] - l[4usize] * ((l[6usize] - l[3usize]) / (l[7usize] - l[4usize]))
        }
        if l[12usize] > maxstep { l[12usize] = maxstep }
        dbl[0usize] = 0usize
        dbl[1usize] = 0usize
        ret 2usize
    }
    if dbl[0usize] == 1usize { ret 5usize }
    l[12usize] = 2.0f64 * l[12usize]
    if l[12usize] > maxstep { l[12usize] = maxstep }
    dbl[1usize] = 1usize
    ret 2usize
}

// register.fd for one curve: cvec (nw coefficients of W, in and out) is moved to the optimum; ycoefs the curve, y0coefs the tgt in the curve basis; yreg receives the registered curve's coefficients
fn register_curve(a: *mem.Arena, cx: *const RegCtx, ycoefs: []const f64, y0coefs: []const f64, conv: f64, iterlim: usize, cvec: []f64, yreg: []f64) -> err {
    let nw = cx.nw
    let nf = cx.nfine
    let np = nw * (nw + 1usize) / 2usize
    let (yfine, e1) = mem.alloc[f64](a, nf)
    let (y0fine, e2) = mem.alloc[f64](a, nf)
    let (ffine, e3) = mem.alloc[f64](a, nf)
    let (dffine, e4) = mem.alloc[f64](a, nf * nw)
    let (hfine, e5) = mem.alloc[f64](a, nf)
    let (dhfine, e6) = mem.alloc[f64](a, nf * nw)
    let (d2h, e7) = mem.alloc[f64](a, nf * np)
    let (fm, e8) = mem.alloc[f64](a, 1usize)
    let (gcur, e9) = mem.alloc[f64](a, nw)
    let (gold, e10) = mem.alloc[f64](a, nw)
    let (hess, e11) = mem.alloc[f64](a, nw * nw)
    let (deltac, e12) = mem.alloc[f64](a, nw)
    let (cold, e13) = mem.alloc[f64](a, nw)
    let (cnew, e14) = mem.alloc[f64](a, nw)
    let (ctmp, e15) = mem.alloc[f64](a, nw)
    let (rcur, e16) = mem.alloc[f64](a, 2usize)
    let (lmat, e17) = mem.alloc[f64](a, 15usize)
    let (lim, e18) = mem.alloc[usize](a, 2usize)
    let (dbl, e19) = mem.alloc[usize](a, 2usize)
    let (ips, e20) = mem.alloc[usize](a, 1usize)
    let (indv, e21) = mem.alloc[usize](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok { ret mem.Full }
    eval_curve(a, cx.yn, cx.yb, ycoefs, cx.xfine, 0usize, yfine)
    eval_curve(a, cx.yn, cx.yb, y0coefs, cx.xfine, 0usize, y0fine)
    var e = reg_h(a, cx, cvec, true, ffine, dffine, hfine, dhfine, d2h, fm)
    if e != ok { ret e }
    e = reg_yfn(a, cx, cvec, hfine, yfine, ycoefs, yreg)
    if e != ok { ret e }
    e = reg_fg(a, cx, y0fine, dhfine, yreg, cvec, rcur, gcur)
    if e != ok { ret e }
    e = reg_hs(a, cx, y0fine, dhfine, d2h, yreg, hess)
    if e != ok { ret e }
    let _c0 = reg_direction(a, nw, hess, gcur, deltac)
    var fcur = rcur[0usize]
    var fold = fcur
    var q = 0usize
    while q < nw {
        gold[q] = gcur[q]
        cold[q] = cvec[q]
        q += 1usize
    }
    var trial = 1.0f64
    var reset = 0usize
    q = 0usize
    while q < 15usize {
        lmat[q] = 0.0f64
        q += 1usize
    }
    ips[0usize] = 0usize
    var iter = 1usize
    var outer = true
    while iter <= iterlim && outer {
        dbl[0usize] = 0usize
        dbl[1usize] = 0usize
        lim[0usize] = 0usize
        lim[1usize] = 0usize
        indv[0usize] = 0usize
        ips[0usize] = 0usize
        var slope = 0.0f64
        var sdg = 0.0f64
        q = 0usize
        while q < nw {
            slope += deltac[q] * gold[q]
            sdg += deltac[q] * deltac[q]
            q += 1usize
        }
        sdg = math.sqrt[f64](sdg)
        q = 0usize
        while q < nw {
            deltac[q] = deltac[q] / sdg
            q += 1usize
        }
        slope = slope / sdg
        var c = 0usize
        while c < 4usize {
            lmat[c * 3usize] = 0.0f64
            lmat[c * 3usize + 1usize] = slope
            lmat[c * 3usize + 2usize] = fcur
            c += 1usize
        }
        var cutoff = 1.0e-3f64
        if conv < cutoff { cutoff = conv }
        if slope >= 0.0f64 {
            outer = false
        } else if slope >= 0.0f64 - cutoff {
            outer = false
        }
        if outer {
            lmat[12usize] = trial
            q = 0usize
            while q < nw {
                cnew[q] = cvec[q]
                q += 1usize
            }
            var stepiter = 1usize
            var inner = true
            while stepiter <= 5usize && inner {
                lmat[12usize] = step_chk(lmat[12usize], cvec, deltac, lim, indv, nw)
                if indv[0usize] == 1usize {
                    inner = false
                } else if lmat[12usize] <= 1.0e-7f64 {
                    inner = false
                } else {
                    q = 0usize
                    while q < nw {
                        cnew[q] = cvec[q] + lmat[12usize] * deltac[q]
                        ctmp[q] = cnew[q]
                        q += 1usize
                    }
                    ctmp[0usize] = 0.0f64
                    e = reg_h(a, cx, ctmp, false, ffine, dffine, hfine, dhfine, d2h, fm)
                    if e != ok { ret e }
                    e = reg_yfn(a, cx, ctmp, hfine, yfine, ycoefs, yreg)
                    if e != ok { ret e }
                    e = reg_fg(a, cx, y0fine, dhfine, yreg, cnew, rcur, gcur)
                    if e != ok { ret e }
                    fcur = rcur[0usize]
                    lmat[14usize] = fcur
                    var sl = 0.0f64
                    q = 0usize
                    while q < nw {
                        sl += deltac[q] * gcur[q]
                        q += 1usize
                    }
                    lmat[13usize] = sl
                    indv[0usize] = step_it(lmat, ips, dbl, 100.0f64)
                    trial = lmat[12usize]
                    if indv[0usize] == 0usize || indv[0usize] == 5usize { inner = false }
                }
                stepiter += 1usize
            }
            q = 0usize
            while q < nw {
                cvec[q] = cnew[q]
                q += 1usize
            }
            if fcur > fold {
                q = 0usize
                while q < nw {
                    cvec[q] = cold[q]
                    gcur[q] = gold[q]
                    deltac[q] = 0.0f64 - gold[q]
                    q += 1usize
                }
                fcur = fold
                if reset == 1usize {
                    outer = false
                } else {
                    reset = 1usize
                }
            } else {
                var df = fold - fcur
                if df < 0.0f64 { df = 0.0f64 - df }
                if df < conv {
                    outer = false
                } else {
                    q = 0usize
                    while q < nw {
                        cold[q] = cvec[q]
                        gold[q] = gcur[q]
                        ctmp[q] = cvec[q]
                        q += 1usize
                    }
                    fold = fcur
                    ctmp[0usize] = 0.0f64
                    // the Hessian is taken at the last trial's quadrature values, which are those of cvec
                    e = reg_h(a, cx, ctmp, true, ffine, dffine, hfine, dhfine, d2h, fm)
                    if e != ok { ret e }
                    e = reg_hs(a, cx, y0fine, dhfine, d2h, yreg, hess)
                    if e != ok { ret e }
                    let _cs = reg_direction(a, nw, hess, gcur, deltac)
                    reset = 0usize
                }
            }
        }
        iter += 1usize
    }
    ret ok
}

// register.fd(y0fd, yfd, fdPar(Wbasis, Lfd = m, lambda)) with the curves ycoefs (ynb by ncurve) in the B-spline basis (yn, yb), the tgt y0coefs (ynb) and W starting at wc0 (nw by ncurve, the same start for all curves is allowed by passing it repeated).
// regc receives the registered curves' coefficients (ynb by ncurve), wc the W coefficients (nw by ncurve), warpc the coefficients of warpfd in the W basis (nw by ncurve)
fn register_fd(a: *mem.Arena, yn: usize, yb: []const f64, wn: usize, wb: []const f64, m: usize, lambda: f64, ncurve: usize, ycoefs: []const f64, y0coefs: []const f64, wc0: []const f64, regc: []f64, wc: []f64, warpc: []f64) -> err {
    ret register_fd_crit(a, yn, yb, wn, wb, m, lambda, 2usize, ncurve, ycoefs, y0coefs, wc0, regc, wc, warpc)
}

// register.fd with crit 1 (the sum of squared differences from the target) or 2 (the smallest eigenvalue of the cross-product matrix, the default)
fn register_fd_crit(a: *mem.Arena, yn: usize, yb: []const f64, wn: usize, wb: []const f64, m: usize, lambda: f64, crit: usize, ncurve: usize, ycoefs: []const f64, y0coefs: []const f64, wc0: []const f64, regc: []f64, wc: []f64, warpc: []f64) -> err {
    let ynb = yb.len + yn - 2usize
    let nw = wb.len + wn - 2usize
    var nfine = 10usize * ynb + 1usize
    if nfine < 201usize { nfine = 201usize }
    let (xf, e1) = mem.alloc[f64](a, nfine)
    let (kmat, e2) = mem.alloc[f64](a, nw * nw)
    let (pm, e3) = mem.alloc[f64](a, nw * nw)
    let (gram, e4) = mem.alloc[f64](a, ynb * ynb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let lo = yb[0usize]
    let hi = yb[yb.len - 1usize]
    var i = 0usize
    while i < nfine {
        xf[i] = fr.seq_at(lo, hi, nfine, i)
        i += 1usize
    }
    var e = fa.penalty_matrix(a, yn, yb, 0usize, gram)
    if e != ok { ret e }
    var haspen = false
    if lambda > 0.0f64 {
        haspen = true
        e = fa.penalty_matrix(a, wn, wb, m, pm)
        if e != ok { ret e }
        var r = 1usize
        while r < nw {
            var c = 1usize
            while c < nw {
                kmat[(c - 1usize) * (nw - 1usize) + (r - 1usize)] = lambda * pm[c * nw + r]
                c += 1usize
            }
            r += 1usize
        }
    }
    let cx = RegCtx { yn: yn, yb: yb, ynb: ynb, wn: wn, wb: wb, nw: nw, nfine: nfine, lo: lo, hi: hi, xfine: xf, kmat: kmat, haspen: haspen, gram: gram, crit: crit }
    let (cv, e5) = mem.alloc[f64](a, nw)
    let (yr, e6) = mem.alloc[f64](a, ynb)
    if e5 != ok || e6 != ok { ret mem.Full }
    var ic = 0usize
    while ic < ncurve {
        let st = mem.mark(a)
        i = 0usize
        while i < nw {
            cv[i] = wc0[ic * nw + i]
            i += 1usize
        }
        e = register_curve(a, &cx, ycoefs[ic * ynb..ic * ynb + ynb], y0coefs, 1.0e-4f64, 20usize, cv, yr)
        if e != ok { ret e }
        mem.reset(a, st)
        i = 0usize
        while i < nw {
            wc[ic * nw + i] = cv[i]
            i += 1usize
        }
        i = 0usize
        while i < ynb {
            regc[ic * ynb + i] = yr[i]
            i += 1usize
        }
        ic += 1usize
    }
    // warpfd: eval.monfd of the final W, rescaled onto the range, smoothed in the W basis
    let (wm, e7) = mem.alloc[f64](a, nfine * ncurve)
    let (hf, e8) = mem.alloc[f64](a, nfine)
    if e7 != ok || e8 != ok { ret mem.Full }
    ic = 0usize
    while ic < ncurve {
        e = fr.mon_eval(a, wn, wb, wc[ic * nw..ic * nw + nw], xf, false, hf)
        if e != ok { ret e }
        i = 0usize
        while i < nfine {
            wm[ic * nfine + i] = lo + (hi - lo) * hf[i] / hf[nfine - 1usize]
            i += 1usize
        }
        ic += 1usize
    }
    ret lm.smooth_basis_multi(a, wn, wb, xf, wm, ncurve, 2usize, 0.0f64, warpc)
}
