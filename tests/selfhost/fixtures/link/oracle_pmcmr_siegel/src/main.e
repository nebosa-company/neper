// e.algo.stat.pmcmr's Siegel-Castellan all-pairs test against PMCMRplus. tests/oracle/pmcmr_siegel.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_siegel`; the layout is at the top of scripts/r_oracle/groups/pmcmr_siegel.R.

use e.algo.stat.pmcmr as pm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let kind = usize(z[2usize])
    let ii = usize(z[3usize])
    let jj = usize(z[4usize])
    let y = z[5usize..5usize + n * k]
    if kind < 2usize {
        let (st, p, e) = pm.frd_pair(a, n, k, y, 5usize, ii, jj)
        if e != ok { os.exit(4) }
        if kind == 0usize { ret st }
        ret p
    }
    // Holm over every pair, ordered column by column of the lower triangle, as the R matrix is
    let (ps, e0) = mem.alloc[f64](a, k * (k - 1usize) / 2usize)
    if e0 != ok { os.exit(5) }
    var pos = 0usize
    var want = 0usize
    var col = 0usize
    while col < k {
        var row = col + 1usize
        while row < k {
            let (s2, p2, e2) = pm.frd_pair(a, n, k, y, 5usize, row, col)
            if e2 != ok { os.exit(6) }
            ps[pos] = p2
            if row == ii && col == jj { want = pos }
            pos += 1usize
            row += 1usize
        }
        col += 1usize
    }
    if pm.p_adjust(a, ps, 0usize) != ok { os.exit(7) }
    ret ps[want]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_siegel.json")
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
