// e.algo.stat.lpsolveapi against lpSolveAPI. tests/oracle/lpsolveapi.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lpsolveapi`; the layout is at the top of scripts/r_oracle/groups/lpsolveapi.R.

use e.algo.stat.lpsolveapi as api
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let sense = x[0usize]
    let m = usize(x[1usize])
    let n = usize(x[2usize])
    let rc = 3usize
    let ra = rc + n
    let rr = ra + m * n
    let rb = rr + m
    let rl = rb + m
    let rh = rl + n
    let rk = rh + n
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
    var j = 0usize
    while j < n {
        api.set_bounds(&model, j + 1usize, x[rl + j], x[rh + j])
        api.set_type(&model, j + 1usize, usize(x[rk + j]))
        j += 1usize
    }
    let st = api.solve(a, &model)
    if str.eq(c.name, "status") { ret f64(st) }
    if str.eq(c.name, "obj") { ret api.get_objective(&model) }
    if str.eq(c.name, "xe") { ret api.get_variable(&model, usize(x[rk + n])) }
    if str.eq(c.name, "ce") { ret api.get_constraint(&model, usize(x[rk + n])) }
    var s = 0.0f64
    if str.eq(c.name, "x") {
        j = 1usize
        while j <= n {
            s += api.get_variable(&model, j) * f64(j)
            j += 1usize
        }
        ret s
    }
    i = 1usize
    while i <= m {
        s += api.get_constraint(&model, i) * f64(i)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lpsolveapi.json")
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
