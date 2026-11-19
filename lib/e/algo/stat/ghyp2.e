// R GeneralizedHyperbolic, second part: DistributionUtils::incompleteBesselK (the Slevinsky-Safouhi G transformation of the package's Fortran, line for line),
// pgig on it, and qgig by both of the package's methods ("spline" and "integrate").

use e.algo.stat.ghyp as gh
use e.algo.stat.gslfns as gs
use e.algo.stat.pwr as pw
use e.algo.stat.splinepkg as sl
use e.math
use e.mem

// Fortran IBF(x, y, nu, eps, nmax, KNu): integral from 1 to Inf of t^(-nu - 1) exp(-x t - y / t) dt; KNu is besselK(2 sqrt(x y), nu). Returns NaN when the
// order cap is reached (the package warns and returns an unreliable value).
fn ibf_ssf(am: []f64, nmax: usize, nu: f64, from: usize, to: usize) {
    let w = nmax + 1usize
    if from == 0usize { am[0usize] = 1.0f64 }
    var l = from
    if l == 0usize { l = 1usize }
    while l <= to {
        var k = 1usize
        while k < l {
            am[l * w + k] = (0.0f64 - nu + f64(k) + f64(l) - 1.0f64) * am[(l - 1usize) * w + k] + am[(l - 1usize) * w + k - 1usize]
            k += 1usize
        }
        am[l * w] = (0.0f64 - nu + f64(l) - 1.0f64) * am[(l - 1usize) * w]
        am[l * w + l] = 1.0f64
        l += 1usize
    }
}

fn ibf_comb(cnp: []f64, from: usize, to: usize) {
    var n = from
    while n <= to {
        cnp[n * (n + 1usize) / 2usize] = 1.0f64
        cnp[n * (n + 1usize) / 2usize + n] = 1.0f64
        var np_ = 1usize
        while np_ + 1usize <= n {
            cnp[n * (n + 1usize) / 2usize + np_] = cnp[n * (n - 1usize) / 2usize + np_ - 1usize] + cnp[n * (n - 1usize) / 2usize + np_]
            np_ += 1usize
        }
        n += 1usize
    }
}

fn ibf_powi(x: f64, n: usize) -> f64 {
    var r = 1.0f64
    var i = 0usize
    while i < n {
        r = r * x
        i += 1usize
    }
    ret r
}

fn ibf_gdenom(n: usize, x: f64, y: f64, nu: f64, an: []const f64, nmax: usize, cnp: []const f64, gn: []f64) {
    let w = nmax + 1usize
    var s = 0.0f64
    var ir = 0usize
    while ir <= n {
        var t = 0.0f64
        var i = 0usize
        while i <= ir {
            t = t + an[ir * w + i] * ibf_powi(x, i)
            i += 1usize
        }
        s = s + cnp[n * (n + 1usize) / 2usize + ir] * ibf_powi(0.0f64 - 1.0f64 / y, ir) * t
        ir += 1usize
    }
    gn[n] = s * ibf_powi(0.0f64 - x * y, n) * math.pow[f64](x, nu + 1.0f64) * math.exp[f64](x + y)
}

fn ibf_gnum(n: usize, x: f64, y: f64, nu: f64, am: []const f64, nmax: usize, cnp: []const f64, gm: []f64, gn: []const f64) {
    let w = nmax + 1usize
    var s = 0.0f64
    var ir = 1usize
    while ir <= n {
        var t = 0.0f64
        var is_ = 0usize
        while is_ < ir {
            var tp = 0.0f64
            var i = 0usize
            while i <= is_ {
                tp = tp + am[is_ * w + i] * ibf_powi(0.0f64 - x, i)
                i += 1usize
            }
            t = t + tp * cnp[ir * (ir - 1usize) / 2usize + is_] * ibf_powi(1.0f64 / y, is_)
            is_ += 1usize
        }
        s = s + cnp[n * (n + 1usize) / 2usize + ir] * ibf_powi(x * y, ir) * gn[n - ir] * t
        ir += 1usize
    }
    gm[n - 1usize] = s * math.exp[f64](0.0f64 - x - y) / math.pow[f64](x, nu) / y
}

