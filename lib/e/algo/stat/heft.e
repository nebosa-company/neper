// R polspline heft: hazard estimation with flexible tails (the package's heftall.c). The log hazard is a combination of
// log(x / (x + shift)), log(x + shift), a linear term and a natural cubic spline in the truncated power basis; knots are
// added at the best Rao statistic (interval halving between the uncensored observations) up to a maximum, then removed
// one at a time at the smallest Wald statistic, and the AIC picks the model. Fitted by Newton-Raphson with the
// integrals done by Lagrange interpolation of log(x) against the data. LINPACK dsifa/dsisl/dsidi come from
// e.algo.stat.lspec; dgefa and dgesl are ported here.
//
// Not here: random generation (rheft), plotting; the evaluators needed for the oracle are hheft (hazard) and the
// fit itself. pheft, qheft and heftpq are not ported.

use e.math
use e.mem
use e.algo.stat.lspec as lsp

const HL: i64 = 40i64
const HS: usize = 44usize
const LDA: usize = 40usize

error Failed

type M = struct {
    nk: i64, nk1: i64, aic: f64, ll: f64, tse0: f64, tse1: f64,
    iknots: []i64, icoef: []i64, ad: []i64,
    knots: []f64, yknots: []f64, theta: []f64, coef2: []f64, coef3: []f64, score: []f64, hessian: []f64, logl: []f64, tails: []f64,
    basvec: []f64, basmat: []f64, mult: []f64
}

type D = struct { nd: i64, delta: []i64, data: []f64, cc: f64, bd1: []f64, bd2: []f64 }

type W = struct {
    where: i64,
    ddd: []f64, mat1: []f64, vec1: []f64, vec2: []f64, phi: []f64, mat: []f64, phi2: []f64, masterpt: []f64, xx: []f64,
    cand: []f64, se3: []f64, phi3: []f64, phi7: []f64, phi4: []f64, hh: []f64, powdat: []f64, powvec: []f64,
    info2: []f64, score2: []f64, score3: []f64, newbas: []f64, newdata: []f64, mat33: []f64, vec3: []f64,
    la: []f64, lb: []f64, lkp: []i64, ldet: []f64, lwk: []f64, lsorted: []f64
}

fn u(i: i64) -> usize { ret usize(i) }
fn mi(i: i64, j: i64) -> usize { ret u(i) * HS + u(j) }
fn c3i(i: i64, k: i64, j: i64) -> usize { ret (u(i) * 5usize + u(k)) * HS + u(j) }
fn fabs(x: f64) -> f64 { ret math.abs[f64](x) }

fn hmylog(x: f64) -> f64 {
    if x < 10.0e-250f64 { ret 0.0f64 - 575.64627f64 }
    ret math.log[f64](x)
}

fn zf(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

fn zi(a: *mem.Arena, n: usize, init: i64) -> ([]i64, err) {
    let (v, e) = mem.alloc[i64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = init
        i += 1usize
    }
    ret (v, ok)
}

fn makemodel(a: *mem.Arena) -> (M, err) {
    var m: M = zero
    m.aic = math.pow[f64](10.0f64, 100.0f64)
    let n = HS
    let (ik, e1) = zi(a, n, 1)
    let (ic, e2) = zi(a, n * n, 0)
    let (ad, e3) = zi(a, n, 2)
    let (kn, e4) = zf(a, n)
    let (yk, e5) = zf(a, n)
    let (th, e6) = zf(a, n)
    let (c2, e7) = zf(a, n * n)
    let (c3, e8) = zf(a, n * 5usize * n)
    let (sc, e9) = zf(a, n)
    let (he, e10) = zf(a, n * n)
    let (lg, e11) = zf(a, n)
    let (ta, e12) = zf(a, 8usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (m, mem.Full) }
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (m, mem.Full) }
    m.iknots = ik
    m.icoef = ic
    m.ad = ad
    m.knots = kn
    m.yknots = yk
    m.theta = th
    m.coef2 = c2
    m.coef3 = c3
    m.score = sc
    m.hessian = he
    m.logl = lg
    m.tails = ta
    ret (m, ok)
}

// allocation that records failure in *bad instead of returning it
fn za(a: *mem.Arena, n: usize, bad: *bool) -> []f64 {
    let (v, e) = zf(a, n)
    if e != ok { *bad = true }
    ret v
}

fn makew(a: *mem.Arena, nd: usize, i00: usize) -> (W, err) {
    var w: W = zero
    var bad = false
    let n = HS
    w.ddd = za(a, nd + 4usize, &bad)
    w.mat1 = za(a, n * n, &bad)
    w.vec1 = za(a, n, &bad)
    w.vec2 = za(a, nd + 4usize, &bad)
    w.phi = za(a, n, &bad)
    w.mat = za(a, n * n, &bad)
    w.phi2 = za(a, n, &bad)
    w.masterpt = za(a, n + 100usize, &bad)
    w.xx = za(a, n + 100usize, &bad)
    w.cand = za(a, n, &bad)
    w.se3 = za(a, n, &bad)
    w.phi3 = za(a, n, &bad)
    w.phi7 = za(a, n, &bad)
    w.phi4 = za(a, n, &bad)
    w.hh = za(a, n * n, &bad)
    w.powdat = za(a, (nd + 2usize) * 3usize, &bad)
    w.powvec = za(a, (i00 + 2usize) * 3usize, &bad)
    w.info2 = za(a, n * n, &bad)
    w.score2 = za(a, n, &bad)
    w.score3 = za(a, n, &bad)
    w.newbas = za(a, i00 + 2usize, &bad)
    w.newdata = za(a, nd + 2usize, &bad)
    w.mat33 = za(a, 16usize, &bad)
    w.vec3 = za(a, 8usize, &bad)
    w.la = za(a, LDA * LDA, &bad)
    w.lb = za(a, LDA, &bad)
    w.ldet = za(a, 4usize, &bad)
    w.lwk = za(a, LDA, &bad)
    w.lsorted = za(a, nd + 4usize, &bad)
    let (lk, e26) = zi(a, LDA + 1usize, 0)
    if e26 != ok { bad = true }
    w.lkp = lk
    if bad { ret (w, mem.Full) }
    ret (w, ok)
}

// --- LINPACK dgefa / dgesl on a column-major array (A(r, c) = a[(c - 1) LDA + (r - 1)])

fn lx(r: usize, c: usize) -> usize { ret (c - 1usize) * LDA + (r - 1usize) }

// returns info (0 when no zero pivot)
fn dgefa(a: []f64, n: usize, ipvt: []i64) -> usize {
    var info = 0usize
    if n >= 2usize {
        var k = 1usize
        while k <= n - 1usize {
            // idamax over A(k..n, k)
            var l = k
            var dmax = fabs(a[lx(k, k)])
            var i = k + 1usize
            while i <= n {
                let v = fabs(a[lx(i, k)])
                if v > dmax {
                    dmax = v
                    l = i
                }
                i += 1usize
            }
            ipvt[k] = i64(l)
            if a[lx(l, k)] == 0.0f64 {
                info = k
            } else {
                if l != k {
                    let t = a[lx(l, k)]
                    a[lx(l, k)] = a[lx(k, k)]
                    a[lx(k, k)] = t
                }
                let t1 = 0.0f64 - 1.0f64 / a[lx(k, k)]
                i = k + 1usize
                while i <= n {
                    a[lx(i, k)] = t1 * a[lx(i, k)]
                    i += 1usize
                }
                var j = k + 1usize
                while j <= n {
                    let t = a[lx(l, j)]
                    if l != k {
                        a[lx(l, j)] = a[lx(k, j)]
                        a[lx(k, j)] = t
                    }
                    if t != 0.0f64 {
                        i = k + 1usize
                        while i <= n {
                            a[lx(i, j)] = a[lx(i, j)] + t * a[lx(i, k)]
                            i += 1usize
                        }
                    }
                    j += 1usize
                }
            }
            k += 1usize
        }
    }
    ipvt[n] = i64(n)
    if a[lx(n, n)] == 0.0f64 { info = n }
    ret info
}

// solves A x = b (job 0) with the factors from dgefa; b is 1-based b[1..n]
fn dgesl(a: []f64, n: usize, ipvt: []i64, b: []f64) {
    if n >= 2usize {
        var k = 1usize
        while k <= n - 1usize {
            let l = usize(ipvt[k])
            let t = b[l]
            if l != k {
                b[l] = b[k]
                b[k] = t
            }
            if t != 0.0f64 {
                var i = k + 1usize
                while i <= n {
                    b[i] = b[i] + t * a[lx(i, k)]
                    i += 1usize
                }
            }
            k += 1usize
        }
    }
    var kb = 1usize
    while kb <= n {
        let k = n + 1usize - kb
        b[k] = b[k] / a[lx(k, k)]
        let t = 0.0f64 - b[k]
        if t != 0.0f64 {
            var i = 1usize
            while i <= k - 1usize {
                b[i] = b[i] + t * a[lx(i, k)]
                i += 1usize
            }
        }
        kb += 1usize
    }
}

// Fortran A(r, c) = a[r - 1][c - 1]: copy the C matrix a (stride HS) into la
fn tola(w: *W, a: []f64, n: usize) {
    var r = 0usize
    while r < n {
        var c = 0usize
        while c < n {
            w.la[c * LDA + r] = a[r * HS + c]
            c += 1usize
        }
        r += 1usize
    }
}

// symmetric solve: returns -1 when the factorization found a zero pivot
fn hlusolve(w: *W, a: []f64, n: usize, b: []f64) -> i64 {
    tola(w, a, n)
    var i = 0usize
    while i < n {
        w.lb[i] = b[i]
        i += 1usize
    }
    let info = lsp.dsifa(w.la, LDA, n, w.lkp)
    var k = 0i64
    if info != 0usize { k = 0i64 - 1i64 }
    lsp.dsisl(w.la, LDA, n, w.lkp, w.lb)
    i = 0usize
    while i < n {
        b[i] = w.lb[i]
        i += 1usize
    }
    ret k
}

