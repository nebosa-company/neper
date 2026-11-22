// R copula: bivariate Archimedean copulas Clayton, Frank, Gumbel, AMH and Joe, and the normal and t copulas: density, distribution
// function, Kendall's tau, Spearman's rho (Frank, normal), tail dependence, pobs, the empirical copula, rCopula for all six, fitCopula by
// itau (all families), irho (normal, Clayton, Gumbel, Frank), ml and mpl (all six, the t copula with its df), gofCopula(Sn, pb), and
// the mvdc density, distribution, sampler and fit. Dimension d > 2: exchangeable normal and t density and samplers, Clayton density,
// Clayton/Frank/Gumbel/Joe distribution function and samplers (Frank theta > 0).
//
// Not here: extreme-value copulas, the Gumbel, Joe and Frank density in d > 2, the normal and t distribution in d > 2 (randomised
// Genz), exchangeable and AR1 dispersion structures, gofCopula's SnB, SnC and multiplier variants, Spearman's rho of Clayton, Gumbel,
// Joe and AMH, irho for AMH and the t copula, and fitMvdc margins beyond norm, exp, gamma and lnorm.

use e.algo.rand.r as rng
use e.algo.stat as st
use e.algo.stat.gsldebye as gd
use e.algo.stat.lbfgsb as lb
use e.algo.stat.rbfgs as rb
use e.algo.stat.copulatab as tb
use e.algo.stat.mvt as mt
use e.algo.stat.mvtnorm as mvn
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem
use e.os
use e.str

// family 0 Clayton, 1 Frank, 2 Gumbel, 3 AMH, 4 Joe
fn pcop(fam: usize, th: f64, u: f64, v: f64) -> f64 {
    if fam == 0usize { ret math.pow[f64](math.pow[f64](u, 0.0f64 - th) + math.pow[f64](v, 0.0f64 - th) - 1.0f64, 0.0f64 - 1.0f64 / th) }
    if fam == 1usize {
        let a = math.exp[f64](0.0f64 - th * u) - 1.0f64
        let b = math.exp[f64](0.0f64 - th * v) - 1.0f64
        let c = math.exp[f64](0.0f64 - th) - 1.0f64
        ret 0.0f64 - math.log[f64](1.0f64 + a * b / c) / th
    }
    if fam == 2usize {
        let s = math.pow[f64](0.0f64 - math.log[f64](u), th) + math.pow[f64](0.0f64 - math.log[f64](v), th)
        ret math.exp[f64](0.0f64 - math.pow[f64](s, 1.0f64 / th))
    }
    if fam == 3usize { ret u * v / (1.0f64 - th * (1.0f64 - u) * (1.0f64 - v)) }
    let a = math.pow[f64](1.0f64 - u, th)
    let b = math.pow[f64](1.0f64 - v, th)
    ret 1.0f64 - math.pow[f64](a + b - a * b, 1.0f64 / th)
}

fn dcop(fam: usize, th: f64, u: f64, v: f64) -> f64 {
    if fam == 0usize {
        let s = math.pow[f64](u, 0.0f64 - th) + math.pow[f64](v, 0.0f64 - th) - 1.0f64
        ret (1.0f64 + th) * math.pow[f64](u * v, 0.0f64 - 1.0f64 - th) * math.pow[f64](s, 0.0f64 - 2.0f64 - 1.0f64 / th)
    }
    if fam == 1usize {
        let eu = math.exp[f64](0.0f64 - th * u)
        let ev = math.exp[f64](0.0f64 - th * v)
        let e1 = math.exp[f64](0.0f64 - th)
        let den = (1.0f64 - e1) - (1.0f64 - eu) * (1.0f64 - ev)
        ret th * (1.0f64 - e1) * eu * ev / (den * den)
    }
    if fam == 2usize {
        let lu = 0.0f64 - math.log[f64](u)
        let lv = 0.0f64 - math.log[f64](v)
        let aa = math.pow[f64](lu, th) + math.pow[f64](lv, th)
        let c = pcop(2usize, th, u, v)
        ret c / (u * v) * math.pow[f64](lu * lv, th - 1.0f64) * math.pow[f64](aa, 2.0f64 / th - 2.0f64) * (1.0f64 + (th - 1.0f64) / math.pow[f64](aa, 1.0f64 / th))
    }
    if fam == 3usize {
        let d = 1.0f64 - th * (1.0f64 - u) * (1.0f64 - v)
        ret (1.0f64 + th * ((1.0f64 + u) * (1.0f64 + v) - 3.0f64) + th * th * (1.0f64 - u) * (1.0f64 - v)) / (d * d * d)
    }
    let a = math.pow[f64](1.0f64 - u, th)
    let b = math.pow[f64](1.0f64 - v, th)
    let s = a + b - a * b
    ret math.pow[f64](1.0f64 - u, th - 1.0f64) * math.pow[f64](1.0f64 - v, th - 1.0f64) * math.pow[f64](s, 1.0f64 / th - 2.0f64) * (th - 1.0f64 + s)
}

fn ktau(fam: usize, th: f64) -> f64 {
    if fam == 0usize { ret th / (th + 2.0f64) }
    if fam == 1usize { ret tau_frank(th) }
    if fam == 2usize { ret 1.0f64 - 1.0f64 / th }
    if fam == 3usize { ret 1.0f64 - 2.0f64 * (th + (1.0f64 - th) * (1.0f64 - th) * math.log[f64](1.0f64 - th)) / (3.0f64 * th * th) }
    ret tau_joe(th)
}

// ---- elliptical copulas, tail dependence, rank transforms, samplers and moment-based fits ----

