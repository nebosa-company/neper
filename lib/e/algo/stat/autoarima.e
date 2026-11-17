// forecast::auto.arima(x)$model for a series of frequency m: the KPSS test picks d (ndiffs), the stepwise search over
// (p, q, P, Q, constant) by AICc, the seasonal difference by forecast's seasonal strength test (mstl with na.interp), each candidate fitted by stats::arima (e.algo.stat.arimafit), and the state-space model of the winner.
// A series longer than 150 is searched by CSS and the candidates refitted by ML in the order of their approximate criterion, as
// auto.arima does; series that are constant after differencing take its closed-form branches.
//
// Not here: the non-stepwise search, xreg, lambda, the ADF and PP tests and the OCSB, HEGY and CH seasonal tests (auto.arima's defaults are KPSS and seas).

use e.math
use e.mem
use e.algo.stat.kalman as kal
use e.algo.stat.arimafit as af
use e.algo.stat.pracma as pr
use e.algo.stat.urca as ur
use e.algo.stat.stlpkg as stlp
use e.algo.linalg.decomp as decomp

error NoSuitableModel
error TooShortSeries

type ArIc = struct { fit: af.ArFit, ic: f64 }

type Srch = struct {
    ar: *mem.Arena, x: []const f64, d: usize, sd: usize, per: usize, approx: bool, offset: f64,
    rp: []usize, rq: []usize, rsp: []usize, rsq: []usize, rc: []usize, ric: []f64, k: usize, best: ArIc, bestmade: bool
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

// forecast::ndiffs(x, test = "kpss", max.d = 2)
fn ndiffs(ar: *mem.Arena, x0: []const f64, maxd: usize) -> usize {
    var x: []const f64 = drop_missing(ar, x0)
    var d = 0usize
    if is_constant(x) { ret d }
    var dodiff = kpss_diff(ar, x)
    while dodiff && d < maxd {
        d += 1usize
        x = diff_n(ar, x, 1usize)
        if is_constant(x) { ret d }
        dodiff = kpss_diff(ar, x)
    }
    ret d
}

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
    }
    ret better
}

// the model of the closed-form branches: Arima(x, order = c(0, d, 0), seasonal = c(0, D, 0), fixed = mean) and its variants
fn fixed_model(ar: *mem.Arena, x: []const f64, d: usize, sd: usize, m: usize, kind: usize, xfixed: f64) -> (kal.SsModel, err) {
    let fit = af.arima_fit_s(ar, x, 0usize, d, 0usize, 0usize, sd, 0usize, m, kind, xfixed, 0usize)
    if !fit.good { ret (fit.model, NoSuitableModel) }
    ret (fit.model, ok)
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

// forecast::nsdiffs(x, test = "seas", max.D = 1): 0 or 1
fn nsdiffs(ar: *mem.Arena, x: []const f64, m: usize) -> usize {
    if is_constant(x) { ret 0usize }
    if m <= 1usize || m >= x.len { ret 0usize }
    if x.len <= 2usize * m { ret 0usize }
    let (st, good) = seas_strength(ar, x, m)
    if good && st > 0.64f64 { ret 1usize }
    ret 0usize
}

// auto.arima(y)$model for the series y of frequency m (missing values allowed; leading ones are dropped as auto.arima does)
fn auto_arima_model(ar: *mem.Arena, y: []const f64, m0: usize) -> (kal.SsModel, err) {
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
    var none: kal.SsModel = zero
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
        dd = nsdiffs(ar, x, m)
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
    let d0 = ndiffs(ar, dx, 2usize)
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
    let approx = x.len > 150usize || m > 12usize
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
    var s = Srch{ ar: ar, x: x, d: d, sd: dd, per: m, approx: approx, offset: offset, rp: rp, rq: rq, rsp: rsp, rsq: rsq, rc: rc, ric: ric, k: 0usize, best: zero, bestmade: false }
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
                done = true
            }
            i += 1usize
        }
    }
    if !s.bestmade || s.best.ic >= inf_f() { ret (none, NoSuitableModel) }
    ret (s.best.fit.model, ok)
}
