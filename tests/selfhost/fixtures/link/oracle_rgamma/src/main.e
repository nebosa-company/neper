// e.algo.rand.r's rgamma and rchisq against R's streams. tests/oracle/rgamma.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rgamma`; the layout is at the top of scripts/r_oracle/groups/rgamma.R.

use e.algo.rand.r as rr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[3usize]))
    let m = usize(z[4usize])
    var s = 0.0f64
    var i = 0usize
    while i < m {
        var v = 0.0f64
        if usize(z[0usize]) == 0usize { v = rr.rgamma(&g, z[1usize], z[2usize]) } else { v = rr.rchisq(&g, z[1usize]) }
        s += v * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rgamma.json")
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
