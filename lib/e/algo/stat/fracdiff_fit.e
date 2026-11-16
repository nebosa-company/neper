// R fracdiff's `fracdiff(x, nar, nma)` fit (fdcore.c, Fraley's Haslett-Raftery approximate likelihood): Brent's minimiser over d of the
// concentrated likelihood, which for each d filters the series (`fdfilt`) and fits the ARMA coefficients by MINPACK's lmder on the
// conditional residuals (`ajqp`), the coefficients carried from one d to the next. d, ar and ma, the log likelihood, `fnormMin` and
// sigma are R's. `ar`, `ma` and `fnormMin` are those of the LAST d evaluated, as the C code leaves them. Not here: the Hessian and
// the covariance (fdhess.c), and the arima residuals R adds.

use e.algo.stat.minpacklm as ml
use e.math
use e.math.nmath as nm
use e.mem

type Fd = struct {
    n: usize,
    m: usize,
    p: usize,
    q: usize,
    pq: usize,
    maxpq: usize,
    nm_: usize,
    bignum: f64,
    wnv: f64,
    fnorm: f64,
    igamma: i64,
    y: []f64,
    amk: []f64,
    ak: []f64,
    vk: []f64,
    phi: []f64,
    a: []f64,
}

type Fit1 = struct { d: f64, hood: f64, fnorm: f64, wnv: f64, info: i64 }

fn max_f(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

// the filter of fdfilt: y (1-based, n entries), the sum of log vk; the C code's leftover z__ is vk[mcap]
fn fdfilt(f: *Fd, x: []const f64, d: f64) -> f64 {
    let n = f.n
    var mcap = f.m
    if n < mcap { mcap = n }
    f.amk[1usize] = 0.0f64
    f.ak[1usize] = 1.0f64
    var z = d / (1.0f64 - d)
    f.amk[2usize] = z * x[0usize]
    f.ak[2usize] = 1.0f64 - z
    f.phi[1usize] = z
    let g1 = 1.0f64 - d
    let t0 = 1.0f64 / nm.gammafn(g1)
    let g2 = 1.0f64 - d * 2.0f64
    if g2 <= 0.0f64 {
        f.igamma = 1i64
        ret 0.0f64
    }
    let g0 = nm.gammafn(g2) * (t0 * t0)
    f.vk[1usize] = g0
    f.vk[2usize] = g0 * (1.0f64 - z * z)
    var k = 3usize
    while k <= mcap {
        let km = k - 1usize
        let t = f64(km)
        let u = t - d
        var j = 1usize
        while j <= km - 1usize {
            let s = t - f64(j)
            f.phi[j] = f.phi[j] * (t * (s - d) / (u * s))
            j += 1usize
        }
        let v = d / u
        f.phi[km] = v
        f.vk[k] = f.vk[km] * (1.0f64 - v * v)
        var uu = 0.0f64
        var vv = 1.0f64
        j = 1usize
        while j <= km {
            let tt = f.phi[j]
            uu += tt * x[k - j - 1usize]
            vv -= tt
            j += 1usize
        }
        f.amk[k] = uu
        f.ak[k] = vv
        k += 1usize
    }
    if f.m < n {
        f.phi[1usize] = d
        var s = d
        var j = 2usize
        while j <= mcap {
            let u = f64(j)
            let t = f.phi[j - 1usize] * ((u - 1.0f64 - d) / u)
            s += t
            f.phi[j] = t
            j += 1usize
        }
        s = 1.0f64 - s
        var r = 0.0f64
        let u = f64(mcap)
        let t = u * f.phi[mcap]
        k = mcap + 1usize
        while k <= n {
            let km = k - mcap
            var zz = 0.0f64
            j = 1usize
            while j <= mcap {
                zz += f.phi[j] * x[k - j - 1usize]
                j += 1usize
            }
            if r == 0.0f64 {
                f.amk[k] = zz
                f.ak[k] = s
            } else {
                let v = t * (1.0f64 - math.pow[f64](u / f64(k), d)) / d
                f.amk[k] = zz + v * r / (f64(km) - 1.0f64)
                f.ak[k] = s - v
            }
            r += x[km - 1usize]
            k += 1usize
        }
    }
    var r = 0.0f64
    var s = 0.0f64
    k = 1usize
    while k <= n {
        let t = f.ak[k]
        var u = (x[k - 1usize] - f.amk[k]) * t
        var v = t * t
        if k <= mcap {
            z = f.vk[k]
            u = u / z
            v = v / z
        }
        r += u
        s += v
        k += 1usize
    }
    let hatmu = r / s
    s = 0.0f64
    k = 1usize
    while k <= mcap {
        s += math.log[f64](f.vk[k])
        k += 1usize
    }
    let slogvk = s
    k = 1usize
    while k <= n {
        var t = x[k - 1usize] - f.amk[k] - hatmu * f.ak[k]
        if k <= mcap { t = t / math.sqrt[f64](f.vk[k]) }
        f.y[k] = t
        k += 1usize
    }
    if f.pq == 0usize { ret slogvk }
    let u = z / f64(n)
    k = 1usize
    while k <= n {
        f.y[k] = f.y[k] - u
        k += 1usize
    }
    ret slogvk
}

fn sign_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 1.0f64
}

