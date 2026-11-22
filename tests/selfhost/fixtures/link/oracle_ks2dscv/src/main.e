// e.algo.stat.ks2dscv against ks (Hscv in two dimensions). tests/oracle/ks2dscv.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ks2dscv`; the layout is at the top of scripts/r_oracle/groups/ks2dscv.R.

use e.algo.stat.ks2d as k2
use e.algo.stat.ks2dscv as ks
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    var h: [4]f64 = zero
    let at = usize(x[2usize]) * 2usize + usize(x[3usize])
    if str.eq(c.name, "Hpib") {
        if k2.hpi2b(a, x[4usize..4usize + 2usize * n], n, usize(x[1usize]), true, h[0usize..4usize]) != ok { ret 0.0f64 / 0.0f64 }
        ret h[at]
    }
    if ks.hscv2(a, x[4usize..4usize + 2usize * n], n, usize(x[1usize]), h[0usize..4usize]) != ok { ret 0.0f64 / 0.0f64 }
    ret h[at]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ks2dscv.json")
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
