// e.algo.stat.nnls against nnls: the Lawson-Hanson solution, the deviance and the passive set size.
// tests/oracle/nnls.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nnls`; the
// layout is at the top of scripts/r_oracle/groups/nnls.R.

use e.algo.stat.nnls as nn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let m = usize(x[0usize])
    let n = usize(x[1usize])
    let (s, e) = nn.nnls(a, x[2usize..2usize + m * n], m, n, x[2usize + m * n..2usize + m * n + m])
    if e != ok { os.exit(6) }
    if str.eq(c.name, "x") { ret s.x[usize(x[x.len - 1usize])] }
    if str.eq(c.name, "deviance") { ret s.deviance }
    ret f64(s.npassive)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nnls.json")
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
