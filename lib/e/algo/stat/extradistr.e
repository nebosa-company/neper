// R extraDistr, the closed-form continuous distributions: density `*_d`, distribution function `*_p` and quantile `*_q` of the Gumbel,
// Frechet, Kumaraswamy, Laplace, Lomax, Pareto, Rayleigh, triangular, Gompertz, power, inverse gamma, half-normal, half-Cauchy,
// Birnbaum-Saunders (fatigue life), Wald and beta-prime distributions, with the package's parameterisations.
//
// Not here: the discrete and multivariate distributions, the random generators and the other continuous families.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.algo.stat.gslfns as gsl
use e.algo.rand.r as rng

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pn(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }

fn qn(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

// Gumbel(mu, sigma)
fn gumbel_d(x: f64, mu: f64, s: f64) -> f64 {
    let z = (x - mu) / s
    ret math.exp[f64](0.0f64 - z - math.exp[f64](0.0f64 - z)) / s
}
fn gumbel_p(x: f64, mu: f64, s: f64) -> f64 { ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - (x - mu) / s)) }
fn gumbel_q(p: f64, mu: f64, s: f64) -> f64 { ret mu - s * math.log[f64](0.0f64 - math.log[f64](p)) }

// Frechet(lambda, mu, sigma)
fn frechet_d(x: f64, l: f64, mu: f64, s: f64) -> f64 {
    if x <= mu { ret 0.0f64 }
    let z = (x - mu) / s
    ret l / s * math.pow[f64](z, 0.0f64 - 1.0f64 - l) * math.exp[f64](0.0f64 - math.pow[f64](z, 0.0f64 - l))
}
fn frechet_p(x: f64, l: f64, mu: f64, s: f64) -> f64 {
    if x <= mu { ret 0.0f64 }
    ret math.exp[f64](0.0f64 - math.pow[f64]((x - mu) / s, 0.0f64 - l))
}
fn frechet_q(p: f64, l: f64, mu: f64, s: f64) -> f64 { ret mu + s * math.pow[f64](0.0f64 - math.log[f64](p), 0.0f64 - 1.0f64 / l) }

// Kumaraswamy(a, b) on (0, 1)
fn kumar_d(x: f64, a: f64, b: f64) -> f64 {
    if x <= 0.0f64 || x >= 1.0f64 { ret 0.0f64 }
    ret a * b * math.pow[f64](x, a - 1.0f64) * math.pow[f64](1.0f64 - math.pow[f64](x, a), b - 1.0f64)
}
fn kumar_p(x: f64, a: f64, b: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    if x >= 1.0f64 { ret 1.0f64 }
    ret 1.0f64 - math.pow[f64](1.0f64 - math.pow[f64](x, a), b)
}
fn kumar_q(p: f64, a: f64, b: f64) -> f64 { ret math.pow[f64](1.0f64 - math.pow[f64](1.0f64 - p, 1.0f64 / b), 1.0f64 / a) }

// Laplace(mu, sigma)
fn laplace_d(x: f64, mu: f64, s: f64) -> f64 { ret math.exp[f64](0.0f64 - math.abs[f64](x - mu) / s) / (2.0f64 * s) }
fn laplace_p(x: f64, mu: f64, s: f64) -> f64 {
    let z = (x - mu) / s
    if z < 0.0f64 { ret 0.5f64 * math.exp[f64](z) }
    ret 1.0f64 - 0.5f64 * math.exp[f64](0.0f64 - z)
}
fn laplace_q(p: f64, mu: f64, s: f64) -> f64 {
    if p < 0.5f64 { ret mu + s * math.log[f64](2.0f64 * p) }
    ret mu - s * math.log[f64](2.0f64 * (1.0f64 - p))
}

// Lomax(lambda, kappa): F = 1 - (1 + lambda x)^-kappa
fn lomax_d(x: f64, l: f64, k: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret k * l / math.pow[f64](1.0f64 + l * x, k + 1.0f64)
}
fn lomax_p(x: f64, l: f64, k: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 1.0f64 - math.pow[f64](1.0f64 + l * x, 0.0f64 - k)
}
fn lomax_q(p: f64, l: f64, k: f64) -> f64 { ret (math.pow[f64](1.0f64 - p, 0.0f64 - 1.0f64 / k) - 1.0f64) / l }

