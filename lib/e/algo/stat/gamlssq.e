// R gamlss.dist: the distribution and quantile functions that e.algo.stat.gamlssdist does not carry, written the way the package writes them (the search over the support with
// max.value for the counts, uniroot over a bracket grown in steps of sigma for the integrated skew families, the closed forms elsewhere): GPO, LQNO, NBF, NET, NOF, PIG2, ST1,
// ZAZIPF and ZINBF distributions; BB, BNB, GPO, LQNO, NBF, NET, NOF, PIG, PIG2, SEP1, SEP2, ST1, ST2, ST4, ST5, WARING, ZABB, ZABNB, ZALG, ZAPIG, ZAZIPF, ZIBB, ZIBNB, ZINBF, ZIPF and
// ZIPIG quantiles. The quantile of ZIPIG passes nu to the package's qPIG positionally, where it lands on lower.tail, so that qZIPIG answers the upper tail of the PIG quantile; so does this port.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.algo.stat.gamlssdist as gd
use e.algo.stat.pwr as pw
use e.math.quadpack as qp
use e.mem

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn b2f(b: bool) -> f64 {
    var r = 0.0f64
    if b { r = 1.0f64 }
    ret r
}

// the closing lines of every quantile function: p == 0 and p == 1 take the given values, p outside [0, 1] is NaN
fn fin(p: f64, v: f64, at0: f64, at1: f64) -> f64 {
    if p == 0.0f64 { ret at0 }
    if p == 1.0f64 { ret at1 }
    if p < 0.0f64 { ret nan() }
    if p > 1.0f64 { ret nan() }
    ret v
}

fn fl(x: f64) -> f64 { ret math.floor[f64](x) }

// pGU as the package ships it: the line `cdf[q >= -Inf] <- 0` follows the Gumbel expression and overwrites every value, so the function is 0 for every finite q and 1 at +Inf
// (gamlssdist.pgu is the Gumbel distribution the line was meant to leave)
fn pgu(q: f64, mu: f64, sigma: f64) -> f64 {
    if q == inf() { ret 1.0f64 }
    ret 0.0f64
}

// normal-based
fn lqno_sd(mu: f64, sigma: f64) -> f64 { ret math.sqrt[f64](mu * (1.0f64 + sigma * mu)) }

fn plqno(q: f64, mu: f64, sigma: f64) -> f64 { ret dist.pnorm(q, mu, lqno_sd(mu, sigma), true, false) }

fn qlqno(p: f64, mu: f64, sigma: f64) -> f64 { ret fin(p, dist.qnorm(p, mu, lqno_sd(mu, sigma), true, false), 0.0f64 - inf(), inf()) }

fn nof_sd(mu: f64, sigma: f64, nu: f64) -> f64 { ret sigma * math.pow[f64](math.abs[f64](mu), nu / 2.0f64) }

fn pnof(q: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret dist.pnorm(q, mu, nof_sd(mu, sigma, nu), true, false) }

fn qnof(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret fin(p, dist.qnorm(p, mu, nof_sd(mu, sigma, nu), true, false), 0.0f64 - inf(), inf()) }

// NET (normal exponential t): the package adds the masked pieces as products, so a piece that is NaN poisons the sum even where its mask is 0, and so do these
fn net_ct(nu: f64, tau: f64) -> f64 {
    let c1 = (1.0f64 - 2.0f64 * dist.pnorm(0.0f64 - nu, 0.0f64, 1.0f64, true, false)) * math.sqrt[f64](2.0f64 * gd.pi())
    let c2 = (2.0f64 / nu) * math.exp[f64](0.0f64 - (nu * nu) / 2.0f64)
    let c3 = 2.0f64 * math.exp[f64](0.0f64 - nu * tau + (nu * nu) / 2.0f64) / ((nu * tau - 1.0f64) * nu)
    ret 1.0f64 / (c1 + c2 + c3)
}

