// R SQUAREM: `squarem2` (the objective-free squared extrapolation scheme with step-length methods 1, 2
// and 3, the safeguard retries and the adaptive maximum step) and `fpiter` (the plain fixed-point
// iteration), over a fixed-point map given as a function of the parameter vector. The map is a callback
// `fn(ctx, par, out)`; an `out` with a NaN stands for a failed evaluation.
//
// And `squarem1`, `cyclem1` and `cyclem2` (the objective-function variant and the cycled RRE and MPE schemes). Not here: the
// intermediate-iterate trace; a failed map evaluation ends the run with `failed` set where R stops with an error.

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

// ---- the objective-function variant and the cycled schemes

type Ctl = struct {
    method: u8, tol: f64, maxiter: i64, step_min0: f64, step_max0: f64, mstep: f64, objinc: f64, minimize: bool, kr: f64, k: usize, rre: bool, square: bool
}

fn ctl_default() -> Ctl {
    var c: Ctl = zero
    c.method = 3u8
    c.tol = 1.0e-7f64
    c.maxiter = 1500i64
    c.step_min0 = 1.0f64
    c.step_max0 = 1.0f64
    c.mstep = 4.0f64
    c.objinc = 1.0f64
    c.minimize = true
    c.kr = 1.0f64
    c.k = 2usize
    c.rre = true
    c.square = true
    ret c
}

type Result1 = struct { par: []f64, value: f64, iter: i64, fpevals: i64, objfevals: i64, converged: bool, failed: bool }

fn is_finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

// squarem1: squarem2 with the stabilisation step judged by the objective function (monotone to within objinc)
fn squarem1[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), obj: fn(*Ctx, []const f64) -> f64, par0: []const f64, c: Ctl) -> (Result1, err) {
    var none: Result1 = zero
    let n = par0.len
    let (p, e0) = mem.alloc[f64](a, n)
    let (p1, e1) = mem.alloc[f64](a, n)
    let (p2, e2) = mem.alloc[f64](a, n)
    let (q1, e3) = mem.alloc[f64](a, n)
    let (q2, e4) = mem.alloc[f64](a, n)
    let (pn, e5) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (none, e0) }
    copy_to(p, par0)
    var step_min = c.step_min0
    var step_max = c.step_max0
    var iter = 1i64
    var lold = obj(ctx, p)
    var leval = 1i64
    var feval = 0i64
    var failed = false
    var done = false
    while feval < c.maxiter && !done {
        f(ctx, p, p1)
        feval += 1i64
        if any_nan(p1) {
            failed = true
            break
        }
        var i = 0usize
        while i < n {
            q1[i] = p1[i] - p[i]
            i += 1usize
        }
        let sr2 = norm2(q1)
        if math.sqrt[f64](sr2) < c.tol {
            copy_to(p, p1)
            break
        }
        f(ctx, p1, p2)
        feval += 1i64
        if any_nan(p2) {
            failed = true
            break
        }
        i = 0usize
        while i < n {
            q2[i] = p2[i] - p1[i]
            i += 1usize
        }
        if math.sqrt[f64](norm2(q2)) < c.tol {
            copy_to(p, p2)
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
        if c.method == 1u8 { alpha = 0.0f64 - srv / sv2 } else if c.method == 2u8 { alpha = 0.0f64 - sr2 / srv } else { alpha = math.sqrt[f64](sr2 / sv2) }
        if alpha > step_max { alpha = step_max }
        if alpha < step_min { alpha = step_min }
        i = 0usize
        while i < n {
            pn[i] = p[i] + 2.0f64 * alpha * q1[i] + alpha * alpha * (q2[i] - q1[i])
            i += 1usize
        }
        var dev = alpha - 1.0f64
        if dev < 0.0f64 { dev = 0.0f64 - dev }
        if dev > 0.01f64 {
            f(ctx, pn, p1)
            feval += 1i64
            copy_to(pn, p1)
        }
        var lnew = lold
        var fallback = false
        if any_nan(pn) {
            fallback = true
        } else {
            if is_finite(c.objinc) {
                lnew = obj(ctx, pn)
                leval += 1i64
            }
            var nonmono = false
            if c.minimize { nonmono = lnew > lold + c.objinc } else { nonmono = lnew < lold - c.objinc }
            if lnew != lnew || nonmono { fallback = true }
        }
        if fallback {
            copy_to(pn, p2)
            lnew = obj(ctx, p2)
            leval += 1i64
            if alpha == step_max {
                var cand = step_max / c.mstep
                if cand < c.step_max0 { cand = c.step_max0 }
                step_max = cand
            }
            alpha = 1.0f64
        }
        if alpha == step_max { step_max = c.mstep * step_max }
        if step_min < 0.0f64 && alpha == step_min { step_min = c.mstep * step_min }
        copy_to(p, pn)
        if lnew == lnew { lold = lnew }
        iter += 1i64
    }
    var conv = true
    if feval >= c.maxiter { conv = false }
    if !is_finite(c.objinc) {
        lold = obj(ctx, p)
        leval += 1i64
    }
    ret (Result1 { par: p, value: lold, iter: iter, fpevals: feval, objfevals: leval, converged: conv, failed: failed }, ok)
}

