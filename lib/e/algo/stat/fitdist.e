// R MASS fitdistr for the families fitted by optim: gamma and Weibull and the logistic and Cauchy (two parameters each, so optim's BFGS with its central-difference gradient, step 1e-3, and `optimHess` for the standard errors).
// Starting values, the gamma parscale and the Hessian follow MASS. out = (est1, est2, sd1, sd2, loglik).
//
// Not here: the one-parameter families (Nelder-Mead), the t and negative binomial, and `lower` / `upper` bounds (L-BFGS-B).

use e.algo.stat.rbfgs as bf
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

type FdCtx = struct { x: []const f64, kind: usize, ps1: f64, ps2: f64 }

// the negative log likelihood at the real parameters
fn fd_nll(c: *FdCtx, p1: f64, p2: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < c.x.len {
        if c.kind == 0usize { s += nm.dgamma(c.x[i], p1, 1.0f64 / p2, true) }
        if c.kind == 1usize { s += dist.dweibull(c.x[i], p1, p2, true) }
        if c.kind == 2usize { s += dist.dlogis(c.x[i], p1, p2, true) }
        if c.kind == 3usize { s += dist.dcauchy(c.x[i], p1, p2, true) }
        i += 1usize
    }
    ret 0.0f64 - s
}

// the objective on optim's scaled parameters
fn fd_f(c: *FdCtx, b: []const f64) -> f64 { ret fd_nll(c, b[0usize] * c.ps1, b[1usize] * c.ps2) }

// optim's numerical gradient on the scaled parameters
fn fd_g(c: *FdCtx, b: []const f64, out: []f64) {
    let eps = 0.001f64
    out[0usize] = (fd_nll(c, (b[0usize] + eps) * c.ps1, b[1usize] * c.ps2) - fd_nll(c, (b[0usize] - eps) * c.ps1, b[1usize] * c.ps2)) / (2.0f64 * eps)
    out[1usize] = (fd_nll(c, b[0usize] * c.ps1, (b[1usize] + eps) * c.ps2) - fd_nll(c, b[0usize] * c.ps1, (b[1usize] - eps) * c.ps2)) / (2.0f64 * eps)
}

fn q7(s: []const f64, p: f64) -> f64 {
    let h = (f64(s.len) - 1.0f64) * p
    let lo = math.floor[f64](h)
    let hi = math.ceil[f64](h)
    let q = s[usize(lo)]
    if hi > lo { ret q + (h - lo) * (s[usize(hi)] - q) }
    ret q
}

// kind 0 gamma (shape, rate), 1 Weibull (shape, scale), 2 logistic (location, scale), 3 Cauchy (location, scale)
fn fitdistr2(a: *mem.Arena, x: []const f64, kind: usize, out: []f64) -> err {
    let n = x.len
    let nf = f64(n)
    let (b, e1) = mem.alloc[f64](a, 2usize)
    let (sorted, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret e1 }
    var i = 0usize
    var m = 0.0f64
    while i < n {
        m += x[i]
        sorted[i] = x[i]
        i += 1usize
    }
    m = m / nf
    var v = 0.0f64
    i = 0usize
    while i < n {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    v = v / (nf - 1.0f64)
    i = 1usize
    while i < n {
        let key = sorted[i]
        var j = i
        while j > 0usize && sorted[j - 1usize] > key {
            sorted[j] = sorted[j - 1usize]
            j -= 1usize
        }
        sorted[j] = key
        i += 1usize
    }
    var c = FdCtx{ x: x, kind: kind, ps1: 1.0f64, ps2: 1.0f64 }
    var s1 = 0.0f64
    var s2 = 0.0f64
    if kind == 0usize {
        s1 = m * m / v
        s2 = m / v
        c.ps2 = s2
    } else if kind == 1usize {
        var ml = 0.0f64
        i = 0usize
        while i < n {
            ml += math.log[f64](x[i])
            i += 1usize
        }
        ml = ml / nf
        var vl = 0.0f64
        i = 0usize
        while i < n {
            vl += (math.log[f64](x[i]) - ml) * (math.log[f64](x[i]) - ml)
            i += 1usize
        }
        vl = vl / (nf - 1.0f64)
        s1 = 1.2f64 / math.sqrt[f64](vl)
        s2 = math.exp[f64](ml + 0.572f64 / s1)
    } else {
        s1 = q7(sorted, 0.5f64)
        s2 = (q7(sorted, 0.75f64) - q7(sorted, 0.25f64)) / 2.0f64
    }
    b[0usize] = s1 / c.ps1
    b[1usize] = s2 / c.ps2
    let fmin = bf.vmmin[FdCtx](a, &c, fd_f, fd_g, b, 1.4901161193847656e-08f64, 100usize)
    // optimHess on the scaled parameters
    let (h, e3) = mem.alloc[f64](a, 4usize)
    let (g1, e4) = mem.alloc[f64](a, 2usize)
    let (g2, e5) = mem.alloc[f64](a, 2usize)
    let (bb, e6) = mem.alloc[f64](a, 2usize)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e3 }
    let (ps, e7) = mem.alloc[f64](a, 2usize)
    if e7 != ok { ret e7 }
    ps[0usize] = c.ps1
    ps[1usize] = c.ps2
    var r = 0usize
    while r < 2usize {
        let eps = 0.001f64 / ps[r]
        bb[0usize] = b[0usize]
        bb[1usize] = b[1usize]
        bb[r] = b[r] + eps
        fd_g(&c, bb, g1)
        bb[r] = b[r] - eps
        fd_g(&c, bb, g2)
        var q = 0usize
        while q < 2usize {
            h[q * 2usize + r] = (g1[q] - g2[q]) / (2.0f64 * eps * ps[r] * ps[q])
            q += 1usize
        }
        r += 1usize
    }
    let off = 0.5f64 * (h[1usize] + h[2usize])
    h[1usize] = off
    h[2usize] = off
    let det = h[0usize] * h[3usize] - off * off
    out[0usize] = b[0usize] * c.ps1
    out[1usize] = b[1usize] * c.ps2
    out[2usize] = math.sqrt[f64](h[3usize] / det)
    out[3usize] = math.sqrt[f64](h[0usize] / det)
    out[4usize] = 0.0f64 - fmin
    ret ok
}
