// R bridgesampling: `bridge_normal`, the bridge sampler with the normal proposal and the iterative scheme
// (r0 = 0.5, tolerance 1e-10 on r, at most maxiter steps) for unconstrained real parameters. The first
// round(n / 2) posterior draws fit the proposal (their mean and covariance), the rest enter the scheme, and
// the proposal draws come from mvtnorm::rmvnorm (the eigen method) under the caller's stream.
//
// And warp3 (bridge_warp3) and bounded real parameters (bridge_bounded: log, reflected log and probit transforms with their Jacobians).
// Not here: simplex and circular parameters, repetitions, the effective-sample-size variant of the error estimate (use_neff = FALSE
// only), error_measures and nearPD (the covariance must be positive definite).

use e.algo.rand.r as rng
use e.algo.sort
use e.algo.stat.mvtnorm as mv
use e.math
use e.math.dist as dist
use e.mem

type Fit = struct { logml: f64, niter: i64, mcse: f64, converged: bool }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn median_of(a: *mem.Arena, v: []const f64) -> f64 {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    let n = v.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

fn mean_var(v: []const f64) -> (f64, f64) {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i]
        i += 1usize
    }
    let m = s / f64(v.len)
    var t = 0.0f64
    var q = 0.0f64
    i = 0usize
    while i < v.len {
        t += v[i] - m
        i += 1usize
    }
    let m2 = m + t / f64(v.len)
    i = 0usize
    while i < v.len {
        q += (v[i] - m2) * (v[i] - m2)
        i += 1usize
    }
    ret (m2, q / f64(v.len - 1usize))
}

// R round to the nearest integer, halves to even
fn round_half_even(x: f64) -> usize {
    let f = math.floor[f64](x)
    let d = x - f
    if d < 0.5f64 { ret usize(f) }
    if d > 0.5f64 { ret usize(f) + 1usize }
    if usize(f) % 2usize == 0usize { ret usize(f) }
    ret usize(f) + 1usize
}

// the iterative scheme on the log densities: l1 = q11 - q12 (posterior draws), l2 = q21 - q22 (proposal draws)
fn iterate(a: *mem.Arena, l1: []const f64, l2: []const f64, r0: f64, tol: f64, maxiter: i64) -> (Fit, err) {
    var none: Fit = zero
    let lstar = median_of(a, l1)
    let n1 = f64(l1.len)
    let n2 = f64(l2.len)
    let neff = n1
    let s1 = neff / (neff + n2)
    let s2 = n2 / (neff + n2)
    var r = r0
    var logml = math.log[f64](r) + lstar
    var crit = 1.0f64 + tol
    var i = 1i64
    var mcse = 0.0f64
    let (numi, ne) = mem.alloc[f64](a, l2.len)
    if ne != ok { ret (none, ne) }
    let (deni, de) = mem.alloc[f64](a, l1.len)
    if de != ok { ret (none, de) }
    while i <= maxiter && crit > tol {
        let rold = r
        var k = 0usize
        while k < l2.len {
            let ex = math.exp[f64](l2[k] - lstar)
            numi[k] = ex / (s1 * ex + s2 * r)
            k += 1usize
        }
        k = 0usize
        while k < l1.len {
            deni[k] = 1.0f64 / (s1 * math.exp[f64](l1[k] - lstar) + s2 * r)
            k += 1usize
        }
        let (mn, vn) = mean_var(numi)
        let (md, vd) = mean_var(deni)
        r = mn / md
        logml = math.log[f64](r) + lstar
        crit = math.abs[f64]((r - rold) / r)
        i += 1i64
        var varr = (mn * mn) / (md * md) * (vn / (mn * mn) + vd / (md * md))
        varr = varr / f64(l2.len)
        mcse = math.sqrt[f64](math.log[f64](1.0f64 + varr / (r * r)))
    }
    if i >= maxiter { ret (Fit { logml: 0.0f64 / 0.0f64, niter: i - 1i64, mcse: mcse, converged: false }, ok) }
    ret (Fit { logml: logml, niter: i - 1i64, mcse: mcse, converged: true }, ok)
}