// Pareto(a, b): F = 1 - (b / x)^a, x >= b
fn pareto_d(x: f64, a: f64, b: f64) -> f64 {
    if x < b { ret 0.0f64 }
    ret a * math.pow[f64](b, a) / math.pow[f64](x, a + 1.0f64)
}
fn pareto_p(x: f64, a: f64, b: f64) -> f64 {
    if x < b { ret 0.0f64 }
    ret 1.0f64 - math.pow[f64](b / x, a)
}
fn pareto_q(p: f64, a: f64, b: f64) -> f64 { ret b * math.pow[f64](1.0f64 - p, 0.0f64 - 1.0f64 / a) }

// Rayleigh(sigma)
fn rayleigh_d(x: f64, s: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret x / (s * s) * math.exp[f64](0.0f64 - x * x / (2.0f64 * s * s))
}
fn rayleigh_p(x: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 1.0f64 - math.exp[f64](0.0f64 - x * x / (2.0f64 * s * s))
}
fn rayleigh_q(p: f64, s: f64) -> f64 { ret s * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](1.0f64 - p)) }

// triangular(a, b, c) with mode c
fn triang_d(x: f64, a: f64, b: f64, c: f64) -> f64 {
    if x <= a || x >= b { ret 0.0f64 }
    if x < c { ret 2.0f64 * (x - a) / ((b - a) * (c - a)) }
    if x == c { ret 2.0f64 / (b - a) }
    ret 2.0f64 * (b - x) / ((b - a) * (b - c))
}
fn triang_p(x: f64, a: f64, b: f64, c: f64) -> f64 {
    if x <= a { ret 0.0f64 }
    if x >= b { ret 1.0f64 }
    if x <= c { ret (x - a) * (x - a) / ((b - a) * (c - a)) }
    ret 1.0f64 - (b - x) * (b - x) / ((b - a) * (b - c))
}
fn triang_q(p: f64, a: f64, b: f64, c: f64) -> f64 {
    if p < (c - a) / (b - a) { ret a + math.sqrt[f64](p * (b - a) * (c - a)) }
    ret b - math.sqrt[f64]((1.0f64 - p) * (b - a) * (b - c))
}

// Gompertz(a, b): F = 1 - exp(-a / b (exp(b x) - 1)), a the rate and b the shape
fn gompertz_d(x: f64, a: f64, b: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret a * math.exp[f64](b * x) * math.exp[f64](0.0f64 - a / b * (math.exp[f64](b * x) - 1.0f64))
}
fn gompertz_p(x: f64, a: f64, b: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 1.0f64 - math.exp[f64](0.0f64 - a / b * (math.exp[f64](b * x) - 1.0f64))
}
fn gompertz_q(p: f64, a: f64, b: f64) -> f64 { ret math.log[f64](1.0f64 - b / a * math.log[f64](1.0f64 - p)) / b }

// power(alpha, beta): F = (x / alpha)^beta on (0, alpha), alpha the upper bound
fn power_d(x: f64, al: f64, be: f64) -> f64 {
    if x <= 0.0f64 || x >= al { ret 0.0f64 }
    ret be * math.pow[f64](x, be - 1.0f64) / math.pow[f64](al, be)
}
fn power_p(x: f64, al: f64, be: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    if x >= al { ret 1.0f64 }
    ret math.pow[f64](x / al, be)
}
fn power_q(p: f64, al: f64, be: f64) -> f64 { ret al * math.pow[f64](p, 1.0f64 / be) }

// inverse gamma(alpha, beta): density beta^alpha x^-(alpha + 1) exp(-beta / x) / gamma(alpha)
fn invgamma_d(x: f64, al: f64, be: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](al * math.log[f64](be) - (al + 1.0f64) * math.log[f64](x) - be / x - nm.lgammafn(al))
}
fn invgamma_p(x: f64, al: f64, be: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret nm.pgamma(be / x, al, 1.0f64, false, false)
}
fn invgamma_q(p: f64, al: f64, be: f64) -> f64 { ret be / nm.qgamma(p, al, 1.0f64, false, false) }

