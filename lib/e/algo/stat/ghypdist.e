// R GeneralizedHyperbolic, fourth part: pghyp with lower.tail and the integration tolerances, qghyp by both methods (spline with its integrate fallback for
// probabilities outside the table, including the package's lower.tail = FALSE behaviour), ghypCalcRange and ghypMode.

use e.algo.stat.ghyp as gh
use e.algo.stat.pwr as pw
use e.algo.stat.splinepkg as sl
use e.math
use e.math.quadpack as qp
use e.mem

type Qc = struct { g: gh.Gh, a: *mem.Arena, p: f64, lower: bool, tol: f64, sub: usize, level: f64, n: usize, sx: []f64, sy: []f64, sb: []f64, sc: []f64, sd: []f64 }

fn qc_new(a: *mem.Arena, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64) -> Qc {
    var c: Qc = zero
    c.g.mu = mu
    c.g.delta = delta
    c.g.alpha = alpha
    c.g.beta = beta
    c.g.lambda = lambda
    c.a = a
    c.tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    c.sub = 100usize
    ret c
}

// pghyp(q, lower.tail, subdivisions, intTol): the integral runs on the side of the mode q is on, the other tail is its complement
fn pghyp_tail(c: *Qc, q: f64, lower: bool, mode: f64) -> f64 {
    if q <= mode {
        let (r, e) = qp.qagi[gh.Gh](c.a, &c.g, gh.gh_dens, q, 0i64 - 1i64, c.tol, c.tol, c.sub)
        if e != ok { ret 0.0f64 / 0.0f64 }
        if lower { ret r.result }
        ret 1.0f64 - r.result
    }
    let (r2, e2) = qp.qagi[gh.Gh](c.a, &c.g, gh.gh_dens, q, 1i64, c.tol, c.tol, c.sub)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    if lower { ret 1.0f64 - r2.result }
    ret r2.result
}

fn qc_mode(c: *Qc) -> f64 { ret gh.ghyp_mode(c.g.mu, c.g.delta, c.g.alpha, c.g.beta, c.g.lambda) }

fn qc_cdf_minus(c: *Qc, x: f64) -> f64 { ret pghyp_tail(c, x, c.lower, c.level) - c.p }

fn qc_spline_minus(c: *Qc, x: f64) -> f64 { ret sl.spline_eval(c.n, c.sx, c.sy, c.sb, c.sc, c.sd, x) - c.p }

fn qc_dens_minus(c: *Qc, x: f64) -> f64 { ret gh.dghyp(x, c.g.mu, c.g.delta, c.g.alpha, c.g.beta, c.g.lambda) - c.level }

// ghypCalcRange(tol, density = TRUE): the density-tolerance range, found with uniroot at its default tolerance
fn ghyp_calc_range(a: *mem.Arena, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64, tol: f64) -> (f64, f64) {
    var c = qc_new(a, mu, delta, alpha, beta, lambda)
    c.level = tol
    let mode = qc_mode(&c)
    let sd = math.sqrt[f64](gh.ghyp_var(delta, alpha, beta, lambda))
    var hi = mode + sd
    while gh.dghyp(hi, mu, delta, alpha, beta, lambda) > tol { hi = hi + sd }
    let up = pw.zeroin[Qc](&c, qc_dens_minus, mode, hi, pw.uniroot_tol(), 1000i64)
    var lo = mode - sd
    while gh.dghyp(lo, mu, delta, alpha, beta, lambda) > tol { lo = lo - sd }
    let dn = pw.zeroin[Qc](&c, qc_dens_minus, lo, mode, pw.uniroot_tol(), 1000i64)
    ret (dn, up)
}

// qghyp(p, method = "integrate") for one p
fn qghyp_integrate(a: *mem.Arena, p0: f64, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64, uni_tol: f64, int_tol: f64, sub: usize) -> f64 {
    var c = qc_new(a, mu, delta, alpha, beta, lambda)
    c.tol = int_tol
    c.sub = sub
    let mode = qc_mode(&c)
    c.level = mode
    let sd = math.sqrt[f64](gh.ghyp_var(delta, alpha, beta, lambda))
    let e8 = math.pow[f64](2.220446049250313e-16f64, 8.0f64)
    let pmode = pghyp_tail(&c, mode, true, mode)
    if p0 <= e8 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p0 <= pmode {
        var xlow = mode - sd
        while pghyp_tail(&c, xlow, true, mode) >= p0 { xlow = xlow - sd }
        c.lower = true
        c.p = p0
        ret pw.zeroin[Qc](&c, qc_cdf_minus, xlow, mode, uni_tol, 1000i64)
    }
    if p0 >= 1.0f64 - e8 { ret 1.0f64 / 0.0f64 }
    let p = 1.0f64 - p0
    var xhigh = mode + sd
    while pghyp_tail(&c, xhigh, false, mode) >= p { xhigh = xhigh + sd }
    c.lower = false
    c.p = p
    ret pw.zeroin[Qc](&c, qc_cdf_minus, mode, xhigh, uni_tol, 1000i64)
}

