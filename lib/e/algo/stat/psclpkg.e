// R pscl: zero-inflated Poisson (zeroinfl, logit zero part) and the Poisson hurdle model (hurdle, zero-truncated count part and logit zero part), fitted by Newton's method with step halving on the exact Hessian (R uses BFGS from glm starting values; the likelihood optimum is what is compared). Matrices are row-major with their own constant columns.
//
// Not here: the other zero links, offsets and weights, prediction types beyond response, count and zero.

use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.math.opt as opt
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

// zeroinfl(y ~ x | z, dist = "negbin"): the zero-inflated negative binomial (logit zero part, theta on the log scale as the last parameter) by BFGS on the exact log-likelihood with central-difference
// gradients, started from the zero-inflated Poisson fit. par receives beta (p), gamma (q), log theta; returns the log-likelihood (NaN on failure)
type NbCtx = struct { x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, geom: bool }

fn nb_loglik(c: *NbCtx, par: []const f64) -> f64 {
    var ll = 0.0f64
    var theta = 1.0f64
    if !c.geom { theta = math.exp[f64](par[c.p + c.q]) }
    var i = 0usize
    while i < c.n {
        var eta = 0.0f64
        var j = 0usize
        while j < c.p {
            eta += c.x[i * c.p + j] * par[j]
            j += 1usize
        }
        var zeta = 0.0f64
        j = 0usize
        while j < c.q {
            zeta += c.z[i * c.q + j] * par[c.p + j]
            j += 1usize
        }
        let mu = math.exp[f64](eta)
        let pi = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - zeta))
        let lq = theta * math.log[f64](theta / (theta + mu))
        if c.y[i] == 0.0f64 {
            ll += math.log[f64](pi + (1.0f64 - pi) * math.exp[f64](lq))
        } else {
            ll += math.log[f64](1.0f64 - pi) + nm.lgammafn(theta + c.y[i]) - nm.lgammafn(theta) - nm.lgammafn(c.y[i] + 1.0f64) + lq + c.y[i] * math.log[f64](mu / (theta + mu))
        }
        i += 1usize
    }
    ret ll
}

fn nb_neg(c: *NbCtx, par: []const f64) -> f64 {
    let v = nb_loglik(c, par)
    if v != v { ret 1.0e300f64 }
    ret 0.0f64 - v
}

fn nb_grad(c: *NbCtx, par: []const f64, g: []f64) {
    let m = par.len
    var w: [32]f64 = zero
    var k = 0usize
    while k < m {
        w[k] = par[k]
        k += 1usize
    }
    k = 0usize
    while k < m {
        var h = 1.0e-6f64
        if math.abs[f64](par[k]) > 1.0f64 { h = 1.0e-6f64 * math.abs[f64](par[k]) }
        w[k] = par[k] + h
        let f1 = nb_neg(c, w[0usize..m])
        w[k] = par[k] - h
        let f2 = nb_neg(c, w[0usize..m])
        w[k] = par[k]
        g[k] = (f1 - f2) / (2.0f64 * h)
        k += 1usize
    }
}

fn zeroinfl_nb(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let m = p + q + 1usize
    if m > 32usize { ret nan }
    let l0 = zeroinfl(a, x, z, y, n, p, q, par[0usize..p + q])
    if l0 != l0 { ret nan }
    par[p + q] = 0.0f64
    var c = NbCtx { x: x, z: z, y: y, n: n, p: p, q: q, geom: false }
    let (scr, e0) = mem.alloc[f64](a, m * m + 6usize * m)
    if e0 != ok { ret nan }
    var round = 0usize
    while round < 2usize {
        let (r, e1) = opt.bfgs[NbCtx](&c, nb_neg, nb_grad, par, 1.0e-8f64, 400u32, scr)
        let _ = r
        if e1 != ok { ret nan }
        round += 1usize
    }
    ret nb_loglik(&c, par)
}