// half-normal(sigma) and half-Cauchy(sigma)
fn hnorm_d(x: f64, s: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret math.sqrt[f64](2.0f64 / pi()) / s * math.exp[f64](0.0f64 - x * x / (2.0f64 * s * s))
}
fn hnorm_p(x: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 2.0f64 * pn(x / s) - 1.0f64
}
fn hnorm_q(p: f64, s: f64) -> f64 { ret s * qn((p + 1.0f64) / 2.0f64) }

fn hcauchy_d(x: f64, s: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret 2.0f64 * s / (pi() * (x * x + s * s))
}
fn hcauchy_p(x: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 2.0f64 / pi() * math.atan[f64](x / s)
}
fn hcauchy_q(p: f64, s: f64) -> f64 { ret s * math.tan[f64](p * pi() / 2.0f64) }

// Birnbaum-Saunders / fatigue life (alpha, beta, mu)
fn fatigue_d(x: f64, al: f64, be: f64, mu: f64) -> f64 {
    if x <= mu { ret 0.0f64 }
    let y = x - mu
    let z = (math.sqrt[f64](y / be) - math.sqrt[f64](be / y)) / al
    ret (math.sqrt[f64](y / be) + math.sqrt[f64](be / y)) / (2.0f64 * al * y) * dist.dnorm(z, 0.0f64, 1.0f64, false)
}
fn fatigue_p(x: f64, al: f64, be: f64, mu: f64) -> f64 {
    if x <= mu { ret 0.0f64 }
    let y = x - mu
    ret pn((math.sqrt[f64](y / be) - math.sqrt[f64](be / y)) / al)
}
fn fatigue_q(p: f64, al: f64, be: f64, mu: f64) -> f64 {
    let z = al * qn(p) / 2.0f64
    let w = z + math.sqrt[f64](z * z + 1.0f64)
    ret mu + be * w * w
}

// Wald / inverse Gaussian (mu, lambda)
fn wald_d(x: f64, mu: f64, l: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret math.sqrt[f64](l / (2.0f64 * pi() * x * x * x)) * math.exp[f64](0.0f64 - l * (x - mu) * (x - mu) / (2.0f64 * mu * mu * x))
}
fn wald_p(x: f64, mu: f64, l: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let r = math.sqrt[f64](l / x)
    ret pn(r * (x / mu - 1.0f64)) + math.exp[f64](2.0f64 * l / mu) * pn(0.0f64 - r * (x / mu + 1.0f64))
}

// beta prime (alpha, beta, sigma)
fn betapr_d(x: f64, al: f64, be: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let z = x / s
    ret math.exp[f64]((al - 1.0f64) * math.log[f64](z) - (al + be) * math.log[f64](1.0f64 + z) - nb.lbeta(al, be)) / s
}
fn betapr_p(x: f64, al: f64, be: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let z = x / s
    ret nb.pbeta(z / (1.0f64 + z), al, be, true, false)
}
fn betapr_q(p: f64, al: f64, be: f64, s: f64) -> f64 {
    let u = nb.qbeta(p, al, be, true, false)
    ret s * u / (1.0f64 - u)
}

// Maxwell(sigma)
fn maxwell_d(x: f64, s: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret math.sqrt[f64](2.0f64 / pi()) * x * x * math.exp[f64](0.0f64 - x * x / (2.0f64 * s * s)) / (s * s * s)
}
fn maxwell_p(x: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret nm.pgamma(x * x / (2.0f64 * s * s), 1.5f64, 1.0f64, true, false)
}
fn maxwell_q(p: f64, s: f64) -> f64 { ret s * math.sqrt[f64](2.0f64 * nm.qgamma(p, 1.5f64, 1.0f64, true, false)) }

// beta-binomial(size n, alpha, beta)
fn bbinom_d(x: f64, n: f64, a: f64, b: f64) -> f64 {
    if x < 0.0f64 || x > n || x != math.floor[f64](x) { ret 0.0f64 }
    ret math.exp[f64](nb.lchoose_int(n, x) + nb.lbeta(x + a, n - x + b) - nb.lbeta(a, b))
}
fn bbinom_p(x: f64, n: f64, a: f64, b: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x >= n { ret 1.0f64 }
    var s = 0.0f64
    var k = 0.0f64
    while k <= math.floor[f64](x) {
        s += bbinom_d(k, n, a, b)
        k += 1.0f64
    }
    ret s
}