// general solve (LU with partial pivoting)
fn hlusolve2(w: *W, a: []f64, n: usize, b: []f64) -> i64 {
    tola(w, a, n)
    var i = 0usize
    while i < n {
        w.lb[i + 1usize] = b[i]
        i += 1usize
    }
    let info = dgefa(w.la, n, w.lkp)
    var k = 0i64
    if info != 0usize { k = 0i64 - 1i64 }
    dgesl(w.la, n, w.lkp, w.lb)
    i = 0usize
    while i < n {
        b[i] = w.lb[i + 1usize]
        i += 1usize
    }
    ret k
}

// inverse of the symmetric matrix a (stride HS), in place
fn hluinverse(w: *W, a: []f64, n: usize) {
    tola(w, a, n)
    let info = lsp.dsifa(w.la, LDA, n, w.lkp)
    lsp.dsidi_inv(w.la, LDA, n, w.lkp, w.lwk)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < i {
            a[i * HS + j] = w.la[i * LDA + j]
            j += 1usize
        }
        j = i
        while j < n {
            a[i * HS + j] = w.la[j * LDA + i]
            j += 1usize
        }
        i += 1usize
    }
}

fn dubmodel(m2: *M, m1: *M) {
    m2.tse0 = m1.tse0
    m2.tse1 = m1.tse1
    m2.ll = m1.ll
    m2.nk = m1.nk
    m2.nk1 = m1.nk1
    m2.aic = m1.aic
    var i1 = 0usize
    while i1 < usize(HL) {
        m2.iknots[i1] = m1.iknots[i1]
        m2.logl[i1] = m1.logl[i1]
        m2.knots[i1] = m1.knots[i1]
        m2.yknots[i1] = m1.yknots[i1]
        m2.theta[i1] = m1.theta[i1]
        var i2 = 0usize
        while i2 < usize(HL) {
            m2.icoef[i1 * HS + i2] = m1.icoef[i1 * HS + i2]
            m2.coef2[i1 * HS + i2] = m1.coef2[i1 * HS + i2]
            i2 += 1usize
        }
        i1 += 1usize
    }
    i1 = 0usize
    while i1 < 5usize {
        m2.tails[i1] = m1.tails[i1]
        i1 += 1usize
    }
}

// --- the basis

fn p3(x: f64) -> f64 { ret math.pow[f64](x, 3.0f64) }
fn p2(x: f64) -> f64 { ret math.pow[f64](x, 2.0f64) }

fn getcoef(m: *M) {
    let nk = m.nk
    let knots = m.knots
    let coef2 = m.coef2
    let coef3 = m.coef3
    let icoef = m.icoef
    var i = 0i64
    while i < nk - 1i64 {
        var j = 0i64
        while j < nk + 2i64 {
            coef2[mi(i, j)] = 0.0f64
            icoef[mi(i, j)] = 0
            var k = 0i64
            while k < 4i64 {
                coef3[c3i(i, k, j)] = 0.0f64
                k += 1i64
            }
            j += 1i64
        }
        i += 1i64
    }
    if nk > 2i64 {
        coef2[mi(0i64, 2i64)] = 1.0f64
        coef2[mi(0i64, 3i64)] = (knots[0usize] - knots[2usize]) / (knots[2usize] - knots[1usize])
        coef2[mi(0i64, 4i64)] = (knots[1usize] - knots[0usize]) / (knots[2usize] - knots[1usize])
        coef2[mi(0i64, 1i64)] = 0.0f64 - 3.0f64 * (p2(knots[0usize]) + coef2[mi(0i64, 3i64)] * p2(knots[1usize]) + coef2[mi(0i64, 4i64)] * p2(knots[2usize]))
        coef2[mi(0i64, 0i64)] = 0.0f64 - knots[u(nk - 1i64)] * coef2[mi(0i64, 1i64)] - coef2[mi(0i64, 2i64)] * p3(knots[u(nk - 1i64)] - knots[0usize]) - coef2[mi(0i64, 3i64)] * p3(knots[u(nk - 1i64)] - knots[1usize]) - coef2[mi(0i64, 4i64)] * p3(knots[u(nk - 1i64)] - knots[2usize])
        coef2[mi(0i64, 5i64)] = 0.0f64
    }
    coef2[mi(nk - 2i64, 0i64)] = 1.0f64
    if nk > 3i64 {
        i = 1i64
        while i < nk - 2i64 {
            coef2[mi(i, i + 1i64)] = 1.0f64
            coef2[mi(i, i + 4i64)] = (knots[u(i + 1i64)] - knots[u(i - 1i64)]) * (knots[u(i - 1i64)] - knots[u(i)]) / ((knots[u(i + 1i64)] - knots[u(i + 2i64)]) * (knots[u(i)] - knots[u(i + 2i64)]))
            coef2[mi(i, i + 3i64)] = (coef2[mi(i, i + 4i64)] * (knots[u(i)] - knots[u(i + 2i64)]) + knots[u(i)] - knots[u(i - 1i64)]) / (knots[u(i + 1i64)] - knots[u(i)])
            coef2[mi(i, i + 2i64)] = 0.0f64 - 1.0f64 - coef2[mi(i, i + 3i64)] - coef2[mi(i, i + 4i64)]
            i += 1i64
        }
    }
    if nk > 4i64 {
        i = 1i64
        while i < nk - 3i64 {
            var z0 = 0.0f64
            var z1 = 0.0f64
            var j = 2i64
            while j < nk + 1i64 {
                z0 = z0 + coef2[mi(i, j)] * p3(knots[u(nk - 1i64)] - knots[u(j - 2i64)])
                z1 = z1 + coef2[mi(i + 1i64, j)] * p3(knots[u(nk - 1i64)] - knots[u(j - 2i64)])
                j += 1i64
            }
            j = 2i64
            while j < nk + 2i64 {
                coef2[mi(i, j)] = coef2[mi(i, j)] + (0.0f64 - z0 / z1) * coef2[mi(i + 1i64, j)]
                j += 1i64
            }
            i += 1i64
        }
    }
    if nk > 2i64 {
        var k = 0i64
        while k < 3i64 {
            coef3[c3i(0i64, 1i64, k)] = coef2[mi(0i64, 1i64)]
            coef3[c3i(0i64, 0i64, k)] = coef2[mi(0i64, 0i64)]
            icoef[mi(0i64, k)] = 1
            k += 1i64
        }
        i = 0i64
        while i < nk - 2i64 {
            var j = i
            while j < i + 4i64 {
                k = i + 1i64
                while k < j + 2i64 {
                    if j > 0i64 && j < nk + 1i64 && (i != 0i64 || j != 3i64) {
                        if k != 1i64 {
                            coef3[c3i(i, 0i64, j)] = coef3[c3i(i, 0i64, j)] + (0.0f64 - coef2[mi(i, k)]) * p3(knots[u(k - 2i64)])
                            coef3[c3i(i, 1i64, j)] = coef3[c3i(i, 1i64, j)] + 3.0f64 * coef2[mi(i, k)] * p2(knots[u(k - 2i64)])
                            coef3[c3i(i, 2i64, j)] = coef3[c3i(i, 2i64, j)] + (0.0f64 - 3.0f64) * coef2[mi(i, k)] * knots[u(k - 2i64)]
                            coef3[c3i(i, 3i64, j)] = coef3[c3i(i, 3i64, j)] + coef2[mi(i, k)]
                            icoef[mi(i, j)] = 1
                        }
                    }
                    k += 1i64
                }
                j += 1i64
            }
            i += 1i64
        }
    }
    var j = 0i64
    while j < nk + 1i64 {
        coef3[c3i(nk - 2i64, 0i64, j)] = 1.0f64
        icoef[mi(nk - 2i64, j)] = 1
        j += 1i64
    }
}

// basis functions of the model at the points x[0..nx): row i of basmat (stride HS)
fn basis(x: []f64, nx: i64, m: *M, cc: f64, basmat: []f64) {
    let nk = m.nk
    let knots = m.knots
    var wh = 0i64
    var i = 0i64
    while i < nx {
        var j = 1i64
        while j < nk {
            basmat[mi(i, j)] = 0.0f64
            j += 1i64
        }
        i += 1i64
    }
    i = 0i64
    while i < nx {
        let xi = x[u(i)]
        if xi > 0.0f64 { basmat[mi(i, 0i64)] = hmylog(xi / (xi + cc)) }
        basmat[mi(i, nk)] = hmylog(xi + cc)
        if xi > knots[u(wh)] && wh < nk {
            var again = true
            while again {
                wh += 1i64
                again = xi > knots[u(wh)] && wh < nk
            }
        }
        basmat[mi(i, nk + 1i64)] = 0.0f64
        basmat[mi(i, nk + 2i64)] = 0.0f64
        var j = 1i64
        while j < nk - 1i64 {
            if basmat[mi(i, nk + 1i64)] < 0.5f64 && m.icoef[mi(j - 1i64, wh)] != 0 {
                basmat[mi(i, nk + 1i64)] = f64(j)
                j = nk + 10i64
            }
            j += 1i64
        }
        j = nk - 2i64
        while j > 0i64 {
            if basmat[mi(i, nk + 2i64)] < 0.5f64 && m.icoef[mi(j - 1i64, wh)] != 0 {
                basmat[mi(i, nk + 2i64)] = f64(j)
                j = 0i64
            }
            j = j - 1i64
        }
        j = 1i64
        while j < nk {
            if m.icoef[mi(j - 1i64, wh)] != 0 {
                basmat[mi(i, j)] = ((m.coef3[c3i(j - 1i64, 3i64, wh)] * xi + m.coef3[c3i(j - 1i64, 2i64, wh)]) * xi + m.coef3[c3i(j - 1i64, 1i64, wh)]) * xi + m.coef3[c3i(j - 1i64, 0i64, wh)]
            }
            j += 1i64
        }
        i += 1i64
    }
}

// --- starting values

