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
use e.algo.stat.pwr as pw
use e.algo.stat.gslfns as gs
use e.math.quadpack as qp
use e.mem

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

// BCCG: Box-Cox Cole-Green distribution and quantile
fn pbccg(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    var z = 0.0f64
    if nu != 0.0f64 { z = (math.pow[f64](x / mu, nu) - 1.0f64) / (nu * sigma) } else { z = math.log[f64](x / mu) / sigma }
    let f1 = dist.pnorm(z, 0.0f64, 1.0f64, true, false)
    var f2 = 0.0f64
    if nu > 0.0f64 { f2 = dist.pnorm(0.0f64 - 1.0f64 / (sigma * math.abs[f64](nu)), 0.0f64, 1.0f64, true, false) }
    let f3 = dist.pnorm(1.0f64 / (sigma * math.abs[f64](nu)), 0.0f64, 1.0f64, true, false)
    ret (f1 - f2) / f3
}

fn qbccg(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    let t = dist.pnorm(1.0f64 / (sigma * math.abs[f64](nu)), 0.0f64, 1.0f64, true, false)
    var z = 0.0f64
    if nu <= 0.0f64 { z = dist.qnorm(p * t, 0.0f64, 1.0f64, true, false) } else { z = dist.qnorm(1.0f64 - (1.0f64 - p) * t, 0.0f64, 1.0f64, true, false) }
    if nu != 0.0f64 { ret mu * math.pow[f64](nu * sigma * z + 1.0f64, 1.0f64 / nu) }
    ret mu * math.exp[f64](sigma * z)
}

// GP: generalised Pareto of gamlss.dist, via the F distribution
fn dgp(x: f64, mu: f64, sigma: f64) -> f64 {
    let z = x / mu
    ret math.exp[f64](math.log[f64](z) - math.log[f64](x) - sp.lgamma(sigma) + sp.lgamma(1.0f64 + sigma) - (1.0f64 + sigma) * math.log[f64](1.0f64 + z))
}

fn pgp(x: f64, mu: f64, sigma: f64) -> f64 { ret nb.pf(sigma * (x / mu), 2.0f64, 2.0f64 * sigma, true, false) }

fn qgp(p: f64, mu: f64, sigma: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    ret mu * (1.0f64 / sigma) * nb.qf(p, 2.0f64, 2.0f64 * sigma, true, false)
}

// BE: beta with mean mu and sigma the scale (shapes a = mu (1 - sigma^2) / sigma^2 and b = a (1 - mu) / mu)
fn dbe(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 || x >= 1.0f64 { ret 0.0f64 }
    let a = mu * (1.0f64 - sigma * sigma) / (sigma * sigma)
    ret nb.dbeta(x, a, a * (1.0f64 - mu) / mu, false)
}

fn pbe(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x >= 1.0f64 { ret 1.0f64 }
    let a = mu * (1.0f64 - sigma * sigma) / (sigma * sigma)
    ret nb.pbeta(x, a, a * (1.0f64 - mu) / mu, true, false)
}

fn qbe(p: f64, mu: f64, sigma: f64) -> f64 {
    if p < 0.0000000001f64 { ret 0.0f64 }
    if 1.0f64 - p < 0.0000000001f64 { ret 1.0f64 }
    let a = mu * (1.0f64 - sigma * sigma) / (sigma * sigma)
    ret nb.qbeta(p, a, a * (1.0f64 - mu) / mu, true, false)
}

// LNO: log-normal after the Box-Cox transform with fixed power nu
fn lno_z(x: f64, nu: f64) -> f64 {
    if nu != 0.0f64 { ret (math.pow[f64](x, nu) - 1.0f64) / nu }
    ret math.log[f64](x)
}

fn dlno(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let z = lno_z(x, nu)
    ret math.exp[f64](0.0f64 - 0.5f64 * math.log[f64](2.0f64 * pi()) - math.log[f64](sigma) - 0.5f64 * (z - mu) * (z - mu) / (sigma * sigma) + (nu - 1.0f64) * math.log[f64](x))
}

fn plno(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret dist.pnorm(lno_z(x, nu), mu, sigma, true, false)
}

fn qlno(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    let z = mu + sigma * dist.qnorm(p, 0.0f64, 1.0f64, true, false)
    if nu != 0.0f64 { ret math.pow[f64](nu * z + 1.0f64, 1.0f64 / nu) }
    ret math.exp[f64](z)
}

// GG: generalised gamma of gamlss.dist (a gamma of (x / mu)^nu; the log-normal in the limit nu -> 0)
fn dgg(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    if math.abs[f64](nu) > 0.000001f64 {
        let z = math.pow[f64](x / mu, nu)
        ret dga(z, 1.0f64, sigma * math.abs[f64](nu)) * math.abs[f64](nu) * z / x
    }
    let l = math.log[f64](x) - math.log[f64](mu)
    ret math.exp[f64](0.0f64 - math.log[f64](x) - 0.5f64 * math.log[f64](2.0f64 * pi()) - math.log[f64](sigma) - l * l / (2.0f64 * sigma * sigma))
}

fn pgg(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if math.abs[f64](nu) > 0.000001f64 {
        let z = math.pow[f64](x / mu, nu)
        let s = sigma * math.abs[f64](nu)
        ret nm.pgamma(z, 1.0f64 / (s * s), s * s, nu > 0.0f64, false)
    }
    ret pno(math.log[f64](x), math.log[f64](mu), sigma)
}

fn qgg(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if math.abs[f64](nu) > 0.000001f64 {
        var pp = p
        if nu < 0.0f64 { pp = 1.0f64 - p }
        ret mu * math.pow[f64](qga(pp, 1.0f64, sigma * math.abs[f64](nu)), 1.0f64 / nu)
    }
    ret math.exp[f64](qno(p, math.log[f64](mu), sigma))
}

// GB2: generalised beta of the second kind (mu, sigma, nu, tau), through the F distribution
fn dgb2(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let z = math.pow[f64](x / mu, sigma)
    ret math.exp[f64](nu * math.log[f64](z) + math.log[f64](math.abs[f64](sigma)) - math.log[f64](x) - sp.lgamma(nu) - sp.lgamma(tau) + sp.lgamma(nu + tau) - (nu + tau) * math.log[f64](1.0f64 + z))
}

fn pgb2(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = math.pow[f64](x / mu, sigma)
    let p = nb.pf((tau / nu) * z, 2.0f64 * nu, 2.0f64 * tau, true, false)
    if sigma < 0.0f64 { ret 1.0f64 - p }
    ret p
}

fn qgb2(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var pp = p
    if sigma < 0.0f64 { pp = 1.0f64 - p }
    if pp == 0.0f64 { ret 0.0f64 }
    let w = nb.qf(pp, 2.0f64 * nu, 2.0f64 * tau, true, false)
    ret mu * math.pow[f64]((nu / tau) * w, 1.0f64 / sigma)
}

// IGAMMA: inverse gamma
fn digamma_(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let al = 1.0f64 / (sigma * sigma)
    ret math.exp[f64](al * math.log[f64](mu) + al * math.log[f64](al + 1.0f64) - sp.lgamma(al) - (al + 1.0f64) * math.log[f64](x) - (mu * (al + 1.0f64)) / x)
}

fn pigamma(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let al = 1.0f64 / (sigma * sigma)
    ret math.exp[f64](nm.pgamma((mu * (al + 1.0f64)) / x, al, 1.0f64, false, true))
}

fn qigamma(p: f64, mu: f64, sigma: f64) -> f64 {
    let pp = 1.0f64 - p
    if pp == 0.0f64 { ret 0.0f64 }
    let z = qga(pp, 1.0f64, sigma)
    ret mu * (1.0f64 + sigma * sigma) * math.pow[f64](z, 0.0f64 - 1.0f64)
}

// RGE: reverse generalised extreme value (the Gumbel limit below |nu| 0.001)
fn drge(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if math.abs[f64](nu) < 0.001f64 { ret math.exp[f64](0.0f64 - math.log[f64](sigma) + (x - mu) / sigma - math.exp[f64]((x - mu) / sigma)) }
    let y = nu * (x - mu) / sigma
    var lg = 0.0f64
    if 1.0f64 + y > 0.0f64 { lg = math.log[f64](1.0f64 + y) }
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) + (1.0f64 / nu - 1.0f64) * lg - math.pow[f64](1.0f64 + y, 1.0f64 / nu))
}

fn prge(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if math.abs[f64](nu) < 0.001f64 { ret 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64]((x - mu) / sigma)) }
    let y = nu * (x - mu) / sigma
    ret 1.0f64 - math.exp[f64](0.0f64 - math.pow[f64](1.0f64 + y, 1.0f64 / nu))
}

fn qrge(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if math.abs[f64](nu) < 0.001f64 { ret mu + sigma * math.log[f64](0.0f64 - math.log[f64](1.0f64 - p)) }
    ret mu + (sigma / nu) * (math.pow[f64](0.0f64 - math.log[f64](1.0f64 - p), nu) - 1.0f64)
}

// NO2: the normal with variance sigma (gamlss.dist's qNO2 overwrites its own quantile with sd = sigma, and so does this)
fn dno2(x: f64, mu: f64, sigma: f64) -> f64 { ret dist.dnorm(x, mu, math.sqrt[f64](sigma), false) }

fn pno2(x: f64, mu: f64, sigma: f64) -> f64 { ret dist.pnorm(x, mu, math.sqrt[f64](sigma), true, false) }

fn qno2(p: f64, mu: f64, sigma: f64) -> f64 {
    if p < 0.0000000001f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if 1.0f64 - p < 0.0000000001f64 { ret 1.0f64 / 0.0f64 }
    ret dist.qnorm(p, mu, sigma, true, false)
}

// BI: binomial with probability mu and bd trials
fn dbi(x: f64, mu: f64, bd: f64) -> f64 {
    if x < 0.0f64 || x > bd { ret 0.0f64 }
    ret nb.dbinom(x, bd, mu, false)
}

fn pbi(x: f64, mu: f64, bd: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x > bd { ret 1.0f64 }
    ret nb.pbinom(x, bd, mu, true, false)
}

fn qbi(p: f64, mu: f64, bd: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret bd }
    ret nb.qbinom(p, bd, mu, true, false)
}

// GEOM (mean mu, probability 1 / (mu + 1)) and GEOMo (probability mu)
fn dgeom_mu(x: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nb.dgeom(x, 1.0f64 / (mu + 1.0f64), false)
}

fn pgeom_mu(x: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nb.pgeom(x, 1.0f64 / (mu + 1.0f64), true, false)
}

fn qgeom_mu(p: f64, mu: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    ret nb.qgeom(p, 1.0f64 / (mu + 1.0f64), true, false)
}

