// e.algo.stat.ashr against ashr: ash fits with a normal likelihood. tests/oracle/ashr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ashr`; the layout is at the top of scripts/r_oracle/groups/ashr.R.

use e.algo.stat.ashr as ashr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let kind = i64(z[1usize])
    let x = z[7usize..7usize + n]
    let s = z[7usize + n..7usize + 2usize * n]
    let f = usize(z[7usize + 2usize * n])
    let i = usize(z[8usize + 2usize * n])
    let (r, e) = ashr.ash(a, x, s, kind, z[2usize] > 0.5f64, z[3usize] > 0.5f64, z[4usize], z[5usize], z[6usize])
    if e != ok { ret nan }
    if f == 0usize { ret r.loglik }
    if f == 1usize { ret r.loglr }
    if f == 2usize { ret r.np[i] }
    if f == 3usize { ret r.pp[i] }
    if f == 4usize { ret r.lfsr[i] }
    if f == 5usize { ret r.svalue[i] }
    if f == 6usize { ret r.lfdr[i] }
    if f == 7usize { ret r.qvalue[i] }
    if f == 8usize { ret r.pm[i] }
    if f == 9usize { ret r.psd[i] }
    if f == 10usize { ret f64(r.k) }
    if i >= r.k { ret nan }
    if f == 11usize { ret r.pi[i] }
    if kind == 2i64 {
        if f == 12usize { ret r.sd[i] }
        ret 0.0f64
    }
    if f == 12usize { ret r.lo[i] }
    ret r.hi[i]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ashr.json")
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
