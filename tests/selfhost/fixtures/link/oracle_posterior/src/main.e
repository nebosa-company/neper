// e.algo.stat.posteriorpkg against posterior. tests/oracle/posterior.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R posterior`; the layout is at the top of scripts/r_oracle/groups/posterior.R.

use e.algo.stat.posteriorpkg as pp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nc = usize(x[0usize])
    let n = usize(x[1usize])
    let d = x[2usize..2usize + nc * n]
    if str.eq(c.name, "rhat") { ret pp.rhat(a, d, nc, n) }
    if str.eq(c.name, "essb") { ret pp.ess_bulk(a, d, nc, n) }
    if str.eq(c.name, "esst") { ret pp.ess_tail(a, d, nc, n) }
    ret pp.mcse_mean(a, d, nc, n)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/posterior.json")
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