fn dgeomo(x: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nb.dgeom(x, mu, false)
}

fn pgeomo(x: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nb.pgeom(x, mu, true, false)
}

fn qgeomo(p: f64, mu: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    ret nb.qgeom(p, mu, true, false)
}

// WEI2 (scale mu^(-1 / sigma)) and WEI3 (scale mu / Gamma(1 / sigma + 1)), shape sigma
fn dwei2(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret dist.dweibull(x, sigma, math.pow[f64](mu, 0.0f64 - 1.0f64 / sigma), false)
}

fn pwei2(x: f64, mu: f64, sigma: f64) -> f64 { ret dist.pweibull(x, sigma, math.pow[f64](mu, 0.0f64 - 1.0f64 / sigma), true, false) }

fn qwei2(p: f64, mu: f64, sigma: f64) -> f64 { ret dist.qweibull(p, sigma, math.pow[f64](mu, 0.0f64 - 1.0f64 / sigma), true, false) }

fn wei3_scale(mu: f64, sigma: f64) -> f64 { ret mu / math.exp[f64](sp.lgamma(1.0f64 / sigma + 1.0f64)) }

fn dwei3(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret dist.dweibull(x, sigma, wei3_scale(mu, sigma), false)
}

fn pwei3(x: f64, mu: f64, sigma: f64) -> f64 { ret dist.pweibull(x, sigma, wei3_scale(mu, sigma), true, false) }

fn qwei3(p: f64, mu: f64, sigma: f64) -> f64 { ret dist.qweibull(p, sigma, wei3_scale(mu, sigma), true, false) }

// LOGNO2: log-normal with median mu and log-sd sigma
fn dlogno2(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let z = math.log[f64](x)
    ret math.exp[f64](dist.dnorm(z, math.log[f64](mu), sigma, true) - z)
}

fn plogno2(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret dist.pnorm(math.log[f64](x), math.log[f64](mu), sigma, true, false)
}

fn qlogno2(p: f64, mu: f64, sigma: f64) -> f64 { ret math.exp[f64](dist.qnorm(p, math.log[f64](mu), sigma, true, false)) }

// BEo: beta with the two shapes mu and sigma
fn dbeo(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 || x >= 1.0f64 { ret 0.0f64 }
    ret nb.dbeta(x, mu, sigma, false)
}

fn pbeo(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x >= 1.0f64 { ret 1.0f64 }
    ret nb.pbeta(x, mu, sigma, true, false)
}

fn qbeo(p: f64, mu: f64, sigma: f64) -> f64 {
    if p < 0.0000000001f64 { ret 0.0f64 }
    if 1.0f64 - p < 0.0000000001f64 { ret 1.0f64 }
    ret nb.qbeta(p, mu, sigma, true, false)
}

// TF2: Student t with standard deviation sigma (scale sigma sqrt((nu - 2) / nu))
fn dtf2(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret dtf(x, mu, math.sqrt[f64]((nu - 2.0f64) / nu) * sigma, nu) }

fn ptf2(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret ptf(x, mu, math.sqrt[f64]((nu - 2.0f64) / nu) * sigma, nu) }

fn qtf2(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret qtf(p, mu, math.sqrt[f64]((nu - 2.0f64) / nu) * sigma, nu) }

// ZIBI and ZABI: zero-inflated and zero-adjusted binomial (mu the probability, sigma the zero mass, bd the trials)
fn dzibi(x: f64, mu: f64, sigma: f64, bd: f64) -> f64 {
    if x < 0.0f64 || x > bd { ret 0.0f64 }
    if x == 0.0f64 { ret sigma + (1.0f64 - sigma) * dbi(0.0f64, mu, bd) }
    ret (1.0f64 - sigma) * dbi(x, mu, bd)
}

fn pzibi(x: f64, mu: f64, sigma: f64, bd: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x > bd { ret 1.0f64 }
    ret sigma + (1.0f64 - sigma) * nb.pbinom(x, bd, mu, true, false)
}

fn qzibi(p: f64, mu: f64, sigma: f64, bd: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret bd }
    let pn = (p - sigma) / (1.0f64 - sigma) - 0.0000000001f64
    if pn > 0.0f64 { ret nb.qbinom(pn, bd, mu, true, false) }
    ret 0.0f64
}

fn dzabi(x: f64, mu: f64, sigma: f64, bd: f64) -> f64 {
    if x < 0.0f64 || x > bd { ret 0.0f64 }
    if x == 0.0f64 { ret sigma }
    ret (1.0f64 - sigma) * dbi(x, mu, bd) / (1.0f64 - dbi(0.0f64, mu, bd))
}

fn pzabi(x: f64, mu: f64, sigma: f64, bd: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x > bd { ret 1.0f64 }
    if x == 0.0f64 { ret sigma }
    let c0 = nb.pbinom(0.0f64, bd, mu, true, false)
    ret sigma + (1.0f64 - sigma) * (nb.pbinom(x, bd, mu, true, false) - c0) / (1.0f64 - c0)
}

fn qzabi(p: f64, mu: f64, sigma: f64, bd: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret bd }
    let pn = (p - sigma) / (1.0f64 - sigma) - 0.0000000001f64
    if pn > 0.0f64 {
        let pn2 = nb.pbinom(0.0f64, bd, mu, true, false) * (1.0f64 - pn) + pn
        ret nb.qbinom(pn2, bd, mu, true, false)
    }
    ret 0.0f64
}

// ZAP: zero-adjusted Poisson; ZIP2: zero-inflated Poisson with mean mu (the Poisson mean mu / (1 - sigma))
fn dzap(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret sigma }
    ret (1.0f64 - sigma) * nm.dpois(x, mu, false) / (1.0f64 - nm.dpois(0.0f64, mu, false))
}

fn pzap(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret sigma }
    let c0 = nm.ppois(0.0f64, mu, true, false)
    ret sigma + (1.0f64 - sigma) * (nm.ppois(x, mu, true, false) - c0) / (1.0f64 - c0)
}

fn qzap(p: f64, mu: f64, sigma: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    let pn = (p - sigma) / (1.0f64 - sigma)
    if pn > 0.0f64 {
        let pn2 = nm.ppois(0.0f64, mu, true, false) * (1.0f64 - pn) + pn
        ret nm.qpois(pn2, mu, true, false)
    }
    ret 0.0f64
}

fn dzip2(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let mus = mu / (1.0f64 - sigma)
    if x == 0.0f64 { ret sigma + (1.0f64 - sigma) * math.exp[f64](0.0f64 - mus) }
    ret math.exp[f64]((1.0f64 - x) * math.log[f64](1.0f64 - sigma) - mus + x * math.log[f64](mu) - sp.lgamma(x + 1.0f64))
}

fn pzip2(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret sigma + (1.0f64 - sigma) * nm.ppois(x, mu / (1.0f64 - sigma), true, false)
}

fn qzip2(p: f64, mu: f64, sigma: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    let pn = (p - sigma) / (1.0f64 - sigma) - 0.0000000001f64
    if pn > 0.0f64 { ret nm.qpois(pn, mu / (1.0f64 - sigma), true, false) }
    ret 0.0f64
}

// ZANBI and ZINBI: zero-adjusted and zero-inflated negative binomial (nu the zero mass)
fn dzanbi(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu }
    ret (1.0f64 - nu) * dnbi(x, mu, sigma) / (1.0f64 - dnbi(0.0f64, mu, sigma))
}

fn pzanbi(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu }
    let c0 = pnbi(0.0f64, mu, sigma)
    ret nu + (1.0f64 - nu) * (pnbi(x, mu, sigma) - c0) / (1.0f64 - c0)
}

fn qzanbi(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    let pn = (p - nu) / (1.0f64 - nu) - 0.0000000001f64
    var pn2 = pnbi(0.0f64, mu, sigma) * (1.0f64 - pn) + pn
    if pn2 < 0.0f64 { pn2 = 0.0f64 }
    ret qnbi(pn2, mu, sigma)
}

fn dzinbi(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu + (1.0f64 - nu) * dnbi(0.0f64, mu, sigma) }
    ret (1.0f64 - nu) * dnbi(x, mu, sigma)
}

fn pzinbi(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nu + (1.0f64 - nu) * pnbi(x, mu, sigma)
}

fn qzinbi(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    var pn = (p - nu) / (1.0f64 - nu) - 0.0000001f64
    if pn < 0.0f64 { pn = 0.0f64 }
    ret qnbi(pn, mu, sigma)
}

// ZAGA: zero-adjusted gamma
fn dzaga(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu }
    ret (1.0f64 - nu) * dga(x, mu, sigma)
}

fn pzaga(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu }
    ret nu + (1.0f64 - nu) * pga(x, mu, sigma)
}

fn qzaga(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    var pp = p
    if p <= nu { pp = nu }
    ret qga((pp - nu) / (1.0f64 - nu), mu, sigma)
}

// PE: power exponential (mu, sigma, nu)
fn pe_c(nu: f64) -> f64 { ret math.exp[f64](0.5f64 * (0.0f64 - (2.0f64 / nu) * math.log[f64](2.0f64) + sp.lgamma(1.0f64 / nu) - sp.lgamma(3.0f64 / nu))) }

fn dpe_full(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    let c = pe_c(nu)
    let z = (x - mu) / sigma
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) + math.log[f64](nu) - math.log[f64](c) - 0.5f64 * math.pow[f64](math.abs[f64](z / c), nu) - (1.0f64 + 1.0f64 / nu) * math.log[f64](2.0f64) - sp.lgamma(1.0f64 / nu))
}

fn ppe(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if nu > 10000.0f64 { ret (x - (mu - math.sqrt[f64](3.0f64) * sigma)) / (math.sqrt[f64](12.0f64) * sigma) }
    let c = pe_c(nu)
    let z = (x - mu) / sigma
    var sg = 0.0f64
    if z > 0.0f64 { sg = 1.0f64 }
    if z < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    let s = 0.5f64 * math.pow[f64](math.abs[f64](z / c), nu)
    ret 0.5f64 * (1.0f64 + nm.pgamma(s, 1.0f64 / nu, 1.0f64, true, false) * sg)
}

fn qpe(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    let c = pe_c(nu)
    var sg = 0.0f64
    if p > 0.5f64 { sg = 1.0f64 }
    if p < 0.5f64 { sg = 0.0f64 - 1.0f64 }
    let s = nm.qgamma((2.0f64 * p - 1.0f64) * sg, 1.0f64 / nu, 1.0f64, true, false)
    ret mu + sigma * (sg * math.pow[f64](2.0f64 * s, 1.0f64 / nu) * c)
}