fn pnet(q: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let k1 = nu
    let k2 = tau
    let ct = net_ct(nu, tau)
    let tc = (q - mu) / sigma
    var pw_t = 1.0f64
    if tc != 0.0f64 { pw_t = math.pow[f64](math.abs[f64](tc), 0.0f64 - k1 * k2 + 1.0f64) }
    let fk2 = (ct * math.pow[f64](k2, k1 * k2) / (k1 * k2 - 1.0f64)) * math.exp[f64](0.0f64 - k1 * k2 + (k1 * k1) / 2.0f64) * pw_t
    let cdf1 = (ct / (k1 * (k1 * k2 - 1.0f64))) * math.exp[f64](0.0f64 - k1 * k2 + (k1 * k1) / 2.0f64)
    let fk1 = cdf1 + (ct / k1) * math.exp[f64](0.0f64 - k1 * math.abs[f64](tc) + (k1 * k1) / 2.0f64)
    let cdf2 = cdf1 + (ct / k1) * math.exp[f64](0.0f64 - (k1 * k1) / 2.0f64)
    let f0 = cdf2 + ct * math.sqrt[f64](2.0f64 * gd.pi()) * (dist.pnorm(0.0f64 - math.abs[f64](tc), 0.0f64, 1.0f64, true, false) - dist.pnorm(0.0f64 - k1, 0.0f64, 1.0f64, true, false))
    ret b2f(tc <= 0.0f64 - k2) * fk2 + b2f(tc > 0.0f64 - k2 && tc <= 0.0f64 - k1) * fk1 + b2f(tc > 0.0f64 - k1 && tc <= 0.0f64) * f0 + b2f(tc > 0.0f64 && tc <= k1) * (1.0f64 - f0) + b2f(tc > k1 && tc <= k2) * (1.0f64 - fk1) + b2f(tc > k2) * (1.0f64 - fk2)
}

fn qnet(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var p1 = p
    if p > 0.5f64 { p1 = 1.0f64 - p }
    let p2 = p1
    let ct = net_ct(nu, tau)
    let b = (ct / (nu * (nu * tau - 1.0f64))) * math.exp[f64](0.0f64 - nu * tau + (nu * nu) / 2.0f64)
    let z1 = 0.0f64 - math.pow[f64](b * nu * math.pow[f64](tau, nu * tau) / p1, 1.0f64 / (nu * tau - 1.0f64))
    if !(p1 >= nu * tau * b) { p1 = 0.5f64 }
    let z2 = 0.0f64 - nu / 2.0f64 + (1.0f64 / nu) * math.log[f64]((nu / ct) * (p1 - b))
    let z3 = dist.qnorm(dist.pnorm(0.0f64 - nu, 0.0f64, 1.0f64, true, false) + (1.0f64 / math.sqrt[f64](2.0f64 * gd.pi())) * ((p1 - b) / ct - (1.0f64 / nu) * math.exp[f64](0.0f64 - (nu * nu) / 2.0f64)), 0.0f64, 1.0f64, true, false)
    let edge = b + (ct / nu) * math.exp[f64](0.0f64 - (nu * nu) / 2.0f64)
    let q1 = b2f(p2 <= nu * tau * b) * z1 + b2f(p1 > nu * tau * b && p1 <= edge) * z2 + b2f(p1 > edge && p1 < 0.5f64) * z3
    var q = 0.0f64 - q1
    if p <= 0.5f64 { q = q1 }
    ret fin(p, mu + sigma * q, 0.0f64 - inf(), inf())
}

