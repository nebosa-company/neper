// R fda, the bases other than the B-spline basis and the Fourier basis (those are in fdapkg): monomial, exponential and polygonal bases of eval.basis, the Fourier roughness penalty and smooth.basis on a Fourier basis,
// a smoothed pca.fd (harmonic basis penalised by lambda R) and fRegress with a scalar response and several covariates.

use e.algo.linalg.decomp as dc
use e.algo.stat.bayesmpkg as bz
use e.algo.stat.fdapkg as fa
use e.algo.stat.fdareg as fr
use e.math
use e.mem

// getbasispenalty of a Fourier basis of period equal to its range, Lfdobj = m-th derivative: the diagonal (j w)^(2 m) over the pairs, the constant 1 for m = 0 and 0 past it
fn fourier_penalty_diag(nbasis: usize, period: f64, m: usize, out: []f64) {
    let w = 6.283185307179586f64 / period
    var i = 0usize
    while i < nbasis {
        if i == 0usize {
            out[0usize] = 0.0f64
            if m == 0usize { out[0usize] = 1.0f64 }
        } else {
            let jw = f64((i + 1usize) / 2usize) * w
            var p = 1.0f64
            var k = 0usize
            while k < 2usize * m {
                p = p * jw
                k += 1usize
            }
            out[i] = p
        }
        i += 1usize
    }
}

// solves (A) x = b for symmetric positive definite A (n by n, column-major) through the Cholesky factor
fn spd_solve(a: *mem.Arena, am: []const f64, n: usize, b: []const f64, x: []f64) -> err {
    let (u, e1) = mem.alloc[f64](a, n * n)
    let (iu, e2) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok { ret mem.Full }
    if !bz.chol_upper(am, n, u) { ret mem.Full }
    bz.inv_upper(u, n, iu)
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
            s += inv * b[j]
            j += 1usize
        }
        x[i] = s
        i += 1usize
    }
    ret ok
}

