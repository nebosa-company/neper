// e.algo.stat.sampling's Hajek, ratio, inclusionprobastrata and HTstrata estimators against sampling. tests/oracle/sampling_est.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_est`; the layout is at the top of scripts/r_oracle/groups/sampling_est.R.

use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let npop = x[2usize]
    let tx = x[3usize]
    let ii = usize(x[4usize])
    let y = x[5usize..5usize + n]
    let xv = x[5usize + n..5usize + 2usize * n]
    let pik = x[5usize + 2usize * n..5usize + 3usize * n]
    let strata = x[5usize + 3usize * n..5usize + 4usize * n]
    let nh = x[5usize + 4usize * n..x.len]
    if kind == 0usize { ret sp.hajek_estimator(y, pik, npop, true) }
    if kind == 1usize { ret sp.hajek_estimator(y, pik, npop, false) }
    if kind == 2usize { ret sp.ratio_estimator(y, xv, tx, pik) }
    if kind == 3usize {
        let (pk, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(4) }
        sp.inclusion_strata(strata, nh, pk)
        ret pk[ii]
    }
    ret sp.ht_strata(y, pik, strata)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_est.json")
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
