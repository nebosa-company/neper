// Derivative-free minimisation over a box: Nelder-Mead on the clamped objective, restarted from the best point with
// a fresh simplex until a restart gains less than `tol`. The same optimum as minqa's BOBYQA and NLopt's local
// derivative-free methods on smooth problems; not their evaluation counts or convergence codes.
//
// Not here: BOBYQA, NEWUOA, UOBYQA, COBYLA, Subplex, DIRECT, CRS2-LM, ISRES.

use e.math
use e.math.opt
use e.mem

type Box = struct { f: fn(*u8, []const f64) -> f64, ctx: *u8, lo: []const f64, hi: []const f64, tmp: []f64 }

fn boxed(b: *Box, x: []const f64) -> f64 {
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
fn minimize_box(a: *mem.Arena, f: fn(*u8, []const f64) -> f64, ctx: *u8, x: []f64, lo: []const f64, hi: []const f64, tol: f64) -> (f64, err) {
    let n = x.len
    let (tmp, e1) = mem.alloc[f64](a, n)
    let (scratch, e2) = mem.alloc[f64](a, (n + 1usize) * (n + 1usize) + 4usize * n)
    if e1 != ok || e2 != ok { ret (0.0f64, e1) }
    var box = Box { f: f, ctx: ctx, lo: lo, hi: hi, tmp: tmp }
    var best = 1.0e300f64
    var round = 0usize
    var scale = 0.1f64
    while round < 60usize {
        let (r, e) = opt.nelder_mead[Box](&box, boxed, x, scale, 1.0e-15f64, 20000u32, scratch)
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
