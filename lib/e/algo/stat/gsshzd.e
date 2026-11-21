// R package gss (Gu): sshzd, the smoothing spline hazard estimate over the sampled basis id.basis at failure cases. A port of the package ratfor hzdnewton
// (Newton iteration for the penalised partial likelihood over a quadrature of the time axis, and its proxy loss) and of msphzd (lambda by nlm0, theta by nlm).
// Cubic marginals: Surv(time, status) ~ time (model 1), time + x (2), time * x (3) with one numeric covariate x; start 0 for every case; no counts, offset,
// partial or random terms. The unpenalised columns are the constant, then the phi columns of the terms.
//
// Layouts: a failure-row matrix is nT by nxi (entry i + k nT); a quadrature matrix has one row per (mesh point, covariate value) pair p = m + j nqd, na rows.

use e.math
use e.mem
use e.algo.stat.gss as gss
use e.algo.stat.gssden as den
use e.algo.stat.gssnlm as nlm
use e.algo.stat.cubaturepkg as cub

type HzFit = struct {
    c: []f64, d: []f64, theta: []f64, lambda: f64, cv: f64, nxi: usize, nnull: usize, nq: usize, dim: usize, model: usize,
    xb: []f64, lo: []f64, hi: []f64
}

type HzOut = struct { good: bool, trc: f64, fm: f64 }

fn p10(x: f64) -> f64 { ret math.pow[f64](10.0f64, x) }

fn l10(x: f64) -> f64 { ret math.log10[f64](x) }

fn nanf() -> f64 { ret 0.0f64 / 0.0f64 }

