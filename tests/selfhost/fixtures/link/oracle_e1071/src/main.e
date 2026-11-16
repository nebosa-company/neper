// e.algo.stat.e1071 against e1071: skewness and kurtosis (types 1 to 3) and countpattern.
// tests/oracle/e1071.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R e1071`;
// the layouts are at the top of scripts/r_oracle/groups/e1071.R.

use e.algo.stat.e1071 as e1071
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "skew") { ret e1071.skewness(x[2usize..2usize + usize(x[1usize])], u8(x[0usize])) }
    if str.eq(c.name, "kurt") { ret e1071.kurtosis(x[2usize..2usize + usize(x[1usize])], u8(x[0usize])) }
    let nr = usize(x[0usize])
    let nv = usize(x[1usize])
    let (counts, e) = e1071.count_pattern(a, x[3usize..3usize + nr * nv], nr, nv)
    if e != ok { os.exit(6) }
    ret counts[usize(x[2usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/e1071.json")
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
