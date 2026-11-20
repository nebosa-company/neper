// R MCMCpack: the probit sampler (Albert-Chib augmentation through Scythe's truncated normals) and the R-level draws rwish, riwish and rdirichlet.
// Sampler streams are the Scythe Mersenne-Twister of e.algo.stat.mcmcpacksamp; rwish, riwish and rdirichlet use R's own generator, as the package does.
//
// Not here: the other MCMCpack samplers.

use e.algo.rand.r as rng
use e.algo.stat.mcmcpacksamp as ms
use e.math
use e.math.dist as dist
use e.mem

// Scythe's qnorm1: the Odeh-Evans rational approximation (good to about 1e-7), not R's qnorm
fn qnorm1(in_p: f64) -> f64 {
    var p = in_p
    if p > 0.5f64 { p = 1.0f64 - p }
    if p == 0.5f64 { ret 0.0f64 }
    let y = math.sqrt[f64](math.log[f64](1.0f64 / math.pow[f64](p, 2.0f64)))
    var xp = y + ((((y * (0.0f64 - 0.453642210148e-4f64) + (0.0f64 - 0.0204231210245f64)) * y + (0.0f64 - 0.342242088547f64)) * y + (0.0f64 - 1.0f64)) * y + (0.0f64 - 0.322232431088f64)) / ((((y * 0.38560700634e-2f64 + 0.103537752850f64) * y + 0.531103462366f64) * y + 0.588581570495f64) * y + 0.0993484626060f64)
    if in_p < 0.5f64 { xp = 0.0f64 - xp }
    ret xp
}

fn pnorm1(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }

fn is_finite(x: f64) -> bool { ret x - x == 0.0f64 }

// Scythe's rtnorm: inversion of the truncated normal through pnorm1 and qnorm1
fn rtnorm(r: *ms.Sc, mean: f64, variance: f64, below: f64, above: f64) -> f64 {
    let sd = math.sqrt[f64](variance)
    var fa = 0.0f64
    var fb = 0.0f64
    let za = (above - mean) / sd
    let zb = (below - mean) / sd
    if math.abs[f64](za) < 8.2f64 && math.abs[f64](zb) < 8.2f64 {
        fa = pnorm1(za)
        fb = pnorm1(zb)
    }
    if za < 8.2f64 && zb <= -8.2f64 {
        fa = pnorm1(za)
        fb = 0.0f64
    }
    if za >= 8.2f64 && zb > -8.2f64 {
        fa = 1.0f64
        fb = pnorm1(zb)
    }
    if za >= 8.2f64 && zb <= -8.2f64 {
        fa = 1.0f64
        fb = 0.0f64
    }
    var term = ms.sc_unif(r) * (fa - fb) + fb
    if term < 5.6e-17f64 { term = 5.6e-17f64 }
    if term > 1.0f64 - 5.6e-17f64 { term = 1.0f64 - 5.6e-17f64 }
    var draw = mean + sd * qnorm1(term)
    if draw > above { draw = above }
    if draw < below { draw = below }
    ret draw
}

// rtbnorm_combo(mean, variance, below, 10): normal truncated below
fn rtbnorm_combo(r: *ms.Sc, mean: f64, variance: f64, below: f64) -> f64 {
    let s = math.sqrt[f64](variance)
    if mean / s - below / s > -0.5f64 {
        var x = ms.sc_rnorm(r, mean, s)
        while x < below { x = ms.sc_rnorm(r, mean, s) }
        ret x
    }
    if mean / s - below / s > -5.0f64 {
        ret rtnorm(r, mean, variance, below, 1.0f64 / 0.0f64)
    }
    var x = below + 0.00001f64
    var i = 0usize
    while i < 10usize {
        let z = ms.sc_unif(r) * math.exp[f64](-1.0f64 * math.pow[f64](x - mean, 2.0f64) / (2.0f64 * variance))
        x = ms.sc_unif(r) * ((mean + math.sqrt[f64](-2.0f64 * variance * math.log[f64](z))) - below) + below
        i += 1usize
    }
    if !is_finite(x) { ret below }
    ret x
}

