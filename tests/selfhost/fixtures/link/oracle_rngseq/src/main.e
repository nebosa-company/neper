// e.algo.rand.lecuyer.rngseq_start against rngtools::RNGseq. tests/oracle/rngseq.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rngseq`; the layout is at the top of
// scripts/r_oracle/groups/rngseq.R.

use e.algo.rand.lecuyer as lc
use e.algo.rand.r as rr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    var st: lc.State = zero
    var i = 0usize
    var k = 0usize
    if str.eq(c.name, "seq") {
        var g: rr.Rng = zero
        rr.seed(&g, i64(x[0usize]))
        st = lc.rngseq_start(rr.unif(&g))
        i = usize(x[1usize])
        k = usize(x[2usize])
    } else if str.eq(c.name, "seqc") {
        st = lc.set_seed(u32(x[0usize]))
        i = usize(x[1usize])
        k = usize(x[2usize])
    } else {
        var j = 0usize
        while j < 6usize {
            // the integers are signed 32-bit words; the state holds them unsigned
            var v = x[j]
            if v < 0.0f64 { v += 4294967296.0f64 }
            st.s[j] = u64(v)
            j += 1usize
        }
        i = usize(x[6usize])
        k = usize(x[7usize])
    }
    var n = 0usize
    while n < i {
        st = lc.jump(st, 0u8)
        n += 1usize
    }
    ret f64(st.s[k])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rngseq.json")
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
