// R sn: the skew-normal and skew-t. dsn (with the extension parameter tau), psn by Owen's T (the package's series, including its
// high-h approximation), qsn by the Cornish-Fisher start and Newton steps (tau = 0), and dst.
//
// Not here: psn through the bivariate normal engine (tau != 0, or a point with z * alpha <= -5 in a short vector), qst, the
// random generators, the multivariate families, the cumulants for tau != 0 and selm.

use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.math.nmath as nm
use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.math.quadpack as quad
use e.math.root as root
use e.algo.stat.pbivnorm as bv
use e.mem

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

// psn through the bivariate normal engine (the package's scalar default, and any tau): P(Z <= z, T <= tau) at correlation -delta, over pnorm(tau)
fn psn_biv(x: f64, xi: f64, omega: f64, alpha: f64, tau: f64) -> f64 {
    let z = (x - xi) / omega
    let p = bv.pbivnorm(z, tau, 0.0f64 - alpha / math.sqrt[f64](1.0f64 + alpha * alpha)) / pn(tau)
    if p < 0.0f64 { ret 0.0f64 }
    if p > 1.0f64 { ret 1.0f64 }
    ret p
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

// ---- rsn and rst after set.seed ----

// rsn(n, xi, omega, alpha, tau): for tau = 0 the 2 n normals in pairs (|first|, second); otherwise n uniforms on (pnorm(-tau), 1) first, then n normals; out receives n values
fn rsn(a: *mem.Arena, n: usize, xi: f64, omega: f64, alpha: f64, tau: f64, seed: i64, out: []f64) -> err {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let delta = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
    ret rsn_draw(a, &rg, n, xi, omega, delta, tau, out)
}

fn rsn_draw(a: *mem.Arena, rg: *rng.Rng, n: usize, xi: f64, omega: f64, delta: f64, tau: f64, out: []f64) -> err {
    let sq = math.sqrt[f64](1.0f64 - delta * delta)
    if tau == 0.0f64 {
        var j = 0usize
        while j < n {
            let u0 = rng.norm(rg)
            let u1 = rng.norm(rg)
            out[j] = xi + omega * (delta * math.abs[f64](u0) + sq * u1)
            j += 1usize
        }
        ret ok
    }
    let (tn, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    let lo = pn(0.0f64 - tau)
    var j = 0usize
    while j < n {
        let u = lo + (1.0f64 - lo) * rng.unif(rg)
        tn[j] = dist.qnorm(u, 0.0f64, 1.0f64, true, false)
        j += 1usize
    }
    j = 0usize
    while j < n {
        out[j] = xi + omega * (delta * tn[j] + sq * rng.norm(rg))
        j += 1usize
    }
    ret ok
}

// rst(n, xi, omega, alpha, nu): the skew-normal sample (xi = 0) divided by the root of a chi-square variate over its degrees of freedom, then shifted; nu = Inf leaves it normal
fn rst(a: *mem.Arena, n: usize, xi: f64, omega: f64, alpha: f64, nu: f64, seed: i64, out: []f64) -> err {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let delta = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
    let e = rsn_draw(a, &rg, n, 0.0f64, omega, delta, 0.0f64, out)
    if e != ok { ret e }
    var j = 0usize
    if nu < 1.0e308f64 {
        while j < n {
            out[j] = out[j] / math.sqrt[f64](rd.rchisq(&rg, nu) / nu) + xi
            j += 1usize
        }
    } else {
        while j < n {
            out[j] = out[j] + xi
            j += 1usize
        }
    }
    ret ok
}

// st.cumulants(xi, omega, alpha, nu): the k-th cumulant, k = 1 to 4, of the skew-t (nu = Inf for the skew-normal); NaN where the moment does not exist and the infinite values at nu = 3 and 4 as the package gives them
fn st_cumulant(xi: f64, omega: f64, alpha: f64, nu: f64, k: usize) -> f64 {
    let delta = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
    var bn = math.sqrt[f64](2.0f64 / pi())
    var s2 = 1.0f64
    var s3 = 1.0f64
    var s4 = 1.0f64
    if nu < 1.0e300f64 {
        bn = math.sqrt[f64](nu / pi()) * math.exp[f64](nm.lgammafn((nu - 1.0f64) / 2.0f64) - nm.lgammafn(nu / 2.0f64))
        s2 = 1.0f64 / (1.0f64 - 2.0f64 / nu)
        s3 = 1.0f64 / (1.0f64 - 3.0f64 / nu)
        s4 = 1.0f64 / (1.0f64 - 4.0f64 / nu)
    }
    let mu = bn * delta
    let nan = 0.0f64 / 0.0f64
    if k == 1usize { ret xi + omega * mu }
    if k == 2usize {
        if nu <= 2.0f64 { ret nan }
        ret omega * omega * (s2 - mu * mu)
    }
    if k == 3usize {
        if nu < 3.0f64 + 1.0e-12f64 && nu > 3.0f64 - 1.0e-12f64 { ret math.copysign[f64](1.0f64, alpha) * (1.0f64 / 0.0f64) }
        if nu <= 3.0f64 { ret nan }
        ret omega * omega * omega * mu * ((3.0f64 - delta * delta) * s3 - 3.0f64 * s2 + 2.0f64 * mu * mu)
    }
    if nu < 4.0f64 + 1.0e-12f64 && nu > 4.0f64 - 1.0e-12f64 { ret 1.0f64 / 0.0f64 }
    if nu <= 4.0f64 { ret nan }
    let c2 = s2 - mu * mu
    ret omega * omega * omega * omega * ((3.0f64 * s2 * s4 - 4.0f64 * mu * mu * (3.0f64 - delta * delta) * s3 + 6.0f64 * mu * mu * s2 - 3.0f64 * mu * mu * mu * mu) - 3.0f64 * c2 * c2)
}

// dp2cp(c(xi, omega, alpha, nu)) of the proper type: which 0 the mean, 1 the standard deviation, 2 the skewness, 3 the excess kurtosis (NaN where the moment is missing); nu = Inf for the skew-normal
fn dp2cp(xi: f64, omega: f64, alpha: f64, nu: f64, which: usize) -> f64 {
    let k2 = st_cumulant(xi, omega, alpha, nu, 2usize)
    if which == 0usize { ret st_cumulant(xi, omega, alpha, nu, 1usize) }
    if which == 1usize { ret math.sqrt[f64](k2) }
    if which == 2usize { ret st_cumulant(xi, omega, alpha, nu, 3usize) / (k2 * math.sqrt[f64](k2)) }
    ret st_cumulant(xi, omega, alpha, nu, 4usize) / (k2 * k2)
}

// cp2dp(c(mean, sd, skewness), "SN"): which 0 xi, 1 omega, 2 alpha; NaN when |skewness| is beyond the skew-normal limit
fn cp2dp_sn(mean: f64, sd: f64, skew: f64, which: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let lim = 0.9952717464311565f64
    if math.abs[f64](skew) >= lim { ret nan }
    let c = 2.0f64 * skew / (4.0f64 - pi())
    var g = math.pow[f64](math.abs[f64](c), 1.0f64 / 3.0f64)
    if c < 0.0f64 { g = 0.0f64 - g }
    let muz = g / math.sqrt[f64](1.0f64 + g * g)
    let delta = muz / math.sqrt[f64](2.0f64 / pi())
    let omega = sd / math.sqrt[f64](1.0f64 - muz * muz)
    if which == 1usize { ret omega }
    if which == 0usize { ret mean - omega * muz }
    ret delta / math.sqrt[f64](1.0f64 - delta * delta)
}

// ---- pst (method 0) ----

type PstCtx = struct { alpha: f64, nu: f64, z: f64 }

// composite 15-point Gauss-Kronrod of f over (lo, hi) in 64 panels; the integrands here are smooth
fn gk_int(c: *PstCtx, f: fn(*PstCtx, f64) -> f64, lo: f64, hi: f64) -> f64 {
    let np = 64usize
    let w = (hi - lo) / f64(np)
    var tot = 0.0f64
    var p = 0usize
    while p < np {
        let mid = lo + w * (f64(p) + 0.5f64)
        let hw = w / 2.0f64
        var s = quad.wgk15(7usize) * f(c, mid)
        var j = 0usize
        while j < 7usize {
            let d = hw * quad.xgk15(j)
            s += quad.wgk15(j) * (f(c, mid - d) + f(c, mid + d))
            j += 1usize
        }
        tot += s * hw
        p += 1usize
    }
    ret tot
}

fn dst_std(c: *PstCtx, x: f64) -> f64 { ret dst(x, 0.0f64, 1.0f64, c.alpha, c.nu) }

fn fp_chisq(c: *PstCtx, v: f64) -> f64 {
    ret psn_owen(math.sqrt[f64](v) * c.z, 0.0f64, 1.0f64, c.alpha) * nm.dchisq(v * c.nu, c.nu, false) * c.nu
}

// pst_int: the integer-nu closed form by recursion
fn pst_int(z: f64, alpha: f64, nu: f64) -> f64 {
    if nu == 1.0f64 { ret math.atan[f64](z) / pi() + math.acos[f64](alpha / math.sqrt[f64]((1.0f64 + alpha * alpha) * (1.0f64 + z * z))) / pi() }
    if nu == 2.0f64 {
        let s = math.sqrt[f64](2.0f64 + z * z)
        ret 0.5f64 - math.atan[f64](alpha) / pi() + (0.5f64 + math.atan[f64](z * alpha / s) / pi()) * z / s
    }
    let a = pst_int(math.sqrt[f64]((nu - 2.0f64) / nu) * z, alpha, nu - 2.0f64)
    let b = pst_int(math.sqrt[f64](nu - 1.0f64) * alpha * z / math.sqrt[f64](nu + z * z), 0.0f64, nu - 1.0f64)
    let k = nm.lgammafn((nu - 1.0f64) / 2.0f64) + (nu / 2.0f64 - 1.0f64) * math.log[f64](nu) - 0.5f64 * math.log[f64](pi()) - nm.lgammafn(nu / 2.0f64) - 0.5f64 * (nu - 1.0f64) * math.log[f64](nu + z * z)
    ret a + b * z * math.exp[f64](k)
}

// st_tails (threshold 20): the log tail probability beyond |x|, on the side x is on
fn st_tails_lp(x: f64, alpha: f64, nu: f64) -> f64 {
    if alpha < 0.0f64 { ret st_tails_lp(0.0f64 - x, 0.0f64 - alpha, nu) }
    var s = 0.0f64 - 1.0f64
    if x > 0.0f64 { s = 1.0f64 }
    let lc = math.log[f64](2.0f64) + nm.lgammafn((nu + 1.0f64) / 2.0f64) + (nu / 2.0f64) * math.log[f64](nu) + nb.pt(s * alpha * math.sqrt[f64](nu + 1.0f64), nu + 1.0f64, true, true) - nm.lgammafn(nu / 2.0f64) - 0.5f64 * math.log[f64](pi())
    ret lc - math.log[f64](nu) - nu * math.log[f64](math.abs[f64](x))
}

// pst method 2: the mass of the half below zero plus the integral of the density from zero
fn pst_dst(z: f64, alpha: f64, nu: f64) -> f64 {
    var c = PstCtx { alpha: alpha, nu: nu, z: z }
    let dl = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
    var lo = 0.0f64
    var hi = z
    var sg = 1.0f64
    if z < 0.0f64 {
        lo = z
        hi = 0.0f64
        sg = 0.0f64 - 1.0f64
    }
    ret math.acos[f64](dl) / pi() + sg * gk_int(&c, dst_std, lo, hi)
}

// pst(x, xi, omega, alpha, nu) lower tail, method 0, one point
fn pst(a: *mem.Arena, x: f64, xi: f64, omega: f64, alpha: f64, nu: f64) -> f64 {
    if nu > 1.0e300f64 { ret psn_owen(x, xi, omega, alpha) }
    let z = (x - xi) / omega
    if nu == 1.0f64 {
        let dl = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
        ret math.atan[f64](z) / pi() + math.acos[f64](dl / math.sqrt[f64](1.0f64 + z * z)) / pi()
    }
    if alpha == 0.0f64 { ret nb.pt(z, nu, true, false) }
    if math.abs[f64](alpha) > 1.0e300f64 {
        var z0 = z
        if alpha * z < 0.0f64 { z0 = 0.0f64 }
        let p = nb.pf(z0 * z0, 1.0f64, nu, true, false)
        if alpha < 0.0f64 { ret 1.0f64 - p }
        ret p
    }
    let intnu = nu == math.floor[f64](nu + 0.5f64)
    if intnu && nu <= 6.0f64 { ret pst_int(z, alpha, nu) }
    if math.abs[f64](z) > 30.0f64 + 1.0f64 / math.sqrt[f64](nu) {
        let lp = st_tails_lp(z, alpha, nu)
        if z < 0.0f64 { ret math.exp[f64](lp) }
        ret 1.0f64 - math.exp[f64](lp)
    }
    var c = PstCtx { alpha: alpha, nu: nu, z: z }
    var p = 0.0f64
    if z < 10.0f64 + 50.0f64 / nu {
        p = pst_dst(z, alpha, nu)
    } else {
        let (r, e) = quad.qagi(a, &c, fp_chisq, 0.0f64, 1i64, 1.220703125e-4f64, 1.220703125e-4f64, 100usize)
        if e != ok { ret 0.0f64 / 0.0f64 }
        p = r.result
    }
    if p < 0.0f64 { p = 0.0f64 }
    if p > 1.0f64 { p = 1.0f64 }
    ret p
}

// qsc: the skew-Cauchy quantile
fn qsc(p: f64, xi: f64, omega: f64, alpha: f64) -> f64 {
    if p <= 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if p >= 1.0f64 { ret 1.0f64 / 0.0f64 }
    let u = (p - 0.5f64) * pi()
    let dl = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
    ret xi + omega * (dl / math.cos[f64](u) + math.tan[f64](u))
}

// qst(p, xi, omega, alpha, nu), method 0, tol 1e-8: the package's bracket (qst_bounds) then alternating bisection and regula falsi
fn qst(a: *mem.Arena, p0: f64, xi: f64, omega: f64, alpha: f64, nu: f64) -> f64 {
    let inf = 1.0f64 / 0.0f64
    if nu > 10000.0f64 { ret qsn(p0, xi, omega, alpha) }
    if nu == 1.0f64 { ret qsc(p0, xi, omega, alpha) }
    if alpha > 1.0e300f64 { ret xi + omega * math.sqrt[f64](nb.qf(p0, 1.0f64, nu, true, false)) }
    if alpha < 0.0f64 - 1.0e300f64 { ret xi - omega * math.sqrt[f64](nb.qf(1.0f64 - p0, 1.0f64, nu, true, false)) }
    var p = p0
    if alpha < 0.0f64 { p = 1.0f64 - p0 }
    var sgn = 1.0f64
    if alpha < 0.0f64 { sgn = 0.0f64 - 1.0f64 }
    let aa = math.abs[f64](alpha)
    if p == 0.0f64 { ret xi + omega * sgn * (0.0f64 - inf) }
    if p == 1.0f64 { ret xi + omega * sgn * inf }
    var xa = nb.qt(p, nu, true, false)
    var xb = xa
    if alpha != 0.0f64 {
        let lower = xa
        let upper = math.sqrt[f64](nb.qf(p, 1.0f64, nu, true, false))
        xa = lower
        xb = upper
        if upper - lower > 5.0f64 {
            var step = 5.0f64
            var m = 0.0f64
            var go = true
            while go {
                xa = upper - step
                if pst_dst(xa, aa, nu) < p { go = false } else {
                    step = step * math.pow[f64](2.0f64, 2.0f64 / (m + 2.0f64))
                    m += 1.0f64
                }
            }
        }
    }
    var fa = pst(a, xa, 0.0f64, 1.0f64, aa, nu) - p
    var fb = pst(a, xb, 0.0f64, 1.0f64, aa, nu) - p
    var rf = false
    var xc = 0.0f64
    var it = 0i32
    var go = true
    while go && it < 500i32 {
        if rf { xc = xb - fb * (xb - xa) / (fb - fa) } else { xc = (xb + xa) / 2.0f64 }
        let fc = pst(a, xc, 0.0f64, 1.0f64, aa, nu) - p
        if fc > 0.0f64 {
            xb = xc
            fb = fc
        } else {
            xa = xc
            fa = fc
        }
        let bad = (xc - xa) * (xc - xb)
        if bad > 0.0f64 || bad != bad { ret 0.0f64 / 0.0f64 }
        if math.abs[f64](fc) < 1.0e-8f64 { go = false }
        rf = !rf
        it += 1i32
    }
    var sg2 = 1.0f64
    if alpha < 0.0f64 { sg2 = 0.0f64 - 1.0f64 }
    ret xi + omega * sg2 * xc
}

// ---- cp2dp for the skew-t ----

type CpCtx = struct { g1: f64, g2: f64, delta: f64, nu: f64 }

// b(nu) of the package: E|T| scale of the skew-t, with its large-nu expansion
fn b_nu(nu: f64) -> f64 {
    if nu > 10000.0f64 { ret math.sqrt[f64](2.0f64 / pi()) * (1.0f64 + 0.75f64 / nu + 0.78125f64 / (nu * nu)) }
    ret math.sqrt[f64](nu / pi()) * math.exp[f64](nm.lgammafn((nu - 1.0f64) / 2.0f64) - nm.lgammafn(nu / 2.0f64))
}

// st.gamma1(delta, nu) and st.gamma2: skewness and excess kurtosis of the standard skew-t from delta directly
fn st_gamma(delta: f64, nu: f64, which: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let inf = 1.0f64 / 0.0f64
    if math.abs[f64](delta) > 1.0f64 { ret nan }
    let mu = b_nu(nu) * delta
    let s2 = 1.0f64 / (1.0f64 - 2.0f64 / nu)
    let s3 = 1.0f64 / (1.0f64 - 3.0f64 / nu)
    let s4 = 1.0f64 / (1.0f64 - 4.0f64 / nu)
    let k2 = s2 - mu * mu
    if which == 1usize {
        if nu < 3.0f64 { ret nan }
        if nu == 3.0f64 {
            if delta < 0.0f64 { ret 0.0f64 - inf }
            ret inf
        }
        ret mu * ((3.0f64 - delta * delta) * s3 - 3.0f64 * s2 + 2.0f64 * mu * mu) / (k2 * math.sqrt[f64](k2))
    }
    if nu < 4.0f64 { ret nan }
    if nu == 4.0f64 { ret inf }
    ret ((3.0f64 * s2 * s4 - 4.0f64 * mu * mu * (3.0f64 - delta * delta) * s3 + 6.0f64 * mu * mu * s2 - 3.0f64 * mu * mu * mu * mu) - 3.0f64 * k2 * k2) / (k2 * k2)
}

fn cp_fn0(c: *CpCtx, ln: f64) -> f64 { ret st_gamma(1.0f64, math.exp[f64](ln), 1usize) - c.g1 }
fn cp_fn1(c: *CpCtx, d: f64) -> f64 { ret st_gamma(d, c.nu, 1usize) - c.g1 }
fn cp_fn2(c: *CpCtx, ln: f64) -> f64 { ret st_gamma(c.delta, math.exp[f64](ln), 2usize) - c.g2 }

// cp2dp(c(mean, sd, gamma1, gamma2), "ST") proper: which 0 xi, 1 omega, 2 alpha, 3 nu; NaN where the package finds no solution
fn cp2dp_st(mean: f64, sd: f64, g1: f64, g2: f64, which: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let inf = 1.0f64 / 0.0f64
    let tiny = 1.4901161193847656e-8f64
    let ag = math.abs[f64](g1)
    var sg = 0.0f64
    if g1 > 0.0f64 { sg = 1.0f64 }
    if g1 < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    var c = CpCtx { g1: ag, g2: g2, delta: 0.0f64, nu: 0.0f64 }
    if ag <= 0.5f64 * (4.0f64 - pi()) * math.pow[f64](2.0f64 / (pi() - 2.0f64), 1.5f64) {
        let sn2 = 2.0f64 * (pi() - 3.0f64) * math.pow[f64](2.0f64 * ag / (4.0f64 - pi()), 4.0f64 / 3.0f64)
        let margin = g2 - sn2
        if math.abs[f64](margin) < tiny {
            if which == 3usize { ret inf }
            ret cp2dp_sn(mean, sd, g1, which)
        }
        if margin <= 0.0f64 { ret nan }
    } else {
        if ag >= 4.0f64 { ret nan }
        let r0 = root.brent(&c, cp_fn0, math.log[f64](4.0f64 + tiny), 1000.0f64, 1.0e-13f64, 500u32)
        if !r0.converged { ret nan }
        if g2 < st_gamma(1.0f64, math.exp[f64](r0.x), 2usize) { ret nan }
    }
    c.g1 = g1
    var delta = 0.75f64 * sg
    var nu = inf
    var step = inf
    var it = 0i32
    while step > 1.0e-12f64 && it < 2000i32 {
        c.delta = delta
        let f21 = cp_fn2(&c, math.log[f64](4.0f64 + tiny))
        let f22 = cp_fn2(&c, math.log[f64](1.0e9f64))
        if f21 != f21 || f22 != f22 || f21 * f22 > 0.0f64 { ret nan }
        let r2 = root.brent(&c, cp_fn2, math.log[f64](4.0f64 + tiny), 100.0f64, 1.0e-13f64, 500u32)
        if !r2.converged { ret nan }
        let nn = math.exp[f64](r2.x)
        c.nu = nn
        let r1 = root.brent(&c, cp_fn1, 0.0f64 - 1.0f64, 1.0f64, 1.0e-13f64, 500u32)
        if !r1.converged { ret nan }
        step = math.abs[f64](delta - r1.x) + math.abs[f64](math.log[f64](nu) - math.log[f64](nn))
        delta = r1.x
        nu = nn
        it += 1i32
    }
    if step > 1.0e-12f64 { ret nan }
    let mz = delta * b_nu(nu)
    let omega = sd / math.sqrt[f64](nu / (nu - 2.0f64) - mz * mz)
    if omega < 0.0f64 { ret nan }
    if which == 1usize { ret omega }
    if which == 0usize { ret mean - omega * mz }
    if which == 3usize { ret nu }
    ret delta / math.sqrt[f64](1.0f64 - delta * delta)
}
