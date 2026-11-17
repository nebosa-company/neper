// e.algo.stat.sn against sn. tests/oracle/sn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sn`; the layout is at the top of scripts/r_oracle/groups/sn.R.

use e.algo.stat.sn as sn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "rsn") || str.eq(k, "rst") {
        // args (xi, omega, alpha, tau or nu, n, seed, index)
        let rn = usize(x[4usize])
        let (ro, roe) = mem.alloc[f64](a, rn)
        if roe != ok { ret 0.0f64 / 0.0f64 }
        var re = ok
        if str.eq(k, "rsn") { re = sn.rsn(a, rn, x[0usize], x[1usize], x[2usize], x[3usize], i64(x[5usize]), ro) } else { re = sn.rst(a, rn, x[0usize], x[1usize], x[2usize], x[3usize], i64(x[5usize]), ro) }
        if re != ok { ret 0.0f64 / 0.0f64 }
        ret ro[usize(x[6usize])]
    }
    let xi = x[0usize]
    let om = x[1usize]
    let al = x[2usize]
    let t = x[3usize]
    let v = x[4usize]
    if str.eq(k, "dsn") { ret sn.dsn(v, xi, om, al, t) }
    if str.eq(k, "psn") { ret sn.psn_owen(v, xi, om, al) }
    if str.eq(k, "qsn") { ret sn.qsn(v, xi, om, al) }
    ret sn.dst(v, xi, om, al, t)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sn.json")
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