// bridge_sampler(samples, log_posterior, ..., method = "normal"); logpost(ctx, theta) is the log posterior
fn bridge_normal[Ctx: type](a: *mem.Arena, g: *rng.Rng, ctx: *Ctx, logpost: fn(*Ctx, []const f64) -> f64, samples: []const f64, n: usize, p: usize, maxiter: i64) -> (Fit, err) {
    var none: Fit = zero
    let nfit = round_half_even(f64(n) / 2.0f64)
    let niter_rows = n - nfit
    // mean and covariance of the first nfit rows
    let (m, me) = mem.alloc[f64](a, p)
    let (v, ve) = mem.alloc[f64](a, p * p)
    if me != ok { ret (none, me) }
    if ve != ok { ret (none, ve) }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var i = 0usize
        while i < nfit {
            s += samples[i * p + j]
            i += 1usize
        }
        m[j] = s / f64(nfit)
        j += 1usize
    }
    j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var i = 0usize
            while i < nfit {
                s += (samples[i * p + j] - m[j]) * (samples[i * p + k] - m[k])
                i += 1usize
            }
            v[j * p + k] = s / f64(nfit - 1usize)
            k += 1usize
        }
        j += 1usize
    }
    let it = samples[nfit * p..n * p]
    let (q12, e1) = mem.alloc[f64](a, niter_rows)
    if e1 != ok { ret (none, e1) }
    var i = 0usize
    while i < niter_rows {
        let (d, de) = mv.dmvnorm(a, it[i * p..i * p + p], m, v, p)
        if de != ok { ret (none, de) }
        q12[i] = d
        i += 1usize
    }
    let (gen, ge) = mv.rmvnorm(a, g, niter_rows, m, v, p, 0u8)
    if ge != ok { ret (none, ge) }
    let (q22, e2) = mem.alloc[f64](a, niter_rows)
    let (q11, e3) = mem.alloc[f64](a, niter_rows)
    let (q21, e4) = mem.alloc[f64](a, niter_rows)
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    i = 0usize
    while i < niter_rows {
        let (d, de) = mv.dmvnorm(a, gen[i * p..i * p + p], m, v, p)
        if de != ok { ret (none, de) }
        q22[i] = d
        q11[i] = logpost(ctx, it[i * p..i * p + p])
        q21[i] = logpost(ctx, gen[i * p..i * p + p])
        i += 1usize
    }
    let (l1, l1e) = mem.alloc[f64](a, niter_rows)
    let (l2, l2e) = mem.alloc[f64](a, niter_rows)
    if l1e != ok { ret (none, l1e) }
    if l2e != ok { ret (none, l2e) }
    i = 0usize
    while i < niter_rows {
        l1[i] = q11[i] - q12[i]
        l2[i] = q21[i] - q22[i]
        i += 1usize
    }
    let (fit, fe) = iterate(a, l1, l2, 0.5f64, 1.0e-10f64, maxiter)
    ret (fit, fe)
}

fn bf(logml1: f64, logml2: f64) -> f64 { ret math.exp[f64](logml1 - logml2) }

// post_prob for two models: the softmax of logml + log(prior), subtracting the maximum
fn post_prob2(logml1: f64, logml2: f64, prior1: f64, prior2: f64) -> f64 {
    let a = logml1 + math.log[f64](prior1)
    let b = logml2 + math.log[f64](prior2)
    var m = a
    if b > m { m = b }
    ret math.exp[f64](a - m) / (math.exp[f64](a - m) + math.exp[f64](b - m))
}

// log(exp(a) + exp(b))
fn logaddexp(a: f64, b: f64) -> f64 {
    var m = a
    if b > m { m = b }
    if m == 0.0f64 - 1.0e308f64 * 10.0f64 { ret m }
    ret m + math.log[f64](math.exp[f64](a - m) + math.exp[f64](b - m))
}

