// R pscl: zero-inflated Poisson (zeroinfl, logit zero part) and the Poisson hurdle model (hurdle, zero-truncated count part and logit zero part), fitted by Newton's method with step halving on the exact Hessian (R uses BFGS from glm starting values; the likelihood optimum is what is compared). Matrices are row-major with their own constant columns.
//
// Not here: negative binomial and geometric counts, the other zero links, offsets and weights, prediction types beyond response, count and zero.

use e.algo.stat.gparot as gp
use e.math
use e.math.nmath as nm
use e.mem

// models: 0 zero-inflated Poisson (par = beta[p], gamma[q]), 1 Poisson on all rows (start values), 2 zero-truncated Poisson on the positive rows (par = beta[p]), 3 logistic on y > 0 (par = gamma[q], uses z)
fn lik(model: usize, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []const f64, gr: []f64, h: []f64, want: bool) -> f64 {
    var m = p + q
    if model == 1usize || model == 2usize { m = p }
    if model == 3usize { m = q }
    var i = 0usize
    if want {
        while i < m {
            gr[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < m * m {
            h[i] = 0.0f64
            i += 1usize
        }
    }
    var ll = 0.0f64
    var t = 0usize
    while t < n {
        let yt = y[t]
        var eta = 0.0f64
        var zeta = 0.0f64
        var c = 0usize
        if model != 3usize {
            while c < p {
                eta += par[c] * x[t * p + c]
                c += 1usize
            }
        }
        if model == 0usize || model == 3usize {
            c = 0usize
            var off = p
            if model == 3usize { off = 0usize }
            while c < q {
                zeta += par[off + c] * z[t * q + c]
                c += 1usize
            }
        }
        let lam = math.exp[f64](eta)
        // derivatives of the term in (d1 = d/d eta, d2, e1 = d/d zeta, e2, ez = cross)
        var d1 = 0.0f64
        var d2 = 0.0f64
        var e1 = 0.0f64
        var e2 = 0.0f64
        var ez = 0.0f64
        if model == 1usize {
            ll += yt * eta - lam - nm.lgammafn(yt + 1.0f64)
            d1 = yt - lam
            d2 = 0.0f64 - lam
        }
        if model == 2usize {
            if yt > 0.0f64 {
                let g = 1.0f64 / (math.exp[f64](lam) - 1.0f64)
                ll += yt * eta - lam - math.log[f64](1.0f64 - math.exp[f64](0.0f64 - lam)) - nm.lgammafn(yt + 1.0f64)
                d1 = yt - lam - lam * g
                let gp2 = 0.0f64 - math.exp[f64](lam) * g * g
                d2 = 0.0f64 - lam - lam * g - lam * lam * gp2
            }
        }
        if model == 3usize {
            let pi = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - zeta))
            if yt > 0.0f64 {
                ll += math.log[f64](pi)
                e1 = 1.0f64 - pi
            } else {
                ll += math.log[f64](1.0f64 - pi)
                e1 = 0.0f64 - pi
            }
            e2 = 0.0f64 - pi * (1.0f64 - pi)
        }
        if model == 0usize {
            let pi = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - zeta))
            let em = math.exp[f64](0.0f64 - lam)
            let dpi = pi * (1.0f64 - pi)
            let ddpi = dpi * (1.0f64 - 2.0f64 * pi)
            var lpi = 0.0f64
            var llam = 0.0f64
            var lpp = 0.0f64
            var lll = 0.0f64
            var lpl = 0.0f64
            if yt == 0.0f64 {
                let p0 = pi + (1.0f64 - pi) * em
                ll += math.log[f64](p0)
                let a = (1.0f64 - pi) * em
                let b = 1.0f64 - em
                lpi = b / p0
                llam = 0.0f64 - a / p0
                lpp = 0.0f64 - b * b / (p0 * p0)
                lll = a / p0 - a * a / (p0 * p0)
                lpl = em / p0 + a * b / (p0 * p0)
            } else {
                ll += math.log[f64](1.0f64 - pi) + yt * eta - lam - nm.lgammafn(yt + 1.0f64)
                lpi = 0.0f64 - 1.0f64 / (1.0f64 - pi)
                llam = yt / lam - 1.0f64
                lpp = 0.0f64 - 1.0f64 / ((1.0f64 - pi) * (1.0f64 - pi))
                lll = 0.0f64 - yt / (lam * lam)
            }
            d1 = llam * lam
            d2 = lll * lam * lam + llam * lam
            e1 = lpi * dpi
            e2 = lpp * dpi * dpi + lpi * ddpi
            ez = lpl * lam * dpi
        }
        if want {
            var r = 0usize
            if model != 3usize {
                while r < p {
                    gr[r] += d1 * x[t * p + r]
                    var s = 0usize
                    while s < p {
                        h[r * m + s] += d2 * x[t * p + r] * x[t * p + s]
                        s += 1usize
                    }
                    r += 1usize
                }
            }
            if model == 0usize || model == 3usize {
                var off = p
                if model == 3usize { off = 0usize }
                r = 0usize
                while r < q {
                    gr[off + r] += e1 * z[t * q + r]
                    var s = 0usize
                    while s < q {
                        h[(off + r) * m + off + s] += e2 * z[t * q + r] * z[t * q + s]
                        s += 1usize
                    }
                    if model == 0usize {
                        s = 0usize
                        while s < p {
                            h[(p + r) * m + s] += ez * z[t * q + r] * x[t * p + s]
                            h[s * m + p + r] += ez * z[t * q + r] * x[t * p + s]
                            s += 1usize
                        }
                    }
                    r += 1usize
                }
            }
        }
        t += 1usize
    }
    ret ll
}

