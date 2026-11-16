// e.algo.stat.energy against energy. tests/oracle/energy.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R energy`; the layout is at the top of scripts/r_oracle/groups/energy.R.

use e.algo.stat.energy as en
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "edist") {
        let n1 = usize(x[0usize])
        let n2 = usize(x[1usize])
        let d = usize(x[2usize])
        ret en.edist_stat(x[4usize..4usize + n1 * d], n1, x[4usize + n1 * d..4usize + n1 * d + n2 * d], n2, d, x[3usize])
    }
    let n = usize(x[0usize])
    let dx = usize(x[1usize])
    let dy = usize(x[2usize])
    let (cov, cor, e) = en.dcov_dcor(a, x[4usize..4usize + n * dx], x[4usize + n * dx..4usize + n * dx + n * dy], n, dx, dy, x[3usize])
    if e != ok { os.exit(5) }
    if str.eq(c.name, "dcov") { ret cov }
    ret cor
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/energy.json")
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
