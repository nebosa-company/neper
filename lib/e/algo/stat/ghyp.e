// R GeneralizedHyperbolic: the density of the generalized hyperbolic family dghyp(x, mu, delta, alpha, beta, lambda) and its special cases
// dnig (lambda = -1/2), dhyperb (lambda = 1) and dskewlap, on e.algo.stat.gslfns.bessel_knu.
//
// Not here: the distribution and quantile functions, random numbers, moments and fits.

use e.algo.stat.gslfns as gs
use e.math

// dghyp(x, param = c(mu, delta, alpha, beta, lambda)) in the (alpha, beta) parametrization
fn dghyp(x: f64, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    let gamma = math.sqrt[f64](alpha * alpha - beta * beta)
    let d = x - mu
    let r = math.sqrt[f64](delta * delta + d * d)
    let top = math.pow[f64](gamma / delta, lambda) * gs.bessel_knu(lambda - 0.5f64, alpha * r) * math.exp[f64](beta * d)
    let bot = math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64) * gs.bessel_knu(lambda, delta * gamma) * math.pow[f64](r / alpha, 0.5f64 - lambda)
    ret top / bot
}

fn dnig(x: f64, mu: f64, delta: f64, alpha: f64, beta: f64) -> f64 { ret dghyp(x, mu, delta, alpha, beta, 0.0f64 - 0.5f64) }

fn dhyperb(x: f64, mu: f64, delta: f64, alpha: f64, beta: f64) -> f64 { ret dghyp(x, mu, delta, alpha, beta, 1.0f64) }

fn dskewlap(x: f64, mu: f64, alpha: f64, beta: f64) -> f64 {
    let ab = alpha + beta
    if x <= mu { ret math.exp[f64]((x - mu) / alpha) / ab }
    ret math.exp[f64]((mu - x) / beta) / ab
}
