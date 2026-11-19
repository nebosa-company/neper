// R MASS fitdistr with the optimiser options: any subset of the parameters free (the others fixed through `...`),
// a user start, `lower` / `upper` bounds (L-BFGS-B), and the method chosen by the rules of MASS (bounds: L-BFGS-B,
// several free parameters: BFGS, one: Nelder-Mead) or forced. The standard errors come from optim's Hessian
// (optimHess, unbounded probes) inverted. Families: 0 gamma (shape, rate), 1 Weibull (shape, scale), 2 logistic
// (location, scale), 3 Cauchy (location, scale), 4 negative binomial (size, mu), 5 beta (shape1, shape2), 6 F (df1, df2),
// 7 chi-squared (df), 8 t (m, s, df).
//
// The default starting values are MASS's for gamma, Weibull, negative binomial, Cauchy, logistic and t.

use e.algo.stat.classint as ci
use e.algo.stat.lbfgsb as lb
use e.algo.stat.masscov as mc
use e.algo.stat.masslqs as lq
use e.algo.stat.rbfgs as bf
use e.algo.stat.rnm
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

error BadInput
error Failed

type GCtx = struct { x: []const f64, kind: usize, base: [3]f64, idx: [3]usize, nf: usize, ps: [3]f64, blo: [3]f64, bup: [3]f64, ud: fn(f64, []const f64) -> f64, ulog: bool }

fn no_dens(x: f64, p: []const f64) -> f64 { ret 0.0f64 }

fn nparams(kind: usize) -> usize {
    if kind == 7usize { ret 1usize }
    if kind == 8usize { ret 3usize }
    ret 2usize
}

fn gnll(c: *GCtx, p: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < c.x.len {
        let v = c.x[i]
        if c.kind == 0usize { s += nm.dgamma(v, p[0usize], 1.0f64 / p[1usize], true) }
        if c.kind == 1usize { s += dist.dweibull(v, p[0usize], p[1usize], true) }
        if c.kind == 2usize { s += dist.dlogis(v, p[0usize], p[1usize], true) }
        if c.kind == 3usize { s += dist.dcauchy(v, p[0usize], p[1usize], true) }
        if c.kind == 4usize { s += nb.dnbinom_mu(v, p[0usize], p[1usize], true) }
        if c.kind == 5usize { s += nb.dbeta(v, p[0usize], p[1usize], true) }
        if c.kind == 6usize { s += nb.df(v, p[0usize], p[1usize], true) }
        if c.kind == 7usize { s += nm.dchisq(v, p[0usize], true) }
        if c.kind == 9usize {
            if c.ulog { s += c.ud(v, p) } else { s += math.log[f64](c.ud(v, p)) }
        }
        if c.kind == 8usize { s += nb.dt((v - p[0usize]) / p[1usize], p[2usize], true) - math.log[f64](p[1usize]) }
        i += 1usize
    }
    ret 0.0f64 - s
}

fn gf(c: *GCtx, b: []const f64) -> f64 {
    var full: [3]f64 = c.base
    var j = 0usize
    while j < c.nf {
        full[c.idx[j]] = b[j] * c.ps[j]
        j += 1usize
    }
    ret gnll(c, full[0usize..3usize])
}

fn gg(c: *GCtx, b: []const f64, out: []f64) {
    let eps = 0.001f64
    var w: [3]f64 = zero
    var k = 0usize
    while k < c.nf {
        var j = 0usize
        while j < c.nf {
            w[j] = b[j]
            j += 1usize
        }
        w[k] = b[k] + eps
        let f1 = gf(c, w[0usize..c.nf])
        w[k] = b[k] - eps
        let f2 = gf(c, w[0usize..c.nf])
        out[k] = (f1 - f2) / (2.0f64 * eps)
        k += 1usize
    }
}

fn gg_bounded(c: *GCtx, b: []const f64, out: []f64) {
    // L-BFGS-B probes inside the (scaled) bounds
    var w: [3]f64 = zero
    var j = 0usize
    while j < c.nf {
        w[j] = b[j]
        j += 1usize
    }
    let _ = lb.lbfgsb_fd_gradient[GCtx](c, gf, w[0usize..c.nf], c.blo[0usize..c.nf], c.bup[0usize..c.nf], 0.001f64, out)
}

