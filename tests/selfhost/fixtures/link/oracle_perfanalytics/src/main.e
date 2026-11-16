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
    var rb = r
    if x.len >= 3usize + 2usize * n { rb = x[3usize + n..3usize + 2usize * n] }
    if str.eq(k, "beta") { ret pa.capm_beta(r, rb, p1, a) }
    if str.eq(k, "alpha") { ret pa.capm_alpha(r, rb, p1, a) }
    if str.eq(k, "te") { ret pa.tracking_error(r, rb, a, p1) }
    if str.eq(k, "ir") { ret pa.information_ratio(r, rb, a, p1) }
    if str.eq(k, "omega") { ret pa.omega_sharpe(r, p1) }
    if str.eq(k, "updown") {
        let code = usize(p1)
        ret pa.up_down(a, r, rb, code / 10usize, code % 10usize, p2 > 0.5f64)
    }
    if str.eq(k, "fdn") || str.eq(k, "fdr") || str.eq(k, "fdf") || str.eq(k, "fdt") || str.eq(k, "fde") {
        let (dd, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        let (rr, e2) = mem.alloc[f64](a, n + 1usize)
        if e2 != ok { os.exit(6) }
        let (ff, e3) = mem.alloc[f64](a, n + 1usize)
        if e3 != ok { os.exit(7) }
        let (tr, e4) = mem.alloc[f64](a, n + 1usize)
        if e4 != ok { os.exit(8) }
        let (tt, e5) = mem.alloc[f64](a, n + 1usize)
        if e5 != ok { os.exit(9) }
        pa.drawdowns(r, true, dd)
        let cnt = pa.find_drawdowns(dd, rr, ff, tr, tt)
        if str.eq(k, "fdn") { ret f64(cnt) }
        var s = 0.0f64
        var i = 0usize
        while i < cnt {
            if str.eq(k, "fdr") { s += rr[i] * f64(i + 1usize) }
            if str.eq(k, "fdf") { s += ff[i] * f64(i + 1usize) }
            if str.eq(k, "fdt") { s += tr[i] * f64(i + 1usize) }
            if str.eq(k, "fde") { s += tt[i] * f64(i + 1usize) }
            i += 1usize
        }
        ret s
    }
    if str.eq(k, "annual") { ret pa.return_annualized(r, p1, p2 > 0.5f64) }
    if str.eq(k, "maxdd") { ret pa.max_drawdown(r, p2 > 0.5f64) }
    if str.eq(k, "dd") { ret pa.downside_deviation(r, p1, p2 > 0.5f64 && p2 < 1.5f64, p2 > 1.5f64) }
    if str.eq(k, "sortino") { ret pa.sortino(r, p1) }
    if str.eq(k, "calmar") { ret pa.calmar(r, p1) }
    if str.eq(k, "sharpe") { ret pa.sharpe(r, p1) }
    if str.eq(k, "var") { ret pa.var_loss(a, r, p1, usize(p2)) }
    if usize(p2) == 2usize { ret pa.es_modified(r, p1) }
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
