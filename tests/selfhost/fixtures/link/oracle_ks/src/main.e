// e.algo.stat.ks against ks. tests/oracle/ks.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ks`; the layout is at the top of scripts/r_oracle/groups/ks.R.

use e.algo.stat.ks as ks
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    let n = usize(x[0usize])
    if str.eq(k, "hns") { ret ks.hns(x[2usize..2usize + n], usize(x[1usize])) }
    let d = usize(x[1usize])
    if str.eq(k, "Hns") {
        let (o, e) = mem.alloc[f64](a, d * d)
        if e != ok { os.exit(5) }
        ks.hns_matrix(x[5usize..5usize + n * d], n, d, usize(x[2usize]), o)
        ret o[usize(x[3usize]) * d + usize(x[4usize])]
    }
    ret ks.kde_at(a, x[2usize + d * d + d..2usize + d * d + d + n * d], n, d, x[2usize..2usize + d * d], x[2usize + d * d..2usize + d * d + d])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ks.json")
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
