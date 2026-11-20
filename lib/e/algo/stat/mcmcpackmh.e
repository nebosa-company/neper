// R MCMCpack::MCMCmetrop1R: random-walk Metropolis sampling of a user density (or log density) with proposal covariance diag(tune) V diag(tune),
// on the Scythe Mersenne-Twister stream.
//
// default_v is R's V = solve(-hessian) at the mode from optim BFGS (numerical gradient and Hessian, reltol sqrt(eps), maxit 500); the caller hands over the negative log density and its
// central-difference gradient (num_grad of it).


use e.algo.stat.mcmcpacksamp as ms
use e.algo.stat.rbfgs as bf
use e.math
use e.mem

// f(ctx, theta) is the user function; with logfun false it is a density. out is nsamp rows of theta
fn metrop1r[Ctx: type](a: *mem.Arena, g: *ms.Sc, c: *Ctx, f: fn(*Ctx, []const f64) -> f64, theta0: []const f64, v: []const f64, tune: []const f64, logfun: bool, burnin: usize, mcmc: usize, thin: usize, out: []f64) -> err {
    let np = theta0.len
    let (th, e1) = mem.alloc[f64](a, np)
    let (can, e2) = mem.alloc[f64](a, np)
    let (ve, e3) = mem.alloc[f64](a, np * np)
    let (pc, e4) = mem.alloc[f64](a, np * np)
    let (zz, e5) = mem.alloc[f64](a, np)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var i = 0usize
    var j = 0usize
    while i < np {
        th[i] = theta0[i]
        j = 0usize
        while j < np {
            ve[i * np + j] = tune[i] * v[i * np + j] * tune[j]
            j += 1usize
        }
        i += 1usize
    }
    if !ms.chol(ve, np, pc) { ret ms.NotPd }
    var cur = f(c, th)
    if !logfun { cur = math.log[f64](cur) }
    var count = 0usize
    var iter = 0usize
    while iter < burnin + mcmc {
        i = 0usize
        while i < np {
            zz[i] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < np {
            var s = th[i]
            j = 0usize
            while j <= i {
                s += pc[i * np + j] * zz[j]
                j += 1usize
            }
            can[i] = s
            i += 1usize
        }
        var fc = f(c, can)
        if !logfun { fc = math.log[f64](fc) }
        if ms.sc_unif(g) < math.exp[f64](fc - cur) {
            i = 0usize
            while i < np {
                th[i] = can[i]
                i += 1usize
            }
            cur = fc
        }
        if iter % thin == 0usize && iter >= burnin {
            i = 0usize
            while i < np {
                out[count * np + i] = th[i]
                i += 1usize
            }
            count += 1usize
        }
        iter += 1usize
    }
    ret ok
}

// v is np by np: solve of the Hessian of fneg at the minimiser found by BFGS from theta0
fn default_v[Ctx: type](a: *mem.Arena, c: *Ctx, fneg: fn(*Ctx, []const f64) -> f64, gneg: fn(*Ctx, []const f64, []f64), theta0: []const f64, v: []f64) -> err {
    let np = theta0.len
    let (par, e1) = mem.alloc[f64](a, np)
    let (h, e2) = mem.alloc[f64](a, np * np)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < np {
        par[i] = theta0[i]
        i += 1usize
    }
    let _ = bf.vmmin[Ctx](a, c, fneg, gneg, par, 1.4901161193847656e-8f64, 500usize)
    let eh = num_hess[Ctx](a, c, fneg, par, h)
    if eh != ok { ret eh }
    var ld = 0.0f64
    if ms.inv_pd(a, h, np, v, &ld) != ok { ret ms.NotPd }
    ret ok
}

// optim's numerical gradient: central differences with step 1e-3 (x is changed and restored)
fn num_grad[Ctx: type](c: *Ctx, f: fn(*Ctx, []const f64) -> f64, x: []f64, g: []f64) {
    let np = x.len
    var j = 0usize
    while j < np {
        let keep = x[j]
        x[j] = keep + 0.001f64
        let v1 = f(c, x)
        x[j] = keep - 0.001f64
        let v2 = f(c, x)
        x[j] = keep
        g[j] = (v1 - v2) / 0.002f64
        j += 1usize
    }
}

// optimhess: central differences of the gradient, symmetrised; h is np by np row-major
fn num_hess[Ctx: type](a: *mem.Arena, c: *Ctx, f: fn(*Ctx, []const f64) -> f64, par: []const f64, h: []f64) -> err {
    let np = par.len
    let (x, e1) = mem.alloc[f64](a, np)
    let (g1, e2) = mem.alloc[f64](a, np)
    let (g2, e3) = mem.alloc[f64](a, np)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < np {
        var k = 0usize
        while k < np {
            x[k] = par[k]
            k += 1usize
        }
        x[i] = par[i] + 0.001f64
        num_grad[Ctx](c, f, x, g1)
        x[i] = par[i] - 0.001f64
        num_grad[Ctx](c, f, x, g2)
        k = 0usize
        while k < np {
            h[i * np + k] = (g1[k] - g2[k]) / 0.002f64
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < np {
        var k = 0usize
        while k < i {
            let m = 0.5f64 * (h[i * np + k] + h[k * np + i])
            h[i * np + k] = m
            h[k * np + i] = m
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}
