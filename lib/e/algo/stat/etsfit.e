// R forecast::ets for a series without missing values: the 30 exponential smoothing state space models (error A or M,
// trend N, A, M with or without damping, season N, A, M), each fitted as forecast does (the C code of etscalc, the starting
// parameters of initparam, the starting states of initstate with the classical decomposition, the objective of
// EtsTargetFunction with bounds = "both", and R's Nelder-Mead nmmin from rnm.e), the information criteria, and the AICc
// search of ets(model = "ZZZ") with restrict = TRUE; point forecasts from the final state.
//
// Also: forecast.ets point forecasts (class1, class2, class3 and the C path), the class1 and class2 forecast variances, thetaf.
// Not here: (tbats and bats are in batsfit.e; stlf is in stlf.e, class3 and simulated intervals in etsfc.e), user-fixed alpha, beta, gamma, phi, opt.crit other than "lik", bounds other than "both", the Fourier start for a
// series shorter than three seasons, the Holt-Winters fallback for a series of at most npars + 4 values, Box-Cox, missing
// values and constant series. A model that cannot be fitted answers good = false (R's try-error, an infinite criterion).

use e.math
use e.mem
use e.math.dist as dist
use e.algo.stat.rnm as rn
use e.algo.stat.pracma as pr

type EtsFit = struct {
    good: bool, et: usize, tt: usize, st: usize, damped: bool, m: usize, p: usize, n: usize, nparam: usize,
    alpha: f64, beta: f64, gamma: f64, phi: f64,
    loglik: f64, aic: f64, bic: f64, aicc: f64, mse: f64, amse: f64, sigma2: f64,
    init: []f64, fitted: []f64, resid: []f64, states: []f64, fncount: usize
}

type EtsCtx = struct {
    ar: *mem.Arena, y: []const f64, n: usize, nstate: usize, et: usize, tt: usize, st: usize, damped: bool, m: usize,
    lower: []f64, upper: []f64, alpha: f64, beta: f64, gamma: f64, phi: f64,
    stbuf: []f64, e: []f64, fits: []f64, amse: []f64, wk: []f64, nmse: usize, crit: usize
}

fn es_nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }
fn es_inf() -> f64 { ret 1.0e308f64 * 10.0f64 }

fn es_alloc(ar: *mem.Arena, n: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](ar, n + 1usize)
    if e != ok { ret v[0usize..0usize] }
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0.0f64
        i += 1usize
    }
    ret v[0usize..n]
}

// forecast(): h steps (sh 1 reproduces the damping sum of etscalc.c as written, which the amse of ets() uses; sh 2 the textbook sum forecast.ets reports) from the state (l, b, s); s[0] is the newest seasonal state
fn es_forecast(l: f64, b: f64, s: []const f64, m: usize, trend: usize, season: usize, phi: f64, f: []f64, h: usize, sh: usize) {
    var phistar = phi
    var i = 0usize
    while i < h {
        if trend == 0usize {
            f[i] = l
        } else if trend == 1usize {
            f[i] = l + phistar * b
        } else if b < 0.0f64 {
            f[i] = es_nan()
        } else {
            f[i] = l * math.pow[f64](b, phistar)
        }
        var j = i64(m) - 1i64 - i64(i)
        while j < 0i64 { j += i64(m) }
        if season == 1usize {
            f[i] = f[i] + s[usize(j)]
        } else if season == 2usize {
            f[i] = f[i] * s[usize(j)]
        }
        if i + 1usize < h {
            if math.abs[f64](phi - 1.0f64) < 1.0e-10f64 {
                phistar = phistar + 1.0f64
            } else {
                phistar = phistar + math.pow[f64](phi, f64(i + sh))
            }
        }
        i += 1usize
    }
}

// update(): the new (level, growth) and the shifted seasonal states s
fn es_update(oldl: f64, oldb: f64, olds: []const f64, s: []f64, m: usize, trend: usize, season: usize, alpha: f64, beta: f64, gamma: f64, phi: f64, y: f64) -> (f64, f64) {
    var q = 0.0f64
    var phib = 0.0f64
    if trend == 0usize {
        q = oldl
        phib = 0.0f64
    } else if trend == 1usize {
        phib = phi * oldb
        q = oldl + phib
    } else if math.abs[f64](phi - 1.0f64) < 1.0e-10f64 {
        phib = oldb
        q = oldl * oldb
    } else {
        phib = math.pow[f64](oldb, phi)
        q = oldl * phib
    }
    var p = 0.0f64
    if y != y {
        p = q
    } else if season == 0usize {
        p = y
    } else if season == 1usize {
        p = y - olds[m - 1usize]
    } else if math.abs[f64](olds[m - 1usize]) < 1.0e-10f64 {
        p = 1.0e10f64
    } else {
        p = y / olds[m - 1usize]
    }
    let l = q + alpha * (p - q)
    var b = 0.0f64
    if trend > 0usize {
        var r = 0.0f64
        if trend == 1usize {
            r = l - oldl
        } else if math.abs[f64](oldl) < 1.0e-10f64 {
            r = 1.0e10f64
        } else {
            r = l / oldl
        }
        b = phib + (beta / alpha) * (r - phib)
    }
    if season > 0usize {
        var t = 0.0f64
        if y != y {
            t = olds[m - 1usize]
        } else if season == 1usize {
            t = y - q
        } else if math.abs[f64](q) < 1.0e-10f64 {
            t = 1.0e10f64
        } else {
            t = y / q
        }
        s[0usize] = olds[m - 1usize] + gamma * (t - olds[m - 1usize])
        var k = 1usize
        while k < m {
            s[k] = olds[k - 1usize]
            k += 1usize
        }
    }
    ret (l, b)
}

