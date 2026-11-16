// e.math.opt.simplex against lpSolve::lp. tests/oracle/lpsolve.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lpsolve`; the layout is at the top of scripts/r_oracle/groups/lpsolve.R.

use e.io
use e.math.opt as opt
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let m = usize(x[0usize])
    let n = usize(x[1usize])
    let (cc, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(5) }
    let (am, e2) = mem.alloc[f64](a, m * n)
    if e2 != ok { os.exit(6) }
    let (b, e3) = mem.alloc[f64](a, m)
    if e3 != ok { os.exit(7) }
    var i = 0usize
    while i < n {
        cc[i] = x[2usize + i]
        i += 1usize
    }
    let ra = 2usize + n
    let rr = ra + m * n
    let rb = rr + m
    i = 0usize
    while i < m {
        var sign = 1.0f64
        if x[rr + i] > 0.5f64 { sign = 0.0f64 - 1.0f64 }
        var j = 0usize
        while j < n {
            am[i * n + j] = sign * x[ra + i * n + j]
            j += 1usize
        }
        b[i] = sign * x[rb + i]
        i += 1usize
    }
    let (sol, e4) = mem.alloc[f64](a, n)
    if e4 != ok { os.exit(8) }
    let (tab, e5) = mem.alloc[f64](a, (m + 2usize) * (n + m + 2usize))
    if e5 != ok { os.exit(9) }
    let (bas, e6) = mem.alloc[usize](a, m)
    if e6 != ok { os.exit(10) }
    let (obj, e7) = opt.simplex(cc, am, b, m, n, sol, tab, bas)
    if e7 != ok { os.exit(11) }
    if str.eq(c.name, "obj") { ret obj }
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += sol[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lpsolve.json")
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
