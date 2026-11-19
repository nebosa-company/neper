// e.algo.stat.sampling's calib (linear, raking) against sampling. tests/oracle/sampling_calib.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_calib`; the layout is at the top of scripts/r_oracle/groups/sampling_calib.R.

use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let method = usize(x[0usize])
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let ii = usize(x[3usize])
    let xs = x[4usize..4usize + n * p]
    let d = x[4usize + n * p..4usize + n * p + n]
    let total = x[4usize + n * p + n..4usize + n * p + n + p]
    let q = x[4usize + n * p + n + p..4usize + n * p + 2usize * n + p]
    let (g, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(4) }
    var it = 0usize
    if method == 2usize {
        let tail = 4usize + n * p + 2usize * n + p
        it = sp.calib_truncated(a, xs, d, total, q, n, p, x[tail], x[tail + 1usize], g)
    } else {
        it = sp.calib(a, xs, d, total, q, n, p, method, g)
    }
    if it == 0usize { ret 0.0f64 / 0.0f64 }
    ret g[ii]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_calib.json")
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