// beta-negative-binomial(size r, alpha, beta)
fn bnbinom_d(x: f64, r: f64, a: f64, b: f64) -> f64 {
    if x < 0.0f64 || x != math.floor[f64](x) { ret 0.0f64 }
    ret math.exp[f64](nm.lgammafn(r + x) - nm.lgammafn(x + 1.0f64) - nm.lgammafn(r) + nb.lbeta(a + r, b + x) - nb.lbeta(a, b))
}
fn bnbinom_p(x: f64, r: f64, a: f64, b: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    var s = 0.0f64
    var k = 0.0f64
    while k <= math.floor[f64](x) {
        s += bnbinom_d(k, r, a, b)
        k += 1.0f64
    }
    ret s
}

// discrete Laplace(scale p)
fn dlaplace_d(x: f64, p: f64) -> f64 {
    if x != math.floor[f64](x) { ret 0.0f64 }
    ret (1.0f64 - p) / (1.0f64 + p) * math.pow[f64](p, math.abs[f64](x))
}
fn dlaplace_p(x: f64, p: f64) -> f64 {
    let fx = math.floor[f64](x)
    if fx < 0.0f64 { ret math.pow[f64](p, 0.0f64 - fx) / (1.0f64 + p) }
    ret 1.0f64 - math.pow[f64](p, fx + 1.0f64) / (1.0f64 + p)
}

// logarithmic series(theta)
fn lgser_d(x: f64, th: f64) -> f64 {
    if x < 1.0f64 || x != math.floor[f64](x) { ret 0.0f64 }
    ret 0.0f64 - math.pow[f64](th, x) / (x * math.log[f64](1.0f64 - th))
}
fn lgser_p(x: f64, th: f64) -> f64 {
    var s = 0.0f64
    var k = 1.0f64
    while k <= math.floor[f64](x) {
        s += lgser_d(k, th)
        k += 1.0f64
    }
    ret s
}

// truncated normal(mean, sd, a, b)
fn tnorm_d(x: f64, m: f64, s: f64, a: f64, b: f64) -> f64 {
    if x <= a || x >= b { ret 0.0f64 }
    ret dist.dnorm((x - m) / s, 0.0f64, 1.0f64, false) / s / (pn((b - m) / s) - pn((a - m) / s))
}
fn tnorm_p(x: f64, m: f64, s: f64, a: f64, b: f64) -> f64 {
    if x <= a { ret 0.0f64 }
    if x >= b { ret 1.0f64 }
    let pa = pn((a - m) / s)
    ret (pn((x - m) / s) - pa) / (pn((b - m) / s) - pa)
}
fn tnorm_q(p: f64, m: f64, s: f64, a: f64, b: f64) -> f64 {
    let pa = pn((a - m) / s)
    let pb = pn((b - m) / s)
    ret m + s * qn(pa + p * (pb - pa))
}

// zero-inflated Poisson(lambda, pi), binomial(size, prob, pi), negative binomial(size, prob, pi): the mass at 0 mixed with the base distribution
fn zip_d(x: f64, l: f64, pi0: f64) -> f64 {
    if x < 0.0f64 || x != math.floor[f64](x) { ret 0.0f64 }
    if x == 0.0f64 { ret pi0 + (1.0f64 - pi0) * nm.dpois(0.0f64, l, false) }
    ret (1.0f64 - pi0) * nm.dpois(x, l, false)
}
fn zib_d(x: f64, n: f64, pr: f64, pi0: f64) -> f64 {
    if x < 0.0f64 || x > n || x != math.floor[f64](x) { ret 0.0f64 }
    if x == 0.0f64 { ret pi0 + (1.0f64 - pi0) * nb.dbinom(0.0f64, n, pr, false) }
    ret (1.0f64 - pi0) * nb.dbinom(x, n, pr, false)
}
fn zinb_d(x: f64, n: f64, pr: f64, pi0: f64) -> f64 {
    if x < 0.0f64 || x != math.floor[f64](x) { ret 0.0f64 }
    if x == 0.0f64 { ret pi0 + (1.0f64 - pi0) * nb.dnbinom(0.0f64, n, pr, false) }
    ret (1.0f64 - pi0) * nb.dnbinom(x, n, pr, false)
}