fn qn(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

fn debye_s(n: usize, x: f64) -> f64 {
    let (d, e) = gd.debye(n, math.abs[f64](x))
    var r = d
    if x < 0.0f64 { r = d - f64(n) / f64(n + 1usize) * x }
    ret r
}

// Frank: copula's .tauFrankCopula and .rhoFrankCopula
fn tau_frank(a: f64) -> f64 {
    if math.abs[f64](a) < 10.0f64 * math.sqrt[f64](2.220446049250313e-16f64) { ret a / 9.0f64 }
    ret 1.0f64 - 4.0f64 / a * (1.0f64 - debye_s(1usize, a))
}

fn rho_frank(a: f64) -> f64 {
    if math.abs[f64](a) < math.sqrt[f64](75.0f64 * 2.220446049250313e-16f64) { ret a / 6.0f64 }
    ret 1.0f64 + 12.0f64 / a * (debye_s(2usize, a) - debye_s(1usize, a))
}

fn digamma(x: f64) -> f64 { ret st.digamma(x) }

// Joe: tauJoe(method = "hybrid")
fn tau_joe(th: f64) -> f64 {
    if th == 2.0f64 { ret 2.0f64 - 1.6449340668482264f64 }
    let q = 2.0f64 / th
    let e = q - 1.0f64
    var dt = 0.0f64
    if math.abs[f64](e) < 1.5e-05f64 {
        dt = 0.0f64 - (digamma(1.0f64) + q * 1.6449340668482264f64 + e / 2.0f64 * (0.0f64 - 2.404113806319188570799f64))
    } else {
        dt = (digamma(1.0f64) - q * digamma(q)) / e
    }
    ret 1.0f64 + q * (dt + digamma(1.0f64 + q))
}

// log density of the bivariate normal copula
fn ldnorm_cop(rho: f64, u: f64, v: f64) -> f64 {
    let x = qn(u)
    let y = qn(v)
    let d = 1.0f64 - rho * rho
    ret 0.0f64 - 0.5f64 * math.log[f64](d) - (rho * rho * (x * x + y * y) - 2.0f64 * rho * x * y) / (2.0f64 * d)
}

fn dnorm_cop(rho: f64, u: f64, v: f64) -> f64 { ret math.exp[f64](ldnorm_cop(rho, u, v)) }

fn pnorm_cop(rho: f64, u: f64, v: f64) -> f64 { ret mvn.bvn_cdf(qn(u), qn(v), rho) }

fn ldt_cop(a: *mem.Arena, rho: f64, nu: f64, u: f64, v: f64) -> f64 {
    let x = nb.qt(u, nu, true, false)
    let y = nb.qt(v, nu, true, false)
    let pt2 = [2]f64{x, y}
    let sg = [4]f64{1.0f64, rho, rho, 1.0f64}
    let zm = [2]f64{0.0f64, 0.0f64}
    let (l, e) = mvn.dmvt(a, pt2[0usize..2usize], zm[0usize..2usize], sg[0usize..4usize], 2usize, nu)
    if e != ok { os.exit(9) }
    ret l - nb.dt(x, nu, true) - nb.dt(y, nu, true)
}

fn dt_cop(a: *mem.Arena, rho: f64, nu: f64, u: f64, v: f64) -> f64 { ret math.exp[f64](ldt_cop(a, rho, nu, u, v)) }

// copula's log1mexp: log(1 - exp(-a)), cutoff log 2
fn log1mexp(a: f64) -> f64 {
    if a <= 0.6931471805599453f64 { ret math.log[f64](0.0f64 - dist.expm1(0.0f64 - a)) }
    ret dist.log1p(0.0f64 - math.exp[f64](0.0f64 - a))
}

// log density of the bivariate Frank copula for theta > 0, as copFrank@dacopula (Li_{-1} on the log scale)
fn ldfrank_pos(th: f64, u: f64, v: f64) -> f64 {
    let lp = log1mexp(th)
    let l1 = log1mexp(th * u)
    let l2 = log1mexp(th * v)
    let lz = lp + ((l1 - lp) + (l2 - lp))
    let li = lz - 2.0f64 * log1mexp(0.0f64 - lz)
    ret math.log[f64](th) + li - th * (u + v) - (l1 + l2)
}

fn pt_cop(rho: f64, nu: f64, u: f64, v: f64) -> f64 {
    ret mt.mvbvt(i64(nu), 0.0f64, 0.0f64, nb.qt(u, nu, true, false), nb.qt(v, nu, true, false), 0i64, 0i64, rho)
}

fn tau_norm(rho: f64) -> f64 { ret 2.0f64 * math.asin[f64](rho) / 3.141592653589793f64 }
fn rho_norm(rho: f64) -> f64 { ret math.asin[f64](rho / 2.0f64) * 6.0f64 / 3.141592653589793f64 }
fn itau_norm(tau: f64) -> f64 { ret math.sin[f64](3.141592653589793f64 * tau / 2.0f64) }
fn irho_norm(rho: f64) -> f64 { ret 2.0f64 * math.sin[f64](3.141592653589793f64 * rho / 6.0f64) }

// tail dependence of the Archimedean families 0..4
fn lambda_arch(fam: usize, th: f64, upper: bool) -> f64 {
    if fam == 0usize && !upper { ret math.pow[f64](2.0f64, 0.0f64 - 1.0f64 / th) }
    if (fam == 2usize || fam == 4usize) && upper { ret 2.0f64 - math.pow[f64](2.0f64, 1.0f64 / th) }
    ret 0.0f64
}

fn lambda_t(rho: f64, nu: f64) -> f64 {
    ret 2.0f64 * nb.pt(0.0f64 - math.sqrt[f64]((nu + 1.0f64) * (1.0f64 - rho) / (1.0f64 + rho)), nu + 1.0f64, true, false)
}

fn itau_clayton(tau: f64) -> f64 { ret 2.0f64 * tau / (1.0f64 - tau) }
fn itau_gumbel(tau: f64) -> f64 { ret 1.0f64 / (1.0f64 - tau) }

// pobs on a column: rank (ties averaged) / (n + 1)
fn pobs(x: []const f64, out: []f64) {
    let n = x.len
    var i = 0usize
    while i < n {
        var less = 0.0f64
        var eq = 0.0f64
        var j = 0usize
        while j < n {
            if x[j] < x[i] { less += 1.0f64 }
            if x[j] == x[i] { eq += 1.0f64 }
            j += 1usize
        }
        out[i] = (less + (eq + 1.0f64) / 2.0f64) / (f64(n) + 1.0f64)
        i += 1usize
    }
}

// empirical copula of the pseudo-observations (u column, v column) at (a, b)
fn emp_cop(u: []const f64, v: []const f64, a: f64, b: f64) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < u.len {
        if u[i] <= a && v[i] <= b { c += 1.0f64 }
        i += 1usize
    }
    ret c / f64(u.len)
}

