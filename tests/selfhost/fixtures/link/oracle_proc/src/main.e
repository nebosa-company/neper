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
    if str.eq(c.name, "du_z") || str.eq(c.name, "du_p") {
        let m1 = usize(x[0usize])
        let m2 = usize(x[1usize])
        let (dz, dp) = pr.delong_unpaired(a, x[2usize..2usize + m1], x[2usize + m1..2usize + 2usize * m1], x[2usize + 2usize * m1..2usize + 2usize * m1 + m2], x[2usize + 2usize * m1 + m2..2usize + 2usize * m1 + 2usize * m2])
        if str.eq(c.name, "du_z") { ret dz }
        ret dp
    }
    if str.eq(c.name, "mcauc") {
        let kk = usize(x[0usize])
        let nn = usize(x[1usize])
        ret pr.multiclass_auc(a, x[2usize..2usize + nn], x[2usize + nn..2usize + 2usize * nn], kk)
    }
    let n = usize(x[0usize])
    let y = x[1usize..1usize + n]
    let x1 = x[1usize + n..1usize + 2usize * n]
    let x2 = x[1usize + 2usize * n..1usize + 3usize * n]
    let k = c.name
    if str.eq(k, "bcl") || str.eq(k, "bcm") || str.eq(k, "bch") {
        // args (n, y, x1, x2, boot.n, seed, stratified)
        let (bo, boe) = mem.alloc[f64](a, 3usize)
        if boe != ok { ret 0.0f64 / 0.0f64 }
        let be = pr.ci_auc_boot(a, y, x1, usize(x[3usize * n + 1usize]), i64(x[3usize * n + 2usize]), 0.95f64, x[3usize * n + 3usize] > 0.5f64, bo)
        if be != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(k, "bcl") { ret bo[0usize] }
        if str.eq(k, "bcm") { ret bo[1usize] }
        ret bo[2usize]
    }
    if str.eq(k, "btd") || str.eq(k, "btp") {
        let (bo2, bo2e) = mem.alloc[f64](a, 2usize)
        if bo2e != ok { ret 0.0f64 / 0.0f64 }
        if pr.roc_test_boot(a, y, x1, x2, usize(x[3usize * n + 1usize]), i64(x[3usize * n + 2usize]), x[3usize * n + 3usize] > 0.5f64, bo2) != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(k, "btd") { ret bo2[0usize] }
        ret bo2[1usize]
    }
    if str.eq(k, "smi") || str.eq(k, "sms") || str.eq(k, "sma") {
        let (so, soe) = mem.alloc[f64](a, 3usize)
        if soe != ok { ret 0.0f64 / 0.0f64 }
        if pr.smooth_binormal(a, y, x1, 512usize, so) != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(k, "smi") { ret so[0usize] }
        if str.eq(k, "sms") { ret so[1usize] }
        ret so[2usize]
    }
    if str.eq(k, "ncoord") || str.eq(k, "ssens") || str.eq(k, "sspec") || str.eq(k, "sthr") {
        let (cn, ss, sp, st) = pr.roc_sums(a, y, x1)
        if str.eq(k, "ncoord") { ret cn }
        if str.eq(k, "ssens") { ret ss }
        if str.eq(k, "sspec") { ret sp }
        ret st
    }
    if str.eq(k, "bcnt") || str.eq(k, "bthr") || str.eq(k, "bcrit") {
        let (bc, bt, bq) = pr.roc_best(a, y, x1, x[3usize * n + 2usize], x[3usize * n + 3usize], usize(x[3usize * n + 1usize]))
        if str.eq(k, "bcnt") { ret bc }
        if str.eq(k, "bthr") { ret bt }
        ret bq
    }
    if str.eq(k, "pauc") { ret pr.partial_auc(a, y, x1, x[3usize * n + 1usize], x[3usize * n + 2usize], usize(x[3usize * n + 3usize]), x[3usize * n + 4usize] > 0.5f64) }
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
