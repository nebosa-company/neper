// R drc: the four-parameter log-logistic dose-response model LL.4, f(x) = c + (d - c) / (1 + exp(b (log x - log e))), fitted by
// Levenberg-Marquardt least squares from a data-driven start (e.algo.stat.minpacklm). The fit is the least-squares optimum, so it agrees
// with drm's estimates to the optimiser tolerance, not bit for bit.
//
// Not here: the other model functions (Weibull, log-normal, Cedergreen, Brain-Cousens), fixed parameters, variance-covariance matrices,
// ED with intervals, robust fitting, model comparison and the plots.

use e.algo.stat.minpacklm as ml
use e.math
use e.mem

type Data = struct { dose: []const f64, resp: []const f64 }

fn resid(d: *Data, p: []const f64, out: []f64) {
    var i = 0usize
    while i < d.dose.len {
        let v = p[1usize] + (p[2usize] - p[1usize]) / (1.0f64 + math.exp[f64](p[0usize] * (math.log[f64](d.dose[i]) - math.log[f64](p[3usize]))))
        out[i] = d.resp[i] - v
        i += 1usize
    }
}

// p receives (b, c, d, e); the residual sum of squares is returned
fn fit_ll4(a: *mem.Arena, dose: []const f64, resp: []const f64, p: []f64) -> (f64, err) {
    let n = dose.len
    var lo = resp[0usize]
    var hi = resp[0usize]
    var i = 0usize
    while i < n {
        if resp[i] < lo { lo = resp[i] }
        if resp[i] > hi { hi = resp[i] }
        i += 1usize
    }
    let mid = (lo + hi) / 2.0f64
    var e0 = dose[0usize]
    var best = 1.0e300f64
    i = 0usize
    while i < n {
        var dd = resp[i] - mid
        if dd < 0.0f64 { dd = 0.0f64 - dd }
        if dd < best {
            best = dd
            e0 = dose[i]
        }
        i += 1usize
    }
    // the response falls with dose when the response at the largest dose is below the one at the smallest
    var imin = 0usize
    var imax = 0usize
    i = 0usize
    while i < n {
        if dose[i] < dose[imin] { imin = i }
        if dose[i] > dose[imax] { imax = i }
        i += 1usize
    }
    var b0 = 1.0f64
    if resp[imax] < resp[imin] { b0 = 1.0f64 } else { b0 = 0.0f64 - 1.0f64 }
    var cc = lo - 0.05f64 * (hi - lo)
    var dd2 = hi + 0.05f64 * (hi - lo)
    if resp[imax] > resp[imin] {
        cc = lo - 0.05f64 * (hi - lo)
        dd2 = hi + 0.05f64 * (hi - lo)
    }
    p[0usize] = b0
    p[1usize] = cc
    p[2usize] = dd2
    p[3usize] = e0
    var d = Data { dose: dose, resp: resp }
    let (lb, e1) = mem.alloc[f64](a, 4usize)
    if e1 != ok { ret (0.0f64, e1) }
    let (ub, e2) = mem.alloc[f64](a, 4usize)
    if e2 != ok { ret (0.0f64, e2) }
    lb[0usize] = 0.0f64 - 1.0e10f64
    lb[1usize] = 0.0f64 - 1.0e10f64
    lb[2usize] = 0.0f64 - 1.0e10f64
    lb[3usize] = 1.0e-10f64
    ub[0usize] = 1.0e10f64
    ub[1usize] = 1.0e10f64
    ub[2usize] = 1.0e10f64
    ub[3usize] = 1.0e10f64
    let (f, e3) = ml.nls_lm[Data](a, resid, &d, n, 4usize, p, lb, ub, 1.0e-14f64, 1.0e-14f64, 0.0f64, 2000i64, 500i64)
    if e3 != ok { ret (0.0f64, e3) }
    ret (f.deviance, ok)
}
