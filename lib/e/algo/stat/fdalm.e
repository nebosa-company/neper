// R fda, landmark registration: landmarkreg on a default order-4 basis, built on the smooth.morph of fdareg.
//
// Not here: user-supplied W bases, a target interval other than the range of the curves, register.fd.

use e.algo.stat.fdapkg as fa
use e.algo.stat.fdareg as fr
use e.mem

// smooth.basis(argvals, y, fdPar(basis, m, lambda)) with unit weights for ncol columns of y (argvals.len by ncol, column-major); out is nbasis by ncol
fn smooth_basis_multi(a: *mem.Arena, norder: usize, breaks: []const f64, argvals: []const f64, ymat: []const f64, ncol: usize, m: usize, lambda: f64, out: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let n = argvals.len
    let (lhs, e1) = mem.alloc[f64](a, nb * nb)
    let (rhs, e2) = mem.alloc[f64](a, nb * ncol)
    let (v, e3) = mem.alloc[f64](a, nb + norder)
    let (pm, e4) = mem.alloc[f64](a, nb * nb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var e = fa.penalty_matrix(a, norder, breaks, m, pm)
    if e != ok { ret e }
    var q = 0usize
    while q < nb * nb {
        lhs[q] = lambda * pm[q]
        q += 1usize
    }
    q = 0usize
    while q < nb * ncol {
        rhs[q] = 0.0f64
        q += 1usize
    }
    var t = 0usize
    while t < n {
        let st = mem.mark(a)
        e = fa.eval_bspline(a, norder, breaks, argvals[t], 0usize, v)
        mem.reset(a, st)
        if e != ok { ret e }
        var i = 0usize
        while i < nb {
            var j = 0usize
            while j < nb {
                lhs[j * nb + i] += v[i] * v[j]
                j += 1usize
            }
            var c = 0usize
            while c < ncol {
                rhs[c * nb + i] += v[i] * ymat[c * n + t]
                c += 1usize
            }
            i += 1usize
        }
        t += 1usize
    }
    ret fr.spd_solve(a, lhs, nb, rhs, ncol, out)
}

// x -> a + b x with the monotone curve h rescaled onto (lo, hi) and its end values set exactly, as landmarkreg does
fn rescale_to_range(h: []f64, lo: f64, hi: f64) {
    let n = h.len
    let b = (hi - lo) / (h[n - 1usize] - h[0usize])
    let a0 = lo - b * h[0usize]
    var i = 0usize
    while i < n {
        h[i] = a0 + b * h[i]
        i += 1usize
    }
    h[0usize] = lo
    h[n - 1usize] = hi
}

// landmarkreg(fd(coefs, basis), ximarks, x0marks, c(lo, hi), ylambda) for the default order-4 basis of nbasis functions on (lo, hi) and the default W bases of nl + 2 functions. ximarks is ncurve by nl stored by curve (curve i at i * nl).
// regc, warpc and invc receive the nbasis by ncurve coefficients of regfd, warpfd and warpinvfd; wc the (nl + 2) by ncurve coefficients of Wfd
fn landmark_reg(a: *mem.Arena, lo: f64, hi: f64, nbasis: usize, ncurve: usize, nl: usize, ylambda: f64, x0marks: []const f64, ximarks: []const f64, coefs: []const f64, regc: []f64, warpc: []f64, invc: []f64, wc: []f64) -> err {
    let nw = nl + 2usize
    var nfine = 10usize * nbasis
    if nfine > 101usize { nfine = 101usize }
    let (yb, e1) = mem.alloc[f64](a, nbasis - 2usize)
    let (wb, e2) = mem.alloc[f64](a, nw - 2usize)
    let (xf, e3) = mem.alloc[f64](a, nfine)
    let (yfine, e4) = mem.alloc[f64](a, nfine * ncurve)
    let (yreg, e5) = mem.alloc[f64](a, nfine * ncurve)
    let (hmat, e6) = mem.alloc[f64](a, nfine * ncurve)
    let (imat, e7) = mem.alloc[f64](a, nfine * ncurve)
    let (xv, e8) = mem.alloc[f64](a, nw)
    let (yv, e9) = mem.alloc[f64](a, nw)
    let (c0, e10) = mem.alloc[f64](a, nw)
    let (hf, e11) = mem.alloc[f64](a, nfine)
    let (hv, e12) = mem.alloc[f64](a, nfine)
    let (stats, e13) = mem.alloc[f64](a, 3usize)
    let (cf1, e14) = mem.alloc[f64](a, nbasis)
    let (winv, e15) = mem.alloc[f64](a, nw)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok { ret mem.Full }
    var i = 0usize
    while i < nbasis - 2usize {
        yb[i] = fr.seq_at(lo, hi, nbasis - 2usize, i)
        i += 1usize
    }
    i = 0usize
    while i < nw - 2usize {
        wb[i] = fr.seq_at(lo, hi, nw - 2usize, i)
        i += 1usize
    }
    i = 0usize
    while i < nfine {
        xf[i] = fr.seq_at(lo, hi, nfine, i)
        i += 1usize
    }
    var ic = 0usize
    while ic < ncurve {
        i = 0usize
        while i < nfine {
            let st = mem.mark(a)
            yfine[ic * nfine + i] = fa.eval_fd_bspline(a, 4usize, yb, coefs[ic * nbasis..ic * nbasis + nbasis], xf[i], 0usize)
            mem.reset(a, st)
            i += 1usize
        }
        ic += 1usize
    }
    ic = 0usize
    while ic < ncurve {
        let st = mem.mark(a)
        xv[0usize] = lo
        yv[0usize] = lo
        i = 0usize
        while i < nl {
            xv[i + 1usize] = x0marks[i]
            yv[i + 1usize] = ximarks[ic * nl + i]
            i += 1usize
        }
        xv[nl + 1usize] = hi
        yv[nl + 1usize] = hi
        i = 0usize
        while i < nw {
            c0[i] = 0.0f64
            i += 1usize
        }
        var e = fr.smooth_morph(a, 4usize, wb, 2usize, 1.0e-10f64, c0, xv, yv, lo, hi, 1.0e-4f64, 20usize, wc[ic * nw..ic * nw + nw], stats)
        if e != ok { ret e }
        e = fr.mon_eval(a, 4usize, wb, wc[ic * nw..ic * nw + nw], xf, false, hf)
        if e != ok { ret e }
        rescale_to_range(hf, lo, hi)
        i = 0usize
        while i < nfine {
            hmat[ic * nfine + i] = hf[i]
            i += 1usize
        }
        e = fr.smooth_morph(a, 4usize, wb, 2usize, 1.0e-10f64, c0, hf, xf, lo, hi, 1.0e-4f64, 20usize, winv, stats)
        if e != ok { ret e }
        e = fr.mon_eval(a, 4usize, wb, winv, xf, false, hv)
        if e != ok { ret e }
        rescale_to_range(hv, lo, hi)
        i = 0usize
        while i < nfine {
            imat[ic * nfine + i] = hv[i]
            i += 1usize
        }
        e = smooth_basis_multi(a, 4usize, yb, hv, yfine[ic * nfine..ic * nfine + nfine], 1usize, 2usize, 0.0f64, cf1)
        if e != ok { ret e }
        i = 0usize
        while i < nfine {
            yreg[ic * nfine + i] = fa.eval_fd_bspline(a, 4usize, yb, cf1, xf[i], 0usize)
            i += 1usize
        }
        mem.reset(a, st)
        ic += 1usize
    }
    var e = smooth_basis_multi(a, 4usize, yb, xf, yreg, ncurve, 2usize, ylambda, regc)
    if e != ok { ret e }
    e = smooth_basis_multi(a, 4usize, yb, xf, hmat, ncurve, 2usize, 0.0f64, warpc)
    if e != ok { ret e }
    ret smooth_basis_multi(a, 4usize, yb, xf, imat, ncurve, 2usize, 0.0f64, invc)
}
