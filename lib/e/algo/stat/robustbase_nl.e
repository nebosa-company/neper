// R robustbase nlrob (method "M", Huber weights psi, scale updated by the MAD, test.vec "resid") over nls's Gauss-Newton with its forward-difference gradient (numericDeriv),
// step for step: tol 1e-5, at most 50 iterations, step halving down to 1/1024. The model is one of three fixed forms.

use e.math
use e.algo.linalg.decomp as dc
use e.algo.stat.armx87 as xe
use e.algo.stat.robustbase as rb
use e.mem

// the model functions: 1 a*exp(b*x), 2 a*x/(b+x), 3 a + b*exp(-c*x), 4 a/(1+b*x*x)
fn nl_model(m: usize, p: []const f64, x: f64) -> f64 {
    if m == 1usize { ret p[0usize] * xe.exp_r(p[1usize] * x) }
    if m == 2usize { ret p[0usize] * x / (p[1usize] + x) }
    if m == 4usize { ret p[0usize] / (1.0f64 + p[1usize] * x * x) }
    ret p[0usize] + p[1usize] * xe.exp_r(0.0f64 - p[2usize] * x)
}

// nlsModel's setPars: resid = sqrt(w) (y - f), the weighted forward-difference gradient (numericDeriv, delta = sqrt(eps) |par|) and its qr; dev gets the sum of squared residuals.
fn nls_set(a: *mem.Arena, m: usize, par: []const f64, np: usize, x: []const f64, y: []const f64, sw: []const f64, n: usize, resid: []f64, tmp: []f64) -> (dc.Qr, f64, err) {
    var empty: dc.Qr = zero
    let (g, e0) = mem.alloc[f64](a, n * np)
    let (pp, e1) = mem.alloc[f64](a, np)
    if e0 != ok { ret (empty, 0.0f64, e0) }
    if e1 != ok { ret (empty, 0.0f64, e1) }
    let reps = 1.4901161193847656e-8f64
    var i = 0usize
    var dev = 0.0f64
    while i < n {
        let rhs = nl_model(m, par, x[i])
        resid[i] = sw[i] * (y[i] - rhs)
        tmp[i] = rhs
        dev = dev + resid[i] * resid[i]
        i += 1usize
    }
    var j = 0usize
    while j < np {
        var k = 0usize
        while k < np {
            pp[k] = par[k]
            k += 1usize
        }
        var delta = reps
        if par[j] != 0.0f64 { delta = math.abs[f64](par[j]) * reps }
        pp[j] = par[j] + delta
        i = 0usize
        while i < n {
            g[j * n + i] = sw[i] * ((nl_model(m, pp, x[i]) - tmp[i]) / delta)
            i += 1usize
        }
        j += 1usize
    }
    let (q, qe) = rb.dqrdc2_blue(a, g, n, np, 1.0e-7f64)
    if qe != ok { ret (empty, 0.0f64, qe) }
    ret (q, dev, ok)
}

fn nls_conv(q: *const dc.Qr, resid: []const f64, n: usize, np: usize, rr: []f64) -> f64 {
    var i = 0usize
    while i < n {
        rr[i] = resid[i]
        i += 1usize
    }
    dc.qr_qty(q, rr)
    var s1 = 0.0f64
    var s2 = 0.0f64
    i = 0usize
    while i < np {
        s1 = s1 + rr[i] * rr[i]
        i += 1usize
    }
    while i < n {
        s2 = s2 + rr[i] * rr[i]
        i += 1usize
    }
    ret math.sqrt[f64](s1 / s2)
}

// nls(..., weights, start = par): par is updated, resid gets the weighted residuals and q_out the final qr. false when it did not converge.
fn nls_fit(a: *mem.Arena, m: usize, par: []f64, np: usize, x: []const f64, y: []const f64, sw: []const f64, n: usize, resid: []f64, q_out: *dc.Qr) -> (bool, err) {
    let (tmp, e0) = mem.alloc[f64](a, n)
    let (rr, e1) = mem.alloc[f64](a, n)
    let (inc, e2) = mem.alloc[f64](a, np)
    let (np2, e3) = mem.alloc[f64](a, np)
    if e0 != ok { ret (false, e0) }
    if e1 != ok { ret (false, e1) }
    if e2 != ok { ret (false, e2) }
    if e3 != ok { ret (false, e3) }
    let (q0, dev0, qe) = nls_set(a, m, par, np, x, y, sw, n, resid, tmp)
    if qe != ok { ret (false, qe) }
    var q = q0
    var dev = dev0
    var fac = 1.0f64
    var it = 0usize
    var conv = false
    while it < 50usize {
        let cv = nls_conv(&q, resid, n, np, rr)
        if cv <= 1.0e-5f64 {
            conv = true
            break
        }
        // qr.coef: back-substitution R inc = (Q'resid)[1..np]
        var jj = np
        while jj > 0usize {
            jj -= 1usize
            var s = rr[jj]
            var k = jj + 1usize
            while k < np {
                s = s - q.qr[k * n + jj] * inc[k]
                k += 1usize
            }
            inc[jj] = s / q.qr[jj * n + jj]
        }
        var accepted = false
        while fac >= 1.0f64 / 1024.0f64 {
            var k = 0usize
            while k < np {
                np2[k] = par[k] + fac * inc[k]
                k += 1usize
            }
            let (q2, dev2, e4) = nls_set(a, m, np2, np, x, y, sw, n, resid, tmp)
            if e4 != ok { ret (false, e4) }
            if dev2 <= dev {
                dev = dev2
                q = q2
                k = 0usize
                while k < np {
                    par[k] = np2[k]
                    k += 1usize
                }
                fac = 2.0f64 * fac
                if fac > 1.0f64 { fac = 1.0f64 }
                accepted = true
                break
            }
            fac = fac / 2.0f64
        }
        if !accepted { ret (false, ok) }
        it += 1usize
    }
    *q_out = q
    ret (conv, ok)
}