fn median_iqr(x: []const f64, med: *f64, iqr: *f64, a: *mem.Arena) -> err {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret e }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    lq.sortf(s)
    *med = ci.quantile_r(s, 0.5f64, 7u8)
    *iqr = ci.quantile_r(s, 0.75f64, 7u8) - ci.quantile_r(s, 0.25f64, 7u8)
    ret ok
}

// default starting values (MASS); returns the parscale first value for gamma through ps0
fn default_start(a: *mem.Arena, x: []const f64, kind: usize, st: []f64) -> err {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m /= n
    var v = 0.0f64
    i = 0usize
    while i < x.len {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    v /= n - 1.0f64
    if kind == 0usize {
        st[0usize] = m * m / v
        st[1usize] = m / v
    } else if kind == 1usize {
        var ml = 0.0f64
        i = 0usize
        while i < x.len {
            ml += math.log[f64](x[i])
            i += 1usize
        }
        ml /= n
        var vl = 0.0f64
        i = 0usize
        while i < x.len {
            vl += (math.log[f64](x[i]) - ml) * (math.log[f64](x[i]) - ml)
            i += 1usize
        }
        vl /= n - 1.0f64
        st[0usize] = 1.2f64 / math.sqrt[f64](vl)
        st[1usize] = math.exp[f64](ml + 0.572f64 / st[0usize])
    } else if kind == 4usize {
        st[0usize] = 100.0f64
        if v > m { st[0usize] = m * m / (v - m) }
        st[1usize] = m
    } else if kind == 2usize || kind == 3usize || kind == 8usize {
        var med = 0.0f64
        var iqr = 0.0f64
        let e = median_iqr(x, &med, &iqr, a)
        if e != ok { ret e }
        st[0usize] = med
        st[1usize] = iqr / 2.0f64
        if kind == 8usize { st[2usize] = 10.0f64 }
    } else { ret BadInput }
    ret ok
}

// fitdistr(x, family, ...). free[k] != 0 marks the parameters optimised; start (np values) holds the user's start, or is overwritten
// by the MASS default when use_start is false (fixed parameters always come from `fixed`). lower / upper are per free
// parameter (compact, +-1e308 for none) and read when bounded. method 0 by MASS's rule, 1 BFGS, 2 Nelder-Mead, 3 L-BFGS-B.
// out = est[nf], sd[nf], loglik, then vcov (nf by nf, column-major).
fn fitdistr(a: *mem.Arena, x: []const f64, kind: usize, free: []const f64, fixed: []const f64, start: []const f64, use_start: bool, bounded: bool, lower: []const f64, upper: []const f64, method: usize, out: []f64) -> err {
    ret fitdistr_core(a, x, kind, nparams(kind), no_dens, false, free, fixed, start, use_start, bounded, lower, upper, method, out)
}

// fitdistr(x, densfun, start, ...) with a user density: ud(x, parm) is the density (the log density when ulog, as a densfun with a log argument is called) of np (at most 3)
// parameters, all free; no parscale and no gradient, as MASS calls optim for a function densfun
fn fitdistr_user(a: *mem.Arena, x: []const f64, ud: fn(f64, []const f64) -> f64, ulog: bool, np: usize, start: []const f64, bounded: bool, lower: []const f64, upper: []const f64, method: usize, out: []f64) -> err {
    var free: [3]f64 = zero
    var fixed: [3]f64 = zero
    free[0usize] = 1.0f64
    free[1usize] = 1.0f64
    free[2usize] = 1.0f64
    ret fitdistr_core(a, x, 9usize, np, ud, ulog, free[0usize..3usize], fixed[0usize..3usize], start, true, bounded, lower, upper, method, out)
}

fn fitdistr_core(a: *mem.Arena, x: []const f64, kind: usize, np: usize, ud: fn(f64, []const f64) -> f64, ulog: bool, free: []const f64, fixed: []const f64, start: []const f64, use_start: bool, bounded: bool, lower: []const f64, upper: []const f64, method: usize, out: []f64) -> err {
    var c = GCtx { x: x, kind: kind, base: zero, idx: zero, nf: 0usize, ps: zero, blo: zero, bup: zero, ud: ud, ulog: ulog }
    var st: [3]f64 = zero
    if !use_start {
        let de = default_start(a, x, kind, st[0usize..3usize])
        if de != ok { ret de }
    } else {
        var k = 0usize
        while k < np {
            st[k] = start[k]
            k += 1usize
        }
    }
    var k = 0usize
    c.ps[0usize] = 1.0f64
    c.ps[1usize] = 1.0f64
    c.ps[2usize] = 1.0f64
    while k < np {
        if k < np && free[k] != 0.0f64 {
            c.idx[c.nf] = k
            c.nf += 1usize
        } else {
            c.base[k] = fixed[k]
        }
        k += 1usize
    }
    let nf = c.nf
    if nf == 0usize { ret BadInput }
    if kind == 0usize && !use_start {
        // control parscale = c(1, start$rate): only the shape/rate pair has a valid length
        if nf == 2usize { c.ps[1usize] = st[1usize] }
        if nf == 1usize && free[0usize] == 0.0f64 { ret BadInput }
    }
    let (b, e1) = mem.alloc[f64](a, nf)
    let (g1, e2) = mem.alloc[f64](a, nf)
    let (g2, e3) = mem.alloc[f64](a, nf)
    let (bb, e4) = mem.alloc[f64](a, nf)
    let (h, e5) = mem.alloc[f64](a, nf * nf)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var j = 0usize
    while j < nf {
        b[j] = st[c.idx[j]] / c.ps[j]
        c.blo[j] = lower[j] / c.ps[j]
        c.bup[j] = upper[j] / c.ps[j]
        j += 1usize
    }
    var meth = method
    if meth == 0usize {
        if bounded { meth = 3usize } else if nf > 1usize { meth = 1usize } else { meth = 2usize }
    }
    var fmin = 0.0f64
    if meth == 1usize {
        fmin = bf.vmmin[GCtx](a, &c, gf, gg, b, 1.4901161193847656e-08f64, 100usize)
    } else if meth == 2usize {
        let (fv, cnt, fail) = rnm.nmmin[GCtx](a, &c, gf, b, 0.0f64 - 1.0e308f64, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, bb)
        let _ = cnt
        if fail != 0usize { ret Failed }
        fmin = fv
        j = 0usize
        while j < nf {
            b[j] = bb[j]
            j += 1usize
        }
    } else {
        let (fv, fl) = lb.lbfgsb[GCtx](a, &c, gf, gg_bounded, b, c.blo[0usize..nf], c.bup[0usize..nf], 1.0e7f64, 0.0f64, 5usize, 100usize)
        if fl != 0i64 { ret Failed }
        fmin = fv
    }
    // optimHess: central differences of the (unbounded) gradient
    var r = 0usize
    while r < nf {
        let eps = 0.001f64 / c.ps[r]
        j = 0usize
        while j < nf {
            bb[j] = b[j]
            j += 1usize
        }
        bb[r] = b[r] + eps
        gg(&c, bb, g1)
        bb[r] = b[r] - eps
        gg(&c, bb, g2)
        var q = 0usize
        while q < nf {
            h[q * nf + r] = (g1[q] - g2[q]) / (2.0f64 * eps * c.ps[r] * c.ps[q])
            q += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < nf {
        var q = r + 1usize
        while q < nf {
            let o = 0.5f64 * (h[r * nf + q] + h[q * nf + r])
            h[r * nf + q] = o
            h[q * nf + r] = o
            q += 1usize
        }
        r += 1usize
    }
    let (vc, ve) = mc.inverse(a, h, nf)
    if ve != ok { ret ve }
    j = 0usize
    while j < nf {
        out[j] = b[j] * c.ps[j]
        out[nf + j] = math.sqrt[f64](vc[j * nf + j])
        j += 1usize
    }
    out[2usize * nf] = 0.0f64 - fmin
    j = 0usize
    while j < nf * nf {
        out[2usize * nf + 1usize + j] = vc[j]
        j += 1usize
    }
    ret ok
}