// EGB2: exponential generalised beta of the second kind
fn degb2(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    ret math.exp[f64](nu * z - math.log[f64](math.abs[f64](sigma)) - sp.lgamma(nu) - sp.lgamma(tau) + sp.lgamma(nu + tau) - (nu + tau) * math.log[f64](1.0f64 + math.exp[f64](z)))
}

fn pegb2(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let w = (tau / nu) * math.exp[f64]((x - mu) / sigma)
    let p = nb.pf(w, 2.0f64 * nu, 2.0f64 * tau, true, false)
    if sigma < 0.0f64 { ret 1.0f64 - p }
    ret p
}

fn qegb2(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var pp = p
    if sigma < 0.0f64 { pp = 1.0f64 - p }
    if pp == 0.0f64 { ret 0.0f64 }
    if pp == 1.0f64 { ret 1.0f64 / 0.0f64 }
    let w = nb.qf(pp, 2.0f64 * nu, 2.0f64 * tau, true, false)
    ret mu + sigma * math.log[f64]((nu / tau) * w)
}

// PARETO2o (the original parametrisation) and PARETO1o
fn dpareto2o(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](math.log[f64](sigma) + sigma * math.log[f64](mu) - (sigma + 1.0f64) * math.log[f64](x + mu))
}

fn ppareto2o(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 1.0f64 - math.pow[f64](mu / (mu + x), sigma)
}

fn qpareto2o(p: f64, mu: f64, sigma: f64) -> f64 { ret mu * (math.pow[f64](1.0f64 - p, 0.0f64 - 1.0f64 / sigma) - 1.0f64) }

// LG: logarithmic series; YULE: Yule distribution (cdf by summation, quantile by search as the package does)
fn dlg(x: f64, mu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](x * math.log[f64](mu) - math.log[f64](x) - math.log[f64](0.0f64 - math.log[f64](1.0f64 - mu)))
}

fn plg(x: f64, mu: f64) -> f64 {
    if x < 1.0f64 { ret 0.0f64 }
    var s = 0.0f64
    var j = 1.0f64
    while j <= x {
        s += dlg(j, mu)
        j += 1.0f64
    }
    ret s
}

fn qlg(p: f64, mu: f64, max_value: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p + 0.000000001f64 >= 1.0f64 { ret 1.0f64 / 0.0f64 }
    var cum = 0.0f64
    var j = 1.0f64
    var q = 1.0f64
    while j <= max_value {
        cum += dlg(j, mu)
        q = j
        if p <= cum { break }
        j += 1.0f64
    }
    ret q
}

fn lbeta_(a: f64, b: f64) -> f64 { ret sp.lgamma(a) + sp.lgamma(b) - sp.lgamma(a + b) }

fn dyule(x: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let la = (mu + 1.0f64) / mu
    ret math.exp[f64](lbeta_(la + 1.0f64, x + 1.0f64) - lbeta_(la, 1.0f64))
}

fn pyule(x: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    var s = 0.0f64
    var j = 0.0f64
    while j <= x {
        s += dyule(j, mu)
        j += 1.0f64
    }
    ret s
}

fn qyule(p: f64, mu: f64, max_value: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p + 0.000000001f64 >= 1.0f64 { ret 1.0f64 / 0.0f64 }
    var cum = 0.0f64
    var j = 0.0f64
    var q = 0.0f64
    while j <= max_value {
        cum += dyule(j, mu)
        q = j
        if p <= cum { break }
        j += 1.0f64
    }
    ret q
}

// PARETO1o
fn dpareto1o(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= mu { ret 0.0f64 }
    ret math.exp[f64](math.log[f64](sigma) + sigma * math.log[f64](mu) - (sigma + 1.0f64) * math.log[f64](x))
}

fn ppareto1o(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= mu { ret 0.0f64 }
    ret 1.0f64 - math.pow[f64](mu / x, sigma)
}

fn qpareto1o(p: f64, mu: f64, sigma: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    ret mu * math.pow[f64](1.0f64 - p, 0.0f64 - 1.0f64 / sigma)
}

// NBII: negative binomial of type II (variance mu + sigma mu); gamlss.dist's pNBII applies ppois whenever sigma exceeds 1e-4, and so does this
fn dnbii(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if sigma <= 0.0001f64 { ret nm.dpois(x, mu, false) }
    ret nb.dnbinom_mu(x, mu / sigma, mu, false)
}

fn pnbii(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if sigma > 0.0001f64 { ret nm.ppois(x, mu, true, false) }
    ret nb.pnbinom_mu(x, mu / sigma, mu, true, false)
}

fn qnbii(p: f64, mu: f64, sigma: f64) -> f64 { ret nb.qnbinom_mu(p, mu / sigma, mu, true, false) }

// LOGITNO: logit-normal
fn dlogitno(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 || x >= 1.0f64 { ret 0.0f64 }
    let z = math.log[f64](x / (1.0f64 - x))
    ret math.exp[f64](dist.dnorm(z, math.log[f64](mu / (1.0f64 - mu)), sigma, true) - math.log[f64](x) - math.log[f64](1.0f64 - x))
}

fn plogitno(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x >= 1.0f64 { ret 1.0f64 }
    ret dist.pnorm(math.log[f64](x / (1.0f64 - x)), math.log[f64](mu / (1.0f64 - mu)), sigma, true, false)
}

fn qlogitno(p: f64, mu: f64, sigma: f64) -> f64 {
    if p < 0.0000000001f64 { ret 0.0f64 }
    if 1.0f64 - p < 0.0000000001f64 { ret 1.0f64 }
    let qz = dist.qnorm(p, math.log[f64](mu / (1.0f64 - mu)), sigma, true, false)
    ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - qz))
}

// WARING (cdf by summation), ZALG (zero-adjusted logarithmic) and GPO (the package's dGPO replaces the generalised Poisson by the Poisson whenever sigma exceeds 1e-6)
fn dwaring(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](lbeta_(x + mu / sigma, 1.0f64 / sigma + 2.0f64) - lbeta_(mu / sigma, 1.0f64 / sigma + 1.0f64))
}

fn pwaring(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    var s = 0.0f64
    var j = 0.0f64
    while j <= x {
        s += dwaring(j, mu, sigma)
        j += 1.0f64
    }
    ret s
}

// gamlss.dist's dZALG is the logarithmic density itself for x > 0 (it is not scaled by 1 - sigma)
fn dzalg(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret sigma }
    ret dlg(x, mu)
}

fn pzalg(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x < 1.0f64 { ret sigma }
    ret sigma + (1.0f64 - sigma) * plg(x, mu)
}

fn dgpo(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if sigma > 0.000001f64 { ret nm.dpois(x, mu, false) }
    ret math.exp[f64](x * math.log[f64](mu / (1.0f64 + sigma * mu)) + (x - 1.0f64) * math.log[f64](1.0f64 + sigma * x) + (0.0f64 - mu * (1.0f64 + sigma * x)) / (1.0f64 + sigma * mu) - sp.lgamma(x + 1.0f64))
}

// qexGAUS: gamlss.dist finds the quantile with uniroot (Brent's zeroin at tolerance eps^0.25) on a bracket grown in steps of sigma from mu; the same
// zeroin (e.algo.stat.pwr) on the same bracket gives the same root
type ExgausRoot = struct { mu: f64, sigma: f64, nu: f64, p: f64 }

fn exgaus_h(c: *ExgausRoot, q: f64) -> f64 { ret pexgaus(q, c.mu, c.sigma, c.nu) }

fn exgaus_h1(c: *ExgausRoot, q: f64) -> f64 { ret pexgaus(q, c.mu, c.sigma, c.nu) - c.p }

fn qexgaus(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p <= 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p >= 1.0f64 { ret 1.0f64 / 0.0f64 }
    var c: ExgausRoot = zero
    c.mu = mu
    c.sigma = sigma
    c.nu = nu
    c.p = p
    var lo = 0.0f64
    var hi = 0.0f64
    if exgaus_h(&c, mu) < p {
        lo = mu
        hi = mu + sigma
        var j = 2.0f64
        while exgaus_h(&c, hi) < p {
            hi = mu + j * sigma
            j += 1.0f64
        }
    } else {
        lo = mu - sigma
        hi = mu
        var j = 2.0f64
        while exgaus_h(&c, lo) > p {
            lo = mu - j * sigma
            j += 1.0f64
        }
    }
    ret pw.zeroin[ExgausRoot](&c, exgaus_h1, lo, hi, pw.uniroot_tol(), 1000i64)
}

// JSU distribution and quantile, JSUo (original parametrisation), SHASHo and SHASH: the closed forms of gamlss.dist, and the SHASH quantile through the package's bracket and uniroot
fn jsu_consts(mu: f64, sigma: f64, nu: f64, tau: f64) -> (f64, f64) {
    let rtau = 1.0f64 / tau
    var w = 1.0f64
    if rtau >= 1.0e-7f64 { w = math.exp[f64](rtau * rtau) }
    let omega = 0.0f64 - nu * rtau
    let c = math.pow[f64](0.5f64 * (w - 1.0f64) * (w * cosh_of(2.0f64 * omega) + 1.0f64), 0.0f64 - 0.5f64)
    ret (c, mu + c * sigma * math.sqrt[f64](w) * sinh_of(omega))
}

fn pjsu(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let (c, loc) = jsu_consts(mu, sigma, nu, tau)
    let z = (x - loc) / (c * sigma)
    ret pno(0.0f64 - nu + asinh_of(z) * tau, 0.0f64, 1.0f64)
}

fn qjsu(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let (c, loc) = jsu_consts(mu, sigma, nu, tau)
    let r = qno(p, 0.0f64, 1.0f64)
    ret loc + c * sigma * sinh_of((r + nu) / tau)
}

fn djsuo(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    let r = nu + tau * asinh_of(z)
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) + math.log[f64](tau) - 0.5f64 * math.log[f64](z * z + 1.0f64) - 0.5f64 * math.log[f64](2.0f64 * pi()) - 0.5f64 * r * r)
}

fn pjsuo(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret pno(nu + tau * asinh_of((x - mu) / sigma), 0.0f64, 1.0f64) }

fn qjsuo(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret mu + sigma * sinh_of((qno(p, 0.0f64, 1.0f64) - nu) / tau) }

fn dshasho(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    let a = tau * asinh_of(z) - nu
    let c = cosh_of(a)
    let r = sinh_of(a)
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) + math.log[f64](tau) - math.log[f64](2.0f64 * pi()) / 2.0f64 - math.log[f64](1.0f64 + z * z) / 2.0f64 + math.log[f64](c) - r * r / 2.0f64)
}

fn pshasho(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret pno(sinh_of(tau * asinh_of((x - mu) / sigma) - nu), 0.0f64, 1.0f64) }

