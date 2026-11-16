// e.algo.graph.match.hungarian against clue::solve_LSAP and lpSolve::lp.assign. tests/oracle/assign.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R assign`; the layout is at the top of scripts/r_oracle/groups/assign.R.

use e.algo.graph.match as match
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let (asg, e1) = mem.alloc[usize](a, n)
    if e1 != ok { os.exit(5) }
    let (scr, e2) = mem.alloc[f64](a, 4usize * (n + 1usize))
    if e2 != ok { os.exit(6) }
    let (used, e3) = mem.alloc[usize](a, 2usize * (n + 1usize))
    if e3 != ok { os.exit(7) }
    let (total, e4) = match.hungarian(x[1usize..1usize + n * n], n, asg, scr, used)
    if e4 != ok { os.exit(8) }
    if str.eq(c.name, "perm") {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f64(asg[i] + 1usize) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "lpcost") { ret total }
    ret total
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/assign.json")
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
