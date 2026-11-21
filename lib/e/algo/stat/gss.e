// R package gss (Gu): smoothing spline ANOVA by the exact RKPACK algorithms, ssanova0. A port of the package ratfor/Fortran:
// dstup (LINPACK dqrdc with pivoting of S = FR, F'y, F'QF), dsytr (Householder tridiagonalisation with the truncation rule), dcore/dgold/dtrev (the GCV,
// GML or unbiased risk score over log10(n lambda), minimised by the golden section search to 1e-7), dcoef (c and d), and for several kernels dmudr1/ddeev/dmcdc
// (the Newton iteration over log10 theta with the gradient and Hessian of the score), refitted at the end by dsidr0 on the sum of 10^theta Q.
//
// Matrices are column-major 1-based in the formulas below (cm(i, j, ld) is the 0-based offset), so each line can be read against the ratfor.
// The approximate-basis ssanova (sampled id.basis, sspreg1 / mspreg1w, with case weights) is the second half of this file; its standard errors are in gssse.e (regaux),
// gssanova1 for binomial, Poisson, Gamma and inverse Gaussian in gssglm1.e, gssnlm.e is nlm, gssden.e is ssden and gsshzd.e is sshzd.
// Not here: gssanova itself (the cross-validated Kullback-Leibler score), the nbinomial, polr, weibull, lognorm and loglogis families, the GML score of the approximate basis,
// random, partial and offset terms, and marginals other than cubic and thin-plate.

use e.math
use e.mem
use e.algo.linalg.decomp as dc
use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.gssnlm as nlm

error Rank
error Indefinite
error NoConverge
error NoDescent
error Dimension

type Ss0 = struct { c: []f64, d: []f64, theta: []f64, thfit: []f64, nlaht: f64, score: f64, varht: f64 }

fn cm(i: usize, j: usize, ld: usize) -> usize { ret (j - 1usize) * ld + (i - 1usize) }

fn absf(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn ddot(x: []const f64, ox: usize, ix: usize, y: []const f64, oy: usize, iy: usize, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[ox + i * ix] * y[oy + i * iy]
        i += 1usize
    }
    ret s
}

fn daxpy(n: usize, al: f64, x: []const f64, ox: usize, ix: usize, y: []f64, oy: usize, iy: usize) {
    if al == 0.0f64 { ret }
    var i = 0usize
    while i < n {
        y[oy + i * iy] += al * x[ox + i * ix]
        i += 1usize
    }
}

// 1-based index of the first element of largest magnitude
fn idamax(x: []const f64, ox: usize, inc: usize, n: usize) -> usize {
    var best = 1usize
    var bv = absf(x[ox])
    var i = 2usize
    while i <= n {
        let v = absf(x[ox + (i - 1usize) * inc])
        if v > bv {
            bv = v
            best = i
        }
        i += 1usize
    }
    ret best
}

fn zeros(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (w, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (w, e) }
    var i = 0usize
    while i < n + 1usize {
        w[i] = 0.0f64
        i += 1usize
    }
    ret (w, ok)
}

fn eps_half() -> f64 {
    var t = 1.0f64
    while 1.0f64 + t > 1.0f64 { t = t / 2.0f64 }
    ret t
}

// dsymv('l', n, alph, A, x, 0, y): y = alph A x from the lower triangle
fn dsymv_l(n: usize, alph: f64, am: []const f64, oa: usize, lda: usize, x: []const f64, ox: usize, y: []f64, oy: usize) {
    var i = 1usize
    while i <= n {
        y[oy + i - 1usize] = 0.0f64
        i += 1usize
    }
    var j = 1usize
    while j <= n {
        let t1 = alph * x[ox + j - 1usize]
        var t2 = 0.0f64
        y[oy + j - 1usize] += t1 * am[oa + cm(j, j, lda)]
        i = j + 1usize
        while i <= n {
            y[oy + i - 1usize] += t1 * am[oa + cm(i, j, lda)]
            t2 += am[oa + cm(i, j, lda)] * x[ox + i - 1usize]
            i += 1usize
        }
        y[oy + j - 1usize] += alph * t2
        j += 1usize
    }
}

// dsyr2('l', n, alph, x, y, A)
fn dsyr2_l(n: usize, alph: f64, x: []const f64, ox: usize, y: []const f64, oy: usize, am: []f64, oa: usize, lda: usize) {
    var j = 1usize
    while j <= n {
        let xj = x[ox + j - 1usize]
        let yj = y[oy + j - 1usize]
        if xj != 0.0f64 || yj != 0.0f64 {
            let t1 = alph * yj
            let t2 = alph * xj
            var i = j
            while i <= n {
                am[oa + cm(i, j, lda)] = am[oa + cm(i, j, lda)] + x[ox + i - 1usize] * t1 + y[oy + i - 1usize] * t2
                i += 1usize
            }
        }
        j += 1usize
    }
}

// LINPACK dqrdc with job = 1 and every jpvt = 0 on entry: pivoting among all columns by the largest remaining norm. jpvt is 1-based on exit.
fn dqrdc(x: []f64, n: usize, p: usize, qraux: []f64, jpvt: []usize, work: []f64) {
    var j = 1usize
    while j <= p {
        jpvt[j - 1usize] = j
        qraux[j - 1usize] = dc.norm2(x, (j - 1usize) * n, n)
        work[j - 1usize] = qraux[j - 1usize]
        j += 1usize
    }
    var lup = n
    if p < lup { lup = p }
    var l = 1usize
    while l <= lup {
        if l < p {
            var maxnrm = 0.0f64
            var maxj = l
            j = l
            while j <= p {
                if qraux[j - 1usize] > maxnrm {
                    maxnrm = qraux[j - 1usize]
                    maxj = j
                }
                j += 1usize
            }
            if maxj != l {
                var r = 1usize
                while r <= n {
                    let tmp = x[cm(r, l, n)]
                    x[cm(r, l, n)] = x[cm(r, maxj, n)]
                    x[cm(r, maxj, n)] = tmp
                    r += 1usize
                }
                qraux[maxj - 1usize] = qraux[l - 1usize]
                work[maxj - 1usize] = work[l - 1usize]
                let jp = jpvt[maxj - 1usize]
                jpvt[maxj - 1usize] = jpvt[l - 1usize]
                jpvt[l - 1usize] = jp
            }
        }
        qraux[l - 1usize] = 0.0f64
        if l != n {
            var nrmxl = dc.norm2(x, cm(l, l, n), n - l + 1usize)
            if nrmxl != 0.0f64 {
                if x[cm(l, l, n)] != 0.0f64 {
                    if x[cm(l, l, n)] < 0.0f64 { nrmxl = 0.0f64 - absf(nrmxl) } else { nrmxl = absf(nrmxl) }
                }
                var r = l
                while r <= n {
                    x[cm(r, l, n)] = x[cm(r, l, n)] * (1.0f64 / nrmxl)
                    r += 1usize
                }
                x[cm(l, l, n)] = 1.0f64 + x[cm(l, l, n)]
                j = l + 1usize
                while j <= p {
                    let t = 0.0f64 - ddot(x, cm(l, l, n), 1usize, x, cm(l, j, n), 1usize, n - l + 1usize) / x[cm(l, l, n)]
                    daxpy(n - l + 1usize, t, x, cm(l, l, n), 1usize, x, cm(l, j, n), 1usize)
                    if qraux[j - 1usize] != 0.0f64 {
                        var tt = 1.0f64 - (absf(x[cm(l, j, n)]) / qraux[j - 1usize]) * (absf(x[cm(l, j, n)]) / qraux[j - 1usize])
                        if tt < 0.0f64 { tt = 0.0f64 }
                        let t3 = tt
                        let ratio = qraux[j - 1usize] / work[j - 1usize]
                        tt = 1.0f64 + 0.05f64 * tt * ratio * ratio
                        if tt != 1.0f64 {
                            qraux[j - 1usize] = qraux[j - 1usize] * math.sqrt[f64](t3)
                        } else {
                            qraux[j - 1usize] = dc.norm2(x, cm(l + 1usize, j, n), n - l)
                            work[j - 1usize] = qraux[j - 1usize]
                        }
                    }
                    j += 1usize
                }
                qraux[l - 1usize] = x[cm(l, l, n)]
                x[cm(l, l, n)] = 0.0f64 - nrmxl
            }
        }
        l += 1usize
    }
}

// one Householder reflection j of a LINPACK factor applied to y(1..n) starting at offset oy; qj is the stored v(1)
fn refl(x: []const f64, ox: usize, ldx: usize, n: usize, j: usize, qj: f64, y: []f64, oy: usize) {
    var dot = qj * y[oy + j - 1usize]
    var i = j + 1usize
    while i <= n {
        dot += x[ox + cm(i, j, ldx)] * y[oy + i - 1usize]
        i += 1usize
    }
    let t = 0.0f64 - dot / qj
    y[oy + j - 1usize] += t * qj
    i = j + 1usize
    while i <= n {
        y[oy + i - 1usize] += t * x[ox + cm(i, j, ldx)]
        i += 1usize
    }
}

// dqrsl job 01000: y becomes Q'y for the factor (x, qraux) with n rows and k reflections
fn qty(x: []const f64, ox: usize, ldx: usize, n: usize, k: usize, qraux: []const f64, oq: usize, y: []f64, oy: usize) {
    var ju = k
    if n - 1usize < ju { ju = n - 1usize }
    var j = 1usize
    while j <= ju {
        if qraux[oq + j - 1usize] != 0.0f64 { refl(x, ox, ldx, n, j, qraux[oq + j - 1usize], y, oy) }
        j += 1usize
    }
}

// dqrsl job 10000: y becomes Qy
fn qy(x: []const f64, ox: usize, ldx: usize, n: usize, k: usize, qraux: []const f64, oq: usize, y: []f64, oy: usize) {
    var ju = k
    if n - 1usize < ju { ju = n - 1usize }
    var j = ju
    while j >= 1usize {
        if qraux[oq + j - 1usize] != 0.0f64 { refl(x, ox, ldx, n, j, qraux[oq + j - 1usize], y, oy) }
        j -= 1usize
    }
}

// dqrslm job 0: the symmetric matrix A (lower triangle, n by n) becomes H_k ... H_1 A H_1 ... H_k for the reflections of the factor (x, qraux)
fn dqrslm(x: []const f64, ox: usize, ldx: usize, n: usize, k: usize, qraux: []const f64, oq: usize, am: []f64, oa: usize, lda: usize, v: []f64, w: []f64) {
    var j = 1usize
    while j <= k {
        let qj = qraux[oq + j - 1usize]
        if qj != 0.0f64 {
            let m = n - j + 1usize
            v[0usize] = qj
            var i = 2usize
            while i <= m {
                v[i - 1usize] = x[ox + cm(j + i - 1usize, j, ldx)]
                i += 1usize
            }
            i = 1usize
            while i < j {
                let alph = 0.0f64 - ddot(v, 0usize, 1usize, am, oa + cm(j, i, lda), 1usize, m) / qj
                daxpy(m, alph, v, 0usize, 1usize, am, oa + cm(j, i, lda), 1usize)
                i += 1usize
            }
            dsymv_l(m, 1.0f64 / qj, am, oa + cm(j, j, lda), lda, v, 0usize, w, 0usize)
            let al2 = 0.0f64 - ddot(w, 0usize, 1usize, v, 0usize, 1usize, m) / 2.0f64 / qj
            daxpy(m, al2, v, 0usize, 1usize, w, 0usize, 1usize)
            dsyr2_l(m, 0.0f64 - 1.0f64, v, 0usize, w, 0usize, am, oa + cm(j, j, lda), lda)
        }
        j += 1usize
    }
}

// dsytr on the n by n block at offset ox of x (lower triangle): tridiagonal in the diagonal and the superdiagonal, Householder vectors below
fn dsytr(x: []f64, ox: usize, ldx: usize, n: usize, tol: f64, work: []f64) -> err {
    if ldx < n || n <= 2usize { ret Dimension }
    var nrmtot = ddot(x, ox, ldx + 1usize, x, ox, ldx + 1usize, n)
    var j = 1usize
    while j < n {
        nrmtot += 2.0f64 * ddot(x, ox + cm(j + 1usize, j, ldx), 1usize, x, ox + cm(j + 1usize, j, ldx), 1usize, n - j)
        j += 1usize
    }
    var toltot = eps_half()
    toltot = 4.0f64 * toltot * toltot
    if toltot < tol { toltot = tol }
    toltot = toltot * nrmtot
    var dn = f64(n)
    let toluni = toltot * 6.0f64 / dn / (dn - 1.0f64) / (2.0f64 * dn - 1.0f64)
    var tolcum = 0.0f64
    j = 1usize
    while j < n - 1usize {
        nrmtot = nrmtot - x[ox + cm(j, j, ldx)] * x[ox + cm(j, j, ldx)]
        let nrmxj = ddot(x, ox + cm(j + 1usize, j, ldx), 1usize, x, ox + cm(j + 1usize, j, ldx), 1usize, n - j)
        dn = f64(n - j)
        tolcum = tolcum + toluni * dn * dn
        if 2.0f64 * nrmxj <= tolcum {
            x[ox + cm(j, j + 1usize, ldx)] = 0.0f64
            var i = j + 1usize
            while i <= n {
                x[ox + cm(i, j, ldx)] = 0.0f64
                i += 1usize
            }
            tolcum = tolcum - 2.0f64 * nrmxj
            toltot = toltot - 2.0f64 * nrmxj
            j += 1usize
            continue
        }
        if x[ox + cm(j + 1usize, j, ldx)] < 0.0f64 {
            x[ox + cm(j, j + 1usize, ldx)] = math.sqrt[f64](nrmxj)
        } else {
            x[ox + cm(j, j + 1usize, ldx)] = 0.0f64 - math.sqrt[f64](nrmxj)
        }
        nrmtot = nrmtot - 2.0f64 * nrmxj
        let sc = (0.0f64 - 1.0f64) / x[ox + cm(j, j + 1usize, ldx)]
        var i = j + 1usize
        while i <= n {
            x[ox + cm(i, j, ldx)] = x[ox + cm(i, j, ldx)] * sc
            i += 1usize
        }
        x[ox + cm(j + 1usize, j, ldx)] = 1.0f64 + x[ox + cm(j + 1usize, j, ldx)]
        let v1 = x[ox + cm(j + 1usize, j, ldx)]
        dsymv_l(n - j, 1.0f64 / v1, x, ox + cm(j + 1usize, j + 1usize, ldx), ldx, x, ox + cm(j + 1usize, j, ldx), work, j)
        let alph = 0.0f64 - ddot(work, j, 1usize, x, ox + cm(j + 1usize, j, ldx), 1usize, n - j) / 2.0f64 / v1
        daxpy(n - j, alph, x, ox + cm(j + 1usize, j, ldx), 1usize, work, j, 1usize)
        dsyr2_l(n - j, 0.0f64 - 1.0f64, x, ox + cm(j + 1usize, j, ldx), work, j, x, ox + cm(j + 1usize, j + 1usize, ldx), ldx)
        j += 1usize
    }
    x[ox + cm(n - 1usize, n, ldx)] = x[ox + cm(n, n - 1usize, ldx)]
    ret ok
}

// dpbfa and dpbsl for the packed (2, n) tridiagonal t(1, j) = (j - 1, j) entry, t(2, j) = (j, j) entry; the factor overwrites t
fn dpbfa1(t: []f64, n: usize) -> usize {
    var j = 1usize
    while j <= n {
        var s = 0.0f64
        if j > 1usize {
            let l = t[cm(1usize, j, 2usize)] / t[cm(2usize, j - 1usize, 2usize)]
            t[cm(1usize, j, 2usize)] = l
            s = l * l
        }
        s = t[cm(2usize, j, 2usize)] - s
        if s <= 0.0f64 { ret j }
        t[cm(2usize, j, 2usize)] = math.sqrt[f64](s)
        j += 1usize
    }
    ret 0usize
}