fn huber_w(x: f64, cc: f64) -> f64 {
    let ax = math.abs[f64](x)
    if ax <= cc { ret 1.0f64 }
    ret cc / ax
}

type NlrobFit = struct { iter: usize, converged: bool, scale: f64 }

// nlrob(method = "M", doCov = TRUE): cov gets (R'R)^-1 Scale^2 tau (np by np, row-major), rw the robustness weights psi(resid/Scale), res the working residuals.
fn nlrob_m(a: *mem.Arena, m: usize, par: []f64, np: usize, x: []const f64, y: []const f64, n: usize, cc: f64, maxit: usize, tol: f64, cov: []f64, rw: []f64, res: []f64) -> (NlrobFit, err) {
    var fit = NlrobFit { iter: 0usize, converged: false, scale: 0.0f64 }
    let (resid, e0) = mem.alloc[f64](a, n)
    let (prev, e1) = mem.alloc[f64](a, n)
    let (sw, e2) = mem.alloc[f64](a, n)
    let (ab, e3) = mem.alloc[f64](a, n)
    if e0 != ok { ret (fit, e0) }
    if e1 != ok { ret (fit, e1) }
    if e2 != ok { ret (fit, e2) }
    if e3 != ok { ret (fit, e3) }
    var i = 0usize
    while i < n {
        res[i] = y[i] - nl_model(m, par, x[i])
        i += 1usize
    }
    var qlast: dc.Qr = zero
    var scale = 0.0f64
    var it = 1usize
    while it <= maxit {
        i = 0usize
        while i < n {
            prev[i] = res[i]
            ab[i] = math.abs[f64](res[i])
            i += 1usize
        }
        let (s, se) = rb.sort_copy(a, ab)
        if se != ok { ret (fit, se) }
        scale = rb.median_sorted(s) / 0.6745f64
        if scale == 0.0f64 { break }
        i = 0usize
        while i < n {
            sw[i] = math.sqrt[f64](huber_w(res[i] / scale, cc))
            i += 1usize
        }
        let (ok2, fe) = nls_fit(a, m, par, np, x, y, sw, n, resid, &qlast)
        if fe != ok { ret (fit, fe) }
        if !ok2 { break }
        i = 0usize
        while i < n {
            res[i] = y[i] - nl_model(m, par, x[i])
            i += 1usize
        }
        var d1 = 0.0f64
        var d2 = 0.0f64
        i = 0usize
        while i < n {
            d1 = d1 + (prev[i] - res[i]) * (prev[i] - res[i])
            d2 = d2 + prev[i] * prev[i]
            i += 1usize
        }
        if d2 < 1.0e-20f64 { d2 = 1.0e-20f64 }
        fit.iter = it
        if math.sqrt[f64](d1 / d2) <= tol {
            fit.converged = true
            break
        }
        it += 1usize
    }
    fit.scale = scale
    if !fit.converged { ret (fit, ok) }
    var sr = 0.0f64
    var sd = 0.0f64
    i = 0usize
    while i < n {
        let r = res[i] / scale
        rw[i] = huber_w(r, cc)
        sr = sr + rw[i] * rw[i]
        if math.abs[f64](r) <= cc { sd = sd + 1.0f64 }
        i += 1usize
    }
    let tau = (sr / f64(n)) / ((sd / f64(n)) * (sd / f64(n)))
    // chol2inv(R): R^-1 by back substitution, then R^-1 R^-T
    let (ri, e4) = mem.alloc[f64](a, np * np)
    if e4 != ok { ret (fit, e4) }
    var c = 0usize
    while c < np {
        var r2 = np
        while r2 > 0usize {
            r2 -= 1usize
            var s = 0.0f64
            if r2 == c { s = 1.0f64 }
            var k = r2 + 1usize
            while k < np {
                s = s - qlast.qr[k * n + r2] * ri[k * np + c]
                k += 1usize
            }
            ri[r2 * np + c] = s / qlast.qr[r2 * n + r2]
        }
        c += 1usize
    }
    var r3 = 0usize
    while r3 < np {
        c = 0usize
        while c < np {
            var s = 0.0f64
            var k = 0usize
            while k < np {
                s = s + ri[r3 * np + k] * ri[c * np + k]
                k += 1usize
            }
            cov[r3 * np + c] = s * scale * scale * tau
            c += 1usize
        }
        r3 += 1usize
    }
    ret (fit, ok)
}
