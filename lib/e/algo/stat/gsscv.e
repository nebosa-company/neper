// R package gss: gssanova itself (gssanova.R, family.cv.R): the cross-validated Kullback-Leibler fit over the sampled basis id.basis for the families
// binomial (1), Poisson (2), Gamma (3) and inverse Gaussian (4), with sspngreg (one kernel, nlm0 over log10 lambda) and mspngreg (several kernels, nlm over log10 theta).
// ngreg is the Newton iteration for fixed smoothing parameters with the exact line search of the package (nlm0 to 1e-3) and the cv score of the family.
//
// Not here: nbinomial, polr, weibull, lognorm and loglogis, offsets, case weights, random and partial terms.

use e.math
use e.mem
use e.algo.stat.gss as gss
use e.algo.stat.gssglm1 as g1
use e.algo.stat.gssnlm as nlm

error Diverged

fn fin(x: f64) -> bool { ret x - x == 0.0f64 }

fn devres(fam: usize, y: f64, eta: f64) -> f64 {
    if fam == 1usize {
        let odds = math.exp[f64](eta)
        var l1 = 0.0f64
        if y != 0.0f64 { l1 = math.log[f64](y * (1.0f64 + odds) / odds) }
        var l2 = 0.0f64
        if y != 1.0f64 { l2 = math.log[f64]((1.0f64 - y) * (1.0f64 + odds)) }
        ret 2.0f64 * (y * l1 + (1.0f64 - y) * l2)
    }
    if fam == 2usize {
        let lam = math.exp[f64](eta)
        var l1 = 0.0f64
        if y != 0.0f64 { l1 = math.log[f64](y / lam) }
        ret 2.0f64 * (y * l1 - (y - lam))
    }
    let mu = math.exp[f64](eta)
    if fam == 3usize { ret 2.0f64 * (0.0f64 - math.log[f64](y / mu) + (y - mu) / mu) }
    ret (y - mu) * (y - mu) / (y * (mu * mu))
}

fn devsum(fam: usize, y: []const f64, eta: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += devres(fam, y[i], eta[i])
        i += 1usize
    }
    ret s
}

// u of the mkdata.* functions (before the weight)
fn ufam(fam: usize, y: f64, eta: f64) -> f64 {
    let e = math.exp[f64](eta)
    if fam == 1usize { ret e / (1.0f64 + e) - y }
    if fam == 2usize { ret e - y }
    if fam == 3usize { ret 1.0f64 - y / e }
    ret (1.0f64 - y / e) / e
}

type NgCtx = struct {
    fam: usize, y: []const f64, sr: []const f64, n: usize, nn: usize, n0: usize, q: []const f64, nxi: usize,
    dcl: []f64, dcd: []f64, dcn: []f64, etan: []f64
}

fn devline(c: *NgCtx, x: f64) -> f64 {
    var j = 0usize
    while j < c.nn {
        c.dcn[j] = c.dcl[j] + x * c.dcd[j]
        j += 1usize
    }
    var i = 0usize
    while i < c.n {
        var sm = 0.0f64
        j = 0usize
        while j < c.nn {
            sm += c.sr[i + j * c.n] * c.dcn[j]
            j += 1usize
        }
        c.etan[i] = sm
        i += 1usize
    }
    var pen = 0.0f64
    var a = 0usize
    while a < c.nxi {
        var qc = 0.0f64
        var b = 0usize
        while b < c.nxi {
            qc += c.q[a + b * c.nxi] * c.dcn[c.n0 + b]
            b += 1usize
        }
        pen += c.dcn[c.n0 + a] * qc
        a += 1usize
    }
    ret devsum(c.fam, c.y, c.etan, c.n) + pen
}

