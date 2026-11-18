// e.algo.stat.ismev rlarg.fit against ismev. tests/oracle/ismev_rlarg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ismev_rlarg`; the layout is at the top of scripts/r_oracle/groups/ismev_rlarg.R.

use e.algo.stat.ismev as im
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let rows = usize(x[0usize])
    let r = usize(x[1usize])
    let which = usize(x[2usize])
    let (f, e) = im.fit_rlarg(a, x[3usize..3usize + rows * r], rows, r)
    if e != ok { os.exit(5) }
    if which == 99usize { ret f.nllh }
    if which >= 10usize { ret f.se[which - 10usize] }
    ret f.par[which]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ismev_rlarg.json")
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