fn sgn(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

// Kendall's tau-b of two columns
fn kendall(x: []const f64, y: []const f64) -> f64 {
    var s = 0.0f64
    var tx = 0.0f64
    var ty = 0.0f64
    var i = 0usize
    while i < x.len {
        var j = 0usize
        while j < x.len {
            let a = sgn(x[i] - x[j])
            let b = sgn(y[i] - y[j])
            s += a * b
            tx += a * a
            ty += b * b
            j += 1usize
        }
        i += 1usize
    }
    ret s / (math.sqrt[f64](tx) * math.sqrt[f64](ty))
}

fn pearson(x: []const f64, y: []const f64) -> f64 {
    let n = f64(x.len)
    var mx = 0.0f64
    var my = 0.0f64
    var i = 0usize
    while i < x.len {
        mx += x[i]
        my += y[i]
        i += 1usize
    }
    mx = mx / n
    my = my / n
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < x.len {
        sxy += (x[i] - mx) * (y[i] - my)
        sxx += (x[i] - mx) * (x[i] - mx)
        syy += (y[i] - my) * (y[i] - my)
        i += 1usize
    }
    ret sxy / math.sqrt[f64](sxx * syy)
}

// Spearman's rho: Pearson correlation of the ranks
fn spearman(a: *mem.Arena, x: []const f64, y: []const f64) -> f64 {
    let (rx, e1) = mem.alloc[f64](a, x.len)
    let (ry, e2) = mem.alloc[f64](a, x.len)
    if e1 != ok || e2 != ok { os.exit(9) }
    pobs(x, rx)
    pobs(y, ry)
    ret pearson(rx, ry)
}

// rCopula samplers on R's stream; the n x 2 sample row-major
fn rcop_norm(a: *mem.Arena, g: *rng.Rng, n: usize, rho: f64) -> []f64 {
    let sg = [4]f64{1.0f64, rho, rho, 1.0f64}
    let zm = [2]f64{0.0f64, 0.0f64}
    let (m, e) = mvn.rmvnorm(a, g, n, zm[0usize..2usize], sg[0usize..4usize], 2usize, 0u8)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n * 2usize {
        m[i] = dist.pnorm(m[i], 0.0f64, 1.0f64, true, false)
        i += 1usize
    }
    ret m
}

fn rcop_t(a: *mem.Arena, g: *rng.Rng, n: usize, rho: f64, nu: f64) -> []f64 {
    let sg = [4]f64{1.0f64, rho, rho, 1.0f64}
    let zm = [2]f64{0.0f64, 0.0f64}
    let (m, e) = mvn.rmvt(a, g, n, sg[0usize..4usize], 2usize, nu, zm[0usize..2usize], 0u8)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n * 2usize {
        m[i] = nb.pt(m[i], nu, true, false)
        i += 1usize
    }
    ret m
}

// two uniform columns, drawn column by column: cbind(runif(n), runif(n)) as an n x 2 row-major block
fn two_unif(a: *mem.Arena, g: *rng.Rng, n: usize) -> []f64 {
    let (m, e) = mem.alloc[f64](a, n * 2usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n {
        m[2usize * i] = rng.unif(g)
        i += 1usize
    }
    i = 0usize
    while i < n {
        m[2usize * i + 1usize] = rng.unif(g)
        i += 1usize
    }
    ret m
}

fn rcop_clayton(a: *mem.Arena, g: *rng.Rng, n: usize, al: f64) -> []f64 {
    let m = two_unif(a, g, n)
    var i = 0usize
    while i < n {
        let u = m[2usize * i]
        let v = m[2usize * i + 1usize]
        m[2usize * i + 1usize] = math.pow[f64](math.pow[f64](u, 0.0f64 - al) * (math.pow[f64](v, 0.0f64 - al / (al + 1.0f64)) - 1.0f64) + 1.0f64, 0.0f64 - 1.0f64 / al)
        i += 1usize
    }
    ret m
}

fn rcop_frank(a: *mem.Arena, g: *rng.Rng, n: usize, al: f64) -> []f64 {
    let m = two_unif(a, g, n)
    let aa = 0.0f64 - math.abs[f64](al)
    var i = 0usize
    while i < n {
        let u = m[2usize * i]
        let v = m[2usize * i + 1usize]
        let w = 0.0f64 - 1.0f64 / aa * dist.log1p(0.0f64 - v * dist.expm1(0.0f64 - aa) / (math.exp[f64](0.0f64 - aa * u) * (v - 1.0f64) - v))
        var out = w
        if al > 0.0f64 { out = 1.0f64 - w }
        m[2usize * i + 1usize] = out
        i += 1usize
    }
    ret m
}

// copula's sinc_MM and Zolotarev's A_
fn sinc_mm(x: f64) -> f64 {
    let ax = math.abs[f64](x)
    if ax < 0.006f64 {
        if x == 0.0f64 { ret 1.0f64 }
        let x2 = x * x
        if ax < 2.0e-4f64 { ret 1.0f64 - x2 / 6.0f64 }
        ret 1.0f64 - x2 / 6.0f64 * (1.0f64 - x2 / 20.0f64)
    }
    ret math.sin[f64](x) / x
}

fn zol_a(x: f64, al: f64) -> f64 {
    let ia = 1.0f64 - al
    ret math.pow[f64](ia * sinc_mm(ia * x), ia) * math.pow[f64](al * sinc_mm(al * x), al) / sinc_mm(x)
}

// rstable0 of retstable.c: one positive stable draw, alpha in (0,1)
fn rstable0(g: *rng.Rng, al: f64) -> f64 {
    if al == 1.0f64 { ret 1.0f64 }
    let u = rng.unif(g)
    var w = rng.exp_unit(g)
    while w == 0.0f64 { w = rng.exp_unit(g) }
    ret math.pow[f64](zol_a(3.141592653589793f64 * u, al) / math.pow[f64](w, 1.0f64 - al), 1.0f64 / al)
}

// R's beta(a, b) of nmath
fn rbeta_fn(a: f64, b: f64) -> f64 {
    if a + b < 171.61447887182298f64 { ret 1.0f64 / nm.gammafn(a + b) * nm.gammafn(a) * nm.gammafn(b) }
    ret math.exp[f64](nb.lbeta(a, b))
}

// rSibuya of rSibuya.c, one draw
fn rsibuya(g: *rng.Rng, al: f64, g1a: f64) -> f64 {
    let u = rng.unif(g)
    if u <= al { ret 1.0f64 }
    let xmax = 1.0f64 / 2.220446049250313e-16f64
    let ginv = math.pow[f64]((1.0f64 - u) * g1a, 0.0f64 - 1.0f64 / al)
    let fg = math.floor[f64](ginv)
    if ginv > xmax { ret fg }
    if 1.0f64 - u < 1.0f64 / (fg * rbeta_fn(fg, 1.0f64 - al)) { ret math.ceil[f64](ginv) }
    ret fg
}

// Gumbel: V ~ positive stable on R's stream, then runif(n * 2) column by column
fn rcop_gumbel(a: *mem.Arena, g: *rng.Rng, n: usize, th: f64) -> []f64 { ret rcop_gumbel_d(a, g, n, 2usize, th) }

// n draws of d uniforms as an n x d row-major block, drawn column by column: matrix(runif(n * d), nrow = n)
fn unif_cols(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize) -> []f64 {
    let (m, e) = mem.alloc[f64](a, n * d)
    if e != ok { os.exit(9) }
    var j = 0usize
    while j < d {
        var i = 0usize
        while i < n {
            m[d * i + j] = rng.unif(g)
            i += 1usize
        }
        j += 1usize
    }
    ret m
}

fn rcop_gumbel_d(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, th: f64) -> []f64 {
    let b = 1.0f64 / th
    let cf = math.pow[f64](math.cos[f64](1.5707963267948966f64 * b), 0.0f64 - 1.0f64 / b)
    let gam = math.pow[f64](math.cos[f64](3.141592653589793f64 * (b / 2.0f64)), th)
    let (fr, e0) = mem.alloc[f64](a, n)
    if e0 != ok { os.exit(9) }
    var i = 0usize
    while i < n {
        fr[i] = cf * rstable0(g, b) * gam
        i += 1usize
    }
    let m = unif_cols(a, g, n, d)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            m[d * i + j] = math.exp[f64](0.0f64 - math.pow[f64](0.0f64 - math.log[f64](m[d * i + j]) / fr[i], b))
            j += 1usize
        }
        i += 1usize
    }
    ret m
}

