// R gsDesign: the alpha spending functions of group sequential designs: Hwang-Shih-DeCani (sfHSD), power (sfPower), exponential
// (sfExponential), logistic, normal, Cauchy and extreme-value families in their two-parameter form (a, b), the beta distribution,
// and the Lan-DeMets O'Brien-Fleming and Pocock approximations. Each gives the cumulative alpha spent at information fraction t (capped at 1).
//
// Not here: the four-point parameterisations that solve for (a, b), sfPoints, sfStep, the boundary computation of gsDesign() and gsProbability.

use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

// kind: 0 HSD(gamma), 1 power(rho), 2 exponential(nu), 3 logistic(a, b), 4 normal(a, b), 5 Cauchy(a, b), 6 extreme value(a, b), 7 beta(a, b),
// 8 LDOF(rho; 1 is the plain approximation), 9 LDPocock
fn spend(kind: usize, alpha: f64, t0: f64, p1: f64, p2: f64) -> f64 {
    var t = t0
    if t > 1.0f64 { t = 1.0f64 }
    if kind == 0usize {
        if p1 == 0.0f64 { ret t * alpha }
        ret alpha * (1.0f64 - math.exp[f64](0.0f64 - t * p1)) / (1.0f64 - math.exp[f64](0.0f64 - p1))
    }
    if kind == 1usize { ret alpha * math.pow[f64](t, p1) }
    if kind == 2usize { ret math.pow[f64](alpha, math.pow[f64](t, 0.0f64 - p1)) }
    if kind == 8usize {
        let z = 0.0f64 - dist.qnorm(alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
        ret 2.0f64 * (1.0f64 - dist.pnorm(z / math.pow[f64](t, p1 / 2.0f64), 0.0f64, 1.0f64, true, false))
    }
    if kind == 9usize { ret alpha * math.log[f64](1.0f64 + (math.exp[f64](1.0f64) - 1.0f64) * t) }
    if kind == 7usize { ret alpha * nb.pbeta(t, p1, p2, true, false) }
    if t >= 1.0f64 { ret alpha }
    if kind == 3usize {
        let xv = math.log[f64](t / (1.0f64 - t))
        let y = math.exp[f64](p1 + p2 * xv)
        ret alpha * y / (1.0f64 + y)
    }
    if kind == 4usize {
        let xv = dist.qnorm(t, 0.0f64, 1.0f64, true, false)
        ret alpha * dist.pnorm(p1 + p2 * xv, 0.0f64, 1.0f64, true, false)
    }
    if kind == 5usize {
        let xv = math.tan[f64](pi() * (t - 0.5f64))
        ret alpha * (0.5f64 + math.atan[f64](p1 + p2 * xv) / pi())
    }
    let xv = 0.0f64 - math.log[f64](0.0f64 - math.log[f64](t))
    ret alpha * math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - p1 - p2 * xv))
}
