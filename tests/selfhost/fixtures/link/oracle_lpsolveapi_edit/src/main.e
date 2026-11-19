// e.algo.stat.lpsolveapi model edits and readers against lpSolveAPI. tests/oracle/lpsolveapi_edit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lpsolveapi_edit`; the layout is at the top of scripts/r_oracle/groups/lpsolveapi_edit.R.

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
    let rn = rb + m
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
        api.set_bounds(&model, j + 1usize, 0.0f64, 10.0f64)
        j += 1usize
    }
    let nops = usize(x[rn])
    var k = 0usize
    while k < nops {
        let o = rn + 1usize + k * 16usize
        let code = usize(x[o])
        let oi = usize(x[o + 1usize])
        let oj = usize(x[o + 2usize])
        let ov = x[o + 3usize]
        let vec = x[(o + 4usize)..(o + 16usize)]
        if code == 1usize { api.set_mat(&model, oi, oj, ov) }
        if code == 2usize { api.set_rhs(&model, oi, ov) }
        if code == 3usize { api.set_constr_type(&model, oi, usize(ov)) }
        if code == 4usize { api.set_row(&model, oi, vec) }
        if code == 5usize { api.set_column(&model, oj, vec) }
        if code == 6usize { api.delete_constraint(&model, oi) }
        if code == 7usize { api.delete_column(&model, oj) }
        if code == 8usize {
            if api.add_column(a, &model, vec) != ok { os.exit(6) }
        }
        if code == 9usize { api.set_bounds(&model, oj, 0.0f64, ov) }
        if code == 10usize { api.set_type(&model, oj, 1usize) }
        if code == 11usize { api.set_objfn(&model, vec) }
        k += 1usize
    }
    let nr = model.m
    let nc = model.n
    if str.eq(c.name, "dimm") { ret f64(nr) }
    if str.eq(c.name, "dimn") { ret f64(nc) }
    var s = 0.0f64
    if str.eq(c.name, "mat") {
        i = 0usize
        while i <= nr {
            j = 1usize
            while j <= nc {
                s += api.get_mat(&model, i, j) * f64(100usize * (i + 1usize) + j)
                j += 1usize
            }
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "rhs") || str.eq(c.name, "ctype") {
        i = 1usize
        while i <= nr {
            if str.eq(c.name, "rhs") { s += api.get_rhs(&model, i) * f64(i) }
            if str.eq(c.name, "ctype") { s += f64(api.get_constr_type(&model, i)) * f64(i) }
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "ktype") || str.eq(c.name, "blo") || str.eq(c.name, "bhi") {
        j = 1usize
        while j <= nc {
            if str.eq(c.name, "ktype") && api.get_type(&model, j) > 0usize { s += f64(j) }
            if str.eq(c.name, "blo") { s += api.get_lower(&model, j) * f64(j) }
            if str.eq(c.name, "bhi") { s += api.get_upper(&model, j) * f64(j) }
            j += 1usize
        }
        ret s
    }
    let st = api.solve(a, &model)
    if str.eq(c.name, "status") { ret f64(st) }
    ret api.get_objective(&model)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lpsolveapi_edit.json")
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
