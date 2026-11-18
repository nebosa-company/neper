// R gamlss.dist: the density of the Gumbel (GU), logistic (LO), gamma (GA), inverse Gaussian (IG), Box-Cox Cole-Green (BCCG), power exponential (PE), Weibull (WEI), log-normal (LOGNO),
// negative binomial (NBI), zero-inflated Poisson (ZIP), Johnson SU (JSU), sinh-arcsinh (SHASH) and Box-Cox t (BCT) families
// in the package's (mu, sigma, nu) parametrization, and the distribution and quantile functions of GU and LO.
//
// Not here: the other 90-odd families, p and q for the rest, random numbers, moments and the link functions.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.special as sp

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

fn dgu(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let z = (x - mu) / sigma
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) + z - math.exp[f64](z))
}

fn pgu(x: f64, mu: f64, sigma: f64) -> f64 { ret 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64]((x - mu) / sigma)) }

fn qgu(p: f64, mu: f64, sigma: f64) -> f64 { ret mu + sigma * math.log[f64](0.0f64 - math.log[f64](1.0f64 - p)) }

fn dlo(x: f64, mu: f64, sigma: f64) -> f64 {
    let e = math.exp[f64](0.0f64 - (x - mu) / sigma)
    ret e / (sigma * (1.0f64 + e) * (1.0f64 + e))
}

fn plo(x: f64, mu: f64, sigma: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - (x - mu) / sigma)) }

fn qlo(p: f64, mu: f64, sigma: f64) -> f64 { ret mu + sigma * math.log[f64](p / (1.0f64 - p)) }

fn dga(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let s2 = sigma * sigma
    ret math.exp[f64]((1.0f64 / s2) * math.log[f64](x / (mu * s2)) - x / (mu * s2) - math.log[f64](x) - sp.lgamma(1.0f64 / s2))
}

fn dig(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](0.0f64 - 0.5f64 * math.log[f64](2.0f64 * pi()) - math.log[f64](sigma) - 1.5f64 * math.log[f64](x) - (x - mu) * (x - mu) / (2.0f64 * sigma * sigma * mu * mu * x))
}

fn dbccg(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    var z = 0.0f64
    if nu != 0.0f64 { z = (math.pow[f64](x / mu, nu) - 1.0f64) / (nu * sigma) } else { z = math.log[f64](x / mu) / sigma }
    var ll = nu * math.log[f64](x / mu) - math.log[f64](sigma) - z * z / 2.0f64 - math.log[f64](x) - math.log[f64](2.0f64 * pi()) / 2.0f64
    ll = ll - math.log[f64](dist.pnorm(1.0f64 / (sigma * math.abs[f64](nu)), 0.0f64, 1.0f64, true, false))
    ret math.exp[f64](ll)
}

fn dpe(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    let log_c = 0.5f64 * (0.0f64 - (2.0f64 / nu) * math.log[f64](2.0f64) + sp.lgamma(1.0f64 / nu) - sp.lgamma(3.0f64 / nu))
    let c = math.exp[f64](log_c)
    let z = (x - mu) / sigma
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) + math.log[f64](nu) - log_c - 0.5f64 * math.pow[f64](math.abs[f64](z / c), nu) - (1.0f64 + 1.0f64 / nu) * math.log[f64](2.0f64) - sp.lgamma(1.0f64 / nu))
}

fn asinh_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - math.log[f64](0.0f64 - x + math.sqrt[f64](x * x + 1.0f64)) }
    ret math.log[f64](x + math.sqrt[f64](x * x + 1.0f64))
}

fn sinh_of(x: f64) -> f64 { ret (math.exp[f64](x) - math.exp[f64](0.0f64 - x)) / 2.0f64 }

fn cosh_of(x: f64) -> f64 { ret (math.exp[f64](x) + math.exp[f64](0.0f64 - x)) / 2.0f64 }

