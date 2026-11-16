// e.algo.stat.normem against norm: em.norm and loglik.norm. tests/oracle/norm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R norm`; the layout is at the top of
// scripts/r_oracle/groups/norm.R.

use e.algo.stat.normem as nm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let x = z[3usize..3usize + n * p]
    let q = usize(z[3usize + n * p])
    let (mu, e1) = mem.alloc[f64](a, p)
    let (sg, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    let (it, e) = nm.em_norm(a, x, n, p, z[2usize], 1000usize, mu, sg)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if q < p { ret mu[q] }
    if q < p + p * p { ret sg[q - p] }
    let (ll, le) = nm.loglik_norm(a, x, n, p, mu, sg)
    if le != ok { ret 0.0f64 / 0.0f64 }
    ret ll
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/norm.json")
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
