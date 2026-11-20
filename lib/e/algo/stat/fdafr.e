// R fda, fRegress with a functional response (fRegress.fd with y an fd): the normal equations C b = D built from the weight functions sum_i x_ji x_ki and sum_i x_ji y_i, which times.fd forms in the product basis,
// and the integrals inprod(beta_j basis, beta_k basis, wtfd = weight) by fa.inprod_general. Bases are B-spline (kind 0) or constant (kind 5); a constant covariate has the constant basis and one coefficient per curve.

use e.algo.stat.bayesmpkg as bz
use e.algo.stat.fdabase as fb
use e.algo.stat.fdapkg as fa
use e.math
use e.mem

fn spec_copy(from: *const fa.Bspec, to: *fa.Bspec) {
    to.kind = from.kind
    to.period = from.period
    to.par = from.par
    to.norder = from.norder
    to.breaks = from.breaks
}

// the basis of basisobj1 * basisobj2: the other basis when one is constant, otherwise the B-spline basis of order n1 + n2 - 1 (at most 20) on the union of the interior knots
fn prod_spec(a: *mem.Arena, b1: *const fa.Bspec, b2: *const fa.Bspec, out: *fa.Bspec) -> err {
    if b1.kind == 5usize {
        spec_copy(b2, out)
        ret ok
    }
    if b2.kind == 5usize {
        spec_copy(b1, out)
        ret ok
    }
    let k1 = b1.breaks.len - 2usize
    let k2 = b2.breaks.len - 2usize
    let (br, e) = mem.alloc[f64](a, k1 + k2 + 2usize)
    if e != ok { ret e }
    br[0usize] = b1.breaks[0usize]
    var n = 1usize
    var i = 0usize
    var j = 0usize
    while i < k1 || j < k2 {
        var x = 0.0f64
        if i >= k1 {
            x = b2.breaks[1usize + j]
            j += 1usize
        } else {
            if j >= k2 {
                x = b1.breaks[1usize + i]
                i += 1usize
            } else {
                let x1 = b1.breaks[1usize + i]
                let x2 = b2.breaks[1usize + j]
                if x1 < x2 {
                    x = x1
                    i += 1usize
                } else {
                    x = x2
                    j += 1usize
                    if x1 == x2 { i += 1usize }
                }
            }
        }
        br[n] = x
        n += 1usize
    }
    br[n] = b1.breaks[b1.breaks.len - 1usize]
    n += 1usize
    var no = b1.norder + b2.norder - 1usize
    if no > 20usize { no = 20usize }
    out.kind = 0usize
    out.period = 0.0f64
    out.par = b1.par
    out.norder = no
    out.breaks = br[0usize..n]
    ret ok
}