// the negative binomial with mean mu and variance mu + sigma mu^2
fn dnbi(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let size = 1.0f64 / sigma
    ret math.exp[f64](sp.lgamma(x + size) - sp.lgamma(size) - sp.lgamma(x + 1.0f64) + size * math.log[f64](size / (size + mu)) + x * math.log[f64](mu / (size + mu)))
}

// the zero-inflated Poisson with zero mass sigma
fn dzip(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret sigma + (1.0f64 - sigma) * math.exp[f64](0.0f64 - mu) }
    ret math.exp[f64](math.log[f64](1.0f64 - sigma) - mu + x * math.log[f64](mu) - sp.lgamma(x + 1.0f64))
}

fn dwei(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let z = x / mu
    ret sigma / mu * math.pow[f64](z, sigma - 1.0f64) * math.exp[f64](0.0f64 - math.pow[f64](z, sigma))
}

fn dlogno(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let z = (math.log[f64](x) - mu) / sigma
    ret math.exp[f64](0.0f64 - z * z / 2.0f64) / (x * sigma * math.sqrt[f64](2.0f64 * pi()))
}

// the Johnson SU family in the package's parametrization (tau is the tail parameter)
fn djsu(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let rtau = 1.0f64 / tau
    var w = 1.0f64
    if rtau >= 1.0e-7f64 { w = math.exp[f64](rtau * rtau) }
    let omega = 0.0f64 - nu * rtau
    let c = math.pow[f64](0.5f64 * (w - 1.0f64) * (w * cosh_of(2.0f64 * omega) + 1.0f64), 0.0f64 - 0.5f64)
    let z = (x - (mu + c * sigma * math.sqrt[f64](w) * sinh_of(omega))) / (c * sigma)
    let r = 0.0f64 - nu + asinh_of(z) / rtau
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) - math.log[f64](c) - math.log[f64](rtau) - 0.5f64 * math.log[f64](z * z + 1.0f64) - 0.5f64 * math.log[f64](2.0f64 * pi()) - 0.5f64 * r * r)
}

fn dshash(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    let a = asinh_of(z)
    let r = 0.5f64 * (math.exp[f64](tau * a) - math.exp[f64](0.0f64 - nu * a))
    let c = 0.5f64 * (tau * math.exp[f64](tau * a) + nu * math.exp[f64](0.0f64 - nu * a))
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) - math.log[f64](2.0f64 * pi()) / 2.0f64 - math.log[f64](1.0f64 + z * z) / 2.0f64 + math.log[f64](c) - r * r / 2.0f64)
}

// the Box-Cox t
fn dbct(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    var z = 0.0f64
    if nu != 0.0f64 { z = (math.pow[f64](x / mu, nu) - 1.0f64) / (nu * sigma) } else { z = math.log[f64](x / mu) / sigma }
    var ll = (nu - 1.0f64) * math.log[f64](x) - nu * math.log[f64](mu) - math.log[f64](sigma)
    var ft = sp.lgamma((tau + 1.0f64) / 2.0f64) - sp.lgamma(tau / 2.0f64) - 0.5f64 * math.log[f64](tau) - sp.lgamma(0.5f64)
    ft = ft - ((tau + 1.0f64) / 2.0f64) * math.log[f64](1.0f64 + z * z / tau)
    ll = ll + ft - math.log[f64](nb.pt(1.0f64 / (sigma * math.abs[f64](nu)), tau, true, false))
    ret math.exp[f64](ll)
}

// the exponential family EXP of gamlss.dist with mean mu: density (1 / mu) exp(-x / mu) for x > 0, distribution 1 - exp(-x / mu), quantile -mu log(1 - p)
fn dexp_mu(x: f64, mu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](0.0f64 - x / mu) / mu
}

fn pexp_mu(x: f64, mu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 1.0f64 - math.exp[f64](0.0f64 - x / mu)
}

fn qexp_mu(p: f64, mu: f64) -> f64 { ret 0.0f64 - mu * math.log[f64](1.0f64 - p) }

