// lpSolve's integer programs: lp("max", ..., int.vec = ...) as a depth-first branch and bound over the simplex of e.math.opt (A x <= b, x >= 0), branching on the lowest
// indexed fractional integer variable and cutting a branch whose relaxation cannot beat the incumbent. The optimum value is unique, so that is what agrees with lpSolve;
// the solution returned is the first optimal one found.

use e.math
use e.math.opt as opt
use e.mem

error Malformed

type Best = struct { obj: f64, found: bool }

// the relaxation at a node: the rows of am (m by n) and b, then x_j <= hi[j] for finite hi and -x_j <= -lo[j] for a positive lo; m is the number of original rows
fn node(a: *mem.Arena, cc: []const f64, am: []const f64, b: []const f64, m: usize, n: usize, isint: []const bool, lo: []const f64, hi: []const f64, best: *Best, bx: []f64) -> err {
    var extra = 0usize
    var j = 0usize
    while j < n {
        if hi[j] < 1.0e30f64 { extra += 1usize }
        if lo[j] > 0.0f64 { extra += 1usize }
        j += 1usize
    }
    let mm = m + extra
    let (a2, e0) = mem.alloc[f64](a, mm * n)
    let (b2, e1) = mem.alloc[f64](a, mm)
    if e0 != ok || e1 != ok { ret mem.Full }
    var i = 0usize
    while i < m * n {
        a2[i] = am[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        b2[i] = b[i]
        i += 1usize
    }
    var r = m
    j = 0usize
    while j < n {
        if hi[j] < 1.0e30f64 {
            var q = 0usize
            while q < n {
                a2[r * n + q] = 0.0f64
                q += 1usize
            }
            a2[r * n + j] = 1.0f64
            b2[r] = hi[j]
            r += 1usize
        }
        if lo[j] > 0.0f64 {
            var q = 0usize
            while q < n {
                a2[r * n + q] = 0.0f64
                q += 1usize
            }
            a2[r * n + j] = 0.0f64 - 1.0f64
            b2[r] = 0.0f64 - lo[j]
            r += 1usize
        }
        j += 1usize
    }
    let (sol, e2) = mem.alloc[f64](a, n)
    let (tab, e3) = mem.alloc[f64](a, (mm + 2usize) * (n + mm + 2usize))
    let (bas, e4) = mem.alloc[usize](a, mm)
    if e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let (obj, es) = opt.simplex(cc, a2, b2, mm, n, sol, tab, bas)
    if es != ok { ret ok }
    if best.found && obj <= best.obj + 0.000000001f64 { ret ok }
    // the lowest indexed fractional integer variable
    var branch = n
    j = 0usize
    while j < n && branch == n {
        if isint[j] {
            let f = sol[j] - math.floor[f64](sol[j])
            if f > 0.0000001f64 && f < 1.0f64 - 0.0000001f64 { branch = j }
        }
        j += 1usize
    }
    if branch == n {
        best.obj = obj
        best.found = true
        j = 0usize
        while j < n {
            bx[j] = sol[j]
            j += 1usize
        }
        ret ok
    }
    let fl = math.floor[f64](sol[branch])
    // the up branch first (lpSolve's default is the ceiling), then the down branch
    let old_lo = lo[branch]
    let old_hi = hi[branch]
    let (lo2, e5) = mem.alloc[f64](a, n)
    let (hi2, e6) = mem.alloc[f64](a, n)
    if e5 != ok || e6 != ok { ret mem.Full }
    j = 0usize
    while j < n {
        lo2[j] = lo[j]
        hi2[j] = hi[j]
        j += 1usize
    }
    lo2[branch] = fl + 1.0f64
    let eu = node(a, cc, am, b, m, n, isint, lo2, hi2, best, bx)
    if eu != ok { ret eu }
    lo2[branch] = old_lo
    hi2[branch] = fl
    let ed = node(a, cc, am, b, m, n, isint, lo2, hi2, best, bx)
    let _ = old_hi
    ret ed
}

// maximise cc x subject to am x <= b (m rows, n variables), x >= 0, x_j integer where isint[j]; answers (optimum, error): Malformed when there is no feasible integer point
fn lp_int(a: *mem.Arena, cc: []const f64, am: []const f64, b: []const f64, m: usize, n: usize, isint: []const bool, x: []f64) -> (f64, err) {
    let (lo, e0) = mem.alloc[f64](a, n)
    let (hi, e1) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok { ret (0.0f64, mem.Full) }
    var j = 0usize
    while j < n {
        lo[j] = 0.0f64
        hi[j] = 1.0e300f64
        j += 1usize
    }
    var best = Best { obj: 0.0f64, found: false }
    let e = node(a, cc, am, b, m, n, isint, lo, hi, &best, x)
    if e != ok { ret (0.0f64, e) }
    if !best.found { ret (0.0f64, Malformed) }
    ret (best.obj, ok)
}
