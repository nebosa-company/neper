// R GeneralizedHyperbolic hyperbFitStand (the two-parameter fit of the standardised sample with its Freedman-Diaconis histogram start) and hyperblm
// (regression with hyperbolic errors: alternating coefficient and distribution-parameter fits from a hyperbFitStand start), by Nelder-Mead, BFGS,
// L-BFGS-B and constrOptim, the package's llfunc and the package's quirks (the output transform rho = p / (1 + p^2) and the start read as (rho, zeta)).

use e.algo.linalg.decomp as dc
use e.algo.stat.classint as ci
use e.algo.stat.ghyp as gh
use e.algo.stat.ghypfit as gf
use e.algo.stat.ghypmore as gm
use e.algo.stat.gslfns as gs
use e.algo.stat.lbfgsb as lb
use e.algo.stat.nlm as nlmm
use e.algo.stat.nlminb as nlb
use e.algo.stat.rbfgs as bf
use e.algo.stat.rdensity as rd
use e.algo.stat.rnm as rn
use e.math
use e.mem

type StC = struct { a: *mem.Arena, x: []const f64, xm: []const f64, nr: usize, p: usize, mode: usize, raw: bool, bar: bool, nth: usize, pos: [4]f64, th_old: [4]f64, dp: [3]f64, cf: [8]f64, nfn: usize, ngr: usize, counting: bool }

fn nan_() -> f64 { ret 0.0f64 / 0.0f64 }

fn rint_(v: f64) -> f64 {
    var r = math.floor[f64](v + 0.5f64)
    if r - v == 0.5f64 {
        let h = r * 0.5f64
        if math.floor[f64](h) != h { r = r - 1.0f64 }
    }
    ret r
}

// signif(x, digits) as R's fprec
fn signif_(x: f64, digits: i64) -> f64 {
    if x == 0.0f64 || x != x { ret x }
    var sgn = 1.0f64
    var ax = x
    if x < 0.0f64 {
        sgn = 0.0f64 - 1.0f64
        ax = 0.0f64 - x
    }
    let l10 = math.log10[f64](ax)
    let e10 = digits - 1i64 - i64(math.floor[f64](l10))
    if e10 > 0i64 {
        let p10 = math.pow[f64](10.0f64, f64(e10))
        ret sgn * (rint_(ax * p10) / p10)
    }
    let p10 = math.pow[f64](10.0f64, f64(0i64 - e10))
    ret sgn * (rint_(ax / p10) * p10)
}

// grDevices::nclass.FD
fn nclass_fd(a: *mem.Arena, x: []const f64) -> i64 {
    let n = x.len
    let (xs, e) = mem.alloc[f64](a, n)
    if e != ok { ret 1i64 }
    var i = 0usize
    while i < n {
        xs[i] = signif_(x[i], 5i64)
        i += 1usize
    }
    let (srt, e2) = ci.sorted_copy(a, xs)
    if e2 != ok { ret 1i64 }
    var h = 2.0f64 * (rd.quant7(srt, 0.75f64) - rd.quant7(srt, 0.25f64))
    if h == 0.0f64 {
        var al = 0.25f64
        let al_min = 1.0f64 / 512.0f64
        var go = true
        while go {
            al = al / 2.0f64
            if al >= al_min {
                h = (rd.quant7(srt, 1.0f64 - al) - rd.quant7(srt, al)) / (1.0f64 - 2.0f64 * al)
                if h != 0.0f64 { go = false }
            } else {
                go = false
            }
        }
    }
    if h == 0.0f64 { h = 3.5f64 * math.sqrt[f64](gf.svar(xs)) }
    if h > 0.0f64 {
        let rg = srt[n - 1usize] - srt[0usize]
        ret i64(math.ceil[f64](rg / h * math.pow[f64](f64(n), 1.0f64 / 3.0f64)))
    }
    ret 1i64
}

fn hyp_sum(s: f64, cs: f64, lg: f64, so: *f64, co: *f64) {
    let t = s + lg
    *co = cs + gf.tsum_err(s, lg, t)
    *so = t
}

