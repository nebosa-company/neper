// R forecast, the Box-Cox part: `box_cox` and `inv_box_cox` (sign-preserving, as forecast::BoxCox and InvBoxCox)
// and `box_cox_lambda_loglik` (BoxCox.lambda(method = "loglik") for a plain numeric series: the profile
// log-likelihood of an intercept-only fit over the grid lower, lower + 0.05, ..., upper, first maximum).
// BoxCox.lambda(method = "guerrero") (R optimize, Brent fmin, on the coefficient of variation of the period-wise sd / mean^(1 - lambda)),
// croston_model (croston, sba and sbj). ets and thetaf are in etsfit.e, Arima in arimafit.e, auto.arima in autoarima.e.
// Not here: tslm trend and season terms. tbats and bats are in batsfit.e, stlf is in stlf.e, ets intervals in etsfc.e.

use e.math
use e.mem

fn box_cox(x: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 { ret math.log[f64](x) }
    var sg = 1.0f64
    if x < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if x == 0.0f64 { sg = 0.0f64 }
    ret (sg * math.pow[f64](math.abs[f64](x), lambda) - 1.0f64) / lambda
}

fn inv_box_cox(x: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 { ret math.exp[f64](x) }
    let xx = x * lambda + 1.0f64
    var sg = 1.0f64
    if xx < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if xx == 0.0f64 { sg = 0.0f64 }
    ret sg * math.pow[f64](math.abs[f64](xx), 1.0f64 / lambda)
}

// the log-likelihood at one lambda of an intercept-only fit to the positive series x
fn bc_loglik(x: []const f64, lam: f64, xdot: f64, logx: []const f64) -> f64 {
    let n = x.len
    var mean = 0.0f64
    var i = 0usize
    var sum = 0.0f64
    // transformed values scaled by xdot^(lam - 1); the residual is the deviation from the mean
    var tot = 0.0f64
    let scale = math.pow[f64](xdot, lam - 1.0f64)
    while i < n {
        var xt = 0.0f64
        if math.abs[f64](lam) > 0.02f64 {
            xt = (math.pow[f64](x[i], lam) - 1.0f64) / lam
        } else {
            let l = logx[i]
            xt = l * (1.0f64 + (lam * l) / 2.0f64 * (1.0f64 + (lam * l) / 3.0f64 * (1.0f64 + (lam * l) / 4.0f64)))
        }
        tot += xt / scale
        i += 1usize
    }
    mean = tot / f64(n)
    i = 0usize
    while i < n {
        var xt = 0.0f64
        if math.abs[f64](lam) > 0.02f64 {
            xt = (math.pow[f64](x[i], lam) - 1.0f64) / lam
        } else {
            let l = logx[i]
            xt = l * (1.0f64 + (lam * l) / 2.0f64 * (1.0f64 + (lam * l) / 3.0f64 * (1.0f64 + (lam * l) / 4.0f64)))
        }
        let r = xt / scale - mean
        sum += r * r
        i += 1usize
    }
    ret 0.0f64 - f64(n) / 2.0f64 * math.log[f64](sum)
}

// logx is a scratch of x.len; lower is raised to 0 by the caller when x has non-positive values
// R's optimize(): Brent's fmin on [ax, bx], tol as in optimize(tol = .Machine$double.eps^0.25); the minimiser
fn brent_fmin[Ctx: type](c: *Ctx, f: fn(*Ctx, f64) -> f64, ax: f64, bx: f64, tol: f64) -> f64 {
    let cc = (3.0f64 - math.sqrt[f64](5.0f64)) * 0.5f64
    let eps0 = math.sqrt[f64](2.220446049250313e-16f64)
    var a = ax
    var b = bx
    var v = a + cc * (b - a)
    var w = v
    var x = v
    var d = 0.0f64
    var e = 0.0f64
    var fx = f(c, x)
    var fv = fx
    var fw = fx
    let tol3 = tol / 3.0f64
    var guard = 0usize
    while guard < 1000usize {
        guard += 1usize
        let xm = (a + b) * 0.5f64
        let tol1 = eps0 * math.abs[f64](x) + tol3
        let t2 = tol1 * 2.0f64
        if math.abs[f64](x - xm) <= t2 - (b - a) * 0.5f64 { break }
        var p = 0.0f64
        var q = 0.0f64
        var r = 0.0f64
        if math.abs[f64](e) > tol1 {
            r = (x - w) * (fx - fv)
            q = (x - v) * (fx - fw)
            p = (x - v) * q - (x - w) * r
            q = (q - r) * 2.0f64
            if q > 0.0f64 { p = 0.0f64 - p } else { q = 0.0f64 - q }
            r = e
            e = d
        }
        var u = 0.0f64
        if math.abs[f64](p) >= math.abs[f64](q * 0.5f64 * r) || p <= q * (a - x) || p >= q * (b - x) {
            if x < xm { e = b - x } else { e = a - x }
            d = cc * e
        } else {
            d = p / q
            u = x + d
            if u - a < t2 || b - u < t2 {
                d = tol1
                if x >= xm { d = 0.0f64 - d }
            }
        }
        if math.abs[f64](d) >= tol1 {
            u = x + d
        } else if d > 0.0f64 {
            u = x + tol1
        } else {
            u = x - tol1
        }
        let fu = f(c, u)
        if fu <= fx {
            if u < x { b = x } else { a = x }
            v = w
            w = x
            x = u
            fv = fw
            fw = fx
            fx = fu
        } else {
            if u < x { a = u } else { b = u }
            if fu <= fw || w == x {
                v = w
                fv = fw
                w = u
                fw = fu
            } else if fu <= fv || v == x || v == w {
                v = u
                fv = fu
            }
        }
    }
    ret x
}

