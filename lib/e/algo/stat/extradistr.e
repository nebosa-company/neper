// R extraDistr, the closed-form continuous distributions: density `*_d`, distribution function `*_p` and quantile `*_q` of the Gumbel,
// Frechet, Kumaraswamy, Laplace, Lomax, Pareto, Rayleigh, triangular, Gompertz, power, inverse gamma, half-normal, half-Cauchy,
// Birnbaum-Saunders (fatigue life), Wald and beta-prime distributions, with the package's parameterisations.
//
// Not here: the discrete and multivariate distributions, the random generators and the other continuous families.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb

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
    if x < a || x > b { ret 0.0f64 }
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
