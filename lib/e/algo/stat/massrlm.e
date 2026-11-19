// R MASS rlm in full: M and MM estimation (the S start from lqs), the Huber, Hampel and bisquare psi functions with their
// derivatives, the three scale estimators (MAD, Huber, proposal 2), init by least squares, lts or given coefficients,
// inverse-variance and case weights, the test vector choices, and summary.rlm (XtX and XtWX standard errors).
//
// A port of rlm.default and summary.rlm of MASS 7.3-65. x is n by p, column-major.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.sort
use e.algo.stat.mass as ms
use e.algo.stat.masslqs as lq
use e.math
use e.math.dist as dist
use e.mem

error Singular
error BadInput

// psi: 0 Huber (a = k), 1 Hampel (a, b, c), 2 bisquare (a = c)
type Opts = struct {
    psi: usize,
    pa: f64,
    pb: f64,
    pc: f64,
    scale_est: usize,
    k2: f64,
    mm: bool,
    wt_case: bool,
    has_weights: bool,
    init: usize,
    maxit: usize,
    acc: f64,
    test_vec: usize,
    lq_nsamp: f64,
    lq_psamp: usize,
    mm_c: f64,
}

// rlm.default's defaults: Huber psi with k = 1.345, MAD scale, least-squares start, 20 steps, acc 1e-4, test.vec "resid"
fn default_opts() -> Opts {
    ret Opts { psi: 0usize, pa: 1.345f64, pb: 4.0f64, pc: 8.0f64, scale_est: 0usize, k2: 1.345f64, mm: false, wt_case: false, has_weights: false, init: 0usize, maxit: 20usize, acc: 1.0e-4f64, test_vec: 0usize, lq_nsamp: -9.0f64, lq_psamp: 0usize, mm_c: 0.0f64 }
}

fn psi_w(o: *const Opts, u: f64) -> f64 {
    let au = math.abs[f64](u)
    if o.psi == 0usize {
        var v = o.pa / au
        if v > 1.0f64 { v = 1.0f64 }
        ret v
    }
    if o.psi == 2usize {
        var t = math.abs[f64](u / o.pa)
        if t > 1.0f64 { t = 1.0f64 }
        ret (1.0f64 - t * t) * (1.0f64 - t * t)
    }
    var uu = au + 1.0e-50f64
    if uu > o.pc { uu = o.pc }
    var num = 0.0f64
    if uu <= o.pa { num = uu } else if uu <= o.pb { num = o.pa } else { num = o.pa * (o.pc - uu) / (o.pc - o.pb) }
    ret num / uu
}

fn psi_d(o: *const Opts, u: f64) -> f64 {
    if o.psi == 0usize {
        if math.abs[f64](u) <= o.pa { ret 1.0f64 }
        ret 0.0f64
    }
    if o.psi == 2usize {
        let t = (u / o.pa) * (u / o.pa)
        if t < 1.0f64 { ret (1.0f64 - t) * (1.0f64 - 5.0f64 * t) }
        ret 0.0f64
    }
    var uu = math.abs[f64](u) + 1.0e-50f64
    if uu > o.pc { uu = o.pc }
    if math.abs[f64](u) <= o.pc {
        if uu <= o.pa { ret 1.0f64 }
        if uu <= o.pb { ret 0.0f64 }
        ret 0.0f64 - o.pa / (o.pc - o.pb)
    }
    ret 0.0f64
}

