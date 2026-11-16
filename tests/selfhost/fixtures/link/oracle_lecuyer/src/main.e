// e.algo.rand.lecuyer against R: the L'Ecuyer-CMRG generator after set.seed, with nextRNGStream and
// nextRNGSubStream jumps. tests/oracle/lecuyer.json comes from `R_ORACLE_LIB=<dir> Rscript
// scripts/r_oracle/generate.R lecuyer`; the layout is at the top of scripts/r_oracle/groups/lecuyer.R.

use e.algo.rand.lecuyer as lc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    var st = lc.set_seed(u32(x[0usize]))
    var k = 0usize
    while k < usize(x[1usize]) {
        st = lc.jump(st, 0u8)
        k += 1usize
    }
    k = 0usize
    while k < usize(x[2usize]) {
        st = lc.jump(st, 1u8)
        k += 1usize
    }
    let at = usize(x[3usize])
    if str.eq(c.name, "state") { ret f64(st.s[at]) }
    var v = 0.0f64
    var i = 0usize
    while i <= at {
        v = lc.unif(&st)
        i += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lecuyer.json")
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