fn incomplete_bessel_k_ssf(a: *mem.Arena, x: f64, y: f64, nu: f64, eps: f64, nmax: usize) -> f64 {
    let start = mem.mark(a)
    let w = nmax + 1usize
    let (am, e1) = mem.alloc[f64](a, w * w)
    let (an, e2) = mem.alloc[f64](a, w * w)
    let (cnp, e3) = mem.alloc[f64](a, (nmax + 1usize) * (nmax + 2usize) / 2usize + 1usize)
    let (gm, e4) = mem.alloc[f64](a, nmax + 1usize)
    let (gn, e5) = mem.alloc[f64](a, nmax + 2usize)
    let (gg, e6) = mem.alloc[f64](a, nmax + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0.0f64 / 0.0f64 }
    var res = 0.0f64 / 0.0f64
    var xx = x
    var yy = y
    var nn = nu
    var sgn = 1.0f64
    if !(x >= y) {
        xx = y
        yy = x
        nn = 0.0f64 - nu
        sgn = 0.0f64 - 1.0f64
    }
    ibf_comb(cnp, 0usize, 1usize)
    ibf_ssf(am, nmax, nn - 1.0f64, 0usize, 1usize)
    ibf_ssf(an, nmax, 0.0f64 - nn - 1.0f64, 0usize, 1usize)
    ibf_gdenom(0usize, xx, yy, nn, an, nmax, cnp, gn)
    ibf_gdenom(1usize, xx, yy, nn, an, nmax, cnp, gn)
    ibf_gnum(1usize, xx, yy, nn, am, nmax, cnp, gm, gn)
    gg[1usize] = math.pow[f64](xx, nn) * gm[0usize] / gn[1usize]
    var k = 2usize
    var done = false
    while k <= nmax && !done {
        ibf_comb(cnp, k, k)
        ibf_ssf(am, nmax, nn - 1.0f64, k, k)
        ibf_ssf(an, nmax, 0.0f64 - nn - 1.0f64, k, k)
        ibf_gdenom(k, xx, yy, nn, an, nmax, cnp, gn)
        ibf_gnum(k, xx, yy, nn, am, nmax, cnp, gm, gn)
        gg[k] = math.pow[f64](xx, nn) * gm[k - 1usize] / gn[k]
        if math.abs[f64](gg[k] - gg[k - 1usize]) < eps {
            res = gg[k]
            done = true
        }
        k += 1usize
    }
    if done && sgn < 0.0f64 {
        let kn = gs.bessel_knu(nu, 2.0f64 * math.sqrt[f64](x * y))
        res = 2.0f64 * math.pow[f64](x / y, nu / 2.0f64) * kn - res
    }
    mem.reset(a, start)
    ret res
}

// pgig on the package's incomplete Bessel function: lower tail 1 - q^lambda const incompleteBesselK(psi q / 2, chi / (2 q), -lambda), upper tail without the 1
fn pgig_ssf(a: *mem.Arena, q: f64, chi: f64, psi: f64, lambda: f64, tol: f64, nmax: usize, lower: bool) -> f64 {
    var up = 1.0f64
    if q > 0.0f64 {
        if q == 1.0f64 / 0.0f64 {
            up = 0.0f64
        } else {
            let omega = math.sqrt[f64](chi * psi)
            let kom = gs.bessel_knu(lambda, omega)
            let cst = math.pow[f64](psi / chi, lambda / 2.0f64) / (2.0f64 * kom)
            up = cst * math.pow[f64](q, lambda) * incomplete_bessel_k_ssf(a, psi * q / 2.0f64, chi / (2.0f64 * q), 0.0f64 - lambda, tol, nmax)
        }
    }
    if lower { ret 1.0f64 - up }
    ret up
}

type GigC = struct { chi: f64, psi: f64, lambda: f64, level: f64, a: *mem.Arena, tol: f64, nmax: usize, p: f64, lower: bool, n: usize, sx: []f64, sy: []f64, sb: []f64, sc: []f64, sd: []f64 }

fn gig_range(chi: f64, psi: f64, lambda: f64, tol: f64) -> (f64, f64) {
    let mode = gh.gig_mode(chi, psi, lambda)
    let sd = math.sqrt[f64](gh.gig_var(chi, psi, lambda))
    var c: GigC = zero
    c.chi = chi
    c.psi = psi
    c.lambda = lambda
    c.level = tol
    var hi = mode + sd
    while gh.dgig(hi, chi, psi, lambda) > tol { hi = hi + sd }
    let tl = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let up = pw.zeroin[GigC](&c, gig_dens_minus, mode, hi, tl, 1000i64)
    let dn = pw.zeroin[GigC](&c, gig_dens_minus, 0.0f64, mode, tl, 1000i64)
    ret (dn, up)
}

