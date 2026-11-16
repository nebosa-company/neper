// e.algo.stat.pwr against pwr: power and solved parameters of pwr.p.test, pwr.2p.test, pwr.2p2n.test and
// pwr.norm.test, the pwr.r.test power and ES.h. tests/oracle/pwr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pwr`; the layout is at the top of
// scripts/r_oracle/groups/pwr.R.

use e.algo.stat.pwr as pw
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "rpow") { ret pw.power_r(x[0usize], x[1usize], x[2usize], u8(x[3usize])) }
    if str.eq(c.name, "esh") { ret pw.es_h(x[0usize], x[1usize]) }
    let unknown = i64(x[2usize])
    var p = pw.Problem { kind: u8(x[0usize]), side: u8(x[1usize]), h: x[3usize], n: x[4usize], n2: x[5usize], sig: x[6usize], power: x[7usize], unknown: 9u8 }
    if unknown < 0i64 { ret pw.power_of(&p) }
    p.unknown = u8(unknown)
    ret pw.solve(&p)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pwr.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
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
