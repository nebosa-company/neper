// e.algo.stat.urca against urca: ur.df (statistics, selected lags, critical values) and ur.kpss.
// tests/oracle/urca.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R urca`;
// the layouts are at the top of scripts/r_oracle/groups/urca.R.

use e.algo.stat.urca as urca
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "kpss") {
        let n = usize(x[2usize])
        let (v, lm, e) = urca.ur_kpss(a, x[3usize..3usize + n], u8(x[0usize]), u8(x[1usize]), 0usize)
        if e != ok { os.exit(6) }
        ret v
    }
    let qtype = u8(x[0usize])
    let n = usize(x[3usize])
    let (r, e) = urca.ur_df(a, x[4usize..4usize + n], qtype, usize(x[1usize]), u8(x[2usize]))
    if e != ok { os.exit(7) }
    if str.eq(c.name, "df_tau") { ret r.tau }
    if str.eq(c.name, "df_phia") { ret r.phi_a }
    if str.eq(c.name, "df_phib") { ret r.phi_b }
    if str.eq(c.name, "df_lags") { ret f64(r.lags) }
    // df_c<level>_<which>
    let level = usize(c.name[4usize] - 48u8)
    let which = usize(c.name[6usize] - 48u8)
    ret urca.df_critical(qtype, which, level, r.n)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/urca.json")
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