// skew t (ST4 and ST5 in closed form)
fn qst4(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var lk1 = nm.lgammafn(0.5f64) + nm.lgammafn(nu / 2.0f64) - nm.lgammafn((nu + 1.0f64) / 2.0f64) + 0.5f64 * math.log[f64](nu)
    if !(nu < 1000000.0f64) { lk1 = 0.5f64 * math.log[f64](2.0f64 * gd.pi()) }
    var lk2 = nm.lgammafn(0.5f64) + nm.lgammafn(tau / 2.0f64) - nm.lgammafn((tau + 1.0f64) / 2.0f64) + 0.5f64 * math.log[f64](tau)
    if !(tau < 1000000.0f64) { lk2 = 0.5f64 * math.log[f64](2.0f64 * gd.pi()) }
    let k = math.exp[f64](lk2 - lk1)
    var q = 0.0f64
    if p < 1.0f64 / (1.0f64 + k) { q = mu + sigma * nb.qt(p * (1.0f64 + k) / 2.0f64, nu, true, false) } else { q = mu + sigma * nb.qt((p * (1.0f64 + k) - 1.0f64) / (2.0f64 * k) + 0.5f64, tau, true, false) }
    ret fin(p, q, 0.0f64 - inf(), inf())
}

fn qst5(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    let ve = 2.0f64 / tau
    let lam = 2.0f64 * nu / (tau * math.sqrt[f64](2.0f64 * tau + nu * nu))
    let a = (ve + lam) / 2.0f64
    let b = (ve - lam) / 2.0f64
    let ba = nb.qbeta(p, a, b, true, false)
    let z = (math.sqrt[f64](a + b)) * (2.0f64 * ba - 1.0f64) / (2.0f64 * math.sqrt[f64](ba * (1.0f64 - ba)))
    ret fin(p, mu + sigma * z, 0.0f64 - inf(), inf())
}

// ST1 and the quantiles of SEP1, SEP2, ST1 and ST2 (kind 0, 1, 2, 3): integrate() over (-Inf, z] and the package's bracket and uniroot
type St1Ctx = struct { nu: f64, tau: f64 }

fn st1_dens(c: *St1Ctx, x: f64) -> f64 { ret gd.dst1(x, 0.0f64, 1.0f64, c.nu, c.tau) }

fn pst1(a: *mem.Arena, x: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var c: St1Ctx = zero
    c.nu = nu
    c.tau = tau
    let tol = pw.uniroot_tol()
    let (r, e) = qp.qagi[St1Ctx](a, &c, st1_dens, (x - mu) / sigma, 0i64 - 1i64, tol, tol, 100usize)
    if e != ok { ret nan() }
    ret r.result
}

type RootCtx = struct { a: *mem.Arena, kind: usize, mu: f64, sigma: f64, nu: f64, tau: f64, p: f64 }

fn root_h(c: *RootCtx, q: f64) -> f64 {
    if c.kind == 0usize { ret gd.psep1(c.a, q, c.mu, c.sigma, c.nu, c.tau) }
    if c.kind == 1usize { ret gd.psep2(c.a, q, c.mu, c.sigma, c.nu, c.tau) }
    if c.kind == 2usize { ret pst1(c.a, q, c.mu, c.sigma, c.nu, c.tau) }
    ret gd.pst2(c.a, q, c.mu, c.sigma, c.nu, c.tau)
}

fn root_h1(c: *RootCtx, q: f64) -> f64 { ret root_h(c, q) - c.p }

fn qroot(a: *mem.Arena, kind: usize, p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if p <= 0.0f64 || p >= 1.0f64 { ret fin(p, 0.0f64, 0.0f64 - inf(), inf()) }
    var c: RootCtx = zero
    c.a = a
    c.kind = kind
    c.mu = mu
    c.sigma = sigma
    c.nu = nu
    c.tau = tau
    c.p = p
    var lo = 0.0f64
    var hi = 0.0f64
    if root_h(&c, mu) < p {
        lo = mu
        hi = mu + sigma
        var j = 2.0f64
        while root_h(&c, hi) < p {
            hi = mu + j * sigma
            j += 1.0f64
        }
    } else {
        lo = mu - sigma
        hi = mu
        var j = 2.0f64
        while root_h(&c, lo) > p {
            lo = mu - j * sigma
            j += 1.0f64
        }
    }
    ret pw.zeroin[RootCtx](&c, root_h1, lo, hi, pw.uniroot_tol(), 1000i64)
}

