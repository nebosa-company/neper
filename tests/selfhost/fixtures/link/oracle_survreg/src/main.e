// e.algo.stat.survregpkg against survival::survreg. tests/oracle/survreg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R survreg`; the layout is at the top of scripts/r_oracle/groups/survreg.R.

use e.algo.stat.survregpkg as sr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let (o, oe) = mem.alloc[f64](a, p + 2usize)
    let (se, ee) = mem.alloc[f64](a, p + 1usize)
    if oe != ok || ee != ok { os.exit(4) }
    if sr.survreg(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[3usize + 2usize * n..3usize + 2usize * n + n * p], n, p, usize(x[0usize]), o, se) != ok { os.exit(5) }
    let q = usize(x[3usize + 2usize * n + n * p])
    if q <= p + 1usize { ret o[q] }
    ret se[q - p - 2usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/survreg.json")
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