fn qshasho(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret mu + sigma * sinh_of((1.0f64 / tau) * asinh_of(qno(p, 0.0f64, 1.0f64)) + nu / tau) }

fn pshash(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let a = asinh_of((x - mu) / sigma)
    ret pno(0.5f64 * (math.exp[f64](tau * a) - math.exp[f64](0.0f64 - nu * a)), 0.0f64, 1.0f64)
}

type ShashRoot = struct { mu: f64, sigma: f64, nu: f64, tau: f64, p: f64 }

fn shash_h(c: *ShashRoot, q: f64) -> f64 { ret pshash(q, c.mu, c.sigma, c.nu, c.tau) }

fn shash_h1(c: *ShashRoot, q: f64) -> f64 { ret pshash(q, c.mu, c.sigma, c.nu, c.tau) - c.p }

fn qshash(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p <= 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p >= 1.0f64 { ret 1.0f64 / 0.0f64 }
    var c: ShashRoot = zero
    c.mu = mu
    c.sigma = sigma
    c.nu = nu
    c.tau = tau
    c.p = p
    var lo = 0.0f64
    var hi = 0.0f64
    if shash_h(&c, mu) < p {
        lo = mu
        hi = mu + sigma
        var j = 2.0f64
        while shash_h(&c, hi) < p {
            hi = mu + j * sigma
            j += 1.0f64
        }
    } else {
        lo = mu - sigma
        hi = mu
        var j = 2.0f64
        while shash_h(&c, lo) > p {
            lo = mu - j * sigma
            j += 1.0f64
        }
    }
    ret pw.zeroin[ShashRoot](&c, shash_h1, lo, hi, pw.uniroot_tol(), 1000i64)
}

// BCT distribution and quantile (also BCTo, whose distribution and quantile are the same), BCTo density, BCCGo (the BCCG functions under the original names) and SHASHo2
fn pbct(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    var z = 0.0f64
    if nu != 0.0f64 { z = (math.pow[f64](x / mu, nu) - 1.0f64) / (nu * sigma) } else { z = math.log[f64](x / mu) / sigma }
    let f1 = nb.pt(z, tau, true, false)
    var f2 = 0.0f64
    if nu > 0.0f64 { f2 = nb.pt(0.0f64 - 1.0f64 / (sigma * math.abs[f64](nu)), tau, true, false) }
    let f3 = nb.pt(1.0f64 / (sigma * math.abs[f64](nu)), tau, true, false)
    ret (f1 - f2) / f3
}

fn qbct(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    let zp = nb.pt(1.0f64 / (sigma * math.abs[f64](nu)), tau, true, false)
    var z = 0.0f64
    if nu <= 0.0f64 { z = nb.qt(p * zp, tau, true, false) } else { z = nb.qt(1.0f64 - (1.0f64 - p) * zp, tau, true, false) }
    if nu != 0.0f64 { ret mu * math.pow[f64](nu * sigma * z + 1.0f64, 1.0f64 / nu) }
    ret mu * math.exp[f64](sigma * z)
}

fn dbcto(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    if tau > 1000000.0f64 { ret dbccg(x, mu, sigma, nu) }
    var z = 0.0f64
    if nu != 0.0f64 { z = (math.pow[f64](x / mu, nu) - 1.0f64) / (nu * sigma) } else { z = math.log[f64](x / mu) / sigma }
    var ll = (nu - 1.0f64) * math.log[f64](x) - nu * math.log[f64](mu) - math.log[f64](sigma)
    var ft = sp.lgamma((tau + 1.0f64) / 2.0f64) - sp.lgamma(tau / 2.0f64) - 0.5f64 * math.log[f64](tau) - sp.lgamma(0.5f64)
    ft = ft - ((tau + 1.0f64) / 2.0f64) * math.log[f64](1.0f64 + z * z / tau)
    ll = ll + ft - math.log[f64](nb.pt(1.0f64 / (sigma * math.abs[f64](nu)), tau, true, false))
    ret math.exp[f64](ll)
}

fn dshasho2(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / (sigma * tau)
    let a = tau * asinh_of(z) - nu
    let c = cosh_of(a)
    let r = sinh_of(a)
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) - 0.5f64 * math.log[f64](2.0f64 * pi()) - 0.5f64 * math.log[f64](1.0f64 + z * z) + math.log[f64](c) - 0.5f64 * r * r)
}

fn pshasho2(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret pno(sinh_of(tau * asinh_of((x - mu) / (sigma * tau)) - nu), 0.0f64, 1.0f64) }

fn qshasho2(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret mu + (tau * sigma) * sinh_of((1.0f64 / tau) * asinh_of(qno(p, 0.0f64, 1.0f64)) + nu / tau) }

// BB (beta binomial, bd trials) and BNB (beta negative binomial), distribution by summation; SEP3 and SN2 densities; ST3 density and distribution
fn dbb(x: f64, mu: f64, sigma0: f64, bd: f64) -> f64 {
    if x < 0.0f64 || x > bd { ret 0.0f64 }
    var sigma = sigma0
    if sigma < 0.0000000001f64 { sigma = 0.0000000001f64 }
    if sigma < 0.0001f64 { ret dbi(x, mu, bd) }
    let s1 = 1.0f64 / sigma
    ret math.exp[f64](sp.lgamma(bd + 1.0f64) - sp.lgamma(x + 1.0f64) - sp.lgamma(bd - x + 1.0f64) + sp.lgamma(s1) + sp.lgamma(x + mu * s1) + sp.lgamma(bd + (1.0f64 - mu) / sigma - x) - sp.lgamma(mu * s1) - sp.lgamma((1.0f64 - mu) / sigma) - sp.lgamma(bd + s1))
}

fn pbb(x: f64, mu: f64, sigma: f64, bd: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x >= bd { ret 1.0f64 }
    if sigma < 0.0001f64 { ret nb.pbinom(x, bd, mu, true, false) }
    var s = 0.0f64
    var j = 0.0f64
    while j <= x {
        s += dbb(j, mu, sigma, bd)
        j += 1.0f64
    }
    ret s
}

fn dbnb(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let m = 1.0f64 / sigma + 1.0f64
    let n = (mu * nu) / sigma
    let k = 1.0f64 / nu
    ret math.exp[f64](lbeta_(x + n, m + k) - lbeta_(n, m) - sp.lgamma(x + 1.0f64) - sp.lgamma(k) + sp.lgamma(x + k))
}

fn pbnb(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    var s = 0.0f64
    var j = 0.0f64
    while j <= x {
        s += dbnb(j, mu, sigma, nu)
        j += 1.0f64
    }
    ret s
}

fn dsep3(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    var ll = 0.0f64
    if x < mu { ll = 0.0f64 - 0.5f64 * math.pow[f64](nu * math.abs[f64](z), tau) } else { ll = 0.0f64 - 0.5f64 * math.pow[f64](math.abs[f64](z) / nu, tau) }
    ll = ll - math.log[f64](sigma) + math.log[f64](nu) - math.log[f64](1.0f64 + nu * nu) - (1.0f64 / tau) * math.log[f64](2.0f64) - sp.lgamma(1.0f64 + 1.0f64 / tau)
    ret math.exp[f64](ll)
}

fn dsn2(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret dsep3(x, mu, sigma, nu, 2.0f64) }

fn dst3(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var t = 0.0f64
    if x < mu { t = nu * (x - mu) / sigma } else { t = (x - mu) / (sigma * nu) }
    var base = 0.0f64
    if tau < 1000000.0f64 { base = nb.dt(t, tau, true) } else { base = dist.dnorm(t, 0.0f64, 1.0f64, true) }
    ret math.exp[f64](base + math.log[f64](2.0f64 * nu / (1.0f64 + nu * nu)) - math.log[f64](sigma))
}

fn pst3(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var c = 0.0f64
    if x < mu { c = 2.0f64 * nb.pt(nu * (x - mu) / sigma, tau, true, false) } else { c = 1.0f64 + 2.0f64 * nu * nu * (nb.pt((x - mu) / (sigma * nu), tau, true, false) - 0.5f64) }
    ret c / (1.0f64 + nu * nu)
}

// skew t and skew power exponential densities (ST2, ST4, ST5, SEP1, SEP2, SEP4), SN1, and the ST3 quantile
fn dst2(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    var lam = 1.0f64
    if tau < 1000000.0f64 { lam = (tau + 1.0f64) / (tau + z * z) }
    let w = nu * math.sqrt[f64](lam) * z
    if tau < 1000000.0f64 { ret math.exp[f64](nb.pt(w, tau + 1.0f64, true, true) + nb.dt(z, tau, true) + math.log[f64](2.0f64) - math.log[f64](sigma)) }
    ret math.exp[f64](dist.pnorm(w, 0.0f64, 1.0f64, true, true) + dist.dnorm(z, 0.0f64, 1.0f64, true) + math.log[f64](2.0f64) - math.log[f64](sigma))
}

fn dst4(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var lk1 = sp.lgamma(0.5f64) + sp.lgamma(nu / 2.0f64) - sp.lgamma((nu + 1.0f64) / 2.0f64) + 0.5f64 * math.log[f64](nu)
    if nu >= 1000000.0f64 { lk1 = 0.5f64 * math.log[f64](2.0f64 * pi()) }
    var lk2 = sp.lgamma(0.5f64) + sp.lgamma(tau / 2.0f64) - sp.lgamma((tau + 1.0f64) / 2.0f64) + 0.5f64 * math.log[f64](tau)
    if tau >= 1000000.0f64 { lk2 = 0.5f64 * math.log[f64](2.0f64 * pi()) }
    let k = math.exp[f64](lk2 - lk1)
    let t = (x - mu) / sigma
    let lb = dist.dnorm(t, 0.0f64, 1.0f64, true)
    var l1 = nb.dt(t, nu, true)
    if tau >= 1000000.0f64 { l1 = lb }
    var l2 = nb.dt(t, tau, true)
    if tau >= 1000000.0f64 { l2 = lb }
    var ll = 0.0f64
    if x < mu { ll = l1 } else { ll = l2 + (lk2 - lk1) }
    ret math.exp[f64](ll + math.log[f64](2.0f64 / (1.0f64 + k)) - math.log[f64](sigma))
}

fn dst5(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    let ve = 2.0f64 / tau
    let lam = 2.0f64 * nu / (tau * math.sqrt[f64](2.0f64 * tau + nu * nu))
    let aa = (ve + lam) / 2.0f64
    let bb = (ve - lam) / 2.0f64
    let r = math.sqrt[f64](aa + bb + z * z)
    ret math.exp[f64]((aa + 0.5f64) * math.log[f64](1.0f64 + z / r) + (bb + 0.5f64) * math.log[f64](1.0f64 - z / r) - (aa + bb - 1.0f64) * math.log[f64](2.0f64) - 0.5f64 * math.log[f64](aa + bb) - lbeta_(aa, bb) - math.log[f64](sigma))
}