// the negative log-likelihood of the package's llfunc (mode 0 log zeta / 1 raw zeta: the standardised two-parameter fit; 2 the coefficients with the distribution
// parameters in dp; 3 the distribution parameters (delta, pi, zeta) with the coefficients in cf), or its constrOptim barrier form when bar is set
fn st_nll(c: *StC, par: []const f64) -> f64 {
    if c.counting { c.nfn += 1usize }
    if c.bar {
        var i = 0usize
        while i < c.nth {
            if c.pos[i] > 0.0f64 && par[i] < 0.0f64 { ret nan_() }
            i += 1usize
        }
        let big = 1.0e99f64
        var bar = 0.0f64
        i = 0usize
        while i < c.nth {
            if c.pos[i] > 0.0f64 {
                bar = bar + (c.th_old[i] * math.log[f64](par[i]) - par[i])
            } else {
                bar = bar + (big * math.log[f64](big) - 0.0f64)
            }
            i += 1usize
        }
        if !(bar - bar == 0.0f64) { bar = 0.0f64 - 1.0f64 / 0.0f64 }
        c.bar = false
        let fv = st_nll(c, par)
        c.bar = true
        ret fv - 0.0001f64 * bar
    }
    var s = 0.0f64
    var cs = 0.0f64
    var i = 0usize
    if c.mode <= 1usize {
        let p0 = par[0usize]
        var zeta = par[1usize]
        if c.mode == 1usize {
            if par[1usize] <= 0.0000000001f64 { ret 1.0e99f64 }
        } else {
            zeta = math.exp[f64](par[1usize])
        }
        let rho = p0 / math.sqrt[f64](1.0f64 + p0 * p0)
        var sp: [4]f64 = zero
        gm.ghyp_stand_pars(rho, zeta, 1.0f64, sp[0usize..4usize])
        let mu = sp[0usize]
        let delta = sp[1usize]
        let kn = gs.bessel_knu(1.0f64, zeta)
        let sq = math.sqrt[f64](1.0f64 + p0 * p0)
        while i < c.x.len {
            let d = (c.x[i] - mu) / delta
            let dens = (1.0f64 / (2.0f64 * delta * sq * kn)) * math.exp[f64]((0.0f64 - zeta) * (sq * math.sqrt[f64](1.0f64 + d * d) - p0 * (c.x[i] - mu) / delta))
            hyp_sum(s, cs, math.log[f64](dens), &s, &cs)
            i += 1usize
        }
        ret 0.0f64 - (s + cs)
    }
    var d0 = 0.0f64
    var p1 = 0.0f64
    var z2 = 0.0f64
    if c.mode == 2usize {
        d0 = c.dp[0usize]
        p1 = c.dp[1usize]
        z2 = c.dp[2usize]
    } else {
        if par[2usize] <= 0.0000000000000001f64 { ret 1.0e99f64 }
        if par[0usize] <= 0.0000000000000001f64 { ret 1.0e99f64 }
        d0 = par[0usize]
        p1 = par[1usize]
        z2 = par[2usize]
    }
    let kn = gs.bessel_knu(1.0f64, z2)
    let sq = math.sqrt[f64](1.0f64 + p1 * p1)
    while i < c.nr {
        var fit = 0.0f64
        var j = 0usize
        while j < c.p {
            var cj = par[j]
            if c.mode == 3usize { cj = c.cf[j] }
            fit = fit + cj * c.xm[j * c.nr + i]
            j += 1usize
        }
        let r = c.x[i] - fit
        let dens = (1.0f64 / (2.0f64 * d0 * sq * kn)) * math.exp[f64]((0.0f64 - z2) * (sq * math.sqrt[f64](1.0f64 + (r / d0) * (r / d0)) - p1 * (r / d0)))
        hyp_sum(s, cs, math.log[f64](dens), &s, &cs)
        i += 1usize
    }
    ret 0.0f64 - (s + cs)
}

fn st_grad(c: *StC, par: []const f64, g: []f64) {
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
        let v1 = st_nll(c, xx[0usize..n])
        xx[i] = par[i] - 0.001f64
        let v2 = st_nll(c, xx[0usize..n])
        g[i] = (v1 - v2) / 0.002f64
        xx[i] = par[i]
        i += 1usize
    }
    c.counting = was
}

fn st_grad_count(c: *StC, par: []const f64, g: []f64) {
    c.ngr += 1usize
    st_grad(c, par, g)
}

