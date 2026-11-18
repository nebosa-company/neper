// e.algo.stat.wrs2's t2way against WRS2::t2way (tr = 0.2). tests/oracle/wrs2_t2way.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R wrs2_t2way`; the layout of every case is at the top of scripts/r_oracle/groups/wrs2_t2way.R.

use e.algo.stat.wrs2 as wr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let jn = usize(z[0usize])
    let kn = usize(z[1usize])
    let p = jn * kn
    let which = usize(z[z.len - 1usize])
    let (sizes, e0) = mem.alloc[usize](a, p)
    if e0 != ok { os.exit(10) }
    var g = 0usize
    while g < p {
        sizes[g] = usize(z[2usize + g])
        g += 1usize
    }
    let data = z[2usize + p..z.len - 1usize]
    let (r, e) = wr.t2way(a, data, sizes, jn, kn, 0.2f64)
    if e != ok { os.exit(11) }
    if which == 0usize { ret r.qa }
    if which == 1usize { ret r.pa }
    if which == 2usize { ret r.qb }
    if which == 3usize { ret r.pb }
    if which == 4usize { ret r.qab }
    ret r.pab
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/wrs2_t2way.json")
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
