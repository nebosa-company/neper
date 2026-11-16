// e.algo.stat.parzen against modeest::parzen. tests/oracle/parzen.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R parzen`; the layout is at the top of scripts/r_oracle/groups/parzen.R.

use e.algo.stat.parzen as pz
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/parzen.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[1usize])
        var got = pz.parzen(a, x[2usize..2usize + n], x[0usize])
        if c.name.len == 5usize { got = pz.naive(a, x[2usize..2usize + n], x[0usize], usize(x[2usize + n])) }
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