// hzdnewton: cd (nxis) in and out, q (nxi by nxi), rs (nxis by nt), qdrs (na by nxis), qdwt (na)
fn hzdnewton(a: *mem.Arena, cd: []f64, nxis: usize, q: []const f64, nxi: usize, rs0: []const f64, nt: usize, nobs: usize, qdrs: []const f64, na: usize, qdwt: []const f64, prec: f64, maxiter: usize, mchpr: f64, out: *HzOut) -> err {
    let (rs, e1) = den.zeros(a, nxis * nt)
    let (mrs, e2) = den.zeros(a, nxis)
    let (wt, e3) = den.zeros(a, na)
    let (wtn, e4) = den.zeros(a, na)
    let (fit, e5) = den.zeros(a, nt)
    let (fitn, e6) = den.zeros(a, nt)
    let (mu, e7) = den.zeros(a, nxis)
    let (muwk, e8) = den.zeros(a, nxis)
    let (v, e9) = den.zeros(a, nxis * nxis)
    let (cdn, e10) = den.zeros(a, nxis)
    let (wk, e11) = den.zeros(a, nxis + 3usize)
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
    while i < nxis * nt {
        rs[i] = rs0[i]
        i += 1usize
    }
    out.good = true
    let nd = f64(nobs)
    i = 0usize
    while i < nxis {
        var sm = 0.0f64
        var j = 0usize
        while j < nt {
            sm += rs[i + j * nxis]
            j += 1usize
        }
        mrs[i] = sm / nd
        i += 1usize
    }
    var wsum = 0.0f64
    i = 0usize
    while i < na {
        wt[i] = qdwt[i] * math.exp[f64](den.dot(qdrs, i, na, cd, 0usize, 1usize, nxis))
        i += 1usize
    }
    i = 0usize
    while i < na {
        wsum += gss.absf(wt[i])
        i += 1usize
    }
    var fitmean = 0.0f64
    i = 0usize
    while i < nt {
        let t = den.dot(rs, i * nxis, 1usize, cd, 0usize, 1usize, nxis)
        fit[i] = math.exp[f64](t)
        fitmean += t
        i += 1usize
    }
    fitmean = fitmean / nd - wsum
    den.dsymv_u(nxi, 1.0f64, q, nxi, cd, 0.0f64, wk)
    var lkhd = den.dot(cd, 0usize, 1usize, wk, 0usize, 1usize, nxi) / 2.0f64 - fitmean
    var lkhdnew = 0.0f64
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
            muwk[i] = 0.0f64 - den.dot(wt, 0usize, 1usize, qdrs, i * na, 1usize, na)
            i += 1usize
        }
        i = 0usize
        while i < nxis {
            var j = i
            while j < nxis {
                var sm = 0.0f64
                var k = 0usize
                while k < na {
                    sm += wt[k] * qdrs[k + i * na] * qdrs[k + j * na]
                    k += 1usize
                }
                v[i + j * nxis] = sm
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
        den.dsymv_u(nxi, 0.0f64 - 1.0f64, q, nxi, cd, 1.0f64, mu)
        let mumax = gss.absf(mu[den.amax(mu, nxis)])
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
            i = 0usize
            var cut = false
            while i < na && !cut {
                let t = den.dot(qdrs, i, na, cdn, 0usize, 1usize, nxis)
                if t > 300.0f64 {
                    flag += 1usize
                    cut = true
                } else {
                    wtn[i] = qdwt[i] * math.exp[f64](t)
                    i += 1usize
                }
            }
            if flag == 0usize || flag == 2usize {
                fitmean = 0.0f64
                i = 0usize
                cut = false
                while i < nt && !cut {
                    let t = den.dot(rs, i * nxis, 1usize, cdn, 0usize, 1usize, nxis)
                    if t > 300.0f64 {
                        flag += 1usize
                        cut = true
                    } else {
                        fitn[i] = math.exp[f64](t)
                        fitmean += t
                        i += 1usize
                    }
                }
                wsum = 0.0f64
                i = 0usize
                while i < na {
                    wsum += gss.absf(wtn[i])
                    i += 1usize
                }
                fitmean = fitmean / nd - wsum
                den.dsymv_u(nxi, 1.0f64, q, nxi, cdn, 0.0f64, wk)
                lkhdnew = den.dot(cdn, 0usize, 1usize, wk, 0usize, 1usize, nxi) / 2.0f64 - fitmean
            }
            if flag == 1usize {
                i = 0usize
                while i < nxis {
                    cd[i] = 0.0f64
                    i += 1usize
                }
                wsum = 0.0f64
                i = 0usize
                while i < na {
                    wt[i] = qdwt[i]
                    i += 1usize
                }
                i = 0usize
                while i < na {
                    wsum += gss.absf(wt[i])
                    i += 1usize
                }
                fitmean = 0.0f64 - wsum
                lkhd = 0.0f64 - fitmean
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
                        if gss.absf(mu[den.amax(mu, nxis)] / mumax) < 10.0f64 * mchpr { inner = false }
                    }
                }
            }
        }
        if flag == 1usize {
            flag = 2usize
        } else {
            if flag == 3usize {
                out.good = false
                ret ok
            }
            var disc = 0.0f64
            i = 0usize
            while i < na {
                let dd = gss.absf(wt[i] - wtn[i]) / (1.0f64 + gss.absf(wt[i]))
                if dd > disc { disc = dd }
                i += 1usize
            }
            i = 0usize
            while i < nt {
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
            while i < na {
                wt[i] = wtn[i]
                i += 1usize
            }
            i = 0usize
            while i < nt {
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
                            i = 0usize
                            while i < na {
                                wt[i] = qdwt[i]
                                i += 1usize
                            }
                            wsum = 0.0f64
                            i = 0usize
                            while i < na {
                                wsum += gss.absf(wt[i])
                                i += 1usize
                            }
                            fitmean = 0.0f64 - wsum
                            lkhd = 0.0f64 - fitmean
                            iter = 0usize
                            flag = 2usize
                        } else {
                            running = false
                        }
                    }
                }
            }
        }
    }
    // proxy loss
    var ss = 0.0f64
    i = 0usize
    while i < nt {
        var k = 0usize
        while k < nxis {
            wk[k] = rs[jp[k] - 1usize + i * nxis]
            k += 1usize
        }
        gss.dtrsl_t(v, nxis, wk, 0usize)
        k = 0usize
        while k < nxis {
            ss += wk[k] * wk[k]
            k += 1usize
        }
        i += 1usize
    }
    var k = 0usize
    while k < nxis {
        wk[k] = mrs[jp[k] - 1usize]
        k += 1usize
    }
    gss.dtrsl_t(v, nxis, wk, 0usize)
    var sm2 = 0.0f64
    k = 0usize
    while k < nxis {
        sm2 += wk[k] * wk[k]
        k += 1usize
    }
    out.trc = (ss - nd * sm2) / nd / (nd - 1.0f64)
    out.fm = fitmean
    ret ok
}

