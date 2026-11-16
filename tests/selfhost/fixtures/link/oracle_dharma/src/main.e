// e.algo.stat.dharma against DHARMa. tests/oracle/dharma.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dharma`; the layout is at the top of scripts/r_oracle/groups/dharma.R.

use e.algo.stat.dharma as dh
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let ns = usize(x[1usize])
    let seed = i64(x[2usize])
    let obs = x[3usize..3usize + n]
    let sims = x[3usize + n..3usize + n + n * ns]
    let k = c.name
    if str.eq(k, "zi_ratio") || str.eq(k, "zi_p") || str.eq(k, "disp_ratio") || str.eq(k, "disp_p") {
        let alt = usize(x[3usize + n + n * ns + n])
        var kind = 0usize
        if x[3usize] < 0.0f64 { kind = 0usize }
        if str.eq(k, "disp_ratio") || str.eq(k, "disp_p") { kind = 1usize }
        let (ratio, p) = dh.test_generic(a, sims, obs, x[3usize + n + n * ns..3usize + n + n * ns + n], ns, kind, alt)
        if str.eq(k, "zi_ratio") || str.eq(k, "disp_ratio") { ret ratio }
        ret p
    }
    let (r, e) = mem.alloc[f64](a, n)
    if e != ok { os.exit(5) }
    if dh.pit(a, sims, obs, ns, seed, r) != ok { os.exit(6) }
    if str.eq(k, "res") {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += r[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(k, "ks") { ret dh.ks_uniform(a, r) }
    if str.eq(k, "ksp") { ret dh.ks_pvalue(a, r) }
    let cnt = dh.outlier_count(r, ns)
    if str.eq(k, "nout") { ret f64(cnt) }
    ret dh.binom_test_p(cnt, n, 2.0f64 / f64(ns + 1usize))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dharma.json")
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