// the reverse Gumbel RG of gamlss.dist: density exp(-z - exp(-z)) / sigma with z = (x - mu) / sigma, distribution exp(-exp(-z)), quantile mu - sigma log(-log p)
fn drg(x: f64, mu: f64, sigma: f64) -> f64 {
    let z = (x - mu) / sigma
    ret math.exp[f64](0.0f64 - z - math.exp[f64](0.0f64 - z)) / sigma
}

fn prg(x: f64, mu: f64, sigma: f64) -> f64 {
    let z = (x - mu) / sigma
    ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - z))
}

fn qrg(p: f64, mu: f64, sigma: f64) -> f64 { ret mu - sigma * math.log[f64](0.0f64 - math.log[f64](p)) }

// the Pareto type II PARETO2 of gamlss.dist (scale mu, shape sigma): density exp(-log sigma + log(mu) / sigma - (1 / sigma + 1) log(x + mu)) for x > 0,
// distribution 1 - (mu / (mu + x))^(1 / sigma), quantile mu ((1 - p)^(-sigma) - 1)
fn dpareto2(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) + math.log[f64](mu) / sigma - (1.0f64 / sigma + 1.0f64) * math.log[f64](x + mu))
}

fn ppareto2(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 1.0f64 - math.pow[f64](mu / (mu + x), 1.0f64 / sigma)
}

fn qpareto2(p: f64, mu: f64, sigma: f64) -> f64 { ret mu * (math.pow[f64](1.0f64 - p, 0.0f64 - sigma) - 1.0f64) }

// the Pareto type I PARETO1 of gamlss.dist (shape mu): density mu (1 + x)^(-mu - 1) for x > 0, distribution 1 - (1 + x)^(-mu), quantile (1 - p)^(-1 / mu) - 1
fn dpareto1(x: f64, mu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](math.log[f64](mu) - (mu + 1.0f64) * math.log[f64](1.0f64 + x))
}

fn ppareto1(x: f64, mu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 1.0f64 - math.pow[f64](1.0f64 + x, 0.0f64 - mu)
}

fn qpareto1(p: f64, mu: f64) -> f64 { ret math.pow[f64](1.0f64 - p, 0.0f64 - 1.0f64 / mu) - 1.0f64 }

// the normal family NO of gamlss.dist (mean mu, sd sigma): dnorm, pnorm and qnorm of the base distribution
fn dno(x: f64, mu: f64, sigma: f64) -> f64 { ret dist.dnorm(x, mu, sigma, false) }

fn pno(x: f64, mu: f64, sigma: f64) -> f64 { ret dist.pnorm(x, mu, sigma, true, false) }

fn qno(p: f64, mu: f64, sigma: f64) -> f64 { ret dist.qnorm(p, mu, sigma, true, false) }

// the exponentially modified Gaussian exGAUS of gamlss.dist (mu, sigma, nu): with z = x - mu - sigma^2 / nu, the density
// exp(-log nu - (z + sigma^2 / (2 nu)) / nu) Phi(z / sigma) when nu > 0.05 sigma, else the normal density; the distribution
// Phi((x - mu) / sigma) - Phi(z / sigma) exp(((mu + sigma^2 / nu)^2 - mu^2 - 2 x sigma^2 / nu) / (2 sigma^2)) in that case, else the normal distribution
fn dexgaus(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if nu > 0.05f64 * sigma {
        let z = x - mu - sigma * sigma / nu
        let logfy = 0.0f64 - math.log[f64](nu) - (z + sigma * sigma / (2.0f64 * nu)) / nu + math.log[f64](dist.pnorm(z / sigma, 0.0f64, 1.0f64, true, false))
        ret math.exp[f64](logfy)
    }
    ret dist.dnorm(x, mu, sigma, false)
}

