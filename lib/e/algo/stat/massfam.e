// R MASS negative.binomial family pieces the fit does not need (validmu, valideta, initialize), rnegbin, and gamma.dispersion.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.mass as ms
use e.math
use e.mem

error BadInput

// negative.binomial(theta)$validmu: all(mu > 0)
fn nb_validmu(mu: []const f64) -> bool {
    var i = 0usize
    while i < mu.len {
        if !(mu[i] > 0.0f64) { ret false }
        i += 1usize
    }
    ret true
}

// valideta of make.link: log and identity accept every eta, sqrt wants finite positive values
fn nb_valideta(link: usize, eta: []const f64) -> bool {
    if link != 1usize { ret true }
    var i = 0usize
    while i < eta.len {
        if !(eta[i] - eta[i] == 0.0f64) || !(eta[i] > 0.0f64) { ret false }
        i += 1usize
    }
    ret true
}

// the family's initialize expression: mustart <- y + (y == 0) / 6
fn nb_mustart(y: f64) -> f64 {
    if y == 0.0f64 { ret y + 1.0f64 / 6.0f64 }
    ret y
}

// rnegbin(n, mu, theta): rpois(n, mu * rgamma(n, theta) / theta) with mu and theta recycled; the gammas are all drawn before the Poissons
fn rnegbin(a: *mem.Arena, r: *rng.Rng, n: usize, mu: []const f64, theta: []const f64, out: []f64) -> err {
    if mu.len == 0usize || theta.len == 0usize { ret BadInput }
    let (g, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        g[i] = rd.rgamma(r, theta[i % theta.len], 1.0f64)
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = rd.rpois(r, mu[i % mu.len] * g[i] / theta[i % theta.len])
        i += 1usize
    }
    ret ok
}

// gamma.dispersion: 1 / gamma.shape()$alpha
fn gamma_dispersion(y: []const f64, u: []const f64, aw: []const f64, deviance: f64, dfres: f64, itlim: usize, epsmax: f64) -> f64 {
    var out: [2]f64 = zero
    ms.gamma_shape_ex(y, u, aw, deviance, dfres, itlim, epsmax, out[0usize..2usize])
    ret 1.0f64 / out[0usize]
}