// the zero-truncated negative binomial count part of hurdle(dist = "negbin"): the log-likelihood over the positive rows, parameters beta (p) and log theta
fn nbt_loglik(c: *NbCtx, par: []const f64) -> f64 {
    var ll = 0.0f64
    var theta = 1.0f64
    if !c.geom { theta = math.exp[f64](par[c.p]) }
    var i = 0usize
    while i < c.n {
        if c.y[i] > 0.0f64 {
            var eta = 0.0f64
            var j = 0usize
            while j < c.p {
                eta += c.x[i * c.p + j] * par[j]
                j += 1usize
            }
            let mu = math.exp[f64](eta)
            let lq = theta * math.log[f64](theta / (theta + mu))
            ll += nm.lgammafn(theta + c.y[i]) - nm.lgammafn(theta) - nm.lgammafn(c.y[i] + 1.0f64) + lq + c.y[i] * math.log[f64](mu / (theta + mu)) - math.log[f64](1.0f64 - math.exp[f64](lq))
        }
        i += 1usize
    }
    ret ll
}

fn nbt_neg(c: *NbCtx, par: []const f64) -> f64 {
    var j = 0usize
    while j < par.len {
        if math.abs[f64](par[j]) > 12.0f64 { ret 1.0e300f64 }
        j += 1usize
    }
    let v = nbt_loglik(c, par)
    if v != v { ret 1.0e300f64 }
    ret 0.0f64 - v
}

fn nbt_grad(c: *NbCtx, par: []const f64, g: []f64) {
    let m = par.len
    var w: [32]f64 = zero
    var k = 0usize
    while k < m {
        w[k] = par[k]
        k += 1usize
    }
    k = 0usize
    while k < m {
        var h = 1.0e-6f64
        if math.abs[f64](par[k]) > 1.0f64 { h = 1.0e-6f64 * math.abs[f64](par[k]) }
        w[k] = par[k] + h
        let f1 = nbt_neg(c, w[0usize..m])
        w[k] = par[k] - h
        let f2 = nbt_neg(c, w[0usize..m])
        w[k] = par[k]
        g[k] = (f1 - f2) / (2.0f64 * h)
        k += 1usize
    }
}

// hurdle(y ~ x | z, dist = "negbin"): par receives beta (p), gamma (q) and log theta; the logit zero part is the existing exact fit, the truncated count part is BFGS from the truncated Poisson fit;
// returns the sum of the two log-likelihoods (NaN on failure)
fn hurdle_nb(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let m = p + 1usize
    if m > 32usize { ret nan }
    let l0 = hurdle(a, x, z, y, n, p, q, par[0usize..p + q])
    if l0 != l0 { ret nan }
    // the zero part's log-likelihood: the logit on y > 0
    let (gr, e1) = mem.alloc[f64](a, q)
    let (hh, e2) = mem.alloc[f64](a, q * q)
    if e1 != ok || e2 != ok { ret nan }
    let lz = lik(3usize, x, z, y, n, p, q, par[p..p + q], gr, hh, false)
    // the truncated count part on its own parameters (beta, log theta), keeping gamma aside
    let (bt, e3) = mem.alloc[f64](a, m)
    if e3 != ok { ret nan }
    var j = 0usize
    while j < p {
        bt[j] = par[j]
        j += 1usize
    }
    bt[p] = 0.0f64
    var c = NbCtx { x: x, z: z, y: y, n: n, p: p, q: 0usize, geom: false }
    let (scr, e4) = mem.alloc[f64](a, m * m + 6usize * m)
    if e4 != ok { ret nan }
    var round = 0usize
    while round < 2usize {
        let (r, e5) = opt.bfgs[NbCtx](&c, nbt_neg, nbt_grad, bt, 1.0e-8f64, 400u32, scr)
        let _ = r
        if e5 != ok { ret nan }
        round += 1usize
    }
    // layout of par: beta (p), gamma (q), log theta
    var gm: [8]f64 = zero
    j = 0usize
    while j < q {
        gm[j] = par[p + j]
        j += 1usize
    }
    j = 0usize
    while j < p {
        par[j] = bt[j]
        j += 1usize
    }
    j = 0usize
    while j < q {
        par[p + j] = gm[j]
        j += 1usize
    }
    par[p + q] = bt[p]
    ret nbt_loglik(&c, bt) + lz
}

