// e.algo.stat.ismev rlarg.fit against ismev. tests/oracle/ismev_rlarg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ismev_rlarg`; the layout is at the top of scripts/r_oracle/groups/ismev_rlarg.R.

use e.algo.stat.ismev as im
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "pp") {
        let n = usize(x[0usize])
        let (g, ge) = im.fit_pp(a, x[4usize..4usize + n], x[2usize], usize(x[1usize]))
        if ge != ok { os.exit(6) }
        let w = usize(x[3usize])
        if w == 99usize { ret g.nllh }
        if w >= 10usize { ret g.se[w - 10usize] }
        ret g.par[w]
    }
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
