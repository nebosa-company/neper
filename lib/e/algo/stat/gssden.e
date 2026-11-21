// R package gss (Gu): ssden, the smoothing spline density estimate over the sampled basis id.basis. A port of the package ratfor dnewton (Newton iteration
// for the penalised likelihood over a quadrature, with the proxy loss trace) and of sspdsty (one smoothing parameter, nlm0 over log10(lambda)) and mspdsty
// (several, nlm over log10(theta)). Cubic marginals only: y ~ x, x1 + x2, x1 * x2 (models 1, 2, 3); the quadrature is given by the caller (gauss.quad(200)
// in one dimension, any grid in two); no sampling bias, no counts, no factors.
//
// Matrices are column-major. rdat is the kernel rk(x.basis, x) stored observation-fast (n by nxi, entry i + k n), likewise the quadrature kernel.

use e.math
use e.mem
use e.algo.stat.gss as gss
use e.algo.stat.gssnlm as nlm

error DenDiverge

type DenFit = struct { c: []f64, d: []f64, theta: []f64, lambda: f64, int: f64, cv: f64, nxi: usize, nnull: usize, nq: usize, dim: usize }

fn zeros(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (w, e) = gss.zeros(a, n)
    ret (w, e)
}

fn l10(x: f64) -> f64 { ret math.log10[f64](x) }

fn p10(x: f64) -> f64 { ret math.pow[f64](10.0f64, x) }

fn nanf() -> f64 { ret 0.0f64 / 0.0f64 }

// the number of terms of the model: unpenalised columns and kernels
fn den_nnull(model: usize) -> usize {
    if model == 1usize { ret 1usize }
    if model == 2usize { ret 2usize }
    ret 3usize
}

fn den_nq(model: usize) -> usize {
    if model == 1usize { ret 1usize }
    if model == 2usize { ret 2usize }
    ret 5usize
}

