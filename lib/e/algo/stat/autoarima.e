// forecast::auto.arima(x)$model for a series of frequency m: the KPSS test picks d (ndiffs), the stepwise search over
// (p, q, P, Q, constant) by AICc, the seasonal difference by forecast's seasonal strength test (mstl with na.interp), each candidate fitted by stats::arima (e.algo.stat.arimafit), and the state-space model of the winner.
// A series longer than 150 is searched by CSS and the candidates refitted by ML in the order of their approximate criterion, as
// auto.arima does; series that are constant after differencing take its closed-form branches.
//
// Also here: the exhaustive search (stepwise = FALSE), ndiffs by KPSS, ADF and PP, nsdiffs by seas, OCSB and CH (uroot response-surface p-value).
// Not here: xreg, lambda, the HEGY test, truncate, a user method.

use e.math
use e.mem
use e.algo.stat.kalman as kal
use e.algo.stat.arimafit as af
use e.algo.stat.arimafc as fcs
use e.algo.stat.pracma as pr
use e.algo.stat.urca as ur
use e.algo.stat.urca2 as ur2
use e.algo.stat.olsfit as ols
use e.algo.stat.chtab as cht
use e.algo.stat.stlpkg as stlp
use e.algo.linalg.decomp as decomp

error NoSuitableModel
error TooShortSeries

type ArIc = struct { fit: af.ArFit, ic: f64 }

// the chosen model: its fit, criterion (AICc) and orders (p, d, q)(P, D, Q), the constant flag; closed marks the branches for a constant series
type AaRes = struct { fit: af.ArFit, ic: f64, p: usize, d: usize, q: usize, sp: usize, sd: usize, sq: usize, cst: bool, closed: bool, sigma2: f64 }

type Srch = struct {
    ar: *mem.Arena, x: []const f64, d: usize, sd: usize, per: usize, approx: bool, offset: f64,
    rp: []usize, rq: []usize, rsp: []usize, rsq: []usize, rc: []usize, ric: []f64, k: usize, best: ArIc, bestmade: bool,
    bp: usize, bq: usize, bsp: usize, bsq: usize, bc: usize
}

fn inf_f() -> f64 { ret 1.0e308f64 * 10.0f64 }

// all.equal(x, rep(x[1], length(x))): a missing value anywhere means not constant (unless everything is missing)
fn is_constant(x: []const f64) -> bool {
    let n = x.len
    if n == 0usize { ret true }
    var nn = 0usize
    var i = 0usize
    while i < n {
        if af.ar_isnan(x[i]) { nn += 1usize }
        i += 1usize
    }
    if af.ar_isnan(x[0usize]) { ret nn == n }
    if nn > 0usize { ret false }
    var xy = 0.0f64
    var xn = 0.0f64
    var any_diff = false
    i = 0usize
    while i < n {
        if x[i] != x[0usize] {
            any_diff = true
            xy += math.abs[f64](x[i] - x[0usize])
            xn += math.abs[f64](x[i])
        }
        i += 1usize
    }
    if !any_diff { ret true }
    xy = xy / f64(n)
    xn = xn / f64(n)
    if xn > 1.5e-8f64 { xy = xy / xn }
    ret xy <= 1.5e-8f64
}

// diff(x, differences = dd) keeping missing values in place (they spread to the next difference)
fn diff_n(ar: *mem.Arena, x: []const f64, dd: usize) -> []f64 {
    let n = x.len
    let w = af.fa(ar, n)
    var i = 0usize
    while i < n {
        w[i] = x[i]
        i += 1usize
    }
    var len = n
    var k = 0usize
    while k < dd {
        i = 0usize
        while i + 1usize < len {
            w[i] = w[i + 1usize] - w[i]
            i += 1usize
        }
        if len > 0usize { len -= 1usize }
        k += 1usize
    }
    ret w[0usize..len]
}

// diff(x, lag = m) keeping missing values in place
fn diff_lag(ar: *mem.Arena, x: []const f64, m: usize) -> []f64 {
    let n = x.len
    let w = af.fa(ar, n)
    var i = 0usize
    while i + m < n {
        w[i] = x[i + m] - x[i]
        i += 1usize
    }
    ret w[0usize..n - m]
}

// the p-value urca's ur.kpss(type = "mu") gives forecast::ndiffs: linear in the statistic between the 10, 5, 2.5 and 1 percent critical values, clamped
fn kpss_pvalue(stat: f64) -> f64 {
    var cv: [4]f64 = zero
    var pv: [4]f64 = zero
    cv[0usize] = 0.347f64
    cv[1usize] = 0.463f64
    cv[2usize] = 0.574f64
    cv[3usize] = 0.739f64
    pv[0usize] = 0.1f64
    pv[1usize] = 0.05f64
    pv[2usize] = 0.025f64
    pv[3usize] = 0.01f64
    if stat <= cv[0usize] { ret pv[0usize] }
    if stat >= cv[3usize] { ret pv[3usize] }
    var i = 0usize
    while i < 3usize {
        if stat <= cv[i + 1usize] {
            let w = (stat - cv[i]) / (cv[i + 1usize] - cv[i])
            ret pv[i] + w * (pv[i + 1usize] - pv[i])
        }
        i += 1usize
    }
    ret pv[3usize]
}

// the KPSS decision of ndiffs on x without its missing values: true means difference again
fn kpss_diff(ar: *mem.Arena, x: []const f64) -> bool {
    let st = mem.mark(ar)
    let n = x.len
    let y = af.fa(ar, n)
    var m = 0usize
    var i = 0usize
    while i < n {
        if !af.ar_isnan(x[i]) {
            y[m] = x[i]
            m += 1usize
        }
        i += 1usize
    }
    let lag = usize(math.floor[f64](3.0f64 * math.sqrt[f64](f64(m)) / 13.0f64))
    let (stat, lmax, e) = ur.ur_kpss(ar, y[0usize..m], 0u8, 3u8, lag)
    var res = false
    if e == ok { res = kpss_pvalue(stat) < 0.05f64 }
    mem.reset(ar, st)
    ret res
}

fn drop_missing(ar: *mem.Arena, x: []const f64) -> []f64 {
    var m = 0usize
    var i = 0usize
    while i < x.len {
        if !af.ar_isnan(x[i]) { m += 1usize }
        i += 1usize
    }
    let y = af.fa(ar, m)
    m = 0usize
    i = 0usize
    while i < x.len {
        if !af.ar_isnan(x[i]) {
            y[m] = x[i]
            m += 1usize
        }
        i += 1usize
    }
    ret y
}

// approx(c(c1, c5, c10), c(0.01, 0.05, 0.1), xout = stat, rule = 2): urca's critical-value table read as a p-value
fn pval3(c1: f64, c5: f64, c10: f64, stat: f64) -> f64 {
    if stat <= c1 { ret 0.01f64 }
    if stat >= c10 { ret 0.1f64 }
    if stat <= c5 { ret 0.01f64 + (0.05f64 - 0.01f64) * ((stat - c1) / (c5 - c1)) }
    ret 0.05f64 + (0.1f64 - 0.05f64) * ((stat - c5) / (c10 - c5))
}