// qghyp(p, lower.tail, method) for one p: lower.tail = FALSE takes 1 - p and, as in the package, hands probabilities outside the spline table to the integrate
// method with lower.tail = FALSE again, which takes 1 - p a second time
fn qghyp_full(a: *mem.Arena, p0: f64, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64, lower: bool, spline: bool, n_interpol: usize, uni_tol: f64, sub: usize) -> f64 {
    var p = p0
    if !lower { p = 1.0f64 - p0 }
    if !spline { ret qghyp_integrate(a, p, mu, delta, alpha, beta, lambda, uni_tol, uni_tol, sub) }
    var c = qc_new(a, mu, delta, alpha, beta, lambda)
    c.tol = uni_tol
    c.sub = sub
    let mode = qc_mode(&c)
    c.level = mode
    let (xl, xu) = ghyp_calc_range(a, mu, delta, alpha, beta, lambda, 0.00001f64)
    let p_lo = pghyp_tail(&c, xl, true, mode)
    let p_hi = pghyp_tail(&c, xu, true, mode)
    if !(p > p_lo && p < p_hi) {
        if lower { ret qghyp_integrate(a, p, mu, delta, alpha, beta, lambda, uni_tol, uni_tol, sub) }
        ret qghyp_integrate(a, 1.0f64 - p, mu, delta, alpha, beta, lambda, uni_tol, uni_tol, sub)
    }
    let n = n_interpol
    let (xs, e1) = mem.alloc[f64](a, n)
    let (ys, e2) = mem.alloc[f64](a, n)
    let (bb, e3) = mem.alloc[f64](a, n)
    let (cc, e4) = mem.alloc[f64](a, n)
    let (dd, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        xs[i] = xl + (xu - xl) * f64(i) / f64(n - 1usize)
        i += 1usize
    }
    xs[n - 1usize] = xu
    i = 0usize
    while i < n {
        ys[i] = pghyp_tail(&c, xs[i], true, mode)
        i += 1usize
    }
    sl.fmm_spline(n, xs, ys, bb, cc, dd)
    c.n = n
    c.sx = xs
    c.sy = ys
    c.sb = bb
    c.sc = cc
    c.sd = dd
    c.p = p
    ret pw.zeroin[Qc](&c, qc_spline_minus, xl, xu, uni_tol, 1000i64)
}

// DistributionUtils::momIntegrated(densFn, param, order, about, absolute): the integral of (x - about)^order (or its absolute value) times the density over the whole
// line (ghyp, hyperb: lambda given; gig: mu = chi, delta = psi, alpha = lambda; the package integrates the gig density over the whole line too), by integrate() with 1000 subdivisions and rel.tol sqrt(eps)
type MiC = struct { g: gh.Gh, about: f64, order: f64, absolute: bool, gig: bool }

fn mi_fn(c: *MiC, x: f64) -> f64 {
    var d = 0.0f64
    if c.gig { d = gh.dgig(x, c.g.mu, c.g.delta, c.g.alpha) } else { d = gh.dghyp(x, c.g.mu, c.g.delta, c.g.alpha, c.g.beta, c.g.lambda) }
    var b = x - c.about
    if c.absolute { b = math.abs[f64](b) }
    ret math.pow[f64](b, c.order) * d
}

fn mom_integrated(a: *mem.Arena, gig: bool, order: f64, about: f64, absolute: bool, p0: f64, p1: f64, p2: f64, p3: f64, p4: f64) -> f64 {
    var c: MiC = zero
    c.g.mu = p0
    c.g.delta = p1
    c.g.alpha = p2
    c.g.beta = p3
    c.g.lambda = p4
    c.about = about
    c.order = order
    c.absolute = absolute
    c.gig = gig
    let tol = math.sqrt[f64](2.220446049250313e-16f64)
    let inf = 2i64
    let (r, e) = qp.qagi[MiC](a, &c, mi_fn, 0.0f64, inf, tol, tol, 1000usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret r.result
}
