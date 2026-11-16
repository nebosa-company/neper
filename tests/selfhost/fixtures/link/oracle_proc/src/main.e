// e.algo.stat.proc against pROC. tests/oracle/proc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R proc`; the layout is at the top of scripts/r_oracle/groups/proc.R.

use e.algo.stat.proc as pr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let y = x[1usize..1usize + n]
    let x1 = x[1usize + n..1usize + 2usize * n]
    let x2 = x[1usize + 2usize * n..1usize + 3usize * n]
    let k = c.name
    if str.eq(k, "ncoord") || str.eq(k, "ssens") || str.eq(k, "sspec") || str.eq(k, "sthr") {
        let (cn, ss, sp, st) = pr.roc_sums(a, y, x1)
        if str.eq(k, "ncoord") { ret cn }
        if str.eq(k, "ssens") { ret ss }
        if str.eq(k, "sspec") { ret sp }
        ret st
    }
    if str.eq(k, "atsens") || str.eq(k, "atspec") {
        let (se, sc) = pr.coords_at(y, x1, pr.cases_higher(a, y, x1), x[1usize + 3usize * n])
        if str.eq(k, "atsens") { ret se }
        ret sc
    }
    if str.eq(k, "z") || str.eq(k, "p") {
        let (z, p) = pr.delong_paired(a, y, x1, x2)
        if str.eq(k, "z") { ret z }
        ret p
    }
    let (auc, v) = pr.auc_var(a, y, x1)
    if str.eq(k, "auc") { ret auc }
    if str.eq(k, "var") { ret v }
    let (lo, hi) = pr.ci_delong(auc, v, 0.95f64)
    if str.eq(k, "cilo") { ret lo }
    ret hi
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/proc.json")
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