fn maximise(a: *mem.Arena, model: usize, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    var m = p + q
    if model == 1usize || model == 2usize { m = p }
    if model == 3usize { m = q }
    let (gr, e1) = mem.alloc[f64](a, m)
    let (h, e2) = mem.alloc[f64](a, m * m)
    let (trial, e3) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var ll = lik(model, x, z, y, n, p, q, par, gr, h, true)
    var it = 0usize
    while it < 300usize {
        let start = mem.mark(a)
        let (inv, ie) = gp.invert(a, h, m)
        var scale = 1.0f64
        var moved = false
        var tries = 0usize
        while tries < 50usize {
            var i = 0usize
            while i < m {
                var d = 0.0f64
                if ie == ok {
                    var l = 0usize
                    while l < m {
                        d += inv[i * m + l] * gr[l]
                        l += 1usize
                    }
                    d = 0.0f64 - d
                } else {
                    d = gr[i] * 0.01f64
                }
                trial[i] = par[i] + scale * d
                i += 1usize
            }
            // an uphill Newton direction is a saddle: fall back to the gradient
            let ll2 = lik(model, x, z, y, n, p, q, trial, gr, h, false)
            if ll2 == ll2 && ll2 > ll - 1.0e-15f64 {
                i = 0usize
                while i < m {
                    par[i] = trial[i]
                    i += 1usize
                }
                let step = math.abs[f64](ll2 - ll)
                ll = lik(model, x, z, y, n, p, q, par, gr, h, true)
                moved = true
                if step < 1.0e-13f64 {
                    mem.reset(a, start)
                    ret ll
                }
                break
            }
            scale = scale / 2.0f64
            tries += 1usize
        }
        mem.reset(a, start)
        if !moved { break }
        it += 1usize
    }
    ret ll
}