fn gig_dens_minus(c: *GigC, x: f64) -> f64 { ret gh.dgig(x, c.chi, c.psi, c.lambda) - c.level }

fn gig_spline_minus(c: *GigC, x: f64) -> f64 { ret sl.spline_eval(c.n, c.sx, c.sy, c.sb, c.sc, c.sd, x) - c.p }

fn gig_cdf_minus(c: *GigC, x: f64) -> f64 { ret pgig_ssf(c.a, x, c.chi, c.psi, c.lambda, c.tol, c.nmax, c.lower) - c.p }

// qgig(p, chi, psi, lambda, method = "integrate", ibfTol, nmax) for a single p: the lower branch roots pgig on (0, mode), the upper branch the upper tail on (mode, xHigh)
fn qgig_integrate(a: *mem.Arena, p0: f64, chi: f64, psi: f64, lambda: f64, ibf_tol: f64, nmax: usize) -> f64 {
    let eps = 2.220446049250313e-16f64
    let e5 = math.pow[f64](eps, 5.0f64)
    let mode = gh.gig_mode(chi, psi, lambda)
    let pmode = pgig_ssf(a, mode, chi, psi, lambda, ibf_tol, nmax, true)
    let tl = 0.0000001f64
    var c: GigC = zero
    c.chi = chi
    c.psi = psi
    c.lambda = lambda
    c.a = a
    c.tol = ibf_tol
    c.nmax = nmax
    c.p = p0
    if p0 <= e5 { ret 0.0f64 }
    if p0 <= pmode {
        c.lower = true
        ret pw.zeroin[GigC](&c, gig_cdf_minus, 0.0f64, mode, tl, 1000i64)
    }
    var p = p0
    if p0 < 1.0f64 - e5 { p = 1.0f64 - p0 }
    if p >= 1.0f64 - eps { ret 1.0f64 / 0.0f64 }
    if !(p0 < 1.0f64 - e5) { ret 0.0f64 / 0.0f64 }
    let sd = math.sqrt[f64](gh.gig_var(chi, psi, lambda))
    var xhigh = mode + sd
    while pgig_ssf(a, xhigh, chi, psi, lambda, math.pow[f64](eps, 0.85f64), nmax, false) >= p { xhigh = xhigh + sd }
    c.lower = false
    c.p = p
    ret pw.zeroin[GigC](&c, gig_cdf_minus, mode, xhigh, tl, 1000i64)
}

// qgig with the default method "spline": the upper-tail table at ibfTol = max(ibfTol, eps^0.25) on nInterpol points of gigCalcRange(tol = 1e-7), an fmm spline, uniroot
// at tolerance uniTol; probabilities outside the table fall to the integrate method
fn qgig(a: *mem.Arena, p: f64, chi: f64, psi: f64, lambda: f64, n_interpol: usize, ibf_tol: f64, nmax: usize) -> f64 {
    let (xl, xu) = gig_range(chi, psi, lambda, 0.0000001f64)
    let p_lo = pgig_ssf(a, xl, chi, psi, lambda, ibf_tol, nmax, true)
    let p_hi = pgig_ssf(a, xu, chi, psi, lambda, ibf_tol, nmax, true)
    if !(p > p_lo && p < p_hi) { ret qgig_integrate(a, p, chi, psi, lambda, ibf_tol, nmax) }
    let n = n_interpol
    let (xs, e1) = mem.alloc[f64](a, n)
    let (ys, e2) = mem.alloc[f64](a, n)
    let (bb, e3) = mem.alloc[f64](a, n)
    let (cc, e4) = mem.alloc[f64](a, n)
    let (dd, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    var tb = ibf_tol
    let t25 = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    if t25 > tb { tb = t25 }
    var i = 0usize
    while i < n {
        xs[i] = xl + (xu - xl) * f64(i) / f64(n - 1usize)
        i += 1usize
    }
    xs[n - 1usize] = xu
    i = 0usize
    while i < n {
        ys[i] = pgig_ssf(a, xs[i], chi, psi, lambda, tb, nmax, true)
        i += 1usize
    }
    sl.fmm_spline(n, xs, ys, bb, cc, dd)
    var c: GigC = zero
    c.n = n
    c.sx = xs
    c.sy = ys
    c.sb = bb
    c.sc = cc
    c.sd = dd
    c.p = p
    ret pw.zeroin[GigC](&c, gig_spline_minus, xl, xu, 0.0000001f64, 1000i64)
}