fn hstart2(w: *W, m: *M, d: *D) {
    let nk = m.nk
    let theta = m.theta
    let nx = d.nd
    let tails = m.tails
    let mat1 = w.mat1
    let vec1 = w.vec1
    let vec2 = w.vec2
    if tails[0usize] > 0.0f64 { theta[0usize] = tails[1usize] }
    if tails[2usize] > 0.0f64 { theta[u(nk)] = tails[3usize] }
    var i = 0i64
    while i < nx {
        vec2[u(i)] = 0.0f64
        var j = 1i64
        while j <= nk {
            vec2[u(i)] = vec2[u(i)] + theta[u(j)] * d.bd2[mi(i, j)]
            j += 1i64
        }
        i += 1i64
    }
    i = 1i64
    while i < nk {
        var j = i
        while j < nk {
            mat1[mi(i - 1i64, j - 1i64)] = 0.0f64
            var k = 0i64
            while k < nx {
                mat1[mi(i - 1i64, j - 1i64)] = mat1[mi(i - 1i64, j - 1i64)] + d.bd1[mi(k, i)] * d.bd1[mi(k, j)]
                k += 1i64
            }
            j += 1i64
        }
        i += 1i64
    }
    i = 2i64
    while i < nk {
        var j = 1i64
        while j < i {
            mat1[mi(i - 1i64, j - 1i64)] = mat1[mi(j - 1i64, i - 1i64)]
            j += 1i64
        }
        i += 1i64
    }
    i = 1i64
    while i < nk {
        vec1[u(i - 1i64)] = 0.0f64
        var k = 0i64
        while k < nx {
            vec1[u(i - 1i64)] = vec1[u(i - 1i64)] + d.bd1[mi(k, i)] * vec2[u(k)]
            k += 1i64
        }
        i += 1i64
    }
    if tails[4usize] > 0.5f64 {
        i = 1i64
        while i < nk {
            mat1[mi(0i64, i)] = 0.0f64
            mat1[mi(i, 0i64)] = 0.0f64
            i += 1i64
        }
        mat1[mi(0i64, 0i64)] = 1.0f64
        vec1[0usize] = 0.0f64
    }
    let rc = hlusolve2(w, mat1, u(nk - 1i64), vec1)
    i = 1i64
    while i < nk {
        theta[u(i)] = vec1[u(i - 1i64)]
        i += 1i64
    }
    theta[u(nk)] = theta[u(nk + 1i64)]
}

fn nstart(w: *W, m: *M, d: *D, nkstart: i64) {
    let nk = m.nk
    if nkstart == nk {
        var i = 0i64
        while i <= nk {
            m.theta[u(i)] = 0.0f64
            i += 1i64
        }
        if m.tails[0usize] > 0.0f64 { m.theta[0usize] = m.tails[1usize] }
        if m.tails[2usize] > 0.0f64 { m.theta[u(nk)] = m.tails[3usize] }
        var r = 0.0f64
        var j = 0i64
        i = 0i64
        while i < d.nd {
            r = r + d.data[u(i)]
            j = j + d.delta[u(i)]
            i += 1i64
        }
        r = r / f64(j)
        m.theta[u(nk - 1i64)] = 0.0f64 - hmylog(r)
        ret
    }
    let phi = w.phi
    let mat = w.mat
    var j = 0i64
    while j < nk + 2i64 {
        var i = 0i64
        while i < nk - 1i64 {
            mat[mi(j, i)] = m.coef2[mi(i, j)]
            i += 1i64
        }
        j += 1i64
    }
    j = 0i64
    while j < nk + 2i64 {
        phi[u(j)] = m.theta[u(j)]
        j += 1i64
    }
    let rc = hlusolve2(w, mat, u(nk - 1i64), phi)
    m.theta[0usize] = m.theta[u(nk + 2i64)]
    m.theta[u(nk)] = m.theta[u(nk + 3i64)]
    j = 0i64
    while j < nk - 1i64 {
        m.theta[u(j + 1i64)] = phi[u(j)]
        j += 1i64
    }
}

// theta in the truncated power basis, indexed by yknots
fn thetaswap(w: *W, m: *M) {
    let phi = w.phi2
    var i = 0i64
    while i < HL {
        phi[u(i)] = 0.0f64
        i += 1i64
    }
    var j = 0i64
    while j < m.nk - 1i64 {
        i = 0i64
        while i < m.nk + 2i64 {
            phi[u(i)] = phi[u(i)] + m.theta[u(j + 1i64)] * m.coef2[mi(j, i)]
            i += 1i64
        }
        j += 1i64
    }
    m.theta[u(m.nk1 + 3i64)] = m.theta[u(m.nk)]
    m.theta[u(m.nk1 + 2i64)] = m.theta[0usize]
    m.theta[u(m.nk1 + 1i64)] = phi[1usize]
    m.theta[u(m.nk1)] = phi[0usize]
    j = 1i64
    i = 0i64
    while i < m.nk1 {
        m.theta[u(i)] = 0.0f64
        if m.iknots[u(i)] == 1 {
            j = j + 1i64
            m.theta[u(i)] = phi[u(j)]
        }
        i += 1i64
    }
}

// --- the integration multipliers

fn lgrange(a: f64, b: f64, c: f64, d: f64, n0: f64, uu: f64, v: f64, mult: []f64, j: i64) {
    let n = n0 / ((d - a) * (d - b) * (d - c))
    var cc: [5]f64 = zero
    var u6: [6]f64 = zero
    var v6: [6]f64 = zero
    cc[4usize] = n
    cc[3usize] = 0.0f64 - n * (a + b + c)
    cc[2usize] = n * (a * b + a * c + b * c)
    cc[1usize] = 0.0f64 - a * b * c * n
    u6[1usize] = uu
    var i = 2usize
    while i < 5usize {
        u6[i] = uu * u6[i - 1usize] * f64(i - 1usize) / f64(i)
        i += 1usize
    }
    v6[1usize] = v
    i = 2usize
    while i < 5usize {
        v6[i] = v * v6[i - 1usize] * f64(i - 1usize) / f64(i)
        i += 1usize
    }
    i = 1usize
    while i < 5usize {
        mult[u(j)] = mult[u(j)] - (v6[i] - u6[i]) * cc[i]
        i += 1usize
    }
}

fn midblob(w: *W, j: i64, i0: i64, nint: i64, basvec: []f64, mult: []f64, nx: i64, data: []f64) {
    var i = i0
    var zmin = basvec[u(j * nint + i)]
    let zmax = basvec[u(j * nint + i + 1i64)]
    if j * nint + i == 0i64 { zmin = 0.0f64 }
    if i == 0i64 { i = 1i64 }
    if i == nint - 1i64 { i = nint - 2i64 }
    let i1 = j * nint + i - 1i64
    let i2 = j * nint + i
    let i3 = j * nint + i + 1i64
    let i4 = j * nint + i + 2i64
    let x1 = basvec[u(i1)]
    let x2 = basvec[u(i2)]
    let x3 = basvec[u(i3)]
    let x4 = basvec[u(i4)]
    var go = true
    while go {
        if data[u(w.where)] >= zmax || w.where >= nx {
            let nn = f64(nx - w.where)
            lgrange(x1, x2, x3, x4, nn, zmin, zmax, mult, i4)
            lgrange(x1, x2, x4, x3, nn, zmin, zmax, mult, i3)
            lgrange(x1, x3, x4, x2, nn, zmin, zmax, mult, i2)
            lgrange(x2, x3, x4, x1, nn, zmin, zmax, mult, i1)
            zmin = zmax + 1.0f64
            if data[u(w.where)] == zmax { w.where = w.where + 1i64 }
        } else {
            let nn = f64(nx - w.where)
            let dv = data[u(w.where)]
            lgrange(x1, x2, x3, x4, nn, zmin, dv, mult, i4)
            lgrange(x1, x2, x4, x3, nn, zmin, dv, mult, i3)
            lgrange(x1, x3, x4, x2, nn, zmin, dv, mult, i2)
            lgrange(x2, x3, x4, x1, nn, zmin, dv, mult, i1)
            zmin = dv
            w.where = w.where + 1i64
        }
        go = zmin < zmax
    }
}

fn hopplus(xx: []f64, data: []f64, i: i64, j: i64) -> i64 {
    xx[u(i)] = data[u(j)]
    if xx[u(i)] > xx[u(i - 1i64)] { ret i + 1i64 }
    ret i
}

