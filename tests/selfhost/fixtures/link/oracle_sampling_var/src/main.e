// e.algo.stat.sampling's varest and vartaylor_ratio against sampling. tests/oracle/sampling_var.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_var`; the layout is at the top of scripts/r_oracle/groups/sampling_var.R.

use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let which = usize(x[3usize])
    let y = x[4usize..4usize + n]
    if kind == 3usize {
        let pk3 = x[4usize + n..4usize + n + n * n]
        let x3 = x[4usize + n + n * n..4usize + n + n * n + n * p]
        let tx3 = x[4usize + n + n * n + n * p..4usize + n + n * n + n * p + p - 1usize]
        let (w3, e6) = mem.alloc[f64](a, n)
        let (o3, e7) = mem.alloc[f64](a, 2usize * p + 1usize)
        if e6 != ok || e7 != ok { os.exit(7) }
        var t3 = 0usize
        while t3 < n {
            w3[t3] = 1.0f64 / pk3[t3 * n + t3]
            t3 += 1usize
        }
        if sp.regest(a, y, x3, p, w3, pk3, tx3, o3) != ok { os.exit(8) }
        ret o3[which]
    }
    if kind == 2usize {
        let xx = x[4usize + n..4usize + 2usize * n]
        let pk = x[4usize + 2usize * n..4usize + 2usize * n + n * n]
        let (o, e1) = mem.alloc[f64](a, 2usize)
        if e1 != ok { os.exit(4) }
        sp.var_taylor_ratio(y, xx, pk, o)
        ret o[which]
    }
    let pik = x[4usize + n..4usize + 2usize * n]
    if kind == 0usize {
        let (v, e2) = sp.var_est(a, y, y, 0usize, pik, pik)
        if e2 != ok { os.exit(5) }
        ret v
    }
    let xs = x[4usize + 2usize * n..4usize + 2usize * n + n * p]
    let w = x[4usize + 2usize * n + n * p..4usize + 3usize * n + n * p]
    let (v, e3) = sp.var_est(a, y, xs, p, pik, w)
    if e3 != ok { os.exit(6) }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_var.json")
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