// the conditional residuals a(km), km = 1..nm, of the ARMA coefficients qp (ma first, then ar) on the filtered series y
fn ajqp_obj(f: *Fd, qp: []const f64, a: []f64) {
    var k = f.maxpq + 1usize
    while k <= f.n {
        let km = k - f.maxpq
        var t = 0.0f64
        var l = 1usize
        while l <= f.p {
            t -= qp[f.q + l - 1usize] * f.y[k - l]
            l += 1usize
        }
        var s = 0.0f64
        l = 1usize
        while l <= f.q {
            if km <= l { break }
            s += qp[l - 1usize] * a[km - l - 1usize]
            l += 1usize
        }
        s = f.y[k] + (t + s)
        if math.abs[f64](s) <= f.bignum { a[km - 1usize] = s } else { a[km - 1usize] = sign_of(s) * f.bignum }
        k += 1usize
    }
}

fn fd_f(f: *Fd, qp: []const f64, a: []f64) { ajqp_obj(f, qp, a) }

// the Jacobian (nm by pq, column-major), the residuals first re-evaluated at qp
fn fd_jac(f: *Fd, qp: []const f64, ajac: []f64) {
    ajqp_obj(f, qp, f.a)
    let nmr = f.nm_
    var i = 1usize
    while i <= f.pq {
        var k = f.maxpq + 1usize
        while k <= f.n {
            let km = k - f.maxpq
            var t = 0.0f64
            var l = 1usize
            while l <= f.q {
                if km <= l { break }
                t += qp[l - 1usize] * ajac[(i - 1usize) * nmr + km - l - 1usize]
                l += 1usize
            }
            var s = 0.0f64
            if i <= f.q {
                if km > i { s = f.a[km - i - 1usize] + t } else { s = t }
            } else {
                s = 0.0f64 - f.y[k - (i - f.q)] + t
            }
            if math.abs[f64](s) <= f.bignum { ajac[(i - 1usize) * nmr + km - 1usize] = s } else { ajac[(i - 1usize) * nmr + km - 1usize] = sign_of(s) * f.bignum }
            k += 1usize
        }
        i += 1usize
    }
}

// pqopt: the objective u/2 at d, with qp updated in place and the noise variance and fnorm recorded
fn pqopt(a: *mem.Arena, f: *Fd, x: []const f64, d: f64, qp: []f64, tol_f: f64, tol_x: f64, tol_g: f64) -> f64 {
    let slogvk = fdfilt(f, x, d)
    if f.igamma != 0i64 {
        f.wnv = 1.7976931348623157e308f64
        ret 1.7976931348623157e308f64
    }
    let t = f64(f.n)
    if f.pq == 0usize {
        var s = 0.0f64
        var k = 1usize
        while k <= f.n {
            s += f.y[k] * f.y[k]
            k += 1usize
        }
        f.wnv = s / t
    } else {
        let start = mem.mark(a)
        let (lo, e1) = mem.alloc[f64](a, f.pq)
        let (hi, e2) = mem.alloc[f64](a, f.pq)
        if e1 != ok || e2 != ok { ret 1.7976931348623157e308f64 }
        var i = 0usize
        while i < f.pq {
            lo[i] = 0.0f64 - 1.0e308f64
            hi[i] = 1.0e308f64
            i += 1usize
        }
        let (fit, fe) = ml.nls_lm_der[Fd](a, fd_f, fd_jac, f, f.nm_, f.pq, qp, lo, hi, tol_f, tol_x, tol_g, 100i64, 1000000000i64)
        if fe != ok { ret 1.7976931348623157e308f64 }
        let dev = fit.deviance
        let info = fit.info
        mem.reset(a, start)
        if info == 0i64 {
            f.wnv = 1.7976931348623157e308f64
            ret 1.7976931348623157e308f64
        }
        f.fnorm = math.sqrt[f64](dev)
        f.wnv = f.fnorm * f.fnorm / f64(f.nm_ - 1usize)
    }
    let u = t * (math.log[f64](f.wnv) + 2.8378f64) + slogvk
    ret u / 2.0f64
}

