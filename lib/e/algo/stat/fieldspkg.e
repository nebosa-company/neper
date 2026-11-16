// R fields: the Matern covariance function and the exponential covariance with power p, on a distance (the package's special cases at smoothness 1/2, 3/2 and 5/2,
// and its 1e-10 stand-in for a zero distance in the general case).
//
// Not here: Tps, Krig, the other covariances, spatial process fitting and the plotting helpers.

use e.algo.stat.gslfns as gs
use e.math.special as sp
use e.math
use e.mem

fn gamma_fn(x: f64) -> f64 { ret math.exp[f64](sp.lgamma(x)) }

// Matern(d, range, smoothness, phi)
fn matern(d0: f64, range: f64, nu: f64, phi: f64) -> f64 {
    var d = d0 / range
    if nu == 0.5f64 { ret phi * math.exp[f64](0.0f64 - d) }
    if nu == 1.5f64 { ret phi * (1.0f64 + d) * math.exp[f64](0.0f64 - d) }
    if nu == 2.5f64 { ret phi * (1.0f64 + d + d * d / 3.0f64) * math.exp[f64](0.0f64 - d) }
    if d == 0.0f64 { d = 1.0e-10f64 }
    let con = 1.0f64 / (math.pow[f64](2.0f64, nu - 1.0f64) * gamma_fn(nu))
    ret phi * con * math.pow[f64](d, nu) * gs.bessel_knu(nu, d)
}

// Exp.cov between two points at distance d with range aRange and power p: exp(-(d / aRange)^p)
fn exp_cov(d: f64, range: f64, p: f64) -> f64 { ret math.exp[f64](0.0f64 - math.pow[f64](d / range, p)) }
