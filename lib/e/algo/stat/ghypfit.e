// R GeneralizedHyperbolic fits: hyperbFit and nigFit by optim's Nelder-Mead, BFGS and L-BFGS-B from the package's start values (BN, US, FN, SL, MoM; the
// package's hist/lm asymptote start, the skew-Laplace start and the method-of-moments start, each with its inner optim). Not here: nlm, bounded nlminb, constrOptim
// and the Cauchy start (they sit on routines this library does not have), the Hessian and summary, hyperblm.

use e.algo.stat.classint as ci
use e.algo.stat.ghyp as gh
use e.algo.stat.ghypmore as gm
use e.algo.stat.gslfns as gs
use e.algo.stat.lbfgsb as lb
use e.algo.stat.rbfgs as bf
use e.algo.stat.rnm as rn
use e.math
use e.math.dist as nm
use e.math.nmath as nmm
use e.algo.stat.rdensity as rd
use e.math.scale as sc
use e.mem

type FitC = struct { a: *mem.Arena, x: []const f64, fam: usize, raw: bool, eps: f64, nfn: usize, ngr: usize, counting: bool, mode: usize, m_mean: f64, m_var: f64, m_skew: f64, m_kurt: f64, ps2: f64, th_old: [4]f64 }

fn fit_lambda(fam: usize) -> f64 {
    if fam == 1usize { ret 0.0f64 - 0.5f64 }
    ret 1.0f64
}

