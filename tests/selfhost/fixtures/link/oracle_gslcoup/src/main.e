// e.algo.stat.gslcoupling against gsl, value and error estimate. tests/oracle/gslcoup.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslcoup`; the layout of each case is at the top of scripts/r_oracle/groups/gslcoup.R.

use e.algo.stat.gslcoupling as gk
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn j(x: []const f64, i: usize) -> i64 { ret i64(x[i + 2usize]) }

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    var v = 0.0f64
    var e = 0.0f64
    if n == 3usize {
        let (v3, e3) = gk.coupling_3j(j(x, 0usize), j(x, 1usize), j(x, 2usize), j(x, 3usize), j(x, 4usize), j(x, 5usize))
        v = v3
        e = e3
    }
    if n == 6usize {
        let (v6, e6) = gk.coupling_6j(j(x, 0usize), j(x, 1usize), j(x, 2usize), j(x, 3usize), j(x, 4usize), j(x, 5usize))
        v = v6
        e = e6
    }
    if n == 9usize {
        let (v9, e9) = gk.coupling_9j(j(x, 0usize), j(x, 1usize), j(x, 2usize), j(x, 3usize), j(x, 4usize), j(x, 5usize), j(x, 6usize), j(x, 7usize), j(x, 8usize))
        v = v9
        e = e9
    }
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslcoup.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
