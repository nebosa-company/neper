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

// ---- zeta and the cumulants of the extended skew-normal ----

fn zeta(k: usize, x: f64) -> f64 {
    let inf = 1.0f64 / 0.0f64
    if x < 0.0f64 - 1.0e300f64 {
        if k == 0usize { ret inf }
        if k == 1usize { ret inf }
        if k == 2usize { ret 0.0f64 - 1.0f64 }
        ret 0.0f64
    }
    if x > 1.0e300f64 {
        if k == 0usize { ret inf }
        if k == 1usize { ret 0.0f64 }
        ret 0.0f64
    }
    if k == 0usize { ret dist.pnorm(x, 0.0f64, 1.0f64, true, true) + math.log[f64](2.0f64) }
    if k == 1usize {
        if x > 0.0f64 - 50.0f64 { ret math.exp[f64](dist.dnorm(x, 0.0f64, 1.0f64, true) - dist.pnorm(x, 0.0f64, 1.0f64, true, true)) }
        let x2 = x * x
        ret 0.0f64 - x / (1.0f64 - 1.0f64 / (x2 + 2.0f64) + 1.0f64 / ((x2 + 2.0f64) * (x2 + 4.0f64)) - 5.0f64 / ((x2 + 2.0f64) * (x2 + 4.0f64) * (x2 + 6.0f64)) + 9.0f64 / ((x2 + 2.0f64) * (x2 + 4.0f64) * (x2 + 6.0f64) * (x2 + 8.0f64)) - 129.0f64 / ((x2 + 2.0f64) * (x2 + 4.0f64) * (x2 + 6.0f64) * (x2 + 8.0f64) * (x2 + 10.0f64)))
    }
    let z1 = zeta(1usize, x)
    if k == 2usize { ret 0.0f64 - z1 * (x + z1) }
    let z2 = zeta(2usize, x)
    if k == 3usize { ret 0.0f64 - z2 * (x + z1) - z1 * (1.0f64 + z2) }
    let z3 = zeta(3usize, x)
    ret 0.0f64 - z3 * (x + 2.0f64 * z1) - 2.0f64 * z2 * (1.0f64 + z2)
}

// sn.cumulants(xi, omega, alpha, tau): the k-th cumulant, k = 1 to 4, of the extended skew-normal
fn sn_cumulant(xi: f64, omega: f64, alpha: f64, tau: f64, k: usize) -> f64 {
    if tau == 0.0f64 { ret st_cumulant(xi, omega, alpha, 1.0f64 / 0.0f64, k) }
    let delta = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
    var kap = zeta(k, tau) * math.pow[f64](delta, f64(k))
    if k == 2usize { kap += 1.0f64 }
    kap = kap * math.pow[f64](omega, f64(k))
    if k == 1usize { kap += xi }
    ret kap
}

// ---- the multivariate families (small dimension, row-major matrices) ----

