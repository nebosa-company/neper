// e.algo.stat.loopkg against loo. tests/oracle/loo.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R loo`; the layout is at the top of scripts/r_oracle/groups/loo.R.

use e.algo.stat.loopkg as lp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let s = usize(x[0usize])
    let n = usize(x[1usize])
    let ll = x[2usize..2usize + s * n]
    let (o, e) = mem.alloc[f64](a, 4usize)
    if e != ok { os.exit(5) }
    if str.eq(c.name, "waic_elpd") || str.eq(c.name, "waic_p") {
        lp.waic_totals(ll, s, n, o)
        if str.eq(c.name, "waic_elpd") { ret o[0usize] }
        ret o[1usize]
    }
    if lp.loo_totals(a, ll, s, n, o) != ok { os.exit(6) }
    if str.eq(c.name, "loo_elpd") { ret o[0usize] }
    if str.eq(c.name, "loo_p") { ret o[1usize] }
    ret o[3usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/loo.json")
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