// what 0 only the basis, 1 low-precision integration multipliers, 2 high precision; nint is read and updated
fn intprep(w: *W, nint: *i64, nintx: i64, m: *M, d: *D, what: i64) {
    let npart = *nint
    var nkplus = 0i64
    let nx = d.nd
    var hopla = 1i64
    if what != 0i64 {
        let masterpt = w.masterpt
        let xx = w.xx
        xx[0usize] = d.data[u(nx / 100i64)]
        if what == 2i64 { hopla = hopplus(xx, d.data, hopla, nx / 25i64) }
        if what == 2i64 { hopla = hopplus(xx, d.data, hopla, nx / 15i64) }
        hopla = hopplus(xx, d.data, hopla, nx / 10i64)
        if what == 2i64 { hopla = hopplus(xx, d.data, hopla, nx / 8i64) }
        if what == 2i64 { hopla = hopplus(xx, d.data, hopla, nx / 6i64) }
        hopla = hopplus(xx, d.data, hopla, nx / 4i64)
        hopla = hopplus(xx, d.data, hopla, nx / 2i64)
        hopla = hopplus(xx, d.data, hopla, nx - nx / 4i64)
        if what == 2i64 { hopla = hopplus(xx, d.data, hopla, nx - nx / 6i64) }
        if what == 2i64 { hopla = hopplus(xx, d.data, hopla, nx - nx / 8i64) }
        hopla = hopplus(xx, d.data, hopla, nx - nx / 10i64)
        if what == 2i64 { hopla = hopplus(xx, d.data, hopla, nx - nx / 15i64) }
        if what == 2i64 { hopla = hopplus(xx, d.data, hopla, nx - nx / 25i64) }
        hopla = hopplus(xx, d.data, hopla, nx - 1i64)
        var cr = (xx[1usize] - xx[0usize]) / 1.5f64
        var i = 1i64
        while i < hopla - 1i64 {
            if (xx[u(i + 1i64)] - xx[u(i)]) / 1.5f64 < cr { cr = (xx[u(i + 1i64)] - xx[u(i)]) / 1.5f64 }
            i += 1i64
        }
        i = 0i64
        var j = 0i64
        var k = 0i64
        var go = true
        while go {
            if xx[u(i)] < m.knots[u(j)] || j == m.nk {
                masterpt[u(nkplus)] = xx[u(i)]
                nkplus += 1i64
                if k == 1i64 && masterpt[u(nkplus - 1i64)] - masterpt[u(nkplus - 2i64)] < cr {
                    if i < hopla - 1i64 || m.knots[u(m.nk - 1i64)] >= d.data[u(nx - 3i64)] {
                        nkplus = nkplus - 1i64
                    } else {
                        k = 2i64
                    }
                } else {
                    k = 2i64
                }
                i += 1i64
            } else {
                masterpt[u(nkplus)] = m.knots[u(j)]
                nkplus += 1i64
                if k == 2i64 && masterpt[u(nkplus - 1i64)] - masterpt[u(nkplus - 2i64)] < cr {
                    if j > 0i64 || i > 0i64 || m.knots[0usize] < d.data[2usize] || i < 1i64 {
                        nkplus = nkplus - 1i64
                        masterpt[u(nkplus - 1i64)] = masterpt[u(nkplus)]
                    }
                }
                j += 1i64
                k = 1i64
            }
            go = i < hopla || j < m.nk
        }
        masterpt[u(nkplus - 1i64)] = d.data[u(nx - 1i64)]
        if masterpt[0usize] == 0.0f64 { masterpt[0usize] = masterpt[1usize] / 2.0f64 }
        *nint = (nkplus + 2i64 * nintx) * (*nint) + 1i64
        let bv = m.basvec
        bv[0usize] = 1.0f64 / (21.365f64 * f64((nintx + 1i64) * npart)) * masterpt[0usize]
        bv[1usize] = 1.0f64 / (2.0904f64 * f64((nintx + 1i64) * npart)) * masterpt[0usize]
        i = 2i64
        while i <= npart * (nintx + 1i64) {
            bv[u(i)] = (f64(i - 1i64) / f64((nintx + 1i64) * npart - 1i64)) * masterpt[0usize]
            i += 1i64
        }
        if nkplus > 2i64 {
            j = 1i64
            while j < nkplus - 1i64 {
                i = 1i64
                while i <= npart {
                    bv[u((j + nintx) * npart + i)] = (f64(i) / f64(npart)) * (masterpt[u(j)] - masterpt[u(j - 1i64)]) + masterpt[u(j - 1i64)]
                    i += 1i64
                }
                j += 1i64
            }
        }
        i = 1i64
        while i <= npart * (nintx + 1i64) {
            bv[u(i + (nkplus + nintx - 1i64) * npart)] = (f64(i) / f64((nintx + 1i64) * npart)) * (masterpt[u(nkplus - 1i64)] - masterpt[u(nkplus - 2i64)]) + masterpt[u(nkplus - 2i64)]
            i += 1i64
        }
        i = 0i64
        while i < npart * (nkplus + 2i64 * nintx) + 1i64 {
            m.mult[u(i)] = 0.0f64
            i += 1i64
        }
        w.where = 0i64
        j = 0i64
        while j < nkplus + 2i64 * nintx {
            i = 0i64
            while i < npart {
                midblob(w, j, i, npart, m.basvec, m.mult, nx, d.data)
                i += 1i64
            }
            j += 1i64
        }
    }
    basis(d.data, d.nd, m, d.cc, d.bd1)
    basis(m.basvec, *nint, m, d.cc, m.basmat)
}

// --- likelihood, score and Hessian

fn lambda(nk: i64, basis_: []f64, theta: []f64, which: i64) -> f64 {
    var r = theta[0usize] * basis_[mi(which, 0i64)] + theta[u(nk)] * basis_[mi(which, nk)] + theta[u(nk - 1i64)] * basis_[mi(which, nk - 1i64)]
    var k = i64(basis_[mi(which, nk + 1i64)])
    while k <= i64(basis_[mi(which, nk + 2i64)]) && k > 0i64 {
        r = r + theta[u(k)] * basis_[mi(which, k)]
        k += 1i64
    }
    ret r
}

fn summer2(score: []f64, hessian: []f64, what: i64, nk: i64, ndata: i64, nint: i64, theta: []f64, basdata: []f64, basint: []f64, delta: []i64, mult: []f64) -> f64 {
    var logl = 0.0f64
    var i = 0i64
    if what > 0i64 {
        i = 0i64
        while i <= nk {
            score[u(i)] = 0.0f64
            if what > 1i64 {
                var j = 0i64
                while j <= nk {
                    hessian[mi(i, j)] = 0.0f64
                    j += 1i64
                }
            }
            i += 1i64
        }
    }
    i = 0i64
    while i < nint {
        let lam = math.exp[f64](lambda(nk, basint, theta, i))
        let lm0 = lam * mult[u(i)]
        logl = logl + lm0
        if what > 0i64 {
            score[0usize] = score[0usize] + lm0 * basint[mi(i, 0i64)]
            score[u(nk - 1i64)] = score[u(nk - 1i64)] + lm0 * basint[mi(i, nk - 1i64)]
            score[u(nk)] = score[u(nk)] + lm0 * basint[mi(i, nk)]
            var j = i64(basint[mi(i, nk + 1i64)])
            while j <= i64(basint[mi(i, nk + 2i64)]) && j > 0i64 {
                score[u(j)] = score[u(j)] + lm0 * basint[mi(i, j)]
                j += 1i64
            }
            if what > 1i64 {
                var lm1 = lm0 * basint[mi(i, nk)]
                var k = 0i64
                while k <= nk {
                    hessian[mi(k, nk)] = hessian[mi(k, nk)] + lm1 * basint[mi(i, k)]
                    k += 1i64
                }
                lm1 = lm0 * basint[mi(i, nk - 1i64)]
                k = 0i64
                while k <= nk - 1i64 {
                    hessian[mi(k, nk - 1i64)] = hessian[mi(k, nk - 1i64)] + lm1 * basint[mi(i, k)]
                    k += 1i64
                }
                lm1 = lm0 * basint[mi(i, 0i64)]
                hessian[mi(0i64, 0i64)] = hessian[mi(0i64, 0i64)] + lm1 * basint[mi(i, 0i64)]
                j = i64(basint[mi(i, nk + 1i64)])
                while j <= i64(basint[mi(i, nk + 2i64)]) && j > 0i64 {
                    lm1 = lm0 * basint[mi(i, j)]
                    k = 0i64
                    while k <= j {
                        hessian[mi(k, j)] = hessian[mi(k, j)] + lm1 * basint[mi(i, k)]
                        k += 1i64
                    }
                    j += 1i64
                }
            }
        }
        i += 1i64
    }
    var j = 0i64
    while j < nk {
        var k = j + 1i64
        while k <= nk {
            hessian[mi(k, j)] = hessian[mi(j, k)]
            k += 1i64
        }
        j += 1i64
    }
    i = 0i64
    while i < ndata {
        if delta[u(i)] == 1 {
            let lam = lambda(nk, basdata, theta, i)
            logl = logl + lam
            if what > 0i64 {
                j = 0i64
                while j <= nk {
                    score[u(j)] = score[u(j)] + basdata[mi(i, j)]
                    j += 1i64
                }
            }
        }
        i += 1i64
    }
    ret logl
}

fn summer(m: *M, what: i64, nint: i64, d: *D) -> f64 {
    ret summer2(m.score, m.hessian, what, m.nk, d.nd, nint, m.theta, d.bd1, m.basmat, d.delta, m.mult)
}

// one Newton-Raphson step; returns the status code and the likelihood gain in ldif[0]
fn step(w: *W, d: *D, m: *M, itails: []i64, ldif: []f64, nint: i64, what: i64) -> i64 {
    let nk = m.nk
    let theta = m.theta
    let score = m.score
    let hessian = m.hessian
    let cand = w.cand
    let lold = summer2(score, hessian, 2, nk, d.nd, nint, theta, d.bd1, m.basmat, d.delta, m.mult)
    var i = 0i64
    while i < 3i64 {
        if itails[u(i)] > 0i64 {
            if i == 2i64 { i = nk }
            var j = 0i64
            while j <= nk {
                hessian[mi(j, i)] = 0.0f64
                hessian[mi(i, j)] = 0.0f64
                j += 1i64
            }
            score[u(i)] = 0.0f64
            hessian[mi(i, i)] = 1.0f64
        }
        i += 1i64
    }
    let rc = hlusolve(w, hessian, u(nk + 1i64), score)
    if rc == 0i64 - 1i64 { ret 1i64 }
    if itails[0usize] <= 0i64 {
        var r = 0.0f64 - theta[0usize] - 1.0f64
        if r > 0.0f64 - score[0usize] {
            r = 1.0f64 / math.pow[f64](1.5f64, math.ceil[f64](hmylog((0.0f64 - score[0usize]) / r) / hmylog(1.5f64)))
            if r < 0.0001f64 && itails[0usize] >= 0i64 { ret 2i64 }
            i = 0i64
            while i <= nk {
                score[u(i)] = score[u(i)] * r
                i += 1i64
            }
        }
    }
    var r = 2.0f64
    i = 0i64 - 1i64
    var lnew = 0.0f64
    var again = true
    while again {
        r = r / 2.0f64
        i += 1i64
        var j = 0i64
        while j <= nk {
            cand[u(j)] = theta[u(j)] - r * score[u(j)]
            j += 1i64
        }
        if r < 0.000000001f64 { ret 3i64 }
        lnew = summer2(score, hessian, 0, nk, d.nd, nint, cand, d.bd1, m.basmat, d.delta, m.mult)
        ldif[0usize] = lnew - lold
        again = ldif[0usize] < 0.0f64 - 0.00000001f64 && r > 0.0f64
    }
    if r > 0.0f64 {
        if cand[u(nk)] < 0.0f64 - 1.02f64 {
            r = (0.0f64 - 1.02f64 - theta[u(nk)]) / (cand[u(nk)] - theta[u(nk)])
            var j = 0i64
            while j <= nk {
                theta[u(j)] = r * cand[u(j)] + (1.0f64 - r) * theta[u(j)]
                j += 1i64
            }
        } else {
            var j = 0i64
            while j <= nk {
                theta[u(j)] = cand[u(j)]
                j += 1i64
            }
        }
    }
    ret 0i64
}