fn qsep1(a: *mem.Arena, p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret qroot(a, 0usize, p, mu, sigma, nu, tau) }

fn qsep2(a: *mem.Arena, p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret qroot(a, 1usize, p, mu, sigma, nu, tau) }

fn qst1(a: *mem.Arena, p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret qroot(a, 2usize, p, mu, sigma, nu, tau) }

fn qst2(a: *mem.Arena, p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 { ret qroot(a, 3usize, p, mu, sigma, nu, tau) }

// the counts: NBF (negative binomial family, sigma mu^(nu - 2)), ZINBF
fn nbf_s(mu: f64, sigma: f64, nu: f64) -> f64 { ret sigma * math.pow[f64](mu, nu - 2.0f64) }

fn pnbf(q: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    if q >= inf() { ret 1.0f64 }
    let s1 = nbf_s(mu, sigma, nu)
    if s1 > 0.0001f64 { ret nb.pnbinom_mu(q, 1.0f64 / s1, mu, true, false) }
    ret nm.ppois(q, mu, true, false)
}

fn qnbf(p: f64, mu: f64, sigma: f64, nu: f64) -> f64 {
    let s1 = nbf_s(mu, sigma, nu)
    if s1 < 0.0001f64 { ret nm.qpois(p, mu, true, false) }
    ret nb.qnbinom_mu(p, 1.0f64 / s1, mu, true, false)
}

fn pzinbf(q: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    if q == inf() { ret 1.0f64 }
    ret tau + (1.0f64 - tau) * pnbf(q, mu, sigma, nu)
}

fn qzinbf(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64) -> f64 {
    var pnew = (p - tau) / (1.0f64 - tau)
    if pnew < 0.0f64 { pnew = 0.0f64 }
    ret qzinbf_pn(p, pnew, mu, sigma, nu)
}

fn qzinbf_pn(p: f64, pnew: f64, mu: f64, sigma: f64, nu: f64) -> f64 { ret fin(p, qnbf(pnew, mu, sigma, nu), 0.0f64, inf()) }

// GPO: the package sums dGPO over 0 .. floor(q) and answers log(ppois) when sigma < 1e-4
fn pgpo(q: f64, mu: f64, sigma: f64) -> f64 {
    var cdf = 0.0f64
    if q >= inf() {
        cdf = gd.dgpo(0.0f64, mu, sigma) + gd.dgpo(1.0f64, mu, sigma)
    } else {
        var j = 0.0f64
        let top = fl(q)
        while j <= top {
            cdf += gd.dgpo(j, mu, sigma)
            j += 1.0f64
        }
    }
    if sigma < 0.0001f64 { cdf = math.log[f64](nm.ppois(q, mu, true, false)) }
    if q < 0.0f64 { cdf = 0.0f64 }
    if q >= inf() { cdf = 1.0f64 }
    ret cdf
}

// the search the package uses for BNB, GPO, PIG and WARING: the first j in from .. max.value whose distribution function reaches p (max.value when none does); Inf once p + 1e-9 >= 1
type CntCtx = struct { kind: usize, mu: f64, sigma: f64, nu: f64 }

fn cnt_mass(c: *CntCtx, j: f64) -> f64 {
    if c.kind == 0usize { ret gd.dbnb(j, c.mu, c.sigma, c.nu) }
    if c.kind == 2usize { ret gd.dpig(j, c.mu, c.sigma) }
    ret gd.dwaring(j, c.mu, c.sigma)
}

fn cnt_search(c: *CntCtx, p: f64, max_value: f64) -> f64 {
    if p + 1.0e-9f64 >= 1.0f64 { ret inf() }
    var cum = 0.0f64
    var j = 0.0f64
    var q = 0.0f64
    while j <= max_value {
        cum += cnt_mass(c, j)
        q = j
        if p <= cum { break }
        j += 1.0f64
    }
    ret q
}

fn qbnb(p: f64, mu: f64, sigma: f64, nu: f64, max_value: f64) -> f64 {
    var c = CntCtx { kind: 0usize, mu: mu, sigma: sigma, nu: nu }
    ret fin(p, cnt_search(&c, p, max_value), 0.0f64, inf())
}

fn qpig(p: f64, mu: f64, sigma: f64, max_value: f64) -> f64 {
    var c = CntCtx { kind: 2usize, mu: mu, sigma: sigma, nu: 0.0f64 }
    ret fin(p, cnt_search(&c, p, max_value), 0.0f64, inf())
}

fn qwaring(p: f64, mu: f64, sigma: f64, max_value: f64) -> f64 {
    var c = CntCtx { kind: 3usize, mu: mu, sigma: sigma, nu: 0.0f64 }
    ret fin(p, cnt_search(&c, p, max_value), 0.0f64, inf())
}

fn qgpo(p: f64, mu: f64, sigma: f64, max_value: f64) -> f64 {
    var q = 0.0f64
    if p + 1.0e-9f64 >= 1.0f64 {
        q = inf()
    } else {
        var j = 0.0f64
        while j <= max_value {
            let cp = pgpo(j, mu, sigma)
            q = j
            if p <= cp { break }
            j += 1.0f64
        }
    }
    ret fin(p, q, 0.0f64, inf())
}

// PIG2 (PIG with the second parametrisation: alpha = 1 / (sqrt(mu^2 + sigma^2) - mu)); the upper tail with qPIG's lower.tail = FALSE is built into the ZIPIG quantile
fn pig2_alpha(mu: f64, sigma: f64) -> f64 { ret 1.0f64 / (math.sqrt[f64](mu * mu + sigma * sigma) - mu) }

fn ppig2(q: f64, mu: f64, sigma: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    if q == inf() { ret 1.0f64 }
    ret gd.ppig(q, mu, pig2_alpha(mu, sigma))
}

fn qpig2(p: f64, mu: f64, sigma: f64, max_value: f64) -> f64 { ret fin(p, qpig(p, mu, pig2_alpha(mu, sigma), max_value), 0.0f64, inf()) }

fn qzipf(p: f64, mu: f64, max_value: f64) -> f64 {
    var q = 0.0f64
    if p + 1.0e-9f64 >= 1.0f64 {
        q = inf()
    } else {
        var j = 1.0f64
        while j <= max_value {
            let cp = gd.pzipf(j, mu)
            q = j
            if p <= cp { break }
            j += 1.0f64
        }
    }
    ret fin(p, q, 0.0f64, inf())
}

fn pzazipf(q: f64, mu: f64, sigma: f64) -> f64 {
    if q <= 0.0f64 { ret 0.0f64 }
    var q1 = q
    if q == 0.0f64 { q1 = 1.0f64 }
    var cdf1 = 0.0f64
    if q != 0.0f64 { cdf1 = gd.pzipf(q1, mu) }
    ret sigma + (1.0f64 - sigma) * cdf1
}

fn qzazipf(p: f64, mu: f64, sigma: f64, max_value: f64) -> f64 {
    var pnew = (p - sigma) / (1.0f64 - sigma) - 1.0e-10f64
    if !(pnew > 0.0f64) { pnew = 0.0f64 }
    var q = 0.0f64
    if pnew > 0.0f64 { q = qzipf(pnew, mu, max_value) }
    ret fin(p, q, 0.0f64, inf())
}

// BB, ZABB and ZIBB
fn qbb(p: f64, mu: f64, sigma: f64, bd: f64) -> f64 {
    var q = 0.0f64
    var j = 0.0f64
    while j <= bd {
        let cp = gd.pbb(j, mu, sigma, bd)
        q = j
        if p <= cp { break }
        j += 1.0f64
    }
    if sigma < 0.0001f64 { q = gd.qbi(p, mu, bd) }
    ret fin(p, q, 0.0f64, bd)
}

fn qzabb(p: f64, mu: f64, sigma: f64, nu: f64, bd: f64) -> f64 {
    var pnew = (p - nu) / (1.0f64 - nu) - 0.0000001f64
    if pnew < 0.0f64 { pnew = 0.0f64 }
    let pnew2 = gd.pbb(0.0f64, mu, sigma, bd) * (1.0f64 - pnew) + pnew
    var q = 0.0f64
    if pnew > 0.0f64 { q = qbb(pnew2, mu, sigma, bd) }
    ret fin(p, q, 0.0f64, bd)
}

fn qzibb(p: f64, mu: f64, sigma: f64, nu: f64, bd: f64) -> f64 {
    var pnew = (p - nu) / (1.0f64 - nu) - 0.0000001f64
    if pnew < 0.0f64 { pnew = 0.0f64 }
    var q = 0.0f64
    if pnew > 0.0f64 { q = qbb(pnew, mu, sigma, bd) }
    ret fin(p, q, 0.0f64, bd)
}

// ZABNB, ZIBNB, ZAPIG, ZIPIG, ZALG
fn qzabnb(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64, max_value: f64) -> f64 {
    let pnew = (p - tau) / (1.0f64 - tau) - 1.0e-10f64
    let cdf0 = gd.pbnb(0.0f64, mu, sigma, nu)
    var pnew2 = cdf0 * (1.0f64 - pnew) + pnew
    if !(pnew2 > 0.0f64) { pnew2 = 0.0f64 }
    ret fin(p, qbnb(pnew2, mu, sigma, nu, max_value), 0.0f64, inf())
}

fn qzibnb(p: f64, mu: f64, sigma: f64, nu: f64, tau: f64, max_value: f64) -> f64 {
    var pnew = (p - tau) / (1.0f64 - tau)
    if pnew < 0.0f64 { pnew = 0.0f64 }
    ret qzibnb_pn(p, pnew, mu, sigma, nu, max_value)
}

// the tail of qZIBNB for a given pnew (the vector form of the package re-assigns pnew, see e.algo.stat.gamlssr)
fn qzibnb_pn(p: f64, pnew: f64, mu: f64, sigma: f64, nu: f64, max_value: f64) -> f64 { ret fin(p, qbnb(pnew, mu, sigma, nu, max_value), 0.0f64, inf()) }

fn qzapig(p: f64, mu: f64, sigma: f64, nu: f64, max_value: f64) -> f64 {
    let pnew = (p - nu) / (1.0f64 - nu) - 1.0e-10f64
    let cdf0 = gd.ppig(0.0f64, mu, sigma)
    var pnew2 = cdf0 * (1.0f64 - pnew) + pnew
    if !(pnew2 > 0.0f64) { pnew2 = 0.0f64 }
    ret fin(p, qpig(pnew2, mu, sigma, max_value), 0.0f64, inf())
}

fn qzipig(p: f64, mu: f64, sigma: f64, nu: f64, max_value: f64) -> f64 {
    var pnew = (p - nu) / (1.0f64 - nu)
    if pnew < 0.0f64 { pnew = 0.0f64 }
    var pu = pnew
    if nu != 1.0f64 { pu = 1.0f64 - pnew }
    ret fin(p, qpig(pu, mu, sigma, max_value), 0.0f64, inf())
}

fn qzalg(p: f64, mu: f64, sigma: f64, max_value: f64) -> f64 {
    var pnew = (p - sigma) / (1.0f64 - sigma) - 1.0e-10f64
    if !(pnew > 0.0f64) { pnew = 0.0f64 }
    var q = 0.0f64
    if pnew > 0.0f64 { q = gd.qlg(pnew, mu, max_value) }
    ret fin(p, q, 0.0f64, inf())
}
