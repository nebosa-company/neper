// e.algo.stat.mass against MASS: mad, huber, hubers, fitdistr (closed-form families), boxcox log-likelihood and
// bandwidth.nrd. tests/oracle/mass.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass`;
// the layout is at the top of scripts/r_oracle/groups/mass.R.

use e.algo.stat.mass as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let y = x[1usize..1usize + n]
    if str.eq(c.name, "mad") { ret ms.mad(a, y) }
    if str.eq(c.name, "bw") { ret ms.bandwidth_nrd(a, y) }
    if str.eq(c.name, "huber_mu") || str.eq(c.name, "huber_s") {
        let (mu, s) = ms.huber(a, y, x[1usize + n], 1.0e-6f64)
        if str.eq(c.name, "huber_mu") { ret mu }
        ret s
    }
    if str.eq(c.name, "hubers_mu") || str.eq(c.name, "hubers_s") {
        let (mu, s) = ms.hubers(a, y, x[1usize + n], 1.0e-6f64)
        if str.eq(c.name, "hubers_mu") { ret mu }
        ret s
    }
    if str.eq(c.name, "fd") {
        let (e1, e2, s1, s2, ll, fe) = ms.fitdistr(a, y, u8(x[1usize + n]))
        if fe != ok { ret 0.0f64 / 0.0f64 }
        let q = u8(x[2usize + n])
        if q == 0u8 { ret e1 }
        if q == 1u8 { ret e2 }
        if q == 2u8 { ret s1 }
        if q == 3u8 { ret s2 }
        ret ll
    }
    let cv = x[1usize + n..1usize + 2usize * n]
    let (d, de) = mem.alloc[f64](a, 2usize * n)
    if de != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        d[n + i] = cv[i]
        i += 1usize
    }
    let (ll, le) = ms.boxcox_loglik(a, y, d, 2usize, x[1usize + 2usize * n])
    if le != ok { ret 0.0f64 / 0.0f64 }
    ret ll
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass.json")
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
