// e.algo.stat.plmpkg against plm within, between and random (Swamy-Arora). tests/oracle/plm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R plm`; the layout is at the top of scripts/r_oracle/groups/plm.R.

use e.algo.stat.plmpkg as pm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nn = usize(z[0usize])
    let tt = usize(z[1usize])
    let k = usize(z[2usize])
    let n = nn * tt
    let kb = k + 1usize
    let (out, e1) = mem.alloc[f64](a, 3usize * k + 3usize * kb + 3usize)
    if e1 != ok { ret nan }
    if pm.panel(a, z[3usize + n..3usize + n + n * k], z[3usize..3usize + n], nn, tt, k, out) != ok { ret nan }
    var lo = 0usize
    var cnt = 0usize
    var name = c.name
    if str.eq(name, "wcoef") {
        lo = 0usize
        cnt = k
    }
    if str.eq(name, "wse") {
        lo = k
        cnt = k
    }
    if str.eq(name, "s2e") { ret out[2usize * k] }
    if str.eq(name, "bcoef") {
        lo = 2usize * k + 1usize
        cnt = kb
    }
    if str.eq(name, "rcoef") {
        lo = 2usize * k + 1usize + kb
        cnt = kb
    }
    if str.eq(name, "rse") {
        lo = 2usize * k + 1usize + 2usize * kb
        cnt = kb
    }
    if str.eq(name, "s2mu") { ret out[2usize * k + 1usize + 3usize * kb] }
    if str.eq(name, "theta") { ret out[2usize * k + 2usize + 3usize * kb] }
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += out[lo + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/plm.json")
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