// symsolve(A, B) for the column-major symmetric positive definite A: chol, then solve(t(U), B) and backsolve(U, .) for each column of B
fn symsolve(a: *mem.Arena, am: []const f64, n: usize, b: []const f64, ncol: usize, x: []f64) -> err {
    let (u, e1) = mem.alloc[f64](a, n * n)
    let (z, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    if !bz.chol_upper(am, n, u) { ret mem.Full }
    var c = 0usize
    while c < ncol {
        var i = 0usize
        while i < n {
            var s = b[c * n + i]
            var k = 0usize
            while k < i {
                s -= u[i * n + k] * z[k]
                k += 1usize
            }
            z[i] = s / u[i * n + i]
            i += 1usize
        }
        var ii = n
        while ii > 0usize {
            ii -= 1usize
            var s = z[ii]
            var k = ii + 1usize
            while k < n {
                s -= u[k * n + ii] * x[c * n + k]
                k += 1usize
            }
            x[c * n + ii] = s / u[ii * n + ii]
        }
        c += 1usize
    }
    ret ok
}

// times.fd(fd(c1, b1), fd(c2, b2)) for nrep curves each: the coefficients of the product in prod_spec(b1, b2), by projecting the pointwise product on 10 max(nbasis) + 1 (at least 201) equally spaced points; pc is nbasis(prod) by nrep
fn times_fd(a: *mem.Arena, b1: *const fa.Bspec, c1: []const f64, b2: *const fa.Bspec, c2: []const f64, nrep: usize, pb: *const fa.Bspec, pc: []f64) -> err {
    let nb1 = fa.spec_nbasis(b1)
    let nb2 = fa.spec_nbasis(b2)
    let nbp = fa.spec_nbasis(pb)
    var mx = nb1
    if nb2 > mx { mx = nb2 }
    var neval = 10usize * mx + 1usize
    if neval < 201usize { neval = 201usize }
    let lo = b1.breaks[0usize]
    let hi = b1.breaks[b1.breaks.len - 1usize]
    let by = (hi - lo) / f64(neval - 1usize)
    let (v1, e1) = mem.alloc[f64](a, nb1 + b1.norder + 2usize)
    let (v2, e2) = mem.alloc[f64](a, nb2 + b2.norder + 2usize)
    let (vp, e3) = mem.alloc[f64](a, nbp + pb.norder + 2usize)
    let (f1, e4) = mem.alloc[f64](a, nrep)
    let (f2, e5) = mem.alloc[f64](a, nrep)
    let (cm, e6) = mem.alloc[f64](a, nbp * nbp)
    let (rhs, e7) = mem.alloc[f64](a, nbp * nrep)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var q = 0usize
    while q < nbp * nbp {
        cm[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nbp * nrep {
        rhs[q] = 0.0f64
        q += 1usize
    }
    var i = 0usize
    while i < neval {
        let x = lo + f64(i) * by
        var e = fa.basis_row(a, b1, x, v1)
        if e != ok { ret e }
        e = fa.basis_row(a, b2, x, v2)
        if e != ok { ret e }
        e = fa.basis_row(a, pb, x, vp)
        if e != ok { ret e }
        fa.pair_values(v1, nb1, c1, nrep, f1)
        fa.pair_values(v2, nb2, c2, nrep, f2)
        var j = 0usize
        while j < nbp {
            var k = 0usize
            while k < nbp {
                cm[k * nbp + j] += vp[j] * vp[k]
                k += 1usize
            }
            var r = 0usize
            while r < nrep {
                rhs[r * nbp + j] += vp[j] * (f1[r] * f2[r])
                r += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret symsolve(a, cm, nbp, rhs, nrep, pc)
}

fn identity(a: *mem.Arena, n: usize) -> []f64 {
    let (m, e) = mem.alloc[f64](a, n * n)
    var q = 0usize
    while q < n * n {
        m[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < n {
        m[q * n + q] = 1.0f64
        q += 1usize
    }
    ret m
}

// the weight function of fRegress.fd: sum over the curves of x_j * x_k as coefficients in the product basis wb (nbasis(wb) values)
fn weight_sum(a: *mem.Arena, bj: *const fa.Bspec, cj: []const f64, bk: *const fa.Bspec, ck: []const f64, nrep: usize, wb: *fa.Bspec, wc: []f64) -> err {
    var e = prod_spec(a, bj, bk, wb)
    if e != ok { ret e }
    let nbp = fa.spec_nbasis(wb)
    let (pc, e2) = mem.alloc[f64](a, nbp * nrep)
    if e2 != ok { ret e2 }
    e = times_fd(a, bj, cj, bk, ck, nrep, wb, pc)
    if e != ok { ret e }
    var j = 0usize
    while j < nbp {
        var s = 0.0f64
        var r = 0usize
        while r < nrep {
            s += pc[r * nbp + j]
            r += 1usize
        }
        wc[j] = s
        j += 1usize
    }
    ret ok
}

// fRegress.fd with a functional response: y is the curves yc in basis yb, covariate j the curves xc[j] in xb[j] (the offsets in xoff, one block of nbasis * nrep per covariate), beta j in the basis bb[j] with the penalty lambda[j] on its second derivative
// (B-spline betas); out receives the coefficients of all betas in turn
fn fregress_fd(a: *mem.Arena, nrep: usize, yb: *const fa.Bspec, yc: []const f64, p: usize, xb: []const fa.Bspec, xc: []const f64, bb: []const fa.Bspec, lambda: []const f64, out: []f64) -> err {
    var ncoef = 0usize
    var q = 0usize
    while q < p {
        ncoef += fa.spec_nbasis(&bb[q])
        q += 1usize
    }
    let (cmat, e1) = mem.alloc[f64](a, ncoef * ncoef)
    let (dmat, e2) = mem.alloc[f64](a, ncoef)
    if e1 != ok || e2 != ok { ret mem.Full }
    q = 0usize
    while q < ncoef * ncoef {
        cmat[q] = 0.0f64
        q += 1usize
    }
    let lo = yb.breaks[0usize]
    let hi = yb.breaks[yb.breaks.len - 1usize]
    let (rr, er) = mem.alloc[f64](a, 2usize)
    if er != ok { ret er }
    rr[0usize] = lo
    rr[1usize] = hi
    let onesb = fa.Bspec{ kind: 5usize, period: 0.0f64, par: rr[0usize..0usize], norder: 1usize, breaks: rr }
    let (one, eo) = mem.alloc[f64](a, 1usize)
    if eo != ok { ret eo }
    one[0usize] = 1.0f64
    var wb = fa.Bspec{ kind: 5usize, period: 0.0f64, par: rr[0usize..0usize], norder: 1usize, breaks: rr }
    var mj = 0usize
    var xoffj = 0usize
    var j = 0usize
    while j < p {
        let nbj = fa.spec_nbasis(&bb[j])
        let nxj = fa.spec_nbasis(&xb[j])
        let cj = xc[xoffj..xoffj + nxj * nrep]
        let idj = identity(a, nbj)
        // D_j
        var nbw = fa.spec_nbasis(&xb[j])
        let (wc0, ew0) = mem.alloc[f64](a, 512usize)
        if ew0 != ok { ret ew0 }
        var e = weight_sum(a, &xb[j], cj, yb, yc, nrep, &wb, wc0)
        if e != ok { ret e }
        nbw = fa.spec_nbasis(&wb)
        let (dj, ed) = mem.alloc[f64](a, nbj)
        if ed != ok { ret ed }
        e = fa.inprod_general(a, &bb[j], idj, nbj, &onesb, one, 1usize, &wb, wc0[0usize..nbw], dj)
        if e != ok { ret e }
        var i = 0usize
        while i < nbj {
            dmat[mj + i] = dj[i]
            i += 1usize
        }
        var mk = 0usize
        var xoffk = 0usize
        var k = 0usize
        while k <= j {
            let nbk = fa.spec_nbasis(&bb[k])
            let nxk = fa.spec_nbasis(&xb[k])
            let ck = xc[xoffk..xoffk + nxk * nrep]
            let idk = identity(a, nbk)
            let (wc1, ew1) = mem.alloc[f64](a, 512usize)
            if ew1 != ok { ret ew1 }
            e = weight_sum(a, &xb[j], cj, &xb[k], ck, nrep, &wb, wc1)
            if e != ok { ret e }
            nbw = fa.spec_nbasis(&wb)
            let (blk, eb) = mem.alloc[f64](a, nbj * nbk)
            if eb != ok { ret eb }
            e = fa.inprod_general(a, &bb[j], idj, nbj, &bb[k], idk, nbk, &wb, wc1[0usize..nbw], blk)
            if e != ok { ret e }
            var r = 0usize
            while r < nbj {
                var c = 0usize
                while c < nbk {
                    cmat[(mk + c) * ncoef + mj + r] = blk[c * nbj + r]
                    cmat[(mj + r) * ncoef + mk + c] = blk[c * nbj + r]
                    c += 1usize
                }
                r += 1usize
            }
            xoffk += nxk * nrep
            mk += nbk
            k += 1usize
        }
        if lambda[j] > 0.0f64 {
            let (rm, erm) = mem.alloc[f64](a, nbj * nbj)
            if erm != ok { ret erm }
            e = fa.penalty_matrix(a, bb[j].norder, bb[j].breaks, 2usize, rm)
            if e != ok { ret e }
            var r = 0usize
            while r < nbj {
                var c = 0usize
                while c < nbj {
                    cmat[(mj + c) * ncoef + mj + r] += lambda[j] * rm[c * nbj + r]
                    c += 1usize
                }
                r += 1usize
            }
        }
        xoffj += nxj * nrep
        mj += nbj
        j += 1usize
    }
    var r = 0usize
    while r < ncoef {
        var c = 0usize
        while c < r {
            let s = (cmat[c * ncoef + r] + cmat[r * ncoef + c]) / 2.0f64
            cmat[c * ncoef + r] = s
            cmat[r * ncoef + c] = s
            c += 1usize
        }
        r += 1usize
    }
    ret fb.spd_solve(a, cmat, ncoef, dmat, out)
}
