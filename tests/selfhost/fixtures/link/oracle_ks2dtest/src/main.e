// e.algo.stat.ks2dtest against ks (kde.test, two samples). tests/oracle/ks2dtest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ks2dtest`; the layouts are at the top of scripts/r_oracle/groups/ks2dtest.R.

use e.algo.stat.ks2dtest as ks
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n1 = usize(x[0usize])
    let n2 = usize(x[1usize])
    var o: [8]f64 = zero
    if str.eq(c.name, "kt2d") {
        let s = 3usize
        if ks.kde_test2_default(a, x[s..s + 2usize * n1], n1, x[s + 2usize * n1..s + 2usize * n1 + 2usize * n2], n2, o[0usize..6usize], o[6usize..8usize]) != ok { os.exit(5) }
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "kt1d") {
        ks.kde_test1_default(a, x[3usize..3usize + n1], x[3usize + n1..3usize + n1 + n2], o[0usize..6usize], o[6usize..8usize])
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "kt2") {
        ks.kde_test2(a, x[11usize..11usize + 2usize * n1], n1, x[11usize + 2usize * n1..11usize + 2usize * n1 + 2usize * n2], n2, x[2usize..6usize], x[6usize..10usize], o[0usize..6usize])
        ret o[usize(x[10usize])]
    }
    ks.kde_test1(x[7usize..7usize + n1], x[7usize + n1..7usize + n1 + n2], x[2usize], x[3usize], x[4usize], x[5usize], o[0usize..6usize])
    ret o[usize(x[6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ks2dtest.json")
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
