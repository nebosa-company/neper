// e.algo.stat.ks2dsupp against ks (ksupp in two dimensions). tests/oracle/ks2dsupp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ks2dsupp`; the layout is at the top of scripts/r_oracle/groups/ks2dsupp.R.

use e.algo.stat.ks2dsupp as ks
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    var o: [5]f64 = zero
    if ks.ksupp2(a, x[7usize..7usize + 2usize * n], n, x[1usize..5usize], 151usize, x[5usize], o[0usize..5usize]) != ok { os.exit(5) }
    ret o[usize(x[6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ks2dsupp.json")
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
