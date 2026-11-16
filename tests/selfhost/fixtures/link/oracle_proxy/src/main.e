// e.algo.stat.proxy against R's proxy: the native value of 42 measures on pairs of vectors.
// tests/oracle/proxy.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R proxy`;
// the layout is at the top of scripts/r_oracle/groups/proxy.R.

use e.algo.stat.proxy as proxy
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "nominal") {
        let n = usize(x[1usize])
        let (v, e) = proxy.nominal(a, u8(x[0usize]), x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n])
        if e != ok { os.exit(6) }
        ret v
    }
    if str.eq(c.name, "mahal") {
        let p = usize(x[0usize])
        let (v, e) = proxy.mahalanobis(a, x[1usize..1usize + p], x[1usize + p..1usize + 2usize * p], x[1usize + 2usize * p..1usize + 2usize * p + p * p])
        if e != ok { os.exit(6) }
        ret v
    }
    let n = usize(x[2usize])
    ret proxy.measure(u8(x[0usize]), x[3usize + n..3usize + 2usize * n], x[3usize..3usize + n], x[1usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/proxy.json")
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
            if failures <= 15usize {
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
