// e.algo.stat.tsa's detect_ao against TSA::detectAO on ARMA(1, 1) fits. tests/oracle/tsa_detectao.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsa_detectao`; the layout of every case is at the top of scripts/r_oracle/groups/tsa_detectao.R.

use e.algo.stat.tsa as ts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let robust = z[1usize] == 1.0f64
    let resid = z[2usize..2usize + n]
    let phi = z[2usize + n..3usize + n]
    let theta = z[3usize + n..4usize + n]
    let sigma2 = z[4usize + n]
    let which = usize(z[z.len - 1usize])
    let (ind, e1) = mem.alloc[usize](a, n)
    let (lam, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { os.exit(10) }
    var count = 0usize
    if str.eq(c.name, "io") {
        let (cnt, e4) = ts.detect_io(resid, n, sigma2, robust, 0.05f64, ind, lam)
        if e4 != ok { os.exit(12) }
        count = cnt
    } else {
        let (cnt, e3) = ts.detect_ao(a, resid, n, phi, theta, sigma2, robust, 0.05f64, ind, lam)
        if e3 != ok { os.exit(11) }
        count = cnt
    }
    var s = 0.0f64
    var i = 0usize
    while i < count {
        if which == 1usize { s += f64(ind[i]) }
        if which == 2usize { s += lam[i] }
        i += 1usize
    }
    if which == 0usize { ret f64(count) }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsa_detectao.json")
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
