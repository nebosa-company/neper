// R bridgesampling: `bridge_normal`, the bridge sampler with the normal proposal and the iterative scheme
// (r0 = 0.5, tolerance 1e-10 on r, at most maxiter steps) for unconstrained real parameters. The first
// round(n / 2) posterior draws fit the proposal (their mean and covariance), the rest enter the scheme, and
// the proposal draws come from mvtnorm::rmvnorm (the eigen method) under the caller's stream.
//
// Not here: parameter transformations (bounds, simplex), warp3, repetitions, the effective-sample-size
// variant of the error estimate (use_neff = FALSE only) and nearPD (the covariance must be positive definite).

use e.algo.rand.r as rng
use e.algo.sort
use e.algo.stat.mvtnorm as mv
use e.math
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