fn dsep1(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    let w = nu * z
    let sz = math.pow[f64](math.abs[f64](z), tau) / tau
    let s = math.pow[f64](math.abs[f64](w), tau) / tau
    let lpdf = (1.0f64 - 1.0f64 / tau) * math.log[f64](tau) - sz - sp.lgamma(1.0f64 / tau) - math.log[f64](2.0f64)
    var sg = 0.0f64
    if w > 0.0f64 { sg = 1.0f64 }
    if w < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    var lcdf = 0.0f64
    if s == 0.0f64 {
        lcdf = math.log[f64](0.5f64 + w * math.exp[f64]((1.0f64 - 1.0f64 / tau) * math.log[f64](tau) - sp.lgamma(1.0f64 / tau) - math.log[f64](2.0f64)))
    } else {
        lcdf = math.log[f64](0.5f64 * (1.0f64 + nm.pgamma(s, 1.0f64 / tau, 1.0f64, true, false) * sg))
    }
    ret math.exp[f64](lpdf + lcdf + math.log[f64](2.0f64) - math.log[f64](sigma))
}

fn dsn1(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret dsep1(x, mu, sigma, nu, 2.0f64) }

fn dsep2(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    var sg = 0.0f64
    if z > 0.0f64 { sg = 1.0f64 }
    if z < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    let w = sg * math.pow[f64](math.abs[f64](z), tau / 2.0f64) * nu * math.sqrt[f64](2.0f64 / tau)
    ret math.exp[f64](math.log[f64](dist.pnorm(w, 0.0f64, 1.0f64, true, false)) - math.pow[f64](math.abs[f64](z), tau) / tau - math.log[f64](sigma) - sp.lgamma(1.0f64 / tau) - (1.0f64 / tau - 1.0f64) * math.log[f64](tau))
}

fn dsep4(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let k1 = math.exp[f64](sp.lgamma(1.0f64 + 1.0f64 / nu))
    let k2 = math.exp[f64](sp.lgamma(1.0f64 + 1.0f64 / tau))
    let z = (x - mu) / sigma
    var ll = 0.0f64
    if x < mu { ll = 0.0f64 - math.pow[f64](math.abs[f64](z), nu) } else { ll = 0.0f64 - math.pow[f64](math.abs[f64](z), tau) }
    ret math.exp[f64](ll - math.log[f64](k1 + k2) - math.log[f64](sigma))
}

fn qst3(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    if p < 1.0f64 / (1.0f64 + nu * nu) { ret mu + (sigma / nu) * nb.qt(p * (1.0f64 + nu * nu) / 2.0f64, tau, true, false) }
    ret mu + (sigma * nu) * nb.qt((p * (1.0f64 + nu * nu) - 1.0f64) / (2.0f64 * nu * nu) + 0.5f64, tau, true, false)
}

// the distributions that gamlss.dist integrates numerically (integrate() over (-Inf, z], its defaults: relative and absolute tolerance eps^0.25, 100
// subdivisions), through the QUADPACK port of R's rdqagie in e.math.quadpack; kind 0 SN1, 1 SEP1, 2 ST2, 3 SEP2
type IntCtx = struct { kind: usize, nu: f64, tau: f64 }

fn int_dens(c: *IntCtx, x: f64) -> f64 {
    if c.kind == 0usize { ret dsn1(x, 0.0f64, 1.0f64, c.nu) }
    if c.kind == 1usize { ret dsep1(x, 0.0f64, 1.0f64, c.nu, c.tau) }
    if c.kind == 3usize { ret dsep2(x, 0.0f64, 1.0f64, c.nu, c.tau) }
    ret dst2(x, 0.0f64, 1.0f64, c.nu, c.tau)
}

fn pint(a: *mem.Arena, kind: usize, x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var c: IntCtx = zero
    c.kind = kind
    c.nu = nu
    c.tau = tau
    let tol = pw.uniroot_tol()
    let (r, e) = qp.qagi[IntCtx](a, &c, int_dens, (x - mu) / sigma, 0i64 - 1i64, tol, tol, 100usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret r.result
}

fn psn1(a: *mem.Arena, x: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret pint(a, 0usize, x, mu, sigma, nu, 0.0f64) }

fn psep1(a: *mem.Arena, x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret pint(a, 1usize, x, mu, sigma, nu, tau) }

fn pst2(a: *mem.Arena, x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret pint(a, 2usize, x, mu, sigma, nu, tau) }

fn pst4(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var lk1 = sp.lgamma(0.5f64) + sp.lgamma(nu / 2.0f64) - sp.lgamma((nu + 1.0f64) / 2.0f64) + 0.5f64 * math.log[f64](nu)
    if nu >= 1000000.0f64 { lk1 = 0.5f64 * math.log[f64](2.0f64 * pi()) }
    var lk2 = sp.lgamma(0.5f64) + sp.lgamma(tau / 2.0f64) - sp.lgamma((tau + 1.0f64) / 2.0f64) + 0.5f64 * math.log[f64](tau)
    if tau >= 1000000.0f64 { lk2 = 0.5f64 * math.log[f64](2.0f64 * pi()) }
    let k = math.exp[f64](lk2 - lk1)
    let z = (x - mu) / sigma
    var c = 0.0f64
    if x < mu { c = 2.0f64 * nb.pt(z, nu, true, false) } else { c = 1.0f64 + 2.0f64 * k * (nb.pt(z, tau, true, false) - 0.5f64) }
    ret c / (1.0f64 + k)
}

fn pst5(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    let ve = 2.0f64 / tau
    let lam = 2.0f64 * nu / (tau * math.sqrt[f64](2.0f64 * tau + nu * nu))
    let aa = (ve + lam) / 2.0f64
    let bb = (ve - lam) / 2.0f64
    ret nb.pbeta((1.0f64 + z / math.sqrt[f64](aa + bb + z * z)) / 2.0f64, aa, bb, true, false)
}

// qSN1: the package's bracket (grown in steps of sigma from mu) and uniroot over pSN1
type Sn1Root = struct { a: *mem.Arena, mu: f64, sigma: f64, nu: f64, p: f64 }

fn sn1_h(c: *Sn1Root, q: f64) -> f64 { ret psn1(c.a, q, c.mu, c.sigma, c.nu) }

fn sn1_h1(c: *Sn1Root, q: f64) -> f64 { ret psn1(c.a, q, c.mu, c.sigma, c.nu) - c.p }

fn qsn1(a: *mem.Arena, p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p <= 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p >= 1.0f64 { ret 1.0f64 / 0.0f64 }
    var c: Sn1Root = zero
    c.a = a
    c.mu = mu
    c.sigma = sigma
    c.nu = nu
    c.p = p
    var lo = 0.0f64
    var hi = 0.0f64
    if sn1_h(&c, mu) < p {
        lo = mu
        hi = mu + sigma
        var j = 2.0f64
        while sn1_h(&c, hi) < p {
            hi = mu + j * sigma
            j += 1.0f64
        }
    } else {
        lo = mu - sigma
        hi = mu
        var j = 2.0f64
        while sn1_h(&c, lo) > p {
            lo = mu - j * sigma
            j += 1.0f64
        }
    }
    ret pw.zeroin[Sn1Root](&c, sn1_h1, lo, hi, pw.uniroot_tol(), 1000i64)
}

// SEP3 and SN2 (SEP3 at tau = 2) and SEP4 distributions and quantiles in closed form through the gamma distribution; pSEP2 by the integrate route
fn psep3(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if tau > 10000.0f64 { ret (x - (mu - sigma / nu)) / (sigma * (1.0f64 / nu + nu)) }
    let k = nu * nu
    let sc = math.pow[f64](2.0f64, 1.0f64 / tau)
    var c = 0.0f64
    if x < mu {
        let s1 = math.pow[f64](math.abs[f64](nu * (x - mu) / (sigma * sc)), tau)
        c = 1.0f64 - nm.pgamma(s1, 1.0f64 / tau, 1.0f64, true, false)
    } else {
        let s2 = math.pow[f64](math.abs[f64]((x - mu) / (sigma * nu * sc)), tau)
        c = 1.0f64 + k * nm.pgamma(s2, 1.0f64 / tau, 1.0f64, true, false)
    }
    ret c / (1.0f64 + k)
}

fn qsep3(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    let k = nu * nu
    let sc = math.pow[f64](2.0f64, 1.0f64 / tau)
    if p < 1.0f64 / (1.0f64 + k) { ret mu - (sigma * sc / nu) * math.pow[f64](nm.qgamma(1.0f64 - p * (1.0f64 + k), 1.0f64 / tau, 1.0f64, true, false), 1.0f64 / tau) }
    ret mu + (sigma * nu * sc) * math.pow[f64](nm.qgamma((0.0f64 - 1.0f64 / k) * (1.0f64 - p * (1.0f64 + k)), 1.0f64 / tau, 1.0f64, true, false), 1.0f64 / tau)
}

fn psn2(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret psep3(x, mu, sigma, nu, 2.0f64) }

fn qsn2(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret qsep3(p, mu, sigma, nu, 2.0f64) }

fn sep4_k(nu: f64, tau: f64) -> f64 { ret math.exp[f64](sp.lgamma(1.0f64 + 1.0f64 / tau) - sp.lgamma(1.0f64 + 1.0f64 / nu)) }

fn psep4(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let k = sep4_k(nu, tau)
    let z = (x - mu) / sigma
    var c = 0.0f64
    if x < mu { c = 1.0f64 - nm.pgamma(math.pow[f64](math.abs[f64](z), nu), 1.0f64 / nu, 1.0f64, true, false) } else { c = 1.0f64 + k * nm.pgamma(math.pow[f64](math.abs[f64](z), tau), 1.0f64 / tau, 1.0f64, true, false) }
    ret c / (1.0f64 + k)
}

fn qsep4(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    let k = sep4_k(nu, tau)
    if p < 1.0f64 / (1.0f64 + k) { ret mu - sigma * math.pow[f64](nm.qgamma(1.0f64 - p * (1.0f64 + k), 1.0f64 / nu, 1.0f64, true, false), 1.0f64 / nu) }
    ret mu + sigma * math.pow[f64](nm.qgamma((0.0f64 - 1.0f64 / k) * (1.0f64 - p * (1.0f64 + k)), 1.0f64 / tau, 1.0f64, true, false), 1.0f64 / tau)
}

fn psep2(a: *mem.Arena, x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let c = pint(a, 3usize, x, mu, sigma, nu, tau)
    if c >= 1.0f64 { ret 0.99999f64 }
    ret c
}

// PIG: Poisson inverse Gaussian (mean mu, sigma the inverse-Gaussian dispersion), the probability function through the modified Bessel function K of half-integer
// order, which the recurrence K(v + 1) = K(v - 1) + 2 v K(v) / alpha builds from K(1/2) (scaled by exp(alpha) to stay in range); the distribution is the sum
fn dpig(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let al = math.sqrt[f64](1.0f64 / (sigma * sigma) + 2.0f64 * mu / sigma)
    let kh = math.sqrt[f64](pi() / (2.0f64 * al))
    // k_prev = K(-1/2), k_cur = K(1/2), both times exp(alpha)
    var k_prev = kh
    var k_cur = kh
    var j = 1.0f64
    // after the loop k_cur is K(x - 1/2) exp(alpha)
    while j < x {
        let nxt = k_prev + (2.0f64 * (j - 0.5f64) / al) * k_cur
        k_prev = k_cur
        k_cur = nxt
        j += 1.0f64
    }
    let a1 = mu + 1.0f64 / (2.0f64 * sigma)
    let b1 = 1.0f64 / (2.0f64 * sigma)
    let nu = x - 0.5f64
    ret math.exp[f64](x * math.log[f64](mu) - sp.lgamma(x + 1.0f64) - 0.5f64 * math.log[f64](2.0f64 * pi() * sigma) + 1.0f64 / sigma - al + math.log[f64](2.0f64) + 0.5f64 * nu * math.log[f64](b1 / a1) + math.log[f64](k_cur))
}

fn ppig(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    var s = 0.0f64
    var j = 0.0f64
    while j <= x {
        s += dpig(j, mu, sigma)
        j += 1.0f64
    }
    ret s
}

// zero-adjusted and zero-inflated PIG (ZAPIG, ZIPIG, nu the zero mass), PIG2, NBF and ZINBF (tau the zero mass)
fn dzapig(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu }
    ret (1.0f64 - nu) * dpig(x, mu, sigma) / (1.0f64 - dpig(0.0f64, mu, sigma))
}

