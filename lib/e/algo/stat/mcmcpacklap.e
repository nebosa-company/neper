// R MCMCpack marginal.likelihood = "Laplace" of MCMClogit and MCMCpoisson: optim BFGS (numerical gradient, reltol sqrt(eps), 100 iterations) on the log posterior from the
// start, optimhess for the Hessian, then (p / 2) log(2 pi) + log(sqrt(det(Sigma))) + logpost(theta tilde) with Sigma = solve(-hessian). The log posterior is logpost.logit or
// logpost.poisson of BayesFactors.R (proper N(b0, inverse(B0)) prior, the dpois constant kept).

use e.algo.stat.mcmcpackmh as mh
use e.algo.stat.mcmcpacksamp as ms
use e.algo.stat.rbfgs as bf
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

type Ctx = struct { a: *mem.Arena, kind: usize, y: []const f64, x: []const f64, n: usize, k: usize, b0: []const f64, bb0: []const f64 }

fn logpost(c: *Ctx, th: []const f64) -> f64 {
    var ll = 0.0f64
    var t = 0usize
    while t < c.n {
        var eta = 0.0f64
        var i = 0usize
        while i < c.k {
            eta += c.x[t * c.k + i] * th[i]
            i += 1usize
        }
        if c.kind != 1usize {
            let p = 1.0f64 / (1.0f64 + math.exp[f64](-1.0f64 * eta))
            ll += c.y[t] * math.log[f64](p) + (1.0f64 - c.y[t]) * math.log[f64](1.0f64 - p)
        } else {
            ll += c.y[t] * eta - math.exp[f64](eta) - nm.lgammafn(c.y[t] + 1.0f64)
        }
        t += 1usize
    }
    if c.kind >= 2usize { ret ll + user_prior(c, th) }
    ret ll + ms.lndmvn_prec(c.a, th, c.b0, c.bb0, c.k)
}

// logpost.logit.userprior with the user density a product of independent marginals, locations in b0 and scales in the first k of bb0:
// kind 2 normal (logfun TRUE, sum of dnorm logs), 3 normal as a density (logfun FALSE, log of the product), 4 Cauchy (logfun TRUE)
fn user_prior(c: *Ctx, th: []const f64) -> f64 {
    var s = 0.0f64
    var pr = 1.0f64
    var i = 0usize
    while i < c.k {
        if c.kind == 2usize { s += dist.dnorm(th[i], c.b0[i], c.bb0[i], true) }
        if c.kind == 3usize { pr = pr * dist.dnorm(th[i], c.b0[i], c.bb0[i], false) }
        if c.kind == 4usize { s += dist.dcauchy(th[i], c.b0[i], c.bb0[i], true) }
        i += 1usize
    }
    if c.kind == 3usize { ret math.log[f64](pr) }
    ret s
}

fn fneg(c: *Ctx, th: []const f64) -> f64 { ret -1.0f64 * logpost(c, th) }

fn gneg(c: *Ctx, th: []const f64, g: []f64) {
    var x: [8]f64 = zero
    var i = 0usize
    while i < c.k {
        x[i] = th[i]
        i += 1usize
    }
    mh.num_grad[Ctx](c, fneg, x[0usize..c.k], g)
}

// kind 0 is logit, 1 is Poisson; at most 8 coefficients
fn laplace(a: *mem.Arena, kind: usize, y: []const f64, x: []const f64, n: usize, k: usize, b0: []const f64, bb0: []const f64, theta0: []const f64, ml: *f64) -> err {
    var c: Ctx = zero
    c.a = a
    c.kind = kind
    c.y = y
    c.x = x
    c.n = n
    c.k = k
    c.b0 = b0
    c.bb0 = bb0
    let (par, e1) = mem.alloc[f64](a, k)
    let (h, e2) = mem.alloc[f64](a, k * k)
    let (hi, e3) = mem.alloc[f64](a, k * k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < k {
        par[i] = theta0[i]
        i += 1usize
    }
    let _ = bf.vmmin[Ctx](a, &c, fneg, gneg, par, 1.4901161193847656e-8f64, 100usize)
    let eh = mh.num_hess[Ctx](a, &c, fneg, par, h)
    if eh != ok { ret eh }
    var ld = 0.0f64
    if ms.inv_pd(a, h, k, hi, &ld) != ok { ret ms.NotPd }
    *ml = (f64(k) / 2.0f64) * math.log[f64](2.0f64 * 3.141592653589793f64) - 0.5f64 * ld + logpost(&c, par)
    ret ok
}
