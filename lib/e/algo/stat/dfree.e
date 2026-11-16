// Derivative-free minimisation over a box: Nelder-Mead on the clamped objective, restarted from the best point with
// a fresh simplex until a restart gains less than `tol`. The same optimum as minqa's BOBYQA and NLopt's local
// derivative-free methods on smooth problems; not their evaluation counts or convergence codes.
//
// Not here: BOBYQA, NEWUOA, UOBYQA, COBYLA, Subplex, DIRECT, CRS2-LM, ISRES.

use e.math
use e.math.opt
use e.mem

type Box[C: type] = struct { f: fn(*C, []const f64) -> f64, ctx: *C, lo: []const f64, hi: []const f64, tmp: []f64 }

fn boxed[C: type](b: *Box[C], x: []const f64) -> f64 {
    var pen = 0.0f64
    var i = 0usize
    while i < x.len {
        var v = x[i]
        if v < b.lo[i] {
            pen += (b.lo[i] - v) * (b.lo[i] - v)
            v = b.lo[i]
        }
        if v > b.hi[i] {
            pen += (v - b.hi[i]) * (v - b.hi[i])
            v = b.hi[i]
        }
        b.tmp[i] = v
        i += 1usize
    }
    ret b.f(b.ctx, b.tmp) + 1.0e3f64 * pen
}

// x holds the start and receives the minimiser (inside the box); answers the value there
fn minimize_box[C: type](a: *mem.Arena, f: fn(*C, []const f64) -> f64, ctx: *C, x: []f64, lo: []const f64, hi: []const f64, tol: f64) -> (f64, err) {
    let n = x.len
    let (tmp, e1) = mem.alloc[f64](a, n)
    let (scratch, e2) = mem.alloc[f64](a, (n + 1usize) * (n + 1usize) + 4usize * n)
    if e1 != ok || e2 != ok { ret (0.0f64, e1) }
    var box = Box[C] { f: f, ctx: ctx, lo: lo, hi: hi, tmp: tmp }
    var best = 1.0e300f64
    var round = 0usize
    var scale = 0.1f64
    while round < 60usize {
        let (r, e) = opt.nelder_mead[Box[C]](&box, boxed[C], x, scale, 1.0e-15f64, 20000u32, scratch)
        if e != ok { ret (0.0f64, e) }
        let gain = best - r.value
        if r.value < best { best = r.value }
        if gain >= 0.0f64 && gain < tol && round > 0usize { break }
        scale = 0.05f64 * (1.0f64 + math.abs[f64](x[0usize]))
        round += 1usize
    }
    var i = 0usize
    while i < n {
        if x[i] < lo[i] { x[i] = lo[i] }
        if x[i] > hi[i] { x[i] = hi[i] }
        i += 1usize
    }
    ret (f(ctx, x), ok)
}

// augmented Lagrangian (the method of NLopt's AUGLAG with a derivative-free inner solver). cons fills out with ne
// equalities c = 0 then ni inequalities c <= 0. Answers the objective at the final x (inside the box).
type Al[C: type] = struct { f: fn(*C, []const f64) -> f64, cons: fn(*C, []const f64, []f64), ctx: *C, lam: []f64, rho: f64, ne: usize, ni: usize, c: []f64 }

fn al_obj[C: type](s: *Al[C], x: []const f64) -> f64 {
    s.cons(s.ctx, x, s.c)
    var v = s.f(s.ctx, x)
    var k = 0usize
    while k < s.ne + s.ni {
        if k < s.ne {
            v += s.lam[k] * s.c[k] + 0.5f64 * s.rho * s.c[k] * s.c[k]
        } else {
            let t = math.max[f64](0.0f64, s.lam[k] + s.rho * s.c[k])
            v += (t * t - s.lam[k] * s.lam[k]) / (2.0f64 * s.rho)
        }
        k += 1usize
    }
    ret v
}

fn auglag[C: type](a: *mem.Arena, f: fn(*C, []const f64) -> f64, cons: fn(*C, []const f64, []f64), ctx: *C, ne: usize, ni: usize, x: []f64, lo: []const f64, hi: []const f64, tol: f64) -> (f64, err) {
    let m = ne + ni
    let (lam, e1) = mem.alloc[f64](a, m + 1usize)
    let (cv, e2) = mem.alloc[f64](a, m + 1usize)
    if e1 != ok || e2 != ok { ret (0.0f64, e1) }
    var k = 0usize
    while k < m {
        lam[k] = 0.0f64
        k += 1usize
    }
    var s = Al[C] { f: f, cons: cons, ctx: ctx, lam: lam, rho: 10.0f64, ne: ne, ni: ni, c: cv }
    var outer = 0usize
    while outer < 60usize {
        let (v, e) = minimize_box[Al[C]](a, al_obj[C], &s, x, lo, hi, 1.0e-13f64)
        if e != ok { ret (v, e) }
        cons(ctx, x, cv)
        var viol = 0.0f64
        k = 0usize
        while k < m {
            if k < ne {
                lam[k] += s.rho * cv[k]
                viol = math.max[f64](viol, math.abs[f64](cv[k]))
            } else {
                lam[k] = math.max[f64](0.0f64, lam[k] + s.rho * cv[k])
                viol = math.max[f64](viol, cv[k])
            }
            k += 1usize
        }
        if viol < tol { break }
        s.rho = s.rho * 2.0f64
        outer += 1usize
    }
    ret (f(ctx, x), ok)
}