// Clayton for d > 2: matrix(runif(n * d)), then rgamma(n, shape 1 / alpha), psi(-log(val) / gam) with pmax(1 + t, 0)^(-1 / alpha)
fn rcop_clayton_d(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, al: f64) -> []f64 {
    let m = unif_cols(a, g, n, d)
    let (gm, e0) = mem.alloc[f64](a, n)
    if e0 != ok { os.exit(9) }
    var i = 0usize
    while i < n {
        gm[i] = rgamma_any(g, 1.0f64 / al)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            var base = 1.0f64 + (0.0f64 - math.log[f64](m[d * i + j])) / gm[i]
            if base < 0.0f64 { base = 0.0f64 }
            m[d * i + j] = math.pow[f64](base, 0.0f64 - 1.0f64 / al)
            j += 1usize
        }
        i += 1usize
    }
    ret m
}

// Joe: V0 ~ Sibuya(1 / theta), then rexp(n * 2) column by column
fn rcop_joe(a: *mem.Arena, g: *rng.Rng, n: usize, th: f64) -> []f64 { ret rcop_joe_d(a, g, n, 2usize, th) }

fn rcop_joe_d(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, th: f64) -> []f64 {
    let al = 1.0f64 / th
    let g1a = nm.gammafn(1.0f64 - al)
    let (v0, e0) = mem.alloc[f64](a, n)
    let (m, e1) = mem.alloc[f64](a, n * d)
    if e0 != ok || e1 != ok { os.exit(9) }
    var i = 0usize
    while i < n {
        v0[i] = rsibuya(g, al, g1a)
        i += 1usize
    }
    var j = 0usize
    while j < d {
        i = 0usize
        while i < n {
            m[d * i + j] = rng.exp_unit(g)
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < d {
            m[d * i + j] = 1.0f64 - math.pow[f64](0.0f64 - dist.expm1(0.0f64 - m[d * i + j] / v0[i]), al)
            j += 1usize
        }
        i += 1usize
    }
    ret m
}

// R draws and discards an n x 2 block, then u (n draws) and w (n draws)
fn rcop_amh(a: *mem.Arena, g: *rng.Rng, n: usize, al: f64) -> []f64 {
    let (m, e) = mem.alloc[f64](a, n * 2usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n * 2usize {
        let skip = rng.unif(g)
        i += 1usize
    }
    i = 0usize
    while i < n {
        m[2usize * i] = rng.unif(g)
        i += 1usize
    }
    i = 0usize
    while i < n {
        m[2usize * i + 1usize] = rng.unif(g)
        i += 1usize
    }
    i = 0usize
    while i < n {
        let u = m[2usize * i]
        let w = m[2usize * i + 1usize]
        let b = 1.0f64 - u
        let aa = w * (al * b) * (al * b) - al
        let bb = (al + 1.0f64) - 2.0f64 * al * b * w
        let cc = w - 1.0f64
        let v = (0.0f64 - bb + math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)) / 2.0f64 / aa
        m[2usize * i + 1usize] = 1.0f64 - v
        i += 1usize
    }
    ret m
}


// ---- uniroot (R_zeroin2) on tau(theta) - target or rho(theta) - target, for iTau and iRho of the numerically inverted families ----

type RootC = struct { fam: usize, mode: usize, tgt: f64 }

fn root_f(c: *RootC, x: f64) -> f64 {
    if c.mode == 0usize { ret ktau(c.fam, x) - c.tgt }
    ret rho_frank(x) - c.tgt
}

fn zeroin2(c: *RootC, lower: f64, upper: f64, flo: f64, fup: f64, tol: f64, maxit: i64) -> f64 {
    let eps = 2.220446049250313e-16f64
    var a = lower
    var b = upper
    var cc = a
    var fa = flo
    var fb = fup
    var fc = fa
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    var left = maxit + 1i64
    while left > 0i64 {
        left -= 1i64
        let prev = b - a
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a = b
            b = cc
            cc = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * math.abs[f64](b) + tol / 2.0f64
        var step = (cc - b) / 2.0f64
        if math.abs[f64](step) <= tol_act || fb == 0.0f64 { ret b }
        if math.abs[f64](prev) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = cc - b
            var pp = 0.0f64
            var qq = 0.0f64
            if a == cc {
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
        fb = root_f(c, b)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            cc = a
            fc = fa
        }
    }
    ret b
}

fn uniroot(c: *RootC, lo: f64, up: f64, tol: f64) -> f64 {
    ret zeroin2(c, lo, up, root_f(c, lo), root_f(c, up), tol, 1000i64)
}

// iTau of copula 1.1-7 (tol 1e-7): Frank and Joe by safeUroot's interval, AMH by iTauCopula with bound.eps = sqrt(eps)
fn itau_arch(fam: usize, tau: f64) -> f64 {
    var c: RootC = zero
    c.fam = fam
    c.tgt = tau
    if fam == 0usize { ret itau_clayton(tau) }
    if fam == 2usize { ret itau_gumbel(tau) }
    if fam == 1usize {
        if tau == 0.0f64 { ret 0.0f64 }
        if tau > 0.0f64 { ret uniroot(&c, 0.0f64, 7.21e16f64, 1.0e-7f64) }
        ret uniroot(&c, 0.0f64 - 1.81e16f64, 0.0f64, 1.0e-7f64)
    }
    if fam == 4usize {
        if tau < 0.0f64 { ret 1.0f64 }
        ret uniroot(&c, 1.0f64, 98.0f64, 1.0e-7f64)
    }
    let tau_min = (5.0f64 - 8.0f64 * math.log[f64](2.0f64)) / 3.0f64
    if tau <= tau_min { ret 0.0f64 - 1.0f64 }
    if tau >= 1.0f64 / 3.0f64 { ret 1.0f64 }
    let eb = math.sqrt[f64](2.220446049250313e-16f64)
    ret uniroot(&c, 0.0f64 - 1.0f64 + eb, 1.0f64 - eb, 1.0e-7f64)
}

// iRho of Frank: iRhoCopula, bound.eps = 0, interval +-sqrt(DBL_MAX)
fn irho_frank(rho: f64) -> f64 {
    var c: RootC = zero
    c.fam = 1usize
    c.mode = 1usize
    c.tgt = rho
    let b = math.sqrt[f64](1.7976931348623157e308f64)
    ret uniroot(&c, 0.0f64 - b, b, 1.0e-7f64)
}

// ---- fitCopula(method = "ml" or "mpl"): optim L-BFGS-B from the itau start, numerical gradient ndeps 1e-3, factr 1e7, maxit 1000 ----

type FitC = struct { ar: *mem.Arena, kind: usize, n: usize, u: []f64, lo: [2]f64, up: [2]f64 }

fn fit_nll(c: *FitC, p: []const f64) -> f64 {
    var s = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    let mk = mem.mark(c.ar)
    while i < c.n {
        let u = c.u[2usize * i]
        let v = c.u[2usize * i + 1usize]
        var nu = 0.0f64
        if c.kind == 6usize { nu = p[1usize] }
        let ld = cop_ld(c.ar, c.kind, p[0usize], nu, u, v)
        if c.kind == 6usize { mem.reset(c.ar, mk) }
        if ld == 0.0f64 - 1.0f64 / 0.0f64 {
            s = ld
            comp = 0.0f64
            break
        }
        // R sums in long double: Neumaier compensation keeps the same accuracy
        let tt = s + ld
        if math.abs[f64](s) >= math.abs[f64](ld) { comp += (s - tt) + ld } else { comp += (ld - tt) + s }
        s = tt
        i += 1usize
    }
    s += comp
    let big = 1.7976931348623157e308f64 / 8.0f64
    if s > big { s = big }
    if s < 0.0f64 - big { s = 0.0f64 - big }
    ret 0.0f64 - s
}

fn fit_grad(c: *FitC, p: []const f64, out: []f64) {
    var np = 1usize
    if c.kind == 6usize { np = 2usize }
    var w = [2]f64{p[0usize], 0.0f64}
    if np == 2usize { w[1usize] = p[1usize] }
    let _ = lb.lbfgsb_fd_gradient[FitC](c, fit_nll, w[0usize..np], c.lo[0usize..np], c.up[0usize..np], 0.001f64, out)
}

// u is the n x 2 pseudo-observation block, row-major; kind 0 clayton, 1 gumbel, 2 normal, 3 frank, 4 joe, 5 amh, 6 t (rho, df);
// start holds the itau start and receives the estimate
fn fit_ml(a: *mem.Arena, kind: usize, u: []f64, n: usize, start: []f64) -> i64 {
    var c: FitC = zero
    c.ar = a
    c.kind = kind
    c.n = n
    c.u = u
    let eps = math.sqrt[f64](2.220446049250313e-16f64)
    let big = 1.7976931348623157e308f64 / 8.0f64
    var np = 1usize
    if kind == 0usize {
        c.lo[0usize] = 0.0f64 - 1.0f64 + eps
        c.up[0usize] = big
    }
    if kind == 1usize || kind == 4usize {
        c.lo[0usize] = 1.0f64 + eps
        c.up[0usize] = big
    }
    if kind == 2usize || kind == 5usize || kind == 6usize {
        c.lo[0usize] = 0.0f64 - 1.0f64 + eps
        c.up[0usize] = 1.0f64 - eps
    }
    if kind == 3usize {
        c.lo[0usize] = 0.0f64 - big
        c.up[0usize] = big
    }
    if kind == 6usize {
        np = 2usize
        c.lo[1usize] = 0.01f64 + eps * 0.01f64
        c.up[1usize] = big
    }
    let (fv, fl) = lb.lbfgsb[FitC](a, &c, fit_nll, fit_grad, start[0usize..np], c.lo[0usize..np], c.up[0usize..np], 10000000.0f64, 0.0f64, 5usize, 1000usize)
    ret fl
}

// ---- gofCopula(method = "Sn", estim.method = "mpl", simulation = "pb") for the one-parameter bivariate families ----

// kind 0 clayton, 1 gumbel, 2 normal, 3 frank, 4 joe, 5 amh; the cop-family index of pcop/dcop for the Archimedean kinds
fn fam_of(kind: usize) -> usize {
    if kind == 0usize { ret 0usize }
    if kind == 1usize { ret 2usize }
    if kind == 3usize { ret 1usize }
    if kind == 4usize { ret 4usize }
    ret 3usize
}

fn itau_start(kind: usize, tau: f64) -> f64 {
    if kind == 2usize { ret itau_norm(tau) }
    ret itau_arch(fam_of(kind), tau)
}

// fitCopula(method = "mpl") on raw data x (n x 2, row-major); the estimate goes to out[0]
fn fit_mpl(a: *mem.Arena, kind: usize, x: []const f64, n: usize, out: []f64) -> []f64 {
    let (c1, e1) = mem.alloc[f64](a, n)
    let (c2, e2) = mem.alloc[f64](a, n)
    let (p1, e3) = mem.alloc[f64](a, n)
    let (p2, e4) = mem.alloc[f64](a, n)
    let (uv, e5) = mem.alloc[f64](a, 2usize * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(9) }
    var i = 0usize
    while i < n {
        c1[i] = x[2usize * i]
        c2[i] = x[2usize * i + 1usize]
        i += 1usize
    }
    pobs(c1, p1)
    pobs(c2, p2)
    i = 0usize
    while i < n {
        uv[2usize * i] = p1[i]
        uv[2usize * i + 1usize] = p2[i]
        i += 1usize
    }
    out[0usize] = itau_start(kind, kendall(p1, p2))
    let _ = fit_ml(a, kind, uv, n, out[0usize..2usize])
    ret uv
}

fn cop_cdf(kind: usize, th: f64, u: f64, v: f64) -> f64 {
    if kind == 2usize { ret pnorm_cop(th, u, v) }
    ret pcop(fam_of(kind), th, u, v)
}

// S_n = sum_i (C_n(u_i) - C_theta(u_i))^2 on the pseudo-observation block uv
fn sn_stat(kind: usize, th: f64, uv: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        let a = uv[2usize * i]
        let b = uv[2usize * i + 1usize]
        var cnt = 0.0f64
        var k = 0usize
        while k < n {
            if uv[2usize * k] <= a && uv[2usize * k + 1usize] <= b { cnt += 1.0f64 }
            k += 1usize
        }
        let d = cnt / f64(n) - cop_cdf(kind, th, a, b)
        s += d * d
        i += 1usize
    }
    ret s
}

