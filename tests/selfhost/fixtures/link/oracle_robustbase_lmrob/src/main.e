// e.algo.stat.robustbase_lmrob (lmrob, methods MM and SMDM) against robustbase. tests/oracle/robustbase_lmrob.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R robustbase_lmrob`; the layout is at the top of scripts/r_oracle/groups/robustbase_lmrob.R.

use e.algo.stat.robustbase_lmrob as lm
use e.io
use e.algo.rand.r as rng
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[1usize])
    let pp = usize(x[2usize])
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[0usize]))
    let icpt = x[3usize] != 0.0f64
    var p = pp
    var off = 0usize
    if icpt {
        p = pp + 1usize
        off = 1usize
    }
    let (xc, xe) = mem.alloc[f64](a, n * p)
    let (o, oe) = mem.alloc[f64](a, 2usize * p + 8usize + 3usize * n + p)
    if xe != ok || oe != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        if icpt { xc[i] = 1.0f64 }
        var j = 0usize
        while j < pp {
            xc[(j + off) * n + i] = x[6usize + i * pp + j]
            j += 1usize
        }
        i += 1usize
    }
    let y = x[6usize + n * pp..6usize + n * pp + n]
    if lm.lmrob_fit(a, &g, xc, y, n, p, usize(x[4usize]), x[5usize] != 0.0f64, o) != ok { os.exit(6) }
    ret o[usize(x[6usize + n * pp + n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/robustbase_lmrob.json")
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