// s (na by nnull) and the nq kernels r (each na by nb, entry i + j na: x row i against basis row j) of the cubic model with ranges lo[v], hi[v]
fn den_terms(a: *mem.Arena, model: usize, lo: []const f64, hi: []const f64, x: []const f64, na: usize, xb: []const f64, nb: usize, s: []f64, r: []f64) -> err {
    var dim = 2usize
    if model == 1usize { dim = 1usize }
    let sz = na * nb
    let (p2a, e1) = zeros(a, na)
    let (p2b, e2) = zeros(a, nb)
    let (p1b, e3) = zeros(a, nb)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < na {
        s[i] = gss.cubic_phi(x[i], lo[0usize], hi[0usize])
        if dim == 2usize {
            p2a[i] = gss.cubic_phi(x[na + i], lo[1usize], hi[1usize])
            s[na + i] = p2a[i]
            if model == 3usize { s[2usize * na + i] = s[i] * p2a[i] }
        }
        i += 1usize
    }
    var j = 0usize
    while j < nb {
        p1b[j] = gss.cubic_phi(xb[j], lo[0usize], hi[0usize])
        if dim == 2usize { p2b[j] = gss.cubic_phi(xb[nb + j], lo[1usize], hi[1usize]) }
        i = 0usize
        while i < na {
            let at = i + j * na
            let r1 = gss.cubic_rk(x[i], xb[j], lo[0usize], hi[0usize])
            r[at] = r1
            if dim == 2usize {
                let r2 = gss.cubic_rk(x[na + i], xb[nb + j], lo[1usize], hi[1usize])
                r[sz + at] = r2
                if model == 3usize {
                    let pp1 = gss.cubic_phi(x[i], lo[0usize], hi[0usize]) * p1b[j]
                    r[2usize * sz + at] = r1 * (p2a[i] * p2b[j])
                    r[3usize * sz + at] = pp1 * r2
                    r[4usize * sz + at] = r1 * r2
                }
            }
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// dsymv upper: y = alpha A x + beta y (A n by n, lda)
fn dsymv_u(n: usize, alpha: f64, am: []const f64, lda: usize, x: []const f64, beta: f64, y: []f64) {
    var i = 0usize
    if beta != 1.0f64 {
        while i < n {
            if beta == 0.0f64 { y[i] = 0.0f64 } else { y[i] = beta * y[i] }
            i += 1usize
        }
    }
    var j = 0usize
    while j < n {
        let t1 = alpha * x[j]
        var t2 = 0.0f64
        i = 0usize
        while i < j {
            y[i] += t1 * am[i + j * lda]
            t2 += am[i + j * lda] * x[i]
            i += 1usize
        }
        y[j] += t1 * am[j + j * lda] + alpha * t2
        j += 1usize
    }
}

fn dot(x: []const f64, ox: usize, ix: usize, y: []const f64, oy: usize, iy: usize, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[ox + i * ix] * y[oy + i * iy]
        i += 1usize
    }
    ret s
}

fn amax(x: []const f64, n: usize) -> usize {
    var b = 0usize
    var i = 1usize
    while i < n {
        if gss.absf(x[i]) > gss.absf(x[b]) { b = i }
        i += 1usize
    }
    ret b
}

type DnOut = struct { info: usize, lkhd: f64, trc: f64 }

// dnewton (one sampling-bias term, no counts): cd (nxis) in and out, q the nxi by nxi penalty, rs (nxis by nobs), qdrs (nqd by nxis), qdwt (nqd)
fn dnewton(a: *mem.Arena, cd: []f64, nxis: usize, q: []const f64, nxi: usize, rs0: []const f64, nobs: usize, qdrs: []const f64, nqd: usize, qdwt: []const f64, prec: f64, maxiter: usize, mchpr: f64, out: *DnOut) -> err {
    let (rs, e1) = zeros(a, nxis * nobs)
    let (mrs, e2) = zeros(a, nxis)
    let (wt, e3) = zeros(a, nqd)
    let (wtn, e4) = zeros(a, nqd)
    let (fit, e5) = zeros(a, nobs)
    let (fitn, e6) = zeros(a, nobs)
    let (mu, e7) = zeros(a, nxis)
    let (muwk, e8) = zeros(a, nxis)
    let (v, e9) = zeros(a, nxis * nxis)
    let (cdn, e10) = zeros(a, nxis)
    let (wk, e11) = zeros(a, nxis + 3usize)
    let (jp, e12) = mem.alloc[usize](a, nxis + 1usize)
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
    var i = 0usize
    while i < nxis * nobs {
        rs[i] = rs0[i]
        i += 1usize
    }
    out.info = 0usize
    let nd = f64(nobs)
    i = 0usize
    while i < nxis {
        var sm = 0.0f64
        var j = 0usize
        while j < nobs {
            sm += rs[i + j * nxis]
            j += 1usize
        }
        mrs[i] = sm / nd
        i += 1usize
    }
    var wtsum = 0.0f64
    i = 0usize
    while i < nqd {
        wt[i] = qdwt[i] * math.exp[f64](dot(qdrs, i, nqd, cd, 0usize, 1usize, nxis))
        wtsum += wt[i]
        i += 1usize
    }
    var norm = math.log[f64](wtsum)
    var fitmean = 0.0f64
    i = 0usize
    while i < nobs {
        let t = dot(rs, i * nxis, 1usize, cd, 0usize, 1usize, nxis)
        fit[i] = math.exp[f64](t)
        fitmean += t
        i += 1usize
    }
    fitmean = fitmean / nd
    dsymv_u(nxi, 1.0f64, q, nxi, cd, 0.0f64, wk)
    var lkhd = dot(cd, 0usize, 1usize, wk, 0usize, 1usize, nxi) / 2.0f64 - fitmean + norm
    var lkhdnew = 0.0f64
    var wtsumnew = 0.0f64
    var iter = 0usize
    var flag = 0usize
    var rkv = 0usize
    var running = true
    while running {
        iter += 1usize
        i = 0usize
        while i < nxis {
            mu[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < nxis * nxis {
            v[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < nxis {
            muwk[i] = 0.0f64 - dot(wt, 0usize, 1usize, qdrs, i * nqd, 1usize, nqd) / wtsum
            i += 1usize
        }
        i = 0usize
        while i < nxis {
            var j = i
            while j < nxis {
                var sm = 0.0f64
                var k = 0usize
                while k < nqd {
                    sm += wt[k] * qdrs[k + i * nqd] * qdrs[k + j * nqd]
                    k += 1usize
                }
                v[i + j * nxis] = sm / wtsum - muwk[i] * muwk[j]
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < nxis {
            mu[i] += muwk[i]
            i += 1usize
        }
        i = 0usize
        while i < nxi {
            var j = i
            while j < nxi {
                v[i + j * nxis] += q[i + j * nxi]
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < nxis {
            mu[i] += mrs[i]
            i += 1usize
        }
        dsymv_u(nxi, 0.0f64 - 1.0f64, q, nxi, cd, 1.0f64, mu)
        let mumax = gss.absf(mu[amax(mu, nxis)])
        rkv = gss.dchdc(v, nxis, 0usize, jp, wk)
        while rkv > 1usize && v[(rkv - 1usize) * nxis + rkv - 1usize] < v[0usize] * math.sqrt[f64](mchpr) { rkv -= 1usize }
        i = rkv + 1usize
        while i <= nxis {
            v[(i - 1usize) * nxis + i - 1usize] = v[0usize]
            var r = rkv + 1usize
            while r < i {
                v[(i - 1usize) * nxis + r - 1usize] = 0.0f64
                r += 1usize
            }
            i += 1usize
        }
        var inner = true
        while inner {
            i = 0usize
            while i < nxis {
                cdn[i] = mu[jp[i] - 1usize]
                i += 1usize
            }
            gss.dtrsl_t(v, nxis, cdn, 0usize)
            i = rkv
            while i < nxis {
                cdn[i] = 0.0f64
                i += 1usize
            }
            gss.dtrsl_up(v, 0usize, nxis, nxis, cdn, 0usize)
            i = 0usize
            while i < nxis {
                wk[jp[i] - 1usize] = cdn[i]
                i += 1usize
            }
            i = 0usize
            while i < nxis {
                cdn[i] = wk[i] + cd[i]
                i += 1usize
            }
            wtsumnew = 0.0f64
            i = 0usize
            var cut = false
            while i < nqd && !cut {
                let t = dot(qdrs, i, nqd, cdn, 0usize, 1usize, nxis)
                if t > 300.0f64 {
                    flag += 1usize
                    cut = true
                } else {
                    wtn[i] = qdwt[i] * math.exp[f64](t)
                    wtsumnew += wtn[i]
                    i += 1usize
                }
            }
            norm = math.log[f64](wtsumnew)
            if flag == 0usize || flag == 2usize {
                fitmean = 0.0f64
                i = 0usize
                cut = false
                while i < nobs && !cut {
                    let t = dot(rs, i * nxis, 1usize, cdn, 0usize, 1usize, nxis)
                    if t > 300.0f64 {
                        flag += 1usize
                        cut = true
                    } else {
                        fitn[i] = math.exp[f64](t)
                        fitmean += t
                        i += 1usize
                    }
                }
                fitmean = fitmean / nd
                dsymv_u(nxi, 1.0f64, q, nxi, cdn, 0.0f64, wk)
                lkhdnew = dot(cdn, 0usize, 1usize, wk, 0usize, 1usize, nxi) / 2.0f64 - fitmean + norm
            }
            if flag == 1usize {
                i = 0usize
                while i < nxis {
                    cd[i] = 0.0f64
                    i += 1usize
                }
                wtsum = 0.0f64
                i = 0usize
                while i < nqd {
                    wt[i] = qdwt[i]
                    wtsum += wt[i]
                    i += 1usize
                }
                lkhd = math.log[f64](wtsum)
                i = 0usize
                while i < nobs {
                    fit[i] = 1.0f64
                    i += 1usize
                }
                iter = 0usize
                inner = false
            } else {
                if flag == 3usize {
                    inner = false
                } else {
                    if lkhdnew - lkhd < 10.0f64 * (1.0f64 + gss.absf(lkhd)) * mchpr {
                        inner = false
                    } else {
                        i = 0usize
                        while i < nxis {
                            mu[i] = mu[i] * 0.5f64
                            i += 1usize
                        }
                        if gss.absf(mu[amax(mu, nxis)] / mumax) < 10.0f64 * mchpr { inner = false }
                    }
                }
            }
        }
        if flag == 1usize {
            flag = 2usize
        } else {
            if flag == 3usize {
                out.info = 1usize
                ret ok
            }
            var disc = 0.0f64
            i = 0usize
            while i < nqd {
                let dd = gss.absf(wt[i] - wtn[i]) / (1.0f64 + gss.absf(wt[i]))
                if dd > disc { disc = dd }
                i += 1usize
            }
            i = 0usize
            while i < nobs {
                let dd = gss.absf(fit[i] - fitn[i]) / (1.0f64 + gss.absf(fit[i]))
                if dd > disc { disc = dd }
                i += 1usize
            }
            let m2 = (mumax / (1.0f64 + gss.absf(lkhd))) * (mumax / (1.0f64 + gss.absf(lkhd)))
            if m2 > disc { disc = m2 }
            let m3 = (mumax / (1.0f64 + lkhd)) * (mumax / (1.0f64 + lkhd))
            var disc0 = gss.absf(lkhd - lkhdnew) / (1.0f64 + gss.absf(lkhd))
            if m3 > disc0 { disc0 = m3 }
            i = 0usize
            while i < nxis {
                cd[i] = cdn[i]
                i += 1usize
            }
            i = 0usize
            while i < nqd {
                wt[i] = wtn[i]
                i += 1usize
            }
            wtsum = wtsumnew
            i = 0usize
            while i < nobs {
                fit[i] = fitn[i]
                i += 1usize
            }
            lkhd = lkhdnew
            if disc0 < prec {
                running = false
            } else {
                if disc < prec {
                    running = false
                } else {
                    if iter >= maxiter {
                        if flag == 0usize {
                            i = 0usize
                            while i < nxis {
                                cd[i] = 0.0f64
                                i += 1usize
                            }
                            wtsum = 0.0f64
                            i = 0usize
                            while i < nqd {
                                wt[i] = qdwt[i]
                                wtsum += wt[i]
                                i += 1usize
                            }
                            lkhd = math.log[f64](wtsum)
                            i = 0usize
                            while i < nobs {
                                fit[i] = 1.0f64
                                i += 1usize
                            }
                            iter = 0usize
                            flag = 2usize
                        } else {
                            out.info = 2usize
                            running = false
                        }
                    }
                }
            }
        }
    }
    // proxy loss
    var trc = 0.0f64
    i = 0usize
    while i < nobs {
        var k = 0usize
        while k < nxis {
            rs[k + i * nxis] -= mrs[k]
            k += 1usize
        }
        k = 0usize
        while k < nxis {
            wk[k] = rs[jp[k] - 1usize + i * nxis]
            k += 1usize
        }
        gss.dtrsl_t(v, nxis, wk, 0usize)
        k = rkv
        while k < nxis {
            wk[k] = 0.0f64
            k += 1usize
        }
        k = 0usize
        while k < nxis {
            trc += wk[k] * wk[k]
            k += 1usize
        }
        i += 1usize
    }
    trc = trc / nd / (nd - 1.0f64)
    var lk = 0.0f64
    i = 0usize
    while i < nobs {
        lk += math.log[f64](fit[i])
        i += 1usize
    }
    lk = lk / nd
    out.lkhd = lk - math.log[f64](wtsum)
    out.trc = trc
    ret ok
}

// ---- one smoothing parameter ----

type Sp = struct { lambda: f64, theta: f64, cd: []f64, int: f64, cv: f64 }

type CvS = struct {
    a: *mem.Arena, nxis: usize, nxi: usize, nobs: usize, nqd: usize, q: []const f64, rs: []const f64, qdrs: []const f64, qdwt: []const f64,
    prec: f64, maxiter: usize, alpha: f64, theta: f64, logla0: f64, cd: []f64, bad: bool
}

fn dn_call(a: *mem.Arena, cd: []f64, nxis: usize, q: []const f64, nxi: usize, rs: []const f64, nobs: usize, qdrs: []const f64, nqd: usize, qdwt: []const f64, prec: f64, maxiter: usize, o: *DnOut) -> bool {
    let lb = mem.mark(a)
    let e = dnewton(a, cd, nxis, q, nxi, rs, nobs, qdrs, nqd, qdwt, prec, maxiter, 2.220446049250313e-16f64, o)
    mem.reset(a, lb)
    ret e == ok && o.info != 1usize
}

fn cvs(c: *CvS, lambda: f64) -> f64 {
    let lb = mem.mark(c.a)
    let (qk, e) = zeros(c.a, c.nxi * c.nxi)
    if e != ok {
        mem.reset(c.a, lb)
        ret nanf()
    }
    let sc = p10(lambda + c.theta)
    var t = 0usize
    while t < c.nxi * c.nxi {
        qk[t] = sc * c.q[t]
        t += 1usize
    }
    var o: DnOut = zero
    let good = dn_call(c.a, c.cd, c.nxis, qk, c.nxi, c.rs, c.nobs, c.qdrs, c.nqd, c.qdwt, c.prec, c.maxiter, &o)
    mem.reset(c.a, lb)
    if !good {
        c.bad = true
        ret nanf()
    }
    let cv = c.alpha * o.trc - o.lkhd
    var awk = 0.0f64
    if c.logla0 - lambda - 5.0f64 > 0.0f64 { awk = c.logla0 - lambda - 5.0f64 }
    awk = awk * (3.0f64 - c.alpha) + c.alpha
    if awk > 3.0f64 { awk = 3.0f64 }
    var adj = 0.0f64
    if awk > c.alpha { adj = (awk - c.alpha) * o.trc }
    ret cv + adj
}

fn build_rs(a: *mem.Arena, w: f64, rdat: []const f64, sdat: []const f64, n: usize, nxi: usize, nnull: usize) -> ([]f64, err) {
    let nxis = nxi + nnull
    let (rs, e) = zeros(a, nxis * n)
    if e != ok { ret (rs, e) }
    var i = 0usize
    while i < n {
        var k = 0usize
        while k < nxi {
            rs[k + i * nxis] = w * rdat[i + k * n]
            k += 1usize
        }
        k = 0usize
        while k < nnull {
            rs[nxi + k + i * nxis] = sdat[i + k * n]
            k += 1usize
        }
        i += 1usize
    }
    ret (rs, ok)
}

fn build_qdrs(a: *mem.Arena, w: f64, qr: []const f64, qs: []const f64, nqd: usize, nxi: usize, nnull: usize) -> ([]f64, err) {
    let nxis = nxi + nnull
    let (m, e) = zeros(a, nxis * nqd)
    if e != ok { ret (m, e) }
    var k = 0usize
    while k < nxi {
        var i = 0usize
        while i < nqd {
            m[i + k * nqd] = w * qr[i + k * nqd]
            i += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < nnull {
        var i = 0usize
        while i < nqd {
            m[i + (nxi + k) * nqd] = qs[i + k * nqd]
            i += 1usize
        }
        k += 1usize
    }
    ret (m, ok)
}

// sspdsty: r (n by nxi), q (nxi by nxi), s (n by nnull), the quadrature kernel qr (nqd by nxi) and qs (nqd by nnull)
fn sspdsty(a: *mem.Arena, sdat: []const f64, rdat: []const f64, q: []const f64, qs: []const f64, qr: []const f64, qdwt: []const f64, n: usize, nxi: usize, nnull: usize, nqd: usize, prec: f64, maxiter: usize, alpha: f64, out: *Sp) -> err {
    let nxis = nxi + nnull
    var wsum = 0.0f64
    var i = 0usize
    while i < nqd {
        wsum += qdwt[i]
        i += 1usize
    }
    var sumvr = 0.0f64
    var k = 0usize
    while k < nxi {
        var m1 = 0.0f64
        var m2 = 0.0f64
        i = 0usize
        while i < nqd {
            m1 += qdwt[i] * qr[i + k * nqd]
            m2 += qdwt[i] * (qr[i + k * nqd] * qr[i + k * nqd])
            i += 1usize
        }
        m1 = m1 / wsum
        m2 = m2 / wsum
        sumvr += m2 - m1 * m1
        k += 1usize
    }
    var theta = 0.0f64
    if nnull > 0usize {
        var sumvs = 0.0f64
        k = 0usize
        while k < nnull {
            var m1 = 0.0f64
            var m2 = 0.0f64
            i = 0usize
            while i < nqd {
                m1 += qdwt[i] * qs[i + k * nqd]
                m2 += qdwt[i] * (qs[i + k * nqd] * qs[i + k * nqd])
                i += 1usize
            }
            m1 = m1 / wsum
            m2 = m2 / wsum
            sumvs += m2 - m1 * m1
            k += 1usize
        }
        theta = l10(sumvs / f64(nnull) / sumvr * f64(nxi)) / 2.0f64
    }
    var trq = 0.0f64
    i = 0usize
    while i < nxi {
        trq += q[i + i * nxi]
        i += 1usize
    }
    let logla0 = l10(sumvr / trq) + theta
    let w = p10(theta)
    let (rs, e1) = build_rs(a, w, rdat, sdat, n, nxi, nnull)
    let (qdrs, e2) = build_qdrs(a, w, qr, qs, nqd, nxi, nnull)
    let (cd, e3) = zeros(a, nxis)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var c: CvS = zero
    c.a = a
    c.nxis = nxis
    c.nxi = nxi
    c.nobs = n
    c.nqd = nqd
    c.q = q
    c.rs = rs
    c.qdrs = qdrs
    c.qdwt = qdwt
    c.prec = prec
    c.maxiter = maxiter
    c.alpha = alpha
    c.theta = theta
    c.logla0 = logla0
    c.cd = cd
    var la = logla0
    let mn0 = logla0 - 6.0f64
    let mx0 = logla0 + 6.0f64
    var est = 0.0f64
    var looping = true
    while looping {
        var mn = la - 1.0f64
        if mn0 > mn { mn = mn0 }
        var mx = la + 1.0f64
        if mx0 < mx { mx = mx0 }
        let zz = gss.nlm0[CvS](&c, cvs, mn, mx)
        est = zz.est
        var d1 = est - mn
        if mx - est < d1 { d1 = mx - est }
        var d2 = est - mn0
        if mx0 - est < d2 { d2 = mx0 - est }
        if d1 >= 0.1f64 || d2 < 0.1f64 { looping = false } else { la = est }
        if c.bad { ret DenDiverge }
    }
    let jk = cvs(&c, est)
    if c.bad { ret DenDiverge }
    var itg = 0.0f64
    i = 0usize
    while i < nqd {
        itg += qdwt[i] * math.exp[f64](dot(qdrs, i, nqd, cd, 0usize, 1usize, nxis))
        i += 1usize
    }
    out.lambda = est
    out.theta = theta
    out.cd = cd
    out.int = itg
    out.cv = jk
    ret ok
}

// ---- several smoothing parameters ----

type CvD = struct {
    a: *mem.Arena, nxis: usize, nxi: usize, nobs: usize, nqd: usize, nq: usize, nnull: usize, rk: []const f64, qrk: []const f64, sdat: []const f64, qs: []const f64,
    id: []const usize, qdwt: []const f64, prec: f64, maxiter: usize, alpha: f64, lambda: f64, logth0: []f64, rwk: []f64, thold: []f64, cd: []f64,
    scale: f64, shift: f64, bad: bool
}

fn cvd(c: *CvD, theta: []const f64) -> f64 {
    let lb = mem.mark(c.a)
    let n = c.nobs
    let nxi = c.nxi
    let nq = c.nq
    let sz = n * nxi
    let qsz = c.nqd * nxi
    let (r0, e1) = zeros(c.a, sz)
    let (q0, e2) = zeros(c.a, qsz)
    let (qk, e3) = zeros(c.a, nxi * nxi)
    if e1 != ok || e2 != ok || e3 != ok {
        mem.reset(c.a, lb)
        ret nanf()
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
            let w = p10(theta[i])
            t = 0usize
            while t < sz {
                r0[t] += w * c.rk[i * sz + t]
                t += 1usize
            }
            t = 0usize
            while t < qsz {
                q0[t] += w * c.qrk[i * qsz + t]
                t += 1usize
            }
            i += 1usize
        }
        t = 0usize
        while t < sz {
            c.rwk[t] = r0[t]
            t += 1usize
        }
        i = 0usize
        while i < nq {
            c.thold[i] = theta[i]
            i += 1usize
        }
    } else {
        // the cached sum plus the changed terms; the quadrature sum is recomputed from the cache term by term the same way
        t = 0usize
        while t < sz {
            r0[t] = c.rwk[t]
            t += 1usize
        }
        t = 0usize
        while t < qsz {
            var sm = 0.0f64
            i = 0usize
            while i < nq {
                sm += p10(c.thold[i]) * c.qrk[i * qsz + t]
                i += 1usize
            }
            q0[t] = sm
            t += 1usize
        }
        i = 0usize
        while i < nq {
            if theta[i] != c.thold[i] {
                let tw = (p10(theta[i] - c.thold[i]) - 1.0f64) * p10(c.thold[i])
                t = 0usize
                while t < sz {
                    r0[t] += tw * c.rk[i * sz + t]
                    t += 1usize
                }
                t = 0usize
                while t < qsz {
                    q0[t] += tw * c.qrk[i * qsz + t]
                    t += 1usize
                }
            }
            i += 1usize
        }
    }
    let nl = p10(c.lambda)
    var j = 0usize
    while j < nxi {
        i = 0usize
        while i < nxi {
            qk[i + j * nxi] = nl * r0[c.id[j] + i * n]
            i += 1usize
        }
        j += 1usize
    }
    let (rs, e4) = build_rs(c.a, 1.0f64, r0, c.sdat, n, nxi, c.nnull)
    let (qdrs, e5) = build_qdrs(c.a, 1.0f64, q0, c.qs, c.nqd, nxi, c.nnull)
    if e4 != ok || e5 != ok {
        mem.reset(c.a, lb)
        ret nanf()
    }
    var o: DnOut = zero
    let good = dn_call(c.a, c.cd, c.nxis, qk, nxi, rs, n, qdrs, c.nqd, c.qdwt, c.prec, c.maxiter, &o)
    mem.reset(c.a, lb)
    if !good {
        c.bad = true
        ret nanf()
    }
    let cv = c.alpha * o.trc - o.lkhd
    var mx = 0.0f64
    i = 0usize
    while i < nq {
        let u = theta[i] - c.logth0[i] - 5.0f64
        if u > mx { mx = u }
        i += 1usize
    }
    var awk = mx * (3.0f64 - c.alpha) + c.alpha
    if awk > 3.0f64 { awk = 3.0f64 }
    var adj = 0.0f64
    if awk > c.alpha { adj = (awk - c.alpha) * o.trc }
    ret cv + adj
}

fn cvd_wk(c: *CvD, theta: []const f64) -> f64 { ret c.scale * cvd(c, theta) + c.shift }

// sums of the nq kernels of rk (blocks of sz) with weights 10^theta
fn comb(a: *mem.Arena, rk: []const f64, sz: usize, nq: usize, theta: []const f64) -> ([]f64, err) {
    let (r, e) = zeros(a, sz)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < nq {
        let w = p10(theta[i])
        var t = 0usize
        while t < sz {
            r[t] += w * rk[i * sz + t]
            t += 1usize
        }
        i += 1usize
    }
    ret (r, ok)
}

fn sub_q(a: *mem.Arena, r: []const f64, id: []const usize, n: usize, nxi: usize) -> ([]f64, err) {
    let (q, e) = zeros(a, nxi * nxi)
    if e != ok { ret (q, e) }
    var j = 0usize
    while j < nxi {
        var i = 0usize
        while i < nxi {
            q[i + j * nxi] = r[id[j] + i * n]
            i += 1usize
        }
        j += 1usize
    }
    ret (q, ok)
}

// mspdsty: rk holds the nq kernels (each n by nxi), qrk the quadrature ones (each nqd by nxi), id the 0-based basis rows of the observations
fn mspdsty(a: *mem.Arena, sdat: []const f64, rk: []const f64, id: []const usize, qs: []const f64, qrk: []const f64, qdwt: []const f64, n: usize, nxi: usize, nnull: usize, nqd: usize, nq: usize, prec: f64, maxiter: usize, alpha: f64, skip: bool, fix: []const f64, out: *DenFit) -> err {
    let sz = n * nxi
    let qsz = nqd * nxi
    let nxis = nxi + nnull
    let (theta, e1) = zeros(a, nq)
    let (logth0, e2) = zeros(a, nq)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < nq {
        var tr = 0.0f64
        var k = 0usize
        while k < nxi {
            tr += rk[i * sz + id[k] + k * n]
            k += 1usize
        }
        theta[i] = 0.0f64 - l10(tr)
        i += 1usize
    }
    var (rwk, ea) = comb(a, rk, sz, nq, theta)
    if ea != ok { ret ea }
    var (qwk, eb) = comb(a, qrk, qsz, nq, theta)
    if eb != ok { ret eb }
    var (q1, ec) = sub_q(a, rwk, id, n, nxi)
    if ec != ok { ret ec }
    var z: Sp = zero
    try sspdsty(a, sdat, rwk, q1, qs, qwk, qdwt, n, nxi, nnull, nqd, prec, maxiter, alpha, &z)
    i = 0usize
    while i < nq {
        theta[i] = theta[i] + z.theta
        i += 1usize
    }
    i = 0usize
    while i < nq {
        var cq = 0.0f64
        var l = 0usize
        while l < nxi {
            var rc = 0.0f64
            var k = 0usize
            while k < nxi {
                rc += z.cd[k] * rk[i * sz + id[l] + k * n]
                k += 1usize
            }
            cq += rc * z.cd[l]
            l += 1usize
        }
        theta[i] = 2.0f64 * theta[i] + l10(cq)
        i += 1usize
    }
    let (rw3, ed) = comb(a, rk, sz, nq, theta)
    let (qw3, ee) = comb(a, qrk, qsz, nq, theta)
    if ed != ok { ret ed }
    if ee != ok { ret ee }
    rwk = rw3
    qwk = qw3
    var wsum = 0.0f64
    i = 0usize
    while i < nqd {
        wsum += qdwt[i]
        i += 1usize
    }
    var sumv = 0.0f64
    var k = 0usize
    while k < nxi {
        var m1 = 0.0f64
        var m2 = 0.0f64
        i = 0usize
        while i < nqd {
            m1 += qdwt[i] * qwk[i + k * nqd]
            m2 += qdwt[i] * (qwk[i + k * nqd] * qwk[i + k * nqd])
            i += 1usize
        }
        m1 = m1 / wsum
        m2 = m2 / wsum
        sumv += m2 - m1 * m1
        k += 1usize
    }
    var trq = 0.0f64
    k = 0usize
    while k < nxi {
        trq += rwk[id[k] + k * n]
        k += 1usize
    }
    let logla0 = l10(sumv / trq)
    i = 0usize
    while i < nq {
        logth0[i] = theta[i] - logla0
        i += 1usize
    }
    let (q2, ef) = sub_q(a, rwk, id, n, nxi)
    if ef != ok { ret ef }
    q1 = q2
    var z2: Sp = zero
    try sspdsty(a, sdat, rwk, q1, qs, qwk, qdwt, n, nxi, nnull, nqd, prec, maxiter, alpha, &z2)
    var lambda = z2.lambda
    i = 0usize
    while i < nq {
        logth0[i] = logth0[i] + lambda
        theta[i] = theta[i] + z2.theta
        i += 1usize
    }
    // fix = R's converged [lambda, theta..]: the fit at those values, no search (the search stops on rounding-dependent points)
    if fix.len > 0usize {
        lambda = fix[0usize]
        i = 0usize
        while i < nq {
            theta[i] = fix[1usize + i]
            i += 1usize
        }
    }
    out.nxi = nxi
    out.nnull = nnull
    out.nq = nq
    let (cc, e3) = zeros(a, nxi)
    let (dd, e4) = zeros(a, nnull)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    i = 0usize
    while i < nxi {
        cc[i] = z2.cd[i]
        i += 1usize
    }
    i = 0usize
    while i < nnull {
        dd[i] = z2.cd[nxi + i]
        i += 1usize
    }
    out.c = cc
    out.d = dd
    out.lambda = lambda
    if skip {
        out.theta = theta
        out.int = z2.int
        out.cv = z2.cv
        ret ok
    }
    var cx: CvD = zero
    let (cdv, e5) = zeros(a, nxis)
    let (thold, e6) = zeros(a, nq)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    i = 0usize
    while i < nxis {
        cdv[i] = z2.cd[i]
        i += 1usize
    }
    let (rw4, eg) = comb(a, rk, sz, nq, theta)
    if eg != ok { ret eg }
    rwk = rw4
    i = 0usize
    while i < nq {
        thold[i] = theta[i]
        i += 1usize
    }
    cx.a = a
    cx.nxis = nxis
    cx.nxi = nxi
    cx.nobs = n
    cx.nqd = nqd
    cx.nq = nq
    cx.nnull = nnull
    cx.rk = rk
    cx.qrk = qrk
    cx.sdat = sdat
    cx.qs = qs
    cx.id = id
    cx.qdwt = qdwt
    cx.prec = prec
    cx.maxiter = maxiter
    cx.alpha = alpha
    cx.lambda = lambda
    cx.logth0 = logth0
    cx.rwk = rwk
    cx.thold = thold
    cx.cd = cdv
    cx.scale = 1.0f64
    cx.shift = 0.0f64
    let tmp = gss.absf(cvd(&cx, theta))
    if cx.bad { ret DenDiverge }
    if tmp < 1.0f64 && tmp > 0.0001f64 { cx.scale = 10.0f64 / tmp }
    if tmp < 0.0001f64 {
        cx.scale = 100.0f64
        cx.shift = 10.0f64
    }
    var counter = 0usize
    var searching = fix.len == 0usize
    while searching {
        let r = nlm.nlm[CvD](a, &cx, cvd_wk, theta, 100usize, 7i64, 1.0f64)
        if cx.bad { ret DenDiverge }
        if r.code <= 3i64 { searching = false } else {
            counter += 1usize
            if counter >= 5usize { searching = false }
        }
    }
    let jk = cvd(&cx, theta)
    if cx.bad { ret DenDiverge }
    let (qf, e7) = comb(a, qrk, qsz, nq, theta)
    if e7 != ok { ret e7 }
    var itg = 0.0f64
    i = 0usize
    while i < nqd {
        var t = 0.0f64
        k = 0usize
        while k < nxi {
            t += qf[i + k * nqd] * cdv[k]
            k += 1usize
        }
        k = 0usize
        while k < nnull {
            t += qs[i + k * nqd] * cdv[nxi + k]
            k += 1usize
        }
        itg += qdwt[i] * math.exp[f64](t)
        i += 1usize
    }
    i = 0usize
    while i < nxi {
        cc[i] = cdv[i]
        i += 1usize
    }
    i = 0usize
    while i < nnull {
        dd[i] = cdv[nxi + i]
        i += 1usize
    }
    out.theta = theta
    out.int = itg
    out.cv = jk
    ret ok
}

// ssden: x (n by dim) the data, idb the 0-based basis rows, [lo, hi] the range of each variable, (qx (nqd by dim), qdwt) the quadrature
fn ssden(a: *mem.Arena, model: usize, x: []const f64, n: usize, idb: []const usize, nb: usize, lo: []const f64, hi: []const f64, qx: []const f64, qdwt: []const f64, nqd: usize, alpha: f64, prec: f64, maxiter: usize, skip: bool, fix: []const f64, out: *DenFit) -> err {
    var dim = 2usize
    if model == 1usize { dim = 1usize }
    let nnull = den_nnull(model)
    let nq = den_nq(model)
    let (xb, e1) = zeros(a, nb * dim)
    if e1 != ok { ret e1 }
    var v = 0usize
    while v < dim {
        var i = 0usize
        while i < nb {
            xb[i + v * nb] = x[idb[i] + v * n]
            i += 1usize
        }
        v += 1usize
    }
    let (sdat, e2) = zeros(a, n * nnull)
    let (rk, e3) = zeros(a, nq * n * nb)
    let (qs, e4) = zeros(a, nqd * nnull)
    let (qrk, e5) = zeros(a, nq * nqd * nb)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    try den_terms(a, model, lo, hi, x, n, xb, nb, sdat, rk)
    try den_terms(a, model, lo, hi, qx, nqd, xb, nb, qs, qrk)
    out.dim = dim
    if nq == 1usize {
        let (q, eq) = sub_q(a, rk, idb, n, nb)
        if eq != ok { ret eq }
        var z: Sp = zero
        try sspdsty(a, sdat, rk, q, qs, qrk, qdwt, n, nb, nnull, nqd, prec, maxiter, alpha, &z)
        let (cc, e6) = zeros(a, nb)
        let (dd, e7) = zeros(a, nnull)
        let (th, e8) = zeros(a, 1usize)
        if e6 != ok { ret e6 }
        if e7 != ok { ret e7 }
        if e8 != ok { ret e8 }
        var i = 0usize
        while i < nb {
            cc[i] = z.cd[i]
            i += 1usize
        }
        i = 0usize
        while i < nnull {
            dd[i] = z.cd[nb + i]
            i += 1usize
        }
        th[0usize] = z.theta
        out.c = cc
        out.d = dd
        out.theta = th
        out.lambda = z.lambda
        out.int = z.int
        out.cv = z.cv
        out.nxi = nb
        out.nnull = nnull
        out.nq = 1usize
        ret ok
    }
    try mspdsty(a, sdat, rk, idb, qs, qrk, qdwt, n, nb, nnull, nqd, nq, prec, maxiter, alpha, skip, fix, out)
    ret ok
}

// the log density eta at m new rows xn (m by dim): s d + sum 10^theta r c, and the density exp(eta) / int
fn den_eval(a: *mem.Arena, model: usize, f: *const DenFit, x: []const f64, n: usize, idb: []const usize, lo: []const f64, hi: []const f64, xn: []const f64, m: usize, dens: []f64) -> err {
    let nb = f.nxi
    let dim = f.dim
    let (xb, e1) = zeros(a, nb * dim)
    let (sn, e2) = zeros(a, m * f.nnull)
    let (rn, e3) = zeros(a, f.nq * m * nb)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var v = 0usize
    while v < dim {
        var i = 0usize
        while i < nb {
            xb[i + v * nb] = x[idb[i] + v * n]
            i += 1usize
        }
        v += 1usize
    }
    try den_terms(a, model, lo, hi, xn, m, xb, nb, sn, rn)
    var i = 0usize
    while i < m {
        var eta = 0.0f64
        var k = 0usize
        while k < f.nnull {
            eta += sn[i + k * m] * f.d[k]
            k += 1usize
        }
        k = 0usize
        while k < f.nq {
            var rc = 0.0f64
            var j = 0usize
            while j < nb {
                rc += rn[k * m * nb + i + j * m] * f.c[j]
                j += 1usize
            }
            eta += p10(f.theta[k]) * rc
            k += 1usize
        }
        dens[i] = math.exp[f64](eta) / f.int
        i += 1usize
    }
    ret ok
}
