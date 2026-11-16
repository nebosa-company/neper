// e.algo.stat.nortest against nortest and moments: moments, Jarque-Bera, D'Agostino, Anscombe-Glynn,
// Bonett-Seier, Lilliefors, Cramer-von Mises, Shapiro-Francia and Pearson chi-square.
// tests/oracle/nortest.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nortest`;
// the layout is at the top of scripts/r_oracle/groups/nortest.R.

use e.algo.stat.nortest as nt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let data = x[1usize..1usize + n]
    let rest = x[1usize + n..x.len]
    let nm = c.name
    if str.eq(nm, "moment") { ret nt.moment(data, rest[0usize], rest[1usize] != 0.0f64, rest[2usize] != 0.0f64) }
    if str.eq(nm, "skew") { ret nt.skewness(data) }
    if str.eq(nm, "kurt") { ret nt.kurtosis(data) }
    if str.eq(nm, "jb_stat") || str.eq(nm, "jb_p") {
        let (s, p) = nt.jarque_test(data)
        if str.eq(nm, "jb_stat") { ret s }
        ret p
    }
    if str.eq(nm, "lillie_d") || str.eq(nm, "lillie_p") {
        let (d, p, e) = nt.lillie(a, data)
        if e != ok { os.exit(6) }
        if str.eq(nm, "lillie_d") { ret d }
        ret p
    }
    if str.eq(nm, "cvm_w") || str.eq(nm, "cvm_p") {
        let (d, p, e) = nt.cvm(a, data)
        if e != ok { os.exit(6) }
        if str.eq(nm, "cvm_w") { ret d }
        ret p
    }
    if str.eq(nm, "sf_w") || str.eq(nm, "sf_p") {
        let (d, p, e) = nt.sf(a, data)
        if e != ok { os.exit(6) }
        if str.eq(nm, "sf_w") { ret d }
        ret p
    }
    if str.eq(nm, "pearson_stat") || str.eq(nm, "pearson_p") {
        let (d, p, k, e) = nt.pearson(a, data, usize(rest[0usize]), rest[1usize] != 0.0f64)
        if e != ok { os.exit(6) }
        if str.eq(nm, "pearson_stat") { ret d }
        ret p
    }
    let al = u8(rest[0usize])
    if str.eq(nm[0usize..3usize], "ago") {
        let (s, z, p) = nt.agostino(data, al)
        if str.eq(nm, "agostino_skew") { ret s }
        if str.eq(nm, "agostino_z") { ret z }
        ret p
    }
    if str.eq(nm[0usize..3usize], "ans") {
        let (s, z, p) = nt.anscombe(data, al)
        if str.eq(nm, "anscombe_kurt") { ret s }
        if str.eq(nm, "anscombe_z") { ret z }
        ret p
    }
    let (s, z, p) = nt.bonett(data, al)
    if str.eq(nm, "bonett_tau") { ret s }
    if str.eq(nm, "bonett_z") { ret z }
    ret p
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nortest.json")
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