// LAPACK dpstf2 (upper, tol < 0) as called by R's chol(pivot = TRUE): v is n by n column-major, piv gets the 1-based pivots, the result is the rank; the lower triangle is zeroed
fn pchol(v: []f64, n: usize, piv: []usize, work: []f64) -> usize {
    var i = 0usize
    while i < n {
        piv[i] = i + 1usize
        work[i] = 0.0f64
        work[n + i] = 0.0f64
        i += 1usize
    }
    var pvt = 1usize
    var ajj = v[0usize]
    i = 2usize
    while i <= n {
        if v[gss.cm(i, i, n)] > ajj {
            pvt = i
            ajj = v[gss.cm(i, i, n)]
        }
        i += 1usize
    }
    if !(ajj > 0.0f64) { ret 0usize }
    let dstop = f64(n) * 1.1102230246251565e-16f64 * ajj
    var rank = n
    var j = 1usize
    var going = true
    while going && j <= n {
        i = j
        while i <= n {
            if j > 1usize { work[i - 1usize] += v[gss.cm(j - 1usize, i, n)] * v[gss.cm(j - 1usize, i, n)] }
            work[n + i - 1usize] = v[gss.cm(i, i, n)] - work[i - 1usize]
            i += 1usize
        }
        var halt = false
        if j > 1usize {
            pvt = j
            var best = work[n + j - 1usize]
            i = j + 1usize
            while i <= n {
                if work[n + i - 1usize] > best {
                    best = work[n + i - 1usize]
                    pvt = i
                }
                i += 1usize
            }
            ajj = work[n + pvt - 1usize]
            if ajj <= dstop || ajj != ajj {
                v[gss.cm(j, j, n)] = ajj
                rank = j - 1usize
                halt = true
            }
        }
        if halt {
            going = false
        } else {
            if j != pvt {
                v[gss.cm(pvt, pvt, n)] = v[gss.cm(j, j, n)]
                var k = 1usize
                while k < j {
                    let t = v[gss.cm(k, j, n)]
                    v[gss.cm(k, j, n)] = v[gss.cm(k, pvt, n)]
                    v[gss.cm(k, pvt, n)] = t
                    k += 1usize
                }
                k = pvt + 1usize
                while k <= n {
                    let t = v[gss.cm(j, k, n)]
                    v[gss.cm(j, k, n)] = v[gss.cm(pvt, k, n)]
                    v[gss.cm(pvt, k, n)] = t
                    k += 1usize
                }
                k = j + 1usize
                while k < pvt {
                    let t = v[gss.cm(j, k, n)]
                    v[gss.cm(j, k, n)] = v[gss.cm(k, pvt, n)]
                    v[gss.cm(k, pvt, n)] = t
                    k += 1usize
                }
                let tw = work[j - 1usize]
                work[j - 1usize] = work[pvt - 1usize]
                work[pvt - 1usize] = tw
                let tp = piv[j - 1usize]
                piv[j - 1usize] = piv[pvt - 1usize]
                piv[pvt - 1usize] = tp
            }
            ajj = math.sqrt[f64](ajj)
            v[gss.cm(j, j, n)] = ajj
            if j < n {
                var col = j + 1usize
                while col <= n {
                    var tm = 0.0f64
                    var k = 1usize
                    while k < j {
                        tm += v[gss.cm(k, col, n)] * v[gss.cm(k, j, n)]
                        k += 1usize
                    }
                    v[gss.cm(j, col, n)] = v[gss.cm(j, col, n)] + (0.0f64 - 1.0f64) * tm
                    col += 1usize
                }
                let rj = 1.0f64 / ajj
                col = j + 1usize
                while col <= n {
                    v[gss.cm(j, col, n)] = v[gss.cm(j, col, n)] * rj
                    col += 1usize
                }
            }
            j += 1usize
        }
    }
    var c = 1usize
    while c <= n {
        var r = c + 1usize
        while r <= n {
            v[gss.cm(r, c, n)] = 0.0f64
            r += 1usize
        }
        c += 1usize
    }
    ret rank
}

type Cvv = struct { score: f64, varht: f64 }