// etscalc_internal: x holds the initial state and receives every state row; wk is 108 doubles of scratch;
// the answer is lik (NaN where R has NA)
fn es_calc(y: []const f64, x: []f64, m0: usize, ec: usize, trend: usize, season: usize, alpha: f64, beta: f64, gamma: f64, phi: f64, e: []f64, fits: []f64, amse: []f64, nmse0: usize, wk: []f64) -> f64 {
    var m = m0
    if m < 1usize { m = 1usize }
    var nmse = nmse0
    if nmse > 30usize { nmse = 30usize }
    let n = y.len
    var nstates = 1usize
    if trend > 0usize { nstates += 1usize }
    if season > 0usize { nstates += m }
    let s = wk[0usize..24usize]
    let olds = wk[24usize..48usize]
    let f = wk[48usize..78usize]
    let denom = wk[78usize..108usize]
    var l = x[0usize]
    var b = 0.0f64
    var off = 1usize
    if trend > 0usize {
        b = x[1usize]
        off = 2usize
    }
    if season > 0usize {
        var k = 0usize
        while k < m {
            s[k] = x[off + k]
            k += 1usize
        }
    }
    var lik = 0.0f64
    var lik2 = 0.0f64
    var j = 0usize
    while j < nmse {
        amse[j] = 0.0f64
        denom[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        let oldl = l
        let oldb = b
        if season > 0usize {
            var k = 0usize
            while k < m {
                olds[k] = s[k]
                k += 1usize
            }
        }
        es_forecast(oldl, oldb, olds, m, trend, season, phi, f, nmse, 1usize)
        fits[i] = f[0usize]
        if fits[i] != fits[i] { ret es_nan() }
        if y[i] != y[i] {
            e[i] = es_nan()
        } else if ec == 1usize {
            e[i] = y[i] - fits[i]
        } else {
            e[i] = (y[i] - fits[i]) / fits[i]
        }
        j = 0usize
        while j < nmse {
            if i + j < n {
                denom[j] += 1.0f64
                var tmp = 0.0f64
                if y[i + j] == y[i + j] { tmp = y[i + j] - f[j] }
                amse[j] = (amse[j] * (denom[j] - 1.0f64) + tmp * tmp) / denom[j]
            }
            j += 1usize
        }
        let (nl, nb) = es_update(oldl, oldb, olds, s, m, trend, season, alpha, beta, gamma, phi, y[i])
        l = nl
        b = nb
        x[nstates * (i + 1usize)] = l
        if trend > 0usize { x[nstates * (i + 1usize) + 1usize] = b }
        if season > 0usize {
            var k = 0usize
            while k < m {
                x[off + nstates * (i + 1usize) + k] = s[k]
                k += 1usize
            }
        }
        if e[i] == e[i] { lik = lik + e[i] * e[i] }
        lik2 += math.log[f64](math.abs[f64](f[0usize]))
        i += 1usize
    }
    lik = f64(n) * math.log[f64](lik)
    if ec == 2usize { lik += 2.0f64 * lik2 }
    ret lik
}

// admissible() of EtsTargetFunction for a model whose smoothing parameters are all free
fn es_admissible(c: *EtsCtx) -> bool {
    let phi = c.phi
    let alpha = c.alpha
    var beta = c.beta
    let gamma = c.gamma
    let m = f64(c.m)
    if phi < 0.0f64 || phi > 1.0f64 + 1.0e-8f64 { ret false }
    if c.st == 0usize {
        if alpha < 1.0f64 - 1.0f64 / phi || alpha > 1.0f64 + 1.0f64 / phi { ret false }
        if c.tt != 0usize {
            if beta < alpha * (phi - 1.0f64) || beta > (1.0f64 + phi) * (2.0f64 - alpha) { ret false }
        }
    } else if c.m > 1usize {
        if c.tt == 0usize { beta = 0.0f64 }
        var d = 1.0f64 - 1.0f64 / phi - alpha
        if d < 0.0f64 { d = 0.0f64 }
        if gamma < d || gamma > 1.0f64 + 1.0f64 / phi - alpha { ret false }
        if alpha < 1.0f64 - 1.0f64 / phi - gamma * (1.0f64 - m + phi + phi * m) / (2.0f64 * phi * m) { ret false }
        if beta < 0.0f64 - (1.0f64 - phi) * (gamma / m + alpha) { ret false }
        let deg = c.m + 1usize
        let st0 = mem.mark(c.ar)
        let z = es_alloc(c.ar, deg + 1usize)
        let re = es_alloc(c.ar, deg)
        let im = es_alloc(c.ar, deg)
        // opr in decreasing powers: 1, a+b-phi, (m-2) x (a+b-a phi), a+b-a phi+g-1, phi (1-a-g); polyroot wants increasing powers
        z[deg] = 1.0f64
        z[deg - 1usize] = alpha + beta - phi
        var i = 0usize
        while i + 2usize < c.m {
            z[deg - 2usize - i] = alpha + beta - alpha * phi
            i += 1usize
        }
        z[1usize] = alpha + beta - alpha * phi + gamma - 1.0f64
        z[0usize] = phi * (1.0f64 - alpha - gamma)
        let rd = pr.polyroot_c(c.ar, z, re, im)
        var mx = 0.0f64
        if rd >= 0i64 {
            i = 0usize
            while i < usize(rd) {
                let md = math.sqrt[f64](re[i] * re[i] + im[i] * im[i])
                if md > mx { mx = md }
                i += 1usize
            }
        }
        mem.reset(c.ar, st0)
        if mx > 1.0f64 + 1.0e-10f64 { ret false }
    }
    ret true
}

fn es_check(c: *EtsCtx) -> bool {
    if c.alpha < c.lower[0usize] || c.alpha > c.upper[0usize] { ret false }
    if c.tt != 0usize {
        if c.beta < c.lower[1usize] || c.beta > c.alpha || c.beta > c.upper[1usize] { ret false }
    }
    if c.damped {
        if c.phi < c.lower[3usize] || c.phi > c.upper[3usize] { ret false }
    }
    if c.st != 0usize {
        if c.gamma < c.lower[2usize] || c.gamma > 1.0f64 - c.alpha || c.gamma > c.upper[2usize] { ret false }
    }
    ret es_admissible(c)
}

// the state vector of a parameter vector: the free states and, for a seasonal model, the last seasonal state; false when the states are refused
fn es_states(c: *EtsCtx, par: []const f64) -> bool {
    let np = par.len
    var i = 0usize
    while i < c.nstate {
        c.stbuf[i] = par[np - c.nstate + i]
        i += 1usize
    }
    if c.st != 0usize {
        var start = 1usize
        if c.tt != 0usize { start = 2usize }
        var sum = 0.0f64
        i = start
        while i < c.nstate {
            sum += c.stbuf[i]
            i += 1usize
        }
        var ex = 0.0f64
        if c.st == 2usize { ex = f64(c.m) }
        c.stbuf[c.nstate] = ex - sum
        if c.st == 2usize {
            i = start
            while i <= c.nstate {
                if c.stbuf[i] < 0.0f64 { ret false }
                i += 1usize
            }
        }
    }
    ret true
}

fn es_obj(c: *EtsCtx, par: []const f64) -> f64 {
    var j = 0usize
    c.alpha = par[j]
    j += 1usize
    if c.tt != 0usize {
        c.beta = par[j]
        j += 1usize
    }
    if c.st != 0usize {
        c.gamma = par[j]
        j += 1usize
    }
    if c.damped {
        c.phi = par[j]
        j += 1usize
    }
    if !es_check(c) { ret es_inf() }
    if !es_states(c, par) { ret es_inf() }
    var lik = es_calc(c.y, c.stbuf, c.m, c.et, c.tt, c.st, c.alpha, c.beta, c.gamma, c.phi, c.e, c.fits, c.amse, c.nmse, c.wk)
    if lik < 0.0f64 - 1.0e10f64 { lik = 0.0f64 - 1.0e10f64 }
    if lik != lik { lik = es_inf() }
    if math.abs[f64](lik + 99999.0f64) < 1.0e-7f64 { lik = es_inf() }
    if c.crit == 1usize { ret c.amse[0usize] }
    ret lik
}

fn es_mean(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i]
        i += 1usize
    }
    ret s / f64(v.len)
}