// fracdf: Brent's fmin over d in drange from dinit; qp (ma then ar, length p + q) is the start and receives the last fit
fn fracdf(a: *mem.Arena, x: []const f64, m: usize, p: usize, q: usize, dtol0: f64, dmin: f64, dmax: f64, dinit: f64, qp: []f64) -> (Fit1, err) {
    let n = x.len
    var res: Fit1 = zero
    var mm = m
    if mm == 0usize { mm = 100usize }
    var f: Fd = zero
    f.n = n
    f.m = mm
    f.p = p
    f.q = q
    f.pq = p + q
    if p >= q { f.maxpq = p } else { f.maxpq = q }
    f.nm_ = n - f.maxpq
    let epsmin = 1.1102230246251565e-16f64
    let epsmax = 2.220446049250313e-16f64
    f.bignum = 1.0f64 / epsmin
    let epspt5 = math.sqrt[f64](epsmin)
    let epsp25 = math.sqrt[f64](epspt5)
    let epspt3 = math.pow[f64](epsmin, 0.3f64)
    let epsp75 = math.pow[f64](epsmin, 0.75f64)
    var dtol = dtol0
    if dtol > 0.1f64 { dtol = 0.1f64 }
    var tol_d = 0.0f64
    var tol_f = 0.0f64
    if dtol <= 0.0f64 {
        tol_d = epsp25
        tol_f = epspt3
    } else {
        tol_d = max_f(dtol, epspt5)
        tol_f = max_f(dtol / 10.0f64, epsp75)
    }
    let (y, e1) = mem.alloc[f64](a, n + 2usize)
    let (amk, e2) = mem.alloc[f64](a, n + 2usize)
    let (ak, e3) = mem.alloc[f64](a, n + 2usize)
    let (vk, e4) = mem.alloc[f64](a, mm + 3usize)
    let (phi, e5) = mem.alloc[f64](a, mm + 3usize)
    let (aa, e6) = mem.alloc[f64](a, n + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (res, e1) }
    f.y = y
    f.amk = amk
    f.ak = ak
    f.vk = vk
    f.phi = phi
    f.a = aa
    let cc = 0.38196601125011f64
    var lo = dmin
    var hi = dmax
    var vv = 0.0f64
    if dinit > lo + tol_d && dinit < hi - tol_d { vv = dinit } else { vv = lo + cc * (hi - lo) }
    var ww = vv
    var xx = vv
    var uu = xx
    var dd = 0.0f64
    var ee = 0.0f64
    var nopt = 1i64
    var fx = pqopt(a, &f, x, xx, qp, tol_f, tol_d, tol_f)
    var fv = fx
    var fw = fx
    var fu = 0.0f64
    let tol3 = max_f(tol_d, 0.0f64) / 3.0f64
    let eps = math.sqrt[f64](epsmax)
    var delta = 0.0f64
    var going = true
    while going {
        if f.igamma != 0i64 {
            res.info = 2i64
            ret (res, ok)
        }
        let hh = (lo + hi) * 0.5f64
        let tol1 = eps * (math.abs[f64](xx) + 1.0f64) + tol3
        let tol2 = tol1 * 2.0f64
        delta = math.abs[f64](xx - hh) + (hi - lo) * 0.5f64
        if delta <= tol2 { break }
        if nopt >= 100i64 { break }
        var rr = 0.0f64
        var ss = 0.0f64
        var tt = 0.0f64
        if math.abs[f64](ee) > tol1 {
            rr = (xx - ww) * (fx - fv)
            ss = (xx - vv) * (fx - fw)
            tt = (xx - vv) * ss - (xx - ww) * rr
            ss = (ss - rr) * 2.0f64
            if ss <= 0.0f64 { ss = 0.0f64 - ss } else { tt = 0.0f64 - tt }
            rr = ee
            ee = dd
        }
        if math.abs[f64](tt) >= math.abs[f64](ss * 0.5f64 * rr) || tt <= ss * (lo - xx) || tt >= ss * (hi - xx) {
            if xx >= hh { ee = lo - xx } else { ee = hi - xx }
            dd = cc * ee
        } else {
            dd = tt / ss
            uu = xx + dd
            if uu - lo < tol2 || hi - uu < tol2 {
                dd = tol1
                if xx >= hh { dd = 0.0f64 - dd }
            }
        }
        if math.abs[f64](dd) >= tol1 {
            uu = xx + dd
        } else if dd <= 0.0f64 {
            uu = xx - tol1
        } else {
            uu = xx + tol1
        }
        nopt += 1i64
        fu = pqopt(a, &f, x, uu, qp, tol_f, tol_d, tol_f)
        if fx >= fu {
            if uu >= xx { lo = xx } else { hi = xx }
            vv = ww
            fv = fw
            ww = xx
            fw = fx
            xx = uu
            fx = fu
        } else {
            if uu >= xx { hi = uu } else { lo = uu }
            if fu > fw && ww != xx {
                if fu <= fv || vv == xx || vv == ww {
                    vv = uu
                    fv = fu
                }
            } else {
                vv = ww
                fv = fw
                ww = uu
                fw = fu
            }
        }
    }
    res.d = xx
    res.hood = 0.0f64 - fx
    res.fnorm = f.fnorm
    res.wnv = f.wnv
    res.info = 0i64
    ret (res, ok)
}