type GuerCtx = struct { x: []const f64, period: usize, nyr: usize, rat: []f64 }

fn sd_of(v: []const f64) -> f64 {
    let n = v.len
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += v[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += (v[i] - mean) * (v[i] - mean)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(n - 1usize))
}

// guer.cv: the coefficient of variation of sd / mean^(1 - lam) over the blocks of the last nyr * period values
fn guer_cv(c: *GuerCtx, lam: f64) -> f64 {
    let n = c.x.len
    let start = n - c.nyr * c.period
    var j = 0usize
    while j < c.nyr {
        let blk = c.x[start + j * c.period..start + (j + 1usize) * c.period]
        var mean = 0.0f64
        var i = 0usize
        while i < c.period {
            mean += blk[i]
            i += 1usize
        }
        mean = mean / f64(c.period)
        c.rat[j] = sd_of(blk) / math.pow[f64](mean, 1.0f64 - lam)
        j += 1usize
    }
    var m2 = 0.0f64
    j = 0usize
    while j < c.nyr {
        m2 += c.rat[j]
        j += 1usize
    }
    m2 = m2 / f64(c.nyr)
    ret sd_of(c.rat[0usize..c.nyr]) / m2
}

// BoxCox.lambda(x, method = "guerrero", lower, upper) for a series of frequency freq (nonseasonal.length 2); work holds at least n / 2 doubles
fn guerrero(x: []const f64, freq: usize, lower: f64, upper: f64, work: []f64) -> f64 {
    var period = freq
    if period < 2usize { period = 2usize }
    var c: GuerCtx = zero
    c.x = x
    c.period = period
    c.nyr = x.len / period
    c.rat = work
    ret brent_fmin[GuerCtx](&c, guer_cv, lower, upper, 1.220703125e-4f64)
}

// croston_model(y, alpha, type): type 0 croston, 1 sba, 2 sbj; fits receives the fitted values (fits[0] is NaN, as in R) and the answer is the
// forecast level (the last fitted value, which for a series ending in a demand is the level before that demand); work holds 2 * (number of non-zero values) doubles. A series with fewer than two non-zero values answers NaN.
fn croston(y: []const f64, alpha: f64, typ: usize, fits: []f64, work: []f64) -> f64 {
    let n = y.len
    var k = 0usize
    var i = 0usize
    while i < n {
        if y[i] != 0.0f64 { k += 1usize }
        i += 1usize
    }
    if k < 2usize { ret 0.0f64 / 0.0f64 }
    let fd = work[0usize..k]
    let fi = work[k..2usize * k]
    var coeff = 1.0f64
    if typ == 1usize { coeff = 1.0f64 - alpha / 2.0f64 }
    if typ == 2usize { coeff = 1.0f64 - alpha / (2.0f64 - alpha) }
    var prev = 0usize
    var at = 0usize
    var ratio = 0.0f64
    i = 0usize
    while i < n {
        fits[i] = ratio
        if y[i] != 0.0f64 {
            let interval = f64(i + 1usize - prev)
            if at == 0usize {
                fd[0usize] = y[i]
                fi[0usize] = interval
            } else {
                fd[at] = fd[at - 1usize] + alpha * (y[i] - fd[at - 1usize])
                fi[at] = fi[at - 1usize] + alpha * (interval - fi[at - 1usize])
            }
            ratio = coeff * fd[at] / fi[at]
            at += 1usize
            prev = i + 1usize
        }
        i += 1usize
    }
    fits[0usize] = 0.0f64 / 0.0f64
    ret fits[n - 1usize]
}

fn box_cox_lambda_loglik(x: []const f64, lower: f64, upper: f64, logx: []f64) -> f64 {
    if x.len <= 2usize { ret 1.0f64 }
    var gm = 0.0f64
    var i = 0usize
    while i < x.len {
        logx[i] = math.log[f64](x[i])
        gm += logx[i]
        i += 1usize
    }
    let xdot = math.exp[f64](gm / f64(x.len))
    let m = usize(math.floor[f64]((upper - lower) / 0.05f64 + 1.0e-10f64))
    var best = lower
    var bestll = 0.0f64
    var k = 0usize
    while k <= m {
        let lam = lower + f64(k) * 0.05f64
        let ll = bc_loglik(x, lam, xdot, logx)
        if k == 0usize || ll > bestll {
            bestll = ll
            best = lam
        }
        k += 1usize
    }
    ret best
}
