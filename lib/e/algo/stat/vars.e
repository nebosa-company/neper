// R vars: VAR(y, p, type = "const") by equation-wise least squares (coefficients ordered lag 1 of every series, lag 2, ..., constant), the residual
// covariance of summary(), and VARselect's AIC, HQ, SC and FPE criteria on the common sample that drops the first lag.max observations.
//
// Not here: the trend and both types, exogenous regressors, restrictions, tests, impulse responses, forecasts and the causality tests.

use e.algo.stat.carlmtest as ols
use e.math
use e.mem

// the lag-p design of y (T0 by K row-major) for the observations t0 .. T0 - 1: row i is (y_{t-1}, ..., y_{t-p}, 1), the answers y_t; returns the design
fn lag_design(a: *mem.Arena, y: []const f64, t0: usize, k: usize, p: usize, start: usize, x: []f64) {
    let rows = t0 - start
    var i = 0usize
    while i < rows {
        let t = start + i
        var l = 0usize
        while l < p {
            var j = 0usize
            while j < k {
                x[i * (k * p + 1usize) + l * k + j] = y[(t - 1usize - l) * k + j]
                j += 1usize
            }
            l += 1usize
        }
        x[i * (k * p + 1usize) + k * p] = 1.0f64
        i += 1usize
    }
}

// the coefficient matrix (k rows of k p + 1 columns) and the residuals (rows by k) of the lag-p VAR on the observations from `start`
fn var_fit(a: *mem.Arena, y: []const f64, t0: usize, k: usize, p: usize, start: usize, coef: []f64, resid: []f64) -> err {
    let rows = t0 - start
    let w = k * p + 1usize
    let (x, e1) = mem.alloc[f64](a, rows * w)
    if e1 != ok { ret e1 }
    lag_design(a, y, t0, k, p, start, x)
    let (yy, e2) = mem.alloc[f64](a, rows)
    if e2 != ok { ret e2 }
    var j = 0usize
    while j < k {
        var i = 0usize
        while i < rows {
            yy[i] = y[(start + i) * k + j]
            i += 1usize
        }
        let (f, e3) = ols.ols(a, x, yy, rows, w)
        if e3 != ok { ret e3 }
        var q = 0usize
        while q < w {
            coef[j * w + q] = f.beta[q]
            q += 1usize
        }
        i = 0usize
        while i < rows {
            resid[i * k + j] = f.resid[i]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// the determinant of a k by k matrix by elimination with partial pivoting
fn det_of(m: []const f64, k: usize, scratch: []f64) -> f64 {
    var i = 0usize
    while i < k * k {
        scratch[i] = m[i]
        i += 1usize
    }
    var d = 1.0f64
    var c = 0usize
    while c < k {
        var piv = c
        var r = c + 1usize
        while r < k {
            if math.abs[f64](scratch[r * k + c]) > math.abs[f64](scratch[piv * k + c]) { piv = r }
            r += 1usize
        }
        if scratch[piv * k + c] == 0.0f64 { ret 0.0f64 }
        if piv != c {
            var j = 0usize
            while j < k {
                let t = scratch[c * k + j]
                scratch[c * k + j] = scratch[piv * k + j]
                scratch[piv * k + j] = t
                j += 1usize
            }
            d = 0.0f64 - d
        }
        d = d * scratch[c * k + c]
        r = c + 1usize
        while r < k {
            let f = scratch[r * k + c] / scratch[c * k + c]
            var j = c
            while j < k {
                scratch[r * k + j] -= f * scratch[c * k + j]
                j += 1usize
            }
            r += 1usize
        }
        c += 1usize
    }
    ret d
}

// the residual covariance of summary(VAR): crossprod(resid) / (T - k p - 1) with T the usable observations
fn sigma_u(resid: []const f64, rows: usize, k: usize, p: usize, out: []f64) {
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var t = 0usize
            while t < rows {
                s += resid[t * k + i] * resid[t * k + j]
                t += 1usize
            }
            out[i * k + j] = s / f64(rows - k * p - 1usize)
            j += 1usize
        }
        i += 1usize
    }
}

// VARselect(y, lag.max, type = "const")$criteria at lag p (1 ..= lag.max): kind 0 AIC, 1 HQ, 2 SC, 3 FPE
fn var_select(a: *mem.Arena, y: []const f64, t0: usize, k: usize, p: usize, lag_max: usize, kind: usize) -> f64 {
    let rows = t0 - lag_max
    let w = k * p + 1usize
    let (coef, e1) = mem.alloc[f64](a, k * w)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (res, e2) = mem.alloc[f64](a, rows * k)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    if var_fit(a, y, t0, k, p, lag_max, coef, res) != ok { ret 0.0f64 / 0.0f64 }
    let (sg, e3) = mem.alloc[f64](a, k * k)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var t = 0usize
            while t < rows {
                s += res[t * k + i] * res[t * k + j]
                t += 1usize
            }
            sg[i * k + j] = s / f64(rows)
            j += 1usize
        }
        i += 1usize
    }
    let (sc, e4) = mem.alloc[f64](a, k * k)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    let det = det_of(sg, k, sc)
    let tt = f64(rows)
    let npar = f64(p * k * k + k)
    if kind == 0usize { ret math.log[f64](det) + 2.0f64 * npar / tt }
    if kind == 1usize { ret math.log[f64](det) + 2.0f64 * math.log[f64](math.log[f64](tt)) * npar / tt }
    if kind == 2usize { ret math.log[f64](det) + math.log[f64](tt) * npar / tt }
    let r = (tt + f64(p * k) + 1.0f64) / (tt - f64(p * k) - 1.0f64)
    ret math.pow[f64](r, f64(k)) * det
}

