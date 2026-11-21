// predict.Arima: KalmanForecast over the final state of a fit, plus the regressor contribution (intercept or drift) and
// the forecast standard errors sqrt(var * sigma2). The fit's own model is not touched (a copy runs).

use e.math
use e.mem
use e.algo.stat.kalman as kal

// forecast::Arima's sigma2: the residual sum of squares over nstar - (free coefficients) degrees of freedom
// (stats::arima's own sigma2 divides by n.used); nstar is the count after differencing
fn arima_sigma2(resid: []const f64, nstar: usize, nfree: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < resid.len {
        if resid[i] == resid[i] { s += resid[i] * resid[i] }
        i += 1usize
    }
    ret s / f64(nstar - nfree)
}

// kind 0 no regressor, 1 intercept beta, 2 drift beta times the time index (n + step)
fn arima_fc(ar: *mem.Arena, m0: *const kal.SsModel, sigma2: f64, kind: usize, beta: f64, n: usize, h: usize, mean: []f64, se: []f64) -> bool {
    let (mc, ce) = kal.ss_copy(ar, m0)
    if ce != ok { ret false }
    var m = mc
    let p = m.p
    let (anew, e1) = mem.alloc[f64](ar, p)
    let (mm, e2) = mem.alloc[f64](ar, p * p)
    if e1 != ok || e2 != ok { ret false }
    var l = 0usize
    while l < h {
        kal.ss_predict(&m, anew, mm, 1usize, -1i64)
        var i = 0usize
        while i < p {
            m.av[i] = anew[i]
            i += 1usize
        }
        i = 0usize
        while i < p * p {
            m.pm[i] = m.pn[i]
            i += 1usize
        }
        var f = 0.0f64
        i = 0usize
        while i < p {
            f += m.zv[i] * m.av[i]
            i += 1usize
        }
        var v = m.h
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                v += m.zv[i] * m.zv[j] * m.pm[i * p + j]
                j += 1usize
            }
            i += 1usize
        }
        if kind == 1usize { f += beta }
        if kind == 2usize { f += beta * f64(n + l + 1usize) }
        mean[l] = f
        se[l] = math.sqrt[f64](v * sigma2)
        l += 1usize
    }
    ret true
}