// the lower Cholesky factor l of the symmetrised a; false when it is not positive definite
fn chol_lower(l: []f64, a: []const f64, d: usize) -> bool {
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            l[i * d + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < d {
        var j = 0usize
        while j <= i {
            var s = (a[i * d + j] + a[j * d + i]) / 2.0f64
            var k = 0usize
            while k < j {
                s -= l[i * d + k] * l[j * d + k]
                k += 1usize
            }
            if i == j {
                if s <= 0.0f64 { ret false }
                l[i * d + i] = math.sqrt[f64](s)
            } else {
                l[i * d + j] = s / l[j * d + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// x' Omega^-1 x from the factor l by forward substitution
fn chol_quad(l: []const f64, x: []const f64, d: usize, w: []f64) -> f64 {
    var q = 0.0f64
    var i = 0usize
    while i < d {
        var s = x[i]
        var k = 0usize
        while k < i {
            s -= l[i * d + k] * w[k]
            k += 1usize
        }
        w[i] = s / l[i * d + i]
        q += w[i] * w[i]
        i += 1usize
    }
    ret q
}

// delta of delta.etc(alpha, Omega) into delta; returns alpha' Ocor alpha
fn mv_delta(alpha: []const f64, omg: []const f64, d: usize, delta: []f64) -> f64 {
    var aq = 0.0f64
    var i = 0usize
    while i < d {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            s += omg[i * d + j] / math.sqrt[f64](omg[i * d + i] * omg[j * d + j]) * alpha[j]
            j += 1usize
        }
        delta[i] = s
        aq += alpha[i] * s
        i += 1usize
    }
    i = 0usize
    while i < d {
        delta[i] = delta[i] / math.sqrt[f64](1.0f64 + aq)
        i += 1usize
    }
    ret aq
}

// dmsn at one point x (length d); lg for the log density
fn dmsn(a: *mem.Arena, x: []const f64, xi: []const f64, omg: []const f64, alpha: []const f64, tau: f64, lg: bool) -> f64 {
    let d = alpha.len
    let (l, e1) = mem.alloc[f64](a, d * d)
    let (w, e2) = mem.alloc[f64](a, d)
    let (xc, e3) = mem.alloc[f64](a, d)
    let (dl, e4) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    if !chol_lower(l, omg, d) { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    var logdet = 0.0f64
    var lin = 0.0f64
    while i < d {
        xc[i] = x[i] - xi[i]
        logdet += 2.0f64 * math.log[f64](l[i * d + i])
        lin += xc[i] / math.sqrt[f64](omg[i * d + i]) * alpha[i]
        i += 1usize
    }
    let q = chol_quad(l, xc, d, w)
    var logc = math.log[f64](2.0f64)
    var a0 = 0.0f64
    if tau != 0.0f64 {
        logc = 0.0f64 - dist.pnorm(tau, 0.0f64, 1.0f64, true, true)
        let aq = mv_delta(alpha, omg, d, dl)
        a0 = tau * math.sqrt[f64](1.0f64 + aq)
    }
    let lp = logc - 0.5f64 * q + dist.pnorm(a0 + lin, 0.0f64, 1.0f64, true, true) - 0.5f64 * (f64(d) * math.log[f64](2.0f64 * pi()) + logdet)
    if lg { ret lp }
    ret math.exp[f64](lp)
}

// dmst at one point
fn dmst(a: *mem.Arena, x: []const f64, xi: []const f64, omg: []const f64, alpha: []const f64, nu: f64, lg: bool) -> f64 {
    if nu > 1.0e300f64 { ret dmsn(a, x, xi, omg, alpha, 0.0f64, lg) }
    let d = alpha.len
    let (l, e1) = mem.alloc[f64](a, d * d)
    let (w, e2) = mem.alloc[f64](a, d)
    let (xc, e3) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    if !chol_lower(l, omg, d) { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    var logdet = 0.0f64
    var lin = 0.0f64
    while i < d {
        xc[i] = x[i] - xi[i]
        logdet += 2.0f64 * math.log[f64](l[i * d + i])
        lin += xc[i] / math.sqrt[f64](omg[i * d + i]) * alpha[i]
        i += 1usize
    }
    let q = chol_quad(l, xc, d, w)
    let fd = f64(d)
    var logc = 0.0f64
    var log1q = 0.0f64
    if nu < 10000.0f64 {
        logc = nm.lgammafn((nu + fd) / 2.0f64) - nm.lgammafn(nu / 2.0f64) - 0.5f64 * fd * math.log[f64](nu)
        log1q = math.log[f64](1.0f64 + q / nu)
    } else {
        logc = 0.0f64 - 0.5f64 * fd * math.log[f64](2.0f64) + dist.log1p((fd / 2.0f64) * (fd / 2.0f64 - 1.0f64) / nu)
        log1q = dist.log1p(q / nu)
    }
    let ldm = logc - 0.5f64 * (fd * math.log[f64](pi()) + logdet + (nu + fd) * log1q)
    let lpt = nb.pt(lin * math.sqrt[f64]((nu + fd) / (q + nu)), nu + fd, true, true)
    let lp = math.log[f64](2.0f64) + ldm + lpt
    if lg { ret lp }
    ret math.exp[f64](lp)
}

// rmsn(n, xi, Omega, alpha, tau) after set.seed(seed): out is n x d row-major
fn rmsn(a: *mem.Arena, n: usize, xi: []const f64, omg: []const f64, alpha: []const f64, tau: f64, seed: i64, out: []f64) -> err {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    ret rmsn_draw(a, &rg, n, xi, omg, alpha, tau, out)
}

fn rmsn_draw(a: *mem.Arena, rg: *rng.Rng, n: usize, xi: []const f64, omg: []const f64, alpha: []const f64, tau: f64, out: []f64) -> err {
    let d = alpha.len
    if d == 1usize {
        let dl1 = alpha[0usize] / math.sqrt[f64](1.0f64 + alpha[0usize] * alpha[0usize])
        let om1 = math.sqrt[f64](omg[0usize])
        ret rsn_draw(a, rg, n, xi[0usize], om1, dl1, tau, out)
    }
    let (dl, e1) = mem.alloc[f64](a, d)
    let (psi, e2) = mem.alloc[f64](a, d * d)
    let (l, e3) = mem.alloc[f64](a, d * d)
    let (zz, e4) = mem.alloc[f64](a, n * d)
    let (tn, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e1 }
    let aq = mv_delta(alpha, omg, d, dl)
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            let oc = omg[i * d + j] / math.sqrt[f64](omg[i * d + i] * omg[j * d + j])
            psi[i * d + j] = (oc - dl[i] * dl[j]) / math.sqrt[f64]((1.0f64 - dl[i] * dl[i]) * (1.0f64 - dl[j] * dl[j]))
            j += 1usize
        }
        i += 1usize
    }
    if !chol_lower(l, psi, d) { ret e1 }
    var k = 0usize
    while k < d {
        i = 0usize
        while i < n {
            zz[i * d + k] = rng.norm(rg)
            i += 1usize
        }
        k += 1usize
    }
    i = 0usize
    if tau == 0.0f64 {
        while i < n {
            tn[i] = math.abs[f64](rng.norm(rg))
            i += 1usize
        }
    } else {
        let lo = pn(0.0f64 - tau)
        while i < n {
            tn[i] = dist.qnorm(lo + (1.0f64 - lo) * rng.unif(rg), 0.0f64, 1.0f64, true, false)
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            var y = 0.0f64
            k = 0usize
            while k <= j {
                y += zz[i * d + k] * l[j * d + k]
                k += 1usize
            }
            let z = dl[j] * tn[i] + math.sqrt[f64](1.0f64 - dl[j] * dl[j]) * y
            out[i * d + j] = xi[j] + math.sqrt[f64](omg[j * d + j]) * z
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// rmst(n, xi, Omega, alpha, nu): d = 1 is rst; otherwise rmsn at xi = 0 divided by sqrt of chi-square over nu, then shifted
fn rmst(a: *mem.Arena, n: usize, xi: []const f64, omg: []const f64, alpha: []const f64, nu: f64, seed: i64, out: []f64) -> err {
    let d = alpha.len
    if d == 1usize { ret rst(a, n, xi[0usize], math.sqrt[f64](omg[0usize]), alpha[0usize], nu, seed, out) }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let (z0, e1) = mem.alloc[f64](a, d)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < d {
        z0[i] = 0.0f64
        i += 1usize
    }
    let e = rmsn_draw(a, &rg, n, z0, omg, alpha, 0.0f64, out)
    if e != ok { ret e }
    i = 0usize
    while i < n {
        var v = 1.0f64
        if nu < 1.0e300f64 { v = rd.rchisq(&rg, nu) / nu }
        var j = 0usize
        while j < d {
            out[i * d + j] = xi[j] + out[i * d + j] / math.sqrt[f64](v)
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// ---- selm for a single response: maximum (penalised) likelihood by damped Newton steps ----

// the penalty Q of Qpenalty(alpha) (nu = Inf) and Qpenalty(alpha, nu)
fn qpenalty(alpha: f64, nu: f64) -> f64 { ret qpen_a2(alpha * alpha, nu) }

// the same from alpha' Omega.bar alpha
fn qpen_a2(a2: f64, nu: f64) -> f64 {
    var e1 = 1.0f64 / 3.0f64
    var e2 = 0.2854166f64
    if nu < 1.0e300f64 {
        e1 = e1 * (nu + 2.0f64) * (nu + 3.0f64) / ((nu + 1.0f64) * (nu + 1.0f64))
        e2 = e2 * (1.0f64 + 4.0f64 / (nu + 0.57721f64))
    }
    let c1 = 1.0f64 / (4.0f64 * e2)
    let c2 = e2 / e1
    ret c1 * math.log[f64](1.0f64 + c2 * a2)
}

type FitCtx = struct { y: []const f64, x: []const f64, w: []const f64, n: usize, p: usize, st: bool, pen: bool }

// minus the (penalised) log-likelihood at th = (beta (p), log omega, alpha [, log nu])
fn fit_obj(c: *FitCtx, th: []const f64) -> f64 {
    let p = c.p
    let omega = math.exp[f64](th[p])
    let alpha = th[p + 1usize]
    var nu = 1.0f64 / 0.0f64
    if c.st { nu = math.exp[f64](th[p + 2usize]) }
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        var mu = 0.0f64
        var j = 0usize
        while j < p {
            mu += c.x[i * p + j] * th[j]
            j += 1usize
        }
        let z = (c.y[i] - mu) / omega
        var l1 = 0.0f64
        if c.st {
            l1 = math.log[f64](2.0f64) + nb.dt(z, nu, true) - th[p] + nb.pt(alpha * z * math.sqrt[f64]((nu + 1.0f64) / (z * z + nu)), nu + 1.0f64, true, true)
        } else {
            l1 = math.log[f64](2.0f64) - 0.5f64 * math.log[f64](2.0f64 * pi()) - th[p] - 0.5f64 * z * z + dist.pnorm(alpha * z, 0.0f64, 1.0f64, true, true)
        }
        ll += c.w[i] * l1
        i += 1usize
    }
    if c.pen { ll -= qpenalty(alpha, nu) }
    ret 0.0f64 - ll
}

// the five-point central gradient of fit_obj
fn fit_grad[Ctx: type](c: *Ctx, f: fn(*Ctx, []const f64) -> f64, th: []f64, g: []f64) {
    let m = th.len
    var k = 0usize
    while k < m {
        let h = 1.0e-3f64 * (1.0f64 + math.abs[f64](th[k]))
        let t0 = th[k]
        th[k] = t0 + h
        let f1 = f(c, th)
        th[k] = t0 - h
        let f2 = f(c, th)
        th[k] = t0 + 2.0f64 * h
        let f3 = f(c, th)
        th[k] = t0 - 2.0f64 * h
        let f4 = f(c, th)
        th[k] = t0
        g[k] = (8.0f64 * (f1 - f2) - (f3 - f4)) / (12.0f64 * h)
        k += 1usize
    }
}

// Gaussian elimination with partial pivoting on the m x m system a x = b (both destroyed); false when singular
fn gauss_solve(a: []f64, b: []f64, m: usize) -> bool {
    var c = 0usize
    while c < m {
        var piv = c
        var r = c + 1usize
        while r < m {
            if math.abs[f64](a[r * m + c]) > math.abs[f64](a[piv * m + c]) { piv = r }
            r += 1usize
        }
        if math.abs[f64](a[piv * m + c]) < 1.0e-300f64 { ret false }
        if piv != c {
            var k = 0usize
            while k < m {
                let t = a[c * m + k]
                a[c * m + k] = a[piv * m + k]
                a[piv * m + k] = t
                k += 1usize
            }
            let tb = b[c]
            b[c] = b[piv]
            b[piv] = tb
        }
        r = c + 1usize
        while r < m {
            let f = a[r * m + c] / a[c * m + c]
            var k = c
            while k < m {
                a[r * m + k] -= f * a[c * m + k]
                k += 1usize
            }
            b[r] -= f * b[c]
            r += 1usize
        }
        c += 1usize
    }
    var i = m
    while i > 0usize {
        i -= 1usize
        var s = b[i]
        var k = i + 1usize
        while k < m {
            s -= a[i * m + k] * b[k]
            k += 1usize
        }
        b[i] = s / a[i * m + i]
    }
    ret true
}

// damped Newton minimisation of fit_obj from th (overwritten); the Hessian is a finite difference of fit_grad
fn fit_newton[Ctx: type](a: *mem.Arena, c: *Ctx, f: fn(*Ctx, []const f64) -> f64, th: []f64) -> err {
    let m = th.len
    let (g, e1) = mem.alloc[f64](a, m)
    let (g2, e2) = mem.alloc[f64](a, m)
    let (hm, e3) = mem.alloc[f64](a, m * m)
    let (hs, e4) = mem.alloc[f64](a, m * m)
    let (st, e5) = mem.alloc[f64](a, m)
    let (tr, e6) = mem.alloc[f64](a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var it = 0i32
    var f0 = f(c, th)
    while it < 200i32 {
        fit_grad(c, f, th, g)
        var k = 0usize
        while k < m {
            let h = 1.0e-4f64 * (1.0f64 + math.abs[f64](th[k]))
            let t0 = th[k]
            th[k] = t0 + h
            fit_grad(c, f, th, g2)
            var j = 0usize
            while j < m {
                hm[j * m + k] = g2[j]
                j += 1usize
            }
            th[k] = t0 - h
            fit_grad(c, f, th, st)
            th[k] = t0
            j = 0usize
            while j < m {
                hm[j * m + k] = (hm[j * m + k] - st[j]) / (2.0f64 * h)
                j += 1usize
            }
            k += 1usize
        }
        var ridge = 0.0f64
        var moved = false
        var tries = 0i32
        while !moved && tries < 40i32 {
            k = 0usize
            while k < m * m {
                hs[k] = (hm[k] + hm[(k % m) * m + k / m]) / 2.0f64
                k += 1usize
            }
            k = 0usize
            while k < m {
                hs[k * m + k] += ridge
                st[k] = 0.0f64 - g[k]
                k += 1usize
            }
            var good = gauss_solve(hs, st, m)
            var dec = 0.0f64
            k = 0usize
            while k < m {
                dec += st[k] * g[k]
                k += 1usize
            }
            if good && dec < 0.0f64 {
                var lam = 1.0f64
                var ls = 0i32
                while ls < 30i32 && !moved {
                    k = 0usize
                    while k < m {
                        tr[k] = th[k] + lam * st[k]
                        k += 1usize
                    }
                    let f1 = f(c, tr)
                    if f1 == f1 && f1 < f0 + 1.0e-4f64 * lam * dec {
                        k = 0usize
                        while k < m {
                            th[k] = tr[k]
                            k += 1usize
                        }
                        f0 = f1
                        moved = true
                    }
                    lam = lam / 2.0f64
                    ls += 1i32
                }
            }
            if !moved {
                if ridge == 0.0f64 { ridge = 1.0e-3f64 } else { ridge = ridge * 10.0f64 }
                tries += 1i32
            }
        }
        var gn = 0.0f64
        var k2 = 0usize
        while k2 < m {
            gn += g[k2] * g[k2]
            k2 += 1usize
        }
        if !moved || math.sqrt[f64](gn) < 1.0e-9f64 { ret ok }
        it += 1i32
    }
    ret ok
}

// selm(y ~ x, family SN or ST) by method MLE or MPLE (the Qpenalty penalty), one response; x is n x p row-major with a leading column of ones.
// out receives (beta (p), omega, alpha [, nu]); the return value is the (penalised) log-likelihood at the maximum
fn selm_fit(a: *mem.Arena, y: []const f64, x: []const f64, w: []const f64, p: usize, st: bool, pen: bool, out: []f64) -> f64 {
    let n = y.len
    var c = FitCtx { y: y, x: x, w: w, n: n, p: p, st: false, pen: pen }
    var m = p + 2usize
    let (th, e1) = mem.alloc[f64](a, p + 3usize)
    let (xtx, e2) = mem.alloc[f64](a, p * p)
    let (xty, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += w[i] * x[i * p + j] * x[i * p + k]
                i += 1usize
            }
            xtx[j * p + k] = s
            k += 1usize
        }
        var s2 = 0.0f64
        var i2 = 0usize
        while i2 < n {
            s2 += w[i2] * x[i2 * p + j] * y[i2]
            i2 += 1usize
        }
        xty[j] = s2
        j += 1usize
    }
    if !gauss_solve(xtx, xty, p) { ret 0.0f64 / 0.0f64 }
    var sw = 0.0f64
    var s2r = 0.0f64
    var s3r = 0.0f64
    var i3 = 0usize
    while i3 < n {
        var mu = 0.0f64
        j = 0usize
        while j < p {
            mu += x[i3 * p + j] * xty[j]
            j += 1usize
        }
        let r = y[i3] - mu
        sw += w[i3]
        s2r += w[i3] * r * r
        s3r += w[i3] * r * r * r
        i3 += 1usize
    }
    let sd = math.sqrt[f64](s2r / sw)
    var g1 = s3r / (sw * sd * sd * sd)
    let lim = 0.9952717464311565f64 - 0.00012207031f64
    if g1 > lim { g1 = 0.9f64 * lim }
    if g1 < 0.0f64 - lim { g1 = 0.0f64 - 0.9f64 * lim }
    let ex = cp2dp_sn(xty[0usize], sd, g1, 0usize)
    th[0usize] = ex
    j = 1usize
    while j < p {
        th[j] = xty[j]
        j += 1usize
    }
    th[p] = math.log[f64](cp2dp_sn(xty[0usize], sd, g1, 1usize))
    th[p + 1usize] = cp2dp_sn(xty[0usize], sd, g1, 2usize)
    var ths = th[0usize..m]
    let e = fit_newton(a, &c, fit_obj, ths)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if st {
        c.st = true
        m = p + 3usize
        th[p + 2usize] = math.log[f64](8.0f64)
        ths = th[0usize..m]
        let e5 = fit_newton(a, &c, fit_obj, ths)
        if e5 != ok { ret 0.0f64 / 0.0f64 }
    }
    j = 0usize
    while j < p {
        out[j] = th[j]
        j += 1usize
    }
    out[p] = math.exp[f64](th[p])
    out[p + 1usize] = th[p + 1usize]
    if st { out[p + 2usize] = math.exp[f64](th[p + 2usize]) }
    ret 0.0f64 - fit_obj(&c, ths)
}

// ---- selm for a matrix response (msn.mle, msn.mple, mst.mple) ----

type MvCtx = struct { y: []const f64, x: []const f64, w: []const f64, n: usize, d: usize, p: usize, st: bool, pen: bool, l: []f64, r: []f64, u: []f64 }

// minus the (penalised) log-likelihood at th = (beta (p x d, row j comp k at j d + k), log L_kk (d), L_kl for k > l row-major (d(d-1)/2), alpha (d) [, log nu])
fn mv_obj(c: *MvCtx, th: []const f64) -> f64 {
    let d = c.d
    let p = c.p
    var at = p * d
    var k = 0usize
    while k < d {
        var m = 0usize
        while m < d {
            c.l[k * d + m] = 0.0f64
            m += 1usize
        }
        c.l[k * d + k] = math.exp[f64](th[at + k])
        k += 1usize
    }
    at += d
    k = 1usize
    while k < d {
        var m = 0usize
        while m < k {
            c.l[k * d + m] = th[at]
            at += 1usize
            m += 1usize
        }
        k += 1usize
    }
    let ao = at
    at += d
    var nu = 1.0f64 / 0.0f64
    if c.st { nu = math.exp[f64](th[at]) }
    var logdet = 0.0f64
    var a2 = 0.0f64
    k = 0usize
    while k < d {
        logdet += 2.0f64 * th[p * d + k]
        k += 1usize
    }
    // omega_k and alpha' Omega.bar alpha
    var om = c.u
    k = 0usize
    while k < d {
        var s = 0.0f64
        var m = 0usize
        while m <= k {
            s += c.l[k * d + m] * c.l[k * d + m]
            m += 1usize
        }
        om[k] = math.sqrt[f64](s)
        k += 1usize
    }
    k = 0usize
    while k < d {
        var m = 0usize
        while m < d {
            var s = 0.0f64
            var q = 0usize
            while q <= k && q <= m {
                s += c.l[k * d + q] * c.l[m * d + q]
                q += 1usize
            }
            // msn.pdev hands Qpenalty the covariance matrix where mst.pdev hands it the correlation matrix; the package's own mismatch is kept
            if c.st { a2 += th[ao + k] * th[ao + m] * s / (om[k] * om[m]) } else { a2 += th[ao + k] * th[ao + m] * s }
            m += 1usize
        }
        k += 1usize
    }
    let fd = f64(d)
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        var lin = 0.0f64
        k = 0usize
        while k < d {
            var mu = 0.0f64
            var j = 0usize
            while j < p {
                mu += c.x[i * p + j] * th[j * d + k]
                j += 1usize
            }
            c.r[k] = c.y[i * d + k] - mu
            lin += c.r[k] / om[k] * th[ao + k]
            k += 1usize
        }
        var q = 0.0f64
        k = 0usize
        while k < d {
            var s = c.r[k]
            var m = 0usize
            while m < k {
                s -= c.l[k * d + m] * c.r[d + m]
                m += 1usize
            }
            c.r[d + k] = s / c.l[k * d + k]
            q += c.r[d + k] * c.r[d + k]
            k += 1usize
        }
        var l1 = 0.0f64
        if c.st {
            let lc = nm.lgammafn((nu + fd) / 2.0f64) - nm.lgammafn(nu / 2.0f64) - 0.5f64 * fd * math.log[f64](nu)
            let ldm = lc - 0.5f64 * (fd * math.log[f64](pi()) + logdet + (nu + fd) * math.log[f64](1.0f64 + q / nu))
            l1 = math.log[f64](2.0f64) + ldm + nb.pt(lin * math.sqrt[f64]((nu + fd) / (q + nu)), nu + fd, true, true)
        } else {
            l1 = math.log[f64](2.0f64) - 0.5f64 * q + dist.pnorm(lin, 0.0f64, 1.0f64, true, true) - 0.5f64 * (fd * math.log[f64](2.0f64 * pi()) + logdet)
        }
        ll += c.w[i] * l1
        i += 1usize
    }
    if c.pen { ll -= qpen_a2(a2, nu) }
    ret 0.0f64 - ll
}

// selm for a d-variate response y (n x d row-major) on x (n x p, leading ones): out gets beta (p x d, row j comp k at j d + k), Omega (d x d), alpha (d) [, nu]; the return value is the (penalised) log-likelihood
fn selm_mv(a: *mem.Arena, y: []const f64, x: []const f64, w: []const f64, d: usize, p: usize, st: bool, pen: bool, out: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let n = y.len / d
    let m = p * d + d * (d + 1usize) / 2usize + d + 1usize
    let (th, e1) = mem.alloc[f64](a, m)
    let (l, e2) = mem.alloc[f64](a, d * d)
    let (r, e3) = mem.alloc[f64](a, 2usize * d)
    let (u, e4) = mem.alloc[f64](a, d)
    let (xtx, e5) = mem.alloc[f64](a, p * p)
    let (xty, e6) = mem.alloc[f64](a, p * d)
    let (sg, e7) = mem.alloc[f64](a, d * d)
    let (mn, e8) = mem.alloc[f64](a, d)
    let (g1, e9) = mem.alloc[f64](a, d)
    let (dpo, e10) = mem.alloc[f64](a, d + d * d + d)
    let (cb, e11) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret nan }
    // least squares, one column at a time
    var k = 0usize
    while k < d {
        var j = 0usize
        while j < p {
            var q = 0usize
            while q < p {
                var s = 0.0f64
                var i = 0usize
                while i < n {
                    s += w[i] * x[i * p + j] * x[i * p + q]
                    i += 1usize
                }
                xtx[j * p + q] = s
                q += 1usize
            }
            var s2 = 0.0f64
            var i2 = 0usize
            while i2 < n {
                s2 += w[i2] * x[i2 * p + j] * y[i2 * d + k]
                i2 += 1usize
            }
            cb[j] = s2
            j += 1usize
        }
        if !gauss_solve(xtx, cb, p) { ret nan }
        j = 0usize
        while j < p {
            xty[j * d + k] = cb[j]
            j += 1usize
        }
        // the Gram matrix was destroyed: rebuild it for the next column
        k += 1usize
        if k < d {
            j = 0usize
            while j < p {
                var q = 0usize
                while q < p {
                    var s = 0.0f64
                    var i = 0usize
                    while i < n {
                        s += w[i] * x[i * p + j] * x[i * p + q]
                        i += 1usize
                    }
                    xtx[j * p + q] = s
                    q += 1usize
                }
                j += 1usize
            }
        }
    }
    // residual moments
    var sw = 0.0f64
    k = 0usize
    while k < d {
        g1[k] = 0.0f64
        var q = 0usize
        while q < d {
            sg[k * d + q] = 0.0f64
            q += 1usize
        }
        k += 1usize
    }
    var i = 0usize
    while i < n {
        sw += w[i]
        k = 0usize
        while k < d {
            var mu = 0.0f64
            var j = 0usize
            while j < p {
                mu += x[i * p + j] * xty[j * d + k]
                j += 1usize
            }
            r[k] = y[i * d + k] - mu
            k += 1usize
        }
        k = 0usize
        while k < d {
            var q = 0usize
            while q < d {
                sg[k * d + q] += w[i] * r[k] * r[q]
                q += 1usize
            }
            g1[k] += w[i] * r[k] * r[k] * r[k]
            k += 1usize
        }
        i += 1usize
    }
    k = 0usize
    while k < d {
        var q = 0usize
        while q < d {
            sg[k * d + q] = sg[k * d + q] / sw
            q += 1usize
        }
        g1[k] = g1[k] / (sw * sg[k * d + k] * math.sqrt[f64](sg[k * d + k]))
        mn[k] = xty[k]
        k += 1usize
    }
    // moment start (msn.moment.fit): shrink the skewness until the centred parameters are admissible
    let lim = 0.995f64
    var shrink = 1.0f64
    var found = false
    var tries = 0i32
    while !found && tries < 30i32 {
        k = 0usize
        while k < d {
            var gg = g1[k] * shrink
            if gg > lim { gg = lim }
            if gg < 0.0f64 - lim { gg = 0.0f64 - lim }
            r[k] = gg
            k += 1usize
        }
        if mv_cp2dp_sn(a, mn, sg, r[0usize..d], dpo) { found = true } else { shrink = shrink * 0.7f64 }
        tries += 1i32
    }
    if !found { ret nan }
    // th: beta = LS with the intercept row shifted to the skew-normal xi
    var j = 0usize
    while j < p {
        k = 0usize
        while k < d {
            th[j * d + k] = xty[j * d + k]
            k += 1usize
        }
        j += 1usize
    }
    k = 0usize
    while k < d {
        th[k] = dpo[k]
        k += 1usize
    }
    // Cholesky of Omega from the start
    var om2 = dpo[d..d + d * d]
    if !chol_lower(l, om2, d) { ret nan }
    var at = p * d
    k = 0usize
    while k < d {
        th[at + k] = math.log[f64](l[k * d + k])
        k += 1usize
    }
    at += d
    k = 1usize
    while k < d {
        var q = 0usize
        while q < k {
            th[at] = l[k * d + q]
            at += 1usize
            q += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < d {
        th[at + k] = dpo[d + d * d + k]
        k += 1usize
    }
    at += d
    var c = MvCtx { y: y, x: x, w: w, n: n, d: d, p: p, st: false, pen: pen, l: l, r: r, u: u }
    var nm0 = p * d + d * (d + 1usize) / 2usize + d
    var ths = th[0usize..nm0]
    let e = fit_newton(a, &c, mv_obj, ths)
    if e != ok { ret nan }
    var ms = 0i32
    while pen && ms < 3i32 {
        // a penalised surface can trap the moment start: also start from the unpenalised-style fit with alpha shrunk, and keep the better end
        let (th2, e12) = mem.alloc[f64](a, nm0)
        if e12 != ok { ret nan }
        var q = 0usize
        while q < nm0 {
            th2[q] = th[q]
            q += 1usize
        }
        var k2 = 0usize
        while k2 < d {
            th2[at - d + k2] = th[at - d + k2] * 0.3f64 * f64(ms)
            k2 += 1usize
        }
        c.pen = false
        let e13 = fit_newton(a, &c, mv_obj, th2)
        c.pen = true
        if e13 != ok { ret nan }
        let e14 = fit_newton(a, &c, mv_obj, th2)
        if e14 != ok { ret nan }
        if mv_obj(&c, th2) < mv_obj(&c, ths) {
            q = 0usize
            while q < nm0 {
                th[q] = th2[q]
                q += 1usize
            }
        }
        ms += 1i32
    }
    if st {
        c.st = true
        th[at] = math.log[f64](8.0f64)
        ths = th[0usize..nm0 + 1usize]
        let e5b = fit_newton(a, &c, mv_obj, ths)
        if e5b != ok { ret nan }
    }
    let obj = mv_obj(&c, ths)
    j = 0usize
    while j < p * d {
        out[j] = th[j]
        j += 1usize
    }
    // Omega = L L'
    k = 0usize
    while k < d {
        var q = 0usize
        while q < d {
            var s = 0.0f64
            var t = 0usize
            while t <= k && t <= q {
                s += c.l[k * d + t] * c.l[q * d + t]
                t += 1usize
            }
            out[p * d + k * d + q] = s
            q += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < d {
        out[p * d + d * d + k] = th[at - d + k]
        k += 1usize
    }
    if st { out[p * d + d * d + d] = math.exp[f64](th[at]) }
    ret 0.0f64 - obj
}

// ---- multivariate centred parameters ----

// dp2cp for the multivariate skew-normal (extension tau) and skew-t (nu < Inf, proper): out is mean (d), var.cov (d x d row-major), gamma1 (d)
fn mv_dp2cp(a: *mem.Arena, st: bool, xi: []const f64, omg: []const f64, alpha: []const f64, ex: f64, out: []f64) -> err {
    let d = alpha.len
    let (dl, e1) = mem.alloc[f64](a, d)
    if e1 != ok { ret e1 }
    let aq = mv_delta(alpha, omg, d, dl)
    var z2 = 0.0f64
    var bz = 0.0f64
    if st {
        bz = b_nu(ex)
    } else {
        z2 = zeta(2usize, ex)
        bz = zeta(1usize, ex)
    }
    var i = 0usize
    while i < d {
        let oi = math.sqrt[f64](omg[i * d + i])
        var mui = bz * dl[i] * oi
        out[i] = xi[i] + mui
        var j = 0usize
        while j < d {
            let oj = math.sqrt[f64](omg[j * d + j])
            var cv = 0.0f64
            if st { cv = omg[i * d + j] * ex / (ex - 2.0f64) - bz * dl[i] * oi * bz * dl[j] * oj } else { cv = omg[i * d + j] + z2 * oi * dl[i] * oj * dl[j] }
            out[d + i * d + j] = cv
            j += 1usize
        }
        if st {
            out[d + d * d + i] = st_gamma(dl[i], ex, 1usize)
        } else {
            let sdz = math.sqrt[f64](1.0f64 + z2 * dl[i] * dl[i])
            let r = dl[i] / sdz
            out[d + d * d + i] = zeta(3usize, ex) * r * r * r
        }
        i += 1usize
    }
    ret ok
}

// cp2dp for the multivariate skew-normal: out is xi (d), Omega (d x d), alpha (d); false when the centred parameters are not admissible
fn mv_cp2dp_sn(a: *mem.Arena, mean: []const f64, sig: []const f64, g1: []const f64, out: []f64) -> bool {
    let d = g1.len
    let mx = 0.5f64 * (4.0f64 - pi()) * math.pow[f64](2.0f64 / (pi() - 2.0f64), 1.5f64)
    let bb = math.sqrt[f64](2.0f64 / pi())
    let (dl, e1) = mem.alloc[f64](a, d)
    let (om, e2) = mem.alloc[f64](a, d)
    let (mz, e3) = mem.alloc[f64](a, d)
    let (ob, e4) = mem.alloc[f64](a, d * d)
    let (l, e5) = mem.alloc[f64](a, d * d)
    let (w, e6) = mem.alloc[f64](a, d)
    let (x, e7) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret false }
    var i = 0usize
    while i < d {
        if math.abs[f64](g1[i]) >= mx { ret false }
        var cr = math.pow[f64](2.0f64 * math.abs[f64](g1[i]) / (4.0f64 - pi()), 1.0f64 / 3.0f64)
        if g1[i] < 0.0f64 { cr = 0.0f64 - cr }
        dl[i] = cr / (bb * math.sqrt[f64](1.0f64 + cr * cr))
        mz[i] = bb * dl[i]
        om[i] = math.sqrt[f64](sig[i * d + i] / (1.0f64 - mz[i] * mz[i]))
        i += 1usize
    }
    i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            out[d + i * d + j] = sig[i * d + j] + mz[i] * om[i] * mz[j] * om[j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            ob[i * d + j] = out[d + i * d + j] / math.sqrt[f64](out[d + i * d + i] * out[d + j * d + j])
            j += 1usize
        }
        i += 1usize
    }
    if !chol_lower(l, ob, d) { ret false }
    // solve Obar x = delta through the factor: l l' x = delta
    i = 0usize
    while i < d {
        var s = dl[i]
        var k = 0usize
        while k < i {
            s -= l[i * d + k] * w[k]
            k += 1usize
        }
        w[i] = s / l[i * d + i]
        i += 1usize
    }
    i = d
    while i > 0usize {
        i -= 1usize
        var s = w[i]
        var k = i + 1usize
        while k < d {
            s -= l[k * d + i] * x[k]
            k += 1usize
        }
        x[i] = s / l[i * d + i]
    }
    var dsq = 0.0f64
    i = 0usize
    while i < d {
        dsq += dl[i] * x[i]
        i += 1usize
    }
    if dsq >= 1.0f64 { ret false }
    i = 0usize
    while i < d {
        out[i] = mean[i] - om[i] * mz[i]
        out[d + d * d + i] = x[i] / math.sqrt[f64](1.0f64 - dsq)
        i += 1usize
    }
    ret true
}

// dsc: the skew-Cauchy density
fn dsc(x: f64, xi: f64, omega: f64, alpha: f64) -> f64 {
    let z = (x - xi) / omega
    ret 1.0f64 / (pi() * omega * (1.0f64 + z * z)) * (1.0f64 + alpha * z / math.sqrt[f64](1.0f64 + z * z * (1.0f64 + alpha * alpha)))
}

// rsc(n, xi, omega, alpha) after set.seed: the skew-normal sample at xi = 0 divided by |N(0,1)|, then shifted
fn rsc(a: *mem.Arena, n: usize, xi: f64, omega: f64, alpha: f64, seed: i64, out: []f64) -> err {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let delta = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
    let e = rsn_draw(a, &rg, n, 0.0f64, omega, delta, 0.0f64, out)
    if e != ok { ret e }
    var j = 0usize
    while j < n {
        out[j] = xi + out[j] / math.abs[f64](rng.norm(&rg))
        j += 1usize
    }
    ret ok
}

// dmsc and rmsc are dmst and rmst at nu = 1
fn dmsc(a: *mem.Arena, x: []const f64, xi: []const f64, omg: []const f64, alpha: []const f64, lg: bool) -> f64 { ret dmst(a, x, xi, omg, alpha, 1.0f64, lg) }

fn rmsc(a: *mem.Arena, n: usize, xi: []const f64, omg: []const f64, alpha: []const f64, seed: i64, out: []f64) -> err { ret rmst(a, n, xi, omg, alpha, 1.0f64, seed, out) }

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