// the main Newton-Raphson loop; zerr[1] is set on trouble
fn hiter(w: *W, m: *M, d: *D, zerr: []i64, nint: i64, what: i64) {
    var ldif: [2]f64 = zero
    var itails: [3]i64 = zero
    if m.tails[0usize] > 0.5f64 { itails[0usize] = 1i64 } else { itails[0usize] = 0i64 }
    if m.tails[4usize] > 0.5f64 { itails[1usize] = 1i64 } else { itails[1usize] = 0i64 }
    if m.tails[2usize] > 0.5f64 {
        itails[2usize] = 1i64
    } else {
        itails[2usize] = 0i64
        if m.theta[u(m.nk)] < 0.0f64 - 0.999f64 { itails[2usize] = 2i64 }
    }
    var ctr = 1i64
    while ctr < 500i64 {
        var status = step(w, d, m, itails[0usize..3usize], ldif[0usize..2usize], nint, what)
        if m.theta[u(m.nk)] < 0.0f64 - 1.0f64 {
            m.theta[u(m.nk)] = 0.0f64 - 1.0f64
            itails[2usize] = 2i64
            status = 4i64
        }
        if status == 1i64 || status == 3i64 || (status == 2i64 && itails[0usize] == 0i64 - 1i64) {
            zerr[1usize] = 1
            ret
        }
        if status == 2i64 && itails[0usize] == 0i64 {
            m.theta[0usize] = 0.0f64 - 0.8f64
            itails[0usize] = 2i64
        }
        if status == 0i64 && ldif[0usize] < 0.0000001f64 {
            if itails[0usize] < 2i64 && itails[2usize] < 2i64 { ctr = ctr + 10000i64 }
            if itails[2usize] == 2i64 {
                ldif[0usize] = summer(m, 2, nint, d)
                if m.score[u(m.nk)] > 0.0f64 {
                    itails[2usize] = 0i64
                } else {
                    ctr = ctr + 10000i64
                }
            }
            if itails[0usize] == 2i64 { itails[0usize] = 0i64 - 1i64 }
        }
        ctr += 1i64
    }
    if ctr < 1000i64 {
        zerr[1usize] = 2
        ret
    }
    if m.tails[2usize] < 2.5f64 { ldif[0usize] = summer(m, 2, nint, d) }
    var i = 0i64
    while i < 3i64 {
        if itails[u(i)] != 0i64 {
            if i == 2i64 { i = m.nk }
            var j = 0i64
            while j <= m.nk {
                m.hessian[mi(j, i)] = 0.0f64
                m.hessian[mi(i, j)] = 0.0f64
                j += 1i64
            }
            m.score[u(i)] = 0.0f64
            m.hessian[mi(i, i)] = 0.0f64 - 1.0f64
        }
        i += 1i64
    }
    m.ll = ldif[0usize]
}

// --- removing a knot

fn hremoveknot(w: *W, m: *M) {
    var ratmax = 0.0f64
    var irmax = 1i64
    let se = w.se3
    let phi = w.phi3
    m.nk = m.nk - 1i64
    let nk = m.nk
    var i = 0i64
    while i <= nk {
        phi[u(i)] = 0.0f64
        var j = 0i64
        while j < nk {
            phi[u(i)] = phi[u(i)] + m.theta[u(j + 1i64)] * m.coef2[mi(j, i + 2i64)]
            j += 1i64
        }
        phi[u(i)] = fabs(phi[u(i)])
        i += 1i64
    }
    if m.tails[0usize] > 0.5f64 {
        m.hessian[mi(0i64, 0i64)] = 0.0f64 - 1.0f64
        var j = 1i64
        while j < nk + 2i64 {
            m.hessian[mi(0i64, j)] = 0.0f64
            m.hessian[mi(j, 0i64)] = 0.0f64
            j += 1i64
        }
    }
    if m.tails[2usize] > 0.5f64 || m.theta[u(nk + 1i64)] <= 0.0f64 - 0.999999f64 {
        var j = 0i64
        while j < nk + 2i64 {
            m.hessian[mi(nk + 1i64, j)] = 0.0f64
            m.hessian[mi(j, nk + 1i64)] = 0.0f64
            j += 1i64
        }
        m.hessian[mi(nk + 1i64, nk + 1i64)] = 0.0f64 - 1.0f64
    }
    if m.tails[4usize] > 0.5f64 {
        var j = 0i64
        while j < nk + 2i64 {
            m.hessian[mi(1i64, j)] = 0.0f64
            m.hessian[mi(j, 1i64)] = 0.0f64
            j += 1i64
        }
        m.hessian[mi(1i64, 1i64)] = 0.0f64 - 1.0f64
    }
    hluinverse(w, m.hessian, u(nk + 2i64))
    if m.tails[0usize] > 0.5f64 {
        m.tse0 = 0.0f64
    } else {
        m.tse0 = math.sqrt[f64](0.0f64 - m.hessian[mi(0i64, 0i64)])
    }
    if m.tails[2usize] > 0.5f64 || m.theta[u(nk + 1i64)] <= 0.0f64 - 1.0f64 {
        m.tse1 = 0.0f64
    } else {
        m.tse1 = math.sqrt[f64](0.0f64 - m.hessian[mi(nk + 1i64, nk + 1i64)])
    }
    if nk == 1i64 || (nk == 2i64 && m.tails[4usize] > 0.5f64) { ret }
    if m.tails[4usize] > 0.5f64 {
        var j = 0i64
        while j < nk + 2i64 {
            m.hessian[mi(1i64, j)] = 0.0f64
            m.hessian[mi(j, 1i64)] = 0.0f64
            j += 1i64
        }
        m.hessian[mi(1i64, 1i64)] = 0.0f64
    }
    if nk > 3i64 || (nk == 2i64 && m.tails[4usize] < 0.5f64) {
        i = 0i64
        while i < nk + 1i64 {
            se[u(i)] = 0.0f64
            var j = 0i64
            while j < nk {
                var k = 0i64
                while k < nk {
                    se[u(i)] = se[u(i)] - m.coef2[mi(j, i + 2i64)] * m.coef2[mi(k, i + 2i64)] * m.hessian[mi(j + 1i64, k + 1i64)]
                    k += 1i64
                }
                j += 1i64
            }
            se[u(i)] = math.sqrt[f64](fabs(se[u(i)]))
            if se[u(i)] > phi[u(i)] * ratmax {
                ratmax = se[u(i)] / phi[u(i)]
                irmax = i
            }
            i += 1i64
        }
    } else {
        irmax = 1i64
    }
    var j = 0i64
    i = 0i64
    while i < HL {
        if m.iknots[u(i)] == 1 {
            if j == irmax {
                m.iknots[u(i)] = 0
                i = HL
            }
            j += 1i64
        }
        i += 1i64
    }
    if irmax < nk {
        i = irmax
        while i < nk {
            m.knots[u(i)] = m.knots[u(i + 1i64)]
            i += 1i64
        }
    }
}

fn tossit(w: *W, m: *M, mn: *M, alpha: f64) {
    m.aic = 0.0f64 - 2.0f64 * m.ll + alpha * f64(m.nk + 1i64)
    if m.tails[4usize] > 0.5f64 { m.aic = m.aic - alpha }
    if m.ll > m.logl[u(m.nk)] || mn.ad[u(m.nk)] == 2 {
        m.logl[u(m.nk)] = m.ll
        mn.logl[u(m.nk)] = m.ll
        mn.ad[u(m.nk)] = 1
    }
    if m.aic <= mn.aic {
        dubmodel(mn, m)
    } else {
        if 0.0f64 - 2.0f64 * m.ll + alpha > mn.aic { m.nk = 0i64 }
    }
    hremoveknot(w, m)
    if mn.nk == m.nk + 1i64 && mn.ad[u(m.nk)] == 1 {
        mn.tse0 = m.tse0
        mn.tse1 = m.tse1
    }
}

fn getse2(w: *W, m: *M) {
    let phi = w.phi4
    let hh = w.hh
    let nk = m.nk - 1i64
    var j = 0i64
    while j < HL {
        var i = 0i64
        while i < HL {
            hh[mi(i, j)] = m.hessian[mi(i, j)]
            i += 1i64
        }
        j += 1i64
    }
    var i = 0i64
    while i <= nk {
        phi[u(i)] = 0.0f64
        j = 0i64
        while j < nk {
            phi[u(i)] = phi[u(i)] + m.theta[u(j + 1i64)] * m.coef2[mi(j, i + 2i64)]
            j += 1i64
        }
        phi[u(i)] = fabs(phi[u(i)])
        i += 1i64
    }
    if m.tails[0usize] > 0.5f64 {
        hh[mi(0i64, 0i64)] = 0.0f64 - 1.0f64
        j = 1i64
        while j < nk + 2i64 {
            hh[mi(0i64, j)] = 0.0f64
            hh[mi(j, 0i64)] = 0.0f64
            j += 1i64
        }
    }
    if m.tails[2usize] > 0.5f64 || m.theta[u(nk + 1i64)] <= 0.0f64 - 0.999999f64 {
        j = 0i64
        while j < nk + 2i64 {
            hh[mi(nk + 1i64, j)] = 0.0f64
            hh[mi(j, nk + 1i64)] = 0.0f64
            j += 1i64
        }
        hh[mi(nk + 1i64, nk + 1i64)] = 0.0f64 - 1.0f64
    }
    if m.tails[4usize] > 0.5f64 {
        j = 0i64
        while j < nk + 2i64 {
            hh[mi(1i64, j)] = 0.0f64
            hh[mi(j, 1i64)] = 0.0f64
            j += 1i64
        }
        hh[mi(1i64, 1i64)] = 0.0f64 - 1.0f64
    }
    hluinverse(w, hh, u(nk + 2i64))
    if m.tails[0usize] > 0.5f64 {
        m.tse0 = 0.0f64
    } else {
        m.tse0 = math.sqrt[f64](0.0f64 - hh[mi(0i64, 0i64)])
    }
    if m.tails[2usize] > 0.5f64 || m.theta[u(nk + 1i64)] <= 0.0f64 - 1.0f64 {
        m.tse1 = 0.0f64
    } else {
        m.tse1 = math.sqrt[f64](0.0f64 - hh[mi(nk + 1i64, nk + 1i64)])
    }
}

