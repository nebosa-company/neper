// R mixsqp, the solution: the maximum-likelihood mixture proportions x on the simplex for a nonnegative likelihood
// matrix L and weights w, i.e. the minimiser of `-sum w_i log(L_i x) / sum w_i` (mixsqp's `value`). The problem is
// convex with a unique optimum for a full-rank L, so the optimum is found here by SQUAREM-accelerated EM to a
// tight tolerance, not by mixsqp's sequential quadratic programming: the solution and objective agree to the
// tolerance, the iteration counts and status strings do not.
//
// Not here: the SQP iterations, the active-set and QR options, the progress table.

use e.algo.stat.squarem as sq
use e.math
use e.mem

type Prob = struct { l: []const f64, w: []const f64, n: usize, m: usize, sw: f64, ratio: []f64 }

fn em_map(p: *Prob, x: []const f64, out: []f64) {
    var j = 0usize
    while j < p.m {
        out[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < p.n {
        var d = 0.0f64
        j = 0usize
        while j < p.m {
            d += p.l[j * p.n + i] * x[j]
            j += 1usize
        }
        let r = p.w[i] / d
        j = 0usize
        while j < p.m {
            out[j] += r * p.l[j * p.n + i]
            j += 1usize
        }
        i += 1usize
    }
    var s = 0.0f64
    j = 0usize
    while j < p.m {
        out[j] = out[j] * x[j] / p.sw
        s += out[j]
        j += 1usize
    }
    j = 0usize
    while j < p.m {
        out[j] = out[j] / s
        j += 1usize
    }
}

// objective(x) = -sum w log(L x) / sum w
fn objective(l: []const f64, w: []const f64, n: usize, m: usize, x: []const f64) -> f64 {
    var s = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        var d = 0.0f64
        var j = 0usize
        while j < m {
            d += l[j * n + i] * x[j]
            j += 1usize
        }
        s += w[i] * math.log[f64](d)
        sw += w[i]
        i += 1usize
    }
    ret 0.0f64 - s / sw
}

// L is n by m column-major; x receives the m proportions; answers the objective at the solution
fn mixsqp(a: *mem.Arena, l: []const f64, w: []const f64, n: usize, m: usize, x: []f64) -> (f64, err) {
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += w[i]
        i += 1usize
    }
    let (r, e) = mem.alloc[f64](a, 1usize)
    if e != ok { ret (0.0f64, e) }
    var prob = Prob { l: l, w: w, n: n, m: m, sw: sw, ratio: r }
    let (x0, e0) = mem.alloc[f64](a, m)
    if e0 != ok { ret (0.0f64, e0) }
    var j = 0usize
    while j < m {
        x0[j] = 1.0f64 / f64(m)
        j += 1usize
    }
    let (res, se) = sq.squarem2[Prob](a, &prob, em_map, x0, 3u8, 1.0e-15f64, 20000i64)
    if se != ok { ret (0.0f64, se) }
    j = 0usize
    while j < m {
        x[j] = res.par[j]
        j += 1usize
    }
    ret (objective(l, w, n, m, x), ok)
}