fn rcop_kind(a: *mem.Arena, g: *rng.Rng, kind: usize, n: usize, th: f64) -> []f64 {
    if kind == 0usize { ret rcop_clayton(a, g, n, th) }
    if kind == 1usize { ret rcop_gumbel(a, g, n, th) }
    if kind == 2usize { ret rcop_norm(a, g, n, th) }
    if kind == 3usize { ret rcop_frank(a, g, n, th) }
    if kind == 4usize { ret rcop_joe(a, g, n, th) }
    ret rcop_amh(a, g, n, th)
}

// out = (statistic, p-value, estimate); the R seed is set by the caller: set.seed(seed) before gofCopula(...)
fn gof_sn(a: *mem.Arena, g: *rng.Rng, kind: usize, x: []const f64, n: usize, nboot: usize, out: []f64) {
    var th = [2]f64{0.0f64, 0.0f64}
    let uv = fit_mpl(a, kind, x, n, th[0usize..2usize])
    let t = sn_stat(kind, th[0usize], uv, n)
    var hits = 0.0f64
    var k = 0usize
    while k < nboot {
        let mk = mem.mark(a)
        let m = rcop_kind(a, g, kind, n, th[0usize])
        var th2 = [2]f64{0.0f64, 0.0f64}
        let uv2 = fit_mpl(a, kind, m, n, th2[0usize..2usize])
        let t0 = sn_stat(kind, th2[0usize], uv2, n)
        if t0 >= t { hits += 1.0f64 }
        mem.reset(a, mk)
        k += 1usize
    }
    out[0usize] = t
    out[1usize] = (hits + 0.5f64) / (f64(nboot) + 1.0f64)
    out[2usize] = th[0usize]
}

