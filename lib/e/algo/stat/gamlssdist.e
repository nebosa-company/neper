// R gamlss.dist: the density of the Gumbel (GU), logistic (LO), gamma (GA), inverse Gaussian (IG), Box-Cox Cole-Green (BCCG) and power exponential (PE) families
// in the package's (mu, sigma, nu) parametrization, and the distribution and quantile functions of GU and LO.
//
// Not here: the other 90-odd families, p and q for the rest, random numbers, moments and the link functions.

use e.math
use e.math.dist as dist
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