// stats::decompose(ts(y, frequency = m), type)$seasonal for a series that starts at the first position of a cycle
fn es_decompose(ar: *mem.Arena, y: []const f64, m: usize, mult: bool) -> []f64 {
    let l = y.len
    let trend = es_alloc(ar, l)
    let filt = es_alloc(ar, m + 1usize)
    var nf = m
    let fm = f64(m)
    if m % 2usize == 0usize {
        nf = m + 1usize
        filt[0usize] = 0.5f64 / fm
        var k = 1usize
        while k < m {
            filt[k] = 1.0f64 / fm
            k += 1usize
        }
        filt[m] = 0.5f64 / fm
    } else {
        var k = 0usize
        while k < m {
            filt[k] = 1.0f64 / fm
            k += 1usize
        }
    }
    let o = nf / 2usize
    var i = 0usize
    while i < l {
        if i + o + 1usize < nf || i + o >= l {
            trend[i] = es_nan()
        } else {
            var z = 0.0f64
            var j = 0usize
            while j < nf {
                z += filt[j] * y[i + o - j]
                j += 1usize
            }
            trend[i] = z
        }
        i += 1usize
    }
    let season = es_alloc(ar, l)
    i = 0usize
    while i < l {
        if mult { season[i] = y[i] / trend[i] } else { season[i] = y[i] - trend[i] }
        i += 1usize
    }
    let fig = es_alloc(ar, m)
    var k = 0usize
    while k < m {
        var s = 0.0f64
        var cnt = 0usize
        var idx = k
        while idx < l {
            if season[idx] == season[idx] {
                s += season[idx]
                cnt += 1usize
            }
            idx += m
        }
        fig[k] = s / f64(cnt)
        k += 1usize
    }
    let fmn = es_mean(fig)
    k = 0usize
    while k < m {
        if mult { fig[k] = fig[k] / fmn } else { fig[k] = fig[k] - fmn }
        k += 1usize
    }
    let seas = es_alloc(ar, l)
    i = 0usize
    while i < l {
        seas[i] = fig[i % m]
        i += 1usize
    }
    ret seas
}