// one unit-root decision of ndiffs on x (level type, alpha 0.05): (difference again, decision available); test 0 kpss, 1 adf (type drift,
// one lag), 2 pp (Z-tau, constant, short lags). A test that errors answers "no more differences"; a missing statistic ends the loop.
fn ur_diff(ar: *mem.Arena, x: []const f64, test: usize) -> (bool, bool) {
    if test == 0usize { ret (kpss_diff(ar, x), true) }
    if test == 1usize {
        let (r, e) = ur.ur_df(ar, x, 1u8, 1usize, 0u8)
        if e != ok { ret (false, true) }
        if r.tau != r.tau { ret (false, false) }
        let pv = pval3(ur.df_critical(1u8, 0usize, 0usize, r.n), ur.df_critical(1u8, 0usize, 1usize, r.n), ur.df_critical(1u8, 0usize, 2usize, r.n), r.tau)
        ret (pv > 0.05f64, true)
    }
    let (pp, pe) = ur2.ur_pp(ar, x, 1u8, 0u8, 0i64 - 1i64)
    if pe != ok { ret (false, true) }
    if pp.stat != pp.stat { ret (false, false) }
    let pv2 = pval3(pp.cval1, pp.cval5, pp.cval10, pp.stat)
    ret (pv2 > 0.05f64, true)
}

// forecast::ndiffs(x, test, type = "level", max.d)
fn ndiffs_t(ar: *mem.Arena, x0: []const f64, test: usize, maxd: usize) -> usize {
    var x: []const f64 = drop_missing(ar, x0)
    var d = 0usize
    if is_constant(x) { ret d }
    let (d0, v0) = ur_diff(ar, x, test)
    if !v0 { ret d }
    var dodiff = d0
    while dodiff && d < maxd {
        d += 1usize
        x = diff_n(ar, x, 1usize)
        if is_constant(x) { ret d }
        let (d1, v1) = ur_diff(ar, x, test)
        if !v1 { ret d - 1usize }
        dodiff = d1
    }
    ret d
}

// forecast::ndiffs(x, test = "kpss", max.d = 2)
fn ndiffs(ar: *mem.Arena, x0: []const f64, maxd: usize) -> usize { ret ndiffs_t(ar, x0, 0usize, maxd) }

fn min_modulus_ok(ar: *mem.Arena, v: []const f64, ar_part: bool, minroot: f64) -> (f64, bool) {
    var last = 0usize
    var i = 0usize
    while i < v.len {
        if math.abs[f64](v[i]) > 1.0e-8f64 { last = i + 1usize }
        i += 1usize
    }
    if last == 0usize { ret (minroot, true) }
    let st = mem.mark(ar)
    let z = af.fa(ar, last + 1usize)
    let re = af.fa(ar, last)
    let im = af.fa(ar, last)
    z[0usize] = 1.0f64
    i = 0usize
    while i < last {
        if ar_part { z[i + 1usize] = 0.0f64 - v[i] } else { z[i + 1usize] = v[i] }
        i += 1usize
    }
    let deg = pr.polyroot_c(ar, z, re, im)
    var mr = minroot
    var good = deg >= 0i64
    if good {
        i = 0usize
        while i < usize(deg) {
            let md = math.sqrt[f64](re[i] * re[i] + im[i] * im[i])
            if md < mr { mr = md }
            i += 1usize
        }
    }
    mem.reset(ar, st)
    ret (mr, good)
}

// forecast's myarima for a candidate (p, d, q)(P, D, Q)[m]: the fit and its information criterion (Inf when the fit fails or its roots are unsafe)
fn myarima(ar: *mem.Arena, x: []const f64, p: usize, d: usize, q: usize, sp: usize, sd: usize, sq: usize, m: usize, constant: bool, approximation: bool, offset: f64) -> ArIc {
    var out: ArIc = zero
    out.ic = inf_f()
    var n = 0usize
    var i = 0usize
    while i < x.len {
        if !af.ar_isnan(x[i]) { n += 1usize }
        i += 1usize
    }
    let diffs = d + sd
    var kind = 0usize
    if diffs == 1usize && constant { kind = 2usize }
    if diffs == 0usize && constant { kind = 1usize }
    var method = 0usize
    if approximation { method = 2usize }
    let fit = af.arima_fit_s(ar, x, p, d, q, sp, sd, sq, m, kind, 0.0f64 / 0.0f64, method)
    if !fit.good { ret out }
    let nstar = f64(n) - f64(d) - f64(sd) * f64(m)
    let npar = f64(fit.nfree) + 1.0f64
    var aic = fit.aic
    if method == 2usize { aic = offset + nstar * math.log[f64](fit.sigma2) + 2.0f64 * npar }
    if af.ar_isnan(aic) {
        out.fit = fit
        ret out
    }
    var ic = aic + 2.0f64 * npar * (npar + 1.0f64) / (nstar - npar - 1.0f64)
    var minroot = 2.0f64
    if p + sp > 0usize {
        let (mr, rgood) = min_modulus_ok(ar, fit.phi, true, minroot)
        minroot = mr
        if !rgood { ic = inf_f() }
    }
    if q + sq > 0usize && ic < inf_f() {
        let (mr, rgood) = min_modulus_ok(ar, fit.theta, false, minroot)
        minroot = mr
        if !rgood { ic = inf_f() }
    }
    if minroot < 1.01f64 || !fit.varok { ic = inf_f() }
    out.fit = fit
    out.ic = ic
    ret out
}

fn srch_newmodel(s: *Srch, p: usize, q: usize, sp: usize, sq: usize, cst: bool) -> bool {
    var c1 = 0usize
    if cst { c1 = 1usize }
    var i = 0usize
    while i < s.k {
        if s.rp[i] == p && s.rq[i] == q && s.rsp[i] == sp && s.rsq[i] == sq && s.rc[i] == c1 { ret false }
        i += 1usize
    }
    ret true
}

// fits a candidate as result number `slot` (0-based) and keeps it when it beats the best so far; returns whether it did
fn srch_try(s: *Srch, slot: usize, p: usize, q: usize, sp: usize, sq: usize, cst: bool) -> bool {
    let r = myarima(s.ar, s.x, p, s.d, q, sp, s.sd, sq, s.per, cst, s.approx, s.offset)
    s.rp[slot] = p
    s.rq[slot] = q
    s.rsp[slot] = sp
    s.rsq[slot] = sq
    var c1 = 0usize
    if cst { c1 = 1usize }
    s.rc[slot] = c1
    s.ric[slot] = r.ic
    var better = false
    if !s.bestmade {
        better = true
    } else if r.ic < s.best.ic {
        better = true
    }
    if better {
        s.best = r
        s.bestmade = true
        s.bp = p
        s.bq = q
        s.bsp = sp
        s.bsq = sq
        s.bc = c1
    }
    ret better
}

// the model of the closed-form branches: Arima(x, order = c(0, d, 0), seasonal = c(0, D, 0), fixed = mean) and its variants
fn fixed_model(ar: *mem.Arena, x: []const f64, d: usize, sd: usize, m: usize, kind: usize, xfixed: f64) -> (AaRes, err) {
    let fit = af.arima_fit_s(ar, x, 0usize, d, 0usize, 0usize, sd, 0usize, m, kind, xfixed, 0usize)
    var r: AaRes = zero
    r.fit = fit
    r.d = d
    r.sd = sd
    r.cst = kind > 0usize
    r.closed = true
    r.sigma2 = fcs.arima_sigma2(fit.resid, fit.nused, fit.nfree)
    if !fit.good { ret (r, NoSuitableModel) }
    let nstar = f64(fit.nused)
    let npar = f64(fit.nfree) + 1.0f64
    r.ic = fit.aic + 2.0f64 * npar * (nstar / (nstar - npar - 1.0f64) - 1.0f64)
    ret (r, ok)
}