// zeroinfl(y ~ x | z, dist = "geometric") is the negative binomial with theta = 1 fixed: BFGS on beta (p) and gamma (q) from the zero-inflated Poisson fit; returns the log-likelihood
fn zeroinfl_geom(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let m = p + q
    if m > 32usize { ret nan }
    let l0 = zeroinfl(a, x, z, y, n, p, q, par[0usize..m])
    if l0 != l0 { ret nan }
    var c = NbCtx { x: x, z: z, y: y, n: n, p: p, q: q, geom: true }
    let (scr, e0) = mem.alloc[f64](a, m * m + 6usize * m)
    if e0 != ok { ret nan }
    var round = 0usize
    while round < 2usize {
        let (r, e1) = opt.bfgs[NbCtx](&c, nb_neg, nb_grad, par[0usize..m], 1.0e-8f64, 400u32, scr)
        let _ = r
        if e1 != ok { ret nan }
        round += 1usize
    }
    ret nb_loglik(&c, par[0usize..m])
}

// hurdle(y ~ x | z, dist = "geometric"): the exact logit zero part plus the zero-truncated geometric count part (BFGS on beta from the truncated Poisson fit); par receives beta (p) then gamma (q);
// returns the total log-likelihood
fn hurdle_geom(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    if p > 32usize { ret nan }
    let l0 = hurdle(a, x, z, y, n, p, q, par[0usize..p + q])
    if l0 != l0 { ret nan }
    let (gr, e1) = mem.alloc[f64](a, q)
    let (hh, e2) = mem.alloc[f64](a, q * q)
    if e1 != ok || e2 != ok { ret nan }
    let lz = lik(3usize, x, z, y, n, p, q, par[p..p + q], gr, hh, false)
    var c = NbCtx { x: x, z: z, y: y, n: n, p: p, q: 0usize, geom: true }
    let (scr, e4) = mem.alloc[f64](a, p * p + 6usize * p)
    if e4 != ok { ret nan }
    var round = 0usize
    while round < 2usize {
        let (r, e5) = opt.bfgs[NbCtx](&c, nbt_neg, nbt_grad, par[0usize..p], 1.0e-8f64, 400u32, scr)
        let _ = r
        if e5 != ok { ret nan }
        round += 1usize
    }
    ret nbt_loglik(&c, par[0usize..p]) + lz
}

fn link_inv(link: usize, e: f64) -> f64 {
    if link == 1usize { ret dist.pnorm(e, 0.0f64, 1.0f64, true, false) }
    if link == 2usize { ret 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](e)) }
    if link == 3usize { ret 0.5f64 + math.atan[f64](e) / 3.141592653589793238462643383279f64 }
    ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - e))
}

type LkCtx = struct { x: []const f64, z: []const f64, y: []const f64, n: usize, p: usize, q: usize, link: usize, part: usize, w: []const f64, off: []const f64 }

// the zero-inflated Poisson log-likelihood (part 0) with the zero part's link, or the binomial log-likelihood of y > 0 (part 1, the hurdle's zero part) on gamma alone
fn lk_loglik(c: *LkCtx, par: []const f64) -> f64 {
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        var zeta = 0.0f64
        var j = 0usize
        if c.part == 0usize {
            while j < c.q {
                zeta += c.z[i * c.q + j] * par[c.p + j]
                j += 1usize
            }
            var eta = c.off[i]
            j = 0usize
            while j < c.p {
                eta += c.x[i * c.p + j] * par[j]
                j += 1usize
            }
            let mu = math.exp[f64](eta)
            let pi = link_inv(c.link, zeta)
            if c.y[i] == 0.0f64 {
                ll += c.w[i] * math.log[f64](pi + (1.0f64 - pi) * math.exp[f64](0.0f64 - mu))
            } else {
                ll += c.w[i] * (math.log[f64](1.0f64 - pi) + c.y[i] * eta - mu - nm.lgammafn(c.y[i] + 1.0f64))
            }
        } else {
            while j < c.q {
                zeta += c.z[i * c.q + j] * par[j]
                j += 1usize
            }
            let pr = link_inv(c.link, zeta)
            if c.y[i] > 0.0f64 { ll += c.w[i] * math.log[f64](pr) } else { ll += c.w[i] * math.log[f64](1.0f64 - pr) }
        }
        i += 1usize
    }
    ret ll
}

