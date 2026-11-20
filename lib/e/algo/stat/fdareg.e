// R fda, the pieces built on the B-spline basis of fdapkg: deriv.fd, smooth.fd, eval.monfd with monfn and mongrad, zerobasis, smooth.morph and landmarkreg.
// Matrices are column-major as R passes them. A basis is (norder, breaks), the breaks including the end points; nbasis = breaks + norder - 2.
//
// Not here: register.fd, the other basis types, the Lfd operators beyond a derivative order.

use e.algo.stat.bayesmpkg as bz
use e.algo.stat.fdapkg as fa
use e.math
use e.mem

fn fd_nan() -> f64 { ret 0.0f64 / 0.0f64 }

// solve A x = b for nr right-hand sides by Gaussian elimination with partial pivoting (LAPACK dgesv's order); m is destroyed, b is overwritten with the solution
fn lu_solve(m: []f64, n: usize, b: []f64, nr: usize) -> bool {
    var k = 0usize
    while k < n {
        var p = k
        var best = math.abs[f64](m[k * n + k])
        var i = k + 1usize
        while i < n {
            let v = math.abs[f64](m[k * n + i])
            if v > best {
                best = v
                p = i
            }
            i += 1usize
        }
        if best == 0.0f64 { ret false }
        if p != k {
            var j = 0usize
            while j < n {
                let t = m[j * n + k]
                m[j * n + k] = m[j * n + p]
                m[j * n + p] = t
                j += 1usize
            }
            j = 0usize
            while j < nr {
                let t = b[j * n + k]
                b[j * n + k] = b[j * n + p]
                b[j * n + p] = t
                j += 1usize
            }
        }
        i = k + 1usize
        while i < n {
            let f = m[k * n + i] / m[k * n + k]
            m[k * n + i] = f
            var j = k + 1usize
            while j < n {
                m[j * n + i] -= f * m[j * n + k]
                j += 1usize
            }
            j = 0usize
            while j < nr {
                b[j * n + i] -= f * b[j * n + k]
                j += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    var c = 0usize
    while c < nr {
        var i = n
        while i > 0usize {
            i -= 1usize
            var s = b[c * n + i]
            var j = i + 1usize
            while j < n {
                s -= m[j * n + i] * b[c * n + j]
                j += 1usize
            }
            b[c * n + i] = s / m[i * n + i]
        }
        c += 1usize
    }
    ret true
}

// solve the symmetric positive definite system m x = rhs through its Cholesky factor, as smooth.basis and symsolve do; out is n by nr
fn spd_solve(a: *mem.Arena, m: []const f64, n: usize, rhs: []const f64, nr: usize, out: []f64) -> err {
    let (u, e1) = mem.alloc[f64](a, n * n)
    let (iu, e2) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok { ret mem.Full }
    if !bz.chol_upper(m, n, u) { ret mem.Full }
    bz.inv_upper(u, n, iu)
    var c = 0usize
    while c < nr {
        var i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j < n {
                var inv = 0.0f64
                var k = 0usize
                while k < n {
                    inv += iu[k * n + i] * iu[k * n + j]
                    k += 1usize
                }
                s += inv * rhs[c * n + j]
                j += 1usize
            }
            out[c * n + i] = s
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// seq(lo, hi, length.out = n)[i]
fn seq_at(lo: f64, hi: f64, n: usize, i: usize) -> f64 {
    if i + 1usize == n { ret hi }
    ret lo + f64(i) * ((hi - lo) / f64(n - 1usize))
}

// deriv.fd(fd(coefs, basis), m): the m-th derivative sampled at 10 nbasis + 1 equally spaced points and projected on the same basis by least squares; out has nbasis coefficients
fn deriv_fd(a: *mem.Arena, norder: usize, breaks: []const f64, coefs: []const f64, m: usize, out: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let nx = 10usize * nb + 1usize
    let (bm, e1) = mem.alloc[f64](a, nb * nb)
    let (rhs, e2) = mem.alloc[f64](a, nb)
    let (v, e3) = mem.alloc[f64](a, nb + norder)
    let (dv, e4) = mem.alloc[f64](a, nb + norder)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
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
    while t < nx {
        let x = seq_at(breaks[0usize], breaks[breaks.len - 1usize], nx, t)
        var e = fa.eval_bspline(a, norder, breaks, x, 0usize, v)
        if e != ok { ret e }
        e = fa.eval_bspline(a, norder, breaks, x, m, dv)
        if e != ok { ret e }
        var y = 0.0f64
        var i = 0usize
        while i < nb {
            y += coefs[i] * dv[i]
            i += 1usize
        }
        i = 0usize
        while i < nb {
            var j = 0usize
            while j < nb {
                bm[j * nb + i] += v[i] * v[j]
                j += 1usize
            }
            rhs[i] += v[i] * y
            i += 1usize
        }
        t += 1usize
    }
    ret spd_solve(a, bm, nb, rhs, 1usize, out)
}

// smooth.fd(fd(coefs, basis), fdPar(basis, m, lambda)) for nrep curves in the same basis: (J + lambda R) c = J coefs with J fda's numerical inprod and R the m-th derivative penalty; out is nbasis by nrep
fn smooth_fd(a: *mem.Arena, norder: usize, breaks: []const f64, coefs: []const f64, nrep: usize, m: usize, lambda: f64, out: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let (jm, e1) = mem.alloc[f64](a, nb * nb)
    let (dm, e2) = mem.alloc[f64](a, nb * nrep)
    let (pm, e3) = mem.alloc[f64](a, nb * nb)
    let (id, e4) = mem.alloc[f64](a, nb * nb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var q = 0usize
    while q < nb * nb {
        id[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nb {
        id[q * nb + q] = 1.0f64
        q += 1usize
    }
    var e = fa.inprod_coefs(a, norder, breaks, id, nb, id, nb, jm)
    if e != ok { ret e }
    e = fa.inprod_coefs(a, norder, breaks, id, nb, coefs, nrep, dm)
    if e != ok { ret e }
    e = fa.penalty_matrix(a, norder, breaks, m, pm)
    if e != ok { ret e }
    q = 0usize
    while q < nb * nb {
        jm[q] += lambda * pm[q]
        q += 1usize
    }
    q = 0usize
    while q < nb * nrep {
        out[q] = dm[q]
        q += 1usize
    }
    if !lu_solve(jm, nb, out, nrep) { ret mem.Full }
    ret ok
}

// polintmat(h[ind], smat[ind, ], 0) for five rows whose abscissas h decrease: the Neville extrapolation to zero of each of the nc columns of ya (row r, column c at r * nc + c); ss is the extrapolation, dy the last correction
fn polint5(h: []const f64, ya: []const f64, nc: usize, cs: []f64, ds: []f64, ss: []f64, dy: []f64) {
    var r = 0usize
    while r < 5usize {
        var c = 0usize
        while c < nc {
            cs[r * nc + c] = ya[r * nc + c]
            ds[r * nc + c] = ya[r * nc + c]
            c += 1usize
        }
        r += 1usize
    }
    var c0 = 0usize
    while c0 < nc {
        ss[c0] = ya[4usize * nc + c0]
        c0 += 1usize
    }
    var ns = 4usize
    var mm = 1usize
    while mm <= 4usize {
        var i = 0usize
        while i < 5usize - mm {
            let ho = h[i]
            let hp = h[i + mm]
            var c = 0usize
            while c < nc {
                let w = (cs[(i + 1usize) * nc + c] - ds[i * nc + c]) / (ho - hp)
                ds[i * nc + c] = hp * w
                cs[i * nc + c] = ho * w
                c += 1usize
            }
            i += 1usize
        }
        var c = 0usize
        if 2usize * ns < 5usize - mm {
            while c < nc {
                dy[c] = cs[ns * nc + c]
                c += 1usize
            }
        } else {
            while c < nc {
                dy[c] = ds[(ns - 1usize) * nc + c]
                c += 1usize
            }
            ns -= 1usize
        }
        c = 0usize
        while c < nc {
            ss[c] += dy[c]
            c += 1usize
        }
        mm += 1usize
    }
}

// approx(tv, fv, x)$y for one column of values with stride 1 starting at fv[0]; NaN outside the range
fn approx_lin(tv: []const f64, fv: []const f64, n: usize, v: f64) -> f64 {
    if v < tv[0usize] || v > tv[n - 1usize] { ret fd_nan() }
    var i = 0usize
    var j = n - 1usize
    while i + 1usize < j {
        let ij = (i + j) / 2usize
        if v < tv[ij] {
            j = ij
        } else {
            i = ij
        }
    }
    if v == tv[j] { ret fv[j] }
    if v == tv[i] { ret fv[i] }
    ret fv[i] + (fv[j] - fv[i]) * ((v - tv[i]) / (tv[j] - tv[i]))
}

// monfn(xs, Wfd) (grad false: the monotone function D^-1 exp W, out has xs.len values) or mongrad(xs, Wfd) (grad true: its gradient with respect to the coefficients, xs.len by nbasis). Both are fda's Romberg quadrature on the dyadic
// grid with its quirks kept: the grid skips the midpoint, the cumulative sum steps by the first spacing, and mongrad sums over every point so far at each level. Err when the quadrature does not converge in 15 levels (monfn only)
fn mon_eval(a: *mem.Arena, norder: usize, breaks: []const f64, coefs: []const f64, xs: []const f64, grad: bool, out: []f64) -> err {
    let st0 = mem.mark(a)
    let nb = breaks.len + norder - 2usize
    var nc = 1usize
    if grad { nc = nb }
    let cap = 32770usize
    let (tv, e1) = mem.alloc[f64](a, cap)
    let (fv, e2) = mem.alloc[f64](a, cap * nc)
    let (tt, e3) = mem.alloc[f64](a, cap)
    let (ft, e4) = mem.alloc[f64](a, cap * nc)
    let (tn, e5) = mem.alloc[f64](a, cap)
    let (fnew, e6) = mem.alloc[f64](a, cap * nc)
    let (smat, e7) = mem.alloc[f64](a, 17usize * nc)
    let (hh, e8) = mem.alloc[f64](a, 17usize)
    let (v, e9) = mem.alloc[f64](a, nb + norder)
    let (cs, e10) = mem.alloc[f64](a, 5usize * nc)
    let (ds, e11) = mem.alloc[f64](a, 5usize * nc)
    let (ss, e12) = mem.alloc[f64](a, nc)
    let (dy, e13) = mem.alloc[f64](a, nc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    let lo = breaks[0usize]
    let hi = breaks[breaks.len - 1usize]
    let width = hi - lo
    hh[0usize] = 1.0f64
    hh[1usize] = 0.25f64
    var q = 0usize
    while q < 17usize * nc {
        smat[q] = 0.0f64
        q += 1usize
    }
    // level 1: the two end points
    var cnt = 0usize
    var side = 0usize
    while side < 2usize {
        var xe = lo
        if side == 1usize { xe = hi }
        let st = mem.mark(a)
        let e = fa.eval_bspline(a, norder, breaks, xe, 0usize, v)
        if e != ok { ret e }
        mon_row(v, nb, coefs, grad, fv[cnt * nc..cnt * nc + nc])
        mem.reset(a, st)
        tv[cnt] = xe
        cnt += 1usize
        side += 1usize
    }
    var c = 0usize
    while c < nc {
        smat[c] = width * (fv[c] + fv[nc + c]) / 2.0f64
        c += 1usize
    }
    var tnm = 0.5f64
    var j = 2usize
    var done = false
    while j <= 15usize && !done {
        tnm = tnm * 2.0f64
        let del = width / tnm
        let nnew = usize(tnm)
        var k = 0usize
        while k < nnew {
            let x = lo + del / 2.0f64 + f64(k) * del
            let st = mem.mark(a)
            let e = fa.eval_bspline(a, norder, breaks, x, 0usize, v)
            if e != ok { ret e }
            mon_row(v, nb, coefs, grad, fnew[k * nc..k * nc + nc])
            mem.reset(a, st)
            tn[k] = x
            k += 1usize
        }
        // merge the new sorted points into tv / fv
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
            c = 0usize
            if takea {
                tt[iw] = tv[ia]
                while c < nc {
                    ft[iw * nc + c] = fv[ia * nc + c]
                    c += 1usize
                }
                ia += 1usize
            } else {
                tt[iw] = tn[ib]
                while c < nc {
                    ft[iw * nc + c] = fnew[ib * nc + c]
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
            c = 0usize
            while c < nc {
                fv[k * nc + c] = ft[k * nc + c]
                c += 1usize
            }
            k += 1usize
        }
        c = 0usize
        while c < nc {
            var sum = 0.0f64
            if grad {
                k = 0usize
                while k < cnt {
                    sum += fv[k * nc + c]
                    k += 1usize
                }
            } else {
                k = 0usize
                while k < nnew {
                    sum += fnew[k * nc + c]
                    k += 1usize
                }
            }
            smat[(j - 1usize) * nc + c] = (smat[(j - 2usize) * nc + c] + width * sum / tnm) / 2.0f64
            c += 1usize
        }
        if j >= 11usize {
            fd_polint_rows(hh[j - 5usize..j], smat[(j - 5usize) * nc..j * nc], nc, cs, ds, ss, dy)
            var smax = 0.0f64
            var all_small = true
            c = 0usize
            while c < nc {
                if math.abs[f64](ss[c]) > smax { smax = math.abs[f64](ss[c]) }
                c += 1usize
            }
            c = 0usize
            while c < nc {
                if !(math.abs[f64](dy[c]) < 1.0e-5f64 * smax) { all_small = false }
                c += 1usize
            }
            if all_small || (grad && j >= 15usize) { done = true }
        }
        if !done {
            c = 0usize
            while c < nc {
                smat[j * nc + c] = smat[(j - 1usize) * nc + c]
                c += 1usize
            }
            hh[j] = 0.25f64 * hh[j - 1usize]
            j += 1usize
        }
    }
    if !done { ret mem.Full }
    // fval <- del * (cumsum(fval) - 0.5 * (fval[1] + fval)), then linear interpolation
    let step = tv[1usize] - tv[0usize]
    c = 0usize
    while c < nc {
        let f0 = fv[c]
        var run = 0.0f64
        var k = 0usize
        while k < cnt {
            run += fv[k * nc + c]
            ft[k * nc + c] = step * (run - 0.5f64 * (f0 + fv[k * nc + c]))
            k += 1usize
        }
        k = 0usize
        while k < cnt {
            tn[k] = ft[k * nc + c]
            k += 1usize
        }
        var r = 0usize
        while r < xs.len {
            out[c * xs.len + r] = approx_lin(tv, tn, cnt, xs[r])
            r += 1usize
        }
        c += 1usize
    }
    mem.reset(a, st0)
    ret ok
}

// the five rows ending at row j of the history, handed to polint5 (a thin wrapper so the call site reads as polintmat(h[ind], smat[ind, ], 0))
fn fd_polint_rows(h5: []const f64, rows: []const f64, nc: usize, cs: []f64, ds: []f64, ss: []f64, dy: []f64) {
    polint5(h5, rows, nc, cs, ds, ss, dy)
}

// one row of the quadrature: exp(W(t)) (grad false) or exp(W(t)) times every basis function (grad true), W(t) = sum coefs[k] v[k]
fn mon_row(v: []const f64, nb: usize, coefs: []const f64, grad: bool, row: []f64) {
    var w = 0.0f64
    var k = 0usize
    while k < nb {
        w += v[k] * coefs[k]
        k += 1usize
    }
    let fx = math.exp[f64](w)
    if grad {
        k = 0usize
        while k < nb {
            row[k] = fx * v[k]
            k += 1usize
        }
    } else {
        row[0usize] = fx
    }
}

// eval.monfd(x, fd(coefs, basis), Lfdobj = deriv) for deriv 0 .. 3: D^-1 exp W, exp W, DW exp W, (D2W + DW^2) exp W
fn eval_monfd(a: *mem.Arena, norder: usize, breaks: []const f64, coefs: []const f64, x: f64, deriv: usize) -> f64 {
    let nb = breaks.len + norder - 2usize
    if deriv == 0usize {
        let (xs, ex) = mem.alloc[f64](a, 1usize)
        let (o, e) = mem.alloc[f64](a, 1usize)
        if e != ok || ex != ok { ret fd_nan() }
        xs[0usize] = x
        if mon_eval(a, norder, breaks, coefs, xs[0usize..1usize], false, o) != ok { ret fd_nan() }
        ret o[0usize]
    }
    let (v, e1) = mem.alloc[f64](a, nb + norder)
    if e1 != ok { ret fd_nan() }
    if fa.eval_bspline(a, norder, breaks, x, 0usize, v) != ok { ret fd_nan() }
    var w = 0.0f64
    var k = 0usize
    while k < nb {
        w += v[k] * coefs[k]
        k += 1usize
    }
    let ew = math.exp[f64](w)
    if deriv == 1usize { ret ew }
    if fa.eval_bspline(a, norder, breaks, x, 1usize, v) != ok { ret fd_nan() }
    var dw = 0.0f64
    k = 0usize
    while k < nb {
        dw += v[k] * coefs[k]
        k += 1usize
    }
    if deriv == 2usize { ret dw * ew }
    if fa.eval_bspline(a, norder, breaks, x, 2usize, v) != ok { ret fd_nan() }
    var d2w = 0.0f64
    k = 0usize
    while k < nb {
        d2w += v[k] * coefs[k]
        k += 1usize
    }
    ret (d2w + dw * dw) * ew
}

// zerobasis(k): k by (k - 1) column-normalised Fourier contrasts that sum to zero over the k points 0.5 .. k - 0.5
fn zero_basis(a: *mem.Arena, k: usize, out: []f64) -> err {
    if k == 2usize {
        let s = 1.0f64 / math.sqrt[f64](2.0f64)
        out[0usize] = s
        out[1usize] = 0.0f64 - s
        ret ok
    }
    var nbf = k
    if k % 2usize == 0usize { nbf = k + 1usize }
    let (row, e) = mem.alloc[f64](a, nbf)
    if e != ok { ret e }
    var r = 0usize
    while r < k {
        fa.eval_fourier(nbf, f64(k), f64(r) + 0.5f64, 0usize, row)
        var c = 1usize
        while c < k {
            out[(c - 1usize) * k + r] = row[c]
            c += 1usize
        }
        r += 1usize
    }
    var c = 0usize
    while c < k - 1usize {
        var s = 0.0f64
        r = 0usize
        while r < k {
            s += out[c * k + r] * out[c * k + r]
            r += 1usize
        }
        s = math.sqrt[f64](s)
        r = 0usize
        while r < k {
            out[c * k + r] = out[c * k + r] / s
            r += 1usize
        }
        c += 1usize
    }
    ret ok
}

// the criterion, gradient and Hessian of smooth.morph (fngrad_morph) at the reduced parameter bvec; wbreaks is the basis of W, xs the nobs abscissas, ys the values, zm the zerobasis (nw by nw - 1), kmat the penalty matrix already scaled by lambda (or all zero)
// res = (f, norm); grad has nw - 1 entries and hess (nw - 1) squared
fn morph_fngrad(a: *mem.Arena, norder: usize, wbreaks: []const f64, xs: []const f64, ys: []const f64, wt: []const f64, ylo: f64, yhi: f64, kmat: []const f64, haspen: bool, zm: []const f64, bvec: []const f64, res: []f64, grad: []f64, hess: []f64) -> err {
    let st0 = mem.mark(a)
    let nw = wbreaks.len + norder - 2usize
    let nz = nw - 1usize
    let nobs = xs.len
    let (cvec, e0) = mem.alloc[f64](a, nw)
    let (xe, e1) = mem.alloc[f64](a, nobs + 2usize)
    let (hv, e2) = mem.alloc[f64](a, nobs + 2usize)
    let (gv, e3) = mem.alloc[f64](a, (nobs + 2usize) * nw)
    let (dh, e4) = mem.alloc[f64](a, nobs * nw)
    let (g0, e5) = mem.alloc[f64](a, nw)
    let (h0, e6) = mem.alloc[f64](a, nw * nw)
    let (rs, e7) = mem.alloc[f64](a, nobs)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var i = 0usize
    while i < nw {
        var s = 0.0f64
        var j = 0usize
        while j < nz {
            s += zm[j * nw + i] * bvec[j]
            j += 1usize
        }
        cvec[i] = s
        i += 1usize
    }
    let xlo = wbreaks[0usize]
    let xhi = wbreaks[wbreaks.len - 1usize]
    i = 0usize
    while i < nobs {
        xe[i] = xs[i]
        i += 1usize
    }
    xe[nobs] = xhi
    xe[nobs + 1usize] = xlo
    var e = mon_eval(a, norder, wbreaks, cvec, xe, false, hv)
    if e != ok { ret e }
    e = mon_eval(a, norder, wbreaks, cvec, xe, true, gv)
    if e != ok { ret e }
    let np2 = nobs + 2usize
    let hmax = hv[nobs]
    let hmin = hv[nobs + 1usize]
    let hwidth = hmax - hmin
    let ywidth = yhi - ylo
    var f = 0.0f64
    i = 0usize
    while i < nobs {
        let hi_ = (ylo - hmin) + hv[i] * (ywidth / hwidth)
        rs[i] = ys[i] - hi_
        f += rs[i] * rs[i] * wt[i]
        i += 1usize
    }
    f = f / f64(nobs)
    var k = 0usize
    while k < nw {
        let dwidth = gv[k * np2 + nobs] - gv[k * np2 + nobs + 1usize]
        i = 0usize
        while i < nobs {
            dh[k * nobs + i] = ywidth * (gv[k * np2 + i] * hwidth - hv[i] * dwidth) / (hwidth * hwidth)
            i += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < nw {
        var s = 0.0f64
        i = 0usize
        while i < nobs {
            s += dh[k * nobs + i] * wt[i] * rs[i]
            i += 1usize
        }
        g0[k] = -2.0f64 * s / f64(nobs)
        k += 1usize
    }
    if haspen {
        k = 0usize
        while k < nw {
            var kc = 0.0f64
            var l = 0usize
            while l < nw {
                kc += kmat[l * nw + k] * cvec[l]
                l += 1usize
            }
            g0[k] += 2.0f64 * kc
            f += cvec[k] * kc
            k += 1usize
        }
    }
    k = 0usize
    while k < nw {
        var l = 0usize
        while l < nw {
            var s = 0.0f64
            i = 0usize
            while i < nobs {
                s += (dh[k * nobs + i] * math.sqrt[f64](wt[i])) * (dh[l * nobs + i] * math.sqrt[f64](wt[i]))
                i += 1usize
            }
            h0[l * nw + k] = 2.0f64 * s / f64(nobs)
            if haspen { h0[l * nw + k] += 2.0f64 * kmat[l * nw + k] }
            l += 1usize
        }
        k += 1usize
    }
    var nrm = 0.0f64
    var p = 0usize
    while p < nz {
        var s = 0.0f64
        k = 0usize
        while k < nw {
            s += zm[p * nw + k] * g0[k]
            k += 1usize
        }
        grad[p] = s
        nrm += s * s
        var q = 0usize
        while q < nz {
            var t2 = 0.0f64
            k = 0usize
            while k < nw {
                var inner = 0.0f64
                var l = 0usize
                while l < nw {
                    inner += h0[l * nw + k] * zm[q * nw + l]
                    l += 1usize
                }
                t2 += zm[p * nw + k] * inner
                k += 1usize
            }
            hess[q * nz + p] = t2
            q += 1usize
        }
        p += 1usize
    }
    res[0usize] = f
    res[1usize] = math.sqrt[f64](nrm)
    mem.reset(a, st0)
    ret ok
}

// smooth.morph(x, y, ylim, fdPar(Wbasis, Lfd = m, lambda), conv, iterlim) with the W basis of order norder on wbreaks, initial coefficients c0, weights 1 except 10 on the last observation; x[0] and x[last] are moved onto the range ends as fda does.
// coef receives the nbasis coefficients of W; stats receives (f, gradient norm, iterations)
fn smooth_morph(a: *mem.Arena, norder: usize, wbreaks: []const f64, m: usize, lambda: f64, c0: []const f64, xin: []const f64, ys: []const f64, ylo: f64, yhi: f64, conv: f64, iterlim: usize, coef: []f64, stats: []f64) -> err {
    let nw = wbreaks.len + norder - 2usize
    let nz = nw - 1usize
    let nobs = xin.len
    let (xs, e1) = mem.alloc[f64](a, nobs)
    let (wt, e2) = mem.alloc[f64](a, nobs)
    let (zm, e3) = mem.alloc[f64](a, nw * nz)
    let (kmat, e4) = mem.alloc[f64](a, nw * nw)
    let (bvec, e5) = mem.alloc[f64](a, nz)
    let (cvec, e6) = mem.alloc[f64](a, nw)
    let (cold, e7) = mem.alloc[f64](a, nw)
    let (grad, e8) = mem.alloc[f64](a, nz)
    let (hess, e9) = mem.alloc[f64](a, nz * nz)
    let (pvec, e10) = mem.alloc[f64](a, nz)
    let (bold, e11) = mem.alloc[f64](a, nz)
    let (hcp, e12) = mem.alloc[f64](a, nz * nz)
    let (rs, e13) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    var i = 0usize
    while i < nobs {
        xs[i] = xin[i]
        wt[i] = 1.0f64
        i += 1usize
    }
    wt[nobs - 1usize] = 10.0f64
    xs[0usize] = wbreaks[0usize]
    xs[nobs - 1usize] = wbreaks[wbreaks.len - 1usize]
    var e = zero_basis(a, nw, zm)
    if e != ok { ret e }
    var haspen = false
    var q = 0usize
    if lambda > 0.0f64 {
        haspen = true
        e = fa.penalty_matrix(a, norder, wbreaks, m, kmat)
        if e != ok { ret e }
        q = 0usize
        while q < nw * nw {
            kmat[q] = lambda * kmat[q]
            q += 1usize
        }
    }
    // bvec = Z' c0, cvec = Z bvec
    var p = 0usize
    while p < nz {
        var s = 0.0f64
        i = 0usize
        while i < nw {
            s += zm[p * nw + i] * c0[i]
            i += 1usize
        }
        bvec[p] = s
        p += 1usize
    }
    i = 0usize
    while i < nw {
        var s = 0.0f64
        p = 0usize
        while p < nz {
            s += zm[p * nw + i] * bvec[p]
            p += 1usize
        }
        cvec[i] = s
        cold[i] = s
        i += 1usize
    }
    e = morph_fngrad(a, norder, wbreaks, xs, ys, wt, ylo, yhi, kmat, haspen, zm, bvec, rs, grad, hess)
    if e != ok { ret e }
    var f = rs[0usize]
    var fold = f
    var nrm = rs[1usize]
    q = 0usize
    while q < nz * nz {
        hcp[q] = hess[q]
        q += 1usize
    }
    p = 0usize
    while p < nz {
        pvec[p] = 0.0f64 - grad[p]
        p += 1usize
    }
    if !lu_solve(hcp, nz, pvec, 1usize) { ret mem.Full }
    // pvec = -solve(hmat, grad): lu_solve solved hmat pvec = -grad already
    var iternum = 0usize
    var it = 1usize
    while it <= iterlim {
        iternum += 1usize
        // bvecold = Z' cvecold
        p = 0usize
        while p < nz {
            var s = 0.0f64
            i = 0usize
            while i < nw {
                s += zm[p * nw + i] * cold[i]
                i += 1usize
            }
            bold[p] = s
            p += 1usize
        }
        e = morph_linesearch(a, norder, wbreaks, xs, ys, wt, ylo, yhi, kmat, haspen, zm, bold, fold, grad, pvec, bvec)
        if e != ok { ret e }
        e = morph_fngrad(a, norder, wbreaks, xs, ys, wt, ylo, yhi, kmat, haspen, zm, bvec, rs, grad, hess)
        if e != ok { ret e }
        f = rs[0usize]
        nrm = rs[1usize]
        i = 0usize
        while i < nw {
            var s = 0.0f64
            p = 0usize
            while p < nz {
                s += zm[p * nw + i] * bvec[p]
                p += 1usize
            }
            cvec[i] = s
            i += 1usize
        }
        if math.abs[f64](f - fold) < conv { break }
        if f >= fold { break }
        q = 0usize
        while q < nz * nz {
            hcp[q] = hess[q]
            q += 1usize
        }
        p = 0usize
        while p < nz {
            pvec[p] = 0.0f64 - grad[p]
            p += 1usize
        }
        if !lu_solve(hcp, nz, pvec, 1usize) { ret mem.Full }
        var gp = 0.0f64
        var gg = 0.0f64
        var pp = 0.0f64
        p = 0usize
        while p < nz {
            gp += grad[p] * pvec[p]
            gg += grad[p] * grad[p]
            pp += pvec[p] * pvec[p]
            p += 1usize
        }
        let cosangle = (0.0f64 - gp) / math.sqrt[f64](gg * pp)
        if cosangle < 0.0f64 {
            p = 0usize
            while p < nz {
                pvec[p] = 0.0f64 - grad[p]
                p += 1usize
            }
        }
        fold = f
        i = 0usize
        while i < nw {
            cold[i] = cvec[i]
            i += 1usize
        }
        it += 1usize
    }
    i = 0usize
    while i < nw {
        coef[i] = cvec[i]
        i += 1usize
    }
    stats[0usize] = f
    stats[1usize] = nrm
    stats[2usize] = f64(iternum)
    ret ok
}

// lnsrch_morph: the backtracking line search along pvec from bold; bnew receives the accepted point
fn morph_linesearch(a: *mem.Arena, norder: usize, wbreaks: []const f64, xs: []const f64, ys: []const f64, wt: []const f64, ylo: f64, yhi: f64, kmat: []const f64, haspen: bool, zm: []const f64, bold: []const f64, fold: f64, g: []const f64, pin: []const f64, bnew: []f64) -> err {
    let nw = wbreaks.len + norder - 2usize
    let nz = nw - 1usize
    let (p, e1) = mem.alloc[f64](a, nz)
    let (gtmp, e2) = mem.alloc[f64](a, nz)
    let (hs, e3) = mem.alloc[f64](a, nz * nz)
    let (rs, e4) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var psum = 0.0f64
    var i = 0usize
    while i < nz {
        psum += pin[i] * pin[i]
        i += 1usize
    }
    psum = math.sqrt[f64](psum)
    i = 0usize
    while i < nz {
        p[i] = pin[i]
        if psum > 10.0f64 { p[i] = p[i] * (10.0f64 / psum) }
        i += 1usize
    }
    var slope = 0.0f64
    i = 0usize
    while i < nz {
        slope += g[i] * p[i]
        i += 1usize
    }
    if slope >= 0.0f64 { ret mem.Full }
    var test = 0.0f64
    i = 0usize
    while i < nz {
        var den = math.abs[f64](bold[i])
        if den < 1.0f64 { den = 1.0f64 }
        let temp = math.abs[f64](p[i]) / den
        if temp > test { test = temp }
        i += 1usize
    }
    let alamin = 1.0e-10f64 / test
    var alam = 1.0f64
    var alam2 = 0.0f64
    var f2 = 0.0f64
    var iter = 0usize
    while iter <= 20usize {
        iter += 1usize
        i = 0usize
        while i < nz {
            bnew[i] = bold[i] + alam * p[i]
            i += 1usize
        }
        let st = mem.mark(a)
        let e = morph_fngrad(a, norder, wbreaks, xs, ys, wt, ylo, yhi, kmat, haspen, zm, bnew, rs, gtmp, hs)
        mem.reset(a, st)
        if e != ok { ret e }
        let f = rs[0usize]
        if alam < alamin {
            i = 0usize
            while i < nz {
                bnew[i] = bold[i]
                i += 1usize
            }
            ret ok
        }
        if f <= fold + 1.0e-4f64 * alam * slope { ret ok }
        var tmplam = 0.0f64
        if alam == 1.0f64 {
            tmplam = (0.0f64 - slope) / (2.0f64 * (f - fold - slope))
        } else {
            let rhs1 = f - fold - alam * slope
            let rhs2 = f2 - fold - alam2 * slope
            let ca = (rhs1 / (alam * alam) - rhs2 / (alam2 * alam2)) / (alam - alam2)
            let cb = ((0.0f64 - alam2) * rhs1 / (alam * alam) + alam * rhs2 / (alam * alam2)) / (alam - alam2)
            if ca == 0.0f64 {
                tmplam = (0.0f64 - slope) / (2.0f64 * cb)
            } else {
                let disc = cb * cb - 3.0f64 * ca * slope
                if disc < 0.0f64 {
                    tmplam = 0.5f64 * alam
                } else {
                    if cb <= 0.0f64 {
                        tmplam = ((0.0f64 - cb) + math.sqrt[f64](disc)) / (3.0f64 * ca)
                    } else {
                        tmplam = (0.0f64 - slope) / (cb + math.sqrt[f64](disc))
                    }
                }
                if tmplam > 0.5f64 * alam { tmplam = 0.5f64 * alam }
            }
        }
        alam2 = alam
        f2 = f
        alam = tmplam
        if alam < 0.1f64 * alam2 { alam = 0.1f64 * alam2 }
    }
    ret ok
}