fn dpbsl1(t: []const f64, n: usize, b: []f64, ob: usize) {
    var k = 1usize
    while k <= n {
        var s = 0.0f64
        if k > 1usize { s = t[cm(1usize, k, 2usize)] * b[ob + k - 2usize] }
        b[ob + k - 1usize] = (b[ob + k - 1usize] - s) / t[cm(2usize, k, 2usize)]
        k += 1usize
    }
    var kb = 1usize
    while kb <= n {
        let k2 = n + 1usize - kb
        b[ob + k2 - 1usize] = b[ob + k2 - 1usize] / t[cm(2usize, k2, 2usize)]
        if k2 > 1usize { b[ob + k2 - 2usize] += (0.0f64 - b[ob + k2 - 1usize]) * t[cm(1usize, k2, 2usize)] }
        kb += 1usize
    }
}

fn log10f(x: f64) -> f64 { ret math.log10[f64](x) }
fn pow10(x: f64) -> f64 { ret math.pow[f64](10.0f64, x) }

// dtrev: the score of 'v' (1), 'm' (2) or 'u' (3) from t = the tridiagonal (diag + n lambda) and z; returns (score, varht, info)
type Rev = struct { score: f64, varht: f64, info: usize }

fn dtrev(vmu: usize, t: []f64, n: usize, z: []const f64, oz: usize, wk: []f64, varht_in: f64) -> Rev {
    let la = t[0usize]
    var asum = 0.0f64
    var j = 1usize
    while j <= n {
        asum += absf(t[cm(2usize, j, 2usize)])
        j += 1usize
    }
    let alph = f64(n) / asum
    j = 1usize
    while j <= n {
        t[cm(2usize, j, 2usize)] = t[cm(2usize, j, 2usize)] * alph
        if j >= 2usize { t[cm(1usize, j, 2usize)] = t[cm(1usize, j, 2usize)] * alph }
        j += 1usize
    }
    let info = dpbfa1(t, n)
    if info != 0usize { ret Rev { score: 0.0f64, varht: varht_in, info: info } }
    j = 1usize
    while j <= n {
        wk[j - 1usize] = z[oz + j - 1usize]
        j += 1usize
    }
    dpbsl1(t, n, wk, 0usize)
    var score = 0.0f64
    var varht = varht_in
    let dn = f64(n)
    if vmu == 1usize || vmu == 3usize {
        var tmp = 1.0f64 / t[cm(2usize, n, 2usize)] / t[cm(2usize, n, 2usize)]
        var deno = tmp
        var jj = n - 1usize
        while jj >= 1usize {
            tmp = (1.0f64 + t[cm(1usize, jj + 1usize, 2usize)] * t[cm(1usize, jj + 1usize, 2usize)] * tmp) / t[cm(2usize, jj, 2usize)] / t[cm(2usize, jj, 2usize)]
            deno = deno + tmp
            jj -= 1usize
        }
        let nume = ddot(wk, 0usize, 1usize, wk, 0usize, 1usize, n) / dn
        deno = deno / dn
        if vmu == 1usize {
            varht = alph * la * nume / deno
            score = nume / deno / deno
        } else {
            score = alph * alph * la * la * nume - 2.0f64 * varht * alph * la * deno
        }
    }
    if vmu == 2usize {
        var deno = math.log[f64](t[cm(2usize, n, 2usize)])
        var jj = n - 1usize
        while jj >= 1usize {
            deno = deno + math.log[f64](t[cm(2usize, jj, 2usize)])
            jj -= 1usize
        }
        let nume = ddot(z, oz, 1usize, wk, 0usize, 1usize, n) / dn
        varht = alph * la * nume
        score = nume * math.exp[f64](2.0f64 * deno / dn)
    }
    ret Rev { score: score, varht: varht, info: 0usize }
}

// the packed tridiagonal of the corner block (offset oq, ld ldq, size n) plus 10^m on the diagonal
fn fill_t(tw: []f64, qm: []const f64, oq: usize, ldq: usize, n: usize, m: f64) {
    let lam = pow10(m)
    var j = 1usize
    while j <= n {
        tw[cm(2usize, j, 2usize)] = lam + qm[oq + cm(j, j, ldq)]
        if j >= 2usize { tw[cm(1usize, j, 2usize)] = qm[oq + cm(j - 1usize, j, ldq)] }
        j += 1usize
    }
    tw[0usize] = lam
}

type Gold = struct { nlaht: f64, score: f64, varht: f64, info: usize }

fn dgold(vmu: usize, qm: []const f64, oq: usize, ldq: usize, n: usize, z: []const f64, oz: usize, lo: f64, up: f64, varht_in: f64, tw: []f64, wk: []f64) -> Gold {
    var g: Gold = zero
    var low = lo
    var upp = up
    var varht = varht_in
    let ratio = (math.sqrt[f64](5.0f64) - 1.0f64) / 2.0f64
    if upp < low {
        let t = low
        low = upp
        upp = t
    }
    var mlo = upp - ratio * (upp - low)
    fill_t(tw, qm, oq, ldq, n, mlo)
    var tmpl = 0.0f64
    var tmpu = 0.0f64
    var info = 0usize
    var r = dtrev(vmu, tw, n, z, oz, wk, varht)
    tmpl = r.score
    varht = r.varht
    info = r.info
    if info != 0usize {
        g.info = info
        ret g
    }
    var mup = low + ratio * (upp - low)
    fill_t(tw, qm, oq, ldq, n, mup)
    r = dtrev(vmu, tw, n, z, oz, wk, varht)
    tmpu = r.score
    varht = r.varht
    info = r.info
    if info != 0usize {
        g.info = info
        ret g
    }
    while mup - mlo >= 0.0000001f64 {
        if tmpl < tmpu {
            upp = mup
            mup = mlo
            tmpu = tmpl
            mlo = upp - ratio * (upp - low)
            fill_t(tw, qm, oq, ldq, n, mlo)
            r = dtrev(vmu, tw, n, z, oz, wk, varht)
            tmpl = r.score
        } else {
            low = mlo
            mlo = mup
            tmpl = tmpu
            mup = low + ratio * (upp - low)
            fill_t(tw, qm, oq, ldq, n, mup)
            r = dtrev(vmu, tw, n, z, oz, wk, varht)
            tmpu = r.score
        }
        varht = r.varht
        info = r.info
        if info != 0usize {
            g.info = info
            ret g
        }
    }
    let nl = (mup + mlo) / 2.0f64
    fill_t(tw, qm, oq, ldq, n, nl)
    r = dtrev(vmu, tw, n, z, oz, wk, varht)
    g.nlaht = nl
    g.score = r.score
    g.varht = r.varht
    g.info = r.info
    ret g
}

type Core = struct { nlaht: f64, score: f64, varht: f64, lo: f64, up: f64 }

// dcore with job 0 (automatic range) or -1 (the range lo..up given): tridiagonalises the corner of q in place and transforms z
fn dcore(a: *mem.Arena, vmu: usize, qm: []f64, ldq: usize, nobs: usize, n0: usize, z: []f64, auto: bool, lo: f64, up: f64, varht_in: f64, out: *Core) -> err {
    let n = nobs - n0
    let (work, we) = zeros(a, nobs + 2usize)
    let (tw, te) = zeros(a, 2usize * n + 2usize)
    let (qa, qe) = zeros(a, nobs + 2usize)
    if we != ok { ret we }
    if te != ok { ret te }
    if qe != ok { ret qe }
    let corner = cm(n0 + 1usize, n0 + 1usize, ldq)
    let se = dsytr(qm, corner, ldq, n, 0.0f64, work)
    if se != ok { ret se }
    // U'z2: the reflections live in q(n0 + 2, n0 + 1), their v(1) on its diagonal
    let sub = cm(n0 + 2usize, n0 + 1usize, ldq)
    var j = 1usize
    while j <= n - 2usize {
        qa[j - 1usize] = qm[sub + (j - 1usize) * (ldq + 1usize)]
        j += 1usize
    }
    qty(qm, sub, ldq, n - 1usize, n - 2usize, qa, 0usize, z, n0 + 1usize)
    var low = lo
    var upp = up
    if auto {
        let mchpr = 2.0f64 * eps_half()
        var asum = 0.0f64
        j = 1usize
        while j <= n {
            asum += absf(qm[corner + cm(j, j, ldq)])
            j += 1usize
        }
        var hi = asum * 100.0f64
        if mchpr > hi { hi = mchpr }
        upp = log10f(hi)
        low = log10f(hi * mchpr)
    }
    let g = dgold(vmu, qm, corner, ldq, n, z, n0, low, upp, varht_in, tw, work)
    if g.info != 0usize { ret Indefinite }
    out.nlaht = g.nlaht
    out.varht = g.varht
    out.lo = low
    out.up = upp
    var sc = g.score
    if vmu == 1usize { sc = sc * f64(nobs) / f64(n) }
    if vmu == 2usize { sc = sc * f64(n) / f64(nobs) }
    if vmu == 3usize { sc = sc * f64(n) / f64(nobs) + 2.0f64 * g.varht }
    out.score = sc
    ret ok
}

// dtrsl job 01: the upper triangular T (n by n at offset ot, ld ldt) solves T x = b in place
fn dtrsl_up(t: []const f64, ot: usize, ldt: usize, n: usize, b: []f64, ob: usize) {
    b[ob + n - 1usize] = b[ob + n - 1usize] / t[ot + cm(n, n, ldt)]
    var jj = 2usize
    while jj <= n {
        let j = n - jj + 1usize
        let temp = 0.0f64 - b[ob + j]
        daxpy(j, temp, t, ot + cm(1usize, j + 1usize, ldt), 1usize, b, ob, 1usize)
        b[ob + j - 1usize] = b[ob + j - 1usize] / t[ot + cm(j, j, ldt)]
        jj += 1usize
    }
}

// dprmut job 1: the entries in pivoted order go back to their columns, x[jpvt(j)] = old x[j]
fn unpermute(x: []f64, ox: usize, n: usize, jpvt: []const usize, tmp: []f64) {
    var j = 1usize
    while j <= n {
        tmp[j - 1usize] = x[ox + j - 1usize]
        j += 1usize
    }
    j = 1usize
    while j <= n {
        x[ox + jpvt[j - 1usize] - 1usize] = tmp[j - 1usize]
        j += 1usize
    }
}

// dcoef: c (nobs) and d (n0) from the transformed z, the tridiagonalised q and nlaht
fn dcoef(a: *mem.Arena, s: []const f64, lds: usize, nobs: usize, n0: usize, qraux: []const f64, jpvt: []const usize, z: []f64, qm: []const f64, ldq: usize, nlaht: f64, c: []f64, d: []f64) -> err {
    let n = nobs - n0
    let (tw, te) = zeros(a, 2usize * n + 2usize)
    let (qa, qe) = zeros(a, nobs + 2usize)
    let (tmp, me) = zeros(a, nobs + 2usize)
    if te != ok { ret te }
    if qe != ok { ret qe }
    if me != ok { ret me }
    fill_t(tw, qm, cm(n0 + 1usize, n0 + 1usize, ldq), ldq, n, nlaht)
    if dpbfa1(tw, n) != 0usize { ret Indefinite }
    dpbsl1(tw, n, z, n0)
    let sub = cm(n0 + 2usize, n0 + 1usize, ldq)
    var j = 1usize
    while j <= n - 2usize {
        qa[j - 1usize] = qm[sub + (j - 1usize) * (ldq + 1usize)]
        j += 1usize
    }
    qy(qm, sub, ldq, n - 1usize, n - 2usize, qa, 0usize, z, n0 + 1usize)
    j = 1usize
    while j <= n0 {
        c[j - 1usize] = 0.0f64
        j += 1usize
    }
    j = 1usize
    while j <= n {
        c[n0 + j - 1usize] = z[n0 + j - 1usize]
        j += 1usize
    }
    qy(s, 0usize, lds, nobs, n0, qraux, 0usize, c, 0usize)
    j = 1usize
    while j <= n0 {
        d[j - 1usize] = z[j - 1usize] - ddot(z, n0, 1usize, qm, cm(n0 + 1usize, j, ldq), 1usize, n)
        j += 1usize
    }
    dtrsl_up(s, 0usize, lds, n0, d, 0usize)
    unpermute(d, 0usize, n0, jpvt, tmp)
    ret ok
}

fn method_code(m: usize) -> bool { ret m >= 1usize && m <= 3usize }

// sspreg0: one kernel q (n by n, symmetric) -- ssanova0 with a single penalised term. method 1 = "v", 2 = "m", 3 = "u" (varht known)
fn sspreg0(a: *mem.Arena, s: []const f64, q: []const f64, y: []const f64, n: usize, n0: usize, method: usize, varht: f64, out: *Ss0) -> err {
    ret sspreg0j(a, s, q, y, n, n0, method, varht, true, 0.0f64, 0.0f64, out)
}

