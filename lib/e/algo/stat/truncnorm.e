// R truncnorm: the density, distribution, quantile (Brent root finding as R_zeroin2 does it), mean and
// variance of the truncated normal distribution, and `rtruncnorm` under the Mersenne-Twister stream
// (Robert's rejection samplers chosen by region, as rtruncnorm.c does).
//
// Not here: the vectorised recycling of the R wrappers (a call takes scalars).

use e.algo.rand.r as rng
use e.math
use e.math.dist as dist

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn is_finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn pn(x: f64, mean: f64, sd: f64, lower: bool, lg: bool) -> f64 { ret dist.pnorm(x, mean, sd, lower, lg) }

fn dn(x: f64, lg: bool) -> f64 { ret dist.dnorm(x, 0.0f64, 1.0f64, lg) }

fn log1mexp(x: f64) -> f64 {
    if x > 0.0f64 - 0.6931471805599453f64 { ret math.log[f64](0.0f64 - dist.expm1(x)) }
    ret dist.log1p(0.0f64 - math.exp[f64](x))
}

fn logspace_sub(lx: f64, ly: f64) -> f64 { ret lx + log1mexp(ly - lx) }

fn dtruncnorm(x: f64, a: f64, b: f64, mean: f64, sd: f64) -> f64 {
    if a <= x && x <= b {
        let c1 = pn(a, mean, sd, true, false)
        let c2 = pn(b, mean, sd, true, false)
        let c3 = sd * (c2 - c1)
        let c4 = dn((x - mean) / sd, true)
        let l = math.log[f64](c3)
        if !is_finite(l) { ret 1.0f64 / (b - a) }
        ret math.exp[f64](c4 - l)
    }
    ret 0.0f64
}

fn ptruncnorm(q: f64, a: f64, b: f64, mean: f64, sd: f64) -> f64 {
    if q < a { ret 0.0f64 }
    if q > b { ret 1.0f64 }
    let c1 = pn(q, mean, sd, true, false)
    let c2 = pn(a, mean, sd, true, false)
    let c3 = pn(b, mean, sd, true, false)
    ret (c1 - c2) / (c3 - c2)
}

