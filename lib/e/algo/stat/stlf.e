// forecast::stlf(y, h) for a seasonal series of period m: mstl with its default s.window (11 for a single period) splits y into
// trend, seasonal and remainder; a non-seasonal model (ets "ZZN" without multiplicative trend, or auto.arima without a seasonal part)
// is fitted to the seasonally adjusted series; the forecasts, 80 and 95 percent limits and fitted values are re-seasonalised with the
// last period of the seasonal component. lambda 5 means no Box-Cox transformation; with one the series is transformed first and
// everything is transformed back (without bias adjustment).
//
// Not here: the naive and rwdrift methods, a user model function, xreg, several seasonal periods (msts), t.window and robust.

use e.math
use e.math.dist as dist
use e.mem
use e.algo.stat.arimafc as fc
use e.algo.stat.autoarima as aa
use e.algo.stat.etsfit as es
use e.algo.stat.fcast as fcast
use e.algo.stat.stlpkg as stlp

// results are h long (fitted n long): mean, upper and lower 80 percent, upper and lower 95 percent; method 0 ets, 1 arima
type Stlf = struct { mean: []f64, up80: []f64, lo80: []f64, up95: []f64, lo95: []f64, fitted: []f64 }

fn alloc(ar: *mem.Arena, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](ar, n + 1usize)
    ret s[0usize..n]
}

fn back(v: f64, lam: f64) -> f64 {
    if lam == 5.0f64 { ret v }
    ret fcast.inv_box_cox(v, lam)
}

fn stlf(ar: *mem.Arena, y: []const f64, m: usize, h: usize, lam: f64, method: usize) -> (Stlf, bool) {
    var out: Stlf = zero
    let n = y.len
    out.mean = alloc(ar, h)
    out.up80 = alloc(ar, h)
    out.lo80 = alloc(ar, h)
    out.up95 = alloc(ar, h)
    out.lo95 = alloc(ar, h)
    out.fitted = alloc(ar, n)
    let x = alloc(ar, n)
    var i = 0usize
    while i < n {
        x[i] = y[i]
        if lam != 5.0f64 { x[i] = fcast.box_cox(y[i], lam) }
        i += 1usize
    }
    let seas = alloc(ar, n)
    let trend = alloc(ar, n)
    let rw = alloc(ar, n)
    if stlp.stl(ar, x, m, false, 11.0f64, 0i64, 0.0f64, 1i64, 0.0f64, 1i64, 0usize, 0usize, 0usize, false, seas, trend, rw) != ok { ret (out, false) }
    let sa = alloc(ar, n)
    i = 0usize
    while i < n {
        sa[i] = x[i] - seas[i]
        i += 1usize
    }
    let mean = alloc(ar, h)
    let se = alloc(ar, h)
    let fit = alloc(ar, n)
    if method == 0usize {
        let ef = es.ets_auto(ar, sa, 1usize, 0usize, false)
        if !ef.good { ret (out, false) }
        es.ets_point(ar, &ef, h, mean)
        let vr = alloc(ar, h)
        if !es.ets_var(ar, &ef, h, vr) { ret (out, false) }
        i = 0usize
        while i < h {
            se[i] = math.sqrt[f64](vr[i])
            i += 1usize
        }
        i = 0usize
        while i < n {
            fit[i] = ef.fitted[i]
            i += 1usize
        }
    } else {
        let (res, e) = aa.auto_arima(ar, sa, 1usize, true, 0usize, 0usize, 0usize)
        if e != ok { ret (out, false) }
        var kind = 0usize
        if res.cst {
            kind = 1usize
            if res.d + res.sd == 1usize { kind = 2usize }
        }
        var beta = 0.0f64
        if kind > 0usize { beta = res.fit.coef[res.fit.coef.len - 1usize] }
        if !fc.arima_fc(ar, &res.fit.model, res.sigma2, kind, beta, n, h, mean, se) { ret (out, false) }
        i = 0usize
        while i < n {
            fit[i] = sa[i] - res.fit.resid[i]
            i += 1usize
        }
    }
    let z80 = dist.qnorm(0.9f64, 0.0f64, 1.0f64, true, false)
    let z95 = dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false)
    i = 0usize
    while i < h {
        let ls = seas[n - m + i % m]
        out.mean[i] = back(mean[i] + ls, lam)
        out.up80[i] = back(mean[i] + z80 * se[i] + ls, lam)
        out.lo80[i] = back(mean[i] - z80 * se[i] + ls, lam)
        out.up95[i] = back(mean[i] + z95 * se[i] + ls, lam)
        out.lo95[i] = back(mean[i] - z95 * se[i] + ls, lam)
        i += 1usize
    }
    i = 0usize
    while i < n {
        out.fitted[i] = back(fit[i] + seas[i], lam)
        i += 1usize
    }
    ret (out, true)
}
