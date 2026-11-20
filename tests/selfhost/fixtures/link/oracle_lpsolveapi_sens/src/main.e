// e.algo.stat.lpsolveapi's sensitivity readers against lpSolveAPI. tests/oracle/lpsolveapi_sens.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lpsolveapi_sens`; the layout is at the top of scripts/r_oracle/groups/lpsolveapi_sens.R.

use e.algo.stat.lpsolveapi as api
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nan = 0.0f64 / 0.0f64
    let sense = x[0usize]
    let m = usize(x[1usize])
    let n = usize(x[2usize])
    let rc = 3usize
    let ra = rc + n
    let rr = ra + m * n
    let rb = rr + m
    let rf = rb + m
    let (md, e0) = api.make_lp(a, 0usize, n)
    if e0 != ok { os.exit(5) }
    var model = md
    api.set_sense(&model, sense > 0.5f64)
    api.set_objfn(&model, x[rc..ra])
    var i = 0usize
    while i < m {
        let _ = api.add_constraint(&model, x[(ra + i * n)..(ra + i * n + n)], usize(x[rr + i]), x[rb + i])
        i += 1usize
    }
    let (sol, g1) = mem.alloc[f64](a, n)
    let (du, g2) = mem.alloc[f64](a, m + n)
    let (df, g3) = mem.alloc[f64](a, m + n)
    let (dt, g4) = mem.alloc[f64](a, m + n)
    let (cf, g5) = mem.alloc[f64](a, n)
    let (ct, g6) = mem.alloc[f64](a, n)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok { os.exit(6) }
    if api.sensitivity(a, &model, sol, du, df, dt, cf, ct) != ok { ret nan }
    let field = usize(x[rf])
    let k = usize(x[rf + 1usize]) - 1usize
    if field == 0usize { ret du[k] }
    if field == 1usize { ret df[k] }
    if field == 2usize { ret dt[k] }
    if field == 3usize { ret cf[k] }
    if field == 4usize { ret ct[k] }
    if field == 5usize {
        if k == 0usize { ret 1.0f64 }
        ret du[k - 1usize]
    }
    // get.primal.solution(orig = TRUE): the m row values then the variables
    if k < m {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += x[ra + k * n + j] * sol[j]
            j += 1usize
        }
        ret s
    }
    ret sol[k - m]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lpsolveapi_sens.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
