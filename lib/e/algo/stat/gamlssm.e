// R gamlss.dist: the mean and variance functions kept in the family objects of the families that e.algo.stat.gamlssdist.family_moment and family_moment2 do not carry (family()$mean and
// family()$variance; the families without such functions have none here either): fam 0 BB (bd), 1 BEINF, 2 BNB, 3 GAF, 4 GB2, 5 GIG, 6 GT, 7 JSUo, 8 NBF, 9 NET, 10 NOF, 11 PARETO2o, 12 PE2,
// 13 PIG, 14 SHASHo, 15 SN2, 16 SST, 17 ST2, 18 ST3, 19 ST4, 20 ST5, 21 WARING, 22 ZABNB, 23 ZAPIG, 24 ZASICHEL, 25 ZAZIPF, 26 ZIBNB, 27 ZIPF, 28 ZIPIG, 29 ZISICHEL; which 0 mean, 1 variance;
// Inf and NaN where the package answers them. The GIG variance integrates in the package (integrate over (0, Inf) with its defaults), and so does this, through the QUADPACK qagi port.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.algo.stat.gamlssdist as gd
use e.algo.stat.gslfns as gs
use e.algo.stat.pwr as pw
use e.math.quadpack as qp
use e.mem

fn beta_(a: f64, b: f64) -> f64 { ret math.exp[f64](nb.lbeta(a, b)) }

type GigInt = struct { order: f64, t: f64 }

fn gig_integrand(c: *GigInt, x: f64) -> f64 { ret math.pow[f64](x, c.order - 1.0f64) * math.exp[f64](0.0f64 - 0.5f64 * c.t * (x + 1.0f64 / x)) }

