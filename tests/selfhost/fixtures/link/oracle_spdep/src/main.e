// e.algo.stat.spdeppkg against spdep moran.test and geary.test. tests/oracle/spdep.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spdep`; the layout is at the top of scripts/r_oracle/groups/spdep.R.

use e.algo.stat.spdeppkg as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (out, e1) = mem.alloc[f64](a, 8usize)
    if e1 != ok { ret nan }
    sp.autocorr(z[1usize..1usize + n], z[1usize + n..1usize + n + n * n], n, out)
    if str.eq(c.name, "I") { ret out[0usize] }
    if str.eq(c.name, "EI") { ret out[1usize] }
    if str.eq(c.name, "varN") { ret out[2usize] }
    if str.eq(c.name, "varR") { ret out[3usize] }
    if str.eq(c.name, "C") { ret out[4usize] }
    if str.eq(c.name, "varNg") { ret out[6usize] }
    ret out[7usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spdep.json")
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