fn pexgaus(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if nu > 0.05f64 * sigma {
        let z = x - mu - sigma * sigma / nu
        let s2 = sigma * sigma
        let expo = ((mu + s2 / nu) * (mu + s2 / nu) - mu * mu - 2.0f64 * x * s2 / nu) / (2.0f64 * s2)
        ret dist.pnorm((x - mu) / sigma, 0.0f64, 1.0f64, true, false) - dist.pnorm(z / sigma, 0.0f64, 1.0f64, true, false) * math.exp[f64](expo)
    }
    ret dist.pnorm(x, mu, sigma, true, false)
}

// the Poisson family PO of gamlss.dist (mean mu): dpois, ppois and qpois of the base distribution
fn dpo(x: f64, mu: f64) -> f64 { ret nm.dpois(x, mu, false) }

fn ppo(x: f64, mu: f64) -> f64 { ret nm.ppois(x, mu, true, false) }

fn qpo(p: f64, mu: f64) -> f64 { ret nm.qpois(p, mu, true, false) }

// GA: gamma with mean mu and coefficient of variation sigma (shape 1 / sigma^2, scale mu sigma^2)
fn pga(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret nm.pgamma(x, 1.0f64 / (sigma * sigma), mu * sigma * sigma, true, false)
}

fn qga(p: f64, mu: f64, sigma: f64) -> f64 { ret nm.qgamma(p, 1.0f64 / (sigma * sigma), mu * sigma * sigma, true, false) }

// WEI: Weibull with scale mu and shape sigma
fn pwei(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 1.0f64 - math.exp[f64](0.0f64 - math.pow[f64](x / mu, sigma))
}

fn qwei(p: f64, mu: f64, sigma: f64) -> f64 { ret mu * math.pow[f64](0.0f64 - math.log[f64](1.0f64 - p), 1.0f64 / sigma) }

// LOGNO: log-normal with log-mean mu and log-sd sigma
fn plogno(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret dist.pnorm(math.log[f64](x), mu, sigma, true, false)
}

fn qlogno(p: f64, mu: f64, sigma: f64) -> f64 { ret math.exp[f64](dist.qnorm(p, mu, sigma, true, false)) }

// IG: inverse Gaussian with mean mu and sigma^2 mu^3 variance
fn pig(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let r = x / mu
    let s = sigma * math.sqrt[f64](x)
    let l2 = 2.0f64 / (mu * sigma * sigma) + dist.pnorm((0.0f64 - r - 1.0f64) / s, 0.0f64, 1.0f64, true, true)
    ret dist.pnorm((r - 1.0f64) / s, 0.0f64, 1.0f64, true, false) + math.exp[f64](l2)
}

// ZIP: zero-inflated Poisson, zero mass sigma
fn pzip(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret sigma + (1.0f64 - sigma) * nm.ppois(x, mu, true, false)
}

fn qzip(p: f64, mu: f64, sigma: f64) -> f64 {
    var pn = (p - sigma) / (1.0f64 - sigma)
    if pn < 0.0f64 { pn = 0.0f64 }
    ret nm.qpois(pn, mu, true, false)
}

// NBI: negative binomial with mean mu and size 1 / sigma
fn pnbi(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nb.pnbinom_mu(x, 1.0f64 / sigma, mu, true, false)
}

fn qnbi(p: f64, mu: f64, sigma: f64) -> f64 { ret nb.qnbinom_mu(p, 1.0f64 / sigma, mu, true, false) }

// TF: Student t with location mu, scale sigma and nu degrees of freedom (the normal above 1e6)
fn dtf(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if nu > 1000000.0f64 { ret dno(x, mu, sigma) }
    ret nb.dt((x - mu) / sigma, nu, false) / sigma
}

fn ptf(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if nu > 1000000.0f64 { ret pno(x, mu, sigma) }
    ret nb.pt((x - mu) / sigma, nu, true, false)
}

fn qtf(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if nu > 1000000.0f64 { ret qno(p, mu, sigma) }
    ret mu + sigma * nb.qt(p, nu, true, false)
}
