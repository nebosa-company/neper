// R stabledist: the stable density dstable in the default S0 parametrisation (pm = 0), for alpha in [0.02, 2) with alpha != 1 (alpha = 2 is the normal, alpha = 1 with
// beta = 0 the Cauchy): Nolan's integral representation split at the mode of the integrand and at the points where it falls below 1e-4, each piece integrated with
// integrate() (e.math.quadpack.qags) at tolerance 64 eps and 1000 subdivisions, as stabledist:::.fct1 does.
//
// Not here: alpha below 0.02 (dstable.smallA), the Pareto-tail fallback when the integral underflows to zero, the other parametrisations,
// log densities, pstable, qstable and rstable.

use e.math
use e.math.dist as dist
use e.math.quadpack as qp
use e.math.special as sp
use e.mem
use e.algo.stat.pwr as pw
use e.algo.rand.r as rg

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

fn pi2() -> f64 { ret 1.5707963267948966192313216916398f64 }

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

fn large_exp_arg() -> f64 { ret 708.3964185322641f64 }

// the integrand pieces for one x: g(theta) and g1(theta) = g exp(-g)
type Gctx = struct { alpha: f64, a1: f64, cat0: f64, at0: f64, xmz: f64, mode: usize, lvl: f64 }

fn sgn(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

fn g_of(c: *Gctx, th: f64) -> f64 {
    if math.abs[f64](pi2() - sgn(c.a1) * th) < 64.0f64 * eps() { ret 0.0f64 }
    let att = c.at0 + c.alpha * th
    ret math.pow[f64](c.cat0 * math.cos[f64](th) * math.pow[f64](c.xmz / math.sin[f64](att), c.alpha), 1.0f64 / c.a1) * math.cos[f64](att - th)
}

fn xexpmx(x: f64) -> f64 {
    if x != x { ret x }
    if x > large_exp_arg() { ret 0.0f64 }
    ret x * math.exp[f64](0.0f64 - x)
}

fn g1_of(c: *Gctx, th: f64) -> f64 { ret xexpmx(g_of(c, th)) }

// the functions whose roots uniroot looks for: mode 0 g - 1, 1 log g, 2 g1 - lvl
fn root_fn(c: *Gctx, th: f64) -> f64 {
    if c.mode == 0usize { ret g_of(c, th) - 1.0f64 }
    if c.mode == 1usize { ret math.log[f64](g_of(c, th)) }
    ret g1_of(c, th) - c.lvl
}

fn integ(a: *mem.Arena, c: *Gctx, lo: f64, hi: f64, tol: f64) -> f64 {
    let (r, e) = qp.qags[Gctx](a, c, g1_of, lo, hi, tol, tol, 1000usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret r.result
}

// stabledist:::.fct1 for one x (S0, alpha != 1), returning the density of the standardised variable; NaN when R would stop
fn fct1(a: *mem.Arena, x0: f64, zeta: f64, alpha: f64, theta00: f64, tol: f64, zeta_tol: f64) -> f64 {
    var x = x0
    var theta0 = theta00
    let xmz = math.abs[f64](x - zeta)
    let fzeta = math.exp[f64](lgamma_(1.0f64 + 1.0f64 / alpha)) * math.cos[f64](theta0) / (pi() * math.pow[f64](1.0f64 + zeta * zeta, 1.0f64 / (2.0f64 * alpha)))
    var amax = math.abs[f64](x)
    if math.abs[f64](zeta) > amax { amax = math.abs[f64](zeta) }
    if xmz <= zeta_tol * (zeta_tol + amax) { ret fzeta }
    if x < zeta { theta0 = 0.0f64 - theta0 }
    let a1 = alpha - 1.0f64
    let at0 = alpha * theta0
    var c: Gctx = zero
    c.alpha = alpha
    c.a1 = a1
    c.at0 = at0
    c.cat0 = math.cos[f64](at0)
    c.xmz = xmz
    let c2 = alpha / (pi() * math.abs[f64](a1) * xmz)
    let gp = g_of(&c, pi2())
    let gm = g_of(&c, 0.0f64 - theta0)
    if alpha >= 1.0f64 {
        if (gp == gp && gp > large_exp_arg()) || gm == 0.0f64 { ret 0.0f64 }
    } else {
        if (gm == gm && gm > large_exp_arg()) || gp == 0.0f64 { ret 0.0f64 }
    }
    var gdot = 0.0f64
    if alpha >= 1.0f64 {
        let lt = 0.0f64 - theta0
        gdot = g_of(&c, lt + 0.000001f64 * math.abs[f64](lt))
    } else {
        gdot = g_of(&c, pi2() * (1.0f64 - 0.000001f64))
    }
    if gdot != gdot {
        var ratio = xmz / math.abs[f64](x)
        if xmz > ratio { ratio = xmz }
        if ratio < 0.01f64 { ret fzeta }
    }
    var theta2 = 0.0f64
    var g1th2 = 0.0f64
    if (alpha >= 1.0f64 && gp == gp && gp > 1.0f64) || (alpha < 1.0f64 && gp == gp && gp < 1.0f64) {
        theta2 = pi2() * (1.0f64 - 0.000001f64)
        g1th2 = g1_of(&c, theta2)
    } else if (alpha < 1.0f64 && gm > 1.0f64) || (alpha >= 1.0f64 && gm < 1.0f64) {
        let lt = 0.0f64 - theta0
        theta2 = lt + 0.000001f64 * math.abs[f64](lt)
        g1th2 = g1_of(&c, theta2)
    } else {
        var lth = 0.0f64 - theta0
        var uth = pi2()
        if alpha < 1.0f64 {
            var th = (lth + pi2()) / 2.0f64
            while g_of(&c, th) == 0.0f64 {
                lth = th
                th = (lth + pi2()) / 2.0f64
            }
            if g_of(&c, th) == 1.0f64 {
                th = (lth + uth) / 2.0f64
                while g_of(&c, th) == 1.0f64 {
                    uth = th
                    th = (lth + uth) / 2.0f64
                }
            }
            if math.abs[f64](uth - lth) < 1.0e-13f64 { ret 0.0f64 }
        }
        c.mode = 0usize
        let f1l = root_fn(&c, lth)
        let f1u = root_fn(&c, uth)
        if f1l * f1u > 0.0f64 { ret 0.0f64 / 0.0f64 }
        let r1 = pw.zeroin[Gctx](&c, root_fn, lth, uth, eps(), 1000i64)
        let fr1 = root_fn(&c, r1)
        c.mode = 1usize
        let f2l = root_fn(&c, lth)
        let f2u = root_fn(&c, uth)
        var g2 = 0.0f64 - 1.0f64 / 0.0f64
        var r2 = 0.0f64
        if !(f2l * f2u > 0.0f64) && f2l == f2l && f2u == f2u {
            r2 = pw.zeroin[Gctx](&c, root_fn, lth, uth, eps(), 1000i64)
            g2 = xexpmx(math.exp[f64](root_fn(&c, r2)))
        }
        let g1v = xexpmx(fr1 + 1.0f64)
        if g1v >= g2 {
            theta2 = r1
            g1th2 = g1v
        } else {
            theta2 = r2
            g1th2 = g2
        }
    }
    let epsl = 0.0001f64
    let lt0 = 0.0f64 - theta0
    c.mode = 2usize
    c.lvl = epsl
    let do1 = g1th2 > epsl && g1_of(&c, lt0) < epsl
    let do4 = g1th2 > epsl && g1_of(&c, pi2()) < epsl
    var th1 = 0.0f64
    var th3 = 0.0f64
    if do1 { th1 = pw.zeroin[Gctx](&c, root_fn, lt0, theta2, tol, 1000i64) }
    if do4 { th3 = pw.zeroin[Gctx](&c, root_fn, theta2, pi2(), tol, 1000i64) }
    var r1v = 0.0f64
    var r2v = 0.0f64
    var r3v = 0.0f64
    var r4v = 0.0f64
    if do1 {
        r1v = integ(a, &c, lt0, th1, tol)
        r2v = integ(a, &c, th1, theta2, tol)
    } else {
        r2v = integ(a, &c, lt0, theta2, tol)
    }
    if do4 {
        r3v = integ(a, &c, theta2, th3, tol)
        r4v = integ(a, &c, th3, pi2(), tol)
    } else {
        r3v = integ(a, &c, theta2, pi2(), tol)
    }
    ret c2 * (r1v + r2v + r3v + r4v)
}

fn lgamma_(x: f64) -> f64 { ret sp.lgamma(x) }

// dstable(x, alpha, beta, gamma, delta, pm = 0) for alpha in [0.02, 2) \ {1}, alpha = 2 and alpha = 1 with beta = 0
fn dstable(a: *mem.Arena, x0: f64, alpha: f64, beta: f64, gamma: f64, delta: f64) -> f64 {
    let x = (x0 - delta) / gamma
    if alpha == 2.0f64 { ret dist.dnorm(x, 0.0f64, math.sqrt[f64](2.0f64), false) / gamma }
    if alpha == 1.0f64 && beta == 0.0f64 { ret 1.0f64 / (pi() * (1.0f64 + x * x)) / gamma }
    if alpha == 1.0f64 {
        if x >= 0.0f64 { ret fct2_d(a, x, beta, 64.0f64 * eps()) / gamma }
        ret fct2_d(a, 0.0f64 - x, 0.0f64 - beta, 64.0f64 * eps()) / gamma
    }
    let tanpa2 = math.tan[f64](pi2() * alpha)
    let betan = beta * tanpa2
    let zeta = 0.0f64 - betan
    var th0 = math.atan[f64](betan) / alpha
    if th0 < 0.0f64 - pi2() { th0 = 0.0f64 - pi2() }
    if th0 > pi2() { th0 = pi2() }
    var zt = 0.00005f64
    if betan == 0.0f64 {
        zt = 4.0e-16f64
    } else if 1.0f64 - math.abs[f64](beta) < 0.01f64 || alpha < 0.01f64 {
        zt = 2.0e-15f64
    }
    ret fct1(a, x, zeta, alpha, th0, 64.0f64 * eps(), zt) / gamma
}

// stabledist:::.FCT1: the integral behind pstable (alpha != 1), integrand exp(-g(theta)) over (-theta0 + 1e-6, pi/2 - 1e-6); with giveI the integral over pi, else
// the distribution value c1 + c3 times the integral. The corner cases where g is infinite at an end point (an extra uniroot in R) return NaN here.
type Fctx = struct { alpha: f64, a1: f64, cat0: f64, at0: f64, xmz: f64 }

fn gf(c: *Fctx, th: f64) -> f64 {
    if math.abs[f64](pi2() - sgn(c.a1) * th) < 64.0f64 * eps() { ret 0.0f64 }
    let att = c.at0 + c.alpha * th
    ret math.pow[f64](c.cat0 * math.cos[f64](th) * math.pow[f64](c.xmz / math.sin[f64](att), c.alpha), 1.0f64 / c.a1) * math.cos[f64](att - th)
}

fn expmg(c: *Fctx, th: f64) -> f64 { ret math.exp[f64](0.0f64 - gf(c, th)) }

// the step function whose sign change locates where g stops being infinite
fn inf_step(c: *Fctx, th: f64) -> f64 {
    if gf(c, th) == 1.0f64 / 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 1.0f64
}

fn fct1_cdf(a: *mem.Arena, x: f64, zeta: f64, alpha: f64, theta00: f64, give_i: bool, tol: f64, sub: usize) -> f64 {
    var theta0 = theta00
    let xmz = math.abs[f64](x - zeta)
    if x < zeta { theta0 = 0.0f64 - theta0 }
    var c: Fctx = zero
    c.alpha = alpha
    c.a1 = alpha - 1.0f64
    c.at0 = alpha * theta0
    c.cat0 = math.cos[f64](c.at0)
    c.xmz = xmz
    let lt = 0.0f64 - theta0
    var lth = lt + 0.000001f64 * math.abs[f64](lt)
    var uth = pi2() - 0.000001f64 * math.abs[f64](pi2())
    let inf = 1.0f64 / 0.0f64
    if alpha > 1.0f64 && gf(&c, lth) == inf {
        if inf_step(&c, lth) * inf_step(&c, pi2()) > 0.0f64 { ret 0.0f64 / 0.0f64 }
        lth = pw.zeroin[Fctx](&c, inf_step, lth, pi2(), 0.00000001f64, 1000i64)
    }
    if alpha < 1.0f64 && gf(&c, uth) == inf {
        if inf_step(&c, lth) * inf_step(&c, uth) > 0.0f64 { ret 0.0f64 / 0.0f64 }
        uth = pw.zeroin[Fctx](&c, inf_step, lth, uth, 0.00000001f64, 1000i64)
    }
    let (r, e) = qp.qags[Fctx](a, &c, expmg, lth, uth, tol, tol, sub)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if give_i { ret r.result / pi() }
    var c1 = 1.0f64
    if alpha < 1.0f64 { c1 = 0.5f64 - theta0 / pi() }
    ret c1 + sgn(1.0f64 - alpha) / pi() * r.result
}

// pstable(q, alpha, beta, gamma, delta, pm = 0, lower.tail = TRUE) for alpha != 1 (and the normal and Cauchy cases)
fn pstable(a: *mem.Arena, q: f64, alpha: f64, beta: f64, gamma: f64, delta: f64) -> f64 { ret pstable_tol(a, q, alpha, beta, gamma, delta, 64.0f64 * eps(), 1000usize) }

fn pstable_tol(a: *mem.Arena, q: f64, alpha: f64, beta: f64, gamma: f64, delta: f64, tol: f64, sub: usize) -> f64 { ret pstable_ext(a, q, alpha, beta, gamma, delta, tol, sub, true, false) }

// the value returned for a distribution value f on the lower (use_lower) or upper side, on the probability or log scale: R's retValue
fn ret_value(f: f64, use_lower: bool, log_p: bool) -> f64 {
    if use_lower {
        if log_p { ret math.log[f64](f) }
        ret f
    }
    if log_p { ret math.log[f64](1.0f64 - f) }
    ret 1.0f64 - f
}

// pstable with lower.tail and log.p (S0): stabledist's pstable, including the choice of the tail on which the integral is taken, which decides the precision of the far tails
fn pstable_ext(a: *mem.Arena, q: f64, alpha: f64, beta: f64, gamma: f64, delta: f64, tol: f64, sub: usize, lower: bool, log_p: bool) -> f64 {
    let x0 = (q - delta) / gamma
    if alpha == 2.0f64 { ret dist.pnorm(x0, 0.0f64, math.sqrt[f64](2.0f64), lower, log_p) }
    if alpha == 1.0f64 && beta == 0.0f64 {
        let pc = 0.5f64 + math.atan[f64](x0) / pi()
        ret ret_value(pc, lower, log_p)
    }
    if alpha == 1.0f64 {
        var x = x0
        var b = beta
        var use_l = lower
        if beta < 0.0f64 {
            b = 0.0f64 - beta
            x = 0.0f64 - x0
            use_l = !lower
        }
        var give_i = false
        if !use_l && !log_p {
            give_i = true
            use_l = true
        }
        let v = fct2_p(a, x, b, tol, give_i)
        ret ret_value(v, use_l, log_p)
    }
    let x = x0
    let tanpa2 = math.tan[f64](pi2() * alpha)
    let zeta = 0.0f64 - beta * tanpa2
    var th0 = math.atan[f64](0.0f64 - zeta) / alpha
    if th0 < 0.0f64 - pi2() { th0 = 0.0f64 - pi2() }
    if th0 > pi2() { th0 = pi2() }
    if math.abs[f64](beta) == 1.0f64 && alpha < 1.0f64 {
        if beta == 1.0f64 && x <= zeta { ret ret_value(0.0f64, lower, log_p) }
        if beta == 0.0f64 - 1.0f64 && x >= zeta { ret ret_value(1.0f64, lower, log_p) }
    }
    if math.abs[f64](x - zeta) < 2.0f64 * eps() {
        var r = 0.5f64 + th0 / pi()
        if lower { r = 0.5f64 - th0 / pi() }
        if log_p { ret math.log[f64](r) }
        ret r
    }
    let use_lower = (x > zeta && lower) || (x < zeta && !lower)
    let give_i = !use_lower && alpha > 1.0f64
    let f1 = fct1_cdf(a, x, zeta, alpha, th0, give_i, tol, sub)
    if give_i {
        if log_p { ret math.log[f64](f1) }
        ret f1
    }
    ret ret_value(f1, use_lower, log_p)
}

// qstable(p, alpha, beta, gamma, delta, pm = 0) on the lower tail: stabledist brackets the root with normal and Cauchy quantiles (and the tail bounds p / (1 - p)),
// then runs uniroot (Brent's zeroin, tolerance eps^0.25) on pstable at integration tolerance 1e-7 and 200 subdivisions; the bracket is assumed to contain the sign change
// (R's extendInt would widen it otherwise, and this returns NaN)
type Qctx = struct { a: *mem.Arena, alpha: f64, beta: f64, p: f64 }

fn qroot_fn(c: *Qctx, x: f64) -> f64 { ret pstable_tol(c.a, x, c.alpha, c.beta, 1.0f64, 0.0f64, 0.0000001f64, 200usize) - c.p }

fn qstable(a: *mem.Arena, p: f64, alpha: f64, beta: f64, gamma: f64, delta: f64) -> f64 {
    var res = 0.0f64
    if alpha == 2.0f64 {
        res = dist.qnorm(p, 0.0f64, math.sqrt[f64](2.0f64), true, false)
    } else if alpha == 1.0f64 && beta == 0.0f64 {
        res = math.tan[f64](pi() * (p - 0.5f64))
    } else {
        let left = p < 0.5f64
        let qn = dist.qnorm(p, 0.0f64, math.sqrt[f64](2.0f64), true, false)
        let qc = math.tan[f64](pi() * (p - 0.5f64))
        var xmin = 0.0f64
        var xmax = 0.0f64
        if beta < 0.0f64 {
            xmin = 0.0f64 - (1.0f64 - p) / p
            if left { xmax = qn } else { xmax = qc }
        } else if beta > 0.0f64 {
            if left { xmin = qc } else { xmin = qn }
            xmax = p / (1.0f64 - p)
        } else {
            if left { xmin = qc } else { xmin = qn }
            if left { xmax = qn } else { xmax = qc }
        }
        if xmin >= xmax {
            var fdx = 0.0f64
            if xmin == xmax {
                var m = math.abs[f64](xmin)
                if m < 0.0000001f64 { m = 0.0000001f64 }
                fdx = 0.01f64 * m
            } else {
                fdx = 1.01f64 * (xmin - xmax)
            }
            xmin = xmin - fdx
            xmax = xmax + fdx
        }
        var c: Qctx = zero
        c.a = a
        c.alpha = alpha
        c.beta = beta
        c.p = p
        // uniroot(extendInt = "upX"): widen the end points in steps that double while f(lower) > 0 or f(upper) < 0
        var flo = qroot_fn(&c, xmin)
        var fup = qroot_fn(&c, xmax)
        var d1 = 0.01f64 * math.abs[f64](xmin)
        if d1 < 0.000001f64 { d1 = 0.000001f64 }
        var d2 = 0.01f64 * math.abs[f64](xmax)
        if d2 < 0.000001f64 { d2 = 0.000001f64 }
        var it = 0usize
        while flo > 0.0f64 {
            xmin = xmin - d1
            flo = qroot_fn(&c, xmin)
            it += 1usize
            if it > 1000usize { ret 0.0f64 / 0.0f64 }
            d1 = 2.0f64 * d1
        }
        it = 0usize
        while fup < 0.0f64 {
            xmax = xmax + d2
            fup = qroot_fn(&c, xmax)
            it += 1usize
            if it > 1000usize { ret 0.0f64 / 0.0f64 }
            d2 = 2.0f64 * d2
        }
        res = pw.zeroin[Qctx](&c, qroot_fn, xmin, xmax, pw.uniroot_tol(), 1000i64)
    }
    ret res * gamma + delta
}

// rstable(n, alpha, beta, gamma, delta, pm = 0): n draws by the Chambers-Mallows-Stuck formula from R's uniform stream, the angles first (theta = pi (u - 1/2) for all
// n) and then the exponentials (w = -log u for all n), so a stream seeded as set.seed gives R's values; alpha = 1 with beta = 0 draws the n Cauchy variates after those
fn rstable(r: *rg.Rng, n: usize, alpha: f64, beta: f64, gamma: f64, delta: f64, out: []f64, theta: []f64, w: []f64) {
    var i = 0usize
    while i < n {
        theta[i] = pi() * (rg.unif(r) - 0.5f64)
        i += 1usize
    }
    i = 0usize
    while i < n {
        w[i] = 0.0f64 - math.log[f64](rg.unif(r))
        i += 1usize
    }
    if alpha == 1.0f64 && beta == 0.0f64 {
        i = 0usize
        while i < n {
            out[i] = math.tan[f64](pi() * rg.unif(r)) * gamma + delta
            i += 1usize
        }
        ret
    }
    let btp = beta * math.tan[f64](pi2() * alpha)
    var th0 = math.atan[f64](btp) / alpha
    if th0 < 0.0f64 - pi2() { th0 = 0.0f64 - pi2() }
    if th0 > pi2() { th0 = pi2() }
    let cc = math.pow[f64](1.0f64 + btp * btp, 1.0f64 / (2.0f64 * alpha))
    i = 0usize
    while i < n {
        let at = alpha * (theta[i] + th0)
        let rr = (cc * math.sin[f64](at) / math.pow[f64](math.cos[f64](theta[i]), 1.0f64 / alpha)) * math.pow[f64](math.cos[f64](theta[i] - at) / w[i], (1.0f64 - alpha) / alpha)
        out[i] = (rr - btp) * gamma + delta
        i += 1usize
    }
}

// ---- alpha = 1, beta != 0: stabledist:::.fct2 (the density) and .FCT2 (the distribution), the integral over u in (-1, 1) of a transformed integrand
fn tanpi2(u: f64) -> f64 {
    if u != 0.0f64 && u == math.floor[f64](u + 0.5f64) {
        var m = u - 4.0f64 * math.floor[f64](u / 4.0f64)
        if m < 0.0f64 { m = m + 4.0f64 }
        ret (2.0f64 - m) * (1.0f64 / 0.0f64)
    }
    ret math.tan[f64](pi2() * u)
}

fn cospi2(u: f64) -> f64 {
    if u == math.floor[f64](u + 0.5f64) {
        if u == 0.0f64 { ret 1.0f64 }
        ret 0.0f64
    }
    ret math.cos[f64](pi2() * u)
}

type F2ctx = struct { p2b: f64, ea: f64, u0: f64, mode: usize }

// g(u), zero within 1e-10 of u0
fn g2f(c: *F2ctx, u: f64) -> f64 {
    if math.abs[f64](u - c.u0) < 1.0e-10f64 { ret 0.0f64 }
    let h = c.p2b + u * pi2()
    ret (h / c.p2b) * math.exp[f64](c.ea + h * tanpi2(u)) / cospi2(u)
}

fn g2x(c: *F2ctx, u: f64) -> f64 { ret xexpmx(g2f(c, u)) }

fn g2m1(c: *F2ctx, u: f64) -> f64 { ret g2f(c, u) - 1.0f64 }

fn g2exp(c: *F2ctx, u: f64) -> f64 { ret math.exp[f64](0.0f64 - g2f(c, u)) }

fn g2expm1(c: *F2ctx, u: f64) -> f64 { ret math.exp[f64](0.0f64 - g2f(c, u)) - 1.0f64 }

fn g2step(c: *F2ctx, u: f64) -> f64 {
    if g2f(c, u) == 1.0f64 / 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 1.0f64
}

fn fct2_d(a: *mem.Arena, x: f64, beta: f64, tol: f64) -> f64 {
    let i2b = 1.0f64 / (2.0f64 * beta)
    var c: F2ctx = zero
    c.p2b = pi() * i2b
    c.ea = 0.0f64 - c.p2b * x
    if c.ea == 1.0f64 / 0.0f64 || c.ea == 0.0f64 - 1.0f64 / 0.0f64 { ret 0.0f64 }
    c.u0 = 0.0f64 - sgn(beta)
    if g2m1(&c, 0.0f64 - 1.0f64) * g2m1(&c, 1.0f64) > 0.0f64 { ret 0.0f64 / 0.0f64 }
    let u2 = pw.zeroin[F2ctx](&c, g2m1, 0.0f64 - 1.0f64, 1.0f64, tol, 1000i64)
    let (r1, e1) = qp.qags[F2ctx](a, &c, g2x, 0.0f64 - 1.0f64, u2, tol, tol, 1000usize)
    let (r2, e2) = qp.qags[F2ctx](a, &c, g2x, u2, 1.0f64, tol, tol, 1000usize)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    ret pi2() * math.abs[f64](i2b) * (r1.result + r2.result)
}

// .FCT2: with give_i the value of the integral of expm1(-g) negated, else the integral of exp(-g), halved
fn fct2_p(a: *mem.Arena, x: f64, beta: f64, tol: f64, give_i: bool) -> f64 {
    let i2b = 1.0f64 / (2.0f64 * beta)
    var c: F2ctx = zero
    c.p2b = pi() * i2b
    c.ea = 0.0f64 - c.p2b * x
    if c.ea == 1.0f64 / 0.0f64 || c.ea == 0.0f64 - 1.0f64 / 0.0f64 {
        var l = 0.0f64
        if c.ea < 0.0f64 { l = 1.0f64 }
        if give_i { ret 1.0f64 - l }
        ret l
    }
    c.u0 = 0.0f64 - 1.0f64
    var up = 1.0f64
    let uu = 1.0f64 - 0.000001f64 * 1.0f64
    if g2f(&c, uu) == 1.0f64 / 0.0f64 {
        up = pw.zeroin[F2ctx](&c, g2step, 0.0f64 - 1.0f64, uu, 0.00000001f64, 1000i64)
    }
    var r = 0.0f64
    if give_i {
        let (q, e) = qp.qags[F2ctx](a, &c, g2expm1, 0.0f64 - 1.0f64, up, tol, tol, 1000usize)
        if e != ok { ret 0.0f64 / 0.0f64 }
        r = q.result / 2.0f64
        ret 0.0f64 - r
    }
    let (q2, e2) = qp.qags[F2ctx](a, &c, g2exp, 0.0f64 - 1.0f64, up, tol, tol, 1000usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    ret q2.result / 2.0f64
}