// lm.wfit(x, y, w): the coefficients (aliased ones 0 when some weight is zero) and the residuals
fn wfit(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, coef: []f64, resid: []f64) -> err {
    var m = 0usize
    var i = 0usize
    while i < n {
        if w[i] != 0.0f64 { m += 1usize }
        i += 1usize
    }
    let (xs, e1) = mem.alloc[f64](a, m * p + 1usize)
    let (ys, e2) = mem.alloc[f64](a, m + 1usize)
    let (sw, e3) = mem.alloc[f64](a, m + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var r = 0usize
    i = 0usize
    while i < n {
        if w[i] != 0.0f64 {
            let s = math.sqrt[f64](w[i])
            sw[r] = s
            ys[r] = y[i] * s
            var c = 0usize
            while c < p {
                xs[r + m * c] = x[i + n * c] * s
                c += 1usize
            }
            r += 1usize
        }
        i += 1usize
    }
    let (f, fe) = decomp.lm_fit(a, xs, m, p, ys[0usize..m], 1.0e-7f64)
    if fe != ok { ret fe }
    var c = 0usize
    while c < p {
        coef[c] = f.coef[c]
        c += 1usize
    }
    r = 0usize
    i = 0usize
    while i < n {
        if w[i] != 0.0f64 {
            resid[i] = f.residuals[r] / sw[r]
            r += 1usize
        } else {
            var fv = 0.0f64
            c = 0usize
            while c < p {
                if coef[c] == coef[c] { fv += x[i + n * c] * coef[c] }
                c += 1usize
            }
            resid[i] = y[i] - fv
        }
        i += 1usize
    }
    if m < n {
        c = 0usize
        while c < p {
            if coef[c] != coef[c] { coef[c] = 0.0f64 }
            c += 1usize
        }
    }
    ret ok
}

fn irls_delta(old: []const f64, nw: []const f64) -> f64 {
    var s = 0.0f64
    var o = 0.0f64
    var i = 0usize
    while i < old.len {
        s += (old[i] - nw[i]) * (old[i] - nw[i])
        o += old[i] * old[i]
        i += 1usize
    }
    var d = o
    if d < 1.0e-20f64 { d = 1.0e-20f64 }
    ret math.sqrt[f64](s / d)
}

fn irls_rrxwr(x: []const f64, n: usize, p: usize, w: []const f64, r: []const f64) -> f64 {
    var best = 0.0f64
    var j = 0usize
    while j < p {
        var num = 0.0f64
        var den = 0.0f64
        var i = 0usize
        while i < n {
            let sw = math.sqrt[f64](w[i])
            num += r[i] * sw * x[i + n * j]
            den += sw * (x[i + n * j] * x[i + n * j])
            i += 1usize
        }
        let v = math.abs[f64](num / math.sqrt[f64](den))
        if v > best { best = v }
        j += 1usize
    }
    var sr = 0.0f64
    var i = 0usize
    while i < n {
        sr += math.sqrt[f64](w[i]) * r[i] * r[i]
        i += 1usize
    }
    ret best / math.sqrt[f64](sr)
}

fn cmp_idx(ctx: *[]const f64, p: usize, q: usize) -> i32 {
    let v = *ctx
    if v[p] < v[q] { ret 0i32 - 1i32 }
    if v[p] > v[q] { ret 1i32 }
    ret 0i32
}

// wmad(x, w): the weighted median of |x| / 0.6745
fn wmad(a: *mem.Arena, x: []const f64, w: []const f64) -> f64 {
    let n = x.len
    let (ab, e1) = mem.alloc[f64](a, n)
    let (o, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        ab[i] = math.abs[f64](x[i])
        o[i] = i
        i += 1usize
    }
    var ref: []const f64 = ab
    let se = sort.stable_in_place_by[usize, []const f64](a, o, &ref, cmp_idx)
    if se != ok { ret 0.0f64 / 0.0f64 }
    var tot = 0.0f64
    i = 0usize
    while i < n {
        tot += w[i]
        i += 1usize
    }
    let (pcs, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var cum = 0.0f64
    var cnt = 0usize
    i = 0usize
    while i < n {
        cum += w[o[i]]
        pcs[i] = cum / tot
        if pcs[i] < 0.5f64 { cnt += 1usize }
        i += 1usize
    }
    let pn = pcs[cnt]
    if pn > 0.5f64 { ret ab[o[cnt]] / 0.6745f64 }
    ret (ab[o[cnt]] + ab[o[cnt + 1usize]]) / (2.0f64 * 0.6745f64)
}

type Rlm = struct {
    coef: []f64,
    residuals: []f64,
    wresid: []f64,
    w: []f64,
    s: f64,
    conv: []f64,
    nconv: usize,
    converged: bool,
}

fn median_abs(a: *mem.Arena, r: []const f64) -> f64 {
    let (ab, e) = mem.alloc[f64](a, r.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < r.len {
        ab[i] = math.abs[f64](r[i])
        i += 1usize
    }
    ret ms.median_of(a, ab)
}

// rlm.default. weights (n) is read only when o.has_weights; w0 is the `w` argument (n, ones by default); init_coef is read when o.init == 2.
fn rlm(a: *mem.Arena, g: *rng.Rng, x0: []const f64, n: usize, p: usize, y0: []const f64, weights: []const f64, w0: []const f64, init_coef: []const f64, o: *const Opts) -> (Rlm, err) {
    var out: Rlm = zero
    let (qrf, qe) = decomp.qr(a, x0, n, p, 1.0e-7f64)
    if qe != ok { ret (out, qe) }
    if qrf.rank < p { ret (out, Singular) }
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (y, e2) = mem.alloc[f64](a, n)
    let (w, e3) = mem.alloc[f64](a, n)
    let (coef, e4) = mem.alloc[f64](a, p)
    let (resid, e5) = mem.alloc[f64](a, n)
    let (oldv, e6) = mem.alloc[f64](a, n + p)
    let (conv, e7) = mem.alloc[f64](a, o.maxit + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (out, mem.Full) }
    var i = 0usize
    while i < n * p {
        x[i] = x0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        y[i] = y0[i]
        w[i] = w0[i]
        i += 1usize
    }
    var use_wt = false
    if o.has_weights {
        i = 0usize
        while i < n {
            if weights[i] < 0.0f64 { ret (out, BadInput) }
            i += 1usize
        }
        if !o.wt_case {
            i = 0usize
            while i < n {
                let fac = math.sqrt[f64](weights[i])
                y[i] = y[i] * fac
                var c = 0usize
                while c < p {
                    x[i + n * c] = x[i + n * c] * fac
                    c += 1usize
                }
                i += 1usize
            }
        } else {
            i = 0usize
            while i < n {
                w[i] = w[i] * weights[i]
                i += 1usize
            }
            use_wt = true
        }
    }
    var scale = 0.0f64
    var psi_o = *o
    if !o.mm {
        if o.init == 0usize {
            let fe = wfit(a, x, n, p, y, w, coef, resid)
            if fe != ok { ret (out, fe) }
        } else if o.init == 1usize {
            var ns = o.lq_nsamp
            if ns == -9.0f64 { ns = 200.0f64 }
            let (lf, le) = lq.lqs(a, g, x, n, p, y, false, 1usize, -1.0f64, o.lq_psamp, ns, true, 1.548f64)
            if le != ok { ret (out, le) }
            i = 0usize
            while i < p {
                coef[i] = lf.coef[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                resid[i] = lf.residuals[i]
                i += 1usize
            }
        } else {
            i = 0usize
            while i < p {
                coef[i] = init_coef[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                var fv = 0.0f64
                var c = 0usize
                while c < p {
                    fv += x[i + n * c] * coef[c]
                    c += 1usize
                }
                resid[i] = y[i] - fv
                i += 1usize
            }
        }
    } else {
        var ns = o.lq_nsamp
        if ns == -9.0f64 { ns = -1.0f64 }
        let (lf, le) = lq.lqs(a, g, x, n, p, y, false, 3usize, -1.0f64, o.lq_psamp, ns, true, 1.548f64)
        if le != ok { ret (out, le) }
        i = 0usize
        while i < p {
            coef[i] = lf.coef[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            resid[i] = lf.residuals[i]
            i += 1usize
        }
        psi_o.psi = 2usize
        psi_o.pa = 4.685f64
        if o.mm_c > 1.548f64 { psi_o.pa = o.mm_c }
        scale = lf.scale
    }
    let kk2 = o.k2
    var n1 = f64(n)
    if use_wt {
        n1 = 0.0f64
        i = 0usize
        while i < n {
            n1 += weights[i]
            i += 1usize
        }
    }
    n1 -= f64(p)
    let theta = 2.0f64 * dist.pnorm(kk2, 0.0f64, 1.0f64, true, false) - 1.0f64
    let gamma = theta + kk2 * kk2 * (1.0f64 - theta) - 2.0f64 * kk2 * dist.dnorm(kk2, 0.0f64, 1.0f64, false)
    if !o.mm {
        if !use_wt { scale = 1.4826f64 * median_abs(a, resid) } else { scale = wmad(a, resid, weights) }
    }
    var done = false
    var nconv = 0usize
    var iiter = 1usize
    let (wbuf, e8) = mem.alloc[f64](a, n)
    if e8 != ok { ret (out, mem.Full) }
    while iiter <= o.maxit && !done {
        // testpv
        if o.test_vec == 0usize {
            i = 0usize
            while i < n {
                oldv[i] = resid[i]
                i += 1usize
            }
        } else if o.test_vec == 1usize {
            i = 0usize
            while i < p {
                oldv[i] = coef[i]
                i += 1usize
            }
        } else if o.test_vec == 2usize {
            i = 0usize
            while i < n {
                oldv[i] = w[i]
                i += 1usize
            }
        }
        var stop = false
        if !o.mm {
            if o.scale_est == 0usize {
                if !use_wt { scale = median_abs(a, resid) / 0.6745f64 } else { scale = wmad(a, resid, weights) }
            } else {
                var ss = 0.0f64
                i = 0usize
                while i < n {
                    var r2 = resid[i] * resid[i]
                    let lim = (o.k2 * scale) * (o.k2 * scale)
                    if lim < r2 { r2 = lim }
                    if use_wt { ss += weights[i] * r2 } else { ss += r2 }
                    i += 1usize
                }
                scale = math.sqrt[f64](ss / (n1 * gamma))
            }
            if scale == 0.0f64 {
                done = true
                stop = true
            }
        }
        if !stop {
            i = 0usize
            while i < n {
                wbuf[i] = psi_w(&psi_o, resid[i] / scale)
                if use_wt { wbuf[i] = wbuf[i] * weights[i] }
                i += 1usize
            }
            let fe = wfit(a, x, n, p, y, wbuf, coef, resid)
            if fe != ok { ret (out, fe) }
            i = 0usize
            while i < n {
                w[i] = wbuf[i]
                i += 1usize
            }
            var convi = 0.0f64
            if o.test_vec == 3usize {
                convi = irls_rrxwr(x, n, p, w, resid)
            } else if o.test_vec == 0usize {
                convi = irls_delta(oldv[0usize..n], resid)
            } else if o.test_vec == 1usize {
                convi = irls_delta(oldv[0usize..p], coef)
            } else {
                convi = irls_delta(oldv[0usize..n], w)
            }
            conv[nconv] = convi
            nconv += 1usize
            done = convi <= o.acc
            iiter += 1usize
        }
    }
    // fitted from the unweighted x and the coefficients; wresid is the iteration's residuals
    let (res2, e9) = mem.alloc[f64](a, n)
    if e9 != ok { ret (out, mem.Full) }
    i = 0usize
    while i < n {
        var fv = 0.0f64
        var c = 0usize
        while c < p {
            fv += x0[i + n * c] * coef[c]
            c += 1usize
        }
        res2[i] = y0[i] - fv
        i += 1usize
    }
    out = Rlm { coef: coef, residuals: res2, wresid: resid, w: w, s: scale, conv: conv, nconv: nconv, converged: done }
    ret (out, ok)
}

type Summ = struct { coef: []f64, se: []f64, stddev: f64, rdf: f64, cov: []f64 }

fn pmean(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i]
        i += 1usize
    }
    ret s / f64(v.len)
}

// summary.rlm(fit, method): method 0 "XtX", 1 "XtWX". The fit must come from rlm with the same opts, x0 and weights.
fn summary(a: *mem.Arena, f: *const Rlm, x0: []const f64, n: usize, p: usize, weights: []const f64, o: *const Opts, method: usize) -> (Summ, err) {
    var out: Summ = zero
    let psi_o = *o
    var po = psi_o
    if o.mm {
        po.psi = 2usize
        po.pa = 4.685f64
        if o.mm_c > 1.548f64 { po.pa = o.mm_c }
    }
    let s = f.s
    let (psiprime, e1) = mem.alloc[f64](a, n)
    let (wts, e2) = mem.alloc[f64](a, n)
    let (xx, e3) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok { ret (out, mem.Full) }
    var i = 0usize
    while i < n {
        wts[i] = 1.0f64
        if o.has_weights { wts[i] = weights[i] }
        psiprime[i] = psi_d(&po, f.wresid[i] / s)
        i += 1usize
    }
    var stddev = 0.0f64
    var rdf = 0.0f64
    var wmul = 0.0f64
    var ssum = 0.0f64
    if o.wt_case {
        var sw = 0.0f64
        i = 0usize
        while i < n {
            sw += wts[i]
            i += 1usize
        }
        rdf = sw - f64(p)
        i = 0usize
        while i < n {
            let wi = psi_w(&po, f.wresid[i] / s)
            ssum += wts[i] * (f.wresid[i] * wi) * (f.wresid[i] * wi)
            i += 1usize
        }
        let sq = ssum / rdf
        var m1 = 0.0f64
        var m2 = 0.0f64
        i = 0usize
        while i < n {
            m1 += wts[i] * psiprime[i]
            m2 += wts[i] * psiprime[i] * psiprime[i]
            i += 1usize
        }
        let mn = m1 / sw
        let kappa = 1.0f64 + f64(p) * (m2 - m1 * m1 / sw) / (sw - 1.0f64) / (sw * mn * mn)
        stddev = math.sqrt[f64](sq) * (kappa / mn)
    } else {
        rdf = f64(n - p)
        i = 0usize
        while i < n {
            let wi = psi_w(&po, f.wresid[i] / s)
            ssum += (f.wresid[i] * wi) * (f.wresid[i] * wi)
            i += 1usize
        }
        let sq = ssum / rdf
        let mn = pmean(psiprime)
        var vs = 0.0f64
        i = 0usize
        while i < n {
            vs += (psiprime[i] - mn) * (psiprime[i] - mn)
            i += 1usize
        }
        vs /= f64(n - 1usize)
        let kappa = 1.0f64 + f64(p) * vs / (f64(n) * mn * mn)
        stddev = math.sqrt[f64](sq) * (kappa / mn)
    }
    i = 0usize
    while i < n {
        var m = 1.0f64
        if o.has_weights { m = math.sqrt[f64](weights[i]) }
        var c = 0usize
        while c < p {
            xx[i + n * c] = x0[i + n * c] * m
            c += 1usize
        }
        i += 1usize
    }
    if method == 1usize {
        var sw = 0.0f64
        var swp = 0.0f64
        i = 0usize
        while i < n {
            sw += wts[i]
            swp += wts[i] * psi_w(&po, f.wresid[i] / s)
            i += 1usize
        }
        let mn = swp / sw
        i = 0usize
        while i < n {
            let m = math.sqrt[f64](psi_w(&po, f.wresid[i] / s) / mn)
            var c = 0usize
            while c < p {
                xx[i + n * c] = xx[i + n * c] * m
                c += 1usize
            }
            i += 1usize
        }
    }
    let (qf, qe) = decomp.qr(a, xx, n, p, 1.0e-7f64)
    if qe != ok { ret (out, qe) }
    // rinv = solve(R, I) for the upper triangle R
    let (rinv, e4) = mem.alloc[f64](a, p * p)
    let (se, e5) = mem.alloc[f64](a, p)
    let (cu, e6) = mem.alloc[f64](a, p * p)
    if e4 != ok || e5 != ok || e6 != ok { ret (out, mem.Full) }
    var col = 0usize
    while col < p {
        var r = p
        while r > 0usize {
            r -= 1usize
            var sum = 0.0f64
            if r == col { sum = 1.0f64 }
            var c = r + 1usize
            while c < p {
                sum -= qf.qr[r + n * c] * rinv[c + p * col]
                c += 1usize
            }
            rinv[r + p * col] = sum / qf.qr[r + n * r]
        }
        col += 1usize
    }
    var r = 0usize
    while r < p {
        var ss = 0.0f64
        var c = 0usize
        while c < p {
            ss += rinv[r + p * c] * rinv[r + p * c]
            c += 1usize
        }
        se[r] = math.sqrt[f64](ss) * stddev
        r += 1usize
    }
    r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s2 = 0.0f64
            var k = 0usize
            while k < p {
                s2 += rinv[r + p * k] * rinv[c + p * k]
                k += 1usize
            }
            cu[r + p * c] = s2
            c += 1usize
        }
        r += 1usize
    }
    out = Summ { coef: f.coef, se: se, stddev: stddev, rdf: rdf, cov: cu }
    ret (out, ok)
}

// predict.rlm(fit, newdata, se.fit, interval): newx is m by p column-major. The se.fit use the qr of sqrt(weights) x and the fit's scale s, the intervals the normal
// quantile (df is Inf). interval 0 none, 1 confidence, 2 prediction (the variance s^2 added, newdata weights 1). Writes fit, se, lwr, upr (m each).
fn predict(a: *mem.Arena, f: *const Rlm, x0: []const f64, n: usize, p: usize, weights: []const f64, o: *const Opts, newx: []const f64, m: usize, level: f64, interval: usize, fit: []f64, se: []f64, lwr: []f64, upr: []f64) -> err {
    let (sm, e) = summary(a, f, x0, n, p, weights, o, 0usize)
    if e != ok { ret e }
    let q = dist.qnorm((1.0f64 + level) / 2.0f64, 0.0f64, 1.0f64, true, false)
    var i = 0usize
    while i < m {
        var v = 0.0f64
        var r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                v += newx[i + m * r] * sm.cov[r + p * c] * newx[i + m * c]
                c += 1usize
            }
            r += 1usize
        }
        var ft = 0.0f64
        r = 0usize
        while r < p {
            ft += newx[i + m * r] * f.coef[r]
            r += 1usize
        }
        let sef = f.s * math.sqrt[f64](v)
        fit[i] = ft
        se[i] = sef
        var w = sef
        if interval == 2usize { w = math.sqrt[f64](sef * sef + f.s * f.s) }
        lwr[i] = ft - q * w
        upr[i] = ft + q * w
        i += 1usize
    }
    ret ok
}