fn mean_present(x: []const f64) -> f64 {
    var s = 0.0f64
    var m = 0usize
    var i = 0usize
    while i < x.len {
        if !af.ar_isnan(x[i]) {
            s += x[i]
            m += 1usize
        }
        i += 1usize
    }
    ret s / f64(m)
}

// approx(idx, v[idx], 1:n, rule = 2) for the observed positions of orig: linear between observed values, the end values held
fn interp_linear(ar: *mem.Arena, orig: []const f64, v: []const f64) -> []f64 {
    let n = orig.len
    let o = af.fa(ar, n)
    var i = 0usize
    while i < n {
        o[i] = v[i]
        if af.ar_isnan(orig[i]) {
            var lo = n
            var j = i
            while j > 0usize && lo == n {
                j -= 1usize
                if !af.ar_isnan(orig[j]) { lo = j }
            }
            var hi = n
            j = i + 1usize
            while j < n && hi == n {
                if !af.ar_isnan(orig[j]) { hi = j }
                j += 1usize
            }
            if lo == n && hi == n {
                o[i] = v[i]
            } else if lo == n {
                o[i] = v[hi]
            } else if hi == n {
                o[i] = v[lo]
            } else {
                o[i] = v[lo] + (v[hi] - v[lo]) * f64(i - lo) / f64(hi - lo)
            }
        }
        i += 1usize
    }
    ret o
}


// forecast::na.interp(x) for a series of frequency m: linear when m <= 1 or at most 2 m values are observed, otherwise a Fourier and polynomial
// regression fills the gaps, a robust STL of the filled series gives the seasonal part, and the gaps become the linearly interpolated seasonally
// adjusted series plus that seasonal part (the linear fill instead when that leaves the data range by more than half its width). false when STL fails.
fn na_interp(ar: *mem.Arena, x: []const f64, m: usize, outv: []f64) -> bool {
    let n = x.len
    var nobs = 0usize
    var i = 0usize
    var lo = 0.0f64
    var hi = 0.0f64
    while i < n {
        if !af.ar_isnan(x[i]) {
            if nobs == 0usize {
                lo = x[i]
                hi = x[i]
            }
            if x[i] < lo { lo = x[i] }
            if x[i] > hi { hi = x[i] }
            nobs += 1usize
        }
        i += 1usize
    }
    let lin = interp_linear(ar, x, x)
    if nobs == n || m <= 1usize || nobs <= 2usize * m {
        i = 0usize
        while i < n {
            outv[i] = lin[i]
            i += 1usize
        }
        ret true
    }
    if n <= 2usize * m { ret false }
    var kk = m / 2usize
    if kk > 5usize { kk = 5usize }
    var dg = n / 10usize
    if dg < 1usize { dg = 1usize }
    if dg > 6usize { dg = 6usize }
    let ncolmax = 1usize + 2usize * kk + dg
    let xm = af.fa(ar, n * ncolmax)
    i = 0usize
    while i < n {
        xm[i] = 1.0f64
        i += 1usize
    }
    var nc = 1usize
    var j = 1usize
    while j <= kk {
        if (2usize * j) % m != 0usize {
            i = 0usize
            while i < n {
                let rr = (j * (i + 1usize)) % m
                xm[nc * n + i] = math.sin[f64](2.0f64 * 3.141592653589793f64 * f64(rr) / f64(m))
                i += 1usize
            }
            nc += 1usize
        }
        i = 0usize
        while i < n {
            let rr = (j * (i + 1usize)) % m
            xm[nc * n + i] = math.cos[f64](2.0f64 * 3.141592653589793f64 * f64(rr) / f64(m))
            i += 1usize
        }
        nc += 1usize
        j += 1usize
    }
    // orthonormal polynomial columns (the span is what poly() gives)
    let pstart = nc
    var dgi = 1usize
    while dgi <= dg {
        i = 0usize
        while i < n {
            let tc = (f64(i + 1usize) - f64(n + 1usize) / 2.0f64) / (f64(n) / 2.0f64)
            xm[nc * n + i] = math.pow[f64](tc, f64(dgi))
            i += 1usize
        }
        var pass = 0usize
        while pass < 2usize {
            var ci = 0usize
            while ci < nc {
                if ci == 0usize || ci >= pstart {
                    var dp = 0.0f64
                    var nn2 = 0.0f64
                    i = 0usize
                    while i < n {
                        dp += xm[nc * n + i] * xm[ci * n + i]
                        nn2 += xm[ci * n + i] * xm[ci * n + i]
                        i += 1usize
                    }
                    i = 0usize
                    while i < n {
                        xm[nc * n + i] -= dp / nn2 * xm[ci * n + i]
                        i += 1usize
                    }
                }
                ci += 1usize
            }
            pass += 1usize
        }
        var nrm = 0.0f64
        i = 0usize
        while i < n {
            nrm += xm[nc * n + i] * xm[nc * n + i]
            i += 1usize
        }
        nrm = math.sqrt[f64](nrm)
        i = 0usize
        while i < n {
            xm[nc * n + i] = xm[nc * n + i] / nrm
            i += 1usize
        }
        nc += 1usize
        dgi += 1usize
    }
    // lm on the observed rows, prediction at the missing ones
    let xo = af.fa(ar, nobs * nc)
    let yo = af.fa(ar, nobs)
    var r = 0usize
    i = 0usize
    while i < n {
        if !af.ar_isnan(x[i]) {
            var c1 = 0usize
            while c1 < nc {
                xo[c1 * nobs + r] = xm[c1 * n + i]
                c1 += 1usize
            }
            yo[r] = x[i]
            r += 1usize
        }
        i += 1usize
    }
    let (fit, fe) = decomp.lm_fit(ar, xo, nobs, nc, yo, 1.0e-7f64)
    if fe != ok { ret false }
    let xf = af.fa(ar, n)
    i = 0usize
    while i < n {
        xf[i] = x[i]
        if af.ar_isnan(x[i]) {
            var pred = 0.0f64
            var c2 = 0usize
            while c2 < nc {
                if !af.ar_isnan(fit.coef[c2]) { pred += fit.coef[c2] * xm[c2 * n + i] }
                c2 += 1usize
            }
            xf[i] = pred
        }
        i += 1usize
    }
    let seas = af.fa(ar, n)
    let trend = af.fa(ar, n)
    let rw = af.fa(ar, n)
    let se = stlp.stl(ar, xf, m, false, 11.0f64, 0i64, 0.0f64, 1i64, 0.0f64, 1i64, 0usize, 0usize, 0usize, true, seas, trend, rw)
    if se != ok { ret false }
    let sa = af.fa(ar, n)
    i = 0usize
    while i < n {
        sa[i] = xf[i] - seas[i]
        i += 1usize
    }
    let sai = interp_linear(ar, x, sa)
    let res = af.fa(ar, n)
    var mx = 0.0f64
    var mn = 0.0f64
    i = 0usize
    while i < n {
        res[i] = x[i]
        if af.ar_isnan(x[i]) { res[i] = sai[i] + seas[i] }
        if i == 0usize {
            mx = res[i]
            mn = res[i]
        }
        if res[i] > mx { mx = res[i] }
        if res[i] < mn { mn = res[i] }
        i += 1usize
    }
    let dr = hi - lo
    var useres = true
    if mx > hi + 0.5f64 * dr || mn < lo - 0.5f64 * dr { useres = false }
    i = 0usize
    while i < n {
        if useres { outv[i] = res[i] } else { outv[i] = lin[i] }
        i += 1usize
    }
    ret true
}