// ---- marginal distribution copulas (mvdc), bivariate: copula kinds 0..5 as above and 6 the t copula with df nu ----

// log density of the copula of kind (0 clayton, 1 gumbel, 2 normal, 3 frank, 4 joe, 5 amh, 6 t) at (u, v)
fn cop_ld(a: *mem.Arena, kind: usize, th: f64, nu: f64, u: f64, v: f64) -> f64 {
    if kind == 0usize { ret ldclayton(th, u, v) }
    if kind == 1usize { ret math.log[f64](dcop(2usize, th, u, v)) }
    if kind == 2usize { ret ldnorm_cop(th, u, v) }
    if kind == 3usize {
        if th > 0.0f64 { ret ldfrank_pos(th, u, v) }
        ret math.log[f64](dcop(1usize, th, u, v))
    }
    if kind == 4usize { ret math.log[f64](dcop(4usize, th, u, v)) }
    if kind == 5usize { ret math.log[f64](dcop(3usize, th, u, v)) }
    ret ldt_cop(a, th, nu, u, v)
}

fn cop_cdf_t(kind: usize, th: f64, nu: f64, u: f64, v: f64) -> f64 {
    if kind == 6usize { ret pt_cop(th, nu, u, v) }
    ret cop_cdf(kind, th, u, v)
}

// margins: 0 norm(mean, sd), 1 exp(rate), 2 gamma(shape, rate), 3 lnorm(meanlog, sdlog)
fn m_np(k: usize) -> usize {
    if k == 1usize { ret 1usize }
    ret 2usize
}

fn m_cdf(k: usize, p: []const f64, x: f64) -> f64 {
    if k == 0usize { ret dist.pnorm(x, p[0usize], p[1usize], true, false) }
    if k == 1usize { ret dist.pexp(x, 1.0f64 / p[0usize], true, false) }
    if k == 2usize { ret nm.pgamma(x, p[0usize], 1.0f64 / p[1usize], true, false) }
    ret dist.plnorm(x, p[0usize], p[1usize], true, false)
}

fn m_ld(k: usize, p: []const f64, x: f64) -> f64 {
    if k == 0usize { ret dist.dnorm(x, p[0usize], p[1usize], true) }
    if k == 1usize { ret dist.dexp(x, 1.0f64 / p[0usize], true) }
    if k == 2usize { ret nm.dgamma(x, p[0usize], 1.0f64 / p[1usize], true) }
    ret dist.dlnorm(x, p[0usize], p[1usize], true)
}

fn m_q(k: usize, p: []const f64, u: f64) -> f64 {
    if k == 0usize { ret dist.qnorm(u, p[0usize], p[1usize], true, false) }
    if k == 1usize { ret dist.qexp(u, 1.0f64 / p[0usize], true, false) }
    if k == 2usize { ret nm.qgamma(u, p[0usize], 1.0f64 / p[1usize], true, false) }
    ret dist.qlnorm(u, p[0usize], p[1usize], true, false)
}

// dMvdc(c(x, y), mvdc, log = TRUE); pm0 and pm1 are the marginal parameters
fn dmvdc_log(a: *mem.Arena, ck: usize, th: f64, nu: f64, mk0: usize, pm0: []const f64, mk1: usize, pm1: []const f64, x: f64, y: f64) -> f64 {
    let u = m_cdf(mk0, pm0, x)
    let v = m_cdf(mk1, pm1, y)
    let dm = (0.0f64 + m_ld(mk0, pm0, x)) + m_ld(mk1, pm1, y)
    ret cop_ld(a, ck, th, nu, u, v) + dm
}

fn pmvdc(ck: usize, th: f64, nu: f64, mk0: usize, pm0: []const f64, mk1: usize, pm1: []const f64, x: f64, y: f64) -> f64 {
    ret cop_cdf_t(ck, th, nu, m_cdf(mk0, pm0, x), m_cdf(mk1, pm1, y))
}

// rMvdc(n, mvdc) on R's stream; the n x 2 sample row-major
fn rmvdc(a: *mem.Arena, g: *rng.Rng, n: usize, ck: usize, th: f64, nu: f64, mk0: usize, pm0: []const f64, mk1: usize, pm1: []const f64) -> []f64 {
    var m: []f64 = zero
    if ck == 6usize { m = rcop_t(a, g, n, th, nu) } else { m = rcop_kind(a, g, ck, n, th) }
    var i = 0usize
    while i < n {
        m[2usize * i] = m_q(mk0, pm0, m[2usize * i])
        m[2usize * i + 1usize] = m_q(mk1, pm1, m[2usize * i + 1usize])
        i += 1usize
    }
    ret m
}

type MvC = struct { ar: *mem.Arena, ck: usize, nu: f64, mk0: usize, mk1: usize, n: usize, x: []f64 }

