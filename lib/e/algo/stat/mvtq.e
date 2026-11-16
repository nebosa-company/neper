// R mvtnorm::qmvnorm for the equicoordinate quantile of a centred multivariate normal with a correlation matrix: the local-linear probit search of
// get_quant_loclin (a quasi-binomial-link glm of the Genz-Bretz probabilities against the quantile, with R's weights, stopping rule and new points),
// the start interval of getInt (uniroot of the product of the margins), and pmvnorm re-seeded for every evaluation as qmvnorm's pfct does.
//
// Not here: a mean, sigma input, the t distribution (qmvt), the cauchit link, and the TVPACK/Miwa algorithms.

use e.algo.rand.r as rng
use e.algo.stat.mvt as mvt
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nm
use e.mem

type Fit = struct { b0: f64, b1: f64, c00: f64, c01: f64, c11: f64, disp: f64, df: f64 }

// glm(y ~ x, weights, family = quasi("probit")) by R's IRLS (start mustart = y, epsilon 1e-8, 25 iterations)
fn fitlr(x: []const f64, y: []const f64, w: []const f64) -> Fit {
    let nan = 0.0f64 / 0.0f64
    var fit = Fit { b0: nan, b1: nan, c00: nan, c01: nan, c11: nan, disp: nan, df: 0.0f64 }
    // keep the points with positive weight
    var xs: [4096]f64 = zero
    var ys: [4096]f64 = zero
    var ws: [4096]f64 = zero
    var eta: [4096]f64 = zero
    var mu: [4096]f64 = zero
    var wi: [4096]f64 = zero
    var n = 0usize
    var i = 0usize
    while i < x.len {
        if w[i] > 0.0f64 && n < 4096usize {
            xs[n] = x[i]
            ys[n] = y[i]
            ws[n] = w[i]
            n += 1usize
        }
        i += 1usize
    }
    var devold = 0.0f64
    i = 0usize
    while i < n {
        eta[i] = dist.qnorm(ys[i], 0.0f64, 1.0f64, true, false)
        mu[i] = dist.pnorm(eta[i], 0.0f64, 1.0f64, true, false)
        devold += ws[i] * (ys[i] - mu[i]) * (ys[i] - mu[i])
        i += 1usize
    }
    var iter = 0usize
    var c00 = 0.0f64
    var c01 = 0.0f64
    var c11 = 0.0f64
    while iter < 25usize {
        iter += 1usize
        var s0 = 0.0f64
        var s1 = 0.0f64
        var s2 = 0.0f64
        var t0 = 0.0f64
        var t1 = 0.0f64
        i = 0usize
        while i < n {
            var me = math.exp[f64](0.0f64 - eta[i] * eta[i] / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64)
            if me < 2.220446049250313e-16f64 { me = 2.220446049250313e-16f64 }
            let z = eta[i] + (ys[i] - mu[i]) / me
            let wt = ws[i] * me * me
            wi[i] = wt
            s0 += wt
            s1 += wt * xs[i]
            s2 += wt * xs[i] * xs[i]
            t0 += wt * z
            t1 += wt * xs[i] * z
            i += 1usize
        }
        let det = s0 * s2 - s1 * s1
        fit.b0 = (s2 * t0 - s1 * t1) / det
        fit.b1 = (s0 * t1 - s1 * t0) / det
        c00 = s2 / det
        c01 = 0.0f64 - s1 / det
        c11 = s0 / det
        var dev = 0.0f64
        i = 0usize
        while i < n {
            eta[i] = fit.b0 + fit.b1 * xs[i]
            mu[i] = dist.pnorm(eta[i], 0.0f64, 1.0f64, true, false)
            dev += ws[i] * (ys[i] - mu[i]) * (ys[i] - mu[i])
            i += 1usize
        }
        let done = math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64
        devold = dev
        if done { break }
    }
    var ss = 0.0f64
    i = 0usize
    while i < n {
        var me = math.exp[f64](0.0f64 - eta[i] * eta[i] / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64)
        if me < 2.220446049250313e-16f64 { me = 2.220446049250313e-16f64 }
        let r = (ys[i] - mu[i]) / me
        ss += wi[i] * r * r
        i += 1usize
    }
    fit.df = f64(n) - 2.0f64
    fit.disp = ss / fit.df
    fit.c00 = c00
    fit.c01 = c01
    fit.c11 = c11
    ret fit
}

fn pred(f: Fit, x: f64) -> f64 { ret f.b0 + f.b1 * x }

fn pred_se(f: Fit, x: f64) -> f64 {
    ret math.sqrt[f64]((f.c00 + 2.0f64 * f.c01 * x + f.c11 * x * x) * f.disp)
}

