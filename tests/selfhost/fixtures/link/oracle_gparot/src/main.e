// e.algo.stat.gparot against GPArotation: GPForth (and GPFoblq once ported) with algorithm "bb".
// tests/oracle/gparot.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gparot`;
// the layout is at the top of scripts/r_oracle/groups/gparot.R.

use e.algo.stat.gparot as gp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var n = x.len
    if str.eq(c.name, "load") || str.eq(c.name, "th") { n = x.len - 1usize }
    let orth = x[0usize] != 0.0f64
    let id = u8(x[1usize])
    let normalize = x[2usize] != 0.0f64
    let p = usize(x[3usize])
    let k = usize(x[4usize])
    let npar = usize(x[5usize])
    let par = x[6usize..6usize + npar]
    let am = x[6usize + npar..6usize + npar + p * k]
    var rot: gp.Rotation = zero
    var e = ok
    if orth {
        let (r, re) = gp.gpf_orth(a, am, p, k, id, par, normalize, 0.00001f64, 2000usize)
        rot = r
        e = re
    } else {
        let (r, re) = gp.gpf_obl(a, am, p, k, id, par, normalize, 0.00001f64, 2000usize)
        rot = r
        e = re
    }
    if e != ok { os.exit(6) }
    if str.eq(c.name, "load") { ret rot.loadings[usize(x[x.len - 1usize])] }
    if str.eq(c.name, "th") { ret rot.th[usize(x[x.len - 1usize])] }
    if str.eq(c.name, "f") { ret rot.f }
    ret f64(rot.iterations)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gparot.json")
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
