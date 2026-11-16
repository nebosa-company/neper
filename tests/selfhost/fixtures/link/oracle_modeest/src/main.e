// e.algo.stat.modeest against modeest: venter, shorth, hsm, grenander, meanshift, asselin.
// tests/oracle/modeest.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R modeest`; the
// layout is at the top of scripts/r_oracle/groups/modeest.R.

use e.algo.stat.modeest as me
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let n = usize(z[2usize])
    let x = z[3usize..3usize + n]
    var v = 0.0f64 / 0.0f64
    var e = ok
    if kind <= 3usize {
        let (r, re) = me.venter(a, x, u8(kind + 1usize), 0i64 - 1i64)
        v = r
        e = re
    } else if kind == 4usize {
        let (r, re) = me.hsm(a, x, 0.5f64)
        v = r
        e = re
    } else if kind == 5usize {
        let (r, re) = me.grenander(a, x, z[1usize])
        v = r
        e = re
    } else if kind == 6usize || kind == 8usize {
        let (r, it, re) = me.meanshift(a, x)
        v = r
        if kind == 8usize { v = f64(it) }
        e = re
    } else {
        let (r, re) = me.asselin(a, x)
        v = r
        e = re
    }
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/modeest.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