fn wgt(d: f64, small: bool) -> f64 {
    if small { ret 1.0f64 }
    if d < 1.0f64 {
        let t = 1.0f64 - d * d * d
        ret t * t * t
    }
    ret 0.0f64
}

type Ctx = struct { lat: *const mvt.Lat, seed: i64, n: usize, tail: usize, cor: []const f64, a: *mem.Arena }

// pfct(q): pmvnorm of the equicoordinate box for the tail, from the seed's stream; upper-tail returns 1 - P
fn pfct(c: *const Ctx, q: f64) -> f64 {
    let n = c.n
    let (lo, e1) = mem.alloc[f64](c.a, n)
    let (up, e2) = mem.alloc[f64](c.a, n)
    let (infin, e3) = mem.alloc[i64](c.a, n)
    let (zd, e4) = mem.alloc[f64](c.a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        zd[i] = 0.0f64
        if c.tail == 2usize {
            lo[i] = 0.0f64 - math.abs[f64](q)
            up[i] = math.abs[f64](q)
            infin[i] = 2i64
        } else if c.tail == 1usize {
            lo[i] = q
            up[i] = 0.0f64
            infin[i] = 1i64
        } else {
            lo[i] = 0.0f64
            up[i] = q
            infin[i] = 0i64
        }
        i += 1usize
    }
    var g: rng.Rng = zero
    rng.seed(&g, c.seed)
    let (res, re) = mvt.mvtdst(c.a, &g, c.lat, n, 0i64, lo, up, infin, c.cor, zd, 25000i64, 0.001f64, 0.0f64)
    if re != ok { ret 0.0f64 / 0.0f64 }
    if c.tail == 1usize { ret 1.0f64 - res.value }
    ret res.value
}

fn sany(y: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    var v = y
    if v > 1.0f64 - eps { v = 1.0f64 - eps }
    if v < eps { v = eps }
    ret v
}

// the product-of-margins function of getInt for the tail minus p
fn gi_f(tail: usize, n: usize, p: f64, x: f64) -> f64 {
    var m = 0.0f64
    if tail == 2usize { m = dist.pnorm(x, 0.0f64, 1.0f64, true, false) - dist.pnorm(0.0f64 - x, 0.0f64, 1.0f64, true, false) } else if tail == 1usize { m = dist.pnorm(x, 0.0f64, 1.0f64, false, false) } else { m = dist.pnorm(x, 0.0f64, 1.0f64, true, false) }
    var pr = 1.0f64
    var i = 0usize
    while i < n {
        pr = pr * m
        i += 1usize
    }
    ret pr - p
}