fn hetse(w: *W, m: *M, mn: *M, alpha: f64) {
    m.aic = 0.0f64 - 2.0f64 * m.ll + alpha * f64(m.nk + 1i64)
    if m.tails[4usize] > 0.5f64 { m.aic = m.aic - alpha }
    m.logl[u(m.nk)] = m.ll
    mn.ad[u(m.nk)] = 0
    mn.logl[u(m.nk)] = m.ll
    if m.aic <= mn.aic {
        dubmodel(mn, m)
        getse2(w, m)
        mn.tse0 = m.tse0
        mn.tse1 = m.tse1
    }
}

// --- adding a knot

fn hlocation(what: i64, x: []f64, nx: i64, k: f64) -> i64 {
    if what == 1i64 {
        if x[0usize] > k { ret 0i64 }
        if x[u(nx - 1i64)] <= k { ret nx - 1i64 }
        var i = 0i64
        while i < nx - 1i64 {
            if x[u(i + 1i64)] > k && x[u(i)] <= k { ret i }
            i += 1i64
        }
    }
    if x[u(nx - 1i64)] < k { ret nx - 1i64 }
    if x[0usize] >= k { ret 0i64 }
    var i = 1i64
    while i < nx {
        if x[u(i)] >= k && x[u(i - 1i64)] < k { ret i }
        i += 1i64
    }
    ret nx
}

fn hindyl(uu: i64, l: i64, x: []f64) -> i64 {
    if x[u(l)] == x[u(uu)] { ret 0i64 - 1i64 }
    var i = (uu + l - 1i64) / 2i64
    if x[u(i)] != x[u(uu)] { ret i }
    i = (i + l) / 2i64
    if x[u(i)] != x[u(uu)] { ret i }
    ret l
}

fn hindyr(uu: i64, l: i64, x: []f64) -> i64 {
    if x[u(l)] == x[u(uu)] { ret 0i64 - 1i64 }
    var i = (uu + l + 1i64) / 2i64
    if x[u(i)] != x[u(l)] { ret i }
    i = (i + uu) / 2i64
    if x[u(i)] != x[u(l)] { ret i }
    ret uu
}

fn hindl(lu2: []i64, mind: i64, x: []f64, nx: i64, knt: f64) -> i64 {
    lu2[1usize] = hlocation(0, x, nx, knt)
    if lu2[1usize] < mind - 1i64 { ret 0i64 - 1i64 }
    var i = (lu2[1usize] - 1i64) / 2i64
    if lu2[1usize] - i < mind + 1i64 { i = lu2[1usize] - mind - 1i64 }
    lu2[0usize] = 0i64
    lu2[1usize] = lu2[1usize] - mind - 1i64
    ret i
}

fn hindr(lu2: []i64, mind: i64, x: []f64, nx: i64, knt: f64) -> i64 {
    lu2[0usize] = hlocation(1, x, nx, knt)
    if nx - 1i64 - lu2[0usize] <= mind { ret 0i64 - 1i64 }
    var i = (nx + lu2[0usize]) / 2i64
    if i - lu2[0usize] < mind + 1i64 { i = lu2[0usize] + mind + 1i64 }
    lu2[1usize] = nx - 1i64
    lu2[0usize] = lu2[0usize] + mind + 1i64
    ret i
}

fn hindx(lu2: []i64, nx: i64) -> i64 {
    lu2[0usize] = 0i64
    lu2[1usize] = nx - 1i64
    ret nx / 2i64
}

fn hindm(lu2: []i64, mind: i64, x: []f64, nx: i64, k0: f64, k1: f64) -> i64 {
    lu2[0usize] = hlocation(1, x, nx, k0)
    lu2[1usize] = hlocation(0, x, nx, k1)
    if lu2[1usize] - lu2[0usize] < 2i64 * mind + 1i64 { ret 0i64 - 1i64 }
    lu2[1usize] = lu2[1usize] - mind - 1i64
    lu2[0usize] = lu2[0usize] + mind + 1i64
    ret (lu2[1usize] + lu2[0usize]) / 2i64
}

// the new basis function at the integration points (newbas) and the uncensored data points (newdata)
fn newnew(w: *W, m: *M, cand: f64, nint: i64, d: *D, ipowdat: []i64, ipowvec: []i64) {
    let nk = m.nk
    let knots = m.knots
    let basvec = m.basvec
    let newbas = w.newbas
    let newdata = w.newdata
    let mat = w.mat33
    let vec = w.vec3
    if nk > 2i64 {
        vec[0usize] = 0.0f64 - 1.0f64
        vec[1usize] = 0.0f64 - cand
        vec[2usize] = 0.0f64 - cand * cand
        mat[0usize] = 1.0f64
        mat[1usize] = 1.0f64
        mat[2usize] = 1.0f64
        mat[4usize] = knots[u(nk - 3i64)]
        mat[5usize] = knots[u(nk - 2i64)]
        mat[6usize] = knots[u(nk - 1i64)]
        mat[8usize] = knots[u(nk - 3i64)] * knots[u(nk - 3i64)]
        mat[9usize] = knots[u(nk - 2i64)] * knots[u(nk - 2i64)]
        mat[10usize] = knots[u(nk - 1i64)] * knots[u(nk - 1i64)]
        // mat33 is a 3 by 3 matrix of row stride 4; solve it with the general LU on a copy in the stride HS scratch
        let sc = w.mat1
        var r = 0i64
        while r < 3i64 {
            var c = 0i64
            while c < 3i64 {
                sc[mi(r, c)] = mat[u(r) * 4usize + u(c)]
                c += 1i64
            }
            r += 1i64
        }
        let rc = hlusolve2(w, sc, 3usize, vec)
        var i = 0i64
        while i < nint {
            newbas[u(i)] = 0.0f64
            if basvec[u(i)] > cand { newbas[u(i)] = math.pow[f64](basvec[u(i)] - cand, 3.0f64) }
            i += 1i64
        }
        var j = 0usize
        while j < 3usize {
            if ipowvec[j] < nint - 1i64 {
                i = ipowvec[j] + 1i64
                while i < nint {
                    newbas[u(i)] = newbas[u(i)] + vec[j] * w.powvec[u(i) * 3usize + j]
                    i += 1i64
                }
            }
            j += 1usize
        }
        i = 0i64
        while i < d.nd {
            newdata[u(i)] = 0.0f64
            if d.delta[u(i)] == 1 {
                if d.data[u(i)] > cand { newdata[u(i)] = math.pow[f64](d.data[u(i)] - cand, 3.0f64) }
            }
            i += 1i64
        }
        j = 0usize
        while j < 3usize {
            if ipowdat[j] < d.nd - 1i64 {
                i = ipowdat[j] + 1i64
                while i < d.nd {
                    if d.delta[u(i)] == 1 { newdata[u(i)] = newdata[u(i)] + vec[j] * w.powdat[u(i) * 3usize + j] }
                    i += 1i64
                }
            }
            j += 1usize
        }
    }
    if nk == 2i64 {
        vec[0usize] = (knots[1usize] - cand) / (knots[0usize] - knots[1usize])
        vec[1usize] = (cand - knots[0usize]) / (knots[0usize] - knots[1usize])
        var i = 0i64
        while i < d.nd {
            newdata[u(i)] = 0.0f64
            if d.delta[u(i)] == 1 {
                let x = d.data[u(i)]
                if x < cand { newdata[u(i)] = math.pow[f64](x - cand, 3.0f64) }
                if x < knots[1usize] {
                    newdata[u(i)] = newdata[u(i)] + vec[1usize] * math.pow[f64](x - knots[1usize], 3.0f64)
                    if x < knots[0usize] {
                        newdata[u(i)] = newdata[u(i)] + vec[0usize] * math.pow[f64](x - knots[0usize], 3.0f64)
                    }
                }
            }
            i += 1i64
        }
        i = 0i64
        while i < nint {
            newbas[u(i)] = 0.0f64
            let x = basvec[u(i)]
            if x < cand { newbas[u(i)] = math.pow[f64](x - cand, 3.0f64) }
            if x < knots[1usize] {
                newbas[u(i)] = newbas[u(i)] + vec[1usize] * math.pow[f64](x - knots[1usize], 3.0f64)
                if x < knots[0usize] {
                    newbas[u(i)] = newbas[u(i)] + vec[0usize] * math.pow[f64](x - knots[0usize], 3.0f64)
                }
            }
            i += 1i64
        }
    }
}

fn hrao(w: *W, m: *M, d: *D, cand: f64, nint: i64, ipowvec: []i64, ipowdat: []i64) -> f64 {
    let nk = m.nk
    let info2 = w.info2
    let score2 = w.score2
    let score3 = w.score3
    let newbas = w.newbas
    let newdata = w.newdata
    score2[u(nk + 1i64)] = 0.0f64
    info2[mi(nk + 1i64, nk + 1i64)] = 0.0f64
    var i = 0i64
    while i <= nk {
        score2[u(i)] = m.score[u(i)]
        info2[mi(i, nk + 1i64)] = 0.0f64
        info2[mi(nk + 1i64, i)] = 0.0f64
        var j = 0i64
        while j <= nk {
            info2[mi(i, j)] = m.hessian[mi(i, j)]
            j += 1i64
        }
        i += 1i64
    }
    newnew(w, m, cand, nint, d, ipowdat, ipowvec)
    i = 0i64
    while i < nint {
        let lam = math.exp[f64](lambda(nk, m.basmat, m.theta, i))
        let lm0 = lam * m.mult[u(i)] * newbas[u(i)]
        score2[u(nk + 1i64)] = score2[u(nk + 1i64)] + lm0
        info2[mi(nk + 1i64, nk + 1i64)] = info2[mi(nk + 1i64, nk + 1i64)] + lm0 * newbas[u(i)]
        info2[mi(0i64, nk + 1i64)] = info2[mi(0i64, nk + 1i64)] + lm0 * m.basmat[mi(i, 0i64)]
        info2[mi(nk - 1i64, nk + 1i64)] = info2[mi(nk - 1i64, nk + 1i64)] + lm0 * m.basmat[mi(i, nk - 1i64)]
        info2[mi(nk, nk + 1i64)] = info2[mi(nk, nk + 1i64)] + lm0 * m.basmat[mi(i, nk)]
        var j = i64(m.basmat[mi(i, nk + 1i64)])
        while j <= i64(m.basmat[mi(i, nk + 2i64)]) && j > 0i64 {
            info2[mi(j, nk + 1i64)] = info2[mi(j, nk + 1i64)] + lm0 * m.basmat[mi(i, j)]
            j += 1i64
        }
        i += 1i64
    }
    i = 0i64
    while i < d.nd {
        if d.delta[u(i)] == 1 { score2[u(nk + 1i64)] = score2[u(nk + 1i64)] + newdata[u(i)] }
        i += 1i64
    }
    if m.tails[0usize] > 0.5f64 || m.theta[0usize] < 0.0f64 - 0.999f64 {
        score2[0usize] = 0.0f64
        info2[mi(0i64, 0i64)] = 0.0f64 - 1.0f64
        i = 1i64
        while i <= nk + 1i64 {
            info2[mi(0i64, i)] = 0.0f64
            info2[mi(i, 0i64)] = 0.0f64
            i += 1i64
        }
    }
    if m.tails[4usize] > 0.5f64 {
        score2[1usize] = 0.0f64
        i = 0i64
        while i <= nk + 1i64 {
            info2[mi(1i64, i)] = 0.0f64
            info2[mi(i, 1i64)] = 0.0f64
            i += 1i64
        }
        info2[mi(1i64, 1i64)] = 0.0f64 - 1.0f64
    }
    if m.tails[2usize] > 0.5f64 || m.theta[u(nk)] < 0.0f64 - 0.999f64 {
        score2[u(nk)] = 0.0f64
        i = 0i64
        while i <= nk + 1i64 {
            info2[mi(nk, i)] = 0.0f64
            info2[mi(i, nk)] = 0.0f64
            i += 1i64
        }
        info2[mi(nk, nk)] = 0.0f64 - 1.0f64
    }
    var j = 0i64
    while j <= nk + 1i64 {
        info2[mi(nk + 1i64, j)] = info2[mi(j, nk + 1i64)]
        score3[u(j)] = score2[u(j)]
        j += 1i64
    }
    let rc = hlusolve(w, info2, u(nk + 2i64), score2)
    var r = 0.0f64
    i = 0i64
    while i < nk + 2i64 {
        r = r + score2[u(i)] * score3[u(i)]
        i += 1i64
    }
    ret 0.0f64 - r
}