// initstate(): the starting level, growth and seasonal states (m - 1 of them); ok is false when the series is shorter than three seasons
fn es_initstate(ar: *mem.Arena, y: []const f64, trend: usize, season: usize, m: usize) -> ([]f64, bool) {
    let n = y.len
    let sa = es_alloc(ar, n)
    var nseas = 0usize
    var seas: []f64 = es_alloc(ar, 0usize)
    var iseas: []f64 = es_alloc(ar, 0usize)
    if season != 0usize {
        if n < 3usize * m { ret (iseas, false) }
        seas = es_decompose(ar, y, m, season == 2usize)
        nseas = m - 1usize
        iseas = es_alloc(ar, nseas)
        var k = 0usize
        while k < nseas {
            iseas[k] = seas[m - 1usize - k]
            k += 1usize
        }
        var i = 0usize
        if season == 1usize {
            while i < n {
                sa[i] = y[i] - seas[i]
                i += 1usize
            }
        } else {
            var sum = 0.0f64
            k = 0usize
            while k < nseas {
                if iseas[k] < 0.01f64 { iseas[k] = 0.01f64 }
                sum += iseas[k]
                k += 1usize
            }
            if sum > f64(m) {
                var den = 0.0f64
                k = 0usize
                while k < nseas {
                    den += iseas[k] + 0.01f64
                    k += 1usize
                }
                k = 0usize
                while k < nseas {
                    iseas[k] = iseas[k] / den
                    k += 1usize
                }
            }
            while i < n {
                var sv = seas[i]
                if sv < 0.01f64 { sv = 0.01f64 }
                sa[i] = y[i] / sv
                i += 1usize
            }
        }
    } else {
        var i = 0usize
        while i < n {
            sa[i] = y[i]
            i += 1usize
        }
    }
    var mm = m
    if season == 0usize { mm = 1usize }
    var maxn = 2usize * mm
    if maxn < 10usize { maxn = 10usize }
    if maxn > n { maxn = n }
    var nout = 1usize + nseas
    if trend != 0usize { nout += 1usize }
    let out = es_alloc(ar, nout)
    var l0 = 0.0f64
    var b0 = 0.0f64
    if trend == 0usize {
        l0 = es_mean(sa[0usize..maxn])
    } else {
        let xb = f64(maxn + 1usize) / 2.0f64
        var yb = 0.0f64
        var i = 0usize
        while i < maxn {
            yb += sa[i]
            i += 1usize
        }
        yb = yb / f64(maxn)
        var sxy = 0.0f64
        var sxx = 0.0f64
        i = 0usize
        while i < maxn {
            let dx = f64(i + 1usize) - xb
            sxy += dx * (sa[i] - yb)
            sxx += dx * dx
            i += 1usize
        }
        let c1 = sxy / sxx
        let c0 = yb - c1 * xb
        if trend == 1usize {
            l0 = c0
            b0 = c1
            if math.abs[f64](l0 + b0) < 1.0e-8f64 {
                l0 = l0 * (1.0f64 + 1.0e-3f64)
                b0 = b0 * (1.0f64 - 1.0e-3f64)
            }
        } else {
            l0 = c0 + c1
            if math.abs[f64](l0) < 1.0e-8f64 { l0 = 1.0e-7f64 }
            b0 = (c0 + 2.0f64 * c1) / l0
            l0 = l0 / b0
            if math.abs[f64](b0) > 1.0e10f64 {
                if b0 < 0.0f64 { b0 = 0.0f64 - 1.0e10f64 } else { b0 = 1.0e10f64 }
            }
            if l0 < 1.0e-8f64 || b0 < 1.0e-8f64 {
                l0 = sa[0usize]
                if l0 < 1.0e-3f64 { l0 = 1.0e-3f64 }
                b0 = sa[1usize] / sa[0usize]
                if b0 < 1.0e-3f64 { b0 = 1.0e-3f64 }
            }
        }
    }
    out[0usize] = l0
    var at = 1usize
    if trend != 0usize {
        out[1usize] = b0
        at = 2usize
    }
    var k = 0usize
    while k < nseas {
        out[at + k] = iseas[k]
        k += 1usize
    }
    ret (out, true)
}

