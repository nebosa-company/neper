// R SQUAREM: `squarem2` (the objective-free squared extrapolation scheme with step-length methods 1, 2
// and 3, the safeguard retries and the adaptive maximum step) and `fpiter` (the plain fixed-point
// iteration), over a fixed-point map given as a function of the parameter vector. The map is a callback
// `fn(ctx, par, out)`; an `out` with a NaN stands for a failed evaluation.
//
// Not here: squarem1 and cyclem1 with an objective function, the cyclic RRE and MPE schemes and the
// intermediate-iterate trace.

use e.math
use e.mem

type Result = struct { par: []f64, iter: i64, fpevals: i64, converged: bool }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn norm2(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * x[i]
        i += 1usize
    }
    ret s
}

fn any_nan(x: []const f64) -> bool {
    var i = 0usize
    while i < x.len {
        if x[i] != x[i] { ret true }
        i += 1usize
    }
    ret false
}

fn copy_to(dst: []f64, src: []const f64) {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
}

// fpiter: iterate until the step is shorter than tol or maxiter is reached
fn fpiter[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), par0: []const f64, tol: f64, maxiter: i64) -> (Result, err) {
    var none: Result = zero
    let n = par0.len
    let (par, pe) = mem.alloc[f64](a, n)
    if pe != ok { ret (none, pe) }
    let (nw, ne) = mem.alloc[f64](a, n)
    if ne != ok { ret (none, ne) }
    copy_to(par, par0)
    var iter = 1i64
    var conv = false
    while iter < maxiter {
        f(ctx, par, nw)
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += (nw[i] - par[i]) * (nw[i] - par[i])
            i += 1usize
        }
        if math.sqrt[f64](s) < tol {
            conv = true
            break
        }
        copy_to(par, nw)
        iter += 1i64
    }
    ret (Result { par: par, iter: iter, fpevals: iter, converged: conv }, ok)
}

// squarem2 with the defaults of R (K = 1, step.min0 = step.max0 = 1, mstep = 4, kr = 1)
fn squarem2[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), par0: []const f64, method: u8, tol: f64, maxiter: i64) -> (Result, err) {
    var none: Result = zero
    let n = par0.len
    let (par, e0) = mem.alloc[f64](a, n)
    let (p1, e1) = mem.alloc[f64](a, n)
    let (p2, e2) = mem.alloc[f64](a, n)
    let (q1, e3) = mem.alloc[f64](a, n)
    let (q2, e4) = mem.alloc[f64](a, n)
    let (pn, e5) = mem.alloc[f64](a, n)
    let (pt, e6) = mem.alloc[f64](a, n)
    if e0 != ok { ret (none, e0) }
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    if e5 != ok { ret (none, e5) }
    if e6 != ok { ret (none, e6) }
    copy_to(par, par0)
    let step_min = 1.0f64
    let step_max0 = 1.0f64
    var step_max = 1.0f64
    let mstep = 4.0f64
    let kr = 1.0f64
    var iter = 1i64
    var feval = 0i64
    var conv = true
    var done = false
    while feval < maxiter && !done {
        f(ctx, par, p1)
        feval += 1i64
        if any_nan(p1) { break }
        var i = 0usize
        while i < n {
            q1[i] = p1[i] - par[i]
            i += 1usize
        }
        let sr2 = norm2(q1)
        if math.sqrt[f64](sr2) < tol {
            copy_to(par, p1)
            break
        }
        f(ctx, p1, p2)
        feval += 1i64
        if any_nan(p2) { break }
        i = 0usize
        while i < n {
            q2[i] = p2[i] - p1[i]
            i += 1usize
        }
        let sq2 = math.sqrt[f64](norm2(q2))
        var res = sq2
        if sq2 < tol {
            copy_to(par, p2)
            break
        }
        var sv2 = 0.0f64
        var srv = 0.0f64
        i = 0usize
        while i < n {
            sv2 += (q2[i] - q1[i]) * (q2[i] - q1[i])
            srv += q1[i] * (q2[i] - q1[i])
            i += 1usize
        }
        var alpha = 0.0f64
        if method == 1u8 { alpha = 0.0f64 - srv / sv2 } else if method == 2u8 { alpha = 0.0f64 - sr2 / srv } else { alpha = math.sqrt[f64](sr2 / sv2) }
        if alpha > step_max { alpha = step_max }
        if alpha < step_min { alpha = step_min }
        i = 0usize
        while i < n {
            pn[i] = par[i] + 2.0f64 * alpha * q1[i] + alpha * alpha * (q2[i] - q1[i])
            i += 1usize
        }
        var diff = alpha - 1.0f64
        if diff < 0.0f64 { diff = 0.0f64 - diff }
        if diff > 0.01f64 {
            f(ctx, pn, pt)
            feval += 1i64
            if any_nan(pt) {
                copy_to(pn, p2)
                if alpha == step_max {
                    var cand = step_max / mstep
                    if cand < step_max0 { cand = step_max0 }
                    step_max = cand
                }
                alpha = 1.0f64
            } else {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += (pt[i] - pn[i]) * (pt[i] - pn[i])
                    i += 1usize
                }
                res = math.sqrt[f64](s)
                let parnorm = math.sqrt[f64](norm2(p2) / f64(n))
                let kres = kr * (1.0f64 + parnorm) + sq2
                if res <= kres {
                    copy_to(pn, pt)
                } else {
                    copy_to(pn, p2)
                    if alpha == step_max {
                        var cand = step_max / mstep
                        if cand < step_max0 { cand = step_max0 }
                        step_max = cand
                    }
                    alpha = 1.0f64
                }
            }
        }
        if alpha == step_max { step_max = mstep * step_max }
        copy_to(par, pn)
        iter += 1i64
    }
    if feval >= maxiter { conv = false }
    ret (Result { par: par, iter: iter, fpevals: feval, converged: conv }, ok)
}