// Brent's method as R_zeroin2: the root of f(x) = ptruncnorm(x) - p between lower and upper
fn brent(lower: f64, upper: f64, a0: f64, b0: f64, p: f64, tr_a: f64, tr_b: f64, mean: f64, sd: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    var a = lower
    var b = upper
    var c = a
    var fa = ptruncnorm(a, tr_a, tr_b, mean, sd) - p
    var fb = ptruncnorm(b, tr_a, tr_b, mean, sd) - p
    var fc = fa
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    var maxit = 201i64
    while maxit > 0i64 {
        maxit -= 1i64
        let prev = b - a
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * math.abs[f64](b)
        var step = (c - b) / 2.0f64
        if math.abs[f64](step) <= tol_act || fb == 0.0f64 { ret b }
        if math.abs[f64](prev) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = c - b
            var pp = 0.0f64
            var qq = 0.0f64
            if a == c {
                let t1 = fb / fa
                pp = cb * t1
                qq = 1.0f64 - t1
            } else {
                qq = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                pp = t2 * (cb * qq * (qq - t1) - (b - a) * (t1 - 1.0f64))
                qq = (qq - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if pp > 0.0f64 { qq = 0.0f64 - qq } else { pp = 0.0f64 - pp }
            if pp < (0.75f64 * cb * qq - math.abs[f64](tol_act * qq) / 2.0f64) && pp < math.abs[f64](prev * qq / 2.0f64) { step = pp / qq }
        }
        if math.abs[f64](step) < tol_act {
            if step > 0.0f64 { step = tol_act } else { step = 0.0f64 - tol_act }
        }
        a = b
        fa = fb
        b += step
        fb = ptruncnorm(b, tr_a, tr_b, mean, sd) - p
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret b
}

fn qtruncnorm(p: f64, a: f64, b: f64, mean: f64, sd: f64) -> f64 {
    if p == 0.0f64 { ret a }
    if p == 1.0f64 { ret b }
    if p < 0.0f64 || p > 1.0f64 { ret nan() }
    if a == 0.0f64 - inf() && b == inf() { ret dist.qnorm(p, mean, sd, true, false) }
    var lower = a
    var upper = b
    if lower == 0.0f64 - inf() {
        lower = 0.0f64 - 1.0f64
        while ptruncnorm(lower, a, b, mean, sd) - p >= 0.0f64 { lower *= 2.0f64 }
    } else if upper == inf() {
        upper = 1.0f64
        while ptruncnorm(upper, a, b, mean, sd) - p <= 0.0f64 { upper *= 2.0f64 }
    }
    ret brent(lower, upper, 0.0f64, 0.0f64, p, a, b, mean, sd)
}

fn e_left(a: f64, mean: f64, sd: f64) -> f64 {
    let alpha = (a - mean) / sd
    let phi_a = dn(alpha, true)
    let big_a = pn(alpha, 0.0f64, 1.0f64, false, true)
    ret mean + sd * math.exp[f64](phi_a - big_a)
}

fn e_right(b: f64, mean: f64, sd: f64) -> f64 {
    let beta = (b - mean) / sd
    let phi_b = dn(beta, true)
    let big_b = pn(beta, 0.0f64, 1.0f64, true, true)
    ret mean + sd * (0.0f64 - math.exp[f64](phi_b - big_b))
}

fn e_both(a: f64, b: f64, mean: f64, sd0: f64) -> f64 {
    if b < mean - 6.0f64 * sd0 || a > mean + 6.0f64 * sd0 { ret (a + b) / 2.0f64 }
    var sd = sd0
    let alpha = (a - mean) / sd
    let beta = (b - mean) / sd
    let phi_a = dn(alpha, true)
    let big_a = pn(alpha, 0.0f64, 1.0f64, true, true)
    let phi_b = dn(beta, true)
    let big_b = pn(beta, 0.0f64, 1.0f64, true, true)
    var dphi = 0.0f64
    var dbig = 0.0f64
    if phi_b < phi_a {
        dphi = logspace_sub(phi_a, phi_b)
    } else {
        sd = 0.0f64 - sd
        dphi = logspace_sub(phi_b, phi_a)
    }
    if big_b > big_a {
        sd = 0.0f64 - sd
        dbig = logspace_sub(big_b, big_a)
    } else {
        dbig = logspace_sub(big_a, big_b)
    }
    ret mean + sd * (0.0f64 - math.exp[f64](dphi - dbig))
}

fn v_left(a: f64, mean: f64, sd: f64) -> f64 {
    let alpha = (a - mean) / sd
    let phi_a = dn(alpha, false)
    let big_a = pn(alpha, 0.0f64, 1.0f64, true, false)
    let lambda = phi_a / (1.0f64 - big_a)
    ret sd * sd * (1.0f64 - lambda * (lambda - alpha))
}

fn v_right(b: f64, mean: f64, sd: f64) -> f64 { ret v_left(0.0f64 - b, 0.0f64 - mean, sd) }

fn v_both(a: f64, b: f64, mean: f64, sd: f64) -> f64 {
    if b < mean - 6.0f64 * sd || a > mean + 6.0f64 * sd { ret (b - a) * (b - a) / 12.0f64 }
    let v = sd * sd
    let pi1 = pn(a, mean, sd, true, false)
    let pi2 = pn(b, mean, sd, true, false) - pn(a, mean, sd, true, false)
    let pi3 = pn(b, mean, sd, false, false)
    let e1 = e_right(a, mean, sd)
    let e2 = e_both(a, b, mean, sd)
    let e3 = e_left(b, mean, sd)
    let v1 = v_right(a, mean, sd)
    let v3 = v_left(b, mean, sd)
    let c1 = pi1 * (v1 + (e1 - mean) * (e1 - mean))
    let c3 = pi3 * (v3 + (e3 - mean) * (e3 - mean))
    ret (v - c1 - c3) / pi2 - (e2 - mean) * (e2 - mean)
}

fn etruncnorm(a: f64, b: f64, mean: f64, sd: f64) -> f64 {
    if is_finite(a) && is_finite(b) { ret e_both(a, b, mean, sd) }
    if a == 0.0f64 - inf() && is_finite(b) { ret e_right(b, mean, sd) }
    if is_finite(a) && b == inf() { ret e_left(a, mean, sd) }
    if a == 0.0f64 - inf() && b == inf() { ret mean }
    ret nan()
}

fn vtruncnorm(a: f64, b: f64, mean: f64, sd: f64) -> f64 {
    if is_finite(a) && is_finite(b) { ret v_both(a, b, mean, sd) }
    if a == 0.0f64 - inf() && is_finite(b) { ret v_right(b, mean, sd) }
    if is_finite(a) && b == inf() { ret v_left(a, mean, sd) }
    if a == 0.0f64 - inf() && b == inf() { ret sd * sd }
    ret nan()
}

// --- rtruncnorm

fn ers_a_inf(g: *rng.Rng, a: f64) -> f64 {
    let ainv = 1.0f64 / a
    var x = 0.0f64
    var ok2 = false
    while !ok2 {
        x = rng.rexp(g, ainv) + a
        let rho = math.exp[f64](0.0f64 - 0.5f64 * (x - a) * (x - a))
        if !(rng.runif(g, 0.0f64, 1.0f64) > rho) { ok2 = true }
    }
    ret x
}

fn ers_a_b(g: *rng.Rng, a: f64, b: f64) -> f64 {
    let ainv = 1.0f64 / a
    var x = 0.0f64
    var ok2 = false
    while !ok2 {
        x = rng.rexp(g, ainv) + a
        let rho = math.exp[f64](0.0f64 - 0.5f64 * (x - a) * (x - a))
        if !(rng.runif(g, 0.0f64, 1.0f64) > rho || x > b) { ok2 = true }
    }
    ret x
}

fn nrs_a_b(g: *rng.Rng, a: f64, b: f64) -> f64 {
    var x = 0.0f64 - 1.7976931348623157e308f64
    while x < a || x > b { x = rng.rnorm(g, 0.0f64, 1.0f64) }
    ret x
}

fn nrs_a_inf(g: *rng.Rng, a: f64) -> f64 {
    var x = 0.0f64 - 1.7976931348623157e308f64
    while x < a { x = rng.rnorm(g, 0.0f64, 1.0f64) }
    ret x
}

fn hnrs_a_b(g: *rng.Rng, a: f64, b: f64) -> f64 {
    var x = a - 1.0f64
    while x < a || x > b {
        x = rng.rnorm(g, 0.0f64, 1.0f64)
        if x < 0.0f64 { x = 0.0f64 - x }
    }
    ret x
}

fn urs_a_b(g: *rng.Rng, a: f64, b: f64) -> f64 {
    let phi_a = dn(a, false)
    var ub = phi_a
    if a < 0.0f64 && b > 0.0f64 { ub = 0.3989422804014327f64 }
    var x = 0.0f64
    var ok2 = false
    while !ok2 {
        x = rng.runif(g, a, b)
        if !(rng.runif(g, 0.0f64, 1.0f64) * ub > dn(x, false)) { ok2 = true }
    }
    ret x
}

fn r_left(g: *rng.Rng, a: f64, mean: f64, sd: f64) -> f64 {
    let alpha = (a - mean) / sd
    if alpha < 0.45f64 { ret mean + sd * nrs_a_inf(g, alpha) }
    ret mean + sd * ers_a_inf(g, alpha)
}

fn r_right(g: *rng.Rng, b: f64, mean: f64, sd: f64) -> f64 {
    let beta = (b - mean) / sd
    ret mean - sd * r_left(g, 0.0f64 - beta, 0.0f64, 1.0f64)
}

fn r_both(g: *rng.Rng, a: f64, b: f64, mean: f64, sd: f64) -> f64 {
    let alpha = (a - mean) / sd
    let beta = (b - mean) / sd
    let phi_a = dn(alpha, false)
    let phi_b = dn(beta, false)
    if beta <= alpha { ret nan() }
    if alpha <= 0.0f64 && 0.0f64 <= beta {
        if phi_a <= 0.15f64 || phi_b <= 0.15f64 { ret mean + sd * nrs_a_b(g, alpha, beta) }
        ret mean + sd * urs_a_b(g, alpha, beta)
    }
    if alpha > 0.0f64 {
        if phi_a / phi_b <= 2.18f64 { ret mean + sd * urs_a_b(g, alpha, beta) }
        if alpha < 0.725f64 { ret mean + sd * hnrs_a_b(g, alpha, beta) }
        ret mean + sd * ers_a_b(g, alpha, beta)
    }
    if phi_b / phi_a <= 2.18f64 { ret mean - sd * urs_a_b(g, 0.0f64 - beta, 0.0f64 - alpha) }
    if beta > 0.0f64 - 0.725f64 { ret mean - sd * hnrs_a_b(g, 0.0f64 - beta, 0.0f64 - alpha) }
    ret mean - sd * ers_a_b(g, 0.0f64 - beta, 0.0f64 - alpha)
}

fn rtruncnorm(g: *rng.Rng, a: f64, b: f64, mean: f64, sd: f64) -> f64 {
    if is_finite(a) && is_finite(b) { ret r_both(g, a, b, mean, sd) }
    if a == 0.0f64 - inf() && is_finite(b) { ret r_right(g, b, mean, sd) }
    if is_finite(a) && b == inf() { ret r_left(g, a, mean, sd) }
    if a == 0.0f64 - inf() && b == inf() { ret rng.rnorm(g, mean, sd) }
    ret nan()
}
