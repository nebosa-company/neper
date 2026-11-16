// e.algo.stat.perfanalytics against PerformanceAnalytics. tests/oracle/perfanalytics.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R perfanalytics`; the layout is at the top of scripts/r_oracle/groups/perfanalytics.R.

use e.algo.stat.perfanalytics as pa
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let p1 = x[0usize]
    let p2 = x[1usize]
    let n = usize(x[2usize])
    let r = x[3usize..3usize + n]
    let k = c.name
    if str.eq(k, "annual") { ret pa.return_annualized(r, p1, p2 > 0.5f64) }
    if str.eq(k, "maxdd") { ret pa.max_drawdown(r, p2 > 0.5f64) }
    if str.eq(k, "dd") { ret pa.downside_deviation(r, p1, p2 > 0.5f64 && p2 < 1.5f64, p2 > 1.5f64) }
    if str.eq(k, "sortino") { ret pa.sortino(r, p1) }
    if str.eq(k, "calmar") { ret pa.calmar(r, p1) }
    if str.eq(k, "sharpe") { ret pa.sharpe(r, p1) }
    if str.eq(k, "var") { ret pa.var_loss(a, r, p1, usize(p2)) }
    ret pa.es_loss(a, r, p1, usize(p2))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/perfanalytics.json")
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
