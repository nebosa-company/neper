// R stabledist: the stable density dstable in the default S0 parametrisation (pm = 0), for alpha in [0.02, 2) with alpha != 1 (alpha = 2 is the normal, alpha = 1 with
// beta = 0 the Cauchy): Nolan's integral representation split at the mode of the integrand and at the points where it falls below 1e-4, each piece integrated with
// integrate() (e.math.quadpack.qags) at tolerance 64 eps and 1000 subdivisions, as stabledist:::.fct1 does.
//
// Not here: alpha below 0.02 (dstable.smallA), alpha = 1 with beta != 0, the Pareto-tail fallback when the integral underflows to zero, the other parametrisations,
// log densities, pstable, qstable and rstable.

use e.math
use e.math.dist as dist
use e.math.quadpack as qp
use e.math.special as sp
use e.mem
use e.algo.stat.pwr as pw

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
