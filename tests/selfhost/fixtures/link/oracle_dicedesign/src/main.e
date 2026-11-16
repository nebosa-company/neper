// e.algo.stat.dicedesign against DiceDesign. tests/oracle/dicedesign.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dicedesign`; the layout is at the top of scripts/r_oracle/groups/dicedesign.R.

use e.algo.stat.dicedesign as dd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn gen(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    var total = 0.0f64
    if str.eq(c.name, "fact") {
        var lv: [5]usize = zero
        var cnt = 1usize
        var i = 0usize
        while i < d {
            lv[i] = usize(x[4usize + i])
            cnt = cnt * lv[i]
            i += 1usize
        }
        let (o, e) = mem.alloc[f64](a, cnt * d)
        if e != ok { os.exit(5) }
        dd.fact_design(lv[0usize..d], o)
        i = 0usize
        while i < cnt * d {
            total += o[i] * f64(i + 1usize)
            i += 1usize
        }
        ret total
    }
    let (o, e) = mem.alloc[f64](a, n * d)
    if e != ok { os.exit(6) }
    if str.eq(c.name, "lhs") {
        if dd.lhs_design(a, n, d, x[3usize] > 0.5f64, i64(x[2usize]), o) != ok { os.exit(7) }
    } else {
        if dd.faure(a, n, d, o) != ok { os.exit(8) }
    }
    var i = 0usize
    while i < n * d {
        total += o[i] * f64(i + 1usize)
        i += 1usize
    }
    ret total
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "lhs") || str.eq(c.name, "fact") || str.eq(c.name, "faure") { ret gen(a, c) }
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let p = x[2usize]
    let des = x[3usize..3usize + n * d]
    let k = c.name
    if str.eq(k, "C2") { ret dd.discrepancy(des, n, d, 0usize) }
    if str.eq(k, "L2") { ret dd.discrepancy(des, n, d, 1usize) }
    if str.eq(k, "L2star") { ret dd.discrepancy(des, n, d, 2usize) }
    if str.eq(k, "M2") { ret dd.discrepancy(des, n, d, 3usize) }
    if str.eq(k, "S2") { ret dd.discrepancy(des, n, d, 4usize) }
    if str.eq(k, "W2") { ret dd.discrepancy(des, n, d, 5usize) }
    if str.eq(k, "Mix2") { ret dd.discrepancy(des, n, d, 6usize) }
    if str.eq(k, "mindist") { ret dd.mindist(des, n, d) }
    if str.eq(k, "phip") { ret dd.phi_p(des, n, d, p) }
    ret dd.coverage(des, n, d)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dicedesign.json")
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
