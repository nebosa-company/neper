// e.algo.stat.lmom against lmom: samlmu, lmr, qua and pel. tests/oracle/lmom.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lmom`; the layout is at the top of
// scripts/r_oracle/groups/lmom.R.

use e.algo.stat.lmom as lm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "sam") {
        let nmom = usize(z[0usize])
        let n = usize(z[1usize])
        let (out, e) = mem.alloc[f64](a, 5usize)
        if e != ok { ret nan }
        if lm.samlmu(a, z[2usize..2usize + n], nmom, true, out) != ok { ret nan }
        ret out[usize(z[2usize + n])]
    }
    let kind = u8(z[0usize])
    var o: [4]f64 = zero
    if str.eq(c.name, "lmr") {
        lm.lmr(kind, z[1usize], z[2usize], z[3usize], o[0usize..4usize])
        ret o[usize(z[4usize])]
    }
    if str.eq(c.name, "qua") { ret lm.qua(kind, z[4usize], z[1usize], z[2usize], z[3usize]) }
    lm.pel(kind, z[1usize], z[2usize], z[3usize], o[0usize..3usize])
    ret o[usize(z[4usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lmom.json")
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