fn pzapig(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu }
    let c0 = ppig(0.0f64, mu, sigma)
    ret nu + (1.0f64 - nu) * (ppig(x, mu, sigma) - c0) / (1.0f64 - c0)
}

fn dzipig(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    var f = 0.0f64
    if sigma > 0.0001f64 { f = dpig(x, mu, sigma) } else { f = nm.dpois(x, mu, false) }
    if x == 0.0f64 { ret nu + (1.0f64 - nu) * f }
    ret (1.0f64 - nu) * f
}

fn pzipig(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    var c = 0.0f64
    if sigma > 0.0001f64 { c = ppig(x, mu, sigma) } else { c = nm.ppois(x, mu, true, false) }
    ret nu + (1.0f64 - nu) * c
}

fn dpig2(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret dpig(x, mu, 1.0f64 / (math.sqrt[f64](mu * mu + sigma * sigma) - mu))
}

fn dnbf(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let s1 = sigma * math.pow[f64](mu, nu - 2.0f64)
    if s1 <= 0.0001f64 { ret nm.dpois(x, mu, false) }
    ret nb.dnbinom_mu(x, 1.0f64 / s1, mu, false)
}

fn dzinbf(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let f = dnbf(x, mu, sigma, nu)
    if x == 0.0f64 { ret tau + (1.0f64 - tau) * f }
    ret (1.0f64 - tau) * f
}

// ZIPF and ZAZIPF: the zeta function gamlss.dist uses (zetaP: twelve terms and the Euler-Maclaurin remainder with eight Bernoulli terms)
fn zeta_aux(shape: f64, aa: f64) -> f64 {
    var ans = 1.0f64 / ((shape - 1.0f64) * math.pow[f64](1.0f64 + aa, shape - 1.0f64)) + 0.5f64 / math.pow[f64](1.0f64 + aa, shape)
    var term = (shape / 2.0f64) / math.pow[f64](1.0f64 + aa, shape + 1.0f64)
    ans += term * (1.0f64 / 6.0f64)
    var mm = 2.0f64
    while mm <= 8.0f64 {
        term = term * (shape + 2.0f64 * mm - 3.0f64) * (shape + 2.0f64 * mm - 2.0f64) / ((2.0f64 * mm - 1.0f64) * 2.0f64 * mm * (1.0f64 + aa) * (1.0f64 + aa))
        var b2 = 0.0f64
        if mm == 2.0f64 { b2 = 0.0f64 - 1.0f64 / 30.0f64 }
        if mm == 3.0f64 { b2 = 1.0f64 / 42.0f64 }
        if mm == 4.0f64 { b2 = 0.0f64 - 1.0f64 / 30.0f64 }
        if mm == 5.0f64 { b2 = 5.0f64 / 66.0f64 }
        if mm == 6.0f64 { b2 = 0.0f64 - 691.0f64 / 2730.0f64 }
        if mm == 7.0f64 { b2 = 7.0f64 / 6.0f64 }
        if mm == 8.0f64 { b2 = 0.0f64 - 3617.0f64 / 510.0f64 }
        ans += term * b2
        mm += 1.0f64
    }
    ret ans
}

fn zeta_p(x: f64) -> f64 {
    var ans = 0.0f64
    var ii = 0.0f64
    while ii < 12.0f64 {
        ans += 1.0f64 / math.pow[f64](1.0f64 + ii, x)
        ii += 1.0f64
    }
    ret ans + zeta_aux(x, 12.0f64)
}

fn dzipf(x: f64, mu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](0.0f64 - (mu + 1.0f64) * math.log[f64](x) - math.log[f64](zeta_p(mu + 1.0f64)))
}

fn pzipf(x: f64, mu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let qf = math.floor[f64](x)
    var ans = 0.0f64
    var nn = 1.0f64
    while nn <= 11.0f64 {
        if nn <= qf { ans += 1.0f64 / math.pow[f64](nn, mu + 1.0f64) }
        nn += 1.0f64
    }
    if 11.0f64 <= qf { ans = zeta_p(mu + 1.0f64) - zeta_aux(mu + 1.0f64, qf + 1.0f64) }
    ret ans / zeta_p(mu + 1.0f64)
}

fn dzazipf(x: f64, mu: f64, sigma: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret sigma }
    ret (1.0f64 - sigma) * dzipf(x, mu)
}

// GT (generalised t), NET (normal exponential t) and LQNO densities; pGT integrates over (-Inf, z] at relative and absolute tolerance eps^0.4 and qGT is the
// package's bracket with uniroot at tol eps^0.4
fn dgt(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    let zt = math.pow[f64](math.abs[f64](z), tau)
    if nu < 1000000.0f64 {
        ret math.exp[f64](math.log[f64](tau) - math.log[f64](2.0f64 * sigma) - (1.0f64 / tau) * math.log[f64](nu) - sp.lgamma(1.0f64 / tau) - sp.lgamma(nu) + sp.lgamma(nu + 1.0f64 / tau) - (nu + 1.0f64 / tau) * math.log[f64](1.0f64 + zt / nu))
    }
    ret math.exp[f64](math.log[f64](tau) - math.log[f64](2.0f64 * sigma) - sp.lgamma(1.0f64 / tau) - zt)
}

type GtCtx = struct { nu: f64, tau: f64 }

fn gt_dens(c: *GtCtx, x: f64) -> f64 { ret dgt(x, 0.0f64, 1.0f64, c.nu, c.tau) }

fn eps04() -> f64 { ret math.pow[f64](2.220446049250313e-16f64, 0.4f64) }

