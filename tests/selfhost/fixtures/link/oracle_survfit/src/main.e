// e.algo.stat.survfitpkg against survival::survfit. tests/oracle/survfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R survfit`; the layout is at the top of scripts/r_oracle/groups/survfit.R.

use e.algo.stat.survfitpkg as sf
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[2usize])
    let t = x[3usize..3usize + n]
    let e = x[3usize + n..3usize + 2usize * n]
    let (o, oe) = mem.alloc[f64](a, (n + 1usize) * 7usize)
    if oe != ok { os.exit(4) }
    var rows = 0usize
    if usize(x[1usize]) >= 10usize {
        rows = sf.na_table(t, e, x[0usize], usize(x[1usize]) == 11usize, o, n)
    } else {
        rows = sf.km_table(a, t, e, x[0usize], usize(x[1usize]), o, n)
    }
    let row = usize(x[3usize + 2usize * n])
    let col = usize(x[4usize + 2usize * n])
    if row >= rows { ret 0.0f64 - 1.0f64 }
    ret o[row * 7usize + col]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/survfit.json")
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