// minus the log-likelihood of loglikMvdc over param = c(margin 1 pars, margin 2 pars, copula par)
fn mv_nll(c: *MvC, p: []const f64) -> f64 {
    let n0 = m_np(c.mk0)
    let n1 = m_np(c.mk1)
    var s = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    let mk = mem.mark(c.ar)
    while i < c.n {
        let ld = dmvdc_log(c.ar, c.ck, p[n0 + n1], c.nu, c.mk0, p[0usize..n0], c.mk1, p[n0..n0 + n1], c.x[2usize * i], c.x[2usize * i + 1usize])
        let tt = s + ld
        if math.abs[f64](s) >= math.abs[f64](ld) { comp += (s - tt) + ld } else { comp += (ld - tt) + s }
        s = tt
        mem.reset(c.ar, mk)
        i += 1usize
    }
    ret 0.0f64 - (s + comp)
}

// optim's numerical gradient, unbounded: central differences with ndeps 1e-3
fn mv_grad(c: *MvC, p: []const f64, out: []f64) {
    let q = p.len
    var w: [8]f64 = zero
    var j = 0usize
    while j < q {
        w[j] = p[j]
        j += 1usize
    }
    j = 0usize
    while j < q {
        let keep = w[j]
        w[j] = keep + 0.001f64
        let v1 = mv_nll(c, w[0usize..q])
        w[j] = keep - 0.001f64
        let v2 = mv_nll(c, w[0usize..q])
        out[j] = (v1 - v2) / 0.002f64
        w[j] = keep
        j += 1usize
    }
}

// fitMvdc(data, mvdc, start) with optim's BFGS (reltol sqrt(eps), maxit 100); start is replaced by the estimate
fn fit_mvdc(a: *mem.Arena, ck: usize, nu: f64, mk0: usize, mk1: usize, x: []f64, n: usize, start: []f64) -> f64 {
    var c: MvC = zero
    c.ar = a
    c.ck = ck
    c.nu = nu
    c.mk0 = mk0
    c.mk1 = mk1
    c.n = n
    c.x = x
    ret rb.vmmin[MvC](a, &c, mv_nll, mv_grad, start, math.sqrt[f64](2.220446049250313e-16f64), 100usize)
}

// ---- iRho of Clayton and Gumbel: copula interpolates a stored smoothing-spline grid of rho (approxfun) and back-transforms ----

fn parse_tab(a: *mem.Arena, s: str) -> []f64 {
    let (out, e0) = mem.alloc[f64](a, 1001usize)
    if e0 != ok { os.exit(9) }
    let (it0, es) = str.split(s, " ")
    if es != ok { os.exit(9) }
    var it = it0
    var i = 0usize
    while i < 1001usize {
        let (tok, more) = str.split_next(&it)
        if !more { break }
        let (v, e) = str.parse_f64(tok)
        if e != ok { os.exit(9) }
        out[i] = v
        i += 1usize
    }
    ret out
}

// approxfun(x, y, rule = 1 or 2)(v): NaN outside the grid for rule 1
fn approx_lin(xs: []const f64, ys: []const f64, v: f64, rule2: bool) -> f64 {
    var i = 0usize
    var j = xs.len - 1usize
    if v < xs[i] {
        if rule2 { ret ys[i] }
        ret 0.0f64 / 0.0f64
    }
    if v > xs[j] {
        if rule2 { ret ys[j] }
        ret 0.0f64 / 0.0f64
    }
    while i + 1usize < j {
        let ij = (i + j) / 2usize
        if v < xs[ij] { j = ij } else { i = ij }
    }
    if v == xs[j] { ret ys[j] }
    if v == xs[i] { ret ys[i] }
    ret ys[i] + (ys[j] - ys[i]) * ((v - xs[i]) / (xs[j] - xs[i]))
}

// iRho(claytonCopula(), rho)
fn irho_clayton(a: *mem.Arena, rho: f64) -> f64 {
    var th = 0.0f64
    if rho <= 0.0f64 {
        th = approx_lin(parse_tab(a, tb.clayton_neg_y()), parse_tab(a, tb.clayton_neg_x()), rho, false)
    } else {
        th = approx_lin(parse_tab(a, tb.clayton_pos_y()), parse_tab(a, tb.clayton_pos_x()), rho, false)
    }
    if th <= 0.0f64 { ret th }
    ret 10.0f64 * at_h(th)
}

// iRho(gumbelCopula(), rho): negative rho is replaced by 0
fn irho_gumbel(a: *mem.Arena, rho: f64) -> f64 {
    var r = rho
    if r < 0.0f64 { r = 0.0f64 }
    let th = approx_lin(parse_tab(a, tb.gumbel_y()), parse_tab(a, tb.gumbel_x()), r, true)
    ret 20.0f64 * at_h(th) + 1.0f64
}

fn at_h(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - at_h(0.0f64 - x) }
    ret 0.5f64 * dist.log1p(2.0f64 * x / (1.0f64 - x))
}

// log density of the bivariate Clayton copula as copClayton@dacopula (theta != 0; minus infinity outside the support for theta < 0)
fn ldclayton(th: f64, u: f64, v: f64) -> f64 {
    let lu = math.log[f64](u) + math.log[f64](v)
    var sg = 1.0f64
    if th < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    let t = sg * ((math.pow[f64](u, 0.0f64 - th) - 1.0f64) + (math.pow[f64](v, 0.0f64 - th) - 1.0f64))
    if th < 0.0f64 && !(t < 1.0f64) { ret 0.0f64 - 1.0f64 / 0.0f64 }
    var l1 = 0.0f64
    if th < 0.0f64 { l1 = dist.log1p(0.0f64 - t) } else { l1 = dist.log1p(t) }
    ret dist.log1p(th) - (1.0f64 + th) * lu - (2.0f64 + 1.0f64 / th) * l1
}

// ---- dimension d >= 2: exchangeable normal and t copulas, Archimedean distribution functions, the Clayton density and the samplers ----