fn es_fail(fit: *EtsFit) {
    fit.good = false
    fit.aic = es_inf()
    fit.bic = es_inf()
    fit.aicc = es_inf()
}

// etsmodel() of one model: error et (1 A, 2 M), trend tt, season st (0 N, 1 A, 2 M), damped, seasonal period m1 (used when st > 0)
fn ets_fit(ar: *mem.Arena, y: []const f64, et: usize, tt: usize, st: usize, damped: bool, m1: usize) -> EtsFit {
    let f0 = ets_fit_c(ar, y, et, tt, st, damped, m1, 0usize)
    ret f0
}

// the same with opt.crit: 0 "lik", 1 "mse"
fn ets_fit_c(ar: *mem.Arena, y: []const f64, et: usize, tt: usize, st: usize, damped: bool, m1: usize, crit: usize) -> EtsFit {
    var fit: EtsFit = zero
    fit.good = false
    fit.et = et
    fit.tt = tt
    fit.st = st
    fit.damped = damped
    let n = y.len
    var m = 1usize
    if st != 0usize { m = m1 }
    fit.m = m
    fit.n = n
    es_fail(&fit)
    if st != 0usize && m > 24usize { ret fit }
    let lower = es_alloc(ar, 4usize)
    let upper = es_alloc(ar, 4usize)
    lower[0usize] = 0.0001f64
    lower[1usize] = 0.0001f64
    lower[2usize] = 0.0001f64
    lower[3usize] = 0.8f64
    upper[0usize] = 0.9999f64
    upper[1usize] = 0.9999f64
    upper[2usize] = 0.9999f64
    upper[3usize] = 0.98f64
    // initparam
    var np0 = 1usize
    if tt != 0usize { np0 += 1usize }
    if st != 0usize { np0 += 1usize }
    if damped { np0 += 1usize }
    let (ini, iok) = es_initstate(ar, y, tt, st, m)
    if !iok { ret fit }
    let nstate = ini.len
    let npar = np0 + nstate
    if npar + 1usize >= n { ret fit }
    let par = es_alloc(ar, npar)
    var alpha = lower[0usize] + 0.2f64 * (upper[0usize] - lower[0usize]) / f64(m)
    if alpha > 1.0f64 || alpha < 0.0f64 { alpha = lower[0usize] + 2.0e-3f64 }
    par[0usize] = alpha
    var at = 1usize
    var beta = 0.0f64
    var gamma = 0.0f64
    var phi = 1.0f64
    if tt != 0usize {
        var up1 = upper[1usize]
        if alpha < up1 { up1 = alpha }
        beta = lower[1usize] + 0.1f64 * (up1 - lower[1usize])
        if beta < 0.0f64 || beta > alpha { beta = alpha - 1.0e-3f64 }
        par[at] = beta
        at += 1usize
    }
    if st != 0usize {
        var up2 = upper[2usize]
        if 1.0f64 - alpha < up2 { up2 = 1.0f64 - alpha }
        gamma = lower[2usize] + 0.05f64 * (up2 - lower[2usize])
        if gamma < 0.0f64 || gamma > 1.0f64 - alpha { gamma = 1.0f64 - alpha - 1.0e-3f64 }
        par[at] = gamma
        at += 1usize
    }
    if damped {
        phi = lower[3usize] + 0.99f64 * (upper[3usize] - lower[3usize])
        if phi < 0.0f64 || phi > 1.0f64 { phi = upper[3usize] - 1.0e-3f64 }
        par[at] = phi
        at += 1usize
    }
    var k = 0usize
    while k < nstate {
        par[at + k] = ini[k]
        k += 1usize
    }
    var p = nstate
    if st != 0usize { p += 1usize }
    var c: EtsCtx = zero
    c.ar = ar
    c.y = y
    c.n = n
    c.nstate = nstate
    c.et = et
    c.tt = tt
    c.st = st
    c.damped = damped
    c.m = m
    c.lower = lower
    c.upper = upper
    c.alpha = alpha
    c.beta = beta
    c.gamma = gamma
    c.phi = phi
    c.stbuf = es_alloc(ar, p * (n + 1usize))
    c.e = es_alloc(ar, n)
    c.fits = es_alloc(ar, n)
    c.amse = es_alloc(ar, 30usize)
    c.wk = es_alloc(ar, 108usize)
    c.nmse = 3usize
    c.crit = crit
    // the R-level check.param on the starting values
    if !es_check(&c) { ret fit }
    let best = es_alloc(ar, npar)
    let st1 = mem.mark(ar)
    let (fmin, cnt, fail) = rn.nmmin[EtsCtx](ar, &c, es_obj, par, 0.0f64 - es_inf(), 1.4901161193847656e-8f64, 1.0f64, 0.5f64, 2.0f64, 2000usize, 1.0f64, best)
    mem.reset(ar, st1)
    fit.fncount = cnt
    // final fit
    var j = 0usize
    alpha = best[j]
    j += 1usize
    if tt != 0usize {
        beta = best[j]
        j += 1usize
    }
    if st != 0usize {
        gamma = best[j]
        j += 1usize
    }
    if damped {
        phi = best[j]
        j += 1usize
    }
    fit.alpha = alpha
    fit.beta = beta
    fit.gamma = gamma
    fit.phi = phi
    let ist = es_alloc(ar, p)
    k = 0usize
    while k < nstate {
        ist[k] = best[npar - nstate + k]
        k += 1usize
    }
    if st != 0usize {
        var start = 1usize
        if tt != 0usize { start = 2usize }
        var sum = 0.0f64
        k = start
        while k < nstate {
            sum += ist[k]
            k += 1usize
        }
        var ex = 0.0f64
        if st == 2usize { ex = f64(m) }
        ist[nstate] = ex - sum
    }
    var phiu = phi
    if !damped { phiu = 1.0f64 }
    var betau = beta
    if tt == 0usize { betau = 0.0f64 }
    var gammau = gamma
    if st == 0usize { gammau = 0.0f64 }
    let states = es_alloc(ar, p * (n + 1usize))
    k = 0usize
    while k < p {
        states[k] = ist[k]
        k += 1usize
    }
    let e = es_alloc(ar, n)
    let fits = es_alloc(ar, n)
    let amse = es_alloc(ar, 30usize)
    let lik = es_calc(y, states, m, et, tt, st, alpha, betau, gammau, phiu, e, fits, amse, 3usize, c.wk)
    if lik != lik { ret fit }
    let np = f64(npar + 1usize)
    fit.p = p
    fit.nparam = npar
    fit.loglik = 0.0f64 - 0.5f64 * lik
    fit.aic = lik + 2.0f64 * np
    fit.bic = lik + math.log[f64](f64(n)) * np
    fit.aicc = fit.aic + 2.0f64 * np * (np + 1.0f64) / (f64(n) - np - 1.0f64)
    fit.mse = amse[0usize]
    fit.amse = (amse[0usize] + amse[1usize] + amse[2usize]) / 3.0f64
    var ss = 0.0f64
    k = 0usize
    while k < n {
        ss += e[k] * e[k]
        k += 1usize
    }
    fit.sigma2 = ss / (f64(n) - f64(npar))
    fit.init = ist
    fit.fitted = fits
    fit.resid = e
    fit.states = states
    fit.good = true
    let _ = fmin
    let _ = fail
    ret fit
}