// the negative log-likelihood of the package's llfunc (mode 0; parameters mu, log delta, pi, log zeta, or on the raw scale mu, delta, pi, zeta), the method of
// moments criterion of hyperbFitStartMoM / nigFitStartMoM (mode 1) and the skew-Laplace likelihood of the SL start (mode 2)
fn fit_nll(c: *FitC, par: []const f64) -> f64 {
    if c.counting { c.nfn += 1usize }
    let n = c.x.len
    if c.mode == 6usize {
        // constrOptim's adaptive barrier R(theta, theta.old) for ui = diag(c(0, 1, 0, 1)), ci = c(-1e99, 0, -1e99, 0), mu = 1e-4
        if par[1usize] < 0.0f64 || par[3usize] < 0.0f64 { ret 0.0f64 / 0.0f64 }
        let big = 1.0e99f64
        var bar = (big * math.log[f64](big) - 0.0f64) + (c.th_old[1usize] * math.log[f64](par[1usize]) - par[1usize])
        bar = bar + (big * math.log[f64](big) - 0.0f64)
        bar = bar + (c.th_old[3usize] * math.log[f64](par[3usize]) - par[3usize])
        if !(bar - bar == 0.0f64) { bar = 0.0f64 - 1.0f64 / 0.0f64 }
        c.mode = 0usize
        let fv = fit_nll(c, par)
        c.mode = 6usize
        ret fv - 0.0001f64 * bar
    }
    if c.mode == 3usize || c.mode == 4usize || c.mode == 5usize {
        var s3 = 0.0f64
        var c3 = 0.0f64
        var i3 = 0usize
        while i3 < n {
            var v = 0.0f64
            if c.mode == 3usize { v = nm.dcauchy(c.x[i3], par[0usize], par[1usize], true) }
            if c.mode == 4usize { v = nmm.dgamma(c.x[i3], par[0usize], 1.0f64 / (par[1usize] * c.ps2), true) }
            if c.mode == 5usize {
                let ch = math.exp[f64](par[0usize])
                let ps = math.exp[f64](par[1usize])
                let lm = par[2usize]
                let xv = c.x[i3]
                v = lm / 2.0f64 * math.log[f64](math.exp[f64](par[1usize]) / math.exp[f64](par[0usize])) - math.log[f64](2.0f64 * gs.bessel_knu(math.abs[f64](lm), math.sqrt[f64](ch * ps))) + (lm - 1.0f64) * math.log[f64](xv) - 0.5f64 * (ch * (1.0f64 / xv) + ps * xv)
            }
            let t3 = s3 + v
            c3 = c3 + tsum_err(s3, v, t3)
            s3 = t3
            i3 += 1usize
        }
        ret 0.0f64 - (s3 + c3)
    }
    if c.mode == 2usize {
        var s = 0.0f64
        var cs = 0.0f64
        var i = 0usize
        while i < n {
            let t = s + math.log[f64](gh.dskewlap(c.x[i], par[0usize], par[1usize], par[2usize]))
            cs = cs + tsum_err(s, math.log[f64](gh.dskewlap(c.x[i], par[0usize], par[1usize], par[2usize])), t)
            s = t
            i += 1usize
        }
        ret 0.0f64 - (s + cs)
    }
    if c.mode == 1usize {
        let start = mem.mark(c.a)
        let delta = math.exp[f64](par[1usize])
        let zeta = math.exp[f64](par[3usize])
        var ab: [2]f64 = zero
        gm.hyperb_change_pars(1usize, 2usize, delta, par[2usize], zeta, ab[0usize..2usize])
        let lam = fit_lambda(c.fam)
        let d1 = gh.ghyp_mean(par[0usize], delta, ab[0usize], ab[1usize], lam) - c.m_mean
        let v = gh.ghyp_mom(c.a, 2usize, par[0usize], delta, ab[0usize], ab[1usize], lam, 1usize)
        let d2 = v - c.m_var
        let d3 = gh.ghyp_skew(c.a, par[0usize], delta, ab[0usize], ab[1usize], lam) - c.m_skew
        let d4 = gh.ghyp_kurt(c.a, par[0usize], delta, ab[0usize], ab[1usize], lam) - c.m_kurt
        mem.reset(c.a, start)
        ret d1 * d1 + d2 * d2 + d3 * d3 + d4 * d4
    }
    var mu = par[0usize]
    var delta = par[1usize]
    let pi_ = par[2usize]
    var zeta = par[3usize]
    if c.raw {
        if c.fam == 0usize && (par[0usize] <= c.eps || par[3usize] <= c.eps) { ret 1.0e99f64 }
    } else {
        delta = math.exp[f64](par[1usize])
        zeta = math.exp[f64](par[3usize])
    }
    let sq = math.sqrt[f64](1.0f64 + pi_ * pi_)
    var s = 0.0f64
    var cs = 0.0f64
    var i = 0usize
    if c.fam == 0usize {
        let kn = gs.bessel_knu(1.0f64, zeta)
        while i < n {
            let d = (c.x[i] - mu) / delta
            let dens = (1.0f64 / (2.0f64 * delta * sq * kn)) * math.exp[f64]((0.0f64 - zeta) * (sq * math.sqrt[f64](1.0f64 + d * d) - pi_ * (c.x[i] - mu) / delta))
            let lg = math.log[f64](dens)
            let t = s + lg
            cs = cs + tsum_err(s, lg, t)
            s = t
            i += 1usize
        }
        ret 0.0f64 - (s + cs)
    }
    let kn = gs.bessel_knu(0.5f64, zeta)
    while i < n {
        let dx = c.x[i] - mu
        let r = math.sqrt[f64](delta * delta + dx * dx)
        let k2 = gs.bessel_knu(1.0f64, (zeta * sq / delta) * r)
        let dens = sq * math.pow[f64](zeta, 0.5f64) * math.pow[f64](math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64) * kn, 0.0f64 - 1.0f64) * math.pow[f64](delta * delta + dx * dx, 0.0f64 - 0.5f64) * k2 * math.exp[f64]((zeta * pi_ / delta) * dx)
        let lg = math.log[f64](dens)
        let t = s + lg
        cs = cs + tsum_err(s, lg, t)
        s = t
        i += 1usize
    }
    ret 0.0f64 - (s + cs)
}

// the rounding error of t = s + x (Neumaier): R's sum() accumulates in long double, which the compensated sum reproduces to the last bit in practice
fn tsum_err(s: f64, x: f64, t: f64) -> f64 {
    if math.abs[f64](s) >= math.abs[f64](x) { ret (s - t) + x }
    ret (x - t) + s
}

