// e.algo.stat.bnlearnpkg against bnlearn score. tests/oracle/bnlearn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bnlearn`; the layout is at the top of scripts/r_oracle/groups/bnlearn.R.

use e.algo.stat.bnlearnpkg as bn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let v = usize(z[1usize])
    let kind = usize(z[2usize])
    let iss = z[3usize]
    let (nlev, e1) = mem.alloc[usize](a, v)
    let (out, e2) = mem.alloc[f64](a, 5usize)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < v {
        nlev[i] = usize(z[4usize + i])
        i += 1usize
    }
    let adj = z[4usize + v..4usize + v + v * v]
    let data = z[4usize + v + v * v..4usize + v + v * v + n * v]
    if kind == 0usize {
        if bn.discrete(a, data, n, v, nlev, adj, iss, out) != ok { ret nan }
        if str.eq(c.name, "loglik") { ret out[0usize] }
        if str.eq(c.name, "aic") { ret out[1usize] }
        if str.eq(c.name, "bic") { ret out[2usize] }
        if str.eq(c.name, "bde") { ret out[3usize] }
        ret out[4usize]
    }
    if bn.gaussian(a, data, n, v, adj, out) != ok { ret nan }
    if str.eq(c.name, "loglik-g") { ret out[0usize] }
    if str.eq(c.name, "aic-g") { ret out[1usize] }
    ret out[2usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bnlearn.json")
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
