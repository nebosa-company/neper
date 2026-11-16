// e.algo.stat.proxy against R's proxy: the native value of 42 measures on pairs of vectors.
// tests/oracle/proxy.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R proxy`;
// the layout is at the top of scripts/r_oracle/groups/proxy.R.

use e.algo.stat.proxy as proxy
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
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
        let got = answer(c)
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