fn var_present(v: []const f64) -> f64 {
    var m = 0.0f64
    var c = 0usize
    var i = 0usize
    while i < v.len {
        if !af.ar_isnan(v[i]) {
            m += v[i]
            c += 1usize
        }
        i += 1usize
    }
    m = m / f64(c)
    var s = 0.0f64
    i = 0usize
    while i < v.len {
        if !af.ar_isnan(v[i]) { s += (v[i] - m) * (v[i] - m) }
        i += 1usize
    }
    ret s / f64(c - 1usize)
}

// forecast:::seas.heuristic(x) for a series of frequency m: 1 - var(remainder) / var(remainder + seasonal) from mstl, clamped to [0, 1]; false when STL fails
fn seas_strength(ar: *mem.Arena, x: []const f64, m: usize) -> (f64, bool) {
    let n = x.len
    let xi = af.fa(ar, n)
    if !na_interp(ar, x, m, xi) { ret (0.0f64, false) }
    let seas = af.fa(ar, n)
    let trend = af.fa(ar, n)
    let rw = af.fa(ar, n)
    let se = stlp.stl(ar, xi, m, false, 11.0f64, 0i64, 0.0f64, 1i64, 0.0f64, 1i64, 0usize, 0usize, 0usize, false, seas, trend, rw)
    if se != ok { ret (0.0f64, false) }
    let rem = af.fa(ar, n)
    let rps = af.fa(ar, n)
    var i = 0usize
    while i < n {
        rem[i] = (xi[i] - seas[i]) - trend[i]
        rps[i] = rem[i] + seas[i]
        if af.ar_isnan(x[i]) {
            rem[i] = af.ar_nan()
            rps[i] = af.ar_nan()
        }
        i += 1usize
    }
    let vare = var_present(rem)
    var st = 1.0f64 - vare / var_present(rps)
    if st > 1.0f64 { st = 1.0f64 }
    if st < 0.0f64 { st = 0.0f64 }
    ret (st, true)
}