// dsidr0 with job 0 (auto) or -1 (the search range lo..up in log10 n lambda)
fn sspreg0j(a: *mem.Arena, s: []const f64, q: []const f64, y: []const f64, n: usize, n0: usize, method: usize, varht: f64, auto: bool, lo: f64, up: f64, out: *Ss0) -> err {
    if !method_code(method) { ret Dimension }
    if n0 < 1usize || n0 >= n { ret Dimension }
    let (sw, e1) = zeros(a, n * n0)
    let (qraux, e2) = zeros(a, n0)
    let (work, e3) = zeros(a, n + 2usize)
    let (qw, e4) = zeros(a, n * n)
    let (z, e5) = zeros(a, n)
    let (c, e6) = zeros(a, n)
    let (d, e7) = zeros(a, n0)
    let (th, e8) = zeros(a, 1usize)
    let (jp, e9) = mem.alloc[usize](a, n0 + 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    var i = 0usize
    while i < n * n0 {
        sw[i] = s[i]
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        qw[i] = q[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        z[i] = y[i]
        i += 1usize
    }
    dqrdc(sw, n, n0, qraux, jp, work)
    i = 1usize
    while i <= n0 {
        if sw[cm(i, i, n)] == 0.0f64 { ret Rank }
        i += 1usize
    }
    qty(sw, 0usize, n, n, n0, qraux, 0usize, z, 0usize)
    let (qs, e10) = zeros(a, n)
    if e10 != ok { ret e10 }
    dqrslm(sw, 0usize, n, n, n0, qraux, 0usize, qw, 0usize, n, qs, work)
    var cr: Core = zero
    let ce = dcore(a, method, qw, n, n, n0, z, auto, lo, up, varht, &cr)
    if ce != ok { ret ce }
    let de = dcoef(a, sw, n, n, n0, qraux, jp, z, qw, n, cr.nlaht, c, d)
    if de != ok { ret de }
    out.c = c
    out.d = d
    th[0usize] = 0.0f64
    out.theta = th[0usize..1usize]
    out.thfit = th[0usize..1usize]
    out.nlaht = cr.nlaht
    out.score = cr.score
    out.varht = cr.varht
    ret ok
}

// dmcdc: the modified Cholesky factor of the symmetric matrix in the upper triangle of h (p by p, ld ldh), pivoted; jpvt gets the permutation (1-based)
fn dmcdc(h: []f64, ldh: usize, p: usize, jpvt: []usize) {
    var tmp = eps_half()
    var jmax = idamax(h, 0usize, ldh + 1usize, p)
    var beta = 2.0f64 * tmp
    if absf(h[cm(jmax, jmax, ldh)]) > beta { beta = absf(h[cm(jmax, jmax, ldh)]) }
    tmp = math.sqrt[f64](f64(p * p) - 1.0f64)
    if tmp < 1.0f64 { tmp = 1.0f64 }
    var j = 2usize
    while j <= p {
        jmax = idamax(h, cm(1usize, j, ldh), 1usize, j - 1usize)
        let v = absf(h[cm(jmax, j, ldh)]) / tmp
        if v > beta { beta = v }
        j += 1usize
    }
    var asum = 0.0f64
    j = 1usize
    while j <= p {
        asum += absf(h[cm(j, j, ldh)])
        j += 1usize
    }
    var delta = asum / f64(p) * 0.0000001f64
    if delta < 0.0000000001f64 { delta = 0.0000000001f64 }
    j = 1usize
    while j <= p {
        jpvt[j - 1usize] = j
        j += 1usize
    }
    j = 1usize
    while j <= p {
        jmax = idamax(h, cm(j, j, ldh), ldh + 1usize, p - j + 1usize) + j - 1usize
        if jmax != j {
            var i = 1usize
            while i < j {
                let t = h[cm(i, j, ldh)]
                h[cm(i, j, ldh)] = h[cm(i, jmax, ldh)]
                h[cm(i, jmax, ldh)] = t
                i += 1usize
            }
            i = 1usize
            while i + j + 1usize <= jmax {
                // row j, columns j + i .. against column jmax, rows j + i
                let t = h[cm(j, j + i, ldh)]
                h[cm(j, j + i, ldh)] = h[cm(j + i, jmax, ldh)]
                h[cm(j + i, jmax, ldh)] = t
                i += 1usize
            }
            i = jmax + 1usize
            while i <= p {
                let t = h[cm(j, i, ldh)]
                h[cm(j, i, ldh)] = h[cm(jmax, i, ldh)]
                h[cm(jmax, i, ldh)] = t
                i += 1usize
            }
            let t2 = h[cm(j, j, ldh)]
            h[cm(j, j, ldh)] = h[cm(jmax, jmax, ldh)]
            h[cm(jmax, jmax, ldh)] = t2
            let jt = jpvt[j - 1usize]
            jpvt[j - 1usize] = jpvt[jmax - 1usize]
            jpvt[jmax - 1usize] = jt
        }
        var i = 1usize
        while i < j {
            h[cm(i, j, ldh)] = h[cm(i, j, ldh)] / h[cm(i, i, ldh)]
            i += 1usize
        }
        i = j + 1usize
        while i <= p {
            h[cm(j, i, ldh)] = h[cm(j, i, ldh)] - ddot(h, cm(1usize, j, ldh), 1usize, h, cm(1usize, i, ldh), 1usize, j - 1usize)
            i += 1usize
        }
        var theta = 0.0f64
        if j != p {
            let jm = idamax(h, cm(j, j + 1usize, ldh), ldh, p - j) + j
            theta = absf(h[cm(j, jm, ldh)])
        }
        tmp = delta
        if absf(h[cm(j, j, ldh)]) > tmp { tmp = absf(h[cm(j, j, ldh)]) }
        if theta * theta / beta > tmp { tmp = theta * theta / beta }
        h[cm(j, j, ldh)] = tmp
        i = j + 1usize
        while i <= p {
            h[cm(i, i, ldh)] = h[cm(i, i, ldh)] - h[cm(j, i, ldh)] * h[cm(j, i, ldh)] / h[cm(j, j, ldh)]
            i += 1usize
        }
        j += 1usize
    }
    j = 1usize
    while j <= p {
        h[cm(j, j, ldh)] = math.sqrt[f64](h[cm(j, j, ldh)])
        var i = j + 1usize
        while i <= p {
            h[cm(j, i, ldh)] = h[cm(j, i, ldh)] * h[cm(j, j, ldh)]
            i += 1usize
        }
        j += 1usize
    }
}

// dposl for the factor of dmcdc (upper R, R'R x = b)
fn dposl(h: []const f64, ldh: usize, p: usize, b: []f64) {
    var k = 1usize
    while k <= p {
        let t = ddot(h, cm(1usize, k, ldh), 1usize, b, 0usize, 1usize, k - 1usize)
        b[k - 1usize] = (b[k - 1usize] - t) / h[cm(k, k, ldh)]
        k += 1usize
    }
    var kb = 1usize
    while kb <= p {
        let k2 = p + 1usize - kb
        b[k2 - 1usize] = b[k2 - 1usize] / h[cm(k2, k2, ldh)]
        daxpy(k2 - 1usize, 0.0f64 - b[k2 - 1usize], h, cm(1usize, k2, ldh), 1usize, b, 0usize, 1usize)
        kb += 1usize
    }
}

// y = A x (trans false) or A' x (trans true) for the n by n block of kw at offset ok0
fn dgemv_sq(trans: bool, n: usize, kw: []const f64, ok0: usize, x: []const f64, y: []f64) {
    var i = 0usize
    while i < n {
        y[i] = 0.0f64
        i += 1usize
    }
    var j = 1usize
    if !trans {
        while j <= n {
            let t = x[j - 1usize]
            i = 1usize
            while i <= n {
                y[i - 1usize] += t * kw[ok0 + cm(i, j, n)]
                i += 1usize
            }
            j += 1usize
        }
    } else {
        while j <= n {
            var t = 0.0f64
            i = 1usize
            while i <= n {
                t += kw[ok0 + cm(i, j, n)] * x[i - 1usize]
                i += 1usize
            }
            y[j - 1usize] = t
            j += 1usize
        }
    }
}

// ddeev: gradient gra and Hessian hes (lower triangle, nq by nq) of the score over log10 theta. q holds the transformed kernels (nq of nobs by nobs), u the
// reflections of the tridiagonalisation (qwk at its corner), t the packed tridiagonal without n lambda (destroyed), x = U'z2.
fn ddeev(a: *mem.Arena, vmu: usize, nobs: usize, n0: usize, nq: usize, qs: []const f64, uq: []const f64, uaux: []const f64, t: []f64, x: []const f64, theta: []const f64,
         nlaht: f64, score: f64, varht: f64, hes: []f64, gra: []f64) -> err {
    let n = nobs - n0
    var i = 1usize
    while i <= nq * nq {
        hes[i - 1usize] = 0.0f64
        i += 1usize
    }
    i = 1usize
    while i <= nq {
        gra[i - 1usize] = 0.0f64
        i += 1usize
    }
    let (kwk, e1) = zeros(a, n * n * nq)
    let (hwk1, e2) = zeros(a, nq * nq)
    let (hwk2, e3) = zeros(a, nq * nq)
    let (gwk1, e4) = zeros(a, nq)
    let (gwk2, e5) = zeros(a, nq)
    let (work1, e6) = zeros(a, n + 2usize)
    let (work2, e7) = zeros(a, n + 2usize)
    let (work3, e8) = zeros(a, n + 2usize)
    let (vv, e9) = zeros(a, n + 2usize)
    let (ww, e10) = zeros(a, n + 2usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    let ucorner = cm(n0 + 2usize, n0 + 1usize, nobs)
    // K_i = U'(theta_i Q_i)U for i >= 2
    i = 2usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            let kb = (i - 1usize) * n * n
            let qb = (i - 1usize) * nobs * nobs + cm(n0 + 1usize, n0 + 1usize, nobs)
            var j = 1usize
            while j <= n {
                var r = j
                while r <= n {
                    kwk[kb + cm(r, j, n)] = qs[qb + cm(r, j, nobs)] * pow10(theta[i - 1usize])
                    r += 1usize
                }
                j += 1usize
            }
            dqrslm(uq, ucorner, nobs, n - 1usize, n - 2usize, uaux, 0usize, kwk, kb + cm(2usize, 2usize, n), n, vv, ww)
            qty(uq, ucorner, nobs, n - 1usize, n - 2usize, uaux, 0usize, kwk, kb + cm(2usize, 1usize, n))
        }
        i += 1usize
    }
    // K_1 through U'(sum K_i)U = T
    var j = 1usize
    while j <= n {
        kwk[cm(j, j, n)] = t[cm(2usize, j, 2usize)]
        if j >= 2usize { kwk[cm(j, j - 1usize, n)] = t[cm(1usize, j, 2usize)] }
        var r = j + 2usize
        while r <= n {
            kwk[cm(r, j, n)] = 0.0f64
            r += 1usize
        }
        j += 1usize
    }
    i = 2usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            let kb = (i - 1usize) * n * n
            j = 1usize
            while j <= n {
                var r = j
                while r <= n {
                    kwk[cm(r, j, n)] = kwk[cm(r, j, n)] - kwk[kb + cm(r, j, n)]
                    r += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            let kb = (i - 1usize) * n * n
            j = 1usize
            while j < n {
                var r = j + 1usize
                while r <= n {
                    kwk[kb + cm(j, r, n)] = kwk[kb + cm(r, j, n)]
                    r += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    // T + n lambda factored; T^{-1} K_i
    j = 1usize
    while j <= n {
        t[cm(2usize, j, 2usize)] += pow10(nlaht)
        j += 1usize
    }
    if dpbfa1(t, n) != 0usize { ret Indefinite }
    i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            let kb = (i - 1usize) * n * n
            j = 1usize
            while j <= n {
                dpbsl1(t, n, kwk, kb + cm(1usize, j, n))
                j += 1usize
            }
        }
        i += 1usize
    }
    // gradient and Hessian pieces
    j = 1usize
    while j <= n {
        work1[j - 1usize] = x[j - 1usize]
        j += 1usize
    }
    dpbsl1(t, n, work1, 0usize)
    if vmu != 2usize {
        j = 1usize
        while j <= n {
            work2[j - 1usize] = 2.0f64 * work1[j - 1usize]
            j += 1usize
        }
    } else {
        j = 1usize
        while j <= n {
            work2[j - 1usize] = x[j - 1usize]
            j += 1usize
        }
    }
    i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            dgemv_sq(true, n, kwk, (i - 1usize) * n * n, work2, work3)
            gwk1[i - 1usize] = 0.0f64 - ddot(work1, 0usize, 1usize, work3, 0usize, 1usize, n)
        }
        i += 1usize
    }
    i = 1usize
    while i <= nq {
        gwk2[i - 1usize] = 0.0f64
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            let kb = (i - 1usize) * n * n
            j = 1usize
            while j <= n {
                if vmu != 2usize {
                    var r = 1usize
                    while r <= n {
                        work1[r - 1usize] = kwk[kb + cm(r, j, n)]
                        r += 1usize
                    }
                    dpbsl1(t, n, work1, 0usize)
                    gwk2[i - 1usize] = gwk2[i - 1usize] - work1[j - 1usize]
                } else {
                    gwk2[i - 1usize] = gwk2[i - 1usize] - kwk[kb + cm(j, j, n)]
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    if vmu != 2usize {
        j = 1usize
        while j <= n {
            work1[j - 1usize] = x[j - 1usize]
            j += 1usize
        }
        dpbsl1(t, n, work1, 0usize)
        i = 1usize
        while i <= nq {
            if theta[i - 1usize] > 0.0f64 - 25.0f64 {
                let ib = (i - 1usize) * n * n
                dgemv_sq(false, n, kwk, ib, work1, work2)
                var m = 1usize
                while m <= i {
                    if theta[m - 1usize] > 0.0f64 - 25.0f64 {
                        let mb = (m - 1usize) * n * n
                        dgemv_sq(false, n, kwk, mb, work1, work3)
                        hwk1[cm(i, m, nq)] = 2.0f64 * ddot(work2, 0usize, 1usize, work3, 0usize, 1usize, n)
                        dgemv_sq(true, n, kwk, mb, work1, work3)
                        hwk1[cm(i, m, nq)] = hwk1[cm(i, m, nq)] + 2.0f64 * ddot(work2, 0usize, 1usize, work3, 0usize, 1usize, n)
                    }
                    m += 1usize
                }
                dgemv_sq(true, n, kwk, ib, work1, work2)
                m = 1usize
                while m <= i {
                    if theta[m - 1usize] > 0.0f64 - 25.0f64 {
                        let mb = (m - 1usize) * n * n
                        dgemv_sq(false, n, kwk, mb, work1, work3)
                        hwk1[cm(i, m, nq)] = hwk1[cm(i, m, nq)] + 2.0f64 * ddot(work2, 0usize, 1usize, work3, 0usize, 1usize, n)
                    }
                    m += 1usize
                }
            }
            i += 1usize
        }
    } else {
        j = 1usize
        while j <= n {
            work1[j - 1usize] = x[j - 1usize]
            j += 1usize
        }
        dpbsl1(t, n, work1, 0usize)
        i = 1usize
        while i <= nq {
            if theta[i - 1usize] > 0.0f64 - 25.0f64 {
                dgemv_sq(false, n, kwk, (i - 1usize) * n * n, work1, work2)
                var m = 1usize
                while m <= i {
                    if theta[m - 1usize] > 0.0f64 - 25.0f64 {
                        dgemv_sq(true, n, kwk, (m - 1usize) * n * n, x, work3)
                        hwk1[cm(i, m, nq)] = 2.0f64 * ddot(work2, 0usize, 1usize, work3, 0usize, 1usize, n)
                    }
                    m += 1usize
                }
            }
            i += 1usize
        }
    }
    i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 { hwk1[cm(i, i, nq)] = hwk1[cm(i, i, nq)] + gwk1[i - 1usize] }
        i += 1usize
    }
    i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            let ib = (i - 1usize) * n * n
            var m = 1usize
            while m <= i {
                hwk2[cm(i, m, nq)] = 0.0f64
                if theta[m - 1usize] > 0.0f64 - 25.0f64 {
                    let mb = (m - 1usize) * n * n
                    j = 1usize
                    while j <= n {
                        if vmu != 2usize {
                            var r = 1usize
                            while r <= n {
                                work1[r - 1usize] = kwk[mb + cm(r, j, n)]
                                r += 1usize
                            }
                            dpbsl1(t, n, work1, 0usize)
                            hwk2[cm(i, m, nq)] = hwk2[cm(i, m, nq)] + 2.0f64 * ddot(kwk, ib + cm(j, 1usize, n), n, work1, 0usize, 1usize, n)
                        } else {
                            hwk2[cm(i, m, nq)] = hwk2[cm(i, m, nq)] + ddot(kwk, ib + cm(j, 1usize, n), n, kwk, mb + cm(1usize, j, n), 1usize, n)
                        }
                        j += 1usize
                    }
                }
                m += 1usize
            }
        }
        i += 1usize
    }
    i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 { hwk2[cm(i, i, nq)] = hwk2[cm(i, i, nq)] + gwk2[i - 1usize] }
        i += 1usize
    }
    let dno = f64(nobs)
    let dn = f64(n)
    var trc = 0.0f64
    var det = 0.0f64
    var dum = 0.0f64
    if vmu == 1usize {
        trc = dno * pow10(0.0f64 - nlaht) * varht / score
        i = 1usize
        while i <= nq {
            if theta[i - 1usize] > 0.0f64 - 25.0f64 { gra[i - 1usize] = dno * (gwk1[i - 1usize] / trc / trc - 2.0f64 * score * gwk2[i - 1usize] / trc / dno) }
            i += 1usize
        }
    }
    if vmu == 3usize {
        dum = pow10(nlaht)
        i = 1usize
        while i <= nq {
            if theta[i - 1usize] > 0.0f64 - 25.0f64 { gra[i - 1usize] = (dum * dum * gwk1[i - 1usize] - 2.0f64 * varht * dum * gwk2[i - 1usize]) * (1.0f64 / dn) }
            i += 1usize
        }
    }
    if vmu == 2usize {
        det = pow10(0.0f64 - nlaht) * varht / score
        i = 1usize
        while i <= nq {
            if theta[i - 1usize] > 0.0f64 - 25.0f64 { gra[i - 1usize] = (gwk1[i - 1usize] / det - dno / dn * score * gwk2[i - 1usize]) * (1.0f64 / dno) }
            i += 1usize
        }
    }
    i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            var m = 1usize
            while m <= i {
                if theta[m - 1usize] > 0.0f64 - 25.0f64 {
                    let hh = cm(i, m, nq)
                    if vmu == 1usize {
                        hes[hh] = dno * (hwk1[hh] / trc / trc - 2.0f64 * gwk1[i - 1usize] * gwk2[m - 1usize] / (trc * trc * trc)
                            - 2.0f64 * gwk1[m - 1usize] * gwk2[i - 1usize] / (trc * trc * trc) - 2.0f64 * score * hwk2[hh] / trc / dno
                            + 6.0f64 * score * gwk2[i - 1usize] * gwk2[m - 1usize] / trc / trc / dno)
                    }
                    if vmu == 3usize {
                        hes[hh] = (dum * dum * hwk1[hh] - 2.0f64 * varht * dum * hwk2[hh]) * (1.0f64 / dn)
                    }
                    if vmu == 2usize {
                        hes[hh] = (hwk1[hh] / det - gwk1[i - 1usize] * gwk2[m - 1usize] / det / dn - gwk1[m - 1usize] * gwk2[i - 1usize] / det / dn
                            - dno / dn * score * hwk2[hh] + dno / (dn * dn) * score * gwk2[i - 1usize] * gwk2[m - 1usize]) * (1.0f64 / dno)
                    }
                }
                m += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}

type Mu = struct { theta: []f64, nlaht: f64, score: f64, varht: f64, c: []f64, d: []f64 }

// dmudr0: the kernels qs (nq of n by n, one after the other); theta by the Newton iteration of dmudr1, started at th_in when init and at the plug-in weights otherwise;
// the c, d, nlaht, score and varht are those of dmudr1's own last fit
fn dmudr0(a: *mem.Arena, s: []const f64, qs: []const f64, nq: usize, y: []const f64, n: usize, n0: usize, method: usize, varht_in: f64, init: bool, th_in: []const f64, prec: f64, maxite: usize, out: *Mu) -> err {
    if !method_code(method) || nq < 2usize { ret Dimension }
    if n0 < 1usize || n0 >= n { ret Dimension }
    let nn = n - n0
    let (sw, e1) = zeros(a, n * n0)
    let (qraux, e2) = zeros(a, n0)
    let (work, e3) = zeros(a, n + 2usize)
    let (qq, e4) = zeros(a, n * n * nq)
    let (z0, e5) = zeros(a, n)
    let (qwk, e6) = zeros(a, n * n)
    let (ywk, e7) = zeros(a, n)
    let (thewk, e8) = zeros(a, nq)
    let (theta, e9) = zeros(a, nq)
    let (hes, e10) = zeros(a, nq * nq)
    let (gra, e11) = zeros(a, nq)
    let (gwk1, e12) = zeros(a, nq)
    let (gwk2, e13) = zeros(a, nq)
    let (work2, e14) = zeros(a, nq + 2usize)
    let (cc, e15) = zeros(a, n)
    let (dd, e16) = zeros(a, n0)
    let (twk, e17) = zeros(a, 2usize * nn + 2usize)
    let (traux, e18) = zeros(a, nn)
    let (jp, e19) = mem.alloc[usize](a, n0 + 1usize)
    let (pvt, e20) = mem.alloc[usize](a, nq + 1usize)
    let (qs1, e21) = zeros(a, n)
    let (wk3, e22) = zeros(a, n + 2usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    if e16 != ok { ret e16 }
    if e17 != ok { ret e17 }
    if e18 != ok { ret e18 }
    if e19 != ok { ret e19 }
    if e20 != ok { ret e20 }
    if e21 != ok { ret e21 }
    if e22 != ok { ret e22 }
    var i = 0usize
    while i < n * n0 {
        sw[i] = s[i]
        i += 1usize
    }
    i = 0usize
    while i < n * n * nq {
        qq[i] = qs[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        z0[i] = y[i]
        i += 1usize
    }
    dqrdc(sw, n, n0, qraux, jp, work)
    i = 1usize
    while i <= n0 {
        if sw[cm(i, i, n)] == 0.0f64 { ret Rank }
        i += 1usize
    }
    qty(sw, 0usize, n, n, n0, qraux, 0usize, z0, 0usize)
    i = 0usize
    while i < nq {
        dqrslm(sw, 0usize, n, n, n0, qraux, 0usize, qq, i * n * n, n, qs1, work)
        i += 1usize
    }
    var cr: Core = zero
    var varht = varht_in
    var j = 1usize
    var nlawk = 0.0f64
    var scrwk = 0.0f64
    var ce = ok
    if init {
        i = 0usize
        while i < nq {
            thewk[i] = th_in[i]
            i += 1usize
        }
    } else {
    // the plug-in start
    i = 1usize
    while i <= nq {
        var sm = 0.0f64
        j = 1usize
        while j <= nn {
            sm += absf(qq[(i - 1usize) * n * n + cm(n0 + j, n0 + j, n)])
            j += 1usize
        }
        if sm > 0.0f64 { sm = 1.0f64 / sm }
        thewk[i - 1usize] = sm
        i += 1usize
    }
    j = 1usize
    while j <= n {
        var r = j
        while r <= n {
            qwk[cm(r, j, n)] = 0.0f64
            r += 1usize
        }
        j += 1usize
    }
    i = 1usize
    while i <= nq {
        j = 1usize
        while j <= n {
            var r = j
            while r <= n {
                qwk[cm(r, j, n)] += thewk[i - 1usize] * qq[(i - 1usize) * n * n + cm(r, j, n)]
                r += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        ywk[i] = z0[i]
        i += 1usize
    }
    ce = dcore(a, method, qwk, n, n, n0, ywk, true, 0.0f64, 0.0f64, varht, &cr)
    if ce != ok { ret ce }
    varht = cr.varht
    nlawk = cr.nlaht
    scrwk = cr.score
    ce = dcoef(a, sw, n, n, n0, qraux, jp, ywk, qwk, n, nlawk, cc, dd)
    if ce != ok { ret ce }
    qty(sw, 0usize, n, n, n0, qraux, 0usize, cc, 0usize)
    i = 1usize
    while i <= nq {
        dsymv_l(nn, thewk[i - 1usize], qq, (i - 1usize) * n * n + cm(n0 + 1usize, n0 + 1usize, n), n, cc, n0, wk3, 0usize)
        var t = ddot(cc, n0, 1usize, wk3, 0usize, 1usize, nn) * thewk[i - 1usize]
        if t > 0.0f64 { t = log10f(t) } else { t = 0.0f64 - 25.0f64 }
        thewk[i - 1usize] = t
        i += 1usize
    }
    }
    var scrold = 10000000000.0f64
    var maxitwk = maxite
    var alph = 0.0f64 - 1.0f64
    var job0 = true
    var lo = 0.0f64
    var up = 0.0f64
    var done = false
    while !done {
        j = 1usize
        while j <= n {
            var r = j
            while r <= n {
                qwk[cm(r, j, n)] = 0.0f64
                r += 1usize
            }
            j += 1usize
        }
        i = 1usize
        while i <= nq {
            if thewk[i - 1usize] > 0.0f64 - 25.0f64 {
                let w = pow10(thewk[i - 1usize])
                j = 1usize
                while j <= n {
                    var r = j
                    while r <= n {
                        qwk[cm(r, j, n)] += w * qq[(i - 1usize) * n * n + cm(r, j, n)]
                        r += 1usize
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            ywk[i] = z0[i]
            i += 1usize
        }
        ce = dcore(a, method, qwk, n, n, n0, ywk, job0, lo, up, varht, &cr)
        if ce != ok { ret ce }
        varht = cr.varht
        nlawk = cr.nlaht
        scrwk = cr.score
        if scrold < scrwk {
            let gmx = absf(gwk1[idamax(gwk1, 0usize, 1usize, nq) - 1usize])
            if alph * gmx > 0.0f64 - prec { ret NoDescent }
            alph = alph / 2.0f64
            i = 1usize
            while i <= nq {
                thewk[i - 1usize] = theta[i - 1usize] + alph * gwk1[i - 1usize]
                i += 1usize
            }
            continue
        }
        maxitwk -= 1usize
        // gradient and Hessian
        j = 1usize
        while j <= nn - 2usize {
            traux[j - 1usize] = qwk[cm(n0 + 1usize + j, n0 + j, n)]
            j += 1usize
        }
        j = 1usize
        while j <= nn {
            twk[cm(2usize, j, 2usize)] = qwk[cm(n0 + j, n0 + j, n)]
            if j >= 2usize { twk[cm(1usize, j, 2usize)] = qwk[cm(n0 + j - 1usize, n0 + j, n)] }
            j += 1usize
        }
        ce = ddeev(a, method, n, n0, nq, qq, qwk, traux, twk, ywk[n0..n], thewk, nlawk, scrwk, varht, hes, gra)
        if ce != ok { ret ce }
        // the active subset
        var iwk = 0usize
        i = 1usize
        while i <= nq {
            if thewk[i - 1usize] > 0.0f64 - 25.0f64 {
                iwk += 1usize
                var r = 1usize
                while r <= nq {
                    hes[cm(r, iwk, nq)] = hes[cm(r, i, nq)]
                    r += 1usize
                }
            }
            i += 1usize
        }
        iwk = 0usize
        i = 1usize
        while i <= nq {
            if thewk[i - 1usize] > 0.0f64 - 25.0f64 {
                iwk += 1usize
                var r = 1usize
                while r <= nq {
                    hes[cm(iwk, r, nq)] = hes[cm(i, r, nq)]
                    r += 1usize
                }
                gwk1[iwk - 1usize] = gra[i - 1usize]
                work2[iwk - 1usize] = gra[i - 1usize]
            }
            i += 1usize
        }
        i = 1usize
        while i < iwk {
            var r = 1usize
            while r <= iwk - i {
                hes[cm(i, i + r, nq)] = hes[cm(i + r, i, nq)]
                r += 1usize
            }
            i += 1usize
        }
        dmcdc(hes, nq, iwk, pvt)
        // dprmut job 0 then job 1 around the solve
        i = 1usize
        while i <= iwk {
            wk3[i - 1usize] = gwk1[pvt[i - 1usize] - 1usize]
            i += 1usize
        }
        i = 1usize
        while i <= iwk {
            gwk1[i - 1usize] = wk3[i - 1usize]
            i += 1usize
        }
        dposl(hes, nq, iwk, gwk1)
        i = 1usize
        while i <= iwk {
            wk3[pvt[i - 1usize] - 1usize] = gwk1[i - 1usize]
            i += 1usize
        }
        i = 1usize
        while i <= iwk {
            gwk1[i - 1usize] = wk3[i - 1usize]
            i += 1usize
        }
        alph = 0.0f64 - 1.0f64
        i = nq
        while i >= 1usize {
            if thewk[i - 1usize] <= 0.0f64 - 25.0f64 {
                gwk1[i - 1usize] = 0.0f64
            } else {
                gwk1[i - 1usize] = gwk1[iwk - 1usize]
                iwk -= 1usize
            }
            i -= 1usize
        }
        let ln10 = math.log[f64](10.0f64)
        i = 1usize
        while i <= nq {
            gwk1[i - 1usize] = gwk1[i - 1usize] * (1.0f64 / ln10)
            i += 1usize
        }
        var tmp = absf(gwk1[idamax(gwk1, 0usize, 1usize, nq) - 1usize])
        if tmp > 1.0f64 {
            i = 1usize
            while i <= nq {
                gwk1[i - 1usize] = gwk1[i - 1usize] * (1.0f64 / tmp)
                i += 1usize
            }
        }
        i = 1usize
        while i <= nq {
            if thewk[i - 1usize] > 0.0f64 - 25.0f64 { thewk[i - 1usize] = thewk[i - 1usize] - nlawk }
            theta[i - 1usize] = thewk[i - 1usize]
            i += 1usize
        }
        tmp = gra[idamax(gra, 0usize, 1usize, nq) - 1usize]
        tmp = tmp * tmp
        if tmp < prec * prec || (scrold - scrwk < prec * (scrwk + 1.0f64) && tmp < prec * (scrwk + 1.0f64) * (scrwk + 1.0f64)) {
            done = true
            continue
        }
        if maxitwk < 1usize { ret NoConverge }
        scrold = scrwk
        i = 1usize
        while i <= nq {
            thewk[i - 1usize] = thewk[i - 1usize] + alph * gwk1[i - 1usize]
            i += 1usize
        }
        job0 = false
        lo = 0.0f64 - 1.0f64
        up = 1.0f64
    }
    // the last fit of dmudr1 at the final theta
    j = 1usize
    while j <= n {
        var r = j
        while r <= n {
            qwk[cm(r, j, n)] = 0.0f64
            r += 1usize
        }
        j += 1usize
    }
    i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            let w = pow10(theta[i - 1usize])
            j = 1usize
            while j <= n {
                var r = j
                while r <= n {
                    qwk[cm(r, j, n)] += w * qq[(i - 1usize) * n * n + cm(r, j, n)]
                    r += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        ywk[i] = z0[i]
        i += 1usize
    }
    ce = dcore(a, method, qwk, n, n, n0, ywk, job0, lo, up, varht, &cr)
    if ce != ok { ret ce }
    ce = dcoef(a, sw, n, n, n0, qraux, jp, ywk, qwk, n, cr.nlaht, cc, dd)
    if ce != ok { ret ce }
    out.theta = theta
    out.nlaht = cr.nlaht
    out.score = cr.score
    out.varht = cr.varht
    out.c = cc
    out.d = dd
    ret ok
}

// mspreg0: ssanova0's multiple smoothing parameter fit: theta by dmudr0, then sspreg0 on sum 10^theta Q
fn mspreg0(a: *mem.Arena, s: []const f64, qs: []const f64, nq: usize, y: []const f64, n: usize, n0: usize, method: usize, varht_in: f64, prec: f64, maxite: usize, out: *Ss0) -> err {
    var mu: Mu = zero
    let (t0, te) = zeros(a, nq)
    if te != ok { ret te }
    try dmudr0(a, s, qs, nq, y, n, n0, method, varht_in, false, t0, prec, maxite, &mu)
    let theta = mu.theta
    let (qsum, e23) = zeros(a, n * n)
    if e23 != ok { ret e23 }
    var i = 1usize
    while i <= nq {
        if theta[i - 1usize] > 0.0f64 - 25.0f64 {
            let w = pow10(theta[i - 1usize])
            var t = 0usize
            while t < n * n {
                qsum[t] += w * qs[(i - 1usize) * n * n + t]
                t += 1usize
            }
        }
        i += 1usize
    }
    let fe = sspreg0(a, s, qsum, y, n, n0, method, varht_in, out)
    if fe != ok { ret fe }
    out.theta = theta
    out.thfit = theta
    ret ok
}

// the cubic spline marginal of R gss on [lo, hi] (mkphi.cubic, mkrk.cubic)
fn cubic_phi(x: f64, lo: f64, hi: f64) -> f64 { ret (x - lo) / (hi - lo) - 0.5f64 }

fn cubic_k2(x: f64) -> f64 { ret ((x - 0.5f64) * (x - 0.5f64) - 1.0f64 / 12.0f64) / 2.0f64 }

fn cubic_k4(x: f64) -> f64 {
    let t = (x - 0.5f64) * (x - 0.5f64)
    ret (t * t - t / 2.0f64 + 7.0f64 / 240.0f64) / 24.0f64
}

fn cubic_rk(x: f64, y: f64, lo: f64, hi: f64) -> f64 {
    let u = (x - lo) / (hi - lo)
    let v = (y - lo) / (hi - lo)
    ret cubic_k2(u) * cubic_k2(v) - cubic_k4(absf(u - v))
}

// the default range of mkterm: the data range widened by 5% each side
fn cubic_range_lo(x: []const f64) -> f64 {
    var mn = x[0usize]
    var mx = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < mn { mn = x[i] }
        if x[i] > mx { mx = x[i] }
        i += 1usize
    }
    ret mn - 0.05f64 * (mx - mn)
}

fn cubic_range_hi(x: []const f64) -> f64 {
    var mn = x[0usize]
    var mx = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < mn { mn = x[i] }
        if x[i] > mx { mx = x[i] }
        i += 1usize
    }
    ret mx + 0.05f64 * (mx - mn)
}

type Design = struct { s: []f64, q: []f64, nq: usize, n0: usize }

fn dmin(x: []const f64, o: usize, n: usize) -> f64 {
    var m = x[o]
    var i = 1usize
    while i < n {
        if x[o + i] < m { m = x[o + i] }
        i += 1usize
    }
    ret m
}

fn dmax(x: []const f64, o: usize, n: usize) -> f64 {
    var m = x[o]
    var i = 1usize
    while i < n {
        if x[o + i] > m { m = x[o + i] }
        i += 1usize
    }
    ret m
}

// Gamma at a half integer x2 / 2
fn gamma_half(x2: i64) -> f64 {
    var g = 0.0f64
    var k = 0i64
    if x2 % 2i64 == 0i64 {
        g = 1.0f64
        k = 2i64
    } else {
        g = math.sqrt[f64](3.14159265358979323846f64)
        k = 1i64
    }
    // g is Gamma(k / 2); move k to x2 by the recurrence Gamma(x + 1) = x Gamma(x)
    while k < x2 {
        g = g * (f64(k) / 2.0f64)
        k += 2i64
    }
    while k > x2 {
        k -= 2i64
        g = g / (f64(k) / 2.0f64)
    }
    ret g
}

// thin-plate spline marginal (mkrk.tp, mkphi.tp), or the cubic one when kind is 1
type Marg = struct { kind: usize, dm: usize, order: usize, nn: usize, lo: f64, hi: f64, nm: usize, mesh: []f64, codes: []usize, r: []f64, q: []f64, pep: []f64, theta: f64 }

fn tp_pvec(m: *const Marg, x: []const f64, na: usize, i: usize, out: []f64, o: usize) {
    var k = 0usize
    while k < m.nn {
        var p = 1.0f64
        var j = 0usize
        while j < m.dm {
            var c = 0usize
            while c < m.codes[k * m.dm + j] {
                p = p * x[i + j * na]
                c += 1usize
            }
            j += 1usize
        }
        out[o + k] = p
        k += 1usize
    }
}

// the pseudo kernel E between row i of xa and row j of xb
fn tp_e(m: *const Marg, xa: []const f64, na: usize, i: usize, xb: []const f64, nb: usize, j: usize) -> f64 {
    var d2 = 0.0f64
    var v = 0usize
    while v < m.dm {
        let df = xa[i + v * na] - xb[j + v * nb]
        d2 += df * df
        v += 1usize
    }
    var d = math.sqrt[f64](d2)
    if m.dm == 1usize { d = absf(xa[i] - xb[j]) }
    let power = f64(2usize * m.order - m.dm)
    if m.dm % 2usize == 1usize { ret m.theta * math.pow[f64](d, power) }
    var ld = 1.0f64
    if d > 0.0f64 { ld = d }
    ret m.theta * math.pow[f64](d, power) * math.log[f64](ld)
}

fn tp_marg(a: *mem.Arena, mesh: []const f64, nm: usize, dm: usize, order: usize, out: *Marg) -> err {
    out.kind = 2usize
    out.dm = dm
    out.order = order
    out.nm = nm
    var nn = 0usize
    var tot = 1usize
    var j = 0usize
    while j < dm {
        tot = tot * order
        j += 1usize
    }
    let (codes, ce) = mem.alloc[usize](a, tot * dm + 1usize)
    if ce != ok { ret ce }
    var i = 0usize
    while i < tot {
        var sm = 0usize
        var ind = i
        var cd: [4]usize = zero
        j = 0usize
        while j < dm {
            cd[j] = ind % order
            ind = ind / order
            sm += cd[j]
            j += 1usize
        }
        if sm < order {
            j = 0usize
            while j < dm {
                codes[nn * dm + j] = cd[j]
                j += 1usize
            }
            nn += 1usize
        }
        i += 1usize
    }
    out.nn = nn
    out.codes = codes
    let (ms, me) = zeros(a, nm * dm)
    if me != ok { ret me }
    i = 0usize
    while i < nm * dm {
        ms[i] = mesh[i]
        i += 1usize
    }
    out.mesh = ms
    var th = 0.0f64
    let pi = 3.14159265358979323846f64
    if dm % 2usize == 1usize {
        th = gamma_half(i64(dm) - 2i64 * i64(order)) / math.pow[f64](2.0f64, f64(2usize * order)) / math.pow[f64](pi, f64(dm) / 2.0f64) / gamma_half(2i64 * i64(order))
    } else {
        var sg = 1.0f64
        if (dm / 2usize + order + 1usize) % 2usize == 1usize { sg = 0.0f64 - 1.0f64 }
        th = sg / math.pow[f64](2.0f64, f64(2usize * order - 1usize)) / math.pow[f64](pi, f64(dm) / 2.0f64) / gamma_half(2i64 * i64(order)) / gamma_half(2i64 * (i64(order) - i64(dm) / 2i64 + 1i64))
    }
    out.theta = th
    let w = math.sqrt[f64](1.0f64 / f64(nm))
    let (sm2, e1) = zeros(a, nm * nn)
    let (pv, e2) = zeros(a, nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    i = 0usize
    while i < nm {
        tp_pvec(out, out.mesh, nm, i, pv, 0usize)
        var k = 0usize
        while k < nn {
            sm2[i + k * nm] = w * pv[k]
            k += 1usize
        }
        i += 1usize
    }
    let (f, qe) = dc.qr(a, sm2, nm, nn, 0.0000001f64)
    if qe != ok { ret qe }
    if f.rank < nn { ret Rank }
    let (rr, e3) = zeros(a, nn * nn)
    let (qm, e4) = zeros(a, nm * nn)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var c = 0usize
    while c < nn {
        var rw = 0usize
        while rw <= c {
            rr[rw + c * nn] = f.qr[c * nm + rw]
            rw += 1usize
        }
        // column c of Q is Q e_c
        var t = 0usize
        while t < nm {
            qm[t + c * nm] = 0.0f64
            t += 1usize
        }
        qm[c + c * nm] = 1.0f64
        dc.qr_qy(&f, qm[c * nm..c * nm + nm])
        c += 1usize
    }
    out.r = rr
    out.q = qm
    // pep = Q' (w E w) Q
    let (em, e5) = zeros(a, nm * nm)
    let (tm, e6) = zeros(a, nm * nn)
    let (pp, e7) = zeros(a, nn * nn)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    i = 0usize
    while i < nm {
        j = 0usize
        while j < nm {
            em[i + j * nm] = w * tp_e(out, out.mesh, nm, i, out.mesh, nm, j) * w
            j += 1usize
        }
        i += 1usize
    }
    // tm = E Q (nm by nn), pep = Q' tm
    c = 0usize
    while c < nn {
        i = 0usize
        while i < nm {
            var sm = 0.0f64
            j = 0usize
            while j < nm {
                sm += em[i + j * nm] * qm[j + c * nm]
                j += 1usize
            }
            tm[i + c * nm] = sm
            i += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < nn {
        var k = 0usize
        while k < nn {
            var sm = 0.0f64
            i = 0usize
            while i < nm {
                sm += qm[i + k * nm] * tm[i + c * nm]
                i += 1usize
            }
            pp[k + c * nn] = sm
            k += 1usize
        }
        c += 1usize
    }
    out.pep = pp
    ret ok
}

// R^{-T} p(x) and Q'(w E(mesh, x)) for every row of x: pm and ex are nx by nn
fn tp_rows(a: *mem.Arena, m: *const Marg, x: []const f64, nx: usize, pm: []f64, ex: []f64) -> err {
    let (pv, e1) = zeros(a, m.nn)
    if e1 != ok { ret e1 }
    let w = math.sqrt[f64](1.0f64 / f64(m.nm))
    var i = 0usize
    while i < nx {
        tp_pvec(m, x, nx, i, pv, 0usize)
        var k = 0usize
        while k < m.nn {
            var s = pv[k]
            var l = 0usize
            while l < k {
                s = s - m.r[l + k * m.nn] * pm[i + l * nx]
                l += 1usize
            }
            pm[i + k * nx] = s / m.r[k + k * m.nn]
            k += 1usize
        }
        k = 0usize
        while k < m.nn {
            var s = 0.0f64
            var t = 0usize
            while t < m.nm {
                s += m.q[t + k * m.nm] * (w * tp_e(m, m.mesh, m.nm, t, x, nx, i))
                t += 1usize
            }
            ex[i + k * nx] = s
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the marginal's phi columns at the rows of x (nx by nphi, nphi = nn - 1 for tp, 1 for cubic) and its kernel between the rows xa and xb (na by nb)
fn marg_phi(a: *mem.Arena, m: *const Marg, x: []const f64, nx: usize, out: []f64) -> err {
    if m.kind == 1usize {
        var i = 0usize
        while i < nx {
            out[i] = cubic_phi(x[i], m.lo, m.hi)
            i += 1usize
        }
        ret ok
    }
    let (pm, e1) = zeros(a, nx * m.nn)
    let (ex, e2) = zeros(a, nx * m.nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    try tp_rows(a, m, x, nx, pm, ex)
    var k = 1usize
    while k < m.nn {
        var i = 0usize
        while i < nx {
            out[i + (k - 1usize) * nx] = pm[i + k * nx]
            i += 1usize
        }
        k += 1usize
    }
    ret ok
}

fn marg_rk(a: *mem.Arena, m: *const Marg, xa: []const f64, na: usize, xb: []const f64, nb: usize, out: []f64) -> err {
    if m.kind == 1usize {
        var j = 0usize
        while j < nb {
            var i = 0usize
            while i < na {
                out[i + j * na] = cubic_rk(xa[i], xb[j], m.lo, m.hi)
                i += 1usize
            }
            j += 1usize
        }
        ret ok
    }
    let (pa, e1) = zeros(a, na * m.nn)
    let (xa2, e2) = zeros(a, na * m.nn)
    let (pb, e3) = zeros(a, nb * m.nn)
    let (xb2, e4) = zeros(a, nb * m.nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    try tp_rows(a, m, xa, na, pa, xa2)
    try tp_rows(a, m, xb, nb, pb, xb2)
    var j = 0usize
    while j < nb {
        var i = 0usize
        while i < na {
            var v = tp_e(m, xa, na, i, xb, nb, j)
            var k = 0usize
            var t1 = 0.0f64
            var t2 = 0.0f64
            var t3 = 0.0f64
            while k < m.nn {
                t1 += pa[i + k * na] * xb2[j + k * nb]
                t2 += xa2[i + k * na] * pb[j + k * nb]
                var l = 0usize
                var inner = 0.0f64
                while l < m.nn {
                    inner += m.pep[k + l * m.nn] * pb[j + l * nb]
                    l += 1usize
                }
                t3 += pa[i + k * na] * inner
                k += 1usize
            }
            v = v - t1 - t2 + t3
            out[i + j * na] = v
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// mkterm for the models: 1 y ~ x1, 2 y ~ x1 + x2, 3 y ~ x1 * x2 (cubic marginals); 4, 5, 6 the same with thin-plate marginals of order 2; 7 y ~ x with x the
// two-column matrix (one thin-plate marginal of dimension 2). dat is the n by dim data (ranges and meshes come from it); the s columns are at the rows xa (na of
// them) and the kernel matrices q[i] (na by nb) between the rows xa and xb.
fn design(a: *mem.Arena, model: usize, dat: []const f64, n: usize, xa: []const f64, na: usize, xb: []const f64, nb: usize, out: *Design) -> err {
    var kind = 1usize
    if model >= 4usize { kind = 2usize }
    let m3 = (model - 1usize) % 3usize + 1usize
    var dim = 2usize
    if model == 1usize || model == 4usize { dim = 1usize }
    var n0 = 2usize
    var nq = 1usize
    if model == 7usize {
        n0 = 3usize
        nq = 1usize
    } else {
        if m3 == 2usize {
            n0 = 3usize
            nq = 2usize
        }
        if m3 == 3usize {
            n0 = 4usize
            nq = 5usize
        }
    }
    let (s, e1) = zeros(a, na * n0)
    let (q, e2) = zeros(a, na * nb * nq)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    out.s = s
    out.q = q
    out.nq = nq
    out.n0 = n0
    var i = 0usize
    while i < na {
        s[i] = 1.0f64
        i += 1usize
    }
    if model == 7usize {
        var mg: Marg = zero
        try tp_marg(a, dat, n, 2usize, 2usize, &mg)
        try marg_phi(a, &mg, xa, na, s[na..3usize * na])
        try marg_rk(a, &mg, xa, na, xb, nb, q)
        ret ok
    }
    var mg1: Marg = zero
    var mg2: Marg = zero
    if kind == 1usize {
        mg1.kind = 1usize
        mg1.lo = dmin(dat, 0usize, n) - 0.05f64 * (dmax(dat, 0usize, n) - dmin(dat, 0usize, n))
        mg1.hi = dmax(dat, 0usize, n) + 0.05f64 * (dmax(dat, 0usize, n) - dmin(dat, 0usize, n))
        if dim == 2usize {
            mg2.kind = 1usize
            mg2.lo = dmin(dat, n, n) - 0.05f64 * (dmax(dat, n, n) - dmin(dat, n, n))
            mg2.hi = dmax(dat, n, n) + 0.05f64 * (dmax(dat, n, n) - dmin(dat, n, n))
        }
    } else {
        try tp_marg(a, dat[0usize..n], n, 1usize, 2usize, &mg1)
        if dim == 2usize { try tp_marg(a, dat[n..2usize * n], n, 1usize, 2usize, &mg2) }
    }
    let sz = na * nb
    try marg_phi(a, &mg1, xa[0usize..na], na, s[na..2usize * na])
    try marg_rk(a, &mg1, xa[0usize..na], na, xb[0usize..nb], nb, q[0usize..sz])
    if dim == 1usize { ret ok }
    let (p2, e3) = zeros(a, na)
    let (r2, e4) = zeros(a, sz)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    try marg_phi(a, &mg2, xa[na..2usize * na], na, p2)
    try marg_rk(a, &mg2, xa[na..2usize * na], na, xb[nb..2usize * nb], nb, r2)
    i = 0usize
    while i < na {
        s[2usize * na + i] = p2[i]
        if m3 == 3usize { s[3usize * na + i] = s[na + i] * p2[i] }
        i += 1usize
    }
    i = 0usize
    while i < sz {
        q[sz + i] = r2[i]
        i += 1usize
    }
    if m3 == 3usize {
        // the phi products between the rows xa and xb: phi(xa) phi(xb) for each variable
        let (p1b, e5) = zeros(a, nb)
        let (p2b, e6) = zeros(a, nb)
        let (p1a, e7) = zeros(a, na)
        if e5 != ok { ret e5 }
        if e6 != ok { ret e6 }
        if e7 != ok { ret e7 }
        try marg_phi(a, &mg1, xb[0usize..nb], nb, p1b)
        try marg_phi(a, &mg2, xb[nb..2usize * nb], nb, p2b)
        try marg_phi(a, &mg1, xa[0usize..na], na, p1a)
        var j = 0usize
        while j < nb {
            i = 0usize
            while i < na {
                let at = i + j * na
                let pp1 = p1a[i] * p1b[j]
                let pp2 = p2[i] * p2b[j]
                q[2usize * sz + at] = q[at] * pp2
                q[3usize * sz + at] = pp1 * r2[at]
                q[4usize * sz + at] = q[at] * r2[at]
                i += 1usize
            }
            j += 1usize
        }
    }
    ret ok
}

// the Cholesky solve of the symmetric positive definite m (n by n, destroyed) against the nrhs columns of b (n by nrhs)
fn chol_solve(m: []f64, n: usize, b: []f64, nrhs: usize) -> err {
    var j = 1usize
    while j <= n {
        var s = m[cm(j, j, n)] - ddot(m, cm(j, 1usize, n), n, m, cm(j, 1usize, n), n, j - 1usize)
        if s <= 0.0f64 { ret Indefinite }
        s = math.sqrt[f64](s)
        m[cm(j, j, n)] = s
        var i = j + 1usize
        while i <= n {
            m[cm(i, j, n)] = (m[cm(i, j, n)] - ddot(m, cm(i, 1usize, n), n, m, cm(j, 1usize, n), n, j - 1usize)) / s
            i += 1usize
        }
        j += 1usize
    }
    var c = 1usize
    while c <= nrhs {
        var k = 1usize
        while k <= n {
            b[cm(k, c, n)] = (b[cm(k, c, n)] - ddot(m, cm(k, 1usize, n), n, b, cm(1usize, c, n), 1usize, k - 1usize)) / m[cm(k, k, n)]
            k += 1usize
        }
        k = n
        while k >= 1usize {
            var t = b[cm(k, c, n)]
            var i = k + 1usize
            while i <= n {
                t = t - m[cm(i, k, n)] * b[cm(i, c, n)]
                i += 1usize
            }
            b[cm(k, c, n)] = t / m[cm(k, k, n)]
            k -= 1usize
        }
        c += 1usize
    }
    ret ok
}

type Pred = struct { fit: []f64, se: []f64 }

// predict.ssanova0 with se.fit: s0, q0 the fit design (n rows), s1 (m by n0), q1 (nq of m by n), rd (nq by m) the diagonal kernel values at the new rows
fn predict0(a: *mem.Arena, f: *const Ss0, s0: []const f64, q0: []const f64, s1: []const f64, q1: []const f64, rd: []const f64, wv: []const f64, n: usize, n0: usize, nq: usize, m: usize, out: *Pred) -> err {
    let (qsum, e1) = zeros(a, n * n)
    let (qq, e2) = zeros(a, m * n)
    let (fit, e3) = zeros(a, m)
    let (se, e4) = zeros(a, m)
    let (mm, e5) = zeros(a, n * n)
    let (rhs, e6) = zeros(a, n * (n0 + m))
    let (r0, e7) = zeros(a, n * (n0 + m))
    let (g, e8) = zeros(a, n0 * n0)
    let (u, e9) = zeros(a, n0 * m)
    let (u0, e10) = zeros(a, n0 * m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    var i = 0usize
    while i < nq {
        let w = pow10(f.theta[i])
        let wf = pow10(f.thfit[i])
        var t = 0usize
        while t < n * n {
            qsum[t] += wf * q0[i * n * n + t] * wv[t % n] * wv[t / n]
            t += 1usize
        }
        t = 0usize
        while t < m * n {
            qq[t] += w * q1[i * m * n + t] * wv[t / m]
            t += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        var sm = 0.0f64
        var j = 0usize
        while j < n {
            sm += qq[i + j * m] * f.c[j]
            j += 1usize
        }
        j = 0usize
        while j < n0 {
            sm += s1[i + j * m] * f.d[j]
            j += 1usize
        }
        fit[i] = sm
        i += 1usize
    }
    // M = Q + n lambda I; the right-hand sides are the columns of S and the rows of qq
    let nl = pow10(f.nlaht)
    i = 0usize
    while i < n * n {
        mm[i] = qsum[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        mm[i + i * n] += nl
        i += 1usize
    }
    i = 0usize
    while i < n0 {
        var j = 0usize
        while j < n {
            rhs[i * n + j] = s0[j + i * n] * wv[j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            rhs[(n0 + i) * n + j] = qq[i + j * m]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n * (n0 + m) {
        r0[i] = rhs[i]
        i += 1usize
    }
    let ce = chol_solve(mm, n, rhs, n0 + m)
    if ce != ok { ret ce }
    // G = S'M^{-1}S, then the variance r - q'M^{-1}q + u'G^{-1}u with u = s - S'M^{-1}q
    i = 0usize
    while i < n0 {
        var j = 0usize
        while j < n0 {
            g[i + j * n0] = ddot(r0, i * n, 1usize, rhs, j * n, 1usize, n)
            j += 1usize
        }
        i += 1usize
    }
    let b = f.varht / nl
    i = 0usize
    while i < m {
        var rr = 0.0f64
        var k = 0usize
        while k < nq {
            rr += pow10(f.theta[k]) * rd[k * m + i]
            k += 1usize
        }
        se[i] = rr - ddot(r0, (n0 + i) * n, 1usize, rhs, (n0 + i) * n, 1usize, n)
        k = 0usize
        while k < n0 {
            let uk = s1[i + k * m] - ddot(r0, k * n, 1usize, rhs, (n0 + i) * n, 1usize, n)
            u[k + i * n0] = uk
            u0[k + i * n0] = uk
            k += 1usize
        }
        i += 1usize
    }
    let ge = chol_solve(g, n0, u, m)
    if ge != ok { ret ge }
    i = 0usize
    while i < m {
        let qf = ddot(u0, i * n0, 1usize, u, i * n0, 1usize, n0)
        se[i] = math.sqrt[f64](b * (se[i] + qf))
        i += 1usize
    }
    out.fit = fit
    out.se = se
    ret ok
}

type Gss0 = struct { fit: Ss0, w: []f64, eta: []f64, iter: usize }

// the pseudo data of family 1 binomial, 2 poisson, 3 Gamma, 4 inverse.gaussian (mkdata.* with no offset or case weights)
fn mkdata(fam: usize, y: []const f64, eta: []const f64, n: usize, ywk: []f64, wt: []f64) {
    var i = 0usize
    while i < n {
        if fam == 1usize {
            let odds = math.exp[f64](eta[i])
            let p = odds / (1.0f64 + odds)
            let u = p - y[i]
            let w = p / (1.0f64 + odds)
            ywk[i] = eta[i] - u / w
            wt[i] = w
        }
        if fam == 2usize {
            let lam = math.exp[f64](eta[i])
            let u = lam - y[i]
            ywk[i] = eta[i] - u / lam
            wt[i] = lam
        }
        if fam == 3usize {
            let mu = math.exp[f64](eta[i])
            let u = 1.0f64 - y[i] / mu
            ywk[i] = eta[i] - u
            wt[i] = 1.0f64
        }
        if fam == 4usize {
            let mu = math.exp[f64](eta[i])
            let u = (1.0f64 - y[i] / mu) / mu
            let w = 1.0f64 / mu
            ywk[i] = eta[i] - u / w
            wt[i] = w
        }
        i += 1usize
    }
}

// gssanova0: performance-oriented iteration over the exact ssanova0 fit (sspregpoi for one kernel, mspregpoi for several). fam as in mkdata; method 1 v, 2 m, 3 u
fn gssanova0(a: *mem.Arena, fam: usize, s: []const f64, qs: []const f64, nq: usize, y: []const f64, n: usize, n0: usize, method: usize, varht: f64, prec: f64, maxiter: usize, out: *Gss0) -> err {
    let (eta, e1) = zeros(a, n)
    let (etan, e2) = zeros(a, n)
    let (ywk, e3) = zeros(a, n)
    let (wt, e4) = zeros(a, n)
    let (w, e5) = zeros(a, n)
    let (yw, e6) = zeros(a, n)
    let (sw, e7) = zeros(a, n * n0)
    let (qw, e8) = zeros(a, n * n * nq)
    let (th, e9) = zeros(a, nq)
    let (thr, e10) = zeros(a, nq)
    let (qsum, e11) = zeros(a, n * n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    var nla0 = 0.0f64
    var i = 0usize
    while i < n {
        nla0 += absf(qs[i + i * n])
        i += 1usize
    }
    nla0 = log10f(nla0 / f64(n))
    var lo = nla0 - 0.5f64
    var up = nla0 + 0.5f64
    var fit: Ss0 = zero
    var mu: Mu = zero
    let base = mem.mark(a)
    if fam >= 3usize {
        // the log-response start
        i = 0usize
        while i < n {
            ywk[i] = math.log[f64](y[i])
            i += 1usize
        }
        if nq == 1usize {
            try sspreg0j(a, s, qs, ywk, n, n0, method, varht, false, lo, up, &fit)
            i = 0usize
            while i < n {
                eta[i] = ywk[i] - pow10(fit.nlaht) * fit.c[i]
                i += 1usize
            }
        } else {
            try dmudr0(a, s, qs, nq, ywk, n, n0, method, varht, false, th, prec, maxiter, &mu)
            i = 0usize
            while i < n {
                eta[i] = ywk[i] - pow10(mu.nlaht) * mu.c[i]
                i += 1usize
            }
        }
        mem.reset(a, base)
    }
    var iter = 0usize
    var finished = false
    var init = false
    while !finished {
        iter += 1usize
        mkdata(fam, y, eta, n, ywk, wt)
        i = 0usize
        while i < n {
            w[i] = math.sqrt[f64](wt[i])
            yw[i] = w[i] * ywk[i]
            i += 1usize
        }
        var j = 0usize
        while j < n0 {
            i = 0usize
            while i < n {
                sw[i + j * n] = w[i] * s[i + j * n]
                i += 1usize
            }
            j += 1usize
        }
        var k = 0usize
        while k < nq {
            j = 0usize
            while j < n {
                i = 0usize
                while i < n {
                    qw[k * n * n + i + j * n] = w[i] * qs[k * n * n + i + j * n] * w[j]
                    i += 1usize
                }
                j += 1usize
            }
            k += 1usize
        }
        let lb = mem.mark(a)
        var nl = 0.0f64
        if nq == 1usize {
            try sspreg0j(a, sw, qw, yw, n, n0, method, varht, false, lo, up, &fit)
            nl = fit.nlaht
            i = 0usize
            while i < n {
                etan[i] = (yw[i] - pow10(nl) * fit.c[i]) / w[i]
                i += 1usize
            }
        } else {
            try dmudr0(a, sw, qw, nq, yw, n, n0, method, varht, init, th, prec, maxiter, &mu)
            nl = mu.nlaht
            i = 0usize
            while i < n {
                etan[i] = (yw[i] - pow10(nl) * mu.c[i]) / w[i]
                i += 1usize
            }
        }
        var num = 0.0f64
        var den = 0.0f64
        i = 0usize
        while i < n {
            let df = (eta[i] - etan[i]) / (1.0f64 + absf(eta[i]))
            num += wt[i] * df * df
            den += wt[i]
            i += 1usize
        }
        let disc = num / den
        if nq == 1usize {
            // the fit lives in the arena above base: keep c and d past the reset
            let (c2, ec) = zeros(a, n)
            let (d2, ed) = zeros(a, n0)
            if ec != ok { ret ec }
            if ed != ok { ret ed }
            i = 0usize
            while i < n {
                c2[i] = fit.c[i]
                i += 1usize
            }
            i = 0usize
            while i < n0 {
                d2[i] = fit.d[i]
                i += 1usize
            }
            fit.c = c2
            fit.d = d2
        } else {
            i = 0usize
            while i < nq {
                thr[i] = th[i]
                th[i] = mu.theta[i]
                i += 1usize
            }
            if disc < prec || iter >= maxiter {
                // the last theta is wanted below: th holds it
                finished = true
            }
        }
        let lo2 = nl - 0.5f64
        lo = lo2
        if nla0 - 5.0f64 > lo2 { lo = nla0 - 5.0f64 }
        up = nl + 0.5f64
        if nla0 - 5.0f64 > up { up = nla0 - 5.0f64 }
        if nq == 1usize {
            if disc < prec || iter >= maxiter { finished = true }
        }
        if !finished {
            i = 0usize
            while i < n {
                eta[i] = etan[i]
                i += 1usize
            }
            init = true
        }
        if nq > 1usize {
            mem.reset(a, lb)
        }
    }
    if nq == 1usize {
        out.fit = fit
        let (t1, et) = zeros(a, 1usize)
        if et != ok { ret et }
        out.fit.theta = t1[0usize..1usize]
        out.fit.thfit = t1[0usize..1usize]
    } else {
        // the refit by dsidr0 on the sum of 10^theta Q of the last weighted kernels
        var k = 0usize
        while k < nq {
            let wgt = pow10(th[k])
            var t = 0usize
            while t < n * n {
                qsum[t] += wgt * qw[k * n * n + t]
                t += 1usize
            }
            k += 1usize
        }
        try sspreg0(a, sw, qsum, yw, n, n0, method, varht, &fit)
        out.fit = fit
        out.fit.theta = thr
        out.fit.thfit = th
    }
    out.w = wt
    out.eta = eta
    out.iter = iter
    ret ok
}

// ---- ssanova with the approximate basis (sspreg1, mspreg1): the penalised regression on cbind(s, r) with the Fortran reg (LINPACK dchdc pivoted Cholesky) ----

type RegOut = struct { score: f64, varht: f64, rss: f64, trc: f64, rkv: usize, hat: []f64 }

// dchdc with the first n0 columns forced to lead (they already are) and the rest pivoted on the largest diagonal; jpvt gets the permutation (1-based), the return value is the rank
fn dchdc(v: []f64, p: usize, n0: usize, jpvt: []usize, work: []f64) -> usize {
    var k = 1usize
    while k <= p {
        jpvt[k - 1usize] = k
        k += 1usize
    }
    let pl = n0 + 1usize
    let pu = p
    k = 1usize
    while k <= p {
        var maxdia = v[cm(k, k, p)]
        var maxl = k
        if k >= pl && k < pu {
            var l = k + 1usize
            while l <= pu {
                if v[cm(l, l, p)] > maxdia {
                    maxdia = v[cm(l, l, p)]
                    maxl = l
                }
                l += 1usize
            }
        }
        if !(maxdia > 0.0f64) { ret k - 1usize }
        if k != maxl {
            var r = 1usize
            while r < k {
                let t = v[cm(r, k, p)]
                v[cm(r, k, p)] = v[cm(r, maxl, p)]
                v[cm(r, maxl, p)] = t
                r += 1usize
            }
            v[cm(maxl, maxl, p)] = v[cm(k, k, p)]
            v[cm(k, k, p)] = maxdia
            let jp = jpvt[maxl - 1usize]
            jpvt[maxl - 1usize] = jpvt[k - 1usize]
            jpvt[k - 1usize] = jp
        }
        work[k - 1usize] = math.sqrt[f64](v[cm(k, k, p)])
        v[cm(k, k, p)] = work[k - 1usize]
        var j = k + 1usize
        while j <= p {
            if k != maxl {
                if j < maxl {
                    let t = v[cm(k, j, p)]
                    v[cm(k, j, p)] = v[cm(j, maxl, p)]
                    v[cm(j, maxl, p)] = t
                } else {
                    if j != maxl {
                        let t = v[cm(k, j, p)]
                        v[cm(k, j, p)] = v[cm(maxl, j, p)]
                        v[cm(maxl, j, p)] = t
                    }
                }
            }
            v[cm(k, j, p)] = v[cm(k, j, p)] / work[k - 1usize]
            work[j - 1usize] = v[cm(k, j, p)]
            let temp = 0.0f64 - v[cm(k, j, p)]
            var i = k + 1usize
            while i <= j {
                v[cm(i, j, p)] += temp * work[i - 1usize]
                i += 1usize
            }
            j += 1usize
        }
        k += 1usize
    }
    ret p
}

// dtrsl job 11: v' x = b for the upper triangular v (p by p)
fn dtrsl_t(v: []const f64, p: usize, b: []f64, ob: usize) {
    b[ob] = b[ob] / v[cm(1usize, 1usize, p)]
    var j = 2usize
    while j <= p {
        b[ob + j - 1usize] = (b[ob + j - 1usize] - ddot(v, cm(1usize, j, p), 1usize, b, ob, 1usize, j - 1usize)) / v[cm(j, j, p)]
        j += 1usize
    }
}

// reg: sr is nobs by nn = n0 + nxi, qk the nxi by nxi penalty; method 1 'u', 2 'v'. dcf (nn, original column order) and v (nn by nn) are written to the caller's buffers.
// reg.f method 3 (GML): rss = y'(y - f), the n0 columns of s are Householder-reduced out of the kernel columns, and the score is
// rss/nobs * exp(trc/(nobs-n0)) with trc the log determinant ratio of (Q + R2'R2) to Q over the rkv - n0 largest eigenvalues
fn gml_score(a: *mem.Arena, sr: []const f64, nobs: usize, n0: usize, qk: []const f64, nxi: usize, y: []const f64, dcf: []const f64, rkv: usize, out: *RegOut) -> err {
    let nn = n0 + nxi
    let (w, e1) = zeros(a, nobs * nn)
    let (col, e2) = zeros(a, nobs)
    let (qraux, e3) = zeros(a, nn)
    let (wk, e4) = zeros(a, nn)
    let (jp, e5) = mem.alloc[usize](a, nn + 1usize)
    let (m1, e6) = zeros(a, nxi * nxi)
    let (m2, e7) = zeros(a, nxi * nxi)
    let (ev1, e8) = zeros(a, nxi)
    let (ev2, e9) = zeros(a, nxi)
    let (zz, e10) = zeros(a, nxi * nxi)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    var rss = 0.0f64
    var i = 1usize
    while i <= nobs {
        var f = 0.0f64
        var j = 1usize
        while j <= nn {
            f += sr[(j - 1usize) * nobs + i - 1usize] * dcf[j - 1usize]
            j += 1usize
        }
        rss += y[i - 1usize] * (y[i - 1usize] - f)
        i += 1usize
    }
    var t = 0usize
    while t < nobs * nn {
        w[t] = sr[t]
        t += 1usize
    }
    if n0 > 0usize {
        dqrdc(w, nobs, n0, qraux, jp, wk)
        i = 1usize
        while i <= nxi {
            t = 0usize
            while t < nobs {
                col[t] = w[(n0 + i - 1usize) * nobs + t]
                t += 1usize
            }
            qty(w, 0usize, nobs, nobs, n0, qraux, 0usize, col, 0usize)
            t = 0usize
            while t < nobs {
                w[(n0 + i - 1usize) * nobs + t] = col[t]
                t += 1usize
            }
            i += 1usize
        }
    }
    i = 1usize
    while i <= nxi {
        var j = 1usize
        while j <= nxi {
            m2[cm(i, j, nxi)] = qk[cm(i, j, nxi)]
            m1[cm(i, j, nxi)] = qk[cm(i, j, nxi)] + ddot(w, (n0 + i - 1usize) * nobs + n0, 1usize, w, (n0 + j - 1usize) * nobs + n0, 1usize, nobs - n0)
            j += 1usize
        }
        i += 1usize
    }
    try sy.dsyevr_all(a, m1, nxi, ev1, zz)
    try sy.dsyevr_all(a, m2, nxi, ev2, zz)
    var trc = 0.0f64
    i = 1usize
    while i + n0 <= rkv {
        trc += math.log[f64](ev1[nxi - i]) - math.log[f64](ev2[nxi - i])
        i += 1usize
    }
    out.rss = rss / f64(nobs)
    out.score = rss / f64(nobs) * math.exp[f64](trc / f64(nobs - n0))
    out.varht = rss / f64(nobs - n0)
    ret ok
}

fn reg_fit(a: *mem.Arena, sr: []const f64, nobs: usize, n0: usize, qk: []const f64, nxi: usize, y: []const f64, method: usize, alpha: f64, varht_in: f64, dcf: []f64, vout: []f64, jpo: []usize, out: *RegOut) -> err {
    let nn = n0 + nxi
    let (mu, e1) = zeros(a, nn)
    let (work, e2) = zeros(a, nn + nobs)
    let (jp, e3) = mem.alloc[usize](a, nn + 1usize)
    let (tmp, e4) = zeros(a, nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    let v = vout
    var i = 1usize
    while i <= nn {
        mu[i - 1usize] = ddot(sr, (i - 1usize) * nobs, 1usize, y, 0usize, 1usize, nobs)
        var j = i
        while j <= nn {
            v[cm(i, j, nn)] = ddot(sr, (i - 1usize) * nobs, 1usize, sr, (j - 1usize) * nobs, 1usize, nobs)
            if i > n0 { v[cm(i, j, nn)] += qk[cm(i - n0, j - n0, nxi)] }
            j += 1usize
        }
        i += 1usize
    }
    var rkv = dchdc(v, nn, n0, jp, work)
    i = 0usize
    while i < nn {
        jpo[i] = jp[i]
        i += 1usize
    }
    i = 1usize
    let mchpr = 2.0f64 * eps_half()
    var jm = 1usize
    if rkv > n0 { jm = idamax(v, cm(n0 + 1usize, n0 + 1usize, nn), nn + 1usize, rkv - n0) }
    while rkv > 1usize && v[cm(rkv, rkv, nn)] < v[cm(n0 + jm, n0 + jm, nn)] * math.sqrt[f64](mchpr) { rkv -= 1usize }
    i = rkv + 1usize
    while i <= nn {
        v[cm(i, i, nn)] = v[cm(jm, jm, nn)]
        var r = rkv + 1usize
        while r < i {
            v[cm(r, i, nn)] = 0.0f64
            r += 1usize
        }
        i += 1usize
    }
    // coefficients: permute (job 0), v' x = b, zero past the rank, v x = b, unpermute (job 1)
    i = 1usize
    while i <= nn {
        tmp[i - 1usize] = mu[jp[i - 1usize] - 1usize]
        i += 1usize
    }
    dtrsl_t(v, nn, tmp, 0usize)
    i = rkv + 1usize
    while i <= nn {
        tmp[i - 1usize] = 0.0f64
        i += 1usize
    }
    dtrsl_up(v, 0usize, nn, nn, tmp, 0usize)
    i = 1usize
    while i <= nn {
        dcf[jp[i - 1usize] - 1usize] = tmp[i - 1usize]
        i += 1usize
    }
    if method == 3usize {
        out.rkv = rkv
        out.trc = 0.0f64
        try gml_score(a, sr, nobs, n0, qk, nxi, y, dcf, rkv, out)
        ret ok
    }
    // residuals and the trace of the smoother
    var rss = 0.0f64
    i = 1usize
    while i <= nobs {
        var f = 0.0f64
        var j = 1usize
        while j <= nn {
            f += sr[(j - 1usize) * nobs + i - 1usize] * dcf[j - 1usize]
            j += 1usize
        }
        let rsd = y[i - 1usize] - f
        rss += rsd * rsd
        i += 1usize
    }
    rss = rss / f64(nobs)
    var trc = 0.0f64
    i = 1usize
    while i <= nobs {
        var j = 1usize
        while j <= nn {
            tmp[j - 1usize] = sr[(jp[j - 1usize] - 1usize) * nobs + i - 1usize]
            j += 1usize
        }
        dtrsl_t(v, nn, tmp, 0usize)
        let hi = absf(ddot(tmp, 0usize, 1usize, tmp, 0usize, 1usize, nn))
        if out.hat.len == nobs { out.hat[i - 1usize] = hi }
        trc += hi
        i += 1usize
    }
    trc = trc / f64(nobs)
    out.rss = rss
    out.trc = trc
    out.rkv = rkv
    out.varht = varht_in
    if method == 2usize {
        out.score = rss / ((1.0f64 - alpha * trc) * (1.0f64 - alpha * trc))
        out.varht = rss / (1.0f64 - trc)
    } else {
        out.score = rss + 2.0f64 * varht_in * alpha * trc
    }
    ret ok
}

// nlm0 of the package: 3-point parabola with a golden section safeguard on [lo, hi]
type Nlm0 = struct { est: f64, fv: f64 }

fn nlm0[Ctx: type](c: *Ctx, f: fn(*Ctx, f64) -> f64, lo: f64, hi: f64) -> Nlm0 { ret nlm0p[Ctx](c, f, lo, hi, 0.0000001f64) }

fn nlm0p[Ctx: type](c: *Ctx, f: fn(*Ctx, f64) -> f64, lo: f64, hi: f64, prec: f64) -> Nlm0 {
    var res: Nlm0 = zero
    let ratio = 2.0f64 / (math.sqrt[f64](5.0f64) + 1.0f64)
    var ll = lo
    var uu = hi
    if uu < ll {
        ll = hi
        uu = lo
    }
    if uu - ll < prec {
        let sol = (ll + uu) / 2.0f64
        res.est = sol
        res.fv = f(c, sol)
        ret res
    }
    var ml = uu - ratio * (uu - ll)
    var mu = ll + ratio * (uu - ll)
    var uf = f(c, uu)
    var mf = f(c, mu)
    var mlf = f(c, ml)
    var lf = f(c, ll)
    var running = true
    while running {
        var dl = 0.0f64
        var sl = 0.0f64
        var dld = 0.0f64
        var du = 0.0f64
        var dud = 0.0f64
        if lf < uf {
            dl = ml - ll
            sl = ml + ll
            dld = (mlf - lf) / dl
            du = mu - ml
            dud = (mf - mlf) / du
        } else {
            dl = mu - ml
            sl = mu + ml
            dld = (mf - mlf) / dl
            du = uu - mu
            dud = (uf - mf) / du
        }
        let aa = (dud - dld) / (dl + du)
        let bb = dld - aa * sl
        var nx = hi
        if lo > hi { nx = lo }
        if !(aa <= 0.0f64) { nx = 0.0f64 - bb / 2.0f64 / aa }
        var mm = 0.0f64
        var mmf = 0.0f64
        if mlf < mf {
            uu = mu
            uf = mf
            mm = ml
            mmf = mlf
        } else {
            ll = ml
            lf = mlf
            mm = mu
            mmf = mf
        }
        let rl = mm - ll
        let ru = uu - mm
        var delta = absf(nx - ll)
        if absf(nx - mm) < delta { delta = absf(nx - mm) }
        if absf(nx - uu) < delta { delta = absf(nx - uu) }
        if nx < ll || nx > uu || delta < prec {
            if ru > rl { nx = uu - ratio * ru } else { nx = ll + ratio * rl }
        }
        let nf = f(c, nx)
        if nx < mm {
            ml = nx
            mlf = nf
            mu = mm
            mf = mmf
        } else {
            ml = mm
            mlf = mmf
            mu = nx
            mf = nf
        }
        if rl + ru < 0.5f64 && absf(mm - nx) < math.sqrt[f64](prec) {
            if nf < mmf {
                res.est = nx
                res.fv = nf
            } else {
                res.est = mm
                res.fv = mmf
            }
            running = false
        }
    }
    ret res
}

type SeAux = struct { vec: []f64, val: []f64, rkq: usize, wm: []f64 }

type Ss1 = struct {
    c: []f64, d: []f64, theta: []f64, nlambda: f64, score: f64, varht: f64, se: SeAux,
    v: []f64, jp: []usize, rkv: usize, sw: []const f64, rw: []f64, qm: []f64
}

type Cv1 = struct {
    a: *mem.Arena, sr: []f64, nobs: usize, n0: usize, nxi: usize, qb: []const f64, y: []const f64, method: usize, alpha: f64, varht: f64,
    theta: f64, logla0: f64, dcf: []f64, v: []f64, jp: []usize, ro: RegOut, score: f64
}

fn cv1(c: *Cv1, lambda: f64) -> f64 {
    let lb = mem.mark(c.a)
    let nxi = c.nxi
    let (qk, e) = zeros(c.a, nxi * nxi)
    if e != ok { mem.reset(c.a, lb)
        ret 0.0f64 / 0.0f64 }
    let sc = pow10(lambda + c.theta)
    var t = 0usize
    while t < nxi * nxi {
        qk[t] = sc * c.qb[t]
        t += 1usize
    }
    var ro: RegOut = zero
    let re = reg_fit(c.a, c.sr, c.nobs, c.n0, qk, nxi, c.y, c.method, c.alpha, c.varht, c.dcf, c.v, c.jp, &ro)
    c.ro = ro
    var score = ro.score
    var awk = (c.logla0 - lambda - 5.0f64) * (3.0f64 - c.alpha) + c.alpha
    if c.logla0 - lambda - 5.0f64 < 0.0f64 { awk = c.alpha }
    if awk > 3.0f64 { awk = 3.0f64 }
    if awk > c.alpha {
        if c.method == 1usize { score = score + (awk - c.alpha) * 2.0f64 * c.varht * ro.trc }
        if c.method == 2usize { score = ro.rss / ((1.0f64 - awk * ro.trc) * (1.0f64 - awk * ro.trc)) }
    }
    mem.reset(c.a, lb)
    if re != ok { ret 0.0f64 / 0.0f64 }
    c.score = ro.score
    ret score
}

fn sumsq(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * x[i]
        i += 1usize
    }
    ret s
}

// sspreg1: s (nobs by n0), r (nobs by nxi), q = r[id.basis, ] (nxi by nxi); method 1 'u', 2 'v'
fn sspreg1(a: *mem.Arena, s: []const f64, r: []const f64, q: []const f64, y: []const f64, nobs: usize, n0: usize, nxi: usize, method: usize, alpha: f64, varht: f64, out: *Ss1) -> err {
    let nn = n0 + nxi
    let tmp = sumsq(r[0usize..nobs * nxi])
    let theta = log10f(sumsq(s[0usize..nobs * n0]) / f64(n0) / tmp * f64(nxi)) / 2.0f64
    var trq = 0.0f64
    var i = 0usize
    while i < nxi {
        trq += q[i + i * nxi]
        i += 1usize
    }
    let logla0 = log10f(tmp / trq) + theta
    let (sr, e1) = zeros(a, nobs * nn)
    let (dcf, e2) = zeros(a, nn)
    let (vv, e3) = zeros(a, nn * nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    i = 0usize
    while i < nobs * n0 {
        sr[i] = s[i]
        i += 1usize
    }
    let th10 = pow10(theta)
    i = 0usize
    while i < nobs * nxi {
        sr[nobs * n0 + i] = th10 * r[i]
        i += 1usize
    }
    var cv: Cv1 = zero
    cv.a = a
    cv.sr = sr
    cv.nobs = nobs
    cv.n0 = n0
    cv.nxi = nxi
    cv.qb = q
    cv.y = y
    cv.method = method
    cv.alpha = alpha
    cv.varht = varht
    cv.theta = theta
    cv.logla0 = logla0
    cv.dcf = dcf
    cv.v = vv
    let (jpb, ejp) = mem.alloc[usize](a, nn + 1usize)
    if ejp != ok { ret ejp }
    cv.jp = jpb
    var la = logla0
    let mn0 = logla0 - 6.0f64
    let mx0 = logla0 + 6.0f64
    var est = la
    var going = true
    while going {
        var mn = la - 1.0f64
        if mn0 > mn { mn = mn0 }
        var mx = la + 1.0f64
        if mx0 < mx { mx = mx0 }
        let z = nlm0[Cv1](&cv, cv1, mn, mx)
        est = z.est
        var m1 = est - mn
        if mx - est < m1 { m1 = mx - est }
        var m2 = est - mn0
        if mx0 - est < m2 { m2 = mx0 - est }
        if m1 >= 0.1f64 || m2 < 0.1f64 { going = false } else { la = est }
    }
    let jk = cv1(&cv, est)
    if jk != jk { ret Indefinite }
    let (cc, e4) = zeros(a, nxi)
    let (dd, e5) = zeros(a, n0)
    let (th, e6) = zeros(a, 1usize)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    i = 0usize
    while i < nxi {
        cc[i] = dcf[n0 + i]
        i += 1usize
    }
    i = 0usize
    while i < n0 {
        dd[i] = dcf[i]
        i += 1usize
    }
    th[0usize] = theta
    out.c = cc
    out.d = dd
    out.theta = th[0usize..1usize]
    out.nlambda = est
    out.score = cv.ro.score
    out.varht = cv.ro.varht
    let (rwo, ew1) = zeros(a, nobs * nxi)
    let (qmo, ew2) = zeros(a, nxi * nxi)
    if ew1 != ok { ret ew1 }
    if ew2 != ok { ret ew2 }
    i = 0usize
    while i < nobs * nxi {
        rwo[i] = th10 * r[i]
        i += 1usize
    }
    i = 0usize
    while i < nxi * nxi {
        qmo[i] = th10 * q[i]
        i += 1usize
    }
    out.v = vv
    out.jp = jpb
    out.rkv = cv.ro.rkv
    out.sw = s
    out.rw = rwo
    out.qm = qmo
    ret ok
}

type Cvm = struct {
    a: *mem.Arena, s: []const f64, rs: []const f64, id: []const usize, nobs: usize, n0: usize, nxi: usize, nq: usize, y: []const f64,
    method: usize, alpha: f64, varht: f64, nlambda: f64, logth0: []f64, rwk: []f64, thold: []f64, dcf: []f64, v: []f64, ro: RegOut,
    scale: f64, shift: f64, w: []const f64, jp: []usize
}

fn cvm(c: *Cvm, theta: []const f64) -> f64 {
    let lb = mem.mark(c.a)
    let nobs = c.nobs
    let nxi = c.nxi
    let nq = c.nq
    let nn = c.n0 + nxi
    let (r0, e1) = zeros(c.a, nobs * nxi)
    let (sr, e2) = zeros(c.a, nobs * nn)
    let (qk, e3) = zeros(c.a, nxi * nxi)
    if e1 != ok || e2 != ok || e3 != ok {
        mem.reset(c.a, lb)
        ret 0.0f64 / 0.0f64
    }
    var nch = 0usize
    var i = 0usize
    while i < nq {
        if theta[i] != c.thold[i] { nch += 1usize }
        i += 1usize
    }
    var t = 0usize
    if nch == nq {
        i = 0usize
        while i < nq {
            let w = pow10(theta[i])
            t = 0usize
            while t < nobs * nxi {
                r0[t] += w * c.rs[i * nobs * nxi + t]
                t += 1usize
            }
            i += 1usize
        }
        t = 0usize
        while t < nobs * nxi {
            c.rwk[t] = r0[t]
            t += 1usize
        }
        i = 0usize
        while i < nq {
            c.thold[i] = theta[i]
            i += 1usize
        }
    } else {
        t = 0usize
        while t < nobs * nxi {
            r0[t] = c.rwk[t]
            t += 1usize
        }
        i = 0usize
        while i < nq {
            if theta[i] != c.thold[i] {
                let tw = (pow10(theta[i] - c.thold[i]) - 1.0f64) * pow10(c.thold[i])
                t = 0usize
                while t < nobs * nxi {
                    r0[t] += tw * c.rs[i * nobs * nxi + t]
                    t += 1usize
                }
            }
            i += 1usize
        }
    }
    let nl = pow10(c.nlambda)
    var j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            qk[i + j * nxi] = nl * r0[c.id[i] + j * nobs]
            i += 1usize
        }
        j += 1usize
    }
    t = 0usize
    while t < nobs * c.n0 {
        sr[t] = c.s[t]
        t += 1usize
    }
    t = 0usize
    while t < nobs * nxi {
        sr[nobs * c.n0 + t] = r0[t]
        if c.w.len > 0usize { sr[nobs * c.n0 + t] = c.w[t % nobs] * r0[t] }
        t += 1usize
    }
    var ro: RegOut = zero
    let re = reg_fit(c.a, sr, nobs, c.n0, qk, nxi, c.y, c.method, c.alpha, c.varht, c.dcf, c.v, c.jp, &ro)
    c.ro = ro
    var score = ro.score
    var mx = 0.0f64
    i = 0usize
    while i < nq {
        let u = theta[i] - c.logth0[i] - 5.0f64
        if u > mx { mx = u }
        i += 1usize
    }
    var awk = mx * (3.0f64 - c.alpha) + c.alpha
    if awk > 3.0f64 { awk = 3.0f64 }
    if awk > c.alpha {
        if c.method == 1usize { score = score + (awk - c.alpha) * 2.0f64 * c.varht * ro.trc }
        if c.method == 2usize { score = ro.rss / ((1.0f64 - awk * ro.trc) * (1.0f64 - awk * ro.trc)) }
    }
    mem.reset(c.a, lb)
    if re != ok { ret 0.0f64 / 0.0f64 }
    ret score
}

fn cvm_wk(c: *Cvm, theta: []const f64) -> f64 { ret c.scale * cvm(c, theta) + c.shift }

// mspreg1: rs holds the nq kernels r_i (nobs by nxi) one after the other, id the 0-based rows of the basis; method 1 'u', 2 'v'
fn mspreg1(a: *mem.Arena, s: []const f64, rs: []const f64, id: []const usize, nq: usize, y: []const f64, nobs: usize, n0: usize, nxi: usize, method: usize, alpha: f64, varht: f64, skip: bool, out: *Ss1) -> err {
    var w: []const f64 = zero
    var nofix: []const f64 = zero
    try mspreg1w(a, s, rs, id, nq, y, w, nobs, n0, nxi, method, alpha, varht, skip, nofix, out)
    ret ok
}

// row scaled copy w[i] m[i + j nobs]
fn wscale(a: *mem.Arena, w: []const f64, m: []const f64, nobs: usize, nc: usize) -> ([]f64, err) {
    let (o, e) = zeros(a, nobs * nc)
    if e != ok { ret (o, e) }
    var j = 0usize
    while j < nc {
        var i = 0usize
        while i < nobs {
            o[i + j * nobs] = w[i] * m[i + j * nobs]
            i += 1usize
        }
        j += 1usize
    }
    ret (o, ok)
}

// sspreg1 with case weights w (empty: none): s, r and y are scaled by w, the penalty q is not
fn sspreg1w(a: *mem.Arena, s: []const f64, r: []const f64, q: []const f64, y: []const f64, w: []const f64, nobs: usize, n0: usize, nxi: usize, method: usize, alpha: f64, varht: f64, out: *Ss1) -> err {
    if w.len == 0usize {
        try sspreg1(a, s, r, q, y, nobs, n0, nxi, method, alpha, varht, out)
        ret ok
    }
    let (s2, e1) = wscale(a, w, s, nobs, n0)
    let (r2, e2) = wscale(a, w, r, nobs, nxi)
    let (y2, e3) = wscale(a, w, y, nobs, 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    try sspreg1(a, s2, r2, q, y2, nobs, n0, nxi, method, alpha, varht, out)
    ret ok
}

// mspreg1 with case weights w (empty: none)
fn mspreg1w(a: *mem.Arena, s: []const f64, rs: []const f64, id: []const usize, nq: usize, y: []const f64, w: []const f64, nobs: usize, n0: usize, nxi: usize, method: usize, alpha: f64, varht: f64, skip: bool, fix: []const f64, out: *Ss1) -> err {
    let sz = nobs * nxi
    let (theta, e1) = zeros(a, nq)
    let (rwk, e2) = zeros(a, sz)
    let (q1, e3) = zeros(a, nxi * nxi)
    let (logth0, e4) = zeros(a, nq)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < nq {
        var tr = 0.0f64
        var j = 0usize
        while j < nxi {
            tr += rs[i * sz + id[j] + j * nobs]
            j += 1usize
        }
        theta[i] = 0.0f64 - log10f(tr)
        i += 1usize
    }
    var t = 0usize
    i = 0usize
    while i < nq {
        let wq = pow10(theta[i])
        t = 0usize
        while t < sz {
            rwk[t] += wq * rs[i * sz + t]
            t += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            q1[i + j * nxi] = rwk[id[i] + j * nobs]
            i += 1usize
        }
        j += 1usize
    }
    var z: Ss1 = zero
    try sspreg1w(a, s, rwk, q1, y, w, nobs, n0, nxi, method, alpha, varht, &z)
    i = 0usize
    while i < nq {
        theta[i] = theta[i] + z.theta[0usize]
        i += 1usize
    }
    // theta adjustment with the norms of the fit
    t = 0usize
    while t < sz {
        rwk[t] = 0.0f64
        t += 1usize
    }
    i = 0usize
    while i < nq {
        var cq = 0.0f64
        j = 0usize
        while j < nxi {
            var rc = 0.0f64
            var k = 0usize
            while k < nxi {
                rc += rs[i * sz + id[j] + k * nobs] * z.c[k]
                k += 1usize
            }
            cq += z.c[j] * rc
            j += 1usize
        }
        theta[i] = 2.0f64 * theta[i] + log10f(cq)
        let wq = pow10(theta[i])
        t = 0usize
        while t < sz {
            rwk[t] += wq * rs[i * sz + t]
            t += 1usize
        }
        i += 1usize
    }
    var trq = 0.0f64
    j = 0usize
    while j < nxi {
        trq += rwk[id[j] + j * nobs]
        j += 1usize
    }
    var qsq = sumsq(rwk)
    if w.len > 0usize {
        qsq = 0.0f64
        t = 0usize
        while t < sz {
            let wv = w[t % nobs] * rwk[t]
            qsq += wv * wv
            t += 1usize
        }
    }
    let logla0 = log10f(qsq / trq)
    i = 0usize
    while i < nq {
        logth0[i] = theta[i] - logla0
        i += 1usize
    }
    j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            q1[i + j * nxi] = rwk[id[i] + j * nobs]
            i += 1usize
        }
        j += 1usize
    }
    var z2: Ss1 = zero
    try sspreg1w(a, s, rwk, q1, y, w, nobs, n0, nxi, method, alpha, varht, &z2)
    var nlambda = z2.nlambda
    i = 0usize
    while i < nq {
        logth0[i] = logth0[i] + nlambda
        theta[i] = theta[i] + z2.theta[0usize]
        i += 1usize
    }
    // fix = R's converged [nlambda, theta..] of this call: the fit at those values, no search (the nlm search stops on rounding-dependent points)
    if fix.len > 0usize {
        nlambda = fix[0usize]
        i = 0usize
        while i < nq {
            theta[i] = fix[1usize + i]
            i += 1usize
        }
    }
    if skip {
        // skip.iter = TRUE: the fit at the starting theta
        out.c = z2.c
        out.d = z2.d
        out.theta = theta
        out.nlambda = nlambda
        out.score = z2.score
        out.varht = z2.varht
        out.v = z2.v
        out.jp = z2.jp
        out.rkv = z2.rkv
        out.sw = z2.sw
        out.rw = z2.rw
        out.qm = z2.qm
        ret ok
    }
    // the theta search
    let nn = n0 + nxi
    let (rw2, e5) = zeros(a, sz)
    let (thold, e6) = zeros(a, nq)
    let (dcf, e7) = zeros(a, nn)
    let (vv, e8) = zeros(a, nn * nn)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    i = 0usize
    while i < nq {
        let wq = pow10(theta[i])
        t = 0usize
        while t < sz {
            rw2[t] += wq * rs[i * sz + t]
            t += 1usize
        }
        thold[i] = theta[i]
        i += 1usize
    }
    var cx: Cvm = zero
    cx.a = a
    cx.s = s
    cx.y = y
    cx.w = w
    if w.len > 0usize {
        let (sw, ew1) = wscale(a, w, s, nobs, n0)
        let (yw, ew2) = wscale(a, w, y, nobs, 1usize)
        if ew1 != ok { ret ew1 }
        if ew2 != ok { ret ew2 }
        cx.s = sw
        cx.y = yw
    }
    cx.rs = rs
    cx.id = id
    cx.nobs = nobs
    cx.n0 = n0
    cx.nxi = nxi
    cx.nq = nq
    cx.method = method
    cx.alpha = alpha
    cx.varht = varht
    cx.nlambda = nlambda
    cx.logth0 = logth0
    cx.rwk = rw2
    cx.thold = thold
    cx.dcf = dcf
    cx.v = vv
    cx.scale = 1.0f64
    cx.shift = 0.0f64
    let (jpb, ejp) = mem.alloc[usize](a, nn + 1usize)
    if ejp != ok { ret ejp }
    cx.jp = jpb
    let tmp = absf(cvm(&cx, theta))
    if tmp < 1.0f64 && tmp > 0.0001f64 { cx.scale = 10.0f64 / tmp }
    if tmp < 0.0001f64 {
        cx.scale = 100.0f64
        cx.shift = 10.0f64
    }
    var counter = 0usize
    var searching = fix.len == 0usize
    while searching {
        let r = nlm.nlm[Cvm](a, &cx, cvm_wk, theta, 100usize, 7i64, 1.0f64)
        if r.code <= 3i64 { searching = false } else {
            counter += 1usize
            if counter >= 5usize { searching = false }
        }
    }
    let jk = cvm(&cx, theta)
    if jk != jk { ret Indefinite }
    let (cc, e9) = zeros(a, nxi)
    let (dd, e10) = zeros(a, n0)
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    i = 0usize
    while i < nxi {
        cc[i] = dcf[n0 + i]
        i += 1usize
    }
    i = 0usize
    while i < n0 {
        dd[i] = dcf[i]
        i += 1usize
    }
    out.c = cc
    out.d = dd
    out.theta = theta
    out.nlambda = nlambda
    out.score = cx.ro.score
    out.varht = cx.ro.varht
    // the inputs of regaux: the weighted design at the final theta and the penalty
    let (rfin, ef1) = zeros(a, sz)
    let (qfin, ef2) = zeros(a, nxi * nxi)
    if ef1 != ok { ret ef1 }
    if ef2 != ok { ret ef2 }
    i = 0usize
    while i < nq {
        let wq = pow10(theta[i])
        t = 0usize
        while t < sz {
            rfin[t] += wq * rs[i * sz + t]
            t += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            qfin[i + j * nxi] = rfin[id[i] + j * nobs]
            i += 1usize
        }
        j += 1usize
    }
    if w.len > 0usize {
        t = 0usize
        while t < sz {
            rfin[t] = w[t % nobs] * rfin[t]
            t += 1usize
        }
    }
    out.v = vv
    out.jp = jpb
    out.rkv = cx.ro.rkv
    out.sw = cx.s
    out.rw = rfin
    out.qm = qfin
    ret ok
}

// the posterior mean of an approximate fit: q1 (nq of m by nxi) the kernels between the new rows and the basis, s1 (m by n0)
fn predict1(f: *const Ss1, s1: []const f64, q1: []const f64, nq: usize, n0: usize, nxi: usize, m: usize, out: []f64) {
    var i = 0usize
    while i < m {
        var sm = 0.0f64
        var k = 0usize
        while k < nq {
            var rc = 0.0f64
            var j = 0usize
            while j < nxi {
                rc += q1[k * m * nxi + i + j * m] * f.c[j]
                j += 1usize
            }
            sm += pow10(f.theta[k]) * rc
            k += 1usize
        }
        var j = 0usize
        while j < n0 {
            sm += s1[i + j * m] * f.d[j]
            j += 1usize
        }
        out[i] = sm
        i += 1usize
    }
}

// spfix: the fit at a given theta (log10 weight of each of the nq kernels in rs, nobs by nxi one after the other) and nlambda, no search:
// R's converged values passed in, so the score, varht, c, d and everything built on them are the same least-squares problem as R's
fn spfix(a: *mem.Arena, s: []const f64, rs: []const f64, id: []const usize, nq: usize, y: []const f64, nobs: usize, n0: usize, nxi: usize, method: usize, alpha: f64, varht: f64, theta_in: []const f64, nlambda: f64, out: *Ss1) -> err {
    let sz = nobs * nxi
    let nn = n0 + nxi
    let (theta, e0) = zeros(a, nq)
    let (rk, e1) = zeros(a, sz)
    let (qk, e2) = zeros(a, nxi * nxi)
    let (qm, e3) = zeros(a, nxi * nxi)
    let (sr, e4) = zeros(a, nobs * nn)
    let (dcf, e5) = zeros(a, nn)
    let (vv, e6) = zeros(a, nn * nn)
    let (jpb, e7) = mem.alloc[usize](a, nn + 1usize)
    if e0 != ok { ret e0 }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var i = 0usize
    var t = 0usize
    while i < nq {
        theta[i] = theta_in[i]
        let wq = pow10(theta_in[i])
        t = 0usize
        while t < sz {
            rk[t] += wq * rs[i * sz + t]
            t += 1usize
        }
        i += 1usize
    }
    let nl = pow10(nlambda)
    var j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            qm[i + j * nxi] = rk[id[i] + j * nobs]
            qk[i + j * nxi] = nl * qm[i + j * nxi]
            i += 1usize
        }
        j += 1usize
    }
    t = 0usize
    while t < nobs * n0 {
        sr[t] = s[t]
        t += 1usize
    }
    t = 0usize
    while t < sz {
        sr[nobs * n0 + t] = rk[t]
        t += 1usize
    }
    var ro: RegOut = zero
    try reg_fit(a, sr, nobs, n0, qk, nxi, y, method, alpha, varht, dcf, vv, jpb, &ro)
    let (cc, e8) = zeros(a, nxi)
    let (dd, e9) = zeros(a, n0)
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    i = 0usize
    while i < nxi {
        cc[i] = dcf[n0 + i]
        i += 1usize
    }
    i = 0usize
    while i < n0 {
        dd[i] = dcf[i]
        i += 1usize
    }
    out.c = cc
    out.d = dd
    out.theta = theta
    out.nlambda = nlambda
    out.score = ro.score
    out.varht = ro.varht
    out.v = vv
    out.jp = jpb
    out.rkv = ro.rkv
    out.sw = s
    out.rw = rk
    out.qm = qm
    ret ok
}
