// R sn: the skew-normal and skew-t. dsn (with the extension parameter tau), psn by Owen's T (the package's series, including its
// high-h approximation), qsn by the Cornish-Fisher start and Newton steps (tau = 0), and dst.
//
// Not here: psn through the bivariate normal engine (tau != 0, or a point with z * alpha <= -5 in a short vector), pst, qst, the
// random generators, the multivariate families, the cumulants for tau != 0 and selm.

use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

fn pn(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }

fn dsn(x: f64, xi: f64, omega: f64, alpha: f64, tau: f64) -> f64 {
    let z = (x - xi) / omega
    let ln = 0.0f64 - math.log[f64](math.sqrt[f64](2.0f64 * pi())) - math.log[f64](omega) - z * z / 2.0f64
    let ls = dist.pnorm(tau * math.sqrt[f64](1.0f64 + alpha * alpha) + alpha * z, 0.0f64, 1.0f64, true, true)
    ret math.exp[f64](ln + ls - dist.pnorm(tau, 0.0f64, 1.0f64, true, true))
}

// the series part of T.Owen for 0 <= a <= 1 at h >= 0
fn t_int(h: f64, a: f64) -> f64 {
    let jmax = 50i32
    if h <= 8.0f64 {
        var cum = 0.0f64
        var term = 1.0f64
        var s = 0.0f64
        var i = 0i32
        let e = math.exp[f64](0.0f64 - 0.5f64 * h * h)
        var ap = a
        while i <= jmax {
            if i > 0i32 { term = term * h * h / (2.0f64 * f64(i)) }
            cum += term
            var sg = 1.0f64
            if i % 2i32 == 1i32 { sg = 0.0f64 - 1.0f64 }
            s += (1.0f64 - e * cum) * sg / (2.0f64 * f64(i) + 1.0f64) * ap
            ap = ap * a * a
            i += 1i32
        }
        ret (math.atan[f64](a) - s) / (2.0f64 * pi())
    }
    let at = math.atan[f64](a)
    let ha = h * a
    ret at * math.exp[f64](0.0f64 - 0.5f64 * h * h * a / at) * (1.0f64 + 0.00868f64 * ha * ha * ha * ha) / (2.0f64 * pi())
}

fn t_owen(h: f64, a: f64) -> f64 {
    let aa = math.abs[f64](a)
    let ah = math.abs[f64](h)
    var sg = 1.0f64
    if a < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if aa == 0.0f64 { ret 0.0f64 }
    if aa <= 1.0f64 { ret sg * t_int(ah, aa) }
    ret sg * (0.5f64 * pn(ah) + pn(aa * ah) * (0.5f64 - pn(ah)) - t_int(aa * ah, 1.0f64 / aa))
}

// psn with engine = "T.Owen" (tau = 0)
fn psn_owen(x: f64, xi: f64, omega: f64, alpha: f64) -> f64 {
    let z = (x - xi) / omega
    var p = pn(z) - 2.0f64 * t_owen(z, alpha)
    if p < 0.0f64 { p = 0.0f64 }
    if p > 1.0f64 { p = 1.0f64 }
    ret p
}

// qsn, tau = 0, solver "NR"
fn qsn(p: f64, xi: f64, omega: f64, alpha: f64) -> f64 {
    let d = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
    let bd = math.sqrt[f64](2.0f64 / pi()) * d
    let k1 = bd
    let k2 = 1.0f64 - bd * bd
    let k3 = (4.0f64 - pi()) / 2.0f64 * bd * bd * bd
    let k4 = 2.0f64 * (pi() - 3.0f64) * bd * bd * bd * bd
    let g1 = k3 / math.pow[f64](k2, 1.5f64)
    let g2 = k4 / (k2 * k2)
    let q = dist.qnorm(p, 0.0f64, 1.0f64, true, false)
    var x = q + (q * q - 1.0f64) * g1 / 6.0f64 + q * (q * q - 3.0f64) * g2 / 24.0f64 - q * (2.0f64 * q * q - 5.0f64) * g1 * g1 / 36.0f64
    x = k1 + math.sqrt[f64](k2) * x
    var px = psn_owen(x, 0.0f64, 1.0f64, alpha)
    var miss = 1.0f64
    var it = 0i32
    while miss > 1.0e-8f64 && it < 100i32 {
        x = x - (px - p) / dsn(x, 0.0f64, 1.0f64, alpha, 0.0f64)
        px = psn_owen(x, 0.0f64, 1.0f64, alpha)
        miss = math.abs[f64](px - p)
        it += 1i32
    }
    ret xi + omega * x
}

fn dst(x: f64, xi: f64, omega: f64, alpha: f64, nu: f64) -> f64 {
    let z = (x - xi) / omega
    let pdf = nb.dt(z, nu, false)
    let cdf = nb.pt(alpha * z * math.sqrt[f64]((nu + 1.0f64) / (z * z + nu)), nu + 1.0f64, true, false)
    ret 2.0f64 * pdf * cdf / omega
}
