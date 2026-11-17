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
        let dl = alpha / math.sqrt[f64](1.0f64 + alpha * alpha)
        var lo = 0.0f64
        var hi = z
        var sg = 1.0f64
        if z < 0.0f64 {
            lo = z
            hi = 0.0f64
            sg = 0.0f64 - 1.0f64
        }
        p = math.acos[f64](dl) / pi() + sg * gk_int(&c, dst_std, lo, hi)
    } else {
        let (r, e) = quad.qagi(a, &c, fp_chisq, 0.0f64, 1i64, 1.220703125e-4f64, 1.220703125e-4f64, 100usize)
        if e != ok { ret 0.0f64 / 0.0f64 }
        p = r.result
    }
    if p < 0.0f64 { p = 0.0f64 }
    if p > 1.0f64 { p = 1.0f64 }
    ret p
}