fn pgt(a: *mem.Arena, x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var c: GtCtx = zero
    c.nu = nu
    c.tau = tau
    let end = (x - mu) / sigma
    let (r, e) = qp.qagi[GtCtx](a, &c, gt_dens, end, 0i64 - 1i64, eps04(), eps04(), 100usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if end > 0.0f64 && r.result < 0.001f64 { ret 1.0f64 }
    ret r.result
}

type GtRoot = struct { a: *mem.Arena, mu: f64, sigma: f64, nu: f64, tau: f64, p: f64 }

fn gt_h(c: *GtRoot, q: f64) -> f64 { ret pgt(c.a, q, c.mu, c.sigma, c.nu, c.tau) }

fn gt_h1(c: *GtRoot, q: f64) -> f64 { ret pgt(c.a, q, c.mu, c.sigma, c.nu, c.tau) - c.p }

fn qgt(a: *mem.Arena, p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p <= 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p >= 1.0f64 { ret 1.0f64 / 0.0f64 }
    var c: GtRoot = zero
    c.a = a
    c.mu = mu
    c.sigma = sigma
    c.nu = nu
    c.tau = tau
    c.p = p
    var lo = 0.0f64
    var hi = 0.0f64
    if gt_h(&c, mu) < p {
        lo = mu
        hi = mu + sigma
        var j = 2.0f64
        while gt_h(&c, hi) < p {
            hi = mu + j * sigma
            j += 1.0f64
        }
    } else {
        lo = mu - sigma
        hi = mu
        var j = 2.0f64
        while gt_h(&c, lo) > p {
            lo = mu - j * sigma
            j += 1.0f64
        }
    }
    ret pw.zeroin[GtRoot](&c, gt_h1, lo, hi, eps04(), 1000i64)
}

fn dnet(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let k1 = nu
    let k2 = tau
    let c1 = (1.0f64 - 2.0f64 * dist.pnorm(0.0f64 - k1, 0.0f64, 1.0f64, true, false)) * math.sqrt[f64](2.0f64 * pi())
    let c2 = (2.0f64 / k1) * math.exp[f64](0.0f64 - (k1 * k1) / 2.0f64)
    let c3 = 2.0f64 * math.exp[f64](0.0f64 - k1 * k2 + (k1 * k1) / 2.0f64) / ((k1 * k2 - 1.0f64) * k1)
    let ct = 1.0f64 / (c1 + c2 + c3)
    let tc = (x - mu) / sigma
    var d = 0.0f64
    let at = math.abs[f64](tc)
    if at <= k1 { d = 0.0f64 - (tc * tc) / 2.0f64 }
    if at > k1 && at <= k2 { d = 0.0f64 - k1 * at + (k1 * k1) / 2.0f64 }
    if at > k2 && x != 0.0f64 { d = 0.0f64 - k1 * k2 * math.log[f64](at / k2) - k1 * k2 + (k1 * k1) / 2.0f64 }
    ret math.exp[f64](math.log[f64](ct) - math.log[f64](sigma) + d)
}

fn dlqno(x: f64, mu: f64, sigma: f64) -> f64 { ret dist.dnorm(x, mu, math.sqrt[f64](mu * (1.0f64 + sigma * mu)), false) }

// SICHEL (the probability function through the modified Bessel function K of real order, e.algo.stat.gslfns.bessel_knu) and the GIG density
fn dsichel(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let s1 = 1.0f64 / sigma
    let c = gs.bessel_knu(nu + 1.0f64, s1) / gs.bessel_knu(nu, s1)
    let al = math.sqrt[f64](1.0f64 + 2.0f64 * sigma * (mu / c)) / sigma
    ret math.exp[f64](0.0f64 - sp.lgamma(x + 1.0f64) - (x + nu) * math.log[f64](sigma * al) + x * math.log[f64](mu / c) + math.log[f64](gs.bessel_knu(x + nu, al)) - math.log[f64](gs.bessel_knu(nu, s1)))
}

fn dgig(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let s2 = 1.0f64 / (sigma * sigma)
    let c = gs.bessel_knu(nu + 1.0f64, s2) / gs.bessel_knu(nu, s2)
    ret math.exp[f64](nu * math.log[f64](c) - nu * math.log[f64](mu) + (nu - 1.0f64) * math.log[f64](x) - math.log[f64](2.0f64) - math.log[f64](gs.bessel_knu(nu, s2)) - s2 / 2.0f64 * (c * x / mu + mu / (c * x)))
}

// pGIG integrates the standard GIG density over (0.001, q / mu) with integrate() defaults (QUADPACK qags, tolerance eps^0.25); qGIG is the package's bracket and zeroin
type GigCtx = struct { sigma: f64, nu: f64 }

fn gig_dens(c: *GigCtx, x: f64) -> f64 { ret dgig(x, 1.0f64, c.sigma, c.nu) }

fn pgig(a: *mem.Arena, x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    var c: GigCtx = zero
    c.sigma = sigma
    c.nu = nu
    let tol = pw.uniroot_tol()
    let (r, e) = qp.qags[GigCtx](a, &c, gig_dens, 0.001f64, x / mu, tol, tol, 100usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret r.result
}

type GigRoot = struct { a: *mem.Arena, mu: f64, sigma: f64, nu: f64, p: f64 }

fn gig_h(c: *GigRoot, q: f64) -> f64 { ret pgig(c.a, q, c.mu, c.sigma, c.nu) }

fn gig_h1(c: *GigRoot, q: f64) -> f64 { ret pgig(c.a, q, c.mu, c.sigma, c.nu) - c.p }

fn qgig(a: *mem.Arena, p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p <= 0.0f64 { ret 0.0f64 }
    if p >= 1.0f64 { ret 1.0f64 / 0.0f64 }
    var c: GigRoot = zero
    c.a = a
    c.mu = mu
    c.sigma = sigma
    c.nu = nu
    c.p = p
    var lo = 0.0f64
    var hi = 0.0f64
    if gig_h(&c, mu) < p {
        lo = mu
        hi = mu + sigma
        var j = 2.0f64
        while gig_h(&c, hi) < p {
            hi = mu + j * sigma
            j += 1.0f64
        }
    } else {
        lo = 2.2250738585072014e-308f64
        hi = mu
    }
    ret pw.zeroin[GigRoot](&c, gig_h1, lo, hi, pw.uniroot_tol(), 1000i64)
}

// BEOI, BEZI (beta with the point mass nu at 1 or at 0, shapes mu sigma and (1 - mu) sigma) and BEINF0, BEINF1, BEINF (masses relative to the beta part, shapes as BE)
fn dbeoi(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x <= 0.0f64 || x > 1.0f64 { ret 0.0f64 }
    if x == 1.0f64 { ret nu }
    ret (1.0f64 - nu) * nb.dbeta(x, mu * sigma, (1.0f64 - mu) * sigma, false)
}

fn pbeoi(q: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if q <= 0.0f64 { ret 0.0f64 }
    if q >= 1.0f64 { ret 1.0f64 }
    ret (1.0f64 - nu) * nb.pbeta(q, mu * sigma, (1.0f64 - mu) * sigma, true, false)
}

fn qbeoi(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if p == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 }
    if p <= 1.0f64 - nu { ret nb.qbeta(p / (1.0f64 - nu), mu * sigma, (1.0f64 - mu) * sigma, true, false) }
    ret 1.0f64
}

fn dbezi(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 || x >= 1.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu }
    ret (1.0f64 - nu) * nb.dbeta(x, mu * sigma, (1.0f64 - mu) * sigma, false)
}

fn pbezi(q: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    if q == 0.0f64 { ret nu }
    if q >= 1.0f64 { ret 1.0f64 }
    ret nu + (1.0f64 - nu) * nb.pbeta(q, mu * sigma, (1.0f64 - mu) * sigma, true, false)
}

fn qbezi(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    if nu >= p { ret 0.0f64 }
    ret nb.qbeta((p - nu) / (1.0f64 - nu), mu * sigma, (1.0f64 - mu) * sigma, true, false)
}

fn binf_a(mu: f64, sigma: f64) -> f64 { ret mu * (1.0f64 - sigma * sigma) / (sigma * sigma) }

fn dbeinf0(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 || x >= 1.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu / (1.0f64 + nu) }
    let a = binf_a(mu, sigma)
    ret nb.dbeta(x, a, a * (1.0f64 - mu) / mu, false) / (1.0f64 + nu)
}

fn pbeinf0(q: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    if q >= 1.0f64 { ret 1.0f64 }
    if q == 0.0f64 { ret nu / (1.0f64 + nu) }
    let a = binf_a(mu, sigma)
    ret (nu + nb.pbeta(q, a, a * (1.0f64 - mu) / mu, true, false)) / (1.0f64 + nu)
}

fn qbeinf0(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    if p <= nu / (1.0f64 + nu) { ret 0.0f64 }
    let a = binf_a(mu, sigma)
    ret nb.qbeta((p - nu / (1.0f64 + nu)) * (1.0f64 + nu), a, a * (1.0f64 - mu) / mu, true, false)
}

fn dbeinf1(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x <= 0.0f64 || x > 1.0f64 { ret 0.0f64 }
    if x == 1.0f64 { ret nu / (1.0f64 + nu) }
    let a = binf_a(mu, sigma)
    ret nb.dbeta(x, a, a * (1.0f64 - mu) / mu, false) / (1.0f64 + nu)
}

fn pbeinf1(q: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if q <= 0.0f64 { ret 0.0f64 }
    if q >= 1.0f64 { ret 1.0f64 }
    let a = binf_a(mu, sigma)
    ret nb.pbeta(q, a, a * (1.0f64 - mu) / mu, true, false) / (1.0f64 + nu)
}

fn qbeinf1(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if p == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 }
    if p >= 1.0f64 / (1.0f64 + nu) { ret 1.0f64 }
    let a = binf_a(mu, sigma)
    ret nb.qbeta(p * (1.0f64 + nu), a, a * (1.0f64 - mu) / mu, true, false)
}

fn dbeinf(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x < 0.0f64 || x > 1.0f64 { ret 0.0f64 }
    let t = 1.0f64 + nu + tau
    if x == 0.0f64 { ret nu / t }
    if x == 1.0f64 { ret tau / t }
    let a = binf_a(mu, sigma)
    ret nb.dbeta(x, a, a * (1.0f64 - mu) / mu, false) / t
}

fn pbeinf(q: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    if q > 1.0f64 { ret 1.0f64 }
    let t = 1.0f64 + nu + tau
    if q == 0.0f64 { ret nu / t }
    if q == 1.0f64 { ret 1.0f64 }
    let a = binf_a(mu, sigma)
    ret (nu + nb.pbeta(q, a, a * (1.0f64 - mu) / mu, true, false)) / t
}

fn qbeinf(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 }
    let t = 1.0f64 + nu + tau
    if p >= (1.0f64 + nu) / t { ret 1.0f64 }
    if p <= nu / t { ret 0.0f64 }
    let a = binf_a(mu, sigma)
    ret nb.qbeta((p - nu / t) * t, a, a * (1.0f64 - mu) / mu, true, false)
}

// GB1 (generalised beta of the first kind), SIMPLEX density, and BCPE (Box-Cox power exponential) d, p, q
fn gb1_ab(mu: f64, sigma: f64) -> (f64, f64) {
    let a = mu * (1.0f64 / (sigma * sigma) - 1.0f64)
    ret (a, a * (1.0f64 - mu) / mu)
}

fn dgb1(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x <= 0.0f64 || x >= 1.0f64 { ret 0.0f64 }
    let (a, b) = gb1_ab(mu, sigma)
    let ll = math.log[f64](tau) + b * math.log[f64](nu) + (tau * a - 1.0f64) * math.log[f64](x) + (b - 1.0f64) * math.log[f64](1.0f64 - math.pow[f64](x, tau)) - sp.lgamma(a) - sp.lgamma(b) + sp.lgamma(a + b) - (a + b) * math.log[f64](nu + (1.0f64 - nu) * math.pow[f64](x, tau))
    ret math.exp[f64](ll)
}

fn pgb1(q: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if q <= 0.0f64 { ret 0.0f64 }
    if q >= 1.0f64 { ret 1.0f64 }
    let (a, b) = gb1_ab(mu, sigma)
    let qt = math.pow[f64](q, tau)
    ret nb.pbeta(qt / (nu + (1.0f64 - nu) * qt), a, b, true, false)
}

fn dsimplex(x: f64, mu: f64, sigma: f64) -> f64 {
    if x <= 0.0f64 || x >= 1.0f64 { ret 0.0f64 }
    let r = (x - mu) / (mu * (1.0f64 - mu))
    ret math.exp[f64](0.0f64 - r * r / (2.0f64 * x * (1.0f64 - x) * sigma * sigma) - (math.log[f64](2.0f64 * pi() * sigma * sigma) + 3.0f64 * (math.log[f64](x) + math.log[f64](1.0f64 - x))) / 2.0f64)
}

fn bcpe_ft_cdf(t: f64, tau: f64) -> f64 {
    let c = pe_c(tau)
    let sh = 0.5f64 * math.pow[f64](math.abs[f64](t / c), tau)
    var sg = 1.0f64
    if t < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if t == 0.0f64 { sg = 0.0f64 }
    ret 0.5f64 * (1.0f64 + nm.pgamma(sh, 1.0f64 / tau, 1.0f64, true, false) * sg)
}

fn bcpe_z(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if nu != 0.0f64 { ret (math.pow[f64](x / mu, nu) - 1.0f64) / (nu * sigma) }
    ret math.log[f64](x / mu) / sigma
}