// forecast::thetaf(y, h) (the standard Theta method) for a series of frequency m that starts at the first position of a cycle: the
// point forecasts in mean and the forecast standard errors in se (both h long); false when the ANN fit fails
fn thetaf(ar: *mem.Arena, y: []const f64, m: usize, h: usize, mean: []f64, se: []f64, fitted: []f64) -> bool {
    let n = y.len
    let nf = f64(n)
    var seasonal = false
    var mu = es_mean(y)
    var c0 = 0.0f64
    var i = 0usize
    while i < n {
        c0 += (y[i] - mu) * (y[i] - mu)
        i += 1usize
    }
    if m > 1usize && c0 > 0.0f64 && n > 2usize * m {
        var s2 = 0.0f64
        var rm = 0.0f64
        var k = 1usize
        while k <= m {
            var ck = 0.0f64
            i = k
            while i < n {
                ck += (y[i] - mu) * (y[i - k] - mu)
                i += 1usize
            }
            let rk = ck / c0
            if k < m { s2 += rk * rk } else { rm = rk }
            k += 1usize
        }
        let stat = math.sqrt[f64]((1.0f64 + 2.0f64 * s2) / nf)
        seasonal = math.abs[f64](rm) / stat > dist.qnorm(0.95f64, 0.0f64, 1.0f64, true, false)
    }
    var ysa = y
    var seas: []f64 = es_alloc(ar, 0usize)
    if seasonal {
        seas = es_decompose(ar, y, m, true)
        i = 0usize
        while i < n {
            if math.abs[f64](seas[i]) < 1.0e-4f64 { seasonal = false }
            i += 1usize
        }
    }
    if seasonal {
        let adj = es_alloc(ar, n)
        i = 0usize
        while i < n {
            adj[i] = y[i] / seas[i]
            i += 1usize
        }
        ysa = adj
    }
    let xb = (nf - 1.0f64) / 2.0f64
    mu = es_mean(ysa)
    var sxy = 0.0f64
    var sxx = 0.0f64
    i = 0usize
    while i < n {
        let dx = f64(i) - xb
        sxy += dx * (ysa[i] - mu)
        sxx += dx * dx
        i += 1usize
    }
    let drift = sxy / sxx / 2.0f64
    let fit = ets_fit_c(ar, ysa, 1usize, 0usize, 0usize, false, 1usize, 1usize)
    if !fit.good { ret false }
    var alpha = fit.alpha
    if alpha < 1.0e-10f64 { alpha = 1.0e-10f64 }
    let level = fit.states[fit.p * fit.n]
    let dadj = (1.0f64 - math.pow[f64](1.0f64 - alpha, nf)) / alpha
    i = 0usize
    while i < fitted.len && i < n {
        fitted[i] = fit.fitted[i]
        if seasonal { fitted[i] = fitted[i] * seas[i] }
        i += 1usize
    }
    i = 0usize
    while i < h {
        mean[i] = level + drift * (f64(i) + dadj)
        if seasonal { mean[i] = mean[i] * seas[n - m + i % m] }
        se[i] = math.sqrt[f64](fit.sigma2) * math.sqrt[f64](f64(i) * alpha * alpha + 1.0f64)
        i += 1usize
    }
    ret true
}