// optim: method 0 Nelder-Mead, 1 BFGS, 2 L-BFGS-B with lower bounds lo; (value, function count, convergence)
fn st_optim(a: *mem.Arena, c: *StC, start: []const f64, method: usize, maxit: usize, lo: []const f64, out: []f64) -> (f64, usize, i64) {
    let n = start.len
    if method == 0usize {
        c.counting = false
        let (fv, cnt, fl) = rn.nmmin[StC](a, c, st_nll, start, 0.0f64 - 1.0f64 / 0.0f64, 0.0000000149011611938f64, 1.0f64, 0.5f64, 2.0f64, maxit, 1.0f64, out)
        ret (fv, cnt, i64(fl))
    }
    var i = 0usize
    while i < n {
        out[i] = start[i]
        i += 1usize
    }
    c.nfn = 0usize
    c.ngr = 0usize
    if method == 5usize {
        // nlminb(start, llfunc, NULL, lower = c(-Inf, 1e-10)): the answer is the PORT convergence (0 on a tolerance) and its function evaluations
        c.counting = false
        var lo5: [2]f64 = zero
        var hi5: [2]f64 = zero
        lo5[0usize] = 0.0f64 - 1.0e300f64 * 10.0f64
        lo5[1usize] = 0.0000000001f64
        hi5[0usize] = 1.0e300f64 * 10.0f64
        hi5[1usize] = 1.0e300f64 * 10.0f64
        let r5 = nlb.nlminb_bounded[StC](a, c, st_nll, st_grad, false, out, start[0usize..0usize], lo5[0usize..2usize], hi5[0usize..2usize])
        var cv5 = 1i64
        if r5.code >= 3i64 && r5.code <= 6i64 { cv5 = 0i64 }
        ret (r5.objective, r5.fevals, cv5)
    }
    if method == 4usize {
        c.counting = false
        let r = nlmm.nlm[StC](a, c, st_nll, out, maxit)
        ret (r.fv, r.iters, r.code)
    }
    if method == 1usize {
        c.counting = true
        let fv = bf.vmmin[StC](a, c, st_nll, st_grad_count, out, 0.0000000149011611938f64, maxit)
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
    let (fv, fl) = lb.lbfgsb[StC](a, c, st_nll, st_grad_count, out, lo, up[0usize..n], 10000000.0f64, 0.0f64, 5usize, maxit)
    c.counting = false
    ret (fv, c.nfn, fl)
}

// constrOptim(theta, f, NULL, ui, ci) with the barrier rows of c.pos; the answer in out, (f at the answer, summed counts, convergence)
fn st_constr(a: *mem.Arena, c: *StC, start: []const f64, out: []f64) -> (f64, usize, i64) {
    let n = start.len
    var theta: [4]f64 = zero
    var i = 0usize
    while i < n {
        theta[i] = start[i]
        i += 1usize
    }
    c.bar = false
    c.counting = false
    c.nth = n
    var obj = st_nll(c, theta[0usize..n])
    c.bar = true
    var r = 0.0f64
    var tot = 0usize
    var conv = 0i64
    var iter = 0usize
    i = 0usize
    while i < n {
        c.th_old[i] = theta[i]
        i += 1usize
    }
    r = st_nll(c, theta[0usize..n])
    var obj_old = obj
    var done = false
    while iter < 100usize && !done {
        iter += 1usize
        obj_old = obj
        let r_old = r
        i = 0usize
        while i < n {
            c.th_old[i] = theta[i]
            i += 1usize
        }
        let (fv, cnt, fl) = rn.nmmin[StC](a, c, st_nll, theta[0usize..n], 0.0f64 - 1.0f64 / 0.0f64, 0.0000000149011611938f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, out)
        r = fv
        if r - r == 0.0f64 && r_old - r_old == 0.0f64 && math.abs[f64](r - r_old) < (0.001f64 + math.abs[f64](r)) * 0.00001f64 { done = true }
        if !done {
            i = 0usize
            while i < n {
                theta[i] = out[i]
                i += 1usize
            }
            tot += cnt
            c.bar = false
            obj = st_nll(c, theta[0usize..n])
            c.bar = true
            if obj > obj_old { done = true }
        }
    }
    if iter == 100usize { conv = 7i64 }
    c.bar = false
    let fin = st_nll(c, out)
    if obj > obj_old && conv == 0i64 { conv = 11i64 }
    ret (fin, tot, conv)
}

// hyperbFitStandStart: start kind 0 BN, 1 US (us = the standardised start, read as (rho, zeta)), 2 MoM; rz is (rho, zeta)
fn stand_start(a: *mem.Arena, xs: []const f64, kind: usize, start_method: usize, us: []const f64, rz: []f64) -> bool {
    var mids: []f64 = zero
    var dens: []f64 = zero
    let nb = gf.fit_hist_n(a, xs, nclass_fd(a, xs), &mids, &dens)
    if nb == 0usize { ret false }
    if kind == 1usize {
        if us[1usize] <= 0.0f64 { ret false }
        rz[0usize] = us[0usize]
        rz[1usize] = us[1usize]
        ret true
    }
    if kind == 2usize {
        var c2: gf.FitC = zero
        c2.a = a
        c2.x = xs
        c2.fam = 0usize
        c2.eps = 0.0000000001f64
        var o4: [4]f64 = zero
        if !gf.fit_start(a, &c2, 4usize, start_method, us, o4[0usize..4usize]) { ret false }
        rz[0usize] = o4[0usize]
        rz[1usize] = o4[1usize]
        ret true
    }
    var mi = 0usize
    var best = 0.0f64 - 1.0e300f64
    var dmax = 0.0f64 - 1.0e300f64
    var i = 0usize
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
    let nan = nan_()
    var l: [2]f64 = zero
    var r: [2]f64 = zero
    l[0usize] = nan
    l[1usize] = nan
    r[0usize] = nan
    r[1usize] = nan
    let kl = gf.fit_lm(mids, dens, 0usize, mi, l[0usize..2usize])
    if kl > 1usize {
        r[0usize] = nan
        r[1usize] = 0.0f64 - 10.0f64 * l[1usize]
    }
    let kr = gf.fit_lm(mids, dens, mi, nb - 1usize, r[0usize..2usize])
    if kr > 1usize && kl < 2usize {
        l[0usize] = nan
        l[1usize] = 0.0f64 - 10.0f64 * r[1usize]
    }
    if kl < 2usize && kr < 2usize { ret false }
    var phi = 0.001f64
    if l[1usize] > phi { phi = l[1usize] }
    var gam = 0.001f64
    if 0.0f64 - r[1usize] > gam { gam = 0.0f64 - r[1usize] }
    let alpha = (phi + gam) / 2.0f64
    let beta = (phi - gam) / 2.0f64
    let lmd = math.log[f64](dmax)
    var zeta = 0.0f64
    if l[0usize] == l[0usize] && r[0usize] == r[0usize] {
        let mu = 0.0f64 - (l[0usize] - r[0usize]) / (l[1usize] - r[1usize])
        let inter = l[0usize] + mu * l[1usize]
        zeta = inter - lmd
    } else {
        let mu = gf.smedian(a, xs)
        zeta = mu - lmd
    }
    if zeta <= 0.0f64 { zeta = 0.1f64 }
    rz[0usize] = beta / alpha
    rz[1usize] = zeta
    ret true
}

// hyperbFitStand: kind 0 BN / 1 US / 2 MoM, start_method 0 NM / 1 BFGS (the MoM start's optim), method 0 Nelder-Mead / 1 BFGS / 2 L-BFGS-B / 3 constrOptim;
// us is the start on the normal scale (mu, delta, alpha, beta). out: 0..4 the fit (mu, delta, alpha, beta), 4 the maximised log-likelihood, 5 convergence,
// 6 iterations (the function count), 7..9 the start (rho, zeta)
fn st_fit(a: *mem.Arena, x: []const f64, kind: usize, start_method: usize, method: usize, us: []const f64, out: []f64) -> bool {
    let n = x.len
    let mx = gf.smean(x)
    let sdx = math.sqrt[f64](gf.svar(x))
    let (xs, e) = mem.alloc[f64](a, n)
    if e != ok { ret false }
    var i = 0usize
    while i < n {
        xs[i] = (x[i] - mx) / sdx
        i += 1usize
    }
    var ust: [4]f64 = zero
    ust[0usize] = us[0usize] - mx
    ust[1usize] = us[1usize] / sdx
    ust[2usize] = sdx * us[2usize]
    ust[3usize] = sdx * us[3usize]
    var rz: [2]f64 = zero
    if !stand_start(a, xs, kind, start_method, ust[0usize..4usize], rz[0usize..2usize]) { ret false }
    var sp: [4]f64 = zero
    gm.ghyp_stand_pars(rz[0usize], rz[1usize], 1.0f64, sp[0usize..4usize])
    var pz: [2]f64 = zero
    gh.ghyp_change_pars(1usize, 5usize, sp[1usize], sp[2usize], sp[3usize], pz[0usize..2usize])
    var c: StC = zero
    c.a = a
    c.x = xs
    c.raw = method == 2usize || method == 3usize || method == 5usize
    c.pos[1usize] = 1.0f64
    var p0: [2]f64 = zero
    p0[0usize] = pz[0usize]
    p0[1usize] = pz[1usize]
    if !c.raw { p0[1usize] = math.log[f64](pz[1usize]) }
    c.mode = 0usize
    if c.raw { c.mode = 1usize }
    let f0 = st_nll(&c, p0[0usize..2usize])
    if !(f0 - f0 == 0.0f64) { ret false }
    let (bp, e2) = mem.alloc[f64](a, 2usize)
    if e2 != ok { ret false }
    var lo: [2]f64 = zero
    lo[0usize] = 0.0f64 - 1.0e300f64 * 10.0f64
    var fv = 0.0f64
    var cnt = 0usize
    var fl = 0i64
    if method == 3usize {
        let (fv3, cnt3, fl3) = st_constr(a, &c, p0[0usize..2usize], bp)
        fv = fv3
        cnt = cnt3
        fl = fl3
    } else {
        var maxit = 200usize
        if method == 0usize { maxit = 1000usize }
        if method == 4usize { maxit = 1500usize }
        let (fv2, cnt2, fl2) = st_optim(a, &c, p0[0usize..2usize], method, maxit, lo[0usize..2usize], bp)
        fv = fv2
        cnt = cnt2
        fl = fl2
    }
    var zt = bp[1usize]
    if !c.raw { zt = math.exp[f64](bp[1usize]) }
    let rho = bp[0usize] / (1.0f64 + bp[0usize] * bp[0usize])
    var sp2: [4]f64 = zero
    gm.ghyp_stand_pars(rho, zt, 1.0f64, sp2[0usize..4usize])
    var res: [4]f64 = zero
    gm.ghyp_scale(a, mx, sdx, sp2[1usize], sp2[2usize], sp2[3usize], 1.0f64, res[0usize..4usize])
    out[0usize] = res[0usize]
    out[1usize] = res[1usize]
    out[2usize] = res[2usize]
    out[3usize] = res[3usize]
    out[4usize] = 0.0f64 - fv
    out[5usize] = f64(fl)
    out[6usize] = f64(cnt)
    out[7usize] = rz[0usize]
    out[8usize] = rz[1usize]
    ret true
}

// hyperblm (formula y ~ columns of x, x an n by p column-major design matrix with its intercept column first): method 0 Nelder-Mead / 1 BFGS for the
// coefficients, the distribution parameters by constrOptim; start_kind and start_method are those of the hyperbFitStand start. out: 0..p the coefficients,
// p..p+4 the distribution parameters (shift, delta, alpha, beta), p+4 the log-likelihood, p+5 convergence, p+6 iterations, p+7..p+11 residsParamStart
fn st_lm(a: *mem.Arena, xm: []const f64, y: []const f64, p: usize, method: usize, start_kind: usize, start_method: usize, maxiter: usize, tol: f64, out: []f64) -> bool {
    let n = y.len
    let (ft, e) = dc.lm_fit(a, xm, n, p, y, 0.0000001f64)
    if e != ok { ret false }
    var us0: [4]f64 = zero
    let (sf, sfe) = mem.alloc[f64](a, 12usize)
    if sfe != ok { ret false }
    var mm = gf.smean(ft.residuals[0usize..n])
    us0[0usize] = mm
    us0[1usize] = math.sqrt[f64](gf.svar(ft.residuals[0usize..n]))
    us0[2usize] = 1.5f64
    us0[3usize] = 0.1f64
    if !st_fit(a, ft.residuals[0usize..n], start_kind, start_method, 3usize, us0[0usize..4usize], sf) { ret false }
    var dp: [3]f64 = zero
    gm.hyperb_change_pars(2usize, 1usize, sf[1usize], sf[2usize], sf[3usize], dp[1usize..3usize])
    dp[0usize] = sf[1usize]
    var coef: [8]f64 = zero
    var j = 0usize
    while j < p {
        coef[j] = ft.coef[j]
        j += 1usize
    }
    coef[0usize] = sf[0usize] + ft.coef[0usize]
    var c: StC = zero
    c.a = a
    c.x = y
    c.xm = xm
    c.nr = n
    c.p = p
    var ratio_coef = 1.0f64
    var ratio_param = 1.0f64
    var iter = 0usize
    var hiter = 0usize
    var bad = false
    var co: [8]f64 = zero
    var dpn: [3]f64 = zero
    var lo0: [8]f64 = zero
    while !bad && hiter < maxiter {
        c.mode = 2usize
        c.dp[0usize] = dp[0usize]
        c.dp[1usize] = dp[1usize]
        c.dp[2usize] = dp[2usize]
        var maxit = 10000usize
        if method == 1usize { maxit = 1000usize }
        let (fvc, cntc, flc) = st_optim(a, &c, coef[0usize..p], method, maxit, lo0[0usize..p], co[0usize..p])
        var mx_ratio = 0.0f64
        j = 0usize
        while j < p {
            let rt = math.abs[f64]((coef[j] - co[j]) / coef[j])
            if rt > mx_ratio || rt != rt { mx_ratio = rt }
            coef[j] = co[j]
            j += 1usize
        }
        ratio_coef = mx_ratio
        c.mode = 3usize
        j = 0usize
        while j < p {
            c.cf[j] = coef[j]
            j += 1usize
        }
        c.pos[0usize] = 1.0f64
        c.pos[1usize] = 0.0f64
        c.pos[2usize] = 1.0f64
        let (fvd, cntd, fld) = st_constr(a, &c, dp[0usize..3usize], dpn[0usize..3usize])
        var mx2 = 0.0f64
        j = 0usize
        while j < 3usize {
            let rt = math.abs[f64]((dp[j] - dpn[j]) / dp[j])
            if rt > mx2 || rt != rt { mx2 = rt }
            dp[j] = dpn[j]
            j += 1usize
        }
        ratio_param = mx2
        iter += 1usize
        if ratio_coef <= tol && ratio_param <= tol {
            hiter = maxiter + 1usize
        } else {
            hiter = iter
        }
    }
    let alpha = dp[2usize] * math.sqrt[f64](1.0f64 + dp[1usize] * dp[1usize]) / dp[0usize]
    let beta = dp[2usize] * dp[1usize] / dp[0usize]
    c.mode = 2usize
    c.dp[0usize] = dp[0usize]
    c.dp[1usize] = dp[1usize]
    c.dp[2usize] = dp[2usize]
    let nl = st_nll(&c, coef[0usize..p])
    var conv = 3i64
    if ratio_coef <= tol && ratio_param <= tol {
        conv = 0i64
    } else if ratio_coef > tol && ratio_param <= tol {
        conv = 1i64
    } else if ratio_coef <= tol && ratio_param > tol {
        conv = 2i64
    }
    // fitted values and residuals, their mean shifts the intercept
    let (rs, re) = mem.alloc[f64](a, n)
    if re != ok { ret false }
    var i = 0usize
    while i < n {
        var fit = 0.0f64
        j = 0usize
        while j < p {
            fit = fit + coef[j] * xm[j * n + i]
            j += 1usize
        }
        rs[i] = y[i] - fit
        i += 1usize
    }
    mm = gf.smean(rs)
    j = 0usize
    while j < p {
        out[j] = coef[j]
        j += 1usize
    }
    out[0usize] = coef[0usize] + mm
    out[p] = 0.0f64 - mm
    out[p + 1usize] = dp[0usize]
    out[p + 2usize] = dp[2usize] * math.sqrt[f64](1.0f64 + dp[1usize] * dp[1usize]) / dp[0usize]
    out[p + 3usize] = beta
    out[p + 4usize] = 0.0f64 - nl
    out[p + 5usize] = f64(conv)
    out[p + 6usize] = f64(iter)
    out[p + 7usize] = sf[0usize]
    out[p + 8usize] = sf[1usize]
    out[p + 9usize] = sf[2usize]
    out[p + 10usize] = sf[3usize]
    ret true
}