fn thetaform(w: *W, m: *M, besti: i64) {
    let phi = w.phi7
    var i = 0i64
    while i < HL {
        phi[u(i)] = 0.0f64
        i += 1i64
    }
    var j = 0i64
    while j < m.nk - 2i64 {
        i = 0i64
        while i < m.nk + 1i64 {
            phi[u(i)] = phi[u(i)] + m.theta[u(j + 1i64)] * m.coef2[mi(j, i)]
            i += 1i64
        }
        j += 1i64
    }
    m.theta[u(m.nk + 3i64)] = m.theta[u(m.nk - 1i64)]
    m.theta[u(m.nk + 2i64)] = m.theta[0usize]
    m.theta[1usize] = phi[1usize]
    m.theta[0usize] = phi[0usize]
    m.theta[u(besti + 2i64)] = 0.0f64
    i = 0i64
    while i <= m.nk - 1i64 {
        if i < besti { m.theta[u(i + 2i64)] = phi[u(i + 2i64)] }
        if i > besti { m.theta[u(i + 2i64)] = phi[u(i + 1i64)] }
        i += 1i64
    }
}

// returns the location (index into the uncensored data) of the new knot, or -1
fn add(w: *W, m: *M, d: *D, nint: i64, mn: *M, mind: i64) -> i64 {
    var ipowdat: [3]i64 = zero
    var ipowvec: [3]i64 = zero
    var lu2: [2]i64 = zero
    let sorted = w.lsorted
    var nx = 0i64
    var i = 0i64
    while i < d.nd {
        if d.delta[u(i)] == 1 {
            sorted[u(nx)] = d.data[u(i)]
            nx += 1i64
        }
        i += 1i64
    }
    if m.nk != 2i64 {
        var j = 0usize
        while j < 3usize {
            ipowvec[j] = 0i64 - 1i64
            i = 0i64
            while i < nint {
                if m.basvec[u(i)] > m.knots[u(m.nk - 3i64) + j] {
                    w.powvec[u(i) * 3usize + j] = math.pow[f64](m.basvec[u(i)] - m.knots[u(m.nk - 3i64) + j], 3.0f64)
                } else {
                    w.powvec[u(i) * 3usize + j] = 0.0f64
                    ipowvec[j] = i
                }
                i += 1i64
            }
            j += 1usize
        }
        j = 0usize
        while j < 3usize {
            ipowdat[j] = 0i64 - 1i64
            i = 0i64
            while i < d.nd {
                if d.data[u(i)] > m.knots[u(m.nk - 3i64) + j] {
                    w.powdat[u(i) * 3usize + j] = math.pow[f64](d.data[u(i)] - m.knots[u(m.nk - 3i64) + j], 3.0f64)
                } else {
                    w.powdat[u(i) * 3usize + j] = 0.0f64
                    ipowdat[j] = i
                }
                i += 1i64
            }
            j += 1usize
        }
    }
    var bestrao = 0.0f64 - 1.0f64
    var besti = 0i64 - 1i64
    var bestloc = 0i64 - 1i64
    var loloc = 0i64
    var uploc = 0i64
    var nowloc1 = 0i64
    var ll = 0i64
    var uu = 0i64
    i = 0i64
    while i <= m.nk {
        if i == 0i64 && m.nk > 0i64 { nowloc1 = hindl(lu2[0usize..2usize], mind, sorted, nx, m.knots[0usize]) }
        if i == m.nk && m.nk > 0i64 { nowloc1 = hindr(lu2[0usize..2usize], mind, sorted, nx, m.knots[u(m.nk - 1i64)]) }
        if i == 0i64 && m.nk == 0i64 { nowloc1 = hindx(lu2[0usize..2usize], nx) }
        if i > 0i64 && i < m.nk { nowloc1 = hindm(lu2[0usize..2usize], mind, sorted, nx, m.knots[u(i - 1i64)], m.knots[u(i)]) }
        ll = lu2[0usize]
        uu = lu2[1usize]
        if nowloc1 >= 0i64 {
            let nowrao1 = hrao(w, m, d, sorted[u(nowloc1)], nint, ipowvec[0usize..3usize], ipowdat[0usize..3usize])
            if nowrao1 > bestrao {
                loloc = ll
                uploc = uu
                bestloc = nowloc1
                bestrao = nowrao1
                besti = i
            }
        }
        i += 1i64
    }
    if bestloc < 0i64 { ret 0i64 - 1i64 }
    var go = true
    while go {
        if sorted[u(uploc)] > sorted[u(loloc)] {
            let nowloc2 = hindyr(uploc, bestloc, sorted)
            var nowrao2 = bestrao
            if nowloc2 >= 0i64 { nowrao2 = hrao(w, m, d, sorted[u(nowloc2)], nint, ipowvec[0usize..3usize], ipowdat[0usize..3usize]) }
            let nl1 = hindyl(bestloc, loloc, sorted)
            var nowrao1 = bestrao
            if nl1 >= 0i64 { nowrao1 = hrao(w, m, d, sorted[u(nl1)], nint, ipowvec[0usize..3usize], ipowdat[0usize..3usize]) }
            if bestrao >= nowrao2 && bestrao >= nowrao1 {
                loloc = uploc
            } else {
                if nowrao1 > bestrao {
                    uploc = bestloc
                    bestloc = nl1
                    bestrao = nowrao1
                } else {
                    loloc = bestloc
                    bestloc = nowloc2
                    bestrao = nowrao2
                }
            }
        }
        go = sorted[u(uploc)] > sorted[u(loloc)]
    }
    if bestloc < 0i64 { ret bestloc }
    if besti == m.nk {
        m.knots[u(m.nk)] = sorted[u(bestloc)]
    } else {
        i = m.nk
        while i > besti {
            m.knots[u(i)] = m.knots[u(i - 1i64)]
            mn.iknots[u(i)] = mn.iknots[u(i - 1i64)]
            i = i - 1i64
        }
        m.knots[u(besti)] = sorted[u(bestloc)]
        mn.iknots[u(besti)] = 0
    }
    m.nk = m.nk + 1i64
    thetaform(w, m, besti)
    ret bestloc
}

// --- the main loop (heft() in heftall.c)