// optim's numerical gradient (ndeps = 1e-3, central differences)
fn fit_grad(c: *FitC, par: []const f64, g: []f64) {
    let was = c.counting
    c.counting = false
    let n = par.len
    var xx: [8]f64 = zero
    var i = 0usize
    while i < n {
        xx[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        xx[i] = par[i] + 0.001f64
        let v1 = fit_nll(c, xx[0usize..n])
        xx[i] = par[i] - 0.001f64
        let v2 = fit_nll(c, xx[0usize..n])
        g[i] = (v1 - v2) / 0.002f64
        xx[i] = par[i]
        i += 1usize
    }
    c.counting = was
}

fn fit_grad_count(c: *FitC, par: []const f64, g: []f64) {
    c.ngr += 1usize
    fit_grad(c, par, g)
}

// optim over c's criterion from start (n parameters): method 0 Nelder-Mead (maxit given), 1 BFGS, 2 L-BFGS-B with lower bounds lo; returns (value, function count, convergence)
fn fit_optim(a: *mem.Arena, c: *FitC, start: []const f64, method: usize, maxit: usize, lo: []const f64, out: []f64) -> (f64, usize, i64) {
    let n = start.len
    if method == 0usize {
        c.counting = false
        let (fv, cnt, fl) = rn.nmmin[FitC](a, c, fit_nll, start, 0.0f64 - 1.0f64 / 0.0f64, 0.0000000149011611938f64, 1.0f64, 0.5f64, 2.0f64, maxit, 1.0f64, out)
        ret (fv, cnt, i64(fl))
    }
    var i = 0usize
    while i < n {
        out[i] = start[i]
        i += 1usize
    }
    c.nfn = 0usize
    c.ngr = 0usize
    if method == 1usize {
        c.counting = true
        let fv = bf.vmmin[FitC](a, c, fit_nll, fit_grad_count, out, 0.0000000149011611938f64, maxit)
        c.counting = false
        var cv = 0i64
        if c.ngr >= maxit { cv = 1i64 }
        ret (fv, c.nfn, cv)
    }
    var up: [8]f64 = zero
    i = 0usize
    while i < n {
        up[i] = 1.0e300f64 * 10.0f64
        i += 1usize
    }
    c.counting = true
    let (fv, fl) = lb.lbfgsb[FitC](a, c, fit_nll, fit_grad_count, out, lo, up[0usize..n], 10000000.0f64, 0.0f64, 5usize, maxit)
    c.counting = false
    ret (fv, c.nfn, fl)
}

// ---- sample statistics as the package takes them (mean with R's second pass, sd, skewness and kurtosis of DistributionUtils)
fn smean(x: []const f64) -> f64 { ret ci.mean_of(x) }

fn svar(x: []const f64) -> f64 {
    let m = smean(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

fn sskew(x: []const f64) -> f64 {
    let m = smean(x)
    let sd = math.sqrt[f64](svar(x))
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / (f64(x.len) * sd * sd * sd)
}

fn skurt(x: []const f64) -> f64 {
    let m = smean(x)
    let v = svar(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        let d = (x[i] - m) * (x[i] - m)
        s += d * d
        i += 1usize
    }
    ret s / (f64(x.len) * v * v) - 3.0f64
}

fn smedian(a: *mem.Arena, x: []const f64) -> f64 {
    let (s, e) = ci.sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = s.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

// ---- hist(x, right = FALSE) with Sturges breaks: pretty(range(x), nclass, min.n = 1), counts on the fuzzed breaks; the density is NaN where the count is zero (the
// package's empDens). Returns the number of cells; breaks has nb + 1 entries, mids and dens nb.
fn fit_hist(a: *mem.Arena, x: []const f64, mids: *[]f64, dens: *[]f64) -> usize {
    let n = x.len
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let nclass = i64(math.ceil[f64](math.log2[f64](f64(n)) + 1.0f64))
    let (br, e) = sc.pretty(a, lo, hi, nclass)
    if e != ok { ret 0usize }
    let nb = br.len - 1usize
    var diddle = 0.0f64
    if nb + 1usize > 5usize {
        let (dd, e2) = mem.alloc[f64](a, nb)
        if e2 != ok { ret 0usize }
        i = 0usize
        while i < nb {
            dd[i] = br[i + 1usize] - br[i]
            i += 1usize
        }
        diddle = 0.0000001f64 * smedian(a, dd)
    } else if nb + 1usize <= 3usize {
        diddle = 0.0000001f64 * (hi - lo)
    } else {
        var mn = br[1usize] - br[0usize]
        i = 1usize
        while i < nb {
            if br[i + 1usize] - br[i] < mn { mn = br[i + 1usize] - br[i] }
            i += 1usize
        }
        diddle = 0.0000001f64 * mn
    }
    let (fb, e3) = mem.alloc[f64](a, nb + 1usize)
    let (cnt, e4) = mem.alloc[f64](a, nb)
    let (md, e5) = mem.alloc[f64](a, nb)
    let (dn, e6) = mem.alloc[f64](a, nb)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0usize }
    i = 0usize
    while i < nb {
        fb[i] = br[i] - diddle
        cnt[i] = 0.0f64
        i += 1usize
    }
    fb[nb] = br[nb] + diddle
    i = 0usize
    while i < n {
        var k = 0usize
        while k < nb {
            if x[i] >= fb[k] && x[i] < fb[k + 1usize] {
                cnt[k] += 1.0f64
                break
            }
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nb {
        md[i] = 0.5f64 * (br[i] + br[i + 1usize])
        let d = cnt[i] / (f64(n) * (br[i + 1usize] - br[i]))
        dn[i] = d
        if !(d > 0.0f64) { dn[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    *mids = md
    *dens = dn
    ret nb
}

// coefficients (intercept, slope) of lm(log(dens)[lo..hi] ~ mids[lo..hi]) over the cells whose density is not NA; the count of usable cells is returned
fn fit_lm(mids: []const f64, dens: []const f64, lo: usize, hi: usize, coef: []f64) -> usize {
    var k = 0usize
    var sx = 0.0f64
    var sy = 0.0f64
    var i = lo
    while i <= hi {
        if dens[i] == dens[i] {
            sx += mids[i]
            sy += math.log[f64](dens[i])
            k += 1usize
        }
        i += 1usize
    }
    if k < 2usize { ret k }
    let mx = sx / f64(k)
    let my = sy / f64(k)
    var sxx = 0.0f64
    var sxy = 0.0f64
    i = lo
    while i <= hi {
        if dens[i] == dens[i] {
            sxx += (mids[i] - mx) * (mids[i] - mx)
            sxy += (mids[i] - mx) * (math.log[f64](dens[i]) - my)
        }
        i += 1usize
    }
    coef[1usize] = sxy / sxx
    coef[0usize] = my - coef[1usize] * mx
    ret k
}

// the start values (normal scale: mu, delta, alpha, beta) of hyperbFitStart / nigFitStart: kind 0 BN, 1 US, 2 FN, 3 SL, 4 MoM; start_method 0 Nelder-Mead / 1 BFGS
fn fit_start(a: *mem.Arena, c: *FitC, kind: usize, start_method: usize, us: []const f64, out: []f64) -> bool {
    let x = c.x
    var mids: []f64 = zero
    var dens: []f64 = zero
    let nb = fit_hist(a, x, &mids, &dens)
    if nb == 0usize { ret false }
    var mi = 0usize
    var best = 0.0f64 - 1.0e300f64
    var i = 0usize
    var dmax = 0.0f64 - 1.0e300f64
    while i < nb {
        if dens[i] == dens[i] {
            if dens[i] >= best {
                best = dens[i]
                mi = i
            }
            if dens[i] > dmax { dmax = dens[i] }
        }
        i += 1usize
    }
    let nan = 0.0f64 / 0.0f64
    var l: [2]f64 = zero
    var r: [2]f64 = zero
    l[0usize] = nan
    l[1usize] = nan
    r[0usize] = nan
    r[1usize] = nan
    let kl = fit_lm(mids, dens, 0usize, mi, l[0usize..2usize])
    if kl > 1usize {
        r[0usize] = nan
        r[1usize] = 0.0f64 - 10.0f64 * l[1usize]
    }
    let kr = fit_lm(mids, dens, mi, nb - 1usize, r[0usize..2usize])
    if kr > 1usize && kl < 2usize {
        l[0usize] = nan
        l[1usize] = 0.0f64 - 10.0f64 * r[1usize]
    }
    if kind == 1usize {
        i = 0usize
        while i < 4usize {
            out[i] = us[i]
            i += 1usize
        }
        ret true
    }
    if kind == 5usize {
        c.mode = 3usize
        let (srt, se) = ci.sorted_copy(a, x)
        if se != ok { ret false }
        var pc: [2]f64 = zero
        pc[0usize] = smedian(a, x)
        pc[1usize] = (rd.quant7(srt, 0.75f64) - rd.quant7(srt, 0.25f64)) / 2.0f64
        let (bq, e0) = mem.alloc[f64](a, 2usize)
        if e0 != ok { ret false }
        var lo2: [2]f64 = zero
        let (fv, cnt, fl) = fit_optim(a, c, pc[0usize..2usize], 1usize, 100usize, lo2[0usize..2usize], bq)
        c.mode = 0usize
        if fl != 0i64 { ret false }
        out[0usize] = bq[0usize]
        out[1usize] = bq[1usize]
        out[2usize] = 0.1f64
        out[3usize] = 0.0f64
        ret true
    }
    if kind == 2usize {
        let nu = mids[mi]
        let mu = smean(x)
        let delta = math.sqrt[f64](svar(x))
        let pi_ = (nu - mu) / delta
        let zeta = 1.0f64 + pi_ * pi_
        var ab: [2]f64 = zero
        gm.hyperb_change_pars(1usize, 2usize, delta, pi_, zeta, ab[0usize..2usize])
        out[0usize] = mu
        out[1usize] = delta
        out[2usize] = ab[0usize]
        out[3usize] = ab[1usize]
        ret true
    }
    if kind == 0usize || kind == 3usize {
        if kl < 2usize && kr < 2usize { ret false }
    }
    var ab2: [2]f64 = zero
    if kind == 3usize {
        c.mode = 2usize
        var p0: [3]f64 = zero
        p0[0usize] = mids[mi]
        p0[1usize] = math.log[f64](1.0f64 / l[1usize])
        p0[2usize] = math.log[f64](math.abs[f64](1.0f64 / r[1usize]))
        let (bp, e) = mem.alloc[f64](a, 3usize)
        if e != ok { ret false }
        var lo3: [3]f64 = zero
        let (fv, cnt, fl) = fit_optim(a, c, p0[0usize..3usize], start_method, smaxit(start_method), lo3[0usize..3usize], bp)
        if start_method == 1usize {
            // optim's BFGS default maxit is 100
        }
        c.mode = 0usize
        let phi = 1.0f64 / math.exp[f64](bp[1usize])
        let gam = 1.0f64 / math.exp[f64](bp[2usize])
        gm.hyperb_change_pars(3usize, 2usize, 0.1f64, phi, gam, ab2[0usize..2usize])
        out[0usize] = bp[0usize]
        out[1usize] = 0.1f64
        out[2usize] = ab2[0usize]
        out[3usize] = ab2[1usize]
        ret true
    }
    if kind == 4usize {
        c.mode = 1usize
        c.m_mean = smean(x)
        c.m_var = svar(x)
        c.m_skew = sskew(x)
        c.m_kurt = skurt(x)
        var xi = math.sqrt[f64](c.m_kurt / 3.0f64 + 1.0f64)
        var chi = c.m_skew / 3.0f64
        if xi >= 1.0f64 { xi = 0.999f64 }
        if math.abs[f64](chi) > xi {
            if xi < 0.0f64 { chi = xi + 0.001f64 } else { chi = xi - 0.001f64 }
        }
        let pi_ = chi / math.sqrt[f64](xi * xi - chi * chi)
        let zeta = 1.0f64 / (xi * xi) - 1.0f64
        let rho = chi / xi
        let delta = (math.sqrt[f64](1.0f64 + zeta) - 1.0f64) * math.sqrt[f64](1.0f64 - rho * rho)
        let lam = fit_lambda(c.fam)
        let mu = c.m_mean - delta * pi_ * (gs.bessel_knu(lam + 1.0f64, zeta) / gs.bessel_knu(lam, zeta))
        var p0: [4]f64 = zero
        p0[0usize] = mu
        p0[1usize] = math.log[f64](delta)
        p0[2usize] = pi_
        p0[3usize] = math.log[f64](zeta)
        let (bp, e) = mem.alloc[f64](a, 4usize)
        if e != ok { ret false }
        var lo4: [4]f64 = zero
        let (fv, cnt, fl) = fit_optim(a, c, p0[0usize..4usize], start_method, smaxit(start_method), lo4[0usize..4usize], bp)
        c.mode = 0usize
        gm.hyperb_change_pars(1usize, 2usize, math.exp[f64](bp[1usize]), bp[2usize], math.exp[f64](bp[3usize]), ab2[0usize..2usize])
        out[0usize] = bp[0usize]
        out[1usize] = math.exp[f64](bp[1usize])
        out[2usize] = ab2[0usize]
        out[3usize] = ab2[1usize]
        ret true
    }
    // BN
    var phi = 0.001f64
    if l[1usize] > phi { phi = l[1usize] }
    var gam = 0.001f64
    if 0.0f64 - r[1usize] > gam { gam = 0.0f64 - r[1usize] }
    let lmd = math.log[f64](dmax)
    var mu = 0.0f64
    var zeta = 0.0f64
    if l[0usize] == l[0usize] && r[0usize] == r[0usize] {
        mu = 0.0f64 - (l[0usize] - r[0usize]) / (l[1usize] - r[1usize])
        let inter = l[0usize] + mu * l[1usize]
        zeta = inter - lmd
    } else {
        mu = smedian(a, x)
        zeta = mu - lmd
    }
    if zeta <= 0.0f64 { zeta = 0.1f64 }
    var delta = zeta / math.sqrt[f64](phi * gam)
    if delta <= 0.0f64 { delta = 0.001f64 }
    gm.hyperb_change_pars(3usize, 2usize, delta, phi, gam, ab2[0usize..2usize])
    out[0usize] = mu
    out[1usize] = delta
    out[2usize] = ab2[0usize]
    out[3usize] = ab2[1usize]
    ret true
}

// constrOptim(theta, f, NULL, ui, ci) of the package's constrOptim fits: the barrier objective minimised by Nelder-Mead (optim defaults: maxit 500) in an outer loop;
// returns (f at the answer, summed function counts, convergence code)
fn fit_constr(a: *mem.Arena, c: *FitC, start: []const f64, out: []f64) -> (f64, usize, i64) {
    var theta: [4]f64 = zero
    var i = 0usize
    while i < 4usize {
        theta[i] = start[i]
        i += 1usize
    }
    c.mode = 0usize
    c.counting = false
    var obj = fit_nll(c, theta[0usize..4usize])
    c.mode = 6usize
    var r = 0.0f64
    var tot = 0usize
    var conv = 0i64
    var iter = 0usize
    c.th_old[0usize] = theta[0usize]
    c.th_old[1usize] = theta[1usize]
    c.th_old[2usize] = theta[2usize]
    c.th_old[3usize] = theta[3usize]
    r = fit_nll(c, theta[0usize..4usize])
    var obj_old = obj
    var done = false
    var lastv = 0.0f64
    while iter < 100usize && !done {
        iter += 1usize
        obj_old = obj
        let r_old = r
        i = 0usize
        while i < 4usize {
            c.th_old[i] = theta[i]
            i += 1usize
        }
        let (fv, cnt, fl) = rn.nmmin[FitC](a, c, fit_nll, theta[0usize..4usize], 0.0f64 - 1.0f64 / 0.0f64, 0.0000000149011611938f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, out)
        lastv = fv
        r = fv
        if r - r == 0.0f64 && r_old - r_old == 0.0f64 && math.abs[f64](r - r_old) < (0.001f64 + math.abs[f64](r)) * 0.00001f64 { done = true }
        if !done {
            i = 0usize
            while i < 4usize {
                theta[i] = out[i]
                i += 1usize
            }
            tot += cnt
            c.mode = 0usize
            obj = fit_nll(c, theta[0usize..4usize])
            c.mode = 6usize
            if obj > obj_old { done = true }
        }
    }
    if iter == 100usize { conv = 7i64 }
    c.mode = 0usize
    let fin = fit_nll(c, out)
    if obj > obj_old && conv == 0i64 { conv = 11i64 }
    ret (fin, tot, conv)
}

// hyperbFit (fam 0) and nigFit (fam 1): start kind and start_method as fit_start, method 0 Nelder-Mead, 1 BFGS, 2 L-BFGS-B; out[0..4] the fit (mu, delta, alpha,
// beta), out[4] the maximised log-likelihood, out[5] convergence, out[6] iterations (the function count), out[7..11] the start on the normal scale
fn fit_family(a: *mem.Arena, x: []const f64, fam: usize, kind: usize, start_method: usize, method: usize, us: []const f64, out: []f64) -> bool {
    var c: FitC = zero
    c.a = a
    c.x = x
    c.fam = fam
    c.eps = 0.0000000001f64
    var st: [4]f64 = zero
    if !fit_start(a, &c, kind, start_method, us, st[0usize..4usize]) { ret false }
    var pz: [2]f64 = zero
    gm.hyperb_change_pars(2usize, 1usize, st[1usize], st[2usize], st[3usize], pz[0usize..2usize])
    c.raw = method >= 2usize
    var p0: [4]f64 = zero
    p0[0usize] = st[0usize]
    p0[1usize] = st[1usize]
    p0[2usize] = pz[0usize]
    p0[3usize] = pz[1usize]
    if !c.raw {
        p0[1usize] = math.log[f64](st[1usize])
        p0[3usize] = math.log[f64](pz[1usize])
    }
    let (bp, e) = mem.alloc[f64](a, 4usize)
    if e != ok { ret false }
    var lo: [4]f64 = zero
    lo[0usize] = 0.0f64 - 1.0e300f64 * 10.0f64
    lo[2usize] = lo[0usize]
    if fam == 1usize {
        lo[1usize] = 0.01f64
        lo[3usize] = 0.01f64
    }
    c.mode = 0usize
    let maxit = if_method(method)
    var fv = 0.0f64
    var cnt = 0usize
    var fl = 0i64
    if method == 3usize {
        let (fv3, cnt3, fl3) = fit_constr(a, &c, p0[0usize..4usize], bp)
        fv = fv3
        cnt = cnt3
        fl = fl3
    } else {
        let (fv2, cnt2, fl2) = fit_optim(a, &c, p0[0usize..4usize], method, maxit, lo[0usize..4usize], bp)
        fv = fv2
        cnt = cnt2
        fl = fl2
    }
    var d = bp[1usize]
    var z = bp[3usize]
    if !c.raw {
        d = math.exp[f64](bp[1usize])
        z = math.exp[f64](bp[3usize])
    }
    var ab: [2]f64 = zero
    gm.hyperb_change_pars(1usize, 2usize, d, bp[2usize], z, ab[0usize..2usize])
    out[0usize] = bp[0usize]
    out[1usize] = d
    out[2usize] = ab[0usize]
    out[3usize] = ab[1usize]
    out[4usize] = 0.0f64 - fv
    out[5usize] = f64(fl)
    out[6usize] = f64(cnt)
    var sd = p0[1usize]
    var sz = p0[3usize]
    if !c.raw {
        sd = math.exp[f64](p0[1usize])
        sz = math.exp[f64](p0[3usize])
    }
    var sab: [2]f64 = zero
    gm.hyperb_change_pars(1usize, 2usize, sd, p0[2usize], sz, sab[0usize..2usize])
    out[7usize] = p0[0usize]
    out[8usize] = sd
    out[9usize] = sab[0usize]
    out[10usize] = sab[1usize]
    ret true
}

fn if_method(method: usize) -> usize {
    if method == 0usize { ret 1000usize }
    ret 200usize
}

fn smaxit(m: usize) -> usize {
    if m == 0usize { ret 500usize }
    ret 100usize
}