// the cv score of the family (family.cv.R) at eta with the hat diagonal and the residual mean square of the working fit; sr is the unweighted design, q the penalty
fn cvfam(a: *mem.Arena, fam: usize, y: []const f64, eta: []const f64, hat: []const f64, rss: f64, alpha: f64, sr: []const f64, q: []const f64, n: usize, nn: usize, n0: usize, nxi: usize, out: *Cvv) -> err {
    let nf = f64(n)
    var sh = 0.0f64
    var i = 0usize
    while i < n {
        sh += hat[i]
        i += 1usize
    }
    let aal = gss.absf(alpha)
    if fam == 1usize {
        var l = 0.0f64
        var a1 = 0.0f64
        var a2 = 0.0f64
        i = 0usize
        while i < n {
            let odds = math.exp[f64](eta[i])
            let p = odds / (1.0f64 + odds)
            let w = p / (1.0f64 + odds)
            l += y[i] * eta[i] - math.log[f64](1.0f64 + odds)
            a1 += hat[i] / w
            a2 += y[i] / (1.0f64 + odds)
            i += 1usize
        }
        out.score = (0.0f64 - l) / nf + aal * (a1 / (nf - sh)) * (a2 / nf)
        out.varht = 1.0f64
        ret ok
    }
    if fam == 3usize {
        var l = 0.0f64
        var a2 = 0.0f64
        i = 0usize
        while i < n {
            let mu = math.exp[f64](eta[i])
            let u = 1.0f64 - y[i] / mu
            l += y[i] / mu + eta[i]
            a2 += y[i] * u / mu
            i += 1usize
        }
        out.score = l / nf + alpha * (sh / (nf - sh)) * ((0.0f64 - a2) / nf)
        out.varht = rss / (1.0f64 - sh / nf)
        ret ok
    }
    if fam == 4usize {
        var l = 0.0f64
        var a1 = 0.0f64
        var a2 = 0.0f64
        i = 0usize
        while i < n {
            let mu = math.exp[f64](eta[i])
            let u = (1.0f64 - y[i] / mu) / mu
            let w = 1.0f64 / mu
            l += (y[i] / mu / 2.0f64 - 1.0f64) / mu
            a1 += hat[i] / w
            a2 += y[i] * u / mu / mu
            i += 1usize
        }
        out.score = l / nf + alpha * (a1 / (nf - sh)) * ((0.0f64 - a2) / nf)
        out.varht = rss / (1.0f64 - sh / nf)
        ret ok
    }
    // Poisson
    let (lam, e1) = gss.zeros(a, n)
    let (mu, e2) = gss.zeros(a, nn)
    let (mu2, e3) = gss.zeros(a, nn)
    let (v, e4) = gss.zeros(a, nn * nn)
    let (piv, e5) = mem.alloc[usize](a, nn + 1usize)
    let (wk, e6) = gss.zeros(a, 2usize * nn)
    let (xm, e7) = gss.zeros(a, nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var swl = 0.0f64
    var sy = 0.0f64
    var l = 0.0f64
    i = 0usize
    while i < n {
        lam[i] = math.exp[f64](eta[i])
        swl += lam[i]
        sy += y[i]
        l += y[i] * eta[i] - lam[i]
        i += 1usize
    }
    var j = 0usize
    while j < nn {
        var sm = 0.0f64
        var sm2 = 0.0f64
        i = 0usize
        while i < n {
            sm += lam[i] * sr[i + j * n]
            sm2 += y[i] * sr[i + j * n]
            i += 1usize
        }
        mu[j] = sm / swl
        mu2[j] = sm2 / sy
        j += 1usize
    }
    j = 0usize
    while j < nn {
        var k = 0usize
        while k < nn {
            var sm = 0.0f64
            i = 0usize
            while i < n {
                sm += sr[i + j * n] * (lam[i] * sr[i + k * n])
                i += 1usize
            }
            v[j + k * nn] = sm / swl - mu[j] * mu[k]
            if j >= n0 && k >= n0 { v[j + k * nn] += q[(j - n0) + (k - n0) * nxi] / sy }
            k += 1usize
        }
        j += 1usize
    }
    var rkv = pchol(v, nn, piv, wk)
    while rkv > 1usize && v[gss.cm(rkv, rkv, nn)] < v[0usize] * math.sqrt[f64](2.220446049250313e-16f64) { rkv -= 1usize }
    if rkv < nn {
        let d0 = v[0usize]
        var r = rkv + 1usize
        while r <= nn {
            var c = rkv + 1usize
            while c <= nn {
                v[gss.cm(r, c, nn)] = 0.0f64
                if r == c { v[gss.cm(r, c, nn)] = d0 }
                c += 1usize
            }
            r += 1usize
        }
    }
    var aux1 = 0.0f64
    i = 0usize
    while i < n {
        // v' x = row i of the centred design (pivoted), scaled by sqrt(y)
        var k = 1usize
        while k <= nn {
            let jj = piv[k - 1usize]
            var t = math.sqrt[f64](y[i]) * (sr[i + (jj - 1usize) * n] - mu2[jj - 1usize])
            var l2 = 1usize
            while l2 < k {
                t -= v[gss.cm(l2, k, nn)] * xm[l2 - 1usize]
                l2 += 1usize
            }
            xm[k - 1usize] = t / v[gss.cm(k, k, nn)]
            aux1 += xm[k - 1usize] * xm[k - 1usize]
            k += 1usize
        }
        i += 1usize
    }
    let aux2 = 1.0f64 / sy / (sy - 1.0f64)
    out.score = (0.0f64 - l) / sy + aal * aux1 * aux2
    out.varht = 1.0f64
    ret ok
}

type NgOut = struct { score: f64, varht: f64, rkv: usize }

// ngreg: dc is the start and gets the dc of the final working fit; vout, jpout, wout, etaout get the Cholesky factor, its pivots, the working weights and eta of that fit
fn ngreg(a: *mem.Arena, fam: usize, dc: []f64, sr: []const f64, n: usize, nn: usize, n0: usize, q: []const f64, nxi: usize, y: []const f64, alpha: f64, vout: []f64, jpout: []usize, wout: []f64, etaout: []f64, out: *NgOut) -> err {
    let (dcl, e1) = gss.zeros(a, nn)
    let (dcn, e2) = gss.zeros(a, nn)
    let (dcd, e3) = gss.zeros(a, nn)
    let (dls, e4) = gss.zeros(a, nn)
    let (eta, e5) = gss.zeros(a, n)
    let (etan, e6) = gss.zeros(a, n)
    let (ywk, e7) = gss.zeros(a, n)
    let (wt, e8) = gss.zeros(a, n)
    let (srw, e9) = gss.zeros(a, n * nn)
    let (hat, e10) = gss.zeros(a, n)
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
    var ctx: NgCtx = zero
    ctx.fam = fam
    ctx.y = y
    ctx.sr = sr
    ctx.n = n
    ctx.nn = nn
    ctx.n0 = n0
    ctx.q = q
    ctx.nxi = nxi
    ctx.dcl = dcl
    ctx.dcd = dcd
    ctx.dcn = dcn
    ctx.etan = etan
    var i = 0usize
    var j = 0usize
    while j < nn {
        dcl[j] = dc[j]
        j += 1usize
    }
    ctx.etan = eta
    // eta = sr dc and the penalised deviance (devline at 0 with dcd = 0)
    var dev = devline(&ctx, 0.0f64)
    ctx.etan = etan
    var flag = false
    var flag2 = false
    var iter = 0usize
    var looping = true
    var reset = false
    let (vv, ev) = gss.zeros(a, nn * nn)
    let (jpw, ej) = mem.alloc[usize](a, nn + 1usize)
    if ev != ok { ret ev }
    if ej != ok { ret ej }
    while looping {
        reset = false
        iter += 1usize
        i = 0usize
        while i < n {
            ywk[i] = 0.0f64
            i += 1usize
        }
        g1gss_mkdata(fam, y, eta, n, ywk, wt)
        // mumax = 2 max | sr' u + (0, q cc) |
        var mumax = 0.0f64
        j = 0usize
        while j < nn {
            var g = 0.0f64
            i = 0usize
            while i < n {
                g += sr[i + j * n] * (ufam(fam, y[i], eta[i]) * wt[i])
                i += 1usize
            }
            if j >= n0 {
                var b = 0usize
                while b < nxi {
                    g += q[(j - n0) + b * nxi] * dcl[n0 + b]
                    b += 1usize
                }
            }
            if gss.absf(g) > mumax || g != g { mumax = gss.absf(g) }
            j += 1usize
        }
        mumax = 2.0f64 * mumax
        var allfin = true
        i = 0usize
        while i < n {
            let w = math.sqrt[f64](wt[i])
            ywk[i] = w * ywk[i]
            if !fin(w) || !fin(ywk[i]) { allfin = false }
            j = 0usize
            while j < nn {
                srw[i + j * n] = w * sr[i + j * n]
                if !fin(srw[i + j * n]) { allfin = false }
                j += 1usize
            }
            i += 1usize
        }
        if !allfin {
            if flag { ret Diverged }
            j = 0usize
            while j < nn {
                dcl[j] = 0.0f64
                j += 1usize
            }
            i = 0usize
            while i < n {
                eta[i] = 0.0f64
                i += 1usize
            }
            dev = devsum(fam, y, eta, n)
            iter = 0usize
            flag = true
            reset = true
        }
        if !reset {
            var ro: gss.RegOut = zero
            try gss.reg_fit(a, srw, n, n0, q, nxi, ywk, 1usize, 1.0f64, 1.0f64, dls, vv, jpw, &ro)
            j = 0usize
            while j < nn {
                dcd[j] = dls[j] - dcl[j]
                j += 1usize
            }
            var devn = 0.0f64
            var inner = true
            while inner {
                devn = devline(&ctx, 1.0f64)
                if !fin(devn) {
                    j = 0usize
                    while j < nn {
                        dcd[j] = dcd[j] / 2.0f64
                        j += 1usize
                    }
                } else {
                    inner = false
                    var line = true
                    if !flag2 {
                        if devn - dev < 0.0000001f64 * (1.0f64 + gss.absf(dev)) { line = false }
                    }
                    if line {
                        let zz = gss.nlm0p[NgCtx](&ctx, devline, 0.0f64, 1.0f64, 0.001f64)
                        devn = devline(&ctx, zz.est)
                    }
                }
            }
            var disc0 = 0.0f64
            var d1 = 0.0f64
            var d2 = 0.0f64
            var sw = 0.0f64
            i = 0usize
            while i < n {
                let m1 = mumax / (1.0f64 + eta[i])
                let m2 = gss.absf(etan[i] - eta[i]) / (1.0f64 + eta[i])
                if i == 0usize || m1 * m1 > disc0 || m1 != m1 { disc0 = m1 * m1 }
                if m2 > disc0 || m2 != m2 { disc0 = m2 }
                let df = (eta[i] - etan[i]) / (1.0f64 + gss.absf(eta[i]))
                d1 += wt[i] * df * df
                sw += wt[i]
                i += 1usize
            }
            d2 = d1 / sw
            if !fin(d2) {
                if flag { ret Diverged }
                j = 0usize
                while j < nn {
                    dcl[j] = 0.0f64
                    j += 1usize
                }
                i = 0usize
                while i < n {
                    eta[i] = 0.0f64
                    i += 1usize
                }
                dev = devsum(fam, y, eta, n)
                iter = 0usize
                flag = true
            } else {
                j = 0usize
                while j < nn {
                    dcl[j] = dcn[j]
                    j += 1usize
                }
                i = 0usize
                while i < n {
                    eta[i] = etan[i]
                    i += 1usize
                }
                dev = devn
                var md = disc0
                if d2 < md { md = d2 }
                if md < 0.0000001f64 {
                    looping = false
                } else {
                    if iter > 30usize {
                        if !flag2 {
                            flag2 = true
                            iter = 0usize
                        } else {
                            looping = false
                        }
                    }
                }
            }
        }
    }
    // the working fit at the final eta: dc, the hat diagonal, the Cholesky factor
    g1gss_mkdata(fam, y, eta, n, ywk, wt)
    i = 0usize
    while i < n {
        let w = math.sqrt[f64](wt[i])
        ywk[i] = w * ywk[i]
        j = 0usize
        while j < nn {
            srw[i + j * n] = w * sr[i + j * n]
            j += 1usize
        }
        i += 1usize
    }
    var ro2: gss.RegOut = zero
    ro2.hat = hat[0usize..n]
    try gss.reg_fit(a, srw, n, n0, q, nxi, ywk, 1usize, 1.0f64, 1.0f64, dls, vout, jpout, &ro2)
    var cvo: Cvv = zero
    try cvfam(a, fam, y, eta, hat, ro2.rss, alpha, sr, q, n, nn, n0, nxi, &cvo)
    j = 0usize
    while j < nn {
        dc[j] = dls[j]
        j += 1usize
    }
    i = 0usize
    while i < n {
        wout[i] = wt[i]
        etaout[i] = eta[i]
        i += 1usize
    }
    out.score = cvo.score
    out.varht = cvo.varht
    out.rkv = ro2.rkv
    ret ok
}

fn g1gss_mkdata(fam: usize, y: []const f64, eta: []const f64, n: usize, ywk: []f64, wt: []f64) { gss.mkdata(fam, y, eta, n, ywk, wt) }

// ---- sspngreg: one kernel --------------------------------------------------------------------------------------------------------------------------------

type Sng = struct {
    a: *mem.Arena, fam: usize, s: []const f64, r: []const f64, q: []const f64, y: []const f64, n: usize, n0: usize, nxi: usize, nn: usize,
    alpha: f64, theta: f64, logla0: f64, sr: []f64, dc: []f64, vv: []f64, jp: []usize, w: []f64, eta: []f64, no: NgOut, bad: bool
}

fn cv_s(c: *Sng, lambda: f64) -> f64 {
    let lb = mem.mark(c.a)
    let (qk, e) = gss.zeros(c.a, c.nxi * c.nxi)
    if e != ok {
        mem.reset(c.a, lb)
        ret 0.0f64 / 0.0f64
    }
    let sc = math.pow[f64](10.0f64, lambda + c.theta)
    var t = 0usize
    while t < c.nxi * c.nxi {
        qk[t] = sc * c.q[t]
        t += 1usize
    }
    var awk = (c.logla0 - lambda - 5.0f64)
    if awk < 0.0f64 { awk = 0.0f64 }
    awk = awk * (3.0f64 - c.alpha) + c.alpha
    if awk > 3.0f64 { awk = 3.0f64 }
    var no: NgOut = zero
    let re = ngreg(c.a, c.fam, c.dc, c.sr, c.n, c.nn, c.n0, qk, c.nxi, c.y, awk, c.vv, c.jp, c.w, c.eta, &no)
    mem.reset(c.a, lb)
    if re != ok { ret 0.0f64 / 0.0f64 }
    c.no = no
    ret no.score
}

// s (n by n0), r (n by nxi), q = r[id, ]
fn sspngreg(a: *mem.Arena, fam: usize, s: []const f64, r: []const f64, q: []const f64, y: []const f64, n: usize, n0: usize, nxi: usize, alpha: f64, out: *g1.Gs1) -> err {
    let nn = n0 + nxi
    let tmp = gss.sumsq(r[0usize..n * nxi])
    let theta = math.log10[f64](gss.sumsq(s[0usize..n * n0]) / f64(n0) / tmp * f64(nxi)) / 2.0f64
    var trq = 0.0f64
    var i = 0usize
    while i < nxi {
        trq += q[i + i * nxi]
        i += 1usize
    }
    let logla0 = math.log10[f64](tmp / trq) + theta
    let th10 = math.pow[f64](10.0f64, theta)
    let (sr, e1) = gss.zeros(a, n * nn)
    let (dc, e2) = gss.zeros(a, nn)
    let (vv, e3) = gss.zeros(a, nn * nn)
    let (jp, e4) = mem.alloc[usize](a, nn + 1usize)
    let (w, e5) = gss.zeros(a, n)
    let (eta, e6) = gss.zeros(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    i = 0usize
    while i < n * n0 {
        sr[i] = s[i]
        i += 1usize
    }
    i = 0usize
    while i < n * nxi {
        sr[n * n0 + i] = th10 * r[i]
        i += 1usize
    }
    var c: Sng = zero
    c.a = a
    c.fam = fam
    c.s = s
    c.r = r
    c.q = q
    c.y = y
    c.n = n
    c.n0 = n0
    c.nxi = nxi
    c.nn = nn
    c.alpha = alpha
    c.theta = theta
    c.logla0 = logla0
    c.sr = sr
    c.dc = dc
    c.vv = vv
    c.jp = jp
    c.w = w
    c.eta = eta
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
        let z = gss.nlm0[Sng](&c, cv_s, mn, mx)
        est = z.est
        var m1 = est - mn
        if mx - est < m1 { m1 = mx - est }
        var m2 = est - mn0
        if mx0 - est < m2 { m2 = mx0 - est }
        if m1 >= 0.1f64 || m2 < 0.1f64 { going = false } else { la = est }
    }
    let jk = cv_s(&c, est)
    if jk != jk { ret gss.Indefinite }
    let (cc, e7) = gss.zeros(a, nxi)
    let (dd, e8) = gss.zeros(a, n0)
    let (th, e9) = gss.zeros(a, 1usize)
    let (sw, e10) = gss.zeros(a, n * n0)
    let (rw, e11) = gss.zeros(a, n * nxi)
    let (qm, e12) = gss.zeros(a, nxi * nxi)
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    i = 0usize
    while i < nxi {
        cc[i] = dc[n0 + i]
        i += 1usize
    }
    i = 0usize
    while i < n0 {
        dd[i] = dc[i]
        i += 1usize
    }
    th[0usize] = theta
    i = 0usize
    while i < n {
        let sq = math.sqrt[f64](w[i])
        var j = 0usize
        while j < n0 {
            sw[i + j * n] = sq * s[i + j * n]
            j += 1usize
        }
        j = 0usize
        while j < nxi {
            rw[i + j * n] = th10 * sq * r[i + j * n]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nxi * nxi {
        qm[i] = th10 * q[i]
        i += 1usize
    }
    out.fit.c = cc
    out.fit.d = dd
    out.fit.theta = th[0usize..1usize]
    out.fit.nlambda = est
    out.fit.score = c.no.score
    out.fit.varht = c.no.varht
    out.fit.v = vv
    out.fit.jp = jp
    out.fit.rkv = c.no.rkv
    out.fit.sw = sw
    out.fit.rw = rw
    out.fit.qm = qm
    out.eta = eta
    out.w = w
    ret ok
}

// ---- mspngreg: several kernels --------------------------------------------------------------------------------------------------------------------------

type Mng = struct {
    a: *mem.Arena, fam: usize, s: []const f64, rs: []const f64, id: []const usize, y: []const f64, n: usize, n0: usize, nxi: usize, nn: usize, nq: usize,
    alpha: f64, nlambda: f64, rwk: []f64, thold: []f64, dc: []f64, vv: []f64, jp: []usize, w: []f64, eta: []f64, no: NgOut, scale: f64, shift: f64
}

fn cv_m(c: *Mng, theta: []const f64) -> f64 {
    let lb = mem.mark(c.a)
    let n = c.n
    let nxi = c.nxi
    let nq = c.nq
    let (r0, e1) = gss.zeros(c.a, n * nxi)
    let (qk, e2) = gss.zeros(c.a, nxi * nxi)
    let (sr, e3) = gss.zeros(c.a, n * c.nn)
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
            let w = math.pow[f64](10.0f64, theta[i])
            t = 0usize
            while t < n * nxi {
                r0[t] += w * c.rs[i * n * nxi + t]
                t += 1usize
            }
            i += 1usize
        }
        t = 0usize
        while t < n * nxi {
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
        while t < n * nxi {
            r0[t] = c.rwk[t]
            t += 1usize
        }
        i = 0usize
        while i < nq {
            if theta[i] != c.thold[i] {
                let tw = (math.pow[f64](10.0f64, theta[i] - c.thold[i]) - 1.0f64) * math.pow[f64](10.0f64, c.thold[i])
                t = 0usize
                while t < n * nxi {
                    r0[t] += tw * c.rs[i * n * nxi + t]
                    t += 1usize
                }
            }
            i += 1usize
        }
    }
    let nl = math.pow[f64](10.0f64, c.nlambda)
    var j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            qk[i + j * nxi] = nl * r0[c.id[i] + j * n]
            i += 1usize
        }
        j += 1usize
    }
    t = 0usize
    while t < n * c.n0 {
        sr[t] = c.s[t]
        t += 1usize
    }
    t = 0usize
    while t < n * nxi {
        sr[n * c.n0 + t] = r0[t]
        t += 1usize
    }
    // alpha.wk: the package's z$lambda is NULL here, so max(0, theta - log.th0 - 5) is 0 and alpha.wk is alpha
    var no: NgOut = zero
    let re = ngreg(c.a, c.fam, c.dc, sr, n, c.nn, c.n0, qk, nxi, c.y, c.alpha, c.vv, c.jp, c.w, c.eta, &no)
    mem.reset(c.a, lb)
    if re != ok { ret 0.0f64 / 0.0f64 }
    c.no = no
    ret no.score
}