fn lk_neg(c: *LkCtx, par: []const f64) -> f64 {
    var j = 0usize
    while j < par.len {
        if math.abs[f64](par[j]) > 30.0f64 { ret 1.0e300f64 }
        j += 1usize
    }
    let v = lk_loglik(c, par)
    if v != v { ret 1.0e300f64 }
    ret 0.0f64 - v
}

fn lk_grad(c: *LkCtx, par: []const f64, g: []f64) {
    let m = par.len
    var w: [32]f64 = zero
    var k = 0usize
    while k < m {
        w[k] = par[k]
        k += 1usize
    }
    k = 0usize
    while k < m {
        var h = 1.0e-6f64
        if math.abs[f64](par[k]) > 1.0f64 { h = 1.0e-6f64 * math.abs[f64](par[k]) }
        w[k] = par[k] + h
        let f1 = lk_neg(c, w[0usize..m])
        w[k] = par[k] - h
        let f2 = lk_neg(c, w[0usize..m])
        w[k] = par[k]
        g[k] = (f1 - f2) / (2.0f64 * h)
        k += 1usize
    }
}

// zeroinfl (hurdle = false) or hurdle (true) with Poisson counts and a zero part under the link (0 logit, 1 probit, 2 cloglog, 3 cauchit): the count part is the exact fit of the logit
// model (it does not depend on the link for the hurdle), the zero part / zero-inflation parameters by BFGS from zero; par receives beta (p) then gamma (q); returns the log-likelihood
fn zero_link_fit(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, w: []const f64, off: []const f64, n: usize, p: usize, q: usize, link: usize, hurdle_model: bool, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    if p + q > 32usize { ret nan }
    if hurdle_model {
        let l0 = hurdle(a, x, z, y, n, p, q, par[0usize..p + q])
        if l0 != l0 { ret nan }
        // the truncated Poisson part is link-free: its log-likelihood is the hurdle total minus the logit zero part
        let (gr, e1) = mem.alloc[f64](a, q)
        let (hh, e2) = mem.alloc[f64](a, q * q)
        if e1 != ok || e2 != ok { ret nan }
        let lzl = lik(3usize, x, z, y, n, p, q, par[p..p + q], gr, hh, false)
        let lcount = l0 - lzl
        var c = LkCtx { x: x, z: z, y: y, n: n, p: p, q: q, link: link, part: 1usize, w: w, off: off }
        let (scr, e3) = mem.alloc[f64](a, q * q + 6usize * q)
        if e3 != ok { ret nan }
        var gam: [8]f64 = zero
        var round = 0usize
        while round < 2usize {
            let (r, e4) = opt.bfgs[LkCtx](&c, lk_neg, lk_grad, gam[0usize..q], 1.0e-9f64, 400u32, scr)
            let _ = r
            if e4 != ok { ret nan }
            round += 1usize
        }
        var j = 0usize
        while j < q {
            par[p + j] = gam[j]
            j += 1usize
        }
        ret lcount + lk_loglik(&c, gam[0usize..q])
    }
    let l0 = zeroinfl(a, x, z, y, n, p, q, par[0usize..p + q])
    if l0 != l0 { ret nan }
    var j = 0usize
    while j < q {
        par[p + j] = 0.0f64
        j += 1usize
    }
    var c = LkCtx { x: x, z: z, y: y, n: n, p: p, q: q, link: link, part: 0usize, w: w, off: off }
    let m = p + q
    let (scr, e5) = mem.alloc[f64](a, m * m + 6usize * m)
    if e5 != ok { ret nan }
    var round = 0usize
    while round < 3usize {
        let (r, e6) = opt.bfgs[LkCtx](&c, lk_neg, lk_grad, par[0usize..m], 1.0e-10f64, 500u32, scr)
        let _ = r
        if e6 != ok { ret nan }
        round += 1usize
    }
    ret lk_loglik(&c, par[0usize..m])
}