// R_zeroin2 for gi_f on [ax, bx] at tolerance eps^0.25
fn gi_root(tail: usize, n: usize, p: f64, ax: f64, bx: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    let tol = math.pow[f64](eps, 0.25f64)
    var a = ax
    var b = bx
    var c = a
    var fa = gi_f(tail, n, p, a)
    var fb = gi_f(tail, n, p, b)
    var fc = fa
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    var maxit = 1001i64
    while maxit > 0i64 {
        maxit -= 1i64
        let prev_step = b - a
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * math.abs[f64](b) + tol / 2.0f64
        var new_step = (c - b) / 2.0f64
        if math.abs[f64](new_step) <= tol_act || fb == 0.0f64 { ret b }
        if math.abs[f64](prev_step) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = c - b
            var pp = 0.0f64
            var q = 0.0f64
            if a == c {
                let t1 = fb / fa
                pp = cb * t1
                q = 1.0f64 - t1
            } else {
                q = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                pp = t2 * (cb * q * (q - t1) - (b - a) * (t1 - 1.0f64))
                q = (q - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if pp > 0.0f64 { q = 0.0f64 - q } else { pp = 0.0f64 - pp }
            if pp < (0.75f64 * cb * q - math.abs[f64](tol_act * q) / 2.0f64) && pp < math.abs[f64](prev_step * q / 2.0f64) { new_step = pp / q }
        }
        if math.abs[f64](new_step) < tol_act {
            if new_step > 0.0f64 { new_step = tol_act } else { new_step = 0.0f64 - tol_act }
        }
        a = b
        fa = fb
        b += new_step
        fb = gi_f(tail, n, p, b)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret b
}

// qmvnorm(p, tail, corr, seed, ptol, maxiter): tail 0 lower, 1 upper, 2 both; returns the quantile and f.quantile (the fitted probability minus p)
fn qmvnorm(a: *mem.Arena, lat: *const mvt.Lat, p0: f64, tail: usize, n: usize, corr: []const f64, seed: i64, ptol: f64, maxiter: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (cl, e0) = mem.alloc[f64](a, n * (n - 1usize) / 2usize)
    if e0 != ok { ret (nan, nan) }
    var k = 0usize
    var i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            cl[k] = corr[j * n + i]
            k += 1usize
            j += 1usize
        }
        i += 1usize
    }
    let ctx = Ctx { lat: lat, seed: seed, n: n, tail: tail, cor: cl, a: a }
    // getInt
    var ub = 0.0f64
    var ilo = 0.0f64 - 10.0f64
    var ihi = 10.0f64
    if tail == 2usize {
        ilo = 0.0f64
        ub = dist.qnorm(1.0f64 - (1.0f64 - p0) / 2.0f64, 0.0f64, 1.0f64, true, false)
    } else if tail == 1usize {
        ub = dist.qnorm(1.0f64 - p0, 0.0f64, 1.0f64, true, false)
    } else {
        ub = dist.qnorm(p0, 0.0f64, 1.0f64, true, false)
    }
    let lb = gi_root(tail, n, p0, ilo, ihi)
    var lo = lb
    var hi = ub
    if ub < lb {
        lo = ub
        hi = lb
    }
    var dif = hi - lo
    if dif < 0.1f64 { dif = 0.1f64 }
    lo = lo - 0.2f64 * dif
    hi = hi + 0.2f64 * dif
    var p = p0
    if tail == 1usize { p = 1.0f64 - p0 }
    var minx = 0.0f64 - 1.0f64 / 0.0f64
    if tail == 2usize { minx = 0.0f64 }
    let (x, e1) = mem.alloc[f64](a, 4usize + maxiter)
    let (y, e2) = mem.alloc[f64](a, 4usize + maxiter)
    let (xest, e3) = mem.alloc[f64](a, 1usize + maxiter)
    let (wv, e4) = mem.alloc[f64](a, 4usize + maxiter)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (nan, nan) }
    x[0usize] = math.max[f64](lo, minx)
    x[1usize] = math.max[f64](hi, minx)
    x[2usize] = math.max[f64]((lo + hi) / 2.0f64, minx)
    i = 0usize
    while i < 3usize {
        y[i] = sany(pfct(&ctx, x[i]))
        i += 1usize
    }
    let ttarg = dist.qnorm(p, 0.0f64, 1.0f64, true, false)
    i = 0usize
    while i < 4usize + maxiter {
        wv[i] = 1.0f64
        i += 1usize
    }
    var fit = fitlr(x[0usize..3usize], y[0usize..3usize], wv[0usize..3usize])
    // y holds probabilities; the glm is fitted to them directly, the link scale is the probit
    xest[0usize] = (ttarg - fit.b0) / fit.b1
    x[3usize] = math.max[f64](xest[0usize], minx)
    y[3usize] = sany(pfct(&ctx, x[3usize]))
    var count = 4usize
    var it = 1usize
    while it <= maxiter {
        var small = 0usize
        i = 0usize
        while i < count {
            let d = math.abs[f64](pred(fit, x[i]) - ttarg)
            if d < 1.0f64 && d > 0.0001f64 { small += 1usize }
            i += 1usize
        }
        i = 0usize
        while i < count {
            let d = math.abs[f64](pred(fit, x[i]) - ttarg)
            wv[i] = wgt(d, small < 3usize)
            i += 1usize
        }
        fit = fitlr(x[0usize..count], y[0usize..count], wv[0usize..count])
        let fe = pred(fit, xest[it - 1usize])
        let se = pred_se(fit, xest[it - 1usize])
        let crit = nm.qt(0.975f64, fit.df, true, false)
        let cond1 = fe + crit * se < ttarg + ptol
        let cond2 = fe - crit * se > ttarg - ptol
        if cond1 && cond2 { break }
        xest[it] = (ttarg - fit.b0) / fit.b1
        let f2 = pred(fit, xest[it])
        let s2 = pred_se(fit, xest[it])
        let xlb = (f2 - s2 - fit.b0) / fit.b1
        let xub = (f2 + s2 - fit.b0) / fit.b1
        x[count] = math.max[f64](xlb, minx)
        x[count + 1usize] = math.max[f64](xub, minx)
        y[count] = sany(pfct(&ctx, x[count]))
        y[count + 1usize] = sany(pfct(&ctx, x[count + 1usize]))
        count += 2usize
        it += 1usize
    }
    if it > maxiter { it = maxiter }
    let fq = dist.pnorm(pred(fit, xest[it - 1usize]), 0.0f64, 1.0f64, true, false)
    ret (xest[it - 1usize], fq - p)
}
