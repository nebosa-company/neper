// e.algo.stat.ksndtest against ks (kde.test in 3 and 4 dimensions, rkde in 3 and 4). tests/oracle/ksndtest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ksndtest`; the layouts are at the top of scripts/r_oracle/groups/ksndtest.R.

use e.algo.stat.ksndtest as ks
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "ktn") {
        let d = usize(x[0usize])
        let n1 = usize(x[1usize])
        let n2 = usize(x[2usize])
        let dd = d * d
        let h1 = 3usize
        let h2 = h1 + dd
        let at = h2 + dd
        var v1 = x[at]
        var v2 = x[at + 1usize]
        if v1 < 0.0f64 {
            v1 = 0.0f64 / 0.0f64
            v2 = v1
        }
        let which = usize(x[at + 2usize])
        let p1 = at + 3usize
        let p2 = p1 + n1 * d
        var o: [6]f64 = zero
        ks.kde_test_nd(a, x[p1..p1 + n1 * d], n1, x[p2..p2 + n2 * d], n2, d, x[h1..h1 + dd], x[h2..h2 + dd], v1, v2, o[0usize..6usize])
        ret o[which]
    }
    let n = usize(x[1usize])
    let d = usize(x[2usize])
    let size = usize(x[3usize + d * d])
    let pos = usize(x[4usize + d * d])
    let (out, oe) = mem.alloc[f64](a, size * d)
    if oe != ok { os.exit(4) }
    let xs = 5usize + d * d
    if ks.rkde_nd(a, i64(x[0usize]), x[xs..xs + n * d], n, d, x[3usize..3usize + d * d], size, out) != ok { os.exit(5) }
    ret out[pos]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ksndtest.json")
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
