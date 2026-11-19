// e.algo.stat.robustbase against robustbase. tests/oracle/robustbase.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R robustbase`; the layout is at the top of scripts/r_oracle/groups/robustbase.R.

use e.algo.stat.robustbase as rb
use e.io
use e.algo.rand.r as rng
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "adj") {
        let an = usize(x[2usize])
        let ap = usize(x[3usize])
        let (ao, ae) = mem.alloc[f64](a, an)
        if ae != ok { os.exit(5) }
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        if rb.adj_outlyingness(a, &g, x[4usize..4usize + an * ap], an, ap, usize(x[1usize]), ao) != ok { os.exit(6) }
        ret ao[usize(x[4usize + an * ap])]
    }
    let n = usize(x[0usize])
    let v = x[1usize..1usize + n]
    if str.eq(k, "qn") { ret rb.qn(a, v) }
    if str.eq(k, "sn") { ret rb.sn(a, v) }
    if str.eq(k, "mc") { ret rb.mc(a, v) }
    if str.eq(k, "ab") {
        var ov: [12]f64 = zero
        rb.adjbox_stats(a, v, 1.5f64, 0.0f64 - 4.0f64, 3.0f64, ov[0usize..12usize])
        ret ov[usize(x[1usize + n])]
    }
    if str.eq(k, "tmu") || str.eq(k, "tsd") {
        let (tm, ts) = rb.scale_tau2(a, v, 4.5f64, 3.0f64)
        if str.eq(k, "tmu") { ret tm }
        ret ts
    }
    let (mu, sc, it) = rb.huber_m(a, v, 1.5f64, 1.0e-6f64)
    if str.eq(k, "hmu") { ret mu }
    if str.eq(k, "hs") { ret sc }
    ret f64(it)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/robustbase.json")
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