// the lower Cholesky factor of v (p by p, row-major) into l; false when v is not positive definite
fn chol_lower(v: []const f64, p: usize, l: []f64) -> bool {
    var i = 0usize
    while i < p * p {
        l[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j <= i {
            var s = v[i * p + j]
            var k = 0usize
            while k < j {
                s -= l[i * p + k] * l[j * p + k]
                k += 1usize
            }
            if i == j {
                if s <= 0.0f64 { ret false }
                l[i * p + i] = math.sqrt[f64](s)
            } else {
                l[i * p + j] = s / l[j * p + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// bridge_sampler(samples, log_posterior, ..., method = "warp3", use_neff = FALSE): the posterior draws and the standard normal draws
// are reflected about the fit mean and scaled by the Cholesky factor of the fit covariance, and the proposal is the standard normal
fn bridge_warp3[Ctx: type](a: *mem.Arena, g: *rng.Rng, ctx: *Ctx, logpost: fn(*Ctx, []const f64) -> f64, samples: []const f64, n: usize, p: usize, maxiter: i64) -> (Fit, err) {
    var none: Fit = zero
    let nfit = round_half_even(f64(n) / 2.0f64)
    let nit = n - nfit
    let (m, e1) = mem.alloc[f64](a, p)
    let (v, e2) = mem.alloc[f64](a, p * p)
    let (l, e3) = mem.alloc[f64](a, p * p)
    let (id, e4) = mem.alloc[f64](a, p * p)
    let (zr, e5) = mem.alloc[f64](a, p)
    let (tmp, e6) = mem.alloc[f64](a, p)
    let (tmp2, e7) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (none, e1) }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var i = 0usize
        while i < nfit {
            s += samples[i * p + j]
            i += 1usize
        }
        m[j] = s / f64(nfit)
        zr[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var i = 0usize
            while i < nfit {
                s += (samples[i * p + j] - m[j]) * (samples[i * p + k] - m[k])
                i += 1usize
            }
            v[j * p + k] = s / f64(nfit - 1usize)
            id[j * p + k] = 0.0f64
            if j == k { id[j * p + k] = 1.0f64 }
            k += 1usize
        }
        j += 1usize
    }
    if !chol_lower(v, p, l) { ret (none, mem.Invalid) }
    var logdet = 0.0f64
    j = 0usize
    while j < p {
        logdet += math.log[f64](l[j * p + j])
        j += 1usize
    }
    let it = samples[nfit * p..n * p]
    let (gen, ge) = mv.rmvnorm(a, g, nit, zr, id, p, 0u8)
    if ge != ok { ret (none, ge) }
    let (l1, e8) = mem.alloc[f64](a, nit)
    let (l2, e9) = mem.alloc[f64](a, nit)
    if e8 != ok || e9 != ok { ret (none, e8) }
    let ln2pi = 1.8378770664093453f64
    let c0 = 0.0f64 - math.log[f64](2.0f64) + logdet
    var i = 0usize
    while i < nit {
        // q12: the standard normal log density of L^-1 (x - m)
        var zz = 0.0f64
        j = 0usize
        while j < p {
            var s = it[i * p + j] - m[j]
            var k = 0usize
            while k < j {
                s -= l[j * p + k] * tmp[k]
                k += 1usize
            }
            tmp[j] = s / l[j * p + j]
            zz += tmp[j] * tmp[j]
            j += 1usize
        }
        let q12 = 0.0f64 - 0.5f64 * (f64(p) * ln2pi + zz)
        // q11: the posterior at x and at its reflection 2 m - x
        j = 0usize
        while j < p {
            tmp[j] = it[i * p + j]
            tmp2[j] = 2.0f64 * m[j] - it[i * p + j]
            j += 1usize
        }
        let q11 = logaddexp(logpost(ctx, tmp), logpost(ctx, tmp2))
        l1[i] = c0 + (q11 - q12)
        // q22 and q21: the draw z, then the posterior at m - L z and m + L z
        var gg = 0.0f64
        j = 0usize
        while j < p {
            gg += gen[i * p + j] * gen[i * p + j]
            var s = 0.0f64
            var k = 0usize
            while k <= j {
                s += l[j * p + k] * gen[i * p + k]
                k += 1usize
            }
            tmp[j] = m[j] - s
            tmp2[j] = m[j] + s
            j += 1usize
        }
        let q22 = 0.0f64 - 0.5f64 * (f64(p) * ln2pi + gg)
        let q21 = logaddexp(logpost(ctx, tmp), logpost(ctx, tmp2))
        l2[i] = c0 + (q21 - q22)
        i += 1usize
    }
    let (fit, fe) = iterate(a, l1, l2, 0.5f64, 1.0e-10f64, maxiter)
    ret (fit, fe)
}

// parameter bounds (.transform2Real, .invTransform2Real, .logJacobian for param_types "real"): lb < ub, either may be infinite
type Tx[C: type] = struct { ctx: *C, f: fn(*C, []const f64) -> f64, lb: []const f64, ub: []const f64, buf: []f64 }

fn is_inf(x: f64) -> bool { ret x > 1.0e300f64 || x < 0.0f64 - 1.0e300f64 }

// the log posterior at a point on the unconstrained scale: the posterior at the back-transformed point plus the log Jacobian
fn tx_logpost[C: type](t: *Tx[C], th: []const f64) -> f64 {
    var jac = 0.0f64
    var i = 0usize
    while i < th.len {
        let lo = t.lb[i]
        let hi = t.ub[i]
        if !is_inf(lo) && is_inf(hi) {
            t.buf[i] = math.exp[f64](th[i]) + lo
            jac += th[i]
        } else if is_inf(lo) && !is_inf(hi) {
            t.buf[i] = hi - math.exp[f64](th[i])
            jac += th[i]
        } else if !is_inf(lo) && !is_inf(hi) {
            t.buf[i] = dist.pnorm(th[i], 0.0f64, 1.0f64, true, false) * (hi - lo) + lo
            jac += math.log[f64](hi - lo) + dist.dnorm(th[i], 0.0f64, 1.0f64, true)
        } else {
            t.buf[i] = th[i]
        }
        i += 1usize
    }
    ret t.f(t.ctx, t.buf) + jac
}

// bridge_sampler(samples, log_posterior, lb =, ub =, method = "normal" or "warp3", use_neff = FALSE) for real parameters with bounds;
// method 0 normal, 1 warp3
fn bridge_bounded[C: type](a: *mem.Arena, g: *rng.Rng, ctx: *C, logpost: fn(*C, []const f64) -> f64, samples: []const f64, n: usize, p: usize, lb: []const f64, ub: []const f64, method: u8, maxiter: i64) -> (Fit, err) {
    var none: Fit = zero
    let (ts, e1) = mem.alloc[f64](a, n * p)
    let (buf, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret (none, e1) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            let x = samples[i * p + j]
            let lo = lb[j]
            let hi = ub[j]
            if x < lo || x > hi { ret (none, mem.Invalid) }
            if !is_inf(lo) && is_inf(hi) {
                ts[i * p + j] = math.log[f64](x - lo)
            } else if is_inf(lo) && !is_inf(hi) {
                ts[i * p + j] = math.log[f64](hi - x)
            } else if !is_inf(lo) && !is_inf(hi) {
                ts[i * p + j] = dist.qnorm((x - lo) / (hi - lo), 0.0f64, 1.0f64, true, false)
            } else {
                ts[i * p + j] = x
            }
            j += 1usize
        }
        i += 1usize
    }
    var tx = Tx[C] { ctx: ctx, f: logpost, lb: lb, ub: ub, buf: buf }
    if method == 1u8 {
        let (fw, ew) = bridge_warp3[Tx[C]](a, g, &tx, tx_logpost[C], ts, n, p, maxiter)
        ret (fw, ew)
    }
    let (fn1, en1) = bridge_normal[Tx[C]](a, g, &tx, tx_logpost[C], ts, n, p, maxiter)
    ret (fn1, en1)
}
