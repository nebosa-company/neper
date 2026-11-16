// e.algo.stat.gamlssdist against gamlss.dist. tests/oracle/gamlssdist.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlssdist`; the layout is at the top of scripts/r_oracle/groups/gamlssdist.R.

use e.algo.stat.gamlssdist as gd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "dWEI") { ret gd.dwei(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "dLOGNO") { ret gd.dlogno(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "dNBI") { ret gd.dnbi(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "dZIP") { ret gd.dzip(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "dJSU") { ret gd.djsu(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "dSHASH") { ret gd.dshash(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "dBCT") { ret gd.dbct(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "dGU") { ret gd.dgu(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "dLO") { ret gd.dlo(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "dGA") { ret gd.dga(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "dIG") { ret gd.dig(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "dBCCG") { ret gd.dbccg(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "dPE") { ret gd.dpe(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "pGU") { ret gd.pgu(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "pLO") { ret gd.plo(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "qGU") { ret gd.qgu(x[0usize], x[1usize], x[2usize]) }
    ret gd.qlo(x[0usize], x[1usize], x[2usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlssdist.json")
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
