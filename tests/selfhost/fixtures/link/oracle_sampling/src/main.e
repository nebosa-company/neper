// e.algo.stat.sampling against sampling. tests/oracle/sampling.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling`; the layout is at the top of scripts/r_oracle/groups/sampling.R.

use e.algo.rand.r as rr
use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n_total = usize(x[1usize])
    let n = usize(x[2usize])
    let seed = i64(x[3usize])
    let av = x[4usize..4usize + n_total]
    let (pik, e1) = mem.alloc[f64](a, n_total)
    if e1 != ok { os.exit(5) }
    let (s, e2) = mem.alloc[f64](a, n_total)
    if e2 != ok { os.exit(6) }
    sp.inclusion(av, f64(n), pik)
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    var ok_run = ok
    if kind == 1usize { ok_run = sp.up_systematic(a, &g, pik, s) }
    if kind == 2usize { sp.up_poisson(&g, pik, s) }
    if kind == 3usize { ok_run = sp.srswor(a, &g, n, n_total, s) }
    if kind == 4usize { ok_run = sp.up_random_systematic(a, &g, pik, s) }
    if kind == 5usize { ok_run = sp.up_tille(a, &g, pik, s) }
    if ok_run != ok { os.exit(7) }
    if kind == 6usize { ret sp.ht_estimator(av, pik) }
    var t = 0.0f64
    var i = 0usize
    while i < n_total {
        if kind == 0usize { t += pik[i] * f64(i + 1usize) } else { t += s[i] * f64(i + 1usize) }
        i += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling.json")
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