// zeroinfl(y ~ x | z, dist = "poisson"): par receives beta (p) then gamma (q); returns the log-likelihood
fn zeroinfl(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []f64) -> f64 {
    let (b0, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < p {
        b0[i] = 0.0f64
        i += 1usize
    }
    let r = maximise(a, 1usize, x, z, y, n, p, q, b0)
    if r != r { ret r }
    i = 0usize
    while i < p {
        par[i] = b0[i]
        i += 1usize
    }
    i = 0usize
    while i < q {
        par[p + i] = 0.0f64
        i += 1usize
    }
    ret maximise(a, 0usize, x, z, y, n, p, q, par)
}

// hurdle(y ~ x | z, dist = "poisson"): par receives beta (p, truncated count part) then gamma (q, zero part); returns the sum of the two log-likelihoods
fn hurdle(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []f64) -> f64 {
    let (b0, e1) = mem.alloc[f64](a, p)
    let (g0, e2) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < p {
        b0[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < q {
        g0[i] = 0.0f64
        i += 1usize
    }
    // start the truncated part from the full Poisson fit on the positive rows
    let r0 = maximise(a, 1usize, x, z, y, n, p, q, b0)
    if r0 != r0 { ret r0 }
    let r1 = maximise(a, 2usize, x, z, y, n, p, q, b0)
    let r2 = maximise(a, 3usize, x, z, y, n, p, q, g0)
    i = 0usize
    while i < p {
        par[i] = b0[i]
        i += 1usize
    }
    i = 0usize
    while i < q {
        par[p + i] = g0[i]
        i += 1usize
    }
    ret r1 + r2
}

// the standard errors of the fitted parameters (square roots of the diagonal of the inverse of minus the exact Hessian at par): kind 0 zeroinfl (one block, p + q parameters),
// kind 1 hurdle (the truncated count part and the zero part are separate blocks, as vcov gives block-diagonal)
fn standard_errors(a: *mem.Arena, kind: usize, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []const f64, se: []f64) -> err {
    var blocks = 1usize
    if kind == 1usize { blocks = 2usize }
    var b = 0usize
    while b < blocks {
        var model = 0usize
        var m = p + q
        var off = 0usize
        if kind == 1usize {
            if b == 0usize {
                model = 2usize
                m = p
            } else {
                model = 3usize
                m = q
                off = p
            }
        }
        let (gr, e1) = mem.alloc[f64](a, m)
        let (h, e2) = mem.alloc[f64](a, m * m)
        let (pb, e3) = mem.alloc[f64](a, m)
        if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
        var i = 0usize
        while i < m {
            pb[i] = par[off + i]
            i += 1usize
        }
        let ll = lik(model, x, z, y, n, p, q, pb, gr, h, true)
        if ll != ll { ret mem.Full }
        i = 0usize
        while i < m * m {
            h[i] = 0.0f64 - h[i]
            i += 1usize
        }
        let (inv, ie) = gp.invert(a, h, m)
        if ie != ok { ret ie }
        i = 0usize
        while i < m {
            se[off + i] = math.sqrt[f64](inv[i * m + i])
            i += 1usize
        }
        b += 1usize
    }
    ret ok
}

// predict at the fitted rows (type 0 response, 1 count, 2 zero). zeroinfl: count mu = exp(x beta), zero pi = logistic(z gamma), response (1 - pi) mu. hurdle (pscl's
// definitions): count mu, zero pi / (1 - exp(-mu)) with pi the logistic part (the zero-hurdle probability of a positive count), response pi mu / (1 - exp(-mu)).
fn predict(kind: usize, x: []const f64, z: []const f64, n: usize, p: usize, q: usize, par: []const f64, ptype: usize, out: []f64) {
    var r = 0usize
    while r < n {
        var eta = 0.0f64
        var j = 0usize
        while j < p {
            eta += x[r * p + j] * par[j]
            j += 1usize
        }
        var zeta = 0.0f64
        j = 0usize
        while j < q {
            zeta += z[r * q + j] * par[p + j]
            j += 1usize
        }
        let mu = math.exp[f64](eta)
        let pi = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - zeta))
        var v = 0.0f64
        if kind == 0usize {
            if ptype == 0usize { v = (1.0f64 - pi) * mu }
            if ptype == 1usize { v = mu }
            if ptype == 2usize { v = pi }
        } else {
            if ptype == 0usize { v = pi * mu / (1.0f64 - math.exp[f64](0.0f64 - mu)) }
            if ptype == 1usize { v = mu }
            if ptype == 2usize { v = pi / (1.0f64 - math.exp[f64](0.0f64 - mu)) }
        }
        out[r] = v
        r += 1usize
    }
}

// vuong(zeroinfl, glm Poisson): the three statistics (raw, AIC-corrected, BIC-corrected) of the non-nested comparison of the zero-inflated Poisson fit with par against the plain Poisson
// fit (k2 = p). The per-row log probability ratios m, the corrections (k1 - k2) / n and (k1 - k2) log(n) / (2 n), v = sum(m - c) / (sd(m - c) sqrt(n)).
fn vuong_zip_poisson(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []const f64, out: []f64) -> err {
    let (b0, e1) = mem.alloc[f64](a, p)
    let (m, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < p {
        b0[i] = 0.0f64
        i += 1usize
    }
    let r = maximise(a, 1usize, x, z, y, n, p, q, b0)
    if r != r { ret mem.Full }
    var r0 = 0usize
    while r0 < n {
        var eta = 0.0f64
        var j = 0usize
        while j < p {
            eta += x[r0 * p + j] * par[j]
            j += 1usize
        }
        var eta2 = 0.0f64
        j = 0usize
        while j < p {
            eta2 += x[r0 * p + j] * b0[j]
            j += 1usize
        }
        var zeta = 0.0f64
        j = 0usize
        while j < q {
            zeta += z[r0 * q + j] * par[p + j]
            j += 1usize
        }
        let mu = math.exp[f64](eta)
        let pi = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - zeta))
        let d1 = nm.dpois_raw(y[r0], mu, false)
        var p1 = (1.0f64 - pi) * d1
        if y[r0] == 0.0f64 { p1 = pi + (1.0f64 - pi) * d1 }
        let p2 = nm.dpois_raw(y[r0], math.exp[f64](eta2), false)
        m[r0] = math.log[f64](p1) - math.log[f64](p2)
        r0 += 1usize
    }
    let nf = f64(n)
    let dk = f64(p + q) - f64(p)
    var c = 0usize
    while c < 3usize {
        var corr = 0.0f64
        if c == 1usize { corr = dk / nf }
        if c == 2usize { corr = dk / (2.0f64 * nf) * math.log[f64](nf) }
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += m[i] - corr
            i += 1usize
        }
        let mean = s / nf
        var ss = 0.0f64
        i = 0usize
        while i < n {
            let d = m[i] - corr - mean
            ss += d * d
            i += 1usize
        }
        out[c] = s / (math.sqrt[f64](ss / (nf - 1.0f64)) * math.sqrt[f64](nf))
        c += 1usize
    }
    ret ok
}