fn dbcpe(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let c = pe_c(tau)
    let z = bcpe_z(x, mu, sigma, nu)
    let lc = math.log[f64](c)
    let lft = math.log[f64](tau) - lc - 0.5f64 * math.pow[f64](math.abs[f64](z / c), tau) - (1.0f64 + 1.0f64 / tau) * math.log[f64](2.0f64) - sp.lgamma(1.0f64 / tau)
    let lfz = lft - math.log[f64](bcpe_ft_cdf(1.0f64 / (sigma * math.abs[f64](nu)), tau))
    ret math.exp[f64]((nu - 1.0f64) * math.log[f64](x) - nu * math.log[f64](mu) - math.log[f64](sigma) + lfz)
}

fn pbcpe(q: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if q <= 0.0f64 { ret 0.0f64 }
    let z = bcpe_z(q, mu, sigma, nu)
    let f1 = bcpe_ft_cdf(z, tau)
    var f2 = 0.0f64
    if nu > 0.0f64 { f2 = bcpe_ft_cdf(0.0f64 - 1.0f64 / (sigma * math.abs[f64](nu)), tau) }
    let f3 = bcpe_ft_cdf(1.0f64 / (sigma * math.abs[f64](nu)), tau)
    ret (f1 - f2) / f3
}

fn bcpe_qt(p: f64, tau: f64) -> f64 {
    let c = pe_c(tau)
    var sg = 1.0f64
    if p < 0.5f64 { sg = 0.0f64 - 1.0f64 }
    if p == 0.5f64 { sg = 0.0f64 }
    let s = nm.qgamma((2.0f64 * p - 1.0f64) * sg, 1.0f64 / tau, 1.0f64, true, false)
    ret sg * math.pow[f64](2.0f64 * s, 1.0f64 / tau) * c
}

fn qbcpe(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    var za = 0.0f64
    if nu < 0.0f64 { za = bcpe_qt(p * bcpe_ft_cdf(1.0f64 / (sigma * math.abs[f64](nu)), tau), tau) }
    if nu == 0.0f64 { za = bcpe_qt(p, tau) }
    if nu > 0.0f64 { za = bcpe_qt(1.0f64 - (1.0f64 - p) * bcpe_ft_cdf(1.0f64 / (sigma * math.abs[f64](nu)), tau), tau) }
    if nu != 0.0f64 { ret mu * math.pow[f64](nu * sigma * za + 1.0f64, 1.0f64 / nu) }
    ret mu * math.exp[f64](sigma * za)
}

// SST (skew t with the first two moments standardised, through ST3), PE2 (power exponential with scale sigma), NOF (normal with variance sigma^2 |mu|^nu) and ZAIG (zero-adjusted inverse Gaussian) d, p, q
fn sst_mu(mu: f64, sigma: f64, nu: f64, tau: f64) -> (f64, f64) {
    let m1 = (2.0f64 * math.sqrt[f64](tau) * (nu * nu - 1.0f64)) / ((tau - 1.0f64) * math.exp[f64](lbeta_(0.5f64, tau / 2.0f64)) * nu)
    let m2 = (tau * (nu * nu * nu + 1.0f64 / (nu * nu * nu))) / ((tau - 2.0f64) * (nu + 1.0f64 / nu))
    let s1 = math.sqrt[f64](m2 - m1 * m1)
    ret (mu - sigma * m1 / s1, sigma / s1)
}

fn dsst(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let (m, sg) = sst_mu(mu, sigma, nu, tau)
    ret dst3(x, m, sg, nu, tau)
}

fn psst(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let (m, sg) = sst_mu(mu, sigma, nu, tau)
    ret pst3(x, m, sg, nu, tau)
}

fn qsst(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    let (m, sg) = sst_mu(mu, sigma, nu, tau)
    ret qst3(p, m, sg, nu, tau)
}

fn dpe2(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    let z = (x - mu) / sigma
    ret math.exp[f64](0.0f64 - math.log[f64](sigma) + math.log[f64](nu) - math.log[f64](2.0f64) - math.pow[f64](math.abs[f64](z), nu) - sp.lgamma(1.0f64 / nu))
}

fn ppe2(q: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if nu > 10000.0f64 { ret (q - (mu - sigma)) / (2.0f64 * sigma) }
    let z = (q - mu) / sigma
    var sg = 1.0f64
    if z < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if z == 0.0f64 { sg = 0.0f64 }
    ret 0.5f64 * (1.0f64 + nm.pgamma(math.pow[f64](math.abs[f64](z), nu), 1.0f64 / nu, 1.0f64, true, false) * sg)
}

fn qpe2(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if p == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    var sg = 1.0f64
    if p < 0.5f64 { sg = 0.0f64 - 1.0f64 }
    if p == 0.5f64 { sg = 0.0f64 }
    let sh = nm.qgamma((2.0f64 * p - 1.0f64) * sg, 1.0f64 / nu, 1.0f64, true, false)
    ret mu + sigma * sg * math.pow[f64](sh, 1.0f64 / nu)
}

fn dnof(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret dist.dnorm(x, mu, sigma * math.pow[f64](math.abs[f64](mu), nu / 2.0f64), false) }

fn dzaig(x: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x == 0.0f64 { ret nu }
    ret math.exp[f64](math.log[f64](1.0f64 - nu) - 0.5f64 * math.log[f64](2.0f64 * pi()) - math.log[f64](sigma) - 1.5f64 * math.log[f64](x) - (x - mu) * (x - mu) / (2.0f64 * sigma * sigma * mu * mu * x))
}

fn pzaig(q: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    if q == 0.0f64 { ret nu }
    let c1 = dist.pnorm(((q / mu) - 1.0f64) / (sigma * math.sqrt[f64](q)), 0.0f64, 1.0f64, true, false)
    let c2 = math.exp[f64](2.0f64 / (mu * sigma * sigma)) * dist.pnorm((0.0f64 - ((q / mu) + 1.0f64)) / (sigma * math.sqrt[f64](q)), 0.0f64, 1.0f64, true, false)
    ret nu + (1.0f64 - nu) * (c1 + c2)
}

// qIG and qZAIG (the package's bracket and uniroot on pIG), qGB1 (through qbeta), pSIMPLEX (integrate of the density over (0, q)) and qSIMPLEX (uniroot on (0.001, 0.999))
type IgRoot = struct { mu: f64, sigma: f64, p: f64 }

fn ig_h1(c: *IgRoot, q: f64) -> f64 { ret pig(q, c.mu, c.sigma) - c.p }

fn qig(p: f64, mu: f64, sigma: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    var c: IgRoot = zero
    c.mu = mu
    c.sigma = sigma
    c.p = p
    var lo = 0.0f64
    var hi = 0.0f64
    if pig(mu, mu, sigma) < p {
        lo = mu
        hi = mu + sigma
        var j = 2.0f64
        while pig(hi, mu, sigma) < p {
            hi = mu + j * sigma
            j += 1.0f64
        }
    } else {
        lo = 2.2250738585072014e-308f64
        hi = mu
    }
    ret pw.zeroin[IgRoot](&c, ig_h1, lo, hi, pw.uniroot_tol(), 1000i64)
}

fn qzaig(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if p > nu { ret qig((p - nu) / (1.0f64 - nu), mu, sigma) }
    ret 0.0f64
}

fn qgb1(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 }
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    let (aa, bb) = gb1_ab(mu, sigma)
    let z = nb.qbeta(p, aa, bb, true, false)
    ret math.pow[f64](nu / (1.0f64 / z - (1.0f64 - nu)), 1.0f64 / tau)
}

type SimpCtx = struct { mu: f64, sigma: f64 }

fn simp_pdf(c: *SimpCtx, x: f64) -> f64 { ret 1.0f64 / math.sqrt[f64](2.0f64 * pi() * c.sigma * c.sigma * math.pow[f64](x * (1.0f64 - x), 3.0f64)) * math.exp[f64](0.0f64 - 0.5f64 / (c.sigma * c.sigma) * (x - c.mu) * (x - c.mu) / (x * (1.0f64 - x) * c.mu * c.mu * (1.0f64 - c.mu) * (1.0f64 - c.mu))) }

fn psimplex(a: *mem.Arena, q: f64, mu: f64, sigma: f64) -> f64 {
    if q <= 0.0f64 { ret 0.0f64 }
    if q >= 1.0f64 { ret 1.0f64 }
    var c: SimpCtx = zero
    c.mu = mu
    c.sigma = sigma
    let tol = pw.uniroot_tol()
    let (r, e) = qp.qags[SimpCtx](a, &c, simp_pdf, 0.0f64, q, tol, tol, 100usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret r.result
}

type SimpRoot = struct { a: *mem.Arena, mu: f64, sigma: f64, p: f64 }

fn simp_h1(c: *SimpRoot, x: f64) -> f64 { ret psimplex(c.a, x, c.mu, c.sigma) - c.p }

fn qsimplex(a: *mem.Arena, p: f64, mu: f64, sigma: f64) -> f64 {
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    if p < 1.0e-10f64 { ret 0.0f64 }
    if 1.0f64 - p < 1.0e-10f64 { ret 1.0f64 }
    var c: SimpRoot = zero
    c.a = a
    c.mu = mu
    c.sigma = sigma
    c.p = p
    ret pw.zeroin[SimpRoot](&c, simp_h1, 0.001f64, 0.999f64, pw.uniroot_tol(), 1000i64)
}

// LOGSHASH (the log of a SHASH), BCPEo (the package's BCPEo is BCPE's formula) and ST1 (skew t of Azzalini, through the t and normal densities)
fn dlogshash(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](math.log[f64](dshash(math.log[f64](x), mu, sigma, nu, tau)) - math.log[f64](x))
}

fn plogshash(q: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if q <= 0.0f64 { ret 0.0f64 }
    if q == 1.0f64 / 0.0f64 { ret 1.0f64 }
    ret pshash(math.log[f64](q), mu, sigma, nu, tau)
}

fn qlogshash(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p == 0.0f64 { ret 0.0f64 }
    if p == 1.0f64 { ret 1.0f64 / 0.0f64 }
    if p < 0.0f64 || p > 1.0f64 { ret 0.0f64 / 0.0f64 }
    ret math.exp[f64](qshash(p, mu, sigma, nu, tau))
}

fn dbcpeo(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret dbcpe(x, mu, sigma, nu, tau) }

fn pbcpeo(q: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret pbcpe(q, mu, sigma, nu, tau) }

fn qbcpeo(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret qbcpe(p, mu, sigma, nu, tau) }

fn dst1(x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let z = (x - mu) / sigma
    let w = nu * z
    if tau < 1000000.0f64 {
        ret math.exp[f64](nb.pt(w, tau, true, true) + nb.dt(z, tau, true) + math.log[f64](2.0f64) - math.log[f64](sigma))
    }
    ret math.exp[f64](dist.pnorm(w, 0.0f64, 1.0f64, true, true) + dist.dnorm(z, 0.0f64, 1.0f64, true) + math.log[f64](2.0f64) - math.log[f64](sigma))
}