fn cv_m_wk(c: *Mng, theta: []const f64) -> f64 { ret c.scale * cv_m(c, theta) + c.shift }

fn log10f(x: f64) -> f64 { ret math.log10[f64](x) }

fn mspngreg(a: *mem.Arena, fam: usize, s: []const f64, rs: []const f64, id: []const usize, nq: usize, y: []const f64, n: usize, n0: usize, nxi: usize, alpha: f64, skip: bool, fix: []const f64, out: *g1.Gs1) -> err {
    let sz = n * nxi
    let nn = n0 + nxi
    let (theta, e1) = gss.zeros(a, nq)
    let (rwk, e2) = gss.zeros(a, sz)
    let (q1, e3) = gss.zeros(a, nxi * nxi)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    var j = 0usize
    var t = 0usize
    while i < nq {
        var tr = 0.0f64
        j = 0usize
        while j < nxi {
            tr += rs[i * sz + id[j] + j * n]
            j += 1usize
        }
        theta[i] = 0.0f64 - log10f(tr)
        i += 1usize
    }
    i = 0usize
    while i < nq {
        let wq = math.pow[f64](10.0f64, theta[i])
        t = 0usize
        while t < sz {
            rwk[t] += wq * rs[i * sz + t]
            t += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            q1[i + j * nxi] = rwk[id[i] + j * n]
            i += 1usize
        }
        j += 1usize
    }
    var z: g1.Gs1 = zero
    try sspngreg(a, fam, s, rwk, q1, y, n, n0, nxi, alpha, &z)
    i = 0usize
    while i < nq {
        theta[i] = theta[i] + z.fit.theta[0usize]
        i += 1usize
    }
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
                rc += rs[i * sz + id[j] + k * n] * z.fit.c[k]
                k += 1usize
            }
            cq += z.fit.c[j] * rc
            j += 1usize
        }
        theta[i] = 2.0f64 * theta[i] + log10f(cq)
        let wq = math.pow[f64](10.0f64, theta[i])
        t = 0usize
        while t < sz {
            rwk[t] += wq * rs[i * sz + t]
            t += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            q1[i + j * nxi] = rwk[id[i] + j * n]
            i += 1usize
        }
        j += 1usize
    }
    var z2: g1.Gs1 = zero
    try sspngreg(a, fam, s, rwk, q1, y, n, n0, nxi, alpha, &z2)
    var nlambda = z2.fit.nlambda
    i = 0usize
    while i < nq {
        theta[i] = theta[i] + z2.fit.theta[0usize]
        i += 1usize
    }
    if skip {
        z2.fit.theta = theta
        out.fit = z2.fit
        out.eta = z2.eta
        out.w = z2.w
        ret ok
    }
    // fix = R's converged [nlambda, theta..]: the fit at those values, no search (the nlm search stops on rounding-dependent points)
    if fix.len > 0usize {
        nlambda = fix[0usize]
        i = 0usize
        while i < nq {
            theta[i] = fix[1usize + i]
            i += 1usize
        }
    }
    // the theta search
    let (rw2, e5) = gss.zeros(a, sz)
    let (thold, e6) = gss.zeros(a, nq)
    let (dc, e7) = gss.zeros(a, nn)
    let (vv, e8) = gss.zeros(a, nn * nn)
    let (jp, e9) = mem.alloc[usize](a, nn + 1usize)
    let (w, e10) = gss.zeros(a, n)
    let (eta, e11) = gss.zeros(a, n)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    i = 0usize
    while i < nq {
        let wq = math.pow[f64](10.0f64, theta[i])
        t = 0usize
        while t < sz {
            rw2[t] += wq * rs[i * sz + t]
            t += 1usize
        }
        thold[i] = theta[i]
        i += 1usize
    }
    var cx: Mng = zero
    cx.a = a
    cx.fam = fam
    cx.s = s
    cx.rs = rs
    cx.id = id
    cx.y = y
    cx.n = n
    cx.n0 = n0
    cx.nxi = nxi
    cx.nn = nn
    cx.nq = nq
    cx.alpha = alpha
    cx.nlambda = nlambda
    cx.rwk = rw2
    cx.thold = thold
    cx.dc = dc
    cx.vv = vv
    cx.jp = jp
    cx.w = w
    cx.eta = eta
    cx.scale = 1.0f64
    cx.shift = 0.0f64
    let tmp = gss.absf(cv_m(&cx, theta))
    if tmp < 1.0f64 && tmp > 0.0001f64 { cx.scale = 10.0f64 / tmp }
    if tmp < 0.0001f64 {
        cx.scale = 100.0f64
        cx.shift = 10.0f64
    }
    var counter = 0usize
    var searching = fix.len == 0usize
    while searching {
        let r = nlm.nlm[Mng](a, &cx, cv_m_wk, theta, 100usize, 7i64, 1.0f64)
        if r.code <= 3i64 { searching = false } else {
            counter += 1usize
            if counter >= 5usize { searching = false }
        }
    }
    let jk = cv_m(&cx, theta)
    if jk != jk { ret gss.Indefinite }
    let (cc, e12) = gss.zeros(a, nxi)
    let (dd, e13) = gss.zeros(a, n0)
    let (rfin, e14) = gss.zeros(a, sz)
    let (qfin, e15) = gss.zeros(a, nxi * nxi)
    let (sw, e16) = gss.zeros(a, n * n0)
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    if e16 != ok { ret e16 }
    i = 0usize
    while i < nxi {
        cc[i] = dc[n0 + i]
        i += 1usize
    }
    i = 0usize
    while i < n0 {
        dd[i] = dc[i]
        i += 1usize
    }
    i = 0usize
    while i < nq {
        let wq = math.pow[f64](10.0f64, theta[i])
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
            qfin[i + j * nxi] = rfin[id[i] + j * n]
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        let sq = math.sqrt[f64](w[i])
        j = 0usize
        while j < n0 {
            sw[i + j * n] = sq * s[i + j * n]
            j += 1usize
        }
        j = 0usize
        while j < nxi {
            rfin[i + j * n] = sq * rfin[i + j * n]
            j += 1usize
        }
        i += 1usize
    }
    out.fit.c = cc
    out.fit.d = dd
    out.fit.theta = theta
    out.fit.nlambda = nlambda
    out.fit.score = cx.no.score
    out.fit.varht = cx.no.varht
    out.fit.v = vv
    out.fit.jp = jp
    out.fit.rkv = cx.no.rkv
    out.fit.sw = sw
    out.fit.rw = rfin
    out.fit.qm = qfin
    out.eta = eta
    out.w = w
    ret ok
}

// one kernel (nq == 1) through sspngreg with q = r[id, ], else mspngreg; rs holds the nq kernels one after the other
fn gssanova(a: *mem.Arena, fam: usize, s: []const f64, rs: []const f64, id: []const usize, nq: usize, y: []const f64, n: usize, n0: usize, nxi: usize, alpha: f64, skip: bool, fix: []const f64, out: *g1.Gs1) -> err {
    if nq == 1usize {
        let (q, e) = gss.zeros(a, nxi * nxi)
        if e != ok { ret e }
        var j = 0usize
        while j < nxi {
            var i = 0usize
            while i < nxi {
                q[i + j * nxi] = rs[id[i] + j * n]
                i += 1usize
            }
            j += 1usize
        }
        try sspngreg(a, fam, s, rs, q, y, n, n0, nxi, alpha, out)
        ret ok
    }
    try mspngreg(a, fam, s, rs, id, nq, y, n, n0, nxi, alpha, skip, fix, out)
    ret ok
}