fn gig_k(a: *mem.Arena, order: f64, t: f64) -> f64 {
    var c = GigInt { order: order, t: t }
    let tol = pw.uniroot_tol()
    let (r, e) = qp.qagi[GigInt](a, &c, gig_integrand, 0.0f64, 1i64, tol, tol, 100usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret r.result * 0.5f64
}

fn family_moment3(a: *mem.Arena, fam: usize, which: usize, mu: f64, sigma: f64, nu: f64, tau: f64, bd: f64) -> f64 {
    let inf = 1.0f64 / 0.0f64
    let nan = 0.0f64 / 0.0f64
    let pv = 3.141592653589793f64
    let s2 = sigma * sigma
    if fam == 0usize {
        if which == 0usize { ret bd * mu }
        ret bd * mu * (1.0f64 - mu) * (1.0f64 + sigma * (bd - 1.0f64) / (1.0f64 + sigma))
    }
    if fam == 1usize {
        if which == 0usize { ret (mu + tau) / (1.0f64 + nu + tau) }
        ret (s2 * mu * (1.0f64 - mu) + mu * mu + tau + ((mu + tau) * (mu + tau)) * (1.0f64 / (1.0f64 + nu + tau))) / (1.0f64 + nu + tau)
    }
    if fam == 2usize {
        if which == 0usize { ret mu }
        if sigma < 1.0f64 { ret mu * (1.0f64 + mu * nu) * (1.0f64 + sigma / nu) / (1.0f64 - sigma) }
        ret inf
    }
    if fam == 3usize {
        if which == 0usize { ret mu }
        ret s2 * math.pow[f64](mu, nu)
    }
    if fam == 4usize {
        if which == 0usize {
            if tau > 1.0f64 / sigma { ret mu * beta_(nu + 1.0f64 / sigma, tau - 1.0f64 / sigma) / beta_(nu, tau) }
            ret inf
        }
        if tau > 2.0f64 / sigma {
            let b1 = beta_(nu + 1.0f64 / sigma, tau - 1.0f64 / sigma)
            ret mu * mu * (beta_(nu + 2.0f64 / sigma, tau - 2.0f64 / sigma) * beta_(nu, tau) - b1 * b1) / (beta_(nu, tau) * beta_(nu, tau))
        }
        ret inf
    }
    if fam == 5usize {
        if which == 0usize { ret mu }
        let t = 1.0f64 / s2
        let b = gig_k(a, nu + 1.0f64, t) / gig_k(a, nu, t)
        ret mu * mu * ((2.0f64 * s2 * (nu + 1.0f64)) / b + 1.0f64 / (b * b) - 1.0f64)
    }
    if fam == 6usize {
        if which == 0usize { if nu * tau > 1.0f64 { ret mu } else { ret nan } }
        if nu * tau > 2.0f64 { ret (s2 * math.pow[f64](nu, 2.0f64 / tau) * beta_(3.0f64 / tau, nu - 2.0f64 / tau)) / beta_(1.0f64 / tau, nu) }
        ret inf
    }
    if fam == 7usize {
        let e1 = math.exp[f64](1.0f64 / (tau * tau))
        if which == 0usize { ret mu - sigma * math.sqrt[f64](e1) * gd.sinh_of(nu / tau) }
        ret 0.5f64 * s2 * (e1 - 1.0f64) * (e1 * gd.cosh_of(2.0f64 * nu / tau) + 1.0f64)
    }
    if fam == 8usize {
        if which == 0usize { ret mu }
        ret mu + sigma * math.pow[f64](mu, nu)
    }
    if fam == 9usize {
        if which == 0usize { if nu * tau > 2.0f64 { ret mu } else { ret nan } }
        if nu * tau > 3.0f64 {
            let c1 = math.sqrt[f64](2.0f64 * pv) * (2.0f64 * dist.pnorm(nu, 0.0f64, 1.0f64, true, false) - 1.0f64)
            let c2 = 2.0f64 / nu * math.exp[f64](0.0f64 - nu * nu / 2.0f64)
            let c3 = 2.0f64 / (nu * (nu * tau - 1.0f64)) * math.exp[f64](0.0f64 - nu * tau + nu * nu / 2.0f64)
            let c = 1.0f64 / (c1 + c2 + c3)
            ret 2.0f64 * s2 * c * (math.sqrt[f64](2.0f64 * pv) * (dist.pnorm(nu, 0.0f64, 1.0f64, true, false) - 0.5f64) + (2.0f64 / nu + 2.0f64 / (nu * nu * nu)) * math.exp[f64](0.0f64 - nu * nu / 2.0f64) + (nu * nu * tau * tau + 4.0f64 * nu * tau + 6.0f64) / (nu * nu * nu * (nu * tau - 3.0f64)) * math.exp[f64](0.0f64 - nu * tau + nu * nu / 2.0f64))
        }
        ret inf
    }
    if fam == 10usize {
        if which == 0usize { ret mu }
        ret s2 * math.pow[f64](mu, nu)
    }
    if fam == 11usize {
        if which == 0usize { if sigma > 1.0f64 { ret mu / (sigma - 1.0f64) } else { ret inf } }
        if sigma > 2.0f64 { ret (sigma * mu * mu) / ((sigma - 1.0f64) * (sigma - 1.0f64) * (sigma - 2.0f64)) }
        ret inf
    }
    if fam == 12usize {
        if which == 0usize { ret mu }
        ret s2 / (nm.gammafn(1.0f64 / nu) / nm.gammafn(3.0f64 / nu))
    }
    if fam == 13usize {
        if which == 0usize { ret mu }
        ret mu + sigma * mu * mu
    }
    if fam == 14usize {
        let q1 = 1.0f64 / tau
        let p1 = math.exp[f64](0.25f64) / math.sqrt[f64](8.0f64 * pv) * (gs.bessel_knu((q1 + 1.0f64) / 2.0f64, 0.25f64) + gs.bessel_knu((q1 - 1.0f64) / 2.0f64, 0.25f64))
        if which == 0usize { ret mu + sigma * gd.sinh_of(nu / tau) * p1 }
        let q2 = 2.0f64 / tau
        let p2 = math.exp[f64](0.25f64) / math.sqrt[f64](8.0f64 * pv) * (gs.bessel_knu((q2 + 1.0f64) / 2.0f64, 0.25f64) + gs.bessel_knu((q2 - 1.0f64) / 2.0f64, 0.25f64))
        let sp1 = gd.sinh_of(nu / tau) * p1
        ret s2 / 2.0f64 * (gd.cosh_of(2.0f64 * nu / tau) * p2 - 1.0f64) - s2 * sp1 * sp1
    }
    if fam == 15usize {
        let k = math.sqrt[f64](2.0f64) / math.sqrt[f64](pv) * (nu - 1.0f64 / nu)
        if which == 0usize { ret mu + sigma * k }
        ret s2 * ((nu * nu + 1.0f64 / (nu * nu) - 1.0f64) - k * k)
    }
    if fam == 16usize {
        if which == 0usize { ret mu }
        ret s2
    }
    if fam == 17usize {
        let ez = (nu * math.sqrt[f64](tau) * nm.gammafn((tau - 1.0f64) / 2.0f64)) / (math.sqrt[f64](1.0f64 + nu * nu) * math.sqrt[f64](pv) * nm.gammafn(tau / 2.0f64))
        if which == 0usize { if tau > 1.0f64 { ret mu + sigma * ez } else { ret nan } }
        if tau > 2.0f64 { ret s2 * (tau / (tau - 2.0f64) - ez * ez) }
        ret nan
    }
    if fam == 18usize {
        let ez = (2.0f64 * math.sqrt[f64](tau) * (nu - 1.0f64 / nu)) / ((tau - 1.0f64) * beta_(0.5f64, tau / 2.0f64))
        if which == 0usize { if tau > 1.0f64 { ret mu + sigma * ez } else { ret nan } }
        if tau > 2.0f64 { ret s2 * (tau / (tau - 2.0f64) * (nu * nu + 1.0f64 / (nu * nu) - 1.0f64) - ez * ez) }
        ret nan
    }
    if fam == 19usize {
        let c = 2.0f64 / (math.sqrt[f64](nu) * beta_(0.5f64, nu / 2.0f64) + math.sqrt[f64](tau) * beta_(0.5f64, tau / 2.0f64))
        if which == 0usize {
            if nu > 1.0f64 && tau > 1.0f64 { ret mu + sigma * (c * (tau / (tau - 1.0f64) - nu / (nu - 1.0f64))) }
            ret nan
        }
        if nu > 2.0f64 && tau > 2.0f64 {
            let ez1 = c * (tau / (tau - 1.0f64) - nu / (nu - 1.0f64))
            let ez2 = (c * math.pow[f64](tau, 1.5f64) * beta_(0.5f64, tau / 2.0f64)) / (2.0f64 * (tau - 2.0f64)) + (c * math.pow[f64](nu, 1.5f64) * beta_(0.5f64, nu / 2.0f64)) / (2.0f64 * (nu - 2.0f64))
            ret s2 * (ez2 - ez1 * ez1)
        }
        ret nan
    }
    if fam == 20usize {
        let aa = (1.0f64 + nu * math.pow[f64](2.0f64 * tau + nu * nu, 0.0f64 - 0.5f64)) / tau
        let bb = (1.0f64 - nu * math.pow[f64](2.0f64 * tau + nu * nu, 0.0f64 - 0.5f64)) / tau
        let ez1 = (math.sqrt[f64](aa + bb) * (aa - bb) * nm.gammafn(aa - 0.5f64) * nm.gammafn(bb - 0.5f64)) / (2.0f64 * nm.gammafn(aa) * nm.gammafn(bb))
        if which == 0usize { if aa > 0.5f64 && bb > 0.5f64 { ret mu + sigma * ez1 } else { ret nan } }
        if aa > 1.0f64 && bb > 1.0f64 {
            let ez2 = ((aa + bb) * ((aa - bb) * (aa - bb) + aa + bb - 2.0f64)) / (4.0f64 * (aa - 1.0f64) * (bb - 1.0f64))
            ret s2 * (ez2 - ez1 * ez1)
        }
        ret nan
    }
    if fam == 21usize {
        if which == 0usize { ret mu }
        if sigma < 1.0f64 { ret mu * (mu + 1.0f64) * (1.0f64 + sigma) / (1.0f64 - sigma) }
        ret inf
    }
    if fam == 22usize {
        let p0 = gd.dbnb(0.0f64, mu, sigma, nu)
        let c = (1.0f64 - tau) / (1.0f64 - p0)
        if which == 0usize { ret mu * c }
        if sigma < 1.0f64 { ret c * mu * (1.0f64 + mu * nu) * (1.0f64 + sigma / nu) / (1.0f64 - sigma) + c * (1.0f64 - c) * mu * mu }
        ret inf
    }
    if fam == 23usize {
        let al = math.sqrt[f64](1.0f64 / s2 + 2.0f64 * mu / sigma)
        let c = (1.0f64 - nu) / (1.0f64 - math.exp[f64](1.0f64 / sigma - al))
        if which == 0usize { ret mu * c }
        ret mu * c + c * mu * mu * (1.0f64 + sigma - c)
    }
    if fam == 24usize {
        let p0 = gd.dsichel(0.0f64, mu, sigma, nu)
        let c = (1.0f64 - tau) / (1.0f64 - p0)
        if which == 0usize { ret mu * c }
        let b = gs.bessel_knu(nu + 1.0f64, 1.0f64 / sigma) / gs.bessel_knu(nu, 1.0f64 / sigma)
        let h1 = 1.0f64 / c * (2.0f64 * sigma * (nu + 1.0f64) / b + 1.0f64 / (b * b)) - 1.0f64
        ret c * mu + c * c * mu * mu * h1
    }
    if fam == 25usize {
        let b = gd.zeta_p(mu) / gd.zeta_p(mu + 1.0f64)
        if which == 0usize { if mu > 1.0f64 { ret b * (1.0f64 - sigma) } else { ret inf } }
        if mu > 2.0f64 { ret (1.0f64 - sigma) * (gd.zeta_p(mu - 1.0f64) / gd.zeta_p(mu + 1.0f64)) - (1.0f64 - sigma) * (1.0f64 - sigma) * b * b }
        ret inf
    }
    if fam == 26usize {
        if which == 0usize { ret (1.0f64 - tau) * mu }
        ret (1.0f64 - tau) * mu * (1.0f64 + mu * nu) * (1.0f64 + sigma / nu) * (1.0f64 / (1.0f64 - sigma)) + tau * (1.0f64 - tau) * mu * mu
    }
    if fam == 27usize {
        if which == 0usize { if mu > 1.0f64 { ret gd.zeta_p(mu) / gd.zeta_p(mu + 1.0f64) } else { ret inf } }
        if mu > 2.0f64 { ret (gd.zeta_p(mu + 1.0f64) * gd.zeta_p(mu - 1.0f64) - gd.zeta_p(mu) * gd.zeta_p(mu)) / (gd.zeta_p(mu + 1.0f64) * gd.zeta_p(mu + 1.0f64)) }
        ret inf
    }
    if fam == 28usize {
        if which == 0usize { ret (1.0f64 - nu) * mu }
        ret mu * (1.0f64 - nu) + mu * mu * (1.0f64 - nu) * (sigma + nu)
    }
    if which == 0usize { ret (1.0f64 - tau) * mu }
    let b = gs.bessel_knu(nu + 1.0f64, 1.0f64 / sigma) / gs.bessel_knu(nu, 1.0f64 / sigma)
    let h1 = (1.0f64 / (1.0f64 - tau)) * ((2.0f64 * sigma * (nu + 1.0f64) / b) + (1.0f64 / (b * b))) - 1.0f64
    ret (1.0f64 - tau) * mu + (1.0f64 - tau) * (1.0f64 - tau) * mu * mu * h1
}
