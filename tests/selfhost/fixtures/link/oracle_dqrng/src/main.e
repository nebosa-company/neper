// e.algo.rand.dqrng against dqrng: dqrunif of the xoroshiro128 and xoshiro256 generators after
// dqset.seed. tests/oracle/dqrng.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// dqrng`; the layout is at the top of scripts/r_oracle/groups/dqrng.R.

use e.algo.rand.dqrng as dq
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    var g = dq.seed(u8(x[0usize]), u64(x[1usize]))
    let n = usize(x[4usize])
    var v = 0.0f64
    var i = 0usize
    while i <= n {
        v = dq.unif(&g, x[2usize], x[3usize])
        i += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dqrng.json")
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
