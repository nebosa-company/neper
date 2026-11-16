// e.algo.stat.metaforbias against metafor. tests/oracle/metaforbias.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R metaforbias`; the layout is at the top of scripts/r_oracle/groups/metaforbias.R.

use e.algo.stat.metaforbias as mb
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/metaforbias.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        if str.eq(c.name, "l1o") {
            let lk = usize(x[3usize])
            let g2 = mb.leave1out(a, x[4usize..4usize + lk], x[4usize + lk..4usize + 2usize * lk], usize(x[0usize]), usize(x[1usize]), usize(x[2usize]))
            if !oracle.agrees(g2, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g2))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        let k = usize(x[2usize])
        let y = x[3usize..3usize + k]
        let v = x[3usize + k..3usize + 2usize * k]
        let m = k * (k - 1usize) / 2usize + 1usize
        let (counts, e1) = mem.alloc[f64](a, m)
        if e1 != ok { os.exit(5) }
        let (next, e2) = mem.alloc[f64](a, m)
        if e2 != ok { os.exit(6) }
        var got = 0.0f64
        let test = usize(x[0usize])
        let what = usize(x[1usize])
        if test == 0usize { got = mb.regtest(y, v, what) }
        if test == 1usize { got = mb.ranktest(y, v, what, counts, next) }
        if test == 2usize { got = mb.fsn_rosenthal(y, v) }
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
