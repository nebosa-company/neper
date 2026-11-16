// e.algo.stat.urca2 against urca: ur.pp, ur.ers and ur.za. tests/oracle/urca2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R urca2`; the layouts are at the top of scripts/r_oracle/groups/urca2.R.

use e.algo.stat.urca2 as u
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nan = 0.0f64 / 0.0f64
    let q = usize(x[x.len - 1usize])
    if str.eq(c.name, "pp") {
        let n = usize(x[3usize])
        let (r, e) = u.ur_pp(a, x[4usize..4usize + n], u8(x[0usize]), u8(x[1usize]), i64(x[2usize]))
        if e != ok { ret nan }
        if q == 0usize { ret r.stat }
        if q == 1usize { ret r.cval1 }
        if q == 2usize { ret r.cval5 }
        if q == 3usize { ret r.cval10 }
        ret f64(r.lag)
    }
    if str.eq(c.name, "ers") {
        let n = usize(x[3usize])
        let (r, e) = u.ur_ers(a, x[4usize..4usize + n], u8(x[0usize]), u8(x[1usize]), usize(x[2usize]))
        if e != ok { ret nan }
        if q == 0usize { ret r.stat }
        if q == 1usize { ret r.cval1 }
        if q == 2usize { ret r.cval5 }
        if q == 3usize { ret r.cval10 }
        ret f64(r.lag)
    }
    let n = usize(x[2usize])
    let (r, e) = u.ur_za(a, x[3usize..3usize + n], u8(x[0usize]), usize(x[1usize]))
    if e != ok { ret nan }
    if q == 0usize { ret r.stat }
    if q == 1usize { ret f64(r.bpoint) }
    if q == 2usize { ret r.cval1 }
    if q == 3usize { ret r.cval5 }
    ret r.cval10
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/urca2.json")
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