fn ex_sigma(a: *mem.Arena, d: usize, rho: f64) -> []f64 {
    let (s, e) = mem.alloc[f64](a, d * d)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            if i == j { s[d * i + j] = 1.0f64 } else { s[d * i + j] = rho }
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// log density of the normal copula with exchangeable correlation rho at u (length d)
fn ldnorm_d(a: *mem.Arena, rho: f64, u: []const f64) -> f64 {
    let d = u.len
    let (x, e0) = mem.alloc[f64](a, d)
    let (zm, e1) = mem.alloc[f64](a, d)
    if e0 != ok || e1 != ok { os.exit(9) }
    var s = 0.0f64
    var j = 0usize
    while j < d {
        x[j] = qn(u[j])
        zm[j] = 0.0f64
        s += dist.dnorm(x[j], 0.0f64, 1.0f64, true)
        j += 1usize
    }
    let (l, e) = mvn.dmvnorm(a, x, zm, ex_sigma(a, d, rho), d)
    if e != ok { os.exit(9) }
    ret l - s
}

fn ldt_d(a: *mem.Arena, rho: f64, nu: f64, u: []const f64) -> f64 {
    let d = u.len
    let (x, e0) = mem.alloc[f64](a, d)
    let (zm, e1) = mem.alloc[f64](a, d)
    if e0 != ok || e1 != ok { os.exit(9) }
    var s = 0.0f64
    var j = 0usize
    while j < d {
        x[j] = nb.qt(u[j], nu, true, false)
        zm[j] = 0.0f64
        s += nb.dt(x[j], nu, true)
        j += 1usize
    }
    let (l, e) = mvn.dmvt(a, x, zm, ex_sigma(a, d, rho), d, nu)
    if e != ok { os.exit(9) }
    ret l - s
}

// Clayton log density, theta > 0, any d (copClayton@dacopula)
fn ldclayton_d(th: f64, u: []const f64) -> f64 {
    let d = u.len
    var lu = 0.0f64
    var t = 0.0f64
    var s1 = 0.0f64
    var j = 0usize
    while j < d {
        lu += math.log[f64](u[j])
        t += math.pow[f64](u[j], 0.0f64 - th) - 1.0f64
        if j + 1usize < d { s1 += dist.log1p(th * f64(j + 1usize)) }
        j += 1usize
    }
    ret s1 - (1.0f64 + th) * lu - (f64(d) + 1.0f64 / th) * dist.log1p(t)
}

// distribution function of the d-dimensional Archimedean copula (family index as pcop) at u: psi(sum iPsi(u_j))
fn pcop_d(fam: usize, th: f64, u: []const f64) -> f64 {
    let d = u.len
    var s = 0.0f64
    var p = 1.0f64
    var j = 0usize
    while j < d {
        if fam == 0usize { s += math.pow[f64](u[j], 0.0f64 - th) - 1.0f64 }
        if fam == 1usize { p = p * dist.expm1(0.0f64 - th * u[j]) }
        if fam == 2usize { s += math.pow[f64](0.0f64 - math.log[f64](u[j]), th) }
        if fam == 3usize { s += math.log[f64]((1.0f64 - th * (1.0f64 - u[j])) / u[j]) }
        if fam == 4usize { p = p * (1.0f64 - math.pow[f64](1.0f64 - u[j], th)) }
        j += 1usize
    }
    if fam == 0usize { ret math.pow[f64](1.0f64 + s, 0.0f64 - 1.0f64 / th) }
    if fam == 1usize { ret 0.0f64 - math.log[f64](1.0f64 + p / math.pow[f64](dist.expm1(0.0f64 - th), f64(d - 1usize))) / th }
    if fam == 2usize { ret math.exp[f64](0.0f64 - math.pow[f64](s, 1.0f64 / th)) }
    if fam == 3usize { ret (1.0f64 - th) / (math.exp[f64](s) - th) }
    ret 1.0f64 - math.pow[f64](1.0f64 - p, 1.0f64 / th)
}

fn rcop_norm_d(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, rho: f64) -> []f64 {
    let (zm, e0) = mem.alloc[f64](a, d)
    if e0 != ok { os.exit(9) }
    var j = 0usize
    while j < d {
        zm[j] = 0.0f64
        j += 1usize
    }
    let (m, e) = mvn.rmvnorm(a, g, n, zm, ex_sigma(a, d, rho), d, 0u8)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n * d {
        m[i] = dist.pnorm(m[i], 0.0f64, 1.0f64, true, false)
        i += 1usize
    }
    ret m
}

fn rcop_t_d(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, rho: f64, nu: f64) -> []f64 {
    let (zm, e0) = mem.alloc[f64](a, d)
    if e0 != ok { os.exit(9) }
    var j = 0usize
    while j < d {
        zm[j] = 0.0f64
        j += 1usize
    }
    let (m, e) = mvn.rmvt(a, g, n, ex_sigma(a, d, rho), d, nu, zm, 0u8)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n * d {
        m[i] = nb.pt(m[i], nu, true, false)
        i += 1usize
    }
    ret m
}

// logarithmic series draws, Kemp (1981): LS for alpha < 0.95 (here h > -3), LK in the log(1 - alpha) = h form otherwise
fn rlogseries_ln1p(g: *rng.Rng, h: f64) -> f64 {
    let al = 0.0f64 - dist.expm1(h)
    if h > 0.0f64 - 3.0f64 {
        let t = 0.0f64 - al / math.log[f64](1.0f64 - al)
        var u = rng.unif(g)
        var p = t
        var x = 1.0f64
        while u > p {
            u = u - p
            x = x + 1.0f64
            p = p * al * (x - 1.0f64) / x
        }
        ret x
    }
    let u2 = rng.unif(g)
    if u2 > al { ret 1.0f64 }
    let u1 = rng.unif(g)
    let h_ = u1 * h
    let q = 0.0f64 - dist.expm1(h_)
    if u2 < q * q {
        let lq = log1mexp(0.0f64 - h_)
        if lq == 0.0f64 { ret 1.0f64 / 0.0f64 }
        ret 1.0f64 + math.floor[f64](math.log[f64](u2) / lq)
    }
    if u2 > q { ret 1.0f64 }
    ret 2.0f64
}

// Frank for d > 2 (theta > 0): fr ~ log series with h = -theta, U = matrix(runif(d * n)), psi(-log(U) / fr)
fn rcop_frank_d(a: *mem.Arena, g: *rng.Rng, n: usize, d: usize, th: f64) -> []f64 {
    let (fr, e0) = mem.alloc[f64](a, n)
    if e0 != ok { os.exit(9) }
    var i = 0usize
    while i < n {
        fr[i] = rlogseries_ln1p(g, 0.0f64 - th)
        i += 1usize
    }
    let m = unif_cols(a, g, n, d)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            let t = (0.0f64 - math.log[f64](m[d * i + j])) / fr[i]
            m[d * i + j] = 0.0f64 - log1mexp(t - log1mexp(th)) / th
            j += 1usize
        }
        i += 1usize
    }
    ret m
}

// rgamma(1, shape a, scale 1): Ahrens-Dieter GD for a >= 1 from the shared stream module, and nmath's GS (a < 1) here
fn rgamma_any(g: *rng.Rng, a: f64) -> f64 {
    if a >= 1.0f64 { ret rng.rgamma(g, a, 1.0f64) }
    let e = 1.0f64 + 0.36787944117144233f64 * a
    while true {
        let p = e * rng.unif(g)
        if p >= 1.0f64 {
            let x = 0.0f64 - math.log[f64]((e - p) / a)
            if rng.exp_unit(g) >= (1.0f64 - a) * math.log[f64](x) { ret x }
        } else {
            let x = math.exp[f64](math.log[f64](p) / a)
            if rng.exp_unit(g) >= x { ret x }
        }
    }
    ret 0.0f64
}