// ets(y, model = "ZZZ") with the defaults (ic "aicc", restrict, no multiplicative trend unless asked): the best fit by the criterion
// ic (0 aicc, 1 aic, 2 bic) for a series of period m
fn ets_auto(ar: *mem.Arena, y: []const f64, m: usize, ic: usize, allow_mult_trend: bool) -> EtsFit { ret ets_auto_o(ar, y, m, ic, allow_mult_trend, false) }

// the same with additive.only (set by ets(lambda = ...)): no multiplicative error, trend or season
fn ets_auto_o(ar: *mem.Arena, y: []const f64, m: usize, ic: usize, allow_mult_trend: bool, additive_only: bool) -> EtsFit {
    var best: EtsFit = zero
    best.good = false
    var best_ic = es_inf()
    var minv = y[0usize]
    var i = 0usize
    while i < y.len {
        if y[i] < minv { minv = y[i] }
        i += 1usize
    }
    let positive = minv > 0.0f64
    var ntr = 2usize
    if allow_mult_trend { ntr = 3usize }
    var nse = 1usize
    if m > 1usize && m <= 24usize { nse = 3usize }
    var ei = 1usize
    while ei <= 2usize {
        var ti = 0usize
        while ti < ntr {
            var si = 0usize
            while si < nse {
                var di = 0usize
                while di < 2usize {
                    let damped = di == 0usize
                    var skip = false
                    if ti == 0usize && damped { skip = true }
                    if ei == 1usize && (ti == 2usize || si == 2usize) { skip = true }
                    if ei == 2usize && ti == 2usize && si == 1usize { skip = true }
                    if !positive && ei == 2usize { skip = true }
                    if additive_only && (ei == 2usize || ti == 2usize || si == 2usize) { skip = true }
                    if !skip {
                        let f = ets_fit(ar, y, ei, ti, si, damped, m)
                        var v = f.aicc
                        if ic == 1usize { v = f.aic }
                        if ic == 2usize { v = f.bic }
                        if f.good && v == v && v < best_ic {
                            best = f
                            best_ic = v
                        }
                    }
                    di += 1usize
                }
                si += 1usize
            }
            ti += 1usize
        }
        ei += 1usize
    }
    ret best
}

// forecast.ets point forecasts: etsforecast from the final state
// (forecast.ets: class1 and class2 give the linear forecast, class3 the multiplicative-season mean below, and every other
// model goes through the C etsforecast, whose damping sum is the one of etscalc.c)
fn ets_point(ar: *mem.Arena, fit: *const EtsFit, h: usize, out: []f64) {
    var phiu = fit.phi
    if !fit.damped { phiu = 1.0f64 }
    let last = fit.states[fit.p * fit.n..fit.p * (fit.n + 1usize)]
    var b = 0.0f64
    var off = 1usize
    if fit.tt != 0usize {
        b = last[1usize]
        off = 2usize
    }
    let s = last[off..fit.p]
    var sh = 1usize
    if fit.tt != 2usize && fit.st != 2usize { sh = 2usize }
    if fit.et == 2usize && fit.st == 2usize && fit.tt != 2usize {
        es_class3(ar, fit, phiu, last, h, out)
        ret
    }
    es_forecast(last[0usize], b, s, fit.m, fit.tt, fit.st, phiu, out, h, sh)
}