// smooth.basis(argvals, y, fdPar(fourier basis, m, lambda)): (Phi' Phi + lambda R)^-1 Phi' y, unit weights
fn smooth_fourier(a: *mem.Arena, nbasis: usize, period: f64, argvals: []const f64, y: []const f64, m: usize, lambda: f64, coef: []f64) -> err {
    let nb = nbasis
    let (lhs, e1) = mem.alloc[f64](a, nb * nb)
    let (rhs, e2) = mem.alloc[f64](a, nb)
    let (v, e3) = mem.alloc[f64](a, nb)
    let (dg, e4) = mem.alloc[f64](a, nb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    fourier_penalty_diag(nb, period, m, dg)
    var q = 0usize
    while q < nb * nb {
        lhs[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nb {
        lhs[q * nb + q] = lambda * dg[q]
        rhs[q] = 0.0f64
        q += 1usize
    }
    var t = 0usize
    while t < argvals.len {
        fa.eval_fourier(nb, period, argvals[t], 0usize, v)
        var i = 0usize
        while i < nb {
            var j = 0usize
            while j < nb {
                lhs[j * nb + i] += v[i] * v[j]
                j += 1usize
            }
            rhs[i] += v[i] * y[t]
            i += 1usize
        }
        t += 1usize
    }
    ret spd_solve(a, lhs, nb, rhs, coef)
}

// eval.fd of a Fourier curve: sum c_j D^k phi_j (x)
fn eval_fd_fourier(a: *mem.Arena, nbasis: usize, period: f64, coefs: []const f64, x: f64, nderiv: usize) -> f64 {
    let (v, e) = mem.alloc[f64](a, nbasis)
    if e != ok { ret 0.0f64 / 0.0f64 }
    fa.eval_fourier(nbasis, period, x, nderiv, v)
    var s = 0.0f64
    var j = 0usize
    while j < nbasis {
        s += coefs[j] * v[j]
        j += 1usize
    }
    ret s
}

// pca.fd(fd(coefs, bspline), harmfdPar = fdPar(basis, m, lambda)): the exact Gram matrix plus lambda times the m-th derivative penalty is the matrix whose Cholesky factor M fda uses; values and varprop as in fa.pca_fd_values
fn pca_fd_smooth(a: *mem.Arena, norder: usize, breaks: []const f64, m: usize, lambda: f64, coefs: []const f64, nrep: usize, values: []f64, varprop: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let (gm, e1) = mem.alloc[f64](a, nb * nb)
    let (rm, e2) = mem.alloc[f64](a, nb * nb)
    let (jm, e3) = mem.alloc[f64](a, nb * nb)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var e = fa.penalty_matrix(a, norder, breaks, 0usize, gm)
    if e != ok { ret e }
    e = fa.penalty_matrix(a, norder, breaks, m, rm)
    if e != ok { ret e }
    e = fa.inprod_romberg(a, norder, breaks, jm)
    if e != ok { ret e }
    var q = 0usize
    while q < nb * nb {
        gm[q] = gm[q] + lambda * rm[q]
        q += 1usize
    }
    ret fa.pca_fd_values(a, gm, jm, coefs, nb, nrep, values, varprop)
}

// the Fourier basis' inprod(basis, basis) of fda (Romberg over one period), nbasis by nbasis column-major in out
fn inprod_fourier(a: *mem.Arena, nbasis: usize, period: f64, out: []f64) -> err {
    let (id, e) = mem.alloc[f64](a, nbasis * nbasis)
    let (br, e2) = mem.alloc[f64](a, 2usize)
    if e != ok || e2 != ok { ret mem.Full }
    var q = 0usize
    while q < nbasis * nbasis {
        id[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nbasis {
        id[q * nbasis + q] = 1.0f64
        q += 1usize
    }
    br[0usize] = 0.0f64
    br[1usize] = period
    ret fa.inprod_coefs_k(a, 1usize, period, br, nbasis, br, id, nbasis, id, nbasis, out)
}

// smooth.fd(fd(coefs, fourier basis), fdPar(basis, m, lambda)): (J + lambda R) c = J coefs with J the numerical inprod and R the diagonal m-th derivative penalty; out is nbasis by nrep
fn smooth_fd_fourier(a: *mem.Arena, nbasis: usize, period: f64, coefs: []const f64, nrep: usize, m: usize, lambda: f64, out: []f64) -> err {
    let nb = nbasis
    let (jm, e1) = mem.alloc[f64](a, nb * nb)
    let (dm, e2) = mem.alloc[f64](a, nb * nrep)
    let (dg, e3) = mem.alloc[f64](a, nb)
    let (id, e4) = mem.alloc[f64](a, nb * nb)
    let (br, e5) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var e = inprod_fourier(a, nb, period, jm)
    if e != ok { ret e }
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
    br[0usize] = 0.0f64
    br[1usize] = period
    e = fa.inprod_coefs_k(a, 1usize, period, br, nb, br, id, nb, coefs, nrep, dm)
    if e != ok { ret e }
    fourier_penalty_diag(nb, period, m, dg)
    q = 0usize
    while q < nb {
        jm[q * nb + q] += lambda * dg[q]
        q += 1usize
    }
    q = 0usize
    while q < nb * nrep {
        out[q] = dm[q]
        q += 1usize
    }
    if !fr.lu_solve(jm, nb, out, nrep) { ret mem.Full }
    ret ok
}

// pca.fd of a Fourier-basis fd with harmfdPar = fdPar(basis, m, lambda): the Gram matrix is the identity plus lambda times the diagonal penalty, J the numerical inprod
fn pca_fd_fourier(a: *mem.Arena, nbasis: usize, period: f64, m: usize, lambda: f64, coefs: []const f64, nrep: usize, values: []f64, varprop: []f64) -> err {
    let nb = nbasis
    let (gm, e1) = mem.alloc[f64](a, nb * nb)
    let (jm, e2) = mem.alloc[f64](a, nb * nb)
    let (d0, e3) = mem.alloc[f64](a, nb)
    let (dm, e4) = mem.alloc[f64](a, nb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let e = inprod_fourier(a, nb, period, jm)
    if e != ok { ret e }
    fourier_penalty_diag(nb, period, 0usize, d0)
    fourier_penalty_diag(nb, period, m, dm)
    var q = 0usize
    while q < nb * nb {
        gm[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nb {
        gm[q * nb + q] = d0[q] + lambda * dm[q]
        q += 1usize
    }
    ret fa.pca_fd_values(a, gm, jm, coefs, nb, nrep, values, varprop)
}

// fRegress(y, list(const, z1 .., x1 .., xk), betas): a scalar response, the intercept, nz scalar covariates (constant bases, unpenalised) and nf functional covariates sharing one B-spline basis with the coefficient functions, each
// penalised by lambdas[f] times the second-derivative penalty. xcoefs holds the nf coefficient matrices (nbasis by nobs) one after the other, zs the nz covariates (nobs each); out receives the intercept, the nz scalar
// coefficients, then nbasis coefficients per functional covariate
fn fregress_multi(a: *mem.Arena, norder: usize, breaks: []const f64, nf: usize, nz: usize, xcoefs: []const f64, zs: []const f64, nobs: usize, y: []const f64, lambdas: []const f64, out: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let np = 1usize + nz + nf * nb
    let (jm, e1) = mem.alloc[f64](a, nb * nb)
    let (rm, e2) = mem.alloc[f64](a, nb * nb)
    let (z, e3) = mem.alloc[f64](a, nobs * np)
    let (lhs, e4) = mem.alloc[f64](a, np * np)
    let (rhs, e5) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var e = fa.inprod_romberg(a, norder, breaks, jm)
    if e != ok { ret e }
    e = fa.penalty_matrix(a, norder, breaks, 2usize, rm)
    if e != ok { ret e }
    var i = 0usize
    while i < nobs {
        z[i] = 1.0f64
        var c = 0usize
        while c < nz {
            z[(1usize + c) * nobs + i] = zs[c * nobs + i]
            c += 1usize
        }
        var f = 0usize
        while f < nf {
            var k = 0usize
            while k < nb {
                var s = 0.0f64
                var j = 0usize
                while j < nb {
                    s += xcoefs[f * nb * nobs + i * nb + j] * jm[k * nb + j]
                    j += 1usize
                }
                z[(1usize + nz + f * nb + k) * nobs + i] = s
                k += 1usize
            }
            f += 1usize
        }
        i += 1usize
    }
    var p1 = 0usize
    while p1 < np {
        var p2 = 0usize
        while p2 < np {
            var s = 0.0f64
            i = 0usize
            while i < nobs {
                s += z[p1 * nobs + i] * z[p2 * nobs + i]
                i += 1usize
            }
            if p1 >= 1usize + nz && p2 >= 1usize + nz && (p1 - 1usize - nz) / nb == (p2 - 1usize - nz) / nb {
                s += lambdas[(p1 - 1usize - nz) / nb] * rm[((p2 - 1usize - nz) % nb) * nb + (p1 - 1usize - nz) % nb]
            }
            lhs[p2 * np + p1] = s
            p2 += 1usize
        }
        var sy = 0.0f64
        i = 0usize
        while i < nobs {
            sy += z[p1 * nobs + i] * y[i]
            i += 1usize
        }
        rhs[p1] = sy
        p1 += 1usize
    }
    ret spd_solve(a, lhs, np, rhs, out)
}