// returns nkstart: negative when the knots were unusable (-998, -999); zerr[1] > 0 on convergence trouble
fn heft(a: *mem.Arena, d: *D, nkstart0: i64, alpha: f64, m1: *M, iauto: i64, zerr: []i64, nkmax0: i64, mind: i64) -> (i64, err) {
    var nkstart = nkstart0
    var nkmax = nkmax0
    let nint1 = 20i64
    let nint2 = 50i64
    let nintx1 = 2i64
    let nintx2 = 6i64
    var nint = 0i64
    var nintx = 0i64
    var addi = 0i64
    var lold: [48]f64 = zero
    var i = 0usize
    while i < 48usize {
        lold[i] = 0.0f64 - math.pow[f64](10.0f64, 99.0f64)
        i += 1usize
    }
    let nkmax2 = nkmax
    let (mn0, e1) = makemodel(a)
    let (mo0, e2) = makemodel(a)
    if e1 != ok || e2 != ok { ret (0i64, mem.Full) }
    var modmin = mn0
    var modold = mo0
    modmin.aic = math.pow[f64](10.0f64, 99.0f64)
    let i00i = (HL + 15i64 + 2i64 * nintx2) * nint2
    let i00 = u(i00i)
    let (bv, e3) = zf(a, i00 + 2usize)
    let (mu, e4) = zf(a, i00 + 2usize)
    let (bm, e5) = zf(a, (i00 + 2usize) * HS)
    if e3 != ok || e4 != ok || e5 != ok { ret (0i64, mem.Full) }
    m1.basvec = bv
    m1.mult = mu
    m1.basmat = bm
    let (w0, e6) = makew(a, u(d.nd), i00)
    if e6 != ok { ret (0i64, e6) }
    var w = w0
    let ddd = w.ddd
    var ndd = 0i64
    var q = 0i64
    while q < d.nd {
        if d.delta[u(q)] == 1 {
            ddd[u(ndd)] = d.data[u(q)]
            ndd += 1i64
        }
        q += 1i64
    }
    var r = 0.0f64
    var ii = 0i64
    if d.cc < 0.0f64 - 90000.0f64 {
        r = 0.75f64 * f64(ndd) - 0.75f64
        ii = i64(math.floor[f64](r))
        r = r - f64(ii)
        d.cc = (1.0f64 - r) * ddd[u(ii)] + r * ddd[u(ii + 1i64)]
    }
    if iauto > 0i64 {
        // check and de-duplicate the user's knots
        var i1 = 0i64
        var jj = 1i64
        if m1.knots[0usize] <= 0.0f64 { jj = 0i64 - 999i64 }
        if jj > 0i64 {
            var t = 1i64
            while t < nkstart {
                if m1.knots[u(t)] > m1.knots[u(i1)] {
                    i1 += 1i64
                    m1.knots[u(i1)] = m1.knots[u(t)]
                } else {
                    if m1.knots[u(t)] < m1.knots[u(i1)] { jj = 0i64 - 999i64 }
                }
                t += 1i64
            }
        }
        if jj > 0i64 {
            nkstart = i1 + 1i64
            var t = 0i64
            while t < nkstart {
                m1.yknots[u(t)] = m1.knots[u(t)]
                t += 1i64
            }
            m1.nk = nkstart
        } else {
            nkstart = 0i64 - 999i64
        }
        if nkstart < 0i64 - 900i64 { ret (nkstart, ok) }
        if nkmax == nkstart {
            addi = 0i64
        } else {
            addi = 1i64
        }
    }
    if nkmax == 0i64 {
        r = 5.0f64 * math.pow[f64](f64(d.nd), 0.2f64)
        if r > 29.9f64 { r = 29.9f64 }
        if d.nd <= 60i64 { r = f64(d.nd) / 5.0f64 }
        if r < 1.5f64 { r = 1.5f64 }
        nkmax = i64(math.ceil[f64](r))
    }
    if iauto == 0i64 {
        r = 0.25f64 * f64(ndd) - 0.25f64
        ii = i64(math.floor[f64](r))
        r = r - f64(ii)
        m1.knots[0usize] = (1.0f64 - r) * ddd[u(ii)] + r * ddd[u(ii + 1i64)]
        if m1.tails[4usize] < 0.5f64 {
            m1.nk = 2i64
            nkstart = 2i64
            r = 0.75f64 * f64(ndd) - 0.75f64
            ii = i64(math.floor[f64](r))
            r = r - f64(ii)
            m1.knots[1usize] = (1.0f64 - r) * ddd[u(ii)] + r * ddd[u(ii + 1i64)]
            if m1.knots[1usize] == m1.knots[0usize] {
                ii = hlocation(1, ddd, ndd, m1.knots[0usize])
                if ii == ndd - 1i64 { ret (0i64 - 998i64, ok) }
                m1.knots[1usize] = ddd[u(ii + 1i64)]
            }
        } else {
            r = 0.5f64 * f64(ndd) - 0.5f64
            ii = i64(math.floor[f64](r))
            r = r - f64(ii)
            m1.knots[1usize] = (1.0f64 - r) * ddd[u(ii)] + r * ddd[u(ii + 1i64)]
            r = 0.75f64 * f64(ndd) - 0.75f64
            ii = i64(math.floor[f64](r))
            r = r - f64(ii)
            m1.knots[2usize] = (1.0f64 - r) * ddd[u(ii)] + r * ddd[u(ii + 1i64)]
            m1.nk = 3i64
            nkstart = 3i64
            if m1.knots[1usize] == m1.knots[0usize] {
                ii = hlocation(0, ddd, ndd, m1.knots[0usize])
                if ii == 0i64 { ret (0i64 - 998i64, ok) }
                m1.knots[0usize] = ddd[u(ii - 1i64)]
            }
            if m1.knots[1usize] == m1.knots[2usize] {
                ii = hlocation(1, ddd, ndd, m1.knots[1usize])
                if ii == ndd - 1i64 { ret (0i64 - 998i64, ok) }
                m1.knots[2usize] = ddd[u(ii + 1i64)]
            }
        }
        addi = 1i64
    }
    if addi == 1i64 {
        var go = true
        while go {
            getcoef(m1)
            nint = nint1
            nintx = nintx1
            if m1.nk < 0i64 - 5i64 {
                nint = nint2
                nintx = nintx2
            }
            intprep(&w, &nint, nintx, m1, d, 1)
            nstart(&w, m1, d, nkstart)
            hiter(&w, m1, d, zerr, nint, 1)
            if zerr[1usize] > 0 && m1.nk < 6i64 { ret (nkstart, ok) }
            if zerr[1usize] == 2 {
                nkstart = m1.nk - 1i64
                dubmodel(m1, &modold)
                addi = 2i64
            }
            dubmodel(&modold, m1)
            lold[u(m1.nk)] = m1.ll
            if nkmax != nkstart && nkmax2 == 0i64 {
                var t = 2i64
                while t < m1.nk - 2i64 {
                    if m1.ll - lold[u(t)] < (f64(m1.nk - t) - 2.0f64) / 2.0f64 + 0.5f64 {
                        nkmax = m1.nk
                        addi = 2i64
                    }
                    t += 1i64
                }
            }
            if addi == 1i64 && nkmax == m1.nk { addi = 2i64 }
            hetse(&w, m1, &modmin, alpha)
            if addi == 1i64 {
                let newk = add(&w, m1, d, nint, &modmin, mind)
                if newk < 0i64 {
                    addi = 2i64
                    nkmax = m1.nk
                }
            }
            go = addi == 1i64
        }
    }
    i = 0usize
    while i < usize(HL) {
        m1.yknots[i] = m1.knots[i]
        modmin.yknots[i] = m1.knots[i]
        i += 1usize
    }
    modmin.nk1 = nkmax
    m1.nk1 = nkmax
    var more = true
    while more {
        getcoef(m1)
        if addi == 2i64 {
            nint = nint2
            nintx = nintx2
        } else {
            var t = 0i64
            while t < d.nd {
                var j = 0i64
                while j <= m1.nk + 1i64 {
                    d.bd2[mi(t, j)] = d.bd1[mi(t, j)]
                    j += 1i64
                }
                t += 1i64
            }
        }
        intprep(&w, &nint, nintx, m1, d, addi)
        if addi == 0i64 { hstart2(&w, m1, d) }
        addi = 0i64
        hiter(&w, m1, d, zerr, nint, 0)
        if zerr[1usize] > 0 {
            zerr[1usize] = 0
            nstart(&w, m1, d, m1.nk)
            hiter(&w, m1, d, zerr, nint, 1)
        }
        tossit(&w, m1, &modmin, alpha)
        more = (m1.nk > 1i64 && m1.tails[4usize] < 0.5f64) || m1.nk > 2i64
    }
    dubmodel(m1, &modmin)
    i = 0usize
    while i < usize(HL) {
        m1.ad[i] = modmin.ad[i]
        i += 1usize
    }
    thetaswap(&w, m1)
    ret (nkstart, ok)
}

type HeftFit = struct {
    code: i64, nk: usize, knots: []f64, theta: []f64, logl: []f64, ad: []i64, logse0: f64, logse1: f64
}

// heft() on data sorted ascending with its delta (0/1). tails is R's c(left log?, leftlog, right log?, rightlog, no left linear?);
// knots_in non-empty means user knots (iauto 2); maxknots 0 means the default; alpha the penalty; cc the shift.
fn heft_fit(a: *mem.Arena, x: []const f64, delta: []const i64, alpha: f64, knots_in: []const f64, tails: []const f64, cc: f64, maxknots: i64, mindist: i64) -> (HeftFit, err) {
    var fit: HeftFit = zero
    let n = x.len
    let (m1, em) = makemodel(a)
    if em != ok { ret (fit, em) }
    var mod1 = m1
    var d: D = zero
    d.nd = i64(n)
    let (dd, e1) = zf(a, n + 4usize)
    let (dl, e2) = zi(a, n + 4usize, 1)
    let (b1, e3) = zf(a, (n + 2usize) * HS)
    let (b2, e4) = zf(a, (n + 2usize) * HS)
    let (zr, e5) = zi(a, 24usize, 0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (fit, mem.Full) }
    var i = 0usize
    while i < n {
        dd[i] = x[i]
        dl[i] = delta[i]
        i += 1usize
    }
    d.data = dd
    d.delta = dl
    d.cc = cc
    d.bd1 = b1
    d.bd2 = b2
    zr[0usize] = 1
    i = 0usize
    while i < 5usize {
        mod1.tails[i] = tails[i]
        i += 1usize
    }
    var iauto = 0i64
    var nks = 0i64
    if knots_in.len > 0usize {
        iauto = 2i64
        nks = i64(knots_in.len)
        i = 0usize
        while i < knots_in.len {
            mod1.knots[i] = knots_in[i]
            i += 1usize
        }
    }
    var pen = alpha
    if pen < 0.0f64 { pen = math.log[f64](f64(n)) }
    let (code, eh) = heft(a, &d, nks, pen, &mod1, iauto, zr, maxknots, mindist)
    if eh != ok { ret (fit, eh) }
    if code < 0i64 - 900i64 {
        fit.code = code
        ret (fit, ok)
    }
    if zr[1usize] > 0 {
        fit.code = 1000i64 + i64(zr[1usize])
        ret (fit, ok)
    }
    fit.nk = usize(mod1.nk1)
    fit.knots = mod1.yknots
    fit.theta = mod1.theta
    fit.logl = mod1.logl
    fit.ad = mod1.ad
    fit.logse0 = mod1.tse0
    fit.logse1 = mod1.tse1
    ret (fit, ok)
}

// the hazard hheft(q, fit) of a fitted model (the R evaluator)
fn hheft(f: *const HeftFit, shift: f64, q: f64) -> f64 {
    let nk = f.nk
    var y = f.theta[nk] + q * f.theta[nk + 1usize] + f.theta[nk + 2usize] * math.log[f64](q / (q + shift)) + f.theta[nk + 3usize] * math.log[f64](q + shift)
    var i = 0usize
    while i < nk {
        if f.theta[i] != 0.0f64 {
            let t = (math.abs[f64](q - f.knots[i]) + q - f.knots[i]) / 2.0f64
            y = y + f.theta[i] * (t * t * t)
        }
        i += 1usize
    }
    ret math.exp[f64](y)
}