// solve the least-squares problem min |A x - b| for the m by n column-major A by Householder QR; false when R has a zero or NaN diagonal
fn lstsq(a: *mem.Arena, am: []const f64, m: usize, n: usize, b: []const f64, x: []f64) -> bool {
    let (w, e1) = mem.alloc[f64](a, m * n)
    let (y, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret false }
    var i = 0usize
    while i < m * n {
        w[i] = am[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        y[i] = b[i]
        i += 1usize
    }
    var k = 0usize
    while k < n {
        var s = 0.0f64
        i = k
        while i < m {
            s += w[k * m + i] * w[k * m + i]
            i += 1usize
        }
        var nrm = math.sqrt[f64](s)
        if w[k * m + k] > 0.0f64 { nrm = 0.0f64 - nrm }
        if nrm == 0.0f64 || nrm != nrm { ret false }
        let v0 = w[k * m + k] - nrm
        w[k * m + k] = v0
        var vv = v0 * v0
        i = k + 1usize
        while i < m {
            vv += w[k * m + i] * w[k * m + i]
            i += 1usize
        }
        var j = k + 1usize
        while j < n {
            var d = 0.0f64
            i = k
            while i < m {
                d += w[k * m + i] * w[j * m + i]
                i += 1usize
            }
            let t = 2.0f64 * d / vv
            i = k
            while i < m {
                w[j * m + i] -= t * w[k * m + i]
                i += 1usize
            }
            j += 1usize
        }
        var d = 0.0f64
        i = k
        while i < m {
            d += w[k * m + i] * y[i]
            i += 1usize
        }
        let t = 2.0f64 * d / vv
        i = k
        while i < m {
            y[i] -= t * w[k * m + i]
            i += 1usize
        }
        w[k * m + k] = nrm
        k += 1usize
    }
    k = n
    while k > 0usize {
        k -= 1usize
        var s = y[k]
        var j = k + 1usize
        while j < n {
            s -= w[j * m + k] * x[j]
            j += 1usize
        }
        x[k] = s / w[k * m + k]
    }
    ret true
}

// cyclem1 (with the objective) and cyclem2 (without): cycled reduced-rank or minimal-polynomial extrapolation of order K
fn cyclem[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), obj: fn(*Ctx, []const f64) -> f64, with_obj: bool, par0: []const f64, c: Ctl) -> (Result1, err) {
    var none: Result1 = zero
    let n = par0.len
    let k = c.k
    if k > n {
        none.failed = true
        ret (none, ok)
    }
    let cols = 2usize * k + 1usize
    let (par, e0) = mem.alloc[f64](a, n)
    let (pm, e1) = mem.alloc[f64](a, n * (cols + 1usize))
    let (um, e2) = mem.alloc[f64](a, n * (k + 1usize))
    let (coef, e3) = mem.alloc[f64](a, k + 1usize)
    let (pnew, e4) = mem.alloc[f64](a, n)
    let (ptmp, e5) = mem.alloc[f64](a, n)
    let (gm, e6) = mem.alloc[f64](a, (k + 1usize) * (k + 1usize))
    let (ones, e7) = mem.alloc[f64](a, k + 1usize)
    let (rhs, e8) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (none, e0) }
    copy_to(par, par0)
    var iter = 1i64
    var lold = 0.0f64
    var leval = 0i64
    if with_obj {
        iter = 0i64
        lold = obj(ctx, par)
        leval = 1i64
    }
    f(ctx, par, ptmp)
    var res = 0.0f64
    var i = 0usize
    while i < n {
        res += (ptmp[i] - par[i]) * (ptmp[i] - par[i])
        i += 1usize
    }
    res = math.sqrt[f64](res)
    copy_to(par, ptmp)
    var feval = 1i64
    var failed = false
    while feval < c.maxiter && res > c.tol && !failed {
        if with_obj { iter += 1i64 }
        var extrap = true
        // p columns 0..K+1 by the map, U columns 0..K the differences
        copy_to(pm[0usize..n], par)
        var col = 1usize
        while col <= k + 1usize {
            f(ctx, pm[(col - 1usize) * n..col * n], pm[col * n..(col + 1usize) * n])
            if any_nan(pm[col * n..(col + 1usize) * n]) {
                failed = true
                break
            }
            i = 0usize
            while i < n {
                um[(col - 1usize) * n + i] = pm[col * n + i] - pm[(col - 1usize) * n + i]
                i += 1usize
            }
            col += 1usize
        }
        if failed { break }
        feval += i64(k) + 1i64
        var sqkp1 = 0.0f64
        i = 0usize
        while i < n {
            sqkp1 += um[k * n + i] * um[k * n + i]
            i += 1usize
        }
        sqkp1 = math.sqrt[f64](sqkp1)
        var solved = true
        if c.rre {
            var r = 0usize
            while r <= k {
                var q = 0usize
                while q <= k {
                    var s = 0.0f64
                    i = 0usize
                    while i < n {
                        s += um[r * n + i] * um[q * n + i]
                        i += 1usize
                    }
                    gm[q * (k + 1usize) + r] = s
                    q += 1usize
                }
                ones[r] = 1.0f64
                r += 1usize
            }
            solved = lstsq(a, gm, k + 1usize, k + 1usize, ones, coef)
        } else {
            i = 0usize
            while i < n {
                rhs[i] = 0.0f64 - um[k * n + i]
                i += 1usize
            }
            solved = lstsq(a, um[0usize..k * n], n, k, rhs, coef)
            coef[k] = 1.0f64
        }
        if !solved || any_nan(coef) {
            extrap = false
        } else {
            var sm = 0.0f64
            i = 0usize
            while i <= k {
                sm += coef[i]
                i += 1usize
            }
            if math.abs[f64](sm) < 1.0e-7f64 { extrap = false }
            i = 0usize
            while i <= k {
                coef[i] = coef[i] / sm
                i += 1usize
            }
        }
        if !extrap {
            // the last column of p
            copy_to(par, pm[(k + 1usize) * n..(k + 2usize) * n])
            res = sqkp1
            iter += 1i64
            continue
        }
        var last = k + 1usize
        if !c.square {
            i = 0usize
            while i < n {
                var s = 0.0f64
                var q = 0usize
                while q <= k {
                    s += pm[q * n + i] * coef[q]
                    q += 1usize
                }
                pnew[i] = s
                i += 1usize
            }
        } else {
            if k > 1usize {
                var q = 1usize
                while q <= k - 1usize {
                    f(ctx, pm[(q + k) * n..(q + k + 1usize) * n], pm[(q + k + 1usize) * n..(q + k + 2usize) * n])
                    if any_nan(pm[(q + k + 1usize) * n..(q + k + 2usize) * n]) {
                        failed = true
                        break
                    }
                    q += 1usize
                }
                if failed { break }
                feval += i64(k) - 1i64
                last = 2usize * k
            }
            i = 0usize
            while i < n {
                pnew[i] = 0.0f64
                i += 1usize
            }
            var ii = 0usize
            while ii <= k {
                var jj = 0usize
                while jj <= k {
                    let cc = coef[ii] * coef[jj]
                    i = 0usize
                    while i < n {
                        pnew[i] += cc * pm[(ii + jj) * n + i]
                        i += 1usize
                    }
                    jj += 1usize
                }
                ii += 1usize
            }
            sqkp1 = 0.0f64
            i = 0usize
            while i < n {
                let dd = pm[(2usize * k - 1usize) * n + i] - pm[(2usize * k - 2usize) * n + i]
                sqkp1 += dd * dd
                i += 1usize
            }
            sqkp1 = math.sqrt[f64](sqkp1)
        }
        // the last column of the extended p (0-based index `last`)
        f(ctx, pnew, ptmp)
        feval += 1i64
        if with_obj {
            var bad = any_nan(ptmp)
            if bad {
                copy_to(pnew, pm[last * n..(last + 1usize) * n])
                res = sqkp1
                extrap = false
            } else {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += (ptmp[i] - pnew[i]) * (ptmp[i] - pnew[i])
                    i += 1usize
                }
                res = math.sqrt[f64](s)
                copy_to(pnew, ptmp)
            }
            let lnew = obj(ctx, pnew)
            leval += 1i64
            var nonmono = false
            if c.minimize { nonmono = lnew > lold + c.objinc } else { nonmono = lnew < lold - c.objinc }
            if lnew != lnew || nonmono {
                copy_to(pnew, pm[last * n..(last + 1usize) * n])
                res = sqkp1
                extrap = false
            } else {
                lold = lnew
            }
            copy_to(par, pnew)
        } else {
            if any_nan(ptmp) {
                copy_to(par, pm[last * n..(last + 1usize) * n])
                res = sqkp1
            } else {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += (ptmp[i] - pnew[i]) * (ptmp[i] - pnew[i])
                    i += 1usize
                }
                res = math.sqrt[f64](s)
                var pn2 = 0.0f64
                i = 0usize
                while i < n {
                    pn2 += pm[last * n + i] * pm[last * n + i]
                    i += 1usize
                }
                let parnorm = math.sqrt[f64](pn2 / f64(n))
                if res <= c.kr * (1.0f64 + parnorm) + sqkp1 {
                    copy_to(par, ptmp)
                } else {
                    copy_to(par, pm[last * n..(last + 1usize) * n])
                    res = sqkp1
                }
            }
            iter += 1i64
        }
    }
    var conv = true
    if feval >= c.maxiter { conv = false }
    ret (Result1 { par: par, value: lold, iter: iter, fpevals: feval, objfevals: leval, converged: conv, failed: failed }, ok)
}
