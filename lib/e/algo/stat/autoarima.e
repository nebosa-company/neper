// forecast::auto.arima(x)$model for a non-seasonal series (frequency 1): the KPSS test picks d (ndiffs), the stepwise search over
// (p, q, constant) by AICc, each candidate fitted by stats::arima (e.algo.stat.arimafit), and the state-space model of the winner.
// A series longer than 150 is searched by CSS and the candidates refitted by ML in the order of their approximate criterion, as
// auto.arima does; series that are constant after differencing take its closed-form branches.
//
// Not here: seasonal series (nsdiffs, P, D, Q), the non-stepwise search, xreg, lambda and the other unit root tests.

use e.math
use e.mem
use e.algo.stat.kalman as kal
use e.algo.stat.arimafit as af
use e.algo.stat.pracma as pr
use e.algo.stat.urca as ur

error NoSuitableModel
error TooShortSeries

type ArIc = struct { fit: af.ArFit, ic: f64 }

type Srch = struct {
    ar: *mem.Arena, x: []const f64, d: usize, approx: bool, offset: f64,
    rp: []usize, rq: []usize, rc: []usize, ric: []f64, k: usize, best: ArIc, bestmade: bool
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

// forecast's myarima for a non-seasonal candidate: the fit and its information criterion (Inf when the fit fails or its roots are unsafe)
fn myarima(ar: *mem.Arena, x: []const f64, p: usize, d: usize, q: usize, constant: bool, approximation: bool, offset: f64) -> ArIc {
    var out: ArIc = zero
    out.ic = inf_f()
    var n = 0usize
    var i = 0usize
    while i < x.len {
        if !af.ar_isnan(x[i]) { n += 1usize }
        i += 1usize
    }
    var kind = 0usize
    if d == 1usize && constant { kind = 2usize }
    if d == 0usize && constant { kind = 1usize }
    var method = 0usize
    if approximation { method = 2usize }
    let fit = af.arima_fit(ar, x, p, d, q, kind, 0.0f64 / 0.0f64, method)
    if !fit.good { ret out }
    let nstar = f64(n) - f64(d)
    let npar = f64(fit.nfree) + 1.0f64
    var aic = fit.aic
    if method == 2usize { aic = offset + nstar * math.log[f64](fit.sigma2) + 2.0f64 * npar }
    if af.ar_isnan(aic) {
        out.fit = fit
        ret out
    }
    var ic = aic + 2.0f64 * npar * (npar + 1.0f64) / (nstar - npar - 1.0f64)
    var minroot = 2.0f64
    if p > 0usize {
        let (mr, rgood) = min_modulus_ok(ar, fit.phi, true, minroot)
        minroot = mr
        if !rgood { ic = inf_f() }
    }
    if q > 0usize && ic < inf_f() {
        let (mr, rgood) = min_modulus_ok(ar, fit.theta, false, minroot)
        minroot = mr
        if !rgood { ic = inf_f() }
    }
    if minroot < 1.01f64 || !fit.varok { ic = inf_f() }
    out.fit = fit
    out.ic = ic
    ret out
}

fn srch_newmodel(s: *Srch, p: usize, q: usize, cst: bool) -> bool {
    var c1 = 0usize
    if cst { c1 = 1usize }
    var i = 0usize
    while i < s.k {
        if s.rp[i] == p && s.rq[i] == q && s.rc[i] == c1 { ret false }
        i += 1usize
    }
    ret true
}

// fits a candidate as result number `slot` (0-based) and keeps it when it beats the best so far; returns whether it did
fn srch_try(s: *Srch, slot: usize, p: usize, q: usize, cst: bool) -> bool {
    let r = myarima(s.ar, s.x, p, s.d, q, cst, s.approx, s.offset)
    s.rp[slot] = p
    s.rq[slot] = q
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

// the model of the closed-form branches: Arima(x, order = c(0, d, 0), fixed = mean) and its variants
fn fixed_model(ar: *mem.Arena, x: []const f64, d: usize, kind: usize, xfixed: f64) -> (kal.SsModel, err) {
    let fit = af.arima_fit(ar, x, 0usize, d, 0usize, kind, xfixed, 0usize)
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

// auto.arima(y)$model for the series y (missing values allowed; leading ones are dropped as auto.arima does)
fn auto_arima_model(ar: *mem.Arena, y: []const f64) -> (kal.SsModel, err) {
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
    if is_constant(x) {
        let (fm, fe) = fixed_model(ar, x, 0usize, 1usize, mean_present(x))
        ret (fm, fe)
    }
    var maxp = 5usize
    if serieslength / 3usize < maxp { maxp = serieslength / 3usize }
    let maxq = maxp
    let d0 = ndiffs(ar, x, 2usize)
    var d = d0
    if d > 0usize {
        let dd = diff_n(ar, x, d)
        var allna = true
        i = 0usize
        while i < dd.len {
            if !af.ar_isnan(dd[i]) { allna = false }
            i += 1usize
        }
        if allna { d -= 1usize }
    }
    var dx: []const f64 = x
    if d > 0usize { dx = diff_n(ar, x, d) }
    if dx.len == 0usize { ret (none, TooShortSeries) }
    if is_constant(dx) {
        if d == 2usize {
            let (fm, fe) = fixed_model(ar, x, 2usize, 0usize, 0.0f64 / 0.0f64)
            ret (fm, fe)
        }
        if d == 1usize {
            let (fm, fe) = fixed_model(ar, x, 1usize, 2usize, mean_present(dx))
            ret (fm, fe)
        }
        let (fm0, fe0) = fixed_model(ar, x, 0usize, 1usize, mean_present(dx))
        ret (fm0, fe0)
    }
    let approx = x.len > 150usize
    var offset = 0.0f64
    if approx {
        var kind0 = 0usize
        if d == 0usize { kind0 = 1usize }
        let f0 = af.arima_fit(ar, x, 0usize, d, 0usize, kind0, 0.0f64 / 0.0f64, 0usize)
        if f0.good { offset = 0.0f64 - 2.0f64 * (0.0f64 - 0.5f64 * f0.value) - f64(serieslength) * math.log[f64](f0.sigma2) }
    }
    let allowdrift = d == 1usize
    let allowmean = d == 0usize
    var cst = allowdrift || allowmean
    let nmodels = 94usize
    var startp = 2usize
    var startq = 2usize
    if x.len < 10usize {
        startp = 1usize
        startq = 1usize
    }
    if startp > maxp { startp = maxp }
    if startq > maxq { startq = maxq }
    var p = startp
    var q = startq
    let (rp, e1) = mem.alloc[usize](ar, nmodels)
    let (rq, e2) = mem.alloc[usize](ar, nmodels)
    let (rc, e3) = mem.alloc[usize](ar, nmodels)
    let (ric, e4) = mem.alloc[f64](ar, nmodels)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (none, mem.Exhausted) }
    var s = Srch{ ar: ar, x: x, d: d, approx: approx, offset: offset, rp: rp, rq: rq, rc: rc, ric: ric, k: 0usize, best: zero, bestmade: false }
    i = 0usize
    while i < nmodels {
        ric[i] = 0.0f64 / 0.0f64
        rp[i] = 99usize
        rq[i] = 99usize
        rc[i] = 99usize
        i += 1usize
    }
    let first_better = srch_try(&s, 0usize, p, q, cst)
    s.k = 1usize
    if srch_try(&s, 1usize, 0usize, 0usize, cst) {
        p = 0usize
        q = 0usize
    }
    s.k = 2usize
    var k = 2usize
    if maxp > 0usize {
        var p1 = 0usize
        if maxp > 0usize { p1 = 1usize }
        if srch_try(&s, k, p1, 0usize, cst) {
            p = p1
            q = 0usize
        }
        k += 1usize
        s.k = k
    }
    if maxq > 0usize {
        var q1 = 0usize
        if maxq > 0usize { q1 = 1usize }
        if srch_try(&s, k, 0usize, q1, cst) {
            p = 0usize
            q = q1
        }
        k += 1usize
        s.k = k
    }
    if cst {
        if srch_try(&s, k, 0usize, 0usize, false) {
            p = 0usize
            q = 0usize
        }
        k += 1usize
        s.k = k
    }
    var startk = 0usize
    while startk < k && k < nmodels {
        startk = k
        var skip = false
        // each move: (condition, p', q')
        var mv = 0usize
        while mv < 8usize && !skip {
            var np = p
            var nq = q
            var cond = false
            if mv == 0usize {
                cond = p > 0usize
                if cond { np = p - 1usize }
            } else if mv == 1usize {
                cond = q > 0usize
                if cond { nq = q - 1usize }
            } else if mv == 2usize {
                cond = p < maxp
                np = p + 1usize
            } else if mv == 3usize {
                cond = q < maxq
                nq = q + 1usize
            } else if mv == 4usize {
                cond = q > 0usize && p > 0usize
                if cond {
                    np = p - 1usize
                    nq = q - 1usize
                }
            } else if mv == 5usize {
                cond = q < maxq && p > 0usize
                if cond {
                    np = p - 1usize
                    nq = q + 1usize
                }
            } else if mv == 6usize {
                cond = q > 0usize && p < maxp
                if cond {
                    np = p + 1usize
                    nq = q - 1usize
                }
            } else {
                cond = q < maxq && p < maxp
                np = p + 1usize
                nq = q + 1usize
            }
            if cond && srch_newmodel(&s, np, nq, cst) {
                k += 1usize
                if k > nmodels {
                    skip = true
                } else {
                    s.k = k - 1usize
                    if srch_try(&s, k - 1usize, np, nq, cst) {
                        p = np
                        q = nq
                        skip = true
                    }
                    s.k = k
                }
            }
            mv += 1usize
        }
        if !skip && (allowdrift || allowmean) {
            if srch_newmodel(&s, p, q, !cst) {
                k += 1usize
                if k <= nmodels {
                    s.k = k - 1usize
                    if srch_try(&s, k - 1usize, p, q, !cst) { cst = !cst }
                    s.k = k
                }
            }
        }
    }
    if approx && s.bestmade && s.best.fit.good {
        // refit the candidates by ML in the order of their approximate criterion
        var cnt = 0usize
        let (ordr, e5) = mem.alloc[usize](ar, nmodels)
        if e5 != ok { ret (none, mem.Exhausted) }
        i = 0usize
        while i < nmodels {
            if !af.ar_isnan(ric[i]) {
                ordr[cnt] = i
                cnt += 1usize
            }
            i += 1usize
        }
        // a stable insertion sort by criterion
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
            let r = myarima(ar, x, rp[kk], d, rq[kk], rc[kk] == 1usize, false, 0.0f64)
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
