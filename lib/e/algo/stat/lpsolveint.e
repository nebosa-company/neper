// lp(..., int.vec = isint, binary.vec = isbin, compute.sens = 1): lpSolve reports the sensitivity of the last linear program of its branch and bound, in which every integer variable is nonbasic at the value
// it has in the optimum (x* from lp_general). That program is lp_sens_at over the original rows with the integer columns flagged. duals receive the m constraint prices then the n reduced costs, dfrom and dto
// the right-hand-side and variable ranges, cfrom and cto the objective coefficient ranges; the answer is the optimum. Not reproduced: the value range of an integer variable and programs where lp_solve
// leaves an integer variable basic.

use e.algo.stat.lpsolvepkg as lps
use e.mem

error Malformed

fn lp_sens_int(a: *mem.Arena, c: []const f64, am: []const f64, b: []const f64, rel: []const usize, m: usize, n: usize, maximise: bool, isint: []const bool, isbin: []const bool, duals: []f64, dfrom: []f64, dto: []f64, cfrom: []f64, cto: []f64) -> (f64, err) {
    var nb = 0usize
    var j = 0usize
    while j < n {
        if isbin[j] { nb += 1usize }
        j += 1usize
    }
    let mm = m + nb
    let (ae, e0) = mem.alloc[f64](a, mm * n)
    let (be, e1) = mem.alloc[f64](a, mm)
    let (re, e2) = mem.alloc[usize](a, mm)
    let (ia, e3) = mem.alloc[bool](a, n)
    let (xs, e4) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < mm * n {
        ae[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        j = 0usize
        while j < n {
            ae[i * n + j] = am[i * n + j]
            j += 1usize
        }
        be[i] = b[i]
        re[i] = rel[i]
        i += 1usize
    }
    var r = m
    j = 0usize
    while j < n {
        ia[j] = isint[j] || isbin[j]
        if isbin[j] {
            ae[r * n + j] = 1.0f64
            be[r] = 1.0f64
            re[r] = 0usize
            r += 1usize
        }
        j += 1usize
    }
    let (v, st) = lps.lp_general(a, maximise, c, ae, re, be, mm, n, ia, xs)
    if st != 0usize { ret (0.0f64, Malformed) }
    // the last program of the branch and bound is the program over the original rows with every integer variable held at its value in the optimum
    let (v2, es) = lps.lp_sens_at(a, c, am, b, rel, m, n, maximise, xs, ia, duals, dfrom, dto, cfrom, cto)
    let _ = v2
    if es != ok { ret (0.0f64, es) }
    ret (v, ok)
}