// the h-step point forecasts (rows h by k, row-major) of a fitted VAR from the last p observations of y (t0 by k)
fn var_forecast(y: []const f64, t0: usize, k: usize, p: usize, coef: []const f64, h: usize, out: []f64, hist: []f64) {
    let w = k * p + 1usize
    // hist holds p + h rows: the last p observations then the forecasts
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < k {
            hist[i * k + j] = y[(t0 - p + i) * k + j]
            j += 1usize
        }
        i += 1usize
    }
    var s = 0usize
    while s < h {
        let row = p + s
        var j = 0usize
        while j < k {
            var v = coef[j * w + k * p]
            var l = 0usize
            while l < p {
                var c = 0usize
                while c < k {
                    v += coef[j * w + l * k + c] * hist[(row - 1usize - l) * k + c]
                    c += 1usize
                }
                l += 1usize
            }
            hist[row * k + j] = v
            out[s * k + j] = v
            j += 1usize
        }
        s += 1usize
    }
}

// the moving-average (impulse response) matrices Phi_0 .. Phi_h, each k by k row-major, in phi (h + 1 matrices): Phi_0 = I, Phi_s = sum_{j <= min(s, p)} A_j Phi_{s-j}
fn var_phi(coef: []const f64, k: usize, p: usize, h: usize, phi: []f64) {
    let w = k * p + 1usize
    var i = 0usize
    while i < k * k {
        phi[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        phi[i * k + i] = 1.0f64
        i += 1usize
    }
    var s = 1usize
    while s <= h {
        i = 0usize
        while i < k {
            var j = 0usize
            while j < k {
                var v = 0.0f64
                var l = 1usize
                while l <= p && l <= s {
                    var m = 0usize
                    while m < k {
                        v += coef[i * w + (l - 1usize) * k + m] * phi[(s - l) * k * k + m * k + j]
                        m += 1usize
                    }
                    l += 1usize
                }
                phi[s * k * k + i * k + j] = v
                j += 1usize
            }
            i += 1usize
        }
        s += 1usize
    }
}

// the lower Cholesky factor P of the k by k symmetric s (P P' = s); false when s is not positive definite
fn var_chol(s: []const f64, k: usize, p: []f64) -> bool {
    var i = 0usize
    while i < k * k {
        p[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j <= i {
            var v = s[i * k + j]
            var m = 0usize
            while m < j {
                v -= p[i * k + m] * p[j * k + m]
                m += 1usize
            }
            if i == j {
                if v <= 0.0f64 { ret false }
                p[i * k + i] = math.sqrt[f64](v)
            } else {
                p[i * k + j] = v / p[j * k + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// orthogonalised responses Phi_s P for s = 0 ..= h into out (h + 1 matrices of k by k)
fn var_oirf(phi: []const f64, p: []const f64, k: usize, h: usize, out: []f64) {
    var s = 0usize
    while s <= h {
        var i = 0usize
        while i < k {
            var j = 0usize
            while j < k {
                var v = 0.0f64
                var m = 0usize
                while m < k {
                    v += phi[s * k * k + i * k + m] * p[m * k + j]
                    m += 1usize
                }
                out[s * k * k + i * k + j] = v
                j += 1usize
            }
            i += 1usize
        }
        s += 1usize
    }
}

// deterministic terms: 0 none, 1 const, 2 trend, 3 both; the trend is the 1-based observation index as in vars (p + 1 .. T)
fn det_count(det: usize) -> usize {
    if det == 0usize { ret 0usize }
    if det == 3usize { ret 2usize }
    ret 1usize
}

// var_fit with the deterministic terms `det` (columns after the lags: const then trend); coef is k rows of k p + det_count columns
fn var_fit_det(a: *mem.Arena, y: []const f64, t0: usize, k: usize, p: usize, det: usize, coef: []f64, resid: []f64) -> err {
    let rows = t0 - p
    let nd = det_count(det)
    let w = k * p + nd
    let (x, e1) = mem.alloc[f64](a, rows * w)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < rows {
        let t = p + i
        var l = 0usize
        while l < p {
            var j = 0usize
            while j < k {
                x[i * w + l * k + j] = y[(t - 1usize - l) * k + j]
                j += 1usize
            }
            l += 1usize
        }
        var c = k * p
        if det == 1usize || det == 3usize {
            x[i * w + c] = 1.0f64
            c += 1usize
        }
        if det >= 2usize { x[i * w + c] = f64(t + 1usize) }
        i += 1usize
    }
    let (yy, e2) = mem.alloc[f64](a, rows)
    if e2 != ok { ret e2 }
    var j = 0usize
    while j < k {
        i = 0usize
        while i < rows {
            yy[i] = y[(p + i) * k + j]
            i += 1usize
        }
        let (f, e3) = ols.ols(a, x, yy, rows, w)
        if e3 != ok { ret e3 }
        var q = 0usize
        while q < w {
            coef[j * w + q] = f.beta[q]
            q += 1usize
        }
        i = 0usize
        while i < rows {
            resid[i * k + j] = f.resid[i]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// forecast error variance shares from the orthogonalised responses oo (h matrices Theta_0 .. Theta_{h-1}, k by k): out[(n - 1) k k + i k + j] is the share of series i's n-step error variance due to impulse j
fn var_fevd(oo: []const f64, k: usize, h: usize, out: []f64) {
    var n = 1usize
    while n <= h {
        var i = 0usize
        while i < k {
            var tot = 0.0f64
            var j = 0usize
            while j < k {
                var s = 0.0f64
                var t = 0usize
                while t < n {
                    let v = oo[t * k * k + i * k + j]
                    s += v * v
                    t += 1usize
                }
                out[(n - 1usize) * k * k + i * k + j] = s
                tot += s
                j += 1usize
            }
            j = 0usize
            while j < k {
                out[(n - 1usize) * k * k + i * k + j] /= tot
                j += 1usize
            }
            i += 1usize
        }
        n += 1usize
    }
}