type CvH = struct {
    a: *mem.Arena, nxis: usize, nxi: usize, nt: usize, nobs: usize, na: usize, nq: usize, nnull: usize, rk: []const f64, qrk: []const f64, s: []const f64, qs: []const f64,
    id: []const usize, qdwt: []const f64, prec: f64, maxiter: usize, alpha: f64, lambda: f64, logla0: f64, logth0: []f64, rfix: []f64, qfix: []f64,
    rwk: []f64, thold: []f64, cd: []f64, scale: f64, shift: f64, bad: bool
}

// one fit at (r, qr, lambda): the penalty is 10^lambda r[id, ]
fn hz_eval(c: *CvH, rw: []const f64, qw: []const f64, lambda: f64, o: *HzOut) -> bool {
    let lb = mem.mark(c.a)
    let nxi = c.nxi
    let nt = c.nt
    let na = c.na
    let (qk, e1) = den.zeros(c.a, nxi * nxi)
    let (rs, e2) = den.zeros(c.a, c.nxis * nt)
    let (qdrs, e3) = den.zeros(c.a, c.nxis * na)
    if e1 != ok || e2 != ok || e3 != ok {
        mem.reset(c.a, lb)
        ret false
    }
    let nl = p10(lambda)
    var j = 0usize
    while j < nxi {
        var i = 0usize
        while i < nxi {
            qk[i + j * nxi] = nl * rw[c.id[i] + j * nt]
            i += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < nt {
        var k = 0usize
        while k < nxi {
            rs[k + i * c.nxis] = rw[i + k * nt]
            k += 1usize
        }
        k = 0usize
        while k < c.nnull {
            rs[nxi + k + i * c.nxis] = c.s[i + k * nt]
            k += 1usize
        }
        i += 1usize
    }
    var p = 0usize
    while p < na {
        var k = 0usize
        while k < nxi {
            qdrs[p + k * na] = qw[p + k * na]
            k += 1usize
        }
        k = 0usize
        while k < c.nnull {
            qdrs[p + (nxi + k) * na] = c.qs[p + k * na]
            k += 1usize
        }
        p += 1usize
    }
    let e = hzdnewton(c.a, c.cd, c.nxis, qk, nxi, rs, nt, c.nobs, qdrs, na, c.qdwt, c.prec, c.maxiter, 2.220446049250313e-16f64, o)
    mem.reset(c.a, lb)
    ret e == ok && o.good
}

fn hz_adj(alpha: f64, mx: f64, trc: f64) -> f64 {
    var awk = mx * (3.0f64 - alpha) + alpha
    if awk > 3.0f64 { awk = 3.0f64 }
    if awk > alpha { ret (awk - alpha) * trc }
    ret 0.0f64
}

fn cvs1(c: *CvH, lambda: f64) -> f64 {
    var o: HzOut = zero
    if !hz_eval(c, c.rfix, c.qfix, lambda, &o) {
        c.bad = true
        ret nanf()
    }
    var mx = c.logla0 - lambda - 5.0f64
    if mx < 0.0f64 { mx = 0.0f64 }
    ret c.alpha * o.trc - o.fm + hz_adj(c.alpha, mx, o.trc)
}

fn cvm(c: *CvH, theta: []const f64) -> f64 {
    let lb = mem.mark(c.a)
    let nt = c.nt
    let nxi = c.nxi
    let nq = c.nq
    let sz = nt * nxi
    let qsz = c.na * nxi
    let (r0, e1) = den.zeros(c.a, sz)
    let (q0, e2) = den.zeros(c.a, qsz)
    if e1 != ok || e2 != ok {
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
        t = 0usize
        while t < sz {
            r0[t] = c.rwk[t]
            t += 1usize
        }
        i = 0usize
        while i < nq {
            let w = p10(c.thold[i])
            t = 0usize
            while t < qsz {
                q0[t] += w * c.qrk[i * qsz + t]
                t += 1usize
            }
            i += 1usize
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
    var o: HzOut = zero
    let good = hz_eval(c, r0, q0, c.lambda, &o)
    mem.reset(c.a, lb)
    if !good {
        c.bad = true
        ret nanf()
    }
    var mx = 0.0f64
    i = 0usize
    while i < nq {
        let u = theta[i] - c.logth0[i] - 5.0f64
        if u > mx { mx = u }
        i += 1usize
    }
    ret c.alpha * o.trc - o.fm + hz_adj(c.alpha, mx, o.trc)
}

fn cvm_wk(c: *CvH, theta: []const f64) -> f64 { ret c.scale * cvm(c, theta) + c.shift }

// the sums Sum 10^theta_i x_i of the nq blocks of sz
fn hz_comb(a: *mem.Arena, rk: []const f64, sz: usize, nq: usize, theta: []const f64) -> ([]f64, err) {
    let (r, e) = den.zeros(a, sz)
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

// the variance sums of msphzd: v.s per unpenalised column and v.r per basis column, summed over the covariate values
fn hz_var(qw: []const f64, qs: []const f64, qdwt: []const f64, na: usize, nxi: usize, nnull: usize) -> (f64, f64) {
    var sumr = 0.0f64
    var k = 0usize
    while k < nxi {
        var sm = 0.0f64
        var p = 0usize
        while p < na {
            sm += qdwt[p] * (qw[p + k * na] * qw[p + k * na])
            p += 1usize
        }
        sumr += sm
        k += 1usize
    }
    var sums = 0.0f64
    k = 0usize
    while k < nnull {
        var sm = 0.0f64
        var p = 0usize
        while p < na {
            sm += qdwt[p] * (qs[p + k * na] * qs[p + k * na])
            p += 1usize
        }
        sums += sm
        k += 1usize
    }
    ret (sums, sumr)
}

fn hz_trace_id(r: []const f64, id: []const usize, nt: usize, nxi: usize) -> f64 {
    var tr = 0.0f64
    var k = 0usize
    while k < nxi {
        tr += r[id[k] + k * nt]
        k += 1usize
    }
    ret tr
}

// msphzd for the nq kernels (blocks of nt by nxi in rk, of na by nxi in qrk)
fn msphzd(a: *mem.Arena, s: []const f64, rk: []const f64, id: []const usize, nobs: usize, qs: []const f64, qrk: []const f64, qdwt: []const f64, nt: usize, nxi: usize, nnull: usize, na: usize, nq: usize, prec: f64, maxiter: usize, alpha: f64, skip: bool, fix: []const f64, out: *HzFit) -> err {
    let sz = nt * nxi
    let qsz = na * nxi
    let nxis = nxi + nnull
    let (theta, e1) = den.zeros(a, nq)
    let (logth0, e2) = den.zeros(a, nq)
    let (cdv, e3) = den.zeros(a, nxis)
    let (thold, e4) = den.zeros(a, nq)
    let (la1, e5) = den.zeros(a, 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < nq {
        theta[i] = 0.0f64 - l10(hz_trace_id(rk[i * sz..(i + 1usize) * sz], id, nt, nxi))
        i += 1usize
    }
    var (qwk, ea) = hz_comb(a, qrk, qsz, nq, theta)
    if ea != ok { ret ea }
    var (vs, vr) = hz_var(qwk, qs, qdwt, na, nxi, nnull)
    var thw = 0.0f64
    if nnull > 0usize { thw = l10(vs / f64(nnull) / vr * f64(nxi)) / 2.0f64 }
    i = 0usize
    while i < nq {
        theta[i] = theta[i] + thw
        i += 1usize
    }
    var (rwk, eb) = hz_comb(a, rk, sz, nq, theta)
    if eb != ok { ret eb }
    let (qw2, ec) = hz_comb(a, qrk, qsz, nq, theta)
    if ec != ok { ret ec }
    qwk = qw2
    var logla0 = l10(vr / hz_trace_id(rwk, id, nt, nxi)) + 2.0f64 * thw
    var cx: CvH = zero
    cx.a = a
    cx.nxis = nxis
    cx.nxi = nxi
    cx.nt = nt
    cx.nobs = nobs
    cx.na = na
    cx.nq = nq
    cx.nnull = nnull
    cx.rk = rk
    cx.qrk = qrk
    cx.s = s
    cx.qs = qs
    cx.id = id
    cx.qdwt = qdwt
    cx.prec = prec
    cx.maxiter = maxiter
    cx.alpha = alpha
    cx.logth0 = logth0
    cx.rfix = rwk
    cx.qfix = qwk
    cx.thold = thold
    cx.cd = cdv
    cx.scale = 1.0f64
    cx.shift = 0.0f64
    var cvval = 0.0f64
    var est = 0.0f64
    var phase = 1usize
    if nq > 1usize { phase = 2usize }
    var round = 0usize
    while round < phase {
        cx.logla0 = logla0
        var la = logla0
        let mn0 = logla0 - 6.0f64
        let mx0 = logla0 + 6.0f64
        var looping = true
        while looping {
            var mn = la - 1.0f64
            if mn0 > mn { mn = mn0 }
            var mx = la + 1.0f64
            if mx0 < mx { mx = mx0 }
            let zz = gss.nlm0[CvH](&cx, cvs1, mn, mx)
            est = zz.est
            cvval = zz.fv
            var d1 = est - mn
            if mx - est < d1 { d1 = mx - est }
            var d2 = est - mn0
            if mx0 - est < d2 { d2 = mx0 - est }
            if d1 >= 0.1f64 || d2 < 0.1f64 { looping = false } else { la = est }
            if cx.bad { ret den.DenDiverge }
        }
        round += 1usize
        if round == 1usize && nq > 1usize {
            // theta adjustment with the norms of the fit, then the lambda search again from zero coefficients
            var k = 0usize
            i = 0usize
            while i < nq {
                var cq = 0.0f64
                var l = 0usize
                while l < nxi {
                    var rc = 0.0f64
                    k = 0usize
                    while k < nxi {
                        rc += cdv[k] * rk[i * sz + id[l] + k * nt]
                        k += 1usize
                    }
                    cq += rc * cdv[l]
                    l += 1usize
                }
                theta[i] = 2.0f64 * theta[i] + l10(cq)
                i += 1usize
            }
            let (qw3, ed) = hz_comb(a, qrk, qsz, nq, theta)
            if ed != ok { ret ed }
            let (vs2, vr2) = hz_var(qw3, qs, qdwt, na, nxi, nnull)
            vs = vs2
            vr = vr2
            thw = 0.0f64
            if nnull > 0usize { thw = l10(vs / f64(nnull) / vr * f64(nxi)) / 2.0f64 }
            i = 0usize
            while i < nq {
                theta[i] = theta[i] + thw
                i += 1usize
            }
            let (rw3, ee) = hz_comb(a, rk, sz, nq, theta)
            if ee != ok { ret ee }
            let (qw4, ef) = hz_comb(a, qrk, qsz, nq, theta)
            if ef != ok { ret ef }
            rwk = rw3
            qwk = qw4
            cx.rfix = rwk
            cx.qfix = qwk
            logla0 = l10(vr / hz_trace_id(rwk, id, nt, nxi)) + 2.0f64 * thw
            i = 0usize
            while i < nq {
                logth0[i] = theta[i] - logla0
                i += 1usize
            }
            i = 0usize
            while i < nxis {
                cdv[i] = 0.0f64
                i += 1usize
            }
        }
    }
    // fix = R's converged [lambda, theta.. (the estimate), theta.. (the last point nlm evaluated)]: the fit at those values, no search (the nlm search stops on rounding-dependent points)
    if fix.len > 0usize && nq > 1usize && !skip {
        est = fix[0usize]
        i = 0usize
        while i < nq {
            theta[i] = fix[1usize + i]
            i += 1usize
        }
    }
    cx.lambda = est
    out.nxi = nxi
    out.nnull = nnull
    out.nq = nq
    out.lambda = est
    let (cc, e6) = den.zeros(a, nxi)
    let (dd, e7) = den.zeros(a, nnull)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if nq == 1usize || skip {
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
        out.c = cc
        out.d = dd
        out.theta = theta
        out.cv = cvval
        ret ok
    }
    // theta search
    i = 0usize
    while i < nq {
        thold[i] = theta[i]
        i += 1usize
    }
    let (rw5, eg) = hz_comb(a, rk, sz, nq, theta)
    if eg != ok { ret eg }
    cx.rwk = rw5
    let c0 = cvm(&cx, theta)
    let tmp = gss.absf(c0)
    if cx.bad { ret den.DenDiverge }
    if tmp < 1.0f64 && tmp > 0.0001f64 { cx.scale = 10.0f64 / tmp }
    if tmp < 0.0001f64 {
        cx.scale = 100.0f64
        cx.shift = 10.0f64
    }
    var counter = 0usize
    var searching = fix.len == 0usize
    var fv = cx.scale * c0 + cx.shift
    if fix.len > 0usize {
        // R keeps the c and d of the last evaluation of nlm, not of its estimate: fix carries that point after the estimate
        let (tl, etl) = den.zeros(a, nq)
        if etl != ok { ret etl }
        i = 0usize
        while i < nq {
            tl[i] = fix[1usize + nq + i]
            i += 1usize
        }
        let _ = cvm(&cx, tl)
        if cx.bad { ret den.DenDiverge }
    }
    while searching {
        let r = nlm.nlm[CvH](a, &cx, cvm_wk, theta, 100usize, 7i64, 1.0f64)
        fv = r.fv
        if cx.bad { ret den.DenDiverge }
        if r.code <= 3i64 { searching = false } else {
            counter += 1usize
            if counter >= 5usize { searching = false }
        }
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
    out.c = cc
    out.d = dd
    out.theta = theta
    out.cv = (fv - cx.shift) / cx.scale
    ret ok
}

// the unpenalised columns of the hazard model: the constant, then the phi columns of den_terms
fn hz_terms(a: *mem.Arena, model: usize, lo: []const f64, hi: []const f64, x: []const f64, na: usize, xb: []const f64, nb: usize, s: []f64, r: []f64) -> err {
    let nn = den.den_nnull(model)
    let (s0, e) = den.zeros(a, na * nn)
    if e != ok { ret e }
    try den.den_terms(a, model, lo, hi, x, na, xb, nb, s0, r)
    var i = 0usize
    while i < na {
        s[i] = 1.0f64
        i += 1usize
    }
    var k = 0usize
    while k < nn * na {
        s[na + k] = s0[k]
        k += 1usize
    }
    ret ok
}

// sshzd: tend (nobs) the follow-up times, status (nobs) 1 for a failure, xc (nobs) the covariate (models 2 and 3), idp the 0-based positions among the failures of the nxi
// basis cases
fn sshzd(a: *mem.Arena, model: usize, nobs: usize, tend: []const f64, status: []const f64, xc: []const f64, idp: []const usize, nxi: usize, alpha: f64, prec: f64, maxiter: usize, skip: bool, fix: []const f64, out: *HzFit) -> err {
    var dim = 2usize
    if model == 1usize { dim = 1usize }
    var nt = 0usize
    var mx = tend[0usize]
    var i = 0usize
    while i < nobs {
        if status[i] > 0.5f64 { nt += 1usize }
        if tend[i] > mx { mx = tend[i] }
        i += 1usize
    }
    let (lo, e1) = den.zeros(a, 2usize)
    let (hi, e2) = den.zeros(a, 2usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    lo[0usize] = 0.0f64
    hi[0usize] = mx
    if dim == 2usize {
        let xl = gss.dmin(xc, 0usize, nobs)
        let xh = gss.dmax(xc, 0usize, nobs)
        lo[1usize] = xl - 0.05f64 * (xh - xl)
        hi[1usize] = xh + 0.05f64 * (xh - xl)
    }
    // failure rows and the basis rows
    let (xf, e3) = den.zeros(a, nt * dim)
    let (xb, e4) = den.zeros(a, nxi * dim)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var at = 0usize
    i = 0usize
    while i < nobs {
        if status[i] > 0.5f64 {
            xf[at] = tend[i]
            if dim == 2usize { xf[nt + at] = xc[i] }
            at += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nxi {
        xb[i] = xf[idp[i]]
        if dim == 2usize { xb[nxi + i] = xf[nt + idp[i]] }
        i += 1usize
    }
    // the unique covariate values in order of first appearance
    var nx = 1usize
    let (xu, e5) = den.zeros(a, nobs)
    let (xi, e6) = mem.alloc[usize](a, nobs + 1usize)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if dim == 2usize {
        nx = 0usize
        i = 0usize
        while i < nobs {
            var f = 0usize
            var found = false
            while f < nx && !found {
                if xu[f] == xc[i] { found = true } else { f += 1usize }
            }
            if !found {
                xu[nx] = xc[i]
                nx += 1usize
            }
            xi[i] = f
            i += 1usize
        }
    } else {
        i = 0usize
        while i < nobs {
            xi[i] = 0usize
            i += 1usize
        }
    }
    // Gauss-Legendre 200 over [0, mx]
    let nqd = 200usize
    let (gx, e7) = den.zeros(a, nqd)
    let (gw, e8) = den.zeros(a, nqd)
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    cub.gauss_legendre(nqd, gx, gw)
    let na = nqd * nx
    let (qx, e9) = den.zeros(a, na * dim)
    let (qdwt, e10) = den.zeros(a, na)
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    let range = hi[0usize] - lo[0usize]
    var j = 0usize
    while j < nx {
        var m = 0usize
        while m < nqd {
            qx[m + j * nqd] = lo[0usize] + range * (gx[m] + 1.0f64) / 2.0f64
            if dim == 2usize { qx[na + m + j * nqd] = xu[j] }
            m += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < nobs {
        var m = 0usize
        while m < nqd {
            if qx[m] <= tend[i] && qx[m] > 0.0f64 { qdwt[m + xi[i] * nqd] += 1.0f64 }
            m += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < nx {
        var m = 0usize
        while m < nqd {
            qdwt[m + j * nqd] = (range * gw[m] / 2.0f64 * qdwt[m + j * nqd]) / f64(nobs)
            m += 1usize
        }
        j += 1usize
    }
    let nq = den.den_nq(model)
    let nnull = 1usize + den.den_nnull(model)
    let (s, e11) = den.zeros(a, nt * nnull)
    let (rk, e12) = den.zeros(a, nq * nt * nxi)
    let (qs, e13) = den.zeros(a, na * nnull)
    let (qrk, e14) = den.zeros(a, nq * na * nxi)
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    try hz_terms(a, model, lo, hi, xf, nt, xb, nxi, s, rk)
    try hz_terms(a, model, lo, hi, qx, na, xb, nxi, qs, qrk)
    out.dim = dim
    out.model = model
    out.xb = xb
    out.lo = lo
    out.hi = hi
    try msphzd(a, s, rk, idp, nobs, qs, qrk, qdwt, nt, nxi, nnull, na, nq, prec, maxiter, alpha, skip, fix, out)
    ret ok
}

// the hazard rate exp(s d + sum 10^theta r c) at m rows xn (m by dim: time, then the covariate)
fn hzd_rate(a: *mem.Arena, f: *const HzFit, xn: []const f64, m: usize, rate: []f64) -> err {
    let nb = f.nxi
    let (sn, e1) = den.zeros(a, m * f.nnull)
    let (rn, e2) = den.zeros(a, f.nq * m * nb)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    try hz_terms(a, f.model, f.lo, f.hi, xn, m, f.xb, nb, sn, rn)
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
        rate[i] = math.exp[f64](eta)
        i += 1usize
    }
    ret ok
}