// the lower Cholesky factor L of the symmetric n x n row-major matrix a (a = L L'); false when it is not positive definite
fn chol_lower(a: []const f64, n: usize, l: []f64) -> bool {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = a[i * n + j]
            var k = 0usize
            while k < j {
                s -= l[i * n + k] * l[j * n + k]
                k += 1usize
            }
            if i == j {
                if !(s > 0.0f64) { ret false }
                l[i * n + i] = math.sqrt[f64](s)
            } else {
                l[i * n + j] = s / l[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// x = L^-1 b by forward substitution (L lower, n x n row-major)
fn fwd_solve(l: []const f64, n: usize, b: []const f64, x: []f64) {
    var i = 0usize
    while i < n {
        var s = b[i]
        var k = 0usize
        while k < i {
            s -= l[i * n + k] * x[k]
            k += 1usize
        }
        x[i] = s / l[i * n + i]
        i += 1usize
    }
}

// uroot's ch.rs.pvalue for the joint trigonometric test (all S - 1 seasonal frequencies, no lagged regressor): the response-surface
// quantiles at sample size nobs, the 13 quantiles nearest the statistic, and a generalised least squares fit of the chi-square(2) quantile
fn ch_pvalue(ar: *mem.Arena, stat: f64, per: usize, nobs: usize) -> f64 {
    let nrq = 221usize
    let tab = af.fa(ar, nrq * 8usize)
    cht.ch_ft_q0(tab)
    let rq = af.fa(ar, nrq)
    rq[0usize] = 0.0001f64
    rq[1usize] = 0.0002f64
    rq[2usize] = 0.0005f64
    var i = 0usize
    while i < 10usize {
        rq[3usize + i] = 0.001f64 * f64(i + 1usize)
        i += 1usize
    }
    i = 0usize
    while i < 195usize {
        rq[13usize + i] = 0.015f64 + 0.005f64 * f64(i)
        i += 1usize
    }
    i = 0usize
    while i < 10usize {
        rq[208usize + i] = 0.99f64 + 0.001f64 * f64(i)
        i += 1usize
    }
    rq[218usize] = 0.9995f64
    rq[219usize] = 0.9998f64
    rq[220usize] = 0.9999f64
    let n = f64(nobs)
    let sf = f64(per)
    var xe: [7]f64 = zero
    xe[0usize] = 1.0f64
    xe[1usize] = 1.0f64 / n
    xe[2usize] = 1.0f64 / (n * n)
    xe[3usize] = sf / n
    xe[4usize] = sf / (n * n)
    xe[5usize] = sf - 1.0f64
    xe[6usize] = (sf - 1.0f64) * (sf - 1.0f64)
    let q1 = af.fa(ar, nrq)
    i = 0usize
    while i < nrq {
        var s = 0.0f64
        var j = 0usize
        while j < 7usize {
            s += tab[i * 8usize + j] * xe[j]
            j += 1usize
        }
        q1[i] = s
        i += 1usize
    }
    // sort(): insertion sort, the quantiles are nearly ordered already
    i = 1usize
    while i < nrq {
        let key = q1[i]
        var j = i
        while j > 0usize && q1[j - 1usize] > key {
            q1[j] = q1[j - 1usize]
            j -= 1usize
        }
        q1[j] = key
        i += 1usize
    }
    if stat < q1[0usize] { ret 1.0f64 }
    if stat > q1[nrq - 1usize] { ret 0.0f64 }
    var mas = 0usize
    var md = math.abs[f64](q1[0usize] - stat)
    i = 1usize
    while i < nrq {
        let dd = math.abs[f64](q1[i] - stat)
        if dd < md {
            md = dd
            mas = i
        }
        i += 1usize
    }
    // 1-based as in the R code: mascer = mas + 1, window 6, nobsreg 13
    let mascer = mas + 1usize
    var minq = 1usize
    if mascer > 6usize { minq = mascer - 6usize }
    var maxq = nrq
    if mascer + 6usize < nrq { maxq = mascer + 6usize }
    if maxq == 1usize { maxq = 13usize }
    if maxq == nrq { minq = maxq - 13usize + 1usize }
    let w = maxq - minq + 1usize
    let qi = af.fa(ar, w)
    let pri = af.fa(ar, w)
    let si = af.fa(ar, w)
    i = 0usize
    while i < w {
        qi[i] = q1[minq - 1usize + i]
        pri[i] = rq[minq - 1usize + i]
        si[i] = tab[(minq - 1usize + i) * 8usize + 7usize]
        i += 1usize
    }
    let yv = af.fa(ar, w)
    let p1 = af.fa(ar, w)
    i = 0usize
    while i < w {
        yv[i] = 0.0f64 - 2.0f64 * math.log[f64](1.0f64 - pri[i])
        p1[i] = math.sqrt[f64](pri[i] / (1.0f64 - pri[i]))
        i += 1usize
    }
    let sg = af.fa(ar, w * w)
    i = 0usize
    while i < w {
        var j = i
        while j < w {
            let v = (p1[i] * si[i]) * (si[j] / p1[j])
            sg[i * w + j] = v
            sg[j * w + i] = v
            if i == j { sg[i * w + i] = (v + v) - si[i] * si[i] }
            j += 1usize
        }
        i += 1usize
    }
    let lm = af.fa(ar, w * w)
    i = 0usize
    while i < w * w {
        lm[i] = 0.0f64
        i += 1usize
    }
    if !chol_lower(sg, w, lm) { ret af.ar_nan() }
    let py = af.fa(ar, w)
    fwd_solve(lm, w, yv, py)
    let px = af.fa(ar, w * 4usize)
    let col = af.fa(ar, w)
    let outc = af.fa(ar, w)
    var c = 0usize
    while c < 4usize {
        i = 0usize
        while i < w {
            col[i] = 1.0f64
            if c == 1usize { col[i] = qi[i] }
            if c == 2usize { col[i] = qi[i] * qi[i] }
            if c == 3usize { col[i] = qi[i] * qi[i] * qi[i] }
            i += 1usize
        }
        fwd_solve(lm, w, col, outc)
        i = 0usize
        while i < w {
            px[c * w + i] = outc[i]
            i += 1usize
        }
        c += 1usize
    }
    let (o, oe) = ols.fit(ar, px, w, 4usize, py)
    if oe != ok { ret af.ar_nan() }
    let vc = o.coef[0usize] + o.coef[1usize] * stat + o.coef[2usize] * (stat * stat) + o.coef[3usize] * (stat * stat * stat)
    ret math.exp[f64](0.0f64 - math.abs[f64](vc) / 2.0f64)
}

// uroot::ch.test(x, type = "trigonometric")$pvalues["joint"] (Canova-Hansen joint test of deterministic seasonality, Newey-West
// order round(S (n / 100)^0.25), response-surface p-value); NaN when the regression fails
fn ch_joint_p(ar: *mem.Arena, x: []const f64, per: usize) -> (f64, f64) {
    let n = x.len
    let st = mem.mark(ar)
    let k = per - 1usize
    let sd = af.fa(ar, n * k)
    let sh = per / 2usize
    var iseven = 0usize
    if per % 2usize == 0usize { iseven = 1usize }
    let kk = sh - iseven
    var t = 0usize
    while t < n {
        var j = 0usize
        while j < kk {
            let ang = (2.0f64 * f64(j + 1usize) * 3.141592653589793f64 / f64(per)) * f64(t + 1usize)
            sd[(2usize * j) * n + t] = math.cos[f64](ang)
            sd[(2usize * j + 1usize) * n + t] = math.sin[f64](ang)
            j += 1usize
        }
        if iseven == 1usize {
            var sg = 0.0f64 - 1.0f64
            if t % 2usize == 1usize { sg = 1.0f64 }
            sd[(per - 2usize) * n + t] = sg
        }
        t += 1usize
    }
    let xr = af.fa(ar, n * per)
    t = 0usize
    while t < n {
        xr[t] = 1.0f64
        t += 1usize
    }
    var i = 0usize
    while i < n * k {
        xr[n + i] = sd[i]
        i += 1usize
    }
    let (o, oe) = ols.fit(ar, xr, n, per, x)
    if oe != ok {
        mem.reset(ar, st)
        ret (af.ar_nan(), af.ar_nan())
    }
    let nw = usize(math.floor[f64](f64(per) * math.pow[f64](f64(n) / 100.0f64, 0.25f64) + 0.5f64))
    let sde = af.fa(ar, n * k)
    i = 0usize
    while i < k {
        t = 0usize
        while t < n {
            sde[i * n + t] = sd[i * n + t] * o.resid[t]
            t += 1usize
        }
        i += 1usize
    }
    let om = af.fa(ar, k * k)
    var a = 0usize
    while a < k {
        var b = 0usize
        while b < k {
            var s = 0.0f64
            t = 0usize
            while t < n {
                s += sde[a * n + t] * sde[b * n + t]
                t += 1usize
            }
            om[a * k + b] = 0.5f64 * s
            b += 1usize
        }
        a += 1usize
    }
    var lag = 1usize
    while lag <= nw {
        let wt = 1.0f64 - f64(lag) / f64(nw + 1usize)
        a = 0usize
        while a < k {
            var b = 0usize
            while b < k {
                var s = 0.0f64
                t = 0usize
                while t + lag < n {
                    s += sde[a * n + t] * sde[b * n + t + lag]
                    t += 1usize
                }
                om[a * k + b] += wt * s
                b += 1usize
            }
            a += 1usize
        }
        lag += 1usize
    }
    let oms = af.fa(ar, k * k)
    a = 0usize
    while a < k {
        var b = 0usize
        while b < k {
            oms[a * k + b] = (om[a * k + b] + om[b * k + a]) / f64(n)
            b += 1usize
        }
        a += 1usize
    }
    let fh = af.fa(ar, n * k)
    i = 0usize
    while i < k {
        var cs = 0.0f64
        t = 0usize
        while t < n {
            cs += sde[i * n + t]
            fh[i * n + t] = cs
            t += 1usize
        }
        i += 1usize
    }
    let fcp = af.fa(ar, k * k)
    a = 0usize
    while a < k {
        var b = 0usize
        while b < k {
            var s = 0.0f64
            t = 0usize
            while t < n {
                s += fh[a * n + t] * fh[b * n + t]
                t += 1usize
            }
            fcp[a * k + b] = s
            b += 1usize
        }
        a += 1usize
    }
    // trace(Omega^-1 Fcp) by the Cholesky factor: solve Omega X = Fcp column by column
    let lm = af.fa(ar, k * k)
    i = 0usize
    while i < k * k {
        lm[i] = 0.0f64
        i += 1usize
    }
    if !chol_lower(oms, k, lm) {
        mem.reset(ar, st)
        ret (af.ar_nan(), af.ar_nan())
    }
    var tr = 0.0f64
    let cvec = af.fa(ar, k)
    let yvec = af.fa(ar, k)
    let xvec = af.fa(ar, k)
    var c = 0usize
    while c < k {
        i = 0usize
        while i < k {
            cvec[i] = fcp[i * k + c]
            i += 1usize
        }
        fwd_solve(lm, k, cvec, yvec)
        // back substitution with L'
        i = k
        while i > 0usize {
            i -= 1usize
            var s = yvec[i]
            var j = i + 1usize
            while j < k {
                s -= lm[j * k + i] * xvec[j]
                j += 1usize
            }
            xvec[i] = s / lm[i * k + i]
        }
        tr += xvec[c]
        c += 1usize
    }
    let stat = tr / (f64(n) * f64(n))
    let pv = ch_pvalue(ar, stat, per, n - per)
    mem.reset(ar, st)
    ret (stat, pv)
}

// nsdiffs's Canova-Hansen decision: difference when the joint p-value is below 0.05 (a failed test answers 0, no difference)
fn ch_diff(ar: *mem.Arena, x: []const f64, m: usize) -> bool {
    let (cs, pv) = ch_joint_p(ar, x, m)
    ret pv < 0.05f64
}

// forecast::ocsb.test(x, maxlag, lag.method = "fixed") regression for `lag` lags on the rows common to maxlag: (t value of Z5, AIC of the
// fit, rank, usable); times are 1-based as in the R code, y = (1 - B)(1 - B^m) x, Z4 = lambda(B)(1 - B^m) x, Z5 = lambda(B)(1 - B) x
fn ocsb_fit(ar: *mem.Arena, x: []const f64, m: usize, lag: usize, maxlag: usize) -> (f64, f64, bool) {
    let n = x.len
    let st = mem.mark(ar)
    let dm = af.fa(ar, n + 1usize)
    let dx = af.fa(ar, n + 1usize)
    let yv = af.fa(ar, n + 1usize)
    var t = 1usize
    while t <= n {
        dm[t] = af.ar_nan()
        dx[t] = af.ar_nan()
        yv[t] = af.ar_nan()
        if t > m { dm[t] = x[t - 1usize] - x[t - 1usize - m] }
        if t > 1usize { dx[t] = x[t - 1usize] - x[t - 2usize] }
        t += 1usize
    }
    t = m + 2usize
    while t <= n {
        yv[t] = dm[t] - dm[t - 1usize]
        t += 1usize
    }
    let t0 = m + 2usize + maxlag
    if t0 + lag + 4usize > n {
        mem.reset(ar, st)
        ret (af.ar_nan(), af.ar_nan(), false)
    }
    let nr = n - t0 + 1usize
    let phi = af.fa(ar, lag + 1usize)
    var k = 0usize
    if lag > 0usize {
        let xm = af.fa(ar, nr * lag)
        let yr = af.fa(ar, nr)
        var r = 0usize
        while r < nr {
            yr[r] = yv[t0 + r]
            k = 0usize
            while k < lag {
                xm[k * nr + r] = yv[t0 + r - 1usize - k]
                k += 1usize
            }
            r += 1usize
        }
        let (o, oe) = ols.fit(ar, xm, nr, lag, yr)
        if oe != ok {
            mem.reset(ar, st)
            ret (af.ar_nan(), af.ar_nan(), false)
        }
        k = 0usize
        while k < lag {
            phi[k] = o.coef[k]
            if phi[k] != phi[k] { phi[k] = 0.0f64 }
            k += 1usize
        }
    }
    let z4 = af.fa(ar, n + 1usize)
    let z5 = af.fa(ar, n + 1usize)
    t = 1usize
    while t <= n {
        z4[t] = af.ar_nan()
        z5[t] = af.ar_nan()
        if t >= m + 1usize + lag {
            var v = dm[t]
            k = 0usize
            while k < lag {
                v -= phi[k] * dm[t - 1usize - k]
                k += 1usize
            }
            z4[t] = v
        }
        if t >= 2usize + lag {
            var v2 = dx[t]
            k = 0usize
            while k < lag {
                v2 -= phi[k] * dx[t - 1usize - k]
                k += 1usize
            }
            z5[t] = v2
        }
        t += 1usize
    }
    let nc = lag + 2usize
    let xf = af.fa(ar, nr * nc)
    let yf = af.fa(ar, nr)
    var r2 = 0usize
    while r2 < nr {
        let tt = t0 + r2
        yf[r2] = yv[tt]
        k = 0usize
        while k < lag {
            xf[k * nr + r2] = yv[tt - 1usize - k]
            k += 1usize
        }
        xf[lag * nr + r2] = z4[tt - 1usize]
        xf[(lag + 1usize) * nr + r2] = z5[tt - m]
        r2 += 1usize
    }
    let (of, fe) = ols.fit(ar, xf, nr, nc, yf)
    if fe != ok {
        mem.reset(ar, st)
        ret (af.ar_nan(), af.ar_nan(), false)
    }
    let stat = of.tval[nc - 1usize]
    let nf = f64(nr)
    let ll = 0.0f64 - 0.5f64 * nf * (math.log[f64](2.0f64 * 3.141592653589793f64) + math.log[f64](of.rss / nf) + 1.0f64)
    let aic = 0.0f64 - 2.0f64 * ll + 2.0f64 * (f64(of.rank) + 1.0f64)
    mem.reset(ar, st)
    ret (stat, aic, stat == stat)
}

// ocsb.test(x, maxlag = 3, lag.method = "AIC"): (statistic, 5 percent critical value, lag order chosen, usable)
fn ocsb_run(ar: *mem.Arena, x: []const f64, m: usize) -> (f64, f64, usize, bool) {
    var best = 0usize
    var bestaic = inf_f()
    var lag = 1usize
    while lag <= 3usize {
        let (s, aic, good) = ocsb_fit(ar, x, m, lag, 3usize)
        if !good { ret (af.ar_nan(), af.ar_nan(), 0usize, false) }
        if aic < bestaic {
            bestaic = aic
            best = lag
        }
        lag += 1usize
    }
    let ml = best - 1usize
    let (stat, aic2, good2) = ocsb_fit(ar, x, m, ml, ml)
    if !good2 { ret (af.ar_nan(), af.ar_nan(), ml, false) }
    let lm = math.log[f64](f64(m))
    let dl = lm - 0.7656451f64
    let crit = 0.0f64 - 0.2937411f64 * math.exp[f64](0.0f64 - 0.2850853f64 * dl + (0.0f64 - 0.05983644f64) * (dl * dl)) - 1.652202f64
    ret (stat, crit, ml, true)
}

fn ocsb_diff(ar: *mem.Arena, x: []const f64, m: usize) -> bool {
    let (stat, crit, lag, good) = ocsb_run(ar, x, m)
    ret good && stat > crit
}

// one seasonal unit-root decision of nsdiffs (alpha 0.05): test 0 seas (strength above 0.64), 1 ocsb, 2 ch
fn s_diff(ar: *mem.Arena, x: []const f64, m: usize, test: usize) -> bool {
    if test == 1usize { ret ocsb_diff(ar, x, m) }
    if test == 2usize { ret ch_diff(ar, x, m) }
    let (st, good) = seas_strength(ar, x, m)
    ret good && st > 0.64f64
}

// forecast::nsdiffs(x, test, max.D) for a series of frequency m
fn nsdiffs_t(ar: *mem.Arena, x0: []const f64, m: usize, test: usize, maxd: usize) -> usize {
    var x = x0
    var dd = 0usize
    if is_constant(x) { ret dd }
    if m <= 1usize || m >= x.len { ret dd }
    var dodiff = s_diff(ar, x, m, test)
    while dodiff && dd < maxd {
        dd += 1usize
        x = diff_lag(ar, x, m)
        if is_constant(x) { ret dd }
        if x.len >= 2usize * m && dd < maxd {
            dodiff = s_diff(ar, x, m, test)
        } else {
            dodiff = false
        }
    }
    ret dd
}

// the seasonal check auto.arima makes before nsdiffs
fn nsdiffs(ar: *mem.Arena, x: []const f64, m: usize) -> usize {
    if x.len <= 2usize * m { ret 0usize }
    ret nsdiffs_t(ar, x, m, 0usize, 1usize)
}

// forecast's search.arima (auto.arima(stepwise = FALSE)): every (p, q, P, Q, constant) with p + q + P + Q <= maxorder in the order of
// expand.grid (p slowest, the constant fastest), the first strictly smaller criterion kept; with approximation the best model
// is refitted by CSS-ML, and the search runs again without approximation when that refit is unusable. The fits are discarded as the
// loop goes (the arena is reset) and the winner is refitted, which gives the same fit.
fn search_exhaustive(ar: *mem.Arena, x: []const f64, d: usize, sd: usize, m: usize, maxp: usize, maxq: usize, maxsp: usize, maxsq: usize, maxorder: usize, maxk: bool, approx: bool, offset: f64) -> (AaRes, err) {
    var best: AaRes = zero
    var bic = inf_f()
    var made = false
    var kmax = 0usize
    if maxk { kmax = 1usize }
    var p = 0usize
    while p <= maxp {
        var q = 0usize
        while q <= maxq {
            var sp = 0usize
            while sp <= maxsp {
                var sq = 0usize
                while sq <= maxsq {
                    var k = 0usize
                    while k <= kmax {
                        if p + q + sp + sq <= maxorder {
                            let st = mem.mark(ar)
                            let r = myarima(ar, x, p, d, q, sp, sd, sq, m, k == 1usize, approx, offset)
                            if r.ic < bic {
                                bic = r.ic
                                best.p = p
                                best.q = q
                                best.sp = sp
                                best.sq = sq
                                best.cst = k == 1usize
                                made = true
                            }
                            mem.reset(ar, st)
                        }
                        k += 1usize
                    }
                    sq += 1usize
                }
                sp += 1usize
            }
            q += 1usize
        }
        p += 1usize
    }
    if !made { ret (best, NoSuitableModel) }
    let r2 = myarima(ar, x, best.p, d, best.q, best.sp, sd, best.sq, m, best.cst, false, 0.0f64)
    if approx && r2.ic >= inf_f() {
        let (again, ae) = search_exhaustive(ar, x, d, sd, m, maxp, maxq, maxsp, maxsq, maxorder, maxk, false, 0.0f64)
        ret (again, ae)
    }
    best.fit = r2.fit
    best.ic = r2.ic
    best.sigma2 = fcs.arima_sigma2(r2.fit.resid, r2.fit.nused, r2.fit.nfree)
    best.d = d
    best.sd = sd
    ret (best, ok)
}

// auto.arima(y) for the series y of frequency m (missing values allowed; leading ones are dropped as auto.arima does):
// stepwise or exhaustive search, appr 0 the default approximation rule, 1 off, 2 on; test 0 kpss, 1 adf, 2 pp (ndiffs);
// stest 0 seas, 1 ocsb, 2 ch (nsdiffs)
fn auto_arima(ar: *mem.Arena, y: []const f64, m0: usize, stepwise: bool, appr: usize, test: usize, stest: usize) -> (AaRes, err) {
    let (r, e) = auto_arima_d(ar, y, m0, stepwise, appr, test, stest, false)
    ret (r, e)
}

// auto.arima(y, d = 0) when fixd0 (the order of differencing is given, so ndiffs is not asked), else auto_arima
fn auto_arima_d(ar: *mem.Arena, y: []const f64, m0: usize, stepwise: bool, appr: usize, test: usize, stest: usize, fixd0: bool) -> (AaRes, err) {
    var first = 0usize
    var seen = false
    var i = 0usize
    var serieslength = 0usize
    while i < y.len {
        if !af.ar_isnan(y[i]) {
            serieslength += 1usize
            if !seen {
                first = i
                seen = true
            }
        }
        i += 1usize
    }
    var none: AaRes = zero
    if !seen { ret (none, TooShortSeries) }
    let x = y[first..y.len]
    var m = m0
    if m < 1usize { m = 1usize }
    if is_constant(x) {
        let (fm, fe) = fixed_model(ar, x, 0usize, 0usize, m, 1usize, mean_present(x))
        ret (fm, fe)
    }
    var maxp = 5usize
    if serieslength / 3usize < maxp { maxp = serieslength / 3usize }
    var maxq = maxp
    var maxsp = 2usize
    if serieslength / 3usize / m < maxsp { maxsp = serieslength / 3usize / m }
    var maxsq = maxsp
    var dd = 0usize
    if m == 1usize {
        maxsp = 0usize
        maxsq = 0usize
    } else if x.len > 2usize * m {
        dd = nsdiffs_t(ar, x, m, stest, 1usize)
        if dd > 0usize {
            let sdx = diff_lag(ar, x, m)
            var allna = true
            i = 0usize
            while i < sdx.len {
                if !af.ar_isnan(sdx[i]) { allna = false }
                i += 1usize
            }
            if allna { dd -= 1usize }
        }
    }
    var dx: []const f64 = x
    if dd > 0usize { dx = diff_lag(ar, x, m) }
    var d0 = 0usize
    if !fixd0 { d0 = ndiffs_t(ar, dx, test, 2usize) }
    var d = d0
    if d > 0usize {
        let dfd = diff_n(ar, dx, d)
        var allna = true
        i = 0usize
        while i < dfd.len {
            if !af.ar_isnan(dfd[i]) { allna = false }
            i += 1usize
        }
        if allna { d -= 1usize }
    }
    if d > 0usize { dx = diff_n(ar, dx, d) }
    if dx.len == 0usize { ret (none, TooShortSeries) }
    if is_constant(dx) {
        if dd > 0usize && d == 0usize {
            let (fm, fe) = fixed_model(ar, x, 0usize, dd, m, 2usize, mean_present(dx) / f64(m))
            ret (fm, fe)
        }
        if dd > 0usize && d > 0usize {
            let (fm, fe) = fixed_model(ar, x, d, dd, m, 0usize, 0.0f64 / 0.0f64)
            ret (fm, fe)
        }
        if d == 2usize {
            let (fm, fe) = fixed_model(ar, x, 2usize, 0usize, m, 0usize, 0.0f64 / 0.0f64)
            ret (fm, fe)
        }
        if d == 1usize {
            let (fm, fe) = fixed_model(ar, x, 1usize, 0usize, m, 2usize, mean_present(dx))
            ret (fm, fe)
        }
        let (fm, fe) = fixed_model(ar, x, 0usize, 0usize, m, 1usize, mean_present(dx))
        ret (fm, fe)
    }
    if m > 1usize {
        if maxsp > 0usize && maxp > m - 1usize { maxp = m - 1usize }
        if maxsq > 0usize && maxq > m - 1usize { maxq = m - 1usize }
    }
    var approx = x.len > 150usize || m > 12usize
    if appr == 1usize { approx = false }
    if appr == 2usize { approx = true }
    var offset = 0.0f64
    if approx {
        var kind0 = 0usize
        if d + dd == 0usize { kind0 = 1usize }
        let f0 = af.arima_fit_s(ar, x, 0usize, d, 0usize, 0usize, dd, 0usize, m, kind0, 0.0f64 / 0.0f64, 0usize)
        if f0.good { offset = f0.value - f64(serieslength) * math.log[f64](f0.sigma2) }
    }
    let allowdrift = d + dd == 1usize
    let allowmean = d + dd == 0usize
    var cst = allowdrift || allowmean
    if !stepwise {
        let (xr, xe) = search_exhaustive(ar, x, d, dd, m, maxp, maxq, maxsp, maxsq, 5usize, cst, approx, offset)
        ret (xr, xe)
    }
    let nmodels = 94usize
    var startp = 2usize
    var startq = 2usize
    var startsp = 1usize
    var startsq = 1usize
    if x.len < 10usize {
        startp = 1usize
        startq = 1usize
        startsp = 0usize
        startsq = 0usize
    }
    if startp > maxp { startp = maxp }
    if startq > maxq { startq = maxq }
    if startsp > maxsp { startsp = maxsp }
    if startsq > maxsq { startsq = maxsq }
    var p = startp
    var q = startq
    var sp = startsp
    var sq = startsq
    let (rp, e1) = mem.alloc[usize](ar, nmodels)
    let (rq, e2) = mem.alloc[usize](ar, nmodels)
    let (rc, e3) = mem.alloc[usize](ar, nmodels)
    let (ric, e4) = mem.alloc[f64](ar, nmodels)
    let (rsp, e5) = mem.alloc[usize](ar, nmodels)
    let (rsq, e6) = mem.alloc[usize](ar, nmodels)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (none, mem.Exhausted) }
    var s = Srch{ ar: ar, x: x, d: d, sd: dd, per: m, approx: approx, offset: offset, rp: rp, rq: rq, rsp: rsp, rsq: rsq, rc: rc, ric: ric, k: 0usize, best: zero, bestmade: false, bp: 0usize, bq: 0usize, bsp: 0usize, bsq: 0usize, bc: 0usize }
    i = 0usize
    while i < nmodels {
        ric[i] = 0.0f64 / 0.0f64
        rp[i] = 99usize
        rq[i] = 99usize
        rsp[i] = 99usize
        rsq[i] = 99usize
        rc[i] = 99usize
        i += 1usize
    }
    let first_better = srch_try(&s, 0usize, p, q, sp, sq, cst)
    s.k = 1usize
    if srch_try(&s, 1usize, 0usize, 0usize, 0usize, 0usize, cst) {
        p = 0usize
        q = 0usize
        sp = 0usize
        sq = 0usize
    }
    s.k = 2usize
    var k = 2usize
    if maxp > 0usize || maxsp > 0usize {
        var p1 = 0usize
        if maxp > 0usize { p1 = 1usize }
        var sp1 = 0usize
        if m > 1usize && maxsp > 0usize { sp1 = 1usize }
        if srch_try(&s, k, p1, 0usize, sp1, 0usize, cst) {
            p = p1
            sp = sp1
            q = 0usize
            sq = 0usize
        }
        k += 1usize
        s.k = k
    }
    if maxq > 0usize || maxsq > 0usize {
        var q1 = 0usize
        if maxq > 0usize { q1 = 1usize }
        var sq1 = 0usize
        if m > 1usize && maxsq > 0usize { sq1 = 1usize }
        if srch_try(&s, k, 0usize, q1, 0usize, sq1, cst) {
            p = 0usize
            sp = 0usize
            sq = sq1
            q = q1
        }
        k += 1usize
        s.k = k
    }
    if cst {
        if srch_try(&s, k, 0usize, 0usize, 0usize, 0usize, false) {
            p = 0usize
            q = 0usize
            sp = 0usize
            sq = 0usize
        }
        k += 1usize
        s.k = k
    }
    var startk = 0usize
    while startk < k && k < nmodels {
        startk = k
        var skip = false
        var mv = 0usize
        while mv < 16usize && !skip {
            // moves 0..7 change (P, Q), 8..15 change (p, q): the same eight steps in the order of auto.arima
            var np = p
            var nq = q
            var nsp = sp
            var nsq = sq
            var cond = true
            let step = mv % 8usize
            var dpl = 0usize
            var dmi = 0usize
            var dql = 0usize
            var dqm = 0usize
            // step: 0 (-1, 0), 1 (0, -1), 2 (+1, 0), 3 (0, +1), 4 (-1, -1), 5 (-1, +1), 6 (+1, -1), 7 (+1, +1) for the pair (a, b)
            if step == 0usize { dmi = 1usize }
            if step == 1usize { dqm = 1usize }
            if step == 2usize { dpl = 1usize }
            if step == 3usize { dql = 1usize }
            if step == 4usize {
                dmi = 1usize
                dqm = 1usize
            }
            if step == 5usize {
                dmi = 1usize
                dql = 1usize
            }
            if step == 6usize {
                dpl = 1usize
                dqm = 1usize
            }
            if step == 7usize {
                dpl = 1usize
                dql = 1usize
            }
            var ca = 0usize
            var cb = 0usize
            var maxa = 0usize
            var maxb = 0usize
            if mv < 8usize {
                ca = sp
                cb = sq
                maxa = maxsp
                maxb = maxsq
            } else {
                ca = p
                cb = q
                maxa = maxp
                maxb = maxq
            }
            if dmi > ca { cond = false }
            if dqm > cb { cond = false }
            if ca + dpl > maxa { cond = false }
            if cb + dql > maxb { cond = false }
            if cond {
                let na = ca + dpl - dmi
                let nb = cb + dql - dqm
                if mv < 8usize {
                    nsp = na
                    nsq = nb
                } else {
                    np = na
                    nq = nb
                }
                if srch_newmodel(&s, np, nq, nsp, nsq, cst) {
                    k += 1usize
                    if k > nmodels {
                        skip = true
                    } else {
                        if srch_try(&s, k - 1usize, np, nq, nsp, nsq, cst) {
                            p = np
                            q = nq
                            sp = nsp
                            sq = nsq
                            skip = true
                        }
                        s.k = k
                    }
                }
            }
            mv += 1usize
        }
        if !skip && (allowdrift || allowmean) {
            if srch_newmodel(&s, p, q, sp, sq, !cst) {
                k += 1usize
                if k <= nmodels {
                    if srch_try(&s, k - 1usize, p, q, sp, sq, !cst) { cst = !cst }
                    s.k = k
                }
            }
        }
    }
    if approx && s.bestmade && s.best.fit.good {
        let (ordr, e7) = mem.alloc[usize](ar, nmodels)
        if e7 != ok { ret (none, mem.Exhausted) }
        var cnt = 0usize
        i = 0usize
        while i < nmodels {
            if !af.ar_isnan(ric[i]) {
                ordr[cnt] = i
                cnt += 1usize
            }
            i += 1usize
        }
        i = 1usize
        while i < cnt {
            let key = ordr[i]
            var j = i
            while j > 0usize && ric[ordr[j - 1usize]] > ric[key] {
                ordr[j] = ordr[j - 1usize]
                j -= 1usize
            }
            ordr[j] = key
            i += 1usize
        }
        var done = false
        i = 0usize
        while i < cnt && !done {
            let kk = ordr[i]
            let r = myarima(ar, x, rp[kk], d, rq[kk], rsp[kk], dd, rsq[kk], m, rc[kk] == 1usize, false, 0.0f64)
            if r.ic < inf_f() {
                s.best = r
                s.bp = rp[kk]
                s.bq = rq[kk]
                s.bsp = rsp[kk]
                s.bsq = rsq[kk]
                s.bc = rc[kk]
                done = true
            }
            i += 1usize
        }
    }
    if !s.bestmade || s.best.ic >= inf_f() { ret (none, NoSuitableModel) }
    let res = AaRes{ fit: s.best.fit, ic: s.best.ic, p: s.bp, d: d, q: s.bq, sp: s.bsp, sd: dd, sq: s.bsq, cst: s.bc == 1usize, closed: false, sigma2: fcs.arima_sigma2(s.best.fit.resid, s.best.fit.nused, s.best.fit.nfree) }
    ret (res, ok)
}

// auto.arima(y)$model, the stepwise search with the default tests and approximation rule
fn auto_arima_model(ar: *mem.Arena, y: []const f64, m0: usize) -> (kal.SsModel, err) {
    let (r, e) = auto_arima(ar, y, m0, true, 0usize, 0usize, 0usize)
    ret (r.fit.model, e)
}
