// R MASS boxcox.default and logtrans.default (the profile log-likelihood over a grid, with spline(n = 100) interpolation
// when asked), the lambda (or alpha) that maximises it, and fractions() (continued-fraction rational approximation).
// x is the n by p column-major design of the lm; y the response.

use e.algo.linalg.decomp as decomp
use e.algo.stat.splinepkg as sp
use e.math
use e.mem

error BadInput

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn rss_of(a: *mem.Arena, x: []const f64, n: usize, p: usize, yt: []const f64) -> (f64, err) {
    let (fit, fe) = decomp.lm_fit(a, x, n, p, yt, 1.0e-7f64)
    if fe != ok { ret (0.0f64, fe) }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += fit.residuals[i] * fit.residuals[i]
        i += 1usize
    }
    ret (rss, ok)
}

// spline(xl, ll, n = 100) of the grid (ascending xl), written to ox and oy (100 each)
fn interp100(a: *mem.Arena, xl: []const f64, ll: []const f64, ox: []f64, oy: []f64) -> err {
    let m = xl.len
    let (b, e1) = mem.alloc[f64](a, m)
    let (c, e2) = mem.alloc[f64](a, m)
    let (d, e3) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    sp.fmm_spline(m, xl, ll, b, c, d)
    let from = xl[0usize]
    let to = xl[m - 1usize]
    let by = (to - from) / 99.0f64
    var i = 0usize
    while i < 100usize {
        var u = from + f64(i) * by
        if i == 0usize { u = from }
        if i == 99usize { u = to }
        ox[i] = u
        oy[i] = sp.spline_eval(m, xl, ll, b, c, d, u)
        i += 1usize
    }
    ret ok
}

// boxcox over the lambda grid: ox / oy get the grid (100 points when interp, else the lambdas) and returns the length; best is the first maximiser's x
fn boxcox(a: *mem.Arena, y: []const f64, x: []const f64, p: usize, lambda: []const f64, interp: bool, eps: f64, ox: []f64, oy: []f64) -> (usize, f64, err) {
    let n = y.len
    var i = 0usize
    var gm = 0.0f64
    while i < n {
        if y[i] <= 0.0f64 { ret (0usize, nan(), BadInput) }
        gm += math.log[f64](y[i])
        i += 1usize
    }
    gm = math.exp[f64](gm / f64(n))
    let (ys, e0) = mem.alloc[f64](a, n)
    let (yt, e1) = mem.alloc[f64](a, n)
    let (ll, e2) = mem.alloc[f64](a, lambda.len)
    if e0 != ok || e1 != ok || e2 != ok { ret (0usize, nan(), mem.Full) }
    i = 0usize
    while i < n {
        ys[i] = y[i] / gm
        i += 1usize
    }
    var k = 0usize
    while k < lambda.len {
        let la = lambda[k]
        i = 0usize
        while i < n {
            let ly = math.log[f64](ys[i])
            if math.abs[f64](la) > eps {
                yt[i] = (math.pow[f64](ys[i], la) - 1.0f64) / la
            } else {
                yt[i] = ly * (1.0f64 + (la * ly) / 2.0f64 * (1.0f64 + (la * ly) / 3.0f64 * (1.0f64 + (la * ly) / 4.0f64)))
            }
            i += 1usize
        }
        let (rss, re) = rss_of(a, x, n, p, yt)
        if re != ok { ret (0usize, nan(), re) }
        ll[k] = 0.0f64 - f64(n) / 2.0f64 * math.log[f64](rss)
        k += 1usize
    }
    var m = lambda.len
    var xs: []const f64 = lambda
    var ls: []const f64 = ll
    if interp {
        let ie = interp100(a, lambda, ll, ox, oy)
        if ie != ok { ret (0usize, nan(), ie) }
        xs = ox[0usize..100usize]
        ls = oy[0usize..100usize]
        m = 100usize
    } else {
        i = 0usize
        while i < m {
            ox[i] = lambda[i]
            oy[i] = ll[i]
            i += 1usize
        }
    }
    var mx = 0usize
    i = 1usize
    while i < m {
        if ls[i] > ls[mx] { mx = i }
        i += 1usize
    }
    ret (m, xs[mx], ok)
}

// logtrans over the alpha grid: loglik = -n/2 log(RSS of log(y + alpha)) - sum(log(y + alpha))
fn logtrans(a: *mem.Arena, y: []const f64, x: []const f64, p: usize, alpha: []const f64, interp: bool, ox: []f64, oy: []f64) -> (usize, f64, err) {
    let n = y.len
    let (yt, e1) = mem.alloc[f64](a, n)
    let (ll, e2) = mem.alloc[f64](a, alpha.len)
    if e1 != ok || e2 != ok { ret (0usize, nan(), mem.Full) }
    var k = 0usize
    while k < alpha.len {
        var sy = 0.0f64
        var i = 0usize
        while i < n {
            if y[i] + alpha[k] <= 0.0f64 { ret (0usize, nan(), BadInput) }
            yt[i] = math.log[f64](y[i] + alpha[k])
            sy += yt[i]
            i += 1usize
        }
        let (rss, re) = rss_of(a, x, n, p, yt)
        if re != ok { ret (0usize, nan(), re) }
        ll[k] = 0.0f64 - f64(n) / 2.0f64 * math.log[f64](rss) - sy
        k += 1usize
    }
    var m = alpha.len
    var xs: []const f64 = alpha
    var ls: []const f64 = ll
    var i = 0usize
    if interp {
        let ie = interp100(a, alpha, ll, ox, oy)
        if ie != ok { ret (0usize, nan(), ie) }
        xs = ox[0usize..100usize]
        ls = oy[0usize..100usize]
        m = 100usize
    } else {
        while i < m {
            ox[i] = alpha[i]
            oy[i] = ll[i]
            i += 1usize
        }
    }
    var mx = 0usize
    i = 1usize
    while i < m {
        if ls[i] > ls[mx] { mx = i }
        i += 1usize
    }
    ret (m, xs[mx], ok)
}