// rtanorm_combo(mean, variance, above, 10): normal truncated above
fn rtanorm_combo(r: *ms.Sc, mean: f64, variance: f64, above: f64) -> f64 {
    let s = math.sqrt[f64](variance)
    if mean / s - above / s < 0.5f64 {
        var x = ms.sc_rnorm(r, mean, s)
        while x > above { x = ms.sc_rnorm(r, mean, s) }
        ret x
    }
    if mean / s - above / s < 5.0f64 {
        ret rtnorm(r, mean, variance, -1.0f64 / 0.0f64, above)
    }
    let below = -1.0f64 * above
    let newmu = -1.0f64 * mean
    var x = below + 0.00001f64
    var i = 0usize
    while i < 10usize {
        let z = ms.sc_unif(r) * math.exp[f64](-1.0f64 * math.pow[f64](x - newmu, 2.0f64) / (2.0f64 * variance))
        x = ms.sc_unif(r) * ((newmu + math.sqrt[f64](-2.0f64 * variance * math.log[f64](z))) - below) + below
        i += 1usize
    }
    if !is_finite(x) { ret above }
    ret -1.0f64 * x
}

// MCMCprobit with the N(b0, inverse(B0)) prior: out is nstore rows of beta; ml gets the Chib log marginal likelihood when chib
fn probit(a: *mem.Arena, g: *ms.Sc, y: []const f64, x: []const f64, n: usize, k: usize, beta0: []const f64, b0: []const f64, bb0: []const f64, burnin: usize, mcmc: usize, thin: usize, chib: bool, out: []f64, ml: *f64) -> err {
    let nstore = mcmc / thin
    let (m1, e2) = mem.alloc[f64](a, k * k)
    let (bn_var, e3) = mem.alloc[f64](a, k * k)
    let (cc, e4) = mem.alloc[f64](a, k * k)
    let (beta, e5) = mem.alloc[f64](a, k)
    let (zv, e6) = mem.alloc[f64](a, n)
    let (rhs, e7) = mem.alloc[f64](a, k)
    let (bn, e8) = mem.alloc[f64](a, k)
    let (zz, e9) = mem.alloc[f64](a, k)
    let (bns, e10) = mem.alloc[f64](a, nstore * k)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += x[t * k + i] * x[t * k + j]
                t += 1usize
            }
            m1[i * k + j] = bb0[i * k + j] + s
            j += 1usize
        }
        beta[i] = beta0[i]
        i += 1usize
    }
    var ld = 0.0f64
    if ms.inv_pd(a, m1, k, bn_var, &ld) != ok { ret ms.NotPd }
    if !ms.chol(bn_var, k, cc) { ret ms.NotPd }
    var count = 0usize
    var iter = 0usize
    while iter < burnin + mcmc {
        var t = 0usize
        while t < n {
            var eta = 0.0f64
            i = 0usize
            while i < k {
                eta += x[t * k + i] * beta[i]
                i += 1usize
            }
            if y[t] == 1.0f64 { zv[t] = rtbnorm_combo(g, eta, 1.0f64, 0.0f64) }
            if y[t] == 0.0f64 { zv[t] = rtanorm_combo(g, eta, 1.0f64, 0.0f64) }
            t += 1usize
        }
        i = 0usize
        while i < k {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += bb0[i * k + j] * b0[j]
                j += 1usize
            }
            t = 0usize
            while t < n {
                s += x[t * k + i] * zv[t]
                t += 1usize
            }
            rhs[i] = s
            i += 1usize
        }
        i = 0usize
        while i < k {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += bn_var[i * k + j] * rhs[j]
                j += 1usize
            }
            bn[i] = s
            zz[i] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < k {
            var s = bn[i]
            var j = 0usize
            while j <= i {
                s += cc[i * k + j] * zz[j]
                j += 1usize
            }
            beta[i] = s
            i += 1usize
        }
        if iter >= burnin && iter % thin == 0usize {
            i = 0usize
            while i < k {
                out[count * k + i] = beta[i]
                bns[count * k + i] = bn[i]
                i += 1usize
            }
            count += 1usize
        }
        iter += 1usize
    }
    if chib {
        let (bstar, e11) = mem.alloc[f64](a, k)
        if e11 != ok { ret e11 }
        i = 0usize
        while i < k {
            var s = 0.0f64
            var q = 0usize
            while q < nstore {
                s += out[q * k + i]
                q += 1usize
            }
            bstar[i] = s / f64(nstore)
            i += 1usize
        }
        var dsum = 0.0f64
        var q = 0usize
        while q < nstore {
            dsum += math.exp[f64](ms.lndmvn_prec(a, bstar, bns[q * k..q * k + k], m1, k))
            q += 1usize
        }
        var logbeta = math.log[f64](dsum / f64(nstore))
        // Scythe's lndmvn is NaN for a 1 by 1 matrix, and this density is taken through it for every k
        if k == 1usize { logbeta = 0.0f64 / 0.0f64 }
        var ll = 0.0f64
        var t = 0usize
        while t < n {
            var eta = 0.0f64
            i = 0usize
            while i < k {
                eta += x[t * k + i] * bstar[i]
                i += 1usize
            }
            let phi = pnorm1(eta)
            if y[t] == 1.0f64 { ll += math.log[f64](phi) } else { ll += math.log[f64](1.0f64 - phi) }
            t += 1usize
        }
        var lp = 0.0f64
        if k == 1usize { lp = ms.lndnorm(bstar[0usize], b0[0usize], 1.0f64 / math.sqrt[f64](bb0[0usize])) } else { lp = ms.lndmvn_prec(a, bstar, b0, bb0, k) }
        *ml = ll + lp - logbeta
    }
    ret ok
}

