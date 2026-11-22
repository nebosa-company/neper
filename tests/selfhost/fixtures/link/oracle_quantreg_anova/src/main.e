// e.algo.stat.quantreg anova.rq against quantreg. tests/oracle/quantreg_anova.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R quantreg_anova`; the layout is at the top of
// scripts/r_oracle/groups/quantreg_anova.R.

use e.algo.stat.quantreg as qr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let tau = x[2usize]
    let kind = usize(x[3usize]) / 100usize
    let slot = usize(x[3usize]) % 100usize
    let mask = usize(x[4usize])
    let y = x[5usize..5usize + n]
    let (d, de) = mem.alloc[f64](a, n * p)
    let (out, oe) = mem.alloc[f64](a, 4usize * p)
    let (drop, dpe) = mem.alloc[usize](a, p)
    let (taus, te) = mem.alloc[f64](a, 3usize)
    if de != ok || oe != ok || dpe != ok || te != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    var k = 0usize
    while k < (p - 1usize) * n {
        d[n + k] = x[5usize + n + k]
        k += 1usize
    }
    var nd = 0usize
    k = 0usize
    while k < p - 1usize {
        var bit = 1usize
        var s = 0usize
        while s < k {
            bit = bit * 2usize
            s += 1usize
        }
        if (mask / bit) % 2usize == 1usize {
            drop[nd] = k + 1usize
            nd += 1usize
        }
        k += 1usize
    }
    taus[0usize] = 0.25f64
    taus[1usize] = 0.5f64
    taus[2usize] = 0.75f64
    if kind == 0usize {
        if qr.anova_wald(a, d, y, n, p, tau, drop[0usize..nd], out) != ok { ret 0.0f64 / 0.0f64 }
    } else if kind == 1usize {
        if qr.anova_rank(a, d, y, n, p, tau, drop[0usize..nd], true, out) != ok { ret 0.0f64 / 0.0f64 }
    } else if kind == 2usize {
        if qr.anova_rank(a, d, y, n, p, tau, drop[0usize..nd], false, out) != ok { ret 0.0f64 / 0.0f64 }
    } else if kind == 3usize {
        if qr.anova_taus(a, d, y, n, p, taus, true, out) != ok { ret 0.0f64 / 0.0f64 }
    } else {
        if qr.anova_taus(a, d, y, n, p, taus, false, out) != ok { ret 0.0f64 / 0.0f64 }
    }
    ret out[slot]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/quantreg_anova.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