// gamma-Poisson(shape, scale)
fn gpois_d(x: f64, shape: f64, scale: f64) -> f64 {
    if x < 0.0f64 || x != math.floor[f64](x) { ret 0.0f64 }
    ret nb.dnbinom(x, shape, 1.0f64 / (1.0f64 + scale), false)
}

// Poisson(lambda) truncated to a < x <= b
fn tpois_d(x: f64, l: f64, a: f64, b: f64) -> f64 {
    if x <= a || x > b || x != math.floor[f64](x) { ret 0.0f64 }
    ret nm.dpois(x, l, false) / (nm.ppois(b, l, true, false) - nm.ppois(a, l, true, false))
}

// Skellam(mu1, mu2): exp(-(mu1 + mu2)) (mu1 / mu2)^(x / 2) I_|x|(2 sqrt(mu1 mu2))
fn skellam_d(x: f64, m1: f64, m2: f64) -> f64 {
    if x != math.floor[f64](x) { ret 0.0f64 }
    ret math.exp[f64](0.0f64 - (m1 + m2)) * math.pow[f64](m1 / m2, x / 2.0f64) * gsl.bessel_inu(math.abs[f64](x), 2.0f64 * math.sqrt[f64](m1 * m2))
}

// binomial(size, prob) truncated to a < x <= b
fn tbinom_d(x: f64, n: f64, pr: f64, a: f64, b: f64) -> f64 {
    if x <= a || x > b || x != math.floor[f64](x) { ret 0.0f64 }
    ret nb.dbinom(x, n, pr, false) / (nb.pbinom(b, n, pr, true, false) - nb.pbinom(a, n, pr, true, false))
}

// non-standard beta(shape1, shape2, min, max)
fn nsbeta_d(x: f64, s1: f64, s2: f64, lo: f64, hi: f64) -> f64 {
    if x < lo || x > hi { ret 0.0f64 }
    ret nb.dbeta((x - lo) / (hi - lo), s1, s2, false) / (hi - lo)
}

// half-t(nu, sigma)
fn ht_d(x: f64, nu: f64, s: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret 2.0f64 * nb.dt(x / s, nu, false) / s
}

// slash(mu, sigma)
fn slash_d(x: f64, mu: f64, s: f64) -> f64 {
    let z = (x - mu) / s
    if z == 0.0f64 { ret 1.0f64 / (2.0f64 * math.sqrt[f64](2.0f64 * pi())) }
    ret (dist.dnorm(0.0f64, 0.0f64, 1.0f64, false) - dist.dnorm(z, 0.0f64, 1.0f64, false)) / (s * z * z)
}

// shifted Gompertz(b, eta)
fn sgomp_d(x: f64, b: f64, eta: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    let e = math.exp[f64](0.0f64 - b * x)
    ret b * e * math.exp[f64](0.0f64 - eta * e) * (1.0f64 + eta * (1.0f64 - e))
}

// random draws after set.seed (the generator `rng` seeded by the caller): family 0 Gumbel (mu, s), 1 Frechet (l, mu, s), 2 power (a, b), 3 Lomax (l, k), 4 Pareto (a, b), 5 Rayleigh (s), 6 Kumaraswamy (a, b), 7 Gompertz (a, b), 8 half-normal (s), 9 half-Cauchy (s), 10 Laplace (mu, s);
// each draws one uniform (one standard exponential for the Gumbel, one normal for the half-normal), inverted through the quantile function of the package at u or 1 - u as the package does
fn rgen(r: *rng.Rng, family: usize, p1: f64, p2: f64, p3: f64) -> f64 {
    if family == 0usize { ret p1 - p2 * math.log[f64](rng.exp_unit(r)) }
    if family == 8usize { ret p1 * math.abs[f64](rng.norm(r)) }
    if family == 10usize {
        // Laplace: a standard exponential, then a uniform for the sign
        let e = rng.exp_unit(r)
        let us = rng.unif(r)
        if us > 0.5f64 { ret p1 + p2 * e }
        ret p1 - p2 * e
    }
    let u = rng.unif(r)
    if family == 1usize { ret frechet_q(u, p1, p2, p3) }
    if family == 2usize { ret power_q(u, p1, p2) }
    if family == 3usize { ret lomax_q(1.0f64 - u, p1, p2) }
    if family == 4usize { ret pareto_q(1.0f64 - u, p1, p2) }
    if family == 5usize { ret rayleigh_q(1.0f64 - u, p1) }
    if family == 6usize { ret kumar_q(1.0f64 - u, p1, p2) }
    if family == 7usize { ret gompertz_q(1.0f64 - u, p1, p2) }
    ret p1 * math.abs[f64](math.tan[f64](pi() * u))
}