// forecast.ets prediction variance of class1 (error A, trend N or A, season N or A) and class2 (error M, same trend and season): the
// variance of the h-step forecast in var (h long); false for the other models, whose intervals R simulates
fn ets_var(ar: *mem.Arena, fit: *const EtsFit, h: usize, vr: []f64) -> bool {
    let tt = fit.tt
    let st = fit.st
    if tt == 2usize || st == 2usize { ret false }
    let p = fit.p
    let m = fit.m
    var phiu = fit.phi
    if !fit.damped { phiu = 1.0f64 }
    let last = fit.states[fit.p * fit.n..fit.p * (fit.n + 1usize)]
    let hv = es_alloc(ar, p)
    let fm = es_alloc(ar, p * p)
    let g = es_alloc(ar, p)
    let fj = es_alloc(ar, p * p)
    let tmp = es_alloc(ar, p * p)
    let hf = es_alloc(ar, p)
    let mu = es_alloc(ar, h)
    let cj = es_alloc(ar, h)
    hv[0usize] = 1.0f64
    if st == 1usize { hv[p - 1usize] = 1.0f64 }
    if tt == 1usize { hv[1usize] = phiu }
    fm[0usize] = 1.0f64
    if tt == 1usize {
        fm[1usize] = phiu
        fm[p + 1usize] = phiu
    }
    if st == 1usize {
        fm[(p - m) * p + p - 1usize] = 1.0f64
        var k = 0usize
        while k + 1usize < m {
            fm[(p - m + 1usize + k) * p + p - m + k] = 1.0f64
            k += 1usize
        }
    }
    g[0usize] = fit.alpha
    if tt == 1usize { g[1usize] = fit.beta }
    if st == 1usize { g[2usize] = fit.gamma }
    var i = 0usize
    while i < p {
        fj[i * p + i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < h {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var r = 0usize
            while r < p {
                s += hv[r] * fj[r * p + c]
                r += 1usize
            }
            hf[c] = s
            c += 1usize
        }
        var a1 = 0.0f64
        var a2 = 0.0f64
        c = 0usize
        while c < p {
            a1 += hf[c] * last[c]
            a2 += hf[c] * g[c]
            c += 1usize
        }
        mu[i] = a1
        cj[i] = a2
        // Fj = Fj F
        var r2 = 0usize
        while r2 < p {
            c = 0usize
            while c < p {
                var s = 0.0f64
                var k2 = 0usize
                while k2 < p {
                    s += fj[r2 * p + k2] * fm[k2 * p + c]
                    k2 += 1usize
                }
                tmp[r2 * p + c] = s
                c += 1usize
            }
            r2 += 1usize
        }
        var q = 0usize
        while q < p * p {
            fj[q] = tmp[q]
            q += 1usize
        }
        i += 1usize
    }
    let s2 = fit.sigma2
    if fit.et == 1usize {
        var acc = 0.0f64
        vr[0usize] = s2
        i = 1usize
        while i < h {
            acc += cj[i - 1usize] * cj[i - 1usize]
            vr[i] = s2 * (1.0f64 + acc)
            i += 1usize
        }
    } else {
        let theta = es_alloc(ar, h)
        theta[0usize] = mu[0usize] * mu[0usize]
        var j = 1usize
        while j < h {
            var sm = 0.0f64
            var k3 = 0usize
            while k3 < j {
                sm += cj[k3] * cj[k3] * theta[j - 1usize - k3]
                k3 += 1usize
            }
            theta[j] = mu[j] * mu[j] + s2 * sm
            j += 1usize
        }
        j = 0usize
        while j < h {
            vr[j] = (1.0f64 + s2) * theta[j] - mu[j] * mu[j]
            j += 1usize
        }
    }
    ret true
}

// class3 of forecast.ets: the mean of a multiplicative-error, multiplicative-season model, from Mh = (level, growth) x seasonal states
fn es_class3(ar: *mem.Arena, fit: *const EtsFit, phiu: f64, last: []const f64, h: usize, out: []f64) {
    let m = fit.m
    var rr = 1usize
    if fit.tt != 0usize { rr = 2usize }
    let mh = es_alloc(ar, rr * m)
    let nx = es_alloc(ar, rr * m)
    let xg = es_alloc(ar, rr)
    var r = 0usize
    while r < rr {
        var c = 0usize
        while c < m {
            mh[r * m + c] = last[r] * last[rr + c]
            c += 1usize
        }
        r += 1usize
    }
    let s2 = fit.sigma2
    var i = 0usize
    while i < h {
        var mu = 0.0f64
        r = 0usize
        while r < rr {
            mu += mh[r * m + m - 1usize]
            r += 1usize
        }
        out[i] = mu
        // G1 Mh column m - 1: G1 = alpha (N) or [[a, a], [b, b]]
        if rr == 1usize {
            xg[0usize] = fit.alpha * mh[m - 1usize]
        } else {
            xg[0usize] = fit.alpha * mh[m - 1usize] + fit.alpha * mh[2usize * m - 1usize]
            xg[1usize] = fit.beta * mh[m - 1usize] + fit.beta * mh[2usize * m - 1usize]
        }
        r = 0usize
        while r < rr {
            // F1 Mh row r
            var c = 0usize
            while c < m {
                var f1 = mh[c]
                if rr == 2usize {
                    if r == 0usize { f1 = mh[c] + mh[m + c] } else { f1 = phiu * mh[m + c] }
                }
                nx[r * m + c] = f1
                c += 1usize
            }
            r += 1usize
        }
        // times F2' (column 0 takes the last column, column c the column c - 1), plus sigma2 G1 Mh G2 (column 0 takes G1 Mh column m - 1 times gamma)
        r = 0usize
        while r < rr {
            let row = nx[r * m..r * m + m]
            let last_col = row[m - 1usize]
            var c = m - 1usize
            while c >= 1usize {
                mh[r * m + c] = row[c - 1usize]
                c -= 1usize
            }
            mh[r * m] = last_col
            mh[r * m] = mh[r * m] + s2 * (xg[r] * fit.gamma)
            r += 1usize
        }
        i += 1usize
    }
}