// R's rgamma with the Ahrens-Dieter GS branch for a shape below 1 (e.algo.rand.r.rgamma covers a >= 1)
fn rgamma(g: *rng.Rng, a: f64, scale: f64) -> f64 {
    if a >= 1.0f64 { ret rng.rgamma(g, a, scale) }
    let e = 1.0f64 + 0.36787944117144233f64 * a
    while true {
        let p = e * rng.unif(g)
        if p >= 1.0f64 {
            let x = 0.0f64 - math.log[f64]((e - p) / a)
            if rng.exp_unit(g) >= (1.0f64 - a) * math.log[f64](x) { ret scale * x }
        } else {
            let x = math.exp[f64](math.log[f64](p) / a)
            if rng.exp_unit(g) >= x { ret scale * x }
        }
    }
    ret 0.0f64
}

// rwish(v, S) of MCMCpack's R code under R's generator: the Bartlett factor Z (chi-square roots on the diagonal, normals above) times chol(S), cross-product; out is p by p row-major
fn rwish(a: *mem.Arena, g: *rng.Rng, v: f64, s: []const f64, p: usize, out: []f64) -> err {
    let (l, e1) = mem.alloc[f64](a, p * p)
    let (z, e2) = mem.alloc[f64](a, p * p)
    let (m, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if !ms.chol(s, p, l) { ret ms.NotPd }
    var i = 0usize
    while i < p * p {
        z[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        z[i * p + i] = math.sqrt[f64](rgamma(g, (v - f64(i)) / 2.0f64, 2.0f64))
        i += 1usize
    }
    var j = 1usize
    while j < p {
        i = 0usize
        while i < j {
            z[i * p + j] = rng.norm(g)
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < p {
        j = 0usize
        while j < p {
            var acc = 0.0f64
            var k = 0usize
            while k < p {
                acc += z[i * p + k] * l[j * p + k]
                k += 1usize
            }
            m[i * p + j] = acc
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        j = 0usize
        while j < p {
            var acc = 0.0f64
            var k = 0usize
            while k < p {
                acc += m[k * p + i] * m[k * p + j]
                k += 1usize
            }
            out[i * p + j] = acc
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// riwish(v, S) = solve(rwish(v, solve(S)))
fn riwish(a: *mem.Arena, g: *rng.Rng, v: f64, s: []const f64, p: usize, out: []f64) -> err {
    let (si, e1) = mem.alloc[f64](a, p * p)
    let (w, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var ld = 0.0f64
    if ms.inv_pd(a, s, p, si, &ld) != ok { ret ms.NotPd }
    let e3 = rwish(a, g, v, si, p, w)
    if e3 != ok { ret e3 }
    ret ms.inv_pd(a, w, p, out, &ld)
}

// rdirichlet(n, alpha): n rows of l gamma draws (shape alpha[j], scale 1) in stream order, each row divided by its sum; out is n by l row-major
fn rdirichlet(g: *rng.Rng, n: usize, alpha: []const f64, out: []f64) {
    let l = alpha.len
    var i = 0usize
    while i < n {
        var sm = 0.0f64
        var j = 0usize
        while j < l {
            let d = rgamma(g, alpha[j], 1.0f64)
            out[i * l + j] = d
            sm += d
            j += 1usize
        }
        j = 0usize
        while j < l {
            out[i * l + j] = out[i * l + j] / sm
            j += 1usize
        }
        i += 1usize
    }
}