// cumulative forms of the discrete and truncated families above
fn zip_p(x: f64, l: f64, pi0: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret pi0 + (1.0f64 - pi0) * nm.ppois(x, l, true, false)
}
fn zib_p(x: f64, n: f64, pr: f64, pi0: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret pi0 + (1.0f64 - pi0) * nb.pbinom(x, n, pr, true, false)
}
fn zinb_p(x: f64, n: f64, pr: f64, pi0: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret pi0 + (1.0f64 - pi0) * nb.pnbinom(x, n, pr, true, false)
}
fn gpois_p(x: f64, shape: f64, scale: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nb.pnbinom(x, shape, 1.0f64 / (1.0f64 + scale), true, false)
}
fn tpois_p(x: f64, l: f64, a: f64, b: f64) -> f64 {
    if x <= a { ret 0.0f64 }
    if x >= b { ret 1.0f64 }
    ret (nm.ppois(x, l, true, false) - nm.ppois(a, l, true, false)) / (nm.ppois(b, l, true, false) - nm.ppois(a, l, true, false))
}
fn tbinom_p(x: f64, n: f64, pr: f64, a: f64, b: f64) -> f64 {
    if x <= a { ret 0.0f64 }
    if x >= b { ret 1.0f64 }
    ret (nb.pbinom(x, n, pr, true, false) - nb.pbinom(a, n, pr, true, false)) / (nb.pbinom(b, n, pr, true, false) - nb.pbinom(a, n, pr, true, false))
}
fn nsbeta_p(x: f64, s1: f64, s2: f64, lo: f64, hi: f64) -> f64 {
    if x <= lo { ret 0.0f64 }
    if x >= hi { ret 1.0f64 }
    ret nb.pbeta((x - lo) / (hi - lo), s1, s2, true, false)
}
fn ht_p(x: f64, nu: f64, s: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    ret 2.0f64 * nb.pt(x / s, nu, true, false) - 1.0f64
}
fn sgomp_p(x: f64, b: f64, eta: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let e = math.exp[f64](0.0f64 - b * x)
    ret (1.0f64 - e) * math.exp[f64](0.0f64 - eta * e)
}

// quantile functions: the zero-inflated ones answer 0 up to the mass at zero and invert the base distribution above it; the truncated ones invert the base on the rescaled slice
fn zip_q(p: f64, l: f64, pi0: f64) -> f64 {
    if p <= pi0 { ret 0.0f64 }
    ret nm.qpois((p - pi0) / (1.0f64 - pi0), l, true, false)
}
fn zib_q(p: f64, n: f64, pr: f64, pi0: f64) -> f64 {
    if p <= pi0 { ret 0.0f64 }
    ret nb.qbinom((p - pi0) / (1.0f64 - pi0), n, pr, true, false)
}
fn zinb_q(p: f64, n: f64, pr: f64, pi0: f64) -> f64 {
    if p <= pi0 { ret 0.0f64 }
    ret nb.qnbinom((p - pi0) / (1.0f64 - pi0), n, pr, true, false)
}
fn tpois_q(p: f64, l: f64, a: f64, b: f64) -> f64 {
    let pa = nm.ppois(a, l, true, false)
    ret nm.qpois(pa + p * (nm.ppois(b, l, true, false) - pa), l, true, false)
}
fn tbinom_q(p: f64, n: f64, pr: f64, a: f64, b: f64) -> f64 {
    let pa = nb.pbinom(a, n, pr, true, false)
    ret nb.qbinom(pa + p * (nb.pbinom(b, n, pr, true, false) - pa), n, pr, true, false)
}
fn nsbeta_q(p: f64, s1: f64, s2: f64, lo: f64, hi: f64) -> f64 { ret lo + (hi - lo) * nb.qbeta(p, s1, s2, true, false) }
fn ht_q(p: f64, nu: f64, s: f64) -> f64 { ret s * nb.qt((p + 1.0f64) / 2.0f64, nu, true, false) }
